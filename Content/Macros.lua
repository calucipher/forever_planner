-- Content/Macros.lua: macros de leveling e avançadas por classe (specs 003 e 007), montadas na
-- hora de criar. Nomes vêm do client pelo ID do feitiço (idioma do client); só entra o que o
-- personagem conhece; ao aprender um feitiço, as macros FP já criadas são reescritas.
-- Feitas para repeat (Razer Naga): alvo automático só em combate, prioridades e castsequence.
-- IDs do Classic (rank 1). ID, nome `en` e `level` conferidos nas DB2 do cliente do Forever
-- (build 1.60.1.70862, 07/11/2026, tools/check_content.py). No jogo: /fp macros.
local _, ns = ...
local Macros = {}
ns.Macros = Macros

local MAX_BODY = 255
local ICON = "INV_MISC_QUESTIONMARK" -- com #showtooltip o jogo mostra o ícone do feitiço

-- level = nível em que costuma liberar (mensagem de indisponível); en = nome se o client não
-- devolver pelo ID; alt = nomes do Forever tentados antes do ID (ex.: Curse virou Bane).
Macros.spells = {
    -- Warlock
    immolate = { id = 348, level = 1, en = "Immolate" },
    shadowBolt = { id = 686, level = 1, en = "Shadow Bolt" },
    corruption = { id = 172, level = 4, en = "Corruption" },
    agony = { id = 980, level = 8, en = "Curse of Agony", alt = { "Bane of Agony" } },
    siphon = { id = 18265, level = 30, en = "Siphon Life" },
    drainLife = { id = 689, level = 14, en = "Drain Life" },
    drainSoul = { id = 1120, level = 10, en = "Drain Soul" },
    fear = { id = 5782, level = 8, en = "Fear" },
    shoot = { id = 5019, level = 1, en = "Shoot" },
    lifeTap = { id = 1454, level = 6, en = "Life Tap" },
    -- Warrior
    heroicStrike = { id = 78, level = 1, en = "Heroic Strike" },
    charge = { id = 100, level = 4, en = "Charge" },
    overpower = { id = 7384, level = 12, en = "Overpower" },
    execute = { id = 5308, level = 24, en = "Execute" },
    thunderClap = { id = 6343, level = 6, en = "Thunder Clap" },
    cleave = { id = 845, level = 20, en = "Cleave" },
    mortalStrike = { id = 12294, level = 40, en = "Mortal Strike" },
    bloodthirst = { id = 23881, level = 40, en = "Bloodthirst" },
    whirlwind = { id = 1680, level = 36, en = "Whirlwind" },
    -- Mage
    fireball = { id = 133, level = 1, en = "Fireball" },
    frostbolt = { id = 116, level = 4, en = "Frostbolt" },
    fireBlast = { id = 2136, level = 6, en = "Fire Blast" },
    frostNova = { id = 122, level = 10, en = "Frost Nova" },
    arcaneExplosion = { id = 1449, level = 14, en = "Arcane Explosion" },
    polymorph = { id = 118, level = 8, en = "Polymorph" },
    -- Druid
    wrath = { id = 5176, level = 1, en = "Wrath" },
    moonfire = { id = 8921, level = 4, en = "Moonfire" },
    bearForm = { id = 5487, level = 10, en = "Bear Form" },
    maul = { id = 6807, level = 10, en = "Maul" },
    swipe = { id = 779, level = 16, en = "Swipe" },
    catForm = { id = 768, level = 20, en = "Cat Form" },
    claw = { id = 1082, level = 20, en = "Claw" },
    rake = { id = 1822, level = 24, en = "Rake" },
    rip = { id = 1079, level = 20, en = "Rip" },
    ferociousBite = { id = 22568, level = 32, en = "Ferocious Bite" },
    rejuvenation = { id = 774, level = 4, en = "Rejuvenation" },
}

Macros.categories = { "Leveling", "Avançadas" }

