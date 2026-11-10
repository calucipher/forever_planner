-- Debug.lua: /fp diag — retrato do estado (spec 009, R5). Mostra no chat e grava no registro.
local ADDON, ns = ...
local Tools = {}
ns.DebugTools = Tools

local function yes(v) return v and "sim" or "não" end

local function version()
    local get = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

function Tools.Lines()
    local FP, D, G, Gd = ns.FP, ns.Data, ns.Gps, ns.Guide
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = "diag " .. string.format(fmt, ...) end
    local _, class = UnitClass("player")
    add("v%s classe=%s nível=%s", version(), tostring(class), tostring(UnitLevel("player")))
    local best = C_Map.GetBestMapForUnit("player")
    local p = ns.Planner.PlayerPoint()
    add("mapa=%s zona=%s pos=%s", tostring(best), tostring(Gd.ZoneMap(best)),
        p and p.x and string.format("%.1f,%.1f", p.x, p.y) or "?")
    add("dados QuestieDB=%s índice=%s", yes(D.Q ~= nil), yes(D.ready))
    local g = FP.db.guide
    local nsat = 0
    for _ in pairs(g and g.satellites or {}) do nsat = nsat + 1 end
    add("hub=%s satélites=%d seguindo-quest=%s auto=%s", g and g.hub or "nenhum", nsat,
        tostring(FP.db.following or "não"), yes(FP.db.auto))
    local cur = Gd.current
    add("parada=%s ponto=%s", cur and cur.id or "nenhuma",
        cur and cur.point and string.format("%.1f,%.1f", cur.point.x or -1, cur.point.y or -1) or "-")
    local t = G.target
    add("gps=%s @%s mundo=%s", t and t.title or "sem alvo",
        t and string.format("%s %.1f,%.1f", tostring(t.mapID), t.x, t.y) or "-", yes(t and t.world))
    add("falhas guia=%d%s quests=%d", Gd.failures.count, Gd.failures.first and (" (" .. Gd.failures.first .. ")") or "",
        ns.Planner.failures.count)
    add("eventos ausentes=%s erros guardados=%d", #FP.missingEvents > 0 and table.concat(FP.missingEvents, ",") or "nenhum",
        #(FP.db.debugErrors or {}))
    for _, l in ipairs(ns.ClassGuide.DiagLines()) do add("%s", l) end -- spec 011, A11
    add("tempo por morte=%.1f s fator XP=%.2f", FP.KillSeconds(), FP.MobXPFactor())
    return lines
end

function Tools.Diag()
    local ok, lines = pcall(Tools.Lines)
    if not ok then
        ns.FP.LogError("diag: " .. tostring(lines))
        ns.FP.Print("|cFFFF5555diag falhou:|r", lines)
        return
    end
    for _, line in ipairs(lines) do
        ns.FP.Print(line)
        ns.FP.Debug(line, true) -- grava mesmo com o debug desligado
    end
    ns.FP.Print("|cFF888888registro gravado no disco no próximo /reload ou logout.|r")
end

return Tools
