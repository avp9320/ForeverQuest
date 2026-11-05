-- Run from the repository root: lua tests/unsafe_objective_hub_fallback.lua
dofile("Strategy.lua")
dofile("Route.lua")
local strategy = _G.ForeverQuestStrategy
local route = _G.ForeverQuestRoute
local unsafe = {
  questID = 990001, title = "Unsafe elite", questLevel = 40,
  complete = false, waypointMap = 1413, waypointX = .50, waypointY = .50,
  isElite = true, suggestedGroup = 3,
}
local safePickup = {
  questID = 990002, name = "Appropriate hub quest", questLevel = 15,
  mapID = 1413, x = .62, y = .38,
}
local options = {level = 15, groupSize = 1}
assert(strategy:IsAutoEligible({kind="objective",questID=990001,questLevel=40,isElite=true},options)==false)
local plan = route:Build({unsafe},{safePickup},1413,.50,.50,options)
assert(plan.totalCandidates == 1, "unsafe objective must not suppress distant safe hub")
assert(#plan.stops > 0 and plan.stops[1].questID == 990002, "safe hub should be recommended")
for _, stop in ipairs(plan.stops) do
  assert(stop.questID ~= 990001, "unsafe objective leaked into AUTO")
end
local noPickup = route:Build({unsafe},{},1413,.50,.50,options)
assert(#noPickup.stops == 0, "no eligible work should produce no route")
print("unsafe_objective_hub_fallback: OK")
