-- UI/TrailTab.lua: aba Trilha (spec 047, emenda de 21/11/2026). As zonas da faixa de nível em
-- etapas, com a recomendada e as alternativas, a viagem pelas regras da seta e dos voos, o lar e as
-- masmorras. Os botões ‹ › mostram as outras faixas.
local _, ns = ...
local Theme = ns.Theme

local ROW_H = 18
-- A viagem de cada zona custa: refaz só com outra faixa, nível ou zona, ou a cada 10 s.
local CACHE_SECONDS = 10
local cache = { key = nil, at = 0, tr = nil }
local function minutes(s) return math.max(1, math.floor((s or 0) / 60 + 0.5)) end

-- Spec 047, R6: a trilha da faixa atual, etapa por etapa, com a recomendada e as alternativas.
local function trailLines(out, title, empty, tr)
    local G, LG = ns.Guide, ns.LevelGuide
    if not tr then title("Trilha"); empty("calculando (o catálogo de zonas ainda carrega)"); return end
    title(string.format("Trilha %d–%d", tr.lo, tr.hi))
    if #tr.steps == 0 then empty("nenhuma zona com quests da sua facção nesta faixa") end
    local here = G.PlayerArea()
    for i, st in ipairs(tr.steps) do
        for j, z in ipairs(st.zones) do
            local name = G.AreaName(z.zone)
            local mark = z.zone == here and " |cFF73E65A(você está aqui)|r" or ""
            local trip = z.plan and (ns.Travel.Describe(z.plan) .. " " .. LG.EstLabel(z.plan)) or "viagem ?"
            local fp = z.red > 0 and string.format(" · |cFFFF5555%d ponto(s) de voo a abrir|r", z.red) or ""
            local lead = j == 1 and string.format("  %d. ", i) or "      ou "
            local tip = { name, string.format("faixa %s · %d quests da sua facção nesta faixa (est.)",
                ns.Zones.FormatRange(z.lo, z.hi), z.quests), "Viagem: " .. trip }
            if z.plan then
                for _, s in ipairs(z.plan.steps) do
                    tip[#tip + 1] = string.format("· %s%s ~%d min", s.kind, s.label and (" " .. s.label) or "", minutes(s.seconds))
                end
            end
            if j > 1 then tip[#tip + 1] = "Alternativa da mesma etapa: viagem maior que a da recomendada." end
            out[#out + 1] = { text = string.format("%s%s  %s  |cFF888888%d quests · %s|r%s%s", lead, name,
                ns.Zones.RangeLabel(z.lo, z.hi, tr.level), z.quests, trip, fp, mark),
                action = function() LG.FollowTrip({ zone = z.zone, plan = z.plan or { seconds = 0, steps = {} }, dest = z.dest }) end,
                tip = tip, hint = "Clique: seta no primeiro trecho da viagem" }
        end
    end
    if tr.hearth then
        local h = tr.hearth
        out[#out + 1] = { text = string.format("  |cFFFFD14DMarque o lar:|r %s%s", tostring(h.name), h.place and (", " .. h.place) or ""),
            action = function() ns.Gps.SetTarget(h.point.mapID, h.point.x, h.point.y, "Lar: " .. tostring(h.name)) end,
            tip = { "Pedra de lar", "Estalajadeiro mais perto do hub com mais quests da zona recomendada desta etapa." },
            hint = "Clique: seta no estalajadeiro" }
    end
    if #tr.dungeons > 0 then
        local names = {}
        for _, d in ipairs(tr.dungeons) do names[#names + 1] = d.name .. " " .. ns.DungeonGuide.Range(d, tr.level) end
        out[#out + 1] = { text = "  |cFF888888Masmorras da faixa:|r " .. table.concat(names, ", ") }
    end
end


local function build(panel)
    local api = {}
    local shownL -- nível da faixa mostrada; nil = a do personagem

    local header = Theme.Text(panel, 12, Theme.c.text)
    header:SetPoint("TOPLEFT", 64, -6); header:SetPoint("RIGHT", panel, "RIGHT", -110, 0)
    header:SetJustifyH("LEFT")
    local prev = Theme.Button(panel, "‹", 28, 22, function()
        shownL = math.max(1, (shownL or UnitLevel("player")) - 10); api.Refresh()
    end)
    prev:SetPoint("TOPLEFT", 0, -2)
    local nextB = Theme.Button(panel, "›", 28, 22, function()
        shownL = math.min(60, (shownL or UnitLevel("player")) + 10); api.Refresh()
    end)
    nextB:SetPoint("TOPLEFT", 32, -2)
    local mine = Theme.Button(panel, "Minha faixa", 100, 22, function() shownL = nil; api.Refresh() end)
    mine:SetPoint("TOPRIGHT", 0, -2)

    local box = Theme.Panel(panel, Theme.c.panel)
    box:SetPoint("TOPLEFT", 0, -30); box:SetPoint("BOTTOMRIGHT", 0, 0)
    local render = Theme.LineList(box, ROW_H)

    -- R8: a viagem de cada zona é calculada na hora, fora de combate.
    function api.Refresh()
        if not (ns.Data.Q and ns.Data.ready) then
            header:SetText("|cFF888888Dados da QuestieDB ainda carregando...|r")
            render({})
            return
        end
        local L = UnitLevel("player")
        local key = string.format("%d:%d:%s", shownL or 0, L, tostring(ns.Guide.PlayerArea()))
        local now = _G.GetTime()
        -- R8: em corrotina e fora de combate (constituição 6); mostra o que tem e redesenha ao terminar.
        if not (cache.key == key and now - cache.at < CACHE_SECONDS) and not cache.running then
            cache.running = ns.FP.RunCoroutine("trail", function(yield)
                return ns.LevelGuide.Trail(shownL or L, yield)
            end, function(ok, res)
                cache.running = false
                if not ok then ns.FP.Debug("trilha falhou: " .. tostring(res)); res = nil end
                cache.key, cache.at, cache.tr = key, _G.GetTime(), res
                if panel:IsVisible() then api.Refresh() end
            end)
        end
        local tr = cache.key == key and cache.tr or nil
        local out = {}
        local function title(t) out[#out + 1] = { text = "|cFFB38CFF" .. t .. "|r" } end
        local function empty(t) out[#out + 1] = { text = "  |cFF888888" .. t .. "|r" } end
        trailLines(out, title, empty, tr)
        header:SetText(tr and string.format("Faixa %d–%d%s", tr.lo, tr.hi, shownL and "" or " (a sua)")
            or "|cFF888888Trilha calculando...|r")
        render(out)
        ns.UI.SetStatus("Trilha: clique numa zona para a seta levar até lá (estimativa).")
    end
    ns.FP.On("ZONE_CATALOG", function() if panel:IsVisible() then api.Refresh() end end)
    return api
end

ns.UI.RegisterTab("trail", "Trilha", build)
