-- Weights.lua: pesos de atributo por spec.
-- ATENÇÃO: não existem pesos oficiais do Forever. Estes são heurísticos, derivados das
-- prioridades publicadas (Icy Veins, Warcraft Tavern, Mobalytics, Maxroll) e dos pesos
-- clássicos de caster. Calibre com dummy / tempo de kill real e ajuste na aba Builds.
local _, ns = ...
local Weights = {}
ns.Weights = Weights

-- Chaves: sp (spell power genérico), shadow, fire (dano de escola), sta, int, spi,
-- crit, hit, haste (ratings), dps (DPS de varinha, só slot ranged).
Weights.presets = {
    affliction = {
        label = "Affliction (leveling)",
        w = { sp = 1.00, shadow = 0.95, fire = 0.25, sta = 0.50, int = 0.40, spi = 0.35,
              crit = 0.60, hit = 0.30, haste = 0.50, dps = 3.0 },
    },
    demonology = {
        label = "Demonology",
        w = { sp = 1.00, shadow = 0.90, fire = 0.35, sta = 0.65, int = 0.40, spi = 0.35,
              crit = 0.50, hit = 0.30, haste = 0.45, dps = 3.0 },
    },
    destruction = {
        label = "Destruction (40+)",
        w = { sp = 1.00, shadow = 0.60, fire = 0.90, sta = 0.45, int = 0.50, spi = 0.30,
              crit = 0.70, hit = 0.30, haste = 0.55, dps = 2.5 },
    },
}

Weights.statLabels = {
    sp = "Spell Power", shadow = "Dano de Sombra", fire = "Dano de Fogo", sta = "Stamina",
    int = "Intelecto", spi = "Espírito", crit = "Crit", hit = "Hit", haste = "Haste",
    dps = "DPS (varinha)",
}
Weights.order = { "sp", "shadow", "fire", "sta", "int", "spi", "crit", "hit", "haste", "dps" }

function Weights.PresetNames()
    local names = {}
    for k in pairs(Weights.presets) do names[#names + 1] = k end
    table.sort(names)
    return names
end

-- Ajuste por faixa de nível (sobrevivência pesa mais cedo, crit pesa mais tarde).
local function bandAdjust(w, level)
    if level < 20 then
        w.sta = math.max(w.sta, 0.60); w.crit = math.min(w.crit, 0.30)
    elseif level >= 40 then
        w.crit = math.max(w.crit, 0.70)
    end
    return w
end

-- preset, overrides (db.customWeights) e nível -> tabela final de pesos
function Weights.Get(presetName, overrides, level)
    local p = Weights.presets[presetName] or Weights.presets.affliction
    local w = {}
    for k, v in pairs(p.w) do w[k] = v end
    bandAdjust(w, level or 1)
    for k, v in pairs(overrides or {}) do
        if type(v) == "number" then w[k] = v end
    end
    return w
end

return Weights
