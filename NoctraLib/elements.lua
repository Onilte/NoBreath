--[[
    NoctraLib :: elements.lua
    ----------------------------------------------------------------
    Todos os controles interativos:
      • Toggle, Checkbox
      • Button, SubButton
      • Label, Divider
      • Slider
      • Input
      • Dropdown (multi, search, drag-select)
      • KeyPicker
      • ColorPicker
      • Viewport, Image, Video
      • DependencyBox

    Pendura métodos :Add* em Groupbox e em SubTab.
    Retorna uma função Attach(Library) que devolve Library.
]]

return function(Library)

    local cloneref = (cloneref or clonereference or function(x) return x end)
    local Players        = cloneref(game:GetService("Players"))
    local RunService     = cloneref(game:GetService("RunService"))
    local UserInputService = cloneref(game:GetService("UserInputService"))
    local TweenService   = cloneref(game:GetService("TweenService"))
    local SoundService   = cloneref(game:GetService("SoundService"))
    local LocalPlayer    = Library.LocalPlayer
    local Mouse          = cloneref(LocalPlayer:GetMouse())

    local Sounds = Library.Sounds
    local New    = function(...) return Library:New(...) end
    local function GiveSignal(c) return Library:GiveSignal(c) end
    local function SafeCallback(f, ...) return Library:SafeCallback(f, ...) end
    local function Validate(t, tmpl) return Library:Validate(t, tmpl) end

    Library.Options  = Library.Options  or {}
    Library.Toggles  = Library.Toggles  or {}
    Library.Buttons  = Library.Buttons  or {}
    Library.Labels   = Library.Labels   or {}
    Library.Tooltips = Library.Tooltips or {}

    --================================================================
    --  INPUT HELPERS
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
    local function IsDragInput(Input, IncludeM2)
        return IsMouseInput(Input, IncludeM2)
            and (Input.UserInputState == Enum.UserInputState.Begin
              or Input.UserInputState == Enum.UserInputState.Change)
            and Library.IsRobloxFocused
    end

    local function IsSequentialArray(t)
        for k in pairs(t) do
            if typeof(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        end
        return true
    end
    local function GetTableSize(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    --================================================================
    --  TOOLTIP (simples, segue o mouse)
    --================================================================
    local TooltipLabel = New("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = "BackgroundColor",
        Size = UDim2.fromOffset(120, 0),
        Text = "",
        TextSize = 13,
        TextColor3 = "FontColor",
        TextWrapped = true,
        Visible = false,
        ZIndex = 30,
        Parent = Library.ScreenGui,
    })
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        PaddingTop    = UDim.new(0, 4),
        Parent = TooltipLabel,
    })
    New("UIStroke", {
        Color = "OutlineColor",
        Thickness = Library.StrokeThickness,
        Parent = TooltipLabel,
    })
    table.insert(Library.Corners, New("UICorner", {
        CornerRadius = UDim.new(0, Library.CornerRadius / 2),
        Parent = TooltipLabel,
    }))

    local CurrentHoverInstance

    function Library:AddTooltip(InfoStr, DisabledStr, HoverInstance)
        local TooltipTable = { Disabled = false, Signals = {} }
        local function GiveSignalLocal(c)
            table.insert(TooltipTable.Signals, c)
        end

        local function DoHover()
            if CurrentHoverInstance == HoverInstance then return end
            if Library.ActiveDialog then return end
            if TooltipTable.Disabled and typeof(DisabledStr) ~= "string" then return end
            if not TooltipTable.Disabled and typeof(InfoStr) ~= "string" then return end

            CurrentHoverInstance = HoverInstance
            TooltipLabel.Text = TooltipTable.Disabled and DisabledStr or InfoStr
            TooltipLabel.Visible = true

            while Library.Toggled
                and Library:MouseIsOverFrame(HoverInstance, Mouse)
                and not Library.ActiveDialog
            do
                TooltipLabel.Position = UDim2.fromOffset(Mouse.X + 12, Mouse.Y + 12)
                RunService.RenderStepped:Wait()
            end

            TooltipLabel.Visible = false
            CurrentHoverInstance = nil
        end

        GiveSignalLocal(HoverInstance.MouseEnter:Connect(DoHover))
        GiveSignalLocal(HoverInstance.MouseMoved:Connect(DoHover))
        GiveSignalLocal(HoverInstance.MouseLeave:Connect(function()
            if CurrentHoverInstance == HoverInstance then
                TooltipLabel.Visible = false
                CurrentHoverInstance = nil
            end
        end))

        function TooltipTable:Destroy()
            for _, c in ipairs(TooltipTable.Signals) do
                if c.Connected then c:Disconnect() end
            end
            if CurrentHoverInstance == HoverInstance then
                TooltipLabel.Visible = false
                CurrentHoverInstance = nil
            end
        end

        table.insert(Library.Tooltips, TooltipLabel)
        return TooltipTable
    end

    --================================================================
    --  BASE PROTO (pra todos os elementos usarem cores via Scheme)
    --================================================================
    local function RegisterColor(instance, props)
        if instance then Library:AddToRegistry(instance, props) end
    end

    --================================================================
    --  FUNÇÕES COMUNS — penduradas em Groupbox e SubTab via metatable
    --================================================================
    local ElementFuncs = {}

    --// ------------------------------------------------------------
    --// DIVIDER
    --// ------------------------------------------------------------
    function ElementFuncs:AddDivider(Params)
        if self.Destroyed then return end
        if typeof(Params) == "string" then Params = { Text = Params } end
        Params = Params or {}

        local Container = self.Container
        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 8),
            Parent = Container,
        })
        New("UIPadding", {
            PaddingTop    = UDim.new(0, Params.MarginTop or 0),
            PaddingBottom = UDim.new(0, Params.MarginBottom or 0),
            Parent = Holder,
        })

        if Params.Text then
            New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = Params.Text,
                TextSize = 13,
                TextColor3 = "FontColor",
                TextTransparency = 0.5,
                Parent = Holder,
            })
            New("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = "OutlineColor",
                BorderSizePixel = 0,
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.new(1, 0, 0, 1),
                ZIndex = -1,
                Parent = Holder,
            })
        else
            New("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = "OutlineColor",
                BorderSizePixel = 0,
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.new(1, 0, 0, 1),
                Parent = Holder,
            })
        end

        local Divider = { Type = "Divider", Holder = Holder }
        function Divider:SetVisible(v) Holder.Visible = v end
        function Divider:Destroy() Holder:Destroy() end

        if self._AddElement then self:_AddElement(Divider) end
        return Divider
    end

    --// ------------------------------------------------------------
    --// LABEL
    --// ------------------------------------------------------------
    function ElementFuncs:AddLabel(...)
        if self.Destroyed then return end

        local First, Second = ...
        local Text, DoesWrap, Size, Visible

        if typeof(First) == "table" then
            Text = First.Text or ""
            DoesWrap = First.DoesWrap or false
            Size = First.Size or 14
            Visible = First.Visible ~= false
        else
            Text = First or ""
            DoesWrap = Second or false
            Size = 14
            Visible = true
        end

        local Container = self.Container
        local Lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 18),
            AutomaticSize = DoesWrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
            Text = Text,
            TextSize = Size,
            TextColor3 = "FontColor",
            TextWrapped = DoesWrap,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Container,
        })

        local Label = {
            Type = "Label",
            Text = Text,
            Visible = Visible,
            Addons = {},
            Destroyed = false,
            TextLabel = Lbl,
        }

        function Label:SetText(t)
            Label.Text = t
            Lbl.Text = t
            if DoesWrap then
                local _, Y = Library:GetTextBounds(t, Lbl.FontFace, Lbl.TextSize, Lbl.AbsoluteSize.X)
                Lbl.Size = UDim2.new(1, 0, 0, Y + 4)
            end
        end
        function Label:SetVisible(v)
            Label.Visible = v
            Lbl.Visible = v
            if self.Resize then self:Resize() end
        end
        function Label:Destroy()
            Label.Destroyed = true
            Lbl:Destroy()
        end

        if self._AddElement then self:_AddElement(Label) end
        table.insert(Library.Labels, Label)
        return Label
    end

    --// ------------------------------------------------------------
    --// BUTTON
    --// ------------------------------------------------------------
    local function CreateButtonBase(Info, Holder)
        local Base = New("TextButton", {
            Active = not Info.Disabled,
            BackgroundColor3 = Info.Disabled and "BackgroundColor" or "MainColor",
            Size = UDim2.fromScale(1, 1),
            Text = Info.Text,
            TextSize = 14,
            TextTransparency = 0.4,
            TextColor3 = Info.Risky and "RedColor" or "FontColor",
            Visible = Info.Visible ~= false,
            Parent = Holder,
        })
        local Stroke = New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Transparency = Info.Disabled and 0.5 or 0,
            Parent = Base,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Base,
        }))

        Base.MouseEnter:Connect(function()
            if Info.Disabled then return end
            TweenService:Create(Base, Library.TweenInfo, { TextTransparency = 0 }):Play()
        end)
        Base.MouseLeave:Connect(function()
            if Info.Disabled then return end
            TweenService:Create(Base, Library.TweenInfo, { TextTransparency = 0.4 }):Play()
        end)

        return Base, Stroke
    end

    function ElementFuncs:AddButton(...)
        if self.Destroyed then return end

        local First, Second = ...
        local Info = {}

        if typeof(First) == "table" then
            Info = First
        else
            Info.Text = First or ""
            Info.Func = Second or function() end
        end
        Info = Validate(Info, {
            Text = "Button",
            Func = function() end,
            DoubleClick = false,
            Tooltip = nil,
            DisabledTooltip = nil,
            Risky = false,
            Disabled = false,
            Visible = true,
        })

        local Container = self.Container
        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 22),
            Parent = Container,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalFlex = Enum.UIFlexAlignment.Fill,
            Padding = UDim.new(0, 8),
            Parent = Holder,
        })

        local Base, Stroke = CreateButtonBase(Info, Holder)

        local Button = {
            Type = "Button",
            Text = Info.Text,
            Func = Info.Func,
            Disabled = Info.Disabled,
            Visible = Info.Visible,
            Risky = Info.Risky,
            Locked = false,
            Base = Base,
            Holder = Holder,
        }

        Base.MouseButton1Click:Connect(function()
            if Button.Disabled or Button.Locked then return end
            Sounds:PlayClick()

            if Info.DoubleClick then
                Button.Locked = true
                Base.Text = "Are you sure?"
                local clicked = false
                local conn
                conn = Base.MouseButton1Click:Connect(function()
                    clicked = true
                    if conn and conn.Connected then conn:Disconnect() end
                end)
                task.wait(0.5)
                if conn and conn.Connected then conn:Disconnect() end
                Base.Text = Info.Text
                if clicked then SafeCallback(Button.Func) end
                Button.Locked = false
                return
            end

            SafeCallback(Button.Func)
        end)

        function Button:SetText(t) Button.Text = t Base.Text = t end
        function Button:SetDisabled(d)
            Button.Disabled = d
            Base.Active = not d
            Base.BackgroundColor3 = d and Library.Scheme.BackgroundColor or Library.Scheme.MainColor
            Stroke.Transparency = d and 0.5 or 0
        end
        function Button:SetVisible(v)
            Button.Visible = v
            Holder.Visible = v
            if self.Resize then self:Resize() end
        end
        function Button:Destroy()
            Holder:Destroy()
        end

        -- sub-botão
        function Button:AddButton(...)
            local F, S = ...
            local SubInfo = typeof(F) == "table" and F or { Text = F, Func = S }
            SubInfo = Validate(SubInfo, {
                Text = "Sub",
                Func = function() end,
                DoubleClick = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })

            local SubBase, SubStroke = CreateButtonBase(SubInfo, Holder)
            local Sub = {
                Type = "SubButton",
                Text = SubInfo.Text,
                Func = SubInfo.Func,
                Disabled = SubInfo.Disabled,
                Visible = SubInfo.Visible,
                Base = SubBase,
            }
            SubBase.MouseButton1Click:Connect(function()
                if Sub.Disabled then return end
                Sounds:PlayClick()
                SafeCallback(Sub.Func)
            end)
            function Sub:SetText(t) Sub.Text = t SubBase.Text = t end
            function Sub:SetDisabled(d)
                Sub.Disabled = d
                SubBase.Active = not d
                SubBase.BackgroundColor3 = d and Library.Scheme.BackgroundColor or Library.Scheme.MainColor
                SubStroke.Transparency = d and 0.5 or 0
            end
            function Sub:SetVisible(v)
                Sub.Visible = v
                SubBase.Visible = v
            end
            function Sub:Destroy() SubBase:Destroy() end

            return Sub
        end

        if self._AddElement then self:_AddElement(Button) end
        table.insert(Library.Buttons, Button)
        return Button
    end

    --// ------------------------------------------------------------
    --// TOGGLE
    --// ------------------------------------------------------------
    local function BuildToggle(Info, Container)
        local Toggle = {
            Type = "Toggle",
            Connections = {},
            Text = Info.Text,
            Value = Info.Default,
            Callback = Info.Callback or function() end,
            Changed  = Info.Changed  or function() end,
            Disabled = Info.Disabled or false,
            Visible  = Info.Visible ~= false,
            Risky    = Info.Risky or false,
            Addons   = {},
            Variant  = Info.Variant or "Switch",
        }

        local Button = New("TextButton", {
            Active = not Toggle.Disabled,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 22),
            Text = "",
            Visible = Toggle.Visible,
            Parent = Container,
        })

        local Label = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -44, 1, 0),
            Text = Toggle.Text,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextTransparency = 0.4,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Button,
        })

        local Switch = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = "MainColor",
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(34, 18),
            Parent = Button,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Switch })
        New("UIPadding", {
            PaddingBottom = UDim.new(0, 2),
            PaddingLeft   = UDim.new(0, 2),
            PaddingRight  = UDim.new(0, 2),
            PaddingTop    = UDim.new(0, 2),
            Parent = Switch,
        })
        local SwitchStroke = New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Switch,
        })
        local Ball = New("Frame", {
            BackgroundColor3 = "FontColor",
            Size = UDim2.fromScale(1, 1),
            SizeConstraint = Enum.SizeConstraint.RelativeYY,
            Parent = Switch,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Ball })

        RegisterColor(Switch, { BackgroundColor3 = "MainColor" })
        RegisterColor(SwitchStroke, { Color = "OutlineColor" })
        RegisterColor(Ball, { BackgroundColor3 = "FontColor" })

        function Toggle:Display()
            if Library.Unloaded then return end

            local Offset = Toggle.Value and 1 or 0
            Switch.BackgroundTransparency = Toggle.Disabled and 0.75 or 0
            SwitchStroke.Transparency      = Toggle.Disabled and 0.75 or 0

            Switch.BackgroundColor3 = Toggle.Value and Library.Scheme.AccentColor or Library.Scheme.MainColor
            SwitchStroke.Color      = Toggle.Value and Library.Scheme.AccentColor or Library.Scheme.OutlineColor

            Library.Registry[Switch].BackgroundColor3       = Toggle.Value and "AccentColor" or "MainColor"
            Library.Registry[SwitchStroke].Color            = Toggle.Value and "AccentColor" or "OutlineColor"

            if Toggle.Disabled then
                Label.TextTransparency = 0.8
                Ball.AnchorPoint = Vector2.new(Offset, 0)
                Ball.Position = UDim2.fromScale(Offset, 0)
                return
            end

            TweenService:Create(Label, Library.TweenInfo, {
                TextTransparency = Toggle.Value and 0 or 0.4,
            }):Play()
            TweenService:Create(Ball, Library.TweenInfo, {
                AnchorPoint = Vector2.new(Offset, 0),
                Position    = UDim2.fromScale(Offset, 0),
            }):Play()
        end

        function Toggle:RunChanged()
            SafeCallback(Toggle.Callback, Toggle.Value)
            SafeCallback(Toggle.Changed,  Toggle.Value)
        end

        function Toggle:SetValue(v)
            if Toggle.Disabled then return end
            Toggle.Value = v
            Toggle:Display()
            for _, addon in ipairs(Toggle.Addons) do
                if addon.Type == "KeyPicker" and addon.SyncToggleState then
                    addon.Toggled = Toggle.Value
                    addon:Update()
                end
            end
            Toggle:RunChanged()
        end

        function Toggle:SetDisabled(d)
            Toggle.Disabled = d
            Button.Active = not d
            Toggle:Display()
        end
        function Toggle:SetVisible(v)
            Toggle.Visible = v
            Button.Visible = v
        end
        function Toggle:SetText(t)
            Toggle.Text = t
            Label.Text = t
        end
        function Toggle:OnChanged(f) Toggle.Changed = f end

        Button.MouseButton1Click:Connect(function()
            if Toggle.Disabled then return end
            Sounds:PlayClick()
            Toggle:SetValue(not Toggle.Value)
        end)

        function Toggle:Destroy()
            Toggle.Destroyed = true
            Button:Destroy()
        end

        Toggle.Base = Button
        Toggle.TextLabel = Label
        Toggle:Display()

        return Toggle
    end

    function ElementFuncs:AddToggle(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Text = "Toggle",
            Default = false,
            Callback = function() end,
            Changed  = function() end,
            Risky = false,
            Disabled = false,
            Visible = true,
            Variant = "Switch",
        })

        local Toggle = BuildToggle(Info, self.Container)
        Toggle.Default = Toggle.Value

        if Info.Tooltip or Info.DisabledTooltip then
            Toggle.TooltipTable = Library:AddTooltip(Info.Tooltip, Info.DisabledTooltip, Toggle.Base)
            Toggle.TooltipTable.Disabled = Info.Disabled
        end
        if Info.Risky then
            Toggle.TextLabel.TextColor3 = Library.Scheme.RedColor
            RegisterColor(Toggle.TextLabel, { TextColor3 = "RedColor" })
        end

        if self._AddElement then self:_AddElement(Toggle) end
        Library.Toggles[Idx] = Toggle
        Library.Options[Idx] = Toggle

        return Toggle
    end

    function ElementFuncs:AddCheckbox(Idx, Info)
        Info = Validate(Info or {}, { Text = "Checkbox", Default = false, Callback = function() end, Changed = function() end })
        local Toggle = BuildToggle({ Text = Info.Text, Default = Info.Default, Callback = Info.Callback, Changed = Info.Changed, Variant = "Checkbox" }, self.Container)

        -- esconde switch, mostra checkbox
        local switch = Toggle.Base:FindFirstChildOfClass("Frame")
        if switch then switch.Visible = false end

        local Checkbox = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = "MainColor",
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            Parent = Toggle.Base,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Checkbox,
        }))
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Checkbox,
        })
        local Check = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "✓",
            TextSize = 14,
            TextColor3 = "FontColor",
            TextTransparency = 1,
            Parent = Checkbox,
        })

        local oldDisplay = Toggle.Display
        function Toggle:Display()
            oldDisplay(self)
            Check.TextTransparency = self.Value and 0 or 1
        end
        Toggle:Display()

        if self._AddElement then self:_AddElement(Toggle) end
        Library.Toggles[Idx] = Toggle
        Library.Options[Idx] = Toggle
        return Toggle
    end

    --// ------------------------------------------------------------
    --// SLIDER
    --// ------------------------------------------------------------
    function ElementFuncs:AddSlider(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Text = "Slider",
            Default = 0,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Prefix = "",
            Suffix = "",
            Callback = function() end,
            Changed  = function() end,
            Disabled = false,
            Visible = true,
            Compact = false,
            HideMax = false,
            AllowRightClickInput = true,
        })

        local Container = self.Container
        local Slider = {
            Type = "Slider",
            Connections = {},
            Text = Info.Text,
            Value = Info.Default,
            Min = Info.Min,
            Max = Info.Max,
            Rounding = Info.Rounding,
            Prefix = Info.Prefix,
            Suffix = Info.Suffix,
            Callback = Info.Callback,
            Changed  = Info.Changed,
            Disabled = Info.Disabled,
            Visible = Info.Visible,
            Compact = Info.Compact,
            HideMax = Info.HideMax,
        }

        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, Info.Compact and 16 or 36),
            Visible = Info.Visible,
            Parent = Container,
        })

        local SliderLabel
        if not Info.Compact then
            SliderLabel = New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 16),
                Text = Info.Text,
                TextSize = 14,
                TextColor3 = "FontColor",
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = Holder,
            })
        end

        local Bar = New("TextButton", {
            AnchorPoint = Vector2.new(0, 1),
            Active = not Info.Disabled,
            BackgroundColor3 = "MainColor",
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 16),
            Text = "",
            Parent = Holder,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Bar,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Bar,
        }))

        local Fill = New("Frame", {
            BackgroundColor3 = "AccentColor",
            Size = UDim2.fromScale(0, 1),
            ZIndex = 1,
            Parent = Bar,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Fill,
        }))
        RegisterColor(Fill, { BackgroundColor3 = "AccentColor" })

        local DisplayLabel = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            TextSize = 13,
            TextColor3 = "FontColor",
            ZIndex = 2,
            Parent = Bar,
        })

        function Slider:Display()
            if Library.Unloaded then return end

            if Info.Compact then
                DisplayLabel.Text = string.format("%s: %s%s%s", Slider.Text, Slider.Prefix, Slider.Value, Slider.Suffix)
            elseif Slider.HideMax then
                DisplayLabel.Text = string.format("%s%s%s", Slider.Prefix, Slider.Value, Slider.Suffix)
            else
                DisplayLabel.Text = string.format("%s%s%s / %s%s%s",
                    Slider.Prefix, Slider.Value, Slider.Suffix,
                    Slider.Prefix, Slider.Max, Slider.Suffix)
            end

            local X = (Slider.Value - Slider.Min) / (Slider.Max - Slider.Min)
            Fill.Size = UDim2.fromScale(X, 1)
        end

        function Slider:RunChanged()
            SafeCallback(Slider.Callback, Slider.Value)
            SafeCallback(Slider.Changed,  Slider.Value)
        end

        function Slider:SetValue(num)
            if Slider.Disabled then return end
            num = tonumber(num)
            if not num then return end
            num = math.clamp(num, Slider.Min, Slider.Max)
            num = Library:Round(num, Slider.Rounding)
            Slider.Value = num
            Slider:Display()
            Slider:RunChanged()
        end

        function Slider:SetMin(v) Slider.Min = v Slider:Display() end
        function Slider:SetMax(v) Slider.Max = v Slider:Display() end
        function Slider:SetText(t) Slider.Text = t if SliderLabel then SliderLabel.Text = t end Slider:Display() end
        function Slider:SetDisabled(d)
            Slider.Disabled = d
            Bar.Active = not d
            DisplayLabel.TextTransparency = d and 0.5 or 0
        end
        function Slider:SetVisible(v)
            Slider.Visible = v
            Holder.Visible = v
        end
        function Slider:OnChanged(f) Slider.Changed = f end

        Bar.InputBegan:Connect(function(Input)
            if not IsClickInput(Input) or Slider.Disabled then return end
            Sounds:PlayClick()

            while IsDragInput(Input) and not Slider.Destroyed do
                local loc = Mouse.X
                local scale = math.clamp((loc - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
                local val = Library:Round(Slider.Min + (Slider.Max - Slider.Min) * scale, Slider.Rounding)
                if val ~= Slider.Value then
                    Slider.Value = val
                    Slider:Display()
                    Slider:RunChanged()
                end
                RunService.RenderStepped:Wait()
            end
        end)

        function Slider:Destroy()
            Slider.Destroyed = true
            Holder:Destroy()
        end

        Slider:Display()

        if self._AddElement then self:_AddElement(Slider) end
        Library.Options[Idx] = Slider
        return Slider
    end

    --// ------------------------------------------------------------
    --// INPUT
    --// ------------------------------------------------------------
    function ElementFuncs:AddInput(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Text = "Input",
            Default = "",
            Finished = false,
            Numeric = false,
            ClearTextOnFocus = true,
            ClearTextOnBlur = false,
            Placeholder = "",
            AllowEmpty = true,
            EmptyReset = "---",
            Callback = function() end,
            Changed  = function() end,
            VerifyValue = nil,
            Disabled = false,
            Visible = true,
        })

        local Container = self.Container
        local Input = {
            Type = "Input",
            Text = Info.Text,
            Value = Info.Default,
            Callback = Info.Callback,
            Changed  = Info.Changed,
            Disabled = Info.Disabled,
            Visible = Info.Visible,
            Connections = {},
        }

        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 42),
            Visible = Info.Visible,
            Parent = Container,
        })

        local Lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Text = Info.Text,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Holder,
        })

        local Box = New("TextBox", {
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = "MainColor",
            ClearTextOnFocus = Info.ClearTextOnFocus,
            PlaceholderText = Info.Placeholder,
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 24),
            Text = Info.Default,
            TextEditable = not Info.Disabled,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Holder,
        })
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
            Parent = Box,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Box,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Box,
        }))

        local BoxStroke = Box:FindFirstChildOfClass("UIStroke")

        Box.Focused:Connect(function()
            Sounds:BeginTyping()
            if BoxStroke then
                Library.Registry[BoxStroke] = Library.Registry[BoxStroke] or {}
                TweenService:Create(BoxStroke, Library.TweenInfo, {
                    Color = Library.Scheme.AccentColor,
                }):Play()
            end
        end)
        Box.FocusLost:Connect(function()
            Sounds:StopTyping()
            if BoxStroke then
                TweenService:Create(BoxStroke, Library.TweenInfo, {
                    Color = Library.Scheme.OutlineColor,
                }):Play()
            end
            if Info.ClearTextOnBlur then
                Box.Text = Input.Value
            end
        end)

        function Input:RunChanged()
            SafeCallback(Input.Callback, Input.Value)
            SafeCallback(Input.Changed,  Input.Value)
        end

        function Input:SetValue(text)
            text = tostring(text or "")
            if not Info.AllowEmpty and Library:Trim(text) == "" then
                text = Info.EmptyReset
            end
            if Info.Numeric and text ~= "" and not tonumber(text) then
                text = Input.Value
            end
            if typeof(Info.VerifyValue) == "function" and text ~= Info.EmptyReset and Info.VerifyValue(text) ~= true then
                text = Info.EmptyReset
            end

            Input.Value = text
            Box.Text = text
            if not Input.Disabled then Input:RunChanged() end
        end

        function Input:SetDisabled(d)
            Input.Disabled = d
            Box.TextEditable = not d
            Lbl.TextTransparency = d and 0.5 or 0
            Box.TextTransparency = d and 0.5 or 0
        end
        function Input:SetVisible(v)
            Input.Visible = v
            Holder.Visible = v
        end
        function Input:SetText(t)
            Input.Text = t
            Lbl.Text = t
        end
        function Input:OnChanged(f) Input.Changed = f end

        if Info.Finished then
            Box.FocusLost:Connect(function(enter)
                if enter then Input:SetValue(Box.Text) end
            end)
        else
            Box:GetPropertyChangedSignal("Text"):Connect(function()
                if Box.Text ~= Input.Value then Input:SetValue(Box.Text) end
            end)
        end

        function Input:Destroy()
            Input.Destroyed = true
            Holder:Destroy()
        end

        if self._AddElement then self:_AddElement(Input) end
        Library.Options[Idx] = Input
        return Input
    end

    --// ------------------------------------------------------------
    --// DROPDOWN
    --// ------------------------------------------------------------
    function ElementFuncs:AddDropdown(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Text = "Dropdown",
            Values = {},
            DisabledValues = {},
            Multi = false,
            AllowNull = true,
            Searchable = false,
            MaxVisibleDropdownItems = 8,
            FormatDisplayValue = nil,
            FormatListValue = nil,
            Callback = function() end,
            Changed  = function() end,
            Disabled = false,
            Visible = true,
        })

        local Container = self.Container
        local Dropdown = {
            Type = "Dropdown",
            Text = Info.Text,
            Values = Info.Values,
            DisabledValues = Info.DisabledValues,
            Multi = Info.Multi,
            Value = Info.Multi and {} or nil,
            Callback = Info.Callback,
            Changed  = Info.Changed,
            Disabled = Info.Disabled,
            Visible = Info.Visible,
            Connections = {},
            SearchText = "",
        }

        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, Info.Text and 42 or 24),
            Visible = Info.Visible,
            Parent = Container,
        })

        local Lbl
        if Info.Text then
            Lbl = New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 16),
                Text = Info.Text,
                TextSize = 14,
                TextColor3 = "FontColor",
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = Holder,
            })
        end

        local DisplayBtn = New("TextButton", {
            AnchorPoint = Vector2.new(0, 1),
            Active = not Info.Disabled,
            BackgroundColor3 = "MainColor",
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 24),
            Text = "---",
            TextSize = 14,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Holder,
        })
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 24),
            Parent = DisplayBtn,
        })
        local DisplayStroke = New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = DisplayBtn,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = DisplayBtn,
        }))

        local Arrow = New("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -6, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            Text = "▾",
            TextSize = 16,
            TextColor3 = "FontColor",
            TextTransparency = 0.5,
            Parent = DisplayBtn,
        })

        -- menu de opções
        local Menu = New("ScrollingFrame", {
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = "BackgroundColor",
            CanvasSize = UDim2.fromScale(0, 0),
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = "OutlineColor",
            Size = UDim2.new(1, 0, 0, 0),
            Visible = false,
            ZIndex = 50,
            Parent = Library.Overlay,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Menu,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Menu,
        }))
        local MenuList = New("UIListLayout", { Parent = Menu })

        local function RecomputeList()
            local query = string.lower(Dropdown.SearchText or "")
            local list = {}

            if IsSequentialArray(Dropdown.Values) then
                for _, v in ipairs(Dropdown.Values) do
                    local s = tostring(v)
                    if query == "" or string.find(string.lower(s), query, 1, true) then
                        table.insert(list, { Value = v, Text = s })
                    end
                end
            else
                for k, v in pairs(Dropdown.Values) do
                    local s = tostring(v)
                    if query == "" or string.find(string.lower(s), query, 1, true) or string.find(string.lower(tostring(k)), query, 1, true) then
                        table.insert(list, { Value = k, Text = s })
                    end
                end
            end

            return list
        end

        local function RefreshDisplay()
            local str
            if Dropdown.Multi then
                local parts = {}
                for v in pairs(Dropdown.Value) do table.insert(parts, tostring(v)) end
                str = #parts > 0 and table.concat(parts, ", ") or ""
            else
                str = Dropdown.Value and tostring(Dropdown.Value) or ""
            end
            if Info.FormatDisplayValue then str = tostring(Info.FormatDisplayValue(str)) end
            if #str > 28 then str = str:sub(1, 25) .. "..." end
            DisplayBtn.Text = str == "" and "---" or str
        end

        local function Rebuild()
            for _, c in ipairs(Menu:GetChildren()) do
                if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
            end

            local list = RecomputeList()
            local maxH = Info.MaxVisibleDropdownItems * 24
            local totalH = #list * 24
            local h = math.min(maxH, totalH)

            for _, entry in ipairs(list) do
                local disabled = false
                for _, dv in ipairs(Dropdown.DisabledValues) do
                    if dv == entry.Value then disabled = true break end
                end

                local Item = New("TextButton", {
                    Active = not disabled,
                    BackgroundColor3 = "MainColor",
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 24),
                    Text = Info.FormatListValue and tostring(Info.FormatListValue(entry.Value)) or entry.Text,
                    TextSize = 13,
                    TextColor3 = "FontColor",
                    TextTransparency = disabled and 0.8 or 0.4,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Menu,
                })
                New("UIPadding", {
                    PaddingLeft = UDim.new(0, 10),
                    PaddingRight = UDim.new(0, 10),
                    Parent = Item,
                })

                local selected = Dropdown.Multi and Dropdown.Value[entry.Value] or Dropdown.Value == entry.Value
                if selected then
                    Item.BackgroundTransparency = 0
                    Item.TextTransparency = 0
                end

                Item.MouseEnter:Connect(function()
                    if disabled then return end
                    TweenService:Create(Item, Library.TweenInfo, { BackgroundTransparency = 0.8, TextTransparency = 0.2 }):Play()
                end)
                Item.MouseLeave:Connect(function()
                    if disabled then return end
                    local sel = Dropdown.Multi and Dropdown.Value[entry.Value] or Dropdown.Value == entry.Value
                    TweenService:Create(Item, Library.TweenInfo, {
                        BackgroundTransparency = sel and 0 or 1,
                        TextTransparency = sel and 0 or 0.4,
                    }):Play()
                end)

                Item.MouseButton1Click:Connect(function()
                    if disabled or Dropdown.Disabled then return end
                    Sounds:PlayClick()

                    if Dropdown.Multi then
                        Dropdown.Value[entry.Value] = not Dropdown.Value[entry.Value] or nil
                    else
                        Dropdown.Value = entry.Value
                    end
                    RefreshDisplay()
                    Rebuild()
                    SafeCallback(Dropdown.Callback, Dropdown.Value)
                    SafeCallback(Dropdown.Changed,  Dropdown.Value)
                end)
            end

            Menu.CanvasSize = UDim2.fromOffset(0, totalH)
            Menu.Size = UDim2.new(1, 0, 0, h)
        end

        function Dropdown:SetValue(v) Dropdown.Value = v RefreshDisplay() SafeCallback(Dropdown.Changed, v) end
        function Dropdown:SetValues(v) Dropdown.Values = v Rebuild() end
        function Dropdown:SetDisabled(d)
            Dropdown.Disabled = d
            DisplayBtn.Active = not d
            DisplayBtn.TextTransparency = d and 0.5 or 0
        end
        function Dropdown:SetVisible(v)
            Dropdown.Visible = v
            Holder.Visible = v
        end
        function Dropdown:SetText(t)
            Dropdown.Text = t
            if Lbl then Lbl.Text = t end
        end
        function Dropdown:OnChanged(f) Dropdown.Changed = f end

        local menuOpen = false
        local function ToggleMenu()
            if Dropdown.Disabled then return end
            Sounds:PlayClick()
            menuOpen = not menuOpen
            if menuOpen then
                Rebuild()
                Menu.Position = UDim2.fromOffset(
                    DisplayBtn.AbsolutePosition.X,
                    DisplayBtn.AbsolutePosition.Y + DisplayBtn.AbsoluteSize.Y + 2
                )
                Menu.Size = UDim2.new(0, DisplayBtn.AbsoluteSize.X, 0, math.min(Info.MaxVisibleDropdownItems * 24, #RecomputeList() * 24))
                Menu.Visible = true
                Arrow.Rotation = 180
            else
                Menu.Visible = false
                Arrow.Rotation = 0
            end
        end

        DisplayBtn.MouseButton1Click:Connect(ToggleMenu)

        GiveSignal(UserInputService.InputBegan:Connect(function(Input)
            if not menuOpen then return end
            if not IsClickInput(Input, true) then return end
            if Library:MouseIsOverFrame(Menu, Input.Position) then return end
            if Library:MouseIsOverFrame(DisplayBtn, Input.Position) then return end
            menuOpen = false
            Menu.Visible = false
            Arrow.Rotation = 0
        end))

        function Dropdown:Destroy()
            Dropdown.Destroyed = true
            Menu:Destroy()
            Holder:Destroy()
        end

        RefreshDisplay()

        if self._AddElement then self:_AddElement(Dropdown) end
        Library.Options[Idx] = Dropdown
        return Dropdown
    end

    --// ------------------------------------------------------------
    --// KEYPICKER
    --// ------------------------------------------------------------
    function ElementFuncs:AddKeyPicker(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Text = "KeyPicker",
            Default = "None",
            Mode = "Toggle",
            Modes = { "Always", "Toggle", "Hold" },
            SyncToggleState = false,
            Callback = function() end,
            Changed  = function() end,
            Clicked  = function() end,
        })

        local KeyPicker = {
            Type = "KeyPicker",
            Text = Info.Text,
            Value = Info.Default,
            Mode = Info.Mode,
            Modes = Info.Modes,
            SyncToggleState = Info.SyncToggleState,
            Toggled = false,
            Callback = Info.Callback,
            Changed  = Info.Changed,
            Clicked  = Info.Clicked,
            Connections = {},
        }

        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 42),
            Parent = self.Container,
        })

        local Lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Text = Info.Text,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Holder,
        })

        local Picker = New("TextButton", {
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = "MainColor",
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 24),
            Text = Info.Default,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextTransparency = 0.4,
            Parent = Holder,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Picker,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Picker,
        }))

        local picking = false
        Picker.MouseButton1Click:Connect(function()
            if picking then return end
            picking = true
            Picker.Text = "..."
            Sounds:PlayClick()

            local Input = UserInputService.InputBegan:Wait()
            if Input.UserInputType == Enum.UserInputType.Keyboard then
                KeyPicker.Value = Input.KeyCode == Enum.KeyCode.Escape and "None" or Input.KeyCode.Name
            elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                KeyPicker.Value = "MB1"
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                KeyPicker.Value = "MB2"
            else
                KeyPicker.Value = "Unknown"
            end

            Picker.Text = KeyPicker.Value
            picking = false
            SafeCallback(KeyPicker.Changed, KeyPicker.Value)
        end)

        function KeyPicker:GetState()
            if KeyPicker.Mode == "Always" then return true end
            if KeyPicker.Mode == "Hold" then
                local key = KeyPicker.Value
                if key == "None" or key == "Unknown" then return false end
                if key == "MB1" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
                if key == "MB2" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
                return UserInputService:IsKeyDown(Enum.KeyCode[key] or Enum.KeyCode.Unknown)
            end
            return KeyPicker.Toggled
        end

        function KeyPicker:SetValue(v) KeyPicker.Value = v Picker.Text = v SafeCallback(KeyPicker.Changed, v) end
        function KeyPicker:SetText(t) KeyPicker.Text = t Lbl.Text = t end

        function KeyPicker:Destroy()
            KeyPicker.Destroyed = true
            Holder:Destroy()
        end

        GiveSignal(UserInputService.InputBegan:Connect(function(Input)
            if Library.Unloaded or KeyPicker.Destroyed then return end
            if UserInputService:GetFocusedTextBox() then return end
            if Library.Toggled then return end

            local key = KeyPicker.Value
            if KeyPicker.Mode == "Toggle" then
                local pressed =
                    (Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == key)
                    or (key == "MB1" and Input.UserInputType == Enum.UserInputType.MouseButton1)
                    or (key == "MB2" and Input.UserInputType == Enum.UserInputType.MouseButton2)
                if pressed then
                    KeyPicker.Toggled = not KeyPicker.Toggled
                    SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
                    SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
                end
            elseif KeyPicker.Mode == "Press" then
                local pressed =
                    (Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == key)
                    or (key == "MB1" and Input.UserInputType == Enum.UserInputType.MouseButton1)
                    or (key == "MB2" and Input.UserInputType == Enum.UserInputType.MouseButton2)
                if pressed then
                    SafeCallback(KeyPicker.Callback, true)
                    SafeCallback(KeyPicker.Clicked, true)
                end
            end
        end))

        if self._AddElement then self:_AddElement(KeyPicker) end
        Library.Options[Idx] = KeyPicker
        return KeyPicker
    end

    --// ------------------------------------------------------------
    --// COLOR PICKER
    --// ------------------------------------------------------------
    function ElementFuncs:AddColorPicker(Idx, Info)
        if self.Destroyed then return end
        Info = Validate(Info or {}, {
            Default = Color3.fromRGB(255, 255, 255),
            Transparency = 0,
            Callback = function() end,
            Changed  = function() end,
        })

        local ColorPicker = {
            Type = "ColorPicker",
            Value = Info.Default,
            Transparency = Info.Transparency,
            Callback = Info.Callback,
            Changed  = Info.Changed,
            Connections = {},
        }

        local Holder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 24),
            Parent = self.Container,
        })

        local Box = New("TextButton", {
            BackgroundColor3 = ColorPicker.Value,
            Size = UDim2.fromOffset(24, 24),
            Text = "",
            Parent = Holder,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Box,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius / 2),
            Parent = Box,
        }))

        local ColorMenu = New("Frame", {
            BackgroundColor3 = "BackgroundColor",
            Size = UDim2.fromOffset(230, 190),
            Visible = false,
            ZIndex = 50,
            Parent = Library.Overlay,
        })
        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = ColorMenu,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = ColorMenu,
        }))

        -- sat/vib gradient + hue slider (versão simplificada)
        local SV = New("ImageButton", {
            BackgroundColor3 = ColorPicker.Value,
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(150, 120),
            Image = "rbxassetid://4155801252",
            Parent = ColorMenu,
        })
        local Cursor = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = "WhiteColor",
            Size = UDim2.fromOffset(8, 8),
            Parent = SV,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Cursor })

        local Hue = New("TextButton", {
            Position = UDim2.fromOffset(166, 8),
            Size = UDim2.fromOffset(20, 120),
            Text = "",
            Parent = ColorMenu,
        })
        New("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
                ColorSequenceKeypoint.new(1/6, Color3.fromRGB(255, 255, 0)),
                ColorSequenceKeypoint.new(2/6, Color3.fromRGB(0, 255, 0)),
                ColorSequenceKeypoint.new(3/6, Color3.fromRGB(0, 255, 255)),
                ColorSequenceKeypoint.new(4/6, Color3.fromRGB(0, 0, 255)),
                ColorSequenceKeypoint.new(5/6, Color3.fromRGB(255, 0, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
            }),
            Rotation = 90,
            Parent = Hue,
        })
        local HueCursor = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = "WhiteColor",
            Size = UDim2.new(1, 4, 0, 2),
            Position = UDim2.new(0.5, 0, 0, 0),
            Parent = Hue,
        })

        local Info = New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(8, 138),
            Size = UDim2.new(1, -16, 0, 20),
            Text = "",
            TextSize = 13,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = ColorMenu,
        })

        local function Refresh()
            Box.BackgroundColor3 = ColorPicker.Value
            local h, s, v = ColorPicker.Value:ToHSV()
            SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            Cursor.Position = UDim2.fromScale(s, 1 - v)
            HueCursor.Position = UDim2.new(0.5, 0, h, 0)
            Info.Text = string.format("#%s", ColorPicker.Value:ToHex())
        end
        Refresh()

        local function UpdateValue(color)
            ColorPicker.Value = color
            Refresh()
            SafeCallback(ColorPicker.Callback, color)
            SafeCallback(ColorPicker.Changed, color)
        end

        SV.InputBegan:Connect(function(Input)
            if not IsClickInput(Input) then return end
            while IsDragInput(Input) and not ColorPicker.Destroyed do
                local minX, maxX = SV.AbsolutePosition.X, SV.AbsolutePosition.X + SV.AbsoluteSize.X
                local minY, maxY = SV.AbsolutePosition.Y, SV.AbsolutePosition.Y + SV.AbsoluteSize.Y
                local x = math.clamp(Mouse.X, minX, maxX)
                local y = math.clamp(Mouse.Y, minY, maxY)
                local h = ColorPicker.Value:ToHSV()
                UpdateValue(Color3.fromHSV(h, (x - minX) / (maxX - minX), 1 - (y - minY) / (maxY - minY)))
                RunService.RenderStepped:Wait()
            end
        end)

        Hue.InputBegan:Connect(function(Input)
            if not IsClickInput(Input) then return end
            while IsDragInput(Input) and not ColorPicker.Destroyed do
                local minY, maxY = Hue.AbsolutePosition.Y, Hue.AbsolutePosition.Y + Hue.AbsoluteSize.Y
                local y = math.clamp(Mouse.Y, minY, maxY)
                local _, s, v = ColorPicker.Value:ToHSV()
                UpdateValue(Color3.fromHSV((y - minY) / (maxY - minY), s, v))
                RunService.RenderStepped:Wait()
            end
        end)

        local menuOpen = false
        Box.MouseButton1Click:Connect(function()
            Sounds:PlayClick()
            menuOpen = not menuOpen
            if menuOpen then
                ColorMenu.Position = UDim2.fromOffset(
                    Box.AbsolutePosition.X + 30,
                    Box.AbsolutePosition.Y
                )
                ColorMenu.Visible = true
            else
                ColorMenu.Visible = false
            end
        end)

        function ColorPicker:SetValueRGB(c, t)
            ColorPicker.Transparency = t or ColorPicker.Transparency
            UpdateValue(c)
        end
        function ColorPicker:Destroy()
            ColorPicker.Destroyed = true
            ColorMenu:Destroy()
            Holder:Destroy()
        end

        if self._AddElement then self:_AddElement(ColorPicker) end
        Library.Options[Idx] = ColorPicker
        return ColorPicker
    end

    --================================================================
    --  DEPENDENCY BOX
    --================================================================
    function ElementFuncs:AddDependencyBox()
        local Container = self.Container
        local DepHolder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            Parent = Container,
        })
        local DepList = New("UIListLayout", {
            Padding = UDim.new(0, 8),
            Parent = DepHolder,
        })

        local Depbox = {
            Type = "DependencyBox",
            Container = DepHolder,
            Elements = {},
            Dependencies = {},
            Visible = false,
            Destroyed = false,
        }

        function Depbox:Resize()
            DepHolder.Size = UDim2.new(1, 0, 0, DepList.AbsoluteContentSize.Y / Library.DPIScale)
            if self.Groupbox and self.Groupbox.Resize then self.Groupbox:Resize() end
        end

        function Depbox:SetupDependencies(deps)
            Depbox.Dependencies = deps
            Depbox:Update()
        end

        function Depbox:Update()
            for _, dep in ipairs(Depbox.Dependencies) do
                local el, expected = dep[1], dep[2]
                if el.Type == "Toggle" and el.Value ~= expected then
                    DepHolder.Visible = false
                    Depbox.Visible = false
                    return
                elseif el.Type == "Dropdown" then
                    if typeof(el.Value) == "table" then
                        if not el.Value[expected] then
                            DepHolder.Visible = false
                            Depbox.Visible = false
                            return
                        end
                    elseif el.Value ~= expected then
                        DepHolder.Visible = false
                        Depbox.Visible = false
                        return
                    end
                end
            end
            Depbox.Visible = true
            DepHolder.Visible = true
            Depbox:Resize()
        end

        DepList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            if Depbox.Visible then Depbox:Resize() end
        end)

        function Depbox:Destroy()
            Depbox.Destroyed = true
            DepHolder:Destroy()
        end

        setmetatable(Depbox, { __index = ElementFuncs })
        return Depbox
    end

    --================================================================
    --  PENDU RA métodos em Groupbox / SubTab
    --================================================================
    function Library:AttachElementFuncs(obj)
        if not obj then return obj end
        for k, v in pairs(ElementFuncs) do
            if obj[k] == nil then
                obj[k] = v
            end
        end
        return obj
    end

    -- Substitui o Groupbox:AddElement pra registrar automaticamente
    function Library:_HookGroupbox(Groupbox)
        if not Groupbox then return end
        Groupbox.Groupbox = Groupbox
        for k, v in pairs(ElementFuncs) do
            if Groupbox[k] == nil then
                Groupbox[k] = v
            end
        end
    end

    return Library
end