-- Content/Transports.lua: destino de cada zepelim e barco entre continentes (specs 019 e 020).
-- A QuestieDB dá a posição e o subtítulo, não o destino. Fonte: rotas do Classic, as mesmas no
-- Forever; Tirisfal (Zapetta para Orgrimmar, Hin Denburg para Grom'gol) confirmado no jogo em
-- 07/11/2026. As outras rotas são estimativa até serem vistas no jogo. Muda com patch.
-- crosses = a rota muda de continente. pair = o transporte do outro lado (mesmo tipo): a posição
-- dele na QuestieDB é o ponto de chegada. Transporte fora daqui o addon não usa.
local _, ns = ...
local Transports = {}
ns.Transports = Transports

Transports.npc = { -- Zeppelin Masters da Horda, por ID de NPC
    [9566] = { dest = "Orgrimmar", crosses = true, pair = 9564 },     -- Zapetta (Tirisfal)
    [3150] = { dest = "Grom'gol", crosses = false, pair = 3149 },     -- Hin Denburg (Tirisfal)
    [9564] = { dest = "Undercity", crosses = true, pair = 9566 },     -- Frezza (Durotar)
    [12136] = { dest = "Grom'gol", crosses = true, pair = 12137 },    -- Snurk Bucksquick (Durotar)
    [12137] = { dest = "Orgrimmar", crosses = true, pair = 12136 },   -- Squibby Overspeck (Stranglethorn)
    [3149] = { dest = "Undercity", crosses = false, pair = 3150 },    -- Nez'raz (Stranglethorn)
}

Transports.object = { -- placas "Boat to ..." da Aliança, por ID de objeto
    [176364] = { dest = "Menethil Harbor", crosses = true, pair = 176370 }, -- Auberdine (Darkshore)
    [176365] = { dest = "Teldrassil", crosses = false },                    -- Auberdine (Darkshore)
    [176369] = { dest = "Theramore", crosses = true },                      -- Menethil Harbor (Wetlands); a placa de Theramore não tem posição na QuestieDB
    [176370] = { dest = "Auberdine", crosses = true, pair = 176364 },       -- Menethil Harbor (Wetlands)
    [181985] = { dest = "Auberdine", crosses = true },                      -- sem posição na QuestieDB
}

return Transports
