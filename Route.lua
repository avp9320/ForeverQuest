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
    }
    seen[key] = true
    all[#all + 1] = stop
end

-- Higher value favors unfinished objectives and opportunistic pickups, but
-- a turn-in next to the player still wins over a long cross-zone run.
local VALUE = { objective = 12, pickup = 10, turnin = 8 }
local CLUSTER = 0.025

local function nearCount(stop, others)
    local n = 0
    for _, other in ipairs(others) do
        if other ~= stop and distance(stop.x, stop.y, other.x, other.y) < CLUSTER then
            n = n + 1
        end
    end
    return n
end

local function routeScore(candidate, x, y, all)
    local dist = distance(candidate.x, candidate.y, x, y)
    local value = VALUE[candidate.kind] or 5
    local clustered = math.min(3, nearCount(candidate, all))
    -- A local pickup is worth grabbing, a remote one isn't automatically
    -- more important than an accepted quest. Avoid obsessing over turn-ins.
    local score = value * 0.018 + clustered * 0.029 - dist * 1.3
    if candidate.kind == "pickup" and dist < 0.023 then score = score + 0.045 end
    if candidate.kind == "turnin" and dist < 0.024 then score = score + 0.04 end
    return score, dist, clustered
end

-- quests: active accepted quests, pickups: provisional unaccepted quests.
-- The player position and stop points must refer to the SAME UiMapID.
function Route:Build(quests, pickups, mapID, playerX, playerY)
    local plan = {mapID = mapID, stops = {}, totalCandidates = 0, confidence = "approximate"}
    if type(mapID) ~= "number" or type(playerX) ~= "number"
        or type(playerY) ~= "number" then return plan end

    local all = {mapID = mapID}
    local seen = {}
    for _, q in ipairs(quests or {}) do
        local goals = not q.complete and q.goalPoints
        if type(goals) == "table" and #goals > 0 then
            -- Each unfinished objective gets its own route stop. Alternative
            -- spawn points for the same objective are already collapsed.
            for _, goal in ipairs(goals) do
                append(all, seen, "objective", q.questID, q.title,
                    goal.mapID, goal.x, goal.y,
                    goal.confidence or "provisional", goal.entityName, goal)
            end
        elseif q.waypointX and q.waypointY and q.waypointMap then
            append(all, seen, q.complete and "turnin" or "objective",
                q.questID, q.title, q.waypointMap, q.waypointX, q.waypointY,
                q.waypointConfidence or q.waypointSource, q.waypointArea)
        end
    end
    for _, q in ipairs(pickups or {}) do
        append(all, seen, "pickup", q.questID, q.name,
            q.mapID, q.x, q.y, q.confidence, q.area)
    end

    plan.totalCandidates = #all
    local x, y = playerX, playerY
    local used = {}
    for step = 1, math.min(5, #all) do
        local best, bestScore, bestDist, bestCluster
        for _, candidate in ipairs(all) do
            if not used[candidate.key] then
                local score, dist, clustered = routeScore(candidate, x, y, all)
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
        local stop = {}
        for k, v in pairs(best) do stop[k] = v end
        stop.distance = bestDist
        stop.overlapping = bestCluster
        stop.nearby = {}
        for _, other in ipairs(all) do
            if other ~= best and distance(best.x, best.y, other.x, other.y) < CLUSTER then
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
    if stop.kind == "objective" and stop.targetName
        and stop.targetName ~= "" then
        summary = summary .. ": " .. stop.targetName
    end
    return string.format("%s %s (~%.0f,%.0f)%s", action,
        summary, stop.x * 100, stop.y * 100, extra)
end
