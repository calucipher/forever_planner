-- Leveling.lua: regras puras do guia por hub (spec 002). Sem API do jogo nem db:
-- tudo chega por parâmetro, então tudo é testável fora do jogo.
local _, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, k) return k end }) -- spec 066 (o arquivo também roda sozinho)
local K = ns and ns.Locale and ns.Locale.K or function(s) return s end -- spec 066
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

-- Spec 053, R2 (parecer 053-056): a inversão de i..j só muda a ordem dentro do trecho; confere só ele.
local function segmentOk(list, i, j)
    local pos
    for k = i, j do
        local s = list[k]
        if s.after and s.after[1] then
            if not pos then
                pos = {}
                for m = i, j do if list[m].key then pos[list[m].key] = m end end
            end
            for _, key in ipairs(s.after) do
                if pos[key] and pos[key] > k then return false end
            end
        end
    end
    return true
end

local function reverse(list, i, j)
    while i < j do list[i], list[j] = list[j], list[i]; i, j = i + 1, j - 1 end
end

-- Spec 053, R1: 2-opt na rota aberta que começa em start; cada parada já tem `point`.
local UNTANGLE_PASSES = 20
function Leveling.Untangle(start, stops, dist)
    local route = {}
    for i, s in ipairs(stops) do route[i] = s end
    local n = #route
    local function d(a, b) return (a and b) and legOf(dist, a, b) or 0 end
    for _ = 1, (n >= 2) and UNTANGLE_PASSES or 0 do
        local improved = false
        for i = 1, n - 1 do
            for j = i + 1, n do
                local a = i == 1 and start or route[i - 1].point
                local b, c = route[i].point, route[j].point
                local e = route[j + 1] and route[j + 1].point
                if d(a, c) + d(b, e) < d(a, b) + d(c, e) - 1e-6 then
                    reverse(route, i, j)
                    if segmentOk(route, i, j) then improved = true else reverse(route, i, j) end
                end
            end
        end
        if not improved then break end
    end
    local legs, cursor = 0, start
    for _, s in ipairs(route) do
        legs = legs + d(cursor, s.point)
        cursor = s.point
    end
    return route, legs, cursor
end

-- Spec 068, R7: mudar uma parada de lugar (or-opt). O 2-opt só inverte trechos e não tira do
-- caminho uma parada isolada deixada para o fim (pegar longe, depois voltar). A ordem continua
-- valendo: a parada só vai para depois das que ela espera (`after`) e antes das que esperam por ela.
local RELOCATE_PASSES = 10
local function orderOk(route)
    local pos = {}
    for i, s in ipairs(route) do if s.key then pos[s.key] = i end end
    for i, s in ipairs(route) do
        for _, k in ipairs(s.after or {}) do
            if pos[k] and pos[k] > i then return false end
        end
    end
    return true
