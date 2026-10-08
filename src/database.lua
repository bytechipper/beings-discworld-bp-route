local Database = {}

local initialized = false

function Database.init()
    if initialized then return end

    db.exec([[
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY,
            name TEXT
        )
    ]])

    db.exec([[
        CREATE TABLE IF NOT EXISTS npc_kills (
            room_id TEXT NOT NULL,
            npc_type TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (room_id, npc_type),
            FOREIGN KEY (room_id) REFERENCES rooms(id)
        )
    ]])

    db.exec([[
        CREATE TABLE IF NOT EXISTS room_edges (
            from_id TEXT NOT NULL,
            direction TEXT NOT NULL,
            to_id TEXT NOT NULL,
            PRIMARY KEY (from_id, direction),
            FOREIGN KEY (from_id) REFERENCES rooms(id),
            FOREIGN KEY (to_id) REFERENCES rooms(id)
        )
    ]])

    db.exec([[
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    ]])

    initialized = true
end

function Database.migrate_from_storage()
    local migrated = db.query("SELECT value FROM meta WHERE key = 'migrated_from_storage'")
    if #migrated > 0 then return end

    local npc_data = storage.get("npc_data")
    if npc_data and npc_data.rooms then
        db.transaction(function()
            for room_id, room in pairs(npc_data.rooms) do
                db.exec("INSERT OR IGNORE INTO rooms(id, name) VALUES (?, ?)", { room_id, room.name or "unknown" })
                for _, npc_type in ipairs({
                    "nobleman", "bodyguard", "samurai",
                    "merchant", "trader", "thug",
                    "captain", "ronin",
                }) do
                    local count = room[npc_type] or 0
                    if count > 0 then
                        db.exec([[
                            INSERT INTO npc_kills(room_id, npc_type, count) VALUES (?, ?, ?)
                            ON CONFLICT(room_id, npc_type) DO UPDATE SET count = count + excluded.count
                        ]], { room_id, npc_type, count })
                    end
                end
            end
            if npc_data.total_kills then
                db.exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('total_kills', ?)", {
                    tostring(npc_data.total_kills),
                })
            end
        end)
    end

    local room_graph = storage.get("room_graph")
    if room_graph and room_graph.rooms then
        db.transaction(function()
            for room_id, edges in pairs(room_graph.rooms) do
                for dir, target in pairs(edges) do
                    db.exec([[
                        INSERT INTO room_edges(from_id, direction, to_id) VALUES (?, ?, ?)
                        ON CONFLICT(from_id, direction) DO UPDATE SET to_id = excluded.to_id
                    ]], { room_id, dir, target })
                end
            end
            if room_graph.transitions then
                db.exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('transitions', ?)", {
                    tostring(room_graph.transitions),
                })
            end
        end)
    end

    db.exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('migrated_from_storage', '1')")
end

function Database.get_npc_kills(room_id)
    return db.query("SELECT npc_type, count FROM npc_kills WHERE room_id = ?", { room_id })
end

function Database.get_all_npc_kills()
    return db.query("SELECT room_id, npc_type, count FROM npc_kills")
end

function Database.get_total_kills()
    local row = db.query("SELECT SUM(count) as total FROM npc_kills")
    return row[1] and row[1].total or 0
end

function Database.add_npc_kill(room_id, npc_type, count)
    count = count or 1
    db.exec([[
        INSERT INTO npc_kills(room_id, npc_type, count) VALUES (?, ?, ?)
        ON CONFLICT(room_id, npc_type) DO UPDATE SET count = count + excluded.count
    ]], { room_id, npc_type, count })
end

function Database.get_high_value_rooms(min_kills)
    min_kills = min_kills or 3
    return db.query([[
        SELECT nk.room_id, r.name, SUM(nk.count) as total
        FROM npc_kills nk
        JOIN rooms r ON r.id = nk.room_id
        GROUP BY nk.room_id
        HAVING total >= ?
        ORDER BY total DESC
    ]], { min_kills })
end

function Database.get_high_value_room_types(room_id)
    return db.query("SELECT npc_type, count FROM npc_kills WHERE room_id = ? ORDER BY count DESC", { room_id })
end

function Database.get_all_rooms()
    return db.query("SELECT id, name FROM rooms")
end

function Database.get_room(room_id)
    local rows = db.query("SELECT id, name FROM rooms WHERE id = ?", { room_id })
    return rows[1]
end

function Database.upsert_room(room_id, room_name)
    db.exec([[
        INSERT INTO rooms(id, name) VALUES (?, ?)
        ON CONFLICT(id) DO UPDATE SET name = CASE
            WHEN excluded.name != 'unknown' AND (rooms.name IS NULL OR rooms.name = 'unknown')
            THEN excluded.name
            ELSE rooms.name
        END
    ]], { room_id, room_name or "unknown" })
end

function Database.get_room_count()
    local row = db.query("SELECT COUNT(*) as count FROM rooms")
    return row[1] and row[1].count or 0
end

