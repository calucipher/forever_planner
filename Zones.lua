-- Zones.lua: regras puras da sugestão de zona (spec 029). Sem API do jogo nem db: tudo chega
-- por parâmetro. A mesma regra roda em tools/pesquisa_zonas.lua (R23).
local _, ns = ...
ns = ns or {}
local Zones = {}
ns.Zones = Zones

local floor, min = math.floor, math.min

-- XP para passar de nível no Classic (1->2 ... 59->60), igual no Forever.
Zones.LEVEL_XP = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900,
    14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400,
    44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000,
    106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900,
    180800, 187900, 195000, 202300, 209800 }
function Zones.LevelXP(level) return Zones.LEVEL_XP[level] end

local function fmt(n) return ns.Util and ns.Util.FormatInt(floor((n or 0) + 0.5)) or tostring(floor(n or 0)) end

------------------------------------------------------------------------------------------
-- Mobs (R7, R15)
------------------------------------------------------------------------------------------
-- Máscara de inimigos do faction template: 1 jogadores, 2 Aliança, 4 Horda, 8 monstros.
-- Hostil se ataca jogador ou Horda; 0 (neutro) e template desconhecido contam como atacável.
function Zones.Hostile(enemyMask)
    if enemyMask == nil or enemyMask == 0 then return true end
    return enemyMask % 2 == 1 or floor(enemyMask / 4) % 2 == 1
end

function Zones.IsHelperName(name, patterns)
    patterns = patterns or (ns.ZoneContent and ns.ZoneContent.helperNames) or {}
    for _, pat in ipairs(patterns) do
        if (name or ""):find(pat) then return true end
    end
    return false
end

-- XP/h de grind no nível L. hist = { [nível] = spawns } de mobs normais.
-- p = { perKill, factor, minSpawns }. Devolve XP/h e spawns contados.
function Zones.GrindRate(hist, L, p)
    local spawns, xp, secs = 0, 0, 0
    for l, s in pairs(hist or {}) do
        local x = ns.Leveling.MobXP(L, l, p.factor or 1)
        local inRange = l <= L + 2
        if p.easy then inRange = l >= L - 4 and l <= L - 2 end -- spec 063, R3: modo fácil
        if x > 0 and inRange then
            spawns = spawns + s
            xp = xp + x * s
            secs = secs + s * p.perKill * ns.Leveling.KillFactor(l, L) -- spec 063, R1
        end
    end
    if spawns < (p.minSpawns or 0) or secs <= 0 then return 0, spawns end
    return xp / secs * 3600, spawns
end

-- Zona de grind (R15). rates = { { zone, rate } }; troca a zona atual por outra só se ela
-- render mais que (1 + margin) vezes a atual. Devolve { zone, rate } com a taxa da própria zona.
function Zones.PickGrind(rates, here, margin)
    local best, cur
    for _, r in ipairs(rates or {}) do
        if r.rate > 0 and (not best or r.rate > best.rate) then best = r end
        if r.zone == here then cur = r end
    end
    if cur and cur.rate > 0 and (not best or best.rate <= cur.rate * (1 + (margin or 0))) then
        return { zone = cur.zone, rate = cur.rate }
    end
    if best then return { zone = best.zone, rate = best.rate } end
    return { zone = here, rate = 0 }
end

------------------------------------------------------------------------------------------
-- Quests (R2, R9, R10, R12)
------------------------------------------------------------------------------------------
-- XP que q destrava na zona: filhos solo, não feitos, de nível até L+4, sem repetir.
-- g = { children = { [q] = {filhos} }, info = { [q] = { zone, solo, level, xp } } }.
-- seen é opcional: passado entre chamadas, a soma de várias quests não conta duas vezes.
function Zones.ChainAhead(q, g, zone, L, done, seen, stack)
    seen, stack = seen or {}, stack or {}
    if stack[q] then return 0 end
    stack[q] = true
    seen[q] = true -- a própria quest não é XP destravado (nem num laço)
    local total = 0
    for _, c in ipairs(g.children[q] or {}) do
        local ci = g.info[c]
        if ci and ci.solo and ci.zone == zone and not (done and done[c]) and not seen[c] and ci.level <= L + 4 then
            seen[c] = true
            total = total + (ci.xp or 0) + Zones.ChainAhead(c, g, zone, L, done, seen, stack)
        end
    end
    stack[q] = nil
    return total
end

