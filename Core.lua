-- Core.lua: SavedVariables, eventos, cache de recompensas reais e slash commands.
local ADDON, ns = ...
local Util = ns.Util

local FP = {}
ns.FP = FP
_G.ForeverPlanner = FP

-- Spec 036, R8a: ação bloqueada pelo jogo, ouvida desde a primeira linha do Core num frame só dela.
-- Antes do banco carregar, o erro espera numa fila (FP.LogError grava no ADDON_LOADED).
local earlyErrors, blockedWarned = {}, false
do
    local watcher = CreateFrame("Frame")
    for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(watcher.RegisterEvent, watcher, ev) end
    watcher:SetScript("OnEvent", function(_, event, addon, func)
        if addon ~= ADDON then return end
        FP.LogError(event .. ": " .. tostring(func))
        if not blockedWarned and FP.Print then
            blockedWarned = true
            FP.Print("o jogo bloqueou a função " .. tostring(func) .. " do addon (" .. event .. "). "
                .. "Mande isto para o suporte; /console taintLog 1 grava os detalhes em Logs/taint.log.")
        end
    end)
end

FP.defaults = {
    preset = "affliction",      -- perfil de pesos (Weights.lua)
    customWeights = {},         -- sobrescritas por stat
    upgradePerPoint = 0.005,    -- 1 ponto de score de upgrade = 0,5% do XP do nível (R6)
    upgradeCap = 0.25,          -- teto do upgrade: 25% do XP do circuito/quest (R6)
    goldToXP = 0,               -- XP equivalente por moeda de prata (0 = ignora ouro)
    ttk = 15,                   -- segundos por kill (calibrável)
    downtime = 10,              -- segundos parados por kill: Life Tap, comer, beber (R5)
    mobXPFactor = 1.0,          -- fator do Forever sobre a fórmula do Classic (R2, C4)
    threshold = 0.5,            -- agressividade: tira quest com taxa < 50% da média do circuito (R27)
    hubRadius = 80,             -- jardas entre quest givers do mesmo hub (R8)
    satelliteMaxDetour = 400,   -- desvio máximo para pegar satélite no caminho (spec 008)
    calib = { xp = {}, kill = {}, danger = {} }, -- amostras reais das últimas mortes (R7) e lutas (spec 031)
    guide = nil,                -- hub seguido pelo GPS { map =, hub = }
    minimap = { angle = 225, hide = false }, -- botão do minimapa (spec 004)
    auto = true,                -- auto accept e auto turn-in (spec 005)
    debug = false,              -- modo debug (spec 009): registra decisões em debugLog
    debugChat = false,          -- também mostra o registro no chat
    debugLog = {},              -- últimas 400 linhas (lidas do disco depois do /reload)
    debugErrors = {},           -- últimos 20 erros de Lua do addon (sempre)
    runSpeed = 7,               -- jardas/s a pé
    showOnlyCurrentZone = true,
    autoNext = true,            -- ao entregar a quest seguida, segue a próxima melhor
    gps = { arrow = true, native = true, tomtom = true, roads = true, caves = true, arriveYards = 12, x = 0, y = -160 },
    ui = { point = "CENTER", x = 0, y = 0, tab = "quests" },
    cache = { xp = {}, money = {} }, -- recompensas reais vistas no diálogo de quest
    following = nil,            -- questID seguido pelo GPS
    unavailable = {},           -- quests que o jogo não ofereceu no NPC (spec 014)
    unavailableSeen = {},       -- visitas em que o NPC não ofereceu a quest (marca na 2ª, spec 014)
    weaponsOff = {},            -- armas que o jogador desabilitou na janela Armas (spec 016)
    bagSkipped = {},            -- quests de bolsa dispensadas pelo jogador (spec 010, R7)
    groupAnnounce = true,       -- avisos de quest no chat do grupo (spec 022)
    -- Sugestão de zona (spec 029, R17): estimativas até calibrar no jogo
    zoneStay = 0.6,             -- fica enquanto render >= 60% da melhor alternativa
    zoneLookahead = 2,          -- ao comparar zonas, conta o que abre em até 2 níveis
    zoneMinVisit = 0.25,        -- zona com < 25% do XP do nível rende proporcionalmente menos
    travelSame = 600,           -- viagem entre zonas do mesmo continente (s)
    travelOther = 1200,         -- viagem entre continentes (s)
    grindMinSpawns = 60,        -- grind só conta com pelo menos 60 spawns na faixa
    unknownKills = 6,           -- quest nova do Forever sem objetivo na base
    farDelivery = 300,          -- entrega em outra zona (s)
    -- Spec 035: viagem real (ESTIMATIVA; a spec 036 mede no jogo). fly/flyFactor/flyOverhead = spec 024.
    travel = { walkFactor = 1.2, fly = 32, flyFactor = 1.25, flyOverhead = 20, boardWait = 150, ride = 90,
        hearthSeconds = 30, hearthMinSave = 300 }, -- hearthMinSave: a pedra só vale se poupar 5 min (R4)
    journalMax = 40000,         -- spec 036: teto do diário (~8 MB de SavedVariables, medido em diário sintético)
    journalSeed = nil,          -- spec 036, R2: semente aleatória da chave do personagem no diário
    hubMinShare = 0.15,         -- spec 035, R16: hub com menos de 15% do XP do nível rende proporcionalmente menos
    bind = nil,                 -- ponto da pedra de lar { mapID, x, y, name } (spec 035, R11)
    -- Spec 037: procurar grupo. Texto em inglês porque o servidor é americano (decisão de 14/11/2026).
    lfgWhisper = "hi! {classe} {nivel} ({papel}) for {atividade}, room for one more?",
    lfgWhisperSolo = "hi! {classe} {nivel} ({papel}), want to group up for {atividade}?",
    lfgListComment = "{classe} {nivel} ({papel}) LF group", -- R15: comentário para se listar sozinho
    lfgCallTTL = 600,          -- R6: chamado vira "sem resposta" depois de 10 min (ESTIMATIVA)
    lfgPrefill = true,          -- R12: false = plano B (texto para Ctrl+C, sem abrir o whisper)
    lfgRole = nil,              -- R8: papel escolhido no painel ("DPS", "Tank", "Healer")
}

