-- Content/Dungeons.lua: o que a QuestieDB não tem sobre masmorras (spec 041). Curado à mão.
-- Coordenada 0–100 do mapa da zona (uiMapID). Tudo aqui é estimativa até ser visto no jogo;
-- a entrada aprendida no jogo (ForeverPlannerWorld.dungeons) substitui a da lista.
local _, ns = ...
ns = ns or {}

ns.DungeonContent = {
    -- Nome normalizado (Dungeons.Norm) da atividade do LFG -> nome normalizado da entrada.
    -- Preencher quando o jogo mostrar nome diferente do da QuestieDB.
    aliases = {
        ["stormwind stockade"] = "stockade",
        ["sunken temple"] = "temple of atalhakkar",
        ["lower blackrock spire"] = "blackrock spire",
        ["upper blackrock spire"] = "blackrock spire",
        ["scarlet monastery graveyard"] = "scarlet monastery",
        ["scarlet monastery library"] = "scarlet monastery",
        ["scarlet monastery armory"] = "scarlet monastery",
        ["scarlet monastery cathedral"] = "scarlet monastery",
        ["dire maul east"] = "dire maul",
        ["dire maul west"] = "dire maul",
        ["dire maul north"] = "dire maul",
        ["excavation site"] = "excavation site wetlands",
        ["dalaran"] = "city of dalaran",
    },

    -- Masmorras novas do Forever que faltam na QuestieDB (consulta de 15/11/2026).
    -- Shaper's Terrace (Un'Goro) fica sem ponto: nenhum guia deu coordenada; o jogo aprende.
    seeds = {
        { name = "The Drowned City", mapID = 1434, x = 21.4, y = 27.8,
          source = "conquestcapped.com e chaosboost.com, 15/11/2026 (caverna submersa)" },
        { name = "Krol'dok Stronghold", mapID = 2548, x = 37.5, y = 37.2,
          source = "conquestcapped.com, 15/11/2026; mmonster.co dá 37,5 37,5" },
        { name = "Alcaz Prison", mapID = 1445, x = 75.3, y = 14.1,
          source = "conquestcapped.com, 15/11/2026 (porão da torre da Alcaz Island)" },
        { name = "Blackmaw Hold", mapID = 1447, x = 35.0, y = 23.4,
          source = "conquestcapped.com, 15/11/2026 (fim do túnel; boca do túnel em 38,4 32,6)" },
    },

    -- Attune: passos por facção, em ordem. O último passo feito marca o attune como feito.
    -- Passo sem quest só é dado como feito quando um passo depois dele está feito.
    attunes = {
        ["city of dalaran"] = {
            item = "Dalaran Sewers Key",
            source = "method.gg (15/10/2026) e warcraft.wiki.gg, consulta de 15/11/2026",
            Alliance = {
                { title = "An Alarming Request", npcName = "Emissary Jacques", mapID = 1424, x = 48.3, y = 60.1 },
                { quest = 92458, title = "Heart of Disruption", npcName = "Image of Archmage Modera", mapID = 1421, x = 68.6, y = 45.2 },
            },
            Horde = {
                { title = "Key to the City", npc = 2410 },
                { quest = 545, title = "Dalaran Patrols", npc = 2410 },
                { quest = 92434, title = "Blood in the Streets" },
                { quest = 96984, title = "Heart of Disruption", npcName = "Image of Archmage Modera", mapID = 1421, x = 68.6, y = 45.2 },
            },
            optional = "Black Tome (sala do Arugal, Shadowfang Keep) no Ley Line da prefeitura de Ambermill: só para o chefe secreto.",
        },
    },
}

return ns.DungeonContent
