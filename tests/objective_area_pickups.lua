-- Run from repository root: lua tests/objective_area_pickups.lua
_G.ForeverQuestStrategy = nil
dofile("Route.lua")
local route = _G.ForeverQuestRoute
local active = {{
    questID = 1001, title = "Hunt",
    complete = false,
    goalPoints = {{mapID = 1413, x = .53, y = .50, goalKey = "kill"}},
}}
local pickups = {{
    questID = 1002, name = "Another hunt",
    mapID = 1413, x = .54, y = .50,
}, {
    questID = 1003, name = "Distant starter",
    mapID = 1413, x = .65, y = .50,
}}
local plan = route:Build(active, pickups, 1413, .50, .50, {level = 15})
assert(#plan.stops >= 2, "expected pickup and objective")
assert(plan.stops[1].kind == "pickup", "collect starter by objective first")
assert(plan.stops[1].questID == 1002, "do not detour to distant starter")
assert(plan.stops[2].kind == "objective", "resume accepted objective after pickup")
local noPickup = route:Build(active, {}, 1413, .50, .50, {level = 15})
assert(noPickup.stops[1].kind == "objective", "no pickup: work existing objective")
print("objective-area pickup circuit: ok")
