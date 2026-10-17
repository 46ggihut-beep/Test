--[[
	AUTO BOUNTY - Blox Fruits (standalone)
	+ Travel trung gian của core.lua: Sea1Gate / Sea2Gate / Sea3Gate / Portal / ShortcutWorth
	+ Check PlaceId -> chỉ dùng travel khi đúng game
	+ Spam skill: Melee + Sword + Fruit + Gun
	Lưu thành  workspace/AutoBounty.lua  để tự chạy lại sau khi hop.
]]

getgenv().Config = getgenv().__BountyResume or {
	Team = "Pirates", -- "Pirates" | "Marines"

	Melee = { Z = true, X = true, C = true },
	Sword = { Z = true, X = true },
	Fruit = { Z = true, X = true, C = true, V = true, F = false },
	Gun = { Z = true, X = true },

	RaceV3 = true,
	RaceV4 = true,

	SaveMode = true,
	HealthPercent = 40, -- 1-80: máu local < % này thì bay lên né

	UseTravel = true, -- dùng travel trung gian (Sea1/2/3 gate)
	UsePortal = false, -- dùng Portal-Portal (cần đang ăn Portal, mastery > 200)
	UseSubmarine = true, -- dùng Submarine teleport (Sea3, cần đã giết boss Tiki)
	HopOverheadSec = 3, -- thời gian "ước tính" mỗi lần qua cổng (giây), càng cao càng ít dùng đường tắt
	PortalOverheadSec = 2,
	RouteMargin = 0, -- cộng thêm vào quãng đường tắt khi so sánh
}
getgenv().__BountyResume = nil

-- hằng số
local ATTACK_RANGE = 50
local SAVE_STEP_Y = 1000
local SAVE_INTERVAL = 5
local RESUME_HP = 80
local TWEEN_SPEED = 200
local MAX_STEP = 18
local RUBBER_DIST = 40
local NEAR_SNAP = 100
local HOLD_TIME = 0.1
local STAND_UP = 5
local STAND_BACK = 3
local HOP_INTERVAL = 0.3
local PVP_OFF_CHECKS = 2
local NO_TARGET_HOP = 10
local START_DELAY = 4
local TARGET_TIMEOUT = 120
local BLACKLIST_TIME = 60
local TRAVEL_MIN_DIST = 1500 -- xa hơn mức này mới xét travel trung gian
local SCRIPT_FILE = "AutoBounty.lua"
local JOBS_FILE = "AutoBounty_Jobs.json"
local KILLED_FILE = "AutoBounty_Killed.json" -- target đã giết, không săn lại

repeat
	task.wait()
until game:IsLoaded() and game:GetService("Players").LocalPlayer

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local LP = Players.LocalPlayer
local env = getgenv()

local function log(...)
	print("[AutoBounty]", ...)
end

env.__AutoBountyRun = (env.__AutoBountyRun or 0) + 1
local RUN_ID = env.__AutoBountyRun
local function alive()
	return env.__AutoBountyRun == RUN_ID
end
env.StopAutoBounty = function()
	env.__AutoBountyRun = (env.__AutoBountyRun or 0) + 1
	env.__BountyAim = nil
end
log("start")

repeat
	task.wait(0.5)
until LP:FindFirstChild("DataLoaded")
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")
local CommE = RS.Remotes:WaitForChild("CommE")
log("data loaded")

local function cfg()
	return env.Config or {}
end

-- ===== CHECK ID GAME =====
local PLACE_IDS = {
	[1] = { [2753915549] = true, [85211729168715] = true },
	[2] = { [4442272183] = true, [79091703265657] = true },
	[3] = { [7449423635] = true, [100117331123089] = true },
}
local SEA = 0
for sea, ids in pairs(PLACE_IDS) do
	if ids[game.PlaceId] then
		SEA = sea
	end
end
if SEA == 0 then
	warn("[AutoBounty] PlaceId " .. tostring(game.PlaceId) .. " không phải Blox Fruits -> tắt travel trung gian")
else
	log("Sea " .. SEA .. " (PlaceId " .. tostring(game.PlaceId) .. ")")
end

pcall(function()
	workspace.StreamingMinRadius = 4000
	workspace.StreamingTargetRadius = 6000
end)

-- state (khai báo sớm để travel dùng)
local state = {
	target = nil,
	saving = false,
	saveCF = nil,
	nextSave = 0,
	engaged = false,
	hopping = false,
	lastGoal = nil,
	lastGoalT = 0,
	lastNear = 0,
	targetSince = 0, -- tick khi chọn target (timeout 120s nếu chưa giết)
	skipRequest = false,
}
local blacklist = {}

local function skipCurrentTarget(reason)
	if state.target then
		blacklist[state.target.Name] = tick() + BLACKLIST_TIME
		log(reason or "skip target:", state.target.Name)
	end
	state.target = nil
	state.lastGoal = nil
	state.targetSince = 0
	state.engaged = false
	state.skipRequest = false
	env.__BountyAim = nil
end

-- ===== target đã giết (lưu file, không săn lại) =====
local killed = {} -- [userId string] = { name, t }
local function loadKilled()
	local ok, data = pcall(function()
		if isfile and isfile(KILLED_FILE) then
			return HttpService:JSONDecode(readfile(KILLED_FILE))
		end
	end)
	if ok and type(data) == "table" then
		killed = data
	end
end
local function saveKilled()
	pcall(function()
		writefile(KILLED_FILE, HttpService:JSONEncode(killed))
	end)
end
local function isKilled(plr)
	if not plr then
		return false
	end
	return killed[tostring(plr.UserId)] ~= nil
end
local function markKilled(plr)
	if not plr then
		return
	end
	local id = tostring(plr.UserId)
	if killed[id] then
		return
	end
	killed[id] = { name = plr.Name, t = os.time() }
	saveKilled()
	log("đã giết, lưu:", plr.Name, "UserId", id, "| total", (function()
		local n = 0
		for _ in pairs(killed) do
			n = n + 1
		end
		return n
	end)())
end
pcall(loadKilled)

-- ===== team =====
local function FireButton(b)
	b.Selectable = true
	game:GetService("GuiService").SelectedObject = b
	VIM:SendKeyEvent(true, "Return", false, b)
	VIM:SendKeyEvent(false, "Return", false, b)
end
local function hasTeam()
	local t = LP.Team
	return t ~= nil and (t.Name == "Pirates" or t.Name == "Marines")
end
local function wantTeam()
	local t = tostring(cfg().Team or "Pirates"):lower()
	return t:sub(1, 1) == "m" and "Marines" or "Pirates"
end
local function ensureTeam()
	local want = wantTeam()
	if hasTeam() and LP.Team.Name == want then
		return true
	end
	if not hasTeam() then
		local t1 = tick()
		repeat
			task.wait(0.5)
			pcall(function()
				local pg = LP.PlayerGui
				local main = pg:FindFirstChild("Main (minimal)") or pg:FindFirstChild("Main")
				local choose = main and main:FindFirstChild("ChooseTeam")
				if choose then
					FireButton(choose.Container[want].Frame.TextButton)
				end
			end)
		until hasTeam() or tick() - t1 > 10
		game:GetService("GuiService").SelectedObject = nil
	end
	if not (hasTeam() and LP.Team.Name == want) then
		pcall(function()
			CommF:InvokeServer("SetTeam", want)
		end)
	end
	return hasTeam() and LP.Team.Name == want
end

local function waitUIReady(timeout)
	local t1 = tick()
	repeat
		task.wait(0.5)
		local ok, ready = pcall(function()
			local pg = LP.PlayerGui
			if pg:FindFirstChild("LoadingScreen") or not hasTeam() then
				return false
			end
			local main = pg:FindFirstChild("Main")
			if not main or not main:FindFirstChild("BottomHUDList") or not main:FindFirstChild("Skills") then
				return false
			end
			for _, name in ipairs({ "Main", "Main (minimal)" }) do
				local g = pg:FindFirstChild(name)
				local choose = g and g:FindFirstChild("ChooseTeam")
				if choose and choose.Visible then
					return false
				end
			end
			local char = LP.Character
			return char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil
		end)
		if ok and ready then
			return true
		end
	until tick() - t1 > (timeout or 60)
	return false
end

-- ===== tween =====
local tpUntil, tpTagged = 0, false
local function tagTeleporting()
	tpUntil = tick() + 1.5
	if not CS:HasTag(LP, "Teleporting") then
		CS:AddTag(LP, "Teleporting")
		tpTagged = true
	end
