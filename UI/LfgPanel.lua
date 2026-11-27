-- UI/LfgPanel.lua: painel ao lado da aba Buscar do LFG (spec 037). Lê a busca do jogador, ordena pelas
-- regras puras de Lfg.lua e abre o whisper do líder com o texto pronto. Nunca envia, convida nem busca.
-- Regras da R9: o painel é filho do UIParent, só faz SetPoint e HookScript no frame da Blizzard.
local _, ns = ...
local L = ns.L -- spec 066
local Theme, Lfg = ns.Theme, ns.Lfg
local Panel = {}
ns.LfgPanel = Panel

local BLIZZ_ADDON = "Blizzard_GroupFinder_VanillaStyle"
local MAX_ROWS, ROW_H = 25, 38
local ROLE_CYCLE = { "auto", "DPS", "Tank", "Healer" } -- "auto" = papel da R8

local calls = {}        -- R6: chamados da sessão, chave do líder -> _G.GetTime()
local states = {}       -- R7: nome do tipo de restrição -> nome do estado
local failures = {}     -- R16: falhas de leitura por função
local hooked, pending, wasInGroup = false, false, false
local frame

local function db() return ns.FP.db end

-- R16: pcall que registra e conta a falha por função.
local function handle(name, ok, ...)
    if ok then return true, ... end
    failures[name] = (failures[name] or 0) + 1
    ns.FP.LogError("LFG " .. name .. " (" .. failures[name] .. "x): " .. tostring((...)))
    return false
end
local function try(name, fn, ...) return handle(name, pcall(fn, ...)) end

local function inLockdown()
    local ci = _G.C_ChatInfo
    return ci and ci.InChatMessagingLockdown and ci.InChatMessagingLockdown() or false
end

function Panel.CanRead()
    return Lfg.CanRead(states, inLockdown(), InCombatLockdown())
end

-- R14: valores da documentação, para quando o Enum do client não existir.
local DOC_TYPES = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
local DOC_STATES = { Inactive = 0, Activating = 1, Active = 2 }
local enumWarned = false

-- Nome do valor de um Enum (o payload do evento vem como número).
local function enumName(enum, doc, value)
    if not enum then
        if not enumWarned then
            enumWarned = true
            ns.FP.LogError("LFG: Enum de restrição ausente; usando os valores da documentação")
        end
        enum = doc
    end
    for k, v in pairs(enum) do if v == value then return k end end
    return tostring(value)
end

local function myRealm() return _G.GetRealmName and _G.GetRealmName() or "" end

local function role()
    if db().lfgRole then return db().lfgRole end
    local saved
    local roles = _G.C_LFGListRoles
    if roles and roles.GetRoles then
        local ok, r = try("GetRoles", roles.GetRoles)
        if ok then saved = r end
    end
    local _, classFile = UnitClass("player")
    return Lfg.DefaultRole(saved, classFile)
end

local function fields(activity)
    return { classe = (UnitClass("player")), nivel = UnitLevel("player"), papel = role(), atividade = activity }
end

-- Lê a busca atual em linhas da R5. Só chamar com CanRead verdadeiro.
local actCache = {}
local function activityInfo(id)
    if actCache[id] == nil then
        local ok, a = try("GetActivityInfoTable", _G.C_LFGList.GetActivityInfoTable, id)
        if not (ok and a) then return nil end -- falha não fica no cache: tenta de novo no próximo refresh
        actCache[id] = {
            minLevel = a.minLevel, minLevelSuggestion = a.minLevelSuggestion, maxLevelSuggestion = a.maxLevelSuggestion,
            maxNumPlayers = a.maxNumPlayers, orderIndex = a.orderIndex, shortName = a.shortName ~= "" and a.shortName or a.fullName,
            fullName = a.fullName, -- spec 041, R10: casa com a entrada da masmorra
        }
    end
    return actCache[id]
end

