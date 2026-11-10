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

-- Título mostrado na seta (R2): com trecho de voo, "Voar: A > B · depois: <título>".
function Gps.ShownTitle()
    local t = Gps.target
    if not t then return nil end
    local leg = Gps.leg
    if not leg then return t.title end
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

    -- Botão "+" (spec 006, R9): menu com Melhor hub, Ir entregar e Limpar o log.
    local plus = CreateFrame("Button", nil, f)
    plus:SetSize(22, 22); plus:SetPoint("LEFT", tex, "RIGHT", 2, 0)
    local plusText = plus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    plusText:SetPoint("CENTER"); plusText:SetText("+")
    plus:SetScript("OnClick", function(self) ns.QuickMenu.Toggle(self) end)
    plus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Melhor hub · Ir entregar · Limpar o log"); GameTooltip:Show()
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
    local leg = Gps.leg
    local aimX, aimY = t.world[2], t.world[3]
    if leg then aimX, aimY = leg.from.x, leg.from.y end
    local rel, aimDist = Gps.Relative(px, py, aimX, aimY, facing)
    f.tex:SetRotation(rel)
    f.dist:SetText(string.format("%d yd", aimDist))
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
    if Gps.leg then mapID, x, y = Gps.leg.from.mapID, Gps.leg.from.mx, Gps.leg.from.my end
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
    if legKey(leg) == legKey(Gps.leg) then return end
    Gps.leg = leg
    ns.FP.Debug("gps: rota " .. (leg and legKey(leg) or "a pé"))
    showWaypoint()
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
    if ticker then ticker:Cancel(); ticker = nil end
    Gps.SetInfo(nil)
    clearWaypoints()
    if arrow then arrow:Hide() end
    if not silent then ns.FP.Fire("GPS_TARGET", nil) end
end

return Gps
