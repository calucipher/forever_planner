-- Group.lua: share de quests e avisos de progresso no chat do grupo (spec 022).
local _, ns = ...
local Group = {}
ns.Group = Group

local GAP, MAX_LEN, PUSH_SPACING = 15, 250, 1

------------------------------------------------------------------------------------------
-- Regras puras (testadas fora do jogo)
------------------------------------------------------------------------------------------
-- R1: canal do chat do grupo.
function Group.Channel(inRaid, inInstance)
    if inInstance then return "INSTANCE_CHAT" end
    if inRaid then return "RAID" end
    return "PARTY"
end

-- R2: texto do objetivo, com "n/m" quando o jogo não põe.
function Group.ObjectiveText(o)
    local text = o.text or ""
    if not text:find("%d+%s*/%s*%d+") and (o.numRequired or 0) > 0 then
        local count = (o.numFulfilled or 0) .. "/" .. o.numRequired
        text = text == "" and count or (text .. " " .. count)
    end
    return text
end

-- R3: mensagens do que mudou entre dois estados do log. estado[q] = { name, ready, objs }.
function Group.Changes(prev, cur)
    local out, ids = {}, {}
    for q in pairs(cur) do if prev[q] then ids[#ids + 1] = q end end
    table.sort(ids)
    for _, q in ipairs(ids) do
        local p, c = prev[q], cur[q]
        for i, o in ipairs(c.objs or {}) do
            local before = p.objs and p.objs[i]
            if before and (o.numFulfilled or 0) > (before.numFulfilled or 0) then
                out[#out + 1] = { q = q, msg = "[FP] " .. c.name .. ": " .. Group.ObjectiveText(o),
                    final = (o.numRequired or 0) > 0 and o.numFulfilled >= o.numRequired }
            end
        end
        if c.ready and not p.ready then
            out[#out + 1] = { q = q, msg = "[FP] " .. c.name .. ": pronta para entregar", final = true }
        end
    end
    return out
end

-- R4: limite de envio por quest; mensagem final sempre passa.
function Group.ShouldSend(last, now, gap, final)
    if final or not last then return true end
    return now - last >= (gap or GAP)
end

-- R5: partes juntas com " | " em linhas "[FP] ..." de até maxLen caracteres.
function Group.SummaryLines(parts, maxLen)
    maxLen = maxLen or MAX_LEN
    local lines, cur = {}, nil
    for _, part in ipairs(parts) do
        local room = maxLen - 5 -- "[FP] "
        if #part > room then
            part = part:sub(1, room)
            while #part > 0 and part:byte(#part) >= 0x80 and part:byte(#part) < 0xC0 do part = part:sub(1, -2) end
            if #part > 0 and part:byte(#part) >= 0xC0 then part = part:sub(1, -2) end -- não parte um acento (UTF-8)
        end
        if cur and #cur + 3 + #part <= room then
            cur = cur .. " | " .. part
        else
            if cur then lines[#lines + 1] = "[FP] " .. cur end
            cur = part
        end
    end
    if cur then lines[#lines + 1] = "[FP] " .. cur end
    return lines
end

------------------------------------------------------------------------------------------
-- Parte que depende do jogo
------------------------------------------------------------------------------------------
local function inGroup() return _G.IsInGroup and _G.IsInGroup() or false end

local function channel()
    local inst = _G.IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and _G.IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE)
    return Group.Channel(_G.IsInRaid and _G.IsInRaid() or false, inst or false)
end

local function send(msg)
    local C = _G.C_ChatInfo
    if C and C.InChatMessagingLockdown and C.InChatMessagingLockdown() then return end -- 12.x: chat bloqueado
    local fn = (C and C.SendChatMessage) or _G.SendChatMessage
    if fn then pcall(fn, msg, channel()) end
end

local function questName(q)
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)
    if not t and ns.Data.Q then t = ns.Data.Q.name(q) end
    return t or ("quest " .. tostring(q))
end

local function questState(q)
    local objs = {}
    for _, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}) do
        local text = o.text
        if type(text) == "string" and ns.Util.IsSecret(text) then text = nil end
        objs[#objs + 1] = { text = text, numFulfilled = ns.Util.Num(o.numFulfilled) or 0,
            numRequired = ns.Util.Num(o.numRequired) or 0 }
    end
    return { name = questName(q), ready = ns.Data.IsReadyForTurnIn(q), objs = objs }
end

local function snapshot()
    local cur = {}
    for _, q in ipairs(ns.Data.LogQuests()) do cur[q] = questState(q) end
    return cur
end

local function announceOn() return ns.FP.db and ns.FP.db.groupAnnounce ~= false end

local function pushable(q)
    return C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(q)
        and C_QuestLog.SetSelectedQuest and _G.QuestLogPushQuest
end

-- Compartilha e devolve a seleção do log do jogador; erro do client não vira popup.
local function push(q)
    local before = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    pcall(C_QuestLog.SetSelectedQuest, q)
    pcall(_G.QuestLogPushQuest)
    if before then pcall(C_QuestLog.SetSelectedQuest, before) end
end

-- R6: avisos de progresso.
-- Depois do login, o log pode chegar com contagens zeradas e depois as reais: 10 s sem avisos.
local prev, lastSent, quietUntil = nil, {}, nil
ns.FP.On("READY", function() quietUntil = (_G.GetTime and _G.GetTime() or 0) + 10 end)
ns.FP.On("QUEST_LOG", function()
    local cur = snapshot()
    local now = _G.GetTime and _G.GetTime() or 0
    if prev and inGroup() and announceOn() and not (quietUntil and now < quietUntil) then
        for _, c in ipairs(Group.Changes(prev, cur)) do
            if Group.ShouldSend(lastSent[c.q], now, GAP, c.final) then
                send(c.msg); lastSent[c.q] = now
            end
        end
    end
    prev = cur
end)

-- R7: aceitar em grupo avisa e compartilha.
ns.FP.On("QUEST_ACCEPTED", function(q)
    q = ns.Util.Num(q)
    if not (q and inGroup() and announceOn()) then return end
    send("[FP] peguei: " .. questName(q))
    if pushable(q) then
        if C_Timer then C_Timer.After(0.5, function() push(q) end) else push(q) end
    end
end)

-- R8: botão "Grupo" e /fp grupo.
local function summaryPart(q)
    local st = questState(q)
    if st.ready then return st.name .. " (pronta)" end
    local objs = {}
    for _, o in ipairs(st.objs) do objs[#objs + 1] = Group.ObjectiveText(o) end
    return #objs > 0 and (st.name .. ": " .. table.concat(objs, ", ")) or st.name
end

function Group.ShareAll()
    if not inGroup() then ns.FP.Print("você não está em grupo."); return end
    local parts, n = {}, 0
    for _, q in ipairs(ns.Data.LogQuests()) do
        parts[#parts + 1] = summaryPart(q)
        if pushable(q) then
            n = n + 1
            local delay = (n - 1) * PUSH_SPACING
            if C_Timer and delay > 0 then C_Timer.After(delay, function() push(q) end) else push(q) end
        end
    end
    for _, line in ipairs(Group.SummaryLines(parts, MAX_LEN)) do send(line) end
    ns.FP.Print(string.format("compartilhando %d quest(s) com o grupo.", n))
end

-- R9
function Group.ToggleAnnounce()
    ns.FP.db.groupAnnounce = not announceOn()
    ns.FP.Print(ns.FP.db.groupAnnounce and "avisos no grupo ligados." or "avisos no grupo desligados.")
end

return Group
