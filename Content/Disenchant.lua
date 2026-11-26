-- Content/Disenchant.lua: tabela de desencanto (spec 061, R1 e R4). Curada à mão.
-- Fonte: tabela do Classic (Wowpedia, "Disenchanting tables", e Wowhead Classic), consultada em
-- 25/11/2026. ESTIMATIVA: o Forever pode ter mudado faixas e chances; não conferido no jogo (T2).
-- Faixas por nível do item; verde (2) e azul (3); armadura e arma (na arma, essência e pó trocam).
-- Cada material: id do item, chance da faixa e quantidade mínima e máxima.
local _, ns = ...

local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = { lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134,
    gmystic = 11135, lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203 }
local SHARD = { sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178,
    sbril = 14343, lbril = 14344 }

-- { min, max, pó, pó min, pó max, essência, ess. min, ess. max, fragmento (ou nil) }
local GREEN = {
    { 5, 15, DUST.strange, 1, 2, ESS.lmagic, 1, 2, nil },
    { 16, 20, DUST.strange, 2, 3, ESS.gmagic, 1, 2, SHARD.sglim },
    { 21, 25, DUST.strange, 4, 6, ESS.lastral, 1, 2, SHARD.sglim },
    { 26, 30, DUST.soul, 1, 2, ESS.gastral, 1, 2, SHARD.lglim },
    { 31, 35, DUST.soul, 2, 5, ESS.lmystic, 1, 2, SHARD.sglow },
    { 36, 40, DUST.vision, 1, 2, ESS.gmystic, 1, 2, SHARD.lglow },
    { 41, 45, DUST.vision, 2, 5, ESS.lnether, 1, 2, SHARD.srad },
    { 46, 50, DUST.dream, 1, 2, ESS.gnether, 1, 2, SHARD.lrad },
    { 51, 55, DUST.dream, 2, 5, ESS.leternal, 1, 2, SHARD.sbril },
    { 56, 60, DUST.illusion, 1, 2, ESS.geternal, 1, 2, SHARD.lbril },
    { 61, 65, DUST.illusion, 2, 5, ESS.geternal, 2, 3, SHARD.lbril },
}
-- Azul: o fragmento da faixa (quase sempre 1).
local BLUE = {
    { 5, 25, SHARD.sglim }, { 26, 30, SHARD.lglim }, { 31, 35, SHARD.sglow }, { 36, 40, SHARD.lglow },
    { 41, 45, SHARD.srad }, { 46, 50, SHARD.lrad }, { 51, 55, SHARD.sbril }, { 56, 65, SHARD.lbril },
}

local function greens(weapon)
    local out = {}
    for _, r in ipairs(GREEN) do
        local shard = r[9] and 0.05 or 0
        if r[1] == 21 then shard = 0.10 end -- a faixa 21–25 dá mais fragmento
        -- armadura: pó 75% (80% na primeira faixa), essência com o resto; arma: troca, essência 75%
        -- (80% na primeira faixa) e pó com o resto (parecer 061: na 21–25 da arma, pó 15%)
        local main = (r[1] == 5) and 0.80 or 0.75
        local dust, ess
        if weapon then ess = main; dust = 1 - ess - shard else dust = main; ess = 1 - dust - shard end
        local mats = { { id = r[3], chance = dust, min = r[4], max = r[5] }, { id = r[6], chance = ess, min = r[7], max = r[8] } }
        if r[9] then mats[3] = { id = r[9], chance = shard, min = 1, max = 1 } end
        out[#out + 1] = { min = r[1], max = r[2], mats = mats }
    end
    return out
end
local function blues()
    local out = {}
    for _, r in ipairs(BLUE) do out[#out + 1] = { min = r[1], max = r[2], mats = { { id = r[3], chance = 1, min = 1, max = 1 } } } end
    return out
end

ns.DisenchantTable = {
    armor = { [2] = greens(false), [3] = blues() },
    weapon = { [2] = greens(true), [3] = blues() },
    -- nível de Enchanting exigido pelo nível do item (até max)
    skill = { { max = 20, skill = 1 }, { max = 25, skill = 25 }, { max = 30, skill = 50 }, { max = 35, skill = 75 },
        { max = 40, skill = 100 }, { max = 45, skill = 125 }, { max = 50, skill = 150 }, { max = 55, skill = 175 },
        { max = 60, skill = 200 }, { max = 65, skill = 225 } },
}
return ns.DisenchantTable
