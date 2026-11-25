-- Nav.lua: caminho a pé pela malha de relevo (spec 050). Núcleo puro: decodifica a malha gerada
-- (Content/Nav.lua) e acha o menor caminho com A*. Não chama a API do jogo.
local _, ns = ...
local Nav = {}
ns.Nav = Nav

local RIGHT, DOWN = 1, 2
local SQRT2 = math.sqrt(2)

-- R2: "a3d2b1" -> { 0, 0, 0, 3, 3, 1 } (a–d = 0–3, seguido da contagem).
function Nav.Row(s)
    local out = {}
    for ch, n in tostring(s or ""):gmatch("(%a)(%d+)") do
        local code = ch:byte() - 97
        for _ = 1, tonumber(n) do out[#out + 1] = code end
    end
    return out
end

local function has(code, bit) return code % (bit * 2) >= bit end

-- Pode ir de (r, c) para (r + dr, c + dc), com dr, dc em -1..1 (sem diagonal).
local function step(cell, r, c, dr, dc)
    if dr == 0 and dc == 1 then return has(cell(r, c), RIGHT) end
    if dr == 0 and dc == -1 then return has(cell(r, c - 1), RIGHT) end
    if dr == 1 and dc == 0 then return has(cell(r, c), DOWN) end
    if dr == -1 and dc == 0 then return has(cell(r - 1, c), DOWN) end
    return false
end

-- Diagonal: vale só se os dois caminhos em L valem.
local function move(cell, r, c, dr, dc)
    if dr == 0 or dc == 0 then return step(cell, r, c, dr, dc) end
    return step(cell, r, c, dr, 0) and step(cell, r + dr, c, 0, dc)
        and step(cell, r, c, 0, dc) and step(cell, r, c + dc, dr, 0)
end

-- Fila de prioridade (heap binário) de { f, key }.
local function push(h, f, key)
    h[#h + 1] = { f, key }
    local i = #h
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p][1] <= h[i][1] then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end
local function pop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            if h[l] and h[l][1] < h[m][1] then m = l end
            if h[r] and h[r][1] < h[m][1] then m = r end
            if m == i then break end
            h[m], h[i] = h[i], h[m]
            i = m
        end
    end
    return top
end

-- R2: A* de from a to ({ linha, coluna }), 8 vizinhos, numa janela em volta dos dois.
-- Devolve a lista de células { r, c } do começo ao fim, ou nil.
function Nav.Path(cell, from, to, opts)
    local margin = (opts and opts.margin) or 40
    local maxN = (opts and opts.max) or 60000
    local yield = opts and opts.yield
    local r0 = math.min(from[1], to[1]) - margin
    local r1 = math.max(from[1], to[1]) + margin
    local c0 = math.min(from[2], to[2]) - margin
    local c1 = math.max(from[2], to[2]) + margin
    local W = c1 - c0 + 1
    local function key(r, c) return (r - r0) * W + (c - c0) end
    local function h(r, c)
        local dr, dc = math.abs(r - to[1]), math.abs(c - to[2])
        return math.max(dr, dc) + (SQRT2 - 1) * math.min(dr, dc)
    end
    local g, prev, closed, heap = {}, {}, {}, {}
    local start = key(from[1], from[2])
    g[start] = 0
    push(heap, h(from[1], from[2]), start)
    local goal = key(to[1], to[2])
    local n = 0
    while #heap > 0 do
        local k = pop(heap)[2]
        if k == goal then break end
        if not closed[k] then
            closed[k] = true
            n = n + 1
            if n > maxN then return nil end
            if yield and n % 2000 == 0 then yield() end
            local r, c = math.floor(k / W) + r0, k % W + c0
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local nr, nc = r + dr, c + dc
                    if (dr ~= 0 or dc ~= 0) and nr >= r0 and nr <= r1 and nc >= c0 and nc <= c1
                        and move(cell, r, c, dr, dc) then
                        local nk = key(nr, nc)
                        local ng = g[k] + ((dr ~= 0 and dc ~= 0) and SQRT2 or 1)
                        if not closed[nk] and (not g[nk] or ng < g[nk]) then
                            g[nk], prev[nk] = ng, k
                            push(heap, ng + h(nr, nc), nk)
                        end
                    end
                end
            end
        end
    end
    if not g[goal] then return nil end
    local path, k = {}, goal
    while k do
        table.insert(path, 1, { math.floor(k / W) + r0, k % W + c0 })
        k = prev[k]
    end
    return path
end

return Nav
