-- Lfg.lua: regras puras do painel de procurar grupo (spec 037). Sem API do jogo nem db: tudo chega
-- por parâmetro. O adaptador é UI/LfgPanel.lua.
local _, ns = ...
local K = ns and ns.Locale and ns.Locale.K or function(s) return s end -- spec 066
ns = ns or {}
local Lfg = {}
ns.Lfg = Lfg

local FIELDS = { "classe", "nivel", "papel", "atividade" }

-- R1: troca os campos do texto. Campo vazio sai com os parênteses em volta e o espaço antes.
function Lfg.Message(tpl, p)
    local out = tpl
    for _, f in ipairs(FIELDS) do
        local v = p[f]
        if v == nil or v == "" then
            out = out:gsub("%s?%(?{" .. f .. "}%)?", "")
        else
            local s = tostring(v)
            out = out:gsub("{" .. f .. "}", function() return s end)
        end
    end
    return out
end

-- R2: 0 dentro da faixa sugerida; positivo se a atividade é alta demais; negativo se é baixa.
function Lfg.Fit(act, lvl)
    local lo, hi = act.minLevelSuggestion or 0, act.maxLevelSuggestion
    if not hi or hi == 0 then return nil end
    if lvl < lo then return lo - lvl end
    if lvl > hi then return hi - lvl end
    return 0
end

-- Posição de um Fit na ordem: dentro, alta (menor primeiro), baixa (mais perto primeiro), sem faixa.
local function fitRank(fit)
    if fit == nil then return 3, 0 end
    if fit == 0 then return 0, 0 end
    if fit > 0 then return 1, fit end
    return 2, -fit
end

-- R3: atividade de melhor Fit; empate por orderIndex e depois pela ordem da lista.
function Lfg.BestActivity(acts, lvl)
    local best, bc, bd, bo
    for _, a in ipairs(acts or {}) do
        local c, d = fitRank(Lfg.Fit(a, lvl))
        local o = a.orderIndex or math.huge
        if not best or c < bc or (c == bc and (d < bd or (d == bd and o < bo))) then
            best, bc, bd, bo = a, c, d, o
        end
    end
    return best
end

-- R4: a linha pode receber "Chamar"?
function Lfg.CanCall(row, lvl)
    if not row.leaderName or row.isDelisted or row.hasSelf then return false end
    local a = Lfg.BestActivity(row.acts, lvl)
    if not a then return false end -- sem atividade conhecida, o texto sairia sem ela
    if a.maxNumPlayers and a.maxNumPlayers > 0 and (row.numMembers or 0) >= a.maxNumPlayers then return false end
    if a.minLevel and lvl < a.minLevel then return false end
    return true
end

-- R18 (emenda de 28/11/2026, pedido: "na janela de LFM do addon não diz as roles"): o que falta no
-- grupo, de C_LFGList.GetSearchResultMemberCounts (TANK_REMAINING, HEALER_REMAINING, DAMAGER_REMAINING).
Lfg.ROLES = { { "Tank", "TANK_REMAINING" }, { "Healer", "HEALER_REMAINING" }, { "DPS", "DAMAGER_REMAINING" } }
function Lfg.Missing(counts)
    if type(counts) ~= "table" then return nil end
    local out = {}
    for _, r in ipairs(Lfg.ROLES) do
        local n = tonumber(counts[r[2]]) or 0
        if n > 0 then out[#out + 1] = n > 1 and (n .. " " .. r[1]) or r[1] end
    end
    return out
end
-- verdadeiro: há vaga para o papel; falso: não há; nil: sem dado.
function Lfg.NeedsRole(counts, role)
    if type(counts) ~= "table" or not role then return nil end
    for _, r in ipairs(Lfg.ROLES) do
        if r[1] == role then return (tonumber(counts[r[2]]) or 0) > 0 end
    end
    return nil
end

-- R5: grupos antes de sozinhos; depois Fit, não chamado, anúncio mais novo e searchResultID.
-- R18: entre os grupos, os que têm vaga para o papel do jogador primeiro; os sem vaga por último.
function Lfg.Sort(rows, lvl, calls, role)
    local keyed = {}
    for _, r in ipairs(rows) do
        if not r.hasSelf then
            local a = Lfg.BestActivity(r.acts, lvl)
            local c, d = fitRank(a and Lfg.Fit(a, lvl))
            local need = Lfg.NeedsRole(r.roles, role)
            keyed[#keyed + 1] = { r = r, solo = (r.numMembers or 0) <= 1 and 1 or 0, c = c, d = d,
                need = need == true and 0 or (need == nil and 1 or 2),
                called = calls and r.key and calls[r.key] and 1 or 0, age = r.age or 0, id = r.searchResultID or 0 }
        end
    end
    table.sort(keyed, function(x, y)
        if x.solo ~= y.solo then return x.solo < y.solo end
        if x.need ~= y.need then return x.need < y.need end
        if x.c ~= y.c then return x.c < y.c end
        if x.d ~= y.d then return x.d < y.d end
        if x.called ~= y.called then return x.called < y.called end
        if x.age ~= y.age then return x.age < y.age end
        return x.id < y.id
    end)
    local out = {}
    for i, k in ipairs(keyed) do out[i] = k.r end
    return out
end

-- R6: chave do líder; reino sem espaços nem hífens, omitido quando é o do jogador.
local function realmKey(realm) return (realm or ""):gsub("[%s%-]", "") end

function Lfg.Key(name, realm, myRealm)
    local base, fromName = name:match("^([^%-]+)%-(.+)$")
    if base then name, realm = base, realm or fromName end
    local r = realmKey(realm)
    if r == "" or r == realmKey(myRealm) then return name end
    return name .. "-" .. r
end

function Lfg.Call(calls, key, now) calls[key] = now end
function Lfg.Clear(calls, key) calls[key] = nil end
function Lfg.ClearAll(calls) for k in pairs(calls) do calls[k] = nil end end

function Lfg.Status(calls, key, now, ttl)
    local t = calls[key]
    if not t then return nil end
    local age = now - t
    return { state = age > ttl and K("sem resposta") or K("chamado"), age = age }
end

-- R7: dá para ler a lista e chamar agora?
local BLOCKING = { "Chat", "Combat", "Encounter" }
function Lfg.CanRead(states, inLockdown, inCombat)
    if inLockdown or inCombat then return false end
    for _, t in ipairs(BLOCKING) do
        local s = states and states[t]
        if s == "Activating" or s == "Active" then return false end
    end
    return true
end

-- R8: papel salvo no LFG da Blizzard (se só um) ou o padrão da classe.
local ROLE_NAMES = { tank = "Tank", healer = "Healer", dps = "DPS" }
local DPS_ONLY = { WARLOCK = true, MAGE = true, ROGUE = true, HUNTER = true }
function Lfg.DefaultRole(saved, classFile)
    local only, n = nil, 0
    for k, label in pairs(ROLE_NAMES) do
        if saved and saved[k] then only, n = label, n + 1 end
    end
    if n == 1 then return only end
    if DPS_ONLY[classFile] then return "DPS" end
    return nil
end

return Lfg
