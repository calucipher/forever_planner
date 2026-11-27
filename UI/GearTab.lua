-- UI/GearTab.lua: aba Gear (spec 048, R4 e R5). O melhor upgrade por slot até 3 níveis à frente,
-- de onde vem (quest, cadeia, masmorra, vendedor, AH) e o preço na AH quando ela foi aberta.
local _, ns = ...
local L = ns.L -- spec 066
local Theme = ns.Theme

local SOURCE_COLOR = { quest = "FFFFD14D", cadeia = "FFB38CFF", masmorra = "FF66B3FF", vendedor = "FF73E65A", ah = "FFFF9933" }

local function money(copper)
    local g, s = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    return g > 0 and string.format("%dg %ds", g, s) or string.format("%ds", s)
end

local function build(panel)
    local api = {}
    local GG = ns.GearGuide

    local header = Theme.Text(panel, 12, Theme.c.text)
    header:SetPoint("TOPLEFT", 2, -6); header:SetPoint("RIGHT", panel, "RIGHT", -110, 0)
    header:SetJustifyH("LEFT")
    local again = Theme.Button(panel, L["Recalcular"], 100, 22, function() GG.Refresh(true); api.Refresh() end)
    again:SetPoint("TOPRIGHT", 0, -2)

    local box = Theme.Panel(panel, Theme.c.panel)
    box:SetPoint("TOPLEFT", 0, -30); box:SetPoint("BOTTOMRIGHT", 0, 0)
    local render = Theme.LineList(box, 18)

    local function line(a, prefix)
        local price = a.boe and GG.Price(a.item)
        local ah = a.boe and (L[" · |cFFFF9933AH"] .. (price and (" " .. money(price.copper)) or "") .. "|r") or ""
        local later = a.later and string.format(" · |cFFFFD14Dno %d|r", a.later) or ""
        return string.format("%s|c%s%s|r  %s  |cFF73E65A+%.1f|r  |cFF888888%s|r%s%s", prefix,
            SOURCE_COLOR[a.source] or "FFFFFFFF", a.slot, GG.ItemName(a.item), a.delta, GG.SourceText(a), later, ah)
    end

    function api.Refresh()
        if not (ns.Data.Q and ns.Data.ready) then
            header:SetText("|cFF888888Dados da QuestieDB ainda carregando...|r")
            render({})
            return
        end
        GG.Refresh()
        local r = GG.Result()
        local out = {}
        if not r then
            header:SetText("|cFF888888Procurando upgrades (quests, cadeias, masmorras, vendedores)...|r")
        else
            header:SetText(string.format(L["Nível %d · upgrades até o %d (estimativa)"], r.level, r.level + ns.Gear.AHEAD))
            if r.error then out[#out + 1] = { text = L["|cFFFF6666Erro:|r "] .. r.error:sub(1, 120) } end
            if #r.advice == 0 and not r.error then
                out[#out + 1] = { text = "  |cFF888888nenhum upgrade achado nas fontes para o seu nível|r" }
            end
            for _, a in ipairs(r.advice) do
                local tip = { L["Ganho pelos pesos da aba Builds: +"] .. string.format("%.1f", a.delta), L["Fonte: "] .. GG.SourceText(a) }
                if a.later then tip[#tip + 1] = L["Pede nível "] .. a.later .. "." end
                for _, alt in ipairs(a.alts) do
                    tip[#tip + 1] = string.format(L["ou: %s +%.1f · %s"], GG.ItemName(alt.item), alt.delta, GG.SourceText(alt))
                end
                local _, link = C_Item.GetItemInfo(a.item)
                out[#out + 1] = { text = line(a, "  "), link = link, tip = tip, action = function() GG.Go(a) end,
                    hint = a.source == "ah" and L["Clique: seta no leiloeiro"] or L["Clique: seta até a fonte"] }
            end
            if (r.loading or 0) > 0 then
                out[#out + 1] = { text = string.format("  |cFF888888%d item(ns) ainda carregando do servidor; a lista se refaz sozinha.|r", r.loading) }
            end
        end
        out[#out + 1] = { text = " " }
        out[#out + 1] = { text = "  |cFF888888Item é tratado como fixo: nada confirmou gear que escala com o nível (spec 048).|r" }
        render(out)
        ns.UI.SetStatus(L["Gear: clique num item para a seta ir até a fonte. Abra a AH para ver os preços."])
    end
    ns.FP.On("GEAR", function() if panel:IsVisible() then api.Refresh() end end)
    return api
end

-- R5: eventos do leilão (só a UI registra eventos, constituição 5).
local ah = CreateFrame("Frame")
for _, ev in ipairs({ "AUCTION_HOUSE_SHOW", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED" }) do pcall(ah.RegisterEvent, ah, ev) end
ah:SetScript("OnEvent", function(_, event, arg1)
    if event == "AUCTION_HOUSE_SHOW" then ns.GearGuide.AuctionOpened()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then ns.GearGuide.CommodityResults(arg1) -- spec 061, R6
    else ns.GearGuide.AuctionResults(arg1) end
end)

ns.UI.RegisterTab("gear", "Gear", build)
