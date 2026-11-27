-- Util.lua: funções puras (testáveis fora do jogo) e guards de API.
local _, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, k) return k end }) -- spec 066 (o arquivo também roda sozinho)
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

-- Spec 044, R7: nodeID conhecidos na janela do mestre de voo (C_TaxiMap.GetAllTaxiNodes).
function Util.TaxiKnown(nodes, states)
    local set = {}
    for _, n in ipairs(nodes or {}) do
        if n.nodeID and (n.state == states.Current or n.state == states.Reachable) then set[n.nodeID] = true end
    end
    return set
end

-- Spec 044, R1: pontos de voo de C_TaxiMap.GetTaxiNodesForMap que a facção pode usar (a dela e os
-- neutros, como o FlightPointDataProvider do jogo). F = Enum.FlightPathFaction. x, y de 0 a 100.
-- known: conjunto do mestre de voo do continente (R7) ou nil; sem ele, o ponto fica a conferir (nil).
-- No Forever, isUndiscovered vem sempre falso (emenda de 21/11/2026): só o verdadeiro vale.
function Util.FlightNodes(nodes, faction, F, known)
    local out = {}
    for _, n in ipairs(nodes or {}) do
        local p = n.position
        local mine = n.faction == F.Neutral or (n.faction == F.Horde and faction == "Horde")
            or (n.faction == F.Alliance and faction == "Alliance")
        local retired = type(n.name) == "string" and n.name:find("^zz") -- R1b: ponto desativado
        -- R1c: fora do mapa consultado (o jogo devolve o continente inteiro num mapa de cidade)
        local inside = p and p.x and p.y and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1
        if mine and inside and not retired then
            local isKnown -- nil: a conferir
            if n.isUndiscovered then isKnown = false
            elseif known then isKnown = known[n.nodeID] == true end
            out[#out + 1] = { id = n.nodeID, name = n.name, x = p.x * 100, y = p.y * 100,
                known = isKnown, atlas = n.atlasName }
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
-- GUID secreto (masmorra, spec 014 R13): não dá para ler o texto, devolve nil.
function Util.EntityFromGUID(guid)
    if type(guid) ~= "string" or Util.IsSecret(guid) then return nil end
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
    if kind == "objetivo" then return L["Objetivo: "] .. text end
    local verb = kind == "pegar" and L["Pegar"] or L["Entregar"]
    if target and target ~= "" then
        return verb .. (kind == "pegar" and L[" com "] or L[" a "]) .. target .. ": " .. text
    end
    return verb .. ": " .. text
end

-- Spec 006, R20 (parecer 013-006-masmorra): área da masmorra quando TODOS os spawns de todas as
-- listas ({ [areaId] = pontos }) ficam em masmorra; false se alguma fonte nasce no mundo (veio, erva, baú).
function Util.DungeonOnly(spawnLists, dungeons)
    local area
    for _, spawns in ipairs(spawnLists or {}) do
        for a in pairs(spawns or {}) do
            if not (dungeons and dungeons[a]) then return false end
            area = area or a
        end
    end
    return area or false
end

-- Spec 064, R5: vale de novo se a última vez foi há mais de `gap` segundos (ou nunca).
function Util.Throttle(last, now, gap)
    return last == nil or now - last > gap
end

-- Spec 059, R1: quest de escolta pelo texto dos objetivos.
function Util.IsEscort(texts)
    for _, t in ipairs(texts or {}) do
        if type(t) == "string" and t:lower():find("escort", 1, true) then return true end
    end
    return false
end

-- Spec 067, R1: quest de evento (defender, proteger, sobreviver, ondas, escolta) pelo texto dos objetivos.
local EVENT_WORDS = { "defend", "protect", "survive", "escort", "wave", "waves" }
local EVENT_PHRASES = { "hold off", "fend off", "after he finishes", "after she finishes", "after it finishes",
    "keep him alive", "keep her alive" }
function Util.IsEvent(texts)
    for _, t in ipairs(texts or {}) do
        if type(t) == "string" then
            local s = t:lower()
            for _, w in ipairs(EVENT_WORDS) do
                if s:find("%f[%a]" .. w .. "%f[%A]") then return true end
            end
            for _, ph in ipairs(EVENT_PHRASES) do
                if s:find(ph, 1, true) then return true end
            end
        end
    end
    return false
end

-- Spec 057, R1: índice do destino pelo nome; sem igual, pelo nome antes da vírgula (sem maiúscula).
function Util.TaxiPick(names, target)
    if not target then return nil end
    for i, n in ipairs(names or {}) do if n == target then return i end end
    local function head(s) return (tostring(s):match("^([^,]+)") or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
    local t = head(target)
    for i, n in ipairs(names or {}) do if head(n) == t then return i end end
    return nil
end

-- Spec 013, R6 (emenda de 24/11/2026): objetivo num objeto diz o que pegar.
function Util.ObjectiveTitle(label, object)
    local title = L["Objetivo: "] .. tostring(label or "?")
    if object and object ~= "" then title = title .. L[" · pegue: "] .. object end
    return title
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

-- Spec 023, R10: todos os NPCs que recebem a quest estão em npcSet? Sem quem recebe, falso.
function Util.FinishedOnlyBy(finisherNpcs, npcSet)
    if not (finisherNpcs and finisherNpcs[1]) then return false end
    for _, n in ipairs(finisherNpcs) do if not npcSet[n] then return false end end
    return true
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

-- Spec 036, R2: chave curta do personagem (8 hexadecimais do hash djb2 do GUID). Não guarda o GUID.
function Util.CharKey(guid)
    local h = 5381
    for i = 1, #(guid or "") do h = (h * 33 + guid:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- Spec 036, R10: anel. Acrescenta no fim e tira do começo até ficar com max.
function Util.RingPush(list, item, max)
    list[#list + 1] = item
    local n = #list
    local over = n - max
    if over == 1 then table.remove(list, 1)
    elseif over > 1 then -- teto baixou de uma vez: desloca tudo numa passada (O(n), não O(n²))
        for i = 1, max do list[i] = list[i + over] end
        for i = max + 1, n do list[i] = nil end
    end
end

return Util
