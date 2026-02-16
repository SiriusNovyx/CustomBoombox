local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local PlaylistStore = DataStoreService:GetDataStore("BoomboxPlaylist_V1")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local sound = handle:WaitForChild("BoomboxMusic")
local dataFunc = tool:WaitForChild("Data")
local replication = tool:WaitForChild("Replication")

-- Create Effects
local echo = sound:FindFirstChild("EchoEffect") or Instance.new("EchoSoundEffect", sound)
echo.Name = "EchoEffect"; echo.Enabled = false; echo.WetLevel = 0.4
local reverb = sound:FindFirstChild("ReverbEffect") or Instance.new("ReverbSoundEffect", sound)
reverb.Name = "ReverbEffect"; reverb.Enabled = false; reverb.DecayTime = 1.5

-- === ??? SECURITY ===
local OWNER_IDS = {
[6024031120] = true,
[7483134350] = true,
}

sound.Looped = true
sound.Volume = 0.5
sound.RollOffMaxDistance = 100
sound.RollOffMinDistance = 10

tool:SetAttribute("RGB", false)
tool:SetAttribute("Particles", false)

local MOUNT_NAME = "MountedBoomboxVisual"
local CurrentState = {Name = "Ready", Id = "", IsPlaying = false, StartPosition = 0, LastUpdateTimestamp = 0}

function broadcastState()
    replication:FireAllClients(CurrentState)
end

