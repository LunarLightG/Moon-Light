-- LUNAR HUB game loader: reads Game.json, finds the entry for the current game, runs its script.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local LOADER = {
	GameJsonUrl = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Game.json",
	GameJsonFile = "Game.json", -- local fallback in the executor workspace
	Retries = 3,
	RetryDelay = 1.5,
}

do -- optional override: getgenv().LunarGameLoaderConfig = { GameJsonUrl = "..." }
	local o = rawget(ENV, "LunarGameLoaderConfig")
	if type(o) == "table" then
		for k, v in pairs(o) do
			LOADER[k] = v
		end
	end
end

local function log(...)
	print("[LUNAR GameLoader]", ...)
end

-- Roblox built-in notification (bottom-right, same style as achievement/badge toasts)
local StarterGui = game:GetService("StarterGui")

-- logo shown in the notification: downloaded once, then loaded as a custom asset
local LOGO_URL = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Assets/logoO.png"
local LOGO_FILE = "LunarHub_logo.png"
local logoIcon, logoDone = nil, false

local function loadLogo()
	pcall(function()
		local asset = getcustomasset or getsynasset
		if type(asset) ~= "function" or type(writefile) ~= "function" then
			return
		end
		local hasFile = type(isfile) == "function" and isfile(LOGO_FILE)
		if not hasFile then
			local body = game:HttpGet(LOGO_URL)
			if type(body) ~= "string" or #body == 0 then
				return
			end
			writefile(LOGO_FILE, body)
		end
		logoIcon = asset(LOGO_FILE)
	end)
	logoDone = true
end
task.spawn(loadLogo)

local function notify(text, duration)
	task.spawn(function()
		local waited = 0
		while not logoDone and waited < 3 do -- give the logo a moment to download
			task.wait(0.1)
			waited += 0.1
		end
		for _ = 1, 20 do -- SetCore can fail until the core script has registered it
			local ok = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = "LUNAR HUB",
					Text = text,
					Icon = logoIcon,
					Duration = duration or 5,
				})
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
	end)
end

if not Players.LocalPlayer then
	warn("[LUNAR GameLoader] Must run on the client")
	return
end

local function httpGet(url)
	for attempt = 1, LOADER.Retries do
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == "string" and #body > 0 then
			return body
		end
		log(("download failed (%d/%d): %s"):format(attempt, LOADER.Retries, url))
		task.wait(LOADER.RetryDelay)
	end
end

local function readGameJson()
	local raw = httpGet(LOADER.GameJsonUrl)
	if not raw and type(isfile) == "function" and type(readfile) == "function" and isfile(LOADER.GameJsonFile) then
		raw = readfile(LOADER.GameJsonFile)
		log("using local " .. LOADER.GameJsonFile)
	end
	if not raw then
		return nil, "could not load Game.json"
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(data) ~= "table" then
		return nil, "Game.json is not valid JSON"
	end
	return data
end

local function has(list, value)
	if type(list) ~= "table" then
		return false
	end
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function findGame(data)
	for _, g in ipairs(data.Games or {}) do
		if has(g.PlaceIds, game.PlaceId) or has(g.UniverseIds, game.GameId) then
			return g
		end
	end
end

-- executor check
if type(loadstring) ~= "function" then
	warn("[LUNAR GameLoader] executor ไม่รองรับ loadstring")
	notify("executor ไม่รองรับ loadstring", 8)
	return
end

local data, err = readGameJson()
if not data then
	warn("[LUNAR GameLoader] " .. tostring(err))
	notify("โหลด Game.json ไม่สำเร็จ", 8)
	return
end

local entry = findGame(data)
if not entry then
	warn("[LUNAR GameLoader] แมพนี้ไม่รองรับ (PlaceId " .. game.PlaceId .. ")")
	notify("แมพนี้ไม่รองรับ")
	return
end

local url = entry.Script
if type(url) ~= "string" or url == "" then
	warn("[LUNAR GameLoader] Entry has no Script: " .. tostring(entry.Name))
	notify("ไม่พบลิงก์สคริปต์ของแมพนี้", 8)
	return
end
if not url:match("^https?://") then
	url = (data.Base or "") .. url
end

-- hand the entry's settings to the script (read by its CONFIG override block)
local cfg = {}
if entry.Id ~= nil then
	cfg.Id = tostring(entry.Id)
end
if entry.Name then
	cfg.GameName = entry.Name
end
if type(entry.Systems) == "table" then
	cfg.Systems = entry.Systems
end
if type(entry.LibraryUrl) == "string" then
	cfg.LibraryUrl = entry.LibraryUrl
end
ENV.LunarLoaderConfig = cfg

log(("แมพ: %s -> %s"):format(tostring(entry.Name), url))
notify("แมพ: " .. tostring(entry.Name))
local source = httpGet(url)
if not source then
	warn("[LUNAR GameLoader] โหลดสคริปต์ไม่สำเร็จ: " .. url)
	notify("โหลดสคริปต์ไม่สำเร็จ", 8)
	return
end

local fn, cerr = loadstring(source, "=" .. tostring(entry.Name or "LunarScript"))
if not fn then
	warn("[LUNAR GameLoader] Script compile error: " .. tostring(cerr))
	notify("คอมไพล์ไม่สำเร็จ: " .. tostring(cerr):sub(1, 80), 8)
	return
end

local ok, result = pcall(fn)
if not ok then
	warn("[LUNAR GameLoader] Script error: " .. tostring(result))
	notify("รันไม่สำเร็จ: " .. tostring(result):sub(1, 80), 8)
	return
end

log("รันสำเร็จ: " .. tostring(entry.Name))
notify(tostring(entry.Name) .. " - รันสำเร็จ")
return result
