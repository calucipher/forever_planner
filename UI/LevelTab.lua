-- UI/LevelTab.lua: aba Level (spec 035, R13–R15). Hubs perto, o que resolver antes de sair,
-- viagens que compensam e o que voltar a fazer depois. O jogador decide: cada linha segue algo.
local _, ns = ...
local Theme, Util = ns.Theme, ns.Util

local ROW_H = 18

local function minutes(s) return math.max(1, math.floor((s or 0) / 60 + 0.5)) end
local function xph(v) return Util.FormatInt(math.floor((v or 0) + 0.5)) end

local function build(panel)
    local api, rows = {}, {}

    local header = Theme.Text(panel, 12, Theme.c.text)
    header:SetPoint("TOPLEFT", 2, -6); header:SetPoint("RIGHT", panel, "RIGHT", -110, 0)
    header:SetJustifyH("LEFT")
    local again = Theme.Button(panel, "Recalcular", 100, 22, function() ns.LevelGuide.Refresh(true); api.Refresh() end)
    again:SetPoint("TOPRIGHT", 0, -2)

    local box = Theme.Panel(panel, Theme.c.panel)
    box:SetPoint("TOPLEFT", 0, -30); box:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll = Theme.ScrollArea(box)
    scroll:SetPoint("TOPLEFT", 8, -6); scroll:SetPoint("BOTTOMRIGHT", -8, 6)

    local function showTip(row)
        local d = row.data
        if not (d and d.tip) then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        for i, line in ipairs(d.tip) do
            if i == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        end
        if d.action then GameTooltip:AddLine(d.hint or "Clique: seguir", 0.6, 0.6, 0.7) end
        GameTooltip:Show()
    end

    local function row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, scroll.child, "BackdropTemplate")
        r:SetHeight(ROW_H)
        Theme.Backdrop(r, { 0, 0, 0, 0 })
        r.text = Theme.Text(r, 11, Theme.c.text)
        r.text:SetPoint("LEFT", 2, 0); r.text:SetPoint("RIGHT", -2, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self) if self.data and self.data.action then self.data.action() end end)
        r:SetScript("OnEnter", function(self)
            if self.data and self.data.action then self:SetBackdropColor(unpack(Theme.c.hover)) end
            showTip(self)
        end)
        r:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0); GameTooltip:Hide() end)
        rows[i] = r
        return r
    end

    -- Linhas da tela: { text, action, tip, hint }
    local function lines(res)
        local out = {}
        local function title(t) out[#out + 1] = { text = "|cFFB38CFF" .. t .. "|r" } end
        local function empty(t) out[#out + 1] = { text = "  |cFF888888" .. t .. "|r" } end
        local function gap() out[#out + 1] = { text = " " } end
        local G, LG = ns.Guide, ns.LevelGuide

        title("Perto (zona atual e vizinhas)")
        for _, h in ipairs(res.near) do
            local arrive = h.plan and (" · chegar " .. ns.Travel.Describe(h.plan)) or ""
            local tip = { h.name, G.AreaName(h.zone), string.format("%d para pegar, %d para entregar · ~%d min de circuito",
                h.quests, h.turnIns, minutes(h.seconds)) }
            for _, k in ipairs(h.kept) do tip[#tip + 1] = "· " .. (h.names[k.id] or tostring(k.id)) end
            out[#out + 1] = { text = string.format("  %s  |cFF888888%s|r  |cFF73E65A%s XP/h|r  |cFF888888%d quests%s (est.)|r",
                h.name, G.AreaName(h.zone), xph(h.rate), h.quests + h.turnIns, arrive),
                action = function() G.Follow(h.key) end, tip = tip, hint = "Clique: seguir este hub" }
        end
        if #res.near == 0 then empty("nada perto rende agora") end
        gap()

        title("Antes de sair")
        for _, b in ipairs(res.before) do
            local color = b.reason == "entregar" and "FF73E65A" or "FFFFD14D"
            local loss = b.loss and string.format(" (−%d%% do XP)", math.floor(b.loss * 100 + 0.5)) or ""
            local where = b.zone and G.AreaName(b.zone) or ""
            local tip = { b.name, b.reason == "entregar" and "Pronta para entregar." or
                ("Se você subir de nível antes de entregar, ela rende menos XP (" .. b.reason .. ").") }
            if b.far and b.plan then -- emenda R20: entrega fora de "Perto", com o caminho
                where = where .. " · " .. ns.Travel.Describe(b.plan) .. " " .. LG.EstLabel(b.plan)
                for _, s in ipairs(b.plan.steps) do
                    tip[#tip + 1] = string.format("· %s%s ~%d min", s.kind, s.label and (" " .. s.label) or "", minutes(s.seconds))
                end
            end
            local trip = b.reason == "entregar" and ns.Leveling.TurnInAction(b.plan) == "viagem"
            out[#out + 1] = { text = string.format("  %s  |c%s%s%s|r  |cFF888888%s|r", b.name, color, b.reason, loss, where),
                action = function()
                    if b.reason == "entregar" then LG.FollowTurnIn(b) else ns.Planner.Follow(b.id) end
                end,
                tip = tip, hint = trip and "Clique: seta no primeiro trecho da viagem" or "Clique: seguir esta quest" }
        end
        if #res.before == 0 then empty("nada para resolver antes") end
        gap()

        title("Vale a viagem")
        for _, t in ipairs(res.trips) do
            local mark = t.better and "|cFF73E65Arende mais|r" or "|cFF888888opção|r"
            local extra = t.turnIns > 0 and string.format(" · %d entrega(s) do log lá", t.turnIns) or ""
            local tip = { G.AreaName(t.zone), ns.Travel.Describe(t.plan) .. " " .. LG.EstLabel(t.plan), -- spec 036, R19
                string.format("%s XP/h com a viagem · %d quests · ~%.1f nível(is) de conteúdo (est.)", xph(t.eff), t.n, t.levels) }
            for _, s in ipairs(t.plan.steps) do
                tip[#tip + 1] = string.format("· %s%s ~%d min", s.kind, s.label and (" " .. s.label) or "", minutes(s.seconds))
            end
            if (t.estimated or 0) > 0 then tip[#tip + 1] = "XP das quests novas do Forever é estimado." end
            out[#out + 1] = { text = string.format("  %s  %s  |cFF73E65A%s XP/h|r  |cFF888888%s %s%s|r",
                G.AreaName(t.zone), mark, xph(t.eff), ns.Travel.Describe(t.plan), LG.EstLabel(t.plan), extra),
                action = function() LG.FollowTrip(t) end, tip = tip, hint = "Clique: seta no primeiro trecho da viagem" }
        end
        if #res.trips == 0 then empty("nenhuma viagem compensa") end
        gap()

        title("Volte depois")
        for _, c in ipairs(res.comeBack) do
            out[#out + 1] = { text = string.format("  %s  |cFF888888%s · %d quest(s) altas · volte no ~%d (est.)|r",
                c.name, G.AreaName(c.zone), c.n, c.backAt),
                tip = { c.name, string.format("%d quest(s) com mobs ou nível alto demais agora; ficam boas no nível ~%d (est.).",
                    c.n, c.backAt) } }
        end
        if #res.comeBack == 0 then empty("nada alto demais por perto") end
        return out
    end

    local function render(res)
        local list
        if res and res.error then -- R12: erro aparece, não fica em "calculando..."
            list = { { text = "|cFFFF6666Erro no cálculo da aba Level:|r " .. res.error:sub(1, 120),
                tip = { "Erro no cálculo", res.error, "Clique em Recalcular; se repetir, /fp debug e mande o registro." } } }
        else
            list = res and lines(res) or { { text = "|cFF888888calculando...|r" } }
        end
        for i, d in ipairs(list) do
            local r = row(i)
            r.data = d
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", scroll.child, "RIGHT")
            r.text:SetText(d.text)
            r:Show()
            if GameTooltip:IsOwned(r) then showTip(r) end
        end
        for i = #list + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
        scroll.child:SetHeight(#list * ROW_H + 10)
    end

    panel:HookScript("OnShow", function() ns.LevelGuide.watching = true end)
    panel:HookScript("OnHide", function() ns.LevelGuide.watching = false end)
    ns.FP.On("LEVEL_GUIDE", function() if panel:IsVisible() then api.Refresh() end end)

    function api.Refresh()
        ns.LevelGuide.watching = panel:IsVisible()
        if not (ns.Data.Q and ns.Data.ready) then
            header:SetText("|cFF888888Dados da QuestieDB ainda carregando...|r")
            render(nil)
            return
        end
        local res = ns.LevelGuide.Result()
        ns.LevelGuide.Refresh()
        local L = UnitLevel("player")
        local zone = ns.Guide.PlayerArea()
        local lo, hi = ns.Guide.ZoneLevels(zone)
        header:SetText(string.format("Nível %d · %s%s", L, ns.Guide.AreaName(zone),
            lo and ("  " .. ns.Zones.RangeLabel(lo, hi, L)) or ""))
        render(res)
        ns.UI.SetStatus("Aba Level: o jogador decide. Clique numa linha para seguir.")
    end
    return api
end

ns.UI.RegisterTab("level", "Level", build)