end
function Leveling.Relocate(start, stops, dist)
    local route = {}
    for i, s in ipairs(stops) do route[i] = s end
    local n = #route
    local function d(a, b) return (a and b) and legOf(dist, a, b) or 0 end
    for _ = 1, (n >= 3) and RELOCATE_PASSES or 0 do
        local improved = false
        for i = 1, n do
            local s = route[i]
            local prev = i > 1 and route[i - 1].point or start
            local nxt = route[i + 1] and route[i + 1].point
            local removeGain = d(prev, s.point) + d(s.point, nxt) - d(prev, nxt)
            local rest = {}
            for k, x in ipairs(route) do if k ~= i then rest[#rest + 1] = x end end
            local bestK, bestGain = nil, 1e-6
            for k = 0, #rest do -- depois de rest[k] (k = 0: no começo)
                if k ~= i - 1 then
                    local a = k > 0 and rest[k].point or start
                    local b = rest[k + 1] and rest[k + 1].point
                    local gain = removeGain - (d(a, s.point) + d(s.point, b) - d(a, b))
                    if gain > bestGain then
                        table.insert(rest, k + 1, s)
                        if orderOk(rest) then bestK, bestGain = k, gain end
                        table.remove(rest, k + 1)
                    end
                end
            end
            if bestK then
                table.insert(rest, bestK + 1, s)
                route = rest
                improved = true
            end
        end
        if not improved then break end
    end
    local legs, cursor = 0, start
    for _, s in ipairs(route) do
        legs = legs + d(cursor, s.point)
        cursor = s.point
    end
    return route, legs, cursor
end

-- Spec 053, R4: paradas de `extras` com desvio curto entre as paradas, a mais barata primeiro.
function Leveling.OnTheWay(stops, extras, maxDetour, dist, anchor)
    local out, left, added, total = stops, {}, {}, 0
    for i, x in ipairs(extras or {}) do left[i] = x end
    -- R4b: desvio de x entre a e b (a ou b nil = ponta), só com distâncias conhecidas e não negativo.
    local function detour(a, x, b)
        local ax = a and dist(a, x)
        local xb = b and dist(x, b)
        local ab = a and b and dist(a, b)
        if (a and not ax) or (b and not xb) or (a and b and not ab) then return nil end
        local c = (ax or 0) + (xb or 0) - (ab or 0)
        if c < -1 then return nil end
        return math.max(c, 0)
    end
    while #left > 0 do
        local bestI, bestIdx, bestCost
        for i, x in ipairs(left) do
            for idx = 1, #out + 1 do
                local a = out[idx - 1] and out[idx - 1].point or (idx == 1 and anchor or nil)
                local b = out[idx] and out[idx].point
                if (idx > 1 or anchor) and (a or b) then -- R4: antes da primeira só com o ponto fixo
                    local c = detour(a, x.point, b)
                    if c and c <= maxDetour and (not bestCost or c < bestCost) then bestI, bestIdx, bestCost = i, idx, c end
                end
            end
        end
        if not bestI then break end
        local x = table.remove(left, bestI)
        x.round = (out[bestIdx - 1] or out[bestIdx] or {}).round
        local o = {}
        for k, s in ipairs(out) do
            if k == bestIdx then o[#o + 1] = x end
            o[#o + 1] = s
        end
        if bestIdx > #out then o[#o + 1] = x end
        added[#added + 1] = { stop = x, cost = bestCost }
        out, total = o, total + bestCost
    end
    if out == stops then -- R4: a lista recebida não muda
        out = {}
        for i, s in ipairs(stops) do out[i] = s end
    end
    return out, added, total
end

-- Spec 045, R1: põe `extra` onde soma menos caminho entre as paradas (não a partir do jogador, para
-- não entrar e sair andando). Devolve lista nova e o custo, ou nil acima de maxDetour.
function Leveling.InsertDetour(stops, extra, dist, maxDetour)
    if #stops == 0 then return nil end
    local x = extra.point
    local bestI, bestCost
    for i = 1, #stops do
        local a, b = stops[i].point, stops[i + 1] and stops[i + 1].point
        local cost = legOf(dist, a, x) + (b and (legOf(dist, x, b) - legOf(dist, a, b)) or 0)
        if not bestCost or cost < bestCost then bestI, bestCost = i, cost end
    end
    if bestCost > maxDetour then return nil end
    local out = {}
    for i, s in ipairs(stops) do
        out[#out + 1] = s
        if i == bestI then
            extra.round = s.round
            out[#out + 1] = extra
        end
    end
    return out, bestCost
end

-- Spec 045, R2c: põe `extra` na posição idx (antes da parada idx). Devolve lista nova e o custo do
-- desvio: d(anterior, x) + d(x, seguinte) − d(anterior, seguinte); sem anterior, d(x, seguinte).
function Leveling.InsertAt(stops, extra, idx, dist)
    local prev, nxt = stops[idx - 1], stops[idx]
    local x = extra.point
    local cost
    if prev and nxt then
        cost = legOf(dist, prev.point, x) + legOf(dist, x, nxt.point) - legOf(dist, prev.point, nxt.point)
    elseif nxt then cost = legOf(dist, x, nxt.point)
    elseif prev then cost = legOf(dist, prev.point, x)
    else cost = 0 end
    extra.round = (prev or nxt or {}).round
    local out = {}
    for i, s in ipairs(stops) do
        if i == idx then out[#out + 1] = extra end
        out[#out + 1] = s
    end
    if idx > #stops then out[#out + 1] = extra end
    return out, cost
end

-- Spec 045, R2b (revista): jardas a pé economizadas nas pernas { {a, b} } saindo voando de `node`
-- até o conhecido mais perto de b, quando o voo passa pela regra da seta (spec 024, R1 com a emenda:
-- trecho a pé até walkShare do caminho e tempo até o a pé + margin). opts = { run, fly, factor,
-- overhead, margin, walkShare }.
function Leveling.FlightSaving(legs, node, known, dist, opts)
    local total, share = 0, opts.walkShare or 0.75
    for _, leg in ipairs(legs or {}) do
        local a, b = leg[1], leg[2]
        local k, kd
        for _, n in ipairs(known or {}) do
            local d = legOf(dist, n, b)
            if not kd or d < kd then k, kd = n, d end
        end
        if k then
            local direct = legOf(dist, a, b)
            local onFoot = legOf(dist, a, node) + kd
            local flyTime = onFoot / opts.run + opts.overhead + legOf(dist, node, k) * opts.factor / opts.fly
            if onFoot <= share * direct and flyTime <= direct / opts.run + (opts.margin or 0) then
                total = total + (direct - onFoot)
            end
        end
    end
    return total
end

-- Spec 052: regra única das paradas "abrir ponto de voo", para a viagem toda a partir do jogador.
-- Devolve a lista nova, as paradas que entraram ({ node, cost, why }) e o desvio total (jardas).
-- Um ponto por nó durante a conta (o cache de posição do Planner usa a tabela como chave); a
-- entrada não muda (parecer 050-052).
local function flightPoint(p, cache)
    cache[p] = cache[p] or { mapID = p.mapID, x = p.x, y = p.y, zone = p.zone, source = "taxi" .. tostring(p.id) }
    return cache[p]
end
local function flightStop(p, cache)
    local pt = flightPoint(p, cache)
    return { kind = "voo", key = "voo:" .. tostring(p.id), point = pt, points = { pt }, quests = {}, label = p.name }
end

-- R3–R6: melhor posição de um ponto; nil se nenhuma vale.
local function bestSpot(start, stops, p, ctx, exitIdx, cache)
    local dist, x = ctx.dist, flightPoint(p, cache)
    local mine = ctx.here ~= nil and p.zone == ctx.here
    local last = #stops + 1
    if mine and exitIdx then last = exitIdx end -- R5: abre antes de sair da zona
    local best
    for idx = 1, last do
        local prev = idx == 1 and start or (stops[idx - 1] and stops[idx - 1].point)
        local nxt = stops[idx] and stops[idx].point
        local cost
        if prev and nxt then cost = legOf(dist, prev, x) + legOf(dist, x, nxt) - legOf(dist, prev, nxt)
        elseif nxt then cost = legOf(dist, x, nxt)
        elseif prev then cost = legOf(dist, prev, x)
        else cost = 0 end
        if not best or cost < best.cost then
            local why
            if cost <= ctx.maxDetour then why = "caminho"
            elseif mine and exitIdx and cost <= ctx.zoneMax then why = "zona"
            else
                local legs, from = {}, x
                for k = idx, #stops do legs[#legs + 1] = { from, stops[k].point }; from = stops[k].point end
                if cost < Leveling.FlightSaving(legs, x, ctx.known, dist, ctx.fopts) then why = "economiza" end
            end
            if why then best = { idx = idx, cost = cost, why = why } end
        end
    end
    return best
end

function Leveling.FlightStops(start, stops, red, ctx)
    local zones = {}
    if ctx.here ~= nil then zones[ctx.here] = true end
    for _, s in ipairs(stops) do
        local z = s.point and ctx.zoneOf(s.point)
        if z ~= nil then zones[z] = true end
    end
    local left = {}
    for _, p in ipairs(red or {}) do -- R2
        if p.zone ~= nil and zones[p.zone] then left[#left + 1] = p end
    end
    local out = {}
    for i, s in ipairs(stops) do out[i] = s end
    local added, total, cache = {}, 0, {}
    while #left > 0 do
        local exitIdx
        if ctx.here ~= nil then
            for i, s in ipairs(out) do
                local z = s.point and (s.kind == "voo" and s.point.zone or ctx.zoneOf(s.point))
                if z ~= nil and z ~= ctx.here then exitIdx = i; break end
            end
        end
        local pick, pickI
        for i, p in ipairs(left) do
            local spot = bestSpot(start, out, p, ctx, exitIdx, cache)
            if spot and (not pick or spot.cost < pick.cost) then pick, pickI = spot, i end
        end
        if not pick then break end
        local p = table.remove(left, pickI)
        local extra = flightStop(p, cache)
        extra.round = (out[pick.idx - 1] or out[pick.idx] or {}).round -- R7
        table.insert(out, pick.idx, extra)
        added[#added + 1] = { node = p, cost = pick.cost, why = pick.why, idx = pick.idx }
        total = total + pick.cost
    end
    return out, added, total
end

-- Spec 059, R4: quest dispensada até skips[q] (tempo do jogo)?
function Leveling.SkipActive(skips, q, now)
    local t = skips and skips[q]
    return t ~= nil and now < t
end

-- Spec 059, R3: depois dos 30 s na parada "pegar": "nada", "esperar" (em combate) ou "dispensar".
function Leveling.AbsentDecision(s)
    if not s.same or s.dialog or not s.near then return "nada" end
    if s.combat then return "esperar" end
    return "dispensar"
end

-- Spec 059, R7: paradas sem as dispensadas pelo jogador (skips[id] = até quando) e, em cadeia, sem as
-- que dependem delas (after com a key de uma tirada). Lista nova.
function Leveling.FilterSkipped(stops, skips, now, idOf)
    local gone, changed = {}, true
    for _, s in ipairs(stops or {}) do
        if Leveling.SkipActive(skips, idOf(s), now) and s.key then gone[s.key] = true end
    end
    local function out_(s)
        if Leveling.SkipActive(skips, idOf(s), now) then return true end
        for _, k in ipairs(s.after or {}) do if gone[k] then return true end end
        return false
    end
    while changed do -- a cadeia pode ter vários elos
        changed = false
        for _, s in ipairs(stops or {}) do
            if s.key and not gone[s.key] and out_(s) then gone[s.key] = true; changed = true end
        end
    end
    local out = {}
    for _, s in ipairs(stops or {}) do
        if not out_(s) and not (s.key and gone[s.key]) then out[#out + 1] = s end
    end
    return out
end

-- Spec 006, R20: seguindo uma quest sem ponto de objetivo, por quê? nil = não falta objetivo (vai entregar).
function Leveling.NoPointReason(objectives, dungeon)
    for _, o in ipairs(objectives or {}) do
        if not o.done then return dungeon and "masmorra" or K("sem coordenada") end
    end
    return nil
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
    local weak, cut = {}, (threshold or 0) * avg
    for _, e in ipairs(entries) do
        -- Spec 029, R1: `unlock` (XP que a quest destrava) entra no corte, não na média.
        local rate = e.seconds > 0 and (e.value + (e.unlock or 0)) / e.seconds or huge
        -- Spec 039, R4: com passos adiante, vale a taxa do bloco (valor e tempo da cadeia).
        local a = e.ahead
        if a and (a.seconds or 0) + e.seconds > 0 then
            local block = (e.value + (e.unlock or 0) + (a.value or 0)) / (e.seconds + (a.seconds or 0))
            if not e.locked and rate < cut and block >= cut then e.byChain = true end
            rate = math.max(rate, block)
        end
        if not e.locked and rate < cut then weak[e.id] = true end
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
--       goldToXP, logFree, playerLevel, mobTolerance (spec 031) }

local function pending(q)
    local out = {}
    if q.state == "entregar" then return out end
    for _, o in ipairs(q.objectives or {}) do
        if not o.done and ((o.kills or 0) > 0 or (o.objects or 0) > 0) then out[#out + 1] = o end
    end
    return out
end

-- Spec 030, R5: mob acima do jogador demora mais (+10% por nível, como o grind da spec 029).
-- Spec 063, R1: mob abaixo morre mais rápido (−5% por nível, até 70%; estimativa, calibra pelo diário).
Leveling.KILL_BELOW, Leveling.KILL_FLOOR = 0.05, 0.7
function Leveling.KillFactor(avgLevel, playerLevel)
    if not (avgLevel and playerLevel) then return 1 end
    if avgLevel >= playerLevel then return 1 + 0.1 * (avgLevel - playerLevel) end
    return max(Leveling.KILL_FLOOR, 1 - Leveling.KILL_BELOW * (playerLevel - avgLevel))
end

-- Spec 063, R2a: o modo fácil só vale do nível 10 em diante.
Leveling.EASY_MIN_LEVEL = 10
function Leveling.EasyActive(easy, level)
    return easy == true and (level or 0) >= Leveling.EASY_MIN_LEVEL
end

-- Spec 063, R2: no modo fácil, o corte de mobs altos vale acima de nível − 2.
Leveling.EASY_TOP = -2
function Leveling.EasyTolerance(tolerance, easy)
    if not easy then return tolerance end
    return math.min(tolerance or Leveling.EASY_TOP, Leveling.EASY_TOP)
end

-- Spec 063, R5: diferença média (ponderada pelas kills) dos mobs pendentes para o jogador.
function Leveling.MobDiff(objectives, playerLevel)
    local sum, n = 0, 0
    for _, o in ipairs(objectives or {}) do
        local k = o.kills or 0
        if not o.done and k > 0 and o.avgLevel then sum, n = sum + k * (o.avgLevel - playerLevel), n + k end
    end
    if n == 0 then return nil end
    return sum / n
end

-- Spec 030, R2: objetivo com mob médio mais de 1,5 nível acima do jogador.
-- Spec 031, R5: a tolerância muda com a força do personagem; sem ela, vale o 1,5.
Leveling.MAX_MOB_ABOVE = 1.5

-- Spec 030, R7 (emenda de 28/11/2026): ponto de objetivo cercado de mob alto. dangerAt(p) diz se o
-- ponto é perigoso; com algum ponto seguro, só os seguros ficam; sem nenhum, ficam todos (a quest segue
-- a regra de mobs altos da R3).
Leveling.DANGER_GAP, Leveling.DANGER_MIN = 3, 3 -- mob 3 níveis acima; 3 spawns por perto
function Leveling.DangerousCount(mids, playerLevel)
    local n = 0
    for _, m in ipairs(mids or {}) do if m >= playerLevel + Leveling.DANGER_GAP then n = n + 1 end end
    return n
end
function Leveling.SafePoints(points, dangerAt)
    local safe = {}
    for _, p in ipairs(points or {}) do if not dangerAt(p) then safe[#safe + 1] = p end end
    if #safe == 0 or #safe == #(points or {}) then return points end
    return safe
end

-- Spec 030, R6 (emenda de 28/11/2026, visto no jogo: "Elixir of Pain" (24) junta o sangue de quatro
-- leões, dois em Hillsbrad (23–28) e dois em Alterac (32–34); a seta mandou para os de 32).
-- mobs = { { lo, hi, n = pontos } }. Devolve os mobs até nível + tolerância; se nenhum estiver, todos.
function Leveling.MobsInReach(mobs, playerLevel, tolerance)
    if not (mobs and playerLevel) then return mobs end
    local out = {}
    for _, m in ipairs(mobs) do
        if (m.lo + m.hi) / 2 <= playerLevel + (tolerance or Leveling.MAX_MOB_ABOVE) then out[#out + 1] = m end
    end
    return #out > 0 and out or mobs
end
function Leveling.MobsTooHigh(avgLevel, playerLevel, state, tolerance)
    return state ~= "entregar" and avgLevel ~= nil and playerLevel ~= nil and playerLevel ~= false
        and avgLevel > playerLevel + (tolerance or Leveling.MAX_MOB_ABOVE)
end

-- Algum objetivo pendente com mobs altos demais (R2)? objectives = saída de Data.Objectives.
function Leveling.ObjectivesTooHigh(objectives, playerLevel, state, tolerance)
    if state == "entregar" then return false end
    for _, o in ipairs(objectives or {}) do
        if not o.done and Leveling.MobsTooHigh(o.avgLevel, playerLevel, state, tolerance) then return true end
    end
    return false
end

------------------------------------------------------------------------------------------
-- Força do personagem (spec 031). Todos os números são estimativa, a calibrar no jogo.
------------------------------------------------------------------------------------------
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

Leveling.GEAR_SLOTS = 12     -- cabeça, ombro, peito, cintura, pernas, pés, pulso, mãos, capa, MH, OH, distância
Leveling.GEAR_GAP = 5        -- item level esperado = nível - 5
Leveling.GEAR_SCALE = 0.5    -- metade do nível (mínimo 5) acima do esperado = +1 de tolerância
Leveling.OFFSET_LIMIT = 1    -- o ajuste fica entre -1 e +1

-- R1: média dos 12 slots, vazio conta 0; levels[i] = item level ou nil. Sem nenhum item: nil.
function Leveling.AvgItemLevel(levels)
    local total, filled = 0, 0
    for i = 1, Leveling.GEAR_SLOTS do
        local v = levels and levels[i]
        if v and v > 0 then total = total + v; filled = filled + 1 end
    end
    if filled == 0 then return nil end
    return total / Leveling.GEAR_SLOTS
end

-- R2: ajuste pelo gear, relativo ao nível.
function Leveling.GearOffset(avgIlvl, playerLevel)
    if not (avgIlvl and playerLevel) then return 0 end
    local lim = Leveling.OFFSET_LIMIT
    local scale = max(5, playerLevel * Leveling.GEAR_SCALE)
    return clamp((avgIlvl - (playerLevel - Leveling.GEAR_GAP)) / scale, -lim, lim)
end

Leveling.DANGER_MIN_SAMPLES = 5
Leveling.DANGER_MIN_ABOVE = -1    -- mob verde não diz nada sobre mob alto
Leveling.DANGER_PER_LEVEL = 0.25  -- cada nível acima pesa +25% na perda de HP
Leveling.DANGER_REF = 0.40        -- perda normalizada que dá ajuste 0
Leveling.DANGER_SPAN = 0.15       -- 0,25 dá +1, 0,55 dá -1
Leveling.DANGER_DEATH_WINDOW = 10 -- morte nas últimas 10 lutas: ajuste no máximo 0
Leveling.DANGER_FLEE_LOSS = 0.5   -- luta sem kill só conta com perda alta (fuga, evade)
Leveling.COMBAT_SPREAD = 0.5      -- o combate corrige o gear em até ±0,5 (até a calibração, T6)

-- R10: amostra de uma luta. f = { start, min, above, targetAbove, died, group }.
function Leveling.FightSample(f)
    if not f or f.group then return nil end
    if f.died then return { loss = 1, above = f.above or f.targetAbove or 0, died = true } end
    local loss = max(0, (f.start or 1) - (f.min or f.start or 1))
    if f.above then return { loss = loss, above = f.above } end
    if loss >= Leveling.DANGER_FLEE_LOSS then return { loss = loss, above = f.targetAbove or 0 } end
    return nil
end

-- R3: ajuste pelo combate. samples = { { loss, above, died } }, da mais velha para a mais nova.
function Leveling.CombatOffset(samples)
    if not samples then return nil, false end
    local recentDeath = false -- vale mesmo com poucas amostras (3ª rodada)
    for i = max(1, #samples - Leveling.DANGER_DEATH_WINDOW + 1), #samples do
        if samples[i].died then recentDeath = true end
    end
    local norm = {}
    for _, s in ipairs(samples) do
        local above = s.above or 0
        if above >= Leveling.DANGER_MIN_ABOVE then
            norm[#norm + 1] = (s.loss or 0) / (1 + Leveling.DANGER_PER_LEVEL * above)
        end
    end
    if #norm < Leveling.DANGER_MIN_SAMPLES then return nil, recentDeath end
    table.sort(norm)
    local n = norm[math.ceil(0.75 * #norm)] -- percentil 75: o risco está na cauda
    local lim = Leveling.OFFSET_LIMIT
    local offset = clamp((Leveling.DANGER_REF - n) / Leveling.DANGER_SPAN, -lim, lim)
    if recentDeath then offset = min(offset, 0) end
    return offset, recentDeath
end

-- R4: o combate medido corrige o gear, a no máximo ±0,5 dele; morte recente prende em até 1,5.
function Leveling.MobTolerance(gearOffset, combatOffset, recentDeath)
    local g = gearOffset or 0
    local tol = Leveling.MAX_MOB_ABOVE + g
    if combatOffset ~= nil then
        local spread = Leveling.COMBAT_SPREAD
        tol = Leveling.MAX_MOB_ABOVE + clamp(combatOffset, g - spread, g + spread)
    end
    if recentDeath then tol = min(tol, Leveling.MAX_MOB_ABOVE) end
    return tol
end

local function workSeconds(o, p)
    local per
    if p.killCurve and p.playerLevel then -- spec 067, R6: tempo medido pela diferença de nível
        per = Leveling.KillSecondsFor(p.killCurve, p.ttk, o.avgLevel, p.playerLevel) + (p.downtime or 0)
    else
        local factor = p.playerLevel and Leveling.KillFactor(o.avgLevel, p.playerLevel) or 1
        per = (p.ttk + (p.downtime or 0)) * factor
    end
    return (o.kills or 0) * per + (o.objects or 0) * Leveling.OBJECT_SECONDS
end

Leveling.MAX_LEVELS_ABOVE = 4 -- spec 025: quest "vermelha" demais (também o filtro de quest nova, Data.lua)

-- Spec 025, R4: quest alta demais para fazer agora (a entrega pronta não conta).
function Leveling.TooHigh(qLevel, playerLevel, state)
    return state ~= "entregar" and qLevel ~= nil and playerLevel ~= nil and playerLevel ~= false
        and qLevel > playerLevel + Leveling.MAX_LEVELS_ABOVE
end

-- Spec 046, R7: quest cinza = 6 níveis ou mais abaixo (o corte da limpeza do log, spec 006 R10).
Leveling.GRAY_QUEST_LEVELS = 6
function Leveling.IsGrayQuest(qLevel, playerLevel)
    return qLevel ~= nil and playerLevel ~= nil and playerLevel ~= false
        and playerLevel - qLevel >= Leveling.GRAY_QUEST_LEVELS
end

-- Spec 046, R9: item que segura a quest cinza: upgrade significativo ou raro (ou melhor) usável.
function Leveling.ItemWorth(delta, quality, minDelta)
    if delta == nil then return false end
    return delta >= (minDelta or 10) or (quality or 0) >= 3
end

local function asideReason(q, p)
    if q.forceAside then return q.forceAside end -- ex.: satélite com desvio grande (spec 008)
    -- Spec 046, R8: cinza sai, salvo classe, bolsa, item que vale (goal) ou entrega pronta.
    if q.state ~= "entregar" and Leveling.IsGrayQuest(q.qLevel, p.playerLevel)
        and not (q.classQuest or q.bag or q.goal) then
        return K("cinza")
    end
    -- Spec 025, R1: quest do log alta demais sai do circuito; a entrega pronta fica.
    if Leveling.TooHigh(q.qLevel, p.playerLevel, q.state) then return K("nível alto") end
    local high -- spec 030, R3: o objetivo mais alto decide; backAt = nível em que volta
    for _, o in ipairs(pending(q)) do
        if Leveling.MobsTooHigh(o.avgLevel, p.playerLevel, q.state, p.mobTolerance) then high = max(high or 0, o.avgLevel) end
    end
    if high then return K("mobs altos"), math.ceil(high - (p.mobTolerance or Leveling.MAX_MOB_ABOVE)) end -- spec 031, R6
    if q.state ~= "entregar" then -- spec 030, R7a: objetivo só em lugar cercado de mob alto
        for _, o in ipairs(pending(q)) do if o.danger then return K("área perigosa") end end
    end
    if q.dungeon then return q.group == "grupo" and K("masmorra (em grupo)") or "dungeon" end -- spec 054, R3
    if q.elite and q.group ~= "grupo" then return "elite" end
    -- Spec 067, R4: evento ou quest que já te matou duas vezes, sem a escolha "grupo"
    if q.state ~= "entregar" and q.group ~= "grupo" then
        if q.event then return K("evento") end
        if Leveling.DeathRisky(q.deaths, q.deathLevel, p.playerLevel) then return K("te matou") end
    end
    if q.state == "pegar" and #(q.starters or {}) == 0 then return K("sem coordenada") end
    if #(q.finishers or {}) == 0 then return K("sem coordenada") end
    for _, o in ipairs(pending(q)) do
        if #(o.points or {}) == 0 then return K("sem coordenada") end
    end
    return nil
end

Leveling.AsideReason = asideReason -- spec 054, R3

-- Spec 054, R1: quest de grupo? "masmorra", "elite" ou nil. Spec 067, R3: "evento" (risky).
function Leveling.GroupKind(elite, dungeon, risky)
    if dungeon then return "masmorra" end
    if elite then return "elite" end
    if risky then return "evento" end
    return nil
end

-- Spec 067, R2: duas mortes na mesma quest; R2a: valem até 2 níveis depois da última.
Leveling.DEATH_RISK, Leveling.DEATH_LEVELS = 2, 2
function Leveling.DeathRisky(n, atLevel, level)
    if (n or 0) < Leveling.DEATH_RISK then return false end
    return not (atLevel and level and level - atLevel >= Leveling.DEATH_LEVELS)
end

-- Spec 067, R5a: a morte só conta para a parada se foi perto do alvo da seta.
Leveling.DEATH_NEAR = 150
function Leveling.DeathCounts(dist) return dist ~= nil and dist <= Leveling.DEATH_NEAR end

-- Spec 067, R6: mediana do tempo por morte por diferença de nível (mob − você, de −6 a +3).
Leveling.KILL_DIFF_MIN, Leveling.KILL_DIFF_MAX = -6, 3
function Leveling.KillDiff(avgLevel, playerLevel)
    local d = math.floor((avgLevel or playerLevel) - playerLevel + 0.5)
    return math.max(Leveling.KILL_DIFF_MIN, math.min(Leveling.KILL_DIFF_MAX, d))
end
function Leveling.KillCurve(samples, minSamples)
    local by = {}
    for _, s in ipairs(samples or {}) do
        if s.d and s.s then by[s.d] = by[s.d] or {}; table.insert(by[s.d], s.s) end
    end
    local out = {}
    for d, list in pairs(by) do
        if #list >= (minSamples or 5) then
            table.sort(list)
            local n = #list
            out[d] = n % 2 == 1 and list[(n + 1) / 2] or (list[n / 2] + list[n / 2 + 1]) / 2
        end
    end
    return out
end
function Leveling.KillSecondsFor(curve, base, avgLevel, playerLevel)
    if not playerLevel then return base end
    local d = Leveling.KillDiff(avgLevel, playerLevel)
    if curve then
        if curve[d] then return curve[d] end
        local best
        for k in pairs(curve) do
            if not best or math.abs(k - d) < math.abs(best - d) or (math.abs(k - d) == math.abs(best - d) and k > best) then best = k end
        end
        if best then
            return curve[best] * Leveling.KillFactor(playerLevel + d, playerLevel) / Leveling.KillFactor(playerLevel + best, playerLevel)
        end
    end
    return base * Leveling.KillFactor(avgLevel, playerLevel)
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
        if out[e.id] then aside[#aside + 1] = { id = e.id, reason = K("log cheio") }
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
                aside[#aside + 1] = { id = q.id, reason = L["depende de "] .. pre }
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
            -- R34 com a emenda da spec 046 (R1, R2): do log, só a entrega pronta e a protegida (keep) ficam
            -- travadas; a em andamento entra no corte. Spec 010: bolsa.
            locked = q.state == "entregar" or q.bag or (q.state == "fazer" and q.keep),
            ahead = q.state == "pegar" and q.ahead or nil } -- spec 039, R4: passos adiante da cadeia
    end
    local kept, dropped = Leveling.SelectQuests(entries, p.threshold or 0)
    for _, e in ipairs(dropped) do -- spec 046, R3: a do log sai com "rende pouco" (e não é abandonada)
        aside[#aside + 1] = { id = e.id, reason = e.quest.state == "fazer" and K("rende pouco") or K("abaixo do limiar") }
    end
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
            if e.chain and not needed[e.id] then
                aside[#aside + 1] = { id = e.id, reason = e.quest.state == "fazer" and K("rende pouco") or K("abaixo do limiar") }
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
            local ordered = Leveling.NearestOrder(cursor, all, dist)
            local l, c
            ordered = Leveling.Untangle(cursor, ordered, dist) -- spec 053, R3
            ordered = Leveling.Relocate(cursor, ordered, dist) -- spec 068, R7
            ordered, l, c = Leveling.Untangle(cursor, ordered, dist)
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
    for _, e in ipairs(kept) do keptQuests[#keptQuests + 1] = { id = e.id, chain = e.chain, state = e.quest.state, byChain = e.byChain } end
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
function Leveling.PickHub(hubs, mode, preferZone)
    -- Spec 068, R3: a rota da zona ganha em "best" e "next"; "turnin" segue a regra de antes.
    if preferZone and mode ~= "turnin" then
        for _, h in ipairs(hubs) do
            if h.zone and (h.quests or 0) > 0 then return h.key end
        end
    end
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

-- Spec 010, R5, R8 e R10: melhor quest de bolsa. list = { { q, level, mapID, status, skipped, step } }.
-- step: primeiro passo da cadeia (mesmos campos), quando a quest depende de outra; segue-se o passo.
-- Só a do log ou disponível, não dispensada; a da zona atual primeiro, depois a de menor nível.
function Leveling.PickBag(list, zoneMap)
    local best, bestKey
    for _, b in ipairs(list) do
        local s = b.step or b
        if not b.skipped and (s.status == K("no log") or s.status == K("disponível")) then
            local key = (s.mapID == zoneMap and 0 or 1) * 1000 + s.level
            if not bestKey or key < bestKey then best, bestKey = b, key end
        end
    end
    return best
end

-- Spec 010, R10: primeiro passo da cadeia que leva a q. pre(q) → single, group (alternativas e
-- obrigatórias); done(q) → já feita; takeable(q) → a raça e a classe podem pegar e não foi feita.
-- Devolve a quest cujos pré-requisitos estão todos cumpridos, ou nil se o caminho está fechado.
function Leveling.ChainStart(q, pre, done, takeable, seen)
    seen = seen or {}
    if seen[q] then return nil end -- ciclo nos dados
    seen[q] = true
    local single, group = pre(q)
    if single and single[1] then
        local any = false
        for _, p in ipairs(single) do if done(p) then any = true; break end end
        if not any then
            for _, p in ipairs(single) do
                if takeable(p) then
                    local s = Leveling.ChainStart(p, pre, done, takeable, seen)
                    if s then return s end
                end
            end
            return nil
        end
    end
    -- Obrigatórias: todas as que faltam precisam poder ser pegas; depois desce na primeira.
    local first
    for _, p in ipairs(group or {}) do
        if not done(p) then
            if not takeable(p) then return nil end
            first = first or p
        end
    end
    if first then return Leveling.ChainStart(first, pre, done, takeable, seen) end
    return q
end

-- Spec 035, R7 e R18: o que resolver antes de sair. items = { { id, name, ready, qLevel, zone, travel } }
-- do log; nearZones = { [zona] = true } de "Perto". Prontas ("entregar") de qualquer zona, as de fora
-- de "Perto" com far (até farMax), em ordem de travel (sem travel por último; empate pela posição no
-- log). Depois as de "Perto" que perdem XP se subir de nível antes: "perde XP no nível L+1", com loss.
function Leveling.BeforeLeaving(items, lvl, nearZones, farMax)
    farMax = farMax or 5
    local ready, far, losing = {}, {}, {}
    local falloff = ns.Util.XPFalloff
    for i, it in ipairs(items or {}) do
        local isNear = it.zone and nearZones and nearZones[it.zone]
        if it.zone and it.ready then
            local e = { id = it.id, name = it.name, zone = it.zone, qLevel = it.qLevel, reason = K("entregar"),
                travel = it.travel, far = (not isNear) or nil, pos = i }
            if isNear then ready[#ready + 1] = e else far[#far + 1] = e end
        elseif isNear and it.qLevel then
            local now, next = falloff(lvl, it.qLevel), falloff(lvl + 1, it.qLevel)
            if next < now then
                losing[#losing + 1] = { id = it.id, name = it.name, zone = it.zone, qLevel = it.qLevel,
                    reason = L["perde XP no nível "] .. (lvl + 1), loss = now - next }
            end
        end
    end
    local function byTravel(a, b)
        local ta, tb = a.travel or math.huge, b.travel or math.huge
        if ta ~= tb then return ta < tb end
        return a.pos < b.pos
    end
    table.sort(far, byTravel)
    for i = #far, farMax + 1, -1 do far[i] = nil end
    for _, e in ipairs(far) do ready[#ready + 1] = e end
    table.sort(ready, byTravel)
    for _, e in ipairs(ready) do e.pos = nil end
    for _, e in ipairs(losing) do ready[#ready + 1] = e end
    return ready
end

-- Spec 035, R19: a entrega pronta mais perto (a primeira "entregar" da saída da R18).
function Leveling.NearestReady(list)
    for _, e in ipairs(list or {}) do
        if e.reason == "entregar" then return e end
    end
    return nil
end

-- Spec 035, R20: com transporte ou pedra de lar no caminho, a seta não leva sozinha (outro continente).
function Leveling.TurnInAction(plan)
    for _, s in ipairs(plan and plan.steps or {}) do
        if s.kind == "transporte" or s.kind == "lar" then return "viagem" end
    end
    return "seguir"
end

-- Spec 035, R16: XP/h efetivo de um hub. Hub com pouco XP no total acaba logo e rende menos.
function Leveling.HubWorth(rate, xp, levelXP, share)
    if not (levelXP and levelXP > 0 and share and share > 0) then return rate end
    return rate * math.min(1, (xp or 0) / (share * levelXP))
end

-- Spec 035, R8: hubs com quests deixadas de lado por estarem altas (backAt), por hub.
-- rows = { { key, name, zone, circuit = { aside = { { id, backAt } } } } }.
function Leveling.ComeBack(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local n, back = 0, nil
        for _, a in ipairs(r.circuit and r.circuit.aside or {}) do
            if a.backAt then n = n + 1; back = math.min(back or a.backAt, a.backAt) end
        end
        if n > 0 then out[#out + 1] = { key = r.key, name = r.name, zone = r.zone, n = n, backAt = back } end
    end
    table.sort(out, function(a, b)
        if a.backAt ~= b.backAt then return a.backAt < b.backAt end
        if a.n ~= b.n then return a.n > b.n end
        return tostring(a.key) < tostring(b.key)
    end)
    return out
end

------------------------------------------------------------------------------------------
-- Valor da cadeia (spec 039)
------------------------------------------------------------------------------------------
Leveling.CHAIN_STEPS = 5
Leveling.DUNGEON_STEP_SECONDS = 900 -- estimativa: a parte de uma quest numa ida à masmorra

-- R1: passos adiante de q, em largura. nextOf(id) → ids; infoOf(id) → { level, dungeon, done }.
function Leveling.ChainWalk(q, nextOf, infoOf, lvl, opts)
    local maxDepth = opts and opts.steps or Leveling.CHAIN_STEPS
    local group = opts and opts.group
    local out, seen, frontier = {}, { [q] = true }, { q }
    for _ = 1, maxDepth do
        local nextFrontier = {}
        for _, cur in ipairs(frontier) do
            for _, n in ipairs(nextOf(cur) or {}) do
                if not seen[n] then
                    seen[n] = true
                    local i = infoOf(n) or {}
                    local stop = i.skip or (i.dungeon and not group) or (i.level and i.level > lvl + Leveling.MAX_LEVELS_ABOVE)
                    if not stop then
                        if not i.done then out[#out + 1] = n end
                        nextFrontier[#nextFrontier + 1] = n
                    end
                end
            end
        end
        frontier = nextFrontier
        if not frontier[1] then break end
    end
    return out
end

-- R2: bloco = a quest mais os passos adiante. own e steps = { value, seconds }.
function Leveling.ChainBlock(own, steps)
    local value, seconds = own.value or 0, own.seconds or 0
    for _, s in ipairs(steps or {}) do
        value, seconds = value + (s.value or 0), seconds + (s.seconds or 0)
    end
    return { value = value, seconds = seconds, rate = seconds > 0 and value / seconds or 0, n = #(steps or {}) }
end

-- R3: valor e tempo de um passo adiante, com a mesma conta do circuito.
-- Emenda: cada passo paga um deslocamento desconhecido (UNKNOWN_LEG), como o circuito paga as pernas.
function Leveling.StepEstimate(q, p)
    if q.dungeon then return (q.xp or 0) + (p.goldToXP or 0) * (q.money or 0) / 100, Leveling.DUNGEON_STEP_SECONDS end
    local value, seconds = ownEstimate(q, p)
    return value, seconds + Leveling.UNKNOWN_LEG / (p.speed or 7)
end

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
        -- Spec 039, R7: o bloco da cadeia rende o bastante: não sugere abandonar.
        local chainOk = it.chainRate and (it.hubRate or 0) > 0 and it.chainRate >= (threshold or 0) * it.hubRate
        if it.incomplete and not chainOk and not Leveling.Protected(it) then
            local weak = (it.hubRate or 0) > 0 and (it.rate or 0) < (threshold or 0) * it.hubRate
            if it.gray or weak then out[#out + 1] = { id = it.id, reason = it.gray and K("cinza") or K("rende pouco") } end
        end
    end
    return out
end

return Leveling
