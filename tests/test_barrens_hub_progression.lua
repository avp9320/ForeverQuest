-- Standalone regression: lua tests/test_barrens_hub_progression.lua
-- Run from repository root. No WoW globals required.
dofile("Route.lua")
local route = assert(_G.ForeverQuestRoute)
local pickups = {
    {questID=900001,name="Crossroads test",mapID=1413,x=.52,y=.30},
    {questID=900002,name="Taurajo test",mapID=1413,x=.45,y=.59},
}
local function first(level, mapID)
    local options = {level=level}
    local plan = route:Build({}, pickups, mapID or 1413, .49, .45, options)
    return plan.stops[1] and plan.stops[1].questID
end
assert(first(12)==900001, "early Barrens should favor Crossroads")
assert(first(23)==900002, "later Barrens should favor Camp Taurajo")
assert(first(12,1440)==nil, "Barrens hub pickups must not leak to Ashenvale")
-- The hub bias must not make above-level pickup data safe. Eligibility is
-- applied by Strategy when loaded; this test only checks geographic ranking.
print("Barrens hub progression regression passed")
