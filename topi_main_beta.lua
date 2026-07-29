repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

--// ===================== SERVICES =====================
local Library          = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local InterfaceManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local plr    = Players.LocalPlayer
local player = plr  -- alias used throughout

--// ===================== WORLD DETECTION =====================
local World1 = game.PlaceId == 2753915549 or game.PlaceId == 85211729168715
local World2 = game.PlaceId == 4442272183 or game.PlaceId == 79091703265657
local World3 = game.PlaceId == 7449423635 or game.PlaceId == 100117331123089
local DungeonPlaceId = 73902483975735

--// ===================== CONFIG =====================
-- Dùng từ bên ngoài trước khi load script:
--   getgenv().Config = { Team = "Pirates" }  --// "Pirates" | "Marines"
--   loadstring(game:HttpGet("raw link"))()
local Config = getgenv().Config or {
    Team        = "Pirates",  --// Pirates | Marines
    AutoHideUI  = false,      --// true = tự ẩn UI sau 5s | false = không ẩn
}

-- Áp dụng Team ngay khi script khởi động
-- Chỉ join nếu chưa ở team nào (Neutral hoặc nil)
pcall(function()
    local currentTeam = plr.Team
    local teamName    = currentTeam and currentTeam.Name or ""
    if teamName == "" or teamName == "Neutral" then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", Config.Team)
    end
end)

--// ===================== MOVEMENT =====================
-- Submerged Island travel guard
local _submergedRunning = false
local _submergedCallId  = 0

local function getRoot()
    local c = plr.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

--// ===================== MOVEMENT SYSTEM (Tween + BodyVelocity) =====================
local _currentTween   = nil   -- TweenService tween đang chạy
local _flyEnabled     = false -- Flag chế độ farm (dùng bởi enableFly/disableFly)
local _flyTarget      = nil   -- Compat: non-nil = đang có đích (dùng trong mob-lock)
local _sameY          = false -- khi true: snap Y ngay rồi tween X/Z
local _lockedBringPos = nil   -- Anchor bring mob
local _spinAngle      = 0     -- Góc spin bring (radians)
local _sphereTime     = 0     -- Thời gian tích lũy cho sphere orbit (seconds)

local MOVE_SPEED_DEFAULT = 300  -- stud/s mặc định

local function _getMoveSpeed()
    return getgenv().FlySpeed or MOVE_SPEED_DEFAULT
end

-- BodyVelocity helpers
local function _applyBV(root, vel)
    local bv = root:FindFirstChild("_FlyBV")
    if not bv then
        bv          = Instance.new("BodyVelocity")
        bv.Name     = "_FlyBV"
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = vel
        bv.Parent   = root
    else
        bv.Velocity = vel
    end
end

local function _removeBV(root)
    local bv = root and root:FindFirstChild("_FlyBV")
    if bv then bv:Destroy() end
end

-- Noclip toàn bộ character
local function _applyNoclip()
    local char = plr.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then v.CanCollide = false end
    end
end

-- Hủy tween đang chạy + hover tại chỗ
local function _stopCurrentTween()
    if _currentTween then
        _currentTween:Cancel()
        _currentTween = nil
    end
    local root = getRoot()
    if root then _applyBV(root, Vector3.zero) end
end

-- Heartbeat: noclip liên tục + mob-lock snap + hover khi idle
RunService.Heartbeat:Connect(function(dt)
    if not _flyEnabled then return end
    local root = getRoot()
    if not root then return end

    _applyNoclip()

    local mob    = getgenv().CurrentTargetMob
    local mobHRP = mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart")

    if mobHRP and _flyTarget then
        local distToMob = (mobHRP.Position - root.Position).Magnitude

        if distToMob <= 30 then
            -- Đã vào vùng 30 stud → đứng trên đầu mob 25 stud
            if _currentTween then
                _currentTween:Cancel()
                _currentTween = nil
            end
            root.CFrame = CFrame.new(mobHRP.Position + Vector3.new(0, 25, 0))
            _applyBV(root, Vector3.zero)
            return

        elseif distToMob <= 100 then
            -- ── 30–100 stud: tween thường nhưng dùng teleport tiệm cận ──────
            if _currentTween then
                _currentTween:Cancel()
                _currentTween = nil
            end
            root.CFrame = CFrame.new(mobHRP.Position + Vector3.new(0, 25, 0))
            _applyBV(root, Vector3.zero)
            return
        end
        -- > 100 stud: để _tp tween xử lý bình thường
    end

    -- Hover chống rơi khi không có tween
    if not _currentTween then
        _applyBV(root, Vector3.zero)
    end
end)

-- Respawn: khôi phục PlatformStand + noclip + highlight
plr.CharacterAdded:Connect(function(char)
    if not _flyEnabled then return end
    task.wait(0.1)
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = true end
        _applyNoclip()
    end
    -- Bật lại highlight (bị mất khi nhân vật mới spawn)
    if not char:FindFirstChild("highlight") then
        local hl               = Instance.new("Highlight")
        hl.Name                = "highlight"
        hl.FillColor           = Color3.fromRGB(0, 191, 255)
        hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency    = 0.5
        hl.OutlineTransparency = 0.2
        hl.Parent              = char
    end
end)

local function enableFly()
    _flyEnabled = true
    local root = getRoot()
    if not root then return end
    local char = plr.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end
    if char and not char:FindFirstChild("highlight") then
        local hl               = Instance.new("Highlight")
        hl.Name                = "highlight"
        hl.FillColor           = Color3.fromRGB(0, 191, 255)
        hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency    = 0.5
        hl.OutlineTransparency = 0.2
        hl.Parent              = char
    end
end

local function disableFly()
    _flyEnabled = false
    _flyTarget  = nil
    _stopCurrentTween()
    local root = getRoot()
    _removeBV(root)
    local char = plr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        local hl = char:FindFirstChild("highlight")
        if hl then hl:Destroy() end
    end
end

-- _tp: bắt đầu tween đến targetCF (non-blocking)
local function _tp(targetCF)
    if not _flyEnabled then enableFly() end

    local root = getRoot()
    if not root then return end

    -- Hủy tween cũ + hover tại chỗ
    _flyTarget = nil
    _stopCurrentTween()

    -- SameY: snap trục Y → nếu chênh Y >= 1000 thì hover 0.3s, ngược lại tween luôn
    if _sameY then
        local cur   = root.Position
        local ty    = targetCF.Position.Y
        local yDiff = math.abs(cur.Y - ty)
        if yDiff > 0.5 then
            root.CFrame = CFrame.new(cur.X, ty, cur.Z)
            if yDiff >= 1000 then
                _applyBV(root, Vector3.zero)  -- đứng yên trên không đúng Y trong lúc delay
                task.wait(0.3)
                -- Re-fetch root sau delay (phòng respawn)
                local c2 = player.Character
                root = c2 and c2:FindFirstChild("HumanoidRootPart")
                if not root then return end
            end
            -- < 1000: teleY xong tween luôn, không delay
        end
    end

    -- Bắt đầu tween → set _flyTarget
    _flyTarget = targetCF

    -- Tính duration từ khoảng cách và tốc độ
    local dist     = (root.Position - targetCF.Position).Magnitude
    local speed    = _getMoveSpeed()
    local duration = math.max(0.05, dist / speed)

    -- Noclip ngay
    _applyNoclip()

    -- BV theo hướng đích để hỗ trợ tween vượt collision
    local dir = targetCF.Position - root.Position
    if dir.Magnitude > 0.1 then
        _applyBV(root, dir.Unit * speed)
    end

    -- Tween CFrame mượt đến đích
    local tw = TweenService:Create(
        root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
        {CFrame = targetCF}
    )
    _currentTween = tw
    tw:Play()
    tw.Completed:Connect(function()
        if _currentTween == tw then
            _currentTween = nil
            _flyTarget    = nil
            local r = getRoot()
            if r then _applyBV(r, Vector3.zero) end
        end
    end)
end

-- Alias trỏ thẳng đến raw setter.
-- doIntermediateTeleport dùng _flyTo (không qua portal check) để tránh đệ quy.
local _flyTo = _tp

--// ===================== PORTAL TELEPORT (INTERMEDIATE ISLAND SYSTEM) =====================
-- Danh sách đảo trung gian theo world — nạp ngay khi script khởi động
local IntermediateIslands = {}
if World1 then
    IntermediateIslands = {
        {name="Sky2",      pos=Vector3.new(-4607.82,  872.58, -1667.56)},
        {name="UnderWater",pos=Vector3.new(61163.85,    5.34,  1819.78)},
        {name="Whirlpool", pos=Vector3.new( 3864.69,    5.41, -1926.21)},
        {name="Sky3",      pos=Vector3.new(-7894.62, 5545.49,   -380.20)},
    }
elseif World2 then
    IntermediateIslands = {
        {name="GhostShipGate",   pos=Vector3.new(-6505.30,  75.22,   -126.66)},
        {name="GhostShip",       pos=Vector3.new(  923.21, 120.98,  32852.83)},
        {name="FlamingoMansion", pos=Vector3.new( -287.53, 280.17,    597.60)},
        {name="FlamingoRoom",    pos=Vector3.new( 2284.01,  45.19,    908.03)},
    }
elseif World3 then
    IntermediateIslands = {
        {name="HouseHydarIsland", pos=Vector3.new( 5655, 1013,  -317)},
        {name="Mansion",          pos=Vector3.new(-12465,  459, -7561)},
        {name="CastleOnTheSea",   pos=Vector3.new(-5083,   371, -3177)},
    }
else
    -- Fallback về World 1
    IntermediateIslands = {
        {name="Sky2",      pos=Vector3.new(-4607.82,  872.58, -1667.56)},
        {name="UnderWater",pos=Vector3.new(61163.85,    5.34,  1819.78)},
        {name="Whirlpool", pos=Vector3.new( 3864.69,    5.41, -1926.21)},
    }
end

-- Ngưỡng khoảng cách XZ (stud) để kích hoạt tele trung gian
local INTERMEDIATE_THRESHOLD = 3000

