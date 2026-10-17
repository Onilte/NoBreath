--[[
    NoctraLib :: library.lua
    ----------------------------------------------------------------
    Coração da NoctraLib.
    Contém:
      • Tabela global Library (Scheme, Registry, Signals, Scales)
      • Módulo Sounds (todos os assets de áudio)
      • Registry / Scheme (sistema de cores dinâmicas)
      • Signals (gerenciamento de conexões)
      • Helpers (Trim, Round, SafeCallback, Validate, GetTextBounds,
        MouseIsOverFrame, IsInsideFrame, New, FillInstance, AddOutline)
      • Notify (stub — sobrescrito por extras.lua)
      • Unload (limpeza total)

    Este arquivo NÃO cria janela. NÃO cria elementos.
    Ele só prepara o terreno e devolve a tabela Library.
    Os outros módulos (window, elements, extras) se penduram nele.
]]

local cloneref = (cloneref or clonereference or function(instance) return instance end)

local CoreGui        = cloneref(game:GetService("CoreGui"))
local GuiService     = cloneref(game:GetService("GuiService"))
local Players        = cloneref(game:GetService("Players"))
local RunService     = cloneref(game:GetService("RunService"))
local SoundService   = cloneref(game:GetService("SoundService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TextService    = cloneref(game:GetService("TextService"))
local TweenService   = cloneref(game:GetService("TweenService"))

local LocalPlayer    = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Mouse          = cloneref(LocalPlayer:GetMouse())

local gethui         = gethui or function() return CoreGui end
local protectgui     = protectgui or (syn and syn.protect_gui) or function() end

--// Criação de ScreenGui escondida (será usada depois pelos módulos)
local function ParentUI(UI)
    pcall(protectgui, UI)
    local ok = pcall(function()
        UI.Parent = gethui()
    end)
    if not ok or not UI.Parent then
        UI.Parent = LocalPlayer:WaitForChild("PlayerGui", math.huge)
    end
end

--================================================================
--  TABELA LIBRARY
--================================================================
local Library = {
    LocalPlayer = LocalPlayer,
    IsRobloxFocused = true,

    ScreenGui = nil,       -- criado em window.lua
    Floats    = nil,       -- criado em window.lua
    Overlay   = nil,       -- criado em window.lua

    Window    = nil,
    WindowContainer = nil,

    --// Tabs e elementos
    Tabs       = {},
    TabButtons = {},
    Toggles    = {},
    Buttons    = {},
    Labels     = {},
    Options    = {},
    Tooltips   = {},

    --// Dep. boxes
    DependencyBoxes = {},

    --// Notificações
    Notifications = {},
    NotifySide = "Right",
    NotifyTweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

    --// Dialogs
    Dialogues = {},
    ActiveDialog = nil,

    --// Context menus
    ContextMenus = {},

    --// Cantos
    Corners = {},
    SpecificCorners = {},

    --// Animações
    TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    WindowAnimationInfo = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    DropdownTransitionInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    KeyPickerTransitionInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

    Animations = {
        ToggleWindow = true,
        TabSwitch    = true,
        Groupbox     = true,
        Dropdown     = true,
        KeyPicker    = true,
    },

    --// Estado
    Toggled    = false,
    Unloaded   = false,
    Searching  = false,
    SearchText = "",
    GlobalSearch = false,

    --// Configurações visuais globais — vindas do briefing da NoctraLib
    StrokeThickness = 1.5,         -- todas as bordas
    Font = Font.new("rbxasset://fonts/families/Roboto.json"),
    FontName = "Roboto",

    CornerRadius = 6,
    MinSize = Vector2.new(480, 320),
    DPIScale = 1,
    Scales = {},
    ScalesOffset = {},

    --// Registry (Instance -> {Prop = "SchemeKey"})
    Registry = {},

    --// Signals registrados
    Signals = {},
    UnloadSignals = {},

    --// Scheme — fundo preto, accent laranja (inspirado no painel do tablet)
    IsLightTheme = false,
    Scheme = {
        BackgroundColor = Color3.fromRGB(0, 0, 0),
        MainColor       = Color3.fromRGB(12, 12, 12),
        AccentColor     = Color3.fromRGB(255, 138, 30),
        OutlineColor    = Color3.fromRGB(38, 38, 38),
        FontColor       = Color3.fromRGB(255, 255, 255),

        RedColor         = Color3.fromRGB(255, 60, 60),
        DestructiveColor = Color3.fromRGB(220, 40, 40),
        DarkColor        = Color3.fromRGB(0, 0, 0),
        WhiteColor       = Color3.fromRGB(255, 255, 255),

        BackgroundImage = "",
    },

    --// Mouse original (pra restaurar ao unload)
    OriginalMouseIconEnabled = UserInputService.MouseIconEnabled,

    --// Placeholders que window.lua e extras.lua vão sobrescrever
    Notify = nil,
    Toggle = nil,
}

--================================================================
--  SONS
--================================================================
local Sounds = {
    Click   = "rbxassetid://124476359159008",
    Success = "rbxassetid://116841974988859",
    Error   = "rbxassetid://97972687450528",
    Typing  = "rbxassetid://9113879534",
    Action  = "rbxassetid://9083627113",

    Volume  = 0.5,
    _typing = nil,
}

function Sounds:Play(id, volumeMultiplier)
    if not id or id == "" then return end

    local sound = Instance.new("Sound")
    sound.SoundId = id
    sound.Volume  = (volumeMultiplier or 1) * Sounds.Volume
    sound.Parent  = SoundService
    sound:Play()

    sound.Ended:Connect(function()
        if sound then sound:Destroy() end
    end)
    task.delay(8, function()
        if sound and sound.Parent then sound:Destroy() end
    end)

    return sound
end

function Sounds:PlayClick()   Sounds:Play(Sounds.Click)   end
function Sounds:PlaySuccess() Sounds:Play(Sounds.Success) end
function Sounds:PlayError()   Sounds:Play(Sounds.Error)   end
function Sounds:PlayAction()  Sounds:Play(Sounds.Action)  end

function Sounds:BeginTyping()
    if Sounds._typing then return end

    local sound = Instance.new("Sound")
    sound.SoundId = Sounds.Typing
    sound.Looped  = true
    sound.Volume  = Sounds.Volume * 0.7
    sound.Parent  = SoundService
    sound:Play()

    Sounds._typing = sound
end

function Sounds:StopTyping()
    if not Sounds._typing then return end

    pcall(function()
        Sounds._typing:Stop()
        Sounds._typing:Destroy()
    end)
    Sounds._typing = nil
end

Library.Sounds = Sounds

--================================================================
--  HELPERS BÁSICOS
--================================================================
function Library:Trim(Text)
    return Text:match("^%s*(.-)%s*$")
end

function Library:Round(Value, Rounding)
    assert(Rounding >= 0, "Invalid rounding number.")
    if Rounding == 0 then
        return math.floor(Value)
    end
    return tonumber(string.format("%." .. Rounding .. "f", Value))
end

function Library:GetTableSize(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Library:SafeCallback(Func, ...)
    if not Func or typeof(Func) ~= "function" then return end

    local Result = table.pack(xpcall(Func, function(Error)
        task.defer(error, debug.traceback(Error, 2))
        return Error
    end, ...))

    if not Result[1] then return nil end
    return table.unpack(Result, 2, Result.n)
end

function Library:GiveSignal(Connection)
    local T = typeof(Connection)
    if Connection and (T == "RBXScriptConnection" or T == "RBXScriptSignal") then
        table.insert(Library.Signals, Connection)
    end
    return Connection
end

function Library:OnUnload(Callback)
    table.insert(Library.UnloadSignals, Callback)
end

--// Validação de tabela contra template (merge de defaults)
function Library:Validate(Table, Template)
    if typeof(Table) ~= "table" then
        return Template
    end

    for k, v in pairs(Template) do
        if typeof(k) == "number" then
            continue
        end

        if typeof(v) == "table" then
            Table[k] = Library:Validate(Table[k], v)
        elseif Table[k] == nil then
            Table[k] = v
        end
    end

    return Table
end

--// Texto
function Library:GetTextBounds(Text, Font, Size, Width)
    local Params = Instance.new("GetTextBoundsParams")
    Params.Text     = Text
    Params.RichText = true
    Params.Font     = Font
    Params.Size     = Size
    Params.Width    = Width or (workspace.CurrentCamera.ViewportSize.X - 32)

    local Bounds = TextService:GetTextBoundsAsync(Params)
    return Bounds.X, Bounds.Y
end

--// Colisão de mouse
function Library:MouseIsOverFrame(Frame, MousePos)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize
    return MousePos.X >= AbsPos.X
        and MousePos.X <= AbsPos.X + AbsSize.X
        and MousePos.Y >= AbsPos.Y
        and MousePos.Y <= AbsPos.Y + AbsSize.Y
end

function Library:IsInsideFrame(ParentFrame, Frame)
    local GuiPos,  GuiSize  = Frame.AbsolutePosition, Frame.AbsoluteSize
    local ParFramePos, ParFrameSize = ParentFrame.AbsolutePosition, ParentFrame.AbsoluteSize

    return GuiPos.X >= ParFramePos.X
        and GuiPos.X + GuiSize.X <= ParFramePos.X + ParFrameSize.X
        and GuiPos.Y >= ParFramePos.Y
        and GuiPos.Y + GuiSize.Y <= ParFramePos.Y + ParFrameSize.Y
end

--================================================================
--  SCHEME / REGISTRY
--================================================================
local SchemeReplaceAlias = {
    RedColor   = "Red",
    WhiteColor = "White",
    DarkColor  = "Dark",
}
local SchemeAlias = {
    Red   = "RedColor",
    White = "WhiteColor",
    Dark  = "DarkColor",
}

local function GetSchemeValue(Index)
    if not Index then return nil end

    local Replace = SchemeReplaceAlias[Index]
    if Replace and Library.Scheme[Replace] ~= nil then
        Library.Scheme[Index]   = Library.Scheme[Replace]
        Library.Scheme[Replace] = nil
        return Library.Scheme[Index]
    end

    local Alias = SchemeAlias[Index]
    if Alias and Library.Scheme[Alias] ~= nil then
        return Library.Scheme[Alias]
    end

    return Library.Scheme[Index]
end

function Library:AddToRegistry(Instance, Properties)
    Library.Registry[Instance] = Properties
end

function Library:RemoveFromRegistry(Instance)
    Library.Registry[Instance] = nil
end

function Library:UpdateColorsUsingRegistry()
    for Instance, Properties in pairs(Library.Registry) do
        for Property, Index in pairs(Properties) do
            local SchemeValue = GetSchemeValue(Index)
            if SchemeValue or typeof(Index) == "function" then
                Instance[Property] = SchemeValue or Index()
            end
        end
    end
end

--// Cor "melhorada" pra hovers e afins
function Library:GetBetterColor(Color, Add)
    Add = (Add or 0) * (Library.IsLightTheme and -4 or 2)
    return Color3.fromRGB(
        math.clamp(Color.R * 255 + Add, 0, 255),
        math.clamp(Color.G * 255 + Add, 0, 255),
        math.clamp(Color.B * 255 + Add, 0, 255)
    )
end

function Library:GetLighterColor(Color)
    local H, S, V = Color:ToHSV()
    return Color3.fromHSV(H, math.max(0, S - 0.1), math.min(1, V + 0.1))
end

function Library:GetDarkerColor(Color)
    local H, S, V = Color:ToHSV()
    return Color3.fromHSV(H, S, V / 2)
end

--================================================================
--  CRIAÇÃO DE INSTÂNCIAS (New / FillInstance)
--================================================================
local Templates = {
    Frame = { BorderSizePixel = 0 },
    ImageLabel = { BackgroundTransparency = 1, BorderSizePixel = 0 },
    ImageButton = { AutoButtonColor = false, BorderSizePixel = 0 },
    ScrollingFrame = { BorderSizePixel = 0, ScrollBarThickness = 0 },
    TextLabel = {
        BorderSizePixel = 0,
        FontFace = function() return Library.Font end,
        RichText = true,
        TextColor3 = "FontColor",
        BackgroundTransparency = 1,
    },
    TextButton = {
        AutoButtonColor = false,
        BorderSizePixel = 0,
        FontFace = function() return Library.Font end,
        RichText = true,
        TextColor3 = "FontColor",
    },
    TextBox = {
        BorderSizePixel = 0,
        FontFace = function() return Library.Font end,
        PlaceholderColor3 = function()
            local H, S, V = Library.Scheme.FontColor:ToHSV()
            return Color3.fromHSV(H, S, V / 2)
        end,
        Text = "",
        TextColor3 = "FontColor",
        BackgroundTransparency = 1,
    },
    UIListLayout = { SortOrder = Enum.SortOrder.LayoutOrder },
    UIGridLayout = { SortOrder = Enum.SortOrder.LayoutOrder },
    UIStroke = { ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
}

local function FillInstance(Table, Instance)
    local ThemeProperties = Library.Registry[Instance] or {}

    for key, value in pairs(Table) do
        if key ~= "Text" and key ~= "Parent" then
            local SchemeValue = GetSchemeValue(value)

            if SchemeValue or typeof(value) == "function" then
                ThemeProperties[key] = value
                value = SchemeValue or value()
            else
                ThemeProperties[key] = nil
            end
        end
        Instance[key] = value
    end

    if Library:GetTableSize(ThemeProperties) > 0 then
        Library.Registry[Instance] = ThemeProperties
    end
end

function Library:New(ClassName, Properties)
    local Instance = Instance.new(ClassName)
    Properties = Properties or {}

    if Templates[ClassName] then
        FillInstance(Templates[ClassName], Instance)
    end
    FillInstance(Properties, Instance)

    if Properties.Parent and not Properties.ZIndex then
        pcall(function()
            Instance.ZIndex = Properties.Parent.ZIndex
        end)
    end

    return Instance
end

--// Adiciona UIStroke duplo (outline + sombra) — 1.5 thickness, padrão NoctraLib
function Library:AddOutline(Frame)
    local Thickness = Library.StrokeThickness or 1.5

    local OutlineStroke = Library:New("UIStroke", {
        Color     = "OutlineColor",
        Thickness = Thickness,
        ZIndex    = 2,
        Parent    = Frame,
    })

    local ShadowStroke = Library:New("UIStroke", {
        Color     = "DarkColor",
        Thickness = Thickness,
        ZIndex    = 1,
        Parent    = Frame,
    })

    return OutlineStroke, ShadowStroke
end

--// Linha horizontal
function Library:MakeLine(Frame, Info)
    return Library:New("Frame", {
        AnchorPoint  = Info.AnchorPoint or Vector2.zero,
        BackgroundColor3 = "OutlineColor",
        BorderSizePixel = 0,
        LayoutOrder  = Info.LayoutOrder or 0,
        Position     = Info.Position,
        Size         = Info.Size,
        ZIndex       = Info.ZIndex or Frame.ZIndex,
        Parent       = Frame,
    })
end

--================================================================
--  STUB DE NOTIFY (extras.lua substitui)
--================================================================
function Library:Notify(...)
    warn("[NoctraLib] Notify chamado antes de extras.lua carregar:", ...)
end

--================================================================
--  STUB DE TOGGLE (window.lua substitui)
--================================================================
function Library:Toggle(...)
    warn("[NoctraLib] Toggle chamado antes de window.lua carregar:", ...)
end

--================================================================
--  UNLOAD
--================================================================
function Library:Unload()
    Library.Unloaded = true

    -- Desconecta signals
    for i = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, i)
        if Connection and Connection.Connected then
            Connection:Disconnect()
        end
    end

    -- Callbacks de unload
    for _ = 1, #Library.UnloadSignals do
        local Callback = table.remove(Library.UnloadSignals, 1)
        if Callback then
            Library:SafeCallback(Callback)
        end
    end

    -- Destrói tabs
    for i = #Library.Tabs, 1, -1 do
        local Tab = table.remove(Library.Tabs, i)
        if Tab and Tab.Destroy then
            Library:SafeCallback(Tab.Destroy, Tab)
        end
    end

    -- Restaura mouse
    pcall(function()
        UserInputService.MouseIconEnabled = Library.OriginalMouseIconEnabled
    end)

    -- Destrói ScreenGui
    if Library.ScreenGui then
        Library.ScreenGui:Destroy()
    end

    -- Limpa tabelas
    table.clear(Library.Registry)
    table.clear(Library.Toggles)
    table.clear(Library.Buttons)
    table.clear(Library.Labels)
    table.clear(Library.Options)
    table.clear(Library.Tooltips)
    table.clear(Library.Tabs)
    table.clear(Library.TabButtons)
    table.clear(Library.Corners)
    table.clear(Library.SpecificCorners)
    table.clear(Library.ContextMenus)
    table.clear(Library.Notifications)
    table.clear(Library.Dialogues)
    table.clear(Library.DependencyBoxes)
    table.clear(Library.Signals)
    table.clear(Library.UnloadSignals)

    Library.Toggle = function() end
    Library.Notify = function() end
    Library.ScreenGui = nil
    Library.Floats = nil
    Library.Overlay = nil
    Library.Window = nil
    Library.WindowContainer = nil

    getgenv().NoctraLib = nil
end

--// Registrar o core no getgenv já aqui
getgenv().NoctraLib = Library

--================================================================
--  RETORNO
--================================================================
return {
    Library = Library,
    Sounds  = Sounds,
    ParentUI = ParentUI,
    GetSchemeValue = GetSchemeValue,
}