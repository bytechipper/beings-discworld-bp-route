-- Mallard 0.27.0 loads sibling modules without caching. Share one instance
-- per VM so panel callbacks, commands, and lifecycle handlers see the same state.
local host_require = require
local modules = {}
require = function(name)
    if modules[name] == nil then modules[name] = host_require(name) end
    return modules[name]
end

local NpcTracker = require("npc_tracker")
local RouteEngine = require("route_engine")
local RouteDisplay = require("route_display")
local Database = require("database")

NpcTracker.init()
RouteEngine.init()

local import_mode = false
local import_lines = {}

local function build_death_pattern()
    return "^(.+) (?:deals the death blow to|kills) (?:the |a |an )?(.+?)\\.$"
end

local function handle_death(npc_name)
    local room_id = RouteEngine.get_last_room_id()
    local room_name = RouteEngine.get_last_room_name()

    if not room_id then
        mud.note("[bproute] No room data - move around first.", { fg = "yellow" })
        return
    end

    local npc_type = NpcTracker.record_kill(npc_name, room_id, room_name)
    if npc_type then
        mud.note(string.format("[bproute] %s killed in %s", npc_type, room_name or room_id), { fg = "green" })
    end
end

mud.trigger("^(.+) deals the death blow to (.+)\\.$", function(m)
    handle_death(m[2])
end, { name = "bproute_death_other", priority = 50 })

mud.trigger("^You kill (.+)\\.$", function(m)
    handle_death(m[1])
end, { name = "bproute_death_self", priority = 50 })

mud.trigger("^(.+) dies\\.$", function(m)
    handle_death(m[1])
end, { name = "bproute_death_generic", priority = 50, flags = "i" })

local DIRECTION_TRIGGERS = {
    { pattern = "^You go north\\.$",           dir = "n" },
    { pattern = "^You go south\\.$",           dir = "s" },
    { pattern = "^You go east\\.$",            dir = "e" },
    { pattern = "^You go west\\.$",            dir = "w" },
    { pattern = "^You go northeast\\.$",       dir = "ne" },
    { pattern = "^You go northwest\\.$",       dir = "nw" },
    { pattern = "^You go southeast\\.$",       dir = "se" },
    { pattern = "^You go southwest\\.$",       dir = "sw" },
    { pattern = "^You go up\\.$",              dir = "u" },
    { pattern = "^You go down\\.$",            dir = "d" },
    { pattern = "^You go (?:out|leave)\\.$",   dir = "out" },
    { pattern = "^You go (?:in|enter)\\.$",    dir = "in" },
    { pattern = "^North\\.$",                  dir = "n" },
    { pattern = "^South\\.$",                  dir = "s" },
    { pattern = "^East\\.$",                   dir = "e" },
    { pattern = "^West\\.$",                   dir = "w" },
    { pattern = "^Northeast\\.$",              dir = "ne" },
    { pattern = "^Northwest\\.$",              dir = "nw" },
    { pattern = "^Southeast\\.$",              dir = "se" },
    { pattern = "^Southwest\\.$",              dir = "sw" },
    { pattern = "^Up\\.$",                     dir = "u" },
    { pattern = "^Down\\.$",                   dir = "d" },
}

for _, trig in ipairs(DIRECTION_TRIGGERS) do
    mud.trigger(trig.pattern, function(_)
        RouteEngine.set_pending_direction(trig.dir)
    end, { name = "bproute_dir_" .. trig.dir, priority = 100 })
end

mud.trigger("^(.+)$", function(m)
    if not import_mode then return end
    local line = m[1]
    if line == "===" then
        import_mode = false
        local json_str = table.concat(import_lines, "\n")
        local parsed = Database.import_json(json_str)
        if parsed then
            NpcTracker.reload()
            RouteEngine.reload()
            mud.note("[bproute] Data imported successfully.", { fg = "green" })
        else
            mud.note("[bproute] Import failed: invalid JSON data.", { fg = "red" })
        end
        return
    end
    table.insert(import_lines, line)
    mud.note("[bproute] Line " .. #import_lines .. " captured.", { fg = "white" })
end, { name = "bproute_import_capture", priority = 200 })

gmcp.on("Room.Info", function(pkg, data)
    if data.identifier then
        RouteEngine.set_current_room(data.identifier, data.name)
    end
end)

mud.command("bp", function(m)
    local args = m.args or ""
    if args == "help" then
        mud.note("[bproute] Being's Discworld BP Route help:", { fg = "cyan", bold = true })
        mud.note("  /bp          - Show route suggestion")
        mud.note("  /bp room     - Show all room kill counts")
        mud.note("  /bp route    - Recalculate and show route")
        mud.note("  /bp status   - Show tracking status")
        mud.note("  /bp export   - Export all data as JSON")
        mud.note("  /bp import   - Import data (paste JSON, end with ===)")
        mud.note("  /bp reset    - Clear all tracking data")
        mud.note("  /bp save     - Force save to database")
        return
    end

    if args == "room" then
        RouteDisplay.show_room_counts()
    elseif args == "route" then
        RouteDisplay.show_route()
    elseif args == "status" then
        RouteDisplay.show_status()
    elseif args == "export" then
        local data = Database.export()
        local json = Database.encode_json(data)
        mud.note("[bproute] === Export (copy everything below) ===", { fg = "cyan", bold = true })
        mud.note(json, { fg = "white" })
        mud.note("[bproute] === End export ===", { fg = "cyan", bold = true })
    elseif args == "import" then
        import_mode = true
        import_lines = {}
        mud.note("[bproute] Import mode - paste your JSON data now.", { fg = "yellow", bold = true })
        mud.note("[bproute] Type === on its own line when done.", { fg = "yellow" })
    elseif args == "reset" then
        NpcTracker.reset()
        RouteEngine.reset()
        mud.note("[bproute] All data cleared.", { fg = "green" })
    elseif args == "save" then
        NpcTracker.force_save()
        RouteEngine.force_save()
        mud.note("[bproute] Data saved to database.", { fg = "green" })
    else
        RouteDisplay.show_route()
    end
end, { description = "Being's Discworld BP Route - show suggested farming route", usage = "/bp [room|route|status|export|import|reset|save|help]" })

world.on("disconnect", function()
    NpcTracker.force_save()
    RouteEngine.force_save()
end)
