local HOVER_HEIGHT = 25
local HOVER_RADIUS = 18
local HOVER_SPEED = 2.2
local STAGE_MIN_TIME = 0.5
local CLEAR_HOLD = 1.5 -- seconds with zero enemies before a stage counts as cleared (was 0)
local STAGE_TIMEOUT = 25 -- seconds WITHOUT progress (an enemy dying or losing HP) before skipping (was 25s total)
local STAGE_HARD_TIMEOUT = 180 -- absolute cap per stage, even while still making progress
local STAGE_DEBUG = true -- prints why each stage was left + boss-like objects outside MyEnemies; set false when done
local MAP_WAIT = 10 -- seconds to wait for a newly entered world's map to load before giving up
local PAD_GLOBAL = false
local REBIRTH_GRACE = 3.5
local LOCK_FAILS = 3
local LOCK_TTL = 10

local LIB_URL = "https://raw.githubusercontent.com/LunarLightG/Moon-Light/refs/heads/main/Library.lua"
local EXPECTED_PLACE = 97617452700163

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes", 15)
if not Remotes then
	warn("[AE] ReplicatedStorage.Remotes not found, wrong game?")
	return
end
if game.PlaceId ~= EXPECTED_PLACE then
	warn(("[AE] PlaceId %d differs from the dumped game (%d), names may not match"):format(game.PlaceId, EXPECTED_PLACE))
end

if getgenv().AE and getgenv().AE.Unload then
	pcall(getgenv().AE.Unload)
end
local SESSION = (tonumber(getgenv().AE_SESSION) or 0) + 1
getgenv().AE_SESSION = SESSION

local AE = {
	Running = true,
	AutoSpot = true,
	Spot = 1,
	SpotNeed = {},
	Locked = {},
	SpotVerified = false,
	StageTarget = 15,
	FarmHits = 10,
	StageHits = 10,
	StageRun = { active = false },
	Farm = { Power = false, Rebirth = false, Stage = false },
	InFlight = {},
	LastError = {},
}
getgenv().AE = AE

local function isCurrent()
	return AE.Running and getgenv().AE_SESSION == SESSION
end

local conns = {}
function AE.Unload()
	AE.Running = false
	for k in pairs(AE.Farm) do
		AE.Farm[k] = false
	end
	AE.StageRun = { active = false }
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	if getgenv().AE_SESSION == SESSION then
		getgenv().AE_SESSION = SESSION + 1
	end
end

local function reportError(key, err)
	local msg = tostring(err)
	if AE.LastError[key] ~= msg then
		AE.LastError[key] = msg
		warn(("[AE] %s failed: %s"):format(key, msg))
	end
end

local function fire(name, ...)
	if not isCurrent() then
		return false
	end
	local r = Remotes:FindFirstChild(name)
	if not r or not r:IsA("RemoteEvent") then
		reportError("RemoteEvent " .. name, "missing or wrong class")
		return false
	end
	local ok, err = pcall(r.FireServer, r, ...)
	if not ok then
		reportError(name, err)
	end
	return ok
end

local function invoke(name, ...)
	if not isCurrent() or AE.InFlight[name] then
		return false
	end
	local r = Remotes:FindFirstChild(name)
	if not r or not r:IsA("RemoteFunction") then
		reportError("RemoteFunction " .. name, "missing or wrong class")
		return false
	end
	AE.InFlight[name] = true
	local args = table.pack(...)
	task.spawn(function()
		local ok, result = pcall(r.InvokeServer, r, table.unpack(args, 1, args.n))
		AE.InFlight[name] = nil
		if not ok then
			reportError(name, result)
		end
	end)
	return true
end

local function myRoot()
	local ch = lp.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function tpTo(pos)
	local root = myRoot()
	if not root then
		return false
	end
	root.CFrame = CFrame.new(pos)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function enemyPart(e)
	if e:IsA("BasePart") then
		return e
	end
	if e:IsA("Model") then
		return e.PrimaryPart or e:FindFirstChild("HumanoidRootPart") or e:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function alive(e)
	local hum = e:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return false
	end
	local hp = e:GetAttribute("Health") or e:GetAttribute("HP")
	return not (type(hp) == "number" and hp <= 0)
end

