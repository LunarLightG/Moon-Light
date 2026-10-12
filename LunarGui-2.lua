-- LunarGui Library | Responsive Roblox UI for PC + Mobile
-- Config data is kept in memory by default. For cross-session persistence, pass a trusted Persistence adapter.
-- No executor-only filesystem APIs are used.

local LunarGui = {}
LunarGui.__index = LunarGui

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

LunarGui.Theme = {
    Background = Color3.fromRGB(14, 11, 21),
    Panel = Color3.fromRGB(25, 20, 36),
    Row = Color3.fromRGB(35, 27, 49),
    Stroke = Color3.fromRGB(76, 56, 104),
    Accent = Color3.fromRGB(163, 104, 255),
    AccentDark = Color3.fromRGB(99, 60, 160),
    Text = Color3.fromRGB(245, 239, 255),
    Muted = Color3.fromRGB(169, 155, 190),
    Green = Color3.fromRGB(83, 220, 142),
    Red = Color3.fromRGB(255, 92, 124),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function round(o, r) new("UICorner", {CornerRadius = UDim.new(0, r or 10)}, o) end
local function outline(o, color)
    new("UIStroke", {Color = color or LunarGui.Theme.Stroke, Transparency = 0.15, Thickness = 1}, o)
end
local function tween(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end
local function label(parent, text, size, color, bold)
    return new("TextLabel", {
        BackgroundTransparency = 1, Text = tostring(text or ""), Font = bold and Enum.Font.GothamSemibold or Enum.Font.Gotham,
        TextSize = size or 12, TextColor3 = color or LunarGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 0, 22),
    }, parent)
end
local function button(parent, text, theme, height)
    local b = new("TextButton", {
        AutoButtonColor = false, Text = text or "", Font = Enum.Font.GothamSemibold, TextSize = 12,
        TextColor3 = theme.Text, BackgroundColor3 = theme.Row, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height or 36),
    }, parent)
    round(b, 9); outline(b)
    b.MouseEnter:Connect(function() tween(b, {BackgroundColor3 = theme.AccentDark}) end)
    b.MouseLeave:Connect(function() tween(b, {BackgroundColor3 = theme.Row}) end)
    return b
end

