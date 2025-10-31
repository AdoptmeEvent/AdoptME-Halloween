-- This script has been refactored to use only official Roblox Luau APIs.
-- All functions related to unauthorized event firing (getconnections, setcursorpos, mouse1click) have been removed.

-- CRITICAL FIX V7.4: FORCE START THE SCRIPT
-- If the external environment hasn't initialized the global flag, we assume the script should run.
_G.SOT_TELEPORTER_RUNNING = true

-- Initialize the global control flag for external toggling
if _G.SOT_TELEPORTER_RUNNING == nil then
    _G.SOT_TELEPORTER_RUNNING = false
end

-- Configuration
local TELEPORT_DELAY = 0.15 
local SEARCH_WAIT_TIME = 2.0 
local TIMER_STOP_VALUES = {"00:03"} -- CRITICAL FIX V8.6: Lowered stop time from 00:05 to 00:03 to allow pet click and mannequin cycle to run longer.
local TIMER_START_THRESHOLD = "00:29" -- UPDATED V6.7: Changed from 00:30 to 00:29 to allow the sequence to start when the timer is exactly 30 seconds.
local MANNEQUIN_TEST_TIME = 2.0 -- UPDATED: Reduced from 5.0 to 2.0 seconds per mannequin test.
local MAX_CLICK_RETRIES = 5
local PET_CLICK_RETRIES = 5
local PAW_INITIAL_WAIT = 7.0 -- Initial wait time at the Paw position.
local EXCLUDED_CONTAINER_NAMES = {"MainMap!Fall"} -- NEW: List of container names to ignore during the search.
local VERSION_TEXT = "V9.0 FIX: Increased Mannequin container search to 7s and added debug logging of Minigame children." 

-- Services and Player Setup (Set to nil initially, will be populated asynchronously)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = nil
local Character = nil
local HumanoidRootPart = nil

-- Global Control Flags
local IS_AUTO_PET_CLICK_ACTIVE = true -- Keep this for pet-specific toggle
local IsSequenceActive = false
local ShouldStop = false
local cycleCount = 0

print("--------------------------------------------------")
print("Fashion Frenzy Automation Safe API Initialized")
print(string.format("Version: %s", VERSION_TEXT))
print(string.format("Main Script Status: Controllable via _G.SOT_TELEPORTER_RUNNING | Auto Pet Click Active: %s", tostring(IS_AUTO_PET_CLICK_ACTIVE)))
print("--------------------------------------------------")

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Function to safely convert the MM:SS timer string into total seconds (number)
local function timerStringToSeconds(timerString)
	-- Handle format "M:SS" or "MM:SS"
	local minutes, seconds = timerString:match("(%d+):(%d+)")
	if minutes and seconds then
		return tonumber(minutes) * 60 + tonumber(seconds) + 0.01 -- Add small offset to handle floating point safety
	end
	return 0
end

