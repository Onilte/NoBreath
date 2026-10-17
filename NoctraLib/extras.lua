--[[
    NoctraLib :: extras.lua
    ----------------------------------------------------------------
    Complementos visuais e funcionais:
      • Notification (success / error / info) com som
      • Dialog modal com botões footer
      • DraggableLabel / DraggableButton / DraggableMenu (card flutuante)
      • Search global — filtra elementos por fuzzy match
      • ContextMenu (usado por dropdown/keypicker)
      • Watermark (deprecated, mas suportado)

    Retorna uma função Attach(Library) que devolve Library.
]]

return function(Library)

    local cloneref = (cloneref or clonereference or function(x) return x end)
    local Players        = cloneref(game:GetService("Players"))
    local RunService     = cloneref(game:GetService("RunService"))
    local UserInputService = cloneref(game:GetService("UserInputService"))
    local TweenService   = cloneref(game:GetService("TweenService"))
    local SoundService   = cloneref(game:GetService("SoundService"))
    local TextService    = cloneref(game:GetService("TextService"))
    local LocalPlayer    = Library.LocalPlayer
    local Mouse          = cloneref(LocalPlayer:GetMouse())

    local Sounds = Library.Sounds
    local New    = function(...) return Library:New(...) end
    local function GiveSignal(c) return Library:GiveSignal(c) end
    local function SafeCallback(f, ...) return Library:SafeCallback(f, ...) end

    local ScreenGui = Library.ScreenGui
    local Floats    = Library.Floats
    local Overlay   = Library.Overlay

    Library.Notifications = Library.Notifications or {}
    Library.Dialogues     = Library.Dialogues     or {}
    Library.ContextMenus  = Library.ContextMenus  or {}

    --================================================================
    --  HELPERS
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

    local function Trim(s) return Library:Trim(s) end
    local function GetTableSize(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    --================================================================
    --  NOTIFICATION AREA (referência ao que window criou)
    --================================================================
    local NotificationArea = nil
    do
        for _, child in ipairs(ScreenGui:GetChildren()) do
            if child:IsA("Frame") and child:FindFirstChildOfClass("UIScale") and child.ZIndex == 200 then
                NotificationArea = child
                break
            end
        end

        if not NotificationArea then
            -- fallback: cria novamente se window não criou
            NotificationArea = New("Frame", {
                AnchorPoint = Vector2.new(1, 0),
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -8, 0, 8),
                Size = UDim2.new(0, 320, 1, -8),
                ZIndex = 200,
                Parent = ScreenGui,
            })
            table.insert(Library.Scales, New("UIScale", { Parent = NotificationArea }))
        end
    end

    local NotifyOrder = {}

    function Library:SetNotifySide(side)
        Library.NotifySide = side or "Right"
        local isLeft = string.lower(Library.NotifySide) == "left"
        if isLeft then
            NotificationArea.AnchorPoint = Vector2.new(0, 0)
            NotificationArea.Position = UDim2.fromOffset(8, 8)
        else
            NotificationArea.AnchorPoint = Vector2.new(1, 0)
            NotificationArea.Position = UDim2.new(1, -8, 0, 8)
        end
        for _, fb in ipairs(NotifyOrder) do
            if fb.Parent then
                fb.AnchorPoint = isLeft and Vector2.new(0, 0) or Vector2.new(1, 0)
            end
        end
        Library:UpdateNotificationPositions(true)
    end

    function Library:UpdateNotificationPositions(snap)
        local isLeft = string.lower(Library.NotifySide) == "left"
        local XScale = isLeft and 0 or 1
        local runningY = 0

        for _, fake in ipairs(NotifyOrder) do
            if not fake.Parent then continue end
            local target = UDim2.new(XScale, 0, 0, runningY)

            if snap then
                fake.Position = target
            else
                TweenService:Create(fake, Library.NotifyTweenInfo, { Position = target }):Play()
            end

            runningY = runningY + fake.AbsoluteSize.Y + 8
        end
    end

    --// Notify principal
    function Library:Notify(...)
        local data = {}
        local first = select(1, ...)

        if typeof(first) == "table" then
            data.Title        = first.Title
            data.TitleColor   = first.TitleColor
            data.Description  = first.Description
            data.DescriptionColor = first.DescriptionColor
            data.Time         = first.Time or 5
            data.Icon         = first.Icon
            data.IconColor    = first.IconColor
            data.Type         = first.Type or "Info"    -- "Success" | "Error" | "Info"
            data.Persist      = first.Persist
            data.SoundId      = first.SoundId
        else
            data.Description = tostring(first)
            data.Time = select(2, ...) or 5
            data.Type = "Info"
        end

        -- tom do som automático conforme tipo
        if data.Type == "Success" and not data.SoundId then
            Sounds:PlaySuccess()
        elseif data.Type == "Error" and not data.SoundId then
            Sounds:PlayError()
        elseif data.SoundId then
            Sounds:Play(data.SoundId)
        end

        local Fake = New("Frame", {
            AnchorPoint = string.lower(Library.NotifySide) == "left" and Vector2.new(0, 0) or Vector2.new(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 0),
            Visible = false,
            Parent = NotificationArea,
        })

        local Holder = New("Frame", {
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = "MainColor",
            Position = string.lower(Library.NotifySide) == "left"
                and UDim2.new(-1, -10, 0, -2)
                or  UDim2.new(1, 10, 0, -2),
            Size = UDim2.fromScale(1, 1),
            ZIndex = 5,
            Parent = Fake,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Holder,
        }))
        New("UIListLayout", { Padding = UDim.new(0, 6), Parent = Holder })
        New("UIPadding", {
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft   = UDim.new(0, 10),
            PaddingRight  = UDim.new(0, 10),
            PaddingTop    = UDim.new(0, 10),
            Parent = Holder,
        })
        Library:AddOutline(Holder)

        -- barra colorida lateral indicando tipo
        local accentColor = "AccentColor"
        if data.Type == "Success" then accentColor = "AccentColor"
        elseif data.Type == "Error" then accentColor = "RedColor" end

        local Bar = New("Frame", {
            AnchorPoint = Vector2.new(0, 0),
            BackgroundColor3 = accentColor,
            Size = UDim2.new(0, 3, 1, 0),
            ZIndex = 6,
            Parent = Holder,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Bar,
        }))

        -- linha de título (com ícone opcional)
        local TitleContainer = nil
        if data.Title then
            TitleContainer = New("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 18),
                Parent = Holder,
            })

            if data.Icon then
                local IconLbl = New("ImageLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromOffset(16, 16),
                    ImageColor3 = data.IconColor or accentColor,
                    Parent = TitleContainer,
                })
                pcall(function() IconLbl.Image = tostring(data.Icon) end)
            end

            New("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(data.Icon and 22 or 0, 0),
                Size = UDim2.new(1, data.Icon and -22 or 0, 1, 0),
                Text = data.Title,
                TextSize = 15,
                TextColor3 = data.TitleColor or "FontColor",
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = TitleContainer,
            })
        end

        local Desc
        if data.Description then
            Desc = New("TextLabel", {
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                Text = data.Description,
                TextSize = 13,
                TextColor3 = data.DescriptionColor or "FontColor",
                TextTransparency = 0.2,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = Holder,
            })
        end

        local bar = New("Frame", {
            BackgroundColor3 = "BackgroundColor",
            Size = UDim2.new(1, 0, 0, 2),
            Parent = Holder,
        })
        local Fill = New("Frame", {
            BackgroundColor3 = accentColor,
            Size = UDim2.fromScale(1, 1),
            Parent = bar,
        })

        local NotifyData = {
            Fake = Fake,
            Holder = Holder,
            Destroyed = false,
        }

        function NotifyData:Destroy()
            if NotifyData.Destroyed then return end
            NotifyData.Destroyed = true

            for i, fb in ipairs(NotifyOrder) do
                if fb == Fake then
                    table.remove(NotifyOrder, i)
                    break
                end
            end
            Library:UpdateNotificationPositions(false)

            TweenService:Create(Holder, Library.NotifyTweenInfo, {
                Position = string.lower(Library.NotifySide) == "left"
                    and UDim2.new(-1, -10, 0, -2)
                    or  UDim2.new(1, 10, 0, -2),
            }):Play()

            task.delay(Library.NotifyTweenInfo.Time, function()
                Library.Notifications[Fake] = nil
                Fake:Destroy()
            end)
        end

        function NotifyData:ChangeTitle(t)
            if TitleContainer then
                local lbl = TitleContainer:FindFirstChildOfClass("TextLabel")
                if lbl then lbl.Text = t end
            end
        end
        function NotifyData:ChangeDescription(t)
            if Desc then Desc.Text = t end
        end

        table.insert(NotifyOrder, Fake)
        Library.Notifications[Fake] = NotifyData

        Library:UpdateNotificationPositions(true)
        Fake.Visible = true
        TweenService:Create(Holder, Library.NotifyTweenInfo, { Position = UDim2.fromOffset(0, 0) }):Play()

        if not data.Persist then
            local duration = typeof(data.Time) == "number" and data.Time or 5
            TweenService:Create(Fill,
                TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
                { Size = UDim2.fromScale(0, 1) }
            ):Play()
            task.delay(duration, function()
                if not NotifyData.Destroyed then NotifyData:Destroy() end
            end)
        end

        return NotifyData
    end

    --// Atalhos
    function Library:NotifySuccess(title, description, time)
        return Library:Notify({ Title = title, Description = description, Type = "Success", Time = time or 4 })
    end
    function Library:NotifyError(title, description, time)
        return Library:Notify({ Title = title, Description = description, Type = "Error", Time = time or 5 })
    end

    --================================================================
    --  DIALOG
    --================================================================
    local ActiveDialog = nil

    function Library:AddDialog(Idx, Info)
        Info = Library:Validate(Info or {}, {
            Title = "Dialog",
            Description = "",
            Icon = nil,
            AutoDismiss = true,
            OutsideClickDismiss = true,
            FooterButtons = {},
        })

        -- Se já tem dialog aberto, fecha
        if ActiveDialog and not ActiveDialog.Destroyed then
            ActiveDialog:Dismiss()
        end

        local OverlayFrame = New("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = "DarkColor",
            BackgroundTransparency = 0.5,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            ZIndex = 9000,
            Parent = Library.Window and Library.Window.MainFrame or ScreenGui,
        })

        local Frame = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = "BackgroundColor",
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(400, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 1,
            Parent = OverlayFrame,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Frame,
        }))
        Library:AddOutline(Frame)

        local Scale = New("UIScale", { Scale = 0.9, Parent = Frame })
        TweenService:Create(Scale, Library.TweenInfo, { Scale = 1 }):Play()

        local Inner = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = Frame,
        })
        New("UIPadding", {
            PaddingBottom = UDim.new(0, 16),
            PaddingLeft   = UDim.new(0, 18),
            PaddingRight  = UDim.new(0, 18),
            PaddingTop    = UDim.new(0, 16),
            Parent = Inner,
        })
        New("UIListLayout", {
            Padding = UDim.new(0, 12),
            Parent = Inner,
        })

        -- Title
        if Info.Title then
            New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 20),
                Text = Info.Title,
                TextSize = 17,
                TextColor3 = "FontColor",
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = Inner,
            })
        end

        -- Description
        if Info.Description and Info.Description ~= "" then
            New("TextLabel", {
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                Text = Info.Description,
                TextSize = 13,
                TextColor3 = "FontColor",
                TextTransparency = 0.25,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = Inner,
            })
        end

        -- Buttons holder
        local ButtonsHolder = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 30),
            Parent = Inner,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 8),
            Parent = ButtonsHolder,
        })

        local Dialog = {
            Destroyed = false,
            Container = Inner,
            ButtonsHolder = ButtonsHolder,
            FooterButtonsList = {},
            OutsideClickDismiss = Info.OutsideClickDismiss,
        }

        function Dialog:AddFooterButton(key, info)
            if Dialog.FooterButtonsList[key] then
                Dialog.FooterButtonsList[key]:Destroy()
            end

            local variant = info.Variant or "Secondary"
            local color = "MainColor"
            local textColor = "FontColor"

            if variant == "Primary" then
                color = "AccentColor"
                textColor = "BackgroundColor"
            elseif variant == "Destructive" then
                color = "RedColor"
                textColor = "WhiteColor"
            elseif variant == "Ghost" then
                color = "BackgroundColor"
            end

            local Btn = New("TextButton", {
                BackgroundColor3 = color,
                Size = UDim2.fromOffset(0, 30),
                Text = info.Title or key,
                TextSize = 14,
                TextColor3 = textColor,
                AutoButtonColor = false,
                Parent = ButtonsHolder,
            })
            table.insert(Library.Corners, New("UICorner", {
                CornerRadius = UDim.new(0, Library.CornerRadius),
                Parent = Btn,
            }))
            New("UIStroke", {
                Color = "OutlineColor",
                Thickness = Library.StrokeThickness,
                Transparency = variant == "Primary" and 1 or 0,
                Parent = Btn,
            })
            New("UIPadding", {
                PaddingLeft = UDim.new(0, 18),
                PaddingRight = UDim.new(0, 18),
                Parent = Btn,
            })

            local x = Library:GetTextBounds(Btn.Text, Library.Font, 14, 300)
            Btn.Size = UDim2.fromOffset(x + 40, 30)

            Btn.MouseEnter:Connect(function()
                Btn.BackgroundTransparency = 0.15
            end)
            Btn.MouseLeave:Connect(function()
                Btn.BackgroundTransparency = 0
            end)

            Btn.MouseButton1Click:Connect(function()
                Sounds:PlayClick()
                if info.Callback then SafeCallback(info.Callback, Dialog) end
                if Info.AutoDismiss then Dialog:Dismiss() end
            end)

            Dialog.FooterButtonsList[key] = Btn
            return Btn
        end

        for key, info in pairs(Info.FooterButtons) do
            Dialog:AddFooterButton(key, info)
        end

        function Dialog:Dismiss()
            if Dialog.Destroyed then return end
            Dialog.Destroyed = true

            if ActiveDialog == Dialog then
                ActiveDialog = nil
                Library.ActiveDialog = nil
            end

            TweenService:Create(Scale, Library.TweenInfo, { Scale = 0.9 }):Play()
            TweenService:Create(OverlayFrame, Library.TweenInfo, { BackgroundTransparency = 1 }):Play()

            task.delay(Library.TweenInfo.Time, function()
                OverlayFrame:Destroy()
            end)
        end

        OverlayFrame.MouseButton1Click:Connect(function()
            if Dialog.OutsideClickDismiss then
                Dialog:Dismiss()
            end
        end)

        ActiveDialog = Dialog
        Library.ActiveDialog = Dialog
        Library.Dialogues[Idx] = Dialog

        return Dialog
    end

    --================================================================
    --  CONTEXT MENU (usado por elementos complexos)
    --================================================================
    local CurrentMenu = nil

    function Library:AddContextMenu(Holder, Size, Offset, List, ActiveCallback, IgnoreCornerRadius, SpecificCornersOnly, AnimationType)
        local Menu = New("Frame", {
            BackgroundColor3 = "BackgroundColor",
            Size = typeof(Size) == "function" and Size() or Size,
            Visible = false,
            ZIndex = 1,
            Parent = Overlay,
        })
        table.insert(Library.Scales, New("UIScale", { Parent = Menu }))

        New("UIStroke", {
            Color = "OutlineColor",
            Thickness = Library.StrokeThickness,
            Parent = Menu,
        })

        local Corner
        if not IgnoreCornerRadius then
            Corner = New("UICorner", {
                CornerRadius = UDim.new(0, Library.CornerRadius),
                Parent = Menu,
            })
            table.insert(Library.Corners, Corner)
        end

        local Table = {
            Active = false,
            ActiveCallback = ActiveCallback,
            Holder = Holder,
            Menu = Menu,
            Corner = Corner,
            Destroyed = false,
        }

        function Table:Open()
            if CurrentMenu == Table then return end
            if CurrentMenu then CurrentMenu:Close() end

            CurrentMenu = Table
            Table.Active = true

            if typeof(Offset) == "function" then
                Menu.Position = UDim2.fromOffset(
                    math.floor(Holder.AbsolutePosition.X + Offset()[1]),
                    math.floor(Holder.AbsolutePosition.Y + Offset()[2])
                )
            else
                Menu.Position = UDim2.fromOffset(
                    math.floor(Holder.AbsolutePosition.X + Offset[1]),
                    math.floor(Holder.AbsolutePosition.Y + Offset[2])
                )
            end

            Menu.Size = typeof(Size) == "function" and Size() or Size
            Menu.Visible = true
            if ActiveCallback then SafeCallback(ActiveCallback, true) end
        end

        function Table:Close()
            if CurrentMenu ~= Table then return end
            CurrentMenu = nil
            Table.Active = false
            Menu.Visible = false
            if ActiveCallback then SafeCallback(ActiveCallback, false) end
        end

        function Table:Toggle()
            if Table.Active then Table:Close() else Table:Open() end
        end

        function Table:Destroy()
            Table.Destroyed = true
            if CurrentMenu == Table then CurrentMenu = nil end
            Menu:Destroy()
        end

        table.insert(Library.ContextMenus, Table)
        return Table
    end

    --// click fora fecha menu
    GiveSignal(UserInputService.InputBegan:Connect(function(Input)
        if not CurrentMenu then return end
        if not IsClickInput(Input, true) then return end

        local pos = Input.Position
        if Library:MouseIsOverFrame(CurrentMenu.Menu, pos) then return end
        if Library:MouseIsOverFrame(CurrentMenu.Holder, pos) then return end

        CurrentMenu:Close()
    end))

    --================================================================
    --  DRAGGABLE MENU (card flutuante com header)
    --================================================================
    function Library:AddDraggableMenu(Name)
        local Holder = New("Frame", {
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundColor3 = "BackgroundColor",
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.fromOffset(0, 0),
            ZIndex = 1,
            Parent = Floats,
        })
        table.insert(Library.Corners, New("UICorner", {
            CornerRadius = UDim.new(0, Library.CornerRadius),
            Parent = Holder,
        }))
        table.insert(Library.Scales, New("UIScale", { Parent = Holder }))
        Library:AddOutline(Holder)

        Library:MakeLine(Holder, {
            Position = UDim2.fromOffset(0, 32),
            Size = UDim2.new(1, 0, 0, 1),
        })

        local Label = New("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 32),
            Text = Name,
            TextSize = 14,
            TextColor3 = "FontColor",
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Holder,
        })
        New("UIPadding", {
            PaddingLeft  = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 12),
            Parent = Label,
        })

        local Container = New("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 33),
            Size = UDim2.new(1, 0, 1, -33),
            Parent = Holder,
        })
        New("UIListLayout", { Padding = UDim.new(0, 7), Parent = Container })
        New("UIPadding", {
            PaddingBottom = UDim.new(0, 7),
            PaddingLeft   = UDim.new(0, 7),
            PaddingRight  = UDim.new(0, 7),
            PaddingTop    = UDim.new(0, 7),
            Parent = Container,
        })

        Library:MakeDraggable(Holder, Label, true)

        if not table.find(Library.DraggableElements, Holder) then
            table.insert(Library.DraggableElements, Holder)
        end

        return Holder, Container
    end

    --================================================================
    --  WATERMARK (compat)
    --================================================================
    local Watermark = Library:AddDraggableLabel("", nil, "left")
    Watermark:SetVisible(false)

    function Library:SetWatermark(text)
        Watermark:SetVisible(true)
        Watermark:SetText(text)
    end
    function Library:SetWatermarkVisibility(v)
        Watermark:SetVisible(v)
    end

    --================================================================
    --  SEARCH GLOBAL
    --================================================================
    local function FuzzyScore(Text, Query)
        if Query == "" then return true, 0 end
        if Text == "" then return false, 0 end

        local idx = string.find(Text, Query, 1, true)
        if idx then
            return true, 1e5 - idx + (#Query * 5)
        end

        local ti, qi, score, run = 1, 1, 0, 0
        local lastIdx = 0
        while ti <= #Text and qi <= #Query do
            if string.sub(Text, ti, ti) == string.sub(Query, qi, qi) then
                run = (lastIdx == ti - 1) and run + 1 or 1
                score = score + 1 + math.min(run - 1, 5) * 3
                lastIdx = ti
                qi = qi + 1
            end
            ti = ti + 1
        end

        if qi <= #Query then return false, 0 end
        return true, score - (lastIdx - #Query) * 0.05
    end

    local function MatchesSearch(element, query)
        if not element then return false end
        if element.Text and FuzzyScore(string.lower(element.Text), query) then return true end
        return false
    end

    function Library:UpdateSearch(query)
        query = string.lower(Trim(query or ""))
        Library.SearchText = query
        Library.Searching  = query ~= ""

        if not Library.Tabs then return end

        for _, tab in pairs(Library.Tabs) do
            if tab.Groupboxes then
                for _, gb in pairs(tab.Groupboxes) do
                    local visibleCount = 0
                    for _, el in ipairs(gb.Elements or {}) do
                        if el.Type == "Divider" then
                            if el.Holder then el.Holder.Visible = false end
                        elseif MatchesSearch(el, query) and el.Visible ~= false then
                            if el.Holder then el.Holder.Visible = true end
                            visibleCount = visibleCount + 1
                        else
                            if el.Holder then el.Holder.Visible = false end
                        end
                    end
                    if gb.BoxHolder then
                        gb.BoxHolder.Visible = visibleCount > 0 or query == ""
                    end
                end
            end
        end
    end

    --================================================================
    --  FIM
    --================================================================
    return Library
end