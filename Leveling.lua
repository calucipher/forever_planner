-- Leveling.lua: regras puras do guia por hub (spec 002). Sem API do jogo nem db:
-- tudo chega por parâmetro, então tudo é testável fora do jogo.
local _, ns = ...
ns = ns or {}
local Leveling = {}
ns.Leveling = Leveling

local floor, min, max, huge = math.floor, math.min, math.max, math.huge

Leveling.OVERHEAD = 20     -- segundos por quest: diálogo, aceitar, entregar
Leveling.OBJECT_SECONDS = 8
Leveling.UNKNOWN_LEG = 250 -- jardas quando a distância não é conhecida

------------------------------------------------------------------------------------------
-- XP de mob (fórmula do Classic, R2)
------------------------------------------------------------------------------------------
function Leveling.GrayLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - floor(level / 10) - 5 end
    if level <= 59 then return level - floor(level / 5) - 1 end
    return level - 9
end

local ZERO_DIFF = { { 7, 5 }, { 9, 6 }, { 11, 7 }, { 15, 8 }, { 19, 9 }, { 29, 11 }, { 39, 12 },
    { 44, 13 }, { 49, 14 }, { 54, 15 }, { 59, 16 } }
function Leveling.ZeroDiff(level)
    for _, row in ipairs(ZERO_DIFF) do
        if level <= row[1] then return row[2] end
    end
    return 17
end

-- XP por morte de um mob normal (não elite), já com o fator do Forever.
function Leveling.MobXP(playerLevel, mobLevel, factor)
    if mobLevel <= Leveling.GrayLevel(playerLevel) then return 0 end
    local base = 5 * playerLevel + 45
    local xp
    if mobLevel >= playerLevel then
        xp = base * (1 + 0.05 * min(mobLevel - playerLevel, 4))
    else
        xp = base * (1 - (playerLevel - mobLevel) / Leveling.ZeroDiff(playerLevel))
    end
    return max(xp, 0) * (factor or 1)
end

-- Média do XP por morte entre o nível mínimo e o máximo do mob.
function Leveling.MobXPRange(playerLevel, minLevel, maxLevel, factor)
    local lo, hi = minLevel, max(maxLevel or minLevel, minLevel)
    local total = 0
    for l = lo, hi do total = total + Leveling.MobXP(playerLevel, l, factor) end
    return total / (hi - lo + 1)
end

-- Rested dobra o XP de morte até acabar o rested (R4): o bônus é o menor dos dois.
function Leveling.RestedBonus(mobXP, rested)
    return max(0, min(mobXP or 0, rested or 0))
end

-- Upgrade em XP equivalente, proporcional ao XP do nível e com teto (R6).
function Leveling.UpgradeXP(delta, levelXP, perPoint, cap, circuitXP)
    if not delta or delta <= 0 then return 0 end
    return min(delta * (perPoint or 0) * (levelXP or 0), (cap or 0) * max(circuitXP or 0, 0))
end

