local ADDON_NAME = ...

local FQ = CreateFrame("Frame")
local Planner = _G.ForeverQuestPlanner
local Route = _G.ForeverQuestRoute
local Knowledge = _G.ForeverQuestKnowledge
local Travel = _G.ForeverQuestTravel
local Items = _G.ForeverQuestItems
local Navigation = _G.ForeverQuestNavigation
local VERSION = "1.0.5"
-- Read the TOC version when the client exposes addon metadata. This avoids
-- misleading "v0.3.0 loaded" messages after a successful WoWUp update.
if ADDON_NAME then
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(metadata)=="function" then
        local ok,value=pcall(metadata,ADDON_NAME,"Version")
        if ok and type(value)=="string" and value~="" then VERSION=value end
    end
end

local defaults = {
    locked = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 180,
    mode = "AUTO",
    routeMode = "balanced",
    manualQuestID = nil,
}

local state = {
    quests = {},
    focusQuestID = nil,
    pickup = nil,
    routePlan = nil,
    routeStop = nil,
    routeKey = nil,
    lastRouteSwitch = 0,
    manualChoice = nil,
    nextZones = nil,
    mapCaution = nil,
    mapCautionKey = nil,
    focusScore = nil,
    lastFocusChange = 0,
    refreshElapsed = 0,
    arrowElapsed = 0,
    navigationTarget = nil,
}

local function CopyDefaults()
    ForeverQuestDB = ForeverQuestDB or {}
    for key, value in pairs(defaults) do
        if ForeverQuestDB[key] == nil then
            ForeverQuestDB[key] = value
        end
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff58c6ffForeverQuest:|r " .. tostring(message))
end

local function SafeQuestTitle(questID, fallback)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and title and title ~= "" then
            return title
        end
    end
    return fallback or ("Quest " .. tostring(questID))
end

local function IsEliteQuest(questID)
    if C_QuestLog and type(C_QuestLog.GetQuestTagInfo)=="function" then
        local ok,info=pcall(C_QuestLog.GetQuestTagInfo,questID)
        if ok and type(info)=="table" then
            return info.isElite==true
        end
    end
    return false
end

local function GetObjectives(questID)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
        return nil
    end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok then
        return objectives
    end
end

local function IsQuestComplete(questID)
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, complete = pcall(C_QuestLog.IsComplete, questID)
        if ok then
            return complete and true or false
        end
    end
    return false
end

local function GetBestMap()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then
            return mapID
        end
    end
end

local function GetWaypoint(questID, mapID)
    if not questID then
        return nil
    end

    if mapID and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, questID, mapID)
        if ok and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return mapID, x, y
        end
    end

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local ok, waypointMap, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
        if ok and type(waypointMap) == "number" and type(x) == "number" and type(y) == "number" then
            return waypointMap, x, y
        end
    end
end

-- Native Forever waypoint text offers useful next-step guidance when
-- available; unlike a guessed quest database, this describes live client data.
local function GetWaypointText(questID)
    if not (C_QuestLog and C_QuestLog.GetNextWaypointText) then return nil end
    local ok, value = pcall(C_QuestLog.GetNextWaypointText, questID)
    if ok and type(value) == "string" and value ~= "" then return value end
end

-- Some quests expose map POIs even when GetNextWaypoint returns nothing.
-- Treat these as approximate objective regions, NOT exact mob positions.
local function GetActiveQuestPins(mapID)
    local pins = {}
    if not mapID or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
        return pins
    end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(list) ~= "table" then return pins end
    for _, pin in ipairs(list) do
        local safe, questID, x, y = pcall(function()
            if type(pin) ~= "table" or pin.isQuestStart or pin.inProgress == false then
                return nil
            end
            local id, px, py = pin.questID, pin.x, pin.y
            if type(id) == "number" and type(px) == "number"
                and type(py) == "number" and px >= 0 and px <= 1
                and py >= 0 and py <= 1 then
                return id, px, py
            end
        end)
        if safe and questID and not pins[questID] then
            pins[questID] = {x = x, y = y}
        end
    end
    return pins
end

-- Keep location facts separate from UI/selection. Exact live client
-- waypoints always take priority; these are explicitly approximate fallbacks.
local function CuratedLocation(questID, complete)
    local entry = ForeverQuestData and ForeverQuestData[questID]
    if type(entry) ~= "table" then return nil end
    local point = complete and entry.turnIn or entry.objective
    if not point or not entry.mapID then return nil end
    return entry.mapID, point.x, point.y, point.area, entry.confidence
end

local function PlayerMapDistance(mapID, x, y)
    if not (mapID and x and y and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos or not pos.GetXY then return nil end
    local good, px, py = pcall(pos.GetXY, pos)
    if good and type(px) == "number" and type(py) == "number" then
        local dx, dy = x - px, y - py
        return math.sqrt(dx * dx + dy * dy)
    end
end

local function GetQuestDistance(questID)
    if not (C_QuestLog and C_QuestLog.GetDistanceSqToQuest) then
        return nil, false
    end

    local ok, distanceSq, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, questID)
    if ok and type(distanceSq) == "number" and distanceSq >= 0 then
        return math.sqrt(distanceSq), onContinent and true or false
    end
    return nil, false
end

local function FormatDistance(distance)
    if not distance then
        return ""
    end
    if distance < 1000 then
        return string.format("%d yd", math.floor(distance + 0.5))
    end
    return string.format("%.1fk yd", distance / 1000)
end

local function ObjectiveText(questID, complete)
    if complete then
        return "Ready for turn-in"
    end

    local objectives = GetObjectives(questID)
    if type(objectives) ~= "table" then
        return "Quest in progress"
    end

    local firstUnfinished
    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local finished = objective.finished or objective.isFinished
            local text = objective.text or objective.description
            if not finished and text and text ~= "" then
                firstUnfinished = text
                break
            end
        end
    end

    if firstUnfinished then
        return firstUnfinished
    end

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local text = objective.text or objective.description
            if text and text ~= "" then
                return text
            end
        end
    end

    return "Quest in progress"
end

