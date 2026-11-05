-- Standalone Lua 5.1 regression for multi-NPC pickup hubs.
dofile("Route.lua")
local route = assert(_G.ForeverQuestRoute)
local quests = {
    {questID=100,title="Kill nearby enemies",complete=false,
     waypointMap=1413,waypointX=.52,waypointY=.52},
}
local pickups = {
    {questID=201,name="First offer",mapID=1413,x=.500,y=.500,giverName="NPC A"},
    {questID=202,name="Second offer",mapID=1413,x=.510,y=.506,giverName="NPC B"},
    {questID=203,name="Distant offer",mapID=1413,x=.75,y=.75,giverName="NPC C"},
}
local plan = route:Build({}, pickups, 1413, .49, .49, {level=15})
assert(plan.totalCandidates == 3)
assert(plan.totalLocations == 2, "nearby NPCs form one hub")
assert(plan.stops[1].kind == "pickup")
assert(plan.stops[1].pickupCount == 2, "collect two quests at one hub")
assert(#plan.stops[1].pickupIDs == 2)
local other = route:Build(quests, pickups, 1413, .49, .49, {level=15})
assert(other.stops[1].kind == "pickup", "nearby pickup before objective")
assert(other.stops[1].pickupCount == 2)
local seenObjective = false
for _, stop in ipairs(other.stops) do
    if stop.kind == "objective" then seenObjective = true end
end
assert(seenObjective, "objectives remain in circuit")
print("hub pickup regression passed")
