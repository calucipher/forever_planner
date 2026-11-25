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
    ns.FP.Print("|cFFFFD100feitiços novos para aprender|r (trainer ou quest de classe): " .. M.FormatSpells(missing, 8)
        .. ". /fp treinar leva ao treinador mais perto.") -- spec 051, R6
    return true
end

------------------------------------------------------------------------------------------
-- Spec 055: custo do treino, "Treinar tudo" e rank velho na barra
------------------------------------------------------------------------------------------
local function trainerServices()
    local out = {}
    local num, info, cost = _G.GetNumTrainerServices, _G.GetTrainerServiceInfo, _G.GetTrainerServiceCost
    if not (num and info and cost) then return out end
    for i = 1, (num() or 0) do
        local name, _, category = info(i)
        out[#out + 1] = { index = i, name = name, available = category == "available", cost = (cost(i)) or 0 }
    end
    return out
end
local function money() return _G.GetMoney and _G.GetMoney() or 0 end

-- R2: total ao abrir a janela.
ns.FP.On("TRAINER_SHOW", function()
    local total, n = M.TrainTotal(trainerServices())
    if n > 0 then
        ns.FP.Print(string.format("%d feitiço(s) para treinar aqui, total %s (você tem %s). /fp treinar tudo compra.",
            n, ns.Util.FormatMoney(total), ns.Util.FormatMoney(money())))
    end
    local frame = _G.ClassTrainerFrame
    if frame and not ClassGuide.trainAllButton and ns.Theme and ns.Theme.Button then
        local b = ns.Theme.Button(frame, "Treinar tudo", 90, 22, function() ClassGuide.TrainAll() end)
        b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -30)
        ClassGuide.trainAllButton = b
    end
end)

-- R3: compra os disponíveis em ordem enquanto o dinheiro der.
function ClassGuide.TrainAll()
    local services = trainerServices()
    if #services == 0 or not _G.BuyTrainerService then ns.FP.Print("abra a janela do treinador primeiro."); return end
    -- R3 (parecer 053-056): escolhe em ordem, enquanto o dinheiro der; compra de trás para frente,
    -- porque comprar tira o serviço da lista e muda o índice dos seguintes.
    local pick, spent, left = {}, 0, money()
    for _, s in ipairs(services) do
        if s.available then
            if s.cost > left then break end
            pick[#pick + 1] = s
            spent, left = spent + s.cost, left - s.cost
        end
    end
    for i = #pick, 1, -1 do _G.BuyTrainerService(pick[i].index) end
    local bought = #pick
    ns.FP.Print(bought > 0 and string.format("treinou %d feitiço(s), gastou %s.", bought, ns.Util.FormatMoney(spent))
        or "nada para treinar com o dinheiro que você tem.")
end

-- R4: posições da barra com rank velho.
local function oldRanks()
    local _, class = UnitClass("player")
    local list = ns.Spells and ns.Spells[class]
    local info = _G.GetActionInfo
    if not (list and info) then return {} end
    local slots = {}
    for slot = 1, 180 do
        local kind, id = info(slot)
        if kind == "spell" and id then slots[#slots + 1] = { slot = slot, id = id } end
    end
    return M.OldRanks(slots, list, isKnown)
end

-- R5: /fp ranks [trocar]
function ClassGuide.Ranks(arg)
    local list = oldRanks()
    if #list == 0 then ns.FP.Print("nenhum rank velho na barra."); return end
    if arg ~= "trocar" then
        for _, r in ipairs(list) do
            ns.FP.Print(string.format("  posição %d: %s do nível %d (o livro tem o do nível %d)", r.slot, r.name, r.lvl, r.newLvl))
        end
        ns.FP.Print("/fp ranks trocar põe o rank novo no lugar.")
        return
    end
    if InCombatLockdown() then ns.FP.Print("em combate não dá para mexer na barra."); return end
    local pickup = (_G.C_Spell and _G.C_Spell.PickupSpell) or _G.PickupSpell
    if not (pickup and _G.PlaceAction and _G.ClearCursor) then ns.FP.Print("este cliente não deixa trocar a barra."); return end
    local done = 0
    for _, r in ipairs(list) do
        _G.ClearCursor(); pickup(r.newId); _G.PlaceAction(r.slot); _G.ClearCursor()
        local _, id = _G.GetActionInfo(r.slot)
        if id == r.newId then done = done + 1 end -- parecer: conta só o que a barra confirmou
    end
    ns.FP.Print(string.format("%d de %d posição(ões) com o rank novo.", done, #list))
end

local ranksWarned, ranksPending = {}, false
ns.FP.On("LEARNED", function()
    if ranksPending then return end -- parecer: "Treinar tudo" dispara um LEARNED por feitiço; um aviso só
    ranksPending = true
    ns.FP.AfterCombat("oldRanks", function()
        C_Timer.After(2, function()
            ranksPending = false
            local fresh = 0
            for _, r in ipairs(oldRanks()) do
                if not ranksWarned[r.slot .. ":" .. r.newId] then ranksWarned[r.slot .. ":" .. r.newId] = true; fresh = fresh + 1 end
            end
            if fresh > 0 then ns.FP.Print(string.format("|cFFFFD100%d botão(ões) da barra com rank velho.|r /fp ranks mostra; /fp ranks trocar troca.", fresh)) end
        end)
    end)
end)

-- Spec 051, R5: seta no treinador da classe mais perto (o do mesmo continente primeiro).
function ClassGuide.FollowClassTrainer()
    local level = UnitLevel("player")
    local missing = ClassGuide.MissingSpells(level)
    if missing and #missing == 0 then
        ns.FP.Print(string.format("nada novo para treinar no nível %d.", level))
        return
    end
    local _, class = UnitClass("player")
    local title = M.TrainerTitle(class)
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    local all = title and ns.Data.NpcsBySubName(title, faction) or {}
    local player = ns.Planner.PlayerPoint()
    local near = {}
    for _, p in ipairs(all) do
        if ns.Planner.SameContinent(player, p) == true then near[#near + 1] = p end
    end
    local best = ns.Planner.Nearest(player, #near > 0 and near or all)
    if not best then
        ns.FP.Print("não achei o treinador da sua classe na QuestieDB (" .. tostring(title) .. ").")
        return
    end
    if missing then ns.FP.Print("|cFFFFD100para treinar:|r " .. M.FormatSpells(missing, 8) .. ".") end
    if #near == 0 then ns.FP.Print("o treinador mais perto fica em outro continente.") end
    ns.Gps.SetTarget(best.mapID, best.x, best.y, "Treinar: " .. tostring(best.name))
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
