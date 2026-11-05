-- ForeverQuest contextual quest-item button.
-- Only Blizzard-declared special quest items are shown. NEVER infer an item
-- from its name or run protected UseItemByName() from an OnClick handler.
-- SecureActionButtonTemplate executes the click; attributes are changed only
-- OUTSIDE combat lockdown, so a new focus cannot cause blocked actions.
local Items = {}
_G.ForeverQuestItems = Items

local button, icon, currentLink, latestQuest
local configured = false

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, state = pcall(InCombatLockdown)
    return ok and state == true
end

local function specialItem(quest)
    if not quest or not quest.questID or type(GetQuestLogSpecialItemInfo) ~= "function" then
        return nil
    end
    local logIndex = quest.logIndex
    if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, quest.questID)
        if ok and type(index) == "number" and index > 0 then
            logIndex = index
        end
    end
    if type(logIndex) ~= "number" or logIndex < 1 then return nil end
    local ok, link, texture, charges, showWhenComplete =
        pcall(GetQuestLogSpecialItemInfo, logIndex)
    if not ok or type(link) ~= "string" or link == "" then return nil end
    if quest.complete and not showWhenComplete then return nil end
    return link, texture, charges
end

function Items:Create(parent)
    if button then return button end
    if not parent or type(CreateFrame) ~= "function" then return nil end
    local ok, frame = pcall(CreateFrame, "Button", "ForeverQuestUseItemButton",
        parent, "SecureActionButtonTemplate")
    if not ok or not frame then return nil end
    button = frame
    frame:SetSize(23, 23)
    frame:SetPoint("LEFT", parent, "RIGHT", 5, 0)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("type", "item")
    icon=frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    local bg=frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",frame,"TOPLEFT",-1,1)
    bg:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",1,-1)
    bg:SetColorTexture(0.02,0.02,0.025,0.80)
    frame:SetScript("OnEnter",function(self)
        if GameTooltip and currentLink then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(currentLink)
            GameTooltip:AddLine("ForeverQuest: click to use the quest item",
                0.56,0.90,0.98)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave",function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:Hide()
    configured = true
    return frame
end

function Items:Update(quest)
    latestQuest=quest
    if not button or not configured then return end
    if inCombat() then
        -- Even Show/Hide is restricted on a protected secure action button.
        -- We will reconcile to the latest state after PLAYER_REGEN_ENABLED.
        return
    end
    local link, texture = specialItem(quest)
    if link then
        if currentLink ~= link then
            button:SetAttribute("type", "item")
            button:SetAttribute("item", link)
            currentLink = link
        end
        if icon and texture then icon:SetTexture(texture) end
        button:Show()
    else
        button:Hide()
        button:SetAttribute("item", nil)
        currentLink = nil
    end
end

function Items:Refresh()
    self:Update(latestQuest)
end

function Items:GetCurrentLink()
    return currentLink
end
