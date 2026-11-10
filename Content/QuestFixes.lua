-- Content/QuestFixes.lua: correções de quest por cima da QuestieDB (spec 023).
-- Cada entrada leva fonte e data. Vale até a correção entrar na QuestieDB.
local _, ns = ...

ns.QuestFixes = {
    -- Arugal's Folly (Dalar Dawnweaver): a chain do Forever é 421 > 422 > 423 > 424 > 99 > 98298
    -- (série no Wowhead do Forever, 08/11/2026). A QuestieDB não liga a 98298 à 99, e a seta
    -- mandava pegar a 98298 no meio da chain (visto no jogo em 08/11/2026).
    [98298] = { preQuestSingle = { 99 } },
    [99] = { nextQuestInChain = 98298 },
    -- Ivar the Foul (Rane Yorick): ESTIMATIVA. A chain da Quinn/Rane no Forever é 428 > 429 > 430 >
    -- 91920 > 91921 (Wowhead do Forever, 08/11/2026); a QuestieDB pede só a 430. Com a 430 feita e a
    -- 91920 no log, a Rane não ofereceu a 425 (visto no jogo em 08/11/2026). Confirmar ao fim da 91921.
    [425] = { preQuestSingle = { 91921 } },
    -- Return to Quinn (Again) (Apothecary Renferrel): vem depois da Wild Eyes na mesma chain acima.
    -- Com a 91920 no log, o Renferrel não ofereceu a 91921 (visto no jogo em 10/11/2026).
    [91921] = { preQuestSingle = { 91920 } },
    -- Your Reward has Arrived! (innkeepers): fora do plano (spec 023, R7). Sem requisito na QuestieDB,
    -- o jogo não ofereceu (Innkeeper Norman, Undercity, visto no jogo em 10/11/2026). Pelo nome, é
    -- entrega de recompensa, não de leveling (ESTIMATIVA: a condição real não está nos dados).
    [60860] = { outOfPlan = true },
}
