-- Player-facing ground-object guidance without claiming exact respawns.
dofile("ObjectiveHints.lua")
local hints = _G.ForeverQuestObjectiveHints
assert(hints:Get({kind="objective",questID=815}).search:find("bases of trees",1,true))
assert(hints:Get({kind="objective",questID=815}).crowd:find("Other players",1,true))
assert(hints:Get({kind="objective",questID=815}).source:find("observation",1,true))
assert(hints:Get({kind="objective",questID=901,sourceKind="object"}).search:find("ground",1,true))
assert(hints:Get({kind="objective",questID=901,sourceKind="item drop object"})~=nil)
assert(hints:Get({kind="objective",questID=901,sourceKind="enemy"})==nil)
assert(hints:Get({kind="turnin",questID=815})==nil)
assert(hints:Get({kind="pickup",questID=815})==nil)
assert(hints:Get(nil)==nil)
print("ForeverQuest objective search-hint tests passed")
