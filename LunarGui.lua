--[[
    LunarGui  |  Premium Interface
    - Window: draggable title bar, resize with the bottom-right grip (live size tip, Compact mode when narrow)
    - Built-in tabs: Overview (profile / Players / Ping / FPS / game info) and Settings (General / Panel / Config)
    - Pass BuiltinTabs = false to LunarGui.new to skip them
    - Traffic lights: red = hide, yellow = reset size, green = maximize / restore
    - Components: Label, Button, Toggle, Slider, Dropdown, Textbox, Keybind
    - Every component accepts  Description  (small grey sub-text)
]]

local LunarGui = {}
LunarGui.__index = LunarGui

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Stats = game:GetService("Stats")

---------------------------------------------------------------------
-- Image download / cache (GitHub etc.)
---------------------------------------------------------------------
local function Http(url)
    local ok, result = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(result) == "string" and result ~= "" then return result end
    local req = (syn and syn.request) or http_request or request
    if req then
        local ok2, response = pcall(req, {Url = url, Method = "GET"})
        if ok2 and type(response) == "table" and response.Body and response.Body ~= "" then return response.Body end
    end
    return nil
end

local function SetCover(imageLabel, url, fileName)
    task.spawn(function()
        if not (writefile and getcustomasset and isfile) then
            warn("[LunarGui] Environment does not support image cache APIs"); return
        end
        if type(url) ~= "string" or url == "" then return end
        fileName = fileName or ("lunar_" .. url:gsub("[^%w]", "_"):sub(-40) .. ".img")
        if isfile(fileName) then
            local ok, asset = pcall(getcustomasset, fileName)
            if ok and asset then
                if imageLabel and imageLabel.Parent then imageLabel.Image = asset end
                return
            end
        end
        local data = Http(url)
        if not data then warn("[LunarGui] Could not load image: " .. tostring(url)); return end
        local wOk, wErr = pcall(writefile, fileName, data)
        if not wOk then warn("[LunarGui] Could not save image: " .. tostring(wErr)); return end
        local aOk, asset = pcall(getcustomasset, fileName)
        if aOk and asset then
            if imageLabel and imageLabel.Parent then imageLabel.Image = asset end
        else
            warn("[LunarGui] Could not convert image: " .. tostring(asset))
        end
    end)
end

-- Default config storage (executor file API). Returns nil when unsupported.
function LunarGui._defaultPersistence(name)
    if not (type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function") then return nil end
    local safe = tostring(name):gsub("[^%w_%-]", "_")
    local folder = "LunarGui_" .. safe
    pcall(function() if makefolder and isfolder and not isfolder(folder) then makefolder(folder) end end)
    local function path(n) return folder .. "/" .. n .. ".json" end
    return {
        Save = function(n, json) writefile(path(n), json) end,
        Load = function(n) if isfile(path(n)) then return readfile(path(n)) end end,
        Delete = function(n) if delfile and isfile(path(n)) then delfile(path(n)) end end,
        List = function()
            local out = {}
            if listfiles then
                local ok, files = pcall(listfiles, folder)
                if ok and type(files) == "table" then
                    for _, f in ipairs(files) do
                        local n = tostring(f):match("([^/\\]+)%.json$")
                        if n then table.insert(out, n) end
                    end
                end
            end
            return out
        end,
    }
end

local DEFAULT_BACKGROUND_URL = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Assets/background.png"

---------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------
LunarGui.Theme = {
    Background = Color3.fromRGB(13, 13, 17),
    Sidebar    = Color3.fromRGB(17, 17, 22),
    Panel      = Color3.fromRGB(22, 22, 28),
    Row        = Color3.fromRGB(31, 31, 38),
    Track      = Color3.fromRGB(58, 58, 70),
    Stroke     = Color3.fromRGB(44, 44, 56),
    Accent     = Color3.fromRGB(139, 92, 246),
    Accent2    = Color3.fromRGB(217, 88, 240),
    AccentDark = Color3.fromRGB(76, 50, 140),
    Text       = Color3.fromRGB(244, 244, 250),
    Muted      = Color3.fromRGB(140, 140, 158),
    Green      = Color3.fromRGB(80, 220, 140),
    Red        = Color3.fromRGB(255, 95, 87),
    Yellow     = Color3.fromRGB(254, 188, 46),
    MacGreen   = Color3.fromRGB(40, 200, 64),
}

local TabColors = {
    Color3.fromRGB(99, 102, 241), Color3.fromRGB(245, 158, 11), Color3.fromRGB(14, 165, 233),
    Color3.fromRGB(16, 185, 129), Color3.fromRGB(236, 72, 153), Color3.fromRGB(239, 68, 68),
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function round(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r or 10)}, o) end
local function stroke(o, color, transparency, thickness)
    return new("UIStroke", {Color = color, Transparency = transparency or 0, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
end
local function gradient(o, c1, c2, rot)
    return new("UIGradient", {Color = ColorSequence.new(c1, c2), Rotation = rot or 0}, o)
end
local function tween(o, props, t, style, dir)
    local tw = TweenService:Create(o, TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end
local function text(parent, props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.GothamSemibold
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    return new("TextLabel", props, parent)
end
local function makeIcon(parent, icon, px, color)
    icon = tostring(icon or "")
    if icon:find("rbxassetid") or icon:find("^%d+$") then
        local id = icon:find("^%d+$") and ("rbxassetid://" .. icon) or icon
        return new("ImageLabel", {BackgroundTransparency = 1, Image = id, ImageColor3 = color or WHITE,
            AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(px, px)}, parent)
    end
    return text(parent, {Text = icon, Font = Enum.Font.GothamBold, TextSize = px, TextColor3 = color or WHITE,
        TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(px + 10, px + 10)})
end

-- Premium moon logo: dark squircle, rotating neon border, glowing moon with craters + sparkle.
-- Custom image: options.LogoUrl / options.LogoImage.   Old crescent look: options.LogoStyle = "crescent"
local function makeLogo(parent, px, options, T)
    local tile = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromOffset(px, px)}, parent)
    round(tile, math.floor(px * .32))
    gradient(tile, Color3.fromRGB(34, 21, 56), Color3.fromRGB(11, 8, 21), 90)
    local ug = new("UIGradient", {Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.Accent), ColorSequenceKeypoint.new(.5, T.Accent2), ColorSequenceKeypoint.new(1, T.Accent)})},
        stroke(tile, WHITE, 0, math.max(1.5, px / 26)))

    if (options.LogoImage and options.LogoImage ~= "") or (options.LogoUrl and options.LogoUrl ~= "") then
        local img = new("ImageLabel", {BackgroundTransparency = 1, Image = options.LogoImage or "", ScaleType = Enum.ScaleType.Fit,
            AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.78, .78)}, tile)
        if options.LogoUrl then SetCover(img, options.LogoUrl, "LunarHub_Logo.png") end
        return tile, ug
    end

    if options.LogoStyle == "crescent" then
        local tileColor = Color3.fromRGB(20, 14, 34)
        tile.BackgroundColor3 = tileColor
        for _, ch in ipairs(tile:GetChildren()) do if ch:IsA("UIGradient") then ch:Destroy() end end
        local moon = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.47, .53), Size = UDim2.fromScale(.56, .56)}, tile)
        round(moon, 999); gradient(moon, WHITE, T.Accent2, 45)
        local cut = new("Frame", {BackgroundColor3 = tileColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.61, .42), Size = UDim2.fromScale(.5, .5)}, tile)
        round(cut, 999)
        return tile, ug
    end

    local d = px * .5
    local moon = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .53), Size = UDim2.fromOffset(d, d)}, tile)
    round(moon, 999)
    gradient(moon, Color3.fromRGB(255, 255, 255), Color3.fromRGB(188, 178, 236), 45)
    stroke(moon, T.Accent2, .55, math.max(2, px / 13))
    for _, c in ipairs({{.56, .16, .24}, {.12, .42, .3}, {.58, .6, .16}}) do
        local crater = new("Frame", {BackgroundColor3 = Color3.fromRGB(198, 190, 232), BorderSizePixel = 0,
            Position = UDim2.fromScale(c[1], c[2]), Size = UDim2.fromScale(c[3], c[3])}, moon)
        round(crater, 999)
    end
    local spark = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.78, .24), Size = UDim2.fromScale(.12, .12), Rotation = 45}, tile)
    round(spark, 1)
    return tile, ug
