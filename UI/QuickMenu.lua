-- UI/QuickMenu.lua: menu do botão "+" ao lado da seta do GPS (spec 006, R9 e R10).
local _, ns = ...
local Theme = ns.Theme
local Menu = {}
ns.QuickMenu = Menu

local ITEMS = {
    { "Melhor hub", function() ns.Guide.FollowBest("best") end, "Maior XP/h entre os hubs com 2+ quests" },
    { "Ir entregar", function() ns.Guide.FollowBest("turnin") end, "Hub mais perto com quests prontas para entregar" },
    { "Bolsa", function() ns.Guide.FollowBag() end, "Segue a melhor quest que dá bolsa (zona atual primeiro)" },
    { "Classe", function() ns.ClassGuide.Follow() end, "Segue a melhor quest de classe (pets, bolsa de alma, montaria)" },
    { "Ponto de voo", function() ns.Planner.FollowFlightPoint() end, "Aponta a seta para o ponto de voo descoberto mais perto" },
    { "Armas", function() Menu.ShowWeapons() end, "Escolhe as armas que você usa e aponta a seta para o treinador" },
    { "Grupo", function() ns.Group.ShareAll() end, "Compartilha as quests do log com o grupo e manda um resumo do que falta" },
    { "Limpar o log", function() Menu.ShowCleanup() end, "Mostra quests que não valem a pena; abandona só se você confirmar" },
    { "Reativar quests", function()
        local n = 0
        for _ in pairs(ns.FP.db.unavailable or {}) do n = n + 1 end
        ns.Planner.ClearUnavailable()
        ns.FP.Print(n .. " quest(s) que o jogo não oferecia voltaram ao plano.")
    end, "Desfaz as marcas de quest indisponível (o addon marca sozinho quando o NPC não oferece a quest)" },
}

