-- UI/WorldMap.lua: faixa de nível da zona sob o cursor no mapa-múndi (spec 032, R6).
-- O texto é um FontString do addon, logo abaixo do nome da área: o rótulo e os frames da
-- Blizzard não mudam (sem taint).
local _, ns = ...
local WorldMap = {}
ns.WorldMap = WorldMap

local INTERVAL = 0.1 -- no máximo 10 vezes por segundo

-- Rótulo de área da Blizzard (o data provider que tem Label.Name), se existir.
local function areaLabel(map)
    for provider in pairs(map.dataProviders or {}) do
        local label = type(provider) == "table" and provider.Label
        if type(label) == "table" and label.Name then return label end
    end
end

-- uiMapID da zona sob o cursor; no mapa de zona sem outra zona embaixo, a própria zona.
local function hoveredMap(map)
    local canvas = map.ScrollContainer
    if not (canvas and canvas.GetNormalizedCursorPosition and map.GetMapID and canvas:IsMouseOver()) then return nil end
    local x, y = canvas:GetNormalizedCursorPosition()
    local current = map:GetMapID()
    if not (x and y and current) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(current, x, y)
    local mapID = info and info.mapID or current
    local mapInfo = C_Map.GetMapInfo(mapID)
    if not (mapInfo and mapInfo.mapType and mapInfo.mapType >= ns.Guide.ZONE_MAP_TYPE) then return nil end
    return mapID
end

local function textOf(fs)
    if type(fs) ~= "table" or not (fs.IsShown and fs.GetText) or not fs:IsShown() then return "" end
    return fs:GetText() or ""
end

-- Âncora: abaixo da descrição da Blizzard, se ela tiver texto; senão, abaixo do nome.
local function anchorOf(label)
    if not label then return nil end
    if textOf(label.Description) ~= "" then return label.Description end
    return label.Name
end

local function update(self, text, map)
    local mapID = hoveredMap(map)
    local zone = mapID and ns.Guide.MapZone(mapID)
    local lo, hi = ns.Guide.ZoneLevels(zone)
    if not lo then text:Hide(); return end
    if self.label == nil then self.label = areaLabel(map) or false end -- procura uma vez só
    local anchor = anchorOf(self.label or nil)
    if anchor ~= self.anchor then -- reposiciona só quando a âncora muda
        self.anchor = anchor
        text:ClearAllPoints()
        if anchor then
            text:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
        else
            text:SetPoint("TOP", self, "TOP", 0, -60)
        end
    end
    local label = ns.Zones.RangeLabel(lo, hi, UnitLevel("player"))
    if label ~= self.text then self.text = label; text:SetText(label) end
    text:Show()
end

function WorldMap.Build()
    local map = _G.WorldMapFrame
    if WorldMap.frame or not (map and map.GetCanvasContainer) then return WorldMap.frame end
    local f = CreateFrame("Frame", nil, map:GetCanvasContainer())
    f:SetAllPoints()
    -- strata herdada do mapa (normal ou maximizado); só o nível fica acima do rótulo da Blizzard
    f:SetFrameLevel(math.min(map:GetCanvasContainer():GetFrameLevel() + 500, 9000))
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetShadowOffset(1, -1)
    text:Hide()
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt) -- só roda com o mapa aberto (o frame é filho dele)
        elapsed = elapsed + dt
        if elapsed < INTERVAL then return end
        elapsed = 0
        update(self, text, map)
    end)
    WorldMap.frame = f
    return f
end

-- O mapa-múndi pode carregar depois do addon (Blizzard_WorldMap).
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_WorldMap" and WorldMap.Build() then self:UnregisterAllEvents() end
end)
ns.FP.On("DB_READY", function()
    if WorldMap.Build() then loader:UnregisterAllEvents() end
end)
