-- Guide.lua: guia de leveling por hub (spec 002). Adaptador: lê Data/Planner/Scoring e
-- entrega para as regras puras de Leveling. Também segue o circuito no GPS.
local _, ns = ...
local L, K = ns.L, ns.Locale.K -- spec 066
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

-- Nome de quem dá a quest: NPC (número) ou objeto ("o<id>": cartaz, livro). Spec 002, emenda de
-- 24/11/2026: hub de objeto saía como "Hub 1413:1413:46.36:73.90".
local function sourceName(src)
    local D = ns.Data
    if type(src) == "number" then return D.N.name(src) end
    local oid = type(src) == "string" and tonumber(src:match("^o(%d+)$"))
    if oid and D.O and D.O.name then
        local ok, n = pcall(D.O.name, oid)
        return ok and n or nil
    end
end
local function hubName(hub)
    local count, best = {}, nil
    for _, p in ipairs(hub.points) do
        local src = p.source
        if src ~= nil then
            count[src] = (count[src] or 0) + (hub.questsAt[pointKey(p)] or 0)
            if not best or count[src] > count[best] or (count[src] == count[best] and type(src) == "number" and type(best) ~= "number") then
                best = src
            end
        end
    end
    local name = best and sourceName(best)
    if name then return L["Hub de "] .. name end
    local p = hub.points[1]
    return string.format(L["Hub em %.0f, %.0f"], p.x or 0, p.y or 0)
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