-- Updated function to find a child by a non-exact prefix match and exclude specific names
local function findChildByPrefix(parent, prefix, excludeNames)
    excludeNames = excludeNames or {}
	for _, child in ipairs(parent:GetChildren()) do
		-- Check if the child name STARTS with the prefix
		if child.Name:sub(1, #prefix) == prefix then
            
            -- Check for explicit exclusion
            local isExcluded = false
            for _, excludedName in ipairs(excludeNames) do
                if child.Name == excludedName then
                    isExcluded = true
                    break
                end
            end

            if not isExcluded then
			    return child
            end
		end
	end
	return nil
end

local function getCurrentWorkspaceTimerText()
    local interiors = Workspace:FindFirstChild("Interiors")
    if not interiors then return nil end

    -- Find the FashionFrenzy container using prefix
    local fashionFrenzyContainer = findChildByPrefix(interiors, "FashionFrenzy::", EXCLUDED_CONTAINER_NAMES)
    if not fashionFrenzyContainer then return nil end
    
    -- Navigate the rest of the path as confirmed by user
    local customize = fashionFrenzyContainer:FindFirstChild("Customize", true)
    local minigame = customize and customize:FindFirstChild("Minigame", true)
    local timerSigns = minigame and minigame:FindFirstChild("TimerSigns", true)
    local timerSign = timerSigns and timerSigns:FindFirstChild("TimerSign", true)
    local timerBlock = timerSign and timerSign:FindFirstChild("TimerBlock", true)
    local surfaceGui = timerBlock and timerBlock:FindFirstChild("SurfaceGui", true)
    local frame = surfaceGui and surfaceGui:FindFirstChild("Frame", true)
    local textLabel = frame and frame:FindFirstChild("TextLabel", true)

	if textLabel and textLabel:IsA("TextLabel") then
        return textLabel.Text
    end
    return nil
end

local function getCurrentTimerText()
	-- CRITICAL: Check if LocalPlayer is initialized before accessing its properties
    if not LocalPlayer then return nil end
    
	-- 1. Check PlayerGui (Primary, most reliable source)
	local app = LocalPlayer.PlayerGui:FindFirstChild("FashionFrenzyInGameApp", true)
	local body = app and app:FindFirstChild("Body")
	local left = body and body:FindFirstChild("Left")
	local container = left and left.Container
	local valueLabel = container and container:FindFirstChild("ValueLabel")

	if valueLabel and valueLabel:IsA("TextLabel") then
		return valueLabel.Text
	end
    
    -- 2. Fallback to Workspace/SurfaceGui timer (as requested)
    local workspaceTimer = getCurrentWorkspaceTimerText()
    if workspaceTimer then
        print("[TIMER FALLBACK] Using Workspace Timer Sign.")
        return workspaceTimer
    end

	return nil
end

local function waitWithStopCheck(duration)
	local checkInterval = 1
	local remaining = duration

    -- CRITICAL: Check both ShouldStop (timer) and global flag (_G.SOT_TELEPORTER_RUNNING)
	while remaining > 0 and not ShouldStop and _G.SOT_TELEPORTER_RUNNING do
		local waitTime = math.min(checkInterval, remaining)
		task.wait(waitTime)
		remaining = remaining - checkInterval
	end
end

local function timerMonitor()
	while true do
        -- Only monitor if the script is active globally
        if _G.SOT_TELEPORTER_RUNNING and IsSequenceActive then
			local text = getCurrentTimerText()

			if text then
				-- Check if the current time matches any of the stop values
				for _, stopValue in ipairs(TIMER_STOP_VALUES) do
					if text == stopValue then
						if not ShouldStop then
							print(string.format("[TIMER STOP] !! Timer HIT STOP VALUE (%s). Stopping sequence.", stopValue))
							ShouldStop = true
							break
						end
					end
				}
			end
		end
		task.wait(0.1) 
	end
end
-- task.spawn(timerMonitor) -- Spawned in initializePlayerAndStartLoops

--------------------------------------------------------------------------------
-- GUI INTERACTION FUNCTIONS
--------------------------------------------------------------------------------

