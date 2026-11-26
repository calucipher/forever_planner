-- Essentials.lua: a lista de verificação dos essenciais (spec 062). Núcleo puro, sem API do jogo:
-- recebe os fatos que o adaptador (EssentialsGuide.lua) junta e devolve as linhas.
local _, ns = ...
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
    return table.concat(out, ", ") .. (#list > (max or 3) and (" e mais " .. (#list - (max or 3))) or "")
end

-- R1: uma linha por item, na ordem abaixo; depois, pendentes primeiro (ordem estável).
function Essentials.Build(f)
    local L, out = f.level or 1, {}
    local function add(key, label, status, detail)
        out[#out + 1] = { key = key, label = label, status = status, detail = detail or "", pos = #out + 1 }
    end

    local bagsBad = (f.emptyBagSlots or 0) > 0 or (f.minBag or 99) < 10
    add("bolsas", "Bolsas", bagsBad and "pendente" or "feito",
        ((f.emptyBagSlots or 0) > 0 and (f.emptyBagSlots .. " espaço(s) de bolsa vazio(s)") or
            ((f.minBag or 99) < 10 and ("bolsa pequena (" .. f.minBag .. ")") or "bolsas cheias de espaço"))
        .. ((f.bagQuests or 0) > 0 and (" · " .. f.bagQuests .. " quest(s) de bolsa") or ""))

    local sm = f.spellsMissing or 0
    add("treino", "Treinar feitiços", sm > 0 and "pendente" or "feito",
        sm > 0 and string.format("%d feitiço(s)%s", sm, (f.newSpells or 0) > 0 and (", " .. f.newSpells .. " novo(s) do Forever") or "") or "nada novo")

    add("ranks", "Rank velho na barra", (f.oldRanks or 0) > 0 and "pendente" or "feito",
        (f.oldRanks or 0) > 0 and (f.oldRanks .. " botão(ões)") or "")

    local wm = f.weaponsMissing or {}
    add("armas", "Perícia de arma", #wm > 0 and "pendente" or "feito", #wm > 0 and names(wm) or "")

    if f.classQuest then add("classe", "Quest de classe", "pendente", f.classQuest)
    elseif f.classNext then add("classe", "Quest de classe", "depois", "próxima no " .. f.classNext)
    else add("classe", "Quest de classe", "feito", "") end

    local cost = f.mountCost or Essentials.MOUNT_COST
    local classMount = CLASS_MOUNT[f.class or ""]
    local mountWhere = classMount and "montaria de classe no treinador" or ("~" .. gold(cost) .. " ouro, estimativa")
    if f.mountKnown then add("montaria", "Montaria", "feito", "")
    elseif L >= Essentials.MOUNT_LEVEL then add("montaria", "Montaria", "pendente", mountWhere)
    elseif L >= Essentials.MOUNT_SAVE then
        add("montaria", "Montaria", "depois", classMount and ("no 40: " .. mountWhere)
            or string.format("no 40: junte ~%d ouro (você tem %d)", gold(cost), gold(f.money)))
    else add("montaria", "Montaria", "depois", "no 40") end

    if not f.bindZone or not f.zone then -- R1a: sem o ponto gravado ou a zona, não afirma
        add("pedra", "Pedra de lar", "conferir", "fale com um estalajadeiro para o addon ver onde está")
    else
        local away = f.zone and f.bindZone ~= f.zone
        add("pedra", "Pedra de lar", away and "pendente" or "feito", "marcada em " .. f.bindZone)
    end

    local fr = f.flightRed or {}
    add("voo", "Ponto de voo da zona", #fr > 0 and "pendente" or "feito", #fr > 0 and names(fr) or "")

    add("gear", "Gear", f.gearNow and "pendente" or "feito", f.gearNow or "")

    local food = f.foodLevel
    local hungry = not food or food < L - Essentials.FOOD_GAP
    add("comida", "Comida e bebida", hungry and "pendente" or "feito",
        food and ("a melhor é do nível " .. food) or "nenhuma na bolsa")

    if f.class == "HUNTER" then
        add("municao", "Munição", (f.ammo or 0) == 0 and "pendente" or "feito", (f.ammo or 0) .. " na bolsa")
    end

    if L >= Essentials.FIRST_AID_LEVEL then
        add("socorros", "Primeiros Socorros", (f.firstAid or 0) == 0 and "pendente" or "feito",
            (f.firstAid or 0) == 0 and "ataduras poupam tempo parado" or ("nível " .. f.firstAid))
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