function dataFunc.OnServerInvoke(player, data)
    if not (player.Character) then return {Success = false, Error = "No Character"} end
    local char = player.Character
    local currentSound = char:FindFirstChild(MOUNT_NAME) and char[MOUNT_NAME]:FindFirstChild("BoomboxMusic") or handle:FindFirstChild("BoomboxMusic")
    
    if data.Action == "GetState" then
        return {
        Success = true, 
        Name = CurrentState.Name, 
        Id = CurrentState.Id, 
        IsPlaying = CurrentState.IsPlaying, 
        StartPosition = CurrentState.StartPosition, 
        LastUpdateTimestamp = CurrentState.LastUpdateTimestamp, 
        Status = (CurrentState.IsPlaying and "Playing" or "Paused")
        }
        
    elseif data.Action == "SaveSong" then
        local resultStatus = "Error"
        local success, err = pcall(function()
            local currentList = PlaylistStore:GetAsync(player.UserId) or {}
            for _, s in pairs(currentList) do if s.Id == data.Id then resultStatus = "Duplicate"; return end end
            table.insert(currentList, {Name = data.Name, Id = data.Id})
            PlaylistStore:SetAsync(player.UserId, currentList)
            resultStatus = "Saved"
        end)
        if success and resultStatus == "Saved" then return {Success = true}
        elseif resultStatus == "Duplicate" then return {Success = false, Reason = "Duplicate"}
        else warn("Save Failed: "..tostring(err)); return {Success = false, Reason = "Error"} end
            
        elseif data.Action == "GetPlaylist" then
            local list = {}; pcall(function() list = PlaylistStore:GetAsync(player.UserId) or {} end)
                return {Success = true, List = list}
                
            elseif data.Action == "DeleteSong" then
                pcall(function()
                    local currentList = PlaylistStore:GetAsync(player.UserId) or {}
                    for i, s in pairs(currentList) do if s.Id == data.Id then table.remove(currentList, i); break end end
                    PlaylistStore:SetAsync(player.UserId, currentList)
                end)
                return {Success = true}
                
            elseif data.Action == "ToggleSetting" then
                if data.Setting == "RGB" then tool:SetAttribute("RGB", data.Value)
                elseif data.Setting == "Particles" then tool:SetAttribute("Particles", data.Value)
                end
                    return {Success = true}
                    
                    -- [FIXED] RESUME LOGIC
                elseif data.Action == "Play" then
                    CurrentState.IsPlaying = true
                    
                    -- FIX: If Server Sound reads 0 but we have a saved position, force the saved position
                    if currentSound.TimePosition < 0.1 and CurrentState.StartPosition > 0.1 then
                        currentSound.TimePosition = CurrentState.StartPosition
                    else
                        CurrentState.StartPosition = currentSound.TimePosition
                    end
                    
                    CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
                    
                    currentSound:Play()
                    broadcastState()
                    return {Success = true, Status = "Resumed"}
                    
                    -- [FIXED] PAUSE LOGIC
                elseif data.Action == "Pause" then
                    currentSound:Pause()
                    CurrentState.IsPlaying = false
                    CurrentState.StartPosition = currentSound.TimePosition -- Save this carefully
                    broadcastState()
                    return {Success = true, Status = "Paused"}
                    
                elseif data.Action == "Stop" then
                    currentSound:Stop()
                    CurrentState.IsPlaying = false
                    CurrentState.StartPosition = 0 -- Reset only on explicit STOP
                    broadcastState()
                    return {Success = true, Status = "Stopped"}
                    
                elseif data.Action == "AudioId" then
                    currentSound:Stop()
                    
                    local cleanId = string.match(data.Value, "%d+")
                    if not cleanId then return {Success = false, Error = "Invalid ID"} end
                    
                    local startPos = tonumber(data.Time) or 0
                    
                    currentSound.SoundId = "rbxassetid://" .. cleanId
                    currentSound.TimePosition = startPos
                    currentSound:Play()
                    
                    local songName = "Track " .. cleanId
                    task.spawn(function()
                        pcall(function()
                            local info = MarketplaceService:GetProductInfo(tonumber(cleanId))
                            if info and info.Name then songName = info.Name end
                        end)
                        if CurrentState.Id == cleanId then CurrentState.Name = songName; broadcastState() end
                    end)
                    
                    local t = 0
                    while currentSound.TimeLength == 0 and t < 2 do t = t + 0.1; task.wait(0.1) end
                    
                    if currentSound.TimeLength > 0 then
                        CurrentState.Name = songName
                        CurrentState.Id = cleanId
                        CurrentState.IsPlaying = true
                        CurrentState.StartPosition = startPos
                        CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow() 
                        broadcastState()
                        return {Success = true, Name = songName}
                    else
                        currentSound:Stop()
                        return {Success = false, Error = "Failed to Load"}
                    end
                    
                elseif data.Action == "Seek" then
                    local newTime = tonumber(data.Value)
                    if newTime then
                        currentSound.TimePosition = math.clamp(newTime, 0, currentSound.TimeLength)
                        CurrentState.StartPosition = currentSound.TimePosition
                        CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
                        broadcastState()
                    end
                    return {Success = true}
                    
                elseif data.Action == "Volume" then
                    local vol = tonumber(data.Value)
                    if vol then 
                        local isOwner = OWNER_IDS[player.UserId]
                        currentSound.Volume = math.clamp(vol, 0, isOwner and 20 or 5)
                    end
                    
                elseif data.Action == "Pitch" then
                    local pitch = tonumber(data.Value)
                    if pitch then currentSound.PlaybackSpeed = math.clamp(pitch, 0.5, 2.0) end
                    
                elseif data.Action == "Loop" then
                    currentSound.Looped = not currentSound.Looped
                    return {Success = true, IsLooping = currentSound.Looped}
                    
                elseif data.Action == "Mount" then
                    local existingMount = char:FindFirstChild(MOUNT_NAME)
                    if existingMount then sound.Parent = handle; existingMount:Destroy(); return {Success = true, IsMounted = false}
                    else
                        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                        if not torso then return {Success = false, Error = "No Torso"} end
                        local mountPart = handle:Clone(); mountPart.Name = MOUNT_NAME; mountPart.CanCollide = false; mountPart.Massless = true
                        for _, v in pairs(mountPart:GetChildren()) do if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("Sound") then v:Destroy() end end
                        mountPart.CFrame = torso.CFrame * CFrame.new(0, 0, 1) * CFrame.Angles(0, math.rad(180), 0)
                        mountPart.Parent = char; local weld = Instance.new("WeldConstraint"); weld.Part0 = torso; weld.Part1 = mountPart; weld.Parent = mountPart; sound.Parent = mountPart
                        return {Success = true, IsMounted = true}
                    end
                end
                return {Success = true}
            end

