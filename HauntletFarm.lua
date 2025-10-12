--[[
    Roblox Lua Script (Executor/Exploit Context)
    
    This script is divided into three main phases:
    1. Initial Module Teleport: Uses game modules (InteriorsM, UIManager) to safely teleport the player 
       to the specified 'MainMap' CFrame upon script execution.
    2. Intermediate Static Teleport: Teleports the player to the specific Hauntlet Minigame Join Zone 
       ring to ensure the correct starting location, now with a 5-second countdown.
    3. Continuous Loop: After all initial teleports are confirmed, it starts persistently searching for 
       'TeleportRing' parts inside 'HauntletInterior::...' models and teleports the player to them in sequence.
    
    The entire process is wrapped in a main loop to handle models disappearing and reappearing.
]]

-- Configuration
local SCRIPT_ENABLED = true -- TOGGLE: Set to false to disable the entire script.

local TELEPORT_DELAY = 0.2 -- Time in seconds to pause after each teleport (also hold time for 'stickiness')
local SEARCH_INTERVAL = 3 -- Time in seconds to wait between search attempts
local MARKER_SIZE = Vector3.new(3, 3, 3)
local MARKER_COLOR = BrickColor.new("Really red")
local TELEPORT_OFFSET_Y = 1  -- Reduced to 1 stud above the ring for a smooth, sticky landing

-- Core Roblox services and objects
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = game.Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")

local currentTeleportIndex = 0

-- 1. Identify the search root as 'workspace.Interiors'
local interiorsRoot = game.Workspace:FindFirstChild("Interiors")

-- UI Element
local statusLabel = nil

--------------------------------------------------------------------------------
-- UI FUNCTIONS
--------------------------------------------------------------------------------

-- Function to create the status UI (Increased size to 600 wide)
local function createStatusUI()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TeleportStatusUI"
    screenGui.Parent = playerGui
    
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "TeleportCounter"
    statusLabel.Size = UDim2.new(0, 600, 0, 40) -- Increased width to 600
    statusLabel.Position = UDim2.new({0.513, -300},{0.126, 10}) -- Centered
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.BackgroundTransparency = 0.3
    statusLabel.BorderSizePixel = 0
    statusLabel.Text = "Teleport System Initialized..."
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 18
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.TextYAlignment = Enum.TextYAlignment.Center
    statusLabel.Parent = screenGui
end

-- Function to update the status UI text
local function updateStatus(text)
    if statusLabel then
        statusLabel.Text = text
    end
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
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
-- CORE EXECUTION BLOCK
--------------------------------------------------------------------------------

