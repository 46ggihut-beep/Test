--// ================= LOAD FLUENT RENEWED =================
local Library = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local InterfaceManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()

local Window = Library:CreateWindow({
    Title = "Topi Hub [ Beta V0.015 ]",
    SubTitle = "by wzarii & AI",
    TabWidth = 160,
    Theme = "Dark",
    Acrylic = false,
    Size = UDim2.fromOffset(530, 400),
    MinimizeKey = Enum.KeyCode.End
})

--// ================= SERVICES (CÁC DỊCH VỤ GAME) =================
-- Khai báo các service cần thiết từ Roblox
local Players = game:GetService("Players") -- Quản lý người chơi
local RunService = game:GetService("RunService") -- Quản lý vòng lặp game
local TweenService = game:GetService("TweenService") -- Tạo hiệu ứng di chuyển mượt
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Lưu trữ dữ liệu đồng bộ
local VirtualUser = game:GetService("VirtualUser") -- Mô phỏng hành động người chơi
local VirtualInputManager = game:GetService("VirtualInputManager") -- Mô phỏng input chuột/bàn phím
local UserInputService = game:GetService("UserInputService") -- [FIX] Cần để track chuột toàn màn hình
--------------------------------------------------------------------
-- FIX MOBILE: Ngăn dropdown chọn item khi kéo scroll list
-- _touchMoved = true khi ngón tay di chuyển > 12px (đang kéo, không phải nhấn)
-- GuardDropdown: wrap Callback dropdown, delay 80ms để check có đang kéo không
--------------------------------------------------------------------
local _touchMoved  = false
local _touchDelta  = 0

UserInputService.TouchStarted:Connect(function()
    _touchMoved = false
    _touchDelta = 0
end)
UserInputService.TouchMoved:Connect(function(input)
    _touchDelta = _touchDelta + input.Delta.Magnitude
    if _touchDelta > 12 then _touchMoved = true end
end)
UserInputService.TouchEnded:Connect(function()
    task.delay(0.12, function()
        _touchMoved = false
        _touchDelta = 0
    end)
end)

-- Bọc Callback của dropdown: trên mobile delay 80ms để phân biệt tap vs scroll
local function GuardDropdown(fn)
    if not UserInputService.TouchEnabled then return fn end
    return function(v)
        local val = v
        task.spawn(function()
            task.wait(0.08)
            if not _touchMoved then fn(val) end
        end)
    end
end


local Workspace = game:GetService("Workspace") -- Không gian game chính
local HttpService = game:GetService("HttpService") -- Encode/Decode JSON cho save settings

-- Biến người chơi
local player = Players.LocalPlayer -- Người chơi hiện tại
local lp = player -- Alias ngắn gọn cho LocalPlayer

--// ================= WORLD SPAWN DATABASE (QUÉT POS SPAWN MOB CẢ WORLD) =================
-- Lưu toàn bộ vị trí spawn (EnemySpawns) của TẤT CẢ mob trong world ngay khi script
-- vừa chạy, để khi farm quest hết mob có thể lục lại pos đã lưu mà tween tới, không
-- phụ thuộc vào việc khu vực đó có đang active/loaded ngay lúc đó hay không.
-- Dữ liệu KHÔNG BAO GIỜ bị xóa — mỗi lần quét chỉ lưu đè (merge thêm) vào, giữ
-- nguyên toàn bộ pos đã từng quét được từ trước đó.
if not getgenv().WorldSpawnData then
    getgenv().WorldSpawnData = {} -- [tenMob] = { CFrame, CFrame, ... }
end

local function ScanWorldSpawns()
    local spawnsFolder = Workspace:FindFirstChild("_WorldOrigin")
        and Workspace._WorldOrigin:FindFirstChild("EnemySpawns")
    if not spawnsFolder then return end

    -- Dùng GetDescendants() để quét HẾT mọi cấp con cháu trong EnemySpawns
    -- (không chỉ children cấp 1), phòng khi pos spawn nằm trong folder/model
    -- lồng nhau theo từng khu vực → không bỏ sót pos nào của cả world.
    for _, part in ipairs(spawnsFolder:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Tên object thực tế có dạng "Isle Outlaw [Lv. 2450]" hoặc
            -- "Beautiful Pirate [Lv. 1950] [Boss]" — cắt bỏ hết phần "[...]"
            -- phía sau để lấy đúng tên mob thuần (khớp với Mon/NameMon quest)
            local rawName = part.Name
            local name = rawName:match("^(.-)%s*%[") or rawName
            if name == "" then
                name = rawName
            end
            -- Nếu tên vẫn là tên generic (Part/Union/Spawn...) thì lấy tên
            -- object cha (model/folder bọc ngoài) làm tên mob thay thế
            if name:match("^Part%d*$") or name:match("^Union%d*$")
                or name:match("^Spawn%d*$") or name == "SpawnLocation" then
                name = (part.Parent and part.Parent ~= spawnsFolder and part.Parent.Name) or name
            end

            local p  = part.Position
            local cf = CFrame.new(p.X, p.Y + 25, p.Z)

            local list = getgenv().WorldSpawnData[name]
            if not list then
                list = {}
                getgenv().WorldSpawnData[name] = list
            end

            -- Tránh lưu trùng lặp cùng 1 vị trí (khoảng cách < 3 stud = coi như trùng)
            local isDup = false
            for _, existingCF in ipairs(list) do
                if (existingCF.Position - cf.Position).Magnitude < 3 then
                    isDup = true
                    break
                end
            end
            if not isDup then
                table.insert(list, cf)
            end
        end
    end
end
getgenv().ScanWorldSpawns = ScanWorldSpawns

-- Quét ngay lập tức lúc script vừa load (bắt toàn bộ pos spawn hiện có trong world)
task.spawn(function()
    -- Chờ Workspace sẵn sàng (phòng khi _WorldOrigin chưa kịp replicate lúc vừa join)
    for i = 1, 20 do
        if Workspace:FindFirstChild("_WorldOrigin") then break end
        task.wait(0.5)
    end
    pcall(ScanWorldSpawns)
end)

--// ================= KIỂM TRA WORLD (THẾ GIỚI) =================
-- Xác định người chơi đang ở World nào dựa vào PlaceId
local World1 = game.PlaceId == 2753915549 or game.PlaceId == 85211729168715 -- Thế giới 1 (First Sea)
local World2 = game.PlaceId == 4442272183 or game.PlaceId == 79091703265657 -- Thế giới 2 (Second Sea)
local World3 = game.PlaceId == 7449423635 or game.PlaceId == 100117331123089 -- Thế giới 3 (Third Sea)
local DungeonPlaceId = 73902483975735 -- PlaceId của Dungeon

-- Xác định team của người chơi (Pirates hoặc Marines)
local TeamSelf = player.Team and player.Team.Name or "Pirates"

--------------------------------------------------------------------
-- ĐẢO TRUNG GIAN (INTERMEDIATE ISLANDS) - Dùng để tele nhanh khi farm xa
--------------------------------------------------------------------
local IntermediateIslands = {}

if World1 then
    IntermediateIslands = {
        {
            name = "Sky2",
            pos = Vector3.new(-4607.82, 872.58, -1667.56),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    -- Y từ Cobalt bị lỗi format (879039...); dùng 872.039 gần portal Sky2
                    Event:InvokeServer("requestEntrance", Vector3.new(-4607.8232421875, 872.039099121094, -1667.5570068359))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Sky") end)
            end
        },
        {
            name = "UnderWater",
            pos = Vector3.new(61163.85, 5.34, 1819.78),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(61163.8515625, 11.68000793457, 1819.7840576172))
                end)
            end
        },
        {
            name = "Whirlpool",
            pos = Vector3.new(3864.69, 5.41, -1926.21),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(3864.6879882812, 15.7369995117188, -1926.2139892578))
                end)
            end
        },
        {
            name = "Sky3",
            pos = Vector3.new(-7894.62, 5545.49, -380.2),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-7894.6181640625, 5560.1420898438, -380.29098510742))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Sky2") end)
            end
        },
    }
elseif World2 then
    IntermediateIslands = {
        {
            name = "GhostShipGate",
            pos = Vector3.new(-6505.30, 150.22, -126.66),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-6508.5581054688, 150.035003662109, -132.83999633789))
                end)
            end
        },
        {
            name = "GhostShip",
            pos = Vector3.new(923.21, 170.98, 32852.83),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(923.21301269531, 170.9759979248, 32852.83203125))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Ship") end)
            end
        },
        {
            name = "FlamingoMansion",
            pos = Vector3.new(-287.53, 350.17, 597.60),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-286.98596191406, 350.13739013672, 597.89910888672))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Bar") end)
            end
        },
        {
            name = "FlamingoRoom",
            pos = Vector3.new(2284.01, 150.19, 908.03),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(2284.9091796875, 50.537796020508, 905.46417236328))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "DressTown") end)
            end
        },
    }
elseif World3 then
    IntermediateIslands = {
        {
            name = "HouseHydarIsland",
            pos = Vector3.new(5661.53, 1080.41, -334.96),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function() Event:InvokeServer("GetUnlockables") end)
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(5650.9477539062, 1080.2747802734, -350.3791809082))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Hydra1") end)
            end
        },
        {
            name = "Mansion",
            pos = Vector3.new(-12463.81, 450.95, -7550.29),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function() Event:InvokeServer("GetUnlockables") end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "BigMansion") end)
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-12463.602539062, 400.32705688477, -7566.0830078125))
                end)
            end
        },
        {
            name = "CastleOnTheSea",
            pos = Vector3.new(-5047.54, 380.55, -3159.34),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function() Event:InvokeServer("GetUnlockables") end)
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-5060.4116210938, 340.50201416016, -3193.2248535156))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "SeaCastle") end)
            end
        },
        {
            -- Tiki: pos đích trung gian. request đặc biệt xử lý trong doIntermediateTeleport
            name = "Tiki",
            pos = Vector3.new(-16813.44, 80.32, 304.87),
            special = "Tiki",
            request = function()
                -- Placeholder: logic multi-step chạy trong doIntermediateTeleport
            end
        },
    }
else
    -- Fallback về World 1 nếu không xác định được
    IntermediateIslands = {
        {
            name = "Sky2",
            pos = Vector3.new(-4607.82, 872.58, -1667.56),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-4607.8232421875, 872.039099121094, -1667.5570068359))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Sky") end)
            end
        },
        {
            name = "UnderWater",
            pos = Vector3.new(61163.85, 5.34, 1819.78),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(61163.8515625, 11.68000793457, 1819.7840576172))
                end)
            end
        },
        {
            name = "Whirlpool",
            pos = Vector3.new(3864.69, 5.41, -1926.21),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(3864.6879882812, 15.7369995117188, -1926.2139892578))
                end)
            end
        },
        {
            name = "Sky3",
            pos = Vector3.new(-7894.62, 5545.49, -380.2),
            request = function()
                local Event = game:GetService("ReplicatedStorage").Remotes.CommF_
                pcall(function()
                    Event:InvokeServer("requestEntrance", Vector3.new(-7894.6181640625, 5560.1420898438, -380.29098510742))
                end)
                pcall(function() Event:InvokeServer("SetLastSpawnPoint", "Sky2") end)
            end
        },
    }
end

-- Ngưỡng khoảng cách (studs) để kích hoạt tele trung gian
-- Nếu khoảng cách đến đích > ngưỡng này → tele trung gian trước
local INTERMEDIATE_THRESHOLD = 3000

--------------------------------------------------------------------
-- HÀM LẤY ĐẢO TRUNG GIAN TỐI ƯU
-- Tìm đảo trung gian gần đích nhất VÀ gần hơn khoảng cách thẳng a→b
-- Tham số:
--   a: Vector3 vị trí hiện tại của player
--   b: Vector3 vị trí đích cần đến
-- Trả về: island table {name, pos} nếu tìm được, nil nếu không
--------------------------------------------------------------------
local function getIntermediateTeleport(a, b)
    -- Khoảng cách XZ thẳng từ player đến đích
    local directDist = (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
    local best, bestDist = nil, math.huge

    for _, island in ipairs(IntermediateIslands) do
        -- Nếu tắt Tele Tiki thì bỏ Tiki khỏi danh sách đảo trung gian.
        -- Tiki vẫn tồn tại như một đảo bình thường để các chức năng khác
        -- có thể tween/di chuyển tới đó, chỉ không được chọn làm trung gian.
        local isTiki = island.special == "Tiki" or island.name == "Tiki"
        if not (isTiki and not getgenv().TeleTiki) then
            -- Khoảng cách XZ từ đảo trung gian đến đích
            local d = (Vector2.new(island.pos.X, island.pos.Z) - Vector2.new(b.X, b.Z)).Magnitude
            if d < bestDist then
                bestDist = d
                best = island
            end
        end
    end

    -- Chỉ dùng đảo trung gian nếu nó thực sự gần đích hơn player hiện tại
    if best and bestDist < directDist then
        return best
    end
    return nil
end

--------------------------------------------------------------------
-- FLY STATE VARIABLES (chest-style)
-- shouldTween       : true khi fly được phép chạy
-- currentTween      : tween đang chạy hiện tại (nil = đứng yên)
-- currentTweenSpeed : tốc độ của tween hiện tại (để phát hiện đổi speed)
-- currentTweenTarget: vị trí đích của tween hiện tại (để phát hiện mob di chuyển)
--------------------------------------------------------------------
local shouldTween        = false
local currentTween       = nil
local currentTweenSpeed  = 0
local currentTweenTarget = nil  -- Vector3 đích, dùng để phát hiện mob đổi hướng

--------------------------------------------------------------------
-- HÀM TELEPORT SPAM ĐẾN ĐẢO TRUNG GIAN
-- Spam CFrame trong khoảng thời gian ngắn để đảm bảo đến nơi
-- Tham số:
--   position: Vector3 vị trí đích
--   duration: thời gian spam (giây)
--------------------------------------------------------------------
local function teleportSpam(position, duration)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local t = tick() + duration
    while tick() < t do
        hrp.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
        task.wait()
    end
end

--------------------------------------------------------------------
-- HÀM KIỂM TRA VÀ THỰC HIỆN TELE TRUNG GIAN
-- Gọi hàm này trước mỗi lần tween xa để tiết kiệm thời gian
-- Tham số:
--   targetPos: Vector3 vị trí đích cần đến
-- Trả về: true nếu đã tele trung gian, false nếu không cần
--------------------------------------------------------------------
local _lastIntermediateTele = 0  -- Cooldown tracker
local INTERMEDIATE_COOLDOWN = 3  -- Giây giữa các lần tele trung gian
local _intermediateRunning  = false  -- Guard: ngăn _tp tween trong lúc đang spam TP

--------------------------------------------------------------------
-- HÀM TELE TRUNG GIAN (ASYNC)
-- Sơ đồ:
--   1. Xác định đảo trung gian gần đích nhất
--   2. Dừng tween (cancel currentTween)
--   3. World2/3: gọi island.request() (requestEntrance remote) nếu xa đảo;
--      nếu đã gần đảo (< 500 stud) → bỏ qua tele, để caller tween thẳng.
--      World1 (không có request): spam CFrame như cũ.
--   4. Delay nhỏ sau remote / spam
--   5. Tắt _intermediateRunning → tự gọi _tp tween đến đích thật
-- Nhận targetCF + speed để tự gọi _tp ở bước 5, không để caller gọi.
-- Trả về true nếu đã spawn async (caller KHÔNG gọi _tp thêm),
--         false nếu bỏ qua (caller tự gọi _tp như bình thường).
--------------------------------------------------------------------
local function doIntermediateTeleport(targetCF, speed)
    -- Toggle tắt → bỏ qua
    if not getgenv().TelePorto then return false end

    -- Guard: đang chạy rồi → bỏ qua (caller không gọi _tp lúc này)
    if _intermediateRunning then return true end

    -- Cooldown
    if tick() - _lastIntermediateTele < INTERMEDIATE_COOLDOWN then return false end

    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local targetPos = targetCF.Position
    local playerPos = hrp.Position
    local dist = (Vector2.new(playerPos.X, playerPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude

    -- Chỉ tele trung gian khi khoảng cách vượt ngưỡng
    if dist < INTERMEDIATE_THRESHOLD then return false end

    -- Tìm đảo trung gian tối ưu
    local island = getIntermediateTeleport(playerPos, targetPos)
    if not island then return false end

    -- Khoảng cách XZ tới đảo trung gian
    local distToIsland = (Vector2.new(playerPos.X, playerPos.Z) - Vector2.new(island.pos.X, island.pos.Z)).Magnitude

    -- Đã gần điểm trung gian (< 500 stud) → không remote / không spam,
    -- để caller tween thẳng đến đích (giống logic chest farm)
    if distToIsland < 500 then
        return false
    end

    -- Đặt cờ + cooldown ngay lập tức trước khi spawn
    _intermediateRunning = true
    _lastIntermediateTele = tick()

    task.spawn(function()
        -- Bước 1: Dừng tween đang chạy
        if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
        currentTweenSpeed  = 0
        currentTweenTarget = nil

        print("🚀 Tele trung gian → " .. island.name .. " (dist=" .. math.floor(dist) .. ", distIsland=" .. math.floor(distToIsland) .. ")")

        -- ── SPECIAL: Tiki ──────────────────────────────────────────────
        -- 1) remote tele CastleOnTheSea
        -- 2) tween/spam tới portal pos (-5097.83, 316.54, -3181.23)
        -- 3) delay 0.3
        -- 4) đợi player tới Tiki pos rồi mới tween đích
        if island.special == "Tiki" or island.name == "Tiki" then
            local tikiPos   = Vector3.new(-16813.44, 80.32, 304.87)
            local portalPos = Vector3.new(-5097.83, 316.54, -3181.23)

            -- 1) Remote CastleOnTheSea
            pcall(function()
                local Event = ReplicatedStorage.Remotes.CommF_
                Event:InvokeServer("GetUnlockables")
                Event:InvokeServer("requestEntrance", Vector3.new(-5060.4116210938, 340.50201416016, -3193.2248535156))
                Event:InvokeServer("SetLastSpawnPoint", "SeaCastle")
            end)
            task.wait(0.2)

            -- 2) Đưa player tới portal pos gần Castle
            do
                local deadline = tick() + 8
                while tick() < deadline do
                    local c = player.Character
                    local h = c and c:FindFirstChild("HumanoidRootPart")
                    if h then
                        if (h.Position - portalPos).Magnitude <= 15 then break end
                        h.CFrame = CFrame.new(portalPos + Vector3.new(0, 2, 0))
                    end
                    task.wait()
                end
            end

            -- 3) Delay 0.3
            task.wait(0.3)

            -- 4) Đợi / đưa player tới Tiki pos
            do
                local deadline = tick() + 12
                while tick() < deadline do
                    local c = player.Character
                    local h = c and c:FindFirstChild("HumanoidRootPart")
                    if h then
                        local d = (Vector2.new(h.Position.X, h.Position.Z) - Vector2.new(tikiPos.X, tikiPos.Z)).Magnitude
                        if d <= 80 then break end
                        -- nếu server chưa tele → spam CFrame về Tiki
                        h.CFrame = CFrame.new(tikiPos + Vector3.new(0, 2, 0))
                    end
                    task.wait()
                end
            end

            print("✅ Đã tới Tiki trung gian — tiếp tục tween đích")
        elseif type(island.request) == "function" then
            -- World2/3 thường: remote requestEntrance
            pcall(island.request)
            task.wait(0.15)
        else
            -- World1 / không request: spam CFrame
            local spamDuration = distToIsland < 5000 and 0.3 or 2
            local deadline = tick() + spamDuration
            while tick() < deadline do
                local c = player.Character
                local h = c and c:FindFirstChild("HumanoidRootPart")
                if h then
                    h.CFrame = CFrame.new(island.pos + Vector3.new(0, 2, 0))
                end
                task.wait()
            end
            if distToIsland >= 5000 then
                task.wait(0.2)
            end
        end

        -- Bước 5: Mở khoá rồi tween thẳng đến đích thật
        _intermediateRunning = false
        _tp(targetCF, speed)
    end)

    return true  -- Đã spawn → caller không gọi _tp thêm
end

--// ================= TOGGLE BUTTON UI (ĐÃ FIX DRAG) =================
local screenGui = Instance.new("ScreenGui", game.CoreGui)
screenGui.Name = "ControlGUI"
screenGui.ResetOnSpawn = false      -- [FIX] không bị xóa khi nhân vật respawn
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647 -- [FIX] luôn nổi trên cùng, không bị UI khác che mất nút toggle

local toggleButton = Instance.new("ImageButton", screenGui)
toggleButton.Size = UDim2.new(0, 50, 0, 50)
toggleButton.Position = UDim2.new(0.15, 0, 0.15, 0)
toggleButton.Image = "rbxassetid://89099965623104"
-- [FIX] Trước đây BackgroundTransparency = 1 -> nếu ảnh trên lỗi/không load được
-- (asset bị xoá/kiểm duyệt/không hiện trên máy nào đó) thì cả nút trở nên VÔ HÌNH
-- hoàn toàn, dù nó vẫn tồn tại và vẫn nhận click bình thường ("ControlUI không hiện").
-- Nên luôn có 1 cái nền tròn hiển thị sẵn làm fallback, ảnh nếu load được sẽ đè lên trên.
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
toggleButton.BackgroundTransparency = 0.1
toggleButton.ZIndex = 999
toggleButton.Active = true   -- [FIX] Bắt buộc phải có để nhận input
toggleButton.Draggable = false -- [FIX] Tắt built-in Draggable (buggy), dùng manual drag

local _tbCorner = Instance.new("UICorner", toggleButton)
_tbCorner.CornerRadius = UDim.new(1, 0) -- bo tròn thành hình tròn dễ nhận biết

-- [FIX] Viền cầu vồng chạy quanh nút để LUÔN nhận biết được vị trí nút,
-- kể cả khi ảnh icon bị mất/trong suốt hoàn toàn.
local _tbStroke = Instance.new("UIStroke", toggleButton)
_tbStroke.Color = Color3.fromRGB(255, 0, 0)
_tbStroke.Thickness = 3
_tbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local _tbGradient = Instance.new("UIGradient", _tbStroke)
_tbGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
})

-- Quay gradient liên tục để tạo hiệu ứng cầu vồng "chạy" quanh viền
RunService.RenderStepped:Connect(function(dt)
    _tbGradient.Rotation = (_tbGradient.Rotation + dt * 150) % 360
end)

-- [FIX] Chữ fallback "UI" hiện phía sau ảnh -- chỉ lộ ra rõ nếu ảnh lỗi/trong suốt,
-- còn nếu ảnh load được thì gần như bị ảnh che hết (ảnh vẽ đè lên trên do được add sau)
local _tbLabel = Instance.new("TextLabel", toggleButton)
_tbLabel.BackgroundTransparency = 1
_tbLabel.Size = UDim2.new(1, 0, 1, 0)
_tbLabel.Text = "UI"
_tbLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
_tbLabel.Font = Enum.Font.GothamBold
_tbLabel.TextScaled = true
_tbLabel.ZIndex = 998

-- [FIX] Biến drag
local dragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil

-- [FIX] Bắt đầu drag khi nhấn chuột vào button
toggleButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = toggleButton.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

-- [FIX] Lưu input di chuyển mới nhất từ button
toggleButton.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

-- [FIX] Track chuột toàn màn hình bằng UserInputService
-- Đây là phần quan trọng nhất: khi kéo ra ngoài button vẫn hoạt động
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

-- [FIX] Đảm bảo drag tắt khi nhả chuột ở bất kỳ đâu
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- [FIX] Nút bật/tắt UI trước đây chỉ gọi Window:Minimize() mỗi lần bấm.
-- Nếu hàm Minimize() của thư viện KHÔNG phải là toggle 2 chiều (chỉ có tác dụng ẩn,
-- không tự hiện lại), thì bấm lần 2 sẽ không làm gì cả -> UI bị ẩn vĩnh viễn ("tắt là tắt luôn").
-- Cách fix: tự quản lý trạng thái ẩn/hiện ở phía script, và khi cần HIỆN lại,
-- thử lần lượt nhiều cách (Maximize(), set Window.Minimized = false, rồi mới fallback
-- về Minimize() như toggle) để đảm bảo luôn có cách đưa UI hiện lại được.
local _uiHidden = false

local function _ShowUI()
    local ok = pcall(function() Window:Maximize() end)
    if not ok then
        ok = pcall(function() Window.Minimized = false end)
    end
    if not ok then
        -- fallback cuối: coi Minimize() như toggle
        pcall(function() Window:Minimize() end)
    end
end

local function _HideUI()
    pcall(function() Window:Minimize() end)
end

toggleButton.MouseButton1Click:Connect(function()
    _uiHidden = not _uiHidden
    if _uiHidden then
        _HideUI()
    else
        _ShowUI()
    end
end)

-- [FIX] Phím dự phòng: nếu vì lý do gì đó nút bấm bị che/kẹt, luôn có thể
-- nhấn phím End (trùng MinimizeKey) để bật lại UI. Đồng bộ luôn biến _uiHidden
-- để 2 cách bật/tắt (nút bấm và phím) không bị lệch trạng thái với nhau.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.End then
        _uiHidden = not _uiHidden
    end
end)

--// ================= TABS (CÁC TAB GIAO DIỆN) =================
local Tabs = {
    Settings   = Window:CreateTab({Title = "cài đặt",      Icon = "settings"}),
    Main       = Window:CreateTab({Title = "Farming",       Icon = "sword"}),
    Quests     = Window:CreateTab({Title = "Stack Farming", Icon = "scroll-text"}),
    Stats      = Window:CreateTab({Title = "Stats",         Icon = "bar-chart-2"}),
    Status     = Window:CreateTab({Title = "Status",        Icon = "activity"}),
    FarmOther  = Window:CreateTab({Title = "Farming Other", Icon = "layers"}),
    FruitRaid  = Window:CreateTab({Title = "Dungeon",       Icon = "skull"}),
    Travel     = Window:CreateTab({Title = "Travel",        Icon = "map-pin"}),
    Shop       = Window:CreateTab({Title = "Shop",          Icon = "shopping-cart"}),
}

--------------------------------------------------------------------
-- TOGGLE CALLBACK REGISTRY
-- Lưu Callback của mọi toggle để LoadConfig có thể gọi thủ công.
-- Lý do: Fluent-Renewed SetValue() chỉ cập nhật visual, KHÔNG fire Callback.
--------------------------------------------------------------------
local _ToggleCBs = {}

-- Monkey-patch CreateToggle trên tất cả tab để tự động thu thập callback
local function _PatchTab(tab)
    local orig = tab.CreateToggle
    tab.CreateToggle = function(self, id, opts)
        if opts and type(opts.Callback) == "function" then
            _ToggleCBs[id] = opts.Callback
        end
        return orig(self, id, opts)
    end
end
for _, t in pairs(Tabs) do _PatchTab(t) end


-- Các biến điều khiển chế độ farm
getgenv().FarmLevel = false
getgenv().FarmBone = false
getgenv().FarmKata = false
getgenv().FarmAura = false
getgenv().FarmTyrant = false
getgenv().FarmPhaBinh = false
getgenv().FarmDungeon = false
getgenv().AcceptQuestC = false
getgenv().BypassAcceptQuest = false
getgenv().FarmEliteHunt = false  -- Tự động farm Elite Quest (Diablo/Urban/Deandre)

-- FLAGS FOR MATERIAL FARM (Farm nguyên liệu)
getgenv().AutoMaterial = false
getgenv().SelectMaterial = nil
local MMon = {}
local MPos = nil

-- FLAGS FOR STATS UPGRADE (Nâng cấp chỉ số)
getgenv().Auto_Melee = false      -- Tự động cộng điểm Melee (Đấm đá)
getgenv().Auto_Sword = false      -- Tự động cộng điểm Sword (Kiếm)
getgenv().Auto_Gun = false        -- Tự động cộng điểm Gun (Súng)
getgenv().Auto_DevilFruit = false -- Tự động cộng điểm Devil Fruit (Trái ác quỷ)
getgenv().Auto_Defense = false    -- Tự động cộng điểm Defense (Phòng thủ)
getgenv().pSats = 10              -- Số điểm cộng mỗi lần (mặc định 10)
local Sec = 0.1                   -- Thời gian delay giữa các lần cộng điểm

--------------------------------------------------------------------
-- LOGIC HỦY QUEST CŨ (QUAN TRỌNG)
--------------------------------------------------------------------
-- HÀM KIỂM TRA VÀ HỦY QUEST KHÔNG KHỚP VỚI MỤC TIÊU FARM
-- Mục đích: Khi cấp độ của người chơi cao hơn quest hiện tại,
-- hoặc khi đang farm mob khác với quest đang nhận, hàm này sẽ tự động hủy quest cũ
-- Tham số:
--   questData: Bảng chứa thông tin quest mới cần nhận
--              questData[5] = Tên của mob trong quest (ví dụ: "Bandit", "Monkey")
-- Trả về:
--   true: Đã hủy quest cũ thành công
--   false: Không cần hủy quest (quest đã khớp hoặc không có quest)
local function CheckAndAbandonWrongQuest(questData)
    -- Bước 1: Kiểm tra xem người chơi có giao diện quest không
    local questGui = player.PlayerGui:FindFirstChild("Main")
    if not questGui or not questGui:FindFirstChild("Quest") then
        -- Không tìm thấy GUI quest, trả về false
        return false
    end
    
    local quest = questGui.Quest
    -- Bước 2: Kiểm tra quest có đang hiển thị không
    if not quest.Visible then
        -- Quest không visible, nghĩa là chưa nhận quest nào
        return false
    end
    
    -- Bước 3: Lấy tiêu đề quest hiện tại từ GUI
    local questContainer = quest.Container
    if not questContainer then return false end
    
    local questTitle = questContainer:FindFirstChild("QuestTitle")
    if not questTitle then return false end
    
    local titleText = questTitle:FindFirstChild("Title")
    if not titleText then return false end
    
    local currentQuestTitle = titleText.Text
    
    -- Bước 4: So sánh quest hiện tại với mob mục tiêu cần farm
    -- Nếu tên mob KHÔNG nằm trong tiêu đề quest hiện tại -> quest sai, cần hủy
    if not string.find(currentQuestTitle, questData[5]) then
        pcall(function()
            -- Gọi remote để hủy quest
            if ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                ReplicatedStorage.Remotes.CommF_:InvokeServer("AbandonQuest")
                print("⚠️ Đã hủy quest cũ không khớp: " .. currentQuestTitle)
                print("✅ Chuẩn bị nhận quest mới cho mob: " .. questData[5])
                task.wait(0.5) -- Đợi server xử lý việc hủy quest
                return true
            end
        end)
        return true
    end
    
    -- Quest hiện tại đã đúng, không cần hủy
    return false
end