-- Tempo de uma quest. o = { kills, objects, far, unknownWork };
-- p = { overhead, legYards, speed, perKill, objectSeconds, farDelivery, unknownKills }.
-- Devolve segundos e as kills usadas (quest sem objetivo na base vale unknownKills, R9).
function Zones.QuestSeconds(o, p)
    local kills = o.kills or 0
    if o.unknownWork then kills = p.unknownKills or 0 end
    local s = (p.overhead or 0) + (p.legYards or 0) / (p.speed or 7) + kills * (p.perKill or 0)
        + (o.objects or 0) * (p.objectSeconds or 0) + (o.far and (p.farDelivery or 0) or 0)
    return s, kills
end

-- Oferta de uma zona. entries = { id, value, seconds, unlock, requires }; a seleção é a do guia
-- com unlock (R1). aheadOf(id, seen), opcional, dá o XP destravado com visitados em comum.
function Zones.Offer(entries, threshold, aheadOf)
    local kept = ns.Leveling.SelectQuests(entries, threshold or 0)
    local value, seconds, unlock, seen = 0, 0, 0, {}
    for _, e in ipairs(kept) do
        value, seconds = value + e.value, seconds + e.seconds
        unlock = unlock + (aheadOf and aheadOf(e.id, seen) or e.unlock or 0)
    end
    return { kept = kept, n = #kept, value = value, seconds = seconds, unlock = unlock,
        rate = seconds > 0 and value / seconds * 3600 or 0 }
end

------------------------------------------------------------------------------------------
-- Decisão (R13, R14, R16)
------------------------------------------------------------------------------------------
-- XP/h de uma zona candidata: raw conta a cadeia e a viagem; eff pondera pelo XP disponível.
function Zones.Effective(offer, travel, potential, levelXP, minVisit)
    local value = offer.value or 0
    if value <= 0 then return 0, 0 end
    local full = value + (offer.unlock or 0)
    local raw = full / ((offer.seconds or 0) * full / value + (travel or 0)) * 3600
    local need = (minVisit or 0) * (levelXP or 0)
    local eff = need > 0 and raw * min(1, (potential or full) / need) or raw
    return raw, eff
end

function Zones.Travel(fromZone, toZone, fromCont, toCont, p)
    if fromZone == toZone then return 0 end
    if fromCont ~= nil and fromCont == toCont then return p.travelSame end
    return p.travelOther
end

-- cur = { zone, rate, n }; cands = { { zone, raw, eff } } (outras zonas); grind = { zone, rate };
-- p = { stay }. Devolve { action = "stay" | "go" | "grind", zone, reason }.
function Zones.Decide(cur, cands, grind, p)
    local best
    for _, c in ipairs(cands or {}) do
        if c.zone ~= cur.zone and (not best or c.eff > best.eff) then best = c end
    end
    if (cur.n or 0) > 0 and (not best or cur.rate >= (p.stay or 0) * best.eff) then
        return { action = "stay", zone = cur.zone, reason = ("a zona ainda rende %s XP/h"):format(fmt(cur.rate)) }
    end
    local grindRate = grind and grind.rate or 0
    if best and best.raw >= grindRate then
        local why = (cur.n or 0) == 0 and "acabaram as quests do nível"
            or ("rende mais: %s contra %s XP/h"):format(fmt(best.eff), fmt(cur.rate))
        return { action = "go", zone = best.zone, reason = why }
    end
    local why = best and ("grind rende mais que viajar (%s contra %s XP/h)"):format(fmt(grindRate), fmt(best.raw))
        or "nenhuma quest disponível"
    return { action = "grind", zone = grind and grind.zone, reason = why }
end

------------------------------------------------------------------------------------------
-- Faixa de nível da zona (spec 032)
------------------------------------------------------------------------------------------
Zones.RANGE_MIN_SPAWNS = 100
local RANGE_TAIL = 0.10 -- peso cortado em cada ponta

