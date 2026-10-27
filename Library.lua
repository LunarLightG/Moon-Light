local Lunar = { Version = "3.1.0" }

local function Build(Context)
Context = type(Context) == "table" and Context or {}
Context.ConfigExclude = type(Context.ConfigExclude) == "table" and Context.ConfigExclude or {}
Context.Id = type(Context.Id) == "string" and Context.Id ~= "" and Context.Id or tostring(game.PlaceId)
local SAFE_ID = (Context.Id:gsub("[^%w_%-]", "_"))
if SAFE_ID == "" then
	SAFE_ID = tostring(game.PlaceId)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Stats = game:GetService("Stats")

for _, key in ipairs({ "LunarHubCleanup", "DXPanelCleanup" }) do
	if _G[key] then
		pcall(_G[key])
		_G[key] = nil
	end
end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[LUNAR Hub] LocalPlayer not available (must run on client)")
	return
end

local DEFAULT_SETTINGS = {
	Animate = true,
	Pulse = true,
	ShowFloating = true,
	Lang = "th",
	AntiAFK = false,
	Stars = true,
	Rainbow = false,
	RainbowSpeed = 1,
	Multi = false,
	NeonColors = { "8A63D2", "4B3A78", "2B2B33" },
	ThemeColor = "8A63D2",
	Perf = "Balanced",
	FloatMonitor = false,
	MonitorX = -1,
	MonitorY = -1,
	DefaultConfig = "",
	BgOpacity = 60,
	GroupFrame = true,
	GroupNeon = 60,
	GroupFill = 8,
	SectionOrder = {},
	CompactButtons = true,
	SectionGap = 10,
	SectionFade = 50,
}
local SETTINGS_FILE = "LunarHub_Settings_" .. SAFE_ID .. ".json"

local PERF_PRESETS = {
	High = {
		spinTier = 3, glow = 4, pulse = true, blink = true,
		stars = 36, twinkle = 4, twinkleEvery = 0.5,
		meteor = true, meteorMin = 1.2, meteorMax = 3.4, meteorDouble = true,
		nebula = true, rainbowEvery = 0.5,
	},
	Balanced = {
		spinTier = 1, glow = 2, pulse = true, blink = true,
		stars = 14, twinkle = 2, twinkleEvery = 1.4,
		meteor = true, meteorMin = 4, meteorMax = 8, meteorDouble = false,
		nebula = true, rainbowEvery = 1,
	},
	Low = {
		spinTier = 0, glow = 1, pulse = false, blink = false,
		stars = 0, twinkle = 0, twinkleEvery = 2,
		meteor = false, meteorMin = 4, meteorMax = 8, meteorDouble = false,
		nebula = false, rainbowEvery = 1.5,
	},
}

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = type(v) == "table" and copyTable(v) or v
	end
	return c
end

local function HexToColor3(hex)
	if type(hex) ~= "string" then
		return nil
	end
	hex = hex:gsub("[#%s]", "")
	if #hex ~= 6 then
		return nil
	end
	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not (r and g and b) then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

local function Color3ToHex(c)
	return string.format(
		"%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

local Settings = copyTable(DEFAULT_SETTINGS)
local hasFileApi = type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"

local function GetPerf()
	return PERF_PRESETS[Settings.Perf] or PERF_PRESETS.Balanced
end

local function saveSettings()
	if not hasFileApi then
		return
	end
	pcall(function()
		writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings))
	end)
end

do
	if hasFileApi then
		pcall(function()
			if not isfile(SETTINGS_FILE) then
				return
			end
			local data = HttpService:JSONDecode(readfile(SETTINGS_FILE))
			if type(data) ~= "table" then
				return
			end
			for _, key in ipairs({ "Animate", "Pulse", "ShowFloating", "Stars", "Rainbow", "Multi", "FloatMonitor", "AntiAFK" }) do
				if type(data[key]) == "boolean" then
					Settings[key] = data[key]
				end
			end
			if type(data.NeonColors) == "table" then
				local list = {}
				for _, h in ipairs(data.NeonColors) do
					if HexToColor3(h) and #list < 5 then
						table.insert(list, h)
					end
				end
				if #list >= 2 then
					Settings.NeonColors = list
				end
			end
			if type(data.RainbowSpeed) == "number" then
				Settings.RainbowSpeed = math.clamp(data.RainbowSpeed, 0.2, 3)
			end
			for key, range in pairs({ BgOpacity = { 0, 100 } }) do
				if type(data[key]) == "number" then
					Settings[key] = math.clamp(data[key], range[1], range[2])
				end
			end
			if false then
				local clean = {}
				for page, list in pairs(data.SectionOrder) do
					if type(page) == "string" and type(list) == "table" then
						local names = {}
						for _, nm in ipairs(list) do
							if type(nm) == "string" then
								table.insert(names, nm)
							end
						end
						clean[page] = names
					end
				end
				Settings.SectionOrder = clean
			end
			if HexToColor3(data.ThemeColor) then
				Settings.ThemeColor = data.ThemeColor
			end
			if type(data.Perf) == "string" and PERF_PRESETS[data.Perf] then
				Settings.Perf = data.Perf
			end
			if data.Lang == "en" or data.Lang == "th" then
				Settings.Lang = data.Lang
			end
			if type(data.MonitorX) == "number" and type(data.MonitorY) == "number" then
				Settings.MonitorX, Settings.MonitorY = data.MonitorX, data.MonitorY
			end
			if type(data.DefaultConfig) == "string" then
				Settings.DefaultConfig = data.DefaultConfig
			end
		end)
	end
end

local LANG_PAIRS = {
	{ en = "Overview", th = "ภาพรวม" },
	{ en = "Example", th = "ตัวอย่าง" },
	{ en = "Settings", th = "ตั้งค่า" },
	{ en = "Credits", th = "เครดิต" },
	{ en = "PLAYERS", th = "ผู้เล่น" },
	{ en = "PING", th = "PING" },
	{ en = "FPS", th = "FPS" },
	{ en = "Game", th = "เกม" },
	{ en = "Place ID", th = "รหัสสถานที่" },
	{ en = "Server", th = "เซิร์ฟเวอร์" },
	{ en = "Account Age: %d days", th = "อายุบัญชี: %d วัน" },
	{ en = "Buttons", th = "ปุ่ม" },
	{ en = "Sample Button", th = "ปุ่มตัวอย่าง" },
	{ en = "Danger Button", th = "ปุ่มอันตราย" },
	{ en = "Toggles", th = "สวิตช์" },
	{ en = "Sample Toggle", th = "สวิตช์ตัวอย่าง" },
	{ en = "Locked Toggle (Hook not bound)", th = "สวิตช์ที่ล็อก (ยังไม่ผูก Hook)" },
	{ en = "Sliders", th = "สไลเดอร์" },
	{ en = "Sample Slider", th = "สไลเดอร์ตัวอย่าง" },
	{ en = "Decimal Slider", th = "สไลเดอร์ทศนิยม" },
	{ en = "Select Boxes", th = "กล่องเลือก" },
	{ en = "Sample Select", th = "ตัวเลือกตัวอย่าง" },
	{ en = "Sample Multi Select", th = "เลือกหลายรายการตัวอย่าง" },
	{ en = "Locked Select", th = "ตัวเลือกที่ล็อก" },
	{ en = "Image Box", th = "กล่องรูปภาพ" },
	{ en = "Sample Image Box", th = "กล่องรูปภาพตัวอย่าง" },
	{ en = "Sample button pressed", th = "กดปุ่มตัวอย่างแล้ว" },
	{ en = "Red button (for dangerous actions)", th = "ปุ่มสีแดง (ใช้กับงานอันตราย)" },
	{ en = "Sample Toggle: %s", th = "สวิตช์ตัวอย่าง: %s" },
	{ en = "Selected: %s", th = "เลือก: %s" },
	{ en = "%d items selected", th = "เลือกอยู่ %d รายการ" },
	{ en = "This function has no hook bound yet", th = "ฟังก์ชันนี้ยังไม่ได้ผูก Hook" },
	{ en = "This option has no hook bound yet", th = "ตัวเลือกนี้ยังไม่ได้ผูก Hook" },
	{ en = "Not Available", th = "ใช้งานไม่ได้" },
	{ en = "Select...", th = "เลือก..." },
	{ en = "None", th = "ไม่มี" },
	{ en = "%d selected", th = "เลือกแล้ว %d" },
	{ en = "Search...", th = "ค้นหา..." },
	{ en = "No options", th = "ไม่มีตัวเลือก" },
	{ en = "Clear all", th = "ล้างทั้งหมด" },
	{ en = "Done", th = "เสร็จสิ้น" },
	{ en = "Select 1 option", th = "เลือกได้ 1 ตัวเลือก" },
	{ en = "Select 1 item", th = "เลือกได้ 1 รายการ" },
	{ en = "Option A", th = "ตัวเลือก A" },
	{ en = "Option B", th = "ตัวเลือก B" },
	{ en = "Option C", th = "ตัวเลือก C" },
	{ en = "Item 1", th = "รายการ 1" },
	{ en = "Item 2", th = "รายการ 2" },
	{ en = "Item 3", th = "รายการ 3" },
	{ en = "Item 4", th = "รายการ 4" },
	{ en = "Item 5", th = "รายการ 5" },
	{ en = "Moon Blade", th = "ดาบจันทรา" },
	{ en = "Star Bow", th = "ธนูดาว" },
	{ en = "Nebula Staff", th = "คฑาเนบิวลา" },
	{ en = "Comet Shield", th = "โล่ดาวหาง" },
	{ en = "Eclipse Ring", th = "แหวนอุปราคา" },
	{ en = "Orbit Boots", th = "รองเท้าวงโคจร" },
	{ en = "Moonlight blade", th = "ดาบแสงจันทร์" },
	{ en = "Falling star bow", th = "ธนูดาวตก" },
	{ en = "Cosmic cloud staff", th = "คฑากลุ่มเมฆจักรวาล" },
	{ en = "Icy comet shield", th = "โล่ดาวหางน้ำแข็ง" },
	{ en = "Eclipse ring", th = "แหวนสุริยุปราคา" },
	{ en = "Orbiting boots", th = "รองเท้าโคจร" },
	{ en = "Tap to choose, shown as icon + name", th = "กดเลือก แล้วแสดงเป็นไอคอน + ชื่อ" },
	{ en = "Lunar Trio", th = "ลูนาร์ทรีโอ" },
	{ en = "Aurora", th = "แสงเหนือ" },
	{ en = "Sunset", th = "ตะวันตกดิน" },
	{ en = "Cyber", th = "ไซเบอร์" },
	{ en = "Candy", th = "ลูกกวาด" },
	{ en = "Galaxy", th = "กาแล็กซี" },
	{ en = "General", th = "ทั่วไป" },
	{ en = "Language", th = "ภาษา" },
	{ en = "Animation", th = "แอนิเมชัน" },
	{ en = "Premium Effects", th = "เอฟเฟกต์พรีเมียม" },
	{ en = "Show Floating Button", th = "แสดงปุ่มลอย" },
	{ en = "Shooting Stars", th = "ดาวตก" },
	{ en = "Performance", th = "ประสิทธิภาพ" },
	{ en = "High", th = "สูง" },
	{ en = "Balanced", th = "สมดุล" },
	{ en = "Low", th = "ต่ำ" },
	{ en = "Anti AFK", th = "กันหลุดเมื่อ AFK" },
	{ en = "Monitor", th = "มอนิเตอร์" },
	{ en = "FPS / Ping Monitor", th = "มอนิเตอร์ FPS / Ping" },
	{ en = "Reset Monitor Position", th = "รีเซ็ตตำแหน่งมอนิเตอร์" },
	{ en = "Theme Color", th = "สีธีม" },
	{ en = "Rainbow Mode", th = "โหมดสายรุ้ง" },
	{ en = "Rainbow Speed", th = "ความเร็วสายรุ้ง" },
	{ en = "Multi-Color Neon", th = "นีออนหลายสี" },
	{ en = "Neon Combo", th = "ชุดสีนีออน" },
	{ en = "NEON PALETTE", th = "พาเลตต์นีออน" },
	{ en = "PRESETS", th = "สีสำเร็จรูป" },
	{ en = "APPLY", th = "ใช้สี" },
	{ en = "HUE", th = "เฉดสี" },
	{ en = "SATURATION", th = "ความอิ่มตัว" },
	{ en = "BRIGHTNESS", th = "ความสว่าง" },
	{ en = "Adjusting: neon color #%d  (tap again to return to the main color)", th = "กำลังปรับ: สีนีออนที่ %d  (แตะซ้ำเพื่อกลับไปสีหลัก)" },
	{ en = "Adjusting: theme main color  (tap a circle to pick a neon color)", th = "กำลังปรับ: สีหลักของธีม  (แตะวงกลมเพื่อเลือกสีนีออน)" },
	{ en = "Invalid color code (needs 6 digits)", th = "โค้ดสีไม่ถูกต้อง (ต้องมี 6 หลัก)" },
	{ en = "Config", th = "คอนฟิก" },
	{ en = "Config Name", th = "ชื่อสำหรับบันทึก" },
	{ en = "Config name", th = "ชื่อคอนฟิก" },
	{ en = "Select Config", th = "เลือกคอนฟิก" },
	{ en = "Select a config...", th = "เลือกคอนฟิก..." },
	{ en = "Save Config", th = "บันทึกคอนฟิก" },
	{ en = "Load Config", th = "โหลดคอนฟิก" },
	{ en = "Auto Load Config", th = "โหลดคอนฟิกอัตโนมัติ" },
	{ en = "Delete Config", th = "ลบคอนฟิก" },
	{ en = "Select a config first", th = "เลือกคอนฟิกก่อน" },
	{ en = "Enter a config name first", th = "ใส่ชื่อคอนฟิกก่อน" },
	{ en = "Save failed", th = "บันทึกไม่สำเร็จ" },
	{ en = "Created: %s", th = "สร้างแล้ว: %s" },
	{ en = "Overwritten: %s", th = "บันทึกทับ: %s" },
	{ en = "Created (temporary)", th = "สร้างแล้ว (ชั่วคราว)" },
	{ en = "Saved (temporary)", th = "บันทึกแล้ว (ชั่วคราว)" },
	{ en = "Could not read config", th = "อ่านคอนฟิกไม่ได้" },
	{ en = "Loaded %d values", th = "โหลดแล้ว %d ค่า" },
	{ en = "Config deleted", th = "ลบคอนฟิกแล้ว" },
	{ en = "Auto load on: %s", th = "เปิดโหลดอัตโนมัติ: %s" },
	{ en = "Auto load off", th = "ปิดโหลดอัตโนมัติแล้ว" },
	{ en = "Loaded config: %s", th = "โหลดคอนฟิก: %s" },
	{ en = "Actions", th = "การดำเนินการ" },
	{ en = "Reset Settings", th = "รีเซ็ตการตั้งค่า" },
	{ en = "Destroy GUI", th = "ปิดและลบ GUI" },
	{ en = "Settings reset", th = "รีเซ็ตการตั้งค่าแล้ว" },
	{ en = "Universal Control Panel", th = "แผงควบคุมอเนกประสงค์" },
	{ en = "UI / System  :  LUNAR Team", th = "UI / ระบบ  :  ทีม LUNAR" },
	{ en = "Neon interface for LUNAR Hub", th = "อินเทอร์เฟซนีออนสำหรับ LUNAR Hub" },
	{ en = "Customize", th = "ปรับแต่ง" },
	{ en = "Background Opacity", th = "ความเข้มพื้นหลัง" },
	{ en = "Group Frame", th = "กรอบครอบหมวดหมู่" },
	{ en = "Button Size", th = "ขนาดปุ่ม" },
	{ en = "Normal", th = "ปกติ" },
	{ en = "Compact", th = "กะทัดรัด" },
	{ en = "Section Spacing", th = "ระยะห่างหมวดหมู่" },
	{ en = "Category Opacity", th = "ความเข้มหมวดหมู่" },
	{ en = "Hit by the guard -> picking the animal up again", th = "โดนการ์ดตี -> ไปเก็บสัตว์อีกครั้ง" },
	{ en = "Animal dropped -> going back to pick it up", th = "สัตว์หลุด/ร่วง -> กลับไปเก็บ" },
	{ en = "searching eggs...", th = "กำลังหาไข่..." },
	{ en = "walking to egg", th = "กำลังเดินไปที่ไข่" },
	{ en = "breaking egg", th = "กำลังทุบไข่" },
}
for z = 1, 10 do
	table.insert(LANG_PAIRS, { en = "Zone " .. z, th = "โซน " .. z })
end

local Lang = {
	Current = Settings.Lang == "en" and "en" or "th",
	Index = {},
	Bound = {},
	Listeners = {},
}
for _, pair in ipairs(LANG_PAIRS) do
	Lang.Index[pair.en] = pair
	Lang.Index[pair.th] = pair
end

function Lang.Add(pairs_)
	for _, pair in ipairs(pairs_ or {}) do
		if type(pair) == "table" and type(pair.en) == "string" and type(pair.th) == "string" then
			Lang.Index[pair.en] = pair
			Lang.Index[pair.th] = pair
		end
	end
end
Lang.Add(Context.Translations)

local function Tr(text)
	local pair = type(text) == "string" and Lang.Index[text] or nil
	return pair and pair[Lang.Current] or text
end

local function TrF(text, ...)
	local ok, out = pcall(string.format, Tr(text), ...)
	return ok and out or Tr(text)
end

local DYN_PATTERNS = {
	{ "^Walking to egg %(size (%-?%d+)%)$", "กำลังเดินไปที่ไข่ (ขนาด %s)" },
	{ "^Breaking Titanic Egg: (%d+) / (%d+)$", "กำลังทุบไข่ไททัน: %s / %s" },
	{ "^Waiting for Titanic Egg %(next in (.+)%)$", "รอไข่ไททัน (ครั้งถัดไปใน %s)" },
	{ "^Stealing (.+) %(try (%d+)%)$", "กำลังขโมย %s (ครั้งที่ %s)" },
	{ "^Steal prompt not found for (.+)$", "ไม่พบปุ่มขโมยของ %s" },
	{ "^Cannot read income of (%d+) animal%(s%) yet$", "ยังอ่านรายได้ของสัตว์ %s ตัวไม่ได้" },
	{ "^(%d+) animals: rarity not selected (%d+), income/mutation (%d+), rarity unreadable (%d+)$", "สัตว์ %s ตัว: ความหายากไม่ได้เลือก %s, รายได้/กลายพันธุ์ %s, อ่านความหายากไม่ได้ %s" },
	{ "^Going to (.+) %[(.+)%] zone (%d+)$", "กำลังไปหา %s [%s] โซน %s" },
	{ "^Retry (%d+): (.+)$", "ลองใหม่ครั้งที่ %s: %s" },
	{ "^Stolen: (%d+)$", "ขโมยแล้ว: %s" },
	{ "^1/3 Door: waiting for next event %(starts in (.+)%)$", "1/3 ประตู: รออีเวนต์ถัดไป (เริ่มใน %s)" },
	{ "^1/3 Door: waiting for event %(starts in (.+)%)$", "1/3 ประตู: รออีเวนต์ (เริ่มใน %s)" },
	{ "^2/3 Eggs: (%d+) / (%d+)$", "2/3 ไข่: %s / %s" },
	{ "^3/3 Boss: (%-?%d+) / (%-?%d+)$", "3/3 บอส: %s / %s" },
	{ "^Pickaxe (.+)$", "พิคแอกซ์ %s" },
	{ "^AutoSwing (.+)$", "AutoSwing %s" },
}

local function trCore(core)
	local pair = Lang.Index[core]
	if pair then
		return pair[Lang.Current]
	end
	for _, p in ipairs(DYN_PATTERNS) do
		local caps = { core:match(p[1]) }
		if #caps > 0 then
			for i, c in ipairs(caps) do
				caps[i] = Tr(c)
			end
			local ok, out = pcall(string.format, p[2], table.unpack(caps))
			if ok then
				return out
			end
		end
	end
	return core
end

local function TrDyn(text)
	if type(text) ~= "string" or Lang.Current == "en" then
		return text
	end
	return (text:gsub("[^|]+", function(seg)
		local lead, core, trail = seg:match("^(%s*)(.-)(%s*)$")
		if core == "" then
			return seg
		end
		return lead .. trCore(core) .. trail
	end))
end

function Lang.Bind(obj, prop, src)
	if type(src) ~= "string" or not Lang.Index[src] then
		return
	end
	local shown = Tr(src)
	obj[prop] = shown
	local props = Lang.Bound[obj]
	if not props then
		props = {}
		Lang.Bound[obj] = props
	end
	props[prop] = { src = src, shown = shown }
end

function Lang.OnChange(fn)
	table.insert(Lang.Listeners, fn)
