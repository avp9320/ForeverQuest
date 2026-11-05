local ADDON_NAME = ...

local FQ = CreateFrame("Frame")
local Planner = _G.ForeverQuestPlanner
local Route = _G.ForeverQuestRoute
local VERSION = "0.3.0"

local defaults = {
    locked = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 180,
    mode = "AUTO",
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
    focusScore = nil,
    lastFocusChange = 0,
    refreshElapsed = 0,
    arrowElapsed = 0,
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
            local waypointArea, waypointConfidence
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
            if not waypointMap and Planner and Planner.GetActivePosition then
                local location = Planner:GetActivePosition(questID, complete, currentMap)
                if location then
                    waypointMap, waypointX, waypointY = location.mapID, location.x, location.y
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
                mapDistance = mapDistance,
                score = score,
                logIndex = index,
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
        if C_Map and type(C_Map.SetUserWaypoint) == "function"
            and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function" then
            local ok, allowed = true, true
            if C_Map.CanSetUserWaypointOnMap then
                ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, item.mapID)
            end
            if ok and allowed then
                local setOK, setResult = pcall(function()
                    local point = UiMapPoint.CreateFromCoordinates(item.mapID, item.x, item.y)
                    return C_Map.SetUserWaypoint(point)
                end)
                if setOK and setResult ~= false then
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                    end
                    Print(string.format("Possible pickup: %s, ~%.1f, %.1f (provisional).",
                        item.name, item.x * 100, item.y * 100))
                    return
                end
            end
        end
        Print("The client did not allow placing this suggested pickup waypoint.")
        return
    end
    local quest = FindQuest(state.focusQuestID)
    if not quest then Print("No focused quest."); return end

    -- For a curated objective, the game has no usable quest waypoint.
    -- Set a normal Blizzard map waypoint on explicit user request only.
    if (quest.waypointSource == "curated" or quest.waypointSource == "database") and quest.waypointMap
        and quest.waypointX and quest.waypointY
        and C_Map and type(C_Map.SetUserWaypoint) == "function"
        and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function" then
        local allowed = true
        if type(C_Map.CanSetUserWaypointOnMap) == "function" then
            local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, quest.waypointMap)
            allowed = ok and can
        end
        if allowed then
            local ok, set = pcall(function()
                local point = UiMapPoint.CreateFromCoordinates(
                    quest.waypointMap, quest.waypointX, quest.waypointY)
                return C_Map.SetUserWaypoint(point)
            end)
            if ok and set ~= false then
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                end
                Print(string.format("Approximate %s waypoint: %.1f, %.1f (%s).",
                    quest.title, quest.waypointX * 100, quest.waypointY * 100,
                    quest.waypointSource == "database" and "QuestieDB estimate"
                        or (quest.waypointConfidence == "classic-fallback"
                            and "Classic fallback" or "Forever guide")))
                return
            end
        end
    end

    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" then
        local ok = pcall(C_SuperTrack.SetSuperTrackedQuestID, quest.questID)
        if ok then
            Print("Blizzard quest navigation now tracks " .. quest.title .. ".")
            return
        end
    end
    Print("No client-supported waypoint is available for this quest.")
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

local function RefreshFutureQuests()
    if not Planner or not Planner.Available or not Planner:Available() then return end
    local active = {}
    for _, quest in ipairs(state.quests) do active[quest.questID] = true end
    for id in pairs(IgnoredPickups()) do active[id] = true end
    Planner:Scan(GetBestMap(), UnitLevel("player"), active)
end

local function NearbyPickup()
    if not Planner or not Planner.Available or not Planner:Available() then return nil end
    return Planner:GetNearby(GetBestMap(), 1)[1]
end

local function PrintPlan()
    CollectQuests()
    if not Planner or not Planner:Available() then
        Print("Future quest discovery needs QuestieDB-Forever (data-only addon).")
        Print("Live quest tracking and starter locations still work without it.")
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
    local best = state.quests[1]
    if not best then
        return nil
    end

    local current = FindQuest(state.focusQuestID)
    if current and ForeverQuestDB.mode == "AUTO" then
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
frame:SetSize(258, 46)
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
frame.arrow:SetSize(17, 17)
frame.arrow:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -6)
frame.arrow:SetTexture("Interface\\MINIMAP\\MinimapArrow")
frame.arrow:SetAlpha(0.9)
frame.arrow:Hide()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetJustifyH("LEFT")
frame.title:SetWordWrap(false)
frame.title:SetTextColor(1, 0.82, 0.22)

