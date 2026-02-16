local player = game.Players.LocalPlayer
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local contentProvider = game:GetService("ContentProvider") 
local camera = workspace.CurrentCamera
local tweenService = game:GetService("TweenService")
 
local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local dataFunc = tool:WaitForChild("Data")
local replication = tool:WaitForChild("Replication")
 
-- === ??? DEBUG & CONSTANTS ===
local DEBUG_MODE = true 
local function debugLog(msg) if DEBUG_MODE then warn("[BOOMBOX]: " .. tostring(msg)) end end
 
local COOLDOWN_TIME = 1.5
local THEME = {
BG = Color3.fromRGB(25, 25, 35),
Text = Color3.fromRGB(255, 255, 255),
Accent = Color3.fromRGB(10, 132, 255),
Red = Color3.fromRGB(255, 69, 58),
Yellow = Color3.fromRGB(255, 159, 10),
Green = Color3.fromRGB(48, 209, 88),
Stroke = Color3.fromRGB(255, 255, 255)
}
 
-- UI Elements
local gui, mainFrame, contentFrame, topBar
local trafficRed, trafficYellow, trafficGreen
local idInput, volInput, pitchInput
local loadBtn, saveBtn
local playBtn, pauseBtn, stopBtn, loopBtn, mountBtn
local timelineBG, timelineFill, timelineKnob
local timeLabelLeft, timeLabelRight, syncLabel -- [NEW] syncLabel
local notificationFrame, notifText
local playlistFrame, playlistScroll
local vizContainer
local vizBars = {}
local uiScale 
 
local OWNER_IDS = { [6024031120] = true, [7483134350] = true }
 
-- State
local currentSongName = "Ready" 
local lastWorkingId = "" 
local lastWorkingTime = 0
local isDraggingTimeline = false 
local originalSize = handle.Size
local originalColor = handle.Color
local scrollOffset = 0 
local timeOffset = 0
local smoothedLoudness = 0 
local isLoading = false 
local isActionCooldown = false 
local isMinimized = false
 
-- Global State for Sync
local globalState = {
IsPlaying = false,
StartPosition = 0,
LastUpdateTimestamp = 0
}
 
-- Safety
local isVolumeLocked = false
local lockDuration = 5 
 
-- Animation
local currentAnimTrack = nil
 