-- Linhas do modelo:
--   { "tip", chave? }        #showtooltip (com o feitiço, se conhecido)
--   { "auto" }               alvo automático só em combate (spec 003, R5)
--   { "raw", "/texto" }      linha fixa
--   { "cast", chave, cond? } /cast [cond] Nome
--   { "bang", chave }        /cast !Nome (não desliga varinha nem desfaz forma)
--   { "mo", chave }          mouseover; sem mouseover, alvo
--   { "mofocus", chave }     mouseover; foco; alvo
--   { "self", chave }        /cast [@player] Nome
--   { "seq", {itens} }       /castsequence reset=target/combat; item = chave, {alternativas} ou "null"
--   { "wandOr", chave }      /cast [equipped:Varinhas] !Shoot; Nome (sem varinha, o feitiço)
-- requires = feitiço sem o qual a macro fica indisponível. noRepeat = não usar no repeat.
local AUTO = { "auto" }
local TIP = { "tip" }

Macros.classes = {
    WARLOCK = {
        -- Emenda de 08/11/2026 (spec 003): poupa mana. "null" segura a sequência (não recasta os DoTs).
        { name = "FP Rotacao", cat = "Leveling", requires = "shadowBolt",
          lines = { TIP, AUTO, { "raw", "/petattack" },
              { "seq", { "corruption", "agony", "siphon", "shadowBolt", "null" } }, { "wandOr", "shadowBolt" } },
          desc = "Spam que poupa mana: pet ataca, DoTs, 1 Shadow Bolt e depois a varinha (sem varinha, Shadow Bolt)." },
        { name = "FP Tap", cat = "Leveling", requires = "lifeTap", noRepeat = true,
          lines = { { "tip", "lifeTap" }, { "cast", "lifeTap" } },
          desc = "Life Tap: vida vira mana. Use com vida alta; recupere a vida com Drain Life." },
        { name = "FP Corrup", cat = "Leveling", requires = "corruption",
          lines = { { "tip", "corruption" }, { "mo", "corruption" } },
          desc = "Corruption no mouseover (sem trocar de alvo); sem mouseover, no alvo." },
        { name = "FP Agony", cat = "Leveling", requires = "agony",
          lines = { { "tip", "agony" }, { "mo", "agony" } },
          desc = "Agony (Bane ou Curse) no mouseover; sem mouseover, no alvo." },
        { name = "FP Dreno", cat = "Leveling", requires = "drainLife", noRepeat = true,
          lines = { { "tip", "drainLife" }, AUTO, { "mo", "drainLife" } },
          desc = "Drain Life no mouseover ou no alvo (drain tanking). Canalizado: aperte uma vez." },
        { name = "FP Varinha", cat = "Leveling", requires = "shoot",
          lines = { { "tip", "shoot" }, AUTO, { "raw", "/petattack" }, { "bang", "shoot" } },
          desc = "Pet ataca e liga a varinha sem desligar se apertar de novo." },
        { name = "FP Burst", cat = "Avançadas", requires = "shadowBolt",
          lines = { TIP, AUTO, { "raw", "/petattack" },
              { "seq", { "immolate", "corruption", "agony", "siphon", "shadowBolt", "shadowBolt" } } },
          desc = "Mob difícil ou elite: Immolate, DoTs e 2 Shadow Bolts (gasta muita mana)." },
        { name = "FP Fear", cat = "Avançadas", requires = "fear", noRepeat = true,
          lines = { { "tip", "fear" }, { "mofocus", "fear" } },
          desc = "Fear no mouseover, no foco ou no alvo: tira o segundo mob da luta." },
        { name = "FP Shard", cat = "Avançadas", requires = "drainSoul", noRepeat = true,
          lines = { { "tip", "drainSoul" }, AUTO, { "cast", "drainSoul" } },
          desc = "Drain Soul no fim do mob para ganhar Soul Shard. Canalizado: aperte uma vez." },
    },
    WARRIOR = {
        { name = "FP Guerreiro", cat = "Leveling", requires = "heroicStrike",
          lines = { TIP, AUTO, { "raw", "/startattack" }, { "cast", "charge", "[nocombat]" },
              { "cast", "execute" }, { "cast", "overpower" }, { "cast", "heroicStrike" } },
          desc = "Spam: Charge fora de combate, Execute e Overpower quando dá, Heroic Strike na próxima pancada." },
        { name = "FP AoE", cat = "Avançadas", requires = "thunderClap",
          lines = { TIP, { "raw", "/startattack" }, { "cast", "thunderClap" }, { "cast", "cleave" } },
          desc = "Pull de vários: Thunder Clap quando sai do cooldown, Cleave na próxima pancada." },
        { name = "FP Avancado", cat = "Avançadas", requires = "heroicStrike",
          lines = { TIP, AUTO, { "raw", "/startattack" }, { "cast", "execute" }, { "cast", "overpower" },
              { "cast", "mortalStrike" }, { "cast", "bloodthirst" }, { "cast", "whirlwind" }, { "cast", "heroicStrike" } },
          desc = "Prioridade de nível alto: Execute > Overpower > Mortal Strike/Bloodthirst > Whirlwind, Heroic Strike." },
    },
    MAGE = {
        { name = "FP Mago", cat = "Leveling", requires = "fireball",
          lines = { TIP, AUTO, { "seq", { { "frostbolt", "fireball" }, { "frostbolt", "fireball" },
              { "frostbolt", "fireball" }, "fireBlast" } } },
          desc = "Spam: 3 Frostbolts (ou Fireball no começo) e Fire Blast para finalizar." },
        { name = "FP Varinha", cat = "Leveling", requires = "shoot",
          lines = { { "tip", "shoot" }, AUTO, { "bang", "shoot" } },
          desc = "Liga a varinha sem desligar se apertar de novo (sem mana)." },
        { name = "FP AoE", cat = "Avançadas", requires = "arcaneExplosion",
          lines = { TIP, { "cast", "frostNova" }, { "cast", "arcaneExplosion" } },
          desc = "AoE de pull grande: Frost Nova quando sai do cooldown, depois Arcane Explosion." },
        { name = "FP Avancado", cat = "Avançadas", requires = "fireball",
          lines = { TIP, AUTO, { "cast", "fireBlast" }, { "cast", "frostbolt" }, { "cast", "fireball" } },
          desc = "Prioridade: Fire Blast quando sai do cooldown, senão Frostbolt (ou Fireball)." },
        { name = "FP Poly", cat = "Avançadas", requires = "polymorph", noRepeat = true,
          lines = { { "tip", "polymorph" }, { "mofocus", "polymorph" } },
          desc = "Polymorph no mouseover, no foco ou no alvo: tira o segundo mob da luta." },
    },
    DRUID = {
        { name = "FP Druida", cat = "Leveling", requires = "wrath",
          lines = { TIP, AUTO, { "seq", { "moonfire", "wrath", "wrath", "wrath" } } },
          desc = "Spam de caster (1-10): Moonfire e 3 Wraths." },
        { name = "FP Urso", cat = "Leveling", requires = "bearForm",
          lines = { { "tip", "maul" }, { "bang", "bearForm" }, AUTO, { "raw", "/startattack" }, { "cast", "maul" } },
          desc = "Entra em urso (sem desfazer no spam), ataca e Maul na próxima pancada." },
        { name = "FP Gato", cat = "Leveling", requires = "catForm",
          lines = { TIP, { "bang", "catForm" }, AUTO, { "raw", "/startattack" },
              { "seq", { "rake", "claw", "claw", "claw", { "ferociousBite", "rip" } } } },
          desc = "Entra em gato, Rake, 3 Claws e finaliza com Ferocious Bite (ou Rip antes do 32)." },
        { name = "FP Urso AoE", cat = "Avançadas", requires = "swipe",
          lines = { { "tip", "swipe" }, { "bang", "bearForm" }, { "raw", "/startattack" }, { "cast", "swipe" },
              { "cast", "maul" } },
          desc = "Pull de vários em urso: Swipe e Maul na próxima pancada." },
        { name = "FP Cura", cat = "Avançadas", requires = "rejuvenation", noRepeat = true,
          lines = { { "tip", "rejuvenation" }, { "raw", "/cancelform" }, { "self", "rejuvenation" } },
          desc = "Sai da forma e põe Rejuvenation em você. Aperte uma vez." },
    },
}

