-- EconomyGuide.lua: adaptador da spec 061 (vender, leiloar ou desencantar). Lê as bolsas, o preço
-- da AH guardado pela spec 048 (GearGuide.Price), o Enchanting e põe a linha no tooltip.
local _, ns = ...
local Util = ns.Util
local EG = {}
ns.EconomyGuide = EG

local PRICE_DAYS = 7          -- R6: preço da AH vale por 7 dias
local QUEST, WEAPON, ARMOR = 12, 2, 4
local ENCHANTING = 333
local LABEL = { vendedor = "vendedor", leilao = "leilão", desencantar = "desencantar", guardar = "guardar" }

local function info(id)
    local I = _G.C_Item and _G.C_Item.GetItemInfo or _G.GetItemInfo
    if not I then return nil end
    local name, link, quality, ilvl, _, _, _, _, _, _, sell, classID = I(id)
    if not name then return nil end
    return { id = id, name = name, link = link, quality = quality or 0, level = ilvl or 0, sell = sell or 0,
        classID = classID, weapon = classID == WEAPON }
end

-- R6: preço da AH com menos de 7 dias, em cobre.
local function ahPrice(id)
    local p = ns.GearGuide and ns.GearGuide.Price(id)
    if not (p and p.copper) then return nil end
    if p.at and _G.time and _G.time() - p.at > PRICE_DAYS * 86400 then return nil end
    return p.copper
end

-- R5: nível de Enchanting (0 sem a profissão). API nova (GetProfessions) ou a do Classic (GetSkillLineInfo).
local skillCache
function EG.EnchantingSkill()
    if skillCache == nil then skillCache = EG.ReadEnchanting() end
    return skillCache
end
function EG.ReadEnchanting()
    if _G.GetProfessions and _G.GetProfessionInfo then
        for _, idx in ipairs({ _G.GetProfessions() }) do
            local _, _, rank, _, _, _, line = _G.GetProfessionInfo(idx)
            if line == ENCHANTING then return rank or 0 end
        end
    end
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        for i = 1, _G.GetNumSkillLines() do
            local name, _, _, rank = _G.GetSkillLineInfo(i)
            if name == "Enchanting" or name == "Encantamento" then return rank or 0 end
        end
    end
    return 0
end

local function matPrices(it)
    local out = {}
    for _, id in ipairs(ns.Economy.MatIds(it, ns.DisenchantTable)) do out[id] = ahPrice(id) end
    return out
end

-- R3/R5: destino de um item ({ id, count, bound }).
function EG.Evaluate(id, count, bound)
    local it = info(id)
    if not it then return nil end
    count = count or 1
    local keep = it.classID == QUEST
    if not keep and ns.Scoring and ns.Scoring.UpgradeDelta then
        local ok, delta = pcall(ns.Scoring.UpgradeDelta, id)
        keep = ok and (delta or 0) > 0
    end
    local E, T = ns.Economy, ns.DisenchantTable
    local vendor = it.sell * count
    local ah = not bound and E.AuctionNet(ahPrice(id) and ahPrice(id) * count, vendor) or nil
    local canDE = (it.classID == WEAPON or it.classID == ARMOR) and E.CanDisenchant(EG.EnchantingSkill(), it.level, T)
    local de = (it.classID == WEAPON or it.classID == ARMOR) and E.DisenchantValue(it, matPrices(it), T) or nil
    de = E.Value(de and de * (1 - E.CUT), count) -- R1b: a pilha inteira (parecer 061)
    local r = E.BestUse({ vendor = vendor, ah = ah, de = de, canDE = canDE, keep = keep })
    r.item, r.count, r.bound, r.canDE = it, count, bound, canDE
    r.tradeable = not bound and it.quality >= 2
    return r
end

