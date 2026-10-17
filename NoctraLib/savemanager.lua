--[[
    NoctraLib :: savemanager.lua
    ----------------------------------------------------------------
    Persistência de configuração em disco.

    Estrutura de pastas:
        NoctraLibSettings/
        └── settings/
            ├── autoload.txt
            ├── meu_config.json
            └── outro_config.json

    Uso:
        local SaveManager = NoctraLib.SaveManager
        SaveManager:SetFolder("NoctraLibSettings")
        SaveManager:SetSubFolder("meu_hub")   -- opcional
        SaveManager:LoadAutoloadConfig()

    Salva estado de:
      • Toggle      (Value)
      • Slider      (Value)
      • Dropdown    (Value, Multi)
      • ColorPicker (Value hex, Transparency)
      • KeyPicker   (Mode, Value, Modifiers, Toggled)
      • Input       (Value)
      • Groupbox    (Collapsed, PoppedOut, PopoutPos)
      • Tabbox      (PoppedOut, PopoutPos)
      • KeybindFrame (Visible, Position)

    Retorna uma função Attach(Library) que devolve a Library com
    o SaveManager já pendurado em Library.SaveManager.
]]

return function(Library)

    local cloneref = (cloneref or clonereference or function(x) return x end)
    local HttpService = cloneref(game:GetService("HttpService"))

    --================================================================
    --  FIX is_____ functions (alguns executors erram)
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
        if makefolder then
            pcall(makefolder, p)
        end
    end

    local function delFile(p)
        if delfile then pcall(delfile, p) end
    end

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
    --  TABELA SaveManager
    --================================================================
    local SaveManager = {
        Library = nil,

        Folder    = "NoctraLibSettings",
        SubFolder = "",

        Ignore = {},            -- { [idx] = true }
        LoadingOrder = {},       -- { [type] = priority }
        UseLoadingOrder = false,

        AutoloadConfig = nil,
        Verbose = false,
    }

    function SaveManager:SetLibrary(Lib)
        SaveManager.Library = Lib
    end

    function SaveManager:SetVerbose(state)
        SaveManager.Verbose = state == true
    end

    local function Log(fmt, ...)
        if SaveManager.Verbose then
            print("[NoctraLib::SaveManager] " .. string.format(fmt, ...))
        end
    end

    --================================================================
    --  Helpers de texto / validação
    --================================================================
    local function Trim(s) return s:match("^%s*(.-)%s*$") end
    local function IsEmpty(s) return typeof(s) ~= "string" or Trim(s) == "" end
    local function IsValidFolderName(name)
        return typeof(name) == "string"
            and Trim(name) ~= ""
            and not name:find('[<>:"|%?%*%z]')
    end

    --================================================================
    --  Caminhos
    --================================================================
    local function SplitPath(path)
        local out = {}
        local cur = ""
        for part in string.gmatch(path, "[^/]+") do
            cur = cur == "" and part or (cur .. "/" .. part)
            table.insert(out, cur)
        end
        return out
    end

    local function GetFolderPath()
        if IsEmpty(SaveManager.Folder) then return nil end
        return string.format("%s/settings", SaveManager.Folder)
    end

    local function GetSubFolderPath()
        if IsEmpty(SaveManager.Folder) or IsEmpty(SaveManager.SubFolder) then return nil end
        return string.format("%s/settings/%s", SaveManager.Folder, SaveManager.SubFolder)
    end

    local function GetCurrentSettingsPath()
        return GetSubFolderPath() or GetFolderPath()
    end

    local function GetConfigPath(name)
        local base = GetCurrentSettingsPath()
        if not base then return nil end
        return string.format("%s/%s.json", base, name)
    end

    local function GetAutoloadPath()
        local base = GetCurrentSettingsPath()
        if not base then return nil end
        return string.format("%s/autoload.txt", base)
    end

    local function DoesConfigExist(name)
        local p = GetConfigPath(name)
        return p and safeFile(p) or false
    end

    --================================================================
    --  Folder helpers
    --================================================================
    function SaveManager:GetPaths()
        local p = GetSubFolderPath() or GetFolderPath()
        return p and SplitPath(p) or {}
    end

    function SaveManager:BuildFolderTree(skip)
        local paths = SaveManager:GetPaths()
        if #paths == 0 then return false end

        if skip and safeFolder(paths[1]) then
            return true
        end

        for _, p in ipairs(paths) do
            if not safeFolder(p) then ensureFolder(p) end
        end
        return true
    end

    function SaveManager:CheckFolderTree()
        return SaveManager:BuildFolderTree(true)
    end

    function SaveManager:SetFolder(folder)
        if not IsValidFolderName(folder) then
            error("SaveManager:SetFolder — nome inválido: " .. tostring(folder))
        end
        SaveManager.Folder = folder
        SaveManager:BuildFolderTree()
    end

    function SaveManager:SetSubFolder(sub)
        if not IsValidFolderName(sub) then
            error("SaveManager:SetSubFolder — nome inválido: " .. tostring(sub))
        end
        SaveManager.SubFolder = sub
        SaveManager:BuildFolderTree()
    end

    --================================================================
    --  Ignore / Loading order
    --================================================================
    function SaveManager:SetIgnoreIndexes(list)
        if typeof(list) ~= "table" then return end
        for _, idx in ipairs(list) do
            SaveManager.Ignore[idx] = true
        end
    end

    function SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({
            "BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor",
            "FontFace", "BackgroundImage",
            "ThemeManager_ThemeList", "ThemeManager_CustomThemeList",
            "ThemeManager_CustomThemeName", "ThemeManager_ThemeJSON",
        })
    end

    function SaveManager:SetLoadingOrder(enabled, order)
        SaveManager.UseLoadingOrder = enabled == true
        if typeof(order) == "table" then
            SaveManager.LoadingOrder = order
        end
    end

    --================================================================
    --  Parsers de elemento
    --================================================================
    local SpecialValueParser = {
        UDim2 = {
            Encode = function(v)
                return {
                    X = { Scale = v.X.Scale, Offset = v.X.Offset },
                    Y = { Scale = v.Y.Scale, Offset = v.Y.Offset },
                }
            end,
            Decode = function(d)
                if typeof(d) == "table" then
                    return UDim2.new(d.X.Scale, d.X.Offset, d.Y.Scale, d.Y.Offset)
                end
                return nil
            end,
        },
    }

    local ElementParser = {}

    local function RegisterParser(typeName, collection, SaveFn, LoadFn, CustomFetcher)
        ElementParser[typeName] = {
            Save = function(idx, el)
                local data = SaveFn(idx, el)
                data.type = typeName
                data.idx = idx
                return data
            end,
            Load = function(idx, data)
                if CustomFetcher then
                    return LoadFn(nil, data)
                end
                local list = SaveManager.Library and SaveManager.Library[collection]
                local el = list and list[idx]
                return LoadFn(el, data)
            end,
        }
    end

    --// Toggle
    RegisterParser("Toggle", "Toggles",
        function(_, el) return { value = el.Value } end,
        function(el, data)
            if not el then return end
            if el.Value == data.value then return end
            el:SetValue(data.value)
        end)

    --// Slider
    RegisterParser("Slider", "Options",
        function(_, el) return { value = tonumber(el.Value) } end,
        function(el, data)
            if not el then return end
            if tonumber(el.Value) == tonumber(data.value) then return end
            el:SetValue(tonumber(data.value))
        end)

    --// Dropdown
    RegisterParser("Dropdown", "Options",
        function(_, el)
            return { value = el.Value, multi = el.Multi }
        end,
        function(el, data)
            if not el then return end
            el:SetValue(data.value)
        end)

    --// ColorPicker
    RegisterParser("ColorPicker", "Options",
        function(_, el)
            return { value = el.Value:ToHex(), transparency = el.Transparency }
        end,
        function(el, data)
            if not el then return end
            local ok, color = pcall(Color3.fromHex, data.value)
            if not ok then return end
            el:SetValueRGB(color, data.transparency)
        end)

    --// KeyPicker
    RegisterParser("KeyPicker", "Options",
        function(_, el)
            return {
                mode = el.Mode,
                key = el.Value,
                toggled = el.Toggled,
            }
        end,
        function(el, data)
            if not el then return end
            if data.key then el:SetValue(data.key) end
            if data.mode then el.Mode = data.mode end
            if data.toggled ~= nil then
                el.Toggled = data.toggled
                if el.Update then el:Update() end
            end
        end)

    --// Input
    RegisterParser("Input", "Options",
        function(_, el) return { text = el.Value } end,
        function(el, data)
            if not el then return end
            if typeof(data.text) ~= "string" then return end
            el:SetValue(data.text)
        end)

    --// Groupbox
    RegisterParser("Groupbox", "Tabs",
        function(idx, gb, tabIdx)
            return {
                tabIdx = tabIdx,
                collapsed = gb.Collapsed,
                poppedOut = gb.PoppedOut == true,
                popoutPos = (gb.PoppedOut and gb.PopOutFloat)
                    and SpecialValueParser.UDim2.Encode(gb.PopOutFloat.Position)
                    or nil,
            }
        end,
        function(_, data)
            local tabIdx, idx = data.tabIdx, data.idx
            if typeof(tabIdx) ~= "string" or typeof(idx) ~= "string" then return end

            local tabs = SaveManager.Library and SaveManager.Library.Tabs
            local tab = tabs and tabs[tabIdx]
            if not tab then return end

            local gb = tab.Groupboxes and tab.Groupboxes[idx]
            if not gb then return end

            if gb.Collapsed ~= data.collapsed and gb.SetCollapsed then
                gb:SetCollapsed(data.collapsed == true)
            end

            if gb.PopOutEnabled and gb.SetPoppedOut then
                if data.poppedOut == true then
                    local pos = SpecialValueParser.UDim2.Decode(data.popoutPos)
                    gb:SetPoppedOut(true, pos)
                elseif gb.PoppedOut then
                    gb:SetPoppedOut(false)
                end
            end
        end,
        true)

    --// Tabbox
    RegisterParser("Tabbox", "Tabs",
        function(idx, tb, tabIdx)
            return {
                tabIdx = tabIdx,
                poppedOut = tb.PoppedOut == true,
                popoutPos = (tb.PoppedOut and tb.PopOutFloat)
                    and SpecialValueParser.UDim2.Encode(tb.PopOutFloat.Position)
                    or nil,
            }
        end,
        function(_, data)
            local tabIdx, idx = data.tabIdx, data.idx
            if typeof(tabIdx) ~= "string" or typeof(idx) ~= "string" then return end

            local tabs = SaveManager.Library and SaveManager.Library.Tabs
            local tab = tabs and tabs[tabIdx]
            if not tab then return end

            local tb = tab.Tabboxes and tab.Tabboxes[idx]
            if not tb then return end

            if tb.PopOutEnabled and tb.SetPoppedOut then
                if data.poppedOut == true then
                    local pos = SpecialValueParser.UDim2.Decode(data.popoutPos)
                    tb:SetPoppedOut(true, pos)
                elseif tb.PoppedOut then
                    tb:SetPoppedOut(false)
                end
            end
        end,
        true)

    --================================================================
    --  Refresh config list
    --================================================================
    function SaveManager:RefreshConfigList()
        local base = GetCurrentSettingsPath()
        if not base then return {} end

        local files = safeList(base)
        local names = {}

        for _, path in ipairs(files) do
            local raw = path:match("(.+)%..+$")
            if raw then
                local pos = raw:gsub("\\", "/"):find("/[^/]*$")
                local name = pos and raw:sub(pos + 1) or raw
                if name and name ~= "autoload" then
                    table.insert(names, name)
                end
            end
        end

        return names
    end

    --================================================================
    --  SAVE
    --================================================================
    function SaveManager:SaveJSON(configName)
        local lib = SaveManager.Library
        local ignore = SaveManager.Ignore

        local payload = {
            timestamp = os.date("%d.%m.%Y %H:%M:%S"),
            name = configName or "",
            version = 1,
            objects = {},
            keybindMenu = lib.KeybindFrame and {
                visible = lib.KeybindFrame.Visible,
                position = SpecialValueParser.UDim2.Encode(lib.KeybindFrame.Position),
            } or nil,
        }

        for idx, toggle in pairs(lib.Toggles or {}) do
            if toggle.Type and not ignore[idx] then
                local parser = ElementParser[toggle.Type]
                if parser then
                    table.insert(payload.objects, parser.Save(idx, toggle))
                end
            end
        end

        for idx, option in pairs(lib.Options or {}) do
            if option.Type and not ignore[idx] then
                local parser = ElementParser[option.Type]
                if parser then
                    table.insert(payload.objects, parser.Save(idx, option))
                end
            end
        end

        for tabIdx, tab in pairs(lib.Tabs or {}) do
            if tab.Groupboxes then
                for idx, gb in pairs(tab.Groupboxes) do
                    if typeof(idx) == "string" and not ignore[idx] then
                        local parser = ElementParser.Groupbox
                        if parser then
                            table.insert(payload.objects, parser.Save(idx, gb, tabIdx))
                        end
                    end
                end
            end
            if tab.Tabboxes then
                for idx, tb in pairs(tab.Tabboxes) do
                    if typeof(idx) == "string" and not ignore[idx] then
                        local parser = ElementParser.Tabbox
                        if parser then
                            table.insert(payload.objects, parser.Save(idx, tb, tabIdx))
                        end
                    end
                end
            end
        end

        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
        if not ok then return nil, "Falha ao codificar JSON" end
        return encoded, nil
    end

    function SaveManager:Save(configName)
        if IsEmpty(configName) then return false, "Nome de config inválido" end
        if string.lower(configName) == "autoload" then
            return false, "Nome 'autoload' é reservado"
        end

        local path = GetConfigPath(configName)
        if not path then return false, "Caminho inválido" end

        SaveManager:CheckFolderTree()

        local encoded, err = SaveManager:SaveJSON(configName)
        if not encoded then return false, err end

        local ok, werr = writeFile(path, encoded)
        if not ok then return false, "Falha ao escrever: " .. tostring(werr) end

        Log("config salva: %s", configName)
        return true
    end

    --================================================================
    --  LOAD
    --================================================================
    function SaveManager:LoadJSON(content)
        if IsEmpty(content) then return false, "JSON vazio" end

        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        if not ok or typeof(decoded) ~= "table" or typeof(decoded.objects) ~= "table" then
            return false, "JSON inválido"
        end

        local lib = SaveManager.Library
        local ignore = SaveManager.Ignore

        -- Keybind menu
        if lib.KeybindFrame and typeof(decoded.keybindMenu) == "table" then
            local km = decoded.keybindMenu
            lib.KeybindFrame.Visible = km.visible == true
            local pos = SpecialValueParser.UDim2.Decode(km.position)
            if pos then lib.KeybindFrame.Position = pos end
        end

        -- Ordenar antes de aplicar se UseLoadingOrder
        if SaveManager.UseLoadingOrder and typeof(SaveManager.LoadingOrder) == "table" then
            table.sort(decoded.objects, function(a, b)
                local ai = table.find(SaveManager.LoadingOrder, a.type) or math.huge
                local bi = table.find(SaveManager.LoadingOrder, b.type) or math.huge
                return ai < bi
            end)
        end

        for _, obj in ipairs(decoded.objects) do
            if obj.type and not ignore[obj.idx] then
                local parser = ElementParser[obj.type]
                if parser then
                    task.defer(parser.Load, obj.idx, obj)
                end
            end
        end

        return true
    end

    function SaveManager:Load(configName)
        if IsEmpty(configName) then return false, "Nenhum config selecionado" end

        local path = GetConfigPath(configName)
        if not path or not safeFile(path) then
            return false, "Arquivo de config não existe"
        end

        local content, err = readFile(path)
        if not content then return false, "Falha ao ler: " .. tostring(err) end

        return SaveManager:LoadJSON(content)
    end

    --================================================================
    --  DELETE
    --================================================================
    function SaveManager:Delete(configName)
        if IsEmpty(configName) then return false, "Nenhum config selecionado" end

        local path = GetConfigPath(configName)
        if not path or not safeFile(path) then
            return false, "Arquivo não existe"
        end

        delFile(path)

        if configName == SaveManager.AutoloadConfig then
            SaveManager:DeleteAutoLoadConfig()
        end

        return true
    end

    --================================================================
    --  AUTOLOAD
    --================================================================
    function SaveManager:GetAutoloadConfig()
        SaveManager:CheckFolderTree()

        local path = GetAutoloadPath()
        if not path then return "none", false, "Caminho inválido" end
        if not safeFile(path) then return "none", false, "Nenhum autoload configurado" end

        local content = readFile(path)
        if typeof(content) ~= "string" then return "none", false, "Falha ao ler" end

        content = Trim(content)
        if not DoesConfigExist(content) then
            return "none", false, "Config não encontrado"
        end

        SaveManager.AutoloadConfig = content
        return content, true
    end

    function SaveManager:SaveAutoloadConfig(configName)
        if IsEmpty(configName) then return false, "Nenhum config selecionado" end
        if not DoesConfigExist(configName) then
            return false, "Config não existe"
        end

        SaveManager:CheckFolderTree()
        local path = GetAutoloadPath()
        if not path then return false, "Caminho inválido" end

        local ok, err = writeFile(path, configName)
        if not ok then return false, tostring(err) end

        SaveManager.AutoloadConfig = configName
        return true
    end

    function SaveManager:LoadAutoloadConfig()
        local name, ok, err = SaveManager:GetAutoloadConfig()
        if not ok then
            if err ~= "Nenhum autoload configurado" then
                Log("autoload falhou: %s", tostring(err))
            end
            return
        end

        local loaded, loadErr = SaveManager:Load(name)
        if not loaded then
            Log("autoload load falhou: %s", tostring(loadErr))
            return
        end

        Log("autoload ok: %s", name)
    end

    function SaveManager:DeleteAutoLoadConfig()
        SaveManager:CheckFolderTree()
        local path = GetAutoloadPath()
        if not path or not safeFile(path) then return false end
        delFile(path)
        SaveManager.AutoloadConfig = nil
        return true
    end

    --================================================================
    --  GUI INTEGRATION
    --================================================================
    local function ShowConfirm(Condition, Idx, Title, Description, DestructiveText, DestructiveAction)
        if not Condition() then
            return DestructiveAction()
        end

        return SaveManager.Library.Window:AddDialog(Idx, {
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

    function SaveManager:BuildConfigSection(Tab, IconName)
        assert(SaveManager.Library, "SaveManager:SetLibrary deve ser chamado antes")

        local Box = Tab:AddGroupbox({
            Side = "Right",
            Name = "Configurações",
            IconName = IconName or nil,
        })

        local ConfigNameInput, ConfigList, JSONInput, AutoloadLabel

        local function RefreshList()
            ConfigList:SetValues(SaveManager:RefreshConfigList())
            ConfigList:SetValue(nil)
        end

        local function RefreshAutoloadLabel()
            local name = SaveManager:GetAutoloadConfig()
            AutoloadLabel:SetText("Autoload atual: " .. name)
        end

        -- Criação
        ConfigNameInput = Box:AddInput("SM_ConfigName", { Text = "Nome do config" })

        Box:AddButton({
            Text = "Criar config",
            Func = function()
                local name = ConfigNameInput.Value
                if IsEmpty(name) then
                    Library:NotifyError("Nome vazio", "Digite um nome válido.")
                    return
                end
                if string.lower(name) == "autoload" then
                    Library:NotifyError("Nome reservado", "'autoload' é reservado.")
                    return
                end

                ShowConfirm(
                    function() return DoesConfigExist(name) end,
                    "SM_Create",
                    "Config já existe",
                    string.format("Já existe um config '%s'. Sobrescrever?", name),
                    "Sobrescrever",
                    function()
                        local ok, err = SaveManager:Save(name)
                        if not ok then
                            Library:NotifyError("Falha ao salvar", tostring(err))
                            return
                        end
                        Library:NotifySuccess("Config salvo", name)
                        RefreshList()
                    end
                )
            end,
        })

        Box:AddDivider()

        -- Lista
        ConfigList = Box:AddDropdown("SM_ConfigList", {
            Text = "Configs salvos",
            Values = SaveManager:RefreshConfigList(),
            Multi = false,
            AllowNull = true,
        })

        Box:AddButton({
            Text = "Carregar",
            Func = function()
                local name = ConfigList.Value
                if not name then
                    Library:NotifyError("Nenhum config", "Selecione um primeiro.")
                    return
                end
                ShowConfirm(
                    function() return true end,
                    "SM_Load",
                    "Carregar config",
                    string.format("Carregar '%s'? O estado atual será sobrescrito.", name),
                    "Carregar",
                    function()
                        local ok, err = SaveManager:Load(name)
                        if not ok then
                            Library:NotifyError("Falha", tostring(err))
                            return
                        end
                        Library:NotifySuccess("Config carregado", name)
                    end
                )
            end,
        })

        Box:AddButton({
            Text = "Sobrescrever",
            Func = function()
                local name = ConfigList.Value
                if not name then
                    Library:NotifyError("Nenhum config", "Selecione um primeiro.")
                    return
                end
                local ok, err = SaveManager:Save(name)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Sobrescrito", name)
            end,
        })

        Box:AddButton({
            Text = "Deletar",
            DoubleClick = true,
            Func = function()
                local name = ConfigList.Value
                if not name then
                    Library:NotifyError("Nenhum config", "Selecione um primeiro.")
                    return
                end
                local ok, err = SaveManager:Delete(name)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Deletado", name)
                RefreshAutoloadLabel()
                RefreshList()
            end,
        })

        Box:AddButton("Atualizar lista", RefreshList)

        Box:AddDivider()

        -- Autoload
        Box:AddButton({
            Text = "Definir como autoload",
            Func = function()
                local name = ConfigList.Value
                if not name then
                    Library:NotifyError("Nenhum config", "Selecione um primeiro.")
                    return
                end
                local ok, err = SaveManager:SaveAutoloadConfig(name)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Autoload definido", name)
                RefreshAutoloadLabel()
            end,
        })

        Box:AddButton({
            Text = "Resetar autoload",
            Func = function()
                SaveManager:DeleteAutoLoadConfig()
                Library:NotifySuccess("Autoload resetado", "")
                RefreshAutoloadLabel()
            end,
        })

        AutoloadLabel = Box:AddLabel("Autoload atual: ...", true)

        Box:AddDivider()

        -- Import / Export
        JSONInput = Box:AddInput("SM_JSON", { Text = "Config JSON" })

        Box:AddButton({
            Text = "Importar",
            Func = function()
                local content = JSONInput.Value
                if IsEmpty(content) then
                    Library:NotifyError("Vazio", "Cole um JSON primeiro.")
                    return
                end
                local ok, err = SaveManager:LoadJSON(content)
                if not ok then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                Library:NotifySuccess("Importado", "")
            end,
        })

        Box:AddButton({
            Text = "Exportar",
            Func = function()
                local encoded, err = SaveManager:SaveJSON()
                if not encoded then
                    Library:NotifyError("Falha", tostring(err))
                    return
                end
                JSONInput:SetValue(encoded)
                if setclipboard then
                    setclipboard(encoded)
                    Library:NotifySuccess("Copiado", "Config exportado pro clipboard.")
                end
            end,
        })

        -- ignora config nos saves automáticos
        SaveManager:SetIgnoreIndexes({
            "SM_ConfigName", "SM_ConfigList", "SM_JSON",
        })

        RefreshAutoloadLabel()

        return Box
    end

    --================================================================
    --  AUTO-BUILD
    --================================================================
    SaveManager:BuildFolderTree()

    --================================================================
    --  ATTACH
    --================================================================
    function Library:AttachSaveManager(SM)
        Library.SaveManager = SM
        SM:SetLibrary(Library)
    end

    Library.SaveManager = SaveManager
    SaveManager:SetLibrary(Library)

    return Library
end