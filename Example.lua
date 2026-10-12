-- LunarGui example (place LunarGui.lua as a ModuleScript and require it)
local LunarGui = require(script.Parent.LunarGui)

local UI = LunarGui.new({
    Name = "LunarGui",
    Subtitle = "MOON-LIGHT LIBRARY",
    -- Roblox ImageLabel needs Roblox image asset IDs, not raw GitHub URLs.
    -- Upload your GitHub logo/background to Roblox and enter the rbxassetid:// IDs here.
    LogoImage = "",
    BackgroundImage = "",
    BackgroundTransparency = 0.9,
})

local Home = UI:CreateTab({Name = "Home", Icon = "⌂"})
local General = Home:CreateSection({Name = "General", DefaultOpen = true})
General:CreateLabel({Name = "Welcome to LunarGui"})
General:CreateToggle({Name = "Example Toggle", Flag = "ExampleToggle", Default = false,
    Callback = function(value) print("Toggle:", value) end})
General:CreateSlider({Name = "Power", Flag = "Power", Min = 0, Max = 100, Default = 50, Decimals = 0,
    Callback = function(value) print("Power:", value) end})
General:CreateDropdown({Name = "Mode", Flag = "Mode", Options = {"Normal", "Fast", "Safe"}, Default = "Normal",
    Callback = function(value) print("Mode:", value) end})
General:CreateTextbox({Name = "Player note", Flag = "PlayerNote", Placeholder = "Type here"})
General:CreateKeybind({Name = "Hotkey", Flag = "Hotkey", Default = Enum.KeyCode.RightShift,
    Callback = function(key) print("Pressed:", key.Name) end})
General:CreateButton({Name = "Show notification", Callback = function()
    UI:Notify({Title = "LunarGui", Description = "Everything is working.", Duration = 3})
end})

local ConfigTab = UI:CreateTab({Name = "Settings", Icon = "⚙"})
local ConfigSection = ConfigTab:CreateSection({Name = "Config Manager", DefaultOpen = true})
local configName = ConfigSection:CreateTextbox({Name = "Config name", Flag = "ConfigName", Placeholder = "MyConfig"})
ConfigSection:CreateButton({Name = "Save Config", Callback = function()
    local ok, err = UI:SaveConfig(configName:Get())
    UI:Notify(ok and "Config saved" or tostring(err))
end})
ConfigSection:CreateButton({Name = "Load Selected Config", Callback = function()
    local ok, err = UI:LoadConfig(UI.SelectedConfig)
    UI:Notify(ok and "Config loaded" or tostring(err))
end})
ConfigSection:CreateButton({Name = "Delete Selected Config", Callback = function()
    local ok = UI:DeleteConfig(UI.SelectedConfig)
    UI:Notify(ok and "Config deleted" or "Select a config first")
end})