function Database.reset_npc_kills()
    db.exec("DELETE FROM npc_kills")
    db.exec("DELETE FROM meta WHERE key = 'total_kills'")
end

function Database.get_transition_count()
    local row = db.query("SELECT value FROM meta WHERE key = 'transitions'")
    return row[1] and tonumber(row[1].value) or 0
end

function Database.set_transition_count(count)
    db.exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('transitions', ?)", { tostring(count) })
end

function Database.add_edge(from_id, direction, to_id)
    db.exec([[
        INSERT INTO room_edges(from_id, direction, to_id) VALUES (?, ?, ?)
        ON CONFLICT(from_id, direction) DO UPDATE SET to_id = excluded.to_id
    ]], { from_id, direction, to_id })
end

function Database.get_edges(room_id)
    return db.query("SELECT direction, to_id FROM room_edges WHERE from_id = ?", { room_id })
end

function Database.get_room_count_graph()
    local row = db.query("SELECT COUNT(DISTINCT from_id) as count FROM room_edges")
    return row[1] and row[1].count or 0
end

function Database.get_edge_count()
    local row = db.query("SELECT COUNT(*) as count FROM room_edges")
    return row[1] and row[1].count or 0
end

function Database.reset_room_graph()
    db.exec("DELETE FROM room_edges")
    db.exec("DELETE FROM meta WHERE key = 'transitions'")
end

function Database.reset_all()
    db.exec("DELETE FROM npc_kills")
    db.exec("DELETE FROM room_edges")
    db.exec("DELETE FROM rooms")
    db.exec("DELETE FROM meta WHERE key IN ('total_kills', 'transitions')")
end

function Database.export()
    local rooms = db.query("SELECT id, name FROM rooms")
    local kills = db.query("SELECT room_id, npc_type, count FROM npc_kills")
    local edges = db.query("SELECT from_id, direction, to_id FROM room_edges")
    local transitions_row = db.query("SELECT value FROM meta WHERE key = 'transitions'")
    local total_kills_row = db.query("SELECT SUM(count) as total FROM npc_kills")

    local export = {
        rooms = {},
        npc_kills = {},
        room_edges = {},
        transitions = transitions_row[1] and tonumber(transitions_row[1].value) or 0,
        total_kills = total_kills_row[1] and total_kills_row[1].total or 0,
    }

    for _, r in ipairs(rooms) do
        export.rooms[r.id] = r.name
    end

    for _, k in ipairs(kills) do
        if not export.npc_kills[k.room_id] then
            export.npc_kills[k.room_id] = {}
        end
        export.npc_kills[k.room_id][k.npc_type] = k.count
    end

    for _, e in ipairs(edges) do
        if not export.room_edges[e.from_id] then
            export.room_edges[e.from_id] = {}
        end
        export.room_edges[e.from_id][e.direction] = e.to_id
    end

    return export
end

function Database.import(data, merge)
    if not data then return false, "no data" end

    db.transaction(function()
        if not merge then
            db.exec("DELETE FROM npc_kills")
            db.exec("DELETE FROM rooms")
            db.exec("DELETE FROM room_edges")
            db.exec("DELETE FROM meta WHERE key IN ('total_kills', 'transitions')")
        end

        if data.rooms then
            for room_id, room_name in pairs(data.rooms) do
                db.exec("INSERT OR IGNORE INTO rooms(id, name) VALUES (?, ?)", { room_id, room_name })
            end
        end

        if data.npc_kills then
            for room_id, types in pairs(data.npc_kills) do
                db.exec("INSERT OR IGNORE INTO rooms(id, name) VALUES (?, 'unknown')", { room_id })
                for npc_type, count in pairs(types) do
                    if merge then
                        db.exec([[
                            INSERT INTO npc_kills(room_id, npc_type, count) VALUES (?, ?, ?)
                            ON CONFLICT(room_id, npc_type) DO UPDATE SET count = count + excluded.count
                        ]], { room_id, npc_type, count })
                    else
                        db.exec([[
                            INSERT OR REPLACE INTO npc_kills(room_id, npc_type, count) VALUES (?, ?, ?)
                        ]], { room_id, npc_type, count })
                    end
                end
            end
        end

        if data.room_edges then
            for from_id, directions in pairs(data.room_edges) do
                for direction, to_id in pairs(directions) do
                    if merge then
                        db.exec([[
                            INSERT INTO room_edges(from_id, direction, to_id) VALUES (?, ?, ?)
                            ON CONFLICT(from_id, direction) DO UPDATE SET to_id = excluded.to_id
                        ]], { from_id, direction, to_id })
                    else
                        db.exec("INSERT OR REPLACE INTO room_edges(from_id, direction, to_id) VALUES (?, ?, ?)", {
                            from_id, direction, to_id,
                        })
                    end
                end
            end
        end

        if merge then
            if data.transitions then
                local current = Database.get_transition_count()
                Database.set_transition_count(current + data.transitions)
            end
        else
            if data.transitions then
                Database.set_transition_count(data.transitions)
            end
        end
    end)

    return true
end