end

function Lang.Set(code)
	if code ~= "en" and code ~= "th" then
		code = "th"
	end
	Lang.Current = code
	for obj, props in pairs(Lang.Bound) do
		if obj.Parent == nil then
			Lang.Bound[obj] = nil
			continue
		end
		for prop, b in pairs(props) do
			if obj[prop] == b.shown then
				local t = Tr(b.src)
				obj[prop] = t
				b.shown = t
			end
		end
	end
	for _, fn in ipairs(Lang.Listeners) do
		pcall(fn)
	end
end

local function ensureFolder(path)
	if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
		return false
	end
	return (pcall(function()
		if not isfolder(path) then
			makefolder(path)
		end
	end))
end

local Config = {}
do
	local ROOT_DIR, CFG_DIR = "LunarHub", "LunarHub/configs/" .. SAFE_ID
	local hasFolders = type(isfolder) == "function" and type(makefolder) == "function"
	local hasList = type(listfiles) == "function"
	local mem = {}

	local function pathOf(name)
		if hasFolders then
			return CFG_DIR .. "/" .. name .. ".json"
		end
		return "LunarHub_cfg_" .. SAFE_ID .. "_" .. name .. ".json"
	end
	local INDEX_FILE = hasFolders and (CFG_DIR .. "/_index.json") or ("LunarHub_cfg_" .. SAFE_ID .. "__index.json")

	local function readIndex()
		local list = {}
		if hasFileApi then
			pcall(function()
				if isfile(INDEX_FILE) then
					local data = HttpService:JSONDecode(readfile(INDEX_FILE))
					if type(data) == "table" then
						for _, n in ipairs(data) do
							if type(n) == "string" then
								table.insert(list, n)
							end
						end
					end
				end
			end)
		end
		return list
	end

	local function writeIndex(list)
		if hasFileApi then
			pcall(function()
				writefile(INDEX_FILE, HttpService:JSONEncode(list))
			end)
		end
	end

	Config.Persistent = hasFileApi

	function Config.Sanitize(name)
		name = tostring(name or "")
		name = name:gsub("[^%w%s_%-\128-\255]", "")
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		local len = utf8.len(name)
		if len and len > 24 then
			name = string.sub(name, 1, utf8.offset(name, 25) - 1)
		end
		return name
	end

	function Config.Exists(name)
		if mem[name] ~= nil then
			return true
		end
		if not hasFileApi then
			return false
		end
		local ok, r = pcall(function()
			local p = pathOf(name)
			return isfile(p) and #readfile(p) > 2
		end)
		return ok and r == true
	end

	function Config.List()
		local names, seen = {}, {}
		local function add(n)
			if n and n ~= "" and n ~= "_index" and not seen[n] then
				seen[n] = true
				table.insert(names, n)
			end
		end
		if hasFileApi and hasFolders and hasList then
			pcall(function()
				for _, f in ipairs(listfiles(CFG_DIR)) do
					local n = (tostring(f):gsub("\\", "/")):match("([^/]+)%.json$")
					if n and Config.Exists(n) then
						add(n)
					end
				end
			end)
		else
			for _, n in ipairs(readIndex()) do
				if Config.Exists(n) then
					add(n)
				end
			end
		end
		for n in pairs(mem) do
			add(n)
		end
		table.sort(names, function(a, b)
			return string.lower(a) < string.lower(b)
		end)
		return names
	end

	function Config.Save(name, values)
		local okEncode, json = pcall(function()
			return HttpService:JSONEncode({ Version = 1, Name = name, Values = values })
		end)
		if not okEncode then
			return false, false
		end
		local persisted = false
		if hasFileApi then
			ensureFolder(ROOT_DIR)
			ensureFolder(CFG_DIR)
			persisted = (pcall(writefile, pathOf(name), json))
		end
		if persisted then
			mem[name] = nil
		else
			mem[name] = json
		end
		local idx, found = readIndex(), false
		for _, n in ipairs(idx) do
			if n == name then
				found = true
			end
		end
		if not found then
			table.insert(idx, name)
			writeIndex(idx)
		end
		return true, persisted
	end

	function Config.Read(name)
		local raw = mem[name]
		if raw == nil and hasFileApi then
			local ok, content = pcall(function()
				local p = pathOf(name)
				if isfile(p) then
					return readfile(p)
				end
			end)
			if ok then
				raw = content
			end
		end
		if type(raw) ~= "string" or raw == "" then
			return nil
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(data) == "table" and type(data.Values) == "table" then
			return data
		end
		return nil
	end

	function Config.Delete(name)
		mem[name] = nil
		if hasFileApi then
			local p = pathOf(name)
			local done = false
			if type(delfile) == "function" then
				done = (pcall(delfile, p))
			end
			if not done then
				pcall(writefile, p, "")
			end
		end
		local out = {}
		for _, n in ipairs(readIndex()) do
			if n ~= name then
				table.insert(out, n)
			end
		end
		writeIndex(out)
	end
end

local Assets = { Ready = {}, Waiters = {} }
do
	local BASE = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Assets/"
	local DIR = "LunarHub/assets"
	local FILES = { Background = "backgroundO.png", Logo = "logoO.png" }
	local getAsset = (type(getcustomasset) == "function" and getcustomasset)
		or (type(getsynasset) == "function" and getsynasset)
		or nil
	local hasFolders = type(isfolder) == "function" and type(makefolder) == "function"

	local function fire(name, id)
		Assets.Ready[name] = id
		for _, fn in ipairs(Assets.Waiters[name] or {}) do
			task.spawn(fn, id)
		end
	end

	function Assets.On(name, fn)
		Assets.Waiters[name] = Assets.Waiters[name] or {}
		table.insert(Assets.Waiters[name], fn)
		if Assets.Ready[name] then
			task.spawn(fn, Assets.Ready[name])
		end
	end

	local function download(url)
		local body
		pcall(function()
			body = game:HttpGet(url)
		end)
		if type(body) ~= "string" or #body < 64 then
			body = nil
			local req = (type(request) == "function" and request)
				or (type(http_request) == "function" and http_request)
				or (syn and type(syn.request) == "function" and syn.request)
				or nil
			if req then
				pcall(function()
					local r = req({ Url = url, Method = "GET" })
					if r and (r.StatusCode == 200 or r.Success) and type(r.Body) == "string" then
						body = r.Body
					end
				end)
			end
		end

		if type(body) == "string" and #body >= 64 and string.sub(body, 2, 4) == "PNG" then
			return body
		end
		return nil
	end

	local function hasValidFile(path)
		local ok, exists = pcall(isfile, path)
		if not (ok and exists == true) then
			return false
		end
		local ok2, body = pcall(readfile, path)
		return ok2 and type(body) == "string" and #body >= 64 and string.sub(body, 2, 4) == "PNG"
	end

	local function show(name, path)
		local ok, id = pcall(getAsset, path)
		if ok and id and id ~= "" then
			fire(name, id)
			return true
		end
		return false
	end

	function Assets.Load(force)
		if not (hasFileApi and getAsset) then
			return
		end
		ensureFolder("LunarHub")
		ensureFolder(DIR)
		local missing = {}
		for name, file in pairs(FILES) do
			local path = hasFolders and (DIR .. "/" .. file) or ("LunarHub_" .. file)
			if not force and hasValidFile(path) then
				show(name, path)
			else
				missing[name] = { file = file, path = path }
			end
		end
		for name, info in pairs(missing) do
			task.spawn(function()
				local body = download(BASE .. info.file)
				if body and pcall(writefile, info.path, body) then
					show(name, info.path)
				end
			end)
		end
	end
end

local COLOR = {
	red = Color3.fromRGB(235, 30, 52),
	redBright = Color3.fromRGB(255, 70, 90),
	redSoft = Color3.fromRGB(255, 110, 125),
	redDark = Color3.fromRGB(90, 8, 18),
	neon = Color3.fromRGB(255, 45, 75),

	black = Color3.fromRGB(8, 8, 10),
	black2 = Color3.fromRGB(17, 16, 21),
	sidebar = Color3.fromRGB(10, 10, 13),
	sidebar2 = Color3.fromRGB(15, 14, 19),

	innerBg = Color3.fromRGB(26, 25, 31),
	innerBgHover = Color3.fromRGB(38, 35, 47),
	innerBorder = Color3.fromRGB(70, 67, 80),
	innerBorderHover = Color3.fromRGB(255, 70, 90),

	switchOff = Color3.fromRGB(34, 33, 40),
	switchBorder = Color3.fromRGB(85, 40, 52),

	white = Color3.fromRGB(245, 245, 248),
	grey = Color3.fromRGB(150, 148, 162),
	border = Color3.fromRGB(62, 43, 51),

	good = Color3.fromRGB(100, 220, 125),
	bad = Color3.fromRGB(255, 90, 100),
}

local NeonSequence
local ThemeListeners = {}

local function Shift(c, dh, ds, dv)
	local h, s, v = Color3.toHSV(c)
	return Color3.fromHSV((h + dh) % 1, math.clamp(s + ds, 0, 1), math.clamp(v + dv, 0, 1))
end

local function BuildNeonSequence(c)
	if Settings.Rainbow then
		local pts = {}
		for i = 0, 6 do
			table.insert(pts, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 0.75, 1)))
		end
		pts[7] = ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 0.75, 1))
		return ColorSequence.new(pts)
	end

	if Settings.Multi and type(Settings.NeonColors) == "table" and #Settings.NeonColors >= 2 then
		local list, n, pts = Settings.NeonColors, #Settings.NeonColors, {}
		for i = 1, n do
			table.insert(pts, ColorSequenceKeypoint.new((i - 1) / n, HexToColor3(list[i]) or c))
		end
		table.insert(pts, ColorSequenceKeypoint.new(1, HexToColor3(list[1]) or c))
		return ColorSequence.new(pts)
	end

	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Shift(c, -0.07, -0.1, 0.12)),
		ColorSequenceKeypoint.new(0.3, c),
		ColorSequenceKeypoint.new(0.55, Shift(c, 0.1, 0, 0.1)),
		ColorSequenceKeypoint.new(0.8, Shift(c, 0.04, 0, -0.38)),
		ColorSequenceKeypoint.new(1, Shift(c, -0.07, -0.1, 0.12)),
	})
end

local function BuildLineSequence(c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, c),
		ColorSequenceKeypoint.new(0.25, COLOR.border),
		ColorSequenceKeypoint.new(1, COLOR.border),
	})
end

local function DeriveTheme(c)
	local h, s = Color3.toHSV(c)
	local k = math.min(s, 1)
	COLOR.red = c
	COLOR.neon = c
	COLOR.redBright = Color3.fromHSV(h, math.min(s, 0.55), 1)
	COLOR.redSoft = Color3.fromHSV(h, math.min(s, 0.35), 1)
	COLOR.redDark = Color3.fromHSV(h, math.min(s, 0.45), 0.22)
	COLOR.innerBorderHover = COLOR.redBright
	COLOR.innerBg = Color3.fromHSV(h, k * 0.1, 0.105)
	COLOR.innerBgHover = Color3.fromHSV(h, k * 0.28, 0.17)
	COLOR.innerBorder = Color3.fromHSV(h, k * 0.1, 0.3)
	COLOR.switchBorder = Color3.fromHSV(h, k * 0.2, 0.25)
	COLOR.border = Color3.fromHSV(h, k * 0.12, 0.2)
	NeonSequence = BuildNeonSequence(c)
end

local function OnTheme(fn)
	table.insert(ThemeListeners, fn)
	fn()
end

DeriveTheme(HexToColor3(Settings.ThemeColor) or HexToColor3(DEFAULT_SETTINGS.ThemeColor))

local Actions = {}

local Custom = { Groups = {}, Sections = {}, Buttons = {} }
function Custom.Refresh(kind)
	for _, fn in ipairs(Custom[kind]) do
		pcall(fn)
	end
end
local savePending = false
function Custom.SaveSoon()
	if savePending then
		return
	end
	savePending = true
	task.delay(0.6, function()
		savePending = false
		saveSettings()
	end)
end

local Gui
local destroyed = false
local connections = {}
local cleanupTasks = {}
local SpinTweens = {}

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function addCleanup(fn)
	table.insert(cleanupTasks, fn)
end

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	for _, e in ipairs(SpinTweens) do
		pcall(function()
			e.Tween:Cancel()
		end)
	end
	for _, fn in ipairs(cleanupTasks) do
		pcall(fn)
	end
	table.clear(cleanupTasks)
	if Gui then
		pcall(function()
			Gui:Destroy()
		end)
	end
	if _G.LunarHubCleanup == cleanup then
		_G.LunarHubCleanup = nil
	end
end
_G.LunarHubCleanup = cleanup

local function New(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function Corner(obj, radius)
	return New("UICorner", { CornerRadius = UDim.new(0, radius) }, obj)
end

local function Stroke(obj, color, thickness, transparency)
	return New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, obj)
end

local function Gradient(obj, colorSeq, rotation)
	return New("UIGradient", { Color = colorSeq, Rotation = rotation or 0 }, obj)
end

local function Tween(obj, time, props, style, direction)
	if not Settings.Animate then
		for k, v in pairs(props) do
			obj[k] = v
		end
		return nil
	end
	local t = TweenService:Create(
		obj,
		TweenInfo.new(
			Settings.Animate and (time or 0.2) or 0,
			style or Enum.EasingStyle.Quart,
			direction or Enum.EasingDirection.Out
		),
		props
	)
	t:Play()
	return t
end

local function Txt(parent, props)
	local base = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = COLOR.white,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local obj = New("TextLabel", base, parent)
	Lang.Bind(obj, "Text", base.Text)
	return obj
end

local orderCounters = setmetatable({}, { __mode = "k" })
local function ord(parent)
	orderCounters[parent] = (orderCounters[parent] or 0) + 1
	return orderCounters[parent]
end

local function NeonLayers(parent, radius, specs)
	local list = {}
	for i, s in ipairs(specs) do
		local f = New("Frame", {
			Name = "NeonLayer" .. i,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = i,
		}, parent)
		Corner(f, radius)
		local st = New("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = s[1],
			Transparency = s[2],
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, f)
		local grad = Gradient(st, NeonSequence, 0)
		table.insert(list, { Frame = f, Stroke = st, Grad = grad, Bright = s[2], Dim = s[3] })
	end
	return list
end

local function Spin(grad, seconds, tier, scope, layer)
	grad.Rotation = 0
	local t = TweenService:Create(
		grad,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
		{ Rotation = 360 }
	)
	table.insert(SpinTweens, { Tween = t, Tier = tier or 1, Scope = scope or "root", Layer = layer })
	return t
end

local Interaction = {}
do
	local scrollers, active = {}, nil

	local function setAll(enabled, keep)
		for sf in pairs(scrollers) do
			if sf.Parent and sf ~= keep then
				sf.ScrollingEnabled = enabled
			end
		end
	end

	function Interaction.Begin(owner, keep)
		if active ~= nil then
			return false
		end
		active = owner
		setAll(false, keep)
		return true
	end

	function Interaction.End(owner)
		if active ~= owner then
			return
		end
		active = nil
		setAll(true)
	end

	function Interaction.WatchScroll(sf)
		scrollers[sf] = true
		local lastMove, watching = 0, false
		track(sf:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			lastMove = os.clock()
			if active == nil then
				Interaction.Begin(sf, sf)
			end

			if active == sf and not watching then
				watching = true
				task.spawn(function()
					while active == sf and not destroyed and os.clock() - lastMove < 0.15 do
						task.wait(0.05)
					end
					watching = false
					Interaction.End(sf)
				end)
			end
		end))
	end
end

do
	local containers = { LocalPlayer:FindFirstChild("PlayerGui") }
	pcall(function()
		table.insert(containers, game:GetService("CoreGui"))
	end)
	for _, c in ipairs(containers) do
		for _, n in ipairs({ "LunarHubGui", "LunarHubAfk", "DXPanelGui", "DXPanel" }) do
			local old = c and c:FindFirstChild(n)
			if old then
				pcall(function()
					old:Destroy()
				end)
			end
		end
	end
end

Gui = New("ScreenGui", {
	Name = "LunarHubGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local function Viewport()
	local s = Gui.AbsoluteSize
	if s.X < 50 or s.Y < 50 then
		local cam = workspace.CurrentCamera
		s = cam and cam.ViewportSize or Vector2.new(1280, 720)
	end
	return s
end

local SIZE = { minW = 340, minH = 260, maxW = 850, maxH = 560, defW = 600, defH = 370 }
local PanelSize, PanelPos

local function ClampSize(w, h)
	local vp = Viewport()
	local maxW = math.min(SIZE.maxW, vp.X - 8)
	local maxH = math.min(SIZE.maxH, vp.Y - 8)
	local minW = math.min(SIZE.minW, maxW)
	local minH = math.min(SIZE.minH, maxH)
	return math.clamp(w, minW, maxW), math.clamp(h, minH, maxH)
end

local function ClampPos(x, y)
	local vp = Viewport()
	return math.clamp(x, 0, math.max(0, vp.X - PanelSize.X)), math.clamp(y, 0, math.max(0, vp.Y - PanelSize.Y))
end

do
	local cw, ch = ClampSize(SIZE.defW, SIZE.defH)
	PanelSize = Vector2.new(cw, ch)
	PanelPos = Vector2.new((Viewport().X - cw) / 2, (Viewport().Y - ch) / 2)
end

local Root = New("Frame", {
	Name = "Root",
	Position = UDim2.fromOffset(PanelPos.X, PanelPos.Y),
	Size = UDim2.fromOffset(PanelSize.X, PanelSize.Y),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, Gui)

local function ApplyPanel()
	Root.Size = UDim2.fromOffset(PanelSize.X, PanelSize.Y)
	Root.Position = UDim2.fromOffset(PanelPos.X, PanelPos.Y)
end

local function SetPanelPos(v)
	local x, y = ClampPos(v.X, v.Y)
	PanelPos = Vector2.new(x, y)
	Root.Position = UDim2.fromOffset(x, y)
end

local function SetPanelSize(w, h)
	local cw, ch = ClampSize(w, h)
	PanelSize = Vector2.new(cw, ch)
	Root.Size = UDim2.fromOffset(cw, ch)
	SetPanelPos(PanelPos)
	if Actions.ApplyLayout then
		Actions.ApplyLayout()
	end
end

local function FitPanel(w, h, recenter)
	local cw, ch = ClampSize(w, h)
	PanelSize = Vector2.new(cw, ch)
	if Actions.ApplyLayout then
		Actions.ApplyLayout()
	end
	if recenter then
		local vp = Viewport()
		PanelPos = Vector2.new((vp.X - cw) / 2, (vp.Y - ch) / 2)
	else
		local x, y = ClampPos(PanelPos.X, PanelPos.Y)
		PanelPos = Vector2.new(x, y)
	end
	Tween(Root, 0.25, {
		Size = UDim2.fromOffset(PanelSize.X, PanelSize.Y),
		Position = UDim2.fromOffset(PanelPos.X, PanelPos.Y),
	})
end

local MainGlow = NeonLayers(Root, 16, {
	{ 3, 0.70, 0.82 },
	{ 7, 0.82, 0.90 },
	{ 12, 0.90, 0.95 },
	{ 18, 0.95, 0.98 },
})
for i, l in ipairs(MainGlow) do
	Spin(l.Grad, 5, 3, "root", i)
end

local Main = New("Frame", {
	Name = "Main",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLOR.black,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 10,
}, Root)
Corner(Main, 16)

Gradient(Main, ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR.black2),
	ColorSequenceKeypoint.new(0.55, COLOR.black),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 8)),
}), 65)

local BgImage = New("ImageLabel", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = "",
	ImageTransparency = 1 - Settings.BgOpacity / 100,
	ScaleType = Enum.ScaleType.Crop,
	Visible = false,
	Active = false,
	ZIndex = 10,
}, Main)
Corner(BgImage, 16)

local MainStroke = Stroke(Main, Color3.new(1, 1, 1), 2, 0)
local MainStrokeGrad = Gradient(MainStroke, NeonSequence, 0)
Spin(MainStrokeGrad, 5, 1, "root")

local Sky = New("Frame", {
	Name = "Sky",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Active = false,
	ZIndex = 11,
}, Main)
Corner(Sky, 16)

local rng = Random.new()

local NebulaLayers = {}
local function Nebula(ax, ay, size, second)
	for i, d in ipairs({ 1, 0.7, 0.42 }) do
		local f = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(ax, ay),
			Size = UDim2.fromOffset(size * d, size * d),
			BackgroundColor3 = COLOR.red,
			BackgroundTransparency = ({ 0.965, 0.95, 0.93 })[i],
			BorderSizePixel = 0,
			ZIndex = 11,
		}, Sky)
		Corner(f, size)
		table.insert(NebulaLayers, { Frame = f, Second = second })
	end
