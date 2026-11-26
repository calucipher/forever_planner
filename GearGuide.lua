-- GearGuide.lua: adaptador da aba Gear (spec 048). Junta os candidatos da QuestieDB e da API do
-- jogo (quest, cadeia, masmorra, vendedor, AH) em corrotina, fora de combate, e entrega para a
-- regra pura (Gear.Advice). Só ele lê a QuestieDB por Data.lua e a API de item.
local _, ns = ...
local GG = {}
ns.GearGuide = GG

-- Slot de equipamento (equipLoc do jogo) > nome na aba. Arma de duas mãos e de uma mão concorrem.
GG.SLOTS = {
    INVTYPE_HEAD = "Cabeça", INVTYPE_NECK = "Pescoço", INVTYPE_SHOULDER = "Ombros", INVTYPE_CLOAK = "Capa",
    INVTYPE_CHEST = "Peito", INVTYPE_ROBE = "Peito", INVTYPE_WRIST = "Pulsos", INVTYPE_HAND = "Mãos",
    INVTYPE_WAIST = "Cintura", INVTYPE_LEGS = "Pernas", INVTYPE_FEET = "Pés", INVTYPE_FINGER = "Anel",
    INVTYPE_TRINKET = "Berloque", INVTYPE_WEAPON = "Arma", INVTYPE_2HWEAPON = "Arma",
    INVTYPE_WEAPONMAINHAND = "Arma", INVTYPE_WEAPONOFFHAND = "Mão secundária", INVTYPE_SHIELD = "Mão secundária",
    INVTYPE_HOLDABLE = "Mão secundária", INVTYPE_RANGED = "À distância", INVTYPE_RANGEDRIGHT = "À distância",
    INVTYPE_THROWN = "À distância",
}
local WEAPON, ARMOR = 2, 4
local MAX_BOSS_NPCS = 2 -- item que cai de até 2 NPCs = loot de chefe (R1)
local CHAIN_DEPTH = 5
local BOE = 2 -- bindType do GetItemInfo

local state = { result = nil, dirty = true, loading = 0, retries = 0 }
function GG.Result() return state.result end

