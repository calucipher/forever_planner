-- UI/DungeonPins.lua: pinos de entrada de masmorra e meeting stone no mapa-múndi (spec 041, R9).
-- Frames do addon sobre o canvas do mapa: sem data provider da Blizzard (sem taint). Atualiza na
-- troca de mapa e, com o mapa aberto, no máximo 5 vezes por segundo (zoom e pan).
local _, ns = ...
local Pins = {}
ns.DungeonPins = Pins

local INTERVAL = 0.2
local SIZE = { entrance = 18, stone = 16 }
local ICONS = {
    entrance = "Interface\\Minimap\\Dungeon", -- ícone de masmorra do minimapa clássico
}
-- Atlas de borda transparente que o localizador de grupo do próprio Forever usa
-- (Blizzard_GroupFinder/Mainline/LFGList, branch forever do wow-ui-source, 15/11/2026).
local ATLAS = {
    stone = "groupfinder-icon-friend",
}

local pool = {}

local function showTip(pin)
    local p, DG = pin.data, ns.DungeonGuide
    if not p then return end
    local d = p.d
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name, 1, 1, 1)
    GameTooltip:AddLine((p.kind == "stone" and "Meeting stone" or "Entrada") .. "  " .. DG.Range(d), 0.8, 0.8, 0.8)
    if p.kind == "entrance" and p.p.est then
        GameTooltip:AddLine("Posição estimativa (" .. tostring(p.p.source or "guia") .. "). Entre uma vez para gravar.", 1, 0.82, 0.3, true)
    elseif p.kind == "entrance" and p.p.learned then
        GameTooltip:AddLine("Posição gravada no jogo.", 0.45, 0.9, 0.35)
    end
    local at = DG.AttuneText(d)
    if at then GameTooltip:AddLine(at, 1, 1, 1, true) end
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
            if not p then return end
            if p.kind == "stone" then ns.Gps.SetTarget(p.p.m, p.p.mx, p.p.my, "Meeting stone: " .. p.d.name)
            else ns.Gps.SetTarget(p.p.m, p.p.mx, p.p.my, "Entrada: " .. p.d.name .. (p.p.est and " (estimativa)" or "")) end
        end)
        pool[i] = pin
    end
    return pin
end

local function hideFrom(i)
    for k = i, #pool do pool[k]:Hide(); pool[k].data = nil end
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
    local db = ns.DungeonGuide.db()
    if db.pins == false or not (info and info.mapType and info.mapType >= ns.Guide.ZONE_MAP_TYPE) then
        hideFrom(1); return
    end
    if not ns.DungeonGuide.List() then lastMap = nil; hideFrom(1); return end -- QuestieDB carregando
    local pins = ns.DungeonGuide.InMap(mapID)
    local w, h = canvas:GetSize()
    for i, p in ipairs(pins) do
        local pin = acquire(canvas, i)
        pin.data = p
        if ATLAS[p.kind] then pin.icon:SetAtlas(ATLAS[p.kind]) else pin.icon:SetTexture(ICONS[p.kind]) end
        pin:SetSize(SIZE[p.kind], SIZE[p.kind])
        pin.icon:SetDesaturated(p.kind == "entrance" and p.p.est or false)
        pin:SetScale(1 / scale)
        pin:SetFrameLevel(math.min(canvas:GetFrameLevel() + 2000, 9000))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", p.u * w * scale, -p.v * h * scale)
        pin:Show()
    end
    hideFrom(#pins + 1)
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
        if not ok then ns.FP.Debug("masmorras: pinos falharam: " .. tostring(err)) end
    end)
    Pins.frame = f
    return f
end

ns.FP.On("DUNGEONS", function() lastMap = nil end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_WorldMap" and build() then self:UnregisterAllEvents() end
end)
ns.FP.On("DB_READY", function()
    if build() then loader:UnregisterAllEvents() end
end)