local function escape_json_string(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function encode_json_value(val, depth)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return '"' .. escape_json_string(val) .. '"'
    elseif t == "table" then
        local is_array = #val > 0 or next(val) == nil
        if is_array then
            for k in pairs(val) do
                if type(k) ~= "number" or k < 1 or k > #val or k ~= math.floor(k) then
                    is_array = false
                    break
                end
            end
        end

        local pad = string.rep("  ", depth + 1)
        local close_pad = string.rep("  ", depth)
        local parts = {}

        if is_array then
            for _, v in ipairs(val) do
                table.insert(parts, pad .. encode_json_value(v, depth + 1))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. close_pad .. "]"
        else
            local keys = {}
            for k in pairs(val) do
                table.insert(keys, tostring(k))
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                table.insert(parts, pad .. '"' .. escape_json_string(k) .. '": ' .. encode_json_value(val[k], depth + 1))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. close_pad .. "}"
        end
    else
        return '"[unserializable: ' .. t .. ']"'
    end
end

function Database.encode_json(data)
    return encode_json_value(data, 0)
end

local json_pos = 1
local json_src = ""

local function json_skip_whitespace()
    json_pos = json_src:find("[^ \t\r\n]", json_pos) or #json_src + 1
end

local function json_peek()
    json_skip_whitespace()
    return json_src:sub(json_pos, json_pos)
end

local function json_advance()
    json_pos = json_pos + 1
end

local function json_expect(ch)
    json_skip_whitespace()
    if json_src:sub(json_pos, json_pos) ~= ch then
        error("expected '" .. ch .. "' at position " .. json_pos)
    end
    json_pos = json_pos + 1
end

local json_parse_value

local function json_parse_string()
    json_expect('"')
    local start = json_pos
    local result = {}
    while json_pos <= #json_src do
        local ch = json_src:sub(json_pos, json_pos)
        if ch == '"' then
            json_pos = json_pos + 1
            return table.concat(result) .. json_src:sub(start, json_pos - 2)
        elseif ch == '\\' then
            table.insert(result, json_src:sub(start, json_pos - 1))
            json_pos = json_pos + 1
            local esc = json_src:sub(json_pos, json_pos)
            if esc == 'n' then
                table.insert(result, '\n')
            elseif esc == 'r' then
                table.insert(result, '\r')
            elseif esc == 't' then
                table.insert(result, '\t')
            elseif esc == 'b' then
                table.insert(result, '\b')
            elseif esc == 'f' then
                table.insert(result, '\f')
            elseif esc == 'u' then
                local hex = json_src:sub(json_pos + 1, json_pos + 4)
                local cp = tonumber(hex, 16)
                if cp < 128 then
                    table.insert(result, string.char(cp))
                elseif cp < 2048 then
                    table.insert(result, string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64)))
                else
                    table.insert(result, string.char(
                        0xE0 + math.floor(cp / 4096),
                        0x80 + math.floor((cp % 4096) / 64),
                        0x80 + (cp % 64)
                    ))
                end
                json_pos = json_pos + 4
            else
                table.insert(result, esc)
            end
            json_pos = json_pos + 1
            start = json_pos
        else
            json_pos = json_pos + 1
        end
    end
    error("unterminated string")
end

local function json_parse_number()
    json_skip_whitespace()
    local start = json_pos
    if json_src:sub(json_pos, json_pos) == '-' then json_pos = json_pos + 1 end
    while json_pos <= #json_src and json_src:sub(json_pos, json_pos):match("[%d%.eE%+%-]") do
        json_pos = json_pos + 1
    end
    local num = tonumber(json_src:sub(start, json_pos - 1))
    if not num then error("invalid number at position " .. start) end
    return num
end

local function json_parse_object()
    json_expect('{')
    local obj = {}
    if json_peek() == '}' then json_advance(); return obj end
    while true do
        local key = json_parse_string()
        json_expect(':')
        obj[key] = json_parse_value()
        if json_peek() == '}' then break end
        json_expect(',')
    end
    json_expect('}')
    return obj
end

local function json_parse_array()
    json_expect('[')
    local arr = {}
    if json_peek() == ']' then json_advance(); return arr end
    while true do
        table.insert(arr, json_parse_value())
        if json_peek() == ']' then break end
        json_expect(',')
    end
    json_expect(']')
    return arr
end

json_parse_value = function()
    json_skip_whitespace()
    local ch = json_src:sub(json_pos, json_pos)
    if ch == '"' then return json_parse_string() end
    if ch == '{' then return json_parse_object() end
    if ch == '[' then return json_parse_array() end
    if ch == 't' then json_pos = json_pos + 4; return true end
    if ch == 'f' then json_pos = json_pos + 5; return false end
    if ch == 'n' then json_pos = json_pos + 4; return nil end
    return json_parse_number()
end

function Database.import_json(json_str, merge)
    merge = merge ~= false
    json_src = json_str
    json_pos = 1
    local ok, result = pcall(json_parse_value)
    if not ok then
        return false
    end
    if type(result) ~= "table" then
        return false
    end
    return Database.import(result, merge)
end

return Database
