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
function Gates.Route(gates, from, to, dist)
    dist = dist or span
    if not (from.zone and to.zone) or from.zone == to.zone then return { gates = {}, yd = dist(from, to) } end
    local nodes = {}
    for _, g in ipairs(gates or {}) do
        nodes[#nodes + 1] = { g = g, zone = g.b, enter = g.a }
        nodes[#nodes + 1] = { g = g, zone = g.a, enter = g.b }
    end
    local cost, prev, done = {}, {}, {}
    for i, n in ipairs(nodes) do
        if n.enter == from.zone then cost[i] = dist(from, n.g) end
    end
    local best, bestEnd
    while true do
        local i, ci
        for k, c in pairs(cost) do
            if not done[k] and (not ci or c < ci) then i, ci = k, c end
        end
        if not i or (best and ci >= best) then break end
        done[i] = true
        local n = nodes[i]
        if n.zone == to.zone then
            local total = ci + dist(n.g, to)
            if not best or total < best then best, bestEnd = total, i end
        end
        for k, m in ipairs(nodes) do
            if not done[k] and m.enter == n.zone and m.g ~= n.g then
                local c = ci + dist(n.g, m.g)
                if not cost[k] or c < cost[k] then cost[k], prev[k] = c, i end
            end
        end
    end
    if not bestEnd then return nil end
    local path, k = {}, bestEnd
    while k do
        table.insert(path, 1, { x = nodes[k].g.x, y = nodes[k].g.y, from = nodes[k].enter, to = nodes[k].zone, gate = nodes[k].g })
        k = prev[k]
    end
    return { gates = path, yd = best }
end

-- R4: título da seta.
function Gates.Title(step, name, title)
    return string.format("Passagem: %s > %s · depois: %s", tostring(name(step.from)), tostring(name(step.to)), tostring(title))
end

return Gates