local function readRows()
    local lvl = _G.C_LFGList
    if not lvl then return nil end
    local ok, _, results = try("GetFilteredSearchResults", lvl.GetFilteredSearchResults)
    if not ok then return nil end
    local rows, realm = {}, myRealm()
    for _, id in ipairs(results or {}) do
        local okI, info = try("GetSearchResultInfo", lvl.GetSearchResultInfo, id)
        if okI and info then
            local acts = {}
            for _, aid in ipairs(info.activityIDs or {}) do acts[#acts + 1] = activityInfo(aid) end
            rows[#rows + 1] = { searchResultID = id, leaderName = info.leaderName,
                key = info.leaderName and Lfg.Key(info.leaderName, nil, realm), numMembers = info.numMembers,
                age = info.age, isDelisted = info.isDelisted, hasSelf = info.hasSelf, acts = acts }
        end
    end
    return rows
end

local function statusText(key)
    local s = key and Lfg.Status(calls, key, _G.GetTime(), db().lfgCallTTL)
    if not s then return "" end
    if s.state == "chamado" then return string.format(L["|cFFB38CFFchamado há %d min|r"], math.floor(s.age / 60)) end
    return "|cFF9E99B3" .. L["sem resposta (est.)"] .. "|r"
end

local function rangeText(a)
    if not a or not a.maxLevelSuggestion or a.maxLevelSuggestion == 0 then return "" end
    return string.format("%d–%d", a.minLevelSuggestion or 0, a.maxLevelSuggestion)
end

-- Caixa de texto do painel para Ctrl+C (plano B da R12 e dica da R15).
local function showCopy(box, text)
    box:SetText(text); box:Show(); box:SetFocus(); box:HighlightText()
end

-- R11/R12: no próprio OnClick, sem corrotina nem timer.
local function callLeader(row)
    if not Panel.CanRead() then return end
    local lvl = UnitLevel("player")
    local a = Lfg.BestActivity(row.acts, lvl)
    local solo = (row.numMembers or 0) <= 1
    local text = Lfg.Message(solo and db().lfgWhisperSolo or db().lfgWhisper, fields(a and a.shortName))
    if db().lfgPrefill then
        local util = _G.ChatFrameUtil
        if not (util and util.SendTellWithMessage) then
            ns.FP.Print(L["este client não tem ChatFrameUtil.SendTellWithMessage; use /fp lfg copiar"])
            return
        end
        if not try("SendTellWithMessage", util.SendTellWithMessage, row.leaderName, text) then return end
    else
        showCopy(frame.copy, text)
    end
    Lfg.Call(calls, row.key, _G.GetTime())
    Panel.Refresh()
end

local function buildRow(parent, i)
    local r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.Backdrop(r, i % 2 == 0 and Theme.c.rowAlt or Theme.c.row)
    r:SetHeight(ROW_H - 2)
    r.top = Theme.Text(r, 11, Theme.c.text)
    r.top:SetPoint("TOPLEFT", 6, -4); r.top:SetPoint("RIGHT", -96, 0)
    r.sub = Theme.Text(r, 10, Theme.c.muted)
    r.sub:SetPoint("TOPLEFT", r.top, "BOTTOMLEFT", 0, -3); r.sub:SetPoint("RIGHT", -96, 0)
    r.btn = Theme.Button(r, L["Chamar"], 60, 22, function() if r.row then callLeader(r.row) end end, "primary")
    r.btn:SetPoint("RIGHT", -5, 0)
    -- Spec 041, R10: seta na entrada da masmorra da atividade.
    r.go = Theme.Button(r, ">", 22, 22, function() if r.dungeon then ns.DungeonGuide.GoEntrance(r.dungeon) end end)
    r.go:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
    r.go:HookScript("OnEnter", function(self)
        local d = r.dungeon
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Entrada: "] .. d.name, 1, 1, 1)
        GameTooltip:AddLine(ns.DungeonGuide.Where((ns.DungeonGuide.Nearest(d))), 0.8, 0.8, 0.8)
        if d.stone then GameTooltip:AddLine(L["Meeting stone: "] .. ns.DungeonGuide.Where(d.stone), 0.8, 0.8, 0.8) end
        local at = ns.DungeonGuide.AttuneText(d)
        if at then GameTooltip:AddLine(at, 1, 1, 1, true) end
        GameTooltip:AddLine(L["Clique: seta na entrada"], 0.6, 0.6, 0.7)
        GameTooltip:Show()
    end)
    r.go:HookScript("OnLeave", function() GameTooltip:Hide() end)
    r.go:Hide()
    return r
end

local function build()
    local f = Theme.Panel(UIParent, Theme.c.bg, Theme.c.border)
    f:SetSize(320, 470); f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true); f:Hide()
    f:EnableMouse(true)
    f.title = Theme.Text(f, 13, Theme.c.accent, "OUTLINE")
    f.title:SetPoint("TOPLEFT", 10, -8); f.title:SetText(L["Forever Planner · grupos"])
    f.close = Theme.Button(f, "x", 20, 18, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)

    f.roleBtn = Theme.Button(f, "", 140, 20, function() Panel.CycleRole() end)
    f.roleBtn:SetPoint("TOPLEFT", 10, -28)
    f.modeBtn = Theme.Button(f, "", 150, 20, function()
        db().lfgPrefill = not db().lfgPrefill; Panel.Refresh()
    end)
    f.modeBtn:SetPoint("LEFT", f.roleBtn, "RIGHT", 10, 0)

    f.copy = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    Theme.Backdrop(f.copy, Theme.c.panel, Theme.c.border)
    f.copy:SetFont(STANDARD_TEXT_FONT, 11, ""); f.copy:SetAutoFocus(false); f.copy:SetTextInsets(4, 4, 0, 0)
    f.copy:SetHeight(20); f.copy:SetPoint("TOPLEFT", 10, -52); f.copy:SetPoint("RIGHT", -10, 0)
    f.copy:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:Hide() end)
    f.copy:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    f.copy:Hide()

    f.scroll = Theme.ScrollArea(f)
    f.scroll:SetPoint("TOPLEFT", 8, -76); f.scroll:SetPoint("BOTTOMRIGHT", -8, 56)
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = buildRow(f.scroll.child, i)
        r:SetPoint("LEFT"); r:SetPoint("RIGHT")
        f.rows[i] = r
    end
    f.empty = Theme.Text(f.scroll.child, 11, Theme.c.muted)
    f.empty:SetPoint("TOPLEFT", 4, -4); f.empty:SetWordWrap(true); f.empty:SetWidth(290)
    f.soloTitle = Theme.Text(f.scroll.child, 11, Theme.c.accent) -- R10: título do bloco dos sozinhos
    f.soloTitle:SetText(L["Jogadores sozinhos"]); f.soloTitle:Hide()
    f.more = Theme.Text(f.scroll.child, 10, Theme.c.muted)  -- R10: o que passa de MAX_ROWS
    f.more:Hide()

    -- R15: listar-se sozinho.
    f.hint = Theme.Text(f, 10, Theme.c.muted)
    f.hint:SetPoint("BOTTOMLEFT", 10, 32); f.hint:SetWidth(300); f.hint:SetWordWrap(true)
    f.hint:SetText(L["Listar sozinho: os líderes te convidam com um clique. Cole o texto no comentário da aba Listar."])
    f.listBtn = Theme.Button(f, L["Copiar texto do anúncio"], 300, 20, function()
        showCopy(f.copy, Lfg.Message(db().lfgListComment, fields(nil)))
    end)
    f.listBtn:SetPoint("BOTTOMLEFT", 10, 8)

    _G.ForeverPlannerLfgPanel = f
    return f
