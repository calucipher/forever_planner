-- Dungeons.lua: entrada de masmorra, meeting stone e attune (spec 041). Núcleo puro: tudo chega
-- por parâmetro, em coordenada do mundo (c, x, y em jardas). Sem API do jogo nem db.
-- O adaptador é DungeonGuide.lua.
local _, ns = ...
ns = ns or {}
local Dungeons = {}
ns.Dungeons = Dungeons

local DEFAULTS = { merge = 60, stoneMax = 500, same = 5, trust = 1000 }
local function opt(opts, k) return (opts and opts[k]) or DEFAULTS[k] end

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Nome sem "The ", sem caixa, sem pontuação e sem o que vem entre parênteses.
function Dungeons.Norm(name)
    local s = tostring(name or ""):lower()
    s = s:gsub("%b()", ""):gsub("[%-:]", " "):gsub("[^%w%s]", ""):gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the ", "")
    return s
end

local function keyOf(name, aliases)
    local n = Dungeons.Norm(name)
    return (aliases and aliases[n]) or n
end

local function copyPoint(p, extra)
    local e = { c = p.c, x = p.x, y = p.y, m = p.m, mx = p.mx, my = p.my }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

-- Acrescenta a entrada se não houver outra da mesma masmorra a até `same` jardas.
local function addEntrance(d, p, extra, same)
    if not (p and p.c and p.x and p.y) then return end
    for _, e in ipairs(d.entrances) do
        if e.c == p.c and dist(e, p) <= same then return end
    end
    d.entrances[#d.entrances + 1] = copyPoint(p, extra)
end

-- R1: aprendida substitui as não aprendidas a até `merge` jd; senão é acrescentada.
-- R1a: longe (mais de `trust` jd) de todas as não aprendidas, veio de invocação ou teleporte.
local function addLearned(d, p, merge, trust)
    if not (p and p.c and p.x and p.y) then return end
    local known, near = false, false
    for _, e in ipairs(d.entrances) do
        if not e.learned then
            known = true
            if e.c == p.c and dist(e, p) <= trust then near = true end
        end
    end
    if known and not near then return end
    local keep = {}
    for _, e in ipairs(d.entrances) do
        if e.learned or e.c ~= p.c or dist(e, p) > merge then keep[#keep + 1] = e end
    end
    d.entrances = keep
    addEntrance(d, p, { learned = true }, DEFAULTS.same)
end

local function nearestStone(d, stones, maxD)
    local best, bestD
    for _, s in ipairs(stones or {}) do
        for _, e in ipairs(d.entrances) do
            if s.c == e.c then
                local dd = dist(s, e)
                if dd <= maxD and (not bestD or dd < bestD) then best, bestD = s, dd end
            end
        end
    end
    return best
end

-- R1/R2: src = { questie, seeds, learned, stones, acts, aliases, attunes }.
--   questie/seeds: { { name, points = { {c, x, y, m, mx, my}, ... } } }
--   learned: { [nome da instância] = { {c, x, y, m, mx, my}, ... } }
--   acts: atividades de masmorra do LFG { name, minLevel, minLevelSuggestion, maxLevelSuggestion, ... }
function Dungeons.Build(src, opts)
    local aliases, byKey, order = src.aliases or {}, {}, {}
    local function get(name)
        local k = keyOf(name, aliases)
        if k == "" then return nil end
        if not byKey[k] then
            byKey[k] = { key = k, name = name, entrances = {}, acts = {} }
            order[#order + 1] = k
        end
        return byKey[k]
    end
    local same = opt(opts, "same")
    for _, q in ipairs(src.questie or {}) do
        local d = get(q.name)
        if d then for _, p in ipairs(q.points or {}) do addEntrance(d, p, nil, same) end end
    end
    for _, s in ipairs(src.seeds or {}) do
        local d = get(s.name)
        if d and #d.entrances == 0 then -- a lista só vale para quem não tem entrada na QuestieDB
            for _, p in ipairs(s.points or {}) do addEntrance(d, p, { est = true, source = s.source }, same) end
        end
    end
    for iname, pts in pairs(src.learned or {}) do
        local d = get(iname)
        if d then for _, p in ipairs(pts) do addLearned(d, p, opt(opts, "merge"), opt(opts, "trust")) end end
    end
    local acts = src.acts or {}
    for _, a in ipairs(acts) do
        local d = get(a.name) -- atividade sem entrada conhecida também entra (R2)
        if d then d.acts[#d.acts + 1] = a end
    end
    local out = {}
    for _, k in ipairs(order) do
        local d = byKey[k]
        if #acts == 0 or #d.acts > 0 then
            table.sort(d.acts, function(a, b) return (a.minLevelSuggestion or 0) < (b.minLevelSuggestion or 0) end)
            d.act = d.acts[1]
            d.stone = nearestStone(d, src.stones, opt(opts, "stoneMax"))
            d.attune = src.attunes and src.attunes[k] or nil
            out[#out + 1] = d
        end
    end
    return out
end

-- R3: masmorras "para você": Fit entre 0 e 3, em ordem do mínimo sugerido.
function Dungeons.ForPlayer(list, L)
    local Lfg = ns.Lfg
    local out = {}
    for _, d in ipairs(list or {}) do
        local a = Lfg.BestActivity(d.acts, L)
        local fit = a and Lfg.Fit(a, L)
        if fit and fit >= 0 and fit <= 3 then
            d.best, d.fit = a, fit
            out[#out + 1] = d
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a.best.minLevelSuggestion or 0, b.best.minLevelSuggestion or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return out
end

-- R4: pinos de um mapa. project(c, x, y) devolve u, v (0–1) ou nil.
function Dungeons.InMap(list, project)
    local pins = {}
    local function try(d, kind, p)
        if not p then return end
        local u, v = project(p.c, p.x, p.y)
        if u and v and u >= 0 and u <= 1 and v >= 0 and v <= 1 then
            pins[#pins + 1] = { d = d, kind = kind, u = u, v = v, p = p }
        end
    end
    for _, d in ipairs(list or {}) do
        for _, e in ipairs(d.entrances) do try(d, "entrance", e) end
        try(d, "stone", d.stone)
    end
    return pins
end

-- R5: aprende a entrada ao entrar na instância. s = { c, x, y, m, mx, my } fora,
-- { instance = true, iname } dentro, nil em taxi/morto/sem posição. Devolve verdadeiro ao gravar.
function Dungeons.Learn(store, state, s, opts)
    if not s then state.out = nil; return false end
    if not s.instance then
        state.inst = false
        state.out = s.c and s or nil
        return false
    end
    local was, o = state.inst, state.out
    state.inst, state.out = true, nil
    if was ~= false or not o or not s.iname or s.iname == "" then return false end
    store[s.iname] = store[s.iname] or {}
    local list = store[s.iname]
    for _, e in ipairs(list) do
        if e.c == o.c and dist(e, o) <= opt(opts, "merge") then return false end
    end
    list[#list + 1] = copyPoint(o)
    return true
end

-- R6: estado do attune. def[faction] = passos; done(questID) diz se a quest foi feita.
function Dungeons.Attune(def, faction, done)
    local steps = def and def[faction]
    if not steps or #steps == 0 then return nil end
    local last = 0
    for i, st in ipairs(steps) do
        if st.quest and done(st.quest) then last = i end
    end
    if last == #steps then return { done = true } end
    return { next = steps[last + 1], index = last + 1, total = #steps }
end

return Dungeons
