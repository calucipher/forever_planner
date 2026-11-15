-- Content/Zones.lua: dados curados para a sugestão de zona (spec 029).
-- Fonte: AreaTable do client Forever 1.60.1 (ID, ContinentID, ParentAreaID), lida pelo
-- wow.tools.local em 10/11/2026, e a pesquisa de `pesquisa/README.md` na mesma data.
-- Muda com patch. O que não foi visto no jogo está marcado como estimativa.
local _, ns = ...
local ZoneContent = {}
ns.ZoneContent = ZoneContent

-- Continente por área (AreaTable.ContinentID): 0 Reinos do Leste, 1 Kalimdor, outros = ilhas do Forever.
local EK, KAL = 0, 1
ZoneContent.continent = {
    [1] = EK, [3] = EK, [4] = EK, [8] = EK, [10] = EK, [11] = EK, [12] = EK, [25] = EK, [28] = EK,
    [33] = EK, [36] = EK, [38] = EK, [40] = EK, [41] = EK, [44] = EK, [45] = EK, [46] = EK, [47] = EK,
    [51] = EK, [85] = EK, [130] = EK, [139] = EK, [267] = EK, [1497] = EK, [1519] = EK, [1537] = EK,
    [14] = KAL, [15] = KAL, [16] = KAL, [17] = KAL, [141] = KAL, [148] = KAL, [215] = KAL, [331] = KAL,
    [357] = KAL, [361] = KAL, [400] = KAL, [405] = KAL, [406] = KAL, [440] = KAL, [490] = KAL,
    [493] = KAL, [618] = KAL, [1377] = KAL, [1637] = KAL, [1638] = KAL, [1657] = KAL, [16651] = KAL,
    [16593] = 2991, -- Zephras Isle
    [16606] = 2997, -- Darkspear Islands
}

-- Spec 035, R6: zonas com divisa a pé (basta listar de um lado; Zones.Neighbors completa o outro).
-- Fonte: mapa do jogo (Classic, o mesmo no Forever), 12/11/2026. ESTIMATIVA até conferir no jogo:
-- Alterac > Western Plaguelands e as capitais são as mais incertas. Barco e zepelim não contam.
ZoneContent.neighbors = {
    -- Reinos do Leste
    [85] = { 130, 28, 1497 },        -- Tirisfal: Silverpine, Western Plaguelands, Undercity
    [130] = { 267 },                 -- Silverpine: Hillsbrad
    [267] = { 36, 45, 47 },          -- Hillsbrad: Alterac, Arathi, Hinterlands
    [36] = { 28 },                   -- Alterac: Western Plaguelands
    [28] = { 139 },                  -- Western Plaguelands: Eastern Plaguelands
    [45] = { 11 },                   -- Arathi: Wetlands
    [11] = { 38 },                   -- Wetlands: Loch Modan
    [38] = { 1, 3 },                 -- Loch Modan: Dun Morogh, Badlands
    [1] = { 1537 },                  -- Dun Morogh: Ironforge
    [3] = { 51 },                    -- Badlands: Searing Gorge
    [51] = { 25 },                   -- Searing Gorge: Blackrock Mountain
    [25] = { 46 },                   -- Blackrock Mountain: Burning Steppes
    [46] = { 44 },                   -- Burning Steppes: Redridge
    [44] = { 12, 10 },               -- Redridge: Elwynn, Duskwood
    [12] = { 1519, 40, 10 },         -- Elwynn: Stormwind, Westfall, Duskwood
    [10] = { 40, 41, 33 },           -- Duskwood: Westfall, Deadwind Pass, Stranglethorn
    [41] = { 8 },                    -- Deadwind Pass: Swamp of Sorrows
    [8] = { 4 },                     -- Swamp of Sorrows: Blasted Lands
    -- Kalimdor
    [14] = { 1637, 17 },             -- Durotar: Orgrimmar, Barrens
    [17] = { 215, 406, 331, 400, 15 }, -- Barrens: Mulgore, Stonetalon, Ashenvale, Thousand Needles, Dustwallow
    [215] = { 1638 },                -- Mulgore: Thunder Bluff
    [406] = { 331, 405 },            -- Stonetalon: Ashenvale, Desolace
    [331] = { 148, 361, 16 },        -- Ashenvale: Darkshore, Felwood, Azshara
    [405] = { 357 },                 -- Desolace: Feralas
    [357] = { 400 },                 -- Feralas: Thousand Needles
    [400] = { 440 },                 -- Thousand Needles: Tanaris
    [440] = { 490 },                 -- Tanaris: Un'Goro
    [490] = { 1377 },                -- Un'Goro: Silithus
    [361] = { 618, 493 },            -- Felwood: Winterspring, Moonglade
    [618] = { 493 },                 -- Winterspring: Moonglade
    [141] = { 1657 },                -- Teldrassil: Darnassus
}

-- Zonas cujas quests ficam fora do plano da facção: capitais inimigas (R8).
ZoneContent.enemyCities = {
    Horde = { [1519] = true, [1537] = true, [1657] = true },     -- Stormwind, Ironforge, Darnassus
    Alliance = { [1637] = true, [1497] = true, [1638] = true },  -- Orgrimmar, Undercity, Thunder Bluff
}

-- Zona inicial de outra raça (R8). Estimativa: a QuestieDB não traz restrição de raça e não foi
-- confirmado no jogo. Zephras Isle: "Coming of Age", Thendal Village, nível 1.
ZoneContent.starterZones = {
    [16593] = { note = "zona inicial da raça nova do Forever (estimativa)" },
}

-- Instâncias que a QuestieDB não marca como masmorra (fora da rota solo).
ZoneContent.instances = { [133] = true, [978] = true, [1417] = true, [1517] = true, [1717] = true }

-- Área só de quests de profissão (AreaTable "CraftingQuestNameOnly").
ZoneContent.professionAreas = { [16941] = true }

-- NPCs que a base traz como mob mas não são (R7): Invasão do Flagelo e auxiliares invisíveis.
ZoneContent.helperNames = { "Invasion", "Necropolis", "[Ff]inder", "Proxy", "Relay", " health", "Trigger",
    "Bunny", "DND", "Dummy", "Resonating Crystal", "Shadow of Doom", "Flameshocker" }

-- Facções de bicho (Prey e Ambient): não contam como mob.
ZoneContent.critterFactions = { [31] = true, [188] = true }

-- Spec 030 (emenda R1): NPC sem facção na base (0) e da facção 35 (amigo de todos) não contam no
-- nível médio do objetivo. Casos do Forever, 11/11/2026: 99141 Deathguard Kristof (0, nível 55),
-- 99134 Deathguards (0), 99411 Kyle the Frenzied (35, nível 12).
ZoneContent.notMobFactions = { [0] = true, [35] = true }
