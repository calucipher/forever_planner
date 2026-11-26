-- Gates.lua: passagens entre zonas (spec 049). Núcleo puro: aprende com as amostras do jogador,
-- acha o caminho a pé pelas passagens e monta o título. Distâncias em jardas do mundo.
local _, ns = ...
local Gates = {}
ns.Gates = Gates

local DEFAULTS = { jump = 40, merge = 60 }
local function opt(opts, k) return (opts and opts[k]) or DEFAULTS[k] end
local function span(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- R2: s = { c, x, y, zone } (nil = taxi, morto, sem posição: esquece a amostra anterior). QUANDO a
-- zona mudar a até opts.jump jd da amostra anterior, guarda a passagem no meio das duas, juntando
-- com uma do mesmo par a até opts.merge jd. Devolve a passagem nova ou juntada, ou nil.
function Gates.Learn(store, state, s, opts)
    local last = state.last
    state.last = s
    if not (s and last and s.zone and last.zone) or last.zone == s.zone or last.c ~= s.c then return nil end
    if span(last, s) > opt(opts, "jump") then return nil end -- salto: voo, teleporte, pedra de lar
    local x, y = (last.x + s.x) / 2, (last.y + s.y) / 2
    store[s.c] = store[s.c] or {}
    for _, g in ipairs(store[s.c]) do
        local same = (g.a == last.zone and g.b == s.zone) or (g.a == s.zone and g.b == last.zone)
        if same and span(g, { x = x, y = y }) <= opt(opts, "merge") then return g end
    end
    local g = { a = last.zone, b = s.zone, x = x, y = y, learned = true }
    table.insert(store[s.c], g)
    return g
end

-- R3: caminho a pé mais curto de from a to pelas passagens (Dijkstra; o estado é a passagem cruzada
-- e a zona onde se chega). from/to = { zone, x, y }. Devolve { gates = {...}, yd } ou nil.
-- Spec 064, R1: opts.zoneCost(zone) multiplica o trecho dentro de cada zona intermediária;
-- `yd` continua sendo a distância real do caminho escolhido.
function Gates.Route(gates, from, to, dist, opts)
    dist = dist or span
    local zoneCost, memo = opts and opts.zoneCost, {}
    local function factor(zone)
        if not zoneCost or zone == from.zone or zone == to.zone then return 1 end
        if memo[zone] == nil then memo[zone] = zoneCost(zone) or 1 end -- R1a: uma consulta por zona
        return memo[zone]
    end
    if not (from.zone and to.zone) or from.zone == to.zone then return { gates = {}, yd = dist(from, to) } end
    local nodes = {}
    for _, g in ipairs(gates or {}) do
        nodes[#nodes + 1] = { g = g, zone = g.b, enter = g.a }
        nodes[#nodes + 1] = { g = g, zone = g.a, enter = g.b }
    end
    local cost, prev, done, real = {}, {}, {}, {}
    for i, n in ipairs(nodes) do
        if n.enter == from.zone then cost[i] = dist(from, n.g); real[i] = cost[i] end
    end
    local best, bestEnd, bestReal
    while true do
        local i, ci
        for k, c in pairs(cost) do
            if not done[k] and (not ci or c < ci) then i, ci = k, c end
        end
        if not i or (best and ci >= best) then break end
        done[i] = true
        local n = nodes[i]
        if n.zone == to.zone then
            local leg = dist(n.g, to)
            if not best or ci + leg < best then best, bestEnd, bestReal = ci + leg, i, real[i] + leg end
        end
        for k, m in ipairs(nodes) do
            if not done[k] and m.enter == n.zone and m.g ~= n.g then
                local leg = dist(n.g, m.g)
                local c = ci + leg * factor(n.zone) -- R1: o trecho dentro da zona n.zone
                if not cost[k] or c < cost[k] then cost[k], prev[k], real[k] = c, i, real[i] + leg end
            end
        end
    end
    if not bestEnd then return nil end
    local path, k = {}, bestEnd
    while k do
        table.insert(path, 1, { x = nodes[k].g.x, y = nodes[k].g.y, from = nodes[k].enter, to = nodes[k].zone, gate = nodes[k].g })
        k = prev[k]
    end
    return { gates = path, yd = bestReal }
end

-- Spec 064, R2: custo de atravessar uma zona pelo meio da faixa dela contra o nível do jogador.
function Gates.DangerCost(lo, hi, L)
    if not (lo and L) then return 1 end
    local mid = hi and (lo + hi) / 2 or lo
    if mid <= L + 2 then return 1 end
    if mid <= L + 5 then return 3 end
    return 10
end

-- R4: título da seta.
function Gates.Title(step, name, title)
    return string.format("Passagem: %s > %s · depois: %s", tostring(name(step.from)), tostring(name(step.to)), tostring(title))
end

return Gates