end
task.spawn(function()
	while task.wait(0.1) do
		if tpTagged and tick() >= tpUntil then
			CS:RemoveTag(LP, "Teleporting")
			tpTagged = false
		end
	end
end)

local noclipOn = false
env.__BountyNoclip = env.__BountyNoclip
	or RunService.Stepped:Connect(function()
		if not noclipOn or not alive() then
			return
		end
		local char = LP.Character
		if not char then
			return
		end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				p.CanCollide = false
			end
		end
	end)

local function getHRP()
	local c = LP.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function ensureFloat(hrp)
	if hrp:FindFirstChild("FloatForce") then
		return
	end
	local bv = Instance.new("BodyVelocity")
	bv.Name = "FloatForce"
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.MaxForce = Vector3.new(100000, 100000, 100000)
	bv.P = 10000
	bv.Parent = hrp
end

local Tw = { token = 0, lastTP = 0, lastCF = nil, cap = 1000, nextRaise = 0 }
local function cancelTween()
	Tw.token = Tw.token + 1
end

local function tweenTo(cf, speed)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	if tick() - Tw.lastTP < 1 and Tw.lastCF == cf then
		return
	end
	cancelTween()
	local token = Tw.token
	Tw.lastTP, Tw.lastCF = tick(), cf
	speed = math.max(tonumber(speed) or TWEEN_SPEED, 1)
	task.spawn(function()
		local goalPos = cf.Position
		local pos = hrp.Position
		local lastSet
		while Tw.token == token and alive() do
			local c = LP.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if c ~= char or hrp.Parent ~= c or not h or h.Health <= 0 or hrp.Anchored then
				break
			end
			if (goalPos - pos).Magnitude <= 2.5 then
				break
			end
			local dt = RunService.Heartbeat:Wait()
			local real = hrp.Position
			if lastSet and (real - lastSet).Magnitude > RUBBER_DIST then
				Tw.cap = math.max(Tw.cap * 0.7, 120)
				Tw.nextRaise = tick() + 3
				pos = real
			end
			local diff = goalPos - pos
			local dist = diff.Magnitude
			local step = math.min(math.min(speed, Tw.cap) * dt, MAX_STEP)
			if dist > step and tick() >= Tw.nextRaise then
				Tw.cap = math.min(Tw.cap * 1.08, speed)
				Tw.nextRaise = tick() + 1.5
			end
			if dist <= step or dist <= 0.05 then
				pos = goalPos
			else
				pos = pos + diff / dist * step
			end
			tagTeleporting()
			noclipOn = true
			hrp.CFrame = CFrame.new(pos)
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			lastSet = pos
		end
		if Tw.token == token and hrp.Parent == LP.Character and (goalPos - hrp.Position).Magnitude <= 2.5 then
			hrp.CFrame = cf
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end
	end)
end

-- ===== weapon / skill (Melee + Sword + Fruit + Gun) =====
local CATS = {
	{ "Melee", "Melee" },
	{ "Sword", "Sword" },
	{ "Fruit", "Blox Fruit" },
	{ "Gun", "Gun" },
}
local KEYS = { "Z", "X", "C", "V", "F" }
local castIdx = 0 -- xoay vòng category để Gun cũng được spam

local function toSet(t)
	local s = {}
	if type(t) ~= "table" then
		return s
	end
	for k, v in pairs(t) do
		if type(k) == "number" and type(v) == "string" then
			s[v:upper()] = true
		elseif type(k) == "string" and v then
			s[k:upper()] = true
		end
	end
	return s
end

local function NameWeapon(tip)
	for _, box in ipairs({ LP.Backpack, LP.Character }) do
		if box then
			for _, t in ipairs(box:GetChildren()) do
				if t:IsA("Tool") and t.ToolTip == tip then
					return t
				end
			end
		end
	end
end

local function equiptool(name)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Sit then
		return
	end
	if char:FindFirstChild(name) then
		return
	end
	local tool = LP.Backpack and LP.Backpack:FindFirstChild(name)
	if tool then
		hum:EquipTool(tool)
	end
end

local function skillsGui()
	local main = LP.PlayerGui:FindFirstChild("Main")
	return main and main:FindFirstChild("Skills")
end

local function skillReady(tool, key)
	local gui = skillsGui()
	local box = gui and gui:FindFirstChild(tool.Name)
	local f = box and box:FindFirstChild(key)
	if not f or not f:IsA("Frame") or f.Name == "Template" then
		return false
	end
	local ok, ready = pcall(function()
		local title = f.Title
		local cd = f.Cooldown
		if not title or not cd then
			return false
		end
		if string.find(title.Text, "Transformation") then
			return false
		end
		if title.TextColor3 ~= Color3.new(1, 1, 1) then
			return false
		end
		-- core: sẵn sàng khi cooldown size = (0,0,1,-1) hoặc (1,0,1,-1)
		local sz = cd.Size
		return sz == UDim2.new(0, 0, 1, -1) or sz == UDim2.new(1, 0, 1, -1)
	end)
	return ok and ready
end

local function castSkillOnTool(tool, set)
	local gui = skillsGui()
	if not gui then
		return false
	end
	if not gui:FindFirstChild(tool.Name) then
		equiptool(tool.Name)
		return true -- đợi frame sau skill UI hiện
	end
	for _, key in ipairs(KEYS) do
		if set[key] and skillReady(tool, key) then
			equiptool(tool.Name)
			local char = LP.Character
			if char and char:FindFirstChild(tool.Name) then
				VIM:SendKeyEvent(true, key, false, game)
				task.wait(HOLD_TIME)
				VIM:SendKeyEvent(false, key, false, game)
				return true
			end
		end
	end
	return false
end

-- xoay vòng Melee/Sword/Fruit/Gun mỗi lần gọi
local function castOne()
	local c = cfg()
	local n = #CATS
	for i = 1, n do
		castIdx = (castIdx % n) + 1
		local cat = CATS[castIdx]
		local set = toSet(c[cat[1]])
		if next(set) then
			local tool = NameWeapon(cat[2])
			if tool and castSkillOnTool(tool, set) then
				return true
			end
		end
	end
	return false
end

local function holdWeapon()
	for _, tip in ipairs({ "Melee", "Sword", "Blox Fruit", "Gun" }) do
		local tool = NameWeapon(tip)
		if tool then
			equiptool(tool.Name)
			return
		end
	end
end

-- ===== TRAVEL TRUNG GIAN (port từ core.lua) =====
local function stopped()
	return not alive() or state.hopping
end

local function keepFly()
	tagTeleporting()
	noclipOn = true
end

local function charAlive()
	local c = LP.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and getHRP() ~= nil
end

local function flyPos(pos, radius, timeout)
	radius = radius or 15
	local t0 = tick()
	while tick() - t0 < (timeout or 90) do
		if stopped() or not charAlive() then
			return false
		end
		local hrp = getHRP()
		if (hrp.Position - pos).Magnitude < radius then
			return true
		end
		ensureFloat(hrp)
		keepFly()
		tweenTo(CFrame.new(pos), TWEEN_SPEED)
		task.wait(0.15)
	end
	return false
end

local function hold(t)
	local t0 = tick()
	while tick() - t0 < t do
		if stopped() then
			return
		end
		keepFly()
		task.wait(0.1)
	end
end

-- gọi requestEntrance liên tục tới khi bị dịch chuyển > minMove
local function useEntrance(ent, timeout, minMove)
	local hrp = getHRP()
	if not hrp then
		return false
	end
	local before = hrp.Position
	local t0 = tick()
	while tick() - t0 < (timeout or 20) and not stopped() do
		keepFly()
		pcall(function()
			CommF:InvokeServer("requestEntrance", ent)
		end)
		task.wait(0.2)
		local h = getHRP()
		if not h then
			return false
		end
		if (h.Position - before).Magnitude > (minMove or 100) then
			return true
		end
	end
	return false
end

local function shortcutWorth(direct, viaFly, overheadSec)
	local margin = tonumber(cfg().RouteMargin) or 0
	return viaFly + (overheadSec or 0) * TWEEN_SPEED + margin < direct
end

local unlockCache, unlockLast = {}, {}
local function isUnlocked(flag)
	if unlockCache[flag] then
		return true
	end
	if tick() - (unlockLast[flag] or 0) < 10 then
		return false
	end
	unlockLast[flag] = tick()
	local ok, res = pcall(function()
		return CommF:InvokeServer("GetUnlockables")
	end)
	if ok and type(res) == "table" and res[flag] then
		unlockCache[flag] = true
	end
	return unlockCache[flag] == true