-- Tìm đảo trung gian tối ưu: gần đích nhất VÀ gần hơn khoảng cách thẳng a→b
local function getIntermediateTeleport(a, b)
    local directDist = (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
    local best, bestDist = nil, math.huge
    for _, island in ipairs(IntermediateIslands) do
        local d = (Vector2.new(island.pos.X, island.pos.Z) - Vector2.new(b.X, b.Z)).Magnitude
        if d < bestDist then bestDist = d; best = island end
    end
    if best and bestDist < directDist then return best end
    return nil
end

-- State nội bộ
local _lastIntermediateTele = 0
local INTERMEDIATE_COOLDOWN = 5   -- giây giữa hai lần tele trung gian
local _intermediateRunning  = false

-- Teleport trung gian async.
-- Trả về true  → đã spawn (caller KHÔNG gọi _flyTo thêm).
-- Trả về false → bỏ qua (caller tự bay bình thường).
local function doIntermediateTeleport(targetCF)
    if not getgenv().TelePorto                              then return false end
    if _intermediateRunning                                 then return true  end
    if tick() - _lastIntermediateTele < INTERMEDIATE_COOLDOWN then return false end

    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local targetPos = targetCF.Position
    local playerPos = hrp.Position
    local dist = (Vector2.new(playerPos.X, playerPos.Z)
                - Vector2.new(targetPos.X,  targetPos.Z)).Magnitude
    if dist < INTERMEDIATE_THRESHOLD then return false end

    local island = getIntermediateTeleport(playerPos, targetPos)
    if not island then return false end

    -- Đặt cờ + cooldown ngay trước khi spawn
    _intermediateRunning  = true
    _lastIntermediateTele = tick()

    task.spawn(function()
        -- Bước 1: Dừng tween đang chạy
        _stopCurrentTween()

        -- Bước 2: Tính thời gian spam theo khoảng cách đến đảo
        local distToIsland = (Vector2.new(playerPos.X, playerPos.Z)
                            - Vector2.new(island.pos.X, island.pos.Z)).Magnitude
        local spamDuration = distToIsland < 5000 and 0.3 or 2

        print("🚀 Portal Tp → " .. island.name
              .. "  (dist player→target=" .. math.floor(dist) .. " stud)")

        -- Bước 3: Spam teleport đến đảo trung gian
        local deadline = tick() + spamDuration
        while tick() < deadline do
            local c = player.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            if h then h.CFrame = CFrame.new(island.pos + Vector3.new(0, 2, 0)) end
            task.wait()
        end

        -- Bước 4: Delay sau tele — dựa trên chênh lệch Y giữa player và đích thật
        -- Nếu |Y_player_hiện_tại - Y_đích| >= 250 stud → đợi 0.5s để server load chunk cao/thấp
        -- Nếu nhỏ hơn 250 → tween luôn, không cần delay
        local yDiff = math.abs((island.pos.Y + 2) - targetCF.Position.Y)
        if yDiff >= 250 then
            task.wait(0.5)
        end

        -- Bước 5: Mở khoá → tween thẳng đến đích thật
        -- Dùng _flyTo (không qua portal check) để tránh đệ quy
        _intermediateRunning = false
        _flyTo(targetCF)
    end)

    return true
end

-- Bọc lại _tp với portal check.
-- Mọi lời gọi _tp() trong toàn bộ script (farm loops, quest, dungeon…)
-- sẽ tự động được kiểm tra portal mà không cần sửa từng chỗ.
_tp = function(targetCF)
    if doIntermediateTeleport(targetCF) then return end
    _flyTo(targetCF)
end

-- Chờ đến nơi (blocking, timeout giây)
local function _waitArrival(targetPos, radiusStud, timeoutSec)
    local deadline = tick() + (timeoutSec or 15)
    while tick() < deadline do
        local root = getRoot()
        if not root then break end
        if (root.Position - targetPos).Magnitude <= radiusStud then return true end
        task.wait(0.1)
    end
    return false
end

-- Alias dùng trong Kata/Dungeon farm
local function TweenObject(root, targetCF, speed)
    _tp(targetCF)
end

local function TweenToFixedPos(root, targetCF, speed)
    _tp(targetCF)
end

-- shouldTween kept as false stub for any legacy references
local shouldTween = false

--// ===================== TWEEN TO POS =====================
local function TweenToPos(targetCF, speed)
    local root = getRoot()
    if not root then return end
    _tp(targetCF)
end

--// ===================== TELEPORT TO SUBMERGED ISLAND =====================
local function TeleportToSubmerged(finalPos)
    if not (World3 and player.Data.Level.Value >= 2600) then return end
    if _submergedRunning then return end
    _submergedRunning = true

    _submergedCallId = _submergedCallId + 1
    local myId = _submergedCallId

    local npcCF = CFrame.new(-16269.7041, 25.2288494, 1373.65955)

    -- Bước 1: Fly đến NPC tàu ngầm
    TweenToPos(npcCF, 350)

    local deadline = tick() + 30
    repeat
        task.wait(0.3)
        if myId ~= _submergedCallId then _submergedRunning = false; return end
        if not getgenv().IsFarming then _submergedRunning = false; return end
        local root = getRoot()
        if not root then break end
        if (root.Position - npcCF.Position).Magnitude <= 35 then break end
    until tick() > deadline

    if myId ~= _submergedCallId or not getgenv().IsFarming then
        _submergedRunning = false; return
    end

    -- Bước 2: Dừng tween, đứng yên 2s để NPC nhận diện
    _stopCurrentTween()  -- hover tại chỗ
    task.wait(2)

    if myId ~= _submergedCallId or not getgenv().IsFarming then
        _submergedRunning = false; return
    end

    -- Bước 3: Kích hoạt TravelToSubmergedIsland
    pcall(function()
        ReplicatedStorage.Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak")
            :InvokeServer("TravelToSubmergedIsland")
    end)

    -- Bước 4: Chờ server tele xong (4s)
    task.wait(4)

    if myId ~= _submergedCallId or not getgenv().IsFarming then
        _submergedRunning = false; return
    end

    -- Bước 5: Fly đến vị trí farm bên trong island
    if finalPos then
        local farmCF = CFrame.new(finalPos + Vector3.new(0, 3, 0))
        TweenToPos(farmCF, getgenv().FlySpeed or 300)

        local farmDeadline = tick() + 40
        repeat
            task.wait(0.3)
            if myId ~= _submergedCallId then break end
            if not getgenv().IsFarming then break end
            local root = getRoot()
            if not root then break end
            if (root.Position - finalPos).Magnitude <= 100 then break end
        until tick() > farmDeadline
    end

    _submergedRunning = false
end

--// ===================== DUAL QUEST PAIRINGS =====================
local DualQuestPairings = {
    -- World 1
    JungleQuest       = {Mon="Monkey",           Qdata=1, NameMon="Monkey",           PosM=CFrame.new(-1448.5180664062,  67.853012084961,    11.465796470642)},
    BuggyQuest1       = {Mon="Pirate",            Qdata=1, NameMon="Pirate",            PosM=CFrame.new(-1103.5134277344,  13.752052307129,  3896.0910644531)},
    DesertQuest       = {Mon="Desert Bandit",     Qdata=1, NameMon="Desert Bandit",     PosM=CFrame.new(924.7998046875,    6.4486746788025,  4481.5859375)},
    SnowQuest         = {Mon="Snow Bandit",       Qdata=1, NameMon="Snow Bandit",       PosM=CFrame.new(1354.3479003906,  87.272773742676, -1393.9465332031)},
    SkyQuest          = {Mon="Sky Bandit",        Qdata=1, NameMon="Sky Bandit",        PosM=CFrame.new(-4953.20703125,   295.74420166016, -2899.2290039062)},
    PrisonerQuest     = {Mon="Prisoner",          Qdata=1, NameMon="Prisoner",          PosM=CFrame.new(5098.9736328125,  -0.3204058110714,   474.23733520508)},
    ColosseumQuest    = {Mon="Toga Warrior",      Qdata=1, NameMon="Toga Warrior",      PosM=CFrame.new(-1820.21484375,   51.683856964111, -2740.6650390625)},
    MagmaQuest        = {Mon="Military Soldier",  Qdata=1, NameMon="Military Soldier",  PosM=CFrame.new(-5411.1645507812, 11.081554412842,  8454.29296875)},
    FishmanQuest      = {Mon="Fishman Warrior",   Qdata=1, NameMon="Fishman Warrior",   PosM=CFrame.new(60878.30078125,   18.482830047607,  1543.7574462891)},
    SkyExp2Quest      = {Mon="Royal Squad",       Qdata=1, NameMon="Royal Squad",       PosM=CFrame.new(-7624.2524414062, 5658.1333007812, -1467.3542480469)},
    FountainQuest     = {Mon="Galley Pirate",     Qdata=1, NameMon="Galley Pirate",     PosM=CFrame.new(5551.0219726562,  78.901351928711,  3930.4128417969)},
    -- World 2
    Area1Quest        = {Mon="Raider",            Qdata=1, NameMon="Raider",            PosM=CFrame.new(-728.32672119141, 52.779319763184,  2345.7705078125)},
    Area2Quest        = {Mon="Swan Pirate",       Qdata=1, NameMon="Swan Pirate",       PosM=CFrame.new(1068.6643066406, 137.61428833008,   1322.1060791016)},
    MarineQuest3      = {Mon="Marine Lieutenant", Qdata=1, NameMon="Marine Lieutenant", PosM=CFrame.new(-2821.3723144531, 75.897277832031, -3070.0891113281)},
    ZombieQuest       = {Mon="Zombie",            Qdata=1, NameMon="Zombie",            PosM=CFrame.new(-5657.7768554688, 78.969734191895,  -928.68701171875)},
    SnowMountainQuest = {Mon="Snow Trooper",      Qdata=1, NameMon="Snow Trooper",      PosM=CFrame.new(549.14733886719, 427.38705444336,  -5563.6987304688)},
    IceSideQuest      = {Mon="Lab Subordinate",   Qdata=1, NameMon="Lab Subordinate",   PosM=CFrame.new(-5707.4716796875, 15.951709747314, -4513.3920898438)},
    FireSideQuest     = {Mon="Magma Ninja",       Qdata=1, NameMon="Magma Ninja",       PosM=CFrame.new(-5449.6728515625, 76.658744812012, -5808.2006835938)},
    ShipQuest1        = {Mon="Ship Deckhand",     Qdata=1, NameMon="Ship Deckhand",     PosM=CFrame.new(1212.0111083984, 150.79205322266,  33059.24609375)},
    ShipQuest2        = {Mon="Ship Steward",      Qdata=1, NameMon="Ship Steward",      PosM=CFrame.new(919.43853759766, 129.55599975586,  33436.03515625)},
    FrostQuest        = {Mon="Arctic Warrior",    Qdata=1, NameMon="Arctic Warrior",    PosM=CFrame.new(5966.24609375,   62.970020294189, -6179.3828125)},
    ForgottenQuest    = {Mon="Sea Soldier",       Qdata=1, NameMon="Sea Soldier",       PosM=CFrame.new(-3028.2236328125, 64.674514770508, -9775.4267578125)},
    -- World 3
    PiratePortQuest      = {Mon="Pirate Millionaire",  Qdata=1, NameMon="Pirate Millionaire",  PosM=CFrame.new(-246.00,          47.31,       5584.10)},
    DragonCrewQuest      = {Mon="Dragon Crew Warrior", Qdata=1, NameMon="Dragon Crew Warrior", PosM=CFrame.new(6709.76367,       52.3442993, -1139.02966)},
    VenomCrewQuest       = {Mon="Hydra Enforcer",      Qdata=1, NameMon="Hydra Enforcer",      PosM=CFrame.new(4547.11523,     1003.10217,     334.194824)},
    MarineTreeIsland     = {Mon="Marine Commodore",    Qdata=1, NameMon="Marine Commodore",    PosM=CFrame.new(2519,            109,          -7633)},
    DeepForestIsland3    = {Mon="Fishman Raider",      Qdata=1, NameMon="Fishman Raider",      PosM=CFrame.new(-10407.526367188, 331.76263427734, -8368.5166015625)},
    DeepForestIsland     = {Mon="Forest Pirate",       Qdata=1, NameMon="Forest Pirate",       PosM=CFrame.new(-13274.478515625, 332.37814331055, -7769.5805664062)},
    DeepForestIsland2    = {Mon="Jungle Pirate",       Qdata=1, NameMon="Jungle Pirate",       PosM=CFrame.new(-12256.16015625,  331.73828125,  -10485.836914062)},
    HauntedQuest1        = {Mon="Reborn Skeleton",     Qdata=1, NameMon="Reborn Skeleton",     PosM=CFrame.new(-8763.7236328125, 165.72299194336,  6159.8618164062)},
    HauntedQuest2        = {Mon="Demonic Soul",        Qdata=1, NameMon="Demonic Soul",        PosM=CFrame.new(-9505.8720703125, 172.10482788086,  6158.9931640625)},
    NutsIslandQuest      = {Mon="Peanut Scout",        Qdata=1, NameMon="Peanut Scout",        PosM=CFrame.new(-2143.2419433594,  47.721984863281,-10029.995117188)},
    IceCreamIslandQuest  = {Mon="Ice Cream Chef",      Qdata=1, NameMon="Ice Cream Chef",      PosM=CFrame.new(-872.24658203125,  65.81957244873, -10919.95703125)},
    CakeQuest1           = {Mon="Cookie Crafter",      Qdata=1, NameMon="Cookie Crafter",      PosM=CFrame.new(-2374.13671875,    37.798263549805,-12125.30859375)},
    CakeQuest2           = {Mon="Baking Staff",        Qdata=1, NameMon="Baking Staff",        PosM=CFrame.new(-1887.8099365234,  77.618507385254,-12998.350585938)},
    ChocQuest1           = {Mon="Cocoa Warrior",       Qdata=1, NameMon="Cocoa Warrior",       PosM=CFrame.new(-21.553283691406,  80.574996948242,-12352.387695312)},
    ChocQuest2           = {Mon="Sweet Thief",         Qdata=1, NameMon="Sweet Thief",         PosM=CFrame.new(165.1884765625,    76.058853149414,-12600.836914062)},
    TikiQuest1           = {Mon="Isle Outlaw",         Qdata=1, NameMon="Isle Outlaw",         PosM=CFrame.new(-16479.900390625,  226.6117401123,   -300.31143188477)},
    TikiQuest2           = {Mon="Sun-kissed Warrior",  Qdata=1, NameMon="kissed Warrior",      PosM=CFrame.new(-16347,            64,               984)},
    TikiQuest3           = {Mon="Serpent Hunter",      Qdata=1, NameMon="Serpent Hunter",      PosM=CFrame.new(-16645.64,         163.09,          1352.87)},
    SubmergedQuest1      = {Mon="Reef Bandit",         Qdata=1, NameMon="Reef Bandit",         PosM=CFrame.new(11019.1318,      -2146.06812,       9342.3916)},
    SubmergedQuest2      = {Mon="Sea Chanter",         Qdata=1, NameMon="Sea Chanter",         PosM=CFrame.new(10671.2715,      -2057.59155,      10047.2588)},
    SubmergedQuest3      = {Mon="High Disciple",       Qdata=1, NameMon="High Disciple",       PosM=CFrame.new(9750.41602,      -1966.93884,       9753.36035)},
}

--// ===================== QUEST DATA =====================
-- Returns: Mon, Qdata, Qname, NameMon, PosM, PosQ, altData
-- Index:    [1]   [2]    [3]    [4]     [5]   [6]   [7]
local function QuestNeta()
    local I       = player.Data.Level.Value
    local TeamSelf = tostring(plr.Team)
    local Mon, Qdata, Qname, NameMon, PosM, PosQ

    if World1 then
        if I <= 9 then
            if TeamSelf == "Marines" then
                Mon="Trainee"; Qname="MarineQuest"; Qdata=1; NameMon="Trainee"
                PosM=CFrame.new(-2709.67944,24.5206585,2104.24585,-0.744724929,-3.97967455e-08,-0.667371571,4.32403588e-08,1,-1.07884304e-07,.667371571,-1.09201515e-07,-0.744724929)
                PosQ=PosM
            else
                Mon="Bandit"; Qdata=1; Qname="BanditQuest1"; NameMon="Bandit"
                PosM=CFrame.new(1045.9626464844,27.002508163452,1560.8203125)
                PosQ=PosM
            end
        elseif I <= 14 then
            Mon="Monkey"; Qdata=1; Qname="JungleQuest"; NameMon="Monkey"
            PosQ=CFrame.new(-1598.08911,35.5501175,153.377838,0,0,1,0,1,0,-1,0,0)
            PosM=CFrame.new(-1448.5180664062,67.853012084961,11.465796470642)
        elseif I <= 29 then
            Mon="Gorilla"; Qdata=2; Qname="JungleQuest"; NameMon="Gorilla"
            PosQ=CFrame.new(-1598.08911,35.5501175,153.377838,0,0,1,0,1,0,-1,0,0)
            PosM=CFrame.new(-1129.8836669922,40.46354675293,-525.42370605469)
        elseif I <= 39 then
            Mon="Pirate"; Qdata=1; Qname="BuggyQuest1"; NameMon="Pirate"
            PosQ=CFrame.new(-1141.07483,4.10001802,3831.5498,.965929627,0,-0.258804798,0,1,0,.258804798,0,.965929627)
            PosM=CFrame.new(-1103.5134277344,13.752052307129,3896.0910644531)
        elseif I <= 59 then
            Mon="Brute"; Qdata=2; Qname="BuggyQuest1"; NameMon="Brute"
            PosQ=CFrame.new(-1141.07483,4.10001802,3831.5498,.965929627,0,-0.258804798,0,1,0,.258804798,0,.965929627)
            PosM=CFrame.new(-1140.0837402344,14.809885025024,4322.9213867188)
        elseif I <= 74 then
            Mon="Desert Bandit"; Qdata=1; Qname="DesertQuest"; NameMon="Desert Bandit"
            PosQ=CFrame.new(894.488647,5.14000702,4392.43359,.819155693,0,-0.573571265,0,1,0,.573571265,0,.819155693)
            PosM=CFrame.new(924.7998046875,6.4486746788025,4481.5859375)
        elseif I <= 89 then
            Mon="Desert Officer"; Qdata=2; Qname="DesertQuest"; NameMon="Desert Officer"
            PosQ=CFrame.new(894.488647,5.14000702,4392.43359,.819155693,0,-0.573571265,0,1,0,.573571265,0,.819155693)
            PosM=CFrame.new(1608.2822265625,8.6142244338989,4371.0073242188)
        elseif I <= 99 then
            Mon="Snow Bandit"; Qdata=1; Qname="SnowQuest"; NameMon="Snow Bandit"
            PosQ=CFrame.new(1389.74451,88.1519318,-1298.90796,-0.342042685,0,.939684391,0,1,0,-0.939684391,0,-0.342042685)
            PosM=CFrame.new(1354.3479003906,87.272773742676,-1393.9465332031)
        elseif I <= 119 then
            Mon="Snowman"; Qdata=2; Qname="SnowQuest"; NameMon="Snowman"
            PosQ=CFrame.new(1389.74451,88.1519318,-1298.90796,-0.342042685,0,.939684391,0,1,0,-0.939684391,0,-0.342042685)
            PosM=CFrame.new(1200,144,-1550)
        elseif I <= 149 then
            Mon="Chief Petty Officer"; Qdata=1; Qname="MarineQuest2"; NameMon="Chief Petty Officer"
            PosQ=CFrame.new(-5039.58643,27.3500385,4324.68018,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-4881.2309570312,22.652044296265,4273.7524414062)
        elseif I <= 174 then
            Mon="Sky Bandit"; Qdata=1; Qname="SkyQuest"; NameMon="Sky Bandit"
            PosQ=CFrame.new(-4839.53027,716.368591,-2619.44165,.866007268,0,.500031412,0,1,0,-0.500031412,0,.866007268)
            PosM=CFrame.new(-4953.20703125,295.74420166016,-2899.2290039062)
        elseif I <= 189 then
            Mon="Dark Master"; Qdata=2; Qname="SkyQuest"; NameMon="Dark Master"
            PosQ=CFrame.new(-4839.53027,716.368591,-2619.44165,.866007268,0,.500031412,0,1,0,-0.500031412,0,.866007268)
            PosM=CFrame.new(-5259.8447265625,391.39767456055,-2229.0354003906)
        elseif I <= 209 then
            Mon="Prisoner"; Qdata=1; Qname="PrisonerQuest"; NameMon="Prisoner"
            PosQ=CFrame.new(5308.93115,1.65517521,475.120514,-0.0894274712,-5.00292918e-09,-0.995993316,1.60817859e-09,1,-5.16744869e-09,.995993316,-2.06384709e-09,-0.0894274712)
            PosM=CFrame.new(5098.9736328125,-0.3204058110714,474.23733520508)
        elseif I <= 249 then
            Mon="Dangerous Prisoner"; Qdata=2; Qname="PrisonerQuest"; NameMon="Dangerous Prisoner"
            PosQ=CFrame.new(5308.93115,1.65517521,475.120514,-0.0894274712,-5.00292918e-09,-0.995993316,1.60817859e-09,1,-5.16744869e-09,.995993316,-2.06384709e-09,-0.0894274712)
            PosM=CFrame.new(5654.5634765625,15.633401870728,866.29919433594)
        elseif I <= 274 then
            Mon="Toga Warrior"; Qdata=1; Qname="ColosseumQuest"; NameMon="Toga Warrior"
            PosQ=CFrame.new(-1580.04663,6.35000277,-2986.47534,-0.515037298,0,-0.857167721,0,1,0,.857167721,0,-0.515037298)
            PosM=CFrame.new(-1820.21484375,51.683856964111,-2740.6650390625)
        elseif I <= 299 then
            Mon="Gladiator"; Qdata=2; Qname="ColosseumQuest"; NameMon="Gladiator"
            PosQ=CFrame.new(-1580.04663,6.35000277,-2986.47534,-0.515037298,0,-0.857167721,0,1,0,.857167721,0,-0.515037298)
            PosM=CFrame.new(-1292.8381347656,56.380882263184,-3339.0314941406)
        elseif I <= 324 then
            Mon="Military Soldier"; Qdata=1; Qname="MagmaQuest"; NameMon="Military Soldier"
            PosQ=CFrame.new(-5313.37012,10.9500084,8515.29395,-0.499959469,0,.866048813,0,1,0,-0.866048813,0,-0.499959469)
            PosM=CFrame.new(-5411.1645507812,11.081554412842,8454.29296875)
        elseif I <= 374 then
            Mon="Military Spy"; Qdata=2; Qname="MagmaQuest"; NameMon="Military Spy"
            PosQ=CFrame.new(-5313.37012,10.9500084,8515.29395,-0.499959469,0,.866048813,0,1,0,-0.866048813,0,-0.499959469)
            PosM=CFrame.new(-5802.8681640625,86.262413024902,8828.859375)
        elseif I <= 399 then
            Mon="Fishman Warrior"; Qdata=1; Qname="FishmanQuest"; NameMon="Fishman Warrior"
            PosQ=CFrame.new(61122.65234375,18.497442245483,1569.3997802734)
            PosM=CFrame.new(60878.30078125,18.482830047607,1543.7574462891)
        elseif I <= 449 then
            Mon="Fishman Commando"; Qdata=2; Qname="FishmanQuest"; NameMon="Fishman Commando"
            PosQ=CFrame.new(61122.65234375,18.497442245483,1569.3997802734)
            PosM=CFrame.new(61922.6328125,18.482830047607,1493.9343261719)
        elseif I <= 474 then
            Mon="God's Guard"; Qdata=1; Qname="SkyExp1Quest"; NameMon="God's Guard"
            PosQ=CFrame.new(-4721.88867,843.874695,-1949.96643,.996191859,0,-0.0871884301,0,1,0,.0871884301,0,.996191859)
            PosM=CFrame.new(-4710.04296875,845.27697753906,-1927.3079833984)
        elseif I <= 524 then
            Mon="Shanda"; Qdata=2; Qname="SkyExp1Quest"; NameMon="Shanda"
            PosQ=CFrame.new(-7859.09814,5544.19043,-381.476196,-0.422592998,0,.906319618,0,1,0,-0.906319618,0,-0.422592998)
            PosM=CFrame.new(-7678.4897460938,5566.4038085938,-497.21560668945)
        elseif I <= 549 then
            Mon="Royal Squad"; Qdata=1; Qname="SkyExp2Quest"; NameMon="Royal Squad"
            PosQ=CFrame.new(-7906.81592,5634.6626,-1411.99194,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-7624.2524414062,5658.1333007812,-1467.3542480469)
        elseif I <= 624 then
            Mon="Royal Soldier"; Qdata=2; Qname="SkyExp2Quest"; NameMon="Royal Soldier"
            PosQ=CFrame.new(-7906.81592,5634.6626,-1411.99194,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-7836.7534179688,5645.6640625,-1790.6236572266)
        elseif I <= 649 then
            Mon="Galley Pirate"; Qdata=1; Qname="FountainQuest"; NameMon="Galley Pirate"
            PosQ=CFrame.new(5259.81982,37.3500175,4050.0293,.087131381,0,.996196866,0,1,0,-0.996196866,0,.087131381)
            PosM=CFrame.new(5551.0219726562,78.901351928711,3930.4128417969)
        elseif I <= 699 then
            Mon="Galley Captain"; Qdata=2; Qname="FountainQuest"; NameMon="Galley Captain"
            PosQ=CFrame.new(5259.81982,37.3500175,4050.0293,.087131381,0,.996196866,0,1,0,-0.996196866,0,.087131381)
            PosM=CFrame.new(5441.9516601562,42.502059936523,4950.09375)
        end
    elseif World2 then
        if I <= 724 then
            Mon="Raider"; Qdata=1; Qname="Area1Quest"; NameMon="Raider"
            PosQ=CFrame.new(-429.543518,71.7699966,1836.18188,-0.22495985,0,-0.974368095,0,1,0,.974368095,0,-0.22495985)
            PosM=CFrame.new(-728.32672119141,52.779319763184,2345.7705078125)
        elseif I <= 774 then
            Mon="Mercenary"; Qdata=2; Qname="Area1Quest"; NameMon="Mercenary"
            PosQ=CFrame.new(-429.543518,71.7699966,1836.18188,-0.22495985,0,-0.974368095,0,1,0,.974368095,0,-0.22495985)
            PosM=CFrame.new(-1004.3244018555,80.158866882324,1424.6193847656)
        elseif I <= 799 then
            Mon="Swan Pirate"; Qdata=1; Qname="Area2Quest"; NameMon="Swan Pirate"
            PosQ=CFrame.new(638.43811,71.769989,918.282898,.139203906,0,.99026376,0,1,0,-0.99026376,0,.139203906)
            PosM=CFrame.new(1068.6643066406,137.61428833008,1322.1060791016)
        elseif I <= 874 then
            Mon="Factory Staff"; Qdata=2; Qname="Area2Quest"; NameMon="Factory Staff"
            PosQ=CFrame.new(632.698608,73.1055908,918.666321,-0.0319722369,8.96074881e-10,-0.999488771,1.36326533e-10,1,8.92172336e-10,.999488771,-1.07732087e-10,-0.0319722369)
            PosM=CFrame.new(73.078674316406,81.863441467285,-27.470672607422)
        elseif I <= 899 then
            Mon="Marine Lieutenant"; Qdata=1; Qname="MarineQuest3"; NameMon="Marine Lieutenant"
            PosQ=CFrame.new(-2440.79639,71.7140732,-3216.06812,.866007268,0,.500031412,0,1,0,-0.500031412,0,.866007268)
            PosM=CFrame.new(-2821.3723144531,75.897277832031,-3070.0891113281)
        elseif I <= 949 then
            Mon="Marine Captain"; Qdata=2; Qname="MarineQuest3"; NameMon="Marine Captain"
            PosQ=CFrame.new(-2440.79639,71.7140732,-3216.06812,.866007268,0,.500031412,0,1,0,-0.500031412,0,.866007268)
            PosM=CFrame.new(-1861.2310791016,80.176582336426,-3254.6975097656)
        elseif I <= 974 then
            Mon="Zombie"; Qdata=1; Qname="ZombieQuest"; NameMon="Zombie"
            PosQ=CFrame.new(-5497.06152,47.5923004,-795.237061,-0.29242146,0,-0.95628953,0,1,0,.95628953,0,-0.29242146)
            PosM=CFrame.new(-5657.7768554688,78.969734191895,-928.68701171875)
        elseif I <= 999 then
            Mon="Vampire"; Qdata=2; Qname="ZombieQuest"; NameMon="Vampire"
            PosQ=CFrame.new(-5497.06152,47.5923004,-795.237061,-0.29242146,0,-0.95628953,0,1,0,.95628953,0,-0.29242146)
            PosM=CFrame.new(-6037.66796875,32.184638977051,-1340.6597900391)
        elseif I <= 1049 then
            Mon="Snow Trooper"; Qdata=1; Qname="SnowMountainQuest"; NameMon="Snow Trooper"
            PosQ=CFrame.new(609.858826,400.119904,-5372.25928,-0.374604106,0,.92718488,0,1,0,-0.92718488,0,-0.374604106)
            PosM=CFrame.new(549.14733886719,427.38705444336,-5563.6987304688)
        elseif I <= 1099 then
            Mon="Winter Warrior"; Qdata=2; Qname="SnowMountainQuest"; NameMon="Winter Warrior"
            PosQ=CFrame.new(609.858826,400.119904,-5372.25928,-0.374604106,0,.92718488,0,1,0,-0.92718488,0,-0.374604106)
            PosM=CFrame.new(1142.7451171875,475.63980102539,-5199.4165039062)
        elseif I <= 1124 then
            Mon="Lab Subordinate"; Qdata=1; Qname="IceSideQuest"; NameMon="Lab Subordinate"
            PosQ=CFrame.new(-6064.06885,15.2422857,-4902.97852,.453972578,0,-0.891015649,0,1,0,.891015649,0,.453972578)
            PosM=CFrame.new(-5707.4716796875,15.951709747314,-4513.3920898438)
        elseif I <= 1174 then
            Mon="Horned Warrior"; Qdata=2; Qname="IceSideQuest"; NameMon="Horned Warrior"
            PosQ=CFrame.new(-6064.06885,15.2422857,-4902.97852,.453972578,0,-0.891015649,0,1,0,.891015649,0,.453972578)
            PosM=CFrame.new(-6341.3666992188,15.951770782471,-5723.162109375)
        elseif I <= 1199 then
            Mon="Magma Ninja"; Qdata=1; Qname="FireSideQuest"; NameMon="Magma Ninja"
            PosQ=CFrame.new(-5428.03174,15.0622921,-5299.43457,-0.882952213,0,.469463557,0,1,0,-0.469463557,0,-0.882952213)
            PosM=CFrame.new(-5449.6728515625,76.658744812012,-5808.2006835938)
        elseif I <= 1249 then
            Mon="Lava Pirate"; Qdata=2; Qname="FireSideQuest"; NameMon="Lava Pirate"
            PosQ=CFrame.new(-5428.03174,15.0622921,-5299.43457,-0.882952213,0,.469463557,0,1,0,-0.469463557,0,-0.882952213)
            PosM=CFrame.new(-5213.3315429688,49.737880706787,-4701.451171875)
        elseif I <= 1274 then
            Mon="Ship Deckhand"; Qdata=1; Qname="ShipQuest1"; NameMon="Ship Deckhand"
            PosQ=CFrame.new(1037.80127,125.092171,32911.6016)
            PosM=CFrame.new(1212.0111083984,150.79205322266,33059.24609375)
        elseif I <= 1299 then
            Mon="Ship Engineer"; Qdata=2; Qname="ShipQuest1"; NameMon="Ship Engineer"
            PosQ=CFrame.new(1037.80127,125.092171,32911.6016)
            PosM=CFrame.new(919.47863769531,43.544013977051,32779.96875)
        elseif I <= 1324 then
            Mon="Ship Steward"; Qdata=1; Qname="ShipQuest2"; NameMon="Ship Steward"
            PosQ=CFrame.new(968.80957,125.092171,33244.125)
            PosM=CFrame.new(919.43853759766,129.55599975586,33436.03515625)
        elseif I <= 1349 then
            Mon="Ship Officer"; Qdata=2; Qname="ShipQuest2"; NameMon="Ship Officer"
            PosQ=CFrame.new(968.80957,125.092171,33244.125)
            PosM=CFrame.new(1036.0179443359,181.4390411377,33315.7265625)
        elseif I <= 1374 then
            Mon="Arctic Warrior"; Qdata=1; Qname="FrostQuest"; NameMon="Arctic Warrior"
            PosQ=CFrame.new(5667.6582,26.7997818,-6486.08984,-0.933587909,0,-0.358349502,0,1,0,.358349502,0,-0.933587909)
            PosM=CFrame.new(5966.24609375,62.970020294189,-6179.3828125)
        elseif I <= 1424 then
            Mon="Snow Lurker"; Qdata=2; Qname="FrostQuest"; NameMon="Snow Lurker"
            PosQ=CFrame.new(5667.6582,26.7997818,-6486.08984,-0.933587909,0,-0.358349502,0,1,0,.358349502,0,-0.933587909)
            PosM=CFrame.new(5407.0737304688,69.194374084473,-6880.8803710938)
        elseif I <= 1449 then
            Mon="Sea Soldier"; Qdata=1; Qname="ForgottenQuest"; NameMon="Sea Soldier"
            PosQ=CFrame.new(-3054.44458,235.544281,-10142.8193,.990270376,0,-0.13915664,0,1,0,.13915664,0,.990270376)
            PosM=CFrame.new(-3028.2236328125,64.674514770508,-9775.4267578125)
        elseif I <= 1499 then
            Mon="Water Fighter"; Qdata=2; Qname="ForgottenQuest"; NameMon="Water Fighter"
            PosQ=CFrame.new(-3054.44458,235.544281,-10142.8193,.990270376,0,-0.13915664,0,1,0,.13915664,0,.990270376)
            PosM=CFrame.new(-3352.9013671875,285.01556396484,-10534.841796875)
        end
    elseif World3 then
        if I <= 1524 then
            Mon="Pirate Millionaire"; Qdata=1; Qname="PiratePortQuest"; NameMon="Pirate Millionaire"
            PosQ=CFrame.new(-290.07,42.90,5581.59)
            PosM=CFrame.new(-246.00,47.31,5584.10)
        elseif I <= 1574 then
            Mon="Pistol Billionaire"; Qdata=2; Qname="PiratePortQuest"; NameMon="Pistol Billionaire"
            PosQ=CFrame.new(-290.07,42.90,5581.59)
            PosM=CFrame.new(-187.33,86.24,6013.51)
        elseif I <= 1599 then
            Mon="Dragon Crew Warrior"; Qdata=1; Qname="DragonCrewQuest"; NameMon="Dragon Crew Warrior"
            PosQ=CFrame.new(6737.06055,127.417763,-712.300659,-0.463954359,-7.19574755e-09,0.885859072,7.69187665e-08,1,4.84078626e-08,-0.885859072,9.05982276e-08,-0.463954359)
            PosM=CFrame.new(6709.76367,52.3442993,-1139.02966,-0.763515472,0,0.645789504,0,1,0,-0.645789504,0,-0.763515472)
        elseif I <= 1624 then
            Mon="Dragon Crew Archer"; Qdata=2; Qname="DragonCrewQuest"; NameMon="Dragon Crew Archer"
            PosQ=CFrame.new(6737.06055,127.417763,-712.300659,-0.463954359,-7.19574755e-09,0.885859072,7.69187665e-08,1,4.84078626e-08,-0.885859072,9.05982276e-08,-0.463954359)
            PosM=CFrame.new(6668.76172,481.376923,329.12207,-0.121787429,0,-0.992556155,0,1,0,0.992556155,0,-0.121787429)
        elseif I <= 1649 then
            Mon="Hydra Enforcer"; Qdata=1; Qname="VenomCrewQuest"; NameMon="Hydra Enforcer"
            PosQ=CFrame.new(5206.40185546875,1004.10498046875,748.3504638671875)
            PosM=CFrame.new(4547.11523,1003.10217,334.194824,0.388810456,-0,-0.921317935,0,1,-0,0.921317935,0,0.388810456)
        elseif I <= 1699 then
            Mon="Venomous Assailant"; Qdata=2; Qname="VenomCrewQuest"; NameMon="Venomous Assailant"
            PosQ=CFrame.new(5206.40185546875,1004.10498046875,748.3504638671875)
            PosM=CFrame.new(4674.92676,1134.82654,996.308838,0.731321394,-0,-0.682033002,0,1,-0,0.682033002,0,0.731321394)
        elseif I <= 1724 then
            Mon="Marine Commodore"; Qdata=1; Qname="MarineTreeIsland"; NameMon="Marine Commodore"
            PosQ=CFrame.new(2482,74,-6788)
            PosM=CFrame.new(2519,109,-7633)
        elseif I <= 1774 then
            Mon="Marine Rear Admiral"; Qdata=2; Qname="MarineTreeIsland"; NameMon="Marine Rear Admiral"
            PosQ=CFrame.new(2482,74,-6788)
            PosM=CFrame.new(3722,169,-7038)
        elseif I <= 1799 then
            Mon="Fishman Raider"; Qdata=1; Qname="DeepForestIsland3"; NameMon="Fishman Raider"
            PosQ=CFrame.new(-10581.6563,330.872955,-8761.18652,-0.882952213,0,.469463557,0,1,0,-0.469463557,0,-0.882952213)
            PosM=CFrame.new(-10407.526367188,331.76263427734,-8368.5166015625)
        elseif I <= 1824 then
            Mon="Fishman Captain"; Qdata=2; Qname="DeepForestIsland3"; NameMon="Fishman Captain"
            PosQ=CFrame.new(-10581.6563,330.872955,-8761.18652,-0.882952213,0,.469463557,0,1,0,-0.469463557,0,-0.882952213)
            PosM=CFrame.new(-10994.701171875,352.38140869141,-9002.1103515625)
        elseif I <= 1849 then
            Mon="Forest Pirate"; Qdata=1; Qname="DeepForestIsland"; NameMon="Forest Pirate"
            PosQ=CFrame.new(-13234.04,331.488495,-7625.40137,.707134247,0,-0.707079291,0,1,0,.707079291,0,.707134247)
            PosM=CFrame.new(-13274.478515625,332.37814331055,-7769.5805664062)
        elseif I <= 1899 then
            Mon="Mythological Pirate"; Qdata=2; Qname="DeepForestIsland"; NameMon="Mythological Pirate"
            PosQ=CFrame.new(-13234.04,331.488495,-7625.40137,.707134247,0,-0.707079291,0,1,0,.707079291,0,.707134247)
            PosM=CFrame.new(-13680.607421875,501.08154296875,-6991.189453125)
        elseif I <= 1924 then
            Mon="Jungle Pirate"; Qdata=1; Qname="DeepForestIsland2"; NameMon="Jungle Pirate"
            PosQ=CFrame.new(-12680.3818,389.971039,-9902.01953,-0.0871315002,0,.996196866,0,1,0,-0.996196866,0,-0.0871315002)
            PosM=CFrame.new(-12256.16015625,331.73828125,-10485.836914062)
        elseif I <= 1974 then
            Mon="Musketeer Pirate"; Qdata=2; Qname="DeepForestIsland2"; NameMon="Musketeer Pirate"
            PosQ=CFrame.new(-12680.3818,389.971039,-9902.01953,-0.0871315002,0,.996196866,0,1,0,-0.996196866,0,-0.0871315002)
            PosM=CFrame.new(-13457.904296875,391.54565429688,-9859.177734375)
        elseif I <= 1999 then
            Mon="Reborn Skeleton"; Qdata=1; Qname="HauntedQuest1"; NameMon="Reborn Skeleton"
            PosQ=CFrame.new(-9479.2168,141.215088,5566.09277,0,0,1,0,1,0,-1,0,0)
            PosM=CFrame.new(-8763.7236328125,165.72299194336,6159.8618164062)
        elseif I <= 2024 then
            Mon="Living Zombie"; Qdata=2; Qname="HauntedQuest1"; NameMon="Living Zombie"
            PosQ=CFrame.new(-9479.2168,141.215088,5566.09277,0,0,1,0,1,0,-1,0,0)
            PosM=CFrame.new(-10144.131835938,138.6266784668,5838.0888671875)
        elseif I <= 2049 then
            Mon="Demonic Soul"; Qdata=1; Qname="HauntedQuest2"; NameMon="Demonic Soul"
            PosQ=CFrame.new(-9516.99316,172.017181,6078.46533,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-9505.8720703125,172.10482788086,6158.9931640625)
        elseif I <= 2074 then
            Mon="Posessed Mummy"; Qdata=2; Qname="HauntedQuest2"; NameMon="Posessed Mummy"
            PosQ=CFrame.new(-9516.99316,172.017181,6078.46533,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-9582.0224609375,6.2515273094177,6205.478515625)
        elseif I <= 2099 then
            Mon="Peanut Scout"; Qdata=1; Qname="NutsIslandQuest"; NameMon="Peanut Scout"
            PosQ=CFrame.new(-2104.3908691406,38.104167938232,-10194.21875,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-2143.2419433594,47.721984863281,-10029.995117188)
        elseif I <= 2124 then
            Mon="Peanut President"; Qdata=2; Qname="NutsIslandQuest"; NameMon="Peanut President"
            PosQ=CFrame.new(-2104.3908691406,38.104167938232,-10194.21875,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-1859.3540039062,38.103168487549,-10422.4296875)
        elseif I <= 2149 then
            Mon="Ice Cream Chef"; Qdata=1; Qname="IceCreamIslandQuest"; NameMon="Ice Cream Chef"
            PosQ=CFrame.new(-820.64825439453,65.819526672363,-10965.795898438,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-872.24658203125,65.81957244873,-10919.95703125)
        elseif I <= 2199 then
            Mon="Ice Cream Commander"; Qdata=2; Qname="IceCreamIslandQuest"; NameMon="Ice Cream Commander"
            PosQ=CFrame.new(-820.64825439453,65.819526672363,-10965.795898438,0,0,-1,0,1,0,1,0,0)
            PosM=CFrame.new(-558.06103515625,112.04895782471,-11290.774414062)
        elseif I <= 2224 then
            Mon="Cookie Crafter"; Qdata=1; Qname="CakeQuest1"; NameMon="Cookie Crafter"
            PosQ=CFrame.new(-2021.32007,37.7982254,-12028.7295,.957576931,-8.80302053e-08,.288177818,6.9301187e-08,1,7.51931211e-08,-0.288177818,-5.2032135e-08,.957576931)
            PosM=CFrame.new(-2374.13671875,37.798263549805,-12125.30859375)
        elseif I <= 2249 then
            Mon="Cake Guard"; Qdata=2; Qname="CakeQuest1"; NameMon="Cake Guard"
            PosQ=CFrame.new(-2021.32007,37.7982254,-12028.7295,.957576931,-8.80302053e-08,.288177818,6.9301187e-08,1,7.51931211e-08,-0.288177818,-5.2032135e-08,.957576931)
            PosM=CFrame.new(-1598.3070068359,43.773197174072,-12244.581054688)
        elseif I <= 2274 then
            Mon="Baking Staff"; Qdata=1; Qname="CakeQuest2"; NameMon="Baking Staff"
            PosQ=CFrame.new(-1927.91602,37.7981339,-12842.5391,-0.96804446,4.22142143e-08,.250778586,4.74911062e-08,1,1.49904711e-08,-0.250778586,2.64211941e-08,-0.96804446)
            PosM=CFrame.new(-1887.8099365234,77.618507385254,-12998.350585938)
        elseif I <= 2299 then
            Mon="Head Baker"; Qdata=2; Qname="CakeQuest2"; NameMon="Head Baker"
            PosQ=CFrame.new(-1927.91602,37.7981339,-12842.5391,-0.96804446,4.22142143e-08,.250778586,4.74911062e-08,1,1.49904711e-08,-0.250778586,2.64211941e-08,-0.96804446)
            PosM=CFrame.new(-2216.1882324219,82.884521484375,-12869.293945312)
        elseif I <= 2324 then
            Mon="Cocoa Warrior"; Qdata=1; Qname="ChocQuest1"; NameMon="Cocoa Warrior"
            PosQ=CFrame.new(233.22836303711,29.876001358032,-12201.233398438)
            PosM=CFrame.new(-21.553283691406,80.574996948242,-12352.387695312)
        elseif I <= 2349 then
            Mon="Chocolate Bar Battler"; Qdata=2; Qname="ChocQuest1"; NameMon="Chocolate Bar Battler"
            PosQ=CFrame.new(233.22836303711,29.876001358032,-12201.233398438)
            PosM=CFrame.new(582.59057617188,77.188095092773,-12463.162109375)
        elseif I <= 2374 then
            Mon="Sweet Thief"; Qdata=1; Qname="ChocQuest2"; NameMon="Sweet Thief"
            PosQ=CFrame.new(150.50663757324,30.693693161011,-12774.502929688)
            PosM=CFrame.new(165.1884765625,76.058853149414,-12600.836914062)
        elseif I <= 2399 then
            Mon="Candy Rebel"; Qdata=2; Qname="ChocQuest2"; NameMon="Candy Rebel"
            PosQ=CFrame.new(150.50663757324,30.693693161011,-12774.502929688)
            PosM=CFrame.new(134.86563110352,77.247680664062,-12876.547851562)
        elseif I <= 2449 then
            Mon="Candy Pirate"; Qdata=1; Qname="CandyQuest1"; NameMon="Candy Pirate"
            PosQ=CFrame.new(-1150.0400390625,20.378934860229,-14446.334960938)
            PosM=CFrame.new(-1310.5003662109,26.016523361206,-14562.404296875)
        elseif I <= 2474 then
            Mon="Isle Outlaw"; Qdata=1; Qname="TikiQuest1"; NameMon="Isle Outlaw"
            PosQ=CFrame.new(-16548.8164,55.6059914,-172.8125,.213092566,0,-0.977032006,0,1,0,.977032006,0,.213092566)
            PosM=CFrame.new(-16479.900390625,226.6117401123,-300.31143188477)
        elseif I <= 2499 then
            Mon="Island Boy"; Qdata=2; Qname="TikiQuest1"; NameMon="Island Boy"
            PosQ=CFrame.new(-16548.8164,55.6059914,-172.8125,.213092566,0,-0.977032006,0,1,0,.977032006,0,.213092566)
            PosM=CFrame.new(-16849.396484375,192.86505126953,-150.78532409668)
        elseif I <= 2524 then
            Mon="Sun-kissed Warrior"; Qdata=1; Qname="TikiQuest2"; NameMon="kissed Warrior"
            PosM=CFrame.new(-16347,64,984)
            PosQ=CFrame.new(-16538,55,1049)
        elseif I <= 2550 then
            Mon="Isle Champion"; Qdata=2; Qname="TikiQuest2"; NameMon="Isle Champion"
            PosQ=CFrame.new(-16541.0215,57.3082275,1051.46118,.0410757065,0,-0.999156058,0,1,0,.999156058,0,.0410757065)
            PosM=CFrame.new(-16602.1015625,130.38734436035,1087.2456054688)
        elseif I <= 2574 then
            Mon="Serpent Hunter"; Qdata=1; Qname="TikiQuest3"; NameMon="Serpent Hunter"
            PosQ=CFrame.new(-16668.03,105.32,1568.60)
            PosM=CFrame.new(-16645.64,163.09,1352.87)
        elseif I <= 2599 then
            Mon="Skull Slayer"; Qdata=2; Qname="TikiQuest3"; NameMon="Skull Slayer"
            PosQ=CFrame.new(-16668.03,105.32,1568.60)
            PosM=CFrame.new(-16709.49,419.68,1751.09)
        elseif I <= 2624 then
            Mon="Reef Bandit"; Qdata=1; Qname="SubmergedQuest1"; NameMon="Reef Bandit"
            PosQ=CFrame.new(10778.875,-2087.72437,9265.18359,0.934615612,-9.33109447e-08,-0.355659455,9.17655143e-08,1,-2.12154276e-08,0.355659455,-1.28090019e-08,0.934615612)
            PosM=CFrame.new(11019.1318,-2146.06812,9342.3916,-0.719955266,-1.74275385e-08,0.69402045,5.76556367e-08,1,8.49211546e-08,-0.69402045,1.01153624e-07,-0.719955266)
        elseif I <= 2649 then
            Mon="Coral Pirate"; Qdata=2; Qname="SubmergedQuest1"; NameMon="Coral Pirate"
            PosQ=CFrame.new(10778.875,-2087.72437,9265.18359,0.934615612,-9.33109447e-08,-0.355659455,9.17655143e-08,1,-2.12154276e-08,0.355659455,-1.28090019e-08,0.934615612)
            PosM=CFrame.new(10808.6006,-2030.36145,9364.2334,-0.775185347,-0.0359364748,0.6307109,0.0615428537,0.989336014,0.132010356,-0.628728986,0.141148239,-0.764707148)
        elseif I <= 2674 then
            Mon="Sea Chanter"; Qdata=1; Qname="SubmergedQuest2"; NameMon="Sea Chanter"
            PosQ=CFrame.new(10880.6855,-2086.20044,10032.624,-0.321384728,9.87648434e-08,-0.946948707,7.13271007e-08,1,8.00902953e-08,0.946948707,-4.18033075e-08,-0.321384728)
            PosM=CFrame.new(10671.2715,-2057.59155,10047.2588,-0.846484065,-3.11045447e-08,0.532414079,-5.55383117e-08,1,-2.98785316e-08,-0.532414079,-5.48610757e-08,-0.846484065)
        elseif I <= 2699 then
            Mon="Ocean Prophet"; Qdata=2; Qname="SubmergedQuest2"; NameMon="Ocean Prophet"
            PosQ=CFrame.new(10880.6855,-2086.20044,10032.624,-0.321384728,9.87648434e-08,-0.946948707,7.13271007e-08,1,8.00902953e-08,0.946948707,-4.18033075e-08,-0.321384728)
            PosM=CFrame.new(11008.5195,-2007.72839,10223.0791,-0.688615739,2.33523378e-09,-0.725126445,2.99292546e-09,1,3.78221315e-10,0.725126445,-1.90980032e-09,-0.688615739)
        elseif I <= 2724 then
            Mon="High Disciple"; Qdata=1; Qname="SubmergedQuest3"; NameMon="High Disciple"
            PosQ=CFrame.new(9640.08789,-1992.44507,9613.65234,-0.957327187,4.11991223e-08,0.289006323,1.5775445e-08,1,-9.02985846e-08,-0.289006323,-8.18860855e-08,-0.957327187)
            PosM=CFrame.new(9750.41602,-1966.93884,9753.36035,-0.749824047,5.57797613e-08,-0.661637306,2.03500754e-08,1,6.1243199e-08,0.661637306,3.24572511e-08,-0.749824047)
        else
            Mon="Grand Devotee"; Qdata=2; Qname="SubmergedQuest3"; NameMon="Grand Devotee"
            PosQ=CFrame.new(9640.08789,-1992.44507,9613.65234,-0.957327187,4.11991223e-08,0.289006323,1.5775445e-08,1,-9.02985846e-08,-0.289006323,-8.18860855e-08,-0.957327187)
            PosM=CFrame.new(9611.70508,-1993.47119,9882.68848,-0.591375351,4.14332426e-08,-0.806396425,4.73774868e-08,1,1.66361875e-08,0.806396425,-2.83668058e-08,-0.591375351)
        end
    end

    -- Dual quest: if Qdata=2 and area exists in DualQuestPairings → pass altData
    local altData = nil
    if Qdata == 2 and Qname and DualQuestPairings[Qname] then
        altData = DualQuestPairings[Qname]
    end

    return Mon, Qdata, Qname, NameMon, PosM, PosQ, altData
end

--// ===================== WEAPON SELECTION =====================
-- _G.ChooseWP   = loại weapon được chọn từ dropdown
-- _G.SelectWeapon = tên tool cụ thể trong backpack

local function selectWeapon()
    pcall(function()
        -- Cho phép khi bất kỳ chế độ farm nào đang bật
        local anyFarming = getgenv().IsFarming or _G.AutoFarm_Bone or _G.Auto_Cake_Prince
        if not anyFarming then return end
        if getgenv().BuddhaTransforming then return end

        local choice = _G.ChooseWP
        if not choice or choice == "" then return end

        local tooltipMap = {
            ["Melee"]     = "Melee",
            ["Sword"]     = "Sword",
            ["Gun"]       = "Gun",
            ["Blox Fruit"]= "Blox Fruit",
        }
        local tooltip = tooltipMap[choice]
        if not tooltip then return end

        for _, v in pairs(player.Backpack:GetChildren()) do
            if v.ToolTip == tooltip and player.Backpack:FindFirstChild(tostring(v.Name)) then
                _G.SelectWeapon = v.Name
                break
            end
        end

        if _G.SelectWeapon and player.Character then
            local weapon = player.Backpack:FindFirstChild(_G.SelectWeapon)
            if weapon then
                local equipped = player.Character:FindFirstChildOfClass("Tool")
                if not equipped or equipped.Name ~= _G.SelectWeapon then
                    player.Character.Humanoid:EquipTool(weapon)
                end
            end
        end
    end)
end

local function updateSelectedWeapon() selectWeapon() end
local function equipSelectedWeapon()  selectWeapon() end

--// ===================== WAIT ARRIVAL =====================
-- Chờ nhân vật đến gần targetPos trong vòng timeoutSec giây.
-- Trả về true nếu đến nơi, false nếu timeout hoặc IsFarming tắt.
local function waitArrival(targetPos, threshold, timeoutSec)
    return _waitArrival(targetPos, threshold, timeoutSec)
end

-- Helper đọc quest GUI an toàn
local function getQuestInfo()
    local visible = false
    local title   = ""
    pcall(function()
        local main = plr.PlayerGui:FindFirstChild("Main")
        if main and main:FindFirstChild("Quest") then
            visible = main.Quest.Visible
            if visible then
                title = main.Quest.Container.QuestTitle.Title.Text
            end
        end
    end)
    return visible, title
end

--// ===================== AUTO BUSO (background) =====================
local function activateBuso()
    pcall(function()
        local char = plr.Character
        if not char then return end
        local hasBuso = char:FindFirstChild("HasBuso") or char:FindFirstChild("Buso")
        if not hasBuso then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(1)
        local anyFarm = getgenv().IsFarming or _G.AutoFarm_Bone or _G.Auto_Cake_Prince
        if anyFarm then activateBuso() end
    end
end)

--// ===================== BRING ENEMY (spawn loop — 0.1s) =====================
-- Fly mob farm + TẤT CẢ mob phụ cùng loại trong range về _lockedBringPos mỗi 0.1s.
-- Dùng BodyVelocity để fly mob về đích thay vì teleport thẳng.
-- Speed fly = _getMoveSpeed() (speed tween). Khi đã vào ≤5 stud → snap vào đích.
-- Không bring nếu có player khác trong phạm vi 500 stud quanh player.
-- Khi Spin Bring bật, Heartbeat spin loop tự xử lý — loop này chỉ skip.
-- CurrentTargetMob và _lockedBringPos phải được set bởi từng farm loop.

-- Helper: gắn BodyVelocity vào HRP của mob để fly về targetPos
local function _flyMobToward(hrp, targetPos, speed)
    local dir = targetPos - hrp.Position
    local dist = dir.Magnitude
    if dist <= 5 then
        -- Đã gần: snap thẳng vào đích, dừng BV
        pcall(function() hrp.CFrame = CFrame.new(targetPos) end)
        local bv = hrp:FindFirstChild("_MobFlyBV")
        if bv then bv:Destroy() end
        return
    end
    local vel = dir.Unit * math.min(speed, dist / 0.1)
    local bv  = hrp:FindFirstChild("_MobFlyBV")
    if not bv then
        bv          = Instance.new("BodyVelocity")
        bv.Name     = "_MobFlyBV"
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Parent   = hrp
    end
    bv.Velocity = vel
    sethiddenproperty(plr, "SimulationRadius", math.huge)
end

--// ===================== BRING MOB (Tween về LockPos liên tục) =================
-- BringMob ON + SpinBring OFF:
--   • > 100 stud tới _lockedBringPos → fly BodyVelocity về đó
--   • ≤ 100 stud tới _lockedBringPos → hủy BV, teleport thẳng về đó
-- BringMob ON + SpinBring ON  → teleport mob về _lockedBringPos rồi spin bán kính 5 stud
-- _lockedBringPos được set CỐ ĐỊNH bởi farm loop khi chọn mob mới.
-- Heartbeat KHÔNG được ghi đè _lockedBringPos — chỉ đọc.
RunService.Heartbeat:Connect(function(dt)
    if not getgenv().BringMob then return end

    local centerCF = _lockedBringPos
    if not centerCF then return end

    local targetMob = getgenv().CurrentTargetMob
    if not targetMob or not targetMob.Parent then return end

    local anyFarmActive = getgenv().IsFarming or _G.AutoFarm_Bone
                       or _G.Auto_Cake_Prince or _G.AutoAuraFarm
    if not anyFarmActive then return end

    local myChar = plr.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    -- Không bring nếu có player khác trong 500 stud
    for _, op in ipairs(Players:GetPlayers()) do
        if op == plr then continue end
        local oc = op.Character
        local oh = oc and oc:FindFirstChild("HumanoidRootPart")
        if oh and (oh.Position - myHRP.Position).Magnitude <= 500 then return end
    end

    local center     = centerCF.Position
    local BRING_SPEED = 300
    local SPIN_RADIUS = 5

    local mobName    = targetMob.Name
    local bringRange = getgenv().BringRange or 300

    -- Thu thập tất cả mob cùng loại (gồm targetMob)
    local allMobs = { targetMob }
    for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
        if enemy == targetMob then continue end
        local hum = enemy:FindFirstChild("Humanoid")
        local hrp = enemy:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 and hrp.Parent and enemy.Name == mobName then
            if (hrp.Position - myHRP.Position).Magnitude <= bringRange then
                table.insert(allMobs, enemy)
            end
        end
    end

    if _G.SpinBring then
        -- ── SpinBring ON: teleport về center rồi spin bán kính 5 stud ─────
        _spinAngle = _spinAngle + (BRING_SPEED / SPIN_RADIUS) * dt

        local n = #allMobs
        for i, mob in ipairs(allMobs) do
            pcall(function()
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                local hum = mob:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end

                -- Xác định vị trí orbit cho mob này
                local angle    = _spinAngle + (2 * math.pi / n) * (i - 1)
                local orbitPos = Vector3.new(
                    center.X + SPIN_RADIUS * math.cos(angle),
                    center.Y,
                    center.Z + SPIN_RADIUS * math.sin(angle)
                )

                -- Teleport trực tiếp tới vị trí orbit
                hrp.CFrame = CFrame.new(orbitPos)
                sethiddenproperty(plr, "SimulationRadius", math.huge)
            end)
        end
    else
        -- ── SpinBring OFF: fly BV khi xa, teleport khi ≤ 100 stud ──────────
        for _, mob in ipairs(allMobs) do
            pcall(function()
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                local hum = mob:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end

                local dist = (hrp.Position - center).Magnitude

                if dist <= 2 then
                    -- Đã ở trung tâm → dừng BV, snap
                    local bv = hrp:FindFirstChild("_MobFlyBV")
                    if bv then bv:Destroy() end
                    hrp.CFrame = CFrame.new(center)
                elseif dist <= 100 then
                    -- ≤ 100 stud → hủy BV, teleport thẳng về mob farm
                    local bv = hrp:FindFirstChild("_MobFlyBV")
                    if bv then bv:Destroy() end
                    hrp.CFrame = CFrame.new(center)
                else
                    -- > 100 stud → fly BodyVelocity về center
                    local bv = hrp:FindFirstChild("_MobFlyBV")
                    if not bv then
                        bv          = Instance.new("BodyVelocity")
                        bv.Name     = "_MobFlyBV"
                        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                        bv.Parent   = hrp
                    end
                    bv.Velocity = (center - hrp.Position).Unit * BRING_SPEED
                end
                sethiddenproperty(plr, "SimulationRadius", math.huge)
            end)
        end
    end
end)


--// ===================== DUNGEON HELPERS =====================
local function selectDungeonWeapon()
    pcall(function()
        if not getgenv().FarmDungeon then return end
        if getgenv().BuddhaTransforming then return end
        local choice = _G.DungeonWeaponChoice
        if not choice or choice == "" then return end
        local tooltipMap = {["Melee"]="Melee",["Sword"]="Sword",["Gun"]="Gun",["Blox Fruit"]="Blox Fruit"}
        local tooltip = tooltipMap[choice]
        if not tooltip then return end
        for _, v in pairs(plr.Backpack:GetChildren()) do
            if v.ToolTip == tooltip then _G.DungeonWeapon = v.Name; break end
        end
        if _G.DungeonWeapon and plr.Character then
            local weapon = plr.Backpack:FindFirstChild(_G.DungeonWeapon)
            if weapon then
                local equipped = plr.Character:FindFirstChildOfClass("Tool")
                if not equipped or equipped.Name ~= _G.DungeonWeapon then
                    plr.Character.Humanoid:EquipTool(weapon)
                end
            end
        end
    end)
end

local function GetFarmCFrame(enemy)
    local hrp = enemy:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp.CFrame * CFrame.new(0, 25, 0)
end

local function AttackEnemy(enemy)
    selectDungeonWeapon()
    activateBuso()
end

local function GetCurrentZone()
    local root = getRoot()
    if not root then return nil end
    local dungeonFolder = workspace.Map:FindFirstChild("Dungeon")
    if not dungeonFolder then return nil end
    local nearestZone, minDist = nil, math.huge
    for _, zone in ipairs(dungeonFolder:GetChildren()) do
        local zoneRoot = zone:FindFirstChild("Root")
        if zoneRoot and zone:FindFirstChild("ExitTeleporter") then
            local d = (zoneRoot.Position - root.Position).Magnitude
            if d < minDist then minDist = d; nearestZone = zone end
        end
    end
    return nearestZone
end

local function FindShrine()
    for _, e in ipairs(workspace.Enemies:GetChildren()) do
        if e.Name == "Shrine" then
            local h = e:FindFirstChild("Humanoid")
            if h and h.Health > 0 and e:FindFirstChild("HumanoidRootPart") then return e end
        end
    end
    return nil
end

local function isDestroyTarget(obj)
    if not obj:FindFirstChild("Humanoid") then return false end
    if not obj:FindFirstChild("HumanoidRootPart") then return false end
    if obj.Humanoid.Health <= 0 then return false end
    if obj.Name == "Destroy" then return true end
    for _, child in ipairs(obj:GetDescendants()) do
        if child:IsA("TextLabel") and string.find(child.Text, "Destroy") then return true end
    end
    return false
end

local function FindDestroy()
    for _, e in ipairs(workspace.Enemies:GetChildren()) do
        if isDestroyTarget(e) then return e end
    end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name ~= "Enemies" and isDestroyTarget(obj) then return obj end
    end
    return nil
end

local function GetValidDungeonEnemies()
    local root = getRoot()
    local valid = {}
    for _, e in ipairs(workspace.Enemies:GetChildren()) do
        if e:FindFirstChild("Humanoid") and e:FindFirstChild("HumanoidRootPart") then
            if e.Humanoid.Health > 0 and e.Name ~= "Blank Buddy" then
                table.insert(valid, e)
            end
        end
    end
    if root and #valid > 1 then
        local pos = root.Position
        table.sort(valid, function(a, b)
            return (a.HumanoidRootPart.Position - pos).Magnitude
                 < (b.HumanoidRootPart.Position - pos).Magnitude
        end)
    end
    return valid
end

local function GetBestPad()
    local bestPad, maxPlayers = nil, -1
    for i = 1, 3 do
        local pad = workspace.Map["Simulation Hub"].Pads:FindFirstChild("DUNGEON_TELEPORTER" .. i)
        if pad then
            local n = pad:GetAttribute("NumPlayersOnPad") or 0
            if n < 4 and n > maxPlayers then maxPlayers = n; bestPad = pad end
        end
    end
    return bestPad
end

local dungeonFarmConn
local _dungeonExitReachedTime = 0

local function startDungeonFarm()
    if dungeonFarmConn then dungeonFarmConn:Disconnect() end
    _dungeonExitReachedTime = 0

    if game.PlaceId ~= DungeonPlaceId then
        Library:Notify({Title="Wrong Place",Content="Dungeon farm chỉ hoạt động trong Dungeon!",Duration=5})
        return
    end

    getgenv().FarmDungeon = true
    enableFly()

    dungeonFarmConn = RunService.Heartbeat:Connect(function()
        if not getgenv().FarmDungeon then return end
        pcall(function()
            local root = getRoot()
            if not root then return end

            local currentZone = GetCurrentZone()
            if not currentZone then return end
            local exitTP   = currentZone:FindFirstChild("ExitTeleporter")
            if not exitTP then return end
            local exitRoot = exitTP:FindFirstChild("Root")
            if not exitRoot then return end

            -- Exit teleporter visible → fly đến + delay 1s
            if exitRoot:FindFirstChild("BBG") then
                _tp(exitRoot.CFrame)
                if _dungeonExitReachedTime == 0 then _dungeonExitReachedTime = tick() end
                if tick() - _dungeonExitReachedTime < 1 then return end
                _dungeonExitReachedTime = 0
                return
            else
                _dungeonExitReachedTime = 0
            end

            -- PRIORITY 1: DESTROY
            local destroy = FindDestroy()
            if destroy then
                local cf = GetFarmCFrame(destroy)
                if cf then _tp(cf) end
                AttackEnemy(destroy); return
            end

            -- PRIORITY 2: SHRINE
            local shrine = FindShrine()
            if shrine then
                local cf = GetFarmCFrame(shrine)
                if cf then _tp(cf) end
                AttackEnemy(shrine); return
            end

            -- PRIORITY 3: ALL MOBS – không bring mob dù toggle BringMob có bật
            local enemies = GetValidDungeonEnemies()
            if #enemies > 0 then
                local cf = GetFarmCFrame(enemies[1])
                if cf then _tp(cf) end
                for _, e in ipairs(enemies) do
                    if e:FindFirstChild("Humanoid") and e.Humanoid.Health > 0 then
                        AttackEnemy(e)
                    end
                end
            else
                _tp(exitRoot.CFrame)
            end
        end)
    end)
end

local function stopDungeonFarm()
    if dungeonFarmConn then dungeonFarmConn:Disconnect(); dungeonFarmConn = nil end
    _dungeonExitReachedTime = 0
    getgenv().FarmDungeon = false
    disableFly()
end

--// ===================== AUTO FARM LEVEL LOOP =====================
local function autoFarmLevelLoop()
    getgenv().IsFarming = true
    enableFly()

    while getgenv().IsFarming do
        task.wait(0.15)

        pcall(updateSelectedWeapon)

        local Mon, Qdata, Qname, NameMon, PosM, PosQ, altData
        pcall(function()
            Mon, Qdata, Qname, NameMon, PosM, PosQ, altData = QuestNeta()
        end)
        if not Mon then task.wait(1); continue end

        local questVisible, questTitle = getQuestInfo()

        -- ── Không có quest → nhận quest ──────────────────────────────────
        if not questVisible then
            -- Submerged Island: cần travel vào island trước khi nhận quest
            if World3 and player.Data.Level.Value >= 2600 then
                local root = getRoot()
                if root and root.Position.Y > -500 then
                    TeleportToSubmerged(PosM.Position)
                    if not getgenv().IsFarming then continue end
                end
            end
            _tp(PosQ)
            local arrived = waitArrival(PosQ.Position, 15, 14)
            if not arrived or not getgenv().IsFarming then continue end
            task.wait(0.5)
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", Qname, Qdata)
            end)
            task.wait(0.7)

        -- ── Quest sai → hủy ──────────────────────────────────────────────
        elseif not string.find(questTitle, NameMon) then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("AbandonQuest")
            end)
            task.wait(0.8)

        -- ── Quest đúng → farm mob ─────────────────────────────────────────
        else
            -- Tìm mob còn sống gần nhất
            local targetMob  = nil
            local closestDist = math.huge
            local root = getRoot()
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                if v.Name == Mon and v.PrimaryPart then
                    local hum = v:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 and v.Parent then
                        local d = root and (v.PrimaryPart.Position - root.Position).Magnitude or 0
                        if d < closestDist then
                            closestDist = d
                            targetMob   = v
                        end
                    end
                end
            end

            if targetMob then
                -- Ghi nhớ vị trí ban đầu của mob làm anchor cố định cho phiên kill này.
                -- Khi mob chết → vòng ngoài tìm mob mới → lockedPos mới tự động được set.
                local lockedPos    = (targetMob.PrimaryPart and targetMob.PrimaryPart.Position)
                                     or PosM.Position
                local lastMobPos   = Vector3.new(0, -9999, 0)  -- chỉ dùng khi BringMob OFF
                local killDeadline = tick() + 30

                -- Set globals cho bring mob spawn loop
                getgenv().CurrentTargetMob = targetMob
                _lockedBringPos = CFrame.new(lockedPos)

                while getgenv().IsFarming and tick() < killDeadline do
                    -- Mob còn sống?
                    local hum = targetMob:FindFirstChildOfClass("Humanoid")
                    if not targetMob.Parent or not hum or hum.Health <= 0 then break end
                    -- Quest còn không?
                    local qv, _ = getQuestInfo()
                    if not qv then break end

                    local mobRoot = targetMob:FindFirstChild("HumanoidRootPart")
                    if mobRoot then
                        if getgenv().BringMob then
                            -- ── BringMob ON ──────────────────────────────────────────────
                            -- 1. Ghim player trên lockedPos — chỉ _tp khi lệch > 5 stud
                            local anchorCF = CFrame.new(lockedPos + Vector3.new(0, 25, 0))
                            local root = getRoot()
                            if root and (root.Position - anchorCF.Position).Magnitude > 5 then
                                _tp(anchorCF)
                            end
                            -- 2. Bring target mob về lockedPos nếu nó đã bị lệch > 3 stud
                            if (mobRoot.Position - lockedPos).Magnitude > 3 then
                                pcall(function()
                                    mobRoot.CFrame = CFrame.new(lockedPos)
                                    local mh = targetMob:FindFirstChildOfClass("Humanoid")
                                    if mh then mh.WalkSpeed = 0; mh.JumpPower = 0 end
                                end)
                            end
                            -- 3. Spawn loop bring mob phụ tự xử lý — không gọi BringEnemy ở đây
                        else
                            -- ── BringMob OFF: follow mob bình thường ─────────────────────
                            local curPos = mobRoot.Position
                            if (curPos - lastMobPos).Magnitude > 2 then
                                lastMobPos = curPos
                                _tp(mobRoot.CFrame * CFrame.new(0, 25, 0))
                            end
                        end
                    end

                    -- Chỉ trang bị weapon khi đã đến gần mob trong vòng 200 stud
                    do
                        local _root  = getRoot()
                        local _mobRP = targetMob and targetMob:FindFirstChild("HumanoidRootPart")
                        if _root and _mobRP
                            and (_mobRP.Position - _root.Position).Magnitude <= 200
                        then
                            pcall(equipSelectedWeapon)
                        end
                    end
                    task.wait(0)  -- tick nhanh để phản ứng ngay khi mob dịch chuyển
                end

                -- Xóa target sau khi mob chết
                getgenv().CurrentTargetMob = nil
                _lockedBringPos = nil
            else
                -- Không có mob → đến vùng spawn rồi đợi
                _tp(PosM)
                waitArrival(PosM.Position, 35, 10)
                task.wait(1)
            end
        end
    end

    disableFly()
    getgenv().IsFarming = false
