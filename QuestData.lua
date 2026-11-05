-- ForeverQuest known location seed. All positions are APPROXIMATE search
-- areas in Durotar map coordinates, not exact guaranteed spawn positions.
-- Native WoW: Forever waypoints override these entries whenever available.
-- Coordinates are percentages normalized into the 0..1 range.
-- This launch seed supplements Classic data with verified Forever-only quests.
-- Do not copy guide prose, third-party addon code or proprietary databases.
--
-- Quest 97279 (Wayward Weapons): Forever beta-build guide,
-- https://bindonforever.com/quest/97279
-- Quest 4402 (Galgar): Forever guide,
-- https://bindonforever.com/quest/4402
-- Quest 789 (Sting): Classic-derived objective pins (not yet live-verified),
-- https://questing.wiki/wow-forever/quests/789/
-- Quest 792 (Vile Familiars): Classic-derived objective pins,
-- https://questing.wiki/wow-forever/quests/792/
-- Durotar Classic UiMapID 1411:
-- https://warcraft.wiki.gg/wiki/UiMapID/Classic
--
-- For future Forever corrections, change entries here by quest ID, document
-- the exact source/build, and keep unverified Classic data labeled.
_G.ForeverQuestData = {
    [791] = {
        -- Carry Your Weight: pickup/turn-in Furl Scornbrow at the upper
        -- floor of the Razor Hill watchtower. Coordinates are a published
        -- Forever guide location, not an independently observed live pin.
        -- https://bindonforever.com/quest/791
        -- https://questing.wiki/wow-forever/quests/791/
        mapID = 1411,
        pickup = {x = 0.499, y = 0.404,
            npcID = 3147, npc = "Furl Scornbrow",
            area = "Razor Hill watchtower (upper level)"},
        turnIn = {x = 0.499, y = 0.404,
            npc = "Furl Scornbrow",
            area = "Razor Hill watchtower (upper level)"},
        source = "Published Forever quest guide",
        confidence = "forever-guide",
    },
    [97279] = {
        -- Wayward Weapons, new to Forever.
        mapID = 1411,
        objective = { x = 0.435, y = 0.687, area = "Valley of Trials" },
        turnIn = { x = 0.405, y = 0.680, area = "Kzan Thornslash, the Den" },
        source = "Forever beta guide", confidence = "forever-beta",
    },
    [4402] = {
        -- Galgar's Cactus Apple Surprise; quest ID present in Forever.
        mapID = 1411,
        objective = { x = 0.436, y = 0.682, area = "Valley of Trials cacti" },
        turnIn = { x = 0.427, y = 0.672, area = "Galgar" },
        source = "Forever beta guide", confidence = "forever-beta",
    },
    [789] = {
        -- Sting of the Scorpid, legacy Classic objective location.
        mapID = 1411,
        objective = { x = 0.409, y = 0.620, area = "Valley of Trials scorpids" },
        turnIn = { x = 0.421, y = 0.683, area = "Gornek" },
        source = "Classic-derived", confidence = "classic-fallback",
    },
    [792] = {
        -- Vile Familiars, legacy Classic objective location.
        mapID = 1411,
        objective = { x = 0.437, y = 0.555, area = "Cave approach, Valley of Trials" },
        turnIn = { x = 0.429, y = 0.692, area = "Zureetha Fargaze" },
        source = "Classic-derived", confidence = "classic-fallback",
    },
}