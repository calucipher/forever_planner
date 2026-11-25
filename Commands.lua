-- Commands.lua: registro único dos comandos (spec 040). O /fp, a aba Ferramentas e o menu "+"
-- leem esta lista. Find, Help, Missing, Percent e Positive são puras; as ações chamam os módulos
-- na hora do clique.
local _, ns = ...
local Commands = {}
ns.Commands = Commands

Commands.sections = { "Rota", "Automações", "Personagem", "Grupo", "Interface", "Registro" } -- spec 058, R1

local function FP() return ns.FP end
local function db() return ns.FP.db end

-- R6: agressividade (0–100) e números positivos (TTK).
function Commands.Percent(v)
    local n = tonumber(v)
    if not n then return nil end
    return math.max(0, math.min(100, n))
end
function Commands.Positive(v)
    local n = tonumber(v)
    if not n or n <= 0 then return nil end
    return n
end

-- Spec 058, R2: chave de automação guardada em db[key]; on = ligada por padrão (nil conta como on).
local function toggle(id, label, key, on, tip)
    local function state()
        local v = db()[key]
        if on then return v ~= false end
        return v == true
    end
    return { id = id, label = label, section = "Automações", kind = "liga", tip = tip, state = state,
        run = function()
            db()[key] = not state()
            FP().Print(label .. ": " .. (state() and "ligado" or "desligado") .. ".")
            if ns.Guide then ns.Guide.Invalidate() end
            FP().Fire("CHANGED")
        end }
end

local function stopGps() ns.Gps.Clear(); db().following = nil; db().guide = nil; FP().Fire("CHANGED") end

local function listUnavailable()
    local n = 0
    for q in pairs(db().unavailable or {}) do
        n = n + 1
        FP().Print(string.format("[%d] %s", q, ns.Data.Q and ns.Data.Q.name(q) or "?"))
    end
    if n == 0 then FP().Print("nenhuma quest marcada como indisponível.") end
end

