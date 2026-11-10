-- UI/Theme.lua: visual escuro com roxo de Warlock e verde vil para destaques.
local _, ns = ...
local Theme = {}
ns.Theme = Theme

local FLAT = "Interface\\Buttons\\WHITE8X8"

Theme.c = {
    bg      = { 0.06, 0.05, 0.09, 0.96 },
    panel   = { 0.10, 0.08, 0.15, 0.95 },
    row     = { 0.13, 0.11, 0.19, 0.85 },
    rowAlt  = { 0.11, 0.09, 0.16, 0.85 },
    hover   = { 0.30, 0.22, 0.45, 0.55 },
    border  = { 0.58, 0.51, 0.79, 1.00 }, -- cor de classe do Warlock
    accent  = { 0.70, 0.55, 1.00, 1.00 },
    fel     = { 0.45, 0.90, 0.35, 1.00 },
    gold    = { 1.00, 0.82, 0.30, 1.00 },
    muted   = { 0.62, 0.60, 0.70, 1.00 },
    text    = { 0.93, 0.92, 0.96, 1.00 },
    danger  = { 1.00, 0.40, 0.40, 1.00 },
}

Theme.stateColors = {
    pegar    = { 1.00, 0.82, 0.30 },
    fazer    = { 0.70, 0.55, 1.00 },
    entregar = { 0.45, 0.90, 0.35 },
}

function Theme.Backdrop(f, bg, border)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg or Theme.c.panel))
    f:SetBackdropBorderColor(unpack(border or { 0, 0, 0, 0.8 }))
end

function Theme.Panel(parent, bg, border)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.Backdrop(f, bg, border)
    return f
end

function Theme.Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    fs:SetTextColor(unpack(color or Theme.c.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Botão chato com hover; kind = "primary" | "ghost"
function Theme.Button(parent, label, width, height, onClick, kind)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 100, height or 22)
    local primary = kind == "primary"
    local base = primary and { 0.36, 0.26, 0.58, 1 } or { 0.16, 0.13, 0.23, 1 }
    Theme.Backdrop(b, base, primary and Theme.c.border or { 0.30, 0.26, 0.40, 1 })
    b.label = Theme.Text(b, 11, Theme.c.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.45, 0.33, 0.70, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(base)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Pílula colorida (estado da quest, tags de build)
function Theme.Badge(parent, width)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width or 62, 16)
    Theme.Backdrop(f, { 0, 0, 0, 0.35 }, { 1, 1, 1, 0.6 })
    f.text = Theme.Text(f, 9, Theme.c.text, "OUTLINE")
    f.text:SetPoint("CENTER")
    function f:Set(label, rgb)
        self.text:SetText(label)
        self.text:SetTextColor(rgb[1], rgb[2], rgb[3])
        self:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 0.9)
        self:SetBackdropColor(rgb[1] * 0.2, rgb[2] * 0.2, rgb[3] * 0.2, 0.8)
    end
    return f
end

function Theme.Divider(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(FLAT)
    t:SetVertexColor(Theme.c.border[1], Theme.c.border[2], Theme.c.border[3], 0.35)
    t:SetHeight(1)
    return t
end

-- Área rolável simples (para conteúdo de altura variável)
function Theme.ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        local v = math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(v)
    end)
    sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
    sf.child = child
    return sf
end

return Theme