-- WARNING: This function uses 'getconnections', which is an undocumented and 
-- potentially restricted function outside of standard Roblox Luau execution 
-- environments. This bypasses the safe API restriction of prior versions for maximum click effectiveness.
local function clickButton(button)
    -- Check if getconnections is available in the environment. If not, it falls back to an empty table.
    local getconnections = _G.getconnections 
    
    if not getconnections then 
        warn("[UNSAFE API] 'getconnections' is not defined. Falling back to safe 'Activate()' method.")
        if button and (button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton")) then
            button:Activate() 
            button.MouseButton1Click:Fire()
            return true
        end
        return false
    end
    
    if not button or not (button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton")) then 
		return false 
	end

    print("[CLICK BYPASS] Firing connections for:", button.Name)
    
    -- Fire MouseButton1Down connections
    for _, connection in pairs(getconnections(button.MouseButton1Down)) do
        connection:Fire()
    end

    -- Fire MouseButton1Click connections
    for _, connection in pairs(getconnections(button.MouseButton1Click)) do
        connection:Fire()
    end

    -- Fire MouseButton1Up connections
    for _, connection in pairs(getconnections(button.MouseButton1Up)) do
        connection:Fire()
    end
    
    return true
end

local function checkBackpackVisibility()
	-- CRITICAL: Check if LocalPlayer is initialized before accessing its properties
    if not LocalPlayer then return false end
    
	local gui = LocalPlayer.PlayerGui
	local backpackApp = gui:FindFirstChild("BackpackApp")
	local isVisible = backpackApp and backpackApp:IsA("ScreenGui") and backpackApp.Enabled
	return isVisible
end

local function findInventoryButton()
	-- CRITICAL: Check if LocalPlayer is initialized before accessing its properties
    if not LocalPlayer then return nil end
    
	local gui = LocalPlayer.PlayerGui
	local SEARCH_NAMES = {"InventoryButton", "BackpackButton", "BagButton", "ItemsButton"}
	for _, name in ipairs(SEARCH_NAMES) do
		local button = gui:FindFirstChild(name, true)
		if button and (button:IsA("GuiButton")) then 
			return button
				end
	end
	return nil
end

local function openMainInventory()
	-- Do not proceed if the global switch is off or LocalPlayer is not ready
    if not _G.SOT_TELEPORTER_RUNNING or not LocalPlayer then return end
    
	if checkBackpackVisibility() then return end

	local button = findInventoryButton()

	if button then
		local success = false
		for attempt = 1, MAX_CLICK_RETRIES do
			if not _G.SOT_TELEPORTER_RUNNING then return end -- Check inside the retry loop
			
			if clickButton(button) then 
				success = true
				break
			end
			task.wait(0.2)
		end

		if success then
			task.wait(0.5)
		else
			warn("[INVENTORY] Failed to open Backpack via Inventory button after all retries.")
		end
	else
		warn("[INVENTORY] Could not find the main Backpack/Inventory UI button.")
	end
end

local function clickAllBasicSelects()
	-- CRITICAL: Check global kill switch or if LocalPlayer is not ready
	if ShouldStop or not _G.SOT_TELEPORTER_RUNNING or not LocalPlayer then return end

	local basicSelectsContainer = LocalPlayer.PlayerGui:FindFirstChild("InteractionsApp", true)
		and LocalPlayer.PlayerGui.InteractionsApp:FindFirstChild("BasicSelects", true)

	if not basicSelectsContainer then
		warn("[INTERACTION] InteractionsApp.BasicSelects container not found. Skipping clicks.")
		return
	end

	local clickCount = 0
    
	for _, templateFrame in ipairs(basicSelectsContainer:GetChildren()) do
		-- CRITICAL: Check global kill switch inside the loop
		if ShouldStop or not _G.SOT_TELEPORTER_RUNNING then break end

		if templateFrame:IsA("GuiObject") then
			local buttonToClick = templateFrame:FindFirstChild("TapButton", true)

			if buttonToClick and buttonToClick:IsA("GuiButton") then
				
                -- CRITICAL FIX V6.3: Spawn the click to make it truly non-blocking.
				task.spawn(function()
				    if _G.SOT_TELEPORTER_RUNNING then -- Final check before firing
				        clickButton(buttonToClick)
                    end
				end)
                
                clickCount = clickCount + 1
			end
		end
	end
	
	-- Short yield to ensure all spawned tasks are scheduled before proceeding.
    task.wait(0.05) 
    
	print(string.format("[INTERACTION] Finished fast-clicking %d BasicSelect buttons. (Async)", clickCount))
end

-- NEW FUNCTION: One-time pet clicking during the main sequence
local function clickPetsInRow0()
	-- Do not proceed if the global switch is off or LocalPlayer is not ready
	if not _G.SOT_TELEPORTER_RUNNING or not LocalPlayer or ShouldStop then return end
    
	local gui = LocalPlayer.PlayerGui
    
    openMainInventory()
    task.wait(0.2)

    local BackpackApp = gui:FindFirstChild("BackpackApp")

    if BackpackApp and BackpackApp.Enabled then
        local scrollingFrame = BackpackApp:FindFirstChild("Frame", true)
        local targetContainer

        if scrollingFrame then
            -- Use the path confirmed from the file image: Body > ScrollComplex > ScrollingFrame > Content > pets > Row0
            local Body = scrollingFrame:FindFirstChild("Body", true)
            local ScrollComplex = Body and Body:FindFirstChild("ScrollComplex", true)
            local ScrollingFrame = ScrollComplex and ScrollComplex:FindFirstChild("ScrollingFrame")
            local Content = ScrollingFrame and ScrollingFrame:FindFirstChild("Content")
            local pets = Content and Content:FindFirstChild("pets")
            local petRows = pets and pets:FindFirstChild("Row0")
            
            targetContainer = petRows
        end

        if targetContainer then
            local clickCount = 0
            
            -- Wait briefly for items to render
            task.wait(0.2) 

            for _, descendant in ipairs(targetContainer:GetDescendants()) do
                if descendant:IsA("GuiButton") then
                    local lowerName = descendant.Name:lower()
                    -- Target buttons that are typically pet item holders
                    local isPetItemButton = lowerName == "button" or lowerName == "tapbutton" or lowerName:match("^%d+%_")

                    if isPetItemButton then
                        -- Use the powerful clickButton method
                        task.spawn(function()
                            if _G.SOT_TELEPORTER_RUNNING and not ShouldStop then 
                                if clickButton(descendant) then
                                    clickCount = clickCount + 1
                                end
                            end
                        end)
                        task.wait(0.01) -- Small yield between clicks
                    end
                }
            }
            print(string.format("[PET EXECUTE] Successfully triggered %d pet item clicks (Async).", clickCount))
        else
            warn("[PET EXECUTE] Pet item container (Row0) not found inside open Backpack.")
        end
    else
        warn("[PET EXECUTE] Backpack is not open, skipping pet item clicks.")
    end
    
    -- Close the inventory (Optional, but clean)
    local button = findInventoryButton()
    if button then 
        clickButton(button)
    end