frame.distance = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.distance:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -7)
frame.distance:SetWidth(54)
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
        frame.arrow:IsShown() and 31 or 11, -7)
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
        for i, stop in ipairs(stops) do
            if stop.kind == kind and stop.questID == questID then
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
        state.manualChoice = selected
        if RefreshFocus then RefreshFocus() end
        return
    end

    if #state.quests == 0 then return end
    ForeverQuestDB.mode = "MANUAL"
    ForeverQuestDB.manualKind = nil
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
        state.manualChoice = nil
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
    if state.pickup then
        GameTooltip:AddLine("/fq skip hides an unavailable suggested quest",
            0.7, 0.7, 0.7)
    end
    if state.pickup then
        GameTooltip:AddLine("Possible new quest: " .. state.pickup.name, 0.45, 0.95, 0.56, true)
        GameTooltip:AddLine(string.format("Quest giver ~%.1f, %.1f (%s)",
            state.pickup.x * 100, state.pickup.y * 100, state.pickup.kind), 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Classic/Forever database prediction; offer not confirmed.",
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
                and "QuestieDB estimate: Classic/Forever, unverified in client"
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
        pickups = Planner:GetNearby(mapID, 35)
    end
    local plan = Route:Build(state.quests, pickups, mapID, px, py)
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
            if stop.kind == current.kind and stop.questID == current.questID then
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
    local key = proposed.kind .. ":" .. tostring(proposed.questID)
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
    end
end

RefreshFocus = function()
    CollectQuests()
    RefreshFutureQuests()

    local quest, manualPickup
    if ForeverQuestDB.mode == "MANUAL" then
        if ForeverQuestDB.manualKind == "pickup" then
            local choice = state.manualChoice
            if choice and choice.questID == ForeverQuestDB.manualQuestID
                and choice.mapID == GetBestMap()
                and not FindQuest(choice.questID) then
                manualPickup = {
                    questID = choice.questID, name = choice.name,
                    x = choice.x, y = choice.y, mapID = choice.mapID,
                    confidence = choice.confidence, kind = "quest starter",
                    distance = choice.distance,
                }
            else
                ForeverQuestDB.mode = "AUTO"
                ForeverQuestDB.manualQuestID = nil
                ForeverQuestDB.manualKind = nil
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

    if not quest and not manualPickup then quest = PickAutoQuest() end

    -- A nearby unaccepted quest is often worth grabbing on the way, but
    -- don't interrupt an active objective or nearby completed turn-in.
    state.pickup = manualPickup
    if ForeverQuestDB.mode == "AUTO" then
        local plan = BuildRoute()
        local stop = RouteSelection(plan)
        state.routeStop = stop
        if stop then
            if stop.kind == "pickup" then
                state.pickup = {
                    questID = stop.questID, name = stop.name,
                    x = stop.x, y = stop.y, mapID = stop.mapID,
                    confidence = stop.confidence, kind = "quest starter",
                    distance = stop.distance
                }
            else
                quest = FindQuest(stop.questID) or quest
            end
        end
    else
        state.routeStop = nil
    end

    SetFocus(state.pickup and nil or quest)

    if state.pickup then
        local pickup = state.pickup
        frame.title:SetText("Pick up: " .. pickup.name)
        frame.title:SetTextColor(0.48, 0.95, 0.57)
        frame.objective:SetText("Possible new quest (" .. pickup.kind .. ")")
        frame.distance:SetText(string.format("~%.0f,%.0f",
            pickup.x * 100, pickup.y * 100))
        local overlap = state.routeStop and state.routeStop.overlapping or 0
        frame.group:SetText(overlap > 0 and ("+" .. overlap) or "")
        frame.group:SetShown(overlap > 0)
        UpdateTitleLayout()
        return
    end

    if not quest then
        frame.title:SetText("No active quests")
        frame.objective:SetText("Pick up a quest and ForeverQuest will focus it here.")
        frame.distance:SetText("")
        frame.group:Hide()
        ShowDirectionArrow(false)
        UpdateTitleLayout()
        return
    end

    frame.title:SetText(quest.title)
    local objectiveText = ObjectiveText(quest.questID, quest.complete)
    if objectiveText == "Quest in progress" and quest.waypointText then
        objectiveText = quest.waypointText
    end
    frame.objective:SetText(objectiveText)
    -- Avoid presenting an unrelated quest-log distance as distance to our
    -- approximate objective; show map coordinates instead when using fallback.
    if (quest.waypointSource == "curated" or quest.waypointSource == "database")
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
    local mapID = (pickup and pickup.mapID) or (quest and quest.waypointMap) or GetBestMap()
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

    local dx = targetX - playerX
    local dy = targetY - playerY
    if (dx * dx + dy * dy) < 0.000001 then
        ShowDirectionArrow(false)
        return
    end

    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    -- Map Y grows downward, so negate dy to convert to a north-up angle.
    local worldAngle = math.atan2(dx, -dy)
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

    if state.refreshElapsed >= 1.0 then
        state.refreshElapsed = 0
        RefreshFocus()
    end
end)

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
    elseif command == "route" then
        PrintRoute()
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
        Print("/fq unlock, /fq lock, /fq auto, /fq route, /fq plan, /fq skip, /fq unskip, /fq data, /fq area, /fq navigate, /fq debug, /fq reset")
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

FQ:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CopyDefaults()
        frame:ClearAllPoints()
        frame:SetPoint(ForeverQuestDB.point, UIParent, ForeverQuestDB.relativePoint, ForeverQuestDB.x, ForeverQuestDB.y)
        ApplyLockState()
        RefreshFocus()
        Print("v" .. VERSION .. " loaded. /fq for commands.")
    else
        if ForeverQuestDB then
            if Planner and (
                event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or
                event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP"
            ) then Planner:Invalidate() end
            RefreshFocus()
        end
    end
end)
