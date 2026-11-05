-- ForeverQuest local zone-transition advisor.
-- An intentionally conservative connectivity graph, NOT terrain pathfinding,
-- not a claim about roads, open gates, flight times, or safe travel.
-- IDs use the Vanilla world map set exposed by Forever's client.
local Travel = {}
_G.ForeverQuestTravel = Travel

-- Directed *potential* zone handoffs. We only include connected neighboring
-- areas. Cross-continent boats, zeppelins, hearths and unknown portals are
-- intentionally excluded; the client must never claim those are walkable.
local links = {
    [1411]={1413},                  -- Durotar -> Barrens
    [1412]={1413},                  -- Mulgore -> Barrens
    [1413]={1411,1412,1442,1440,1441,1445}, -- Barrens and Dustwallow
    [1420]={1421},                  -- Tirisfal -> Silverpine
    [1421]={1420,1424},             -- Silverpine -> Hillsbrad
    [1424]={1421,1417,1416},       -- Hillsbrad
    [1417]={1424,1437,1416},       -- Arathi
    [1416]={1424,1417},            -- Alterac
    [1422]={1423},                  -- Western Plaguelands
    [1423]={1422},                  -- Eastern Plaguelands
    [1429]={1436,1433},            -- Elwynn
    [1436]={1429,1431,1433},       -- Westfall
    [1433]={1429,1436,1431},       -- Redridge
    [1431]={1436,1433,1434,1430},  -- Duskwood
    [1434]={1431},                  -- Stranglethorn
    [1430]={1431},                  -- Deadwind Pass
    [1426]={1432},                  -- Dun Morogh -> Loch Modan
    [1432]={1426,1437,1418},       -- Loch Modan
    [1437]={1432,1417},            -- Wetlands
    [1418]={1432,1427},            -- Badlands
    [1427]={1418,1428},            -- Searing Gorge
    [1428]={1427},                  -- Burning Steppes
    [1438]={},                      -- Teldrassil needs boat/portal, not walkable
    [1439]={1440},                 -- Darkshore; Teldrassil is not walkable
    [1440]={1439,1413,1442,1448},  -- Ashenvale
    [1442]={1413,1440,1443},       -- Stonetalon
    [1443]={1442,1444},            -- Desolace
    [1444]={1443,1441,1446},       -- Feralas
    [1441]={1413,1444,1446},       -- Thousand Needles
    [1445]={1413},                  -- Dustwallow Marsh via Barrens
    [1446]={1444,1441,1449},       -- Tanaris
    [1449]={1446,1451},            -- Un'Goro
    [1451]={1449},                 -- Silithus
    [1448]={1440,1452},            -- Felwood
    [1452]={1448},                 -- Winterspring
}

function Travel:GetReachable(currentMap, maxHops)
    if type(currentMap) ~= "number" then return {} end
    maxHops = math.min(4, math.max(1, tonumber(maxHops) or 2))
    local found = {[currentMap]={hops=0, path={currentMap}}}
    local queue, front = {currentMap}, 1
    while front <= #queue do
        local from = queue[front]
        front = front + 1
        local old = found[from]
        if old.hops < maxHops then
            for _, dest in ipairs(links[from] or {}) do
                if not found[dest] then
                    local path = {}
                    for _, id in ipairs(old.path) do path[#path+1]=id end
                    path[#path+1]=dest
                    found[dest]={hops=old.hops+1,path=path,via=path[2]}
                    queue[#queue+1]=dest
                end
            end
        end
    end
    local candidates={}
    for id, info in pairs(found) do
        if id ~= currentMap then
            candidates[#candidates+1]={mapID=id,hops=info.hops,
                via=info.via,path=info.path,source="zone-connectivity-estimate"}
        end
    end
    table.sort(candidates,function(a,b)
        if a.hops == b.hops then return a.mapID < b.mapID end
        return a.hops < b.hops
    end)
    return candidates
end

function Travel:GetHandoff(fromMap, toMap)
    if fromMap == toMap then return nil end
    for _, stop in ipairs(self:GetReachable(fromMap, 4)) do
        if stop.mapID == toMap then return stop end
    end
end

function Travel:DescribeHandoff(path, names)
    if not path or type(path.path) ~= "table" or #path.path < 2 then
        return "Travel route not verified"
    end
    local getName = function(mapID)
        if names and names[mapID] then return names[mapID] end
        if C_Map and C_Map.GetMapInfo then
            local ok, info = pcall(C_Map.GetMapInfo, mapID)
            if ok and type(info)=="table" and info.name then
                return info.name
            end
        end
        return "map " .. tostring(mapID)
    end
    if #path.path == 2 then
        return "Neighboring zone: " .. getName(path.mapID)
    end
    return "Via " .. getName(path.path[2])
        .. " toward " .. getName(path.mapID)
        .. " (zone connections only)"
end

-- Client map layers (caves, interiors, different zones) are not the
-- same coordinate plane. A direct arrow to another map is misleading.
-- We never infer an exact entrance from an enemy spawn coordinate.
function Travel:GetLayerCaution(fromMap,toMap)
    if not fromMap or not toMap or fromMap==toMap then return nil end
    if C_Map and type(C_Map.GetMapInfo)=="function" then
        local okA,origin=pcall(C_Map.GetMapInfo,fromMap)
        local okB,target=pcall(C_Map.GetMapInfo,toMap)
        if okA and okB and type(origin)=="table"
            and type(target)=="table" then
            if origin.parentMapID==toMap or target.parentMapID==fromMap then
                return "Different interior/map layer; use an entrance or exit."
            end
        end
    end
    return "Destination is in another map area; direct arrow paused."
end

-- Known flight-path names are learned from taxi-map visits when available.
-- We never invent taxi coordinates or assume a given character can fly.
function Travel:LearnFlightPaths(account)
    if type(account)~="table" then return 0 end
    if type(NumTaxiNodes)~="function"
        or type(TaxiNodeName)~="function"
        or type(TaxiNodeGetType)~="function" then return 0 end
    local ok,n = pcall(NumTaxiNodes)
    if not ok or type(n)~="number" then return 0 end
    account.flightPaths = account.flightPaths or {}
    local count = 0
    for i=1,math.min(n,256) do
        local good,kind = pcall(TaxiNodeGetType,i)
        if good and (kind=="CURRENT" or kind=="REACHABLE") then
            local valid,name=pcall(TaxiNodeName,i)
            if valid and type(name)=="string" and name~="" then
                account.flightPaths[name]=true
                count=count+1
            end
        end
    end
    return count
end
