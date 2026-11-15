-- Roads.lua: caminho pelas estradas (spec 034). Só funções puras, testadas fora do jogo.
-- Grafo (formato de Content/Roads.lua): nodes = { x1, y1, x2, y2, ... } em jardas do mundo;
-- edges = { { a = i, b = j, pts = { x1, y1, ..., xn, yn }, lig = true|nil }, ... }, com pts do nó a ao nó b.
local _, ns = ...
local Roads = {}
ns.Roads = Roads

local sqrt = math.sqrt

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Polilinha com comprimento acumulado: { xs, ys, cum, len }.
local function polyline(xs, ys)
    local cum = { 0 }
    for k = 2, #xs do cum[k] = cum[k - 1] + dist(xs[k - 1], ys[k - 1], xs[k], ys[k]) end
    return { xs = xs, ys = ys, cum = cum, len = cum[#cum] }
end

-- Projeção de (px, py) na polilinha: distância, posição ao longo (s) e o ponto.
-- Com smin/smax, só procura no trecho da polilinha entre essas posições.
local function project(pl, px, py, smin, smax)
    local bestD, bestS, bx, by
    local xs, ys, cum = pl.xs, pl.ys, pl.cum
    for k = 1, #xs - 1 do
        local seg = cum[k + 1] - cum[k]
        local lo, hi = 0, 1
        if smin and seg > 0 then
            lo = math.max(0, (smin - cum[k]) / seg)
            hi = math.min(1, (smax - cum[k]) / seg)
        elseif smin and (cum[k] < smin or cum[k] > smax) then
            lo = 2 -- segmento de comprimento zero fora da janela: ignora
        end
        if lo <= hi then
            local ax, ay = xs[k], ys[k]
            local dx, dy = xs[k + 1] - ax, ys[k + 1] - ay
            local l2 = dx * dx + dy * dy
            local t = lo
            if l2 > 0 then t = math.max(lo, math.min(hi, ((px - ax) * dx + (py - ay) * dy) / l2)) end
            local qx, qy = ax + t * dx, ay + t * dy
            local d = dist(px, py, qx, qy)
            if not bestD or d < bestD then
                bestD, bestS, bx, by = d, cum[k] + t * seg, qx, qy
            end
        end
    end
    return bestD, bestS, bx, by
end

-- Ponto na posição s da polilinha.
local function pointAt(pl, s)
    local xs, ys, cum = pl.xs, pl.ys, pl.cum
    if s <= 0 then return xs[1], ys[1] end
    for k = 2, #xs do
        if s <= cum[k] then
            local seg = cum[k] - cum[k - 1]
            local t = seg > 0 and (s - cum[k - 1]) / seg or 0
            return xs[k - 1] + t * (xs[k] - xs[k - 1]), ys[k - 1] + t * (ys[k] - ys[k - 1])
        end
    end
    return xs[#xs], ys[#ys]
end

-- Acrescenta a out os pontos da polilinha de s1 a s2 (em qualquer sentido), sem repetir o último.
local function slice(out, pl, s1, s2)
    local function push(x, y)
        local last = out[#out]
        if not (last and math.abs(last.x - x) < 1e-6 and math.abs(last.y - y) < 1e-6) then
            out[#out + 1] = { x = x, y = y }
        end
    end
    push(pointAt(pl, s1))
    local cum = pl.cum
    if s2 >= s1 then
        for k = 1, #cum do if cum[k] > s1 and cum[k] < s2 then push(pl.xs[k], pl.ys[k]) end end
    else
        for k = #cum, 1, -1 do if cum[k] < s1 and cum[k] > s2 then push(pl.xs[k], pl.ys[k]) end end
    end
    push(pointAt(pl, s2))
end

-- Preparo do grafo (polilinhas e vizinhança), guardado por grafo.
local prepared = setmetatable({}, { __mode = "k" })
local function prepare(g)
    local p = prepared[g]
    if p then return p end
    p = { edges = {}, adj = {} }
    for i, e in ipairs(g.edges) do
        local xs, ys = {}, {}
        for k = 1, #e.pts, 2 do xs[#xs + 1] = e.pts[k]; ys[#ys + 1] = e.pts[k + 1] end
        local pl = polyline(xs, ys)
        pl.a, pl.b = e.a, e.b
        p.edges[i] = pl
        p.adj[e.a] = p.adj[e.a] or {}
        p.adj[e.b] = p.adj[e.b] or {}
        table.insert(p.adj[e.a], { to = e.b, edge = i })
        table.insert(p.adj[e.b], { to = e.a, edge = i })
    end
    prepared[g] = p
    return p
end

-- Aresta mais próxima do ponto: índice, distância, posição s.
local function nearestEdge(p, x, y)
    local bestI, bestD, bestS
    for i, pl in ipairs(p.edges) do
        local d, s = project(pl, x, y)
        if d and (not bestD or d < bestD) then bestI, bestD, bestS = i, d, s end
    end
    return bestI, bestD, bestS
end

-- Fila de prioridade (heap binário) por f.
local function push(heap, item)
    heap[#heap + 1] = item
    local i = #heap
    while i > 1 do
        local parent = math.floor(i / 2)
        if heap[parent].f <= heap[i].f then break end
        heap[parent], heap[i] = heap[i], heap[parent]
        i = parent
    end
end
local function pop(heap)
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local i, n = 1, #heap
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            if l <= n and heap[l].f < heap[m].f then m = l end
            if r <= n and heap[r].f < heap[m].f then m = r end
            if m == i then break end
            heap[m], heap[i] = heap[i], heap[m]
            i = m
        end
    end
    return top
end

-- R7: menor caminho de from a to pelas estradas.
function Roads.Path(g, from, to)
    if not (g and g.edges and g.edges[1] and from and to) then return nil end
    local p = prepare(g)
    local ef, df, sf = nearestEdge(p, from.x, from.y)
    local et, dt, st = nearestEdge(p, to.x, to.y)
    if not (ef and et) then return nil end
    local plF, plT = p.edges[ef], p.edges[et]
    local tx, ty = pointAt(plT, st)
    local function nodeXY(i) return g.nodes[2 * i - 1], g.nodes[2 * i] end
    -- custo para sair da aresta de destino por cada nó dela
    local exitCost = { [plT.a] = st, [plT.b] = plT.len - st }
    if plT.a == plT.b then exitCost[plT.a] = math.min(st, plT.len - st) end

    local best, bestEnd = nil, nil
    if ef == et then best, bestEnd = math.abs(st - sf), "direct" end

    local gcost, prev, heap = {}, {}, {}
    local function relax(node, cost, from_, edge)
        if gcost[node] == nil or cost < gcost[node] then
            gcost[node], prev[node] = cost, { node = from_, edge = edge }
            local nx, ny = nodeXY(node)
            push(heap, { node = node, f = cost + dist(nx, ny, tx, ty), g = cost })
        end
    end
    relax(plF.a, sf, nil, ef)
    relax(plF.b, plF.len - sf, nil, ef)
    while #heap > 0 do
        local cur = pop(heap)
        if best and cur.f >= best then break end
        if cur.g == gcost[cur.node] then
            local exit = exitCost[cur.node]
            if exit and (not best or cur.g + exit < best) then best, bestEnd = cur.g + exit, cur.node end
            for _, nb in ipairs(p.adj[cur.node] or {}) do
                relax(nb.to, cur.g + p.edges[nb.edge].len, cur.node, nb.edge)
            end
        end
    end
    if not best then return nil end

    local points = {}
    if bestEnd == "direct" then
        slice(points, plF, sf, st)
    else
        -- cadeia de nós do fim até o começo
        local chain, node = {}, bestEnd
        while node do
            table.insert(chain, 1, { node = node, edge = prev[node].edge, from = prev[node].node })
            node = prev[node].node
        end
        -- em aresta de laço (a == b), o lado é o mais curto, o mesmo do custo
        local function side(pl, s, endNode)
            if pl.a == pl.b then return s <= pl.len - s and 0 or pl.len end
            return endNode == pl.a and 0 or pl.len
        end
        slice(points, plF, sf, side(plF, sf, chain[1].node))
        for k = 2, #chain do
            local pl = p.edges[chain[k].edge]
            if chain[k].from == pl.a then slice(points, pl, 0, pl.len) else slice(points, pl, pl.len, 0) end
        end
        slice(points, plT, side(plT, st, bestEnd), st)
    end
    return { points = points, accessFrom = df, accessTo = dt, road = best }
end

-- R9: ponto ahead jardas à frente da projeção de pos; devolve (ponto, distância à polilinha, jardas até o fim).
-- Com state, lembra o avanço (state.s) e procura perto dele, para não pular de perna num grampo;
-- sem achar nada a até state.lost jd (padrão 60) na janela, procura na polilinha inteira.
local AIM_BACK, AIM_FWD, AIM_LOST = 30, 200, 60
local polylines = setmetatable({}, { __mode = "k" })
function Roads.Aim(points, pos, ahead, state)
    if not (points and points[1] and pos) then return nil end
    local pl = polylines[points]
    if not pl then
        local xs, ys = {}, {}
        for i, pt in ipairs(points) do xs[i], ys[i] = pt.x, pt.y end
        pl = polyline(xs, ys)
        polylines[points] = pl
    end
    if #pl.xs == 1 then return { x = pl.xs[1], y = pl.ys[1] }, dist(pos.x, pos.y, pl.xs[1], pl.ys[1]), 0 end
    local d, s
    if state and state.s then d, s = project(pl, pos.x, pos.y, state.s - AIM_BACK, state.s + AIM_FWD) end
    if not d or d > (state and state.lost or AIM_LOST) then d, s = project(pl, pos.x, pos.y) end
    if state then state.s = s end
    local ax, ay = pointAt(pl, math.min(pl.len, s + (ahead or 0)))
    return { x = ax, y = ay }, d, pl.len - s
end

return Roads
