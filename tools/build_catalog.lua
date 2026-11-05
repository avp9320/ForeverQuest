-- tools/build_catalog.lua
-- Produce a *facts-only* ForeverQuest snapshot from a pinned QuestieDB revision.
-- Uses only names, identifiers, eligibility fields and approximate coordinates;
-- no external quest descriptions, UI assets or addon code are distributed.
-- Original factual source and license/provenance: see DATA_SOURCES.md.
-- Usage: lua5.1 tools/build_catalog.lua .catalog_source CatalogData.lua
local source = assert(arg[1], "missing source directory")
local target = assert(arg[2], "missing output file")
local raw = {}
local zone = {private = {}}
QuestieLoader = {
    ImportModule = function(_, name)
        if name == "QuestieDB" then return raw end
        if name == "ZoneDB" then return zone end
        error("unsupported module " .. tostring(name))
    end,
}
local function loadSource(path)
    local chunk, err = loadfile(source .. "/" .. path)
    assert(chunk, err)
    chunk()
end
for _, entity in ipairs({"Quest","Npc","Object","Item"}) do
    loadSource("data/Forever/forever" .. entity .. "DB.lua")
end
loadSource("support/Forever/Zones/areaIdToUiMapId.lua")
local function decode(str)
    assert(type(str) == "string", "missing Questie data literal")
    local chunk, err = loadstring(str)
    assert(chunk, err)
    local ok, value = pcall(chunk)
    assert(ok and type(value) == "table", "failed decoding source table")
    return value
end
local qdb = decode(raw.questData)
local ndb = decode(raw.npcData)
local odb = decode(raw.objectData)
local idb = decode(raw.itemData)
local maps = decode(zone.private.areaIdToUiMapId)
local overrides = decode(zone.private.areaIdToUiMapIdOverride)
for id, map in pairs(overrides) do maps[id] = map end

local function valid(t) return type(t) == "table" end
local function field(row, keys, key)
    return valid(row) and type(keys) == "table" and row[keys[key]] or nil
end

local QFields = {
    "name", "startedBy", "finishedBy", "requiredLevel", "questLevel",
    "requiredRaces", "requiredClasses", "preQuestGroup", "preQuestSingle",
    "childQuests", "exclusiveTo", "requiredSkill", "requiredMinRep",
    "requiredMaxRep", "parentQuest", "requiredSpell", "requiredSpecialization",
    "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith",
    "requiredRanks", "disabledByQuest", "nextQuestInChain", "specialFlags",
}
local quests, npcs, objects, items = {}, {}, {}, {}
local neededNpc, neededObject, neededItem = {}, {}, {}

local function collectIDs(t, dest)
    if not valid(t) then return end
    for _, id in ipairs(t) do
        if type(id) == "number" and id > 0 then dest[id] = true end
    end
end