end

local function pill(parent, label, T, accent, order)
    local p = new("Frame", {BackgroundColor3 = accent and WHITE or T.Row, BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), LayoutOrder = order}, parent)
    round(p, 12)
    if accent then gradient(p, T.Accent, T.Accent2, 0) else stroke(p, T.Stroke, .2, 1) end
    new("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11)}, p)
    text(p, {Text = label, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = accent and WHITE or T.Muted,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0)})
    return p
end

-- A settings row: title + description on the left, room for a control on the right
local function makeRow(parent, T, opts, ctrlW, forceH)
    local hasDesc = opts.Description and opts.Description ~= ""
    local row = new("Frame", {BackgroundColor3 = T.Row, BackgroundTransparency = .05, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, forceH or (hasDesc and 58 or 46))}, parent)
    round(row, 12)
    local st = stroke(row, T.Stroke, .45, 1)
    row.MouseEnter:Connect(function() tween(st, {Color = T.Accent, Transparency = .55}, .2) end)
    row.MouseLeave:Connect(function() tween(st, {Color = T.Stroke, Transparency = .45}, .2) end)
    local title = text(row, {Text = tostring(opts.Name or ""), TextSize = 13, TextColor3 = T.Text,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, hasDesc and 9 or 0),
        Size = UDim2.new(1, -(ctrlW + 28), hasDesc and 0 or 1, hasDesc and 20 or 0)})
    local desc
    if hasDesc then
        desc = text(row, {Text = tostring(opts.Description), Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.Muted,
            TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 29), Size = UDim2.new(1, -(ctrlW + 28), 0, 18)})
    end
    return row, title, desc
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
function LunarGui.new(options)
    options = options or {}
    local self = setmetatable({}, LunarGui)
    self.Name = options.Name or "LunarGui"
    self.Theme = table.clone(LunarGui.Theme)
    for k, v in pairs(options.Theme or {}) do self.Theme[k] = v end
    local T = self.Theme
    self.Values, self.Bindings, self.Tabs, self.Configs = {}, {}, {}, {}
    self.SelectedConfig, self.Persistence, self._connections = nil, options.Persistence, {}
    if self.Persistence == nil then self.Persistence = LunarGui._defaultPersistence(self.Name) end
    self.ShowFloating = true
    self._visible, self._idn = true, 0
    local pg = options.Parent or (player and player:WaitForChild("PlayerGui"))
    assert(pg, "LunarGui requires PlayerGui or options.Parent")

    self.Screen = new("ScreenGui", {Name = self.Name, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = options.DisplayOrder or 40}, pg)

    local function viewport()
        local c = workspace.CurrentCamera
        return c and c.ViewportSize or Vector2.new(1280, 720)
    end
    local LIM = {minW = 340, minH = 260, maxW = 850, maxH = 560, defW = 600, defH = 370}
    self.SizeLimits = LIM
    local function clampSize(w, h)
        local v = viewport()
        local maxW, maxH = math.min(LIM.maxW, v.X - 8), math.min(LIM.maxH, v.Y - 8)
        return math.clamp(w, math.min(LIM.minW, maxW), maxW), math.clamp(h, math.min(LIM.minH, maxH), maxH)
    end
    local function defaultSize()
        return Vector2.new(clampSize(LIM.defW, LIM.defH))
    end
    local function centered(sz)
        local v = viewport()
        return UDim2.fromOffset(math.floor((v.X - sz.X) / 2), math.floor((v.Y - sz.Y) / 2))
    end
    local s0 = options.Size or defaultSize()

    -- Root = invisible holder (position / size / shadow). Window = clipped, rounded surface.
    self.Root = new("Frame", {Name = "Root", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0),
        Position = centered(s0), Size = UDim2.fromOffset(s0.X, s0.Y)}, self.Screen)
    self._scale = new("UIScale", {Scale = .9}, self.Root)
    new("ImageLabel", {Name = "Shadow", BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = .45, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450),
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, 70, 1, 70), ZIndex = 0}, self.Root)
    self.Window = new("CanvasGroup", {Name = "Window", BackgroundColor3 = T.Background, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 1}, self.Root)
    round(self.Window, 16)
    gradient(stroke(self.Window, WHITE, .15, 1.2), T.Stroke, T.Accent, 60)

    -- Background image: always cropped + clipped, so resizing never distorts or breaks it
    self.BG = new("ImageLabel", {Name = "Background", BackgroundTransparency = 1, Image = options.BackgroundImage or "",
        ImageTransparency = options.BackgroundTransparency or .92, ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1), ZIndex = 0}, self.Window)
    round(self.BG, 16)
    if options.BackgroundUrl ~= false then SetCover(self.BG, options.BackgroundUrl or DEFAULT_BACKGROUND_URL, "LunarHub_Background.png") end

    -- Title bar
    self.Top = new("Frame", {Name = "Top", BackgroundColor3 = T.Sidebar, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 50), ZIndex = 3}, self.Window)
    round(self.Top, 16) -- rounded top corners (ClipsDescendants does not round children)
    new("Frame", {BackgroundColor3 = T.Sidebar, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16)}, self.Top)
    new("Frame", {BackgroundColor3 = T.Stroke, BackgroundTransparency = .35, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 2}, self.Top)

    local lights = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 66, 1, 0)}, self.Top)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, lights)
    local glyphs = {}
    local function light(color, glyph, order, fn)
        local b = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = color, BorderSizePixel = 0,
            Size = UDim2.fromOffset(14, 14), LayoutOrder = order}, lights)
        round(b, 7)
        glyphs[#glyphs + 1] = text(b, {Text = glyph, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.fromRGB(50, 25, 25),
            TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, Size = UDim2.fromScale(1, 1)})
        b.Activated:Connect(fn)
    end
    lights.MouseEnter:Connect(function() for _, g in ipairs(glyphs) do tween(g, {TextTransparency = 0}, .15) end end)
    lights.MouseLeave:Connect(function() for _, g in ipairs(glyphs) do tween(g, {TextTransparency = 1}, .15) end end)

    lights.Visible = options.TrafficLights ~= false
    local infoX = options.TrafficLights == false and 16 or 92
    local info = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(infoX, 0), Size = UDim2.new(1, -(infoX + 8), 1, 0)}, self.Top)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, info)
    local logo = makeLogo(info, 30, options, T); logo.LayoutOrder = 1
    self.Title = text(info, {Text = self.Name, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), LayoutOrder = 2})
    gradient(self.Title, WHITE, Color3.fromRGB(226, 205, 255), 0)
    self.TagPill = pill(info, options.Tag or options.Subtitle or "PREMIUM", T, true, 3)
    self.VersionPill = pill(info, options.Version or "v1.0.0", T, false, 4)

    -- Side bar
    self.Side = new("Frame", {Name = "Side", BackgroundColor3 = T.Sidebar, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 50), Size = UDim2.new(0, 190, 1, -50), ZIndex = 2}, self.Window)
    round(self.Side, 16) -- only the bottom-left corner stays rounded
    new("Frame", {BackgroundColor3 = T.Sidebar, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 16)}, self.Side)
    new("Frame", {BackgroundColor3 = T.Sidebar, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 16, 1, 0)}, self.Side)
    new("Frame", {BackgroundColor3 = T.Stroke, BackgroundTransparency = .35, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 2}, self.Side)
    self.TabList = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 12),
        Size = UDim2.new(1, -20, 1, -84), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
        ScrollBarThickness = 0}, self.Side)
    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, self.TabList)

    self.Profile = new("Frame", {BackgroundColor3 = T.Row, BackgroundTransparency = .1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 50)}, self.Side)
    round(self.Profile, 12); stroke(self.Profile, T.Stroke, .45, 1)
    self.Avatar = new("ImageLabel", {BackgroundColor3 = T.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset(9, 8),
        Size = UDim2.fromOffset(34, 34), Image = ""}, self.Profile)
    round(self.Avatar, 17); gradient(stroke(self.Avatar, WHITE, 0, 1.5), T.Accent, T.Accent2, 45)
    self.Dot = new("Frame", {BackgroundColor3 = T.Green, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromOffset(46, 44), Size = UDim2.fromOffset(10, 10), ZIndex = 3}, self.Profile)
    round(self.Dot, 5); stroke(self.Dot, T.Row, 0, 2)
    self.PName = text(self.Profile, {Text = player and player.DisplayName or "Player", TextSize = 12, TextColor3 = T.Text,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -60, 0, 18)})
    self.PHandle = text(self.Profile, {Text = player and ("@" .. player.Name) or "", Font = Enum.Font.Gotham, TextSize = 10,
        TextColor3 = T.Muted, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 26), Size = UDim2.new(1, -60, 0, 16)})
    if player then task.spawn(function()
        local ok, image = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end)
        if ok and self.Avatar.Parent then self.Avatar.Image = image end
    end) end

    self.Content = new("Frame", {Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(190, 50), Size = UDim2.new(1, -190, 1, -50), ZIndex = 2}, self.Window)
    self.ActiveTab = nil

    -- Responsive layout (runs whenever the window is resized)
    local function layout()
        local w = self.Window.AbsoluteSize.X
        if w <= 0 then return end
        local compact = w < 480
        local tight = self.Window.AbsoluteSize.Y < 320
        local sw = compact and 56 or (w < 640 and 160 or 190)
        self.Side.Size = UDim2.new(0, sw, 1, -50)
        self.Content.Position, self.Content.Size = UDim2.fromOffset(sw, 50), UDim2.new(1, -sw, 1, -50)
        local narrow = sw < 150
        self.PName.Visible, self.PHandle.Visible = not narrow, not narrow
        self.Avatar.Position = narrow and UDim2.new(.5, -17, 0, 8) or UDim2.fromOffset(9, 8)
        self.Dot.Position = narrow and UDim2.new(.5, 17, 0, 44) or UDim2.fromOffset(46, 44)
        self.VersionPill.Visible = w >= 580
        self.TagPill.Visible = w >= 480
        self.Title.Visible = w >= 340
        self._iconOnly = compact
        self.Profile.Visible = not tight
        self.TabList.Size = UDim2.new(1, -20, 1, tight and -24 or -84)
        for _, t in ipairs(self.Tabs) do
            t.Label.Visible = not compact
            t.Tile.Position = compact and UDim2.new(.5, -14, 0, 8) or UDim2.fromOffset(8, 8)
        end
    end
    self.Window:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
    layout()

    function self:RefreshFloating()
        if self.ToggleButton then self.ToggleButton.Visible = self.ShowFloating ~= false or not self._visible end
        if self._toggleDot then tween(self._toggleDot, {BackgroundColor3 = self._visible and T.Green or T.Track}, .2) end
    end
    -- Window show / hide
    function self:SetVisible(v)
        self._visible = v and true or false
        self:RefreshFloating()
        if self._tScale then
            tween(self._tScale, {Scale = 1.22}, .1)
            task.delay(.1, function() if self._tScale then tween(self._tScale, {Scale = 1}, .45, Enum.EasingStyle.Back) end end)
        end
        if v then
            self.Root.Visible = true
            self._scale.Scale = .9
            tween(self._scale, {Scale = 1}, .38, Enum.EasingStyle.Back)
        else
            tween(self._scale, {Scale = .9}, .18)
            task.delay(.18, function() if not self._visible and self.Root.Parent then self.Root.Visible = false end end)
        end
    end
    tween(self._scale, {Scale = 1}, .45, Enum.EasingStyle.Back)

    -- Traffic lights
    local maximized, restore = false, nil
    light(T.Red, "×", 1, function() self:SetVisible(false) end)
    light(T.Yellow, "↺", 2, function() maximized = false; self:FitPanel(LIM.defW, LIM.defH, true) end)
    light(T.MacGreen, "+", 3, function()
        if not maximized then
            restore = {self.Root.Position, self.Root.Size}
            maximized = true
            self:FitPanel(LIM.maxW, LIM.maxH, true)
        else
            maximized = false
            if restore then tween(self.Root, {Position = restore[1], Size = restore[2]}, .3) end
        end
    end)

    -- Dragging (title bar)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    self.Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragInput, dragStart, startPos = true, input, input.Position, self.Root.Position
            maximized = false
            local c; c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false; if c then c:Disconnect() end end
            end)
        end
    end)
    table.insert(self._connections, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
            local d, v = input.Position - dragStart, viewport()
            local sz = self.Root.AbsoluteSize
            local x = math.clamp(startPos.X.Offset + d.X, 80 - sz.X, v.X - 80)
            local y = math.clamp(startPos.Y.Offset + d.Y, 0, v.Y - 50)
            self.Root.Position = UDim2.fromOffset(x, y)
        end
    end))

    function self:SetPanelSize(w, h)
        local cw, ch = clampSize(w, h)
        local v = viewport()
        local px, py = self.Root.Position.X.Offset, self.Root.Position.Y.Offset
        self.Root.Size = UDim2.fromOffset(cw, ch)
        self.Root.Position = UDim2.fromOffset(math.clamp(px, 0, math.max(0, v.X - cw)), math.clamp(py, 0, math.max(0, v.Y - ch)))
    end
    function self:FitPanel(w, h, recenter)
        local cw, ch = clampSize(w, h)
        local v = viewport()
        local x, y
        if recenter then
            x, y = (v.X - cw) / 2, (v.Y - ch) / 2
        else
            x = math.clamp(self.Root.Position.X.Offset, 0, math.max(0, v.X - cw))
            y = math.clamp(self.Root.Position.Y.Offset, 0, math.max(0, v.Y - ch))
        end
        tween(self.Root, {Size = UDim2.fromOffset(cw, ch), Position = UDim2.fromOffset(x, y)}, .25)
    end

    -- Resize grip (bottom-right) with a live size tip
    local grip = new("TextButton", {Name = "ResizeGrip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -3),
        Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 100}, self.Window)
    local dots = {}
    for _, p in ipairs({{18, 18}, {18, 11}, {11, 18}, {18, 4}, {4, 18}, {11, 11}}) do
        local d = new("Frame", {BackgroundColor3 = T.Track, BorderSizePixel = 0, Position = UDim2.fromOffset(p[1], p[2]),
            Size = UDim2.fromOffset(3, 3), ZIndex = 101}, grip)
        round(d, 2); dots[#dots + 1] = d
    end
    local gripHover, gripActive = false, false
    local function paintGrip()
        local c = (gripHover or gripActive) and T.Accent2 or T.Track
        for _, d in ipairs(dots) do tween(d, {BackgroundColor3 = c}, .15) end
    end
    grip.MouseEnter:Connect(function() gripHover = true; paintGrip() end)
    grip.MouseLeave:Connect(function() gripHover = false; paintGrip() end)

    local tip = new("Frame", {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -14), AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 26), BackgroundColor3 = T.Panel, Visible = false, ZIndex = 250}, self.Window)
    round(tip, 13); gradient(stroke(tip, WHITE, .1, 1.5), T.Accent, T.Accent2, 45)
    new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, tip)
    local tipLabel = text(tip, {Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.Text,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), ZIndex = 251})
    local tipToken = 0
    local function showTip()
        tipToken = tipToken + 1
        local token = tipToken
        local sz = self.Root.AbsoluteSize
        tipLabel.Text = string.format("%d × %d%s", sz.X, sz.Y, sz.X < 480 and "  ·  Compact" or "")
        tip.Visible = true
        task.delay(.9, function() if token == tipToken and tip.Parent and not gripActive then tip.Visible = false end end)
    end

    local gInput, gStart, gSize = nil, nil, nil
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            gInput, gStart, gSize = input, input.Position, self.Root.AbsoluteSize
            gripActive, maximized = true, false
            paintGrip()
        end
    end)
    table.insert(self._connections, UIS.InputChanged:Connect(function(input)
        if gInput and ((gInput.UserInputType == Enum.UserInputType.Touch and input == gInput)
            or (gInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local d = input.Position - gStart
            self:SetPanelSize(gSize.X + d.X, gSize.Y + d.Y)
            showTip()
        end
    end))
    table.insert(self._connections, UIS.InputEnded:Connect(function(input)
        if gInput and (input == gInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
            gInput, gripActive = nil, false
            paintGrip(); showTip()
        end
    end))

    -- Keep the window inside the screen when the viewport changes
    local function fitViewport()
        local sz = self.Root.AbsoluteSize
        self:SetPanelSize(sz.X, sz.Y)
    end
    if workspace.CurrentCamera then
        table.insert(self._connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitViewport))
    end

    -- Floating logo button: tap = show / hide, drag = move. Always kept inside the screen.
    local TOG = 56
    local vp0 = viewport()
    local tCenter = Vector2.new(vp0.X - TOG / 2 - 16, vp0.Y * .42)
    self.ToggleButton = new("TextButton", {Name = "LunarGuiToggle", AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(tCenter.X, tCenter.Y), Size = UDim2.fromOffset(TOG, TOG), ZIndex = 300}, self.Screen)
    local tGlow = new("ImageLabel", {BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = T.Accent, ImageTransparency = .55,
        ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450), AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, 38, 1, 38)}, self.ToggleButton)
    TweenService:Create(tGlow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {ImageTransparency = .82}):Play()
    local logoTile, logoGrad = makeLogo(self.ToggleButton, TOG, options, T)
    if logoGrad then
        self._spin = TweenService:Create(logoGrad, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 405})
        self._spin:Play()
    end
    local dotStatus = new("Frame", {BackgroundColor3 = T.Green, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -1, 0, 1), Size = UDim2.fromOffset(13, 13), ZIndex = 5}, self.ToggleButton)
    round(dotStatus, 7); stroke(dotStatus, T.Background, 0, 2)
    self._toggleDot = dotStatus
    local tScale = new("UIScale", {Scale = 1}, self.ToggleButton)
    self._tScale = tScale

    local function setToggle(v)
        local vs, half = viewport(), TOG / 2 + 6
        tCenter = Vector2.new(math.clamp(v.X, half, math.max(half, vs.X - half)), math.clamp(v.Y, half, math.max(half, vs.Y - half)))
        self.ToggleButton.Position = UDim2.fromOffset(tCenter.X, tCenter.Y)
    end
    setToggle(tCenter)
    if workspace.CurrentCamera then
        table.insert(self._connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() setToggle(tCenter) end))
    end

    self.ToggleButton.MouseEnter:Connect(function() tween(tScale, {Scale = 1.08}, .2, Enum.EasingStyle.Back) end)
    self.ToggleButton.MouseLeave:Connect(function() tween(tScale, {Scale = 1}, .2) end)
    local fInput, fStart, fOrigin, fMoved = nil, nil, nil, false
    self.ToggleButton.InputBegan:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not fInput then
            fInput, fStart, fOrigin, fMoved = input, input.Position, tCenter, false
            tween(tScale, {Scale = .9}, .1)
        end
    end)
    table.insert(self._connections, UIS.InputChanged:Connect(function(input)
        if fInput and ((fInput.UserInputType == Enum.UserInputType.Touch and input == fInput)
            or (fInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local d = input.Position - fStart
            if fMoved or d.Magnitude > 10 then fMoved = true; setToggle(fOrigin + Vector2.new(d.X, d.Y)) end
        end
    end))
    table.insert(self._connections, UIS.InputEnded:Connect(function(input)
        if fInput and (input == fInput or (fInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
            local moved = fMoved
            fInput = nil
            tween(tScale, {Scale = 1}, .3, Enum.EasingStyle.Back)
            if not moved then self:SetVisible(not self._visible) end
        end
    end))
    self:RefreshFloating()

    if options.BuiltinTabs ~= false then
        self:_buildOverview(options)
        self:_buildSettings(options)
    end
    return self
end

---------------------------------------------------------------------
-- Tabs / Sections / Components
---------------------------------------------------------------------
function LunarGui:CreateTab(options)
    options = options or {}
    local gui, T = self, self.Theme
    local tab = {Name = options.Name or ("Tab" .. (#self.Tabs + 1)), Icon = options.Icon or "✦", Sections = {}}
    local color = options.Color or TabColors[(#self.Tabs % #TabColors) + 1]
    local order = options.Order
    if not order then self._userTabN = (self._userTabN or 0) + 1; order = self._userTabN end

    tab.Button = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = T.Row, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order}, self.TabList)
    round(tab.Button, 12)
    tab.Stroke = stroke(tab.Button, T.Stroke, 1, 1)
    local tile = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(28, 28)}, tab.Button)
    round(tile, 8); gradient(tile, color:Lerp(WHITE, .3), color:Lerp(Color3.new(0, 0, 0), .2), 90)
    tab.Tile = tile
    if gui._iconOnly then tile.Position = UDim2.new(.5, -14, 0, 8) end
    makeIcon(tile, tab.Icon, 15, WHITE)
    tab.Label = text(tab.Button, {Text = tab.Name, TextSize = 13, TextColor3 = T.Muted, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -52, 1, 0)})
    tab.Label.Visible = not gui._iconOnly
    tab.Button.MouseEnter:Connect(function()
        if gui.ActiveTab ~= tab then tween(tab.Button, {BackgroundTransparency = .6}, .15); tween(tab.Label, {TextColor3 = T.Text}, .15) end
    end)
    tab.Button.MouseLeave:Connect(function()
        if gui.ActiveTab ~= tab then tween(tab.Button, {BackgroundTransparency = 1}, .15); tween(tab.Label, {TextColor3 = T.Muted}, .15) end
    end)

    tab.Page = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Accent, ScrollBarImageTransparency = .3, Visible = false}, self.Content)
    new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 20)}, tab.Page)
    new("UIListLayout", {Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder}, tab.Page)

    function tab:CreateSection(opts)
        opts = opts or {}
        local section = {Gui = gui, Tab = self, Name = opts.Name or "Section", Open = opts.DefaultOpen ~= false, Components = {}}
        section.Frame = new("Frame", {BackgroundColor3 = T.Panel, BackgroundTransparency = .04, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = #self.Sections + 1}, self.Page)
        round(section.Frame, 16); stroke(section.Frame, T.Stroke, .35, 1)
        new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, section.Frame)

        section.Header = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 1}, section.Frame)
        local titleX = 16
        if opts.Icon then
            local holder = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(24, 24)}, section.Header)
            makeIcon(holder, opts.Icon, 17, T.Accent)
            titleX = 46
        end
        text(section.Header, {Text = section.Name, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.Text,
            Position = UDim2.fromOffset(titleX, 0), Size = UDim2.new(1, -(titleX + 44), 1, 0)})
        local chev = text(section.Header, {Text = "›", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = T.Muted,
            TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(1, -26, .5, 0),
            Size = UDim2.fromOffset(24, 24), Rotation = section.Open and -90 or 90})
        section.Header.MouseEnter:Connect(function() tween(chev, {TextColor3 = T.Accent}, .15) end)
        section.Header.MouseLeave:Connect(function() tween(chev, {TextColor3 = T.Muted}, .15) end)

        section.Clip = new("Frame", {BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2}, section.Frame)
        section.Body = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, section.Clip)
        new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12)}, section.Body)
        new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, section.Body)
        section.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if section.Open then section.Clip.Size = UDim2.new(1, 0, 0, section.Body.AbsoluteSize.Y) end
        end)
        section.Header.Activated:Connect(function()
            section.Open = not section.Open
            tween(chev, {Rotation = section.Open and -90 or 90}, .28, Enum.EasingStyle.Back)
            tween(section.Clip, {Size = UDim2.new(1, 0, 0, section.Open and section.Body.AbsoluteSize.Y or 0)}, .3)
        end)

        local function nextId(prefix) gui._idn = gui._idn + 1; return prefix .. gui._idn end
        function section:_register(id, setter, getter, kind)
            if gui._noSave then return end
            gui.Bindings[id] = {Set = setter, Get = getter, Type = kind}
            if gui.Values[id] == nil then gui.Values[id] = getter() end
            table.insert(self.Components, id)
        end

        function section:CreateLabel(o)
            o = type(o) == "string" and {Name = o} or (o or {})
            local l = text(self.Body, {Text = o.Name or o.Text or "Label", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = T.Muted,
                TextWrapped = true, Size = UDim2.new(1, 0, 0, o.Height or 22)})
            return {SetText = function(_, v) l.Text = tostring(v) end, Instance = l}
        end

        function section:CreateButton(o)
            o = o or {}
            local row = makeRow(self.Body, T, o, 30)
            local arrow = text(row, {Text = "›", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = T.Accent,
                TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(20, 24)})
            local sc = new("UIScale", {Scale = 1}, row)
            local hit = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5}, row)
            hit.MouseEnter:Connect(function() tween(row, {BackgroundColor3 = T.AccentDark}, .2); tween(arrow, {Position = UDim2.new(1, -6, .5, 0)}, .2) end)
            hit.MouseLeave:Connect(function() tween(row, {BackgroundColor3 = T.Row}, .2); tween(arrow, {Position = UDim2.new(1, -10, .5, 0)}, .2); tween(sc, {Scale = 1}, .12) end)
            hit.MouseButton1Down:Connect(function() tween(sc, {Scale = .975}, .08) end)
            hit.MouseButton1Up:Connect(function() tween(sc, {Scale = 1}, .18, Enum.EasingStyle.Back) end)
            hit.Activated:Connect(function() if o.Callback then task.spawn(o.Callback) end end)
            return {Instance = row}
        end

        function section:CreateToggle(o)
            o = o or {}; local id = o.Flag or o.Name or nextId("Toggle")
            local row = makeRow(self.Body, T, o, 56)
            local track = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = T.Track, AnchorPoint = Vector2.new(1, .5),
                Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(46, 26)}, row)
            round(track, 13)
            local knob = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(20, 20)}, track)
            round(knob, 10)
            local value = o.Default == true
            local function set(v, silent)
                value = v == true
                tween(track, {BackgroundColor3 = value and T.Accent or T.Track}, .22)
                tween(knob, {Position = value and UDim2.new(1, -23, 0, 3) or UDim2.fromOffset(3, 3)}, .28, Enum.EasingStyle.Back)
                gui.Values[id] = value
                if not silent and o.Callback then task.spawn(o.Callback, value) end
            end
            track.Activated:Connect(function() set(not value) end)
            set(value, true)
            self:_register(id, function(v) set(v, true) end, function() return value end, "Toggle")
            return {Set = set, Get = function() return value end, Instance = row}
        end

        function section:CreateSlider(o)
            o = o or {}; local id = o.Flag or o.Name or nextId("Slider")
            local min, max = tonumber(o.Min) or 0, tonumber(o.Max) or 100
            if max < min then min, max = max, min end
            local dec = math.max(0, math.floor(tonumber(o.Decimals) or 0)); local factor = 10 ^ dec
            local row = makeRow(self.Body, T, o, 200)
            local box = new("TextBox", {ClearTextOnFocus = false, Text = tostring(o.Default or min), Font = Enum.Font.GothamMedium, TextSize = 12,
                TextColor3 = T.Muted, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, .5),
                Position = UDim2.new(1, -150, .5, 0), Size = UDim2.fromOffset(46, 24)}, row)
            local bar = new("Frame", {BackgroundColor3 = T.Track, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5),
                Position = UDim2.new(1, -18, .5, 0), Size = UDim2.fromOffset(122, 6)}, row)
            round(bar, 3)
            local fill = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0)}, bar)
            round(fill, 3); gradient(fill, T.Accent, T.Accent2, 0)
            local knob = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
                Position = UDim2.fromScale(1, .5), Size = UDim2.fromOffset(18, 18), ZIndex = 3}, fill)
            round(knob, 9); stroke(knob, Color3.new(0, 0, 0), .75, 3)
            local hit = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5),
                Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, 20, 0, 32)}, bar)
            local value = min
            local function set(v, silent)
                v = tonumber(v); if not v then return false end
                v = math.floor(math.clamp(v, min, max) * factor + .5) / factor; value = v
                tween(fill, {Size = UDim2.new(max == min and 0 or (v - min) / (max - min), 0, 1, 0)}, .08)
                box.Text = tostring(v); gui.Values[id] = v
                if not silent and o.Callback then task.spawn(o.Callback, v) end
                return true
            end
            local function fromX(x) set(min + (max - min) * math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)) end
            local sliding = false
            hit.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    sliding = true; tween(knob, {Size = UDim2.fromOffset(22, 22)}, .12); fromX(i.Position.X)
                end
            end)
            table.insert(gui._connections, UIS.InputChanged:Connect(function(i)
                if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
            end))
            table.insert(gui._connections, UIS.InputEnded:Connect(function(i)
                if sliding and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                    sliding = false; tween(knob, {Size = UDim2.fromOffset(18, 18)}, .15)
                end
            end))
            box.FocusLost:Connect(function() if not set(box.Text) then box.Text = tostring(value) end end)
            set(o.Default or min, true)
            self:_register(id, function(v) set(v, true) end, function() return value end, "Slider")
            return {Set = set, Get = function() return value end, Instance = row}
        end

        function section:CreateDropdown(o)
            o = o or {}; local id = o.Flag or o.Name or nextId("Dropdown")
            local row = makeRow(self.Body, T, o, 150)
            local value = o.Default
            local pillBtn = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = T.Panel, AnchorPoint = Vector2.new(1, .5),
                Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(130, 30)}, row)
            round(pillBtn, 9); stroke(pillBtn, T.Stroke, .3, 1)
            local chosen = text(pillBtn, {Text = value and tostring(value) or "Select...", Font = Enum.Font.GothamMedium, TextSize = 12,
                TextColor3 = value and T.Text or T.Muted, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0)})
            text(pillBtn, {Text = "⌄", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = T.Accent, TextXAlignment = Enum.TextXAlignment.Center,
                Position = UDim2.new(1, -24, 0, 0), Size = UDim2.fromOffset(20, 30)})
            local function picker()
                if gui.Picker then gui.Picker:Destroy() end
                local overlay = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1), ZIndex = 100}, gui.Screen)
                gui.Picker = overlay
                tween(overlay, {BackgroundTransparency = .45}, .2)
                local modal = new("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(.86, 0, .68, 0),
                    BackgroundColor3 = T.Panel, BorderSizePixel = 0}, overlay)
                new("UISizeConstraint", {MinSize = Vector2.new(250, 240), MaxSize = Vector2.new(420, 500)}, modal)
                round(modal, 18); gradient(stroke(modal, WHITE, .2, 1.5), T.Accent, T.Accent2, 45)
                local ms = new("UIScale", {Scale = .9}, modal); tween(ms, {Scale = 1}, .3, Enum.EasingStyle.Back)
                text(modal, {Text = o.Name or "Choose one", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.Text,
                    Position = UDim2.fromOffset(18, 6), Size = UDim2.new(1, -64, 0, 40)})
                local close = new("TextButton", {Text = "×", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = T.Muted, BackgroundTransparency = 1,
                    Position = UDim2.new(1, -44, 0, 6), Size = UDim2.fromOffset(36, 36)}, modal)
                local list = new("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 50),
                    Size = UDim2.new(1, -20, 1, -60), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = 3, ScrollBarImageColor3 = T.Accent}, modal)
                new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)
                local function closePicker() if overlay.Parent then overlay:Destroy() end gui.Picker = nil end
                overlay.Activated:Connect(closePicker); close.Activated:Connect(closePicker)
                for n, item in ipairs(o.Options or {}) do
                    local sel = item == value
                    local b = new("TextButton", {AutoButtonColor = false, Text = "", BackgroundColor3 = sel and T.AccentDark or T.Row, BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 42), LayoutOrder = n}, list)
                    round(b, 10)
                    text(b, {Text = tostring(item), TextSize = 13, TextColor3 = T.Text, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -50, 1, 0)})
                    text(b, {Text = sel and "✓" or "", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Center,
                        Position = UDim2.new(1, -34, 0, 0), Size = UDim2.fromOffset(22, 42)})
                    b.MouseEnter:Connect(function() if item ~= value then tween(b, {BackgroundColor3 = T.Track}, .12) end end)
                    b.MouseLeave:Connect(function() if item ~= value then tween(b, {BackgroundColor3 = T.Row}, .12) end end)
                    b.Activated:Connect(function()
                        value = item; chosen.Text = tostring(item); chosen.TextColor3 = T.Text; gui.Values[id] = item
                        if o.Callback then task.spawn(o.Callback, item) end
                        closePicker()
                    end)
                end
            end
            pillBtn.Activated:Connect(picker)
            self:_register(id, function(v) value = v; chosen.Text = v == nil and "Select..." or tostring(v) end, function() return value end, "Dropdown")
            return {Get = function() return value end, Open = picker, Instance = row,
                Clear = function() value = nil; chosen.Text = "Select..."; chosen.TextColor3 = T.Muted end,
                Set = function(v) for _, x in ipairs(o.Options or {}) do if x == v then value = v; chosen.Text = tostring(v); chosen.TextColor3 = T.Text; gui.Values[id] = v; return true end end return false end}
        end

        function section:CreateTextbox(o)
            o = o or {}; local id = o.Flag or o.Name or nextId("Textbox")
            local row = makeRow(self.Body, T, o, 170)
            local box = new("TextBox", {ClearTextOnFocus = false, Text = tostring(o.Default or ""), PlaceholderText = o.Placeholder or "Type here",
                Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = T.Text, PlaceholderColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left,
                BackgroundColor3 = T.Panel, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(152, 30)}, row)
            round(box, 9); local bs = stroke(box, T.Stroke, .3, 1)
            new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, box)
            box.Focused:Connect(function() tween(bs, {Color = T.Accent, Transparency = 0}, .15) end)
            local val = box.Text
            box.FocusLost:Connect(function(enter)
                tween(bs, {Color = T.Stroke, Transparency = .3}, .15)
                val = box.Text; gui.Values[id] = val
                if o.Callback then task.spawn(o.Callback, val, enter) end
            end)
            self:_register(id, function(v) val = tostring(v or ""); box.Text = val end, function() return val end, "Textbox")
            return {Get = function() return val end, Set = function(v) val = tostring(v or ""); box.Text = val; gui.Values[id] = val end, Instance = row}
        end

        function section:CreateKeybind(o)
            o = o or {}; local id = o.Flag or o.Name or nextId("Keybind")
            local row = makeRow(self.Body, T, o, 100)
            local key = o.Default or Enum.KeyCode.RightShift; local listening = false
            local b = new("TextButton", {AutoButtonColor = false, Text = key.Name, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.Text,
                BackgroundColor3 = T.Panel, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(88, 30)}, row)
            round(b, 9); local bs = stroke(b, T.Stroke, .3, 1)
            b.Activated:Connect(function() listening = true; b.Text = "Press key"; tween(bs, {Color = T.Accent, Transparency = 0}, .15) end)
            table.insert(gui._connections, UIS.InputBegan:Connect(function(input, processed)
                if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                    key = input.KeyCode; listening = false; b.Text = key.Name; gui.Values[id] = key.Name
                    tween(bs, {Color = T.Stroke, Transparency = .3}, .15)
                elseif not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key and o.Callback then
                    task.spawn(o.Callback, key)
                end
            end))
            self:_register(id, function(v)
                if typeof(v) == "EnumItem" then key = v elseif Enum.KeyCode[tostring(v)] then key = Enum.KeyCode[tostring(v)] end
                b.Text = key.Name
            end, function() return key.Name end, "Keybind")
            return {Get = function() return key end, Instance = row}
        end

        table.insert(self.Sections, section)
        return section
    end

    tab.Button.Activated:Connect(function() gui:SelectTab(tab) end)
    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function LunarGui:SelectTab(tab)
    if type(tab) == "string" then for _, t in ipairs(self.Tabs) do if t.Name == tab then tab = t break end end end
    if type(tab) ~= "table" then return end
    local T = self.Theme
    self.ActiveTab = tab
    for _, t in ipairs(self.Tabs) do
        local active = t == tab
        if active and not t.Page.Visible then
            t.Page.Position = UDim2.fromOffset(0, 18)
            t.Page.Visible = true
            tween(t.Page, {Position = UDim2.fromOffset(0, 0)}, .4, Enum.EasingStyle.Quint)
        elseif not active then
            t.Page.Visible = false
        end
        tween(t.Button, {BackgroundTransparency = active and .05 or 1}, .2)
        tween(t.Stroke, {Transparency = active and .35 or 1}, .2)
        tween(t.Label, {TextColor3 = active and T.Text or T.Muted}, .2)
    end
