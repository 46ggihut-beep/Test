-- ===================== KHỞI TẠO FLUENT UI =====================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Fast Hop Hub",
    SubTitle = "Bypass Teleport",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl -- Nhấn Ctrl trái để ẩn/hiện UI
})

local Tabs = {
    Travel = Window:AddTab({ Title = "Travel", Icon = "plane" })
}

-- ===================== KHAI BÁO CƠ BẢN =====================
local plr = game:GetService("Players").LocalPlayer

-- Đưa các biến World lên đầu để tránh lỗi khi khởi tạo Dropdown
local World1 = game.PlaceId == 2753915549 or game.PlaceId == 85211729168715
local World2 = game.PlaceId == 4442272183 or game.PlaceId == 79091703265657
local World3 = game.PlaceId == 7449423635 or game.PlaceId == 100117331123089

-- ===================== BYPASS TELEPORT (FAST HOP) =====================
local DC_MAX_STEP_DIST = getgenv().DC_MAX_STEP_DIST or 9000
local DC_HOLD_TIME = getgenv().DC_HOLD_TIME or 2
local DC_HOLD_STEP = getgenv().DC_HOLD_STEP or 0.03
local DC_RESPAWN_TIMEOUT = getgenv().DC_RESPAWN_TIMEOUT or 7
local DC_SKIP_IF_NEAR = getgenv().DC_SKIP_IF_NEAR or 2000

local IslandCF = {
	["WindMill"] = CFrame.new(979.799, 16.516, 1429.047),
	["Marine"] = CFrame.new(-2566.43, 6.856, 2045.256),
	["Middle Town"] = CFrame.new(-690.331, 15.094, 1582.238),
	["Jungle"] = CFrame.new(-1612.796, 36.852, 149.128),
	["Pirate Village"] = CFrame.new(-1181.309, 4.751, 3803.546),
	["Desert"] = CFrame.new(944.158, 20.92, 4373.3),
	["Snow Island"] = CFrame.new(1347.807, 104.668, -1319.737),
	["MarineFord"] = CFrame.new(-4914.821, 50.964, 4281.028),
	["Colosseum"] = CFrame.new(-1427.62, 7.288, -2792.772),
	["Sky Island 1"] = CFrame.new(-4869.103, 733.461, -2667.018),
	["Sky Island 2"] = CFrame.new(-11.311, 29.277, 2771.522),
	["Sky Island 3"] = CFrame.new(-483.734, 332.038, 595.327),
	["Prison"] = CFrame.new(4875.33, 5.652, 734.85),
	["Magma Village"] = CFrame.new(-5247.716, 12.884, 8504.969),
	["Under Water Island"] = CFrame.new(61163.852, 11.68, 1819.784),
	["Fountain City"] = CFrame.new(5127.128, 59.501, 4105.446),

	["The Cafe"] = CFrame.new(-380.479, 77.22, 255.826),
	["Frist Spot"] = CFrame.new(-9515.372, 164.006, 5786.061),
	["Dark Area"] = CFrame.new(3780.03, 22.652, -3498.586),
	["Flamingo Mansion"] = CFrame.new(-3032.764, 317.897, -10075.373),
	["Flamingo Room"] = CFrame.new(2284.414, 15.152, 875.725),
	["Green Zone"] = CFrame.new(-2448.53, 73.016, -3210.631),
	["Factory"] = CFrame.new(424.127, 211.162, -427.54),
	["Colossuim"] = CFrame.new(-1503.622, 219.796, 1369.31),
	["Zombie Island"] = CFrame.new(-5622.033, 492.196, -781.786),
	["Two Snow Mountain"] = CFrame.new(753.143, 408.236, -5274.615),
	["Punk Hazard"] = CFrame.new(-6127.654, 15.952, -5040.286),
	["Cursed Ship"] = CFrame.new(923.402, 125.057, 32885.875),
	["Ice Castle"] = CFrame.new(6148.412, 294.387, -6741.117),
	["Forgotten Island"] = CFrame.new(2681.274, 1682.809, -7190.985),

	["Sea castle"] = CFrame.new(-5496.452, 313.809, -2857.703),
	["Mini Sky Island"] = CFrame.new(-288.741, 49326.316, -35248.594),
	["Great Tree"] = CFrame.new(2681.274, 1682.809, -7190.985),
	["Port Town"] = CFrame.new(-226.751, 20.603, 5538.34),
	["Hydra Island"] = CFrame.new(5291.249, 1005.443, 393.762),
	["Mansion"] = CFrame.new(-12633.672, 459.521, -7425.463),
	["Haunted Castle"] = CFrame.new(-9366.803, 141.366, 5443.941),
	["Ice Cream Island"] = CFrame.new(-902.568, 79.932, -10988.848),
	["Peanut Island"] = CFrame.new(-2062.748, 50.474, -10232.568),
	["Cake Island"] = CFrame.new(-1884.775, 19.328, -11666.897),
	["Cocoa Island"] = CFrame.new(87.943, 73.555, -12319.465),
	["Candy Island"] = CFrame.new(-1014.424, 149.111, -14555.963),
	["Tiki Outpost"] = CFrame.new(-16218.683, 9.086, 445.618),
	["Dragon Dojo"] = CFrame.new(5743.319, 1206.91, 936.011),
}