end
Nebula(0.88, 0.12, 300, false)
Nebula(0.25, 0.95, 260, true)

local StarList = {}
for _ = 1, 36 do
	local big = rng:NextInteger(1, 8) == 1
	local sz = big and 3 or rng:NextInteger(1, 2)
	local f = New("Frame", {
		Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
		Size = UDim2.fromOffset(sz, sz),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = rng:NextNumber(0.4, 0.85),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 11,
	}, Sky)
	if big then
		Corner(f, 2)
	end
	table.insert(StarList, { Frame = f, Base = f.BackgroundTransparency })
end

OnTheme(function()
	local h, s, v = Color3.toHSV(COLOR.red)
	for _, l in ipairs(NebulaLayers) do
		l.Frame.BackgroundColor3 = l.Second and Color3.fromHSV((h + 0.12) % 1, math.max(s, 0.5), 1) or COLOR.red
	end
end)

function Actions.RefreshSky()
	local p = GetPerf()
	for i, st in ipairs(StarList) do
		st.Frame.Visible = Settings.Stars and i <= p.stars
	end
	for _, l in ipairs(NebulaLayers) do
		l.Frame.Visible = p.nebula and not Assets.Ready.Background
	end
end

function Actions.SetStars(on)
	Settings.Stars = on
	Actions.RefreshSky()
end

local function SpawnMeteor()
	local sz = Sky.AbsoluteSize
	if sz.X < 120 then
		return
	end
	local len = rng:NextInteger(70, 130)
	local sx = rng:NextNumber(0.4, 1.05) * sz.X
	local sy = rng:NextNumber(-0.08, 0.35) * sz.Y
	local dist = rng:NextNumber(0.5, 0.85) * sz.X
	local ex, ey = sx - dist * 0.866, sy + dist * 0.5
	local dur = rng:NextNumber(0.8, 1.4)

	local m = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(sx, sy),
		Size = UDim2.fromOffset(len, 2),
		Rotation = -30,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, Sky)
	Corner(m, 1)
	local g = Gradient(m, ColorSequence.new(Color3.new(1, 1, 1), COLOR.redSoft), 0)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.18, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	TweenService:Create(m, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(ex, ey),
	}):Play()

	TweenService:Create(
		m,
		TweenInfo.new(dur * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, dur * 0.55),
		{ BackgroundTransparency = 1 }
	):Play()
	task.delay(dur + 0.05, function()
		if m.Parent then
			m:Destroy()
		end
	end)
end

task.spawn(function()
	while not destroyed and Sky.Parent do
		local p = GetPerf()
		task.wait(rng:NextNumber(p.meteorMin, p.meteorMax))
		p = GetPerf()
		if p.meteor and Settings.Stars and Root.Visible then
			SpawnMeteor()
			if p.meteorDouble and rng:NextInteger(1, 4) == 1 then
				task.delay(rng:NextNumber(0.2, 0.5), SpawnMeteor)
			end
		end
	end
end)

task.spawn(function()
	while not destroyed and Sky.Parent do
		local p = GetPerf()
		task.wait(p.twinkleEvery)
		p = GetPerf()
		if p.twinkle > 0 and Settings.Stars and Root.Visible then
			for _ = 1, p.twinkle do
				local st = StarList[rng:NextInteger(1, math.max(1, p.stars))]
				if st and st.Frame.Visible then
					TweenService:Create(
						st.Frame,
						TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true),
						{ BackgroundTransparency = 0.05 }
					):Play()
				end
			end
		end
	end
end)

Assets.On("Background", function(id)
	if BgImage.Parent then
		BgImage.Image = id
		BgImage.Visible = true
		Actions.RefreshSky()
	end
end)

local Toast = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(240, 30),
	BackgroundColor3 = COLOR.black,
	BackgroundTransparency = 0.05,
	Text = "",
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextColor3 = COLOR.white,
	Visible = false,
	ZIndex = 300,
}, Main)
Corner(Toast, 10)
local ToastStroke = Stroke(Toast, COLOR.good, 1.5, 0)
local toastToken = 0

local function Notify(text, good)
	toastToken += 1
	local token = toastToken
	Toast.Text = Tr(text)
	ToastStroke.Color = good and COLOR.good or COLOR.bad
	Toast.Visible = true
	task.delay(2, function()
		if token == toastToken and Toast.Parent then
			Toast.Visible = false
		end
	end)
end

local Sidebar = New("Frame", {
	Position = UDim2.new(0, 2, 0, 4),
	Size = UDim2.new(0, 145, 1, -6),
	BackgroundColor3 = COLOR.sidebar2,
	BorderSizePixel = 0,
	Active = true,
	ClipsDescendants = true,
	ZIndex = 11,
}, Main)
Corner(Sidebar, 14)

Gradient(Sidebar, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205)), 80)

local SidebarLine = New("Frame", {
	Position = UDim2.new(1, -1, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = COLOR.border,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 15,
}, Sidebar)

local Moon = New("Frame", {
	Position = UDim2.new(0, 14, 0, 13),
	Size = UDim2.fromOffset(30, 30),
	BackgroundTransparency = 1,
	ZIndex = 20,
}, Sidebar)
local MoonDisc = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(240, 236, 255),
	BorderSizePixel = 0,
	ZIndex = 21,
}, Moon)
Corner(MoonDisc, 12)
Gradient(MoonDisc, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 184, 230)), 45)
local MoonStroke = Stroke(MoonDisc, COLOR.neon, 3, 0.6)
for _, c in ipairs({ { 14, 5, 6 }, { 5, 12, 8 }, { 15, 15, 4 } }) do
	local crater = New("Frame", {
		Position = UDim2.fromOffset(c[1], c[2]),
		Size = UDim2.fromOffset(c[3], c[3]),
		BackgroundColor3 = Color3.fromRGB(196, 190, 228),
		BorderSizePixel = 0,
		ZIndex = 22,
	}, MoonDisc)
	Corner(crater, c[3])
end

local LogoImage = New("ImageLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	Visible = false,
	ZIndex = 23,
}, Moon)
Assets.On("Logo", function(id)
	if LogoImage.Parent then
		LogoImage.Image = id
		LogoImage.Visible = true
		MoonDisc.Visible = false
	end
end)

local LogoTitle = Txt(Sidebar, {
	Position = UDim2.new(0, 52, 0, 12),
	Size = UDim2.new(1, -58, 0, 18),
	Text = "LUNAR",
	Font = Enum.Font.GothamBlack,
	TextSize = 17,
	ZIndex = 20,
})

local PanelWord = Txt(Sidebar, {
	Position = UDim2.new(0, 52, 0, 29),
	Size = UDim2.new(1, -58, 0, 12),
	Text = "H U B",
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	ZIndex = 20,
})

local LogoLine = New("Frame", {
	Visible = false,
	Position = UDim2.new(0, 15, 0, 49),
	Size = UDim2.fromOffset(35, 2),
	BackgroundColor3 = COLOR.red,
	BorderSizePixel = 0,
	ZIndex = 20,
}, Sidebar)
Corner(LogoLine, 2)
local LogoGrad = Gradient(LogoLine, ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR.redBright),
	ColorSequenceKeypoint.new(1, COLOR.redDark),
}), 0)

local Online = Txt(Sidebar, {
	Position = UDim2.new(0, 15, 0, 55),
	Size = UDim2.new(1, -30, 0, 18),
	Text = "●  " .. Tr("ONLINE"),
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = COLOR.good,
	ZIndex = 20,
})

task.spawn(function()
	local dim = false
	while not destroyed and Online.Parent do
		if Root.Visible and GetPerf().blink then
			Tween(Online, 1.0, { TextTransparency = dim and 0 or 0.55 }, Enum.EasingStyle.Sine)
		end
		dim = not dim
		task.wait(1)
	end
end)

local TabHolder = New("ScrollingFrame", {
	Position = UDim2.new(0, 9, 0, 88),
	Size = UDim2.new(1, -18, 1, -98),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ClipsDescendants = true,
	ZIndex = 20,
}, Sidebar)
New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, TabHolder)

local SidebarDivider = New("Frame", {
	Position = UDim2.new(0, 12, 0, 80),
	Size = UDim2.new(1, -24, 0, 2),
	BackgroundColor3 = COLOR.red,
	BorderSizePixel = 0,
	ZIndex = 20,
}, Sidebar)
Corner(SidebarDivider, 2)
New("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, SidebarDivider)
Interaction.WatchScroll(TabHolder)

local Content = New("Frame", {
	Position = UDim2.new(0, 145, 0, 4),
	Size = UDim2.new(1, -145, 1, -6),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 11,
}, Main)

local Header = New("Frame", {
	Position = UDim2.new(0, 15, 0, 9),
	Size = UDim2.new(1, -30, 0, 38),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 25,
}, Content)

local Title = Txt(Header, {
	Size = UDim2.new(1, -55, 0, 22),
	Text = "Overview",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	ZIndex = 30,
})

Txt(Header, {
	Position = UDim2.new(0, 0, 0, 21),
	Size = UDim2.new(1, -55, 0, 14),
	Text = "LUNAR Hub Premium Interface",
	TextSize = 10,
	TextColor3 = COLOR.grey,
	ZIndex = 30,
})

local Close = New("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 4),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = Color3.fromRGB(24, 19, 23),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "×",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = COLOR.grey,
	ZIndex = 100,
}, Header)
Corner(Close, 8)
local CloseStroke = Stroke(Close, COLOR.border, 1, 0.1)

track(Close.MouseEnter:Connect(function()
	Tween(Close, 0.15, { BackgroundColor3 = Color3.fromRGB(70, 12, 20), TextColor3 = COLOR.redBright, Rotation = 90 })
	Tween(CloseStroke, 0.15, { Color = COLOR.red })
end))
track(Close.MouseLeave:Connect(function()
	Tween(Close, 0.15, { BackgroundColor3 = Color3.fromRGB(24, 19, 23), TextColor3 = COLOR.grey, Rotation = 0 })
	Tween(CloseStroke, 0.15, { Color = COLOR.border })
end))

local PageHolder = New("Frame", {
	Position = UDim2.new(0, 15, 0, 68),
	Size = UDim2.new(1, -30, 1, -80),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 15,
}, Content)

local Pages = {}
local Tabs = {}

local layoutCompact, layoutTight

function Actions.ApplyLayout()
	local compact = PanelSize.X < 480
	local tight = PanelSize.Y < 320
	local w = compact and 56 or 145
	local changed = false

	if compact ~= layoutCompact then
		local sizeS = UDim2.new(0, w, 1, -6)
		local posC = UDim2.new(0, w, 0, 4)
		local sizeC = UDim2.new(1, -w, 1, -6)
		if layoutCompact == nil then
			Sidebar.Size, Content.Position, Content.Size = sizeS, posC, sizeC
		else
			Tween(Sidebar, 0.22, { Size = sizeS })
			Tween(Content, 0.22, { Position = posC, Size = sizeC })
		end
		layoutCompact = compact

		LogoTitle.Visible = not compact
		PanelWord.Visible = not compact
		Moon.Position = compact and UDim2.new(0.5, -15, 0, 13) or UDim2.new(0, 14, 0, 13)
		Online.Text = compact and "●" or ("●  " .. Tr("ONLINE"))
		Online.TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		changed = true
	end

	if tight ~= layoutTight then
		layoutTight = tight
		changed = true
	end

	if changed then

		Online.Visible = true
		Online.Size = compact and UDim2.new(1, 0, 0, 18) or UDim2.new(1, -30, 0, 18)
		Online.Position = UDim2.new(0, compact and 0 or 15, tight and 1 or 0, tight and -26 or 55)
		local top = tight and 58 or 88
		local bottom = tight and 32 or 10
		TabHolder.Position = UDim2.new(0, 9, 0, top)
		SidebarDivider.Position = UDim2.new(0, 12, 0, top - 8)
		TabHolder.Size = UDim2.new(1, -18, 1, -(top + bottom))
	end

	for _, tab in pairs(Tabs) do
		tab.Label.Visible = not compact
	end
end

Lang.OnChange(function()
	if layoutCompact ~= nil then
		Online.Text = layoutCompact and "●" or ("●  " .. Tr("ONLINE"))
	end
	if Actions.ActiveTab then
		Title.Text = Tr(Actions.ActiveTab)
	end
end)

OnTheme(function()
	MainStroke.Color = Color3.new(1, 1, 1)
	MainStrokeGrad.Color = NeonSequence
	for _, layer in ipairs(MainGlow) do
		layer.Stroke.Color = Color3.new(1, 1, 1)
		layer.Grad.Color = NeonSequence
	end
	LogoTitle.TextColor3 = COLOR.white
	SidebarDivider.BackgroundColor3 = COLOR.red
	PanelWord.TextColor3 = COLOR.redSoft
	MoonStroke.Color = COLOR.neon
	LogoLine.BackgroundColor3 = COLOR.red
	LogoGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOR.redBright),
		ColorSequenceKeypoint.new(1, COLOR.redDark),
	})
	SidebarLine.BackgroundColor3 = COLOR.border
	Title.TextColor3 = COLOR.white
end)

local CurrentPage = nil
local Picker = {}
local Registry, RegistryOrder = {}, {}

local function Register(text, kind, api, explicitKey)
	local key = explicitKey
	if not key then
		if kind == "section" then
			key = "Section:" .. tostring(CurrentPage) .. ":" .. text
		elseif CurrentPage and CurrentPage ~= "Settings" then
			key = tostring(CurrentPage) .. ":" .. text
		else
			return nil
		end
	end
	if Registry[key] then
		local n = 2
		while Registry[key .. "#" .. n] do
			n += 1
		end
		key = key .. "#" .. n
	end
	api.Kind = kind
	Registry[key] = api
	table.insert(RegistryOrder, key)
	return key
end

local function IsExcludedKey(key)
	for _, pattern in ipairs(Context.ConfigExclude) do
		if key:find(pattern) then
			return true
		end
	end
	return false
end

local function CollectConfig()
	local values = {}
	for _, key in ipairs(RegistryOrder) do
		local r = Registry[key]
		local ok, v = pcall(r.Get)
		if ok and v ~= nil and not IsExcludedKey(key) then
			values[key] = v
		end
	end
	return values
end

local function ApplyConfig(values)
	local applied = 0
	for _, key in ipairs(RegistryOrder) do
		local v = values[key]
		local r = Registry[key]
		if v ~= nil and r and not IsExcludedKey(key) then
			if pcall(r.Set, v) then
				applied += 1
			end
		end
	end
	return applied
end

local function CreatePage(name)
	CurrentPage = name
	local Page = New("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = COLOR.red,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
	}, PageHolder)

	Interaction.WatchScroll(Page)

	New("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 8),
	}, Page)

	local Layout = New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, Page)
	track(Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		Page.CanvasSize = UDim2.fromOffset(0, Layout.AbsoluteContentSize.Y + 10)
	end))

	OnTheme(function()
		Page.ScrollBarImageColor3 = COLOR.red
	end)

	Pages[name] = Page
	return Page
end

local function IconWrap(parent)
	return New("Frame", {
		Position = UDim2.new(0, 9, 0.5, -9),
		Size = UDim2.fromOffset(19, 19),
		BackgroundTransparency = 1,
		ZIndex = 40,
	}, parent)
end

local function Part(parent, props, radius)
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 41
	local f = New("Frame", props, parent)
	if radius then
		Corner(f, radius)
	end
	return f
end

local IconBuilders = {}

function IconBuilders.house(parent, color)
	local Wrap = IconWrap(parent)
	local RoofClip = New("Frame", {
		Size = UDim2.fromOffset(19, 9),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 41,
	}, Wrap)
	local Roof = Part(RoofClip, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.fromOffset(13, 13),
		Rotation = 45,
		BackgroundColor3 = color,
	}, 3)
	local Chimney = Part(Wrap, {
		Position = UDim2.new(0, 13, 0, 0),
		Size = UDim2.fromOffset(3, 6),
		BackgroundColor3 = color,
		ZIndex = 39,
	}, 1)
	local Body = Part(Wrap, {
		Position = UDim2.new(0, 2, 0, 8),
		Size = UDim2.fromOffset(15, 11),
		BackgroundColor3 = color,
	}, 3)
	Part(Body, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 1, 1, 0),
		Size = UDim2.fromOffset(4, 7),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	}, 1)
	Part(Body, {
		Position = UDim2.new(0, 3, 0, 2),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	}, 1)
	return Wrap, { Roof, Chimney, Body }
end

function IconBuilders.gear(parent, color)
	local Wrap = IconWrap(parent)
	local parts = {}
	for i = 1, 8 do
		table.insert(parts, Part(Wrap, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(4, 18),
			Rotation = (i - 1) * 45,
			BackgroundColor3 = color,
			ZIndex = 40,
		}, 2))
	end
	table.insert(parts, Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(13, 13),
		BackgroundColor3 = color,
	}, 7))
	Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	})
	return Wrap, parts
end

function IconBuilders.player(parent, color)
	local Wrap = IconWrap(parent)
	local Head = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = color,
	}, 4)
	local Body = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.fromOffset(15, 8),
		BackgroundColor3 = color,
	}, 5)
	return Wrap, { Head, Body }
end

function IconBuilders.sprout(parent, color)
	local Wrap = IconWrap(parent)
	local Stem = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.fromOffset(2, 11),
		BackgroundColor3 = color,
	}, 1)
	local LeafL = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(5, 6),
		Size = UDim2.fromOffset(9, 5),
		Rotation = -30,
		BackgroundColor3 = color,
	}, 3)
	local LeafR = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(9, 5),
		Rotation = 30,
		BackgroundColor3 = color,
	}, 3)
	return Wrap, { Stem, LeafL, LeafR }
end

function IconBuilders.eye(parent, color)
	local Wrap = IconWrap(parent)
	local Outer = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(19, 12),
		BackgroundColor3 = color,
	}, 6)
	Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	}, 5)
	local Dot = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = color,
		ZIndex = 43,
	}, 2)
	return Wrap, { Outer, Dot }
end

function IconBuilders.info(parent, color)
	local Wrap = IconWrap(parent)
	local Circle = Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = color,
	}, 9)
	Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		Size = UDim2.fromOffset(2, 7),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	})
	Part(Wrap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = COLOR.black,
		ZIndex = 42,
	}, 2)
	return Wrap, { Circle }
end

local function CreateTab(name, icon)
	local Button = New("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = COLOR.innerBg,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = ord(TabHolder),
		ZIndex = 30,
	}, TabHolder)
	Corner(Button, 12)

	local Bar = New("Frame", {
		Position = UDim2.new(0, 5, 0.5, -8),
		Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = COLOR.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 40,
	}, Button)
	Corner(Bar, 3)

	local Icon, iconParts, isImage
	local iconStr = tostring(icon)

	if IconBuilders[iconStr] then
		Icon, iconParts = IconBuilders[iconStr](Button, COLOR.grey)
	elseif iconStr:match("^rbxassetid://") or iconStr:match("^%d+$") then
		isImage = true
		Icon = New("ImageLabel", {
			Position = UDim2.new(0, 11, 0.5, -9),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			Image = iconStr:match("^%d+$") and ("rbxassetid://" .. iconStr) or iconStr,
			ImageColor3 = COLOR.grey,
			ZIndex = 40,
		}, Button)
	else
		Icon = Txt(Button, {
			Position = UDim2.new(0, 11, 0, 0),
			Size = UDim2.fromOffset(20, 32),
			Text = iconStr,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = COLOR.grey,
			ZIndex = 40,
		})
	end

	local Label = Txt(Button, {
		Position = UDim2.new(0, 37, 0, 0),
		Size = UDim2.new(1, -42, 0, 32),
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextColor3 = COLOR.grey,
		ZIndex = 40,
	})

	local tab = {
		Button = Button,
		Icon = Icon,
		Label = Label,
		Bar = Bar,
		IsImage = isImage,
		IconParts = iconParts,
		Active = false,
	}
	Tabs[name] = tab

	local function IconColor(c, instant)
		if tab.IconParts then
			for _, part in ipairs(tab.IconParts) do
				if instant then
					part.BackgroundColor3 = c
				else
					Tween(part, 0.18, { BackgroundColor3 = c })
				end
			end
		elseif tab.IsImage then
			Tween(tab.Icon, 0.18, { ImageColor3 = c })
		else
			Tween(tab.Icon, 0.18, { TextColor3 = c })
		end
	end

	function tab.Paint(instant)
		local a = tab.Active
		Tween(Button, 0.18, {
			BackgroundColor3 = a and COLOR.red or COLOR.innerBg,
			BackgroundTransparency = a and 0 or 0.35,
		})
		IconColor(a and Color3.new(1, 1, 1) or COLOR.grey, instant)
		Label.Font = a and Enum.Font.GothamBold or Enum.Font.GothamMedium
		Tween(Label, 0.18, { TextColor3 = a and Color3.new(1, 1, 1) or COLOR.grey })
		Bar.Visible = false
	end

	OnTheme(function()
		tab.Paint(true)
	end)

	track(Button.MouseEnter:Connect(function()
		if not tab.Active then
			Tween(Button, 0.15, { BackgroundColor3 = COLOR.innerBgHover, BackgroundTransparency = 0.1 })
			Tween(Label, 0.15, { TextColor3 = COLOR.white })
		end
	end))
	track(Button.MouseLeave:Connect(function()
		if not tab.Active then
			Tween(Button, 0.15, { BackgroundColor3 = COLOR.innerBg, BackgroundTransparency = 0.35 })
			Tween(Label, 0.15, { TextColor3 = COLOR.grey })
		end
	end))
	track(Button.Activated:Connect(function()
		Actions.ActivateTab(name)
	end))

	return Button