end

local tikiCache, tikiAsk = false, 0
local function isTikiBossKilled()
	if tikiCache then
		return true
	end
	if tick() - tikiAsk < 5 then
		return false
	end
	tikiAsk = tick()
	local ok, res = pcall(function()
		local ev = RS.Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak")
		return ev and ev:InvokeServer("AskKilledTikiBoss")
	end)
	if ok and res == true then
		tikiCache = true
	end
	return tikiCache
end

-- gate dùng chung cho Sea1/Sea2: bay tới điểm chờ rồi requestEntrance
local gst = { cool = 0, attemptStart = nil, attempts = 0, cloudSkip = setmetatable({}, { __mode = "k" }) }
local function gate(waitPos, entrancePos, after)
	if tick() < gst.cool then
		return false
	end
	if not flyPos(waitPos, 15, 120) then
		return true
	end
	hold(0.3)
	local now = tick()
	if not gst.attemptStart or now - gst.attemptStart > 60 then
		gst.attemptStart, gst.attempts = now, 0
	end
	gst.attempts = gst.attempts + 1
	if gst.attempts > 5 then
		gst.cool, gst.attemptStart = now + 30, nil
		return false
	end
	useEntrance(entrancePos, 20, 100)
	if after then
		pcall(after)
	end
	return true
end

local function lift(cond, dy)
	return function()
		local hrp = getHRP()
		if hrp and cond(hrp.Position) then
			hrp.CFrame = hrp.CFrame + Vector3.new(0, dy, 0)
		end
	end
end

-- ---------- Sea 1 ----------
local S1 = {
	SKY2_POS = Vector3.new(-4210, 1092, -374),
	SKY_START_POS = Vector3.new(-6022, 5485, 2222),
	SKY_ENTRANCE_POS = Vector3.new(-4166.60986328125, 1093.697998046875, -347.16226196289062),
	UNDER_WAIT_POS = Vector3.new(4047, 10, -1816),
	UNDER_ENTRANCE_POS = Vector3.new(61163.8515625, 11.680007934570312, 1819.7840576171875),
	XOAY_WAIT_POS = Vector3.new(61170, 10, 1955),
	XOAY_ENTRANCE_POS = Vector3.new(3864.68798828125, 6.73699951171875, -1926.2139892578125),
	SKY3_Y = 4000,
	UNDER_X = 40000,
	CLOUD_RANGE = 50,
	CLOUD_REACH = 10,
	CLOUD_ENTRANCE_POS = Vector3.new(-6023.57666015625, 5469.7197265625, 2203.308349609375),
	CLOUD_SKIP_TIME = 10,
	CLOUD_INTERVAL = 0.1,
}
local function s1Zone(pos)
	if pos.X > S1.UNDER_X then
		return "Under"
	end
	if pos.Y > S1.SKY3_Y then
		return "Sky3"
	end
	return "Main"
