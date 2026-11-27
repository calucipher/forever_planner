-- Travel.lua: tempo de viagem real entre dois pontos de mundo (spec 035, R1–R5). Puro: sem API do jogo.
-- Pontos { cont, x, y } em jardas do mundo. O contexto (pontos de voo, transportes, pedra de lar)
-- vem do adaptador (LevelGuide.lua).
local _, ns = ...
local L = ns.L -- spec 066
local Travel = {}
ns.Travel = Travel

local function span(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function nearestNode(p, nodes)
    local best, bestD
    for _, n in ipairs(nodes or {}) do
        local d = span(p, n)
        if not bestD or d < bestD then best, bestD = n, d end
    end
    return best, bestD
end

local function isMeasured(ctx, key) return ctx.measured ~= nil and ctx.measured[key] == true end

local function walkStep(a, b, ctx)
    return { kind = "andar", seconds = span(a, b) * ctx.walkFactor / ctx.run, point = b, measured = isMeasured(ctx, "run") }
end

-- R2: mesmo continente, o menor entre andar e voar. Devolve { seconds, steps }.
local function sameContinent(a, b, ctx)
    local walk = walkStep(a, b, ctx)
    local best = { seconds = walk.seconds, steps = { walk } }
    local nodes = ctx.nodes and ctx.nodes[a.cont]
    local na = nearestNode(a, nodes)
    local nb = nearestNode(b, nodes)
    if na and nb and na ~= nb then
        local s1 = walkStep(a, na, ctx)
        local label = string.format("%s > %s", tostring(na.name), tostring(nb.name))
        -- spec 036, R18: tempo medido da rota, quando houver; senão, a conta por distância
        local measured = ctx.flights and ctx.flights[label]
        local fly = { kind = "voar", seconds = measured or (ctx.flyOverhead + span(na, nb) * ctx.flyFactor / ctx.fly),
            label = label, point = na, from = na, to = nb, measured = measured ~= nil or isMeasured(ctx, "fly") }
        local s3 = walkStep(nb, b, ctx)
        local total = s1.seconds + fly.seconds + s3.seconds
        if total < best.seconds then best = { seconds = total, steps = { s1, fly, s3 } } end
    end
    return best
end

local function concat(...)
    local out, seconds = {}, 0
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        seconds = seconds + part.seconds
        for _, s in ipairs(part.steps) do out[#out + 1] = s end
    end
    return { seconds = seconds, steps = out }
end

-- R2 e R3: sem pedra de lar.
local function plain(a, b, ctx)
    if a.cont == b.cont then return sameContinent(a, b, ctx) end
    local best
    for _, t in ipairs(ctx.transports or {}) do
        if t.from.cont == a.cont and t.to.cont == b.cont then
            local ride = { seconds = ctx.boardWait + ctx.ride, steps = { { kind = "transporte",
                seconds = ctx.boardWait + ctx.ride, label = t.label or (L["transporte para "] .. tostring(t.dest)),
                point = t.from, mapPoint = t.mapPoint, dest = t.dest,
                measured = isMeasured(ctx, "boardWait") and isMeasured(ctx, "ride") } } }
            local total = concat(sameContinent(a, t.from, ctx), ride, sameContinent(t.to, b, ctx))
            if not best or total.seconds < best.seconds then best = total end
        end
    end
    return best
end

-- R1, R4: caminho mais rápido, com a pedra de lar se ela estiver pronta.
function Travel.Plan(from, to, ctx)
    if not (from and to and from.cont and to.cont) then return nil end
    local best = plain(from, to, ctx)
    local h = ctx.hearth
    -- spec 056, R2: em recarga, esperar pode compensar, até hearthMaxWait (parecer: tempo parado vale menos)
    local wait = h and not h.ready and h.left and h.left <= (ctx.hearthMaxWait or 600) and h.left
    if h and (h.ready or wait) and h.to then
        local after = plain(h.to, to, ctx)
        if after then
            local stone = { seconds = ctx.hearthSeconds, steps = { { kind = "lar", seconds = ctx.hearthSeconds,
                label = L["pedra de lar"] .. (h.name and (" (" .. h.name .. ")") or ""), point = from,
                measured = isMeasured(ctx, "hearthSeconds") } } }
            local total = concat(stone, after)
            if wait then
                total = concat({ seconds = wait, steps = { { kind = "esperar", seconds = wait, point = from,
                    label = string.format(L["espere a pedra de lar (%d min)"], math.max(1, math.floor(wait / 60 + 0.5))) } } }, total)
            end
            -- a recarga é de cerca de 1 hora: só vale se poupar pelo menos hearthMinSave
            if not best or total.seconds + (ctx.hearthMinSave or 0) <= best.seconds then best = total end
        end
    end
    return best
end

local function minutes(s) return math.max(1, math.floor(s / 60 + 0.5)) end

-- R5: texto curto do caminho.
function Travel.Describe(plan)
    if not plan then return L["sem caminho conhecido"] end
    local parts = {}
    for _, s in ipairs(plan.steps) do
        if s.kind == "voar" then parts[#parts + 1] = L["voo "] .. (s.label or "?")
        elseif s.kind == "transporte" then parts[#parts + 1] = s.label or "transporte"
        elseif s.kind == "lar" or s.kind == "esperar" then parts[#parts + 1] = s.label or L["pedra de lar"] end -- spec 056, R3
    end
    if #parts == 0 then return string.format(L["a pé ~%d min"], minutes(plan.seconds)) end
    parts[#parts + 1] = string.format(L["~%d min"], minutes(plan.seconds))
    return table.concat(parts, " · ")
end

-- R14: primeiro trecho que não é andar (para onde a seta aponta), ou nil se o caminho é a pé.
function Travel.FirstLeg(plan)
    for _, s in ipairs(plan and plan.steps or {}) do
        if s.kind ~= "andar" then return s end
    end
    return nil
end

return Travel