end

function Actions.ActivateTab(name)
	for tabName, tab in pairs(Tabs) do
		tab.Active = tabName == name
		tab.Paint()
		if Pages[tabName] then
			Pages[tabName].Visible = tab.Active
		end
		if tab.Active then
			Actions.ActiveTab = tabName
			Title.Text = Tr(tabName)
		end
	end
	if Actions.UpdateAnim then
		Actions.UpdateAnim()
	end
end

local SectionsByParent = setmetatable({}, { __mode = "k" })

local Layout = { Edit = false }
function Layout.Sorted(parent)
	local list = {}
	for _, s in ipairs(SectionsByParent[parent] or {}) do
		if s.Holder.Parent then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		return a.Holder.LayoutOrder < b.Holder.LayoutOrder
	end)
	return list
end
function Layout.Apply(parent, ordered)
	local cur = Layout.Sorted(parent)
	if #cur == 0 then
		return
	end
	local base = cur[1].Holder.LayoutOrder
	local blocks = {}
	for _, s in ipairs(cur) do
		local blk = s.Members()
		table.sort(blk, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		table.insert(blk, 1, s.Holder)
		blocks[s] = blk
	end
	local n = base
	for _, s in ipairs(ordered) do
		for _, obj in ipairs(blocks[s] or {}) do
			obj.LayoutOrder = n
			n = n + 1
		end
	end
end
function Layout.Save(parent)
	local names = {}
	for _, s in ipairs(Layout.Sorted(parent)) do
		table.insert(names, s.Name)
	end
	if type(Settings.SectionOrder) ~= "table" then
		Settings.SectionOrder = {}
	end
	Settings.SectionOrder[parent.Name] = names
	Custom.SaveSoon()
end
function Layout.Move(parent, sec, dir)
	local list = Layout.Sorted(parent)
	local idx = table.find(list, sec)
	if not idx then
		return
	end
	local j = idx + dir
	if j < 1 or j > #list then
		return
	end
	list[idx], list[j] = list[j], list[idx]
	Layout.Apply(parent, list)
	Layout.Save(parent)
	Custom.Refresh("Sections")
	Custom.Refresh("Groups")
end
function Layout.Restore()
	local saved = Settings.SectionOrder
	if type(saved) ~= "table" then
		return
	end
	for parent in pairs(SectionsByParent) do
		local names = saved[parent.Name]
		if type(names) == "table" then
			local cur = Layout.Sorted(parent)
			table.sort(cur, function(a, b)
				return a.Index < b.Index
			end)
			local ordered, used = {}, {}
			for _, nm in ipairs(names) do
				for _, s in ipairs(cur) do
					if not used[s] and s.Name == nm then
						used[s] = true
						table.insert(ordered, s)
						break
					end
				end
			end
			for _, s in ipairs(cur) do
				if not used[s] then
					table.insert(ordered, s)
				end
			end
			Layout.Apply(parent, ordered)
		end
	end
	Custom.Refresh("Sections")
	Custom.Refresh("Groups")
end
function Layout.Reset()
	for parent in pairs(SectionsByParent) do
		local cur = Layout.Sorted(parent)
		table.sort(cur, function(a, b)
			return a.Index < b.Index
		end)
		Layout.Apply(parent, cur)
	end
	Settings.SectionOrder = {}
	Custom.Refresh("Sections")
	Custom.Refresh("Groups")
	saveSettings()
end

local function MakeChevron(parent, size, z, thickOverride)
	local Holder = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z or 1,
	}, parent)
	local arms = {}
	local len = size * 0.56
	local thick = thickOverride or math.max(2, size * 0.17)
	for _, side in ipairs({ -1, 1 }) do
		local arm = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(size / 2 + side * len * 0.355, size / 2),
			Size = UDim2.fromOffset(thick, len),
			Rotation = side * 45,
			BackgroundColor3 = COLOR.grey,
			BorderSizePixel = 0,
			ZIndex = (z or 1) + 1,
		}, Holder)
		Corner(arm, thick / 2)
		table.insert(arms, arm)
	end
	return Holder, arms
end

local function MakeArrowBadge(parent, opts)
	opts = opts or {}
	local size = opts.Size or 22
	local z = opts.Z or 60
	local danger = opts.Danger == true
	local accentIdle = opts.AccentIdle == true

	local Badge = New("Frame", {
		AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Corner(Badge, size / 2)
	Gradient(Badge, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 185)), 90)
	local BadgeStroke = Stroke(Badge, COLOR.border, 1.3, 0.1)

	local Halo = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size + 6, size + 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
	}, Badge)
	Corner(Halo, (size + 6) / 2)
	local HaloStroke = Stroke(Halo, COLOR.red, 2, 1)

	local Rot = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	}, Badge)
	local cs = math.floor(size * 0.66)
	local GlowChev, glowArms = MakeChevron(Rot, cs, z + 2, math.max(5, cs * 0.36))
	GlowChev.Position = UDim2.fromScale(0.5, 0.5)
	local Chev, arms = MakeChevron(Rot, cs, z + 3, math.max(2, cs * 0.2))
	Chev.Position = UDim2.fromScale(0.5, 0.5)
	for _, a in ipairs(glowArms) do
		a.BackgroundTransparency = 1
	end

	local B = { Frame = Badge, Lit = false, Hover = false }

	function B.Paint(lit, hover)
		B.Lit, B.Hover = lit == true, hover == true
		local accent = danger and COLOR.bad or COLOR.red
		local soft = danger and COLOR.bad or COLOR.redSoft
		local bg, stroke, arm, haloT, glowT
		if B.Hover then
			bg, stroke, arm, haloT, glowT = COLOR.innerBgHover, accent, soft, 0.62, 0.8
		elseif B.Lit then
			bg, stroke, arm, haloT, glowT = COLOR.innerBg, accent, soft, 1, 0.88
		else
			bg, stroke, arm, haloT, glowT = COLOR.innerBg, danger and COLOR.bad or (accentIdle and COLOR.red or COLOR.border), danger and COLOR.bad or (accentIdle and COLOR.redSoft or COLOR.grey), 1, 1
		end
		Tween(Badge, 0.16, { BackgroundColor3 = bg })
		Tween(BadgeStroke, 0.16, { Color = stroke })
		Tween(HaloStroke, 0.16, { Color = accent, Transparency = haloT })
		for _, a in ipairs(arms) do
			Tween(a, 0.16, { BackgroundColor3 = arm })
		end
		for _, a in ipairs(glowArms) do
			Tween(a, 0.16, { BackgroundColor3 = soft, BackgroundTransparency = glowT })
		end
	end

	function B.SetRotation(deg, instant)
		if instant then
			Rot.Rotation = deg
		else
			Tween(Rot, 0.24, { Rotation = deg }, Enum.EasingStyle.Back)
		end
	end

	function B.Press()
		Badge.Size = UDim2.fromOffset(size - 5, size - 5)
		Tween(Badge, 0.2, { Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Back)
	end

	OnTheme(function()
		B.Paint(B.Lit, B.Hover)
	end)
	return B
end

local function Section(parent, text)
	local prior = SectionsByParent[parent]
	local isFirst = not (prior and #prior > 0)
	local prevSec = prior and prior[#prior] or nil
	local sec
	local function gapNow()
		if sec == nil then
			return isFirst and 0 or Settings.SectionGap
		end
		return (Layout.Sorted(parent)[1] == sec) and 0 or Settings.SectionGap
	end
	local Holder = New("TextButton", {
		Size = UDim2.new(1, 0, 0, 26 + gapNow()),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = ord(parent),
	}, parent)
	local Inner = New("Frame", {
		Position = UDim2.fromOffset(0, gapNow()),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
	}, Holder)

	local Plate = New("Frame", {
		Size = UDim2.new(1, 0, 1, -2),
		BackgroundColor3 = COLOR.redDark,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, Inner)
	Corner(Plate, 7)
	local PlateStroke = Stroke(Plate, COLOR.red, 1, 1)
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
	}, Plate)
	local BottomLine = New("Frame", {
		Position = UDim2.new(0, 8, 1, -3),
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = COLOR.red,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, Inner)
	local AccentBar = New("Frame", {
		Visible = false,
		Position = UDim2.new(0, 9, 0, 6),
		Size = UDim2.fromOffset(3, 11),
		BackgroundColor3 = COLOR.redBright,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, Inner)
	Corner(AccentBar, 2)

	local Label = Txt(Inner, {
		Position = UDim2.new(0, 10, 0, 3),
		Size = UDim2.new(1, -30, 0, 18),
		Text = string.upper(Tr(text)),
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextTransparency = 0.2,
		ZIndex = 3,
	})
	Lang.OnChange(function()
		Label.Text = string.upper(Tr(text))
	end)

	local Badge = MakeArrowBadge(Inner, {
		Size = 18,
		Z = 4,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 12),
	})

	Badge.Frame.Visible = false

	local function makeMove(dir, x)
		local b = New("TextButton", {
			Position = UDim2.new(1, x, 0, 2),
			Size = UDim2.fromOffset(22, 20),
			BackgroundColor3 = COLOR.redDark,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = ">",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = COLOR.white,
			Rotation = dir < 0 and -90 or 90,
			Visible = false,
			ZIndex = 8,
		}, Inner)
		Corner(b, 5)
		Stroke(b, COLOR.red, 1, 0.5)
		track(b.Activated:Connect(function()
			Layout.Move(parent, sec, dir)
		end))
		return b
	end
	local MoveUp = makeMove(-1, -54)
	local MoveDown = makeMove(1, -28)

	local siblings = SectionsByParent[parent]
	if not siblings then
		siblings = {}
		SectionsByParent[parent] = siblings
	end
	sec = { Holder = Holder, Collapsed = false, Name = text, Index = #siblings + 1 }
	table.insert(siblings, sec)
	if prevSec then
		prevSec.Next = sec
	end

	local hover = false
	local paintArrow
	local function members()
		local mine = Holder.LayoutOrder
		local nextOrder = math.huge
		for _, s in ipairs(siblings) do
			local o = s.Holder.LayoutOrder
			if s ~= sec and o > mine and o < nextOrder then
				nextOrder = o
			end
		end
		local out = {}
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("GuiObject") then
				local o = child.LayoutOrder
				if o > mine and o < nextOrder then
					table.insert(out, child)
				end
			end
		end
		return out
	end

	sec.Members = members

	local Glow = New("Frame", {
		Name = "GroupGlow",
		Visible = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	}, Holder)
	Corner(Glow, 11)
	local GlowStroke = Stroke(Glow, COLOR.redBright, 4, 0.8)

	local Group = New("Frame", {
		Name = "Group",
		Visible = false,
		BackgroundColor3 = COLOR.black,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 2,
	}, Holder)
	Corner(Group, 11)
	local GroupStroke = Stroke(Group, COLOR.red, 1.4, 0.3)

	local function applyFrameStyle()
		local n = math.clamp(Settings.GroupNeon, 0, 100) / 100
		Group.BackgroundTransparency = 1 - math.clamp(Settings.GroupFill, 0, 100) / 100 * 0.6
		GroupStroke.Color = COLOR.red
		GroupStroke.Transparency = 0.6 - 0.5 * n
		GroupStroke.Thickness = 1 + 0.6 * n
		GlowStroke.Color = COLOR.redBright
		GlowStroke.Transparency = 1 - 0.45 * n
		Glow.Visible = Group.Visible and n > 0.02
	end

	local function updateGroup()
		if not Settings.GroupFrame or not Holder.Parent then
			Group.Visible = false
			Glow.Visible = false
			return
		end
		local hy = Holder.AbsolutePosition.Y
		local top = hy + gapNow() - 2
		local bottom
		for _, child in ipairs(members()) do
			if child.Visible then
				local b = child.AbsolutePosition.Y + child.AbsoluteSize.Y
				bottom = bottom and math.max(bottom, b) or b
			end
		end
		if not bottom then
			bottom = hy + Holder.AbsoluteSize.Y
		end
		for _, f in ipairs({ Group, Glow }) do
			f.Position = UDim2.new(0, -2, 0, top - hy)
			f.Size = UDim2.new(1, 4, 0, bottom - top + 6)
			f.Visible = true
		end
		applyFrameStyle()
	end

	local function apply()
		for _, child in ipairs(members()) do
			child.Visible = not sec.Collapsed
		end
		Badge.SetRotation(sec.Collapsed and -90 or 0)
		paintArrow()
		if sec.Collapsed then
			Group.Visible = false
		end
		if sec.Next and sec.Next.Restyle then
			sec.Next.Restyle()
		end
		task.defer(updateGroup)
	end

	local layout = parent:FindFirstChildOfClass("UIListLayout")
	if layout then
		track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			task.defer(updateGroup)
		end))
	end
	task.defer(updateGroup)
	table.insert(Custom.Groups, updateGroup)

	function paintArrow()
		Badge.Paint(not sec.Collapsed, hover)
		local base = 1 - (Settings.SectionFade / 100) * 0.44
		Tween(Plate, 0.15, { BackgroundTransparency = math.clamp(hover and base - 0.18 or base, 0, 1) })
	end

	local function applyStyle()
		local s = Settings.SectionFade / 100
		Label.TextTransparency = 0.5 * (1 - s)
		BottomLine.BackgroundTransparency = 1 - s * 0.6
		AccentBar.BackgroundTransparency = math.max(0, 1 - s * 1.1)
		Holder.Size = UDim2.new(1, 0, 0, 26 + gapNow())
		Inner.Position = UDim2.fromOffset(0, gapNow())
		local sorted = Layout.Sorted(parent)
		MoveUp.Visible = false
		MoveDown.Visible = false
		MoveUp.TextTransparency = (sorted[1] == sec) and 0.7 or 0
		MoveDown.TextTransparency = (sorted[#sorted] == sec) and 0.7 or 0
		paintArrow()
	end
	sec.Restyle = applyStyle
	table.insert(Custom.Sections, applyStyle)

	function sec.Set(collapsed)
		-- collapse system removed: sections are always open
		sec.Collapsed = false
	end

	OnTheme(function()
		Label.TextColor3 = COLOR.grey
		Plate.BackgroundColor3 = COLOR.redDark
		PlateStroke.Color = COLOR.red
		BottomLine.BackgroundColor3 = COLOR.red
		AccentBar.BackgroundColor3 = COLOR.redBright
		GroupStroke.Color = COLOR.red
		GlowStroke.Color = COLOR.redBright
		applyStyle()
	end)

	track(Holder.MouseEnter:Connect(function()
		hover = true
		paintArrow()
	end))
	track(Holder.MouseLeave:Connect(function()
		hover = false
		paintArrow()
	end))
	Holder.Active = false
	Holder.AutoButtonColor = false

	Register(text, "section", {
		Get = function()
			return sec.Collapsed
		end,
		Set = sec.Set,
	})

	return Holder
end

local function CardBase(parent, height, class)
	local Holder = New(class or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		LayoutOrder = ord(parent),
		ZIndex = 50,
	}, parent)
	if class == "TextButton" then
		Holder.AutoButtonColor = false
		Holder.Text = ""
	end
	Corner(Holder, 10)
	Gradient(Holder, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 212)), 0)
	local S = Stroke(Holder, COLOR.innerBorder, 1.5, 0)
	local Accent = New("Frame", {
		Visible = false,
		Position = UDim2.new(0, 8, 0, 6),
		Size = UDim2.new(0, 3, 1, -12),
		BackgroundColor3 = COLOR.redBright,
		BorderSizePixel = 0,
		ZIndex = 55,
	}, Holder)
	Corner(Accent, 3)
	return Holder, S, Accent
end

local function Hover(obj, fn)
	track(obj.MouseEnter:Connect(function()
		fn(true)
	end))
	track(obj.MouseLeave:Connect(function()
		fn(false)
	end))
end

local function Safe(fn, ...)
	if not fn then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[LUNAR Hub] callback error: " .. tostring(err))
	end
end

local function RowBase(parent, title, desc, icon, reserve, class)
	local h = 38
	local Holder, S, Accent = CardBase(parent, h, class)
	local rightPad = 18 + (reserve or 12)

	local Title = Txt(Holder, {
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(1, -rightPad, 0, h),
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 60,
	})

	return Holder, S, Accent, Title
end

local function Button(parent, text, callback, danger, desc, icon)
	local Btn, S, Accent, Title = RowBase(parent, text, desc, icon, 34, "TextButton")
	local function applySize()
		Btn.Size = UDim2.new(1, 0, 0, 38)
		Title.Size = UDim2.new(1, -52, 0, 38)
		Title.TextSize = 12
	end
	applySize()
	table.insert(Custom.Buttons, applySize)
	if danger then
		Title.TextColor3 = COLOR.bad
	end

	local Badge = MakeArrowBadge(Btn, {
		Size = 22,
		Z = 60,
		Position = UDim2.new(1, -24, 0.5, 0),
		Danger = danger,
		AccentIdle = true,
	})
	Badge.SetRotation(-90, true)

	local hover = false
	local function paint()
		Tween(Btn, 0.15, { BackgroundColor3 = hover and COLOR.innerBgHover or COLOR.innerBg })
		Tween(S, 0.15, {
			Color = danger and COLOR.bad or (hover and COLOR.innerBorderHover or COLOR.innerBorder),
			Thickness = hover and 1.8 or 1.5,
		})
		Badge.Paint(false, hover)
		Tween(Badge.Frame, 0.15, {
			Position = hover and UDim2.new(1, -21, 0.5, 0) or UDim2.new(1, -24, 0.5, 0),
		})
	end
	Hover(Btn, function(h)
		hover = h
		paint()
	end)
	OnTheme(paint)
	track(Btn.Activated:Connect(function()
		Badge.Press()
		task.spawn(Safe, callback)
	end))
	return Btn
end

local function Toggle(parent, text, enabled, callback, availableFn, desc, icon, key)
	local state = enabled == true
	local hover = false
	local Holder, HolderStroke = RowBase(parent, text, desc, icon, 100)

	local Note = Txt(Holder, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		Size = UDim2.fromOffset(64, 14),
		Text = (availableFn and not availableFn()) and Tr("Not Available") or "",
		TextSize = 9,
		TextColor3 = COLOR.bad,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 60,
	})

	Lang.OnChange(function()
		if Note.Text ~= "" then
			Note.Text = Tr("Not Available")
		end
	end)

	local Switch = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(38, 20),
		BackgroundColor3 = COLOR.switchOff,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 70,
	}, Holder)
	Corner(Switch, 10)
	local SwitchStroke = Stroke(Switch, COLOR.switchBorder, 1.4, 0)

	local Knob = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.fromRGB(215, 215, 220),
		BorderSizePixel = 0,
		ZIndex = 75,
	}, Switch)
	Corner(Knob, 7)

	local Hit = New("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 52,
	}, Holder)

	local function paint()
		Tween(Holder, 0.15, { BackgroundColor3 = (hover and not state) and COLOR.innerBgHover or COLOR.innerBg })
		Tween(HolderStroke, 0.18, {
			Color = state and COLOR.red or (hover and COLOR.redBright or COLOR.innerBorder),
			Thickness = (state or hover) and 1.7 or 1.5,
		})
		Tween(Switch, 0.18, { BackgroundColor3 = state and COLOR.red or COLOR.switchOff })
		Tween(SwitchStroke, 0.18, { Color = state and COLOR.redBright or COLOR.switchBorder })
		Tween(Knob, 0.18, {
			Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(215, 215, 220),
		})
	end

	local api = {}
	function api.Get()
		return state
	end
	function api.Set(value, silent)
		state = value == true
		paint()
		if not silent then
			task.spawn(Safe, callback, state)
		end
	end

	local function click()
		if availableFn and not availableFn() then
			Note.Text = Tr("Not Available")
			Notify("This function has no hook bound yet", false)
			return
		end
		api.Set(not state)
	end
	track(Hit.Activated:Connect(click))
	track(Switch.Activated:Connect(click))
	Hover(Holder, function(h)
		hover = h
		paint()
	end)
	OnTheme(paint)

	Register(text, "toggle", {
		Get = function()
			return state
		end,
		Set = function(v)
			if availableFn and not availableFn() then
				return
			end
			if state ~= (v == true) then
				api.Set(v == true)
			end
		end,
	}, key)

	return Holder, api
