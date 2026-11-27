-- Commands.lua: registro único dos comandos (spec 040). O /fp, a aba Ferramentas e o menu "+"
-- leem esta lista. Find, Help, Missing, Percent e Positive são puras; as ações chamam os módulos
-- na hora do clique.
local _, ns = ...
local L, K = ns.L, ns.Locale.K -- spec 066
local Commands = {}
ns.Commands = Commands

Commands.sections = { K("Rota"), K("Automações"), K("Personagem"), K("Grupo"), K("Interface"), K("Registro") } -- spec 058, R1

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
    return { id = id, label = label, section = K("Automações"), kind = "liga", tip = tip, state = state,
        run = function()
            db()[key] = not state()
            FP().Print(L[label] .. ": " .. (state() and L["ligado"] or L["desligado"]) .. ".")
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
    if n == 0 then FP().Print(L["nenhuma quest marcada como indisponível."]) end
end

local function listCaves()
    local n = 0
    for _, list in pairs(ns.Gps.LearnedCaves()) do
        for _, e in ipairs(list) do
            n = n + 1
            FP().Print(string.format(L["%s · mapa %s · %s, %s · %d pontos"], tostring(e.name or "?"), tostring(e.m or "?"),
                tostring(e.mx or "?"), tostring(e.my or "?"), #(e.pts or {}) / 2))
        end
    end
    if n == 0 then FP().Print(L["nenhuma entrada aprendida ainda. Entre numa caverna andando."]) end
end

local function clearCaves()
    local caves = ns.Gps.LearnedCaves()
    for c in pairs(caves) do caves[c] = nil end
    ns.Gps.UpdateDoor()
    FP().Print(L["entradas aprendidas apagadas."])
end

local function listBags()
    local list = ns.Data.Q and ns.Data.ready and ns.Data.BagQuests(UnitLevel("player")) or {}
    if #list == 0 then FP().Print(L["nenhuma quest de bolsa para este personagem (ou dados ainda carregando)."]) end
    for _, b in ipairs(list) do
        local status = b.step and string.format(L["começa por %s (%s, %s)"], b.step.name, b.step.zone, L[b.step.status])
            or L[b.status] -- spec 010, R10
        FP().Print(string.format("[%d] %s — %s%s (%s) — %s%s", b.level, b.name, b.itemName or L["bolsa"],
            b.bonus and L[" (bônus de XP)"] or "", b.zone, status, b.skipped and L[" — dispensada"] or ""))
    end
end

local function listMacros()
    for key, sp in pairs(ns.Macros.spells) do
        local name = ns.Macros.Resolve(key)
        FP().Print(string.format("%s (ID %d): %s", key, sp.id,
            name and ("|cFF73E65A" .. name .. "|r") or L["|cFF888888não conhecido|r"]))
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
        FP().Print(L["perfil de pesos:"], rest)
    else
        FP().Print(L["perfis:"], table.concat(names, ", "))
    end
end

local function setAggressiveness(rest)
    local v = Commands.Percent(rest)
    if not v then FP().Print(L["agressividade: use um número de 0 a 100."]); return end
    db().threshold = v / 100
    ns.Guide.Invalidate(); FP().Fire("CHANGED")
    FP().Print(L["agressividade:"], math.floor(db().threshold * 100) .. "%")
end

local function setTTK(rest)
    local v = Commands.Positive(rest)
    if not v then FP().Print(L["TTK: use um número de segundos maior que 0."]); return end
    db().ttk = v; FP().Fire("CHANGED"); FP().Print("TTK:", v, "s")
end

local function onOff(v) return v and L["ligado"] or L["desligado"] end

-- Spec 066, R3: /fp idioma pt|en|auto; sem argumento (botão), troca auto > pt > en.
local function language()
    local W = _G.ForeverPlannerWorld
    return type(W) == "table" and W.idioma or "auto"
end
local function setLanguage(rest)
    rest = rest and rest:lower() or nil
    if rest == nil then rest = ({ auto = "pt", pt = "en", en = "auto" })[language()] or "auto" end
    if rest ~= "pt" and rest ~= "en" and rest ~= "auto" then
        FP().Print(string.format(ns.L["idioma atual: %s. Use /fp idioma pt, en ou auto."], language()))
        return
    end
    if type(_G.ForeverPlannerWorld) ~= "table" then _G.ForeverPlannerWorld = {} end
    _G.ForeverPlannerWorld.idioma = rest ~= "auto" and rest or nil
    FP().Print(string.format(ns.L["idioma: %s (vale depois do /reload)"], rest))
    FP().Fire("CHANGED")
end

-- Spec 047, R7 e R8: a trilha no chat, calculada em corrotina e fora de combate.
local function printTrail(lvl)
    local started = FP().RunCoroutine("trailCmd", function(yield) return ns.LevelGuide.Trail(lvl, yield) end, function(ok, tr)
        if not ok then FP().Debug("trilha falhou: " .. tostring(tr)); tr = nil end
        if not tr then FP().Print(L["trilha: o catálogo de zonas ainda está carregando."]); return end
        FP().Print(string.format(L["trilha %d–%d (estimativa):"], tr.lo, tr.hi))
        if #tr.steps == 0 then FP().Print(L["  nenhuma zona com quests da sua facção nesta faixa."]) end
        for i, st in ipairs(tr.steps) do
            for j, z in ipairs(st.zones) do
                FP().Print(string.format("  %s%s (%s) · %d quests · %s%s", j == 1 and (i .. ". ") or L["   ou "],
                    ns.Guide.AreaName(z.zone), ns.Zones.FormatRange(z.lo, z.hi), z.quests,
                    z.plan and ns.Travel.Describe(z.plan) or L["viagem ?"],
                    z.red > 0 and string.format(L[" · %d ponto(s) de voo a abrir"], z.red) or ""))
            end
        end
        if tr.hearth then FP().Print(L["  marque o lar: "] .. tostring(tr.hearth.name) .. (tr.hearth.place and (", " .. tr.hearth.place) or "")) end
        if #tr.dungeons > 0 then
            local names = {}
            for _, d in ipairs(tr.dungeons) do names[#names + 1] = d.name end
            FP().Print(L["  masmorras: "] .. table.concat(names, ", "))
        end
    end)
    if not started then FP().Print(L["trilha: já calculando; aguarde."]) end
end

-- R1: { id, label, tip, section, kind, run(rest), state(), input, arg, value(), confirma }
-- confirma: a ação abre uma confirmação; a resposta dela sai no chat (R4a).
Commands.list = {
    -- Rota
    { id = "guia", label = K("Recalcular rota"), section = K("Rota"), kind = "acao",
        tip = K("Escolhe o hub de maior XP/h desta zona e refaz a rota a partir de onde você está"),
        run = function() ns.Guide.FollowBest() end },
    { id = "next", label = K("Seguir a melhor quest"), section = K("Rota"), kind = "acao",
        tip = K("Aponta a seta para a melhor quest sozinha (sem hub)"), run = function() ns.Planner.FollowBest() end },
    { id = "pular", label = K("Pular esta parada"), section = K("Rota"), kind = "acao",
        tip = K("A parada atual do hub sai da rota por 10 minutos (NPC ausente, área cheia) (spec 059, R7)"),
        run = function() ns.Guide.SkipCurrent() end },
    { id = "essenciais ir", label = K("Essenciais"), section = K("Personagem"), kind = "acao",
        tip = K("Seta no primeiro essencial pendente: treino, bolsa, pedra de lar, ponto de voo... (spec 062)"),
        run = function() ns.EssentialsGuide.FollowFirst() end },
    { id = "entregar", label = K("Ir entregar"), section = K("Rota"), kind = "acao",
        tip = K("Hub mais perto com quests prontas para entregar"), run = function() ns.Guide.FollowBest("turnin") end },
    { id = "voo", label = K("Ponto de voo"), section = K("Rota"), kind = "acao",
        tip = K("Aponta a seta para o ponto de voo descoberto mais perto"), run = function() ns.Planner.FollowFlightPoint() end },
    { id = "clear", label = K("Parar GPS"), section = K("Rota"), kind = "acao", alias = { "stop" },
        tip = K("Tira a seta e para de seguir quest ou hub"), run = stopGps },
    { id = "limpar", label = K("Limpar o log"), section = K("Rota"), kind = "acao",
        tip = K("Mostra quests que não valem a pena; abandona só se você confirmar"), run = function() ns.QuickMenu.ShowCleanup() end },
    { id = "zonas", label = K("Zonas"), section = K("Rota"), kind = "lista",
        tip = K("Sugestão de zona (ficar, trocar ou grind) e a faixa de nível de cada zona"), run = function() ns.Guide.PrintZones() end },
    { id = "trilha", label = K("Trilha da faixa"), section = K("Rota"), kind = "lista", arg = "[nível]",
        tip = K("Zonas da faixa de nível em ordem, com alternativas, viagem, pontos de voo e lar (spec 047)"),
        run = function(rest) printTrail(tonumber(rest)) end },
    { id = "passagens", label = K("Passagens da zona"), section = K("Rota"), kind = "lista", arg = "[limpar]",
        tip = K("Passagens a pé desta zona para as vizinhas (estrada, relevo ou aprendida); 'limpar' apaga as aprendidas (spec 049)"),
        run = function(rest) ns.Gps.PrintGates(rest) end },
    { id = "gear", label = K("Gear"), section = K("Personagem"), kind = "lista",
        tip = K("Melhor upgrade por slot até 3 níveis à frente: quest, cadeia, masmorra, vendedor ou AH (spec 048)"),
        run = function() ns.GearGuide.Print() end },
    { id = "grupo quests", label = K("Quests de grupo"), section = K("Rota"), kind = "lista", arg = "[limpar]",
        tip = K("Quests de elite ou masmorra do log e a escolha de cada uma (pular ou fazer em grupo); 'limpar' pergunta de novo (spec 054)"),
        run = function(rest) ns.Guide.PrintGroupQuests(rest) end },
    { id = "rota zona", label = K("Rota da zona"), section = K("Rota"), kind = "liga",
        tip = K("Junta as quests de todos os hubs da zona numa rota só, sem ir e voltar entre hubs (spec 068)"),
        state = function() return db().zoneRoute ~= false end,
        run = function()
            db().zoneRoute = db().zoneRoute == false
            FP().Print(L["rota da zona:"], onOff(db().zoneRoute ~= false))
            if ns.Guide then ns.Guide.Invalidate() end
            FP().Fire("CHANGED")
        end },
    { id = "modo facil", label = K("Modo fácil"), section = K("Rota"), kind = "liga",
        tip = K("Prefere mobs de 4 a 2 níveis abaixo: quest com mobs no seu nível ou acima sai da rota até você subir (spec 063)"),
        state = function() return db().easyMode == true end,
        run = function()
            db().easyMode = db().easyMode ~= true
            FP().Print(L["modo fácil:"], onOff(db().easyMode))
            if ns.Guide then ns.Guide.Invalidate() end
            FP().Fire("CHANGED")
        end },
    { id = "indisponiveis", label = K("Indisponíveis"), section = K("Rota"), kind = "lista",
        tip = K("Quests que o jogo não ofereceu e saíram do plano"), run = listUnavailable },
    { id = "indisponiveis limpar", label = K("Reativar quests"), section = K("Rota"), kind = "acao",
        tip = K("Desfaz as marcas de quest indisponível (pede confirmação). Para só atualizar, 'Recalcular rota'."),
        confirma = true, run = function() ns.Planner.ConfirmClearUnavailable("comando") end },
    { id = "entradas", label = K("Entradas de caverna"), section = K("Rota"), kind = "lista",
        tip = K("Entradas de caverna que o jogo gravou (spec 038)"), run = listCaves },
    { id = "entradas limpar", label = K("Apagar entradas"), section = K("Rota"), kind = "acao",
        tip = K("Apaga as entradas de caverna aprendidas"), run = clearCaves },
    { id = "masmorras", label = K("Masmorras para você"), section = K("Rota"), kind = "lista",
        tip = K("Masmorras do seu nível: entrada, meeting stone e attune (spec 041)"),
        run = function() ns.DungeonGuide.PrintList(false) end },
    { id = "masmorras zona", label = K("Masmorras do mapa"), section = K("Rota"), kind = "lista",
        tip = K("Todas as masmorras com entrada ou pedra no mapa da zona atual"),
        run = function() ns.DungeonGuide.PrintList(true) end },
    { id = "masmorras limpar", label = K("Apagar entradas de masmorra"), section = K("Rota"), kind = "acao",
        tip = K("Apaga as entradas de masmorra que o jogo gravou"), run = function() ns.DungeonGuide.ClearLearned() end },
    -- Personagem
    { id = "bolsa", label = K("Seguir bolsa"), section = K("Personagem"), kind = "acao",
        tip = K("Segue a melhor quest que dá bolsa (zona atual primeiro)"), run = function() ns.Guide.FollowBag() end },
    { id = "bolsas", label = K("Quests de bolsa"), section = K("Personagem"), kind = "lista",
        tip = K("Lista as quests de bolsa deste personagem"), run = listBags },
    { id = "classe", label = K("Quests de classe"), section = K("Personagem"), kind = "lista",
        tip = K("Lista as quests de classe e segue a melhor"), run = function() ns.ClassGuide.PrintList(); ns.ClassGuide.Follow() end },
    { id = "armas", label = K("Armas"), section = K("Personagem"), kind = "acao",
        tip = K("Escolhe as armas que você usa e aponta a seta para o treinador"), run = function() ns.QuickMenu.ShowWeapons() end },
    { id = "treinar", label = K("Treinar"), section = K("Personagem"), kind = "acao",
        tip = K("Seta no treinador da classe mais perto e a lista do que falta aprender, com os novos do Forever (spec 051)"),
        run = function() ns.ClassGuide.FollowClassTrainer() end },
    { id = "essenciais", label = K("Essenciais"), section = K("Personagem"), kind = "lista",
        tip = K("O que o personagem não pode esquecer: bolsa, treino, montaria, pedra de lar, ponto de voo, comida (spec 062)"),
        run = function() ns.EssentialsGuide.Print() end },
    { id = "venda", label = K("Vender, leiloar ou desencantar"), section = K("Personagem"), kind = "lista",
        tip = K("O melhor destino de cada item das bolsas: vendedor, leilão (preço visto na AH) ou desencantar (spec 061)"),
        run = function() ns.EconomyGuide.Print() end },
    { id = "treinar tudo", label = K("Treinar tudo"), section = K("Personagem"), kind = "acao",
        tip = K("Com a janela do treinador aberta, compra todos os feitiços disponíveis que o dinheiro der (spec 055)"),
        run = function() ns.ClassGuide.TrainAll() end },
    { id = "ranks", label = K("Ranks velhos na barra"), section = K("Personagem"), kind = "lista", arg = "[trocar]",
        tip = K("Botões da barra com rank velho de feitiço; 'trocar' põe o rank novo (fora de combate) (spec 055)"),
        run = function(rest) ns.ClassGuide.Ranks(rest) end },
    { id = "marcos", label = K("Marcos da classe"), section = K("Personagem"), kind = "lista",
        tip = K("Feitiços e armas por nível da sua classe"), run = function() ns.ClassGuide.PrintMilestones(); ns.ClassGuide.WarnWeapons() end },
    { id = "macros", label = K("Feitiços das macros"), section = K("Personagem"), kind = "lista",
        tip = K("Quais feitiços das macros você já conhece"), run = listMacros },
    { id = "calib", label = K("Calibração"), section = K("Personagem"), kind = "lista",
        tip = K("Tempo por morte, fator de XP e tolerância de mobs altos, com a fonte"), run = function() FP().PrintCalib() end },
    { id = "preset", label = K("Perfil de pesos"), section = K("Personagem"), kind = "valor", input = "opcoes", arg = "<nome>",
        tip = K("Troca o perfil de pesos dos itens"), run = setPreset, value = function() return db().preset end },
    { id = "agressividade", label = K("Agressividade (0–100)"), section = K("Personagem"), kind = "valor", input = "numero", arg = "<0-100>",
        tip = K("Quanto o guia corta quest que rende pouco"), run = setAggressiveness,
        value = function() return math.floor((db().threshold or 0.5) * 100) end },
    { id = "ttk", label = K("TTK (segundos)"), section = K("Personagem"), kind = "valor", input = "numero", arg = "<seg>",
        tip = K("Tempo por morte usado nas contas, em segundos (maior que 0)"), run = setTTK, value = function() return db().ttk end },
    { id = "stats", label = K("Comparar item"), section = K("Personagem"), kind = "valor", input = "texto", arg = "<link>",
        tip = "Shift+clique num item com o campo em foco, ou o ID do item", run = function(rest) ns.Scoring.Debug(rest) end },
    -- Grupo
    { id = "grupo", label = K("Compartilhar quests"), section = K("Grupo"), kind = "acao",
        tip = K("Compartilha as quests do log com o grupo e manda um resumo do que falta"), run = function() ns.Group.ShareAll() end },
    { id = "grupo avisos", label = K("Avisos no grupo"), section = K("Grupo"), kind = "liga",
        tip = K("Avisa o grupo quando um objetivo avança"), run = function() ns.Group.ToggleAnnounce() end,
        state = function() return db().groupAnnounce ~= false end },
    { id = "lfg", label = K("Procurar grupo"), section = K("Grupo"), kind = "acao",
        tip = K("Abre o painel de procurar grupo (spec 037)"), run = function(rest) ns.LfgPanel.Command(rest) end },
    { id = "lfg texto", label = K("Texto para grupo"), section = K("Grupo"), kind = "valor", input = "texto", arg = "<texto>",
        tip = K("Whisper para o líder de grupo. Campos: {classe} {nivel} {papel} {atividade}"),
        run = function(rest) ns.LfgPanel.Command("texto " .. (rest or "")) end, value = function() return db().lfgWhisper end },
    { id = "lfg solo", label = K("Texto para sozinho"), section = K("Grupo"), kind = "valor", input = "texto", arg = "<texto>",
        tip = K("Whisper para quem está sozinho"), run = function(rest) ns.LfgPanel.Command("solo " .. (rest or "")) end,
        value = function() return db().lfgWhisperSolo end },
    { id = "lfg padrao", label = K("Textos padrão do LFG"), section = K("Grupo"), kind = "acao",
        tip = K("Volta os textos do LFG ao padrão"), run = function() ns.LfgPanel.Command("padrao") end },
    { id = "lfg copiar", label = K("LFG só copia"), section = K("Grupo"), kind = "acao",
        tip = K("'Chamar' passa a só copiar o texto"), run = function() ns.LfgPanel.Command("copiar") end },
    -- Interface
    -- Automações (spec 058)
    { id = "auto", label = K("Automações de quest (geral)"), section = K("Automações"), kind = "liga",
        tip = K("Chave geral: desligada, não aceita, não entrega e não escolhe recompensa"), run = function() ns.Auto.Toggle() end,
        state = function() return db().auto ~= false end },
    toggle("auto aceitar", K("Aceitar sozinho"), "autoAccept", true, K("Aceita só as quests do plano: hubs da zona, a seguida e a continuação da que você entregou")),
    toggle("auto entregar", K("Entregar sozinho"), "autoTurnIn", true, K("Completa e entrega a quest pronta")),
    toggle("auto recompensa", K("Escolher recompensa"), "autoReward", true, K("Escolhe o maior upgrade entre as recompensas")),
    toggle("auto seguir", K("Seguir a próxima"), "autoNext", true, K("Depois de entregar, a seta segue a próxima quest ou hub")),
    toggle("auto grupo", K("Perguntar quest de grupo"), "groupAsk", true, K("Ao aceitar quest de elite ou masmorra, pergunta: pular ou fazer em grupo (spec 054)")),
    toggle("auto voo rota", K("Abrir pontos de voo na rota"), "flightStops", true, K("Paradas 'Abrir ponto de voo' no circuito (spec 052)")),
    toggle("auto entrega caminho", K("Entrega no caminho"), "turnInsOnTheWay", true, K("Quest pronta de outro hub com o NPC no caminho entra no circuito (spec 053)")),
    toggle("voo marcar", K("Marcar o destino do voo"), "taxiMark", true, K("Ao abrir o mestre de voo, destaca o destino da seta (spec 057)")),
    toggle("voo auto", K("Voar sozinho"), "taxiAuto", false, K("Ao abrir o mestre de voo, voa para o destino marcado (spec 057)")),
    { id = "idioma", label = K("Idioma"), section = K("Interface"), kind = "valor", input = "opcoes", arg = "pt|en|auto",
        tip = K("Idioma do addon: pt, en ou auto (pelo cliente do jogo). Vale depois do /reload (spec 066)"),
        run = setLanguage, value = language },
    { id = "minimapa", label = K("Botão no minimapa"), section = K("Interface"), kind = "liga", alias = { "minimap" },
        tip = K("Mostra ou esconde o botão no minimapa"), run = function() ns.MinimapButton.Toggle() end,
        state = function() return not (db().minimap and db().minimap.hide) end },
    { id = "masmorras pinos", label = K("Masmorras no mapa"), section = K("Interface"), kind = "liga",
        tip = K("Mostra ou esconde os pinos de entrada de masmorra e meeting stone no mapa-múndi (spec 041)"),
        run = function()
            local d = ns.DungeonGuide.db()
            d.pins = d.pins == false
            ns.FP.Fire("DUNGEONS")
        end,
        state = function() return ns.DungeonGuide.db().pins ~= false end },
    { id = "voos lista", label = K("Pontos de voo do mapa (diagnóstico)"), section = K("Registro"), kind = "lista",
        tip = K("O que o jogo devolve de pontos de voo para o mapa aberto e o que o addon mostra; grava para relatar"),
        run = function() ns.FlightPins.Diag() end },
    { id = "voos", label = K("Pontos de voo no mapa"), section = K("Interface"), kind = "liga",
        tip = K("Pontos de voo no mapa-múndi: verde descoberto, vermelho a descobrir (spec 044)"),
        run = function()
            db().flightPins = db().flightPins == false
            FP().Print(L["pontos de voo no mapa:"], onOff(db().flightPins ~= false))
            if ns.FlightPins then ns.FlightPins.Refresh(true) end
        end,
        state = function() return db().flightPins ~= false end },
    -- Registro
    { id = "diario", label = K("Diário"), section = K("Registro"), kind = "liga", arg = "[on|off]",
        tip = K("Diário do que você faz no jogo (spec 036). Sem argumento no comando: o resumo"),
        run = function(rest)
            if rest == nil then rest = ns.Journal.IsOn() and "off" or "on" end -- botão: liga/desliga
            ns.Journal.Command(rest)
        end, state = function() return ns.Journal.IsOn() end },
    { id = "diario limpar", label = K("Apagar diário"), section = K("Registro"), kind = "acao",
        tip = K("Apaga o diário (pede confirmação). Importe antes com tools/journal.py"), confirma = true,
        run = function() ns.Journal.Command("limpar") end },
    { id = "debug", label = K("Modo debug"), section = K("Registro"), kind = "liga",
        tip = K("Grava o registro de debug (sai no /reload ou logout)"),
        run = function()
            db().debug = not db().debug
            FP().Print(L["modo debug:"], db().debug and L["ligado (registro gravado no /reload ou logout)"] or L["desligado"])
        end, state = function() return db().debug == true end },
    { id = "debug chat", label = K("Debug no chat"), section = K("Registro"), kind = "liga",
        tip = K("Mostra o debug também no chat"),
        run = function() db().debugChat = not db().debugChat; FP().Print(L["debug no chat:"], onOff(db().debugChat)) end,
        state = function() return db().debugChat == true end },
    { id = "diag", label = K("Diagnóstico"), section = K("Registro"), kind = "lista",
        tip = K("Estado dos dados e do cálculo, para relatar problema"), run = function() ns.DebugTools.Diag() end },
    { id = "cena", label = K("Gravar cena de voo"), section = K("Registro"), kind = "acao",
        tip = K("Grava a situação do último cálculo de ponto de voo para virar teste (spec 052); depois /reload"),
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
    local out = { L["/fp (janela)"] }
    for _, c in ipairs(list) do out[#out + 1] = "/fp " .. c.id .. (c.arg and (" " .. c.arg) or "") end
    return L["comandos: "] .. table.concat(out, ", ")
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
        out[#out + 1] = L["|cFFFF6666erro:|r "] .. tostring(err):match("^[^\n]*")
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