end

--// ===================== UI FRAMEWORK =====================
local Window = Library:CreateWindow({
    Title       = "Script Hub",
    SubTitle    = "Made by User",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(580, 460),
    Acrylic     = false,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs         = {}
local Elements     = {}
local ActiveThreads = {}
local StopCallbacks = {}

local TabOrder = {
    "Shop", "SettingFarm", "Farming", "Item", "Stack Farm",
    "Fruit & Dungeon", "LocalPlayer", "Upgraded Race",
    "Sea Event", "Volcano Event", "Travel", "Misc", "Settings"
}

local TabIcons = {
    Shop               = "shopping-cart",
    SettingFarm        = "wrench",
    Farming            = "swords",
    Item               = "package",
    ["Stack Farm"]     = "layers",
    ["Fruit & Dungeon"]= "cherry",
    LocalPlayer        = "user",
    ["Upgraded Race"]  = "zap",
    ["Sea Event"]      = "waves",
    ["Volcano Event"]  = "flame",
    Travel             = "navigation",
    Misc               = "tool",
    Settings           = "settings"
}

local SettingsFile = "ScriptHub_Settings.json"
local Settings = {}

local LoadSettings = function()
    local ok, result = pcall(function()
        local data = readfile(SettingsFile)
        if data and data ~= "" then
            return game:GetService("HttpService"):JSONDecode(data)
        end
        return {}
    end)
    Settings = (ok and type(result) == "table") and result or {}
end

local SaveSettings = function()
    pcall(function()
        writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(Settings))
    end)
end

LoadSettings()

local SpawnTracked = function(fn)
    local thread = task.spawn(fn)
    table.insert(ActiveThreads, thread)
    return thread
end

local StopAllLogic = function()
    -- Stop farm level
    getgenv().IsFarming = false
    disableFly()

    for _, thread in ipairs(ActiveThreads) do
        pcall(task.cancel, thread)
    end
    ActiveThreads = {}

    for _, fn in ipairs(StopCallbacks) do
        pcall(fn)
    end
    StopCallbacks = {}
end

local GetDefault = function(Element)
    if Element.Default ~= nil then return Element.Default end
    if Element.Mode == "Toggle"      then return false
    elseif Element.Mode == "Slider"  then return 0
    elseif Element.Mode == "Dropdown" then return nil   -- ← always nil for dropdowns
    elseif Element.Mode == "TextBox" then return ""
    elseif Element.Mode == "Colorpicker" then return {R=1,G=1,B=1}
    elseif Element.Mode == "Keybind" then return "LeftControl"
    end
    return nil
end

--// ===================== UI CONFIG =====================
-- GetConnectionEnemies được define ở line ~2075 (sau UIConfig).
-- Forward-declare local ở đây để wrapper bên dưới resolve đúng upvalue lúc gọi.
local GetConnectionEnemies  -- sẽ được gán ở phần định nghĩa chính bên dưới
local function GetNearestEnemy(nameOrTable)
    return GetConnectionEnemies(nameOrTable)
end

--// ===================== KATA FARM (forward declarations before UIConfig) =====================
local kataFarmConn
local _CakeQuestPos    = CFrame.new(-1927.92, 37.8, -12842.54)
local _CakeTeleportPos = CFrame.new(-2151.82, 149.32, -12404.91)
local _CakeMirrorPos   = CFrame.new(-2151.82, 149.32, -12404.91)
local _CakePrinceTable = {"Cookie Crafter","Cake Guard","Baking Staff","Head Baker"}
local _CAKE_QUESTS     = {
    {"StartQuest","CakeQuest2",2}, {"StartQuest","CakeQuest2",1},
    {"StartQuest","CakeQuest1",1}, {"StartQuest","CakeQuest1",2},
}

-- State cho mirror delay (Heartbeat-safe: không dùng task.wait blocking)
local _mirrorDelayActive = false
local _mirrorDelayStart  = 0
local MIRROR_DELAY       = 1.2  -- giây chờ sau khi fly đến mirror trước khi loop tiếp

local function startKataFarm()
    if kataFarmConn then kataFarmConn:Disconnect(); kataFarmConn = nil end
    if not World3 then return end
    enableFly()

    _mirrorDelayActive = false
    _mirrorDelayStart  = 0

    kataFarmConn = RunService.Heartbeat:Connect(function()
        if not _G.Auto_Cake_Prince then return end
        pcall(function()
            local root = getRoot()
            if not root then return end
            local questUI = plr.PlayerGui.Main.Quest

            -- ── Map chưa load? → về spawn đợi ─────────────────────────────────
            local cakeMap   = workspace.Map:FindFirstChild("CakeLoaf")
            local bigMirror = cakeMap and cakeMap:FindFirstChild("BigMirror")
            if not bigMirror or not bigMirror:FindFirstChild("Other") then
                _mirrorDelayActive = false
                if (root.Position - _CakeTeleportPos.Position).Magnitude > 60 then
                    _tp(_CakeTeleportPos)
                end
                return
            end

            local otherPart = bigMirror.Other
            local bossEvent = otherPart.Transparency == 0

            -- ── BRANCH A: Boss event active hoặc Cake Prince đã tồn tại ───────
            if bossEvent or workspace.Enemies:FindFirstChild("Cake Prince") then
                local cakePrince = GetNearestEnemy("Cake Prince")

                if cakePrince then
                    -- Cake Prince đang sống → farm nó
                    _mirrorDelayActive = false
                    local cpHRP = cakePrince:FindFirstChild("HumanoidRootPart")
                    if cpHRP then
                        local mPos  = cpHRP.Position
                        local mCF   = cpHRP.CFrame
                        local lRaw  = Vector3.new(mCF.LookVector.X, 0, mCF.LookVector.Z)
                        local lFlat = lRaw.Magnitude > 0.01 and lRaw.Unit or Vector3.new(0,0,1)
                        local yOff  = (_G.ChooseWP == "Blox Fruit") and 15 or 25
                        local dest  = Vector3.new(mPos.X, mPos.Y + yOff, mPos.Z)
                        if (root.Position - dest).Magnitude > 10 then
                            _tp(CFrame.new(dest, dest + lFlat))
                        end
                    end
                    activateBuso()
                    equipSelectedWeapon()
                else
                    -- Boss event nhưng Cake Prince chưa spawn → fly đến mirror chờ
                    if not _mirrorDelayActive then
                        _mirrorDelayActive = true
                        _mirrorDelayStart  = tick()
                        _tp(_CakeMirrorPos)
                    elseif tick() - _mirrorDelayStart < MIRROR_DELAY then
                        -- Đang trong delay → đứng yên, không làm gì
                        return
                    end
                    -- Hết delay → loop tiếp frame sau (Cake Prince sẽ spawn và branch trên bắt)
                end
                return
            end

            -- ── BRANCH B: Không có boss event → farm mob thường ────────────────
            _mirrorDelayActive = false

            -- Ưu tiên mob trong quest (nếu có quest active), fallback sang toàn bộ list
            local cakeMob
            local qv, qt = getQuestInfo()
            if qv then
                for _, name in ipairs(_CakePrinceTable) do
                    if string.find(qt, name, 1, true) then
                        cakeMob = GetNearestEnemy(name)
                        break
                    end
                end
                if not cakeMob then
                    cakeMob = GetNearestEnemy(_CakePrinceTable)
                end
            else
                cakeMob = GetNearestEnemy(_CakePrinceTable)
            end

            if cakeMob then
                -- Nhận quest nếu AcceptQuestC bật và quest chưa active
                if _G.AcceptQuestC and not questUI.Visible then
                    -- Di chuyển đến NPC quest trước
                    if (root.Position - _CakeQuestPos.Position).Magnitude > 50 then
                        _tp(_CakeQuestPos)
                        return  -- chờ frame kế tiếp đến gần hơn
                    end
                    -- Đã đủ gần → gửi request nhận quest
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer(
                            unpack(_CAKE_QUESTS[math.random(1, #_CAKE_QUESTS)])
                        )
                    end)
                    return  -- chờ frame kế tiếp để questUI cập nhật
                end
                -- Set globals cho bring mob spawn loop
                getgenv().CurrentTargetMob = cakeMob
                local cakeMobHRP = cakeMob:FindFirstChild("HumanoidRootPart")
                if cakeMobHRP then
                    _lockedBringPos = CFrame.new(cakeMobHRP.Position)
                end
                -- Farm mob
                local cf = GetFarmCFrame(cakeMob)
                if cf and (root.Position - cf.Position).Magnitude > 10 then
                    _tp(cf)
                end
                activateBuso()
                equipSelectedWeapon()
            else
                -- Không có mob nào → về spawn đợi respawn
                if (root.Position - _CakeTeleportPos.Position).Magnitude > 60 then
                    _tp(_CakeTeleportPos)
                end
            end
        end)
    end)
end

local function stopKataFarm()
    if kataFarmConn then
        kataFarmConn:Disconnect()
        kataFarmConn = nil
    end
    _mirrorDelayActive = false
    _G.Auto_Cake_Prince = false
    disableFly()
end

--// ===================== AURA FARM =====================
-- Farm TẤT CẢ mob trong phạm vi AuraFarmDistance quanh player.
-- Hoạt động giống autoFarmLevelLoop: dùng enableFly + _tp + AttackEnemy.
-- Khi không có mob trong range → fly hover tại chỗ (fly system tự xử lý).
local _auraFarmThread = nil

local function stopAuraFarm()
    _G.AutoAuraFarm = false
    if _auraFarmThread then
        pcall(task.cancel, _auraFarmThread)
        _auraFarmThread = nil
    end
    disableFly()
    getgenv().CurrentTargetMob = nil
    _lockedBringPos = nil
end

local function startAuraFarm()
    if _auraFarmThread then pcall(task.cancel, _auraFarmThread) end
    _G.AutoAuraFarm = true
    enableFly()

    _auraFarmThread = task.spawn(function()
        while _G.AutoAuraFarm do
            task.wait(0.15)
            pcall(function()
                pcall(updateSelectedWeapon)

                local root = getRoot()
                if not root then return end

                local farmDist = _G.AuraFarmDistance
                if not farmDist or farmDist <= 0 then return end

                -- Tìm mob gần nhất còn sống trong phạm vi
                local nearest, nearestDist = nil, math.huge
                for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
                    local hum = enemy:FindFirstChild("Humanoid")
                    local hrp = enemy:FindFirstChild("HumanoidRootPart")
                    if hum and hrp and hum.Health > 0 and enemy.Parent then
                        local d = (hrp.Position - root.Position).Magnitude
                        if d <= farmDist and d < nearestDist then
                            nearestDist = d
                            nearest     = enemy
                        end
                    end
                end

                if nearest then
                    -- Set globals cho bring mob spawn loop
                    local mobHRP = nearest:FindFirstChild("HumanoidRootPart")
                    if mobHRP then
                        getgenv().CurrentTargetMob = nearest
                        _lockedBringPos = CFrame.new(mobHRP.Position)

                        -- Di chuyển đến mob giống farm thường
                        local farmCF = GetFarmCFrame(nearest)
                        if farmCF then
                            _tp(farmCF)
                        end
                    end

                    -- Attack + buso
                    activateBuso()
                    equipSelectedWeapon()
                    AttackEnemy(nearest)
                else
                    -- Không có mob → hover tại chỗ (fly BV zero tự xử lý)
                    _flyTarget = nil
                    getgenv().CurrentTargetMob = nil
                    _lockedBringPos = nil
                end
            end)
        end

        -- Cleanup
        disableFly()
        getgenv().CurrentTargetMob = nil
        _lockedBringPos = nil
    end)
end

local UIConfig = {
    Shop = {
        -- ─── Buy Fighting Styles ──────────────────────────────────────────────
        { Section = "Buy Fighting Styles" },
        {
            Id = "SelectFightingStyleBuy", Mode = "Dropdown",
            Title = "Select Fighting Styles Buy",
            Description = "Select a fighting style to buy.",
            Values = (function()
                local all = {
                    {name="BlackLeg",      w1=true,  w2=true,  w3=true},
                    {name="Electro",       w1=true,  w2=true,  w3=true},
                    {name="FishmanKarate", w1=true,  w2=true,  w3=true},
                    {name="DragonClaw",    w1=false, w2=true,  w3=true},
                    {name="Superhuman",    w1=false, w2=true,  w3=true},
                    {name="DeathStep",     w1=false, w2=true,  w3=true},
                    {name="SharkmanKarate",w1=false, w2=true,  w3=true},
                    {name="ElectricClaw",  w1=false, w2=false, w3=true},
                    {name="DragonTalon",   w1=false, w2=false, w3=true},
                    {name="Godhuman",      w1=false, w2=false, w3=true},
                    {name="SanguineArt",   w1=false, w2=false, w3=true},
                }
                local result = {}
                for _, v in ipairs(all) do
                    if (World1 and v.w1) or (World2 and v.w2) or (World3 and v.w3)
                    or (not World1 and not World2 and not World3 and v.w1) then
                        result[#result+1] = v.name
                    end
                end
                return result
            end)(),
            Default = nil,
            Callback = function(Value)
                _G.SelectedFightingStyle = Value
            end
        },
        {
            Id = "AutoBuyFightingStyle", Mode = "Toggle",
            Title = "Auto Buy Fighting Styles",
            Description = "Auto buy selected fighting style.",
            Default = false,
            Callback = function(Value)
                _G.AutoBuyFightingStyle = Value
                if not Value then
                    _G._BuyFSActive = false
                    _stopCurrentTween()
                end
            end
        },
    },

    SettingFarm = {
        -- ─── Movement ─────────────────────────────────────────────────────────
        { Section = "Movement" },
        {
            Id = "SameY", Mode = "Toggle",
            Title = "Same Y",
            Description = "Lock Y-axis when flying.",
            Default = false,
            Callback = function(Value)
                _sameY = Value
            end
        },
        {
            Id = "UsePortalTp", Mode = "Toggle",
            Title = "Use Portal Tp",
            Description = "Use intermediate island teleport when flying far.",
            Default = false,
            Callback = function(Value)
                getgenv().TelePorto = Value
            end
        },
        {
            Id = "SelectSpeedFly", Mode = "Dropdown",
            Title = "Select Speed Fly",
            Description = "Set fly speed for farming.",
            Values = {"180","250","300","325","350"},
            Default = nil,
            Callback = function(Value)
                if Value and Value ~= "" then
                    getgenv().FlySpeed = tonumber(Value)
                end
            end
        },
        -- ─── Bring Mob ────────────────────────────────────────────────────────
        { Section = "Bring Mob" },
        {
            Id = "SelectBringRange", Mode = "Dropdown",
            Title = "Select Bring Range",
            Description = "Set bring mob range (studs).",
            Values = {"100","200","300","350","400","450","500","550","1000"},
            Default = nil,
            Callback = function(Value)
                if Value and Value ~= "" then
                    getgenv().BringRange = tonumber(Value)
                end
            end
        },
        {
            Id = "BringMob", Mode = "Toggle",
            Title = "Bring Mob",
            Description = "Enable bring mob.",
            Default = false,
            Callback = function(Value)
                getgenv().BringMob = Value
                -- Tắt SpinBring nếu tắt BringMob
                if not Value then
                    _G.SpinBring = false
                    _spinAngle   = 0
                    _sphereTime  = 0
                    if _UI and _UI["SpinBring"] then
                        pcall(function() _UI["SpinBring"]:SetValue(false) end)
                    end
                    -- Dọn BAV tumble + BV fly còn sót trên tất cả mob
                    pcall(function()
                        for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
                            local hrp = enemy:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local bav = hrp:FindFirstChild("_MobTumbleBAV")
                                if bav then bav:Destroy() end
                                local bv = hrp:FindFirstChild("_MobFlyBV")
                                if bv then bv:Destroy() end
                            end
                        end
                    end)
                end
            end
        },
        {
            Id = "SpinBring", Mode = "Toggle",
            Title = "Spin Bring",
            Description = "Enable spin bring.",
            Default = false,
            Callback = function(Value)
                if Value and not getgenv().BringMob then
                    -- SpinBring yêu cầu BringMob phải bật
                    _G.SpinBring = false
                    if _UI and _UI["SpinBring"] then
                        pcall(function() _UI["SpinBring"]:SetValue(false) end)
                    end
                    return
                end
                _G.SpinBring = Value
                if not Value then
                    _spinAngle  = 0
                    _sphereTime = 0  -- reset sphere khi tắt SpinBring để sphere bắt đầu mượt
                else
                    _sphereTime = 0  -- reset sphere khi bật SpinBring (sphere sẽ tạm dừng)
                    -- Dọn BAV tumble khi chuyển sang SpinBring
                    pcall(function()
                        for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
                            local hrp = enemy:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local bav = hrp:FindFirstChild("_MobTumbleBAV")
                                if bav then bav:Destroy() end
                            end
                        end
                    end)
                end
            end
        },
    },

    Farming = {
        -- ─── Farm Configuration ───────────────────────────────────────────────
        { Section = "Farm Configuration" },
        {
            Id = "SelectTool", Mode = "Dropdown",
            Title = "Select Tool",
            Description = "Select farming weapon.",
            Values = {"Melee","Sword","Blox Fruit","Gun"},
            Default = nil,
            Callback = function(Value)
                _G.ChooseWP = (Value and Value ~= "") and Value or nil
            end
        },
        {
            Id = "AttackBuddha", Mode = "Toggle",
            Title = "Attack Buddha",
            Description = "Toggle legacy attack mode.",
            Default = true,
            Callback = function(Value)
                _G.AttackBuddha = Value
            end
        },
        {
            Id = "AcceptQuests", Mode = "Toggle",
            Title = "Accept Quests",
            Description = "Auto accept quests.",
            Default = false,
            Callback = function(Value)
                _G.AcceptQuestC = Value
            end
        },
        {
            Id = "AutoRaceV3", Mode = "Toggle",
            Title = "Auto Turn Race V3",
            Description = "Auto complete Race V3.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoRaceV4", Mode = "Toggle",
            Title = "Auto Turn Race V4",
            Description = "Auto complete Race V4.",
            Default = false, Callback = function(Value) end
        },

        -- ─── Level ────────────────────────────────────────────────────────────
        { Section = "Level" },
        {
            Id = "AutoFarmLevel", Mode = "Toggle",
            Title = "Auto Farm Level",
            Description = "Auto farm EXP.",
            Default = false,
            Callback = function(Value)
                if Value then
                    -- Guard: không spawn thêm nếu đã đang farm
                    if getgenv().IsFarming then return end
                    local t = SpawnTracked(function()
                        autoFarmLevelLoop()
                    end)
                    getgenv().FarmThread = t
                else
                    -- Tắt flag → loop thoát tự nhiên; cancel thread ngay để không chờ tick
                    getgenv().IsFarming = false
                    disableFly()
                    if getgenv().FarmThread then
                        pcall(task.cancel, getgenv().FarmThread)
                        getgenv().FarmThread = nil
                    end
                end
            end
        },

        -- ─── Bone ─────────────────────────────────────────────────────────────
        { Section = "Bone" },
        {
            Id = "TotalBonesLabel", Mode = "Label",
            Title = "Total Bones", Content = "Total Bones: 0"
        },
        {
            Id = "AutoFarmBone", Mode = "Toggle",
            Title = "Auto Farm Bone",
            Description = "Auto farm bones.",
            Default = false,
            Callback = function(Value)
                _G.AutoFarm_Bone = Value
                if Value then
                    enableFly()
                elseif not getgenv().IsFarming and not _G.Auto_Cake_Prince then
                    disableFly()
                end
            end
        },

        -- ─── Aura Farm ────────────────────────────────────────────────────────
        { Section = "Aura Farm" },
        {
            Id = "AuraFarmDistance", Mode = "Slider",
            Title = "Farm Distance",
            Description = "Set farm detection range (studs).",
            Min = 500, Max = 1000, Rounding = 1, Default = nil,
            Callback = function(Value)
                _G.AuraFarmDistance = Value
            end
        },
        {
            Id = "AutoAuraFarm", Mode = "Toggle",
            Title = "Auto Aura Farm",
            Description = "Enable all-mob farming.",
            Default = false,
            Callback = function(Value)
                _G.AutoAuraFarm = Value
                if Value then
                    startAuraFarm()
                else
                    stopAuraFarm()
                end
            end
        },

        -- ─── Cake Prince ──────────────────────────────────────────────────────
        { Section = "Cake Prince" },
        {
            Id = "CakePrinceStatusLabel", Mode = "Label",
            Title = "Cake Prince Status", Content = "Cake Prince Status: Idle"
        },
        {
            Id = "AutoCakePrince", Mode = "Toggle",
            Title = "Auto Cake Prince",
            Description = "Auto farm Cake Prince.",
            Default = false,
            Callback = function(Value)
                _G.Auto_Cake_Prince = Value
                if Value then
                    startKataFarm()
                else
                    stopKataFarm()
                end
            end
        },
        {
            Id = "IgnoreCakePrince", Mode = "Toggle",
            Title = "Ignore Cake Prince",
            Description = "Skip Cake Prince.",
            Default = false, Callback = function(Value) end
        },

        -- ─── Tyrant of the Skies ─────────────────────────────────────────────
        { Section = "Tyrant of the Skies" },
        {
            Id = "TyrantStatusLabel", Mode = "Label",
            Title = "Tyrant Status", Content = "Tyrant Status: Idle"
        },
        {
            Id = "AcceptQuestTyrant", Mode = "Toggle",
            Title = "Accept Quests",
            Description = "Auto nhận quest khi farm Tyrant.",
            Default = false,
            Callback = function(Value)
                _G.AcceptQuest = Value
            end
        },
        {
            Id = "AutoTyrant", Mode = "Toggle",
            Title = "Auto Tyrant",
            Description = "Auto farm Tyrant of the Skies (boss + vasos + mobs + quest).",
            Default = false,
            Callback = function(Value)
                _G.AutoTyrant = Value
                _G.StartFarm  = Value
                if Value then
                    enableFly()
                    if _UI and _UI["TyrantStatusLabel"] then
                        pcall(function() _UI["TyrantStatusLabel"]:SetText("Tyrant Status: Running") end)
                    end
                else
                    if not getgenv().IsFarming and not _G.Auto_Cake_Prince then
                        disableFly()
                    end
                    if _UI and _UI["TyrantStatusLabel"] then
                        pcall(function() _UI["TyrantStatusLabel"]:SetText("Tyrant Status: Idle") end)
                    end
                end
            end
        },

        -- ─── Mastery ──────────────────────────────────────────────────────────
        { Section = "Mastery" },
        {
            Id = "SelectFarmMasteryMode", Mode = "Dropdown",
            Title = "Select Farm Mastery Mode",
            Description = "Select mastery mode.",
            Values = {}, Default = nil
        },
        {
            Id = "SelectMasteryTool", Mode = "Dropdown",
            Title = "Select Mastery Tool",
            Description = "Select mastery weapon.",
            Values = {}, Default = nil
        },
        {
            Id = "LowHealth", Mode = "Slider",
            Title = "Low Health",
            Description = "Set low HP stop threshold.",
            Min = 0, Max = 100, Rounding = 1, Default = 20,
            Callback = function(Value) end
        },
        {
            Id = "AutoFarmMastery", Mode = "Toggle",
            Title = "Auto Farm Mastery",
            Description = "Auto farm mastery.",
            Default = false, Callback = function(Value) end
        },

        -- ─── Chest ────────────────────────────────────────────────────────────
        { Section = "Chest" },
        {
            Id = "AutoChestTween", Mode = "Toggle",
            Title = "Auto Chest <Tween>",
            Description = "Auto farm chests (tween).",
            Default = false,
            Callback = function(Value)
                if Value and _G.AutoChestBypass then
                    -- Conflict: tắt cả 2, hiện thông báo
                    _G.AutoChestTween   = false
                    _G.AutoChestBypass  = false
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title   = "⚠️ Farm Chest",
                        Text    = "Tắt 1 toggle Farm Chest (chỉ được bật 1 toggle).",
                        Duration = 5,
                    })
                    return
                end
                _G.AutoChestTween = Value
                if not Value then
                    _G._ChestTweenActive = false
                    _stopCurrentTween()
                end
            end
        },
        {
            Id = "AutoChestBypass", Mode = "Toggle",
            Title = "Auto Chest <Bypass>",
            Description = "Auto farm chests (teleport).",
            Default = false,
            Callback = function(Value)
                if Value and _G.AutoChestTween then
                    -- Conflict: tắt cả 2, hiện thông báo
                    _G.AutoChestTween   = false
                    _G.AutoChestBypass  = false
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title   = "⚠️ Farm Chest",
                        Text    = "Tắt 1 toggle Farm Chest (chỉ được bật 1 toggle).",
                        Duration = 5,
                    })
                    return
                end
                _G.AutoChestBypass = Value
                if not Value then _G._ChestBypassActive = false end
            end
        },
    },

    Item = {},
    ["Stack Farm"] = {},

    ["Fruit & Dungeon"] = {
        -- ─── Fruit ────────────────────────────────────────────────────────────
        { Section = "Fruit" },
        {
            Id = "AutoRandomFruits", Mode = "Toggle",
            Title = "Auto Random Fruits",
            Description = "Auto spin fruits.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "TweenToFruits", Mode = "Toggle",
            Title = "Tween To Fruits",
            Description = "Auto collect map fruits.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoStoreFruit", Mode = "Toggle",
            Title = "Auto Store Fruit",
            Description = "Auto store fruits.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoBringFruit", Mode = "Toggle",
            Title = "Auto Bring Fruit",
            Description = "Auto bring fruits.",
            Default = false, Callback = function(Value) end
        },

        -- ─── Raid ─────────────────────────────────────────────────────────────
        { Section = "Raid" },
        {
            Id = "SelectChips", Mode = "Dropdown",
            Title = "Select Chips",
            Description = "Select raid chip.",
            Values = {}, Default = nil
        },
        {
            Id = "AutoBuyChip", Mode = "Toggle",
            Title = "Auto Buy Chip",
            Description = "Auto buy raid chip.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoStartRaid", Mode = "Toggle",
            Title = "Auto Start Raid",
            Description = "Auto start raid.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoGetMinFruitInInventory", Mode = "Toggle",
            Title = "Auto Get Min Fruit In Inventory",
            Description = "Set minimum fruit count.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoAwaken", Mode = "Toggle",
            Title = "Auto Awaken",
            Description = "Auto awaken fruit.",
            Default = false, Callback = function(Value) end
        },
        {
            Id = "AutoRaidFruit", Mode = "Toggle",
            Title = "Auto Raid Fruit",
            Description = "Auto farm raid.",
            Default = false, Callback = function(Value) end
        },

        -- ─── Dungeon ──────────────────────────────────────────────────────────
        { Section = "Dungeon" },
        {
            Id = "SelectToolAttackDungeon", Mode = "Dropdown",
            Title = "Select Tool Attack Dungeon",
            Description = "Select dungeon weapon.",
            Values = {"Melee","Sword","Gun","Blox Fruit"}, Default = nil,
            Callback = function(Value)
                _G.DungeonWeaponChoice = Value
            end
        },
        {
            Id = "AutoFarmDungeon", Mode = "Toggle",
            Title = "Auto Farm Dungeon",
            Description = "Auto farm dungeon.",
            Default = false,
            Callback = function(Value)
                if Value then
                    startDungeonFarm()
                else
                    stopDungeonFarm()
                end
            end
        },

        -- ─── Muti Farm Dungeon ────────────────────────────────────────────────
        { Section = "Muti Farm Dungeon" },
        {
            Id = "SelectPlayerMutiFarm", Mode = "Dropdown",
            Title = "Select Player (Multi Farm)",
            Description = "Select player to follow.",
            Values = (function()
                local names = {}
                for _, p in ipairs(game.Players:GetPlayers()) do
                    if p ~= plr then table.insert(names, p.Name) end
                end
                return names
            end)(),
            Default = nil,
            Callback = function(Value)
                _G.MutiFarmTarget = Value
            end
        },
        {
            Id = "ResetPlayerList", Mode = "Button",
            Title = "Reset Player List",
            Description = "Refresh player list.",
            Callback = function()
                local names = {}
                for _, p in ipairs(game.Players:GetPlayers()) do
                    if p ~= plr then table.insert(names, p.Name) end
                end
                if Elements["Fruit & Dungeon"] and Elements["Fruit & Dungeon"]["SelectPlayerMutiFarm"] then
                    Elements["Fruit & Dungeon"]["SelectPlayerMutiFarm"]:SetValues(names)
                end
                Library:Notify({Title="Player List",Content="Refreshed "..#names.." player(s).",Duration=2})
            end
        },
        {
            Id = "SelectMaxPlayer", Mode = "Dropdown",
            Title = "Select Max Players",
            Description = "Set minimum pad player count.",
            Values = {"1","2","3","4"}, Default = "1",
            Callback = function(Value)
                _G.SelectedMaxPlayers = tonumber(Value) or 1
            end
        },
        {
            Id = "SelectBestPadBtn", Mode = "Button",
            Title = "Fly to Best Pad",
            Description = "Fly to best pad.",
            Callback = function()
                if game.PlaceId ~= DungeonPlaceId then
                    Library:Notify({Title="Wrong PlaceId",Content="Chỉ có thể join pad trong Dungeon!",Duration=3})
                    return
                end
                local bestPad = GetBestPad()
                if not bestPad then
                    Library:Notify({Title="No Pad Found",Content="Không tìm thấy pad phù hợp!",Duration=3})
                    return
                end
                local n = bestPad:GetAttribute("NumPlayersOnPad") or 0
                if n < (_G.SelectedMaxPlayers or 1) then
                    Library:Notify({Title="Not Enough Players",
                        Content="Pad chỉ có "..n.." players, cần "..((_G.SelectedMaxPlayers or 1)),Duration=3})
                    return
                end
                local char = plr.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local targetCF = bestPad.Pad.CFrame * CFrame.new(0, 5, 0)
                local dist     = (hrp.Position - targetCF.Position).Magnitude
                local speed    = getgenv().FlySpeed or 200
                local tw = TweenService:Create(hrp,
                    TweenInfo.new(dist / speed, Enum.EasingStyle.Linear),
                    {CFrame = targetCF})
                tw:Play()
                Library:Notify({Title="Success",Content="Flying to pad with "..n.." players!",Duration=2})
            end
        },
        {
            Id = "MutiJoinDungeon", Mode = "Toggle",
            Title = "Multi Join Dungeon",
            Description = "Follow player into dungeon.",
            Default = false,
            Callback = function(Value)
                _G.MutiJoinDungeon = Value
                if Value and _G.AutoJoinDungeon then
                    Library:Notify({Title="Conflict",
                        Content="AutoJoinDungeon đang bật! Hãy tắt 1 cái để tránh lỗi.",Duration=5})
                end
            end
        },
        {
            Id = "AutoJoinDungeon", Mode = "Toggle",
            Title = "Auto Join Dungeon",
            Description = "Auto join best pad.",
            Default = false,
            Callback = function(Value)
                _G.AutoJoinDungeon = Value
                if Value and _G.MutiJoinDungeon then
                    Library:Notify({Title="Conflict",
                        Content="MultiJoinDungeon đang bật! Hãy tắt 1 cái để tránh lỗi.",Duration=5})
                end
            end
        },
    },

    LocalPlayer = {
        -- ─── Stats ────────────────────────────────────────────────────────────
        { Section = "Stats" },
        {
            Id = "SelectStatsType", Mode = "Dropdown",
            Title = "Select Stats Update",
            Description = "Select stat to upgrade.",
            Values = {"Melee", "Sword", "Gun", "Demon Fruit"}, Default = nil,
            Callback = function(Value)
                _G.SelectedStatsType = Value
            end
        },
        {
            Id = "AutoUpStats", Mode = "Toggle",
            Title = "Auto Up Stats",
            Description = "Auto upgrade selected stat.",
            Default = false,
            Callback = function(Value)
                _G.AutoUpStats = Value
            end
        },

        -- ─── Select Skill ──────────────────────────────────────────────────────
        { Section = "Select Skill" },
        {
            Id = "SkillMeleeKey", Mode = "Dropdown",
            Title = "Melee",
            Description = "Chon skill Melee muon spam. Bo trong = bo qua weapon nay.",
            Values = {"Z", "X", "C"}, Default = {}, Multi = true,
            Callback = function(Value)
                _G.SkillMeleeKeys = (type(Value) == "table" and next(Value)) and Value or {}
            end
        },
        {
            Id = "SkillSwordKey", Mode = "Dropdown",
            Title = "Sword",
            Description = "Chon skill Sword muon spam. Bo trong = bo qua weapon nay.",
            Values = {"Z", "X"}, Default = {}, Multi = true,
            Callback = function(Value)
                _G.SkillSwordKeys = (type(Value) == "table" and next(Value)) and Value or {}
            end
        },
        {
            Id = "SkillGunKey", Mode = "Dropdown",
            Title = "Gun",
            Description = "Chon skill Gun muon spam. Bo trong = bo qua weapon nay.",
            Values = {"Z", "X"}, Default = {}, Multi = true,
            Callback = function(Value)
                _G.SkillGunKeys = (type(Value) == "table" and next(Value)) and Value or {}
            end
        },
        {
            Id = "SkillFruitKey", Mode = "Dropdown",
            Title = "Fruit",
            Description = "Chon skill Fruit muon spam. Bo trong = bo qua weapon nay.",
            Values = {"Z", "X", "C", "V", "F"}, Default = {}, Multi = true,
            Callback = function(Value)
                _G.SkillFruitKeys = (type(Value) == "table" and next(Value)) and Value or {}
            end
        },

        -- ─── Select Skill Hold ─────────────────────────────────────────────────
        { Section = "Select Skill Hold" },

        { Id = "LabelHoldMelee", Mode = "Label", Title = "Melee", Content = "" },
        {
            Id = "HoldMeleeZ", Mode = "Slider",
            Title = "Z", Description = "Hold time for melee Z.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldMeleeZ = Value end
        },
        {
            Id = "HoldMeleeX", Mode = "Slider",
            Title = "X", Description = "Hold time for melee X.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldMeleeX = Value end
        },
        {
            Id = "HoldMeleeC", Mode = "Slider",
            Title = "C", Description = "Hold time for melee C.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldMeleeC = Value end
        },

        { Id = "LabelHoldSword", Mode = "Label", Title = "Sword", Content = "" },
        {
            Id = "HoldSwordZ", Mode = "Slider",
            Title = "Z", Description = "Hold time for sword Z.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldSwordZ = Value end
        },
        {
            Id = "HoldSwordX", Mode = "Slider",
            Title = "X", Description = "Hold time for sword X.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldSwordX = Value end
        },

        { Id = "LabelHoldGun", Mode = "Label", Title = "Gun", Content = "" },
        {
            Id = "HoldGunZ", Mode = "Slider",
            Title = "Z", Description = "Hold time for gun Z.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldGunZ = Value end
        },
        {
            Id = "HoldGunX", Mode = "Slider",
            Title = "X", Description = "Hold time for gun X.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldGunX = Value end
        },

        { Id = "LabelHoldFruit", Mode = "Label", Title = "Fruit", Content = "" },
        {
            Id = "HoldFruitZ", Mode = "Slider",
            Title = "Z", Description = "Hold time for fruit Z.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldFruitZ = Value end
        },
        {
            Id = "HoldFruitX", Mode = "Slider",
            Title = "X", Description = "Hold time for fruit X.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldFruitX = Value end
        },
        {
            Id = "HoldFruitC", Mode = "Slider",
            Title = "C", Description = "Hold time for fruit C.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldFruitC = Value end
        },
        {
            Id = "HoldFruitV", Mode = "Slider",
            Title = "V", Description = "Hold time for fruit V.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldFruitV = Value end
        },
        {
            Id = "HoldFruitF", Mode = "Slider",
            Title = "F", Description = "Hold time for fruit F.",
            Min = 0, Max = 10, Default = 0, Increment = 0.1,
            Callback = function(Value) _G.HoldFruitF = Value end
        },
    },
    ["Upgraded Race"]= {},
    ["Sea Event"]    = {},
    ["Volcano Event"]= {},

    Travel = {
        -- ─── Submarine Travel ──────────────────────────────────────────────
        { Section = "Submarine Travel" },
        {
            Id = "SubmarineIslandSelect", Mode = "Dropdown",
            Title = "Chọn Đảo",
            Description = "Select destination island.",
            Values = {
                "Haunted Castle",
                "Turtle Mountain",
                "Turtle Entrance",
                "Tiki Outpost",
                "Turtle Mansion",
                "Chocolate Land",
                "Sea Castle",
                "Port",
                "Peanut Land",
                "Great Tree",
                "Hydra Arena",
                "Ice Cream Land",
                "Cake Land",
                "Submerged Island (Worker)",
            },
            Default = "Haunted Castle",
            Callback = function(Value)
                _G.SelectedSubmarineIsland = Value
            end
        },
        {
            Id = "TravelToIslandBtn", Mode = "Button",
            Title = "Travel to Island",
            Description = "Travel to selected island.",
            Callback = function()
                local island = _G.SelectedSubmarineIsland or "Haunted Castle"

                -- ── Vị trí mốc ──────────────────────────────────────────────────
                local POS_SUBMARINE_NPC = Vector3.new(-16268, 25, 1376)   -- NPC tàu ngầm (trên mặt nước)
                local POS_SUBMARINE_HUB = Vector3.new(11429, -2155, 9730) -- Hub dưới đảo ngầm
                local NEAR_THRESHOLD    = 2000  -- stud để coi là "đã ở gần"

                -- ── Remote map ──────────────────────────────────────────────────
                local Net = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
                local IslandRemotes = {
                    ["Haunted Castle"]            = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Haunted Castle"} },
                    ["Turtle Mountain"]           = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Turtle Mountain"} },
                    ["Turtle Entrance"]           = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Turtle Entrance"} },
                    ["Tiki Outpost"]              = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Tiki Outpost"} },
                    ["Turtle Mansion"]            = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Turtle Mansion"} },
                    ["Chocolate Land"]            = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Chocolate Land"} },
                    ["Sea Castle"]                = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Sea Castle"} },
                    ["Port"]                      = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Port"} },
                    ["Peanut Land"]               = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Peanut Land"} },
                    ["Great Tree"]                = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Great Tree"} },
                    ["Hydra Arena"]               = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Hydra Arena"} },
                    ["Ice Cream Land"]            = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Ice Cream Land"} },
                    ["Cake Land"]                 = { remote = "RF/SubmarineTransportation", args = {"InitiateTeleport", "Cake Land"} },
                }
                local RF_WORKER     = Net:FindFirstChild("RF/SubmarineWorkerSpeak")
                local RF_SUBMARINE  = Net:FindFirstChild("RF/SubmarineTransportation")

                -- ── Helper: invoke với pcall ─────────────────────────────────────
                local function invokeRemote(rf, a1, a2, a3)
                    if rf and rf:IsA("RemoteFunction") then
                        pcall(function() rf:InvokeServer(a1, a2, a3) end)
                    end
                end

                -- ── Helper: invoke với args table ────────────────────────────────
                local function invokeRemoteArgs(rf, argsTable)
                    if rf and rf:IsA("RemoteFunction") then
                        local a1, a2, a3 = argsTable[1], argsTable[2], argsTable[3]
                        pcall(function() rf:InvokeServer(a1, a2, a3) end)
                    end
                end

                -- ── Helper: tween đến pos rồi đợi đến nơi (timeout 30s) ─────────
                local function tweenAndWait(targetPos, radiusStud, timeoutSec)
                    _tp(CFrame.new(targetPos))
                    local deadline = tick() + (timeoutSec or 30)
                    repeat
                        task.wait(0.3)
                        local root = getRoot()
                        if root and (root.Position - targetPos).Magnitude <= radiusStud then
                            return true
                        end
                    until tick() > deadline
                    return false
                end

                -- ── Main logic (chạy async để không block UI) ───────────────────
                task.spawn(function()
                    local root = getRoot()
                    if not root then
                        Library:Notify({Title="Travel",Content="Không tìm thấy character!",Duration=3})
                        return
                    end

                    local playerPos = root.Position
                    local distToHub = (playerPos - POS_SUBMARINE_HUB).Magnitude

                    -- ── Trường hợp: Đã ở gần Hub dưới ngầm (Pos 2) ────────────────
                    if distToHub <= NEAR_THRESHOLD then
                        if island == "Submerged Island (Worker)" then
                            Library:Notify({Title="Travel",Content="Bạn đã ở Submerged Island rồi!",Duration=4})
                            return
                        end
                        -- Chỉ cần tween tới Hub và kích hoạt remote đảo đích
                        Library:Notify({Title="Travel",Content="Đang tween tới Hub...",Duration=2})
                        tweenAndWait(POS_SUBMARINE_HUB, 50, 20)
                        task.wait(0.5)
                        local logic = IslandRemotes[island]
                        if logic then
                            invokeRemoteArgs(RF_SUBMARINE, logic.args)
                            Library:Notify({Title="Travel",Content="Đã gửi lệnh đến: "..island,Duration=3})
                        end
                        return
                    end

                    -- ── Trường hợp: Chọn Submerged Island (chỉ cần NPC tàu ngầm) ──
                    if island == "Submerged Island (Worker)" then
                        Library:Notify({Title="Travel",Content="Đang tween tới NPC tàu ngầm...",Duration=2})
                        local arrived = tweenAndWait(POS_SUBMARINE_NPC, 35, 30)
                        if not arrived then
                            Library:Notify({Title="Travel",Content="Timeout! Không đến được NPC.",Duration=4})
                            return
                        end
                        _stopCurrentTween()
                        task.wait(0.5)
                        invokeRemote(RF_WORKER, "TravelToSubmergedIsland")
                        Library:Notify({Title="Travel",Content="Đã kích hoạt TravelToSubmergedIsland!",Duration=4})
                        return
                    end

                    -- ── Trường hợp chính: tween NPC → portal → Hub → đảo đích ──────
                    -- Bước 1: Nếu player đang trên mặt nước (Y > 0) → tween tới NPC tàu ngầm
                    if playerPos.Y > 0 then
                        Library:Notify({Title="Travel",Content="Bước 1: Tween tới NPC tàu ngầm...",Duration=3})
                        local arrived = tweenAndWait(POS_SUBMARINE_NPC, 35, 30)
                        if not arrived then
                            Library:Notify({Title="Travel",Content="Timeout! Không đến được NPC.",Duration=4})
                            return
                        end
                        _stopCurrentTween()
                        task.wait(0.5)

                        -- Bước 2: Kích hoạt TravelToSubmergedIsland
                        invokeRemote(RF_WORKER, "TravelToSubmergedIsland")
                        Library:Notify({Title="Travel",Content="Bước 2: Đang chờ server teleport...",Duration=2})
                        task.wait(1)  -- chờ server tele player xuống đảo ngầm
                    end

                    -- Bước 3: Tween tới Hub dưới ngầm
                    Library:Notify({Title="Travel",Content="Bước 3: Tween tới Hub...",Duration=3})
                    local arrivedHub = tweenAndWait(POS_SUBMARINE_HUB, 80, 30)
                    if not arrivedHub then
                        Library:Notify({Title="Travel",Content="Timeout! Không đến được Hub.",Duration=4})
                        return
                    end
                    task.wait(0.5)

                    -- Bước 4: Kích hoạt remote đến đảo đích
                    local logic = IslandRemotes[island]
                    if logic then
                        invokeRemoteArgs(RF_SUBMARINE, logic.args)
                        Library:Notify({Title="Travel",Content="✅ Đã gửi lệnh đến: "..island,Duration=4})
                    else
                        Library:Notify({Title="Travel",Content="Không tìm thấy remote cho đảo: "..island,Duration=4})
                    end
                end)
            end
        },
    },

    Misc             = {},

    Settings = {
        { Section = "Settings Manager" },
        {
            Id = "SettingsLabel", Mode = "Label",
            Title = "Manage Settings",
            Content = "Reset all settings back to their default values. This will also stop all active logic and running tasks."
        },
        {
            Id = "ResetSettings", Mode = "Button",
            Title = "Reset to Default",
            Description = "Reset all settings to default.",
            Callback = function() end
        }
    }
}

--// ===================== RESET SETTINGS =====================
local ResetSettings = function()
    StopAllLogic()
    Settings = {}
    pcall(function() delfile(SettingsFile) end)

    for _, Name in ipairs(TabOrder) do
        local ElementsList = UIConfig[Name]
        if type(ElementsList) == "table" then
            for _, Element in ipairs(ElementsList) do
                if type(Element) == "table" and Element.Id and Element.Mode then
                    if Element.Mode ~= "Label" and Element.Mode ~= "Button" and Element.Section == nil then
                        local Default = GetDefault(Element)
                        pcall(function()
                            if Element.Mode == "Toggle" and Library.Options[Element.Id] then
                                Library.Options[Element.Id]:SetValue(Default)
                            elseif Elements[Name] and Elements[Name][Element.Id] then
                                local el = Elements[Name][Element.Id]
                                if Element.Mode == "Slider" then
                                    el:SetValue(Default)
                                elseif Element.Mode == "Dropdown" then
                                    el:SetValue(Default)
                                elseif Element.Mode == "Colorpicker" then
                                    local dc = GetDefault(Element)
                                    el:SetValueRGB(Color3.fromRGB(dc.R*255, dc.G*255, dc.B*255))
                                elseif Element.Mode == "Keybind" then
                                    el:SetValue(Default, Element.Mode2 or "Toggle")
                                end
                            elseif Element.Mode == "TextBox" and Library.Options[Element.Id] then
                                Library.Options[Element.Id]:SetValue(Default)
                            end
                        end)
                    end
                end
            end
        end
    end

    Library:Notify({
        Title      = "Settings Reset",
        Content    = "All settings have been restored to their default values.",
        SubContent = "All active logic and tasks have been stopped.",
        Duration   = 4
    })
end

UIConfig.Settings[3].Callback = function() ResetSettings() end

--// ===================== BUILD ELEMENT =====================
-- Flag giữ lại cho Reset Settings (StopAllLogic vẫn dùng ở đó).
-- Không còn dùng trong OnChanged nữa — StopAllLogic đã được bỏ khỏi generic OnChanged.
local isInitializing = true

local BuildElement = function(Tab, Name, Element)
    if type(Element) ~= "table" then return end

    if Element.Section then
        Tab:AddSection(Element.Section)
        return
    end

    local Mode = Element.Mode
    local Id   = Element.Id
    if not Id or not Mode then return end

    if Mode == "Label" then
        Elements[Name][Id] = Tab:CreateParagraph(Id, {
            Title   = Element.Title,
            Content = Element.Content
        })
        return
    end

    local Key = Name .. "_" .. Id

    if Settings[Key] == nil and Mode ~= "Button" then
        Settings[Key] = GetDefault(Element)
        SaveSettings()
    end

    if Mode == "Toggle" then
        local Default = Settings[Key]
        Elements[Name][Id] = Tab:CreateToggle(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Default     = Default
        })
        -- Không fire callback ở đây — sẽ fire SAU khi build xong để tránh bị StopAllLogic() kill
        Elements[Name][Id]:OnChanged(function(Value)
            if Value == nil then return end
            Settings[Key] = Value
            SaveSettings()
            if Element.Callback then
                if Value then
                    SpawnTracked(function() Element.Callback(Value) end)
                else
                    -- Chỉ gọi Callback(false) của chính toggle đó.
                    -- KHÔNG gọi StopAllLogic() ở đây — sẽ kill farm khi tắt bất kỳ toggle nào.
                    -- Mỗi feature tự dọn dẹp qua Callback riêng (VD: AutoFarmLevel set IsFarming=false).
                    Element.Callback(Value)
                end
            end
        end)

    elseif Mode == "Slider" then
        local Default = Settings[Key]
        Elements[Name][Id] = Tab:CreateSlider(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Default     = Default,
            Min         = Element.Min or 0,
            Max         = Element.Max or 100,
            Rounding    = Element.Rounding or 1
        })
        if Element.Callback then
            SpawnTracked(function() Element.Callback(Default) end)
        end
        Elements[Name][Id]:OnChanged(function(Value)
            if Value == nil then return end
            Settings[Key] = Value
            SaveSettings()
            if Element.Callback then Element.Callback(Value) end
        end)

    elseif Mode == "Dropdown" then
        local isMulti = Element.Multi or false
        local Default = Settings[Key]
        -- Khi Multi=true, Fluent yêu cầu Default phải là table
        -- Nếu load từ file ra string hoặc nil → ép về {}
        if isMulti and type(Default) ~= "table" then
            Default = Element.Default or {}
        end
        -- Khi không phải Multi, nil là hợp lệ
        if not isMulti and Default == nil then
            Default = Element.Default or nil
        end
        Elements[Name][Id] = Tab:CreateDropdown(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Values      = Element.Values or {},
            Default     = Default,
            Multi       = isMulti
        })
        if Element.Callback then
            SpawnTracked(function() Element.Callback(Default) end)
        end
        Elements[Name][Id]:OnChanged(function(Value)
            if Value == nil then return end
            Settings[Key] = Value
            SaveSettings()
            if Element.Callback then Element.Callback(Value) end
        end)

    elseif Mode == "Button" then
        Elements[Name][Id] = Tab:CreateButton({
            Title       = Element.Title,
            Description = Element.Description,
            Callback    = Element.Callback or function() end
        })

    elseif Mode == "Keybind" then
        local Default = Settings[Key]
        Elements[Name][Id] = Tab:CreateKeybind(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Mode        = Element.Mode2 or "Toggle",
            Default     = Default
        })
        Elements[Name][Id]:OnChanged(function()
            local Value = Elements[Name][Id].Value
            if Value == nil then return end
            Settings[Key] = Value
            SaveSettings()
        end)

    elseif Mode == "Colorpicker" then
        local C = Settings[Key]
        if type(C) ~= "table" or C.R == nil then
            C = GetDefault(Element)
            Settings[Key] = C
            SaveSettings()
        end
        local DefaultColor = Color3.fromRGB(C.R*255, C.G*255, C.B*255)
        Elements[Name][Id] = Tab:CreateColorpicker(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Default     = DefaultColor
        })
        if Element.Callback then
            SpawnTracked(function() Element.Callback(DefaultColor) end)
        end
        Elements[Name][Id]:OnChanged(function()
            local Color = Elements[Name][Id].Value
            if Color == nil then return end
            Settings[Key] = {
                R = math.floor(Color.R*255+0.5)/255,
                G = math.floor(Color.G*255+0.5)/255,
                B = math.floor(Color.B*255+0.5)/255
            }
            SaveSettings()
            if Element.Callback then Element.Callback(Color) end
        end)

    elseif Mode == "TextBox" then
        local Default = Settings[Key]
        Elements[Name][Id] = Tab:CreateInput(Id, {
            Title       = Element.Title,
            Description = Element.Description,
            Default     = Default,
            Placeholder = Element.Placeholder or "",
            Numeric     = Element.Numeric or false,
            Finished    = Element.Finished or false,
            Callback    = function(Value)
                Settings[Key] = Value
                SaveSettings()
                if Element.Callback then Element.Callback(Value) end
            end
        })
    end
