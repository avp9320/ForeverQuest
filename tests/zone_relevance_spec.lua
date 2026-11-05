-- Offline zone advisor regression: raw quest volume must not beat relevant levels.
_G.ForeverQuestTravel = {
    GetReachable=function()
        return {{mapID=1413,hops=1,via=1413},
                {mapID=1440,hops=1,via=1440}}
    end,
    DescribeHandoff=function() return "Neighboring zone" end,
}
UnitFactionGroup=function() return "Horde" end
UnitRace=function() return "Orc","Orc",2 end
UnitClass=function() return "Warrior","WARRIOR",1 end
local quests, ids = {}, {}
for i=1,12 do
    local id=1000+i
    ids[#ids+1]=id
    quests[id]={questLevel=5,requiredLevel=1,startedBy={{id}}}
end
for i=1,4 do
    local id=2000+i
    ids[#ids+1]=id
    quests[id]={questLevel=22,requiredLevel=18,startedBy={{id}}}
end
local npc={}
for i=1,12 do npc[1000+i]={spawns={[17]={{50,50}}}} end
for i=1,4 do npc[2000+i]={spawns={[331]={{50,50}}}} end
_G.ForeverQuestCatalog={
    Quest={
        GetAllIds=function() return ids end,
        Get=function(id,key) return quests[id] and quests[id][key] end,
    },
    Npc={Get=function(id,key) return npc[id] and npc[id][key] end},
    Object={Get=function() return nil end},
    AreaToMap={[17]=1413,[331]=1440},
}
dofile("QuestPlanner.lua")
local planner=_G.ForeverQuestPlanner
local zones=planner:GetNextZones(1411,22,{},3)
assert(#zones==2,"both zones have available quests")
assert(zones[1].mapID==1440,
    "four level-relevant quests must outrank twelve trivial quests")
assert(zones[1].relevantScore>zones[2].relevantScore,
    "relevance score reflects character level")
assert(zones[2].possibleQuests==12,
    "raw quest counts are retained for display")
print("ForeverQuest zone relevance tests passed")
