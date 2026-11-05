-- ForeverQuest compact navigation: readable bearing / straight-line yardage
-- and respectful use of Blizzard's user waypoint.
-- No terrain routes or client-only claimed precision. Never replaces a
-- player's own map pin in AUTO. Shift-click is explicit manual navigation.
local Nav = {}
_G.ForeverQuestNavigation = Nav

local ownedWaypoint
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

local function matching(pin, target)
    if not pin or not target or pin.uiMapID ~= target.mapID then return false end
    local x, y = xy(pin)
    return x and math.abs(x - target.x) < 0.00035
        and math.abs(y - target.y) < 0.00035
end

local function currentWaypoint()
    if not (C_Map and type(C_Map.GetUserWaypoint) == "function") then
        return false, nil
    end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok then return false, nil end
    return true, point
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

local function canPlace(target)
    if not valid(target.mapID, target.x, target.y)
        or not (C_Map and type(C_Map.SetUserWaypoint) == "function")
        or not (UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function")
        then return false end
    if C_Map.CanSetUserWaypointOnMap then
        local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, target.mapID)
        if not ok or not allowed then return false end
    end
    if type(InCombatLockdown) == "function" then
        local ok, combat = pcall(InCombatLockdown)
        if not ok or combat then return false end
    end
    return true
end

local function place(target)
    if not canPlace(target) then return false end
    local ok, result = pcall(function()
        return C_Map.SetUserWaypoint(
            UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y))
    end)
    if not ok or result == false then return false end
    ownedWaypoint = {mapID = target.mapID, x = target.x, y = target.y}
    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

function Nav:Mark(target, explicit)
    if not target or not valid(target.mapID, target.x, target.y) then
        return "unavailable"
    end
    if not canPlace(target) then return "unavailable" end
    if not explicit then
        -- A missing GetUserWaypoint API means we cannot safely inspect
        -- the player's existing pin. Disable AUTO marking rather than
        -- risk overwriting a pin they placed themselves.
        local ok, current = currentWaypoint()
        if not ok then return "unsupported" end
        if matching(current, target) then
            return "marked"
        end
        if current and not matching(current, ownedWaypoint) then
            ownedWaypoint = nil
            return "manual-pin"
        end
    end
    return place(target) and "marked" or "unavailable"
end

function Nav:ClearOwnPin()
    local ok, current = currentWaypoint()
    if ownedWaypoint and ok and matching(current, ownedWaypoint)
        and C_Map and type(C_Map.ClearUserWaypoint) == "function" then
        pcall(C_Map.ClearUserWaypoint)
    end
    ownedWaypoint = nil
end

function Nav:OwnsCurrentPin()
    local ok, current = currentWaypoint()
    return ok and ownedWaypoint ~= nil and matching(current, ownedWaypoint)
end
