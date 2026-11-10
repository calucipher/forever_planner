-- Content/Classes.lua: perícias de arma, Weapon Masters e marcos por nível (spec 011).
-- Fontes (nov/2026): Warcraft Tavern "Weapon Skill Trainer Locations" (Forever, out/2026) e
-- Blizzard Watch (06/10/2026): o Forever mantém as perícias de arma do Classic. Marcos do
-- Warlock: relatório técnico do projeto (06/11/2026) e guias de classe do Forever.
-- Conferidos nas DB2 do cliente do Forever (build 1.60.1.70862, 07/11/2026, tools/check_content.py):
-- perícias (ID, nome do feitiço e se a classe pode treinar) e marcos (ID existe e o feitiço não é
-- de nível acima do marco). Treinadores, textos e dicas continuam vindo dos guias acima.
-- Muda com patch: confira in-game. As quests de classe em si vêm da QuestieDB, não daqui.
local _, ns = ...
local Classes = {}
ns.Classes = Classes

-- Weapon Masters por facção (nome, cidade e ponto de referência)
local T = {
    hanashi = "Hanashi (Orgrimmar, Valley of Honor)",
    sayoc = "Sayoc (Orgrimmar, Valley of Honor)",
    ansekhwa = "Ansekhwa (Thunder Bluff, Lower Rise 40.9, 62.7)",
    archibald = "Archibald (Undercity, War Quarter 57.3, 32.8)",
    wooPing = "Woo Ping (Stormwind, Trade District 57.1, 57.7)",
    ilyenia = "Ilyenia Moonfire (Darnassus)",
    bixi = "Bixi Wobblebonk (Ironforge)",
}

-- Perícias de caster (Warlock e Mage): cajado, adaga e espada de uma mão. Varinha vem com a classe.
local CASTER_WEAPONS = {
    { key = "staff", spell = 227, name = "Cajados",
      trainers = { Horde = { T.hanashi, T.ansekhwa }, Alliance = { T.wooPing, T.ilyenia } } },
    { key = "dagger", spell = 1180, name = "Adagas",
      trainers = { Horde = { T.archibald, T.sayoc }, Alliance = { T.wooPing, T.ilyenia, T.bixi } } },
    { key = "sword1h", spell = 201, name = "Espadas de uma mão",
      trainers = { Horde = { T.archibald }, Alliance = { T.wooPing } } },
}

-- lvl = nível do marco; key = identificador estável; text = o que fazer.
Classes.WARLOCK = {
    trainerEvenLevels = true, -- feitiços novos nos níveis pares de 4 a 60 (SpellLevels/SkillLineAbility do cliente, build 1.60.1.70862, 07/11/2026)
    weapons = CASTER_WEAPONS,
    milestones = {
        { lvl = 1, key = "imp", spell = 688, text = "Imp: quest de classe na zona inicial (Undead: Piercing the Veil, Deathknell)." },
        { lvl = 10, key = "talentos", text = "Talentos abrem: comece por Suppression (Affliction). Veja a aba Builds." },
        { lvl = 10, key = "voidwalker", spell = 697, text = "Voidwalker: quest de classe (Undead: Halgar's Summons, em Brill, segue pra Undercity). Hub Classe na aba Guia." },
        { lvl = 10, key = "armas", text = "Treine Cajados (Orgrimmar ou Thunder Bluff) e Espadas de uma mão (Undercity): as melhores armas de quest do early são cajados." },
        { lvl = 14, key = "cozy", text = "Cozy Sleeping Bag: a chain começa no Barrens (torre queimada ao sul de Camp Taurajo) e dá duas bolsas de 12. Vale fazer quando passar por Barrens/Stonetalon." },
        { lvl = 15, key = "rathmael", text = "The Wrath of Rath'mael (Brill, Ruins of Lordaeron): Gnarled Necromancer's Staff, +26 SP no 22." },
        { lvl = 20, key = "sayaad", spell = 712, text = "Sayaad (Succubus/Incubus) e Small Soul Pouch: quest de classe." },
        { lvl = 20, key = "soranruk", text = "The Orb of Soran'ruk: fragmentos de BFD e SFK; Staff (+34 Sombra/Fogo) ou Orb. Só se for fazer as duas dungeons." },
        { lvl = 25, key = "glimmering", text = "Glimmering Staff (Enchanting 140, 45 Merchant's Favor): +34 SP, sem dungeon. Ou procure no AH." },
        { lvl = 30, key = "felhunter", spell = 691, text = "Felhunter: quest de classe. Drain tanking começa (Drain Life r3 + Fel Concentration)." },
        { lvl = 40, key = "montaria", spell = 5784, text = "Riding (100 g) e Dual Spec. Summon Felsteed é quest de classe: veja o hub Classe." },
        { lvl = 60, key = "dreadsteed", spell = 23161, text = "Dreadsteed of Xoroth: quest de classe longa (veja o hub Classe)." },
    },
}

Classes.MAGE = {
    trainerEvenLevels = true,
    weapons = CASTER_WEAPONS,
    milestones = {},
}

return Classes
