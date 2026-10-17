--[[
    NoctraLib :: thememanager.lua
    ----------------------------------------------------------------
    Sistema de temas.

    Estrutura de pastas:
        NoctraLibSettings/
        └── themes/
            ├── default.txt          (nome do tema padrão)
            ├── meu_tema.json
            └── outro_tema.json

    Uso:
        local TM = NoctraLib.ThemeManager
        TM:SetFolder("NoctraLibSettings")
        TM:LoadDefault()
        TM:ApplyToTab(Window:AddTab("Temas"))

    Contém:
      • 18 temas built-in (Noctra, Tokyo Night, Dracula, Nord, ...)
      • WCAG 2.1 contrast checking
      • Custom themes salvos em disco
      • Import/Export JSON
      • UI completa (ThemeManager:CreateThemeManager)

    Retorna uma função Attach(Library) que devolve a Library com
    o ThemeManager já pendurado em Library.ThemeManager.
]]

return function(Library)

    local cloneref = (cloneref or clonereference or function(x) return x end)
    local HttpService = cloneref(game:GetService("HttpService"))

    --================================================================
    --  FIX is_____ (mesma proteção do SaveManager)
    --================================================================
    local _isfolder, _isfile, _listfiles = isfolder, isfile, listfiles

    local function safeFolder(p)
        if not _isfolder then return false end
        local ok, res = pcall(_isfolder, p)
        return ok and res == true
    end
    local function safeFile(p)
        if not _isfile then return false end
        local ok, res = pcall(_isfile, p)
        return ok and res == true
    end
    local function safeList(p)
        if not _listfiles then return {} end
        local ok, res = pcall(_listfiles, p)
        return ok and typeof(res) == "table" and res or {}
    end
    local function ensureFolder(p)
        if not p or p == "" then return end
        if safeFolder(p) then return end
        if makefolder then pcall(makefolder, p) end
    end
    local function delFile(p) if delfile then pcall(delfile, p) end end
    local function writeFile(p, data)
        if not writefile then return false, "writefile indisponível" end
        local ok, err = pcall(writefile, p, data)
        return ok, err
    end
    local function readFile(p)
        if not readfile then return nil, "readfile indisponível" end
        local ok, data = pcall(readfile, p)
        if not ok then return nil, data end
        return data
    end

    --================================================================
    --  Helpers
    --================================================================
    local function Trim(s) return s:match("^%s*(.-)%s*$") end
    local function IsEmpty(s) return typeof(s) ~= "string" or Trim(s) == "" end
    local function IsValidFolderName(name)
        return typeof(name) == "string"
            and Trim(name) ~= ""
            and not name:find('[<>:"|%?%*%z]')
    end

    --================================================================
    --  WCAG 2.1 — Relative Luminance / Contrast Ratio
    --================================================================
    local ContrastWarnThreshold = 4.5
    local SrgbLinearThreshold   = 0.03928
    local SrgbLinearDivisor     = 12.92
    local SrgbGammaOffset       = 0.055
    local SrgbGammaScale        = 1.055
    local SrgbGammaExponent     = 2.4
    local LR, LG, LB            = 0.2126, 0.7152, 0.0722
    local ContrastOffset        = 0.05

    local function LinearizeChannel(c)
        if c <= SrgbLinearThreshold then
            return c / SrgbLinearDivisor
        end
        return ((c + SrgbGammaOffset) / SrgbGammaScale) ^ SrgbGammaExponent
    end

    local function GetRelativeLuminance(color)
        return LR * LinearizeChannel(color.R)
             + LG * LinearizeChannel(color.G)
             + LB * LinearizeChannel(color.B)
    end

    local function GetContrastRatio(a, b)
        local la, lb = GetRelativeLuminance(a), GetRelativeLuminance(b)
        local lighter, darker = math.max(la, lb), math.min(la, lb)
        return (lighter + ContrastOffset) / (darker + ContrastOffset)
    end

    --================================================================
    --  TABELA ThemeManager
    --================================================================
    local SchemeIndexes = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor" }

    local ThemeManager = {
        Library = nil,

        Folder = "NoctraLibSettings",

        AppliedToTab = false,
        DefaultThemeName = nil,

        ContrastLabel = nil,
        ContrastWasPoor = false,

        -- Temas built-in — { [ordem], { dados } }
        BuiltInThemes = {

            ["Noctra"] = {
                1,
                {
                    FontColor = "ffffff",
                    MainColor = "0c0c0c",
                    AccentColor = "ff8a1e",
                    BackgroundColor = "000000",
                    OutlineColor = "262626",
                    BackgroundImage = "",
                },
            },

            ["Tokyo Night"] = {
                2,
                {
                    FontColor = "ffffff",
                    MainColor = "191925",
                    AccentColor = "6759b3",
                    BackgroundColor = "16161f",
                    OutlineColor = "323232",
                    BackgroundImage = "",
                },
            },

            ["Dracula"] = {
                3,
                {
                    FontColor = "f8f8f2",
                    MainColor = "44475a",
                    AccentColor = "ff79c6",
                    BackgroundColor = "282a36",
                    OutlineColor = "6272a4",
                    BackgroundImage = "",
                },
            },

            ["Nord"] = {
                4,
                {
                    FontColor = "eceff4",
                    MainColor = "3b4252",
                    AccentColor = "88c0d0",
                    BackgroundColor = "2e3440",
                    OutlineColor = "4c566a",
                    BackgroundImage = "",
                },
            },

            ["Catppuccin"] = {
                5,
                {
                    FontColor = "d9e0ee",
                    MainColor = "302d41",
                    AccentColor = "f5c2e7",
                    BackgroundColor = "1e1e2e",
                    OutlineColor = "575268",
                    BackgroundImage = "",
                },
            },

            ["Monokai"] = {
                6,
                {
                    FontColor = "f8f8f2",
                    MainColor = "272822",
                    AccentColor = "f92672",
                    BackgroundColor = "1e1f1c",
                    OutlineColor = "49483e",
                    BackgroundImage = "",
                },
            },

            ["Gruvbox"] = {
                7,
                {
                    FontColor = "ebdbb2",
                    MainColor = "3c3836",
                    AccentColor = "fb4934",
                    BackgroundColor = "282828",
                    OutlineColor = "504945",
                    BackgroundImage = "",
                },
            },

            ["Solarized"] = {
                8,
                {
                    FontColor = "839496",
                    MainColor = "073642",
                    AccentColor = "cb4b16",
                    BackgroundColor = "002b36",
                    OutlineColor = "586e75",
                    BackgroundImage = "",
                },
            },

            ["One Dark"] = {
                9,
                {
                    FontColor = "abb2bf",
                    MainColor = "282c34",
                    AccentColor = "c678dd",
                    BackgroundColor = "21252b",
                    OutlineColor = "5c6370",
                    BackgroundImage = "",
                },
            },

            ["Cyberpunk"] = {
                10,
                {
                    FontColor = "f9f9f9",
                    MainColor = "262335",
                    AccentColor = "00ff9f",
                    BackgroundColor = "1a1a2e",
                    OutlineColor = "413c5e",
                    BackgroundImage = "",
                },
            },

            ["Oceanic Next"] = {
                11,
                {
                    FontColor = "d8dee9",
                    MainColor = "1b2b34",
                    AccentColor = "6699cc",
                    BackgroundColor = "16232a",
                    OutlineColor = "343d46",
                    BackgroundImage = "",
                },
            },

            ["Material"] = {
                12,
                {
                    FontColor = "eeffff",
                    MainColor = "212121",
                    AccentColor = "82aaff",
                    BackgroundColor = "151515",
                    OutlineColor = "424242",
                    BackgroundImage = "",
                },
            },

            ["Jester"] = {
                13,
                {
                    FontColor = "ffffff",
                    MainColor = "242424",
                    AccentColor = "db4467",
                    BackgroundColor = "1c1c1c",
                    OutlineColor = "373737",
                    BackgroundImage = "",
                },
            },

            ["Mint"] = {
                14,
                {
                    FontColor = "ffffff",
                    MainColor = "242424",
                    AccentColor = "3db488",
                    BackgroundColor = "1c1c1c",
                    OutlineColor = "373737",
                    BackgroundImage = "",
                },
            },

            ["Ubuntu"] = {
                15,
                {
                    FontColor = "ffffff",
                    MainColor = "3e3e3e",
                    AccentColor = "e2581e",
                    BackgroundColor = "323232",
                    OutlineColor = "191919",
                    BackgroundImage = "",
                },
            },

            ["Quartz"] = {
                16,
                {
                    FontColor = "ffffff",
                    MainColor = "232330",
                    AccentColor = "426e87",
                    BackgroundColor = "1d1b26",
                    OutlineColor = "27232f",
                    BackgroundImage = "",
                },
            },

            ["BBot"] = {
                17,
                {
                    FontColor = "ffffff",
                    MainColor = "1e1e1e",
                    AccentColor = "7e48a3",
                    BackgroundColor = "232323",
                    OutlineColor = "141414",
                    BackgroundImage = "",
                },
            },

            ["Fatality"] = {
                18,
                {
                    FontColor = "ffffff",
                    MainColor = "1e1842",
                    AccentColor = "c50754",
                    BackgroundColor = "191335",
                    OutlineColor = "3c355d",
                    BackgroundImage = "",
                },
            },
        },
    }

    function ThemeManager:SetLibrary(lib)
        ThemeManager.Library = lib
    end

    --================================================================
    --  Paths
    --================================================================
    local function SplitPath(p)
        local out, cur = {}, ""
        for part in string.gmatch(p, "[^/]+") do
            cur = cur == "" and part or (cur .. "/" .. part)
            table.insert(out, cur)
        end
        return out
    end

    local function GetFolderPath()
        if IsEmpty(ThemeManager.Folder) then return nil end
        return string.format("%s/themes", ThemeManager.Folder)
    end

    local function GetThemePath(name)
        local base = GetFolderPath()
        if not base then return nil end
        return string.format("%s/%s.json", base, name)
    end

    local function GetDefaultThemePath()
        local base = GetFolderPath()
        if not base then return nil end
        return string.format("%s/default.txt", base)
    end

    local function DoesThemeExist(name)
        if ThemeManager.BuiltInThemes[name] then return true end
        local p = GetThemePath(name)
        return p and safeFile(p) or false
    end

    --================================================================
    --  Folder tree
    --================================================================
    function ThemeManager:GetPaths()
        local p = GetFolderPath()
        return p and SplitPath(p) or {}
    end

    function ThemeManager:BuildFolderTree(skip)
        local paths = ThemeManager:GetPaths()
        if #paths == 0 then return false end
        if skip and safeFolder(paths[1]) then return true end
        for _, p in ipairs(paths) do
            if not safeFolder(p) then ensureFolder(p) end
        end
        return true
    end

    function ThemeManager:CheckFolderTree()
        return ThemeManager:BuildFolderTree(true)
    end

    function ThemeManager:SetFolder(folder)
        if not IsValidFolderName(folder) then
            error("ThemeManager:SetFolder — nome inválido")
        end
        ThemeManager.Folder = folder
        ThemeManager:BuildFolderTree()
    end

    --================================================================
    --  Custom themes (disco)
    --================================================================
    function ThemeManager:ReloadCustomThemes()
        local base = GetFolderPath()
        if not base then return {} end

        local files = safeList(base)
        local names = {}
        for _, path in ipairs(files) do
            local raw = path:match("(.+)%..+$")
            if raw then
                local pos = raw:gsub("\\", "/"):find("/[^/]*$")
                local name = pos and raw:sub(pos + 1) or raw
                if name and name ~= "default" then
                    table.insert(names, name)
                end
            end
        end
        return names
    end

    function ThemeManager:GetCustomTheme(name)
        if IsEmpty(name) then return nil end
        local p = GetThemePath(name)
        if not p or not safeFile(p) then return nil end

        local content = readFile(p)
        if not content then return nil end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        if not ok or typeof(decoded) ~= "table" then return nil end
        return decoded
    end

    function ThemeManager:SaveCustomTheme(name)
        if IsEmpty(name) then return false, "Nome inválido" end
        if string.lower(name) == "default" then
            return false, "Nome 'default' é reservado"
        end

        local p = GetThemePath(name)
        if not p then return false, "Caminho inválido" end

        ThemeManager:CheckFolderTree()

        local encoded, err = ThemeManager:SaveJSON()
        if not encoded then return false, err end

        local ok, werr = writeFile(p, encoded)
        if not ok then return false, "Falha ao escrever: " .. tostring(werr) end
        return true
    end

    function ThemeManager:Delete(name)
        if IsEmpty(name) then return false, "Nenhum tema selecionado" end
        local p = GetThemePath(name)
        if not p or not safeFile(p) then return false, "Arquivo não existe" end

        delFile(p)

        if name == ThemeManager.DefaultThemeName then
            ThemeManager:DeleteDefaultTheme()
        end
        return true
    end

    --================================================================
    --  Default theme
    --================================================================
    function ThemeManager:GetDefaultTheme()
        ThemeManager:CheckFolderTree()
        local p = GetDefaultThemePath()
        if not p then return "none", false, "Caminho inválido" end
        if not safeFile(p) then return "none", false, "Nenhum tema padrão definido" end

        local content = readFile(p)
        if typeof(content) ~= "string" then return "none", false, "Falha ao ler" end

        content = Trim(content)
        if not DoesThemeExist(content) then
            return "none", false, "Tema não encontrado"
        end

        ThemeManager.DefaultThemeName = content
        return content, true
    end

    function ThemeManager:SaveDefault(name)
        if IsEmpty(name) then return false, "Nenhum tema selecionado" end

        ThemeManager:CheckFolderTree()
        local p = GetDefaultThemePath()
        if not p then return false, "Caminho inválido" end
        if not DoesThemeExist(name) then return false, "Tema não existe" end

        local ok, err = writeFile(p, name)
        if not ok then return false, tostring(err) end

        ThemeManager.DefaultThemeName = name
        return true
    end

    function ThemeManager:LoadDefault()
        local name, ok, err = ThemeManager:GetDefaultTheme()
        if not ok then
            if err ~= "Nenhum tema padrão definido" then
                ThemeManager.Library:NotifyError("Tema padrão", tostring(err))
            end
            return
        end

        if ThemeManager:GetCustomTheme(name) then
            local ok2, err2 = ThemeManager:ApplyTheme(name)
            if not ok2 then
                ThemeManager.Library:NotifyError("Falha ao aplicar padrão", tostring(err2))
                return
            end
        else
            -- built-in
            local opt = ThemeManager.Library.Options and ThemeManager.Library.Options["ThemeManager_ThemeList"]
            if opt then opt:SetValue(name) end
        end

        ThemeManager.Library:NotifySuccess("Tema padrão", name)
    end

    function ThemeManager:DeleteDefaultTheme()
        ThemeManager:CheckFolderTree()
        local p = GetDefaultThemePath()
        if not p or not safeFile(p) then return false, "Nenhum padrão definido" end
        delFile(p)
        ThemeManager.DefaultThemeName = nil
        return true
    end

    --================================================================
    --  Aplicação de temas
    --================================================================
    function ThemeManager:GetContrastReport()
        local lib = ThemeManager.Library
        if not lib or not lib.Options then
            return { Ratio = math.huge, PairName = "", Passes = true }
        end

        local fontOpt = lib.Options.FontColor
        local bgOpt   = lib.Options.BackgroundColor
        local mainOpt = lib.Options.MainColor

        if not (fontOpt and bgOpt and mainOpt) then
            return { Ratio = math.huge, PairName = "", Passes = true }
        end

        local surfaces = {
            { Name = "fonte vs. fundo",    Color = bgOpt.Value },
            { Name = "fonte vs. main",     Color = mainOpt.Value },
        }

        local worst, worstName = math.huge, ""
        for _, s in ipairs(surfaces) do
            local ratio = GetContrastRatio(fontOpt.Value, s.Color)
            if ratio < worst then
                worst, worstName = ratio, s.Name
            end
        end

        return {
            Ratio = worst,
            PairName = worstName,
            Passes = worst >= ContrastWarnThreshold,
        }
    end

    function ThemeManager:UpdateContrastWarning()
        local label = ThemeManager.ContrastLabel
        if not label or label.Destroyed then return end

        local lib = ThemeManager.Library
        local report = ThemeManager:GetContrastReport()

        if report.Passes then
            label:SetText(string.format("Contraste: bom (%.1f:1)", report.Ratio))
        else
            label:SetText(string.format(
                "Contraste baixo (%.1f:1) entre %s. Recomendado: %.1f:1.",
                report.Ratio, report.PairName, ContrastWarnThreshold
            ))
            if not ThemeManager.ContrastWasPoor then
                lib:Notify({
                    Title = "Tema com baixo contraste",
                    Description = string.format(
                        "Contraste de %.1f:1 entre %s. Texto pode ser difícil de ler.",
                        report.Ratio, report.PairName
                    ),
                    Type = "Error",
                    Time = 10,
                })
            end
        end

        ThemeManager.ContrastWasPoor = not report.Passes
    end

    function ThemeManager:ThemeUpdate()
        local lib = ThemeManager.Library
        for _, idx in ipairs(SchemeIndexes) do
            local el = lib.Options and lib.Options[idx]
            if el then lib.Scheme[idx] = el.Value end
        end
        lib:UpdateColorsUsingRegistry()
        ThemeManager:UpdateContrastWarning()
    end

    function ThemeManager:ApplyThemeData(data)
        if typeof(data) ~= "table" then return false, "Dados inválidos" end

        local lib = ThemeManager.Library

        for idx, value in pairs(data) do
            if idx == "VideoLink" then continue end

            local el = lib.Options and lib.Options[idx]
            local finalValue = value

            if idx == "FontFace" then
                if typeof(value) ~= "string" or not Enum.Font[value] then continue end
                lib:SetFont(Enum.Font[value])

            elseif idx == "BackgroundImage" then
                if typeof(value) ~= "string" then continue end
                lib:SetBackgroundImage(value)

            elseif table.find(SchemeIndexes, idx) then
                local ok, color = pcall(Color3.fromHex, value)
                if not ok then continue end
                finalValue = color
                lib.Scheme[idx] = color

            else
                continue
            end

            if el then el:SetValue(finalValue) end
        end

        ThemeManager:ThemeUpdate()
        return true
    end

    function ThemeManager:ApplyTheme(name)
        if IsEmpty(name) then return false, "Nenhum tema selecionado" end

        local custom = ThemeManager:GetCustomTheme(name)
        local builtin = ThemeManager.BuiltInThemes[name]

        local data = custom or (builtin and builtin[2])
        if not data then return false, "Tema não encontrado" end

        return ThemeManager:ApplyThemeData(data)
    end

    --================================================================
    --  JSON Import / Export
    --================================================================
    function ThemeManager:SaveJSON()
        local lib = ThemeManager.Library
        if not lib or not lib.Options then
            return nil, "Library não configurada"
        end

        local out = {
            FontFace = lib.Options.FontFace and lib.Options.FontFace.Value or "Code",
            BackgroundImage = lib.Options.BackgroundImage and lib.Options.BackgroundImage.Value or "",
        }

        for _, idx in ipairs(SchemeIndexes) do
            local el = lib.Options[idx]
            if el then out[idx] = el.Value:ToHex() end
        end

        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, out)
        if not ok then return nil, "Falha ao codificar" end
        return encoded
    end

    function ThemeManager:LoadJSON(content)
        if IsEmpty(content) then return false, "JSON vazio" end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        if not ok or typeof(decoded) ~= "table" then
            return false, "JSON inválido"
        end

        for _, idx in ipairs(SchemeIndexes) do
            if typeof(decoded[idx]) ~= "string" then
                return false, "JSON incompleto (falta " .. idx .. ")"
            end
        end

        return ThemeManager:ApplyThemeData(decoded)
    end

    --================================================================
    --  UI
    --================================================================
    local function ShowConfirm(Condition, Idx, Title, Description, DestructiveText, DestructiveAction)
        if not Condition() then return DestructiveAction() end

        return ThemeManager.Library.Window:AddDialog(Idx, {
            Title = Title,
            Description = Description,
            AutoDismiss = false,
            FooterButtons = {
                Cancel = {
                    Title = "Cancelar",
                    Variant = "Ghost",
                    Callback = function(d) d:Dismiss() end,
                },
                Destructive = {
                    Title = DestructiveText,
                    Variant = "Destructive",
                    Callback = function(d)
                        d:Dismiss()
                        DestructiveAction()
                    end,
                },
            },
        })
    end

    function ThemeManager:CreateThemeManager(Box)
        assert(ThemeManager.Library, "SetLibrary antes")

        local builtInNames = {}
        for name, _ in pairs(ThemeManager.BuiltInThemes) do
            table.insert(builtInNames, name)
        end
        table.sort(builtInNames, function(a, b)
            return ThemeManager.BuiltInThemes[a][1] < ThemeManager.BuiltInThemes[b][1]
        end)

        local CustomList, CustomName, ThemeList, FontFace, BgImage, DefaultLabel, JSONInput

        local function RefreshCustom()
            CustomList:SetValues(ThemeManager:ReloadCustomThemes())
            CustomList:SetValue(nil)
        end
        local function RefreshDefaultLabel()
            local name = ThemeManager:GetDefaultTheme()
            DefaultLabel:SetText("Tema padrão: " .. name)
        end

        -- Cores editáveis
        local function ColorOption(text, key)
            local label = Box:AddLabel(text)
            local cp = label:AddColorPicker(key, {
                Default = ThemeManager.Library.Scheme[key],
            })
            return cp
        end

        local BgColor  = ColorOption("Cor de fundo",  "BackgroundColor")
        local MainClr  = ColorOption("Cor principal", "MainColor")
        local AccentCl = ColorOption("Accent",        "AccentColor")
        local OutlineC = ColorOption("Contorno",      "OutlineColor")
        local FontClr  = ColorOption("Cor da fonte",  "FontColor")

        ThemeManager.ContrastLabel = Box:AddLabel("Contraste: ...", true)

        FontFace = Box:AddDropdown("FontFace", {
            Text = "Fonte",
            Default = "Code",
            Values = { "Roboto", "Code", "BuilderSans", "Fantasy", "Gotham", "Jura", "RobotoMono", "SourceSans" },
            AllowNull = false,
            Multi = false,
        })

        BgImage = Box:AddInput("BackgroundImage", {
            Text = "Imagem de fundo",
            Default = "",
            Finished = true,
            ClearTextOnFocus = false,
            ClearTextOnBlur = false,
        })

        Box:AddDivider()

        ThemeList = Box:AddDropdown("ThemeManager_ThemeList", {
            Text = "Temas disponíveis",
            Values = builtInNames,
            AllowNull = true,
            Multi = false,
            FormatDisplayValue = function(v)
                if v ~= "Noctra" and v == ThemeManager.DefaultThemeName then
                    return v .. " (padrão)"
                end
                return v
            end,
        })

        Box:AddButton({
            Text = "Aplicar tema",
            Func = function()
                local name = ThemeList.Value
                if not name then
                    Library:NotifyError("Nenhum tema", "Selecione um primeiro.")
                    return
                end
                ThemeManager:ApplyTheme(name)
                Library:NotifySuccess("Tema aplicado", name)
            end,
        })

        Box:AddButton({
            Text = "Definir como padrão",
            Func = function()
                local name = ThemeList.Value
                if not name then
                    Library:NotifyError("Nenhum tema", "Selecione um primeiro.")
                    return
                end
                ThemeManager:SaveDefault(name)
                Library:NotifySuccess("Padrão salvo", name)
                RefreshDefaultLabel()
            end,
        })

        Box:AddDivider()

        -- Custom theme
        CustomName = Box:AddInput("ThemeManager_CustomName", { Text = "Nome do tema custom" })

        local function SaveWithContrastCheck(name, successMsg, onSaved)
            local function DoSave()
                local ok, err = ThemeManager:SaveCustomTheme(name)
                if not ok then
                    Library:NotifyError("Falha ao salvar", tostring(err))
                    return
                end
                Library:NotifySuccess(successMsg, name)
                if onSaved then onSaved() end
            end

            local report = ThemeManager:GetContrastReport()
            if report.Passes then
                DoSave()
                return
            end

            ShowConfirm(
                function() return true end,
                "TM_LowContrast",
                "Contraste baixo",
                string.format(
                    "Este tema tem contraste %.1f:1 entre %s (recomendado: %.1f:1). Salvar mesmo assim?",
                    report.Ratio, report.PairName, ContrastWarnThreshold
                ),
                "Salvar mesmo assim",
                DoSave
            )
        end

        Box:AddButton({
            Text = "Criar tema custom",
            Func = function()
                local name = CustomName.Value
                if IsEmpty(name) then
                    Library:NotifyError("Nome vazio", "")
                    return
                end
                if string.lower(name) == "default" then
                    Library:NotifyError("Nome reservado", "")
                    return
                end

                ShowConfirm(
                    function() return ThemeManager:GetCustomTheme(name) ~= nil end,
                    "TM_Create",
                    "Tema já existe",
                    string.format("Já existe '%s'. Sobrescrever?", name),
                    "Sobrescrever",
                    function() SaveWithContrastCheck(name, "Tema criado", RefreshCustom) end
                )
            end,
        })

        CustomList = Box:AddDropdown("ThemeManager_CustomList", {
            Text = "Temas custom salvos",
            Values = ThemeManager:ReloadCustomThemes(),
            AllowNull = true,
            Multi = false,
        })

        Box:AddButton({
            Text = "Carregar tema custom",
            Func = function()
                local name = CustomList.Value
                if not name then
                    Library:NotifyError("Nenhum tema", "")
                    return
                end
                ThemeManager:ApplyTheme(name)
                Library:NotifySuccess("Tema aplicado", name)
            end,
        })

        Box:AddButton({
            Text = "Sobrescrever custom",
            Func = function()
                local name = CustomList.Value
                if not name then
                    Library:NotifyError("Nenhum tema", "")
                    return
                end
                SaveWithContrastCheck(name, "Tema sobrescrito")
            end,
        })

        Box:AddButton({
            Text = "Deletar custom",
            DoubleClick = true,
            Func = function()
                local name = CustomList.Value
                if not name then
                    Library:NotifyError("Nenhum tema", "")
                    return
                end
                local ok, err = ThemeManager:Delete(name)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Deletado", name)
                RefreshCustom()
                RefreshDefaultLabel()
            end,
        })

        Box:AddButton("Atualizar lista", RefreshCustom)

        Box:AddButton({
            Text = "Resetar padrão",
            Func = function()
                ThemeManager:DeleteDefaultTheme()
                Library:NotifySuccess("Padrão resetado", "")
                RefreshDefaultLabel()
            end,
        })

        DefaultLabel = Box:AddLabel("Tema padrão: ...", true)

        Box:AddDivider()

        JSONInput = Box:AddInput("ThemeManager_JSON", { Text = "Tema JSON" })

        Box:AddButton({
            Text = "Importar tema",
            Func = function()
                local content = JSONInput.Value
                if IsEmpty(content) then
                    Library:NotifyError("Vazio", "")
                    return
                end
                local ok, err = ThemeManager:LoadJSON(content)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Importado", "")
            end,
        })

        Box:AddButton({
            Text = "Exportar tema atual",
            Func = function()
                local encoded, err = ThemeManager:SaveJSON()
                if not encoded then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                JSONInput:SetValue(encoded)
                if setclipboard then
                    setclipboard(encoded)
                    Library:NotifySuccess("Copiado", "Tema exportado pro clipboard.")
                end
            end,
        })

        -- Handlers de mudança
        ThemeList:OnChanged(function() ThemeManager:ApplyTheme(ThemeList.Value) end)

        local function Update()
            ThemeManager:ThemeUpdate()
        end

        BgColor:OnChanged(Update)
        MainClr:OnChanged(Update)
        AccentCl:OnChanged(Update)
        OutlineC:OnChanged(Update)
        FontClr:OnChanged(Update)
        FontFace:OnChanged(function(v)
            if Enum.Font[v] then
                Library:SetFont(Enum.Font[v])
            end
        end)
        BgImage:OnChanged(function(v)
            Library:SetBackgroundImage(v)
        end)

        ThemeManager:LoadDefault()
        ThemeManager:UpdateContrastWarning()
        ThemeManager.AppliedToTab = true
        RefreshDefaultLabel()

        return Box
    end

    function ThemeManager:ApplyToTab(Tab, IconName)
        local Box = Tab:AddGroupbox({
            Side = "Left",
            Name = "Temas",
            IconName = IconName or nil,
        })
        return ThemeManager:CreateThemeManager(Box)
    end

    function ThemeManager:ApplyToGroupbox(Groupbox)
        return ThemeManager:CreateThemeManager(Groupbox)
    end

    --================================================================
    --  Auto-build + attach
    --================================================================
    ThemeManager:BuildFolderTree()

    Library.ThemeManager = ThemeManager
    ThemeManager:SetLibrary(Library)

    return Library
end