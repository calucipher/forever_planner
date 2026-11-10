-- Auto.lua: auto accept e auto turn-in (spec 005). Os eventos chegam pelo Core ("QUEST_DIALOG").
local _, ns = ...
local Util = ns.Util
local Auto = {}
ns.Auto = Auto

local LOAD_RETRIES, LOAD_WAIT = 3, 0.33 -- R5: até ~1 s esperando itens carregarem

-- Função pura (R4, R5): choices = { { index, delta, price, loading } }. Algum item carregando: nil
-- (não escolhe). Senão: maior upgrade; sem upgrade, o usável (delta não nulo) de maior delta; sem
-- usável, maior preço de venda; sem nenhum, a primeira.
function Auto.ChooseReward(choices)
    for _, c in ipairs(choices) do
        if c.loading then return nil end
    end
    local best, bestDelta
    for _, c in ipairs(choices) do
        if c.delta and (not bestDelta or c.delta > bestDelta) then best, bestDelta = c.index, c.delta end
    end
    if best then return best end
    local bestPrice
    for _, c in ipairs(choices) do
        if (c.price or 0) > 0 and (not bestPrice or c.price > bestPrice) then best, bestPrice = c.index, c.price end
    end
    return best or (choices[1] and choices[1].index) or 1
end

local function enabled() return ns.FP.db and ns.FP.db.auto end

-- Relevante para o planejador (R1). Sem a QuestieDB não dá para saber: não aceita.
local function relevant(q)
    q = Util.Num(q)
    return q and q > 0 and ns.Data.Q ~= nil and ns.Data.IsRelevant(q, UnitLevel("player"))
end

local function onDetail()
    if _G.QuestGetAutoAccept and _G.QuestGetAutoAccept() then return end -- o jogo já aceitou
    local q = GetQuestID()
    if relevant(q) then _G.AcceptQuest(); ns.FP.Debug("auto: aceitou " .. tostring(q))
    else ns.FP.Debug("auto: não aceitou " .. tostring(q) .. " (não relevante)") end
end

local function onProgress()
    if _G.IsQuestCompletable() and (Util.Num(_G.GetQuestMoneyToGet()) or 0) == 0 then -- R2, R3
        _G.CompleteQuest(); ns.FP.Debug("auto: completou " .. tostring(GetQuestID()))
    end
end

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

local function onComplete(tries)
    local n = _G.GetNumQuestChoices() or 0
    if n <= 1 then _G.GetQuestReward(n == 1 and 1 or nil); return end
    local choices, loading = {}, false
    for i = 1, n do
        local link = _G.GetQuestItemLink("choice", i)
        local id = itemID(link)
        local delta, why
        if id then delta, why = ns.Scoring.UpgradeDelta(id) end
        if why == "loading" then loading = true end
        local price = link and select(11, C_Item.GetItemInfo(link))
        choices[i] = { index = i, delta = delta, price = Util.Num(price), loading = why == "loading", link = link }
    end
    if loading and (tries or 0) < LOAD_RETRIES then
        C_Timer.After(LOAD_WAIT, function() onComplete((tries or 0) + 1) end)
        return
    end
    local pick = Auto.ChooseReward(choices)
    if not pick then -- R5: item que não carregou não é escolhido às cegas
        ns.FP.Print("|cFFFFAA00recompensa: um item não carregou; escolha você.|r")
        return
    end
    ns.FP.Debug(string.format("auto: recompensa %d de %d", pick, n))
    ns.FP.Print("recompensa escolhida:", choices[pick].link or pick) -- R8
    _G.GetQuestReward(pick)
end

-- R6: primeiro entrega, depois pega.
local function onGossip()
    local G = _G.C_GossipInfo
    if not G then return end
    for _, info in ipairs(G.GetActiveQuests() or {}) do
        if info.isComplete then G.SelectActiveQuest(info.questID); return end
    end
    for _, info in ipairs(G.GetAvailableQuests() or {}) do
        if relevant(info.questID) then G.SelectAvailableQuest(info.questID); return end
    end
end

-- NPC com a janela antiga de saudação (sem gossip)
local function onGreeting()
    for i = 1, (_G.GetNumActiveQuests and _G.GetNumActiveQuests() or 0) do
        local _, isComplete = _G.GetActiveTitle(i)
        if isComplete then _G.SelectActiveQuest(i); return end
    end
    for i = 1, (_G.GetNumAvailableQuests and _G.GetNumAvailableQuests() or 0) do
        local questID = _G.GetAvailableQuestInfo and select(5, _G.GetAvailableQuestInfo(i))
        if relevant(questID) then _G.SelectAvailableQuest(i); return end
    end
end

local handlers = {
    QUEST_DETAIL = onDetail, QUEST_PROGRESS = onProgress, QUEST_COMPLETE = onComplete,
    GOSSIP_SHOW = onGossip, QUEST_GREETING = onGreeting,
}

ns.FP.On("QUEST_DIALOG", function(event)
    if enabled() and handlers[event] then handlers[event]() end
end)

-- R7
function Auto.Toggle()
    ns.FP.db.auto = not ns.FP.db.auto
    ns.FP.Print(ns.FP.db.auto and "auto accept/turn-in ligado." or "auto accept/turn-in desligado.")
end

return Auto
