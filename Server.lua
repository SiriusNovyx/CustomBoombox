local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local PlaylistStore = DataStoreService:GetDataStore("BoomboxPlaylist_V1")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local dataFunc = tool:WaitForChild("Data")
local replication = tool:WaitForChild("Replication")

-- === ??? SECURITY ===
local OWNER_IDS = {
	[6024031120] = true,
	[7483134350] = true,
}

tool:SetAttribute("RGB", false)
tool:SetAttribute("Particles", false)

local MOUNT_NAME = "MountedBoomboxVisual"
local PLAYER_NAME = "BoomboxAudioPlayer"
local EMITTER_NAME = "BoomboxAudioEmitter"
local WIRE_NAME = "BoomboxAudioWire"

local CurrentState = {Name = "Ready", Id = "", IsPlaying = false, StartPosition = 0, LastUpdateTimestamp = 0, PlaybackSpeed = 1}

local function setPropertySafe(instance, propertyName, value)
	pcall(function()
		instance[propertyName] = value
	end)
end

local function getPropertySafe(instance, propertyName, fallback)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if ok and value ~= nil then
		return value
	end
	return fallback
end

local function resolveAudioPart(parent)
	if parent and parent:IsA("BasePart") then
		return parent
	end
	if parent then
		local candidate = parent:FindFirstChildWhichIsA("BasePart")
		if candidate then
			return candidate
		end
	end
	return handle
end

local function ensureAudioRig(parent)
	local audioParent = resolveAudioPart(parent)
	local audioPlayer = audioParent:FindFirstChild(PLAYER_NAME)
	if not (audioPlayer and audioPlayer:IsA("AudioPlayer")) then
		if audioPlayer then
			audioPlayer:Destroy()
		end
		audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Name = PLAYER_NAME
		audioPlayer.Parent = audioParent
	end

	local audioEmitter = audioParent:FindFirstChild(EMITTER_NAME)
	if not (audioEmitter and audioEmitter:IsA("AudioEmitter")) then
		if audioEmitter then
			audioEmitter:Destroy()
		end
		audioEmitter = Instance.new("AudioEmitter")
		audioEmitter.Name = EMITTER_NAME
		audioEmitter.Parent = audioParent
	else
		audioEmitter.Parent = audioParent
	end

	local wire = audioParent:FindFirstChild(WIRE_NAME)
	if not (wire and wire:IsA("Wire")) then
		if wire then
			wire:Destroy()
		end
		wire = Instance.new("Wire")
		wire.Name = WIRE_NAME
		wire.Parent = audioParent
	else
		wire.Parent = audioParent
	end

	wire.SourceInstance = audioPlayer
	wire.TargetInstance = audioEmitter

	setPropertySafe(audioPlayer, "AutoLoad", true)
	setPropertySafe(audioPlayer, "Looping", true)
	setPropertySafe(audioPlayer, "Volume", 0.5)
	setPropertySafe(audioPlayer, "PlaybackSpeed", 1)
	setPropertySafe(audioEmitter, "MaxDistance", 100)
	setPropertySafe(audioEmitter, "MinDistance", 10)
	pcall(function()
		audioEmitter:SetDistanceAttenuation({[0] = 1, [15] = 0.8, [50] = 0.2, [80] = 0})
	end)

	return audioPlayer, audioEmitter, wire
end

local function getCurrentPlayerForCharacter(char)
	local mounted = char and char:FindFirstChild(MOUNT_NAME)
	if mounted then
		return ensureAudioRig(mounted)
	end
	return ensureAudioRig(handle)
end

local function getTimeLength(audioPlayer)
	local length = getPropertySafe(audioPlayer, "TimeLength", 0)
	if typeof(length) == "number" and length > 0 then
		return length
	end
	length = getPropertySafe(audioPlayer, "Length", 0)
	if typeof(length) == "number" and length > 0 then
		return length
	end
	return 0
end

local function broadcastState()
	replication:FireAllClients(CurrentState)
end

-- Ensure rig exists on tool handle at startup.
ensureAudioRig(handle)

