-- Run from repository root: lua tests/barrens_hub_priority.lua
_G.ForeverQuestStrategy = nil
dofile("Route.lua")
local route = assert(_G.ForeverQuestRoute)
local function pickup(id,x,y)
    return {questID=id,name="Starter "..id,mapID=1413,x=x,y=y,questLevel=10}
end
local function first(level)
    local plan=route:Build({},{
        pickup(101,.52,.30), -- Crossroads
        pickup(102,.48,.38), -- isolated nearer to player
    },1413,.48,.38,{level=level})
    assert(plan.stops[1] and plan.stops[1].kind=="pickup")
    return plan.stops[1].questID
end
assert(first(12)==101,"level 12 should favor Crossroads")
assert(first(30)==102,"level 30 should not get an early hub bonus")
local other=route:Build({},{
    {questID=201,name="Far starter",mapID=1440,x=.52,y=.30},
    {questID=202,name="Near starter",mapID=1440,x=.48,y=.38},
},1440,.48,.38,{level=12})
assert(other.stops[1].questID==202,"Barrens preference must not affect Ashenvale")
print("Barrens hub priority regression passed")
