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
-- A distant, high-density pickup cluster can be eligible because it lies
-- along an accepted objective. It must not steal the initial collection
-- phase from the quest giver standing beside the player.
local distantCluster = {
    {questID=701,name="Local starter",mapID=1411,x=.40,y=.50},
}
for i=1,7 do
    distantCluster[#distantCluster+1] = {
        questID=710+i,name="Remote starter "..i,mapID=1411,
        x=.75+(i%3)*.002,y=.75+math.floor(i/3)*.002,
    }
end
local circuit = route:Build({
    {questID=700,title="Remote objective",complete=false,
        waypointMap=1411,waypointX=.75,waypointY=.75,questLevel=10},
},distantCluster,1411,.40,.50,{level=10})
assert(circuit.stops[1] and circuit.stops[1].questID==701,
    "nearby starter must win initial pickup phase over distant cluster")
assert(circuit.stops[2] and circuit.stops[2].kind=="objective",
    "after local collection, proceed to the accepted objective")

print("hub pickup phase: OK")
