-- ForeverQuest self-contained quest-chain graph.
-- Classic and Forever data is incomplete: edges represent possible chain
-- relationships, not proof an NPC currently offers the next quest.
local Chain = {}
_G.ForeverQuestChains = Chain

local revision, forward

local function getDB()
    local lib = _G.ForeverQuestCatalog
    return lib and lib.Quest
end

local function get(questID, field)
    local db = getDB()
    if not db or not db.Get then return nil end
    local ok, value = pcall(db.Get, questID, field)
    return ok and value or nil
end

local function addEdge(all, before, after, kind)
    if type(before)~="number" or before<1
        or type(after)~="number" or after<1
        or before==after then return end
    all[before]=all[before] or {}
    local entry=all[before][after]
    if not entry then
        all[before][after]={questID=after,via=kind}
    elseif kind=="required" then
        -- A mandatory prerequisite beats a weaker "may follow" link.
        entry.via=kind
    end
end

local function build()
    local db=getDB()
    if not db or type(db.GetAllIds)~="function" then return {} end
    if revision==db and forward then return forward end
    local links={}
    local ok,ids=pcall(db.GetAllIds)
    if not ok or type(ids)~="table" then return {} end
    for _,id in ipairs(ids) do
        if type(id)=="number" then
            local children=get(id,"childQuests")
            if type(children)=="table" then
                for _,child in ipairs(children) do addEdge(links,id,child,"possible") end
            end
            local nextID=get(id,"nextQuestInChain")
            addEdge(links,id,nextID,"possible")
            local parent=get(id,"parentQuest")
            addEdge(links,parent,id,"required")
            local prereqs=get(id,"preQuestGroup")
            if type(prereqs)=="table" then
                for _,prereq in ipairs(prereqs) do
                    addEdge(links,prereq,id,"required")
                end
            end
            local singles=get(id,"preQuestSingle")
            if type(singles)=="table" then
                for _,prereq in ipairs(singles) do
                    addEdge(links,prereq,id,"possible")
                end
            end
            addEdge(links,get(id,"availableStartingWith"),id,"possible")
        end
    end
    forward={}
    for parent,children in pairs(links) do
        local sorted={}
        for _,child in pairs(children) do
            if get(child.questID,"name") then sorted[#sorted+1]=child end
        end
        table.sort(sorted,function(a,b)return a.questID<b.questID end)
        forward[parent]=sorted
    end
    revision=db
    return forward
end

function Chain:GetNextIDs(questID)
    local links=build()[questID] or {}
    local result={}
    for _,nextStep in ipairs(links) do
        result[#result+1]=nextStep.questID
    end
    return result
end

function Chain:GetPreview(questID,level,limit)
    local items=build()[questID] or {}
    local result={}
    for _,nextStep in ipairs(items) do
        local id=nextStep.questID
        local name=get(id,"name")
        if type(name)=="string" and name~="" then
            local min=tonumber(get(id,"requiredLevel")) or 1
            local qlevel=tonumber(get(id,"questLevel")) or min
            result[#result+1]={
                questID=id,name=name,requiredLevel=min,
                questLevel=qlevel,relation=nextStep.via,
                nearLevel=not level or (min<=level+5 and qlevel<=level+8),
            }
        end
    end
    table.sort(result,function(a,b)
        if a.nearLevel~=b.nearLevel then return a.nearLevel end
        if a.requiredLevel==b.requiredLevel then return a.questID<b.questID end
        return a.requiredLevel<b.requiredLevel
    end)
    local max=math.min(20,math.max(1,tonumber(limit) or 4))
    while #result>max do result[#result]=nil end
    return result
end

function Chain:Reset()
    forward=nil
    revision=nil
end