function FP.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage("|cFF9482C9[Forever Planner]|r " .. table.concat(parts, " "))
end

-- Modo debug (spec 009). O registro vai para as SavedVariables: o WoW grava no disco a cada
-- /reload e logout, e dá para ler fora do jogo.
local MAX_LOG, MAX_ERRORS = 400, 20
local function stamp()
    local clock = _G.date and _G.date("%H:%M:%S") or ""
    local t = _G.GetTime and _G.GetTime() or 0
    return string.format("[%s t=%.1f]", clock, t)
end
local function push(list, line, limit)
    list[#list + 1] = line
    while #list > limit do table.remove(list, 1) end
end
function FP.Debug(msg, force)
    local db = FP.db
    if not db or not (db.debug or force) then return end
    db.debugLog = db.debugLog or {}
    local line = stamp() .. " " .. tostring(msg)
    push(db.debugLog, line, MAX_LOG)
    if db.debugChat and not force then DEFAULT_CHAT_FRAME:AddMessage("|cFF888888[FP debug]|r " .. tostring(msg)) end
end
function FP.LogError(msg)
    local db = FP.db
    if not db then table.insert(earlyErrors, tostring(msg)); return end -- R8a: grava no ADDON_LOADED
    db.debugErrors = db.debugErrors or {}
    push(db.debugErrors, stamp() .. " " .. tostring(msg), MAX_ERRORS)
    FP.Debug("ERRO: " .. tostring(msg))
end

-- Callbacks simples entre módulos
local listeners = {}
function FP.On(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
function FP.Fire(name, ...)
    for _, fn in ipairs(listeners[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            FP.Print("|cFFFF5555erro em", name, ":", err)
            FP.LogError(name .. ": " .. tostring(err))
        end
    end
end

-- Parâmetros efetivos: medidos no jogo quando há amostras (R7), senão os do db.
local MIN_SAMPLES = 5
local MAX_KILL_GAP = 45 -- spec 009, R7: acima disso o intervalo inclui caminhada e loot
function FP.RecordKillGap(gap)
    if gap and gap > 0 and gap <= MAX_KILL_GAP then ns.Leveling.PushSample(FP.db.calib.kill, gap, 20) end
end
function FP.KillSeconds(minSamples)
    local list = FP.db.calib.kill
    if #list >= (minSamples or MIN_SAMPLES) then
        local copy = {}
        for i, v in ipairs(list) do copy[i] = v end
        return Util.Median(copy) -- mediana: um pull ruim não estraga a média
    end
    return FP.db.ttk + (FP.db.downtime or 0)
end
function FP.MobXPFactor()
    return ns.Leveling.Mean(FP.db.calib.xp, MIN_SAMPLES) or FP.db.mobXPFactor or 1
end

-- Força do personagem (spec 031). Slots de GetInventoryItemLink, na ordem de Leveling.AvgItemLevel.
local GEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18 }
local OFFHAND = 11 -- posição da mão secundária na lista acima
local function slotItemLevel(slot)
    local link = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", slot)
    if not link then return nil, false end
    local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    ilvl = Util.Num(ilvl) or Util.Num((select(4, C_Item.GetItemInfo(link))))
    local equipLoc = C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(link))
    return ilvl, true, equipLoc == "INVTYPE_2HWEAPON"
end
-- Item level médio, ou nil se algum item equipado ainda não está no cache (R1).
function FP.GearItemLevel()
    local levels = {}
    for i, slot in ipairs(GEAR_SLOTS) do
        local ilvl, equipped, twoHand = slotItemLevel(slot)
        if equipped and not ilvl then return nil end
        levels[i] = ilvl or levels[i]
        if twoHand and not levels[OFFHAND] then levels[OFFHAND] = ilvl end
    end
    return ns.Leveling.AvgItemLevel(levels)
end
-- Tolerância de mobs altos (R4, R7): tolerância, fonte e número de amostras de luta.
function FP.MobTolerance()
    local L = ns.Leveling
    local danger = FP.db.calib.danger or {}
    local combat, recentDeath = L.CombatOffset(danger)
    local avg = FP.GearItemLevel()
    local source = combat and "combate" or (avg and "gear" or "padrão")
    return L.MobTolerance(L.GearOffset(avg, UnitLevel("player")), combat, recentDeath), source, #danger
end

-- /fp calib e o botão "Calibração" do menu + (spec 031, R9)
function FP.PrintCalib()
    FP.Print(string.format("tempo por morte: %.1f s (%d amostras) · fator de XP: %.2f (%d amostras)",
        FP.KillSeconds(), #FP.db.calib.kill, FP.MobXPFactor(), #FP.db.calib.xp))
    local tol, source, n = FP.MobTolerance()
    FP.Print(string.format("tolerância de mobs altos: +%.1f nível (fonte: %s, %d lutas; estimativa)",
        tol, source, n))
end

-- Coleta das lutas (R8): o Core só junta os dados; a regra da amostra é Leveling.FightSample (R10).
-- Sem combat log: a API do Forever é a 12.x.
local fight -- { start, min, level, targetAbove, above, group, died, closing }
local FIGHT_CLOSE_DELAY = 1 -- s: o XP do kill pode chegar depois do fim do combate
local function hpFraction()
    local h, m = _G.UnitHealth and _G.UnitHealth("player"), _G.UnitHealthMax and _G.UnitHealthMax("player")
    if Util.IsSecret(h) or Util.IsSecret(m) then return nil end
    h, m = Util.Num(h), Util.Num(m)
    if not (h and m) or m <= 0 then return nil end
    return h / m
end
local function inGroup() return _G.IsInGroup ~= nil and _G.IsInGroup() == true end
local function targetAbove(level)
    if not (level and _G.UnitCanAttack and _G.UnitCanAttack("player", "target")) then return nil end
    local l = UnitLevel("target")
    if Util.IsSecret(l) then return nil end
    l = Util.Num(l)
    return l and l > 0 and l - level or nil -- -1 = caveira: nível desconhecido
end
local function FightFinish(f)
    if f.done then return end -- R8: o timer não grava de novo a luta já fechada
    f.done = true
    local sample = ns.Leveling.FightSample(f)
    if sample then
        FP.db.calib.danger = FP.db.calib.danger or {}
        ns.Leveling.PushSample(FP.db.calib.danger, sample, 20)
    end
    if fight == f then fight = nil end
end
local function FightStart()
    if fight then FightFinish(fight) end -- a luta anterior ainda fechando
    local hp, level = hpFraction() or 1, Util.Num(UnitLevel("player"))
    fight = { start = hp, min = hp, level = level, targetAbove = targetAbove(level), group = inGroup() }
end
local function FightHealth()
    local f = fight and hpFraction()
    if f and f < fight.min then fight.min = f end
end
local function FightKill(mobLevel)
    if fight and fight.level and mobLevel then
        fight.above = math.max(fight.above or -math.huge, mobLevel - fight.level)
    end
end
local function FightEnd()
    if not fight or fight.closing then return end
    FightHealth()
    local f = fight
    f.group, f.closing = f.group or inGroup(), true
    if C_Timer and C_Timer.After then C_Timer.After(FIGHT_CLOSE_DELAY, function() FightFinish(f) end)
    else FightFinish(f) end
end
local function FightDeath()
    if not fight then return end -- queda ou afogamento fora de luta não contam
    fight.died = true
    FightFinish(fight)
end

-- Calibração pelo chat de XP: "X dies, you gain N experience." (R7, D7)
local xpPattern, lastKill
local function OnXPGain(msg)
    if type(msg) ~= "string" or Util.IsSecret(msg) or not ns.Data.N then return end
    xpPattern = xpPattern or Util.FormatToPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON)
    if not xpPattern then return end
    local name, xp = msg:match(xpPattern)
    xp = tonumber(xp)
    if not (name and xp) then return end
    local rested = tonumber(msg:match("%(%+?(%d+)")) or 0
    FP.Fire("KILL_XP", xp, name) -- spec 036: o diário grava a morte com o mob mirado com esse nome
    local now = _G.GetTime and _G.GetTime() or 0
    if lastKill then FP.RecordKillGap(now - lastKill) end
    lastKill = now
    local ids = ns.Data.N.IdsByName and ns.Data.N.IdsByName(name)
    local id = ids and ids[1]
    -- spec 036, R20: o nível visto no jogo (mirando o mob) vale mais que o da QuestieDB pelo nome
    local lvl = (ns.Journal and ns.Journal.SeenLevelByName(name)) or (id and ns.Data.N.minLevel(id))
    if not lvl or lvl <= 0 then return end
    FightKill(lvl) -- spec 031, R8
    local expected = ns.Leveling.MobXP(UnitLevel("player"), lvl, 1)
    if expected > 0 then ns.Leveling.PushSample(FP.db.calib.xp, (xp - rested) / expected, 20) end
end

-- Ações adiadas para depois do combate (nada pesado em combate)
local pending = {}
function FP.AfterCombat(key, fn)
    if Util.InCombat() then pending[key] = fn else fn() end
end

-- Spec 035, R12: cálculo longo em corrotina, um passo por quadro, pausado em combate (constituição 6).
-- O frame fica aqui (constituição 5). fn(yield) devolve o resultado; done(ok, resultadoOuErro).
-- Devolve false se já houver um cálculo com a mesma chave rodando.
local runners = {}
function FP.RunCoroutine(key, fn, done)
    local r = runners[key]
    if r and r.co then return false end
    r = r or { frame = CreateFrame("Frame") }
    runners[key] = r
    r.co = coroutine.create(function() return fn(coroutine.yield) end)
    r.frame:SetScript("OnUpdate", function(self)
        if Util.InCombat() then return end
        local ok, res = coroutine.resume(r.co)
        if not ok or coroutine.status(r.co) == "dead" then
            self:SetScript("OnUpdate", nil)
            r.co = nil
            done(ok, res)
        end
    end)
    return true
end

-- Recompensa real vista na tela da quest: corrige a estimativa
local function CacheQuestRewards()
    local questID = Util.Num(GetQuestID and GetQuestID())
    if not questID or questID == 0 then return end
    local xp = Util.Num(GetRewardXP and GetRewardXP())
    local money = Util.Num(GetRewardMoney and GetRewardMoney())
    local level = UnitLevel("player")
    if xp and xp > 0 then FP.db.cache.xp[questID] = { xp = xp, level = level } end
    if money and money > 0 then FP.db.cache.money[questID] = money end
end

-- Registro protegido: evento que não existe no client (a API do Forever é a 12.x, e nomes
-- do Classic sumiram) é ignorado e avisado no login, em vez de derrubar o addon inteiro.
-- Cada item é um evento ou uma lista de nomes alternativos (registra o primeiro que existir).
local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "QUEST_DETAIL", "QUEST_COMPLETE",
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED",
    "CHAT_MSG_COMBAT_XP_GAIN", "SPELLS_CHANGED", "QUEST_PROGRESS", "GOSSIP_SHOW", "QUEST_GREETING",
    "QUEST_REMOVED", "PLAYER_REGEN_DISABLED", "PLAYER_DEAD", -- spec 031, R8
    "CHAT_MSG_SYSTEM", "PLAYER_ENTERING_WORLD", -- spec 035, R11: ponto da pedra de lar
    -- spec 036: diário (mob visto, morte de mob, saque, tempo jogado, saída)
    -- Sem COMBAT_LOG_EVENT_UNFILTERED: com ele, o cliente mostrou "blocked from an action" (13/11/2026).
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "LOOT_OPENED", "TIME_PLAYED_MSG", "PLAYER_LOGOUT",
    { "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }, -- renomeado no Mainline 11.0
}
FP.missingEvents = {}
local frame = CreateFrame("Frame")
for _, entry in ipairs(EVENTS) do
    local names = type(entry) == "table" and entry or { entry }
    local ok = false
    for _, name in ipairs(names) do
        ok = pcall(frame.RegisterEvent, frame, name)
        if ok then break end
    end
    if not ok then table.insert(FP.missingEvents, table.concat(names, "/")) end
end
do -- spec 031, R8: só o HP do jogador
    local ok = frame.RegisterUnitEvent ~= nil and pcall(frame.RegisterUnitEvent, frame, "UNIT_HEALTH", "player")
    if not ok then ok = pcall(frame.RegisterEvent, frame, "UNIT_HEALTH") end
    if not ok then table.insert(FP.missingEvents, "UNIT_HEALTH") end
end
do -- spec 035, R11: feitiço do jogador (pedra de lar)
    for _, ev in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START" }) do -- START: spec 036, R6
        local ok = frame.RegisterUnitEvent ~= nil and pcall(frame.RegisterUnitEvent, frame, ev, "player")
        if not ok then table.insert(FP.missingEvents, ev) end
    end
end

local itemRefreshQueued = false
local QUIET = { GET_ITEM_INFO_RECEIVED = true, UNIT_HEALTH = true, CHAT_MSG_SYSTEM = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_START = true, UPDATE_MOUSEOVER_UNIT = true }
-- Spec 036: eventos que só alimentam o diário (FP.Fire e nada mais).
local JOURNAL_EVENTS = { PLAYER_TARGET_CHANGED = { "UNIT_LOOK", "target" }, UPDATE_MOUSEOVER_UNIT = { "UNIT_LOOK", "mouseover" },
    LOOT_OPENED = { "LOOT" }, PLAYER_LOGOUT = { "LOGOUT" } }
frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if FP.db and FP.db.debug and not QUIET[event] then
        FP.Debug(string.format("evento %s %s", event, tostring(arg1 or "")))
    end
    if event == "CHAT_MSG_SYSTEM" then
        FP.Fire("SYSTEM_MSG", arg1)
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then FP.Fire("SPELL_DONE", arg3) end
        return
    elseif JOURNAL_EVENTS[event] then
        local e = JOURNAL_EVENTS[event]
        FP.Fire(e[1], e[2])
        return
    elseif event == "TIME_PLAYED_MSG" then
        FP.Fire("TIME_PLAYED", arg1)
        return
    elseif event == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then FP.Fire("SPELL_START", arg3) end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        FP.Fire("ENTERING_WORLD")
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverPlannerDB = Util.CopyDefaults(FP.defaults, ForeverPlannerDB)
        FP.db = ForeverPlannerDB
        for _, msg in ipairs(earlyErrors) do FP.LogError(msg) end -- spec 036, R8a
        earlyErrors = {}
        FP.Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        local ok, msg = ns.Data.Init()
        FP.Debug("login: Data.Init " .. (ok and "ok" or ("falhou: " .. tostring(msg))))
        if not ok then
            FP.Print("|cFFFF5555" .. tostring(msg))
            return
        end
        FP.Fire("READY")
        FP.Print("pronto. |cFFFFFFFF/fp|r abre o painel, |cFFFFFFFF/fp next|r segue a melhor quest.")
        if #FP.missingEvents > 0 then
            FP.Print("|cFFFFAA00eventos que não existem neste client (função ligada a eles fica parada):|r "
                .. table.concat(FP.missingEvents, ", "))
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        FightStart()
    elseif event == "UNIT_HEALTH" then
        if arg1 == "player" then FightHealth() end
    elseif event == "PLAYER_DEAD" then
        FightDeath()
        FP.Fire("DIED") -- spec 036, R8
    elseif event == "PLAYER_REGEN_ENABLED" then
        FightEnd()
        for k, fn in pairs(pending) do pending[k] = nil; pcall(fn) end
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        CacheQuestRewards()
        FP.Fire("QUEST_DIALOG", event)
    elseif event == "QUEST_PROGRESS" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        FP.Fire("QUEST_DIALOG", event)
    elseif event == "QUEST_TURNED_IN" then
        if ns.Data.MarkTurnedIn then ns.Data.MarkTurnedIn(arg1) end -- spec 006, R12
        FP.Fire("QUEST_TURNED_IN", arg1, arg2, arg3) -- spec 036: XP e dinheiro da entrega
        FP.Fire("CHANGED")
    elseif event == "QUEST_REMOVED" then
        FP.Fire("QUEST_REMOVED", arg1) -- spec 006, R15: a quest saiu do log (entregue ou abandonada)
    elseif event == "QUEST_ACCEPTED" then
        FP.Fire("QUEST_ACCEPTED", arg2 or arg1)
        FP.Fire("CHANGED")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if ns.Scoring then ns.Scoring.ClearEquippedCache() end
        FP.Fire("CHANGED")
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        FP.Fire("SPELLS") -- macros FP acompanham o que você aprende (spec 003, R7)
        FP.Fire("CHANGED")
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPGain(arg1)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not itemRefreshQueued and C_Timer then
            itemRefreshQueued = true
            C_Timer.After(0.5, function() itemRefreshQueued = false; FP.Fire("CHANGED") end)
        end
    else -- QUEST_LOG_UPDATE, ZONE_CHANGED_NEW_AREA, PLAYER_LEVEL_UP
        if event == "QUEST_LOG_UPDATE" then FP.Fire("QUEST_LOG") end
        if event == "PLAYER_LEVEL_UP" then FP.Fire("LEVEL_UP", arg1) end -- spec 011
        if event == "ZONE_CHANGED_NEW_AREA" then FP.Fire("ZONE") end -- spec 006, R19
        FP.Fire("CHANGED") -- a UI faz debounce
    end
end)

if _G.geterrorhandler and _G.seterrorhandler then
    local previous = _G.geterrorhandler()
    _G.seterrorhandler(function(msg, ...)
        if type(msg) == "string" and msg:find("ForeverPlanner", 1, true) then pcall(FP.LogError, msg) end
        if previous then return previous(msg, ...) end
    end)
end

SLASH_FOREVERPLANNER1 = "/fp"
SLASH_FOREVERPLANNER2 = "/foreverplanner"
SlashCmdList.FOREVERPLANNER = function(msg)
    -- Spec 040: o registro (Commands.lua) despacha; sem comando, a janela.
    if (msg or ""):match("^%s*$") then ns.UI.Toggle() else ns.Commands.Run(msg) end
end
