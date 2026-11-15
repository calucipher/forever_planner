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
    if a == b then return nil end
    local walk = span(player, target) / opts.run
    local total = da / opts.run + opts.overhead + span(a, b) * opts.factor / opts.fly + db / opts.run
    if total + opts.margin >= walk then return nil end
    return { from = a, to = b, walk = walk, total = total }
end

-- Spec 034, R8: ir pela estrada compensa? Caminho de Roads.Path ou nil.
function Gps.PlanRoad(player, target, graph, opts)
    if not (player and target and graph) then return nil end
    local straight = span(player, target)
    if straight <= opts.minDist then return nil end
    local path = ns.Roads.Path(graph, player, target)
    if not path or path.accessFrom > opts.maxAccess or path.accessTo > opts.maxAccess then return nil end
    if path.accessFrom + path.road + path.accessTo > opts.factor * straight then return nil end
    return path
end

------------------------------------------------------------------------------------------
-- Rota com voo (spec 024): constantes são estimativa, a calibrar no jogo
------------------------------------------------------------------------------------------
local FLIGHT = { fly = 32, factor = 1.25, overhead = 20, margin = 60 }
local REROUTE_EVERY = 2
Gps.leg = nil -- { from, to } quando a seta aponta para o ponto de voo

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
    local T = _G.C_TaxiMap
    if not (T and T.GetAllTaxiNodes and ns.Planner and ns.Planner.ContinentMap) then return {} end
    local cmap = ns.Planner.ContinentMap(C_Map.GetBestMapForUnit("player"))
    if not cmap then return {} end
    local E = _G.Enum
    local states = E and E.FlightPathState or { Reachable = 0, Current = 1 }
    local ok, raw = pcall(T.GetAllTaxiNodes, cmap)
    if not ok then return {} end
    local out = {}
    for _, p in ipairs(Util.TaxiPoints(raw, cmap, function(st) return st == states.Reachable or st == states.Current end)) do
        local c, w = C_Map.GetWorldPosFromMapPos(cmap, CreateVector2D(p.x / 100, p.y / 100))
        if w and c == cont then
            local wx, wy = w:GetXY()
            out[#out + 1] = { x = wx, y = wy, name = p.name, mapID = cmap, mx = p.x, my = p.y }
        end
    end
    return out
end

-- R2/R4: refaz o plano. Em voo, sem alvo no mundo ou em outro continente: sem trecho de voo.
local function reroute()
    local t = Gps.target
    if not (t and t.world) or (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) then return nil end
    local cont, px, py = playerWorld()
    if not cont or cont ~= t.world[1] then return nil end
    local opts = { run = ns.FP.db.runSpeed or 7, fly = FLIGHT.fly, factor = FLIGHT.factor,
        overhead = FLIGHT.overhead, margin = FLIGHT.margin }
    local plan = Gps.PlanFlight({ x = px, y = py }, { x = t.world[2], y = t.world[3] }, taxiNodes(cont), opts)
    return plan and { from = plan.from, to = plan.to } or nil
end

------------------------------------------------------------------------------------------
-- Pela estrada (spec 034): constantes são estimativa, a calibrar no jogo
------------------------------------------------------------------------------------------
local ROAD = { minDist = 400, maxAccess = 150, factor = 1.6, ahead = 30, offRoute = 60 }
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
    if t and t.world and not Gps.leg and ns.FP.db.gps.caves ~= false then
        local cont, px, py = playerWorld()
        if cont then
            local ok, d = pcall(ns.Caves.Door, caveList(), { c = cont, x = px, y = py, indoors = indoors() },
                { c = t.world[1], x = t.world[2], y = t.world[3] }, { arrive = ns.FP.db.gps.arriveYards })
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
    local flipped = ns.Caves.Learn(learnedCaves(), learnState, s)
    if flipped and Gps.target and Gps.UpdateDoor() then Gps.RefreshWaypoint() end
end
ns.FP.On("READY", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(LEARN_EVERY, function()
        local ok, err = pcall(learnTick)
        if not ok then ns.FP.Debug("gps: aprendizado de entrada falhou: " .. tostring(err)) end
    end) end
end)

-- R11/R12/R13: caminho para o trecho a pé; reaproveita o atual se o destino não mudou.
local function planRoad()
    local t = Gps.target
    if not (t and t.world) or ns.FP.db.gps.roads == false then return nil end
    if _G.UnitOnTaxi and _G.UnitOnTaxi("player") then return nil end
    local graphs = ns.RoadGraphs
    local cont, px, py = playerWorld()
    if not (graphs and cont and cont == t.world[1] and graphs[cont]) then return nil end
    local leg, door = Gps.leg, Gps.door
    local dest = leg and { x = leg.from.x, y = leg.from.y } or door and { x = door.x, y = door.y }
        or { x = t.world[2], y = t.world[3] } -- spec 038, R5: a estrada termina na entrada
    local cur = Gps.road
    if cur and cur.dest.x == dest.x and cur.dest.y == dest.y then return cur end
    if InCombatLockdown() then return nil end -- constituição 6: nada pesado em combate
    local path = Gps.PlanRoad({ x = px, y = py }, dest, graphs[cont], ROAD)
    if not path then return nil end
    -- R9/R10: a rota seguida começa no jogador e termina no destino (acessos inclusos)
    local route = { { x = px, y = py } }
    for _, pt in ipairs(path.points) do route[#route + 1] = pt end
    route[#route + 1] = dest
    path.dest, path.route, path.aim = dest, route, { lost = ROAD.offRoute }
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

-- Título mostrado na seta (R2): com trecho de voo, "Voar: A > B · depois: <título>".
function Gps.ShownTitle()
    local t = Gps.target
    if not t then return nil end
    local leg = Gps.leg
    if not leg then
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
    local rel, aimDist = Gps.Relative(px, py, aimX, aimY, facing)
    f.tex:SetRotation(rel)
    f.dist:SetText(distText or string.format("%d yd", aimDist))
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
    Gps.UpdateDoor() -- spec 038
    updateRoad()
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
    if Gps.UpdateDoor() or legChanged then showWaypoint() end -- spec 038
    updateRoad()
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
    Gps.road = nil
    Gps.door = nil
    if ticker then ticker:Cancel(); ticker = nil end
    Gps.SetInfo(nil)
    clearWaypoints()
    if arrow then arrow:Hide() end
    if not silent then ns.FP.Fire("GPS_TARGET", nil) end
end

return Gps