end

--// ===================== BUILD TABS =====================
for _, Name in ipairs(TabOrder) do
    Elements[Name] = {}
    Tabs[Name] = Window:CreateTab({
        Title = Name,
        Icon  = TabIcons[Name] or ""
    })
end

for _, Name in ipairs(TabOrder) do
    local ElementsList = UIConfig[Name]
    if Tabs[Name] and type(ElementsList) == "table" then
        for _, Element in ipairs(ElementsList) do
            BuildElement(Tabs[Name], Name, Element)
        end
    end
end

InterfaceManager:SetLibrary(Library)
InterfaceManager:SetFolder("ScriptHub")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)

--// ===================== POST-BUILD: FIRE LOADED TRUE TOGGLES =====================
-- Tất cả element đã được tạo xong → giờ mới an toàn để fire callback.
-- isInitializing = false trước để OnChanged hoạt động bình thường từ đây trở đi.
isInitializing = false

for _, Name in ipairs(TabOrder) do
    local ElementsList = UIConfig[Name]
    if type(ElementsList) == "table" then
        for _, Element in ipairs(ElementsList) do
            if type(Element) == "table" and Element.Mode == "Toggle" and Element.Callback then
                local Key = Name .. "_" .. Element.Id
                if Settings[Key] == true then
                    local cb = Element.Callback
                    SpawnTracked(function() cb(true) end)
                end
            end
        end
    end
