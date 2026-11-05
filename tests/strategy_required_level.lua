-- Run from repository root with: lua tests/strategy_required_level.lua
-- Pure Lua regression: no WoW client needed.
local facts = {
    [100] = {questLevel=9,requiredLevel=15},
    [101] = {questLevel=12,requiredLevel=10,suggestedGroup=3},
    [102] = {questLevel=12,requiredLevel=10},
}
_G.ForeverQuestCatalog = {Quest = {Get = function(id, field)
    return facts[id] and facts[id][field]
end}}
dofile("Strategy.lua")
local strategy = _G.ForeverQuestStrategy
local function eligible(id, kind, level, extra)
    local stop = {questID=id,kind=kind}
    for k,v in pairs(extra or {}) do stop[k]=v end
    return strategy:IsAutoEligible(stop,{level=level,groupSize=1})
end
assert(not eligible(100,"pickup",12), "minimum-level gate ignored")
assert(not eligible(100,"objective",12), "accepted quest minimum-level gate ignored")
assert(eligible(100,"pickup",15), "unlocked quest incorrectly blocked")
assert(not eligible(101,"pickup",12), "catalog group flag ignored")
assert(not eligible(101,"objective",12), "accepted catalog group flag ignored")
assert(eligible(102,"pickup",12), "safe solo quest incorrectly blocked")
assert(eligible(100,"turnin",12), "completed turn-in must remain eligible")
print("strategy minimum-level/group safety: OK")
