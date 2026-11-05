-- ForeverQuest route/data contract tests (run with lua5.1).
-- Mock API values match QuestieDB's public field schema; no WoW client needed.
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected "
        .. tostring(expected) .. ", received " .. tostring(actual))
end

dofile("Route.lua")
local route = _G.ForeverQuestRoute

local active = {
    {questID=1, title="Far objective", complete=false, waypointMap=1411,
        waypointX=.76, waypointY=.78, waypointSource="client"},
}
local nearby = {
    {questID=2, name="Nearby pickup", mapID=1411, x=.405, y=.602,
        confidence="provisional"},
}
local path = route:Build(active, nearby, 1411, .4, .6)
equal(#path.stops, 2, "two stops")
equal(path.stops[1].kind, "pickup", "opportunistic pickup")
equal(path.stops[1].questID, 2, "pickup quest")
assert(string.find(route:Describe(path.stops[1]), "PICK UP", 1, true))

local turnin = {
    {questID=3, title="Ready", complete=true, waypointMap=1411,
        waypointX=.402, waypointY=.602},
}
path = route:Build({turnin[1], active[1]}, {}, 1411, .4, .6)
equal(path.stops[1].kind, "turnin", "nearby turn-in")
path = route:Build({active[1]}, {{questID=1,name="Duplicate",mapID=1411,x=.42,y=.61}},1411,.4,.6)
equal(#path.stops,2,"distinct kinds remain distinct")
path = route:Build(active, nearby, 1412, .4, .6)
equal(#path.stops,0,"other-zone coordinates excluded")
path = route:Build({}, {}, 1411, .4, .6)
equal(#path.stops,0,"empty planning")

-- A remote, speculative pickup must not derail a nearby active objective.
local localWork={{questID=301,title="Local work",complete=false,
    waypointMap=1411,waypointX=.420,waypointY=.615}}
local farPickup={{questID=302,name="Remote guess",mapID=1411,x=.87,y=.85}}
local guarded=route:Build(localWork,farPickup,1411,.4,.6)
equal(#guarded.stops,1,"remote speculative pickup excluded while busy")
equal(guarded.stops[1].questID,301,"keep nearby accepted objective")
local noActive=route:Build({},farPickup,1411,.4,.6)
equal(#noActive.stops,1,"future pickup still works with empty quest log")

-- A distant pickup really ON the way to an accepted objective remains
-- worthwhile, even though the quest giver isn't next to the character.
local onWay={{questID=303,title="Far accepted objective",complete=false,
    waypointMap=1411,waypointX=.65,waypointY=.65}}
local passerby={{questID=304,name="Passing quest giver",mapID=1411,x=.645,y=.648}}
local along=route:Build(onWay,passerby,1411,.4,.6)
equal(#along.stops,2,"pickups near active objective remain in route")

-- Clustering should decrease as tasks are visited in the route, not
-- keep pulling the player back toward already planned/visited stops.
local sameArea = {
    {questID=401,name="Gather A",mapID=1411,x=.400,y=.400},
    {questID=402,name="Gather B",mapID=1411,x=.403,y=.400},
    {questID=403,name="Gather C",mapID=1411,x=.406,y=.400},
}
local clustered = route:Build({},sameArea,1411,.4,.4)
equal(#clustered.stops,3,"three nearby pickup stops")
equal(clustered.stops[1].overlapping,2,"first stop has two pending nearby goals")
equal(clustered.stops[2].overlapping,1,"second stop has one pending nearby goal")
equal(clustered.stops[3].overlapping,0,"last stop does not count visited goals")

-- Small native vs provisional distance difference: trust the client.
local trusted = route:Build({
    {questID=411,title="Client target",complete=false,
        waypointMap=1411,waypointX=.450,waypointY=.450,
        waypointSource="client"},
    {questID=412,title="Approximate target",complete=false,
        waypointMap=1411,waypointX=.446,waypointY=.450,
        waypointSource="database"},
}, {},1411,.4,.45)
equal(trusted.stops[1].questID,411,"prefer nearby confirmed client position")

local playerLevel = 8
local finished = {[105]=true}
UnitRace = function() return "Orc","Orc",2 end
UnitClass = function() return "Warrior","WARRIOR",1 end
UnitLevel = function() return playerLevel end
C_Map = {
    GetPlayerMapPosition = function()
        return {GetXY=function() return .4, .6 end}
    end,
}
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return finished[id] or false end,
}
C_Timer = { After=function(_,fn) fn() end }

local questRows = {
    [101] = {name="Nearby quest",requiredLevel=1,questLevel=8,
        startedBy={{11}},finishedBy={{12}},
        objectives={{{21,3}}},childQuests={107},requiredRaces=2,requiredClasses=1},
    [102] = {name="Locked chain",requiredLevel=1,
        startedBy={{11}},preQuestGroup={99}},
    [103] = {name="Wrong race",requiredLevel=1,
        startedBy={{11}},requiredRaces=1},
    [104] = {name="Another zone",requiredLevel=1,startedBy={{14}}},
    [105] = {name="Already finished",requiredLevel=1,startedBy={{11}}},
    [106] = {name="Item drop",requiredLevel=2,
        startedBy={{11}},objectives={{},{},{{801,3}}}},
    [107] = {name="Next chapter",requiredLevel=15,startedBy={{11}}},
    -- Active-only fixture: several different goals for the SAME quest.
    [108] = {name="Mixed objective",finishedBy={{12}},
        objectives={{{21,2},{22,4}},{{81,1}},{{801,3}}}},
    [109] = {name="Explore the cave",
        triggerPoints={[14]={{52.5,73.5}}}},
}
local npcRows = {
    [11] = {name="Starter",spawns={[14]={{40.5,60.3}}}},
    [12] = {name="Turn-in",spawns={[14]={{41,62}}}},
    [14] = {name="Other zone",spawns={[17]={{40,60}}}},
    [21] = {name="Scorpid",spawns={[14]={{45,65}}}},
    [22] = {name="Familiar",spawns={[14]={{51,73}}}},
    [31] = {name="Item source",spawns={[14]={{44.5,64.5}}}},
}
local itemRows = {[801] = {name="Supply Token",npcDrops={31}}}
local objectRows = {[81] = {name="Supply Chest",spawns={[14]={{53,70}}}}}
local function entity(rows)
    return {
        Get = function(id,key) return rows[id] and rows[id][key] end,
    }
end
ForeverQuestCatalog = {
    flavor = {expansion="Forever"},
    Quest=entity(questRows),
    Npc=entity(npcRows),
    Object=entity(objectRows),
    Item=entity(itemRows),
    Enum={raceMaskById={[2]=2}},
}
ForeverQuestCatalog.Quest.GetAllIds = function() return {101,102,103,104,105,106,107} end

dofile("QuestPlanner.lua")
local planner=_G.ForeverQuestPlanner
assert(planner:Available(), "bundled quest catalog provider")
planner:Scan(1411, playerLevel, {})
local candidates=planner:GetNearby(1411,10)
equal(#candidates,2,"eligible new quests")
equal(candidates[1].questID,101,"nearest eligible pickup")
assert(string.find(planner:Status(),"2 possible",1,true))
local objective=planner:GetActivePosition(101,false,1411)
equal(objective.entityID,21,"active NPC objective")
local finishedOnly=planner:GetActivePosition(101,false,1411,
    {{text="3/3 Scorpid slain", finished=true}})
equal(finishedOnly,nil,"avoid finished NPC target")
local unfinishedObjective=planner:GetActivePosition(101,false,1411,
    {{text="0/3 Scorpid slain", finished=false}})
equal(unfinishedObjective.entityID,21,"retain unfinished NPC target")
local turn=planner:GetActivePosition(101,true,1411)
equal(turn.entityID,12,"turn-in NPC")
local drop=planner:GetActivePosition(106,false,1411)
equal(drop.entityID,31,"item drop source")
local chain=planner:GetChainPreview(101)
equal(chain[1].name,"Next chapter","future chain preview")

local goals=planner:GetActivePositions(108,false,1411,nil,6)
equal(#goals,4,"distinct unfinished goals in one quest")
local unique={}
for _,goal in ipairs(goals) do
    assert(not unique[goal.goalKey],"duplicate quest goal")
    unique[goal.goalKey]=true
end
assert(unique["enemy:21"] and unique["enemy:22"] and unique["object:81"]
    and unique["item:801"],"mixed objective types")
local remaining=planner:GetActivePositions(108,false,1411,
    {{text="2/2 Scorpid slain",finished=true},
     {text="4/4 Familiar slain",finished=true}},6)
equal(#remaining,2,"completed kill goals are excluded")
local doneItem=planner:GetActivePositions(108,false,1411,
    {{text="1/1 Supply Token",finished=true}},6)
equal(#doneItem,3,"completed item goal is excluded")
local turnTargets=planner:GetActivePositions(108,true,1411,nil,6)
equal(#turnTargets,1,"one alternative turn-in stop")

local exploration=planner:GetActivePositions(109,false,1411,nil,6)
equal(#exploration,1,"exploration-only quest is locatable")
equal(exploration[1].goalKey,"trigger","spatial exploration goal")
equal(exploration[1].x,.525,"exploration map coordinate")
local premature=planner:GetActivePositions(109,false,1411,
    {{text="0/8 enemies slain",finished=false}},6)
equal(#premature,0,"do not send to exploration trigger before other objectives")
local readyTrigger=planner:GetActivePositions(109,false,1411,
    {{text="8/8 enemies slain",finished=true}},6)
equal(#readyTrigger,1,"visit completion trigger after other objectives")

local multi=route:Build({
    {questID=108,title="Mixed objective",complete=false,
        waypointMap=1411,waypointX=.45,waypointY=.65,
        goalPoints=goals}
}, {}, 1411,.4,.6)
equal(#multi.stops,4,"multi-objective route contains separate stops")
local keys={}
for _,stop in ipairs(multi.stops) do
    assert(not keys[stop.key], "duplicate stop identity")
    keys[stop.key]=true
    assert(stop.targetName and stop.goalKey,"stop has specific objective")
end

planner:Invalidate()
planner:Scan(1411,playerLevel,{[101]=true})
equal(#planner:GetNearby(1411,10),1,"accepted quest suppressed")
finished[106]=true
planner:Invalidate()
planner:Scan(1411,playerLevel,{})
equal(#planner:GetNearby(1411,10),1,"completed quest suppressed")

-- Adjacent-zone lookahead: available quests in Barrens are relevant to a
-- Durotar character, but not a promise that travel is immediately ideal.
UnitFactionGroup = function() return "Horde" end
local zones = planner:GetNextZones(1411, playerLevel, {}, 3)
equal(zones[1].mapID,1413,"Durotar -> Barrens lookahead")
assert(zones[1].possibleQuests >= 1,"Barrens quest candidate count")

-- Do not send Horde characters to explicitly Alliance-only NPCs.
npcRows[14].friendlyToFaction = "A"
planner:Invalidate()
zones = planner:GetNextZones(1411, playerLevel, {}, 3)
equal(#zones,0,"opposite-faction questgiver excluded")
print("ForeverQuest offline route + bundled catalog adapter tests passed")
