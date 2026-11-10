-- Util.lua: funções puras (testáveis fora do jogo) e guards de API.
local _, ns = ...
ns = ns or {}
local Util = {}
ns.Util = Util

local floor = math.floor

-- Máscaras de raça do Forever passam de 32 bits (Skyborne usa bits 32/33),
-- então nada de bit.band: aritmética em double é exata até 2^53.
function Util.HasBit(mask, bitValue)
    if not mask or mask == 0 then return true end -- 0 = sem restrição
    if not bitValue or bitValue <= 0 then return false end
    return floor(mask / bitValue) % 2 == 1
end

-- Spec 029, R5: flag de verdade. Diferente de HasBit, máscara 0 (ou nil) não tem flag nenhuma.
function Util.HasFlag(mask, bitValue)
    if not mask or mask == 0 or not bitValue or bitValue <= 0 then return false end
    return floor(mask / bitValue) % 2 == 1
end

-- Falloff de XP de quest do Classic (mantido no Forever).
function Util.XPFalloff(playerLevel, questLevel)
    local diff = (playerLevel or 0) - (questLevel or 0)
    if diff <= 5 then return 1.0
    elseif diff == 6 then return 0.8
    elseif diff == 7 then return 0.6
    elseif diff == 8 then return 0.4
    elseif diff == 9 then return 0.2
    end
    return 0.1
end

-- Secret values (herança do Midnight): nunca fazer conta com eles.
function Util.IsSecret(v)
    local f = _G and _G.issecretvalue
    return f ~= nil and v ~= nil and f(v) == true
end

function Util.Num(v)
    if v == nil or Util.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

function Util.InCombat()
    local f = _G and _G.InCombatLockdown
    return f ~= nil and f() == true
end

