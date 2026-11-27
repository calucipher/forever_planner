-- Content/Builds.lua: builds de leveling do Warlock no Forever.
-- Fonte: guias de leveling do Forever (Icy Veins, Warcraft Tavern, Zockify), nov/2026.
-- O Forever lançou em 4/11/2026; talentos ainda mudaram em 2-3/nov. Confira in-game.
local _, ns = ...
local K = ns.Locale.K -- spec 066
local Builds = {}
ns.Builds = Builds

Builds.list = {
    {
        id = "affliction", title = "Affliction 40/11/0", tag = K("RECOMENDADA"), preset = "affliction",
        summary = K("Consenso dos guias para 10-60: DoTs + drain tanking, pouco downtime."),
        steps = {
            { lvl = "10-13", text = K("Suppression (hit e -ameaça)") },
            { lvl = "14-18", text = K("Improved Corruption (+10% de dano)") },
            { lvl = "19-21", text = "Improved Drains / Soul Siphon" },
            { lvl = "22-24", text = K("Pandemic (crit de DoT/drain)") },
            { lvl = "25-26", text = "Nightfall" },
            { lvl = "30", text = K("Siphon Life; começa drain tanking (Drain Life r3 + Fel Concentration)") },
            { lvl = "31-41", text = K("11 pontos em Demonology até Demonic Sacrifice (dura 2 h)") },
            { lvl = "51", text = K("Volta pra Affliction: Wrack (capstone de 31 pontos)") },
            { lvl = "52-60", text = "Amplify Curse, Curse of the Elements, Soul Siphon, Fel Concentration" },
        },
    },
    {
        id = "demonology", title = "Demonology 20/31/0", tag = K("ALTERNATIVA"), preset = "demonology",
        summary = K("Pet forte e segurança. Warcraft Tavern: Affliction 10-26, respec pra Demo no 27."),
        steps = {
            { lvl = "10-14", text = "Unholy Power (row 1)" },
            { lvl = "15-20", text = K("Fel Vitality / Demonic Energies (pet cura com 15% do seu dano)") },
            { lvl = "30", text = "Soul Link" },
            { lvl = "40", text = K("Demonic Pact (Sacrifice + outro pet ativo)") },
            { lvl = "41-60", text = K("Completa Affliction até 20 pontos") },
        },
    },
    {
        id = "destruction", title = "Destruction 6/11/34", tag = K("SÓ 40+"), preset = "destruction",
        summary = K("Guias desaconselham antes do 40. Bom com Dual Spec (liberado no 40)."),
        steps = {
            { lvl = "40+", text = "Bane of Havoc, Shadow and Flame" },
            { lvl = "50+", text = K("Incinerate (31 pontos)") },
        },
    },
}

Builds.legacy = {
    title = K("Legacy (16 pontos por personagem)"),
    items = {
        { text = "Thrill of Adventure 5/5", note = K("5% vida/mana em 10 s a cada killing blow fora de instância") },
        { text = "The Quick and the Dead 1/2", note = K("assim que tiver 6 pontos") },
        { text = "Well Rested", note = K("+20% de taxa e cap de rested") },
        { text = "Talented", note = K("talentos desde o 5, mas custa 10 pontos") },
    },
}

Builds.tips = {
    K("Rota Undead: Tirisfal (1-12) > Silverpine + Ruins of Lordaeron (15-20) > Tarren Mill + Dalaran (20-33) > Barrens/Stonetalon > Desolace/Arathi > Riverglades (35-45)."),
    K("Ruins of Lordaeron: The Wrath of Rath'mael (Brill, pega do 15) dá Gnarled Necromancer's Staff (+26 SP)."),
    K("Quest de classe Orb of Soran'ruk (20+, fragmentos de BFD/SFK): Staff ou Orb de Soran'ruk."),
    K("Pegue o Cozy Sleeping Bag (chain do 14) e cozinhe comida pro Well Fed (+5% XP de kill)."),
    K("Varinhas não escalam com Spell Power no Forever: compare pelo DPS da própria varinha."),
    K("Pesos de atributo são heurísticos: ajuste aqui e valide pelo seu tempo de kill (/fp ttk)."),
}

return Builds