end

---------------------------------------------------------------------
-- Notifications (stack bottom-right)
---------------------------------------------------------------------
function LunarGui:Notify(options)
    options = type(options) == "string" and {Description = options} or (options or {})
    local T = self.Theme
    self._toasts = self._toasts or {}
    local function yFor(i) return -(16 + (i - 1) * 86) end
    local idx = #self._toasts + 1
    local toast = new("Frame", {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 320, 1, yFor(idx)), Size = UDim2.fromOffset(290, 76),
        BackgroundColor3 = T.Panel, BorderSizePixel = 0, ZIndex = 200}, self.Screen)
    round(toast, 14); gradient(stroke(toast, WHITE, .2, 1.2), T.Accent, T.Accent2, 45)
    local bar = new("Frame", {BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 14), Size = UDim2.new(0, 3, 1, -28)}, toast)
    round(bar, 2); gradient(bar, T.Accent2, T.Accent, 90)
    text(toast, {Text = options.Title or "LunarGui", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.Text,
        Position = UDim2.fromOffset(24, 9), Size = UDim2.new(1, -36, 0, 20)})
    text(toast, {Text = options.Description or options.Content or "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.Muted, TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(24, 30), Size = UDim2.new(1, -36, 0, 32)})
    local life = options.Duration or 3
    local prog = new("Frame", {BackgroundColor3 = T.Accent2, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -5), Size = UDim2.new(1, -32, 0, 2)}, toast)
    round(prog, 1)
    TweenService:Create(prog, TweenInfo.new(life, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 2)}):Play()
    table.insert(self._toasts, toast)
    tween(toast, {Position = UDim2.new(1, -16, 1, yFor(idx))}, .45, Enum.EasingStyle.Back)
    task.delay(life, function()
        if not toast.Parent then return end
        local at = table.find(self._toasts, toast)
        if at then table.remove(self._toasts, at) end
        tween(toast, {Position = UDim2.new(1, 320, 1, toast.Position.Y.Offset)}, .3)
        for i, t in ipairs(self._toasts) do tween(t, {Position = UDim2.new(1, -16, 1, yFor(i))}, .3) end
        task.delay(.35, function() if toast.Parent then toast:Destroy() end end)
    end)
    return toast