-- 12345 -> "12.345"
function Util.FormatInt(n)
    n = floor((n or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if out:sub(1, 1) == "." then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

-- cobre -> "1g 20s"
function Util.FormatMoney(copper)
    copper = floor(copper or 0)
    if copper <= 0 then return "-" end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

-- Soma dos números do texto do objetivo ("kill 8 X and 8 Y" -> 16).
function Util.ParseObjectiveCount(texts)
    if type(texts) ~= "table" then return nil end
    local total = 0
    for _, t in ipairs(texts) do
        if type(t) == "string" then
            for num in t:gmatch("(%d+)") do
                local n = tonumber(num)
                if n and n > 0 and n <= 40 then total = total + n end
            end
        end
    end
    return total > 0 and total or nil
end

-- Formato de GlobalString ("%s dies, you gain %d experience.") -> padrão Lua com capturas.
function Util.FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local pat = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pat = pat:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. pat
end

function Util.Median(list)
    local n = #list
    if n == 0 then return nil end
    table.sort(list)
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

function Util.CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Util.CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Spec 018, R2: nós da API de táxi -> pontos {mapID, x, y, name} em 0-100; ignora nó sem posição ou não usável.
function Util.TaxiPoints(nodes, mapID, isUsable)
    local out = {}
    for _, n in ipairs(nodes or {}) do
        local p = n.position
        if p and p.x and p.y and isUsable(n.state) then
            out[#out + 1] = { mapID = mapID, x = p.x * 100, y = p.y * 100, name = n.name, source = "taxi" .. tostring(n.nodeID) }
        end
    end
    return out
end

-- Spec 019, R1: rota do transporte (kind "npc"|"object", id) só se ela mudar de continente; senão nil.
function Util.CrossingRoute(routes, kind, id)
    local route = routes and routes[kind] and routes[kind][id]
    if route and route.crosses then return route end
    return nil
end

-- Spec 014: ("npc"|"object", id) a partir do GUID de Creature/Vehicle/GameObject; nil para o resto.
function Util.EntityFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind = guid:match("^(%a+)%-")
    local id = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not id then return nil end
    if kind == "Creature" or kind == "Vehicle" then return "npc", id end
    if kind == "GameObject" then return "object", id end
    return nil
end

-- Spec 014, R7: visitas sem oferta até marcar. Quest nova do Forever (ID >= 90000) sem pré-requisito
-- nos dados marca na 1ª: a QuestieDB não traz pré-requisito das quests novas do Forever.
function Util.VisitsToMark(q, hasPre)
    if (tonumber(q) or 0) >= 90000 and not hasPre then return 1 end
    return 2
end

-- Spec 014, R8: quests marcadas cujo NPC fica a até radius de quem deu/recebeu a quest entregue.
-- candidates = { { q, points } }; dist(a, b) em jardas (nil = desconhecida).
function Util.NearTurnIn(candidates, turnPoints, radius, dist)
    local out = {}
    for _, c in ipairs(candidates) do
        local near = false
        for _, p in ipairs(c.points or {}) do
            for _, t in ipairs(turnPoints or {}) do
                local d = dist(p, t)
                if d and d <= radius then near = true; break end
            end
            if near then break end
        end
        if near then out[#out + 1] = c.q end
    end
    return out
end

-- Spec 014: candidatas que não estão no conjunto oferecido, na ordem original.
function Util.NotOffered(candidates, offered)
    local out = {}
    for _, q in ipairs(candidates) do
        if not offered[q] then out[#out + 1] = q end
    end
    return out
end

-- Spec 013: título da seta. kind = "pegar" | "entregar" | "objetivo"; alvo = nome do NPC/objeto (ou nil).
function Util.TargetTitle(kind, target, text)
    if kind == "objetivo" then return "Objetivo: " .. text end
    local verb = kind == "pegar" and "Pegar" or "Entregar"
    if target and target ~= "" then
        return verb .. (kind == "pegar" and " com " or " a ") .. target .. ": " .. text
    end
    return verb .. ": " .. text
end

-- Spec 023, R1: campo de quest com a correção curada por cima da QuestieDB.
function Util.FixedQuestField(fixes, field, q, original)
    local fix = fixes and fixes[q]
    if fix and fix[field] ~= nil then return fix[field] end
    return original(q)
end

-- Spec 023, R5: quest de livro. Se um objeto que dá a quest solta um item do objetivo, o NPC que
-- dá e também recebe é só a entrega e sai de quem dá. dropsOf(item) devolve os objetos que soltam o item.
function Util.BookStarters(startedBy, finisherNpcs, objectiveItems, dropsOf)
    local npcs, objects = startedBy and startedBy[1], startedBy and startedBy[2]
    if not (npcs and npcs[1] and objects and objects[1] and finisherNpcs and finisherNpcs[1]) then return startedBy end
    local isStartObject = {}
    for _, o in ipairs(objects) do isStartObject[o] = true end
    local book = false
    for _, item in ipairs(objectiveItems or {}) do
        for _, o in ipairs(dropsOf(item) or {}) do if isStartObject[o] then book = true end end
    end
    if not book then return startedBy end
    local finishes = {}
    for _, n in ipairs(finisherNpcs) do finishes[n] = true end
    local kept = {}
    for _, n in ipairs(npcs) do if not finishes[n] then kept[#kept + 1] = n end end
    local out = {}
    for k, v in pairs(startedBy) do out[k] = v end
    out[1] = kept
    return out
end

-- Spec 014, R11: progresso aberto direto? Sem lista de quests do mesmo NPC nos últimos `window` s.
-- lastList = { guid, t } da última lista aberta (GOSSIP_SHOW/QUEST_GREETING), ou nil.
function Util.DirectProgress(lastList, guid, now, window)
    if not (lastList and lastList.guid == guid and lastList.t and now) then return true end
    return now - lastList.t > window
end

-- Spec 006, R19: o jogador saiu da zona do hub seguido (e entrou em outra)?
function Util.LeftHubZone(hubMap, fromZone, toZone)
    return hubMap ~= nil and fromZone ~= nil and toZone ~= nil and hubMap == fromZone and toZone ~= fromZone
end

-- Spec 006, R19: o que fazer ao trocar de zona. "best", o hub guardado da zona nova, ou nil.
function Util.ZoneHubAction(hubMap, fromZone, toZone, savedForTo)
    if not Util.LeftHubZone(hubMap, fromZone, toZone) then return nil end
    return savedForTo or "best"
end

-- Spec 021, R1: dica de lugar. Nomes de área sem repetir, sem vazio e sem a zona; "interior" no fim.
function Util.PlaceHint(names, zone, indoors)
    local out, seen = {}, { [""] = true }
    if zone then seen[zone] = true end
    for _, n in ipairs(names or {}) do
        if type(n) == "string" and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    if indoors then out[#out + 1] = "interior" end
    return #out > 0 and table.concat(out, ", ") or nil
end

-- Spec 021, R2: título da seta com a dica de lugar entre parênteses.
function Util.WithPlace(title, hint)
    if not hint or hint == "" then return title end
    return title .. " (" .. hint .. ")"
end

-- Spec 021, R7: o lugar guardado vale para o ponto? Sem posição guardada, sim; senão, mesmo mapa e perto.
function Util.SamePlace(saved, p, tol)
    if not (saved and saved.mapID and saved.x and saved.y) then return true end
    tol = tol or 3
    return saved.mapID == p.mapID and math.abs(saved.x - p.x) <= tol and math.abs(saved.y - p.y) <= tol
end

-- Spec 021, R3: chave do lugar guardado, igual ao source dos pontos (NPC = número, objeto = "o<id>").
function Util.PlaceKey(kind, id)
    if kind == "object" then return "o" .. tostring(id) end
    return id
end

return Util
