-- Small, source-labeled search hints for difficult quest objectives.
-- This is static guidance, not a claim of a guaranteed object spawn.
local Hints = {}
_G.ForeverQuestObjectiveHints = Hints

-- Launch-day first-hand WoW: Forever observations (2026-11-05):
-- https://gitm.gg/guides/wow-forever-break-a-few-eggs/
-- Quest identity / objective confirmed at:
-- https://www.wowhead.com/forever/quest=815/break-a-few-eggs
local known = {
    [815] = {
        search = "Taillasher Eggs are tiny ground objects at the bases of trees near Bloodtalon Taillashers on the Echo Isles. Check several trees.",
        crowd = "Other players may pick up the eggs before you arrive. The arrow marks a search area, not a guaranteed egg spawn.",
        source = "Forever launch-day player observation (2026-11-05); spawns may change.",
    },
}

local groundObject = {
    search = "Look around the marked area for a clickable object on the ground. The marker may indicate an area rather than an exact object.",
    source = "General object-search advice; the specific spawn is unverified.",
}

function Hints:Get(stop)
    if type(stop) ~= "table" or stop.kind ~= "objective" then return nil end
    local guide = known[tonumber(stop.questID)]
    if guide then return guide end
    if stop.sourceKind == "object" or stop.sourceKind == "item drop object" then
        return groundObject
    end
    return nil
end

return Hints
