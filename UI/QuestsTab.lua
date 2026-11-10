-- UI/QuestsTab.lua: ranking de quests da zona. Clique numa linha = GPS segue a quest.
local _, ns = ...
local Theme, Util = ns.Theme, ns.Util

local ROW_H, VISIBLE = 30, 10

local columns = { -- x, largura, título
    { 6, 62, "" }, { 72, 28, "Nv" }, { 102, 200, "Quest" }, { 304, 64, "XP" },
    { 370, 46, "Min" }, { 418, 60, "XP/min" }, { 480, 92, "Upgrade" },
}

local function build(panel)
    local api, rows, data, offset = {}, {}, {}, 0

    -- Barra de ações
    local follow = Theme.Button(panel, "Seguir a melhor", 140, 24, function() ns.Planner.FollowBest() end, "primary")
    follow:SetPoint("TOPLEFT", 0, -4)
    local stop = Theme.Button(panel, "Parar GPS", 90, 24, function()
        ns.Gps.Clear(); ns.FP.db.following = nil; api.Refresh()
    end)
    stop:SetPoint("LEFT", follow, "RIGHT", 6, 0)
    local refresh = Theme.Button(panel, "Atualizar", 80, 24, function() api.Refresh() end)
    refresh:SetPoint("LEFT", stop, "RIGHT", 6, 0)
    local summary = Theme.Text(panel, 11, Theme.c.muted)
    summary:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -16)
    summary:SetJustifyH("RIGHT")

    -- Cabeçalho das colunas
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

    local function showTooltip(row)
        local r = row.data
        if not r then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddLine(string.format("Nível %d · %s", r.level, r.state:upper()), 0.7, 0.55, 1)
        local src = r.xpSrc == "real" and "valor real" or (r.xpSrc == "db" and "QuestieDB" or "estimativa")
        GameTooltip:AddDoubleLine("XP", Util.FormatInt(r.xp) .. " (" .. src .. ")", 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        GameTooltip:AddDoubleLine("Tempo estimado", string.format("%.1f min", r.minutes), 0.8, 0.8, 0.8, 1, 1, 1)
        if r.money > 0 then GameTooltip:AddDoubleLine("Ouro", Util.FormatMoney(r.money), 0.8, 0.8, 0.8, 1, 1, 1) end
        if r.rewardID then
            local name = C_Item.GetItemInfo(r.rewardID) or ("item " .. r.rewardID)
            GameTooltip:AddDoubleLine("Melhor recompensa", name, 0.8, 0.8, 0.8, 0.45, 0.9, 0.35)
            GameTooltip:AddDoubleLine("Ganho de score", string.format("+%.1f", r.delta), 0.8, 0.8, 0.8, 0.45, 0.9, 0.35)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Clique: GPS segue esta quest", 0.6, 0.6, 0.7)
        GameTooltip:Show()
    end

    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, list, "BackdropTemplate")
        row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        Theme.Backdrop(row, i % 2 == 0 and Theme.c.rowAlt or Theme.c.row)
        row.base = i % 2 == 0 and Theme.c.rowAlt or Theme.c.row

        row.badge = Theme.Badge(row, 62); row.badge:SetPoint("LEFT", columns[1][1], 0)
        row.level = Theme.Text(row, 12, Theme.c.text); row.level:SetPoint("LEFT", columns[2][1], 0)
        row.name = Theme.Text(row, 12, Theme.c.text); row.name:SetPoint("LEFT", columns[3][1], 0); row.name:SetWidth(columns[3][2])
        row.xp = Theme.Text(row, 12, Theme.c.gold); row.xp:SetPoint("LEFT", columns[4][1], 0)
        row.min = Theme.Text(row, 12, Theme.c.text); row.min:SetPoint("LEFT", columns[5][1], 0)
        row.rate = Theme.Text(row, 12, Theme.c.accent); row.rate:SetPoint("LEFT", columns[6][1], 0)
        row.itemIcon = row:CreateTexture(nil, "ARTWORK")
        row.itemIcon:SetSize(20, 20); row.itemIcon:SetPoint("LEFT", columns[7][1], 0)
        row.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.up = Theme.Text(row, 12, Theme.c.fel); row.up:SetPoint("LEFT", row.itemIcon, "RIGHT", 4, 0)
        row.pin = row:CreateTexture(nil, "OVERLAY")
        row.pin:SetTexture("Interface\\Buttons\\WHITE8X8"); row.pin:SetWidth(3)
        row.pin:SetPoint("TOPLEFT"); row.pin:SetPoint("BOTTOMLEFT")
        row.pin:SetVertexColor(unpack(Theme.c.fel))

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(Theme.c.hover)); showTooltip(self)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(self.base)); GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if self.data then ns.Planner.Follow(self.data.q); api.Refresh() end
        end)
        rows[i] = row
    end

    local scrollInfo = Theme.Text(panel, 10, Theme.c.muted)
    scrollInfo:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -2, -4)
    scrollInfo:SetJustifyH("RIGHT")

    local legend = Theme.Text(panel, 10, Theme.c.muted)
    legend:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -4)

    local function render()
        local following = ns.FP.db.following
        for i, row in ipairs(rows) do
            local r = data[i + offset]
            row.data = r
            if r then
                row:Show()
                row.badge:Set(r.state:upper(), Theme.stateColors[r.state])
                row.level:SetText(r.level > 0 and r.level or "?")
                row.name:SetText(r.name)
                row.xp:SetText(Util.FormatInt(r.xp) .. (r.xpSrc == "estimativa" and "*" or ""))
                row.min:SetText(string.format("%.1f", r.minutes))
                row.rate:SetText(Util.FormatInt(r.rate))
                if r.rewardID then
                    row.itemIcon:SetTexture(C_Item.GetItemIconByID(r.rewardID)); row.itemIcon:Show()
                    row.up:SetText(string.format("+%.1f", r.delta))
                else
                    row.itemIcon:Hide()
                    row.up:SetText(r.loadingItems and "|cFF888888...|r" or "")
                end
                row.pin:SetShown(following == r.q)
            else
                row:Hide()
            end
        end
        local n = #data
        scrollInfo:SetText(n > VISIBLE and string.format("%d-%d de %d  (role com a roda)",
            offset + 1, math.min(offset + VISIBLE, n), n) or "")
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #data - VISIBLE), offset - delta))
        render()
    end)

    function api.Refresh()
        if not ns.Data.Q then empty:SetText("QuestieDB não carregado."); return end
        if not ns.Data.ready then
            empty:SetText("Indexando recompensas da QuestieDB...")
            ns.UI.SetStatus("Preparando base de dados...")
        else
            empty:SetText("")
        end
        data = ns.Planner.Rank()
        if #data == 0 and ns.Data.ready then empty:SetText("Nenhuma quest elegível nesta zona.") end
        offset = math.min(offset, math.max(0, #data - VISIBLE))
        local inLog = 0
        for _, r in ipairs(data) do if r.state ~= "pegar" then inLog = inLog + 1 end end
        local f = ns.Planner.failures
        summary:SetText(string.format("%d quests · %d no log%s", #data, inLog,
            f.count > 0 and string.format(" · |cFFFF6666%d falhas|r", f.count) or ""))
        legend:SetText(f.first and ("|cFFFF6666Falha: " .. f.first .. "|r")
            or "* XP estimada (vira real quando você abre a quest)  ·  XP inclui os mobs dos objetivos")
        local t = ns.Gps.target
        ns.UI.SetStatus(t and ("|cFF73E65AGPS:|r " .. t.title) or "GPS parado. Clique numa quest ou em Seguir a melhor.")
        render()
    end
    return api
end

ns.UI.RegisterTab("quests", "Quests", build)
