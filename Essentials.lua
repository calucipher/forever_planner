-- Essentials.lua: a lista de verificação dos essenciais (spec 062). Núcleo puro, sem API do jogo:
-- recebe os fatos que o adaptador (EssentialsGuide.lua) junta e devolve as linhas.
local _, ns = ...
local L = ns.L -- spec 066
local Essentials = {}
ns.Essentials = Essentials

Essentials.MOUNT_LEVEL, Essentials.MOUNT_SAVE = 40, 38
Essentials.MOUNT_COST = 1000000 -- 100 ouro em cobre: estimativa do Classic (treino + montaria)
Essentials.FOOD_GAP = 10
Essentials.FIRST_AID_LEVEL = 10
local CLASS_MOUNT = { WARLOCK = true, PALADIN = true }
local RANK = { pendente = 1, conferir = 2, depois = 3, feito = 4 } -- R1a

local function gold(c) return math.floor((c or 0) / 10000) end
local function names(list, max)
    local out = {}
    for i = 1, math.min(#list, max or 3) do out[i] = list[i] end
    return table.concat(out, ", ") .. (#list > (max or 3) and (L[" e mais "] .. (#list - (max or 3))) or "")
end

-- Spec 066: o estado é chave interna; quem mostra traduz com L[estado].
Essentials.STATUS = { ns.Locale.K("pendente"), ns.Locale.K("conferir"), ns.Locale.K("depois"), ns.Locale.K("feito") }

-- R1: uma linha por item, na ordem abaixo; depois, pendentes primeiro (ordem estável).
function Essentials.Build(f)
    local lvl, out = f.level or 1, {}
    local function add(key, label, status, detail)
        out[#out + 1] = { key = key, label = label, status = status, detail = detail or "", pos = #out + 1 }
    end

    local bagsBad = (f.emptyBagSlots or 0) > 0 or (f.minBag or 99) < 10
    add("bolsas", L["Bolsas"], bagsBad and "pendente" or "feito",
        ((f.emptyBagSlots or 0) > 0 and (f.emptyBagSlots .. L[" espaço(s) de bolsa vazio(s)"]) or
            ((f.minBag or 99) < 10 and (L["bolsa pequena ("] .. f.minBag .. ")") or L["bolsas cheias de espaço"]))
        .. ((f.bagQuests or 0) > 0 and (" · " .. f.bagQuests .. L[" quest(s) de bolsa"]) or ""))

    local sm = f.spellsMissing or 0
    add("treino", L["Treinar feitiços"], sm > 0 and "pendente" or "feito",
        sm > 0 and string.format(L["%d feitiço(s)%s"], sm, (f.newSpells or 0) > 0 and (", " .. f.newSpells .. L[" novo(s) do Forever"]) or "") or L["nada novo"])

    add("ranks", L["Rank velho na barra"], (f.oldRanks or 0) > 0 and "pendente" or "feito",
        (f.oldRanks or 0) > 0 and (f.oldRanks .. L[" botão(ões)"]) or "")

    local wm = f.weaponsMissing or {}
    add("armas", L["Perícia de arma"], #wm > 0 and "pendente" or "feito", #wm > 0 and names(wm) or "")

    if f.classQuest then add("classe", L["Quest de classe"], "pendente", f.classQuest)
    elseif f.classNext then add("classe", L["Quest de classe"], "depois", L["próxima no "] .. f.classNext)
    else add("classe", L["Quest de classe"], "feito", "") end

    local cost = f.mountCost or Essentials.MOUNT_COST
    local classMount = CLASS_MOUNT[f.class or ""]
    local mountWhere = classMount and L["montaria de classe no treinador"] or ("~" .. gold(cost) .. L[" ouro, estimativa"])
    if f.mountKnown then add("montaria", L["Montaria"], "feito", "")
    elseif lvl >= Essentials.MOUNT_LEVEL then add("montaria", L["Montaria"], "pendente", mountWhere)
    elseif lvl >= Essentials.MOUNT_SAVE then
        add("montaria", L["Montaria"], "depois", classMount and (L["no 40: "] .. mountWhere)
            or string.format(L["no 40: junte ~%d ouro (você tem %d)"], gold(cost), gold(f.money)))
    else add("montaria", L["Montaria"], "depois", L["no 40"]) end

    if not f.bindZone or not f.zone then -- R1a: sem o ponto gravado ou a zona, não afirma
        add("pedra", L["Pedra de lar"], "conferir", L["fale com um estalajadeiro para o addon ver onde está"])
    else
        local away = f.zone and f.bindZone ~= f.zone
        add("pedra", L["Pedra de lar"], away and "pendente" or "feito", L["marcada em "] .. f.bindZone)
    end

    local fr = f.flightRed or {}
    add("voo", L["Ponto de voo da zona"], #fr > 0 and "pendente" or "feito", #fr > 0 and names(fr) or "")

    add("gear", L["Gear"], f.gearNow and "pendente" or "feito", f.gearNow or "")

    local food = f.foodLevel
    local hungry = not food or food < lvl - Essentials.FOOD_GAP
    add("comida", L["Comida e bebida"], hungry and "pendente" or "feito",
        food and (L["a melhor é do nível "] .. food) or L["nenhuma na bolsa"])

    if f.class == "HUNTER" then
        add("municao", L["Munição"], (f.ammo or 0) == 0 and "pendente" or "feito", (f.ammo or 0) .. L[" na bolsa"])
    end

    if lvl >= Essentials.FIRST_AID_LEVEL then
        add("socorros", L["Primeiros Socorros"], (f.firstAid or 0) == 0 and "pendente" or "feito",
            (f.firstAid or 0) == 0 and L["ataduras poupam tempo parado"] or (L["nível "] .. f.firstAid))
    end

    table.sort(out, function(a, b)
        if RANK[a.status] ~= RANK[b.status] then return RANK[a.status] < RANK[b.status] end
        return a.pos < b.pos
    end)
    return out
end

-- R2
function Essentials.PendingCount(list)
    local n = 0
    for _, it in ipairs(list or {}) do if it.status == "pendente" then n = n + 1 end end
    return n
end

return Essentials