end

local function Slider(parent, text, min, max, default, decimals, onChange, releaseOnly, desc, icon, key)
	local TRACK_W = 84
	local Row, RowStroke = RowBase(parent, text, desc, icon, TRACK_W + 70)

	local ValueBox = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(14 + TRACK_W + 12), 0.5, 0),
		Size = UDim2.fromOffset(42, 22),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Row)
	Corner(ValueBox, 7)
	local ValueStroke = Stroke(ValueBox, COLOR.innerBorder, 1.2, 0.1)
	local ValueLabel = New("TextBox", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLOR.redSoft,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
	}, ValueBox)

	local Track = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(TRACK_W, 5),
		BackgroundColor3 = COLOR.switchOff,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Row)
	Corner(Track, 3)
	local Fill = New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLOR.red,
		BorderSizePixel = 0,
		ZIndex = 61,
	}, Track)
	Corner(Fill, 3)
	local Knob = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 65,
	}, Track)
	Corner(Knob, 7)
	local KnobStroke = Stroke(Knob, COLOR.red, 2, 0)

	local Hit = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(TRACK_W + 16, 34),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 70,
	}, Row)

	OnTheme(function()
		ValueLabel.TextColor3 = COLOR.redSoft
		ValueBox.BackgroundColor3 = COLOR.black
		ValueStroke.Color = COLOR.innerBorder
		Fill.BackgroundColor3 = COLOR.red
		KnobStroke.Color = COLOR.red
		RowStroke.Color = COLOR.innerBorder
		Row.BackgroundColor3 = COLOR.innerBg
	end)

	local value = default
	local pow = 10 ^ decimals
	local function setValue(v, silent)
		v = math.clamp(v, min, max)
		v = math.floor(v * pow + 0.5) / pow
		value = v
		local a = (v - min) / (max - min)
		Fill.Size = UDim2.fromScale(a, 1)
		Knob.Position = UDim2.fromScale(a, 0.5)
		if not ValueLabel:IsFocused() then
			ValueLabel.Text = string.format("%." .. decimals .. "f", v)
		end
		if not silent and not releaseOnly then
			task.spawn(Safe, onChange, v)
		end
	end
	setValue(default, true)

	track(ValueLabel.Focused:Connect(function()
		Tween(ValueStroke, 0.15, { Color = COLOR.redBright, Thickness = 1.8, Transparency = 0 })
		Tween(ValueBox, 0.15, { BackgroundColor3 = Color3.fromRGB(28, 28, 36) })
		ValueLabel.TextColor3 = COLOR.white
		ValueLabel.Text = tostring(value)
	end))
	track(ValueLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = (ValueLabel.Text:gsub("[^%d%.%-]", ""))
		if clean ~= ValueLabel.Text then
			ValueLabel.Text = clean
		end
	end))
	track(ValueLabel.FocusLost:Connect(function()
		Tween(ValueStroke, 0.15, { Color = COLOR.innerBorder, Thickness = 1.2, Transparency = 0.1 })
		Tween(ValueBox, 0.15, { BackgroundColor3 = COLOR.black })
		ValueLabel.TextColor3 = COLOR.redSoft
		local n = tonumber(ValueLabel.Text)
		if n then
			setValue(n, true)
			task.spawn(Safe, onChange, value)
		else
			setValue(value, true)
		end
	end))

	local dragging, dragInput = false, nil
	local function fromX(x)
		local w = Track.AbsoluteSize.X
		if w <= 0 then
			return
		end
		setValue(min + (max - min) * math.clamp((x - Track.AbsolutePosition.X) / w, 0, 1))
	end

	track(Hit.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			if dragging or not Interaction.Begin(Hit) then
				return
			end
			dragging = true
			dragInput = input
			fromX(input.Position.X)
		end
	end))
	track(UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == dragInput) then
			fromX(input.Position.X)
		end
	end))
	track(UIS.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == dragInput) then
			dragging = false
			dragInput = nil
			Interaction.End(Hit)
			if releaseOnly then
				task.spawn(Safe, onChange, value)
			end
		end
	end))

	local api = {
		Set = setValue,
		Get = function()
			return value
		end,
	}

	Register(text, "slider", {
		Get = function()
			return value
		end,
		Set = function(v)
			if type(v) == "number" and v ~= value then
				setValue(v, true)
				task.spawn(Safe, onChange, value)
			end
		end,
	}, key)

	return api
end

local function Dropdown(parent, text, opts)
	opts = opts or {}
	local multi = opts.Multi == true
	local open, hover = false, false
	local selected = multi and {} or nil
	local PILL_W = 124

	local Wrap = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = ord(parent),
	}, parent)
	New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Wrap)

	local Head, HeadStroke = RowBase(Wrap, text, opts.Desc, opts.Icon, PILL_W + 28, "TextButton")

	local Pill = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(PILL_W, 26),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Head)
	Corner(Pill, 8)
	local PillStroke = Stroke(Pill, COLOR.innerBorder, 1.2, 0.1)

	local ValueLabel = Txt(Pill, {
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
	})

	local Badge = MakeArrowBadge(Pill, {
		Size = 18,
		Z = 62,
		Position = UDim2.new(1, -15, 0.5, 0),
	})

	local function available()
		return not opts.Available or opts.Available()
	end

	local function optionList()
		local src = opts.Options
		if type(src) == "function" then
			local ok, r = pcall(src)
			src = ok and r or {}
		end
		local out = {}
		if type(src) == "table" then
			for _, v in ipairs(src) do
				table.insert(out, typeof(v) == "Instance" and v.Name or tostring(v))
			end
		end
		return out
	end

	local function isSel(name)
		if multi then
			return selected[name] == true
		end
		return selected == name
	end

	local function get()
		if multi then
			local arr = {}
			for k in pairs(selected) do
				table.insert(arr, k)
			end
			table.sort(arr)
			return arr
		end
		return selected
	end

	local function summary()
		if not available() then
			return "Not Available"
		end
		if multi then
			local n, names = 0, {}
			for k in pairs(selected) do
				n += 1
				table.insert(names, Tr(k))
			end
			table.sort(names)
			if n == 0 then
				return opts.Placeholder or "None"
			elseif n <= 2 then
				return table.concat(names, ", ")
			end
			return TrF("%d selected", n)
		end
		return selected or opts.Placeholder or "Select..."
	end

	local function paint()
		Tween(Head, 0.15, { BackgroundColor3 = (hover or open) and COLOR.innerBgHover or COLOR.innerBg })
		Tween(HeadStroke, 0.15, {
			Color = open and COLOR.red or (hover and COLOR.innerBorderHover or COLOR.innerBorder),
			Thickness = (open or hover) and 1.7 or 1.5,
		})
		Tween(PillStroke, 0.15, { Color = open and COLOR.redBright or COLOR.innerBorder })
		Badge.SetRotation(open and 180 or 0)
		Badge.Paint(open, hover)
		ValueLabel.Text = Tr(summary())
		ValueLabel.TextColor3 = (not available()) and COLOR.bad or COLOR.white
		Pill.BackgroundColor3 = COLOR.black
	end

	local api = {}

	Lang.OnChange(paint)

	local function fire()
		task.spawn(Safe, opts.OnChange, get())
	end

	function api.Get()
		return get()
	end

	function api.Set(value, silent)
		if multi then
			selected = {}
			if type(value) == "table" then
				for _, v in ipairs(value) do
					selected[tostring(v)] = true
				end
			end
		else
			selected = value ~= nil and tostring(value) or nil
		end
		paint()
		if not silent then
			fire()
		end
	end

	function api.Refresh()
		paint()
	end

	if opts.Default ~= nil then
		api.Set(opts.Default, true)
	end

	track(Head.Activated:Connect(function()
		if not available() then
			Notify("This option has no hook bound yet", false)
			return
		end
		Badge.Press()
		if open then
			Picker.Close()
			return
		end
		local items = {}
		for _, name in ipairs(optionList()) do
			table.insert(items, { Name = name })
		end
		open = true
		paint()
		Picker.Open({
			Title = Tr(text),
			Multi = multi,
			Items = items,
			IsSelected = isSel,
			Subtitle = function()
				if multi then
					local n = 0
					for _ in pairs(selected) do
						n += 1
					end
					return TrF("%d items selected", n)
				end
				return Tr("Select 1 option")
			end,
			OnSelect = function(name)
				if multi then
					selected[name] = (not selected[name]) or nil
				else
					selected = name
				end
				paint()
				fire()
			end,
			OnClear = multi and function()
				selected = {}
				paint()
				fire()
			end or nil,
			OnClose = function()
				open = false
				paint()
			end,
		})
	end))
	Hover(Head, function(h)
		hover = h
		paint()
	end)
	OnTheme(paint)

	Register(text, "dropdown", {
		Get = function()
			if multi then
				return get()
			end
			return selected or ""
		end,
		Set = function(v)
			if not available() then
				return
			end
			if multi then
				if type(v) ~= "table" then
					return
				end
				local want = {}
				for _, x in ipairs(v) do
					table.insert(want, tostring(x))
				end
				table.sort(want)
				if table.concat(get(), "\n") ~= table.concat(want, "\n") then
					api.Set(want)
				end
			else
				local nv = (v ~= nil and v ~= "") and tostring(v) or nil
				if selected ~= nv then
					api.Set(nv)
				end
			end
		end,
	}, opts.Key)

	return Wrap, api
end

local function TextInput(parent, text, opts)
	opts = opts or {}
	local PILL_W = 150
	local Holder = RowBase(parent, text, opts.Desc, nil, PILL_W + 28)

	local Pill = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(PILL_W, 26),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Holder)
	Corner(Pill, 8)
	local PillStroke = Stroke(Pill, COLOR.innerBorder, 1.2, 0.1)

	local Box = New("TextBox", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = opts.Placeholder or "",
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = COLOR.white,
		PlaceholderColor3 = COLOR.grey,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	}, Pill)
	Lang.Bind(Box, "PlaceholderText", opts.Placeholder)

	track(Box.Focused:Connect(function()
		Tween(PillStroke, 0.15, { Color = COLOR.redBright, Thickness = 1.8 })
	end))
	track(Box.FocusLost:Connect(function()
		Tween(PillStroke, 0.15, { Color = COLOR.innerBorder, Thickness = 1.2 })
	end))
	OnTheme(function()
		Pill.BackgroundColor3 = COLOR.black
		PillStroke.Color = COLOR.innerBorder
	end)

	return Holder, {
		Get = function()
			return Box.Text
		end,
		Set = function(t)
			Box.Text = t or ""
		end,
	}
end

local function ResolveImage(img)
	if img == nil then
		return nil
	end
	local str = tostring(img)
	if str == "" then
		return nil
	end
	if str:match("^%d+$") then
		return "rbxassetid://" .. str
	end
	return str
end

local function FirstChar(text)
	local ok, nextPos = pcall(utf8.offset, text, 2)
	if ok and nextPos then
		return string.sub(text, 1, nextPos - 1)
	end
	return string.sub(text, 1, 1)
end

local function NormalizeItems(src)
	if type(src) == "function" then
		local ok, r = pcall(src)
		src = ok and r or {}
	end
	local out = {}
	if type(src) == "table" then
		for _, v in ipairs(src) do
			if type(v) == "table" then
				table.insert(out, {
					Name = tostring(v.Name or v[1] or "?"),
					Image = v.Image or v.Icon,
					Desc = v.Desc,
				})
			else
				table.insert(out, { Name = typeof(v) == "Instance" and v.Name or tostring(v) })
			end
		end
	end
	return out
end

local function ItemIcon(parent, item, size, z)
	local hue = 0
	for i = 1, #item.Name do
		hue = (hue * 31 + string.byte(item.Name, i)) % 360
	end
	local radius = math.floor(size * 0.28)
	local Box = New("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromHSV(hue / 360, 0.5, 0.55),
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Corner(Box, radius)
	local img = ResolveImage(item.Image)
	if img then
		local pic = New("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = img,
			ScaleType = Enum.ScaleType.Crop,
			BorderSizePixel = 0,
			ZIndex = z + 1,
		}, Box)
		Corner(pic, radius)
	else
		Txt(Box, {
			Size = UDim2.fromScale(1, 1),
			Text = string.upper(FirstChar(item.Name)),
			Font = Enum.Font.GothamBold,
			TextSize = math.max(10, math.floor(size * 0.5)),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
		})
	end
	return Box
end

do
	local Overlay, Backdrop, Window, WinGrad, WinStroke, WinStrokeGrad
	local TitleLbl, SubLbl, CloseBtn, SearchBar, SearchBox, List, Empty
	local Footer, ClearBtn, DoneBtn
	local current, rows = nil, {}
	local isOpen, closeToken = false, 0

	local function clearRows()
		for _, r in ipairs(rows) do
			r.Btn:Destroy()
		end
		table.clear(rows)
	end

	local function updateSub()
		SubLbl.Text = (current and current.Subtitle) and current.Subtitle() or ""
	end

	local function repaintRows()
		for _, r in ipairs(rows) do
			r.Paint()
		end
	end

	local function applyFilter()
		local q = string.lower(SearchBox.Text or "")
		for _, r in ipairs(rows) do
			r.Btn.Visible = q == "" or string.find(string.lower(r.Name), q, 1, true) ~= nil
		end
	end

	local function footerButton(text, order, accent)
		local B = New("TextButton", {
			Size = UDim2.new(accent and 0.58 or 0.38, -4, 1, 0),
			BackgroundColor3 = accent and COLOR.red or COLOR.innerBg,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = Color3.new(1, 1, 1),
			LayoutOrder = order,
			ZIndex = 530,
		}, Footer)
		Corner(B, 9)
		Lang.Bind(B, "Text", text)
		return B, Stroke(B, accent and COLOR.redBright or COLOR.innerBorder, 1.2, 0.2)
	end

	local doneStroke, clearStroke

	local function build()
		if Overlay then
			return
		end
		Overlay = New("Frame", {
			Name = "PickerOverlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 500,
		}, Gui)

		Backdrop = New("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 501,
		}, Overlay)

		Window = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(340, 360),
			BackgroundColor3 = COLOR.black,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 510,
		}, Overlay)
		Corner(Window, 16)
		WinGrad = Gradient(Window, ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLOR.black2),
			ColorSequenceKeypoint.new(1, COLOR.black),
		}), 65)
		WinStroke = Stroke(Window, Color3.new(1, 1, 1), 2, 0)
		WinStrokeGrad = Gradient(WinStroke, NeonSequence, 45)

		TitleLbl = Txt(Window, {
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(1, -64, 0, 20),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 520,
		})
		SubLbl = Txt(Window, {
			Position = UDim2.fromOffset(16, 30),
			Size = UDim2.new(1, -64, 0, 14),
			TextSize = 10,
			TextColor3 = COLOR.grey,
			ZIndex = 520,
		})

		CloseBtn = New("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Color3.fromRGB(24, 19, 23),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "×",
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = COLOR.grey,
			ZIndex = 530,
		}, Window)
		Corner(CloseBtn, 8)
		Stroke(CloseBtn, COLOR.border, 1, 0.1)

		SearchBar = New("Frame", {
			Position = UDim2.fromOffset(12, 54),
			Size = UDim2.new(1, -24, 0, 32),
			BackgroundColor3 = COLOR.innerBg,
			BorderSizePixel = 0,
			ZIndex = 520,
		}, Window)
		Corner(SearchBar, 9)
		Stroke(SearchBar, COLOR.innerBorder, 1.2, 0.1)
		SearchBox = New("TextBox", {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			PlaceholderText = "Search...",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = COLOR.white,
			PlaceholderColor3 = COLOR.grey,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 524,
		}, SearchBar)

		List = New("ScrollingFrame", {
			Position = UDim2.fromOffset(12, 54),
			Size = UDim2.new(1, -24, 1, -60),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = COLOR.redBright,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 520,
		}, Window)
		New("UIPadding", { PaddingRight = UDim.new(0, 6) }, List)
		New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, List)
		Interaction.WatchScroll(List)

		Empty = Txt(Window, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -32, 0, 24),
			Text = "No options",
			TextColor3 = COLOR.grey,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			ZIndex = 520,
		})

		Footer = New("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -10),
			Size = UDim2.new(1, -24, 0, 34),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 520,
		}, Window)
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, Footer)
		ClearBtn, clearStroke = footerButton("Clear all", 1, false)
		DoneBtn, doneStroke = footerButton("Done", 2, true)

		track(Backdrop.Activated:Connect(function()
			Picker.Close()
		end))
		track(CloseBtn.Activated:Connect(function()
			Picker.Close()
		end))
		track(DoneBtn.Activated:Connect(function()
			Picker.Close()
		end))
		track(ClearBtn.Activated:Connect(function()
			if current and current.OnClear then
				Safe(current.OnClear)
				repaintRows()
				updateSub()
			end
		end))
		track(SearchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter))
		track(UIS.InputBegan:Connect(function(input)
			if isOpen and input.KeyCode == Enum.KeyCode.Escape then
				Picker.Close()
			end
		end))

		OnTheme(function()
			Window.BackgroundColor3 = COLOR.black
			WinGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLOR.black2),
				ColorSequenceKeypoint.new(1, COLOR.black),
			})
			WinStroke.Color = Color3.new(1, 1, 1)
			WinStrokeGrad.Color = NeonSequence
			List.ScrollBarImageColor3 = COLOR.redBright
			DoneBtn.BackgroundColor3 = COLOR.red
			doneStroke.Color = COLOR.redBright
			ClearBtn.BackgroundColor3 = COLOR.innerBg
			clearStroke.Color = COLOR.innerBorder
		end)
	end

	local function addRow(i, item, cfg, rowH, rich)
		local Btn = New("TextButton", {
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundColor3 = COLOR.innerBgHover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			ZIndex = 522,
		}, List)
		Corner(Btn, 10)

		local Label, Box
		if rich then
			local Ico = ItemIcon(Btn, item, 32, 524)
			Ico.Position = UDim2.new(0, 8, 0.5, -16)
			local hasDesc = item.Desc ~= nil and item.Desc ~= ""
			Label = Txt(Btn, {
				Position = UDim2.new(0, 50, 0, hasDesc and 7 or 0),
				Size = UDim2.new(1, -92, 0, hasDesc and 16 or rowH),
				Text = Tr(item.Name),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 524,
			})
			if hasDesc then
				Txt(Btn, {
					Position = UDim2.new(0, 50, 0, 23),
					Size = UDim2.new(1, -92, 0, 14),
					Text = Tr(item.Desc),
					TextSize = 10,
					TextColor3 = COLOR.grey,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 524,
				})
			end
			Box = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = COLOR.switchOff,
				BorderSizePixel = 0,
				ZIndex = 524,
			}, Btn)
			Corner(Box, 8)
		else
			Box = New("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = COLOR.switchOff,
				BorderSizePixel = 0,
				ZIndex = 524,
			}, Btn)
			Corner(Box, cfg.Multi and 5 or 8)
			Label = Txt(Btn, {
				Position = UDim2.new(0, 34, 0, 0),
				Size = UDim2.new(1, -42, 1, 0),
				Text = Tr(item.Name),
				Font = Enum.Font.GothamMedium,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 524,
			})
		end
		local BoxStroke = Stroke(Box, COLOR.switchBorder, 1.4, 0)
		local Mark = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 526,
		}, Box)
		Corner(Mark, 3)

		local hovered = false
		local row = { Btn = Btn, Name = item.Name }
		function row.Paint()
			local sel = cfg.IsSelected(item.Name)
			Btn.BackgroundTransparency = sel and 0.55 or (hovered and 0.7 or 1)
			Box.BackgroundColor3 = sel and COLOR.red or COLOR.switchOff
			BoxStroke.Color = sel and COLOR.redBright or COLOR.switchBorder
			Mark.BackgroundTransparency = sel and 0 or 1
			Label.TextColor3 = sel and COLOR.white or COLOR.grey
		end
		row.Paint()

		Btn.MouseEnter:Connect(function()
			hovered = true
			row.Paint()
		end)
		Btn.MouseLeave:Connect(function()
			hovered = false
			row.Paint()
		end)
		Btn.Activated:Connect(function()
			if current ~= cfg then
				return
			end
			Safe(cfg.OnSelect, item.Name)
			if cfg.Multi then
				repaintRows()
				updateSub()
			else
				Picker.Close()
			end
		end)

		table.insert(rows, row)
	end

	function Picker.IsOpen()
		return isOpen
	end

	function Picker.Open(cfg)
		build()
		if isOpen then
			local old = current
			isOpen = false
			current = nil
			if old and old.OnClose then
				Safe(old.OnClose)
			end
		end
		closeToken += 1
		clearRows()
		current, isOpen = cfg, true

		local items = cfg.Items or {}
		local multi, rich = cfg.Multi == true, cfg.Rich == true
		local showSearch = #items > 7

		local vp = Viewport()
		local W = math.clamp(vp.X - 32, 240, rich and 400 or 360)
		local rowH = rich and 44 or 34
		local top = 54 + (showSearch and 40 or 0)
		local foot = multi and 52 or 0
		local want = top + math.max(#items, 1) * (rowH + 4) + 8 + foot
		local H = math.clamp(want, 150, math.max(150, math.min(vp.Y - 40, 460)))

		SearchBar.Visible = showSearch
		Footer.Visible = multi
		List.Position = UDim2.fromOffset(12, top)
		List.Size = UDim2.new(1, -24, 1, -(top + foot + 6))
		List.CanvasPosition = Vector2.new(0, 0)
		TitleLbl.Text = Tr(cfg.Title or "")
		SearchBox.Text = ""
		SearchBox.PlaceholderText = Tr("Search...")

		for i, item in ipairs(items) do
			addRow(i, item, cfg, rowH, rich)
		end
		Empty.Visible = #items == 0
		updateSub()

		Overlay.Visible = true
		Backdrop.BackgroundTransparency = 1
		Tween(Backdrop, 0.18, { BackgroundTransparency = 0.45 })
		Window.Size = UDim2.fromOffset(W - 24, H - 24)
		Tween(Window, 0.22, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
	end

	function Picker.Close()
		if not isOpen then
			return
		end
		isOpen = false
		local cfg = current
		current = nil
		closeToken += 1
		local token = closeToken
		Tween(Backdrop, 0.12, { BackgroundTransparency = 1 })
		task.delay(0.13, function()
			if token == closeToken and not isOpen and Overlay then
				Overlay.Visible = false
				clearRows()
			end
		end)
		if cfg and cfg.OnClose then
			Safe(cfg.OnClose)
		end
	end
end

local function ImageBox(parent, text, opts)
	opts = opts or {}
	local open, hover = false, false
	local selected = nil
	local items = NormalizeItems(opts.Options)
	local pillShown = nil
	local PILL_W = 150

	local Wrap = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = ord(parent),
	}, parent)
	New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Wrap)

	local Head, HeadStroke = RowBase(Wrap, text, opts.Desc, opts.Icon, PILL_W + 28, "TextButton")

	local Pill = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(PILL_W, 30),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Head)
	Corner(Pill, 8)
	local PillStroke = Stroke(Pill, COLOR.innerBorder, 1.2, 0.1)

	local PillIcon = New("Frame", {
		Position = UDim2.new(0, 5, 0.5, -11),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 61,
	}, Pill)

	local ValueLabel = Txt(Pill, {
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
	})

	local Badge = MakeArrowBadge(Pill, {
		Size = 18,
		Z = 62,
		Position = UDim2.new(1, -15, 0.5, 0),
	})

	local api = {}

	local function available()
		return not opts.Available or opts.Available()
	end

	local function currentItem()
		for _, it in ipairs(items) do
			if it.Name == selected then
				return it
			end
		end
		return nil
	end

	local function paintPill()
		local it = currentItem()
		local shown = it and it.Name or nil
		if shown ~= pillShown then
			pillShown = shown
			PillIcon:ClearAllChildren()
			if it then
				ItemIcon(PillIcon, it, 22, 62)
			end
		end
		PillIcon.Visible = it ~= nil
		local x = it and 33 or 10
		ValueLabel.Position = UDim2.new(0, x, 0, 0)
		ValueLabel.Size = UDim2.new(1, -(x + 24), 1, 0)
		if not available() then
			ValueLabel.Text = Tr("Not Available")
			ValueLabel.TextColor3 = COLOR.bad
		elseif selected then
			ValueLabel.Text = Tr(selected)
			ValueLabel.TextColor3 = COLOR.white
		else
			ValueLabel.Text = Tr(opts.Placeholder or "Select...")
			ValueLabel.TextColor3 = COLOR.grey
		end
	end

	local function paint()
		Tween(Head, 0.15, { BackgroundColor3 = (hover or open) and COLOR.innerBgHover or COLOR.innerBg })
		Tween(HeadStroke, 0.15, {
			Color = open and COLOR.red or (hover and COLOR.innerBorderHover or COLOR.innerBorder),
			Thickness = (open or hover) and 1.7 or 1.5,
		})
		Tween(PillStroke, 0.15, { Color = open and COLOR.redBright or COLOR.innerBorder })
		Badge.SetRotation(open and 180 or 0)
		Badge.Paint(open, hover)
		Pill.BackgroundColor3 = COLOR.black
		paintPill()
	end

	Lang.OnChange(paint)

	local function fire()
		task.spawn(Safe, opts.OnChange, selected, currentItem())
	end

	function api.Get()
		return selected
	end

	function api.GetItem()
		return currentItem()
	end

	function api.Set(value, silent)
		if type(value) == "number" and items[value] then
			selected = items[value].Name
		elseif value ~= nil then
			selected = tostring(value)
		else
			selected = nil
		end
		paint()
		if not silent then
			fire()
		end
	end

	function api.SetOptions(list)
		opts.Options = list
		items = NormalizeItems(list)
		if selected and not currentItem() then
			selected = nil
		end
		paint()
	end

	function api.Refresh()
		items = NormalizeItems(opts.Options)
		paint()
	end

	if opts.Default ~= nil then
		api.Set(opts.Default, true)
	else
		paint()
	end

	track(Head.Activated:Connect(function()
		if not available() then
			Notify("This option has no hook bound yet", false)
			return
		end
		Badge.Press()
		if open then
			Picker.Close()
			return
		end
		items = NormalizeItems(opts.Options)
		open = true
		paint()
		Picker.Open({
			Title = Tr(text),
			Rich = true,
			Items = items,
			IsSelected = function(name)
				return selected == name
			end,
			Subtitle = function()
				return selected and TrF("Selected: %s", Tr(selected)) or Tr("Select 1 item")
			end,
			OnSelect = function(name)
				selected = name
				paint()
				fire()
			end,
			OnClose = function()
				open = false
				paint()
			end,
		})
	end))
	Hover(Head, function(h)
		hover = h
		paint()
	end)
	OnTheme(paint)

	Register(text, "imagebox", {
		Get = function()
			return selected or ""
		end,
		Set = function(v)
			if not available() then
				return
			end
			local nv = (v ~= nil and v ~= "") and tostring(v) or nil
			if selected ~= nv then
				api.Set(nv)
			end
		end,
	}, opts.Key)

	return Wrap, api