-- Spec 068, R1: um hub com a união dos hubs do mapa (a rota da zona).
function Guide.ZoneHub(hubs, mapID)
    local z = { key = mapID .. ":zona", name = L["Rota da zona"], points = {}, quests = {}, questList = {}, questsAt = {}, zone = true }
    for _, h in ipairs(hubs) do
        for _, p in ipairs(h.points) do z.points[#z.points + 1] = p end
        for k, n in pairs(h.questsAt or {}) do z.questsAt[k] = (z.questsAt[k] or 0) + n end
        for _, q in ipairs(h.questList) do
            if not z.quests[q] then z.quests[q] = true; z.questList[#z.questList + 1] = q end
        end
    end
    return z
end

-- R5 (spec 006): de caverna/cidade sobe até o mapa da zona (mapType 3 = zona).
local ZONE_MAP_TYPE = 3
Guide.ZONE_MAP_TYPE = ZONE_MAP_TYPE -- UI/WorldMap.lua usa a mesma constante
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
-- Spec 039, R3: passos adiante da cadeia para quest que ainda vai ser pega; nil sem passos.
local function chainAheadOf(q, level)
    local D = ns.Data
    if D.IsOnQuest(q) then return nil end
    local a = D.ChainAhead(q, level)
    return a.n > 0 and a or nil
end

local function itemQuality(id)
    local byID = C_Item.GetItemQualityByID
    local quality = byID and byID(id)
    if quality == nil then quality = select(3, C_Item.GetItemInfo(id)) end
    return quality
end

-- Spec 046, R9: melhor item que vale a pena na quest ou num passo adiante da cadeia (spec 039).
local function questGoal(q, level, bestItem, delta)
    local D, minDelta, best = ns.Data, ns.FP.db.grayKeepDelta or 10, nil
    local function try(item, d, step)
        if item and ns.Leveling.ItemWorth(d, itemQuality(item), minDelta) and (not best or (d or 0) > (best.delta or 0)) then
            best = { item = item, delta = d, step = step }
        end
    end
    try(bestItem, delta, nil)
    for _, n in ipairs(D.ChainAhead(q, level).ids) do
        local item, d = ns.Scoring.BestReward(D.Rewards(n))
        try(item, d, n)
    end
    return best
end

local function goalText(goal)
    if not goal then return "" end
    local name = C_Item.GetItemInfo(goal.item) or (L["item "] .. goal.item)
    return (goal.step and L[" (cadeia leva a: "] or L[" (leva a: "]) .. name .. ")"
end

local function questInfo(q, level, requires)
    local D = ns.Data
    local objectives, elite, dungeon = D.Objectives(q, level, ns.FP.MobXPFactor())
    local bestItem, delta = ns.Scoring.BestReward(D.Rewards(q))
    local trainSkill, trainOn = ns.ClassGuide.MissingSkillFor(bestItem) -- spec 011, R6
    delta = ns.Milestones.EffectiveDelta(delta, trainSkill)
    local bag, bonusXP = D.WantsBag(q) -- spec 010 (R8: dispensada não conta; R9: bônus de XP)
    local weapon = ns.Milestones.IsWeaponUpgrade(ns.ClassGuide.ItemClass(bestItem), delta, trainSkill) -- spec 012
    local classQuest = (D.Q.requiredClasses(q) or 0) ~= 0
    local qLevel = D.Q.questLevel(q)
    -- Spec 046, R9: o item só importa para segurar a cinza (R8); fora dela não se calcula.
    local goal = ns.Leveling.IsGrayQuest(qLevel, level) and questGoal(q, level, bestItem, delta) or nil
    return {
        bag = bag, bonusXP = bonusXP or nil, weapon = weapon,
        classQuest = classQuest, goal = goal,
        keep = classQuest or weapon or (delta or 0) > 0, -- spec 046, R2
        trainSkill = trainSkill, trainOn = trainOn, -- trainOn: arma habilitada na janela Armas (spec 016)
        id = q, name = D.Q.name(q) or (L["Quest "] .. q), state = ns.Planner.State(q),
        xp = (D.QuestXP(q, level)), money = D.QuestMoney(q), delta = delta,
        starters = D.StarterPoints(q), finishers = D.FinisherPoints(q),
        objectives = objectives, elite = elite, dungeon = dungeon, requires = requires,
        group = (ns.FP.db.groupChoice or {})[q], -- spec 054, R3
        event = Guide.IsEvent(q) or nil, -- spec 067, R1
        deaths = (ns.FP.db.questDeaths or {})[q], -- spec 067, R2
        deathLevel = (ns.FP.db.questDeathLevel or {})[q], -- spec 067, R2a
        qLevel = qLevel, -- spec 025
        ahead = chainAheadOf(q, level), -- spec 039, R3
    }
end

-- Spec 067, R1 (parecer): o texto da quest não muda; guarda o resultado por quest.
local eventCache = {}
function Guide.IsEvent(q)
    local v = eventCache[q]
    if v == nil then
        v = ns.Data.Q and ns.Util.IsEvent(ns.Data.Q.objectivesText(q)) or false
        eventCache[q] = v
    end
    return v
end

local function params()
    local db = ns.FP.db
    return {
        ttk = ns.FP.KillSeconds(), downtime = 0, speed = db.runSpeed or 7, threshold = db.threshold or 0.5,
        killCurve = ns.FP.KillCurve(), -- spec 067, R6
        levelXP = Util.Num(_G.UnitXPMax and _G.UnitXPMax("player")) or 0,
        upgradePerPoint = db.upgradePerPoint, upgradeCap = db.upgradeCap,
        rested = Util.Num(_G.GetXPExhaustion and _G.GetXPExhaustion()) or 0,
        goldToXP = db.goldToXP, logFree = ns.Data.LogFree(),
        playerLevel = UnitLevel("player"), -- spec 025
        mobTolerance = (ns.FP.MobTolerance()), -- spec 031, R7
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
                if not D.IsOnQuest(q) and D.IsEligible(q, level) and D.IsRelevantForChain(q, level) then
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
    local now = _G.GetTime and _G.GetTime() or 0
    local function add(info)
        if info and info.state == "pegar" and ns.Leveling.SkipActive(Guide.pickSkip, info.id, now) then return end -- spec 059
        if info and not seen[info.id] then seen[info.id] = true; list[#list + 1] = info end
    end
    -- R1 (spec 006): quest do log só entra pelo logByHub (hub da entrega). Pelo hub de quem deu a
    -- quest, a entrega em outro mapa virava parada do circuito (ex.: "Sample for Helbrim", 11/11/2026).
    for _, q in ipairs(hub.questList) do
        if not D.IsOnQuest(q) and D.IsEligible(q, level) and D.IsRelevantForChain(q, level) then add(safeInfo(q, level)) end -- spec 039, R5
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
            if #requires > 0 and D.IsEligible(q, level, inCircuit) and D.IsRelevantForChain(q, level) then
                local info = safeInfo(q, level, requires)
                if info then info.requiresAny = any end
                add(info)
            end
        end
    end
    local c = ns.Leveling.BuildCircuit(list, player, params(), ns.Planner.Distance)
    local names, keptSet, byID = {}, {}, {}
    for _, info in ipairs(list) do byID[info.id] = info end
    for _, info in ipairs(list) do
        local escort = info.state == "pegar" and Util.IsEscort(D.Q.objectivesText(info.id)) -- spec 059, R2
        names[info.id] = info.name .. (escort and L[" (escolta)"] or "") .. (info.requires and L[" (cont.)"] or "") .. (info.satellite and L[" (no caminho)"] or "")
            .. goalText(info.goal) -- spec 046, R10
            .. (info.bag and (info.bonusXP and L[" (bônus de XP)"] or L[" (bolsa)"]) or "") .. (info.weapon and L[" (arma)"] or "") .. (info.trainSkill and info.trainOn and (L[" (treine "] .. info.trainSkill .. ")") or "")
    end
    for _, k in ipairs(c.kept) do
        keptSet[k.id] = true
        local info = k.byChain and byID[k.id]
        if info and info.ahead then -- spec 039, R6
            names[k.id] = names[k.id] .. string.format(L[" (cadeia: ~%s em %d passos, estimativa)"], Util.FormatInt(math.floor(info.ahead.value)), info.ahead.n)
        end
    end
    c.names, c.satellites = names, {}
    for _, q in ipairs(satIDs) do if keptSet[q] then c.satellites[q] = true end end
    return c
end

------------------------------------------------------------------------------------------
-- Ranking de hubs (R14) com cache (R25)
------------------------------------------------------------------------------------------
local cache = { key = nil, at = 0, rows = nil }

function Guide.Invalidate() cache.key, cache.rows = nil, nil end

-- Spec 045, R1–R4: parada "abrir ponto de voo" onde o desvio entre as paradas for curto.
-- Um ponto por vez, o de menor custo primeiro; cada um soma desvio / velocidade + conversa.
local ZONE_MAX_DETOUR = 1500 -- R2c: desvio máximo para abrir o ponto antes de sair da zona (estimativa)
local flightSkip = {} -- R6a: parada de voo dispensada nesta sessão ("voo:taxi<id>" = true)
-- Spec 052: o adaptador só junta os dados; a regra é Leveling.FlightStops (pura, com cenários).
Guide.lastFlight = {} -- última entrada da regra por hub, para /fp cena (R9)
local function addFlightStops(c, red, player)
    local db = ns.FP.db
    local speed, overhead = db.runSpeed or 7, db.flightOverhead or 10
    local left = {}
    for _, p in ipairs(red) do
        if not flightSkip["voo:taxi" .. tostring(p.id)] then left[#left + 1] = p end
    end
    if #left == 0 then return end
    local F = ns.Gps.FLIGHT
    local okHere, here = pcall(function() return (Guide.PlayerArea()) end)
    local zones = {}
    local ctx = {
        dist = ns.Planner.Distance, here = okHere and here or nil,
        zoneOf = function(pt)
            if pt.zone ~= nil then return pt.zone end
            if zones[pt.mapID] == nil then
                local ok, z = pcall(Guide.MapZone, pt.mapID)
                zones[pt.mapID] = ok and z or false
            end
            return zones[pt.mapID] or nil
        end,
        -- spec 044, R8: os conhecidos do continente do jogador (os vermelhos vêm de mapas dele)
        known = ns.Planner.KnownTaxiPoints(ns.Planner.ContinentMap(player and player.mapID or left[1].mapID)),
        maxDetour = db.flightMaxDetour or 400, zoneMax = ZONE_MAX_DETOUR,
        fopts = { run = speed, fly = F.fly, factor = F.factor, overhead = F.overhead, margin = F.margin, walkShare = F.walkShare },
    }
    local start = player and player.x and player or nil
    Guide.lastFlight[c.hubKey or "?"] = { start = start, stops = c.stops, red = left, ctx = ctx, hub = c.hubName or "?" }
    local out, added, cost = ns.Leveling.FlightStops(start, c.stops, left, ctx)
    for _, a in ipairs(added) do
        ns.FP.Debug(string.format("voo no circuito: %s na parada %d, desvio %.0f jd (%s)", tostring(a.node.name), a.idx, a.cost, a.why))
    end
    if #added == 0 then return end
    c.stops = out
    c.legs = (c.legs or 0) + cost -- spec 045, R3
    c.seconds = c.seconds + cost / speed + overhead * #added
    c.rate = c.seconds > 0 and c.value / c.seconds * 3600 or 0
end

-- R9: grava a última entrada da regra em jardas do mundo, para virar cenário de teste.
function Guide.SaveScene()
    -- parecer 050-052: a cena é a do hub seguido, não a do último hub do ranking
    local followed = ns.FP.db.guide and ns.FP.db.guide.hub
    local f = followed and Guide.lastFlight[followed]
    if not f then ns.FP.Print(L["nenhum cálculo de voo do hub seguido: siga um hub com ponto de voo a abrir."]); return end
    local function w(p)
        if not p then return nil end
        local _, wx, wy = ns.Planner.WorldPos(p.mapID, p.x, p.y)
        return { x = wx and math.floor(wx + 0.5), y = wy and math.floor(wy + 0.5), mapID = p.mapID, mx = p.x, my = p.y,
            zone = f.ctx.zoneOf(p) }
    end
    local scene = { at = _G.date and _G.date("%Y-%m-%d %H:%M") or "", hub = f.hub, here = f.ctx.here, start = w(f.start),
        stops = {}, red = {}, known = {} }
    for _, s in ipairs(f.stops) do scene.stops[#scene.stops + 1] = w(s.point) end
    for _, p in ipairs(f.red) do
        local r = w(p); r.id, r.name, r.zone = p.id, p.name, p.zone
        scene.red[#scene.red + 1] = r
    end
    for _, k in ipairs(f.ctx.known) do local r = w(k); r.name = k.name; scene.known[#scene.known + 1] = r end
    local db = ns.FP.db
    db.scenes = db.scenes or {}
    table.insert(db.scenes, 1, scene)
    while #db.scenes > 5 do table.remove(db.scenes) end
    ns.FP.Print(string.format(L["cena gravada (%s, %d paradas, %d pontos a abrir). Dê /reload para salvar no disco."],
        tostring(f.hub), #scene.stops, #scene.red))
end

------------------------------------------------------------------------------------------
-- Quest de grupo (spec 054): pular ou fazer em grupo
------------------------------------------------------------------------------------------
local function groupKindOf(q)
    local _, elite, dungeon = ns.Data.Objectives(q, UnitLevel("player"))
    local db = ns.FP.db
    local risky = Guide.IsEvent(q) or ns.Leveling.DeathRisky((db.questDeaths or {})[q], (db.questDeathLevel or {})[q],
        UnitLevel("player")) -- spec 067
    return ns.Leveling.GroupKind(elite, dungeon, risky), dungeon
end
Guide.GroupKindOf = groupKindOf -- spec 067, R3: também no auto accept

-- R2: pergunta ao aceitar, uma vez por quest. Parecer 053-056: o diálogo é definido uma vez, a quest
-- vai em `data`, e as que chegam com ele aberto esperam na fila.
local groupQueue, groupOpen = {}, false
local askNext
local function choose(q, v)
    local db = ns.FP.db
    db.groupChoice = db.groupChoice or {}
    db.groupChoice[q] = v
    ns.FP.Print(string.format("%s: %s.", ns.Data.Q.name(q) or tostring(q), v == "grupo" and L["fazer em grupo"] or L["pulada (fica no log, fora da rota)"]))
    Guide.Invalidate(); ns.FP.Fire("CHANGED")
end
local function groupDialog()
    local dialogs = _G.StaticPopupDialogs
    if dialogs and not dialogs.FOREVERPLANNER_GRUPO then
        dialogs.FOREVERPLANNER_GRUPO = {
            text = L["%s é de %s.\n\nPular: fica no log, fora da rota.\nFazer em grupo: entra na rota (elite) ou na lista da masmorra (/fp masmorras)."],
            button1 = L["Fazer em grupo"], button2 = L["Pular"],
            OnAccept = function(_, q) choose(q, "grupo") end,
            OnCancel = function(_, q, why) if why ~= "override" then choose(q, "pular") end end,
            OnHide = function() groupOpen = false; C_Timer.After(0.3, function() askNext() end) end,
            timeout = 0, whileDead = true, hideOnEscape = false,
        }
    end
    return dialogs
end
askNext = function()
    local db = ns.FP.db
    db.groupChoice = db.groupChoice or {}
    if groupOpen or not ns.Data.Q or not groupDialog() or not _G.StaticPopup_Show then return end
    while groupQueue[1] do
        local q = table.remove(groupQueue, 1)
        local kind, dungeon = groupKindOf(q)
        if kind and not db.groupChoice[q] and ns.Data.IsOnQuest(q) then
            local what = kind == "elite" and "elite"
                or ("masmorra" .. (type(dungeon) == "number" and (" (" .. tostring(Guide.AreaName(dungeon)) .. ")") or ""))
            local dialog = _G.StaticPopup_Show("FOREVERPLANNER_GRUPO", ns.Data.Q.name(q) or tostring(q), what, q)
            if dialog then groupOpen = true; return end
            table.insert(groupQueue, 1, q) -- parecer: popups ocupados; pergunta depois
            return
        end
    end
end
ns.FP.On("QUEST_ACCEPTED", function(q)
    q = tonumber(q)
    if not q or ns.FP.db.groupAsk == false or (ns.FP.db.groupChoice or {})[q] then return end -- spec 058
    groupQueue[#groupQueue + 1] = q
    ns.FP.AfterCombat("askGroup", function() C_Timer.After(1, function() askNext() end) end)
end)

-- Spec 058, R4: quests do plano: as mantidas nos circuitos dos hubs da zona e a seguida.
-- Parecer 057-058: no diálogo do NPC, o último ranking (mesmo vencido); só recalcula sem nenhum e fora de combate.
local function rowsForPlan()
    local p = ns.Planner.PlayerPoint()
    local key = p and p.mapID and (tostring(Guide.ZoneMap(p.mapID)) .. ":" .. UnitLevel("player"))
    if cache.rows and cache.key == key then return cache.rows end -- parecer: só o da zona e do nível atuais
    if InCombatLockdown() then return {} end
    local ok, rows = pcall(Guide.Rank)
    return ok and rows or {}
end
function Guide.PlanQuests()
    local set = {}
    local db = ns.FP.db
    if ns.Data.Q ~= nil and ns.Data.ready then
        for _, r in ipairs(rowsForPlan()) do
            for _, k in ipairs(r.circuit.kept) do set[k.id] = true end
        end
        local g = db.guide and Guide.lastFollowed -- hub seguido em outro mapa
        for _, k in ipairs(g and g.circuit and g.circuit.kept or {}) do set[k.id] = true end
    end
    if db.following then set[db.following] = true end
    if Guide.tripQuest then set[Guide.tripQuest] = true end -- viagem real para entregar (spec 035)
    return set
end

-- R4: quests do log de masmorra, por masmorra: { [chave] = { { name, dungeon, q, skipped } } }.
function Guide.DungeonQuests()
    local D, entries = ns.Data, {}
    if not D.Q then return {} end
    local choice = ns.FP.db.groupChoice or {}
    for _, q in ipairs(D.LogQuests()) do
        local kind, dungeon = groupKindOf(q)
        if kind == "masmorra" and type(dungeon) == "number" then
            entries[#entries + 1] = { name = D.Q.name(q) or tostring(q), dungeon = Guide.AreaName(dungeon) or "", q = q,
                skipped = choice[q] == "pular" }
        end
    end
    return ns.Dungeons.QuestsByDungeon(entries, ns.DungeonContent and ns.DungeonContent.aliases)
end

-- R5: /fp grupo quests [limpar]
function Guide.PrintGroupQuests(arg)
    local db = ns.FP.db
    if arg == "limpar" then db.groupChoice = {}; db.questDeaths = {}; db.questDeathLevel = {}; Guide.Invalidate(); ns.FP.Print(L["escolhas de quest de grupo apagadas."]); return end
    local n = 0
    for _, q in ipairs(ns.Data.LogQuests()) do
        local kind = groupKindOf(q)
        if kind then
            n = n + 1
            local c = (db.groupChoice or {})[q]
            ns.FP.Print(string.format("  %s · %s · %s", ns.Data.Q.name(q) or tostring(q), kind,
                c == "grupo" and L["fazer em grupo"] or (c == "pular" and L["pulada"] or L["sem escolha (fora da rota)"])))
        end
    end
    if n == 0 then ns.FP.Print(L["nenhuma quest de elite ou masmorra no log."]) end
end

-- Spec 053, R5: entrega pronta de outro hub com o NPC no caminho do circuito entra nele.
local function addTurnInsOnTheWay(c, hub, level, readyLog)
    local D, db = ns.Data, ns.FP.db
    local inCircuit, extras = {}, {}
    for _, k in ipairs(c.kept) do inCircuit[k.id] = true end
    local function credit(q)
        local xp = (D.QuestXP(q, level)) or 0
        c.value, c.xp = c.value + xp, (c.xp or 0) + xp -- R5: valor e XP do circuito
        c.names[q] = (D.Q.name(q) or (L["Quest "] .. q)) .. L[" (entrega no caminho)"]
    end
    for _, q in ipairs(readyLog) do
        if not inCircuit[q] then
            local p = ns.Planner.Nearest(hub.points[1], D.FinisherPoints(q))
            local same -- R5 (parecer): o circuito já para nesse NPC; a entrega sai lá, sem parada nova
            for _, st in ipairs(c.stops) do
                if p and st.point and st.point.source ~= nil and st.point.source == p.source then same = true; break end
            end
            if p and not same and ns.Planner.SameContinent(hub.points[1], p) == true then -- spec 053, R4b
                extras[#extras + 1] = { kind = "entregar", key = "entregar-caminho:" .. q, quests = { q }, point = p,
                    points = { p }, quest = q }
            end
        end
    end
    local speed = db.runSpeed or 7
    local added, cost = {}, 0
    if #extras > 0 then
        local out
        out, added, cost = ns.Leveling.OnTheWay(c.stops, extras, db.flightMaxDetour or 400, ns.Planner.Distance, hub.points[1])
        if #added > 0 then c.stops = out end
    end
    if #added == 0 then return end
    c.legs = (c.legs or 0) + cost
    c.seconds = c.seconds + cost / speed + 10 * #added
    for _, a in ipairs(added) do
        credit(a.stop.quest)
        ns.FP.Debug(string.format("entrega no caminho: %s, desvio %.0f jd", tostring(c.names[a.stop.quest]), a.cost))
    end
    c.rate = c.seconds > 0 and c.value / c.seconds * 3600 or 0
end

-- Ranking de um mapa, sem cache (a aba Level, spec 035, pede vários mapas de uma vez).
-- yield, opcional, é chamado a cada hub.
function Guide.RankMap(mapID, player, level, yield)
    local D = ns.Data
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
    -- Spec 045, R2 (emenda de 21/11/2026): pontos de voo a abrir do mapa do hub e dos mapas onde
    -- ficam as paradas (hub de Thunder Bluff com objetivos em Stonetalon: Sun Rock Retreat).
    local redByMap = {}
    local function redOf(map)
        if redByMap[map] == nil then
            local list = {}
            for _, p in ipairs(ns.Planner.FlightNodesWithZone(map, Guide.MapZone)) do if p.known == false then list[#list + 1] = p end end
            redByMap[map] = list
        end
        return redByMap[map]
    end
    local readyLog = {} -- spec 053, R5: prontas para entregar (uma lista por ranking)
    for _, q in ipairs(D.LogQuests()) do
        if ns.Planner.State(q) == "entregar" then readyLog[#readyLog + 1] = q end
    end
    local rows = {}
    -- Spec 068, R2: a rota da zona é mais um hub, com o log de todos os hubs.
    local list = {}
    for _, hub in ipairs(hubs) do list[#list + 1] = hub end
    if #hubs >= 2 and ns.FP.db.zoneRoute ~= false then
        local z = Guide.ZoneHub(hubs, mapID)
        local zl = {}
        for _, hub in ipairs(hubs) do for _, q in ipairs(logByHub[hub.key] or {}) do zl[#zl + 1] = q end end
        logByHub[z.key] = zl
        list[#list + 1] = z
    end
    for _, hub in ipairs(list) do
        local c = buildCircuit(hub, level, player, logByHub, hubs)
        if #c.kept > 0 and ns.FP.db.turnInsOnTheWay ~= false then addTurnInsOnTheWay(c, hub, level, readyLog) end -- spec 053, R5; 058
        if #c.kept > 0 then
            local red, seenMap, seenNode = {}, {}, {}
            local maps = { mapID }
            -- R2c (emenda de 24/11/2026): também a zona onde o jogador está. Terminada a quest em
            -- Stonetalon, sobravam só entregas em Thunder Bluff, e Sun Rock Retreat saía da conta.
            local here = player and player.mapID and Guide.ZoneMap(player.mapID)
            if here then maps[#maps + 1] = here end
            for _, s in ipairs(c.stops) do if s.point and s.point.mapID then maps[#maps + 1] = s.point.mapID end end
            for _, m in ipairs(maps) do
                if not seenMap[m] then
                    seenMap[m] = true
                    for _, p in ipairs(redOf(m)) do
                        if not seenNode[p.id] then seenNode[p.id] = true; red[#red + 1] = p end
                    end
                end
            end
            ns.FP.Debug(string.format("voo no circuito: hub %s, %d mapa(s), %d ponto(s) vermelho(s)", tostring(hub.key),
                #maps, #red))
            if #red > 0 and ns.FP.db.flightStops ~= false then c.hubName, c.hubKey = hub.name, hub.key; addFlightStops(c, red, player) end -- spec 058
        end
        if #c.kept > 0 or #c.aside > 0 then
            local ready = 0
            for _, k in ipairs(c.kept) do if k.state == "entregar" then ready = ready + 1 end end
            rows[#rows + 1] = { key = hub.key, name = hub.name, hub = hub, circuit = c, ready = ready, zone = hub.zone,
                dist = ns.Planner.Distance(player, hub.points[1]) }
        end
        if yield then yield() end
    end
    table.sort(rows, function(a, b) return a.circuit.rate > b.circuit.rate end)
    return rows
end

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
    local rows = Guide.RankMap(mapID, player, level)
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
local function stopLabel(stop, names, point)
    if stop.kind == "objetivo" then -- spec 013, R6: no objeto, diz o que pegar
        local p = point or stop.point
        local obj = p and type(p.source) == "string" and p.source:match("^o%d+$") and ns.Data.PointName(p)
        return ns.Util.ObjectiveTitle(stop.label, obj or nil)
    end
    if stop.kind == "voo" then return L["Abrir ponto de voo: "] .. (stop.label or "?") end -- spec 045, R5
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
    Guide.lastFollowed = row -- spec 058, R4: o plano inclui o hub seguido
    -- spec 059, R7: sem as paradas que o jogador pulou
    local stops = ns.Leveling.FilterSkipped(row and row.circuit.stops or {}, Guide.stopSkip, _G.GetTime(), stopID)
    if #stops == 0 then
        local waiting, mins = Guide.HubWaiting(g.hub, row and row.circuit.stops) -- spec 059, R5 e R7
        if #waiting > 0 then
            Guide.current = nil
            ns.Gps.Clear(true)
            if Guide.waitNote ~= g.hub .. ":" .. mins then
                Guide.waitNote = g.hub .. ":" .. mins
                ns.FP.Print(string.format(L["esperando %s: volta em %d min."], table.concat(waiting, ", "), mins))
            end
            return
        end
        ns.FP.Debug(string.format("step: circuito concluído (hub=%s row=%s)", g.hub, tostring(row ~= nil)))
        ns.FP.db.guide, Guide.current = nil, nil
        ns.Gps.Clear()
        ns.FP.Print(L["circuito concluído:"], row and row.name or "hub")
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
    Guide.current = { id = stopID(stop), point = point, visited = visited,
        quests = stop.kind == "objetivo" and stop.quests or nil } -- spec 067, R5
    ns.FP.Debug(string.format("step hub=%s parada=%s ponto=%.1f,%.1f paradas=%d mantida=%s",
        g.hub, Guide.current.id, point.x or -1, point.y or -1, #stops, tostring(cur ~= nil and cur.id == Guide.current.id)))
    ns.Gps.SetTarget(point.mapID, point.x, point.y, stopLabel(stop, row.circuit.names, point))
    -- R18: o plano sob a seta.
    local idx = 1
    for i, s in ipairs(stops) do if s == stop then idx = i end end
    local info = { string.format(L["%s · parada %d de %d · ~%d min"], row.name, idx, #stops,
        math.floor((row.circuit.seconds or 0) / 60 + 0.5)) }
    local shown = 0
    for i, s in ipairs(stops) do
        if i ~= idx and shown < 2 then
            shown = shown + 1
            info[#info + 1] = (shown == 1 and L["depois: "] or "") .. stopLabel(s, row.circuit.names)
        end
    end
    ns.Gps.SetInfo(info)
    ns.FP.Fire("CHANGED")
end

function Guide.Follow(key)
    local changed = not (ns.FP.db.guide and ns.FP.db.guide.hub == key)
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
    if changed then ns.FP.Fire("FOLLOW", "hub", key, row and row.circuit.rate) end -- spec 036, R9
    Guide.Invalidate()
    Guide.Step()
end

-- mode: "best" (R7), "turnin" (Ir entregar) ou "next" (fim de circuito, R6).
-- quiet: sem hub na zona, não avisa no chat (troca de zona, R19).
-- fallback: sem hub na zona, chama fallback() em vez de avisar (spec 006, R6a).
function Guide.FollowBest(mode, quiet, fallback)
    mode = mode or "best"
    ns.FP.AfterCombat("guideBest", function()
        local rows, cands, byKey = Guide.Rank(), {}, {}
        for _, r in ipairs(rows) do
            if #r.circuit.stops > 0 then
                cands[#cands + 1] = { key = r.key, ready = r.ready, quests = #r.circuit.kept,
                    rate = r.circuit.rate, dist = r.dist, zone = r.zone }
                byKey[r.key] = r
            end
        end
        local best = byKey[ns.Leveling.PickHub(cands, mode, ns.FP.db.zoneRoute ~= false) or ""] -- spec 068, R4
        ns.FP.Debug(string.format("melhor hub modo=%s candidatos=%d escolhido=%s", mode, #cands, best and best.key or "nenhum"))
        if best then
            local why = (mode ~= "best" and best.ready > 0) and string.format(L["%d entrega(s) pronta(s)"], best.ready)
                or string.format(L["%s XP/h"], Util.FormatInt(best.circuit.rate))
            ns.FP.Print("seguindo:", best.name, "(" .. why .. ")")
            Guide.Follow(best.key)
        elseif fallback then
            fallback()
        elseif quiet then -- R19: sem hub na zona nova, o hub seguido continua
            ns.FP.Debug("zona: sem hub na zona nova; hub seguido mantido")
        elseif mode == "turnin" then -- spec 035, R22: sem entrega na zona, a pronta mais perto de qualquer zona
            local LG = ns.LevelGuide
            local e = LG and LG.NearestTurnIn()
            if not e then
                ns.FP.Print(L["nenhuma quest pronta para entregar nesta zona."])
                return
            end
            local how = e.plan and (ns.Travel.Describe(e.plan) .. " " .. LG.EstLabel(e.plan)) or L["sem caminho calculado"]
            local trip = ns.Leveling.TurnInAction(e.plan) == "viagem"
            local tail = trip and L["; na chegada, use /fp entregar de novo"] or ""
            if e.zone == Guide.PlayerArea() then -- pronta na zona, mas fora dos circuitos (cidade sem hub)
                ns.FP.Print(string.format(L["seguindo a entrega de %s (%s)%s"], tostring(e.name), how, tail))
            else
                ns.FP.Print(string.format(L["nenhuma pronta nesta zona; seguindo a entrega de %s em %s (%s)%s"], tostring(e.name),
                    Guide.AreaName(e.zone), how, tail))
            end
            LG.FollowTurnIn(e, true)
        else
            ns.FP.Print(L["nenhum hub com circuito nesta zona."])
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

-- Spec 039, R7: taxa do bloco (a quest no log e os passos adiante); nil sem passos.
local function chainRateOf(q, est, level)
    local a = ns.Data.ChainAhead(q, level)
    if a.n == 0 then return nil end
    return ns.Leveling.ChainBlock(est, { a }).rate
end

function Guide.CleanupList(mapID)
    local D = ns.Data
    if not dataReady() then return {} end
    local level = UnitLevel("player")
    mapID = mapID or Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
    local items = {}
    for _, row in ipairs(Guide.Rank(mapID)) do
      if not row.zone then -- spec 068 (parecer): a rota da zona repete as quests dos hubs
        local c = row.circuit
        local hubRate = c.seconds > 0 and c.value / c.seconds or 0
        local logQuests = {}
        for _, k in ipairs(c.kept) do if k.state == "fazer" then logQuests[#logQuests + 1] = k end end
        for _, a in ipairs(c.aside) do -- spec 046, R6: o que saiu da rota mas segue no log
            if (a.reason == K("rende pouco") or a.reason == "cinza") and D.IsOnQuest(a.id) then
                logQuests[#logQuests + 1] = { id = a.id, state = "fazer" }
            end
        end
        for _, k in ipairs(logQuests) do
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
                classQuest = (D.Q.requiredClasses(k.id) or 0) ~= 0, bagReward = D.WantsBag(k.id),
                chainUpgrade = chainUpgrade, chainXP = chainXP, medianXP = D.medianXPByLevel[qLevel],
                chainRate = chainRateOf(k.id, est, level) } -- spec 039, R7
        end
      end
    end
    local list = ns.Leveling.CleanupCandidates(items, ns.FP.db.threshold or 0.5)
    local names = {}
    for _, it in ipairs(items) do names[it.id] = it.name end
    for _, c in ipairs(list) do c.name = names[c.id] or (L["Quest "] .. c.id) end
    return list
end

------------------------------------------------------------------------------------------
-- Bolsas (spec 010, R5): do log ou disponível na zona atual primeiro, depois menor nível.
-- Emenda de 12/11/2026: o jogador escolhe na lista (R6) ou dispensa (R7, R8).
------------------------------------------------------------------------------------------
function Guide.BestBag()
    if not dataReady() then return nil end
    local zone = Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
    return ns.Leveling.PickBag(ns.Data.BagQuests(UnitLevel("player")), zone)
end

-- R10: com a quest atrás de outra, segue o primeiro passo da cadeia.
local function followBagEntry(b)
    local s = b.step or b
    local via = b.step and string.format(L[" · começa por %s (%s)"], s.name, s.zone) or ""
    ns.FP.Debug("bolsa: seguir " .. s.q .. (b.step and (" (cadeia de " .. b.q .. ")") or ""))
    if ns.Planner.Follow(s.q) then
        ns.FP.Print(string.format(L["seguindo bolsa: %s (%s, %s) — %s%s"], b.name, b.itemName or L["bolsa"], b.zone, L[s.status], via))
    end
end

function Guide.FollowBag()
    ns.FP.AfterCombat("followBag", function()
        local b = Guide.BestBag()
        if not b then ns.FP.Print(L["nenhuma quest de bolsa disponível agora."]); return end
        followBagEntry(b)
    end)
end

local function bagEntry(q)
    if not dataReady() then return nil end
    for _, b in ipairs(ns.Data.BagQuests(UnitLevel("player"))) do
        if b.q == q then return b end
    end
end

-- R6: segue a quest de bolsa escolhida na lista, se estiver no log ou disponível.
function Guide.FollowBagQuest(q)
    ns.FP.AfterCombat("followBag", function()
        local b = bagEntry(q)
        if not b then ns.FP.Print(L["essa quest de bolsa não está mais na lista."]); return end
        local s = b.step or b
        if s.status ~= K("no log") and s.status ~= K("disponível") then
            ns.FP.Print(string.format(L["%s ainda não dá para fazer: %s%s."], b.name, L[s.status],
                b.step and (L[" (começa por "] .. s.name .. ")") or ""))
            return
        end
        followBagEntry(b)
    end)
end

-- R7: dispensa a quest de bolsa, ou volta atrás. Devolve true se ficou dispensada.
function Guide.ToggleBagSkip(q)
    local db = ns.FP.db
    db.bagSkipped = db.bagSkipped or {}
    db.bagSkipped[q] = not db.bagSkipped[q] or nil
    -- R8: a proteção e a marca do circuito mudam já, também no circuito seguido e na sugestão de zona.
    Guide.Invalidate()
    Guide.ResetZoneAdvice()
    if db.guide then ns.FP.AfterCombat("guideStep", Guide.Step) end
    local name = ns.Data.Q.name(q) or (L["Quest "] .. q)
    ns.FP.Print(db.bagSkipped[q] and (name .. L[" dispensada: o \"Bolsa\" não vai mais a ela."])
        or (name .. L[" voltou para as quests de bolsa."]))
    ns.FP.Debug("bolsa: dispensada " .. q .. " = " .. tostring(db.bagSkipped[q] == true))
    ns.FP.Fire("CHANGED")
    return db.bagSkipped[q] == true
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
        ns.FP.Print(string.format(L["%d quest(s) abandonada(s)."], #ids))
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
    if row ~= nil and #row.circuit.stops > 0 then return true end
    return #(Guide.HubWaiting(key, row and row.circuit.stops)) > 0 -- spec 059, R5 e R7: hub esperando continua salvo
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
    -- Spec 059, R3: chegou para pegar e, em 30 s, nem diálogo nem quest: quem dá não está aqui.
    if cur and cur.id:find("^pegar:") then Guide.WatchAbsent(cur.id) end
    -- Spec 045, R6a: chegou ao ponto de voo e não abriu o mestre em 20 s: a parada sai na sessão.
    if cur and cur.id:find("^voo:") then
        local id = cur.id
        C_Timer.After(20, function()
            local now = Guide.current
            if now and now.id == id then flightSkip[id] = true; invalidateAndStep() end
        end)
    end
    C_Timer.After(1.5, step)
end)
-- Spec 059, R3: vigia da parada "pegar" desde a primeira chegada; a decisão é Leveling.AbsentDecision.
local ABSENT_SKIP, ABSENT_WAIT, ABSENT_NEAR = 600, 30, 40
Guide.pickSkip, Guide.pickSkipHub = {}, {}
local watch -- { id, npc, dialog }
ns.FP.On("QUEST_DIALOG", function()
    if not watch then return end
    local guid = _G.UnitGUID and _G.UnitGUID("npc")
    local _, id = Util.EntityFromGUID(guid)
    if not id or not watch.npc or tostring(id) == tostring(watch.npc) then watch.dialog = true end
end)
local function absentCheck(id)
    if not (watch and watch.id == id) then return end
    local cur = Guide.current
    local same = cur and cur.id == id
    local p = ns.Planner.PlayerPoint()
    local d = same and p and ns.Planner.Distance(p, cur.point)
    local what = ns.Leveling.AbsentDecision({ same = same, dialog = watch.dialog, near = d ~= nil and d <= ABSENT_NEAR,
        combat = _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") })
    if what == "esperar" then C_Timer.After(10, function() absentCheck(id) end); return end
    watch = nil
    if what ~= "dispensar" then return end
    local g = ns.FP.db.guide
    local row = g and Guide.Find(g.hub)
    local D, stop = ns.Data, nil
    for _, s in ipairs(row and row.circuit.stops or {}) do if stopID(s) == id then stop = s; break end end
    if not stop then return end
    local names, escort, untilT = {}, false, _G.GetTime() + ABSENT_SKIP
    for _, q in ipairs(stop.quests or {}) do
        if not D.IsOnQuest(q) then
            Guide.pickSkip[q], Guide.pickSkipHub[q] = untilT, g.hub
            names[#names + 1] = D.Q.name(q) or tostring(q)
            escort = escort or Util.IsEscort(D.Q.objectivesText(q))
        end
    end
    if #names == 0 then return end
    ns.FP.Print(string.format(L["%s não está aqui: %s sai(em) da rota por 10 min%s."], tostring(D.PointName(stop.point) or L["quem dá a quest"]),
        table.concat(names, ", "), escort and L[" (escolta: outro jogador pode estar com ele; ele volta em alguns minutos)"] or ""))
    invalidateAndStep()
    C_Timer.After(ABSENT_SKIP + 1, invalidateAndStep)
end
function Guide.WatchAbsent(id)
    if watch and watch.id == id then return end -- R3: a primeira chegada vale; não reinicia
    local npc = id:match("^pegar:(%d+)$")
    watch = { id = id, npc = npc and tonumber(npc) or nil, dialog = false }
    C_Timer.After(ABSENT_WAIT, function() absentCheck(id) end)
end

-- R5: quests do hub seguido dispensadas agora (nomes e minutos que faltam).
function Guide.HubWaiting(hubKey, stops)
    local now, names, left = _G.GetTime(), {}, 0
    local present = {} -- R7: só conta a pulada que ainda está no circuito (parecer 006-059)
    for _, s in ipairs(stops or {}) do present[stopID(s)] = true end
    for q, hub in pairs(Guide.pickSkipHub) do
        if hub == hubKey and ns.Leveling.SkipActive(Guide.pickSkip, q, now) then
            names[#names + 1] = ns.Data.Q.name(q) or tostring(q)
            left = math.max(left, Guide.pickSkip[q] - now)
        end
    end
    for id, s in pairs(Guide.stopSkipInfo) do -- spec 059, R7: as puladas pelo jogador
        if s.hub == hubKey and present[id] and ns.Leveling.SkipActive(Guide.stopSkip, id, now) then
            names[#names + 1] = s.label
            left = math.max(left, Guide.stopSkip[id] - now)
        end
    end
    return names, math.ceil(left / 60)
end

-- Spec 059, R7: "Pular esta parada" (menu + e /fp pular): a parada atual sai por 10 minutos.
Guide.stopSkip, Guide.stopSkipInfo = {}, {}
function Guide.SkipCurrent()
    local g, cur = ns.FP.db.guide, Guide.current
    if not (g and cur) then ns.FP.Print(L["nenhuma parada de hub sendo seguida."]); return end
    local row = Guide.Find(g.hub)
    local label = cur.id
    for _, s in ipairs(row and row.circuit.stops or {}) do
        if stopID(s) == cur.id then label = stopLabel(s, row.circuit.names); break end
    end
    if cur.id:find("^voo:") then -- R7: voo usa a dispensa de voo (spec 045, R6a), que vale na sessão
        flightSkip[cur.id] = true
        ns.FP.Print(string.format(L["parada pulada nesta sessão: %s"], label))
    else
        Guide.stopSkip[cur.id] = _G.GetTime() + ABSENT_SKIP
        Guide.stopSkipInfo[cur.id] = { hub = g.hub, label = label }
        ns.FP.Print(string.format(L["parada pulada por 10 min: %s"], label))
    end
    Guide.current = nil
    invalidateAndStep()
    C_Timer.After(ABSENT_SKIP + 1, invalidateAndStep)
end
ns.FP.On("READY", function() C_Timer.After(1, invalidateAndStep) end) -- R4: retoma depois do /reload
ns.FP.On("DATA_READY", invalidateAndStep) -- R4: o índice termina segundos depois do READY
ns.FP.On("TAXI_KNOWN", invalidateAndStep) -- spec 045, R6: ponto aberto sai do circuito

------------------------------------------------------------------------------------------
-- Sugestão de zona (spec 029): ficar, ir para outra zona ou fazer grind
------------------------------------------------------------------------------------------
local function zoneParams()
    local db, Lev = ns.FP.db, ns.Leveling
    return { perKill = ns.FP.KillSeconds(), killCurve = ns.FP.KillCurve(), factor = ns.FP.MobXPFactor(), minSpawns = db.grindMinSpawns,
        overhead = Lev.OVERHEAD, legYards = Lev.UNKNOWN_LEG, speed = db.runSpeed or 7, objectSeconds = Lev.OBJECT_SECONDS,
        farDelivery = db.farDelivery, unknownKills = db.unknownKills, travelSame = db.travelSame,
        travelOther = db.travelOther, stay = db.zoneStay, minVisit = db.zoneMinVisit,
        lookahead = db.zoneLookahead, threshold = db.threshold or 0.5,
        mobTolerance = (ns.FP.MobTolerance()), -- spec 031, R7 (e o modo fácil, spec 063, R2)
        easy = Lev.EasyActive(db.easyMode, UnitLevel("player")) } -- spec 063, R3 e R2a: grind só de L-4 a L-2
end
Guide.ZoneParams = zoneParams -- tools/pesquisa_zonas.lua usa os mesmos parâmetros (R23)

local doneLookup = setmetatable({}, { __index = function(_, q) return ns.Data.IsCompleted(q) end })

-- Valor e tempo de uma quest do catálogo no nível L (R9, R10, R12). Também usada pela pesquisa.
function Guide.ZoneQuestEntry(info, lvl, p, unlock)
    local D, Z = ns.Data, ns.Zones
    local q = info.id
    local kills, objects, mobXP = 0, 0, 0
    for _, o in ipairs(D.Objectives(q, lvl, p.factor)) do
        -- spec 030, R5: kill de mob alto conta como mais tempo (o XP é o da kill mesmo)
        kills = kills + o.kills * ns.Leveling.KillSecondsFor(p.killCurve, p.perKill, o.avgLevel, lvl) / p.perKill -- spec 067, R7
        objects, mobXP = objects + o.objects, mobXP + o.kills * o.mobXP
    end
    local seconds, used = Z.QuestSeconds({ kills = kills, objects = objects, far = info.far,
        unknownWork = info.unknownWork }, p)
    if info.unknownWork then mobXP = used * ns.Leveling.MobXPRange(lvl, info.level, info.level, p.factor) end
    return { id = q, value = (D.QuestXP(q, lvl)) + mobXP, seconds = seconds, unlock = unlock or 0,
        requires = D.Prerequisites(q) }
end

-- Oferta de uma zona no nível L (R12), com o XP que as cadeias destravam (R2) e a cinza que destrava (R3).
local function zoneOffer(cat, zone, lvl, p)
    local D, Z = ns.Data, ns.Zones
    local entries = {}
    for _, q in ipairs(cat.zones[zone].quests) do
        local info = cat.info[q]
        if info.solo and info.level <= lvl + 3 and D.IsEligible(q, lvl)
            and not ns.Leveling.ObjectivesTooHigh(D.Objectives(q, lvl, p.factor), lvl, nil, p.mobTolerance) then -- spec 030, R4; 031, R7
            local unlock = Z.ChainAhead(q, cat, zone, lvl, doneLookup)
            local gray = lvl - info.level >= 10
            if D.IsRelevant(q, lvl) or (gray and unlock > 0 and D.IsRelevant(q, info.level)) then
                entries[#entries + 1] = Guide.ZoneQuestEntry(info, lvl, p, unlock)
            end
        end
    end
    local o = Z.Offer(entries, p.threshold, function(id, seen) return Z.ChainAhead(id, cat, zone, lvl, doneLookup, seen) end)
    o.estimated = 0 -- R9: quests novas do Forever da oferta com XP pela mediana
    for _, e in ipairs(o.kept) do
        local info = cat.info[e.id]
        if info.forever and info.xpSrc == "estimativa" then o.estimated = o.estimated + 1 end
    end
    return o
end

local function areaName(area)
    if not area then return L["zona desconhecida"] end
    local map = ns.Data.areaToMap[area]
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or (L["área "] .. tostring(area))
end
Guide.AreaName = areaName
Guide.ZoneOffer = zoneOffer -- spec 035: a aba Level usa a mesma oferta de zona

-- Spec 032, R4: faixa de nível da zona, calculada uma vez por catálogo.
local levels = { cat = nil, byZone = {} }
local function capital(zone)
    for _, list in pairs((ns.ZoneContent and ns.ZoneContent.enemyCities) or {}) do
        if list[zone] then return true end
    end
    return false
end

function Guide.ZoneLevels(zone)
    local cat = ns.Data.zoneCatalog
    if not (cat and zone) then return nil end
    if levels.cat ~= cat then levels.cat, levels.byZone = cat, {} end
    local hit = levels.byZone[zone]
    if hit == nil then
        hit = false
        local z = cat.zones[zone]
        if z and z.continent and not capital(zone) then
            local quests = {}
            for _, q in ipairs(z.quests or {}) do
                local info = cat.info[q]
                if info and info.solo then quests[info.level] = (quests[info.level] or 0) + 1 end
            end
            local lo, hi = ns.Zones.LevelRange(z.hist, quests)
            if lo then hit = { lo, hi } end
        end
        levels.byZone[zone] = hit
    end
    if not hit then return nil end
    return hit[1], hit[2]
end

-- " (lo–hi)" para pôr depois do nome da zona (R7, R8); vazio sem faixa.
local function rangeSuffix(zone)
    local lo, hi = Guide.ZoneLevels(zone)
    return lo and (" (" .. ns.Zones.FormatRange(lo, hi) .. ")") or ""
end

-- R5: zona (área da zona-mãe) de um uiMapID.
function Guide.MapZone(mapID)
    local D = ns.Data
    local map = Guide.ZoneMap(mapID)
    local area = map and D.mapToArea and D.mapToArea[map]
    return area and D.ZoneOfArea(area)
end

-- Faixa de nível dos mobs que contam no grind (R19).
local function grindLevels(hist, lvl)
    local lo, hi
    for l, s in pairs(hist) do
        if s > 0 and ns.Leveling.MobXP(lvl, l, 1) > 0 and l <= lvl + 2 then
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
function Guide.GrindRates(cat, lvl, p)
    local out = {}
    for zone, z in pairs(cat.zones) do
        if z.continent then out[#out + 1] = { zone = zone, rate = (ns.Zones.GrindRate(z.hist, lvl, p)) } end
    end
    table.sort(out, function(a, b) return a.zone < b.zone end) -- ordem estável
    return out
end

-- Cálculo completo, síncrono (os testes chamam direto). yield, opcional, é chamado a cada zona.
function Guide.ComputeZoneAdvice(yield)
    local D, Z = ns.Data, ns.Zones
    local cat = D.zoneCatalog
    local lvl = UnitLevel("player")
    local levelXP = Z.LevelXP(lvl)
    if not (cat and levelXP) then return nil end
    local p = zoneParams()
    local here = Guide.PlayerArea()
    local hereCont = here and cat.zones[here] and cat.zones[here].continent
    local cur = { zone = here, rate = 0, n = 0 }
    local cands = {}
    for zone, z in pairs(cat.zones) do
        if #z.quests > 0 then
            local o = zoneOffer(cat, zone, lvl, p)
            if zone == here then
                cur.rate, cur.n, cur.offer = o.rate, o.n, o
            elseif o.n > 0 then
                local travel = Z.Travel(here, zone, hereCont, z.continent, p)
                local ahead = zoneOffer(cat, zone, math.min(lvl + p.lookahead, #Z.LEVEL_XP), p)
                local potential = math.max(o.value + o.unlock, ahead.value)
                local raw, eff = Z.Effective(o, travel, potential, levelXP, p.minVisit)
                cands[#cands + 1] = { zone = zone, raw = raw, eff = eff, n = o.n, travel = travel, offer = o,
                    estimated = o.estimated, anyRace = z.anyRace, potential = potential } -- potential: aba Level (035)
            end
        end
        if yield then yield() end
    end
    local grind = Z.PickGrind(Guide.GrindRates(cat, lvl, p), here, GRIND_MARGIN)
    table.sort(cands, function(a, b) return a.eff > b.eff end)
    local d = Z.Decide(cur, cands, grind, p)
    if grind.zone and cat.zones[grind.zone] then grind.lo, grind.hi = grindLevels(cat.zones[grind.zone].hist, lvl) end
    d.level, d.here, d.cur, d.cands, d.grind = lvl, here, cur, cands, grind
    for _, c in ipairs(cands) do if c.zone == d.zone then d.target = c end end
    return d
end

-- R18: recálculo fora de combate, em coroutine, com cache por nível + entregas + zona.
local advice = { key = nil, turnIns = 0, lastNotice = nil, running = false, pending = false }
-- Spec 010, R8: dispensar uma bolsa muda o circuito; a sugestão de zona recalcula na próxima vez.
function Guide.ResetZoneAdvice() advice.key = nil end
function Guide.ZoneAdvice() return advice.result end

local function notify(d)
    if not d or d.action == "stay" then advice.lastNotice = nil; return end
    local key = d.action .. ":" .. tostring(d.zone) .. ":" .. d.level
    if advice.lastNotice == key then return end -- R20: uma vez por ação, zona e nível
    advice.lastNotice = key
    local what = d.action == "go" and (L["ir para "] .. areaName(d.zone)) or (L["grind em "] .. areaName(d.zone))
    ns.FP.Print(L["zona: "] .. what .. " (" .. d.reason .. L[", est.)"])
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
        -- Corrotina pelo Core (constituição 5 e 6; emenda da spec 035).
        ns.FP.RunCoroutine("zoneAdvice", Guide.ComputeZoneAdvice, function(ok, res)
            advice.running = false
            if not ok then ns.FP.Debug("sugestão de zona: erro " .. tostring(res)); return end
            advice.key, advice.result = key, res
            local ms = started and (_G.debugprofilestop() - started)
            ns.FP.Debug(string.format("sugestão de zona: %s %s (%s)%s", res and res.action or "nada",
                res and tostring(res.zone) or "", res and res.reason or "", ms and string.format(" %.0f ms", ms) or ""))
            notify(res)
            ns.FP.Fire("CHANGED")
            if advice.pending then Guide.RefreshZoneAdvice() end
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
    local here = string.format(L["|cFFB38CFFAqui:|r %s%s — %d quests, %s XP/h (est.)"], areaName(d.here), rangeSuffix(d.here), d.cur.n,
        F(math.floor(d.cur.rate + 0.5)))
    local tip
    if d.action == "stay" then
        tip = L["|cFF73E65ASugestão:|r ficar ("] .. d.reason .. L[", est.)"]
    elseif d.action == "go" then
        local t = d.target
        tip = string.format(L["|cFFFFD24DSugestão:|r ir para %s%s — %s XP/h, viagem ~%d min (%s, est.)"],
            areaName(d.zone), rangeSuffix(d.zone),
            F(math.floor((t and t.eff or 0) + 0.5)), math.floor((t and t.travel or 0) / 60 + 0.5), d.reason)
        if t and (t.estimated or 0) > 0 then tip = tip .. L["; XP das quests novas do Forever é estimado"] end
    else
        local g = d.grind
        local mobs = (g.lo and g.hi) and string.format(L["mobs %d–%d, "], g.lo, g.hi) or ""
        tip = string.format(L["|cFFFFD24DSugestão:|r grind em %s — %s%s XP/h (%s, est.)"], areaName(d.zone), mobs,
            F(math.floor(g.rate + 0.5)), d.reason)
    end
    return here .. "\n" .. tip
end

-- R21: /fp zonas, as 5 melhores zonas do nível e o melhor grind.
function Guide.PrintZones()
    ns.FP.AfterCombat("zoneList", function()
        if not ns.Data.zoneCatalog then ns.FP.Print(L["zonas: catálogo ainda montando, tente em alguns segundos."]); return end
        local d = Guide.ComputeZoneAdvice()
        if not d then ns.FP.Print(L["zonas: nada a sugerir neste nível."]); return end
        local F = Util.FormatInt
        ns.FP.Print(string.format(L["zonas para o nível %d (estimativa):"], d.level))
        for i = 1, math.min(5, #d.cands) do
            local c = d.cands[i]
            local extra = ""
            if (c.estimated or 0) > 0 then extra = extra .. string.format(L[", %d novas do Forever com XP estimado"], c.estimated) end
            if (c.anyRace or 0) > 0 then extra = extra .. string.format(L[", %d sem raça na base"], c.anyRace) end
            ns.FP.Print(string.format(L["%d. %s%s: %s XP/h, %d quests, viagem ~%d min%s"], i, areaName(c.zone), rangeSuffix(c.zone),
                F(math.floor(c.eff + 0.5)), c.n, math.floor(c.travel / 60 + 0.5), extra))
        end
        local g = d.grind
        if g.zone and g.rate > 0 then
            ns.FP.Print(string.format(L["melhor grind: %s%s, %s XP/h"], areaName(g.zone),
                (g.lo and g.hi) and string.format(L[" (mobs %d–%d)"], g.lo, g.hi) or "", F(math.floor(g.rate + 0.5))))
        end
        ns.FP.Print((Guide.ZoneAdviceText(d):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end)
end


-- Spec 067, R5: morte seguindo uma parada de objetivo ou uma quest conta para as quests dela.
ns.FP.On("DIED", function()
    local db = ns.FP.db
    if not db then return end
    local qs = (db.guide and Guide.current and Guide.current.quests) or (db.following and { db.following }) or {}
    -- R5a (parecer 067): só conta perto do alvo da seta (morte na viagem ou em outro lugar não é da quest)
    local t, p = ns.Gps.target, ns.Planner.PlayerPoint()
    local dist = t and p and ns.Planner.Distance(p, { mapID = t.mapID, x = t.x, y = t.y }) or nil
    if not ns.Leveling.DeathCounts(dist) then
        ns.FP.Debug("morte longe da parada (" .. tostring(dist and math.floor(dist)) .. " jd): não conta para a quest")
        return
    end
    db.questDeaths, db.questDeathLevel = db.questDeaths or {}, db.questDeathLevel or {}
    local level, changed = UnitLevel("player"), false
    for _, q in ipairs(qs) do
        local before = db.questDeaths[q] or 0
        if (db.questDeathLevel[q] or level) <= level - ns.Leveling.DEATH_LEVELS then before = 0 end -- R2a: velha não soma
        db.questDeaths[q], db.questDeathLevel[q] = before + 1, level
        if not ns.Leveling.DeathRisky(before) and ns.Leveling.DeathRisky(before + 1) then
            changed = true
            ns.FP.Print(string.format(L["%s te matou %d vezes: fora da rota. Para fazer em grupo, /fp grupo quests."],
                ns.Data.Q and ns.Data.Q.name(q) or tostring(q), before + 1))
        end
    end
    ns.FP.Debug("morte: quests da parada " .. table.concat(qs, ","))
    if changed then Guide.Invalidate(); ns.FP.Fire("CHANGED") end
end)

return Guide
