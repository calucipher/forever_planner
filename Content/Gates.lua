-- Content/Gates.lua: passagens entre zonas por continente (spec 049, fonte 2). GERADO por tools/gen_gates.py.
-- Fonte: estradas de Content/Roads.lua (spec 034) e areaId do terreno (.adt raiz) do cliente do Forever, build 1.60.1.71037, 21/11/2026.
-- Ponto = onde a estrada cruza de uma zona para outra (ESTIMATIVA até conferir no jogo; passagem fora de estrada não aparece).
-- relevo = true: achada pela inclinação do chão e pela ligação com o vale das duas zonas, sem estrada (mais incerta).
-- Fora por pesquisa: Mulgore | Desolace: sem passagem (fórum da Blizzard, us.forums.blizzard.com/en/wow/t/1284441); Mulgore | Stonetalon: sem passagem (o mesmo fórum); Mulgore | Shen'dralas: só pelo Valley of Bones, em Desolace (forever-hub.com/en/guides/new-zones).
-- O terreno não vê túnel nem ponte (Talondeep Pass, Thandol Span, túnel dos Timbermaw): essas vêm do jogo (aprendidas).
-- Formato: { a = zona, b = zona, x, y } em jardas do mundo (x norte, y oeste); vale nos dois sentidos.
local _, ns = ...
local G = {}
ns.GateData = G
G[0] = {
    { a = 1, b = 11, x = -4162, y = -1400, relevo = true }, -- Dun Morogh | Wetlands
    { a = 1, b = 38, x = -5611, y = -2500 }, -- Dun Morogh | Loch Modan
    { a = 3, b = 38, x = -5996, y = -3300, relevo = true }, -- Badlands | Loch Modan
    { a = 3, b = 16591, x = -7429, y = -3438, relevo = true }, -- Badlands | Riverglades
    { a = 4, b = 8, x = -10664, y = -2980 }, -- Blasted Lands | Swamp of Sorrows
    { a = 8, b = 44, x = -9597, y = -3767 }, -- Swamp of Sorrows | Redridge Mountains
    { a = 8, b = 16591, x = -9596, y = -4379, relevo = true }, -- Swamp of Sorrows | Riverglades
    { a = 8, b = 16591, x = -9596, y = -3892, relevo = true }, -- Swamp of Sorrows | Riverglades
    { a = 10, b = 12, x = -10135, y = 509, relevo = true }, -- Duskwood | Elwynn Forest
    { a = 10, b = 12, x = -10091, y = 35, relevo = true }, -- Duskwood | Elwynn Forest
    { a = 10, b = 12, x = -9950, y = -1066, relevo = true }, -- Duskwood | Elwynn Forest
    { a = 10, b = 12, x = -9941, y = -1468, relevo = true }, -- Duskwood | Elwynn Forest
    { a = 10, b = 12, x = -9931, y = -540, relevo = true }, -- Duskwood | Elwynn Forest
    { a = 10, b = 33, x = -11262, y = 283, relevo = true }, -- Duskwood | Stranglethorn Vale
    { a = 10, b = 40, x = -10859, y = 632 }, -- Duskwood | Westfall
    { a = 10, b = 44, x = -9900, y = -1709 }, -- Duskwood | Redridge Mountains
    { a = 11, b = 38, x = -5363, y = -4396, relevo = true }, -- Wetlands | Loch Modan
    { a = 11, b = 38, x = -4742, y = -4396, relevo = true }, -- Wetlands | Loch Modan
    { a = 11, b = 38, x = -4262, y = -4125, relevo = true }, -- Wetlands | Loch Modan
    { a = 12, b = 40, x = -9800, y = 831 }, -- Elwynn Forest | Westfall
    { a = 12, b = 44, x = -9609, y = -1735 }, -- Elwynn Forest | Redridge Mountains
    { a = 28, b = 36, x = 592, y = -1763, relevo = true }, -- Western Plaguelands | Alterac Mountains
    { a = 28, b = 36, x = 870, y = -1475 }, -- Western Plaguelands | Alterac Mountains
    { a = 28, b = 85, x = 1719, y = -798 }, -- Western Plaguelands | Tirisfal Glades
    { a = 28, b = 139, x = 1502, y = -3038, relevo = true }, -- Western Plaguelands | Eastern Plaguelands
    { a = 28, b = 139, x = 1928, y = -2604 }, -- Western Plaguelands | Eastern Plaguelands
    { a = 33, b = 408, x = -13682, y = 2668 }, -- Stranglethorn Vale | Gillijim's Isle
    { a = 33, b = 408, x = -13165, y = 2666 }, -- Stranglethorn Vale | Gillijim's Isle
    { a = 36, b = 85, x = 1438, y = -4, relevo = true }, -- Alterac Mountains | Tirisfal Glades
    { a = 36, b = 130, x = -35, y = 465, relevo = true }, -- Alterac Mountains | Silverpine Forest
    { a = 36, b = 130, x = 520, y = 511, relevo = true }, -- Alterac Mountains | Silverpine Forest
    { a = 36, b = 130, x = 1051, y = 145, relevo = true }, -- Alterac Mountains | Silverpine Forest
    { a = 36, b = 267, x = -162, y = 116 }, -- Alterac Mountains | Hillsbrad Foothills
    { a = 36, b = 267, x = -129, y = -442, relevo = true }, -- Alterac Mountains | Hillsbrad Foothills
    { a = 36, b = 267, x = 198, y = -678 }, -- Alterac Mountains | Hillsbrad Foothills
    { a = 44, b = 16591, x = -8833, y = -3126 }, -- Redridge Mountains | Riverglades
    { a = 44, b = 16591, x = -8676, y = -2668 }, -- Redridge Mountains | Riverglades
    { a = 45, b = 267, x = -834, y = -1584 }, -- Arathi Highlands | Hillsbrad Foothills
    { a = 47, b = 267, x = -126, y = -1807, relevo = true }, -- The Hinterlands | Hillsbrad Foothills
    { a = 85, b = 130, x = 1531, y = 600 }, -- Tirisfal Glades | Silverpine Forest
    { a = 85, b = 139, x = 3492, y = -2263, relevo = true }, -- Tirisfal Glades | Eastern Plaguelands
    { a = 130, b = 267, x = -584, y = 630 }, -- Silverpine Forest | Hillsbrad Foothills
    { a = 130, b = 17065, x = -831, y = 1555 }, -- Silverpine Forest | Gilneas
    { a = 16756, b = 17065, x = -1850, y = 1262 }, -- Ruins of Gilneas | Gilneas
    { a = 16756, b = 17065, x = -1409, y = 1264 }, -- Ruins of Gilneas | Gilneas
    { a = 17065, b = 17066, x = -2448, y = 1828, relevo = true }, -- Gilneas | Shark-Infested Waters
}
G[1] = {
    { a = 14, b = 16, x = 2067, y = -5462, relevo = true }, -- Durotar | Azshara
    { a = 14, b = 17, x = -131, y = -3791, relevo = true }, -- Durotar | The Barrens
    { a = 14, b = 17, x = 320, y = -3768 }, -- Durotar | The Barrens
    { a = 14, b = 17, x = 1065, y = -3852, relevo = true }, -- Durotar | The Barrens
    { a = 14, b = 17, x = 1488, y = -3896, relevo = true }, -- Durotar | The Barrens
    { a = 14, b = 1637, x = 1404, y = -4370, relevo = true }, -- Durotar | Orgrimmar
    { a = 15, b = 17, x = -3683, y = -2463 }, -- Dustwallow Marsh | The Barrens
    { a = 15, b = 17, x = -2346, y = -3846, relevo = true }, -- Dustwallow Marsh | The Barrens
    { a = 16, b = 331, x = 2814, y = -3799 }, -- Azshara | Ashenvale
    { a = 17, b = 215, x = -2343, y = -1537 }, -- The Barrens | Mulgore
    { a = 17, b = 331, x = 1335, y = -2256 }, -- The Barrens | Ashenvale
    { a = 17, b = 400, x = -4564, y = -1850 }, -- The Barrens | Thousand Needles
    { a = 17, b = 406, x = -255, y = -834, relevo = true }, -- The Barrens | Stonetalon Mountains
    { a = 141, b = 1657, x = 9989, y = 2002 }, -- Teldrassil | Darnassus
    { a = 148, b = 331, x = 4070, y = 507 }, -- Darkshore | Ashenvale
    { a = 148, b = 331, x = 4136, y = 38 }, -- Darkshore | Ashenvale
    { a = 148, b = 331, x = 4271, y = 1073, relevo = true }, -- Darkshore | Ashenvale
    { a = 215, b = 1638, x = -1031, y = 57, relevo = true }, -- Mulgore | Thunder Bluff
    { a = 331, b = 361, x = 3570, y = -1514 }, -- Ashenvale | Felwood
    { a = 400, b = 440, x = -6829, y = -3754, relevo = true }, -- Thousand Needles | Tanaris
    { a = 405, b = 16651, x = -2209, y = 1595, relevo = true }, -- Desolace | Shen'dralas
    { a = 440, b = 1377, x = -8775, y = -1062, relevo = true }, -- Tanaris | Silithus
    { a = 616, b = 618, x = 4577, y = -3933 }, -- Mount Hyjal | Winterspring
    { a = 1377, b = 3478, x = -8213, y = 2100 }, -- Silithus | Gates of Ahn'Qiraj
    { a = 1377, b = 3478, x = -8199, y = 1540 }, -- Silithus | Gates of Ahn'Qiraj
}
return G
