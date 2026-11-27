-- DungeonGuide.lua: adaptador da spec 041 (entrada de masmorra, meeting stone e attune).
-- Junta QuestieDB, LFG do jogo, Content/Dungeons.lua e o que o jogo aprendeu, e passa para o
-- núcleo puro (Dungeons.lua). A UI (aba Level, mapa, LFG, /fp masmorras) lê daqui.
local _, ns = ...
local L = ns.L -- spec 066
local DG = {}
ns.DungeonGuide = DG

local DUNGEON_CATEGORY = 2 -- GROUP_FINDER_CATEGORY_ID_DUNGEONS da interface da Blizzard
local LEARN_EVERY = 0.5

local function FP() return ns.FP end
local function db()
    local d = ns.FP.db
    d.dungeons = d.dungeons or {}
    return d.dungeons
end

-- Entradas aprendidas, na conta (a geografia é a mesma para todos os personagens).
function DG.Learned()
    local W = _G.ForeverPlannerWorld
    if type(W) ~= "table" then W = {}; _G.ForeverPlannerWorld = W end
    W.dungeons = W.dungeons or {}
    return W.dungeons
end

local function point(mapID, x, y)
    if not (mapID and x and y) then return nil end
    local ok, c, wx, wy = pcall(ns.Gps.ToWorld, mapID, x, y)
    if not (ok and c and wx) then return nil end
    return { c = c, x = wx, y = wy, m = mapID, mx = x, my = y }
end

