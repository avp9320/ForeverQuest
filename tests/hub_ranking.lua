-- Standalone Lua 5.1 regression: nearby productive hubs should outrank
-- slightly closer isolated starters, but not distant quest hubs.
_G.ForeverQuestCatalog = {
    AreaToMap = {[14]=1411},
    Quest = {
        GetAllIds = function() return {101,102,103,104} end,
        Get = function(id,field)
            local records = {
                [101]={name="Isolated",questLevel=10,startedBy={{201}}},
                [102]={name="Hub A",questLevel=10,startedBy={{202}}},
                [103]={name="Hub B",questLevel=10,startedBy={{203}}},
                [104]={name="Far away",questLevel=10,startedBy={{204}}},
            }
            return records[id] and records[id][field]
        end,
    },
    Npc = {
        Get = function(id,field)
            if field == "friendlyToFaction" then return "H" end
            if field ~= "spawns" then return nil end
            local positions = {
                [201]={40.4,50},[202]={41.4,50},
                [203]={41.6,50},[204]={90,90},
            }
            return {[14]={positions[id]}}
        end,
    },
}
C_Map = {GetPlayerMapPosition=function()
    return {GetXY=function() return .40,.50 end}
end}
C_Timer = {After=function(_,callback) callback() end}
UnitFactionGroup=function() return "Horde" end
UnitRace=function() return "Orc","Orc",2 end
UnitClass=function() return "Warrior","WARRIOR",1 end
C_QuestLog = {IsQuestFlaggedCompleted=function() return false end}
dofile("QuestPlanner.lua")
local planner=_G.ForeverQuestPlanner
planner:Scan(1411,10,{})
local ranked=planner:GetNearby(1411,4)
assert(#ranked==4,"all eligible starters should be found")
assert(ranked[1].questID==102 or ranked[1].questID==103,
    "nearby two-quest hub should beat isolated starter")
assert(ranked[1].hubCount==2,"hub size should be exposed")
assert(ranked[4].questID==104,"distant hub must not jump ahead")
assert(ranked[1].distance>ranked[3].distance,
    "actual distance must be preserved, not replaced by ranking")
print("hub ranking regression passed")
