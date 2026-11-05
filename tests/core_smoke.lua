-- ForeverQuest Core smoke test under Lua 5.1 with minimal UI/game mocks.
-- Catches load/init, AUTO/MANUAL, empty quest log, and future-pickup card regressions.
local allFrames={}
local function makeUI(name)
    local t={scripts={},shown=true,text=""}
    setmetatable(t,{__index=function(_,key)
        return function() end
    end})
    function t:SetScript(event,fn) self.scripts[event]=fn end
    function t:GetScript(event) return self.scripts[event] end
    function t:CreateTexture() return makeUI() end
    function t:CreateFontString() return makeUI() end
    function t:SetText(v) self.text=v end
    function t:GetText() return self.text end
    function t:Hide() self.shown=false end
    function t:Show() self.shown=true end
    function t:IsShown() return self.shown end
    function t:SetShown(v) self.shown=v end
    function t:GetPoint() return "CENTER",nil,"CENTER",0,180 end
    if name then _G[name]=t end
    allFrames[#allFrames+1]=t
    return t
end
CreateFrame=function(_,name) return makeUI(name) end
UIParent=makeUI()
DEFAULT_CHAT_FRAME={AddMessage=function()end}
GameTooltip=makeUI()
SlashCmdList={}
wipe=function(t) for k in pairs(t) do t[k]=nil end end
GetTime=function() return 100 end
UnitLevel=function() return 5 end
UnitGUID=function() return "Player-test-1" end
UnitName=function() return "Test" end
GetRealmName=function() return "Realm" end
UnitAffectingCombat=function() return false end
C_Map={
    GetBestMapForUnit=function() return 1411 end,
    GetPlayerMapPosition=function() return {GetXY=function()return .40,.60 end} end,
}
local log={
    {questID=100,title="Sample quest",isHeader=false,isHidden=false},
}
C_QuestLog={
    GetNumQuestLogEntries=function() return #log end,
    GetInfo=function(i) return log[i] end,
    GetTitleForQuestID=function(id) return id==100 and "Sample quest" or "Other" end,
    GetQuestObjectives=function() return {{text="0/3 Sample enemies",finished=false}} end,
    IsComplete=function() return false end,
    GetDistanceSqToQuest=function() return 900,true end,
}
C_Timer={After=function(_,f) f() end}
dofile("QuestData.lua")
dofile("QuestPlanner.lua")
dofile("Route.lua")
dofile("Core.lua")
local core=allFrames[3] -- UIParent and GameTooltip were created before the addon.
assert(core.scripts.OnEvent,"core event listener")
core.scripts.OnEvent(core,"PLAYER_LOGIN")
local card=_G.ForeverQuestFocusFrame
assert(card.title:GetText()=="Sample quest","shows accepted quest")
assert(string.find(card.objective:GetText(),"Sample enemies",1,true),"objective text")
SlashCmdList.FOREVERQUEST("route")
card.scripts.OnClick(card,"LeftButton")
assert(ForeverQuestDB.mode=="MANUAL","manual quest cycle")
card.scripts.OnClick(card,"RightButton")
assert(ForeverQuestDB.mode=="AUTO","right-click AUTO")

-- The active log is now empty. An optional data-provider pickup must still
-- produce actionable guidance, and manual cycling must support it.
log={}
local p=_G.ForeverQuestPlanner
p.Available=function()return true end
p.Scan=function() end
p.GetNearby=function()
    return {{questID=201,mapID=1411,x=.405,y=.603,name="Next Adventure",
        confidence="provisional",kind="NPC",distance=.006}}
end
p.GetActivePosition=function()return nil end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(string.find(card.title:GetText(),"Pick up:",1,true),"future pickup shown")
card.scripts.OnClick(card,"LeftButton")
assert(ForeverQuestDB.mode=="MANUAL","manual cycle with empty quest log")
assert(string.find(card.title:GetText(),"Pick up:",1,true),"manual pickup retained")
card.scripts.OnClick(card,"RightButton")
assert(ForeverQuestDB.mode=="AUTO","restore automatic planning")
SlashCmdList.FOREVERQUEST("skip")
assert(ForeverQuestDB.ignoredByCharacter["Player-test-1"][201],
    "per-character skip saved")
SlashCmdList.FOREVERQUEST("unskip")
assert(not ForeverQuestDB.ignoredByCharacter["Player-test-1"][201],
    "skip can be restored")
-- No quest-log objectives or nearby starters: suggest a plausible
-- neighboring questing zone, without inventing a travel waypoint.
p.GetNearby = function() return {} end
p.GetNextZones = function()
    return {{mapID=1413,name="The Barrens",possibleQuests=5}}
end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(string.find(card.title:GetText(),"The Barrens",1,true),
    "neighboring-zone hint should replace an empty quest tracker")
SlashCmdList.FOREVERQUEST("zones")
print("ForeverQuest Core mock game/UI smoke test passed")
