local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ENV = (type(getgenv) == "function" and getgenv()) or _G

local CONFIG = {

	LibraryUrl = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Library.lua",

	LibraryFile = "LUNAR_Library.lua",
	Retries = 3,
	RetryDelay = 1.5,

	Systems = { Farm = true },

	PlaceIds = {},
	GameName = nil,

	-- Config/settings namespace. Each distinct Id gets its own save files
	-- (LunarHub_Settings_<Id>.json, LunarHub/configs/<Id>/*.json), so running
	-- this loader in two different games never mixes their saved configs.
	-- Leave nil to auto-use the current PlaceId.
	Id = nil,
}

do
	local override = rawget(ENV, "LunarLoaderConfig")
	if type(override) == "table" then
		for key, value in pairs(override) do
			if type(value) == "table" and type(CONFIG[key]) == "table" then
				for k, v in pairs(value) do
					CONFIG[key][k] = v
				end
			else
				CONFIG[key] = value
			end
		end
	end
end

local function log(...)
	print("[LUNAR Loader]", ...)
end

if not Players.LocalPlayer then
	warn("[LUNAR Loader] Must run on the client")
	return
end

if #CONFIG.PlaceIds > 0 and not table.find(CONFIG.PlaceIds, game.PlaceId) then
	warn("[LUNAR Loader] This place is not supported: " .. tostring(game.PlaceId))
	return
end

if type(ENV.LunarLoader) == "table" and type(ENV.LunarLoader.Unload) == "function" then
	pcall(ENV.LunarLoader.Unload)
end

local function compile(source, label)
	local fn, err = loadstring(source, label)
	if not fn then
		return nil, err
	end
	local ok, result = pcall(fn)
	if not ok then
		return nil, result
	end
	return result
end

local function fetchLibrary()

	if type(rawget(ENV, "LunarLibrary")) == "table" and type(ENV.LunarLibrary.new) == "function" then
		return ENV.LunarLibrary
	end

	if type(CONFIG.LibraryUrl) == "string" and CONFIG.LibraryUrl ~= "" and not CONFIG.LibraryUrl:find("YOUR_NAME", 1, true) then
		for attempt = 1, CONFIG.Retries do
			local ok, source = pcall(function()
				return game:HttpGet(CONFIG.LibraryUrl)
			end)
			if ok and type(source) == "string" and #source > 0 then
				local lib, err = compile(source, "=LUNAR_Library")
				if lib then
					return lib
				end
				warn("[LUNAR Loader] Library compile error: " .. tostring(err))
				break
			end
			warn(("[LUNAR Loader] download failed (%d/%d): %s"):format(attempt, CONFIG.Retries, tostring(ok and ("empty/non-string response: " .. type(source)) or source)))
			task.wait(CONFIG.RetryDelay)
		end
	end

	if type(isfile) == "function" and type(readfile) == "function" and isfile(CONFIG.LibraryFile) then
		local lib, err = compile(readfile(CONFIG.LibraryFile), "=LUNAR_Library")
		if lib then
			return lib
		end
		warn("[LUNAR Loader] Local library error: " .. tostring(err))
	end

	return nil
end

local EventGate = {
	Active = false,
	Abort = false,
	StealBusy = false,
	InArena = nil,
	Safe = nil,
	InZone = nil,
	Running = false,
}

local Stats = {
	Eggs = 0,
	Stolen = 0,
	MutStolen = 0,
	Mut = {},
	Seen = setmetatable({}, { __mode = "k" }),
}

function Stats.Reset()
	Stats.Eggs = 0
	Stats.Stolen = 0
	Stats.MutStolen = 0
	Stats.Mut = {}
end

function Stats.Steal(muts, sign)
	Stats.Stolen = math.max(0, Stats.Stolen + sign)
	if muts and next(muts) ~= nil then
		Stats.MutStolen = math.max(0, Stats.MutStolen + sign)
		for name in pairs(muts) do
			Stats.Mut[name] = math.max(0, (Stats.Mut[name] or 0) + sign)
		end
	end
end

Stats.On = false
Stats.MaxEggSize = 0
Stats.NextId = 0
Stats.HistoryMax = 100
Stats.History = { Steal = {}, Eggs = {}, Rev = 0 }
Stats.EggSizeSeen = setmetatable({}, { __mode = "k" })
Stats.EggSnapCache = setmetatable({}, { __mode = "k" })

local function histDrop(entry)
	if entry and entry.Model then
		pcall(function()
			entry.Model:Destroy()
		end)
		entry.Model = nil
	end
end

local function histTrim(list)
	while #list > Stats.HistoryMax do
		histDrop(table.remove(list))
	end
end

Stats.AfkClock = function()
	return 0
end

local RARITY_STYLE = {
	Common = { "#9AA0A6" },
	Uncommon = { "#5FCB5F" },
	Rare = { "#3FA7FF" },
	Epic = { "#A855F7" },
	Legendary = { "#FF2D2D" },
	Mythic = { "#FF4D4D", rainbow = true },
	Divine = { "#2F5BFF" },
	Cosmic = { "#5A2CA0", stroke = "#CBB0FF" },
	Secret = { "#0C0C0C", stroke = "#FFFFFF" },
	Celestial = { "#FFD24A" },
	Inferno = { "#FF6A1F" },
	Void = { "#2A0B4D", stroke = "#B98CFF" },
	Omega = { "#2ECC8F" },
	Spectral = { "#0A5C8A" },
	Ethereal = { "#0E8F5E" },
	Primordial = { "#B5179E", stroke = "#FFD6F5" },
}

local function richEsc(v)
	return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function hex3(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function Stats.RarityColor3(name)
	local st = name and RARITY_STYLE[name]
	local ok, c = pcall(Color3.fromHex, st and st[1] or "#9AA0A6")
	return ok and c or Color3.fromRGB(154, 160, 166)
end

function Stats.RarityRich(name, text, bold)
	text = tostring(text or name or "?")
	local st = name and RARITY_STYLE[name]
	local out
	if st and st.rainbow then
		local chars = {}
		local okc = pcall(function()
			for _, cp in utf8.codes(text) do
				chars[#chars + 1] = utf8.char(cp)
			end
		end)
		if not okc or #chars == 0 then
			chars = {}
			for i = 1, #text do
				chars[#chars + 1] = text:sub(i, i)
			end
		end
		local n = math.max(#chars, 1)
		local parts = {}
		for i, ch in ipairs(chars) do
			local c = Color3.fromHSV(((i - 1) / n) * 0.85, 0.8, 1)
			parts[#parts + 1] = ('<font color="%s">%s</font>'):format(hex3(c), richEsc(ch))
		end
		out = table.concat(parts)
	else
		out = ('<font color="%s">%s</font>'):format(st and st[1] or "#9AA0A6", richEsc(text))
		if st and st.stroke then
			out = ('<stroke color="%s" joins="miter" thickness="1" transparency="0.3">%s</stroke>'):format(st.stroke, out)
		end
	end
	if bold then
		out = "<b>" .. out .. "</b>"
	end
	return out
end

function Stats.ViewClone(inst)
	if typeof(inst) ~= "Instance" then
		return nil
	end
	-- Some game models are Archivable = false (or have non-archivable children). Clone() then
	-- returns nil or skips them, which is what caused the "?" / empty icons. Unlock, clone, restore.
	local flipped = {}
	local function unlock(i)
		local okA, a = pcall(function()
			return i.Archivable
		end)
		if okA and a == false then
			if pcall(function()
				i.Archivable = true
			end) then
				flipped[#flipped + 1] = i
			end
		end
	end
	unlock(inst)
	local okD, desc = pcall(function()
		return inst:GetDescendants()
	end)
	if okD then
		for _, d in ipairs(desc) do
			unlock(d)
		end
	end
	local ok, c = pcall(function()
		return inst:Clone()
	end)
	for _, i in ipairs(flipped) do
		pcall(function()
			i.Archivable = false
		end)
	end
	if not ok or not c then
		return nil
	end
	if c:IsA("LuaSourceContainer") or c:IsA("GuiBase2d") then
		pcall(function()
			c:Destroy()
		end)
		return nil
	end
	local kill = {}
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("GuiBase2d") or d:IsA("Sound") or d:IsA("ParticleEmitter")
			or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") then
			kill[#kill + 1] = d
		end
	end
	for _, d in ipairs(kill) do
		pcall(function()
			d:Destroy()
		end)
	end
	local parts = {}
	if c:IsA("BasePart") then
		parts[1] = c
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	if #parts == 0 then
		pcall(function()
			c:Destroy()
		end)
		return nil
	end
	local visible = 0
	for _, pt in ipairs(parts) do
		if pt.Transparency < 0.95 then
			visible += 1
		end
	end
	for _, pt in ipairs(parts) do
		pt.Anchored = true
		-- invisible hitboxes make the camera frame far too wide (tiny / empty icon)
		if visible > 0 and pt ~= c and pt.Transparency >= 0.95 then
			pcall(function()
				pt:Destroy()
			end)
		end
	end
	return c
end

function Stats.NoteEggSize(sz)
	if type(sz) == "number" and sz > Stats.MaxEggSize then
		Stats.MaxEggSize = sz
	end
end

function Stats.SizeScore(raw)
	if type(raw) ~= "number" or raw <= 0 or Stats.MaxEggSize <= 0 then
		return nil
	end
	return math.clamp(math.floor(raw / Stats.MaxEggSize * 100 + 0.5), 1, 100)
end

function Stats.AddSteal(muts, info)
	if not Stats.On then
		return nil
	end
	info = info or {}
	muts = muts or {}
	Stats.Steal(muts, 1)
	Stats.NextId += 1
	local names = {}
	for n in pairs(muts) do
		names[#names + 1] = n
	end
	table.sort(names)
	local entry = {
		Id = Stats.NextId,
		Kind = "Steal",
		At = os.time(),
		AfkAt = select(2, pcall(Stats.AfkClock)),
		Name = info.Name or "?",
		Rarity = info.Rarity,
		Income = info.Income,
		Muts = names,
		MutSet = muts,
		Model = info.Model,
	}
	table.insert(Stats.History.Steal, 1, entry)
	histTrim(Stats.History.Steal)
	Stats.History.Rev += 1
	return entry
end

function Stats.UndoSteal(entry)
	if not entry then
		return
	end
	Stats.Steal(entry.MutSet or {}, -1)
	local list = Stats.History.Steal
	local idx = table.find(list, entry)
	if idx then
		table.remove(list, idx)
	end
	histDrop(entry)
	Stats.History.Rev += 1
end

function Stats.AddEgg(info)
	if not Stats.On then
		return
	end
	info = info or {}
	Stats.Eggs += 1
	Stats.NoteEggSize(info.Size)
	Stats.NextId += 1
	local entry = {
		Id = Stats.NextId,
		Kind = "Egg",
		At = os.time(),
		AfkAt = select(2, pcall(Stats.AfkClock)),
		Name = info.Name or "?",
		Rarity = info.Rarity,
		MaxHealth = info.MaxHealth,
		Size = info.Size,
		Model = info.Model,
	}
	table.insert(Stats.History.Eggs, 1, entry)
	histTrim(Stats.History.Eggs)
	Stats.History.Rev += 1
end

local FarmSystem = {
	Id = "Farm",
	Name = "Farm",
	Build = function(UI)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Lang, Tr, TrDyn, Config, Assets, COLOR, Gui, track, addCleanup, New, Corner, Stroke, Notify, CollectConfig, ApplyConfig, CreatePage, CreateTab, Section, Safe, Toggle, Dropdown, TextInput, TextInputCb = UI.Lang, UI.Tr, UI.TrDyn, UI.Config, UI.Assets, UI.COLOR, UI.Gui, UI.track, UI.addCleanup, UI.New, UI.Corner, UI.Stroke, UI.Notify, UI.CollectConfig, UI.ApplyConfig, UI.CreatePage, UI.CreateTab, UI.Section, UI.Safe, UI.Toggle, UI.Dropdown, UI.TextInput, UI.TextInputCb
	Config = Config or { List = function() return {} end, Read = function() return nil end }
	Assets = Assets or { On = function() end }
	TextInput = TextInput or TextInputCb
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ContextActionService = game:GetService("ContextActionService")
	local Workspace = game:GetService("Workspace")

	local Page = CreatePage("Farm")
	CreateTab("Farm", "124620632231839")
	local Page2 = CreatePage("Extras")
	CreateTab("Extras", "9013498676")

	local BREAK_RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic", "Secret", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal" }
	local STEAL_RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic", "Secret", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal", "Primordial" }
	local RANK = {}
	for i, r in ipairs(STEAL_RARITIES) do
		RANK[r] = i
	end

	local TMX = { Exit = function() end }
	-- shared Teleport move mode for Auto Break / Auto Titanic Egg (filled in after tpReach)
	local TPX = {}

	local function getHRP()
		local c = LocalPlayer.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	end

	local function getHumanoid()
		local c = LocalPlayer.Character
		return c and c:FindFirstChildOfClass("Humanoid")
	end

	-- Real walking (same method as Auto Collect Gems): Humanoid:Move() is applied from a RenderStep that runs AFTER the
	-- game's own controls (they call Move(0) every frame), Humanoid:MoveTo is the backup, and the character jumps when
	-- stuck. The speed is the game's own WalkSpeed. Used by Auto Break, Titanic Egg and every walking leg of Auto Steal.
	local RW_BIND = "LunarRealWalk"
	local RW = { Target = nil, Bound = false }

	local function rwBind()
		if RW.Bound then
			return
		end
		RW.Bound = true
		pcall(function()
			RunService:UnbindFromRenderStep(RW_BIND)
		end)
		RunService:BindToRenderStep(RW_BIND, 2000, function()
			local t = RW.Target
			if not t then
				return
			end
			local hrp, hum = getHRP(), getHumanoid()
			if not hrp or not hum then
				return
			end
			local off = Vector3.new(t.X - hrp.Position.X, 0, t.Z - hrp.Position.Z)
			if off.Magnitude > 0.5 then
				pcall(function()
					hum:Move(off.Unit, false)
				end)
			end
		end)
	end

	local function rwHalt()
		RW.Target = nil
		if not RW.Bound then
			return
		end
		RW.Bound = false
		pcall(function()
			RunService:UnbindFromRenderStep(RW_BIND)
		end)
		local h, r = getHumanoid(), getHRP()
		if h then
			pcall(function()
				h:Move(Vector3.zero, false)
			end)
		end
		if h and r then
			pcall(function()
				h:MoveTo(r.Position)
			end)
		end
	end
	addCleanup(rwHalt)

	-- target: Vector3 or a function returning Vector3 / nil. Returns true when within `stop` studs (flat distance).
	local function realWalk(target, stop, alive, abortFn, abortEvery)
		local function resolve()
			if type(target) == "function" then
				return target()
			end
			return target
		end
		local hrp0, p0 = getHRP(), resolve()
		if not hrp0 or not p0 then
			return false
		end
		local off0 = Vector3.new(p0.X - hrp0.Position.X, 0, p0.Z - hrp0.Position.Z).Magnitude
		local timeout = off0 / 10 + 10
		local t0 = os.clock()
		local lastMove, lastPos, lastMoved, stuck, nextCheck = 0, nil, t0, 0, 0
		local result = false
		while true do
			if alive and not alive() then
				break
			end
			local hrp, hum, p = getHRP(), getHumanoid(), resolve()
			if not hrp or not hum or not p then
				break
			end
			local dist = Vector3.new(p.X - hrp.Position.X, 0, p.Z - hrp.Position.Z).Magnitude
			if dist <= stop then
				result = true
				break
			end
			local now = os.clock()
			if now - t0 > timeout then
				break
			end
			if abortFn and now > nextCheck then
				nextCheck = now + (abortEvery or 0.4)
				if abortFn() then
					break
				end
			end
			RW.Target = p
			rwBind()
			if now - lastMove >= 0.25 then
				lastMove = now
				pcall(function()
					hum:MoveTo(p)
				end)
			end
			-- stuck check: not moving while still away from the target -> jump, give up after 4 tries
			if not lastPos or (hrp.Position - lastPos).Magnitude > 0.4 then
				lastPos, lastMoved = hrp.Position, now
			elseif now - lastMoved > 0.7 then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end)
				lastMoved = now
				stuck += 1
				if stuck >= 4 then
					break
				end
			end
			RunService.Heartbeat:Wait()
		end
		rwHalt()
		return result
	end

	local function toSet(list)
		local t = {}
		for _, v in ipairs(list or {}) do
			t[v] = true
		end
		return t
	end

	local function StatusCard(parent, initial)
		return function() end -- status label removed
	end

	local SW, ST, TT, GM
	SW = {
		Running = false, Job = 0, Speed = 150,
		Order = "Largest first",
		Rarity = { Ethereal = true, Spectral = true, Omega = true, Void = true },
		Yielded = false, Assumed = false, OnSig = nil, OffSig = nil, MonitorOff = false, ManualOff = false, EvtState = nil,
		Working = false, TpMode = true,
		Zone = {}, Pending = setmetatable({}, { __mode = "k" }), Skip = setmetatable({}, { __mode = "k" }),
	}
	ST = {
		Running = false, Busy = false, Working = false, Noclip = true, SafeWait = false, AntiRagdoll = true,
		Speed = 100, Rarity = {}, Mutation = {}, Collected = 0, MinIncome = 0, Unread = 0, TpMode = true, TpArmed = false,
		CE = { Running = false, Busy = false, Job = 0, Failed = false, RetryAt = 0, Orig = setmetatable({}, { __mode = "k" }), Pos = Vector3.new(-119.387, 3.692, -186.409), Z1 = Vector3.new(-127.983, 3.692, 0), Mode = false },
	}
	TT = { Running = false, Job = 0, Speed = 150, TpMode = true, Working = false, Paused = false, EnabledSwing = false, Zone = {} }
	GM = { Running = false, Job = 0, Working = false }
	for z = 1, 13 do
		TT.Zone[z] = true
		SW.Zone[z] = true
	end

	local function evBlock()
		if EventGate.Active then return true end
		if EventGate.InArena then
			local ok, v = pcall(EventGate.InArena)
			return ok and v == true
		end
		return false
	end

	local function breakBlocked()
		return SW.PEBusy or ST.Working or ST.CE.Busy or GM.Working or TT.Working or evBlock()
	end

	local swToggle, stToggle
	local stIncomeInput
	local setSwStatus, setStStatus

	local SW_STOP = 6

	local function swAlive(id)
		return SW.Running and SW.Job == id
	end

	local function findSwingBtn()
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local mg = pg and pg:FindFirstChild("MainGUI")
		local btn = mg and mg:FindFirstChild("AutoSwing")
		if not btn and pg then
			btn = pg:FindFirstChild("AutoSwing", true)
		end
		return btn
	end

	local function pressBtn(btn)
		if firesignal and btn and btn:IsA("GuiButton") then
			pcall(firesignal, btn.MouseButton1Click)
			pcall(firesignal, btn.Activated)
			return true
		end
		return false
	end

	local function sigOf(btn)
		local parts = {}
		local nodes = btn:GetDescendants()
		table.insert(nodes, 1, btn)
		for _, d in ipairs(nodes) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				table.insert(parts, d.Text .. tostring(d.TextColor3))
			end
			if d:IsA("GuiObject") then
				table.insert(parts, tostring(d.BackgroundColor3) .. d.BackgroundTransparency .. tostring(d.Visible))
			end
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				table.insert(parts, tostring(d.ImageColor3) .. d.Image)
			end
			if d:IsA("UIStroke") then
				table.insert(parts, tostring(d.Color))
			end
			if d:IsA("BoolValue") then
				table.insert(parts, tostring(d.Value))
			end
		end
		return table.concat(parts, "|")
	end

	local function wordState(t)
		t = t:lower()
		if t:find("%f[%a]off%f[%A]") then
			return false
		end
		if t:find("%f[%a]on%f[%A]") then
			return true
		end
		return nil
	end

	local swingHooked = {}
	local function setSwingEventState(want)
		if type(getnilinstances) ~= "function" then
			return false
		end
		local ok, list = pcall(getnilinstances)
		if not ok or type(list) ~= "table" then
			return false
		end
		for _, obj in ipairs(list) do
			local matches = false
			pcall(function()
				matches = obj.Name == "Event"
					and obj:IsA("BindableEvent")
					and obj:GetDebugId() == "0_132375"
			end)
			if matches then
				local fired = pcall(function()
					obj:Fire(want)
				end)
				if fired then
					SW.EvtState = want
					return true
				end
			end
		end
		return false
	end
	local function hookSwingEvents()
		if type(getnilinstances) ~= "function" then
			return
		end
		local ok, list = pcall(getnilinstances)
		if not ok or type(list) ~= "table" then
			return
		end
		for _, o in ipairs(list) do
			local isEvt = false
			pcall(function()
				isEvt = o.Name == "Event" and o:IsA("BindableEvent")
			end)
			if isEvt and not swingHooked[o] then
				swingHooked[o] = true
				pcall(function()
					track(o.Event:Connect(function(v)
						if type(v) == "boolean" then
							SW.EvtState = v
						end
					end))
				end)
			end
		end
	end

	local function readSwingState(btn)
		for _, inst in ipairs({ btn, btn.Parent }) do
			if inst then
				for k, v in pairs(inst:GetAttributes()) do
					if type(v) == "boolean" then
						local n = k:lower()
						if n:find("auto") or n:find("enabled") or n:find("active") or n == "on" or n:find("toggle") or n:find("state") then
							return v
						end
					end
				end
			end
		end
		for _, d in ipairs(btn:GetChildren()) do
			if d:IsA("BoolValue") then
				return d.Value
			end
		end
		local nodes = btn:GetDescendants()
		table.insert(nodes, 1, btn)
		for _, d in ipairs(nodes) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				local r = wordState(d.Text)
				if r ~= nil then
					return r
				end
			end
		end
		if SW.EvtState ~= nil then
			return SW.EvtState
		end
		if SW.OnSig and SW.OffSig then
			local s = sigOf(btn)
			if s == SW.OnSig then
				return true
			elseif s == SW.OffSig then
				return false
			end
		end
		return nil
	end

	local function setGameSwing(want)
		local btn = findSwingBtn()
		if not btn then
			return false
		end
		local cur = readSwingState(btn)
		if cur == nil then
			cur = SW.Assumed
		end
		if cur ~= want then
			if pressBtn(btn) then
				SW.Assumed = want
			end
		end
		return true
	end

	local function btnShown(btn)
		if not btn then
			return false
		end
		local g = btn
		while g and not g:IsA("LayerCollector") do
			if g:IsA("GuiObject") and not g.Visible then
				return false
			end
			g = g.Parent
		end
		return true
	end

	local ensureSwingRemote

	local function holdingPick()
		local c = LocalPlayer.Character
		if c then
			for _, t in ipairs(c:GetChildren()) do
				if t:IsA("Tool") and t.Name:lower():find("pick") then
					return true
				end
			end
		end
		return false
	end

	local function enableGameSwing()
		hookSwingEvents()
		local btn = ensureSwingRemote and ensureSwingRemote() or findSwingBtn()
		if not btn then

			setSwingEventState(true)
			Notify("Game AutoSwing button not found (walking only)", false)
			return
		end

		SW.EvtState = nil
		SW.Assumed = nil
		local current = readSwingState(btn)
		local before = sigOf(btn)

		if current ~= true then
			if not pressBtn(btn) then
				Notify("firesignal not available - cannot press AutoSwing", false)
				setSwingEventState(true)
				return
			end
			task.wait(0.35)
		end

		setSwingEventState(true)
		SW.Assumed = true

		for _ = 1, 2 do
			local st = readSwingState(btn)
			if st ~= false then
				break
			end
			pressBtn(btn)
			task.wait(0.35)
		end

		local after = sigOf(btn)
		if before ~= after and readSwingState(btn) ~= false then
			SW.OffSig, SW.OnSig = before, after
		end
	end

	local function monitorSwing(id)
		local lastPress = 0
		local lastHook = 0
		local wasHolding = nil
		while swAlive(id) do
			task.wait(0.15)
			if os.clock() - lastHook > 5 then
				lastHook = os.clock()
				hookSwingEvents()
			end
			if swAlive(id) and not SW.Yielded and not SW.Resuming and not EventGate.Active then

				local holding = holdingPick()
				if wasHolding == false and holding then
					enableGameSwing()
					setSwStatus("Pickaxe back in hand -> AutoSwing turned ON again")
				end
				wasHolding = holding
				if SW.EvtState == false then
					setSwingEventState(true)
				end
				local btn = findSwingBtn()
				if not btnShown(btn) and ensureSwingRemote then
					btn = ensureSwingRemote()
				end

				if btn and readSwingState(btn) == false and os.clock() - lastPress > 0.6 then
					lastPress = os.clock()
					pressBtn(btn)
					SW.Assumed = true
					setSwStatus("AutoSwing was OFF -> turned ON again")
				end
			else
				wasHolding = nil
			end
		end
	end

	local function isPickaxe(t)
		return t:IsA("Tool") and t.Name:lower():find("pick") ~= nil
	end

	local function equipPickaxe()
		if SW.PlacingEgg then
			return true -- Auto Place Eggs is holding an egg right now: do not swap it for the pickaxe
		end
		local char = LocalPlayer.Character
		local hum = getHumanoid()
		if not (char and hum) then
			return false
		end
		for _, t in ipairs(char:GetChildren()) do
			if isPickaxe(t) then
				return true
			end
		end
		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		if not bp then
			return false
		end
		for _, t in ipairs(bp:GetChildren()) do
			if isPickaxe(t) then
				pcall(function()
					hum:EquipTool(t)
				end)
				return true
			end
		end
		return false
	end

	local function reequipPickaxe()
		local hum = getHumanoid()
		if hum then
			pcall(function()
				hum:UnequipTools()
			end)
		end
		task.wait(0.3)
		equipPickaxe()
	end

	ensureSwingRemote = function()
		local btn = findSwingBtn()
		for _ = 1, 3 do
			if btnShown(btn) then
				return btn
			end
			if setSwStatus then
				setSwStatus("Swing button not showing -> re-equipping pickaxe")
			end
			reequipPickaxe()
			task.wait(0.6)
			btn = findSwingBtn()
		end
		return btn
	end

	local function eggRarity(model)
		local g = model:FindFirstChild("RarityGradient", true)
		return g and g:GetAttribute("Rarity")
	end

	local function eggAlive(part)
		return part and part.Parent and part:GetAttribute("Broken") ~= true and (part:GetAttribute("Health") or 1) > 0
	end

	local function eggSize(model, part)
		local ok, s = pcall(function()
			return model:GetExtentsSize()
		end)
		if not ok or not s then
			s = part.Size
		end
		return math.floor(s.X * s.Y * s.Z * 100 + 0.5)
	end

	local function scanEggs()
		local out = {}
		local build = Workspace:FindFirstChild("Build")
		local zb = build and build:FindFirstChild("ZoneBuilds")
		if not zb then
			return out
		end
		local hrp = getHRP()
		for _, zone in ipairs(zb:GetChildren()) do
			local eggs = zone:FindFirstChild("Eggs")
			local zn = tonumber(tostring(zone.Name):match("%d+"))
			local zoneOk = next(SW.Zone) == nil or (zn ~= nil and SW.Zone[zn] == true)
			if eggs and zoneOk then
				for _, m in ipairs(eggs:GetChildren()) do
					local part = m:FindFirstChild("Egg")
					if part and part:IsA("BasePart") and eggAlive(part) and not (SW.Skip[part] and SW.Skip[part] > os.clock()) then
						local r = eggRarity(m)
						local wanted = r and SW.Rarity[r]
						local sz
						if wanted then
							sz = eggSize(m, part)
						else
							sz = Stats.EggSizeSeen[m]
							if sz == nil then
								sz = eggSize(m, part)
								Stats.EggSizeSeen[m] = sz
							end
						end
						Stats.NoteEggSize(sz)
						if wanted then
							table.insert(out, {
								part = part,
								model = m,
								name = m.Name,
								rarityName = r,
								size = sz,
								rank = RANK[r] or 0,
								dist = hrp and (part.Position - hrp.Position).Magnitude or 0,
							})
						end
					end
				end
			end
		end

		local order = SW.Order
		table.sort(out, function(a, b)
			if order == "Nearest first" then
				if a.dist ~= b.dist then
					return a.dist < b.dist
				end
				if a.size ~= b.size then
					return a.size > b.size
				end
				return a.rank > b.rank
			elseif order == "Smallest first" then
				if a.size ~= b.size then
					return a.size < b.size
				end
				if a.rank ~= b.rank then
					return a.rank > b.rank
				end
				return a.dist < b.dist
			end
			-- Largest first (default)
			if a.size ~= b.size then
				return a.size > b.size
			end
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			return a.dist < b.dist
		end)
		return out
	end

	function Stats.SnapEgg(e)
		if not Stats.On or not e or not e.part then
			return nil
		end
		local part = e.part
		local cached = Stats.EggSnapCache[part]
		if cached then
			return cached
		end
		local model = e.model or part.Parent
		local hp = tonumber(part:GetAttribute("MaxHealth")) or tonumber(part:GetAttribute("Health"))
		local rar = e.rarityName
		if not rar and model then
			rar = eggRarity(model)
		end
		local snap = {
			Name = tostring(e.name or (model and model.Name) or part.Name),
			Rarity = rar,
			MaxHealth = hp,
			Size = e.size or eggSize(model, part),
			Model = Stats.ViewClone(model or part),
		}
		Stats.EggSnapCache[part] = snap
		return snap
	end

	local function swWalkTo(part, id)
		if SW.TpMode then
			local done = TPX.reach({
				part = part,
				stop = SW_STOP,
				say = setSwStatus,
				alive = function()
					return swAlive(id) and not breakBlocked() and eggAlive(part)
				end,
			})
			if done then
				return true
			end
		end
		local ok = realWalk(function()
			return part.Parent and part.Position or nil
		end, SW_STOP, function()
			return swAlive(id) and not breakBlocked() and eggAlive(part)
		end)
		if not ok and swAlive(id) and not breakBlocked() and eggAlive(part) then
			SW.Skip[part] = os.clock() + 10 -- could not reach it (stuck / too long): skip this egg for 10s
		end
		return ok
	end

	-- Divine zone = the zone where the Divine eggs spawn (zone 7, from the game dump)
	local DIVINE_ZONE = 7
	local DIVINE_POS = Vector3.new(-1565.5, 3.693, 0)
	local DIVINE_X = { -1819.5, -1311.5 }

	-- zones where each egg rarity spawns (from the game dump)
	local RARITY_ZONES = {
		Common = { 1 }, Uncommon = { 2 }, Rare = { 3 }, Epic = { 4 }, Legendary = { 5 }, Mythic = { 6 },
		Divine = { 7 }, Cosmic = { 8 }, Secret = { 9 }, Celestial = { 10 }, Inferno = { 7, 11 },
		Void = { 7, 12 }, Omega = { 7, 12, 13 }, Spectral = { 12, 13 }, Ethereal = { 13 },
	}

	-- true when the far zones (beyond the Divine zone) that can hold the chosen rarities are loaded, i.e. their
	-- Eggs folder exists AND already has eggs in it. A far zone that is not streamed in has no folder / no eggs.
	local function swFarMapLoaded()
		local build = Workspace:FindFirstChild("Build")
		local zb = build and build:FindFirstChild("ZoneBuilds")
		if not zb then
			return false
		end
		local chosen = {}
		if next(SW.Zone) == nil then
			for z = DIVINE_ZONE + 1, 13 do
				chosen[z] = true
			end
		else
			for z in pairs(SW.Zone) do
				if z > DIVINE_ZONE then
					chosen[z] = true
				end
			end
		end
		-- keep only the zones where a chosen rarity really spawns
		local need = {}
		for rar, on in pairs(SW.Rarity) do
			if on then
				local zs = RARITY_ZONES[rar]
				if zs then
					for _, z in ipairs(zs) do
						if chosen[z] then
							need[z] = true
						end
					end
				else
					for z in pairs(chosen) do
						need[z] = true
					end
				end
			end
		end
		for z in pairs(need) do
			local zf = zb:FindFirstChild("Zone" .. z)
			local eggs = zf and zf:FindFirstChild("Eggs")
			if not (eggs and #eggs:GetChildren() > 0) then
				return false
			end
		end
		return true
	end

	-- true when a chosen zone is beyond the Divine zone, its map is NOT loaded and we are not in the Divine zone yet.
	-- Only asked when NO egg of the chosen zones is in sight. If the map is loaded (or a far egg is in sight) we never
	-- go to the Divine zone.
	local function swNeedDivineStop()
		local far = false
		for z in pairs(SW.Zone) do
			if z > DIVINE_ZONE then
				far = true
				break
			end
		end
		if next(SW.Zone) == nil then
			far = true
		end
		if not far or swFarMapLoaded() then
			return false
		end
		local r = getHRP()
		if r and r.Position.X <= DIVINE_X[2] + 5 and r.Position.X >= DIVINE_X[1] - 5 then
			return false
		end
		return os.clock() >= (SW.DivineAt or 0)
	end

	local function swGoTo(pos, id)
		local function alive()
			return swAlive(id) and not breakBlocked()
		end
		if SW.TpMode then
			local done = TPX.reach({
				pos = pos,
				stop = 8,
				say = setSwStatus,
				alive = alive,
			})
			if done then
				return true
			end
		end
		return realWalk(pos, 8, alive)
	end

	-- counts a broken egg exactly once, however the loop noticed it
	local function swCountEgg(e)
		if e and e.part and not eggAlive(e.part) and not Stats.Seen[e.part] then
			Stats.Seen[e.part] = true
			SW.Pending[e.part] = nil
			pcall(function()
				Stats.AddEgg(Stats.SnapEgg(e))
			end)
		end
	end

	-- eggs we went for but did not see break (the loop was interrupted, the egg died while walking...)
	local function swSweepPending()
		for part, rec in pairs(SW.Pending) do
			if os.clock() - rec.t > 45 then
				SW.Pending[part] = nil
			elseif not eggAlive(part) then
				swCountEgg(rec.e)
				SW.Pending[part] = nil
			end
		end
	end

	local function breakLoop(id)
		local lastEquip = 0
		reequipPickaxe()
		enableGameSwing()
		task.spawn(monitorSwing, id)
		while swAlive(id) do
			if breakBlocked() then
				SW.Working = false
				if not SW.Yielded then
					SW.Yielded = true
					setSwStatus(evBlock() and "Paused - Hell Event has priority" or (TT.Working and "Paused - Auto Titanic Egg is working (AutoSwing kept ON)" or "Paused - Auto Steal is working (AutoSwing kept ON)"))
				end
				task.wait(0.15)
			else
				if SW.Yielded then
					SW.Resuming = true
					SW.Yielded = false
					setSwStatus("Auto Steal finished -> equipping Pickaxe")

					local equipped = false
					for _ = 1, 5 do
						if not swAlive(id) then break end
						equipPickaxe()
						task.wait(0.25)
						local char = LocalPlayer.Character
						if char then
							for _, tool in ipairs(char:GetChildren()) do
								if isPickaxe(tool) then
									equipped = true
									break
								end
							end
						end
						if equipped then break end
					end

					if equipped and not SW.ManualOff then
						hookSwingEvents()
						local btn = ensureSwingRemote and ensureSwingRemote() or findSwingBtn()
						if btn then

							SW.EvtState = nil
							SW.Assumed = nil
							if readSwingState(btn) ~= true then

								pressBtn(btn)
								task.wait(0.35)
							end
						end
						setSwingEventState(true)
						SW.Assumed = true
						setSwStatus("Resumed - Pickaxe equipped, AutoSwing enabled")
					elseif not equipped then
						setSwStatus("Cannot resume - Pickaxe not found/equipped")
					end
					SW.Resuming = false
				elseif os.clock() - lastEquip > 1 then
					lastEquip = os.clock()
					equipPickaxe()
				end
				swSweepPending()
				local e = scanEggs()[1]
				if not e and swNeedDivineStop() then
					SW.Working = true
					TMX.Exit()
					setSwStatus("The map of the chosen zone is not loaded -> going to the Divine zone first")
					swGoTo(DIVINE_POS, id)
					SW.DivineAt = os.clock() + 4
					task.wait(0.5)
				elseif not e then
					SW.Working = false
					setSwStatus("No matching egg found, scanning...")
					task.wait(0.5)
				else
					SW.Working = true
					TMX.Exit()
					Stats.SnapEgg(e)
					SW.Pending[e.part] = { e = e, t = os.clock() }
					setSwStatus("Walking to egg (size " .. e.size .. ")")
					if swWalkTo(e.part, id) then
						setSwStatus("Breaking egg")
						while swAlive(id) and not breakBlocked() and eggAlive(e.part) do
							local r = getHRP()
							if r and Vector3.new(e.part.Position.X - r.Position.X, 0, e.part.Position.Z - r.Position.Z).Magnitude > SW_STOP * 4 then
								break
							end
							task.wait(0.3)
						end
					end
					swCountEgg(e)
				end
				task.wait()
			end
		end
	end

	local function swStop(msg)
		local was = SW.Running
		SW.Running = false
		SW.Working = false
		SW.Job += 1
		SW.Yielded = false
		if was then
			setGameSwing(false)
		end
		setSwingEventState(false)
		local hrp = getHRP()
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		if setSwStatus then
			setSwStatus(msg or "Stopped")
		end
	end

	local function swStart()
		local any = false
		for _, v in pairs(SW.Rarity) do
			if v then
				any = true
				break
			end
		end
		if not any then
			Notify("Select a rarity first", false)
			return false
		end
		SW.Running = true
		SW.Yielded = false
		SW.MonitorOff = false
		SW.ManualOff = false
		SW.Job += 1
		local id = SW.Job
		task.spawn(function()
			local ok, err = pcall(breakLoop, id)
			if not ok then
				warn("[LUNAR Hub] AutoBreak error: " .. tostring(err))
				if SW.Job == id then
					swStop("Error - see console")
					pcall(function()
						swToggle.Set(false, true)
					end)
				end
			end
		end)
		return true
	end

	local setTtStatus
	local TT_GAP = 3.2

	local function ttAlive(id)
		return TT.Running and TT.Job == id
	end

	local function titanicBlocked()
		return ST.Working or ST.CE.Busy or GM.Working or evBlock()
	end

	local function fmtClock(sec)
		sec = math.max(0, math.floor(sec))
		return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
	end

	local function isTitanicEgg(model, part)
		if part:GetAttribute("Titanic") == true then
			return true
		end
		local zi = tonumber(Workspace:GetAttribute("TitanicZoneIndex"))
		local nm = Workspace:GetAttribute("TitanicEggName")
		local ends = tonumber(Workspace:GetAttribute("TitanicEndsAt"))
		local despawn = tonumber(part:GetAttribute("DespawnAt"))
		if zi and nm and ends and despawn
			and tonumber(part:GetAttribute("ZoneIndex")) == zi
			and part:GetAttribute("EggType") == nm
			and math.abs(despawn - ends) < 2 then
			return true
		end
		return false
	end

	local function findTitanic()
		local build = Workspace:FindFirstChild("Build")
		local zb = build and build:FindFirstChild("ZoneBuilds")
		if not zb then
			return nil
		end
		local r = getHRP()
		local best, bd = nil, math.huge
		for _, zone in ipairs(zb:GetChildren()) do
			local eggs = zone:FindFirstChild("Eggs")
			local zn0 = tonumber(zone.Name:match("%d+"))
			if eggs then
				for _, m in ipairs(eggs:GetChildren()) do
					local part = m:FindFirstChild("Egg")
					local zn = (part and tonumber(part:GetAttribute("ZoneIndex"))) or zn0
					if part and part:IsA("BasePart") and (zn == nil or TT.Zone[zn]) and eggAlive(part)
						and isTitanicEgg(m, part) then
						local d = r and (part.Position - r.Position).Magnitude or 0
						if d < bd then
							best, bd = part, d
						end
					end
				end
			end
		end
		return best
	end

	local function ttStopDist(part)
		return math.max(SW_STOP, math.max(part.Size.X, part.Size.Z) / 2 + TT_GAP)
	end

	local function ttWalkTo(part, id)
		local stop = ttStopDist(part)
		if TT.TpMode then
			local done = TPX.reach({
				part = part,
				stop = stop,
				say = setTtStatus,
				alive = function()
					return ttAlive(id) and not titanicBlocked() and eggAlive(part)
				end,
			})
			if done then
				return true
			end
		end
		return realWalk(function()
			return part.Parent and part.Position or nil
		end, stop, function()
			return ttAlive(id) and not titanicBlocked() and eggAlive(part)
		end)
	end

	local function ttPrepare()
		equipPickaxe()
		if EventGate.Active then
			return
		end
		local btn = findSwingBtn()
		local st = btn and readSwingState(btn)
		if st == true or (st == nil and SW.Assumed == true) then
			return
		end
		hookSwingEvents()
		TT.EnabledSwing = true
		enableGameSwing()
	end

	local function ttRelease()
		if TT.EnabledSwing and not SW.Running and not EventGate.Active then
			pcall(setGameSwing, false)
			pcall(setSwingEventState, false)
		end
		TT.EnabledSwing = false
	end

	local function ttHit(part, id)
		local r = getHRP()
		if not r then
			return
		end
		local holdCF = r.CFrame
		local lastEquip, lastChk, lastPress, lastStatus = 0, 0, 0, 0
		local wasHolding = nil
		while ttAlive(id) and not titanicBlocked() and eggAlive(part) do
			r = getHRP()
			if not r then
				break
			end
			r.CFrame = holdCF
			r.AssemblyLinearVelocity = Vector3.zero
			local now = os.clock()
			if now - lastEquip > 1 then
				lastEquip = now
				equipPickaxe()
			end
			if now - lastChk > 0.3 and not EventGate.Active then
				lastChk = now

				local holding = holdingPick()
				if wasHolding == false and holding then
					enableGameSwing()
				end
				wasHolding = holding
				if SW.EvtState == false then
					setSwingEventState(true)
				end
				local btn = findSwingBtn()
				if btn and readSwingState(btn) == false and now - lastPress > 0.8 then
					lastPress = now
					pressBtn(btn)
					SW.Assumed = true
				end
			elseif EventGate.Active then
				wasHolding = nil
			end
			if now - lastStatus > 0.5 then
				lastStatus = now
				local hp = tonumber(part:GetAttribute("Health")) or 0
				local mx = tonumber(part:GetAttribute("MaxHealth")) or hp
				setTtStatus(("Breaking Titanic Egg: %d / %d"):format(math.floor(hp), math.floor(mx)))
			end
			RunService.Heartbeat:Wait()
		end
	end

	local function titanicStep(id)
		do
			if next(TT.Zone) == nil then
				TT.Working = false
				setTtStatus("Select a zone first")
				task.wait(0.5)
			elseif titanicBlocked() then
				if not TT.Paused then
					TT.Paused = true
					TT.Working = false
					setTtStatus(evBlock() and "Paused - Hell Event has priority" or "Paused - Auto Steal is working")
				end
				task.wait(0.15)
			else
				TT.Paused = false
				local egg = findTitanic()
				if not egg then
					TT.Working = false
					local nextAt = Workspace:GetAttribute("TitanicNextAt")
					local cd = nextAt and (nextAt - os.time()) or 0
					setTtStatus("Waiting for Titanic Egg" .. (cd > 0 and (" (next in " .. fmtClock(cd) .. ")") or ""))
					task.wait(0.5)
				else
					if not TT.Working then
						TT.Working = true
						TMX.Exit()
						local t0 = os.clock()
						while ttAlive(id) and SW.Running and not SW.Yielded and os.clock() - t0 < 1.5 do
							RunService.Heartbeat:Wait()
						end
						if ttAlive(id) and not titanicBlocked() then
							setTtStatus("Preparing Pickaxe / AutoSwing")
							ttPrepare()
						end
					end
					if ttAlive(id) and not titanicBlocked() then
						Stats.SnapEgg({ part = egg, model = egg.Parent })
						setTtStatus("Walking to Titanic Egg")
						if ttWalkTo(egg, id) then
							ttHit(egg, id)
						end
						if ttAlive(id) and not titanicBlocked() and not eggAlive(egg) then
							if not Stats.Seen[egg] then
								Stats.Seen[egg] = true
								Stats.AddEgg(Stats.SnapEgg({ part = egg, model = egg.Parent }))
							end
							setTtStatus("Titanic Egg broken")
							Notify("Titanic Egg broken", true)
							TT.Working = false
							ttRelease()
							task.wait(1)
						end
					end
				end
			end
		end
	end

	local function titanicLoop(id)
		while ttAlive(id) do
			local ok, err = pcall(titanicStep, id)
			if not ok then
				warn("[LUNAR Hub] AutoTitanicEgg: " .. tostring(err))
				task.wait(1)
			end
			task.wait()
		end
	end

	local function ttStop(msg)
		local was = TT.Running
		TT.Running = false
		TT.Job += 1
		TT.Working = false
		TT.Paused = false
		if was then
			ttRelease()
		end
		local hrp = getHRP()
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		if setTtStatus then
			setTtStatus(msg or "Stopped")
		end
	end

	local function ttStart()
		TT.Running = true
		TT.Paused = false
		TT.Job += 1
		local id = TT.Job
		task.spawn(function()
			while ttAlive(id) do
				local ok, err = pcall(titanicLoop, id)
				if ok then break end
				warn("[LUNAR Hub] AutoTitanicEgg error (auto-restart): " .. tostring(err))
				TT.Working = false
				task.wait(1)
			end
		end)
		return true
	end


	-- (kept inside a do-block so it does not use up local-variable slots)
	do
		-- Auto Collect Gems: gems drop on the ground in Workspace.EggGemDrops and are collected by touching them.
		-- Priority (high -> low): Auto Steal > Auto Collect Gems > Titanic Egg > Auto Break > Auto Treadmill
		local function gmAlive(id)
			return GM.Running and GM.Job == id
		end

		local function gemPos(o)
			if not o or not o.Parent then
				return nil
			end
			if o:IsA("BasePart") then
				return o.Position
			end
			if o:IsA("Model") then
				local ok, cf = pcall(function()
					return o:GetPivot()
				end)
				if ok and cf then
					return cf.Position
				end
			end
			local p = o:FindFirstChildWhichIsA("BasePart", true)
			return p and p.Position or nil
		end

		local function gemPart(o)
			if not o or not o.Parent then
				return nil
			end
			if o:IsA("BasePart") then
				return o
			end
			if o:IsA("Model") and o.PrimaryPart then
				return o.PrimaryPart
			end
			return o:FindFirstChildWhichIsA("BasePart", true)
		end

		local gmSkip = setmetatable({}, { __mode = "k" })
		local gmStuck = 0
		local GM_BIND = "LunarGemWalk"

		local function nextGem(from)
			local root = Workspace:FindFirstChild("EggGemDrops")
			if not root then
				return nil
			end
			local best, bestD
			for _, o in ipairs(root:GetChildren()) do
				local p = gemPos(o)
				if p and not (gmSkip[o] and gmSkip[o] > os.clock()) then
					local d = Vector3.new(p.X - from.X, 0, p.Z - from.Z).Magnitude
					if not bestD or d < bestD then
						best, bestD = o, d
					end
				end
			end
			return best
		end

			-- Real walking at the game's own WalkSpeed (no CFrame / teleport): walk to the nearest gem until it disappears,
			-- then pick the next nearest one. The game's default controls call Humanoid:Move(0) every frame and would cancel
			-- our movement, so Humanoid:Move() is applied from a RenderStep that runs AFTER them (priority 2000),
			-- with Humanoid:MoveTo as a backup. A gem we cannot reach (stuck / too long) is skipped for 10s.
			-- No gem left -> idle (GM.Working = false so Auto Break etc. can run) and resume when a new gem drops.
			local function gemLoop(id)
				local moving = false
				local target = nil -- Vector3 the render step walks toward (nil = do nothing)
				local bound = false
				local function bindWalk()
					if bound then
						return
					end
					bound = true
					pcall(function()
						RunService:UnbindFromRenderStep(GM_BIND)
					end)
					RunService:BindToRenderStep(GM_BIND, 2000, function()
						local t = target
						if not t then
							return
						end
						local hrp, hum = getHRP(), getHumanoid()
						if not hrp or not hum then
							return
						end
						local off = Vector3.new(t.X - hrp.Position.X, 0, t.Z - hrp.Position.Z)
						if off.Magnitude > 0.5 then
							pcall(function()
								hum:Move(off.Unit, false)
							end)
						end
					end)
				end
				local function halt()
					target = nil
					if bound then
						bound = false
						pcall(function()
							RunService:UnbindFromRenderStep(GM_BIND)
						end)
					end
					if not moving then
						return
					end
					moving = false
					local h, r = getHumanoid(), getHRP()
					if h then
						pcall(function()
							h:Move(Vector3.zero, false)
						end)
					end
					if h and r then
						pcall(function()
							h:MoveTo(r.Position)
						end)
					end
				end
				while gmAlive(id) do
					local r = getHRP()
					if ST.Working or ST.CE.Busy or evBlock() or not r then
						GM.Working = false
						halt()
						task.wait(0.2)
					else
						local g = nextGem(r.Position)
						if not g then
							GM.Working = false
							halt()
							task.wait(0.25)
						else
							GM.Working = true
							local startedAt, lastMove, lastPos, lastMoved = os.clock(), 0, nil, os.clock()
							while gmAlive(id) and not ST.Working and not ST.CE.Busy and not evBlock() and g.Parent do
								task.wait(0.1)
								local hrp, hum = getHRP(), getHumanoid()
								local p = gemPos(g)
								if not gmAlive(id) or ST.Working or ST.CE.Busy or not hrp or not hum or not p then
									break
								end
								local now = os.clock()
								local dist = Vector3.new(p.X - hrp.Position.X, 0, p.Z - hrp.Position.Z).Magnitude
								target = p
								moving = true
								bindWalk()
								-- backup: MoveTo times out after 8s, so re-issue it regularly
								if now - lastMove >= 0.25 then
									lastMove = now
									pcall(function()
										hum:MoveTo(p)
									end)
								end
								-- stuck check: not moving while still away from the gem -> jump, then give up on this gem
								if dist < 1.5 or not lastPos or (hrp.Position - lastPos).Magnitude > 0.4 then
									lastPos, lastMoved = hrp.Position, now
								elseif now - lastMoved > 0.7 then
									pcall(function()
										hum:ChangeState(Enum.HumanoidStateType.Jumping)
									end)
									lastMoved = now
									gmStuck += 1
									if gmStuck >= 4 then
										gmSkip[g] = now + 10
										gmStuck = 0
										break
									end
								end
								if now - startedAt > 20 then
									gmSkip[g] = now + 10
									break
								end
							end
							gmStuck = 0
						end
					end
				end
				GM.Working = false
				halt()
			end

		function GM.Stop()
			GM.Running = false
			GM.Job += 1
			GM.Working = false
			pcall(function()
				RunService:UnbindFromRenderStep(GM_BIND)
			end)
		end

		function GM.Start()
			GM.Running = true
			GM.Job += 1
			local id = GM.Job
			task.spawn(function()
				while gmAlive(id) do
					local ok, err = pcall(gemLoop, id)
					if ok then
						break
					end
					warn("[LUNAR Hub] AutoCollectGems error (auto-restart): " .. tostring(err))
					GM.Working = false
					task.wait(1)
				end
			end)
			return true
		end
	end

	local TM = { Running = false, Job = 0, Speed = 150, Margin = 7, GroundY = 3.693 }
	local setTmStatus, setEqStatus

	function TM.Alive(id)
		return TM.Running and TM.Job == id
	end

	function TM.Find()
		local plots = Workspace:FindFirstChild("Plots")
		if not plots then
			return nil, "Plots not found"
		end
		local uid = LocalPlayer.UserId
		for _, plot in ipairs(plots:GetChildren()) do
			if tonumber(plot:GetAttribute("OwnerUserId")) == uid then
				if plot:GetAttribute("TreadmillUnlocked") == false then
					return nil, "Treadmill is locked"
				end
				for _, c in ipairs(plot:GetChildren()) do
					if c.Name ~= "TreadmillBoard" and c.Name:lower():find("treadmill", 1, true) then
						local hb = c:FindFirstChild("Hitbox")
						if hb and hb:IsA("BasePart") then
							return hb
						end
					end
				end
				return nil, "Treadmill not found in your plot"
			end
		end
		return nil, "Your plot was not found"
	end

	function TM.Inside(hb, hrp, margin)
		local m = margin or TM.Margin
		local rel = hb.CFrame:PointToObjectSpace(hrp.Position)
		return math.abs(rel.X) <= hb.Size.X / 2 + m
			and math.abs(rel.Z) <= hb.Size.Z / 2 + m
			and math.abs(rel.Y) <= hb.Size.Y / 2 + 6
	end

	function TM.Blocked()
		return SW.PEBusy or ST.Working or ST.CE.Busy or GM.Working or TT.Working or SW.Working or evBlock()
	end

	TM.Leaving = false

	function TM.Leave(hb, hrp)
		if TM.Leaving then

			local w0 = os.clock()
			while TM.Leaving and os.clock() - w0 < 1.5 do
				task.wait(0.05)
			end
			return
		end
		TM.Leaving = true
		local ok, err = pcall(function()
			local hum = getHumanoid()
			if hum and hum.Health > 0 then
				local t0 = os.clock()
				while os.clock() - t0 < 0.3 do
					hum.Jump = true
					pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
					task.wait(0.05)
				end
			end
			local r = getHRP() or hrp
			if r and TM.Inside(hb, r) then
				local out = hb.CFrame:PointToWorldSpace(Vector3.new(hb.Size.X / 2 + TM.Margin + 4, 0, 0))
				r.CFrame = CFrame.new(out.X, TM.GroundY, out.Z)
				r.AssemblyLinearVelocity = Vector3.zero
			end
		end)
		TM.Leaving = false
		if not ok then
			warn("[LUNAR Hub] Treadmill leave error: " .. tostring(err))
		end
	end

	TMX.Exit = function()
		if not TM.Running then return end
		local hb = TM.Find()
		local r = getHRP()
		if hb and r and TM.Inside(hb, r) then
			TM.Leave(hb, r)
		end
	end

	local function tmLoop(id)
		local touching = false
		while TM.Alive(id) do
			local hrp = getHRP()
			if not hrp then
				touching = false
				task.wait(0.3)
				continue
			end
			local hb, why = TM.Find()
			if not hb then
				touching = false
				setTmStatus(why)
				task.wait(1)
				continue
			end
			if TM.Blocked() then
				if touching or TM.Inside(hb, hrp) then
					TM.Leave(hb, hrp)
				end
				touching = false
				setTmStatus("Paused - another function is working")
				task.wait(0.1)
			elseif touching and TM.Inside(hb, hrp) then
				setTmStatus("On treadmill")
				task.wait(0.2)
			elseif TM.Inside(hb, hrp, 0) then
				touching = true
				setTmStatus("On treadmill")
				task.wait(0.2)
			else
				touching = false
				setTmStatus("Walking to treadmill")
				local dt = math.min(RunService.Heartbeat:Wait(), 0.05)
				local r = getHRP()
				if TM.Alive(id) and r and not TM.Blocked() then
					local to = Vector3.new(hb.Position.X - r.Position.X, 0, hb.Position.Z - r.Position.Z)
					if to.Magnitude > 0.3 then
						local np = r.Position + to.Unit * math.min(TM.Speed * dt, to.Magnitude)
						np = Vector3.new(np.X, TM.GroundY, np.Z)
						r.CFrame = CFrame.new(np, np + Vector3.new(to.X, 0, to.Z))
						r.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end
	end

	function TM.Stop(msg)
		local was = TM.Running
		TM.Running = false
		TM.Job += 1
		if was then

			local hb = TM.Find()
			local hrp = getHRP()
			if hb and hrp and TM.Inside(hb, hrp) then
				TM.Leave(hb, hrp)
			end
		end
		if setTmStatus then
			setTmStatus(msg or "Stopped")
		end
	end

	-- Auto Equip Best Pets: when ON, fires the game's PetsInventoryRemote("EquipBest") once after every successful
	-- steal, after a random 1 - 5 second delay (EQ.Kick is called from Auto Steal).
	local EQ = { Running = false, Job = 0, Pending = false }

	function EQ.Stop(msg)
		EQ.Running = false
		EQ.Job += 1
		EQ.Pending = false
		if setEqStatus then
			setEqStatus(msg or "Stopped")
		end
	end

	function EQ.Start()
		EQ.Running = true
		EQ.Job += 1
		EQ.Pending = false
		if setEqStatus then
			setEqStatus("Waiting for a successful steal")
		end
	end

	function EQ.Kick()
		if not EQ.Running or EQ.Pending then
			return
		end
		EQ.Pending = true
		local id = EQ.Job
		local delay = 1 + math.random() * 4
		if setEqStatus then
			setEqStatus(("Steal done -> equipping best pets in %.1fs"):format(delay))
		end
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < delay and EQ.Running and EQ.Job == id do
				task.wait(0.1)
			end
			EQ.Pending = false
			if not (EQ.Running and EQ.Job == id) then
				return
			end
			local ok, fired = pcall(function()
				local remote = game:GetService("ReplicatedStorage"):FindFirstChild("PetsInventoryRemote")
				if not remote then
					return false
				end
				remote:FireServer("EquipBest", nil)
				return true
			end)
			if setEqStatus then
				if ok and fired then
					setEqStatus("Equipped best pets")
				elseif ok then
					setEqStatus("Pet remote not found")
				else
					setEqStatus("Equip failed")
				end
			end
		end)
	end

	function TM.Start()
		TM.Running = true
		TM.Job += 1
		local id = TM.Job
		task.spawn(function()
			while TM.Alive(id) do
				local ok, err = pcall(tmLoop, id)
				if ok then break end
				warn("[LUNAR Hub] AutoTreadmill error (auto-restart): " .. tostring(err))
				task.wait(1)
			end
		end)
		return true
	end

	do
		local AFK = { Active = false, Snapshot = nil, Config = nil, Job = 0, StartedAt = 0, Elapsed = 0, AntiIdle = true }
		Stats.AfkClock = function()
			return AFK.Elapsed + (AFK.Active and (os.clock() - AFK.StartedAt) or 0)
		end
		local afkGui, afkTime, afkStats, afkAnti, afkRefresh
		local afkHist, histPanel, histRefresh, buildHistoryUI
		local afkToggle, afkOffFn

		local VirtualUser = game:GetService("VirtualUser")
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local VIM
		pcall(function()
			VIM = game:GetService("VirtualInputManager")
		end)
		local idleConn
		local blockOn = false
		local hooked = false
		local blockRemote
		local disabledConns = {}

		local function poke()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0))
			end)
			if VIM then
				pcall(function()
					local cam = Workspace.CurrentCamera
					local v = cam and cam.ViewportSize or Vector2.new(400, 300)
					VIM:SendMouseMoveEvent(v.X / 2 + math.random(-3, 3), v.Y / 2 + math.random(-3, 3), game)
				end)
			end
		end

		local function installBlock()
			blockRemote = blockRemote or ReplicatedStorage:FindFirstChild("AntiAfkRejoinRemote", true)
			if not blockRemote then
				return
			end
			if not hooked and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
				local wrap = type(newcclosure) == "function" and newcclosure or function(f)
					return f
				end
				local old
				local ok = pcall(function()
					old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
						if blockOn and self == blockRemote then
							local m = getnamecallmethod()
							if m == "FireServer" or m == "InvokeServer" then
								return nil
							end
						end
						return old(self, ...)
					end))
				end)
				hooked = ok
			end
			if type(getconnections) == "function" and blockRemote:IsA("RemoteEvent") then
				pcall(function()
					for _, c in ipairs(getconnections(blockRemote.OnClientEvent)) do
						c:Disable()
						disabledConns[#disabledConns + 1] = c
					end
				end)
			end
		end

		local function startAntiIdle()
			blockOn = true
			pcall(installBlock)
			if idleConn then
				return
			end
			idleConn = LocalPlayer.Idled:Connect(poke)
		end

		local function stopAntiIdle()
			blockOn = false
			for _, c in ipairs(disabledConns) do
				pcall(function()
					c:Enable()
				end)
			end
			disabledConns = {}
			if idleConn then
				idleConn:Disconnect()
				idleConn = nil
			end
		end

		local function fmtTime(sec)
			sec = math.max(0, math.floor(sec))
			return string.format("%02d:%02d:%02d", sec // 3600, (sec // 60) % 60, sec % 60)
		end

		local function buildAfkGui()
			if afkGui and afkGui.Parent then
				return afkGui
			end
			afkGui = New("ScreenGui", {
				Name = "LunarHubAfk",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = 2147483647,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Enabled = false,
			})
			afkGui.Parent = Gui.Parent or LocalPlayer:WaitForChild("PlayerGui")

			local Root = New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = COLOR.black,
				BorderSizePixel = 0,
				Active = true,
				ZIndex = 1,
			}, afkGui)

			local Bg = New("ImageLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = "",
				ScaleType = Enum.ScaleType.Crop,
				Visible = false,
				ZIndex = 2,
			}, Root)
			Assets.On("Background", function(id)
				if Bg.Parent then
					Bg.Image = id
					Bg.Visible = true
				end
			end)
			New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = COLOR.black,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, Root)

			-- top-right: small running-time counter + small close button
			local Pill = New("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 12),
				Size = UDim2.fromOffset(152, 32),
				BackgroundColor3 = COLOR.innerBg,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				ZIndex = 8,
			}, Root)
			Corner(Pill, 10)
			Stroke(Pill, COLOR.innerBorder, 1.5, 0)
			afkTime = New("TextLabel", {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -46, 1, 0),
				BackgroundTransparency = 1,
				Text = "00:00:00",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = COLOR.white,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 9,
			}, Pill)
			local Close = New("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = COLOR.red,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				ZIndex = 9,
			}, Pill)
			Corner(Close, 8)
			-- draw the X with two rotated bars (font glyphs for ✕ may not render)
			for _, rot in ipairs({ 45, -45 }) do
				New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(14, 2),
					Rotation = rot,
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					ZIndex = 10,
				}, Close)
			end
			local function closeAfk()
				-- close directly (never depends on the toggle callback), then sync the switch silently
				if afkOffFn then
					local ok, err = pcall(afkOffFn)
					if not ok then
						warn("[LUNAR Hub] AFK close error: " .. tostring(err))
					end
				end
				if afkGui then
					afkGui.Enabled = false
				end
				if afkToggle then
					pcall(afkToggle.Set, false, true)
				end
			end
			track(Close.Activated:Connect(closeAfk))
			track(Close.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					closeAfk()
				end
			end))

			-- centre column: logo, title, stat cards, mutation chips, system status
			local Center = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(400, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, Root)
			New("UIListLayout", {
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}, Center)

			local LogoBox = New("Frame", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, Center)
			local Logo = New("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(96, 96),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = "",
				ScaleType = Enum.ScaleType.Fit,
				Visible = false,
				ZIndex = 5,
			}, LogoBox)
			local LogoFallback = New("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(96, 96),
				BackgroundTransparency = 1,
				Text = "☾",
				Font = Enum.Font.GothamBlack,
				TextSize = 72,
				TextColor3 = COLOR.redBright,
				ZIndex = 5,
			}, LogoBox)
			Assets.On("Logo", function(id)
				if Logo.Parent then
					Logo.Image = id
					Logo.Visible = true
					LogoFallback.Visible = false
				end
			end)

			New("TextLabel", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,
				Text = "LUNAR HUB",
				Font = Enum.Font.GothamBlack,
				TextSize = 28,
				TextColor3 = COLOR.white,
				ZIndex = 5,
			}, Center)

			afkStats = { MutSig = "", Dots = {} }

			local CardsRow = New("Frame", {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 84),
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, Center)
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, CardsRow)

			local function statCard(order, key, label, color)
				local Card = New("Frame", {
					LayoutOrder = order,
					Size = UDim2.new(1 / 3, -7, 1, 0),
					BackgroundColor3 = COLOR.innerBg,
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
					ZIndex = 6,
				}, CardsRow)
				Corner(Card, 12)
				Stroke(Card, COLOR.innerBorder, 1.5, 0)
				local Accent = New("Frame", {
					Position = UDim2.fromOffset(14, 0),
					Size = UDim2.new(1, -28, 0, 3),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					ZIndex = 7,
				}, Card)
				Corner(Accent, 2)
				afkStats[key] = New("TextLabel", {
					Position = UDim2.fromOffset(0, 14),
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundTransparency = 1,
					Text = "0",
					Font = Enum.Font.GothamBlack,
					TextSize = 28,
					TextColor3 = color,
					ZIndex = 7,
				}, Card)
				local L = New("TextLabel", {
					Position = UDim2.fromOffset(0, 54),
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					Text = "",
					Font = Enum.Font.GothamMedium,
					TextSize = 11,
					TextColor3 = COLOR.grey,
					ZIndex = 7,
				}, Card)
				Lang.Bind(L, "Text", label)
			end
			statCard(1, "Eggs", "Eggs Broken", Color3.fromRGB(110, 193, 255))
			statCard(2, "Stolen", "Animals Stolen", Color3.fromRGB(255, 162, 74))
			statCard(3, "MutStolen", "Mutated Stolen", Color3.fromRGB(199, 125, 255))

			afkStats.MutRow = New("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, Center)
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Wraps = true,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}, afkStats.MutRow)

			local StatusRow = New("Frame", {
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, Center)
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}, StatusRow)
			local function statusPill(order, key, label)
				local P = New("Frame", {
					LayoutOrder = order,
					Size = UDim2.new(1 / 3, -6, 1, 0),
					BackgroundColor3 = COLOR.innerBg,
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
					ZIndex = 6,
				}, StatusRow)
				Corner(P, 10)
				Stroke(P, COLOR.innerBorder, 1.2, 0)
				local Dot = New("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.fromOffset(8, 8),
					BackgroundColor3 = Color3.fromRGB(100, 100, 100),
					BorderSizePixel = 0,
					ZIndex = 7,
				}, P)
				Corner(Dot, 4)
				afkStats.Dots[key] = Dot
				local L = New("TextLabel", {
					Position = UDim2.fromOffset(24, 0),
					Size = UDim2.new(1, -28, 1, 0),
					BackgroundTransparency = 1,
					Text = "",
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = COLOR.white,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 7,
				}, P)
				Lang.Bind(L, "Text", label)
			end
			statusPill(1, "Break", "Auto Break")
			statusPill(2, "Steal", "Auto Steal")
			statusPill(3, "Treadmill", "Auto Treadmill")

			buildHistoryUI(Root)
			return afkGui
		end

		local MUT_COLORS = {
			Gold = "#FFD24A", Diamond = "#4FD8FF", Lucky = "#5BE37D", Lightning = "#FFEE58",
			Angelic = "#F2F2FF", Frozen = "#8CDCFF", ["Fallen Angel"] = "#B48CFF",
			["Fallen Angel Gold"] = "#FFC878", ["Fallen Angel Diamond"] = "#82E6FF",
			["Devil Gold"] = "#FF7850", ["Devil Diamond"] = "#FF5A8C",
			Void = "#9B6BFF", Time = "#4DD0E1", Hacker = "#39FF14",
		}
		local MUT_ORDER = { "Gold", "Diamond", "Lightning", "Angelic", "Frozen", "Lucky", "Void", "Time", "Hacker" }

		local function tx(s)
			local ok, r = pcall(TrDyn, s)
			if ok and type(r) == "string" and r ~= "" then
				return r
			end
			return s
		end

		local function line(color, label, value)
			return ('<font color="%s">%s</font>: <font color="#FFFFFF">%d</font>'):format(color, label, value)
		end

		local function statsText()
			local lines = {
				line("#6EC1FF", tx("Eggs Broken"), Stats.Eggs),
				line("#FFA24A", tx("Animals Stolen"), Stats.Stolen),
				line("#C77DFF", tx("Mutated Stolen"), Stats.MutStolen),
			}
			local shown = {}
			for _, n in ipairs(MUT_ORDER) do
				shown[n] = true
				lines[#lines + 1] = "   " .. line(MUT_COLORS[n], n, Stats.Mut[n] or 0)
			end
			local extra = {}
			for n in pairs(Stats.Mut) do
				if not shown[n] then
					extra[#extra + 1] = n
				end
			end
			table.sort(extra)
			for _, n in ipairs(extra) do
				lines[#lines + 1] = "   " .. line("#E0E0E0", n, Stats.Mut[n])
			end
			return table.concat(lines, "\n")
		end

		local histCat = "Steal"
		local histRows = {}
		local histList, histEmpty

		local function esc(v)
			return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		end

		local function fmtNum(n)
			if type(n) ~= "number" then
				return "?"
			end
			for _, u in ipairs({ { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
				if n >= u[1] then
					local str = string.format("%.2f", n / u[1]):gsub("0+$", ""):gsub("%.$", "")
					return str .. u[2]
				end
			end
			return tostring(math.floor(n))
		end

		local function afkStamp(sec)
			if type(sec) ~= "number" then
				return ""
			end
			sec = math.max(0, math.floor(sec))
			local th = tx("History") ~= "History"
			local uh, um, us = "h", "m", "s"
			if th then
				uh, um, us = "ชั่วโมง", "นาที", "วินาที"
			end
			local h = sec // 3600
			local m = (sec % 3600) // 60
			local sp = th and " " or ""
			if h > 0 then
				if m > 0 then
					return ("%d%s%s %d%s%s"):format(h, sp, uh, m, sp, um)
				end
				return ("%d%s%s"):format(h, sp, uh)
			end
			if m > 0 then
				return ("%d%s%s"):format(m, sp, um)
			end
			return ("%d%s%s"):format(sec, sp, us)
		end

		local function rowText(entry)
			local head = Stats.RarityRich(entry.Rarity, entry.Name or "?", true)
			if entry.Kind == "Steal" and entry.Muts and #entry.Muts > 0 then
				local names = {}
				for _, n in ipairs(entry.Muts) do
					names[#names + 1] = ('<font color="%s"><b>%s</b></font>'):format(MUT_COLORS[n] or "#E0E0E0", esc(n))
				end
				head = head .. "  " .. table.concat(names, ", ")
			end
			if entry.Rarity then
				head = head .. "  " .. Stats.RarityRich(entry.Rarity, entry.Rarity, false)
			end
			local out = { head }
			if entry.Kind == "Steal" then
				out[#out + 1] = tx("Income / s") .. ": " .. fmtNum(entry.Income)
			else
				out[#out + 1] = tx("Max Health") .. ": " .. fmtNum(entry.MaxHealth)
				local sc = Stats.SizeScore(entry.Size)
				out[#out + 1] = tx("Size") .. ": " .. (sc and tostring(sc) or "?") .. " / 100"
			end
			local when = afkStamp(entry.AfkAt)
			if when ~= "" then
				out[#out + 1] = '<font color="#9AA0A6">' .. esc(when) .. "</font>"
			end
			return table.concat(out, "\n")
		end

		local function placeCam(v)
			local dir = Vector3.new(math.sin(v.angle) * 0.8, 0.45, math.cos(v.angle) * 0.8).Unit
			v.cam.CFrame = CFrame.lookAt(v.center + dir * v.dist, v.center)
		end

		local function mountView(vf, src)
			if not src then
				return nil
			end
			local ok, clone = pcall(function()
				return src:Clone()
			end)
			if not ok or not clone then
				return nil
			end
			local holder = Instance.new("Model")
			clone.Parent = holder
			holder.Parent = vf
			local cf, size
			local okb, cf0, size0 = pcall(function()
				return holder:GetBoundingBox()
			end)
			if okb and cf0 and size0 and size0.Magnitude > 0 then
				cf, size = cf0, size0
			else
				-- fallback: measure the parts by hand
				local mn, mx
				for _, d in ipairs(holder:GetDescendants()) do
					if d:IsA("BasePart") then
						local h = d.Size / 2
						local lo, hi = d.Position - h, d.Position + h
						if mn then
							mn = Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z))
							mx = Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z))
						else
							mn, mx = lo, hi
						end
					end
				end
				if mn then
					cf, size = CFrame.new((mn + mx) / 2), mx - mn
				end
			end
			if not cf or not size or size.Magnitude <= 0 then
				holder:Destroy()
				return nil
			end
			local cam = Instance.new("Camera")
			cam.FieldOfView = 40
			cam.Parent = vf
			vf.CurrentCamera = cam
			local v = {
				cam = cam,
				center = cf.Position,
				dist = (size.Magnitude / 2) / math.tan(math.rad(20)) * 1.05,
				angle = math.random() * 6.28,
			}
			placeCam(v)
			-- meshes / textures that are not loaded yet are what made some icons show up empty
			task.spawn(function()
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ holder })
				end)
			end)
			return v
		end

		local function firstChar(name)
			name = tostring(name or "?")
			local okc, e = pcall(utf8.offset, name, 2)
			local ch = okc and (e and name:sub(1, e - 1) or name) or name:sub(1, 1)
			if ch == "" then
				ch = "?"
			end
			return ch:upper()
		end

		local function retryMount(row)
			if row.view or not row.entry.Model or (row.tries or 0) >= 4 then
				return
			end
			row.tries = (row.tries or 0) + 1
			local v = mountView(row.vf, row.entry.Model)
			if v then
				row.view = v
				if row.ph then
					pcall(function()
						row.ph:Destroy()
					end)
					row.ph = nil
				end
			end
		end

		local function makeRow(entry, parent)
			local frame = New("Frame", {
				Size = UDim2.new(1, -4, 0, 80),
				BackgroundColor3 = COLOR.innerBg,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ZIndex = 22,
			}, parent)
			Corner(frame, 8)
			local vf = New("ViewportFrame", {
				Position = UDim2.fromOffset(6, 12),
				Size = UDim2.fromOffset(56, 56),
				BackgroundColor3 = COLOR.black,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Ambient = Color3.fromRGB(190, 190, 190),
				LightColor = Color3.new(1, 1, 1),
				LightDirection = Vector3.new(-1, -1, -0.5),
				ZIndex = 23,
			}, frame)
			Corner(vf, 8)
			local label = New("TextLabel", {
				Position = UDim2.fromOffset(68, 0),
				Size = UDim2.new(1, -72, 1, 0),
				BackgroundTransparency = 1,
				RichText = true,
				Text = "",
				Font = Enum.Font.GothamMedium,
				TextSize = 11,
				TextColor3 = COLOR.white,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped = true,
				ZIndex = 23,
			}, frame)
			local row = { frame = frame, label = label, vf = vf, entry = entry, tries = 0, text = "" }
			row.view = mountView(vf, entry.Model)
			if not row.view then
				-- no model / could not draw it: show the first letter in the rarity colour instead of "?"
				row.ph = New("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = firstChar(entry.Name),
					Font = Enum.Font.GothamBold,
					TextSize = 24,
					TextColor3 = Stats.RarityColor3(entry.Rarity),
					ZIndex = 24,
				}, vf)
			end
			return row
		end

		buildHistoryUI = function(Root)
			afkHist = New("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 52),
				Size = UDim2.fromOffset(170, 34),
				BackgroundColor3 = COLOR.innerBg,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				ZIndex = 7,
			}, Root)
			Corner(afkHist, 10)
			Stroke(afkHist, COLOR.innerBorder, 1.5, 0)
			local histTitle = New("TextLabel", {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -34, 1, 0),
				BackgroundTransparency = 1,
				Text = "",
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 8,
			}, afkHist)
			Lang.Bind(histTitle, "Text", "History")
			local histArrow = New("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				Text = "▼",
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = COLOR.grey,
				ZIndex = 8,
			}, afkHist)

			-- dropdown panel (opens under the button) with two tabs inside
			histPanel = New("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 92),
				Size = UDim2.new(0, 340, 1, -104),
				BackgroundColor3 = COLOR.black,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Visible = false,
				Active = true,
				ZIndex = 20,
			}, Root)
			Corner(histPanel, 12)
			Stroke(histPanel, COLOR.innerBorder, 1.5, 0)
			New("UISizeConstraint", { MinSize = Vector2.new(260, 160), MaxSize = Vector2.new(340, 440) }, histPanel)

			local TabBar = New("Frame", {
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(1, -16, 0, 32),
				BackgroundTransparency = 1,
				ZIndex = 21,
			}, histPanel)
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, TabBar)
			local tabs = {}
			local function mkTab(cat, order)
				local b = New("TextButton", {
					LayoutOrder = order,
					Size = UDim2.new(0.5, -3, 1, 0),
					BackgroundColor3 = COLOR.innerBg,
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Text = "",
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = Color3.new(1, 1, 1),
					ZIndex = 22,
				}, TabBar)
				Corner(b, 8)
				Stroke(b, COLOR.innerBorder, 1.2, 0)
				tabs[cat] = b
				track(b.Activated:Connect(function()
					histCat = cat
					histRefresh()
				end))
			end
			mkTab("Steal", 1)
			mkTab("Eggs", 2)

			histList = New("ScrollingFrame", {
				Position = UDim2.fromOffset(8, 48),
				Size = UDim2.new(1, -16, 1, -56),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ZIndex = 21,
			}, histPanel)
			New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, histList)

			histEmpty = New("TextLabel", {
				Position = UDim2.fromOffset(8, 48),
				Size = UDim2.new(1, -16, 1, -56),
				BackgroundTransparency = 1,
				Text = "",
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = COLOR.grey,
				ZIndex = 22,
			}, histPanel)

			track(afkHist.Activated:Connect(function()
				histPanel.Visible = not histPanel.Visible
				histArrow.Text = histPanel.Visible and "▲" or "▼"
				if histPanel.Visible then
					histRefresh()
				end
			end))

			histRefresh = function()
				if not (histPanel and histPanel.Parent and histPanel.Visible) then
					return
				end
				tabs.Steal.Text = tx("Stolen Animals")
				tabs.Eggs.Text = tx("Broken Eggs")
				for cat, b in pairs(tabs) do
					b.BackgroundColor3 = (cat == histCat) and COLOR.red or COLOR.innerBg
				end
				local list = Stats.History[histCat]
				local present = {}
				for _, entry in ipairs(list) do
					present[entry] = true
				end
				for entry, row in pairs(histRows) do
					if not present[entry] then
						pcall(function()
							row.frame:Destroy()
						end)
						histRows[entry] = nil
					end
				end
				local made = 0
				for i, entry in ipairs(list) do
					local row = histRows[entry]
					if not row then
						if made >= 20 then
							break
						end
						made += 1
						row = makeRow(entry, histList)
						histRows[entry] = row
					end
					row.frame.LayoutOrder = i
					retryMount(row)
					local t = rowText(entry)
					if row.text ~= t then
						row.text = t
						row.label.Text = t
					end
				end
				histEmpty.Visible = #list == 0
				histEmpty.Text = tx("No history yet")
			end

			track(RunService.Heartbeat:Connect(function(dt)
				if not (AFK.Active and histPanel and histPanel.Parent and histPanel.Visible) then
					return
				end
				local lp, ls = histList.AbsolutePosition, histList.AbsoluteSize
				for _, row in pairs(histRows) do
					local v = row.view
					if v then
						local y = row.frame.AbsolutePosition.Y
						if y + row.frame.AbsoluteSize.Y >= lp.Y and y <= lp.Y + ls.Y then
							v.angle += dt * 1.2
							placeCam(v)
						end
					end
				end
			end))
		end

		function afkRefresh()
			if afkTime and afkTime.Parent then
				afkTime.Text = fmtTime(AFK.Elapsed + (AFK.Active and (os.clock() - AFK.StartedAt) or 0))
			end
			if afkStats and afkStats.Eggs and afkStats.Eggs.Parent then
				afkStats.Eggs.Text = tostring(Stats.Eggs)
				afkStats.Stolen.Text = tostring(Stats.Stolen)
				afkStats.MutStolen.Text = tostring(Stats.MutStolen)

				-- mutation chips (only mutations that were actually stolen)
				local names = {}
				for n, c in pairs(Stats.Mut) do
					if c > 0 then
						names[#names + 1] = n
					end
				end
				table.sort(names)
				local sig = {}
				for _, n in ipairs(names) do
					sig[#sig + 1] = n .. ":" .. Stats.Mut[n]
				end
				sig = table.concat(sig, "|")
				if sig ~= afkStats.MutSig then
					afkStats.MutSig = sig
					for _, ch in ipairs(afkStats.MutRow:GetChildren()) do
						if ch:IsA("TextLabel") then
							ch:Destroy()
						end
					end
					for i, n in ipairs(names) do
						local col = Color3.fromHex(MUT_COLORS[n] or "#E0E0E0")
						local chip = New("TextLabel", {
							LayoutOrder = i,
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, 26),
							BackgroundColor3 = COLOR.innerBg,
							BackgroundTransparency = 0.15,
							BorderSizePixel = 0,
							Text = n .. "  " .. Stats.Mut[n],
							Font = Enum.Font.GothamBold,
							TextSize = 12,
							TextColor3 = col,
							ZIndex = 6,
						}, afkStats.MutRow)
						Corner(chip, 8)
						Stroke(chip, col, 1, 0.5)
						New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
					end
				end

				-- system status dots
				local ON, OFF = Color3.fromRGB(46, 204, 113), Color3.fromRGB(100, 100, 100)
				afkStats.Dots.Break.BackgroundColor3 = (SW.Running or TT.Running) and ON or OFF
				afkStats.Dots.Steal.BackgroundColor3 = ST.Running and ON or OFF
				afkStats.Dots.Treadmill.BackgroundColor3 = TM.Running and ON or OFF
			end
			if histRefresh then
				histRefresh()
			end
		end

		local function afkOn()
			if AFK.Active then
				return true
			end
			local data
			if AFK.Config and AFK.Config ~= "" then
				data = Config.Read(AFK.Config)
				if not data then
					Notify("Could not read config", false)
					return false
				end
			end
			AFK.Snapshot = CollectConfig()
			AFK.Active = true
			AFK.StartedAt = os.clock()
			Stats.On = true
			AFK.Job += 1
			if data then
				ApplyConfig(data.Values)
			end
			local g = buildAfkGui()
			g.Enabled = true
			afkRefresh()
			if AFK.AntiIdle then
				startAntiIdle()
			end
			local job = AFK.Job
			task.spawn(function()
				local lastPoke = os.clock()
				local lastJump = os.clock()
				while AFK.Active and AFK.Job == job do
					pcall(afkRefresh)
					if AFK.AntiIdle and os.clock() - lastPoke >= 30 then
						lastPoke = os.clock()
						poke()
					end
					if AFK.AntiIdle and os.clock() - lastJump >= 40 then
						lastJump = os.clock()
						local hum = getHumanoid()
						if hum and hum.Health > 0 then
							hum.Jump = true
						end
					end
					task.wait(0.5)
				end
			end)
			return true
		end

		local function afkOff()
			if not AFK.Active then
				return
			end
			AFK.Elapsed += os.clock() - AFK.StartedAt
			Stats.On = false
			AFK.Active = false
			AFK.Job += 1
			if afkGui then
				afkGui.Enabled = false
			end
			pcall(stopAntiIdle)
			local snap = AFK.Snapshot
			AFK.Snapshot = nil
			-- restoring the snapshot may flip the AFK switch back ON (it was ON when the snapshot was taken): block that
			AFK.Closing = true
			if snap then
				local ok, err = pcall(ApplyConfig, snap)
				if not ok then
					warn("[LUNAR Hub] AFK restore error: " .. tostring(err))
				end
			end
			AFK.Active = false
			AFK.Snapshot = nil
			Stats.On = false
			if afkGui then
				afkGui.Enabled = false
			end
			if afkToggle then
				pcall(afkToggle.Set, false, true)
			end
			task.delay(1.5, function()
				AFK.Closing = false
			end)
		end
		afkOffFn = afkOff

		addCleanup(function()
			Stats.On = false
			AFK.Active = false
			AFK.Job += 1
			stopAntiIdle()
			if afkGui then
				pcall(function()
					afkGui:Destroy()
				end)
			end
		end)

		Section(Page, "AFK Mode")
		Dropdown(Page, "AFK Config", {
			Options = function()
				return Config.List()
			end,
			Placeholder = "Select a config...",
			Desc = "Config used while AFK Mode is ON (optional)",
			OnChange = function(v)
				AFK.Config = (v ~= nil and v ~= "") and v or nil
			end,
		})
		local _afk
		_afk, afkToggle = Toggle(Page, "AFK Mode", false, function(on)
			if on and AFK.Closing then
				if afkToggle then
					pcall(afkToggle.Set, false, true)
				end
				return
			end
			if on then
				if not afkOn() then
					afkToggle.Set(false, true)
				end
			else
				afkOff()
			end
		end, nil, "Covers the screen with the LUNAR HUB screen and shows how long it has been running. Uses the chosen AFK Config while ON and restores your previous settings when closed")
	end

	Section(Page2, "Auto Extras")
	setTmStatus = StatusCard(Page2, "Idle")
	setEqStatus = StatusCard(Page2, "Idle")
	Toggle(Page2, "Auto Treadmill", false, function(on)
		if on then
			TM.Start()
			setTmStatus("Started")
		else
		TM.Stop()
		end
	end, nil, "Lowest priority: walks to your treadmill when nothing else is working, leaves when another function starts")
	Toggle(Page2, "Auto Equip Best Pets", false, function(on)
		if on then
			EQ.Start()
		else
			EQ.Stop()
		end
	end, nil, "Equips your best pets once after every successful steal, after a random 1 - 5 second delay")
	Toggle(Page2, "Auto Place Eggs", false, function(on)
		if on then
			if SW.PEStart then
				SW.PEStart()
			end
		elseif SW.PEStop then
			SW.PEStop()
		end
	end, nil, "Walks to your plot (TP Walk, speed 100), holds each egg you carry and keeps placing eggs at random spots while it keeps TP-walking around your garden, with no delay and no messages. Pauses while Auto Steal / a Hell Event is working")

	Section(Page, "Auto Break")
	setSwStatus = StatusCard(Page, "Idle")
	setTtStatus = StatusCard(Page, "Idle")
	local _
	_, swToggle = Toggle(Page, "Auto Break", false, function(on)
		if on then
			if not swStart() then
				swToggle.Set(false, true)
			else
				ttStart()
				setSwStatus("Started")
			end
		else
			ttStop()
			swStop()
		end
	end, nil, "Walk to eggs + keep the game's AutoSwing ON. Also breaks the Titanic Egg when it spawns (pauses while Auto Steal works)")
	Toggle(Page, "Auto Collect Gems", false, function(on)
		if on then
			GM.Start()
		else
			GM.Stop()
		end
	end, nil, "Walks to the nearest gem at the game's own walk speed (controls are overridden while it walks); when it disappears it moves to the next one, and idles when no gem is left (Auto Break keeps working). Auto Steal has priority")
	Dropdown(Page, "Egg Rarity", {
		Multi = true,
		Options = BREAK_RARITIES,
		Default = { "Ethereal", "Spectral", "Omega", "Void" },
		Placeholder = "Select rarity",
		Desc = "Tap to choose one or more",
		OnChange = function(chosen)
			SW.Rarity = toSet(chosen)
		end,
	})
	local SW_ZONES = {}
	for z = 1, 13 do
		SW_ZONES[z] = "Zone " .. z
	end
	Dropdown(Page, "Egg Zone", {
		Multi = true,
		Options = SW_ZONES,
		Default = SW_ZONES,
		Placeholder = "Select zone",
		Format = function(names)
			local nums = {}
			for _, nm in ipairs(names) do
				local z = tonumber(tostring(nm):match("%d+"))
				if z then table.insert(nums, z) end
			end
			table.sort(nums)
			local parts, i = {}, 1
			while i <= #nums do
				local j = i
				while nums[j + 1] == nums[j] + 1 do j += 1 end
				table.insert(parts, j > i and (nums[i] .. "-" .. nums[j]) or tostring(nums[i]))
				i = j + 1
			end
			return Tr("Zone") .. " " .. table.concat(parts, ", ")
		end,
		Desc = "Only break eggs in the chosen zones (none chosen = all zones). If a chosen zone is beyond the Divine zone (7), none of its eggs is in sight and its map is not loaded, Auto Break goes to the Divine zone first",
		OnChange = function(chosen)
			SW.Zone = {}
			for _, n in ipairs(chosen) do
				local z = tonumber(tostring(n):match("%d+"))
				if z then
					SW.Zone[z] = true
				end
			end
		end,
	})
	Dropdown(Page, "Auto Break Egg Order", {
		Options = { "Largest first", "Smallest first", "Nearest first" },
		Default = "Largest first",
		Placeholder = "Largest first",
		Desc = "Tap to choose which matching egg Auto Break goes for first: the biggest, the smallest, or the closest to you",
		OnChange = function(v)
			if v == "Smallest first" or v == "Nearest first" then
				SW.Order = v
			else
				SW.Order = "Largest first"
			end
		end,
	})
	local TT_ZONES = {}
	for z = 1, 13 do
		TT_ZONES[z] = "Zone " .. z
	end
	Dropdown(Page, "Titanic Zones", {
		Multi = true,
		Options = TT_ZONES,
		Default = TT_ZONES,
		Placeholder = "Select zone",
		Format = function(names)
			local nums = {}
			for _, nm in ipairs(names) do
				local z = tonumber(tostring(nm):match("%d+"))
				if z then table.insert(nums, z) end
			end
			table.sort(nums)
			local parts, i = {}, 1
			while i <= #nums do
				local j = i
				while nums[j + 1] == nums[j] + 1 do j += 1 end
				table.insert(parts, j > i and (nums[i] .. "-" .. nums[j]) or tostring(nums[i]))
				i = j + 1
			end
			return Tr("Zone") .. " " .. table.concat(parts, ", ")
		end,
		Desc = "Only break the Titanic Egg in the chosen zones",
		OnChange = function(chosen)
			TT.Zone = {}
			for _, n in ipairs(chosen) do
				local z = tonumber(tostring(n):match("%d+"))
				if z then
					TT.Zone[z] = true
				end
			end
		end,
	})

	local SAFE = Vector3.new(-72.500, 3.693, 0)
	local GROUND_Y = 3.693
	local ZONE_X = {
		[1] = { -174.5, -81.5 }, [2] = { -304.0, -187.0 }, [3] = { -463.2, -315.8 },
		[4] = { -681.8, -475.2 }, [5] = { -960.8, -694.2 }, [6] = { -1299.8, -973.2 },
		[7] = { -1819.5, -1311.5 }, [8] = { -2338.0, -1831.0 }, [9] = { -2863.0, -2350.0 },
		[10] = { -3565.0, -2863.0 }, [11] = { -4276.0, -3565.0 }, [12] = { -5268.0, -4276.0 }, [13] = { -5834.0, -5268.0 },
	}
	local stJob = 0

	local function inAnyZone(pos)
		return pos.X <= ZONE_X[1][2] and pos.X >= ZONE_X[13][1] - 5
	end
	EventGate.Safe = SAFE
	EventGate.InZone = inAnyZone

	local function stAlive(id)
		if ST.Ext and ST.Ext.id == id then
			return ST.Ext.alive() == true
		end
		return ST.Running and stJob == id
	end

	local function stStatus(t)
		if ST.Ext then
			ST.Ext.say(t)
			return
		end
		if setStStatus then
			setStStatus(t .. "   |   Stolen: " .. ST.Collected)
		end
	end

	local saved, humState = {}, nil

	local function lockControls(on)
		if on then
			pcall(function()
				ContextActionService:BindActionAtPriority("LunarStealLock", function()
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value + 100,
					Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
					Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight,
					Enum.PlayerActions.CharacterJump)
			end)
		else
			pcall(function()
				ContextActionService:UnbindAction("LunarStealLock")
			end)
		end
	end

	local function freezeHumanoid()
		local h = getHumanoid()
		if not h then
			return
		end
		if not humState then
			humState = { h = h, ws = h.WalkSpeed, jp = h.JumpPower, jh = h.JumpHeight }
		end
		if ST.Walking then
			if h.WalkSpeed ~= humState.ws then h.WalkSpeed = humState.ws end
			if h.JumpPower ~= humState.jp then h.JumpPower = humState.jp end
			if h.JumpHeight ~= humState.jh then h.JumpHeight = humState.jh end
			return
		end
		if h.WalkSpeed ~= 0 then h.WalkSpeed = 0 end
		if h.JumpPower ~= 0 then h.JumpPower = 0 end
		if h.JumpHeight ~= 0 then h.JumpHeight = 0 end
	end

	local function unfreezeHumanoid()
		if humState then
			local h = humState.h
			if h and h.Parent then
				h.WalkSpeed = humState.ws
				h.JumpPower = humState.jp
				h.JumpHeight = humState.jh
			end
			humState = nil
		end
	end

	local function restoreCollide()
		for p, v in pairs(saved) do
			if p and p.Parent then
				p.CanCollide = v
			end
		end
		table.clear(saved)
	end

	local function setBusy(b)
		if ST.Busy == b then
			return
		end
		ST.Busy = b
		EventGate.StealBusy = b
		if b then
			lockControls(true)
			freezeHumanoid()
		else
			lockControls(false)
			unfreezeHumanoid()
			restoreCollide()
		end
	end

	local stParts, stPartsChar, stPartsAt = {}, nil, 0
	local function stGetParts(c)
		local now = os.clock()
		if stPartsChar ~= c or now - stPartsAt > 0.5 then
			stPartsChar, stPartsAt = c, now
			stParts = {}
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") then
					stParts[#stParts + 1] = p
				end
			end
		end
		return stParts
	end

	track(RunService.Stepped:Connect(function()
		if not (ST.Running and ST.Busy) then
			return
		end
		freezeHumanoid()
		if not ST.Noclip or ST.CE.Mode then
			return
		end
		local c = LocalPlayer.Character
		if not c then
			return
		end
		for _, p in ipairs(stGetParts(c)) do
			if saved[p] == nil then
				saved[p] = p.CanCollide
			end
			if p.CanCollide then
				p.CanCollide = false
			end
		end
	end))

	local lastRagCheck, lastRagState = 0, 0
	local function antiRagdoll()
		if os.clock() - lastRagState < 0.1 then
			return
		end
		lastRagState = os.clock()
		local c = LocalPlayer.Character
		local h = getHumanoid()
		if not (c and h) then
			return
		end
		pcall(function()
			h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			if h.PlatformStand then
				h.PlatformStand = false
			end
			local st = h:GetState()
			if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		if os.clock() - lastRagCheck < 0.25 then
			return
		end
		lastRagCheck = os.clock()
		pcall(function()
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BallSocketConstraint") then
					d.Enabled = false
				elseif d:IsA("Motor6D") and not d.Enabled then
					d.Enabled = true
				end
			end
		end)
	end

	local function restoreRagdollStates()
		local h = getHumanoid()
		if h then
			pcall(function()
				h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
				h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			end)
		end
	end

	track(RunService.Heartbeat:Connect(function()
		if not ST.Running then
			return
		end
		if ST.AntiRagdoll and not ST.TpMode and not ST.Ext then
			antiRagdoll()
		end
		if not ST.Busy then
			return
		end
		local hrp = getHRP()
		if not hrp then
			return
		end
		if not ST.Walking then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
		local p = hrp.Position
		if p.Y < GROUND_Y - 3 or p.Y > GROUND_Y + 12 then
			hrp.CFrame = CFrame.new(p.X, GROUND_Y, p.Z)
		end
	end))

	track(LocalPlayer.CharacterAdded:Connect(function()
		table.clear(saved)
		humState = nil
	end))

	local TemplateRarity = {}
	pcall(function()
		local root = ReplicatedStorage:FindFirstChild("Animals") or ReplicatedStorage
		for _, d in ipairs(root:GetDescendants()) do
			local r = d:GetAttribute("Rarity")
			if r and (d:IsA("Model") or d:IsA("Folder")) then
				TemplateRarity[d.Name:lower()] = tostring(r)
			end
		end
	end)

	local rarityCache = setmetatable({}, { __mode = "k" })
	local function getRarity(obj)
		if rarityCache[obj] then
			return rarityCache[obj]
		end
		local res
		local cur = obj
		for _ = 1, 4 do
			if not cur then
				break
			end
			local v = cur:GetAttribute("Rarity")
			if typeof(v) == "string" and v ~= "" then
				res = v
				break
			end
			cur = cur.Parent
		end
		if not res then
			local nm = obj:GetAttribute("AnimalName") or obj.Name
			res = TemplateRarity[tostring(nm):lower()]
		end
		if not res then
			local rf = ReplicatedStorage:FindFirstChild("Rarities")
			if rf and rf:IsA("ModuleScript") then
				local ok, data = pcall(require, rf)
				if ok and type(data) == "table" then
					local e = data[obj.Name]
					if type(e) == "string" then
						res = e
					elseif type(e) == "table" then
						res = e.Rarity or e.rarity
					end
				end
			end
		end
		if not res then
			for _, d in ipairs(obj:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and RANK[d.Text] then
					res = d.Text
					break
				end
				if d:IsA("UIGradient") and RANK[d.Name] then
					res = d.Name
					break
				end
				local v = d:GetAttribute("Rarity")
				if typeof(v) == "string" and v ~= "" then
					res = v
					break
				end
			end
		end
		if not res then
			local low = obj.Name:lower()
			for _, r in ipairs(STEAL_RARITIES) do
				if low:find(r:lower(), 1, true) then
					res = r
					break
				end
			end
		end
		if res then
			rarityCache[obj] = res
		end
		return res
	end

	local function zoneOfX(x)
		for z, rng in pairs(ZONE_X) do
			if x >= rng[1] - 5 and x <= rng[2] + 5 then
				return z
			end
		end
		local best, bd = nil, math.huge
		for z, rng in pairs(ZONE_X) do
			local d = math.min(math.abs(x - rng[1]), math.abs(x - rng[2]))
			if d < bd then
				best, bd = z, d
			end
		end
		return best
	end

	local function zoneIdx(pos)
		if pos.X > ZONE_X[1][2] + 5 then
			return 0
		end
		return zoneOfX(pos.X) or 0
	end

	local function zoneGap(a, b)
		return math.abs(zoneIdx(a) - zoneIdx(b))
	end

	local function getPart(o)
		if o:IsA("BasePart") then
			return o
		end
		if o:IsA("Model") then
			return o.PrimaryPart or o:FindFirstChild("HumanoidRootPart") or o:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	local MONEY_MULT = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
	local function toNumber(num, suffix)
		local n = tonumber((tostring(num):gsub(",", "")))
		if not n then return nil end
		return n * (MONEY_MULT[tostring(suffix or ""):upper()] or 1)
	end

	local function parseAmount(text)
		if type(text) ~= "string" then return nil end
		local num, suf = text:match("([%d][%d,%.]*)%s*([KkMmBbTt]?)")
		if not num then return nil end
		return toNumber(num, suf)
	end

	local function formatAmount(n)
		if type(n) ~= "number" or n <= 0 then return "" end
		for _, u in ipairs({ { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
			if n >= u[1] then
				local str = string.format("%.2f", n / u[1]):gsub("0+$", ""):gsub("%.$", "")
				return str .. u[2]
			end
		end
		return tostring(math.floor(n))
	end

	local function incomeFromText(text)
		if type(text) ~= "string" or not text:find("/", 1, true) then return nil end
		text = text:gsub("<[^>]->", "")
		local num, suf = text:match("([%d][%d,%.]*)%s*([KkMmBbTt]?)%s*/%s*[sS]")
		if not num then return nil end
		return toNumber(num, suf)
	end
	local incomeLabel = setmetatable({}, { __mode = "k" })

	local function incomeOf(obj)
		local lbl = incomeLabel[obj]
		if lbl and lbl.Parent then
			local v = incomeFromText(lbl.Text)
			if v then return v end
		end
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				local v = incomeFromText(d.Text)
				if v then
					incomeLabel[obj] = d
					return v
				end
			end
		end
		return nil
	end
	-- the filter in use: Auto Steal's own, or the Auto Carry Escape one while it runs
	local function FL()
		if ST.CE.Mode and ST.CE.F then
			return ST.CE.F
		end
		return ST
	end
	local function passIncome(obj)
		local minInc = FL().MinIncome
		if minInc <= 0 then return true end
		local inc = incomeOf(obj)
		if inc == nil then
			ST.Unread += 1
			return false
		end
		return inc >= minInc
	end

	local MUT_NAMES = { "Gold", "Diamond", "Lightning", "Angelic", "Frozen", "Lucky",
		"Void", "Time", "Hacker", "Fallen Angel", "Fallen Angel Gold", "Fallen Angel Diamond", "Devil Gold", "Devil Diamond" }
	local MUT_CANON = {}
	for _, n in ipairs(MUT_NAMES) do MUT_CANON[n:lower()] = n end

	task.spawn(function()
		local m = ReplicatedStorage:FindFirstChild("MutationConfig", true)
		if m and m:IsA("ModuleScript") then
			local ok, t = pcall(require, m)
			if ok and type(t) == "table" then
				local keys = {}
				for k in pairs(t) do keys[#keys + 1] = tostring(k) end
				table.sort(keys)
				warn("[LUNAR Hub] MutationConfig keys: " .. table.concat(keys, ", "))
			end
		end
	end)

	local function mutationsOf(obj)
		local found, source = {}, nil
		local function addValue(v, from)
			if typeof(v) ~= "string" or v == "" then return end
			local canon = MUT_CANON[v:lower()]
			if canon then
				found[canon] = true
			else

				local hit = false
				for low, n in pairs(MUT_CANON) do
					if v:lower():find(low, 1, true) then found[n] = true; hit = true end
				end
				if not hit then found[v] = true end
			end
			source = source or from
		end
		local function scanAttrs(inst)
			if not inst then return end
			addValue(inst:GetAttribute("Variant"), "attr Variant")
			for k, v in pairs(inst:GetAttributes()) do
				local kl = tostring(k):lower()
				if k ~= "Variant" and (kl:find("mutation", 1, true) or kl:find("variant", 1, true)) then
					addValue(v, "attr " .. tostring(k))
				end
			end
		end
		scanAttrs(obj)
		scanAttrs(getPart(obj))
		if next(found) == nil then

			for _, c in ipairs(obj:GetChildren()) do
				if c:IsA("Model") or c:IsA("BasePart") then scanAttrs(c) end
			end
		end
		if next(found) == nil then

			for _, d in ipairs(obj:GetDescendants()) do
				if d.Name == "Mutation" and d:IsA("GuiObject") and d.Visible then
					for _, c in ipairs(d:GetChildren()) do
						if c:IsA("GuiObject") and c.Visible and MUT_CANON[c.Name:lower()] then
							found[MUT_CANON[c.Name:lower()]] = true
							source = source or "UI"
						end
					end
				end
			end
		end
		return found, source
	end

	local function chosenFrom(found)
		local want = FL().Mutation
		if next(want) == nil then
			return false
		end
		for n in pairs(want) do
			if found[n] then
				return true
			end
		end
		return false
	end

	local dbgSeen = {}
	local function dbgLog(o, msg)
		if dbgSeen[o] == msg then return end
		dbgSeen[o] = msg
		warn("[LUNAR Hub] Steal: " .. tostring(o.Name) .. " " .. msg)
	end

	local function getTargets(skip)
		local list, skipped = {}, 0
		ST.Unread = 0
		ST.Why = ""
		local folder = Workspace:FindFirstChild("AnimalPickups")
		if not folder then
			return list, skipped
		end
		local hrp = getHRP()
		local cut = { rarity = 0, norarity = 0, income = 0 }
		local total = 0
		for _, o in ipairs(folder:GetChildren()) do
			local part = getPart(o)
			-- Auto Carry Escape: never pick up an animal lying where we noclip (all of zone 1, or within 120 studs of the
			-- escape spot): that is where an animal you put down ends up, even if you walk away from it afterwards
			if part and ST.CE.Mode
				and (Vector3.new(part.Position.X - ST.CE.Pos.X, 0, part.Position.Z - ST.CE.Pos.Z).Magnitude <= 120
					or (inAnyZone(part.Position) and zoneIdx(part.Position) == 1)) then
				part = nil
			end
			if part then
				total += 1
				local r = getRarity(o)
				local z = zoneOfX(part.Position.X)
				local muts, msrc = mutationsOf(o)
				local hasMut = next(muts) ~= nil
				local chosen = chosenFrom(muts)
				local mutText = ""
				if hasMut then
					local names = {}
					for n in pairs(muts) do names[#names + 1] = n end
					table.sort(names)
					mutText = table.concat(names, "+") .. " (" .. tostring(msrc) .. ")"
				end

				local reason
				if not r then
					reason = "cut: rarity unreadable"
					cut.norarity += 1
				elseif not FL().Rarity[r] then
					reason = "cut: rarity " .. r .. " not selected"
					cut.rarity += 1
				elseif not (chosen or passIncome(o)) then
					reason = hasMut and ("cut: " .. mutText .. " not chosen and income below Min Income")
						or "cut: income below Min Income / unreadable"
					cut.income += 1
				end
				if hasMut then
					dbgLog(o, ("Variant=%s rarity=%s chosen=%s -> %s"):format(mutText, tostring(r), tostring(chosen), reason or "OK"))
				end
				if not reason then
					if skip[o] and skip[o] > os.clock() then
						skipped += 1
					else
						table.insert(list, {
							obj = o,
							part = part,
							rarity = r,
							rank = RANK[r] or 0,
							mut = chosen and 1 or 0,
							zone = z or 0,
							d = hrp and (part.Position - hrp.Position).Magnitude or 0,
						})
					end
				end
			end
		end
		if total > 0 and #list == 0 and skipped == 0 then
			ST.Why = ("%d animals: rarity not selected %d, income/mutation %d, rarity unreadable %d"):format(total, cut.rarity, cut.income, cut.norarity)
		end

		table.sort(list, function(a, b)
			if a.mut ~= b.mut then
				return a.mut > b.mut
			end
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			return a.d < b.d
		end)
		return list, skipped
	end

	local function sleep(t, id)
		local t0 = os.clock()
		while os.clock() - t0 < t do
			if not stAlive(id) then
				return false
			end
			RunService.Heartbeat:Wait()
		end
		return stAlive(id)
	end

	-- ===== Landing safety for far teleports (StreamingEnabled) =====
	-- A far teleport can land where the floor is not streamed in yet: the character falls through the gap and keeps
	-- falling once the floor appears above it. So: ask the game to stream the destination first, wait until a floor is
	-- found, hold the character at the target height until it stands on something, and pull it back if it still ends
	-- up far below the map.
	local function floorRay(pos, up, down)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LocalPlayer.Character }
		local r = Workspace:Raycast(Vector3.new(pos.X, pos.Y + up, pos.Z), Vector3.new(0, -(up + down), 0), params)
		if r and r.Position.Y > GROUND_Y - 20 then
			return r
		end
		return nil
	end

	function ST.PrepareLanding(pos)
		pcall(function()
			LocalPlayer:RequestStreamAroundAsync(pos, 1.5)
		end)
		local t = os.clock()
		while os.clock() - t < 1.5 and not floorRay(pos, 60, 200) do
			RunService.Heartbeat:Wait()
		end
		return floorRay(pos, 60, 200) ~= nil
	end

	function ST.HoldLanding(pos, id)
		local t = os.clock()
		while os.clock() - t < 1.5 do
			local hrp = getHRP()
			if not hrp or (id and not stAlive(id)) then
				return
			end
			if floorRay(hrp.Position, 0, 15) then
				return
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			if hrp.Position.Y < pos.Y - 1 then
				hrp.CFrame = CFrame.new(hrp.Position.X, pos.Y, hrp.Position.Z)
			end
			RunService.Heartbeat:Wait()
		end
	end

	do
		local lastSafe, nextSave = SAFE, 0
		track(RunService.Heartbeat:Connect(function()
			if not (ST.Running or ST.Ext or (ST.CE and (ST.CE.Running or ST.CE.Mode))) then
				return
			end
			local hrp = getHRP()
			if not hrp then
				return
			end
			local p = hrp.Position
			if p.Y < GROUND_Y - 30 then
				-- fell under the map: back to the last safe spot
				hrp.CFrame = CFrame.new(lastSafe)
				hrp.AssemblyLinearVelocity = Vector3.zero
			elseif p.Y >= GROUND_Y - 3 and p.Y <= GROUND_Y + 12 and os.clock() >= nextSave and floorRay(p, 0, 15) then
				lastSafe = p
				nextSave = os.clock() + 0.5
			end
		end))
	end

	local function moveTo(target, id, stopDist, abortFn, forceWalk, abortEvery, speed)
		stopDist = stopDist or 2.5
		local spd = speed or ST.Speed
		local nextCheck = 0
		local function resolve()
			if type(target) == "function" then
				return target()
			end
			return target
		end
		local hrp = getHRP()
		local pos = resolve()
		if not hrp or not pos then
			return false
		end
		if (ST.TpMode or ST.Ext) and ST.TpArmed and not forceWalk then

			if not stAlive(id) or EventGate.Abort then
				return false
			end
			local np = Vector3.new(pos.X, GROUND_Y, pos.Z)
			local far = (hrp.Position - np).Magnitude > 200
			if far then
				-- far teleport: make the destination floor load first
				ST.PrepareLanding(np)
				if not stAlive(id) or EventGate.Abort then
					return false
				end
				hrp = getHRP()
				if not hrp then
					return false
				end
			end
			hrp.CFrame = CFrame.new(np)
			hrp.AssemblyLinearVelocity = Vector3.zero
			if far then
				ST.HoldLanding(np, id)
			end
			RunService.Heartbeat:Wait()
			return true
		end
		-- TP Walk: ขยับตัวละครด้วย CFrame ตามความเร็ว spd (studs/วินาที)
		local t0 = os.clock()
		local off0 = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z).Magnitude
		local timeout = off0 / math.max(spd, 1) * 3 + 8
		while stAlive(id) and not EventGate.Abort do
			hrp = getHRP()
			pos = resolve()
			if not hrp or not pos then
				return false
			end
			local off = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
			if off.Magnitude <= stopDist then
				return true
			end
			if os.clock() - t0 > timeout then
				return false
			end
			if abortFn and os.clock() > nextCheck then
				nextCheck = os.clock() + (abortEvery or 0.4)
				if abortFn() then
					return false
				end
			end
			local dt = math.min(RunService.Heartbeat:Wait(), 0.05)
			if not stAlive(id) then
				return false
			end
			local step = math.min(spd * dt, off.Magnitude)
			local np = hrp.Position + off.Unit * step
			np = Vector3.new(np.X, GROUND_Y, np.Z)
			hrp.CFrame = CFrame.new(np, np + Vector3.new(off.X, 0, off.Z))
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		return false
	end

	local lockConn
	local function cleanupLock()
		if lockConn then
			lockConn:Disconnect()
			lockConn = nil
		end
	end

	local function carriedCount()
		local f = Workspace:FindFirstChild("CarriedAnimals")
		return f and #f:GetDescendants() or 0
	end

	local function isStolen(obj, before)
		if not obj.Parent then
			return true
		end
		local f = Workspace:FindFirstChild("CarriedAnimals")
		if not f then
			return false
		end
		if obj:IsDescendantOf(f) then
			return true
		end
		if #f:GetDescendants() > before then
			for _, d in ipairs(f:GetDescendants()) do
				if d.Name == obj.Name then
					return true
				end
			end
		end
		return false
	end

	local function findPrompt(obj, part, allowGlobal)
		local found
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				if d.ActionText == "Steal" then
					return d
				end
				found = found or d
			end
		end
		if obj:IsA("ProximityPrompt") then
			return obj
		end
		if found then
			return found
		end
		if allowGlobal and part then
			local best, bd = nil, 15
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d:IsA("ProximityPrompt") and (d.ActionText == "Steal" or d.ObjectText == obj.Name) then
					local p = d.Parent
					local pos = p and (p:IsA("Attachment") and p.WorldPosition or p:IsA("BasePart") and p.Position)
					if pos then
						local dist = (pos - part.Position).Magnitude
						if dist < bd then
							best, bd = d, dist
						end
					end
				end
			end
			return best
		end
	end

	local function promptPos(prompt, part)
		local p = prompt and prompt.Parent
		if p then
			if p:IsA("Attachment") then
				return p.WorldPosition
			end
			if p:IsA("BasePart") then
				return p.Position
			end
		end
		return part and part.Position
	end

	local function firePrompt(prompt, attempt)
		pcall(function()
			prompt.Enabled = true
			prompt.MaxActivationDistance = 60
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0
		end)
		if fireproximityprompt and attempt % 3 ~= 0 then
			pcall(fireproximityprompt, prompt)
		else
			pcall(function()
				prompt:InputHoldBegin()
				task.wait(0.1)
				prompt:InputHoldEnd()
			end)
		end
	end

	local function groundClamp(v)
		return Vector3.new(v.X, math.clamp(v.Y, GROUND_Y, GROUND_Y + 5), v.Z)
	end

	local function verifyTarget(o)
		if not (o and o.Parent) then
			return false
		end
		local pf = Workspace:FindFirstChild("AnimalPickups")
		if pf and not o:IsDescendantOf(pf) then
			return false
		end
		local r = getRarity(o)
		if not r or not FL().Rarity[r] then
			return false
		end
		if chosenFrom((mutationsOf(o))) then
			return true
		end
		return passIncome(o)
	end

	local function snapshotCarried()
		local s = {}
		local f = Workspace:FindFirstChild("CarriedAnimals")
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				s[d] = true
			end
		end
		return s
	end

	local function findMine(obj, beforeSet)
		local f = Workspace:FindFirstChild("CarriedAnimals")
		if not f then
			return nil
		end
		if obj.Parent and obj:IsDescendantOf(f) then
			return obj
		end
		local fallback
		for _, d in ipairs(f:GetDescendants()) do
			if not beforeSet[d] then
				if d.Name == obj.Name then
					return d
				end
				fallback = fallback or d
			end
		end
		return fallback
	end

	local function collect(obj, part, id, skipVerify)
		cleanupLock()
		local lockPos
		lockConn = RunService.Heartbeat:Connect(function()
			if not (ST.Running or ST.Ext) then
				cleanupLock()
				return
			end
			local hrp = getHRP()
			if hrp and lockPos then
				hrp.CFrame = CFrame.new(lockPos)
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end)

		local before = carriedCount()
		local beforeSet = snapshotCarried()
		local result = false
		local invalid = false
		local t0, tries, lastGlobal = os.clock(), 0, 0
		while stAlive(id) and os.clock() - t0 < 10 do
			if isStolen(obj, before) then
				result = true
				break
			end
			if not skipVerify and not verifyTarget(obj) then
				invalid = true
				break
			end
			local allowGlobal = os.clock() - lastGlobal > 1.5
			if allowGlobal then
				lastGlobal = os.clock()
			end
			local prompt = findPrompt(obj, part, allowGlobal)
			if prompt then
				local pp = promptPos(prompt, part)
				lockPos = pp and groundClamp(pp) or lockPos
				tries += 1
				stStatus(("Stealing %s (try %d)"):format(obj.Name, tries))
				if tries == 1 then
					sleep(0.05, id)
				end
				if not stAlive(id) then
					break
				end
				firePrompt(prompt, tries)
			else
				lockPos = (part and part.Parent and groundClamp(part.Position)) or lockPos
				stStatus("Steal prompt not found for " .. obj.Name)
			end
			if not sleep(0.15, id) then
				break
			end
		end
		if not result and stAlive(id) then
			result = isStolen(obj, before)
		end
		cleanupLock()
		local mine
		if result then
			mine = findMine(obj, beforeSet)
			-- the carried copy can show up a moment after the pickup disappears: wait for it instead of giving up
			local tm = os.clock()
			while not mine and stAlive(id) and os.clock() - tm < 1.5 do
				RunService.Heartbeat:Wait()
				mine = findMine(obj, beforeSet)
			end
		end
		return result, mine, invalid
	end

	local function claimWork(id)
		ST.Working = true
		TMX.Exit()
		local t0 = os.clock()
		while stAlive(id) and ((SW.Running and not SW.Yielded) or TT.Working or GM.Working) and os.clock() - t0 < 1.5 do
			RunService.Heartbeat:Wait()
		end
	end

	local guardCache, guardAt = nil, 0
	local function nearestGuard()
		local hrp = getHRP()
		if not hrp then
			return nil
		end
		if not (guardCache and os.clock() - guardAt < 10) then
			guardCache, guardAt = {}, os.clock()
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d.Name == "GuardOverhead" then
					local p = d
					while p and not p:IsA("BasePart") do
						p = p.Parent
					end
					if p then
						table.insert(guardCache, p)
					end
				end
			end
		end
		local best, bd
		for _, p in ipairs(guardCache) do
			if p.Parent then
				local dist = (p.Position - hrp.Position).Magnitude
				if not bd or dist < bd then
					best, bd = p, dist
				end
			end
		end
		return best
	end

	local flingRemote
	local flingAt = -100
	task.spawn(function()
		local r = ReplicatedStorage:FindFirstChild("CatchFlingRemote") or ReplicatedStorage:WaitForChild("CatchFlingRemote", 60)
		if r and r:IsA("RemoteEvent") then
			flingRemote = r
			track(r.OnClientEvent:Connect(function(kind)
				if kind == "fling" then
					flingAt = os.clock()
				end
			end))
		end
	end)

	-- true when the guard really hit us after `mark` (a flingAt value taken before walking to the guard).
	-- Uses the game's own fling event; without it, falls back to standing next to a guard.
	local function guardHitSince(mark)
		if flingRemote then
			local t = os.clock()
			while flingAt <= mark and os.clock() - t < 0.6 do
				RunService.Heartbeat:Wait()
			end
			return flingAt > mark
		end
		local g, h = nearestGuard(), getHRP()
		return g ~= nil and h ~= nil and (g.Position - h.Position).Magnitude <= 20
	end

	-- Teleport mode, outbound leg. From 2+ zones away from the target we break an egg of the zone we stand in
	-- (Safe Zone -> zone 1), pick the hatched animal up and let that zone's guard hit us, which arms the teleport.
	ST.PrimeSpeed = 100

	function ST.PrimeZone(pos)
		local z = zoneIdx(pos)
		if z >= 1 then
			return z
		end
		local d1 = Vector3.new(pos.X - SAFE.X, 0, pos.Z - SAFE.Z).Magnitude
		if d1 <= 80 then
			return 1
		end
		return nil
	end

	local function primeFolder(n)
		local build = Workspace:FindFirstChild("Build")
		local zb = build and build:FindFirstChild("ZoneBuilds")
		return zb and zb:FindFirstChild("Zone" .. n)
	end

	function ST.FindPrimeEgg(zone)
		local hrp = getHRP()
		if not hrp then
			return nil
		end
		local function nearestIn(n)
			local zf = primeFolder(n)
			local eggs = zf and zf:FindFirstChild("Eggs")
			if not eggs then
				return nil
			end
			-- smallest egg wins (same eggSize the stats use); equal size -> the nearer one
			local best, bs, bd
			for _, m in ipairs(eggs:GetChildren()) do
				local part = m:FindFirstChild("Egg")
				if part and part:IsA("BasePart") and eggAlive(part) then
					local sz = eggSize(m, part)
					local d = (part.Position - hrp.Position).Magnitude
					if not bs or sz < bs or (sz == bs and d < bd) then
						best, bs, bd = { part = part, model = m, zone = n }, sz, d
					end
				end
			end
			return best, bd
		end
		return (nearestIn(zone))
	end

	-- GuardOverhead -> the BasePart of that guard
	function ST.GuardPart(d)
		local pt = d
		while pt and not pt:IsA("BasePart") do
			pt = pt.Parent
		end
		if not pt then
			local mdl = d:FindFirstAncestorWhichIsA("Model")
			pt = mdl and getPart(mdl)
		end
		return pt
	end

	-- The guard of zone `n` that is closest to `from`. It only looks at guards that belong to that zone
	-- (inside Workspace.Build.ZoneBuilds.ZoneN, or standing inside the zone's X range) and never falls back to a guard
	-- of another zone, so it can no longer run off to some far away guard. Returns nil when the zone has no guard.
	local zoneGuardCache = {}
	function ST.ZoneGuard(n, from)
		local cache = zoneGuardCache[n]
		if not cache or os.clock() - cache.at > 10 or #cache.list == 0 then
			cache = { at = os.clock(), list = {} }
			zoneGuardCache[n] = cache
			local seen = {}
			local function add(pt)
				if pt and not seen[pt] then
					seen[pt] = true
					cache.list[#cache.list + 1] = pt
				end
			end
			local zf = primeFolder(n)
			if zf then
				for _, d in ipairs(zf:GetDescendants()) do
					if d.Name == "GuardOverhead" then
						add(ST.GuardPart(d))
					end
				end
			end
			if #cache.list == 0 and ZONE_X[n] then
				local lo, hi = ZONE_X[n][1] - 20, ZONE_X[n][2] + 20
				for _, d in ipairs(Workspace:GetDescendants()) do
					if d.Name == "GuardOverhead" then
						local pt = ST.GuardPart(d)
						if pt and pt.Position.X >= lo and pt.Position.X <= hi then
							add(pt)
						end
					end
				end
			end
		end
		if not from then
			local h = getHRP()
			from = h and h.Position
		end
		local best, bd
		for _, pt in ipairs(cache.list) do
			if pt.Parent then
				local d = from and (pt.Position - from).Magnitude or 0
				if not bd or d < bd then
					best, bd = pt, d
				end
			end
		end
		return best
	end

	function ST.EggPrime(id, zone)
		local egg = ST.FindPrimeEgg(zone)
		if not egg then
			stStatus("Teleport: no egg in this zone -> normal route")
			return false
		end
		local part, model = egg.part, egg.model
		local epos = part.Position
		local swingOwned = not SW.Running
		local function cleanup()
			if swingOwned then
				pcall(setGameSwing, false)
				pcall(setSwingEventState, false)
			end
		end
		local function toEgg()
			return moveTo(function()
				return part.Parent and part.Position or nil
			end, id, SW_STOP, function()
				return not eggAlive(part)
			end, true, 0.2, ST.PrimeSpeed)
		end

		local pickBefore = {}
		local pf0 = Workspace:FindFirstChild("AnimalPickups")
		if pf0 then
			for _, c in ipairs(pf0:GetChildren()) do
				pickBefore[c] = true
			end
		end
		local eggInfo = {
			part = part,
			model = model,
			name = model.Name,
			size = eggSize(model, part),
			rarityName = eggRarity(model),
		}
		Stats.SnapEgg(eggInfo)

		stStatus("Teleport: walking to an egg")
		equipPickaxe()
		toEgg()
		if not stAlive(id) then
			cleanup()
			return false
		end

		stStatus("Teleport: breaking the egg")
		equipPickaxe()
		enableGameSwing()
		local t0, lastKeep = os.clock(), os.clock()
		while stAlive(id) and eggAlive(part) and os.clock() - t0 < 40 do
			if os.clock() - lastKeep > 1 then
				lastKeep = os.clock()
				equipPickaxe()
				local btn = findSwingBtn()
				if btn and readSwingState(btn) == false then
					pressBtn(btn)
				end
				local r = getHRP()
				if r and Vector3.new(part.Position.X - r.Position.X, 0, part.Position.Z - r.Position.Z).Magnitude > SW_STOP * 2 then
					toEgg()
				end
			end
			RunService.Heartbeat:Wait()
		end
		if not stAlive(id) then
			cleanup()
			return false
		end
		if eggAlive(part) then
			cleanup()
			stStatus("Teleport: egg not broken -> normal route")
			return false
		end
		if not Stats.Seen[part] then
			Stats.Seen[part] = true
			Stats.AddEgg(Stats.SnapEgg(eggInfo))
		end

		stStatus("Teleport: picking up the animal")
		local obj, apart
		local t1 = os.clock()
		repeat
			local pf = Workspace:FindFirstChild("AnimalPickups")
			if pf then
				local bd
				for _, c in ipairs(pf:GetChildren()) do
					if not pickBefore[c] then
						local pt = getPart(c)
						if pt then
							local d = Vector3.new(pt.Position.X - epos.X, 0, pt.Position.Z - epos.Z).Magnitude
							if d <= 80 and (not bd or d < bd) then
								obj, apart, bd = c, pt, d
							end
						end
					end
				end
			end
			if not obj then
				RunService.Heartbeat:Wait()
			end
		until obj or os.clock() - t1 > 8 or not stAlive(id)
		if not (obj and apart) then
			cleanup()
			if stAlive(id) then
				stStatus("Teleport: no animal from the egg -> normal route")
			end
			return false
		end
		-- the animal that just came out of the egg: walk to it for real (Humanoid:MoveTo), no TP walk
		realWalk(function()
			return apart.Parent and apart.Position or nil
		end, 3, function()
			return stAlive(id) and apart.Parent ~= nil
		end)
		local okc, mine = false, nil
		if stAlive(id) and apart.Parent then
			okc, mine = collect(obj, apart, id, true)
		end
		cleanup()
		if not stAlive(id) or not okc then
			return false
		end

		local function holding()
			local cf = Workspace:FindFirstChild("CarriedAnimals")
			if not cf then
				return false
			end
			if mine then
				return mine.Parent ~= nil and mine:IsDescendantOf(cf)
			end
			return carriedCount() > 0
		end
		local hitMark = flingAt
		for _ = 1, 3 do
			if not stAlive(id) or not holding() then
				break
			end
			local hp1 = getHRP()
			local g = ST.ZoneGuard(egg.zone, hp1 and hp1.Position)
			if not g then
				warn("[LUNAR Hub] Teleport: no guard found in zone " .. tostring(egg.zone) .. " -> normal route")
				break
			end
			if g then
				warn(("[LUNAR Hub] Teleport: using the zone %d guard, %d studs away"):format(egg.zone, math.floor(hp1 and (g.Position - hp1.Position).Magnitude or 0)))
				stStatus("Teleport: walking to the guard")
				moveTo(function()
					return g.Parent and g.Position or nil
				end, id, 8, function()
					return not holding()
				end, true, 0.05, ST.PrimeSpeed)
			end
			local t2 = os.clock()
			while stAlive(id) and os.clock() - t2 < 3 and holding() do
				RunService.Heartbeat:Wait()
			end
		end
		if not stAlive(id) then
			return false
		end
		if holding() then
			return false
		end
		if not guardHitSince(hitMark) then
			stStatus("Teleport: the guard did not hit us -> normal route")
			return false
		end
		stStatus("Teleport: guard hit -> teleporting to the target")
		return true
	end

	local function flatDist(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	local function tpReach(target, id, stopDist)
		local reachDist = stopDist + 9
		for attempt = 1, 3 do
			if not stAlive(id) then
				return false
			end
			local pos = target()
			local hrp = getHRP()
			if not pos or not hrp then
				return false
			end
			if flatDist(hrp.Position, pos) <= reachDist then
				return true
			end
			if attempt > 1 then
				stStatus("Teleport: retrying to reach the target")
			end
			ST.TpArmed = true
			moveTo(target, id, stopDist)
			RunService.Heartbeat:Wait()
			hrp = getHRP()
			pos = target()
			if hrp and pos and flatDist(hrp.Position, pos) <= reachDist then
				return true
			end
			sleep(0.15, id)
		end
		if not stAlive(id) then
			return false
		end
		stStatus("Teleport failed -> walking")
		ST.TpArmed = false
		return moveTo(target, id, stopDist, nil, true)
	end

	-- Teleport move mode for other features. Returns true when we ended up at the target.
	-- Same recipe as Auto Steal: from 2+ zones away break an egg here, get hit by the guard, then teleport.
	-- o = { part, stop, alive, say }
	function TPX.reach(o)
		if ST.Ext or (ST.Running and (ST.Busy or ST.Working)) then
			return false
		end
		local hrp = getHRP()
		local part = o.part
		local function tpos()
			if o.pos then
				return o.pos
			end
			return part and part.Parent and part.Position or nil
		end
		local p0 = tpos()
		if not (hrp and p0 and o.alive()) then
			return false
		end
		local zone = ST.PrimeZone(hrp.Position)
		if not (zone and zoneGap(hrp.Position, p0) >= 2) then
			return false
		end
		local id = {}
		ST.Ext = { id = id, alive = o.alive, say = o.say or function() end }
		local reached = false
		pcall(function()
			local primed = ST.EggPrime(id, zone)
			if not (primed and o.alive() and tpos()) then
				return
			end
			local stop = math.max(o.stop or 4, 2)
			local from = getHRP() and getHRP().Position or p0
			local dir = Vector3.new(from.X - p0.X, 0, from.Z - p0.Z)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
			local function target()
				local tp = tpos()
				if not tp then
					return nil
				end
				return tp + dir * math.max(stop - 1, 1)
			end
			ST.TpArmed = true
			reached = tpReach(target, id, stop)
		end)
		ST.TpArmed = false
		ST.Ext = nil
		return reached
	end

	-- ===== Auto Carry Escape =====
	-- Separate system (Extras tab) with its own switch, Rarity and Min Income. It is the Auto Steal loop with its own
	-- filter that finds its targets itself, but the animal is delivered to the escape spot (ST.CE.Pos, outside the map)
	-- instead of the Safe Zone. Noclip every frame while ON, collisions are restored when it is turned OFF.
	-- It uses the same loop as Auto Steal, so the two can not run at the same time (turning one ON turns the other OFF).
	function ST.CE.Dest()
		return ST.CE.Mode and ST.CE.Pos or SAFE
	end

	track(RunService.Stepped:Connect(function()
		if not ST.CE.Running then
			return
		end
		local c = LocalPlayer.Character
		if not c then
			return
		end
		-- noclip inside all of zone 1 and inside the radius (120 studs) around the escape spot; everywhere else collisions are normal
		local root = c:FindFirstChild("HumanoidRootPart")
		if not root or ((root.Position - ST.CE.Pos).Magnitude > 120 and not (inAnyZone(root.Position) and zoneIdx(root.Position) == 1)) then
			ST.CE.Restore()
			return
		end
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then
				if ST.CE.Orig[d] == nil then
					ST.CE.Orig[d] = d.CanCollide
				end
				if d.CanCollide then
					d.CanCollide = false
				end
			end
		end
	end))

	function ST.CE.Restore()
		for part, was in pairs(ST.CE.Orig) do
			if part.Parent then
				part.CanCollide = was
			end
		end
		ST.CE.Orig = setmetatable({}, { __mode = "k" })
	end

	addCleanup(function()
		ST.CE.Running = false
		ST.CE.Mode = false
		ST.CE.Restore()
	end)

	-- Zone 1 rule of Auto Carry Escape: inside zone 1 (not standing at the escape spot itself) there is no guard hit and
	-- nothing is picked up automatically. An animal you pick up yourself is simply walked to the escape spot.
	function ST.CE.InZone1(pos)
		if not pos then
			return false
		end
		if zoneIdx(pos) ~= 1 or not inAnyZone(pos) then
			return false
		end
		return Vector3.new(pos.X - ST.CE.Pos.X, 0, pos.Z - ST.CE.Pos.Z).Magnitude > 15
	end

	-- an animal of ours is in our hands: a carried animal part right next to the character
	function ST.CE.Holding()
		local f = Workspace:FindFirstChild("CarriedAnimals")
		local hrp = getHRP()
		if not f or not hrp then
			return false
		end
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") and (d.Position - hrp.Position).Magnitude <= 40 then
				return true
			end
		end
		return false
	end

	-- An animal of ours is on us right now (tight radius, so another player's carried animal nearby does not count).
	function ST.CE.Carrying()
		local f = Workspace:FindFirstChild("CarriedAnimals")
		local hrp = getHRP()
		if not f or not hrp then
			return false
		end
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") and (d.Position - hrp.Position).Magnitude <= 15 then
				return true
			end
		end
		return false
	end

	-- ST.CE.Busy: while Auto Carry Escape is ON and we are carrying an animal, every other function waits (Auto Break,
	-- gems, Titanic, treadmill, Auto Place Eggs ...) until the animal is released.
	do
		local nextCheck = 0
		track(RunService.Heartbeat:Connect(function()
			if os.clock() < nextCheck then
				return
			end
			nextCheck = os.clock() + 0.2
			if ST.CE.Mode and ST.CE.Running then
				ST.CE.Busy = ST.CE.Carrying()
			else
				ST.CE.Busy = false
			end
		end))
	end

	-- Auto Carry Escape: straight teleport (no TP Walk) to the escape spot, exact position incl. height. Repeats until we
	-- are there, the animal is gone from our hands, or the loop stops.
	function ST.CE.Warp(id, holdFn)
		holdFn = holdFn or ST.CE.Holding
		local function there()
			local h = getHRP()
			return h ~= nil and (h.Position - ST.CE.Pos).Magnitude <= 6
		end
		local h0 = getHRP()
		if h0 and (h0.Position - ST.CE.Pos).Magnitude > 200 then
			ST.PrepareLanding(ST.CE.Pos)
		end
		while stAlive(id) and not EventGate.Abort and holdFn() and not there() do
			local t = os.clock()
			while stAlive(id) and os.clock() - t < 1.5 do
				local h = getHRP()
				if h then
					h.CFrame = CFrame.new(ST.CE.Pos)
					h.AssemblyLinearVelocity = Vector3.zero
				end
				RunService.Heartbeat:Wait()
				if there() and os.clock() - t > 0.25 then
					break
				end
			end
		end
		ST.HoldLanding(ST.CE.Pos, id)
	end

	local function returnToSpot(id, pos, armed)
		if not stAlive(id) or not pos then
			return
		end
		local hrp = getHRP()
		if not hrp then
			return
		end
		local function target()
			return pos
		end
		if armed and zoneGap(hrp.Position, pos) >= 2 then
			stStatus("Teleport -> back to the original spot")
			tpReach(target, id, 2.5)
		else
			stStatus("Walking back to the original spot")
			ST.TpArmed = false
			moveTo(target, id, 2.5, nil, true)
		end
		ST.TpArmed = false
	end

	local function runAuto(id)
		local skip = {}
		local needSafe = true
		local startFromSafe = true
		local tpHitDone = false
		local stealPos = nil
		local function hasTarget()
			local l = getTargets(skip)
			return #l > 0
		end

		while stAlive(id) do
			if evBlock() then

				if ST.Working or ST.Busy then
					ST.Working = false
					setBusy(false)
				end
				startFromSafe = false
				needSafe = false
				stStatus(EventGate.Active and "Paused - Hell Event has priority" or "Paused - still in Hell arena")
				sleep(0.4, id)
				continue
			end
			local hrp = getHRP()
			if not hrp then
				sleep(0.5, id)
				continue
			end

			if not Workspace:FindFirstChild("AnimalPickups") then
				stStatus("Waiting for AnimalPickups folder...")
				sleep(1, id)
				continue
			end

			-- Auto Carry Escape: at the escape spot with the animal still in our hands -> stand still, no new round
			-- (the player moves freely). The loop works again as soon as nothing is carried any more.
			if ST.CE.Mode then
				local flatEsc = Vector3.new(hrp.Position.X - ST.CE.Pos.X, 0, hrp.Position.Z - ST.CE.Pos.Z).Magnitude
				if flatEsc <= 15 and ST.CE.Holding() then
					if ST.Working or ST.Busy then
						ST.Working = false
						setBusy(false)
					end
					stStatus("At the escape spot with the animal -> standing still, move yourself")
					sleep(0.4, id)
					continue
				end
			end

			-- Auto Carry Escape in zone 1: no guard, no automatic pick-up; an animal you pick up yourself is walked out
			if ST.CE.Mode and ST.CE.InZone1(hrp.Position) then
				if not ST.CE.Holding() then
					ST.CE.Tried = false
					if ST.Working or ST.Busy then
						ST.Working = false
						setBusy(false)
					end
					stStatus("Zone 1: pick up an animal yourself (nothing is picked up automatically)")
				elseif not ST.CE.Tried then
					ST.CE.Tried = true -- one try per animal
					claimWork(id)
					setBusy(true)
					stStatus("Zone 1 -> teleporting to the escape spot")
					ST.CE.Warp(id)
					setBusy(false)
					ST.Working = false
				else
					stStatus("Zone 1: already tried this animal - move yourself")
				end
				sleep(0.4, id)
				continue
			end

			-- Auto Carry Escape: while an animal is in our hands (anywhere) no new round, no warp back; everything else waits too
			if ST.CE.Mode and ST.CE.Carrying() then
				if ST.Working or ST.Busy then
					ST.Working = false
					setBusy(false)
				end
				stStatus("Carrying an animal -> all other functions wait until it is released")
				sleep(0.4, id)
				continue
			end

			local list, skipped = getTargets(skip)
			local e = list[1]

			if not e then

				ST.Working = false
				startFromSafe = true
				setBusy(false)
				if skipped > 0 then
					stStatus("Waiting for next round (some skipped)")
					sleep(0.6, id)
				elseif ST.SafeWait and needSafe then
					local flat = Vector3.new(hrp.Position.X - SAFE.X, 0, hrp.Position.Z - SAFE.Z).Magnitude
					if flat > 4 and not inAnyZone(hrp.Position) then
						claimWork(id)
						stStatus("No target -> going to Safe Zone")
						setBusy(true)
						moveTo(SAFE, id, 2.5, hasTarget)
						setBusy(false)
						ST.Working = false
					end
					needSafe = false
				else
					stStatus(ST.Unread > 0 and ("Cannot read income of " .. ST.Unread .. " animal(s) yet") or (ST.Why ~= "" and ST.Why or "Waiting for animals"))
					sleep(0.6, id)
				end
				continue
			end

			if not ST.Working then
				claimWork(id)
				if not stAlive(id) then
					break
				end
			end
			ST.TpArmed = false
			stealPos = nil
			local animalZone = zoneOfX(e.part.Position.X)
			needSafe = true
			setBusy(true)

			if startFromSafe then
				startFromSafe = false
				local flat = Vector3.new(hrp.Position.X - SAFE.X, 0, hrp.Position.Z - SAFE.Z).Magnitude
				if flat > 6 and not inAnyZone(hrp.Position) then
					stStatus("Going to Safe Zone first")
					moveTo(SAFE, id, 2.5)
					continue
				end
			end

			if ST.TpMode and not tpHitDone then
				local hp0 = getHRP()
				local pz = hp0 and ST.PrimeZone(hp0.Position)
				if pz and zoneGap(hp0.Position, e.part.Position) >= 2 then
					local primed = ST.EggPrime(id, pz)
					if not stAlive(id) then
						break
					end
					ST.TpArmed = primed == true
					if not e.part.Parent then
						ST.TpArmed = false
						continue
					end
				end
			end

			stStatus(("Going to %s [%s] zone %d"):format(e.obj.Name, e.rarity, e.zone))
			local function toAnimal()
				return e.part.Parent and e.part.Position or nil
			end
			if ST.TpMode and ST.TpArmed then
				tpReach(toAnimal, id, 3)
				ST.TpArmed = false
			else
				moveTo(toAnimal, id, 3)
			end
			if not stAlive(id) then
				break
			end

			local eMuts = mutationsOf(e.obj)
			local eInfo = nil
			if Stats.On then
				local obj = e.obj
				local nm = obj:GetAttribute("AnimalName") or obj:GetAttribute("DisplayName") or obj.Name
				eInfo = {
					Name = tostring(nm),
					Rarity = e.rarity,
					Income = incomeOf(obj),
					Model = Stats.ViewClone(obj),
				}
			end
			local ok, mine, invalid = false, nil, false
			local pickBefore = {}
			do
				local pf = Workspace:FindFirstChild("AnimalPickups")
				if pf then
					for _, c in ipairs(pf:GetChildren()) do
						pickBefore[c] = true
					end
				end
			end
			local carriedBase = carriedCount()
			for attempt = 1, 3 do
				if not stAlive(id) or not e.part.Parent or EventGate.Abort then
					break
				end
				if attempt > 1 then
					stStatus(("Retry %d: %s"):format(attempt, e.obj.Name))
					moveTo(function()
						return e.part.Parent and e.part.Position or nil
					end, id, 3)
				end
				ok, mine, invalid = collect(e.obj, e.part, id)
				if ok or invalid then
					break
				end
			end
			if not stAlive(id) then
				break
			end

			if ok then
				ST.Collected += 1
				EQ.Kick()
				local hs = getHRP()
				stealPos = hs and hs.Position or nil
				local hpz = getHRP()
				-- Auto Carry Escape + stolen inside zone 1: walk straight to the escape spot, no guard hit, no recovery
				local zone1Out = ST.CE.Mode and ST.CE.InZone1(hpz and hpz.Position)
				local deliverTp = ST.TpMode and not zone1Out -- return leg always uses TP mode (guard hit -> teleport), except zone 1 of Carry Escape
				local histEntry = Stats.AddSteal(eMuts, eInfo or {})
				stStatus("Stolen! Heading back to Safe Zone")
				local DROP_NEAR_SAFE = 30
				local DROP_SEARCH_RADIUS = 80
				local GUARD_HIT_RADIUS = 20
				local curObj, curPart = e.obj, e.part
				local recoveries, guardTries, gone, finished = 0, 0, false, false

				local function holding()
					if not mine then
						return carriedCount() > carriedBase
					end
					local cf = Workspace:FindFirstChild("CarriedAnimals")
					return cf ~= nil and mine.Parent ~= nil and mine:IsDescendantOf(cf)
				end
				local function lost()
					if holding() then
						return false
					end
					local h = getHRP()
					if h and Vector3.new(h.Position.X - ST.CE.Dest().X, 0, h.Position.Z - ST.CE.Dest().Z).Magnitude <= DROP_NEAR_SAFE then
						return false
					end
					return true
				end
				local function byGuard()
					if flingRemote then
						local t = os.clock()
						while os.clock() - t < 0.3 and os.clock() - flingAt > 1.5 do
							RunService.Heartbeat:Wait()
						end
						return os.clock() - flingAt <= 1.5
					end
					local g = nearestGuard()
					local h = getHRP()
					return g ~= nil and h ~= nil and (g.Position - h.Position).Magnitude <= GUARD_HIT_RADIUS
				end
				local function findDropped()
					local pf = Workspace:FindFirstChild("AnimalPickups")
					if not pf then
						return nil
					end
					if curObj.Parent == pf then
						local p = getPart(curObj)
						if p then
							return curObj, p
						end
					end
					local h = getHRP()
					local best, bp, bd
					for _, c in ipairs(pf:GetChildren()) do
						if not pickBefore[c] and c.Name == curObj.Name then
							local p = getPart(c)
							if p then
								local d = h and (p.Position - h.Position).Magnitude or 0
								if d <= DROP_SEARCH_RADIUS and (not bd or d < bd) then
									best, bp, bd = c, p, d
								end
							end
						end
					end
					return best, bp
				end
				local function awaitDropped(sec)
					local t1 = os.clock()
					repeat
						local o, p = findDropped()
						if o and p then
							return o, p
						end
						RunService.Heartbeat:Wait()
					until os.clock() - t1 >= sec or not stAlive(id)
					return nil
				end
				local function recover(hitByGuard)
					local obj, part = awaitDropped(2.5)
					if not (obj and part) then
						return false
					end
					stStatus("Animal dropped -> picking it up again")
					local armed = ST.TpArmed
					ST.TpArmed = ST.TpMode and hitByGuard
					moveTo(function()
						return part.Parent and part.Position or nil
					end, id, 3)
					ST.TpArmed = armed
					if not stAlive(id) or not part.Parent then
						return false
					end
					local ok2, mine2 = collect(obj, part, id, true)
					if ok2 then
						mine, curObj, curPart = mine2, obj, part
						return true
					end
					return false
				end

				while stAlive(id) and not gone and not finished do
					if deliverTp and not tpHitDone and guardTries < 3 and holding() then
						ST.TpArmed = false
						guardTries += 1
						if stAlive(id) and not lost() then
							stStatus("Stolen! (Teleport) going to the guard")
						end
						if stAlive(id) and not lost() then
							local hz = getHRP()
							local curZ = hz and zoneIdx(hz.Position) or 0
							local gz = curZ >= 1 and curZ or animalZone
							local g = ST.ZoneGuard(gz, hz and hz.Position)
							if not g then
								warn("[LUNAR Hub] Teleport: no guard found in zone " .. tostring(gz) .. " -> normal route")
							else
								warn(("[LUNAR Hub] Teleport: using the zone %d guard, %d studs away"):format(gz, math.floor(hz and (g.Position - hz.Position).Magnitude or 0)))
							end
							if g then
								stStatus("Walking to the guard")
								moveTo(function()
									return g.Parent and g.Position or nil
								end, id, 8, lost, true, 0.05, ST.PrimeSpeed)
								local t2 = os.clock()
								while stAlive(id) and os.clock() - t2 < 3 and not lost() do
									RunService.Heartbeat:Wait()
								end
							end
						end
						if stAlive(id) and lost() then
							local gh = byGuard()
							recoveries += 1
							if recoveries > 5 or not recover(gh) then
								gone = true
							else
								tpHitDone = gh
							end
						elseif stAlive(id) then
							guardTries = 3
						end
					elseif deliverTp and tpHitDone then
						ST.TpArmed = true
						-- Carry Escape: teleport to zone 1 first, then walk (noclip) to the escape spot
						stStatus(ST.CE.Mode and "Teleport -> escape spot" or "Teleport -> Safe Zone")
						if ST.CE.Mode then
							ST.TpArmed = false
							ST.CE.Warp(id, holding)
							-- arrived: free the character (controls, speed, jump, collisions)
							setBusy(false)
						else
							moveTo(ST.CE.Dest(), id, 2.5)
						end
						local t3 = os.clock()
						local safeWait = ST.CE.Mode and 0 or 2.5
						while stAlive(id) and os.clock() - t3 < safeWait and holding() do
							RunService.Heartbeat:Wait()
						end
						if not stAlive(id) or holding() then
							finished = true
						elseif awaitDropped(0.6) then
							local gh = byGuard()
							recoveries += 1
							if recoveries > 5 or not recover(gh) then
								gone = true
							else
								tpHitDone = gh
							end
						else
							finished = true
						end
					else
						ST.TpArmed = false
						if ST.CE.Mode then
							ST.CE.Warp(id, holding)
							setBusy(false)
						else
							moveTo(ST.CE.Dest(), id, nil, lost, false, 0.05)
						end
						if not stAlive(id) then
							finished = true
						elseif zone1Out and lost() then
							finished = true -- zone 1: the dropped animal is not picked up again automatically
						elseif lost() then
							local gh = byGuard()
							recoveries += 1
							if recoveries > 5 or not recover(gh) then
								gone = true
							elseif ST.TpMode then
								tpHitDone = gh
							end
						else
							finished = true
						end
					end
				end

				if gone then
					ST.Collected = math.max(0, ST.Collected - 1)
					Stats.UndoSteal(histEntry)
					stStatus("Animal lost -> next target")
					if stAlive(id) and ST.TpMode and stealPos then
						returnToSpot(id, stealPos, tpHitDone)
					end
					stealPos = nil
					tpHitDone = false
					ST.TpArmed = false
					needSafe = false
					startFromSafe = false
				elseif ST.TpMode and stealPos and not ST.CE.Mode then
					if stAlive(id) then
						returnToSpot(id, stealPos, tpHitDone)
					end
					stealPos = nil
					tpHitDone = false
					ST.TpArmed = false
					needSafe = false
					startFromSafe = false
				else
					stealPos = nil
					tpHitDone = false
					ST.TpArmed = false
					needSafe = false
					startFromSafe = false
				end
			else
				skip[e.obj] = os.clock() + 15
				needSafe = false
				stStatus(invalid and "Target no longer matches - skipped" or "Steal failed -> next target")
			end
		end
		setBusy(false)
		ST.Working = false
	end

	local function stStop(msg)
		ST.Running = false
		ST.TpArmed = false
		ST.Working = false
		stJob += 1
		cleanupLock()
		setBusy(false)
		restoreCollide()
		restoreRagdollStates()
		local hrp = getHRP()
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		stStatus(msg or "Stopped")
	end

	local function stStart()
		ST.Running = true
		stJob += 1
		local id = stJob
		task.spawn(function()
			local ok, err = pcall(runAuto, id)
			if not ok then
				warn("[LUNAR Hub] AutoSteal error: " .. tostring(err))
				if stJob == id then
					stStop("Error - see console")
					pcall(function()
						stToggle.Set(false, true)
					end)
				end
			end
		end)
		return true
	end

	Section(Page, "Auto Steal")
	setStStatus = StatusCard(Page, "Idle   |   Stolen: 0")
	_, stToggle = Toggle(Page, "Auto Steal", false, function(on)
		if on then
			if ST.CE.Mode then
				ST.CE.Stop()
				pcall(function()
					ST.CE.Toggle.Set(false, true)
				end)
			end
			if not stStart() then
				stToggle.Set(false, true)
			else
				stStatus("Started")
			end
		else
			stStop()
		end
	end, nil, "Best animal first. Pauses Auto Break while it works")
	local STEAL_DEFAULT = { "Primordial", "Ethereal", "Spectral", "Omega", "Void", "Inferno", "Celestial" }
	ST.Rarity = toSet(STEAL_DEFAULT)
	_, stIncomeInput = TextInputCb(Page, "Min Income / s", "", "e.g. 500K, 1.2M", function(text)
		local v = 0
		if type(text) == "string" and text:match("%S") then
			v = parseAmount(text)
			if v == nil then
				Notify("Invalid number", false)
				v = 0
			end
		end
		ST.MinIncome = v

		if stIncomeInput then stIncomeInput.Set(formatAmount(v), true) end
	end, "Only steal animals earning at least this per second (0 / empty = off)")
	Dropdown(Page, "Animal Rarity", {
		Multi = true,
		Options = STEAL_RARITIES,
		Default = STEAL_DEFAULT,
		Placeholder = "Select rarity",
		Desc = "Tap to choose one or more",
		OnChange = function(chosen)
			ST.Rarity = toSet(chosen)
		end,
	})
	Dropdown(Page, "Animal Mutation", {
		Multi = true,
		Options = MUT_NAMES,
		Default = {},
		Placeholder = "None",
		Desc = "Steal animals with the chosen mutation (rarity must match) even if the income is below Min Income",
		OnChange = function(chosen)
			ST.Mutation = toSet(chosen)
		end,
	})

	-- ===== Auto Carry Escape (Extras tab) =====
	function ST.CE.Stop()
		local was = ST.CE.Mode
		ST.CE.Mode = false
		ST.CE.Running = false
		ST.CE.Busy = false
		ST.CE.Restore()
		if was then
			stStop("Auto Carry Escape stopped")
		end
	end

	function ST.CE.Start()
		if ST.CE.Mode then
			return true
		end
		if ST.Running then
			stStop("Switched to Auto Carry Escape")
			pcall(function()
				stToggle.Set(false, true)
			end)
		end
		ST.CE.Mode = true
		ST.CE.Running = true
		if not stStart() then
			ST.CE.Stop()
			return false
		end
		return true
	end

	Section(Page2, "Auto Carry Escape")
	ST.CE.F = { Rarity = toSet(STEAL_DEFAULT), Mutation = {}, MinIncome = 0 }
	_, ST.CE.Toggle = Toggle(Page2, "Auto Carry Escape", false, function(on)
		if on then
			if not ST.CE.Start() then
				ST.CE.Toggle.Set(false, true)
			end
		else
			ST.CE.Stop()
		end
	end, nil, "Finds animals by itself (its own Rarity / Min Income), steals them and teleports straight to the escape spot outside the map instead of the Safe Zone. Once there you can walk and drop the animal; a dropped animal is not picked up again by itself. Noclip while ON. Turns Auto Steal OFF (they share the same loop)")
	Dropdown(Page2, "Carry Escape Rarity", {
		Multi = true,
		Options = STEAL_RARITIES,
		Default = STEAL_DEFAULT,
		Placeholder = "Select rarity",
		Desc = "Tap to choose one or more",
		OnChange = function(chosen)
			ST.CE.F.Rarity = toSet(chosen)
		end,
	})
	_, ST.CE.IncomeInput = TextInputCb(Page2, "Carry Escape Min Income / s", "", "e.g. 500K, 1.2M", function(text)
		local v = 0
		if type(text) == "string" and text:match("%S") then
			v = parseAmount(text)
			if v == nil then
				Notify("Invalid number", false)
				v = 0
			end
		end
		ST.CE.F.MinIncome = v
		if ST.CE.IncomeInput then ST.CE.IncomeInput.Set(formatAmount(v), true) end
	end, "Only steal animals earning at least this per second (0 / empty = off)")

	-- ===== Auto Sell (Extras tab) =====
	-- Sells the animals in the backpack whose Rarity is chosen and whose income per second (ToolValue / 60) is BELOW the
	-- entered value (equal or higher = kept). Nothing is sold until a Rarity is chosen AND a value is entered.
	ST.Sell = { Running = false, Job = 0, Rarity = {}, Below = nil, Total = 0 }

	local SELL_UNITS = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18, SX = 1e21, SP = 1e24, OC = 1e27, NO = 1e30, DC = 1e33 }
	function ST.Sell.Parse(text)
		if type(text) ~= "string" then
			return nil
		end
		local num, suf = text:gsub(",", ""):match("^%s*([%d%.]+)%s*(%a*)%s*$")
		local n = tonumber(num)
		if not n then
			return nil
		end
		if suf ~= "" then
			local m = SELL_UNITS[suf:upper()]
			if not m then
				return nil
			end
			n = n * m
		end
		return n
	end

	function ST.Sell.Cfg()
		if ST.Sell.cfg == nil then
			local ok, m = pcall(function()
				return require(ReplicatedStorage:WaitForChild("Shared", 10):WaitForChild("BackpackSellConfig", 10))
			end)
			ST.Sell.cfg = (ok and type(m) == "table") and m or false
		end
		return ST.Sell.cfg or nil
	end

	function ST.Sell.Step()
		if next(ST.Sell.Rarity) == nil or not ST.Sell.Below then
			return 0
		end
		local cfg = ST.Sell.Cfg()
		local remote = ReplicatedStorage:FindFirstChild("BackpackSellRemote")
		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		if not (cfg and remote and bp) then
			return 0
		end
		local list = {}
		for _, t in ipairs(game:GetService("CollectionService"):GetTagged("AnimalTool")) do
			if t:IsDescendantOf(bp) then
				local r = t:GetAttribute("Rarity")
				if r and ST.Sell.Rarity[r] then
					local okV, v = pcall(cfg.ToolValue, t)
					local okS, sellable = pcall(cfg.IsSellable, t)
					if okV and type(v) == "number" and v / 60 < ST.Sell.Below and okS and sellable then
						list[#list + 1] = t
					end
				end
			end
		end
		local sold = 0
		for i = 1, #list, 200 do
			if not ST.Sell.Running then
				break
			end
			local batch = {}
			for j = i, math.min(i + 199, #list) do
				batch[#batch + 1] = list[j]
			end
			local ok, err = pcall(remote.InvokeServer, remote, batch)
			if ok then
				sold += #batch
			else
				warn("[LUNAR Hub] Auto Sell error: " .. tostring(err))
			end
			task.wait(0.5)
		end
		return sold
	end

	function ST.Sell.Stop()
		ST.Sell.Running = false
		ST.Sell.Job += 1
	end

	function ST.Sell.Start()
		ST.Sell.Running = true
		ST.Sell.Job += 1
		local id = ST.Sell.Job
		task.spawn(function()
			while ST.Sell.Running and ST.Sell.Job == id do
				local ok, n = pcall(ST.Sell.Step)
				if ok and n and n > 0 then
					ST.Sell.Total += n
				elseif not ok then
					warn("[LUNAR Hub] Auto Sell error: " .. tostring(n))
				end
				local t0 = os.clock()
				while ST.Sell.Running and ST.Sell.Job == id and os.clock() - t0 < 3 do
					task.wait(0.25)
				end
			end
		end)
	end

	Section(Page2, "Auto Sell")
	Toggle(Page2, "Auto Sell", false, function(on)
		if on then
			ST.Sell.Start()
		else
			ST.Sell.Stop()
		end
	end, nil, "Sells the animals in your backpack of the chosen Rarity that produce LESS income per second than the value below (equal or more is kept). Does nothing until a Rarity is chosen and a value is entered")
	Dropdown(Page2, "Sell Rarity", {
		Multi = true,
		Options = STEAL_RARITIES,
		Default = {},
		Placeholder = "None",
		Desc = "Tap to choose one or more. Nothing is sold while none is chosen",
		OnChange = function(chosen)
			ST.Sell.Rarity = toSet(chosen)
		end,
	})
	_, ST.Sell.Input = TextInputCb(Page2, "Sell Only Below (income / s)", "", "e.g. 100B", function(text)
		local v = nil
		if type(text) == "string" and text:match("%S") then
			v = ST.Sell.Parse(text)
			if v == nil then
				Notify("Invalid number", false)
			end
		end
		ST.Sell.Below = v
		if ST.Sell.Input and v then
			ST.Sell.Input.Set(formatAmount(v), true)
		end
	end, "Animals that produce less income per second than this are sold, equal or more are kept (e.g. 100B = 100B/s). Empty = nothing is sold")

	-- Auto Place Eggs: places the eggs you carry (the game keeps them as parent-less inventory items) into your own
	-- garden at random spots. The garden is the Hitbox of the plot whose OwnerUserId is yours, so it follows you when the
	-- plot changes (another Base_N, another server, an upgraded / wider plot). Kept in a do-block to save local slots.
	do
		local PE = { Running = false, Job = 0, Sent = 0, Tried = setmetatable({}, { __mode = "k" }), Twin = setmetatable({}, { __mode = "k" }), Speed = 100, Saved = {} } -- Speed: TP Walk speed to the plot (studs / second), fixed
		local PE_MARGIN = 3 -- studs kept free from the edge of the garden

		local function peAlive(id)
			return PE.Running and PE.Job == id
		end

		local function myPlot()
			local plots = Workspace:FindFirstChild("Plots")
			if not plots then
				return nil
			end
			local uid = LocalPlayer.UserId
			for _, plot in ipairs(plots:GetChildren()) do
				if tonumber(plot:GetAttribute("OwnerUserId")) == uid then
					local hb = plot:FindFirstChild("Hitbox")
					if hb and hb:IsA("BasePart") then
						return plot, hb
					end
				end
			end
			return nil
		end

		-- random point inside the garden, on the floor
		local function randomSpot(plot, hb)
			local cf, size = hb.CFrame, hb.Size
			local hx = math.max(size.X / 2 - PE_MARGIN, 0)
			local hz = math.max(size.Z / 2 - PE_MARGIN, 0)
			local lx = (math.random() * 2 - 1) * hx
			local lz = (math.random() * 2 - 1) * hz
			local top = cf:PointToWorldSpace(Vector3.new(lx, size.Y / 2, lz))
			local y = hb.Position.Y - size.Y / 2 + 0.77 -- fallback height (same as a normal placement)
			pcall(function()
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local skip = { hb }
				if LocalPlayer.Character then
					table.insert(skip, LocalPlayer.Character)
				end
				local animals = plot:FindFirstChild("PlacedAnimals")
				if animals then
					table.insert(skip, animals)
				end
				params.FilterDescendantsInstances = skip
				local hit = Workspace:Raycast(top, Vector3.new(0, -size.Y - 5, 0), params)
				if hit then
					y = hit.Position.Y + 0.19
				end
			end)
			return Vector3.new(top.X, y, top.Z)
		end

		local NOT_EGG = { "RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction", "LuaSourceContainer",
			"GuiBase", "Sound", "Animation", "Attachment", "Decal", "Texture", "ParticleEmitter", "Weld", "Constraint" }

		local function looksLikeEgg(o)
			local ok, name = pcall(function()
				return o.Name
			end)
			if not ok or type(name) ~= "string" or not name:lower():match("egg%s*$") then
				return false
			end
			for _, c in ipairs(NOT_EGG) do
				local isC = false
				pcall(function()
					isC = o:IsA(c)
				end)
				if isC then
					return false
				end
			end
			return true
		end

		-- eggs you carry: egg tools in your hand / backpack first, then parent-less inventory items named "... Egg"
		local function findEggs()
			local out, seen = {}, {}
			local function add(o)
				if o and not seen[o] and looksLikeEgg(o) then
					local rec = PE.Tried[o]
					if rec and rec.n >= 3 and os.clock() - rec.t < 30 then
						return
					end
					if rec and rec.n >= 3 then
						PE.Tried[o] = nil
					end
					seen[o] = true
					out[#out + 1] = o
				end
			end
			if LocalPlayer.Character then
				for _, o in ipairs(LocalPlayer.Character:GetChildren()) do
					if o:IsA("Tool") then
						add(o)
					end
				end
			end
			local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
			if bp then
				for _, o in ipairs(bp:GetChildren()) do
					add(o)
				end
			end
			local tools = #out
			if type(getnilinstances) == "function" then
				local ok, list = pcall(getnilinstances)
				if ok and type(list) == "table" then
					for _, o in ipairs(list) do
						add(o)
					end
				end
			end
			return out, tools
		end

		-- hold the egg tool (the game places the egg you hold); true when it is in the hand
		function PE.holdEgg(tool)
			local char = LocalPlayer.Character
			local hum = getHumanoid()
			if not (char and hum) then
				return false
			end
			if tool.Parent == char then
				return true
			end
			pcall(function()
				hum:EquipTool(tool)
			end)
			local t0 = os.clock()
			while os.clock() - t0 < 1 do
				if tool.Parent == char then
					return true
				end
				RunService.Heartbeat:Wait()
			end
			return tool.Parent == char
		end

		-- the parent-less inventory item with the same name as a held egg tool, if the game made one
		function PE.nilTwin(tool)
			if type(getnilinstances) ~= "function" then
				return nil
			end
			local ok, list = pcall(getnilinstances)
			if ok and type(list) == "table" then
				for _, o in ipairs(list) do
					if o ~= tool and looksLikeEgg(o) and o.Name == tool.Name then
						return o
					end
				end
			end
			return nil
		end

		function PE.usable(o)
			local rec = PE.Tried[o]
			return not (rec and rec.n >= 3 and os.clock() - rec.t < 30)
		end

		-- the egg tool that is already in the hand
		function PE.heldEgg()
			local c = LocalPlayer.Character
			if c then
				for _, o in ipairs(c:GetChildren()) do
					if o:IsA("Tool") and looksLikeEgg(o) and PE.usable(o) then
						return o
					end
				end
			end
			return nil
		end

		-- other systems that have priority (Auto Place Eggs steps aside for them)
		function PE.blocked()
			return ST.Working or ST.CE.Busy or GM.Working or TT.Working or evBlock()
		end

		-- the spot inside the garden that is closest to us, and whether we are already standing in the garden
		function PE.target(hb, hrp)
			local cf, size = hb.CFrame, hb.Size
			local hx = math.max(size.X / 2 - 4, 0)
			local hz = math.max(size.Z / 2 - 4, 0)
			local lp = cf:PointToObjectSpace(hrp.Position)
			local w = cf:PointToWorldSpace(Vector3.new(math.clamp(lp.X, -hx, hx), 0, math.clamp(lp.Z, -hz, hz)))
			local target = Vector3.new(w.X, hb.Position.Y - size.Y / 2 + 3, w.Z)
			local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z).Magnitude
			return target, flat <= 2 and math.abs(target.Y - hrp.Position.Y) <= 8
		end

		-- TP Walk to the plot at a fixed speed (collisions off while walking so walls do not stop us)
				function PE.restore()
			for p, v in pairs(PE.Saved) do
				if p and p.Parent then
					p.CanCollide = v
				end
			end
			table.clear(PE.Saved)
		end

		function PE.walk(id, target)
			local char = LocalPlayer.Character
			local hrp = getHRP()
			if not (char and hrp) then
				return false
			end
			local parts = {}
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then
					parts[#parts + 1] = p
				end
			end
			local t0 = os.clock()
			local timeout = (target - hrp.Position).Magnitude / PE.Speed * 3 + 5
			local arrived = false
			while peAlive(id) do
				hrp = getHRP()
				if not hrp or PE.blocked() or os.clock() - t0 > timeout then
					break
				end
				local off = target - hrp.Position
				if off.Magnitude <= 1.5 then
					arrived = true
					break
				end
				local dt = math.min(RunService.Heartbeat:Wait(), 0.05)
				for _, p in ipairs(parts) do
					if p.Parent then
						if PE.Saved[p] == nil then
							PE.Saved[p] = p.CanCollide
						end
						p.CanCollide = false
					end
				end
				local np = hrp.Position + off.Unit * math.min(PE.Speed * dt, off.Magnitude)
				if Vector3.new(off.X, 0, off.Z).Magnitude > 0.05 then
					hrp.CFrame = CFrame.new(np, np + Vector3.new(off.X, 0, off.Z))
				else
					hrp.CFrame = CFrame.new(np)
				end
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
			PE.restore()
			return arrived
		end

		-- inside the garden: keep TP-walking (fixed speed) between random waypoints while the eggs are fired,
		-- so the eggs end up spread over the whole garden
		function PE.roam(hb)
			local char = LocalPlayer.Character
			local hrp = getHRP()
			if not (char and hrp) then
				return
			end
			local now = os.clock()
			local dt = math.min(now - (PE.LastT or now), 0.05)
			PE.LastT = now
			local cf, size = hb.CFrame, hb.Size
			local standY = hb.Position.Y - size.Y / 2 + 3
			local way = PE.Way
			if way and Vector3.new(way.X - hrp.Position.X, 0, way.Z - hrp.Position.Z).Magnitude <= 1.5 then
				way = nil
			end
			if not way then
				local hx = math.max(size.X / 2 - 4, 0)
				local hz = math.max(size.Z / 2 - 4, 0)
				local w = cf:PointToWorldSpace(Vector3.new((math.random() * 2 - 1) * hx, 0, (math.random() * 2 - 1) * hz))
				way = Vector3.new(w.X, standY, w.Z)
				PE.Way = way
			end
			if PE.PartsChar ~= char or now - (PE.PartsAt or 0) > 0.5 then
				PE.PartsChar, PE.PartsAt, PE.Parts = char, now, {}
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then
						PE.Parts[#PE.Parts + 1] = p
					end
				end
			end
			for _, p in ipairs(PE.Parts) do
				if p.Parent then
					if PE.Saved[p] == nil then
						PE.Saved[p] = p.CanCollide
					end
					p.CanCollide = false
				end
			end
			local off = Vector3.new(way.X - hrp.Position.X, 0, way.Z - hrp.Position.Z)
			if off.Magnitude > 0.05 and dt > 0 then
				local np = hrp.Position + off.Unit * math.min(PE.Speed * dt, off.Magnitude)
				np = Vector3.new(np.X, standY, np.Z)
				hrp.CFrame = CFrame.new(np, np + off)
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end

		-- nothing to place / stepping aside: let Auto Break & co. work again
		function PE.Release()
			PE.restore()
			PE.Way, PE.LastT = nil, nil
			SW.PEBusy = false
			SW.PlacingEgg = false
		end

		-- one frame of work: find an egg -> walk to the plot -> hold it -> fire PlaceEgg. No messages, no waits.
		function PE.Step(id)
			local plot, hb = myPlot()
			local remote = ReplicatedStorage:FindFirstChild("MergeMachineRemote")
			if not hb or not remote or PE.blocked() then
				PE.Release()
				return false
			end
			local egg = PE.heldEgg()
			if not egg then
				egg = findEggs()[1]
				if not egg then
					PE.Release()
					return false
				end
			end
			SW.PEBusy = true
			local hrp = getHRP()
			if not hrp then
				return false
			end
			local target, inside = PE.target(hb, hrp)
			if not inside then
				PE.walk(id, target)
				return true
			end
			local arg = egg
			local rec = PE.Tried[egg] or { n = 0, t = 0, f = 0 }
			if egg:IsA("Tool") then
				SW.PlacingEgg = true
				if egg.Parent ~= LocalPlayer.Character and not PE.holdEgg(egg) then
					rec.n += 1
					rec.t = os.clock()
					PE.Tried[egg] = rec
					return false
				end
				local tw = PE.Twin[egg]
				if not tw or os.clock() - tw.t > 0.5 then
					tw = { v = PE.nilTwin(egg), t = os.clock() }
					PE.Twin[egg] = tw
				end
				arg = tw.v or egg
			end
			PE.roam(hb) -- TP Walk to the next random waypoint in the garden, then shoot
			-- safety: one egg that never goes away after a lot of shots is skipped for a while
			rec.f = (rec.f or 0) + 1
			if rec.f > 300 then
				rec.n, rec.t, rec.f = 3, os.clock(), 0
			end
			PE.Tried[egg] = rec
			local pos = randomSpot(plot, hb)
			local ok, err = pcall(function()
				remote:FireServer("PlaceEgg", arg, pos)
			end)
			if ok then
				PE.Sent += 1
			else
				warn("[LUNAR Hub] Auto Place Eggs error: " .. tostring(err))
			end
			return true
		end

		function PE.Stop()
			PE.Running = false
			PE.Job += 1
			PE.Release()
		end

		function PE.Start()
			PE.Running = true
			PE.Job += 1
			local id = PE.Job
			task.spawn(function()
				while peAlive(id) do
					local ok, did = pcall(PE.Step, id)
					if not ok then
						warn("[LUNAR Hub] Auto Place Eggs error: " .. tostring(did))
						PE.Release()
						task.wait(1)
					elseif did then
						RunService.Heartbeat:Wait() -- working: next shot on the very next frame
					else
						-- nothing to place right now: look again in a moment
						local t0 = os.clock()
						while peAlive(id) and os.clock() - t0 < 0.25 do
							RunService.Heartbeat:Wait()
						end
					end
				end
			end)
		end

		SW.PEStart = PE.Start
		SW.PEStop = PE.Stop
		addCleanup(PE.Stop)
	end

	addCleanup(function()
		ST.Sell.Stop()
		ST.CE.Stop()
	end)

	addCleanup(function()
		swStop()
		stStop()
		ttStop()
		GM.Stop()
		TM.Stop()
		EQ.Stop()
	end)
	end,
}

local ALL_SYSTEMS = { FarmSystem }

local TRANSLATIONS = {
	{ en = "ON", th = "เปิด" },
	{ en = "OFF", th = "ปิด" },
	{ en = "Farm", th = "ฟาร์ม" },
	{ en = "Event", th = "อีเวนต์" },
	{ en = "Auto Treadmill", th = "ลู่วิ่งอัตโนมัติ" },
	{ en = "Auto Extras", th = "ระบบเสริมอัตโนมัติ" },
	{ en = "Auto Equip Best Pets", th = "สวมใส่สัตว์ที่ดีที่สุดอัตโนมัติ" },
	{ en = "Extras", th = "ระบบเสริม" },
	{ en = "Auto Carry Escape", th = "วาปหนีเมื่อถือสัตว์" },
	{ en = "Carry Escape Rarity", th = "ความหายากของวาปหนี" },
	{ en = "Carry Escape Min Income / s", th = "รายได้ขั้นต่ำ / วินาที ของวาปหนี" },
	{ en = "Finds animals by itself (its own Rarity / Min Income), steals them and teleports straight to the escape spot outside the map instead of the Safe Zone. Once there you can walk and drop the animal; a dropped animal is not picked up again by itself. Noclip while ON. Turns Auto Steal OFF (they share the same loop)", th = "หาสัตว์เอง (ใช้ความหายากและรายได้ขั้นต่ำของตัวเอง) ขโมยแล้ววาปไปจุดหนีนอกแมพแทนโซนปลอดภัย เปิด noclip ตลอดที่เปิดอยู่ จะปิด Auto Steal (ใช้ลูปเดียวกัน)" },
	{ en = "Auto Sell", th = "ขายอัตโนมัติ" },
	{ en = "Auto Place Eggs", th = "วางไข่อัตโนมัติ" },
	{ en = "Your plot was not found", th = "ไม่พบพล็อตของคุณ" },
	{ en = "Walks to your plot (TP Walk, speed 100), holds each egg you carry and keeps placing eggs at random spots while it keeps TP-walking around your garden, with no delay and no messages. Pauses while Auto Steal / a Hell Event is working", th = "เดินไปที่พล็อตของคุณ (TP Walk ความเร็ว 100) ถือไข่แล้วยิงวางรัวแบบสุ่มตำแหน่ง พร้อมเดิน TP Walk วนไปทั่วสวนตลอด ไม่มีดีเลย์และไม่มีข้อความแจ้งเตือน หยุดชั่วคราวเมื่อ Auto Steal หรือ Hell Event กำลังทำงาน" },
	{ en = "Sell Rarity", th = "ความหายากที่จะขาย" },
	{ en = "Sell Only Below (income / s)", th = "ขายเฉพาะที่รายได้ต่ำกว่า (/วินาที)" },
	{ en = "Sells the animals in your backpack of the chosen Rarity that produce LESS income per second than the value below (equal or more is kept). Does nothing until a Rarity is chosen and a value is entered", th = "ขายสัตว์ในกระเป๋าที่เป็นความหายากที่เลือกและผลิตรายได้ต่อวินาทีต่ำกว่าค่าด้านล่าง (เท่ากับหรือมากกว่าจะเก็บไว้) ไม่ทำอะไรจนกว่าจะเลือกความหายากและกรอกค่า" },
	{ en = "Animals that produce less income per second than this are sold, equal or more are kept (e.g. 100B = 100B/s). Empty = nothing is sold", th = "สัตว์ที่ผลิตรายได้ต่อวินาทีต่ำกว่าค่านี้จะถูกขาย เท่ากับหรือมากกว่าจะเก็บไว้ (เช่น 100B = 100B ต่อวินาที) ว่าง = ไม่ขายอะไร" },
	{ en = "Tap to choose one or more. Nothing is sold while none is chosen", th = "แตะเพื่อเลือกอย่างน้อยหนึ่งอย่าง ถ้าไม่เลือกจะไม่ขายอะไร" },
	{ en = "Equips your best pets once after every successful steal, after a random 1 - 5 second delay", th = "ใส่สัตว์ที่ดีที่สุดหนึ่งครั้งหลังขโมยสำเร็จทุกครั้ง โดยหน่วงสุ่ม 1 - 5 วินาที" },
	{ en = "Equipped best pets", th = "สวมใส่สัตว์ที่ดีที่สุดแล้ว" },
	{ en = "Pet remote not found", th = "ไม่พบ remote ของสัตว์" },
	{ en = "Equip failed", th = "สวมใส่ไม่สำเร็จ" },
	{ en = "Auto Titanic Egg", th = "ไข่ไททันอัตโนมัติ" },
	{ en = "Auto Collect Gems", th = "เก็บเจมอัตโนมัติ" },
	{ en = "Auto Break", th = "ทุบไข่อัตโนมัติ" },
	{ en = "Auto Steal", th = "ขโมยอัตโนมัติ" },
	{ en = "Shop", th = "ร้านค้า" },
	{ en = "Hell Event", th = "อีเวนต์นรก" },
	{ en = "Auto Hell Event", th = "อีเวนต์นรกอัตโนมัติ" },
	{ en = "TP Speed", th = "ความเร็วเคลื่อนที่" },
	{ en = "AFK Mode", th = "โหมด AFK" },
	{ en = "Anti AFK", th = "กันหลุด" },
	{ en = "Eggs Broken", th = "ทุบไข่แล้ว" },
	{ en = "Animals Stolen", th = "ขโมยสัตว์แล้ว" },
	{ en = "Mutated Stolen", th = "ขโมยกลายพันธุ์แล้ว" },
	{ en = "AFK Config", th = "คอนฟิกสำหรับ AFK" },
	{ en = "Running time", th = "เวลาที่ทำงานมาแล้ว" },
	{ en = "Close AFK", th = "ปิดโหมด AFK" },
	{ en = "Covers the screen with the LUNAR HUB screen and shows how long it has been running. Uses the chosen AFK Config while ON and restores your previous settings when closed", th = "ใช้หน้าจอ LUNAR HUB ปิดทับจอ แสดงเวลาที่ทำงานมาแล้ว ใช้คอนฟิกที่เลือกตอนเปิด และคืนค่าเดิมทั้งหมดเมื่อปิด" },
	{ en = "Config used while AFK Mode is ON (optional)", th = "คอนฟิกที่ใช้ขณะเปิดโหมด AFK (ไม่บังคับ)" },
	{ en = "Move Mode", th = "วิธีเคลื่อนที่" },
	{ en = "Auto Break Move Mode", th = "วิธีเคลื่อนที่ของทุบไข่อัตโนมัติ" },
	{ en = "Titanic Move Mode", th = "วิธีเคลื่อนที่ของไข่ไททัน" },
	{ en = "Tap to choose. TP Walk = walk at the speed above. Teleport = from 2+ zones away it breaks an egg in the zone you stand in, gets hit by the guard, then teleports to the egg (closer than that it walks)", th = "แตะเพื่อเลือก TP Walk = เดินตามความเร็วด้านบน, Teleport = เมื่อห่างเป้าหมาย 2 โซนขึ้นไป จะทุบไข่ในโซนที่ยืนอยู่ ให้การ์ดตี แล้วเทเลพอร์ตไปหาไข่ (ใกล้กว่านั้นจะเดิน)" },
	{ en = "TP Walk", th = "TP Walk (เดินเร็ว)" },
	{ en = "Teleport", th = "Teleport (วาร์ป)" },
	{ en = "Tap to choose. TP Walk = walk at the speed below. Teleport = from 2+ zones away it breaks an egg in the zone you stand in, gets hit by the guard, then teleports to the target (closer than that it walks). After delivering it returns to where it stole", th = "แตะเพื่อเลือก TP Walk = เดินตามความเร็วด้านล่าง, Teleport = ถ้าห่างเป้าหมาย 2 โซนขึ้นไปจะทุบไข่ในโซนที่ยืน ให้การ์ดตี แล้ววาร์ปไปหาเป้าหมาย (ใกล้กว่านั้นจะเดิน) ส่งสัตว์เสร็จจะกลับจุดที่ขโมย" },
	{ en = "Stolen! (Teleport) going to the guard", th = "ขโมยได้แล้ว! (Teleport) กำลังไปหาการ์ด" },
	{ en = "Teleport: no egg in this zone -> normal route", th = "Teleport: ไม่มีไข่ในโซนนี้ -> ใช้เส้นทางปกติ" },
	{ en = "Teleport: walking to an egg", th = "Teleport: กำลังเดินไปหาไข่" },
	{ en = "Teleport: breaking the egg", th = "Teleport: กำลังทุบไข่" },
	{ en = "Teleport: egg not broken -> normal route", th = "Teleport: ทุบไข่ไม่แตก -> ใช้เส้นทางปกติ" },
	{ en = "Teleport: picking up the animal", th = "Teleport: กำลังเก็บสัตว์จากไข่" },
	{ en = "Teleport: no animal from the egg -> normal route", th = "Teleport: ไม่พบสัตว์จากไข่ -> ใช้เส้นทางปกติ" },
	{ en = "Teleport: walking to the guard", th = "Teleport: กำลังไปหาการ์ด" },
	{ en = "Teleport: guard hit -> teleporting to the target", th = "Teleport: การ์ดตีแล้ว -> วาร์ปไปหาเป้าหมาย" },
	{ en = "Walking to the guard", th = "กำลังเคลื่อนที่ไปหาการ์ด" },
	{ en = "Teleport -> Safe Zone", th = "Teleport -> Safe Zone" },
	{ en = "Teleport -> back to the original spot", th = "Teleport -> กลับตำแหน่งเดิม" },
	{ en = "Walking back to the original spot", th = "กำลังเดินกลับตำแหน่งเดิม" },
	{ en = "Teleport: retrying to reach the target", th = "Teleport: ลองวาร์ปไปหาเป้าหมายอีกครั้ง" },
	{ en = "Teleport failed -> walking", th = "Teleport ไม่สำเร็จ -> เปลี่ยนเป็นเดิน" },
	{ en = "Titanic Zone", th = "โซนไข่ไททัน" },
	{ en = "Egg Rarity", th = "ความหายากของไข่" },
	{ en = "Auto Break Egg Order", th = "ลำดับการทุบไข่อัตโนมัติ" },
	{ en = "Largest first", th = "ไข่ที่ใหญ่สุดก่อน" },
	{ en = "Smallest first", th = "ไข่ที่เล็กสุดก่อน" },
	{ en = "Nearest first", th = "ไข่ที่อยู่ใกล้ที่สุดก่อน" },
	{ en = "Animal Mutation", th = "กลายพันธุ์สัตว์" },
	{ en = "Egg Zone", th = "โซนไข่" },
	{ en = "Only break eggs in the chosen zones (none chosen = all zones). If a chosen zone is beyond the Divine zone (7), none of its eggs is in sight and its map is not loaded, Auto Break goes to the Divine zone first", th = "ทุบเฉพาะไข่ในโซนที่เลือก (ไม่เลือก = ทุกโซน) ถ้าโซนที่เลือกอยู่เลยโซน Divine (7) มองไม่เห็นไข่ของโซนนั้นและแมพยังไม่โหลด Auto Break จะไปโซน Divine ก่อน" },
	{ en = "The map of the chosen zone is not loaded -> going to the Divine zone first", th = "แมพของโซนที่เลือกยังไม่โหลด -> ไปโซน Divine ก่อน" },
	{ en = "Animal Rarity", th = "ความหายากของสัตว์" },
	{ en = "Min Income / s", th = "รายได้ขั้นต่ำ / วินาที" },
	{ en = "Safe Zone First", th = "ไปโซนปลอดภัยก่อน" },
	{ en = "Anti Ragdoll", th = "กันล้มกลิ้ง" },
	{ en = "Noclip While Working", th = "ทะลุสิ่งกีดขวางขณะทำงาน" },
	{ en = "Zone", th = "โซน" },
	{ en = "Select rarity", th = "เลือกความหายาก" },
	{ en = "Select zone", th = "เลือกโซน" },
	{ en = "e.g. 500K, 1.2M", th = "เช่น 500K, 1.2M" },
	{ en = "Tap to choose one or more", th = "กดเลือกได้หลายรายการ" },
	{ en = "Walk speed in studs/s (100 - 200)", th = "ความเร็วเดิน หน่วย studs/วินาที (100 - 200)" },
	{ en = "Walk to eggs + keep the game's AutoSwing ON (pauses while Auto Steal works)", th = "เดินไปหาไข่ + เปิด AutoSwing ของเกมไว้ (หยุดชั่วคราวขณะ Auto Steal ทำงาน)" },
	{ en = "Break the Titanic Egg when it spawns. Pauses Auto Break; Auto Steal / Hell Event have priority", th = "ทุบไข่ไททันเมื่อเกิด หยุด Auto Break ชั่วคราว โดย Auto Steal / Hell Event สำคัญกว่า" },
	{ en = "Only break the Titanic Egg in the chosen zones", th = "ทุบไข่ไททันเฉพาะในโซนที่เลือก" },
	{ en = "Lowest priority: walks to your treadmill when nothing else is working, leaves when another function starts", th = "ลำดับต่ำสุด: เดินไปที่ลู่วิ่งเมื่อไม่มีฟังก์ชันอื่นทำงาน และออกเมื่อฟังก์ชันอื่นเริ่ม" },
	{ en = "Best animal first. Pauses Auto Break while it works", th = "ขโมยตัวที่ดีที่สุดก่อน หยุด Auto Break ชั่วคราวขณะทำงาน" },
	{ en = "Steal animals with the chosen mutation (rarity must match) even if the income is below Min Income", th = "ขโมยสัตว์ที่มีกลายพันธุ์ที่เลือก (ความหายากต้องตรง) แม้รายได้ต่ำกว่าขั้นต่ำ" },
	{ en = "Only steal animals earning at least this per second (0 / empty = off)", th = "ขโมยเฉพาะสัตว์ที่ได้รายได้อย่างน้อยเท่านี้ต่อวินาที (0 / ว่าง = ปิด)" },
	{ en = "Return to the Safe Zone after stealing / when no targets", th = "กลับโซนปลอดภัยหลังขโมย / เมื่อไม่มีเป้าหมาย" },
	{ en = "Stops ragdoll / fall-down while Auto Steal is running", th = "กันตัวละครล้มกลิ้งขณะ Auto Steal ทำงาน" },
	{ en = "Walk through walls only while walking / stealing", th = "ทะลุกำแพงเฉพาะตอนเดิน / ขโมย" },
	{ en = "Under maintenance", th = "อยู่ระหว่างปรับปรุง" },
	{ en = "Wait for the door -> pickaxe eggs until points are full -> bat the boss -> repeat every event", th = "รอประตู -> ทุบไข่ด้วยพิคแอกซ์จนแต้มเต็ม -> ตีบอสด้วยไม้ -> ทำซ้ำทุกอีเวนต์" },
	{ en = "Game AutoSwing button not found (walking only)", th = "ไม่พบปุ่ม AutoSwing ของเกม (เดินอย่างเดียว)" },
	{ en = "firesignal not available - cannot press AutoSwing", th = "ไม่รองรับ firesignal - กด AutoSwing ไม่ได้" },
	{ en = "Select a rarity first", th = "เลือกความหายากก่อน" },
	{ en = "Titanic Egg broken", th = "ทุบไข่ไททันแล้ว" },
	{ en = "Invalid number", th = "ตัวเลขไม่ถูกต้อง" },
	{ en = "Hell Event finished", th = "อีเวนต์นรกจบแล้ว" },
	{ en = "Idle", th = "ว่าง" },
	{ en = "Started", th = "เริ่มแล้ว" },
	{ en = "Stopped", th = "หยุดแล้ว" },
	{ en = "Error - see console", th = "เกิดข้อผิดพลาด - ดูที่คอนโซล" },
	{ en = "Pickaxe back in hand -> AutoSwing turned ON again", th = "ถือพิคแอกซ์แล้ว -> เปิด AutoSwing อีกครั้ง" },
	{ en = "AutoSwing was OFF -> turned ON again", th = "AutoSwing ถูกปิด -> เปิดใหม่อีกครั้ง" },
	{ en = "Swing button not showing -> re-equipping pickaxe", th = "ไม่เห็นปุ่มสวิง -> ถือพิคแอกซ์ใหม่" },
	{ en = "Paused - Hell Event has priority", th = "หยุดชั่วคราว - อีเวนต์นรกสำคัญกว่า" },
	{ en = "Paused - Auto Titanic Egg is working (AutoSwing kept ON)", th = "หยุดชั่วคราว - ไข่ไททันอัตโนมัติกำลังทำงาน (AutoSwing ยังเปิดอยู่)" },
	{ en = "Paused - Auto Steal is working (AutoSwing kept ON)", th = "หยุดชั่วคราว - ขโมยอัตโนมัติกำลังทำงาน (AutoSwing ยังเปิดอยู่)" },
	{ en = "Auto Steal finished -> equipping Pickaxe", th = "ขโมยอัตโนมัติเสร็จแล้ว -> กำลังถือพิคแอกซ์" },
	{ en = "Resumed - Pickaxe equipped, AutoSwing enabled", th = "ทำต่อ - ถือพิคแอกซ์แล้ว เปิด AutoSwing แล้ว" },
	{ en = "Cannot resume - Pickaxe not found/equipped", th = "ทำต่อไม่ได้ - ไม่พบ/ไม่ได้ถือพิคแอกซ์" },
	{ en = "No matching egg found, scanning...", th = "ไม่พบไข่ที่ตรงเงื่อนไข กำลังสแกน..." },
	{ en = "Breaking egg", th = "กำลังทุบไข่" },
	{ en = "Select a zone first", th = "เลือกโซนก่อน" },
	{ en = "Paused - Auto Steal is working", th = "หยุดชั่วคราว - ขโมยอัตโนมัติกำลังทำงาน" },
	{ en = "Waiting for Titanic Egg", th = "รอไข่ไททัน" },
	{ en = "Preparing Pickaxe / AutoSwing", th = "เตรียมพิคแอกซ์ / AutoSwing" },
	{ en = "Walking to Titanic Egg", th = "กำลังเดินไปที่ไข่ไททัน" },
	{ en = "Plots not found", th = "ไม่พบแปลง" },
	{ en = "Treadmill is locked", th = "ลู่วิ่งยังล็อกอยู่" },
	{ en = "Treadmill not found in your plot", th = "ไม่พบลู่วิ่งในแปลงของคุณ" },
	{ en = "Your plot was not found", th = "ไม่พบแปลงของคุณ" },
	{ en = "Paused - another function is working", th = "หยุดชั่วคราว - ฟังก์ชันอื่นกำลังทำงาน" },
	{ en = "On treadmill", th = "อยู่บนลู่วิ่ง" },
	{ en = "Walking to treadmill", th = "กำลังเดินไปที่ลู่วิ่ง" },
	{ en = "Paused - still in Hell arena", th = "หยุดชั่วคราว - ยังอยู่ในสนามนรก" },
	{ en = "Waiting for AnimalPickups folder...", th = "รอโฟลเดอร์ AnimalPickups..." },
	{ en = "Waiting for next round (some skipped)", th = "รอรอบถัดไป (ข้ามบางตัว)" },
	{ en = "No target -> going to Safe Zone", th = "ไม่มีเป้าหมาย -> ไปโซนปลอดภัย" },
	{ en = "Waiting for animals", th = "รอสัตว์" },
	{ en = "Going to Safe Zone first", th = "ไปโซนปลอดภัยก่อน" },
	{ en = "Stolen! Heading back to Safe Zone", th = "ขโมยสำเร็จ! กำลังกลับโซนปลอดภัย" },
	{ en = "Steal failed -> next target", th = "ขโมยไม่สำเร็จ -> เป้าหมายถัดไป" },
	{ en = "Target no longer matches - skipped", th = "เป้าหมายไม่ตรงเงื่อนไขแล้ว - ข้าม" },
	{ en = "Animal dropped -> picking it up again", th = "สัตว์หลุด/ร่วง -> กำลังไปเก็บใหม่" },
	{ en = "Animal lost -> next target", th = "สัตว์หายไป -> ไปเป้าหมายถัดไป" },
	{ en = "1/3 Door: waiting for next event", th = "1/3 ประตู: รออีเวนต์ถัดไป" },
	{ en = "1/3 Door: waiting for event", th = "1/3 ประตู: รออีเวนต์" },
	{ en = "1/3 Door: waiting for Auto Steal to finish its target", th = "1/3 ประตู: รอขโมยอัตโนมัติทำเป้าหมายให้เสร็จ" },
	{ en = "1/3 Door: walking to safe zone", th = "1/3 ประตู: กำลังเดินไปโซนปลอดภัย" },
	{ en = "1/3 Door: safe zone already done, going to portal", th = "1/3 ประตู: ผ่านโซนปลอดภัยแล้ว กำลังไปที่พอร์ทัล" },
	{ en = "1/3 Door: already in a zone, skipping safe zone", th = "1/3 ประตู: อยู่ในโซนแล้ว ข้ามโซนปลอดภัย" },
	{ en = "1/3 Door: portal not loaded -> walking to safe zone", th = "1/3 ประตู: พอร์ทัลยังไม่โหลด -> เดินไปโซนปลอดภัย" },
	{ en = "1/3 Door: walking to portal", th = "1/3 ประตู: กำลังเดินไปที่พอร์ทัล" },
	{ en = "1/3 Door: entering portal", th = "1/3 ประตู: กำลังเข้าพอร์ทัล" },
	{ en = "2/3 Eggs: checking pickaxe...", th = "2/3 ไข่: กำลังเช็กพิคแอกซ์..." },
	{ en = "NOT EQUIPPED", th = "ไม่ได้ถือ" },
	{ en = "Stopped: could not enter door", th = "หยุด: เข้าประตูไม่ได้" },
	{ en = "Stopped: egg goal not reached", th = "หยุด: ยังไม่ถึงเป้าหมายไข่" },
	{ en = "Done - event finished", th = "เสร็จแล้ว - อีเวนต์จบ" },
	{ en = "Event finished - waiting to leave arena", th = "อีเวนต์จบ - รอออกจากสนาม" },
	{ en = "History", th = "ประวัติ" },
	{ en = "Stolen Animals", th = "สัตว์ที่ขโมย" },
	{ en = "Broken Eggs", th = "ไข่ที่ทุบ" },
	{ en = "No history yet", th = "ยังไม่มีประวัติ" },
	{ en = "Mutation", th = "กลายพันธุ์" },
	{ en = "Income / s", th = "รายได้ / วินาที" },
	{ en = "Max Health", th = "เลือดสูงสุด" },
	{ en = "Size", th = "ขนาด" },
}

log("step 1: loading library...")
local Lunar = fetchLibrary()
if not Lunar then
	warn("[LUNAR Loader] Could not load LUNAR Library. Set CONFIG.LibraryUrl or put LUNAR_Library.lua in your workspace folder.")
	return
end
log("step 2: library loaded, type = " .. type(Lunar) .. ", Lunar.new = " .. type(type(Lunar) == "table" and Lunar.new or nil))
if type(Lunar) ~= "table" or type(Lunar.new) ~= "function" then
	warn("[LUNAR Loader] Library has no .new function (the library file is probably wrong / outdated / returned an error page)")
	return
end

local systems = {}
for _, system in ipairs(ALL_SYSTEMS) do
	if CONFIG.Systems[system.Id] ~= false then
		-- ครอบ Build ด้วย xpcall เพื่อให้เห็น error ที่ไลบรารีอาจกลืนไว้
		local origBuild = system.Build
		system.Build = function(UI)
			log("step 4: building system '" .. tostring(system.Id) .. "'")
			local ok, err = xpcall(origBuild, debug.traceback, UI)
			if not ok then
				warn("[LUNAR Loader] Build error in system '" .. tostring(system.Id) .. "':\n" .. tostring(err))
				error(err, 0)
			end
			log("step 5: system '" .. tostring(system.Id) .. "' built OK")
		end
		table.insert(systems, system)
	end
end

log("step 3: creating Hub...")
local okHub, Hub = xpcall(Lunar.new, debug.traceback, {
	Id = CONFIG.Id or tostring(game.PlaceId),
	GameName = CONFIG.GameName,
	Translations = TRANSLATIONS,
	ConfigExclude = { "^Farm:AFK", "^Section:Farm:AFK" },
	Systems = systems,
})
if not okHub then
	warn("[LUNAR Loader] Lunar.new error:\n" .. tostring(Hub))
	return
end

if not Hub then
	warn("[LUNAR Loader] Lunar.new returned nil/false -> the library refused to create the UI (no error was thrown). "
		.. "PlaceId = " .. tostring(game.PlaceId) .. ", Id = " .. tostring(CONFIG.Id or game.PlaceId))
	return
end
log("step 6: Hub created")

local Loader = {
	Hub = Hub,
	Config = CONFIG,
	Systems = systems,
	EventGate = EventGate,
	Unload = function()
		pcall(Hub.Destroy)
		ENV.LunarLoader = nil
	end,
}
ENV.LunarLoader = Loader

log(("ready - %d system(s): %s"):format(#systems, table.concat((function()
	local names = {}
	for _, s in ipairs(systems) do
		table.insert(names, s.Name)
	end
	return names
end)(), ", ")))

return Loader
