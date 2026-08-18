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

-- Camera Control (Optional, will skip if not available)
local function DisableCameraShake()
    pcall(function()
        local cameraModule = require(ReplicatedStorage.Util.CameraShaker)
        cameraModule:Stop()
    end)
end

-- Main Loop Initialization
local function StartMainLoops()
    task.spawn(function()
        while task.wait(FastAttackModule.Rate) do
            pcall(FastAttackModule.ExecuteFastAttack)
        end
    end)
    
    RunService.Heartbeat:Connect(function()
        pcall(HitRegistrationModule.Execute)
    end)
end

-- Main Controller
function MainController.Start()
    DisableCameraShake()
    StartMainLoops()
end

-- Auto-start the system
MainController.Start()

-- Handle character respawn
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
end)

print("Fast Attack System Loaded Successfully!")
