-- Configuration
local SCRIPT_ENABLED_DEFAULT = true -- The default initial state
local IS_RUNNING = SCRIPT_ENABLED_DEFAULT -- TOGGLE: Global variable to control the main loop

local TELEPORT_DELAY = 0.2 -- Time in seconds to pause after each teleport (also hold time for 'stickiness')
local SEARCH_INTERVAL = 3 -- Time in seconds to wait between search attempts
local MARKER_SIZE = Vector3.new(3, 3, 3)
local MARKER_COLOR = BrickColor.new("Really red")
local TELEPORT_OFFSET_Y = 1 -- Reduced to 1 stud above the ring for a smooth, sticky landing

-- Core Roblox services and objects
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = game.Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")

local currentTeleportIndex = 0

-- 1. Identify the search root as 'workspace.Interiors'
local interiorsRoot = game.Workspace:FindFirstChild("Interiors")

-- UI Element Holders
local statusLabel = nil
local toggleButton = nil
local screenGui = nil -- Store the main ScreenGui

--------------------------------------------------------------------------------
-- 🎮 UI Control Functions
--------------------------------------------------------------------------------

-- Function to update the status UI text
local function updateStatus(text)
    if statusLabel then
        statusLabel.Text = text
    end
end

-- Function to update the toggle button's appearance
local function updateToggleButton()
    if toggleButton then
        if IS_RUNNING then
            toggleButton.Text = "TELEPORT: ON"
            toggleButton.BackgroundColor3 = Color3.new(0, 1, 0) -- Green
            updateStatus("Teleport System is **ON**. Waiting for targets...")
        else
            toggleButton.Text = "TELEPORT: OFF"
            toggleButton.BackgroundColor3 = Color3.new(1, 0, 0) -- Red
            updateStatus("Teleport System is **OFF**. Click ON to start.")
        end
    end
end

-- Function to handle the ON/OFF toggle
local function onToggleClicked()
    IS_RUNNING = not IS_RUNNING
    updateToggleButton()
end

-- Function to handle the Close Button click
local function onCloseClicked()
    -- Destroy the main UI element, which removes all children (statusLabel, buttons)
    if screenGui then
        IS_RUNNING = false -- Stop the loop just in case it's running
        screenGui:Destroy()
        warn("Teleport System UI destroyed.")
    end
end

-- Function to create the full UI (Status, Toggle, Close)
local function createFullUI()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    -- Main ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TeleportControlUI"
    screenGui.Parent = playerGui

    -- UI Container Frame (Holds the status label and control buttons)
    local controlFrame = Instance.new("Frame")
    controlFrame.Name = "ControlPanel"
    controlFrame.Size = UDim2.new(0, 600, 0, 80) -- Increased height to 80 for buttons
    controlFrame.Position = UDim2.new(0.5, -300, 0, 80) -- Centered, moved down to 80 pixels from top
    controlFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    controlFrame.BackgroundTransparency = 0.1
    controlFrame.BorderSizePixel = 0
    controlFrame.Parent = screenGui

    -- Status Text Label (Top part of the frame)
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "TeleportCounter"
    statusLabel.Size = UDim2.new(1, 0, 0, 30) -- Full width, 30 height
    statusLabel.Position = UDim2.new(0, 0, 0, 0)
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.BackgroundTransparency = 0.3
    statusLabel.BorderSizePixel = 0
    statusLabel.Text = "Initializing Teleport System..."
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 18
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.TextYAlignment = Enum.TextYAlignment.Center
    statusLabel.Parent = controlFrame

    -- Toggle Button (Left side)
    toggleButton = Instance.new("TextButton")
    toggleButton.Name = "ToggleButton"
    toggleButton.Size = UDim2.new(0.7, -10, 0, 40) -- 70% width, leaving space for the close button
    toggleButton.Position = UDim2.new(0, 5, 0, 35) -- 5 pixels from left, below status
    toggleButton.BackgroundColor3 = Color3.new(1, 1, 1)
    toggleButton.Text = "TELEPORT: OFF/ON"
    toggleButton.TextColor3 = Color3.new(0, 0, 0)
    toggleButton.Font = Enum.Font.SourceSansBold
    toggleButton.TextSize = 20
    toggleButton.Parent = controlFrame
    toggleButton.MouseButton1Click:Connect(onToggleClicked)

    -- Close Button (Right side)
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0.3, -5, 0, 40) -- 30% width
    closeButton.Position = UDim2.new(0.7, 5, 0, 35) -- Starts at 70% + 5 pixels
    closeButton.BackgroundColor3 = Color3.new(1, 0, 0) -- BRIGHT RED (Changed here)
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Font = Enum.Font.SourceSansBold
    closeButton.TextSize = 24
    closeButton.Parent = controlFrame
    closeButton.MouseButton1Click:Connect(onCloseClicked)

    -- Initial state update
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
    IS_RUNNING = false -- Disable the script if core module is missing
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
    if not InteriorsM then return end -- Don't run if module load failed

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
            if not IS_RUNNING then return end -- Check for toggle
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
            if not IS_RUNNING then return end -- Check for toggle
            updateStatus(string.format("Teleporting to Join Zone in... %d seconds", i))
            wait(1)
        end
        
        if not IS_RUNNING then return end -- Final check

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
    while #roomModels == 0 do
        if not IS_RUNNING then break end -- Check for toggle
        updateStatus("Searching for Hauntlet Minigame...")
        
        roomModels = {}
        
        for _, object in pairs(interiorsRoot:GetChildren()) do
            if string.match(object.Name, "^HauntletInterior::") and object:IsA("Model") then
                table.insert(roomModels, object)
            end
        end
        
        if #roomModels == 0 then
            wait(SEARCH_INTERVAL)
        end
    end
    
    if not IS_RUNNING then continue end -- Restart loop if turned off during search

    print(string.format("Found %d HauntletInterior Room Models. Starting target scan.", #roomModels))

    -- Now, search within these models for the actual teleport rings
    for _, roomModel in ipairs(roomModels) do
        if not IS_RUNNING then break end -- Check for toggle
        for _, object in pairs(roomModel:GetDescendants()) do
            if not IS_RUNNING then break end -- Check for toggle
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
    
    if not IS_RUNNING then continue end -- Restart loop if turned off during target scan

    local totalTargets = #teleportTargets
    updateStatus(string.format("Found %d total teleport targets. Starting sequence...", totalTargets))

    -- 3. Teleport to each target and update UI
    if totalTargets > 0 then
        for i, targetData in ipairs(teleportTargets) do
            if not IS_RUNNING then break end -- Check for toggle
            
            local ring = targetData.part
            local roomModel = targetData.roomModel
            currentTeleportIndex = i
            
            local doorHitName = ring.Name
            local roomName = string.match(roomModel.Name, "^(HauntletInterior::[^:]+)") or "Unknown Room"

            local statusText = string.format("Teleporting: %d/%d | DoorHit: %s | Room: %s", 
                currentTeleportIndex, totalTargets, doorHitName, roomName)
            updateStatus(statusText)

            -- Create and position the marker cube
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

            -- Perform Teleportation
            rootPart.Anchored = true
            rootPart.CFrame = ring.CFrame * CFrame.new(0, TELEPORT_OFFSET_Y, 0)
            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            wait(TELEPORT_DELAY) 
            rootPart.Anchored = false

            marker:Destroy()
        end
        
        if IS_RUNNING then -- Only update status and wait if the script is still ON
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