end

function LunarGui:SetTheme(theme)
    for k, v in pairs(theme or {}) do self.Theme[k] = v end
    self.Window.BackgroundColor3 = self.Theme.Background
    self.Top.BackgroundColor3, self.Side.BackgroundColor3 = self.Theme.Sidebar, self.Theme.Sidebar
end

---------------------------------------------------------------------
-- Configs
---------------------------------------------------------------------
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
        if ok and type(raw) == "string" then
            local dOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
            if dOk then data = decoded; self.Configs[name] = decoded end
        end
    end
    if type(data) ~= "table" then return false, "Config not found" end
    self.SelectedConfig = name
    for id, value in pairs(data) do local binding = self.Bindings[id]; if binding then pcall(binding.Set, value) end end
    return true
end
function LunarGui:DeleteConfig(name)
    name = tostring(name or self.SelectedConfig or "")
    if name == "" then return false end
    local had = self.Configs[name] ~= nil
    self.Configs[name] = nil
    if self.SelectedConfig == name then self.SelectedConfig = nil end
    if self.Persistence and self.Persistence.Delete then
        local ok = pcall(self.Persistence.Delete, name)
        had = had or ok
    end
    return had
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
    local set, list = {}, {}
    for name in pairs(self.Configs) do set[name] = true end
    if self.Persistence and self.Persistence.List then
        local ok, names = pcall(self.Persistence.List)
        if ok and type(names) == "table" then for _, n in ipairs(names) do set[n] = true end end
    end
    for name in pairs(set) do table.insert(list, name) end
    table.sort(list)
    return list
