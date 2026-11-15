-- Content/QuestFixes.lua: correções de quest por cima da QuestieDB (spec 023).
-- Cada entrada leva fonte e data. Vale até a correção entrar na QuestieDB.
local _, ns = ...

ns.QuestFixes = {
    -- 98298/99, 425 e 91921: a QuestieDB 1.0.14 já traz esses vínculos (11/11/2026). Ficam para quem
    -- está numa versão anterior (o RequireContract(4) aceita a 1.0.11); sobre a 1.0.14 não mudam nada.
    -- Tirar quando o addon exigir a 1.0.14 ou mais nova.
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
    -- A Ludite's Guide to Caring for Your Demonic Pet (spec 023, R9): começa no objeto 423901 (Book);
    -- o Garion Wendell só recebe. Na QuestieDB 1.0.14 o item 215824 perdeu o objectDrops (commit
    -- 397d8d1 do upstream) e a regra do livro (R5) não pega mais a quest (11/11/2026).
    [79953] = { startedBy = { {}, { 423901 } } },
    -- Your Reward has Arrived! (innkeepers): fora do plano (spec 023, R7). Sem requisito na QuestieDB,
    -- o jogo não ofereceu (Innkeeper Norman, Undercity, visto no jogo em 10/11/2026). Pelo nome, é
    -- entrega de recompensa, não de leveling (ESTIMATIVA: a condição real não está nos dados).
    [60860] = { outOfPlan = true },
    -- Rocks to Rests (Thra, atrás do Grommash Hold, Orgrimmar): fora do plano (spec 023, R11). Na
    -- QuestieDB a Thra dá e recebe, sem requisito; no jogo (nível 18, 14/11/2026) ela não abriu diálogo
    -- nenhum, e sem diálogo a spec 014 não tem como marcar. O Wowhead do Forever não diz quem dá a
    -- quest. ESTIMATIVA: a condição real não está nos dados. Tirar se alguém a oferecer no jogo.
    [97326] = { outOfPlan = true },
}

-- Spec 023, R10: quem só recebe livros. Quest entregue só a eles é coleção, não leveling, e sai do
-- plano (salvo no log). O Owen não ofereceu "Friend of the Library" sem livro (visto no jogo em 11/11/2026).
ns.OutOfPlanFinishers = {
    [211022] = true, -- Owen Thadd, Undercity
    [211033] = true, -- Garion Wendell, Stormwind
}

-- Spec 010, R9: itens de recompensa que dão bônus de XP. A QuestieDB não traz o efeito do item.
ns.XPBonusItems = {
    -- Cozy Sleeping Bag (79976, This Must Be The Place): ESTIMATIVA, bônus de XP ao descansar nele.
    -- Conferir o tooltip no jogo e pôr aqui como fonte (12/11/2026). A ligação item > quest é da QuestieDB.
    [211527] = true,
}
