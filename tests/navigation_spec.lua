-- Offline tests for readable, non-intrusive ForeverQuest navigation.
dofile("QuestData.lua")
dofile("Navigation.lua")
local nav = assert(_G.ForeverQuestNavigation)
local function eq(a,b,why)
    assert(a==b,(why or "value")..": expected "..tostring(b)
        ..", got "..tostring(a))
end
local px,py=.5,.5
local current, marks, clears=nil,0,0
C_Map={
    GetPlayerMapPosition=function(id,unit)
        return {GetXY=function()return px,py end}
    end,
    GetMapWorldSize=function() return 1000,1000 end,
    CanSetUserWaypointOnMap=function()return true end,
    GetUserWaypoint=function()return current end,
    SetUserWaypoint=function(point)
        marks=marks+1
        current=point
        return true
    end,
    ClearUserWaypoint=function() clears=clears+1;current=nil end,
}
UiMapPoint={
    CreateFromCoordinates=function(mapID,x,y)
        return {uiMapID=mapID,position={x=x,y=y}}
    end
}
InCombatLockdown=function()return false end
local function guidance(x,y)
    return assert(nav:Guidance({mapID=1411,x=x,y=y}))
end
eq(guidance(.5,.4).direction,"N","north")
eq(guidance(.6,.4).direction,"NE","northeast")
eq(guidance(.6,.5).direction,"E","east")
eq(guidance(.6,.6).direction,"SE","southeast")
eq(guidance(.5,.6).direction,"S","south")
eq(guidance(.4,.6).direction,"SW","southwest")
eq(guidance(.4,.5).direction,"W","west")
eq(guidance(.4,.4).direction,"NW","northwest")
eq(guidance(.5,.4).label,"N ~100 yd","real straight-line yardage")
eq(guidance(.502,.5).label,"Nearby","small distance")
assert(nav:Destination(791,"pickup","Someone"):find("Razor Hill watchtower",1,true),
    "specific named guide destination")
eq(nav:Destination(123456,"pickup","Known NPC"),"Known NPC",
    "generic names are not invented")

-- Official Blizzard quest tracking is the only navigation write.
-- Map user pins must be left untouched, including a pre-existing personal pin.
local tracked, calls = nil, 0
C_SuperTrack = {
    GetSuperTrackedQuestID=function() return tracked end,
    SetSuperTrackedQuestID=function(id)
        tracked=id
        calls=calls+1
        return true
    end,
}
eq(nav:TrackQuest(791),true,"track accepted quest")
eq(tracked,791,"selected quest is supertracked")
eq(nav:TrackQuest(791),true,"same quest is already tracked")
eq(calls,1,"avoid redundant tracking calls")
eq(nav:TrackQuest(792),true,"switch official quest objective")
eq(tracked,792,"new quest is supertracked")
eq(marks,0,"no map pins created")
eq(clears,0,"no personal pins removed")
C_SuperTrack=nil
eq(nav:TrackQuest(791),false,"graceful fallback when supertrack unavailable")
C_Map.GetMapWorldSize=nil
assert(guidance(.6,.4).label:find("NE",1,true),"compass works without yard API")
print("ForeverQuest official quest tracking navigation tests passed")
