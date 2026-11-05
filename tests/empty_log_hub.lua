-- Run with: lua tests/empty_log_hub.lua
-- Offline regression for empty-log hub collection; no WoW client required.
_G.ForeverQuestStrategy = {
    IsAutoEligible = function() return true end,
    Assess = function() return 0, "test" end,
}
dofile("Route.lua")
local route = _G.ForeverQuestRoute
local function pickup(id, x, y)
    return {questID=id, name="Quest "..id, mapID=1413, x=x, y=y,
        confidence="provisional", giverName="Giver "..id}
end
local plan = route:Build({}, {
    pickup(1,.50,.30), pickup(2,.52,.30),
    pickup(3,.80,.80), pickup(4,.82,.80),
},1413,.49,.30,{level=12})
assert(#plan.stops >= 1, "empty quest log must suggest a hub")
for _, stop in ipairs(plan.stops) do
    assert(stop.kind=="pickup", "empty log must only suggest pickups")
    assert(math.sqrt((stop.x-plan.stops[1].x)^2+
        (stop.y-plan.stops[1].y)^2)<=.035,
        "empty-log circuit must not jump to a different hub")
end
local other = route:Build({}, {pickup(3,.80,.80)},1413,.79,.80,{level=12})
assert(#other.stops==1 and other.stops[1].questID==3,
    "a new location must select its own local hub")
print("empty-log hub regression passed")