function LunarGui.new(options)
    options = options or {}
    local self = setmetatable({}, LunarGui)
    self.Name = options.Name or "LunarGui"
    self.Theme = table.clone(LunarGui.Theme)
    for k, v in pairs(options.Theme or {}) do self.Theme[k] = v end
    self.Values, self.Bindings, self.Tabs, self.Configs = {}, {}, {}, {}
    self.SelectedConfig, self.Persistence, self._connections = nil, options.Persistence, {}
    local pg = options.Parent or (player and player:WaitForChild("PlayerGui"))
    assert(pg, "LunarGui requires PlayerGui or options.Parent")

    self.Screen = new("ScreenGui", {
        Name = self.Name, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = options.DisplayOrder or 40,
    }, pg)

    self.Root = new("Frame", {
        Name = "Window", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.new(.82, 0, .78, 0), BackgroundColor3 = self.Theme.Background,
        BorderSizePixel = 0, ClipsDescendants = true,
    }, self.Screen)
    round(self.Root, 16); outline(self.Root, self.Theme.Stroke)
    new("UISizeConstraint", {MinSize = Vector2.new(300, 300), MaxSize = Vector2.new(950, 720)}, self.Root)
    self.BG = new("ImageLabel", {
        Name = "Background", BackgroundTransparency = 1, Image = options.BackgroundImage or "",
        ImageTransparency = options.BackgroundTransparency or .88, ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1), ZIndex = 0,
    }, self.Root)

    self.Top = new("Frame", {BackgroundColor3 = self.Theme.Panel, BackgroundTransparency = .03,
        BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 54), ZIndex = 2}, self.Root)
    round(self.Top, 16)
    new("Frame", {BackgroundColor3 = self.Theme.Panel, BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), ZIndex = 2}, self.Top)
    self.Logo = new("ImageLabel", {BackgroundTransparency = 1, Image = options.LogoImage or "",
        Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(34, 34), ScaleType = Enum.ScaleType.Fit, ZIndex = 3}, self.Top)
    self.Title = new("TextLabel", {BackgroundTransparency = 1, Text = self.Name, Font = Enum.Font.GothamBold,
        TextSize = 17, TextColor3 = self.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(54, 4), Size = UDim2.new(1, -110, 0, 26), ZIndex = 3}, self.Top)
    self.Subtitle = new("TextLabel", {BackgroundTransparency = 1, Text = options.Subtitle or "GALAXY INTERFACE",
        Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = self.Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(55, 29),
        Size = UDim2.new(1, -110, 0, 14), ZIndex = 3}, self.Top)
    self.Min = new("TextButton", {AutoButtonColor = false, Text = "—", Font = Enum.Font.GothamBold,
        TextSize = 18, TextColor3 = self.Theme.Text, BackgroundColor3 = self.Theme.Row,
        AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0),
        Size = UDim2.fromOffset(30, 30), ZIndex = 4}, self.Top)
    round(self.Min, 8)

    self.Side = new("Frame", {BackgroundColor3 = self.Theme.Panel, BackgroundTransparency = .12,
        BorderSizePixel = 0, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(0, 150, 1, -54), ZIndex = 1}, self.Root)
    self.TabList = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -88),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.Theme.Accent}, self.Side)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, self.TabList)
    self.Profile = new("Frame", {BackgroundColor3 = self.Theme.Row, BackgroundTransparency = .15,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8),
        Size = UDim2.new(1, -16, 0, 62)}, self.Side)
    round(self.Profile, 11)
    self.Avatar = new("ImageLabel", {BackgroundColor3 = self.Theme.Panel, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(42, 42), Image = ""}, self.Profile)
    round(self.Avatar, 21); outline(self.Avatar, self.Theme.Accent)
    self.Dot = new("Frame", {BackgroundColor3 = self.Theme.Green, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0, 51, 0, 51), Size = UDim2.fromOffset(11, 11), ZIndex = 5}, self.Profile)
    round(self.Dot, 6); outline(self.Dot, self.Theme.Background)
    self.PName = new("TextLabel", {BackgroundTransparency = 1, Text = player and player.DisplayName or "Player",
        Font = Enum.Font.GothamSemibold, TextSize = 11, TextColor3 = self.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(58, 10), Size = UDim2.new(1, -64, 0, 20)}, self.Profile)
    self.PHandle = new("TextLabel", {BackgroundTransparency = 1, Text = player and ("@" .. player.Name) or "",
        Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = self.Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -64, 0, 16)}, self.Profile)
    if player then task.spawn(function()
        local ok, image = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end)
        if ok and self.Avatar.Parent then self.Avatar.Image = image end
    end) end

    self.Content = new("Frame", {BackgroundTransparency = 1, Position = UDim2.new(0, 150, 0, 54),
        Size = UDim2.new(1, -150, 1, -54)}, self.Root)
    self._expanded, self._minimized, self.ActiveTab = true, false, nil
    self.Min.Activated:Connect(function()
        self._minimized = not self._minimized
        if self._minimized then
            self._restoreSize = self.Root.Size
            self.Root.Size = UDim2.new(0, 300, 0, 54)
            self.Side.Visible, self.Content.Visible, self.BG.Visible = false, false, false
            self.Min.Text = "+"
        else
            self.Root.Size = self._restoreSize or UDim2.new(.82, 0, .78, 0)
            self.Side.Visible, self.Content.Visible, self.BG.Visible = true, true, true
            self.Min.Text = "—"
        end
    end)

    local dragging, dragStart, startPos = false, nil, nil
    self.Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, self.Root.Position
            local c; c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false; if c then c:Disconnect() end end
            end)
        end
    end)
    table.insert(self._connections, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            self.Root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    local function responsive()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if cam.ViewportSize.X < 650 then
            self.Root.Size = UDim2.new(1, -12, 1, -24)
            self.Side.Size = UDim2.new(0, 112, 1, -54)
            self.Content.Position, self.Content.Size = UDim2.new(0, 112, 0, 54), UDim2.new(1, -112, 1, -54)
            self.PName.Visible, self.PHandle.Visible = false, false
            self.Avatar.Position = UDim2.new(.5, -21, 0, 7)
            self.Dot.Position = UDim2.new(1, -7, 1, -7)
            self.Profile.Size = UDim2.new(1, -16, 0, 58)
        elseif not self._minimized then
            self.Root.Size = UDim2.new(.82, 0, .78, 0)
            local w = self._expanded and 150 or 64
            self.Side.Size = UDim2.new(0, w, 1, -54)
            self.Content.Position, self.Content.Size = UDim2.new(0, w, 0, 54), UDim2.new(1, -w, 1, -54)
            self.PName.Visible, self.PHandle.Visible = self._expanded, self._expanded
            self.Avatar.Position = self._expanded and UDim2.fromOffset(8, 9) or UDim2.new(.5, -21, 0, 7)
            self.Dot.Position = self._expanded and UDim2.new(0, 51, 0, 51) or UDim2.new(1, -7, 1, -7)
            self.Profile.Size = UDim2.new(1, -16, 0, self._expanded and 62 or 58)
        end
    end
    self._responsive = responsive
    if workspace.CurrentCamera then table.insert(self._connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive)) end
    responsive()

    self.Collapse = new("TextButton", {BackgroundTransparency = 1, Text = "‹", Font = Enum.Font.GothamBold,
        TextSize = 20, TextColor3 = self.Theme.Muted, Position = UDim2.new(1, -28, 0, 0), Size = UDim2.fromOffset(24, 26)}, self.Side)
    self.Collapse.Activated:Connect(function()
        self._expanded = not self._expanded
        if workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X >= 650 then
            local w = self._expanded and 150 or 64
            self.Side.Size = UDim2.new(0, w, 1, -54)
            self.Content.Position, self.Content.Size = UDim2.new(0, w, 0, 54), UDim2.new(1, -w, 1, -54)
            self.PName.Visible, self.PHandle.Visible = self._expanded, self._expanded
            self.Avatar.Position = self._expanded and UDim2.fromOffset(8, 9) or UDim2.new(.5, -21, 0, 7)
            self.Dot.Position = self._expanded and UDim2.new(0, 51, 0, 51) or UDim2.new(1, -7, 1, -7)
            self.Collapse.Text = self._expanded and "‹" or "›"
            for _, tab in ipairs(self.Tabs) do tab.Button.Text = self._expanded and (tab.Icon .. "  " .. tab.Name) or tab.Icon end
        end
    end)
    return self