local function CollectQuests()
    wipe(state.quests)

    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return
    end

    local ok, numEntries = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or type(numEntries) ~= "number" then
        return
    end

    local currentMap = GetBestMap()
    local mapPins = GetActiveQuestPins(currentMap)

    for index = 1, numEntries do
        local infoOK, info = pcall(C_QuestLog.GetInfo, index)
        if infoOK and type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 and not info.isHidden then
            local questID = info.questID
            local complete = IsQuestComplete(questID)
            local distance, onContinent = GetQuestDistance(questID)
            local waypointMap, waypointX, waypointY = GetWaypoint(questID, currentMap)
            local waypointSource = waypointMap and "client" or nil
            local waypointArea, waypointConfidence, goalPoints
            if not waypointMap and mapPins[questID] then
                waypointMap = currentMap
                waypointX, waypointY = mapPins[questID].x, mapPins[questID].y
                waypointSource = "client-map-pin"
            end
            if not waypointMap then
                -- Prefer documented Forever-specific positions over Classic guesses.
                local curated = ForeverQuestData and ForeverQuestData[questID]
                if curated and curated.confidence == "forever-beta" then
                    waypointMap, waypointX, waypointY, waypointArea,
                        waypointConfidence = CuratedLocation(questID, complete)
                    if waypointMap then waypointSource = "curated" end
                end
            end
            -- Build separate unfinished targets even when the game already
            -- offers a waypoint. Previously ANY native waypoint suppressed
            -- multi-objective routing for the entire quest.
            if Planner and Planner.GetActivePositions and not complete then
                local candidates = Planner:GetActivePositions(
                    questID, false, currentMap, GetObjectives(questID), 6)
                if type(candidates) == "table" and #candidates > 0 then
                    local accept = true
                    if waypointMap == currentMap and waypointX and waypointY then
                        -- A native waypoint is more reliable than an inherited
                        -- Classic spawn. Match it to an identified target only
                        -- when their areas are reasonably close; otherwise
                        -- keep the native waypoint rather than guessing.
                        local closest, bestSquared
                        for _, target in ipairs(candidates) do
                            if target.mapID == currentMap then
                                local dx = target.x - waypointX
                                local dy = target.y - waypointY
                                local squared = dx * dx + dy * dy
                                if not bestSquared or squared < bestSquared then
                                    bestSquared, closest = squared, target
                                end
                            end
                        end
                        if closest and bestSquared <= 0.055 * 0.055 then
                            closest.x, closest.y = waypointX, waypointY
                            closest.confidence = "client"
                            closest.waypointSource = "client"
                        else
                            accept = false
                        end
                    end
                    if accept then
                        goalPoints = candidates
                        local location = goalPoints[1]
                        if not waypointMap and location then
                            waypointMap, waypointX, waypointY = location.mapID,
                                location.x, location.y
                            waypointSource = "database"
                            waypointArea = location.entityName
                            waypointConfidence = location.confidence
                        end
                    end
                end
            elseif not waypointMap and Planner and Planner.GetActivePosition then
                -- Completed quests only need one alternative turn-in position.
                local location = Planner:GetActivePosition(
                    questID, true, currentMap, GetObjectives(questID))
                if location then
                    waypointMap, waypointX, waypointY = location.mapID,
                        location.x, location.y
                    waypointSource = "database"
                    waypointArea = location.entityName
                    waypointConfidence = location.confidence
                end
            end
            if not waypointMap then
                waypointMap, waypointX, waypointY, waypointArea,
                    waypointConfidence = CuratedLocation(questID, complete)
                if waypointMap then waypointSource = "curated" end
            end
            local mapDistance = PlayerMapDistance(waypointMap, waypointX, waypointY)
            local sameMap = mapDistance ~= nil

            -- Prioritize actual objective positions where we have them. The
            -- quest-log distance can point toward a turn-in NPC even when a
            -- quest has outstanding kills/collections, so it is the fallback.
            local score
            if mapDistance then
                score = mapDistance * 100000
            elseif distance and onContinent then
                score = distance
            elseif sameMap then
                score = 2500
            elseif onContinent then
                score = 10000
            else
                score = 25000
            end

            if sameMap then
                score = math.max(0, score - math.min(600, score * 0.15))
            end
            -- Do not give completed quests an artificial distance bonus.
            -- Turn-ins remain tracked, but unfinished objectives should be
            -- the default focus while any unfinished quest is available.

            table.insert(state.quests, {
                questID = questID,
                title = SafeQuestTitle(questID, info.title),
                complete = complete,
                distance = distance,
                onContinent = onContinent,
                sameMap = sameMap,
                waypointMap = waypointMap,
                waypointX = waypointX,
                waypointY = waypointY,
                waypointText = GetWaypointText(questID),
                waypointSource = waypointSource,
                waypointArea = waypointArea,
                waypointConfidence = waypointConfidence,
                goalPoints = goalPoints,
                mapDistance = mapDistance,
                score = score,
                logIndex = index,
                suggestedGroup = info.suggestedGroup,
                questLevel = info.level or info.difficultyLevel,
                isElite = IsEliteQuest(questID),
            })
        end
    end

    -- Group only quests with known, nearby map points on the same map.
    -- 0.045 is a *map-relative* radius, not a precise yardage claim.
    -- This identifies candidate quest areas, not guaranteed shared kills.
    for _, quest in ipairs(state.quests) do
        quest.nearbyCount = 0
        if not quest.complete and quest.sameMap and quest.waypointX and quest.waypointY then
            for _, other in ipairs(state.quests) do
                if quest ~= other and not other.complete and other.sameMap
                    and other.waypointMap == quest.waypointMap
                    and other.waypointX and other.waypointY then
                    local dx, dy = quest.waypointX - other.waypointX,
                        quest.waypointY - other.waypointY
                    if dx * dx + dy * dy <= 0.045 * 0.045 then
                        quest.nearbyCount = quest.nearbyCount + 1
                    end
                end
            end
            if quest.nearbyCount > 0 then
                -- Prefer a nearby cluster, but do not send the player far
                -- across the zone for a distant cluster.
                quest.score = quest.score - math.min(quest.nearbyCount, 3)
                    * math.min(220, math.max(0, quest.score) * 0.12)
            end
        end
    end

    table.sort(state.quests, function(a, b)
        -- The card is a next-objective assistant, not a turn-in reminder.
        -- Keep completed quests available in MANUAL and as a fallback when
        -- every remaining quest is ready to turn in.
        if a.complete ~= b.complete then
            return not a.complete
        end
        if a.score == b.score then
            return a.questID < b.questID
        end
        return a.score < b.score
    end)
end

local function FindQuest(questID)
    if not questID then
        return nil
    end
    for _, quest in ipairs(state.quests) do
        if quest.questID == questID then
            return quest
        end
    end
end

