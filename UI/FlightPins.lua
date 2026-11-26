-- UI/FlightPins.lua: pontos de voo no mapa-múndi, verde descoberto e vermelho a descobrir (spec 044).
-- Frames do addon sobre o canvas do mapa, como UI/DungeonPins.lua: sem data provider da Blizzard
-- (sem taint). Atualiza na troca de mapa e, com o mapa aberto, no máximo 5 vezes por segundo.
local _, ns = ...
local Pins = {}
ns.FlightPins = Pins

local INTERVAL, SIZE = 0.2, 16
local MAP_TYPES = { [2] = true, [3] = true } -- continente e zona (R2); masmorra, micro e órfão não
-- known: true verde, false vermelho, nil amarelo (a conferir, R2a).
local function key(known) return known == nil and "check" or (known and "yes" or "no") end
local COLOR = { yes = { 0.25, 1, 0.25 }, no = { 1, 0.2, 0.2 }, check = { 1, 0.85, 0.2 } }
-- Emenda R2b da spec 044 (26/11/2026, visto no jogo: nos Barrens só os pontos dos vizinhos apareciam):
-- o atlas que o jogo dá para o ponto (o da Horda, por exemplo) pode não existir no Forever, e o pino
-- ficava invisível. Todo pino usa o atlas neutro, que aparece, tingido pela cor do estado; sem ele, o
-- ícone da própria janela de voo do Forever (TaxiFrame.lua).
local ATLAS = "TaxiNode_Neutral"
local FALLBACK = "Interface\\TaxiFrame\\UI-Taxi-Icon-White"

local pool = {}

local function showTip(pin)
    local p = pin.data
    if not p then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.name or "Ponto de voo", 1, 1, 1)
    if p.known then
        GameTooltip:AddLine("Descoberto", 0.45, 0.9, 0.35)
    elseif p.known == nil then
        GameTooltip:AddLine("Abra um mestre de voo neste continente para o addon conferir", 1, 0.85, 0.2, true)
    else
        GameTooltip:AddLine("Ainda não descoberto: fale com o mestre de voo para abrir", 1, 0.35, 0.35, true)
    end
    GameTooltip:AddLine("Clique: seta até aqui", 0.6, 0.6, 0.7)
    GameTooltip:Show()
end

local function acquire(canvas, i)
    local pin = pool[i]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints()
        pin:SetScript("OnEnter", showTip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", function(self)
            local p = self.data
            if p then ns.Gps.SetTarget(p.mapID, p.x, p.y, "Ponto de voo: " .. tostring(p.name)) end
        end)
        pool[i] = pin
    end
    return pin
end

local function paint(pin)
    local color = COLOR[key(pin.data.known)]
    pin.icon:SetAtlas(ATLAS)
    if not pin.icon:GetAtlas() then pin.icon:SetTexture(FALLBACK) end
    pin.icon:SetDesaturated(true)
    pin.icon:SetVertexColor(color[1], color[2], color[3])
end

local function hideFrom(i)
    for k = i, #pool do pool[k]:Hide(); pool[k].data = nil end
end

local function nodesFor(mapID)
    local T = _G.C_TaxiMap
    if T and T.ShouldMapShowTaxiNodes and T.ShouldMapShowTaxiNodes(mapID) then return {} end -- R3: o jogo já desenha
    return ns.Planner.FlightNodes(mapID)
end

