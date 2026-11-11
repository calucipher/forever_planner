-- Guide.lua: guia de leveling por hub (spec 002). Adaptador: lê Data/Planner/Scoring e
-- entrega para as regras puras de Leveling. Também segue o circuito no GPS.
local _, ns = ...
local Util = ns.Util
local Guide = {}
ns.Guide = Guide

local CACHE_SECONDS = 2 -- R25
-- Quem dá quest e aparece em muitos lugares (galinha, mob que anda) não ancora hub:
-- os spawns dele ligariam a zona inteira num hub só. A quest dele vai para o hub da entrega.
local MAX_ANCHOR_SPAWNS = 5

------------------------------------------------------------------------------------------
-- Hubs estáticos por mapa (D3)
------------------------------------------------------------------------------------------
local hubsByMap = {}

local function pointKey(p) return string.format("%d:%.2f:%.2f", p.mapID or 0, p.x or 0, p.y or 0) end

local function hubName(hub)
    local count, best = {}, nil
    for _, p in ipairs(hub.points) do
        local src = p.source
        if type(src) == "number" then
            count[src] = (count[src] or 0) + (hub.questsAt[pointKey(p)] or 0)
            if not best or count[src] > count[best] then best = src end
        end
    end
    local name = best and ns.Data.N.name(best)
    return name and ("Hub de " .. name) or ("Hub " .. hub.key)
end

