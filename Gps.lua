-- Gps.lua: aponta para onde ir. Usa o waypoint nativo (pino + super-track), o TomTom se
-- estiver instalado, e uma seta própria na tela com distância.
local _, ns = ...
local Util = ns.Util
local Gps = {}
ns.Gps = Gps

Gps.target = nil -- { mapID, x, y, title } (x/y em 0-100)
Gps.info = nil   -- linhas de contexto sob a seta (spec 006, R18)
local tomtomUID
local showWaypoint, zonePoint -- definidas na API (spec 024)

------------------------------------------------------------------------------------------
-- Matemática pura (testada fora do jogo)
------------------------------------------------------------------------------------------
-- Coordenadas de mundo do WoW: x aponta pro norte, y pro oeste.
-- facing: radianos, 0 = norte, cresce no sentido anti-horário (pra oeste).
-- Retorna ângulo relativo (anti-horário, 0 = em frente) e distância.
function Gps.Relative(px, py, tx, ty, facing)
    local dn, dw = tx - px, ty - py
    local dist = math.sqrt(dn * dn + dw * dw)
    local bearing = math.atan2(dw, dn)
    local rel = (bearing - (facing or 0)) % (2 * math.pi)
    return rel, dist
end

-- Spec 024, R1: voar compensa? Pontos {x, y} em jardas do mundo. A = nó mais perto do jogador,
-- B = nó mais perto do alvo. Devolve {from, to, walk, total} ou nil.
local function span(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function nearestNode(p, nodes)
    local best, bestD
    for _, n in ipairs(nodes) do
        local d = span(p, n)
        if not bestD or d < bestD then best, bestD = n, d end
    end
    return best, bestD
end
function Gps.PlanFlight(player, target, nodes, opts)
    if not (player and target and nodes and nodes[1]) then return nil end
    local a, da = nearestNode(player, nodes)
    local b, db = nearestNode(target, nodes)
    -- Spec 049, R5: com opts.walk, os trechos a pé contam pelas passagens entre zonas, e os pontos de
    -- partida e de chegada são os de menor caminho a pé (em linha reta, o mais perto pode estar atrás
    -- da montanha: Thunder Bluff para Stonetalon).
    local walkYd = span(player, target)
    if opts.walk then
        walkYd = opts.walk(player, target)
        a, da, b, db = nil, nil, nil, nil
        for _, n in ipairs(nodes) do
            local w1, w2 = opts.walk(player, n), opts.walk(n, target)
            if not da or w1 < da then a, da = n, w1 end
            if not db or w2 < db then b, db = n, w2 end
        end
    end
    if a == b then return nil end
    local walk = walkYd / opts.run
    local onFoot = (da + db) / opts.run
    local total = onFoot + opts.overhead + span(a, b) * opts.factor / opts.fly
    -- R1 (emenda de 21/11/2026): andar o menos possível. Voa se o trecho a pé for até walkShare do
    -- caminho a pé e o voo não passar do tempo a pé mais a margem (voar é tempo parado).
    if onFoot > (opts.walkShare or 0.75) * walk or total > walk + opts.margin then return nil end
    return { from = a, to = b, walk = walk, total = total }
end

-- Spec 034, R8: ir pela estrada compensa? Caminho de Roads.Path ou nil. canJump: R7a.
function Gps.PlanRoad(player, target, graph, opts, canJump)
    if not (player and target and graph) then return nil end
    local straight = span(player, target)
    if straight <= opts.minDist then return nil end
    local path = ns.Roads.Path(graph, player, target, { canJump = canJump })
    if not path or path.accessFrom > opts.maxAccess
        or path.accessTo > (opts.maxAccessTo or opts.maxAccess) then return nil end -- R8a
    if path.accessFrom + path.road + path.accessTo > opts.factor * straight then return nil end
    return path
end

-- Spec 034, R8b: o fim da estrada até o destino precisa ir pela malha? Ponto de saída ou nil.
-- Só quando o acesso passa de minYd e clear(ax, ay, bx, by) diz que a reta não passa; sem clear, nil.
function Gps.TailNeeded(path, dest, clear, minYd)
    local last = path and path.points and path.points[#path.points]
    if not (last and dest and clear) or (path.accessTo or 0) <= minYd then return nil end
    if clear(last.x, last.y, dest.x, dest.y) then return nil end
    return last
end

-- R8b: a rota com os pontos da malha antes do destino (o último ponto da rota). Rota nova; o
-- começo é o mesmo, então o avanço guardado da mira continua valendo.
function Gps.WithTail(route, pts)
    local out = {}
    for i = 1, #route - 1 do out[i] = route[i] end
    for _, pt in ipairs(pts) do out[#out + 1] = pt end
    out[#out + 1] = route[#route]
    return out
end

------------------------------------------------------------------------------------------
-- Rota com voo (spec 024): constantes são estimativa, a calibrar no jogo
------------------------------------------------------------------------------------------
local FLIGHT = { fly = 32, factor = 1.25, overhead = 20, margin = 60, walkShare = 0.75 }
Gps.FLIGHT = FLIGHT -- spec 045, R2b: o ganho de abrir um ponto de voo usa as mesmas constantes
local REROUTE_EVERY = 2
Gps.leg = nil -- { from, to } quando a seta aponta para o ponto de voo

local playerZone, targetZone, nodeZone -- spec 049 (definidos abaixo)
local function playerWorld()
    local ok, cont, px, py = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return nil end
        local c, w = C_Map.GetWorldPosFromMapPos(mapID, pos)
        if not w then return nil end
        local x, y = w:GetXY()
        return c, x, y
    end)
    if not ok or not px or Util.IsSecret(px) then return nil end
    return cont, px, py
end

-- Pontos de voo descobertos do continente do jogador, com posição no mundo (R5).
local function taxiNodes(cont)
    if not (ns.Planner and ns.Planner.ContinentMap) then return {} end
    local cmap = ns.Planner.ContinentMap(C_Map.GetBestMapForUnit("player"))
    if not cmap then return {} end
    local out = {}
    for _, p in ipairs(ns.Planner.KnownTaxiPoints(cmap)) do -- spec 044, R8
        local c, w = C_Map.GetWorldPosFromMapPos(cmap, CreateVector2D(p.x / 100, p.y / 100))
        if w and c == cont then
            local wx, wy = w:GetXY()
            out[#out + 1] = { x = wx, y = wy, name = p.name, mapID = cmap, mx = p.x, my = p.y }
        end
    end
    return out
end

------------------------------------------------------------------------------------------
-- Passagens entre zonas (spec 049)
------------------------------------------------------------------------------------------
Gps.gate = nil -- próxima passagem do caminho a pé ({ x, y, from, to, m, mx, my }), sem trecho de voo
local gateState = {}
local seenGates = setmetatable({}, { __mode = "k" })

local function learnedGates()
    local W = _G.ForeverPlannerWorld
    if type(W) ~= "table" then W = {}; _G.ForeverPlannerWorld = W end
    W.gates = W.gates or {}
    return W.gates
end
Gps.LearnedGates = learnedGates

-- R1: as geradas do cliente (Content/Gates.lua) e as aprendidas no jogo, do continente.
local function gateList(cont)
    local out = {}
    for _, g in ipairs((ns.GateData or {})[cont] or {}) do out[#out + 1] = g end
    for _, g in ipairs(learnedGates()[cont] or {}) do out[#out + 1] = g end
    return out
end
Gps.GateList = gateList

-- Sem a QuestieDB (mapa > zona), nil: a seta segue sem passagem, como antes.
playerZone = function()
    local ok, z = pcall(function() return ns.Guide.PlayerArea() end)
    return ok and z or nil
end
targetZone = function(t)
    if t.zone == nil then
        local ok, z = pcall(ns.Guide.MapZone, t.mapID)
        t.zone = ok and z or false
    end
    return t.zone or nil
end

-- Zona de um ponto de voo (mapa do continente): o mapa de zona naquela posição. Cache por nome.
local nodeZones = {}
nodeZone = function(n)
    local key = tostring(n.name)
    if nodeZones[key] == nil then
        local ok, z = pcall(function()
            local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(n.mapID, n.mx / 100, n.my / 100)
            return info and ns.Guide.MapZone(info.mapID)
        end)
        nodeZones[key] = ok and z or false
    end
    return nodeZones[key] or nil
end

-- Spec 064, R3: custo de atravessar a zona pelo nível dela (spec 032) contra o do jogador.
local function zoneCostFn()
    local L = UnitLevel("player")
    return function(zone)
        local ok, lo, hi = pcall(ns.Guide.ZoneLevels, zone)
        if not ok then lo, hi = nil, nil end
        return ns.Gates.DangerCost(lo, hi, L)
    end
end
Gps.ZoneCost = zoneCostFn

-- R5: distância a pé entre dois pontos com zona, pelas passagens; sem caminho conhecido, a reta.
function Gps.WalkFn(cont)
    local list = gateList(cont)
    local opts = { zoneCost = zoneCostFn() } -- spec 064, R3
    return function(a, b)
        if a.zone and b.zone and a.zone ~= b.zone then
            local ok, r = pcall(ns.Gates.Route, list, a, b, nil, opts)
            if ok and r then return r.yd end
        end
        local dx, dy = a.x - b.x, a.y - b.y
        return math.sqrt(dx * dx + dy * dy)
    end
end

-- R4: a próxima passagem até o alvo, sem trecho de voo e no mesmo continente.
local function gateKey(g) return g and string.format("%s>%s:%.0f:%.0f", tostring(g.from), tostring(g.to), g.x, g.y) or "" end
function Gps.UpdateGate()
    local t, gate = Gps.target, nil
    if t and t.world and not Gps.leg then
        local cont, px, py = playerWorld()
        local pz, tz = playerZone(), targetZone(t)
        if cont and cont == t.world[1] and pz and tz and pz ~= tz then
            local ok, r = pcall(ns.Gates.Route, gateList(cont), { zone = pz, x = px, y = py },
                { zone = tz, x = t.world[2], y = t.world[3] }, nil, { zoneCost = zoneCostFn() }) -- spec 064, R3
            if not ok then ns.FP.Debug("gps: passagem descartada: " .. tostring(r)) end
            gate = ok and r and r.gates[1] or nil
            -- R4: o caminho ainda passa por zona bem acima do nível (não havia outro): avisa na seta
            t.danger = nil
            if ok and r then
                local L = UnitLevel("player")
                for _, s in ipairs(r.gates) do
                    local okL, lo, hi = pcall(ns.Guide.ZoneLevels, s.to)
                    if okL and lo and s.to ~= tz and ns.Gates.DangerCost(lo, hi, L) >= 10 then
                        t.danger = string.format("%s (%s)", tostring(ns.Guide.AreaName(s.to)), ns.Zones.FormatRange(lo, hi))
                        break
                    end
                end
            end
            -- chegou perto da passagem e o jogo não trocou de zona: o ponto estimado errou; não mira de novo
            if gate and t.gatePassed and t.gatePassed == gateKey(gate) then gate = nil end
            if gate then -- pino no mapa da zona atual
                local map = ns.Data.areaToMap and ns.Data.areaToMap[pz]
                local okPos, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(gate.x, gate.y), map)
                if okPos and pos then
                    local mx, my = pos:GetXY()
                    gate.m, gate.mx, gate.my = map, mx * 100, my * 100
                end
            end
        end
    end
    local changed = gateKey(gate) ~= gateKey(Gps.gate)
    Gps.gate = gate
    if changed then
        ns.FP.Debug(gate and string.format("gps: passagem %s > %s", tostring(gate.from), tostring(gate.to)) or "gps: sem passagem")
    end
    return changed
end

-- R7: /fp passagens [limpar]
function Gps.PrintGates(arg)
    if arg == "limpar" then
        _G.ForeverPlannerWorld.gates = {}
        ns.FP.Print("passagens aprendidas apagadas.")
        return
    end
    local cont = playerWorld()
    local pz = playerZone()
    if not (cont and pz) then ns.FP.Print("não consegui ler a sua zona agora."); return end
    local G, n = ns.Guide, 0
    for _, g in ipairs(gateList(cont)) do
        if g.a == pz or g.b == pz then
            n = n + 1
            local other = g.a == pz and g.b or g.a
            ns.FP.Print(string.format("  %s · %s", G.AreaName(other),
                g.learned and "aprendida no jogo" or (g.relevo and "pelo relevo (estimativa)" or "pela estrada (estimativa)")))
        end
    end
    if n == 0 then ns.FP.Print("nenhuma passagem conhecida em " .. tostring(G.AreaName(pz)) .. ".") end
end

-- R2/R4: refaz o plano. Em voo, sem alvo no mundo ou em outro continente: sem trecho de voo.
local function reroute()
    local t = Gps.target
    if not (t and t.world) or (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) then return nil end
    local cont, px, py = playerWorld()
    if not cont or cont ~= t.world[1] then return nil end
    local opts = { run = ns.FP.db.runSpeed or 7, fly = FLIGHT.fly, factor = FLIGHT.factor,
        overhead = FLIGHT.overhead, margin = FLIGHT.margin, walk = Gps.WalkFn(cont) } -- spec 049, R5
    local nodes = taxiNodes(cont)
    for _, n in ipairs(nodes) do n.zone = nodeZone(n) end
    local plan = Gps.PlanFlight({ x = px, y = py, zone = playerZone() }, { x = t.world[2], y = t.world[3], zone = targetZone(t) },
        nodes, opts)
    return plan and { from = plan.from, to = plan.to } or nil
end

------------------------------------------------------------------------------------------
-- Pela estrada (spec 034): constantes são estimativa, a calibrar no jogo
------------------------------------------------------------------------------------------
-- Spec 038, R3a (emenda de 21/11/2026): pegada aprendida com alcance menor é prédio, não caverna.
-- Medido em 21/11/2026: prédios de cidade 3–40 jd (Ratchet, Valley of Strength, Fenris Keep);
-- cavernas 151–392 jd (Beren's Peril, Wailing Caverns). Estimativa.
local CAVE_MIN_REACH = 60
local GATE_ARRIVE = 40 -- spec 049: a passagem é um ponto estimado; chegou perto, refaz
local ROAD = { minDist = 400, maxAccess = 150, maxAccessTo = 250, factor = 1.6, ahead = 30, offRoute = 60, tailMin = 40 }
Gps.road = nil -- caminho de Roads.Path + dest, para o trecho a pé (até o alvo ou o ponto de voo)

------------------------------------------------------------------------------------------
-- Entrada de caverna (spec 038)
------------------------------------------------------------------------------------------
Gps.door = nil -- entrada por onde a seta passa (Caves.Door), sem trecho de voo
local LEARN_EVERY = 0.5
local learnState = {}
local seedCache -- lista da Content/Caves.lua em jardas do mundo (convertida uma vez)

-- Entradas aprendidas, na conta (ForeverPlannerWorld). Lido na hora: o SavedVariables chega no login.
local function learnedCaves()
    local W = _G.ForeverPlannerWorld
    if type(W) ~= "table" then W = {}; _G.ForeverPlannerWorld = W end
    W.caves = W.caves or {}
    return W.caves
end
Gps.LearnedCaves = learnedCaves

local function toWorld(mapID, x, y)
    local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
    if not pos then return nil end
    local wx, wy = pos:GetXY()
    return cont, wx, wy
end
Gps.ToWorld = toWorld -- spec 041: entradas de masmorra e meeting stones

local function caveList()
    if not seedCache and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, seeds = pcall(ns.Caves.Seeds, ns.CaveSeeds, toWorld)
        if not ok then ns.FP.Debug("gps: lista de cavernas descartada: " .. tostring(seeds)) end
        seedCache = ok and seeds or {}
    end
    return ns.Caves.Merge(learnedCaves(), seedCache)
end

local function indoors() return (_G.IsIndoors and _G.IsIndoors()) and true or false end

-- R4/R8: refaz a entrada. Com trecho de voo, desligado ou sem posição: sem entrada.
local function doorKey(d) return d and string.format("%s:%.0f:%.0f", tostring(d.exit), d.x, d.y) or "" end
function Gps.UpdateDoor()
    local t, door = Gps.target, nil
    if t and t.world and not Gps.leg and not Gps.gate and ns.FP.db.gps.caves ~= false then
        local cont, px, py = playerWorld()
        if cont then
            local ok, d = pcall(ns.Caves.Door, caveList(), { c = cont, x = px, y = py, indoors = indoors() },
                { c = t.world[1], x = t.world[2], y = t.world[3] }, { arrive = ns.FP.db.gps.arriveYards, minReach = CAVE_MIN_REACH })
            if not ok then ns.FP.Debug("gps: entrada descartada: " .. tostring(d)) end
            door = ok and d or nil
        end
    end
    local changed = doorKey(door) ~= doorKey(Gps.door)
    Gps.door = door
    if changed then
        ns.FP.Debug(door and string.format("gps: %s %s", door.exit and "saída" or "entrada", tostring(door.name)) or "gps: sem entrada")
    end
    return changed
end

-- R1/R2/R9: amostra do jogador para aprender entradas; em taxi, morto ou sem posição, esquece.
local function learnTick()
    local cont, px, py = playerWorld()
    local s
    if cont and not (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) and not (_G.UnitIsDeadOrGhost and _G.UnitIsDeadOrGhost("player")) then
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local mx, my
        if pos then mx, my = pos:GetXY() end
        if mx and Util.IsSecret(mx) then mx, my = nil, nil end
        local name = _G.GetSubZoneText and _G.GetSubZoneText()
        if name == "" or Util.IsSecret(name) then name = nil end
        s = { c = cont, x = px, y = py, indoors = indoors(), m = mapID,
            mx = mx and math.floor(mx * 1000 + 0.5) / 10, my = my and math.floor(my * 1000 + 0.5) / 10, name = name }
    end
    local okG, gate = pcall(ns.Gates.Learn, learnedGates(), gateState, s and { c = s.c, x = s.x, y = s.y, zone = playerZone() })
    if not okG then ns.FP.Debug("gps: aprendizado de passagem falhou: " .. tostring(gate))
    elseif gate and gate.learned and not seenGates[gate] then
        seenGates[gate] = true -- só na memória (parecer: não vai para o SavedVariables)
        ns.FP.Debug(string.format("gps: passagem aprendida %s > %s", tostring(gate.a), tostring(gate.b)))
    end
    local flipped = ns.Caves.Learn(learnedCaves(), learnState, s)
    if flipped and Gps.target and Gps.UpdateDoor() then Gps.RefreshWaypoint() end
end
ns.FP.On("READY", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(LEARN_EVERY, function()
        local ok, err = pcall(learnTick)
        if not ok then ns.FP.Debug("gps: aprendizado de entrada falhou: " .. tostring(err)) end
    end) end
end)

local roadJumpCheck -- spec 034, R7a (definida com a malha, abaixo)

-- R11/R12/R13: caminho para o trecho a pé; reaproveita o atual se o destino não mudou.
local function planRoad()
    local t = Gps.target
    if not (t and t.world) or ns.FP.db.gps.roads == false then return nil end
    if _G.UnitOnTaxi and _G.UnitOnTaxi("player") then return nil end
    local graphs = ns.RoadGraphs
    local cont, px, py = playerWorld()
    if not (graphs and cont and cont == t.world[1] and graphs[cont]) then return nil end
    local leg, door = Gps.leg, Gps.door
    local gate = Gps.gate -- spec 049: a estrada termina na passagem
    local dest = leg and { x = leg.from.x, y = leg.from.y } or gate and { x = gate.x, y = gate.y }
        or door and { x = door.x, y = door.y }
        or { x = t.world[2], y = t.world[3] } -- spec 038, R5: a estrada termina na entrada
    local cur = Gps.road
    if cur and cur.dest.x == dest.x and cur.dest.y == dest.y then return cur end
    if InCombatLockdown() then return nil end -- constituição 6: nada pesado em combate
    local path = Gps.PlanRoad({ x = px, y = py }, dest, graphs[cont], ROAD, roadJumpCheck(cont))
    if not path then return nil end
    -- R9/R10: a rota seguida começa no jogador e termina no destino (acessos inclusos)
    local route = { { x = px, y = py } }
    for _, pt in ipairs(path.points) do route[#route + 1] = pt end
    route[#route + 1] = dest
    path.dest, path.route, path.aim = dest, route, { lost = ROAD.offRoute }
    path.tailFrom = Gps.TailNeeded(path, dest, roadJumpCheck(cont), ROAD.tailMin) -- R8b
    return path
end

local function updateRoad()
    local ok, road = pcall(planRoad)
    if not ok then
        ns.FP.Debug("gps: estrada descartada: " .. tostring(road))
        road = nil
    end
    if (road ~= nil) ~= (Gps.road ~= nil) then
        ns.FP.Debug(road and string.format("gps: pela estrada (%d yd)", road.road) or "gps: sem estrada")
    end
    Gps.road = road
end

------------------------------------------------------------------------------------------
-- Caminho a pé pelo relevo (spec 050): sem estrada, a malha de Content/Nav.lua
------------------------------------------------------------------------------------------
local NAV = { minDist = 150, ahead = 50, offRoute = 60, snap = 3 }
Gps.nav = nil -- { dest, route, aim } do trecho a pé, quando não há estrada
local navRows, navRunning = {}, false

local function navCell(cont)
    local G = ns.NavData and ns.NavData[cont]
    if not G then return nil end
    navRows[cont] = navRows[cont] or setmetatable({}, { __mode = "v" }) -- parecer 050-052: o GC solta as linhas
    local rows = navRows[cont]
    return function(r, c)
        if r < 1 or r > G.rows or c < 1 or c > G.cols then return 0 end
        local row = rows[r]
        if not row then row = ns.Nav.Row(G.lines[r]); rows[r] = row end
        return row[c] or 0
    end, G
end

-- Spec 034, R7a: o pulo entre pontas de estrada só vale se a malha tiver chão ligado no meio.
-- Uma função por continente (o Roads.Path guarda o preparo do grafo por ela).
local jumpChecks = {}
roadJumpCheck = function(cont)
    if jumpChecks[cont] == nil then
        local cell, G = navCell(cont)
        jumpChecks[cont] = cell and function(ax, ay, bx, by) return ns.Nav.Clear(cell, G, ax, ay, bx, by) end or false
    end
    return jumpChecks[cont] or nil
end

-- Célula do ponto; numa célula sem saída (encosta, prédio), a transitável mais perto (até 3).
local function navSnap(cell, G, x, y)
    local r0, c0 = math.floor((G.x0 - x) / G.cell) + 1, math.floor((G.y0 - y) / G.cell) + 1
    for d = 0, NAV.snap do
        for dr = -d, d do
            for dc = -d, d do
                if math.max(math.abs(dr), math.abs(dc)) == d and cell(r0 + dr, c0 + dc) > 0 then return { r0 + dr, c0 + dc } end
            end
        end
    end
    return { r0, c0 }
end

-- R3/R4: o mesmo destino do trecho a pé da estrada (ponto de voo, passagem, entrada ou alvo).
local function walkDest(t)
    local leg, gate, door = Gps.leg, Gps.gate, Gps.door
    return leg and { x = leg.from.x, y = leg.from.y } or gate and { x = gate.x, y = gate.y }
        or door and { x = door.x, y = door.y } or { x = t.world[2], y = t.world[3] }
end

local function sameDest(a, b) return a and b and a.x == b.x and a.y == b.y end
local navFailed -- parecer 050-052: { key } do último par sem caminho; não refaz o A* para o mesmo par

local function updateNav()
    local t = Gps.target
    if not (t and t.world) or Gps.road or ns.FP.db.gps.nav == false then Gps.nav = nil; return end
    local dest = walkDest(t)
    -- parecer 050-052: destino mudou, o caminho antigo sai já (mesmo com busca em andamento)
    if Gps.nav and not sameDest(Gps.nav.dest, dest) then Gps.nav = nil end
    if navRunning or (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) then return end
    local cont, px, py = playerWorld()
    if not cont or cont ~= t.world[1] then Gps.nav = nil; return end
    if Gps.nav then return end
    local dx, dy = px - dest.x, py - dest.y
    if math.sqrt(dx * dx + dy * dy) <= NAV.minDist then Gps.navNone = nil; return end -- parecer 050-053: perto, sem aviso
    local cell, G = navCell(cont)
    if not cell then return end
    local from, to = navSnap(cell, G, px, py), navSnap(cell, G, dest.x, dest.y)
    local key = string.format("%d:%d>%d:%d", from[1], from[2], to[1], to[2])
    if navFailed == key then return end
    navRunning = ns.FP.RunCoroutine("nav", function(yield)
        return ns.Nav.Path(cell, from, to, { yield = yield, margin = 60, max = 120000, links = G.links }) -- spec 060, R6
    end, function(ok, path)
        navRunning = false
        if not ok then ns.FP.Debug("gps: caminho descartado: " .. tostring(path)); navFailed = key; return end
        if Gps.target ~= t or not sameDest(walkDest(t), dest) then Gps.nav = nil; return end
        if not path then
            ns.FP.Debug("gps: sem caminho pelo relevo")
            navFailed, Gps.nav = key, nil
            Gps.navNone = dest -- spec 050, R5: a seta avisa que não achou caminho a pé
            return
        end
        navFailed, Gps.navNone = nil, nil
        local route = { { x = px, y = py } }
        for i = 2, #path - 1 do
            route[#route + 1] = { x = G.x0 - (path[i][1] - 0.5) * G.cell, y = G.y0 - (path[i][2] - 0.5) * G.cell }
        end
        route[#route + 1] = dest
        Gps.nav = { dest = dest, route = route, aim = { lost = NAV.offRoute } }
        ns.FP.Debug(string.format("gps: pelo relevo (%d células)", #path))
    end) or false
end

-- Spec 034, R8b: o fim da estrada até o destino pela malha, em corrotina (constituição 5 e 6).
-- Sem caminho, fica a reta de antes.
local tailRunning = false
local tailFailed -- { x, y } do destino sem caminho pela malha: não refaz a busca (parecer 034-r8b)
local function updateRoadTail()
    local road = Gps.road
    if not (road and road.tailFrom) or road.tailDone or tailRunning then return end
    if sameDest(tailFailed, road.dest) then road.tailDone = true; return end
    local cont = playerWorld()
    local cell, G = navCell(cont)
    if not cell then road.tailDone = true; return end
    local from, to = navSnap(cell, G, road.tailFrom.x, road.tailFrom.y), navSnap(cell, G, road.dest.x, road.dest.y)
    tailRunning = ns.FP.RunCoroutine("roadtail", function(yield)
        return ns.Nav.Path(cell, from, to, { yield = yield, margin = 20, max = 20000, links = G.links })
    end, function(ok, path)
        tailRunning = false
        road.tailDone = true
        if Gps.road ~= road then return end
        if not (ok and path) then
            tailFailed = { x = road.dest.x, y = road.dest.y }
            ns.FP.Debug("gps: fim da estrada em reta (sem caminho pela malha): " .. tostring(path))
            return
        end
        local pts = {}
        for i = 2, #path - 1 do
            pts[#pts + 1] = { x = G.x0 - (path[i][1] - 0.5) * G.cell, y = G.y0 - (path[i][2] - 0.5) * G.cell }
        end
        road.route = Gps.WithTail(road.route, pts)
        ns.FP.Debug(string.format("gps: fim da estrada pela malha (%d células)", #path))
    end) or false
end

-- Título mostrado na seta (R2): com trecho de voo, "Voar: A > B · depois: <título>".
function Gps.ShownTitle()
    local t = Gps.target
    if not t then return nil end
    local leg = Gps.leg
    if not leg then
        if Gps.gate then -- spec 049, R4; spec 064, R4: aviso de zona perigosa no caminho
            return ns.Gates.Title(Gps.gate, ns.Guide.AreaName, t.title) .. (t.danger and (" · cuidado: " .. t.danger) or "")
        end
        if Gps.door then return ns.Caves.Title(Gps.door, t.title) end -- spec 038, R6
        return t.title
    end
    return string.format("Voar: %s > %s · depois: %s", tostring(leg.from.name), tostring(leg.to.name), tostring(t.title))
end

------------------------------------------------------------------------------------------
-- Seta na tela
------------------------------------------------------------------------------------------
local arrow
local function buildArrow()
    local db = ns.FP.db.gps
    local f = CreateFrame("Button", "ForeverPlannerArrow", UIParent)
    f:SetSize(64, 84)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("RightButtonUp")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.x, db.y = x, y
    end)
    f:SetScript("OnClick", function() Gps.Clear(); ns.FP.db.following = nil; ns.FP.Fire("CHANGED") end)

    local glow = f:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    glow:SetSize(84, 84); glow:SetPoint("TOP", 0, 10)
    glow:SetVertexColor(0.58, 0.51, 0.79, 0.55)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    tex:SetSize(56, 56); tex:SetPoint("TOP")
    tex:SetVertexColor(0.70, 0.55, 1.0)
    f.tex = tex

    local dist = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dist:SetPoint("TOP", tex, "BOTTOM", 0, 2); f.dist = dist
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOP", dist, "BOTTOM", 0, -1); title:SetWidth(220); f.title = title
    local info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOP", title, "BOTTOM", 0, -2); info:SetWidth(260); info:SetJustifyH("CENTER")
    f.info = info

    -- Botão "+" (spec 006, R9): menu com Recalcular rota, Ir entregar e Limpar o log.
    local plus = CreateFrame("Button", nil, f)
    plus:SetSize(22, 22); plus:SetPoint("LEFT", tex, "RIGHT", 2, 0)
    local plusText = plus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    plusText:SetPoint("CENTER"); plusText:SetText("+")
    plus:SetScript("OnClick", function(self) ns.QuickMenu.Toggle(self) end)
    plus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Recalcular rota · Ir entregar · Limpar o log"); GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local acc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        Gps.UpdateArrow(self)
    end)
    f:Hide()
    return f
end

function Gps.UpdateArrow(f)
    local t = Gps.target
    if not t then f:Hide(); return end
    local ok, cont, px, py = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return nil end
        local c, w = C_Map.GetWorldPosFromMapPos(mapID, pos)
        if not w then return nil end
        local x, y = w:GetXY()
        return c, x, y
    end)
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not ok or not px or Util.IsSecret(px) or not facing or Util.IsSecret(facing) or not t.world then
        f.tex:SetAlpha(0.3); f.dist:SetText("?")
        return
    end
    f.tex:SetAlpha(1)
    if cont ~= t.world[1] then f.dist:SetText("outro continente"); return end
    -- R3: a chegada é sempre no alvo final; a seta aponta para o ponto de voo se houver trecho.
    local _, dist = Gps.Relative(px, py, t.world[2], t.world[3], facing)
    local leg, door = Gps.leg, Gps.door
    local aimX, aimY = t.world[2], t.world[3]
    if leg then aimX, aimY = leg.from.x, leg.from.y
    elseif Gps.gate then -- spec 049, R4: mira a passagem; perto dela, refaz (do outro lado, a próxima)
        local g = Gps.gate
        local _, gateDist = Gps.Relative(px, py, g.x, g.y, facing)
        local now = _G.GetTime and _G.GetTime() or 0
        if gateDist <= GATE_ARRIVE and now - (t.gateAt or 0) >= LEARN_EVERY then
            t.gateAt = now
            t.gatePassed = gateKey(g) -- a troca de zona (ZONE) libera; até lá, segue para o alvo
            if Gps.UpdateGate() then Gps.UpdateDoor(); Gps.RefreshWaypoint() end
        end
        if Gps.gate then aimX, aimY = Gps.gate.x, Gps.gate.y end
    elseif door then -- spec 038, R5: mira a entrada; ao chegar nela, refaz (dentro, a seta vai ao alvo)
        local _, doorDist = Gps.Relative(px, py, door.x, door.y, facing)
        local now = _G.GetTime and _G.GetTime() or 0
        if doorDist <= (ns.FP.db.gps.arriveYards or 12) and now - (t.doorAt or 0) >= LEARN_EVERY then
            t.doorAt = now
            if Gps.UpdateDoor() then Gps.RefreshWaypoint() end
        end
        door = Gps.door
        if door then aimX, aimY = door.x, door.y end
    end
    -- Spec 034, R9/R10: com caminho, mira 30 jd à frente nele; longe dele, descarta e o ticker replaneja.
    local road, distText = Gps.road, nil
    if road then
        local okAim, aim, off, left = pcall(ns.Roads.Aim, road.route, { x = px, y = py }, ROAD.ahead, road.aim)
        if not okAim then
            Gps.road = nil
            ns.FP.Debug("gps: estrada descartada na seta: " .. tostring(aim))
        elseif not aim or off > ROAD.offRoute then
            Gps.road = nil
            ns.FP.Debug(string.format("gps: fora da estrada (%d yd)", off or -1))
        elseif left > 1 then
            aimX, aimY = aim.x, aim.y
            distText = string.format("%d yd pela estrada", left)
        end
    end
    -- Spec 050, R3/R4: sem estrada, o caminho pelo relevo; longe dele, descarta e o ticker refaz.
    local nav = not Gps.road and Gps.nav or nil
    if nav and not sameDest(nav.dest, walkDest(t)) then nav = nil end -- parecer 050-052: caminho de outro destino
    local noPath = not Gps.road and not nav and sameDest(Gps.navNone, walkDest(t)) -- spec 050, R5
    if nav then
        local okAim, aim, off, left = pcall(ns.Roads.Aim, nav.route, { x = px, y = py }, NAV.ahead, nav.aim)
        if not okAim or not aim or off > NAV.offRoute then
            Gps.nav = nil
            ns.FP.Debug(string.format("gps: fora do caminho (%s)", okAim and tostring(off and math.floor(off)) or tostring(aim)))
        elseif left > 1 then
            aimX, aimY = aim.x, aim.y
            distText = string.format("%d yd pelo caminho", left)
        end
    end
    local rel, aimDist = Gps.Relative(px, py, aimX, aimY, facing)
    f.tex:SetRotation(rel)
    f.dist:SetText(distText or string.format(noPath and "%d yd (sem caminho a pé conhecido)" or "%d yd", aimDist))
    if dist <= (ns.FP.db.gps.arriveYards or 12) and not t.arrived then
        t.arrived = true
        ns.FP.Debug(string.format("gps: chegou (%d yd) %s", dist, tostring(t.title)))
        PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
        ns.FP.Fire("GPS_ARRIVED", t)
    end
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
-- Waypoint nativo, TomTom e título da seta no ponto mostrado: o ponto de voo (R2) ou o alvo.
local ticker -- timer do replanejamento (spec 024), vivo enquanto houver alvo

-- Ponto do mapa do continente convertido para o mapa da zona (para o pino nativo); sem a API, igual.
zonePoint = function(cmap, x, y)
    local ok, mapID, zx, zy = pcall(function()
        local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(cmap, x / 100, y / 100)
        if not (info and info.mapID and C_Map.GetMapPosFromWorldPos) then return nil end
        local cont, w = C_Map.GetWorldPosFromMapPos(cmap, CreateVector2D(x / 100, y / 100))
        local _, pos = C_Map.GetMapPosFromWorldPos(cont, w, info.mapID)
        if not pos then return nil end
        local px, py = pos:GetXY()
        return info.mapID, px * 100, py * 100
    end)
    if ok and mapID then return mapID, zx, zy end
    return cmap, x, y
end

local function clearWaypoints()
    if tomtomUID and _G.TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
    tomtomUID = nil
    if C_Map.ClearUserWaypoint and ns.FP.db.gps.native then pcall(C_Map.ClearUserWaypoint) end
end
showWaypoint = function()
    local t = Gps.target
    if not t then return end
    local db = ns.FP.db.gps
    local mapID, x, y = t.mapID, t.x, t.y
    if Gps.leg then mapID, x, y = Gps.leg.from.mapID, Gps.leg.from.mx, Gps.leg.from.my
    elseif Gps.gate and Gps.gate.m and Gps.gate.mx then -- spec 049: pino na passagem
        mapID, x, y = Gps.gate.m, Gps.gate.mx, Gps.gate.my
    elseif Gps.door and Gps.door.m and Gps.door.mx then -- spec 038, R5: pino na entrada
        mapID, x, y = Gps.door.m, Gps.door.mx, Gps.door.my
    end
    if Gps.leg and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        mapID, x, y = zonePoint(mapID, x, y) -- pino no mapa da zona do ponto de voo
    end
    local title = Gps.ShownTitle()
    clearWaypoints()
    if db.tomtom and _G.TomTom and TomTom.AddWaypoint then
        tomtomUID = TomTom:AddWaypoint(mapID, x / 100, y / 100,
            { title = title, persistent = false, minimap = true, world = true, from = "ForeverPlanner" })
    end
    if db.native and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap
        and C_Map.CanSetUserWaypointOnMap(mapID) then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
    end
    if arrow then arrow.title:SetText(title) end
end
function Gps.RefreshWaypoint() showWaypoint() end
function Gps.SetTarget(mapID, x, y, title)
    local t = Gps.target
    if t and t.mapID == mapID and math.abs(t.x - x) < 0.01 and math.abs(t.y - y) < 0.01 and t.title == title then
        return -- mesmo alvo: evita recriar waypoint a cada QUEST_LOG_UPDATE
    end
    Gps.taxiHint = nil -- spec 057, R2: quem define o alvo com voo põe a dica depois
    Gps.Clear(true)
    local db = ns.FP.db.gps
    local world
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
        if pos then local wx, wy = pos:GetXY(); world = { cont, wx, wy } end
    end
    Gps.target = { mapID = mapID, x = x, y = y, title = title, world = world }
    ns.FP.Debug(string.format("gps: alvo %s @%s %.1f,%.1f mundo=%s", tostring(title), tostring(mapID), x, y, tostring(world ~= nil)))
    local ok, leg = pcall(reroute)
    Gps.leg = ok and leg or nil
    Gps.UpdateGate() -- spec 049
    Gps.UpdateDoor() -- spec 038
    updateRoad()
    updateRoadTail() -- spec 034, R8b
    updateNav() -- spec 050
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(REROUTE_EVERY, Gps.Reroute) end
    if db.arrow then arrow = arrow or buildArrow() end
    showWaypoint()
    if db.arrow then
        arrow.info:SetText(Gps.info and table.concat(Gps.info, "\n") or "")
        arrow:Show()
    end
    ns.FP.Fire("GPS_TARGET", Gps.target)
end

-- Spec 024: refaz o plano de voo; se o trecho mudar, troca waypoint e título.
local function legKey(leg) return leg and (tostring(leg.from.name) .. ">" .. tostring(leg.to.name)) or "" end
function Gps.Reroute()
    if not Gps.target then return end
    local ok, leg = pcall(reroute)
    if not ok then leg = nil end
    local legChanged = legKey(leg) ~= legKey(Gps.leg)
    if legChanged then
        Gps.leg = leg
        ns.FP.Debug("gps: rota " .. (leg and legKey(leg) or "a pé"))
    end
    local gateChanged = Gps.UpdateGate() -- spec 049
    if Gps.UpdateDoor() or legChanged or gateChanged then showWaypoint() end -- spec 038
    updateRoad()
    updateRoadTail() -- spec 034, R8b
    updateNav() -- spec 050
end

-- R18: contexto sob a seta (hub, parada i de N, próximas). nil apaga.
function Gps.SetInfo(lines)
    Gps.info = lines
    if arrow then arrow.info:SetText(lines and table.concat(lines, "\n") or "") end
end

function Gps.Clear(silent)
    if Gps.target then ns.FP.Debug("gps: limpo") end
    Gps.target = nil
    Gps.leg = nil
    if ns.Guide then ns.Guide.tripQuest = nil end -- parecer 057-058
    Gps.taxiHint = nil -- parecer 057-058: dica velha faria o voo auto ir a um destino que a seta não pede
    Gps.road = nil
    Gps.door = nil
    Gps.gate = nil
    Gps.nav = nil
    if ticker then ticker:Cancel(); ticker = nil end
    Gps.SetInfo(nil)
    clearWaypoints()
    if arrow then arrow:Hide() end
    if not silent then ns.FP.Fire("GPS_TARGET", nil) end
end

-- Spec 049: trocou de zona, refaz (a passagem cruzada some e vem a próxima).
ns.FP.On("ZONE", function()
    if Gps.target then Gps.target.gatePassed = nil; Gps.Reroute() end
end)

return Gps
