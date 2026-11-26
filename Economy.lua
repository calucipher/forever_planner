-- Economy.lua: vender, leiloar ou desencantar (spec 061). Núcleo puro, sem API do jogo.
local _, ns = ...
local Economy = {}
ns.Economy = Economy

Economy.CUT = 0.05          -- taxa da casa de leilões
Economy.DEPOSIT = 0.15      -- depósito de 12 h em fração do preço do vendedor (estimativa do Classic)
Economy.MARGIN = 0.25       -- leilão e desencanto só ganham do vendedor com 25% a mais...
Economy.MIN_GAIN = 1000     -- ...e pelo menos 10 prata

local function band(bands, level)
    for _, b in ipairs(bands or {}) do
        if level >= b.min and level <= b.max then return b end
    end
end

-- R1: valor esperado dos materiais; nil sem preço de algum material ou fora da tabela.
function Economy.DisenchantValue(item, prices, tbl)
    if not (item and item.level and item.quality and item.quality >= 2 and item.quality <= 4) then return nil end
    local kind = item.weapon and tbl.weapon or tbl.armor
    local b = kind and band(kind[item.quality], item.level)
    if not b then return nil end
    local total = 0
    for _, m in ipairs(b.mats) do
        local p = prices and prices[m.id]
        if not p then return nil end
        total = total + m.chance * (m.min + m.max) / 2 * p
    end
    return total
end

-- R1a: ids dos materiais da faixa do item (para buscar o preço na AH, mesmo sem preço ainda).
function Economy.MatIds(item, tbl)
    local out = {}
    if not (item and item.level and item.quality and item.quality >= 2 and item.quality <= 4) then return out end
    local kind = item.weapon and tbl.weapon or tbl.armor
    local b = kind and band(kind[item.quality], item.level)
    for _, m in ipairs(b and b.mats or {}) do out[#out + 1] = m.id end
    return out
end

-- R1b: valor da pilha.
function Economy.Value(per, count)
    if not per then return nil end
    return per * (count or 1)
end

-- R2: o que sobra do leilão depois da taxa e do depósito.
function Economy.AuctionNet(price, vendor, opts)
    if not price then return nil end
    local cut = (opts and opts.cut) or Economy.CUT
    local rate = (opts and opts.depositRate) or Economy.DEPOSIT
    return price * (1 - cut) - (vendor or 0) * rate
end

-- R4: Enchanting no nível exigido pela faixa do item.
function Economy.CanDisenchant(skill, level, tbl)
    for _, s in ipairs(tbl.skill or {}) do
        if level <= s.max then return (skill or 0) >= s.skill end
    end
    return false
end

-- R3: guardar, vendedor, leilão ou desencantar.
function Economy.BestUse(o)
    local out = { vendor = o.vendor or 0, ah = o.ah, de = o.de }
    if o.keep then out.use = "guardar"; return out end
    local margin, minGain = o.margin or Economy.MARGIN, o.minGain or Economy.MIN_GAIN
    local function beats(v) return v and v >= out.vendor * (1 + margin) and v - out.vendor >= minGain end
    local best, value
    if beats(o.ah) then best, value = "leilao", o.ah end
    if o.canDE and beats(o.de) and (not value or o.de > value) then best, value = "desencantar", o.de end
    if not best then
        if out.vendor > 0 then best, value = "vendedor", out.vendor else best, value = "guardar", 0 end
    end
    out.use, out.value = best, value
    return out
end

return Economy