local lastMap, lastScale
function Pins.Refresh(force)
    local map = _G.WorldMapFrame
    if not (map and map:IsShown() and map.ScrollContainer and map.ScrollContainer.Child) then return end
    local canvas = map.ScrollContainer.Child
    local mapID = map:GetMapID()
    local scale = map.ScrollContainer.GetCanvasScale and map.ScrollContainer:GetCanvasScale() or 1
    if not force and mapID == lastMap and scale == lastScale then return end
    lastMap, lastScale = mapID, scale
    local info = mapID and C_Map.GetMapInfo(mapID)
    if ns.FP.db.flightPins == false or not (info and MAP_TYPES[info.mapType]) then
        hideFrom(1); return
    end
    local list = nodesFor(mapID)
    local w, h = canvas:GetSize()
    for i, p in ipairs(list) do
        local pin = acquire(canvas, i)
        pin.data = p
        paint(pin)
        pin:SetSize(SIZE, SIZE)
        pin:SetScale(1 / scale)
        -- spec 044, R2c: acima dos marcadores de quest (Sepulcher, hub de quest, ficava coberto)
        pin:SetFrameLevel(math.min(canvas:GetFrameLevel() + 3000, 9500))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", p.x / 100 * w * scale, -p.y / 100 * h * scale)
        pin:Show()
    end
    hideFrom(#list + 1)
end

local function build()
    local map = _G.WorldMapFrame
    if Pins.frame or not (map and map.ScrollContainer) then return Pins.frame end
    local f = CreateFrame("Frame", nil, map)
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt) -- filho do mapa: só roda com ele aberto
        elapsed = elapsed + dt
        if elapsed < INTERVAL then return end
        elapsed = 0
        local ok, err = pcall(Pins.Refresh)
        if not ok then ns.FP.Debug("voos: pinos falharam: " .. tostring(err)) end
    end)
    Pins.frame = f
    return f
end