------------------------------------------------------------------------------------------
-- Calibração (R7)
------------------------------------------------------------------------------------------
function Leveling.PushSample(list, value, limit)
    list[#list + 1] = value
    while #list > limit do table.remove(list, 1) end
end

function Leveling.Mean(list, minCount)
    if #list < (minCount or 1) then return nil end
    local total = 0
    for _, v in ipairs(list) do total = total + v end
    return total / #list
end

------------------------------------------------------------------------------------------
-- Geometria genérica (dist é injetada: jardas de mundo no jogo, plano nos testes)
------------------------------------------------------------------------------------------
local function legOf(dist, a, b)
    if not a or not b then return Leveling.UNKNOWN_LEG end
    return dist(a, b) or Leveling.UNKNOWN_LEG
end

local function nearestPoint(dist, from, points)
    local best, bestD
    for _, p in ipairs(points or {}) do
        local d = legOf(dist, from, p)
        if bestD == nil or d < bestD then best, bestD = p, d end
    end
    return best, bestD
end

-- Agrupa pontos que estejam a até `radius` um do outro (ligação simples). Devolve listas de índices.
function Leveling.Cluster(points, radius, dist)
    local parent = {}
    for i = 1, #points do parent[i] = i end
    local function root(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    for i = 1, #points do
        for j = i + 1, #points do
            local d = dist(points[i], points[j])
            if d and d <= radius then parent[root(i)] = root(j) end
        end
    end
    local groups, byRoot = {}, {}
    for i = 1, #points do
        local r = root(i)
        if not byRoot[r] then byRoot[r] = {}; groups[#groups + 1] = byRoot[r] end
        table.insert(byRoot[r], i)
    end
    return groups
end

-- Ordena paradas pelo vizinho mais próximo (R10). Cada parada tem `points`; a escolhida ganha `point`.
-- Parada com `after = {chaves}` só sai depois das paradas com essas chaves (R30).
local function blocked(s, left)
    for _, k in ipairs(s.after or {}) do
        for _, other in ipairs(left) do
            if other ~= s and other.key == k then return true end
        end
    end
    return false
end

function Leveling.NearestOrder(start, stops, dist)
    local left, ordered, cursor, legs = {}, {}, start, 0
    for i, s in ipairs(stops) do left[i] = s end
    while #left > 0 do
        local bestI, bestP, bestD = nil, nil, huge
        for i, s in ipairs(left) do
            local p, d = nearestPoint(dist, cursor, s.points)
            if p and d < bestD and not blocked(s, left) then bestI, bestP, bestD = i, p, d end
        end
        if not bestI then
            for i, st in ipairs(left) do
                local pt, d = nearestPoint(dist, cursor, st.points)
                if pt and d < bestD then bestI, bestP, bestD = i, pt, d end
            end
        end
        if not bestI then break end
        local s = table.remove(left, bestI)
        s.point = bestP
        ordered[#ordered + 1] = s
        legs = legs + bestD
        cursor = bestP
    end
    return ordered, legs, cursor
end

-- Spec 006, R13: objetivo espalhado. Ponto não visitado mais perto de `from`; com todos
-- visitados, limpa `visited` (o objeto renasce) e volta a valer o mais perto.
function Leveling.NextPoint(points, from, visited, dist)
    local best, bestD
    for _, p in ipairs(points or {}) do
        if not visited[p] then
            local d = legOf(dist, from, p)
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    if best then return best end
    for k in pairs(visited) do visited[k] = nil end
    return (nearestPoint(dist, from, points))
end

------------------------------------------------------------------------------------------
-- Seleção estilo "Dynamic Progress" (R27, R28)
------------------------------------------------------------------------------------------
-- entries: { id, value, seconds, requires = {ids}, locked }. Tira quem rende menos que
-- threshold × taxa média, salvo se for pré-requisito de quem fica (vira "cadeia") ou se
-- estiver travada (quest que já está no log, R34).
function Leveling.SelectQuests(entries, threshold)
    local totalV, totalS = 0, 0
    for _, e in ipairs(entries) do totalV = totalV + e.value; totalS = totalS + e.seconds end
    local avg = totalS > 0 and totalV / totalS or 0
    local weak = {}
    for _, e in ipairs(entries) do
        -- Spec 029, R1: `unlock` (XP que a quest destrava) entra no corte, não na média.
        local rate = e.seconds > 0 and (e.value + (e.unlock or 0)) / e.seconds or huge
        if not e.locked and rate < (threshold or 0) * avg then weak[e.id] = true end
    end
    for _, e in ipairs(entries) do
        if not weak[e.id] then
            for _, pre in ipairs(e.requires or {}) do
                if weak[pre] then weak[pre] = nil; weak["chain:" .. pre] = true end
            end
        end
    end
    local kept, dropped = {}, {}
    for _, e in ipairs(entries) do
        if weak[e.id] then
            dropped[#dropped + 1] = e
        else
            if weak["chain:" .. e.id] then e.chain = true end
            kept[#kept + 1] = e
        end
    end
    return kept, dropped
end

------------------------------------------------------------------------------------------
-- Circuito (R9–R16, R29)
------------------------------------------------------------------------------------------
-- quest = { id, state = "pegar"|"fazer"|"entregar", xp, money, delta, starters, finishers,
--           objectives = { { key, kind, kills, objects, mobXP, points, done } },
--           elite, dungeon, requires = {ids} }
-- p = { ttk, downtime, speed, threshold, levelXP, upgradePerPoint, upgradeCap, rested,
--       goldToXP, logFree }

local function pending(q)
    local out = {}
    if q.state == "entregar" then return out end
    for _, o in ipairs(q.objectives or {}) do
        if not o.done and ((o.kills or 0) > 0 or (o.objects or 0) > 0) then out[#out + 1] = o end
    end
    return out
end

-- Spec 030, R5: mob acima do jogador demora mais (+10% por nível, como o grind da spec 029).
function Leveling.KillFactor(avgLevel, playerLevel)
    if not (avgLevel and playerLevel) then return 1 end
    return 1 + 0.1 * max(0, avgLevel - playerLevel)
end

-- Spec 030, R2: objetivo com mob médio mais de 1,5 nível acima do jogador.
Leveling.MAX_MOB_ABOVE = 1.5
function Leveling.MobsTooHigh(avgLevel, playerLevel, state)
    return state ~= "entregar" and avgLevel ~= nil and playerLevel ~= nil and playerLevel ~= false
        and avgLevel > playerLevel + Leveling.MAX_MOB_ABOVE
end

-- Algum objetivo pendente com mobs altos demais (R2)? objectives = saída de Data.Objectives.
function Leveling.ObjectivesTooHigh(objectives, playerLevel, state)
    if state == "entregar" then return false end
    for _, o in ipairs(objectives or {}) do
        if not o.done and Leveling.MobsTooHigh(o.avgLevel, playerLevel, state) then return true end
    end
    return false
end

local function workSeconds(o, p)
    local factor = p.playerLevel and Leveling.KillFactor(o.avgLevel, p.playerLevel) or 1
    return (o.kills or 0) * (p.ttk + (p.downtime or 0)) * factor + (o.objects or 0) * Leveling.OBJECT_SECONDS
end

Leveling.MAX_LEVELS_ABOVE = 4 -- spec 025: quest "vermelha" demais (também o filtro de quest nova, Data.lua)

-- Spec 025, R4: quest alta demais para fazer agora (a entrega pronta não conta).
function Leveling.TooHigh(qLevel, playerLevel, state)
    return state ~= "entregar" and qLevel ~= nil and playerLevel ~= nil and playerLevel ~= false
        and qLevel > playerLevel + Leveling.MAX_LEVELS_ABOVE
end

local function asideReason(q, p)
    if q.forceAside then return q.forceAside end -- ex.: satélite com desvio grande (spec 008)
    -- Spec 025, R1: quest do log alta demais sai do circuito; a entrega pronta fica.
    if Leveling.TooHigh(q.qLevel, p.playerLevel, q.state) then return "nível alto" end
    local high -- spec 030, R3: o objetivo mais alto decide; backAt = nível em que volta
    for _, o in ipairs(pending(q)) do
        if Leveling.MobsTooHigh(o.avgLevel, p.playerLevel, q.state) then high = max(high or 0, o.avgLevel) end
    end
    if high then return "mobs altos", math.ceil(high - Leveling.MAX_MOB_ABOVE) end
    if q.elite then return "elite" end
    if q.dungeon then return "dungeon" end
    if q.state == "pegar" and #(q.starters or {}) == 0 then return "sem coordenada" end
    if #(q.finishers or {}) == 0 then return "sem coordenada" end
    for _, o in ipairs(pending(q)) do
        if #(o.points or {}) == 0 then return "sem coordenada" end
    end
    return nil
end

local function ownEstimate(q, p)
    local seconds, mobXP = Leveling.OVERHEAD + (q.extraSeconds or 0), 0 -- extra: desvio do satélite
    for _, o in ipairs(pending(q)) do
        seconds = seconds + workSeconds(o, p)
        mobXP = mobXP + (o.kills or 0) * (o.mobXP or 0)
    end
    return (q.xp or 0) + mobXP + (p.goldToXP or 0) * (q.money or 0) / 100, seconds
end

-- Limite do log (R15): só quem ainda vai ser pego ocupa espaço. Sai quem rende menos.
local function fitLog(kept, p, aside)
    local pickups = {}
    for _, e in ipairs(kept) do if e.quest.state == "pegar" then pickups[#pickups + 1] = e end end
    local excess = #pickups - (p.logFree or huge)
    if excess <= 0 then return kept end
    table.sort(pickups, function(a, b) return a.value / a.seconds < b.value / b.seconds end)
    local out = {}
    for i = 1, excess do out[pickups[i].id] = true end
    local fitted = {}
    for _, e in ipairs(kept) do
        if out[e.id] then aside[#aside + 1] = { id = e.id, reason = "log cheio" }
        else fitted[#fitted + 1] = e end
    end
    return fitted
end

local function pointKey(pt)
    return string.format("%s:%.2f:%.2f", tostring(pt.mapID or 0), pt.x or 0, pt.y or 0)
end

-- Junta numa parada só quem usa o mesmo ponto (mesmo NPC). Cada quest escolhe o ponto mais perto de `from`.
local function groupByPoint(quests, field, from, dist, kind)
    local stops, byKey = {}, {}
    for _, q in ipairs(quests) do
        local pt = nearestPoint(dist, from, q[field])
        if pt then
            local k = pointKey(pt)
            if not byKey[k] then
                byKey[k] = { kind = kind, points = { pt }, quests = {} }
                stops[#stops + 1] = byKey[k]
            end
            table.insert(byKey[k].quests, q.id)
        end
    end
    return stops
end

-- Junta objetivos com os mesmos mobs (R11): mortes = maior contagem exigida.
function Leveling.MergeObjectives(quests)
    local merged, byKey = {}, {}
    for _, q in ipairs(quests) do
        for _, o in ipairs(pending(q)) do
            local m = byKey[o.key]
            if not m then
                m = { kind = "objetivo", key = o.key, points = o.points, kills = 0, objects = 0,
                      mobXP = o.mobXP or 0, quests = {}, label = o.label, after = {} }
                byKey[o.key] = m
                merged[#merged + 1] = m
            end
            m.estimated = m.estimated or o.estimated or nil
            if o.avgLevel then m.avgLevel = max(m.avgLevel or o.avgLevel, o.avgLevel) end -- spec 030, R5
            for _, k in ipairs(o.after or {}) do m.after[#m.after + 1] = k end
            m.kills = max(m.kills, o.kills or 0)
            m.objects = max(m.objects, o.objects or 0)
            table.insert(m.quests, q.id)
        end
    end
    return merged
end

local function appendAll(dst, src) for _, v in ipairs(src) do dst[#dst + 1] = v end end

-- R13a (spec 002): requisitos de uma quest dentro do circuito. single: alternativas (basta uma);
-- group e prevInChain: obrigatórios. Alternativa já feita libera todas. Devolve requires (todas,
-- para a ordem do R13) e requiresAny (as alternativas que ainda contam).
function Leveling.CircuitRequires(single, group, prevInChain, inCircuit, done)
    local requires, any, seen = {}, {}, {}
    local function add(list, q)
        if not seen[q] then seen[q] = true; requires[#requires + 1] = q end
        if list then list[#list + 1] = q end
    end
    local freed = false
    for _, q in ipairs(single or {}) do if done[q] then freed = true end end
    if not freed then
        for _, q in ipairs(single or {}) do if inCircuit[q] then add(any, q) end end
    end
    for _, q in ipairs(group or {}) do if inCircuit[q] then add(nil, q) end end
    for _, q in ipairs(prevInChain or {}) do if inCircuit[q] then add(nil, q) end end
    return requires, any
end

-- Motivo para a quest ficar de fora por depender de quem ficou (R13a), ou nil.
local function blockedBy(q, out)
    if q.state ~= "pegar" then return nil end -- R34: quest do log não sai
    local isAny = {}
    for _, r in ipairs(q.requiresAny or {}) do isAny[r] = true end
    for _, r in ipairs(q.requires or {}) do
        if not isAny[r] and out[r] then return r end
    end
    local first
    for _, r in ipairs(q.requiresAny or {}) do
        if not out[r] then return nil end
        first = first or r
    end
    return first
end

-- R13a: quem depende de quest que ficou de fora também fica de fora, em cadeia.
-- items: lista; questOf(item) devolve a quest; out: { [id] = true } das que já ficaram de fora.
local function dropDependents(items, questOf, out, aside)
    local changed = true
    while changed do
        changed = false
        for _, it in ipairs(items) do
            local q = questOf(it)
            local pre = not out[q.id] and blockedBy(q, out)
            if pre then
                out[q.id], changed = true, true
                aside[#aside + 1] = { id = q.id, reason = "depende de " .. pre }
            end
        end
    end
    local left = {}
    for _, it in ipairs(items) do if not out[questOf(it).id] then left[#left + 1] = it end end
    return left
end

local function itself(q) return q end
local function questOfEntry(e) return e.quest end

function Leveling.BuildCircuit(quests, start, p, dist)
    local aside, candidates, out = {}, {}, {}
    for _, q in ipairs(quests) do
        local why, backAt = asideReason(q, p)
        if why then aside[#aside + 1] = { id = q.id, reason = why, backAt = backAt }; out[q.id] = true
        else candidates[#candidates + 1] = q end
    end
    candidates = dropDependents(candidates, itself, out, aside)
    local byId = {}
    for _, q in ipairs(candidates) do byId[q.id] = q end

    local entries = {}
    for _, q in ipairs(candidates) do
        local value, seconds = ownEstimate(q, p)
        entries[#entries + 1] = { id = q.id, value = value, seconds = seconds, requires = q.requires, quest = q,
            locked = q.state ~= "pegar" or q.bag } -- R34: o que já está no log não sai; spec 010: bolsa
    end
    local kept, dropped = Leveling.SelectQuests(entries, p.threshold or 0)
    for _, e in ipairs(dropped) do aside[#aside + 1] = { id = e.id, reason = "abaixo do limiar" } end
    for _, e in ipairs(dropped) do out[e.id] = true end
    -- R13a + R15: refaz o corte do log sem quem saiu por depender, até não mudar.
    local pool = kept
    while true do
        local logAside, trialOut = {}, {}
        for k in pairs(out) do trialOut[k] = true end
        local fitted = fitLog(pool, p, logAside)
        local fittedIds = {}
        for _, e in ipairs(fitted) do fittedIds[e.id] = true end
        for _, e in ipairs(pool) do if not fittedIds[e.id] then trialOut[e.id] = true end end
        local depAside = {}
        local left = dropDependents(fitted, questOfEntry, trialOut, depAside)
        if #depAside == 0 then
            appendAll(aside, logAside)
            kept = left
            break
        end
        appendAll(aside, depAside)
        local gone = {}
        for _, a in ipairs(depAside) do gone[a.id] = true; out[a.id] = true end
        local nextPool = {}
        for _, e in ipairs(pool) do if not gone[e.id] then nextPool[#nextPool + 1] = e end end
        pool = nextPool
    end
    -- R13a + R28: quem ficou só por cadeia e perdeu o dependente volta a ser "abaixo do limiar".
    -- Repete até não mudar: numa cadeia de vários elos, tirar um elo pode soltar o anterior.
    repeat
        local needed = {}
        for _, e in ipairs(kept) do for _, r in ipairs(e.quest.requires or {}) do needed[r] = true end end
        local final = {}
        for _, e in ipairs(kept) do
            if e.chain and not needed[e.id] then aside[#aside + 1] = { id = e.id, reason = "abaixo do limiar" }
            else final[#final + 1] = e end
        end
        local changed = #final < #kept
        kept = final
    until not changed

    -- Rodada 2: quem depende de uma quest do próprio circuito entra depois da entrega dela (R13).
    local inCircuit = {}
    for _, e in ipairs(kept) do inCircuit[e.id] = true end
    local rounds = { {}, {} }
    for _, e in ipairs(kept) do
        local second = false
        for _, pre in ipairs(e.quest.requires or {}) do if inCircuit[pre] and byId[pre] then second = true end end
        table.insert(rounds[second and 2 or 1], e.quest)
    end

    local stops, legs, cursor = {}, 0, start
    local merged = {}
    for ri, round in ipairs(rounds) do
        if #round > 0 then
            -- R8 (spec 006, revisto): rota única. A próxima parada é a mais perto entre as
            -- liberadas: objetivo depois da coleta da quest; entrega depois dos objetivos;
            -- entrega pronta livre desde o início (no mesmo NPC, antes de pegar).
            local pick, ready, later = {}, {}, {}
            for _, q in ipairs(round) do
                if q.state == "pegar" then pick[#pick + 1] = q end
                if q.state == "entregar" then ready[#ready + 1] = q else later[#later + 1] = q end
            end
            local readyStops = groupByPoint(ready, "finishers", cursor, dist, "entregar")
            local pickStops = groupByPoint(pick, "starters", cursor, dist, "pegar")
            local laterStops = groupByPoint(later, "finishers", cursor, dist, "entregar")
            local objs = Leveling.MergeObjectives(round)
            appendAll(merged, objs)

            local pickKey, objKeys = {}, {}
            for _, st in ipairs(readyStops) do st.key = "entregar-pronta:" .. pointKey(st.points[1]) end
            for _, st in ipairs(pickStops) do
                st.key = "pegar:" .. pointKey(st.points[1])
                for _, q in ipairs(st.quests) do pickKey[q] = st.key end
            end
            for _, m in ipairs(objs) do
                for _, q in ipairs(m.quests) do
                    if pickKey[q] then m.after[#m.after + 1] = pickKey[q] end
                    objKeys[q] = objKeys[q] or {}
                    table.insert(objKeys[q], m.key)
                end
            end
            for _, st in ipairs(laterStops) do
                st.key = "entregar:" .. pointKey(st.points[1])
                st.after = {}
                for _, q in ipairs(st.quests) do
                    if pickKey[q] then st.after[#st.after + 1] = pickKey[q] end
                    for _, k in ipairs(objKeys[q] or {}) do st.after[#st.after + 1] = k end
                end
            end

            local all = {}
            appendAll(all, readyStops) -- vêm primeiro: no empate (mesmo NPC), entregar antes de pegar
            appendAll(all, pickStops)
            appendAll(all, objs)
            appendAll(all, laterStops)
            local ordered, l, c = Leveling.NearestOrder(cursor, all, dist)
            for _, st in ipairs(ordered) do st.round = ri end -- spec 006, R16
            appendAll(stops, ordered); legs, cursor = legs + l, c
        end
    end

    local seconds, mobXP, xp, money, delta = Leveling.OVERHEAD * #kept + legs / (p.speed or 7), 0, 0, 0, 0
    for _, m in ipairs(merged) do
        seconds = seconds + workSeconds(m, p)
        mobXP = mobXP + m.kills * m.mobXP
    end
    for _, e in ipairs(kept) do
        xp = xp + (e.quest.xp or 0)
        money = money + (e.quest.money or 0)
        if (e.quest.delta or 0) > 0 then delta = delta + e.quest.delta end
    end
    local rested = Leveling.RestedBonus(mobXP, p.rested)
    local base = xp + mobXP + rested
    local upgradeXP = Leveling.UpgradeXP(delta, p.levelXP, p.upgradePerPoint, p.upgradeCap, base)
    local value = base + (p.goldToXP or 0) * money / 100 + upgradeXP

    local keptQuests, estimates = {}, {}
    for _, e in ipairs(kept) do keptQuests[#keptQuests + 1] = { id = e.id, chain = e.chain, state = e.quest.state } end
    for _, e in ipairs(entries) do estimates[e.id] = { value = e.value, seconds = e.seconds } end
    return {
        stops = stops, kept = keptQuests, aside = aside, legs = legs, estimates = estimates,
        seconds = seconds, xp = xp, mobXP = mobXP, restedXP = rested, upgradeXP = upgradeXP, money = money,
        value = value, rate = seconds > 0 and value / seconds * 3600 or 0,
    }
end

------------------------------------------------------------------------------------------
-- Escolha de hub (spec 006, R6 e R7)
------------------------------------------------------------------------------------------
-- hubs = { { key, ready = entregas prontas, quests = quests no circuito, rate = XP/h, dist = jardas } }
-- mode: "turnin" (mais perto com entrega pronta), "best" (maior taxa com piso de 2 quests),
-- "next" (turnin; se não houver, best).
local MIN_QUESTS = 2
function Leveling.PickHub(hubs, mode)
    if mode ~= "best" then
        local best, bestD
        for _, h in ipairs(hubs) do
            if (h.ready or 0) > 0 and (not bestD or (h.dist or huge) < bestD) then best, bestD = h, h.dist or huge end
        end
        if best or mode == "turnin" then return best and best.key end
    end
    local best, fallback
    for _, h in ipairs(hubs) do
        if (h.quests or 0) >= MIN_QUESTS and (not best or h.rate > best.rate) then best = h end
        if (h.quests or 0) > 0 and (not fallback or h.rate > fallback.rate) then fallback = h end
    end
    best = best or fallback
    return best and best.key
end

------------------------------------------------------------------------------------------
-- Limpeza do log (spec 006, R10 e R11)
------------------------------------------------------------------------------------------
Leveling.NEW_QUEST_ID = 80000 -- heurística: quests que não existiam no Classic original
Leveling.CHAIN_XP_FACTOR = 1.5

-- item = { id, classQuest, chainUpgrade, chainXP, medianXP }
function Leveling.Protected(item)
    if item.classQuest or item.chainUpgrade or item.bagReward then return true end -- bagReward: spec 010
    if (item.id or 0) >= Leveling.NEW_QUEST_ID then return true end
    if item.chainXP and item.medianXP and item.medianXP > 0
        and item.chainXP >= Leveling.CHAIN_XP_FACTOR * item.medianXP then return true end
    return false
end

-- items = { { id, incomplete, rate, hubRate, gray, ... } } → { { id, reason } } na mesma ordem.
function Leveling.CleanupCandidates(items, threshold)
    local out = {}
    for _, it in ipairs(items) do
        if it.incomplete and not Leveling.Protected(it) then
            local weak = (it.hubRate or 0) > 0 and (it.rate or 0) < (threshold or 0) * it.hubRate
            if it.gray or weak then out[#out + 1] = { id = it.id, reason = it.gray and "cinza" or "rende pouco" } end
        end
    end
    return out
end

return Leveling