local function GetAreaQuests(quest)
    local area = {}
    if not quest or quest.complete or not quest.sameMap
        or not quest.waypointX or not quest.waypointY then return area end
    for _, other in ipairs(state.quests) do
        if not other.complete and other.sameMap
            and other.waypointMap == quest.waypointMap
            and other.waypointX and other.waypointY then
            local dx, dy = quest.waypointX - other.waypointX,
                quest.waypointY - other.waypointY
            if dx * dx + dy * dy <= 0.045 * 0.045 then
                area[#area + 1] = other
            end
        end
    end
    return area
end

local function PrintArea()
    local quest = FindQuest(state.focusQuestID)
    if not quest then Print("No focused quest."); return end
    local area = GetAreaQuests(quest)
    if #area == 0 then
        Print("No trusted nearby quest positions for this objective. Not guessing a route.")
        return
    end
    Print("Possible same-area objectives (" .. #area .. "; approximate map positions):")
    for i = 1, math.min(#area, 5) do
        local q = area[i]
        Print("  " .. q.title .. ": " .. ObjectiveText(q.questID, q.complete))
    end
end

local function NavigateToFocus()
    if state.pickup then
        local item = state.pickup
        local destination = Navigation and Navigation.Destination
            and Navigation:Destination(item.questID, "pickup",
                item.giverName or item.area or item.name)
            or item.giverName or item.area or item.name
        Print("Suggested pickup: " .. tostring(destination)
            .. ". Blizzard cannot track it until you accept the quest.")
        return
    end
    local quest = FindQuest(state.focusQuestID)
    if not quest then Print("No focused quest."); return end
    if Navigation and Navigation.TrackQuest
        and Navigation:TrackQuest(quest.questID) then
        Print("Blizzard now tracks: " .. quest.title .. ".")
    else
        Print("Blizzard quest supertracking is unavailable on this client.")
    end
end

-- Skips are character-specific. Database predictions can be wrong on
-- Forever, so the player can dismiss a pickup without disabling AUTO.
local function IgnoredPickups()
    if not ForeverQuestDB then return {} end
    ForeverQuestDB.ignoredByCharacter = ForeverQuestDB.ignoredByCharacter or {}
    local key = (UnitGUID and UnitGUID("player"))
        or ((UnitName and UnitName("player") or "player")
            .. "-" .. (GetRealmName and GetRealmName() or "realm"))
    local account = ForeverQuestDB.ignoredByCharacter
    account[key] = account[key] or {}
    return account[key]
end

local function AvoidedQuests()
    if not ForeverQuestDB then return {} end
    ForeverQuestDB.avoidedByCharacter = ForeverQuestDB.avoidedByCharacter or {}
    local key = (UnitGUID and UnitGUID("player"))
        or ((UnitName and UnitName("player") or "player")
            .. "-" .. (GetRealmName and GetRealmName() or "realm"))
    local registry = ForeverQuestDB.avoidedByCharacter
    registry[key] = registry[key] or {}
    return registry[key]
end

local function RefreshFutureQuests()
    if not Planner or not Planner.Available or not Planner:Available() then return end
    local active = {}
    for _, quest in ipairs(state.quests) do active[quest.questID] = true end
    for id in pairs(IgnoredPickups()) do active[id] = true end
    for id in pairs(AvoidedQuests()) do active[id] = true end
    Planner:Scan(GetBestMap(), UnitLevel("player"), active)
end

local function NearbyPickup()
    if not Planner or not Planner.Available or not Planner:Available() then return nil end
    return Planner:GetNearby(GetBestMap(), 1)[1]
end

local function PrintPlan()
    CollectQuests()
    if not Planner or not Planner:Available() then
        Print("Bundled quest catalog is unavailable; see /fq debug.")
        Print("Live quest tracking and verified starter locations remain available.")
        return
    end
    RefreshFutureQuests()
    Print(Planner:Status())
    local candidates = Planner:GetNearby(GetBestMap(), 5)
    if #candidates == 0 then
        Print("No pickup suggestions yet, or the zone scan is still running.")
        return
    end
    Print("Possible quest pickups (not confirmed by the live NPC):")
    for i, q in ipairs(candidates) do
        Print(string.format("%d. %s: ~%.1f, %.1f (%s)",
            i, q.name, q.x * 100, q.y * 100, q.kind))
    end
end

local function PickAutoQuest()
    local best
    local strategy = _G.ForeverQuestStrategy
    local opts = {
        level = UnitLevel and UnitLevel("player") or 1,
        groupSize = math.max(1, (GetNumGroupMembers and GetNumGroupMembers()) or 1),
        avoided = AvoidedQuests(),
    }
    for _, candidate in ipairs(state.quests) do
        local eligible = not strategy or not strategy.IsAutoEligible
            or strategy:IsAutoEligible({
                questID = candidate.questID,
                kind = candidate.complete and "turnin" or "objective",
                questLevel = candidate.questLevel,
                isElite = candidate.isElite,
                suggestedGroup = candidate.suggestedGroup,
            }, opts)
        if eligible then
            best = candidate
            break
        end
    end
    if not best then
        return nil
    end

    local current = FindQuest(state.focusQuestID)
    if current and not AvoidedQuests()[current.questID]
        and ForeverQuestDB.mode == "AUTO"
        and (not strategy or not strategy.IsAutoEligible
            or strategy:IsAutoEligible({
                questID = current.questID,
                kind = current.complete and "turnin" or "objective",
                questLevel = current.questLevel,
                suggestedGroup = current.suggestedGroup,
                isElite = current.isElite,
            }, opts)) then
        -- A quest becoming ready for turn-in must immediately yield to a
        -- nearby unfinished quest, even if the old quest is very close.
        -- Do not let the anti-thrashing rule preserve the completed quest.
        if current.complete ~= best.complete then
            return best
        end
        -- Keep the current focus unless another quest is meaningfully better.
        -- This prevents the card from bouncing between nearby objectives.
        local improvement = current.score - best.score
        local threshold = math.max(120, current.score * 0.18)
        if improvement < threshold then
            return current
        end
    end

    return best
end

local frame = CreateFrame("Button", "ForeverQuestFocusFrame", UIParent, "BackdropTemplate")
-- Two compact tracker lines: quest + distance, then the current objective.
-- Don't impersonate a full quest-log window or show an always-on AUTO badge.
frame:SetSize(320, 49)
if Items and Items.Create then Items:Create(frame) end
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
frame:EnableMouseWheel(true)
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
})
frame:SetBackdropColor(0.025, 0.025, 0.03, 0.66)

frame.accent = frame:CreateTexture(nil, "ARTWORK")
frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 3)
frame.accent:SetWidth(2)
frame.accent:SetColorTexture(0.73, 0.60, 0.25, 0.9)

frame.arrow = frame:CreateTexture(nil, "ARTWORK")
frame.arrow:SetSize(22, 22)
frame.arrow:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -4)
frame.arrow:SetTexture("Interface\\MINIMAP\\MinimapArrow")
frame.arrow:SetAlpha(1)
frame.arrow:SetVertexColor(0.46, 0.98, 0.56)
frame.arrow:Hide()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetJustifyH("LEFT")
frame.title:SetWordWrap(false)
frame.title:SetTextColor(1, 0.82, 0.22)

frame.distance = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.distance:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -7)
frame.distance:SetWidth(102)
frame.distance:SetJustifyH("RIGHT")
frame.distance:SetTextColor(0.72, 0.72, 0.72)
frame.distance:SetText("")

frame.objective = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.objective:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -27)
frame.objective:SetPoint("RIGHT", frame, "RIGHT", -9, 0)
frame.objective:SetJustifyH("LEFT")
frame.objective:SetWordWrap(false)
frame.objective:SetTextColor(0.90, 0.90, 0.90)

frame.group = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.group:SetPoint("RIGHT", frame.distance, "LEFT", -3, 0)
frame.group:SetWidth(24)
frame.group:SetJustifyH("RIGHT")
frame.group:SetTextColor(0.45, 0.86, 0.50)
frame.group:Hide()

local function UpdateTitleLayout()
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT",
        frame.arrow:IsShown() and 36 or 11, -7)
    if frame.group:IsShown() then
        frame.title:SetPoint("RIGHT", frame.group, "LEFT", -5, 0)
    elseif frame.distance:GetText() ~= "" then
        frame.title:SetPoint("RIGHT", frame.distance, "LEFT", -5, 0)
    else
        frame.title:SetPoint("RIGHT", frame, "RIGHT", -9, 0)
    end
end

local function ShowDirectionArrow(show)
    if show and not frame.arrow:IsShown() then
        frame.arrow:Show()
        UpdateTitleLayout()
    elseif not show and frame.arrow:IsShown() then
        frame.arrow:Hide()
        UpdateTitleLayout()
    end
end

UpdateTitleLayout()

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ForeverQuestDB.point = point
    ForeverQuestDB.relativePoint = relativePoint
    ForeverQuestDB.x = x
    ForeverQuestDB.y = y
end

local function ApplyLockState()
    frame:SetMovable(not ForeverQuestDB.locked)
    frame:RegisterForDrag("LeftButton")
    -- Blue accent means the card is draggable; no overlay text obscuring quests.
    if ForeverQuestDB.locked then
        frame.accent:SetColorTexture(0.73, 0.60, 0.25, 0.9)
    else
        frame.accent:SetColorTexture(0.28, 0.72, 1.0, 1.0)
    end
end

