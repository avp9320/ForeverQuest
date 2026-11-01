local ADDON_NAME = ...

local CONFIG = {
    key = "quest",
    display = "ForeverQuest",
    events = {
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "QUEST_LOG_UPDATE",
        "PLAYER_LEVEL_UP",
    },
}

_G.ForeverDebugRegistry = _G.ForeverDebugRegistry or {
    modules = {},
    order = {},
    slashInstalled = false,
}
local Registry = _G.ForeverDebugRegistry

local function GetMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addon, field)
    end
end

local function IsLoaded(addon)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addon)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(addon)
    end
    return true
end

local module = Registry.modules[ADDON_NAME]
if not module then
    module = {}
    Registry.modules[ADDON_NAME] = module
    Registry.order[#Registry.order + 1] = ADDON_NAME
end

module.addon = ADDON_NAME
module.key = CONFIG.key
module.display = CONFIG.display
module.lastEvent = module.lastEvent or "DEBUG_LOADED"
module.lastAt = module.lastAt or ((GetTime and GetTime()) or 0)
module.registeredEvents = 0
module.failedEvents = {}

local function SetEventDetail(event, ...)
    if event == "PLAYER_LEVEL_UP" then
        module.lastDetail = "level " .. tostring(select(1, ...))
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        module.lastDetail = "slot " .. tostring(select(1, ...))
    elseif event == "PLAYER_ENTERING_WORLD" then
        module.lastDetail = "entered world"
    elseif event == "QUEST_LOG_UPDATE" then
        module.lastDetail = "quest log changed"
    elseif event == "BAG_UPDATE_DELAYED" then
        module.lastDetail = "bags changed"
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        module.lastDetail = "zone changed"
    elseif event == "PLAYER_REGEN_DISABLED" then
        module.lastDetail = "combat started"
    elseif event == "PLAYER_REGEN_ENABLED" then
        module.lastDetail = "combat ended"
    elseif event == "PLAYER_TALENT_UPDATE" then
        module.lastDetail = "talents changed"
    else
        module.lastDetail = nil
    end
end

local eventFrame = CreateFrame("Frame")
for i = 1, #CONFIG.events do
    local eventName = CONFIG.events[i]
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
    if ok then
        module.registeredEvents = module.registeredEvents + 1
    else
        module.failedEvents[#module.failedEvents + 1] = eventName
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    module.lastEvent = event
    module.lastAt = (GetTime and GetTime()) or 0
    SetEventDetail(event, ...)
end)

module.GetProbeText = function()
    local parts = {}
    do
        local ok, value = pcall(function() return C_QuestLog and (C_QuestLog.GetNumQuestLogEntries or C_QuestLog.GetInfo) end)
        parts[#parts + 1] = "QuestLog:" .. ((ok and value) and "OK" or "MISS")
    end
    do
        local ok, value = pcall(function() return C_Map and C_Map.GetBestMapForUnit end)
        parts[#parts + 1] = "Map:" .. ((ok and value) and "OK" or "MISS")
    end
    do
        local ok, value = pcall(function() return C_SuperTrack ~= nil or SetSuperTrackedQuestID ~= nil end)
        parts[#parts + 1] = "SuperTrack:" .. ((ok and value) and "OK" or "MISS")
    end
    if #module.failedEvents > 0 then
        parts[#parts + 1] = "events:" .. tostring(module.registeredEvents) .. "/" .. tostring(#CONFIG.events)
    end
    return table.concat(parts, " | ")
end

module.GetStateText = function()
    local ok, text = pcall(function()
        local count = "?"
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            local ok2, value = pcall(C_QuestLog.GetNumQuestLogEntries)
            if ok2 then count = tostring(value) end
        elseif GetNumQuestLogEntries then
            local ok2, value = pcall(GetNumQuestLogEntries)
            if ok2 then count = tostring(value) end
        end
        return "questEntries=" .. count
    end)
    if ok and text then
        return tostring(text)
    end
    return "state unavailable"
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SecondsSince(when)
    local now = (GetTime and GetTime()) or 0
    local delta = math.max(0, now - (tonumber(when) or now))
    if delta < 10 then
        return string.format("%.1fs", delta)
    end
    return tostring(math.floor(delta + 0.5)) .. "s"
end

local function MatchesFilter(entry, filter)
    if filter == "" or filter == "all" then
        return true
    end
    local needle = string.lower(filter)
    return string.find(string.lower(entry.key or ""), needle, 1, true)
        or string.find(string.lower(entry.addon or ""), needle, 1, true)
        or string.find(string.lower(entry.display or ""), needle, 1, true)
end

Registry.Print = Registry.Print or function(message)
    local filter = string.lower(Trim(message))
    if filter == "help" then
        print("|cffd9b93eForever Debug|r: /foreverdebug [all|dps|dungeon|loot|quest|talent|upgrade]")
        return
    end

    local version, build, interface = "?", "?", "?"
    if GetBuildInfo then
        local ok, v, b, _, i = pcall(GetBuildInfo)
        if ok then
            version, build, interface = tostring(v or "?"), tostring(b or "?"), tostring(i or "?")
        end
    end

    local count = 0
    for i = 1, #Registry.order do
        local entry = Registry.modules[Registry.order[i]]
        if entry and MatchesFilter(entry, filter) then
            count = count + 1
        end
    end

    print(string.format(
        "|cffd9b93eForever Debug|r client=%s build=%s interface=%s project=%s modules=%d",
        version,
        build,
        interface,
        tostring(WOW_PROJECT_ID or "?"),
        count
    ))

    local printed = 0
    for i = 1, #Registry.order do
        local entry = Registry.modules[Registry.order[i]]
        if entry and MatchesFilter(entry, filter) then
            printed = printed + 1
            local addonVersion = GetMetadata(entry.addon, "Version") or "?"
            local loaded = IsLoaded(entry.addon) and "loaded" or "NOT loaded"
            local eventText = tostring(entry.lastEvent or "none") .. " " .. SecondsSince(entry.lastAt) .. " ago"
            if entry.lastDetail then
                eventText = eventText .. " (" .. tostring(entry.lastDetail) .. ")"
            end
            print(string.format("|cff66ccff%s|r v%s %s | last=%s", entry.display, addonVersion, loaded, eventText))
            if entry.GetProbeText then
                print("  API: " .. entry.GetProbeText())
            end
            if entry.GetStateText then
                print("  State: " .. entry.GetStateText())
            end
        end
    end

    if printed == 0 then
        print("No Forever addon matched '" .. tostring(filter) .. "'. Try /foreverdebug help")
    end
end

if not Registry.slashInstalled then
    Registry.slashInstalled = true
    SLASH_FOREVERDEBUG1 = "/foreverdebug"
    SlashCmdList = SlashCmdList or {}
    SlashCmdList.FOREVERDEBUG = function(message)
        Registry.Print(message)
    end
end