-- Itens das bolsas: { id, count, bound }. Cache até a bolsa mudar (parecer 061: o tooltip chama muito).
local bagCache
local function bagItems()
    if bagCache then return bagCache end
    local C, out = _G.C_Container, {}
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
    for bag = 0, 4 do
        for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
            local d = C.GetContainerItemInfo(bag, slot)
            if d and d.itemID then out[#out + 1] = { id = d.itemID, count = d.stackCount or 1, bound = d.isBound == true } end
        end
    end
    bagCache = out
    return out
end
local evalCache = {}
-- Os eventos chegam pelo Core (constituição 5: só Core, Gps e UI registram eventos).
local function reset() bagCache, evalCache = nil, {} end
ns.FP.On("BAGS", reset)
ns.FP.On("EQUIPMENT", reset)
ns.FP.On("LEVEL_UP", reset) -- parecer 061: o upgrade muda com o nível
ns.FP.On("SKILLS", function() skillCache = nil; reset() end)
ns.FP.On("GEAR", function() evalCache = {} end) -- preço novo da AH
ns.FP.On("LEARNED", function() skillCache = nil; evalCache = {} end)

-- R6: o que buscar na AH: itens não presos verdes ou melhores e, com Enchanting, os materiais deles.
function EG.WantedPrices()
    local want, seen = {}, {}
    local skill = EG.EnchantingSkill()
    for _, b in ipairs(bagItems()) do
        local it = info(b.id)
        if it and it.quality >= 2 and not seen[b.id] then
            if not b.bound then seen[b.id] = true; want[#want + 1] = b.id end
            if skill > 0 and (it.classID == WEAPON or it.classID == ARMOR) then
                for _, m in ipairs(ns.Economy.MatIds(it, ns.DisenchantTable)) do -- R1a: mesmo sem preço
                    if not seen[m] then seen[m] = true; want[#want + 1] = m end
                end
            end
        end
    end
    return want
end

local function money(c) return Util.FormatMoney(math.floor(c or 0)) end

-- R7: linha do tooltip de item que está na bolsa.
local function tooltipLine(tt, id)
    if not (tt and id) or ns.FP.db.saleTooltip == false then return end
    local found, bound = false, false -- parecer 061: só item das bolsas (não o vestido nem o do banco)
    for _, b in ipairs(bagItems()) do if b.id == id then found, bound = true, b.bound; break end end
    if not found then return end
    local key = id .. (bound and "b" or "")
    local r = evalCache[key]
    if r == nil then r = EG.Evaluate(id, 1, bound) or false; evalCache[key] = r end
    r = r or nil
    if not r or r.use == "guardar" and r.vendor == 0 then return end
    local parts = {}
    if r.use ~= "vendedor" and r.vendor > 0 then parts[#parts + 1] = "vendedor " .. money(r.vendor) end
    if r.ah and r.use ~= "leilao" then parts[#parts + 1] = "leilão ~" .. money(r.ah) end
    if r.de and r.canDE and r.use ~= "desencantar" then parts[#parts + 1] = "desencantar ~" .. money(r.de) end
    local head = r.use == "guardar" and "Guardar" or ("Melhor: " .. LABEL[r.use] .. " " .. (r.use == "vendedor" and "" or "~") .. money(r.value))
    local text = head .. (#parts > 0 and (" (" .. table.concat(parts, " · ") .. ")") or "")
    tt:AddLine("|cFFB38CFF" .. text .. "|r")
    if r.tradeable and not r.ah then tt:AddLine("|cFF888888leilão: abra a AH para o addon ver o preço|r") end
end

local function hookTooltip()
    local P, E = _G.TooltipDataProcessor, _G.Enum
    if P and P.AddTooltipPostCall and E and E.TooltipDataType then
        P.AddTooltipPostCall(E.TooltipDataType.Item, function(tt, data)
            if tt == _G.GameTooltip or tt == _G.ItemRefTooltip then
                local ok, err = pcall(tooltipLine, tt, data and data.id)
                if not ok then ns.FP.Debug("venda: tooltip falhou: " .. tostring(err)) end
            end
        end)
    elseif _G.GameTooltip and _G.GameTooltip.HookScript then
        _G.GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            local ok, err = pcall(tooltipLine, tt, id)
            if not ok then ns.FP.Debug("venda: tooltip falhou: " .. tostring(err)) end
        end)
    end
end
ns.FP.On("READY", hookTooltip)

-- R8: /fp venda
function EG.Print()
    local groups, totals, order = {}, {}, { "leilao", "desencantar", "vendedor", "guardar" }
    local seen = {}
    for _, b in ipairs(bagItems()) do
        local key = b.id .. (b.bound and "b" or "")
        if not seen[key] then
            seen[key] = { id = b.id, count = 0, bound = b.bound }
        end
        seen[key].count = seen[key].count + b.count
    end
    for _, s in pairs(seen) do
        local r = EG.Evaluate(s.id, s.count, s.bound)
        if r and not (r.use == "guardar" and r.vendor == 0 and not r.ah) then
            groups[r.use] = groups[r.use] or {}
            table.insert(groups[r.use], r)
            totals[r.use] = (totals[r.use] or 0) + (r.value or 0)
        end
    end
    local any = false
    for _, use in ipairs(order) do
        local g = groups[use]
        if g then
            any = true
            ns.FP.Print(string.format("|cFFB38CFF%s|r (%d, ~%s):", LABEL[use], #g, money(totals[use])))
            for _, r in ipairs(g) do
                ns.FP.Print(string.format("  %s%s %s", r.item.link or r.item.name, r.count > 1 and (" x" .. r.count) or "",
                    use == "guardar" and "" or ("~" .. money(r.value))))
            end
        end
    end
    if not any then ns.FP.Print("nada nas bolsas para vender.") end
    if EG.EnchantingSkill() == 0 then ns.FP.Print("|cFF888888sem Enchanting: desencantar não entra na conta.|r") end
end

return EG