local function listCaves()
    local n = 0
    for _, list in pairs(ns.Gps.LearnedCaves()) do
        for _, e in ipairs(list) do
            n = n + 1
            FP().Print(string.format("%s · mapa %s · %s, %s · %d pontos", tostring(e.name or "?"), tostring(e.m or "?"),
                tostring(e.mx or "?"), tostring(e.my or "?"), #(e.pts or {}) / 2))
        end
    end
    if n == 0 then FP().Print("nenhuma entrada aprendida ainda. Entre numa caverna andando.") end
end

local function clearCaves()
    local caves = ns.Gps.LearnedCaves()
    for c in pairs(caves) do caves[c] = nil end
    ns.Gps.UpdateDoor()
    FP().Print("entradas aprendidas apagadas.")
end

local function listBags()
    local list = ns.Data.Q and ns.Data.ready and ns.Data.BagQuests(UnitLevel("player")) or {}
    if #list == 0 then FP().Print("nenhuma quest de bolsa para este personagem (ou dados ainda carregando).") end
    for _, b in ipairs(list) do
        local status = b.step and string.format("começa por %s (%s, %s)", b.step.name, b.step.zone, b.step.status)
            or b.status -- spec 010, R10
        FP().Print(string.format("[%d] %s — %s%s (%s) — %s%s", b.level, b.name, b.itemName or "bolsa",
            b.bonus and " (bônus de XP)" or "", b.zone, status, b.skipped and " — dispensada" or ""))
    end
end

local function listMacros()
    for key, sp in pairs(ns.Macros.spells) do
        local name = ns.Macros.Resolve(key)
        FP().Print(string.format("%s (ID %d): %s", key, sp.id,
            name and ("|cFF73E65A" .. name .. "|r") or "|cFF888888não conhecido|r"))
    end
end

local function setPreset(rest)
    local names = ns.Weights.PresetNames()
    if rest == nil then -- botão: troca para o próximo perfil
        local cur = 1
        for i, n in ipairs(names) do if n == db().preset then cur = i end end
        rest = names[cur % #names + 1]
    end
    if ns.Weights.presets[rest] then
        db().preset = rest; ns.Scoring.ClearCache(); FP().Fire("CHANGED")
        FP().Print("perfil de pesos:", rest)
    else
        FP().Print("perfis:", table.concat(names, ", "))
    end
end

local function setAggressiveness(rest)
    local v = Commands.Percent(rest)
    if not v then FP().Print("agressividade: use um número de 0 a 100."); return end
    db().threshold = v / 100
    ns.Guide.Invalidate(); FP().Fire("CHANGED")
    FP().Print("agressividade:", math.floor(db().threshold * 100) .. "%")
end

local function setTTK(rest)
    local v = Commands.Positive(rest)
    if not v then FP().Print("TTK: use um número de segundos maior que 0."); return end
    db().ttk = v; FP().Fire("CHANGED"); FP().Print("TTK:", v, "s")
end

local function onOff(v) return v and "ligado" or "desligado" end

-- Spec 047, R7 e R8: a trilha no chat, calculada em corrotina e fora de combate.
local function printTrail(L)
    local started = FP().RunCoroutine("trailCmd", function(yield) return ns.LevelGuide.Trail(L, yield) end, function(ok, tr)
        if not ok then FP().Debug("trilha falhou: " .. tostring(tr)); tr = nil end
        if not tr then FP().Print("trilha: o catálogo de zonas ainda está carregando."); return end
        FP().Print(string.format("trilha %d–%d (estimativa):", tr.lo, tr.hi))
        if #tr.steps == 0 then FP().Print("  nenhuma zona com quests da sua facção nesta faixa.") end
        for i, st in ipairs(tr.steps) do
            for j, z in ipairs(st.zones) do
                FP().Print(string.format("  %s%s (%s) · %d quests · %s%s", j == 1 and (i .. ". ") or "   ou ",
                    ns.Guide.AreaName(z.zone), ns.Zones.FormatRange(z.lo, z.hi), z.quests,
                    z.plan and ns.Travel.Describe(z.plan) or "viagem ?",
                    z.red > 0 and string.format(" · %d ponto(s) de voo a abrir", z.red) or ""))
            end
        end
        if tr.hearth then FP().Print("  marque o lar: " .. tostring(tr.hearth.name) .. (tr.hearth.place and (", " .. tr.hearth.place) or "")) end
        if #tr.dungeons > 0 then
            local names = {}
            for _, d in ipairs(tr.dungeons) do names[#names + 1] = d.name end
            FP().Print("  masmorras: " .. table.concat(names, ", "))
        end
    end)
    if not started then FP().Print("trilha: já calculando; aguarde.") end
end

-- R1: { id, label, tip, section, kind, run(rest), state(), input, arg, value(), confirma }
-- confirma: a ação abre uma confirmação; a resposta dela sai no chat (R4a).
Commands.list = {
    -- Rota
    { id = "guia", label = "Recalcular rota", section = "Rota", kind = "acao",
        tip = "Escolhe o hub de maior XP/h desta zona e refaz a rota a partir de onde você está",
        run = function() ns.Guide.FollowBest() end },
    { id = "next", label = "Seguir a melhor quest", section = "Rota", kind = "acao",
        tip = "Aponta a seta para a melhor quest sozinha (sem hub)", run = function() ns.Planner.FollowBest() end },
    { id = "entregar", label = "Ir entregar", section = "Rota", kind = "acao",
        tip = "Hub mais perto com quests prontas para entregar", run = function() ns.Guide.FollowBest("turnin") end },
    { id = "voo", label = "Ponto de voo", section = "Rota", kind = "acao",
        tip = "Aponta a seta para o ponto de voo descoberto mais perto", run = function() ns.Planner.FollowFlightPoint() end },
    { id = "clear", label = "Parar GPS", section = "Rota", kind = "acao", alias = { "stop" },
        tip = "Tira a seta e para de seguir quest ou hub", run = stopGps },
    { id = "limpar", label = "Limpar o log", section = "Rota", kind = "acao",
        tip = "Mostra quests que não valem a pena; abandona só se você confirmar", run = function() ns.QuickMenu.ShowCleanup() end },
    { id = "zonas", label = "Zonas", section = "Rota", kind = "lista",
        tip = "Sugestão de zona (ficar, trocar ou grind) e a faixa de nível de cada zona", run = function() ns.Guide.PrintZones() end },
    { id = "trilha", label = "Trilha da faixa", section = "Rota", kind = "lista", arg = "[nível]",
        tip = "Zonas da faixa de nível em ordem, com alternativas, viagem, pontos de voo e lar (spec 047)",
        run = function(rest) printTrail(tonumber(rest)) end },
    { id = "passagens", label = "Passagens da zona", section = "Rota", kind = "lista", arg = "[limpar]",
        tip = "Passagens a pé desta zona para as vizinhas (estrada, relevo ou aprendida); 'limpar' apaga as aprendidas (spec 049)",
        run = function(rest) ns.Gps.PrintGates(rest) end },
    { id = "gear", label = "Gear", section = "Personagem", kind = "lista",
        tip = "Melhor upgrade por slot até 3 níveis à frente: quest, cadeia, masmorra, vendedor ou AH (spec 048)",
        run = function() ns.GearGuide.Print() end },
    { id = "grupo quests", label = "Quests de grupo", section = "Rota", kind = "lista", arg = "[limpar]",
        tip = "Quests de elite ou masmorra do log e a escolha de cada uma (pular ou fazer em grupo); 'limpar' pergunta de novo (spec 054)",
        run = function(rest) ns.Guide.PrintGroupQuests(rest) end },
    { id = "indisponiveis", label = "Indisponíveis", section = "Rota", kind = "lista",
        tip = "Quests que o jogo não ofereceu e saíram do plano", run = listUnavailable },
    { id = "indisponiveis limpar", label = "Reativar quests", section = "Rota", kind = "acao",
        tip = "Desfaz as marcas de quest indisponível (pede confirmação). Para só atualizar, 'Recalcular rota'.",
        confirma = true, run = function() ns.Planner.ConfirmClearUnavailable("comando") end },
    { id = "entradas", label = "Entradas de caverna", section = "Rota", kind = "lista",
        tip = "Entradas de caverna que o jogo gravou (spec 038)", run = listCaves },
    { id = "entradas limpar", label = "Apagar entradas", section = "Rota", kind = "acao",
        tip = "Apaga as entradas de caverna aprendidas", run = clearCaves },
    { id = "masmorras", label = "Masmorras para você", section = "Rota", kind = "lista",
        tip = "Masmorras do seu nível: entrada, meeting stone e attune (spec 041)",
        run = function() ns.DungeonGuide.PrintList(false) end },
    { id = "masmorras zona", label = "Masmorras do mapa", section = "Rota", kind = "lista",
        tip = "Todas as masmorras com entrada ou pedra no mapa da zona atual",
        run = function() ns.DungeonGuide.PrintList(true) end },
    { id = "masmorras limpar", label = "Apagar entradas de masmorra", section = "Rota", kind = "acao",
        tip = "Apaga as entradas de masmorra que o jogo gravou", run = function() ns.DungeonGuide.ClearLearned() end },
    -- Personagem
    { id = "bolsa", label = "Seguir bolsa", section = "Personagem", kind = "acao",
        tip = "Segue a melhor quest que dá bolsa (zona atual primeiro)", run = function() ns.Guide.FollowBag() end },
    { id = "bolsas", label = "Quests de bolsa", section = "Personagem", kind = "lista",
        tip = "Lista as quests de bolsa deste personagem", run = listBags },
    { id = "classe", label = "Quests de classe", section = "Personagem", kind = "lista",
        tip = "Lista as quests de classe e segue a melhor", run = function() ns.ClassGuide.PrintList(); ns.ClassGuide.Follow() end },
    { id = "armas", label = "Armas", section = "Personagem", kind = "acao",
        tip = "Escolhe as armas que você usa e aponta a seta para o treinador", run = function() ns.QuickMenu.ShowWeapons() end },
    { id = "treinar", label = "Treinar", section = "Personagem", kind = "acao",
        tip = "Seta no treinador da classe mais perto e a lista do que falta aprender, com os novos do Forever (spec 051)",
        run = function() ns.ClassGuide.FollowClassTrainer() end },
    { id = "treinar tudo", label = "Treinar tudo", section = "Personagem", kind = "acao",
        tip = "Com a janela do treinador aberta, compra todos os feitiços disponíveis que o dinheiro der (spec 055)",
        run = function() ns.ClassGuide.TrainAll() end },
    { id = "ranks", label = "Ranks velhos na barra", section = "Personagem", kind = "lista", arg = "[trocar]",
        tip = "Botões da barra com rank velho de feitiço; 'trocar' põe o rank novo (fora de combate) (spec 055)",
        run = function(rest) ns.ClassGuide.Ranks(rest) end },
    { id = "marcos", label = "Marcos da classe", section = "Personagem", kind = "lista",
        tip = "Feitiços e armas por nível da sua classe", run = function() ns.ClassGuide.PrintMilestones(); ns.ClassGuide.WarnWeapons() end },
    { id = "macros", label = "Feitiços das macros", section = "Personagem", kind = "lista",
        tip = "Quais feitiços das macros você já conhece", run = listMacros },
    { id = "calib", label = "Calibração", section = "Personagem", kind = "lista",
        tip = "Tempo por morte, fator de XP e tolerância de mobs altos, com a fonte", run = function() FP().PrintCalib() end },
    { id = "preset", label = "Perfil de pesos", section = "Personagem", kind = "valor", input = "opcoes", arg = "<nome>",
        tip = "Troca o perfil de pesos dos itens", run = setPreset, value = function() return db().preset end },
    { id = "agressividade", label = "Agressividade (0–100)", section = "Personagem", kind = "valor", input = "numero", arg = "<0-100>",
        tip = "Quanto o guia corta quest que rende pouco", run = setAggressiveness,
        value = function() return math.floor((db().threshold or 0.5) * 100) end },
    { id = "ttk", label = "TTK (segundos)", section = "Personagem", kind = "valor", input = "numero", arg = "<seg>",
        tip = "Tempo por morte usado nas contas, em segundos (maior que 0)", run = setTTK, value = function() return db().ttk end },
    { id = "stats", label = "Comparar item", section = "Personagem", kind = "valor", input = "texto", arg = "<link>",
        tip = "Shift+clique num item com o campo em foco, ou o ID do item", run = function(rest) ns.Scoring.Debug(rest) end },
    -- Grupo
    { id = "grupo", label = "Compartilhar quests", section = "Grupo", kind = "acao",
        tip = "Compartilha as quests do log com o grupo e manda um resumo do que falta", run = function() ns.Group.ShareAll() end },
    { id = "grupo avisos", label = "Avisos no grupo", section = "Grupo", kind = "liga",
        tip = "Avisa o grupo quando um objetivo avança", run = function() ns.Group.ToggleAnnounce() end,
        state = function() return db().groupAnnounce ~= false end },
    { id = "lfg", label = "Procurar grupo", section = "Grupo", kind = "acao",
        tip = "Abre o painel de procurar grupo (spec 037)", run = function(rest) ns.LfgPanel.Command(rest) end },
    { id = "lfg texto", label = "Texto para grupo", section = "Grupo", kind = "valor", input = "texto", arg = "<texto>",
        tip = "Whisper para o líder de grupo. Campos: {classe} {nivel} {papel} {atividade}",
        run = function(rest) ns.LfgPanel.Command("texto " .. (rest or "")) end, value = function() return db().lfgWhisper end },
    { id = "lfg solo", label = "Texto para sozinho", section = "Grupo", kind = "valor", input = "texto", arg = "<texto>",
        tip = "Whisper para quem está sozinho", run = function(rest) ns.LfgPanel.Command("solo " .. (rest or "")) end,
        value = function() return db().lfgWhisperSolo end },
    { id = "lfg padrao", label = "Textos padrão do LFG", section = "Grupo", kind = "acao",
        tip = "Volta os textos do LFG ao padrão", run = function() ns.LfgPanel.Command("padrao") end },
    { id = "lfg copiar", label = "LFG só copia", section = "Grupo", kind = "acao",
        tip = "'Chamar' passa a só copiar o texto", run = function() ns.LfgPanel.Command("copiar") end },
    -- Interface
    -- Automações (spec 058)
    { id = "auto", label = "Automações de quest (geral)", section = "Automações", kind = "liga",
        tip = "Chave geral: desligada, não aceita, não entrega e não escolhe recompensa", run = function() ns.Auto.Toggle() end,
        state = function() return db().auto ~= false end },
    toggle("auto aceitar", "Aceitar sozinho", "autoAccept", true, "Aceita só as quests do plano: hubs da zona, a seguida e a continuação da que você entregou"),
    toggle("auto entregar", "Entregar sozinho", "autoTurnIn", true, "Completa e entrega a quest pronta"),
    toggle("auto recompensa", "Escolher recompensa", "autoReward", true, "Escolhe o maior upgrade entre as recompensas"),
    toggle("auto seguir", "Seguir a próxima", "autoNext", true, "Depois de entregar, a seta segue a próxima quest ou hub"),
    toggle("auto grupo", "Perguntar quest de grupo", "groupAsk", true, "Ao aceitar quest de elite ou masmorra, pergunta: pular ou fazer em grupo (spec 054)"),
    toggle("auto voo rota", "Abrir pontos de voo na rota", "flightStops", true, "Paradas 'Abrir ponto de voo' no circuito (spec 052)"),
    toggle("auto entrega caminho", "Entrega no caminho", "turnInsOnTheWay", true, "Quest pronta de outro hub com o NPC no caminho entra no circuito (spec 053)"),
    toggle("voo marcar", "Marcar o destino do voo", "taxiMark", true, "Ao abrir o mestre de voo, destaca o destino da seta (spec 057)"),
    toggle("voo auto", "Voar sozinho", "taxiAuto", false, "Ao abrir o mestre de voo, voa para o destino marcado (spec 057)"),
    { id = "minimapa", label = "Botão no minimapa", section = "Interface", kind = "liga", alias = { "minimap" },
        tip = "Mostra ou esconde o botão no minimapa", run = function() ns.MinimapButton.Toggle() end,
        state = function() return not (db().minimap and db().minimap.hide) end },
    { id = "masmorras pinos", label = "Masmorras no mapa", section = "Interface", kind = "liga",
        tip = "Mostra ou esconde os pinos de entrada de masmorra e meeting stone no mapa-múndi (spec 041)",
        run = function()
            local d = ns.DungeonGuide.db()
            d.pins = d.pins == false
            ns.FP.Fire("DUNGEONS")
        end,
        state = function() return ns.DungeonGuide.db().pins ~= false end },
    { id = "voos", label = "Pontos de voo no mapa", section = "Interface", kind = "liga",
        tip = "Pontos de voo no mapa-múndi: verde descoberto, vermelho a descobrir (spec 044)",
        run = function()
            db().flightPins = db().flightPins == false
            FP().Print("pontos de voo no mapa:", onOff(db().flightPins ~= false))
            if ns.FlightPins then ns.FlightPins.Refresh(true) end
        end,
        state = function() return db().flightPins ~= false end },
    -- Registro
    { id = "diario", label = "Diário", section = "Registro", kind = "liga", arg = "[on|off]",
        tip = "Diário do que você faz no jogo (spec 036). Sem argumento no comando: o resumo",
        run = function(rest)
            if rest == nil then rest = ns.Journal.IsOn() and "off" or "on" end -- botão: liga/desliga
            ns.Journal.Command(rest)
        end, state = function() return ns.Journal.IsOn() end },
    { id = "diario limpar", label = "Apagar diário", section = "Registro", kind = "acao",
        tip = "Apaga o diário (pede confirmação). Importe antes com tools/journal.py", confirma = true,
        run = function() ns.Journal.Command("limpar") end },
    { id = "debug", label = "Modo debug", section = "Registro", kind = "liga",
        tip = "Grava o registro de debug (sai no /reload ou logout)",
        run = function()
            db().debug = not db().debug
            FP().Print("modo debug:", db().debug and "ligado (registro gravado no /reload ou logout)" or "desligado")
        end, state = function() return db().debug == true end },
    { id = "debug chat", label = "Debug no chat", section = "Registro", kind = "liga",
        tip = "Mostra o debug também no chat",
        run = function() db().debugChat = not db().debugChat; FP().Print("debug no chat:", onOff(db().debugChat)) end,
        state = function() return db().debugChat == true end },
    { id = "diag", label = "Diagnóstico", section = "Registro", kind = "lista",
        tip = "Estado dos dados e do cálculo, para relatar problema", run = function() ns.DebugTools.Diag() end },
    { id = "cena", label = "Gravar cena de voo", section = "Registro", kind = "acao",
        tip = "Grava a situação do último cálculo de ponto de voo para virar teste (spec 052); depois /reload",
        run = function() ns.Guide.SaveScene() end },
}

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- R3: comando pelo id (ou apelido) mais longo que casa com o começo da mensagem, em palavra inteira.
function Commands.Find(list, msg)
    local raw = trim(msg):gsub("%s+", " ") -- espaços repetidos contam como um
    msg = raw:lower()
    local best, bestLen
    for _, c in ipairs(list) do
        local names = { c.id }
        for _, a in ipairs(c.alias or {}) do names[#names + 1] = a end
        for _, name in ipairs(names) do
            local n = #name
            if msg:sub(1, n) == name and (#msg == n or msg:sub(n + 1, n + 1) == " ") and (not bestLen or n > bestLen) then
                best, bestLen = c, n
            end
        end
    end
    if not best then return nil end
    return best, (raw:sub(bestLen + 2):gsub("^%s+", "")) -- o argumento mantém maiúsculas (textos do LFG)
end

function Commands.Help(list)
    local out = { "/fp (janela)" }
    for _, c in ipairs(list) do out[#out + 1] = "/fp " .. c.id .. (c.arg and (" " .. c.arg) or "") end
    return "comandos: " .. table.concat(out, ", ")
end

-- R2: comandos sem seção conhecida ou sem ação.
function Commands.Missing(list, sections)
    local known, out = {}, {}
    for _, s in ipairs(sections or {}) do known[s] = true end
    for _, c in ipairs(list) do
        if not known[c.section] or type(c.run) ~= "function" then out[#out + 1] = tostring(c.id) end
    end
    return out
end

-- R4: roda fn e devolve as linhas que ela mandaria ao chat por FP.Print, sem mandar.
function Commands.Capture(fn)
    local fp = ns.FP
    local orig, out = fp.Print, {}
    fp.Print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(parts, " ")
    end
    local ok, err = xpcall(fn, function(e)
        return tostring(e) .. (_G.debugstack and ("\n" .. _G.debugstack(2)) or "")
    end)
    fp.Print = orig
    if not ok then
        out[#out + 1] = "|cFFFF6666erro:|r " .. tostring(err):match("^[^\n]*")
        if fp.LogError then fp.LogError("aba Ferramentas: " .. tostring(err)) end
    end
    return out
end

-- /fp: despacha pelo registro (R3). Argumento vazio vira "" (o botão passa nil).
function Commands.Run(msg)
    local c, rest = Commands.Find(Commands.list, msg)
    if not c then ns.FP.Print(Commands.Help(Commands.list)); return end
    c.run(rest or "")
end

return Commands
