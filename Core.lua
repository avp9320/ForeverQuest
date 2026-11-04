local ADDON_NAME = ...

local FQ = CreateFrame("Frame")
local VERSION = "0.1.4"

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

    for index = 1, numEntries do
        local infoOK, info = pcall(C_QuestLog.GetInfo, index)
        if infoOK and type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 and not info.isHidden then
            local questID = info.questID
            local complete = IsQuestComplete(questID)
            local distance, onContinent = GetQuestDistance(questID)
            local waypointMap = GetWaypoint(questID, currentMap)
            local sameMap = waypointMap and currentMap and waypointMap == currentMap or false

            local score
            if distance and onContinent then
                score = distance
            elseif sameMap then
                score = 2500
            elseif onContinent then
                score = 10000
            else
                score = 25000
            end

            if sameMap then
                score = score - 600
            end
            if complete then
                score = score - 900
            end

            table.insert(state.quests, {
                questID = questID,
                title = SafeQuestTitle(questID, info.title),
                complete = complete,
                distance = distance,
                onContinent = onContinent,
                sameMap = sameMap,
                score = score,
                logIndex = index,
            })
        end
    end

    table.sort(state.quests, function(a, b)
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

local function PickAutoQuest()
    local best = state.quests[1]
    if not best then
        return nil
    end

    local current = FindQuest(state.focusQuestID)
    if current and ForeverQuestDB.mode == "AUTO" then
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

local function UpdateTitleLayout()
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT",
        frame.arrow:IsShown() and 31 or 11, -7)
    if frame.distance:GetText() ~= "" then
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

local function ManualCycle(direction)
    if #state.quests == 0 then
        return
    end

    ForeverQuestDB.mode = "MANUAL"
    local currentIndex = 1
    for index, quest in ipairs(state.quests) do
        if quest.questID == state.focusQuestID then
            currentIndex = index
            break
        end
    end

    currentIndex = currentIndex + direction
    if currentIndex > #state.quests then
        currentIndex = 1
    elseif currentIndex < 1 then
        currentIndex = #state.quests
    end

    ForeverQuestDB.manualQuestID = state.quests[currentIndex].questID
    SetFocus(state.quests[currentIndex])
end

frame:SetScript("OnClick", function(_, button)
    if not ForeverQuestDB.locked then
        return
    end

    if button == "RightButton" then
        ForeverQuestDB.mode = "AUTO"
        ForeverQuestDB.manualQuestID = nil
        SetFocus(PickAutoQuest())
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
    GameTooltip:AddLine("Mode: " .. (ForeverQuestDB and ForeverQuestDB.mode or "AUTO"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(ForeverQuestDB and ForeverQuestDB.locked and "/fq unlock to move" or "Drag to move, /fq lock to finish", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function RefreshFocus()
    CollectQuests()

    local quest
    if ForeverQuestDB.mode == "MANUAL" then
        quest = FindQuest(ForeverQuestDB.manualQuestID)
        if not quest then
            ForeverQuestDB.mode = "AUTO"
            ForeverQuestDB.manualQuestID = nil
        end
    end

    if not quest then
        quest = PickAutoQuest()
    end

    SetFocus(quest)

    if not quest then
        frame.title:SetText("No active quests")
        frame.objective:SetText("Pick up a quest and ForeverQuest will focus it here.")
        frame.distance:SetText("")
        ShowDirectionArrow(false)
        UpdateTitleLayout()
        return
    end

    frame.title:SetText(quest.title)
    frame.objective:SetText(ObjectiveText(quest.questID, quest.complete))
    frame.distance:SetText(FormatDistance(quest.distance))
    UpdateTitleLayout()

    if quest.complete then
        frame.title:SetTextColor(0.35, 1.0, 0.45)
    else
        frame.title:SetTextColor(1, 0.82, 0.22)
    end
end

local function UpdateArrow()
    local questID = state.focusQuestID
    local mapID = GetBestMap()
    if not questID or not mapID or not (C_Map and C_Map.GetPlayerMapPosition) then
        ShowDirectionArrow(false)
        return
    end

    local waypointMap, targetX, targetY = GetWaypoint(questID, mapID)
    if waypointMap ~= mapID or not targetX or not targetY then
        ShowDirectionArrow(false)
        return
    end

    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not position or not position.GetXY then
        ShowDirectionArrow(false)
        return
    end

    local playerX, playerY = position:GetXY()
    if not playerX or not playerY then
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
        RefreshFocus()
        Print("AUTO mode")
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
        Print("/fq unlock, /fq lock, /fq auto, /fq debug, /fq reset")
    end
end

FQ:RegisterEvent("PLAYER_LOGIN")
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
            RefreshFocus()
        end
    end
end)
