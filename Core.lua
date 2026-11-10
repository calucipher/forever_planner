-- Core.lua: SavedVariables, eventos, cache de recompensas reais e slash commands.
local ADDON, ns = ...
local Util = ns.Util

local FP = {}
ns.FP = FP
_G.ForeverPlanner = FP

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
    calib = { xp = {}, kill = {} }, -- amostras reais das últimas mortes (R7)
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
    gps = { arrow = true, native = true, tomtom = true, arriveYards = 12, x = 0, y = -160 },
    ui = { point = "CENTER", x = 0, y = 0, tab = "quests" },
    cache = { xp = {}, money = {} }, -- recompensas reais vistas no diálogo de quest
    following = nil,            -- questID seguido pelo GPS
    unavailable = {},           -- quests que o jogo não ofereceu no NPC (spec 014)
    unavailableSeen = {},       -- visitas em que o NPC não ofereceu a quest (marca na 2ª, spec 014)
    weaponsOff = {},            -- armas que o jogador desabilitou na janela Armas (spec 016)
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
    if not db then return end
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
    local now = _G.GetTime and _G.GetTime() or 0
    if lastKill then FP.RecordKillGap(now - lastKill) end
    lastKill = now
    local ids = ns.Data.N.IdsByName and ns.Data.N.IdsByName(name)
    local id = ids and ids[1]
    local lvl = id and ns.Data.N.minLevel(id)
    if not lvl or lvl <= 0 then return end
    local expected = ns.Leveling.MobXP(UnitLevel("player"), lvl, 1)
    if expected > 0 then ns.Leveling.PushSample(FP.db.calib.xp, (xp - rested) / expected, 20) end
end

-- Ações adiadas para depois do combate (nada pesado em combate)
local pending = {}
function FP.AfterCombat(key, fn)
    if Util.InCombat() then pending[key] = fn else fn() end
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
    "QUEST_REMOVED",
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

local itemRefreshQueued = false
local QUIET = { GET_ITEM_INFO_RECEIVED = true }
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if FP.db and FP.db.debug and not QUIET[event] then
        FP.Debug(string.format("evento %s %s", event, tostring(arg1 or "")))
    end
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverPlannerDB = Util.CopyDefaults(FP.defaults, ForeverPlannerDB)
        FP.db = ForeverPlannerDB
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        for k, fn in pairs(pending) do pending[k] = nil; pcall(fn) end
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        CacheQuestRewards()
        FP.Fire("QUEST_DIALOG", event)
    elseif event == "QUEST_PROGRESS" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        FP.Fire("QUEST_DIALOG", event)
    elseif event == "QUEST_TURNED_IN" then
        if ns.Data.MarkTurnedIn then ns.Data.MarkTurnedIn(arg1) end -- spec 006, R12
        FP.Fire("QUEST_TURNED_IN", arg1)
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
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "next" then
        ns.Planner.FollowBest()
    elseif cmd == "zonas" then
        ns.Guide.PrintZones() -- spec 029, R21
    elseif cmd == "guia" then
        ns.Guide.FollowBest()
    elseif cmd == "agressividade" and tonumber(rest) then
        FP.db.threshold = math.max(0, math.min(100, tonumber(rest))) / 100
        ns.Guide.Invalidate(); FP.Fire("CHANGED")
        FP.Print("agressividade:", math.floor(FP.db.threshold * 100) .. "%")
    elseif cmd == "debug" then
        if rest == "chat" then
            FP.db.debugChat = not FP.db.debugChat
            FP.Print("debug no chat:", FP.db.debugChat and "ligado" or "desligado")
        else
            FP.db.debug = not FP.db.debug
            FP.Print("modo debug:", FP.db.debug and "ligado (registro gravado no /reload ou logout)" or "desligado")
        end
    elseif cmd == "diag" then
        ns.DebugTools.Diag()
    elseif cmd == "bolsa" then
        ns.Guide.FollowBag()
    elseif cmd == "bolsas" then
        local list = ns.Data.Q and ns.Data.ready and ns.Data.BagQuests(UnitLevel("player")) or {}
        if #list == 0 then FP.Print("nenhuma quest de bolsa para este personagem (ou dados ainda carregando).") end
        for _, b in ipairs(list) do
            FP.Print(string.format("[%d] %s — %s (%s) — %s", b.level, b.name, b.itemName or "bolsa", b.zone, b.status))
        end
    elseif cmd == "classe" then
        ns.ClassGuide.PrintList()
        ns.ClassGuide.Follow()
    elseif cmd == "armas" then
        ns.QuickMenu.ShowWeapons()
    elseif cmd == "indisponiveis" then
        if rest == "limpar" then
            ns.Planner.ClearUnavailable("/fp indisponiveis limpar")
            FP.Print("marcas de quest indisponível apagadas.")
        else
            local n = 0
            for q in pairs(FP.db.unavailable or {}) do
                n = n + 1
                FP.Print(string.format("[%d] %s", q, ns.Data.Q and ns.Data.Q.name(q) or "?"))
            end
            if n == 0 then FP.Print("nenhuma quest marcada como indisponível.") end
        end
    elseif cmd == "marcos" then
        ns.ClassGuide.PrintMilestones()
        ns.ClassGuide.WarnWeapons()
    elseif cmd == "entregar" then
        ns.Guide.FollowBest("turnin")
    elseif cmd == "limpar" then
        ns.QuickMenu.ShowCleanup()
    elseif cmd == "grupo" then
        if rest == "avisos" then ns.Group.ToggleAnnounce() else ns.Group.ShareAll() end -- spec 022
    elseif cmd == "auto" then
        ns.Auto.Toggle()
    elseif cmd == "minimapa" or cmd == "minimap" then
        ns.MinimapButton.Toggle()
    elseif cmd == "macros" then
        for key, sp in pairs(ns.Macros.spells) do
            local name = ns.Macros.Resolve(key)
            FP.Print(string.format("%s (ID %d): %s", key, sp.id,
                name and ("|cFF73E65A" .. name .. "|r") or "|cFF888888não conhecido|r"))
        end
    elseif cmd == "calib" then
        FP.Print(string.format("tempo por morte: %.1f s (%d amostras) · fator de XP: %.2f (%d amostras)",
            FP.KillSeconds(), #FP.db.calib.kill, FP.MobXPFactor(), #FP.db.calib.xp))
    elseif cmd == "clear" or cmd == "stop" then
        ns.Gps.Clear(); FP.db.following = nil; FP.db.guide = nil; FP.Fire("CHANGED")
    elseif cmd == "preset" and rest ~= "" then
        if ns.Weights.presets[rest] then
            FP.db.preset = rest; ns.Scoring.ClearCache(); FP.Fire("CHANGED")
            FP.Print("perfil de pesos:", rest)
        else
            FP.Print("perfis:", table.concat(ns.Weights.PresetNames(), ", "))
        end
    elseif cmd == "stats" then
        ns.Scoring.Debug(rest)
    elseif cmd == "ttk" and tonumber(rest) then
        FP.db.ttk = tonumber(rest); FP.Fire("CHANGED"); FP.Print("TTK:", FP.db.ttk, "s")
    else
        FP.Print("comandos: /fp, /fp guia, /fp next, /fp clear, /fp preset <nome>, /fp stats <link>, /fp ttk <seg>, /fp agressividade <0-100>, /fp calib, /fp macros, /fp minimapa, /fp auto, /fp grupo [avisos], /fp entregar, /fp limpar, /fp debug [chat], /fp diag, /fp bolsa, /fp bolsas, /fp classe, /fp marcos, /fp armas, /fp indisponiveis [limpar]")
    end
end