end

--------------------------------------------------------------------------------
-- CONTINUOUS ROW0 PET CLICK LOOP (REMOVED - Now integrated into main sequence)
--------------------------------------------------------------------------------

local function continuousRow0ClickLoop()
	-- This function is now DEPRECATED. 
	-- The logic has been moved to clickPetsInRow0 and integrated into runPrimarySequence.
	-- This loop now only yields to avoid erroring if still spawned.
    while true do
        task.wait(5)
    end
end
-- task.spawn(continuousRow0ClickLoop) -- Still spawned below, but is now a placeholder

--------------------------------------------------------------------------------
-- TELEPORT FUNCTIONS
--------------------------------------------------------------------------------

local function findBestPartToTeleportTo(model, primaryName)
	local primaryPart = model:FindFirstChild(primaryName, true)
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end
	if model:IsA("BasePart") then
		return model
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			return descendant
		end
	end
	return nil
end

local function TeleportTo(position)
	-- CRITICAL: Check global kill switch
	if ShouldStop or not _G.SOT_TELEPORTER_RUNNING then return end

    -- CRITICAL: Add an additional safety check for HumanoidRootPart existence
    if not HumanoidRootPart or not HumanoidRootPart.Parent then
        warn("[TELEPORT FAIL] HumanoidRootPart is missing or destroyed (Not initialized). Cannot teleport.")
        return
    end

	local marker = Instance.new("Part")
	marker.Name = "TeleportMarker"
	marker.Size = Vector3.new(1.5, 1.5, 1.5)
	marker.Position = position + Vector3.new(0, 3, 0)
	marker.Transparency = 0.2
	marker.Anchored = true
	marker.CanCollide = false
    
    -- V8.3 FIX: Use Color3 for guaranteed green color instead of BrickColor.new()
	marker.Color = Color3.fromRGB(0, 255, 0) 
    
	marker.Material = Enum.Material.Neon
	marker.Parent = Workspace

	HumanoidRootPart.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))

	task.wait(TELEPORT_DELAY)

	marker:Destroy()
