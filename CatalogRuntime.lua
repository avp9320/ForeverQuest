-- ForeverQuest built-in fact catalog runtime.
-- CatalogData.lua is generated at package time, under this same addon folder.
-- Never requires Questie or QuestieDB to be enabled.
local data = _G.ForeverQuestCatalogData
if type(data) ~= "table" or type(data.Quest) ~= "table" then
    _G.ForeverQuestCatalog = nil
    return
end

local function entity(records)
    records = records or {}
    return {
        Get = function(id, field)
            local row = records[id]
            return row and row[field] or nil
        end,
        Exists = function(id)
            return records[id] ~= nil
        end,
    }
end

local Quest = entity(data.Quest)
local ids = {}
for id in pairs(data.Quest) do
    if type(id) == "number" then ids[#ids + 1] = id end
end
table.sort(ids)
Quest.GetAllIds = function() return ids end

_G.ForeverQuestCatalog = {
    Quest = Quest,
    Npc = entity(data.Npc),
    Object = entity(data.Object),
    Item = entity(data.Item),
    AreaToMap = data.AreaToMap or {},
    Enum = {
        raceMaskById = {
            [1] = 1,       -- Human
            [2] = 2,       -- Orc
            [3] = 4,       -- Dwarf
            [4] = 8,       -- Night Elf
            [5] = 16,      -- Undead
            [6] = 32,      -- Tauren
            [7] = 64,      -- Gnome
            [8] = 128,     -- Troll
            -- Other client-defined races must be explicitly verified.
        },
    },
    flavor = { expansion = "Forever" },
    provenance = "QuestieDB Forever factual snapshot v1.0.10; see DATA_SOURCES.md",
    Counts = {
        quests = #ids,
    },
}

-- Drop the temporary top-level reference after adapters have been built.
-- The entity closures hold the facts; this saves a global lookup elsewhere.
_G.ForeverQuestCatalogData = nil