--------------------------------------------------------------------
-- HÀM KIỂM TRA CẤP ĐỘ NGƯỜI CHƠI VỚI YÊU CẦU QUEST
--------------------------------------------------------------------
-- Mục đích: Kiểm tra xem người chơi đã vượt cấp quest chưa
-- Nếu đã vượt cấp -> hủy quest cũ để nhận quest phù hợp hơn
-- Tham số:
--   questData: Thông tin quest (questData[1] = Level tối thiểu, questData[2] = Level tối đa)
-- Trả về:
--   true: Cấp đã quá quest hiện tại, nên hủy
--   false: Cấp vẫn phù hợp với quest
local function CheckLevelForQuest(questData)
    local myLevel = player.Data.Level.Value or 1
    
    -- Nếu cấp người chơi cao hơn cấp tối đa của quest
    if myLevel > questData[2] then
        print("📊 Level hiện tại (" .. myLevel .. ") đã cao hơn quest (" .. questData[2] .. ")")
        return true -- Nên hủy quest này
    end
    
    return false -- Level vẫn phù hợp
end

--------------------------------------------------------------------
-- TẠO DANH SÁCH NGUYÊN LIỆU THEO WORLD
--------------------------------------------------------------------
-- Mỗi World có các loại nguyên liệu khác nhau để farm
-- Danh sách này sẽ được dùng trong dropdown menu cho người chơi chọn
local MaterialList = {}
if World1 then
    -- Nguyên liệu có trong World 1 (First Sea)
    MaterialList = {
        "Angel Wings",           -- Cánh thiên thần
        "Leather + Scrap Metal", -- Da + Sắt vụn
        "Magma Ore",            -- Quặng Magma
        "Fish Tail"             -- Đuôi cá
    }
elseif World2 then
    -- Nguyên liệu có trong World 2 (Second Sea)
    MaterialList = {
        "Leather + Scrap Metal",  -- Da + Sắt vụn
        "Magma Ore",             -- Quặng Magma
        "Ectoplasm",             -- Chất linh hồn
        "Mystic Droplet",        -- Giọt thần bí
        "Radioactive Material",  -- Vật liệu phóng xạ
        "Vampire Fang"           -- Nanh ma cà rồng
    }
elseif World3 then
    -- Nguyên liệu có trong World 3 (Third Sea)
    MaterialList = {
        "Scrap Metal",      -- Sắt vụn
        "Fish Tail",        -- Đuôi cá
        "Conjured Cocoa",   -- Cacao huyền bí
        "Dragon Scale",     -- Vảy rồng
        "Gunpowder",        -- Thuốc súng
        "Mini Tusk",        -- Ngà nhỏ
        "Demonic Wisp"      -- Linh hồn ác ma
    }
end

--------------------------------------------------------------------
-- CÁC BIẾN CẤU HÌNH FARM (FARM SETTINGS)
--------------------------------------------------------------------
getgenv().BringMob = true           -- Bật tính năng kéo mob lại gần (giúp farm nhanh hơn)
getgenv().FlySpeed = 280            -- Tốc độ bay (càng cao bay càng nhanh, nhưng dễ bị phát hiện)
getgenv().FlyHeight = 30            -- Độ cao bay so với mob (tránh bị đánh)
getgenv().BringRange = 300          -- Phạm vi kéo mob (khoảng cách tối đa để bring mob)
getgenv().TargetRange = 10000       -- Phạm vi tìm kiếm mob mục tiêu
getgenv().Noclip = false            -- Xuyên tường (tắt va chạm với địa hình)
getgenv().TelePorto = false         -- Bật/tắt tele trung gian khi tween xa
getgenv().TeleTiki = true              -- Cho phép dùng Tiki làm đảo trung gian (W3)

getgenv().IsFarming = false         -- Trạng thái đang farm (true = đang farm, false = dừng)
getgenv().AutoBusoLoop = false      -- Tự động bật Buso Haki liên tục
getgenv().FastAttack = false        -- Auto Attack (mac dinh tat)
getgenv().CurrentTargetMob = nil    -- Mob đang được nhắm mục tiêu hiện tại


--// ================= GUI LOGIC =================
local SelectedFarm = "Farm cấp"

local function CheckWorldRequirement(farmType)
    if farmType == "Farm bone" or farmType == "Farm kata" or farmType == "Tyrant of the Skie" then
        if not World3 then
            Library:Notify({
                Title = "Sai World",
                Content = "Chức năng này chỉ hoạt động ở World 3!",
                Duration = 5
            })
            return false
        end
    end
    return true
end

-- SECTION 1: LEVEL FARM
Tabs.Main:AddSection("Level Farm")

Tabs.Main:CreateDropdown("FarmType", {
    Title = "Chọn loại Farm",
    Values = {"Farm cấp", "Farm bone", "Farm kata", "Farm aura", "Tyrant of the Skie"},
    Default = 1,
    Callback = GuardDropdown(function(v)
        SelectedFarm = v
        -- Chỉ xử lý restart nếu đang farm VÀ AutoFarm đang bật
        if not getgenv().IsFarming then return end
        if not (getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
                or getgenv().FarmAura or getgenv().FarmTyrant) then return end

        if not CheckWorldRequirement(v) then
            getgenv().IsFarming = false
            return
        end

        -- Chạy trong coroutine: dừng farm cũ, delay 1s, bật farm mới
        task.spawn(function()
            -- Dừng toàn bộ farm đang chạy + reset tất cả flag
            stopLevelFarm(); stopBoneFarm(); stopKataFarm()
            stopAuraFarm(); stopTyrantFarm(); stopPhaBinhFarm()
            stopFly()
            getgenv().FarmLevel  = false
            getgenv().FarmBone   = false
            getgenv().FarmKata   = false
            getgenv().FarmAura   = false
            getgenv().FarmTyrant = false

            -- Delay 1 giây trước khi bật farm mới
            task.wait(0.3)

            -- Đảm bảo người dùng chưa tắt toggle trong lúc chờ
            if not getgenv().IsFarming then return end

            -- Bật flag và start farm mới theo loại đã chọn
            if v == "Farm cấp" then
                getgenv().FarmLevel = true
                startFly(); startLevelFarm()
            elseif v == "Farm bone" then
                getgenv().FarmBone = true
                startFly(); startBoneFarm()
            elseif v == "Farm kata" then
                getgenv().FarmKata = true
                startFly(); startKataFarm()
            elseif v == "Farm aura" then
                getgenv().FarmAura = true
                startFly(); startAuraFarm()
            elseif v == "Tyrant of the Skie" then
                getgenv().FarmTyrant = true
                startFly(); startTyrantFarm()
            end
        end)
    end),
})

Tabs.Main:CreateToggle("AutoFarm", {
    Title = "Tự động Farm (Level/Boss)",
    Default = false,
    Callback = function(v)
        getgenv().FarmLevel = false
        getgenv().FarmBone = false
        getgenv().FarmKata = false
        getgenv().FarmAura = false
        getgenv().FarmTyrant = false
        getgenv().FarmPhaBinh = false
        getgenv().AutoMaterial = false
        
        getgenv().Noclip = v
        getgenv().IsFarming = v
        getgenv().AutoBusoLoop = v
        
        if v and not CheckWorldRequirement(SelectedFarm) then
            getgenv().IsFarming = false
            return
        end

        if SelectedFarm == "Farm cấp" then
            getgenv().FarmLevel = v
        elseif SelectedFarm == "Farm bone" then
            getgenv().FarmBone = v
        elseif SelectedFarm == "Farm kata" then
            getgenv().FarmKata = v
        elseif SelectedFarm == "Farm aura" then
            getgenv().FarmAura = v
        elseif SelectedFarm == "Tyrant of the Skie" then
            getgenv().FarmTyrant = v
        end

        if v then
            startFly()
            if SelectedFarm == "Farm cấp" then
                startLevelFarm()
            elseif SelectedFarm == "Farm kata" then
                startKataFarm()
            elseif SelectedFarm == "Farm bone" then
                startBoneFarm()
            elseif SelectedFarm == "Farm aura" then
                startAuraFarm()
            elseif SelectedFarm == "Tyrant of the Skie" then
                startTyrantFarm()
            end
        else
            -- UI callbacks may run before fly functions are defined.
            if type(stopFly) == "function" then stopFly() end
            if type(stopLevelFarm) == "function" then stopLevelFarm() end
            if type(stopBoneFarm) == "function" then stopBoneFarm() end
            if type(stopKataFarm) == "function" then stopKataFarm() end
            if type(stopAuraFarm) == "function" then stopAuraFarm() end
            if type(stopTyrantFarm) == "function" then stopTyrantFarm() end
            if type(stopPhaBinhFarm) == "function" then stopPhaBinhFarm() end
        end
    end
})

Tabs.Main:CreateToggle("AcceptQuest", {
    Title = "Accept Quests (Manual)",
    Description = "Tự động nhận nhiệm vụ cho Bone/Kata",
    Default = false,
    Callback = function(v)
        getgenv().AcceptQuestC = v
    end
})

Tabs.Main:CreateToggle("BypassAcceptQuest", {
    Title = "Bypass AcceptQuest",
    Description = "Nhận quest ngay tại chỗ, không cần tween tới vị trí NPC quest",
    Default = false,
    Callback = function(v)
        getgenv().BypassAcceptQuest = v
    end
})

-- SECTION: BONES / GRAVESTONE
Tabs.Main:AddSection("Bones / Gravestone")

local ToggleRandomBones = Tabs.Main:AddToggle("AutoRandomBones", {
    Title = "Auto Random Bones",
    Description = "",
    Default = false
})
ToggleRandomBones:OnChanged(function(Value)
    _G.Auto_Random_Bone = Value
end)
spawn(function()
    while wait(Sec) do
        pcall(function()
            if _G.Auto_Random_Bone then
                repeat
                    task.wait()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("Bones", "Buy", 1, 1)
                until not _G.Auto_Random_Bone
            end
        end)
    end
end)

local ToggleTryLuck = Tabs.Main:AddToggle("AutoTryLuckGravestone", {
    Title = "Auto Try Luck Gravestone",
    Description = "",
    Default = false
})
ToggleTryLuck:OnChanged(function(Value)
    _G.TryLucky = Value
end)
spawn(function()
    while wait(Sec) do
        if _G.TryLucky then
            local try_bones_luck = CFrame.new(-8761.3154296875, 164.85829162598, 6161.1567382813)
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                if (hrp.Position - try_bones_luck.Position).Magnitude > 5 then
                    _tp(try_bones_luck)
                else
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("gravestoneEvent", 1)
                end
            end
        end
    end
end)

local TogglePray = Tabs.Main:AddToggle("AutoPrayGravestone", {
    Title = "Auto Pray Gravestone",
    Description = "",
    Default = false
})
TogglePray:OnChanged(function(Value)
    _G.Praying = Value
end)
spawn(function()
    while wait(Sec) do
        if _G.Praying then
            local try_bones_luck = CFrame.new(-8761.3154296875, 164.85829162598, 6161.1567382813)
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                if (hrp.Position - try_bones_luck.Position).Magnitude > 5 then
                    _tp(try_bones_luck)
                else
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("gravestoneEvent", 2)
                end
            end
        end
    end
end)

-- SECTION 2: MATERIAL FARM
Tabs.Main:AddSection("Material Farm")

Tabs.Main:CreateDropdown("SelectMaterial", {
    Title = "Chọn Nguyên Liệu (" .. (World1 and "W1" or World2 and "W2" or "W3") .. ")",
    Values = MaterialList,
    Default = 1,
    Callback = GuardDropdown(function(v)
        getgenv().SelectMaterial = v
    end),
})

Tabs.Main:CreateToggle("AutoMaterial", {
    Title = "Auto Farm Material",
    Default = false,
    Callback = function(v)
        getgenv().AutoMaterial = v
        
        getgenv().IsFarming = v 
        getgenv().Noclip = v
        getgenv().AutoBusoLoop = v
        
        if v then
            getgenv().FarmLevel = false
            stopLevelFarm()
            startFly()
        else
            -- UI callbacks may run before fly functions are defined.
            if type(stopFly) == "function" then stopFly() end
        end
    end
})

--// ================= SETTINGS TAB =================
Tabs.Settings:AddSection("Settings / Configure")

local _Weapon = {
    "Melee",
    "Sword",
    "Blox Fruit",
    "Gun"
}

local Weapon_Config = Tabs.Settings:CreateDropdown("Weapon_Config", {
    Title = "Chọn Vũ Khí",
    Values = _Weapon,
    Multi = false,
    Default = 1,
    Callback = GuardDropdown(function(Value)
        _G.ChooseWP = Value
    end),
})

_G.ChooseWP = "Melee"
_G.SelectWeapon = nil

-- ===== REMOVE CARD-RELATED GLOBALS (AutoPickCard features removed) =====

Tabs.Settings:CreateSlider("SpeedTween", {
    Title = "Speed Tween",
    Description = "Tốc độ bay / tween (0 - 300)",
    Default = 280,
    Min = 0,
    Max = 300,
    Rounding = 1,
    Callback = function(v)
        getgenv().FlySpeed = v
    end,
})



--------------------------------------------------------------------
-- FAST ATTACK (Standalone) — điều khiển bởi toggle Auto Attack
--------------------------------------------------------------------
getgenv().FastAttack = getgenv().FastAttack or false

local FastAttackModule = {}
local HitRegistrationModule = {}
local MainController = {}

do
    local GameService = game
    local Players = GameService:GetService("Players")
    local RunService = GameService:GetService("RunService")
    local ReplicatedStorage = GameService:GetService("ReplicatedStorage")
    local Workspace = GameService:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer

    local function SafeWaitForChild(parent, childName)
        local success, result = pcall(function()
            return parent:WaitForChild(childName)
        end)
        return result
    end

    local Enemies = SafeWaitForChild(Workspace, "Enemies") or Instance.new("Folder")
    local Characters = SafeWaitForChild(Workspace, "Characters") or Instance.new("Folder")
    local Modules = SafeWaitForChild(ReplicatedStorage, "Modules") or Instance.new("Folder")
    local Net = SafeWaitForChild(Modules, "Net") or Instance.new("Folder")

    FastAttackModule.Rate = 0.000000002
    FastAttackModule.Enabled = false
    FastAttackModule.MaxDistance = 60

    local _faRateRunning = false
    local _faHBConn = nil
    local _faCharConn = nil

    local function GetCharacter()
        local character = LocalPlayer.Character
        if not character or not character.Parent then
            character = LocalPlayer.CharacterAdded:Wait()
        end
        return character
    end

    function FastAttackModule.IsAlive(target)
        local humanoid = target:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health > 0 then
            return true
        end
        return false
    end

    function FastAttackModule.GetNearbyTargets(character, folder)
        if not folder or not folder:IsA("Instance") then
            return {}
        end
        local characterPosition = character:GetPivot().Position
        local nearbyTargets = {}
        local children = folder:GetChildren()
        for i = 1, #children do
            local target = children[i]
            if target:IsA("Model") then
                local humanoid = target:FindFirstChild("Humanoid")
                local rootPart = target:FindFirstChild("HumanoidRootPart")
                if humanoid and rootPart and humanoid.Health > 0 and target ~= character then
                    local distance = (rootPart.Position - characterPosition).Magnitude
                    if distance <= FastAttackModule.MaxDistance then
                        table.insert(nearbyTargets, target)
                    end
                end
            end
        end
        return nearbyTargets
    end

    function FastAttackModule.GetTargetParts(targetList)
        local result = {}
        local count = #targetList
        for i = 1, count do
            local target = targetList[i]
            local head = target:FindFirstChild("Head") or target.PrimaryPart
            if head then
                table.insert(result, {target, head})
            end
        end
        return result
    end

    function FastAttackModule.GetAllTargets(character)
        local enemies = FastAttackModule.GetNearbyTargets(character, Enemies)
        local otherCharacters = FastAttackModule.GetNearbyTargets(character, Characters)
        local allTargets = {}
        for i = 1, #enemies do
            table.insert(allTargets, enemies[i])
        end
        for i = 1, #otherCharacters do
            table.insert(allTargets, otherCharacters[i])
        end
        return allTargets
    end

    function FastAttackModule.ExecuteFastAttack()
        if not FastAttackModule.Enabled then return end
        local character = GetCharacter()
        if not character then return end
        local tool = character:FindFirstChildOfClass("Tool")
        if not tool then return end
        local targets = FastAttackModule.GetAllTargets(character)
        if #targets < 1 then return end
        local targetParts = FastAttackModule.GetTargetParts(targets)
        if #targetParts < 1 then return end
        local attackRemote = Net:FindFirstChild("RE/RegisterAttack")
        local hitRemote = Net:FindFirstChild("RE/RegisterHit")
        if attackRemote and hitRemote then
            pcall(function()
                attackRemote:FireServer(FastAttackModule.Rate)
                local targetHead = targetParts[1][2]
                hitRemote:FireServer(targetHead, targetParts)
            end)
        end
    end

    local AttackRemoteTarget
    local AttackRemoteId

    local function InitializeHitRegistration()
        local foldersToCheck = {
            ReplicatedStorage:FindFirstChild("Util"),
            ReplicatedStorage:FindFirstChild("Common"),
            ReplicatedStorage:FindFirstChild("Remotes"),
            ReplicatedStorage:FindFirstChild("Assets"),
            ReplicatedStorage:FindFirstChild("FX")
        }
        for _, folder in ipairs(foldersToCheck) do
            if folder and folder:IsA("Instance") then
                local children = folder:GetChildren()
                for _, child in ipairs(children) do
                    if child:IsA("RemoteEvent") and child:GetAttribute("Id") then
                        AttackRemoteTarget = child
                        AttackRemoteId = child:GetAttribute("Id")
                    end
                end
                folder.ChildAdded:Connect(function(child)
                    if child:IsA("RemoteEvent") and child:GetAttribute("Id") then
                        AttackRemoteTarget = child
                        AttackRemoteId = child:GetAttribute("Id")
                    end
                end)
            end
        end
    end

    InitializeHitRegistration()

    function HitRegistrationModule.Execute()
        if not FastAttackModule.Enabled then return end
        local character = GetCharacter()
        if not character then return end
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end
        local hitTargets = {}
        local function ScanFolder(folder)
            if not folder or not folder:IsA("Instance") then return end
            local children = folder:GetChildren()
            for i = 1, #children do
                local target = children[i]
                if target:IsA("Model") then
                    local humanoid = target:FindFirstChild("Humanoid")
                    local rootPart = target:FindFirstChild("HumanoidRootPart")
                    if humanoid and rootPart and humanoid.Health > 0 and target ~= character then
                        local distance = (rootPart.Position - humanoidRootPart.Position).Magnitude
                        if distance <= FastAttackModule.MaxDistance then
                            local targetChildren = target:GetChildren()
                            for _, child in ipairs(targetChildren) do
                                if child:IsA("BasePart") then
                                    table.insert(hitTargets, {target, child})
                                end
                            end
                        end
                    end
                end
            end
        end
        ScanFolder(Enemies)
        ScanFolder(Characters)
        local tool = character:FindFirstChildOfClass("Tool")
        if #hitTargets > 0 and tool and (tool:GetAttribute("WeaponType") == "Melee" or tool:GetAttribute("WeaponType") == "Sword") then
            pcall(function()
                local seed = Modules.Net.seed:InvokeServer()
                local attackRemote = Net:FindFirstChild("RE/RegisterAttack")
                local hitRemote = Net:FindFirstChild("RE/RegisterHit")
                if attackRemote and hitRemote then
                    attackRemote:FireServer()
                    local targetHead = hitTargets[1][1]:FindFirstChild("Head")
                    if not targetHead then return end
                    hitRemote:FireServer(targetHead, hitTargets, {})
                    if AttackRemoteTarget then
                        local remoteCode = "RE/RegisterHit"
                        local encryptionKey = math.floor(Workspace:GetServerTimeNow() / 10 % 10) + 1
                        local encodedString = string.gsub(remoteCode, ".", function(char)
                            return string.char(bit32.bxor(string.byte(char), encryptionKey))
                        end)
                        local finalId = bit32.bxor(AttackRemoteId + 909090, seed * 2)
                        cloneref(AttackRemoteTarget):FireServer(
                            encodedString,
                            finalId,
                            targetHead,
                            hitTargets
                        )
                    end
                end
            end)
        end
    end

    local function DisableCameraShake()
        pcall(function()
            local cameraModule = require(ReplicatedStorage.Util.CameraShaker)
            cameraModule:Stop()
        end)
    end

    local function StartMainLoops()
        if not _faRateRunning then
            _faRateRunning = true
            task.spawn(function()
                while FastAttackModule.Enabled do
                    task.wait(FastAttackModule.Rate)
                    if not FastAttackModule.Enabled then break end
                    pcall(FastAttackModule.ExecuteFastAttack)
                end
                _faRateRunning = false
            end)
        end
        if _faHBConn then
            pcall(function() _faHBConn:Disconnect() end)
            _faHBConn = nil
        end
        _faHBConn = RunService.Heartbeat:Connect(function()
            if not FastAttackModule.Enabled then
                if _faHBConn then
                    pcall(function() _faHBConn:Disconnect() end)
                    _faHBConn = nil
                end
                return
            end
            pcall(HitRegistrationModule.Execute)
        end)
    end

    function MainController.Start()
        if FastAttackModule.Enabled then return end
        FastAttackModule.Enabled = true
        getgenv().FastAttack = true
        pcall(DisableCameraShake)
        StartMainLoops()
        if not _faCharConn then
            _faCharConn = LocalPlayer.CharacterAdded:Connect(function()
                -- keep running after respawn; loops already check Enabled flag
            end)
        end
        print("Fast Attack System Started!")
    end

    function MainController.Stop()
        FastAttackModule.Enabled = false
        getgenv().FastAttack = false
        if _faHBConn then
            pcall(function() _faHBConn:Disconnect() end)
            _faHBConn = nil
        end
        -- rate loop exits itself when Enabled = false
        print("Fast Attack System Stopped!")
    end

    getgenv()._startFastAttackFn = MainController.Start
    getgenv()._stopFastAttackFn = MainController.Stop
end

--------------------------------------------------------------------
-- TOGGLE: AUTO ATTACK
-- Bật: loop kích hoạt Fast Attack. Tắt: hủy / dừng attack.
--------------------------------------------------------------------
Tabs.Settings:CreateToggle("Initialize", {
    Title = "Auto Attack",
    Default = false,
    Callback = function(v)
        getgenv().FastAttack = v
        if v then
            if getgenv()._startFastAttackFn then
                getgenv()._startFastAttackFn()
            end
        else
            if getgenv()._stopFastAttackFn then
                getgenv()._stopFastAttackFn()
            end
        end
    end
})

Tabs.Settings:CreateToggle("BringMob", {
    Title = "Bring Mob",
    Default = true,
    Callback = function(v)
        getgenv().BringMob = v
    end
})

Tabs.Settings:CreateToggle("BuddhaFarm", {
    Title = "Buddha Farm",
    Description = "Bật: Tự động kích hoạt Buddha khi farm (nếu đang dùng fruit Buddha). Tắt: Farm bình thường không bật Buddha.",
    Default = false,
    Callback = function(v)
        getgenv().BuddhaFarm = v
    end
})

Tabs.Settings:CreateToggle("AutoRaceV3", {
    Title = "Auto Active Race V3",
    Description = "T\225\187\177 \196\144\225\187\153ng B\225\186\173t T\225\187\153c V3",
    Default = false,
    Callback = function(v)
        _G.AutoRaceV3 = v
    end
})

spawn(function()
    while wait() do
        pcall(function()
            if _G.AutoRaceV3 then
                game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("ActivateAbility")
            end
        end)
    end
end)

Tabs.Settings:CreateToggle("AutoRaceV4", {
    Title = "Auto Active Race V4",
    Description = "T\225\187\177 \196\144\225\187\153ng B\225\186\173t T\225\187\153c V4",
    Default = false,
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
                    VirtualInputManager:SendKeyEvent(true, "Y", false, game)
                    wait()
                    VirtualInputManager:SendKeyEvent(false, "Y", false, game)
                end
            end
        end)
    end
end)

--------------------------------------------------------------------
-- TOGGLE: TELEPORT PORTO (TELEPORT TRUNG GIAN)
-- Bật: trước mỗi lần tween xa (> 3000 stud XZ) sẽ dừng tween,
--      spam teleport đến đảo trung gian gần đích nhất, rồi mới tween đi.
-- Tắt: tween thẳng đến đích, không tele trung gian.
--------------------------------------------------------------------
Tabs.Settings:CreateToggle("TelePorto", {
    Title = "Teleport Porto",
    Description = "Bật: dùng tele trung gian khi tween xa (> 3000 stud). Tắt: tween thẳng không tele trung gian.",
    Default = false,
    Callback = function(v)
        getgenv().TelePorto = v
    end
})

Tabs.Settings:CreateToggle("TeleTiki", {
    Title = "Tele Tiki",
    Description = "Bật: dùng Tiki làm đảo trung gian. Tắt: Tiki là đảo bình thường, không dùng làm tele trung gian.",
    Default = true,
    Callback = function(v)
        getgenv().TeleTiki = v
    end
})


--// ================= STATUS TAB =================
Tabs.Status:AddSection("Generals Quests / Items")

--------------------------------------------------------------------
-- DEVIL FRUIT STATUS DISPLAY
--------------------------------------------------------------------
local v70 = Tabs.Status:CreateParagraph("DevilFruitStatus", {
    Title = "Devil Fruit",
    Content = "Loading..."
})

spawn(function()
    while wait() do
        pcall(function()
            local lp = game:GetService("Players").LocalPlayer
            local fruitName = lp.Data.DevilFruit.Value
            if (lp.Character and lp.Character:FindFirstChild(fruitName)) or lp.Backpack:FindFirstChild(fruitName) then
                v70:SetContent("Devil Fruit: " .. fruitName)
            else
                v70:SetContent("Not Have Devil Fruit")
            end
        end)
    end
end)

--------------------------------------------------------------------
-- BUDDHA FRUIT LOGIC
--------------------------------------------------------------------
-- Kiem tra fruit hien tai co phai Buddha khong
local function IsBuddhaFruit()
    local ok, result = pcall(function()
        return player.Data.DevilFruit.Value
    end)
    if ok and result then
        return string.lower(result) == "buddha" or string.find(string.lower(result), "buddha") ~= nil
    end
    return false
end

-- Trang bi Buddha fruit va kich hoat skill Z
-- BuddhaTransforming = true: nhan vat dung im, cac farm loop khong duoc di chuyen/attack
local function ActivateBuddha()
    pcall(function()
        local char = player.Character
        local backpack = player.Backpack
        if not char or not backpack then return end

        -- Danh dau dang trong qua trinh transform, farm loop se dung im
        getgenv().BuddhaTransforming = true

        -- Giai phong vu khi hien tai (neu co) de tranh xung dot voi skill Z
        local currentTool = char:FindFirstChildOfClass("Tool")
        if currentTool then
            currentTool.Parent = backpack
        end
        task.wait(0.1)

        -- Tim va trang bi Blox Fruit tu backpack
        local buddhaItem = nil
        for _, v in pairs(backpack:GetChildren()) do
            if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then
                buddhaItem = v
                break
            end
        end

        if buddhaItem then
            char.Humanoid:EquipTool(buddhaItem)
        end

        -- Delay 0.3 giay cho fruit duoc equip on dinh
        task.wait(0.3)

        -- Bam skill Z de kich hoat Buddha transform
        VirtualInputManager:SendKeyEvent(true, "Z", false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, "Z", false, game)

        -- ** QUAN TRONG **: Doi 0.5 giay sau khi Z de animation hoan tat
        -- Trong thoi gian nay nhan vat dung im, khong trang bi weapon farm
        task.wait(0.5)

        -- Tat flag: cho phep farm loop trang bi weapon va di chuyen binh thuong
        getgenv().BuddhaTransforming = false
        print("Buddha Z skill activated - ready to farm!")
    end)
end

-- Tat Buddha: tra fruit ve backpack sau khi stop farm
local function DeactivateBuddha()
    pcall(function()
        local char = player.Character
        if not char then return end
        for _, v in pairs(char:GetChildren()) do
            if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then
                v.Parent = player.Backpack
                break
            end
        end
    end)
end

getgenv().BuddhaActive = false
getgenv().BuddhaTransforming = false  -- Khi true: nhan vat dung im, farm loop khong di chuyen/attack
getgenv().BuddhaFarm = false           -- Khi true: kích hoạt Buddha khi bắt đầu farm (nếu có fruit Buddha)

--------------------------------------------------------------------
-- HÀM NÂNG CẤP CHỈ SỐ (STATS UPGRADE FUNCTION)
--------------------------------------------------------------------
-- Hàm này được gọi để tự động cộng điểm vào các chỉ số kỹ năng
-- Tham số:
--   statType: Loại chỉ số cần cộng ("Melee", "Sword", "Gun", "Devil", "Defense")
--   points: Số điểm muốn cộng mỗi lần
local function statsSetings(statType, points)
    pcall(function()
        -- Kiểm tra có ReplicatedStorage và Remotes không
        if not ReplicatedStorage:FindFirstChild("Remotes") then return end
        if not ReplicatedStorage.Remotes:FindFirstChild("CommF_") then return end
        
        -- Gọi server để cộng điểm
        -- statType: "Melee" (Đấm đá), "Sword" (Kiếm), "Gun" (Súng), 
        --           "Devil" (Trái ác quỷ), "Defense" (Phòng thủ)
        local result = ReplicatedStorage.Remotes.CommF_:InvokeServer("AddPoint", statType, points)
        
        -- Log kết quả (có thể bật để debug)
        -- print("✅ Đã cộng " .. points .. " điểm vào " .. statType)
    end)
end

local MobKilled = Tabs.Status:CreateParagraph("CakePrinceInfo", {
    Title = "Cake Princes :",
    Content = "Killed : ..."
})

spawn(function()
    while task.wait(5) do
        pcall(function()
            if World3 then
                local result = ReplicatedStorage.Remotes.CommF_:InvokeServer("CakePrinceSpawner")
                local killed = tonumber(string.match(tostring(result), "%d+"))
                if killed then
                    MobKilled:SetContent("Killed : " .. (500 - killed))
                end
            end
        end)
    end
end)

--// ================= EYES STATUS (TIKI) =================
local EyesStatus = Tabs.Status:CreateParagraph("EyesStatusInfo", {
    Title = "Check Eyes Status",
    Content = "Loading..."
})

spawn(function()
    while task.wait(1) do
        pcall(function()
            if World3 and workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("TikiOutpost") then
                local eyes = {
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye1"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye2"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye3"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye4")
                }
                local count = 0
                for _, eye in ipairs(eyes) do
                    if eye and eye:IsA("BasePart") and eye.Transparency == 0 then
                        count = count + 1
                    end
                end
                local suffix = (count == 4 and " ✅ Ready (Auto switch)" or "")
                EyesStatus:SetContent("Status: " .. count .. " Eye(s)" .. suffix)
            else
                EyesStatus:SetContent("Not in Tiki Outpost")
            end
        end)
    end