for id, row in pairs(qdb) do
    local name = field(row, raw.questKeys, "name")
    if type(id) == "number" and type(name) == "string" and name ~= "" then
        local record = {}
        for _, key in ipairs(QFields) do
            local val = field(row, raw.questKeys, key)
            if val ~= nil and val ~= 0 and (not valid(val) or next(val)) then
                record[key] = val
            end
        end
        -- Some quests finish by discovering a location rather than looting
        -- or killing something. Keep only approximate trigger coordinates,
        -- never the external quest description or guide wording.
        local trigger = field(row, raw.questKeys, "triggerEnd")
        if valid(trigger) and valid(trigger[2]) then
            local areaPoints = {}
            for area, points in pairs(trigger[2]) do
                if maps[area] and valid(points) then
                    local output = {}
                    for i = 1, math.min(#points, 4) do
                        local xy = points[i]
                        if valid(xy) and type(xy[1]) == "number"
                            and type(xy[2]) == "number"
                            and xy[1] >= 0 and xy[1] <= 100
                            and xy[2] >= 0 and xy[2] <= 100 then
                            output[#output + 1] = {
                                math.floor(xy[1] * 100 + 0.5) / 100,
                                math.floor(xy[2] * 100 + 0.5) / 100,
                            }
                        end
                    end
                    if #output > 0 then areaPoints[area] = output end
                end
            end
            if next(areaPoints) then record.triggerPoints = areaPoints end
        end
        -- Avoid distributing quest prose. Objectives use only IDs, not text.
        local objective = field(row, raw.questKeys, "objectives")
        if valid(objective) then
            local subset = {}
            for group = 1, 3 do
                local list = objective[group]
                if valid(list) then
                    local ids = {}
                    for _, entry in ipairs(list) do
                        local entityID = valid(entry) and entry[1] or entry
                        if type(entityID) == "number" and entityID > 0 then
                            ids[#ids + 1] = {entityID}
                            if group == 1 then neededNpc[entityID] = true
                            elseif group == 2 then neededObject[entityID] = true
                            else neededItem[entityID] = true end
                        end
                    end
                    if #ids > 0 then subset[group] = ids end
                end
            end
            if next(subset) then record.objectives = subset end
        end
        local started = record.startedBy
        local finished = record.finishedBy
        if valid(started) then
            collectIDs(started[1], neededNpc)
            collectIDs(started[2], neededObject)
            collectIDs(started[3], neededItem)
        end
        if valid(finished) then
            collectIDs(finished[1], neededNpc)
            collectIDs(finished[2], neededObject)
        end
        quests[id] = record
    end
end

-- Item quests and item-objectives can be sourced from NPCs / objects.
for id in pairs(neededItem) do
    local row = idb[id]
    if valid(row) then
        local record = {name = field(row, raw.itemKeys, "name")}
        for _, key in ipairs({"npcDrops", "objectDrops", "itemDrops"}) do
            local val = field(row, raw.itemKeys, key)
            if valid(val) and #val > 0 then record[key] = val end
        end
        items[id] = record
        collectIDs(record.npcDrops, neededNpc)
        collectIDs(record.objectDrops, neededObject)
    end
end

-- Retain a spatially representative subset, rather than copying a giant
-- exact mob-spawn database into the user's UI addon. Up to 9 per area.
-- The returned points remain *approximate* Classic/Forever guide positions.
local function sampledSpawns(spawns)
    if not valid(spawns) then return nil end
    local result = {}
    for area, points in pairs(spawns) do
        if valid(points) and #points > 0 and maps[area] then
            local list, picked = {}, {}
            local count = math.min(#points, 9)
            for k = 1, count do
                local index = math.floor((k - 1) * (#points - 1) / math.max(1, count - 1) + 1)
                if not picked[index] then
                    local p = points[index]
                    if valid(p) and type(p[1]) == "number" and type(p[2]) == "number"
                        and p[1] >= 0 and p[1] <= 100
                        and p[2] >= 0 and p[2] <= 100 then
                        list[#list + 1] = {
                            math.floor(p[1] * 100 + 0.5) / 100,
                            math.floor(p[2] * 100 + 0.5) / 100,
                        }
                    end
                    picked[index] = true
                end
            end
            if #list > 0 then result[area] = list end
        end
    end
    return next(result) and result or nil
end
for id in pairs(neededNpc) do
    local row = ndb[id]
    if valid(row) then
        local spawns = sampledSpawns(field(row, raw.npcKeys, "spawns"))
        if spawns then
            npcs[id] = {
                name = field(row, raw.npcKeys, "name"),
                spawns = spawns,
                friendlyToFaction = field(row, raw.npcKeys, "friendlyToFaction"),
            }
        end
    end
end
for id in pairs(neededObject) do
    local row = odb[id]
    if valid(row) then
        local spawns = sampledSpawns(field(row, raw.objectKeys, "spawns"))
        if spawns then
            objects[id] = {name = field(row, raw.objectKeys, "name"), spawns = spawns}
        end
    end
end

local function serialize(value, depth)
    depth = depth or 0
    assert(depth < 15, "unexpected data nesting")
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "nil" end
    local entries = {}
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys, function(a,b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
    end)
    for _, key in ipairs(keys) do
        local lhs = type(key) == "string" and key:match("^[%a_][%w_]*$")
            and key or ("[" .. serialize(key, depth+1) .. "]")
        entries[#entries+1] = lhs .. "=" .. serialize(value[key],depth+1)
    end
    return "{" .. table.concat(entries,",") .. "}"
end
local f = assert(io.open(target, "wb"))
f:write("-- GENERATED, do not edit. Factual Classic+Forever baseline.\n")
f:write("-- Source: QuestieDB v1.0.10, pinned SHA in .github/workflows/release.yml.\n")
f:write("-- Standalone snapshot: no other addon is required.\n")
f:write("ForeverQuestCatalogData={\n")
local function writeMap(key, values)
    f:write(key, "={\n")
    local keys = {}
    for id in pairs(values) do keys[#keys+1] = id end
    table.sort(keys)
    for _, id in ipairs(keys) do
        f:write("[", tostring(id), "]=",serialize(values[id]),",\n")
    end
    f:write("},\n")
end
writeMap("Quest",quests)
writeMap("Npc",npcs)
writeMap("Object",objects)
writeMap("Item",items)
writeMap("AreaToMap",maps)
f:write("}\n")
f:close()
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local triggers = 0
for _, quest in pairs(quests) do
    if quest.triggerPoints then triggers = triggers + 1 end
end
print(string.format("FOREVER_CATALOG quests=%d npc=%d objects=%d items=%d areas=%d triggers=%d",
    count(quests),count(npcs),count(objects),count(items),count(maps),triggers))
assert(count(quests) > 3000, "insufficient quest coverage")
assert(count(npcs) > 1000, "insufficient NPC coverage")
assert(count(maps) > 200, "insufficient map coverage")