end

local function findFirstPawPart(minigameContainer)
	-- V8.4 FIX: Updated path based on user confirmation: 
	-- Minigame > PetPodiums > PetPodium1 > "1" > Paw
	
	-- Step 1: Find "PetPodiums"
	local petPodiumsContainer = minigameContainer:FindFirstChild("PetPodiums")
    
    if not petPodiumsContainer then warn("[PAW PATH DEBUG V8.4] PetPodiums container not found.") return nil end
    
	-- Step 2: Find "PetPodium1"
	local petPodium1 = petPodiumsContainer:FindFirstChild("PetPodium1", true) 

	if not petPodium1 then 
        warn("[PAW PATH DEBUG V8.4] PetPodium1 not found.")
        return nil 
    end
    
    -- Step 3: Find the model/part named "1" (the actual target holder)
	local specificPodiumPart = petPodium1:FindFirstChild("1", true) 
    
    if not specificPodiumPart then 
        warn("[PAW PATH DEBUG V8.4] PetPodium1['1'] not found.")
        return nil 
    end

    -- Step 4: Find the final "Paw" part
    local targetPart = specificPodiumPart:FindFirstChild("Paw")
	if targetPart and targetPart:IsA("BasePart") then
		return targetPart -- Return the Part object
	end
    
    warn("[PAW PATH DEBUG V8.4] Found specific podium part, but no part named 'Paw' was found.")
	return nil
end

--------------------------------------------------------------------------------
-- TELEPORT SEQUENCE FUNCTIONS
--------------------------------------------------------------------------------