end

Window:SelectTab(1)

--// ===================== AUTO HIDE UI =====================
if Config.AutoHideUI then
    task.delay(0.2, function()
        Window:Minimize()
    end)
end

--// ===================== HELPER: GetConnectionEnemies =====================
-- Trả về mob sống gần nhất trong workspace.Enemies khớp với name hoặc table name.
-- Gán vào upvalue đã forward-declare ở trên để GetNearestEnemy wrapper hoạt động đúng.
GetConnectionEnemies = function(nameOrTable)
    local root = getRoot()
    if not root then return nil end
    local closest, closestDist = nil, math.huge
    for _, v in pairs(workspace.Enemies:GetChildren()) do
        local match = false
        if type(nameOrTable) == "string" then
            match = v.Name == nameOrTable
        elseif type(nameOrTable) == "table" then
            for _, n in ipairs(nameOrTable) do
                if v.Name == n then match = true; break end
            end
        end
        -- Fallback: dùng HumanoidRootPart nếu PrimaryPart không được set
        local anchor = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
        if match and anchor then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and v.Parent then
                local d = (anchor.Position - root.Position).Magnitude
                if d < closestDist then
                    closestDist = d
                    closest = v
                end
            end
        end
    end
    return closest
end

-- GetNearestEnemy wrapper đã được khai báo trước UIConfig; upvalue GetConnectionEnemies
-- đã được gán ở trên, nên wrapper hoạt động đúng khi được gọi.

