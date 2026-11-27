-- UI/ToolsTab.lua: aba Ferramentas (spec 040). Um botão para cada comando do registro
-- (Commands.lua), por seção, e a resposta do comando na área de resultado à direita.
local _, ns = ...
local L = ns.L -- spec 066: rótulo e dica do registro (K) traduzidos na hora
local Theme = ns.Theme

local LEFT_W, BTN_W, BTN_H, GAP = 330, 158, 22, 4

local function tooltip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(text, 1, 1, 1, true); GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local linkBox -- campo de "Comparar item" em foco recebe o shift+clique do item
if _G.hooksecurefunc and _G.ChatEdit_InsertLink then
    _G.hooksecurefunc("ChatEdit_InsertLink", function(text)
        if linkBox and linkBox:HasFocus() and text then linkBox:SetText(text) end
    end)
end

local function build(panel)
    local api, toggles, values = {}, {}, {}

    -- Área de resultado (R4)
    local box = Theme.Panel(panel, Theme.c.panel)
    box:SetPoint("TOPLEFT", LEFT_W + 10, -2); box:SetPoint("BOTTOMRIGHT", 0, 0)
    local head = Theme.Text(box, 12, Theme.c.accent)
    head:SetPoint("TOPLEFT", 8, -8); head:SetText(L["Resultado"])
    local out = Theme.ScrollArea(box)
    out:SetPoint("TOPLEFT", 8, -28); out:SetPoint("BOTTOMRIGHT", -8, 8)
    local text = Theme.Text(out.child, 11, Theme.c.text)
    text:SetPoint("TOPLEFT"); text:SetPoint("RIGHT", out.child, "RIGHT")
    text:SetWordWrap(true); text:SetJustifyV("TOP")
    text:SetText("|cFF888888Clique num botão: a resposta aparece aqui.|r")

    -- R4a: confirmação e combate deixam a ação para depois; a aba diz isso em vez de "feito."
    local function pending(cmd)
        if cmd.confirma then return "|cFFFFD100Confirme na janela que abriu. A resposta sai no chat.|r" end
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            return "|cFFFFD100Em combate: o comando roda quando o combate acabar. A resposta sai no chat.|r"
        end
        return "|cFF888888feito.|r"
    end

    local function show(cmd, lines)
        head:SetText(L[cmd.label])
        text:SetText(#lines > 0 and table.concat(lines, "\n") or pending(cmd))
        out.child:SetHeight(text:GetStringHeight() + 10)
        out:SetVerticalScroll(0)
    end

    local function refreshStates()
        for _, t in ipairs(toggles) do
            local okS, on = pcall(t.cmd.state)
            on = okS and on
            t.btn.label:SetText(L[t.cmd.label] .. ": " .. (on and ("|cFF73E65A" .. L["ligado"] .. "|r") or ("|cFF888888" .. L["desligado"] .. "|r")))
        end
        for _, v in ipairs(values) do
            local okV, cur = pcall(v.cmd.value or function() end)
            if not okV then cur = nil end
            if v.edit and not v.edit:HasFocus() then v.edit:SetText(cur and tostring(cur) or "") end
            if v.btn then v.btn.label:SetText(tostring(cur or "?")) end
        end
    end

    local function run(cmd, arg)
        show(cmd, ns.Commands.Capture(function() cmd.run(arg) end))
        refreshStates()
    end

    -- Lista de comandos por seção (R1, R7)
    local list = Theme.ScrollArea(panel)
    list:SetPoint("TOPLEFT", 0, -2); list:SetPoint("BOTTOMLEFT", 0, 0); list:SetWidth(LEFT_W)
    local y = 0
    for _, section in ipairs(ns.Commands.sections) do
        local title = Theme.Text(list.child, 12, Theme.c.accent)
        title:SetPoint("TOPLEFT", 2, -y - 4); title:SetText(L[section])
        y = y + 22
        local col = 0
        for _, cmd in ipairs(ns.Commands.list) do
            if cmd.section == section and cmd.kind ~= "valor" then
                local b = Theme.Button(list.child, L[cmd.label], BTN_W, BTN_H, function() run(cmd, nil) end)
                b:SetPoint("TOPLEFT", col * (BTN_W + GAP), -y)
                tooltip(b, L[cmd.tip] .. "\n|cFF888888/fp " .. cmd.id .. "|r")
                if cmd.kind == "liga" then toggles[#toggles + 1] = { cmd = cmd, btn = b } end
                col = col + 1
                if col == 2 then col = 0; y = y + BTN_H + GAP end
            end
        end
        if col > 0 then y = y + BTN_H + GAP end
        for _, cmd in ipairs(ns.Commands.list) do
            if cmd.section == section and cmd.kind == "valor" then
                local label = Theme.Text(list.child, 11, Theme.c.text)
                label:SetPoint("TOPLEFT", 2, -y - 4); label:SetWidth(130); label:SetText(L[cmd.label])
                local v = { cmd = cmd }
                if cmd.input == "opcoes" then
                    v.btn = Theme.Button(list.child, "", 180, BTN_H, function() run(cmd, nil) end)
                    v.btn:SetPoint("TOPLEFT", 136, -y)
                    tooltip(v.btn, L[cmd.tip] .. L[" (clique troca)"] .. "\n|cFF888888/fp " .. cmd.id .. " " .. (cmd.arg or "") .. "|r")
                else
                    local edit = CreateFrame("EditBox", nil, list.child, "InputBoxTemplate")
                    edit:SetSize(cmd.input == "texto" and 118 or 60, 20); edit:SetAutoFocus(false)
                    edit:SetPoint("TOPLEFT", 142, -y - 1)
                    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); run(cmd, self:GetText()) end)
                    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                    if cmd.id == "stats" then linkBox = edit end
                    tooltip(edit, L[cmd.tip] .. "\n|cFF888888/fp " .. cmd.id .. " " .. (cmd.arg or "") .. "|r")
                    local apply = Theme.Button(list.child, L["Aplicar"], 54, BTN_H, function()
                        edit:ClearFocus(); run(cmd, edit:GetText())
                    end)
                    apply:SetPoint("LEFT", edit, "RIGHT", 4, 0)
                    v.edit = edit
                end
                values[#values + 1] = v
                y = y + BTN_H + GAP
            end
        end
        y = y + 6
    end
    list.child:SetHeight(y + 10)

    function api.Refresh()
        refreshStates()
        ns.UI.SetStatus(L["Ferramentas: cada botão é um comando /fp (passe o mouse para ver qual)."])
    end
    return api
end

ns.UI.RegisterTab("tools", ns.Locale.K("Ferramentas"), build) -- spec 066
