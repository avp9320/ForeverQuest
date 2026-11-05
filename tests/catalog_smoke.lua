-- Standalone packaged-catalog smoke test, no other addon installed.
assert(io.open("CatalogData.lua","rb"),"CatalogData.lua not generated")
dofile("CatalogData.lua")
dofile("CatalogRuntime.lua")
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
print(string.format("Standalone catalog tests passed: %d quests, %d areas",#ids,n))
