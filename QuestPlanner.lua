-- ForeverQuest: future-quest discovery via the optional QuestieDB public API.
-- No copied Questie database or borrowed UI code.
-- API: https://github.com/Questie/QuestieDB/blob/master/docs/api.md
-- Database availability is only a prediction; Forever quest offers vary.
local Planner = {}
_G.ForeverQuestPlanner = Planner

local cache = {
    items = {}, mapID = nil, level = nil, activeKey = nil,
    status = "Not scanned", scanning = false, generation = 0,
}
local areaMap

local function get(db, id, field)
    if not db or type(db.Get) ~= "function" then return nil end
    local ok, value = pcall(db.Get, id, field)
    return ok and value or nil
end

local function provider()
    local lib = _G.LibQuestieDB
    if not lib or not lib.Quest or not lib.Npc then return nil end
    if lib.flavor and lib.flavor.expansion
        and tostring(lib.flavor.expansion):lower() ~= "forever" then
        return nil
    end
    if type(lib.Quest.GetAllIds) ~= "function" then return nil end
    return lib
end

local function playerXY(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos or not pos.GetXY then return nil end
    local valid, x, y = pcall(pos.GetXY, pos)
    if valid and type(x) == "number" and type(y) == "number" then
        return x, y
    end
end

local function zoneMap(lib)
    if areaMap then return areaMap end
    local result = {
        [14] = 1411, [17] = 1413, [12] = 1429,
        [215] = 1412, [85] = 1420, [1] = 1426,
    }
    if lib.Support and type(lib.Support.Get) == "function" then
        local ok, zone = pcall(lib.Support.Get, "ZoneDB")
        if ok and type(zone) == "table" and type(zone.private) == "table" then
            for _, key in ipairs({"areaIdToUiMapId", "areaIdToUiMapIdOverride"}) do
                local source = zone.private[key]
                if type(source) == "string" then
                    for area, map in source:gmatch("%[(%-?%d+)%]%s*=%s*(%-?%d+)") do
                        result[tonumber(area)] = tonumber(map)
                    end
                end
            end
        end
    end
    areaMap = result
    return result
end

local function completed(id)
    local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    if type(f) ~= "function" then f = _G.IsQuestFlaggedCompleted end
    if type(f) ~= "function" then return nil end
    local ok, done = pcall(f, id)
    if not ok then return nil end
    return done and true or false
end

-- Lua double-precision arithmetic handles bit positions above 32.
local function allowed(mask, bit)
    if type(mask) ~= "number" or mask == 0 then return true end
    if type(bit) ~= "number" or bit < 1 then return false end
    return math.floor(mask / bit) % 2 == 1
end

local function prereqs(q, id, active)
    local group = get(q, id, "preQuestGroup")
    if type(group) == "table" then
        for _, pre in ipairs(group) do
            if completed(pre) ~= true then return false end
        end
    end
    local single = get(q, id, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        local pass = false
        for _, pre in ipairs(single) do
            if completed(pre) == true then pass = true; break end
        end
        if not pass then return false end
    end
    local parent = get(q, id, "parentQuest")
    if type(parent) == "number" and parent > 0 and not active[parent] then
        return false
    end
    local chain = get(q, id, "availableStartingWith")
    if type(chain) == "number" and chain > 0
        and not active[chain] and completed(chain) ~= true then return false end
    local untilDone = get(q, id, "availableUntilCompleted")
    if type(untilDone) == "number" and untilDone > 0
        and completed(untilDone) == true then return false end
    local disabled = get(q, id, "disabledByQuest")
    if type(disabled) == "number" and disabled > 0 and active[disabled] then
        return false
    end
    local exclusives = get(q, id, "exclusiveTo")
    if type(exclusives) == "table" then
        for _, other in ipairs(exclusives) do
            if active[other] or completed(other) == true then return false end
        end
    end
    return true
end

local function eligible(lib, id, level, active, raceBit, classBit)
    local q = lib.Quest
    if active[id] or completed(id) == true then return false end
    local min = get(q, id, "requiredLevel")
    if type(min) == "number" and min > level then return false end
    local max = get(q, id, "requiredMaxLevel")
    if type(max) == "number" and max > 0 and level > max then return false end
    local questLevel = get(q, id, "questLevel")
    if type(questLevel) == "number" and questLevel > level + 5 then return false end
    if not allowed(get(q, id, "requiredRaces"), raceBit) then return false end
    if not allowed(get(q, id, "requiredClasses"), classBit) then return false end
    -- Don't recommend quests with gates we cannot verify from character state.
    for _, key in ipairs({
        "requiredSkill", "requiredMinRep", "requiredMaxRep",
        "requiredSpell", "requiredSpecialization", "requiredRanks",
    }) do
        local gate = get(q, id, key)
        if gate and gate ~= 0 then return false end
    end
    return prereqs(q, id, active)
end

local function starter(lib, id, mapID, maps, playerX, playerY)
    local startedBy = get(lib.Quest, id, "startedBy")
    if type(startedBy) ~= "table" then return nil end
    local best, bestSquared
    for _, entry in ipairs({
        {db = lib.Npc, ids = startedBy[1], kind = "NPC"},
        {db = lib.Object, ids = startedBy[2], kind = "object"},
    }) do
        if entry.db and type(entry.ids) == "table" then
            for _, npcID in ipairs(entry.ids) do
                local spawns = get(entry.db, npcID, "spawns")
                if type(spawns) == "table" then
                    for area, points in pairs(spawns) do
                        if (maps[area] == mapID or area == mapID)
                            and type(points) == "table" then
                            for _, p in ipairs(points) do
                                local x, y = p[1], p[2]
                                if type(x) == "number" and type(y) == "number"
                                    and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                                    local normalizedX, normalizedY = x / 100, y / 100
                                    local dx, dy = normalizedX - playerX, normalizedY - playerY
                                    local distance = dx * dx + dy * dy
                                    if not bestSquared or distance < bestSquared then
                                        bestSquared = distance
                                        best = {
                                            questID = id, mapID = mapID,
                                            x = normalizedX, y = normalizedY,
                                            giverID = npcID, kind = entry.kind,
                                            confidence = "provisional",
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Discover locations for active objectives and ready turn-ins across zones.
-- QuestieDB objectives group [1] NPCs, [2] objects, [3] items. For item
-- objectives we follow published NPC/object drop-source IDs. These are search
-- areas, not exact proof a particular spawn will drop the quest item.
local function closestEntity(lib, ids, db, mapID, maps, px, py, kind)
    if not db or type(ids) ~= "table" then return nil end
    local best, dist
    for _, id in ipairs(ids) do
        if type(id) == "number" and id > 0 then
            local spawns = get(db, id, "spawns")
            if type(spawns) == "table" then
                for areaID, points in pairs(spawns) do
                    if (maps[areaID] == mapID or areaID == mapID)
                        and type(points) == "table" then
                        for _, point in ipairs(points) do
                            local x, y = point[1], point[2]
                            if type(x) == "number" and type(y) == "number"
                                and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                                x, y = x / 100, y / 100
                                local dx, dy = x - px, y - py
                                local d = dx*dx + dy*dy
                                if not dist or d < dist then
                                    best, dist = {
                                        mapID = mapID, x = x, y = y,
                                        entityID = id, kind = kind,
                                        entityName = get(db, id, "name"),
                                        confidence = "questiedb-forever-provisional",
                                    }, d
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, dist
end

-- Only suppress a database target when its name unambiguously matches a
-- finished objective in the live quest log. Unknown matches remain eligible.
local function FinishedInQuestLog(name, statuses)
    if type(name) ~= "string" or name == ""
        or type(statuses) ~= "table" then return false end
    local needle = name:lower()
    if #needle < 4 then return false end
    for _, objective in ipairs(statuses) do
        if type(objective) == "table" then
            local text = objective.text or objective.description
            if type(text) == "string" and text:lower():find(needle, 1, true) then
                local done = objective.finished == true or objective.isFinished == true
                local required = tonumber(objective.numRequired)
                local fulfilled = tonumber(objective.numFulfilled)
                if required and required > 0 and fulfilled and fulfilled >= required then
                    done = true
                end
                if done then return true end
            end
        end
    end
    return false
end

function Planner:GetActivePosition(questID, complete, mapID, statuses)
    local lib = provider()
    if not lib or not questID or not mapID then return nil end
    local px, py = playerXY(mapID)
    if not px then return nil end
    local maps = zoneMap(lib)
    local idGroups
    if complete then
        idGroups = get(lib.Quest, questID, "finishedBy")
    else
        idGroups = get(lib.Quest, questID, "objectives")
    end
    if type(idGroups) ~= "table" then return nil end
    local candidates = {}
    local function add(ids, db, kind)
        local found = closestEntity(lib, ids, db, mapID, maps, px, py, kind)
        if found then candidates[#candidates+1] = found end
    end
    local npcIDs, objectIDs = {}, {}
    for _, row in ipairs(type(idGroups[1]) == "table" and idGroups[1] or {}) do
        local id = type(row) == "table" and row[1] or row
        if type(id) == "number" and id > 0
            and (complete or not FinishedInQuestLog(get(lib.Npc, id, "name"), statuses)) then
            npcIDs[#npcIDs+1] = id
        end
    end
    for _, row in ipairs(type(idGroups[2]) == "table" and idGroups[2] or {}) do
        local id = type(row) == "table" and row[1] or row
        if type(id) == "number" and id > 0
            and (complete or not FinishedInQuestLog(get(lib.Object, id, "name"), statuses)) then
            objectIDs[#objectIDs+1] = id
        end
    end
    add(npcIDs, lib.Npc, "NPC")
    add(objectIDs, lib.Object, "object")

    if not complete then
        for _, row in ipairs(type(idGroups[3]) == "table" and idGroups[3] or {}) do
            local itemID = type(row) == "table" and row[1] or row
            if type(itemID) == "number" and itemID > 0 and lib.Item
                and not FinishedInQuestLog(get(lib.Item, itemID, "name"), statuses) then
                add(get(lib.Item, itemID, "npcDrops"), lib.Npc, "item drop NPC")
                add(get(lib.Item, itemID, "objectDrops"), lib.Object, "item drop object")
            end
        end
    end

    local best, bestD
    for _, candidate in ipairs(candidates) do
        local dx, dy = candidate.x - px, candidate.y - py
        local d = dx*dx + dy*dy
        if not bestD or d < bestD then best, bestD = candidate, d end
    end
    return best
end

function Planner:GetChainPreview(questID, maxCount)
    local lib = provider()
    if not lib or not questID then return {} end
    local children = get(lib.Quest, questID, "childQuests")
    if type(children) ~= "table" then return {} end
    local result = {}
    for _, id in ipairs(children) do
        local name = get(lib.Quest, id, "name")
        if type(name) == "string" and name ~= "" then
            result[#result+1] = {questID = id, name = name}
        end
        if #result >= (maxCount or 3) then break end
    end
    return result
end

function Planner:Available() return provider() ~= nil end
function Planner:Status() return cache.status end

function Planner:Invalidate()
    cache.generation = cache.generation + 1
    cache.mapID, cache.activeKey, cache.level = nil, nil, nil
    cache.items, cache.scanning = {}, false
end

function Planner:GetNearby(mapID, maxResults)
    if cache.scanning or cache.mapID ~= mapID then return {} end
    local px, py = playerXY(mapID)
    if not px then return {} end
    local ranked = {}
    for _, item in ipairs(cache.items) do
        local dx, dy = item.x - px, item.y - py
        ranked[#ranked+1] = {item = item, distance = math.sqrt(dx*dx + dy*dy)}
    end
    table.sort(ranked, function(a, b) return a.distance < b.distance end)
    local out = {}
    for i = 1, math.min(maxResults or 5, #ranked) do
        local copy = {}
        for key, value in pairs(ranked[i].item) do copy[key] = value end
        copy.distance = ranked[i].distance
        out[#out+1] = copy
    end
    return out
end

function Planner:Scan(mapID, level, active, force)
    local lib = provider()
    if not lib or not mapID or not level then
        cache.status = lib and "Map not available" or "QuestieDB-Forever not installed"
        return
    end
    active = active or {}
    local sorted = {}
    for id in pairs(active) do sorted[#sorted+1] = id end
    table.sort(sorted)
    local key = table.concat(sorted, ",")
    if not force and cache.mapID == mapID and cache.level == level
        and cache.activeKey == key then return end
    self:Invalidate()
    cache.mapID, cache.level, cache.activeKey = mapID, level, key
    cache.scanning = true
    cache.status = "Scanning possible quest pickups"
    local ok, ids = pcall(lib.Quest.GetAllIds)
    if not ok or type(ids) ~= "table" then
        cache.scanning = false
        cache.status = "QuestieDB quest index unavailable"
        return
    end
    local raceID = UnitRace and select(3, UnitRace("player"))
    local classID = UnitClass and select(3, UnitClass("player"))
    local raceBit = lib.Enum and lib.Enum.raceMaskById
        and lib.Enum.raceMaskById[raceID]
    local classBit = type(classID) == "number" and (2 ^ (classID - 1)) or nil
    local maps = zoneMap(lib)
    local playerX, playerY = playerXY(mapID)
    if not playerX then
        cache.scanning = false
        cache.status = "Player map position unavailable"
        return
    end
    local generation = cache.generation
    local index, found = 1, {}
    local function scanBatch()
        if generation ~= cache.generation then return end
        local limit = math.min(#ids, index + 149)
        while index <= limit do
            local id = ids[index]
            index = index + 1
            -- A bad record must never interrupt scanning the zone.
            local valid, item = pcall(function()
                if not eligible(lib, id, level, active, raceBit, classBit) then return nil end
                local name = get(lib.Quest, id, "name")
                if type(name) ~= "string" or name == "" then return nil end
                local start = starter(lib, id, mapID, maps, playerX, playerY)
                if start then
                    start.name = name
                    start.source = "QuestieDB Forever baseline"
                end
                return start
            end)
            if valid and item then found[#found+1] = item end
        end
        if index <= #ids and C_Timer and C_Timer.After then
            C_Timer.After(0.02, scanBatch)
        else
            cache.items = found
            cache.scanning = false
            cache.status = string.format(
                "%d possible unaccepted quests on this map (unverified database estimates)",
                #found)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, scanBatch)
    else
        cache.scanning = false
        cache.status = "Quest database needs a working timer API"
    end
end
