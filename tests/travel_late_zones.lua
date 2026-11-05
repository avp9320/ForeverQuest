-- Run from repository root with: lua tests/travel_late_zones.lua
_G.C_Map = nil
dofile("Travel.lua")
local travel = assert(_G.ForeverQuestTravel)
local function path(from, to)
    local handoff = travel:GetHandoff(from, to)
    assert(handoff, "No handoff from " .. from .. " to " .. to)
    assert(handoff.path[1] == from and handoff.path[#handoff.path] == to)
    assert(handoff.hops == #handoff.path - 1)
    return handoff
end
assert(path(1420,1422).hops == 1) -- Bulwark
assert(path(1424,1425).hops == 1) -- Hinterlands
assert(path(1430,1435).hops == 1) -- Deadwind -> Swamp
assert(path(1435,1419).hops == 1) -- Swamp -> Blasted Lands
assert(path(1411,1443).hops >= 2) -- Durotar -> Barrens -> Stonetalon -> Desolace
assert(travel:GetHandoff(1411,1420) == nil) -- no invented walkable ocean crossing
assert(travel:ProgressionWeight(1425,45,"Horde") == 1)
assert(travel:ProgressionWeight(1419,50,"Horde") == 1)
assert(travel:ProgressionWeight(1425,20,"Horde") < 1)
print("late-zone handoff regression checks passed")
