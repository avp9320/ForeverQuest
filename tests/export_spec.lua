-- Standalone /fqexport data smoke test (Lua 5.1).
local messages = {}
local observer
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent(event) self.event = event end
    function frame:SetScript(name, fn) self[name] = fn end
    observer = frame
    return frame
end
SlashCmdList = {}
UnitGUID = function() return "Player-test-export" end
UnitName = function() return "GumbusJr" end
UnitRace = function() return "Orc" end
UnitClass = function() return "Warrior" end
UnitLevel = function() return 7 end
UnitXP = function() return 1991 end
UnitXPMax = function() return 4500 end
GetRealmName = function() return "Forever" end
GetMoney = function() return 206 end
GetZoneText = function() return "Durotar" end
GetSubZoneText = function() return "Razor Hill" end
GetInventoryItemLink = function(_, slot)
    if slot == 16 then return "|cff1eff00|Hitem:123:0|h[Large Axe]|h|r" end
end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Mining", nil, 20, 75 end
C_Map = {
    GetBestMapForUnit = function() return 1411 end,
    GetPlayerMapPosition = function()
        return {GetXY=function() return 0.522, 0.431 end}
    end,
}
C_QuestLog = {
    GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(index)
        if index == 1 then return {isHeader=true, title="Durotar"} end
        return {questID=1234, title="Testing Export", level=8}
    end,
    GetQuestObjectives = function()
        return {
            {text="2/4 Enemies slain", finished=false},
            {text="1/1 Item collected", finished=true},
        }
    end,
    IsComplete = function() return false end,
    GetTitleForQuestID = function(id) return "Turned In " .. id end,
}
C_Container = {
    GetContainerNumSlots = function(bag)
        if bag == 0 then return 1 end
        return 0
    end,
    GetContainerItemLink = function()
        return "|cff1eff00|Hitem:88:0|h[Mining Pick]|h|r"
    end,
    GetContainerItemInfo = function() return {stackCount=1} end,
}
ForeverQuestDB = {}
dofile("Export.lua")
local exp = _G.ForeverQuestExport
assert(type(SlashCmdList.FOREVERQUESTEXPORT) == "function", "export slash command")
local report = exp.BuildReport()
assert(report:find("GumbusJr - Orc Warrior (level 7)",1,true), "identity")
assert(report:find("1991 / 4500",1,true), "xp")
assert(report:find("Razor Hill",1,true), "zone")
assert(report:find("52.2, 43.1",1,true), "position")
assert(report:find("Large Axe",1,true), "equipped weapon")
assert(report:find("Mining 20/75",1,true), "profession skill")
assert(report:find("[1234] L8 Testing Export",1,true), "quest ID and title")
assert(report:find("[ ] 2/4 Enemies slain",1,true), "unfinished objective")
assert(report:find("[done] 1/1 Item collected",1,true), "finished objective")
assert(report:find("Mining Pick x1",1,true), "bag inventory")
assert(observer.event == "QUEST_TURNED_IN", "turnin observer")
observer.OnEvent(observer, "QUEST_TURNED_IN", 9876)
report = exp.BuildReport()
assert(report:find("[9876] Turned In 9876",1,true), "recent completed quest")
print("ForeverQuest export smoke test passed")