-- Fly đến vị trí cố định (alias _tp, dùng trong KataFarm) - already defined at line ~161

--// ===================== HELPER: GetM =====================
-- Đọc giá trị stat/material của player (VD: "Bones").
local function GetM(stat)
    local val = 0
    pcall(function()
        -- Try direct Data child first
        if player.Data:FindFirstChild(stat) then
            val = player.Data[stat].Value
        -- Try leaderstats
        elseif player.leaderstats and player.leaderstats:FindFirstChild(stat) then
            val = player.leaderstats[stat].Value
        -- Try PlayerGui inventory / backpack label (Bones shown in UI)
        else
            local inv = player.PlayerGui:FindFirstChild("Main")
            if inv then
                local b = inv:FindFirstChild(stat, true)
                if b and b:IsA("NumberValue") then val = b.Value end
            end
        end
    end)
    return val
end

--// ===================== HELPER: Attack =====================
-- Attack.Kill  – tp lên mob + dùng tool tấn công (mob thường)
-- Attack.Kill2 – tp sát mob + dùng tool tấn công (boss, ít lag hơn)
local Attack = {}

function Attack.Kill(mob, flag)
    if not flag then return end
    pcall(function()
        local mobRP = mob and mob:FindFirstChild("HumanoidRootPart")
        if not mobRP then return end
        local root = getRoot()
        local targetCF = mobRP.CFrame * CFrame.new(0, 25, 0)
        if root and (root.Position - targetCF.Position).Magnitude > 5 then
            _tp(targetCF)
        end
        equipSelectedWeapon()
    end)
