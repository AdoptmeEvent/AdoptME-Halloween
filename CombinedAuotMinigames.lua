
-- Configuration
local SCRIPT_ENABLED_DEFAULT = true -- The default initial state
local IS_RUNNING = SCRIPT_ENABLED_DEFAULT -- Global variable to control the main loop

local TELEPORT_DELAY = 0.2 -- Time in seconds to pause after each teleport (for 'stickiness')
local SEARCH_INTERVAL = 3 -- Time in seconds to wait between search attempts
local MARKER_SIZE = Vector3.new(3, 3, 3)
local MARKER_COLOR = BrickColor.new("Really red")
local TELEPORT_OFFSET_Y = 1 -- Studs above the ring to teleport to for a smooth landing

-- Core Roblox services and objects
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")

local currentTeleportIndex = 0

-- 1. Identify the search root as 'workspace.Interiors'
local interiorsRoot = game.Workspace:FindFirstChild("Interiors")

-- UI Element Holders (Global references for updating)
local statusLabel = nil -- Used to display the current state/progress
local toggleButton = nil -- Used to turn the main script ON/OFF
local screenGui = nil
local frame = nil -- Reference to the main draggable frame

--------------------------------------------------------------------------------
-- 🎮 UI Control Functions
--------------------------------------------------------------------------------

-- Function to update the status UI text
local function updateStatus(text)
    if statusLabel then
        statusLabel.Text = text
    end
end

-- Function to update the main toggle button's appearance
local function updateToggleButton()
    if toggleButton then
        if IS_RUNNING then
            toggleButton.Text = "FARMING: ON (HAUNTLET)"
            toggleButton.BackgroundColor3 = Color3.fromRGB(0, 180, 0) -- Green
            updateStatus("Teleport System is **ON**. Searching for Hauntlet targets...")
        else
            toggleButton.Text = "FARMING: OFF"
            toggleButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0) -- Red
            updateStatus("Teleport System is **OFF**. Click ON to start Hauntlet farm.")
        end
    end
end

-- Function to handle the ON/OFF toggle
local function onToggleClicked()
    IS_RUNNING = not IS_RUNNING
    updateToggleButton()
end

