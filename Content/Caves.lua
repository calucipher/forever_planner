-- Content/Caves.lua: entradas de caverna escritas à mão (spec 038), para a 1ª visita. A entrada
-- que o jogo grava (ForeverPlannerWorld) confirma a daqui quando fica a até 15 jd dela.
-- Coordenada 0–100 do mapa da zona; raio da área em jardas. Cada entrada leva fonte e data.
local _, ns = ...

ns.CaveSeeds = {
    -- Skull Rock (Durotar): ESTIMATIVA. Warcraft Wiki dá a Skull Rock em 55, 11 e um guia dá a entrada
    -- em 55, 10 (consulta de 14/11/2026). A área cobre os spawns da Burning Blade (Fanatic e Apprentice)
    -- da QuestieDB, de 51,4 a 55,0 em x e de 7,6 a 11,1 em y. Confirmar no jogo.
    { name = "Skull Rock", mapID = 1411, entrance = { 55.0, 10.0 }, center = { 53.2, 9.3 }, radius = 110 },
}
