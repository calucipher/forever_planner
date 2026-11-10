-- Planner.lua: ranking de quests por zona (valor / tempo) e escolha do próximo passo do GPS.
local _, ns = ...
local Util = ns.Util
local Planner = {}
ns.Planner = Planner

local UNKNOWN_LEG = 250     -- jardas assumidas quando não há coordenada
local OTHER_CONTINENT = 1500
local OVERHEAD = 20         -- segundos de diálogo/aceitar/entregar

-- Falhas da última avaliação (R26): total e motivo da primeira.
Planner.failures = { count = 0, first = nil }

------------------------------------------------------------------------------------------
-- Funções puras (testadas fora do jogo)
------------------------------------------------------------------------------------------
-- p = { legs = {jardas...}, count = n, kind = "kill"|"loot"|"object"|"talk", ttk = s, speed = yd/s,
--       downtime = s por morte (R5) }
function Planner.EstimateSeconds(p)
    local travel = 0
    for _, d in ipairs(p.legs or {}) do travel = travel + (d or UNKNOWN_LEG) end
    local count = p.count or 1
    local work = 0
    local perKill = (p.ttk or 0) + (p.downtime or 0)
    if p.kind == "kill" then work = count * perKill
    elseif p.kind == "loot" then work = count * perKill / 0.45 -- ~45% de drop médio
    elseif p.kind == "object" then work = count * 8
    end
    return OVERHEAD + travel / (p.speed or 7) + work
end

-- Valor em "XP equivalente": XP da quest + XP de mob + ouro + upgrade com teto (R1, R6).
function Planner.Value(xp, money, delta, mobXP, levelXP, db)
    local base = (xp or 0) + (mobXP or 0)
    local up = ns.Leveling.UpgradeXP(delta, levelXP, db.upgradePerPoint, db.upgradeCap, base)
    return base + (db.goldToXP or 0) * (money or 0) / 100 + up
end