end
function LunarGui:Destroy()
    if self._spin then pcall(function() self._spin:Cancel() end) end
    for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
    if self.Picker then self.Picker:Destroy() end
    if self.Screen then self.Screen:Destroy() end
end

---------------------------------------------------------------------
-- Built-in tabs
---------------------------------------------------------------------
function LunarGui:_buildOverview(options)
    local gui, T = self, self.Theme
    local tab = self:CreateTab({Name = "Overview", Icon = "⌂", Color = TabColors[1], Order = 0})
    local sec = tab:CreateSection({Name = "Overview", Icon = "◈"})
    local body, n = sec.Body, 0
    local function ord(o) n = n + 1; o.LayoutOrder = n; return o end

    -- Profile card
    local card = ord(new("Frame", {BackgroundColor3 = T.Row, BackgroundTransparency = .05, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 76)}, body))
    round(card, 12); stroke(card, T.Stroke, .45, 1)
    local avatar = new("ImageLabel", {BackgroundColor3 = T.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(56, 56)}, card)
    round(avatar, 28); gradient(stroke(avatar, WHITE, 0, 2), T.Accent, T.Accent2, 45)
    text(card, {Text = player and player.DisplayName or "Player", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.Text,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(78, 9), Size = UDim2.new(1, -170, 0, 20)})
    text(card, {Text = player and ("@" .. player.Name) or "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.Muted,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(78, 29), Size = UDim2.new(1, -170, 0, 16)})
    text(card, {Text = player and ("Account Age: " .. player.AccountAge .. " days") or "", Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = T.Muted,
        TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(78, 47), Size = UDim2.new(1, -170, 0, 16)})
    local badge = new("Frame", {BackgroundColor3 = Color3.fromRGB(15, 35, 20), BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5),
        Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(80, 24)}, card)
    round(badge, 12); stroke(badge, Color3.fromRGB(60, 160, 80), .2, 1)
    local dot = new("Frame", {BackgroundColor3 = T.Green, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5),
        Position = UDim2.new(0, 12, .5, 0), Size = UDim2.fromOffset(6, 6)}, badge)
    round(dot, 3)
    text(badge, {Text = "ONLINE", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = T.Green, Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -26, 1, 0)})
    if player then task.spawn(function()
        local ok, image = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180) end)
        if ok and avatar.Parent then avatar.Image = image end
    end) end

    -- Stat tiles
    local tiles = ord(new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60)}, body))
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, tiles)
    local function tile(label, i)
        local f = new("Frame", {BackgroundColor3 = T.Row, BackgroundTransparency = .05, BorderSizePixel = 0, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i}, tiles)
        round(f, 12); stroke(f, T.Stroke, .45, 1)
        local v = text(f, {Text = "-", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Center,
            Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 26)})
        text(f, {Text = string.upper(label), Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center,
            Position = UDim2.fromOffset(0, 37), Size = UDim2.new(1, 0, 0, 14)})
        return v
    end
    local playersV, pingV, fpsV = tile("Players", 1), tile("Ping", 2), tile("FPS", 3)

    -- Game info rows
    local function info(name)
        local row = ord(makeRow(body, T, {Name = name}, 190, 40))
        return text(row, {Text = "-", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(180, 30)})
    end
    local gameV, placeV, serverV = info("Game"), info("Place ID"), info("Server")
    gameV.Text = options.GameName or game.Name
    placeV.Text = tostring(game.PlaceId)
    serverV.Text = game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "Studio"
    if not options.GameName then task.spawn(function()
        local ok, infoData = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if ok and infoData and infoData.Name and gameV.Parent then gameV.Text = infoData.Name end
    end) end

    -- Live stats
    local acc, frames = 0, 0
    table.insert(self._connections, RunService.Heartbeat:Connect(function(dt)
        acc, frames = acc + dt, frames + 1
        if acc >= .5 then fpsV.Text = tostring(math.floor(frames / acc + .5)); acc, frames = 0, 0 end
    end))
    task.spawn(function()
        while gui.Screen and gui.Screen.Parent do
            playersV.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
            local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
            pingV.Text = (ok and ping) and (math.floor(ping) .. "ms") or "N/A"
            task.wait(1)
        end
    end)
    return tab
