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
