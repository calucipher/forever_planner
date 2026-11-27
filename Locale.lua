-- Locale.lua: idioma do addon (spec 066). Núcleo puro: a chave é o texto em português.
--   L["Fechar"]  -> o texto no idioma ativo; sem tradução, a própria chave.
--   K("Fechar")  -> marca texto guardado na carga do arquivo (tabela de comandos, por exemplo);
--                   quem mostra traduz na hora com L[texto]. O sensor de tests/ acha os dois.
local _, ns = ...
local Locale = { tables = {}, active = "pt", early = {} }
ns.Locale = Locale

ns.L = setmetatable({}, {
    __index = function(_, key)
        -- R1a: traduzir antes do ADDON_LOADED ignora o idioma escolhido; o aceite exige zero
        if not Locale.ready then Locale.early[#Locale.early + 1] = tostring(key) end
        local t = Locale.tables[Locale.active]
        return (t and key ~= nil and t[key]) or key
    end,
})

function Locale.K(s) return s end

-- R3: o override ("pt", "en") vence; senão, ptBR é português e o resto é inglês.
-- Sem GetLocale (fora do jogo, nos testes), português.
function Locale.Pick(gameLocale, override)
    if override == "pt" or override == "en" then return override end
    if gameLocale == nil then return "pt" end
    return gameLocale == "ptBR" and "pt" or "en"
end

function Locale.Set(lang) Locale.active = lang end

Locale.Set(Locale.Pick(_G.GetLocale and _G.GetLocale(), nil)) -- na carga: pelo cliente (R3)

return Locale