end

local function StatRow(holder, label)
	local Row = New("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, holder)
	local Dot = New("Frame", {
		Position = UDim2.new(0, 2, 0.5, -3),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = COLOR.redBright,
		BorderSizePixel = 0,
	}, Row)
	Corner(Dot, 6)
	OnTheme(function()
		Dot.BackgroundColor3 = COLOR.redBright
	end)
	Txt(Row, {
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(0.4, -16, 1, 0),
		Text = label,
		TextColor3 = COLOR.grey,
	})
	return Txt(Row, {
		Position = UDim2.new(0.4, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

local rainbowGen = 0

function Actions.ApplyColor(c)
	DeriveTheme(c)
	for _, fn in ipairs(ThemeListeners) do
		pcall(fn)
	end
end

function Actions.SetRainbow(on, silent)
	rainbowGen += 1
	Settings.Rainbow = on
	if on and Settings.Multi then
		Settings.Multi = false
		if Actions.OnMulti then
			Actions.OnMulti(false)
		end
	end
	if on then
		local gen = rainbowGen
		task.spawn(function()
			local h = Color3.toHSV(HexToColor3(Settings.ThemeColor) or COLOR.red)
			while not destroyed and Settings.Rainbow and gen == rainbowGen do
				local every = GetPerf().rainbowEvery
				h = (h + 0.04 * (Settings.RainbowSpeed or 1) * every) % 1

				if Root.Visible then
					Actions.ApplyColor(Color3.fromHSV(h, 0.7, 1))
				end
				task.wait(every)
			end
		end)
	else
		Actions.ApplyColor(HexToColor3(Settings.ThemeColor) or COLOR.red)
	end
	if Actions.OnRainbow then
		Actions.OnRainbow(on)
	end
	if not silent then
		saveSettings()
	end
end

function Actions.SetThemeColor(c, silent)
	Settings.ThemeColor = Color3ToHex(c)
	if Settings.Rainbow then
		Actions.SetRainbow(false, true)
	end
	Actions.ApplyColor(c)
	if not silent then
		saveSettings()
	end
end

function Actions.RefreshNeon()
	if Settings.Rainbow then
		return
	end
	Actions.ApplyColor(HexToColor3(Settings.ThemeColor) or COLOR.red)
end

function Actions.SetMulti(on, silent)
	Settings.Multi = on
	if on and Settings.Rainbow then
		Actions.SetRainbow(false, true)
	end
	Actions.RefreshNeon()
	if Actions.OnMulti then
		Actions.OnMulti(on)
	end
	if not silent then
		saveSettings()
	end
end

function Actions.SetNeonSlot(i, c)
	Settings.NeonColors[i] = Color3ToHex(c)
	if not Settings.Multi then
		Actions.SetMulti(true, true)
	else
		Actions.RefreshNeon()
	end
	if Actions.OnNeonChanged then
		Actions.OnNeonChanged()
	end
	saveSettings()
end

local Telemetry = { Listeners = {}, Conn = nil, Frames = 0, Acc = 0 }

function Telemetry.Add(fn, isActive)
	table.insert(Telemetry.Listeners, { Fn = fn, Active = isActive })
end

local function telemetryNeeded()
	for _, l in ipairs(Telemetry.Listeners) do
		local ok, active = pcall(l.Active)
		if ok and active then
			return true
		end
	end
	return false
end

function Telemetry.Poke()
	if not Telemetry.Conn and telemetryNeeded() then
		Telemetry.Frames, Telemetry.Acc = 0, 0
		Telemetry.Conn = RunService.Heartbeat:Connect(function(dt)
			Telemetry.Frames += 1
			Telemetry.Acc += dt
		end)
	end
end

addCleanup(function()
	if Telemetry.Conn then
		Telemetry.Conn:Disconnect()
		Telemetry.Conn = nil
	end
end)

task.spawn(function()
	while not destroyed do
		task.wait(1)
		if telemetryNeeded() then
			if not Telemetry.Conn then
				Telemetry.Poke()
			elseif Telemetry.Acc > 0 then
				local fps = math.floor(Telemetry.Frames / Telemetry.Acc + 0.5)
				Telemetry.Frames, Telemetry.Acc = 0, 0
				local ok, ping = pcall(function()
					return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
				end)
				ping = (ok and ping) and math.floor(ping) or nil
				for _, l in ipairs(Telemetry.Listeners) do
					local okActive, active = pcall(l.Active)
					if okActive and active then
						pcall(l.Fn, fps, ping)
					end
				end
			end
		elseif Telemetry.Conn then
			Telemetry.Conn:Disconnect()
			Telemetry.Conn = nil
		end
	end
end)

local AntiAfk = { Job = 0, Warned = false }

local function antiAfkPulse()
	local ok, err = pcall(function()
		local vu = game:GetService("VirtualUser")
		vu:CaptureController()
		vu:ClickButton2(Vector2.new())
	end)
	if not ok and not AntiAfk.Warned then
		AntiAfk.Warned = true
		warn("[LUNAR Hub] Anti AFK failed, your executor may block VirtualUser: " .. tostring(err))
	end
	return ok
end

function Actions.SetAntiAfk(on)
	if AntiAfk.Conn then
		pcall(function()
			AntiAfk.Conn:Disconnect()
		end)
		AntiAfk.Conn = nil
	end
	AntiAfk.Job += 1
	if not on then
		return
	end
	-- Immediate reactive hook (fires on Roblox's own ~20 min idle timer)
	AntiAfk.Conn = LocalPlayer.Idled:Connect(antiAfkPulse)
	-- Proactive heartbeat so it doesn't rely only on Idled firing / doesn't need a 20 min wait to confirm it works
	local job = AntiAfk.Job
	task.spawn(function()
		while AntiAfk.Job == job do
			task.wait(90)
			if AntiAfk.Job ~= job then
				break
			end
			antiAfkPulse()
		end
	end)
end

local CARD_SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 212))

do
	local Page = CreatePage("Overview")
	CreateTab("Overview", "11761637751")


	local Card = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		LayoutOrder = ord(Page),
		ZIndex = 50,
	}, Page)
	Corner(Card, 14)
	Gradient(Card, CARD_SHADE, 0)
	local CardStroke = Stroke(Card, Color3.new(1, 1, 1), 1.6, 0.15)
	local CardStrokeGrad = Gradient(CardStroke, NeonSequence, 0)
	Spin(CardStrokeGrad, 9, 2, Page)

	New("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
	}, Card)
	New("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Card)

	local HeaderRow = New("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, Card)

	local Avatar = New("ImageLabel", {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 55,
	}, HeaderRow)
	Corner(Avatar, 32)
	local AvatarStroke = Stroke(Avatar, Color3.new(1, 1, 1), 2.2, 0)
	local AvatarGrad = Gradient(AvatarStroke, NeonSequence, 0)
	Spin(AvatarGrad, 6, 2, Page)

	Txt(HeaderRow, {
		Position = UDim2.new(0, 78, 0, 2),
		Size = UDim2.new(1, -160, 0, 22),
		Text = LocalPlayer.DisplayName,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 55,
	})
	Txt(HeaderRow, {
		Position = UDim2.new(0, 78, 0, 25),
		Size = UDim2.new(1, -160, 0, 16),
		Text = "@" .. LocalPlayer.Name,
		TextColor3 = COLOR.grey,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 55,
	})
	local AgeLabel = Txt(HeaderRow, {
		Position = UDim2.new(0, 78, 0, 45),
		Size = UDim2.new(1, -160, 0, 14),
		Text = TrF("Account Age: %d days", LocalPlayer.AccountAge),
		TextSize = 10,
		TextColor3 = COLOR.grey,
		ZIndex = 55,
	})
	Lang.OnChange(function()
		AgeLabel.Text = TrF("Account Age: %d days", LocalPlayer.AccountAge)
	end)

	local Badge = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(78, 22),
		BackgroundColor3 = Color3.fromRGB(15, 35, 20),
		BorderSizePixel = 0,
		ZIndex = 55,
	}, HeaderRow)
	Corner(Badge, 11)
	Stroke(Badge, Color3.fromRGB(60, 160, 80), 1, 0.2)
	local BadgeInner = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 58,
	}, Badge)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, BadgeInner)
	local BadgeDot = New("Frame", {
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = COLOR.good,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		ZIndex = 60,
	}, BadgeInner)
	Corner(BadgeDot, 6)
	Txt(BadgeInner, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Text = "ONLINE",
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = COLOR.good,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = 60,
	})

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				LocalPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size180x180
			)
		end)
		if ok and Avatar.Parent then
			Avatar.Image = content
		end
	end)

	local Tiles = New("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, Card)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Tiles)

	local function Tile(label, order)
		local T = New("Frame", {
			Size = UDim2.new(1 / 3, -6, 1, 0),
			BackgroundColor3 = COLOR.innerBg,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ZIndex = 55,
		}, Tiles)
		Corner(T, 10)
		Gradient(T, CARD_SHADE, 90)
		local S = Stroke(T, COLOR.innerBorder, 1.2, 0.1)
		local Bar = New("Frame", {
			Visible = false,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(22, 2),
			BackgroundColor3 = COLOR.red,
			BorderSizePixel = 0,
			ZIndex = 60,
		}, T)
		Corner(Bar, 2)
		local V = Txt(T, {
			Position = UDim2.new(0, 0, 0, 9),
			Size = UDim2.new(1, 0, 0, 24),
			Text = "-",
			Font = Enum.Font.GothamBold,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 60,
		})
		Txt(T, {
			Position = UDim2.new(0, 0, 0, 33),
			Size = UDim2.new(1, 0, 0, 14),
			Text = string.upper(label),
			Font = Enum.Font.GothamMedium,
			TextSize = 9,
			TextColor3 = COLOR.grey,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 60,
		})
		OnTheme(function()
			T.BackgroundColor3 = COLOR.innerBg
			S.Color = COLOR.innerBorder
			Bar.BackgroundColor3 = COLOR.red
			V.TextColor3 = COLOR.redSoft
		end)
		return V
	end

	local PlayersValue = Tile("Players", 1)
	local PingValue = Tile("Ping", 2)
	local FpsValue = Tile("FPS", 3)

	local Divider = New("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = COLOR.border,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		LayoutOrder = 3,
	}, Card)

	local StatsHolder = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
	}, Card)
	New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, StatsHolder)

	local GameValue = StatRow(StatsHolder, "Game")
	local PlaceValue = StatRow(StatsHolder, "Place ID")
	local ServerValue = StatRow(StatsHolder, "Server")

	GameValue.Text = Context.GameName or game.Name
	PlaceValue.Text = tostring(game.PlaceId)
	ServerValue.Text = (game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "Studio")

	if not Context.GameName then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(game.PlaceId)
			end)
			if ok and type(info) == "table" and info.Name and GameValue.Parent then
				GameValue.Text = info.Name
			end
		end)
	end

	OnTheme(function()
		CardStroke.Color = Color3.new(1, 1, 1)
		CardStrokeGrad.Color = NeonSequence
		AvatarStroke.Color = Color3.new(1, 1, 1)
		AvatarGrad.Color = NeonSequence
		Card.BackgroundColor3 = COLOR.innerBg
		Divider.BackgroundColor3 = COLOR.border
	end)

	local function updatePlayers()
		PlayersValue.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
	end
	updatePlayers()

	Telemetry.Add(function(fps, ping)
		FpsValue.Text = tostring(fps)
		PingValue.Text = ping and (ping .. "ms") or "N/A"
		updatePlayers()
	end, function()
		return Root.Visible and Page.Visible
	end)
end

local UI = {

	Lang = Lang, Config = Config, Assets = Assets, COLOR = COLOR, Gui = Gui,
	Settings = Settings, Actions = Actions, Context = Context,

	Tr = Tr, TrF = TrF, TrDyn = TrDyn, track = track, addCleanup = addCleanup,
	New = New, Corner = Corner, Stroke = Stroke, Txt = Txt, Tween = Tween, Hover = Hover,
	Notify = Notify, Safe = Safe, Register = Register,
	CollectConfig = CollectConfig, ApplyConfig = ApplyConfig,
	ExcludeFromConfig = function(pattern)
		table.insert(Context.ConfigExclude, pattern)
	end,

	CreatePage = CreatePage, CreateTab = CreateTab, Section = Section, CardBase = CardBase,
	Button = Button, Toggle = Toggle, Slider = Slider, Dropdown = Dropdown,
	TextInput = TextInput, ImageBox = ImageBox, StatRow = StatRow,
}

function UI.TextInputCb(parent, text, default, placeholder, callback, desc)
	local Holder, base = TextInput(parent, text, { Placeholder = placeholder, Desc = desc })
	local box = Holder:FindFirstChildWhichIsA("TextBox", true)
	local ctl = {}
	function ctl.Get()
		return base.Get()
	end
	function ctl.Set(v, silent)
		base.Set(v or "")
		if not silent then
			task.spawn(Safe, callback, base.Get())
		end
	end
	if box then
		track(box.FocusLost:Connect(function()
			task.spawn(Safe, callback, box.Text)
		end))
	end
	if default ~= nil and default ~= "" then
		base.Set(default)
	end
	Register(text, "textinput", {
		Get = ctl.Get,
		Set = function(v)
			ctl.Set(v)
		end,
	})
	return Holder, ctl
end

for index, system in ipairs(Context.Systems or {}) do
	if type(system) == "table" and type(system.Build) == "function" then
		local ok, err = pcall(system.Build, UI)
		if not ok then
			warn("[LUNAR Hub] System '" .. tostring(system.Name or system.Id or index) .. "' failed: " .. tostring(err))
		end
	end
end