------------------------------------------------------------------------------------------
-- Geometria (depende do jogo)
------------------------------------------------------------------------------------------
local function worldPos(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
    if not pos then return nil end
    local wx, wy = pos:GetXY()
    if Util.IsSecret(wx) then return nil end
    return cont, wx, wy
end

-- Mesma tabela enquanto o jogador não se move: a posição de mundo fica no cache.
local lastPlayer
function Planner.PlayerPoint()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return { mapID = mapID } end
    local x, y = pos:GetXY()
    if Util.IsSecret(x) or not x then return { mapID = mapID } end
    x, y = x * 100, y * 100
    local lp = lastPlayer
    if lp and lp.mapID == mapID and lp.x == x and lp.y == y then return lp end
    lastPlayer = { mapID = mapID, x = x, y = y }
    return lastPlayer
end

-- Cache forte (R24): os pontos da QuestieDB são tabelas estáveis (Data guarda por entidade).
local wpCache = {}
local function resolve(p)
    if not p or not p.x then return nil end
    local c = wpCache[p]
    if c == nil then
        local cont, wx, wy = worldPos(p.mapID, p.x, p.y)
        c = cont and { cont, wx, wy } or false
        wpCache[p] = c
    end
    return c or nil
end

function Planner.Distance(a, b)
    local wa, wb = resolve(a), resolve(b)
    if not wa or not wb then return nil end
    if wa[1] ~= wb[1] then return OTHER_CONTINENT end
    local dx, dy = wa[2] - wb[2], wa[3] - wb[3]
    return math.sqrt(dx * dx + dy * dy)
end

-- Spec 016, R6: true/false se os dois pontos estão no mesmo continente; nil se não der para saber.
function Planner.SameContinent(a, b)
    local wa, wb = resolve(a), resolve(b)
    if not wa or not wb then return nil end
    return wa[1] == wb[1]
end

function Planner.Nearest(from, pts)
    local best, bestD
    for _, p in ipairs(pts or {}) do
        local d = Planner.Distance(from, p)
        if d and (bestD == nil or d < bestD) then best, bestD = p, d end
    end
    if not best and pts and pts[1] then return pts[1], nil end
    return best, bestD
end

------------------------------------------------------------------------------------------
-- Estado de uma quest: "pegar", "fazer", "entregar"
------------------------------------------------------------------------------------------
function Planner.State(q)
    local D = ns.Data
    if not D.IsOnQuest(q) then return "pegar" end
    if D.IsReadyForTurnIn(q) then return "entregar" end
    return "fazer"
end

-- R13 (spec 006): pontos de objetivo já visitados, por quest seguida.
Planner.visited, Planner.lastPoint = {}, nil

-- Próximo ponto do GPS para a quest
function Planner.NextStep(q, from)
    local D = ns.Data
    local state = Planner.State(q)
    local pts, label
    if state == "pegar" then pts, label = D.StarterPoints(q), "Pegar"
    elseif state == "fazer" then pts, label = D.PendingObjectivePoints(q, UnitLevel("player")), "Objetivo"
    else pts, label = D.FinisherPoints(q), "Entregar" end
    if (not pts or #pts == 0) and state == "fazer" then pts, label = D.FinisherPoints(q), "Entregar" end
    local p
    if label == "Objetivo" then
        Planner.visited[q] = Planner.visited[q] or {}
        p = ns.Leveling.NextPoint(pts, from, Planner.visited[q], Planner.Distance)
    else
        p = Planner.Nearest(from, pts)
    end
    return p, label, state
end

------------------------------------------------------------------------------------------
-- Ranking
------------------------------------------------------------------------------------------
function Planner.Evaluate(q, level, player)
    local D, FP = ns.Data, ns.FP
    local db = FP.db
    local state = Planner.State(q)
    local xp, xpSrc = D.QuestXP(q, level)
    local money = D.QuestMoney(q)
    local rewardID, delta, loading = ns.Scoring.BestReward(D.Rewards(q))
    delta = ns.Milestones.EffectiveDelta(delta, ns.ClassGuide.MissingSkillFor(rewardID)) -- spec 011, R6
    local objectives = D.Objectives(q, level, FP.MobXPFactor())

    local legs, cursor = {}, player
    if state == "pegar" then
        local s, d = Planner.Nearest(cursor, D.StarterPoints(q))
        legs[#legs + 1] = d; cursor = s or cursor
    end
    local work, mobXP, objPts = 0, 0, {}
    local perKill = FP.KillSeconds()
    for _, o in ipairs(objectives) do
        if state ~= "entregar" and not o.done then
            for _, p in ipairs(o.points) do objPts[#objPts + 1] = p end
            work = work + o.kills * perKill + o.objects * ns.Leveling.OBJECT_SECONDS
            mobXP = mobXP + o.kills * o.mobXP
        end
    end
    if #objPts > 0 then
        local o, d = Planner.Nearest(cursor, objPts)
        legs[#legs + 1] = d; cursor = o or cursor
    end
    local _, d = Planner.Nearest(cursor, D.FinisherPoints(q))
    legs[#legs + 1] = d
    mobXP = mobXP + ns.Leveling.RestedBonus(mobXP, Util.Num(_G.GetXPExhaustion and _G.GetXPExhaustion()))

    local seconds = Planner.EstimateSeconds({ legs = legs, count = 0, kind = "talk", speed = db.runSpeed }) + work
    local value = Planner.Value(xp, money, delta, mobXP, Util.Num(_G.UnitXPMax and _G.UnitXPMax("player")), db)
    return {
        q = q, name = D.Q.name(q) or ("Quest " .. q), level = D.Q.questLevel(q) or 0,
        state = state, xp = xp, xpSrc = xpSrc, money = money, mobXP = mobXP,
        rewardID = (delta and delta > 0) and rewardID or nil, delta = delta, loadingItems = loading,
        minutes = seconds / 60, rate = value / math.max(seconds / 60, 0.5), value = value,
    }
end

function Planner.Rank(mapID)
    local D = ns.Data
    if not D.Q then return {} end
    local level = UnitLevel("player")
    local player = Planner.PlayerPoint() or { mapID = mapID }
    mapID = mapID or player.mapID
    local rows, failures = {}, { count = 0, first = nil }
    for _, q in ipairs(D.QuestsForMap(mapID)) do
        if D.IsEligible(q, level) and D.IsRelevant(q, level)
            and not ns.Leveling.TooHigh(D.Q.questLevel(q), level, Planner.State(q)) then -- spec 025, R4
            local ok, row = pcall(Planner.Evaluate, q, level, player)
            if ok and row then rows[#rows + 1] = row
            else
                failures.count = failures.count + 1
                failures.first = failures.first or ("quest " .. q .. ": " .. tostring(row))
            end
        end
    end
    Planner.failures = failures
    table.sort(rows, function(a, b) return a.rate > b.rate end)
    return rows
end

------------------------------------------------------------------------------------------
-- GPS: seguir quest
------------------------------------------------------------------------------------------
function Planner.Follow(q)
    local db = ns.FP.db
    db.following = q
    db.guide = nil -- seguir uma quest desliga o guia de hub (os dois brigavam pela seta)
    if ns.Guide then ns.Guide.current = nil end
    local player = Planner.PlayerPoint()
    local p, label = Planner.NextStep(q, player)
    if not p then
        ns.FP.Print("sem coordenadas para", ns.Data.Q.name(q) or q)
        ns.Gps.Clear()
        return
    end
    Planner.lastPoint = label == "Objetivo" and p or nil
    ns.FP.Debug(string.format("seguir quest %s: %s @%.1f,%.1f", tostring(q), label, p.x, p.y))
    local kind = ({ Pegar = "pegar", Entregar = "entregar" })[label] or "objetivo"
    local title = ns.Util.TargetTitle(kind, ns.Data.PointName(p), ns.Data.Q.name(q) or tostring(q))
    if kind ~= "objetivo" then title = ns.Util.WithPlace(title, ns.Data.PointPlace(p)) end -- spec 021
    ns.Gps.SetTarget(p.mapID, p.x, p.y, title)
    ns.FP.Fire("CHANGED")
end

-- Spec 014: quests que o jogo não ofereceu no NPC/objeto aberto saem do plano.
local function offeredIDs()
    local offered = {}
    local G = _G.C_GossipInfo
    for _, info in ipairs(G and G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
        if info.questID then offered[info.questID] = true end
    end
    for i = 1, (_G.GetNumAvailableQuests and _G.GetNumAvailableQuests() or 0) do
        local id = _G.GetAvailableQuestInfo and select(5, _G.GetAvailableQuestInfo(i))
        if id then offered[id] = true end
    end
    return offered
end

-- Spec 014, R9: o NPC aberto tem quest pronta para entregar?
local function pendingTurnIn()
    local G = _G.C_GossipInfo
    for _, info in ipairs(G and G.GetActiveQuests and G.GetActiveQuests() or {}) do
        if info.isComplete then return true end
    end
    for i = 1, (_G.GetNumActiveQuests and _G.GetNumActiveQuests() or 0) do
        local _, isComplete = _G.GetActiveTitle(i)
        if isComplete then return true end
    end
    return false
end

-- origem: quem pediu (botão do painel, menu "+", comando), para o registro (R12).
function Planner.ClearUnavailable(origem)
    local n = 0
    for _ in pairs(ns.FP.db.unavailable or {}) do n = n + 1 end
    ns.FP.Debug(string.format("indisponível: %d marca(s) apagada(s) (%s)", n, tostring(origem or "?")))
    ns.FP.db.unavailable = {}
    ns.FP.db.unavailableSeen = {}
    ns.FP.db.unavailableRevived = {}
    if ns.Guide then ns.Guide.Invalidate() end
    ns.FP.Fire("CHANGED")
end

local directOffered -- R11: o que a última lista do mesmo NPC ofereceu (só no modo direto)

-- event: evento do diálogo. "QUEST_PROGRESS" (R11): progresso aberto sem lista; nada oferecido, e
-- entrega pendente se a quest do progresso fecha.
function Planner.CheckOffers(event)
    local direct = event == "QUEST_PROGRESS"
    local D = ns.Data
    if not (D.Q and D.N and _G.UnitGUID) then return end
    local kind, id = ns.Util.EntityFromGUID(_G.UnitGUID("npc"))
    if not kind then return end
    local source = kind == "npc" and D.N or D.O
    local level = UnitLevel("player")
    local offered, candidates = direct and (directOffered or {}) or offeredIDs(), {}
    local turnInPending -- R9: a próxima da chain só aparece depois da entrega
    if direct then turnInPending = _G.IsQuestCompletable and _G.IsQuestCompletable() == true
    else turnInPending = pendingTurnIn() end
    for _, q in ipairs(source.questStarts(id) or {}) do
        if offered[q] then
            ns.FP.db.unavailableSeen[q] = nil
            if ns.FP.db.unavailableRevived then ns.FP.db.unavailableRevived[q] = nil end -- R10: oferecida, pode reativar de novo
            if D.IsUnavailable(q) then ns.FP.db.unavailable[q] = nil; ns.FP.Debug("indisponível: voltou " .. q) end
        elseif not turnInPending and D.StartsQuest(kind, id, q) and not D.IsOnQuest(q) and not D.IsUnavailable(q) and D.IsRelevant(q, level) and D.IsEligible(q, level) then
            candidates[#candidates + 1] = q
        end
    end
    local changed = false
    for _, q in ipairs(ns.Util.NotOffered(candidates, offered)) do
        local seen = (ns.FP.db.unavailableSeen[q] or 0) + 1
        ns.FP.db.unavailableSeen[q] = seen
        -- Duas visitas sem oferta (menu com subpágina não vira falso positivo); quest nova do Forever
        -- sem pré-requisito nos dados, uma (R7, emenda de 08/11/2026).
        local single, group = D.Q.preQuestSingle(q), D.Q.preQuestGroup(q)
        local hasPre = (single and #single > 0) or (group and #group > 0)
        if seen >= ns.Util.VisitsToMark(q, hasPre) then
        ns.FP.db.unavailable[q] = true
        changed = true
        ns.FP.Debug(string.format("indisponível: %s não oferecida (%s %s)", q, kind, id))
        ns.FP.Print(string.format("|cFFFFAA00%s não está disponível aqui; tirei do plano.|r Volta sozinha quando o NPC oferecer. (/fp indisponiveis lista as marcadas)",
            D.Q.name(q) or q))
        if ns.FP.db.following == q then Planner.FollowBest() end
        end
    end
    if changed then
        if ns.Guide then ns.Guide.Invalidate() end
        ns.FP.Fire("CHANGED")
        -- R12: a seta sai da quest marcada na hora.
        if ns.Guide and ns.FP.db.guide then ns.FP.AfterCombat("guideStep", function() ns.Guide.Step() end) end
    end
end

-- R12: "Reativar quests" pede confirmação, listando o que volta ao plano.
function Planner.ConfirmClearUnavailable(origem)
    local names = {}
    for q in pairs(ns.FP.db.unavailable or {}) do
        names[#names + 1] = (ns.Data.Q and ns.Data.Q.name(q)) or tostring(q)
    end
    if #names == 0 then ns.FP.Print("nenhuma quest marcada como indisponível."); return end
    table.sort(names)
    local dialogs, show = _G.StaticPopupDialogs, _G.StaticPopup_Show
    local function run()
        Planner.ClearUnavailable(origem)
        ns.FP.Print(#names .. " quest(s) que o jogo não oferecia voltaram ao plano.")
    end
    if not (dialogs and show) then run(); return end
    dialogs.FOREVERPLANNER_REATIVAR = {
        text = "Voltar ao plano as quests que o jogo não ofereceu?\n\n%s\n\n(Para só atualizar a seta, use 'Recalcular rota'.)",
        button1 = "Reativar", button2 = "Cancelar", OnAccept = run,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    show("FOREVERPLANNER_REATIVAR", table.concat(names, "\n"))
end

local PROGRESS_WINDOW = 60 -- R11: lista ou progresso do mesmo NPC nesse intervalo já contou a visita
local lastList, lastDirect
ns.FP.On("QUEST_DIALOG", function(event)
    local guid = _G.UnitGUID and _G.UnitGUID("npc")
    local now = _G.GetTime and _G.GetTime()
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        lastList = { guid = guid, t = now, offered = offeredIDs() }
        Planner.CheckOffers(event)
    elseif event == "QUEST_PROGRESS" and guid and ns.Util.DirectProgress(lastList, guid, now, PROGRESS_WINDOW)
        and ns.Util.DirectProgress(lastDirect, guid, now, PROGRESS_WINDOW) then
        lastDirect = { guid = guid, t = now }
        directOffered = lastList and lastList.guid == guid and lastList.offered or nil
        Planner.CheckOffers(event)
        directOffered = nil
    end
end)

-- Spec 014, R8: entregar uma quest reativa as marcadas do mesmo hub (a chain pode ter liberado).
function Planner.ReactivateNear(turnedIn)
    local D = ns.Data
    local marks = ns.FP.db.unavailable
    if not (D.Q and marks and next(marks)) then return end
    local turnPoints = {}
    for _, p in ipairs(D.StarterPoints(turnedIn)) do turnPoints[#turnPoints + 1] = p end
    for _, p in ipairs(D.FinisherPoints(turnedIn)) do turnPoints[#turnPoints + 1] = p end
    local revived = ns.FP.db.unavailableRevived or {}
    ns.FP.db.unavailableRevived = revived
    local candidates = {}
    for q in pairs(marks) do
        if not revived[q] then candidates[#candidates + 1] = { q = q, points = D.StarterPoints(q) } end -- R10
    end
    local back = ns.Util.NearTurnIn(candidates, turnPoints, ns.FP.db.hubRadius or 80, Planner.Distance)
    for _, q in ipairs(back) do
        marks[q] = nil; ns.FP.db.unavailableSeen[q] = nil; revived[q] = true
        ns.FP.Debug("indisponível: reativada " .. q .. " (entrega de " .. tostring(turnedIn) .. " no mesmo hub)")
    end
    if #back > 0 and ns.Guide then ns.Guide.Invalidate() end
end
ns.FP.On("QUEST_TURNED_IN", function(q) q = ns.Util.Num(q); if q then Planner.ReactivateNear(q) end end)

-- Mapa do continente que contém o mapa dado (sobe pelos pais até o tipo Continente).
function Planner.ContinentMap(map)
    local info = map and C_Map.GetMapInfo(map)
    local E = _G.Enum
    local continent = E and E.UIMapType and E.UIMapType.Continent or 2
    while info and info.mapType and info.mapType > continent and info.parentMapID and info.parentMapID > 0 do
        map = info.parentMapID; info = C_Map.GetMapInfo(map)
    end
    return map
end

-- Spec 018, R1/R3: seta no ponto de voo descoberto mais perto (API do jogo, continente do jogador).
function Planner.FollowFlightPoint()
    local T = _G.C_TaxiMap
    if not (T and T.GetAllTaxiNodes and C_Map and C_Map.GetBestMapForUnit) then
        ns.FP.Print("este client não informa os pontos de voo."); return
    end
    local map = Planner.ContinentMap(C_Map.GetBestMapForUnit("player"))
    local E = _G.Enum
    local states = E and E.FlightPathState or { Reachable = 0, Current = 1 }
    local pts = ns.Util.TaxiPoints(T.GetAllTaxiNodes(map), map, function(s) return s == states.Reachable or s == states.Current end)
    local from = Planner.PlayerPoint()
    if not from then ns.FP.Print("não consegui ler a sua posição agora."); return end
    local best = Planner.Nearest(from, pts)
    if not best then ns.FP.Print("nenhum ponto de voo descoberto neste continente."); return end
    ns.FP.Print("seguindo: ponto de voo " .. tostring(best.name))
    ns.Gps.SetTarget(best.mapID, best.x, best.y, "Ponto de voo: " .. tostring(best.name))
end

function Planner.FollowBest()
    ns.FP.AfterCombat("followBest", function()
        local rows = Planner.Rank()
        if rows[1] then
            Planner.Follow(rows[1].q)
            ns.FP.Print("seguindo:", rows[1].name)
        else
            ns.FP.Print("nenhuma quest elegível nesta zona.")
        end
    end)
end

-- Reavalia o passo quando o log muda / ao chegar no ponto
local function refreshFollow()
    local q = ns.FP.db and ns.FP.db.following
    if q then ns.FP.AfterCombat("refollow", function() Planner.Follow(q) end) end
end
ns.FP.On("QUEST_LOG", refreshFollow)
ns.FP.On("QUEST_ACCEPTED", refreshFollow)
ns.FP.On("DATA_READY", refreshFollow) -- retoma a seta depois do /reload (spec 006, R4)
ns.FP.On("GPS_ARRIVED", function()
    local q = ns.FP.db and ns.FP.db.following
    if q and Planner.lastPoint then -- R13: chegou ao ponto do objetivo; o próximo é outro
        Planner.visited[q] = Planner.visited[q] or {}
        Planner.visited[q][Planner.lastPoint] = true
    end
    C_Timer.After(1.5, refreshFollow)
end)
ns.FP.On("QUEST_TURNED_IN", function(q)
    local db = ns.FP.db
    if db.following == q then
        db.following = nil
        ns.Gps.Clear()
        if db.autoNext then C_Timer.After(1, Planner.FollowBest) end
    end
end)

return Planner