function dataFunc.OnServerInvoke(player, data)
	if not player.Character then
		return {Success = false, Error = "No Character"}
	end
	local char = player.Character
	local currentPlayer = getCurrentPlayerForCharacter(char)

	if data.Action == "GetState" then
		return {
			Success = true,
			Name = CurrentState.Name,
			Id = CurrentState.Id,
			IsPlaying = CurrentState.IsPlaying,
			StartPosition = CurrentState.StartPosition,
			LastUpdateTimestamp = CurrentState.LastUpdateTimestamp,
			Status = (CurrentState.IsPlaying and "Playing" or "Paused"),
			PlaybackSpeed = CurrentState.PlaybackSpeed,
		}

	elseif data.Action == "SaveSong" then
		local resultStatus = "Error"
		local success, err = pcall(function()
			local currentList = PlaylistStore:GetAsync(player.UserId) or {}
			for _, s in pairs(currentList) do
				if s.Id == data.Id then
					resultStatus = "Duplicate"
					return
				end
			end
			table.insert(currentList, {Name = data.Name, Id = data.Id})
			PlaylistStore:SetAsync(player.UserId, currentList)
			resultStatus = "Saved"
		end)
		if success and resultStatus == "Saved" then
			return {Success = true}
		elseif resultStatus == "Duplicate" then
			return {Success = false, Reason = "Duplicate"}
		else
			warn("Save Failed: " .. tostring(err))
			return {Success = false, Reason = "Error"}
		end

	elseif data.Action == "GetPlaylist" then
		local list = {}
		pcall(function()
			list = PlaylistStore:GetAsync(player.UserId) or {}
		end)
		return {Success = true, List = list}

	elseif data.Action == "DeleteSong" then
		pcall(function()
			local currentList = PlaylistStore:GetAsync(player.UserId) or {}
			for i, s in pairs(currentList) do
				if s.Id == data.Id then
					table.remove(currentList, i)
					break
				end
			end
			PlaylistStore:SetAsync(player.UserId, currentList)
		end)
		return {Success = true}

	elseif data.Action == "ToggleSetting" then
		if data.Setting == "RGB" then
			tool:SetAttribute("RGB", data.Value)
		elseif data.Setting == "Particles" then
			tool:SetAttribute("Particles", data.Value)
		end
		return {Success = true}

	elseif data.Action == "Play" then
		CurrentState.IsPlaying = true

		local currentTime = getPropertySafe(currentPlayer, "TimePosition", 0)
		if currentTime < 0.1 and CurrentState.StartPosition > 0.1 then
			setPropertySafe(currentPlayer, "TimePosition", CurrentState.StartPosition)
		else
			CurrentState.StartPosition = currentTime
		end

		CurrentState.PlaybackSpeed = getPropertySafe(currentPlayer, "PlaybackSpeed", 1)
		CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
		currentPlayer:Play()
		broadcastState()
		return {Success = true, Status = "Resumed"}

	elseif data.Action == "Pause" then
		currentPlayer:Pause()
		CurrentState.IsPlaying = false
		CurrentState.StartPosition = getPropertySafe(currentPlayer, "TimePosition", 0)
		broadcastState()
		return {Success = true, Status = "Paused"}

	elseif data.Action == "Stop" then
		currentPlayer:Stop()
		CurrentState.IsPlaying = false
		CurrentState.StartPosition = 0
		broadcastState()
		return {Success = true, Status = "Stopped"}

	elseif data.Action == "AudioId" then
		currentPlayer:Stop()

		local cleanId = string.match(tostring(data.Value), "%d+")
		if not cleanId then
			return {Success = false, Error = "Invalid ID"}
		end

		local startPos = tonumber(data.Time) or 0
		setPropertySafe(currentPlayer, "Asset", "rbxassetid://" .. cleanId)
		setPropertySafe(currentPlayer, "TimePosition", startPos)
		currentPlayer:Play()

		local songName = "Track " .. cleanId
		task.spawn(function()
			pcall(function()
				local info = MarketplaceService:GetProductInfo(tonumber(cleanId))
				if info and info.Name then
					songName = info.Name
				end
			end)
			if CurrentState.Id == cleanId then
				CurrentState.Name = songName
				broadcastState()
			end
		end)

		local t = 0
		while getTimeLength(currentPlayer) == 0 and t < 2 do
			t = t + 0.1
			task.wait(0.1)
		end

		if getTimeLength(currentPlayer) > 0 then
			CurrentState.Name = songName
			CurrentState.Id = cleanId
			CurrentState.IsPlaying = true
			CurrentState.StartPosition = startPos
			CurrentState.PlaybackSpeed = getPropertySafe(currentPlayer, "PlaybackSpeed", 1)
			CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
			broadcastState()
			return {Success = true, Name = songName}
		else
			currentPlayer:Stop()
			return {Success = false, Error = "Failed to Load"}
		end

	elseif data.Action == "Seek" then
		local newTime = tonumber(data.Value)
		if newTime then
			local length = getTimeLength(currentPlayer)
			if length > 0 then
				setPropertySafe(currentPlayer, "TimePosition", math.clamp(newTime, 0, length))
			else
				setPropertySafe(currentPlayer, "TimePosition", math.max(newTime, 0))
			end
			CurrentState.StartPosition = getPropertySafe(currentPlayer, "TimePosition", 0)
			CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
			broadcastState()
		end
		return {Success = true}

	elseif data.Action == "Volume" then
		local vol = tonumber(data.Value)
		if vol then
			local isOwner = OWNER_IDS[player.UserId]
			setPropertySafe(currentPlayer, "Volume", math.clamp(vol, 0, isOwner and 20 or 5))
		end

	elseif data.Action == "Pitch" then
		local pitch = tonumber(data.Value)
		if pitch then
			local newSpeed = math.clamp(pitch, 0.5, 2.0)
			setPropertySafe(currentPlayer, "PlaybackSpeed", newSpeed)
			CurrentState.PlaybackSpeed = newSpeed
			CurrentState.StartPosition = getPropertySafe(currentPlayer, "TimePosition", 0)
			CurrentState.LastUpdateTimestamp = workspace:GetServerTimeNow()
			broadcastState()
			return {Success = true, PlaybackSpeed = newSpeed}
		end

	elseif data.Action == "Loop" then
		local newLooping = not getPropertySafe(currentPlayer, "Looping", true)
		setPropertySafe(currentPlayer, "Looping", newLooping)
		return {Success = true, IsLooping = newLooping}

	elseif data.Action == "Mount" then
		local existingMount = char:FindFirstChild(MOUNT_NAME)
		if existingMount then
			local toolPlayer = ensureAudioRig(handle)
			local mountPlayer = ensureAudioRig(existingMount)
			if getPropertySafe(mountPlayer, "Asset", "") ~= "" then
				setPropertySafe(toolPlayer, "Asset", getPropertySafe(mountPlayer, "Asset", ""))
			end
			setPropertySafe(toolPlayer, "TimePosition", getPropertySafe(mountPlayer, "TimePosition", 0))
			setPropertySafe(toolPlayer, "PlaybackSpeed", getPropertySafe(mountPlayer, "PlaybackSpeed", 1))
			setPropertySafe(toolPlayer, "Volume", getPropertySafe(mountPlayer, "Volume", 0.5))
			setPropertySafe(toolPlayer, "Looping", getPropertySafe(mountPlayer, "Looping", true))
			if CurrentState.IsPlaying then
				toolPlayer:Play()
			else
				toolPlayer:Pause()
			end
			existingMount:Destroy()
			return {Success = true, IsMounted = false}
		else
			local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
			if not torso then
				return {Success = false, Error = "No Torso"}
			end

			local mountPart = handle:Clone()
			mountPart.Name = MOUNT_NAME
			mountPart.CanCollide = false
			mountPart.Massless = true
			for _, v in pairs(mountPart:GetChildren()) do
				if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("Sound") or v:IsA("AudioPlayer") or v:IsA("AudioEmitter") or v:IsA("Wire") then
					v:Destroy()
				end
			end
			mountPart.CFrame = torso.CFrame * CFrame.new(0, 0, 1) * CFrame.Angles(0, math.rad(180), 0)
			mountPart.Parent = char
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = mountPart
			weld.Parent = mountPart

			local mountPlayer = ensureAudioRig(mountPart)
			local toolPlayer = ensureAudioRig(handle)
			setPropertySafe(mountPlayer, "Asset", getPropertySafe(toolPlayer, "Asset", ""))
			setPropertySafe(mountPlayer, "TimePosition", getPropertySafe(toolPlayer, "TimePosition", 0))
			setPropertySafe(mountPlayer, "PlaybackSpeed", getPropertySafe(toolPlayer, "PlaybackSpeed", 1))
			setPropertySafe(mountPlayer, "Volume", getPropertySafe(toolPlayer, "Volume", 0.5))
			setPropertySafe(mountPlayer, "Looping", getPropertySafe(toolPlayer, "Looping", true))

			if CurrentState.IsPlaying then
				mountPlayer:Play()
				toolPlayer:Stop()
			end
			return {Success = true, IsMounted = true}
		end
	end

	return {Success = true}
end
