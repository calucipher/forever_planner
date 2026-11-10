-- UI/BuildsTab.lua: builds de talento por nível, pesos de atributo editáveis, Legacy e dicas.
local _, ns = ...
local Theme, Weights = ns.Theme, ns.Weights

local function build(panel)
    local api = {}
    local selected = ns.FP.db.preset

    -- Coluna esquerda: escolha da build
    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", 0, -4); left:SetPoint("BOTTOMLEFT"); left:SetWidth(170)
    local buildButtons = {}
    for i, b in ipairs(ns.Builds.list) do
        local card = CreateFrame("Button", nil, left, "BackdropTemplate")
        card:SetSize(170, 52); card:SetPoint("TOPLEFT", 0, -(i - 1) * 58)
        Theme.Backdrop(card, Theme.c.row)
        card.title = Theme.Text(card, 12, Theme.c.text); card.title:SetPoint("TOPLEFT", 8, -8)
        card.title:SetText(b.title)
        card.badge = Theme.Badge(card, 90); card.badge:SetPoint("BOTTOMLEFT", 8, 8)
        card.badge:Set(b.tag, b.id == "affliction" and { 0.45, 0.9, 0.35 } or { 0.7, 0.55, 1 })
        card:SetScript("OnClick", function() selected = b.id; api.Refresh() end)
        card.build = b
        buildButtons[i] = card
    end

    -- Direita: conteúdo rolável
    local area = Theme.ScrollArea(panel)
    area:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); area:SetPoint("BOTTOMRIGHT")
    local c = area.child

    local title = Theme.Text(c, 15, Theme.c.text, "OUTLINE"); title:SetPoint("TOPLEFT", 4, -4)
    local summary = Theme.Text(c, 11, Theme.c.muted); summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    summary:SetWidth(380); summary:SetWordWrap(true); summary:SetJustifyV("TOP")

    local stepLines = {}
    for i = 1, 10 do
        local lvl = Theme.Text(c, 11, Theme.c.gold); lvl:SetWidth(48)
        local txt = Theme.Text(c, 11, Theme.c.text); txt:SetWidth(330)
        stepLines[i] = { lvl = lvl, txt = txt }
    end

    local usePreset = Theme.Button(c, "Usar pesos desta build", 170, 22, function()
        ns.FP.db.preset = selected; ns.Scoring.ClearCache(); ns.FP.Fire("CHANGED"); api.Refresh()
        ns.FP.Print("perfil de pesos:", selected)
    end, "primary")

    -- Editor de pesos
    local wTitle = Theme.Text(c, 13, Theme.c.accent, "OUTLINE")
    wTitle:SetText("PESOS DE ATRIBUTO (heurísticos - ajuste à vontade)")
    local weightRows = {}
    for i, key in ipairs(Weights.order) do
        local r = CreateFrame("Frame", nil, c)
        r:SetSize(180, 20)
        r.label = Theme.Text(r, 11, Theme.c.text); r.label:SetPoint("LEFT"); r.label:SetText(Weights.statLabels[key])
        r.value = Theme.Text(r, 11, Theme.c.gold); r.value:SetPoint("LEFT", 100, 0)
        local function bump(d)
            local db = ns.FP.db
            local cur = Weights.Get(db.preset, db.customWeights, UnitLevel("player"))[key] or 0
            db.customWeights[key] = math.max(0, math.floor((cur + d) * 100 + 0.5) / 100)
            ns.Scoring.ClearCache(); ns.FP.Fire("CHANGED"); api.Refresh()
        end
        local minus = Theme.Button(r, "-", 20, 18, function() bump(-0.05) end); minus:SetPoint("LEFT", 140, 0)
        local plus = Theme.Button(r, "+", 20, 18, function() bump(0.05) end); plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        r.key = key
        weightRows[i] = r
    end
    local reset = Theme.Button(c, "Zerar ajustes", 110, 20, function()
        wipe(ns.FP.db.customWeights); ns.Scoring.ClearCache(); ns.FP.Fire("CHANGED"); api.Refresh()
    end)

    local legacyTitle = Theme.Text(c, 13, Theme.c.accent, "OUTLINE"); legacyTitle:SetText(ns.Builds.legacy.title:upper())
    local legacyLines = {}
    for i, item in ipairs(ns.Builds.legacy.items) do
        local t = Theme.Text(c, 11, Theme.c.text); t:SetWidth(380); t:SetWordWrap(true)
        t:SetText("|cFF73E65A" .. item.text .. "|r  ·  " .. item.note)
        legacyLines[i] = t
    end
    -- Marcos da classe (spec 011, R7): os marcos de níveis já passados ficam esmaecidos.
    local _, myClass = UnitClass("player")
    local classDef = ns.Classes and ns.Classes[myClass]
    local marksTitle = Theme.Text(c, 13, Theme.c.accent, "OUTLINE"); marksTitle:SetText("MARCOS DA CLASSE")
    local markLines = {}
    for i, m in ipairs(classDef and classDef.milestones or {}) do
        local lvl = Theme.Text(c, 11, Theme.c.gold); lvl:SetWidth(48); lvl:SetText(tostring(m.lvl))
        local txt = Theme.Text(c, 11, Theme.c.text); txt:SetWidth(330); txt:SetWordWrap(true); txt:SetJustifyV("TOP")
        txt:SetText(m.text)
        markLines[i] = { lvl = lvl, txt = txt, m = m }
    end
    local tipsTitle = Theme.Text(c, 13, Theme.c.accent, "OUTLINE"); tipsTitle:SetText("DICAS DE LEVELING")
    local tipLines = {}
    for i, tip in ipairs(ns.Builds.tips) do
        local t = Theme.Text(c, 11, Theme.c.text); t:SetWidth(380); t:SetWordWrap(true); t:SetJustifyV("TOP")
        t:SetText("- " .. tip)
        tipLines[i] = t
    end

    -- Layout vertical recalculado a cada refresh
    local function layout(b)
        local y = 46
        for i, line in ipairs(stepLines) do
            local s = b.steps[i]
            line.lvl:ClearAllPoints(); line.txt:ClearAllPoints()
            if s then
                line.lvl:SetPoint("TOPLEFT", 4, -y); line.txt:SetPoint("TOPLEFT", 56, -y)
                line.lvl:SetText(s.lvl); line.txt:SetText(s.text)
                line.lvl:Show(); line.txt:Show()
                y = y + 18
            else
                line.lvl:Hide(); line.txt:Hide()
            end
        end
        y = y + 6
        usePreset:ClearAllPoints(); usePreset:SetPoint("TOPLEFT", 4, -y); y = y + 34
        wTitle:ClearAllPoints(); wTitle:SetPoint("TOPLEFT", 4, -y); y = y + 20
        for i, r in ipairs(weightRows) do
            r:ClearAllPoints()
            local col, rowIdx = (i - 1) % 2, math.floor((i - 1) / 2)
            r:SetPoint("TOPLEFT", 4 + col * 196, -(y + rowIdx * 22))
        end
        y = y + math.ceil(#weightRows / 2) * 22 + 4
        reset:ClearAllPoints(); reset:SetPoint("TOPLEFT", 4, -y); y = y + 32
        legacyTitle:ClearAllPoints(); legacyTitle:SetPoint("TOPLEFT", 4, -y); y = y + 20
        for _, t in ipairs(legacyLines) do t:ClearAllPoints(); t:SetPoint("TOPLEFT", 4, -y); y = y + 18 end
        y = y + 10
        marksTitle:ClearAllPoints(); marksTitle:SetPoint("TOPLEFT", 4, -y); y = y + 20
        local level = UnitLevel("player")
        for _, line in ipairs(markLines) do
            line.lvl:ClearAllPoints(); line.txt:ClearAllPoints()
            line.lvl:SetPoint("TOPLEFT", 4, -y); line.txt:SetPoint("TOPLEFT", 56, -y)
            local past = line.m.lvl < level or ns.ClassGuide.IsMilestoneDone(line.m) -- spec 017, R3
            line.txt:SetTextColor(unpack(past and Theme.c.muted or Theme.c.text))
            y = y + math.max(16, line.txt:GetStringHeight()) + 4
        end
        y = y + 10
        tipsTitle:ClearAllPoints(); tipsTitle:SetPoint("TOPLEFT", 4, -y); y = y + 20
        for _, t in ipairs(tipLines) do
            t:ClearAllPoints(); t:SetPoint("TOPLEFT", 4, -y)
            y = y + math.max(16, t:GetStringHeight()) + 4
        end
        c:SetHeight(y + 10)
    end

    function api.Refresh()
        local db = ns.FP.db
        local b
        for _, card in ipairs(buildButtons) do
            local on = card.build.id == selected
            card:SetBackdropBorderColor(unpack(on and Theme.c.border or { 0, 0, 0, 0.8 }))
            if on then b = card.build end
        end
        b = b or ns.Builds.list[1]
        local active = db.preset == b.preset
        title:SetText(b.title .. (active and "  |cFF73E65A(pesos ativos)|r" or ""))
        summary:SetText(b.summary)
        usePreset.label:SetText(active and "Pesos ativos" or "Usar pesos desta build")
        local w = Weights.Get(db.preset, db.customWeights, UnitLevel("player"))
        for _, r in ipairs(weightRows) do
            local custom = db.customWeights[r.key] ~= nil
            r.value:SetText(string.format("%.2f%s", w[r.key] or 0, custom and "*" or ""))
        end
        layout(b)
    end
    return api
end

ns.UI.RegisterTab("builds", "Builds", build)