end

local function frameOrBuild()
    frame = frame or build()
    return frame
end

function Panel.CycleRole()
    local cur, nextIdx = db().lfgRole or "auto", 1
    for i, r in ipairs(ROLE_CYCLE) do if r == cur then nextIdx = i % #ROLE_CYCLE + 1; break end end
    local r = ROLE_CYCLE[nextIdx]
    db().lfgRole = r ~= "auto" and r or nil
    Panel.Refresh()
end

local function header(f)
    local r = role()
    f.roleBtn.label:SetText(L["Papel: "] .. (r or "?") .. (db().lfgRole and "" or L[" (auto)"]))
    f.modeBtn.label:SetText(db().lfgPrefill and L["Chamar: abre o whisper"] or L["Chamar: só copia"])
end

local function fill(f, list, lvl)
    local y, soloShown = 0, false
    f.soloTitle:Hide()
    for i, r in ipairs(f.rows) do
        local row = list[i]
        r.row = row
        if row then
            local a = Lfg.BestActivity(row.acts, lvl)
            local solo = (row.numMembers or 0) <= 1
            if solo and not soloShown then
                soloShown = true
                f.soloTitle:ClearAllPoints(); f.soloTitle:SetPoint("TOPLEFT", 4, -y - 4); f.soloTitle:Show()
                y = y + 20
            end
            local size = a and a.maxNumPlayers and a.maxNumPlayers > 0 and ("/" .. a.maxNumPlayers) or ""
            local fit = a and Lfg.Fit(a, lvl)
            local color = fit == 0 and "|cFF73E659" or "|cFFEDEBF5"
            r.top:SetText(color .. ((a and a.shortName) or "?") .. "|r  " .. (solo and "sozinho" or ((row.numMembers or 0) .. size)))
            local d = a and ns.DungeonGuide.ForActivity(a.fullName or a.shortName)
            local e = d and ns.DungeonGuide.Nearest(d)
            local st = d and ns.DungeonGuide.AttuneState(d)
            r.dungeon = e and d or nil
            local where = (e and ("  · " .. ns.DungeonGuide.MapName(e.m)) or "") ..
                ((st and st.next) and (L["  |cFFFFD14DAttune: falta "] .. st.next.title .. "|r") or "")
            r.sub:SetText((row.leaderName or "?") .. "  " .. rangeText(a) .. "  " .. statusText(row.key) .. where)
            if r.dungeon then r.go:Show() else r.go:Hide() end
            if Lfg.CanCall(row, lvl) then r.btn:Show() else r.btn:Hide() end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT")
            r:Show()
            y = y + ROW_H
        else
            r:Hide()
        end
    end
    local extra = #list - #f.rows
    if extra > 0 then
        f.more:SetText(string.format(L["+%d anúncios (refine a busca)"], extra))
        f.more:ClearAllPoints(); f.more:SetPoint("TOPLEFT", 4, -y - 4); f.more:Show()
        y = y + 20
    else
        f.more:Hide()
    end
    f.scroll.child:SetHeight(math.max(1, y))
