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
-- Multi-goal quest: both the visible objective and navigation waypoint
-- must change when the player manually selects the second route stop.
log={{questID=100,title="Sample quest",isHeader=false,isHidden=false}}
local objectiveRows = {
    {text="0/3 First Target",finished=false},
    {text="0/4 Second Target",finished=false},
}
C_QuestLog.GetQuestObjectives=function() return objectiveRows end
p.GetActivePositions=function(_, questID, complete, mapID)
    local points = {}
    if not objectiveRows[1].finished then
        points[#points+1] = {
            mapID=1411,x=.405,y=.606,goalKey="enemy:55",
            targetName="First Target",stepLabel="Defeat First Target",
            kind="enemy",entityName="First Target",confidence="provisional",
        }
    end
    if not objectiveRows[2].finished then
        points[#points+1] = {
            mapID=1411,x=.435,y=.640,goalKey="enemy:56",
            targetName="Second Target",stepLabel="Defeat Second Target",
            kind="enemy",entityName="Second Target",confidence="provisional",
        }
    end
    return points
end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(card.title:GetText()=="Sample quest","multi-target quest visible")
assert(card.objective:GetText()=="0/3 First Target","closest objective in AUTO")
card.scripts.OnClick(card,"LeftButton")
assert(ForeverQuestDB.mode=="MANUAL","manual mode for second target")
assert(card.objective:GetText()=="0/4 Second Target",
    "manual cycle displays the selected second target")
assert(card.distance:GetText()=="~44,64","distance label matches selected target")
local waypoint
UiMapPoint={CreateFromCoordinates=function(map,x,y)
    return {mapID=map,x=x,y=y}
end}
C_Map.SetUserWaypoint=function(point) waypoint=point; return true end
C_Map.CanSetUserWaypointOnMap=function() return true end
SlashCmdList.FOREVERQUEST("navigate")
assert(waypoint and math.abs(waypoint.x-.435)<.001,
    "navigation uses chosen second target, not first objective")

-- A completed first target vanishes from suggested goals while the second
-- stays in the plan and remains correctly selected.
objectiveRows[1].text="3/3 First Target"
objectiveRows[1].finished=true
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(card.objective:GetText()=="0/4 Second Target",
    "manual route keeps unfinished target after another goal completes")
assert(card.distance:GetText()=="~44,64","waypoint does not regress on refresh")
card.scripts.OnClick(card,"RightButton")
assert(ForeverQuestDB.mode=="AUTO","automatic mode restored after multi-step test")
SlashCmdList.FOREVERQUEST("why") -- explain selected automatic objective safely

-- Client native waypoint should not hide the quest's other distinct
-- database goals. Nearby native coordinates are attached to the matching
-- goal; a very different native coordinate should be left authoritative
-- rather than guessed to refer to a Classic objective.
-- Advance beyond the anti-thrashing window. In normal gameplay a fully
-- completed goal does not spontaneously become unfinished again.
GetTime=function() return 125 end
objectiveRows[1]={text="0/3 First Target",finished=false}
objectiveRows[2]={text="0/4 Second Target",finished=false}
C_QuestLog.GetNextWaypointForMap=function(questID,mapID)
    if questID==100 then return .405,.605 end
end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(card.objective:GetText()=="0/3 First Target",
    "client waypoint and multiple goals coexist")
card.scripts.OnClick(card,"LeftButton")
assert(card.objective:GetText()=="0/4 Second Target",
    "second database goal remains selectable with native waypoint")
card.scripts.OnClick(card,"RightButton")
C_QuestLog.GetNextWaypointForMap=function(questID,mapID)
    if questID==100 then return .80,.80 end
end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(card.distance:GetText()=="30 yd",
    "far-away client waypoint is retained over unverified database points")
C_QuestLog.GetNextWaypointForMap=nil

-- A cluster of quest starters should take one card/route stop, not fill all
-- five slots with repeated coordinates. Skipping the leading false-positive
-- should still reveal the other quest at that hub.
log={}
p.GetNearby=function()
    local ignored=ForeverQuestDB.ignoredByCharacter
        and ForeverQuestDB.ignoredByCharacter["Player-test-1"] or {}
    local all={}
    if not ignored[601] then
        all[#all+1]={questID=601,mapID=1411,x=.401,y=.401,
            name="First Hub Quest",giverID=900,kind="NPC",
            confidence="provisional"}
    end
    all[#all+1]={questID=602,mapID=1411,x=.402,y=.401,
        name="Second Hub Quest",giverID=900,kind="NPC",
        confidence="provisional"}
    return all
end
core.scripts.OnEvent(core,"QUEST_LOG_UPDATE")
assert(card.objective:GetText()=="2 possible quests at this stop",
    "quest giver hub shows combined pickup count")
SlashCmdList.FOREVERQUEST("skip")
assert(card.title:GetText()=="Pick up: Second Hub Quest",
    "skip first quest reveals other pickup without leaving hub")

print("ForeverQuest Core mock game/UI smoke test passed")