local ID_NAMES = { "Id", "ID", "EnemyId", "EnemyID", "Uid", "UID", "Eid" }
local function enemyId(e)
	for _, n in ipairs(ID_NAMES) do
		local v = e:GetAttribute(n)
		if type(v) == "number" then
			return v
		end
		local c = e:FindFirstChild(n)
		if c and c:IsA("ValueBase") and type(c.Value) == "number" then
			return c.Value
		end
	end
	for k, v in pairs(e:GetAttributes()) do
		if type(v) == "number" and tostring(k):lower():find("id") then
			return v
		end
	end
	local num = e.Name:match("%d+")
	return num and tonumber(num) or nil
end

local function enemyList()
	local f = workspace:FindFirstChild("MyEnemies")
	return f and f:GetChildren() or {}
end

local function aliveCount()
	local n = 0
	for _, e in ipairs(enemyList()) do
		if enemyPart(e) and alive(e) then
			n = n + 1
		end
	end
	return n
end

local function enemyHp(e)
	local hum = e:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum.Health
	end
	local hp = e:GetAttribute("Health") or e:GetAttribute("HP")
	return type(hp) == "number" and hp or nil
end

-- alive count and summed HP (HP is nil when no alive enemy exposes it)
local function enemyStats()
	local n, sum, any = 0, 0, false
	for _, e in ipairs(enemyList()) do
		if enemyPart(e) and alive(e) then
			n = n + 1
			local hp = enemyHp(e)
			if hp then
				sum = sum + hp
				any = true
			end
		end
	end
	return n, any and sum or nil
end