function Guide.Hubs(mapID)
    if hubsByMap[mapID] then return hubsByMap[mapID] end
    local D = ns.Data
    local points, byKey, questsOf, floating = {}, {}, {}, {}
    local spawnsOf = {}
    local function anchors(pts)
        local out = {}
        for _, p in ipairs(pts) do spawnsOf[p.source or "?"] = (spawnsOf[p.source or "?"] or 0) + 1 end
        for _, p in ipairs(pts) do
            if p.mapID == mapID and (spawnsOf[p.source or "?"] or 0) <= MAX_ANCHOR_SPAWNS then out[#out + 1] = p end
        end
        return out
    end
    for _, q in ipairs(D.QuestsForMap(mapID)) do
        spawnsOf = {}
        local pts = anchors(D.StarterPoints(q))
        if #pts == 0 then floating[#floating + 1] = q end
        for _, p in ipairs(pts) do
            local k = pointKey(p)
            if not byKey[k] then byKey[k] = p; points[#points + 1] = p; questsOf[k] = {} end
            table.insert(questsOf[k], q)
        end
    end
    local radius = ns.FP.db.hubRadius or 80
    local hubs = {}
    for _, group in ipairs(ns.Leveling.Cluster(points, radius, ns.Planner.Distance)) do
        local hub = { points = {}, quests = {}, questList = {}, questsAt = {} }
        for _, i in ipairs(group) do
            local p = points[i]
            local k = pointKey(p)
            hub.points[#hub.points + 1] = p
            hub.questsAt[k] = #questsOf[k]
            for _, q in ipairs(questsOf[k]) do
                if not hub.quests[q] then hub.quests[q] = true; hub.questList[#hub.questList + 1] = q end
            end
        end
        hub.key = mapID .. ":" .. pointKey(hub.points[1])
        hub.name = hubName(hub)
        hubs[#hubs + 1] = hub
    end
    -- Quests sem âncora: entram no hub mais perto de quem recebe (se a entrega for neste mapa).
    for _, q in ipairs(floating) do
        local fin
        for _, p in ipairs(D.FinisherPoints(q)) do if p.mapID == mapID then fin = p; break end end
        local h = fin and Guide.NearestHub(hubs, fin)
        if h and not h.quests[q] then h.quests[q] = true; h.questList[#h.questList + 1] = q end
    end
    hubsByMap[mapID] = hubs
    return hubs
end

-- R5 (spec 006): de caverna/cidade sobe até o mapa da zona (mapType 3 = zona).
local ZONE_MAP_TYPE = 3
function Guide.ZoneMap(mapID)
    local guard = 0
    while mapID and guard < 5 do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        if not (info and info.mapType and info.mapType > ZONE_MAP_TYPE and info.parentMapID) then break end
        mapID, guard = info.parentMapID, guard + 1
    end
    return mapID
end

-- Hub mais perto de um ponto (entrega de quest do log, R16)
function Guide.NearestHub(hubs, p)
    local best, bestD
    for _, h in ipairs(hubs) do
        for _, hp in ipairs(h.points) do
            local d = ns.Planner.Distance(p, hp)
            if d and (not bestD or d < bestD) then best, bestD = h, d end
        end
    end
    return best
end

------------------------------------------------------------------------------------------
-- Circuito de um hub
------------------------------------------------------------------------------------------
local function questInfo(q, level, requires)
    local D = ns.Data
    local objectives, elite, dungeon = D.Objectives(q, level, ns.FP.MobXPFactor())
    local bestItem, delta = ns.Scoring.BestReward(D.Rewards(q))
    local trainSkill, trainOn = ns.ClassGuide.MissingSkillFor(bestItem) -- spec 011, R6
    delta = ns.Milestones.EffectiveDelta(delta, trainSkill)
    return {
        bag = D.IsBagQuest(q), -- spec 010
        weapon = ns.Milestones.IsWeaponUpgrade(ns.ClassGuide.ItemClass(bestItem), delta, trainSkill), -- spec 012
        trainSkill = trainSkill, trainOn = trainOn, -- trainOn: arma habilitada na janela Armas (spec 016)
        id = q, name = D.Q.name(q) or ("Quest " .. q), state = ns.Planner.State(q),
        xp = (D.QuestXP(q, level)), money = D.QuestMoney(q), delta = delta,
        starters = D.StarterPoints(q), finishers = D.FinisherPoints(q),
        objectives = objectives, elite = elite, dungeon = dungeon, requires = requires,
        qLevel = D.Q.questLevel(q), -- spec 025
    }
end

local function params()
    local db = ns.FP.db
    return {
        ttk = ns.FP.KillSeconds(), downtime = 0, speed = db.runSpeed or 7, threshold = db.threshold or 0.5,
        levelXP = Util.Num(_G.UnitXPMax and _G.UnitXPMax("player")) or 0,
        upgradePerPoint = db.upgradePerPoint, upgradeCap = db.upgradeCap,
        rested = Util.Num(_G.GetXPExhaustion and _G.GetXPExhaustion()) or 0,
        goldToXP = db.goldToXP, logFree = ns.Data.LogFree(),
        playerLevel = UnitLevel("player"), -- spec 025
    }
end

local failures = { count = 0, first = nil }
Guide.failures = failures

local function safeInfo(q, level, requires)
    local ok, info = pcall(questInfo, q, level, requires)
    if ok then return info end
    failures.count = failures.count + 1
    failures.first = failures.first or ("quest " .. q .. ": " .. tostring(info))
    return nil
end

-- Satélites (spec 008): quest de hub com menos de 2 quests para pegar, entregue neste hub.
-- Devolve { [questID] = desvio em jardas }.
local MIN_HUB_QUESTS = 2
local function onMap(points, mapID)
    for _, p in ipairs(points) do if p.mapID == mapID then return p end end
end
local function findSatellites(hub, hubs, level, player)
    local D, dist = ns.Data, ns.Planner.Distance
    local radius = ns.FP.db.hubRadius or 80
    local out = {}
    for _, other in ipairs(hubs) do
        if other ~= hub then
            local pickable = {}
            for _, q in ipairs(other.questList) do
                if not D.IsOnQuest(q) and D.IsEligible(q, level) and D.IsRelevant(q, level) then
                    pickable[#pickable + 1] = q
                end
            end
            if #pickable > 0 and #pickable < MIN_HUB_QUESTS then
                for _, q in ipairs(pickable) do
                    local fin = onMap(D.FinisherPoints(q), hub.points[1].mapID)
                    local start = onMap(D.StarterPoints(q), hub.points[1].mapID)
                    local h = fin and Guide.NearestHub(hubs, fin)
                    local near = false
                    if h == hub then
                        for _, p in ipairs(hub.points) do
                            local d = dist(fin, p)
                            if d and d <= radius then near = true; break end
                        end
                    end
                    if near and start then
                        local a = dist(player, start) or 0
                        local b = dist(start, hub.points[1]) or 0
                        local c = dist(player, hub.points[1]) or 0
                        out[q] = math.max(a + b - c, 0) -- R3
                    end
                end
            end
        end
    end
    return out
end

-- logByHub: quests do log deste hub (R1 da spec 006: cada uma num hub só).
local function buildCircuit(hub, level, player, logByHub, hubs)
    local D = ns.Data
    local list, seen = {}, {}
    local function add(info) if info and not seen[info.id] then seen[info.id] = true; list[#list + 1] = info end end
    for _, q in ipairs(hub.questList) do
        if D.IsEligible(q, level) and D.IsRelevant(q, level) then add(safeInfo(q, level)) end
    end
    for _, q in ipairs(logByHub[hub.key] or {}) do add(safeInfo(q, level)) end
    -- Satélites (spec 008). R5: no hub seguido, o conjunto fica congelado.
    local g = ns.FP.db.guide
    local frozen = g and g.hub == hub.key and g.satellites
    local satellites, satIDs = {}, {}
    if frozen then
        for q in pairs(frozen) do
            if not D.IsCompleted(q) and (D.IsOnQuest(q) or D.IsEligible(q, level)) then satellites[q] = 0 end
        end
    else
        satellites = findSatellites(hub, hubs, level, player)
    end
    local speed = ns.FP.db.runSpeed or 7
    local maxDetour = ns.FP.db.satelliteMaxDetour or 400
    for q, detour in pairs(satellites) do
        if not seen[q] then
            local info = safeInfo(q, level)
            if info then
                info.extraSeconds, info.satellite = detour / speed, true
                if detour > maxDetour then info.forceAside = "desvio" end -- R4
                add(info)
                satIDs[#satIDs + 1] = q
            end
        end
    end
    -- Segunda volta (R13): quest do hub que libera ao concluir quests do circuito, seja a
    -- seguinte da cadeia, seja por pré-requisito. Entra depois da entrega das que ela depende.
    local inCircuit = {}
    for _, info in ipairs(list) do inCircuit[info.id] = true end
    local nextOf = {}
    for _, info in ipairs(list) do
        local n = D.NextInChain(info.id)
        if n then nextOf[n] = nextOf[n] or {}; table.insert(nextOf[n], info.id) end
    end
    for _, q in ipairs(hub.questList) do
        if not seen[q] and not D.IsCompleted(q) then
            local done = setmetatable({}, { __index = function(_, p) return D.IsCompleted(p) end })
            local requires, any = ns.Leveling.CircuitRequires(D.Q.preQuestSingle(q), D.Q.preQuestGroup(q),
                nextOf[q], inCircuit, done) -- spec 002, R13a
            if #requires > 0 and D.IsEligible(q, level, inCircuit) and D.IsRelevant(q, level) then
                local info = safeInfo(q, level, requires)
                if info then info.requiresAny = any end
                add(info)
            end
        end
    end
    local c = ns.Leveling.BuildCircuit(list, player, params(), ns.Planner.Distance)
    local names, keptSet = {}, {}
    for _, info in ipairs(list) do
        names[info.id] = info.name .. (info.requires and " (cont.)" or "") .. (info.satellite and " (no caminho)" or "")
            .. (info.bag and " (bolsa)" or "") .. (info.weapon and " (arma)" or "") .. (info.trainSkill and info.trainOn and (" (treine " .. info.trainSkill .. ")") or "")
    end
    for _, k in ipairs(c.kept) do keptSet[k.id] = true end
    c.names, c.satellites = names, {}
    for _, q in ipairs(satIDs) do if keptSet[q] then c.satellites[q] = true end end
    return c
end

------------------------------------------------------------------------------------------
-- Ranking de hubs (R14) com cache (R25)
------------------------------------------------------------------------------------------
local cache = { key = nil, at = 0, rows = nil }

function Guide.Invalidate() cache.key, cache.rows = nil, nil end

function Guide.Rank(mapID)
    local D = ns.Data
    if not D.Q then return {} end
    local level = UnitLevel("player")
    local player = ns.Planner.PlayerPoint() or { mapID = mapID }
    mapID = mapID or Guide.ZoneMap(player.mapID)
    local key = mapID .. ":" .. level
    local now = _G.GetTime and _G.GetTime() or 0
    if cache.key == key and cache.rows and now - cache.at < CACHE_SECONDS then return cache.rows end

    failures.count, failures.first = 0, nil
    local hubs = Guide.Hubs(mapID)
    local logByHub = {}
    for _, q in ipairs(D.LogQuests()) do
        local anchor
        for _, p in ipairs(D.FinisherPoints(q)) do if p.mapID == mapID then anchor = p; break end end
        if not anchor then
            for _, p in ipairs(D.PendingObjectivePoints(q, level)) do if p.mapID == mapID then anchor = p; break end end
        end
        local h = anchor and Guide.NearestHub(hubs, anchor)
        if h then logByHub[h.key] = logByHub[h.key] or {}; table.insert(logByHub[h.key], q) end
    end
    local rows = {}
    for _, hub in ipairs(hubs) do
        local c = buildCircuit(hub, level, player, logByHub, hubs)
        if #c.kept > 0 or #c.aside > 0 then
            local ready = 0
            for _, k in ipairs(c.kept) do if k.state == "entregar" then ready = ready + 1 end end
            rows[#rows + 1] = { key = hub.key, name = hub.name, hub = hub, circuit = c, ready = ready,
                dist = ns.Planner.Distance(player, hub.points[1]) }
        end
    end
    table.sort(rows, function(a, b) return a.circuit.rate > b.circuit.rate end)
    cache.key, cache.at, cache.rows = key, now, rows
    ns.FP.Debug(string.format("rank mapa=%s nível=%d hubs=%d falhas=%d", tostring(mapID), level, #rows, failures.count))
    return rows
end

function Guide.Find(key)
    local mapID = tonumber(key:match("^(%d+):"))
    for _, r in ipairs(Guide.Rank(mapID)) do if r.key == key then return r end end
    return nil
end

------------------------------------------------------------------------------------------
-- Seguir circuito no GPS (R20–R23)
------------------------------------------------------------------------------------------
local function stopLabel(stop, names)
    if stop.kind == "objetivo" then return "Objetivo: " .. (stop.label or "?") end
    local qs = {}
    for _, q in ipairs(stop.quests) do qs[#qs + 1] = names[q] or tostring(q) end
    local title = ns.Util.TargetTitle(stop.kind, ns.Data.PointName(stop.point), table.concat(qs, ", ")) -- spec 013
    return ns.Util.WithPlace(title, ns.Data.PointPlace(stop.point)) -- spec 021
end

-- R2 (spec 006): parada = tipo + NPC/objeto (pegar/entregar) ou chave do objetivo.
local function stopID(stop)
    if stop.kind == "objetivo" then return "objetivo:" .. tostring(stop.key) end
    return stop.kind .. ":" .. tostring(stop.point.source or pointKey(stop.point))
end

local function dataReady() return ns.Data.Q ~= nil and ns.Data.ready end

function Guide.Step()
    local g = ns.FP.db.guide
    if not g then return end
    if not dataReady() then -- R3: sem dados, não mexe no hub seguido
        ns.FP.Debug(string.format("step: esperando dados (Q=%s ready=%s)", tostring(ns.Data.Q ~= nil), tostring(ns.Data.ready)))
        return
    end
    local row = Guide.Find(g.hub)
    local stops = row and row.circuit.stops or {}
    if #stops == 0 then
        ns.FP.Debug(string.format("step: circuito concluído (hub=%s row=%s)", g.hub, tostring(row ~= nil)))
        ns.FP.db.guide, Guide.current = nil, nil
        ns.Gps.Clear()
        ns.FP.Print("circuito concluído:", row and row.name or "hub")
        if ns.FP.db.autoNext then C_Timer.After(1, function() Guide.FollowBest("next") end) end -- R6
        return
    end
    -- R2/R23: mantém a parada e o ponto enquanto a parada existir. R13: no objetivo espalhado,
    -- depois de chegar ao ponto, vai ao não visitado mais perto.
    local stop, point, visited = stops[1], nil, {}
    local cur = Guide.current
    -- R16: só mantém a parada se ela estiver liberada (mesma volta e sem dependência pendente).
    local present = {}
    for _, s in ipairs(stops) do if s.key then present[s.key] = true end end
    local function free(s)
        if (s.round or 1) ~= (stops[1].round or 1) then return false end
        for _, k in ipairs(s.after or {}) do if present[k] then return false end end
        return true
    end
    if cur then
        for _, s in ipairs(stops) do
            if stopID(s) == cur.id and free(s) then
                stop, visited = s, cur.visited or {}
                for _, p in ipairs(s.points or {}) do if p == cur.point then point = p; break end end
                if point and visited[point] then
                    point = ns.Leveling.NextPoint(s.points, point, visited, ns.Planner.Distance)
                end
                break
            end
        end
    end
    point = point or stop.point
    Guide.current = { id = stopID(stop), point = point, visited = visited }
    ns.FP.Debug(string.format("step hub=%s parada=%s ponto=%.1f,%.1f paradas=%d mantida=%s",
        g.hub, Guide.current.id, point.x or -1, point.y or -1, #stops, tostring(cur ~= nil and cur.id == Guide.current.id)))
    ns.Gps.SetTarget(point.mapID, point.x, point.y, stopLabel(stop, row.circuit.names))
    -- R18: o plano sob a seta.
    local idx = 1
    for i, s in ipairs(stops) do if s == stop then idx = i end end
    local info = { string.format("%s · parada %d de %d · ~%d min", row.name, idx, #stops,
        math.floor((row.circuit.seconds or 0) / 60 + 0.5)) }
    local shown = 0
    for i, s in ipairs(stops) do
        if i ~= idx and shown < 2 then
            shown = shown + 1
            info[#info + 1] = (shown == 1 and "depois: " or "") .. stopLabel(s, row.circuit.names)
        end
    end
    ns.Gps.SetInfo(info)
    ns.FP.Fire("CHANGED")
end

function Guide.Follow(key)
    ns.FP.db.following = nil
    ns.FP.db.guide = { hub = key }
    Guide.current = nil
    -- Spec 008, R5: congela os satélites escolhidos agora até o hub acabar.
    Guide.Invalidate()
    local row = Guide.Find(key)
    if row then ns.FP.db.guide.satellites = row.circuit.satellites end
    local nsat = 0
    for _ in pairs(row and row.circuit.satellites or {}) do nsat = nsat + 1 end
    ns.FP.Debug(string.format("follow hub=%s achado=%s satélites=%d", key, tostring(row ~= nil), nsat))
    Guide.Invalidate()
    Guide.Step()
end

-- mode: "best" (R7), "turnin" (Ir entregar) ou "next" (fim de circuito, R6).
-- quiet: sem hub na zona, não avisa no chat (troca de zona, R19).
function Guide.FollowBest(mode, quiet)
    mode = mode or "best"
    ns.FP.AfterCombat("guideBest", function()
        local rows, cands, byKey = Guide.Rank(), {}, {}
        for _, r in ipairs(rows) do
            if #r.circuit.stops > 0 then
                cands[#cands + 1] = { key = r.key, ready = r.ready, quests = #r.circuit.kept,
                    rate = r.circuit.rate, dist = r.dist }
                byKey[r.key] = r
            end
        end
        local best = byKey[ns.Leveling.PickHub(cands, mode) or ""]
        ns.FP.Debug(string.format("melhor hub modo=%s candidatos=%d escolhido=%s", mode, #cands, best and best.key or "nenhum"))
        if best then
            local why = (mode ~= "best" and best.ready > 0) and string.format("%d entrega(s) pronta(s)", best.ready)
                or string.format("%s XP/h", Util.FormatInt(best.circuit.rate))
            ns.FP.Print("seguindo:", best.name, "(" .. why .. ")")
            Guide.Follow(best.key)
        elseif quiet then -- R19: sem hub na zona nova, o hub seguido continua
            ns.FP.Debug("zona: sem hub na zona nova; hub seguido mantido")
        elseif mode == "turnin" then
            ns.FP.Print("nenhuma quest pronta para entregar nesta zona.")
        else
            ns.FP.Print("nenhum hub com circuito nesta zona.")
        end
    end)
end

------------------------------------------------------------------------------------------
-- Limpeza do log (spec 006, R10 e R11)
------------------------------------------------------------------------------------------
local CHAIN_STEPS = 5
local GRAY_LEVELS = 6

-- Quests liberadas adiante: seguinte da cadeia e quem tem q como pré-requisito (até 5 passos).
local function chainAhead(q, mapID)
    local D = ns.Data
    local dependents = {}
    for _, other in ipairs(D.QuestsForMap(mapID)) do
        for _, pre in ipairs(D.Prerequisites(other)) do
            dependents[pre] = dependents[pre] or {}
            table.insert(dependents[pre], other)
        end
    end
    local out, seen, frontier = {}, { [q] = true }, { q }
    for _ = 1, CHAIN_STEPS do
        local nextFrontier = {}
        for _, cur in ipairs(frontier) do
            local nexts = {}
            for _, d in ipairs(dependents[cur] or {}) do nexts[#nexts + 1] = d end
            local n = D.NextInChain(cur)
            if n then nexts[#nexts + 1] = n end
            for _, n2 in ipairs(nexts) do
                if not seen[n2] then seen[n2] = true; out[#out + 1] = n2; nextFrontier[#nextFrontier + 1] = n2 end
            end
        end
        frontier = nextFrontier
    end
    return out
end

function Guide.CleanupList(mapID)
    local D = ns.Data
    if not dataReady() then return {} end
    local level = UnitLevel("player")
    mapID = mapID or Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
    local items = {}
    for _, row in ipairs(Guide.Rank(mapID)) do
        local c = row.circuit
        local hubRate = c.seconds > 0 and c.value / c.seconds or 0
        for _, k in ipairs(c.kept) do
            if k.state == "fazer" then
                local est = c.estimates[k.id] or { value = 0, seconds = 1 }
                local qLevel = D.Q.questLevel(k.id) or level
                local chainUpgrade, chainXP = false, 0
                for _, n in ipairs(chainAhead(k.id, mapID)) do
                    local _, delta = ns.Scoring.BestReward(D.Rewards(n))
                    if delta and delta > 0 then chainUpgrade = true end
                    chainXP = chainXP + (D.QuestXP(n, level) or 0)
                end
                items[#items + 1] = { id = k.id, name = c.names[k.id], incomplete = true,
                    rate = est.value / math.max(est.seconds, 1), hubRate = hubRate,
                    gray = level - qLevel >= GRAY_LEVELS,
                    classQuest = (D.Q.requiredClasses(k.id) or 0) ~= 0, bagReward = D.IsBagQuest(k.id),
                    chainUpgrade = chainUpgrade, chainXP = chainXP, medianXP = D.medianXPByLevel[qLevel] }
            end
        end
    end
    local list = ns.Leveling.CleanupCandidates(items, ns.FP.db.threshold or 0.5)
    local names = {}
    for _, it in ipairs(items) do names[it.id] = it.name end
    for _, c in ipairs(list) do c.name = names[c.id] or ("Quest " .. c.id) end
    return list
end

------------------------------------------------------------------------------------------
-- Bolsas (spec 010, R5): do log ou disponível na zona atual primeiro, depois menor nível.
------------------------------------------------------------------------------------------
function Guide.BestBag()
    if not dataReady() then return nil end
    local level = UnitLevel("player")
    local zone = Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
    local best, bestKey
    for _, b in ipairs(ns.Data.BagQuests(level)) do
        if b.status == "no log" or b.status == "disponível" then
            local key = (b.mapID == zone and 0 or 1) * 1000 + b.level
            if not bestKey or key < bestKey then best, bestKey = b, key end
        end
    end
    return best
end

function Guide.FollowBag()
    ns.FP.AfterCombat("followBag", function()
        local b = Guide.BestBag()
        if not b then ns.FP.Print("nenhuma quest de bolsa disponível agora."); return end
        ns.FP.Print(string.format("seguindo bolsa: %s (%s, %s) — %s", b.name, b.itemName or "bolsa", b.zone, b.status))
        ns.FP.Debug("bolsa: seguir " .. b.q)
        ns.Planner.Follow(b.q)
    end)
end

-- Abandona só o que o jogador confirmou (R10). Fora de combate.
function Guide.Abandon(ids)
    ns.FP.AfterCombat("abandon", function()
        local Q = C_QuestLog
        for _, q in ipairs(ids) do
            if Q.SetSelectedQuest and Q.SetAbandonQuest and Q.AbandonQuest then
                Q.SetSelectedQuest(q); Q.SetAbandonQuest(); Q.AbandonQuest()
            end
        end
        ns.FP.Print(string.format("%d quest(s) abandonada(s).", #ids))
        Guide.Invalidate()
    end)
end

-- O log muda a cada mob morto: aí vale o cache de 2 s (R25). Pegar/entregar invalida na hora.
local function step()
    if ns.FP.db and ns.FP.db.guide then ns.FP.AfterCombat("guideStep", Guide.Step) end
end
local function invalidateAndStep() Guide.Invalidate(); step() end
-- R14: depois de uma rajada de mudanças no log, um recálculo final sem cache.
local trailing = false
local function stepAfterCache()
    if trailing then return end
    trailing = true
    C_Timer.After(CACHE_SECONDS + 0.2, function() trailing = false; invalidateAndStep() end)
end
ns.FP.On("QUEST_LOG", function() step(); stepAfterCache() end)
-- R17: recálculos pedidos por eventos próximos viram um só por janela (0,3 s, 1 s, 3 s).
local scheduled = {}
local function refreshIn(delay)
    if scheduled[delay] then return end
    scheduled[delay] = true
    C_Timer.After(delay, function() scheduled[delay] = nil; invalidateAndStep() end)
end
-- R12/R15: o jogo atualiza o log em etapas; recalcula logo, em 1 s e em 3 s.
local function burst() refreshIn(0.3); refreshIn(1); refreshIn(3) end
ns.FP.On("QUEST_ACCEPTED", burst)
ns.FP.On("QUEST_TURNED_IN", burst)
ns.FP.On("QUEST_REMOVED", function() refreshIn(0.3) end)
-- R19 (spec 006): saiu da zona do hub seguido, segue o melhor hub da zona nova.
local lastZone
local function playerZone() return Guide.ZoneMap(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) end
local function hubMapOf(key) return key and tonumber(key:match("^(%d+):")) end
local function hasCircuit(key)
    local row = Guide.Find(key)
    return row ~= nil and #row.circuit.stops > 0
end
ns.FP.On("ZONE", function()
    local to = playerZone()
    if not (to and dataReady()) then return end -- mapa nil (carregando, táxi) ou dados carregando
    local from = lastZone
    lastZone = to
    ns.FP.AfterCombat("guideZone", function()
        local g = ns.FP.db and ns.FP.db.guide
        local now = playerZone()
        if not (g and g.hub) or now ~= to then return end -- em combate, voltou ou mudou de novo
        local byZone = ns.FP.db.hubByZone or {}
        ns.FP.db.hubByZone = byZone
        local saved = byZone[to]
        if saved and not hasCircuit(saved) then saved = nil end
        local action = ns.Util.ZoneHubAction(hubMapOf(g.hub), from, to, saved)
        if not action then return end
        ns.FP.Debug(string.format("zona: saiu de %s para %s, hub %s, ação %s", tostring(from), tostring(to), g.hub, action))
        byZone[from] = g.hub
        if action == "best" then Guide.FollowBest("best", true) else Guide.Follow(action) end
    end)
end)
ns.FP.On("READY", function() lastZone = lastZone or playerZone() end)
ns.FP.On("GPS_ARRIVED", function()
    local cur = Guide.current
    if cur and cur.id:find("^objetivo:") then cur.visited[cur.point] = true end -- R13
    C_Timer.After(1.5, step)
end)
ns.FP.On("READY", function() C_Timer.After(1, invalidateAndStep) end) -- R4: retoma depois do /reload
ns.FP.On("DATA_READY", invalidateAndStep) -- R4: o índice termina segundos depois do READY

------------------------------------------------------------------------------------------
-- Sugestão de zona (spec 029): ficar, ir para outra zona ou fazer grind
------------------------------------------------------------------------------------------
local function zoneParams()
    local db, L = ns.FP.db, ns.Leveling
    return { perKill = ns.FP.KillSeconds(), factor = ns.FP.MobXPFactor(), minSpawns = db.grindMinSpawns,
        overhead = L.OVERHEAD, legYards = L.UNKNOWN_LEG, speed = db.runSpeed or 7, objectSeconds = L.OBJECT_SECONDS,
        farDelivery = db.farDelivery, unknownKills = db.unknownKills, travelSame = db.travelSame,
        travelOther = db.travelOther, stay = db.zoneStay, minVisit = db.zoneMinVisit,
        lookahead = db.zoneLookahead, threshold = db.threshold or 0.5 }
end
Guide.ZoneParams = zoneParams -- tools/pesquisa_zonas.lua usa os mesmos parâmetros (R23)

local doneLookup = setmetatable({}, { __index = function(_, q) return ns.Data.IsCompleted(q) end })

-- Valor e tempo de uma quest do catálogo no nível L (R9, R10, R12). Também usada pela pesquisa.
function Guide.ZoneQuestEntry(info, L, p, unlock)
    local D, Z = ns.Data, ns.Zones
    local q = info.id
    local kills, objects, mobXP = 0, 0, 0
    for _, o in ipairs(D.Objectives(q, L, p.factor)) do
        -- spec 030, R5: kill de mob alto conta como mais tempo (o XP é o da kill mesmo)
        kills = kills + o.kills * ns.Leveling.KillFactor(o.avgLevel, L)
        objects, mobXP = objects + o.objects, mobXP + o.kills * o.mobXP
    end
    local seconds, used = Z.QuestSeconds({ kills = kills, objects = objects, far = info.far,
        unknownWork = info.unknownWork }, p)
    if info.unknownWork then mobXP = used * ns.Leveling.MobXPRange(L, info.level, info.level, p.factor) end
    return { id = q, value = (D.QuestXP(q, L)) + mobXP, seconds = seconds, unlock = unlock or 0,
        requires = D.Prerequisites(q) }
end

-- Oferta de uma zona no nível L (R12), com o XP que as cadeias destravam (R2) e a cinza que destrava (R3).
local function zoneOffer(cat, zone, L, p)
    local D, Z = ns.Data, ns.Zones
    local entries = {}
    for _, q in ipairs(cat.zones[zone].quests) do
        local info = cat.info[q]
        if info.solo and info.level <= L + 3 and D.IsEligible(q, L)
            and not ns.Leveling.ObjectivesTooHigh(D.Objectives(q, L, p.factor), L) then -- spec 030, R4
            local unlock = Z.ChainAhead(q, cat, zone, L, doneLookup)
            local gray = L - info.level >= 10
            if D.IsRelevant(q, L) or (gray and unlock > 0 and D.IsRelevant(q, info.level)) then
                entries[#entries + 1] = Guide.ZoneQuestEntry(info, L, p, unlock)
            end
        end
    end
    local o = Z.Offer(entries, p.threshold, function(id, seen) return Z.ChainAhead(id, cat, zone, L, doneLookup, seen) end)
    o.estimated = 0 -- R9: quests novas do Forever da oferta com XP pela mediana
    for _, e in ipairs(o.kept) do
        local info = cat.info[e.id]
        if info.forever and info.xpSrc == "estimativa" then o.estimated = o.estimated + 1 end
    end
    return o
end

local function areaName(area)
    if not area then return "zona desconhecida" end
    local map = ns.Data.areaToMap[area]
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("área " .. tostring(area))
end
Guide.AreaName = areaName

-- Faixa de nível dos mobs que contam no grind (R19).
local function grindLevels(hist, L)
    local lo, hi
    for l, s in pairs(hist) do
        if s > 0 and ns.Leveling.MobXP(L, l, 1) > 0 and l <= L + 2 then
            lo, hi = math.min(lo or l, l), math.max(hi or l, l)
        end
    end
    return lo, hi
end

function Guide.PlayerArea()
    local D = ns.Data
    local map = Guide.ZoneMap(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local area = map and D.mapToArea[map]
    return area and D.ZoneOfArea(area), map
end

-- R15: XP/h de grind das zonas do mapa de continentes (fora instância e campo de batalha).
local GRIND_MARGIN = 0.15
function Guide.GrindRates(cat, L, p)
    local out = {}
    for zone, z in pairs(cat.zones) do
        if z.continent then out[#out + 1] = { zone = zone, rate = (ns.Zones.GrindRate(z.hist, L, p)) } end
    end
    table.sort(out, function(a, b) return a.zone < b.zone end) -- ordem estável
    return out
end

-- Cálculo completo, síncrono (os testes chamam direto). yield, opcional, é chamado a cada zona.
function Guide.ComputeZoneAdvice(yield)
    local D, Z = ns.Data, ns.Zones
    local cat = D.zoneCatalog
    local L = UnitLevel("player")
    local levelXP = Z.LevelXP(L)
    if not (cat and levelXP) then return nil end
    local p = zoneParams()
    local here = Guide.PlayerArea()
    local hereCont = here and cat.zones[here] and cat.zones[here].continent
    local cur = { zone = here, rate = 0, n = 0 }
    local cands = {}
    for zone, z in pairs(cat.zones) do
        if #z.quests > 0 then
            local o = zoneOffer(cat, zone, L, p)
            if zone == here then
                cur.rate, cur.n, cur.offer = o.rate, o.n, o
            elseif o.n > 0 then
                local travel = Z.Travel(here, zone, hereCont, z.continent, p)
                local ahead = zoneOffer(cat, zone, math.min(L + p.lookahead, #Z.LEVEL_XP), p)
                local potential = math.max(o.value + o.unlock, ahead.value)
                local raw, eff = Z.Effective(o, travel, potential, levelXP, p.minVisit)
                cands[#cands + 1] = { zone = zone, raw = raw, eff = eff, n = o.n, travel = travel, offer = o,
                    estimated = o.estimated, anyRace = z.anyRace }
            end
        end
        if yield then yield() end
    end
    local grind = Z.PickGrind(Guide.GrindRates(cat, L, p), here, GRIND_MARGIN)
    table.sort(cands, function(a, b) return a.eff > b.eff end)
    local d = Z.Decide(cur, cands, grind, p)
    if grind.zone and cat.zones[grind.zone] then grind.lo, grind.hi = grindLevels(cat.zones[grind.zone].hist, L) end
    d.level, d.here, d.cur, d.cands, d.grind = L, here, cur, cands, grind
    for _, c in ipairs(cands) do if c.zone == d.zone then d.target = c end end
    return d
end

-- R18: recálculo fora de combate, em coroutine, com cache por nível + entregas + zona.
local advice = { key = nil, turnIns = 0, lastNotice = nil, running = false, pending = false, frame = nil }
function Guide.ZoneAdvice() return advice.result end

local function notify(d)
    if not d or d.action == "stay" then advice.lastNotice = nil; return end
    local key = d.action .. ":" .. tostring(d.zone) .. ":" .. d.level
    if advice.lastNotice == key then return end -- R20: uma vez por ação, zona e nível
    advice.lastNotice = key
    local what = d.action == "go" and ("ir para " .. areaName(d.zone)) or ("grind em " .. areaName(d.zone))
    ns.FP.Print("zona: " .. what .. " (" .. d.reason .. ", est.)")
end

function Guide.RefreshZoneAdvice()
    ns.FP.AfterCombat("zoneAdvice", function()
        if not ns.Data.zoneCatalog then return end
        if advice.running then advice.pending = true; return end -- recalcula ao terminar
        local key = table.concat({ UnitLevel("player"), advice.turnIns, tostring(Guide.PlayerArea()),
            tostring(ns.FP.db.threshold) }, ":")
        if key == advice.key then return end
        advice.running, advice.pending = true, false
        local started = _G.debugprofilestop and _G.debugprofilestop()
        local co = coroutine.create(function() return Guide.ComputeZoneAdvice(coroutine.yield) end)
        advice.frame = advice.frame or CreateFrame("Frame")
        advice.frame:SetScript("OnUpdate", function(self)
            if Util.InCombat() then return end -- constituição 6: pausa no combate
            local ok, res = coroutine.resume(co)
            if not ok then
                self:SetScript("OnUpdate", nil); advice.running = false
                ns.FP.Debug("sugestão de zona: erro " .. tostring(res))
                return
            end
            if coroutine.status(co) == "dead" then
                self:SetScript("OnUpdate", nil)
                advice.running, advice.key, advice.result = false, key, res
                local ms = started and (_G.debugprofilestop() - started)
                ns.FP.Debug(string.format("sugestão de zona: %s %s (%s)%s", res and res.action or "nada",
                    res and tostring(res.zone) or "", res and res.reason or "", ms and string.format(" %.0f ms", ms) or ""))
                notify(res)
                ns.FP.Fire("CHANGED")
                if advice.pending then Guide.RefreshZoneAdvice() end
            end
        end)
    end)
end

local turnInToken = 0
ns.FP.On("QUEST_TURNED_IN", function()
    advice.turnIns = advice.turnIns + 1
    turnInToken = turnInToken + 1
    local mine = turnInToken
    C_Timer.After(3, function() if mine == turnInToken then Guide.RefreshZoneAdvice() end end) -- junta entregas
end)
ns.FP.On("LEVEL_UP", function() C_Timer.After(1, Guide.RefreshZoneAdvice) end)
ns.FP.On("ZONE", function() C_Timer.After(2, Guide.RefreshZoneAdvice) end)
ns.FP.On("ZONE_CATALOG", Guide.RefreshZoneAdvice)

-- R19: duas linhas para a aba Guia (sempre com "est.").
function Guide.ZoneAdviceText(d)
    if not d then return nil end
    local F = Util.FormatInt
    local here = string.format("|cFFB38CFFAqui:|r %s — %d quests, %s XP/h (est.)", areaName(d.here), d.cur.n,
        F(math.floor(d.cur.rate + 0.5)))
    local tip
    if d.action == "stay" then
        tip = "|cFF73E65ASugestão:|r ficar (" .. d.reason .. ", est.)"
    elseif d.action == "go" then
        local t = d.target
        tip = string.format("|cFFFFD24DSugestão:|r ir para %s — %s XP/h, viagem ~%d min (%s, est.)", areaName(d.zone),
            F(math.floor((t and t.eff or 0) + 0.5)), math.floor((t and t.travel or 0) / 60 + 0.5), d.reason)
        if t and (t.estimated or 0) > 0 then tip = tip .. "; XP das quests novas do Forever é estimado" end
    else
        local g = d.grind
        local mobs = (g.lo and g.hi) and string.format("mobs %d–%d, ", g.lo, g.hi) or ""
        tip = string.format("|cFFFFD24DSugestão:|r grind em %s — %s%s XP/h (%s, est.)", areaName(d.zone), mobs,
            F(math.floor(g.rate + 0.5)), d.reason)
    end
    return here .. "\n" .. tip
end

-- R21: /fp zonas, as 5 melhores zonas do nível e o melhor grind.
function Guide.PrintZones()
    ns.FP.AfterCombat("zoneList", function()
        if not ns.Data.zoneCatalog then ns.FP.Print("zonas: catálogo ainda montando, tente em alguns segundos."); return end
        local d = Guide.ComputeZoneAdvice()
        if not d then ns.FP.Print("zonas: nada a sugerir neste nível."); return end
        local F = Util.FormatInt
        ns.FP.Print(string.format("zonas para o nível %d (estimativa):", d.level))
        for i = 1, math.min(5, #d.cands) do
            local c = d.cands[i]
            local extra = ""
            if (c.estimated or 0) > 0 then extra = extra .. string.format(", %d novas do Forever com XP estimado", c.estimated) end
            if (c.anyRace or 0) > 0 then extra = extra .. string.format(", %d sem raça na base", c.anyRace) end
            ns.FP.Print(string.format("%d. %s: %s XP/h, %d quests, viagem ~%d min%s", i, areaName(c.zone),
                F(math.floor(c.eff + 0.5)), c.n, math.floor(c.travel / 60 + 0.5), extra))
        end
        local g = d.grind
        if g.zone and g.rate > 0 then
            ns.FP.Print(string.format("melhor grind: %s%s, %s XP/h", areaName(g.zone),
                (g.lo and g.hi) and string.format(" (mobs %d–%d)", g.lo, g.hi) or "", F(math.floor(g.rate + 0.5))))
        end
        ns.FP.Print((Guide.ZoneAdviceText(d):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end)
end

return Guide