-- R1 (cadeia): primeira quest não feita da cadeia que leva a q, e quantos passos até q.
local function chainEntry(q, L, depth)
    local D = ns.Data
    depth = depth or 1
    if depth > CHAIN_DEPTH then return nil end
    local pres = {}
    for _, p in ipairs(D.Q.preQuestGroup(q) or {}) do pres[#pres + 1] = p end
    for _, p in ipairs(D.Q.preQuestSingle(q) or {}) do pres[#pres + 1] = p end
    for _, p in ipairs(pres) do
        if not D.IsCompleted(p) then
            if D.IsEligible(p, L) then return p, depth + 1 end
            local e, n = chainEntry(p, L, depth + 1)
            if e then return e, n end
        end
    end
    return nil
end

-- R1 (masmorra): áreas das masmorras cuja faixa da LFG cruza L..L+ahead.
local function dungeonAreas(L, ahead)
    local D, out = ns.Data, {}
    local byName = {}
    for _, d in ipairs(ns.DungeonGuide.List() or {}) do
        local a = d.best or d.act
        local lo, hi = a and (a.minLevelSuggestion or a.minLevel), a and a.maxLevelSuggestion
        if lo and hi and lo <= L + ahead and hi >= L then byName[(d.name or ""):lower()] = d end
    end
    for area, e in pairs(D.dungeons or {}) do
        local d = byName[tostring(e[1] or ""):lower()]
        if d then out[area] = d end
    end
    return out
end

local function bossDungeon(item, areas)
    local D = ns.Data
    local npcs = D.I.npcDrops(item)
    if not npcs or #npcs == 0 or #npcs > MAX_BOSS_NPCS then return nil end
    for _, npc in ipairs(npcs) do
        for area in pairs(D.N.spawns(npc) or {}) do
            if areas[area] then return areas[area], npc end
        end
    end
    return nil
end

local function friendlyVendor(item, faction)
    local D = ns.Data
    local tag = faction == "Horde" and "H" or "A"
    for _, npc in ipairs(D.I.vendors(item) or {}) do
        local f = D.N.friendlyToFaction(npc)
        if f == nil or tostring(f):find(tag) then return npc end
    end
    return nil
end

-- R1: nível exigido. A QuestieDB traz 0 em muitos itens (Crescent Staff, 21/11/2026): vale o do jogo
-- (item no cache) e, sem ele, itemLevel − 5 (a relação do Classic, estimativa).
-- Primeiro só a QuestieDB (barato); o nível do jogo entra depois, para o item que já tem fonte
-- (parecer reviews/047-049.md: GetItemInfo pede o item ao servidor).
local function reqLevel(item)
    local D = ns.Data
    local req = D.I.requiredLevel(item) or 0
    if req > 0 then return req, true end
    local il = D.I.itemLevel(item)
    return il and il > 0 and math.max(il - 5, 1) or nil, false
end
local function refineReq(item, req, exact)
    if exact then return req end
    local min = select(5, C_Item.GetItemInfo(item))
    return (min and min > 0) and min or req
end

-- Quest que o personagem pode fazer pela raça e pela classe (a cadeia de outra classe não serve).
local function forMe(q)
    local D, U = ns.Data, ns.Util
    return U.HasBit(D.Q.requiredRaces(q), D.raceMask) and U.HasBit(D.Q.requiredClasses(q), D.classMask)
end

-- R1, R2: candidatos. yield a cada 300 itens. Devolve a lista e quantos itens ainda carregam.
local function candidates(L, yield)
    local D, G = ns.Data, ns.Gear
    local ahead = G.AHEAD
    local areas = dungeonAreas(L, ahead)
    local faction = _G.UnitFactionGroup("player")
    local out, loading = {}, 0
    for i, item in ipairs(D.I.GetAllIds()) do
        local cls = D.I.class(item)
        local req, exact
        if cls == WEAPON or cls == ARMOR then req, exact = reqLevel(item) end
        if req and req <= L + ahead and req >= L - 10 then
            local sources = {}
            for _, q in ipairs(D.I.questRewards(item) or {}) do
                if D.IsEligible(q, L + ahead) then
                    sources[#sources + 1] = { source = "quest", quest = q }
                elseif not D.IsCompleted(q) and forMe(q) then
                    local entry, steps = chainEntry(q, L + ahead)
                    if entry then sources[#sources + 1] = { source = "cadeia", quest = q, entry = entry, steps = steps } end
                end
            end
            local d, boss = bossDungeon(item, areas)
            if d then sources[#sources + 1] = { source = "masmorra", dungeon = d, npc = boss } end
            local vendor = friendlyVendor(item, faction)
            if vendor then sources[#sources + 1] = { source = "vendedor", npc = vendor } end
            if #sources > 0 then req = refineReq(item, req, exact) end
            if #sources > 0 and req <= L + ahead then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(item)
                local slot = GG.SLOTS[equipLoc or ""]
                local delta, why = ns.Scoring.UpgradeDelta(item)
                if why == "loading" then loading = loading + 1 end
                if slot and delta and delta > 0 then
                    local bind = select(14, C_Item.GetItemInfo(item))
                    local boe = bind == BOE
                    for _, s in ipairs(sources) do
                        s.item, s.slot, s.delta, s.reqLevel, s.boe = item, slot, delta, req, boe
                        s.cost = G.Cost(s.source, s.steps)
                        out[#out + 1] = s
                    end
                    if boe then
                        out[#out + 1] = { source = "ah", item = item, slot = slot, delta = delta, reqLevel = req,
                            boe = true, cost = G.Cost("ah") }
                    end
                end
            end
        end
        if yield and i % 300 == 0 then yield() end
    end
    return out, loading
end

GG.Candidates = candidates -- para a integração com a QuestieDB (tests) e a pesquisa

-- R8: refaz a lista (em corrotina). Com itens ainda carregando, tenta de novo até 2 vezes.
function GG.Refresh(force)
    local D = ns.Data
    if not (D.Q and D.ready and D.I) then return end
    if not (force or state.dirty) then return end
    local L = UnitLevel("player")
    local started = ns.FP.RunCoroutine("gear", function(yield)
        local cands, loading = candidates(L, yield)
        return { level = L, advice = ns.Gear.Advice(cands, L), loading = loading }
    end, function(ok, res)
        if not ok then
            ns.FP.Debug("gear: falhou: " .. tostring(res))
            state.result = { level = L, advice = {}, error = tostring(res) }
        else
            state.result = res
            state.dirty = false
            if res.loading > 0 and state.retries < 2 then
                state.retries = state.retries + 1
                C_Timer.After(3, function() GG.Refresh(true) end)
            else
                state.retries = 0
            end
        end
        ns.FP.Fire("GEAR")
    end)
    if started then state.dirty = false end
end

local function dirty() state.dirty = true; state.retries = 0 end
ns.FP.On("LEVEL_UP", dirty)
ns.FP.On("EQUIPMENT", dirty)
ns.FP.On("QUEST_TURNED_IN", dirty)

-- R4: seta até a fonte.
function GG.Go(a)
    local D = ns.Data
    if a.source == "quest" then ns.Planner.Follow(a.quest)
    elseif a.source == "cadeia" then ns.Planner.Follow(a.entry)
    elseif a.source == "masmorra" then ns.DungeonGuide.GoEntrance(a.dungeon)
    else
        local pts = a.source == "vendedor" and D.NpcPoints(a.npc)
            or D.NpcsBySubName("Auctioneer", (_G.UnitFactionGroup("player")))
        local from = ns.Planner.PlayerPoint()
        local p = from and ns.Planner.Nearest(from, pts) or pts[1]
        if not p then ns.FP.Print("não achei onde fica: " .. (a.source == "ah" and "leiloeiro" or "vendedor")); return end
        ns.Gps.SetTarget(p.mapID, p.x, p.y, (a.source == "ah" and "Leiloeiro" or "Vendedor") .. ": " .. tostring(GG.ItemName(a.item)))
    end
end

function GG.ItemName(item)
    return C_Item.GetItemInfo(item) or ns.Data.I.name(item) or ("item " .. item)
end

-- R4: "de onde vem" em texto curto.
function GG.SourceText(a)
    local D = ns.Data
    if a.source == "quest" then return "quest " .. (D.Q.name(a.quest) or a.quest)
    elseif a.source == "cadeia" then
        return string.format("cadeia: %s → %s (%d passos)", D.Q.name(a.entry) or a.entry, D.Q.name(a.quest) or a.quest, a.steps or 1)
    elseif a.source == "masmorra" then
        return "masmorra " .. tostring(a.dungeon and a.dungeon.name) .. (a.npc and (" (" .. tostring(D.N.name(a.npc)) .. ")") or "")
    elseif a.source == "vendedor" then return "vendedor " .. tostring(D.N.name(a.npc))
    else return "AH (BoE)" end
end

-- R7: no chat.
function GG.Print()
    local r = state.result
    if not r then ns.FP.Print("gear: calculando; tente de novo em alguns segundos."); GG.Refresh(true); return end
    ns.FP.Print(string.format("gear no nível %d (estimativa, até %d níveis à frente):", r.level, ns.Gear.AHEAD))
    if #r.advice == 0 then ns.FP.Print("  nenhum upgrade achado nas quests, cadeias, masmorras e vendedores.") end
    for _, a in ipairs(r.advice) do
        ns.FP.Print(string.format("  %s: %s +%.1f · %s%s", a.slot, GG.ItemName(a.item), a.delta, GG.SourceText(a),
            a.later and (" · no " .. a.later) or ""))
    end
end

------------------------------------------------------------------------------------------
-- R5: preço na casa de leilões (API do leilão moderno; a conferir no jogo)
------------------------------------------------------------------------------------------
local AH_MAX, AH_GAP = 20, 1.5 -- spec 061, R6: até 20 buscas (gear e venda)
local queue, waiting = {}, nil

local function prices() ns.FP.db.gearPrices = ns.FP.db.gearPrices or {}; return ns.FP.db.gearPrices end

local function nextSearch()
    local A = _G.C_AuctionHouse
    local item = table.remove(queue, 1)
    if not (A and item) then waiting = nil; return end
    local ok, err = pcall(function()
        waiting = item
        A.SendSearchQuery(A.MakeItemKey(item), {}, false)
    end)
    if not ok then ns.FP.Debug("gear: busca na AH falhou: " .. tostring(err)); waiting = nil end
    C_Timer.After(AH_GAP, nextSearch)
end

function GG.AuctionOpened()
    if not _G.C_AuctionHouse then return end
    local r = state.result
    queue = {}
    local seen = {}
    for _, a in ipairs(r and r.advice or {}) do
        for _, c in ipairs({ a, a.alts[1], a.alts[2] }) do
            if c and c.boe and not seen[c.item] and #queue < AH_MAX then seen[c.item] = true; queue[#queue + 1] = c.item end
        end
    end
    -- spec 061, R6: itens da bolsa que dá para leiloar e materiais de desencanto
    local ok, more = pcall(function() return ns.EconomyGuide and ns.EconomyGuide.WantedPrices() or {} end)
    for _, id in ipairs(ok and more or {}) do
        if not seen[id] and #queue < AH_MAX then seen[id] = true; queue[#queue + 1] = id end
    end
    if #queue > 0 then nextSearch() end
end

function GG.AuctionResults(itemKey)
    local A = _G.C_AuctionHouse
    local item = type(itemKey) == "table" and itemKey.itemID or waiting
    if not (A and item) then return end
    local ok, err = pcall(function()
        local n = A.GetNumItemSearchResults(A.MakeItemKey(item)) or 0
        local best
        for i = 1, n do
            local info = A.GetItemSearchResultInfo(A.MakeItemKey(item), i)
            local buy = info and info.buyoutAmount
            -- spec 061, R6: preço por unidade (o leilão pode ser uma pilha)
            if buy and buy > 0 then buy = buy / math.max(info.quantity or 1, 1) end
            if buy and buy > 0 and (not best or buy < best) then best = buy end
        end
        if best then prices()[item] = { copper = best, at = _G.time() } end
    end)
    if not ok then ns.FP.Debug("gear: preço da AH falhou: " .. tostring(err)) end
    ns.FP.Fire("GEAR")
end

-- Spec 061, R6: material de desencanto é commodity (base 12.x): resultado e preço por unidade próprios.
function GG.CommodityResults(itemID)
    local A = _G.C_AuctionHouse
    local item = tonumber(itemID) or waiting
    if not (A and item and A.GetNumCommoditySearchResults) then return end
    local ok, err = pcall(function()
        local best
        for i = 1, (A.GetNumCommoditySearchResults(item) or 0) do
            local info = A.GetCommoditySearchResultInfo(item, i)
            local unit = info and info.unitPrice
            if unit and unit > 0 and (not best or unit < best) then best = unit end
        end
        if best then prices()[item] = { copper = best, at = _G.time() } end
    end)
    if not ok then ns.FP.Debug("venda: preço de commodity falhou: " .. tostring(err)) end
    ns.FP.Fire("GEAR")
end

function GG.Price(item) return prices()[item] end

return GG
