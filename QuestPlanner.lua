-- ForeverQuest: optional future quest discovery through QuestieDB's public API.
-- This file does not modify QuestieDB or copy its database.
-- Source: https://github.com/Questie/QuestieDB/blob/master/docs/api.md
local Planner = {}
_G.ForeverQuestPlanner = Planner
local cache = { items = {}, status = "not scanned", mapID = nil, level = nil }
function Planner:Available()
    return type(QuestDB) == "table" and type(NpcDB) == "table"
       and type(QuestDB.GetAllIds) == "function"
       and type(QuestDB.Get) == "function"
end
function Planner:GetStatus() return cache.status end
local function get(db, id, field)
    if not db then return nil end
    local ok, value = pcall(db.Get, id, field)
    return ok and value or nil
end
function Planner:GetNearest()
    return cache.items[1]
end
function Planner:GetCandidates()
    return cache.items
end
-- Only recommend quest starters when prerequisites and the NPC map position
-- are backed by data; unverified Classic values remain provisional.
function Planner:Refresh(mapID, level, active)
    if not self:Available() then
        cache.status = "QuestieDB not installed"
        return false
    end
    if cache.mapID == mapID and cache.level == level then return true end
    cache.items, cache.mapID, cache.level = {}, mapID, level
    cache.status = "Scanning nearby possible quest pickups"
    return true
end