-- Macros.list = macros da classe do personagem (spec 007, R1).
function Macros.List()
    local _, class = UnitClass("player")
    return Macros.classes[class] or {}
end
setmetatable(Macros, { __index = function(_, k) if k == "list" then return Macros.List() end end })

------------------------------------------------------------------------------------------
-- Montagem pura: names = { [chave] = nome localizado } só com o que o personagem conhece
------------------------------------------------------------------------------------------
-- Spec 003, R5: em combate, troca de alvo só se não houver alvo hostil vivo. Fora de combate
-- não procura alvo sozinha (com a macro repetida, puxava mob atrás de mob).
local AUTO_TARGET = "/targetenemy [combat,noharm][combat,dead]"

local function missing(key)
    local s = Macros.spells[key]
    return { missing = key, level = s and s.level or 1 }
end

local function pick(item, names) -- item = chave, lista de alternativas ou "null"
    if item == "null" then return "null" end
    if type(item) ~= "table" then return names[item] end
    for _, k in ipairs(item) do if names[k] then return names[k] end end
    return nil
end

local LINE = {
    tip = function(l, names) return l[2] and names[l[2]] and ("#showtooltip " .. names[l[2]]) or "#showtooltip" end,
    auto = function() return AUTO_TARGET end,
    raw = function(l) return l[2] end,
    cast = function(l, names)
        local n = names[l[2]]
        return n and ("/cast " .. (l[3] and (l[3] .. " ") or "") .. n)
    end,
    bang = function(l, names) return names[l[2]] and ("/cast !" .. names[l[2]]) end,
    mo = function(l, names) return names[l[2]] and ("/cast [@mouseover,harm,nodead][] " .. names[l[2]]) end,
    mofocus = function(l, names)
        return names[l[2]] and ("/cast [@mouseover,harm,nodead][@focus,harm,nodead][] " .. names[l[2]])
    end,
    self = function(l, names) return names[l[2]] and ("/cast [@player] " .. names[l[2]]) end,
    seq = function(l, names)
        local seq = {}
        for _, item in ipairs(l[2]) do seq[#seq + 1] = pick(item, names) end
        if seq[#seq] == "null" and #seq == 1 then return nil end
        return #seq > 0 and ("/castsequence reset=target/combat " .. table.concat(seq, ", ")) or nil
    end,
    -- R10 (emenda de 08/11/2026): varinha se houver uma equipada; senão, o feitiço.
    wandOr = function(l, names)
        local spell = names[l[2]]
        if not names.shoot then return spell and ("/cast " .. spell) end
        local wand = "/cast [equipped:" .. (names["@wands"] or "Wands") .. "] !" .. names.shoot
        return spell and (wand .. "; " .. spell) or wand
    end,
}

function Macros.Compose(m, names)
    if not names[m.requires] then return nil, missing(m.requires) end
    local lines = {}
    for _, l in ipairs(m.lines) do
        local text = LINE[l[1]](l, names)
        if text then lines[#lines + 1] = text end
    end
    local body = table.concat(lines, "\n")
    if #body > MAX_BODY then return nil, { tooLong = true, length = #body } end -- R8
    return body
end

------------------------------------------------------------------------------------------
-- Adaptador: o que o personagem conhece, com o nome do client
------------------------------------------------------------------------------------------
local function spellName(id)
    local C = _G.C_Spell
    if C and C.GetSpellInfo then
        local info = C.GetSpellInfo(id)
        return info and info.name
    end
    return _G.GetSpellInfo and (_G.GetSpellInfo(id))
end

local function knownByName(name)
    local C = _G.C_Spell
    if C and C.GetSpellInfo then return C.GetSpellInfo(name) ~= nil end
    return _G.GetSpellInfo and _G.GetSpellInfo(name) ~= nil
end

local function knownByID(id)
    if _G.IsPlayerSpell then return _G.IsPlayerSpell(id) == true end
    return _G.IsSpellKnown and _G.IsSpellKnown(id) == true
end

-- Nome localizado se o personagem conhece o feitiço; nil se não conhece (R1, R3).
function Macros.Resolve(key)
    local s = Macros.spells[key]
    for _, alt in ipairs(s.alt or {}) do
        if knownByName(alt) then return alt end
    end
    local name = spellName(s.id) or s.en
    if knownByID(s.id) or knownByName(name) then return name end
    return nil
end

-- Nome do tipo de item "varinha" no idioma do client (classe 2, subclasse 19), para [equipped:].
local function wandsName()
    local C = _G.C_Item
    local name = C and C.GetItemSubClassInfo and C.GetItemSubClassInfo(2, 19)
    if not name and _G.GetItemSubClassInfo then name = _G.GetItemSubClassInfo(2, 19) end
    return name
end

function Macros.KnownNames()
    local names = {}
    for key in pairs(Macros.spells) do names[key] = Macros.Resolve(key) end
    names["@wands"] = wandsName()
    return names
end

function Macros.Build(m) return Macros.Compose(m, Macros.KnownNames()) end

function Macros.WhyText(why)
    if why.tooLong then return string.format("texto com %d caracteres (máximo %d)", why.length, MAX_BODY) end
    local s = Macros.spells[why.missing]
    return string.format("libera no nível %d (%s)", why.level, s and s.en or why.missing)
end

-- Cria ou atualiza a macro (personagem). Proibido em combate.
function Macros.Install(m)
    if InCombatLockdown() then ns.FP.Print("saia do combate para criar macros."); return false end
    local body, why = Macros.Build(m)
    if not body then ns.FP.Print(m.name .. ":", Macros.WhyText(why)); return false end
    local idx = GetMacroIndexByName(m.name)
    if idx and idx > 0 then
        EditMacro(idx, m.name, ICON, body)
        ns.FP.Print("macro atualizada:", m.name)
        return true
    end
    local _, numChar = GetNumMacros()
    if numChar >= (MAX_CHARACTER_MACROS or 18) then ns.FP.Print("sem espaço para macros de personagem."); return false end
    local ok, err = pcall(CreateMacro, m.name, ICON, body, true)
    if not ok then ns.FP.Print("não deu pra criar:", err); return false end
    ns.FP.Print("macro criada:", m.name, "- arraste da janela /macro para a barra.")
    return true
end

function Macros.IsInstalled(m)
    local idx = GetMacroIndexByName(m.name)
    return idx ~= nil and idx > 0
end

-- R7: reescreve as macros FP já criadas quando o texto muda (mesmo índice: continua na barra).
function Macros.RefreshInstalled()
    local updated = {}
    for _, m in ipairs(Macros.List()) do
        local idx = GetMacroIndexByName(m.name)
        if idx and idx > 0 then
            local body = Macros.Build(m)
            local _, _, current = _G.GetMacroInfo(idx)
            if body and body ~= current then
                EditMacro(idx, m.name, nil, body)
                updated[#updated + 1] = m.name
            end
        end
    end
    if #updated > 0 then ns.FP.Print("macros atualizadas com o feitiço novo:", table.concat(updated, ", ")) end
end

ns.FP.On("SPELLS", function() ns.FP.AfterCombat("macrosRefresh", Macros.RefreshInstalled) end)

return Macros
