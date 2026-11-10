-- UI/MinimapButton.lua: botão no minimapa e entrada no menu de addons (spec 004).
local _, ns = ...
local Button = {}
ns.MinimapButton = Button

local ICON = "Interface\\Icons\\Spell_Shadow_SummonFelHunter"
local RADIUS = 105 -- distância do centro do minimapa (minimapa padrão)

-- Função pura (A1): ângulo em graus -> deslocamento x, y a partir do centro.
function Button.Position(angle, radius)
    local rad = math.rad(angle or 0)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

local function place(b)
    local x, y = Button.Position(ns.FP.db.minimap.angle, RADIUS)
    b:ClearAllPoints()
    b:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

-- Ângulo do cursor em volta do centro do minimapa (arrastar, R4).
local function cursorAngle()
    local mx, my = _G.Minimap:GetCenter()
    local scale = _G.Minimap:GetEffectiveScale()
    local cx, cy = _G.GetCursorPosition()
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cFF9482C9Forever|r Planner", 1, 1, 1)
    GameTooltip:AddLine("Clique: abre/fecha o painel", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Clique direito: segue o melhor hub", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Arraste: move o botão", 0.6, 0.6, 0.7)
    GameTooltip:Show()
end

function Button.Build()
    if Button.frame or not _G.Minimap then return Button.frame end
    local b = CreateFrame("Button", "ForeverPlannerMinimapButton", _G.Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.Guide.FollowBest() else ns.UI.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(f)
            ns.FP.db.minimap.angle = cursorAngle()
            place(f)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Button.frame = b
    place(b)
    b:SetShown(not ns.FP.db.minimap.hide)
    return b
end

-- R6
function Button.Toggle()
    local m = ns.FP.db.minimap
    m.hide = not m.hide
    if Button.frame then Button.frame:SetShown(not m.hide) end
    ns.FP.Print(m.hide and "botão do minimapa escondido (/fp minimapa mostra de novo)." or "botão do minimapa visível.")
end

-- R5: o .toc aponta para esta função (## AddonCompartmentFunc).
_G.ForeverPlanner_OnAddonCompartmentClick = function(_, mouse)
    if mouse == "RightButton" then ns.Guide.FollowBest() else ns.UI.Toggle() end
end

ns.FP.On("DB_READY", Button.Build)

return Button
