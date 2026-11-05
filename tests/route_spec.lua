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
}
local npcRows = {
    [11] = {name="Starter",spawns={[14]={{40.5,60.3}}}},
    [12] = {name="Turn-in",spawns={[14]={{41,62}}}},
    [14] = {name="Other zone",spawns={[17]={{40,60}}}},
    [21] = {name="Scorpid",spawns={[14]={{45,65}}}},
    [31] = {name="Item source",spawns={[14]={{44.5,64.5}}}},
}
local itemRows = {[801] = {npcDrops={31}}}
local function entity(rows)
    return {
        Get = function(id,key) return rows[id] and rows[id][key] end,
    }
end
LibQuestieDB = {
    flavor = {expansion="Forever"},
    Quest=entity(questRows),
    Npc=entity(npcRows),
    Object=entity({}),
    Item=entity(itemRows),
    Enum={raceMaskById={[2]=2}},
}
LibQuestieDB.Quest.GetAllIds = function() return {101,102,103,104,105,106,107} end

dofile("QuestPlanner.lua")
local planner=_G.ForeverQuestPlanner
assert(planner:Available(), "QuestieDB provider")
planner:Scan(1411, playerLevel, {})
local candidates=planner:GetNearby(1411,10)
equal(#candidates,2,"eligible new quests")
equal(candidates[1].questID,101,"nearest eligible pickup")
assert(string.find(planner:Status(),"2 possible",1,true))
local objective=planner:GetActivePosition(101,false,1411)
equal(objective.entityID,21,"active NPC objective")
local turn=planner:GetActivePosition(101,true,1411)
equal(turn.entityID,12,"turn-in NPC")
local drop=planner:GetActivePosition(106,false,1411)
equal(drop.entityID,31,"item drop source")
local chain=planner:GetChainPreview(101)
equal(chain[1].name,"Next chapter","future chain preview")

planner:Invalidate()
planner:Scan(1411,playerLevel,{[101]=true})
equal(#planner:GetNearby(1411,10),1,"accepted quest suppressed")
finished[106]=true
planner:Invalidate()
planner:Scan(1411,playerLevel,{})
equal(#planner:GetNearby(1411,10),1,"completed quest suppressed")
print("ForeverQuest offline route + QuestieDB adapter tests passed")
