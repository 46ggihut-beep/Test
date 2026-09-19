--[[
  Player Aimbot - Skill + M1 Fruit + M1 Gun
  Target: người chơi khác (Players, không tính LocalPlayer)
  Có toggle UI trên màn hình để bật/tắt
]]

repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

-- ===================== CONFIG =====================
getgenv().MobAimbot = getgenv().MobAimbot or {
    Enabled = false,            -- mặc định TẮT, bật bằng toggle UI
    MaxDistance = 500,
    PredictDivisor = 0.5,
    PreferAlive = true,
    RequireHRP = true,
    TeamCheck = false,          -- true = bỏ qua người cùng team
    Debug = false,
    ToggleKey = Enum.KeyCode.RightControl, -- phím tắt (optional)
}

local Config = getgenv().MobAimbot
-- config cũ được giữ lại khi reload, nên bổ sung key mới nếu thiếu
if Config.TeamCheck == nil then Config.TeamCheck = false end

local CurrentTarget = nil
getgenv().AimPos = getgenv().AimPos or nil

local function log(...)
    if Config.Debug then
        print("[PlayerAimbot]", ...)
    end
end

-- ===================== UI TOGGLE =====================
-- Xóa GUI cũ nếu reload script
local old = PlayerGui:FindFirstChild("MobAimbotToggleGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MobAimbotToggleGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = PlayerGui

-- Khung chính (kéo được)
local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, 160, 0, 44)
frame.Position = UDim2.new(0, 20, 0.35, 0)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 80)
stroke.Thickness = 1.2
stroke.Parent = frame

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -52, 1, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.Text = "Aim Player: OFF"
title.Parent = frame

-- Nút toggle
local btn = Instance.new("TextButton")
btn.Name = "ToggleBtn"
btn.Size = UDim2.new(0, 42, 0, 24)
btn.Position = UDim2.new(1, -42, 0.5, -12)
btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
btn.Text = ""
btn.AutoButtonColor = false
btn.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(1, 0)
btnCorner.Parent = btn

local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.Size = UDim2.new(0, 20, 0, 20)
knob.Position = UDim2.new(0, 2, 0.5, -10)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.Parent = btn

local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

local function refreshUI()
    if Config.Enabled then
        title.Text = "Aim Player: ON"
        title.TextColor3 = Color3.fromRGB(120, 255, 160)
        btn.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = UDim2.new(1, -22, 0.5, -10)
        }):Play()
        stroke.Color = Color3.fromRGB(40, 170, 90)
    else
        title.Text = "Aim Player: OFF"
        title.TextColor3 = Color3.fromRGB(230, 230, 240)
        btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = UDim2.new(0, 2, 0.5, -10)
        }):Play()
        stroke.Color = Color3.fromRGB(60, 60, 80)
    end
end

local function setEnabled(v)
    Config.Enabled = v and true or false
    refreshUI()
    print("[PlayerAimbot] Enabled =", Config.Enabled)
end

btn.MouseButton1Click:Connect(function()
    setEnabled(not Config.Enabled)
end)

-- Phím tắt
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if Config.ToggleKey and input.KeyCode == Config.ToggleKey then
        setEnabled(not Config.Enabled)
    end
end)

refreshUI()

-- ===================== HELPERS =====================
local function getHRP(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model.PrimaryPart
end

local function isAlive(char)
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health > 0 end
    return false
end

local function getCharPos()
    local char = LP.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

-- Trả về character (Model) của player gần nhất, bỏ qua LocalPlayer
local function getClosestTarget()
    local origin = getCharPos()
    if not origin then return nil end

    local best, bestDist = nil, math.huge
    local maxD = Config.MaxDistance or 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local skip = false

            -- team check
            if Config.TeamCheck and plr.Team ~= nil and plr.Team == LP.Team then
                skip = true
            end

            local char = plr.Character
            if not skip and char and char.Parent then
                if not Config.PreferAlive or isAlive(char) then
                    local hrp = getHRP(char)
                    if hrp then
                        local d = (hrp.Position - origin).Magnitude
                        if (maxD <= 0 or d <= maxD) and d < bestDist then
                            bestDist = d
                            best = char
                        end
                    end
                end
            end
        end
    end

    return best
end

local function makeAimCFrame(hrp)
    local pos = hrp.Position
    local vel = hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
    local div = Config.PredictDivisor
    if not div or div == 0 then div = 0.5 end
    return CFrame.new(pos, pos + (vel / div))
end

local function updateAim()
    if not Config.Enabled then
        CurrentTarget = nil
        return
    end
    local target = getClosestTarget()
    CurrentTarget = target
    if not target then return end
    local hrp = getHRP(target)
    if not hrp then return end
    getgenv().AimPos = makeAimCFrame(hrp)
end

RunService.Heartbeat:Connect(function()
    pcall(updateAim)
end)

-- ===================== HOOK RemoteEvent (Skill + Fruit M1) =====================
pcall(function()
    local MT = getrawmetatable(game)
    local oldNamecall = MT.__namecall
    setreadonly(MT, false)

    MT.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = { ... }

        if Config.Enabled
            and method == "FireServer"
            and typeof(self) == "Instance"
            and self.Name == "RemoteEvent"
            and getgenv().AimPos
            and typeof(getgenv().AimPos) == "CFrame"
            and tostring(getgenv().AimPos.X) ~= "nan"
        then
            if #args == 1 then
                if typeof(args[1]) == "Vector3" then
                    args[1] = getgenv().AimPos.Position
                elseif typeof(args[1]) == "CFrame" then
                    args[1] = getgenv().AimPos
                end
            end
            return oldNamecall(self, unpack(args))
        end

        return oldNamecall(self, ...)
    end)

    setreadonly(MT, true)
    log("RemoteEvent hook OK")
end)

-- ===================== HOOK Gun =====================
pcall(function()
    local CombatUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatUtil"))
    if not CombatUtil or not CombatUtil.GetTargetPosition then return end
    local oldGet = CombatUtil.GetTargetPosition
    CombatUtil.GetTargetPosition = function(...)
        if Config.Enabled then
            local target = CurrentTarget or getClosestTarget()
            if target then
                local hrp = getHRP(target)
                if hrp then return hrp.Position end
            end
        end
        return oldGet(...)
    end
    log("Gun hook OK")
end)

-- ===================== API =====================
getgenv().MobAimbot_SetEnabled = setEnabled
getgenv().MobAimbot_GetTarget = function()
    return CurrentTarget
end

print("[PlayerAimbot] Loaded — bật/tắt bằng nút trên màn hình (kéo được)")
print("[PlayerAimbot] Phím tắt: RightControl | API: MobAimbot_SetEnabled(true/false)")
