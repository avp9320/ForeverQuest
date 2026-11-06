-- ForeverQuest route engine.
-- Pure planner: no quest log/UI dependencies, no copied external addon code.
-- Produces a few approximate same-map stops, NOT navigable terrain paths.
-- Treat QuestieDB and Classic-derived positions as provisional.
local Route = {}
_G.ForeverQuestRoute = Route

local function validPoint(mapID, x, y, requiredMap)
    return mapID == requiredMap
        and type(x) == "number" and x >= 0 and x <= 1
        and type(y) == "number" and y >= 0 and y <= 1
end

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function append(all, seen, kind, id, name, mapID, x, y,
    confidence, area, goal)
    local goalKey = goal and goal.goalKey or "main"
    local key = tostring(kind) .. ":" .. tostring(id) .. ":" .. tostring(goalKey)
    if not id or seen[key] or not validPoint(mapID, x, y, all.mapID) then
        return
    end
    local stop = {
        key = key, kind = kind, questID = id, name = name,
        goalKey = goalKey,
        mapID = mapID, x = x, y = y,
        confidence = confidence or "unknown",
        area = area,
        targetName = goal and goal.targetName,
        stepLabel = goal and goal.stepLabel,
        sourceKind = goal and goal.kind,
        waypointSource = goal and goal.waypointSource,
        giverID = kind == "pickup" and goal and goal.giverID or nil,
        giverName = kind == "pickup" and goal and goal.giverName or nil,
        suggestedGroup = goal and goal.suggestedGroup or nil,
        isElite = goal and goal.isElite or nil,
        questLevel = goal and goal.questLevel or nil,
    }
    seen[key] = true
    all[#all + 1] = stop
end

-- Higher value favors unfinished objectives and opportunistic pickups, but
-- a turn-in next to the player still wins over a long cross-zone run.
local VALUE = { objective = 12, pickup = 10, turnin = 8 }
local CLUSTER = 0.035
-- A questing hub may contain several distinct quest givers. Cluster nearby
-- starters into one collection trip, but keep distant villages separate.
-- Map-relative radius is intentionally conservative; not road distance.
local PICKUP_HUB = 0.018

local function groupPickupHubs(candidates)
    local grouped = {mapID = candidates.mapID}
    -- Deterministic grouping regardless of catalog enumeration order.
    local pickups = {}
    for _, candidate in ipairs(candidates) do
        if candidate.kind == "pickup" then
            pickups[#pickups + 1] = candidate
        else
            grouped[#grouped + 1] = candidate
        end
    end
    table.sort(pickups, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return a.questID < b.questID
    end)
    local hubs = {}
    for _, candidate in ipairs(pickups) do
        local hub, bestDistance
        for _, existing in ipairs(hubs) do
            local d = distance(existing.x, existing.y, candidate.x, candidate.y)
            -- Close coordinates do not mean the same NPC. Preserve separate
            -- stops for different known quest givers so the player can collect
            -- every offer in a hub instead of being sent to the wrong NPC.
            -- For missing IDs, use a much tighter proximity threshold; the
            -- catalog may be approximate and should not invent shared givers.
            local sameGiver = candidate.giverID and existing.giverID
                and candidate.giverID == existing.giverID
                and candidate.kind == existing.kind
            -- A missing NPC ID is not evidence that two offers belong to
            -- the same NPC. Only coalesce unknown IDs when BOTH entries
            -- explicitly name the same giver of the same entity type.
            -- Otherwise retain independent collection stops, even when
            -- inherited Classic coordinates happen to overlap.
            local sameNamedGiver = not candidate.giverID
                and not existing.giverID
                and type(candidate.giverName) == "string"
                and candidate.giverName ~= ""
                and candidate.giverName == existing.giverName
                and candidate.sourceKind == existing.sourceKind
            local radius = sameGiver and PICKUP_HUB or 0.002
            if (sameGiver or sameNamedGiver)
                and d <= radius
                and (not bestDistance or d < bestDistance) then
                hub, bestDistance = existing, d
            end
        end
        if hub then
            hub.pickupCount = hub.pickupCount + 1
            hub.pickupNames[#hub.pickupNames + 1] = candidate.name
            hub.pickupIDs[#hub.pickupIDs + 1] = candidate.questID
            hub.pickupGivers[#hub.pickupGivers + 1] = candidate.giverName
        else
            candidate.pickupCount = 1
            candidate.pickupNames = {candidate.name}
            candidate.pickupIDs = {candidate.questID}
            candidate.pickupGivers = {candidate.giverName or "unknown"}
            hubs[#hubs + 1] = candidate
        end
    end
    for _, hub in ipairs(hubs) do grouped[#grouped + 1] = hub end
    return grouped
end

local function nearCount(stop, others, used)
    local n = 0
    for _, other in ipairs(others) do
        -- Only reward unfinished, unvisited activities. Previously a stop
        -- could still get a cluster bonus from tasks already behind us,
        -- causing pointless backtracking to the same spot.
        if other ~= stop and not used[other.key]
            and distance(stop.x, stop.y, other.x, other.y) < CLUSTER then
            n = n + 1
        end
    end
    return n
end

local function routeScore(candidate, x, y, all, used, options)
    local dist = distance(candidate.x, candidate.y, x, y)
    local value = VALUE[candidate.kind] or 5
    local clustered = math.min(3, nearCount(candidate, all, used))
    -- Favor productive local groups over a distant pile of speculative
    -- quest pickups, but never treat map distance as real terrain distance.
    local score = value * 0.018 + clustered * 0.052 - dist * 0.85
    -- In the Barrens, select a level-appropriate quest hub before treating
    -- an isolated nearby starter as the next destination. These are broad
    -- hub regions, not claims about individual quest giver coordinates.
    -- Never override quest safety or the pickup/objective/turn-in phases.
    if candidate.kind == "pickup" and candidate.mapID == 1413 then
        local level = tonumber(options.level)
        if level then
            -- Progress the *pickup* phase south as levels increase. The
            -- overlapping bands are intentional (Ratchet remains a useful
            -- side hub), but an older Crossroads starter must not keep
            -- winning purely from its central position at level 23+.
            -- Actual accepted objectives and completed turn-ins are never
            -- penalized by this advisory hub preference.
            local hubs = {
                {min=10, max=19, x=.52, y=.30, radius=.12, weight=.22}, -- Crossroads
                {min=13, max=22, x=.62, y=.38, radius=.085, weight=.16}, -- Ratchet
                {min=18, max=27, x=.45, y=.59, radius=.10, weight=.24}, -- Camp Taurajo
            }
            for _, hub in ipairs(hubs) do
                local d = distance(candidate.x,candidate.y,hub.x,hub.y)
                if d <= hub.radius then
                    local proximity = 1 - d / hub.radius
                    if level >= hub.min and level <= hub.max then
                        score = score + hub.weight * proximity
                    elseif level > hub.max + 2 then
                        -- Soft bias only: a valid quest can still win if it
                        -- is genuinely useful and the character is nearby.
                        score = score - 0.13 * proximity
                    end
                    break
                end
            end
        end
    end
    if candidate.kind == "pickup" and dist < 0.023 then score = score + 0.045 end
    if candidate.kind == "pickup" and (candidate.pickupCount or 1) > 1 then
        -- One trip to this quest giver may unlock several objectives.
        score = score + math.min(3, candidate.pickupCount - 1) * 0.012
    end
    if candidate.kind == "turnin" and dist < 0.024 then score = score + 0.04 end
    -- A client-supplied location deserves slightly more trust than an
    -- approximate inherited Classic entry. The bias stays small enough
    -- that nearby provisional goals can still win.
    local source = candidate.waypointSource or candidate.confidence
    if source == "client" or source == "client-map-pin" then
        score = score + 0.025
    elseif source == "forever-beta" then
        score = score + 0.012
    end
    local strategy = _G.ForeverQuestStrategy
    if strategy and strategy.Assess then
        local adjustment, reason = strategy:Assess(candidate, options)
        score = score + adjustment
        candidate.decisionReason = reason
    end
    return score, dist, clustered
end

-- quests: active accepted quests, pickups: provisional unaccepted quests.
-- The player position and stop points must refer to the SAME UiMapID.
function Route:Build(quests, pickups, mapID, playerX, playerY, options)
    options = options or {}
    local avoided = options.avoided or {}
    local plan = {mapID = mapID, stops = {}, totalCandidates = 0, confidence = "approximate"}
    if type(mapID) ~= "number" or type(playerX) ~= "number"
        or type(playerY) ~= "number" then return plan end

    local all = {mapID = mapID}
    local seen = {}
    for _, q in ipairs(quests or {}) do
        if not avoided[q.questID] then
        local goals = not q.complete and q.goalPoints
        if type(goals) == "table" and #goals > 0 then
            -- Each unfinished objective gets its own route stop. Alternative
            -- spawn points for the same objective are already collapsed.
            for _, goal in ipairs(goals) do
                goal.suggestedGroup = q.suggestedGroup
                goal.isElite = q.isElite
                goal.questLevel = q.questLevel
                append(all, seen, "objective", q.questID, q.title,
                    goal.mapID, goal.x, goal.y,
                    goal.confidence or "provisional", goal.entityName, goal)
            end
        elseif q.waypointX and q.waypointY and q.waypointMap then
            append(all, seen, q.complete and "turnin" or "objective",
                q.questID, q.title, q.waypointMap, q.waypointX, q.waypointY,
                q.waypointConfidence or q.waypointSource, q.waypointArea, q)
        end
        end
    end
    -- Unaccepted quests are provisional. Do not cross a zone just because
    -- a distant quest giver has several possible quests. Collect them
    -- opportunistically when near the player, or near a known active task.
    -- With an empty active log, future pickups remain the primary plan.
    -- An unsafe accepted objective must not suppress discovery of a safe
    -- pickup hub. Filter accepted work BEFORE deciding whether speculative
    -- pickups are local detours or the main plan. This also avoids rewarding
    -- pickups for proximity to objectives AUTO will never recommend.
    local strategy = _G.ForeverQuestStrategy
    if strategy and strategy.IsAutoEligible and not options.includeUnsafe then
        local safe = {mapID = mapID}
        for _, stop in ipairs(all) do
            if strategy:IsAutoEligible(stop, options) then
                safe[#safe + 1] = stop
            end
        end
        all = safe
    end
    -- A player can defer a frustrating objective without abandoning its
    -- entire quest. Temporarily set aside its individual route-stop key;
    -- discover other eligible work first. If nothing else remains on this
    -- map, restore the deferred objective automatically (no stranded quest).
    local deferredCandidates = {}
    if type(options.deferred) == "table" then
        local ready = {mapID = mapID}
        for _, stop in ipairs(all) do
            if stop.kind == "objective" and options.deferred[stop.key] then
                deferredCandidates[#deferredCandidates + 1] = stop
            else
                ready[#ready + 1] = stop
            end
        end
        all = ready
    end
    local activeCount = #all
    for _, q in ipairs(pickups or {}) do
        if not avoided[q.questID]
            and validPoint(q.mapID, q.x, q.y, mapID) then
            local playerDistance = distance(playerX, playerY, q.x, q.y)
            local alongRoute = false
            if activeCount > 0 then
                for i = 1, activeCount do
                    local active = all[i]
                    if distance(q.x, q.y, active.x, active.y) <= 0.035 then
                        alongRoute = true
                        break
                    end
                end
            end
            if activeCount == 0 or playerDistance <= 0.055 or alongRoute then
                append(all, seen, "pickup", q.questID, q.name,
                    q.mapID, q.x, q.y, q.confidence, q.area, q)
            end
        end
    end

    -- Unsafe objectives cannot win simply because they are the closest.
    -- Filter before grouping and scoring so they also grant no cluster bonus.
    local strategy = _G.ForeverQuestStrategy
    if strategy and strategy.IsAutoEligible and not options.includeUnsafe then
        local filtered = {mapID = mapID}
        for _, stop in ipairs(all) do
            if strategy:IsAutoEligible(stop, options) then
                filtered[#filtered + 1] = stop
            end
        end
        all = filtered
    end
    if #all == 0 and #deferredCandidates > 0 then
        -- AUTO comes back to the hard objective when there is no other safe
        -- location-backed work, without requiring /fq resume.
        for _, stop in ipairs(deferredCandidates) do
            all[#all + 1] = stop
        end
    end
    plan.totalCandidates = #all
    all = groupPickupHubs(all)
    plan.totalLocations = #all

    -- Keep the selected route stop until its work is completed or it
    -- disappears from the eligible candidates. Avoid proximity flip-flops.
    local pinned
    if type(options.preferredKey) == "string" then
        for _, candidate in ipairs(all) do
            if candidate.key == options.preferredKey then
                local strategy = _G.ForeverQuestStrategy
                local blocked = strategy and strategy.ShouldAvoidAuto
                    and strategy:ShouldAvoidAuto(candidate, options)
                if not blocked then pinned = candidate end
                break
            end
        end
    end
    local x, y = playerX, playerY
    local used = {}
    -- A guide circuit is a sequence of phases, not five unrelated nearest
    -- stops. Gather a nearby starter cluster, do active objectives, then
    -- return for turn-ins. Newly accepted quests will trigger a fresh plan.
    -- Only local pickups join a circuit that already has active objectives;
    -- otherwise a distant speculative starter cannot hijack the route.
    -- Once we start collecting quests at a hub, finish its nearby pickups
    -- before heading to objectives. A single pickup at step one was not
    -- enough: the planner could walk away from a second nearby quest giver.
    -- Never chase distant speculative pickups while active work remains.
    local collectingHub = false
    -- Pickups encountered at an objective cluster should be collected before
    -- leaving that cluster, not deferred until after the objective/turn-in
    -- circuit. This is especially important when a character already has
    -- one quest and discovers another starter at the same hunting area.
    local function hasPickupNearObjective()
        for _, pickup in ipairs(all) do
            if pickup.kind == "pickup" and not used[pickup.key] then
                for _, objective in ipairs(all) do
                    if objective.kind == "objective" and not used[objective.key]
                        and distance(pickup.x, pickup.y, objective.x, objective.y) <= 0.018
                        and distance(x, y, objective.x, objective.y) <= 0.035 then
                        return true
                    end
                end
            end
        end
        return false
    end
    -- An empty quest log should trigger one hub collection trip, not a
    -- five-stop sightseeing tour of unrelated quest givers across the map.
    -- After reaching that hub, accepting quests causes a fresh live plan.
    local emptyLogPickupTrip = activeCount == 0
    local firstPickupX, firstPickupY
    local function phaseForStep(step)
        local hasObjective, hasTurnin, localPickup = false, false, false
        for _, candidate in ipairs(all) do
            if not used[candidate.key] then
                if candidate.kind == "objective" then hasObjective = true end
                if candidate.kind == "turnin" then hasTurnin = true end
                if candidate.kind == "pickup"
                    and distance(candidate.x, candidate.y, x, y) <= 0.035 then
                    localPickup = true
                end
            end
        end
        if step == 1 then
            -- Initial hub radius can be larger than the between-giver radius.
            for _, candidate in ipairs(all) do
                if candidate.kind == "pickup" and not used[candidate.key]
                    and distance(candidate.x, candidate.y, x, y) <= 0.035 then
                    collectingHub = true
                    return "pickup"
                end
            end
        end
        if collectingHub and localPickup then return "pickup" end
        collectingHub = false
        -- Bank a completed quest when its giver is right here and the
        -- remaining objectives require a separate trip. This can unlock
        -- follow-ups on the next live quest-log refresh. Do not detour
        -- from a dense objective cluster merely to chase a remote turn-in.
        if step == 1 and hasTurnin and not localPickup then
            local nearestTurnin, nearestObjective = math.huge, math.huge
            for _, candidate in ipairs(all) do
                if not used[candidate.key] then
                    local d = distance(x, y, candidate.x, candidate.y)
                    if candidate.kind == "turnin" then
                        nearestTurnin = math.min(nearestTurnin, d)
                    elseif candidate.kind == "objective" then
                        nearestObjective = math.min(nearestObjective, d)
                    end
                end
            end
            if nearestTurnin <= 0.025 and nearestObjective > 0.07 then
                return "turnin"
            end
        end
        if hasObjective and hasPickupNearObjective() then
            return "pickup"
        end
        if hasObjective then return "objective" end
        if hasTurnin then return "turnin" end
        return "pickup"
    end
    for step = 1, math.min(5, #all) do
        -- Keep an empty-log itinerary inside the first selected hub. This
        -- prevents the route from promising five distant pickups before the
        -- player has even accepted the first quest.
        if emptyLogPickupTrip and firstPickupX then
            local nearby = false
            for _, candidate in ipairs(all) do
                if not used[candidate.key] and candidate.kind == "pickup"
                    and distance(candidate.x, candidate.y,
                        firstPickupX, firstPickupY) <= 0.035 then
                    nearby = true
                    break
                end
            end
            if not nearby then break end
        end
        local phase = phaseForStep(step)
        local best, bestScore, bestDist, bestCluster
        for _, candidate in ipairs(all) do
            local objectiveAreaPickup = phase == "pickup" and
                not collectingHub and hasPickupNearObjective()
            local nearObjective = not objectiveAreaPickup
            if objectiveAreaPickup then
                nearObjective = false
                for _, objective in ipairs(all) do
                    if objective.kind == "objective" and not used[objective.key]
                        and distance(candidate.x, candidate.y, objective.x, objective.y) <= 0.018
                        and distance(x, y, objective.x, objective.y) <= 0.035 then
                        nearObjective = true
                        break
                    end
                end
            end
            -- Keep a collection phase triggered by a nearby quest giver
            -- inside that hub, not a distant, denser pickup cluster.
            local withinCollectionHub = not collectingHub
                or candidate.kind ~= "pickup"
                or distance(candidate.x, candidate.y, x, y) <= 0.035
            if not used[candidate.key] and candidate.kind == phase
                and nearObjective and withinCollectionHub
                and (not emptyLogPickupTrip or not firstPickupX
                    or distance(candidate.x, candidate.y,
                        firstPickupX, firstPickupY) <= 0.035) then
                local score, dist, clustered = routeScore(candidate, x, y, all, used, options)
                if step == 1 and candidate == pinned then
                    score = score + 100
                end
                -- Small stable tie-break avoids nondeterministic NPC spawn order.
                score = score - (tonumber(candidate.questID) or 0) * 0.000000001
                if not bestScore or score > bestScore then
                    best, bestScore, bestDist, bestCluster =
                        candidate, score, dist, clustered
                end
            end
        end
        if not best then break end
        used[best.key] = true
        if emptyLogPickupTrip and not firstPickupX and best.kind == "pickup" then
            firstPickupX, firstPickupY = best.x, best.y
        end
        local stop = {}
        for k, v in pairs(best) do stop[k] = v end
        stop.distance = bestDist
        stop.overlapping = bestCluster
        stop.nearby = {}
        for _, other in ipairs(all) do
            if other ~= best and not used[other.key]
                and distance(best.x, best.y, other.x, other.y) < CLUSTER then
                stop.nearby[#stop.nearby + 1] = {
                    name = other.name, kind = other.kind,
                    questID = other.questID, goalKey = other.goalKey,
                    targetName = other.targetName,
                }
            end
        end
        plan.stops[#plan.stops + 1] = stop
        x, y = best.x, best.y
    end
    return plan
end

function Route:Describe(stop)
    if not stop then return "No known destination" end
    local action = stop.kind == "pickup" and "PICK UP"
        or stop.kind == "turnin" and "TURN IN" or "DO"
    local extra = stop.overlapping > 0 and (" • +" .. stop.overlapping .. " nearby") or ""
    local summary = stop.name or "Quest"
    if stop.kind == "pickup" and (stop.pickupCount or 1) > 1 then
        summary = string.format("%d possible quests here (e.g. %s)",
            stop.pickupCount, summary)
    end
    if stop.kind == "objective" and stop.targetName
        and stop.targetName ~= "" then
        summary = summary .. ": " .. stop.targetName
    end
    return string.format("%s %s (~%.0f,%.0f)%s", action,
        summary, stop.x * 100, stop.y * 100, extra)
end
