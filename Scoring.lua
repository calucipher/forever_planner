-- Scoring.lua: score de item (estilo Pawn) e delta de upgrade contra o equipado.
local _, ns = ...
local Util = ns.Util
local Scoring = {}
ns.Scoring = Scoring

-- Chaves de GetItemStats (independem do idioma do client)
Scoring.statKeys = {
    ITEM_MOD_SPELL_POWER_SHORT = "sp",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
    ITEM_MOD_SHADOW_DAMAGE_SHORT = "shadow",
    ITEM_MOD_FIRE_DAMAGE_SHORT = "fire",
    ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
    ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit",
    ITEM_MOD_HASTE_RATING_SHORT = "haste",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "haste",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}

-- Dano de escola às vezes só aparece no texto do tooltip. enUS confirmado no Classic;
-- ptBR é melhor esforço: confira com /fp stats <link> e ajuste se precisar.
Scoring.tooltipPatterns = {
    { "Increases damage done by Shadow spells and effects by up to (%d+)", "shadow" },
    { "Increases damage done by Fire spells and effects by up to (%d+)", "fire" },
    { "%+(%d+) Shadow Spell Damage", "shadow" },
    { "%+(%d+) Fire Spell Damage", "fire" },
    { "dano causado por feitiços e efeitos de Sombra em até (%d+)", "shadow" },
    { "dano causado por feitiços e efeitos de Fogo em até (%d+)", "fire" },
    { "%+(%d+) de Dano de Feitiços de Sombra", "shadow" },
    { "%+(%d+) de Dano de Feitiços de Fogo", "fire" },
}

-- Warlock: tecido + misc (anel, colar, trinket, off-hand "held"); cajado, adaga,
-- espada 1H e varinha. classID 4 = armadura, 2 = arma.
Scoring.usable = {
    [4] = { [0] = true, [1] = true },
    [2] = { [7] = true, [10] = true, [15] = true, [19] = true },
}

-- equipLoc -> slots de inventário a comparar
Scoring.slotsFor = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16, 17, combine = true },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
}

function Scoring.IsUsable(classID, subclassID, equipLoc)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return false end
    local c = Scoring.usable[classID]
    return c ~= nil and c[subclassID] == true and Scoring.slotsFor[equipLoc] ~= nil
end

-- Função pura: stats normalizados {sp=, sta=, ...} x pesos
function Scoring.ScoreStats(stats, weights, isRangedSlot)
    local total = 0
    for k, v in pairs(stats or {}) do
        if k == "dps" then
            if isRangedSlot then total = total + v * (weights.dps or 0) end
        else
            total = total + v * (weights[k] or 0)
        end
    end
    return total
end

-- Função pura: maior ganho entre os slots candidatos.
-- equipped: slot -> score (nil = vazio = 0). Para 2H soma MH+OH.
function Scoring.Delta(newScore, slots, equipped)
    if slots.combine then
        local cur = (equipped[slots[1]] or 0) + (equipped[slots[2]] or 0)
        return newScore - cur
    end
    local worst
    for _, s in ipairs(slots) do
        local cur = equipped[s] or 0
        if worst == nil or cur < worst then worst = cur end
    end
    return newScore - (worst or 0)
end

------------------------------------------------------------------------------------------
-- Parte que depende do jogo
------------------------------------------------------------------------------------------
local statCache, equippedCache = {}, nil

function Scoring.ClearCache() statCache = {}; equippedCache = nil end
function Scoring.ClearEquippedCache() equippedCache = nil end

local function weights()
    local db = ns.FP.db
    return ns.Weights.Get(db.preset, db.customWeights, UnitLevel("player"))
end

local function addTooltipStats(itemRef, out)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
    local data = type(itemRef) == "number" and C_TooltipInfo.GetItemByID(itemRef)
        or (C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(itemRef))
    if not data or not data.lines then return end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not Util.IsSecret(text) then
            for _, p in ipairs(Scoring.tooltipPatterns) do
                local n = tonumber(text:match(p[1]))
                if n then out[p[2]] = math.max(out[p[2]] or 0, n) end
            end
        end
    end
end

-- Stats normalizados de um item (ou nil se o client ainda não carregou o item)
function Scoring.GetStats(itemRef)
    local cached = statCache[itemRef]
    if cached then return cached end
    local link = itemRef
    if type(itemRef) == "number" then
        local _, l = C_Item.GetItemInfo(itemRef)
        if not l then
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemRef) end
            return nil
        end
        link = l
    end
    local raw = (C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link)) or {}
    local out = {}
    for key, v in pairs(raw) do
        local stat = Scoring.statKeys[key]
        local n = Util.Num(v)
        if stat and n then out[stat] = (out[stat] or 0) + n end
    end
    addTooltipStats(itemRef, out)
    statCache[itemRef] = out
    return out
end

function Scoring.ItemScore(itemRef, isRangedSlot)
    local stats = Scoring.GetStats(itemRef)
    if not stats then return nil end
    return Scoring.ScoreStats(stats, weights(), isRangedSlot)
end

local function equippedScores()
    if equippedCache then return equippedCache end
    local t = {}
    for slot = 1, 18 do
        local link = GetInventoryItemLink("player", slot)
        if link then t[slot] = Scoring.ItemScore(link, slot == 18) or 0 end
    end
    equippedCache = t
    return t
end

-- Delta de upgrade de um item de recompensa. nil = não carregado / não usável.
function Scoring.UpgradeDelta(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not Scoring.IsUsable(classID, subclassID, equipLoc) then return nil, "unusable" end
    local slots = Scoring.slotsFor[equipLoc]
    local score = Scoring.ItemScore(itemID, slots[1] == 18)
    if not score then return nil, "loading" end
    return Scoring.Delta(score, slots, equippedScores()), equipLoc
end

-- Melhor recompensa de uma lista (choices + fixas)
function Scoring.BestReward(itemIDs)
    local bestID, bestDelta, loading = nil, nil, false
    for _, id in ipairs(itemIDs or {}) do
        local d, why = Scoring.UpgradeDelta(id)
        if d and (bestDelta == nil or d > bestDelta) then bestID, bestDelta = id, d end
        if why == "loading" then loading = true end
    end
    return bestID, bestDelta, loading
end

function Scoring.Debug(ref)
    local id = tonumber(ref) or (ref and tonumber(ref:match("item:(%d+)")))
    if not id then ns.FP.Print("uso: /fp stats <link ou itemID>"); return end
    local _, link = C_Item.GetItemInfo(id)
    local raw = link and ((C_Item.GetItemStats and C_Item.GetItemStats(link)) or {}) or {}
    for k, v in pairs(raw) do
        ns.FP.Print(k, "=", tostring(v), Scoring.statKeys[k] and "" or "|cFFFFAA00(sem mapeamento)|r")
    end
    statCache[id] = nil
    local d = Scoring.UpgradeDelta(id)
    ns.FP.Print("score:", tostring(Scoring.ItemScore(id)), "delta:", tostring(d))
end

return Scoring