-- Menor e maior nível em que o peso acumulado de cada ponta passa de 10% do total.
local function trimmedRange(hist)
    local levels, total = {}, 0
    for l, w in pairs(hist or {}) do
        if w > 0 then levels[#levels + 1] = l; total = total + w end
    end
    if total <= 0 then return nil, nil, 0 end
    table.sort(levels)
    local cut = total * RANGE_TAIL
    local lo, hi, acc = levels[1], levels[#levels], 0
    for _, l in ipairs(levels) do
        acc = acc + hist[l]
        if acc > cut then lo = l; break end
    end
    acc = 0
    for i = #levels, 1, -1 do
        acc = acc + hist[levels[i]]
        if acc > cut then hi = levels[i]; break end
    end
    return lo, hi, total
end

-- R1: faixa pelos mobs; com menos de minSpawns spawns, pelas quests.
function Zones.LevelRange(hist, questLevels, minSpawns)
    local lo, hi, total = trimmedRange(hist)
    if lo and total >= (minSpawns or Zones.RANGE_MIN_SPAWNS) then return lo, hi, "mobs" end
    lo, hi = trimmedRange(questLevels)
    if lo then return lo, hi, "quests" end
    return nil
end

-- R2: cor da faixa para o nível L.
function Zones.LevelColor(lo, hi, L)
    if ns.Leveling.MobXP(L, hi, 1) <= 0 then return "gray" end
    if lo > L + 1 then return "red" end
    if L <= hi then return "yellow" end
    return "green"
end

-- R3: texto da faixa.
function Zones.FormatRange(lo, hi)
    if lo == hi then return tostring(lo) end
    return lo .. "–" .. hi
end

local RANGE_COLORS = { red = "FF1919", yellow = "FFD100", green = "40C040", gray = "808080" }
function Zones.RangeLabel(lo, hi, L)
    return ("|cFF%sníveis %s (est.)|r"):format(RANGE_COLORS[Zones.LevelColor(lo, hi, L)], Zones.FormatRange(lo, hi))
end

-- Spec 035, R6: zonas vizinhas (divisa a pé), simétrico. neighbors = { [zona] = { vizinhas } }.
function Zones.Neighbors(zone, neighbors)
    local out, seen = {}, {}
    local function add(z) if z ~= zone and not seen[z] then seen[z] = true; out[#out + 1] = z end end
    for _, z in ipairs(neighbors[zone] or {}) do add(z) end
    for other, list in pairs(neighbors) do
        for _, z in ipairs(list) do if z == zone then add(other) end end
    end
    table.sort(out)
    return out
end

-- Spec 035, R9: viagens que valem. cands = { { zone, eff, levels, ... } }; nearRate = melhor hub perto.
-- "better" com a mesma margem da 029 (zoneStay): rende mais que o perto dividido pela margem.
function Zones.WorthTrip(cands, nearRate, p)
    local ok = {}
    for _, c in ipairs(cands or {}) do
        if (c.levels or 0) >= p.zoneMinVisit then ok[#ok + 1] = c end
    end
    table.sort(ok, function(a, b) return a.eff > b.eff end)
    local out = {}
    for i = 1, math.min(p.tripMax or 2, #ok) do
        local c = {}
        for k, v in pairs(ok[i]) do c[k] = v end -- cópia: não altera a candidata recebida
        c.better = c.eff * p.zoneStay > (nearRate or 0)
        out[#out + 1] = c
    end
    return out
end

------------------------------------------------------------------------------------------
-- Trilha por faixa de nível (spec 047)
------------------------------------------------------------------------------------------
-- R1: faixa de 10 em 10 (1–10, 11–20, ..., 51–60) que contém L.
function Zones.Bracket(L)
    local lo = math.floor((math.max(L or 1, 1) - 1) / 10) * 10 + 1
    lo = math.min(lo, 51)
    return lo, lo + 9
end

-- R2: etapas da faixa. zones = { { zone, lo, hi, quests, travel } }. Entra a zona que cruza a faixa
-- com pelo menos opts.minQuests quests; etapa = zonas com mínimo a até opts.alt níveis do mínimo da
-- primeira; dentro da etapa, a de menor viagem primeiro (sem viagem, no fim) e as outras são alternativas.
function Zones.Trail(zones, lo, hi, opts)
    local minQuests, alt = (opts and opts.minQuests) or 8, (opts and opts.alt) or 3
    local inside = {}
    for _, z in ipairs(zones or {}) do
        if z.lo and z.hi and z.lo <= hi and z.hi >= lo and (z.quests or 0) >= minQuests then inside[#inside + 1] = z end
    end
    table.sort(inside, function(a, b)
        if a.lo ~= b.lo then return a.lo < b.lo end
        return tostring(a.zone) < tostring(b.zone)
    end)
    local steps, cur = {}, nil
    for _, z in ipairs(inside) do
        if not cur or z.lo - cur.lo > alt then
            cur = { lo = z.lo, zones = {} }
            steps[#steps + 1] = cur
        end
        cur.zones[#cur.zones + 1] = z
    end
    local huge = math.huge
    for _, st in ipairs(steps) do
        table.sort(st.zones, function(a, b)
            local ta, tb = a.travel or huge, b.travel or huge
            if ta ~= tb then return ta < tb end
            return a.lo < b.lo
        end)
    end
    return steps
end

return Zones
