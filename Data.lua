-- Data.lua: camada sobre a QuestieDB (GPL-3.0). Quests, spawns, zonas, XP e recompensas.
local _, ns = ...
local Util = ns.Util
local Data = {}
ns.Data = Data

Data.ready = false        -- índice de recompensas pronto
Data.rewardsByQuest = {}  -- questID -> { itemID, ... } (invertido de Item.questRewards)
Data.medianXPByLevel = {} -- questLevel -> XP mediana (para quests sem XP conhecida)

local function loadZoneTable(str)
    if type(str) ~= "string" then return {} end
    local fn = loadstring(str)
    local ok, t = pcall(fn or function() return {} end)
    return (ok and type(t) == "table") and t or {}
end

-- Spec 023, R2: acesso às quests da QuestieDB com as correções curadas por cima.
function Data.WithFixes(quest, fixes)
    if not (quest and fixes and next(fixes)) then return quest end
    local fixed = setmetatable({}, { __index = quest })
    for _, fix in pairs(fixes) do
        for field in pairs(fix) do
            if not rawget(fixed, field) and quest[field] then
                local original = quest[field]
                fixed[field] = function(q) return Util.FixedQuestField(fixes, field, q, original) end
            end
        end
    end
    return fixed
end

-- Spec 023, R5: startedBy sem o NPC que só recebe o livro (resultado guardado por quest).
function Data.WithBookStarters(quest, item)
    if not (quest and quest.startedBy and quest.finishedBy and quest.objectives and item and item.objectDrops) then
        return quest
    end
    local wrapped, cache = setmetatable({}, { __index = quest }), {}
    local function dropsOf(id) return item.objectDrops(id) end
    function wrapped.startedBy(q)
        if cache[q] == nil then
            local s = quest.startedBy(q)
            if s and s[1] and s[1][1] and s[2] and s[2][1] then
                local items = {}
                for _, it in ipairs((quest.objectives(q) or {})[3] or {}) do items[#items + 1] = it[1] end
                local finisher = quest.finishedBy(q)
                s = Util.BookStarters(s, finisher and finisher[1], items, dropsOf)
            end
            cache[q] = s or false
        end
        return cache[q] or nil
    end
    return wrapped
end

-- Spec 023, R6: o NPC está entre quem dá a quest (startedBy corrigido)?
function Data.StartsQuest(kind, id, q)
    local s = Data.Q.startedBy(q) or {}
    for _, x in ipairs(s[kind == "npc" and 1 or 2] or {}) do if x == id then return true end end
    return false
end

function Data.Init()
    local L = _G.LibQuestieDB
    if not L then return false, "QuestieDB não está instalado/ativo. Instale a versão Forever." end
    if L.RequireContract then
        local ok, msg = L.RequireContract(4)
        if not ok then return false, msg end
    end
    Data.L, Data.N, Data.I, Data.O = L, L.Npc, L.Item, L.Object
    Data.Q = Data.WithBookStarters(Data.WithFixes(L.Quest, ns.QuestFixes), L.Item)

    local zdb = L.Support.Get("ZoneDB") or {}
    local priv = zdb.private or {}
    Data.areaToMap = loadZoneTable(priv.areaIdToUiMapId)
    for k, v in pairs(loadZoneTable(priv.areaIdToUiMapIdOverride)) do Data.areaToMap[k] = v end
    Data.mapToArea = loadZoneTable(priv.uiMapIdToAreaId)

    Data.dungeons = priv.dungeons or {}
    Data.subToParent = loadZoneTable(priv.subZoneToParentZone) -- spec 029, R6
    for k, v in pairs(loadZoneTable(priv.subZoneToParentZoneOverride)) do Data.subToParent[k] = v end
    Data.factionTemplate = (L.Support.Get("QuestieDB") or {}).factionTemplate or {} -- spec 029, R7

    local xp = L.Support.Get("QuestXP")
    Data.baseXP = (xp and xp.db) or {}

    local _, _, raceID = UnitRace("player")
    local _, classToken = UnitClass("player")
    Data.raceMask = L.Enum.raceMaskById and L.Enum.raceMaskById[raceID]
    Data.classMask = L.Enum.classKeys and L.Enum.classKeys[classToken]
    Data.BuildMedianXP()
    Data.StartRewardIndex()
    return true
end

-- XP mediana por nível de quest, calculada da própria tabela da QuestieDB
function Data.BuildMedianXP()
    local buckets = {}
    for _, entry in pairs(Data.baseXP) do
        local lvl, xp = entry[1], entry[2]
        if lvl and xp and xp > 0 then
            buckets[lvl] = buckets[lvl] or {}
            table.insert(buckets[lvl], xp)
        end
    end
    for lvl, list in pairs(buckets) do Data.medianXPByLevel[lvl] = Util.Median(list) end
end

-- Fim do índice: avisa quem esperava os dados (o guia retoma a seta, spec 006 R4).
function Data.MarkReady()
    Data.ready = true
    ns.FP.Debug("dados prontos (índice de recompensas)")
    ns.FP.Fire("DATA_READY")
    ns.FP.Fire("CHANGED")
    Data.BuildZoneCatalog() -- spec 029, R6
end

-- Índice questID -> itens, em coroutine para não travar o login
function Data.StartRewardIndex()
    local ids = Data.I.GetAllIds()
    local co = coroutine.create(function()
        for i, itemID in ipairs(ids) do
            local quests = Data.I.questRewards(itemID)
            if quests then
                for _, q in ipairs(quests) do
                    local list = Data.rewardsByQuest[q]
                    if not list then list = {}; Data.rewardsByQuest[q] = list end
                    list[#list + 1] = itemID
                end
            end
            if i % 400 == 0 then coroutine.yield() end
        end
    end)
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local ok, err = coroutine.resume(co)
        if not ok then ns.FP.Print("erro no índice:", err); self:SetScript("OnUpdate", nil); return end
        if coroutine.status(co) == "dead" then
            self:SetScript("OnUpdate", nil)
            Data.MarkReady()
        end
    end)
end

------------------------------------------------------------------------------------------
-- Estado do jogador
------------------------------------------------------------------------------------------
-- Entregas vistas no evento: o jogo marca a quest como concluída (e tira do log) com atraso.
Data.turnedIn = {}
function Data.MarkTurnedIn(q) if Util.Num(q) then Data.turnedIn[q] = true end end

local function completed(q) return Data.turnedIn[q] == true or C_QuestLog.IsQuestFlaggedCompleted(q) == true end
function Data.IsCompleted(q) return completed(q) end

-- Spec 014: o jogo não ofereceu a quest no NPC que, pela QuestieDB, a dá.
function Data.IsUnavailable(q)
    local u = ns.FP and ns.FP.db and ns.FP.db.unavailable
    return u ~= nil and u[q] == true
end

function Data.IsOnQuest(q)
    if Data.turnedIn[q] then return false end -- spec 006, R12
    if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(q) == true end
    return C_QuestLog.GetLogIndexForQuestID(q) ~= nil
end

function Data.IsReadyForTurnIn(q)
    if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(q) == true end
    return C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) == true
