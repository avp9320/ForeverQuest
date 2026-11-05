-- Run from repository root: lua tests/test_zone_progression.lua
-- Pure Lua smoke/regression coverage; no WoW client required.
dofile("Travel.lua")
local travel = assert(_G.ForeverQuestTravel)
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
-- Low-level Horde should progress into Barrens, not high-level zones.
eq(travel:ProgressionWeight(1413, 12, "Horde"), 1, "Barrens at 12")
eq(travel:ProgressionWeight(1446, 12, "Horde"), 0.12, "Tanaris at 12")
-- Higher levels should not be dragged back to starter zones.
eq(travel:ProgressionWeight(1411, 35, "Horde"), 0.22, "Durotar at 35")
eq(travel:ProgressionWeight(1443, 35, "Horde"), 1, "Desolace at 35")
eq(travel:ProgressionWeight(1451, 58, "Horde"), 1, "Silithus at 58")
-- Unknown/Alliance-only zones are deprioritized, not falsely advertised.
eq(travel:ProgressionWeight(1429, 12, "Horde"), 0.25, "Elwynn for Horde")
eq(travel:ProgressionWeight(1429, 12, "Alliance"), 1, "No Horde bias for Alliance")
-- No phantom walking route across continents.
assert(travel:GetHandoff(1413, 1421) == nil, "Barrens to Silverpine not walkable")
assert(travel:GetHandoff(1411, 1413), "Durotar to Barrens connected")
print("zone progression checks passed")