end)

--// ================= AUTO BUSO LOOP =================
spawn(function()
    while task.wait(1) do
        pcall(function()
            if getgenv().IsFarming then
                local hasBuso1 = player.Character and player.Character:FindFirstChild("HasBuso")
                local hasBuso2 = player.Character and player.Character:FindFirstChild("Buso")
                
                if not hasBuso1 and not hasBuso2 then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
                end
            end
        end)
    end
end)

--// ================= CHARACTER FUNCTIONS =================
local function getChar()
    repeat task.wait() until player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return player.Character
end

local function getRoot()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

--// ================= NOCLIP =================
-- Noclip bật khi: getgenv().Noclip = true (farm)
-- HOẶC shouldTween = true (bất kỳ tween nào đang chạy: farm, mua võ, fly đảo, v.v.)
RunService.Stepped:Connect(function()
    if (getgenv().Noclip or shouldTween) and player.Character then
        for _,v in pairs(player.Character:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    end
end)

--// ================= NO STUN (chống stun khi farm) =================
-- Chạy liên tục khi đang farm: fire RemoveStun remote + xóa giá trị Stun trên character
-- Áp dụng cho tất cả farm + fly đảo
task.spawn(function()
    while task.wait(0) do
        pcall(function()
            local isActive = getgenv().IsFarming
                or getgenv().AutoMaterial
                or getgenv().FarmDungeon
            if not isActive then return end

            -- Gọi remote unstun (Blox Fruits dùng CommE FireServer)
            ReplicatedStorage.Remotes.CommE:FireServer("RemoveStun")

            -- Xóa Stun value trực tiếp trên character (phòng khi remote delay)
            local char = player.Character
            if not char then return end

            -- Stun value phổ biến
            local stunVal = char:FindFirstChild("Stun")
            if stunVal and stunVal:IsA("BoolValue") then
                stunVal.Value = false
            end

            -- Debuffs folder
            local debuffs = char:FindFirstChild("Debuffs")
            if debuffs then
                local stunDebuff = debuffs:FindFirstChild("Stun")
                if stunDebuff then stunDebuff:Destroy() end
            end
        end)
    end
end)

--// ================= HÀM CHỌN VŨ KHÍ =================
local function selectWeapon()
    pcall(function()
        if not getgenv().IsFarming and not getgenv().FarmPhaBinh then return end
        -- Khong trang bi weapon trong luc Buddha dang transform (dang bam Z)
        if getgenv().BuddhaTransforming then return end
        
        if _G.ChooseWP == "Melee" then
            for _, v in pairs(player.Backpack:GetChildren()) do
                if v.ToolTip == "Melee" and player.Backpack:FindFirstChild(tostring(v.Name)) then
                    _G.SelectWeapon = v.Name
                    break
                end
            end
        elseif _G.ChooseWP == "Sword" then
            for _, v in pairs(player.Backpack:GetChildren()) do
                if v.ToolTip == "Sword" and player.Backpack:FindFirstChild(tostring(v.Name)) then
                    _G.SelectWeapon = v.Name
                    break
                end
            end
        elseif _G.ChooseWP == "Gun" then
            for _, v in pairs(player.Backpack:GetChildren()) do
                if v.ToolTip == "Gun" and player.Backpack:FindFirstChild(tostring(v.Name)) then
                    _G.SelectWeapon = v.Name
                    break
                end
            end
        elseif _G.ChooseWP == "Blox Fruit" then
            for _, v in pairs(player.Backpack:GetChildren()) do
                if v.ToolTip == "Blox Fruit" and player.Backpack:FindFirstChild(tostring(v.Name)) then
                    _G.SelectWeapon = v.Name
                    break
                end
            end
        end
        
        if _G.SelectWeapon and player.Character then
            local weapon = player.Backpack:FindFirstChild(_G.SelectWeapon)
            if weapon then
                player.Character.Humanoid:EquipTool(weapon)
            end
        end
    end)
end

--// ================= SKILL UTILITIES (PHÁ BÌNH) =================
local function sendSkillKey(key)
    if not VirtualInputManager then return end
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function equipAndUseSkills(toolType)
    if not getgenv().FarmPhaBinh then return end
    local char = player.Character
    local backpack = player.Backpack
    if not char or not backpack then return end
    
    for _, item in pairs(backpack:GetChildren()) do
        if item:IsA("Tool") and item.ToolTip == toolType then
            item.Parent = char
            task.wait(0.12)
            
            local skills = {"Z", "X"}
            if toolType == "Melee" then skills = {"Z", "X", "C"} end
            if toolType == "Blox Fruit" then skills = {"Z", "X", "C", "V", "F"} end
            if toolType == "Gun" then skills = {"Z", "X"} end
            
            for _, skill in ipairs(skills) do
                if not getgenv().FarmPhaBinh then break end
                pcall(sendSkillKey, skill)
                task.wait(0.12)
            end
            
            item.Parent = backpack
            break
        end
    end
end

--// ================= HELPER FUNCTIONS =================
-- ============================================================
-- LÕI FLY MỚI (_tp) - Topi Chest style, tích hợp cho Topi Hub
-- - Khi đang tween đúng speed → để chạy tiếp, không cancel/recreate
-- - Khi speed đổi → cancel và tạo tween mới
-- ============================================================

local function _tp(targetCF, speed)
    if not shouldTween then return end
    if _intermediateRunning then return end  -- Đang tele trung gian → không tween
    if getgenv().BuddhaTransforming then return end
    local char = player.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end

    local dist = (targetCF.Position - hrp.Position).Magnitude

    if dist < 1 then return end  -- Đã đến nơi, không cần làm gì

    -- Cách đích ≤ 150 stud → tăng tốc lên 500 để vào tới nơi nhanh hơn
    local effectiveSpeed = speed
    if dist <= 100 then
        effectiveSpeed = 600
    end

    -- ── Xa đích: tween, cập nhật khi mob di chuyển ──
    -- Cancel + tạo tween mới nếu: chưa có tween, đổi speed,
    -- hoặc mob đã di chuyển > 3 studs so với đích cũ
    local needUpdate = (not currentTween)
        or (currentTweenSpeed ~= effectiveSpeed)
        or (currentTweenTarget == nil)
        or ((currentTweenTarget - targetCF.Position).Magnitude > 3)

    if not needUpdate then return end

    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
    currentTweenSpeed  = effectiveSpeed
    currentTweenTarget = targetCF.Position
    currentTween = TweenService:Create(hrp,
        TweenInfo.new(dist / effectiveSpeed, Enum.EasingStyle.Linear),
        {CFrame = targetCF})
    currentTween:Play()
    currentTween.Completed:Once(function()
        currentTween       = nil
        currentTweenTarget = nil
    end)
end

-- Backward-compat aliases (tham số root/obj bỏ qua, hrp lấy nội bộ)
local function FlyMove(_, cf, speed) _tp(cf, speed) end
local function TweenObject(_, cf, speed) _tp(cf, speed) end

local function CalculateHeight(mobPosition)
    if _G.ChooseWP == "Blox Fruit" then
        return mobPosition.Y + 10  -- Fruit: Y+10
    end
    if _G.ChooseWP == "Melee" or _G.ChooseWP == "Sword" then
        return mobPosition.Y + 40  -- Melee/Sword: Y+40
    end
    return mobPosition.Y + 30  -- Gun/mặc định: Y+30
end

--------------------------------------------------------------------
-- HÀM TÍNH CFRAME FARM
-- Up: Y+40 (Melee/Sword) / Y+30 (Gun) / Y+10 (Blox Fruit), đứng thẳng trên mob
--------------------------------------------------------------------
local function GetFarmCFrame(mob)
    if not mob or not mob:FindFirstChild("HumanoidRootPart") then return nil end
    local mobHRP  = mob.HumanoidRootPart
    local mobPos  = mobHRP.Position
    local mobCF   = mobHRP.CFrame

    local lookRaw  = Vector3.new(mobCF.LookVector.X, 0, mobCF.LookVector.Z)
    local lookFlat = lookRaw.Magnitude > 0.01 and lookRaw.Unit or Vector3.new(0, 0, 1)

    local targetPos

    -- Đứng thẳng trên mob (không lệch X/Z)
    if _G.ChooseWP == "Blox Fruit" then
        targetPos = Vector3.new(mobPos.X, mobPos.Y + 10, mobPos.Z)
    elseif _G.ChooseWP == "Melee" or _G.ChooseWP == "Sword" then
        targetPos = Vector3.new(mobPos.X, mobPos.Y + 40, mobPos.Z)
    else
        targetPos = Vector3.new(mobPos.X, mobPos.Y + 30, mobPos.Z)
    end

    return CFrame.new(targetPos, targetPos + lookFlat)
end

local function GetNearestEnemy(enemyNames)
    local root = getRoot()
    if not root then return nil end
    local nearest, dist = nil, math.huge
    local enemies = workspace.Enemies:GetChildren()
    for _, mob in pairs(enemies) do
        if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local isTarget = false
            if type(enemyNames) == "table" then
                for _, name in pairs(enemyNames) do
                    if mob.Name == name then isTarget = true; break end
                end
            elseif mob.Name == enemyNames then
                isTarget = true
            end
            if isTarget then
                local mag = (mob.HumanoidRootPart.Position - root.Position).Magnitude
                if mag < dist then
                    dist = mag
                    nearest = mob
                end
            end
        end
    end
    return nearest
end

local function GetAnyEnemy()
    local root = getRoot()
    if not root then return nil end
    local nearest, dist = nil, math.huge
    for _, mob in pairs(workspace.Enemies:GetChildren()) do
        if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local mag = (mob.HumanoidRootPart.Position - root.Position).Magnitude
            if mag < dist then
                dist = mag
                nearest = mob
            end
        end
    end
    return nearest
end

local function AttackEnemy(enemy)
    -- Khong attack khi Buddha dang transform: nhan vat phai dung im
    if getgenv().BuddhaTransforming then return end
    if enemy and enemy:FindFirstChild("Humanoid") and enemy.Humanoid.Health > 0 then
        pcall(function()
            if getgenv().IsFarming or getgenv().FarmPhaBinh then selectWeapon() end
            ReplicatedStorage.Remotes.Combat:FireServer(enemy)
        end)
    end
end

--// ===================== BRING ENEMY (Heartbeat — TELEPORT, mỗi 0.2s) =====================
-- KHÔNG lock look pos: mỗi 0.2s teleport mob farm + TẤT CẢ mob cùng loại
-- trong BringRange thẳng về VỊ TRÍ HIỆN TẠI (live) của chính mob đang farm.
-- Không dùng tween/BodyVelocity — chỉ teleport.
-- Không bring nếu có player khác trong 500 stud quanh player.
-- SpinBring ON: teleport + orbit bán kính 5 quanh mob farm.
--------------------------------------------------------------------
local _spinAngle = 0
_G.SpinBring = _G.SpinBring or false

local MAX_BRING_RANGE = 300 -- Giới hạn cứng: chỉ bring mob trong phạm vi 200 stud
local BRING_INTERVAL = 0.2  -- Bring mob mỗi 0.2 giây 1 lần
local _bringAccum = 0

-- Noclip cho mob khi bị bring: tắt CanCollide toàn bộ BasePart của mob để
-- không bị kẹt/văng ra khi bị teleport chồng lên nhau hoặc dính địa hình
local function NoclipMob(mob)
    for _, v in ipairs(mob:GetDescendants()) do
        if v:IsA("BasePart") and v.CanCollide then
            v.CanCollide = false
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not getgenv().BringMob then return end

    _bringAccum = _bringAccum + dt
    if _bringAccum < BRING_INTERVAL then return end
    _bringAccum = 0

    local targetMob = getgenv().CurrentTargetMob
    if not targetMob or not targetMob.Parent then return end

    local anyFarmActive = getgenv().IsFarming or getgenv().AutoMaterial
        or getgenv().FarmDungeon or getgenv().FarmEliteHunt
        or getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
        or getgenv().FarmAura or getgenv().FarmTyrant
    if not anyFarmActive then return end

    -- Vị trí bring = vị trí HIỆN TẠI của mob farm (live, không lock)
    local targetHRP = targetMob:FindFirstChild("HumanoidRootPart")
    local targetHum = targetMob:FindFirstChild("Humanoid")
    if not targetHRP or not targetHum or targetHum.Health <= 0 then return end
    local center = targetHRP.Position

    local myChar = player.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    -- Không bring nếu có player khác trong 500 stud
    for _, op in ipairs(Players:GetPlayers()) do
        if op ~= player then
            local oc = op.Character
            local oh = oc and oc:FindFirstChild("HumanoidRootPart")
            if oh and (oh.Position - myHRP.Position).Magnitude <= 500 then
                return
            end
        end
    end

    local SPIN_RADIUS = 5
    local mobName = targetMob.Name
    -- Giới hạn cứng 200 stud, dù getgenv().BringRange có bị chỉnh cao hơn
    local bringRange = math.min(getgenv().BringRange or MAX_BRING_RANGE, MAX_BRING_RANGE)

    -- Thu thập: mob cùng loại trong range (không teleport mob farm - nó chính
    -- là mốc center nên đứng yên tại chỗ)
    local allMobs = {}
    for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
        if enemy ~= targetMob then
            local hum = enemy:FindFirstChild("Humanoid")
            local hrp = enemy:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 and hrp.Parent and enemy.Name == mobName then
                if (hrp.Position - myHRP.Position).Magnitude <= bringRange then
                    table.insert(allMobs, enemy)
                end
            end
        end
    end

    if #allMobs == 0 then return end

    pcall(function()
        sethiddenproperty(player, "SimulationRadius", math.huge)
    end)

    if _G.SpinBring then
        -- Spin: teleport orbit quanh mob farm
        _spinAngle = _spinAngle + (300 / SPIN_RADIUS) * BRING_INTERVAL
        local n = #allMobs
        for i, mob in ipairs(allMobs) do
            pcall(function()
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                local hum = mob:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end
                -- dọn BV cũ nếu còn
                local bv = hrp:FindFirstChild("_MobFlyBV")
                if bv then bv:Destroy() end
                NoclipMob(mob)
                local angle = _spinAngle + (2 * math.pi / n) * (i - 1)
                local orbitPos = Vector3.new(
                    center.X + SPIN_RADIUS * math.cos(angle),
                    center.Y,
                    center.Z + SPIN_RADIUS * math.sin(angle)
                )
                hrp.CFrame = CFrame.new(orbitPos)
                hrp.Velocity = Vector3.zero
                hrp.CanCollide = false
                hum.WalkSpeed = 0
                hum.JumpPower = 0
            end)
        end
    else
        -- Teleport thẳng mọi mob cùng loại về vị trí hiện tại của mob farm
        for _, mob in ipairs(allMobs) do
            pcall(function()
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                local hum = mob:FindFirstChild("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then return end
                local bv = hrp:FindFirstChild("_MobFlyBV")
                if bv then bv:Destroy() end
                NoclipMob(mob)
                hrp.CFrame = CFrame.new(center)
                hrp.Velocity = Vector3.zero
                hrp.CanCollide = false
                hum.WalkSpeed = 0
                hum.JumpPower = 0
            end)
        end
    end
end)


--// ================= FLY =================
-- Chest-style: BodyVelocity (MaxForce 1e5) được quản lý bởi vòng lặp bên dưới.
-- startFly / stopFly chỉ cần bật/tắt shouldTween và cancel tween.

-- Vòng lặp tự động tạo/xoá BodyVelocity khi IsFarming thay đổi
task.spawn(function()
    while task.wait(0.2) do
        pcall(function()
            local char = player.Character; if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
            if getgenv().IsFarming or getgenv().AutoMaterial then
                if not hrp:FindFirstChild("BodyClip") then
                    local bv = Instance.new("BodyVelocity")
                    bv.Name     = "BodyClip"
                    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                    bv.Velocity = Vector3.zero
                    bv.Parent   = hrp
                end
            else
                local bc = hrp:FindFirstChild("BodyClip")
                if bc then bc:Destroy() end
            end
        end)
    end
end)

function startFly()
    shouldTween = true
end

function stopFly()
    shouldTween = false
    if currentTween then
        pcall(function() currentTween:Cancel() end)
        currentTween       = nil
        currentTweenSpeed  = 0
        currentTweenTarget = nil
    end
    -- Xoá BodyVelocity ngay lập tức (không chờ vòng lặp)
    pcall(function()
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bc = hrp:FindFirstChild("BodyClip")
                if bc then bc:Destroy() end
            end
        end
    end)
end

--// ================= DUAL QUEST PAIRINGS =================
-- Khi người chơi đạt lv của quest cao (Qdata=2), sau khi hoàn thành sẽ xen kẽ
-- nhận quest thấp (Qdata=1) cùng khu vực, rồi quay lại quest cao, lặp lại liên tục.
-- Chỉ áp dụng cho các khu vực có 2 quest cùng vị trí NPC (cùng PosQ).
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
    PiratePortQuest   = {Mon="Pirate Millionaire",    Qdata=1, NameMon="Pirate Millionaire",    PosM=CFrame.new(-246.00,          47.31,       5584.10)},
    DragonCrewQuest   = {Mon="Dragon Crew Warrior",   Qdata=1, NameMon="Dragon Crew Warrior",   PosM=CFrame.new(6709.76367,       52.3442993, -1139.02966)},
    VenomCrewQuest    = {Mon="Hydra Enforcer",        Qdata=1, NameMon="Hydra Enforcer",        PosM=CFrame.new(4547.11523,     1003.10217,     334.194824)},
    MarineTreeIsland  = {Mon="Marine Commodore",      Qdata=1, NameMon="Marine Commodore",      PosM=CFrame.new(2519,            109,          -7633)},
    DeepForestIsland3 = {Mon="Fishman Raider",        Qdata=1, NameMon="Fishman Raider",        PosM=CFrame.new(-10407.526367188, 331.76263427734, -8368.5166015625)},
    DeepForestIsland  = {Mon="Forest Pirate",         Qdata=1, NameMon="Forest Pirate",         PosM=CFrame.new(-13274.478515625, 332.37814331055, -7769.5805664062)},
    DeepForestIsland2 = {Mon="Jungle Pirate",         Qdata=1, NameMon="Jungle Pirate",         PosM=CFrame.new(-12256.16015625,  331.73828125,  -10485.836914062)},
    HauntedQuest1     = {Mon="Reborn Skeleton",       Qdata=1, NameMon="Reborn Skeleton",       PosM=CFrame.new(-8763.7236328125, 165.72299194336,  6159.8618164062)},
    HauntedQuest2     = {Mon="Demonic Soul",          Qdata=1, NameMon="Demonic Soul",          PosM=CFrame.new(-9505.8720703125, 172.10482788086,  6158.9931640625)},
    NutsIslandQuest   = {Mon="Peanut Scout",          Qdata=1, NameMon="Peanut Scout",          PosM=CFrame.new(-2143.2419433594,  47.721984863281,-10029.995117188)},
    IceCreamIslandQuest={Mon="Ice Cream Chef",        Qdata=1, NameMon="Ice Cream Chef",        PosM=CFrame.new(-872.24658203125,  65.81957244873, -10919.95703125)},
    CakeQuest1        = {Mon="Cookie Crafter",        Qdata=1, NameMon="Cookie Crafter",        PosM=CFrame.new(-2374.13671875,    37.798263549805,-12125.30859375)},
    CakeQuest2        = {Mon="Baking Staff",          Qdata=1, NameMon="Baking Staff",          PosM=CFrame.new(-1887.8099365234,  77.618507385254,-12998.350585938)},
    ChocQuest1        = {Mon="Cocoa Warrior",         Qdata=1, NameMon="Cocoa Warrior",         PosM=CFrame.new(-21.553283691406,  80.574996948242,-12352.387695312)},
    ChocQuest2        = {Mon="Sweet Thief",           Qdata=1, NameMon="Sweet Thief",           PosM=CFrame.new(165.1884765625,    76.058853149414,-12600.836914062)},
    TikiQuest1        = {Mon="Isle Outlaw",           Qdata=1, NameMon="Isle Outlaw",           PosM=CFrame.new(-16479.900390625,  226.6117401123,   -300.31143188477)},
    TikiQuest2        = {Mon="Sun-kissed Warrior",    Qdata=1, NameMon="kissed Warrior",        PosM=CFrame.new(-16347,            64,               984)},
    TikiQuest3        = {Mon="Serpent Hunter",        Qdata=1, NameMon="Serpent Hunter",        PosM=CFrame.new(-16645.64,         163.09,          1352.87)},
    SubmergedQuest1   = {Mon="Reef Bandit",           Qdata=1, NameMon="Reef Bandit",           PosM=CFrame.new(11019.1318,      -2146.06812,       9342.3916)},
    SubmergedQuest2   = {Mon="Sea Chanter",           Qdata=1, NameMon="Sea Chanter",           PosM=CFrame.new(10671.2715,      -2057.59155,      10047.2588)},
    SubmergedQuest3   = {Mon="High Disciple",         Qdata=1, NameMon="High Disciple",         PosM=CFrame.new(9750.41602,      -1966.93884,       9753.36035)},
}

