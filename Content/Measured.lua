-- Content/Measured.lua: tempos medidos no jogo (spec 036, R16). Gerado por `tools/journal.py calibrar`
-- em 25/11/2026, a partir do diário do jogador (visto no jogo; mediana com pelo menos 3 amostras).
-- Não edite à mão: rode a ferramenta de novo.
local _, ns = ...
ns.Measured = {
    date = "25/11/2026",
    travel = { fly = 16.7, flyFactor = 1, flyOverhead = 0, run = 6.3 },
    flights = {
        ["Crossroads, The Barrens > Ratchet, The Barrens"] = 51,
        ["Orgrimmar, Durotar > Crossroads, The Barrens"] = 110,
        ["The Sepulcher, Silverpine Forest > Undercity, Tirisfal"] = 112,
        ["Undercity, Tirisfal > The Sepulcher, Silverpine Forest"] = 106,
    },
    samples = { ["fly"] = 24, ["run"] = 3254, ["voo Crossroads, The Barrens > Ratchet, The Barrens"] = 3, ["voo Orgrimmar, Durotar > Crossroads, The Barrens"] = 4, ["voo The Sepulcher, Silverpine Forest > Undercity, Tirisfal"] = 3, ["voo Undercity, Tirisfal > The Sepulcher, Silverpine Forest"] = 5 },
}