-- debug only: boss-like objects that are NOT under workspace.MyEnemies
local function bossLikeOutsideEnemies()
	local folder = workspace:FindFirstChild("MyEnemies")
	local found = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and d.Name:lower():find("boss", 1, true) and not (folder and d:IsDescendantOf(folder)) then
			found[#found + 1] = d:GetFullName()
			if #found >= 5 then
				break
			end
		end
	end
	return found
end

local function nearestEnemies(root, maxN)
	local cand = {}
	for _, e in ipairs(enemyList()) do
		local p = enemyPart(e)
		if p and alive(e) then
			cand[#cand + 1] = { e = e, p = p, d = (p.Position - root.Position).Magnitude }
		end
	end
	table.sort(cand, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i = 1, math.min(maxN, #cand) do
		out[i] = { pos = cand[i].p.Position, id = enemyId(cand[i].e) }
	end
	return out
end

local attackBtn, attackClickable, warnedNoSignal
local SIGNALS = { "MouseButton1Down", "Activated", "MouseButton1Click", "MouseButton1Up" }

local function resolveAttackButton()
	if attackBtn and attackBtn.Parent then
		return attackClickable
	end
	attackBtn, attackClickable = nil, nil
	local pg = lp:FindFirstChild("PlayerGui")
	local main = pg and pg:FindFirstChild("Main")
	local hud = main and main:FindFirstChild("HUD")
	local skills = hud and hud:FindFirstChild("Skills")
	local a = skills and skills:FindFirstChild("Attack")
	if not a then
		return nil
	end
	attackBtn = a
	if a:IsA("GuiButton") then
		attackClickable = a
	else
		for _, d in ipairs(a:GetDescendants()) do
			if d:IsA("GuiButton") then
				attackClickable = d
				break
			end
		end
	end
	return attackClickable
end

local function pressAttack()
	if not (firesignal or getconnections) then
		if not warnedNoSignal then
			warnedNoSignal = true
			warn("[AE] executor has no firesignal/getconnections, attacking with the remote only")
		end
		return
	end
	local b = resolveAttackButton()
	if not b then
		return
	end
	for _, sn in ipairs(SIGNALS) do
		local ok, sig = pcall(function()
			return b[sn]
		end)
		if ok and sig then
			if firesignal then
				pcall(firesignal, sig)
			else
				local okc, list = pcall(getconnections, sig)
				if okc then
					for _, c in ipairs(list) do
						pcall(function()
							c:Fire()
						end)
					end
				end
			end
		end
	end
end

local FREE_SPOTS = { 1, 2, 4, 5, 7, 8, 10, 11, 13 }

local function myRebirths()
	local v = lp:GetAttribute("Rebirths")
	return type(v) == "number" and v or 0
end

local function spotDisplay(n)
	local m = workspace:FindFirstChild("Training" .. n, true)
	return m and m:FindFirstChild("Display")
end

local function parseNum(s)
	local num, suf = tostring(s):match("(%d[%d,%.]*)%s*([KkMmBb]?)")
	if not num then
		return nil
	end
	local v = tonumber((num:gsub(",", "")))
	if not v then
		return nil
	end
	suf = suf:lower()
	if suf == "k" then
		v = v * 1e3
	elseif suf == "m" then
		v = v * 1e6
	elseif suf == "b" then
		v = v * 1e9
	end
	return v
end

local function isLabel(x)
	return x:IsA("TextLabel") or x:IsA("TextBox") or x:IsA("TextButton")
end

local function spotNeed(n)
	if AE.SpotNeed[n] then
		return AE.SpotNeed[n]
	end
	local d = spotDisplay(n)
	if not d then
		return nil
	end
	local need = d:FindFirstChild("Need", true)
	local mult = d:FindFirstChild("Mult", true)
	if need then
		local items = { need }
		for _, x in ipairs(need:GetDescendants()) do
			items[#items + 1] = x
		end
		for _, x in ipairs(items) do
			if isLabel(x) then
				local v = parseNum(x.Text)
				if v then
					return v
				end
			end
		end
	end
	for _, x in ipairs(d:GetDescendants()) do
		if isLabel(x) and not (mult and (x == mult or x:IsDescendantOf(mult))) then
			local t = x.Text
			if t ~= "" and not t:match("^%s*[Tt]rain%s*%d+%s*$") and not t:match("^%s*[xX]") then
				local v = parseNum(t)
				if v then
					return v
				end
			end
		end
	end
	return nil
end

local function isLocked(n)
	local t = AE.Locked[n]
	return type(t) == "number" and t > os.clock()
end

function AE.PrintSpots()
	print("[AE] my Rebirths =", myRebirths(), " Level =", lp:GetAttribute("Level"), " RebirthLevel =", lp:GetAttribute("RebirthLevel"), " TrainSpot =", lp:GetAttribute("TrainSpot"))
	for _, n in ipairs(FREE_SPOTS) do
		local d = spotDisplay(n)
		local texts = {}
		if d then
			for _, x in ipairs(d:GetDescendants()) do
				if isLabel(x) and x.Text ~= "" then
					texts[#texts + 1] = x.Name .. "=" .. x.Text
				end
			end
		end
		print(("  Training%d need=%s locked=%s texts: %s"):format(
			n, tostring(spotNeed(n)), tostring(isLocked(n)), table.concat(texts, " | ")))
	end
end

local function spotLabel(n)
	local need = spotNeed(n)
	return ("Rebirth %s · Train %d"):format(need and tostring(need) or "?", n)
end

local BEST_LABEL = "Best for my rebirths (auto)"

local function spotOptions()
	local order = {}
	for _, n in ipairs(FREE_SPOTS) do
		order[#order + 1] = n
	end
	table.sort(order, function(a, b)
		local na, nb = spotNeed(a) or math.huge, spotNeed(b) or math.huge
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	local out = { BEST_LABEL }
	for _, n in ipairs(order) do
		out[#out + 1] = spotLabel(n)
	end
	return out
end

local bestCache, bestAt, lastRb, warnedBest = 1, 0, -1, false
local rbChangedAt, verifying, failCount, failSpot = 0, false, 0, nil
local function bestSpot()
	local rb = myRebirths()
	if rb ~= lastRb then
		if lastRb ~= -1 then
			rbChangedAt = os.clock()
		end
		lastRb = rb
		AE.Locked = {}
		failCount, failSpot = 0, nil
		bestAt = 0
	end
	if os.clock() - bestAt < 4 then
		return bestCache
	end
	bestAt = os.clock()
	local best, bestNeed, parsed = 1, -1, false
	for _, n in ipairs(FREE_SPOTS) do
		if not isLocked(n) then
			local need = spotNeed(n)
			if need then
				parsed = true
			end
			local req = need or 0
			if req <= rb and (req > bestNeed or (req == bestNeed and n > best)) then
				best, bestNeed = n, req
			end
		end
	end
	if not parsed and not warnedBest then
		warnedBest = true
		warn("[AE] could not read any Rebirth requirement from the training signs; using the highest spot that accepts me. Run getgenv().AE.PrintSpots() in the executor and send me the output, or fill AE.SpotNeed.")
	end
	bestCache = best
	return best
end

local zoneCache = {}
local function zonePos(n)
	if zoneCache[n] then
		return zoneCache[n]
	end
	local m = workspace:FindFirstChild("Training" .. n, true)
	local z = m and m:FindFirstChild("Zone")
	if z and z:IsA("BasePart") then
		zoneCache[n] = z.Position
		return z.Position
	end
	local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
	return Vector3.new(-62 - 28 * col, 0.2, 38 + 28 * row)
end

local function spotTarget(n)
	return zonePos(n) + Vector3.new(0, 3.4, -8)
end

local function inZone(n)
	local root = myRoot()
	if not root then
		return true
	end
	local z = zonePos(n)
	return (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(z.X, 0, z.Z)).Magnitude <= 5
end

local function tpToSpot(n)
	if verifying then
		return false
	end
	local ok = tpTo(zonePos(n) + Vector3.new(0, 4, 0))
	if ok then
		verifying = true
		task.delay(1.5, function()
			verifying = false
			if not isCurrent() then
				return
			end
			local ts = lp:GetAttribute("TrainSpot")
			if ts == n then
				AE.SpotVerified = true
				failCount, failSpot = 0, nil
			elseif AE.SpotVerified and AE.AutoSpot and n > 1 and ts ~= nil and os.clock() - rbChangedAt >= REBIRTH_GRACE then
				if failSpot ~= n then
					failSpot, failCount = n, 0
				end
				failCount = failCount + 1
				if failCount >= LOCK_FAILS then
					AE.Locked[n] = os.clock() + LOCK_TTL
					failCount, failSpot = 0, nil
					bestAt = 0
					warn(("[AE] Training%d did not accept me (TrainSpot=%s), stepping down for %ds"):format(n, tostring(ts), LOCK_TTL))
				end
			end
		end)
	end
	return ok
end

task.spawn(function()
	while isCurrent() do
		if AE.Farm.Power and not AE.Farm.Stage then
			if AE.AutoSpot then
				AE.Spot = bestSpot()
			end
			if not inZone(AE.Spot) then
				tpToSpot(AE.Spot)
			end
		end
		task.wait(0.25)
	end
end)

local lastTryRb, lastTryAt, warnedRb = -1, 0, false
local function tryRebirth()
	local lv, need = lp:GetAttribute("Level"), lp:GetAttribute("RebirthLevel")
	if type(lv) ~= "number" or type(need) ~= "number" then
		if not warnedRb then
			warnedRb = true
			warn("[AE] Level / RebirthLevel attributes not found, auto rebirth idle")
		end
		return
	end
	if lv < need then
		return
	end
	local rb = myRebirths()
	if rb == lastTryRb and os.clock() - lastTryAt < 3 then
		return
	end
	if invoke("Rebirth") then
		lastTryRb, lastTryAt = rb, os.clock()
	end
end

local function currentWorld()
	return tonumber(lp:GetAttribute("RunWorld")) or tonumber(lp:GetAttribute("World")) or 1
end

local function worldMap(w)
	local m = workspace:FindFirstChild(w == 1 and "Map" or ("Map" .. w))
	if m and (m:GetAttribute("World") == nil or m:GetAttribute("World") == w) and m:FindFirstChild("Stages") then
		return m
	end
	for _, c in ipairs(workspace:GetChildren()) do
		if c:GetAttribute("World") == w and c:FindFirstChild("Stages") then
			return c
		end
	end
	return nil
end

local function stageModel(w, s)
	local m = worldMap(w)
	local st = m and m:FindFirstChild("Stages")
	return st and st:FindFirstChild("Stage" .. s)
end

local function stageCenter(w, s)
	local sm = stageModel(w, s)
	if not sm then
		return nil
	end
	local src = sm:FindFirstChild("Ground") or sm
	local sum, c = Vector3.zero, 0
	local list = src:IsA("BasePart") and { src } or src:GetDescendants()
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			sum = sum + d.Position
			c = c + 1
		end
	end
	return c > 0 and (sum / c) or nil
end

local function padPart(w, s)
	local sm = stageModel(w, s)
	local pg = sm and sm:FindFirstChild("PadGold")
	return pg and (pg:IsA("BasePart") and pg or pg:FindFirstChildWhichIsA("BasePart", true))
end

local function claim(w, s)
	AE.StageRun = { active = false }
	local part = padPart(w, s)
	local before = lp:GetAttribute("Wins")
	if part then
		tpTo(part.Position + Vector3.new(0, 3, 0))
		task.wait(0.2)
		local root = myRoot()
		if root and firetouchinterest then
			pcall(firetouchinterest, root, part, 0)
			pcall(firetouchinterest, root, part, 1)
		end
	else
		warn(("[AE] World %d stage %d: PadGold not found, firing Pad anyway"):format(w, s))
	end
	local n = PAD_GLOBAL and ((w - 1) * 15 + s) or s
	for _ = 1, 2 do
		fire("Pad", n, "gold")
		task.wait(0.1)
	end
	task.wait(0.2)
	print(("[AE] world %d stage %d claimed, Wins %s -> %s"):format(w, s, tostring(before), tostring(lp:GetAttribute("Wins"))))
end

task.spawn(function()
	while isCurrent() do
		if not AE.Farm.Stage then
			AE.StageRun = { active = false }
			task.wait(0.3)
		else
			local w, target = currentWorld(), AE.StageTarget
			local worldChanged = false
			if STAGE_DEBUG then
				print(("[AE] Auto Stage pass: world=%d (RunWorld=%s World=%s) target=%d"):format(w, tostring(lp:GetAttribute("RunWorld")), tostring(lp:GetAttribute("World")), target))
			end
			for s = 1, target do
				if not (isCurrent() and AE.Farm.Stage) then
					break
				end
				local center = stageCenter(w, s)
				local waitStart = os.clock()
				while not center and isCurrent() and AE.Farm.Stage and os.clock() - waitStart < MAP_WAIT and currentWorld() == w do
					task.wait(0.5)
					center = stageCenter(w, s)
				end
				if currentWorld() ~= w then
					worldChanged = true
					AE.StageRun = { active = false }
					break
				end
				if not center then
					warn(("[AE] World %d stage %d not found (map not loaded?), Auto Stage stopped"):format(w, s))
					AE.Farm.Stage = false
					AE.StageRun = { active = false }
					if AE.Notify then
						AE.Notify("Stage not found, stopped", false)
					end
					break
				end
				AE.StageRun = { active = true, center = center, angle = 0, stage = s }
				local t0, clearSince = os.clock(), nil
				local lastProgress, lastCount, lastHp = t0, nil, nil
				local exitReason = "stopped"
				while isCurrent() and AE.Farm.Stage do
					if currentWorld() ~= w then
						exitReason = "world changed"
						worldChanged = true
						break
					end
					local now = os.clock()
					local elapsed = now - t0
					local count, hp = enemyStats()
					if (lastCount and count < lastCount) or (hp and lastHp and hp < lastHp - 0.001) then
						lastProgress = now
					end
					lastCount, lastHp = count, hp
					if elapsed >= STAGE_MIN_TIME then
						if count == 0 then
							clearSince = clearSince or now
							if now - clearSince >= CLEAR_HOLD then
								exitReason = "cleared"
								break
							end
						else
							clearSince = nil
						end
					end
					if now - lastProgress >= STAGE_TIMEOUT then
						exitReason = ("no progress for %ds"):format(STAGE_TIMEOUT)
						break
					end
					if elapsed >= STAGE_HARD_TIMEOUT then
						exitReason = "hard timeout"
						break
					end
					task.wait()
				end
				if STAGE_DEBUG then
					local c2, hp2 = enemyStats()
					print(("[AE] world %d stage %d left: %s | %.1fs | still alive in MyEnemies=%d hp=%s"):format(w, s, exitReason, os.clock() - t0, c2, tostring(hp2)))
					local outside = bossLikeOutsideEnemies()
					if #outside > 0 then
						print("[AE] boss-like objects OUTSIDE MyEnemies: " .. table.concat(outside, " | "))
					end
				end
				if worldChanged then
					AE.StageRun = { active = false }
					break
				end
				if isCurrent() and AE.Farm.Stage and s == target then
					claim(w, s)
				end
			end
			if worldChanged and STAGE_DEBUG then
				print(("[AE] world changed %d -> %d, restarting Auto Stage from stage 1"):format(w, currentWorld()))
			end
			task.wait(0.3)
		end
	end
end)

conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
	if not isCurrent() then
		return
	end
	local root = myRoot()
	local run = AE.StageRun

	if run.active and run.center and root then
		run.angle = (run.angle or 0) + HOVER_SPEED * dt
		root.CFrame = CFrame.new(run.center + Vector3.new(math.cos(run.angle) * HOVER_RADIUS, HOVER_HEIGHT, math.sin(run.angle) * HOVER_RADIUS))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local power = AE.Farm.Power and not AE.Farm.Stage
	if AE.Farm.Rebirth then
		tryRebirth()
	end
	if AE.Farm.Power then
		fire("Train")
	end

	local targets = {}
	if power then
		-- Auto Train: no attack, only Train + TP
	elseif run.active and root then
		targets = nearestEnemies(root, 5)
		if #targets == 0 and run.center then
			targets[1] = { pos = run.center + Vector3.new(0, 3.4, 0) }
		end
	end
	if #targets == 0 then
		return
	end

	local castR = Remotes:FindFirstChild("Cast")
	if not castR or not castR:IsA("RemoteEvent") then
		reportError("RemoteEvent Cast", "missing or wrong class")
		return
	end

	pressAttack()
	local hits = power and AE.FarmHits or AE.StageHits
	local n = #targets
	local ok, err = pcall(function()
		for i = 1, hits do
			local t = targets[(i - 1) % n + 1]
			if t.id then
				castR:FireServer("attack", t.pos, t.id)
			else
				castR:FireServer("attack", t.pos)
			end
		end
	end)
	if not ok then
		reportError("Cast", err)
	end
end)

local STAGE_OPTIONS = {}
for i = 1, 15 do
	STAGE_OPTIONS[i] = "Stage " .. i
end

local System = {
	Name = "AnimeEyes",
	Build = function(UI)
		UI.addCleanup(AE.Unload)
		AE.Notify = UI.Notify

		local Page = UI.CreatePage("Farm")
		UI.CreateTab("Farm", "133509126985362")

		UI.Section(Page, "Power Farm")
		UI.Dropdown(Page, "Training spot", {
			Options = spotOptions,
			Default = BEST_LABEL,
			OnChange = function(v)
				v = tostring(v or "")
				if v == BEST_LABEL or v == "" then
					AE.AutoSpot = true
					return
				end
				local n = tonumber(v:match("Train (%d+)"))
				if n then
					AE.AutoSpot, AE.Spot = false, n
				end
			end,
			Key = "AE:Spot",
		})
		UI.Toggle(Page, "Auto Train (TP + Attack)", AE.Farm.Power, function(on)
			AE.Farm.Power = on
		end)
		UI.Toggle(Page, "Auto Rebirth", AE.Farm.Rebirth, function(on)
			AE.Farm.Rebirth = on
		end)

		UI.Section(Page, "Auto Stage")
		UI.Dropdown(Page, "Target stage", {
			Options = STAGE_OPTIONS,
			Default = "Stage " .. AE.StageTarget,
			OnChange = function(v)
				local n = tonumber(tostring(v or ""):match("%d+"))
				if n and n >= 1 and n <= 15 then
					AE.StageTarget = n
				end
			end,
			Key = "AE:StageTarget",
		})
		UI.Toggle(Page, "Auto Stage", AE.Farm.Stage, function(on)
			AE.Farm.Stage = on
			if not on then
				AE.StageRun = { active = false }
			end
		end)
	end,
}

local okLoad, Lib = pcall(function()
	return loadstring(game:HttpGet(LIB_URL))()
end)
if not okLoad or Lib == nil then
	warn("[AE] could not load LUNAR library: " .. tostring(Lib))
	return
end

local Context = {
	Id = "AnimeEyes",
	GameName = "+1 Anime Eyes",
	Systems = { System },
	Translations = {
		{ en = "Farm", th = "ฟาร์ม" },
		{ en = "Power Farm", th = "ฟามพลัง" },
		{ en = "Training spot", th = "จุดเทรน" },
		{ en = "Best for my rebirths (auto)", th = "ดีที่สุดตาม Rebirth ของฉัน (อัตโนมัติ)" },
		{ en = "Auto Train (TP + Attack)", th = "เทรนอัตโนมัติ (วาร์ป + ตี)" },
		{ en = "Auto Rebirth", th = "รีเบิร์ธอัตโนมัติ" },
		{ en = "Auto Stage", th = "ไต่ด่านอัตโนมัติ" },
		{ en = "Target stage", th = "ด่านปลายทาง" },
	},
}

local started = false
if type(Lib) == "function" then
	started = pcall(Lib, Context)
elseif type(Lib) == "table" then
	for _, n in ipairs({ "Build", "Create", "Init", "Run", "Load", "Start", "Launch", "Open", "new", "New" }) do
		local f = Lib[n]
		if type(f) == "function" and (pcall(f, Context) or pcall(f, Lib, Context)) then
			started = true
			break
		end
	end
end

if not started then
	local keys = {}
	if type(Lib) == "table" then
		for k, v in pairs(Lib) do
			keys[#keys + 1] = tostring(k) .. ":" .. type(v)
		end
	end
	warn("[AE] could not find the library entry point. Returned: " .. typeof(Lib) .. " keys = {" .. table.concat(keys, ", ") .. "}")
else
	print("[AE] loaded.")
end
