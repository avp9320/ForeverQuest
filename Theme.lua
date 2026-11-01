-- ForeverQuest visual theme
-- The quest focus card should read like a compact Blizzard tracker element, not a custom overlay.

local function ApplyForeverQuestTheme()
    local frame = _G.ForeverQuestFocusFrame
    if not frame then return false end

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
        frame:SetBackdropBorderColor(0.62, 0.52, 0.28, 0.92)
    end

    if frame.mode then
        frame.mode:SetTextColor(0.82, 0.72, 0.42)
    end

    if frame.objective then
        frame.objective:SetTextColor(0.90, 0.90, 0.90)
    end

    if frame.distance then
        frame.distance:SetTextColor(0.72, 0.72, 0.72)
    end

    if frame.arrow then
        frame.arrow:SetAlpha(0.92)
    end

    frame.ForeverStockTheme = true
    return true
end

ApplyForeverQuestTheme()

local themeEvents = CreateFrame("Frame")
themeEvents:RegisterEvent("PLAYER_LOGIN")
themeEvents:SetScript("OnEvent", function()
    -- Core applies its lock state during PLAYER_LOGIN; theme immediately after so
    -- the normal locked card returns to the stock Blizzard treatment.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ApplyForeverQuestTheme)
    else
        ApplyForeverQuestTheme()
    end
end)
