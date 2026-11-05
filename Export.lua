-- ForeverQuest quick character export for sharing quest progress without screenshots.
-- Nothing is sent automatically. The player manually copies the report.
local Export = {}
_G.ForeverQuestExport = Export

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

local function clean(value)
    if value == nil then return "unknown" end
    local s = tostring(value)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[\r\n\t]", " "):gsub("%s+", " ")
    return s
end

local function itemName(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("%[([^%]]+)%]")
    return name or clean(link)
end

local function currentCharacterKey()
    local guid = safeCall(UnitGUID, "player")
    if guid then return tostring(guid) end
    return clean(safeCall(UnitName, "player")) .. "-" .. clean(safeCall(GetRealmName))
end

local function moneyText(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    return string.format("%dg %ds %dc", math.floor(copper / 10000),
        math.floor(copper / 100) % 100, copper % 100)
end

local function append(lines, line)
    lines[#lines + 1] = line
end

local function addCharacter(lines)
    local name = safeCall(UnitName, "player") or "Unknown"
    local race = safeCall(UnitRace, "player") or "Unknown"
    local class = safeCall(UnitClass, "player") or "Unknown"
    local level = safeCall(UnitLevel, "player") or "?"
    local realm = safeCall(GetRealmName) or "Unknown"
    append(lines, "Character: " .. clean(name) .. " - " .. clean(race) ..
        " " .. clean(class) .. " (level " .. tostring(level) .. ")")
    append(lines, "Realm: " .. clean(realm))
    local xp, maxXP = safeCall(UnitXP, "player"), safeCall(UnitXPMax, "player")
    if type(xp) == "number" and type(maxXP) == "number" and maxXP > 0 then
        append(lines, string.format("XP: %d / %d", xp, maxXP))
    end
    append(lines, "Money: " .. moneyText(safeCall(GetMoney)))
    local zone = safeCall(GetZoneText) or "Unknown"
    local subzone = safeCall(GetSubZoneText)
    local area = clean(zone)
    if subzone and subzone ~= "" and subzone ~= zone then
        area = area .. " / " .. clean(subzone)
    end
    local mapID = safeCall(C_Map and C_Map.GetBestMapForUnit, "player")
    local location = area
    if type(mapID) == "number" then
        location = location .. " (map " .. tostring(mapID) .. ")"
        local position = safeCall(C_Map and C_Map.GetPlayerMapPosition,
            mapID, "player")
        if position and type(position.GetXY) == "function" then
            local x, y = safeCall(position.GetXY, position)
            if type(x) == "number" and type(y) == "number" then
                location = location .. string.format(" %.1f, %.1f", x * 100, y * 100)
            end
        end
    end
    append(lines, "Location: " .. location)
end

local function addEquipment(lines)
    append(lines, "")
    append(lines, "EQUIPMENT")
    local slots = {
        {16, "Main hand"}, {17, "Off hand"},
        {1, "Head"}, {2, "Neck"}, {3, "Shoulder"},
        {5, "Chest"}, {6, "Waist"}, {7, "Legs"},
        {8, "Feet"}, {9, "Wrist"}, {10, "Hands"},
        {11, "Ring 1"}, {12, "Ring 2"},
        {13, "Trinket 1"}, {14, "Trinket 2"},
        {15, "Back"}, {18, "Ranged"},
    }
    local found = 0
    for _, slot in ipairs(slots) do
        local link = safeCall(GetInventoryItemLink, "player", slot[1])
        if link then
            found = found + 1
            append(lines, slot[2] .. ": " .. clean(itemName(link)))
        end
    end
    if found == 0 then append(lines, "(equipment API unavailable)") end
end

local function addProfessions(lines)
    append(lines, "")
    append(lines, "PROFESSIONS")
    local indices = {safeCall(GetProfessions)}
    local found = 0
    for _, index in ipairs(indices) do
        if type(index) == "number" and index > 0 then
            local name, _, skill, maxSkill = safeCall(GetProfessionInfo, index)
            if name then
                found = found + 1
                local suffix = ""
                if type(skill) == "number" then
                    suffix = " " .. tostring(skill)
                    if type(maxSkill) == "number" then
                        suffix = suffix .. "/" .. tostring(maxSkill)
                    end
                end
                append(lines, clean(name) .. suffix)
            end
        end
    end
    if found == 0 then append(lines, "(none known or API unavailable)") end
end

local function addQuests(lines)
    append(lines, "")
    append(lines, "ACTIVE QUESTS (live quest log)")
    local api = C_QuestLog
    if not (api and type(api.GetNumQuestLogEntries) == "function" and
        type(api.GetInfo) == "function") then
        append(lines, "(quest log API unavailable)")
        return
    end
    local entries = safeCall(api.GetNumQuestLogEntries)
    if type(entries) ~= "number" then
        append(lines, "(quest log not available)")
        return
    end
    local count = 0
    for i = 1, math.min(entries, 200) do
        local info = safeCall(api.GetInfo, i)
        if type(info) == "table" and not info.isHeader and not info.isHidden then
            local id = info.questID
            if type(id) == "number" and id > 0 then
                count = count + 1
                local title = info.title
                if not title or title == "" then
                    title = safeCall(api.GetTitleForQuestID, id) or ("Quest " .. id)
                end
                local completed = safeCall(api.IsComplete, id) == true
                local levelText = type(info.level) == "number" and
                    ("L" .. tostring(info.level) .. " ") or ""
                append(lines, string.format("- [%d] %s%s%s", id, levelText,
                    clean(title), completed and " [READY TO TURN IN]" or ""))
                local objectives = safeCall(api.GetQuestObjectives, id)
                if type(objectives) == "table" then
                    for _, objective in ipairs(objectives) do
                        if type(objective) == "table" then
                            local text = objective.text or objective.description
                            if text and text ~= "" then
                                local done = objective.finished or objective.isFinished
                                append(lines, "    " .. (done and "[done] " or "[ ] ") ..
                                    clean(text))
                            end
                        end
                    end
                end
            end
        end
    end
    if count == 0 then append(lines, "(quest log empty)") end
end

local function addRecentTurnins(lines)
    append(lines, "")
    append(lines, "RECENT TURN-INS (recorded while this exporter was installed)")
    local db = ForeverQuestDB
    local recent = type(db) == "table" and db.exportRecentTurnins
    recent = type(recent) == "table" and recent[currentCharacterKey()] or nil
    if type(recent) ~= "table" or #recent == 0 then
        append(lines, "(none recorded yet)")
        return
    end
    for _, entry in ipairs(recent) do
        append(lines, string.format("- [%d] %s", entry.id, clean(entry.title)))
    end
end

local function addBagSummary(lines)
    append(lines, "")
    append(lines, "BAGS")
    local grouped, order = {}, {}
    local countItems = 0
    for bag = 0, 4 do
        local slots = safeCall(C_Container and C_Container.GetContainerNumSlots, bag)
        if type(slots) ~= "number" then
            slots = safeCall(GetContainerNumSlots, bag)
        end
        for slot = 1, math.min(tonumber(slots) or 0, 40) do
            local link = safeCall(C_Container and C_Container.GetContainerItemLink,
                bag, slot) or safeCall(GetContainerItemLink, bag, slot)
            if link then
                local name = itemName(link)
                local info = safeCall(C_Container and C_Container.GetContainerItemInfo,
                    bag, slot)
                local quantity = type(info) == "table" and info.stackCount or nil
                if not quantity then
                    local _, oldCount = safeCall(GetContainerItemInfo, bag, slot)
                    quantity = oldCount
                end
                quantity = tonumber(quantity) or 1
                local key = clean(name)
                if not grouped[key] then
                    grouped[key] = 0
                    order[#order + 1] = key
                end
                grouped[key] = grouped[key] + quantity
                countItems = countItems + 1
            end
        end
    end
    table.sort(order)
    for _, name in ipairs(order) do
        append(lines, "- " .. name .. " x" .. tostring(grouped[name]))
    end
    if countItems == 0 then append(lines, "(no bag items found or API unavailable)") end
end

function Export.BuildReport()
    local lines = {"FOREVERQUEST CHARACTER REPORT v1", "Manual export - no automatic sharing"}
    addCharacter(lines)
    addEquipment(lines)
    addProfessions(lines)
    addQuests(lines)
    addRecentTurnins(lines)
    addBagSummary(lines)
    return table.concat(lines, "\n")
end

local window, editBox
function Export.Open()
    if not UIParent or type(CreateFrame) ~= "function" then
        return
    end
    if not window then
        window = CreateFrame("Frame", "ForeverQuestExportWindow", UIParent)
        window:SetSize(720, 480)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", function(self) self:StartMoving() end)
        window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local backdrop = window:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(window)
        backdrop:SetColorTexture(0.06, 0.07, 0.09, 0.97)
        local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText("ForeverQuest - Character Export")
        local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 18, -40)
        hint:SetText("Text selected: press Ctrl+C, then paste into ChatGPT. No automatic uploads.")
        local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() window:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -67)
        scroll:SetPoint("BOTTOMRIGHT", -33, 50)
        editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(0)
        editBox:SetAutoFocus(false)
        editBox:SetWidth(655)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            window:Hide()
        end)
        scroll:SetScrollChild(editBox)
        local selectButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        selectButton:SetSize(110, 24)
        selectButton:SetPoint("BOTTOMLEFT", 18, 14)
        selectButton:SetText("Select all")
        selectButton:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)
        local refreshButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        refreshButton:SetSize(110, 24)
        refreshButton:SetPoint("LEFT", selectButton, "RIGHT", 10, 0)
        refreshButton:SetText("Refresh report")
        refreshButton:SetScript("OnClick", function() Export.Open() end)
    end
    local report = Export.BuildReport()
    editBox:SetText(report)
    -- Multiline edit boxes calculate their display height from line count.
    local _, breaks = report:gsub("\n", "\n")
    editBox:SetHeight(math.max(350, (breaks + 2) * 16))
    window:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

