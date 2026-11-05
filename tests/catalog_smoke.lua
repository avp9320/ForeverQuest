-- Standalone packaged-catalog smoke test, no other addon installed.
assert(io.open("CatalogData.lua","rb"),"CatalogData.lua not generated")
dofile("CatalogData.lua")
dofile("CatalogRuntime.lua")
dofile("QuestData.lua")
local db = _G.ForeverQuestCatalog
assert(type(db)=="table","ForeverQuestCatalog not initialized")
assert(_G.LibQuestieDB == nil,"unexpected dependence on QuestieDB")
assert(db.flavor.expansion=="Forever","wrong catalog flavor")
local ids=db.Quest.GetAllIds()
assert(#ids>3000,"too few quest entries: "..#ids)
local first=db.Quest.Get(6,"name")
assert(type(first)=="string" and #first>0,"missing known Classic quest")
assert(db.AreaToMap[14]==1411,"Durotar area/map conversion")
local npc=db.Npc.Get(823,"spawns")
assert(type(npc)=="table" and type(npc[12])=="table","quest giver coordinates missing")
local n=0
for _ in pairs(db.AreaToMap) do n=n+1 end
assert(n>200,"too few area mapping entries")
assert(db.Quest.Get(99999999,"name")==nil,"unknown quest should not exist")
local triggers=0
for _, questID in ipairs(ids) do
    if type(db.Quest.Get(questID,"triggerPoints")) == "table" then
        triggers=triggers+1
    end
end
assert(triggers>0,"no exploration trigger coordinates in bundled quest catalog")
-- Run the actual planner against the bundled data, not a separately
-- installed addon. The mock character is an Orc warrior in Durotar.
C_Map = {
    GetPlayerMapPosition = function(id, unit)
        return {GetXY = function() return 0.43, 0.68 end}
    end,
}
C_Timer = { After = function(_, action) action() end }
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return false end }
UnitRace = function() return "Orc", "Orc", 2 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
dofile("QuestPlanner.lua")
local planner = _G.ForeverQuestPlanner
assert(planner:Available(), "standalone planner not connected")
planner:Scan(1411, 5, {})
local options = planner:GetNearby(1411, 15)
assert(#options > 0, "no starter quests found in Durotar from bundled data")
assert(options[1].name and options[1].mapID == 1411,
    "bad candidate quest mapping")
assert(not _G.LibQuestieDB, "external QuestieDB runtime must not be loaded")

-- A published Forever pickup landmark should survive the standalone
-- catalog and planner path, including a useful NPC name. No external
-- addon or hardcoded generic tracker location.
-- A curated Razor Hill landmark must be checked with an eligible character,
-- not the level-5 starter used for the Valley of Trials scan above. Simulate
-- completed prerequisites so the test isolates location provenance.
local originalCompletion = C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id ~= 791 end
local landmarkLevel = math.max(5,
    tonumber(db.Quest.Get(791, "requiredLevel")) or 5,
    tonumber(db.Quest.Get(791, "questLevel")) or 5)
planner:Scan(1411, landmarkLevel, {})
local known
for _, candidate in ipairs(planner:GetNearby(1411,500)) do
    if candidate.questID == 791 then known=candidate; break end
end
assert(known and math.abs(known.x-.499)<.002
    and math.abs(known.y-.404)<.002,
    "Carry Your Weight starter should use published Forever waypoint")
C_QuestLog.IsQuestFlaggedCompleted = originalCompletion
assert(known.giverName=="Furl Scornbrow"
    and known.area:find("watchtower",1,true),
    "Carry Your Weight starter should identify the landmark")
print(string.format("Standalone catalog integration passed: %d quests, %d areas, %d exploration triggers, %d nearby candidates",#ids,n,triggers,#options))