end

function Attack.Kill2(mob, flag)
    if not flag then return end
    pcall(function()
        local mobRP = mob and mob:FindFirstChild("HumanoidRootPart")
        if not mobRP then return end
        local root = getRoot()
        local targetCF = mobRP.CFrame * CFrame.new(0, 25, 0)
        if root and (root.Position - targetCF.Position).Magnitude > 5 then
            _tp(targetCF)
        end
        equipSelectedWeapon()
    end)
end

--// ===================== STATUS CHECK: CAKE PRINCE =====================
-- Server trả về số mob CÒN CẦN kill (500 → 0), hiển thị trực tiếp.
task.spawn(function()
    while true do
        task.wait(0.1)
        pcall(function()
            local remaining = string.match(
                ReplicatedStorage.Remotes.CommF_:InvokeServer("CakePrinceSpawner"),
                "%d+"
            )
            if remaining and Elements["Farming"] and Elements["Farming"]["CakePrinceStatusLabel"] then
                Elements["Farming"]["CakePrinceStatusLabel"]:SetContent(
                    "Mob cần kill : " .. tonumber(remaining)
                )
            end
        end)
    end
end)

--// ===================== STATUS CHECK: BONES =====================
task.spawn(function()
    while wait(0.2) do
        pcall(function()
            local bones = tostring(GetM("Bones"))
            if Elements["Farming"] and Elements["Farming"]["TotalBonesLabel"] then
                Elements["Farming"]["TotalBonesLabel"]:SetDesc(" Bones : " .. bones)
            end
        end)
    end
end)

--// ===================== SHARED KILL MOB LOOP =====================
-- Dùng chung cho Bone, Cake mob, Cake boss.
-- flagFn()      → trả về true khi feature vẫn còn bật
-- breakExtraFn()→ điều kiện thoát thêm (trả về true → break)
-- timeout       → giây timeout (default 30, boss dùng 90)
local function killMobLoop(mob, flagFn, breakExtraFn, timeout)
    timeout = timeout or 30
    local mobRP = mob:FindFirstChild("HumanoidRootPart")
    if not mobRP then return end
    local lockedPos  = mobRP.Position
    local lastMobPos = Vector3.new(0, -9999, 0)
    local deadline   = tick() + timeout
    local busoTimer  = tick()

    -- Set globals cho bring mob spawn loop
    getgenv().CurrentTargetMob = mob
    _lockedBringPos = CFrame.new(lockedPos)

    while flagFn() and tick() < deadline do
        local hum = mob:FindFirstChildOfClass("Humanoid")
        if not mob.Parent or not hum or hum.Health <= 0 then break end
        if breakExtraFn and breakExtraFn() then break end

        mobRP = mob:FindFirstChild("HumanoidRootPart")
        if not mobRP then break end

        -- Buso mỗi 2s
        if tick() - busoTimer >= 2 then activateBuso(); busoTimer = tick() end

        if getgenv().BringMob then
            local anchorCF = CFrame.new(lockedPos + Vector3.new(0, 25, 0))
            local r = getRoot()
            if r and (r.Position - anchorCF.Position).Magnitude > 5 then _tp(anchorCF) end
            if (mobRP.Position - lockedPos).Magnitude > 3 then
                pcall(function()
                    mobRP.CFrame = CFrame.new(lockedPos)
                    hum.WalkSpeed = 0; hum.JumpPower = 0
                end)
            end
            -- Spawn loop bring mob phụ tự xử lý — không gọi BringEnemy ở đây
        else
            local curPos = mobRP.Position
            if (curPos - lastMobPos).Magnitude > 2 then
                lastMobPos = curPos
                _tp(mobRP.CFrame * CFrame.new(0, 25, 0))
            end
        end

        local r = getRoot()
        if r and (mobRP.Position - r.Position).Magnitude <= 200 then
            equipSelectedWeapon()
        end

        task.wait(0)
    end

    -- Xóa target sau khi mob chết
    getgenv().CurrentTargetMob = nil
    _lockedBringPos = nil
end

--// ===================== AUTO FARM BONE =====================
-- Sơ đồ:
--   Không có mob bone / chưa ở vùng spawn → fly tới spawn bone
--   AcceptQuestC bật + chưa có quest       → fly NPC → nhận quest
--   Có mob + có quest (hoặc AcceptQuestC tắt) → killMobLoop (buso+weapon+noclip)
task.spawn(function()
    local SPAWN_BONE = CFrame.new(-9495.68, 453.59, 5977.35)
    local QUEST_BONE = CFrame.new(-9516.99316, 172.017181, 6078.46533, 0,0,-1, 0,1,0, 1,0,0)
    local BONE_MOBS  = {"Reborn Skeleton","Living Zombie","Demonic Soul","Posessed Mummy"}
    local BONE_QUESTS = {
        {"StartQuest","HauntedQuest2",2},
        {"StartQuest","HauntedQuest2",1},
        {"StartQuest","HauntedQuest1",1},
        {"StartQuest","HauntedQuest1",2},
    }

    while true do
        task.wait(0.3)
        if not _G.AutoFarm_Bone then continue end
        pcall(function()
            local root    = getRoot()
            local questUI = plr.PlayerGui.Main.Quest
            if not root then return end

            -- ── Xác định mob cần farm ──────────────────────────────────────────
            -- Nếu có quest → ưu tiên mob trong quest; hết mob quest → fallback list
            local bone
            local qv, qt = getQuestInfo()
            if qv then
                -- Tìm mob quest trong list BONE_MOBS
                for _, name in ipairs(BONE_MOBS) do
                    if string.find(qt, name, 1, true) then
                        bone = GetConnectionEnemies(name)
                        break
                    end
                end
                -- Hết mob quest → farm bất kỳ mob nào còn lại
                if not bone then
                    bone = GetConnectionEnemies(BONE_MOBS)
                end
            else
                bone = GetConnectionEnemies(BONE_MOBS)
            end

            -- ── Không có mob → fly tới spawn bone ──
            if not bone then
                _tp(SPAWN_BONE)
                local dl = tick() + 8
                repeat task.wait(0.3)
                until not _G.AutoFarm_Bone
                    or (SPAWN_BONE.Position - (getRoot() and getRoot().Position or Vector3.zero)).Magnitude <= 60
                    or tick() > dl
                return
            end

            -- ── AcceptQuestC bật + chưa có quest → fly NPC nhận quest ──
            if _G.AcceptQuestC and not questUI.Visible then
                _tp(QUEST_BONE)
                local dl = tick() + 10
                repeat task.wait(0.2)
                until not _G.AutoFarm_Bone
                    or (QUEST_BONE.Position - (getRoot() and getRoot().Position or Vector3.zero)).Magnitude <= 50
                    or tick() > dl
                if not _G.AutoFarm_Bone then return end
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer(
                        unpack(BONE_QUESTS[math.random(1, #BONE_QUESTS)])
                    )
                end)
                task.wait(0.5)
                return
            end

            -- ── Farm mob bone ──
            killMobLoop(bone,
                function() return _G.AutoFarm_Bone end,
                function() return _G.AcceptQuestC and not questUI.Visible end
            )
        end)
    end
end)

--// ===================== AUTO JOIN DUNGEON (background loop) =====================
task.spawn(function()
    while true do
        task.wait(2)
        if not _G.AutoJoinDungeon then continue end
        if _G.MutiJoinDungeon then continue end
        pcall(function()
            local bestPad = GetBestPad()
            if not bestPad then return end
            local n = bestPad:GetAttribute("NumPlayersOnPad") or 0
            if n < (_G.SelectedMaxPlayers or 1) then return end
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local targetCF = bestPad.Pad.CFrame * CFrame.new(0, 5, 0)
            if (hrp.Position - targetCF.Position).Magnitude < 10 then return end
            enableFly()
            _tp(targetCF)
        end)
    end
end)

--// ===================== MUTI JOIN DUNGEON (background loop) =====================
task.spawn(function()
    while true do
        task.wait(0.5)
        if not _G.MutiJoinDungeon then continue end
        if _G.AutoJoinDungeon then continue end
        pcall(function()
            local targetName = _G.MutiFarmTarget
            if not targetName or targetName == "" then return end
            local targetPlayer = game.Players:FindFirstChild(targetName)
            if not targetPlayer then return end
            local targetChar = targetPlayer.Character
            local targetHRP  = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            local myHRP = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if not myHRP then return end
            if (myHRP.Position - targetHRP.Position).Magnitude < 15 then return end
            enableFly()
            _tp(targetHRP.CFrame)
        end)
    end
end)

--// =====================================
--// FAST ATTACK | 0.1s INTERVAL | RANGE 2000
--// =====================================
do
    local _Net            = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
    local _RegisterAttack = _Net:WaitForChild("RE/RegisterAttack")
    local _RegisterHit    = _Net:WaitForChild("RE/RegisterHit")

    -- Mặc định bật attack Buddha (attack cũ)
    if _G.AttackBuddha == nil then _G.AttackBuddha = true end

    local CONFIG = {
        RANGE    = 2000,
        INTERVAL = 0.1,
    }

    local LastAttack = 0
    local LastTool   = nil

    local function IsAlive(m)
        local h = m:FindFirstChild("Humanoid")
        return h and h.Health > 0
    end

    local function GetTargets()
        local char = plr.Character
        if not char then return {} end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return {} end
        local list = {}
        local function Scan(folder)
            for _, v in pairs(folder:GetChildren()) do
                if v ~= char
                    and v:FindFirstChild("HumanoidRootPart")
                    and IsAlive(v)
                then
                    if (hrp.Position - v.HumanoidRootPart.Position).Magnitude <= CONFIG.RANGE then
                        table.insert(list, v)
                    end
                end
            end
        end
        if workspace:FindFirstChild("Enemies")    then Scan(workspace.Enemies)    end
        if workspace:FindFirstChild("Characters") then Scan(workspace.Characters) end
        return list
    end

    local function AttackMeleeSword(targets)
        pcall(function() _RegisterAttack:FireServer(0) end)
        local hitTable = {}
        for i, v in ipairs(targets) do
            hitTable[i] = { v, v.HumanoidRootPart }
        end
        pcall(function() _RegisterHit:FireServer(targets[1].HumanoidRootPart, hitTable) end)
    end

    -- Light & Ice: dùng LeftClickRemote với direction thực đến enemy
    -- (AttackFruit() bắn direction xuống đất nên miss, phải dùng hướng thật)
    local SwordFruitCombo = 0
    local SwordFruitComboTime = 0
    local function AttackSwordFruit(targets)
        local char = plr.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local tool = char:FindFirstChildOfClass("Tool")
        if not tool then return end
        local remote = tool:FindFirstChild("LeftClickRemote")
        if not remote then return end
        -- Tính direction đến target gần nhất
        local targetHRP = targets[1]:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return end
        local direction = (targetHRP.Position - hrp.Position).Unit
        -- Track combo (reset sau 0.3s)
        if tick() - SwordFruitComboTime > 0.3 then SwordFruitCombo = 0 end
        SwordFruitCombo = (SwordFruitCombo % 4) + 1
        SwordFruitComboTime = tick()
        pcall(function() remote:FireServer(direction, SwordFruitCombo) end)
    end

    local function AttackFruit()
        local char = plr.Character
        if not char then return end
        local tool = char:FindFirstChildOfClass("Tool")
        if not tool or tool.ToolTip ~= "Blox Fruit" then return end
        local remote = tool:FindFirstChild("LeftClickRemote")
        if not remote then return end
        pcall(function() remote:FireServer(Vector3.new(0.01, -500, 0.01), 1, true) end)
        pcall(function() remote:FireServer(false) end)
    end

    RunService.Heartbeat:Connect(function()
        -- Chỉ attack khi bất kỳ chế độ farm nào đang bật
        local anyFarm = getgenv().IsFarming or _G.AutoFarm_Bone
                     or _G.Auto_Cake_Prince or getgenv().FarmDungeon
                     or _G.AutoAuraFarm or _G.AutoTyrant
        if not anyFarm then return end
        if not _G.AttackBuddha then return end  -- Tắt khi dùng attack mới

        local now = tick()
        if now - LastAttack < CONFIG.INTERVAL then return end
        LastAttack = now

        local char = plr.Character
        if not char then return end
        local tool = char:FindFirstChildOfClass("Tool")
        if tool ~= LastTool then LastTool = tool end

        local targets = GetTargets()
        if #targets == 0 then return end

        -- Light & Ice có M1 kiểu sword → dùng RegisterAttack/RegisterHit
        local M1_SWORD_FRUITS = { Light = true, Ice = true }

        if tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword") then
            AttackMeleeSword(targets)
        elseif tool and tool.ToolTip == "Blox Fruit" then
            if M1_SWORD_FRUITS[tool.Name] then
                AttackSwordFruit(targets)
            else
                AttackFruit()
            end
        end
    end)

    -- ─── Attack Mới: hỗ trợ Ice/Light (chạy khi AttackBuddha = false) ───────
    local NewCombo     = 0
    local NewComboTime = 0
    RunService.Heartbeat:Connect(function()
        local anyFarm = getgenv().IsFarming or _G.AutoFarm_Bone
                     or _G.Auto_Cake_Prince or getgenv().FarmDungeon
                     or _G.AutoAuraFarm or _G.AutoTyrant
        if not anyFarm then return end
        if _G.AttackBuddha then return end  -- Tắt khi dùng attack Buddha

        local now = tick()
        if now - LastAttack < CONFIG.INTERVAL then return end
        LastAttack = now

        local char = plr.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local tool = char:FindFirstChildOfClass("Tool")

        local targets = GetTargets()
        if #targets == 0 then return end

        -- Fruit có LeftClickRemote → bắn direction thực đến target
        if tool and tool.ToolTip == "Blox Fruit" then
            local remote = tool:FindFirstChild("LeftClickRemote")
            if remote then
                local targetHRP = targets[1]:FindFirstChild("HumanoidRootPart")
                if targetHRP then
                    local direction = (targetHRP.Position - hrp.Position).Unit
                    if tick() - NewComboTime > 0.3 then NewCombo = 0 end
                    NewCombo = (NewCombo % 4) + 1
                    NewComboTime = tick()
                    pcall(function() remote:FireServer(direction, NewCombo) end)
                end
                return
            end
        end

        -- Melee / Sword / Fruit không có LeftClickRemote → RegisterHit với Head
        local firstHead = nil
        local hitTable  = {}
        for i, v in ipairs(targets) do
            if not firstHead then
                firstHead = v:FindFirstChild("Head") or v.HumanoidRootPart
            end
            hitTable[i] = { v, v.HumanoidRootPart }
        end
        pcall(function() _RegisterAttack:FireServer(-math.huge) end)
        pcall(function() _RegisterHit:FireServer(firstHead, hitTable) end)
    end)
end

print("✅ FAST ATTACK ENABLED | Interval: 0.1s | Range: 2000")

--// ===================== ANTI-AFK =====================
do
    local VIM = game:GetService("VirtualInputManager")
    local VU  = game:GetService("VirtualUser")
    local cam = workspace.CurrentCamera

    -- Loop liên tục mỗi 240s: giả lập input để reset idle timer
    task.spawn(function()
        while task.wait(240) do
            pcall(function()
                cam.CFrame = cam.CFrame * CFrame.Angles(
                    math.random(-10, 10) * 0.01,
                    math.random(-10, 10) * 0.01,
                    0
                )
                VIM:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
        end
    end)

    -- Backup: khi Roblox sắp kick AFK → giả lập input ngay lập tức
    plr.Idled:Connect(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end

--// ===================== BUY FIGHTING STYLE =====================
local currentWorldKey = World1 and "world1" or World2 and "world2" or World3 and "world3" or "world1"

local FightingStyleData = {
    BlackLeg = {
        world1 = Vector3.new(-984, 17, 3990),
        world2 = Vector3.new(-4753, 37, -4853),
        world3 = Vector3.new(-5050, 374, -3183),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBlackLeg") end,
    },
    Electro = {
        world1 = Vector3.new(-5383, 17, -2149),
        world2 = Vector3.new(-4870, 37, -4769),
        world3 = Vector3.new(-5000, 317, -3201),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyElectro") end,
    },
    FishmanKarate = {
        world1 = Vector3.new(61586, 23, 987),
        world2 = Vector3.new(-4960, 39, -4663),
        world3 = Vector3.new(-5026, 375, -3196),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyFishmanKarate") end,
    },
    DragonClaw = {
        world1 = nil,
        world2 = Vector3.new(695, 189, 654),
        world3 = Vector3.new(-4983, 374, -3213),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "2") end,
    },
    Superhuman = {
        world1 = nil,
        world2 = Vector3.new(1380, 250, -5188),
        world3 = Vector3.new(-5007, 374, -3203),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuySuperhuman") end,
    },
    DeathStep = {
        world1 = nil,
        world2 = Vector3.new(6352, 300, -6762),
        world3 = Vector3.new(-5002, 318, -3225),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyDeathStep") end,
    },
    SharkmanKarate = {
        world1 = nil,
        world2 = Vector3.new(-2604, 242, -10318),
        world3 = Vector3.new(-4969, 317, -3226),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuySharkmanKarate") end,
    },
    ElectricClaw = {
        world1 = nil,
        world2 = nil,
        world3 = Vector3.new(-10373, 334, -10136),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyElectricClaw") end,
    },
    DragonTalon = {
        world1 = nil,
        world2 = nil,
        world3 = Vector3.new(5659, 1214, 859),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyDragonTalon") end,
    },
    Godhuman = {
        world1 = nil,
        world2 = nil,
        world3 = Vector3.new(-13771, 337, -9881),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyGodhuman") end,
    },
    SanguineArt = {
        world1 = nil,
        world2 = nil,
        world3 = Vector3.new(-16517, 26, -185),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuySanguineArt") end,
    },
}

-- Loop Buy Fighting Style
task.spawn(function()
    while task.wait(0.5) do
        if not _G.AutoBuyFightingStyle then continue end

        -- Chưa chọn võ → thông báo
        local selected = _G.SelectedFightingStyle
        if not selected or selected == "" then
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title    = "⚠️ Buy Fighting Style",
                Text     = "Please select a Fighting Style first.",
                Duration = 4,
            })
            _G.AutoBuyFightingStyle = false
            continue
        end

        local data = FightingStyleData[selected]
        if not data then
            _G.AutoBuyFightingStyle = false
            continue
        end

        local npcPos = data[currentWorldKey]
        if not npcPos then
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title    = "⚠️ Buy Fighting Style",
                Text     = selected .. " is not available in this world.",
                Duration = 4,
            })
            _G.AutoBuyFightingStyle = false
            continue
        end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then task.wait(1) continue end

        local dist = (root.Position - npcPos).Magnitude

        if dist <= 100 then
            -- Đã đến gần NPC → mua + tắt toggle
            pcall(data.remote)
            task.wait(0.5)
            _G.AutoBuyFightingStyle = false
            _stopCurrentTween()
        else
            -- Tween đến NPC (tích hợp SameY + tele trung gian nếu bật)
            _tp(CFrame.new(npcPos))
        end
    end
end)

--// ===================== FARM CHEST HELPERS =====================
local CollectionService = game:GetService("CollectionService")

-- Tìm chest gần nhất (ưu tiên island hiện tại nếu có)
local function getNearestChest()
    local char = player.Character
    if not char then return nil, math.huge end
    local pos = char:GetPivot().Position
    local chests = CollectionService:GetTagged("_ChestTagged")
    local nearest, nearestDist = nil, math.huge
    for _, chest in ipairs(chests) do
        if chest:GetAttribute("IsDisabled") then continue end
        local d = (chest:GetPivot().Position - pos).Magnitude
        if d < nearestDist then
            nearestDist = d
            nearest     = chest
        end
    end
    return nearest, nearestDist
end

-- Jump helper (bypass = bỏ qua cooldown 1s)
local _lastJumpTime = 0
local function PerformJump(bypass)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local now = tick()
    if not bypass and (now - _lastJumpTime) < 1 then return end
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    _lastJumpTime = now
end

-- Reset nhân vật (gán HP = 0, lặp tới khi chết)
local function ResetPlayer()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if hum then hum.Health = 0 end
end

--// ── FARM CHEST <TWEEN> ──────────────────────────────────────────────────────
-- Logic:
--   • Mỗi 0.15s quét chest gần nhất.
--   • Nếu chest đang tween đến bị thay thế bởi chest gần hơn → hủy tween, đổi đích.
--   • Dùng _tp() (đã tích hợp doIntermediateTeleport + SameY) để di chuyển.
--   • Khi ≤10 stud → nhảy liên tục để nhặt.
task.spawn(function()
    local _chestTarget = nil  -- chest đang nhắm đến
    while true do
        task.wait(0.1)

        if not _G.AutoChestTween then
            -- Tắt toggle → dừng tween + reset toàn bộ ngay lập tức
            if _chestTarget then
                _stopCurrentTween()
                _chestTarget = nil
            end
            task.wait(0.3)
            continue
        end

        -- Conflict guard
        if _G.AutoChestBypass then
            _stopCurrentTween()
            _G.AutoChestTween = false
            _chestTarget = nil
            continue
        end

        local char = player.Character
        if not char then task.wait(0.5) continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then task.wait(0.3) continue end

        local nearest, dist = getNearestChest()
        if not nearest then
            -- Không còn chest → dừng tween, chờ
            _stopCurrentTween()
            _chestTarget = nil
            task.wait(0.3)
            continue
        end

        -- Khi đã gần ≤10 stud → nhảy liên tục để nhặt
        if dist <= 3 then
            _stopCurrentTween()
            PerformJump(true)
            PerformJump(true)
            _chestTarget = nil  -- reset để pick chest tiếp theo
            continue
        end

        -- Chest mới gần hơn hoặc chưa có target → hủy tween cũ, đổi đích
        if _chestTarget ~= nearest then
            _chestTarget = nearest
            _stopCurrentTween()
            pcall(function() _tp(nearest:GetPivot()) end)
        end
    end
end)

