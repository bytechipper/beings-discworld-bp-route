local NpcTracker = require("npc_tracker")
local RouteEngine = require("route_engine")

local RouteDisplay = {}

local DIR_LABELS = {
    n = "north", s = "south",
    e = "east", w = "west",
    ne = "northeast", nw = "northwest",
    se = "southeast", sw = "southwest",
    u = "up", d = "down",
    x = "explore",
}

local function format_path(path)
    if not path or #path == 0 then return "stay" end
    local labels = {}
    for _, dir in ipairs(path) do
        table.insert(labels, DIR_LABELS[dir] or dir)
    end
    if #labels == 1 then
        return labels[1]
    else
        return table.concat(labels, ", then ")
    end
end

local function format_types(types)
    if not types or #types == 0 then return "none" end
    local parts = {}
    for _, t in ipairs(types) do
        table.insert(parts, t.count .. " " .. t.npc_type)
    end
    return table.concat(parts, ", ")
end

function RouteDisplay.show_room_counts()
    local rooms = NpcTracker.get_all_rooms()
    local room_list = {}
    for room_id, room in pairs(rooms) do
        table.insert(room_list, {
            id = room_id,
            name = room.name or "unknown",
            total = room.total or 0,
        })
    end
    table.sort(room_list, function(a, b) return a.total > b.total end)

    mud.note(".:: BP NPC Kill Counts ::.", { bold = true })

    if #room_list == 0 then
        mud.note("  No kills recorded yet.", { fg = "white" })
        return
    end

    for _, room in ipairs(room_list) do
        local types = NpcTracker.get_type_counts(room.id)
        mud.note(string.format("  %d kills  %s [%s]",
            room.total, room.name, format_types(types)), { fg = "white" })
    end

    mud.note(string.format("\n  Total: %d kills across %d rooms",
        NpcTracker.get_total_kills(), #room_list), { fg = "cyan" })
end

function RouteDisplay.show_route(min_kills)
    min_kills = min_kills or 3
    local high_value = NpcTracker.get_high_value_rooms(min_kills)
    local start_id = RouteEngine.get_last_room_id()
    local start_name = RouteEngine.get_last_room_name()

    mud.note(".:: Being's Discworld BP Route ::.", { bold = true })

    if start_name then
        mud.note("  Current location: " .. start_name, { fg = "cyan" })
    end

    if #high_value == 0 then
        mud.note("  No rooms with " .. min_kills .. "+ kills yet.", { fg = "white" })
        mud.note("  Keep killing NPCs to build route data.", { fg = "white" })
        return
    end

    mud.note("  High-value rooms (" .. min_kills .. "+ kills):", { fg = "yellow" })
    for i, room in ipairs(high_value) do
        mud.note(string.format("    %d. %s (%d kills: %s)",
            i, room.name, room.total, format_types(room.types)), { fg = "white" })
    end

    if not start_id then
        mud.note("\n  Move around to build the route graph.", { fg = "yellow" })
        return
    end

    local route = RouteEngine.calculate_route(high_value, start_id)
    if not route or #route == 0 then
        mud.note("\n  Cannot calculate route - not enough room graph data.", { fg = "yellow" })
        mud.note("  Walk between rooms to build connections.", { fg = "yellow" })
        return
    end

    local total_moves = 0
    for _, step in ipairs(route) do
        total_moves = total_moves + step.distance
    end

    mud.note(string.format("\n  Route (%d rooms, ~%d moves):", #route, total_moves), { fg = "green" })

    for i, step in ipairs(route) do
        if step.is_return then
            mud.note(string.format("    %d. Return to start (%s)",
                i, format_path(step.path)), { fg = "cyan" })
        else
            mud.note(string.format("    %d. %s → %s (%d kills)",
                i, format_path(step.path), step.room.name, step.room.total), { fg = "green" })
        end
    end
end

function RouteDisplay.show_status()
    local rooms = NpcTracker.get_all_rooms()
    local room_count = 0
    for _ in pairs(rooms) do room_count = room_count + 1 end

    local graph = RouteEngine.get_graph()
    local graph_rooms = 0
    for _ in pairs(graph.rooms) do graph_rooms = graph_rooms + 1 end

    mud.note(".:: Being's Discworld BP Route ::.", { bold = true })
    mud.note(string.format("  Kills recorded: %d", NpcTracker.get_total_kills()), { fg = "white" })
    mud.note(string.format("  Rooms with kills: %d", room_count), { fg = "white" })
    mud.note(string.format("  Rooms in graph: %d", graph_rooms), { fg = "white" })
    mud.note(string.format("  Graph transitions: %d", graph.transitions), { fg = "white" })
end

return RouteDisplay