do
	local Page = CreatePage("Settings")
	CreateTab("Settings", "7059346373")
	local ctl = {}
	local _

	Section(Page, "General")
	local langDrop
	_, langDrop = Dropdown(Page, "Language", {
		Options = { "ไทย", "English" },
		Default = Lang.Current == "en" and "English" or "ไทย",
		OnChange = function(v)
			local code = v == "English" and "en" or "th"
			Settings.Lang = code
			Lang.Set(code)
			saveSettings()
		end,
	})
	_, ctl.anim = Toggle(Page, "Animation", Settings.Animate, function(on)
		Settings.Animate = on
		saveSettings()
	end)
	_, ctl.pulse = Toggle(Page, "Premium Effects", Settings.Pulse, function(on)
		Actions.SetPulse(on)
		Settings.Pulse = on
		saveSettings()
	end)
	_, ctl.float = Toggle(Page, "Show Floating Button", Settings.ShowFloating, function(on)
		Settings.ShowFloating = on
		Actions.RefreshFloating()
		saveSettings()
	end)
	_, ctl.stars = Toggle(Page, "Shooting Stars", Settings.Stars, function(on)
		Actions.SetStars(on)
		saveSettings()
	end)
	local perfDrop
	_, perfDrop = Dropdown(Page, "Performance", {
		Options = { "High", "Balanced", "Low" },
		Default = Settings.Perf,
		OnChange = function(v)
			Actions.SetPerf(v)
		end,
	})
	_, ctl.afk = Toggle(Page, "Anti AFK", Settings.AntiAFK, function(on)
		Settings.AntiAFK = on
		Actions.SetAntiAfk(on)
		saveSettings()
	end)

	Section(Page, "Customize")
	ctl.bg = Slider(Page, "Background Opacity", 0, 100, Settings.BgOpacity, 0, function(v)
		Settings.BgOpacity = v
		BgImage.ImageTransparency = 1 - v / 100
		Custom.SaveSoon()
	end)

	Section(Page, "Monitor")
	_, ctl.monitor = Toggle(Page, "FPS / Ping Monitor", Settings.FloatMonitor, function(on)
		Actions.SetMonitor(on)
	end)
	Button(Page, "Reset Monitor Position", function()
		Actions.ResetMonitorPos()
	end)

	Section(Page, "Theme Color")
	_, ctl.rainbow = Toggle(Page, "Rainbow Mode", Settings.Rainbow, function(on)
		Actions.SetRainbow(on)
	end)
	Actions.OnRainbow = function(on)
		if ctl.rainbow then
			ctl.rainbow.Set(on, true)
		end
	end
	ctl.rspeed = Slider(Page, "Rainbow Speed", 0.2, 3, Settings.RainbowSpeed or 1, 1, function(v)
		Settings.RainbowSpeed = v
		saveSettings()
	end, true)

	local pickTarget = nil
	local pickerRef = {}
	local palette = {}

	_, ctl.multi = Toggle(Page, "Multi-Color Neon", Settings.Multi, function(on)
		Actions.SetMulti(on)
	end)
	Actions.OnMulti = function(on)
		if ctl.multi then
			ctl.multi.Set(on, true)
		end
	end

	local Combos = {
		{ "Lunar Trio", { "9B5CFF", "3DA5FF", "FF5CC8" } },
		{ "Aurora", { "3DDCC8", "5CFF9B", "9B5CFF" } },
		{ "Sunset", { "FF8A3D", "FF4F8B", "9B5CFF" } },
		{ "Cyber", { "00E5FF", "FF2BD6", "FFE600" } },
		{ "Candy", { "FF8FD8", "8FC8FF", "B7FF9B" } },
		{ "Galaxy", { "5C3DFF", "E75CFF", "3DDCFF", "FFFFFF" } },
	}
	local comboNames = {}
	for _, c in ipairs(Combos) do
		table.insert(comboNames, c[1])
	end

	local Palette = New("Frame", {
		Size = UDim2.new(1, 0, 0, 98),
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		LayoutOrder = 0,
		ZIndex = 50,
	}, Page)
	Corner(Palette, 14)
	Gradient(Palette, CARD_SHADE, 0)
	local PalStroke = Stroke(Palette, COLOR.innerBorder, 1.5, 0)
	Txt(Palette, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 12),
		Text = "NEON PALETTE",
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = COLOR.grey,
		ZIndex = 60,
	})
	local PalStatus = Txt(Palette, {
		Position = UDim2.fromOffset(16, 24),
		Size = UDim2.new(1, -32, 0, 14),
		TextSize = 10,
		TextColor3 = COLOR.redSoft,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 60,
	})
	local SlotRow = New("Frame", {
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -28, 0, 36),
		BackgroundTransparency = 1,
		ZIndex = 55,
	}, Palette)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, SlotRow)
	local slotObjs = {}

	local function setStatus()
		PalStatus.Text = pickTarget and TrF("Adjusting: neon color #%d  (tap again to return to the main color)", pickTarget)
			or Tr("Adjusting: theme main color  (tap a circle to pick a neon color)")
	end

	local function selectTarget(t)
		pickTarget = t
		setStatus()
		local c = t and HexToColor3(Settings.NeonColors[t]) or HexToColor3(Settings.ThemeColor)
		if c and pickerRef.Sync then
			pickerRef.Sync(c)
		end
		palette.Build()
	end

	function palette.Build()
		for _, o in ipairs(slotObjs) do
			o:Destroy()
		end
		table.clear(slotObjs)
		local list = Settings.NeonColors
		for i, hex in ipairs(list) do
			local sel = pickTarget == i
			local Sw = New("TextButton", {
				Size = UDim2.fromOffset(32, 32),
				BackgroundColor3 = HexToColor3(hex) or COLOR.red,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = i,
				ZIndex = 60,
			}, SlotRow)
			Corner(Sw, 16)
			Stroke(Sw, sel and Color3.new(1, 1, 1) or COLOR.innerBorder, sel and 2.6 or 1.5, sel and 0 or 0.2)
			track(Sw.Activated:Connect(function()
				selectTarget(pickTarget == i and nil or i)
			end))
			table.insert(slotObjs, Sw)
		end
		local function mini(text, order, fn)
			local B = New("TextButton", {
				Size = UDim2.fromOffset(32, 32),
				BackgroundColor3 = COLOR.switchOff,
				AutoButtonColor = false,
				Text = text,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = COLOR.white,
				LayoutOrder = order,
				ZIndex = 60,
			}, SlotRow)
			Corner(B, 16)
			Stroke(B, COLOR.innerBorder, 1.5, 0.1)
			track(B.Activated:Connect(function()
				fn()
			end))
			table.insert(slotObjs, B)
		end
		if #list < 5 then
			mini("+", 20, function()
				local h, s, v = Color3.toHSV(HexToColor3(list[#list]) or COLOR.red)
				table.insert(Settings.NeonColors, Color3ToHex(Color3.fromHSV((h + 0.17) % 1, s, v)))
				if not Settings.Multi then
					Actions.SetMulti(true, true)
				else
					Actions.RefreshNeon()
				end
				saveSettings()
				palette.Build()
			end)
		end
		if #list > 2 then
			mini("-", 21, function()
				table.remove(Settings.NeonColors, pickTarget or #Settings.NeonColors)
				pickTarget = nil
				setStatus()
				Actions.RefreshNeon()
				saveSettings()
				palette.Build()
			end)
		end
	end
	function palette.Reset()
		pickTarget = nil
		setStatus()
		palette.Build()
	end
	Actions.OnNeonChanged = palette.Build
	setStatus()
	Lang.OnChange(setStatus)
	palette.Build()
	OnTheme(function()
		Palette.BackgroundColor3 = COLOR.innerBg
		PalStroke.Color = COLOR.innerBorder
		PalStatus.TextColor3 = COLOR.redSoft
	end)

	local _, comboDrop = Dropdown(Page, "Neon Combo", {
		Options = comboNames,
		OnChange = function(v)
			for _, c in ipairs(Combos) do
				if c[1] == v then
					Settings.NeonColors = copyTable(c[2])
					Actions.SetMulti(true, true)
					Actions.SetThemeColor(HexToColor3(c[2][1]), true)
					pickTarget = nil
					setStatus()
					palette.Build()
					if pickerRef.Sync then
						pickerRef.Sync(HexToColor3(c[2][1]))
					end
					saveSettings()
				end
			end
		end,
	})

	Palette.LayoutOrder = ord(Page)

	local Presets = {
		{ "Lunar Purple", "9B5CFF" },
		{ "Nebula", "6C7BFF" },
		{ "Galaxy Pink", "E75CFF" },
		{ "Aurora", "3DDCC8" },
		{ "Moonlight", "8FB8FF" },
		{ "Rose Moon", "FF6FA8" },
		{ "Solar Gold", "FFC857" },
	}

	local Picker = New("Frame", {
		Size = UDim2.new(1, 0, 0, 226),
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		LayoutOrder = ord(Page),
		ZIndex = 50,
	}, Page)
	Corner(Picker, 14)
	Gradient(Picker, CARD_SHADE, 0)
	local PickerStroke = Stroke(Picker, COLOR.innerBorder, 1.5, 0)

	local ph, ps, pv = 0, 0.85, 0.92
	local picker = {}
	local bars = {}
	local presetSwatches = {}

	local function currentColor()
		return Color3.fromHSV(ph, ps, pv)
	end

	local Preview = New("Frame", {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = currentColor(),
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Picker)
	Corner(Preview, 21)
	local PreviewStroke = Stroke(Preview, Color3.new(1, 1, 1), 2, 0.55)

	local Field = New("Frame", {
		Position = UDim2.new(0, 66, 0, 14),
		Size = UDim2.new(1, -66 - 92, 0, 42),
		BackgroundColor3 = COLOR.black,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, Picker)
	Corner(Field, 10)
	local FieldStroke = Stroke(Field, COLOR.innerBorder, 1.5, 0)
	Gradient(Field, ColorSequence.new(Color3.fromRGB(235, 235, 240), Color3.new(1, 1, 1)), 90)

	Txt(Field, {
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.fromOffset(14, 42),
		Text = "#",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLOR.grey,
		ZIndex = 65,
	})
	local Input = New("TextBox", {
		Position = UDim2.new(0, 28, 0, 0),
		Size = UDim2.new(1, -38, 1, 0),
		BackgroundTransparency = 1,
		Text = Color3ToHex(currentColor()),
		PlaceholderText = "FF2D4B",
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = COLOR.white,
		PlaceholderColor3 = COLOR.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ZIndex = 65,
	}, Field)

	local Apply = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(70, 42),
		BackgroundColor3 = COLOR.red,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "APPLY",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 65,
	}, Picker)
	Corner(Apply, 10)
	local ApplyStroke = Stroke(Apply, COLOR.redBright, 1.2, 0.35)
	Lang.Bind(Apply, "Text", "APPLY")
	Gradient(Apply, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), 90)

	Txt(Picker, {
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 0, 12),
		Text = "PRESETS",
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = COLOR.grey,
		ZIndex = 60,
	})
	local PresetRow = New("Frame", {
		Position = UDim2.fromOffset(14, 82),
		Size = UDim2.new(1, -28, 0, 32),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, Picker)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, PresetRow)

	local function MakeBar(title, y, onMove)
		Txt(Picker, {
			Position = UDim2.fromOffset(16, y - 15),
			Size = UDim2.new(1, -32, 0, 12),
			Text = string.upper(title),
			Font = Enum.Font.GothamBold,
			TextSize = 9,
			TextColor3 = COLOR.grey,
			ZIndex = 60,
		})
		local Track = New("Frame", {
			Position = UDim2.new(0, 14, 0, y),
			Size = UDim2.new(1, -28, 0, 12),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 60,
		}, Picker)
		Corner(Track, 6)
		Stroke(Track, COLOR.innerBorder, 1, 0.3)
		local G = Gradient(Track, ColorSequence.new(Color3.new(1, 1, 1)), 0)
		local Knob = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 66,
		}, Track)
		Corner(Knob, 10)
		Stroke(Knob, Color3.fromRGB(20, 20, 24), 2.5, 0.1)

		local Hit = New("TextButton", {
			Position = UDim2.new(0, 14, 0, y - 12),
			Size = UDim2.new(1, -28, 0, 36),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 70,
		}, Picker)

		local bar = { Gradient = G, Knob = Knob }
		function bar.Set(v)
			Knob.Position = UDim2.fromScale(math.clamp(v, 0, 1), 0.5)
		end

		local dragging, dragInput = false, nil
		local function fromX(x)
			local w = Track.AbsoluteSize.X
			if w <= 0 then
				return
			end
			onMove(math.clamp((x - Track.AbsolutePosition.X) / w, 0, 1), false)
		end
		track(Hit.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				if dragging or not Interaction.Begin(Hit) then
					return
				end
				dragging, dragInput = true, input
				fromX(input.Position.X)
			end
		end))
		track(UIS.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == dragInput) then
				fromX(input.Position.X)
			end
		end))
		track(UIS.InputEnded:Connect(function(input)
			if not dragging then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == dragInput) then
				dragging, dragInput = false, nil
				Interaction.End(Hit)
				onMove(nil, true)
			end
		end))
		return bar
	end

	local function refreshVisual()
		local c = currentColor()
		Preview.BackgroundColor3 = c
		if not Input:IsFocused() then
			Input.Text = Color3ToHex(c)
		end
		bars.h.Set(ph)
		bars.s.Set(ps)
		bars.v.Set(pv)
		bars.s.Gradient.Color = ColorSequence.new(Color3.fromHSV(ph, 0, pv), Color3.fromHSV(ph, 1, pv))
		bars.v.Gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(ph, ps, 1))
		local hex = Color3ToHex(c)
		for _, sw in ipairs(presetSwatches) do
			local on = sw.Hex == Color3ToHex(HexToColor3(sw.Hex)) and sw.Hex == hex
			Tween(sw.Stroke, 0.15, { Color = on and Color3.new(1, 1, 1) or COLOR.innerBorder, Transparency = on and 0 or 0.2, Thickness = on and 2.4 or 1.5 })
		end
	end

	local function applyCurrent()
		if pickTarget then
			Actions.SetNeonSlot(pickTarget, currentColor())
		else
			Actions.SetThemeColor(currentColor())
		end
	end

	bars.h = MakeBar("Hue", 138, function(v, released)
		if released then
			applyCurrent()
		else
			ph = v
			refreshVisual()
		end
	end)
	bars.s = MakeBar("Saturation", 172, function(v, released)
		if released then
			applyCurrent()
		else
			ps = v
			refreshVisual()
		end
	end)
	bars.v = MakeBar("Brightness", 206, function(v, released)
		if released then
			applyCurrent()
		else
			pv = math.max(v, 0.25)
			refreshVisual()
		end
	end)
	bars.h.Gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
		ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
		ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
		ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
		ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
	})

	function picker.Sync(c)
		ph, ps, pv = Color3.toHSV(c)
		pv = math.max(pv, 0.25)
		refreshVisual()
	end

	for i, p in ipairs(Presets) do
		local col = HexToColor3(p[2])
		local Swatch = New("TextButton", {
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = col,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			ZIndex = 65,
		}, PresetRow)
		Corner(Swatch, 15)
		local SwStroke = Stroke(Swatch, COLOR.innerBorder, 1.5, 0.2)
		table.insert(presetSwatches, { Hex = p[2], Stroke = SwStroke })
		track(Swatch.MouseEnter:Connect(function()
			Tween(Swatch, 0.12, { Size = UDim2.fromOffset(34, 34) })
		end))
		track(Swatch.MouseLeave:Connect(function()
			Tween(Swatch, 0.12, { Size = UDim2.fromOffset(30, 30) })
		end))
		track(Swatch.Activated:Connect(function()
			picker.Sync(col)
			applyCurrent()
		end))
	end

	track(Input.Focused:Connect(function()
		Tween(FieldStroke, 0.15, { Color = COLOR.redBright, Thickness = 2 })
		Tween(Field, 0.15, { BackgroundColor3 = Color3.fromRGB(18, 18, 24) })
	end))
	track(Input:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = string.upper(Input.Text:gsub("[^%x]", "")):sub(1, 6)
		if clean ~= Input.Text then
			Input.Text = clean
			return
		end
		local c = HexToColor3(clean)
		if c and Input:IsFocused() then
			Preview.BackgroundColor3 = c
		end
	end))
	local function commitHex()
		local c = HexToColor3(Input.Text)
		if c then
			picker.Sync(c)
			applyCurrent()
		else
			Notify("Invalid color code (needs 6 digits)", false)
			Tween(FieldStroke, 0.1, { Color = COLOR.bad })
			task.delay(0.4, function()
				if FieldStroke.Parent then
					Tween(FieldStroke, 0.2, { Color = COLOR.innerBorder })
				end
			end)
			refreshVisual()
		end
	end
	track(Input.FocusLost:Connect(function(enter)
		Tween(FieldStroke, 0.15, { Color = COLOR.innerBorder, Thickness = 1.5 })
		Tween(Field, 0.15, { BackgroundColor3 = COLOR.black })
		if enter then
			commitHex()
		else
			refreshVisual()
		end
	end))
	track(Apply.Activated:Connect(commitHex))
	Hover(Apply, function(h)
		Tween(Apply, 0.12, { BackgroundColor3 = h and COLOR.redBright or COLOR.red })
	end)

	OnTheme(function()
		Picker.BackgroundColor3 = COLOR.innerBg
		PickerStroke.Color = COLOR.innerBorder
		FieldStroke.Color = COLOR.innerBorder
		Apply.BackgroundColor3 = COLOR.red
		ApplyStroke.Color = COLOR.redBright
	end)

	pickerRef.Sync = picker.Sync
	picker.Sync(HexToColor3(Settings.ThemeColor) or COLOR.red)

	Section(Page, "Config")
	local selectedCfg = nil
	local cfgInput, cfgDrop
	if Settings.DefaultConfig ~= "" and Config.Exists(Settings.DefaultConfig) then
		selectedCfg = Settings.DefaultConfig
	else
		Settings.DefaultConfig = ""
	end

	_, cfgInput = TextInput(Page, "Config Name", {
		Placeholder = "Config name",
	})
	_, cfgDrop = Dropdown(Page, "Select Config", {
		Options = function()
			return Config.List()
		end,
		Placeholder = "Select a config...",
		OnChange = function(v)
			selectedCfg = v
			if Settings.DefaultConfig ~= "" and v and v ~= "" then
				Settings.DefaultConfig = v
				saveSettings()
			end
		end,
	})
	if selectedCfg then
		cfgDrop.Set(selectedCfg, true)
	end

	local function needSelected()
		if not selectedCfg or selectedCfg == "" then
			Notify("Select a config first", false)
			return false
		end
		return true
	end

	Button(Page, "Save Config", function()
		local name = Config.Sanitize(cfgInput.Get())
		if name == "" then
			name = selectedCfg or ""
		end
		if name == "" then
			Notify("Enter a config name first", false)
			return
		end
		local existed = Config.Exists(name)
		local ok, persisted = Config.Save(name, CollectConfig())
		if not ok then
			Notify("Save failed", false)
			return
		end
		selectedCfg = name
		cfgDrop.Set(name, true)
		cfgInput.Set("")
		if Settings.DefaultConfig ~= "" and Settings.DefaultConfig ~= name then
			Settings.DefaultConfig = name
			saveSettings()
		end
		if persisted then
			Notify(TrF(existed and "Overwritten: %s" or "Created: %s", name), true)
		else
			Notify(existed and "Saved (temporary)" or "Created (temporary)", true)
		end
	end)
	Button(Page, "Load Config", function()
		if not needSelected() then
			return
		end
		local data = Config.Read(selectedCfg)
		if not data then
			Notify("Could not read config", false)
			return
		end
		local n = ApplyConfig(data.Values)
		Notify(TrF("Loaded %d values", n), true)
	end)
	_, ctl.autocfg = Toggle(Page, "Auto Load Config", Settings.DefaultConfig ~= "", function(on)
		if on then
			if not selectedCfg or selectedCfg == "" then
				Notify("Select a config first", false)
				ctl.autocfg.Set(false, true)
				return
			end
			Settings.DefaultConfig = selectedCfg
			saveSettings()
			Notify(TrF("Auto load on: %s", selectedCfg), true)
		else
			Settings.DefaultConfig = ""
			saveSettings()
			Notify("Auto load off", true)
		end
	end)
	Button(Page, "Delete Config", function()
		if not needSelected() then
			return
		end
		Config.Delete(selectedCfg)
		if Settings.DefaultConfig == selectedCfg then
			Settings.DefaultConfig = ""
			saveSettings()
			ctl.autocfg.Set(false, true)
		end
		selectedCfg = nil
		cfgDrop.Set(nil, true)
		Notify("Config deleted", true)
	end, true)

	Section(Page, "Actions")
	Button(Page, "Reset Settings", function()
		Settings = copyTable(DEFAULT_SETTINGS)
		ctl.bg.Set(Settings.BgOpacity, true)
		BgImage.ImageTransparency = 1 - Settings.BgOpacity / 100
		Layout.Reset()
		Custom.Refresh("Buttons")
		Custom.Refresh("Sections")
		Custom.Refresh("Groups")
		ctl.anim.Set(Settings.Animate, true)
		ctl.pulse.Set(Settings.Pulse, true)
		ctl.float.Set(Settings.ShowFloating, true)
		ctl.stars.Set(Settings.Stars, true)
		ctl.afk.Set(Settings.AntiAFK, true)
		Actions.SetAntiAfk(Settings.AntiAFK)
		ctl.autocfg.Set(false, true)
		ctl.rainbow.Set(false, true)
		ctl.rspeed.Set(Settings.RainbowSpeed, true)
		Actions.SetRainbow(false, true)
		ctl.multi.Set(Settings.Multi, true)
		Actions.SetMulti(Settings.Multi, true)
		palette.Reset()
		Actions.SetPulse(Settings.Pulse)
		Actions.SetThemeColor(HexToColor3(Settings.ThemeColor), true)
		picker.Sync(HexToColor3(Settings.ThemeColor))
		perfDrop.Set(Settings.Perf, true)
		ctl.monitor.Set(Settings.FloatMonitor, true)
		Actions.SetMonitor(Settings.FloatMonitor, true)
		Actions.ResetMonitorPos()
		Lang.Set(Settings.Lang)
		langDrop.Set("ไทย", true)
		Actions.SetStars(Settings.Stars)
		Actions.ApplyPerf()
		Actions.RefreshFloating()
		saveSettings()
		Notify("Settings reset", true)
	end)
	Button(Page, "Destroy GUI", cleanup, true)
