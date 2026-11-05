-- Offline tests for ForeverQuest route strategy, zone transitions,
-- account-observed quest locations and secure quest item handling.
-- No live client or extra addon required.
local function eq(actual,want,label)
    assert(actual==want,(label or "value")..": expected "..tostring(want)
        ..", received "..tostring(actual))
end
dofile("Travel.lua")
local travel=_G.ForeverQuestTravel
local nearby=travel:GetReachable(1411,2)
local barrens,ashenvale
for _,value in ipairs(nearby) do
    if value.mapID==1413 then barrens=value end
    if value.mapID==1440 then ashenvale=value end
end
assert(barrens,"Durotar must reach Barrens")
eq(barrens.hops,1,"direct neighbor")
assert(ashenvale,"Ashenvale reached via Barrens")
eq(ashenvale.hops,2,"two-hop route")
eq(ashenvale.path[2],1413,"handoff via Barrens")
assert(not travel:GetHandoff(1411,1429),"cannot walk between continents")
assert(travel:DescribeHandoff(ashenvale,{[1413]="Barrens",[1440]="Ashenvale"})
    :find("Via Barrens",1,true),"honest zone-transition hint")

local db={Quest={
    Get=function(id,key)
        local t={
            [500]={questLevel=10,childQuests={501,502}},
            [501]={requiredLevel=10,questLevel=11},
            [502]={requiredLevel=21,questLevel=22},
            [503]={questLevel=20},
            [504]={questLevel=9},
        }
        return t[id] and t[id][key]
    end,
}}
_G.ForeverQuestCatalog=db
dofile("Strategy.lua")
local strategy=_G.ForeverQuestStrategy
local early,later=strategy:ChainValue(500,10)
eq(early,1,"one relevant immediate follow-up")
eq(later,0,"distant chain not overvalued")
local chainBonus=strategy:Assess({questID=500,kind="turnin"},
    {level=10,mode="balanced"})
assert(chainBonus>0,"chain-unlocking turn-in prioritized")
local risky=strategy:Assess({questID=503,kind="objective",suggestedGroup=3},
    {level=10,mode="balanced"})
assert(risky<-.25,"risky elite quest should be penalized")
local pickup={questID=504,kind="pickup"}
local fast=strategy:Assess(pickup,{level=10,mode="fast"})
local complete=strategy:Assess(pickup,{level=10,mode="complete"})
assert(complete>fast,"completion preference values pickups more")
local avoided=strategy:Assess(pickup,{avoided={[504]=true},level=10})
eq(avoided,-1000,"avoided stop excluded from auto")

dofile("Knowledge.lua")
local knowledge=_G.ForeverQuestKnowledge
local account={}
assert(knowledge:Observe(account,"pickup",42,1411,.431,.68))
assert(knowledge:Observe(account,"turnin",42,1411,.405,.66))
local learned=knowledge:Get(account,"pickup",42)
eq(learned.confidence,"account-observed","learned source")
eq(learned.x,.431,"remembered coordinates")
local counts=knowledge:Counts(account)
eq(counts.pickup,1,"pickup count")
eq(counts.turnin,1,"turn-in count")
assert(not knowledge:Observe(account,"pickup",1,1411,1.5,.6),
    "reject invalid map positions")
knowledge:Clear(account)
eq(knowledge:Counts(account).pickup,0,"clear account learning")

local comb=false
local lastButton
local function widget()
    local f={attributes={},shown=true,scripts={}}
    function f:SetAttribute(key,value) self.attributes[key]=value end
    function f:SetSize() end
    function f:SetPoint() end
    function f:RegisterForClicks() end
    function f:CreateTexture()
        return {SetAllPoints=function()end,SetTexture=function()end,
            SetPoint=function()end,SetColorTexture=function()end}
    end
    function f:SetScript(event,fn) self.scripts[event]=fn end
    function f:Hide() self.shown=false end
    function f:Show() self.shown=true end
    return f
end
CreateFrame=function(_,name,parent,template)
    eq(template,"SecureActionButtonTemplate","secure quest item template")
    lastButton=widget()
    return lastButton
end
InCombatLockdown=function() return comb end
GetQuestLogSpecialItemInfo=function(logIndex)
    if logIndex==3 then return "|cff00ff00|Hitem:1234|h[Tool]|h|r",1351,1,false end
    if logIndex==4 then return "|cff00ff00|Hitem:5678|h[New Tool]|h|r",1352,1,false end
end
dofile("QuestItems.lua")
local items=_G.ForeverQuestItems
items:Create(widget())
local a={questID=99,logIndex=3,complete=false}
local b={questID=100,logIndex=4,complete=false}
items:Update(a)
assert(lastButton.shown,"relevant quest item shown")
eq(lastButton.attributes.type,"item","secure item action type")
assert(lastButton.attributes.item:find("item:1234",1,true))
comb=true
items:Update(b)
assert(lastButton.attributes.item:find("item:1234",1,true),
    "secure item attributes do not change during combat")
comb=false
items:Refresh()
assert(lastButton.attributes.item:find("item:5678",1,true),
    "pending item applied once combat ends")
b.complete=true
items:Update(b)
assert(not lastButton.shown,"item hidden on complete quest")
print("ForeverQuest roadmap tests passed")