local function buildMenu()
    local f = Theme.Panel(UIParent, Theme.c.bg, Theme.c.border)
    f:SetSize(170, 16 + #ITEMS * 30)
    f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:Hide()
    for i, item in ipairs(ITEMS) do
        local b = Theme.Button(f, item[1], 150, 24, function() f:Hide(); item[2]() end, i == 1 and "primary" or nil)
        b:SetPoint("TOP", 0, -8 - (i - 1) * 30)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(item[3], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    _G.ForeverPlannerQuickMenu = f
    tinsert(UISpecialFrames, "ForeverPlannerQuickMenu")
    return f
end

function Menu.Toggle(anchor)
    Menu.frame = Menu.frame or buildMenu()
    local f = Menu.frame
    if f:IsShown() then f:Hide(); return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    f:Show()
end

-- Spec 016: janela Armas. Uma linha por arma da classe: usar, estado e ir ao treinador.
local function buildWeapons()
    local d = Theme.Panel(UIParent, Theme.c.bg, Theme.c.border)
    d:SetWidth(420); d:SetPoint("CENTER", 0, 120)
    d:SetFrameStrata("DIALOG"); d:SetClampedToScreen(true); d:Hide()
    d.title = Theme.Text(d, 13, Theme.c.accent, "OUTLINE")
    d.title:SetPoint("TOPLEFT", 12, -10)
    d.title:SetText("Armas da classe")
    d.hint = Theme.Text(d, 10, Theme.c.muted)
    d.hint:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4); d.hint:SetWidth(396); d.hint:SetWordWrap(true)
    d.hint:SetText("Marque as armas que você quer usar. Só elas geram aviso e '(treine X)'.")
    d.rows = {}
    local close = Theme.Button(d, "Fechar", 80, 22, function() d:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    _G.ForeverPlannerWeapons = d -- UISpecialFrames procura o frame pelo nome global (ESC fecha)
    tinsert(UISpecialFrames, "ForeverPlannerWeapons")
    return d
end

function Menu.ShowWeapons()
    Menu.weapons = Menu.weapons or buildWeapons()
    local d = Menu.weapons
    local rows = ns.ClassGuide.WeaponRows()
    if #rows == 0 then ns.FP.Print("esta classe não tem perícias de arma cadastradas."); return end
    for i, r in ipairs(rows) do
        local line = d.rows[i]
        if not line then
            line = CreateFrame("Frame", nil, d)
            line:SetSize(396, 26); line:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 30)
            line.check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
            line.check:SetSize(24, 24); line.check:SetPoint("LEFT", 0, 0)
            line.name = Theme.Text(line, 12, Theme.c.text); line.name:SetPoint("LEFT", 30, 0); line.name:SetWidth(140)
            line.name:SetJustifyH("LEFT")
            line.state = Theme.Text(line, 11, Theme.c.muted); line.state:SetPoint("LEFT", 176, 0); line.state:SetWidth(110)
            line.state:SetJustifyH("LEFT")
            line.go = Theme.Button(line, "Ir ao treinador", 100, 22, nil)
            line.go:SetPoint("RIGHT", 0, 0)
            d.rows[i] = line
        end
        line.check:SetChecked(r.enabled)
        line.check:SetScript("OnClick", function(self) ns.ClassGuide.SetEnabled(r.key, self:GetChecked()); Menu.ShowWeapons() end)
        line.name:SetText(r.name)
        line.state:SetText(r.known and "|cFF73E65Atreinada|r" or (r.enabled and "|cFFFFAA00falta|r" or "|cFF888888não uso|r"))
        line.go:SetShown(not r.known and r.enabled)
        line.go:SetScript("OnClick", function() ns.ClassGuide.FollowTrainer(r.key) end)
        line:Show()
    end
    for i = #rows + 1, #d.rows do d.rows[i]:Hide() end
    d:SetHeight(50 + #rows * 30 + 44)
    d:Show()
end

-- Confirmação da limpeza (R10): lista o que sai e só abandona no clique.
local function buildDialog()
    local d = Theme.Panel(UIParent, Theme.c.bg, Theme.c.border)
    d:SetWidth(340); d:SetPoint("CENTER", 0, 120)
    d:SetFrameStrata("DIALOG"); d:SetClampedToScreen(true); d:Hide()
    d.title = Theme.Text(d, 13, Theme.c.accent, "OUTLINE")
    d.title:SetPoint("TOPLEFT", 12, -10)
    d.body = Theme.Text(d, 11, Theme.c.text)
    d.body:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8); d.body:SetWidth(316)
    d.body:SetJustifyV("TOP"); d.body:SetWordWrap(true)
    d.ok = Theme.Button(d, "Abandonar", 140, 24, nil, "primary")
    d.ok:SetPoint("BOTTOMLEFT", 12, 10)
    d.cancel = Theme.Button(d, "Cancelar", 100, 24, function() d:Hide() end)
    d.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    return d
end

function Menu.ShowCleanup()
    local list = ns.Guide.CleanupList()
    if #list == 0 then
        ns.FP.Print("nada para limpar: as quests do log valem a pena ou estão protegidas.")
        return
    end
    Menu.dialog = Menu.dialog or buildDialog()
    local d, lines, ids = Menu.dialog, {}, {}
    for _, c in ipairs(list) do
        lines[#lines + 1] = string.format("·  %s  |cFF888888(%s)|r", c.name, c.reason)
        ids[#ids + 1] = c.id
    end
    d.title:SetText(string.format("Abandonar %d quest(s)?", #list))
    d.body:SetText(table.concat(lines, "\n") ..
        "\n\n|cFF888888Protegidas e fora da lista: quest de classe, cadeia que leva a upgrade ou a muito XP, quest que não existia no Classic.|r")
    d:SetHeight(100 + d.body:GetStringHeight())
    d.ok.label:SetText(string.format("Abandonar %d", #list))
    d.ok:SetScript("OnClick", function() d:Hide(); ns.Guide.Abandon(ids) end)
    d:Show()
end

return Menu
