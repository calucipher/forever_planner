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
-- Sem o atlas do ponto: indicador comum do jogo na cor certa.
local FALLBACK = { yes = "Interface\\COMMON\\Indicator-Green", no = "Interface\\COMMON\\Indicator-Red",
    check = "Interface\\COMMON\\Indicator-Yellow" }

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

local function paint(pin, p)
    local color = COLOR[key(p.known)]
    if p.atlas and pin.icon:SetAtlas(p.atlas) ~= false and pin.icon:GetAtlas() then
        pin.icon:SetDesaturated(true)
        pin.icon:SetVertexColor(color[1], color[2], color[3])
    else
        pin.icon:SetTexture(FALLBACK[key(p.known)])
        pin.icon:SetDesaturated(false)
        pin.icon:SetVertexColor(1, 1, 1)
    end
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
        paint(pin, p)
        pin:SetSize(SIZE, SIZE)
        pin:SetScale(1 / scale)
        pin:SetFrameLevel(math.min(canvas:GetFrameLevel() + 1990, 9000)) -- logo abaixo dos de masmorra
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
