-- ClassGuide.lua: adaptador dos marcos da classe (spec 011). Liga a QuestieDB (Data), o
-- conteúdo (Content/Classes) e as regras puras (Milestones) aos avisos no chat e ao GPS.
local _, ns = ...
local ClassGuide = {}
ns.ClassGuide = ClassGuide

local M = ns.Milestones

local function classDef()
    local _, class = UnitClass("player")
    return ns.Classes and ns.Classes[class]
end

local function isKnown(spell)
    if _G.IsPlayerSpell then return _G.IsPlayerSpell(spell) == true end
    return _G.IsSpellKnown ~= nil and _G.IsSpellKnown(spell) == true
end

local function dataReady() return ns.Data.Q ~= nil and ns.Data.ready end

-- R2: lista visível, sem versões repetidas (fica a de quest giver mais perto).
function ClassGuide.List(level)
    if not dataReady() then return {} end
    level = level or UnitLevel("player")
    local player = ns.Planner.PlayerPoint()
    local visible = M.VisibleClassList(ns.Data.ClassQuests(level), level)
    return M.DedupeByName(visible, function(e)
        return player and e.starter and ns.Planner.Distance(player, e.starter) or nil
    end)
end

-- R3
function ClassGuide.Best()
    if not dataReady() then return nil end
    local zone = ns.Guide.ZoneMap(C_Map.GetBestMapForUnit("player"))
    return M.Best(ClassGuide.List(), zone)
end

function ClassGuide.Follow()
    ns.FP.AfterCombat("followClass", function()
        local e = ClassGuide.Best()
        if not e then ns.FP.Print("nenhuma quest de classe disponível agora."); return end
        ns.FP.Print(string.format("seguindo quest de classe: %s (%s) — %s", e.name, e.zone, e.status))
        ns.FP.Debug("classe: seguir " .. e.q)
        ns.Planner.Follow(e.q)
    end)
end

function ClassGuide.PrintList()
    local list = ClassGuide.List()
    if #list == 0 then ns.FP.Print("nenhuma quest de classe para este personagem (ou dados ainda carregando).") end
    for _, e in ipairs(list) do
        ns.FP.Print(string.format("[%d] %s (%s) — %s", e.level, e.name, e.zone, e.status))
    end
end

-- Spec 016: arma habilitada na janela Armas (padrão: todas).
function ClassGuide.IsEnabled(key)
    local off = ns.FP.db and ns.FP.db.weaponsOff
    return not (off and off[key])
end

function ClassGuide.SetEnabled(key, on)
    ns.FP.db.weaponsOff = ns.FP.db.weaponsOff or {}
    ns.FP.db.weaponsOff[key] = (not on) or nil
    ns.Guide.Invalidate()
    ns.FP.Fire("CHANGED")
end

-- R6: nome da perícia que falta para a arma (itemID), ou nil. 2º retorno: a arma está habilitada
-- (desabilitada zera o delta, mas não gera rótulo nem aviso).
function ClassGuide.MissingSkillFor(itemID)
    if not itemID or not C_Item.GetItemInfoInstant then return nil end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    local spell = M.WeaponSkillSpell(classID, subclassID)
    local name = M.MissingSkillName(classDef(), spell, isKnown)
    local w = name and M.WeaponBySpell(classDef(), spell)
    return name, w ~= nil and ClassGuide.IsEnabled(w.key)
end

-- Spec 016: linhas da janela Armas.
function ClassGuide.WeaponRows()
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    local rows = {}
    for _, w in ipairs(classDef() and classDef().weapons or {}) do
        rows[#rows + 1] = { key = w.key, name = w.name, known = isKnown(w.spell), enabled = ClassGuide.IsEnabled(w.key),
            trainers = (w.trainers and w.trainers[faction]) or {} }
    end
    return rows
end

-- Spec 012: o item é arma? (classe 2)
function ClassGuide.ItemClass(itemID)
    if not itemID or not C_Item.GetItemInfoInstant then return nil end
    return (select(6, C_Item.GetItemInfoInstant(itemID)))