end
local function cloudPos(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		return obj:GetPivot().Position
	end
end
local function pickCloud(hrp)
	local map = workspace:FindFirstChild("Map")
	local sky = map and map:FindFirstChild("Sky")
	if not sky then
		return nil
	end
	local now = tick()
	local best, bestD
	for _, obj in ipairs(sky:GetChildren()) do
		if obj.Name:lower() == "cloud" and (gst.cloudSkip[obj] or 0) < now then
			local pos = cloudPos(obj)
			if pos and (pos - S1.SKY2_POS).Magnitude <= S1.CLOUD_RANGE then
				local d = (pos - hrp.Position).Magnitude
				if not bestD or d < bestD then
					best, bestD = obj, d
				end
			end
		end
	end
	return best
end
local function clickScreen()
	local vp = workspace.CurrentCamera.ViewportSize
	local x, y = vp.X * 0.15, vp.Y * 0.15
	VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
	VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
end
local function climbSky3()
	if not flyPos(S1.SKY2_POS, 60, 120) then
		return true
	end
	local target
	local t0, lastEquip = tick(), 0
	while not stopped() and tick() - t0 < 90 do
		local hrp = getHRP()
		if not hrp or not charAlive() or hrp.Position.Y > S1.SKY3_Y then
			break
		end
		keepFly()
		if tick() - lastEquip >= 0.5 then
			lastEquip = tick()
			pcall(function()
				local hum = LP.Character:FindFirstChildOfClass("Humanoid")
				local tool = NameWeapon("Melee")
				if hum and tool and not hum.Sit and tool.Parent ~= LP.Character then
					hum:EquipTool(tool)
				end
			end)
		end
		if not target or not target.Parent then
			target = pickCloud(hrp)
		end
		local pos = target and cloudPos(target)
		if pos then
			if (hrp.Position - pos).Magnitude > S1.CLOUD_REACH then
				ensureFloat(hrp)
				tweenTo(CFrame.new(pos), TWEEN_SPEED)
			else
				gst.cloudSkip[target] = tick() + S1.CLOUD_SKIP_TIME
				target = nil
				pcall(clickScreen)
				task.wait(0.15)
				keepFly()
				pcall(function()
					CommF:InvokeServer("requestEntrance", S1.CLOUD_ENTRANCE_POS)
				end)
				task.wait(0.3)
			end
		else
			target = nil
			if (hrp.Position - S1.SKY2_POS).Magnitude > 15 then
				ensureFloat(hrp)
				tweenTo(CFrame.new(S1.SKY2_POS), TWEEN_SPEED)
			end
		end
		task.wait(S1.CLOUD_INTERVAL)
	end
	return true
end
local function sea1Step(hrp, tpos)
	local pz, tz = s1Zone(hrp.Position), s1Zone(tpos)
	if pz == tz then
		return false
	end
	noclipOn = true
	if pz == "Under" then
		return gate(S1.XOAY_WAIT_POS, S1.XOAY_ENTRANCE_POS)
	elseif pz == "Sky3" then
		return gate(S1.SKY_START_POS, S1.SKY_ENTRANCE_POS, lift(function(p)
			return p.Y < S1.SKY3_Y
		end, 30))
	elseif tz == "Sky3" then
		return climbSky3()
	elseif tz == "Under" then
		return gate(S1.UNDER_WAIT_POS, S1.UNDER_ENTRANCE_POS)
	end
	return false
end

-- ---------- Sea 2 ----------
local C2 = {
	MANSION_WAIT = Vector3.new(-287, 328, 591),
	MANSION_ENTRANCE = Vector3.new(-286.9859619140625, 306.13739013671875, 597.8905029296875),
	ROOM_WAIT = Vector3.new(2285, 42, 911),
	ROOM_ENTRANCE = Vector3.new(2284.9091796875, 15.537796020507812, 905.4727783203125),
	MANSION_R = 900,
	MANSION_MIN_Y = 200,
	ROOM_R = 600,
	DOOR_WAIT = Vector3.new(-6498, 106, -119),
	SHIP_ENTRANCE = Vector3.new(923.2130126953125, 126.97599792480469, 32852.83203125),
	SHIP_WAIT = Vector3.new(923, 125, 32853),
	DOOR_ENTRANCE = Vector3.new(-6508.55810546875, 89.035003662109375, -132.83999633789062),
	SHIP_Z = 20000,
}
local function horiz(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function flamZone(pos)
	if pos.Y > C2.MANSION_MIN_Y and horiz(pos, C2.MANSION_WAIT) < C2.MANSION_R then
		return "Mansion"
	end
	if horiz(pos, C2.ROOM_WAIT) < C2.ROOM_R then
		return "Room"
	end
	return nil
end
local function sea2Step(hrp, tpos)
	local pos = hrp.Position
	local pShip, tShip = pos.Z > C2.SHIP_Z, tpos.Z > C2.SHIP_Z
	if pShip ~= tShip then
		noclipOn = true
		if tShip then
			return gate(C2.DOOR_WAIT, C2.SHIP_ENTRANCE, lift(function(p)
				return p.Z > C2.SHIP_Z
			end, 60))
		end
		return gate(C2.SHIP_WAIT, C2.DOOR_ENTRANCE, lift(function(p)
			return p.Z < C2.SHIP_Z
		end, 30))
	end
	if pShip then
		return false
	end
	if not isUnlocked("FlamingoAccess") then
		return false
	end
	local tz = flamZone(tpos)
	if tz then
		local dM = (pos - C2.MANSION_WAIT).Magnitude
		local dR = (pos - C2.ROOM_WAIT).Magnitude
		if tz == "Mansion" and dR < dM then
			noclipOn = true
			return gate(C2.ROOM_WAIT, C2.MANSION_ENTRANCE, lift(function(p)
				return flamZone(p) == "Mansion"
			end, 30))
		elseif tz == "Room" and dM < dR then
			noclipOn = true
			return gate(C2.MANSION_WAIT, C2.ROOM_ENTRANCE, lift(function(p)
				return flamZone(p) == "Room"
			end, 30))
		end
	end
	return false
end

-- ---------- Sea 3 (Castle / Hydra / Mansion / Tiki) ----------
local V3 = Vector3.new
local TEMPLE = V3(28282.5703125, 14896.8505859375, 105.1042709350586)
local HOP = {
	["Castle>Hydra"] = { to = "Hydra", fly = V3(-5027.0302734375, 330, -3206.70361328125), ent = V3(5662, 1013, -338), need = "indra" },
	["Hydra>Castle"] = { to = "Castle", fly = V3(5659, 1030, -334), ent = V3(-5021, 314, -3194), need = "indra" },
	["Mansion>Castle"] = { to = "Castle", fly = V3(-12463.6025390625, 398, -7566.0830078125), ent = V3(-5055, 314, -3179), need = "indra" },
	["Castle>Mansion"] = { to = "Mansion", fly = V3(-5060.41162109375, 330, -3193.224853515625), ent = V3(-12465, 374, -7554), need = "indra" },
	["Tiki>Castle"] = { to = "Castle", fly = V3(-16800, 59, 291), jump = "Castle", need = "tiki" },
	["Castle>Tiki"] = { to = "Tiki", fly = V3(-5098, 316, -3179), jump = "Tiki", need = "tiki" },
	["Tiki>Submerged"] = { to = "Submerged", fly = V3(-16269.4082, 23.9799957, 1371.66235), sub = true, need = "tiki" },
}
-- Submarine: pocket Submerged Island + NPC thoát + các đảo có thể tele tới
local SUB_POCKET = V3(11538.6, -2154.7, 9827.3)
local SUB_NPC = V3(11427.9189, -2156.36401, 9726.24023)
local CAKE_ARENA = V3(-1990.67, 4532.97, -14973.67)
local SUB_ISLANDS = {
	["Turtle Mountain"] = V3(-9537, 7, -8348),
	["Hydra Town"] = V3(3251, 5, 2431),
	["Chocolate Land"] = V3(-155, 7, -11938),
	["Sea Castle"] = V3(-6071, 16, -2155),
	["Haunted Castle"] = V3(-9517, 20, 4565),
	["Port"] = V3(6, 10, 5397),
	["Peanut Land"] = V3(-2041, 4, -9826),
	["Great Tree"] = V3(2041, 21, -6525),
	["Ice Cream Land"] = V3(-1007, 7, -10745),
	["Cake Land"] = V3(-1989, 9, -11411),
}
local LIFT = 100
local REFS = {
	Hydra = { V3(3399, 72, 1572), V3(5245, 602, 251), V3(5288, 1011, 392), V3(5661, 1013, -334), V3(5659, 1030, -334) },
	Castle = { V3(-5500, 314, -2855), V3(-5055, 314, -3179), V3(-5027, 318, -3206), V3(-5060, 330, -3193), V3(-5098, 316, -3179) },
	Mansion = {
		V3(-12463, 375, -7549), V3(-12548, 337, -7481), V3(-12463.6, 398, -7566),
		V3(-12538, 339, -7817), V3(-12008, 339, -9179), V3(-10164, 340, -8321), V3(-12857, 853, -10715),
	},
	Tiki = { V3(-16204, 9, 479), V3(-16456, 530, 436), V3(-16800, 59, 291) },
}
local function minDist(pos, refs)
	local m = math.huge
	for _, r in ipairs(refs) do
		local d = (pos - r).Magnitude
		if d < m then
			m = d
		end
	end
	return m
end
local function nearestHub(pos)
	local best, bd
	for name, refs in pairs(REFS) do
		local d = minDist(pos, refs)
		if not bd or d < bd then
			best, bd = name, d
		end
	end
	return best
end
local function hubOpen(name)
	if name == "Castle" then
		return true
	end
	local need = HOP["Castle>" .. name].need
	if need == "indra" then
		return isUnlocked("DefeatedIndraTrueForm")
	end
	if need == "tiki" then
		return isTikiBossKilled()
	end
	return true
end
local function nearestOpenHub(pos)
	local best, bd
	for name, refs in pairs(REFS) do
		if hubOpen(name) then
			local d = minDist(pos, refs)
			if not bd or d < bd then
				best, bd = name, d
			end
		end
	end
	return best
end
local function inPocket(pos)
	return (pos - SUB_POCKET).Magnitude <= 3000
end
local function nearestNode(pos, onlyOpen)
	if (pos - CAKE_ARENA).Magnitude <= 1000 then
		return "Cake Land"
	end
	local best, bd
	for name, p in pairs(SUB_ISLANDS) do
		local d = (pos - p).Magnitude
		if not bd or d < bd then
			best, bd = name, d
		end
	end
	for name, refs in pairs(REFS) do
		if not onlyOpen or hubOpen(name) then
			local d = minDist(pos, refs)
			if not bd or d < bd then
				best, bd = name, d
			end
		end
	end
	return best
end
-- đảo submarine gần đích nhất (nil nếu tắt / chưa giết boss Tiki / đích gần hub hơn)
local function subDest(pos)
	if cfg().UseSubmarine == false or not isTikiBossKilled() then
		return nil
	end
	local best = nearestNode(pos, true)
	if SUB_ISLANDS[best] then
		return best
	end
	return nil
end
-- thoát Submerged Island: bay tới NPC rồi InitiateTeleport
local function subExit(island)
	if not flyPos(SUB_NPC, 8, 90) then
		return false
	end
	hold(0.3)
	if island then
		task.wait(0.6)
	end
	local hrp = getHRP()
	if not hrp then
		return false
	end
	local before = hrp.Position
	local net = RS.Modules.Net
	pcall(function()
		net:FindFirstChild("RF/SubmarineTransportation"):InvokeServer("GetAvailableLocations")
	end)
	pcall(function()
		net:FindFirstChild("RF/SubmarineTransportation"):InvokeServer("InitiateTeleport", island or "Tiki Outpost")
	end)
	local t0 = tick()
	while tick() - t0 < 10 and not stopped() do
		task.wait(0.3)
		local h = getHRP()
		if h and (h.Position - before).Magnitude > 500 then
			return true
		end
	end
	return false
end
local function route(ph, dh)
	local hops = {}
	if ph ~= "Castle" then
		hops[#hops + 1] = ph .. ">Castle"
	end
	if dh ~= "Castle" then
		hops[#hops + 1] = "Castle>" .. dh
	end
	return hops
end
local function landingOf(h)
	if h.ent then
		return h.ent + V3(0, LIFT, 0)
	end
	local r = REFS[h.to]
	return r and r[1] or h.fly
end
local function routeFlyDist(pos, hops, tpos, island)
	local cur, dist = pos, 0
	for _, key in ipairs(hops) do
		local h = HOP[key]
		dist = dist + (cur - h.fly).Magnitude
		cur = h.sub and SUB_POCKET or landingOf(h)
	end
	if island and SUB_ISLANDS[island] then
		dist = dist + (cur - SUB_NPC).Magnitude
		cur = SUB_ISLANDS[island]
	end
	return dist + (cur - tpos).Magnitude
end
local function doJump()
	local ch = LP.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	keepFly()
	hum.Jump = true
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	VIM:SendKeyEvent(true, "Space", false, game)
	task.wait(0.1)
	VIM:SendKeyEvent(false, "Space", false, game)
end
local function jumpUntilNear(name, timeout)
	local t0 = tick()
	while tick() - t0 < (timeout or 25) and not stopped() do
		local hrp = getHRP()
		if not hrp then
			return false
		end
		if nearestHub(hrp.Position) == name then
			return true
		end
		doJump()
		hold(0.6)
	end
	return false
end
local function runHop(h)
	if not flyPos(h.fly) then
		return false
	end
	hold(h.jump and 0.6 or 0.3)
	if h.sub then
		local b0 = getHRP()
		b0 = b0 and b0.Position
		local moved = false
		local t0 = tick()
		while tick() - t0 < 30 and not stopped() do
			keepFly()
			pcall(function()
				RS.Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak"):InvokeServer("TravelToSubmergedIsland")
			end)
			pcall(function()
				CommF:InvokeServer("SetLastSpawnPoint", "SubmergedIsland")
			end)
			hold(0.2)
			local c0 = getHRP()
			if c0 and b0 and (c0.Position - b0).Magnitude > 500 then
				moved = true
				break
			end
		end
		return moved
	end
	if h.ent then
		if not useEntrance(h.ent, 30, 500) then
			return false
		end
	else
		if not jumpUntilNear(h.jump) then
			return false
		end
		hold(0.6)
	end
	local hrp = getHRP()
	if not hrp then
		return false
	end
	hrp.CFrame = hrp.CFrame + Vector3.new(0, LIFT, 0)
	return nearestHub(hrp.Position) == h.to
end

local s3running, s3cool, s3fails = false, 0, 0
local function sea3Step(hrp, tpos)
	if s3running then
		return true
	end
	if tick() < s3cool then
		return false
	end
	local pos = hrp.Position
	if (tpos - TEMPLE).Magnitude <= 3000 or (pos - TEMPLE).Magnitude <= 3000 then
		return false
	end
	-- đang ở Submerged Island: thoát bằng NPC submarine
	if inPocket(pos) then
		if inPocket(tpos) then
			return false
		end
		s3running = true
		noclipOn = true
		local ok, res = pcall(subExit, subDest(tpos))
		s3running = false
		if not (ok and res) then
			s3cool = tick() + 10
		end
		return true
	end
	local island = subDest(tpos)
	local hops
	if island or inPocket(tpos) then
		if island and nearestNode(pos) == island then
			return false
		end
		local ph = nearestHub(pos)
		hops = {}
		if ph ~= "Tiki" then
			if ph ~= "Castle" then
				hops[#hops + 1] = ph .. ">Castle"
			end
			hops[#hops + 1] = "Castle>Tiki"
		end
		hops[#hops + 1] = "Tiki>Submerged"
	else
		local dh, ph = nearestOpenHub(tpos), nearestHub(pos)
		if not dh or ph == dh then
			return false
		end
		hops = route(ph, dh)
	end
	for _, key in ipairs(hops) do
		local need = HOP[key].need
		if need == "indra" and not isUnlocked("DefeatedIndraTrueForm") then
			return false
		end
		if need == "tiki" and not isTikiBossKilled() then
			return false
		end
	end
	local direct = (pos - tpos).Magnitude
	local viaFly = routeFlyDist(pos, hops, tpos, island)
	local steps = #hops + (island and 1 or 0)
	if not shortcutWorth(direct, viaFly, steps * (tonumber(cfg().HopOverheadSec) or 3)) then
		return false
	end
	s3running = true
	noclipOn = true
	local allOk = true
	for _, key in ipairs(hops) do
		local ok, res = pcall(runHop, HOP[key])
		if not (ok and res) then
			allOk = false
			break
		end
	end
	s3running = false
	if allOk then
		s3fails = 0
	else
		s3fails = s3fails + 1
		if s3fails >= 2 then
			s3fails = 0
			s3cool = tick() + 30
		end
	end
	return true
end

-- ---------- Portal-Portal (tùy chọn) ----------
local PORTAL = {
	Sea1 = {
		Colosseum = V3(-2143.41333, 152.074326, -3025.54614), Desert = V3(1330.68298, 103.55368, 4489.30615),
		Fountain = V3(5420.33643, 431.04068, 4396.38721), Jungle = V3(-1340.21948, 136.020538, -101.374214),
		["Marine Fortress"] = V3(-5180.23828, 281.343445, 4383.03174), ["Middle Town"] = V3(-703.16748, 9.55188751, 1575.1864),
		["Pirate Village"] = V3(-807.662109, 27.8020515, 4119.30127), Prison = V3(5270.56934, 163.508469, 844.72821),
		Sky = V3(-4808.76904, 721.326355, -2668.81787), Snow = V3(1394.46399, 39.0448875, -1321.63904),
		["Starter Island"] = V3(1038.29968, 112.1365051, 1287.83447), ["Starter Marine"] = V3(-3096.51929, 231.443558, 2087.51929),
		Underwater = V3(61147.9766, 20.5708408, 1366.09839), ["Upper Sky"] = V3(-7950.03662, 5815.68457, -1968.3374),
		Volcano = V3(-5513.97852, 64.4943161, 8577.40039),
	},
	Sea2 = {
		Cafe = V3(-382, 74, 356), Colosseum = V3(-1836, 46, 1642), ["Dark Arena"] = V3(3948, 13, -3479),
		["Docks 1"] = V3(-923, 8, 1810), ["Docks 2"] = V3(-13, 39, 2708), ["Docks 3"] = V3(-1944, 9, -2594),
		["Docks 4"] = V3(-5798, 1, -5021), Doghouse = V3(-1984, 125, -82), Graveyard = V3(-5710, 126, -775),
		["Haunted Ship"] = V3(937, 125, 32879), Lab = V3(-5542, 335, -5924), Lava = V3(-5280, 7, -5618),
		Mansion = V3(-494, 339, 593), Raid = V3(-6503, 251, -4495), Remote = V3(4766, 8, 2911),
		Skull = V3(-2956.24341, 123.399323, -9981.06934), Snow = V3(1210, 429, -4663),
		["Winter Castle"] = V3(5544.71777, 60.1393852, -6359.08887),
	},
	Sea3 = {
		["Cake Land"] = V3(-2098.970458984375, 76.39494323730469, -12128.359375),
		["Chocolate Land"] = V3(379.1396179199219, 130.20599365234375, -12720.83984375),
		["Great Tree"] = V3(4345.09375, 575.0524291992188, -6159.00439453125),
		["Haunted Castle"] = V3(-9515.0009765625, 149.18876647949, 5534.0502929688),
		["Hydra Arena"] = V3(5020.94580078125, 174.08645629882812, -2011.18505859375),
		["Hydra Town"] = V3(5288.62158203125, 1011.6527709960938, 392.4296875),
		["Ice Cream Land"] = V3(-917.54852294922, 63.364143371582, -10858.696289062),
		["Peanut Land"] = V3(-2037.8001708984, 13.651118278503, -9948.2021484375),
		Port = V3(-342.4343566894531, 23.8315486907959, 5547.345703125),
		["Sea Castle"] = V3(-5502.1787109375, 323.6708984375, -2863.4616699219),
		["Tiki Outpost"] = V3(-16456.4629, 530.251953, 436.231812),
		["Turtle Center"] = V3(-12007.979492188, 339.15548706055, -9178.580078125),
		["Turtle Entrance"] = V3(-10163.96484375, 340.29028320313, -8320.767578125),
		["Turtle Mansion"] = V3(-12538.421875, 339.39358520508, -7817.0708007813),
		["Turtle Mountain"] = V3(-12856.61328125, 852.75360107422, -10715.23046875),
	},
}
local function portalToolGet()
	return (LP.Character and LP.Character:FindFirstChild("Portal-Portal")) or LP.Backpack:FindFirstChild("Portal-Portal")
end
local function portalReady()
	local data = LP.Data:FindFirstChild("DevilFruit")
	if not data or data.Value ~= "Portal-Portal" then
		return false
	end
	local tool = portalToolGet()
	if not tool or not tool:FindFirstChild("Level") or tool.Level.Value <= 200 then
		return false
	end
	local skills = skillsGui()
	local box = skills and skills:FindFirstChild("Portal-Portal")
	local f = box and box:FindFirstChild("C")
	if not f or not f:IsA("Frame") then
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:EquipTool(tool)
		end
		return false
	end
	local cd = f:FindFirstChild("Cooldown")
	return cd ~= nil
		and f.Title.TextColor3 == Color3.new(1, 1, 1)
		and (cd.Size == UDim2.new(0, 0, 1, -1) or cd.Size == UDim2.new(1, 0, 1, -1))
end
local function portalGo(name)
	local tool = portalToolGet()
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if not tool or not hum then
		return false
	end
	hum:EquipTool(tool)
	local gw = LP.PlayerGui.Main:FindFirstChild("Gateway")
	if not gw then
		return false
	end
	VIM:SendKeyEvent(true, "C", false, game)
	VIM:SendKeyEvent(false, "C", false, game)
	local t1 = tick() + 3
	repeat
		task.wait(0.1)
	until gw.Visible or tick() > t1
	if not gw.Visible then
		return false
	end
	local mc = gw:FindFirstChild("MainContent")
	local btn = mc and mc.ScrollingFrame:FindFirstChild(tostring(name))
	if btn and btn.MouseButton1Click then
		for _, c in pairs(getconnections(btn.MouseButton1Click)) do
			pcall(function()
				c.Function()
			end)
		end
		return true
	end
	return false
end
local function portalStep(hrp, tpos)
	local list = PORTAL["Sea" .. SEA]
	if not list or not portalReady() then
		return false
	end
	local direct = (tpos - hrp.Position).Magnitude
	for name, p in pairs(list) do
		local d = (tpos - p).Magnitude
		if d <= 3000 and direct >= 3000 and shortcutWorth(direct, d, tonumber(cfg().PortalOverheadSec) or 2) then
			noclipOn = true
			if portalGo(name) then
				local t1 = tick() + 5
				repeat
					task.wait(0.2)
					local h = getHRP()
				until (h and (h.Position - p).Magnitude < 500) or tick() > t1
				return true
			end
		end
	end
	return false
end

-- điểm vào travel: trả true nếu đã tự xử lý di chuyển
local function travelStep(hrp, tpos)
	if SEA == 0 or cfg().UseTravel == false then
		return false
	end
	if cfg().UsePortal and portalStep(hrp, tpos) then
		return true
	end
	if SEA == 1 then
		return sea1Step(hrp, tpos)
	elseif SEA == 2 then
		return sea2Step(hrp, tpos)
	elseif SEA == 3 then
		return sea3Step(hrp, tpos)
	end
	return false
end

-- ===== toTarget =====
local function toTarget(cf, noGate)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	if hum.Sit then
		cancelTween()
		hum.Jump = true
		VIM:SendKeyEvent(true, "Space", false, game)
		task.wait()
		VIM:SendKeyEvent(false, "Space", false, game)
		hrp.CFrame = hrp.CFrame * CFrame.new(0, 10, 0)
		return
	end
	ensureFloat(hrp)
	noclipOn = true
	tagTeleporting()
	if hrp.Position.Y < -60 and hrp.Position.Y > -100 then
		hrp.CFrame = hrp.CFrame * CFrame.new(0, 20, 0)
	end
	local dist = (cf.Position - hrp.Position).Magnitude
	if dist < NEAR_SNAP then
		cancelTween()
		hrp.CFrame = cf
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		return
	end
	if not noGate and dist >= TRAVEL_MIN_DIST then
		local ok, handled = pcall(travelStep, hrp, cf.Position)
		if not ok then
			warn("[AutoBounty] travel:", handled)
		elseif handled then
			return
		end
	end
	tweenTo(cf, TWEEN_SPEED)
end

local function cleanupMove()
	cancelTween()
	noclipOn = false
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:FindFirstChild("FloatForce") then
		hrp.FloatForce:Destroy()
	end
end

-- ===== race / buso / pvp =====
local function turnOnV4()
	local char = LP.Character
	local energy = char and char:FindFirstChild("RaceEnergy")
	local transformed = char and char:FindFirstChild("RaceTransformed")
	if not energy or energy.Value < 1 or not transformed or transformed.Value then
		return
	end
	local tool = LP.Backpack:FindFirstChild("Awakening") or char:FindFirstChild("Awakening")
	if tool then
		tool.RemoteFunction:InvokeServer(true)
	end
end

local function hasBuso(char)
	if char:FindFirstChild("HasBuso") then
		return true
	end
	for _, c in ipairs(char:GetChildren()) do
		if string.match(c.Name, "_BusoLayer1") then
			return true
		end
	end
	return false
end

local function checkSafezone(char)
	local ok, res = pcall(function()
		for _, part in ipairs(workspace._WorldOrigin.SafeZones:GetChildren()) do
			if part:IsA("Part") then
				if
					(part.Position - char.HumanoidRootPart.Position).Magnitude <= 400
					and char.Humanoid.Health / char.Humanoid.MaxHealth >= 0.9
				then
					return true
				end
			end
		end
		return false
	end)
	return ok and res
end

local function checkCantAttack(char)
	local ok, res = pcall(function()
		for _, s in ipairs(LP.PlayerGui.Notifications:GetDescendants()) do
			if s:IsA("TextLabel") then
				if string.find(s.Text, "attack") and not s:FindFirstChild(char.Name) then
					local mark = Instance.new("TextBox")
					mark.Parent = s.Parent
					mark.Name = char.Name
					s:Destroy()
					return true
				end
			end
		end
		return false
	end)
	return ok and res
end

-- ===== aim hook (skill melee/sword/fruit) =====
if not env.__BountyHooked then
	env.__BountyHooked = true
	pcall(function()
		local mt = getrawmetatable(game)
		local old = mt.__namecall
		setreadonly(mt, false)
		mt.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			local aim = getgenv().__BountyAim
			if aim and method == "FireServer" and self.Name == "RemoteEvent" and tostring(aim.X) ~= "nan" then
				local args = { ... }
				if #args == 1 then
					if typeof(args[1]) == "Vector3" then
						args[1] = aim.Position
					elseif typeof(args[1]) == "CFrame" then
						args[1] = aim
					end
					return old(self, unpack(args))
				end
			end
			return old(self, ...)
		end)
		setreadonly(mt, true)
	end)
end
local MouseModule
pcall(function()
	MouseModule = require(RS:WaitForChild("Mouse", 5))
end)

-- ===== hop server =====
local function loadVisited()
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(JOBS_FILE))
	end)
	return (ok and type(data) == "table") and data or {}
end
local function saveVisited(t)
	pcall(function()
		writefile(JOBS_FILE, HttpService:JSONEncode(t))
	end)
end
local function hopServer()
	local visited = loadVisited()
	for k, v in pairs(visited) do
		if type(v) ~= "number" or os.time() - v > 1800 then
			visited[k] = nil
		end
	end
	visited[game.JobId] = os.time()
	saveVisited(visited)
	local browser = RS:WaitForChild("__ServerBrowser")
	while true do
		for page = 1, 100 do
			local ok, servers = pcall(function()
				return browser:InvokeServer(page)
			end)
			if ok and type(servers) == "table" then
				for jobId in pairs(servers) do
					if jobId ~= game.JobId and not visited[jobId] then
						visited[jobId] = os.time()
						saveVisited(visited)
						log("hop ->", jobId)
						pcall(function()
							browser:InvokeServer("teleport", jobId)
						end)
						task.wait(HOP_INTERVAL)
					end
				end
			end
		end
		task.wait(HOP_INTERVAL)
	end
end

local function queueSelf()
	local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
	if not q then
		return warn("[AutoBounty] executor không có queue_on_teleport, hop xong sẽ không tự chạy lại")
	end
	if not (isfile and isfile(SCRIPT_FILE)) then
		warn("[AutoBounty] chưa có workspace/" .. SCRIPT_FILE .. ", hop xong sẽ không tự chạy lại")
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(env.Config)
	end)
	if not ok then
		return
	end
	q(string.format(
		'repeat task.wait() until game:IsLoaded()\ngetgenv().__BountyResume = game:GetService("HttpService"):JSONDecode(%q)\nif isfile(%q) then loadstring(readfile(%q))() end',
		json,
		SCRIPT_FILE,
		SCRIPT_FILE
	))
end

-- ===== target =====
local function validChar(plr)
	if plr == LP or (blacklist[plr.Name] or 0) > tick() then
		return nil
	end
	if isKilled(plr) then
		return nil -- đã giết rồi, không săn lại
	end
	local folder = workspace:FindFirstChild("Characters")
	local char = folder and folder:FindFirstChild(plr.Name)
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return nil
	end
	if LP.Team and LP.Team.Name == "Marines" and plr.Team and plr.Team.Name == "Marines" then
		return nil
	end
	if checkSafezone(char) then
		return nil
	end
	return char
end

local function pickTarget()
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = validChar(plr)
		if char then
			local d = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
			if not bestD or d < bestD then
				best, bestD = plr, d
			end
		end
	end
	return best
end

-- theo dõi target chết -> lưu vào killed
local function wasTargetKilled(plr)
	if not plr then
		return false
	end
	local folder = workspace:FindFirstChild("Characters")
	local char = folder and folder:FindFirstChild(plr.Name)
	if not char then
		-- character mất: coi như chết nếu đã từng engaged gần đây
		return state.engaged or (state.lastNear and tick() - state.lastNear < 8)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return true
	end
	return false
end

local function bindTargetDeath(plr)
	if not plr then
		return
	end
	local folder = workspace:FindFirstChild("Characters")
	local char = folder and folder:FindFirstChild(plr.Name)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	pcall(function()
		hum.Died:Connect(function()
			if state.target == plr then
				markKilled(plr)
			end
		end)
	end)
end

-- ===== ESP Player (tên, máu, khoảng cách) khi săn =====
local espCache = {} -- [playerName] = Drawing.Text
local function clearEsp()
	for name, d in pairs(espCache) do
		pcall(function()
			d:Remove()
		end)
		espCache[name] = nil
	end
end
local function ensureEsp(name)
	local d = espCache[name]
	if d then
		return d
	end
	if not Drawing then
		return nil
	end
	d = Drawing.new("Text")
	d.Visible = false
	d.Transparency = 1
	d.Size = 16
	d.Center = true
	d.Outline = true
	d.OutlineColor = Color3.fromRGB(0, 0, 0)
	d.Font = 2
	d.Color = Color3.fromRGB(255, 255, 255)
	espCache[name] = d
	return d
end

task.spawn(function()
	while alive() do
		local ok, err = pcall(function()
			if state.hopping or state.saving or state.dead then
				for _, d in pairs(espCache) do
					d.Visible = false
				end
				return
			end
			local myHrp = getHRP()
			local cam = workspace.CurrentCamera
			if not myHrp or not cam or not Drawing then
				return
			end
			local seen = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = validChar(plr)
				if char then
					local hrp = char:FindFirstChild("HumanoidRootPart")
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hrp and hum then
						seen[plr.Name] = true
						local d = ensureEsp(plr.Name)
						if d then
							local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
							if onScreen and pos.Z > 0 then
								local dist = (hrp.Position - myHrp.Position).Magnitude
								local isTarget = state.target == plr
								d.Text = string.format(
									"%s\n%d / %d HP\n%d m",
									plr.Name,
									math.floor(hum.Health),
									math.floor(hum.MaxHealth),
									math.floor(dist)
								)
								d.Color = isTarget and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 255, 255)
								d.Position = Vector2.new(pos.X, pos.Y - 40)
								d.Visible = true
							else
								d.Visible = false
							end
						end
					end
				end
			end
			for name, d in pairs(espCache) do
				if not seen[name] then
					d.Visible = false
				end
			end
		end)
		if not ok then
			warn("[AutoBounty] ESP:", err)
			task.wait(1)
		end
		task.wait(0.05)
	end
	clearEsp()
end)

RunService.RenderStepped:Connect(function()
	if not alive() then
		return
	end
	local plr = state.target
	local char = plr and (not state.saving) and validChar(plr)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local p, v = hrp.Position, hrp.AssemblyLinearVelocity
		if v.Magnitude > 1 then
			env.__BountyAim = CFrame.new(p, p + v / 0.5)
		else
			env.__BountyAim = CFrame.new(p)
		end
		if MouseModule then
			pcall(function()
				MouseModule.Hit = hrp.CFrame
				MouseModule.Target = char
			end)
		end
		if state.engaged then
			local cam = workspace.CurrentCamera
			if cam then
				cam.CFrame = CFrame.lookAt(cam.CFrame.Position, p)
			end
		end
	else
		env.__BountyAim = nil
	end
end)

local function pvpOff()
	local ok, vis = pcall(function()
		return LP.PlayerGui.Main.BottomHUDList.PvpDisabled.Visible
	end)
	return ok and vis == true
end

local function startHop(reason)
	if state.hopping then
		return
	end
	state.hopping = true
	state.engaged = false
	env.__BountyAim = nil
	cleanupMove()
	log(reason, "-> hop server")
	task.spawn(hopServer)
end

local function onDeath()
	if state.dead then
		return
	end
	state.dead = true
	state.engaged = false
	state.saving = false
	state.saveCF = nil
	state.target = nil
	state.lastGoal = nil
	state.targetSince = 0
	state.noTargetSince = nil
	env.__BountyAim = nil
	cleanupMove()
	log("chết, chờ respawn")
end

-- ===== UI status (KHANHLY style + logo core) =====
local LOGO_ID = "rbxassetid://77671524243147"
local function getBounty()
	local ok, v = pcall(function()
		local ls = LP:FindFirstChild("leaderstats")
		local bh = ls and ls:FindFirstChild("Bounty/Honor")
		return bh and bh.Value or 0
	end)
	return ok and v or 0
end
local function fmtNum(n)
	n = tonumber(n) or 0
	local s = tostring(math.floor(n))
	local k
	while true do
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return s
end
local function buildUI()
	local pg = LP:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("KHANHLYHUB")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "KHANHLYHUB"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = pg

	-- top bar
	local bar = Instance.new("Frame")
	bar.Name = "IOS"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bar.Size = UDim2.new(0, 512, 0, 49)
	bar.Position = UDim2.new(0, 379, 0, 0)
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local barAspect = Instance.new("UIAspectRatioConstraint", bar)
	barAspect.AspectRatio = 10.44898

	local statusDot = Instance.new("Frame")
	statusDot.Name = "tink"
	statusDot.BorderSizePixel = 0
	statusDot.BackgroundColor3 = Color3.fromRGB(0, 255, 22)
	statusDot.Size = UDim2.new(0, 15, 0, 15)
	statusDot.Position = UDim2.new(0, 26, 0, 17)
	statusDot.Parent = bar
	Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)
	Instance.new("UIAspectRatioConstraint", statusDot)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.TextStrokeTransparency = 0
	title.ZIndex = 22
	title.BorderSizePixel = 0
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.Font = Enum.Font.SourceSansBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Size = UDim2.new(0, 423, 0, 50)
	title.Position = UDim2.new(0.11133, 0, -0.02041, 0)
	title.Text = "Auto Bounty"
	title.Parent = bar
	Instance.new("UITextSizeConstraint", title).MaxTextSize = 18

	-- main panel
	local panel = Instance.new("Frame")
	panel.Name = "UI IOS KHANHLY"
	panel.BorderSizePixel = 0
	panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	panel.BackgroundTransparency = 0.35
	panel.Size = UDim2.new(0, 433, 0, 266)
	panel.Position = UDim2.new(0, 420, 0, 88)
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)
	local panelAspect = Instance.new("UIAspectRatioConstraint", panel)
	panelAspect.AspectRatio = 1.62782

	local inner = Instance.new("Frame")
	inner.Name = "UI"
	inner.BorderSizePixel = 0
	inner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	inner.Size = UDim2.new(0, 420, 0, 252)
	inner.Position = UDim2.new(0, 6, 0, 7)
	inner.Parent = panel
	Instance.new("UICorner", inner).CornerRadius = UDim.new(0, 20)
	local innerAspect = Instance.new("UIAspectRatioConstraint", inner)
	innerAspect.AspectRatio = 1.672

	local logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.BorderSizePixel = 0
	logo.BackgroundTransparency = 1
	logo.Image = LOGO_ID
	logo.ImageTransparency = 0.1
	logo.Size = UDim2.new(0, 120, 0, 120)
	logo.Position = UDim2.new(0, 25, 0, 24)
	logo.Parent = inner
	Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 20)

	local function makeInfo(name, y, text)
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.BackgroundTransparency = 1
		lbl.TextStrokeTransparency = 0.5
		lbl.ZIndex = 22
		lbl.BorderSizePixel = 0
		lbl.TextSize = 16
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextScaled = true
		lbl.Font = Enum.Font.SourceSansBold
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.Size = UDim2.new(0, 250, 0, 28)
		lbl.Position = UDim2.new(0, 160, 0, y)
		lbl.Text = text
		lbl.Parent = inner
		Instance.new("UITextSizeConstraint", lbl).MaxTextSize = 16
		return lbl
	end

	local lblTarget = makeInfo("Target", 16, "Target: -")
	local lblDist = makeInfo("Distance", 48, "Distance: -")
	local lblHp = makeInfo("Health", 80, "HP: -")
	local lblBounty = makeInfo("Bounty", 112, "Bounty: -")
	local lblStatus = makeInfo("Status", 144, "Status: idle")

	local skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipTarget"
	skipBtn.BorderSizePixel = 0
	skipBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	skipBtn.Size = UDim2.new(0, 140, 0, 36)
	skipBtn.Position = UDim2.new(0, 160, 0, 190)
	skipBtn.Font = Enum.Font.SourceSansBold
	skipBtn.TextSize = 16
	skipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	skipBtn.Text = "Skip Target"
	skipBtn.AutoButtonColor = true
	skipBtn.Parent = inner
	Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 10)

	skipBtn.MouseButton1Click:Connect(function()
		state.skipRequest = true
	end)

	-- update loop
	task.spawn(function()
		while alive() and gui.Parent do
			task.wait(0.2)
			local ok, err = pcall(function()
				local tgt = state.target
				local tchar = tgt and validChar(tgt)
				if tchar and tchar:FindFirstChild("HumanoidRootPart") and tchar:FindFirstChildOfClass("Humanoid") then
					local hrp = getHRP()
					local dist = hrp and (tchar.HumanoidRootPart.Position - hrp.Position).Magnitude or 0
					local th = tchar:FindFirstChildOfClass("Humanoid")
					lblTarget.Text = "Target: " .. tgt.Name
					lblDist.Text = "Distance: " .. math.floor(dist) .. " m"
					lblHp.Text = "HP: " .. math.floor(th.Health) .. " / " .. math.floor(th.MaxHealth)
				else
					lblTarget.Text = "Target: -"
					lblDist.Text = "Distance: -"
					lblHp.Text = "HP: -"
				end
				lblBounty.Text = "Bounty: " .. fmtNum(getBounty())
				local st = "idle"
				if state.hopping then
					st = "hopping"
				elseif state.saving then
					st = "save mode"
				elseif state.engaged then
					st = "fighting"
				elseif state.target then
					st = "chasing"
				end
				local left = ""
				if state.target and state.targetSince > 0 then
					local rem = math.max(0, TARGET_TIMEOUT - (tick() - state.targetSince))
					left = string.format(" | t/o %.0fs", rem)
				end
				lblStatus.Text = "Status: " .. st .. left
				statusDot.BackgroundColor3 = state.hopping and Color3.fromRGB(255, 180, 0)
					or (state.engaged and Color3.fromRGB(0, 255, 22) or Color3.fromRGB(80, 180, 255))
			end)
			if not ok then
				warn("[AutoBounty] UI:", err)
			end
		end
	end)

	return gui
