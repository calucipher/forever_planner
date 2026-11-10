-- UI/MacrosTab.lua: macros sugeridas, com criar/atualizar e caixa para copiar.
local _, ns = ...
local Theme = ns.Theme

local CARD_H = 46

local function build(panel)
    local api, cards = {}, {}

    local intro = Theme.Text(panel, 11, Theme.c.muted)
    intro:SetPoint("TOPLEFT", 2, -6)
    intro:SetText("Feitas para repeat (alvo só em combate). Ao aprender um feitiço, as criadas se atualizam.")

    -- Caixa de visualização / cópia
    local preview = Theme.Panel(panel, { 0.03, 0.03, 0.05, 0.95 }, Theme.c.border)
    preview:SetPoint("BOTTOMLEFT", 0, 0); preview:SetPoint("BOTTOMRIGHT", 0, 0); preview:SetHeight(92)
    local pvTitle = Theme.Text(preview, 10, Theme.c.accent)
    pvTitle:SetPoint("TOPLEFT", 8, -6)
    pvTitle:SetText("Selecione uma macro para ver o texto (Ctrl+C copia)")
    local edit = CreateFrame("EditBox", nil, preview)
    edit:SetMultiLine(true); edit:SetAutoFocus(false)
    edit:SetFont("Fonts\\ARIALN.TTF", 12, "")
    edit:SetTextColor(0.85, 0.95, 0.85)
    edit:SetPoint("TOPLEFT", 8, -20); edit:SetPoint("BOTTOMRIGHT", -8, 6)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    local area = Theme.ScrollArea(panel)
    area:SetPoint("TOPLEFT", 0, -24); area:SetPoint("BOTTOMRIGHT", preview, "TOPRIGHT", 0, 6)
    local child = area.child

    local y = 0
    for _, cat in ipairs(ns.Macros.categories) do
        local h = Theme.Text(child, 13, Theme.c.accent, "OUTLINE")
        h:SetPoint("TOPLEFT", 2, -y - 4); h:SetText(cat:upper())
        y = y + 24
        for _, m in ipairs(ns.Macros.list) do
            if m.cat == cat then
                local card = Theme.Panel(child, Theme.c.row)
                card:SetPoint("TOPLEFT", 0, -y); card:SetPoint("RIGHT", child, "RIGHT", -6, 0)
                card:SetHeight(CARD_H - 4)
                card.name = Theme.Text(card, 12, Theme.c.text)
                card.name:SetPoint("TOPLEFT", 10, -7)
                card.desc = Theme.Text(card, 10, Theme.c.muted)
                card.desc:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
                card.desc:SetWidth(380); card.desc:SetText(m.desc)

                card.install = Theme.Button(card, "Criar", 70, 22, function()
                    if ns.Macros.Install(m) then api.Refresh() end
                end, "primary")
                card.install:SetPoint("RIGHT", -8, 0)
                local view = Theme.Button(card, "Ver", 46, 22, function()
                    local body, why = ns.Macros.Build(m)
                    if body then
                        pvTitle:SetText(m.name .. "  ·  " .. #body .. "/255 caracteres")
                        edit:SetText(body); edit:SetFocus(); edit:HighlightText()
                    else
                        pvTitle:SetText(m.name .. "  ·  indisponível")
                        edit:SetText(ns.Macros.WhyText(why))
                    end
                end)
                view:SetPoint("RIGHT", card.install, "LEFT", -6, 0)
                card.macro = m
                cards[#cards + 1] = card
                y = y + CARD_H
            end
        end
        y = y + 6
    end
    child:SetHeight(y)

    function api.Refresh()
        for _, card in ipairs(cards) do
            local m = card.macro
            local body, why = ns.Macros.Build(m)
            local state = body and "" or ("  |cFF888888(" .. ns.Macros.WhyText(why) .. ")|r")
            local done = ns.Macros.IsInstalled(m) and "  |cFF73E65Ainstalada|r" or ""
            local rep = m.noRepeat and "  |cFFFFAA00sem repeat|r" or ""
            card.name:SetText(m.name .. state .. rep .. done)
            card.install.label:SetText(ns.Macros.IsInstalled(m) and "Atualizar" or "Criar")
            card.install:SetEnabled(body ~= nil)
            card.install:SetAlpha(body and 1 or 0.4)
        end
    end
    return api
end

ns.UI.RegisterTab("macros", "Macros", build)