end

-- Spec 011, A11: relatório para o /fp diag. Inclui as linhas de perícia do jogo como 2ª fonte.
function ClassGuide.DiagLines()
    local out = M.SkillReport(classDef(), isKnown)
    local num, info = _G.GetNumSkillLines, _G.GetSkillLineInfo
    if num and info then
        local names = {}
        for i = 1, num() do
            local name, isHeader = info(i)
            if name and not isHeader then names[#names + 1] = name end
        end
        out[#out + 1] = "linhas de perícia do jogo: " .. (#names > 0 and table.concat(names, ", ") or "nenhuma")
    else
        out[#out + 1] = "linhas de perícia do jogo: API ausente"
    end
    return out
end

-- Spec 016, R4/R5: aponta o GPS para o treinador da arma no mesmo continente; senão, só avisa onde fica.
function ClassGuide.FollowTrainer(key)
    local row
    for _, r in ipairs(ClassGuide.WeaponRows()) do if r.key == key then row = r end end
    if not row then return end
    local player = ns.Planner.PlayerPoint()
    local options = {}
    for _, trainer in ipairs(row.trainers) do
        local p, d = ns.Planner.Nearest(player, ns.Data.NpcPointsByName(M.TrainerNpcName(trainer)))
        if p then
            options[#options + 1] = { name = M.TrainerNpcName(trainer), place = M.TrainerPlace(trainer), point = p, dist = d,
                same = ns.Planner.SameContinent(player, p) == true }
        end
    end
    local best = M.PickTrainer(options)
    if not best then ns.FP.Print("não achei o Weapon Master de " .. row.name .. " na QuestieDB."); return end
    if not best.same then
        local places = {}
        for _, o in ipairs(options) do places[#places + 1] = o.name .. " (" .. o.place .. ")" end
        local gates = {}
        local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
        for _, g in ipairs(ns.Data.TransportPoints(faction)) do
            gates[#gates + 1] = { name = g.name, point = g, dist = ns.Planner.Distance(player, g),
                same = ns.Planner.SameContinent(player, g) == true, kind = g.kind, dest = g.dest, arrival = g.arrival }
        end
        -- Spec 020, R1: o transporte cuja chegada fica mais perto do treinador, não só o mais perto de você
        local gate = M.PickGate(gates, options, ns.Planner.Distance)
        if gate then
            ns.FP.Print(string.format("|cFFFFAA00%s: o treinador fica em outro continente (%s).|r Seta no %s %s, para %s; ao chegar do outro lado, clique em 'Ir ao treinador' de novo.",
                row.name, table.concat(places, " ou "), gate.kind, gate.name, gate.dest))
            ns.Gps.SetTarget(gate.point.mapID, gate.point.x, gate.point.y,
                "Ir ao treinador de " .. row.name .. ": " .. gate.kind .. " " .. gate.name .. " (para " .. gate.dest .. ")")
        else
            ns.FP.Print(M.NoGateText(row.name, table.concat(places, " ou "), ns.Transports ~= nil))
        end
        return
    end
    ns.FP.Print(string.format("seguindo: treinar %s com %s", row.name, best.name))
    ns.Gps.SetTarget(best.point.mapID, best.point.x, best.point.y, "Treinar " .. row.name .. ": " .. best.name)
end

-- R5: aviso das perícias que faltam.
function ClassGuide.WarnWeapons()
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    for _, w in ipairs(M.MissingWeapons(classDef(), faction, isKnown, ClassGuide.IsEnabled)) do
        local where = #w.trainers > 0 and table.concat(w.trainers, " ou ") or "Weapon Master da sua facção"
        ns.FP.Print(string.format("|cFFFFD100você ainda não treinou %s.|r Weapon Master: %s. Botão 'Armas' da aba Guia aponta o caminho.", w.name, where))
    end
end

-- Spec 017, R2: feitiços da classe que o jogador ainda não aprendeu (trainer ou quest de classe).
function ClassGuide.MissingSpells(level)
    local _, class = UnitClass("player")
    local list = ns.Spells and ns.Spells[class]
    if not list then return nil end
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    local mine = {}
    for _, s in ipairs(list) do
        if M.SpellAllowed(s, faction, ns.Data.raceMask, ns.Util.HasBit) then mine[#mine + 1] = s end -- spec 017, R6
    end
    return M.MissingSpells(mine, level or UnitLevel("player"), isKnown)
end

-- onlyLevel: no level-up mostra só os do nível novo; no login (nil) mostra tudo que falta.
function ClassGuide.WarnSpells(level, onlyLevel)
    local missing = ClassGuide.MissingSpells(level)
    if not missing then return false end
    if onlyLevel then
        local fresh = {}
        for _, s in ipairs(missing) do if s.lvl == onlyLevel then fresh[#fresh + 1] = s end end
        missing = fresh
    end
    if #missing == 0 then return true end
    ns.FP.Print("|cFFFFD100feitiços novos para aprender|r (trainer ou quest de classe): " .. M.FormatSpells(missing, 8) .. ".")
    return true
end

-- Spec 017, R3: marco cumprido (o jogador já conhece o feitiço)?
function ClassGuide.IsMilestoneDone(m) return M.IsDone(m, isKnown) end

-- R7: no login, avisa os marcos dos últimos níveis (instalou o addon depois de passar por eles).
function ClassGuide.WarnMissedMilestones()
    for _, m in ipairs(M.Missed(classDef(), UnitLevel("player"), nil, isKnown)) do
        ns.FP.Print(string.format("|cFFB38CFFmarco do nível %d (atrasado):|r %s", m.lvl, m.text))
    end
end

-- R7: lista os marcos recentes que passaram e os próximos.
function ClassGuide.PrintMilestones()
    local level = UnitLevel("player")
    for _, m in ipairs(M.Missed(classDef(), level, nil, isKnown)) do
        ns.FP.Print(string.format("[%d] %s |cFF888888(já passou)|r", m.lvl, m.text))
    end
    local list = M.Upcoming(classDef(), level, 6, isKnown)
    if #list == 0 then ns.FP.Print("sem marcos cadastrados para esta classe.") end
    for _, m in ipairs(list) do ns.FP.Print(string.format("[%d] %s", m.lvl, m.text)) end
end

-- R4, R5, R7, R8: avisos ao subir de nível. O nível vem do evento (UnitLevel pode atrasar).
local function onLevelUp(level)
    level = tonumber(level) or UnitLevel("player")
    local def = classDef()
    for _, m in ipairs(M.ForLevel(def, level, isKnown)) do
        ns.FP.Print("|cFFB38CFFmarco do nível " .. level .. ":|r " .. m.text)
    end
    if not ClassGuide.WarnSpells(level, level) and M.TrainerDue(def, level) then
        ns.FP.Print("nível " .. level .. ": passe no trainer da classe, deve ter feitiço novo.")
    end
    for _, e in ipairs(M.UnlockedNow(ClassGuide.List(level), level)) do
        ns.FP.Print(string.format("|cFFB38CFFquest de classe liberada:|r %s (%s). /fp classe para seguir.", e.name, e.zone))
    end
    ClassGuide.WarnWeapons()
end

local warnedThisSession = false
ns.FP.On("LEVEL_UP", function(level) ns.FP.AfterCombat("classLevelUp", function() onLevelUp(level) end) end)
-- R5: no login, uma vez; espera os feitiços do personagem carregarem.
ns.FP.On("READY", function()
    if warnedThisSession then return end
    warnedThisSession = true
    C_Timer.After(5, function()
        ns.FP.AfterCombat("classWeapons", function()
            ClassGuide.WarnWeapons()
            ClassGuide.WarnSpells()
            ClassGuide.WarnMissedMilestones()
        end)
    end)
end)

return ClassGuide