end

function LunarGui:_buildSettings(options)
    local gui = self
    gui._noSave = true -- settings controls are not part of saved configs
    local tab = self:CreateTab({Name = "Settings", Icon = "⚙", Color = Color3.fromRGB(20, 184, 166), Order = 9999})

    local general = tab:CreateSection({Name = "General", Icon = "⚙"})
    general:CreateToggle({Name = "Show Floating Button", Description = "แสดงปุ่มพระจันทร์ลอยบนหน้าจอ", Default = true,
        Callback = function(on) gui.ShowFloating = on; gui:RefreshFloating() end})
    general:CreateToggle({Name = "Background Image", Description = "เปิด/ปิดภาพพื้นหลังของหน้าต่าง", Default = true,
        Callback = function(on) gui.BG.Visible = on end})
    general:CreateKeybind({Name = "Toggle UI", Description = "กดเพื่อซ่อน/แสดงหน้าต่าง", Default = Enum.KeyCode.RightShift,
        Callback = function() gui:SetVisible(not gui._visible) end})

    local panel = tab:CreateSection({Name = "Panel", Icon = "▣"})
    local L = gui.SizeLimits
    local sizeMap = {Compact = {L.minW, L.minH}, Default = {L.defW, L.defH}, Large = {L.maxW, L.maxH}}
    local sizeDD = panel:CreateDropdown({Name = "Panel Size", Description = "เลือกขนาดหน้าต่างสำเร็จรูป", Options = {"Compact", "Default", "Large"}, Default = "Default",
        Callback = function(v) local sz = sizeMap[v]; if sz then gui:FitPanel(sz[1], sz[2], false) end end})
    panel:CreateButton({Name = "Reset Interface", Description = "คืนขนาดและตำแหน่งเริ่มต้น",
        Callback = function() gui:FitPanel(L.defW, L.defH, true); sizeDD.Set("Default"); gui:SelectTab("Overview") end})

    local cfg = tab:CreateSection({Name = "Config", Icon = "💾"})
    local cfgOptions = {}
    local nameBox = cfg:CreateTextbox({Name = "Config Name", Description = "ตั้งชื่อก่อนกดบันทึก", Placeholder = "my_config"})
    local listDD
    local function clean(nm)
        nm = tostring(nm or ""):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        return (nm)
    end
    local function refresh()
        for i = #cfgOptions, 1, -1 do cfgOptions[i] = nil end
        for _, nm in ipairs(gui:ListConfigs()) do table.insert(cfgOptions, nm) end
        if not (gui.SelectedConfig and listDD.Set(gui.SelectedConfig)) then listDD.Clear() end
    end
    local function say(msg) gui:Notify({Title = "Config", Description = msg}) end
    listDD = cfg:CreateDropdown({Name = "Saved Configs", Description = "เลือก config ที่บันทึกไว้", Options = cfgOptions,
        Callback = function(v) gui.SelectedConfig = v; nameBox.Set(v) end})
    cfg:CreateButton({Name = "Save Config", Description = "บันทึกค่าทุกตัวเลือกในตอนนี้", Callback = function()
        local nm = clean(nameBox.Get())
        if nm == "" then nm = gui.SelectedConfig or "" end
        if nm == "" then return say("ใส่ชื่อ config ก่อนครับ") end
        local ok, err = gui:SaveConfig(nm)
        refresh()
        say(ok and ("บันทึก '" .. nm .. "' แล้ว") or ("บันทึกไม่สำเร็จ: " .. tostring(err)))
    end})
    cfg:CreateButton({Name = "Load Config", Description = "โหลดค่าจาก config ที่เลือก", Callback = function()
        local nm = gui.SelectedConfig or clean(nameBox.Get())
        if nm == "" then return say("เลือก config ก่อนครับ") end
        local ok, err = gui:LoadConfig(nm)
        say(ok and ("โหลด '" .. nm .. "' แล้ว") or ("โหลดไม่สำเร็จ: " .. tostring(err)))
    end})
    cfg:CreateButton({Name = "Delete Config", Description = "ลบ config ที่เลือก", Callback = function()
        local nm = gui.SelectedConfig or clean(nameBox.Get())
        if nm == "" then return say("เลือก config ก่อนครับ") end
        local ok = gui:DeleteConfig(nm)
        refresh()
        say(ok and ("ลบ '" .. nm .. "' แล้ว") or "ไม่พบ config นี้")
    end})
    cfg:CreateButton({Name = "Refresh List", Description = "โหลดรายการ config ใหม่", Callback = refresh})
    refresh()

    gui._noSave = false
    return tab
end

return LunarGui
