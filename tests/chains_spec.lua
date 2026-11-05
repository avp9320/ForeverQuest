-- Independent quest-chain graph regression tests.
local function equal(got, want, why)
    assert(got == want, (why or "value") .. " expected "
        .. tostring(want) .. " got " .. tostring(got))
end
local rows={
    [50]={name="First",nextQuestInChain=51,childQuests={55}},
    [51]={name="Second",preQuestGroup={50},requiredLevel=10},
    [52]={name="Alternate",preQuestSingle={50},requiredLevel=9},
    [53]={name="Nested",parentQuest=50,requiredLevel=9},
    [54]={name="Opens after",availableStartingWith=50,requiredLevel=8},
    [55]={name="Bonus follow-up",requiredLevel=40},
}
ForeverQuestCatalog={Quest={
    Get=function(id,field)return rows[id] and rows[id][field] end,
    GetAllIds=function()return {50,51,52,53,54,55} end,
}}
dofile("Chains.lua")
local chain=_G.ForeverQuestChains
local nextIDs=chain:GetNextIDs(50)
equal(#nextIDs,5,"all reverse prerequisites and follow-ups")
for i=1,5 do equal(nextIDs[i],50+i,"stable ascending IDs") end
local preview=chain:GetPreview(50,10,5)
equal(#preview,5,"five possible follow-ups")
assert(preview[1].nearLevel,"near-level chain prioritized")
assert(not preview[5].nearLevel,"far-level chain clearly marked")
local foundRequired=false
for _,step in ipairs(preview) do
    if step.questID==51 then
        equal(step.relation,"required","mandatory prerequisite recorded")
        foundRequired=true
    end
end
assert(foundRequired,"mandatory link should exist")
dofile("Strategy.lua")
local immediate, distant=_G.ForeverQuestStrategy:ChainValue(50,10)
equal(immediate,4,"four near-level unlocks")
equal(distant,0,"level-40 unlock not an immediate benefit")
chain:Reset()
equal(#chain:GetNextIDs(50),5,"graph rebuild")
print("ForeverQuest full prerequisite chain tests passed")
