--[[
    NoctraLib :: window.lua
    ----------------------------------------------------------------
    Monta a janela principal, tabs, groupboxes, tabboxes.
    Contém:
      • CreateWindow
      • Botões de janela (fechar, minimizar, maximizar, fullscreen)
      • Resize por borda (8 handles — 4 lados + 4 cantos)
      • Drag da janela pela topbar
      • AddTab / AddGroupbox / AddTabbox / AddDependencyBox
      • Pop-out de groupbox/tabbox
      • Search global de elementos

    Retorna uma função Attach(Library) que pendura tudo e devolve Library.
]]

return function(Library)

    local cloneref = (cloneref or clonereference or function(x) return x end)
    local CoreGui        = cloneref(game:GetService("CoreGui"))
    local Players        = cloneref(game:GetService("Players"))
    local RunService     = cloneref(game:GetService("RunService"))
    local UserInputService = cloneref(game:GetService("UserInputService"))
    local TweenService   = cloneref(game:GetService("TweenService"))
    local GuiService     = cloneref(game:GetService("GuiService"))
    local LocalPlayer    = Library.LocalPlayer

    local Sounds = Library.Sounds
    local New    = function(...) return Library:New(...) end
    local function GiveSignal(c) return Library:GiveSignal(c) end

    --// Placeholders que elements.lua vai preencher
    Library.Tabs       = Library.Tabs or {}
    Library.TabButtons = Library.TabButtons or {}

    --================================================================
    --  DETECÇÃO DE INPUT
    --================================================================
    local function IsMouseInput(Input, IncludeM2)
        return Input.UserInputType == Enum.UserInputType.MouseButton1
            or (IncludeM2 == true and Input.UserInputType == Enum.UserInputType.MouseButton2)
            or Input.UserInputType == Enum.UserInputType.Touch
    end

    local function IsClickInput(Input, IncludeM2)
        return IsMouseInput(Input, IncludeM2)
            and Input.UserInputState == Enum.UserInputState.Begin
            and Library.IsRobloxFocused
    end

    local function IsHoverInput(Input)
        return (Input.UserInputType == Enum.UserInputType.MouseMovement
             or Input.UserInputType == Enum.UserInputType.Touch)
            and Input.UserInputState == Enum.UserInputState.Change
    end

    --================================================================
    --  SCREEN GUI / FLOATS / OVERLAY
    --================================================================
    local ScreenGui = New("ScreenGui", {
        Name = "NoctraLib",
        DisplayOrder = 998,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    pcall(protectgui, ScreenGui)
    local okParent = pcall(function()
        ScreenGui.Parent = gethui and gethui() or CoreGui
    end)
    if not okParent or not ScreenGui.Parent then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui", math.huge)
    end

    Library.ScreenGui = ScreenGui

    ScreenGui.DescendantRemoving:Connect(function(Instance)
        task.defer(function()
            if Instance.Parent and Instance:IsDescendantOf(ScreenGui) then return end
            Library:RemoveFromRegistry(Instance)
        end)
    end)

    local Floats = New("Frame", {
        Name = "Floats",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 10,
        Active = false,
        Parent = ScreenGui,
    })
    local Overlay = New("Frame", {
        Name = "Overlay",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 20,
        Active = false,
        Parent = ScreenGui,
    })

    Library.Floats  = Floats
    Library.Overlay = Overlay

    --================================================================
    --  CURSOR CUSTOMIZADO (opcional, desligado por padrão)
    --================================================================
    local Cursor = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(9, 1),
        Visible = false,
        ZIndex = 11000,
        Parent = ScreenGui,
    })
    New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = "DarkColor",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 2, 1, 2),
        ZIndex = 1,
        Parent = Cursor,
    })
    New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = "WhiteColor",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
        Parent = Cursor,
    })
    New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = "DarkColor",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(3, 11),
        ZIndex = 1,
        Parent = Cursor,
    })
    New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = "WhiteColor",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(1, 9),
        ZIndex = 2,
        Parent = Cursor,
    })

    local function RestoreMouseIcon()
        pcall(function()
            RunService:UnbindFromRenderStep("NoctraLib_Cursor")
        end)
        UserInputService.MouseIconEnabled = Library.OriginalMouseIconEnabled
        Cursor.Visible = false
    end

    --================================================================
    --  NOTIFICATION AREA
    --================================================================
    local NotificationArea = New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.new(0, 320, 1, -8),
        ZIndex = 200,
        Parent = ScreenGui,
    })
    table.insert(Library.Scales, New("UIScale", { Parent = NotificationArea }))

    --================================================================
    --  DRAGGABLE / SNAPPING HELPERS (usados por popout)
    --================================================================
    Library.DraggableElements = Library.DraggableElements or {}

    function Library:MakeDraggable(UI, DragFrame, IgnoreToggled, IsMainWindow, SnapConfig)
        local StartPos, FramePos
        local Dragging = false
        local Changed, InputBegan, InputChanged

        local SnapGuideX, SnapGuideY

        local function GetSnapGuides()
            if not SnapGuideX then
                SnapGuideX = New("Frame", {
                    BackgroundColor3 = "AccentColor",
                    BackgroundTransparency = 0.3,
                    BorderSizePixel = 0,
                    AnchorPoint = Vector2.new(0.5, 0),
                    Size = UDim2.new(0, 2, 1, 0),
                    Visible = false,
                    ZIndex = 10000,
                    Parent = ScreenGui,
                })
            end
            if not SnapGuideY then
                SnapGuideY = New("Frame", {
                    BackgroundColor3 = "AccentColor",
                    BackgroundTransparency = 0.3,
                    BorderSizePixel = 0,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(1, 0, 0, 2),
                    Visible = false,
                    ZIndex = 10000,
                    Parent = ScreenGui,
                })
            end
            return SnapGuideX, SnapGuideY
        end

        local function HideSnapGuides()
            if SnapGuideX then SnapGuideX.Visible = false end
            if SnapGuideY then SnapGuideY.Visible = false end
        end

        InputBegan = DragFrame.InputBegan:Connect(function(Input)
            if not IsClickInput(Input) then return end
            if IsMainWindow and Library.CantDragForced then return end

            StartPos = Input.Position
            FramePos = UI.Position
            Dragging = true

            Changed = Input.Changed:Connect(function()
                if Input.UserInputState ~= Enum.UserInputState.End then return end
                Dragging = false
                HideSnapGuides()
                if Changed and Changed.Connected then
                    Changed:Disconnect()
                    Changed = nil
                end
            end)
        end)

        InputChanged = UserInputService.InputChanged:Connect(function(Input)
            if (not IgnoreToggled and not Library.Toggled)
                or (IsMainWindow and Library.CantDragForced)
                or not (ScreenGui and ScreenGui.Parent)
            then
                Dragging = false
                HideSnapGuides()
                if Changed and Changed.Connected then
                    Changed:Disconnect()
                    Changed = nil
                end
                return
            end

            if Dragging and IsHoverInput(Input) then
                local Delta = Input.Position - StartPos
                local NewX = FramePos.X.Offset + Delta.X
                local NewY = FramePos.Y.Offset + Delta.Y

                -- Snapping opcional
                if SnapConfig and SnapConfig.Enabled then
                    local Viewport = workspace.CurrentCamera.ViewportSize
                    local Distance = SnapConfig.Distance or 24
                    local Margin   = SnapConfig.Margin   or 8

                    local ElemSize = UI.AbsoluteSize
                    local AbsX = FramePos.X.Scale * Viewport.X + NewX
                    local AbsY = FramePos.Y.Scale * Viewport.Y + NewY

                    local TargetsX = {
                        Left  = Margin,
                        CenterX = (Viewport.X - ElemSize.X) / 2,
                        Right = Viewport.X - ElemSize.X - Margin,
                    }
                    local TargetsY = {
                        Top   = Margin,
                        CenterY = (Viewport.Y - ElemSize.Y) / 2,
                        Bottom = Viewport.Y - ElemSize.Y - Margin,
                    }

                    local GX, GY = GetSnapGuides()
                    GX.Visible = false
                    GY.Visible = false

                    for _, Target in pairs(TargetsX) do
                        if math.abs(AbsX - Target) <= Distance then
                            NewX = Target - FramePos.X.Scale * Viewport.X
                            GX.Position = UDim2.fromOffset(Target, 0)
                            GX.Visible = true
                            break
                        end
                    end
                    for _, Target in pairs(TargetsY) do
                        if math.abs(AbsY - Target) <= Distance then
                            NewY = Target - FramePos.Y.Scale * Viewport.Y
                            GY.Position = UDim2.fromOffset(0, Target)
                            GY.Visible = true
                            break
                        end
                    end
                end

                UI.Position = UDim2.new(FramePos.X.Scale, NewX, FramePos.Y.Scale, NewY)
            end
        end)

        GiveSignal(InputChanged)
        GiveSignal(InputBegan)

        UI.Destroying:Once(function()
            if InputChanged and InputChanged.Connected then InputChanged:Disconnect() end
            if InputBegan   and InputBegan.Connected   then InputBegan:Disconnect()   end
            if Changed      and Changed.Connected      then Changed:Disconnect()      end
            if SnapGuideX then SnapGuideX:Destroy() end
            if SnapGuideY then SnapGuideY:Destroy() end
        end)
    end

    --// Resize por borda — 8 handles (top, bottom, left, right, 4 cantos)
    function Library:MakeBorderResizable(UI, MinSize, Callback)
        MinSize = MinSize or Library.MinSize

        local edges = {
            { Name = "T", Cursor = "SizeNS", Anchor = Vector2.new(0.5, 0), Size = UDim2.new(1, 0, 0, 6), Pos = UDim2.new(0, 0, 0, 0),       DirX = 0,  DirY = -1 },
            { Name = "B", Cursor = "SizeNS", Anchor = Vector2.new(0.5, 1), Size = UDim2.new(1, 0, 0, 6), Pos = UDim2.new(0, 0, 1, 0),       DirX = 0,  DirY = 1  },
            { Name = "L", Cursor = "SizeWE", Anchor = Vector2.new(0, 0.5), Size = UDim2.new(0, 6, 1, 0), Pos = UDim2.new(0, 0, 0, 0),       DirX = -1, DirY = 0  },
            { Name = "R", Cursor = "SizeWE", Anchor = Vector2.new(1, 0.5), Size = UDim2.new(0, 6, 1, 0), Pos = UDim2.new(1, 0, 0, 0),       DirX = 1,  DirY = 0  },
            { Name = "TL", Cursor = "SizeNWSE", Anchor = Vector2.new(0, 0), Size = UDim2.fromOffset(8, 8), Pos = UDim2.new(0, 0, 0, 0),     DirX = -1, DirY = -1 },
            { Name = "TR", Cursor = "SizeNESW", Anchor = Vector2.new(1, 0), Size = UDim2.fromOffset(8, 8), Pos = UDim2.new(1, 0, 0, 0),     DirX = 1,  DirY = -1 },
            { Name = "BL", Cursor = "SizeNESW", Anchor = Vector2.new(0, 1), Size = UDim2.fromOffset(8, 8), Pos = UDim2.new(0, 0, 1, 0),     DirX = -1, DirY = 1  },
            { Name = "BR", Cursor = "SizeNWSE", Anchor = Vector2.new(1, 1), Size = UDim2.fromOffset(8, 8), Pos = UDim2.new(1, 0, 1, 0),     DirX = 1,  DirY = 1  },
        }

        local handles = {}

        for _, edge in ipairs(edges) do
            local Handle = New("TextButton", {
                Name = "Resize_" .. edge.Name,
                BackgroundTransparency = 1,
                Text = "",
                AnchorPoint = edge.Anchor,
                Position = edge.Pos,
                Size = edge.Size,
                ZIndex = 999,
                Parent = UI,
            })

            local StartMouse, StartSize, StartPos
            local Dragging = false
            local ChangedConn

            Handle.MouseEnter:Connect(function()
                pcall(function()
                    UserInputService.MouseIcon = Enum.MouseIconType[edge.Cursor] or UserInputService.MouseIcon
                end)
            end)

            Handle.InputBegan:Connect(function(Input)
                if not IsClickInput(Input) then return end

                Library.CantDragForced = true
                Dragging = true
                StartMouse = Vector2.new(Input.Position.X, Input.Position.Y)
                StartSize  = UI.AbsoluteSize
                StartPos   = UI.AbsolutePosition

                ChangedConn = Input.Changed:Connect(function()
                    if Input.UserInputState ~= Enum.UserInputState.End then return end
                    Dragging = false
                    Library.CantDragForced = false
                    if ChangedConn and ChangedConn.Connected then
                        ChangedConn:Disconnect()
                        ChangedConn = nil
                    end
                end)
            end)

            GiveSignal(UserInputService.InputChanged:Connect(function(Input)
                if not Dragging or not IsHoverInput(Input) then return end
                if not Library.Toggled then return end

                local Delta = Vector2.new(Input.Position.X, Input.Position.Y) - StartMouse

                local NewW = StartSize.X
                local NewH = StartSize.Y
                local NewX = StartPos.X
                local NewY = StartPos.Y

                if edge.DirX == 1 then
                    NewW = math.max(MinSize.X, StartSize.X + Delta.X)
                elseif edge.DirX == -1 then
                    local W = math.max(MinSize.X, StartSize.X - Delta.X)
                    NewX = StartPos.X + (StartSize.X - W)
                    NewW = W
                end

                if edge.DirY == 1 then
                    NewH = math.max(MinSize.Y, StartSize.Y + Delta.Y)
                elseif edge.DirY == -1 then
                    local H = math.max(MinSize.Y, StartSize.Y - Delta.Y)
                    NewY = StartPos.Y + (StartSize.Y - H)
                    NewH = H
                end

                UI.Size     = UDim2.fromOffset(NewW, NewH)
                UI.Position = UDim2.fromOffset(NewX, NewY)

                if Callback then Library:SafeCallback(Callback) end
            end))

            table.insert(handles, Handle)
        end

        return handles
    end

    --================================================================
    --  POP-OUT (groupbox / tabbox)
    --================================================================
    local function DimPopOutClone(Root)
        for _, Descendant in Root:QueryDescendants("TextLabel, TextButton, TextBox") do
            Descendant.TextTransparency = math.max(Descendant.TextTransparency, 0.4)
        end
        for _, Descendant in Root:QueryDescendants("ImageLabel, ImageButton") do
            Descendant.ImageTransparency = math.max(Descendant.ImageTransparency, 0.4)
        end
        for _, Descendant in Root:QueryDescendants("GuiButton") do
            Descendant.Active = false
            Descendant.AutoButtonColor = false
        end
    end

    local function GetPopOutBodyMaxHeight(Box, Reserved)
        local Float = Box.PopOutFloat
        if not Float then return math.huge end
        local screenY = ScreenGui.AbsolutePosition.Y + ScreenGui.AbsoluteSize.Y
        local available = math.min(screenY - Float.AbsolutePosition.Y, ScreenGui.AbsoluteSize.Y * 0.9)
        return math.max(0, available / Library.DPIScale - Reserved)
    end

    function Library:MakeBoxPopOut(Box, Options)
        Box.PoppedOut    = false
        Box.PopOutEnabled = Options.Enabled ~= false
        Box.PopOutFloat   = nil

        if not Box.PopOutEnabled then
            function Box:SetPoppedOut() end
            function Box:TogglePoppedOut() end
            function Box:RefreshPopOutPlaceholder() end
            return
        end

        local BoxHolder = Box.BoxHolder
        local Holder    = Box.Holder
        local Header    = Options.Header

        local Placeholder, PlaceholderHeader
        local Float, FloatScale
        local HandledChildren, OriginalParents, OriginalLayoutOrders = {}, {}, {}

        local function RaiseFloat()
            if not Float or not Floats then return end
            local MaxZ = Float.ZIndex
            for _, Child in Floats:GetChildren() do
                if Child:IsA("GuiObject") and Child ~= Float then
                    MaxZ = math.max(MaxZ, Child.ZIndex)
                end
            end
            Float.ZIndex = MaxZ + 1
            if Float.Parent == Floats then
                Float.Parent = Overlay
            end
            Float.Parent = Floats
        end

        local function CreatePlaceholder()
            local Frame = New("Frame", {
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = "BackgroundColor",
                BackgroundTransparency = 0.15,
                ClipsDescendants = true,
                Size = UDim2.new(1, 0, 0, 0),
                Parent = BoxHolder,
            })
            table.insert(Library.Corners, New("UICorner", {
                CornerRadius = UDim.new(0, Library.CornerRadius),
                Parent = Frame,
            }))
            Library:AddOutline(Frame)

            PlaceholderHeader = Header:Clone()
            PlaceholderHeader.Parent = Frame
            DimPopOutClone(PlaceholderHeader)

            local DockBtn = New("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(22, 22),
                Text = "x",
                TextColor3 = "FontColor",
                TextSize = 16,
                ZIndex = PlaceholderHeader.ZIndex + 1,
                Parent = Frame,
            })
            DockBtn.MouseButton1Click:Connect(function()
                Sounds:PlayClick()
                Box:SetPoppedOut(false)
            end)

            return Frame
        end

        function Box:RefreshPopOutPlaceholder()
            if not Box.PoppedOut or not Placeholder or not Header then return end
            if PlaceholderHeader then
                PlaceholderHeader:Destroy()
                PlaceholderHeader = nil
            end
            PlaceholderHeader = Header:Clone()
            PlaceholderHeader.Parent = Placeholder
            DimPopOutClone(PlaceholderHeader)
        end

        function Box:SetPoppedOut(Value, FloatPosition)
            if not Box.PopOutEnabled or Box.Destroyed then return end

            Value = Value == true
            if Box.PoppedOut == Value then
                if Value and FloatPosition and Float then
                    Float.Position = FloatPosition
                end
                return
            end

            if Value then
                if Options.Before then Options.Before() end

                local BoxChildren = Options.Children and Options.Children() or { Holder }
                HandledChildren = {}
                table.clear(OriginalParents)
                table.clear(OriginalLayoutOrders)

                for _, Child in ipairs(BoxChildren) do
                    if Child and Child.Parent then
                        table.insert(HandledChildren, Child)
                        OriginalParents[Child]      = Child.Parent
                        OriginalLayoutOrders[Child] = Child.LayoutOrder
                    end
                end

                if #HandledChildren == 0 then return end

                local Width = Holder.AbsoluteSize.X / Library.DPIScale
                if Width < 50 then Width = 220 end

                Placeholder = CreatePlaceholder()
                Box.PopOutPlaceholder = Placeholder

                Float = New("Frame", {
                    Active = true,
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Position = FloatPosition or UDim2.fromOffset(
                        Holder.AbsolutePosition.X / Library.DPIScale,
                        Holder.AbsolutePosition.Y / Library.DPIScale
                    ),
                    Size = UDim2.fromOffset(Width, 0),
                    ZIndex = 1,
                    Parent = Floats,
                })
                FloatScale = New("UIScale", { Parent = Float })
                table.insert(Library.Scales, FloatScale)
                FloatScale.Scale = Library.DPIScale

                New("UIListLayout", { Padding = UDim.new(0, 6), Parent = Float })

                for _, Child in ipairs(HandledChildren) do
                    Child.Parent = Float
                end

                if not table.find(Library.DraggableElements, Float) then
                    table.insert(Library.DraggableElements, Float)
                end

                Box.PopOutFloat = Float
                Box.PoppedOut = true
                RaiseFloat()

                if Options.After then Options.After() end
                return
            end

            if Float then
                local idx = table.find(Library.DraggableElements, Float)
                if idx then table.remove(Library.DraggableElements, idx) end
            end

            if FloatScale then
                local idx = table.find(Library.Scales, FloatScale)
                if idx then table.remove(Library.Scales, idx) end
            end

            for _, Child in ipairs(HandledChildren) do
                if Child and Child.Parent then
                    Child.Parent = OriginalParents[Child] or BoxHolder
                    Child.LayoutOrder = OriginalLayoutOrders[Child] or 0
                end
            end

            if Placeholder then Placeholder:Destroy() Placeholder = nil end
            PlaceholderHeader = nil
            if Float then Float:Destroy() Float = nil end

            Box.PopOutFloat = nil
            Box.PoppedOut = false
            table.clear(HandledChildren)
            table.clear(OriginalParents)
            table.clear(OriginalLayoutOrders)

            if Options.After then Options.After() end
        end

        function Box:TogglePoppedOut()
            Box:SetPoppedOut(not Box.PoppedOut)
        end
    end

    --================================================================
    --  CREATEWINDOW
    --================================================================
    local DefaultWindowInfo = {
        Title       = "NoctraLib",
        Icon        = nil,                 -- asset id ou lucide name
        Footer      = "NoctraLib • NoBreath",
        Position    = UDim2.fromOffset(8, 8),
        Size        = UDim2.fromOffset(720, 460),
        Center      = true,
        Resizable   = true,
        BorderResize = true,
        MinSize     = Vector2.new(480, 320),
        MaxSize     = nil,
        CornerRadius = 6,
        Font        = nil,
        ToggleKeybind = Enum.KeyCode.RightControl,
        NotifySide  = "Right",
        AlwaysOnTop = true,
        AutoShow    = true,
        ShowCustomCursor = false,
        SearchBar   = true,
        GlobalSearch = false,
        Snapping    = false,
        SnapDistance = 24,
        SnapMargin   = 8,
    }

    function Library:CreateWindow(WindowInfo)
        WindowInfo = Library:Validate(WindowInfo, DefaultWindowInfo)

        if WindowInfo.Font then
            Library.Font = WindowInfo.Font
        end
        Library.CornerRadius = WindowInfo.CornerRadius or 6
        Library.MinSize      = WindowInfo.MinSize or Library.MinSize
        Library.ToggleKeybind = WindowInfo.ToggleKeybind
        Library.GlobalSearch  = WindowInfo.GlobalSearch
        Library.ShowCustomCursor = WindowInfo.ShowCustomCursor

        local viewport = workspace.CurrentCamera.ViewportSize
        local MaxX = viewport.X - 64
        local MaxY = viewport.Y - 64

        WindowInfo.Size = UDim2.fromOffset(
            math.clamp(WindowInfo.Size.X.Offset, Library.MinSize.X, MaxX),
            math.clamp(WindowInfo.Size.Y.Offset, Library.MinSize.Y, MaxY)
        )

        --// Estrutura principal
        local MainFrame, DividerLine, TopBar, TitleHolder, WindowTitle, WindowIcon
        local RightWrapper, SearchBox, Tabs, Container, BottomBar, FooterLabel
        local ResizeIcon = nil

        MainFrame = New("TextButton", {
            Name = "Main",
            BackgroundColor3 = function()
                return Library:GetBetterColor(Library.Scheme.BackgroundColor, -1)
            end,
            Text = "",
            Position = WindowInfo.Position,
            Size = WindowInfo.Size,
            Visible = false,
            AutoButtonColor = false,
            Parent = ScreenGui,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, WindowInfo.CornerRadius),
            Parent = MainFrame,
        }))
        table.insert(Library.Scales, New("UIScale", { Parent = MainFrame }))
        Library:AddOutline(MainFrame)

        -- linha vertical que divide sidebar de conteúdo
        DividerLine = New("Frame", {
            BackgroundColor3 = "OutlineColor",
            Position = UDim2.fromOffset(180, 0),
            Size = UDim2.new(0, 1, 1, -22),
            ZIndex = 2,
            Parent = MainFrame,
        })

        -- topbar (drag)
        TopBar = New("Frame", {
            Name = "TopBar",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 48),
            Parent = MainFrame,
        })
        Library:MakeDraggable(MainFrame, TopBar, false, true, {
            Enabled = WindowInfo.Snapping,
            Distance = WindowInfo.SnapDistance,
            Margin   = WindowInfo.SnapMargin,
        })

        -- título + ícone
        TitleHolder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 180, 1, 0),
            Parent = TopBar,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
            Parent = TitleHolder,
        })

        if WindowInfo.Icon then
            WindowIcon = New("ImageLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(24, 24),
                ImageColor3 = "AccentColor",
                Parent = TitleHolder,
            })
            pcall(function()
                WindowIcon.Image = tostring(WindowInfo.Icon)
            end)
        else
            WindowIcon = New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(24, 24),
                Text = WindowInfo.Title:sub(1, 1),
                TextScaled = true,
                TextColor3 = "AccentColor",
                Parent = TitleHolder,
            })
        end

        local TitleX = Library:GetTextBounds(
            WindowInfo.Title, Library.Font, 18, 180 - 60
        )
        WindowTitle = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(0, TitleX, 1, 0),
            Text = WindowInfo.Title,
            TextSize = 18,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = TitleHolder,
        })

        -- botões de janela — fechar, minimizar, maximizar, fullscreen
        local function MakeWindowButton(IconId, Tooltip, ClickCallback)
            local Btn = New("TextButton", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(28, 28),
                Text = "",
                Parent = TopBar,
            })
            local Icon = New("ImageLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(16, 16),
                Position = UDim2.fromOffset(6, 6),
                ImageColor3 = "FontColor",
                ImageTransparency = 0.35,
                Parent = Btn,
            })
            pcall(function()
                Icon.Image = IconId
            end)

            Btn.MouseEnter:Connect(function()
                TweenService:Create(Icon, Library.TweenInfo, { ImageTransparency = 0 }):Play()
            end)
            Btn.MouseLeave:Connect(function()
                TweenService:Create(Icon, Library.TweenInfo, { ImageTransparency = 0.35 }):Play()
            end)
            Btn.MouseButton1Click:Connect(function()
                Sounds:PlayClick()
                ClickCallback()
            end)

            return Btn
        end

        -- fechar
        local CloseBtn = MakeWindowButton(
            "rbxassetid://102326100327209",
            "Fechar",
            function() Library:Toggle(false) end
        )
        CloseBtn.AnchorPoint = Vector2.new(1, 0)
        CloseBtn.Position = UDim2.new(1, -6, 0, 10)

        -- minimizar (não disponível ainda — só esconde)
        local MinBtn = MakeWindowButton(
            "rbxassetid://107097915128295",   -- fallback lucide "minus"
            "Minimizar",
            function() Library:Toggle(false) end
        )
        MinBtn.AnchorPoint = Vector2.new(1, 0)
        MinBtn.Position = UDim2.new(1, -38, 0, 10)

        -- maximizar / restaurar
        local MaxBtn = MakeWindowButton(
            "rbxassetid://107348972788829",   -- fallback lucide "square"
            "Maximizar",
            function()
                if Library._IsMaximized then
                    Library._IsMaximized = false
                    MainFrame.Size     = Library._LastSize or WindowInfo.Size
                    MainFrame.Position = Library._LastPosition or MainFrame.Position
                else
                    Library._LastSize     = MainFrame.Size
                    Library._LastPosition = MainFrame.Position
                    Library._IsMaximized  = true
                    MainFrame.Size     = UDim2.fromOffset(viewport.X - 32, viewport.Y - 80)
                    MainFrame.Position = UDim2.fromOffset(16, 16)
                end
            end
        )
        MaxBtn.AnchorPoint = Vector2.new(1, 0)
        MaxBtn.Position = UDim2.new(1, -70, 0, 10)

        --================================================================
        --  SEARCH + CONTAINER
        --================================================================
        RightWrapper = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -110, 0.5, 0),
            Size = UDim2.new(1, -180 - 120, 1, -16),
            Parent = TopBar,
        })

        SearchBox = New("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = "MainColor",
            PlaceholderText = "Search",
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.new(1, 0, 1, 0),
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Visible = WindowInfo.SearchBar ~= false,
            Parent = RightWrapper,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = SearchBox,
        }))
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            Parent = SearchBox,
        })
        local SearchStroke = New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = SearchBox,
        })
        SearchBox.Focused:Connect(function()
            TweenService:Create(SearchStroke, Library.TweenInfo, {
                Color = Library.Scheme.AccentColor,
            }):Play()
            Sounds:BeginTyping()
        end)
        SearchBox.FocusLost:Connect(function()
            TweenService:Create(SearchStroke, Library.TweenInfo, {
                Color = Library.Scheme.OutlineColor,
            }):Play()
            Sounds:StopTyping()
        end)

        -- barra de tabs (sidebar)
        Tabs = New("ScrollingFrame", {
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = "BackgroundColor",
            CanvasSize = UDim2.fromScale(0, 0),
            Position = UDim2.fromOffset(0, 49),
            Size = UDim2.new(0, 180, 1, -71),
            ScrollBarThickness = 0,
            Parent = MainFrame,
        })
        New("UIListLayout", { Parent = Tabs })

        -- container (onde as tabs aparecem)
        Container = New("Frame", {
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = function()
                return Library:GetBetterColor(Library.Scheme.BackgroundColor, 1)
            end,
            ClipsDescendants = true,
            Name = "Container",
            Position = UDim2.new(1, 0, 0, 49),
            Size = UDim2.new(1, -181, 1, -71),
            Parent = MainFrame,
        })
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            Parent = Container,
        })
        Library.WindowContainer = Container

        -- rodapé
        BottomBar = New("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = function()
                return Library:GetBetterColor(Library.Scheme.BackgroundColor, 3)
            end,
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 22 + Library.CornerRadius),
            Parent = MainFrame,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = BottomBar,
        }))
        Library:MakeLine(MainFrame, {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, -22),
            Size = UDim2.new(1, 0, 0, 1),
        })

        FooterLabel = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 0, 0, 22),
            Text = WindowInfo.Footer,
            TextSize = 13,
            TextColor3 = "FontColor",
            TextTransparency = 0.5,
            Parent = BottomBar,
        })

        --================================================================
        --  RESIZE PELA BORDA (8 handles)
        --================================================================
        if WindowInfo.BorderResize and WindowInfo.Resizable then
            Library:MakeBorderResizable(MainFrame, Library.MinSize, function()
                for _, Tab in pairs(Library.Tabs) do
                    if Tab.Resize then Tab:Resize(true) end
                end
            end)
        end

        -- cantinho inferior direito com ícone de resize (fallback)
        if WindowInfo.Resizable then
            local CornerResize = New("TextButton", {
                AnchorPoint = Vector2.new(1, 1),
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -2, 1, -2),
                Size = UDim2.fromOffset(16, 16),
                Text = "",
                ZIndex = 5,
                Parent = MainFrame,
            })
            local Icon = New("ImageLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(2, 2),
                Size = UDim2.new(1, -4, 1, -4),
                ImageColor3 = "FontColor",
                ImageTransparency = 0.5,
                Parent = CornerResize,
            })
            pcall(function()
                Icon.Image = "rbxassetid://107348972788829"
            end)

            local StartMouse, StartSize
            local Dragging = false
            local ChangedConn

            CornerResize.InputBegan:Connect(function(Input)
                if not IsClickInput(Input) then return end
                Library.CantDragForced = true
                Dragging = true
                StartMouse = Vector2.new(Input.Position.X, Input.Position.Y)
                StartSize  = MainFrame.AbsoluteSize

                ChangedConn = Input.Changed:Connect(function()
                    if Input.UserInputState ~= Enum.UserInputState.End then return end
                    Dragging = false
                    Library.CantDragForced = false
                    if ChangedConn and ChangedConn.Connected then
                        ChangedConn:Disconnect()
                        ChangedConn = nil
                    end
                end)
            end)

            GiveSignal(UserInputService.InputChanged:Connect(function(Input)
                if not Dragging or not IsHoverInput(Input) then return end
                local Delta = Vector2.new(Input.Position.X, Input.Position.Y) - StartMouse
                local W = math.max(Library.MinSize.X, StartSize.X + Delta.X)
                local H = math.max(Library.MinSize.Y, StartSize.Y + Delta.Y)
                MainFrame.Size = UDim2.fromOffset(W, H)
                for _, Tab in pairs(Library.Tabs) do
                    if Tab.Resize then Tab:Resize(true) end
                end
            end))
        end

        --================================================================
        --  WINDOW API
        --================================================================
        local Window = {}
        Library.Window = Window
        Library._MainFrame = MainFrame

        Window.MainFrame = MainFrame

        function Window:ChangeTitle(title)
            WindowTitle.Text = title
            WindowInfo.Title = title
        end

        function Window:SetFooter(text)
            FooterLabel.Text = text
        end

        function Window:SetBackgroundImage(id)
            -- implementação simples — guarda pra depois aplicar em frame dedicado
            Library.Scheme.BackgroundImage = id
        end

        function Window:Toggle(value)
            if typeof(value) == "boolean" then
                Library.Toggled = value
            else
                Library.Toggled = not Library.Toggled
            end

            MainFrame.Visible = Library.Toggled

            if Library.Toggled then
                Sounds:PlayClick()
                RunService:BindToRenderStep("NoctraLib_Cursor", Enum.RenderPriority.Last.Value, function()
                    Cursor.Position = UDim2.fromOffset(Mouse.X, Mouse.Y)
                    Cursor.Visible = Library.ShowCustomCursor
                end)
            else
                RestoreMouseIcon()
            end
        end

        Library.Toggle = function(v) return Window:Toggle(v) end

        --================================================================
        --  TAB
        --================================================================
        function Window:AddTab(...)
            local Name, Icon, Description, Order

            if select("#", ...) == 1 and typeof(...) == "table" then
                local info = ...
                Name = info.Name or "Tab"
                Icon = info.Icon
                Description = info.Description
                Order = info.Order
            else
                Name = select(1, ...) or "Tab"
                Icon = select(2, ...)
                Description = select(3, ...)
                Order = select(4, ...)
            end

            if not tonumber(Order) then Order = #Tabs:GetChildren() end

            local TabButton, TabLabel, TabIcon
            local TabCanvas, TabContainer, TabLeft, TabRight

            TabButton = New("TextButton", {
                BackgroundColor3 = "MainColor",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 40),
                Text = "",
                LayoutOrder = Order,
                Parent = Tabs,
            })
            local ButtonPadding = New("UIPadding", {
                PaddingLeft  = UDim.new(0, 14),
                PaddingRight = UDim.new(0, 14),
                PaddingTop   = UDim.new(0, 11),
                PaddingBottom = UDim.new(0, 11),
                Parent = TabButton,
            })

            TabLabel = New("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(32, 0),
                Size = UDim2.new(1, -32, 1, 0),
                Text = Name,
                TextSize = 15,
                TextTransparency = 0.5,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = TabButton,
            })

            if Icon then
                TabIcon = New("ImageLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    SizeConstraint = Enum.SizeConstraint.RelativeYY,
                    ImageColor3 = "AccentColor",
                    ImageTransparency = 0.5,
                    Parent = TabButton,
                })
                pcall(function() TabIcon.Image = tostring(Icon) end)
            end

            table.insert(Library.TabButtons, {
                Button = TabButton,
                Label  = TabLabel,
                Icon   = TabIcon,
                Padding = ButtonPadding,
            })

            -- Canvas
            TabCanvas = New("CanvasGroup", {
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                GroupTransparency = 0,
                Size = UDim2.fromScale(1, 1),
                Visible = false,
                Parent = Container,
            })

            TabContainer = New("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Parent = TabCanvas,
            })

            TabLeft = New("ScrollingFrame", {
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                CanvasSize = UDim2.fromScale(0, 0),
                ScrollBarThickness = 0,
                Size = UDim2.new(0.5, -3, 1, 0),
                Parent = TabContainer,
            })
            New("UIListLayout", { Padding = UDim.new(0, 8), Parent = TabLeft })
            New("UIPadding", {
                PaddingBottom = UDim.new(0, 6),
                PaddingTop    = UDim.new(0, 6),
                Parent = TabLeft,
            })

            TabRight = New("ScrollingFrame", {
                AnchorPoint = Vector2.new(1, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                CanvasSize = UDim2.fromScale(0, 0),
                Position = UDim2.fromScale(1, 0),
                ScrollBarThickness = 0,
                Size = UDim2.new(0.5, -3, 1, 0),
                Parent = TabContainer,
            })
            New("UIListLayout", { Padding = UDim.new(0, 8), Parent = TabRight })
            New("UIPadding", {
                PaddingBottom = UDim.new(0, 6),
                PaddingTop    = UDim.new(0, 6),
                Parent = TabRight,
            })

            local Tab = {
                Name = Name,
                Description = Description,
                Window = Window,
                Canvas = TabCanvas,
                Sides = { TabLeft, TabRight },
                Groupboxes = {},
                Tabboxes   = {},
                DependencyBoxes = {},
                DependencyGroupboxes = {},
                Elements = {},
                Connections = {},
                Destroyed = false,
            }

            function Tab:Show()
                if Library.ActiveTab == Tab then return end
                if Library.ActiveTab then Library.ActiveTab:Hide() end

                TweenService:Create(TabButton, Library.TweenInfo, { BackgroundTransparency = 0 }):Play()
                TweenService:Create(TabLabel,  Library.TweenInfo, { TextTransparency = 0 }):Play()
                if TabIcon then
                    TweenService:Create(TabIcon, Library.TweenInfo, { ImageTransparency = 0 }):Play()
                end

                TabCanvas.Visible = true
                TabCanvas.GroupTransparency = 0
                Library.ActiveTab = Tab
            end

            function Tab:Hide()
                TweenService:Create(TabButton, Library.TweenInfo, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(TabLabel,  Library.TweenInfo, { TextTransparency = 0.5 }):Play()
                if TabIcon then
                    TweenService:Create(TabIcon, Library.TweenInfo, { ImageTransparency = 0.5 }):Play()
                end
                TabCanvas.Visible = false
                Library.ActiveTab = nil
            end

            function Tab:Resize() end
            function Tab:RefreshSides() end
            function Tab:UpdateCorners() end

            function Tab:Destroy()
                Tab.Destroyed = true
                for _, g in pairs(Tab.Groupboxes) do
                    if g.Destroy then g:Destroy() end
                end
                for _, t in pairs(Tab.Tabboxes) do
                    if t.Destroy then t:Destroy() end
                end
                if TabCanvas then TabCanvas:Destroy() end
                if TabButton then TabButton:Destroy() end
                Library.Tabs[Name] = nil
            end

            --================================================================
            --  GROUPBOX
            --================================================================
            function Tab:AddGroupbox(Info)
                if typeof(Info) == "string" then Info = { Name = Info } end
                Info = Library:Validate(Info, {
                    Side = 1,
                    Name = "Groupbox",
                    IconName = nil,
                    Description = nil,
                    Visible = true,
                    Collapsed = false,
                    DisableCollapsing = false,
                    PopOut = true,
                })

                if typeof(Info.Side) == "string" then
                    Info.Side = (string.lower(Info.Side) == "left") and 1 or 2
                end

                local BoxHolder = New("Frame", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 0),
                    Parent = (Info.Side == 1) and TabLeft or TabRight,
                })
                New("UIListLayout", { Padding = UDim.new(0, 6), Parent = BoxHolder })
                New("UIPadding", {
                    PaddingBottom = UDim.new(0, 4),
                    PaddingTop    = UDim.new(0, 4),
                    Parent = BoxHolder,
                })

                local GroupboxHolder = New("Frame", {
                    BackgroundColor3 = "BackgroundColor",
                    Size = UDim2.fromScale(1, 0),
                    Parent = BoxHolder,
                })
                table.insert(Library.Corners, New("UICorner", {
                    CornerRadius = UDim.new(0, Library.CornerRadius),
                    Parent = GroupboxHolder,
                }))
                New("UIListLayout", { Parent = GroupboxHolder })
                Library:AddOutline(GroupboxHolder)

                local GroupboxTop = New("Frame", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 0),
                    Parent = GroupboxHolder,
                })
                New("UIPadding", {
                    PaddingBottom = UDim.new(0, 6),
                    PaddingLeft   = UDim.new(0, 8),
                    PaddingRight  = UDim.new(0, 8),
                    PaddingTop    = UDim.new(0, 6),
                    Parent = GroupboxTop,
                })

                if Info.IconName then
                    local iconLbl = New("ImageLabel", {
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.fromScale(0, 0.5),
                        Size = UDim2.fromOffset(18, 18),
                        ImageColor3 = "AccentColor",
                        BackgroundTransparency = 1,
                        Parent = GroupboxTop,
                    })
                    pcall(function() iconLbl.Image = tostring(Info.IconName) end)
                end

                local TextsFrame = New("Frame", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(Info.IconName and 26 or 0, 0),
                    Size = UDim2.new(1, Info.IconName and -26 or 0, 0, 0),
                    Parent = GroupboxTop,
                })
                New("UIListLayout", { Parent = TextsFrame })

                local GroupboxLabel = New("TextLabel", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 0),
                    Text = Info.Name,
                    TextSize = 15,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TextsFrame,
                })

                local GroupboxDescription = New("TextLabel", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 0),
                    Text = Info.Description or "",
                    TextSize = 13,
                    TextTransparency = 0.5,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Visible = Info.Description ~= nil,
                    Parent = TextsFrame,
                })

                local CollapseArrow = New("ImageButton", {
                    Visible = not Info.DisableCollapsing,
                    AnchorPoint = Vector2.new(1, 0.5),
                    BackgroundTransparency = 1,
                    Position = UDim2.fromScale(1, 0.5),
                    Size = UDim2.fromOffset(20, 20),
                    ImageColor3 = "FontColor",
                    ImageTransparency = 0.4,
                    Rotation = 180,
                    Parent = GroupboxTop,
                })
                pcall(function()
                    CollapseArrow.Image = "rbxassetid://107097915128295"
                end)

                local GroupboxLine = Library:MakeLine(GroupboxHolder, {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 1),
                })

                local GroupboxContainer = New("ScrollingFrame", {
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    CanvasSize = UDim2.fromScale(0, 0),
                    LayoutOrder = 2,
                    ScrollBarThickness = 0,
                    Size = UDim2.fromScale(1, 0),
                    Parent = GroupboxHolder,
                })
                local GroupboxList = New("UIListLayout", {
                    Padding = UDim.new(0, 8),
                    Parent = GroupboxContainer,
                })
                New("UIPadding", {
                    PaddingBottom = UDim.new(0, 8),
                    PaddingLeft   = UDim.new(0, 8),
                    PaddingRight  = UDim.new(0, 8),
                    PaddingTop    = UDim.new(0, 8),
                    Parent = GroupboxContainer,
                })

                local Groupbox = {
                    Type = "Groupbox",
                    Name = Info.Name,
                    Description = Info.Description,
                    Visible = true,
                    Collapsed = false,
                    BoxHolder = BoxHolder,
                    Holder = GroupboxHolder,
                    Container = GroupboxContainer,
                    Elements = {},
                    DependencyBoxes = {},
                    Tab = Tab,
                    Destroyed = false,
                }

                function Groupbox:Resize()
                    local TopSize = GroupboxTop.AbsoluteSize.Y / Library.DPIScale
                    local BodySize = GroupboxList.AbsoluteContentSize.Y / Library.DPIScale + 16
                    if Groupbox.PoppedOut then
                        BodySize = math.min(BodySize, GetPopOutBodyMaxHeight(Groupbox, TopSize + 1))
                    end
                    GroupboxContainer.Size = UDim2.new(1, 0, 0, BodySize)
                    GroupboxHolder.Size = UDim2.new(1, 0, 0, Groupbox.Collapsed and TopSize or (TopSize + 1 + BodySize))
                    GroupboxLine.Visible = not Groupbox.Collapsed
                    GroupboxContainer.Visible = not Groupbox.Collapsed
                end

                function Groupbox:SetCollapsed(state)
                    if Info.DisableCollapsing then return end
                    Groupbox.Collapsed = state
                    CollapseArrow.Rotation = state and 0 or 180
                    Groupbox:Resize()
                end

                function Groupbox:ToggleCollapsed()
                    Groupbox:SetCollapsed(not Groupbox.Collapsed)
                end

                function Groupbox:SetVisible(v)
                    Groupbox.Visible = v
                    BoxHolder.Visible = v
                end

                function Groupbox:Show() Groupbox:SetVisible(true) end
                function Groupbox:Hide() Groupbox:SetVisible(false) end

                function Groupbox:SetDescription(d)
                    GroupboxDescription.Text = d or ""
                    GroupboxDescription.Visible = d ~= nil
                    Groupbox:Resize()
                end

                function Groupbox:Destroy()
                    Groupbox.Destroyed = true
                    for _, e in pairs(Groupbox.Elements) do
                        if e.Destroy then e:Destroy() end
                    end
                    if GroupboxHolder then GroupboxHolder:Destroy() end
                    if BoxHolder then BoxHolder:Destroy() end
                end

                CollapseArrow.MouseButton1Click:Connect(function()
                    Sounds:PlayClick()
                    Groupbox:ToggleCollapsed()
                end)

                Library:MakeBoxPopOut(Groupbox, {
                    Enabled = Info.PopOut ~= false,
                    Header = GroupboxTop,
                    Children = function()
                        local list = {}
                        for _, Child in ipairs(BoxHolder:GetChildren()) do
                            if Child:IsA("GuiObject") and Child ~= Groupbox.PopOutPlaceholder then
                                table.insert(list, Child)
                            end
                        end
                        return list
                    end,
                    Before = function() CollapseArrow.Visible = false end,
                    After  = function()
                        CollapseArrow.Visible = not Info.DisableCollapsing
                        Groupbox:Resize()
                    end,
                })

                -- Elementos vão ser pendurados por elements.lua através dessa tabela
                Groupbox.Elements = Groupbox.Elements or {}
                Groupbox.Container = GroupboxContainer
                Groupbox.Resize = Groupbox.Resize

                -- Guarda referência pro elements.lua adicionar métodos
                Groupbox._AddElement = function(element)
                    table.insert(Groupbox.Elements, element)
                    Groupbox:Resize()
                end

                Tab.Groupboxes[Info.Name or #Tab.Groupboxes + 1] = Groupbox

                if Info.Visible == false then Groupbox:Hide() end
                if Info.Collapsed then Groupbox:SetCollapsed(true) end

                task.defer(function() Groupbox:Resize() end)

                return Groupbox
            end

            --================================================================
            --  TABBOX
            --================================================================
            function Tab:AddTabbox(Info)
                Info = Info or {}
                Info = Library:Validate(Info, {
                    Side = 1,
                    Name = nil,
                    PopOut = true,
                })

                if typeof(Info.Side) == "string" then
                    Info.Side = (string.lower(Info.Side) == "left") and 1 or 2
                end

                local BoxHolder = New("Frame", {
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 0),
                    Parent = (Info.Side == 1) and TabLeft or TabRight,
                })
                New("UIListLayout", { Padding = UDim.new(0, 6), Parent = BoxHolder })

                local TabboxHolder = New("Frame", {
                    BackgroundColor3 = "BackgroundColor",
                    Size = UDim2.fromScale(1, 0),
                    Parent = BoxHolder,
                })
                table.insert(Library.Corners, New("UICorner", {
                    CornerRadius = UDim.new(0, Library.CornerRadius),
                    Parent = TabboxHolder,
                }))
                Library:AddOutline(TabboxHolder)

                local TabboxButtons = New("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 32),
                    Parent = TabboxHolder,
                })
                New("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalFlex = Enum.UIFlexAlignment.Fill,
                    Parent = TabboxButtons,
                })

                local Tabbox = {
                    Type = "Tabbox",
                    Tabs = {},
                    ActiveTab = nil,
                    BoxHolder = BoxHolder,
                    Holder = TabboxHolder,
                    Visible = true,
                    Destroyed = false,
                    Connections = {},
                }

                function Tabbox:Resize()
                    if Tabbox.ActiveTab then Tabbox.ActiveTab:Resize() end
                end

                function Tabbox:Destroy()
                    Tabbox.Destroyed = true
                    for _, t in pairs(Tabbox.Tabs) do
                        if t.Destroy then t:Destroy() end
                    end
                    if TabboxHolder then TabboxHolder:Destroy() end
                    if BoxHolder then BoxHolder:Destroy() end
                end

                function Tabbox:AddTab(Name, Icon)
                    local Button = New("TextButton", {
                        BackgroundColor3 = "MainColor",
                        Size = UDim2.fromOffset(0, 32),
                        Text = "",
                        Parent = TabboxButtons,
                    })
                    local corner = New("UICorner", {
                        CornerRadius = UDim.new(0, Library.CornerRadius),
                        Parent = Button,
                    })
                    table.insert(Library.SpecificCorners, corner)

                    local BtnLabel = New("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.fromScale(1, 1),
                        Text = Name or "",
                        TextSize = 14,
                        TextTransparency = 0.5,
                        Parent = Button,
                    })

                    local Container = New("ScrollingFrame", {
                        AutomaticCanvasSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        CanvasSize = UDim2.fromScale(0, 0),
                        Position = UDim2.fromOffset(0, 33),
                        ScrollBarThickness = 0,
                        Size = UDim2.new(1, 0, 1, -33),
                        Visible = false,
                        Parent = TabboxHolder,
                    })
                    local List = New("UIListLayout", {
                        Padding = UDim.new(0, 8),
                        Parent = Container,
                    })
                    New("UIPadding", {
                        PaddingBottom = UDim.new(0, 8),
                        PaddingLeft   = UDim.new(0, 8),
                        PaddingRight  = UDim.new(0, 8),
                        PaddingTop    = UDim.new(0, 8),
                        Parent = Container,
                    })

                    local SubTab = {
                        Name = Name,
                        Container = Container,
                        Elements = {},
                        DependencyBoxes = {},
                        Type = "SubTab",
                    }

                    function SubTab:Show()
                        if Tabbox.ActiveTab then Tabbox.ActiveTab:Hide() end
                        Button.BackgroundTransparency = 1
                        BtnLabel.TextTransparency = 0
                        Container.Visible = true
                        Tabbox.ActiveTab = SubTab
                        SubTab:Resize()
                    end

                    function SubTab:Hide()
                        Button.BackgroundTransparency = 0
                        BtnLabel.TextTransparency = 0.5
                        Container.Visible = false
                        Tabbox.ActiveTab = nil
                    end

                    function SubTab:Resize()
                        local size = List.AbsoluteContentSize.Y / Library.DPIScale + 16
                        Container.Size = UDim2.new(1, 0, 0, size)
                        TabboxHolder.Size = UDim2.new(1, 0, 0, size + 33)
                    end

                    function SubTab:Destroy()
                        Container:Destroy()
                        Button:Destroy()
                    end

                    Button.MouseButton1Click:Connect(function()
                        Sounds:PlayClick()
                        SubTab:Show()
                    end)

                    Tabbox.Tabs[Name or #Tabbox.Tabs + 1] = SubTab
                    if not Tabbox.ActiveTab then SubTab:Show() end

                    return SubTab
                end

                Tab.Tabboxes[Info.Name or #Tab.Tabboxes + 1] = Tabbox
                task.defer(function() if Tabbox.ActiveTab then Tabbox.ActiveTab:Resize() end end)

                return Tabbox
            end

            --================================================================
            --  Register + exibição
            --================================================================
            TabButton.MouseButton1Click:Connect(function()
                Sounds:PlayClick()
                Tab:Show()
            end)

            TabButton.MouseEnter:Connect(function()
                if Library.ActiveTab ~= Tab then
                    TweenService:Create(TabLabel, Library.TweenInfo, { TextTransparency = 0.25 }):Play()
                end
            end)
            TabButton.MouseLeave:Connect(function()
                if Library.ActiveTab ~= Tab then
                    TweenService:Create(TabLabel, Library.TweenInfo, { TextTransparency = 0.5 }):Play()
                end
            end)

            Library.Tabs[Name] = Tab
            if not Library.ActiveTab then
                Tab:Show()
            end

            return Tab
        end

        --================================================================
        --  TOGGLE KEYBIND + ESC
        --================================================================
        GiveSignal(UserInputService.InputBegan:Connect(function(Input)
            if Library.Unloaded then return end

            if Input.KeyCode == Enum.KeyCode.Escape then
                local FocusedBox = UserInputService:GetFocusedTextBox()
                if FocusedBox then
                    FocusedBox:ReleaseFocus()
                    return
                end
                if Library.ActiveDialog then
                    Library.ActiveDialog:Dismiss()
                    return
                end
                return
            end

            if UserInputService:GetFocusedTextBox() then return end

            if Input.KeyCode == Library.ToggleKeybind then
                Library:Toggle()
            end
        end))

        GiveSignal(UserInputService.WindowFocused:Connect(function()
            Library.IsRobloxFocused = true
        end))
        GiveSignal(UserInputService.WindowFocusReleased:Connect(function()
            Library.IsRobloxFocused = false
        end))

        -- centralizar
        if WindowInfo.Center then
            MainFrame.Position = UDim2.new(
                0.5, -MainFrame.Size.X.Offset / 2,
                0.5, -MainFrame.Size.Y.Offset / 2
            )
        end

        -- hover de clique (feedback do botão principal)
        MainFrame.MouseEnter:Connect(function()
            MainFrame.BackgroundColor3 = Library:GetBetterColor(Library.Scheme.BackgroundColor, 0)
        end)

        if WindowInfo.AutoShow and not Library.ActiveLoading then
            task.spawn(function() Library:Toggle(true) end)
        end

        --================================================================
        --  SEARCH — placeholder (search real implementado em elements/extras)
        --================================================================
        GiveSignal(SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            Library.SearchText = SearchBox.Text
            Library.Searching  = SearchBox.Text ~= ""
        end))

        return Window
    end

    --================================================================
    --  DRAGGABLE LABELS / BUTTONS (usados pra flutuar textos)
    --================================================================
    function Library:AddDraggableLabel(Text, Icon, IconPosition)
        local Label = {
            Connections = {},
            Destroyed = false,
        }

        local IconImage
        local Lbl = New("TextLabel", {
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundColor3 = "BackgroundColor",
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(0, 0),
            Text = Text or "",
            TextSize = 15,
            TextColor3 = "FontColor",
            ZIndex = 1,
            Parent = Floats,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Lbl,
        }))
        local Padding = New("UIPadding", {
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft   = UDim.new(0, 12),
            PaddingRight  = UDim.new(0, 12),
            PaddingTop    = UDim.new(0, 6),
            Parent = Lbl,
        })
        table.insert(Library.Scales, New("UIScale", { Parent = Lbl }))
        Library:AddOutline(Lbl)
        Library:MakeDraggable(Lbl, Lbl, true)

        function Label:SetText(t) Lbl.Text = t end
        function Label:SetVisible(v) Lbl.Visible = v end
        function Label:SetIcon(id)
            if id and id ~= "" then
                if not IconImage then
                    IconImage = New("ImageLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.fromOffset(16, 16),
                        ImageColor3 = "FontColor",
                        Parent = Lbl,
                    })
                end
                pcall(function() IconImage.Image = tostring(id) end)
                IconImage.Visible = true
            elseif IconImage then
                IconImage.Visible = false
            end
        end
        function Label:Destroy()
            Label.Destroyed = true
            if Lbl then Lbl:Destroy() end
        end

        Label.Label = Lbl
        Label:SetIcon(Icon)

        if not table.find(Library.DraggableElements, Lbl) then
            table.insert(Library.DraggableElements, Lbl)
        end

        return Label
    end

    function Library:AddDraggableButton(Text, Callback, NoScaling, NoDragging)
        local Btn = New("TextButton", {
            BackgroundColor3 = "BackgroundColor",
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(90, 26),
            Text = Text or "",
            TextSize = 14,
            TextColor3 = "FontColor",
            ZIndex = 1,
            Parent = Floats,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Btn,
        }))
        if not NoScaling then
            table.insert(Library.Scales, New("UIScale", { Parent = Btn }))
        end
        Library:AddOutline(Btn)

        local wrapper = { Button = Btn }

        function wrapper:SetText(t) Btn.Text = t end
        function wrapper:Destroy() Btn:Destroy() end

        local DragThreshold = NoDragging and 0.25 or math.huge
        Btn.InputBegan:Connect(function(Input)
            if not IsClickInput(Input) then return end
            local Start = tick()
            local Changed
            Changed = Input.Changed:Connect(function()
                if Input.UserInputState ~= Enum.UserInputState.End then return end
                if tick() - Start > DragThreshold then return end
                Sounds:PlayClick()
                Library:SafeCallback(Callback, wrapper)
                if Changed and Changed.Connected then Changed:Disconnect() end
            end)
        end)

        Library:MakeDraggable(Btn, Btn, true)

        if not table.find(Library.DraggableElements, Btn) then
            table.insert(Library.DraggableElements, Btn)
        end

        return wrapper
    end

    --================================================================
    --  FIM
    --================================================================
    return Library
end