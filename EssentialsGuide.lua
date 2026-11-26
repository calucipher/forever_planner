-- EssentialsGuide.lua: adaptador da spec 062 (Essenciais). Junta os fatos do personagem para a regra
-- pura (Essentials.Build) e leva a seta a cada item.
local _, ns = ...
local ESG = {}
ns.EssentialsGuide = ESG

local CONSUMABLE, FOOD_DRINK, PROJECTILE = 0, 5, 6
local FIRST_AID = 129
local CLASS_MOUNT = { WARLOCK = 5784, PALADIN = 13819 } -- Felsteed, Summon Warhorse

local function itemInfo(id)
    local I = _G.C_Item and _G.C_Item.GetItemInfo or _G.GetItemInfo
    if not I then return nil end
    local name, _, _, _, minLevel, _, _, _, _, _, _, classID, subclassID = I(id)
    if not name then return nil end
    return { minLevel = minLevel or 0, classID = classID, subclassID = subclassID }
end

-- Bolsas: espaços vazios (slots 1–4 sem bolsa), a menor bolsa, a melhor comida/bebida e a munição.
local function bagFacts()
    local C = _G.C_Container
    local f = { emptyBagSlots = 0, minBag = 99, foodLevel = nil, ammo = 0 }
    if not (C and C.GetContainerNumSlots) then return f end
    for bag = 1, 4 do
        local n = C.GetContainerNumSlots(bag) or 0
        local _, family = 0, 0
        if C.GetContainerNumFreeSlots then _, family = C.GetContainerNumFreeSlots(bag) end
        -- R1a: aljava, bolsa de munição e de alma (família não zero) não contam como bolsa pequena
        if n == 0 then f.emptyBagSlots = f.emptyBagSlots + 1 elseif (family or 0) == 0 and n < f.minBag then f.minBag = n end
    end
    for bag = 0, 4 do
        for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
            local d = C.GetContainerItemInfo(bag, slot)
            local it = d and d.itemID and itemInfo(d.itemID)
            if it then
                if it.classID == CONSUMABLE and it.subclassID == FOOD_DRINK and (not f.foodLevel or it.minLevel > f.foodLevel) then
                    f.foodLevel = it.minLevel
                elseif it.classID == PROJECTILE then
                    f.ammo = f.ammo + (d.stackCount or 1)
                end
            end
        end
    end
    return f
end

local function skillRank(line, names)
    if _G.GetProfessions and _G.GetProfessionInfo then
        for _, idx in ipairs({ _G.GetProfessions() }) do
            local _, _, rank, _, _, _, l = _G.GetProfessionInfo(idx)
            if l == line then return rank or 0 end
        end
    end
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        for i = 1, _G.GetNumSkillLines() do
            local name, _, _, rank = _G.GetSkillLineInfo(i)
            if names[name] then return rank or 0 end
        end
    end
    return 0
end

local function isKnown(id) return _G.IsPlayerSpell and _G.IsPlayerSpell(id) == true end

