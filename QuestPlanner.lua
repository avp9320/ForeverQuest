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

-- Standalone only. The packaged factual snapshot ships INSIDE
-- ForeverQuest, not as a separate addon or an optional runtime dependency.
local function provider()
    local lib = _G.ForeverQuestCatalog
    if not lib or not lib.Quest or not lib.Npc then return nil end
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
    if type(lib.AreaToMap) == "table" and next(lib.AreaToMap) then
        return lib.AreaToMap
    end
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
    local nextQuest = get(q, id, "nextQuestInChain")
    if type(nextQuest) == "number" and nextQuest > 0
        and (active[nextQuest] or completed(nextQuest) == true) then
        return false
    end
    local breadcrumbTarget = get(q,id,"breadcrumbForQuestId")
    if type(breadcrumbTarget)=="number" and breadcrumbTarget>0
        and (active[breadcrumbTarget] or completed(breadcrumbTarget)==true) then
        return false
    end
    local breadcrumbs = get(q,id,"breadcrumbs")
    if type(breadcrumbs)=="table" then
        for _,before in ipairs(breadcrumbs) do
            if active[before] then return false end
        end
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
    -- Event-gated quests should not be advertised as definitely available.
    local flags = get(q, id, "specialFlags")
    if type(flags) == "number" and math.floor(flags / 2) % 2 == 1 then
        return false
    end
    local min = get(q, id, "requiredLevel")
    if type(min) == "number" and min > level then return false end
    local max = get(q, id, "requiredMaxLevel")
    if type(max) == "number" and max > 0 and level > max then return false end
    local questLevel = get(q, id, "questLevel")
    if type(questLevel) == "number" and questLevel > level then return false end
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

local function FriendlyQuestGiver(db, npcID, kind)
    if kind ~= "NPC" then return true end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction ~= "Horde" and faction ~= "Alliance" then return true end
    local friendly = get(db, npcID, "friendlyToFaction")
    if type(friendly) ~= "string" or friendly == "" then return true end
    return friendly:find(faction == "Horde" and "H" or "A", 1, true) ~= nil
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
                local spawns = FriendlyQuestGiver(entry.db, npcID, entry.kind)
                    and get(entry.db, npcID, "spawns") or nil
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
                                            giverName = get(entry.db, npcID, "name"),
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
    -- A documented Forever location wins over an inherited Classic spawn.
    -- Keep the NPC's ID/name for grouping and show an actual destination
    -- rather than forcing the player to decode 50,40.
    local curated = _G.ForeverQuestData and _G.ForeverQuestData[id]
    local point = curated and curated.pickup
    if curated and curated.mapID == mapID and type(point) == "table"
        and type(point.x) == "number" and type(point.y) == "number"
        and point.x >= 0 and point.x <= 1
        and point.y >= 0 and point.y <= 1 then
        best = {
            questID = id, mapID = mapID, x = point.x, y = point.y,
            giverID = point.npcID or (best and best.giverID),
            giverName = point.npc or (best and best.giverName),
            area = point.area,
            kind = best and best.kind or "NPC",
            confidence = curated.confidence or "provisional",
        }
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

