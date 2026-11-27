-- Journal.lua: diário do que o jogador faz no jogo (spec 036, R1–R11). Adaptador: escuta os eventos
-- internos que o Core dispara e anota linhas curtas em ForeverPlannerJournal (SavedVariables da conta).
-- tools/journal.py importa o diário numa base SQLite. Nada é calculado em combate: só anota a linha.
-- Privacidade: sem nome de personagem, conta, reino ou outro jogador; o personagem é Util.CharKey.
local _, ns = ...
local L = ns.L -- spec 066
local Util = ns.Util
local Journal = {}
ns.Journal = Journal

Journal.VERSION = 1
local BASE = { "t", "s", "c", "lv", "m", "x", "y" }
local function schema(...)
    local s = {}
    for _, f in ipairs(BASE) do s[#s + 1] = f end
    for i = 1, select("#", ...) do s[#s + 1] = (select(i, ...)) end
    return s
end
-- Esquema por tipo: a ferramenta lê pelo nome do campo (R13). Mudou o esquema, sobe VERSION.
Journal.SCHEMA = {
    session_start = schema("addon", "build", "race", "class", "faction"),
    session_end = schema(),
    afk_start = schema(), afk_end = schema(),
    quest_offer = schema("src", "sid", "avail", "active"),
    quest_detail = schema("q", "title", "obj", "xp", "money", "rewards", "choices", "src", "sid"),
    quest_accept = schema("q"),
    quest_abandon = schema("q"),
    quest_turnin = schema("q", "xp", "money", "src", "sid"),
    quest_progress = schema("q", "i", "text", "n", "total"),
    mob_seen = schema("npc", "mlv", "class", "reaction"),
    kill = schema("npc", "mlv", "ttk", "xp"),
    loot = schema("src", "sid", "items"),
    taxi = schema("from", "to", "dur", "fwc", "fwx", "fwy", "wc", "wx", "wy"),
    cont = schema("dur", "wait", "fwc", "fwx", "fwy", "wc", "wx", "wy"),
    hearth = schema("dur", "fm", "fx", "fy"),
    zone = schema("from", "to", "name"),
    trail = schema("wc", "wx", "wy", "mounted", "spd"),
    level = schema(),
    played = schema("total"),
    death = schema("killer"),
    bind = schema("name"),
    follow = schema("kind", "key", "rate"),
}
-- Teto por tipo (R10), para um total de 60.000; escala com journalMax (padrão 40.000).
local CAPS = { trail = 24000, mob_seen = 6000, kill = 6000, loot = 4000, quest_progress = 4000 }
local OTHER_CAP = 1000

local TRAIL_SECONDS, AFK_SECONDS, MOB_EVERY, OFFER_EVERY = 10, 180, 60, 30
local NEAR_TRANSPORT, TRANSPORT_WINDOW, HEARTH_TIMEOUT = 40, 600, 60

local J, charKey -- ForeverPlannerJournal e a chave do personagem
local function clock() return _G.GetTime and _G.GetTime() or 0 end
local function epoch() return (_G.time or os.time)() end
local function round(v, n) if not v then return nil end local f = 10 ^ (n or 2) return math.floor(v * f + 0.5) / f end

local function init()
    _G.ForeverPlannerJournal = _G.ForeverPlannerJournal or {}
    J = _G.ForeverPlannerJournal
    -- Esquema mudou: as linhas antigas vão para o arquivo com o esquema delas (a ferramenta lê as duas).
    if J.v and J.v ~= Journal.VERSION and J.rows and next(J.rows) then
        J.archive = J.archive or {}
        J.archive[tostring(J.v)] = { v = J.v, schema = J.schema, rows = J.rows }
        J.rows = {}
    end
    J.v, J.schema = Journal.VERSION, Journal.SCHEMA
    if J.on == nil then J.on = true end
    J.rows = J.rows or {}
    J.seq = J.seq or 0
    -- R2: semente aleatória por personagem, não o GUID (hash de GUID seria pseudônimo reversível).
    local db = ns.FP.db
    if db and not db.journalSeed then
        db.journalSeed = string.format("%d-%.0f-%.6f", epoch(), clock() * 1000, math.random())
    end
    charKey = Util.CharKey(db and db.journalSeed or "?")
end

-- Privacidade: o jogo troca $N pelo nome do personagem no texto da quest; o diário desfaz a troca.
local function unname(text)
    if type(text) ~= "string" then return text end
    local name = _G.UnitName and _G.UnitName("player")
    if not name or name == "" then return text end
    return (text:gsub(name:gsub("%W", "%%%0"), "$N"))
end

-- Anota uma linha (R1). Os campos extras seguem o esquema do tipo, depois dos campos de base.
function Journal.Add(kind, ...)
    if not J then init() end
    if not (J.on and Journal.SCHEMA[kind]) then return end
    local p = ns.Planner.PlayerPoint() or {}
    J.seq = (J.seq or 0) + 1 -- nunca volta atrás: com t, é a chave da linha na base
    local row = { epoch(), J.seq, charKey, _G.UnitLevel("player"), p.mapID, round(p.x), round(p.y), ... }
    J.rows[kind] = J.rows[kind] or {}
    local max = math.floor((CAPS[kind] or OTHER_CAP) * (ns.FP.db and ns.FP.db.journalMax or 40000) / 60000)
    Util.RingPush(J.rows[kind], row, math.max(1, max))
    return row
end

-- Teste e "/fp diario limpar": recomeça o diário.
function Journal.Reset()
    local seq = J and J.seq or 0
    _G.ForeverPlannerJournal = { on = true, seq = seq } -- a sequência continua (chave da base)
    J = nil
    init()
end

ns.FP.On("DB_READY", init)

------------------------------------------------------------------------------------------
-- Sessão, nível, morte, lar, guia (R1, R2, R8, R9)
------------------------------------------------------------------------------------------
ns.FP.On("READY", function()
    init()
    local meta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local version = meta and meta("ForeverPlanner", "Version")
    local build = _G.GetBuildInfo and table.concat({ _G.GetBuildInfo() }, " ", 1, 2)
    local _, race = _G.UnitRace("player")
    local _, class = _G.UnitClass("player")
    Journal.Add("session_start", version, build, race, class, (_G.UnitFactionGroup("player")))
    if _G.C_Timer and _G.C_Timer.NewTicker then _G.C_Timer.NewTicker(1, function() Journal.Tick() end) end
end)
ns.FP.On("LOGOUT", function() Journal.Add("session_end") end)
ns.FP.On("LEVEL_UP", function() Journal.Add("level") end)
ns.FP.On("TIME_PLAYED", function(total) Journal.Add("played", tonumber(total)) end)
ns.FP.On("BIND", function(name) Journal.Add("bind", name) end)
ns.FP.On("FOLLOW", function(kind, key, rate)
    if key ~= nil then Journal.Add("follow", kind, tostring(key), rate and math.floor(rate + 0.5)) end
end)

local lastArea
ns.FP.On("ZONE", function()
    local area = ns.Guide and ns.Guide.PlayerArea()
    Journal.Add("zone", lastArea, area, _G.GetZoneText and _G.GetZoneText() or nil)
    lastArea = area
end)

------------------------------------------------------------------------------------------
-- Quest (R3)
------------------------------------------------------------------------------------------
local function npcSource()
    local kind, id = Util.EntityFromGUID(_G.UnitGUID and _G.UnitGUID("npc"))
    return kind, id
end

local turnedIn = {}
ns.FP.On("QUEST_ACCEPTED", function(q) Journal.Add("quest_accept", tonumber(q)) end)
ns.FP.On("QUEST_TURNED_IN", function(q, xp, money)
    q = tonumber(q)
    if q then turnedIn[q] = true end
    local src, sid = npcSource()
    Journal.Add("quest_turnin", q, tonumber(xp), tonumber(money), src, sid)
end)
-- Abandono: saiu do log sem entrega (o jogo manda QUEST_REMOVED nos dois casos).
ns.FP.On("QUEST_REMOVED", function(q)
    q = tonumber(q)
    if not q then return end
    C_Timer.After(1, function()
        if not turnedIn[q] then Journal.Add("quest_abandon", q) end
        turnedIn[q] = nil
    end)
end)

local function itemIDs(kind, n)
    local out = {}
    for i = 1, n or 0 do
        local link = _G.GetQuestItemLink and _G.GetQuestItemLink(kind, i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then out[#out + 1] = id end
    end
    return out
end

local lastOffer = {}
ns.FP.On("QUEST_DIALOG", function(event)
    local src, sid = npcSource()
    if event == "QUEST_DETAIL" then
        local q = tonumber(_G.GetQuestID and _G.GetQuestID())
        if not q or q == 0 then return end
        Journal.Add("quest_detail", q, unname(_G.GetTitleText and _G.GetTitleText()),
            unname(_G.GetObjectiveText and _G.GetObjectiveText()),
            tonumber(_G.GetRewardXP and _G.GetRewardXP()), tonumber(_G.GetRewardMoney and _G.GetRewardMoney()),
            itemIDs("reward", _G.GetNumQuestRewards and _G.GetNumQuestRewards()),
            itemIDs("choice", _G.GetNumQuestChoices and _G.GetNumQuestChoices()), src, sid)
    elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        if not sid then return end
        local now = clock()
        if lastOffer[sid] and now - lastOffer[sid] < OFFER_EVERY then return end
        lastOffer[sid] = now
        local avail, active = {}, {}
        local G = _G.C_GossipInfo
        for _, info in ipairs(G and G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
            if info.questID then avail[#avail + 1] = info.questID end
        end
        for _, info in ipairs(G and G.GetActiveQuests and G.GetActiveQuests() or {}) do
            if info.questID then active[#active + 1] = info.questID end
        end
        for i = 1, (_G.GetNumAvailableQuests and _G.GetNumAvailableQuests() or 0) do
            local id = _G.GetAvailableQuestInfo and select(5, _G.GetAvailableQuestInfo(i))
            if id then avail[#avail + 1] = id end
        end
        Journal.Add("quest_offer", src, sid, avail, active)
    end
end)

-- Progresso de objetivo: só o que mudou desde a última leitura do log (a posição é a do momento).
local objectives = nil
ns.FP.On("QUEST_LOG", function()
    if not (ns.Data and ns.Data.LogQuests) then return end
    local first = objectives == nil
    objectives = objectives or {}
    for _, q in ipairs(ns.Data.LogQuests()) do
        for i, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}) do
            local key = q .. ":" .. i
            local n = tonumber(o.numFulfilled) or 0
            if not first and objectives[key] ~= nil and n > objectives[key] then
                Journal.Add("quest_progress", q, i, unname(o.text), n, tonumber(o.numRequired))
            end
            objectives[key] = n
        end
    end
end)

------------------------------------------------------------------------------------------
-- Mob, morte de mob e saque (R4, R5)
------------------------------------------------------------------------------------------
local seenAt, levelByName, levelById = {}, {}, {}
-- R20: nível visto do mob pelo nome, só na sessão (não vai para o diário com o nome).
function Journal.SeenLevelByName(name) return name and levelByName[name] end

ns.FP.On("UNIT_LOOK", function(unit)
    if not (_G.UnitExists(unit) and not _G.UnitIsPlayer(unit)) then return end
    local kind, id = Util.EntityFromGUID(_G.UnitGUID(unit))
    if kind ~= "npc" then return end
    local reaction = _G.UnitReaction and _G.UnitReaction(unit, "player")
    if not reaction or reaction > 4 then return end -- só hostil e neutro
    local level = _G.UnitLevel(unit)
    local name = _G.UnitName and _G.UnitName(unit)
    if level and level > 0 then
        levelById[id] = level
        if name then levelByName[name] = level end
    end
    local now = clock()
    Journal.Looked(name, id, now) -- alvo ou mouseover
    if seenAt[id] and now - seenAt[id] < MOB_EVERY then return end
    seenAt[id] = now
    Journal.Add("mob_seen", id, level, _G.UnitClassification and _G.UnitClassification(unit), reaction)
end)

-- Morte de mob (R4): pela mensagem de XP, com o mob mirado com aquele nome. Sem log de combate (R4).
local lookByName = {} -- nome > { id, at } do último mob mirado com esse nome (só na memória)
local tick -- estado do tique (abaixo)
function Journal.Looked(name, id, now)
    if not (name and id) then return end
    local look = lookByName[name]
    -- mirar de novo o mesmo mob não reinicia o tempo; outro mob com o mesmo nome também não
    if look and look.id == id and now - look.at < 120 then return end
    lookByName[name] = { id = id, at = now }
end
-- Sem mob mirado com esse nome: o ID da QuestieDB, se ela tiver um só mob com esse nome (parecer).
local function idByName(name)
    local N = ns.Data and ns.Data.N
    local ids = N and N.IdsByName and N.IdsByName(name)
    return ids and #ids == 1 and ids[1] or nil
end
ns.FP.On("KILL_XP", function(xp, name)
    local now = clock()
    local look = name and lookByName[name]
    local id = (look and look.id) or (name and idByName(name))
    local ttk = look and round(now - look.at, 1)
    if tick then tick.activeAt = now end
    ns.FP.Fire("KILL_TIME", ttk, id and levelById[id]) -- spec 067, R6: calibra mesmo com o diário desligado
    Journal.Add("kill", id, id and levelById[id], ttk, tonumber(xp))
    -- Vários mobs com o mesmo nome (AoE, pet): o próximo conta desde esta morte, com o mesmo ID.
    if look then look.at = now end
end)
local lastDeath -- spec 064, R5: o PLAYER_DEAD vem duas vezes no Forever; uma morte por 30 s
ns.FP.On("DIED", function()
    local now = _G.GetTime()
    if not Util.Throttle(lastDeath, now, 30) then return end
    lastDeath = now
    local id
    if _G.UnitExists("target") and not _G.UnitIsPlayer("target") and (_G.UnitReaction("target", "player") or 5) <= 4 then
        _, id = Util.EntityFromGUID(_G.UnitGUID("target"))
    end
    Journal.Add("death", id) -- o mob hostil mirado, se havia um
end)

ns.FP.On("LOOT", function()
    local n = _G.GetNumLootItems and _G.GetNumLootItems() or 0
    local items, src, sid = {}, nil, nil
    for i = 1, n do
        local link = _G.GetLootSlotLink and _G.GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local qty = _G.GetLootSlotInfo and select(3, _G.GetLootSlotInfo(i))
            items[#items + 1] = { id, tonumber(qty) or 1 }
        end
        if not sid and _G.GetLootSourceInfo then src, sid = Util.EntityFromGUID((_G.GetLootSourceInfo(i))) end
    end
    if #items > 0 then Journal.Add("loot", src, sid, items) end
end)

------------------------------------------------------------------------------------------
-- Viagem, rastro e AFK: um tique por segundo (R1, R6, R7)
------------------------------------------------------------------------------------------
local taxiDest, taxiFrom
if _G.hooksecurefunc and _G.TakeTaxiNode then
    _G.hooksecurefunc("TakeTaxiNode", function(slot)
        taxiDest = _G.TaxiNodeName and _G.TaxiNodeName(slot)
        taxiFrom = nil
        for i = 1, (_G.NumTaxiNodes and _G.NumTaxiNodes() or 0) do
            if _G.TaxiNodeGetType and _G.TaxiNodeGetType(i) == "CURRENT" then taxiFrom = _G.TaxiNodeName(i) end
        end
    end)
end

local hearthStart
ns.FP.On("SPELL_START", function(spellID)
    if tick then tick.activeAt = clock() end
    if spellID == ns.LevelGuide.HEARTH_SPELL then hearthStart = { at = clock(), p = ns.Planner.PlayerPoint() } end
end)

local transportWorld
local function transportsNear(w)
    if not transportWorld then
        transportWorld = {}
        for _, t in ipairs(ns.Data.TransportPoints and ns.Data.TransportPoints((_G.UnitFactionGroup("player"))) or {}) do
            local c, x, y = ns.Planner.WorldPos(t.mapID, t.x, t.y)
            if c then transportWorld[#transportWorld + 1] = { cont = c, x = x, y = y } end
        end
    end
    for _, t in ipairs(transportWorld) do
        if t.cont == w.cont then
            local dx, dy = t.x - w.x, t.y - w.y
            if dx * dx + dy * dy <= NEAR_TRANSPORT * NEAR_TRANSPORT then return true end
        end
    end
    return false
end

tick = { prev = nil, trailAt = nil, taxi = nil, nearFirst = nil, nearLast = nil, activeAt = nil, afk = false,
    dist = 0, moving = 0 }
ns.FP.On("SPELL_DONE", function() tick.activeAt = clock() end)

local function worldOf(p)
    if not (p and p.mapID and p.x) then return nil end
    local c, x, y = ns.Planner.WorldPos(p.mapID, p.x, p.y)
    return c and { cont = c, x = x, y = y } or nil
end

-- R7: também chamado pelos testes. Barato: posição, duas comparações e no máximo uma linha.
function Journal.Tick()
    if not (J and J.on) then return end
    local now = clock()
    local p = ns.Planner.PlayerPoint()
    local w = worldOf(p)
    local prev = tick.prev
    local step = (prev and w and prev.cont == w.cont) and math.sqrt((prev.x - w.x) ^ 2 + (prev.y - w.y) ^ 2) or nil
    local moved = prev and w and (prev.cont ~= w.cont or (step or 0) > 1)
    tick.activeAt = tick.activeAt or now
    if moved then tick.activeAt = now end

    -- AFK (R1): andar, lançar feitiço ou bater encerram
    if tick.afk and now - tick.activeAt < 2 then tick.afk = false; Journal.Add("afk_end")
    elseif not tick.afk and now - tick.activeAt >= AFK_SECONDS then tick.afk = true; Journal.Add("afk_start") end

    -- Voo (R6)
    local onTaxi = _G.UnitOnTaxi and _G.UnitOnTaxi("player")
    if onTaxi and not tick.taxi then
        tick.taxi = { at = now, from = taxiFrom, to = taxiDest, w = prev or w }
    elseif not onTaxi and tick.taxi then
        local t, fw = tick.taxi, tick.taxi.w or {}
        Journal.Add("taxi", t.from, t.to, round(now - t.at, 1), fw.cont, round(fw.x, 1), round(fw.y, 1),
            w and w.cont, w and round(w.x, 1), w and round(w.y, 1))
        tick.taxi = nil
    end

    if w then
        -- Transporte (R6): perto do embarque é espera; do último momento perto até trocar de continente,
        -- travessia. Sem passagem recente pelo embarque (portal, pedra), sem tempo.
        if not onTaxi and transportsNear(w) then
            if not (tick.nearLast and now - tick.nearLast <= 5) then tick.nearFirst = now end
            tick.nearLast = now
        end
        if prev and prev.cont ~= w.cont and not onTaxi and not hearthStart then
            local recent = tick.nearLast and now - tick.nearLast <= TRANSPORT_WINDOW
            Journal.Add("cont", recent and round(now - tick.nearLast, 1) or nil,
                recent and round(tick.nearLast - tick.nearFirst, 1) or nil, prev.cont, round(prev.x, 1), round(prev.y, 1),
                w.cont, round(w.x, 1), round(w.y, 1))
            tick.nearFirst, tick.nearLast = nil, nil
        end
        -- Pedra de lar (R6): chegou quando a posição salta.
        if hearthStart then
            local jump = prev and (prev.cont ~= w.cont or math.abs(prev.x - w.x) + math.abs(prev.y - w.y) > 200)
            if jump then
                local hp = hearthStart.p or {}
                Journal.Add("hearth", round(now - hearthStart.at, 1), hp.mapID, round(hp.x), round(hp.y))
                hearthStart = nil
            elseif now - hearthStart.at > HEARTH_TIMEOUT then
                hearthStart = nil
            end
        end
        -- Rastro (R7): só andando, um a cada TRAIL_SECONDS, com a velocidade nos segundos em movimento.
        if moved and not onTaxi and step then tick.dist, tick.moving = tick.dist + step, tick.moving + 1 end
        if moved and not onTaxi and (not tick.trailAt or now - tick.trailAt >= TRAIL_SECONDS) then
            tick.trailAt = now
            local spd = tick.moving > 0 and round(tick.dist / tick.moving, 1) or nil
            tick.dist, tick.moving = 0, 0
            Journal.Add("trail", w.cont, round(w.x, 1), round(w.y, 1), (_G.IsMounted and _G.IsMounted()) and true or false, spd)
        end
    end
    tick.prev = w
end

------------------------------------------------------------------------------------------
-- Comando (R11)
------------------------------------------------------------------------------------------
-- Spec 040: estado para o botão da aba Ferramentas.
function Journal.IsOn()
    if not J then init() end
    return J.on == true
end

function Journal.Command(arg)
    if not J then init() end
    arg = (arg or ""):lower()
    if arg == "off" or arg == "on" then
        J.on = arg == "on"
        ns.FP.Print(L["diário "] .. (J.on and L["ligado"] or L["desligado"]) .. ".")
        return
    end
    if arg == "limpar" then
        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            _G.StaticPopupDialogs.FOREVERPLANNER_JOURNAL_CLEAR = _G.StaticPopupDialogs.FOREVERPLANNER_JOURNAL_CLEAR or {
                text = L["Apagar o diário do Forever Planner? Importe antes com tools/journal.py."],
                button1 = _G.YES or L["Sim"], button2 = _G.NO or L["Não"], timeout = 0, whileDead = true, hideOnEscape = true,
                OnAccept = function() Journal.Reset(); ns.FP.Print(L["diário apagado."]) end,
            }
            _G.StaticPopup_Show("FOREVERPLANNER_JOURNAL_CLEAR")
        end
        return
    end
    local total, oldest, parts = 0, nil, {}
    for kind, list in pairs(J.rows) do
        total = total + #list
        if list[1] and (not oldest or list[1][1] < oldest) then oldest = list[1][1] end
        parts[#parts + 1] = kind .. " " .. #list
    end
    table.sort(parts)
    ns.FP.Print(string.format(L["diário %s: %d linhas%s"], J.on and "ligado" or "desligado", total,
        oldest and (L[", a mais velha de "] .. (_G.date or os.date)("%d/%m/%Y %H:%M", oldest)) or ""))
    if #parts > 0 then ns.FP.Print(table.concat(parts, " · ")) end
end

return Journal