--// ================= QUEST DATA FUNCTION =================
local function QuestNeta()
    local I = player.Data.Level.Value
    local Mon, Qdata, Qname, NameMon, PosM, PosQ
    
    if World1 then
        if I == 1 or I <= 9 then
            if tostring(TeamSelf) == "Marines" then
                Mon = "Trainee"
                Qname = "MarineQuest"
                Qdata = 1
                NameMon = "Trainee"
                PosM = CFrame.new(-2709.67944, 24.5206585, 2104.24585, -0.744724929, -3.97967455e-08, -0.667371571, 4.32403588e-08, 1, -1.07884304e-07, .667371571, -1.09201515e-07, -0.744724929)
                PosQ = CFrame.new(-2709.67944, 24.5206585, 2104.24585, -0.744724929, -3.97967455e-08, -0.667371571, 4.32403588e-08, 1, -1.07884304e-07, .667371571, -1.09201515e-07, -0.744724929)
            elseif tostring(TeamSelf) == "Pirates" then
                Mon = "Bandit"
                Qdata = 1
                Qname = "BanditQuest1"
                NameMon = "Bandit"
                PosM = CFrame.new(1045.9626464844, 27.002508163452, 1560.8203125)
                PosQ = CFrame.new(1045.9626464844, 27.002508163452, 1560.8203125)
            end
        elseif I == 10 or I <= 14 then
            Mon = "Monkey"
            Qdata = 1
            Qname = "JungleQuest"
            NameMon = "Monkey"
            PosQ = CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, 0, -1, 0, 0)
            PosM = CFrame.new(-1448.5180664062, 67.853012084961, 11.465796470642)
        elseif I == 15 or I <= 29 then
            Mon = "Gorilla"
            Qdata = 2
            Qname = "JungleQuest"
            NameMon = "Gorilla"
            PosQ = CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, 0, -1, 0, 0)
            PosM = CFrame.new(-1129.8836669922, 40.46354675293, -525.42370605469)
        elseif I == 30 or I <= 39 then
            Mon = "Pirate"
            Qdata = 1
            Qname = "BuggyQuest1"
            NameMon = "Pirate"
            PosQ = CFrame.new(-1141.07483, 4.10001802, 3831.5498, .965929627, 0, -0.258804798, 0, 1, 0, .258804798, 0, .965929627)
            PosM = CFrame.new(-1103.5134277344, 13.752052307129, 3896.0910644531)
        elseif I == 40 or I <= 59 then
            Mon = "Brute"
            Qdata = 2
            Qname = "BuggyQuest1"
            NameMon = "Brute"
            PosQ = CFrame.new(-1141.07483, 4.10001802, 3831.5498, .965929627, 0, -0.258804798, 0, 1, 0, .258804798, 0, .965929627)
            PosM = CFrame.new(-1140.0837402344, 14.809885025024, 4322.9213867188)
        elseif I == 60 or I <= 74 then
            Mon = "Desert Bandit"
            Qdata = 1
            Qname = "DesertQuest"
            NameMon = "Desert Bandit"
            PosQ = CFrame.new(894.488647, 5.14000702, 4392.43359, .819155693, 0, -0.573571265, 0, 1, 0, .573571265, 0, .819155693)
            PosM = CFrame.new(924.7998046875, 6.4486746788025, 4481.5859375)
        elseif I == 75 or I <= 89 then
            Mon = "Desert Officer"
            Qdata = 2
            Qname = "DesertQuest"
            NameMon = "Desert Officer"
            PosQ = CFrame.new(894.488647, 5.14000702, 4392.43359, .819155693, 0, -0.573571265, 0, 1, 0, .573571265, 0, .819155693)
            PosM = CFrame.new(1608.2822265625, 8.6142244338989, 4371.0073242188)
        elseif I == 90 or I <= 99 then
            Mon = "Snow Bandit"
            Qdata = 1
            Qname = "SnowQuest"
            NameMon = "Snow Bandit"
            PosQ = CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, .939684391, 0, 1, 0, -0.939684391, 0, -0.342042685)
            PosM = CFrame.new(1354.3479003906, 87.272773742676, -1393.9465332031)
        elseif I == 100 or I <= 119 then
            Mon = "Snowman"
            Qdata = 2
            Qname = "SnowQuest"
            NameMon = "Snowman"
            PosQ = CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, .939684391, 0, 1, 0, -0.939684391, 0, -0.342042685)
            PosM = CFrame.new(1200, 144, -1550)
        elseif I == 120 or I <= 149 then
            Mon = "Chief Petty Officer"
            Qdata = 1
            Qname = "MarineQuest2"
            NameMon = "Chief Petty Officer"
            PosQ = CFrame.new(-5039.58643, 27.3500385, 4324.68018, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-4881.2309570312, 22.652044296265, 4273.7524414062)
        elseif I == 150 or I <= 174 then
            Mon = "Sky Bandit"
            Qdata = 1
            Qname = "SkyQuest"
            NameMon = "Sky Bandit"
            PosQ = CFrame.new(-4839.53027, 716.368591, -2619.44165, .866007268, 0, .500031412, 0, 1, 0, -0.500031412, 0, .866007268)
            PosM = CFrame.new(-4953.20703125, 295.74420166016, -2899.2290039062)
        elseif I == 175 or I <= 189 then
            Mon = "Dark Master"
            Qdata = 2
            Qname = "SkyQuest"
            NameMon = "Dark Master"
            PosQ = CFrame.new(-4839.53027, 716.368591, -2619.44165, .866007268, 0, .500031412, 0, 1, 0, -0.500031412, 0, .866007268)
            PosM = CFrame.new(-5259.8447265625, 391.39767456055, -2229.0354003906)
        elseif I == 190 or I <= 209 then
            Mon = "Prisoner"
            Qdata = 1
            Qname = "PrisonerQuest"
            NameMon = "Prisoner"
            PosQ = CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, .995993316, -2.06384709e-09, -0.0894274712)
            PosM = CFrame.new(5098.9736328125, -0.3204058110714, 474.23733520508)
        elseif I == 210 or I <= 249 then
            Mon = "Dangerous Prisoner"
            Qdata = 2
            Qname = "PrisonerQuest"
            NameMon = "Dangerous Prisoner"
            PosQ = CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, .995993316, -2.06384709e-09, -0.0894274712)
            PosM = CFrame.new(5654.5634765625, 15.633401870728, 866.29919433594)
        elseif I == 250 or I <= 274 then
            Mon = "Toga Warrior"
            Qdata = 1
            Qname = "ColosseumQuest"
            NameMon = "Toga Warrior"
            PosQ = CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, .857167721, 0, -0.515037298)
            PosM = CFrame.new(-1820.21484375, 51.683856964111, -2740.6650390625)
        elseif I == 275 or I <= 299 then
            Mon = "Gladiator"
            Qdata = 2
            Qname = "ColosseumQuest"
            NameMon = "Gladiator"
            PosQ = CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, .857167721, 0, -0.515037298)
            PosM = CFrame.new(-1292.8381347656, 56.380882263184, -3339.0314941406)
        elseif I == 300 or I <= 324 then
            Mon = "Military Soldier"
            Qdata = 1
            Qname = "MagmaQuest"
            NameMon = "Military Soldier"
            PosQ = CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, .866048813, 0, 1, 0, -0.866048813, 0, -0.499959469)
            PosM = CFrame.new(-5411.1645507812, 11.081554412842, 8454.29296875)
        elseif I == 325 or I <= 374 then
            Mon = "Military Spy"
            Qdata = 2
            Qname = "MagmaQuest"
            NameMon = "Military Spy"
            PosQ = CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, .866048813, 0, 1, 0, -0.866048813, 0, -0.499959469)
            PosM = CFrame.new(-5802.8681640625, 86.262413024902, 8828.859375)
        elseif I == 375 or I <= 399 then
            Mon = "Fishman Warrior"
            Qdata = 1
            Qname = "FishmanQuest"
            NameMon = "Fishman Warrior"
            PosQ = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
            PosM = CFrame.new(60878.30078125, 18.482830047607, 1543.7574462891)
        elseif I == 400 or I <= 449 then
            Mon = "Fishman Commando"
            Qdata = 2
            Qname = "FishmanQuest"
            NameMon = "Fishman Commando"
            PosQ = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
            PosM = CFrame.new(61922.6328125, 18.482830047607, 1493.9343261719)
        elseif I == 450 or I <= 474 then
            Mon = "God's Guard"
            Qdata = 1
            Qname = "SkyExp1Quest"
            NameMon = "God's Guard"
            PosQ = CFrame.new(-4721.88867, 843.874695, -1949.96643, .996191859, 0, -0.0871884301, 0, 1, 0, .0871884301, 0, .996191859)
            PosM = CFrame.new(-4710.04296875, 845.27697753906, -1927.3079833984)
        elseif I == 475 or I <= 524 then
            Mon = "Shanda"
            Qdata = 2
            Qname = "SkyExp1Quest"
            NameMon = "Shanda"
            PosQ = CFrame.new(-7859.09814, 5544.19043, -381.476196, -0.422592998, 0, .906319618, 0, 1, 0, -0.906319618, 0, -0.422592998)
            PosM = CFrame.new(-7678.4897460938, 5566.4038085938, -497.21560668945)
        elseif I == 525 or I <= 549 then
            Mon = "Royal Squad"
            Qdata = 1
            Qname = "SkyExp2Quest"
            NameMon = "Royal Squad"
            PosQ = CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-7624.2524414062, 5658.1333007812, -1467.3542480469)
        elseif I == 550 or I <= 624 then
            Mon = "Royal Soldier"
            Qdata = 2
            Qname = "SkyExp2Quest"
            NameMon = "Royal Soldier"
            PosQ = CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-7836.7534179688, 5645.6640625, -1790.6236572266)
        elseif I == 625 or I <= 649 then
            Mon = "Galley Pirate"
            Qdata = 1
            Qname = "FountainQuest"
            NameMon = "Galley Pirate"
            PosQ = CFrame.new(5259.81982, 37.3500175, 4050.0293, .087131381, 0, .996196866, 0, 1, 0, -0.996196866, 0, .087131381)
            PosM = CFrame.new(5551.0219726562, 78.901351928711, 3930.4128417969)
        elseif I >= 650 and I <= 699 then
            Mon = "Galley Captain"
            Qdata = 2
            Qname = "FountainQuest"
            NameMon = "Galley Captain"
            PosQ = CFrame.new(5259.81982, 37.3500175, 4050.0293, .087131381, 0, .996196866, 0, 1, 0, -0.996196866, 0, .087131381)
            PosM = CFrame.new(5441.9516601562, 42.502059936523, 4950.09375)
        end
    elseif World2 then
        if I == 700 or I <= 724 then
            Mon = "Raider"
            Qdata = 1
            Qname = "Area1Quest"
            NameMon = "Raider"
            PosQ = CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, .974368095, 0, -0.22495985)
            PosM = CFrame.new(-728.32672119141, 52.779319763184, 2345.7705078125)
        elseif I == 725 or I <= 774 then
            Mon = "Mercenary"
            Qdata = 2
            Qname = "Area1Quest"
            NameMon = "Mercenary"
            PosQ = CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, .974368095, 0, -0.22495985)
            PosM = CFrame.new(-1004.3244018555, 80.158866882324, 1424.6193847656)
        elseif I == 775 or I <= 799 then
            Mon = "Swan Pirate"
            Qdata = 1
            Qname = "Area2Quest"
            NameMon = "Swan Pirate"
            PosQ = CFrame.new(638.43811, 71.769989, 918.282898, .139203906, 0, .99026376, 0, 1, 0, -0.99026376, 0, .139203906)
            PosM = CFrame.new(1068.6643066406, 137.61428833008, 1322.1060791016)
        elseif I == 800 or I <= 874 then
            Mon = "Factory Staff"
            Qname = "Area2Quest"
            Qdata = 2
            NameMon = "Factory Staff"
            PosQ = CFrame.new(632.698608, 73.1055908, 918.666321, -0.0319722369, 8.96074881e-10, -0.999488771, 1.36326533e-10, 1, 8.92172336e-10, .999488771, -1.07732087e-10, -0.0319722369)
            PosM = CFrame.new(73.078674316406, 81.863441467285, -27.470672607422)
        elseif I == 875 or I <= 899 then
            Mon = "Marine Lieutenant"
            Qdata = 1
            Qname = "MarineQuest3"
            NameMon = "Marine Lieutenant"
            PosQ = CFrame.new(-2440.79639, 71.7140732, -3216.06812, .866007268, 0, .500031412, 0, 1, 0, -0.500031412, 0, .866007268)
            PosM = CFrame.new(-2821.3723144531, 75.897277832031, -3070.0891113281)
        elseif I == 900 or I <= 949 then
            Mon = "Marine Captain"
            Qdata = 2
            Qname = "MarineQuest3"
            NameMon = "Marine Captain"
            PosQ = CFrame.new(-2440.79639, 71.7140732, -3216.06812, .866007268, 0, .500031412, 0, 1, 0, -0.500031412, 0, .866007268)
            PosM = CFrame.new(-1861.2310791016, 80.176582336426, -3254.6975097656)
        elseif I == 950 or I <= 974 then
            Mon = "Zombie"
            Qdata = 1
            Qname = "ZombieQuest"
            NameMon = "Zombie"
            PosQ = CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, .95628953, 0, -0.29242146)
            PosM = CFrame.new(-5657.7768554688, 78.969734191895, -928.68701171875)
        elseif I == 975 or I <= 999 then
            Mon = "Vampire"
            Qdata = 2
            Qname = "ZombieQuest"
            NameMon = "Vampire"
            PosQ = CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, .95628953, 0, -0.29242146)
            PosM = CFrame.new(-6037.66796875, 32.184638977051, -1340.6597900391)
        elseif I == 1000 or I <= 1049 then
            Mon = "Snow Trooper"
            Qdata = 1
            Qname = "SnowMountainQuest"
            NameMon = "Snow Trooper"
            PosQ = CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, .92718488, 0, 1, 0, -0.92718488, 0, -0.374604106)
            PosM = CFrame.new(549.14733886719, 427.38705444336, -5563.6987304688)
        elseif I == 1050 or I <= 1099 then
            Mon = "Winter Warrior"
            Qdata = 2
            Qname = "SnowMountainQuest"
            NameMon = "Winter Warrior"
            PosQ = CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, .92718488, 0, 1, 0, -0.92718488, 0, -0.374604106)
            PosM = CFrame.new(1142.7451171875, 475.63980102539, -5199.4165039062)
        elseif I == 1100 or I <= 1124 then
            Mon = "Lab Subordinate"
            Qdata = 1
            Qname = "IceSideQuest"
            NameMon = "Lab Subordinate"
            PosQ = CFrame.new(-6064.06885, 15.2422857, -4902.97852, .453972578, 0, -0.891015649, 0, 1, 0, .891015649, 0, .453972578)
            PosM = CFrame.new(-5707.4716796875, 15.951709747314, -4513.3920898438)
        elseif I == 1125 or I <= 1174 then
            Mon = "Horned Warrior"
            Qdata = 2
            Qname = "IceSideQuest"
            NameMon = "Horned Warrior"
            PosQ = CFrame.new(-6064.06885, 15.2422857, -4902.97852, .453972578, 0, -0.891015649, 0, 1, 0, .891015649, 0, .453972578)
            PosM = CFrame.new(-6341.3666992188, 15.951770782471, -5723.162109375)
        elseif I == 1175 or I <= 1199 then
            Mon = "Magma Ninja"
            Qdata = 1
            Qname = "FireSideQuest"
            NameMon = "Magma Ninja"
            PosQ = CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, .469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            PosM = CFrame.new(-5449.6728515625, 76.658744812012, -5808.2006835938)
        elseif I == 1200 or I <= 1249 then
            Mon = "Lava Pirate"
            Qdata = 2
            Qname = "FireSideQuest"
            NameMon = "Lava Pirate"
            PosQ = CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, .469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            PosM = CFrame.new(-5213.3315429688, 49.737880706787, -4701.451171875)
        elseif I == 1250 or I <= 1274 then
            Mon = "Ship Deckhand"
            Qdata = 1
            Qname = "ShipQuest1"
            NameMon = "Ship Deckhand"
            PosQ = CFrame.new(1037.80127, 125.092171, 32911.6016)
            PosM = CFrame.new(1212.0111083984, 150.79205322266, 33059.24609375)
        elseif I == 1275 or I <= 1299 then
            Mon = "Ship Engineer"
            Qdata = 2
            Qname = "ShipQuest1"
            NameMon = "Ship Engineer"
            PosQ = CFrame.new(1037.80127, 125.092171, 32911.6016)
            PosM = CFrame.new(919.47863769531, 43.544013977051, 32779.96875)
        elseif I == 1300 or I <= 1324 then
            Mon = "Ship Steward"
            Qdata = 1
            Qname = "ShipQuest2"
            NameMon = "Ship Steward"
            PosQ = CFrame.new(968.80957, 125.092171, 33244.125)
            PosM = CFrame.new(919.43853759766, 129.55599975586, 33436.03515625)
        elseif I == 1325 or I <= 1349 then
            Mon = "Ship Officer"
            Qdata = 2
            Qname = "ShipQuest2"
            NameMon = "Ship Officer"
            PosQ = CFrame.new(968.80957, 125.092171, 33244.125)
            PosM = CFrame.new(1036.0179443359, 181.4390411377, 33315.7265625)
        elseif I == 1350 or I <= 1374 then
            Mon = "Arctic Warrior"
            Qdata = 1
            Qname = "FrostQuest"
            NameMon = "Arctic Warrior"
            PosQ = CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, .358349502, 0, -0.933587909)
            PosM = CFrame.new(5966.24609375, 62.970020294189, -6179.3828125)
        elseif I == 1375 or I <= 1424 then
            Mon = "Snow Lurker"
            Qdata = 2
            Qname = "FrostQuest"
            NameMon = "Snow Lurker"
            PosQ = CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, .358349502, 0, -0.933587909)
            PosM = CFrame.new(5407.0737304688, 69.194374084473, -6880.8803710938)
        elseif I == 1425 or I <= 1449 then
            Mon = "Sea Soldier"
            Qdata = 1
            Qname = "ForgottenQuest"
            NameMon = "Sea Soldier"
            PosQ = CFrame.new(-3054.44458, 235.544281, -10142.8193, .990270376, 0, -0.13915664, 0, 1, 0, .13915664, 0, .990270376)
            PosM = CFrame.new(-3028.2236328125, 64.674514770508, -9775.4267578125)
        elseif I >= 1450 and I <= 1499 then
            Mon = "Water Fighter"
            Qdata = 2
            Qname = "ForgottenQuest"
            NameMon = "Water Fighter"
            PosQ = CFrame.new(-3054.44458, 235.544281, -10142.8193, .990270376, 0, -0.13915664, 0, 1, 0, .13915664, 0, .990270376)
            PosM = CFrame.new(-3352.9013671875, 285.01556396484, -10534.841796875)
        end
    elseif World3 then
        if I == 1500 or I <= 1524 then
            Mon = "Pirate Millionaire"
            Qdata = 1
            Qname = "PiratePortQuest"
            NameMon = "Pirate Millionaire"
            PosQ = CFrame.new(-290.07, 42.90, 5581.59)
            PosM = CFrame.new(-246.00, 47.31, 5584.10)
        elseif I == 1525 or I <= 1574 then
            Mon = "Pistol Billionaire"
            Qdata = 2
            Qname = "PiratePortQuest"
            NameMon = "Pistol Billionaire"
            PosQ = CFrame.new(-290.07, 42.90, 5581.59)
            PosM = CFrame.new(-187.33, 86.24, 6013.51)
        elseif I == 1575 or I <= 1599 then
            Mon = "Dragon Crew Warrior"
            Qdata = 1
            Qname = "DragonCrewQuest"
            NameMon = "Dragon Crew Warrior"
            PosQ = CFrame.new(6737.06055,127.417763,-712.300659,-0.463954359,-7.19574755e-09,0.885859072,7.69187665e-08,1,4.84078626e-08,-0.885859072,9.05982276e-08,-0.463954359)
            PosM = CFrame.new(6709.76367,52.3442993,-1139.02966,-0.763515472,0,0.645789504,0,1,0,-0.645789504,0,-0.763515472)
        elseif I == 1600 or I <= 1624 then
            Mon = "Dragon Crew Archer"
            Qdata = 2
            Qname = "DragonCrewQuest"
            NameMon = "Dragon Crew Archer"
            PosQ = CFrame.new(6737.06055,127.417763,-712.300659,-0.463954359,-7.19574755e-09,0.885859072,7.69187665e-08,1,4.84078626e-08,-0.885859072,9.05982276e-08,-0.463954359)
            PosM = CFrame.new(6668.76172,481.376923,329.12207,-0.121787429,0,-0.992556155,0,1,0,0.992556155,0,-0.121787429)
        elseif I == 1625 or I <= 1649 then
            Mon = "Hydra Enforcer"
            Qname = "VenomCrewQuest"
            Qdata = 1
            NameMon = "Hydra Enforcer"
            PosQ = CFrame.new(5206.40185546875, 1004.10498046875, 748.3504638671875)
            PosM = CFrame.new(4547.11523, 1003.10217, 334.194824, 0.388810456, -0, -0.921317935, 0, 1, -0, 0.921317935, 0, 0.388810456)
        elseif I == 1650 or I <= 1699 then
            Mon = "Venomous Assailant"
            Qname = "VenomCrewQuest"
            Qdata = 2
            NameMon = "Venomous Assailant"
            PosQ = CFrame.new(5206.40185546875, 1004.10498046875, 748.3504638671875)
            PosM = CFrame.new(4674.92676, 1134.82654, 996.308838, 0.731321394, -0, -0.682033002, 0, 1, -0, 0.682033002, 0, 0.731321394)
        elseif I == 1700 or I <= 1724 then
            Mon = "Marine Commodore"
            Qdata = 1
            Qname = "MarineTreeIsland"
            NameMon = "Marine Commodore"
            PosQ = CFrame.new(2482, 74, -6788)
            PosM = CFrame.new(2519, 109, -7633)
        elseif I == 1725 or I <= 1774 then
            Mon = "Marine Rear Admiral"
            NameMon = "Marine Rear Admiral"
            Qname = "MarineTreeIsland"
            Qdata = 2
            PosQ = CFrame.new(2482, 74, -6788)
            PosM = CFrame.new(3722, 169, -7038)
        elseif I == 1775 or I <= 1799 then
            Mon = "Fishman Raider"
            Qdata = 1
            Qname = "DeepForestIsland3"
            NameMon = "Fishman Raider"
            PosQ = CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, .469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            PosM = CFrame.new(-10407.526367188, 331.76263427734, -8368.5166015625)
        elseif I == 1800 or I <= 1824 then
            Mon = "Fishman Captain"
            Qdata = 2
            Qname = "DeepForestIsland3"
            NameMon = "Fishman Captain"
            PosQ = CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, .469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            PosM = CFrame.new(-10994.701171875, 352.38140869141, -9002.1103515625)
        elseif I == 1825 or I <= 1849 then
            Mon = "Forest Pirate"
            Qdata = 1
            Qname = "DeepForestIsland"
            NameMon = "Forest Pirate"
            PosQ = CFrame.new(-13234.04, 331.488495, -7625.40137, .707134247, 0, -0.707079291, 0, 1, 0, .707079291, 0, .707134247)
            PosM = CFrame.new(-13274.478515625, 332.37814331055, -7769.5805664062)
        elseif I == 1850 or I <= 1899 then
            Mon = "Mythological Pirate"
            Qdata = 2
            Qname = "DeepForestIsland"
            NameMon = "Mythological Pirate"
            PosQ = CFrame.new(-13234.04, 331.488495, -7625.40137, .707134247, 0, -0.707079291, 0, 1, 0, .707079291, 0, .707134247)
            PosM = CFrame.new(-13680.607421875, 501.08154296875, -6991.189453125)
        elseif I == 1900 or I <= 1924 then
            Mon = "Jungle Pirate"
            Qdata = 1
            Qname = "DeepForestIsland2"
            NameMon = "Jungle Pirate"
            PosQ = CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, .996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002)
            PosM = CFrame.new(-12256.16015625, 331.73828125, -10485.836914062)
        elseif I == 1925 or I <= 1974 then
            Mon = "Musketeer Pirate"
            Qdata = 2
            Qname = "DeepForestIsland2"
            NameMon = "Musketeer Pirate"
            PosQ = CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, .996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002)
            PosM = CFrame.new(-13457.904296875, 391.54565429688, -9859.177734375)
        elseif I == 1975 or I <= 1999 then
            Mon = "Reborn Skeleton"
            Qdata = 1
            Qname = "HauntedQuest1"
            NameMon = "Reborn Skeleton"
            PosQ = CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, 0, -1, 0, 0)
            PosM = CFrame.new(-8763.7236328125, 165.72299194336, 6159.8618164062)
        elseif I == 2000 or I <= 2024 then
            Mon = "Living Zombie"
            Qdata = 2
            Qname = "HauntedQuest1"
            NameMon = "Living Zombie"
            PosQ = CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, 0, -1, 0, 0)
            PosM = CFrame.new(-10144.131835938, 138.6266784668, 5838.0888671875)
        elseif I == 2025 or I <= 2049 then
            Mon = "Demonic Soul"
            Qdata = 1
            Qname = "HauntedQuest2"
            NameMon = "Demonic Soul"
            PosQ = CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-9505.8720703125, 172.10482788086, 6158.9931640625)
        elseif I == 2050 or I <= 2074 then
            Mon = "Posessed Mummy"
            Qdata = 2
            Qname = "HauntedQuest2"
            NameMon = "Posessed Mummy"
            PosQ = CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-9582.0224609375, 6.2515273094177, 6205.478515625)
        elseif I == 2075 or I <= 2099 then
            Mon = "Peanut Scout"
            Qdata = 1
            Qname = "NutsIslandQuest"
            NameMon = "Peanut Scout"
            PosQ = CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-2143.2419433594, 47.721984863281, -10029.995117188)
        elseif I == 2100 or I <= 2124 then
            Mon = "Peanut President"
            Qdata = 2
            Qname = "NutsIslandQuest"
            NameMon = "Peanut President"
            PosQ = CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-1859.3540039062, 38.103168487549, -10422.4296875)
        elseif I == 2125 or I <= 2149 then
            Mon = "Ice Cream Chef"
            Qdata = 1
            Qname = "IceCreamIslandQuest"
            NameMon = "Ice Cream Chef"
            PosQ = CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-872.24658203125, 65.81957244873, -10919.95703125)
        elseif I == 2150 or I <= 2199 then
            Mon = "Ice Cream Commander"
            Qdata = 2
            Qname = "IceCreamIslandQuest"
            NameMon = "Ice Cream Commander"
            PosQ = CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            PosM = CFrame.new(-558.06103515625, 112.04895782471, -11290.774414062)
        elseif I == 2200 or I <= 2224 then
            Mon = "Cookie Crafter"
            Qdata = 1
            Qname = "CakeQuest1"
            NameMon = "Cookie Crafter"
            PosQ = CFrame.new(-2021.32007, 37.7982254, -12028.7295, .957576931, -8.80302053e-08, .288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, .957576931)
            PosM = CFrame.new(-2374.13671875, 37.798263549805, -12125.30859375)
        elseif I == 2225 or I <= 2249 then
            Mon = "Cake Guard"
            Qdata = 2
            Qname = "CakeQuest1"
            NameMon = "Cake Guard"
            PosQ = CFrame.new(-2021.32007, 37.7982254, -12028.7295, .957576931, -8.80302053e-08, .288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, .957576931)
            PosM = CFrame.new(-1598.3070068359, 43.773197174072, -12244.581054688)
        elseif I == 2250 or I <= 2274 then
            Mon = "Baking Staff"
            Qdata = 1
            Qname = "CakeQuest2"
            NameMon = "Baking Staff"
            PosQ = CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, .250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446)
            PosM = CFrame.new(-1887.8099365234, 77.618507385254, -12998.350585938)
        elseif I == 2275 or I <= 2299 then
            Mon = "Head Baker"
            Qdata = 2
            Qname = "CakeQuest2"
            NameMon = "Head Baker"
            PosQ = CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, .250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446)
            PosM = CFrame.new(-2216.1882324219, 82.884521484375, -12869.293945312)
        elseif I == 2300 or I <= 2324 then
            Mon = "Cocoa Warrior"
            Qdata = 1
            Qname = "ChocQuest1"
            NameMon = "Cocoa Warrior"
            PosQ = CFrame.new(233.22836303711, 29.876001358032, -12201.233398438)
            PosM = CFrame.new(-21.553283691406, 80.574996948242, -12352.387695312)
        elseif I == 2325 or I <= 2349 then
            Mon = "Chocolate Bar Battler"
            Qdata = 2
            Qname = "ChocQuest1"
            NameMon = "Chocolate Bar Battler"
            PosQ = CFrame.new(233.22836303711, 29.876001358032, -12201.233398438)
            PosM = CFrame.new(582.59057617188, 77.188095092773, -12463.162109375)
        elseif I == 2350 or I <= 2374 then
            Mon = "Sweet Thief"
            Qdata = 1
            Qname = "ChocQuest2"
            NameMon = "Sweet Thief"
            PosQ = CFrame.new(150.50663757324, 30.693693161011, -12774.502929688)
            PosM = CFrame.new(165.1884765625, 76.058853149414, -12600.836914062)
        elseif I == 2375 or I <= 2399 then
            Mon = "Candy Rebel"
            Qdata = 2
            Qname = "ChocQuest2"
            NameMon = "Candy Rebel"
            PosQ = CFrame.new(150.50663757324, 30.693693161011, -12774.502929688)
            PosM = CFrame.new(134.86563110352, 77.247680664062, -12876.547851562)
        elseif I == 2400 or I <= 2449 then
            Mon = "Candy Pirate"
            Qdata = 1
            Qname = "CandyQuest1"
            NameMon = "Candy Pirate"
            PosQ = CFrame.new(-1150.0400390625, 20.378934860229, -14446.334960938)
            PosM = CFrame.new(-1310.5003662109, 26.016523361206, -14562.404296875)
        elseif I == 2450 or I <= 2474 then
            Mon = "Isle Outlaw"
            Qdata = 1
            Qname = "TikiQuest1"
            NameMon = "Isle Outlaw"
            PosQ = CFrame.new(-16548.8164, 55.6059914, -172.8125, .213092566, 0, -0.977032006, 0, 1, 0, .977032006, 0, .213092566)
            PosM = CFrame.new(-16479.900390625, 226.6117401123, -300.31143188477)
        elseif I == 2475 or I <= 2499 then
            Mon = "Island Boy"
            Qdata = 2
            Qname = "TikiQuest1"
            NameMon = "Island Boy"
            PosQ = CFrame.new(-16548.8164, 55.6059914, -172.8125, .213092566, 0, -0.977032006, 0, 1, 0, .977032006, 0, .213092566)
            PosM = CFrame.new(-16849.396484375, 192.86505126953, -150.78532409668)
        elseif I == 2500 or I <= 2524 then
            Mon = "Sun-kissed Warrior"
            Qdata = 1
            Qname = "TikiQuest2"
            NameMon = "kissed Warrior"
            PosM = CFrame.new(-16347, 64, 984)
            PosQ = CFrame.new(-16538, 55, 1049)
        elseif I == 2525 or I <= 2550 then
            Mon = "Isle Champion"
            Qdata = 2
            Qname = "TikiQuest2"
            NameMon = "Isle Champion"
            PosQ = CFrame.new(-16541.0215, 57.3082275, 1051.46118, .0410757065, 0, -0.999156058, 0, 1, 0, .999156058, 0, .0410757065)
            PosM = CFrame.new(-16602.1015625, 130.38734436035, 1087.2456054688)
        elseif I == 2551 or I <= 2574 then
            Mon = "Serpent Hunter"
            Qdata = 1
            Qname = "TikiQuest3"
            NameMon = "Serpent Hunter"
            PosQ = CFrame.new(-16668.03,105.32,1568.60)
            PosM = CFrame.new(-16645.64,163.09,1352.87)
        elseif I >= 2575 and I <= 2599 then 
            Mon = "Skull Slayer"
            Qdata = 2
            Qname = "TikiQuest3"
            NameMon = "Skull Slayer"
            PosQ = CFrame.new(-16668.03,105.32,1568.60)
            PosM = CFrame.new(-16709.49,419.68,1751.09)
        elseif I >= 2600 and I <= 2624 then
            Mon = "Reef Bandit"
            Qdata = 1
            Qname = "SubmergedQuest1"
            NameMon = "Reef Bandit"
            PosQ = CFrame.new(10778.875, -2087.72437, 9265.18359, 0.934615612, -9.33109447e-08, -0.355659455, 9.17655143e-08, 1, -2.12154276e-08, 0.355659455, -1.28090019e-08, 0.934615612)
            PosM = CFrame.new(11019.1318, -2146.06812, 9342.3916, -0.719955266, -1.74275385e-08, 0.69402045, 5.76556367e-08, 1, 8.49211546e-08, -0.69402045, 1.01153624e-07, -0.719955266)
        elseif I >= 2625 and I <= 2649 then
            Mon = "Coral Pirate"
            Qdata = 2
            Qname = "SubmergedQuest1"
            NameMon = "Coral Pirate"
            PosQ = CFrame.new(10778.875, -2087.72437, 9265.18359, 0.934615612, -9.33109447e-08, -0.355659455, 9.17655143e-08, 1, -2.12154276e-08, 0.355659455, -1.28090019e-08, 0.934615612)
            PosM = CFrame.new(10808.6006, -2030.36145, 9364.2334, -0.775185347, -0.0359364748, 0.6307109, 0.0615428537, 0.989336014, 0.132010356, -0.628728986, 0.141148239, -0.764707148)
        elseif I >= 2650 and I <= 2674 then
            Mon = "Sea Chanter"
            Qdata = 1
            Qname = "SubmergedQuest2"
            NameMon = "Sea Chanter"
            PosQ = CFrame.new(10880.6855, -2086.20044, 10032.624, -0.321384728, 9.87648434e-08, -0.946948707, 7.13271007e-08, 1, 8.00902953e-08, 0.946948707, -4.18033075e-08, -0.321384728)
            PosM = CFrame.new(10671.2715, -2057.59155, 10047.2588, -0.846484065, -3.11045447e-08, 0.532414079, -5.55383117e-08, 1, -2.98785316e-08, -0.532414079, -5.48610757e-08, -0.846484065)
        elseif I >= 2675 and I <= 2699 then
            Mon = "Ocean Prophet"
            Qdata = 2
            Qname = "SubmergedQuest2"
            NameMon = "Ocean Prophet"
            PosQ = CFrame.new(10880.6855, -2086.20044, 10032.624, -0.321384728, 9.87648434e-08, -0.946948707, 7.13271007e-08, 1, 8.00902953e-08, 0.946948707, -4.18033075e-08, -0.321384728)
            PosM = CFrame.new(11008.5195, -2007.72839, 10223.0791, -0.688615739, 2.33523378e-09, -0.725126445, 2.99292546e-09, 1, 3.78221315e-10, 0.725126445, -1.90980032e-09, -0.688615739)
        elseif I >= 2700 and I <= 2724 then
            Mon = "High Disciple"
            Qdata = 1
            Qname = "SubmergedQuest3"
            NameMon = "High Disciple"
            PosQ = CFrame.new(9640.08789, -1992.44507, 9613.65234, -0.957327187, 4.11991223e-08, 0.289006323, 1.5775445e-08, 1, -9.02985846e-08, -0.289006323, -8.18860855e-08, -0.957327187)
            PosM = CFrame.new(9750.41602, -1966.93884, 9753.36035, -0.749824047, 5.57797613e-08, -0.661637306, 2.03500754e-08, 1, 6.1243199e-08, 0.661637306, 3.24572511e-08, -0.749824047)
        elseif I >= 2725 then
            Mon = "Grand Devotee"
            Qdata = 2
            Qname = "SubmergedQuest3"
            NameMon = "Grand Devotee"
            PosQ = CFrame.new(9640.08789, -1992.44507, 9613.65234, -0.957327187, 4.11991223e-08, 0.289006323, 1.5775445e-08, 1, -9.02985846e-08, -0.289006323, -8.18860855e-08, -0.957327187)
            PosM = CFrame.new(9611.70508, -1993.47119, 9882.68848, -0.591375351, 4.14332426e-08, -0.806396425, 4.73774868e-08, 1, 1.66361875e-08, 0.806396425, -2.83668058e-08, -0.591375351)
        end
    end
    
    -- Dual quest: nếu Qdata=2 và có khu vực tương ứng trong DualQuestPairings → trả về altData
    local altData = nil
    if Qdata == 2 and Qname and DualQuestPairings[Qname] then
        altData = DualQuestPairings[Qname]
    end
    
    return Mon, Qdata, Qname, NameMon, PosM, PosQ, altData
end

--// ================= TELEPORT & SUBMERGED =================
local function TweenToPos(targetCF, speed)
    local root = getRoot()
    if not root then return end
    local spd = speed or getgenv().FlySpeed
    -- Nếu TelePorto bật và tele trung gian được spawn → _tp sẽ được gọi bên trong async
    if doIntermediateTeleport(targetCF, spd) then return end
    -- Không có tele trung gian → tween thẳng
    _tp(targetCF, spd)
end

--------------------------------------------------------------------
-- HÀM TWEEN ĐẾN VỊ TRÍ CỐ ĐỊNH (Farm loops: Bone, Kata, Aura...)
--------------------------------------------------------------------
local function TweenToFixedPos(_, targetCF, speed)
    if not targetCF then return end
    local spd = speed or getgenv().FlySpeed
    if doIntermediateTeleport(targetCF, spd) then return end
    _tp(targetCF, spd)
end

--------------------------------------------------------------------
-- TELEPORT ĐẾN SUBMERGED ISLAND (W3, lv >= 2600)
--
-- Dùng session counter thay cho boolean flag để tránh lock stale:
--   - Mỗi lần gọi (kể cả sau tắt/bật farm) đều bump _submergedCallId.
--   - Coroutine cũ so sánh myId vs _submergedCallId ở mỗi checkpoint;
--     nếu lệch → abort ngay, không block lần gọi mới.
--
-- Luồng:
--   1. Fly đến vị trí NPC, đợi đến đủ gần (≤10 stud) — không timeout
--   2. Kích hoạt TravelToSubmergedIsland ngay
--   3. Chờ server tele + (tuỳ chọn) fly tới finalPos
--------------------------------------------------------------------
local _submergedCallId = 0    -- bump khi bắt đầu mỗi call MỚI
local _submergedRunning = false  -- guard: ngăn chạy song song từ Heartbeat

--------------------------------------------------------------------
-- TeleportToSubmerged(finalPos?)
--   finalPos (Vector3, tuỳ chọn): nếu được truyền vào, sau khi
--   TravelToSubmergedIsland kích hoạt xong sẽ chờ server tele
--   rồi fly thẳng đến vị trí farm đó.
-- Không truyền finalPos → hành vi cũ (dùng bởi auto-lv farm).
--------------------------------------------------------------------
local function TeleportToSubmerged(finalPos)
    if not (World3 and player.Data.Level.Value >= 2600) then return end

    -- Guard: ngăn Heartbeat spawn nhiều instance song song.
    if _submergedRunning then return end
    _submergedRunning = true

    -- Bump session id để cancel mọi instance cũ nếu stopFly được gọi.
    _submergedCallId = _submergedCallId + 1
    local myId = _submergedCallId

    local npcCF = CFrame.new(-16269.7041, 25.2288494, 1373.65955)

    -- Bước 1: Fly đến NPC (tele trung gian được xử lý bên trong TweenToPos)
    TweenToPos(npcCF, 350)

    -- Đợi đến đủ gần ≤10 stud — không timeout, chỉ check khoảng cách
    while true do
        task.wait(0.15)
        if myId ~= _submergedCallId then _submergedRunning = false; return end
        if not getgenv().IsFarming then _submergedRunning = false; return end
        local root = getRoot()
        if root and (root.Position - npcCF.Position).Magnitude <= 10 then
            break
        end
        -- vẫn chưa gần → gọi lại TweenToPos để tiếp tục bay
        TweenToPos(npcCF, 350)
    end

    if myId ~= _submergedCallId or not getgenv().IsFarming then
        _submergedRunning = false
        return
    end

    -- Bước 2: Dừng tween rồi kích hoạt TravelToSubmergedIsland ngay
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
    currentTweenSpeed = 0

    pcall(function()
        ReplicatedStorage.Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak")
            :InvokeServer("TravelToSubmergedIsland")
    end)

    -- Bước 4: Chờ server xử lý tele (4s: 2s buffer ban đầu + 2s thêm để
    -- đảm bảo nhân vật đã được teleport vào island trước khi fly)
    task.wait(4)

    if myId ~= _submergedCallId or not getgenv().IsFarming then
        _submergedRunning = false
        return
    end

    -- Bước 5 (tuỳ chọn): Fly đến vị trí farm bên trong island
    if finalPos then
        local farmCF = CFrame.new(finalPos + Vector3.new(0, 3, 0))
        TweenToPos(farmCF, getgenv().FlySpeed or 300)

        -- Đợi đến nơi (timeout 40s — di chuyển dưới nước chậm hơn)
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

