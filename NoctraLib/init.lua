--[[
    NoctraLib :: init.lua
    ----------------------------------------------------------------
    Ponto de entrada. Este é o ÚNICO arquivo que você executa.

    Uso:
        local Noctra = loadstring(game:HttpGet(
            "https://SEU_HOST/NoctraLib/init.lua"
        ))()

        local Window = Noctra:CreateWindow({ Title = "NoBreath" })

    O que faz:
      1. Define BASE_URL dos módulos
      2. Busca cada módulo (HttpGet → fallback readfile)
      3. Compila com loadstring em ambiente isolado
      4. Encadeia: library → window → elements → extras → savemanager → thememanager
      5. Retorna a Library final com tudo pendurado
]]

--================================================================
--  CONFIG — MUDE ISSO
--================================================================
local BASE_URL = "https://raw.githubusercontent.com/Onilte/NoBreath/main/"

-- Se você quiser testar local (VS Code + executor com writefile), use:
-- local BASE_URL = "NoctraLib/"   -- e o FetchModule vai ler do disco

--================================================================
--  Ambiente base
--================================================================
local cloneref = (cloneref or clonereference or function(x) return x end)

--================================================================
--  Fetch de módulo — tenta HTTP primeiro, cai pro disco
--================================================================
local function FetchModule(path)
    -- 1. Tenta leitura local primeiro (mais rápido em dev)
    if readfile and isfile then
        local okFile, exists = pcall(isfile, path)
        if okFile and exists then
            local okRead, content = pcall(readfile, path)
            if okRead and typeof(content) == "string" and #content > 0 then
                return content
            end
        end
    end

    -- 2. Tenta via HTTP
    if game and game.HttpGet then
        local ok, content = pcall(function()
            return game:HttpGet(BASE_URL .. path)
        end)
        if ok and typeof(content) == "string" and #content > 0 then
            return content
        end
    end

    -- 3. Falhou tudo
    error(string.format(
        "[NoctraLib] Falha ao carregar módulo '%s'. Verifique BASE_URL ou hospede localmente.",
        path
    ))
end

--================================================================
--  Compilador de módulo — ambiente isolado por arquivo
--================================================================
local function LoadModule(path, extraEnv)
    local source = FetchModule(path)

    local chunk, compileErr = loadstring(source, "@NoctraLib/" .. path)
    if not chunk then
        error(string.format(
            "[NoctraLib] Erro de compilação em '%s':\n%s",
            path, tostring(compileErr)
        ))
    end

    -- Ambiente isolado: módulo vê globais normais + o que passamos
    local env = setmetatable({}, {
        __index = function(_, key)
            if extraEnv and extraEnv[key] ~= nil then
                return extraEnv[key]
            end
            return getfenv()[key]
        end,
        __newindex = function(_, key, value)
            -- Impede módulo de sobrescrever globais por acidente
            rawset(extraEnv or {}, key, value)
        end,
    })

    if setfenv then
        setfenv(chunk, env)
    end

    return chunk()
end

--================================================================
--  Carregamento em cadeia
--================================================================
local function Bootstrap()
    -- 1. library.lua — devolve a tabela base
    local libraryModule = LoadModule("library.lua")

    if typeof(libraryModule) ~= "table"
        or typeof(libraryModule.Library) ~= "table"
    then
        error("[NoctraLib] library.lua não devolveu a tabela esperada.")
    end

    local Library = libraryModule.Library

    -- 2. window.lua — devolve function(Library) → Library
    local windowAttach = LoadModule("window.lua")
    if typeof(windowAttach) ~= "function" then
        error("[NoctraLib] window.lua deve retornar uma função Attach(Library).")
    end
    Library = windowAttach(Library)

    -- 3. elements.lua
    local elementsAttach = LoadModule("elements.lua")
    if typeof(elementsAttach) == "function" then
        Library = elementsAttach(Library)
    end

    -- 4. extras.lua
    local extrasAttach = LoadModule("extras.lua")
    if typeof(extrasAttach) == "function" then
        Library = extrasAttach(Library)
    end

    -- 5. savemanager.lua (opcional)
    local okSM, smAttach = pcall(LoadModule, "savemanager.lua")
    if okSM and typeof(smAttach) == "function" then
        local ok2, err2 = pcall(smAttach, Library)
        if not ok2 then
            warn("[NoctraLib] SaveManager falhou: " .. tostring(err2))
        end
    else
        warn("[NoctraLib] SaveManager não carregado (ok se você não usa).")
    end

    -- 6. thememanager.lua (opcional)
    local okTM, tmAttach = pcall(LoadModule, "thememanager.lua")
    if okTM and typeof(tmAttach) == "function" then
        local ok2, err2 = pcall(tmAttach, Library)
        if not ok2 then
            warn("[NoctraLib] ThemeManager falhou: " .. tostring(err2))
        end
    else
        warn("[NoctraLib] ThemeManager não carregado (ok se você não usa).")
    end

    return Library
end

--================================================================
--  Executa
--================================================================
local NoctraLib = Bootstrap()

--================================================================
--  Atalhos no getgenv
--================================================================
if getgenv then
    getgenv().NoctraLib = NoctraLib
    -- alias curto — opcional
    getgenv().Noctra = NoctraLib
end

--================================================================
--  Print de boas-vindas (útil no F9)
--================================================================
print(string.format(
    "[NoctraLib] carregada — %d tabs disponíveis, %d módulos ativos.",
    (function()
        local n = 0
        for _ in pairs(NoctraLib.Tabs or {}) do n = n + 1 end
        return n
    end)(),
    (NoctraLib.SaveManager and 5 or 4)
))

return NoctraLib