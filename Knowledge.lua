-- ForeverQuest account-wide observed quest locations.
-- Only records the character's actual map coordinates on quest acceptance
-- or turn-in. Observations are local to the account and never sent online.
-- One observation is helpful for alts but not proof every NPC is identical
-- across Forever phases, factions, or seasons.
local Knowledge = {}
_G.ForeverQuestKnowledge = Knowledge

local function reasonable(mapID,x,y)
    return type(mapID)=="number" and mapID>0
        and type(x)=="number" and x>=0 and x<=1
        and type(y)=="number" and y>=0 and y<=1
end

local function records(db, kind)
    if type(db)~="table" then return nil end
    db.learnedQuestLocations = db.learnedQuestLocations or {
        pickup={},turnin={},
    }
    local root=db.learnedQuestLocations
    root[kind] = root[kind] or {}
    return root[kind]
end

function Knowledge:Observe(db,kind,questID,mapID,x,y)
    if (kind~="pickup" and kind~="turnin")
        or type(questID)~="number" or questID<1
        or not reasonable(mapID,x,y) then return false end
    local dest=records(db,kind)
    if not dest then return false end
    local old=dest[questID]
    if old and old.mapID==mapID then
        -- Favor the more recent observation, but avoid misleading
        -- sub-pixel jitter generating constant changes.
        if math.abs(old.x-x)<.0001 and math.abs(old.y-y)<.0001 then
            return false
        end
    end
    dest[questID]={mapID=mapID,x=x,y=y,
        source="account-observed",lastSeen=time and time() or 0}
    return true
end

function Knowledge:Get(db,kind,questID)
    if (kind~="pickup" and kind~="turnin")
        or type(questID)~="number" then return nil end
    local dest=records(db,kind)
    local item=dest and dest[questID]
    if item and reasonable(item.mapID,item.x,item.y) then
        return {mapID=item.mapID,x=item.x,y=item.y,
            confidence="account-observed",kind=kind}
    end
end

function Knowledge:Counts(db)
    local out={pickup=0,turnin=0}
    for kind in pairs(out) do
        local t=records(db,kind)
        if t then for _ in pairs(t) do out[kind]=out[kind]+1 end end
    end
    return out
end

function Knowledge:Clear(db)
    if type(db)~="table" then return end
    db.learnedQuestLocations={pickup={},turnin={}}
end
