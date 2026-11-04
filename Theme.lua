-- ForeverQuest: subtle stock-tracker-inspired style, no oversized tooltip
-- border. The card follows a two-line layout built in Core.lua.
local function ApplyForeverQuestTheme()
    local frame = _G.ForeverQuestFocusFrame
    if not frame then return false end

    if frame.SetBackdropColor then
        frame:SetBackdropColor(0.025, 0.025, 0.03, 0.66)
    end
    if frame.objective then
        frame.objective:SetTextColor(0.90, 0.90, 0.90)
    end
    if frame.distance then
        frame.distance:SetTextColor(0.72, 0.72, 0.72)
    end
    if frame.arrow then
        frame.arrow:SetAlpha(0.90)
    end

    frame.ForeverStockTheme = true
    return true
end

ApplyForeverQuestTheme()

local themeEvents = CreateFrame("Frame")
themeEvents:RegisterEvent("PLAYER_LOGIN")
themeEvents:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ApplyForeverQuestTheme)
    else
        ApplyForeverQuestTheme()
    end
end)
