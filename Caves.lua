-- Caves.lua: entrada de caverna (e de prédio) para a seta (spec 038). Núcleo puro: recebe as
-- amostras de posição e as listas por parâmetro; não chama a API do jogo nem lê o db.
-- Distâncias em jardas do mundo. Os padrões são estimativa, a calibrar no jogo.
local _, ns = ...
local Caves = {}
ns.Caves = Caves

local DEFAULTS = { jump = 30, merge = 15, step = 8, max = 300, near = 20, arrive = 10, minReach = 0 }
local function opt(opts, k) return (opts and opts[k]) or DEFAULTS[k] end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Entrada da lista (seed) ou aprendida a até `merge` jd de (x, y), no continente c.
local function nearEntrance(list, x, y, merge, learnedOnly)
    for _, e in ipairs(list or {}) do
        if not (learnedOnly and e.seed) and dist(e.x, e.y, x, y) <= merge then return e end
    end
    return nil
end

-- R1/R2/R9: aprende com a amostra s = { c, x, y, indoors, m, mx, my, name } (s = nil esquece a
-- amostra externa). state guarda a amostra externa anterior e a entrada atual. Devolve verdadeiro
-- quando o estado interno/externo mudou.
function Caves.Learn(store, state, s, opts)
    if not s then
        state.lastOut, state.current, state.indoors = nil, nil, nil
        return false
    end
    local was = state.indoors
    state.indoors = s.indoors and true or false
    if not s.indoors then
        state.current = nil
        state.lastOut = s
        return was == true
    end
    local o = state.lastOut
    if was == false and o and o.c == s.c and dist(o.x, o.y, s.x, s.y) <= opt(opts, "jump") then
        store[s.c] = store[s.c] or {}
        local e = nearEntrance(store[s.c], o.x, o.y, opt(opts, "merge"), true)
        if not e then
            e = { x = o.x, y = o.y, m = o.m, mx = o.mx, my = o.my, name = s.name, pts = {} }
            store[s.c][#store[s.c] + 1] = e
        end
        state.current = e
    end
    state.lastOut = nil
    local e = state.current
    if e and e.pts then
        local n = #e.pts
        if n / 2 < opt(opts, "max") and (n == 0 or dist(e.pts[n - 1], e.pts[n], s.x, s.y) > opt(opts, "step")) then
            e.pts[n + 1], e.pts[n + 2] = s.x, s.y
        end
    end
    return was == false
end

-- A área da entrada contém (x, y)? Aprendida: pela pegada; da lista: pelo raio do centro.
local function contains(e, x, y, near)
    if e.seed then return dist(e.cx, e.cy, x, y) <= e.radius end
    local pts = e.pts or {}
    for i = 1, #pts - 1, 2 do
        if dist(pts[i], pts[i + 1], x, y) <= near then return true end
    end
    return false
end

-- R3: entradas do continente c cuja área contém o ponto.
-- R3a (emenda de 21/11/2026): alcance da pegada aprendida, a maior distância da boca até um ponto.
function Caves.Reach(e)
    local pts, best = e.pts or {}, 0
    for i = 1, #pts - 1, 2 do best = math.max(best, dist(e.x, e.y, pts[i], pts[i + 1])) end
    return best
end

function Caves.Find(caves, c, x, y, near, minReach)
    local out = {}
    near, minReach = near or DEFAULTS.near, minReach or DEFAULTS.minReach
    for _, e in ipairs(caves and caves[c] or {}) do
        -- R3a: prédio de cidade (pegada curta) não vale como caverna; a da lista sempre vale.
        if (e.seed or Caves.Reach(e) >= minReach) and contains(e, x, y, near) then out[#out + 1] = e end
    end
    return out
end

-- R7: entrada da lista vira a aprendida quando esta fica perto dela ou tem pegada dentro da área
-- da lista (a área da lista continua valendo).
local function confirmed(caves, c, e, merge)
    if not e.seed then return e end
    local hit = nearEntrance(caves[c], e.x, e.y, merge, true)
    if hit then return hit end
    for _, l in ipairs(caves[c] or {}) do
        if not l.seed then
            local pts = l.pts or {}
            for i = 1, #pts - 1, 2 do
                if dist(e.cx, e.cy, pts[i], pts[i + 1]) <= e.radius then return l end
            end
        end
    end
    return e
end

local function nearestTo(list, x, y)
    local best, bestD
    for _, e in ipairs(list) do
        local d = dist(e.x, e.y, x, y)
        if not bestD or d < bestD then best, bestD = e, d end
    end
    return best, bestD
end

local function door(e, exit)
    return { x = e.x, y = e.y, m = e.m, mx = e.mx, my = e.my, name = e.name, seed = e.seed, exit = exit }
end

-- R4: entrada por onde a seta passa. player = { c, x, y, indoors }; target = { c, x, y }.
function Caves.Door(caves, player, target, opts)
    if not (caves and player and target) or player.c ~= target.c then return nil end
    local c, near, merge = player.c, opt(opts, "near"), opt(opts, "merge")
    if player.indoors then
        local here = Caves.Find(caves, c, player.x, player.y, near, opt(opts, "minReach"))
        if not here[1] then return nil end
        for _, e in ipairs(here) do
            if contains(e, target.x, target.y, near) then return nil end
        end
        local e = nearestTo(here, player.x, player.y)
        -- R4 (emenda): só sai quando a entrada está mais perto do alvo que o jogador. Pegada que
        -- ainda não chegou ao alvo não quer dizer que ele está fora (1ª visita).
        if dist(e.x, e.y, target.x, target.y) >= dist(player.x, player.y, target.x, target.y) then return nil end
        return door(confirmed(caves, c, e, merge), true)
    end
    local there = Caves.Find(caves, c, target.x, target.y, near, opt(opts, "minReach"))
    if not there[1] then return nil end
    local e, d = nearestTo(there, player.x, player.y)
    if d <= opt(opts, "arrive") then return nil end
    return door(confirmed(caves, c, e, merge), false)
end

-- R6: título mostrado com a entrada.
function Caves.Title(d, title)
    local name = d.name or "caverna"
    if d.seed then name = name .. " (estimativa)" end
    return string.format("%s: %s · depois: %s", d.exit and "Saída" or "Entrada", name, tostring(title))
end

-- Lista da Content/Caves.lua (coordenada 0–100 da zona) convertida para jardas do mundo.
-- toWorld(mapID, x, y) devolve continente, wx, wy (ou nil). raio em jardas.
function Caves.Seeds(list, toWorld)
    local out = {}
    for _, s in ipairs(list or {}) do
        local c, x, y = toWorld(s.mapID, s.entrance[1], s.entrance[2])
        local cc, cx, cy = toWorld(s.mapID, s.center[1], s.center[2])
        if c and cc == c then
            out[c] = out[c] or {}
            out[c][#out[c] + 1] = { x = x, y = y, m = s.mapID, mx = s.entrance[1], my = s.entrance[2],
                name = s.name, seed = true, cx = cx, cy = cy, radius = s.radius }
        end
    end
    return out
end

-- Junta aprendidas e lista por continente (sem copiar as entradas).
function Caves.Merge(learned, seeds)
    local out = {}
    for _, src in ipairs({ learned or {}, seeds or {} }) do
        for c, list in pairs(src) do
            out[c] = out[c] or {}
            for _, e in ipairs(list) do out[c][#out[c] + 1] = e end
        end
    end
    return out
end

return Caves