local Alias = {
	["MiniSky"] = "Mini Sky Island",
	["Colosseum"] = "Colosseum",
	["Colossuim"] = "Colossuim",
}

local WorldIslands = {
	World1 = {"WindMill","Marine","Middle Town","Jungle","Pirate Village","Desert","Snow Island","MarineFord","Colosseum","Sky Island 1","Sky Island 2","Sky Island 3","Prison","Magma Village","Under Water Island","Fountain City"},
	World2 = {"The Cafe","Frist Spot","Dark Area","Flamingo Mansion","Flamingo Room","Green Zone","Factory","Colossuim","Zombie Island","Two Snow Mountain","Punk Hazard","Cursed Ship","Ice Castle","Forgotten Island"},
	World3 = {"Sea castle","Mini Sky Island","Great Tree","Port Town","Hydra Island","Mansion","Haunted Castle","Ice Cream Island","Peanut Island","Cake Island","Cocoa Island","Candy Island","Tiki Outpost","Dragon Dojo"},
}

local function getWorldKey()
	if World1 then return "World1" end
	if World2 then return "World2" end
	if World3 then return "World3" end
	return "World1"
end

local function normName(name)
	if type(name) ~= "string" then return nil end
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if Alias[name] then name = Alias[name] end
	return name
end

local function dist(a, b) return (a - b).Magnitude end

local function GetChar()
	local c = plr.Character or plr.CharacterAdded:Wait()
	local hrp = c:WaitForChild("HumanoidRootPart", 10)
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) then return end
	return c, hrp, hum
end

