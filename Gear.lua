-- Gear.lua: conselho de gear pelo nível (spec 048). Núcleo puro: recebe os candidatos prontos
-- (o adaptador é GearGuide.lua) e não chama a API do jogo.
local _, ns = ...
local Gear = {}
ns.Gear = Gear

-- R3: custo em segundos por fonte (estimativa). Masmorra = DUNGEON_STEP_SECONDS da spec 039.
Gear.COST = { quest = 600, cadeia = 600, masmorra = 900, vendedor = 300, ah = 300 }
Gear.AHEAD = 3

function Gear.Cost(source, steps)
    local base = Gear.COST[source] or Gear.COST.quest
    if source == "cadeia" then return base * math.max(steps or 1, 1) end
    return base
end

local function score(c) return c.delta / math.max(c.cost or 1, 1) end

-- R3: por slot, o maior delta/custo entre os que dão upgrade e cabem até L + ahead.
-- Devolve { slot, item, delta, ..., alts = {até 2}, later = reqLevel se > L }, na ordem do score.
function Gear.Advice(cands, L, opts)
    local ahead = (opts and opts.ahead) or Gear.AHEAD
    local bySlot = {}
    for _, c in ipairs(cands or {}) do
        if (c.delta or 0) > 0 and (c.reqLevel or 0) <= L + ahead and c.slot then
            bySlot[c.slot] = bySlot[c.slot] or {}
            table.insert(bySlot[c.slot], c)
        end
    end
    local out = {}
    for slot, list in pairs(bySlot) do
        table.sort(list, function(a, b)
            local sa, sb = score(a), score(b)
            if sa ~= sb then return sa > sb end
            return (a.item or 0) < (b.item or 0)
        end)
        local best = {}
        for k, v in pairs(list[1]) do best[k] = v end
        best.slot = slot
        best.alts = {}
        for i = 2, #list do -- o mesmo item por outra fonte (quest e AH) não é alternativa dele mesmo
            if list[i].item ~= best.item and #best.alts < 2 then best.alts[#best.alts + 1] = list[i] end
        end
        best.later = (best.reqLevel or 0) > L and best.reqLevel or nil
        out[#out + 1] = best
    end
    table.sort(out, function(a, b)
        local sa, sb = score(a), score(b)
        if sa ~= sb then return sa > sb end
        return tostring(a.slot) < tostring(b.slot)
    end)
    return out
end

return Gear
