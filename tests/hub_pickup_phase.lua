-- Standalone Lua 5.1 regression for hub pickup phase ordering.
-- Run from repository root: lua tests/hub_pickup_phase.lua
dofile("Route.lua")
local route = assert(_G.ForeverQuestRoute)
local quests = {
    {questID=501,title="Active objective",complete=false,
        waypointMap=1411,waypointX=.47,waypointY=.50,questLevel=10},
}
local pickups = {
    {questID=601,name="First hub giver",mapID=1411,x=.40,y=.50},
    {questID=602,name="Second hub giver",mapID=1411,x=.425,y=.50},
    {questID=603,name="Distant giver",mapID=1411,x=.80,y=.80},
}
local plan = route:Build(quests,pickups,1411,.398,.50,{level=10})
assert(#plan.stops >= 3,"expected two pickup hubs and an objective")
assert(plan.stops[1].kind=="pickup","first stop should collect nearby quests")
assert(plan.stops[2].kind=="pickup","second nearby giver must be collected before objectives")
assert(plan.stops[3].kind=="objective","objective follows local pickup circuit")
for _,stop in ipairs(plan.stops) do
    assert(stop.questID~=603,"distant speculative pickup must not hijack active circuit")
end
print("hub pickup phase: OK")