--// ================= MATERIAL FARM LOGIC =================
local function MaterialMon()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local function shouldRequestEntrance(pos, dist)
        if (root.Position - pos).Magnitude >= dist then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance", pos)
        end
    end

    if World1 then
        if getgenv().SelectMaterial == "Angel Wings" then
            MMon = {"Shanda", "Royal Squad", "Royal Soldier", "Wysper", "Thunder God"}
            MPos = CFrame.new(-7656, 5619, -1033)
            shouldRequestEntrance(Vector3.new(-4607.8, 872.5, -1667.5), 10000)
        elseif getgenv().SelectMaterial == "Leather + Scrap Metal" then
            MMon = {"Brute", "Pirate"}
            MPos = CFrame.new(-1145, 15, 4350)
        elseif getgenv().SelectMaterial == "Magma Ore" then
            MMon = {"Military Soldier", "Military Spy", "Magma Admiral"}
            MPos = CFrame.new(-5815, 84, 8820)
        elseif getgenv().SelectMaterial == "Fish Tail" then
            MMon = {"Fishman Warrior", "Fishman Commando", "Fishman Lord"}
            MPos = CFrame.new(61123, 19, 1569)
            shouldRequestEntrance(Vector3.new(61163.8, 5.3, 1819.7), 17000)
        end
    elseif World2 then
        if getgenv().SelectMaterial == "Leather + Scrap Metal" then
            MMon = {"Marine Captain"}
            MPos = CFrame.new(-2010.5, 73, -3326.6)
        elseif getgenv().SelectMaterial == "Magma Ore" then
            MMon = {"Magma Ninja", "Lava Pirate"}
            MPos = CFrame.new(-5428, 78, -5959)
        elseif getgenv().SelectMaterial == "Ectoplasm" then
            MMon = {"Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer"}
            MPos = CFrame.new(911.3, 125.9, 33159.5)
            shouldRequestEntrance(Vector3.new(61163.8, 5.3, 1819.7), 18000)
        elseif getgenv().SelectMaterial == "Mystic Droplet" then
            MMon = {"Water Fighter"}
            MPos = CFrame.new(-3385, 239, -10542)
        elseif getgenv().SelectMaterial == "Radioactive Material" then
            MMon = {"Factory Staff"}
            MPos = CFrame.new(295, 73, -56)
        elseif getgenv().SelectMaterial == "Vampire Fang" then
            MMon = {"Vampire"}
            MPos = CFrame.new(-6033, 7, -1317)
        end
    elseif World3 then
        if getgenv().SelectMaterial == "Scrap Metal" then
            MMon = {"Jungle Pirate", "Forest Pirate"}
            MPos = CFrame.new(-11975.7, 331.7, -10620)
        elseif getgenv().SelectMaterial == "Fish Tail" then
            MMon = {"Fishman Raider", "Fishman Captain"}
            MPos = CFrame.new(-10993, 332, -8940)
        elseif getgenv().SelectMaterial == "Conjured Cocoa" then
            MMon = {"Chocolate Bar Battler", "Cocoa Warrior"}
            MPos = CFrame.new(620.6, 78.9, -12581.3)
        elseif getgenv().SelectMaterial == "Dragon Scale" then
            MMon = {"Dragon Crew Archer", "Dragon Crew Warrior"}
            MPos = CFrame.new(6594, 383, 139)
        elseif getgenv().SelectMaterial == "Gunpowder" then
            MMon = {"Pistol Billionaire"}
            MPos = CFrame.new(-84.8, 85.6, 6132)
        elseif getgenv().SelectMaterial == "Mini Tusk" then
            MMon = {"Mythological Pirate"}
            MPos = CFrame.new(-13545, 470, -6917)
        elseif getgenv().SelectMaterial == "Demonic Wisp" then
            MMon = {"Demonic Soul"}
            MPos = CFrame.new(-9495.6, 453.5, 5977.3)
        end
    end
end

--// ================= LEVEL FARM =================
local levelFarmConn

function startLevelFarm()
    if levelFarmConn then levelFarmConn:Disconnect() end
    
    --------------------------------------------------------------------
    -- DUAL QUEST STATE
    -- DualQuestNext[Qname]:
    --   nil / falsy → nhận quest CAO (Qdata=2) tiếp theo
    --   1           → nhận quest THẤP (altData, Qdata=1) tiếp theo
    --   2           → nhận quest CAO (Qdata=2) tiếp theo
    --
    -- Flip chỉ xảy ra khi quest HOÀN THÀNH (questUI.Visible: true → false).
    -- Trong lúc đang farm, mob mục tiêu được xác định từ TIÊU ĐỀ QUEST
    -- thực tế trên UI, không phải từ biến trạng thái — tránh desync.
    --------------------------------------------------------------------
    if not getgenv().DualQuestNext then
        getgenv().DualQuestNext = {}
    end

    local prevQuestVisible = false  -- trạng thái visibility của frame trước
    local prevQname        = nil    -- Qname của frame trước (để tránh flip khi đổi khu vực)

    --------------------------------------------------------------------
    -- ENEMY SPAWN STATE (dùng khi không có mob - fly qua EnemySpawns thực tế)
    -- Chỉ hoạt động với Farm LV
    --------------------------------------------------------------------
    local _spawnPoints    = nil  -- danh sách CFrame lấy từ WorldSpawnData (đã quét sẵn cả world)
    local _spawnIndex     = 1    -- chỉ số điểm spawn hiện tại
    local _spawnLastMon   = nil  -- tên mob lần trước để rebuild khi đổi khu
    local _spawnArrivedAt = 0    -- tick() khi đến điểm spawn (để delay trước khi đổi điểm)
    local _spawnRefreshAt = 0    -- tick() lần quét lại EnemySpawns gần nhất (check liên tục)
    local _questArrivedAt = 0    -- tick() khi đến gần PosQ (để delay 2s trước khi nhận quest)

    levelFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmLevel then return end
        
        pcall(function()
            local root = getRoot()
            if not root then return end
            
            local Mon, Qdata, Qname, NameMon, PosM, PosQ, altData = QuestNeta()
            if not Mon then return end
            
            local questUI      = player.PlayerGui.Main.Quest
            local questVisible = questUI.Visible

            ------------------------------------------------------------
            -- PHÁT HIỆN HOÀN THÀNH QUEST → flip DualQuestNext
            -- Điều kiện: khu vực có dual quest + quest vừa biến mất
            -- + Qname không đổi (tránh nhầm khi lên lv và đổi khu vực)
            ------------------------------------------------------------
            if altData and prevQuestVisible and not questVisible and prevQname == Qname then
                local cur = getgenv().DualQuestNext[Qname]
                -- cur == 1 nghĩa là vừa xong quest thấp → lần sau nhận quest cao
                -- cur == nil/2 nghĩa là vừa xong quest cao → lần sau nhận quest thấp
                getgenv().DualQuestNext[Qname] = (cur == 1) and 2 or 1
            end
            prevQuestVisible = questVisible
            prevQname        = Qname

            -- Submerged teleport (W3 lv >= 2600)
            -- Dùng task.spawn để Heartbeat callback không bị block; guard
            -- _submergedRunning bên trong hàm ngăn chạy song song.
            if World3 and player.Data.Level.Value >= 2600 and (PosQ.Position - root.Position).Magnitude > 10000 then
                task.spawn(TeleportToSubmerged)
                return
            end
            
            ------------------------------------------------------------
            -- NHẬN QUEST (khi questUI không hiển thị = chưa có quest)
            ------------------------------------------------------------
            if not questVisible then
                if not getgenv().BypassAcceptQuest then
                    TweenToPos(PosQ, getgenv().FlySpeed)
                    if (root.Position - PosQ.Position).Magnitude > 20 then
                        _questArrivedAt = 0  -- chưa đến → reset timer
                        return
                    end
                end
                -- Đến nơi (hoặc bypass) → bắt đầu đếm delay 2s trước khi nhận quest
                if _questArrivedAt == 0 then
                    _questArrivedAt = tick()
                elseif tick() - _questArrivedAt >= 2 then
                    _questArrivedAt = 0
                    -- Xác định Qdata cần nhận dựa vào DualQuestNext
                    local qdataToAccept = Qdata  -- mặc định: quest cao
                    if altData then
                        local nextTarget = getgenv().DualQuestNext[Qname]
                        if nextTarget == 1 then
                            qdataToAccept = altData.Qdata  -- nhận quest thấp
                        end
                    end
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", Qname, qdataToAccept)
                    end)
                    -- Mỗi khi vừa nhận quest mới → quét lại pos spawn cả world, merge vào data đã lưu
                    pcall(ScanWorldSpawns)
                    task.wait(0.5)
                end
                return
            end
            
            ------------------------------------------------------------
            -- QUEST ĐANG CHẠY: xác định mob mục tiêu từ tiêu đề UI thực tế
            -- Đọc từ UI thay vì từ biến trạng thái → không bao giờ desync
            ------------------------------------------------------------
            local QuestTitle  = questUI.Container.QuestTitle.Title.Text
            local activeMon   = Mon
            local activeNameMon = NameMon
            local activePosM  = PosM

            if altData and string.find(QuestTitle, altData.NameMon) then
                -- Quest thấp (altData) đang hoạt động
                activeMon       = altData.Mon
                activeNameMon   = altData.NameMon
                activePosM      = altData.PosM
            elseif not string.find(QuestTitle, NameMon) then
                -- Tiêu đề không khớp quest cao lẫn quest thấp → sai quest, hủy
                if not (altData and string.find(QuestTitle, altData.NameMon)) then
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("AbandonQuest")
                    end)
                    task.wait(0.5)
                    return
                end
            end
            
            -- === FARM MOB ===
            local enemy = GetNearestEnemy(activeMon)
            getgenv().CurrentTargetMob = enemy
            
            if enemy then
                if enemy:FindFirstChild("HumanoidRootPart") then
                    local targetCF = GetFarmCFrame(enemy)
                    if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                    AttackEnemy(enemy)
                end
            else
                -- Không có mob → liên tục tìm EnemySpawn đúng tên mob quest (khớp 100%)
                -- rồi tween tới các điểm spawn theo thứ tự gần nhất; quét lại định kỳ
                -- trong lúc làm quest
                getgenv().CurrentTargetMob = nil

                local needRebuild = (_spawnLastMon ~= activeMon)
                    or (not _spawnPoints)
                    or (#_spawnPoints == 0)
                    or (tick() - (_spawnRefreshAt or 0) >= 2)

                if needRebuild then
                    local monChanged = (_spawnLastMon ~= activeMon)
                    local oldCount   = _spawnPoints and #_spawnPoints or 0
                    _spawnLastMon   = activeMon
                    _spawnRefreshAt = tick()
                    -- Reset index khi đổi mob hoặc list cũ rỗng
                    if monChanged or oldCount == 0 then
                        _spawnIndex = 1
                    end
                    _spawnArrivedAt = 0

                    -- Hết mob → quét lại pos spawn cả world (merge thêm pos mới nếu có,
                    -- KHÔNG xóa data cũ), sau đó lục trong data đã lưu từ lúc script
                    -- chạy để lấy toàn bộ pos từng thấy của đúng tên mob quest.
                    -- KHÔNG fallback về PosM — chỉ dùng đúng pos spawn thật đã quét được.
                    pcall(ScanWorldSpawns)
                    _spawnPoints = getgenv().WorldSpawnData[activeMon] or {}
                    print(("[WorldSpawn] mob=%s -> %d pos đã lưu"):format(tostring(activeMon), #_spawnPoints))

                    if _spawnIndex > #_spawnPoints then
                        _spawnIndex = 1
                    end
                end

                -- Mỗi Heartbeat khi không có mob: tween tới spawn hiện tại, xoay vòng liên tục
                if _spawnPoints and #_spawnPoints > 0 then
                    local targetSP = _spawnPoints[_spawnIndex]
                    TweenToPos(targetSP, getgenv().FlySpeed)

                    if root and (root.Position - targetSP.Position).Magnitude <= 20 then
                        if _spawnArrivedAt == 0 then
                            _spawnArrivedAt = tick()
                        elseif tick() - _spawnArrivedAt >= 0.3 then
                            _spawnArrivedAt = 0
                            _spawnIndex     = (_spawnIndex % #_spawnPoints) + 1
                        end
                    else
                        _spawnArrivedAt = 0
                    end
                end
            end
        end)
    end)
end

function stopLevelFarm()
    if levelFarmConn then
        levelFarmConn:Disconnect()
        levelFarmConn = nil
    end
    getgenv().CurrentTargetMob = nil
end

--------------------------------------------------------------------
-- HẾT MOB -> TWEEN POS SPAWN THẬT (dùng chung cho Bone / Kata / Material)
--
-- GetMobSpawnWaypoints(mobList, onePerMob):
--   Quét lại _WorldOrigin.EnemySpawns (ScanWorldSpawns) rồi lấy pos spawn
--   thật đã lưu trong WorldSpawnData cho từng tên mob trong mobList.
--     onePerMob = true  -> mỗi loại mob CHỈ lấy 1 pos (dùng cho Bone/Kata,
--                          làm điểm mốc tuần tra qua lại giữa các loại mob)
--     onePerMob = false -> lấy HẾT toàn bộ pos đã quét được của mọi loại mob
--                          (dùng cho Material farm nhiều loại mob: phải đi
--                          qua hết pos của tất cả loại mob mới lặp lại)
--
-- MakeSpawnPatroller(mobList, onePerMob):
--   Trả về bộ điều khiển tuần tra { step, reset } cho 1 farm mode:
--     step(root, speed) -> tween tới waypoint hiện tại, tự xoay vòng qua
--                          waypoint kế tiếp sau khi đến gần + delay 0.5s.
--                          Trả về CFrame đích nếu có waypoint, nil nếu
--                          chưa quét được pos nào (để farm tự fallback).
--     reset()           -> gọi khi tìm lại được mob, để lần hết mob kế
--                          tiếp patrol lại từ waypoint đầu tiên.
--------------------------------------------------------------------
local function GetMobSpawnWaypoints(mobList, onePerMob)
    pcall(ScanWorldSpawns)
    local waypoints = {}
    for _, mobName in ipairs(mobList) do
        local list = getgenv().WorldSpawnData[mobName]
        if list and #list > 0 then
            if onePerMob then
                table.insert(waypoints, list[1])
            else
                for _, cf in ipairs(list) do
                    table.insert(waypoints, cf)
                end
            end
        end
    end
    return waypoints
end

local function MakeSpawnPatroller(mobList, onePerMob)
    local waypoints  = nil
    local idx        = 1
    local arrivedAt  = 0
    local lastScanAt = 0

    local function rebuild()
        waypoints  = GetMobSpawnWaypoints(mobList, onePerMob)
        lastScanAt = tick()
        if idx > #waypoints then idx = 1 end
        arrivedAt = 0
    end

    local function reset()
        idx = 1
        arrivedAt = 0
    end

    local function step(root, speed)
        -- Rebuild nếu chưa có data, rỗng, hoặc đã quá 3s kể từ lần quét trước
        -- (phòng khi lúc đầu khu vực chưa load kịp EnemySpawns)
        if not waypoints or #waypoints == 0 or (tick() - lastScanAt) >= 3 then
            rebuild()
        end
        if not waypoints or #waypoints == 0 then return nil end

        local targetCF = waypoints[idx]
        TweenToFixedPos(root, targetCF, speed)

        if root and (root.Position - targetCF.Position).Magnitude <= 80 then
            if arrivedAt == 0 then
                arrivedAt = tick()
            elseif tick() - arrivedAt >= 0.5 then
                arrivedAt = 0
                idx = (idx % #waypoints) + 1  -- qua waypoint kế tiếp, hết vòng thì quay lại đầu
            end
        else
            arrivedAt = 0
        end
        return targetCF
    end

    return { step = step, reset = reset }
end

--// ================= BONE FARM =================
local boneFarmConn
local BoneQuestPos = CFrame.new(-9516.99316, 172.017181, 6078.46533)
local BoneFarmPos = CFrame.new(-9495.6806640625, 453.58624267578125, 5977.3486328125) -- fallback khi chưa quét được pos spawn thật
local BonesTable = {"Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy"}
local bonePatrol = MakeSpawnPatroller(BonesTable, true) -- mỗi loại mob chỉ lấy 1 pos spawn thật, tween qua lại giữa 4 pos

function startBoneFarm()
    if boneFarmConn then boneFarmConn:Disconnect() end
    if not World3 then return end

    local lastUpdate = tick()
    boneFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmBone then return end
        local root = getRoot()
        if not root then return end
        local questUI = player.PlayerGui.Main.Quest
        local bone = GetNearestEnemy(BonesTable)
        
        getgenv().CurrentTargetMob = bone
    
        if bone then
            bonePatrol.reset() -- có mob lại -> lần hết mob kế tiếp patrol lại từ pos đầu
            if getgenv().AcceptQuestC and not questUI.Visible then
                if not getgenv().BypassAcceptQuest then
                    TweenToFixedPos(root, BoneQuestPos, getgenv().FlySpeed)
                    if (root.Position - BoneQuestPos.Position).Magnitude > 50 then return end
                end
                local randomQuest = math.random(1, 4)
                local questData = {
                    [1] = {"StartQuest", "HauntedQuest2", 2},
                    [2] = {"StartQuest", "HauntedQuest2", 1},
                    [3] = {"StartQuest", "HauntedQuest1", 1},
                    [4] = {"StartQuest", "HauntedQuest1", 2}
                }
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer(unpack(questData[randomQuest]))
                end)
                task.wait(1)
            end
            
            if bone:FindFirstChild("HumanoidRootPart") then
                local targetCF = GetFarmCFrame(bone)
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                AttackEnemy(bone)
            end
        else
            getgenv().CurrentTargetMob = nil
            -- Hết mob -> tween qua lại giữa pos spawn thật của 4 loại mob Bone
            -- (không tween về pos chờ cố định nữa)
            local reached = bonePatrol.step(root, getgenv().FlySpeed)
            if not reached then
                TweenToFixedPos(root, BoneFarmPos, getgenv().FlySpeed) -- fallback: chưa quét được pos spawn
            end
        end
    end)
end

function stopBoneFarm()
    if boneFarmConn then 
        boneFarmConn:Disconnect() 
        boneFarmConn = nil
    end
    getgenv().CurrentTargetMob = nil
end

--// ================= KATA FARM =================
local kataFarmConn
local CakeQuestPos = CFrame.new(-1927.92, 37.8, -12842.54)
local CakeTeleportPos = CFrame.new(-2151.82, 149.32, -12404.91)
local CakeMirrorPos = CFrame.new(-2151.82, 149.32, -12404.91)
local CakePrinceTable = {"Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker"}
local kataPatrol = MakeSpawnPatroller(CakePrinceTable, true) -- mỗi loại mob chỉ lấy 1 pos spawn thật, tween qua lại giữa 4 pos

function startKataFarm()
    if kataFarmConn then kataFarmConn:Disconnect() end
    if not World3 then return end
    
    local lastUpdate = tick()
    local mirrorTweenDone = false  -- Flag: đã tween đến mirror, đang delay chờ Cake Prince spawn
    local mirrorTweenTime = 0      -- Thời điểm bắt đầu delay

    kataFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmKata then return end
        local root = getRoot()
        if not root then return end
        local questUI = player.PlayerGui.Main.Quest
        local cakeMap = workspace.Map:FindFirstChild("CakeLoaf")
        local bigMirror = cakeMap and cakeMap:FindFirstChild("BigMirror")
        
        if not bigMirror or not bigMirror:FindFirstChild("Other") then
            getgenv().CurrentTargetMob = nil
            mirrorTweenDone = false
            TweenToFixedPos(root, CakeTeleportPos, getgenv().FlySpeed)
            return
        end
        
        if bigMirror.Other.Transparency == 0 or workspace.Enemies:FindFirstChild("Cake Prince") then
            local cakePrince = GetNearestEnemy("Cake Prince")
            getgenv().CurrentTargetMob = cakePrince
            
            if cakePrince then
                -- Có Cake Prince rồi → reset flag, farm bình thường
                mirrorTweenDone = false

                local cpHRP = cakePrince:FindFirstChild("HumanoidRootPart")

                -- Farm bình thường
                if cpHRP then
                    local mPos2  = cpHRP.Position
                    local mCF2   = cpHRP.CFrame
                    local lRaw2  = Vector3.new(mCF2.LookVector.X, 0, mCF2.LookVector.Z)
                    local lFlat2 = lRaw2.Magnitude > 0.01 and lRaw2.Unit or Vector3.new(0, 0, 1)
                    local yOff
                    if _G.ChooseWP == "Blox Fruit" then
                        yOff = 15
                    else
                        yOff = 25
                    end
                    local bossPos = Vector3.new(mPos2.X, mPos2.Y + yOff, mPos2.Z)
                    targetCF = CFrame.new(bossPos, bossPos + lFlat2)
                end
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                AttackEnemy(cakePrince)
            else
                if bigMirror.Other.Transparency == 0 then
                    getgenv().CurrentTargetMob = nil

                    if not mirrorTweenDone then
                        -- Lần đầu phát hiện mirror mở → tween đến mirror và bắt đầu delay
                        mirrorTweenDone = true
                        mirrorTweenTime = tick()
                        TweenToFixedPos(root, CakeMirrorPos, getgenv().FlySpeed)
                    elseif tick() - mirrorTweenTime < 0.8 then
                        -- Đang trong thời gian delay 0.8s → đứng yên chờ Cake Prince spawn
                        return
                    end
                    -- Sau 0.8s: tiếp tục vòng lặp bình thường (sẽ detect Cake Prince nếu đã spawn)
                end
            end
        else
            local cakeMob = GetNearestEnemy(CakePrinceTable)
            getgenv().CurrentTargetMob = cakeMob
            
            if cakeMob then
                kataPatrol.reset() -- có mob lại -> lần hết mob kế tiếp patrol lại từ pos đầu
                if getgenv().AcceptQuestC and not questUI.Visible then
                    if not getgenv().BypassAcceptQuest then
                        TweenToFixedPos(root, CakeQuestPos, getgenv().FlySpeed)
                        if (root.Position - CakeQuestPos.Position).Magnitude > 50 then return end
                    end
                    local randomQuest = math.random(1, 4)
                    local questData = {
                        [1] = {"StartQuest", "CakeQuest2", 2},
                        [2] = {"StartQuest", "CakeQuest2", 1},
                        [3] = {"StartQuest", "CakeQuest1", 1},
                        [4] = {"StartQuest", "CakeQuest1", 2}
                    }
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer(unpack(questData[randomQuest]))
                    end)
                    task.wait(1)
                end
                
                local targetCF = GetFarmCFrame(cakeMob)
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                AttackEnemy(cakeMob)
            else
                getgenv().CurrentTargetMob = nil
                -- Hết mob -> tween qua lại giữa pos spawn thật của 4 loại mob Kata
                -- (không tween về pos chờ cố định nữa)
                local reached = kataPatrol.step(root, getgenv().FlySpeed)
                if not reached then
                    TweenToFixedPos(root, CakeTeleportPos, getgenv().FlySpeed) -- fallback: chưa quét được pos spawn
                end
            end
        end
    end)
end

function stopKataFarm()
    if kataFarmConn then 
        kataFarmConn:Disconnect() 
        kataFarmConn = nil
    end
    getgenv().CurrentTargetMob = nil
end

--// ================= AURA FARM =================
local auraFarmConn
local AuraFarmPos = Vector3.new(-5000, 100, 5000)

function startAuraFarm()
    if auraFarmConn then auraFarmConn:Disconnect() end
    local lastUpdate = tick()
    
    auraFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmAura then return end
        local root = getRoot()
        if not root then return end
        local enemy = GetAnyEnemy()
        
        getgenv().CurrentTargetMob = enemy
        
        if enemy then
            if enemy:FindFirstChild("HumanoidRootPart") then
                local targetCF = GetFarmCFrame(enemy)
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                AttackEnemy(enemy)
            end
        else
            getgenv().CurrentTargetMob = nil
            TweenToFixedPos(root, CFrame.new(AuraFarmPos), getgenv().FlySpeed)
        end
    end)
end

function stopAuraFarm()
    if auraFarmConn then 
        auraFarmConn:Disconnect() 
        auraFarmConn = nil
    end
    getgenv().CurrentTargetMob = nil
end

--// ================= TYRANT OF THE SKIES FARM =================
local tyrantFarmConn
local TyrantBossPos = Vector3.new(-16268.287, 152.616, 1390.773)
local TyrantMobList = {"Serpent Hunter", "Skull Slayer", "Isle Champion", "Sun-kissed Warrior"}

function startTyrantFarm()
    if tyrantFarmConn then tyrantFarmConn:Disconnect() end
    if not World3 then return end
    
    tyrantFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmTyrant then return end
        
        pcall(function()
            local root = getRoot()
            if not root then return end
            
            if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("TikiOutpost") then
                local eyes = {
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye1"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye2"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye3"),
                    workspace.Map.TikiOutpost.IslandModel:FindFirstChild("Eye4")
                }
                local count = 0
                for _, eye in ipairs(eyes) do
                    if eye and eye:IsA("BasePart") and eye.Transparency == 0 then
                        count = count + 1
                    end
                end
                if count == 4 and not getgenv().FarmPhaBinh then
                    getgenv().FarmTyrant = false
                    getgenv().FarmPhaBinh = true
                    getgenv().CurrentTargetMob = nil
                    stopTyrantFarm()
                    startPhaBinhFarm()
                    return
                end
            end
            
            local boss = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
            if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then
                getgenv().CurrentTargetMob = boss
                
                if (root.Position - TyrantBossPos).Magnitude > 10 then
                    TweenToFixedPos(root, CFrame.new(TyrantBossPos), getgenv().FlySpeed)
                    return
                end
                selectWeapon()
                AttackEnemy(boss)
                return
            end
            
            local targetMob = nil
            for _, mobName in ipairs(TyrantMobList) do
                targetMob = GetNearestEnemy(mobName)
                if targetMob then break end
            end
            
            getgenv().CurrentTargetMob = targetMob
            
            if targetMob then
                local targetCF = GetFarmCFrame(targetMob)
                if targetCF and (root.Position - targetCF.Position).Magnitude > 20 then
                    TweenObject(root, targetCF, getgenv().FlySpeed)
                end
                
                selectWeapon()
                AttackEnemy(targetMob)
            else
                getgenv().CurrentTargetMob = nil
                if (root.Position - TyrantBossPos).Magnitude > 10 then
                    TweenToFixedPos(root, CFrame.new(TyrantBossPos), getgenv().FlySpeed)
                end
            end
        end)
    end)
end

function stopTyrantFarm()
    if tyrantFarmConn then
        tyrantFarmConn:Disconnect()
        tyrantFarmConn = nil
    end
    getgenv().CurrentTargetMob = nil
end

--// ================= BREAK POTS FARM (TIKI) =================
local phaBinhFarmConn
local PhaBinhPoints = {
    CFrame.new(-16332.5263671875, 158.07200622558594, 1440.324951171875),
    CFrame.new(-16288.609375, 158.16700744628906, 1470.3680419921875),
    CFrame.new(-16245.412109375, 158.43699645996094, 1463.365966796875),
    CFrame.new(-16212.46875, 158.16700744628906, 1466.343994140625),
    CFrame.new(-16211.9462890625, 158.07200622558594, 1322.39794921875),
    CFrame.new(-16260.921875, 154.92100524902344, 1323.615966796875),
    CFrame.new(-16297.0595703125, 159.322998046875, 1317.2239990234375),
    CFrame.new(-16335.0966796875, 159.33399963378906, 1324.885986328125),
}
local currentPointIndex = 1

function startPhaBinhFarm()
    if phaBinhFarmConn then phaBinhFarmConn:Disconnect() end
    if not World3 then return end
    
    phaBinhFarmConn = RunService.Heartbeat:Connect(function()
        if not getgenv().FarmPhaBinh then return end
        
        pcall(function()
            local root = getRoot()
            if not root then return end
            
            local boss = workspace.Enemies:FindFirstChild("Tyrant of the Skies")
            if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then
                getgenv().FarmPhaBinh = false
                getgenv().FarmTyrant = true
                stopPhaBinhFarm()
                startTyrantFarm()
                return
            end
            
            local targetCF = PhaBinhPoints[currentPointIndex]
            local dist = (root.Position - targetCF.Position).Magnitude
            
            if dist > 5 then
                TweenObject(root, targetCF, getgenv().FlySpeed)
                return
            end
            
            if not player.Character:FindFirstChild("HasBuso") and not player.Character:FindFirstChild("Buso") then
                ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
            end
            
            equipAndUseSkills("Melee")
            equipAndUseSkills("Sword")
            equipAndUseSkills("Gun")
            
            currentPointIndex = currentPointIndex + 1
            if currentPointIndex > #PhaBinhPoints then
                currentPointIndex = 1
            end
            
            task.wait(0.5)
        end)
    end)
end

function stopPhaBinhFarm()
    if phaBinhFarmConn then
        phaBinhFarmConn:Disconnect()
        phaBinhFarmConn = nil
    end
    currentPointIndex = 1
end

--// ================= DUNGEON FARM =================
local dungeonFarmConn
local _dungeonExitReachedTime = 0  -- timestamp khi đến exit, dùng cho delay 1s

