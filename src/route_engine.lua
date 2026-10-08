local Database = require("database")

local RouteEngine = {}

local OPPOSITE = {
    n = "s", s = "n",
    e = "w", w = "e",
    ne = "sw", sw = "ne",
    nw = "se", se = "nw",
    u = "d", d = "u",
    ["in"] = "out", out = "in",
}

local graph = { rooms = {}, transitions = 0 }

local last_room_id = nil
local last_room_name = nil
local pending_direction = nil

function RouteEngine.init()
    Database.init()
    Database.migrate_from_storage()
    RouteEngine.load()
end

function RouteEngine.load()
    graph.rooms = {}
    local edges = db.query("SELECT from_id, direction, to_id FROM room_edges")
    for _, e in ipairs(edges) do
        if not graph.rooms[e.from_id] then
            graph.rooms[e.from_id] = {}
        end
        graph.rooms[e.from_id][e.direction] = e.to_id
    end
    graph.transitions = Database.get_transition_count()
end

function RouteEngine.save()
    local edges = db.query("SELECT from_id, direction, to_id FROM room_edges")
    local existing = {}
    for _, e in ipairs(edges) do
        local key = e.from_id .. "|" .. e.direction
        existing[key] = e.to_id
    end

    db.transaction(function()
        for from_id, directions in pairs(graph.rooms) do
            for dir, to_id in pairs(directions) do
                local key = from_id .. "|" .. dir
                if not existing[key] then
                    db.exec("INSERT OR REPLACE INTO room_edges(from_id, direction, to_id) VALUES (?, ?, ?)", {
                        from_id, dir, to_id,
                    })
                end
            end
        end
        Database.set_transition_count(graph.transitions)
    end)
end

function RouteEngine.force_save()
    RouteEngine.save()
end

function RouteEngine.set_current_room(room_id, room_name)
    if not room_id or room_id == "" then return end

    if last_room_id and last_room_id ~= room_id then
        RouteEngine.record_transition(last_room_id, room_id, pending_direction)
        pending_direction = nil
    end

    last_room_id = room_id
    last_room_name = room_name or last_room_name
end

function RouteEngine.set_pending_direction(dir)
    pending_direction = dir
end

function RouteEngine.record_transition(from_id, to_id, direction)
    if not from_id or not to_id or from_id == to_id then return end

    if not graph.rooms[from_id] then
        graph.rooms[from_id] = {}
    end
    if not graph.rooms[to_id] then
        graph.rooms[to_id] = {}
    end

    if direction and OPPOSITE[direction] then
        if not graph.rooms[from_id][direction] then
            graph.rooms[from_id][direction] = to_id
        end
        if not graph.rooms[to_id][OPPOSITE[direction]] then
            graph.rooms[to_id][OPPOSITE[direction]] = from_id
        end
    else
        local found_dir = nil
        for dir, target in pairs(graph.rooms[from_id]) do
            if target == to_id then
                found_dir = dir
                break
            end
        end
        if not found_dir then
            for dir, target in pairs(graph.rooms[to_id]) do
                if target == from_id then
                    found_dir = OPPOSITE[dir]
                    break
                end
            end
        end
        if not found_dir then
            found_dir = "x"
        end
        graph.rooms[from_id][found_dir] = to_id
        if OPPOSITE[found_dir] then
            graph.rooms[to_id][OPPOSITE[found_dir]] = from_id
        end
    end

    graph.transitions = graph.transitions + 1
end

function RouteEngine.bfs(start_id, target_id)
    if start_id == target_id then return {} end
    if not graph.rooms[start_id] or not graph.rooms[target_id] then return nil end

    local queue = { { id = start_id, path = {} } }
    local visited = { [start_id] = true }

    while #queue > 0 do
        local current = table.remove(queue, 1)

        for dir, neighbor in pairs(graph.rooms[current.id] or {}) do
            if neighbor == target_id then
                local result = {}
                for _, step in ipairs(current.path) do
                    table.insert(result, step)
                end
                table.insert(result, dir)
                return result
            end

            if not visited[neighbor] then
                visited[neighbor] = true
                local new_path = {}
                for _, step in ipairs(current.path) do
                    table.insert(new_path, step)
                end
                table.insert(new_path, dir)
                table.insert(queue, { id = neighbor, path = new_path })
            end
        end
    end

    return nil
end

function RouteEngine.calculate_route(high_value_rooms, start_id)
    if not start_id or #high_value_rooms == 0 then return nil end

    local route = {}
    local current = start_id
    local visited = { [start_id] = true }

    local unvisited = {}
    for _, room in ipairs(high_value_rooms) do
        if room.id ~= start_id then
            table.insert(unvisited, room)
        end
    end

    while #unvisited > 0 do
        local best_idx = nil
        local best_distance = math.huge
        local best_path = nil

        for i, room in ipairs(unvisited) do
            local path = RouteEngine.bfs(current, room.id)
            if path and #path < best_distance then
                best_distance = #path
                best_path = path
                best_idx = i
            end
        end

        if best_idx then
            local room = table.remove(unvisited, best_idx)
            table.insert(route, {
                room = room,
                path = best_path,
                distance = best_distance,
            })
            current = room.id
            visited[room.id] = true
        else
            break
        end
    end

    local return_path = RouteEngine.bfs(current, start_id)
    if return_path then
        table.insert(route, {
            room = { id = start_id, name = "Return to start", total = 0, types = {} },
            path = return_path,
            distance = #return_path,
            is_return = true,
        })
    end

    return route
end

function RouteEngine.reload()
    RouteEngine.load()
end

function RouteEngine.get_last_room_id()
    return last_room_id
end

function RouteEngine.get_last_room_name()
    return last_room_name
end

function RouteEngine.get_graph()
    return graph
end

function RouteEngine.reset()
    graph.rooms = {}
    graph.transitions = 0
    last_room_id = nil
    last_room_name = nil
    pending_direction = nil
    Database.reset_all()
end

function RouteEngine.import_data(imported)
    if not imported then return end
    if imported.rooms then
        for room_id, edges in pairs(imported.rooms) do
            if not graph.rooms[room_id] then
                graph.rooms[room_id] = {}
            end
            for dir, target in pairs(edges) do
                if not graph.rooms[room_id][dir] then
                    graph.rooms[room_id][dir] = target
                end
            end
        end
    end
    if imported.transitions then
        graph.transitions = graph.transitions + imported.transitions
    end
end

return RouteEngine