end

function LunarGui:CreateTab(options)
    options = options or {}
    local tab = {Name = options.Name or ("Tab" .. (#self.Tabs + 1)), Icon = options.Icon or "✦", Sections = {}}
    tab.Button = new("TextButton", {AutoButtonColor = false, Text = tab.Icon .. "  " .. tab.Name,
        Font = Enum.Font.GothamSemibold, TextSize = 12, TextColor3 = self.Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = self.Theme.Row,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = #self.Tabs + 1}, self.TabList)
    round(tab.Button, 9)
    new("UIPadding", {PaddingLeft = UDim.new(0, 10)}, tab.Button)
    tab.Page = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.Theme.Accent, Visible = false}, self.Content)
    new("UIPadding", {PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14)}, tab.Page)
    new("UIListLayout", {Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder}, tab.Page)
    local gui = self
    function tab:CreateSection(opts)
        opts = opts or {}
        local section = {Gui = gui, Tab = self, Name = opts.Name or "Section", Open = opts.DefaultOpen ~= false, Components = {}}
        section.Frame = new("Frame", {BackgroundColor3 = gui.Theme.Panel, BackgroundTransparency = .06,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42), AutomaticSize = Enum.AutomaticSize.Y}, self.Page)
        round(section.Frame, 12); outline(section.Frame)
        section.Header = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 42)}, section.Frame)
        local title = label(section.Header, section.Name, 13, gui.Theme.Text, true)
        title.Position, title.Size = UDim2.fromOffset(13, 0), UDim2.new(1, -48, 1, 0)
        section.Chevron = label(section.Header, section.Open and "⌄" or "›", 18, gui.Theme.Accent, true)
        section.Chevron.TextXAlignment = Enum.TextXAlignment.Center
        section.Chevron.Position, section.Chevron.Size = UDim2.new(1, -32, 0, 8), UDim2.fromOffset(20, 24)
        section.Body = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 42),
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = section.Open}, section.Frame)
        new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            PaddingBottom = UDim.new(0, 12)}, section.Body)
        new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, section.Body)
        section.Header.Activated:Connect(function()
            section.Open = not section.Open
            section.Body.Visible = section.Open
            section.Chevron.Text = section.Open and "⌄" or "›"
        end)
        function section:_register(id, setter, getter, kind)
            gui.Bindings[id] = {Set = setter, Get = getter, Type = kind}
            if gui.Values[id] == nil then gui.Values[id] = getter() end
        end
        function section:CreateLabel(opts)
            opts = type(opts) == "string" and {Name = opts} or (opts or {})
            local l = label(self.Body, opts.Name or opts.Text or "Label", 12, gui.Theme.Muted, false)
            l.Size = UDim2.new(1, 0, 0, opts.Height or 26)
            return {SetText = function(_, v) l.Text = tostring(v) end, Instance = l}
        end
        function section:CreateButton(opts)
            opts = opts or {}
            local b = button(self.Body, opts.Name or "Button", gui.Theme, opts.Height or 38)
            b.Activated:Connect(function() if opts.Callback then task.spawn(opts.Callback) end end)
            return {Instance = b}
        end
        function section:CreateToggle(opts)
            opts = opts or {}; local id = opts.Flag or opts.Name or ("Toggle" .. (#self.Components + 1))
            local row = new("Frame", {BackgroundColor3 = gui.Theme.Row, BackgroundTransparency = .12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42)}, self.Body); round(row, 9)
            local l = label(row, opts.Name or id, 12, gui.Theme.Text, true); l.Position = UDim2.fromOffset(10, 0); l.Size = UDim2.new(1, -65, 1, 0)
            local track = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = gui.Theme.Stroke, Position = UDim2.new(1, -52, .5, -11), Size = UDim2.fromOffset(42, 22)}, row); round(track, 12)
            local knob = new("Frame", {BackgroundColor3 = gui.Theme.Text, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(16, 16)}, track); round(knob, 9)
            local value = opts.Default == true
            local function set(v, silent)
                value = v == true; tween(track, {BackgroundColor3 = value and gui.Theme.Accent or gui.Theme.Stroke})
                tween(knob, {Position = value and UDim2.new(1, -20, 0, 3) or UDim2.fromOffset(4, 3)})
                gui.Values[id] = value
                if not silent and opts.Callback then task.spawn(opts.Callback, value) end
            end
            track.Activated:Connect(function() set(not value) end); set(value, true)
            self:_register(id, function(v) set(v, true) end, function() return value end, "Toggle")
            return {Set = set, Get = function() return value end, Instance = row}
        end
        function section:CreateSlider(opts)
            opts = opts or {}; local id = opts.Flag or opts.Name or ("Slider" .. (#self.Components + 1))
            local min, max = tonumber(opts.Min) or 0, tonumber(opts.Max) or 100
            if max < min then min, max = max, min end
            local dec = math.max(0, math.floor(tonumber(opts.Decimals) or 0)); local factor = 10 ^ dec
            local row = new("Frame", {BackgroundColor3 = gui.Theme.Row, BackgroundTransparency = .12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 72)}, self.Body); round(row, 9)
            local l = label(row, opts.Name or id, 12, gui.Theme.Text, true); l.Position = UDim2.fromOffset(10, 3); l.Size = UDim2.new(1, -98, 0, 23)
            local box = new("TextBox", {ClearTextOnFocus = false, Text = tostring(opts.Default or min), Font = Enum.Font.GothamSemibold, TextSize = 12,
                TextColor3 = gui.Theme.Text, BackgroundColor3 = gui.Theme.Background, BorderSizePixel = 0, Position = UDim2.new(1, -80, 0, 4), Size = UDim2.fromOffset(70, 25)}, row); round(box, 7)
            local bar = new("Frame", {BackgroundColor3 = gui.Theme.Stroke, BorderSizePixel = 0, Position = UDim2.new(0, 10, 0, 47), Size = UDim2.new(1, -20, 0, 7)}, row); round(bar, 4)
            local fill = new("Frame", {BackgroundColor3 = gui.Theme.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0)}, bar); round(fill, 4)
            local hit = new("TextButton", {Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, -9), Size = UDim2.new(1, 0, 0, 25)}, bar)
            local value = min
            local function set(v, silent)
                v = tonumber(v); if not v then return false end
                v = math.floor(math.clamp(v, min, max) * factor + .5) / factor; value = v
                fill.Size = UDim2.new(max == min and 0 or (v - min) / (max - min), 0, 1, 0); box.Text = tostring(v); gui.Values[id] = v
                if not silent and opts.Callback then task.spawn(opts.Callback, v) end
                return true
            end
            local function fromX(x) local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1); set(min + (max - min) * a) end
            hit.Activated:Connect(function() fromX(UIS:GetMouseLocation().X) end)
            hit.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then fromX(i.Position.X) end end)
            box.FocusLost:Connect(function() if not set(box.Text) then box.Text = tostring(value) end end)
            set(opts.Default or min, true); self:_register(id, function(v) set(v, true) end, function() return value end, "Slider")
            return {Set = set, Get = function() return value end, Instance = row}
        end
        function section:CreateDropdown(opts)
            opts = opts or {}; local id = opts.Flag or opts.Name or ("Dropdown" .. (#self.Components + 1))
            local row = new("Frame", {BackgroundColor3 = gui.Theme.Row, BackgroundTransparency = .12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44)}, self.Body); round(row, 9)
            local l = label(row, opts.Name or id, 12, gui.Theme.Text, true); l.Position = UDim2.fromOffset(10, 0); l.Size = UDim2.new(.42, -10, 1, 0)
            local value = opts.Default
            local chosen = label(row, value or "Select...", 11, gui.Theme.Muted, false); chosen.TextXAlignment = Enum.TextXAlignment.Right; chosen.Position = UDim2.new(.42, 0, 0, 0); chosen.Size = UDim2.new(.58, -38, 1, 0)
            local open = new("TextButton", {Text = "⌄", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = gui.Theme.Accent, BackgroundTransparency = 1, Position = UDim2.new(1, -34, 0, 4), Size = UDim2.fromOffset(30, 34)}, row)
            local function picker()
                if gui.Picker then gui.Picker:Destroy() end
                local overlay = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = .4, Size = UDim2.fromScale(1, 1), ZIndex = 100}, gui.Screen)
                gui.Picker = overlay
                local modal = new("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(.86, 0, .68, 0), BackgroundColor3 = gui.Theme.Panel, BorderSizePixel = 0, ZIndex = 101}, overlay)
                new("UISizeConstraint", {MinSize = Vector2.new(250, 240), MaxSize = Vector2.new(440, 520)}, modal); round(modal, 15); outline(modal, gui.Theme.Accent)
                local head = label(modal, opts.Name or "Choose one", 15, gui.Theme.Text, true); head.Position = UDim2.fromOffset(15, 6); head.Size = UDim2.new(1, -60, 0, 38); head.ZIndex = 103
                local close = new("TextButton", {Text = "×", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = gui.Theme.Muted, BackgroundTransparency = 1, Position = UDim2.new(1, -42, 0, 5), Size = UDim2.fromOffset(34, 34), ZIndex = 104}, modal)
                local list = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 1, -58), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = gui.Theme.Accent, ZIndex = 102}, modal)
                new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)
                local function closePicker() if overlay.Parent then overlay:Destroy() end gui.Picker = nil end
                overlay.Activated:Connect(closePicker); close.Activated:Connect(closePicker)
                for n, item in ipairs(opts.Options or {}) do
                    local b = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = item == value and gui.Theme.AccentDark or gui.Theme.Row, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = n, ZIndex = 103}, list); round(b, 8)
                    local t = label(b, tostring(item), 12, gui.Theme.Text, item == value); t.Position = UDim2.fromOffset(12, 0); t.Size = UDim2.new(1, -45, 1, 0); t.ZIndex = 104
                    local check = label(b, item == value and "✓" or "", 15, gui.Theme.Text, true); check.TextXAlignment = Enum.TextXAlignment.Center; check.Position = UDim2.new(1, -32, 0, 0); check.Size = UDim2.fromOffset(22, 40); check.ZIndex = 104
                    b.Activated:Connect(function() value = item; chosen.Text = tostring(item); gui.Values[id] = item; if opts.Callback then task.spawn(opts.Callback, item) end; closePicker() end)
                end
            end
            open.Activated:Connect(picker)
            self:_register(id, function(v) value = v; chosen.Text = v == nil and "Select..." or tostring(v) end, function() return value end, "Dropdown")
            return {Get = function() return value end, Set = function(v) for _, x in ipairs(opts.Options or {}) do if x == v then value = v; chosen.Text = tostring(v); gui.Values[id] = v; return true end end return false end, Open = picker, Instance = row}
        end
        function section:CreateTextbox(opts)
            opts = opts or {}; local id = opts.Flag or opts.Name or ("Textbox" .. (#self.Components + 1))
            local row = new("Frame", {BackgroundColor3 = gui.Theme.Row, BackgroundTransparency = .12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 66)}, self.Body); round(row, 9)
            local l = label(row, opts.Name or id, 12, gui.Theme.Text, true); l.Position = UDim2.fromOffset(10, 0)
            local box = new("TextBox", {ClearTextOnFocus = false, Text = tostring(opts.Default or ""), PlaceholderText = opts.Placeholder or "Type here", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = gui.Theme.Text, PlaceholderColor3 = gui.Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = gui.Theme.Background, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 29), Size = UDim2.new(1, -16, 0, 29)}, row); round(box, 7)
            local val = box.Text; box.FocusLost:Connect(function(enter) val = box.Text; gui.Values[id] = val; if opts.Callback then task.spawn(opts.Callback, val, enter) end end)
            self:_register(id, function(v) val = tostring(v or ""); box.Text = val end, function() return val end, "Textbox")
            return {Get = function() return val end, Set = function(v) val = tostring(v or ""); box.Text = val; gui.Values[id] = val end, Instance = row}
        end
        function section:CreateKeybind(opts)
            opts = opts or {}; local id = opts.Flag or opts.Name or ("Keybind" .. (#self.Components + 1))
            local row = new("Frame", {BackgroundColor3 = gui.Theme.Row, BackgroundTransparency = .12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42)}, self.Body); round(row, 9)
            local l = label(row, opts.Name or id, 12, gui.Theme.Text, true); l.Position = UDim2.fromOffset(10, 0); l.Size = UDim2.new(1, -100, 1, 0)
            local key = opts.Default or Enum.KeyCode.RightShift; local listening = false
            local b = button(row, key.Name, gui.Theme, 28); b.AnchorPoint = Vector2.new(1, .5); b.Position = UDim2.new(1, -8, .5, 0); b.Size = UDim2.fromOffset(82, 28)
            b.Activated:Connect(function() listening = true; b.Text = "Press key" end)
            table.insert(gui._connections, UIS.InputBegan:Connect(function(input, processed)
                if listening and input.UserInputType == Enum.UserInputType.Keyboard then key = input.KeyCode; listening = false; b.Text = key.Name; gui.Values[id] = key.Name
                elseif not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key and opts.Callback then task.spawn(opts.Callback, key) end
            end))
            self:_register(id, function(v) if typeof(v) == "EnumItem" then key = v elseif Enum.KeyCode[tostring(v)] then key = Enum.KeyCode[tostring(v)] end; b.Text = key.Name end, function() return key.Name end, "Keybind")
            return {Get = function() return key end, Instance = row}
        end
        table.insert(self.Sections or {}, section)
        return section
    end
    tab.Button.Activated:Connect(function() gui:SelectTab(tab) end)
    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function LunarGui:SelectTab(tab)
    if type(tab) == "string" then for _, t in ipairs(self.Tabs) do if t.Name == tab then tab = t break end end end
    if not tab then return end
    self.ActiveTab = tab
    for _, t in ipairs(self.Tabs) do
        local active = t == tab; t.Page.Visible = active
        t.Button.BackgroundTransparency = active and 0 or 1
        t.Button.BackgroundColor3 = active and self.Theme.AccentDark or self.Theme.Row
        t.Button.TextColor3 = active and self.Theme.Text or self.Theme.Muted
    end
end

function LunarGui:Notify(options)
    options = type(options) == "string" and {Description = options} or (options or {})
    local toast = new("Frame", {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, 90),
        Size = UDim2.new(0, 270, 0, 76), BackgroundColor3 = self.Theme.Panel, BorderSizePixel = 0, ZIndex = 200}, self.Screen)
    round(toast, 12); outline(toast, self.Theme.Accent)
    local title = label(toast, options.Title or "LunarGui", 13, self.Theme.Text, true); title.Position = UDim2.fromOffset(12, 7); title.Size = UDim2.new(1, -24, 0, 22); title.ZIndex = 201
    local desc = new("TextLabel", {BackgroundTransparency = 1, Text = options.Description or options.Content or "", Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = self.Theme.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -24, 0, 36), ZIndex = 201}, toast)
    tween(toast, {Position = UDim2.new(1, -14, 1, -14)})
    task.delay(options.Duration or 3, function() if toast.Parent then tween(toast, {Position = UDim2.new(1, -14, 1, 90), BackgroundTransparency = 1}); task.delay(.25, function() if toast.Parent then toast:Destroy() end end) end end)
    return toast