local function zoneName(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name
end

-- R1: os fatos. Cada parte em pcall: uma falha não esconde a lista inteira.
function ESG.Facts()
    local L = UnitLevel("player")
    local _, class = UnitClass("player")
    local f = { level = L, class = class, money = _G.GetMoney and _G.GetMoney() or 0, weaponsMissing = {}, flightRed = {} }
    local function try(name, fn)
        local ok, err = pcall(fn)
        if not ok then ns.FP.Debug("essenciais: " .. name .. " falhou: " .. tostring(err)) end
    end
    try("bolsas", function() for k, v in pairs(bagFacts()) do f[k] = v end end)
    try("quests de bolsa", function()
        local n = 0
        for _, b in ipairs(ns.Data.ready and ns.Data.BagQuests(L) or {}) do if not b.skipped then n = n + 1 end end
        f.bagQuests = n
    end)
    try("treino", function()
        local miss = ns.ClassGuide.MissingSpells(L) or {}
        f.spellsMissing, f.newSpells = #miss, 0
        for _, s in ipairs(miss) do if s.new then f.newSpells = f.newSpells + 1 end end
    end)
    try("ranks", function() f.oldRanks = #ns.ClassGuide.OldRanks() end)
    try("armas", function() f.weaponsMissing = ns.ClassGuide.MissingWeaponNames() end)
    try("classe", function()
        local best = ns.ClassGuide.Best()
        f.classQuest = best and string.format("%s (%s)", best.name, best.zone) or nil
        if not best then -- R1a: a próxima acima do nível
            for _, e in ipairs(ns.ClassGuide.List(L + 10)) do
                if (e.level or 0) > L and (not f.classNext or e.level < f.classNext) then f.classNext = e.level end
            end
        end
    end)
    try("montaria", function()
        f.mountKnown = (CLASS_MOUNT[class] and isKnown(CLASS_MOUNT[class]))
            or skillRank(762, { Riding = true, Montaria = true }) > 0
    end)
    try("pedra", function()
        local bind = ns.FP.db.bind
        local here = ns.Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
        local name = _G.GetBindLocation and _G.GetBindLocation()
        if bind and bind.mapID and name and bind.name == name then -- parecer: o gravado tem de ser o atual
            local same = ns.Guide.ZoneMap(bind.mapID) == here
            f.bindZone = name
            f.zone = same and name or zoneName(here)
        end
    end)
    try("voo", function()
        local here = ns.Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
        local zone = here and ns.Guide.MapZone(here)
        for _, p in ipairs(ns.Planner.FlightNodesWithZone(here, ns.Guide.MapZone)) do
            if p.known == false and p.zone == zone then f.flightRed[#f.flightRed + 1] = p.name end
        end
    end)
    try("gear", function()
        local r = ns.GearGuide.Result()
        for _, a in ipairs(r and r.advice or {}) do
            if (a.reqLevel or 99) <= L and a.source ~= "masmorra" then f.gearNow = ns.GearGuide.ItemName(a.item); break end
        end
    end)
    try("socorros", function()
        f.firstAid = skillRank(FIRST_AID, { ["First Aid"] = true, ["Primeiros Socorros"] = true })
        if f.firstAid == 0 then -- R1a: a linha de perícia pode estar recolhida; os feitiços dizem
            for _, id in ipairs({ 3273, 3274, 7924, 10846 }) do if isKnown(id) then f.firstAid = 1; break end end
        end
    end)
    return f
end

-- Parecer 062: os fatos custam (bolsas, barra, voos); cache até algo mudar ou 30 s.
local cache, cacheAt = nil, 0
local function invalidate() cache = nil end
for _, ev in ipairs({ "BAGS", "SPELLS", "LEARNED", "LEVEL_UP", "ZONE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "EQUIPMENT", "GEAR",
    "TAXI_KNOWN", "BIND", "DATA_READY" }) do
    ns.FP.On(ev, invalidate)
end
function ESG.List()
    local now = _G.GetTime and _G.GetTime() or 0
    if not cache or now - cacheAt > 30 then cache, cacheAt = ns.Essentials.Build(ESG.Facts()), now end
    return cache
end

local function goNearest(points, title)
    local from = ns.Planner.PlayerPoint()
    local p = from and ns.Planner.Nearest(from, points) or (points or {})[1]
    if not p then ns.FP.Print("não achei onde fica: " .. title); return end
    ns.Gps.SetTarget(p.mapID, p.x, p.y, title .. ": " .. tostring(p.name or ""))
end
local function bySub(sub) return ns.Data.NpcsBySubName(sub, (_G.UnitFactionGroup("player"))) end

-- R4: o clique numa linha.
function ESG.Go(key)
    local _, class = UnitClass("player")
    if key == "treino" then ns.ClassGuide.FollowClassTrainer()
    elseif key == "ranks" then ns.ClassGuide.Ranks()
    elseif key == "armas" then ns.QuickMenu.ShowWeapons()
    elseif key == "classe" then ns.ClassGuide.Follow()
    elseif key == "montaria" then
        -- parecer 062: montaria de classe leva ao treinador da classe mesmo sem feitiço novo
        if CLASS_MOUNT[class] then ns.ClassGuide.FollowClassTrainer(true)
        else goNearest(bySub("Riding Trainer"), "Treinador de montaria") end
    elseif key == "pedra" or key == "comida" then goNearest(ns.Data.Innkeepers((_G.UnitFactionGroup("player"))), "Estalajadeiro")
    elseif key == "voo" then
        local here = ns.Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
        local zone = here and ns.Guide.MapZone(here)
        local red = {}
        for _, p in ipairs(ns.Planner.FlightNodesWithZone(here, ns.Guide.MapZone)) do
            if p.known == false and p.zone == zone then red[#red + 1] = { mapID = p.mapID, x = p.x, y = p.y, name = p.name } end
        end
        goNearest(red, "Abrir ponto de voo")
    elseif key == "gear" then if ns.UI and ns.UI.Select then ns.UI.Select("gear") end
    elseif key == "municao" then
        local pts = {}
        for _, sub in ipairs({ "Ammunition Vendor", "Bowyer", "Gunsmith", "Arrows & Bullets" }) do
            for _, p in ipairs(bySub(sub)) do pts[#pts + 1] = p end
        end
        goNearest(pts, "Munição")
    elseif key == "socorros" then goNearest(bySub("First Aid Trainer"), "Treinador de Primeiros Socorros")
    elseif key == "bolsas" then ns.Guide.FollowBag()
    end
end

-- R3: "Seguir este hub" vai ao primeiro pendente.
function ESG.FollowFirst()
    for _, it in ipairs(ESG.List()) do
        if it.status == "pendente" then ESG.Go(it.key); return end
    end
    ns.FP.Print("nenhum essencial pendente.")
end

-- R6: /fp essenciais
function ESG.Print()
    local list = ESG.List()
    for _, it in ipairs(list) do
        local color = ({ pendente = "FFFF6666", conferir = "FFB0B0FF", depois = "FFFFD14D" })[it.status] or "FF73E65A"
        ns.FP.Print(string.format("|c%s%s|r %s%s", color, it.status, it.label, it.detail ~= "" and (" — " .. it.detail) or ""))
    end
end

-- R5: no level-up, os pendentes.
ns.FP.On("LEVEL_UP", function()
    ns.FP.AfterCombat("essentialsLevel", function()
        C_Timer.After(3, function()
            local ok, list = pcall(ESG.List)
            if not ok then return end
            local names = {}
            for _, it in ipairs(list) do if it.status == "pendente" then names[#names + 1] = it.label end end
            if #names > 0 then
                ns.FP.Print(string.format("|cFFFFD100%d essenciais pendentes:|r %s (aba Guia > Essenciais)", #names, table.concat(names, ", ")))
            end
        end)
    end)
end)

return ESG
