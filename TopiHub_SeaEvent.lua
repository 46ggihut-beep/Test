local Fluent = loadstring(game:HttpGet(
    "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Topi Hub [ Beta V0.012 ]",
    SubTitle = "by wzarii & AI",
    TabWidth = 160,
    Theme = "Dark",
    Acrylic = false,
    Size = UDim2.fromOffset(530, 400),
    MinimizeKey = Enum.KeyCode.End
})

--// ================= SERVICES =================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local VirtualUser        = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")
local HttpService        = game:GetService("HttpService")

local player = Players.LocalPlayer
local lp     = player
local plr    = player

--// ================= TOGGLE BUTTON UI =================
local screenGui = Instance.new("ScreenGui", game.CoreGui)
screenGui.Name = "ControlGUI"

local toggleButton = Instance.new("ImageButton", screenGui)
toggleButton.Size                = UDim2.new(0, 50, 0, 50)
toggleButton.Position            = UDim2.new(0.02, 0, 0.22, 0)
toggleButton.Image               = "rbxassetid://89099965623104"
toggleButton.BackgroundTransparency = 1
toggleButton.Active              = true
toggleButton.Draggable           = false

local dragging  = false
local dragInput = nil
local dragStart = nil
local startPos  = nil

toggleButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = toggleButton.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

toggleButton.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        toggleButton.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

toggleButton.MouseButton1Click:Connect(function()
    Window:Minimize()
end)

--// ================= TABS =================
local Tabs = {
    Settings   = Window:AddTab({Title = "cài đặt"}),
    Main       = Window:AddTab({Title = "Farming"}),
    SeaEvent   = Window:AddTab({Title = "Sea Event"}),
    Leviathan  = Window:AddTab({Title = "Leviathan Hunt"}),
}