-- One quest may have several unfinished objectives. Return one nearby search
-- area for EACH distinct NPC, object, or collection goal. This avoids the
-- previous bug where the whole quest was pinned to just one target.
-- Alternative spawn positions or drop sources for the same goal are choices,
-- not additional things the player has to complete.
function Planner:GetActivePositions(questID, complete, mapID, statuses, maxCount)
    local lib = provider()
    if not lib or not questID or not mapID then return {} end
    local px, py = playerXY(mapID)
    if not px then return {} end
    local maps = zoneMap(lib)
    local groups = get(lib.Quest, questID, complete and "finishedBy" or "objectives")
    -- Pure exploration quests can have a trigger location but no NPC/item
    -- objective table at all.
    if type(groups) ~= "table" then groups = {} end

    local result = {}
    local function bestLocation(ids, db, kind)
        return closestEntity(lib, ids, db, mapID, maps, px, py, kind)
    end
    local function add(key, label, stepLabel, location)
        if not location then return end
        local Knowledge = _G.ForeverQuestKnowledge
        local learned = Knowledge and Knowledge:Get(
            _G.ForeverQuestDB,"objective",questID,key)
        if learned and learned.mapID==mapID then
            location.x,location.y=learned.x,learned.y
            location.confidence="account-observed"
        end
        location.goalKey = key
        location.targetName = label
        location.stepLabel = stepLabel
        local dx, dy = location.x - px, location.y - py
        location.mapDistance = math.sqrt(dx * dx + dy * dy)
        result[#result + 1] = location
    end

    if complete then
        local Knowledge = _G.ForeverQuestKnowledge
        local learned = Knowledge and Knowledge:Get(_G.ForeverQuestDB,"turnin",questID)
        if learned and learned.mapID == mapID then
            learned.entityName = "Previously observed turn-in"
            add("turnin","Previously observed turn-in","Turn in quest",learned)
            return result
        end
        -- Multiple finishers are usually alternatives; never route the player
        -- to all of them. Choose the nearest known valid turn-in location.
        local npc, npcD = bestLocation(groups[1], lib.Npc, "turn-in NPC")
        local object, objectD = bestLocation(groups[2], lib.Object, "turn-in object")
        local best = npc
        if object and (not npcD or (objectD and objectD < npcD)) then
            best = object
        end
        add("turnin", best and best.entityName, "Turn in quest", best)
        return result
    end

    -- NPC and object goal rows include IDs + quantities; the live quest log
    -- is authoritative about whether each objective is already complete.
    for _, group in ipairs({
        {rows = groups[1], db = lib.Npc, kind = "enemy", prefix = "Defeat "},
        {rows = groups[2], db = lib.Object, kind = "object", prefix = "Use "},
    }) do
        if type(group.rows) == "table" then
            local done = {}
            for _, row in ipairs(group.rows) do
                local id = type(row) == "table" and row[1] or row
                if type(id) == "number" and id > 0 and not done[id] then
                    done[id] = true
                    local label = get(group.db, id, "name")
                    if not FinishedInQuestLog(label, statuses) then
                        local location = bestLocation({id}, group.db, group.kind)
                        add(group.kind .. ":" .. id, label,
                            group.prefix .. (label or "quest target"), location)
                    end
                end
            end
        end
    end

    -- Item goals have several potential sources. Pick just one source area
    -- per item, favoring the closest known drop NPC or interactable object.
    if type(groups[3]) == "table" and lib.Item then
        local done = {}
        for _, row in ipairs(groups[3]) do
            local itemID = type(row) == "table" and row[1] or row
            if type(itemID) == "number" and itemID > 0 and not done[itemID] then
                done[itemID] = true
                local itemName = get(lib.Item, itemID, "name")
                if not FinishedInQuestLog(itemName, statuses) then
                    local npc, npcD = bestLocation(
                        get(lib.Item, itemID, "npcDrops"), lib.Npc, "item drop NPC")
                    local object, objectD = bestLocation(
                        get(lib.Item, itemID, "objectDrops"), lib.Object, "item drop object")
                    local best = npc
                    if object and (not npcD or (objectD and objectD < npcD)) then
                        best = object
                    end
                    local label = itemName or ("Item " .. itemID)
                    local text = "Collect " .. label
                    if best and best.entityName then
                        text = text .. " (" .. best.entityName .. ")"
                    end
                    add("item:" .. itemID, label, text, best)
                end
            end
        end
    end

    -- Exploration / visit-location quests often lack kill and item goals.
    -- Only use their spatial trigger once no other known objective remains,
    -- AND when the live quest log doesn't report unfinished tasks we lack
    -- coordinates for. Never send the player to a completion trigger early.
    if #result == 0 then
        local unfinishedLiveGoal = false
        for _, objective in ipairs(type(statuses) == "table" and statuses or {}) do
            if type(objective) == "table"
                and not (objective.finished == true or objective.isFinished == true) then
                local required, fulfilled = tonumber(objective.numRequired),
                    tonumber(objective.numFulfilled)
                if not required or not fulfilled or fulfilled < required then
                    unfinishedLiveGoal = true
                    break
                end
            end
        end
        if not unfinishedLiveGoal then
            local locations = get(lib.Quest, questID, "triggerPoints")
            local best, bestD
            if type(locations) == "table" then
                for areaID, points in pairs(locations) do
                    if (maps[areaID] == mapID or areaID == mapID)
                        and type(points) == "table" then
                        for _, xy in ipairs(points) do
                            local x, y = xy[1], xy[2]
                            if type(x) == "number" and type(y) == "number"
                                and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                                x, y = x / 100, y / 100
                                local dx, dy = x - px, y - py
                                local d = dx * dx + dy * dy
                                if not bestD or d < bestD then
                                    bestD = d
                                    best = {
                                        x = x, y = y, mapID = mapID,
                                        kind = "exploration",
                                        entityName = "Quest location",
                                        confidence = "bundled-catalog-provisional",
                                    }
                                end
                            end
                        end
                    end
                end
            end
            add("trigger", "Quest location", "Explore quest area", best)
        end
    end

    table.sort(result, function(a, b)
        if a.mapDistance == b.mapDistance then
            return a.goalKey < b.goalKey
        end
        return a.mapDistance < b.mapDistance
    end)
    -- A bounded number of separate objectives avoids massive cluster spam.
    local limit = math.max(1, math.min(10, maxCount or 6))
    while #result > limit do result[#result] = nil end
    return result
end

-- Compatibility API for callers needing only the first immediate target.
function Planner:GetActivePosition(questID, complete, mapID, statuses)
    return self:GetActivePositions(questID, complete, mapID, statuses, 1)[1]
end

function Planner:GetChainPreview(questID, maxCount)
    local chains = _G.ForeverQuestChains
    if chains and chains.GetPreview then
        local level=UnitLevel and UnitLevel("player") or nil
        return chains:GetPreview(questID,level,maxCount)
    end
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

-- Conservative neighboring-zone suggestions, not a world-wide speedrun
-- ranking. No invented road paths or impossible cross-continent waypoints.
-- A zone is suggested only when the bundled catalog has eligible quest
-- starters on that map. Zone links are hand-reviewed geographic adjacency.
local neighboringZones = {
    [1411]={1413},       -- Durotar -> Barrens
    [1412]={1413},       -- Mulgore -> Barrens
    [1420]={1421},       -- Tirisfal -> Silverpine
    [1429]={1436,1433},  -- Elwynn -> Westfall / Redridge
    [1426]={1432},       -- Dun Morogh -> Loch Modan
    [1438]={1439},       -- Teldrassil -> Darkshore
    [1413]={1442,1440,1441}, -- Barrens -> Stonetalon / Ashenvale / Thousand Needles
    [1421]={1424},       -- Silverpine -> Hillsbrad
    [1436]={1431,1433},  -- Westfall -> Duskwood / Redridge
    [1433]={1431},       -- Redridge -> Duskwood
    [1432]={1437,1418},  -- Loch Modan -> Wetlands / Badlands
    [1439]={1440},       -- Darkshore -> Ashenvale
    [1440]={1442,1448},  -- Ashenvale -> Stonetalon / Felwood
    [1442]={1443},       -- Stonetalon -> Desolace
    [1441]={1444,1446},  -- Thousand Needles -> Feralas / Tanaris
    [1424]={1417,1416},  -- Hillsbrad -> Arathi / Alterac
    [1437]={1417},       -- Wetlands -> Arathi
    [1431]={1434,1430},  -- Duskwood -> Stranglethorn / Deadwind
    [1418]={1427},       -- Badlands -> Searing Gorge
    [1443]={1444},       -- Desolace -> Feralas
    [1444]={1446},       -- Feralas -> Tanaris
    [1446]={1449},       -- Tanaris -> Un'Goro
    [1448]={1452},       -- Felwood -> Winterspring
    [1427]={1428},       -- Searing Gorge -> Burning Steppes
    [1422]={1423},       -- Western -> Eastern Plaguelands
    [1449]={1451},       -- Un'Goro -> Silithus
}
local zoneLabels = {
    [1413]="The Barrens", [1421]="Silverpine Forest", [1436]="Westfall",
    [1433]="Redridge Mountains", [1432]="Loch Modan", [1439]="Darkshore",
    [1442]="Stonetalon Mountains", [1440]="Ashenvale", [1441]="Thousand Needles",
    [1424]="Hillsbrad Foothills", [1431]="Duskwood", [1437]="Wetlands",
    [1418]="Badlands", [1448]="Felwood", [1443]="Desolace",
    [1444]="Feralas", [1446]="Tanaris", [1417]="Arathi Highlands",
    [1416]="Alterac Mountains", [1434]="Stranglethorn Vale",
    [1430]="Deadwind Pass", [1427]="Searing Gorge", [1449]="Un'Goro Crater",
    [1452]="Winterspring", [1428]="Burning Steppes",
    [1423]="Eastern Plaguelands", [1451]="Silithus",
}
local zonesMemo = {}

function Planner:GetNextZones(currentMap, level, active, maxResults)
    local lib = provider()
    local travel = _G.ForeverQuestTravel
    local reachable = travel and travel:GetReachable(currentMap, 2) or nil
    local neighbors = neighboringZones[currentMap]
    if not lib or not level or (not reachable and not neighbors) then return {} end
    local ids = {}
    for id in pairs(active or {}) do ids[#ids+1] = id end
    table.sort(ids)
    local key = tostring(currentMap) .. ":" .. tostring(level)
        .. ":" .. table.concat(ids, ",") .. ":" .. tostring(UnitFactionGroup
            and UnitFactionGroup("player") or "?")
        .. ":" .. tostring(UnitRace and select(3, UnitRace("player")) or "?")
        .. ":" .. tostring(UnitClass and select(3, UnitClass("player")) or "?")
    if zonesMemo.key == key then return zonesMemo.options end

    -- Count quest opportunities, but rank zones by level-appropriate work.
    -- A low-level zone with dozens of trivial quests must not crowd out
    -- a zone with fewer useful quests at the player's current level.
    local eligibleZones, travelHints, relevantZones = {}, {}, {}
    if reachable then
        for _, info in ipairs(reachable) do
            eligibleZones[info.mapID] = 0
            travelHints[info.mapID] = info
        end
    else
        for _, id in ipairs(neighbors or {}) do
            eligibleZones[id] = 0
            travelHints[id] = {mapID=id,hops=1,via=id,path={currentMap,id}}
        end
    end
    local maps = zoneMap(lib)
    local raceID = UnitRace and select(3, UnitRace("player"))
    local classID = UnitClass and select(3, UnitClass("player"))
    local raceBit = lib.Enum and lib.Enum.raceMaskById
        and lib.Enum.raceMaskById[raceID]
    local classBit = type(classID) == "number" and (2 ^ (classID - 1)) or nil

    local valid, all = pcall(lib.Quest.GetAllIds)
    if not valid or type(all) ~= "table" then return {} end
    for _, id in ipairs(all) do
        if eligible(lib, id, level, active or {}, raceBit, classBit) then
            local starters = get(lib.Quest, id, "startedBy")
            local seenZones = {}
            if type(starters) == "table" then
                for _, entry in ipairs({
                    {db=lib.Npc, ids=starters[1], kind="NPC"},
                    {db=lib.Object, ids=starters[2], kind="object"},
                }) do
                    if type(entry.ids) == "table" then
                        for _, entityID in ipairs(entry.ids) do
                            if FriendlyQuestGiver(entry.db,entityID,entry.kind) then
                                local spawns = get(entry.db,entityID,"spawns")
                                if type(spawns) == "table" then
                                    for area in pairs(spawns) do
                                        local destination = maps[area] or area
                                        if eligibleZones[destination] ~= nil then
                                            seenZones[destination] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local questLevel = tonumber(get(lib.Quest, id, "questLevel"))
            -- The bundled catalog is provisional; unknown quest levels
            -- remain possible but receive less weight than known matches.
            local weight = 0.4
            if questLevel and questLevel > 0 then
                local gap = level - questLevel
                if gap >= 0 and gap <= 5 then
                    weight = 1
                elseif gap <= 10 and gap > 5 then
                    weight = 0.6
                elseif gap > 10 then
                    weight = 0.15
                elseif gap < 0 then
                    -- Quests above character level are never automatically
                    -- recommended, even if the requiredLevel permits them.
                    weight = 0
                end
            end
            for dest in pairs(seenZones) do
                if weight > 0 then
                    eligibleZones[dest] = eligibleZones[dest] + 1
                    relevantZones[dest] = (relevantZones[dest] or 0) + weight
                end
            end
        end
    end
    local options = {}
    for id, count in pairs(eligibleZones) do
        if count > 0 then
            local name = zoneLabels[id] or ("Map " .. id)
            if C_Map and type(C_Map.GetMapInfo) == "function" then
                local ok, info = pcall(C_Map.GetMapInfo, id)
                if ok and type(info) == "table"
                    and type(info.name) == "string" and info.name ~= "" then
                    name = info.name
                end
            end
            local hint = travelHints[id] or {}
            local hops = hint.hops or 1
            options[#options+1] = {
                mapID=id, name=name, possibleQuests=count,
                relevantScore=relevantZones[id] or 0,
                hops=hops, via=hint.via,
                handoff=travel and travel:DescribeHandoff(hint, zoneLabels)
                    or "Neighboring zone",
                -- A zone a single hop away generally beats a remote zone
                -- with only a couple more possible quests.
                merit=(relevantZones[id] or 0) / (hops * hops),
                source="bundled-catalog-provisional",
            }
        end
    end
    table.sort(options,function(a,b)
        if a.merit == b.merit then
            if a.hops == b.hops then return a.mapID < b.mapID end
            return a.hops < b.hops
        end
        return a.merit > b.merit
    end)
    zonesMemo = {key=key, options=options}
    return options
end

function Planner:Available() return provider() ~= nil end
function Planner:Status() return cache.status end

function Planner:Invalidate()
    zonesMemo = {}
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
    -- Prefer a productive quest hub over an isolated starter at nearly the
    -- same distance. This is a local pickup *ranking*, not a claim that the
    -- catalog's inherited spawn points are confirmed in Forever.
    -- A distant village cannot outrank a nearby starter on hub size alone.
    for _, entry in ipairs(ranked) do
        local neighbors = 0
        for _, other in ipairs(ranked) do
            if entry ~= other then
                local dx = entry.item.x - other.item.x
                local dy = entry.item.y - other.item.y
                if dx * dx + dy * dy <= 0.018 * 0.018 then
                    neighbors = neighbors + 1
                end
            end
        end
        entry.hubCount = 1 + neighbors
        entry.rankDistance = entry.distance - math.min(3, neighbors) * 0.008
    end
    table.sort(ranked, function(a, b)
        if a.rankDistance == b.rankDistance then
            if a.distance == b.distance then
                return a.item.questID < b.item.questID
            end
            return a.distance < b.distance
        end
        return a.rankDistance < b.rankDistance
    end)
    local out = {}
    for i = 1, math.min(maxResults or 5, #ranked) do
        local copy = {}
        for key, value in pairs(ranked[i].item) do copy[key] = value end
        copy.distance = ranked[i].distance
        copy.hubCount = ranked[i].hubCount
        out[#out+1] = copy
    end
    return out
end

function Planner:Scan(mapID, level, active, force)
    local lib = provider()
    if not lib or not mapID or not level then
        cache.status = lib and "Map not available" or "Bundled quest catalog not loaded"
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
        cache.status = "Bundled quest index unavailable"
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
                local Knowledge = _G.ForeverQuestKnowledge
                local learned = Knowledge and Knowledge:Get(_G.ForeverQuestDB,"pickup",id)
                if learned and learned.mapID == mapID then
                    start = start or {
                        questID=id,mapID=mapID,kind="previously observed starter",
                    }
                    start.x, start.y = learned.x, learned.y
                    start.confidence = "account-observed"
                end
                if start then
                    start.name = name
                    start.questLevel = get(lib.Quest, id, "questLevel")
                    start.suggestedGroup = get(lib.Quest, id, "suggestedGroup")
                    start.source = start.confidence == "account-observed"
                        and "Observed on this account"
                        or "ForeverQuest bundled Classic/Forever baseline"
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