end

do
	local Page = CreatePage("Credits")
	CreateTab("Credits", "info")

	local Card = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLOR.innerBg,
		BorderSizePixel = 0,
		LayoutOrder = ord(Page),
		ZIndex = 50,
	}, Page)
	Corner(Card, 14)
	Gradient(Card, CARD_SHADE, 0)
	local CardStroke = Stroke(Card, Color3.new(1, 1, 1), 1.6, 0.15)
	local CardStrokeGrad = Gradient(CardStroke, NeonSequence, 0)
	Spin(CardStrokeGrad, 9, 2, Page)
	New("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 16),
	}, Card)
	New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Card)

	local Logo = Txt(Card, {
		Size = UDim2.new(1, 0, 0, 28),
		Text = "LUNAR Hub",
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		LayoutOrder = 1,
		ZIndex = 55,
	})
	local Line = New("Frame", {
		Visible = false,
		Size = UDim2.fromOffset(42, 2),
		BackgroundColor3 = COLOR.red,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		ZIndex = 55,
	}, Card)
	Corner(Line, 2)
	Txt(Card, {
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Universal Control Panel",
		TextColor3 = COLOR.grey,
		LayoutOrder = 3,
		ZIndex = 55,
	})
	Txt(Card, {
		Size = UDim2.new(1, 0, 0, 18),
		Text = "UI / System  :  LUNAR Team",
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 4,
		ZIndex = 55,
	})
	Txt(Card, {
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Neon interface for LUNAR Hub",
		TextSize = 10,
		TextColor3 = COLOR.grey,
		LayoutOrder = 5,
		ZIndex = 55,
	})

	OnTheme(function()
		Logo.TextColor3 = COLOR.red
		Line.BackgroundColor3 = COLOR.red
		Card.BackgroundColor3 = COLOR.innerBg
		CardStroke.Color = Color3.new(1, 1, 1)
		CardStrokeGrad.Color = NeonSequence
	end)
end

Actions.ApplyLayout()
Actions.ActivateTab("Overview")

local function Draggable(handle, opts)
	local dragging, moved = false, false
	local startInput, startPointer, startValue

	local function finish()
		if not dragging then
			return
		end
		dragging = false
		Interaction.End(handle)
		if not moved and opts.onClick then
			opts.onClick()
		elseif moved and opts.onEnd then
			opts.onEnd()
		end
	end

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if opts.canStart and not opts.canStart() then
			return
		end
		if dragging or not Interaction.Begin(handle) then
			return
		end
		dragging, moved = true, false
		startInput = input
		startPointer = Vector2.new(input.Position.X, input.Position.Y)
		startValue = opts.get()
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				finish()
			end
		end)
	end))

	track(UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == startInput) then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - startPointer
			if not moved and delta.Magnitude < 5 then
				return
			end
			moved = true
			opts.set(startValue + delta)
		end
	end))

	track(UIS.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or (input.UserInputType == Enum.UserInputType.Touch and input == startInput)
		then
			finish()
		end
	end))
end

local TOGGLE = 50
local ToggleCenter = Vector2.new(Viewport().X - 52, Viewport().Y * 0.72)

local ToggleRoot = New("Frame", {
	Name = "FloatingToggle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(ToggleCenter.X, ToggleCenter.Y),
	Size = UDim2.fromOffset(TOGGLE, TOGGLE),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 200,
}, Gui)

local ToggleGlow = NeonLayers(ToggleRoot, 16, {
	{ 3, 0.65, 0.80 },
	{ 7, 0.80, 0.90 },
	{ 12, 0.90, 0.96 },
})
for i, l in ipairs(ToggleGlow) do
	Spin(l.Grad, 4, 3, "toggle", i)
end

local ToggleButton = New("TextButton", {
	Name = "Body",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 10, 14),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 10,
}, ToggleRoot)
Corner(ToggleButton, 16)
Gradient(ToggleButton, ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 12, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 11)),
}), 90)

local ToggleStroke = Stroke(ToggleButton, Color3.new(1, 1, 1), 2, 0)
local ToggleStrokeGrad = Gradient(ToggleStroke, NeonSequence, 0)
Spin(ToggleStrokeGrad, 4, 1, "toggle")

local ToggleLabel = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -2),
	Size = UDim2.fromScale(1, 0.7),
	BackgroundTransparency = 1,
	RichText = true,
	Text = "",
	Font = Enum.Font.GothamBlack,
	TextSize = 19,
	TextColor3 = COLOR.white,
	ZIndex = 12,
}, ToggleButton)
local ToggleLabelStroke = New("UIStroke", {
	Color = COLOR.neon,
	Thickness = 1.4,
	Transparency = 0.45,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
}, ToggleLabel)

local FMoon = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -2),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = Color3.fromRGB(240, 236, 255),
	BorderSizePixel = 0,
	ZIndex = 13,
}, ToggleButton)
Corner(FMoon, 13)
Gradient(FMoon, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 184, 230)), 45)
local FMoonStroke = Stroke(FMoon, COLOR.neon, 3, 0.55)
for _, c in ipairs({ { 15, 5, 6 }, { 5, 13, 8 }, { 16, 16, 4 } }) do
	local crater = New("Frame", {
		Position = UDim2.fromOffset(c[1], c[2]),
		Size = UDim2.fromOffset(c[3], c[3]),
		BackgroundColor3 = Color3.fromRGB(196, 190, 228),
		BorderSizePixel = 0,
		ZIndex = 14,
	}, FMoon)
	Corner(crater, c[3])
end
OnTheme(function()
	FMoonStroke.Color = COLOR.neon
end)

local FLogo = New("ImageLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Image = "",
	ScaleType = Enum.ScaleType.Crop,
	Visible = false,
	ZIndex = 11,
}, ToggleButton)
Corner(FLogo, 16)
Assets.On("Logo", function(id)
	if FLogo.Parent then
		FLogo.Image = id
		FLogo.Visible = true
		FMoon.Visible = false
	end
end)

local ToggleBar = New("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(22, 2),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 12,
}, ToggleButton)
Corner(ToggleBar, 2)
local ToggleBarGrad = Gradient(ToggleBar, ColorSequence.new(COLOR.red), 0)

local PanelVisible = true

OnTheme(function()
	ToggleStroke.Color = Color3.new(1, 1, 1)
	ToggleStrokeGrad.Color = NeonSequence
	ToggleLabelStroke.Color = COLOR.neon
	for _, layer in ipairs(ToggleGlow) do
		layer.Stroke.Color = Color3.new(1, 1, 1)
		layer.Grad.Color = NeonSequence
	end
	ToggleBarGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOR.redDark),
		ColorSequenceKeypoint.new(0.5, COLOR.redSoft),
		ColorSequenceKeypoint.new(1, COLOR.redDark),
	})
end)

local function SetToggleCenter(v)
	local vp = Viewport()
	local half = TOGGLE / 2 + 4
	ToggleCenter = Vector2.new(
		math.clamp(v.X, half, math.max(half, vp.X - half)),
		math.clamp(v.Y, half, math.max(half, vp.Y - half))
	)
	ToggleRoot.Position = UDim2.fromOffset(ToggleCenter.X, ToggleCenter.Y)
end

track(ToggleButton.MouseEnter:Connect(function()
	Tween(ToggleRoot, 0.18, { Size = UDim2.fromOffset(TOGGLE + 6, TOGGLE + 6) })
	Tween(ToggleStroke, 0.18, { Thickness = 2.6 })
end))
track(ToggleButton.MouseLeave:Connect(function()
	Tween(ToggleRoot, 0.18, { Size = UDim2.fromOffset(TOGGLE, TOGGLE) })
	Tween(ToggleStroke, 0.18, { Thickness = 2 })
end))

function Actions.RefreshFloating()
	ToggleRoot.Visible = Settings.ShowFloating or not PanelVisible
	if Actions.UpdateAnim then
		Actions.UpdateAnim()
	end
end

local Animating = false
local AnimToken = 0
local POP = 26

local function SetToggleState(open)
	Tween(ToggleLabel, 0.2, { TextTransparency = open and 0 or 0.4 })
end

local function OpenPanel()
	PanelVisible = true
	Animating = true
	AnimToken += 1
	local token = AnimToken
	Actions.RefreshFloating()
	Root.Visible = true
	Actions.UpdateAnim()
	Root.Size = UDim2.fromOffset(PanelSize.X - POP, PanelSize.Y - POP)
	Root.Position = UDim2.fromOffset(PanelPos.X + POP / 2, PanelPos.Y + POP / 2)
	Tween(Root, 0.28, {
		Size = UDim2.fromOffset(PanelSize.X, PanelSize.Y),
		Position = UDim2.fromOffset(PanelPos.X, PanelPos.Y),
	}, Enum.EasingStyle.Back)
	SetToggleState(true)
	task.delay(0.32, function()
		if token == AnimToken then
			Animating = false
			ApplyPanel()
		end
	end)
end

local function ClosePanel()
	Picker.Close()
	PanelVisible = false
	Animating = true
	AnimToken += 1
	local token = AnimToken
	Actions.RefreshFloating()
	Tween(Root, 0.2, {
		Size = UDim2.fromOffset(PanelSize.X - POP, PanelSize.Y - POP),
		Position = UDim2.fromOffset(PanelPos.X + POP / 2, PanelPos.Y + POP / 2),
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	SetToggleState(false)
	task.delay(0.24, function()
		if token == AnimToken then
			Animating = false
			Root.Visible = false
			ApplyPanel()
			Actions.UpdateAnim()
		end
	end)
end

local function CanMovePanel()
	return PanelVisible and not Animating
end

Draggable(ToggleButton, {
	get = function()
		return ToggleCenter
	end,
	set = SetToggleCenter,
	onClick = function()
		if PanelVisible then
			ClosePanel()
		else
			OpenPanel()
		end
	end,
})

local PanelDrag = {
	get = function()
		return PanelPos
	end,
	set = SetPanelPos,
	canStart = CanMovePanel,
}
Draggable(Header, PanelDrag)
Draggable(Sidebar, PanelDrag)

track(Close.Activated:Connect(function()
	if PanelVisible then
		ClosePanel()
	end
end))

local Resize = New("TextButton", {
	Name = "ResizeHandle",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -3, 1, -3),
	Size = UDim2.fromOffset(26, 26),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 100,
}, Main)

local GripDots = {}
for _, p in ipairs({ { 18, 18 }, { 18, 11 }, { 11, 18 }, { 18, 4 }, { 4, 18 }, { 11, 11 } }) do
	local d = New("Frame", {
		Position = UDim2.fromOffset(p[1], p[2]),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = COLOR.innerBorder,
		BorderSizePixel = 0,
		ZIndex = 101,
	}, Resize)
	Corner(d, 2)
	table.insert(GripDots, d)
end
local gripHover, gripActive = false, false
local function PaintGrip()
	local c = (gripHover or gripActive) and COLOR.redSoft or COLOR.innerBorder
	for _, d in ipairs(GripDots) do
		Tween(d, 0.15, { BackgroundColor3 = c })
	end
end
OnTheme(PaintGrip)
track(Resize.MouseEnter:Connect(function()
	gripHover = true
	PaintGrip()
end))
track(Resize.MouseLeave:Connect(function()
	gripHover = false
	PaintGrip()
end))

local SizeTip = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(120, 24),
	BackgroundColor3 = COLOR.black,
	BackgroundTransparency = 0.1,
	Text = "",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = COLOR.white,
	Visible = false,
	ZIndex = 250,
}, Main)
Corner(SizeTip, 12)
local SizeTipStroke = Stroke(SizeTip, COLOR.red, 1.5, 0.1)
OnTheme(function()
	SizeTipStroke.Color = COLOR.red
end)
local tipToken = 0

local function ShowSizeTip()
	tipToken += 1
	local token = tipToken
	SizeTip.Text = string.format("%d × %d%s", PanelSize.X, PanelSize.Y, PanelSize.X < 480 and "  ·  Compact" or "")
	SizeTip.Size = UDim2.fromOffset(PanelSize.X < 480 and 150 or 100, 24)
	SizeTip.Visible = true
	task.delay(0.9, function()
		if token == tipToken and SizeTip.Parent and not gripActive then
			SizeTip.Visible = false
		end
	end)
end

Draggable(Resize, {
	get = function()
		return PanelSize
	end,
	set = function(v)
		gripActive = true
		PaintGrip()
		SetPanelSize(v.X, v.Y)
		ShowSizeTip()
	end,
	canStart = CanMovePanel,
})
track(UIS.InputEnded:Connect(function(input)
	if gripActive and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		gripActive = false
		PaintGrip()
		ShowSizeTip()
	end
end))

local MONITOR_W, MONITOR_H = 116, 46
local MONITOR_DEFAULT = Vector2.new(12, 48)
local MonitorPos = MONITOR_DEFAULT
if (Settings.MonitorX or -1) >= 0 and (Settings.MonitorY or -1) >= 0 then
	MonitorPos = Vector2.new(Settings.MonitorX, Settings.MonitorY)
end

local MonitorRoot = New("Frame", {
	Name = "Monitor",
	Position = UDim2.fromOffset(MonitorPos.X, MonitorPos.Y),
	Size = UDim2.fromOffset(MONITOR_W, MONITOR_H),
	BackgroundColor3 = COLOR.black,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Active = true,
	Visible = Settings.FloatMonitor == true,
	ZIndex = 190,
}, Gui)
Corner(MonitorRoot, 10)
local MonitorStroke = Stroke(MonitorRoot, Color3.new(1, 1, 1), 1.6, 0.1)
local MonitorStrokeGrad = Gradient(MonitorStroke, NeonSequence, 0)

local function MonitorRow(y, label)
	Txt(MonitorRoot, {
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.fromOffset(40, 16),
		Text = label,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = COLOR.grey,
		ZIndex = 191,
	})
	return Txt(MonitorRoot, {
		Position = UDim2.new(0, 48, 0, y),
		Size = UDim2.new(1, -60, 0, 16),
		Text = "-",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 191,
	})
end
local MonFps = MonitorRow(6, "FPS")
local MonPing = MonitorRow(24, "PING")
local MON_YELLOW = Color3.fromRGB(255, 200, 90)

OnTheme(function()
	MonitorRoot.BackgroundColor3 = COLOR.black
	MonitorStroke.Color = Color3.new(1, 1, 1)
	MonitorStrokeGrad.Color = NeonSequence
end)

Telemetry.Add(function(fps, ping)
	MonFps.Text = tostring(fps)
	MonFps.TextColor3 = fps >= 50 and COLOR.good or (fps >= 30 and MON_YELLOW or COLOR.bad)
	if ping then
		MonPing.Text = ping .. "ms"
		MonPing.TextColor3 = ping < 100 and COLOR.good or (ping < 200 and MON_YELLOW or COLOR.bad)
	else
		MonPing.Text = "N/A"
		MonPing.TextColor3 = COLOR.grey
	end
end, function()
	return MonitorRoot.Visible
end)

local function SetMonitorPos(v)
	local vp = Viewport()
	MonitorPos = Vector2.new(
		math.clamp(v.X, 0, math.max(0, vp.X - MONITOR_W)),
		math.clamp(v.Y, 0, math.max(0, vp.Y - MONITOR_H))
	)
	MonitorRoot.Position = UDim2.fromOffset(MonitorPos.X, MonitorPos.Y)
end

function Actions.ClampMonitor()
	SetMonitorPos(MonitorPos)
end

function Actions.SetMonitor(on, silent)
	Settings.FloatMonitor = on == true
	MonitorRoot.Visible = on == true
	Telemetry.Poke()
	if not silent then
		saveSettings()
	end
end

function Actions.ResetMonitorPos()
	SetMonitorPos(MONITOR_DEFAULT)
	Settings.MonitorX, Settings.MonitorY = -1, -1
	saveSettings()
end

Draggable(MonitorRoot, {
	get = function()
		return MonitorPos
	end,
	set = SetMonitorPos,
	onEnd = function()
		Settings.MonitorX, Settings.MonitorY = MonitorPos.X, MonitorPos.Y
		saveSettings()
	end,
})

function Actions.Refit()
	SetPanelSize(PanelSize.X, PanelSize.Y)
	SetToggleCenter(ToggleCenter)
	if Actions.ClampMonitor then
		Actions.ClampMonitor()
	end
end
track(Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Actions.Refit))

function Actions.UpdateAnim()
	local p = GetPerf()
	for _, e in ipairs(SpinTweens) do
		local visible
		if e.Scope == "toggle" then
			visible = ToggleRoot.Visible
		elseif e.Scope == "root" then
			visible = Root.Visible
		else
			visible = Root.Visible and e.Scope.Visible
		end
		local layerOn = e.Layer == nil or e.Layer <= p.glow
		local should = Settings.Pulse and p.spinTier >= e.Tier and visible and layerOn
		local playing = e.Tween.PlaybackState == Enum.PlaybackState.Playing
		if should and not playing then
			e.Tween:Play()
		elseif not should and playing then
			e.Tween:Pause()
		end
	end
	Telemetry.Poke()
end

function Actions.SetPulse(on)
	Settings.Pulse = on
	Actions.UpdateAnim()
end

function Actions.ApplyPerf()
	local p = GetPerf()
	for i, l in ipairs(MainGlow) do
		l.Frame.Visible = i <= p.glow
	end
	for i, l in ipairs(ToggleGlow) do
		l.Frame.Visible = i <= p.glow
	end
	Actions.RefreshSky()
	Actions.UpdateAnim()
end

function Actions.SetPerf(name, silent)
	if not PERF_PRESETS[name] then
		return
	end
	Settings.Perf = name
	Actions.ApplyPerf()
	if not silent then
		saveSettings()
	end
end

task.spawn(function()
	local dim = false
	while not destroyed and Gui.Parent do
		local p = GetPerf()
		if Settings.Pulse and p.pulse then
			if Root.Visible then
				for i, layer in ipairs(MainGlow) do
					if i <= p.glow then
						Tween(layer.Stroke, 1.2, { Transparency = dim and layer.Dim or layer.Bright }, Enum.EasingStyle.Sine)
					end
				end
			end
			if ToggleRoot.Visible then
				for i, layer in ipairs(ToggleGlow) do
					if i <= p.glow then
						Tween(layer.Stroke, 1.2, { Transparency = dim and layer.Dim or layer.Bright }, Enum.EasingStyle.Sine)
					end
				end
			end
		end
		dim = not dim
		task.wait(1.2)
	end
end)

track(Gui.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end))

do
	local ok = pcall(function()
		Gui.Parent = game:GetService("CoreGui")
	end)
	if not ok or not Gui.Parent then
		Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

Actions.ApplyPerf()
if Settings.Rainbow then
	Actions.SetRainbow(true, true)
end
Actions.ApplyLayout()
Layout.Restore()
Actions.Refit()
Actions.RefreshFloating()
Actions.ActivateTab("Overview")

Assets.Load()
Actions.SetAntiAfk(Settings.AntiAFK)
addCleanup(function()
	if AntiAfk.Conn then
		AntiAfk.Conn:Disconnect()
		AntiAfk.Conn = nil
	end
end)

task.defer(function()
	local name = Settings.DefaultConfig
	if type(name) == "string" and name ~= "" and Config.Exists(name) then
		local data = Config.Read(name)
		if data then
			ApplyConfig(data.Values)
			Notify(TrF("Loaded config: %s", name), true)
		end
	end
end)

print("[LUNAR Hub] Loaded successfully")

return {
	Version = Lunar.Version,
	UI = UI,
	Gui = Gui,
	Notify = Notify,
	Destroy = function()
		cleanup()
	end,
}
end

Lunar.new = Build

return Lunar
