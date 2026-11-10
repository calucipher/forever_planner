-- Milestones.lua: regras puras dos marcos da classe (spec 011). Sem API do WoW: tudo chega
-- por parâmetro (conteúdo da classe, função que diz se um feitiço é conhecido, distância).
local _, ns = ...
local Milestones = {}
ns.Milestones = Milestones

-- R6: perícia (feitiço passivo) por subclasse de arma (classe de item 2)
local WEAPON_CLASS = 2
local SKILL_BY_SUBCLASS = {
    [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201,
    [8] = 202, [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009,
}

function Milestones.WeaponSkillSpell(classID, subclassID)
    if classID ~= WEAPON_CLASS then return nil end
    return SKILL_BY_SUBCLASS[subclassID]
end

-- R5: perícias da classe que faltam, com os Weapon Masters da facção.
-- isKnown(spellID) -> boolean. Retorna { key, spell, name, trainers }.
function Milestones.MissingWeapons(classDef, faction, isKnown, isEnabled)
    local out = {}
    for _, w in ipairs(classDef and classDef.weapons or {}) do
        if not isKnown(w.spell) and (not isEnabled or isEnabled(w.key)) then
            out[#out + 1] = { key = w.key, spell = w.spell, name = w.name,
                trainers = (w.trainers and w.trainers[faction]) or {} }
        end
    end
    return out
end

-- Spec 016: arma da classe pela perícia (spell), ou nil.
function Milestones.WeaponBySpell(classDef, spell)
    for _, w in ipairs(classDef and classDef.weapons or {}) do
        if w.spell == spell then return w end
    end
    return nil
end

-- Spec 016, R4/R5: opções = { {name, point, dist, same} }. Do mesmo continente, a de menor distância;
-- sem nenhuma, a primeira (same=false); sem opções, nil.
function Milestones.PickTrainer(options)
    local best
    for _, o in ipairs(options) do
        if o.same and (not best or (o.dist or math.huge) < (best.dist or math.huge)) then best = o end
    end
    return best or options[1]
end

-- Spec 020, R1: custo de um transporte = dist (jogador até ele) + chegada até o treinador mais perto.
local function gateCost(gate, trainers, distance)
    if not gate.arrival or not gate.dist then return math.huge end
    local near = math.huge
    for _, t in ipairs(trainers) do
        local d = distance(gate.arrival, t.point)
        if d and d < near then near = d end
    end
    return gate.dist + near
end

-- Spec 020, R1: gates = { {name, dist, same, arrival} }; trainers = { {point} }; distance(a, b).
-- Entre os do continente do jogador, o de menor custo; empate (inclusive todos infinitos), o de
-- menor dist; sem nenhum no continente, nil.
function Milestones.PickGate(gates, trainers, distance)
    local best, bestCost
    for _, g in ipairs(gates) do
        if g.same then
            local cost = gateCost(g, trainers, distance)
            local closer = best and cost == bestCost and (g.dist or math.huge) < (best.dist or math.huge)
            if not best or cost < bestCost or closer then best, bestCost = g, cost end
        end
    end
    return best
end

-- Spec 020, R4: aviso quando não há transporte para o treinador em outro continente.
function Milestones.NoGateText(weaponName, places, routesLoaded)
    local cause = routesLoaded and "Onde você está não há nenhum zepelim ou barco para outro continente"
        or "A tabela de rotas não carregou: reabra o jogo (/reload não carrega arquivo novo)"
    return string.format("|cFFFFAA00%s só tem treinador em outro continente:|r %s. %s; viaje até lá.", weaponName, places, cause)
end

-- Spec 016: "Hanashi (Orgrimmar, Valley of Honor)" -> "Orgrimmar, Valley of Honor".
function Milestones.TrainerPlace(trainer)
    local text = tostring(trainer)
    return text:match("%((.-)%)") or text
end

-- Spec 015, R2: "Hanashi (Orgrimmar, ...)" -> "Hanashi".
function Milestones.TrainerNpcName(trainer)
    local text = tostring(trainer)
    return text:match("^(.-)%s*%(") or text
end

-- Spec 011, A11: uma linha por perícia da classe, para o /fp diag (validar IsPlayerSpell no client).
function Milestones.SkillReport(classDef, isKnown)
    local out = {}
    for _, w in ipairs(classDef and classDef.weapons or {}) do
        out[#out + 1] = string.format("%s (%d): conhece=%s", w.name, w.spell, isKnown(w.spell) and "sim" or "não")
    end
    return out
end

-- Nome da perícia que a arma pede, se o personagem não a tem (para o "(treine X)").
function Milestones.MissingSkillName(classDef, spell, isKnown)
    if not spell or isKnown(spell) then return nil end
    for _, w in ipairs(classDef and classDef.weapons or {}) do
        if w.spell == spell then return w.name end
    end
    return nil
end

-- R7: marcos de um nível; Upcoming: marcos do nível atual em diante (até `count`).
-- Spec 017, R3: marco com `spell` que o jogador já conhece está cumprido.
function Milestones.IsDone(m, isKnown)
    return isKnown ~= nil and m.spell ~= nil and isKnown(m.spell) == true
end

function Milestones.ForLevel(classDef, level, isKnown)
    local out = {}
    for _, m in ipairs(classDef and classDef.milestones or {}) do
        if m.lvl == level and not Milestones.IsDone(m, isKnown) then out[#out + 1] = m end
    end
    return out
end

-- R7: marcos dos últimos `window` níveis já passados (quem instala o addon no meio do leveling).
function Milestones.Missed(classDef, level, window, isKnown)
    local out = {}
    for _, m in ipairs(classDef and classDef.milestones or {}) do
        if m.lvl < level and m.lvl >= level - (window or 5) and not Milestones.IsDone(m, isKnown) then out[#out + 1] = m end
    end
    return out
end

-- R6: arma sem a perícia treinada não conta como upgrade.
function Milestones.EffectiveDelta(delta, missingSkill)
    if missingSkill then return 0 end
    return delta
end

-- Spec 012: a recompensa é arma (classe de item 2) que o personagem pode usar e que rende upgrade.
function Milestones.IsWeaponUpgrade(classID, effectiveDelta, missingSkill)
    return classID == 2 and (effectiveDelta or 0) > 0 and not missingSkill
end

function Milestones.Upcoming(classDef, level, count, isKnown)
    local out = {}
    for _, m in ipairs(classDef and classDef.milestones or {}) do
        if m.lvl >= level and #out < (count or 5) and not Milestones.IsDone(m, isKnown) then out[#out + 1] = m end
    end
    return out
end

-- Spec 017, R6: o feitiço vale para este personagem? `fac` = facção exigida, `races` = máscara de raças.
function Milestones.SpellAllowed(spell, faction, raceBit, hasBit)
    if spell.fac and faction and spell.fac ~= faction then return false end
    if spell.races and (not raceBit or not hasBit or not hasBit(spell.races, raceBit)) then return false end -- sem raça conhecida, não mostra
    return true
end

-- Spec 017, R1: spells = { {lvl, id, name} }. Aprendido = conhece qualquer feitiço de mesmo nome com
-- nível igual ou maior. Dos que faltam (até o nível do jogador) fica o de maior nível por nome.
-- Retorna { {lvl, id, name, rank} } com os mais novos primeiro; rank = existe um de nível menor com o mesmo nome.
function Milestones.MissingSpells(spells, level, isKnown)
    local knownLvl, lowest = {}, {}
    for _, s in ipairs(spells or {}) do
        if isKnown(s.id) and s.lvl > (knownLvl[s.name] or 0) then knownLvl[s.name] = s.lvl end
        if not lowest[s.name] or s.lvl < lowest[s.name] then lowest[s.name] = s.lvl end
    end
    local best = {}
    for _, s in ipairs(spells or {}) do
        if s.lvl <= level and s.lvl > (knownLvl[s.name] or 0) and (not best[s.name] or s.lvl > best[s.name].lvl) then
            best[s.name] = s
        end
    end
    local out = {}
    for name, s in pairs(best) do
        out[#out + 1] = { lvl = s.lvl, id = s.id, name = s.name, rank = lowest[name] < s.lvl }
    end
    table.sort(out, function(a, b) if a.lvl ~= b.lvl then return a.lvl > b.lvl end return a.name < b.name end)
    return out
end

-- Spec 017, R4: "A (10), B (12, rank novo) e mais 3". Mostra os `max` primeiros.
function Milestones.FormatSpells(list, max)
    local parts = {}
    for i = 1, math.min(#list, max) do
        local s = list[i]
        parts[#parts + 1] = string.format("%s (%d%s)", s.name, s.lvl, s.rank and ", rank novo" or "")
    end
    local text = table.concat(parts, ", ")
    if #list > max then text = text .. " e mais " .. (#list - max) end
    return text
end

-- R8: nível par a partir do 4 (validado no cliente, spec 017).
function Milestones.TrainerDue(classDef, level)
    return classDef ~= nil and classDef.trainerEvenLevels == true and level >= 4 and level % 2 == 0
end

-- R2: disponível e no log ficam; das que não liberaram, só começo de cadeia em até `window` níveis.
local DEFAULT_WINDOW = 10
local function isOpen(e) return e.status == "disponível" or e.status == "no log" end

function Milestones.VisibleClassList(entries, level, window)
    local out = {}
    for _, e in ipairs(entries) do
        local soon = (e.req or 0) > level and (e.req or 0) <= level + (window or DEFAULT_WINDOW) and not e.hasPre
        if isOpen(e) or soon then out[#out + 1] = e end
    end
    return out
end

-- R2: versões com o mesmo nome (por raça ou cidade) viram uma: a do log, senão a de menor distância.
-- dist(entry) -> jardas ou nil. Mantém a ordem da primeira ocorrência de cada nome.
function Milestones.DedupeByName(entries, dist)
    local bestByName, order = {}, {}
    for _, e in ipairs(entries) do
        local key = e.name or tostring(e.q)
        local cur = bestByName[key]
        local d = dist(e)
        if not cur then
            bestByName[key] = { e = e, d = d }
            order[#order + 1] = key
        else
            -- a do log tem prioridade; entre iguais, a de quest giver mais perto
            local inLog, curInLog = e.status == "no log", cur.e.status == "no log"
            if (inLog and not curInLog)
                or (inLog == curInLog and d and (cur.d == nil or d < cur.d)) then
                bestByName[key] = { e = e, d = d }
            end
        end
    end
    local out = {}
    for _, key in ipairs(order) do out[#out + 1] = bestByName[key].e end
    return out
end

-- R4: quests de classe que liberaram exatamente neste nível e estão disponíveis.
function Milestones.UnlockedNow(entries, level)
    local out = {}
    for _, e in ipairs(entries) do
        if e.status == "disponível" and e.req == level then out[#out + 1] = e end
    end
    return out
end

-- R3: a melhor para seguir: aberta, na zona atual primeiro, depois menor nível.
function Milestones.Best(entries, zone)
    local best, bestKey
    for _, e in ipairs(entries) do
        if isOpen(e) then
            local key = (e.mapID == zone and 0 or 1) * 1000 + (e.level or e.req or 0)
            if not bestKey or key < bestKey then best, bestKey = e, key end
        end
    end
    return best
end

return Milestones
