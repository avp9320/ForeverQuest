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

local a={mapID=1411,x=.5,y=.4}
local b={mapID=1411,x=.55,y=.45}
eq(nav:Mark(a,false),"marked","AUTO sets pin when map free")
eq(marks,1,"one pin creation")
eq(nav:Mark(a,false),"marked","same pin stays in place")
eq(marks,1,"no repeated map writes")
eq(nav:Mark(b,false),"marked","owned pin follows new objective")
eq(marks,2,"new destination changes owned pin")
current={uiMapID=1411,position={x=.9,y=.8}} -- user's own map pin
eq(nav:Mark(a,false),"manual-pin","user pin is protected")
eq(marks,2,"user pin not overwritten")
eq(nav:Mark(a,true),"marked","explicit Shift-click can replace pin")
eq(marks,3,"explicit map write")
nav:ClearOwnPin()
eq(clears,1,"only own map pin cleared")
eq(current,nil,"own map pin removed")

-- If the client lacks the query API, automatic pinning is disabled; the
-- compass still works and explicit Shift-click is available.
C_Map.GetUserWaypoint=nil
eq(nav:Mark(a,false),"unsupported","safe fallback on missing map-query API")
eq(marks,3,"never overwrite unknown existing pin")
eq(nav:Mark(a,true),"marked","manual action works without query API")
eq(marks,4,"explicit mark accepted")
C_Map.GetMapWorldSize=nil
assert(guidance(.6,.4).label:find("NE",1,true),"compass works without yard API")
InCombatLockdown=function() return true end
eq(nav:Mark(b,true),"unavailable","no map waypoint writes in combat")
print("ForeverQuest human-readable navigation and waypoint protection tests passed")