local function GetCurrentZone()
    local root = getRoot()
    if not root then return nil end
    
    local nearestZone = nil
    local minDistance = math.huge
    local dungeonFolder = workspace.Map:FindFirstChild("Dungeon")
    
    if not dungeonFolder then return nil end
    
    for _, zone in ipairs(dungeonFolder:GetChildren()) do
        local zoneRoot = zone:FindFirstChild("Root")
        if zoneRoot and zone:FindFirstChild("ExitTeleporter") then
            local dist = (zoneRoot.Position - root.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                nearestZone = zone
            end
        end
    end
    
    return nearestZone
end


-- Tìm Shrine gần player nhất (không lấy theo thứ tự GetChildren)
local function FindShrine()
    local root = getRoot()
    local best, bestDist = nil, math.huge

    for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
        if enemy.Name == "Shrine"
            and enemy:FindFirstChild("Humanoid")
            and enemy:FindFirstChild("HumanoidRootPart")
            and enemy.Humanoid.Health > 0
        then
            local dist = root
                and (enemy.HumanoidRootPart.Position - root.Position).Magnitude
                or 0
            if dist < bestDist then
                bestDist = dist
                best = enemy
            end
        end
    end

    return best
end

-- Helper: kiểm tra object có label "Destroy" (BillboardGui hoặc tên trực tiếp)
local function isDestroyTarget(obj)
    if not obj:FindFirstChild("Humanoid") then return false end
    if not obj:FindFirstChild("HumanoidRootPart") then return false end
    if obj.Humanoid.Health <= 0 then return false end

    -- Cách 1: tên Instance khớp trực tiếp
    if obj.Name == "Destroy" then return true end

    -- Cách 2: có BillboardGui chứa TextLabel với text "Destroy"
    for _, child in ipairs(obj:GetDescendants()) do
        if child:IsA("TextLabel") and string.find(child.Text, "Destroy") then
            return true
        end
    end

    return false
end

-- Tìm mob "Destroy" gần player nhất (ưu tiên cao nhất)
-- Trước đây lấy theo thứ tự GetChildren → xa phá trước, gần phá sau
local function FindDestroy()
    local root = getRoot()
    local best, bestDist = nil, math.huge

    local function consider(obj)
        if not isDestroyTarget(obj) then return end
        local hrp = obj.HumanoidRootPart
        local dist = root and (hrp.Position - root.Position).Magnitude or 0
        if dist < bestDist then
            bestDist = dist
            best = obj
        end
    end

    -- Tìm trong workspace.Enemies
    for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
        consider(enemy)
    end

    -- Fallback: tìm trong workspace (phòng khi Destroy spawn ngoài Enemies)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name ~= "Enemies" then
            consider(obj)
        end
    end

    return best
end


local function GetValidDungeonEnemies()
    local root = getRoot()
    local validEnemies = {}

    for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
        if enemy:FindFirstChild("Humanoid") and enemy:FindFirstChild("HumanoidRootPart") then
            if enemy.Humanoid.Health > 0 then
                -- Chỉ bỏ qua Blank Buddy, farm tất cả mob còn lại
                if enemy.Name == "Blank Buddy" then
                    continue
                end
                table.insert(validEnemies, enemy)
            end
        end
    end

    -- Sắp xếp theo khoảng cách gần nhất trước
    if root and #validEnemies > 1 then
        local playerPos = root.Position
        table.sort(validEnemies, function(a, b)
            local dA = (a.HumanoidRootPart.Position - playerPos).Magnitude
            local dB = (b.HumanoidRootPart.Position - playerPos).Magnitude
            return dA < dB
        end)
    end

    return validEnemies
end



function startDungeonFarm()
    if dungeonFarmConn then dungeonFarmConn:Disconnect() end
    _dungeonExitReachedTime = 0
    
    if game.PlaceId ~= DungeonPlaceId then
        Library:Notify({
            Title = "Wrong Place",
            Content = "Dungeon farm chỉ hoạt động trong Dungeon!",
            Duration = 5
        })
        return
    end
    
    dungeonFarmConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmDungeon then return end
        
        pcall(function()
            local root = getRoot()
            if not root then return end
            
            local currentZone = GetCurrentZone()
            if not currentZone then return end
            
            local exitTeleporter = currentZone:FindFirstChild("ExitTeleporter")
            if not exitTeleporter then return end
            
            local exitRoot = exitTeleporter:FindFirstChild("Root")
            if not exitRoot then return end
            
            -- Kiểm tra đã đến exit teleporter (BBG visible)
            if exitRoot:FindFirstChild("BBG") then
                TweenObject(root, exitRoot.CFrame, getgenv().FlySpeed)
                -- Delay 1s tại exit (timestamp-based, tránh coroutine stacking)
                if _dungeonExitReachedTime == 0 then
                    _dungeonExitReachedTime = tick()
                end
                if tick() - _dungeonExitReachedTime < 1 then
                    return  -- Đang chờ đủ 1s tại exit
                end
                -- Đã đủ 1s → reset timer, teleporter tự xử lý zone transition
                _dungeonExitReachedTime = 0
                return
            else
                _dungeonExitReachedTime = 0  -- Reset khi BBG biến mất (đã qua zone mới)
            end
            
            -------- PRIORITY 1: DESTROY MObS (Highest) --------
            local destroy = FindDestroy()
            if destroy then
                getgenv().CurrentTargetMob = destroy
                local targetCF = GetFarmCFrame(destroy)
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                selectWeapon()
                AttackEnemy(destroy)
                return
            end
            
            -------- PRIORITY 2: SHRINE (High) --------
            local shrine = FindShrine()
            if shrine then
                getgenv().CurrentTargetMob = shrine
                local targetCF = GetFarmCFrame(shrine)
                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                selectWeapon()
                AttackEnemy(shrine)
                return
            end
            
            -------- PRIORITY 3: FARM ALL MOB (không giới hạn phạm vi) --------
            local enemies = GetValidDungeonEnemies()

            if #enemies > 0 then
                -- Fly đến mob gần nhất, attack tất cả mob còn sống
                local nearest = enemies[1]
                getgenv().CurrentTargetMob = nearest

                if nearest:FindFirstChild("HumanoidRootPart") then
                    local targetCF = GetFarmCFrame(nearest)
                    if targetCF then
                        TweenObject(root, targetCF, getgenv().FlySpeed)
                    end
                end

                selectWeapon()
                for _, enemy in ipairs(enemies) do
                    if enemy:FindFirstChild("Humanoid") and enemy.Humanoid.Health > 0 then
                        AttackEnemy(enemy)
                    end
                end
            else
                -------- HẾT MOB -> FLY ĐẾN EXIT --------
                getgenv().CurrentTargetMob = nil
                if exitRoot then
                    TweenObject(root, exitRoot.CFrame, getgenv().FlySpeed)
                end
            end
        end)
    end)
end

function stopDungeonFarm()
    if dungeonFarmConn then
        dungeonFarmConn:Disconnect()
        dungeonFarmConn = nil
    end
    _dungeonExitReachedTime = 0
    getgenv().CurrentTargetMob = nil
end

--// ================= MATERIAL FARM LOOP =================
-- Hết mob -> tween qua pos spawn THẬT của nguyên liệu đang chọn thay vì bay
-- về 1 pos mặc định cố định (MPos chỉ còn dùng làm fallback khi chưa quét
-- được pos nào). Nguyên liệu nào có nhiều hơn 1 loại mob (Dragon Scale,
-- Magma Ore, Angel Wings...) sẽ tween qua HẾT pos spawn của TẤT CẢ loại mob
-- thuộc nguyên liệu đó rồi mới lặp lại từ đầu; nguyên liệu chỉ có 1 loại mob
-- thì tween qua lại giữa các pos spawn thật của đúng loại mob đó.
local _matPatroller = nil
local _matPatrolKey  = nil -- SelectMaterial hiện tại, dùng để phát hiện đổi loại nguyên liệu

spawn(function()
    while task.wait() do
        if getgenv().AutoMaterial and getgenv().SelectMaterial then
            pcall(function()
                MaterialMon()

                local target = GetNearestEnemy(MMon)
                local root = getRoot()

                getgenv().CurrentTargetMob = target

                if target and target:FindFirstChild("HumanoidRootPart") then
                    -- Có mob: đánh bình thường (reset patrol để lần hết mob kế
                    -- tiếp tuần tra lại từ pos đầu)
                    if _matPatroller then _matPatroller.reset() end
                    local targetCF = GetFarmCFrame(target)
                    if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                    AttackEnemy(target)

                else
                    -- Hết mob: tween qua pos spawn thật của (các) loại mob thuộc
                    -- nguyên liệu đang chọn, xoay vòng liên tục cho tới khi có mob
                    getgenv().CurrentTargetMob = nil

                    if _matPatrolKey ~= getgenv().SelectMaterial then
                        -- Đổi loại nguyên liệu -> tạo lại patroller ứng với danh
                        -- sách mob (MMon) của loại nguyên liệu mới
                        _matPatrolKey = getgenv().SelectMaterial
                        _matPatroller = MakeSpawnPatroller(MMon, false)
                    end

                    local reached = _matPatroller and _matPatroller.step(root, getgenv().FlySpeed)
                    if not reached and MPos then
                        -- Fallback: chưa quét được pos spawn thật nào -> dùng pos mặc định
                        TweenToFixedPos(root, MPos, getgenv().FlySpeed)
                    end
                end
            end)
        end
    end
end)

--------------------------------------------------------------------
-- BUDDHA WRAPPER
--------------------------------------------------------------------
local function doBuddhaStartSequence(callback)
    if IsBuddhaFruit() then
        getgenv().BuddhaActive = true
        ActivateBuddha()
        task.wait(0.3)
    end
    if callback then callback() end
end

local function doBuddhaStopSequence(callback)
    if callback then callback() end
    if getgenv().BuddhaActive then
        task.wait(0.2)
        ActivateBuddha()
        task.wait(0.5)
        DeactivateBuddha()
        getgenv().BuddhaActive = false
    end
end

--------------------------------------------------------------------
-- PATCH: Wrap startFly + stopFly với Buddha logic
--------------------------------------------------------------------
local _origStartFly = startFly
function startFly()
    if getgenv().BuddhaFarm and IsBuddhaFruit() and not getgenv().BuddhaActive then
        getgenv().BuddhaActive = true
        _origStartFly()
        task.spawn(function()
            ActivateBuddha()
        end)
    else
        _origStartFly()
    end
end

local _origStopFly = stopFly
function stopFly()
    _origStopFly()
    if getgenv().BuddhaActive and getgenv().BuddhaFarm then
        task.spawn(function()
            task.wait(0.1)
            getgenv().BuddhaTransforming = true
            local char = player.Character
            local backpack = player.Backpack
            if char and backpack then
                local currentTool = char:FindFirstChildOfClass("Tool")
                if currentTool then
                    currentTool.Parent = backpack
                end
                task.wait(0.1)
                local buddhaItem = nil
                for _, v in pairs(backpack:GetChildren()) do
                    if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then
                        buddhaItem = v
                        break
                    end
                end
                if buddhaItem then
                    char.Humanoid:EquipTool(buddhaItem)
                end
                task.wait(0.3)
                VirtualInputManager:SendKeyEvent(true, "Z", false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, "Z", false, game)
                task.wait(0.5)
                local fruitTool = char:FindFirstChildOfClass("Tool")
                if fruitTool and fruitTool.ToolTip == "Blox Fruit" then
                    fruitTool.Parent = backpack
                end
            end
            getgenv().BuddhaTransforming = false
            getgenv().BuddhaActive = false
            print("Buddha deactivated - farm stopped completely.")
        end)
    end
end

--------------------------------------------------------------------
-- BUDDHA RESPAWN LOGIC
--------------------------------------------------------------------
player.CharacterAdded:Connect(function(newChar)
    local hum = newChar:WaitForChild("Humanoid", 10)
    if hum then
        hum.Died:Connect(function()
            if (getgenv().IsFarming or getgenv().AutoMaterial) and IsBuddhaFruit() and getgenv().BuddhaFarm then
                getgenv().BuddhaTransforming = true
                getgenv().BuddhaActive = false
                print("Character died - pausing farm until respawn...")
            end
        end)
    end

    -- ── GENERAL RESPAWN: delay 0.5s sau khi hồi sinh, bật lại fly ──
    -- Áp dụng cho mọi chế độ farm (kể cả khi không dùng Buddha)
    local anyFarmActive = getgenv().IsFarming or getgenv().AutoMaterial or getgenv().FarmDungeon
    if anyFarmActive then
        task.spawn(function()
            local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
            if not hrp then return end
            task.wait(0.5)
            if getgenv().IsFarming or getgenv().AutoMaterial or getgenv().FarmDungeon then
                startFly()
                print("🔄 Hồi sinh xong — tiếp tục farm sau 0.5s!")
            end
        end)
    end

    if not getgenv().IsFarming and not getgenv().AutoMaterial then return end
    if not IsBuddhaFruit() then return end
    if not getgenv().BuddhaFarm then return end

    getgenv().BuddhaTransforming = true
    getgenv().BuddhaActive = false

    task.spawn(function()
        local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
        local hum = newChar:WaitForChild("Humanoid", 10)
        if not hrp or not hum then
            getgenv().BuddhaTransforming = false
            return
        end
        task.wait(1)
        local backpack = player.Backpack
        local currentTool = newChar:FindFirstChildOfClass("Tool")
        if currentTool then
            currentTool.Parent = backpack
        end
        task.wait(0.1)
        local buddhaItem = nil
        for _, v in pairs(backpack:GetChildren()) do
            if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then
                buddhaItem = v
                break
            end
        end
        if buddhaItem then
            hum:EquipTool(buddhaItem)
        end
        task.wait(0.3)
        VirtualInputManager:SendKeyEvent(true, "Z", false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, "Z", false, game)
        task.wait(0.5)
        getgenv().BuddhaActive = true
        getgenv().BuddhaTransforming = false
        print("Buddha re-activated after respawn - resuming farm!")
    end)
end)

pcall(function()
    local currentChar = player.Character
    if currentChar then
        local hum = currentChar:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Died:Connect(function()
                if (getgenv().IsFarming or getgenv().AutoMaterial) and IsBuddhaFruit() and getgenv().BuddhaFarm then
                    getgenv().BuddhaTransforming = true
                    getgenv().BuddhaActive = false
                    print("Character died - pausing farm until respawn...")
                end
            end)
        end
    end
end)

--------------------------------------------------------------------
-- INTERFACE MANAGER (Fluent-Renewed) – chỉ quản lý theme / màu
--------------------------------------------------------------------
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetFolder("TopiHub")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)

--------------------------------------------------------------------
-- HỆ THỐNG SAVE / LOAD RIÊNG (Library.Options)
-- Lưu tất cả Toggle / Dropdown / Slider / Colorpicker vào JSON
-- File: TopiHub/<tên player>-config.json
--------------------------------------------------------------------
local _SV_FOLDER = "TopiHub"
local _SV_FILE   = _SV_FOLDER .. "/" .. Players.LocalPlayer.Name .. "-config.json"
if not isfolder(_SV_FOLDER) then makefolder(_SV_FOLDER) end

-- Các key không lưu (theme được InterfaceManager quản lý riêng)
local _SV_IGNORE = {InterfaceTheme = true, InterfaceTransparency = true, MinimizeKeybind = true}

local function SaveConfig()
    pcall(function()
        local data = {}
        for id, opt in pairs(Library.Options) do
            if not _SV_IGNORE[id] and opt.Value ~= nil then
                local v = opt.Value
                if typeof(v) == "Color3" then
                    v = {__color = true, R = v.R, G = v.G, B = v.B}
                elseif typeof(v) == "EnumItem" then
                    v = tostring(v)
                end
                data[id] = v
            end
        end
        writefile(_SV_FILE, HttpService:JSONEncode(data))
    end)
end

local function LoadConfig()
    task.spawn(function()
        task.wait(0.6) -- Chờ toàn bộ UI mount xong

        local loaded = false
        pcall(function()
            if not isfile(_SV_FILE) then return end
            local data = HttpService:JSONDecode(readfile(_SV_FILE))

            -- ── PASS 1: Load Dropdown / Slider / Colorpicker trước ──────────
            -- Các biến global (SelectedFarm, FlySpeed...) phải
            -- được set TRƯỚC khi toggle farm bật và gọi logic farm.
            for id, value in pairs(data) do
                local opt = Library.Options[id]
                if opt and opt.Type ~= "Toggle" then
                    pcall(function()
                        if type(value) == "table" and value.__color then
                            opt:SetValue(Color3.new(value.R, value.G, value.B))
                        else
                            opt:SetValue(value)
                        end
                    end)
                end
            end

            -- ── PASS 2: Load Toggle ─────────────────────────────────────────
            -- SetValue() chỉ cập nhật visual, KHÔNG fire Callback.
            -- → Sau SetValue, gọi thủ công _ToggleCBs[id](value) để
            --   kích hoạt đúng logic (farm, esp, fly, v.v.)
            task.wait(0.15)
            for id, value in pairs(data) do
                local opt = Library.Options[id]
                if opt and opt.Type == "Toggle" then
                    pcall(function()
                        opt:SetValue(value)           -- cập nhật visual
                    end)
                    if value == true and _ToggleCBs[id] then
                        task.spawn(_ToggleCBs[id], true)  -- kích hoạt logic
                    end
                end
            end

            loaded = true
        end)

        if loaded then
            Library:Notify({
                Title = "✅ Settings Loaded",
                Content = "Đã khôi phục cài đặt từ lần chạy trước.",
                Duration = 4
            })
        end
    end)
end

-- Auto-save mỗi 5 giây
task.spawn(function()
    while task.wait(5) do
        SaveConfig()
    end
end)

-- Hàm khởi động load (gọi cuối file sau khi tất cả elements đã tạo)
local function AutoLoad()
    LoadConfig()
end


Window:SelectTab(1)
Library:Notify({Title = "Script Loaded", Content = "All Features Ready + Buddha Logic + Respawn + Dungeon Farm + Stats Upgrade", Duration = 5})

--------------------------------------------------------------------
-- TAB QUESTS: AUTO ELITE QUEST
--------------------------------------------------------------------
Tabs.Quests:AddSection("Elite Hunt")

local EliteNames = {"Diablo", "Urban", "Deandre"}

local function IsEliteName(name)
    for _, eName in pairs(EliteNames) do
        if string.find(name, eName) then
            return true
        end
    end
    return false
end

local function GetNearestEliteEnemy()
    local root = getRoot()
    if not root then return nil end
    local nearest, dist = nil, math.huge
    for _, mob in pairs(workspace.Enemies:GetChildren()) do
        if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            if IsEliteName(mob.Name) then
                local mag = (mob.HumanoidRootPart.Position - root.Position).Magnitude
                if mag < dist then
                    dist = mag
                    nearest = mob
                end
            end
        end
    end
    return nearest
end

local function GetEliteReplicatedPart()
    local replicated = ReplicatedStorage
    for _, v in pairs(replicated:GetChildren()) do
        if IsEliteName(v.Name) then
            if v:FindFirstChild("HumanoidRootPart") then
                return v
            end
        end
    end
    return nil
end

local eliteHuntConn   -- Heartbeat connection cho lúc đang farm elite
local eliteWatchConn  -- Heartbeat connection cho lúc chờ elite xuất hiện

-- Trạng thái stack farming
getgenv().EliteActive   = false  -- Đang trong phiên farm elite
getgenv().NormalPaused  = false  -- Normal farm đang bị tạm dừng do elite

--------------------------------------------------------------------
-- HÀM TIỆN ÍCH: KIỂM TRA ELITE CÓ SẴN KHÔNG
--------------------------------------------------------------------
-- Trả về true nếu có elite trong ReplicatedStorage HOẶC đang có quest elite
local function IsEliteAvailable()
    -- Cách 1: Elite đã spawn → xuất hiện trong ReplicatedStorage
    if GetEliteReplicatedPart() then return true end
    -- Cách 2: Quest elite đang active
    local questUI = player.PlayerGui:FindFirstChild("Main")
    if questUI then
        local questPanel = questUI:FindFirstChild("Quest")
        if questPanel and questPanel.Visible then
            local titleFrame = questPanel:FindFirstChild("Container")
            local questTitleObj = titleFrame and titleFrame:FindFirstChild("QuestTitle")
            local titleLabel = questTitleObj and questTitleObj:FindFirstChild("Title")
            local titleText = titleLabel and titleLabel.Text or ""
            if IsEliteName(titleText) then return true end
        end
    end
    return false
end

--------------------------------------------------------------------
-- TẠM DỪNG / TIẾP TỤC NORMAL FARM
--------------------------------------------------------------------
local function PauseNormalFarm()
    if getgenv().NormalPaused then return end
    getgenv().NormalPaused = true
    -- Dừng các loop farm bình thường (không tắt flag IsFarming/FarmLevel/v.v.)
    stopLevelFarm()
    stopBoneFarm()
    stopKataFarm()
    stopAuraFarm()
    stopTyrantFarm()
    stopPhaBinhFarm()
    print("⏸ Normal farm tạm dừng để farm Elite")
end

local function ResumeNormalFarm()
    if not getgenv().NormalPaused then return end
    getgenv().NormalPaused = false
    -- Khởi động lại đúng loại farm theo SelectedFarm
    if getgenv().FarmLevel and SelectedFarm == "Farm cấp" then
        startLevelFarm()
    elseif getgenv().FarmBone and SelectedFarm == "Farm bone" then
        startBoneFarm()
    elseif getgenv().FarmKata and SelectedFarm == "Farm kata" then
        startKataFarm()
    elseif getgenv().FarmAura and SelectedFarm == "Farm aura" then
        startAuraFarm()
    elseif getgenv().FarmTyrant and SelectedFarm == "Tyrant of the Skie" then
        startTyrantFarm()
    end
    print("▶ Normal farm tiếp tục sau khi Elite xong")
end

--------------------------------------------------------------------
-- FARM ELITE (MỘT PHIÊN): chạy cho đến khi quest elite kết thúc
--------------------------------------------------------------------
local function startEliteHunt()
    if eliteHuntConn then eliteHuntConn:Disconnect() end
    getgenv().EliteActive = true

    eliteHuntConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().FarmEliteHunt then return end
        pcall(function()
            local root = getRoot()
            if not root then return end

            local questUI = player.PlayerGui:FindFirstChild("Main")
            if not questUI then return end
            local questPanel = questUI:FindFirstChild("Quest")
            if not questPanel then return end

            if questPanel.Visible then
                local titleFrame = questPanel:FindFirstChild("Container")
                local questTitleObj = titleFrame and titleFrame:FindFirstChild("QuestTitle")
                local titleLabel = questTitleObj and questTitleObj:FindFirstChild("Title")
                local titleText = titleLabel and titleLabel.Text or ""

                if IsEliteName(titleText) then
                    -- Đang có quest elite → farm
                    local repPart = GetEliteReplicatedPart()
                    if repPart then
                        local repPos = repPart.HumanoidRootPart.Position
                        if (root.Position - repPos).Magnitude > 500 then
                            TweenToPos(repPart.HumanoidRootPart.CFrame, getgenv().FlySpeed)
                        end
                    end

                    local enemy = GetNearestEliteEnemy()
                    getgenv().CurrentTargetMob = enemy

                    if enemy and enemy:FindFirstChild("HumanoidRootPart") then
                        local targetCF = GetFarmCFrame(enemy)
                        if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                        AttackEnemy(enemy)
                    end
                else
                    -- Quest không phải elite → hủy quest sai nếu có
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("AbandonQuest")
                    end)
                    task.wait(0.5)
                end
            else
                -- Không có quest: thử nhận elite quest
                local repPart = GetEliteReplicatedPart()
                if repPart then
                    getgenv().CurrentTargetMob = nil
                    pcall(function()
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("EliteHunter")
                    end)
                    task.wait(1)
                else
                    -- Elite đã biến mất (đã farm xong hoặc chưa spawn)
                    -- Kết thúc phiên farm elite này
                    eliteHuntConn:Disconnect()
                    eliteHuntConn = nil
                    getgenv().EliteActive = false
                    getgenv().CurrentTargetMob = nil

                    -- Tắt fly + farming nếu không có normal farm chạy song song
                    local anyNormalFarm = getgenv().FarmLevel or getgenv().FarmBone
                        or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                        or getgenv().AutoMaterial or getgenv().FarmDungeon
                    if not anyNormalFarm then
                        getgenv().IsFarming = false
                        getgenv().Noclip = false
                        getgenv().AutoBusoLoop = false
                        stopFly()
                    else
                        -- Có normal farm đang đợi → resume
                        ResumeNormalFarm()
                    end
                    print("✅ Elite farm xong, toggle vẫn bật — chờ elite tiếp theo")
                end
            end
        end)
    end)
end

local function stopEliteHunt()
    if eliteHuntConn then
        eliteHuntConn:Disconnect()
        eliteHuntConn = nil
    end
    if eliteWatchConn then
        eliteWatchConn:Disconnect()
        eliteWatchConn = nil
    end
    getgenv().EliteActive = false
    getgenv().CurrentTargetMob = nil
    -- Resume normal farm nếu đang bị pause
    ResumeNormalFarm()
end

--------------------------------------------------------------------
-- WATCHER: Liên tục poll, khi elite xuất hiện thì kích hoạt farm
--------------------------------------------------------------------
local function startEliteWatcher()
    if eliteWatchConn then eliteWatchConn:Disconnect() end

    eliteWatchConn = RunService.Heartbeat:Connect(function()
        if not getgenv().FarmEliteHunt then return end
        if getgenv().EliteActive then return end  -- Đang farm rồi, không cần check

        pcall(function()
            if IsEliteAvailable() then
                print("⚡ Phát hiện Elite! Bắt đầu farm elite...")
                -- Tạm dừng normal farm nếu đang chạy
                local anyNormalFarm = getgenv().FarmLevel or getgenv().FarmBone
                    or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                if anyNormalFarm then
                    PauseNormalFarm()
                end
                -- Đảm bảo fly + farming bật
                if not getgenv().IsFarming then
                    getgenv().IsFarming = true
                    getgenv().Noclip = true
                    getgenv().AutoBusoLoop = true
                    startFly()
                end
                startEliteHunt()
            end
        end)
    end)
end

--------------------------------------------------------------------
-- TOGGLE AUTO ELITE QUEST
--------------------------------------------------------------------
local Q = Tabs.Quests:CreateToggle("Q", {
    Title = "Auto Elite Quest",
    Description = "Tu dong farm Elite Quest. Tu dong dung khi xong va tiep tuc khi co elite moi.",
    Default = false
})

Q:OnChanged(function(Value)
    getgenv().FarmEliteHunt = Value

    if Value then
        print("✅ Bật Auto Elite Quest — đang chờ Elite xuất hiện...")
        -- Bật fly/farm ngay nếu đang có normal farm chạy
        local anyNormalFarm = getgenv().FarmLevel or getgenv().FarmBone
            or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
            or getgenv().AutoMaterial or getgenv().FarmDungeon
        if anyNormalFarm and not getgenv().IsFarming then
            getgenv().IsFarming = true
            getgenv().Noclip = true
            getgenv().AutoBusoLoop = true
            startFly()
        end
        -- Nếu elite đã có sẵn ngay lúc bật toggle, kích hoạt luôn
        if IsEliteAvailable() then
            local hasNormal = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
            if hasNormal then PauseNormalFarm() end
            if not getgenv().IsFarming then
                getgenv().IsFarming = true
                getgenv().Noclip = true
                getgenv().AutoBusoLoop = true
                startFly()
            end
            startEliteHunt()
        end
        startEliteWatcher()
    else
        stopEliteHunt()
        local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
            or getgenv().FarmAura or getgenv().FarmTyrant or getgenv().AutoMaterial
            or getgenv().FarmDungeon
        if not anyFarmActive then
            getgenv().IsFarming = false
            getgenv().Noclip = false
            getgenv().AutoBusoLoop = false
            stopFly()
        end
        print("❌ Tắt Auto Elite Quest")
    end
end)

--------------------------------------------------------------------
-- TAB QUESTS: AUTO SEA 2 & AUTO SEA 3 (TRAVEL)
-- Dùng chung fly / attack / TweenToPos của hệ thống farm
--------------------------------------------------------------------
Tabs.Quests:AddSection("Sea Travel")

getgenv().TravelDres = false
getgenv().AutoZou    = false

-- ================================================================
-- AUTO SEA 2 — Travel Dressrosa (Second Sea), yêu cầu lv >= 700
-- ================================================================
local AutoSea2Toggle = Tabs.Quests:CreateToggle("AutoSea2", {
    Title       = "Auto Sea 2",
    Description = "Tự động hoàn thành điều kiện và travel sang Second Sea (Dressrosa). Yêu cầu lv >= 700.",
    Default     = false,
})

AutoSea2Toggle:OnChanged(function(v)
    getgenv().TravelDres = v
    if v then
        getgenv().IsFarming = true
        getgenv().Noclip    = true
        startFly()
        Library:Notify({ Title = "Auto Sea 2", Content = "Đã bật — đang xử lý Travel Dressrosa...", Duration = 3 })
    else
        local anyFarm = getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
            or getgenv().FarmAura or getgenv().FarmTyrant or getgenv().AutoMaterial
            or getgenv().FarmDungeon or getgenv().AutoZou or getgenv().FarmEliteHunt
        if not anyFarm then
            getgenv().IsFarming = false
            getgenv().Noclip    = false
            stopFly()
        end
        Library:Notify({ Title = "Auto Sea 2", Content = "Đã tắt.", Duration = 2 })
    end
end)

spawn(function()
    while task.wait(Sec) do
        pcall(function()
            if not getgenv().TravelDres then return end
            if player.Data.Level.Value < 700 then return end

            local CommF = ReplicatedStorage.Remotes.CommF_
            local root  = getRoot()
            if not root then return end

            -- Lấy trạng thái cửa Ice một cách an toàn
            local map  = workspace:FindFirstChild("Map")
            local ice  = map and map:FindFirstChild("Ice")
            local door = ice and ice:FindFirstChild("Door")
            if not door then return end

            if door.CanCollide == true and door.Transparency == 0 then
                -- Bước 1: Gọi quest Detective để chuẩn bị mở cửa
                CommF:InvokeServer("DressrosaQuestProgress", "Detective")
                -- Trang bị chìa khóa nếu có trong backpack
                local keyTool = player.Backpack:FindFirstChild("Key")
                if keyTool and player.Character then
                    player.Character.Humanoid:EquipTool(keyTool)
                end
                -- Bay đến vị trí trước cửa bằng fly chung của farm
                TweenToPos(CFrame.new(1347.7124, 37.3751602, -1325.6488), getgenv().FlySpeed)

            elseif door.CanCollide == false and door.Transparency == 1 then
                -- Bước 2: Cửa đã mở — tìm Ice Admiral và tiêu diệt
                local admiral = GetNearestEnemy("Ice Admiral")
                if admiral and admiral:FindFirstChild("Humanoid") and admiral.Humanoid.Health > 0 then
                    getgenv().CurrentTargetMob = admiral
                    local targetCF = GetFarmCFrame(admiral)
                    if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                    AttackEnemy(admiral)
                    -- Kiểm tra sau khi đánh
                    if admiral.Humanoid.Health <= 0 then
                        task.wait(0.5)
                        CommF:InvokeServer("TravelDressrosa")
                    end
                else
                    -- Admiral đã chết hoặc không có → travel ngay
                    getgenv().CurrentTargetMob = nil
                    CommF:InvokeServer("TravelDressrosa")
                end
            else
                -- Cửa chưa sẵn sàng → thử gọi travel trực tiếp
                CommF:InvokeServer("TravelDressrosa")
            end
        end)
    end
end)

-- ================================================================
-- AUTO SEA 3 — Travel Zou (Third Sea), yêu cầu lv >= 1500
-- ================================================================
local AutoSea3Toggle = Tabs.Quests:CreateToggle("AutoSea3", {
    Title       = "Auto Sea 3",
    Description = "Tự động hoàn thành Bartilo Quest + mở FlamingoAccess và travel sang Third Sea (Zou). Yêu cầu lv >= 1500.",
    Default     = false,
})