end

-- ===== vòng chính =====
local function step()
	if state.hopping then
		return
	end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		state.engaged = false
		return
	end
	if hum.Health <= 0 then
		onDeath()
		return
	end
	state.dead = false

	local c = cfg()
	local hp = hum.Health / math.max(hum.MaxHealth, 1) * 100

	if c.SaveMode then
		local enter = math.clamp(tonumber(c.HealthPercent) or 40, 1, 80)
		if not state.saving and hp < enter then
			state.saving = true
			state.nextSave = 0
			state.saveCF = nil
			state.target = nil
			state.targetSince = 0
		elseif state.saving and hp > RESUME_HP then
			-- hồi đủ máu: reset character để khỏi bay xuống từ trên cao
			state.saving = false
			state.saveCF = nil
			log("HP >", RESUME_HP, "% -> reset character")
			cleanupMove()
			pcall(function()
				hum.Health = 0
			end)
			return
		end
	else
		state.saving = false
	end

	if state.saving then
		state.engaged = false
		state.noTargetSince = nil
		if tick() >= state.nextSave then
			state.nextSave = tick() + SAVE_INTERVAL
			state.saveCF = CFrame.new(hrp.Position + Vector3.new(0, SAVE_STEP_Y, 0))
		end
		if state.saveCF then
			toTarget(state.saveCF, true) -- save mode: bỏ qua gate
		end
		return
	end

	if state.skipRequest then
		skipCurrentTarget("skip button")
	end

	local tchar = state.target and validChar(state.target)
	if not tchar then
		-- target mất: nếu đã chết thì lưu vào killed (không săn lại)
		if state.target and wasTargetKilled(state.target) then
			markKilled(state.target)
		end
		local prev = state.target
		state.target = pickTarget()
		state.lastGoal = nil
		state.lastNear = tick()
		state.targetSince = state.target and tick() or 0
		if state.target and state.target ~= prev then
			bindTargetDeath(state.target)
		end
		tchar = state.target and validChar(state.target)
	end
	if not state.target or not tchar then
		state.engaged = false
		state.noTargetSince = state.noTargetSince or tick()
		if tick() - state.noTargetSince > NO_TARGET_HOP then
			startHop("hết target (chưa săn trong server)")
		end
		return
	end
	state.noTargetSince = nil

	-- timeout 120s: target chưa bị giết (kể cả chưa bay tới) -> skip
	if state.targetSince > 0 and tick() - state.targetSince > TARGET_TIMEOUT then
		skipCurrentTarget("timeout 120s (chưa giết)")
		return
	end

	local thrp = tchar.HumanoidRootPart
	local dist = (thrp.Position - hrp.Position).Magnitude
	-- đứng trước mặt target (theo LookVector)
	local front = thrp.CFrame.LookVector
	front = Vector3.new(front.X, 0, front.Z)
	if front.Magnitude < 0.01 then
		front = Vector3.new(0, 0, -1)
	end
	local standPos = Vector3.new(thrp.Position.X, thrp.Position.Y + STAND_UP, thrp.Position.Z) + front.Unit * STAND_BACK
	local goal = CFrame.lookAt(standPos, thrp.Position)

	if
		dist <= NEAR_SNAP
		or not state.lastGoal
		or (goal.Position - state.lastGoal.Position).Magnitude > 15
		or tick() - state.lastGoalT > 0.5
	then
		state.lastGoal = goal
		state.lastGoalT = tick()
		toTarget(goal)
	end

	-- toTarget có thể block lâu (travel) -> target có thể đã đổi, đo lại
	local hrp2 = getHRP()
	if hrp2 and state.target then
		local cur = validChar(state.target)
		local chrp = cur and cur:FindFirstChild("HumanoidRootPart")
		dist = chrp and (chrp.Position - hrp2.Position).Magnitude or math.huge
	end

	state.engaged = dist <= ATTACK_RANGE
	if state.engaged then
		state.lastNear = tick()
	end