local function buildNodes()
	local wk = getWorldKey()
	local list = WorldIslands[wk] or {}
	local nodes = {}
	for _, n in ipairs(list) do
		if IslandCF[n] then nodes[#nodes+1] = n end
	end
	return nodes
end

local function nearestIsland(pos, nodes)
	local best, bestD
	for _, n in ipairs(nodes) do
		local d = dist(pos, IslandCF[n].Position)
		if not bestD or d < bestD then bestD, best = d, n end
	end
	return best, bestD or math.huge
end

local function dijkstra(nodes, startName, goalName, maxStep)
	local adj = {}
	for _, a in ipairs(nodes) do adj[a] = {} end

	for i=1,#nodes do
		local ai = nodes[i]
		local ap = IslandCF[ai].Position
		for j=i+1,#nodes do
			local bj = nodes[j]
			local bp = IslandCF[bj].Position
			local d = dist(ap, bp)
			if d <= maxStep then
				adj[ai][bj] = d
				adj[bj][ai] = d
			end
		end
	end

	local distMap, prev, used = {}, {}, {}
	for _, n in ipairs(nodes) do distMap[n] = math.huge end
	distMap[startName] = 0

	while true do
		local u, best = nil, math.huge
		for _, n in ipairs(nodes) do
			if not used[n] and distMap[n] < best then best, u = distMap[n], n end
		end
		if not u or u == goalName then break end
		used[u] = true
		for v, w in pairs(adj[u]) do
			if not used[v] then
				local nd = distMap[u] + w
				if nd < distMap[v] then distMap[v], prev[v] = nd, u end
			end
		end
	end

	if distMap[goalName] == math.huge then return nil end
	local path, cur = {}, goalName
	while cur do
		table.insert(path, 1, cur)
		cur = prev[cur]
	end
	return path
end

local _STOP, _RUN = false, false

local function HoldTPAndReset(pos)
	local c, hrp, hum = GetChar()
	if not c then return false end
	local cf = CFrame.new(pos)

	pcall(function()
		hrp.CFrame = cf
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)

	local t0 = os.clock()
	while os.clock() - t0 < DC_HOLD_TIME do
		if _STOP then break end
		if not (hrp and hrp.Parent and hum and hum.Parent and hum.Health > 0) then break end
		pcall(function()
			hrp.CFrame = cf
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end)
		task.wait(DC_HOLD_STEP)
	end

	if _STOP then return false end
	pcall(function() hum.Health = 0 end)
	return true
end

-- ===================== ĐOẠN ĐÃ ĐƯỢC SỬA FIX ĐỢI 1S =====================
local function WaitRespawn()
	local t0 = os.clock()
	while os.clock() - t0 < DC_RESPAWN_TIMEOUT do
		if _STOP then return false end
		local c = plr.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		
		if hrp and hum and hum.Health > 0 then 
			-- NHÂN VẬT ĐÃ HỒI SINH: Tiến hành đợi thêm 1 giây như yêu cầu
			local waitStart = os.clock()
			while os.clock() - waitStart < 1 do
				if _STOP then return false end -- Nếu bấm tắt toggle lúc đang đợi thì dừng luôn
				task.wait(0.05)
			end
			return true 
		end
		task.wait(0.15)
	end
	return false
end
-- =====================================================================

function DC_FastHopTo(targetName)
	targetName = normName(targetName)
	if not (targetName and IslandCF[targetName]) then return false end

	local nodes = buildNodes()
	if #nodes == 0 then return false end

	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if not WaitRespawn() then return false end
		hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	end
	if not hrp then return false end

	local startIsland = nearestIsland(hrp.Position, nodes)
	local path = dijkstra(nodes, startIsland, targetName, DC_MAX_STEP_DIST)
	if not path then return false end

	_RUN, _STOP = true, false

	for _, name in ipairs(path) do
		if _STOP then break end
		local pos = IslandCF[name].Position
		local ch = plr.Character
		local hrp2 = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp2 and dist(hrp2.Position, pos) <= DC_SKIP_IF_NEAR then
			task.wait(0.1)
		else
			if not HoldTPAndReset(pos) or _STOP then break end
			if not WaitRespawn() or _STOP then break end
		end
		task.wait(0.2)
	end

	_RUN = false
	return not _STOP
end

function DC_StopFastHop()
	_STOP = true
end

function DC_IsFastHopRunning()
	return _RUN
end

local function BuildIslandOptions()
	local wk = getWorldKey()
	local list = WorldIslands[wk] or {}
	local out, seen = {}, {}
	for _, name in ipairs(list) do
		if Alias and Alias[name] then name = Alias[name] end
		if IslandCF[name] and not seen[name] then
			seen[name] = true
			out[#out+1] = name
		end
	end
	table.sort(out)
	return out
end

-- ===================== FLUENT UI ELEMENTS =====================
_G.Islandtp = _G.Islandtp or BuildIslandOptions()[1]

local BypassIslandDropdown = Tabs.Travel:AddDropdown("BypassIslandDrop", {
	Title = "Select Island",
	Values = BuildIslandOptions(),
	Multi = false,
	Default = _G.Islandtp and table.find(BuildIslandOptions(), _G.Islandtp) or 1,
	Callback = function(Value)
		_G.Islandtp = Value
	end
})

local BypassToggle = Tabs.Travel:AddToggle("BypassToggle", {
    Title = "Turn on Bypass Teleport",
    Default = false,
    Callback = function(Value)
        _G.Bypass = Value
        if not Value and typeof(DC_StopFastHop) == "function" then
            DC_StopFastHop()
        end
    end
})

-- Vòng lặp xử lý logic Fast Hop
task.spawn(function()
	while task.wait(0.25) do
		if _G.Bypass and _G.Islandtp and not _RUN then
			_STOP = false
			DC_FastHopTo(_G.Islandtp)
		end
	end
end)

-- Khởi tạo hoàn tất
Fluent:Notify({
    Title = "Hub Loaded",
    Content = "Bypass Teleport is ready to use!",
    Duration = 5
})