AutoSea3Toggle:OnChanged(function(v)
    getgenv().AutoZou = v
    if v then
        getgenv().IsFarming = true
        getgenv().Noclip    = true
        startFly()
        Library:Notify({ Title = "Auto Sea 3", Content = "Đã bật — đang xử lý Travel Zou...", Duration = 3 })
    else
        local anyFarm = getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
            or getgenv().FarmAura or getgenv().FarmTyrant or getgenv().AutoMaterial
            or getgenv().FarmDungeon or getgenv().TravelDres or getgenv().FarmEliteHunt
        if not anyFarm then
            getgenv().IsFarming = false
            getgenv().Noclip    = false
            stopFly()
        end
        Library:Notify({ Title = "Auto Sea 3", Content = "Đã tắt.", Duration = 2 })
    end
end)

spawn(function()
    while task.wait(Sec) do
        pcall(function()
            if not getgenv().AutoZou then return end
            if player.Data.Level.Value < 1500 then return end

            local CommF = ReplicatedStorage.Remotes.CommF_
            local root  = getRoot()
            if not root then return end

            local bartiloProgress = CommF:InvokeServer("BartiloQuestProgress", "Bartilo")

            -- ── STAGE 3: Bartilo quest hoàn tất ──────────────────────────
            if bartiloProgress == 3 then
                local unlockables = CommF:InvokeServer("GetUnlockables")

                if unlockables and unlockables.FlamingoAccess ~= nil then
                    -- Đã có FlamingoAccess — xử lý ZQuest và travel Zou
                    local zProgress = CommF:InvokeServer("ZQuestProgress", "Check")

                    if zProgress == 0 then
                        -- Kill rip_indra để tiến hành ZQuest
                        local indra = GetNearestEnemy("rip_indra")
                        if indra and indra:FindFirstChild("Humanoid") and indra.Humanoid.Health > 0 then
                            getgenv().CurrentTargetMob = indra
                            local targetCF = GetFarmCFrame(indra)
                            if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                            AttackEnemy(indra)
                            if indra.Humanoid.Health <= 0 then
                                task.wait(0.5)
                                CommF:InvokeServer("F_", "TravelZou")
                            end
                        else
                            CommF:InvokeServer("F_", "ZQuestProgress", "Check")
                            task.wait(0.1)
                            CommF:InvokeServer("F_", "ZQuestProgress", "Begin")
                        end

                    elseif zProgress == 1 then
                        -- ZQuest hoàn tất, travel thẳng
                        CommF:InvokeServer("F_", "TravelZou")

                    else
                        -- Kill Don Swan để unlock Zou
                        local donSwan = GetNearestEnemy("Don Swan")
                        if donSwan and donSwan:FindFirstChild("Humanoid") and donSwan.Humanoid.Health > 0 then
                            getgenv().CurrentTargetMob = donSwan
                            local targetCF = GetFarmCFrame(donSwan)
                            if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                            AttackEnemy(donSwan)
                        else
                            getgenv().CurrentTargetMob = nil
                            TweenToPos(CFrame.new(2288.802, 15.1870775, 863.034607), getgenv().FlySpeed)
                        end
                    end

                else
                    -- Chưa có FlamingoAccess — dùng Devil Fruit nói chuyện Trevor để unlock
                    local TabelDevilFruitStore = {}
                    local TabelDevilFruitOpen  = {}

                    for _, e in pairs(CommF:InvokeServer("getInventoryFruits")) do
                        for k, val in pairs(e) do
                            if k == "Name" then
                                table.insert(TabelDevilFruitStore, val)
                            end
                        end
                    end

                    for _, e in next, CommF:InvokeServer("GetFruits") do
                        if e.Price >= 1000000 then
                            table.insert(TabelDevilFruitOpen, e.Name)
                        end
                    end

                    local currentUnlockables = CommF:InvokeServer("GetUnlockables")
                    for _, fruitName in pairs(TabelDevilFruitOpen) do
                        for _, storedName in pairs(TabelDevilFruitStore) do
                            if fruitName == storedName and currentUnlockables.FlamingoAccess == nil then
                                if not player.Backpack:FindFirstChild(storedName) then
                                    CommF:InvokeServer("F_", "LoadFruit", storedName)
                                else
                                    CommF:InvokeServer("F_", "TalkTrevor", "1")
                                    CommF:InvokeServer("F_", "TalkTrevor", "2")
                                    CommF:InvokeServer("F_", "TalkTrevor", "3")
                                end
                            end
                        end
                    end
                    CommF:InvokeServer("F_", "TalkTrevor", "1")
                    CommF:InvokeServer("F_", "TalkTrevor", "2")
                    CommF:InvokeServer("F_", "TalkTrevor", "3")
                end

            -- ── STAGE 0: Bắt đầu — Kill Swan Pirates (50 mobs) ─────────
            elseif bartiloProgress == 0 then
                local questUI     = player.PlayerGui:FindFirstChild("Main")
                local questPanel  = questUI and questUI:FindFirstChild("Quest")
                local questVis    = questPanel and questPanel.Visible
                local questTitle  = ""
                if questVis then
                    pcall(function()
                        questTitle = questPanel.Container.QuestTitle.Title.Text
                    end)
                end

                if string.find(questTitle, "Swan Pirates") and string.find(questTitle, "50") and questVis then
                    local swanPirate = GetNearestEnemy("Swan Pirate")
                    if swanPirate and swanPirate:FindFirstChild("Humanoid") and swanPirate.Humanoid.Health > 0 then
                        getgenv().CurrentTargetMob = swanPirate
                        local targetCF = GetFarmCFrame(swanPirate)
                        if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                        AttackEnemy(swanPirate)
                    else
                        getgenv().CurrentTargetMob = nil
                        TweenToPos(CFrame.new(1057.92761, 137.614319, 1242.08069), getgenv().FlySpeed)
                    end
                else
                    -- Bay đến NPC Bartilo để nhận quest
                    getgenv().CurrentTargetMob = nil
                    TweenToPos(CFrame.new(-456.28952, 73.0200958, 299.895966), getgenv().FlySpeed)
                end

            -- ── STAGE 1: Kill Jeremy ─────────────────────────────────────
            elseif bartiloProgress == 1 then
                local jeremy = GetNearestEnemy("Jeremy")
                if jeremy and jeremy:FindFirstChild("Humanoid") and jeremy.Humanoid.Health > 0 then
                    getgenv().CurrentTargetMob = jeremy
                    local targetCF = GetFarmCFrame(jeremy)
                    if targetCF then TweenToPos(targetCF, getgenv().FlySpeed) end
                    AttackEnemy(jeremy)
                else
                    getgenv().CurrentTargetMob = nil
                    TweenToPos(CFrame.new(2099.88159, 448.931, 648.997375), getgenv().FlySpeed)
                end

            -- ── STAGE 2: Điều hướng qua mê cung Bartilo ─────────────────
            elseif bartiloProgress == 2 then
                getgenv().CurrentTargetMob = nil
                -- Bay đến điểm xuất phát của mê cung
                TweenToPos(CFrame.new(-1836, 11, 1714), getgenv().FlySpeed)
                task.wait(0.3)
                -- Duyệt tuần tự qua các checkpoint bằng direct CFrame
                local checkpoints = {
                    CFrame.new(-1850.49329, 13.1789551, 1750.89685),
                    CFrame.new(-1858.87305, 19.3777466, 1712.01807),
                    CFrame.new(-1803.94324, 16.5789185, 1750.89685),
                    CFrame.new(-1858.55835, 16.8604317, 1724.79541),
                    CFrame.new(-1869.54224, 15.987854,  1681.00659),
                    CFrame.new(-1800.0979,  16.4978027, 1684.52368),
                    CFrame.new(-1819.26343, 14.795166,  1717.90625),
                    CFrame.new(-1813.51843, 14.8604736, 1724.79541),
                }
                for _, cp in ipairs(checkpoints) do
                    if not getgenv().AutoZou then break end
                    local r = getRoot()
                    if r then r.CFrame = cp end
                    task.wait(0.12)
                end
            end
        end)
    end
end)

--------------------------------------------------------------------
-- TAB STATS: NÂNG CẤP CHỈ SỐ TỰ ĐỘNG
--------------------------------------------------------------------
Tabs.Stats:AddSection("Stats Upgrade")

local StatusSelect = Tabs.Stats:CreateSlider("StatusSelect", {
    Title = "Stats Value",
    Description = "Chọn số điểm cộng mỗi lần (1-1000)",
    Default = 10,
    Min = 0,
    Max = 1000,
    Rounding = 1,
    Callback = function(Value)
        getgenv().pSats = Value
        print("📊 Đã đặt giá trị cộng điểm: " .. Value)
    end
})

StatusSelect:OnChanged(function(Value)
    getgenv().pSats = Value
end)

local StatsUpgMelee = Tabs.Stats:CreateToggle("StatsUpgMelee", {
    Title = "Auto Melee",
    Description = "Tự động cộng điểm vào kỹ năng Melee (Đấm đá)",
    Default = false
})

StatsUpgMelee:OnChanged(function(Value)
    getgenv().Auto_Melee = Value
end)

spawn(function()
    while wait(Sec) do
        pcall(function()
            if getgenv().Auto_Melee then
                statsSetings("Melee", getgenv().pSats)
            end
        end)
    end
end)

local StatsUpgSword = Tabs.Stats:CreateToggle("StatsUpgSword", {
    Title = "Auto Sword",
    Description = "Tự động cộng điểm vào kỹ năng Sword (Kiếm)",
    Default = false
})

StatsUpgSword:OnChanged(function(Value)
    getgenv().Auto_Sword = Value
end)

spawn(function()
    while wait(Sec) do
        pcall(function()
            if getgenv().Auto_Sword then
                statsSetings("Sword", getgenv().pSats)
            end
        end)
    end
end)

local StatsUpgGun = Tabs.Stats:CreateToggle("StatsUpgGun", {
    Title = "Auto Gun",
    Description = "Tự động cộng điểm vào kỹ năng Gun (Súng)",
    Default = false
})

StatsUpgGun:OnChanged(function(Value)
    getgenv().Auto_Gun = Value
end)

spawn(function()
    while wait(Sec) do
        pcall(function()
            if getgenv().Auto_Gun then
                statsSetings("Gun", getgenv().pSats)
            end
        end)
    end
end)

local StatsUpgDevil = Tabs.Stats:CreateToggle("StatsUpgDevil", {
    Title = "Auto Blox Fruit",
    Description = "Tự động cộng điểm vào kỹ năng Devil Fruit (Trái ác quỷ)",
    Default = false
})

StatsUpgDevil:OnChanged(function(Value)
    getgenv().Auto_DevilFruit = Value
end)

spawn(function()
    while wait(Sec) do
        pcall(function()
            if getgenv().Auto_DevilFruit then
                statsSetings("Devil", getgenv().pSats)
            end
        end)
    end
end)

local StatsUpgDefense = Tabs.Stats:CreateToggle("StatsUpgDefense", {
    Title = "Auto Defense",
    Description = "Tự động cộng điểm vào kỹ năng Defense (Phòng thủ)",
    Default = false
})

StatsUpgDefense:OnChanged(function(Value)
    getgenv().Auto_Defense = Value
end)

spawn(function()
    while wait(Sec) do
        pcall(function()
            if getgenv().Auto_Defense then
                statsSetings("Defense", getgenv().pSats)
            end
        end)
    end
end)

--------------------------------------------------------------------
-- HÀM HỖ TRỢ: LẤY THÔNG TIN QUEST DỰA TRÊN LEVEL (VỚI HỦY QUEST TỰ ĐỘNG)
--------------------------------------------------------------------
local function GetQuestDataWithAbandonCheck()
    local myLevel = player.Data.Level.Value or 1
    local questData = nil
    
    if World1 then
        if myLevel >= 1 and myLevel <= 9 then
            questData = {1, 9, "Starter Island", "BanditQuest1", "Bandit", CFrame.new(1059.37, 16.55, 1550.4)}
        elseif myLevel >= 10 and myLevel <= 14 then
            questData = {10, 14, "Jungle", "JungleQuest", "Monkey", CFrame.new(-1611.7, 36.85, 148.2)}
        end
    elseif World2 then
        if myLevel >= 700 and myLevel <= 724 then
            questData = {700, 724, "Area1", "Area1Quest", "Raider", CFrame.new(-428.75, 71.7, 1836.18)}
        end
    elseif World3 then
        if myLevel >= 1500 and myLevel <= 1524 then
            questData = {1500, 1524, "Amazon", "AmazonQuest", "Amazon", CFrame.new(5497.06, 845.55, 752.25)}
        end
    end
    
    if questData then
        if CheckLevelForQuest(questData) then
            print("🔄 Level đã cao hơn quest, cần cập nhật quest mới")
        end
        CheckAndAbandonWrongQuest(questData)
    end
    
    return questData
end

--------------------------------------------------------------------
-- STUB TABS (Coming Soon)
--------------------------------------------------------------------
Tabs.FarmOther:AddSection("Farming Other")
Tabs.FarmOther:CreateParagraph("ComingSoon", {Title = "Coming Soon", Content = "Tinh nang dang phat trien."})

--------------------------------------------------------------------
-- TAB FRUIT & RAID, DUNGEON
--------------------------------------------------------------------
Tabs.FruitRaid:AddSection("Dungeon Farm")

Tabs.FruitRaid:CreateToggle("DungeonFarm", {
    Title = "Auto Dungeon Farm",
    Description = "Tu dong farm trong Dungeon (chi hoat dong trong Dungeon PlaceId)",
    Default = false,
    Callback = function(v)
        getgenv().FarmDungeon = v
        getgenv().Noclip = v
        getgenv().AutoBusoLoop = v

        if v then
            if game.PlaceId ~= DungeonPlaceId then
                Library:Notify({
                    Title = "Sai PlaceId",
                    Content = "Dungeon farm chi hoat dong trong Dungeon!",
                    Duration = 5
                })
                getgenv().FarmDungeon = false
                getgenv().Noclip = false
                getgenv().AutoBusoLoop = false
                return
            end
            getgenv().IsFarming = true
            startFly()
            startDungeonFarm()
            print("Bat Dungeon Farm")
        else
            stopDungeonFarm()
            -- Chi tat IsFarming neu khong co farm nao khac dang chay
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
                or getgenv().FarmAura or getgenv().FarmTyrant or getgenv().FarmEliteHunt
                or getgenv().AutoMaterial
            if not anyFarmActive then
                getgenv().IsFarming = false
                getgenv().Noclip = false
                getgenv().AutoBusoLoop = false
                stopFly()
            end
            print("Tat Dungeon Farm")
        end
    end
})

--------------------------------------------------------------------
-- GET BEST PAD FUNCTION - Tìm pad tốt nhất với số player phù hợp
--------------------------------------------------------------------
function GetBestPad()
    local bestPad = nil
    local maxPlayers = -1
    for i = 1, 3 do
        local pad = workspace.Map["Simulation Hub"].Pads:FindFirstChild("DUNGEON_TELEPORTER" .. i)
        if pad then
            local playersOnPad = pad:GetAttribute("NumPlayersOnPad") or 0
            if playersOnPad < 4 and playersOnPad > maxPlayers then
                maxPlayers = playersOnPad
                bestPad = pad
            end
        end
    end
    return bestPad
end

--------------------------------------------------------------------
-- DUNGEON PAD SETTINGS - Dropdown MaxPlayer + Button Join Pad
--------------------------------------------------------------------
Tabs.FruitRaid:AddSection("Dungeon Pad Settings")


Tabs.FruitRaid:CreateDropdown("MaxPlayerSelect", {
    Title = "Select Max Players",
    Description = "Chọn số lượng player tối thiểu trên pad",
    Values = {"1", "2", "3"},
    Default = "1",
    Callback = GuardDropdown(function(value)
        _G.SelectedMaxPlayers = tonumber(value)
        print("📊 Selected max players: " .. value)
    end),
})

Tabs.FruitRaid:CreateButton({
    Title = "Join Best Pad",
    Description = "Fly tới pad có số player >= số đã chọn",
    Callback = function()
        if game.PlaceId ~= DungeonPlaceId then
            Library:Notify({
                Title = "Wrong PlaceId",
                Content = "Chỉ có thể join pad trong Dungeon!",
                Duration = 3
            })
            return
        end

        local bestPad = GetBestPad()
        if not bestPad then
            Library:Notify({
                Title = "No Pad Found",
                Content = "Không tìm thấy pad phù hợp!",
                Duration = 3
            })
            return
        end

        local numPlayers = bestPad:GetAttribute("NumPlayersOnPad") or 0
        if numPlayers < (_G.SelectedMaxPlayers or 1) then
            Library:Notify({
                Title = "Not Enough Players",
                Content = "Pad chỉ có " .. numPlayers .. " players, cần " .. (_G.SelectedMaxPlayers or 1),
                Duration = 3
            })
            return
        end

        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local targetCF = bestPad.Pad.CFrame * CFrame.new(0, 5, 0)
        local dist = (hrp.Position - targetCF.Position).Magnitude
        local speed = getgenv().FlySpeed or 200

        -- Fly trực tiếp không phụ thuộc FarmDungeon/shouldTween
        local tween = TweenService:Create(hrp,
            TweenInfo.new(dist / speed, Enum.EasingStyle.Linear),
            {CFrame = targetCF}
        )
        tween:Play()

        Library:Notify({
            Title = "Success",
            Content = "Flying to pad with " .. numPlayers .. " players!",
            Duration = 2
        })
    end
})

--------------------------------------------------------------------
-- FRUIT SECTION
--------------------------------------------------------------------
Tabs.FruitRaid:AddSection("Fruit")

-- Helper: drop tất cả devil fruit trong backpack
local function DropFruits()
    for _, v in pairs(player.Backpack:GetChildren()) do
        if v:IsA("Tool") and v.ToolTip == "Blox Fruit" then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("DropFruit", v.Name)
            end)
        end
    end
end

-- Helper: store tất cả devil fruit trong backpack vào kho
local function UpdStFruit()
    for _, x in next, player.Backpack:GetChildren() do
        local StoreFruit = x:FindFirstChild("EatRemote", true)
        if StoreFruit then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer(
                    "StoreFruit",
                    StoreFruit.Parent:GetAttribute("OriginalName"),
                    player.Backpack:FindFirstChild(x.Name)
                )
            end)
        end
    end
end

-- Flag
_G.Random_Auto = false
_G.DropFruit   = false
_G.StoreF      = false
_G.TwFruits    = false

Tabs.FruitRaid:CreateToggle("RandomFF", {
    Title = "Auto Random Fruit",
    Description = "Tự động mua random devil fruit",
    Default = false,
    Callback = function(v) _G.Random_Auto = v end
})
spawn(function()
    while wait(Sec) do
        pcall(function()
            if _G.Random_Auto then
                ReplicatedStorage.Remotes.CommF_:InvokeServer("Cousin", "Buy")
            end
        end)
    end
end)

Tabs.FruitRaid:CreateToggle("DropF", {
    Title = "Auto Drop Fruit",
    Description = "Tự động drop devil fruit",
    Default = false,
    Callback = function(v) _G.DropFruit = v end
})
spawn(function()
    while wait(Sec) do
        if _G.DropFruit then
            pcall(function() DropFruits() end)
        end
    end
end)

Tabs.FruitRaid:CreateToggle("StoredF", {
    Title = "Auto Store Fruit",
    Description = "Tự động lưu devil fruit vào kho",
    Default = false,
    Callback = function(v) _G.StoreF = v end
})
spawn(function()
    while wait(Sec) do
        if _G.StoreF then
            pcall(function() UpdStFruit() end)
        end
    end
end)

-- ── AUTO TWEEN TO FRUIT (Elite-style) ──────────────────────────
-- Watcher liên tục poll workspace để phát hiện fruit rơi.
-- Khi có fruit → tạm dừng normal farm, bật fly, tween đến nhặt.
-- Khi fruit biến mất (đã nhặt) → resume normal farm như trước.
--------------------------------------------------------------------
_G.TwFruits               = false
getgenv().FruitPickActive = false  -- Đang trong phiên đi nhặt fruit

local fruitPickConn  = nil  -- Heartbeat của phiên nhặt fruit
local fruitWatchConn = nil  -- Heartbeat watcher poll liên tục

-- Tìm handle của fruit gần nhất trên map
local function FindNearestFruit()
    local root = getRoot()
    if not root then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if string.find(obj.Name, "Fruit") then
            local handle = obj:FindFirstChild("Handle")
            if handle then
                local dist = (handle.Position - root.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = handle
                end
            end
        end
    end
    return best
end

-- Tạm dừng normal farm để nhặt fruit (không tắt flag farm)
local function PauseFarmForFruit()
    if getgenv().FruitPickActive then return end
    getgenv().FruitPickActive = true
    stopLevelFarm(); stopBoneFarm(); stopKataFarm()
    stopAuraFarm(); stopTyrantFarm(); stopPhaBinhFarm()
    print("⏸ Farm tạm dừng để nhặt Fruit")
end

-- Resume lại đúng loại farm sau khi nhặt xong
local function ResumeFarmAfterFruit()
    if not getgenv().FruitPickActive then return end
    getgenv().FruitPickActive = false
    if getgenv().FarmLevel and SelectedFarm == "Farm cấp" then
        startLevelFarm()
    elseif getgenv().FarmBone and SelectedFarm == "Farm bone" then
        startBoneFarm()
    elseif getgenv().FarmKata and SelectedFarm == "Farm kata" then
        startKataFarm()
    elseif getgenv().FarmAura and SelectedFarm == "Farm aura" then
        startAuraFarm()
    elseif getgenv().FarmTyrant and SelectedFarm == "Tyrant of the Skie" then
        startTyrantFarm()
    end
    print("▶ Farm tiếp tục sau khi nhặt Fruit xong")
end

-- Bắt đầu phiên nhặt: dùng fly để tween liên tục đến fruit cho đến khi biến mất
local function startFruitPick(targetHandle)
    if fruitPickConn then fruitPickConn:Disconnect() end

    fruitPickConn = RunService.Heartbeat:Connect(function()
        if not _G.TwFruits then return end

        -- Fruit đã biến mất → kết thúc phiên nhặt
        if not targetHandle or not targetHandle.Parent then
            fruitPickConn:Disconnect(); fruitPickConn = nil
            getgenv().CurrentTargetMob = nil

            local anyNormalFarm = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon
            if not anyNormalFarm then
                getgenv().IsFarming = false
                getgenv().Noclip = false
                stopFly()
            else
                ResumeFarmAfterFruit()
            end
            print("✅ Đã nhặt Fruit — tiếp tục bình thường")
            return
        end

        local root = getRoot()
        if not root then return end

        -- Dùng TweenToPos (lõi fly farm) để bay đến Handle của fruit
        TweenToPos(CFrame.new(targetHandle.Position), getgenv().FlySpeed)
    end)
end

-- Watcher: poll liên tục, khi phát hiện fruit thì kích hoạt nhặt
local function startFruitWatcher()
    if fruitWatchConn then fruitWatchConn:Disconnect() end

    fruitWatchConn = RunService.Heartbeat:Connect(function()
        if not _G.TwFruits then return end
        if getgenv().FruitPickActive then return end  -- Đang nhặt rồi, không check lại

        pcall(function()
            local handle = FindNearestFruit()
            if handle then
                print("🍎 Phát hiện Fruit! Tạm dừng farm và đi nhặt...")

                -- Pause normal farm nếu đang chạy
                local anyNormalFarm = getgenv().FarmLevel or getgenv().FarmBone
                    or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                if anyNormalFarm then
                    PauseFarmForFruit()
                else
                    getgenv().FruitPickActive = true
                end

                -- Đảm bảo fly bật
                if not getgenv().IsFarming then
                    getgenv().IsFarming = true
                    getgenv().Noclip = true
                    startFly()
                end

                startFruitPick(handle)
            end
        end)
    end)
end

local function stopFruitWatcher()
    if fruitPickConn  then fruitPickConn:Disconnect();  fruitPickConn  = nil end
    if fruitWatchConn then fruitWatchConn:Disconnect(); fruitWatchConn = nil end
    ResumeFarmAfterFruit()
    getgenv().CurrentTargetMob = nil
end

Tabs.FruitRaid:CreateToggle("TwF", {
    Title = "Auto Tween to Fruit",
    Description = "Khi có fruit rơi trên map: tạm dừng farm, dùng fly tween đến nhặt, sau đó tiếp tục farm tự động.",
    Default = false,
    Callback = function(v)
        _G.TwFruits = v
        if v then
            print("✅ Bật Auto Tween to Fruit — đang chờ Fruit xuất hiện...")
            startFruitWatcher()
        else
            stopFruitWatcher()
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon
                or getgenv().AutoRaid or getgenv().RaidOnly
            if not anyFarmActive then
                getgenv().IsFarming = false
                getgenv().Noclip = false
                stopFly()
            end
        end
    end
})

--------------------------------------------------------------------
-- RAID SECTION (DUNGEON EVENT / RAIDING)
--------------------------------------------------------------------

-- Hàm kiểm tra có chip / item không (backpack + character)
local function GetBP(itemName)
    for _, v in pairs(player.Backpack:GetChildren()) do
        if v.Name == itemName then return true end
    end
    for _, v in pairs(player.Character and player.Character:GetChildren() or {}) do
        if v.Name == itemName then return true end
    end
    return false
end

-- Hàm teleport trực tiếp
local function _tp(cf)
    local root = getRoot()
    if root then root.CFrame = cf end
end

-- Hàm kiểm tra mob có phải raid mob / boss / không di chuyển không
local function IsRaidMob(mob)
    local n = mob.Name:lower()
    if n:find("raid") or n:find("microchip") or n:find("island") then return true end
    if mob:GetAttribute("IsRaid") or mob:GetAttribute("RaidMob") or mob:GetAttribute("IsBoss") then return true end
    local hum = mob:FindFirstChild("Humanoid")
    if hum and hum.WalkSpeed == 0 then return true end
    if mob.Parent and tostring(mob.Parent):lower():find("_worldorigin") then return true end
    return false
end

-- Hàm kiểm tra đang trong raid
local function IsInRaid()
    local ok, result = pcall(function()
        return player.PlayerGui.Main.TopHUDList.RaidTimer.Visible
    end)
    return ok and result == true
end

-- Hàm lấy đảo raid theo thứ tự 5→1 (chỉ đảo chưa có mob hoặc đang đứng gần)
local function IsIslandRaid(cu)
    local ok, locs = pcall(function() return workspace["_WorldOrigin"].Locations end)
    if not ok or not locs then return nil end
    local best, bestDist = nil, math.huge
    for _, v in ipairs(locs:GetChildren()) do
        if v.Name == "Island " .. cu then
            local root = getRoot()
            if root then
                local dist = (v.Position - root.Position).Magnitude
                if dist < bestDist then bestDist = dist; best = v end
            end
        end
    end
    if best and bestDist <= 4500 then return best end
    return nil
end

local function getNextRaidIsland()
    for _, id in ipairs({5, 4, 3, 2, 1}) do
        local island = IsIslandRaid(id)
        if island then return island end
    end
    return nil
end

-- Flags
getgenv().AutoRaid      = false
getgenv().RaidOnly      = false   -- Toggle "Raid": chỉ farm bên trong raid, không mua chip / start raid
getgenv().SelectChip    = "Ice"
getgenv().RaidKillAura  = true    -- Dùng Kill Aura ở đảo 4+5 (mặc định bật)

-- ===== UI =====
Tabs.FruitRaid:AddSection("Dungeon Event / Raiding")

-- Dropdown chọn loại chip
Tabs.FruitRaid:CreateDropdown("RaidChipSelect", {
    Title = "Select Chip",
    Description = "Loại chip dùng để start raid",
    Values = {
        "Flame", "Ice", "Quake", "Light", "Dark",
        "String", "Rumble", "Magma", "Human: Buddha",
        "Sand", "Bird: Phoenix", "Dough"
    },
    Default = 1,
    Callback = GuardDropdown(function(v)
        getgenv().SelectChip = v
    end),
})

-- Toggle duy nhất: toàn bộ quy trình Raid
local raidFarmConn = nil

Tabs.FruitRaid:CreateToggle("AutoRaid", {
    Title = "Auto Raid",
    Description = "Mua chip → Start Raid → Farm mob (2000 stud) → Qua đảo → Lặp lại",
    Default = false,
    Callback = function(v)
        getgenv().AutoRaid = v

        if not v then
            -- Tắt hoàn toàn
            if raidFarmConn then raidFarmConn:Disconnect(); raidFarmConn = nil end
            getgenv().CurrentTargetMob = nil
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon
            if not anyFarmActive then
                getgenv().IsFarming = false
                getgenv().AutoBusoLoop = false
                getgenv().Noclip = false
                stopFly()
            end
            return
        end

        -- Bật fly + haki + flags chung
        getgenv().IsFarming  = true
        getgenv().Noclip     = true
        getgenv().AutoBusoLoop = true
        startFly()

        -- Luồng chính chạy trong coroutine để không block Heartbeat
        task.spawn(function()
            while getgenv().AutoRaid do
                pcall(function()

                    -- ── BƯỚC 1: Mua chip nếu chưa có ──────────────────────
                    if not IsInRaid() and not GetBP("Special Microchip") then

                        -- Thử mua bằng Beli trước
                        local boughtBeli = false
                        pcall(function()
                            ReplicatedStorage.Remotes.CommF_:InvokeServer(
                                "RaidsNpc", "Select", getgenv().SelectChip or "Ice")
                            boughtBeli = true
                        end)

                        -- Nếu mua bằng Beli không được → thử dùng fruit
                        if not boughtBeli or not GetBP("Special Microchip") then
                            pcall(function()
                                local fruits = ReplicatedStorage.Remotes.CommF_:InvokeServer("GetFruits")
                                for _, data in pairs(fruits or {}) do
                                    if GetBP("Special Microchip") then break end
                                    local rarity = tostring(data.Rarity or ""):lower()
                                    if (data.Price or 0) <= 1150000
                                    or rarity == "common" or rarity == "uncommon" or rarity == "rare" then
                                        ReplicatedStorage.Remotes.CommF_:InvokeServer("LoadFruit", data.Name)
                                        ReplicatedStorage.Remotes.CommF_:InvokeServer(
                                            "RaidsNpc", "Select", getgenv().SelectChip or "Ice")
                                    end
                                end
                            end)
                        end

                        task.wait(0.5) -- Delay sau khi mua chip
                    end

                    -- ── BƯỚC 2: Start Raid nếu chưa vào ──────────────────
                    if not IsInRaid() and GetBP("Special Microchip") then
                        if World2 then
                            _tp(CFrame.new(-6438.73535, 250.645355, -4501.50684))
                            task.wait(0.3)
                            pcall(function()
                                fireclickdetector(workspace.Map.CircleIsland.RaidSummon2.Button.Main.ClickDetector)
                            end)
                        elseif World3 then
                            pcall(function()
                                ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance",
                                    Vector3.new(-5097.93164, 316.447021, -3142.66602,
                                        -0.405007899, -4.31682743e-08, 0.914313197,
                                        -1.90943332e-08, 1, 3.8755779e-08,
                                        -0.914313197, -1.76180437e-09, -0.405007899))
                            end)
                            task.wait(0.3)
                            pcall(function()
                                fireclickdetector(workspace.Map["Boat Castle"].RaidSummon2.Button.Main.ClickDetector)
                            end)
                        end

                        -- Đợi server teleport vào raid (tối đa 30s)
                        local deadline = tick() + 30
                        repeat task.wait(0.5) until IsInRaid() or tick() > deadline or not getgenv().AutoRaid
                        if not getgenv().AutoRaid then return end

                        task.wait(1) -- Buffer cho map raid load
                    end

                    -- ── BƯỚC 3: Bật Heartbeat farm nếu đang trong raid ───
                    if IsInRaid() then
                        if raidFarmConn then raidFarmConn:Disconnect(); raidFarmConn = nil end

                        raidFarmConn = RunService.Heartbeat:Connect(function()
                            if not getgenv().AutoRaid then return end

                            -- Khi raid kết thúc → dừng Heartbeat, vòng while sẽ lo bước tiếp
                            if not IsInRaid() then
                                if raidFarmConn then raidFarmConn:Disconnect(); raidFarmConn = nil end
                                getgenv().CurrentTargetMob = nil
                                return
                            end

                            local root = getRoot()
                            if not root then return end

                            -- ── KILL AURA (chỉ đảo 4 & 5, chỉ khi bật): kill mob trong 2000 stud ──
                            -- Farm bình thường vẫn chạy bên dưới song song để không miss mob
                            local onHighIsland = IsIslandRaid(4) or IsIslandRaid(5)
                            if onHighIsland and getgenv().RaidKillAura then
                                for _, enemy in pairs(workspace.Enemies:GetChildren()) do
                                    if enemy:FindFirstChild("Humanoid")
                                    and enemy:FindFirstChild("HumanoidRootPart")
                                    and enemy.Humanoid.Health > 0
                                    and not IsRaidMob(enemy) then
                                        local dist = (enemy.HumanoidRootPart.Position - root.Position).Magnitude
                                        if dist <= 2000 then
                                            pcall(function()
                                                sethiddenproperty(player, "SimulationRadius", math.huge)
                                                enemy.Humanoid.Health = 0
                                                enemy:BreakJoints()
                                                enemy.HumanoidRootPart.CanCollide = false
                                            end)
                                        end
                                    end
                                end
                            end

                            -- ── FARM THƯỜNG (mọi đảo, mọi lúc): tween đến mob gần nhất + attack ──
                            -- Đảm bảo farm tiếp tục kể cả khi kill aura hụt
                            local nearest, nearestDist = nil, math.huge
                            for _, mob in pairs(workspace.Enemies:GetChildren()) do
                                if mob:FindFirstChild("Humanoid")
                                and mob:FindFirstChild("HumanoidRootPart")
                                and mob.Humanoid.Health > 0
                                and not IsRaidMob(mob) then
                                    local dist = (mob.HumanoidRootPart.Position - root.Position).Magnitude
                                    if dist <= 2000 and dist < nearestDist then
                                        nearestDist = dist
                                        nearest = mob
                                    end
                                end
                            end

                            getgenv().CurrentTargetMob = nearest

                            if nearest then
                                local targetCF = GetFarmCFrame(nearest)
                                if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                                AttackEnemy(nearest)
                            else
                                -- Không có mob trong 2000 stud → di chuyển đến đảo tiếp theo
                                local nextIsland = getNextRaidIsland()
                                if nextIsland then
                                    TweenObject(root, nextIsland.CFrame * CFrame.new(0, 50, 0), getgenv().FlySpeed)
                                end
                            end
                        end)

                        -- Chờ raid kết thúc
                        repeat task.wait(1) until not IsInRaid() or not getgenv().AutoRaid
                        if raidFarmConn then raidFarmConn:Disconnect(); raidFarmConn = nil end
                        getgenv().CurrentTargetMob = nil
                    end

                end) -- end pcall
                task.wait(1)
            end -- end while
        end) -- end task.spawn
    end
})