end

task.spawn(function()
	pcall(ensureTeam)
	log("đợi UI game...")
	waitUIReady(60)
	log("UI đủ, đợi thêm", START_DELAY, "s")
	task.wait(START_DELAY)
	if not alive() then
		return
	end
	queueSelf()

	for _ = 1, 10 do
		if not pvpOff() then
			break
		end
		pcall(function()
			CommF:InvokeServer("EnablePvp")
		end)
		task.wait(1)
	end
	state.pvpArmed = true
	log("bắt đầu farm | team:", LP.Team and LP.Team.Name, "| pvp tắt:", pvpOff(), "| travel:", SEA ~= 0 and cfg().UseTravel ~= false)

	pcall(buildUI)

	-- thread skill (Melee/Sword/Fruit/Gun — chỉ spam skill, không bắn súng)
	task.spawn(function()
		local lastHold = 0
		while alive() do
			task.wait()
			if not state.hopping then
				local ok, err = pcall(function()
					if state.engaged then
						if not castOne() then
							holdWeapon()
						end
					elseif tick() - lastHold > 0.5 then
						lastHold = tick()
						holdWeapon()
					end
				end)
				if not ok then
					warn("[AutoBounty] skill:", err)
					task.wait(1)
				end
			end
		end
	end)

	-- thread phụ: pvp, buso, ken, race, team, target không đánh được
	task.spawn(function()
		local lastV3, lastTeam, lastKen, pvpOffCount = 0, 0, 0, 0
		while alive() do
			task.wait(1)
			if not state.hopping then
				if state.pvpArmed and pvpOff() then
					pvpOffCount = pvpOffCount + 1
					if pvpOffCount >= PVP_OFF_CHECKS then
						startHop("PVP tắt")
					end
				else
					pvpOffCount = 0
				end
				pcall(function()
					local char = LP.Character
					if char and not hasBuso(char) then
						CommF:InvokeServer("Buso")
					end
				end)
				if tick() - lastKen > 5 then
					lastKen = tick()
					pcall(function()
						CommE:FireServer("Ken", true)
					end)
				end
				if tick() - lastTeam > 15 then
					lastTeam = tick()
					pcall(ensureTeam)
				end
				if state.engaged then
					local c = cfg()
					if c.RaceV3 and tick() - lastV3 > 2 then
						lastV3 = tick()
						pcall(function()
							CommE:FireServer("ActivateAbility")
						end)
					end
					if c.RaceV4 then
						pcall(turnOnV4)
					end
					local tgt = state.target
					local tchar = tgt and validChar(tgt)
					if tchar and checkCantAttack(tchar) then
						skipCurrentTarget("cant attack")
					end
				end
			end
		end
	end)

	-- thread main
	while alive() do
		task.wait()
		local ok, err = pcall(step)
		if not ok then
			warn("[AutoBounty] step:", err)
			task.wait(1)
		end
	end
	cleanupMove()
end)