end

-- Pode pegar (ou já está com) a quest? Regras principais da QuestieDB.
-- Não replica as blacklists/políticas internas do Questie.
-- assume: { [questID] = true } tratadas como já feitas (quest seguinte de uma cadeia, R13).
function Data.IsEligible(q, level, assume)
    if completed(q) then return false end
    if Data.IsOnQuest(q) then return true end
    if Data.IsUnavailable(q) then return false end -- spec 014
    local function done(p) return (assume and assume[p]) or completed(p) end
    local Q = Data.Q
    local req = Q.requiredLevel(q) or 0
    if req > level then return false end
    local maxLvl = Q.requiredMaxLevel(q) or 0
    if maxLvl > 0 and level > maxLvl then return false end
    if not Util.HasBit(Q.requiredRaces(q), Data.raceMask) then return false end
    if not Util.HasBit(Q.requiredClasses(q), Data.classMask) then return false end
    if Q.requiredSkill(q) then return false end -- profissão: fora do escopo do piloto
    local single = Q.preQuestSingle(q)
    if single then
        local any = false
        for _, p in ipairs(single) do if done(p) then any = true; break end end
        if not any then return false end
    end
    for _, p in ipairs(Q.preQuestGroup(q) or {}) do
        if not done(p) then return false end
    end
    for _, p in ipairs(Q.exclusiveTo(q) or {}) do
        if done(p) or Data.IsOnQuest(p) then return false end
    end
    return true
end

