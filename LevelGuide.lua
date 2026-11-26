-- LevelGuide.lua: aba Level (spec 035). Adaptador: junta os hubs da zona atual e das vizinhas
-- (Guide.RankMap), a oferta das outras zonas (Guide.ZoneOffer, spec 029) e a viagem real
-- (Travel.Plan, com os pontos de voo, os transportes e a pedra de lar do jogo).
local _, ns = ...
local LevelGuide = {}
ns.LevelGuide = LevelGuide

local HEARTHSTONE = 6948
local NEAR_MAX, COMEBACK_MAX = 6, 4
LevelGuide.HEARTH_SPELL = 8690

------------------------------------------------------------------------------------------
-- Contexto da viagem (R11)
------------------------------------------------------------------------------------------
local function world(p)
    if not (p and p.mapID and p.x) then return nil end
    local cont, x, y = ns.Planner.WorldPos(p.mapID, p.x, p.y)
    return cont and { cont = cont, x = x, y = y } or nil
end
LevelGuide.World = world

-- Pontos de voo descobertos de um mapa de continente, com posição de mundo: { [cont] = { {x, y, name} } }.
local function addNodes(nodes, cmap)
    if not (cmap and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    for _, p in ipairs(ns.Planner.KnownTaxiPoints(cmap)) do -- spec 044, R8
        local c, w = C_Map.GetWorldPosFromMapPos(cmap, CreateVector2D(p.x / 100, p.y / 100))
        if c and w then
            local x, y = w:GetXY()
            nodes[c] = nodes[c] or {}
            table.insert(nodes[c], { x = x, y = y, name = p.name, mapID = cmap, mx = p.x, my = p.y })
        end
    end
end

local function transports()
    local out = {}
    for _, t in ipairs(ns.Data.TransportPoints((_G.UnitFactionGroup("player")))) do
        local from, to = world(t), world(t.arrival)
        if from and to then
            out[#out + 1] = { from = from, to = to, dest = t.dest, label = (t.kind or "transporte") .. " para " .. tostring(t.dest),
                mapPoint = { mapID = t.mapID, x = t.x, y = t.y } }
        end
    end
    return out
end

-- Pedra de lar: precisa do item e do ponto conhecido (R11); ready = recarga zerada.
local function hearth()
    local bind = ns.FP.db.bind
    local name = _G.GetBindLocation and _G.GetBindLocation()
    if not (bind and bind.mapID and name and bind.name == name) then return nil end
    if (_G.GetItemCount and _G.GetItemCount(HEARTHSTONE) or 0) == 0 then return nil end
    local start, duration = 0, 0
    local cd = (_G.C_Container and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
    if cd then start, duration = cd(HEARTHSTONE) end
    local now = _G.GetTime and _G.GetTime() or 0
    local ready = (start or 0) == 0 or now >= (start or 0) + (duration or 0)
    local left = not ready and ((start or 0) + (duration or 0) - now) or nil -- spec 056, R1
    return { ready = ready, left = left, to = world(bind), name = name }
end

-- Spec 036, R18: o medido no jogo (Content/Measured.lua) substitui a estimativa, campo a campo.
local function measured() return ns.Measured and ns.Measured.travel end

-- Spec 036, R19: "(medido)" só quando todos os trechos do caminho usaram valor medido (constituição 2).
function LevelGuide.EstLabel(plan)
    if not (plan and plan.steps and plan.steps[1]) then return "(est.)" end
    for _, s in ipairs(plan.steps) do
        if not s.measured then return "(est.)" end
    end
    return "(medido)"
end

function LevelGuide.TravelContext(contMaps)
    local db = ns.FP.db
    local t = {}
    for k, v in pairs(db.travel or {}) do t[k] = v end
    for k, v in pairs(measured() or {}) do t[k] = v end
    local nodes = {}
    for cmap in pairs(contMaps or {}) do addNodes(nodes, cmap) end
    local isMeasured = {}
    for k in pairs(measured() or {}) do isMeasured[k] = true end
    return { measured = isMeasured, run = t.run or db.runSpeed or 7, walkFactor = t.walkFactor, fly = t.fly, flyFactor = t.flyFactor,
        flyOverhead = t.flyOverhead, boardWait = t.boardWait, ride = t.ride, hearthSeconds = t.hearthSeconds,
        hearthMinSave = t.hearthMinSave, nodes = nodes, transports = transports(), hearth = hearth(),
        flights = ns.Measured and ns.Measured.flights }
end

------------------------------------------------------------------------------------------
-- Ponto da pedra de lar (R11): onde o jogador estava quando o lar mudou, ou onde chegou com a pedra
------------------------------------------------------------------------------------------
local knownBind, hearthCast = nil, false

local function recordBind(why)
    local p = ns.Planner.PlayerPoint()
    local name = _G.GetBindLocation and _G.GetBindLocation()
    if not (p and p.x and name) then return end
    ns.FP.db.bind = { mapID = p.mapID, x = p.x, y = p.y, name = name }
    knownBind = name
    ns.FP.Fire("BIND", name) -- spec 036, R8
    ns.FP.Debug(string.format("lar: %s em %d %.1f,%.1f (%s)", name, p.mapID, p.x, p.y, why))
end

ns.FP.On("READY", function()
    knownBind = _G.GetBindLocation and _G.GetBindLocation()
    local b = ns.FP.db.bind
    if b and b.name ~= knownBind then ns.FP.db.bind = nil end -- mudou fora do addon: ponto desconhecido
end)
ns.FP.On("SYSTEM_MSG", function()
    C_Timer.After(0.5, function()
        local name = _G.GetBindLocation and _G.GetBindLocation()
        if name and name ~= knownBind then recordBind("estalajadeiro") end
    end)
end)
-- A pedra teleporta no fim do feitiço; com tela de carregamento, a posição só vale depois dela.
-- A marca vale 30 s, para não gravar o lar numa divisa cruzada a pé depois (parecer).
local HEARTH_WINDOW = 30
local function now() return _G.GetTime and _G.GetTime() or 0 end
ns.FP.On("SPELL_DONE", function(spellID)
    if spellID ~= LevelGuide.HEARTH_SPELL then return end
    hearthCast = now()
    C_Timer.After(5, function() if hearthCast then recordBind("pedra de lar") end end)
end)
ns.FP.On("ENTERING_WORLD", function()
    if hearthCast and now() - hearthCast <= HEARTH_WINDOW then
        C_Timer.After(2, function() recordBind("pedra de lar, depois do carregamento"); hearthCast = false end)
    end
end)

------------------------------------------------------------------------------------------
-- Cálculo (R10)
------------------------------------------------------------------------------------------
local function countKept(c, state)
    local n = 0
    for _, k in ipairs(c.kept) do if not state or k.state == state then n = n + 1 end end
    return n
end

-- Destino da viagem: o hub da zona com mais quests da oferta (parecer: a média dos pontos caía
-- no meio do nada em zona com vários polos, como Barrens).
local function offerHub(o, map)
    local kept = {}
    for _, e in ipairs(o.kept or {}) do kept[e.id] = true end
    local best, bestN = nil, 0
    for _, h in ipairs(ns.Guide.Hubs(map)) do
        local n = 0
        for _, q in ipairs(h.questList) do if kept[q] then n = n + 1 end end
        if n > bestN then best, bestN = h, n end
    end
    local p = best and best.points[1]
    return p and { mapID = p.mapID, x = p.x, y = p.y } or nil
end

-- R21: o ponto de entrega mais perto do jogador, o mesmo que a seta usa.
local function finisherOf(q, player)
    local pts = ns.Data.FinisherPoints(q)
    return pts[1] and ns.Planner.Nearest(player, pts) or nil
end

local function deliveryZone(q, player)
    local fin = finisherOf(q, player)
    return fin and ns.Guide.MapZone(fin.mapID)
end

-- Zona de entrega das quests do log: { [zona] = n }.
local function turnInsByZone(player)
    local out = {}
    for _, q in ipairs(ns.Data.LogQuests()) do
        local zone = deliveryZone(q, player)
        if zone then out[zone] = (out[zone] or 0) + 1 end
    end
    return out
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- R18 e R21: quests do log com a zona do ponto de entrega mais perto (o mesmo da seta) e, nas
-- prontas, a viagem até ele (sem pedra em "Perto"). Devolve a lista e o índice por id.
local function logItems(player, pw, nearSet, ctx, nearCtx)
    local D, out, byId = ns.Data, {}, {}
    for _, q in ipairs(D.LogQuests()) do
        local fin = finisherOf(q, player)
        local zone = fin and ns.Guide.MapZone(fin.mapID)
        local it = { id = q, name = D.Q.name(q) or ("Quest " .. q), ready = D.IsReadyForTurnIn(q),
            qLevel = D.Q.questLevel(q), zone = zone, point = fin }
        if it.ready and zone and pw and ctx then
            local fw = world(fin)
            local plan = fw and ns.Travel.Plan(pw, fw, nearSet[zone] and nearCtx or ctx)
            if plan then it.travel, it.plan = plan.seconds, plan end
        end
        out[#out + 1] = it
        byId[q] = it
    end
    return out, byId
end

-- R18: a saída da Leveling.BeforeLeaving com o caminho e o ponto de entrega de volta.
local function beforeLeaving(player, pw, L, nearSet, ctx, nearCtx)
    local items, byId = logItems(player, pw, nearSet, ctx, nearCtx)
    local list = ns.Leveling.BeforeLeaving(items, L, nearSet)
    for _, e in ipairs(list) do
        local it = byId[e.id]
        if it then e.plan, e.point = it.plan, it.point end
    end
    return list
end

-- Contexto da viagem dos continentes da zona atual e das zonas do catálogo; o de "Perto" é sem pedra (R4).
local function travelContexts(hereMap)
    local D = ns.Data
    local contMaps = { [ns.Planner.ContinentMap(hereMap) or 0] = true }
    local cat = D.zoneCatalog
    if cat then
        for zone, z in pairs(cat.zones) do
            local map = z.continent and D.areaToMap[zone]
            if map then contMaps[ns.Planner.ContinentMap(map) or 0] = true end
        end
    end
    contMaps[0] = nil
    local ctx = LevelGuide.TravelContext(contMaps)
    local nearCtx = copy(ctx)
    nearCtx.hearth = nil
    return ctx, nearCtx
end

-- Oferta da zona no nível L (spec 029): reaproveita a da sugestão de zona quando ela é do mesmo
-- nível e da mesma zona de partida (parecer, item 9). Devolve a oferta e o potencial.
local function offerOf(zone, L, cat, p, adv)
    local G, Z = ns.Guide, ns.Zones
    for _, c in ipairs(adv and adv.cands or {}) do
        if c.zone == zone and c.potential then return c.offer, c.potential end
    end
    local o = G.ZoneOffer(cat, zone, L, p)
    local ahead = G.ZoneOffer(cat, zone, math.min(L + p.lookahead, #Z.LEVEL_XP), p)
    return o, math.max(o.value + o.unlock, ahead.value)
end

------------------------------------------------------------------------------------------
-- Trilha por faixa (spec 047): catálogo + viagem real + pontos de voo + lar
------------------------------------------------------------------------------------------
local function mostQuestsHub(map)
    local best
    for _, h in ipairs(ns.Guide.Hubs(map)) do
        if not best or #h.questList > #best.questList then best = h end
    end
    return best
end

-- R5: estalajadeiro mais perto do hub com mais quests da zona recomendada; nil se o lar já é lá.
local function hearthFor(zone)
    local map = zone and zone.map
    local hub = map and mostQuestsHub(map)
    local from = hub and hub.points[1]
    if not from then return nil end
    local inn = ns.Planner.Nearest(from, ns.Data.Innkeepers((_G.UnitFactionGroup("player"))))
    if not inn then return nil end
    local place = ns.Data.PointPlace(inn)
    local bind = _G.GetBindLocation and _G.GetBindLocation()
    if bind and place and place:find(bind, 1, true) then return nil end -- o lar já é lá
    return { point = inn, name = inn.name, place = place }
end

-- R2–R5: a trilha da faixa de L. yield, opcional, a cada zona.
function LevelGuide.Trail(L, yield)
    local D, G, Z = ns.Data, ns.Guide, ns.Zones
    local cat = D.zoneCatalog
    if not (cat and D.Q and D.ready) then return nil end
    local easy = false
    if not L then -- spec 063, R4: só o nível do personagem; o pedido à mão fica como está
        L = UnitLevel("player")
        easy = ns.Leveling.EasyActive(ns.FP.db.easyMode, L)
        if easy then L = math.max(1, L - 3) end
    end
    local lo, hi = Z.Bracket(L)
    local _, hereMap = G.PlayerArea()
    local player = ns.Planner.PlayerPoint() or { mapID = hereMap }
    local pw = world(player)
    local ctx = travelContexts(hereMap)
    local zones = {}
    for zone, z in pairs(cat.zones) do
        local zlo, zhi = G.ZoneLevels(zone)
        local map = D.areaToMap[zone]
        if zlo and map then
            local n, xp = 0, 0
            for _, q in ipairs(z.quests or {}) do
                local info = cat.info[q]
                if info and info.solo and info.level >= lo and info.level <= hi and not D.IsCompleted(q) then
                    n, xp = n + 1, xp + (info.xp or 0)
                end
            end
            if n > 0 then
                local hub = mostQuestsHub(map)
                local dest = hub and hub.points[1]
                local dw = dest and world(dest)
                local plan = pw and dw and ns.Travel.Plan(pw, dw, ctx) -- R3: as regras da seta e dos voos
                local red = 0
                for _, p in ipairs(ns.Planner.FlightNodes(map)) do if p.known == false then red = red + 1 end end
                zones[#zones + 1] = { zone = zone, map = map, lo = zlo, hi = zhi, quests = n, xp = xp,
                    travel = plan and plan.seconds, plan = plan, dest = dest, red = red }
            end
        end
        if yield then yield() end
    end
    local steps = Z.Trail(zones, lo, hi)
    local current = steps[1]
    for _, st in ipairs(steps) do
        local z = st.zones[1]
        if z.lo <= L and z.hi >= L then current = st; break end
    end
    local dungeons = {}
    for _, d in ipairs(ns.DungeonGuide.List() or {}) do
        local a = d.best or d.act
        local dlo = a and (a.minLevelSuggestion or a.minLevel)
        if dlo and dlo >= lo and dlo <= hi then dungeons[#dungeons + 1] = d end
    end
    table.sort(dungeons, function(a, b)
        local x, y = a.best or a.act, b.best or b.act
        return (x.minLevelSuggestion or 0) < (y.minLevelSuggestion or 0)
    end)
    return { lo = lo, hi = hi, level = L, easy = easy, steps = steps, current = current, dungeons = dungeons,
        hearth = current and hearthFor(current.zones[1]) or nil }
end

-- Cálculo completo, síncrono (os testes chamam direto). yield, opcional, a cada hub e a cada zona.
function LevelGuide.Compute(yield)
    local D, G, Z = ns.Data, ns.Guide, ns.Zones
    if not (D.Q and D.ready) then return nil end
    local L = UnitLevel("player")
    local here, hereMap = G.PlayerArea()
    if not here then return nil end
    local player = ns.Planner.PlayerPoint() or { mapID = hereMap }
    local pw = world(player)
    local zones = { here }
    for _, z in ipairs(Z.Neighbors(here, ns.ZoneContent.neighbors)) do zones[#zones + 1] = z end
    local nearSet = {}
    for _, z in ipairs(zones) do nearSet[z] = true end

    -- Contexto da viagem: continentes da zona atual e das candidatas.
    local cat = D.zoneCatalog
    local ctx, nearCtx = travelContexts(hereMap) -- R4: em "Perto" a pedra nunca entra

    -- 1. Perto
    local levelXP = Z.LevelXP(L)
    local near, all = {}, {}
    for _, zone in ipairs(zones) do
        local map = D.areaToMap[zone]
        if map then
            for _, r in ipairs(G.RankMap(map, player, L, yield)) do
                r.zone = zone
                all[#all + 1] = r
                local c = r.circuit
                if #c.stops > 0 and countKept(c) > 0 then
                    local hw = world(r.hub.points[1])
                    local plan = pw and hw and ns.Travel.Plan(pw, hw, nearCtx)
                    local rate = ns.Leveling.HubWorth(c.rate, (c.xp or 0) + (c.mobXP or 0), levelXP, ns.FP.db.hubMinShare) -- R16
                    near[#near + 1] = { key = r.key, name = r.name, zone = zone, rate = rate, rawRate = c.rate,
                        quests = countKept(c, "pegar"), turnIns = countKept(c, "entregar"),
                        seconds = c.seconds, names = c.names, kept = c.kept, plan = plan }
                end
            end
        end
        if yield then yield() end
    end
    table.sort(near, function(a, b) return a.rate > b.rate end)
    while #near > NEAR_MAX do table.remove(near) end

    -- 2. Antes de sair (só o que fica em "Perto"); 4. Volte depois
    local before = beforeLeaving(player, pw, L, nearSet, ctx, nearCtx)
    local comeBack = ns.Leveling.ComeBack(all)
    while #comeBack > COMEBACK_MAX do table.remove(comeBack) end

    -- 3. Vale a viagem: zona contra zona, pelo mesmo modelo (R9)
    local trips, nearRate = {}, 0
    if cat and levelXP and pw then
        local p = G.ZoneParams()
        local adv = G.ZoneAdvice()
        if not (adv and adv.level == L and adv.here == here) then adv = nil end
        local turnIns = turnInsByZone(player)
        local cands = {}
        for zone, z in pairs(cat.zones) do
            local map = D.areaToMap[zone]
            if z.continent and map and #z.quests > 0 then
                local o, potential = offerOf(zone, L, cat, p, adv)
                local plan, dest
                if o.n > 0 then
                    dest = offerHub(o, map)
                    local dw = dest and world(dest)
                    if zone == here then plan = { seconds = 0, steps = {} }
                    elseif dw then plan = ns.Travel.Plan(pw, dw, nearSet[zone] and nearCtx or ctx) end
                end
                if plan then
                    local raw, eff = Z.Effective(o, plan.seconds, potential, levelXP, p.minVisit)
                    if nearSet[zone] then
                        nearRate = math.max(nearRate, eff)
                    else
                        cands[#cands + 1] = { zone = zone, raw = raw, eff = eff, travel = plan.seconds, plan = plan,
                            levels = (o.value + o.unlock) / levelXP, n = o.n, turnIns = turnIns[zone] or 0,
                            dest = dest, estimated = o.estimated }
                    end
                end
            end
            if yield then yield() end
        end
        local db = ns.FP.db
        trips = Z.WorthTrip(cands, nearRate, { zoneStay = db.zoneStay, zoneMinVisit = db.zoneMinVisit, tripMax = 2 })
    end
    return { level = L, here = here, near = near, before = before, trips = trips, comeBack = comeBack,
        nearRate = nearRate }
end

------------------------------------------------------------------------------------------
-- Cálculo em segundo plano (R12)
------------------------------------------------------------------------------------------
local state = { key = nil, result = nil, running = false, pending = false, force = false, turnIns = 0 }
function LevelGuide.Result() return state.result end

-- Chave do cache: nível, entregas, zona, log, posição (quadrado de 5% do mapa) e pedra pronta.
local function readyCount()
    local n = 0
    for _, q in ipairs(ns.Data.LogQuests()) do if ns.Data.IsReadyForTurnIn(q) then n = n + 1 end end
    return n
end

-- R21: a chave inclui as prontas do log (a 5723 ficou pronta sem trocar nada do resto).
local function cacheKey()
    local p = ns.Planner.PlayerPoint() or {}
    local h = hearth()
    return table.concat({ UnitLevel("player"), state.turnIns, tostring(ns.Guide.PlayerArea()), #ns.Data.LogQuests(),
        readyCount(),
        tostring(ns.Data.zoneCatalog ~= nil), tostring(p.mapID), math.floor((p.x or 0) / 5), math.floor((p.y or 0) / 5),
        tostring(h and h.ready), h and h.left and math.floor(h.left / 60) or "-" }, ":") -- spec 056: a espera muda por minuto
end

function LevelGuide.Refresh(force)
    ns.FP.AfterCombat("levelGuide", function()
        if not (ns.Data.Q and ns.Data.ready) then return end
        if state.running then state.pending = true; state.force = state.force or force; return end
        local key = cacheKey()
        if key == state.key and not force then return end
        state.running, state.pending, state.force = true, false, false
        ns.FP.RunCoroutine("levelGuide", LevelGuide.Compute, function(ok, res)
            state.running = false
            if ok then
                state.key, state.result = key, res
            else
                state.key, state.result = nil, { error = tostring(res) }
                ns.FP.Debug("aba Level: erro " .. tostring(res))
            end
            ns.FP.Fire("LEVEL_GUIDE")
            if state.pending then LevelGuide.Refresh(state.force) end
        end)
    end)
end

-- Com a aba aberta (a UI liga isso), recalcula nos eventos da R12.
LevelGuide.watching = false
local function maybe() if LevelGuide.watching then LevelGuide.Refresh() end end
ns.FP.On("LEVEL_UP", function() C_Timer.After(1, maybe) end)
ns.FP.On("ZONE", function() C_Timer.After(2, maybe) end)
ns.FP.On("QUEST_TURNED_IN", function() state.turnIns = state.turnIns + 1; C_Timer.After(3, maybe) end)
ns.FP.On("QUEST_ACCEPTED", function() C_Timer.After(2, maybe) end)
-- R21: o log muda a cada mob; só recalcula quando muda o número de prontas (parecer, revisão 2).
local logQueued, lastReady = false, nil
ns.FP.On("QUEST_LOG", function()
    if logQueued or not LevelGuide.watching then return end
    logQueued = true
    C_Timer.After(2, function()
        logQueued = false
        if not (ns.Data.Q and ns.Data.ready) then return end
        local n = readyCount()
        if n ~= lastReady then lastReady = n; maybe() end
    end)
end)

------------------------------------------------------------------------------------------
-- Ações (R14, R17)
------------------------------------------------------------------------------------------
function LevelGuide.FollowTrip(t)
    ns.FP.AfterCombat("levelTrip", function()
        local leg = ns.Travel.FirstLeg(t.plan)
        local zoneName = ns.Guide.AreaName(t.zone)
        local after = t.after or zoneName -- R20: na entrega, "entregar Quest"
        local db = ns.FP.db
        if leg and leg.kind == "esperar" then -- spec 056: esperar a pedra compensa mais que andar
            ns.FP.Print(leg.label .. " e use; ir a pé leva mais. Depois " .. (t.questID and "use /fp entregar de novo." or ("clique de novo em " .. zoneName .. ".")))
            return
        end
        if leg and leg.kind == "lar" then
            if t.questID then db.guide, db.following, ns.Guide.current = nil, nil, nil end -- parecer: o hub puxaria a seta
            ns.FP.Print("use a pedra de lar (" .. tostring(leg.label) .. "); depois " .. (t.questID and "use /fp entregar de novo." or ("clique de novo em " .. zoneName .. ".")))
            return
        end
        local mapID, x, y, title
        if leg and leg.kind == "voar" and leg.from and leg.from.mapID then
            mapID, x, y = leg.from.mapID, leg.from.mx, leg.from.my
            title = "Voar: " .. leg.label .. " · depois: " .. after
        elseif leg and leg.kind == "transporte" and leg.mapPoint then
            mapID, x, y = leg.mapPoint.mapID, leg.mapPoint.x, leg.mapPoint.y
            title = leg.label .. " · depois: " .. after
        elseif t.dest then
            mapID, x, y, title = t.dest.mapID, t.dest.x, t.dest.y, t.questID and after or ("Ir para " .. zoneName)
        end
        if not mapID then ns.FP.Print("não achei o ponto do primeiro trecho da viagem."); return end
        -- R17: o hub e a quest seguidos puxariam a seta de volta (como em Planner.Follow).
        db.guide, db.following = nil, nil
        ns.Guide.current = nil
        ns.Gps.SetTarget(mapID, x, y, title)
        ns.Guide.tripQuest = t.questID -- spec 058, R4: a entrega da viagem é do plano
        if leg and leg.kind == "voar" and leg.to then ns.Gps.taxiHint = leg.to.name end -- spec 057, R2
        if t.questID then
            ns.FP.Fire("FOLLOW", "entrega", t.questID) -- R20: no diário, a entrega e não "trip"
        else
            ns.FP.Print("viagem: " .. zoneName .. " — " .. ns.Travel.Describe(t.plan) .. " " .. LevelGuide.EstLabel(t.plan))
            ns.FP.Fire("FOLLOW", "trip", t.zone, t.eff) -- spec 036, R9
        end
        ns.FP.Fire("CHANGED")
    end)
end

-- R20: segue a entrega de uma linha de "Antes de sair" (ou da R22, com quiet: ela avisa no chat).
-- Devolve "seguir" ou "viagem".
function LevelGuide.FollowTurnIn(e, quiet)
    local action = ns.Leveling.TurnInAction(e.plan)
    if action == "seguir" then
        ns.Planner.Follow(e.id)
    else
        if not quiet then
            ns.FP.Print(string.format("entrega de %s em %s: %s %s; na chegada, use /fp entregar", tostring(e.name),
                ns.Guide.AreaName(e.zone), ns.Travel.Describe(e.plan), LevelGuide.EstLabel(e.plan)))
        end
        LevelGuide.FollowTrip({ plan = e.plan, zone = e.zone, dest = e.point, questID = e.id,
            after = "entregar " .. tostring(e.name) })
    end
    return action
end

-- R22: a entrega pronta mais perto, de qualquer zona, calculada na hora (sem a aba aberta).
function LevelGuide.NearestTurnIn()
    local D, G = ns.Data, ns.Guide
    if not (D.Q and D.ready) then return nil end
    local here, hereMap = G.PlayerArea()
    local player = ns.Planner.PlayerPoint() or { mapID = hereMap }
    local nearSet = {}
    if here then
        nearSet[here] = true
        for _, z in ipairs(ns.Zones.Neighbors(here, ns.ZoneContent.neighbors)) do nearSet[z] = true end
    end
    local ctx, nearCtx = travelContexts(hereMap)
    return ns.Leveling.NearestReady(beforeLeaving(player, world(player), UnitLevel("player"), nearSet, ctx, nearCtx))
end

return LevelGuide