-- Fontes fixas (QuestieDB e lista), convertidas uma vez por sessão.
local fixed
local function fixedSources()
    if fixed then return fixed end
    local D = ns.Data
    if not (D and D.ready and D.areaToMap) then return nil end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end -- R13: varredura pesada
    local questie, seeds, stones = {}, {}, {}
    for _, entry in pairs(D.dungeons or {}) do
        local pts = {}
        for _, loc in ipairs(type(entry[4]) == "table" and entry[4] or {}) do
            local p = point(D.areaToMap[loc[1]], loc[2], loc[3])
            if p then pts[#pts + 1] = p end
        end
        questie[#questie + 1] = { name = entry[1], points = pts }
    end
    for _, s in ipairs(ns.DungeonContent.seeds or {}) do
        seeds[#seeds + 1] = { name = s.name, source = s.source, points = { point(s.mapID, s.x, s.y) } }
    end
    if D.O and D.O.GetAllIds then
        for _, id in ipairs(D.O.GetAllIds() or {}) do
            if D.O.name(id) == "Meeting Stone" then
                for _, sp in ipairs(D.SpawnPoints(D.O.spawns(id), "o" .. id)) do
                    local p = point(sp.mapID, sp.x, sp.y)
                    if p then p.id = id; stones[#stones + 1] = p end
                end
            end
        end
    end
    fixed = { questie = questie, seeds = seeds, stones = stones }
    return fixed
end

-- Atividades de masmorra do LFG, lidas uma vez (a faixa não muda na sessão).
local acts
local function lfgActivities()
    if acts and #acts > 0 then return acts end
    local lvl = _G.C_LFGList
    if not (lvl and lvl.GetAvailableActivities and lvl.GetActivityInfoTable) then return {} end
    local ok, ids = pcall(lvl.GetAvailableActivities, DUNGEON_CATEGORY)
    if not (ok and type(ids) == "table") then return {} end
    local out = {}
    for _, id in ipairs(ids) do
        local okI, a = pcall(lvl.GetActivityInfoTable, id)
        if okI and a and a.fullName and not ns.Util.IsSecret(a.fullName) then
            out[#out + 1] = { id = id, name = a.fullName, minLevel = a.minLevel,
                minLevelSuggestion = a.minLevelSuggestion, maxLevelSuggestion = a.maxLevelSuggestion,
                orderIndex = a.orderIndex }
        end
    end
    acts = out
    return acts
end

local cache, cacheActs
function DG.Invalidate() cache = nil end

-- R1/R2: lista de masmorras (nil enquanto a QuestieDB carrega).
function DG.List()
    local src = fixedSources()
    if not src then return nil end
    local a = lfgActivities()
    if cache and cacheActs == #a then return cache end
    local C = ns.DungeonContent
    cache = ns.Dungeons.Build({ questie = src.questie, seeds = src.seeds, stones = src.stones,
        learned = DG.Learned(), acts = a, aliases = C.aliases, attunes = C.attunes })
    cacheActs = #a
    return cache
end

-- R3
function DG.ForPlayer()
    return ns.Dungeons.ForPlayer(DG.List() or {}, UnitLevel("player"))
end

-- R4: pinos de um mapa de zona.
function DG.InMap(mapID)
    local list = DG.List()
    if not (list and mapID and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return {} end
    return ns.Dungeons.InMap(list, function(c, x, y)
        local ok, m, pos = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(x, y), mapID)
        if not (ok and pos and m == mapID) then return nil end
        return pos:GetXY()
    end)
end

-- Masmorra da atividade do LFG (R10).
function DG.ForActivity(name)
    local list = DG.List()
    if not (list and name) then return nil end
    local A = ns.DungeonContent.aliases
    local k = ns.Dungeons.Norm(name)
    k = A[k] or k
    for _, d in ipairs(list) do if d.key == k then return d end end
    return nil
end

-- R6: estado do attune do personagem.
function DG.AttuneState(d)
    if not (d and d.attune) then return nil end
    local faction = _G.UnitFactionGroup("player")
    local isDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    return ns.Dungeons.Attune(d.attune, faction, function(q) return isDone and isDone(q) or false end)
end

function DG.AttuneText(d)
    local st = DG.AttuneState(d)
    if not st then return nil end
    if st.done then return "|cFF73E65AAttune: feito|r" end
    return string.format("|cFFFFD14DAttune: falta %s (%d/%d)|r", st.next.title, st.index, st.total)
end

-- Faixa colorida da atividade (dado do jogo, sem "est.").
function DG.Range(d, lvl)
    local a = d and (d.best or d.act)
    if not (a and a.maxLevelSuggestion and a.maxLevelSuggestion > 0) then return "|cFF888888faixa ?|r" end
    local lo, hi = a.minLevelSuggestion or a.minLevel or 0, a.maxLevelSuggestion
    local colors = { red = "FF1919", yellow = "FFD100", green = "40C040", gray = "808080" }
    return ("|cFF%s%s|r"):format(colors[ns.Zones.LevelColor(lo, hi, lvl or UnitLevel("player"))] or "FFFFFF",
        ns.Zones.FormatRange(lo, hi))
end

local function playerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or ns.Util.IsSecret(x) then return nil end
    return point(mapID, x * 100, y * 100)
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Entrada mais perto do jogador (mesmo continente primeiro), com a distância em jardas.
function DG.Nearest(d)
    local me, best, bestD = playerPos(), nil, nil
    for _, e in ipairs(d.entrances or {}) do
        local dd = (me and me.c == e.c) and dist(me, e) or math.huge
        if not best or dd < bestD then best, bestD = e, dd end
    end
    return best, bestD ~= math.huge and bestD or nil
end

function DG.MapName(m)
    local info = m and C_Map.GetMapInfo(m)
    return info and info.name or "?"
end

function DG.Where(p)
    if not p then return L["entrada desconhecida: entre uma vez para gravar"] end
    return string.format("%s %.1f, %.1f", DG.MapName(p.m), p.mx or 0, p.my or 0)
end

-- R8: seta.
function DG.GoEntrance(d)
    local e = DG.Nearest(d)
    if not e then FP().Print(d.name .. L[": entrada desconhecida. Entre uma vez para o addon gravar."]) return end
    ns.Gps.SetTarget(e.m, e.mx, e.my, L["Entrada: "] .. d.name .. (e.est and L[" (estimativa)"] or ""))
end

function DG.GoStone(d)
    local s = d.stone
    if not s then FP().Print(d.name .. L[": nenhuma meeting stone perto da entrada."]) return end
    ns.Gps.SetTarget(s.m, s.mx, s.my, L["Meeting stone: "] .. d.name)
end

function DG.GoAttune(d)
    local st = DG.AttuneState(d)
    if not (st and st.next) then return end
    local step, m, x, y = st.next, st.next.mapID, st.next.x, st.next.y
    if step.npc and ns.Data.N then
        local pts = ns.Data.SpawnPoints(ns.Data.N.spawns(step.npc), step.npc)
        if pts[1] then m, x, y = pts[1].mapID, pts[1].x, pts[1].y end
    end
    if not m then FP().Print(L["Attune de "] .. d.name .. L[": falta "] .. step.title .. L[" (local desconhecido)."]) return end
    ns.Gps.SetTarget(m, x, y, L["Attune: "] .. step.title)
end

-- R5: aprendizado ao entrar na instância.
local learnState = {}
local function sample()
    if (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) or (_G.UnitIsDeadOrGhost and _G.UnitIsDeadOrGhost("player")) then
        return nil
    end
    local inInstance, kind = _G.IsInInstance()
    if inInstance then
        if kind ~= "party" and kind ~= "raid" then return nil end
        local name = _G.GetInstanceInfo()
        if not name or ns.Util.IsSecret(name) then return nil end
        return { instance = true, iname = name }
    end
    return playerPos()
end
local function learnTick()
    if ns.Dungeons.Learn(DG.Learned(), learnState, sample()) then
        DG.Invalidate()
        FP().Fire("DUNGEONS")
    end
end
ns.FP.On("READY", function()
    local loc = _G.GetLocale and _G.GetLocale()
    if loc and loc ~= "enUS" then -- R12
        FP().Print(L["masmorras: o casamento é pelo nome em inglês; com o cliente em "] .. loc .. L[" a lista pode ficar vazia."])
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(LEARN_EVERY, function()
        local ok, err = pcall(learnTick)
        if not ok then FP().Debug("masmorras: aprendizado falhou: " .. tostring(err)) end
    end) end
end)

-- R11
function DG.PrintList(zoneOnly)
    local list
    if zoneOnly then
        local seen = {}
        list = {}
        for _, p in ipairs(DG.InMap(C_Map.GetBestMapForUnit("player"))) do
            if not seen[p.d] then seen[p.d] = true; list[#list + 1] = p.d end
        end
    else
        list = DG.ForPlayer()
    end
    if not DG.List() then FP().Print(L["dados da QuestieDB ainda carregando."]) return end
    if #list == 0 then
        FP().Print(zoneOnly and L["nenhuma masmorra neste mapa."] or L["nenhuma masmorra para o seu nível agora."])
        return
    end
    local lvl = UnitLevel("player")
    local okQ, quests = pcall(ns.Guide.DungeonQuests)
    if not okQ then quests = {} end
    for _, d in ipairs(list) do
        local e = DG.Nearest(d)
        FP().Print(string.format("%s  %s  · %s%s", d.name, DG.Range(d, lvl), DG.Where(e), e and e.est and L[" (estimativa)"] or ""))
        if d.stone then FP().Print(L["    meeting stone: "] .. DG.Where(d.stone)) end
        local at = DG.AttuneText(d)
        if at then FP().Print("    " .. at) end
        local mine = quests[d.key] -- spec 054, R4
        if mine then
            local names = {}
            for _, mq in ipairs(mine) do names[#names + 1] = mq.name .. (mq.skipped and L[" (pulada)"] or "") end
            FP().Print(L["    |cFFFFD100suas quests:|r "] .. table.concat(names, ", "))
        end
    end
end

function DG.ClearLearned()
    local W = DG.Learned()
    for k in pairs(W) do W[k] = nil end
    DG.Invalidate()
    FP().Fire("DUNGEONS")
    FP().Print(L["entradas de masmorra aprendidas apagadas."])
end

DG.db = db
return DG