-- Categorias fora do leveling normal (eventos sazonais, PvP, invasões, outras classes)
local EXCLUDED_SORTS = {
    "AHN_QIRAJ_WAR", "BATTLEGROUNDS", "BREWFEST", "CHILDRENS_WEEK", "DARKMOON_FAIRE",
    "DAY_OF_THE_DEAD", "HALLOWS_END", "HARVEST_FESTIVAL", "LOVE_IS_IN_THE_AIR", "LUNAR_FESTIVAL",
    "MIDSUMMER", "NOBLEGARDEN", "PILGRIMS_BOUNTY", "SEASONAL", "WINTER_VEIL", "INVASION",
    "NIGHTMARE_INCURSIONS", "BLACKROCK_ERUPTION", "FIRELANDS_INVASION", "SPECIALTEMP",
    "TITAN_REFORGED_REALM", "TOURNAMENT", "BRAWLERS_GUILD", "PET_BATTLE", "PROVING_GROUNDS",
    "SCENARIO", "LEGENDARY",
}
local CLASS_SORTS = { "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local MAX_LEVELS_ABOVE = ns.Leveling.MAX_LEVELS_ABOVE -- quest "vermelha" demais (spec 025, R4)

local excludedSort
local function buildExcludedSorts()
    excludedSort = {}
    local keys = (Data.L and Data.L.Enum and Data.L.Enum.sortKeys) or {}
    for _, name in ipairs(EXCLUDED_SORTS) do
        if keys[name] then excludedSort[keys[name]] = true end
    end
    local _, myClass = UnitClass("player")
    for _, name in ipairs(CLASS_SORTS) do
        if keys[name] and name ~= myClass then excludedSort[keys[name]] = true end
    end
end

-- Categoria fora do leveling normal (evento sazonal, PvP, outra classe...).
function Data.IsExcludedSort(q)
    if not excludedSort then buildExcludedSorts() end
    local zone = Data.Q.zoneOrSort(q) or 0
    return zone < 0 and excludedSort[zone] == true
end

-- Vale entrar no planejador? (política do addon, separada das regras da quest)
function Data.IsRelevant(q, level)
    if Data.IsOnQuest(q) then return true end
    local fix = ns.QuestFixes and ns.QuestFixes[q]
    if fix and fix.outOfPlan then return false end -- spec 023, R7
    if not excludedSort then buildExcludedSorts() end
    local zone = Data.Q.zoneOrSort(q) or 0
    if zone < 0 and excludedSort[zone] then return false end
    local qLevel = Data.Q.questLevel(q) or 0
    if qLevel > level + MAX_LEVELS_ABOVE then return false end
    if qLevel > 0 and level - qLevel >= 10 then return false end -- cinza: 10% de XP
    return true
end

------------------------------------------------------------------------------------------
-- XP e ouro
------------------------------------------------------------------------------------------
-- Retorna xp (já com falloff para o nível atual) e a origem: "real", "db" ou "estimativa"
function Data.QuestXP(q, level)
    local qLevel = Data.Q.questLevel(q) or 0
    if qLevel <= 0 then qLevel = level end
    local seen = ns.FP.db.cache.xp[q]
    if seen and seen.xp then
        local base = seen.xp / Util.XPFalloff(seen.level or level, qLevel)
        return base * Util.XPFalloff(level, qLevel), "real"
    end
    local entry = Data.baseXP[q]
    if entry and entry[2] and entry[2] > 0 then
        return entry[2] * Util.XPFalloff(level, qLevel), "db"
    end
    local med = Data.medianXPByLevel[qLevel]
    if med then return med * Util.XPFalloff(level, qLevel), "estimativa" end
    return 0, "estimativa"
end

function Data.QuestMoney(q) return ns.FP.db.cache.money[q] or 0 end

function Data.Rewards(q) return Data.rewardsByQuest[q] end

------------------------------------------------------------------------------------------
-- Espaço: spawns e mapas
------------------------------------------------------------------------------------------
-- spawns da QuestieDB: { [areaId] = { {x, y}, ... } } em 0-100 (já convertidos pro Forever)
-- Retorna lista de pontos { mapID=, x=, y=, source= } (0-100). source = NPC (número) ou "o<id>" (objeto).
function Data.SpawnPoints(spawns, source)
    local out = {}
    for areaId, list in pairs(spawns or {}) do
        local mapID = Data.areaToMap[areaId]
        if mapID then
            for _, p in ipairs(list) do
                if p[1] and p[1] >= 0 and p[2] and p[2] >= 0 then
                    out[#out + 1] = { mapID = mapID, x = p[1], y = p[2], source = source }
                end
            end
        end
    end
    return out
end

-- Mesma tabela de pontos por entidade durante a sessão: o cache de posição de mundo do
-- Planner usa a tabela como chave (R24).
local pointsCache = {}
local function entityPoints(kind, id)
    local key = kind .. ":" .. tostring(id)
    local pts = pointsCache[key]
    if pts then return pts end
    if kind == "npc" then pts = Data.SpawnPoints(Data.N.spawns(id), id)
    elseif kind == "object" then pts = Data.SpawnPoints(Data.O.spawns(id), "o" .. id)
    else pts = {} end
    pointsCache[key] = pts
    return pts
end

local function inDungeon(spawns)
    for areaId in pairs(spawns or {}) do
        if Data.dungeons and Data.dungeons[areaId] then return true end
    end
    return false
end

-- Spec 013: nome do NPC/objeto de um ponto (source numérico = NPC, "o<id>" = objeto).
function Data.PointName(p)
    local src = p and p.source
    if not src or not Data.N then return nil end
    if type(src) == "number" then return Data.N.name(src) end
    local oid = tonumber(tostring(src):match("^o(%d+)$"))
    return oid and Data.O.name(oid) or nil
end

-- Spec 015: pontos de um NPC achado pelo nome exato (índice montado na primeira chamada).
local npcByName
function Data.NpcPointsByName(name)
    if not Data.N or not Data.N.GetAllIds then return {} end
    if not npcByName then
        npcByName = {}
        for _, id in ipairs(Data.N.GetAllIds() or {}) do
            local n = Data.N.name(id)
            if n then npcByName[n] = npcByName[n] or {}; table.insert(npcByName[n], id) end
        end
    end
    local out = {}
    for _, id in ipairs(npcByName[name] or {}) do
        for _, p in ipairs(entityPoints("npc", id)) do out[#out + 1] = p end
    end
    return out
end

-- Spec 016, R7: pontos de transporte entre continentes, por facção. Horde: NPCs "Zeppelin Master".
-- Aliança: objetos "Boat to ..." com posição. Posição da QuestieDB; destino de Content/Transports.lua.

-- Spec 020, R3: todo transporte da facção com posição na QuestieDB: { {kind, id, name, label} }.
function Data.TransportCandidates(faction)
    local out = {}
    local function add(kind, id, name, label)
        if #entityPoints(kind, id) > 0 then out[#out + 1] = { kind = kind, id = id, name = name, label = label } end
    end
    if faction == "Horde" and Data.N and Data.N.GetAllIds then
        for _, id in ipairs(Data.N.GetAllIds() or {}) do
            if Data.N.subName(id) == "Zeppelin Master" then
                local f = Data.N.friendlyToFaction(id)
                if f ~= nil and tostring(f):find("H") then add("npc", id, Data.N.name(id), "zepelim") end
            end
        end
    end
    if faction == "Alliance" and Data.O and Data.O.GetAllIds then
        for _, id in ipairs(Data.O.GetAllIds() or {}) do
            local n = Data.O.name(id)
            if n and n:find("^Boat to ") then add("object", id, n, "barco") end
        end
    end
    return out
end

-- Spec 019, R2: só entra rota que muda de continente. Cada ponto leva name, kind e dest.
-- Spec 020, R2: e arrival, a primeira posição do transporte do outro lado (pair da rota).
local transport = {}
function Data.TransportPoints(faction)
    if faction ~= "Horde" and faction ~= "Alliance" then return {} end
    if transport[faction] then return transport[faction] end
    local out = {}
    for _, c in ipairs(Data.TransportCandidates(faction)) do
        local route = ns.Util.CrossingRoute(ns.Transports, c.kind, c.id)
        if route then
            local arrival = route.pair and entityPoints(c.kind, route.pair)[1]
            for _, p in ipairs(entityPoints(c.kind, c.id)) do
                out[#out + 1] = { mapID = p.mapID, x = p.x, y = p.y, source = p.source, name = c.name, kind = c.label,
                    dest = route.dest, arrival = arrival }
            end
        end
    end
    transport[faction] = out
    return out
end

-- Pontos de quem dá a quest
function Data.StarterPoints(q)
    local s = Data.Q.startedBy(q) or {}
    local pts = {}
    for _, id in ipairs(s[1] or {}) do for _, p in ipairs(entityPoints("npc", id)) do pts[#pts + 1] = p end end
    for _, id in ipairs(s[2] or {}) do for _, p in ipairs(entityPoints("object", id)) do pts[#pts + 1] = p end end
    return pts
end

function Data.FinisherPoints(q)
    local f = Data.Q.finishedBy(q) or {}
    local pts = {}
    for _, id in ipairs(f[1] or {}) do for _, p in ipairs(entityPoints("npc", id)) do pts[#pts + 1] = p end end
    for _, id in ipairs(f[2] or {}) do for _, p in ipairs(entityPoints("object", id)) do pts[#pts + 1] = p end end
    return pts
end

------------------------------------------------------------------------------------------
-- Objetivos estruturados (spec 002: R1, R3, R11, R17, R18, R22)
------------------------------------------------------------------------------------------
local LOOT_RATE = 0.45 -- drop médio assumido; a QuestieDB não traz taxa de drop
local DEFAULT_COUNT = { kill = 6, loot = 4, object = 1 }

local function isEliteNpc(id)
    local r = Data.N.rank(id) or 0
    return r == 1 or r == 2
end

local function npcLevels(id, fallback)
    local lo, hi = Data.N.minLevel(id) or 0, Data.N.maxLevel(id) or 0
    if lo <= 0 then return fallback, fallback, true end
    return lo, math.max(hi, lo), false
end

local function addAll(dst, src) for _, v in ipairs(src) do dst[#dst + 1] = v end end

local function spawnCount(npc)
    local n = 0
    for _, list in pairs(Data.N.spawns(npc) or {}) do n = n + #list end
    return n
end

-- Objetivo "pegar um item que dropa": de quem dropa, pontos, níveis, elite/dungeon e taxa.
-- Usado na coleta (objetivo [3]) e no item exigido antes do objetivo (R30).
local function dropObjective(item, qLevel)
    local npcs, objs = Data.I.npcDrops(item) or {}, Data.I.objectDrops(item) or {}
    if #npcs == 0 and #objs == 0 then return nil end
    local pts, levels, allElite, est, dungeon = {}, {}, #npcs > 0, false, false
    for _, npc in ipairs(npcs) do
        addAll(pts, entityPoints("npc", npc))
        local lo, hi, e2 = npcLevels(npc, qLevel)
        levels[#levels + 1] = { lo, hi }
        est = est or e2
        if not isEliteNpc(npc) then allElite = false end
        if inDungeon(Data.N.spawns(npc)) then dungeon = true end
    end
    for _, obj in ipairs(objs) do addAll(pts, entityPoints("object", obj)) end
    local key
    if #npcs == 1 and #objs == 0 then key = "npc:" .. npcs[1] -- junta com "matar o mesmo mob" (R11)
    elseif #npcs > 0 then local s = {}; for i, n in ipairs(npcs) do s[i] = n end; table.sort(s); key = "npcs:" .. table.concat(s, ",")
    else key = "item:" .. item end
    -- R32: mob nomeado (um NPC com até 2 spawns) dropa o item de quest sempre.
    local named = #npcs == 1 and #objs == 0 and spawnCount(npcs[1]) <= 2
    return { key = key, kind = #npcs > 0 and "loot" or "object", names = { Data.I.name(item) },
        label = Data.I.name(item), points = pts, levels = levels, estimated = est,
        rate = named and 1 or LOOT_RATE, item = item }, allElite, dungeon
end

local function itemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    return f and (Util.Num(f(id)) or 0) or 0
end

-- Parte estática (não depende do jogador): calculada uma vez por quest.
local staticCache = {}
local function staticObjectives(q)
    if staticCache[q] then return staticCache[q] end
    local Q = Data.Q
    local o = Q.objectives(q) or {}
    local qLevel = Q.questLevel(q) or 1
    local list, elite, dungeon = {}, false, false
    if (Q.zoneOrSort(q) or 0) > 0 and Data.dungeons[Q.zoneOrSort(q)] then dungeon = true end

    for _, e in ipairs(o[1] or {}) do
        local id = e[1]
        local lo, hi, est = npcLevels(id, qLevel)
        if isEliteNpc(id) then elite = true end
        if inDungeon(Data.N.spawns(id)) then dungeon = true end
        list[#list + 1] = { key = "npc:" .. id, kind = "kill", names = { Data.N.name(id) },
            label = Data.N.name(id), points = entityPoints("npc", id), levels = { { lo, hi } }, estimated = est }
    end
    for _, e in ipairs(o[2] or {}) do
        local id = e[1]
        if inDungeon(Data.O.spawns(id)) then dungeon = true end
        list[#list + 1] = { key = "obj:" .. id, kind = "object", names = { Data.O.name(id) },
            label = Data.O.name(id), points = entityPoints("object", id), levels = {} }
    end
    for _, e in ipairs(o[3] or {}) do
        local ob, allElite, inDg = dropObjective(e[1], qLevel)
        if ob then
            list[#list + 1] = ob
            elite, dungeon = elite or allElite, dungeon or inDg
        else -- item sem drop conhecido: objetivo sem coordenada (a quest fica à parte, R29)
            list[#list + 1] = { key = "item:" .. e[1], kind = "object", names = { Data.I.name(e[1]) },
                label = Data.I.name(e[1]), points = {}, levels = {} }
        end
    end
    for _, e in ipairs(o[5] or {}) do -- kill credit: { {npcIds...}, creditId, nome }
        local npcs = type(e[1]) == "table" and e[1] or {}
        local pts, levels = {}, {}
        for _, npc in ipairs(npcs) do
            addAll(pts, entityPoints("npc", npc))
            local lo, hi = npcLevels(npc, qLevel)
            levels[#levels + 1] = { lo, hi }
            if isEliteNpc(npc) then elite = true end
        end
        list[#list + 1] = { key = "kc:" .. tostring(e[2]), kind = "kill", names = { e[3], Data.N.name(e[2] or 0) },
            label = e[3] or Data.N.name(e[2] or 0), points = pts, levels = levels }
    end

    -- Contagem pelo texto da base: números na ordem dos objetivos, se baterem; senão, padrão.
    local nums = {}
    for _, t in ipairs(Q.objectivesText(q) or {}) do
        if type(t) == "string" then
            for n in t:gmatch("(%d+)") do
                local v = tonumber(n)
                if v and v > 0 and v <= 40 then nums[#nums + 1] = v end
            end
        end
    end
    for i, ob in ipairs(list) do
        ob.textCount = (#nums == #list) and nums[i] or DEFAULT_COUNT[ob.kind] or 1
    end

    -- R30/R31: item exigido que dropa no mundo vira objetivo anterior aos demais.
    local sources = {}
    for _, item in ipairs(Q.requiredSourceItems(q) or {}) do
        local ob, allElite, inDg = dropObjective(item, qLevel)
        if ob then
            ob.source, ob.textCount = true, 1
            sources[#sources + 1] = ob
            elite, dungeon = elite or allElite, dungeon or inDg
        end
    end
    for _, ob in ipairs(list) do
        ob.after = {}
        for _, src in ipairs(sources) do ob.after[#ob.after + 1] = src.key end
    end
    for i = #sources, 1, -1 do table.insert(list, 1, sources[i]) end
    staticCache[q] = { list = list, elite = elite, dungeon = dungeon }
    return staticCache[q]
end

-- Progresso no log, casado pelo nome do mob/item/objeto no texto do objetivo (D5).
local function logProgress(q, ob)
    if not (Data.IsOnQuest(q) and C_QuestLog.GetQuestObjectives) then return nil end
    for _, lo in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
        local text = lo.text
        if type(text) == "string" and not Util.IsSecret(text) then
            for _, name in ipairs(ob.names) do
                if type(name) == "string" and name ~= "" and text:find(name, 1, true) then return lo end
            end
        end
    end
    return nil
end

-- Objetivos da quest para o nível do jogador:
-- { key, kind, label, points, kills, objects, mobXP, done, estimated }
function Data.Objectives(q, level, factor)
    local st = staticObjectives(q)
    local ready = Data.IsOnQuest(q) and Data.IsReadyForTurnIn(q)
    local out, doneKey = {}, {}
    for _, ob in ipairs(st.list) do
        local need, done = ob.textCount, ready
        if ob.source then
            done = ready or itemCount(ob.item) > 0 -- R30: cumprido com o item nas bolsas
        else
            local lo = logProgress(q, ob)
            if lo then
                done = lo.finished == true
                local req, got = Util.Num(lo.numRequired), Util.Num(lo.numFulfilled)
                if req and got then need = math.max(req - got, 0) end
            end
        end
        doneKey[ob.key] = done
        local kills, objects, mobXP = 0, 0, 0
        if ob.kind == "kill" then kills = need
        elseif ob.kind == "loot" then kills = math.ceil(need / (ob.rate or LOOT_RATE))
        else objects = need end
        if #ob.levels > 0 then
            for _, r in ipairs(ob.levels) do mobXP = mobXP + ns.Leveling.MobXPRange(level, r[1], r[2], factor) end
            mobXP = mobXP / #ob.levels
        end
        local after = {}
        for _, k in ipairs(ob.after or {}) do if not doneKey[k] then after[#after + 1] = k end end
        out[#out + 1] = { key = ob.key, kind = ob.kind, label = ob.label, points = ob.points,
            kills = done and 0 or kills, objects = done and 0 or objects, mobXP = mobXP, done = done,
            estimated = ob.estimated, after = after }
    end
    return out, st.elite, st.dungeon
end

-- Pontos dos objetivos que faltam e já podem ser feitos (R22, R30). Sem pendente: lista vazia.
function Data.PendingObjectivePoints(q, level)
    local pts = {}
    for _, ob in ipairs(Data.Objectives(q, level or 1)) do
        if not ob.done and #ob.after == 0 then addAll(pts, ob.points) end
    end
    return pts
end

-- Pré-requisitos diretos (preQuestSingle + preQuestGroup).
function Data.Prerequisites(q)
    local out = {}
    for _, p in ipairs(Data.Q.preQuestSingle(q) or {}) do out[#out + 1] = p end
    for _, p in ipairs(Data.Q.preQuestGroup(q) or {}) do out[#out + 1] = p end
    return out
end

------------------------------------------------------------------------------------------
-- Quests de bolsa (spec 010)
------------------------------------------------------------------------------------------
local CONTAINER, BAG, SOUL_BAG = 1, 0, 1

-- R1: recompensa da classe recipiente, subclasse bolsa; para Warlock também bolsa de alma.
function Data.IsBagQuest(q)
    local _, class = UnitClass("player")
    for _, item in ipairs(Data.Rewards(q) or {}) do
        if Data.I.class(item) == CONTAINER then
            local sub = Data.I.subClass(item)
            if sub == BAG or (sub == SOUL_BAG and class == "WARLOCK") then return true, item end
        end
    end
    return false
end

local function zoneName(mapID)
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or (mapID and ("mapa " .. mapID)) or "?"
end

-- Spec 021, R4: guarda a subzona e se o lugar é interno do NPC/objeto com diálogo aberto.
function Data.RememberPlace()
    if not (_G.UnitGUID and _G.GetSubZoneText) then return end
    local kind, id = Util.EntityFromGUID(_G.UnitGUID("npc"))
    if not kind then return end
    local db = ns.FP.db
    db.places = db.places or {}
    local key = Util.PlaceKey(kind, id)
    local old = db.places[key]
    local sub = _G.GetSubZoneText()
    local place = {
        area = (sub and sub ~= "") and sub or nil,
        indoors = (_G.IsIndoors and _G.IsIndoors()) and true or nil,
    }
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then place.mapID, place.x, place.y = mapID, pos.x * 100, pos.y * 100 end
    if not place.area and old and old.area and Util.SamePlace(old, place) then place.area = old.area end
    db.places[key] = place
end
ns.FP.On("QUEST_DIALOG", function() Data.RememberPlace() end)

-- Nomes das áreas exploradas na posição do ponto (API do jogo; nil se o client não tiver).
local function areasAt(p)
    local E = _G.C_MapExplorationInfo
    if not (E and E.GetExploredAreaIDsAtPosition and C_Map.GetAreaInfo and CreateVector2D and p.mapID) then return nil end
    local ok, ids = pcall(E.GetExploredAreaIDsAtPosition, p.mapID, CreateVector2D(p.x / 100, p.y / 100))
    if not ok or type(ids) ~= "table" then return nil end
    local names = {}
    for _, areaID in ipairs(ids) do names[#names + 1] = C_Map.GetAreaInfo(areaID) end
    return names
end

-- Spec 021, R5: dica de lugar do ponto (guardado no diálogo; senão, área pela posição).
function Data.PointPlace(p)
    if not (p and p.x and p.y) then return nil end
    local places = ns.FP.db and ns.FP.db.places
    local saved = p.source ~= nil and places and places[p.source] or nil
    if saved and not Util.SamePlace(saved, p) then saved = nil end -- outro spawn do mesmo NPC
    local names = (saved and saved.area) and { saved.area } or areasAt(p)
    return Util.PlaceHint(names, p.mapID and zoneName(p.mapID), saved and saved.indoors)
end

-- Entrada de lista (bolsa ou classe): situação, zona e ponto do quest giver.
local function questEntry(q, level)
    local Q = Data.Q
    local req = Q.requiredLevel(q) or 0
    local status
    if Data.IsOnQuest(q) then status = "no log"
    elseif Data.IsEligible(q, level) then status = "disponível"
    elseif req > level then status = "libera no nível " .. req
    else status = "depois de outra quest" end
    local starter = Data.StarterPoints(q)[1]
    local zone = Q.zoneOrSort(q) or 0
    local mapID = zone > 0 and Data.areaToMap[zone] or nil
    if not mapID then mapID = starter and starter.mapID end
    local hasPre = (Q.preQuestSingle(q) or {})[1] ~= nil or (Q.preQuestGroup(q) or {})[1] ~= nil
    local qLevel = Q.questLevel(q) or 0
    return { q = q, name = Q.name(q) or ("Quest " .. q), level = qLevel > 0 and qLevel or req, req = req,
        mapID = mapID, zone = zoneName(mapID), status = status, starter = starter, hasPre = hasPre }
end

-- Quests que a raça e a classe podem fazer, ainda não feitas, dentro do nível máximo.
local function canTake(q, level)
    local Q = Data.Q
    if completed(q) then return false end
    if not (Util.HasBit(Q.requiredRaces(q), Data.raceMask) and Util.HasBit(Q.requiredClasses(q), Data.classMask)) then
        return false
    end
    local maxLvl = Q.requiredMaxLevel(q) or 0
    return maxLvl == 0 or level <= maxLvl
end

local function byLevelThenName(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
end

-- R4 (spec 010): quests de bolsa que o personagem pode fazer, de qualquer zona.
-- { q, name, item, itemName, level, req, mapID, zone, status, starter, hasPre }
function Data.BagQuests(level)
    local out = {}
    for q in pairs(Data.rewardsByQuest) do
        local isBag, item = Data.IsBagQuest(q)
        if isBag and not Data.IsExcludedSort(q) and canTake(q, level) then
            local e = questEntry(q, level)
            e.item, e.itemName = item, Data.I.name(item)
            out[#out + 1] = e
        end
    end
    table.sort(out, byLevelThenName)
    return out
end

-- R1 (spec 011): quests da categoria da classe na QuestieDB que o personagem pode fazer.
local classQuestIDs
local function buildClassQuestIDs()
    classQuestIDs = {}
    local _, myClass = UnitClass("player")
    local sort = Data.L and Data.L.Enum and Data.L.Enum.sortKeys and Data.L.Enum.sortKeys[myClass]
    local Q = Data.Q
    if not (sort and Q.GetAllIds) then return end
    for _, q in ipairs(Q.GetAllIds() or {}) do
        if Q.zoneOrSort(q) == sort and Util.HasBit(Q.requiredClasses(q), Data.classMask) then
            classQuestIDs[#classQuestIDs + 1] = q
        end
    end
end

function Data.ClassQuests(level)
    if not classQuestIDs then buildClassQuestIDs() end
    local out = {}
    for _, q in ipairs(classQuestIDs) do
        if canTake(q, level) then out[#out + 1] = questEntry(q, level) end
    end
    table.sort(out, byLevelThenName)
    return out
end

function Data.NextInChain(q)
    local n = Data.Q.nextQuestInChain(q)
    return (n and n > 0) and n or nil
end

local LOG_SIZE = 40 -- Forever: log de 40 quests
function Data.LogFree()
    if not C_QuestLog.GetNumQuestLogEntries then return LOG_SIZE end
    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    return math.max(LOG_SIZE - (Util.Num(numQuests) or 0), 0)
end

-- Quests no log (para R16). Vazio se a API não existir.
function Data.LogQuests()
    local out = {}
    if not (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, Util.Num(n) or 0 do
        local info = C_QuestLog.GetInfo(i)
        local q = info and not info.isHeader and Util.Num(info.questID)
        if q and not Data.turnedIn[q] then out[#out + 1] = q end
    end
    return out
end

-- Quests candidatas de um mapa: dadas por alguém no mapa ou com zona = mapa.
local mapIndex = {}
function Data.QuestsForMap(mapID)
    if mapIndex[mapID] then return mapIndex[mapID] end
    local list, seen = {}, {}
    local Q = Data.Q
    for _, q in ipairs(Q.GetAllIds()) do
        local zone = Q.zoneOrSort(q) or 0
        local hit = zone > 0 and Data.areaToMap[zone] == mapID
        if not hit then
            local s = Q.startedBy(q) or {}
            for _, npc in ipairs(s[1] or {}) do
                local spawns = Data.N.spawns(npc)
                for areaId in pairs(spawns or {}) do
                    if Data.areaToMap[areaId] == mapID then hit = true; break end
                end
                if hit then break end
            end
        end
        if hit and not seen[q] then seen[q] = true; list[#list + 1] = q end
    end
    mapIndex[mapID] = list
    return list
end

------------------------------------------------------------------------------------------
-- Catálogo de zonas (spec 029, R6–R11): montado uma vez por sessão, em coroutine
------------------------------------------------------------------------------------------
-- Área -> zona-mãe (subZoneToParentZone da QuestieDB); instância fica com o próprio ID.
function Data.ZoneOfArea(area)
    local C = ns.ZoneContent or {}
    if not area or (C.instances and C.instances[area]) or Data.dungeons[area] then return area end
    return (Data.subToParent and Data.subToParent[area]) or area
end

local function giverZones(g)
    local zs = {}
    for _, n in ipairs(g and g[1] or {}) do
        for a in pairs(Data.N.spawns(n) or {}) do zs[Data.ZoneOfArea(a)] = true end
    end
    for _, o in ipairs(g and g[2] or {}) do
        for a in pairs(Data.O.spawns(o) or {}) do zs[Data.ZoneOfArea(a)] = true end
    end
    return zs
end

-- R10: ninguém da entrega na zona de quem dá a quest.
local function farDelivery(q)
    local from, to = giverZones(Data.Q.startedBy(q)), giverZones(Data.Q.finishedBy(q))
    if not next(from) or not next(to) then return false end
    for z in pairs(to) do if from[z] then return false end end
    return true
end

local function noObjectives(q)
    local o = Data.Q.objectives(q) or {}
    return #(o[1] or {}) + #(o[2] or {}) + #(o[3] or {}) + #(o[5] or {}) == 0
end

-- R8: quest de zona que entra no catálogo do personagem.
local function catalogQuest(q, faction)
    local Q, C = Data.Q, ns.ZoneContent or {}
    local area = Q.zoneOrSort(q) or 0
    if area <= 0 then return nil end
    if not (Util.HasBit(Q.requiredRaces(q), Data.raceMask) and Util.HasBit(Q.requiredClasses(q), Data.classMask)) then
        return nil
    end
    if Q.requiredSkill(q) or (C.professionAreas and C.professionAreas[area]) then return nil end
    if Data.IsExcludedSort(q) then return nil end
    local fix = ns.QuestFixes and ns.QuestFixes[q]
    if fix and fix.outOfPlan then return nil end
    local zone = Data.ZoneOfArea(area)
    local enemy = C.enemyCities and C.enemyCities[faction] or {}
    if enemy[zone] or (C.starterZones and C.starterZones[zone]) then return nil end
    return zone, area
end

local function addMob(cat, n)
    local C, N = ns.ZoneContent or {}, Data.N
    local lo, hi = N.minLevel(n) or 0, N.maxLevel(n) or 0
    if lo <= 0 or hi > 63 or (N.npcFlags(n) or 0) ~= 0 then return end
    local f = N.factionID(n) or 0
    if (C.critterFactions and C.critterFactions[f]) or ns.Zones.IsHelperName(N.name(n)) then return end
    if not ns.Zones.Hostile(Data.factionTemplate[f]) then return end
    hi = math.max(hi, lo)
    local rank = N.rank(n) or 0
    for area, pts in pairs(N.spawns(n) or {}) do
        local z = cat.zones[Data.ZoneOfArea(area)]
        if z and #pts > 0 then
            local bucket = (rank == 1 or rank == 2) and z.elite or z.hist
            local share = #pts / (hi - lo + 1)
            for l = lo, hi do bucket[l] = (bucket[l] or 0) + share end
            z.npcs[n] = true
        end
    end
end

local function newZone(cat, zone)
    local z = cat.zones[zone]
    if not z then
        z = { quests = {}, hist = {}, elite = {}, npcs = {}, anyRace = 0, forever = 0,
            continent = (ns.ZoneContent and ns.ZoneContent.continent or {})[zone] }
        cat.zones[zone] = z
    end
    return z
end

local function catalogInfo(q, zone, area)
    local Q = Data.Q
    local qLevel = Q.questLevel(q) or 0
    if qLevel <= 0 then qLevel = math.max(Q.requiredLevel(q) or 1, 1) end
    local _, elite, dungeon = Data.Objectives(q, qLevel, 1)
    local C = ns.ZoneContent or {}
    local xp, src = Data.QuestXP(q, 1)
    return { id = q, zone = zone, level = qLevel, req = math.max(Q.requiredLevel(q) or 1, 1),
        xp = xp, xpSrc = src, far = farDelivery(q), forever = q >= 90000,
        unknownWork = q >= 90000 and noObjectives(q),
        anyRace = q >= 90000 and (Q.requiredRaces(q) or 0) == 0,
        repeatFlag = Util.HasFlag(Q.specialFlags(q) or 0, 1), -- só informativo (emenda da R4)
        solo = not (elite or dungeon or (C.instances and C.instances[area]) or Data.dungeons[area]) }
end

-- R6: monta Data.zoneCatalog em coroutine (cede a cada 400 entidades) e avisa ZONE_CATALOG.
function Data.BuildZoneCatalog()
    if Data.zoneCatalog or Data.buildingCatalog or not Data.Q then return end
    Data.buildingCatalog = true
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player") or "Horde"
    local cat = { zones = {}, info = {}, children = {} }
    local co = coroutine.create(function()
        for i, q in ipairs(Data.Q.GetAllIds()) do
            local zone, area = catalogQuest(q, faction)
            if zone then
                local info = catalogInfo(q, zone, area)
                cat.info[q] = info
                local z = newZone(cat, zone)
                z.quests[#z.quests + 1] = q
                if info.forever then z.forever = z.forever + 1 end
                if info.anyRace then z.anyRace = z.anyRace + 1 end
            end
            if i % 400 == 0 then coroutine.yield() end
        end
        for q in pairs(cat.info) do
            for _, p in ipairs(Data.Prerequisites(q)) do
                cat.children[p] = cat.children[p] or {}
                table.insert(cat.children[p], q)
            end
        end
        -- Zonas de grind: as do mapa de continentes, menos zona inicial de outra raça e capital
        -- inimiga (R8 vale também para o grind: os guardas não são mob para farmar).
        local C = ns.ZoneContent or {}
        local enemy = C.enemyCities and C.enemyCities[faction] or {}
        for zone in pairs(C.continent or {}) do
            if not enemy[zone] and not (C.starterZones and C.starterZones[zone]) then newZone(cat, zone) end
        end
        for i, n in ipairs(Data.N.GetAllIds()) do
            addMob(cat, n)
            if i % 400 == 0 then coroutine.yield() end
        end
    end)
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local ok, err = coroutine.resume(co)
        if not ok then
            ns.FP.Print("erro no catálogo de zonas:", err)
            self:SetScript("OnUpdate", nil); Data.buildingCatalog = false
            return
        end
        if coroutine.status(co) == "dead" then
            self:SetScript("OnUpdate", nil)
            Data.zoneCatalog, Data.buildingCatalog = cat, false
            ns.FP.Debug("catálogo de zonas pronto")
            ns.FP.Fire("ZONE_CATALOG")
        end
    end)
end

return Data