-- Function to create the full UI
local function createFullUI()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    if screenGui and screenGui.Parent then return end

    -- 1. Setup ScreenGui container
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HauntletFarmUI"
    screenGui.Parent = playerGui

    -- 2. Main Frame setup
    frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.new(0.3, 0, 0.35, 0) -- Adjusted size for single toggle
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Parent = screenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 12)
    frameCorner.Parent = frame

    -- 3. Title Frame (Used for dragging)
    local titleFrame = Instance.new("Frame")
    titleFrame.Name = "TitleBar"
    titleFrame.Size = UDim2.new(1, 0, 0.2, 0) 
    titleFrame.Position = UDim2.new(0, 0, 0, 0)
    titleFrame.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
    titleFrame.BorderSizePixel = 0
    titleFrame.Parent = frame

    -- Title Label
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(0.9, 0, 1, 0)
    titleLabel.Position = UDim2.new(0.05, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.Text = "Hauntlet Autofarm Controller"
    titleLabel.TextSize = 20
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleFrame

    -- Close Button (X)
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0.08, 0, 0.6, 0)
    closeButton.Position = UDim2.new(0.95, 0, 0.5, 0)
    closeButton.AnchorPoint = Vector2.new(1, 0.5)
    closeButton.Text = "X"
    closeButton.Font = Enum.Font.SourceSansBold
    closeButton.TextSize = 18
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    closeButton.BorderSizePixel = 0
    closeButton.Parent = titleFrame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 6)
    buttonCorner.Parent = closeButton

    closeButton.MouseButton1Click:Connect(function()
        if screenGui then
            IS_RUNNING = false
            screenGui:Destroy()
            screenGui = nil
        end
    end)
    
    -- 4. Content Container and Layout
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 0.8, 0)
    contentFrame.Position = UDim2.new(0, 0, 0.2, 0)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = contentFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Vertical
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 10)
    listLayout.Parent = contentFrame

    -- 5. Status Label (main info display)
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.LayoutOrder = 1
    statusLabel.Size = UDim2.new(1, 0, 0, 50)
    statusLabel.Text = "Initializing Teleport System..."
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 16
    statusLabel.TextWrapped = true
    statusLabel.Parent = contentFrame

    -- 6. Main Toggle Button (FARMING)
    toggleButton = Instance.new("TextButton")
    toggleButton.Name = "ToggleButton"
    toggleButton.LayoutOrder = 2
    toggleButton.Size = UDim2.new(1, 0, 0, 45)
    toggleButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0) -- Initial color (Red)
    toggleButton.Text = "FARMING: OFF"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.Font = Enum.Font.SourceSansBold
    toggleButton.TextSize = 22
    toggleButton.Parent = contentFrame
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 8)
    toggleCorner.Parent = toggleButton
    
    toggleButton.MouseButton1Click:Connect(onToggleClicked)
    
    -- 7. Dragging functionality (connected to Title Bar)
    local dragging = false
    local dragStart = Vector2.new(0, 0)
    local startPos = UDim2.new(0, 0, 0, 0)

    local function startDrag(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end

    local function updateDrag(input)
        if dragging then
            local delta = input.Position - dragStart
            local newX = startPos.X.Offset + delta.X
            local newY = startPos.Y.Offset + delta.Y
            frame.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
        end
    end

    local function endDrag()
        dragging = false
    end

    titleFrame.InputBegan:Connect(startDrag)
    UserInputService.InputChanged:Connect(updateDrag)
    UserInputService.InputEnded:Connect(endDrag)

    updateToggleButton()
end

--------------------------------------------------------------------------------
-- 🔨 Utility Functions
--------------------------------------------------------------------------------

-- Function to safely get the physical part from a target object
local function getPhysicalPart(targetObject)
    if targetObject:IsA("BasePart") then
        return targetObject
    elseif targetObject:IsA("Model") then
        local primaryPart = targetObject.PrimaryPart
        if primaryPart and primaryPart:IsA("BasePart") then
            return primaryPart
        end
        for _, descendant in pairs(targetObject:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- 🚀 Core Execution Block
--------------------------------------------------------------------------------

-- Create the full UI right away
createFullUI()

-- Hardcoded spawn CFrame for returning to the main map after a game or for setup
local spawn_cframe = CFrame.new(-275.9091491699219, 25.812084197998047, -1548.145751953125, -0.9798217415809631, 0.0000227206928684609, 0.19986890256404877, -0.000003862579433189239, 1, -0.00013261348067317158, -0.19986890256404877, -0.00013070966815575957, -0.9798217415809631)

local InteriorsM = nil
local UIManager = nil 

-- Attempt to require necessary modules.
local successInteriorsM, errorMessageInteriorsM = pcall(function()
    local ClientModules = ReplicatedStorage:WaitForChild("ClientModules")
    local Core = ClientModules:WaitForChild("Core")
    local InteriorsMContainer = Core:WaitForChild("InteriorsM")
    InteriorsM = require(InteriorsMContainer.InteriorsM)
end)

if not successInteriorsM then
    warn("Failed to require InteriorsM:", errorMessageInteriorsM)
    updateStatus("ERROR: Cannot load InteriorsM. Script halted.")
    IS_RUNNING = false
    updateToggleButton()
else
    print("InteriorsM module loaded successfully.")
end

local successUIManager, errorMessageUIManager = pcall(function()
    UIManager = require(ReplicatedStorage:WaitForChild("Fsys")).load("UIManager")
end)

if not successUIManager or not UIManager then
    warn("Failed to require UIManager module:", errorMessageUIManager)
end

---

local function initialTeleportSetup()
    if not InteriorsM then return end

    updateStatus("Initial Teleporting to MainMap...")

    local destinationId = "MainMap"
    local doorIdForTeleport = "MainDoor" 

    local teleportSettings = {
        house_owner = localPlayer; 
        spawn_cframe = spawn_cframe; 
        anchor_char_immediately = true,
        post_character_anchored_wait = 0.5,
        move_camera = true,
    }

    local waitBeforeTeleport = 5 
    print(string.format("\nWaiting %d seconds for game stability before initial teleport...", waitBeforeTeleport))
    updateStatus(string.format("Waiting %d seconds before initial MainMap teleport...", waitBeforeTeleport))
    task.wait(waitBeforeTeleport)

    print("\n--- Initiating Direct Teleport to MainMap ---")
    InteriorsM.enter_smooth(destinationId, doorIdForTeleport, teleportSettings, nil)

    local postTeleportWait = 10 
    updateStatus(string.format("Teleporting to MainMap. Waiting %d seconds for map to load...", postTeleportWait))
    task.wait(postTeleportWait)
end

---

local function intermediateTeleportToRing()
    if not InteriorsM then return end

    local ringTarget = nil
    local interiorsFolder = game.Workspace:FindFirstChild("Interiors")

    if interiorsFolder then
        print("Starting persistent search for HauntletMinigameJoinZone...")

        local maxAttempts = 20
        local attempt = 0

        repeat
            if not IS_RUNNING then return end
            attempt = attempt + 1
            updateStatus(string.format("Searching for Join Zone... (Attempt %d/%d)", attempt, maxAttempts))

            local minigameRingParent = interiorsFolder:FindFirstChild("MainMap!Fall", true)
            
            if minigameRingParent then
                local joinZone = minigameRingParent:FindFirstChild("HauntletMinigameJoinZone", true)
                if joinZone then
                    ringTarget = joinZone:FindFirstChild("Ring", true)
                end
            end

            if not ringTarget then
                task.wait(1)
            end
        until ringTarget or attempt >= maxAttempts or not localPlayer.Parent

    end

    if ringTarget and ringTarget:IsA("BasePart") then
        updateStatus("Found Minigame Join Zone Ring. Teleporting in 5 seconds...")

        local countdownTime = 5
        for i = countdownTime, 1, -1 do
            if not IS_RUNNING then return end
            updateStatus(string.format("Teleporting to Join Zone in... %d seconds", i))
            wait(1)
        end
        
        if not IS_RUNNING then return end

        updateStatus("Teleporting to Minigame Join Zone Ring NOW...")
        
        rootPart.Anchored = true
        rootPart.CFrame = ringTarget.CFrame * CFrame.new(0, TELEPORT_OFFSET_Y, 0)
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        wait(TELEPORT_DELAY) 
        rootPart.Anchored = false
        
        updateStatus("Teleport to Join Zone complete. Starting continuous search.")
        wait(1)
    else
        warn("Failed to find Minigame Join Zone Ring.")
        updateStatus("Join Zone not found. Starting persistent door search directly.")
        wait(2)
    end
end

---

-- Main script flow
if SCRIPT_ENABLED_DEFAULT then
    initialTeleportSetup()
    intermediateTeleportToRing()
end

-- MAIN CONTINUOUS LOOP
while true do
    -- **CRITICAL CHECK**: Only proceed if IS_RUNNING is true
    while not IS_RUNNING do
        updateStatus("Teleport System is OFF. Awaiting activation...")
        wait(1)
    end

    -- Check if the primary container exists
    if not interiorsRoot then
        print("Error: Could not find 'Interiors' folder.")
        updateStatus("ERROR: Missing 'Interiors' folder. Script halted.")
        IS_RUNNING = false
        updateToggleButton()
        break
    end

    local teleportTargets = {}
    local roomModels = {}
    
    -- 2. Persistent Search Loop for Room Models
    -- FIX APPLIED: Changed prefix from "HauntletInterior::" to the correct "Hauntlet::"
    local searchPrefix = "^Hauntlet::"
    local minigameName = "Hauntlet"

    while #roomModels == 0 do
        if not IS_RUNNING then break end
        updateStatus(string.format("Searching for %s Minigame...", minigameName))
        
        roomModels = {}
        
        for _, object in pairs(interiorsRoot:GetChildren()) do
            -- Look for models starting with the Hauntlet prefix
            if string.match(object.Name, searchPrefix) and object:IsA("Model") then
                table.insert(roomModels, object)
            end
        end
        
        if #roomModels == 0 then
            wait(SEARCH_INTERVAL)
        end
    end
    
    if not IS_RUNNING then continue end

    print(string.format("Found %d %s Room Models. Starting target scan.", #roomModels, minigameName))

    -- Now, search within these models for the actual teleport rings
    for _, roomModel in ipairs(roomModels) do
        if not IS_RUNNING then break end
        for _, object in pairs(roomModel:GetDescendants()) do
            if not IS_RUNNING then break end
            -- Find parts/models whose name contains "teleport" (case-insensitive)
            if string.match(string.lower(object.Name), "teleport") and (object:IsA("BasePart") or object:IsA("Model")) then
                local physicalPart = getPhysicalPart(object)
                if physicalPart then
                    table.insert(teleportTargets, {
                        part = physicalPart,
                        roomModel = roomModel
                    })
                end
            end
        end
    end
    
    if not IS_RUNNING then continue end

    local totalTargets = #teleportTargets
    updateStatus(string.format("Found %d total teleport targets. Starting sequence...", totalTargets))

    -- 3. Teleport to each target and update UI
    if totalTargets > 0 then
        for i, targetData in ipairs(teleportTargets) do
            if not IS_RUNNING then break end
            
            local ring = targetData.part
            local roomModel = targetData.roomModel
            currentTeleportIndex = i
            
            local doorHitName = ring.Name
            -- Extract the specific room name after the prefix (e.g., "Fall" from "Hauntlet::Fall")
            local roomName = string.match(roomModel.Name, searchPrefix .. "([^:]+)") or "Unknown Room"

            local statusText = string.format("Teleporting: %d/%d | DoorHit: %s | Room: %s", 
                currentTeleportIndex, totalTargets, doorHitName, roomName)
            updateStatus(statusText)

            -- Create and position the marker cube (for visual confirmation)
            local marker = Instance.new("Part")
            marker.Name = "TeleportMarker_" .. i
            marker.Size = MARKER_SIZE
            marker.CFrame = ring.CFrame
            marker.Anchored = true
            marker.CanCollide = false
            marker.BrickColor = MARKER_COLOR
            marker.Material = Enum.Material.Neon
            marker.Transparency = 0.2
            marker.Parent = game.Workspace

            -- Perform Teleportation (Anchoring is used for precise movement)
            rootPart.Anchored = true
            rootPart.CFrame = ring.CFrame * CFrame.new(0, TELEPORT_OFFSET_Y, 0)
            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            wait(TELEPORT_DELAY) 
            rootPart.Anchored = false

            marker:Destroy()
        end
        
        if IS_RUNNING then
            updateStatus(string.format("Teleport sequence complete! Hit all %d targets. Restarting search...", totalTargets))
            wait(SEARCH_INTERVAL)
        end
    else
        if IS_RUNNING then
            updateStatus("Error: Found 0 teleport targets. Restarting search...")
            wait(SEARCH_INTERVAL)
        end
    end
end



wait("2")

loadstring(game:HttpGet(('https://raw.githubusercontent.com/UnclesVan/ValentinesDay-2025/refs/heads/main/SleepOrTreat')))()



