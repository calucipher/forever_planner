-- UI/GuideTab.lua: guia por hub (spec 002). Lista de hubs por XP/h e o circuito do hub escolhido.
local _, ns = ...
local L, K = ns.L, ns.Locale.K -- spec 066
local Theme, Util = ns.Theme, ns.Util

local ROW_H, VISIBLE = 24, 6
local columns = { { 6, 250, K("Hub") }, { 262, 50, K("Quests") }, { 316, 70, K("XP") }, { 390, 50, K("Min") }, { 444, 90, K("XP/h") } }
local REASONS = { elite = K("elite"), dungeon = K("dungeon"), [K("mobs altos")] = K("mobs altos"), [K("sem coordenada")] = K("sem coordenada"),
    ["abaixo do limiar"] = K("rende pouco"), [K("log cheio")] = K("log cheio"), desvio = K("desvio grande"), [K("nível alto")] = K("nível alto") }

-- Spec 066: rótulo do tipo de parada (o tipo em si é chave interna)
local KINDS = { pegar = K("PEGAR"), entregar = K("ENTREGAR"), objetivo = K("OBJETIVO"), voo = K("VOO") }

local function build(panel)
    local api, rows, data, offset, selected = {}, {}, {}, 0, nil

    local follow = Theme.Button(panel, L["Recalcular rota"], 110, 24, function() ns.Guide.FollowBest() end, "primary")
    follow:SetPoint("TOPLEFT", 0, -4)
    local followSel = Theme.Button(panel, L["Seguir este hub"], 100, 24, function()
        if selected == "__bags" then ns.EssentialsGuide.FollowFirst() -- spec 062, R3
        elseif selected == "__class" then ns.ClassGuide.Follow()
        elseif selected then ns.Guide.Follow(selected) end
    end)
    followSel:SetPoint("LEFT", follow, "RIGHT", 6, 0)
    local stop = Theme.Button(panel, L["Parar GPS"], 66, 24, function()
        ns.Gps.Clear(); ns.FP.db.guide = nil; api.Refresh()
    end)
    stop:SetPoint("LEFT", followSel, "RIGHT", 6, 0)
    -- Spec 062: "Essenciais" no lugar de "Bolsas" (spec 010): a lista de verificação e, embaixo, as quests de bolsa.
    local bags = Theme.Button(panel, L["Essenciais"], 68, 24, function() selected = "__bags"; api.Refresh() end)
    bags:SetPoint("LEFT", stop, "RIGHT", 6, 0)
    -- Hub especial "Classe" (spec 011, R3): quests de classe de qualquer zona.
    local classBtn = Theme.Button(panel, L["Classe"], 54, 24, function() selected = "__class"; api.Refresh() end)
    classBtn:SetPoint("LEFT", bags, "RIGHT", 6, 0)
    -- Spec 015: escolhe as armas que você usa e vai ao treinador.
    local train = Theme.Button(panel, L["Armas"], 56, 24, function() ns.QuickMenu.ShowWeapons() end)
    train:SetPoint("LEFT", classBtn, "RIGHT", 6, 0)
    train:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Escolha as armas que você usa e aponte a seta para o treinador de cada uma"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    train:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Spec 051, R5: treinador da classe mais perto, com o que falta aprender.
    local trainClass = Theme.Button(panel, L["Treinar"], 58, 24, function() ns.ClassGuide.FollowClassTrainer() end)
    trainClass:SetPoint("LEFT", train, "RIGHT", 6, 0)
    trainClass:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Seta no treinador da classe mais perto e, no chat, o que falta aprender (os novos do Forever marcados)"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    trainClass:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local summary = Theme.Text(panel, 11, Theme.c.muted)
    summary:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -16)
    summary:SetJustifyH("RIGHT")

    local header = Theme.Panel(panel, { 0.16, 0.12, 0.25, 0.9 })
    header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", 0, -34); header:SetHeight(20)
    for _, c in ipairs(columns) do
        local t = Theme.Text(header, 10, Theme.c.muted)
        t:SetPoint("LEFT", c[1], 0); t:SetWidth(c[2]); t:SetText(L[c[3]])
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

    -- Linhas clicáveis da lista "Bolsas" (spec 010, R6 e R7): clique segue, botão direito dispensa.
    local BAG_ROW_H, bagRows = 16, {}
    local function showBagTip(row)
        if not row.bag then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.bag.name, 1, 1, 1)
        if row.bag.step then -- R10
            GameTooltip:AddLine(string.format(L["Começa por %s (%s, %s)"], row.bag.step.name, row.bag.step.zone,
                L[row.bag.step.status]), 0.9, 0.82, 0.3, true)
        end
        GameTooltip:AddLine(row.bag.step and L["Clique: seguir o primeiro passo da cadeia"] or L["Clique: seguir esta quest"], 0.6, 0.6, 0.7)
        GameTooltip:AddLine(row.bag.skipped and L["Botão direito: voltar a considerar"] or L["Botão direito: dispensar (não vale mais a pena)"],
            0.6, 0.6, 0.7)
        GameTooltip:Show()
    end
    local function bagRow(i)
        local row = bagRows[i]
        if row then return row end
        row = CreateFrame("Button", nil, scroll.child, "BackdropTemplate")
        row:SetHeight(BAG_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Theme.Backdrop(row, { 0, 0, 0, 0 })
        row.text = Theme.Text(row, 11, Theme.c.text)
        row.text:SetPoint("LEFT", 2, 0); row.text:SetPoint("RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self, button)
            if self.header then return end -- o título "Quests de bolsa" não é clicável
            if self.ess then ns.EssentialsGuide.Go(self.ess.key); return end -- spec 062, R4
            if not self.bag then return end
            -- O CHANGED disparado por seguir ou dispensar redesenha a aba (um render só).
            if button == "RightButton" then ns.Guide.ToggleBagSkip(self.bag.q) else ns.Guide.FollowBagQuest(self.bag.q) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.header then return end
            self:SetBackdropColor(unpack(Theme.c.hover))
            if self.bag then showBagTip(self) else GameTooltip:Hide() end
        end)
        row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0); GameTooltip:Hide() end)
        bagRows[i] = row
        return row
    end
    local function hideBagRows(from)
        for i = from, #bagRows do bagRows[i]:Hide(); bagRows[i].bag = nil; bagRows[i].ess = nil; bagRows[i].header = nil end
    end

    local function showTooltip(row)
        local r = row.data
        if not r then return end
        local c = r.circuit
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["XP das quests"], Util.FormatInt(c.xp), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        GameTooltip:AddDoubleLine(L["XP de mob"], Util.FormatInt(c.mobXP), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        if c.restedXP > 0 then GameTooltip:AddDoubleLine("Rested", "+" .. Util.FormatInt(c.restedXP), 0.8, 0.8, 0.8, 0.5, 0.7, 1) end
        if c.upgradeXP > 0 then GameTooltip:AddDoubleLine(L["Upgrade (XP equiv.)"], "+" .. Util.FormatInt(c.upgradeXP), 0.8, 0.8, 0.8, 0.45, 0.9, 0.35) end
        GameTooltip:AddDoubleLine(L["Deslocamento"], string.format(L["%d yd"], c.legs), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Tempo por morte"], string.format("%.0f s", ns.FP.KillSeconds()), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Clique: ver o circuito"], 0.6, 0.6, 0.7)
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
        -- spec 063, R5: quão difícil é o hub ("mobs −3"), pelas kills pendentes das paradas de objetivo
        local diff = ns.Leveling.MobDiff(c.stops, UnitLevel("player"))
        local mobs = diff and string.format(L["  ·  mobs %s%.0f"], diff >= 0 and "+" or "−", math.abs(diff)) or ""
        lines[#lines + 1] = string.format(L["|cFFB38CFF%s|r  ·  %s XP/h  ·  %.0f min%s%s"], r.name,
            Util.FormatInt(c.rate), c.seconds / 60, mobs,
            ns.Leveling.EasyActive(ns.FP.db.easyMode, UnitLevel("player")) and L["  ·  modo fácil"] or "")
        for i, s in ipairs(c.stops) do
            local qs = {}
            for _, q in ipairs(s.quests) do qs[#qs + 1] = names[q] or tostring(q) end
            local color = s.kind == "pegar" and "FFFFD14D" or (s.kind == "entregar" and "FF73E65A" or "FFB38CFF")
            local what = s.kind == "voo" and (L["abrir "] .. (s.label or "?")) or s.kind == "objetivo"
                and string.format("%s%s", s.label or "?", s.kills > 0 and string.format(L[" (~%d mortes%s)"], s.kills, s.estimated and L[", nível do mob estimado"] or "")
                    or (s.objects > 0 and string.format(L[" (%d coletas)"], s.objects) or ""))
                or table.concat(qs, ", ")
            lines[#lines + 1] = string.format("%2d. |c%s%s|r  %s  |cFF888888(%.0f, %.0f)|r", i, color,
                L[KINDS[s.kind] or s.kind:upper()], what, s.point.x, s.point.y)
        end
        local cadeia = {}
        for _, k in ipairs(c.kept) do if k.chain then cadeia[#cadeia + 1] = names[k.id] or tostring(k.id) end end
        if #cadeia > 0 then lines[#lines + 1] = L["|cFF888888Mantidas por cadeia:|r "] .. table.concat(cadeia, ", ") end
        if #c.aside > 0 then
            lines[#lines + 1] = " "
            lines[#lines + 1] = L["|cFFFF6666Fora do circuito|r"]
            for _, a in ipairs(c.aside) do
                local why = L[REASONS[a.reason] or a.reason]
                if a.backAt then why = why .. L[", volta no ~"] .. a.backAt end -- spec 030, R3; 031, R9 (estimativa)
                lines[#lines + 1] = string.format("  · %s  |cFF888888(%s)|r", names[a.id] or tostring(a.id), why)
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
            -- Spec 062, R3: a lista de verificação primeiro, uma linha por item (cor pelo estado).
            local ok, ess = pcall(ns.EssentialsGuide.List)
            ess = ok and ess or {}
            detail:SetText(L["|cFFB38CFFEssenciais|r  ·  clique numa linha para a seta ir lá  ·  Seguir este hub vai ao primeiro pendente"])
            local top = detail:GetStringHeight() + 4
            local COLOR = { pendente = "FFFF6666", conferir = "FFB0B0FF", depois = "FFFFD14D", feito = "FF73E65A" }
            for i, it in ipairs(ess) do
                local row = bagRow(i)
                row.bag, row.ess, row.header = nil, it, nil
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -top - (i - 1) * BAG_ROW_H); row:SetPoint("RIGHT", scroll.child, "RIGHT")
                row.text:SetText(string.format("|c%s%s|r  %s  |cFF888888%s|r", COLOR[it.status] or "FFFFFFFF", L[it.status], it.label, it.detail))
                row:Show()
            end
            local base = #ess
            top = top + base * BAG_ROW_H + 6
            local bagList = ns.Data.ready and ns.Data.BagQuests(UnitLevel("player")) or {}
            local head = bagRow(base + 1)
            head.bag, head.ess, head.header = nil, nil, true
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", 0, -top); head:SetPoint("RIGHT", scroll.child, "RIGHT")
            head.text:SetText(L["|cFFB38CFFQuests de bolsa|r  |cFF888888clique segue · botão direito dispensa|r"]
                .. (#bagList == 0 and L["  |cFF888888(nenhuma para este personagem)|r"] or ""))
            head:Show()
            top = top + BAG_ROW_H
            local following = ns.FP.db.following
            for j, b in ipairs(bagList) do
                local row = bagRow(base + 1 + j)
                row.bag, row.ess, row.header = b, nil, nil
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -top - (j - 1) * BAG_ROW_H); row:SetPoint("RIGHT", scroll.child, "RIGHT")
                local s = b.step or b
                local mark = following == s.q and "|cFF73E65A> |r" or "  "
                local item = (b.itemName or L["bolsa"]) .. (b.bonus and L[" (bônus de XP)"] or "") -- R9
                if b.skipped then
                    row.text:SetText(string.format(L["%s|cFF666666[%d] %s  %s  · %s · dispensada|r"], mark,
                        b.level, b.name, item, b.zone))
                else
                    -- R10: atrás de outra quest, mostra por onde começar.
                    local status = b.step and string.format(L["começa por %s (%s, %s)"], s.name, s.zone, L[s.status]) or L[b.status]
                    row.text:SetText(string.format("%s[%d] %s  |c%s%s|r  |cFF888888%s · %s|r", mark,
                        b.level, b.name, b.bonus and "FFFFD14D" or "FF73E65A", item, b.zone, status))
                end
                row:Show()
                if GameTooltip:IsOwned(row) then showBagTip(row) end -- a linha sob o mouse pode ter mudado de quest
            end
            hideBagRows(base + 2 + #bagList)
            scroll.child:SetHeight(top + #bagList * BAG_ROW_H + 10)
            return
        end
        hideBagRows(1)
        if selected == "__class" then
            local lines = { L["|cFFB38CFFQuests de classe|r  ·  clique em Seguir este hub para ir à melhor"] }
            for _, e in ipairs(ns.ClassGuide.List()) do
                lines[#lines + 1] = string.format("[%d] %s  |cFF888888%s · %s|r", e.level, e.name, e.zone, L[e.status])
            end
            if #lines == 1 then lines[2] = L["|cFF888888nenhuma quest de classe para este personagem agora.|r"] end
            detail:SetText(table.concat(lines, "\n"))
            scroll.child:SetHeight(detail:GetStringHeight() + 10)
            return
        end
        local f = ns.Guide.failures
        local warn = f.first and (L["|cFFFF6666Falha ("] .. f.count .. "): " .. f.first .. "|r\n\n") or ""
        local zone = ns.Guide.ZoneAdviceText(ns.Guide.ZoneAdvice()) -- spec 029, R19
        warn = (zone and (zone .. "\n\n") or "") .. warn
        detail:SetText(warn .. (sel and circuitText(sel) or L["|cFF888888Clique num hub para ver o circuito.|r"]))
        scroll.child:SetHeight(detail:GetStringHeight() + 10)
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #data - VISIBLE), offset - delta))
        render()
    end)

    function api.Refresh()
        if not ns.Data.Q then empty:SetText(L["QuestieDB não carregado."]); return end
        empty:SetText(ns.Data.ready and "" or L["Indexando recompensas da QuestieDB..."])
        data = ns.Guide.Rank()
        if #data == 0 and ns.Data.ready then empty:SetText(L["Nenhum hub com quests elegíveis nesta zona."]) end
        if not selected and data[1] then selected = data[1].key end
        offset = math.min(offset, math.max(0, #data - VISIBLE))
        local f = ns.Guide.failures
        summary:SetText(string.format(L["%d hubs%s"], #data,
            f.count > 0 and string.format(L["  ·  |cFFFF6666%d falhas|r"], f.count) or ""))
        local t = ns.Gps.target
        ns.UI.SetStatus(t and (L["|cFF73E65AGPS:|r "] .. t.title) or L["GPS parado. Escolha um hub e clique em Seguir."])
        render()
    end
    return api
end

ns.UI.RegisterTab("guide", K("Guia"), build)
