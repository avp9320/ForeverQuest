-- ForeverQuest route decision layer.
-- Keep preferences/risk/quest-chain value separate from geometry. Every
-- candidate is advisory: the built-in Classic baseline is not live truth.
local Strategy = {}
_G.ForeverQuestStrategy = Strategy

local function questField(id, field)
    local db = _G.ForeverQuestCatalog and _G.ForeverQuestCatalog.Quest
    if not db or not db.Get or type(id) ~= "number" then return nil end
    local ok, value = pcall(db.Get, id, field)
    return ok and value or nil
end

local function chainTargets(id)
    local chains = _G.ForeverQuestChains
    if chains and chains.GetNextIDs then
        return chains:GetNextIDs(id)
    end
    local candidates, seen = {}, {}
    local nextID = questField(id, "nextQuestInChain")
    if type(nextID) == "number" and nextID > 0 then
        candidates[#candidates+1] = nextID
        seen[nextID] = true
    end
    local children = questField(id, "childQuests")
    if type(children) == "table" then
        for _, child in ipairs(children) do
            if type(child) == "number" and child > 0 and not seen[child] then
                candidates[#candidates+1] = child
                seen[child] = true
            end
        end
    end
    return candidates
end

function Strategy:ChainValue(questID, level)
    local direct, nearFuture = 0, 0
    for _, following in ipairs(chainTargets(questID)) do
        local required = questField(following, "requiredLevel")
        local qlevel = questField(following, "questLevel")
        if type(required) ~= "number" then required = 1 end
        -- A low-level character should not detour to unlock a chain they
        -- cannot meaningfully use for many levels.
        if required <= (level or 1) + 3 then
            local withinLevel = type(qlevel) ~= "number"
                or qlevel <= (level or 1) + 6
            if withinLevel then direct = direct + 1 end
        elseif required <= (level or 1) + 8 then
            nearFuture = nearFuture + 1
        end
    end
    return direct, nearFuture
end

function Strategy:Assess(stop, opts)
    opts = opts or {}
    if not stop then return 0, "Unknown stop" end
    local id = stop.questID
    if opts.avoided and opts.avoided[id] then
        return -1000, "Manually avoided quest"
    end
    local level = tonumber(opts.level) or 1
    local mode = opts.mode or "balanced"
    local qlevel = tonumber(questField(id, "questLevel"))
    local group = tonumber(stop.suggestedGroup) or 0
    local elite = stop.isElite == true
    local gap = qlevel and qlevel - level or 0
    local modifier = 0
    local details = {}

    if gap > 4 then
        modifier = modifier - math.min(0.23, (gap - 4) * 0.038)
        details[#details+1] = "Higher-level quest; may be unsafe"
    elseif gap < -6 and stop.kind ~= "turnin" then
        modifier = modifier - 0.045
        details[#details+1] = "Low-level quest"
    end
    if group > 1 or elite then
        local members = math.max(1, tonumber(opts.groupSize) or 1)
        if members >= math.max(2, math.min(5, group)) then
            modifier = modifier - 0.025
            details[#details+1] = "Group quest; party may help"
        else
            modifier = modifier - 0.23
            details[#details+1] = "Group/elite quest; caution solo"
        end
    end
    if stop.kind ~= "turnin" then
        local classMask = tonumber(questField(id,"requiredClasses"))
        if classMask and classMask > 0 then
            modifier = modifier + 0.027
            details[#details+1] = "Class-specific quest"
        end
    end

    local unlocks, later = self:ChainValue(id, level)
    if stop.kind == "turnin" then
        modifier = modifier + math.min(0.085, unlocks * 0.028)
        if unlocks > 0 then
            details[#details+1] = "Turn-in unlocks possible follow-up quests"
        end
    elseif stop.kind == "objective" then
        modifier = modifier + math.min(0.036, unlocks * 0.012)
        if unlocks > 0 then
            details[#details+1] = "Progresses a useful quest chain"
        end
    elseif stop.kind == "pickup" then
        modifier = modifier + math.min(0.025, unlocks * 0.007)
    end

    -- QuestieDB knows a subset of quests deliberately designed as a
    -- shared objective group. Completing these while several are active
    -- reduces return trips without claiming identical spawn positions.
    local inGroup = questField(id,"inGroupWith")
    if type(inGroup)=="table" and type(opts.active)=="table"
        and stop.kind=="objective" then
        local overlap=0
        for _,other in ipairs(inGroup) do
            if opts.active[other] then overlap=overlap+1 end
        end
        if overlap>0 then
            modifier=modifier+math.min(.045,overlap*.018)
            details[#details+1]="Other active quests share this quest group"
        end
    end
    if stop.kind=="pickup" then
        local breadcrumb=tonumber(questField(id,"breadcrumbForQuestId"))
        if breadcrumb and breadcrumb>0 then
            modifier=modifier-.025
            details[#details+1]="Optional breadcrumb to another quest"
        end
    end

    if mode == "fast" then
        -- Fewer speculative pickups; prioritize known work and turn-ins.
        if stop.kind == "pickup" then modifier = modifier - 0.045 end
        if stop.kind == "objective" then modifier = modifier + 0.025 end
        if gap < -3 and stop.kind ~= "turnin" then modifier = modifier - 0.03 end
    elseif mode == "complete" then
        -- Still avoid suicidal quests, but favor collecting optional pickups.
        if stop.kind == "pickup" then modifier = modifier + 0.032 end
        if stop.kind == "turnin" then modifier = modifier + 0.015 end
    end
    if #details == 0 then
        details[1] = stop.kind == "pickup" and "Possible unaccepted quest"
            or stop.kind == "turnin" and "Quest completed; ready to turn in"
            or "Unfinished accepted objective"
    end
    return modifier, table.concat(details, "; "), {
        directFollowups = unlocks, laterFollowups = later,
        levelGap = gap, group = group,
    }
end

function Strategy:ShouldAvoidAuto(stop, opts)
    local adjustment = self:Assess(stop, opts)
    return adjustment <= -0.3
end

function Strategy:Explain(stop, opts)
    local delta, reason, details = self:Assess(stop, opts)
    local mode = opts and opts.mode or "balanced"
    local sign = delta > 0 and "+" or ""
    return string.format("%s (route preference: %s; modifier %s%.3f)",
        reason, mode, sign, delta)
end