frame:SetScript("OnDragStart", function(self)
    if not ForeverQuestDB.locked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local function SetFocus(quest)
    local oldID = state.focusQuestID
    state.focusQuestID = quest and quest.questID or nil
    state.focusScore = quest and quest.score or nil
    if oldID ~= state.focusQuestID then
        state.lastFocusChange = GetTime()
    end
end

-- Cycle planned actions, including possible pickups even with no quest log.
local RefreshFocus
local function ManualCycle(direction)
    local stops = state.routePlan and state.routePlan.stops or {}
    if #stops > 0 then
        local index = 0
        local kind = ForeverQuestDB.mode == "MANUAL"
            and ForeverQuestDB.manualKind
            or (state.routeStop and state.routeStop.kind)
        local questID = ForeverQuestDB.mode == "MANUAL"
            and ForeverQuestDB.manualQuestID
            or (state.routeStop and state.routeStop.questID)
        local goalKey = ForeverQuestDB.mode == "MANUAL"
            and ForeverQuestDB.manualGoalKey
            or (state.routeStop and state.routeStop.goalKey)
        for i, stop in ipairs(stops) do
            if stop.kind == kind and stop.questID == questID
                and (not goalKey or stop.goalKey == goalKey) then
                index = i
                break
            end
        end
        index = index + direction
        if index > #stops then index = 1 end
        if index < 1 then index = #stops end
        local selected = stops[index]
        ForeverQuestDB.mode = "MANUAL"
        ForeverQuestDB.manualKind = selected.kind
        ForeverQuestDB.manualQuestID = selected.questID
        ForeverQuestDB.manualGoalKey = selected.goalKey
        state.manualChoice = selected
        if RefreshFocus then RefreshFocus() end
        return
    end

    if #state.quests == 0 then return end
    ForeverQuestDB.mode = "MANUAL"
    ForeverQuestDB.manualKind = nil
    ForeverQuestDB.manualGoalKey = nil
    local currentIndex = 1
    for i, quest in ipairs(state.quests) do
        if quest.questID == state.focusQuestID then currentIndex = i; break end
    end
    currentIndex = currentIndex + direction
    if currentIndex > #state.quests then currentIndex = 1 end
    if currentIndex < 1 then currentIndex = #state.quests end
    ForeverQuestDB.manualQuestID = state.quests[currentIndex].questID
    state.manualChoice = nil
    if RefreshFocus then RefreshFocus() end
end

frame:SetScript("OnClick", function(_, button)
    if not ForeverQuestDB.locked then
        return
    end

    if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
        NavigateToFocus()
    elseif button == "RightButton" then
        ForeverQuestDB.mode = "AUTO"
        ForeverQuestDB.manualQuestID = nil
        ForeverQuestDB.manualKind = nil
        ForeverQuestDB.manualGoalKey = nil
        state.manualChoice = nil
        state.routeStop = nil
        state.routeKey = nil
        if RefreshFocus then RefreshFocus() end
        Print("AUTO mode")
    elseif button == "LeftButton" then
        ManualCycle(1)
    end
end)

frame:SetScript("OnMouseWheel", function(_, delta)
    if ForeverQuestDB.locked then
        ManualCycle(delta > 0 and -1 or 1)
    end
end)

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverQuest")
    GameTooltip:AddLine("Left click / mouse wheel: cycle quests", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right click: return to AUTO", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-left click: navigate using Blizzard's quest tracking", 0.8, 0.8, 0.8)
    if state.mapCaution then
        GameTooltip:AddLine(state.mapCaution, 0.96, 0.74, 0.42, true)
    end
    if state.pickup then
        GameTooltip:AddLine("/fq skip hides an unavailable suggested quest",
            0.7, 0.7, 0.7)
    end
    if state.pickup then
        GameTooltip:AddLine("Possible new quest: " .. state.pickup.name, 0.45, 0.95, 0.56, true)
        local dest = Navigation and Navigation.Destination
            and Navigation:Destination(state.pickup.questID, "pickup",
                state.pickup.giverName or state.pickup.area)
            or state.pickup.giverName or state.pickup.area
        if dest then
            GameTooltip:AddLine("Where: " .. dest, 0.75, 0.92, 1.0, true)
        end
        GameTooltip:AddLine(string.format("Map: ~%.1f, %.1f (estimated quest giver)",
            state.pickup.x * 100, state.pickup.y * 100), 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Blizzard objective tracking starts after quest acceptance.",
            0.70, 0.84, 1.0, true)
        GameTooltip:AddLine("Compass / yards are straight-line estimates, not paths.",
            0.65, 0.65, 0.65, true)
        if (state.pickup.pickupCount or 1) > 1
            and type(state.pickup.pickupNames) == "table" then
            GameTooltip:AddLine("Other possible quests at this stop:",
                0.63, 0.90, 0.69)
            for i = 2, math.min(5, #state.pickup.pickupNames) do
                GameTooltip:AddLine("  " .. state.pickup.pickupNames[i],
                    0.82, 0.82, 0.82)
            end
        end
        GameTooltip:AddLine("Classic/Forever database prediction; offers not confirmed.",
            0.75, 0.69, 0.45, true)
    end
    local quest = FindQuest(state.focusQuestID)
    if quest then
        if quest.waypointText then
            GameTooltip:AddLine("Next step: " .. quest.waypointText, 0.65, 0.90, 1.0, true)
        end
        if (quest.waypointSource == "curated" or quest.waypointSource == "database")
            and quest.waypointX and quest.waypointY then
            GameTooltip:AddLine(string.format("Approx. location: %.1f, %.1f (%s)",
                quest.waypointX * 100, quest.waypointY * 100,
                quest.waypointArea or "search area"), 0.7, 0.85, 1, true)
            local confidenceNote = quest.waypointSource == "database"
                and "bundled catalog estimate: Classic/Forever, unverified in client"
                or (quest.waypointConfidence == "classic-fallback"
                    and "Unverified Classic location; Forever may differ"
                    or "Forever beta guide location; verify in game")
            GameTooltip:AddLine(confidenceNote, 0.65, 0.65, 0.65, true)
        end
        if Planner and Planner.GetChainPreview then
            local followups = Planner:GetChainPreview(quest.questID, 2)
            if #followups > 0 then
                GameTooltip:AddLine("Potential next quests after turn-in:", 0.73, 0.80, 0.95)
                for _, nextQuest in ipairs(followups) do
                    GameTooltip:AddLine("  " .. nextQuest.name, 0.75, 0.75, 0.75)
                end
            end
        end
        local area = GetAreaQuests(quest)
        if #area > 1 then
            GameTooltip:AddLine("Possibly in the same area:", 0.50, 0.90, 0.55)
            for i = 1, math.min(#area, 4) do
                local q = area[i]
                GameTooltip:AddLine("  " .. q.title .. " — " .. ObjectiveText(q.questID, false),
                    0.85, 0.85, 0.85, true)
            end
        end
    end
    if state.nextZones and #state.nextZones > 0 and not state.pickup
        and not FindQuest(state.focusQuestID) then
        GameTooltip:AddLine("Possible nearby leveling zones:", 0.55, 0.84, 1.0)
        for i = 1, math.min(3, #state.nextZones) do
            local zone = state.nextZones[i]
            GameTooltip:AddLine(zone.name .. " • " .. zone.possibleQuests
                .. " possibly eligible quests", 0.8, 0.8, 0.8)
            if zone.handoff then
                GameTooltip:AddLine("  " .. zone.handoff,0.65,0.70,0.82,true)
            end
        end
        GameTooltip:AddLine("Not a travel route; verify quest availability.",
            0.63, 0.63, 0.63, true)
    end
    if state.routeStop and state.routeStop.kind == "objective"
        and state.routeStop.stepLabel then
        GameTooltip:AddLine("Selected objective: " .. state.routeStop.stepLabel,
            0.65, 0.94, 0.70, true)
        local active = FindQuest(state.routeStop.questID)
        if active then
            GameTooltip:AddLine("Quest progress: "
                .. ObjectiveText(active.questID, active.complete),
                0.75, 0.75, 0.75, true)
        end
    end
    if state.routePlan and state.routePlan.stops and #state.routePlan.stops > 0
        and Route and Route.Describe then
        GameTooltip:AddLine("Suggested next stops (approx. map locations):", 0.53, 0.83, 1.0)
        for i, stop in ipairs(state.routePlan.stops) do
            GameTooltip:AddLine(tostring(i) .. ". " .. Route:Describe(stop),
                0.82, 0.82, 0.82, true)
        end
    end
    GameTooltip:AddLine("Mode: " .. (ForeverQuestDB and ForeverQuestDB.mode or "AUTO"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(ForeverQuestDB and ForeverQuestDB.locked and "/fq unlock to move" or "Drag to move, /fq lock to finish", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function MapXY(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos or not pos.GetXY then return nil end
    local safe, x, y = pcall(pos.GetXY, pos)
    if safe and type(x) == "number" and type(y) == "number" then return x, y end
end

local function BuildRoute()
    if not Route or not Route.Build then return nil end
    local mapID = GetBestMap()
    local px, py = MapXY(mapID)
    if not px then return nil end
    local pickups = {}
    if Planner and Planner.Available and Planner:Available() then
        -- Inspect the whole local catalog so a productive quest hub is not
        -- lost behind the first 35 nearest individual quest starters.
        pickups = Planner:GetNearby(mapID, 100)
    end
    local active = {}
    for _, q in ipairs(state.quests) do active[q.questID]=true end
    local plan = Route:Build(state.quests, pickups, mapID, px, py, {
        level = UnitLevel and UnitLevel("player") or 1,
        mode = ForeverQuestDB.routeMode or "balanced",
        avoided = AvoidedQuests(),
        active = active,
        groupSize = math.max(1,(GetNumGroupMembers and GetNumGroupMembers()) or 1),
        -- Stay with the current unfinished destination instead of treating
        -- every small movement as a reason to rewrite the whole circuit.
        preferredKey = ForeverQuestDB.mode == "AUTO"
            and state.routeStop and state.routeStop.mapID == mapID
            and state.routeStop.key or nil,
    })
    state.routePlan = plan
    return plan
end

local function RouteSelection(plan)
    local proposed = plan and plan.stops and plan.stops[1]
    if not proposed then return nil end
    local current = state.routeStop
    local inCombat = false
    if UnitAffectingCombat then
        local ok, combat = pcall(UnitAffectingCombat, "player")
        inCombat = ok and combat == true
    end
    if current and (inCombat or (state.routeKey and GetTime
        and GetTime() - state.lastRouteSwitch < 9)) then
        for _, stop in ipairs(plan.stops) do
            if stop.key == current.key then
                return stop
            end
        end
    end
    -- Never interrupt active combat with an unsolicited new quest pickup.
    if inCombat and proposed.kind == "pickup" then
        for _, stop in ipairs(plan.stops) do
            if stop.kind == "objective" then
                proposed = stop
                break
            end
        end
    end
    local key = proposed.key
    if key ~= state.routeKey then
        state.routeKey = key
        state.lastRouteSwitch = GetTime and GetTime() or 0
    end
    return proposed
end

local function PrintRoute()
    CollectQuests()
    RefreshFutureQuests()
    local plan = BuildRoute()
    if not plan then
        Print("Cannot calculate map-relative route at your current location.")
        return
    end
    if #plan.stops == 0 then
        Print("No location-backed quest stops found. Use /fq data to check database coverage.")
        return
    end
    Print("Suggested next stops (straight-line map estimates, not roads):")
    for i, stop in ipairs(plan.stops) do
        Print(tostring(i) .. ". " .. Route:Describe(stop))
        -- Show which other actions may overlap at the same location. Players
        -- can now see why the route favors an area, without extra map pins.
        if stop.nearby and #stop.nearby > 0 then
            local nearby, used = {}, {}
            for _, other in ipairs(stop.nearby) do
                local label = other.targetName or other.name
                if label and not used[label] then
                    used[label] = true
                    nearby[#nearby + 1] = label
                end
                if #nearby >= 3 then break end
            end
            if #nearby > 0 then
                Print("   Nearby tasks: " .. table.concat(nearby, ", "))
            end
        end
    end
end

local function ExplainFocus()
    if ForeverQuestDB.mode == "MANUAL" then
        Print("Manual choice: left-click to cycle stops; right-click for AUTO.")
        return
    end
    local stop = state.routeStop
    if not stop then
        Print("No location-backed stop selected. /fq data checks the catalog; /fq zones suggests adjacent zones.")
        return
    end
    local why
    if stop.kind == "pickup" then
        if (stop.pickupCount or 1) > 1 then
            why = stop.pickupCount .. " possible quests from nearby starters at one stop (unverified offers)"
        else
            why = "Possible new quest pickup near your route (unverified database offer)"
        end
    elseif stop.kind == "turnin" then
        why = "Completed quest and a useful turn-in stop along the route"
    else
        why = "Unfinished accepted quest objective with a known search area"
    end
    if (stop.overlapping or 0) > 0 then
        why = why .. "; " .. stop.overlapping
            .. " other tasks appear in the same area"
    end
    local confidence = stop.confidence or "unknown"
    local Strategy = _G.ForeverQuestStrategy
    if Strategy and Strategy.Explain then
        why = why .. ". " .. Strategy:Explain(stop, {
            level=UnitLevel and UnitLevel("player") or 1,
            mode=ForeverQuestDB.routeMode or "balanced",
            avoided=AvoidedQuests(),
            groupSize=math.max(1,(GetNumGroupMembers and GetNumGroupMembers()) or 1),
        })
    end
    Print(why .. ". Location source: " .. confidence
        .. ". /fq route lists alternatives.")
end

local function ObserveFocusedProgress()
    local stop=state.routeStop
    if not Knowledge or not stop or stop.kind~="objective"
        or type(stop.targetName)~="string" or stop.goalKey=="main" then
        return
    end
    local mapID=GetBestMap()
    if stop.mapID~=mapID then return end
    local x,y=MapXY(mapID)
    if not x or not y then return end
    local objectives=GetObjectives(stop.questID)
    if type(objectives)~="table" then return end
    for _,objective in ipairs(objectives) do
        if type(objective)=="table" then
            local label=objective.text or objective.description
            if type(label)=="string"
                and label:lower():find(stop.targetName:lower(),1,true) then
                local amount=tonumber(objective.numFulfilled)
                    or tonumber(label:match("(%d+)%s*/%s*%d+"))
                if amount then
                    Knowledge:ObserveProgress(ForeverQuestDB,
                        stop.questID,stop.goalKey,amount,mapID,x,y)
                end
                return
            end
        end
    end
end

RefreshFocus = function()
    -- Catch the objective increment while still pointing at its previous
    -- location, before the AUTO route might switch targets.
    ObserveFocusedProgress()
    CollectQuests()
    RefreshFutureQuests()
    state.nextZones = nil

    -- Rebuild in both AUTO and MANUAL modes. A manual stop should follow
    -- changing quest progress, rather than staying frozen at old coordinates.
    local plan = BuildRoute()
    local quest, manualPickup, manualStop
    if ForeverQuestDB.mode == "MANUAL" then
        if ForeverQuestDB.manualKind then
            for _, stop in ipairs((plan and plan.stops) or {}) do
                if stop.kind == ForeverQuestDB.manualKind
                    and stop.questID == ForeverQuestDB.manualQuestID
                    and stop.goalKey == (ForeverQuestDB.manualGoalKey or "main") then
                    manualStop = stop
                    break
                end
            end

            -- The desired objective might leave the top-five suggested
            -- stops as the character moves. Retain a deliberately selected
            -- objective as long as it is still unfinished.
            local choice = state.manualChoice
            if not manualStop and choice
                and choice.kind == ForeverQuestDB.manualKind
                and choice.questID == ForeverQuestDB.manualQuestID
                and choice.goalKey == (ForeverQuestDB.manualGoalKey or "main") then
                if choice.kind == "pickup" and choice.mapID == GetBestMap()
                    and not FindQuest(choice.questID)
                    and not IgnoredPickups()[choice.questID] then
                    manualStop = choice
                elseif choice.kind == "objective" then
                    local active = FindQuest(choice.questID)
                    if active and not active.complete then
                        for _, point in ipairs(active.goalPoints or {}) do
                            if point.goalKey == choice.goalKey then
                                manualStop = choice
                                manualStop.x, manualStop.y = point.x, point.y
                                manualStop.mapID = point.mapID
                                manualStop.targetName = point.targetName
                                manualStop.stepLabel = point.stepLabel
                                manualStop.confidence = point.confidence
                                break
                            end
                        end
                    end
                end
            end

            if manualStop then
                if manualStop.kind == "pickup" then
                    manualPickup = {
                        questID = manualStop.questID, name = manualStop.name,
                        x = manualStop.x, y = manualStop.y, mapID = manualStop.mapID,
                        confidence = manualStop.confidence,
                        kind = "quest starter", distance = manualStop.distance,
                        giverName = manualStop.giverName, area = manualStop.area,
                        pickupCount = manualStop.pickupCount,
                        pickupNames = manualStop.pickupNames,
                    }
                else
                    quest = FindQuest(manualStop.questID)
                    if not quest then manualStop = nil end
                end
            end
            if not manualStop then
                ForeverQuestDB.mode = "AUTO"
                ForeverQuestDB.manualQuestID = nil
                ForeverQuestDB.manualKind = nil
                ForeverQuestDB.manualGoalKey = nil
                state.manualChoice = nil
            end
        else
            quest = FindQuest(ForeverQuestDB.manualQuestID)
            if not quest then
                ForeverQuestDB.mode = "AUTO"
                ForeverQuestDB.manualQuestID = nil
                state.manualChoice = nil
            end
        end
    end

    if ForeverQuestDB.mode == "AUTO" then
        quest = PickAutoQuest()
    end

    state.pickup = manualPickup
    if ForeverQuestDB.mode == "AUTO" then
        local stop = RouteSelection(plan)
        state.routeStop = stop
        if stop then
            if stop.kind == "pickup" then
                state.pickup = {
                    questID = stop.questID, name = stop.name,
                    x = stop.x, y = stop.y, mapID = stop.mapID,
                    confidence = stop.confidence, kind = "quest starter",
                    giverName = stop.giverName, area = stop.area,
                    distance = stop.distance, pickupCount = stop.pickupCount,
                    pickupNames = stop.pickupNames,
                }
            else
                quest = FindQuest(stop.questID) or quest
            end
        end
    else
        state.routeStop = manualStop
    end

    -- A selected individual target must drive the arrow, coordinates and
    -- navigation too. Previously only the route list changed while the
    -- quest card kept pointing at the quest's *first* objective.
    local selected = state.routeStop
    if quest and selected and selected.kind == "objective"
        and selected.questID == quest.questID and selected.goalKey ~= "main" then
        quest.waypointMap = selected.mapID
        quest.waypointX, quest.waypointY = selected.x, selected.y
        quest.waypointSource = selected.waypointSource or "database"
        quest.waypointArea = selected.targetName or selected.area
        quest.waypointConfidence = selected.confidence
    end

    SetFocus(state.pickup and nil or quest)

    -- Keep local directional guidance but never create a map pin.
    -- Accepted quests use Blizzard's own official supertracking.
    state.navigationTarget = nil
    if state.pickup then
        state.navigationTarget = {
            mapID = state.pickup.mapID, x = state.pickup.x,
            y = state.pickup.y
        }
    elseif quest and quest.waypointMap
        and quest.waypointX and quest.waypointY then
        state.navigationTarget = {
            mapID = quest.waypointMap, x = quest.waypointX,
            y = quest.waypointY
        }
    end
    if not state.pickup and quest and Navigation and Navigation.TrackQuest then
        Navigation:TrackQuest(quest.questID)
    end

    ObserveFocusedProgress()
    if Items and Items.Update then
        Items:Update(state.pickup and nil or quest)
    end

    if state.pickup then
        local pickup = state.pickup
        frame.title:SetText("Pick up: " .. pickup.name)
        frame.title:SetTextColor(0.48, 0.95, 0.57)
        local destination = Navigation and Navigation.Destination
            and Navigation:Destination(pickup.questID, "pickup",
                pickup.giverName or pickup.area)
            or pickup.giverName or pickup.area
        if (pickup.pickupCount or 1) > 1 then
            frame.objective:SetText(pickup.pickupCount .. " possible quests"
                .. (destination and (" - " .. destination) or " at this stop"))
        else
            frame.objective:SetText(destination
                and ("Find " .. destination)
                or "Find quest starter (estimated location)")
        end
        local guidance = Navigation and Navigation.Guidance
            and Navigation:Guidance(state.navigationTarget)
        frame.distance:SetText(guidance and guidance.label
            or string.format("~%.0f,%.0f",
                pickup.x * 100, pickup.y * 100))
        local overlap = state.routeStop and state.routeStop.overlapping or 0
        frame.group:SetText(overlap > 0 and ("+" .. overlap) or "")
        frame.group:SetShown(overlap > 0)
        UpdateTitleLayout()
        return
    end

    if not quest then
        frame.distance:SetText("")
        frame.group:Hide()
        ShowDirectionArrow(false)

        local status = Planner and Planner:Status() or "No catalog"
        if status:find("Scanning", 1, true) then
            frame.title:SetText("Finding nearby quests...")
            frame.objective:SetText("Checking the built-in Classic/Forever catalog")
        else
            local options
            if Planner and Planner.GetNextZones then
                local active = {}
                for _, q in ipairs(state.quests) do active[q.questID] = true end
                for id in pairs(IgnoredPickups()) do active[id] = true end
                options = Planner:GetNextZones(GetBestMap(), UnitLevel("player"), active, 3)
            end
            state.nextZones = options
            if options and options[1] then
                frame.title:SetText("Consider: " .. options[1].name)
                frame.title:SetTextColor(0.62, 0.87, 1.0)
                local best=options[1]
                if (best.hops or 1)>1 and best.via then
                    local viaName
                    if C_Map and C_Map.GetMapInfo then
                        local ok,info=pcall(C_Map.GetMapInfo,best.via)
                        if ok and info then viaName=info.name end
                    end
                    frame.objective:SetText("Via " .. (viaName or "a nearby zone")
                        .. " • " .. best.possibleQuests .. " possible quests")
                else
                    frame.objective:SetText(best.possibleQuests
                        .. " possible quests in that zone")
                end
            else
                frame.title:SetText("No location-backed quest found")
                frame.objective:SetText("Try /fq zones or check live quest NPCs")
                frame.title:SetTextColor(0.9, 0.83, 0.52)
            end
        end
        UpdateTitleLayout()
        return
    end

    frame.title:SetText(quest.title)
    local objectiveText = ObjectiveText(quest.questID, quest.complete)
    local selectedGoal = state.routeStop
    if selectedGoal and selectedGoal.kind == "objective"
        and selectedGoal.questID == quest.questID
        and selectedGoal.goalKey ~= "main" and selectedGoal.targetName then
        -- The chosen destination should determine which objective text is
        -- shown. Previously the card always displayed the FIRST unfinished
        -- objective, even while routing to another one.
        local target = selectedGoal.targetName:lower()
        local matched = nil
        for _, obj in ipairs(GetObjectives(quest.questID) or {}) do
            local text = type(obj) == "table" and (obj.text or obj.description)
            local completed = type(obj) == "table"
                and (obj.finished == true or obj.isFinished == true)
            if type(text) == "string" and text:lower():find(target, 1, true)
                and not completed then
                matched = text
                break
            end
        end
        objectiveText = matched or selectedGoal.stepLabel or objectiveText
    elseif objectiveText == "Quest in progress" and quest.waypointText then
        objectiveText = quest.waypointText
    end
    frame.objective:SetText(objectiveText)
    -- Avoid presenting an unrelated quest-log distance as distance to our
    -- approximate objective; show map coordinates instead when using fallback.
    local guidance = Navigation and Navigation.Guidance
        and Navigation:Guidance(state.navigationTarget)
    if guidance and guidance.straightYards then
        frame.distance:SetText(guidance.label)
    elseif (quest.waypointSource == "curated" or quest.waypointSource == "database")
        and quest.waypointX then
        frame.distance:SetText(string.format("~%.0f,%.0f",
            quest.waypointX * 100, quest.waypointY * 100))
    else
        frame.distance:SetText(FormatDistance(quest.distance))
    end
    local overlap = state.routeStop and state.routeStop.overlapping or quest.nearbyCount or 0
    frame.group:SetText(overlap > 0 and ("+" .. overlap) or "")
    frame.group:SetShown(overlap > 0)
    UpdateTitleLayout()

    if quest.complete then
        frame.title:SetTextColor(0.35, 1.0, 0.45)
    else
        frame.title:SetTextColor(1, 0.82, 0.22)
    end
end

local function UpdateArrow()
    local questID = state.focusQuestID
    local quest = FindQuest(questID)
    local pickup = state.pickup
    local currentMap = GetBestMap()
    local mapID = (pickup and pickup.mapID) or (quest and quest.waypointMap) or currentMap
    local key = tostring(currentMap) .. ":" .. tostring(mapID)
    if state.mapCautionKey ~= key then
        state.mapCautionKey = key
        state.mapCaution = Travel and Travel.GetLayerCaution
            and Travel:GetLayerCaution(currentMap,mapID) or nil
    end
    if state.mapCaution then
        ShowDirectionArrow(false)
        return
    end
    if (not questID and not pickup) or not mapID
        or not (C_Map and C_Map.GetPlayerMapPosition) then
        ShowDirectionArrow(false)
        return
    end

    local targetX = pickup and pickup.x or (quest and quest.waypointX)
    local targetY = pickup and pickup.y or (quest and quest.waypointY)
    if not targetX or not targetY then
        local waypointMap
        waypointMap, targetX, targetY = GetWaypoint(questID, mapID)
        if waypointMap ~= mapID then
            ShowDirectionArrow(false)
            return
        end
    end
    if not targetX or not targetY then
        ShowDirectionArrow(false)
        return
    end

    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not position or not position.GetXY then
        ShowDirectionArrow(false)
        return
    end

    local safeXY, playerX, playerY = pcall(position.GetXY, position)
    if not safeXY or type(playerX) ~= "number" or type(playerY) ~= "number" then
        ShowDirectionArrow(false)
        return
    end

    -- Update compass/distance while moving, not just after quest changes.
    if Navigation and Navigation.Guidance and state.navigationTarget then
        local guidance = Navigation:Guidance(state.navigationTarget)
        if guidance and (pickup or guidance.straightYards)
            and frame.distance:GetText() ~= guidance.label then
            frame.distance:SetText(guidance.label)
            UpdateTitleLayout()
        end
    end

    local dx = targetX - playerX
    local dy = targetY - playerY
    if (dx * dx + dy * dy) < 0.000001 then
        ShowDirectionArrow(false)
        return
    end

    -- Use map aspect ratio for a physically meaningful bearing, not raw
    -- normalized coordinates (which skew diagonals on non-square maps).
    if C_Map and type(C_Map.GetMapWorldSize) == "function" then
        local sizeOK, width, height = pcall(C_Map.GetMapWorldSize, mapID)
        if sizeOK and type(width) == "number" and width > 0
            and type(height) == "number" and height > 0 then
            dx, dy = dx * width, dy * height
        end
    end

    -- Map Y grows down. Vanilla Lua 5.1 has no guaranteed math.atan2;
    -- use a quadrant-safe alternative when the client doesn't provide it.
    local worldAngle
    if type(math.atan2) == "function" then
        worldAngle = math.atan2(dx, -dy)
    elseif dy == 0 then
        worldAngle = dx >= 0 and math.pi / 2 or -math.pi / 2
    else
        worldAngle = math.atan(dx / -dy)
        if dy > 0 then worldAngle = worldAngle + math.pi end
    end
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    local relativeAngle = worldAngle - facing

    if frame.arrow.SetRotation then
        frame.arrow:SetRotation(relativeAngle)
        ShowDirectionArrow(true)
    else
        ShowDirectionArrow(false)
    end
end

frame:SetScript("OnUpdate", function(_, elapsed)
    if not ForeverQuestDB then return end

    state.refreshElapsed = state.refreshElapsed + elapsed
    state.arrowElapsed = state.arrowElapsed + elapsed

    if state.arrowElapsed >= 0.10 then
        state.arrowElapsed = 0
        UpdateArrow()
    end

    -- Live quest events trigger immediate refreshes; the background tick
    -- only needs to adapt periodically to movement and async DB scans.
    -- Previously we rebuilt ~4,000-quest plan context every SECOND.
    if state.refreshElapsed >= 3.0 then
        state.refreshElapsed = 0
        RefreshFocus()
    end
end)

local function ReportState()
    local mapID=GetBestMap()
    local stop=state.routeStop
    Print(string.format("REPORT v%s level=%s map=%s mode=%s preference=%s active=%d",
        VERSION,tostring(UnitLevel and UnitLevel("player") or "?"),
        tostring(mapID),tostring(ForeverQuestDB.mode),
        tostring(ForeverQuestDB.routeMode),#state.quests))
    Print("Catalog: " .. (Planner and Planner:Status() or "unavailable"))
    if stop then
        Print(string.format("Focus kind=%s quest=%s goal=%s map=%s at ~%.1f,%.1f source=%s",
            tostring(stop.kind),tostring(stop.questID),
            tostring(stop.goalKey),tostring(stop.mapID),
            (stop.x or 0)*100,(stop.y or 0)*100,
            tostring(stop.confidence or stop.waypointSource or "unknown")))
    else
        Print("No current coordinate-backed route stop.")
    end
    if state.mapCaution then Print("Navigation caution: "..state.mapCaution) end
    local count=Knowledge and Knowledge:Counts(ForeverQuestDB)
    if count then
        Print(string.format("Account observations: pickups=%d turnins=%d goals=%d",
            count.pickup,count.turnin,count.objective or 0))
    end
    Print("Use /fq here at a correctly found objective, or /fq skip on an unavailable pickup.")
end

local function DebugDump()
    Print("version " .. VERSION .. ", mode " .. tostring(ForeverQuestDB.mode))
    Print("mapID " .. tostring(GetBestMap()) .. ", quests " .. tostring(#state.quests) .. ", focus " .. tostring(state.focusQuestID))
    if Planner then Print(Planner:Status()) end
    if state.routePlan then Print("routeStops=" .. tostring(#state.routePlan.stops)) end
    local quest = FindQuest(state.focusQuestID)
    if quest then
        local mapID, x, y = GetWaypoint(quest.questID, GetBestMap())
        Print(string.format("%s (%d) complete=%s distance=%s waypoint=%s %.4f %.4f", quest.title, quest.questID, tostring(quest.complete), tostring(quest.distance), tostring(mapID), tonumber(x) or -1, tonumber(y) or -1))
    end
end

SLASH_FOREVERQUEST1 = "/fq"
SLASH_FOREVERQUEST2 = "/foreverquest"
SlashCmdList.FOREVERQUEST = function(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))

    if command == "unlock" then
        ForeverQuestDB.locked = false
        ApplyLockState()
        Print("unlocked — drag the card where you want it")
    elseif command == "lock" then
        ForeverQuestDB.locked = true
        ApplyLockState()
        SavePosition()
        Print("locked")
    elseif command == "auto" then
        ForeverQuestDB.mode = "AUTO"
        ForeverQuestDB.manualQuestID = nil
        ForeverQuestDB.manualKind = nil
        state.manualChoice = nil
        RefreshFocus()
        Print("AUTO mode")
    elseif command == "area" then
        CollectQuests()
        PrintArea()
    elseif command == "plan" or command == "pickups" then
        PrintPlan()
    elseif command == "data" then
        Print(Planner and Planner:Status() or "Quest data provider unavailable.")
    elseif command == "knowledge" then
        local counts = Knowledge and Knowledge:Counts(ForeverQuestDB)
        if not counts then
            Print("Account location learning is unavailable.")
        else
            local flights=0
            for _ in pairs(ForeverQuestDB.flightPaths or {}) do flights=flights+1 end
            Print(string.format("Account observed: %d pickups, %d turn-ins, %d objective areas, %d taxi nodes.",
                counts.pickup,counts.turnin,counts.objective or 0,flights))
        end
    elseif command == "here" then
        local stop=state.routeStop
        local mapID=GetBestMap()
        local x,y=MapXY(mapID)
        if stop and stop.kind=="objective" and stop.goalKey~="main"
            and stop.mapID==mapID and x and y and Knowledge then
            Knowledge:Observe(ForeverQuestDB,"objective",
                stop.questID,mapID,x,y,stop.goalKey)
            RefreshFocus()
            Print("Learned this objective's current location for your other characters.")
        else
            Print("Select a specific quest objective and stand at its actual location first.")
        end
    elseif command == "knowledge clear" then
        if Knowledge then Knowledge:Clear(ForeverQuestDB) end
        if Planner then Planner:Invalidate() end
        RefreshFocus()
        Print("Cleared account-observed quest locations.")
    elseif command == "route" then
        PrintRoute()
    elseif command == "why" then
        ExplainFocus()
    elseif command == "mode" then
        Print("Questing preference: " .. (ForeverQuestDB.routeMode or "balanced")
            .. ". Options: /fq mode fast, /fq mode balanced, /fq mode complete")
    elseif command == "mode fast" or command == "mode balanced"
        or command == "mode complete" then
        ForeverQuestDB.routeMode = command:sub(6)
        state.routeKey = nil
        state.routeStop = nil
        RefreshFocus()
        Print("Questing preference: " .. ForeverQuestDB.routeMode)
    elseif command == "avoid" then
        local stop = state.routeStop
        local quest = stop and stop.questID and FindQuest(stop.questID)
        if quest then
            AvoidedQuests()[quest.questID] = true
            state.routeStop, state.routeKey = nil, nil
            if Planner then Planner:Invalidate() end
            ForeverQuestDB.mode = "AUTO"
            RefreshFocus()
            Print("Avoiding " .. quest.title
                .. " in AUTO. /fq unavoid restores avoided quests.")
        else
            Print("Select an accepted quest objective before using /fq avoid.")
        end
    elseif command == "unavoid" then
        local avoided = AvoidedQuests()
        for id in pairs(avoided) do avoided[id] = nil end
        if Planner then Planner:Invalidate() end
        RefreshFocus()
        Print("Cleared your character's avoided quests.")
    elseif command == "zones" then
        if not Planner or not Planner.GetNextZones then
            Print("Bundled zone advisor is unavailable.")
        else
            CollectQuests()
            local active = {}
            for _, q in ipairs(state.quests) do active[q.questID] = true end
            for id in pairs(IgnoredPickups()) do active[id] = true end
            local options = Planner:GetNextZones(
                GetBestMap(), UnitLevel("player"), active, 3)
            if #options == 0 then
                Print("No nearby or connected zones with plausible quests in the baseline at this level.")
            else
                Print("Neighboring zones with possible quests (catalog estimates):")
                for i = 1, math.min(3, #options) do
                    local option=options[i]
                    Print(i .. ". " .. option.name .. " — "
                        .. option.possibleQuests .. " possible quests; "
                        .. (option.handoff or "zone transition unverified"))
                end
            end
        end
    elseif command == "skip" then
        if state.pickup then
            local id, name = state.pickup.questID, state.pickup.name
            IgnoredPickups()[id] = true
            if Planner then Planner:Invalidate() end
            state.pickup = nil
            state.routeStop = nil
            state.manualChoice = nil
            ForeverQuestDB.mode = "AUTO"
            ForeverQuestDB.manualKind = nil
            ForeverQuestDB.manualQuestID = nil
            RefreshFocus()
            Print("Skipped provisional pickup: " .. tostring(name)
                .. ". /fq unskip restores hidden suggestions.")
        else
            Print("No suggested pickup to skip right now.")
        end
    elseif command == "unskip" then
        local ignored = IgnoredPickups()
        for id in pairs(ignored) do ignored[id] = nil end
        if Planner then Planner:Invalidate() end
        RefreshFocus()
        Print("Restored skipped possible quest pickups for this character.")
    elseif command == "navigate" then
        NavigateToFocus()
    elseif command == "report" then
        ReportState()
    elseif command == "debug" then
        CollectQuests()
        DebugDump()
    elseif command == "reset" then
        ForeverQuestDB.point = defaults.point
        ForeverQuestDB.relativePoint = defaults.relativePoint
        ForeverQuestDB.x = defaults.x
        ForeverQuestDB.y = defaults.y
        frame:ClearAllPoints()
        frame:SetPoint(defaults.point, UIParent, defaults.relativePoint, defaults.x, defaults.y)
        Print("position reset")
    else
        Print("/fq unlock, /fq lock, /fq auto, /fq route, /fq why, /fq mode fast|balanced|complete, /fq avoid, /fq unavoid, /fq zones, /fq plan, /fq skip, /fq unskip, /fq here, /fq knowledge, /fq report, /fq data, /fq navigate, /fq debug, /fq reset")
    end
end

FQ:RegisterEvent("PLAYER_LOGIN")
FQ:RegisterEvent("PLAYER_LEVEL_UP")
FQ:RegisterEvent("PLAYER_ENTERING_WORLD")
FQ:RegisterEvent("QUEST_LOG_UPDATE")
FQ:RegisterEvent("QUEST_ACCEPTED")
FQ:RegisterEvent("QUEST_REMOVED")
FQ:RegisterEvent("QUEST_TURNED_IN")
FQ:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FQ:RegisterEvent("ZONE_CHANGED")
FQ:RegisterEvent("ZONE_CHANGED_INDOORS")
pcall(FQ.RegisterEvent,FQ,"TAXIMAP_OPENED")
pcall(FQ.RegisterEvent,FQ,"BAG_UPDATE_DELAYED")
pcall(FQ.RegisterEvent,FQ,"PLAYER_REGEN_ENABLED")

FQ:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        CopyDefaults()
        frame:ClearAllPoints()
        frame:SetPoint(ForeverQuestDB.point, UIParent, ForeverQuestDB.relativePoint, ForeverQuestDB.x, ForeverQuestDB.y)
        ApplyLockState()
        RefreshFocus()
        Print("v" .. VERSION .. " loaded. /fq for commands.")
    else
        if ForeverQuestDB then
            if Knowledge and (event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN") then
                local first, second = ...
                local questID = event=="QUEST_ACCEPTED" and second or first
                if type(questID)~="number" then questID=first end
                local mapID=GetBestMap()
                local x,y=MapXY(mapID)
                if type(questID)=="number" and x and y then
                    Knowledge:Observe(ForeverQuestDB,
                        event=="QUEST_ACCEPTED" and "pickup" or "turnin",
                        questID,mapID,x,y)
                end
            end
            if event=="TAXIMAP_OPENED" and Travel and Travel.LearnFlightPaths then
                Travel:LearnFlightPaths(ForeverQuestDB)
                return
            end
            if Planner and (
                event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or
                event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP"
            ) then Planner:Invalidate() end
            RefreshFocus()
            if event=="PLAYER_REGEN_ENABLED" and Items and Items.Refresh then
                Items:Refresh()
            end
        end
    end
end)
