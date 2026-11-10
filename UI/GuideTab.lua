-- UI/GuideTab.lua: guia por hub (spec 002). Lista de hubs por XP/h e o circuito do hub escolhido.
local _, ns = ...
local Theme, Util = ns.Theme, ns.Util

local ROW_H, VISIBLE = 24, 6
local columns = { { 6, 250, "Hub" }, { 262, 50, "Quests" }, { 316, 70, "XP" }, { 390, 50, "Min" }, { 444, 90, "XP/h" } }
local REASONS = { elite = "elite", dungeon = "dungeon", ["sem coordenada"] = "sem coordenada",
    ["abaixo do limiar"] = "rende pouco", ["log cheio"] = "log cheio", desvio = "desvio grande", ["nível alto"] = "nível alto" }

local function build(panel)
    local api, rows, data, offset, selected = {}, {}, {}, 0, nil

    local follow = Theme.Button(panel, "Recalcular rota", 126, 24, function() ns.Guide.FollowBest() end, "primary")
    follow:SetPoint("TOPLEFT", 0, -4)
    local followSel = Theme.Button(panel, "Seguir este hub", 100, 24, function()
        if selected == "__bags" then ns.Guide.FollowBag()
        elseif selected == "__class" then ns.ClassGuide.Follow()
        elseif selected then ns.Guide.Follow(selected) end
    end)
    followSel:SetPoint("LEFT", follow, "RIGHT", 6, 0)
    local stop = Theme.Button(panel, "Parar GPS", 70, 24, function()
        ns.Gps.Clear(); ns.FP.db.guide = nil; api.Refresh()
    end)
    stop:SetPoint("LEFT", followSel, "RIGHT", 6, 0)
    -- Hub especial "Bolsas" (spec 010): mostra a lista no detalhe; "Seguir este hub" segue a melhor.
    local bags = Theme.Button(panel, "Bolsas", 54, 24, function() selected = "__bags"; api.Refresh() end)
    bags:SetPoint("LEFT", stop, "RIGHT", 6, 0)
    -- Hub especial "Classe" (spec 011, R3): quests de classe de qualquer zona.
    local classBtn = Theme.Button(panel, "Classe", 54, 24, function() selected = "__class"; api.Refresh() end)
    classBtn:SetPoint("LEFT", bags, "RIGHT", 6, 0)
    -- Spec 015: escolhe as armas que você usa e vai ao treinador.
    local train = Theme.Button(panel, "Armas", 56, 24, function() ns.QuickMenu.ShowWeapons() end)
    train:SetPoint("LEFT", classBtn, "RIGHT", 6, 0)
    train:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Escolha as armas que você usa e aponte a seta para o treinador de cada uma", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    train:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local summary = Theme.Text(panel, 11, Theme.c.muted)
    summary:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -16)
    summary:SetJustifyH("RIGHT")

    local header = Theme.Panel(panel, { 0.16, 0.12, 0.25, 0.9 })
    header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", 0, -34); header:SetHeight(20)
    for _, c in ipairs(columns) do
        local t = Theme.Text(header, 10, Theme.c.muted)
        t:SetPoint("LEFT", c[1], 0); t:SetWidth(c[2]); t:SetText(c[3])
    end

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    list:SetHeight(ROW_H * VISIBLE)
    list:EnableMouseWheel(true)
    local empty = Theme.Text(list, 12, Theme.c.muted)
    empty:SetPoint("CENTER")

    -- Detalhe: circuito do hub escolhido
    local detailBox = Theme.Panel(panel, Theme.c.panel)
    detailBox:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
    detailBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    local scroll = Theme.ScrollArea(detailBox)
    scroll:SetPoint("TOPLEFT", 8, -6); scroll:SetPoint("BOTTOMRIGHT", -8, 6)
    local detail = scroll.child:CreateFontString(nil, "OVERLAY")
    detail:SetFont(STANDARD_TEXT_FONT, 11, "")
    detail:SetTextColor(unpack(Theme.c.text))
    detail:SetJustifyH("LEFT"); detail:SetJustifyV("TOP")
    detail:SetPoint("TOPLEFT"); detail:SetPoint("RIGHT", scroll.child, "RIGHT")
    detail:SetWordWrap(true)

    local function showTooltip(row)
        local r = row.data
        if not r then return end
        local c = r.circuit
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP das quests", Util.FormatInt(c.xp), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        GameTooltip:AddDoubleLine("XP de mob", Util.FormatInt(c.mobXP), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        if c.restedXP > 0 then GameTooltip:AddDoubleLine("Rested", "+" .. Util.FormatInt(c.restedXP), 0.8, 0.8, 0.8, 0.5, 0.7, 1) end
        if c.upgradeXP > 0 then GameTooltip:AddDoubleLine("Upgrade (XP equiv.)", "+" .. Util.FormatInt(c.upgradeXP), 0.8, 0.8, 0.8, 0.45, 0.9, 0.35) end
        GameTooltip:AddDoubleLine("Deslocamento", string.format("%d yd", c.legs), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Tempo por morte", string.format("%.0f s", ns.FP.KillSeconds()), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Clique: ver o circuito", 0.6, 0.6, 0.7)
        GameTooltip:Show()
    end

    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, list, "BackdropTemplate")
        row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row.base = i % 2 == 0 and Theme.c.rowAlt or Theme.c.row
        Theme.Backdrop(row, row.base)
        row.name = Theme.Text(row, 12, Theme.c.text); row.name:SetPoint("LEFT", columns[1][1], 0); row.name:SetWidth(columns[1][2])
        row.count = Theme.Text(row, 12, Theme.c.text); row.count:SetPoint("LEFT", columns[2][1], 0)
        row.xp = Theme.Text(row, 12, Theme.c.gold); row.xp:SetPoint("LEFT", columns[3][1], 0)
        row.min = Theme.Text(row, 12, Theme.c.text); row.min:SetPoint("LEFT", columns[4][1], 0)
        row.rate = Theme.Text(row, 12, Theme.c.accent); row.rate:SetPoint("LEFT", columns[5][1], 0)
        row.pin = row:CreateTexture(nil, "OVERLAY")
        row.pin:SetTexture("Interface\\Buttons\\WHITE8X8"); row.pin:SetWidth(3)
        row.pin:SetPoint("TOPLEFT"); row.pin:SetPoint("BOTTOMLEFT")
        row.pin:SetVertexColor(unpack(Theme.c.fel))
        row:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(Theme.c.hover)); showTooltip(self) end)
        row:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.base)); GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self) if self.data then selected = self.data.key; api.Refresh() end end)
        rows[i] = row
    end

    local function circuitText(r)
        local c, names, lines = r.circuit, r.circuit.names, {}
        lines[#lines + 1] = string.format("|cFFB38CFF%s|r  ·  %s XP/h  ·  %.0f min", r.name,
            Util.FormatInt(c.rate), c.seconds / 60)
        for i, s in ipairs(c.stops) do
            local qs = {}
            for _, q in ipairs(s.quests) do qs[#qs + 1] = names[q] or tostring(q) end
            local color = s.kind == "pegar" and "FFFFD14D" or (s.kind == "entregar" and "FF73E65A" or "FFB38CFF")
            local what = s.kind == "objetivo"
                and string.format("%s%s", s.label or "?", s.kills > 0 and string.format(" (~%d mortes%s)", s.kills, s.estimated and ", nível do mob estimado" or "")
                    or (s.objects > 0 and string.format(" (%d coletas)", s.objects) or ""))
                or table.concat(qs, ", ")
            lines[#lines + 1] = string.format("%2d. |c%s%s|r  %s  |cFF888888(%.0f, %.0f)|r", i, color,
                s.kind:upper(), what, s.point.x, s.point.y)
        end
        local cadeia = {}
        for _, k in ipairs(c.kept) do if k.chain then cadeia[#cadeia + 1] = names[k.id] or tostring(k.id) end end
        if #cadeia > 0 then lines[#lines + 1] = "|cFF888888Mantidas por cadeia:|r " .. table.concat(cadeia, ", ") end
        if #c.aside > 0 then
            lines[#lines + 1] = " "
            lines[#lines + 1] = "|cFFFF6666Fora do circuito|r"
            for _, a in ipairs(c.aside) do
                lines[#lines + 1] = string.format("  · %s  |cFF888888(%s)|r", names[a.id] or tostring(a.id),
                    REASONS[a.reason] or a.reason)
            end
        end
        return table.concat(lines, "\n")
    end

    local function render()
        local followed = ns.FP.db.guide and ns.FP.db.guide.hub
        for i, row in ipairs(rows) do
            local r = data[i + offset]
            row.data = r
            if r then
                local c = r.circuit
                row:Show()
                row.name:SetText(r.name)
                row.count:SetText(#c.kept)
                row.xp:SetText(Util.FormatInt(c.xp + c.mobXP))
                row.min:SetText(string.format("%.0f", c.seconds / 60))
                row.rate:SetText(Util.FormatInt(c.rate))
                row.pin:SetShown(followed == r.key)
                row:SetBackdropColor(unpack(selected == r.key and Theme.c.hover or row.base))
            else
                row:Hide()
            end
        end
        local sel
        for _, r in ipairs(data) do if r.key == selected then sel = r end end
        if selected == "__bags" then
            local lines = { "|cFFB38CFFBolsas|r  ·  clique em Seguir este hub para ir à melhor" }
            for _, b in ipairs(ns.Data.ready and ns.Data.BagQuests(UnitLevel("player")) or {}) do
                lines[#lines + 1] = string.format("[%d] %s  |cFF73E65A%s|r  |cFF888888%s · %s|r",
                    b.level, b.name, b.itemName or "bolsa", b.zone, b.status)
            end
            if #lines == 1 then lines[2] = "|cFF888888nenhuma quest de bolsa para este personagem.|r" end
            detail:SetText(table.concat(lines, "\n"))
            scroll.child:SetHeight(detail:GetStringHeight() + 10)
            return
        end
        if selected == "__class" then
            local lines = { "|cFFB38CFFQuests de classe|r  ·  clique em Seguir este hub para ir à melhor" }
            for _, e in ipairs(ns.ClassGuide.List()) do
                lines[#lines + 1] = string.format("[%d] %s  |cFF888888%s · %s|r", e.level, e.name, e.zone, e.status)
            end
            if #lines == 1 then lines[2] = "|cFF888888nenhuma quest de classe para este personagem agora.|r" end
            detail:SetText(table.concat(lines, "\n"))
            scroll.child:SetHeight(detail:GetStringHeight() + 10)
            return
        end
        local f = ns.Guide.failures
        local warn = f.first and ("|cFFFF6666Falha (" .. f.count .. "): " .. f.first .. "|r\n\n") or ""
        local zone = ns.Guide.ZoneAdviceText(ns.Guide.ZoneAdvice()) -- spec 029, R19
        warn = (zone and (zone .. "\n\n") or "") .. warn
        detail:SetText(warn .. (sel and circuitText(sel) or "|cFF888888Clique num hub para ver o circuito.|r"))
        scroll.child:SetHeight(detail:GetStringHeight() + 10)
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #data - VISIBLE), offset - delta))
        render()
    end)

    function api.Refresh()
        if not ns.Data.Q then empty:SetText("QuestieDB não carregado."); return end
        empty:SetText(ns.Data.ready and "" or "Indexando recompensas da QuestieDB...")
        data = ns.Guide.Rank()
        if #data == 0 and ns.Data.ready then empty:SetText("Nenhum hub com quests elegíveis nesta zona.") end
        if not selected and data[1] then selected = data[1].key end
        offset = math.min(offset, math.max(0, #data - VISIBLE))
        local f = ns.Guide.failures
        summary:SetText(string.format("%d hubs%s", #data,
            f.count > 0 and string.format("  ·  |cFFFF6666%d falhas|r", f.count) or ""))
        local t = ns.Gps.target
        ns.UI.SetStatus(t and ("|cFF73E65AGPS:|r " .. t.title) or "GPS parado. Escolha um hub e clique em Seguir.")
        render()
    end
    return api
end

ns.UI.RegisterTab("guide", "Guia", build)