--// ================= ATTACK MODULE (từ AttackModule.lua - luôn chạy ngầm) =================
--[[
  Banana Hub / Chuoi Hub - Attack Module (Cleaned)
  Scope: Weapon (Melee/Sword) + Blox Fruit + Gun + Attack No Animation
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

LocalPlayer.CharacterAdded:Connect(function(c)
    Character = c
end)

-- // Modules
local MouseModule  = require(ReplicatedStorage:WaitForChild("Mouse"))
local CombatUtil   = require(ReplicatedStorage.Modules.CombatUtil)
local Net          = require(ReplicatedStorage.Modules.Net)

local RegisterAttack = ReplicatedStorage.Modules.Net:WaitForChild("RE/RegisterAttack")
local RegisterHit    = Net.RemoteEvent(Net, "RegisterHit", true)

-- // Settings fallback
if not getgenv().Settings then
    getgenv().Settings = {}
end
local Settings = getgenv().Settings
if Settings["Attack No Animation "] == nil then
    Settings["Attack No Animation "] = true
end
if not Settings["Select Weapon"] then
    Settings["Select Weapon"] = "Melee"
end

-- // State (combo / fruit click counter)
local comboIndex   = 0
local fruitClickId = 1

---------------------------------------------------------------------------
-- 1. equiptool
---------------------------------------------------------------------------
local function equiptool(toolName)
    if not toolName then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    local tool = bp:FindFirstChild(toolName)
    if not tool then return end
    local hum = Character and Character:FindFirstChildOfClass("Humanoid")
    if hum and not hum.Sit then
        hum:EquipTool(tool)
    end
end

---------------------------------------------------------------------------
-- 2. NameWeapon  (by ToolTip)
---------------------------------------------------------------------------
local function NameWeapon(tip, returnTool)
    local function scan(container)
        if not container then return nil end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == tip then
                return returnTool and t or t.Name
            end
        end
        return nil
    end
    return scan(LocalPlayer.Backpack) or scan(Character)
end

---------------------------------------------------------------------------
-- 3. getBladeHits  (parts in radius around origin)
---------------------------------------------------------------------------
local function getBladeHits(originParts, radius)
    local hits = {}
    local origin = originParts[1] and originParts[1].Position
    if not origin then return hits end

    local function collect(container)
        for _, obj in ipairs(container:GetDescendants()) do
            if obj:IsA("BasePart") then
                if (obj.Position - origin).Magnitude <= radius then
                    table.insert(hits, obj)
                end
            end
        end
    end

    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        for _, model in ipairs(enemies:GetChildren()) do
            if model:FindFirstChild("HumanoidRootPart") then
                local hrp = model.HumanoidRootPart
                local playerFromChar = Players:GetPlayerFromCharacter(model)
                local r = playerFromChar and (radius / 1.5) or radius
                local checkPoints = { hrp.Position }
                if hrp.Size.Y > 5 then
                    table.insert(checkPoints, (hrp.CFrame * CFrame.new(0, (-hrp.Size.Y * 1.5) + 3, 0)).Position)
                end
                for _, pos in ipairs(checkPoints) do
                    if (pos - origin).Magnitude < (10 + r + hrp.Size.X / 2) then
                        for _, part in ipairs(model:GetDescendants()) do
                            if part:IsA("BasePart") then
                                table.insert(hits, part)
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    return hits
end

getgenv().getBladeHits = getBladeHits

---------------------------------------------------------------------------
-- 4. AttackAOE  → returns { {rig, hitPart}, ... } or nil
---------------------------------------------------------------------------
local function AttackAOE(radius, includeSelf)
    local char = Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        return nil
    end

    local origin = { char.HumanoidRootPart }
    local parts  = getBladeHits(origin, radius or 30)
    local results = {}
    local seen = {}

    for _, part in ipairs(parts) do
        local rig = CombatUtil:GetRigOfHitPart(part)
        if rig and CombatUtil:IsVulnerable(rig) and not seen[rig] then
            if includeSelf or rig \~= char then
                table.insert(results, { rig, part })
                seen[rig] = true
            end
        end
    end

    if #results > 0 then
        return results
    end
    return nil
end

---------------------------------------------------------------------------
-- 5. attackMelee  (WITH animation – uses CombatUtil moveset)
---------------------------------------------------------------------------
local function attackMelee(radius)
    local tool = Character and Character:FindFirstChildOfClass("Tool")
    if not tool then return end

    if not AttackAOE(radius or 30, false) then return end

    local hum = Character:FindFirstChildOfClass("Humanoid")
    if not hum or not hum.RootPart then return end

    local animCache = CombatUtil:GetMovesetAnimCache(hum)
    if not animCache then return end

    local weaponName = CombatUtil:GetWeaponName(tool)
    local weaponData = CombatUtil:GetWeaponData(weaponName)
    if not weaponData then return end

    local weaponType = weaponData.WeaponType
    local moveset    = weaponData.Moveset
    if not CombatUtil:CanAttack(hum.RootPart.Parent, weaponType) then return end

    comboIndex = comboIndex + 1
    if comboIndex > #moveset.Basic then
        comboIndex = 1
    end

    local pureName = CombatUtil:GetPureWeaponName(weaponName)
    local animKey  = pureName .. "-basic" .. comboIndex
    local anim     = animCache[animKey]
    if not anim then return end

    local length = anim.Length
    local speed  = anim:GetAttribute("SpeedMult") or 1
    RegisterAttack:FireServer(length / speed)
end

---------------------------------------------------------------------------
-- 6. AttackFunction  (core – No Animation path preferred)
---------------------------------------------------------------------------
local function AttackFunction(radius)
    radius = radius or 30

    local stun = Character and Character:FindFirstChild("Stun")
    if stun and stun.Value \~= 0 then
        return
    end

    if Settings["Attack No Animation "] then
        local hits = AttackAOE(radius, false)
        if not hits or #hits == 0 then return end

        RegisterAttack:FireServer(0)

        local primary = table.remove(hits, 1)
        local primaryPart = primary[2]
        RegisterHit:FireServer(primaryPart, hits)

        table.clear(hits)
    else
        attackMelee(radius)
    end
end

local function AttackFunctionnhungSuperTrial()
    local stun = Character and Character:FindFirstChild("Stun")
    if stun and stun.Value \~= 0 then return end

    local hits = AttackAOE(80, true)
    if not hits then return end

    RegisterAttack:FireServer(0)
    local primary = table.remove(hits, 1)
    RegisterHit:FireServer(primary[2], hits)
    table.clear(hits)
end

getgenv().AttackFunctionnhungSuperTrial = AttackFunctionnhungSuperTrial
getgenv().AttackFunctionnhungSuper     = AttackFunctionnhungSuperTrial

---------------------------------------------------------------------------
-- 7. UseFruitM1  (Blox Fruit left-click / TAP)
---------------------------------------------------------------------------
local function UseFruitM1(target, boatMode)
    local char = Character
    if not char then return false end

    local root = char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if not target then return false end

    local targetPos
    if typeof(target) == "Vector3" then
        targetPos = target
    elseif target.PrimaryPart then
        targetPos = target.PrimaryPart.Position
    elseif target:IsA("BasePart") then
        targetPos = target.Position
    else
        return false
    end

    local dir = (targetPos - root.Position).Unit
    local mouseFlat = ((MouseModule.Hit.Position - root.Position) * Vector3.new(1, 0, 1)).Unit

    local fruitName = NameWeapon("Blox Fruit")
    if not fruitName then return false end

    local tool = char:FindFirstChild(fruitName)
    if not tool then return false end

    local leftClick = tool:FindFirstChild("LeftClickRemote")
    local rf        = tool:FindFirstChild("RemoteFunction")
    local re        = tool:FindFirstChild("RemoteEvent")

    if fruitName == "Mammoth-Mammoth" and leftClick then
        leftClick:FireServer(targetPos)
        return true
    end

    if leftClick then
        fruitClickId = fruitClickId + 1
        if fruitClickId > 5 then fruitClickId = 1 end

        leftClick:FireServer(dir, fruitClickId)
        if boatMode then
            leftClick:FireServer(mouseFlat, fruitClickId)
        end
        return true
    end

    if rf then
        if re then
            re:FireServer(targetPos)
        end
        rf:InvokeServer("TAP")
        return true
    end

    return false
end

getgenv().UseFruitM1     = function(t, _) return UseFruitM1(t, false) end
getgenv().UseFruitM1Boat = function(t, _) return UseFruitM1(t, true)  end

---------------------------------------------------------------------------
-- 8. Gun: ShootM1 / SpamGunSkullGuitar / SpamGunDragonStorm
---------------------------------------------------------------------------
local function ShootM1(target)
    local tool = Character and Character:FindFirstChildOfClass("Tool")
    if not tool then return end
    if CombatUtil:IsGunReloading(tool) then return end

    local pos = (typeof(target) == "Instance" and target:IsA("BasePart") and target.Position)
             or (typeof(target) == "Instance" and target.PrimaryPart and target.PrimaryPart.Position)
             or (typeof(target) == "Vector3" and target)
             or (typeof(target) == "CFrame" and target.Position)

    if not pos then return end
    local re = tool:FindFirstChild("RemoteEvent")
    if re then
        re:FireServer("TAP", pos)
    end
end

local function SpamGunSkullGuitar(cframeOrPos)
    local char = Character
    if not char then return end
    local tool = char:FindFirstChild("Skull Guitar")
    if not tool then return end
    if CombatUtil:IsGunReloading(tool) then return end

    local pos = typeof(cframeOrPos) == "CFrame" and cframeOrPos.Position
             or typeof(cframeOrPos) == "Vector3" and cframeOrPos
             or (cframeOrPos and cframeOrPos.Position)

    if pos and tool:FindFirstChild("RemoteEvent") then
        tool.RemoteEvent:FireServer("TAP", pos)
    end
end

local function SpamGunDragonStorm(targetPart)
    local char = Character
    if not char then return end
    local tool = char:FindFirstChild("Dragonstorm")
    if not tool then return end
    if CombatUtil:IsGunReloading(tool) then return end

    local pos = targetPart and (targetPart.Position or (targetPart.PrimaryPart and targetPart.PrimaryPart.Position))
    if pos and tool:FindFirstChild("RemoteEvent") then
        tool.RemoteEvent:FireServer("TAP", pos)
    end
end

getgenv().SpamGunSkullGuitar  = SpamGunSkullGuitar
getgenv().SpamGunDragonStorm  = SpamGunDragonStorm

---------------------------------------------------------------------------
-- 9. ClickM1  – unified entry (weapon / fruit)
---------------------------------------------------------------------------
local function isNear(target, maxDist)
    maxDist = maxDist or 70
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return false end
    if not target or not target:FindFirstChild("HumanoidRootPart") then return false end
    if not target:FindFirstChild("Humanoid") or target.Humanoid.Health <= 0 then return false end
    return (Character.HumanoidRootPart.Position - target.HumanoidRootPart.Position).Magnitude < maxDist
end

local function ClickM1(target, bigHit)
    if not isNear(target) then return end

    local weapon = Settings["Select Weapon"] or "Melee"

    if weapon \~= "Blox Fruit" then
        AttackFunction(bigHit and 80 or 30)
    else
        UseFruitM1(target, false)
    end
end

getgenv().ClickM1 = ClickM1

getgenv().ClickM1Dungeon = function(target, bigHit)
    if not isNear(target) then return end
    local w = Settings["Select Weapon Dungeon"] or Settings["Select Weapon"] or "Melee"
    if w \~= "Blox Fruit" then
        AttackFunction(bigHit and 80 or 30)
    else
        UseFruitM1(target, false)
    end
end

getgenv().ClickM1Volcano = function(target, bigHit)
    if not isNear(target) then return end
    local w = Settings["Select Weapon Kill Golem"] or Settings["Select Weapon"] or "Melee"
    if w \~= "Blox Fruit" then
        AttackFunction(bigHit and 80 or 30)
    else
        UseFruitM1(target, false)
    end
end

---------------------------------------------------------------------------
-- 10. UsedualFlock – equip current Select Weapon
---------------------------------------------------------------------------
local function UsedualFlock()
    local tip = Settings["Select Weapon"] or "Melee"
    local name = NameWeapon(tip)
    if name then
        equiptool(name)
    end
end

---------------------------------------------------------------------------
-- 11. sizepart
---------------------------------------------------------------------------
local function sizepart(mob)
    if not mob or not mob:FindFirstChild("HumanoidRootPart") then return end
    local hrp = mob.HumanoidRootPart
    if not hrp:GetAttribute("OriginalSize") then
        hrp:SetAttribute("OriginalSize", hrp.Size)
    end
    pcall(function()
        hrp.Size = Vector3.new(60, 60, 60)
        hrp.Transparency = 1
        hrp.CanCollide = false
    end)
end

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
local Attack = {
    equiptool              = equiptool,
    NameWeapon             = NameWeapon,
    AttackAOE              = AttackAOE,
    AttackFunction         = AttackFunction,
    attackMelee            = attackMelee,
    AttackFunctionnhungSuperTrial = AttackFunctionnhungSuperTrial,
    UseFruitM1             = UseFruitM1,
    ShootM1                = ShootM1,
    SpamGunSkullGuitar     = SpamGunSkullGuitar,
    SpamGunDragonStorm     = SpamGunDragonStorm,
    ClickM1                = ClickM1,
    UsedualFlock           = UsedualFlock,
    sizepart               = sizepart,
    getBladeHits           = getBladeHits,
}

getgenv().AttackFunction = AttackFunction
getgenv().AttackAOE      = AttackAOE
getgenv().equiptool      = equiptool
getgenv().NameWeapon     = NameWeapon
getgenv().ShootM1        = ShootM1
getgenv().sizepart       = sizepart
getgenv().UsedualFlock   = UsedualFlock

-- Đồng bộ weapon từ dropdown Main tab
spawn(function()
    while task.wait(0.15) do
        pcall(function()
            if _G.ChooseWP then
                Settings["Select Weapon"] = _G.ChooseWP
            end
        end)
    end
end)

-- Attack luôn chạy ngầm
spawn(function()
    while task.wait() do
        pcall(function()
            AttackFunction(30)
        end)
    end
end)


Tabs.Settings:AddDropdown("SpeedTweenDropdown", {
    Title       = "Speed Tween",
    Values      = {"280", "325", "350"},
    Multi       = false,
    Default     = 1,
    Callback    = function(Value)
        getgenv().TweenSpeed = tonumber(Value)
    end
})
getgenv().TweenSpeed = 280

Tabs.Settings:AddDropdown("BoatSpeedDropdown", {
    Title       = "Speed Boats",
    Values      = {"280", "400", "450", "500", "550"},
    Multi       = false,
    Default     = 1,
    Callback    = function(Value)
        getgenv().BoatTweenSpeed = tonumber(Value)
    end
})
getgenv().BoatTweenSpeed = 280

--// ================= AUTO BUSO LOOP =================
-- Chạy liên tục: nếu Buso chưa bật thì bật, bật rồi thì thôi
spawn(function()
    while task.wait(1) do
        pcall(function()
            if getgenv().IsFarming then
                local char = player.Character
                local hasBuso1 = char and char:FindFirstChild("HasBuso")
                local hasBuso2 = char and char:FindFirstChild("Buso")
                if not hasBuso1 and not hasBuso2 then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
                end
            end
        end)
    end
end)

--// ================= AUTO RACE V3 =================
_G.AutoRaceV3 = false
Tabs.Settings:AddToggle("AutoRaceV3", {
    Title    = "Auto Active Race V3",
    Default  = false,
    Callback = function(v)
        _G.AutoRaceV3 = v
    end
})

spawn(function()
    while wait() do
        pcall(function()
            if _G.AutoRaceV3 then
                ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
            end
        end)
    end
end)

--// ================= AUTO RACE V4 =================
_G.AutoRaceV4 = false
Tabs.Settings:AddToggle("AutoRaceV4", {
    Title    = "Auto Active Race V4",
    Default  = false,
    Callback = function(v)
        _G.AutoRaceV4 = v
    end
})

spawn(function()
    while wait(0.2) do
        pcall(function()
            if _G.AutoRaceV4 then
                local raceEnergy = player.Character and player.Character:FindFirstChild("RaceEnergy")
                if raceEnergy and raceEnergy.Value == 1 then
                    VirtualInputManager:SendKeyEvent(true,  "Y", false, game)
                    wait()
                    VirtualInputManager:SendKeyEvent(false, "Y", false, game)
                end
            end
        end)
    end
end)

--// ===================================================================
--//              SEA EVENT: CONSTANTS & DATA
--// ===================================================================

-- Vị trí điểm mua thuyền (cố định trên map)
local BUY_BOAT_CFRAME = CFrame.new(-16927.451, 12, 433.864)

-- CFrame các vùng biển
local SEA_ZONE_CFRAMES = {
    ["Lv 1"]        = CFrame.new(-21998.375,  35, -682.309143),
    ["Lv 2"]        = CFrame.new(-26779.5215, 35, -822.858032),
    ["Lv 3"]        = CFrame.new(-31171.957,  35, -2256.93774),
    ["Lv 4"]        = CFrame.new(-34054.6875, 35, -2560.12012),
    ["Lv 5"]        = CFrame.new(-38887.5547, 35, -2162.99023),
    ["Lv 6"]        = CFrame.new(-44541.7617, 35, -1244.8584),
    ["Lv Infinite"] = CFrame.new(-10000000,   35,  37016.25),
}

-- Map toggle genv → thông tin mob
-- isBoat = true  → kiểm tra b.Health + b.VehicleSeat, dùng b.Engine làm root
-- isSeaBeast = true → tìm trong workspace.SeaBeasts, kiểm tra b.Health.Value
local SEA_MOB_MAP = {
    AutoSharkEnabled       = { names = {"Shark"},                                folder = "Enemies"   },
    AutoPiranhaEnabled     = { names = {"Piranha"},                              folder = "Enemies"   },
    AutoTerrorSharkEnabled = { names = {"Terrorshark"},                          folder = "Enemies"   },
    AutoFishCrewEnabled    = { names = {"Fish Crew Member"},                     folder = "Enemies"   },
    AutoHauntedCrewEnabled = { names = {"Haunted Crew Member"},                  folder = "Enemies"   },
    AutoPirateGrandEnabled = { names = {"PirateGrandBrigade","PirateBrigade"},   folder = "Enemies",   isBoat = true },
    AutoFishBoatEnabled    = { names = {"FishBoat"},                             folder = "Enemies",   isBoat = true },
    AutoSeaBeastEnabled    = { names = {"SeaBeast1","SeaBeast"},                 folder = "SeaBeasts", isSeaBeast = true },
}

--// ===================================================================
--//              SEA EVENT: UTILITY FUNCTIONS
--// ===================================================================

-- ─── Noclip ───────────────────────────────────────────────────────────
local noclipConn = nil
local function SetNoclip(enabled)
    if enabled then
        if noclipConn then return end
        noclipConn = RunService.Stepped:Connect(function()
            local char = player.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
    else
        if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    end
end

-- ─── BodyVelocity (giữ player lơ lửng – force re-set mỗi Heartbeat) ──
--    MaxForce trên Y = math.huge → chống rơi
--    MaxForce trên X,Z = 0       → tween vẫn di chuyển được
local bvLoopConn = nil
local function SetBodyVelocity(enabled)
    if enabled then
        if bvLoopConn then return end
        bvLoopConn = RunService.Heartbeat:Connect(function()
            local char = player.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local bv = hrp:FindFirstChild("SeaFarmBV")
            if not bv then
                bv        = Instance.new("BodyVelocity")
                bv.Name   = "SeaFarmBV"
                bv.Parent = hrp
            end
            -- Force re-set mỗi tick để tránh bị game override hoặc destroy âm thầm
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.MaxForce = Vector3.new(0, math.huge, 0)
            bv.P        = 9999
        end)
    else
        if bvLoopConn then bvLoopConn:Disconnect() bvLoopConn = nil end
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bv = hrp:FindFirstChild("SeaFarmBV")
                if bv then bv:Destroy() end
            end
        end
    end
end

-- ─── Trang bị weapon theo tên ─────────────────────────────────────────
local function EquipWeapon(weaponName)
    if not weaponName then return end
    local char = player.Character
    if not char then return end
    -- Nếu đã trang bị rồi thì bỏ qua
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and equipped.Name == weaponName then return end
    -- Tìm trong backpack
    local tool = player.Backpack:FindFirstChild(weaponName)
    if tool then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum:EquipTool(tool) end
    end
end

-- ─── Weapon loop (dùng Heartbeat để bám sát, dừng khi stopFn() = true) ─
local weaponLoopConn = nil
local function StartWeaponLoop(getWeaponFn)
    if weaponLoopConn then weaponLoopConn:Disconnect() weaponLoopConn = nil end
    local lastEquip = 0
    weaponLoopConn = RunService.Heartbeat:Connect(function()
        if (tick() - lastEquip) < 0.15 then return end
        lastEquip = tick()
        pcall(function()
            local wName = getWeaponFn()
            if wName then EquipWeapon(wName) end
        end)
    end)
end

local function StopWeaponLoop()
    if weaponLoopConn then weaponLoopConn:Disconnect() weaponLoopConn = nil end
end

-- Mob nào dùng weapon từ dropdown (melee/sword/gun/fruit)
local SEA_MELEE_MOB_NAMES = {
    ["Shark"]               = true,
    ["Piranha"]             = true,
    ["TerrorShark"]         = true,
    ["FishCrewMember"]      = true,
    ["HauntedCrewMember"]   = true,
}
-- Mob nào dùng Blox Fruit (nếu toggle AutoM1Fruit bật)
local SEA_FRUIT_MOB_NAMES = {
    ["FishBoat"]            = true,
    ["PirateBrigade"]       = true,
    ["PirateGrandBrigade"]  = true,
    ["SeaBeast"]            = true,
}

-- ─── Lấy tên weapon cần equip cho mob ─────────────────────────────────
local function GetWeaponForMob(genvKey)
    local data = SEA_MOB_MAP[genvKey]
    if not data then return nil end
    -- Sea beast hoặc boat + Auto M1 Fruit bật → Blox Fruit
    if (data.isSeaBeast or data.isBoat) and getgenv().AutoM1FruitEnabled then
        -- Tìm Blox Fruit trong backpack
        local char = player.Character
        if char then
            for _, v in ipairs(player.Backpack:GetChildren()) do
                if v.ToolTip == "Blox Fruit" then return v.Name end
            end
            -- Có thể đã equipped
            local eq = char:FindFirstChildOfClass("Tool")
            if eq and eq.ToolTip == "Blox Fruit" then return eq.Name end
        end
        return nil
    end
    -- Các mob melee (Shark, Piranha...) → dùng _G.SelectWeapon từ dropdown
    if SEA_MELEE_MOB_NAMES[genvKey] or
       (data and not data.isBoat and not data.isSeaBeast) then
        return _G.SelectWeapon
    end
    return nil
end

local function FindBloxFruitName()
    local char = player.Character
    if char then
        local eq = char:FindFirstChildOfClass("Tool")
        if eq and eq.ToolTip == "Blox Fruit" then return eq.Name end
    end
    for _, v in ipairs(player.Backpack:GetChildren()) do
        if v.ToolTip == "Blox Fruit" then return v.Name end
    end
    return nil
end

-- ─── vim1 alias + weaponSc ────────────────────────────────────────────
local vim1 = VirtualInputManager

-- Trang bị weapon theo ToolTip
local function weaponSc(tooltip)
    local char = player.Character
    if not char then return end
    local eq = char:FindFirstChildOfClass("Tool")
    if eq and eq.ToolTip == tooltip then return end -- đã đúng
    for _, v in ipairs(player.Backpack:GetChildren()) do
        if v.ToolTip == tooltip then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(v) end
            return
        end
    end
end

-- ─── Useskills: trang bị + bấm skill ────────────────────────────────
local function Useskills(weapon, skill)
    if weapon == "Melee" then
        weaponSc("Melee")
        if skill == "Z" then
            vim1:SendKeyEvent(true,  "Z", false, game)
            vim1:SendKeyEvent(false, "Z", false, game)
        elseif skill == "X" then
            vim1:SendKeyEvent(true,  "X", false, game)
            vim1:SendKeyEvent(false, "X", false, game)
        elseif skill == "C" then
            vim1:SendKeyEvent(true,  "C", false, game)
            vim1:SendKeyEvent(false, "C", false, game)
        end
    elseif weapon == "Sword" then
        weaponSc("Sword")
        if skill == "Z" then
            vim1:SendKeyEvent(true,  "Z", false, game)
            vim1:SendKeyEvent(false, "Z", false, game)
        elseif skill == "X" then
            vim1:SendKeyEvent(true,  "X", false, game)
            vim1:SendKeyEvent(false, "X", false, game)
        end
    elseif weapon == "Blox Fruit" then
        weaponSc("Blox Fruit")
        if skill == "Z" then
            vim1:SendKeyEvent(true,  "Z", false, game)
            vim1:SendKeyEvent(false, "Z", false, game)
        elseif skill == "X" then
            vim1:SendKeyEvent(true,  "X", false, game)
            vim1:SendKeyEvent(false, "X", false, game)
        elseif skill == "C" then
            vim1:SendKeyEvent(true,  "C", false, game)
            vim1:SendKeyEvent(false, "C", false, game)
        end
    elseif weapon == "Gun" then
        weaponSc("Gun")
        if skill == "Z" then
            vim1:SendKeyEvent(true,  "Z", false, game)
            vim1:SendKeyEvent(false, "Z", false, game)
        elseif skill == "X" then
            vim1:SendKeyEvent(true,  "X", false, game)
            vim1:SendKeyEvent(false, "X", false, game)
        end
    end
end

-- Skill list theo từng weapon (spam tuần tự không delay)
local WEAPON_SKILLS = {
    ["Melee"]      = {"Z", "X", "C"},
    ["Sword"]      = {"Z", "X"},
    ["Blox Fruit"] = {"Z", "X", "C"},
    ["Gun"]        = {"Z", "X"},
}
local WEAPON_TYPES = {"Melee", "Sword", "Blox Fruit", "Gun"}

-- ─── Skill Spam Loop cho sea beast / boat (không bật Auto M1 Fruit) ───
-- Cứ 2s đổi weapon ngẫu nhiên (không lặp weapon trước), spam skill liên tục
local skillSpamThread = nil
local function StartSkillSpamLoop(stopFn)
    if skillSpamThread then
        task.cancel(skillSpamThread)
        skillSpamThread = nil
    end
    skillSpamThread = task.spawn(function()
        local prevWeapon = nil
        while not stopFn() do
            if getgenv().AutoM1FruitEnabled then
                -- Chỉ loop Blox Fruit, không spam skill
                weaponSc("Blox Fruit")
                task.wait(0.1)
            else
                -- Chọn weapon ngẫu nhiên, không lặp weapon trước
                local available = {}
                for _, w in ipairs(WEAPON_TYPES) do
                    if w ~= prevWeapon then
                        table.insert(available, w)
                    end
                end
                local chosenWeapon = available[math.random(#available)]
                prevWeapon = chosenWeapon
                local skills = WEAPON_SKILLS[chosenWeapon]

                -- Dùng weapon này trong 0.3s, spam skill mỗi 0.1s
                local deadline = tick() + 0.3
                local si = 1
                while not stopFn() and tick() < deadline do
                    if getgenv().AutoM1FruitEnabled then break end
                    local sk = skills[si]
                    pcall(Useskills, chosenWeapon, sk)
                    si = (si % #skills) + 1
                    task.wait(0.1)
                end
            end
        end
    end)
end

local function StopSkillSpamLoop()
    if skillSpamThread then
        task.cancel(skillSpamThread)
        skillSpamThread = nil
    end
end

-- ─── Weapon selection loop (cập nhật _G.SelectWeapon liên tục) ────────
local Sec = 0.15
spawn(function()
    while task.wait(Sec) do
        pcall(function()
            local tooltip = _G.ChooseWP
            if not tooltip then return end
            for _, v in ipairs(player.Backpack:GetChildren()) do
                if v.ToolTip == tooltip then
                    _G.SelectWeapon = v.Name
                    break
                end
            end
        end)
    end
end)
local function GetBoatRoot(boat)
    if not boat then return nil end
    return boat:FindFirstChild("Engine")
        or boat.PrimaryPart
        or boat:FindFirstChildWhichIsA("VehicleSeat", true)
end

-- ─── Noclip thuyền (loop Stepped) ────────────────────────────────────
local boatNoclipConn = nil
local function SetBoatNoclip(boat, enabled)
    if enabled then
        if boatNoclipConn then boatNoclipConn:Disconnect() boatNoclipConn = nil end
        boatNoclipConn = RunService.Stepped:Connect(function()
            if not boat or not boat.Parent then
                boatNoclipConn:Disconnect() boatNoclipConn = nil
                return
            end
            for _, p in ipairs(boat:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    else
        if boatNoclipConn then boatNoclipConn:Disconnect() boatNoclipConn = nil end
    end
end

-- ─── BodyVelocity trên thuyền (chống chìm khi tween) ─────────────────
local boatBvConn = nil
local function SetBoatBodyVelocity(boat, enabled)
    if enabled then
        if boatBvConn then boatBvConn:Disconnect() boatBvConn = nil end
        boatBvConn = RunService.Heartbeat:Connect(function()
            if not boat or not boat.Parent then
                boatBvConn:Disconnect() boatBvConn = nil
                return
            end
            local root = GetBoatRoot(boat)
            if not root then return end
            local bv = root:FindFirstChild("SeaBoatBV")
            if not bv then
                bv           = Instance.new("BodyVelocity")
                bv.Name      = "SeaBoatBV"
                bv.Velocity  = Vector3.new(0, 0, 0)
                bv.MaxForce  = Vector3.new(0, math.huge, 0)
                bv.P         = 9999
                bv.Parent    = root
            end
        end)
    else
        if boatBvConn then boatBvConn:Disconnect() boatBvConn = nil end
        if boat and boat.Parent then
            local root = GetBoatRoot(boat)
            if root then
                local bv = root:FindFirstChild("SeaBoatBV")
                if bv then bv:Destroy() end
            end
        end
    end
end

-- ─── Tween THUYỀN tới CFrame dùng Heartbeat PivotTo + BV + Noclip ───
-- PivotTo toàn bộ model mỗi Heartbeat (mượt, không bị override bởi physics)
local activeBoatTweenConn = nil
local boatTweenRunning    = false

local function TweenBoatTo(boat, targetCF, callback)
    boatTweenRunning = false
    if activeBoatTweenConn then
        activeBoatTweenConn:Disconnect()
        activeBoatTweenConn = nil
    end

    if not boat or not boat.Parent then
        if callback then callback() end return
    end

    -- Bật BV + Noclip trước khi tween
    SetBoatNoclip(boat, true)
    SetBoatBodyVelocity(boat, true)

    local startCF   = boat:GetPivot()
    local dist      = (startCF.Position - targetCF.Position).Magnitude
    local speed     = getgenv().BoatTweenSpeed or 280
    local duration  = math.max(0.05, dist / speed)
    local startTime = tick()

    boatTweenRunning = true
    activeBoatTweenConn = RunService.Heartbeat:Connect(function()
        if not boatTweenRunning or not boat or not boat.Parent then
            if activeBoatTweenConn then
                activeBoatTweenConn:Disconnect()
                activeBoatTweenConn = nil
            end
            return
        end
        local alpha  = math.clamp((tick() - startTime) / duration, 0, 1)
        local newCF  = startCF:Lerp(targetCF, alpha)
        pcall(function() boat:PivotTo(newCF) end)
        if alpha >= 1 then
            boatTweenRunning = false
            activeBoatTweenConn:Disconnect()
            activeBoatTweenConn = nil
            if callback then callback() end
        end
    end)
end

local function TweenBoatToSync(boat, targetCF)
    local done = false
    TweenBoatTo(boat, targetCF, function() done = true end)
    while not done and boatTweenRunning do task.wait() end
end

local function CancelBoatTween()
    boatTweenRunning = false
    if activeBoatTweenConn then
        activeBoatTweenConn:Disconnect()
        activeBoatTweenConn = nil
    end
end

-- ─── Safe Boat: tween thuyền lên Y=500, quay vòng quanh player ────────
-- Kích hoạt chỉ khi đang farm mob + toggle SafeBoat bật
-- Dùng PivotTo mỗi Heartbeat → không cần player ngồi trên thuyền
local safeBoatConn    = nil
local safeBoatRunning = false

local SAFE_BOAT_Y      = 500   -- độ cao thuyền an toàn
local SAFE_BOAT_RADIUS = 500   -- bán kính vòng tròn quanh player (stud)
local SAFE_BOAT_SPEED  = 0.5   -- rad/s (~12.5s một vòng, tốc độ cố định)

local function StartSafeBoat(boat)
    -- Dừng orbit cũ nếu có
    if safeBoatConn then safeBoatConn:Disconnect() safeBoatConn = nil end
    safeBoatRunning = false

    if not boat or not boat.Parent then return end
    if not getgenv().SafeBoatEnabled then return end

    -- Bật noclip + BV cho thuyền để tween xuyên địa hình
    SetBoatNoclip(boat, true)
    SetBoatBodyVelocity(boat, true)

    -- Phase 1: Tween thuyền lên Y = SAFE_BOAT_Y (500) trước khi quay
    local currentPivot = boat:GetPivot()
    local upCF = CFrame.new(currentPivot.Position.X, SAFE_BOAT_Y, currentPivot.Position.Z)
    TweenBoatToSync(boat, upCF)

    -- Kiểm tra lại sau tween (có thể bị cancel / toggle tắt)
    if not getgenv().SafeBoatEnabled or not boat or not boat.Parent then return end

    -- Phase 2: Quay tròn quanh player với bán kính SAFE_BOAT_RADIUS ở độ cao SAFE_BOAT_Y
    safeBoatRunning = true
    safeBoatConn = RunService.Heartbeat:Connect(function()
        if not safeBoatRunning or not boat or not boat.Parent then
            if safeBoatConn then safeBoatConn:Disconnect() safeBoatConn = nil end
            return
        end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local angle  = tick() * ((getgenv().TweenSpeed or 300) / SAFE_BOAT_RADIUS)
        local newPos = Vector3.new(
            hrp.Position.X + math.cos(angle) * SAFE_BOAT_RADIUS,
            SAFE_BOAT_Y,
            hrp.Position.Z + math.sin(angle) * SAFE_BOAT_RADIUS
        )
        pcall(function() boat:PivotTo(CFrame.new(newPos)) end)
    end)
end

local function StopSafeBoat()
    safeBoatRunning = false
    if safeBoatConn then safeBoatConn:Disconnect() safeBoatConn = nil end
    -- Hủy tween thuyền (bao gồm cả phase tween lên Y=500 nếu đang chạy)
    CancelBoatTween()
end

-- ─── Tween tới CFrame (bay theo đường thẳng, speed = TweenSpeed stud/s) ─
local activeTween = nil
local function TweenTo(targetCF, callback)
    if activeTween then activeTween:Cancel() activeTween = nil end
    local char = player.Character
    if not char then if callback then callback() end return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then if callback then callback() end return end

    -- Bật BV để chống rơi trong suốt quá trình tween
    SetBodyVelocity(true)

    local dist     = (hrp.Position - targetCF.Position).Magnitude
    local speed    = getgenv().TweenSpeed or 300
    local duration = math.max(0.05, dist / speed)

    local tw = TweenService:Create(
        hrp,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        { CFrame = targetCF }
    )
    activeTween = tw
    tw:Play()
    tw.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed then
            activeTween = nil
            if callback then callback() end
        end
    end)
    return tw
end

-- Tween đồng bộ (yield) – BV tự bật bên trong TweenTo
local function TweenToSync(targetCF)
    local done = false
    TweenTo(targetCF, function() done = true end)
    while not done do task.wait() end
end

-- ─── Tìm thuyền đã chọn trong workspace.Boats ───────────────────────
local function GetNearestBoat()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local boatsFolder = workspace:FindFirstChild("Boats")
    if not boatsFolder then return nil end

    local boatName    = _G.SelectedBoat or "Guardian"
    local MAX_BOAT_RANGE = 3500
    local bestBoat, bestDist = nil, math.huge

    for _, boat in ipairs(boatsFolder:GetChildren()) do
        if boat.Name == boatName then
            local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
            if seat then
                local dist = (seat.Position - hrp.Position).Magnitude
                if dist < bestDist and dist <= MAX_BOAT_RANGE then
                    bestDist = dist
                    bestBoat = boat
                end
            end
        end
    end
    return bestBoat
end

-- ─── Kiểm tra player đang Sit ─────────────────────────────────────────
local function IsOnBoat()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    return hum and hum.Sit
end

-- ─── Ngồi lên thuyền ──────────────────────────────────────────────────
local function SitOnBoat(boat)
    if not boat then return false end
    local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
    if not seat then return false end
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    -- Tween ngay trên ghế
    TweenToSync(seat.CFrame * CFrame.new(0, 2.5, 0))
    task.wait(0.3)
    local hum = char:FindFirstChild("Humanoid")
    if hum then seat:Sit(hum) end
    task.wait(0.6)
    return IsOnBoat()
end

-- ─── Jump khỏi thuyền ─────────────────────────────────────────────────
local lastJumpTime = 0
local function PerformJump(bypass)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local now = tick()
    if not bypass and (now - lastJumpTime) < 1 then return end
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    lastJumpTime = now
end

-- ─── Reset player (HP = 0) ────────────────────────────────────────────
local function ResetPlayer()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if hum then hum.Health = 0 end
end

-- ─── Kiểm tra có toggle mob nào đang bật không ───────────────────────
local function IsAnyMobToggleOn()
    for genvKey in pairs(SEA_MOB_MAP) do
        if getgenv()[genvKey] then return true end
    end
    return false
end

-- ─── Tìm mob sea gần nhất đang bật toggle (trong 2000 stud) ──────────
local function FindNearestSeaMob()
    local char = player.Character
    if not char then return nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end

    local bestDist, bestMob, bestKey = math.huge, nil, nil

    for genvKey, data in pairs(SEA_MOB_MAP) do
        if getgenv()[genvKey] then
            local folder = workspace:FindFirstChild(data.folder)
            if folder then
                for _, mob in ipairs(folder:GetChildren()) do
                    -- Kiểm tra tên
                    local nameMatch = false
                    for _, n in ipairs(data.names) do
                        if mob.Name == n then nameMatch = true break end
                    end
                    if nameMatch then
                        -- Kiểm tra còn sống
                        local alive = false
                        local rootPos = nil
                        if data.isSeaBeast then
                            local hp = mob:FindFirstChild("Health")
                            alive = hp and hp.Value > 0
                            local rp = mob:FindFirstChild("HumanoidRootPart")
                            rootPos = rp and rp.Position
                        elseif data.isBoat then
                            local hp   = mob:FindFirstChild("Health")
                            local vs   = mob:FindFirstChild("VehicleSeat")
                            alive = hp and hp.Value > 0 and vs ~= nil
                            local eng = mob:FindFirstChild("Engine")
                            rootPos = eng and eng.Position
                        else
                            local hum = mob:FindFirstChild("Humanoid")
                            alive = hum and hum.Health > 0
                            local rp = mob:FindFirstChild("HumanoidRootPart")
                            rootPos = rp and rp.Position
                        end

                        if alive and rootPos then
                            local dist = (rootPos - hrp.Position).Magnitude
                            if dist <= 2000 and dist < bestDist then
                                bestDist = dist
                                bestMob  = mob
                                bestKey  = genvKey
                            end
                        end
                    end
                end
            end
        end
    end

    return bestMob, bestKey
end

-- ─── Kiểm tra mob còn sống ────────────────────────────────────────────
local function IsMobAlive(mob, genvKey)
    if not mob or not mob.Parent then return false end
    local data = SEA_MOB_MAP[genvKey]
    if not data then return false end
    if data.isSeaBeast then
        local hp = mob:FindFirstChild("Health")
        return hp and hp.Value > 0
    elseif data.isBoat then
        local hp = mob:FindFirstChild("Health")
        return hp and hp.Value > 0 and mob:FindFirstChild("VehicleSeat") ~= nil
    else
        local hum = mob:FindFirstChild("Humanoid")
        return hum and hum.Health > 0
    end
end

-- ─── Lấy vị trí root của mob ──────────────────────────────────────────
local function GetMobRootCFrame(mob, genvKey)
    local data = SEA_MOB_MAP[genvKey]
    if not data then return nil end
    if data.isBoat then
        local eng = mob:FindFirstChild("Engine")
        return eng and eng.CFrame
    else
        local rp = mob:FindFirstChild("HumanoidRootPart")
        return rp and rp.CFrame
    end
end

-- ─── Lấy CFrame farm chính xác theo từng loại mob ────────────────────
-- Boat mob dùng offset relative to Engine.CFrame
-- Regular mob: Y + 10, Sea beast: Y + 200
local function GetMobFarmCFrame(mob, genvKey)
    local data = SEA_MOB_MAP[genvKey]
    if not data then return nil end

    if data.isBoat then
        local eng = mob:FindFirstChild("Engine")
        if not eng then return nil end
        if mob.Name == "PirateGrandBrigade" or mob.Name == "PirateBrigade" then
            -- PirateBrigade/PirateGrandBrigade: bám phía sau-dưới Engine
            local offset = (mob.Name == "PirateGrandBrigade")
                and CFrame.new(0, -50, -50)
                or  CFrame.new(0, -30, -10)
            return eng.CFrame * offset
        elseif mob.Name == "FishBoat" then
            return eng.CFrame * CFrame.new(0, -50, -25)
        else
            -- Boat khác: đứng trên Engine
            return eng.CFrame * CFrame.new(0, 5, 0)
        end
    elseif data.isSeaBeast then
        local rp = mob:FindFirstChild("HumanoidRootPart")
        if not rp then return nil end
        -- Y = 35 tuyệt đối (mặt nước), X/Z bám theo sea beast
        return CFrame.new(rp.Position.X, 35, rp.Position.Z)
    else
        local rp = mob:FindFirstChild("HumanoidRootPart")
        if not rp then return nil end
        local wp = _G.ChooseWP or "Melee"
        local yOff
        if wp == "Melee" or wp == "Sword" then
            yOff = 40
        elseif wp == "Blox Fruit" then
            yOff = 15
        else
            yOff = 70  -- Gun
        end
        return CFrame.new(rp.Position.X, rp.Position.Y + yOff, rp.Position.Z)
    end
end

--// ===================================================================
--//              SEA EVENT: MAIN STATE MACHINE
--// ===================================================================

-- Khởi tạo các genv
getgenv().AutoSailEnabled        = false
getgenv().AutoSharkEnabled       = false
getgenv().AutoPiranhaEnabled     = false
getgenv().AutoTerrorSharkEnabled = false
getgenv().AutoFishCrewEnabled    = false
getgenv().AutoHauntedCrewEnabled = false
getgenv().AutoPirateGrandEnabled = false
getgenv().AutoFishBoatEnabled    = false
getgenv().AutoSeaBeastEnabled    = false
getgenv().AutoMutiFarmSeaEnabled = false

_G.SelectedBoat  = "Guardian"
_G.DangerSc      = "Lv 1"
_G.MutiSeaTarget = nil

local seaFarmRunning = false
local seaFarmThread  = nil

local function StopSeaFarm()
    seaFarmRunning = false
    if seaFarmThread then task.cancel(seaFarmThread) seaFarmThread = nil end
    SetNoclip(false)
    SetBodyVelocity(false)
    StopWeaponLoop()
    StopSkillSpamLoop()
    StopSafeBoat()
    if activeTween then activeTween:Cancel() activeTween = nil end
    CancelBoatTween()
    if boatNoclipConn then boatNoclipConn:Disconnect() boatNoclipConn = nil end
    if boatBvConn then boatBvConn:Disconnect() boatBvConn = nil end
end

--// ===================================================================
--//     [MUTI FARM SEA] HELPERS – săn cùng bạn bè
--// ===================================================================

-- ─── Tìm thuyền bạn bè đang lái ──────────────────────────────────────
local function GetFriendBoatForSea()
    local friendName = _G.MutiSeaTarget
    if not friendName or friendName == "(Không có player)" then return nil end
    local boatsFolder = workspace:FindFirstChild("Boats")
    if not boatsFolder then return nil end
    local friendPlr = Players:FindFirstChild(friendName)
    if not friendPlr then return nil end

    -- Ưu tiên: bạn đang ngồi VehicleSeat của thuyền nào
    for _, boat in ipairs(boatsFolder:GetChildren()) do
        local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
        if seat and seat.Occupant then
            if seat.Occupant.Parent and seat.Occupant.Parent.Name == friendName then
                return boat
            end
        end
    end

    -- Fallback: thuyền gần nhất trong 500 stud so với bạn
    local friendChar = friendPlr.Character
    if friendChar then
        local friendHRP = friendChar:FindFirstChild("HumanoidRootPart")
        if friendHRP then
            local best, bestDist = nil, math.huge
            for _, boat in ipairs(boatsFolder:GetChildren()) do
                local root = GetBoatRoot(boat)
                if root then
                    local d = (root.Position - friendHRP.Position).Magnitude
                    if d < bestDist and d < 500 then
                        bestDist = d
                        best     = boat
                    end
                end
            end
            return best
        end
    end
    return nil
end

-- ─── Lấy danh sách pháo (cannon) trên thuyền ─────────────────────────
local function GetSeaCannonSeats(boat)
    local cannons = {}
    if not boat then return cannons end
    for _, child in ipairs(boat:GetChildren()) do
        local n = child.Name:lower()
        if n:find("cannon") and not n:find("harpoon") and not n:find("heart") then
            table.insert(cannons, child)
        end
    end
    return cannons
end

-- ─── Lấy BasePart đại diện của pháo ──────────────────────────────────
local function GetSeaCannonPart(cannon)
    if not cannon then return nil end
    if cannon:IsA("BasePart") then return cannon end
    local seat = cannon:FindFirstChildWhichIsA("VehicleSeat", true)
               or cannon:FindFirstChildWhichIsA("Seat", true)
    if seat then return seat end
    if cannon.PrimaryPart then return cannon.PrimaryPart end
    return cannon:FindFirstChildWhichIsA("BasePart", true)
end

-- ─── Kiểm tra pháo có người ngồi chưa ───────────────────────────────
local function IsSeaCannonOccupied(cannon)
    if not cannon or not cannon.Parent then return true end
    local part = GetSeaCannonPart(cannon)
    if not part then return true end
    if part:IsA("Seat") or part:IsA("VehicleSeat") then
        return part.Occupant ~= nil
    end
    local pos = part.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - pos).Magnitude < 8 then
                return true
            end
        end
    end
    return false
end

-- ─── Tìm pháo trống đầu tiên trên thuyền ────────────────────────────
local function FindEmptySeaCannon(boat)
    for _, cannon in ipairs(GetSeaCannonSeats(boat)) do
        if not IsSeaCannonOccupied(cannon) then return cannon end
    end
    return nil
end

-- ─── Tween tới pháo bạn bè và ngồi vào, hủy tween+BV sau khi ngồi ───
local function SitOnFriendCannon(boat)
    if not boat then return false end
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return false end

    -- Nếu đã đang ngồi rồi thì không làm gì thêm (tránh tween văng ra khỏi pháo)
    if hum.Sit then
        if activeTween then activeTween:Cancel() activeTween = nil end
        SetNoclip(false)
        SetBodyVelocity(false)
        StopWeaponLoop()
        StopSkillSpamLoop()
        return true
    end

    -- Thử tìm pháo (cannon)
    local cannon = FindEmptySeaCannon(boat)
    local part

    if cannon then
        part = GetSeaCannonPart(cannon)
    end

    -- Fallback: dùng VehicleSeat nếu không có pháo
    if not part then
        part = boat:FindFirstChildWhichIsA("VehicleSeat", true)
    end
    if not part then return false end

    -- Tween tới pháo
    SetNoclip(true)
    SetBodyVelocity(false)
    TweenToSync(part.CFrame * CFrame.new(0, 3, 0))
    task.wait(0.2)

    -- Ngồi nếu là Seat/VehicleSeat
    if part:IsA("Seat") or part:IsA("VehicleSeat") then
        if not part.Occupant then
            pcall(function() part:Sit(hum) end)
            task.wait(0.8)  -- đợi đủ lâu để Humanoid.Sit = true sync về client
        end
    end

    -- Hủy TOÀN BỘ tween + BV + noclip + weapon/skill loop sau khi ngồi
    if activeTween then activeTween:Cancel() activeTween = nil end
    SetNoclip(false)
    SetBodyVelocity(false)
    StopWeaponLoop()
    StopSkillSpamLoop()

    local h = player.Character and player.Character:FindFirstChild("Humanoid")
    local hrpNow = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return (h and h.Sit)
        or (hrpNow and (hrpNow.Position - part.Position).Magnitude < 12)
end

-- ─── Vòng lặp chính ───────────────────────────────────────────────────
local function SeaFarmLoop()
    seaFarmRunning = true
    SetNoclip(true)
    SetBodyVelocity(true)

    while seaFarmRunning do
        -- Kiểm tra cần tiếp tục không
        if not getgenv().AutoSailEnabled and not IsAnyMobToggleOn() then
            StopSeaFarm()
            break
        end

        local ok, err = pcall(function()
            local char = player.Character
            if not char then task.wait(1) return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(1) return end

            local autoSail     = getgenv().AutoSailEnabled
            local anyMobToggle = IsAnyMobToggleOn()
            local mutiSea      = getgenv().AutoMutiFarmSeaEnabled

            -- Không có gì bật → đứng yên
            if not autoSail and not anyMobToggle then
                task.wait(0.5)
                return
            end

            -- ══════════════════════════════════════════════════════════
            -- CHẾ ĐỘ MUTI FARM SEA (AutoSail + AutoMutiFarmSea):
            -- Ngồi trên pháo thuyền bạn bè, bạn lái, mình farm mob.
            -- Hết mob → tween về pháo bạn lại.
            -- ══════════════════════════════════════════════════════════
            if autoSail and mutiSea then
                local friendBoat = GetFriendBoatForSea()
                if not friendBoat then
                    task.wait(1)
                    return
                end

                -- Kiểm tra đã ngồi trên pháo chưa
                local humNow = char:FindFirstChild("Humanoid")
                local alreadySat = humNow and humNow.Sit
                if not alreadySat then
                    SitOnFriendCannon(friendBoat)
                    task.wait(1.5)  -- đợi Humanoid.Sit sync đủ trước khi loop lại
                    return
                end

                -- Đã ngồi → farm mob
                if anyMobToggle then
                    local mob, genvKey = FindNearestSeaMob()
                    if mob then
                        -- Có mob → nhảy ra farm
                        PerformJump(true)
                        task.wait(0.5)
                        SetNoclip(true)
                        SetBodyVelocity(true)

                        local data = SEA_MOB_MAP[genvKey]
                        local isBoatOrBeast = data and (data.isBoat or data.isSeaBeast)

                        if isBoatOrBeast then
                            local alive = true
                            StartSkillSpamLoop(function()
                                return not (seaFarmRunning and alive and mutiSea)
                            end)
                            local timeout = 0
                            while seaFarmRunning and IsMobAlive(mob, genvKey) and mutiSea do
                                local tgtCF = GetMobFarmCFrame(mob, genvKey)
                                if tgtCF then TweenTo(tgtCF) end
                                task.wait(0.1)
                                timeout += 0.1
                                if timeout > 60 then break end
                            end
                            alive = false
                            StopSkillSpamLoop()
                        else
                            StartWeaponLoop(function() return GetWeaponForMob(genvKey) end)
                            local timeout = 0
                            while seaFarmRunning and IsMobAlive(mob, genvKey) and mutiSea do
                                local tgtCF = GetMobFarmCFrame(mob, genvKey)
                                if tgtCF then TweenTo(tgtCF) end
                                task.wait(0.1)
                                timeout += 0.1
                                if timeout > 60 then break end
                            end
                            StopWeaponLoop()
                        end

                        -- Hết mob → tween về pháo bạn
                        if activeTween then activeTween:Cancel() activeTween = nil end
                        SetNoclip(false)
                        SetBodyVelocity(false)
                        task.wait(0.2)

                        -- Quay về pháo bạn bè
                        local fb2 = GetFriendBoatForSea()
                        if fb2 then
                            SitOnFriendCannon(fb2)
                        end
                    else
                        -- Không có mob → bắt buộc hủy toàn bộ tween+BV+loop, đứng yên trên pháo chờ
                        if activeTween then activeTween:Cancel() activeTween = nil end
                        SetNoclip(false)
                        SetBodyVelocity(false)
                        StopWeaponLoop()
                        StopSkillSpamLoop()
                        task.wait(0.5)
                    end
                else
                    -- Không bật mob toggle → bắt buộc hủy toàn bộ, chỉ ngồi trên pháo bạn bè
                    if activeTween then activeTween:Cancel() activeTween = nil end
                    SetNoclip(false)
                    SetBodyVelocity(false)
                    StopWeaponLoop()
                    StopSkillSpamLoop()
                    task.wait(0.5)
                end
                return
            end

            -- ══════════════════════════════════════════════════════════
            -- CHẾ ĐỘ CHỈ MOB TOGGLE (không có AutoSail):
            -- Tìm mob ngay tại chỗ, nếu không có → không làm gì.
            -- Nếu có → farm rồi dừng (không loop mua thuyền, không sail).
            -- ══════════════════════════════════════════════════════════
            if anyMobToggle and not autoSail then
                local mob, genvKey = FindNearestSeaMob()
                if not mob then
                    task.wait(0.5)
                    return
                end

                local data2 = SEA_MOB_MAP[genvKey]
                local isBoatOrBeast2 = data2 and (data2.isBoat or data2.isSeaBeast)

                -- Có mob → farm bám theo mob
                SetNoclip(true)
                SetBodyVelocity(true)

                -- Safe Boat: quay vòng quanh player ở Y=500 khi đang farm
                local safeBoat2 = GetNearestBoat()
                if safeBoat2 then StartSafeBoat(safeBoat2) end

                if isBoatOrBeast2 then
                    local alive2 = true
                    StartSkillSpamLoop(function()
                        return not (seaFarmRunning and alive2
                            and getgenv().AutoSailEnabled == false
                            and IsAnyMobToggleOn())
                    end)

                    local timeout = 0
                    while seaFarmRunning and getgenv().AutoSailEnabled == false
                        and IsAnyMobToggleOn()
                        and IsMobAlive(mob, genvKey) do
                        local tgtCF = GetMobFarmCFrame(mob, genvKey)
                        if tgtCF then TweenTo(tgtCF) end
                        task.wait(0.1)
                        timeout += 0.1
                        if timeout > 60 then break end
                    end

                    alive2 = false
                    StopSkillSpamLoop()
                else
                    StartWeaponLoop(function() return GetWeaponForMob(genvKey) end)

                    local timeout = 0
                    while seaFarmRunning and getgenv().AutoSailEnabled == false
                        and IsAnyMobToggleOn()
                        and IsMobAlive(mob, genvKey) do
                        local tgtCF = GetMobFarmCFrame(mob, genvKey)
                        if tgtCF then TweenTo(tgtCF) end
                        task.wait(0.1)
                        timeout += 0.1
                        if timeout > 60 then break end
                    end

                    StopWeaponLoop()
                end

                -- Hết mob → dừng Safe Boat để player có thể tween tới thuyền
                StopSafeBoat()

                -- Teleport thuyền xuống Y=30 chỉ khi SafeBoat đã bật (thuyền đang ở Y=500)
                if getgenv().SafeBoatEnabled and safeBoat2 and safeBoat2.Parent then
                    local pivot = safeBoat2:GetPivot()
                    pcall(function()
                        safeBoat2:PivotTo(CFrame.new(pivot.Position.X, 30, pivot.Position.Z))
                    end)
                end

                SetNoclip(false)
                SetBodyVelocity(false)
                if activeTween then activeTween:Cancel() activeTween = nil end

                -- Mob chết hoặc toggle tắt → dừng mọi hoạt động, không tiếp tục
                return
            end

            -- ══════════════════════════════════════════════════════════
            -- CHẾ ĐỘ AUTOSAIL (có thể kết hợp mob toggle):
            -- BƯỚC 1: Mua thuyền nếu không có trong 3500 stud
            -- ══════════════════════════════════════════════════════════
            local myBoat = GetNearestBoat()

            -- Không có thuyền nào trong 3500 stud
            if not myBoat then
                if getgenv().ResetCharacterEnabled then
                    -- Toggle reset bật → reset nhân vật, CharacterAdded lo phần còn lại
                    ResetPlayer()
                    task.wait(6)
                    return
                else
                    -- Toggle reset tắt → tween tới mua thuyền bình thường
                    TweenToSync(BUY_BOAT_CFRAME)
                    if not seaFarmRunning then return end
                    task.wait(0.5)
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBoat", _G.SelectedBoat)
                    end)
                    task.wait(1.5)
                    myBoat = GetNearestBoat()
                    if not myBoat then task.wait(2) return end
                end
            end

            -- ══════════════════════════════════════════════════════════
            -- BƯỚC 2: Ngồi lên thuyền (nếu chưa ngồi)
            -- ══════════════════════════════════════════════════════════
            if not IsOnBoat() then
                local sat = SitOnBoat(myBoat)
                if not sat then task.wait(1) return end
            end
            if not seaFarmRunning then return end

            -- ══════════════════════════════════════════════════════════
            -- BƯỚC 3: Tween THUYỀN ra biển đã chọn
            -- Nếu toggle mob bật: kiểm tra mob mỗi bước, interrupt khi gặp
            -- ══════════════════════════════════════════════════════════
            local targetSeaCF = SEA_ZONE_CFRAMES[_G.DangerSc] or SEA_ZONE_CFRAMES["Lv 1"]

            local boatRoot = GetBoatRoot(myBoat)
            if not boatRoot then task.wait(1) return end

            SetBoatNoclip(myBoat, true)
            SetBoatBodyVelocity(myBoat, true)

            local startPos  = boatRoot.Position
            local endPos    = targetSeaCF.Position
            local totalDist = (endPos - startPos).Magnitude
            local steps     = math.max(1, math.ceil(totalDist / 500))
            local interrupted = false

            -- Lấy Y thuyền 1 lần trước vòng lặp (chỉ dùng khi FlyBoat tắt)
            local fixedBoatY
            if not getgenv().FlyBoatEnabled then
                local boatRootNow = GetBoatRoot(myBoat)
                fixedBoatY = boatRootNow and boatRootNow.Position.Y or 35
            end

            for i = 1, steps do
                if not seaFarmRunning then
                    CancelBoatTween()
                    SetBoatNoclip(myBoat, false)
                    SetBoatBodyVelocity(myBoat, false)
                    return
                end
                if not IsOnBoat() then break end

                local t       = i / steps
                local stepPos = startPos + (endPos - startPos) * t
                local stepY
                if getgenv().FlyBoatEnabled then
                    stepY = 150
                else
                    -- Chỉ tween X/Z, Y giữ nguyên vị trí ban đầu của thuyền
                    stepY = fixedBoatY
                end
                local stepCF  = CFrame.new(stepPos.X, stepY, stepPos.Z)

                TweenBoatToSync(myBoat, stepCF)
                if not seaFarmRunning then
                    CancelBoatTween()
                    SetBoatNoclip(myBoat, false)
                    SetBoatBodyVelocity(myBoat, false)
                    return
                end

                -- Chỉ kiểm tra mob nếu toggle mob bật
                if IsAnyMobToggleOn() then
                    local mob, _ = FindNearestSeaMob()
                    if mob then
                        interrupted = true
                        break
                    end
                end
            end

            CancelBoatTween()
            SetBoatNoclip(myBoat, false)
            SetBoatBodyVelocity(myBoat, false)

            if not seaFarmRunning then return end

            -- ══════════════════════════════════════════════════════════
            -- BƯỚC 4: Có mob → nhảy khỏi thuyền → farm bám theo mob
            -- ══════════════════════════════════════════════════════════
            if interrupted and IsAnyMobToggleOn() then
                PerformJump(true)
                task.wait(0.6)

                SetNoclip(true)
                SetBodyVelocity(true)

                -- Safe Boat: bật ngay sau khi nhảy khỏi thuyền, thuyền quay vòng ở Y=500
                local safeBoatRef = myBoat
                if safeBoatRef then StartSafeBoat(safeBoatRef) end

                -- Vòng ngoài: tìm mob mới khi mob cũ chết
                while seaFarmRunning and IsAnyMobToggleOn() do
                    local mob, genvKey = FindNearestSeaMob()
                    if not mob then break end

                    local data = SEA_MOB_MAP[genvKey]
                    local isBoatOrBeast = data and (data.isBoat or data.isSeaBeast)

                    if isBoatOrBeast then
                        local alive = true
                        StartSkillSpamLoop(function()
                            return not (seaFarmRunning and alive and IsAnyMobToggleOn())
                        end)

                        local timeout = 0
                        while seaFarmRunning and IsMobAlive(mob, genvKey) do
                            local tgtCF = GetMobFarmCFrame(mob, genvKey)
                            if tgtCF then TweenTo(tgtCF) end
                            task.wait(0.1)
                            timeout += 0.1
                            if timeout > 60 then break end
                        end

                        alive = false
                        StopSkillSpamLoop()
                    else
                        -- Mob thường: weapon từ dropdown
                        StartWeaponLoop(function() return GetWeaponForMob(genvKey) end)

                        local timeout = 0
                        while seaFarmRunning and IsMobAlive(mob, genvKey) do
                            local tgtCF = GetMobFarmCFrame(mob, genvKey)
                            if tgtCF then TweenTo(tgtCF) end
                            task.wait(0.1)
                            timeout += 0.1
                            if timeout > 60 then break end
                        end

                        StopWeaponLoop()
                    end

                    task.wait(0.2)
                end

                -- Hết mob → dừng Safe Boat để player có thể tween tới thuyền
                StopSafeBoat()

                -- Teleport thuyền xuống Y=30 chỉ khi SafeBoat đã bật (thuyền đang ở Y=500)
                if getgenv().SafeBoatEnabled and safeBoatRef and safeBoatRef.Parent then
                    local pivot = safeBoatRef:GetPivot()
                    pcall(function()
                        safeBoatRef:PivotTo(CFrame.new(pivot.Position.X, 30, pivot.Position.Z))
                    end)
                end

                SetNoclip(false)
                SetBodyVelocity(false)
                if activeTween then activeTween:Cancel() activeTween = nil end

                if not seaFarmRunning then return end

                -- ══════════════════════════════════════════════════════
                -- BƯỚC 5: Hết mob → quay về thuyền và tiếp tục ra biển
                -- ══════════════════════════════════════════════════════
                myBoat = GetNearestBoat()
                if myBoat then
                    local sat = SitOnBoat(myBoat)
                    if not sat then task.wait(1) end
                else
                    if getgenv().ResetCharacterEnabled then
                        ResetPlayer()
                    end
                    task.wait(4)
                end
            else
                -- AutoSail thuần (không có mob): đã tới vùng biển, chờ mob spawn
                task.wait(3)
            end
        end)

        if not ok then
            -- Lỗi pcall → chờ rồi thử lại
            task.wait(1)
        end
    end
    seaFarmThread = nil
end

-- ─── Phát hiện thuyền vỡ khi đang farm ────────────────────────────────
spawn(function()
    while true do
        task.wait(1)
        if not seaFarmRunning then continue end
        pcall(function()
            if IsOnBoat() then
                local myBoat = GetNearestBoat()
                if not myBoat then
                    -- Thuyền vỡ khi đang ngồi
                    if getgenv().ResetCharacterEnabled then
                        ResetPlayer()
                        -- CharacterAdded sẽ handle restart
                    end
                    task.wait(4)
                end
            end
        end)
    end
end)

-- ─── Sau khi respawn: cancel loop cũ → tween buy → buy → restart loop ──
player.CharacterAdded:Connect(function(char)
    if not seaFarmRunning then return end

    -- Cancel tween và goroutine cũ đang bị kẹt
    if activeTween then activeTween:Cancel() activeTween = nil end
    CancelBoatTween()
    if seaFarmThread then task.cancel(seaFarmThread) seaFarmThread = nil end

    task.wait(2) -- Đợi character load hoàn toàn
    if not seaFarmRunning then return end

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end

    SetNoclip(true)
    SetBodyVelocity(true)

    -- Tween tới điểm mua thuyền
    TweenToSync(BUY_BOAT_CFRAME)
    if not seaFarmRunning then return end

    task.wait(0.5)

    -- Mua thuyền
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBoat", _G.SelectedBoat)
    end)

    -- Đợi thuyền spawn (tối đa 5s)
    local waited = 0
    while waited < 5 do
        task.wait(0.5)
        waited += 0.5
        if GetNearestBoat() then break end
    end

    if not seaFarmRunning then return end

    -- Restart vòng farm từ đầu
    seaFarmThread = task.spawn(SeaFarmLoop)
end)

--// ===================================================================
--//              MAIN TAB – Settings / Configure
--// ===================================================================

Tabs.Main:AddSection("Settings / Configure")

local _Weapon = { "Melee", "Sword", "Blox Fruit", "Gun" }

local Weapon_Config = Tabs.Main:AddDropdown("Weapon_Config", {
    Title   = "Select Weapon",
    Values  = _Weapon,
    Multi   = false,
    Default = 1
})
Weapon_Config:OnChanged(function(Value)
    _G.ChooseWP = Value
end)
_G.ChooseWP = _Weapon[1]

--// ===================================================================
--//              SEA EVENT TAB (UI)
--// ===================================================================

Tabs.SeaEvent:AddSection("Sea Event / Setting Sail")

local ListSeaBoat = {
    "Guardian",
    "PirateGrandBrigade",
    "MarineGrandBrigade",
    "PirateBrigade",
    "MarineBrigade",
    "PirateSloop",
    "MarineSloop",
    "Beast Hunter"
}

local ListSeaZone = {
    "Lv 1", "Lv 2", "Lv 3", "Lv 4", "Lv 5", "Lv 6", "Lv Infinite"
}

-- Map tên hiển thị → genv key (định nghĩa trước để dùng trong UI + loop)
local SeaEntityGenvMap = {
    ["Auto Shark"]               = "AutoSharkEnabled",
    ["Auto Piranha"]             = "AutoPiranhaEnabled",
    ["Auto Terror Shark"]        = "AutoTerrorSharkEnabled",
    ["Auto Fish Crew Member"]    = "AutoFishCrewEnabled",
    ["Auto Haunted Crew Member"] = "AutoHauntedCrewEnabled",
    ["Auto PirateGrandBrigade"]  = "AutoPirateGrandEnabled",
    ["Auto Fish Boat"]           = "AutoFishBoatEnabled",
    ["Auto Sea Beast"]           = "AutoSeaBeastEnabled",
}
for _, genv in pairs(SeaEntityGenvMap) do
    getgenv()[genv] = false
end

-- ── 1. BoatDropdown ──────────────────────────────────────────────────
local BoatDropdown = Tabs.SeaEvent:AddDropdown("BoatDropdown", {
    Title   = "Choose Boats",
    Values  = ListSeaBoat,
    Multi   = false,
    Default = 1,
})
BoatDropdown:OnChanged(function(Value)
    _G.SelectedBoat = Value
end)
_G.SelectedBoat = ListSeaBoat[1]

-- ── 2. SeaEntityDropdown ─────────────────────────────────────────────
local SeaEntityNames = {
    "Auto Shark",
    "Auto Piranha",
    "Auto Terror Shark",
    "Auto Fish Crew Member",
    "Auto Haunted Crew Member",
    "Auto PirateGrandBrigade",
    "Auto Fish Boat",
    "Auto Sea Beast",
}

local SeaEntityDropdown = Tabs.SeaEvent:AddDropdown("SeaEntityDropdown", {
    Title   = "Select Sea Entities",
    Values  = SeaEntityNames,
    Multi   = true,
    Default = {},
})
SeaEntityDropdown:OnChanged(function(selectedTable)
    for _, genv in pairs(SeaEntityGenvMap) do
        getgenv()[genv] = false
    end
    for name, isSelected in pairs(selectedTable) do
        if isSelected and SeaEntityGenvMap[name] then
            getgenv()[SeaEntityGenvMap[name]] = true
        end
    end
    if IsAnyMobToggleOn() then
        if not seaFarmRunning then
            seaFarmThread = task.spawn(SeaFarmLoop)
        end
    else
        if not getgenv().AutoSailEnabled then
            StopSeaFarm()
        end
    end
end)

-- ── 3. SeaLevelDropdown ──────────────────────────────────────────────
local SeaLevelDropdown = Tabs.SeaEvent:AddDropdown("SeaLevelDropdown", {
    Title   = "Choose Sea Level",
    Values  = ListSeaZone,
    Multi   = false,
    Default = 1,
})
SeaLevelDropdown:OnChanged(function(Value)
    _G.DangerSc = Value
end)
_G.DangerSc = ListSeaZone[1]

-- ── 4. SelectMutiSeaEvent (dropdown player trong server) ─────────────
local function GetSeaPlayerList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            table.insert(list, p.Name)
        end
    end
    if #list == 0 then
        table.insert(list, "(Không có player)")
    end
    return list
end

_G.MutiSeaTarget = nil
local mutiSeaDropdown = Tabs.SeaEvent:AddDropdown("SelectMutiSeaEvent", {
    Title   = "Select Player (Multi Farm)",
    Values  = GetSeaPlayerList(),
    Multi   = false,
    Default = 1,
})
mutiSeaDropdown:OnChanged(function(Value)
    _G.MutiSeaTarget = Value
end)
_G.MutiSeaTarget = GetSeaPlayerList()[1]

-- ── 5. ResetList button ──────────────────────────────────────────────
Tabs.SeaEvent:AddButton({
    Title    = "Reset List",
    Callback = function()
        local newList = GetSeaPlayerList()
        mutiSeaDropdown:SetValues(newList)
        _G.MutiSeaTarget = newList[1]
    end,
})

-- ── 6. Buy Boats button ──────────────────────────────────────────────
Tabs.SeaEvent:AddButton({
    Title    = "Buy Boats",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBoat", _G.SelectedBoat)
        end)
    end,
})

-- ── 7. AutoSailToggle ────────────────────────────────────────────────
Tabs.SeaEvent:AddToggle("AutoSailToggle", {
    Title    = "Auto Sail Boat",
    Default  = false,
    Callback = function(state)
        getgenv().AutoSailEnabled = state
        if state then
            if not seaFarmRunning then
                seaFarmThread = task.spawn(SeaFarmLoop)
            end
        else
            if not IsAnyMobToggleOn() then
                StopSeaFarm()
            end
        end
    end,
})

-- ── 8. AutoMutiFarmSea toggle (săn cùng bạn bè) ─────────────────────
getgenv().AutoMutiFarmSeaEnabled = false
Tabs.SeaEvent:AddToggle("AutoMutiFarmSea", {
    Title    = "Auto Muti Farm Sea",
    Default  = false,
    Callback = function(state)
        getgenv().AutoMutiFarmSeaEnabled = state
    end,
})

-- ── 9. AutoM1FruitToggle ─────────────────────────────────────────────
getgenv().AutoM1FruitEnabled = false
Tabs.SeaEvent:AddToggle("AutoM1FruitToggle", {
    Title    = "Auto M1 Fruit For Sea Event",
    Default  = false,
    Callback = function(state)
        getgenv().AutoM1FruitEnabled = state
    end,
})

-- ── 10. ResetCharacterToggle ─────────────────────────────────────────
getgenv().ResetCharacterEnabled = false
Tabs.SeaEvent:AddToggle("ResetCharacterToggle", {
    Title    = "Reset Character",
    Default  = false,
    Callback = function(state)
        getgenv().ResetCharacterEnabled = state
    end,
})

-- ── 11. FlyBoatToggle ────────────────────────────────────────────────
getgenv().FlyBoatEnabled = false
Tabs.SeaEvent:AddToggle("FlyBoatToggle", {
    Title    = "Fly Boat",
    Default  = false,
    Callback = function(state)
        getgenv().FlyBoatEnabled = state
    end,
})

-- ── 12. SafeBoatToggle ───────────────────────────────────────────────
getgenv().SafeBoatEnabled = false
Tabs.SeaEvent:AddToggle("SafeBoatToggle", {
    Title    = "Safe Boat",
    Default  = false,
    Callback = function(state)
        getgenv().SafeBoatEnabled = state
        if not state then
            StopSafeBoat()
        end
    end,
})

--// ===================================================================
--//              LEVIATHAN HUNT TAB (UI + LOGIC)
--// ===================================================================

-- Alias ngắn cho RemoteStorage
local replicated = ReplicatedStorage

-- ─── Safe fallback cho GetSetting / SaveSettings nếu chưa định nghĩa ──
if not _G.SaveData then _G.SaveData = {} end

local _settingsFile = "Topichest/Settings.json"

if not rawget(_G, "_GetSetting_defined") then
    _G._GetSetting_defined = true
    GetSetting = GetSetting or function(key, default)
        local v = _G.SaveData[key]
        if v == nil then return default end
        return v
    end
    SaveSettings = SaveSettings or function()
        pcall(function()
            local folder = "Topichest"
            if not isfolder(folder) then makefolder(folder) end
            writefile(_settingsFile, HttpService:JSONEncode(_G.SaveData))
        end)
    end
end

-- ── [SECTION] Frozen Dimension ────────────────────────────────────────
Tabs.Leviathan:AddSection("Frozen Dimension")

-- Paragraph kiểm tra đảo băng
local FrozenIsland = Tabs.Leviathan:AddParagraph({
    Title = "Đảo Băng Levi",
    Desc  = "Status: đang kiểm tra..."
})
spawn(function()
    pcall(function()
        while wait(1) do
            if workspace._WorldOrigin
            and workspace._WorldOrigin:FindFirstChild("Locations")
            and workspace._WorldOrigin.Locations:FindFirstChild("Frozen Dimension") then
                FrozenIsland:SetDesc("✅️ Có Đảo")
            else
                FrozenIsland:SetDesc("❌️ Không Có")
            end
        end
    end)
end)

-- Nút mua Spy
Tabs.Leviathan:AddButton({
    Title       = "Buy Spy",
    Callback    = function()
        pcall(function()
            replicated.Remotes.CommF_:InvokeServer("InfoLeviathan", "2")
        end)
    end
})

-- ── Helper: Lấy CFrame của Frozen Dimension (dùng cho tween) ──────────
local function GetFrozenDimensionCFrame()
    -- Ưu tiên lấy từ _WorldOrigin.Locations
    pcall(function()
        local loc = workspace._WorldOrigin.Locations:FindFirstChild("Frozen Dimension")
        if loc then
            if loc.PrimaryPart then return loc.PrimaryPart.CFrame end
            local part = loc:FindFirstChildWhichIsA("BasePart")
            if part then return part.CFrame end
        end
    end)
    -- Fallback: LeviathanGate trên Map
    local gate = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("LeviathanGate")
    if gate then
        if gate.PrimaryPart then return gate.PrimaryPart.CFrame end
        local part = gate:FindFirstChildWhichIsA("BasePart")
        if part then return part.CFrame end
    end
    return nil
end

-- ── Toggle: Teleport to Frozen Dimension (pure tween) ─────────────────
_G.FrozenTP      = false
local frozenTPThread = nil

local function StopFrozenTP()
    _G.FrozenTP = false
    if frozenTPThread then task.cancel(frozenTPThread) frozenTPThread = nil end
end

Tabs.Leviathan:AddToggle("FrozenTPToggle", {
    Title       = "Teleport Frozen Dimension",
    Default     = GetSetting("FrozenTP_Save", false),
    Callback    = function(I)
        _G.FrozenTP = I
        _G.SaveData["FrozenTP_Save"] = I
        SaveSettings()

        if I then
            SetNoclip(true)
            SetBodyVelocity(true)

            frozenTPThread = task.spawn(function()
                while _G.FrozenTP do
                    pcall(function()
                        -- Tween tới Frozen Dimension nếu đang có đảo
                        local frozenCF = GetFrozenDimensionCFrame()
                        if frozenCF then
                            TweenToSync(frozenCF * CFrame.new(0, 5, 0))
                        end

                        -- Mở cổng nếu LeviathanGate tồn tại
                        local gate = workspace:FindFirstChild("Map")
                                   and workspace.Map:FindFirstChild("LeviathanGate")
                        if gate then
                            local gatePart = gate.PrimaryPart
                                          or gate:FindFirstChildWhichIsA("BasePart")
                            if gatePart then
                                TweenToSync(gatePart.CFrame * CFrame.new(0, 3, 0))
                            end
                            replicated.Remotes.CommF_:InvokeServer("OpenLeviathanGate")
                        end
                    end)
                    task.wait(0.5)
                end
            end)
        else
            StopFrozenTP()
            SetNoclip(false)
            SetBodyVelocity(false)
        end
    end,
})

--// ===================================================================
--//              [SECTION] Leviathan Hunt Setup
--// ===================================================================
Tabs.Leviathan:AddSection("Leviathan Hunt Setup")

-- ── Helper: Lấy danh sách player hiện tại trong server ───────────────
local function GetPlayerNameList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(list, p.Name)
    end
    if #list == 0 then
        table.insert(list, "(Không có player)")
    end
    return list
end

-- ── Dropdown: Select Owner Boat ───────────────────────────────────────
_G.LeviathanBoatOwner = nil

local leviOwnerDropdown = Tabs.Leviathan:AddDropdown("LeviOwnerBoatDropdown", {
    Title       = "Select Owner Boat",
    Values      = GetPlayerNameList(),
    Multi       = false,
    Default     = 1,
})
leviOwnerDropdown:OnChanged(function(Value)
    _G.LeviathanBoatOwner = Value
end)
_G.LeviathanBoatOwner = GetPlayerNameList()[1]

-- ── Button: Reset List Player ─────────────────────────────────────────
Tabs.Leviathan:AddButton({
    Title       = "Reset List Player",
    Callback    = function()
        local newList = GetPlayerNameList()
        -- Fluent SetValues để reset dropdown
        leviOwnerDropdown:SetValues(newList)
        _G.LeviathanBoatOwner = newList[1]
        Fluent:Notify({
            Title    = "Leviathan Hunt",
            Content  = "Đã cập nhật: " .. #newList .. " player",
            Duration = 3,
        })
    end,
})

-- ── Helper: Tìm thuyền của owner được chọn ───────────────────────────
local function GetOwnerBoat()
    local ownerName = _G.LeviathanBoatOwner
    if not ownerName or ownerName == "(Không có player)" then return nil end

    local boatsFolder = workspace:FindFirstChild("Boats")
    if not boatsFolder then return nil end

    -- Kiểm tra xem owner có đang ngồi trên thuyền nào không
    local ownerPlr = Players:FindFirstChild(ownerName)
    if ownerPlr then
        for _, boat in ipairs(boatsFolder:GetChildren()) do
            local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
            if seat and seat.Occupant then
                if seat.Occupant.Parent and seat.Occupant.Parent.Name == ownerName then
                    return boat
                end
            end
        end
        -- Fallback: tìm thuyền gần owner nhất (trong 800 stud)
        local ownerChar = ownerPlr.Character
        if ownerChar then
            local ownerHRP = ownerChar:FindFirstChild("HumanoidRootPart")
            if ownerHRP then
                local best, bestDist = nil, math.huge
                for _, boat in ipairs(boatsFolder:GetChildren()) do
                    local root = GetBoatRoot(boat)
                    if root then
                        local d = (root.Position - ownerHRP.Position).Magnitude
                        if d < bestDist and d < 800 then
                            bestDist = d
                            best     = boat
                        end
                    end
                end
                return best
            end
        end
    end
    return nil
end


-- ── Helper: Lấy danh sách pháo thật trên thuyền ─────────────────────
-- Pháo = child TRỰC TIẾP dưới boat tên chứa "Cannon" (Cannon, Cannon1, Cannon2...)
-- Loại trừ hoàn toàn mọi thứ tên chứa "Harpoon" hoặc "Heart"
-- Cấu trúc: boat.Cannon, boat:GetChildren()[15], [16], [17] (tên đều chứa "Cannon")
local function GetCannonSeats(boat)
    local cannons = {}
    if not boat then return cannons end
    for _, child in ipairs(boat:GetChildren()) do
        local n = child.Name:lower()
        if n:find("cannon") and not n:find("harpoon") and not n:find("heart") then
            table.insert(cannons, child)
        end
    end
    return cannons
end

-- ── Helper: Lấy BasePart đại diện của cannon để tween tới ────────────
-- Ưu tiên VehicleSeat/Seat (có thể ngồi), rồi PrimaryPart, rồi BasePart bất kỳ
-- Nếu cannon bản thân là BasePart thì dùng luôn
local function GetCannonPart(cannon)
    if not cannon then return nil end
    if cannon:IsA("BasePart") then return cannon end
    local seat = cannon:FindFirstChildWhichIsA("VehicleSeat", true)
               or cannon:FindFirstChildWhichIsA("Seat", true)
    if seat then return seat end
    if cannon.PrimaryPart then return cannon.PrimaryPart end
    return cannon:FindFirstChildWhichIsA("BasePart", true)
end

-- ── Helper: Kiểm tra cannon có ai đứng gần không (trong 8 stud) ──────
local function IsCannonOccupied(cannon)
    if not cannon or not cannon.Parent then return true end
    local part = GetCannonPart(cannon)
    if not part then return true end
    if part:IsA("Seat") or part:IsA("VehicleSeat") then
        return part.Occupant ~= nil
    end
    local pos = part.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - pos).Magnitude < 8 then
                return true
            end
        end
    end
    return false
end

-- ── Helper: Tìm cannon trống đầu tiên ────────────────────────────────
local function FindEmptyCannonSeat(boat)
    for _, cannon in ipairs(GetCannonSeats(boat)) do
        if not IsCannonOccupied(cannon) then return cannon end
    end
    return nil
end

-- ── Helper: Tìm thuyền Beast Hunter của mình gần nhất (< 800 stud) ───
local function GetMyBeastHunterBoat()
    local boatsFolder = workspace:FindFirstChild("Boats")
    if not boatsFolder then return nil end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, boat in ipairs(boatsFolder:GetChildren()) do
        if boat.Name == "Beast Hunter" then
            local root = GetBoatRoot(boat)
            if root then
                local d = (root.Position - hrp.Position).Magnitude
                if d < bestDist and d < 800 then
                    bestDist = d
                    best     = boat
                end
            end
        end
    end
    return best
end

-- ── Helper: Tween tới pháo trống và đứng/ngồi lên ───────────────────
local function SitOnCannon(boat)
    if not boat then return false end
    local cannon = FindEmptyCannonSeat(boat)
    if not cannon then return false end
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return false end

    local part = GetCannonPart(cannon)
    if not part then return false end

    -- Tween đứng ngay trên pháo
    TweenToSync(part.CFrame * CFrame.new(0, 3, 0))
    task.wait(0.2)

    -- Nếu là Seat/VehicleSeat thì ngồi luôn
    if part:IsA("Seat") or part:IsA("VehicleSeat") then
        if not part.Occupant then
            pcall(function() part:Sit(hum) end)
            task.wait(0.4)
        end
        local h = player.Character and player.Character:FindFirstChild("Humanoid")
        return h and h.Sit
    end

    -- BasePart thường: kiểm tra đã đến gần chưa
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and (hrp.Position - part.Position).Magnitude < 8
end

-- ── State chung cho Miti/Auto Hunt ───────────────────────────────────
_G.MitiHuntEnabled = false
_G.AutoHuntEnabled = false

local leviHuntThread  = nil
local leviHuntRunning = false

local function StopLeviHunt()
    leviHuntRunning = false
    if leviHuntThread then task.cancel(leviHuntThread) leviHuntThread = nil end
end

-- ── Mode 1: Miti + Auto Hunt → leo lên pháo thuyền của owner ─────────
-- Vòng lặp: theo dõi vị trí pháo liên tục, nếu bị văng ra thì tween lại
local function StartMitiAutoHunt()
    StopLeviHunt()
    leviHuntRunning = true
    leviHuntThread = task.spawn(function()
        SetNoclip(true)
        SetBodyVelocity(true)
        local lastCannonPos = nil
        while leviHuntRunning do
            pcall(function()
                local char = player.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(1) return end

                local boat = GetOwnerBoat()
                if not boat then task.wait(1) return end

                local cannon = FindEmptyCannonSeat(boat)
                if not cannon then
                    task.wait(1)
                    return
                end

                local cannonPart = GetCannonPart(cannon)
                if not cannonPart then task.wait(1) return end

                -- Kiểm tra còn ở gần pháo không (trong 8 stud)
                if lastCannonPos and (hrp.Position - cannonPart.Position).Magnitude < 8 then
    -- Đang ngồi im trên pháo → không tween, chỉ cập nhật pos và chờ
    lastCannonPos = cannonPart.Position
    task.wait(0.3)
    return
end

                -- Bị văng ra hoặc chưa ở pháo → tween lại
                local ok = SitOnCannon(boat)
                if ok then
                    lastCannonPos = cannonPart.Position
                else
                    lastCannonPos = nil
                    task.wait(1)
                end
            end)
            task.wait(0.1)
        end
    end)
end

-- ── Mode 2: Chỉ Auto Hunt → mua Beast Hunter + sit ghế lái + sail Lv Infinite ──
-- Flow giống Sea Event: tween mua → BuyBoat → SitOnBoat (ghế lái) → TweenBoat ra biển
local function StartAutoHuntOnly()
    StopLeviHunt()
    leviHuntRunning = true
    leviHuntThread = task.spawn(function()
        while leviHuntRunning do
            pcall(function()
                SetNoclip(true)
                SetBodyVelocity(true)

                -- Bước 1: Kiểm tra đã có Beast Hunter gần chưa (trong 3500 stud)
                local myBoat = nil
                local boatsFolder = workspace:FindFirstChild("Boats")
                if boatsFolder then
                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local bestDist = math.huge
                        for _, boat in ipairs(boatsFolder:GetChildren()) do
                            if boat.Name == "Beast Hunter" then
                                local root = GetBoatRoot(boat)
                                if root then
                                    local d = (root.Position - hrp.Position).Magnitude
                                    if d < bestDist and d <= 3500 then
                                        bestDist = d
                                        myBoat = boat
                                    end
                                end
                            end
                        end
                    end
                end

                -- Chưa có → mua
                if not myBoat then
                    TweenToSync(BUY_BOAT_CFRAME)
                    if not leviHuntRunning then return end
                    task.wait(0.5)
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBoat", "Beast Hunter")
                    end)
                    task.wait(1.5)
                    -- Đợi Beast Hunter spawn (tối đa 6s)
                    local waited = 0
                    while waited < 6 and leviHuntRunning do
                        task.wait(0.5)
                        waited = waited + 0.5
                        myBoat = GetMyBeastHunterBoat()
                        if myBoat then break end
                    end
                end

                if not myBoat or not leviHuntRunning then return end

                -- Bước 2: Ngồi lên ghế lái Beast Hunter (giống SitOnBoat trong Sea Event)
                if not IsOnBoat() then
                    local sat = SitOnBoat(myBoat)
                    if not sat then task.wait(1) return end
                end
                if not leviHuntRunning then return end

                -- Bước 3: Tween thuyền Beast Hunter ra vùng biển Lv Infinite
                local targetCF = SEA_ZONE_CFRAMES["Lv Infinite"]
                if not targetCF then return end

                local boatRoot = GetBoatRoot(myBoat)
                if not boatRoot then return end

                SetBoatNoclip(myBoat, true)
                SetBoatBodyVelocity(myBoat, true)

                local startPos  = boatRoot.Position
                local endPos    = targetCF.Position
                local totalDist = (endPos - startPos).Magnitude
                local steps     = math.max(1, math.ceil(totalDist / 500))

                for i = 1, steps do
                    if not leviHuntRunning then
                        CancelBoatTween()
                        SetBoatNoclip(myBoat, false)
                        SetBoatBodyVelocity(myBoat, false)
                        return
                    end
                    if not IsOnBoat() then break end
                    local t       = i / steps
                    local stepPos = startPos + (endPos - startPos) * t
                    local stepCF  = CFrame.new(stepPos.X, math.max(stepPos.Y, 35), stepPos.Z)
                    TweenBoatToSync(myBoat, stepCF)
                end

                CancelBoatTween()
                SetBoatNoclip(myBoat, false)
                SetBoatBodyVelocity(myBoat, false)

                -- Đã tới Lv Infinite → chờ (không loop lại ngay)
                local waited2 = 0
                while leviHuntRunning and waited2 < 10 do
                    task.wait(1)
                    waited2 = waited2 + 1
                    -- Nếu bị văng khỏi thuyền → restart loop
                    if not IsOnBoat() then break end
                end
            end)
            if leviHuntRunning then task.wait(0.5) end
        end
    end)
end

-- ── Chọn mode dựa vào trạng thái 2 toggle ────────────────────────────
local function UpdateLeviHuntMode()
    if _G.MitiHuntEnabled and _G.AutoHuntEnabled then
        -- Cả hai bật → leo pháo thuyền owner
        StartMitiAutoHunt()
    elseif _G.AutoHuntEnabled then
        -- Chỉ Auto Hunt → mua Beast Hunter + sail Lv Infinite
        StartAutoHuntOnly()
    else
        -- Tắt hết
        StopLeviHunt()
        SetNoclip(false)
        SetBodyVelocity(false)
    end
end

-- ── Toggle: Miti Hunt Leviathan ───────────────────────────────────────
Tabs.Leviathan:AddToggle("MitiHuntToggle", {
    Title       = "Miti Hunt Leviathan",
    Default     = false,
    Callback    = function(state)
        _G.MitiHuntEnabled = state
        UpdateLeviHuntMode()
    end,
})

-- ── Toggle: Auto Hunt Leviathan ───────────────────────────────────────
Tabs.Leviathan:AddToggle("AutoHuntToggle", {
    Title       = "Auto Hunt Leviathan",
    Default     = false,
    Callback    = function(state)
        _G.AutoHuntEnabled = state
        UpdateLeviHuntMode()
    end,
})

--// ===================================================================
--//              LEVIATHAN ATTACK SECTION
--// ===================================================================
Tabs.Leviathan:AddSection("Leviathan Attack")

-- ── Helper: Kiểm tra một mob levi còn sống không ────────────────────
local function IsLeviAlive(mob)
    if not mob or not mob.Parent then return false end
    local hp = mob:FindFirstChild("Health")
    if hp then return hp.Value > 0 end
    -- Không có Health object → còn tồn tại trong workspace = còn sống
    return mob:FindFirstChild("HumanoidRootPart") ~= nil
        or mob:FindFirstChildWhichIsA("BasePart") ~= nil
end

-- ── Helper: Lấy Position của một mob levi ────────────────────────────
local function GetLeviPosition(mob)
    if not mob then return nil end
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position end
    local bp = mob:FindFirstChildWhichIsA("BasePart")
    if bp then return bp.Position end
    if mob:IsA("BasePart") then return mob.Position end
    return nil
end

-- ── Helper: Lấy tất cả Leviathan Segment còn sống ────────────────────
-- Segment = tên chứa "segment" (case-insensitive), không phải main body
local function FindAllLeviSegments()
    local seaBeasts = workspace:FindFirstChild("SeaBeasts")
    if not seaBeasts then return {} end
    local segments = {}
    for _, mob in ipairs(seaBeasts:GetChildren()) do
        if mob.Name:lower():find("segment") and IsLeviAlive(mob) then
            table.insert(segments, mob)
        end
    end
    return segments
end

-- ── Helper: Tìm Leviathan chính (không phải segment, không phải tail) ─
-- Ưu tiên tên đúng "Leviathan", fallback GetChildren()[4],[5]
local function FindMainLeviathan()
    local seaBeasts = workspace:FindFirstChild("SeaBeasts")
    if not seaBeasts then return nil end

    -- Pass 1: tên đúng "Leviathan" hoặc "Leviathan Tail"
    for _, mob in ipairs(seaBeasts:GetChildren()) do
        local n = mob.Name:lower()
        if n:find("leviathan") and not n:find("segment") then
            if IsLeviAlive(mob) then return mob end
        end
    end

    -- Pass 2: fallback index [4], [5]
    local children = seaBeasts:GetChildren()
    for _, idx in ipairs({4, 5}) do
        local mob = children[idx]
        if mob and mob.Name:lower():find("leviathan") and IsLeviAlive(mob) then
            return mob
        end
    end

    return nil
end

-- ── State: Auto Attack Levi + M1 Fruit Levi ──────────────────────────
_G.AutoAttackLeviEnabled = false
_G.M1FruitLeviEnabled    = false

local leviAttackThread  = nil
local leviAttackRunning = false

local function StopLeviAttack()
    leviAttackRunning = false
    if leviAttackThread then task.cancel(leviAttackThread) leviAttackThread = nil end
end

-- ── Skill spam riêng cho Levi ─────────────────────────────────────────
local leviSkillThread = nil
local function StartLeviSkillSpam(stopFn)
    if leviSkillThread then task.cancel(leviSkillThread) leviSkillThread = nil end
    leviSkillThread = task.spawn(function()
        local prevWeapon = nil
        while not stopFn() do
            if _G.M1FruitLeviEnabled then
                pcall(function() weaponSc("Blox Fruit") end)
                task.wait(0.1)
            else
                local available = {}
                for _, w in ipairs(WEAPON_TYPES) do
                    if w ~= prevWeapon then table.insert(available, w) end
                end
                local chosen = available[math.random(#available)]
                prevWeapon = chosen
                local skills = WEAPON_SKILLS[chosen]
                local deadline = tick() + 0.3
                local si = 1
                while not stopFn() and tick() < deadline do
                    if _G.M1FruitLeviEnabled then break end
                    pcall(Useskills, chosen, skills[si])
                    si = (si % #skills) + 1
                    task.wait(0.1)
                end
            end
        end
    end)
end

local function StopLeviSkillSpam()
    if leviSkillThread then task.cancel(leviSkillThread) leviSkillThread = nil end
end

-- ── Tween bám + M1 Fruit fire vào một target ─────────────────────────
local function AttackLeviTarget(mob)
    local pos = GetLeviPosition(mob)
    if not pos then return end

    TweenTo(CFrame.new(pos.X, pos.Y + 10, pos.Z))

    if _G.M1FruitLeviEnabled then
        pcall(function()
            local char = player.Character
            if not char then return end
            local tool = char:FindFirstChildOfClass("Tool")
            if tool and tool.ToolTip == "Blox Fruit" then
                local lcr = tool:FindFirstChild("LeftClickRemote")
                if lcr then
                    Actived()
                    lcr:FireServer(Vector3.new(pos.X, pos.Y, pos.Z), 1, true)
                    lcr:FireServer(false)
                end
            end
        end)
    end
end

-- ── Vòng lặp chính ────────────────────────────────────────────────────
-- Phase 1: farm từng Segment cho đến khi chết, hết tất cả → Phase 2
-- Phase 2: bám theo Leviathan chính / Tail
local function StartLeviAttackLoop()
    StopLeviAttack()
    leviAttackRunning = true
    leviAttackThread = task.spawn(function()
        SetNoclip(true)
        SetBodyVelocity(true)
        StartLeviSkillSpam(function() return not leviAttackRunning end)

        while leviAttackRunning do
            pcall(function()
                -- ── Phase 1: Segment còn sống → ưu tiên diệt hết ────
                local segments = FindAllLeviSegments()
                if #segments > 0 then
                    -- Lấy segment đầu tiên còn sống, bám liên tục cho đến khi chết
                    local seg = segments[1]
                    local timeout = 0
                    while leviAttackRunning and IsLeviAlive(seg) and timeout < 120 do
                        AttackLeviTarget(seg)
                        task.wait(0.1)
                        timeout = timeout + 0.1
                    end
                    -- Segment chết → loop lại để check segment tiếp theo
                    return
                end

                -- ── Phase 2: Hết segment → farm Leviathan chính ──────
                local main = FindMainLeviathan()
                if not main then
                    -- Chưa có levi nào → đợi
                    task.wait(0.5)
                    return
                end

                AttackLeviTarget(main)
            end)
            task.wait(0.1)
        end

        StopLeviSkillSpam()
        SetNoclip(false)
        SetBodyVelocity(false)
    end)
end

local function UpdateLeviAttackMode()
    if _G.AutoAttackLeviEnabled then
        StartLeviAttackLoop()
    else
        StopLeviAttack()
        StopLeviSkillSpam()
    end
end

-- ── Toggle: Auto Attack Leviathan ────────────────────────────────────
Tabs.Leviathan:AddToggle("AutoAttackLeviToggle", {
    Title       = "Auto Attack Leviathan",
    Default     = false,
    Callback    = function(state)
        _G.AutoAttackLeviEnabled = state
        UpdateLeviAttackMode()
    end,
})

-- ── Toggle: M1 Fruit for Leviathan ───────────────────────────────────
Tabs.Leviathan:AddToggle("M1FruitLeviToggle", {
    Title       = "M1 Fruit for Leviathan",
    Default     = false,
    Callback    = function(state)
        _G.M1FruitLeviEnabled = state
        -- Nếu Auto Attack đang chạy → restart để áp dụng mode mới
        if _G.AutoAttackLeviEnabled then
            StartLeviAttackLoop()
        end
    end,
})
