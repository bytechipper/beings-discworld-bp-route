local Database = require("database")

local NpcTracker = {}

local NPC_TYPES = {
    "nobleman", "bodyguard", "samurai",
    "merchant", "trader", "thug",
    "captain", "ronin",
}

function NpcTracker.init()
    Database.init()
    Database.migrate_from_storage()
end

function NpcTracker.record_kill(npc_name, room_id, room_name)
    if not room_id or room_id == "" then return nil end

    local npc_type = NpcTracker.match_npc_type(npc_name)
    if not npc_type then return nil end

    Database.upsert_room(room_id, room_name)
    Database.add_npc_kill(room_id, npc_type, 1)

    return npc_type
end

function NpcTracker.match_npc_type(npc_name)
    if not npc_name then return nil end
    local lower = npc_name:lower()
    for _, npc_type in ipairs(NPC_TYPES) do
        if lower:find(npc_type, 1, true) then
            return npc_type
        end
    end
    return nil
end

function NpcTracker.get_room_data(room_id)
    local room = Database.get_room(room_id)
    if not room then return nil end
    local kills = Database.get_npc_kills(room_id)
    local data = { name = room.name }
    local total = 0
    for _, k in ipairs(kills) do
        data[k.npc_type] = k.count
        total = total + k.count
    end
    data.total = total
    return data
end

function NpcTracker.get_all_rooms()
    local rooms = Database.get_all_rooms()
    local result = {}
    for _, r in ipairs(rooms) do
        local kills = Database.get_npc_kills(r.id)
        local data = { name = r.name }
        local total = 0
        for _, k in ipairs(kills) do
            data[k.npc_type] = k.count
            total = total + k.count
        end
        data.total = total
        result[r.id] = data
    end
    return result
end

function NpcTracker.get_high_value_rooms(min_kills)
    min_kills = min_kills or 3
    local rows = Database.get_high_value_rooms(min_kills)
    local result = {}
    for _, row in ipairs(rows) do
        local types = Database.get_high_value_room_types(row.room_id)
        table.insert(result, {
            id = row.room_id,
            name = row.name,
            total = row.total,
            types = types,
        })
    end
    return result
end

function NpcTracker.get_type_counts(room_id)
    return Database.get_high_value_room_types(room_id)
end

function NpcTracker.get_npc_types()
    return NPC_TYPES
end

function NpcTracker.get_total_kills()
    return Database.get_total_kills()
end

function NpcTracker.reset()
    Database.reset_npc_kills()
end

function NpcTracker.import_data(imported)
    if not imported then return end
    if imported.rooms then
        for room_id, room in pairs(imported.rooms) do
            Database.upsert_room(room_id, room.name)
            for _, npc_type in ipairs(NPC_TYPES) do
                local count = room[npc_type] or 0
                if count > 0 then
                    Database.add_npc_kill(room_id, npc_type, count)
                end
            end
        end
    end
end

return NpcTracker