local function teleportToMannequins(minigameContainer, returnPosition)
	print("--- STARTING MANNEQUIN TELEPORT & ACCESSORY CYCLE ---")
	
    -- Mannequins Container path confirmed by user: ...Minigame.AccessoryMannequins
	local mannequinsContainer = nil

    -- NEW V9.0: Robustly wait for Mannequin container (up to 7 seconds)
    for attempt = 1, 7 do
        mannequinsContainer = minigameContainer:FindFirstChild("AccessoryMannequins")
        if mannequinsContainer then 
            print(string.format("[MANNEQUIN INIT] SUCCESS: Mannequin container found on attempt %d.", attempt))
            break 
        end
        
        print(string.format("[MANNEQUIN INIT] DEBUG: Waiting for 'AccessoryMannequins' container... (Attempt %d/7)", attempt))

        -- V9.0 CRITICAL LOGGING: On first attempt fail, list all children to debug naming/loading
        if attempt == 1 then
            local childNames = {}
            for _, child in ipairs(minigameContainer:GetChildren()) do
                table.insert(childNames, child.Name)
            end
            print(string.format("[MANNEQUIN INIT] DEBUG: MinigameContainer children found: {%s}", table.concat(childNames, ", ")))
        end

        task.wait(1.0)
    end
    
    -- CRITICAL: Check global kill switch and container presence
	if not mannequinsContainer or ShouldStop or not _G.SOT_TELEPORTER_RUNNING then 
        warn(string.format("[SEQUENCE ABORT] Mannequin container 'AccessoryMannequins' was NOT found after 7 attempts or sequence stopped. Aborting mannequin cycle."))
        return 
    end

	local targetsFound = 0
    local allMannequins = mannequinsContainer:GetChildren()
    print(string.format("[MANNEQUIN SCAN] Found %d mannequin models to process.", #allMannequins))
    
    -- Iterate through all children (the individual mannequin models with UUID names)
	for i, mannequinModel in ipairs(allMannequins) do
		-- CRITICAL: Check global kill switch inside the loop
		if ShouldStop or not _G.SOT_TELEPORTER_RUNNING then 
            print("[MANNEQUIN STOP] Aborting mannequin cycle early (Timer hit stop value or script deactivated).")
            break 
        end
        
        -- We only care about models/parts that are actual mannequins
        if mannequinModel:IsA("Model") or mannequinModel:IsA("BasePart") then

            targetsFound = targetsFound + 1
            -- We teleport to the Head part of the mannequin model
            local targetPart = findBestPartToTeleportTo(mannequinModel, "Head")

            if targetPart then
                print(string.format("[MANNEQUIN %d/%d] Teleporting to Mannequin: %s (Target: %s) - Testing accessories.", targetsFound, #allMannequins, mannequinModel.Name, targetPart.Name))

                TeleportTo(targetPart.Position)
                
                print(string.format("[MANNEQUIN %d/%d] Executing interaction clicks (fast fire, ASYNC)...", targetsFound, #allMannequins))
                clickAllBasicSelects()
                
                print(string.format("[MANNEQUIN %d/%d] Waiting %.1f seconds for accessory testing...", targetsFound, #allMannequins, MANNEQUIN_TEST_TIME))
                waitWithStopCheck(MANNEQUIN_TEST_TIME)
                
                -- CRITICAL FIX: Ensure return teleport happens regardless of timer status
                if returnPosition then
                    print(string.format("[MANNEQUIN %d/%d] Confirmation Step: Teleporting back to Paw.", targetsFound, #allMannequins))
                    TeleportTo(returnPosition)
                end
                
                -- Now check the stop condition *after* completing the Paw teleport cleanup
                if ShouldStop or not _G.SOT_TELEPORTER_RUNNING then 
                    warn("[MANNEQUIN STOP] Timer expired during mannequin cycle. Final cleanup complete (Teleported back to Paw). Aborting loop.")
                    break 
                end
            end
        end
	end
	print(string.format("--- MANNEQUIN TELEPORT & ACCESSORY CYCLE FINISHED. Processed %d out of %d mannequins. ---", targetsFound, #allMannequins))
end

local function runPrimarySequence(minigameContainer)
	IsSequenceActive = true
	ShouldStop = false
	cycleCount = cycleCount + 1
	
	-- V6.9: Use pcall to catch errors and ensure IsSequenceActive is reset
	local success, result = pcall(function()
        
        print(string.format("--- STARTING NEW FASHION FRENZY CYCLE #%d ---", cycleCount))
        
        local pawPart = nil
        
        -- FIX: Retry loop for Paw asset loading to prevent immediate sequence abort
        for attempt = 1, 5 do
            if not _G.SOT_TELEPORTER_RUNNING then 
                warn("[CYCLE ABORT] Global switch turned off during asset search.")
                return -- EXIT pcall function early
            end

            pawPart = findFirstPawPart(minigameContainer)
            
            if pawPart and pawPart.Parent then 
                print(string.format("[ASSET SUCCESS] Paw found on attempt %d.", attempt))
                break -- Found the part and it's in the game
            end
            
            warn(string.format("[ASSET WAIT] Paw asset not found/valid on attempt %d. Waiting 1.0s...", attempt))
            task.wait(1.0)
        end

        if not pawPart or not pawPart.Parent then
            warn("[CYCLE ABORT] Could not find a valid Paw part to start the sequence after 5 attempts.")
            print("[PAW DEBUG V9.0] SEQUENCE ABORTED. Paw part was not found.")
            return -- EXIT pcall function early
        end
        
        local pawPosition = pawPart.Position -- Get position after confirming validity
        
        print(string.format("[CYCLE %d] Paw asset found and confirmed. Teleporting...", cycleCount))

        TeleportTo(pawPosition)
        print(string.format("[CYCLE %d] Teleported to Paw. STARTING %.1f second wait...", cycleCount, PAW_INITIAL_WAIT))
        
        -- Initial wait at the Paw position as requested
        waitWithStopCheck(PAW_INITIAL_WAIT)
        
        -- Check if the wait was aborted
        if ShouldStop or not _G.SOT_TELEPORTER_RUNNING then 
            warn("[CYCLE ABORT] Paw wait aborted by timer/script deactivation.")
            return -- EXIT pcall function early
        end
        
        -- NEW INTEGRATION: Click Pet buttons before proceeding to the Mannequins
        if IS_AUTO_PET_CLICK_ACTIVE then
            print(string.format("[CYCLE %d] PAW WAIT FINISHED. Executing one-time Pet Item Click.", cycleCount))
            clickPetsInRow0()
        end
        
        print(string.format("[CYCLE %d] Proceeding to Mannequins. This includes the Accessory Interaction Clicks.", cycleCount))

        teleportToMannequins(minigameContainer, pawPosition)

        TeleportTo(pawPosition)
        print(string.format("[CYCLE %d] Teleported to Paw for final selection.", cycleCount))

        ShouldStop = false
        print(string.format("--- CYCLE #%d COMPLETE. Searching for new round. ---", cycleCount))
    end)
    
    -- ALWAYS reset IsSequenceActive after the sequence attempt
	IsSequenceActive = false 

    if not success then
        -- Log the caught Luau error to help with debugging
        error(string.format("[CRITICAL ERROR] Sequence Aborted due to Luau Error in Cycle #%d: %s", cycleCount, tostring(result)))
    end
end

--------------------------------------------------------------------------------
-- MAIN GAME SEARCH LOOP
--------------------------------------------------------------------------------

local function mainSearchLoop()
    -- CRITICAL: Ensure player data is ready before starting the loop
    if not LocalPlayer then 
        warn("[MAIN LOOP FAIL] LocalPlayer not initialized. Main search loop aborted.")
        return 
    end
    
    print("[DEBUG START] Main search loop initialized and beginning first check.")
    
	local MINIGAME_CONTAINER_COMPONENTS_STATIC = {
		"Interiors",
		"FashionFrenzy::", -- Using the full confirmed prefix
		"Customize",
		"Minigame" 
	}
	
	local thresholdSeconds = timerStringToSeconds(TIMER_START_THRESHOLD)
	
	while true do
        
        -- V8.8 NEW DEBUG: This message confirms the 'mainSearchLoop' is actively running.
        print(string.format("[DEBUG LOOP] Search cycle running (Wait: %.1fs). IsActive: %s", SEARCH_WAIT_TIME, tostring(IsSequenceActive)))
        
		-- CRITICAL: Check global kill switch (now defaults to true)
		if _G.SOT_TELEPORTER_RUNNING then
			-- V6.9: Only check timer if no sequence is currently running
			if not IsSequenceActive and not ShouldStop then
				
				local fashionFrenzyContainer = nil
				local interiors = Workspace:FindFirstChild(MINIGAME_CONTAINER_COMPONENTS_STATIC[1])
				
                if not interiors then
                    print("[SEARCH ABORTED] Waiting for 'Interiors' folder to appear in Workspace.")
                end

				if interiors then
                    -- Use findChildByPrefix with the full prefix
					fashionFrenzyContainer = findChildByPrefix(interiors, MINIGAME_CONTAINER_COMPONENTS_STATIC[2], EXCLUDED_CONTAINER_NAMES)
                    
                    if not fashionFrenzyContainer then
                        print(string.format("[SEARCH] Searching for new Fashion Frenzy round... (No map container found in Interiors)"))
                    end
				}

				if fashionFrenzyContainer then
					local customize = fashionFrenzyContainer:FindFirstChild(MINIGAME_CONTAINER_COMPONENTS_STATIC[3])
					local minigameContainer = customize and customize:FindFirstChild(MINIGAME_CONTAINER_COMPONENTS_STATIC[4])

					if minigameContainer then
						
						print(string.format("[SEARCH SUCCESS] Found Minigame Container: %s", minigameContainer.Name))
						
						local currentTimer = getCurrentTimerText()
						local timerSeconds = currentTimer and timerStringToSeconds(currentTimer)
						
                        print(string.format("[DEBUG TIMER] Current Timer Read: %s (Seconds: %s), Threshold: %s (Seconds: %s)", 
                            currentTimer or "nil", tostring(timerSeconds or "nil"), TIMER_START_THRESHOLD, thresholdSeconds))
                        
						if timerSeconds and timerSeconds > thresholdSeconds then
							print(string.format("[SEARCH] Minigame ready. Timer is %s (%d seconds, above %s). Starting sequence...", currentTimer, timerSeconds, TIMER_START_THRESHOLD))
                            -- V6.9: Spawn the sequence to ensure IsSequenceActive=true is registered immediately and search loop doesn't block.
							task.spawn(runPrimarySequence, minigameContainer) 
                            
                            -- V7.8 FIX: Add a brief yield to allow the spawned thread to execute its first line, setting IsSequenceActive = true.
                            -- This prevents the search loop from immediately spawning a duplicate cycle.
                            task.wait(0.1) 
						else
							print(string.format("[SEARCH] Minigame ready, but timer is low (%s). Waiting for the round to end.", currentTimer or "N/A"))
						end
					else
						print("[SEARCH] Round Found, but Minigame parts still loading...")
					end
				else
					-- If Interiors exists but no FashionFrenzy map exists, the generic search message runs above.
				end

			end
		end

		task.wait(SEARCH_WAIT_TIME)
	end
end
-- task.spawn(mainSearchLoop) -- Spawned in initializePlayerAndStartLoops

--------------------------------------------------------------------------------
-- INITIALIZATION FUNCTION (V8.8 FIX)
--------------------------------------------------------------------------------

local function initializePlayerAndStartLoops()
    
    print("[INIT DEBUG V8.8] Acquiring LocalPlayer...")
    local tempLocalPlayer = Players.LocalPlayer
    
    -- Robust loop to wait for LocalPlayer property to be populated (Max 10 seconds)
    local localPlayerTimeout = 10
    local startTime = tick()
    while not tempLocalPlayer and (tick() - startTime < localPlayerTimeout) and _G.SOT_TELEPORTER_RUNNING do
        print("[INIT DEBUG V8.8] LocalPlayer property is nil. Waiting 0.5s...")
        task.wait(0.5)
        tempLocalPlayer = Players.LocalPlayer
    end

    if not tempLocalPlayer then
        warn("[INIT FAIL] Script aborted. Could not find LocalPlayer property within 10 seconds.")
        return 
    end
    
    LocalPlayer = tempLocalPlayer -- Set the main script variable
    print(string.format("[INIT DEBUG V8.8] LocalPlayer found! Name: %s", LocalPlayer.Name))
    
    
    -- Check for Character (either already present or wait for it)
    print("[INIT DEBUG V8.8] Checking/Waiting for Character to load...")
    
    local tempCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Character = tempCharacter -- Set the main script variable
    
    if Character then
        print(string.format("[INIT DEBUG V8.8] Character found! Name: %s. Waiting for HRP with 15s timeout...", Character.Name))
        
        -- V8.7 CRITICAL FIX: Add a timeout to WaitForChild to prevent infinite yield
        -- This will be nil if the wait times out
        HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 15) 
    end
    
    if LocalPlayer and Character and HumanoidRootPart then
        print("[INIT SUCCESS] Player, Character, and HRP successfully acquired. Starting continuous loops...")

        -- Spawn the main loops ONLY after HRP is ready
        task.spawn(timerMonitor)
        task.spawn(continuousRow0ClickLoop) -- Still spawned, but is now a placeholder loop
        task.spawn(mainSearchLoop)
    else
        -- Log detailed failure reason
        warn(string.format("[INIT FAIL] Initialization failed. LocalPlayer: %s, Character: %s, HRP: %s. Script will not run core features.",
            tostring(LocalPlayer ~= nil), tostring(Character ~= nil), tostring(HumanoidRootPart ~= nil)))
    end
end

-- Start the initialization in a separate, non-blocking thread immediately.
task.spawn(initializePlayerAndStartLoops)