end

function Panel.Refresh()
    pending = false
    if not frame or not frame:IsShown() then return end
    header(frame)
    if not Panel.CanRead() then
        fill(frame, {}, 0); frame.empty:SetText(L["lista indisponível agora (combate ou luta de chefe)"]); frame.empty:Show()
        return
    end
    local rows = readRows()
    if not rows then
        fill(frame, {}, 0); frame.empty:SetText(L["não deu para ler a lista"]); frame.empty:Show()
        return
    end
    local lvl = UnitLevel("player")
    local list = Lfg.Sort(rows, lvl, calls)
    fill(frame, list, lvl)
    if #list == 0 then
        frame.empty:SetText(L["faça uma busca na janela do LFG; os grupos aparecem aqui, os do seu nível primeiro"])
        frame.empty:Show()
    else
        frame.empty:Hide()
    end
end

-- R10: junta a rajada de eventos num refresh a cada 0,5 s.
local function dirty()
    if pending or not frame or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.5, Panel.Refresh)
end

local function anchor()
    local f = frameOrBuild()
    f:ClearAllPoints()
    local blizz = _G.LFGParentFrame or _G.LFGBrowseFrame
    if blizz then f:SetPoint("TOPLEFT", blizz, "TOPRIGHT", 4, 0) else f:SetPoint("CENTER") end
end

