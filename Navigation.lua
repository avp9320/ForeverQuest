-- ForeverQuest navigation: in-game directional guidance and Blizzard's
-- official quest supertracking and opt-in-safe Blizzard waypoints.
-- AUTO may replace only a waypoint this addon last placed, never a player pin.
local Nav = {}
_G.ForeverQuestNavigation = Nav

local function valid(mapID, x, y)
    return type(mapID) == "number" and mapID > 0
        and type(x) == "number" and x >= 0 and x <= 1
        and type(y) == "number" and y >= 0 and y <= 1
end

local function xy(point)
    if type(point) ~= "table" then return nil end
    local pos = point.position or point
    if type(pos) ~= "table" then return nil end
    if type(pos.x) == "number" and type(pos.y) == "number" then
        return pos.x, pos.y
    end
    if type(pos.GetXY) == "function" then
        local ok, x, y = pcall(pos.GetXY, pos)
        if ok and type(x) == "number" and type(y) == "number" then
            return x, y
        end
    end
end

function Nav:Destination(questID, kind, fallback)
    local entry = _G.ForeverQuestData and _G.ForeverQuestData[questID]
    if type(entry) ~= "table" then return fallback end
    local p = kind == "pickup" and entry.pickup
        or kind == "turnin" and entry.turnIn or entry.objective
    if type(p) ~= "table" then return fallback end
    local npc = p.npc or p.giver or fallback
    local area = p.area
    if type(npc) == "string" and npc ~= "" and type(area) == "string"
        and area ~= "" then
        return npc .. " - " .. area
    end
    return area or npc or fallback
end

function Nav:Guidance(target)
    if type(target) ~= "table" or not valid(target.mapID, target.x, target.y)
        or not (C_Map and type(C_Map.GetPlayerMapPosition) == "function") then
        return nil
    end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, target.mapID, "player")
    if not ok or not position then return nil end
    local px, py = xy(position)
    if not px then return nil end
    local dx, dy = target.x - px, target.y - py
    local normalized = math.sqrt(dx * dx + dy * dy)
    local radians = math.atan2 and math.atan2(dx, -dy) or nil
    if not radians then
        -- Lua 5.1 doesn't guarantee atan2. Handle the east/west axis
        -- explicitly instead of dividing by negative zero.
        if dx == 0 and dy == 0 then radians = 0
        elseif dy == 0 then radians = dx > 0 and math.pi / 2 or -math.pi / 2
        else
            radians = math.atan(dx / -dy)
            if dy > 0 then radians = radians + math.pi end
        end
    end
    local angle = (math.deg(radians) + 360) % 360
    local compass = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
    local direction = compass[(math.floor((angle + 22.5) / 45) % 8) + 1]

    local yards
    if C_Map and type(C_Map.GetMapWorldSize) == "function" then
        local good, w, h = pcall(C_Map.GetMapWorldSize, target.mapID)
        if good and type(w) == "number" and type(h) == "number"
            and w > 0 and h > 0 then
            yards = math.sqrt((dx * w) ^ 2 + (dy * h) ^ 2)
        end
    end
    local label
    if yards then
        if yards <= 15 then
            label = "Nearby"
        elseif yards < 1000 then
            label = string.format("%s ~%d yd", direction,
                math.floor((yards + 5) / 10) * 10)
        else
            label = string.format("%s ~%.1fk yd", direction, yards / 1000)
        end
    elseif normalized < 0.003 then
        label = "Nearby"
    else
        label = string.format("%s ~%.0f,%.0f", direction,
            target.x * 100, target.y * 100)
    end
    return {label = label, direction = direction, straightYards = yards,
        normalizedDistance = normalized,
        mapID = target.mapID, x = target.x, y = target.y}
end


-- Track ownership only while running; a fresh session treats any existing
-- waypoint as player-owned until the player explicitly Shift-clicks.
local ownedPin
local function coordinates(point)
    if not point or type(point) ~= "table" then return nil end
    local position = point.position
    if not position then return nil end
    local x, y
    if type(position.GetXY) == "function" then
        local ok, ax, ay = pcall(position.GetXY, position)
        if ok then x,y=ax,ay end
    elseif type(position) == "table" then
        x,y=position.x,position.y
    end
    if type(point.uiMapID)=="number" and type(x)=="number" and type(y)=="number" then
        return point.uiMapID,x,y
    end
end
local function equivalent(point, destination)
    if not point or not destination then return false end
    local map,x,y=coordinates(point)
    return map==destination.mapID and x and y
        and math.abs(x-destination.x)<0.0004
        and math.abs(y-destination.y)<0.0004
end
function Nav:PlacePin(destination, manual)
    if not destination or not valid(destination.mapID,destination.x,destination.y) then
        return false,"No valid map coordinates."
    end
    if not (C_Map and type(C_Map.SetUserWaypoint)=="function" and
        type(C_Map.GetUserWaypoint)=="function" and UiMapPoint and
        type(UiMapPoint.CreateFromCoordinates)=="function") then
        return false,"Blizzard waypoint API unavailable."
    end
    if type(C_Map.CanSetUserWaypointOnMap)=="function" then
        local ok,allowed=pcall(C_Map.CanSetUserWaypointOnMap,destination.mapID)
        if not ok or allowed==false then return false,"Waypoints unavailable on this map." end
    end
    local ok,current=pcall(C_Map.GetUserWaypoint)
    if not ok then return false,"Cannot inspect the existing waypoint." end
    if current and equivalent(current,destination) then
        if manual then ownedPin={mapID=destination.mapID,x=destination.x,y=destination.y} end
        return true
    end
    if not manual and current and (not ownedPin or not equivalent(current,ownedPin)) then
        return false,"Keeping your personal map pin."
    end
    local created,point=pcall(UiMapPoint.CreateFromCoordinates,destination.mapID,destination.x,destination.y)
    if not created or not point then return false,"Could not create a waypoint." end
    local set,result=pcall(C_Map.SetUserWaypoint,point)
    if not set or result==false then return false,"Game rejected the waypoint." end
    ownedPin={mapID=destination.mapID,x=destination.x,y=destination.y}
    return true
end
function Nav:AutoPin(destination)
    if not ForeverQuestDB or ForeverQuestDB.autoPin==false then return false end
    return self:PlacePin(destination,false)
end

-- Only accepted quests can use Blizzard's official quest objective.
-- Avoid repeatedly writing the same supertracked quest every refresh.
function Nav:TrackQuest(questID)
    if type(questID) ~= "number" or questID <= 0
        or not (C_SuperTrack and
            type(C_SuperTrack.SetSuperTrackedQuestID) == "function") then
        return false
    end
    if type(C_SuperTrack.GetSuperTrackedQuestID) == "function" then
        local ok, current = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and current == questID then return true end
    end
    local ok, result = pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
    return ok and result ~= false
end
