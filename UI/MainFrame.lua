-- UI/MainFrame.lua: janela principal com abas (Quests, Macros, Builds).
local _, ns = ...
local Theme = ns.Theme
local UI = { tabs = {}, order = {} }
ns.UI = UI

local W, H = 600, 480

function UI.RegisterTab(id, label, builder)
    UI.tabs[id] = { id = id, label = label, builder = builder }
    table.insert(UI.order, id)
end

local function build()
    local db = ns.FP.db
    local f = CreateFrame("Frame", "ForeverPlannerFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint(db.ui.point, UIParent, db.ui.point, db.ui.x, db.ui.y)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.ui.point, db.ui.x, db.ui.y = point, x, y
    end)
    Theme.Backdrop(f, Theme.c.bg, Theme.c.border)
    tinsert(UISpecialFrames, "ForeverPlannerFrame") -- ESC fecha

    -- Cabeçalho com faixa de cor
    local band = f:CreateTexture(nil, "ARTWORK")
    band:SetTexture("Interface\\Buttons\\WHITE8X8")
    band:SetGradient("HORIZONTAL", CreateColor(0.36, 0.20, 0.62, 0.9), CreateColor(0.06, 0.05, 0.09, 0))
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(46)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_SummonFelHunter")
    icon:SetSize(30, 30); icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = Theme.Text(f, 16, Theme.c.text, "OUTLINE")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    title:SetText("FOREVER |cFFB38CFFPLANNER|r")
    f.subtitle = Theme.Text(f, 11, Theme.c.muted)
    f.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local close = Theme.Button(f, "X", 24, 24, function() f:Hide() end)
    close.label:SetFont(STANDARD_TEXT_FONT, 16, "")
    close:SetPoint("TOPRIGHT", -8, -10)

    -- Barra de abas
    f.tabButtons = {}
    local x = 10
    for _, id in ipairs(UI.order) do
        local tab = UI.tabs[id]
        local b = CreateFrame("Button", nil, f)
        b:SetSize(110, 26); b:SetPoint("TOPLEFT", x, -52)
        b.label = Theme.Text(b, 12, Theme.c.muted)
        b.label:SetPoint("CENTER"); b.label:SetText(tab.label)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(2)
        b:SetScript("OnClick", function() UI.Select(id) end)
        b:SetScript("OnEnter", function(self) if UI.current ~= id then self.label:SetTextColor(unpack(Theme.c.text)) end end)
        b:SetScript("OnLeave", function(self) if UI.current ~= id then self.label:SetTextColor(unpack(Theme.c.muted)) end end)
        f.tabButtons[id] = b
        x = x + 114
    end
    local div = Theme.Divider(f)
    div:SetPoint("TOPLEFT", 10, -78); div:SetPoint("TOPRIGHT", -10, -78)

    -- Área de conteúdo
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 10, -84); f.content:SetPoint("BOTTOMRIGHT", -10, 30)

    -- Rodapé
    f.status = Theme.Text(f, 10, Theme.c.muted)
    f.status:SetPoint("BOTTOMLEFT", 12, 10)
    f.status:SetWidth(W - 150)
    -- Spec 014: desfaz as marcas de quest que o jogo não ofereceu.
    local reset = Theme.Button(f, "Reativar quests", 110, 18, function()
        local n = 0
        for _ in pairs(ns.FP.db.unavailable or {}) do n = n + 1 end
        ns.Planner.ClearUnavailable()
        ns.FP.Print(n .. " quest(s) que o jogo não oferecia voltaram ao plano.")
    end)
    reset:SetPoint("BOTTOMRIGHT", -10, 6)
    reset:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Desfaz as marcas de quest indisponível (o addon marca sozinho quando o NPC não oferece a quest)", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reset:HookScript("OnLeave", function() GameTooltip:Hide() end)

    f:SetScript("OnShow", function() UI.Refresh() end)
    return f
end

function UI.Select(id)
    local f = UI.frame
    UI.current = id
    ns.FP.db.ui.tab = id
    for tid, b in pairs(f.tabButtons) do
        local on = tid == id
        b.label:SetTextColor(unpack(on and Theme.c.text or Theme.c.muted))
        b.line:SetVertexColor(Theme.c.accent[1], Theme.c.accent[2], Theme.c.accent[3], on and 1 or 0)
    end
    for tid, tab in pairs(UI.tabs) do
        if not tab.panel and tid == id then
            tab.panel = CreateFrame("Frame", nil, f.content)
            tab.panel:SetAllPoints()
            tab.api = tab.builder(tab.panel) or {}
        end
        if tab.panel then tab.panel:SetShown(tid == id) end
    end
    UI.Refresh()
end

function UI.SetStatus(text) if UI.frame then UI.frame.status:SetText(text or "") end end

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    f.subtitle:SetText(string.format("%s  ·  nível %d  ·  perfil: %s",
        info and info.name or "?", UnitLevel("player"),
        ns.Weights.presets[ns.FP.db.preset] and ns.Weights.presets[ns.FP.db.preset].label or ns.FP.db.preset))
    local tab = UI.tabs[UI.current]
    if tab and tab.api and tab.api.Refresh then
        ns.FP.AfterCombat("uiRefresh", tab.api.Refresh)
    end
end

function UI.Toggle()
    if not ns.FP.db then return end
    if not UI.frame then
        UI.frame = build()
        UI.Select(ns.FP.db.ui.tab or "quests")
        return
    end
    UI.frame:SetShown(not UI.frame:IsShown())
end

-- Atualização com debounce para não recalcular a cada evento
local queued = false
ns.FP.On("CHANGED", function()
    if queued or not C_Timer then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; UI.Refresh() end)
end)
ns.FP.On("GPS_TARGET", function() UI.Refresh() end)

return UI