--// ── FARM CHEST <BYPASS> ─────────────────────────────────────────────────────
-- Logic:
--   • Teleport thẳng đến chest gần nhất liên tục (delay = 0).
--   • Khi ≤10 stud → nhảy liên tục.
--   • Mỗi 6s (CHỈ đếm khi đang sống, sau khi hồi sinh xong) → reset nhân vật.
--   • Chờ hồi sinh hoàn toàn xong mới bắt đầu đếm lại.
task.spawn(function()
    local _bypassTimer   = 0   -- tích lũy thời gian sống sau khi hồi sinh
    local RESET_INTERVAL = 6   -- giây giữa các lần reset
    local _waitingRespawn = false

    while true do
        task.wait()  -- delay = 0 (next frame)

        if not _G.AutoChestBypass then
            _bypassTimer      = 0
            _waitingRespawn   = false
            task.wait(0.3)
            continue
        end

        -- Conflict guard
        if _G.AutoChestTween then
            _G.AutoChestBypass = false
            _bypassTimer     = 0
            _waitingRespawn  = false
            continue
        end

        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        -- Đang chết hoặc chưa hồi sinh → không đếm timer, chờ
        if not char or not hum or hum.Health <= 0 or not root then
            _waitingRespawn = true
            task.wait(0.1)
            continue
        end

        -- Vừa hồi sinh xong → reset timer, bắt đầu đếm lại
        if _waitingRespawn then
            _waitingRespawn = false
            _bypassTimer    = 0
            task.wait(0.5)  -- delay nhỏ sau respawn để char ổn định
            continue
        end

        -- Tích lũy thời gian sống (mỗi frame ≈ 1/60s nhưng dùng dt thực tế không có sẵn → dùng tick diff)
        _bypassTimer = _bypassTimer + task.wait()  -- task.wait() trả về dt

        -- 6s → reset
        if _bypassTimer >= RESET_INTERVAL then
            _bypassTimer = 0
            -- Lặp gán HP = 0 cho đến khi nhân vật thực sự chết
            repeat
                local c2 = player.Character
                local h2 = c2 and c2:FindFirstChildOfClass("Humanoid")
                if h2 and h2.Health > 0 then h2.Health = 0 end
                task.wait(0.05)
            until not player.Character
                or not player.Character:FindFirstChildOfClass("Humanoid")
                or player.Character:FindFirstChildOfClass("Humanoid").Health <= 0
            _waitingRespawn = true
            continue
        end

        -- Teleport thẳng đến chest gần nhất (delay = 0)
        local nearest, dist = getNearestChest()
        if not nearest then continue end

        if dist <= 3 then
            PerformJump(true)
            PerformJump(true)
        else
            pcall(function()
                root.CFrame = nearest:GetPivot() * CFrame.new(0, 3, 0)
            end)
        end
    end
end)

--// ===================== AUTO UP STATS =====================
-- Chạy ngầm, mỗi 1s kiểm tra:
--   _G.AutoUpStats        → toggle bật/tắt
--   _G.SelectedStatsType  → stat được chọn từ dropdown
-- Khi cả hai đều hợp lệ và player còn điểm → gọi AddPoint
task.spawn(function()
    local remote = ReplicatedStorage.Remotes.CommF_
    -- Map tên hiển thị → tên server nhận
    local STAT_MAP = {
        ["Melee"]       = "Melee",
        ["Sword"]       = "Sword",
        ["Gun"]         = "Gun",
        ["Demon Fruit"] = "Demon Fruit",
    }
    while true do
        task.wait(1)
        if not _G.AutoUpStats then continue end
        pcall(function()
            local selected = _G.SelectedStatsType
            if not selected then return end
            local statName = STAT_MAP[selected]
            if not statName then return end
            -- Kiểm tra còn điểm không
            if plr.Data.Points.Value == 0 then return end
            -- Dùng 9999999 để tiêu hết toàn bộ điểm hiện có vào stat đã chọn
            remote:InvokeServer("AddPoint", statName, 9999999)
        end)
    end
end)

----------------------------------------------------------------------------
-- TYRANT OF THE SKIES — Auto Farm (Boss + Vasos + Mobs + Quest)
----------------------------------------------------------------------------

local FarmHeight = 45

-- NoClip liên tục khi AutoTyrant bật
spawn(function()
    game:GetService("RunService").Stepped:Connect(function()
        if _G.AutoTyrant and _G.StartFarm then
            local char = game.Players.LocalPlayer.Character
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
                if char:FindFirstChild("Humanoid") then
                    char.Humanoid.AutoRotate = true
                    char.Humanoid:ChangeState(11)
                end
            end
        end
    end)
end)

-- Chọn mob + quest theo level
local function GetTargetByLevel()
    local myLevel = game.Players.LocalPlayer.Data.Level.Value

    if myLevel >= 2575 then
        return {
            Name = "Skull Slayer",
            QuestArgs = {"StartQuest", "TikiQuest3", 2},
            QuestPos = CFrame.new(-16665.0879, 105.27478, 1577.61743,
                -0.999621451, 3.5280582e-08, 0.0275127869,
                 3.5990368e-08, 1, 2.53032191e-08,
                -0.0275127869, 2.62838356e-08, -0.999621451),
            FarmPos = CFrame.new(-16709.49, 419.68, 1751.09)
        }
    elseif myLevel > 2550 then
        return {
            Name = "Serpent Hunter",
            QuestArgs = {"StartQuest", "TikiQuest3", 1},
            QuestPos = CFrame.new(-16665.0879, 105.27478, 1577.61743,
                -0.999621451, 3.5280582e-08, 0.0275127869,
                 3.5990368e-08, 1, 2.53032191e-08,
                -0.0275127869, 2.62838356e-08, -0.999621451),
            FarmPos = CFrame.new(-16645.64, 163.09, 1352.87)
        }
    elseif myLevel >= 2525 then
        return {
            Name = "Isle Champion",
            QuestArgs = {"StartQuest", "TikiQuest2", 2},
            QuestPos = CFrame.new(-16546.748, 55.7216759, -172.865311,
                -0.0595058464, 2.45485676e-08, 0.998227954,
                -5.3272025e-08, 1, -2.77677703e-08,
                -0.998227954, -5.48299717e-08, -0.0595058464),
            FarmPos = CFrame.new(-16602.1015625, 130.38734436035, 1087.2456054688)
        }
    elseif myLevel >= 2500 then
        return {
            Name = "Sun-kissed Warrior",
            QuestArgs = {"StartQuest", "TikiQuest2", 1},
            QuestPos = CFrame.new(-16546.748, 55.7216759, -172.865311,
                -0.0595058464, 2.45485676e-08, 0.998227954,
                -5.3272025e-08, 1, -2.77677703e-08,
                -0.998227954, -5.48299717e-08, -0.0595058464),
            FarmPos = CFrame.new(-16347, 64, 984)
        }
    elseif myLevel >= 2475 then
        return {
            Name = "Island Boy",
            QuestArgs = {"StartQuest", "TikiQuest1", 2},
            QuestPos = CFrame.new(-16546.748, 55.7216759, -172.865311,
                -0.0595058464, 2.45485676e-08, 0.998227954,
                -5.3272025e-08, 1, -2.77677703e-08,
                -0.998227954, -5.48299717e-08, -0.0595058464),
            FarmPos = CFrame.new(-16670, 43, -270)
        }
    else
        return {
            Name = "Isle Outlaw",
            QuestArgs = {"StartQuest", "TikiQuest1", 1},
            QuestPos = CFrame.new(-16546.748, 55.7216759, -172.865311,
                -0.0595058464, 2.45485676e-08, 0.998227954,
                -5.3272025e-08, 1, -2.77677703e-08,
                -0.998227954, -5.48299717e-08, -0.0595058464),
            FarmPos = CFrame.new(-16350, 45, -180)
        }
    end
end

-- Đếm mắt (vasos) chưa bị phá
local function GetEyesCount()
    local model = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("TikiOutpost")
        and workspace.Map.TikiOutpost:FindFirstChild("IslandModel")
    local count = 0
    if model then
        local eye1   = model:FindFirstChild("Eye1")
        local eye2   = model:FindFirstChild("Eye2")
        local chunks = model:FindFirstChild("IslandChunks")
        local eye3   = chunks and chunks:FindFirstChild("E") and chunks.E:FindFirstChild("Eye3")
        local eye4   = chunks and chunks:FindFirstChild("E") and chunks.E:FindFirstChild("Eye4")
        if eye1 and eye1.Transparency == 0 then count += 1 end
        if eye2 and eye2.Transparency == 0 then count += 1 end
        if eye3 and eye3.Transparency == 0 then count += 1 end
        if eye4 and eye4.Transparency == 0 then count += 1 end
    end
    return count
end

-- ════════════════════════════════════════════════════════════════════════════
-- TYRANT ENGINE — helpers + 3 logic loops
-- ════════════════════════════════════════════════════════════════════════════

local vim1 = game:GetService("VirtualInputManager")

-- ── Status label ─────────────────────────────────────────────────────────────
local function _setTyrantStatus(text)
    if _UI and _UI["TyrantStatusLabel"] then
        pcall(function() _UI["TyrantStatusLabel"]:SetText("Tyrant Status: " .. text) end)
    end
end

-- ── Guard helper ─────────────────────────────────────────────────────────────
local function _tyrantActive()
    return _G.AutoTyrant and _G.StartFarm
end

-- ── Equip weapon theo Select Tool dropdown (_G.ChooseWP) ─────────────────────
-- Dùng cho boss + mob (không dùng cho vaso)
local function _tyrantEquipSelectTool()
    local choice = _G.ChooseWP
    if not choice or choice == "" then return end
    local tooltipMap = {
        ["Melee"] = "Melee", ["Sword"] = "Sword",
        ["Gun"] = "Gun", ["Blox Fruit"] = "Blox Fruit",
    }
    local tooltip = tooltipMap[choice]
    if not tooltip then return end
    local char = plr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    for _, v in pairs(plr.Backpack:GetChildren()) do
        if v:IsA("Tool") and v.ToolTip == tooltip then
            local equipped = char:FindFirstChildOfClass("Tool")
            if not equipped or equipped.ToolTip ~= tooltip then
                hum:EquipTool(v)
                task.wait(0.12)
            end
            return
        end
    end
end

-- ── Equip weapon theo ToolTip (dùng cho vaso spam) ───────────────────────────
local function _equipByTooltip(tooltip)
    local char = plr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    for _, v in pairs(plr.Backpack:GetChildren()) do
        if v:IsA("Tool") and v.ToolTip == tooltip then
            local equipped = char:FindFirstChildOfClass("Tool")
            if not equipped or equipped.ToolTip ~= tooltip then
                hum:EquipTool(v)
                task.wait(0.1)
            end
            return
        end
    end
end

-- ── Thứ tự skill theo weapon ─────────────────────────────────────────────────
local WEAPON_SKILL_ORDER = {
    ["Melee"]      = {"Z", "X", "C"},
    ["Sword"]      = {"Z", "X"},
    ["Blox Fruit"] = {"Z", "X", "C", "V", "F"},
    ["Gun"]        = {"Z", "X"},
}
local WEAPON_TYPES = {"Melee", "Sword", "Blox Fruit", "Gun"}

-- Lấy hold time từ slider _G
local function _getHoldTime(weapon, skill)
    local map = {
        ["Melee"]      = { Z = _G.HoldMeleeZ, X = _G.HoldMeleeX, C = _G.HoldMeleeC },
        ["Sword"]      = { Z = _G.HoldSwordZ, X = _G.HoldSwordX },
        ["Gun"]        = { Z = _G.HoldGunZ,   X = _G.HoldGunX },
        ["Blox Fruit"] = { Z = _G.HoldFruitZ, X = _G.HoldFruitX,
                           C = _G.HoldFruitC, V = _G.HoldFruitV, F = _G.HoldFruitF },
    }
    return (map[weapon] and map[weapon][skill]) or 0
end

-- Lấy keys đã chọn cho weapon — nil nếu rỗng
local function _getSelectedKeys(weapon)
    local map = {
        ["Melee"]      = _G.SkillMeleeKeys,
        ["Sword"]      = _G.SkillSwordKeys,
        ["Blox Fruit"] = _G.SkillFruitKeys,
        ["Gun"]        = _G.SkillGunKeys,
    }
    local t = map[weapon]
    return (type(t) == "table" and next(t)) and t or nil
end

-- Key có trong table không
local function _keyIn(t, k)
    for _, v in pairs(t) do if v == k then return true end end
    return false
end

-- Aim camera xuống để skill không miss
local function _aimDown()
    pcall(function()
        local cam = workspace.CurrentCamera
        cam.CFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + Vector3.new(0,-1,0))
    end)
end

-- Spam tất cả skill đã chọn của 1 weapon (blocking)
local function _spamWeaponSkills(weapon)
    local keys = _getSelectedKeys(weapon)
    if not keys then return end
    _aimDown()
    _equipByTooltip(weapon)
    task.wait(0.1)
    local order = WEAPON_SKILL_ORDER[weapon] or {}
    for i, k in ipairs(order) do
        if not _keyIn(keys, k) then continue end
        local hold = _getHoldTime(weapon, k)
        vim1:SendKeyEvent(true,  k, false, game)
        task.wait(hold > 0 and hold or 0.05)
        vim1:SendKeyEvent(false, k, false, game)
        -- delay 0.5s giữa các skill, không delay skill cuối
        local isLast = true
        for j = i+1, #order do
            if _keyIn(keys, order[j]) then isLast = false; break end
        end
        if not isLast then task.wait(0.5) end
    end
end

-- Danh sách weapon active (có ít nhất 1 skill được chọn)
local function _getActiveWeapons()
    local t = {}
    for _, wp in ipairs(WEAPON_TYPES) do
        if _getSelectedKeys(wp) then table.insert(t, wp) end
    end
    return t
end

-- ── Tìm mob gần nhất ─────────────────────────────────────────────────────────
local TYRANT_MOBS = {
    "Skull Slayer", "Serpent Hunter", "Isle Champion",
    "Sun-kissed Warrior", "Island Boy", "Isle Outlaw"
}

local function _findClosestMob(hrp)
    local closest, minD = nil, math.huge
    for _, v in pairs(workspace.Enemies:GetChildren()) do
        if table.find(TYRANT_MOBS, v.Name)
        and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
        and v:FindFirstChild("HumanoidRootPart") then
            local d = (hrp.Position - v.HumanoidRootPart.Position).Magnitude
            if d < minD then minD = d; closest = v end
        end
    end
    return closest
end

-- ── Tìm bình gần nhất ────────────────────────────────────────────────────────
local VASO_POSITIONS = {
    CFrame.new(-16335.1, 158.1, 1465.6), CFrame.new(-16288.6, 158.1, 1470.3),
    CFrame.new(-16258.0, 156.7, 1461.4), CFrame.new(-16212.4, 158.1, 1466.3),
    CFrame.new(-16335.0, 159.3, 1324.8), CFrame.new(-16286.0, 155.9, 1323.8),
    CFrame.new(-16250.3, 159.3, 1316.3),
}

local function _findClosestVaso(hrp, excludeIdx)
    local closest, closestIdx, minD = nil, nil, math.huge
    for i, cf in ipairs(VASO_POSITIONS) do
        if i == excludeIdx then continue end
        local d = (hrp.Position - cf.Position).Magnitude
        if d < minD then minD = d; closest = cf; closestIdx = i end
    end
    return closest, closestIdx
end

-- ════════════════════════════════════════════════════════════════════════════
-- LOGIC 1 — Phá bình triệu hồi boss (khi đủ 4 mắt)
-- Flow: tween bình gần nhất → equip weapon random (không trùng trước) →
--       spam skill của weapon đó → bình gần tiếp theo (weapon random khác) →
--       lặp qua tất cả weapon active → lặp lại từ đầu cho đến khi boss xuất hiện
-- ════════════════════════════════════════════════════════════════════════════
local function _logic1_BreakVasos()
    _setTyrantStatus("Breaking Vasos")

    local activeWeapons = _getActiveWeapons()
    -- Nếu không chọn skill nào thì vẫn chạy nhưng chỉ tween qua bình (không spam)
    local weaponQueue = {}  -- queue weapon để dùng lần lượt qua từng bình
    local lastWeaponIdx = 0

    -- Build queue: cycle qua tất cả weapon active không trùng liên tiếp
    local function _nextWeapon()
        if #activeWeapons == 0 then return nil end
        if #activeWeapons == 1 then return activeWeapons[1] end
        local idx
        repeat idx = math.random(1, #activeWeapons)
        until idx ~= lastWeaponIdx
        lastWeaponIdx = idx
        return activeWeapons[idx]
    end

    local lastVasoIdx = nil  -- tránh tween bình vừa rời

    while _tyrantActive() do
        -- Thoát nếu đã có boss
        local boss = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
        if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then break end
        -- Thoát nếu chưa đủ 4 mắt (không cần phá nữa)
        if GetEyesCount() ~= 4 then break end

        local char = plr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2); continue end

        -- Tìm bình gần nhất (không phải bình vừa rời)
        local vasoPos, vasoIdx = _findClosestVaso(hrp, lastVasoIdx)
        if not vasoPos then task.wait(0.2); continue end
        lastVasoIdx = vasoIdx

        -- Tween đến bình, chờ đến nơi
        _tp(vasoPos)
        waitArrival(vasoPos.Position, 20, 8)
        if not _tyrantActive() then break end

        -- Chọn weapon random (không trùng lần trước)
        local weapon = _nextWeapon()

        if weapon then
            -- Equip weapon đã chọn trong Select Skill
            _equipByTooltip(weapon)
            task.wait(0.1)
            -- Spam tất cả skill đã chọn của weapon đó 1 lần
            _spamWeaponSkills(weapon)
        else
            task.wait(0.3)
        end

        task.wait(0.1)
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- LOGIC 2 — Farm boss (khi boss tồn tại)
-- Flow: tween đầu boss +45Y → equip Select Tool → spam skill →
--       nếu chết thì chờ hồi sinh → tiếp tục cho đến khi boss chết
-- ════════════════════════════════════════════════════════════════════════════
local function _logic2_FarmBoss(boss)
    _setTyrantStatus("Killing Boss")

    while _tyrantActive() do
        if not (boss and boss.Parent and boss:FindFirstChild("Humanoid")) then break end
        if boss.Humanoid.Health <= 0 then break end
        if not boss:FindFirstChild("HumanoidRootPart") then task.wait(0.2); continue end

        -- Tween lên đầu boss, chờ đến nơi
        local bossPos = boss.HumanoidRootPart.CFrame * CFrame.new(0, FarmHeight, 0)
        _tp(bossPos)
        waitArrival(bossPos.Position, 35, 5)

        if not _tyrantActive() then break end
        if not (boss and boss.Parent) then break end

        -- Equip Select Tool và bám boss cho đến khi chết hoặc player chết
        local root = getRoot()
        while _tyrantActive()
            and boss and boss.Parent
            and boss:FindFirstChild("Humanoid")
            and boss.Humanoid.Health > 0
        do
            -- Bám boss nếu di chuyển
            if boss:FindFirstChild("HumanoidRootPart") then
                local newBossPos = boss.HumanoidRootPart.CFrame * CFrame.new(0, FarmHeight, 0)
                root = getRoot()
                if root and (root.Position - newBossPos.Position).Magnitude > 35 then
                    _tp(newBossPos)
                end
            end

            -- Equip Select Tool (attack chạy qua Heartbeat tự động)
            _tyrantEquipSelectTool()

            -- Detect chết → chờ hồi sinh
            local char = plr.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health <= 0 then
                    _setTyrantStatus("Dead — Waiting Respawn")
                    plr.CharacterAdded:Wait()
                    task.wait(1.5)
                    _setTyrantStatus("Killing Boss")
                end
            end

            task.wait(0.1)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- LOGIC 3 — Farm mob thường cày mắt (khi chưa đủ 4 mắt)
-- Flow: (nhận quest nếu bật) → tween mob gần nhất +20Y →
--       equip Select Tool → spam skill → lặp
-- Quest: chưa có quest → tween NPC → nhận → farm mob → quest done → nhận lại
-- ════════════════════════════════════════════════════════════════════════════
local function _logic3_FarmMobs()
    _setTyrantStatus("Farming Mobs")

    while _tyrantActive() do
        -- Thoát nếu đã đủ 4 mắt hoặc boss xuất hiện
        local eyes = GetEyesCount()
        local boss = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
        if eyes == 4 then break end
        if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then break end

        local char = plr.Character or plr.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart", 3)
        if not hrp then task.wait(0.2); continue end

        -- ── Quest handling ──────────────────────────────────────────────────
        if _G.AcceptQuest then
            local questVisible = pcall(function()
                return plr.PlayerGui.Main.Quest.Visible
            end) and plr.PlayerGui.Main.Quest.Visible or false

            if not questVisible then
                _setTyrantStatus("Getting Quest")
                local td = GetTargetByLevel()
                _tp(td.QuestPos)
                waitArrival(td.QuestPos.Position, 6, 10)
                if not _tyrantActive() then break end
                pcall(function()
                    game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(
                        unpack(td.QuestArgs)
                    )
                end)
                task.wait(0.5)
                _setTyrantStatus("Farming Mobs")
                continue
            end
        end

        -- ── Tìm mob gần nhất ────────────────────────────────────────────────
        local mob = _findClosestMob(hrp)

        if mob then
            local mobPos = mob.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0)
            _tp(mobPos)
            waitArrival(mobPos.Position, 25, 6)
            if not _tyrantActive() then break end

            -- Bám mob + equip Select Tool cho đến khi mob chết
            -- Attack chạy qua Heartbeat tự động (giống farm level)
            while _tyrantActive()
                and mob.Parent
                and mob:FindFirstChild("Humanoid")
                and mob.Humanoid.Health > 0
            do
                if GetEyesCount() == 4 then break end
                local bossNow = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
                if bossNow and bossNow:FindFirstChild("Humanoid") and bossNow.Humanoid.Health > 0 then break end

                -- Bám mob nếu di chuyển
                if mob:FindFirstChild("HumanoidRootPart") then
                    local root = getRoot()
                    local newMobPos = mob.HumanoidRootPart.Position + Vector3.new(0, 20, 0)
                    if root and (root.Position - newMobPos).Magnitude > 25 then
                        _tp(CFrame.new(newMobPos))
                    end
                end

                -- Equip Select Tool (Heartbeat attack tự xử lý)
                _tyrantEquipSelectTool()
                task.wait(0.1)
            end
        else
            -- Không có mob → tween về FarmPos của level
            local td = GetTargetByLevel()
            _tp(td.FarmPos)
            task.wait(1)
        end

        task.wait(0.1)
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- MAIN LOOP — điều phối 3 logic
-- ════════════════════════════════════════════════════════════════════════════
spawn(function()
    while task.wait(0.15) do
        if not _tyrantActive() then continue end

        pcall(function()
            local boss = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
            local eyes = GetEyesCount()

            if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then
                -- Logic 2: có boss → farm boss
                _logic2_FarmBoss(boss)

            elseif eyes == 4 then
                -- Logic 1: đủ 4 mắt → phá bình
                _logic1_BreakVasos()

            else
                -- Logic 3: chưa đủ mắt → farm mob
                _logic3_FarmMobs()
            end
        end)
    end
end)