if SCRIPT_ENABLED then

    --------------------------------------------------------------------------------
    -- INITIAL MAINMAP TELEPORT SETUP (Phase 1)
    --------------------------------------------------------------------------------

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
        warn("The game structure may have changed. Cannot proceed with automatic teleport.")
        return
    end

    local successUIManager, errorMessageUIManager = pcall(function()
        UIManager = require(ReplicatedStorage:WaitForChild("Fsys")).load("UIManager")
    end)

    if not successUIManager or not UIManager then
        warn("Failed to require UIManager module:", errorMessageUIManager)
    end

    print("InteriorsM module loaded successfully. Proceeding with automatic teleport setup.")


    -- Create the UI right away
    createStatusUI()
    updateStatus("Initial Teleporting to MainMap...")

    local destinationId = "MainMap"
    local doorIdForTeleport = "MainDoor" 

    local teleportSettings = {
        house_owner = localPlayer; 
        spawn_cframe = spawn_cframe; 
        
        -- Removed the unreliable teleport_completed_callback
        -- Relying on a fixed wait instead for robust execution
        anchor_char_immediately = true,
        post_character_anchored_wait = 0.5,
        move_camera = true,
    }

    local waitBeforeTeleport = 5 
    print(string.format("\nWaiting %d seconds for game stability before initial teleport...", waitBeforeTeleport))
    task.wait(waitBeforeTeleport)

    print("\n--- Initiating Direct Teleport to MainMap ---")
    InteriorsM.enter_smooth(destinationId, doorIdForTeleport, teleportSettings, nil)

    -- NEW STRATEGY: Wait a generous amount of time for the map to load after the teleport call
    local postTeleportWait = 10 
    -- UPDATED STATUS MESSAGE HERE: Removed "Module"
    updateStatus(string.format("Teleporting to MainMap. Waiting %d seconds for map to load...", postTeleportWait))
    task.wait(postTeleportWait)


    --------------------------------------------------------------------------------
    -- INTERMEDIATE STATIC TELEPORT (Phase 2)
    --------------------------------------------------------------------------------

    local function intermediateTeleportToRing()
        local ringTarget = nil
        local interiorsFolder = game.Workspace:FindFirstChild("Interiors")

        if interiorsFolder then
            -- PHASE 2 PERSISTENCE LOOP: Wait and search for the target until it appears
            print("Starting persistent search for HauntletMinigameJoinZone...")

            local maxAttempts = 20 -- Try for up to 20 seconds (20 * 1 second waits)
            local attempt = 0

            repeat
                attempt = attempt + 1
                -- Update status immediately before attempting to find the target
                updateStatus(string.format("Searching for Hauntlet Minigame Join Zone... (Attempt %d/%d)", attempt, maxAttempts))

                -- Attempt to find the specific structure
                local minigameRingParent = interiorsFolder:FindFirstChild("MainMap!Fall", true)
                
                if minigameRingParent then
                    local joinZone = minigameRingParent:FindFirstChild("HauntletMinigameJoinZone", true)
                    if joinZone then
                        ringTarget = joinZone:FindFirstChild("Ring", true)
                    end
                end

                if not ringTarget then
                    task.wait(1) -- Wait 1 second before checking again
                end
            until ringTarget or attempt >= maxAttempts or not localPlayer.Parent

        end

        if ringTarget and ringTarget:IsA("BasePart") then
            print("Found Minigame Join Zone Ring. Starting 5-second countdown.")
            
            -- IMMEDIATE STATUS UPDATE BEFORE COUNTDOWN
            updateStatus("Found Minigame Join Zone Ring. Teleporting in 5 seconds...")

            -- 5-SECOND COUNTDOWN LOOP
            local countdownTime = 5
            for i = countdownTime, 1, -1 do
                -- Update status for each second of the countdown
                updateStatus(string.format("Teleporting to Minigame Join Zone in... %d seconds", i))
                wait(1)
            end
            
            updateStatus("Teleporting to Minigame Join Zone Ring NOW...")
            
            -- Teleportation Safety/Stickiness
            rootPart.Anchored = true
            rootPart.CFrame = ringTarget.CFrame * CFrame.new(0, TELEPORT_OFFSET_Y, 0)
            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            wait(TELEPORT_DELAY) 
            rootPart.Anchored = false
            
            print("Intermediate teleport complete. Starting continuous search loop.")
            updateStatus("Teleport to Join Zone complete. Starting continuous search.")
            wait(1) -- Small pause before starting main loop
        else
            warn("Failed to find Minigame Join Zone Ring after persistent search. Starting persistent door search directly.")
            updateStatus("Join Zone not found. Starting persistent search...")
            wait(2)
        end
    end

    -- Execute Phase 2
    intermediateTeleportToRing()

    --------------------------------------------------------------------------------
    -- CONTINUOUS TELEPORT LOOP (Phase 3)
    --------------------------------------------------------------------------------

    -- Check if the primary container exists
    if not interiorsRoot then
        print("Error: Could not find 'Interiors' folder directly under game.Workspace.")
        print("Please verify the folder name and location.")
        -- Script stops here if Interiors is missing
        return
    end

    -- MAIN CONTINUOUS LOOP
    while true do
        -- Reset targets for the new search cycle
        local teleportTargets = {}
        local roomModels = {}
        
        -- 2. Persistent Search Loop for Room Models
        while #roomModels == 0 do
            updateStatus("Searching for Hauntlet Minigame...")
            print("Searching for Hauntlet Minigame...")
            
            roomModels = {}
            
            -- Find all 'HauntletInterior::...' models
            for _, object in pairs(interiorsRoot:GetChildren()) do
                if string.match(object.Name, "^HauntletInterior::") and object:IsA("Model") then
                    table.insert(roomModels, object)
                end
            end
            
            if #roomModels == 0 then
                -- If none found, wait and try again
                wait(SEARCH_INTERVAL)
            end
        end

        -- Once roomModels are found, proceed with finding targets
        print(string.format("Found %d HauntletInterior Room Models. Starting target scan.", #roomModels))

        -- Now, search within these models for the actual teleport rings
        for _, roomModel in ipairs(roomModels) do
            for _, object in pairs(roomModel:GetDescendants()) do
                -- Check if the object's name contains "teleport" (case-insensitive)
                if string.match(string.lower(object.Name), "teleport") then
                    
                    -- And check if it's a part or a model that contains a part
                    if object:IsA("BasePart") or object:IsA("Model") then
                        local physicalPart = getPhysicalPart(object)
                        
                        if physicalPart then
                            -- Store the physical part AND the room model it belongs to
                            table.insert(teleportTargets, {
                                part = physicalPart,
                                roomModel = roomModel -- Store the parent room model
                            })
                            print("Found target part: " .. physicalPart:GetFullName())
                        end
                    end
                end
            end
        end

        local totalTargets = #teleportTargets
        updateStatus(string.format("Found %d total teleport targets. Starting sequence...", totalTargets))
        print(string.format("Found %d eligible teleport targets.", totalTargets))

        -- 3. Teleport to each target and update UI
        if totalTargets > 0 then
            for i, targetData in ipairs(teleportTargets) do
                local ring = targetData.part
                local roomModel = targetData.roomModel
                currentTeleportIndex = i
                
                -- Prepare the UI text
                local doorHitName = ring.Name -- The name of the TeleportRing part/model
                
                -- Clean up the room name for UI display
                local roomName = string.match(roomModel.Name, "^(HauntletInterior::[^:]+)") 
                    or "Unknown Room" 

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
                
                print(string.format("Teleporting to Target #%d...", i))
                
                -- SAFETY STEP 1: Anchor HRP for stability
                rootPart.Anchored = true
                
                -- Teleport the player's HumanoidRootPart
                rootPart.CFrame = ring.CFrame * CFrame.new(0, TELEPORT_OFFSET_Y, 0)
                
                -- SAFETY STEP 2: Reset velocities to stop motion instantly
                rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                
                -- STICKINESS STEP: Wait briefly while anchored, ensuring the character stays put
                wait(TELEPORT_DELAY) 
                
                -- SAFETY STEP 3: Unanchor HRP
                rootPart.Anchored = false
                
                -- Clean up the marker right away to prevent clutter
                marker:Destroy()
            end
            updateStatus(string.format("Teleport sequence complete! Hit all %d targets. Restarting search...", totalTargets))
            wait(SEARCH_INTERVAL) -- Pause briefly before restarting the entire loop
        else
            updateStatus("Error: Found 0 teleport targets. Restarting search...")
            wait(SEARCH_INTERVAL) -- Pause before restarting the entire loop
        end
    end
else
    -- Script is disabled
    createStatusUI()
    updateStatus("Script is currently DISABLED (SCRIPT_ENABLED = false). Change the variable to true to run.")
end