-- Diagnóstico (/fp voos lista): o que o jogo devolve para o mapa aberto (ou o da zona) e o que fica.
function Pins.Diag()
    local map = _G.WorldMapFrame
    local mapID = (map and map:IsShown() and map:GetMapID()) or (ns.Guide and ns.Guide.ZoneMap(C_Map.GetBestMapForUnit("player")))
    local T, E = _G.C_TaxiMap, _G.Enum
    if not (mapID and T and T.GetTaxiNodesForMap and E and E.FlightPathFaction) then ns.FP.Print("sem a API de voo agora."); return end
    local ok, raw = pcall(T.GetTaxiNodesForMap, mapID)
    if not ok or type(raw) ~= "table" then ns.FP.Print("GetTaxiNodesForMap falhou: " .. tostring(raw)); return end
    local info = C_Map.GetMapInfo(mapID)
    local kept = {}
    for _, p in ipairs(ns.Planner.FlightNodes(mapID)) do kept[p.id] = p end
    local out = { map = mapID, name = info and info.name, type = info and info.mapType, faction = (_G.UnitFactionGroup("player")),
        show = T.ShouldMapShowTaxiNodes and T.ShouldMapShowTaxiNodes(mapID) or false, nodes = {} }
    ns.FP.Print(string.format("mapa %s (%s, tipo %s): %d ponto(s) do jogo", tostring(mapID), tostring(out.name), tostring(out.type), #raw))
    for _, n in ipairs(raw) do
        local p = n.position
        local x, y = p and p.x, p and p.y
        local k = kept[n.nodeID]
        local state = k and (k.known == true and "verde" or (k.known == false and "vermelho" or "amarelo")) or "fora"
        local line = string.format("  %s · id %s · facção %s · %.3f, %.3f · %s", tostring(n.name), tostring(n.nodeID),
            tostring(n.faction), x or -1, y or -1, state)
        ns.FP.Print(line)
        out.nodes[#out.nodes + 1] = line
    end
    ns.FP.db.voosDiag = out
end

-- R7: na janela de voo, o jogo diz quais pontos do continente o personagem conhece.
local function learn()
    local T, E = _G.C_TaxiMap, _G.Enum
    if not (T and T.GetAllTaxiNodes and ns.FP.db) then return end
    local cmap = ns.Planner.ContinentMap(C_Map.GetBestMapForUnit("player"))
    if not cmap then return end
    local ok, raw = pcall(T.GetAllTaxiNodes, cmap)
    if not ok or type(raw) ~= "table" or #raw == 0 then return end -- lista vazia não apaga o que se sabe
    local states = (E and E.FlightPathState) or { Current = 0, Reachable = 1 }
    ns.FP.db.taxiKnown = ns.FP.db.taxiKnown or {}
    local before = ns.FP.db.taxiKnown[cmap]
    local now = ns.Util.TaxiKnown(raw, states)
    ns.FP.db.taxiKnown[cmap] = now
    local changed = not before
    for id in pairs(now) do if not (before and before[id]) then changed = true end end
    if changed then ns.FP.Fire("TAXI_KNOWN") end -- spec 045, R6: o circuito tira a parada aberta
end

-- Spec 057, R2–R4: destaca o destino da seta na janela de voo; com voo auto, voa.
local glow, marked
local function unmark() -- parecer 057-058: os TaxiButton são reaproveitados por índice
    if marked then marked:UnlockHighlight(); marked = nil end
    if glow then glow:Hide() end
end
local function markDestination()
    local db = ns.FP.db
    unmark()
    if db.taxiMark == false and db.taxiAuto ~= true then return end
    if not ns.Gps.target then return end -- sem alvo da seta, nada a marcar
    local leg = ns.Gps.leg
    local target = (leg and leg.to and leg.to.name) or ns.Gps.taxiHint
    if not (target and _G.NumTaxiNodes and _G.TaxiNodeName) then return end
    local names = {}
    for i = 1, _G.NumTaxiNodes() do names[i] = _G.TaxiNodeName(i) end
    local idx = ns.Util.TaxiPick(names, target)
    if not idx then ns.FP.Debug("voos: destino " .. tostring(target) .. " fora da janela"); return end
    if _G.TaxiNodeGetType and _G.TaxiNodeGetType(idx) ~= "REACHABLE" then return end
    local button = _G["TaxiButton" .. idx]
    if db.taxiMark ~= false and button then
        button:LockHighlight(); marked = button
        if _G.TaxiNodeOnButtonEnter then _G.TaxiNodeOnButtonEnter(button) end -- rota desenhada e tooltip
        if not glow then
            glow = CreateFrame("Frame", nil, button:GetParent())
            local tex = glow:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(); tex:SetTexture("Interface\\Buttons\\CheckButtonGlow"); tex:SetBlendMode("ADD")
            glow:SetSize(44, 44)
        end
        glow:SetParent(button:GetParent()); glow:ClearAllPoints(); glow:SetPoint("CENTER", button); glow:Show()
        ns.FP.Print("voo marcado: " .. names[idx])
    end
    if db.taxiAuto == true and _G.TakeTaxiNode then
        C_Timer.After(0.5, function()
            local frame = _G.TaxiFrame
            if not (frame and frame:IsShown()) or _G.TaxiNodeName(idx) ~= names[idx] then return end -- parecer
            ns.FP.Print("voando para " .. names[idx])
            _G.TakeTaxiNode(idx)
        end)
    end
end

-- R5: ponto recém-descoberto fica verde sem /reload.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs({ "TAXIMAP_OPENED", "TAXI_NODE_STATUS_CHANGED", "TAXIMAP_CLOSED" }) do
    pcall(loader.RegisterEvent, loader, ev)
end
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_WorldMap" then build() end
        return
    end
    if event == "TAXIMAP_OPENED" then -- R7: só com a janela de voo aberta
        local ok, err = pcall(learn)
        if not ok then ns.FP.Debug("voos: aprender falhou: " .. tostring(err)) end
        C_Timer.After(0.1, function() -- spec 057: depois do TaxiFrame_OnShow, que posiciona os botões
            local okM, errM = pcall(markDestination)
            if not okM then ns.FP.Debug("voos: marcar destino falhou: " .. tostring(errM)) end
        end)
    end
    if event == "TAXIMAP_CLOSED" then unmark(); if _G.GameTooltip then _G.GameTooltip:Hide() end end
    lastMap = nil
end)
ns.FP.On("DB_READY", build)