end

function LunarGui:SetTheme(theme)
    for k, v in pairs(theme or {}) do self.Theme[k] = v end
    self.Root.BackgroundColor3, self.Top.BackgroundColor3, self.Side.BackgroundColor3 = self.Theme.Background, self.Theme.Panel, self.Theme.Panel
end

function LunarGui:SaveConfig(name)
    name = tostring(name or self.SelectedConfig or "")
    if name == "" then return false, "Config name required" end
    local data = {}
    for id, binding in pairs(self.Bindings) do
        local value = binding.Get()
        if typeof(value) == "EnumItem" then value = value.Name end
        data[id] = value
    end
    self.Configs[name], self.SelectedConfig = data, name
    if self.Persistence and self.Persistence.Save then
        local ok, err = pcall(self.Persistence.Save, name, HttpService:JSONEncode(data))
        if not ok then return false, tostring(err) end
    end
    return true
end
function LunarGui:LoadConfig(name)
    name = tostring(name or self.SelectedConfig or "")
    local data = self.Configs[name]
    if not data and self.Persistence and self.Persistence.Load then
        local ok, raw = pcall(self.Persistence.Load, name)
        if ok and type(raw) == "string" then local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end); if decodedOk then data = decoded; self.Configs[name] = decoded end end
    end
    if type(data) ~= "table" then return false, "Config not found" end
    self.SelectedConfig = name
    for id, value in pairs(data) do local binding = self.Bindings[id]; if binding then pcall(binding.Set, value) end end
    return true
end
function LunarGui:DeleteConfig(name)
    name = tostring(name or self.SelectedConfig or "")
    if not self.Configs[name] then return false end
    self.Configs[name] = nil; if self.SelectedConfig == name then self.SelectedConfig = nil end
    if self.Persistence and self.Persistence.Delete then pcall(self.Persistence.Delete, name) end
    return true
end
function LunarGui:RenameConfig(oldName, newName)
    if not self.Configs[oldName] or self.Configs[newName] or newName == "" then return false end
    self.Configs[newName], self.Configs[oldName] = self.Configs[oldName], nil
    if self.SelectedConfig == oldName then self.SelectedConfig = newName end
    if self.Persistence and self.Persistence.Save then pcall(self.Persistence.Save, newName, HttpService:JSONEncode(self.Configs[newName])) end
    if self.Persistence and self.Persistence.Delete then pcall(self.Persistence.Delete, oldName) end
    return true
end
function LunarGui:ListConfigs()
    local list = {}; for name in pairs(self.Configs) do table.insert(list, name) end; table.sort(list); return list
end
function LunarGui:Destroy()
    for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
    if self.Picker then self.Picker:Destroy() end
    if self.Screen then self.Screen:Destroy() end
end

return LunarGui