-- ===== TOGGLE: RAID (chỉ farm bên trong raid, không mua chip / không start raid) =====
local raidOnlyConn = nil

Tabs.FruitRaid:CreateToggle("RaidOnly", {
    Title = "Raid",
    Description = "Chỉ auto farm bên trong raid (không mua chip, không start raid). Phải vào raid thủ công trước.",
    Default = false,
    Callback = function(v)
        getgenv().RaidOnly = v

        if not v then
            -- Tắt hoàn toàn
            if raidOnlyConn then raidOnlyConn:Disconnect(); raidOnlyConn = nil end
            getgenv().CurrentTargetMob = nil
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon or getgenv().AutoRaid
            if not anyFarmActive then
                getgenv().IsFarming = false
                getgenv().AutoBusoLoop = false
                getgenv().Noclip = false
                stopFly()
            end
            return
        end

        -- Bật fly + haki + flags chung
        getgenv().IsFarming    = true
        getgenv().Noclip       = true
        getgenv().AutoBusoLoop = true
        startFly()

        -- Luồng chính: chờ cho đến khi vào raid rồi bắt đầu farm
        task.spawn(function()
            while getgenv().RaidOnly do
                pcall(function()

                    -- ── Chờ cho đến khi player đang trong raid ──────────
                    if not IsInRaid() then
                        task.wait(1)
                        return
                    end

                    -- ── Bật Heartbeat farm khi đang trong raid ───────────
                    if raidOnlyConn then raidOnlyConn:Disconnect(); raidOnlyConn = nil end

                    raidOnlyConn = RunService.Heartbeat:Connect(function()
                        if not getgenv().RaidOnly then return end

                        -- Raid kết thúc → dừng Heartbeat
                        if not IsInRaid() then
                            if raidOnlyConn then raidOnlyConn:Disconnect(); raidOnlyConn = nil end
                            getgenv().CurrentTargetMob = nil
                            return
                        end

                        local root = getRoot()
                        if not root then return end

                        -- ── KILL AURA (chỉ đảo 4 & 5, chỉ khi bật): kill mob trong 2000 stud ──
                        -- Farm bình thường vẫn chạy bên dưới song song để không miss mob
                        local onHighIsland = IsIslandRaid(4) or IsIslandRaid(5)
                        if onHighIsland and getgenv().RaidKillAura then
                            for _, enemy in pairs(workspace.Enemies:GetChildren()) do
                                if enemy:FindFirstChild("Humanoid")
                                and enemy:FindFirstChild("HumanoidRootPart")
                                and enemy.Humanoid.Health > 0
                                and not IsRaidMob(enemy) then
                                    local dist = (enemy.HumanoidRootPart.Position - root.Position).Magnitude
                                    if dist <= 2000 then
                                        pcall(function()
                                            sethiddenproperty(player, "SimulationRadius", math.huge)
                                            enemy.Humanoid.Health = 0
                                            enemy:BreakJoints()
                                            enemy.HumanoidRootPart.CanCollide = false
                                        end)
                                    end
                                end
                            end
                        end

                        -- ── FARM THƯỜNG (mọi đảo, mọi lúc): tween đến mob gần nhất + attack ──
                        -- Đảm bảo farm tiếp tục kể cả khi kill aura hụt
                        local nearest, nearestDist = nil, math.huge
                        for _, mob in pairs(workspace.Enemies:GetChildren()) do
                            if mob:FindFirstChild("Humanoid")
                            and mob:FindFirstChild("HumanoidRootPart")
                            and mob.Humanoid.Health > 0
                            and not IsRaidMob(mob) then
                                local dist = (mob.HumanoidRootPart.Position - root.Position).Magnitude
                                if dist <= 2000 and dist < nearestDist then
                                    nearestDist = dist
                                    nearest = mob
                                end
                            end
                        end

                        getgenv().CurrentTargetMob = nearest

                        if nearest then
                            local targetCF = GetFarmCFrame(nearest)
                            if targetCF then TweenObject(root, targetCF, getgenv().FlySpeed) end
                            AttackEnemy(nearest)
                        else
                            -- Không có mob trong 2000 stud → di chuyển đến đảo tiếp theo
                            local nextIsland = getNextRaidIsland()
                            if nextIsland then
                                TweenObject(root, nextIsland.CFrame * CFrame.new(0, 50, 0), getgenv().FlySpeed)
                            end
                        end
                    end)

                    -- Chờ raid kết thúc
                    repeat task.wait(1) until not IsInRaid() or not getgenv().RaidOnly
                    if raidOnlyConn then raidOnlyConn:Disconnect(); raidOnlyConn = nil end
                    getgenv().CurrentTargetMob = nil

                end) -- end pcall
                task.wait(1)
            end -- end while
        end) -- end task.spawn
    end
})

Tabs.FruitRaid:CreateToggle("RaidKillAura", {
    Title = "Use Kill Aura on Raid",
    Description = "Bật: đảo 4+5 dùng Kill Aura (2000 stud) + farm bình thường song song. Tắt: farm bình thường tất cả các đảo.",
    Default = true,
    Callback = function(v)
        getgenv().RaidKillAura = v
    end
})

--------------------------------------------------------------------
-- TAB TRAVEL
--------------------------------------------------------------------

-- ===== DỮ LIỆU ĐẢO THEO WORLD =====
local IslandData = {
    world1 = {
        { name = "Marine Start",          pos = Vector3.new(-2573.34, 15.89,  2047.00) },
        { name = "Start Island",          pos = Vector3.new( 1071.28, 25.31,  1426.87) },
        { name = "Middle Town",           pos = Vector3.new( -655.82, 15.89,  1436.68) },
        { name = "Jungle",                pos = Vector3.new(-1249.77, 20.89,   341.36) },
        { name = "Pirate Village",        pos = Vector3.new(-1122.35, 10.79,  3855.92) },
        { name = "Desert",                pos = Vector3.new( 1094.15, 15.47,  4192.89) },
        { name = "Frozen Village",        pos = Vector3.new( 1198.01, 35.01, -1211.73) },
        { name = "MarineFord",            pos = Vector3.new(-4505.38, 30.69,  4260.56) },
        { name = "Fountain City",         pos = Vector3.new( 5132.71, 10.54,  4037.86) },
        { name = "Colosseum",             pos = Vector3.new(-1428.35, 15.39, -3014.37) },
        { name = "Sky 1",                 pos = Vector3.new(-4970.22, 717.71,-2622.35) },
        { name = "Sky 2",                 pos = Vector3.new(-4607.82, 872.58,-1667.56) },
        { name = "Sky 3",                 pos = Vector3.new(-7894.62,5545.49,  -380.25) },
        { name = "Magma Village",         pos = Vector3.new(-5231.76, 15.62,  8467.88) },
        { name = "Shanks Room",           pos = Vector3.new(-1442.17, 29.88,   -28.35) },
        { name = "Prison",                pos = Vector3.new( 4854.16, 15.17,   740.19) },
        { name = "Underwater City",       pos = Vector3.new(61163.85,  5.34,  1819.78) },
        { name = "Whirlpool",             pos = Vector3.new( 3864.69,  5.41, -1926.21) },
    },
    world2 = {
        { name = "Magma Side",            pos = Vector3.new(-5478.39,  30.98, -5246.91) },
        { name = "Ghost Island",          pos = Vector3.new(-5571.84, 200.18,  -795.43) },
        { name = "Hot and Cold",          pos = Vector3.new(-6026.96,  20.75, -5071.96) },
        { name = "First Spot",            pos = Vector3.new(   82.95,  25.07,  2834.99) },
        { name = "Snow Mountain",         pos = Vector3.new( 1384.68, 470.57, -4990.10) },
        { name = "Green Bit",             pos = Vector3.new(-2372.15,  80.99, -3166.51) },
        { name = "Cafe",                  pos = Vector3.new( -385.25,  80.05,   297.39) },
        { name = "Forgotten Island",      pos = Vector3.new(-3043.32, 250.88,-10191.58) },
        { name = "Frosted Island",        pos = Vector3.new( 5400.40,  35.22, -6236.99) },
        { name = "Flamingo Mansion",      pos = Vector3.new( -287.53, 306.17,   597.60) },
        { name = "Flamingo Room",         pos = Vector3.new( 2284.01,  15.19,   908.03) },
        { name = "Dark Area",             pos = Vector3.new( 3807.10,  30.00, -3452.20) },
        { name = "Factory",               pos = Vector3.new(  430.43, 230.02,  -432.50) },
        { name = "Raid Low",              pos = Vector3.new(-5530, 224, -5903) },
        { name = "Ghost Ship Gate",       pos = Vector3.new(-6491, 305, -4729) },
        { name = "Ghost Ship",            pos = Vector3.new(  923.21, 135.98, 32852.83) },
        { name = "Raid Fruit",            pos = Vector3.new(-6520.40, 307.79, -4654.34) },
    },
    world3 = {
        { name = "Hydar Island",          pos = Vector3.new(  3567.22,   51.38,  1927.11) },
        { name = "Peanut Island",         pos = Vector3.new( -1943.60,   44.90,-10288.01) },
        { name = "Ice Cream Island",      pos = Vector3.new(  -950.00,   59.00,-10907.00) },
        { name = "House Hydar Island",    pos = Vector3.new(  5661.53, 1013.41,  -334.96) },
        { name = "Tiki",                  pos = Vector3.new(-16813.44,   58.29,   304.87) },
        { name = "Haunted Castle",        pos = Vector3.new( -9387.11,  141.36,  5616.04) },
        { name = "Mansion",               pos = Vector3.new(-12463.81,  374.95, -7550.29) },
        { name = "Port Town",             pos = Vector3.new(  -306.00,   20.65,  5557.35) },
        { name = "Great Tree",            pos = Vector3.new(  2262.59,   28.96, -6462.95) },
        { name = "Room Enma/Yama",        pos = Vector3.new(  5251.19,   23.92,   450.37) },
        { name = "Secret Temple",         pos = Vector3.new(  5692.08,   21.01,   324.07) },
        { name = "CakeLoaf",              pos = Vector3.new( -2106.07,   45.10,-11908.52) },
        { name = "Castle on the Sea",     pos = Vector3.new( -5047.54,  314.55, -3159.34) },
        { name = "North Poles",           pos = Vector3.new(  -986.51,   26.67,-14087.59) },
        { name = "Cacao Island",          pos = Vector3.new(   471.13,   42.35,-12212.00) },
        { name = "Submerged Island",      pos = Vector3.new( 11158, -1913, 9796), special = true },
    },
}

-- Xác định danh sách đảo theo world hiện tại
local currentIslandList = World1 and IslandData.world1
    or World2 and IslandData.world2
    or IslandData.world3

local currentIslandNames = {}
for _, v in ipairs(currentIslandList) do
    table.insert(currentIslandNames, v.Name or v.name)
end

-- Xây dựng map name→data để tra nhanh
local islandMap = {}
for _, v in ipairs(currentIslandList) do
    islandMap[v.Name or v.name] = v
end

-- Xây dựng NPCList từ ReplicatedStorage.NPCs
local NPCList = {}
local NPClist = ""
pcall(function()
    for _, v in pairs(ReplicatedStorage.NPCs:GetChildren()) do
        table.insert(NPCList, v.Name)
    end
    table.sort(NPCList)
end)
if #NPCList == 0 then NPCList = {"(Không có NPC)"} end

-- Flag
getgenv().TravelToIsland = false
getgenv().TPNpc = false
local selectedIslandName = currentIslandNames[1] or ""
local selectedNPC = NPCList[1] or ""

-- ===== UI =====

-- SECTION: TRAVEL WORLDS
Tabs.Travel:AddSection("Travel - Worlds")

Tabs.Travel:CreateButton({
    Title = "Travel East Blue (World 1)",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelMain")
        end)
    end
})

Tabs.Travel:CreateButton({
    Title = "Travel Dressrosa (World 2)",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelDressrosa")
        end)
    end
})

Tabs.Travel:CreateButton({
    Title = "Travel Zou (World 3)",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelZou")
        end)
    end
})

-- SECTION: TRAVEL ISLAND
Tabs.Travel:AddSection("Travel - Island")

Tabs.Travel:CreateDropdown("IslandSelect", {
    Title = "Chọn Đảo",
    Description = "Chọn đảo muốn bay đến",
    Values = currentIslandNames,
    Default = 1,
    Callback = GuardDropdown(function(v)
        selectedIslandName = v
    end),
})

local TravelIslandToggle = Tabs.Travel:CreateToggle("TravelToIsland", {
    Title = "Fly tới Đảo",
    Description = "Bay đến đảo đã chọn bằng lõi fly + tele trung gian",
    Default = false,
    Callback = function(v)
        getgenv().TravelToIsland = v
        if not v then
            -- Tắt fly nếu không có farm nào khác đang chạy
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon or getgenv().AutoRaid
            if not anyFarmActive then
                getgenv().IsFarming = false
                stopFly()
            end
            return
        end

        local data = islandMap[selectedIslandName]
        if not data then return end

        getgenv().IsFarming = true
        startFly()

        task.spawn(function()
            pcall(function()
                -- Xử lý đặc biệt: Submerged Island
                if data.special then
                    local finalPos = data.pos  -- Vector3.new(11158, -1913, 9796)

                    -- Kiểm tra "đã ở gần": khoảng cách 3D đến vị trí farm <= 3000 studs
                    -- (Y âm = đang trong island, hoặc mới teleport vào gần đó)
                    local root = getRoot()
                    local alreadyNear = root and (root.Position - finalPos).Magnitude <= 3000

                    if alreadyNear then
                        -- Đã ở trong Submerged Island → fly thẳng đến vị trí farm
                        local farmCF = CFrame.new(finalPos + Vector3.new(0, 3, 0))
                        TweenToPos(farmCF, getgenv().FlySpeed or 300)

                        local deadline = tick() + 40
                        repeat
                            task.wait(0.3)
                            local r = getRoot()
                            if not r then break end
                            if (r.Position - finalPos).Magnitude <= 100 then break end
                        until tick() > deadline or not getgenv().TravelToIsland
                    else
                        -- Chưa ở gần: đi qua NPC ngoài mặt nước, kích hoạt
                        -- TravelToSubmergedIsland, sau đó fly đến vị trí farm
                        TeleportToSubmerged(finalPos)
                    end

                    getgenv().TravelToIsland = false
                    TravelIslandToggle:SetValue(false)
                    local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                        or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                        or getgenv().AutoMaterial or getgenv().FarmDungeon or getgenv().AutoRaid
                    if not anyFarmActive then
                        getgenv().IsFarming = false
                        stopFly()
                    end
                    return
                end

                local targetCF = CFrame.new(data.pos + Vector3.new(0, 5, 0))
                -- TweenToPos tự xử lý tele trung gian nếu TelePorto bật
                TweenToPos(targetCF, getgenv().FlySpeed or 300)

                -- Đợi đến nơi (tối đa 60s)
                local deadline = tick() + 60
                repeat
                    task.wait(0.3)
                    local root = getRoot()
                    if not root then break end
                    if (root.Position - data.pos).Magnitude <= 100 then break end
                until tick() > deadline or not getgenv().TravelToIsland

                -- Tắt toggle sau khi đến nơi
                getgenv().TravelToIsland = false
                TravelIslandToggle:SetValue(false)
                local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                    or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                    or getgenv().AutoMaterial or getgenv().FarmDungeon or getgenv().AutoRaid
                if not anyFarmActive then
                    getgenv().IsFarming = false
                    stopFly()
                end
            end)
        end)
    end
})

-- SECTION: TRAVEL TO NPC
Tabs.Travel:AddSection("Travel - NPC")

local NPCsPos = Tabs.Travel:CreateDropdown("NPCsPos", {
    Title = "Select NPC",
    Description = "Chọn NPC muốn đến",
    Values = NPCList,
    Default = 1,
    Callback = GuardDropdown(function(v)
        selectedNPC = v
    end),
})
NPCsPos:OnChanged(function(Value)
    selectedNPC = Value
end)

local GoNPCs = Tabs.Travel:CreateToggle("GoNPCs", {
    Title = "Auto Tween to NPC",
    Description = "Tự động tele đến NPC đã chọn",
    Default = false,
    Callback = function(v)
        getgenv().TPNpc = v
        if v then
            getgenv().IsFarming = true
            startFly()
        else
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone
                or getgenv().FarmKata or getgenv().FarmAura or getgenv().FarmTyrant
                or getgenv().AutoMaterial or getgenv().FarmDungeon or getgenv().AutoRaid
            if not anyFarmActive then
                getgenv().IsFarming = false
                stopFly()
            end
        end
    end
})
GoNPCs:OnChanged(function(Value)
    getgenv().TPNpc = Value
end)

spawn(function()
    while wait(Sec) do
        if getgenv().TPNpc then
            pcall(function()
                for _, v in pairs(ReplicatedStorage.NPCs:GetChildren()) do
                    if v.Name == selectedNPC and v:FindFirstChild("HumanoidRootPart") then
                        -- TweenToPos tự xử lý tele trung gian nếu TelePorto bật
                        TweenToPos(v.HumanoidRootPart.CFrame, getgenv().FlySpeed or 300)
                        break
                    end
                end
            end)
        end
    end
end)

Tabs.Shop:AddSection("Shop")

--------------------------------------------------------------------
-- FIGHTING STYLE SHOP (MUA VÕ THUẬT)
--------------------------------------------------------------------
-- Dữ liệu vị trí NPC bán võ theo từng world
-- Format: {world1 = Vector3, world2 = Vector3, world3 = Vector3}
-- nil = không có NPC ở world đó
local FightingStyleData = {
    BlackLeg = {
        world1 = Vector3.new(-984, 17, 3990),
        world2 = Vector3.new(-4753, 37, -4853),
        world3 = Vector3.new(-5050, 374, -3183),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyBlackLeg") end,
    },
    Electro = {
        world1 = Vector3.new(-5383, 17, -2149),
        world2 = Vector3.new(-4960, 39, -4663),
        world3 = Vector3.new(-5000, 317, -3201),
        remote = function() ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyElectro") end,
    },
    FishmanKarate = {
        world1 = Vector3.new(61586, 23, 987),
        world2 = Vector3.new(-4870, 37, -4769),
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

-- Xác định key world hiện tại để tra cứu vị trí NPC
local currentWorldKey = World1 and "world1" or World2 and "world2" or World3 and "world3" or "world1"

-- Ngưỡng khoảng cách (studs) để được phép mua võ sau khi tween đến NPC
local BUY_PROXIMITY = 150

--------------------------------------------------------------------
-- HÀM TWEEN ĐẾN VỊ TRÍ NPC VÕ VÀ MUA
-- Dùng cùng lõi fly của farm: startFly → TweenToPos → mua → stopFly
--------------------------------------------------------------------
--------------------------------------------------------------------
-- FIGHTING STYLE BUY (TOGGLE)
-- _buyStyleActive[styleName] = true khi toggle đang bật
-- Khi tắt → flag = false → coroutine tự thoát vòng chờ
--------------------------------------------------------------------
local _buyStyleActive = {}

local function BuyFightingStyle(styleName, styleData, enabled)
    if not enabled then
        -- Tắt toggle → huỷ
        _buyStyleActive[styleName] = false
        return
    end

    -- Bật toggle → bắt đầu mua
    _buyStyleActive[styleName] = true

    local targetPos = styleData[currentWorldKey]
    if not targetPos then
        Library:Notify({
            Title = "Không có NPC",
            Content = styleName .. " không có NPC bán ở world này!",
            Duration = 4
        })
        _buyStyleActive[styleName] = false
        return
    end

    -- Chạy trong coroutine để không block UI
    coroutine.wrap(function()
        pcall(function()
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                Library:Notify({Title = "Lỗi", Content = "Không tìm thấy nhân vật!", Duration = 3})
                _buyStyleActive[styleName] = false
                return
            end

            Library:Notify({
                Title = "Buy " .. styleName,
                Content = "Đang di chuyển đến NPC...",
                Duration = 3
            })

            -- Bật fly để di chuyển
            getgenv().IsFarming = true
            startFly()

            local targetCF = CFrame.new(targetPos + Vector3.new(0, 3, 0))
            TweenToPos(targetCF, getgenv().FlySpeed or 300)

            -- Chờ đến gần NPC hoặc bị tắt toggle hoặc timeout
            local deadline = tick() + 30
            repeat
                task.wait(0.2)
                if not _buyStyleActive[styleName] then break end
                local r = getRoot()
                if not r then break end
                if (r.Position - targetPos).Magnitude <= BUY_PROXIMITY then break end
            until tick() > deadline

            -- Kiểm tra lại: nếu toggle vẫn bật thì mới mua
            if _buyStyleActive[styleName] then
                local r = getRoot()
                if r and (r.Position - targetPos).Magnitude <= BUY_PROXIMITY then
                    task.wait(0.3)
                    styleData.remote()
                    Library:Notify({
                        Title = "Mua thành công!",
                        Content = "Đã gửi yêu cầu mua " .. styleName,
                        Duration = 4
                    })
                else
                    local dist = r and math.floor((r.Position - targetPos).Magnitude) or "?"
                    Library:Notify({
                        Title = "Thất bại",
                        Content = "Không đến được NPC " .. styleName .. " (khoảng cách: " .. dist .. " studs)",
                        Duration = 5
                    })
                end
            else
                Library:Notify({
                    Title = "Đã huỷ",
                    Content = "Buy " .. styleName .. " bị tắt.",
                    Duration = 3
                })
            end

            _buyStyleActive[styleName] = false

            -- Tắt fly nếu không có farm nào khác
            local anyFarmActive = getgenv().FarmLevel or getgenv().FarmBone or getgenv().FarmKata
                or getgenv().FarmAura or getgenv().FarmTyrant or getgenv().AutoMaterial
                or getgenv().FarmDungeon
            if not anyFarmActive then
                getgenv().IsFarming = false
                stopFly()
            end
        end)
    end)()
end

--------------------------------------------------------------------
-- THÊM SECTION VÕ THUẬT VÀO TAB SHOP
-- Chỉ hiển thị button cho world hiện tại (world không có NPC thì ẩn button)
--------------------------------------------------------------------

--------------------------------------------------------------------
-- SECTION: SHOP OPTIONS (Haki & Abilities)
--------------------------------------------------------------------
Tabs.Shop:AddSection("Shop Options")

Tabs.Shop:CreateButton({
    Title = "Buy Buso",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyHaki", "Buso")
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Geppo",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyHaki", "Geppo")
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Soru",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BuyHaki", "Soru")
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Ken",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("KenTalk", "Buy")
        end)
    end
})

--------------------------------------------------------------------
-- SECTION: FRAGMENTS SHOP
--------------------------------------------------------------------
Tabs.Shop:AddSection("Fragments Shop")

Tabs.Shop:CreateButton({
    Title = "Buy Refund Stats",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Refund", "2")
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Reroll Race",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "2")
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Ghoul Race (2.5k)",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("Ectoplasm", " Change", 4)
        end)
    end
})

Tabs.Shop:CreateButton({
    Title = "Buy Cyborg Race (2.5k)",
    Description = "",
    Callback = function()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("CyborgTrainer", " Buy")
        end)
    end
})

--------------------------------------------------------------------
-- SECTION: FIGHTING STYLE (TOGGLE)
--------------------------------------------------------------------
Tabs.Shop:AddSection("Fighting - Style")

-- Black Leg (W1, W2, W3)
if FightingStyleData.BlackLeg[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyBlackLeg", {
        Title = "Buy Black Leg",
        Description = "Bật: tween đến NPC mua Black Leg. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Black Leg", FightingStyleData.BlackLeg, v) end
    })
end

-- Electro (W1, W2, W3)
if FightingStyleData.Electro[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyElectro", {
        Title = "Buy Electro",
        Description = "Bật: tween đến NPC mua Electro. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Electro", FightingStyleData.Electro, v) end
    })
end

-- Fishman Karate (W1, W2, W3)
if FightingStyleData.FishmanKarate[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyFishmanKarate", {
        Title = "Buy Fishman Karate",
        Description = "Bật: tween đến NPC mua Fishman Karate. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Fishman Karate", FightingStyleData.FishmanKarate, v) end
    })
end

-- Dragon Claw (W2, W3)
if FightingStyleData.DragonClaw[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyDragonClaw", {
        Title = "Buy DragonClaw",
        Description = "Bật: tween đến NPC mua DragonClaw. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("DragonClaw", FightingStyleData.DragonClaw, v) end
    })
end

-- Superhuman (W2, W3)
if FightingStyleData.Superhuman[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuySuperhuman", {
        Title = "Buy Superhuman",
        Description = "Bật: tween đến NPC mua Superhuman. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Superhuman", FightingStyleData.Superhuman, v) end
    })
end

-- Death Step (W2, W3)
if FightingStyleData.DeathStep[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyDeathStep", {
        Title = "Buy Death Step",
        Description = "Bật: tween đến NPC mua Death Step. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Death Step", FightingStyleData.DeathStep, v) end
    })
end

-- Sharkman Karate (W2, W3)
if FightingStyleData.SharkmanKarate[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuySharkmanKarate", {
        Title = "Buy Sharkman Karate",
        Description = "Bật: tween đến NPC mua Sharkman Karate. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Sharkman Karate", FightingStyleData.SharkmanKarate, v) end
    })
end

-- Electric Claw (W3 only)
if FightingStyleData.ElectricClaw[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyElectricClaw", {
        Title = "Buy ElectricClaw",
        Description = "Bật: tween đến NPC mua ElectricClaw. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("ElectricClaw", FightingStyleData.ElectricClaw, v) end
    })
end

-- Dragon Talon (W3 only)
if FightingStyleData.DragonTalon[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyDragonTalon", {
        Title = "Buy DragonTalon",
        Description = "Bật: tween đến NPC mua DragonTalon. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("DragonTalon", FightingStyleData.DragonTalon, v) end
    })
end

-- Godhuman (W3 only)
if FightingStyleData.Godhuman[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuyGodhuman", {
        Title = "Buy Godhuman",
        Description = "Bật: tween đến NPC mua Godhuman. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("Godhuman", FightingStyleData.Godhuman, v) end
    })
end

-- Sanguine Art (W3 only)
if FightingStyleData.SanguineArt[currentWorldKey] then
    Tabs.Shop:CreateToggle("BuySanguineArt", {
        Title = "Buy SanguineArt",
        Description = "Bật: tween đến NPC mua SanguineArt. Tắt: huỷ.",
        Default = false,
        Callback = function(v) BuyFightingStyle("SanguineArt", FightingStyleData.SanguineArt, v) end
    })
end

-- Khôi phục settings sau khi toàn bộ UI đã sẵn sàng
AutoLoad()