-- === CUSTOM DRAGGER ===
local function makeDraggable(guiObj)
    guiObj.Active = true; guiObj.Selectable = true
    local dragging, dragInput, dragStart, startPos
    guiObj.InputBegan:Connect(function(input)
        if guiObj:GetAttribute("Locked") then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = guiObj.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
            end)
                guiObj.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
                    userInputService.InputChanged:Connect(function(input) 
                        if input == dragInput and dragging then 
                            if guiObj:GetAttribute("Locked") then dragging = false; return end
                            local delta = input.Position - dragStart; guiObj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) 
                        end 
                    end)
                end
 
                -- === UI HELPERS ===
                local function createRound(parent, radius)
                    local uiCorner = Instance.new("UICorner", parent)
                    uiCorner.CornerRadius = UDim.new(0, radius)
                    return uiCorner
                end
 
                local function createStroke(parent, transparency, thickness)
                    local uiStroke = Instance.new("UIStroke", parent)
                    uiStroke.Color = THEME.Stroke
                    uiStroke.Transparency = transparency
                    uiStroke.Thickness = thickness
                    uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    return uiStroke
                end
 
                local function formatTime(seconds)
                    if not seconds or seconds == math.huge then return "0:00" end
                    local m = math.floor(seconds / 60); local s = math.floor(seconds % 60)
                    return string.format("%d:%02d", m, s)
                end
 
                -- === NOTIFICATION SYSTEM ===
                local function showNotification(text, typeColor)
                    if not notificationFrame then return end
                    notifText.Text = text
                    notifText.TextColor3 = typeColor or THEME.Text
                    
                    notificationFrame:TweenPosition(UDim2.new(0.5, -100, 0, 10), "Out", "Back", 0.4, true)
                    task.delay(2.5, function()
                        notificationFrame:TweenPosition(UDim2.new(0.5, -100, 0, -60), "In", "Quad", 0.3, true)
                    end)
                end
 
                -- === CORE FUNCTIONS ===
                local function getSound()
                    local char = player.Character
                    if char then
                        local mounted = char:FindFirstChild("MountedBoomboxVisual")
                        if mounted and mounted:FindFirstChild("BoomboxMusic") then return mounted.BoomboxMusic end
                    end
                    return handle:FindFirstChild("BoomboxMusic")
                end
 
                -- === ?? SYNC LOGIC ===
                local function syncAudio(state)
                    local sound = getSound()
                    if not sound then return end
 
                    -- Update Global State
                    globalState.IsPlaying = state.IsPlaying
                    globalState.StartPosition = state.StartPosition or 0
                    globalState.LastUpdateTimestamp = state.LastUpdateTimestamp or 0
 
                    if state.Name then currentSongName = state.Name end
                    if state.Id then idBox.Text = state.Id end
                    
                    -- Update Status Text
                    if scrollingMusicLabel then
                        if state.Status == "Paused" then
                            scrollingMusicLabel.Text = "Paused: " .. currentSongName
                            scrollingMusicLabel.TextColor3 = THEME.Yellow
                        elseif not state.IsPlaying then
                            scrollingMusicLabel.Text = "Stopped"
                            scrollingMusicLabel.TextColor3 = Color3.fromRGB(150,150,150)
                        else
                            scrollingMusicLabel.Text = currentSongName
                            scrollingMusicLabel.TextColor3 = THEME.Text
                        end
                        scrollOffset = 0
                        scrollingMusicLabel.Position = UDim2.new(0,0,0,0)
                    end
                    
                    if state.IsPlaying then
                        if not sound.IsLoaded then
                            task.spawn(function()
                                contentProvider:PreloadAsync({sound})
                                local timeout = 0
                                while not sound.IsLoaded and timeout < 3 do timeout = timeout + 0.1; task.wait(0.1) end
                                
                                if sound.IsLoaded then
                                    if not sound.IsPlaying then sound:Play() end
                                    local timePassed = workspace:GetServerTimeNow() - state.LastUpdateTimestamp
                                    local targetTime = state.StartPosition + timePassed
                                    if sound.Looped then targetTime = targetTime % sound.TimeLength else targetTime = math.clamp(targetTime, 0, sound.TimeLength) end
                                    sound.TimePosition = targetTime
                                end
                            end)
                        else
                            if not sound.IsPlaying then sound:Play() end
                            
                            local timePassed = workspace:GetServerTimeNow() - state.LastUpdateTimestamp
                            local targetTime = state.StartPosition + timePassed
                            if sound.Looped then targetTime = targetTime % sound.TimeLength else targetTime = math.clamp(targetTime, 0, sound.TimeLength) end
                            
                            if math.abs(sound.TimePosition - targetTime) > 0.5 then
                                sound.TimePosition = targetTime
                            end
                        end
                    else
                        sound:Stop()
                    end
                end
 
                -- === LOAD PLAYLIST ===
                local function loadPlaylist()
                    for _, child in pairs(playlistScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
                    local res = dataFunc:InvokeServer({Action = "GetPlaylist"})
                    if res.Success and res.List then
                        for _, song in ipairs(res.List) do
                            local row = Instance.new("Frame", playlistScroll)
                            row.Size = UDim2.new(1, 0, 0, 35); row.BackgroundColor3 = Color3.fromRGB(40, 40, 40); row.BackgroundTransparency = 0.5
                            createRound(row, 6)
                            
                            local nameLbl = Instance.new("TextLabel", row); nameLbl.Size = UDim2.new(0.65, 0, 1, 0); nameLbl.Position = UDim2.new(0.05, 0, 0, 0); nameLbl.BackgroundTransparency = 1; nameLbl.Text = song.Name; nameLbl.TextColor3 = THEME.Text; nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.Font = Enum.Font.GothamMedium; nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                            
                            local playB = Instance.new("TextButton", row); playB.Size = UDim2.new(0.12, 0, 0.7, 0); playB.Position = UDim2.new(0.72, 0, 0.15, 0); playB.Text = "?"; playB.BackgroundColor3 = THEME.Accent; playB.TextColor3 = THEME.Text; createRound(playB, 4)
                            local delB = Instance.new("TextButton", row); delB.Size = UDim2.new(0.12, 0, 0.7, 0); delB.Position = UDim2.new(0.86, 0, 0.15, 0); delB.Text = "X"; delB.BackgroundColor3 = THEME.Red; delB.TextColor3 = THEME.Text; createRound(delB, 4)
                            
                            playB.MouseButton1Click:Connect(function() idBox.Text = song.Id; loadBtnLink() end)
                                delB.MouseButton1Click:Connect(function() dataFunc:InvokeServer({Action = "DeleteSong", Id = song.Id}); row:Destroy() end)
                                end
                                end
                                end
 
                                    -- === GUI CREATION ===
                                    function createGui()
                                        if player:WaitForChild("PlayerGui"):FindFirstChild("BoomboxUI_Ultimate") then player.PlayerGui.BoomboxUI_Ultimate:Destroy() end
 
                                        gui = Instance.new("ScreenGui")
                                        gui.Name = "BoomboxUI_Ultimate"
                                        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling 
                                        gui.ResetOnSpawn = true 
                                        
                                        notificationFrame = Instance.new("Frame", gui)
                                        notificationFrame.Size = UDim2.new(0, 200, 0, 32)
                                        notificationFrame.Position = UDim2.new(0.5, -100, 0, -60)
                                        notificationFrame.BackgroundColor3 = Color3.fromRGB(10,10,10)
                                        notificationFrame.ZIndex = 200
                                        createRound(notificationFrame, 20)
                                        createStroke(notificationFrame, 0.8, 1)
                                        
                                        notifText = Instance.new("TextLabel", notificationFrame)
                                        notifText.Size = UDim2.new(1,0,1,0)
                                        notifText.BackgroundTransparency = 1
                                        notifText.Font = Enum.Font.GothamBold
                                        notifText.TextSize = 14
                                        notifText.Text = "" -- [FIX] Empty by default
                                        notifText.TextColor3 = THEME.Text
 
                                        mainFrame = Instance.new("Frame", gui)
                                        mainFrame.Size = UDim2.new(0, 320, 0, 450)
                                        mainFrame.Position = UDim2.new(0.5, -160, 0.5, -225)
                                        mainFrame.BackgroundColor3 = THEME.BG
                                        mainFrame.BackgroundTransparency = 0.1
                                        mainFrame:SetAttribute("Locked", false)
                                        makeDraggable(mainFrame)
                                        createRound(mainFrame, 16)
                                        createStroke(mainFrame, 0.8, 1)
                                        
                                        uiScale = Instance.new("UIScale", mainFrame)
                                        
                                        topBar = Instance.new("Frame", mainFrame)
                                        topBar.Size = UDim2.new(1, 0, 0, 40)
                                        topBar.BackgroundTransparency = 1
                                        
                                        trafficRed = Instance.new("TextButton", topBar); trafficRed.Size = UDim2.new(0, 22, 0, 22); trafficRed.Position = UDim2.new(0, 15, 0.5, -11); trafficRed.BackgroundColor3 = THEME.Red; trafficRed.Text = ""; createRound(trafficRed, 11)
                                        trafficYellow = Instance.new("TextButton", topBar); trafficYellow.Size = UDim2.new(0, 22, 0, 22); trafficYellow.Position = UDim2.new(0, 50, 0.5, -11); trafficYellow.BackgroundColor3 = THEME.Yellow; trafficYellow.Text = ""; createRound(trafficYellow, 11)
                                        trafficGreen = Instance.new("TextButton", topBar); trafficGreen.Size = UDim2.new(0, 22, 0, 22); trafficGreen.Position = UDim2.new(0, 85, 0.5, -11); trafficGreen.BackgroundColor3 = THEME.Green; trafficGreen.Text = ""; createRound(trafficGreen, 11)
 
                                        contentFrame = Instance.new("Frame", mainFrame)
                                        contentFrame.Size = UDim2.new(1, -20, 1, -40)
                                        contentFrame.Position = UDim2.new(0, 10, 0, 35)
                                        contentFrame.BackgroundTransparency = 1
 
                                        local vizArea = Instance.new("Frame", contentFrame)
                                        vizArea.Size = UDim2.new(1, 0, 0, 60)
                                        vizArea.BackgroundColor3 = Color3.fromRGB(0,0,0)
                                        vizArea.BackgroundTransparency = 0.5
                                        createRound(vizArea, 8)
                                        
                                        vizContainer = Instance.new("Frame", vizArea)
                                        vizContainer.Size = UDim2.new(0.9, 0, 0.8, 0)
                                        vizContainer.Position = UDim2.new(0.05, 0, 0.1, 0)
                                        vizContainer.BackgroundTransparency = 1
                                        local vizLayout = Instance.new("UIListLayout", vizContainer); vizLayout.FillDirection = Enum.FillDirection.Horizontal; vizLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; vizLayout.VerticalAlignment = Enum.VerticalAlignment.Center; vizLayout.Padding = UDim.new(0, 3)
                                        for i=1, 20 do local bar = Instance.new("Frame", vizContainer); bar.Size = UDim2.new(0, 8, 0, 5); bar.BackgroundColor3 = THEME.Text; bar.BackgroundTransparency = 0.4; createRound(bar, 2); table.insert(vizBars, bar) end
 
                                        local scrollClip = Instance.new("Frame", contentFrame)
                                        scrollClip.Size = UDim2.new(1, 0, 0, 25)
                                        scrollClip.Position = UDim2.new(0, 0, 0, 70)
                                        scrollClip.BackgroundTransparency = 1
                                        scrollClip.ClipsDescendants = true
                                        
                                        scrollingMusicLabel = Instance.new("TextLabel", scrollClip)
                                        scrollingMusicLabel.Size = UDim2.new(1, 0, 1, 0)
                                        scrollingMusicLabel.AutomaticSize = Enum.AutomaticSize.X
                                        scrollingMusicLabel.BackgroundTransparency = 1
                                        scrollingMusicLabel.Text = "Ready to Play"
                                        scrollingMusicLabel.TextColor3 = THEME.Text
                                        scrollingMusicLabel.Font = Enum.Font.GothamBold
                                        scrollingMusicLabel.TextSize = 16
                                        scrollingMusicLabel.TextWrapped = false
 
                                        timelineBG = Instance.new("Frame", contentFrame)
                                        timelineBG.Size = UDim2.new(1, 0, 0, 4)
                                        timelineBG.Position = UDim2.new(0, 0, 0, 110)
                                        timelineBG.BackgroundColor3 = Color3.fromRGB(80,80,80)
                                        createRound(timelineBG, 2)
                                        timelineFill = Instance.new("Frame", timelineBG); timelineFill.Size = UDim2.new(0, 0, 1, 0); timelineFill.BackgroundColor3 = THEME.Text; createRound(timelineFill, 2)
                                        timelineKnob = Instance.new("Frame", timelineBG); timelineKnob.Size = UDim2.new(0, 12, 0, 12); timelineKnob.AnchorPoint = Vector2.new(0.5, 0.5); timelineKnob.Position = UDim2.new(0, 0, 0.5, 0); timelineKnob.BackgroundColor3 = THEME.Text; createRound(timelineKnob, 6)
                                        
                                        timeLabelLeft = Instance.new("TextLabel", contentFrame); timeLabelLeft.Size = UDim2.new(0, 50, 0, 15); timeLabelLeft.Position = UDim2.new(0, 0, 0, 120); timeLabelLeft.BackgroundTransparency = 1; timeLabelLeft.Text = "0:00"; timeLabelLeft.TextColor3 = Color3.fromRGB(180,180,180); timeLabelLeft.Font = Enum.Font.Gotham; timeLabelLeft.TextSize = 12; timeLabelLeft.TextXAlignment = Enum.TextXAlignment.Left
                                        timeLabelRight = Instance.new("TextLabel", contentFrame); timeLabelRight.Size = UDim2.new(0, 50, 0, 15); timeLabelRight.Position = UDim2.new(1, -50, 0, 120); timeLabelRight.BackgroundTransparency = 1; timeLabelRight.Text = "0:00"; timeLabelRight.TextColor3 = Color3.fromRGB(180,180,180); timeLabelRight.Font = Enum.Font.Gotham; timeLabelRight.TextSize = 12; timeLabelRight.TextXAlignment = Enum.TextXAlignment.Right
 
                                        -- [NEW] SYNC NOTE LABEL
                                        syncLabel = Instance.new("TextLabel", contentFrame)
                                        syncLabel.Size = UDim2.new(1, 0, 0, 15)
                                        syncLabel.Position = UDim2.new(0, 0, 0, 138)
                                        syncLabel.BackgroundTransparency = 1
                                        syncLabel.Text = "Note: If others desync, move the seek bar to fix it."
                                        syncLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                                        syncLabel.Font = Enum.Font.Gotham
                                        syncLabel.TextSize = 11
 
                                        -- [SHIFTED DOWN] All elements moved by +15 pixels
                                        local inputRow = Instance.new("Frame", contentFrame); inputRow.Size = UDim2.new(1, 0, 0, 35); inputRow.Position = UDim2.new(0, 0, 0, 160); inputRow.BackgroundTransparency = 1
                                        idBox = Instance.new("TextBox", inputRow); idBox.Size = UDim2.new(0.65, 0, 1, 0); idBox.BackgroundColor3 = Color3.fromRGB(40,40,40); idBox.PlaceholderText = "Song ID"; idBox.Text = ""; idBox.TextColor3 = THEME.Text; idBox.PlaceholderColor3 = Color3.fromRGB(150,150,150); idBox.Font = Enum.Font.Gotham; createRound(idBox, 8)
                                        loadBtn = Instance.new("TextButton", inputRow); loadBtn.Size = UDim2.new(0.15, 0, 1, 0); loadBtn.Position = UDim2.new(0.67, 0, 0, 0); loadBtn.BackgroundColor3 = THEME.Accent; loadBtn.Text = "??"; loadBtn.TextColor3 = THEME.Text; createRound(loadBtn, 8)
                                        saveBtn = Instance.new("TextButton", inputRow); saveBtn.Size = UDim2.new(0.15, 0, 1, 0); saveBtn.Position = UDim2.new(0.84, 0, 0, 0); saveBtn.BackgroundColor3 = Color3.fromRGB(60,60,60); saveBtn.Text = "??"; saveBtn.TextColor3 = THEME.Text; createRound(saveBtn, 8)
 
                                        local ctrlRow = Instance.new("Frame", contentFrame); ctrlRow.Size = UDim2.new(1, 0, 0, 45); ctrlRow.Position = UDim2.new(0, 0, 0, 210); ctrlRow.BackgroundTransparency = 1
                                        local ctrlLayout = Instance.new("UIListLayout", ctrlRow); ctrlLayout.FillDirection = Enum.FillDirection.Horizontal; ctrlLayout.Padding = UDim.new(0, 10); ctrlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                                        local function createCtrlBtn(text, color) local b = Instance.new("TextButton", ctrlRow); b.Size = UDim2.new(0, 60, 1, 0); b.BackgroundColor3 = color or Color3.fromRGB(50,50,50); b.Text = text; b.TextColor3 = THEME.Text; b.Font = Enum.Font.GothamBold; b.TextSize = 20; createRound(b, 10); return b end
                                        
                                        resumeBtn = createCtrlBtn("?", THEME.Green)
                                        pauseBtn = createCtrlBtn("?", THEME.Yellow)
                                        stopBtn = createCtrlBtn("?", THEME.Red)
                                        loopBtn = createCtrlBtn("??", Color3.fromRGB(80,80,200))
                                        
                                        local lowerRow = Instance.new("Frame", contentFrame); lowerRow.Size = UDim2.new(1, 0, 0, 30); lowerRow.Position = UDim2.new(0, 0, 0, 270); lowerRow.BackgroundTransparency = 1
                                        volBox = Instance.new("TextBox", lowerRow); volBox.Size = UDim2.new(0.3, 0, 1, 0); volBox.BackgroundColor3 = Color3.fromRGB(40,40,40); volBox.Text = "0.5"; volBox.PlaceholderText = "Vol"; volBox.TextColor3 = THEME.Text; createRound(volBox, 6)
                                        pitchBox = Instance.new("TextBox", lowerRow); pitchBox.Size = UDim2.new(0.3, 0, 1, 0); pitchBox.Position = UDim2.new(0.35, 0, 0, 0); pitchBox.BackgroundColor3 = Color3.fromRGB(40,40,40); pitchBox.Text = "1"; pitchBox.PlaceholderText = "Pitch"; pitchBox.TextColor3 = THEME.Text; createRound(pitchBox, 6)
                                        mountBtn = Instance.new("TextButton", lowerRow); mountBtn.Size = UDim2.new(0.3, 0, 1, 0); mountBtn.Position = UDim2.new(0.7, 0, 0, 0); mountBtn.BackgroundColor3 = Color3.fromRGB(60,60,60); mountBtn.Text = "Mount"; mountBtn.TextColor3 = THEME.Text; createRound(mountBtn, 6)
 
                                        local plFrame = Instance.new("Frame", contentFrame); plFrame.Size = UDim2.new(1, 0, 0, 110); plFrame.Position = UDim2.new(0, 0, 0, 310); plFrame.BackgroundColor3 = Color3.fromRGB(0,0,0); plFrame.BackgroundTransparency = 0.6; createRound(plFrame, 8)
                                        
                                        playlistScroll = Instance.new("ScrollingFrame", plFrame)
                                        playlistScroll.Size = UDim2.new(1, -10, 1, -10)
                                        playlistScroll.Position = UDim2.new(0, 5, 0, 5)
                                        playlistScroll.BackgroundTransparency = 1
                                        playlistScroll.BorderSizePixel = 0
                                        playlistScroll.ScrollBarThickness = 4
                                        playlistScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y 
                                        playlistScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
                                        
                                        local plLayout = Instance.new("UIListLayout", playlistScroll); plLayout.Padding = UDim.new(0, 5)
                                        
                                        openBtn = Instance.new("TextButton", gui); openBtn.Size = UDim2.new(0, 120, 0, 40); openBtn.Position = UDim2.new(0.5, -60, 0.9, -50); openBtn.BackgroundColor3 = THEME.Accent; openBtn.Text = "Open Radio"; openBtn.TextColor3 = THEME.Text; openBtn.Visible = false; createRound(openBtn, 20)
 
                                        gui.Parent = player:WaitForChild("PlayerGui")
                                        
                                        trafficRed.MouseButton1Click:Connect(function() mainFrame.Visible = false; openBtn.Visible = true end)
                                            openBtn.MouseButton1Click:Connect(function() mainFrame.Visible = true; openBtn.Visible = false end)
                                                trafficYellow.MouseButton1Click:Connect(function()
                                                    isMinimized = not isMinimized
                                                    if isMinimized then mainFrame:TweenSize(UDim2.new(0, 320, 0, 30), "Out", "Quad", 0.3, true); contentFrame.Visible = false
                                                    else mainFrame:TweenSize(UDim2.new(0, 320, 0, 450), "Out", "Quad", 0.3, true); contentFrame.Visible = true end
                                                    end)
                                                        trafficGreen.MouseButton1Click:Connect(function() local locked = mainFrame:GetAttribute("Locked"); mainFrame:SetAttribute("Locked", not locked); trafficGreen.Text = locked and "" or "??" end)
                                                            loadBtn.MouseButton1Click:Connect(loadBtnLink)
                                                            
                                                            local function triggerCooldown() isActionCooldown = true; task.delay(COOLDOWN_TIME, function() isActionCooldown = false end) end
                                                            resumeBtn.MouseButton1Click:Connect(function() if isActionCooldown then return end; local s = getSound(); if s then s.TimePosition = math.min(s.TimePosition + 0.5, s.TimeLength); s:Play() end; dataFunc:InvokeServer({Action = "Play"}); triggerCooldown() end)
                                                                pauseBtn.MouseButton1Click:Connect(function() if isActionCooldown then return end; dataFunc:InvokeServer({Action = "Pause"}); triggerCooldown() end)
                                                                    stopBtn.MouseButton1Click:Connect(function() dataFunc:InvokeServer({Action = "Stop"}) end)
                                                                        loopBtn.MouseButton1Click:Connect(function() local r = dataFunc:InvokeServer({Action = "Loop"}); if r.Success then loopBtn.BackgroundColor3 = r.IsLooping and THEME.Accent or Color3.fromRGB(80,80,200) end end)
                                                                            mountBtn.MouseButton1Click:Connect(function() dataFunc:InvokeServer({Action = "Mount"}) end)
                                                                                saveBtn.MouseButton1Click:Connect(function() if idBox.Text ~= "" and currentSongName ~= "Ready" then local r = dataFunc:InvokeServer({Action="SaveSong", Id=idBox.Text, Name=currentSongName}); if r.Success then showNotification("Saved!", THEME.Green); loadPlaylist() elseif r.Reason == "Duplicate" then showNotification("Already Saved", THEME.Yellow) else showNotification("Error Saving", THEME.Red) end end end)
                                                                                    volBox.FocusLost:Connect(function() local v = tonumber(volBox.Text); if v then dataFunc:InvokeServer({Action="Volume", Value=v}) end end)
                                                                                        pitchBox.FocusLost:Connect(function() local p = tonumber(pitchBox.Text); if p then dataFunc:InvokeServer({Action="Pitch", Value=p}) end end)
                                                                                            loadPlaylist()
                                                                                            
                                                                                            local function updateTimelineInput(input)
                                                                                                local sound = getSound()
                                                                                                if not sound or sound.TimeLength <= 0 then return end
                                                                                                local bgAbsPos = timelineBG.AbsolutePosition; local bgAbsSize = timelineBG.AbsoluteSize
                                                                                                local relativeX = input.Position.X - bgAbsPos.X
                                                                                                local percent = math.clamp(relativeX / bgAbsSize.X, 0, 1)
                                                                                                timelineFill.Size = UDim2.new(percent, 0, 1, 0)
                                                                                                timelineKnob.Position = UDim2.new(percent, 0, 0.5, 0)
                                                                                                return percent * sound.TimeLength
                                                                                            end
                                                                                            timelineBG.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDraggingTimeline = true; updateTimelineInput(input) end end)
                                                                                                userInputService.InputChanged:Connect(function(input) if isDraggingTimeline and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateTimelineInput(input) end end)
                                                                                                    userInputService.InputEnded:Connect(function(input) if isDraggingTimeline and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then isDraggingTimeline = false; local seekTime = updateTimelineInput(input); if seekTime then dataFunc:InvokeServer({Action = "Seek", Value = seekTime}) end end end)
 
                                                                                                        local function checkScreenSize()
                                                                                                            local vp = camera.ViewportSize
                                                                                                            if vp.Y < 500 then uiScale.Scale = math.clamp(vp.Y / 700, 0.55, 0.8) 
                                                                                                            else uiScale.Scale = math.clamp(vp.Y / 900, 0.9, 1.1) end
                                                                                                            end
                                                                                                                checkScreenSize()
                                                                                                                camera:GetPropertyChangedSignal("ViewportSize"):Connect(checkScreenSize)
                                                                                                            end
 
                                                                                                            function loadBtnLink()
                                                                                                                if isLoading then return end
                                                                                                                isLoading = true
                                                                                                                local sound = getSound()
                                                                                                                if sound and sound.SoundId ~= "" and lastWorkingId == "" then if sound.TimeLength > 0 then lastWorkingId = string.match(sound.SoundId, "%d+"); lastWorkingTime = sound.TimePosition end elseif sound and sound.TimeLength > 0 then lastWorkingTime = sound.TimePosition end
                                                                                                                showNotification("Loading...", THEME.Accent)
                                                                                                                local targetId = idBox.Text
                                                                                                                local success, result = pcall(function() return dataFunc:InvokeServer({Action = "AudioId", Value = targetId}) end)
                                                                                                                    if success and result.Success then
                                                                                                                        task.spawn(function()
                                                                                                                            local waitTime = 0
                                                                                                                            while waitTime < 8 do if getSound().TimeLength > 0 then break end; waitTime = waitTime + 0.1; task.wait(0.1) end
                                                                                                                            isLoading = false
                                                                                                                            local newSound = getSound()
                                                                                                                            if newSound and newSound.TimeLength > 0 then lastWorkingId = targetId; local state = dataFunc:InvokeServer({Action = "GetState"}); if state then syncAudio(state) end; showNotification("Playing", THEME.Green)
                                                                                                                            else showNotification("Failed! Reverting...", THEME.Red); if lastWorkingId ~= "" then dataFunc:InvokeServer({Action = "AudioId", Value = lastWorkingId, Time = lastWorkingTime}) end end
                                                                                                                            end)
                                                                                                                            else isLoading = false; showNotification("Invalid ID", THEME.Red) end
                                                                                                                            end
 
                                                                                                                                replication.OnClientEvent:Connect(function(newState) syncAudio(newState) end)
 
	                                                                                                                                    runService.RenderStepped:Connect(function(step)
	                                                                                                                                        pcall(function()
	                                                                                                                                            local sound = getSound()
	                                                                                                                                            if not mainFrame.Visible then return end
	                                                                                                                                            timeOffset = timeOffset + (step * 2)

	                                                                                                                                            if sound and sound.IsPlaying then
	                                                                                                                                                local centerIndex = (#vizBars + 1) / 2
	                                                                                                                                                local loudness = math.clamp(sound.PlaybackLoudness / 1200, 0, 1)
	                                                                                                                                                for i, bar in ipairs(vizBars) do
	                                                                                                                                                    local distanceFromCenter = math.abs(i - centerIndex)
	                                                                                                                                                    local normalizedDistance = distanceFromCenter / centerIndex
	                                                                                                                                                    local bellCurve = math.exp(-(normalizedDistance * normalizedDistance) / 0.2)
	                                                                                                                                                    local idleWave = (math.sin((timeOffset * 2.4) + (i * 0.55)) + 1) * 0.5
	                                                                                                                                                    local targetHeight = math.clamp(4 + (loudness * 42 * bellCurve) + (idleWave * 4 * (1 - normalizedDistance)), 4, 50)
	                                                                                                                                                    bar.Size = bar.Size:Lerp(UDim2.new(0, 8, 0, targetHeight), 0.2)
	                                                                                                                                                end
	                                                                                                                                            else
	                                                                                                                                                for i, bar in ipairs(vizBars) do
	                                                                                                                                                    local centerIndex = (#vizBars + 1) / 2
	                                                                                                                                                    local distanceFromCenter = math.abs(i - centerIndex)
	                                                                                                                                                    local normalizedDistance = distanceFromCenter / centerIndex
	                                                                                                                                                    local idleWave = (math.sin((timeOffset * 1.8) + (i * 0.45)) + 1) * 0.5
	                                                                                                                                                    local targetHeight = 4 + (idleWave * 2.5 * (1 - normalizedDistance))
	                                                                                                                                                    bar.Size = bar.Size:Lerp(UDim2.new(0, 8, 0, targetHeight), 0.2)
	                                                                                                                                                end
	                                                                                                                                            end

	                                                                                                                                            -- [ACTIVE SYNC CHECK]
	                                                                                                                                            if globalState.IsPlaying and sound and sound.IsPlaying and sound.TimeLength > 0 and sound.IsLoaded then
	                                                                                                                                                local timePassed = workspace:GetServerTimeNow() - globalState.LastUpdateTimestamp
	                                                                                                                                                local expectedTime = globalState.StartPosition + timePassed
	                                                                                                                                                if sound.Looped then expectedTime = expectedTime % sound.TimeLength else expectedTime = math.clamp(expectedTime, 0, sound.TimeLength) end
	                                                                                                                                                
	                                                                                                                                                if math.abs(sound.TimePosition - expectedTime) > 0.8 then
	                                                                                                                                                    sound.TimePosition = expectedTime
	                                                                                                                                                end
	                                                                                                                                            end

	                                                                                                                                            if sound and sound.TimeLength > 0 then
	                                                                                                                                                timeLabelLeft.Text = formatTime(sound.TimePosition)
	                                                                                                                                                timeLabelRight.Text = formatTime(sound.TimeLength)
	                                                                                                                                                if not isDraggingTimeline then
	                                                                                                                                                    local pct = math.clamp(sound.TimePosition / sound.TimeLength, 0, 1)
	                                                                                                                                                    timelineFill.Size = timelineFill.Size:Lerp(UDim2.new(pct, 0, 1, 0), 0.3)
	                                                                                                                                                    timelineKnob.Position = timelineKnob.Position:Lerp(UDim2.new(pct, 0, 0.5, 0), 0.3)
	                                                                                                                                                end
	                                                                                                                                            end
	                                                                                                                                            if scrollingMusicLabel then local textWidth = scrollingMusicLabel.TextBounds.X; local containerWidth = 280; if textWidth > containerWidth then scrollOffset = scrollOffset - (step * 40); if scrollOffset < -(textWidth + 30) then scrollOffset = containerWidth end; scrollingMusicLabel.Position = UDim2.new(0, scrollOffset, 0, 0) else scrollingMusicLabel.Position = UDim2.new(0, 0, 0, 0) end end
	                                                                                                                                        end)
	                                                                                                                                    end)
 
                                                                                                                                    tool.Equipped:Connect(function() if not gui then createGui() end; gui.Parent = player:WaitForChild("PlayerGui"); local state = dataFunc:InvokeServer({Action = "GetState"}); if state and state.Success then syncAudio(state) end end)
                                                                                                                                        tool.Unequipped:Connect(function() if gui then gui.Parent = nil end end)