SLASH_FOREVERQUESTEXPORT1 = "/fqexport"
SlashCmdList.FOREVERQUESTEXPORT = function()
    Export.Open()
end

-- Record only turn-ins observed after this feature is installed. This avoids
-- exporting thousands of historical quest IDs and keeps the report readable.
if type(CreateFrame) == "function" then
    local observer = CreateFrame("Frame")
    observer:RegisterEvent("QUEST_TURNED_IN")
    observer:SetScript("OnEvent", function(_, _, questID)
        if type(questID) ~= "number" or questID <= 0 then return end
        ForeverQuestDB = ForeverQuestDB or {}
        ForeverQuestDB.exportRecentTurnins =
            ForeverQuestDB.exportRecentTurnins or {}
        local key = currentCharacterKey()
        local entries = ForeverQuestDB.exportRecentTurnins[key] or {}
        ForeverQuestDB.exportRecentTurnins[key] = entries
        local title = safeCall(C_QuestLog and C_QuestLog.GetTitleForQuestID,
            questID) or ("Quest " .. questID)
        -- Keep last 20 turn-ins, newest first, without duplicates.
        for i = #entries, 1, -1 do
            if entries[i].id == questID then table.remove(entries, i) end
        end
        table.insert(entries, 1, {id=questID, title=title})
        while #entries > 20 do table.remove(entries) end
    end)
end