-- R9: liga no frame da Blizzard só com HookScript.
local function hook()
    local browse = _G.LFGBrowseFrame
    if hooked or not browse then return end
    hooked = true
    browse:HookScript("OnShow", function() anchor(); frame:Show(); Panel.Refresh() end)
    browse:HookScript("OnHide", function() if frame then frame:Hide() end end)
    if browse:IsShown() then anchor(); frame:Show(); Panel.Refresh() end
end

-- /fp lfg: abre o painel solto (plano do T3 da spec).
function Panel.Toggle()
    local f = frameOrBuild()
    if f:IsShown() then f:Hide(); return end
    if not (_G.LFGBrowseFrame and _G.LFGBrowseFrame:IsShown()) then f:ClearAllPoints(); f:SetPoint("CENTER", 200, 0) end
    f:Show(); Panel.Refresh()
end

function Panel.Command(rest)
    rest = rest or ""
    local cmd, arg = rest:match("^(%S*)%s*(.-)$")
    if cmd == "" then Panel.Toggle()
    elseif cmd == "texto" and arg ~= "" then db().lfgWhisper = arg; ns.FP.Print(L["texto para grupo:"], arg)
    elseif cmd == "solo" and arg ~= "" then db().lfgWhisperSolo = arg; ns.FP.Print(L["texto para jogador sozinho:"], arg)
    elseif cmd == "padrao" then
        local d = ns.FP.defaults
        db().lfgWhisper, db().lfgWhisperSolo, db().lfgListComment = d.lfgWhisper, d.lfgWhisperSolo, d.lfgListComment
        ns.FP.Print(L["textos do LFG de volta ao padrão"])
    elseif cmd == "copiar" then db().lfgPrefill = false; ns.FP.Print(L["Chamar agora só copia o texto"]); Panel.Refresh()
    else
        ns.FP.Print(L["/fp lfg [texto <t> | solo <t> | padrao | copiar]. Campos: {classe} {nivel} {papel} {atividade}"])
    end
end

-- Eventos: o painel registra os dele (constituição, regra 5: UI/ registra eventos).
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PARTY_INVITE_REQUEST",
    "CHAT_MSG_WHISPER", "GROUP_ROSTER_UPDATE" }) do
    try("RegisterEvent " .. e, ev.RegisterEvent, ev, e) -- regra 7: evento que falta no client fica no debugErrors
end
ev:SetScript("OnEvent", function(_, event, a1, a2, _, _, a5)
    if event == "ADDON_LOADED" then
        if a1 == BLIZZ_ADDON then hook() end
    elseif event == "PLAYER_LOGIN" then
        local addons = _G.C_AddOns
        if addons and addons.IsAddOnLoaded and addons.IsAddOnLoaded(BLIZZ_ADDON) then hook() end
        wasInGroup = _G.IsInGroup and _G.IsInGroup() or false
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- R7: decide pelo payload (IsAddOnRestrictionActive dá false durante este evento)
        local E = _G.Enum or {}
        local state = enumName(E.AddOnRestrictionState, DOC_STATES, a2)
        states[enumName(E.AddOnRestrictionType, DOC_TYPES, a1)] = state
        if frame and frame:IsShown() then
            Panel.Refresh()
            -- R14: o bloqueio de chat pode sair um instante depois do evento; confere de novo em 0,5 s
            if state == "Inactive" then dirty() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if frame and frame:IsShown() then Panel.Refresh() end
    elseif event == "PARTY_INVITE_REQUEST" then
        -- R13: a1 = name, a5 = isNativeRealm
        if a1 then Lfg.Clear(calls, Lfg.Key(a1, a5 and myRealm() or nil, myRealm())); dirty() end
    elseif event == "CHAT_MSG_WHISPER" then
        -- R13: o nome vem secreto no bloqueio de chat; comparar daria erro de Lua
        if not inLockdown() and a2 then
            try("CHAT_MSG_WHISPER", function() Lfg.Clear(calls, Lfg.Key(a2, nil, myRealm())) end)
            dirty()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local now = _G.IsInGroup and _G.IsInGroup() or false
        if now and not wasInGroup then Lfg.ClearAll(calls); dirty() end
        wasInGroup = now
    else
        dirty()
    end
end)

return Panel
