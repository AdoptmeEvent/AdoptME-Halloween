


-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Modules
local ClientDataModulePath = ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("Core"):WaitForChild("ClientData")
local ClientDataModuleRef = nil

local function getClientDataModule()
    if not ClientDataModuleRef or type(ClientDataModuleRef) ~= "table" then
        local success, module = pcall(require, ClientDataModulePath)
        if success and type(module) == "table" then
            ClientDataModuleRef = module
        else
            warn("Failed to load ClientDataModule:", module)
            ClientDataModuleRef = nil
        end
    end
    return ClientDataModuleRef
end

local function getLatestServerData()
    local module = getClientDataModule()
    if not module or type(module.get_data) ~= "function" then return nil end
    local success, data = pcall(module.get_data)
    if not success then return nil end
    return data
end

-- Versioning
local VERSION = "1.0.23" -- FIX: Implemented a safelist filter in the Gift Dropdown to exclude non-openable items (like furniture) incorrectly stored in the 'gifts' inventory table.

-- Load Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "v1.0.23 EventMasterGroup",
    Icon = 16019271248,
    LoadingTitle = "EventMaster",
    LoadingSubtitle = "by EventMaster Group (v" .. VERSION .. ")", 
    Theme = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RayfieldConfigs",
        FileName = "EventMasterGroup"
    },
    Discord = {Enabled = false},
    KeySystem = true,
})

-- Tabs
local PetTab = Window:CreateTab("Pet Management", 4483362458)
local ExtraTab = Window:CreateTab("Utility & Auto-Buy", 4483362458)
local EventTab = Window:CreateTab("Event Management", 4483362458)
local VisualTab = Window:CreateTab("Visual", 4483362458) 
local ReleaseNotesTab = Window:CreateTab("ReleaseNotes", 4483362458)


-- UI Elements (Forward declarations)
local PetDropdown = nil
local FoodDropdown = nil
local GiftDropdown = nil
local PotionDelaySlider = nil
local AutoAgeToggle = nil
local AutoOpenBoxToggle = nil -- Renamed to be more general
local RefreshButton = nil
local SelectedPetAgeLabel = nil
local AutoNeonToggle = nil
local NeonFusionPetDropdown = nil
local AutoBuyItemDropdown = nil
local AutoBuyAmountSlider = nil
local AutoBuyGlobalToggle = nil
local AutoClaimQuestToggle = nil
local HotBarManagerToggle = nil
local HauntletFarmToggle = nil
local JoinZoneDetectionToggle = nil
local FashionFrenzyAllToggle = nil
local WhereBearToggle = nil
local TrickOrTreatToggle = nil
local OpenPetPenUIToggle = nil
local AutoClaimYarnApplesToggle = nil
local AutoProgressKittyBatsToggle = nil

-- New variables to guard UI creation (FIX for FindFirstChild error)
local PetFarmComingSoonToggle = nil
local ReleaseNotesHeaderLabel = nil

-- Visual Tab Labels
local VisualTab_MainEventTimerLabel = nil
local VisualTab_FashionTimerLabel = nil
local VisualTab_HauntletTimerLabel = nil
local VisualTab_CandyAmountLabel = nil
local VisualTab_BucksAmountLabel = nil
local _VISUAL_MONITOR_TASK = nil -- Task tracker for the monitoring loop

local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer
local targetPlayerName = LocalPlayer.Name

-- State variables
local currentlySelectedPetUniqueId = nil
local potionUseDelay = 1
local autoGiveAgePotionEnabled = false
local autoOpenGiftBoxEnabled = false -- Updated state variable name
local autoNeonEnabled = false
local selectedNeonPetSpeciesId = nil
local hotBarManagerEnabled = false
local autoClaimYarnApplesEnabled = false
local autoProgressKittyBatsEnabled = false
local autoClaimQuestEnabled = false 
local currentQuestClaimTask = nil 

-- Safelist of item IDs that are actually intended to be "opened" gifts/boxes/eggs.
-- This filters out items like furniture/toys that the game incorrectly lists under the 'gifts' inventory category.
local openableGiftItemIds = {
    "summerfest_2025_kelp_raider_box",
    "halloween_2025_spider_box",
    "box_mystery", -- Generic mystery boxes/eggs
    "box_pet_gift",
    "box_royal_egg",
    "box_ocean_egg",
    "box_fossil_egg",
    "egg_royal", -- Various eggs
    "egg_fossil",
    "egg_ocean",
    "egg_mythic",
    "egg_cracked",
    "egg_pet",
    "pet_gift_box", -- Common gift boxes
    "gift_box",
    "large_gift_box",
    "golden_gift_box",
    "diamond_gift_box",
    "small_gift", -- Various gift types
    "big_gift",
    "huge_gift",
    "box_golden_pet", -- Golden Pet Egg Box
}

local function isItemOpenableGift(itemId)
    for _, id in ipairs(openableGiftItemIds) do
        if id == itemId then
            return true
        end
    end
    return false
end

-- Buyable items (Updated with new Halloween items)
local allBuyableItems = {
    -- Existing Summer Items
    { id = "summerfest_2025_kelp_raider_box", category = "gifts", defaultCount = 1, name = "Kelp Raider Box" },
    { id = "summerfest_2025_island_tarsier", category = "pets", defaultCount = 16, name = "Island Tarsier" },
    { id = "summerfest_2025_manta_ray", category = "pets", defaultCount = 1, name = "Manta Ray" },
    { id = "summerfest_2025_seabed_creeper", category = "pets", defaultCount = 16, name = "Seabed Creeper" },
    { id = "summer_2025_emperor_shrump", category = "pets", defaultCount = 16, name = "Emperor Shrimp" },
    { id = "summerfest_2025_coconut_friend", category = "pets", defaultCount = 3, name = "Coconut Friend" },
    { id = "summerfest_2025_pirate_skull_vehicle", category = "transport", defaultCount = 1, name = "Pirate Skull Vehicle" },
    { id = "summerfest_2025_pirate_row_boat", category = "transport", defaultCount = 1, name = "Pirate Row Boat" },
    -- NEW HALLOWEEN ITEMS (Only the spider box should appear in the gift dropdown if it's owned)
    { id = "halloween_2025_spider_box", category = "gifts", defaultCount = 1, name = "Halloween Spider Box" },
    { id = "halloween_2025_keyboard_leash", category = "accessories", defaultCount = 1, name = "Keyboard Leash" },
    { id = "halloween_2025_haunted_piano", category = "furniture", defaultCount = 1, name = "Haunted Piano" },
    { id = "halloween_2025_haunted_cupboard", category = "furniture", defaultCount = 1, name = "Haunted Cupboard" },
    { id = "halloween_2025_haunted_sofa_set", category = "furniture", defaultCount = 1, name = "Haunted Sofa Set" },
    { id = "halloween_2025_noob_voodoo_doll_chew_toy", category = "toys", defaultCount = 1, name = "Voodoo Doll Chew Toy" },
    { id = "halloween_2025_stalagmite", category = "furniture", defaultCount = 1, name = "Stalagmite Decoration" },
}

-- Data maps
local uniqueIdToPetDataMap = {}
local uniqueIdToPetDisplayStringMap = {}
local uniqueIdToFoodDataMap = {}
local uniqueIdToFoodDisplayStringMap = {}
local uniqueIdToGiftDataMap = {}
local uniqueIdToGiftDisplayStringMap = {}

-- Auto-buy system
local autoBuyStates = {}
local autoBuyCounts = {}
local currentSelectedAutoBuyItemId = nil
local currentAutoBuyTask = nil

for _, item in ipairs(allBuyableItems) do
    autoBuyStates[item.id] = false
    autoBuyCounts[item.id] = item.defaultCount
end

-- External script tracking (for simple ONCE loading)
local externalScriptsLoaded = {
    HauntletFarm = false,
    JoinZoneDetection = false,
    FashionFrenzyAll = false,
    WhereBear = false,
    TrickOrTreat = false,
    PetPenUI = false,
    QuestManager = false,
}

-- Generic Script Loader
local function loadExternalScript(scriptName, url, toggle)
    if not externalScriptsLoaded[scriptName] then
        print("Loading script: " .. scriptName .. " from " .. url)
        local success, err = pcall(function()
            -- This handles the loadstring(game:HttpGet('...'))() pattern
            loadstring(game:HttpGet(url))()
        end)
        
        if not success then
            warn("Failed to load script " .. scriptName .. ": " .. tostring(err))
            -- If loading fails, immediately turn the toggle off
            if toggle and toggle.Set then
                toggle:Set(false)
            end
        else
            print("Successfully loaded script: " .. scriptName)
            externalScriptsLoaded[scriptName] = true
        end
    elseif not toggle.CurrentValue then
        warn("Script '" .. scriptName .. "' is already running. Cannot stop external script without a designated stop function.")
    end
end

-- Generic ID resolver function
local function getDisplayId(idValue)
    if type(idValue) == "string" then
        return idValue
    elseif type(idValue) == "number" then
        return tostring(idValue)
    elseif type(idValue) == "table" and idValue then
        if idValue.Name and type(idValue.Name) == "string" then
            return idValue.Name
        elseif idValue.Value and type(idValue.Value) == "string" then
            return idIdValue.Value
        else
            return "[Complex ID Table]"
        end
    else
        return "UnknownID:" .. tostring(idValue)
    end
end

-- --- Hotbar Manager Functions ---
local function clickButton(button)
    if button then
        local log = function(msg) print("Hotbar Manager: " .. msg) end
        local function fireEvent(event, name)
            pcall(function()
                for _, connection in pairs(getconnections(event)) do
                    connection:Fire() 
                end
            end)
            log("Fired connections for: " .. name)
        end
        
        fireEvent(button.MouseButton1Down, "MouseButton1Down (Press)")
        task.wait(0.01)
        fireEvent(button.MouseButton1Click, "MouseButton1Click (Click)")
        task.wait(0.01)
        fireEvent(button.MouseButton1Up, "MouseButton1Up (Release)")
        task.wait(0.01)
        fireEvent(button.MouseButton2Down, "MouseButton2Down (Press)")
        task.wait(0.01)
        fireEvent(button.MouseButton2Click, "MouseButton2Click (Click)")
        task.wait(0.01)
        fireEvent(button.MouseButton2Up, "MouseButton2Up (Release)")

        log("Completed click sequence for: " .. button.Name)
    else
        print("Button not found!")
    end
end

local function clickAllHotbarItems()
    if not hotBarManagerEnabled then return end
    
    local hotbar = LocalPlayer.PlayerGui:FindFirstChild("MinigameHotbarApp")
        and LocalPlayer.PlayerGui.MinigameHotbarApp:FindFirstChild("Hotbar")

    if not hotbar then return end

    for _, container in ipairs(hotbar:GetChildren()) do
        if container:IsA("Folder") or container:IsA("Frame") or container:IsA("Model") then
            local button = container:FindFirstChild("Button")
            if button and button:IsA("GuiButton") and button.Visible and button.Active then
                clickButton(button)
                task.wait(0.01) 
            end
        end
    end
end
-- --- End Hotbar Manager Functions ---

-- Utility Functions for Auto Feature Stops
local function stopAutoAgePotionFeature()
    autoGiveAgePotionEnabled = false
    if AutoAgeToggle and AutoAgeToggle.Set then
        AutoAgeToggle:Set(false)
    end
end

local function stopAutoNeonFeature()
    autoNeonEnabled = false
    if AutoNeonToggle and AutoNeonToggle.Set then
        AutoNeonToggle:Set(false)
    end
end

local function stopAutoOpenBoxFeature()
    autoOpenGiftBoxEnabled = false
    if AutoOpenBoxToggle and AutoOpenBoxToggle.Set then
        AutoOpenBoxToggle:Set(false)
    end
end

local function stopAutoBuyFeature(itemId)
    if itemId and autoBuyStates[itemId] ~= nil then
        autoBuyStates[itemId] = false
    end
    if currentAutoBuyTask then
        task.cancel(currentAutoBuyTask)
        currentAutoBuyTask = nil
    end
    if AutoBuyGlobalToggle and AutoBuyGlobalToggle.Set then
        AutoBuyGlobalToggle:Set(false)
    end
end

-- --- Quest Claiming Logic ---
local function claimAllQuests()
    local module = getClientDataModule()
    if not module then warn("ClientData module not available for quest claim.") return end

    local getDataFunction = module.get_data
    if typeof(getDataFunction) ~= "function" then warn("Module does not contain a 'get_data' function.") return end

    local callSuccess, result = pcall(getDataFunction)
    if not callSuccess or typeof(result) ~= "table" then warn("Failed to call get_data() for quest claim.") return end

    local PARENT_KEY = "test65476858679" 
    local QUEST_MANAGER_KEY = "quest_manager"
    local CACHED_QUESTS_KEY = "quests_cached"
    
    local questData = result[PARENT_KEY] and result[PARENT_KEY][QUEST_MANAGER_KEY] and result[PARENT_KEY][QUEST_MANAGER_KEY][CACHED_QUESTS_KEY]
    local questUUIDs = {}

    if typeof(questData) == "table" then
        for uuid in pairs(questData) do
            table.insert(questUUIDs, uuid)
        end
    end

    if #questUUIDs == 0 then
        -- print("Auto Quest Claim: No quests found to claim.")
        return
    end

    local QuestAPI = ReplicatedStorage:WaitForChild("API", 5):WaitForChild("QuestAPI/ClaimQuest", 5)

    if not QuestAPI or not QuestAPI:IsA("RemoteFunction") then
        warn("Auto Quest Claim: Error: QuestAPI/ClaimQuest RemoteFunction not found.")
        return
    end

    local success, claimResult = pcall(QuestAPI.InvokeServer, QuestAPI, unpack(questUUIDs))

    if success then
        if claimResult == false then
            print(string.format("Auto Quest Claim: Invoked for %d quests. Server returned 'false' (often means already claimed or no reward).", #questUUIDs))
        elseif claimResult == nil then
             print(string.format("Auto Quest Claim: Invoked for %d quests (Server returned no data).", #questUUIDs))
        else
            print(string.format("Auto Quest Claim: Successfully invoked ClaimQuest for %d quests. Server response: %s", #questUUIDs, tostring(claimResult)))
        end
    else
        warn("Auto Quest Claim: Invocation Failed. Error:", tostring(claimResult))
    end
end
-- --- End Quest Claiming Logic ---

-- --- Visual Data Monitoring Loop ---
local function monitorVisualData()
    local updateTimer = 0.5 -- Update frequency in seconds
    local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- Ensure Visual Tab Labels exist before starting the loop
    if not VisualTab_MainEventTimerLabel or not VisualTab_FashionTimerLabel or not VisualTab_HauntletTimerLabel or not VisualTab_CandyAmountLabel or not VisualTab_BucksAmountLabel then
        -- This should be handled by the creation logic below, but we ensure robustness.
        warn("Visual Tab labels were not initialized correctly. Retrying initialization.")
        return
    end

    while true do
        local mainEventTimeText = "Loading..."
        local fashionTimeText = "Loading..."
        local hauntletTimeText = "Loading..."
        local candyAmountText = "N/A"
        local bucksAmountText = "N/A"
        
        -- 1. Main Event Timer
        local success, mainEventTime = pcall(function()
            local questApp = PlayerGui:FindFirstChild("QuestIconApp")
            if questApp then
                local imgButton = questApp:FindFirstChild("ImageButton")
                if imgButton then
                    local eventContainer = imgButton:FindFirstChild("EventContainer")
                    if eventContainer then
                        local eventFrame = eventContainer:FindFirstChild("EventFrame")
                        if eventFrame then
                            local eventImageBottom = eventFrame:FindFirstChild("EventImageBottom")
                            if eventImageBottom then
                                local eventTimeLabel = eventImageBottom:FindFirstChild("EventTime")
                                if eventTimeLabel and eventTimeLabel.Text and eventTimeLabel.Text ~= "" then
                                    return eventTimeLabel.Text
                                end
                            end
                        end
                    end
                end
            end
            return nil
        end)
        if success and mainEventTime then mainEventTimeText = mainEventTime end

        -- 2. Fashion Frenzy Timer 
        -- Path: workspace.Interiors["MainMap!Fall"].FashionFrenzyJoinZone.Billboard.BillboardGui.TimerLabel 
        local success, fashionTime = pcall(function()
            local map = Workspace.Interiors["MainMap!Fall"]
            if map then
                local fashionZone = map:FindFirstChild("FashionFrenzyJoinZone")
                if fashionZone then
                    local billboard = fashionZone:FindFirstChild("Billboard")
                    if billboard then
                        local billboardGui = billboard:FindFirstChild("BillboardGui")
                        if billboardGui then
                            local timerLabel = billboardGui:FindFirstChild("TimerLabel")
                            if timerLabel and timerLabel.Text and timerLabel.Text ~= "" then
                                return timerLabel.Text
                            end
                        end
                    end
                end
            end
            return nil
        end)
        if success and fashionTime then fashionTimeText = fashionTime end

        -- 3. Hauntlet Minigame Timer 
        -- Path: workspace.Interiors["MainMap!Fall"].HauntletMinigameJoinZone.Billboard.BillboardGui.TimerLabel 
        local success, hauntletTime = pcall(function()
            local map = Workspace.Interiors["MainMap!Fall"]
            if map then
                local hauntletZone = map:FindFirstChild("HauntletMinigameJoinZone")
                if hauntletZone then
                    local billboard = hauntletZone:FindFirstChild("Billboard")
                    if billboard then
                        local billboardGui = billboard:FindFirstChild("BillboardGui")
                        if billboardGui then
                            local timerLabel = billboardGui:FindFirstChild("TimerLabel")
                            if timerLabel and timerLabel.Text and timerLabel.Text ~= "" then
                                return timerLabel.Text
                            end
                        end
                    end
                end
            end
            return nil
        end)
        if success and hauntletTime then hauntletTimeText = hauntletTime end

        -- 4. Halloween Currency (Candy) Amount 
        -- Path: game:GetService("Players").LocalPlayer.PlayerGui.AltCurrencyIndicatorApp.CurrencyIndicator.Container.Amount
        local success, candyAmount = pcall(function()
            local indicatorApp = PlayerGui:FindFirstChild("AltCurrencyIndicatorApp")
            if indicatorApp then
                local indicator = indicatorApp:FindFirstChild("CurrencyIndicator")
                if indicator then
                    local container = indicator:FindFirstChild("Container")
                    if container then
                        local amountLabel = container:FindFirstChild("Amount")
                        if amountLabel and amountLabel.Text and amountLabel.Text ~= "" then
                            return amountLabel.Text
                        end
                    end
                end
            end
            return nil
        end)
        if success and candyAmount then candyAmountText = candyAmount end
        
        -- 5. Bucks Currency Amount
        -- Path: game:GetService("Players").LocalPlayer.PlayerGui.BucksIndicatorApp.CurrencyIndicator.Container.Amount
        local success, bucksAmount = pcall(function()
            local indicatorApp = PlayerGui:FindFirstChild("BucksIndicatorApp")
            if indicatorApp then
                local indicator = indicatorApp:FindFirstChild("CurrencyIndicator")
                if indicator then
                    local container = indicator:FindFirstChild("Container")
                    if container then
                        local amountLabel = container:FindFirstChild("Amount")
                        if amountLabel and amountLabel.Text and amountLabel.Text ~= "" then
                            return amountLabel.Text
                        end
                    end
                end
            end
            return nil
        end)
        if success and bucksAmount then bucksAmountText = bucksAmount end

        -- Update Window Title
        if Rayfield.SetTitle then
            if mainEventTimeText ~= "Loading..." then
                Rayfield:SetTitle("Adopt Me Halloween Suite | Timer: " .. mainEventTimeText)
            else
                Rayfield:SetTitle("Adopt Me Halloween Suite | Timer: [Loading...]")
            end
        end
        
        -- Update Visual Tab Labels
        if VisualTab_MainEventTimerLabel and VisualTab_MainEventTimerLabel.Set then
            VisualTab_MainEventTimerLabel:Set("Main Event Timer: " .. mainEventTimeText)
        end
        if VisualTab_FashionTimerLabel and VisualTab_FashionTimerLabel.Set then
            VisualTab_FashionTimerLabel:Set("Fashion Frenzy Timer: " .. fashionTimeText)
        end
        if VisualTab_HauntletTimerLabel and VisualTab_HauntletTimerLabel.Set then
            VisualTab_HauntletTimerLabel:Set("Hauntlet Minigame Timer: " .. hauntletTimeText)
        end
        if VisualTab_CandyAmountLabel and VisualTab_CandyAmountLabel.Set then
            VisualTab_CandyAmountLabel:Set("Halloween Currency (Candy): " .. candyAmountText)
        end
        if VisualTab_BucksAmountLabel and VisualTab_BucksAmountLabel.Set then
            VisualTab_BucksAmountLabel:Set("Bucks Currency: " .. bucksAmountText)
        end

        task.wait(updateTimer)
    end
end
-- --- End Visual Data Monitoring Loop ---

-- NEW: Function to create the Event Tab UI (ensuring all toggles are created)
local function createEventTabUI()
    local FIX_TEXT_COLOR = Color3.fromRGB(30, 30, 30)

    -- Event Management Tab Elements (These are created only once)
    -- We rely on HotBarManagerToggle being nil to know if the entire section has been created.
    if not HotBarManagerToggle then
        EventTab:CreateLabel(
            "Auto-Claim and Farming Toggles", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )

        -- 1. Hotbar Manager Toggle
        HotBarManagerToggle = EventTab:CreateToggle({
            Name = "HotBarManager (Click All Items)",
            CurrentValue = hotBarManagerEnabled,
            Flag = "HotBarManagerToggle",
            Callback = function(val)
                hotBarManagerEnabled = val
                if val then
                    task.spawn(function()
                        while hotBarManagerEnabled do
                            clickAllHotbarItems()
                            task.wait(0.5)
                        end
                    end)
                end
            end
        })

        -- 2. Hauntlet Farm (existing)


            HauntletFarmToggle = EventTab:CreateToggle({
            Name = "auto-close-reward coming soon",
            CurrentValue = false,
            Flag = "autoclosereward",
            Callback = function(val)
                if val then
                    loadExternalScript("autoclosereward", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/auto-close-rewards', HauntletFarmToggle)
                end
            end
        })



        HauntletFarmToggle = EventTab:CreateToggle({
            Name = "Hauntlet Farm Auto",
            CurrentValue = false,
            Flag = "HauntletFarmToggle",
            Callback = function(val)
                if val then
                    loadExternalScript("HauntletFarm", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/HauntletFarm.lua', HauntletFarmToggle)
                end
            end
        })

        -- 3. Join Zone Detection
        JoinZoneDetectionToggle = EventTab:CreateToggle({
            Name = "Join Zone Detection",
            CurrentValue = false,
            Flag = "JoinZoneDetectionToggle",
            Callback = function(val)
                if val then
                    loadExternalScript("JoinZoneDetection", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/JoinZoneDetection', JoinZoneDetectionToggle)
                end
            end
        })
        
        -- 4. Fashion Frenzy All
        FashionFrenzyAllToggle = EventTab:CreateToggle({
            Name = "Fashion Frenzy All",
            CurrentValue = false,
            Flag = "FashionFrenzyAllToggle",
            Callback = function(val)
                if val then
                    loadExternalScript("FashionFrenzyAll", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/FashionFrenzy', FashionFrenzyAllToggle)
                end
            end
        })

        -- 5. WhereBear
        WhereBearToggle = EventTab:CreateToggle({
            Name = "WhereBear Teleport",
            CurrentValue = false,
            Flag = "WhereBearToggle",
            Callback = function(val)
                if val then
                    loadExternalScript("WhereBear", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/WhereBear', WhereBearToggle)
                end
            end
        })

        -- 6. Trick Or Treat
        TrickOrTreatToggle = EventTab:CreateToggle({
            Name = "Trick Or Treat Auto",
            CurrentValue = false,
            Flag = "TrickOrTreatToggle",
            Callback = function(val)
                if val then
                    loadExternalScript("TrickOrTreat", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/TrickOrTreat', TrickOrTreatToggle)
                end
            end
        })

        -- 7. AutoClaimYarnApples (Treat Bag)
        AutoClaimYarnApplesToggle = EventTab:CreateToggle({
            Name = "Auto Claim Yarn Apples (Treat Bag)",
            CurrentValue = autoClaimYarnApplesEnabled,
            Flag = "AutoClaimYarnApplesToggle",
            Callback = function(val)
                autoClaimYarnApplesEnabled = val
                if val then
                    task.spawn(function()
                        local claimRemote = game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("HalloweenEventAPI/ClaimTreatBag")
                        while autoClaimYarnApplesEnabled do
                            local success, result = pcall(claimRemote.InvokeServer, claimRemote)
                            if success then
                                if result == nil then
                                    print("ClaimTreatBag Invoked successfully (Server returned no data).")
                                else
                                    print("ClaimTreatBag Invoked successfully. Server response:", tostring(result))
                                end
                            else
                                warn("ClaimTreatBag Invocation Failed. Error:", tostring(result))
                            end
                            task.wait(5)
                        end
                    end)
                end
            end
        })

        -- 8. AutoProgressKittyBats (Taming)
        AutoProgressKittyBatsToggle = EventTab:CreateToggle({
            Name = "Auto Progress Kitty Bats (Taming)",
            CurrentValue = autoProgressKittyBatsEnabled,
            Flag = "AutoProgressKittyBatsToggle",
            Callback = function(val)
                autoProgressKittyBatsEnabled = val
                if val then
                    task.spawn(function()
                        local progressRemote = game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("HalloweenEventAPI/ProgressTaming")
                        while autoProgressKittyBatsEnabled do
                            local success, result = pcall(progressRemote.InvokeServer, progressRemote)
                            if success then
                                if result == nil then
                                    print("ProgressTaming Invoked successfully (Server returned no data).")
                                else
                                    print("ProgressTaming Invoked successfully. Server response:", tostring(result))
                                end
                            else
                                warn("ProgressTaming Invocation Failed. Error:", tostring(result))
                            end
                            task.wait(5)
                        end
                    end)
                end
            end
        })
    end
end

-- NEW: Function to create the Visual Tab UI (ensuring all labels are created)
local function createVisualTabUI()
    local FIX_TEXT_COLOR = Color3.fromRGB(30, 30, 30)
    -- Only create the static labels once
    if not VisualTab_MainEventTimerLabel then
        VisualTab:CreateLabel(
            "--- Real-time Game Data Monitor ---", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )

        VisualTab_MainEventTimerLabel = VisualTab:CreateLabel(
            "Main Event Timer: Loading...", 
            "clock", 
            FIX_TEXT_COLOR,
            false
        )
        VisualTab_FashionTimerLabel = VisualTab:CreateLabel(
            "Fashion Frenzy Timer: Loading...", 
            "sparkles", 
            FIX_TEXT_COLOR,
            false
        )
        VisualTab_HauntletTimerLabel = VisualTab:CreateLabel(
            "Hauntlet Minigame Timer: Loading...", 
            "skull", 
            FIX_TEXT_COLOR,
            false
        )
        VisualTab_CandyAmountLabel = VisualTab:CreateLabel(
            "Halloween Currency (Candy): N/A", 
            "star", -- Changed from 'coin' as it's not strictly bucks/robux
            FIX_TEXT_COLOR,
            false
        )
        VisualTab_BucksAmountLabel = VisualTab:CreateLabel(
            "Bucks Currency: N/A", 
            "dollar-sign", 
            FIX_TEXT_COLOR,
            false
        )
    end
    -- Start the monitoring loop ONCE after all UI is created.
    if not _VISUAL_MONITOR_TASK then
        print("Starting Visual Data Monitor loop...")
        _VISUAL_MONITOR_TASK = task.spawn(monitorVisualData)
    end
end

local function createOrUpdateUIData(dataToUse)
    -- Reset maps
    uniqueIdToPetDataMap = {}
    uniqueIdToPetDisplayStringMap = {}
    uniqueIdToFoodDataMap = {}
    uniqueIdToFoodDisplayStringMap = {}
    uniqueIdToGiftDataMap = {}
    uniqueIdToGiftDisplayStringMap = {}

    local currentPlayerData = dataToUse and dataToUse[targetPlayerName]

    -- Pet dropdown population
    local petDropdownOptions = {"No pets found"}
    local initialPetOption = "No pets found"
    local newSelectedPetUid = nil
    local neonFusionOptions = {"Select a pet species for fusion"}
    local initialNeonFusionOption = "Select a pet species for fusion"
    if currentPlayerData and currentPlayerData.inventory and currentPlayerData.inventory.pets then
        local pets = currentPlayerData.inventory.pets
        if next(pets) then
            petDropdownOptions = {}
            local uniqueSpeciesForNeon = {}
            for uid, pet in pairs(pets) do
                -- FIX: Changed display format to improve visibility in Rayfield dropdown
                local display = getDisplayId(pet.id) .. " | UID: " .. tostring(uid) 
                table.insert(petDropdownOptions, display)
                uniqueIdToPetDataMap[tostring(uid)] = {uniqueId=uid, speciesId=pet.id, fullData=pet}
                uniqueIdToPetDisplayStringMap[tostring(uid)] = display
                if not newSelectedPetUid then
                    newSelectedPetUid = tostring(uid)
                    initialPetOption = display
                end
                if not uniqueSpeciesForNeon[pet.id] then
                    table.insert(neonFusionOptions, getDisplayId(pet.id))
                    uniqueSpeciesForNeon[pet.id] = true
                end
            end
            table.sort(neonFusionOptions, function(a, b) return a < b end)
            table.insert(neonFusionOptions, 1, "Select a pet species for fusion")
        end
    end
    if currentlySelectedPetUniqueId and uniqueIdToPetDisplayStringMap[currentlySelectedPetUniqueId] then
        initialPetOption = uniqueIdToPetDisplayStringMap[currentlySelectedPetUniqueId]
    else
        currentlySelectedPetUniqueId = newSelectedPetUid
    end

    -- Neon fusion initial selection
    if selectedNeonPetSpeciesId then
        local found = false
        for _, option in ipairs(neonFusionOptions) do
            if option == selectedNeonPetSpeciesId then
                initialNeonFusionOption = option
                found = true
                break
            end
        end
        if not found then
            selectedNeonPetSpeciesId = nil
            initialNeonFusionOption = "Select a pet species for fusion"
        end
    end

    -- Food dropdown population
    local foodOptions = {"No food found"}
    local initialFoodOption = "No food found"
    if currentPlayerData and currentPlayerData.inventory and currentPlayerData.inventory.food then
        local foods = currentPlayerData.inventory.food
        if next(foods) then
            foodOptions = {}
            for uid, food in pairs(foods) do
                -- FIX: Changed display format to improve visibility in Rayfield dropdown
                local display = getDisplayId(food.id) .. " | UID: " .. tostring(uid)
                table.insert(foodOptions, display)
                uniqueIdToFoodDataMap[tostring(uid)] = {uniqueId=uid, itemId=food.id, fullData=food}
                uniqueIdToFoodDisplayStringMap[tostring(uid)] = display
                if initialFoodOption == "No food found" then initialFoodOption = display end
            end
        end
    end

    -- **GIFT DROPDOWN POPULATION (UPDATED WITH FILTER)**
    local giftOptions = {"No openable gifts in inventory"}
    local initialGiftOption = "No openable gifts in inventory"
    
    if currentPlayerData and currentPlayerData.inventory and currentPlayerData.inventory.gifts then
        local gifts = currentPlayerData.inventory.gifts
        if next(gifts) then
            giftOptions = {}
            local foundAny = false
            for uid, gift in pairs(gifts) do
                -- NEW FILTER: Only include items that are designated as openable gifts/boxes
                if isItemOpenableGift(gift.id) then 
                    local display = getDisplayId(gift.id) .. " | UID: " .. tostring(uid)
                    table.insert(giftOptions, display)
                    if initialGiftOption == "No openable gifts in inventory" then initialGiftOption = display end
                    foundAny = true
                    -- Populate the uniqueIdToGiftDataMap for AutoOpenBox feature
                    uniqueIdToGiftDataMap[tostring(uid)] = {uniqueId=uid, itemId=gift.id, fullData=gift}
                end
            end
            if not foundAny then
                giftOptions = {"No openable gifts in inventory"}
                initialGiftOption = "No openable gifts in inventory"
            end
        end
    end
    -- --- Create or Update UI Elements ---
    local FIX_TEXT_COLOR = Color3.fromRGB(30, 30, 30)

    -- PetTab Elements
    if not PetDropdown then
        PetDropdown = PetTab:CreateDropdown({
            Name = "Select Pet",
            Options = petDropdownOptions,
            CurrentOption = {initialPetOption},
            MultipleOptions = false,
            Flag = "PetDropdownSelection",
            Callback = function(selectedOptions)
                local selected = selectedOptions[1]
                local targetUid = nil
                if type(selected) == "string" then
                    -- FIX: Updated match pattern to reflect new display format
                    local match = selected:match("| UID: ([%w_]+)") 
                    if match then targetUid = match end
                end
                currentlySelectedPetUniqueId = targetUid
                local petInfo = uniqueIdToPetDataMap[targetUid]
                local displayName = uniqueIdToPetDisplayStringMap[targetUid] or "Unknown Pet"
                if petInfo then
                    print("--- Selected Pet ---")
                    print("Name: " .. displayName)
                    
                    local petUniqueId = petInfo.uniqueId
                    local equipOptions = {use_sound_delay=false, equip_as_last=false}
                    local args = {petUniqueId, equipOptions}
                    
                    pcall(function()
                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/Equip"):InvokeServer(unpack(args))
                    end)
                    
                    if SelectedPetAgeLabel then
                        SelectedPetAgeLabel:Set("Selected Pet Age: " .. tostring(petInfo.fullData.age or "N/A"))
                    end
                else
                    if SelectedPetAgeLabel then
                        SelectedPetAgeLabel:Set("Selected Pet Age: N/A")
                    end
                end
            end
        })
    elseif PetDropdown.UpdateOptions and PetDropdown.Set then
        PetDropdown:UpdateOptions(petDropdownOptions)
        PetDropdown:Set(initialPetOption)
    end

    -- ** Auto Claim Quest Toggle **
    if not AutoClaimQuestToggle then
        AutoClaimQuestToggle = PetTab:CreateToggle({
            Name = "Auto Claim Quests (Loop)",
            CurrentValue = autoClaimQuestEnabled,
            Flag = "AutoClaimQuestToggle",
            Callback = function(val)
                autoClaimQuestEnabled = val
                
                if currentQuestClaimTask then
                    task.cancel(currentQuestClaimTask)
                    currentQuestClaimTask = nil
                end

                if val then
                    -- Execute quest_manager.lua FIRST
                    loadExternalScript("QuestManager", 'https://raw.githubusercontent.com/AdoptmeEvent/AdoptME-Halloween/refs/heads/main/quest_manager.lua', AutoClaimQuestToggle)
                    
                    print("Starting Auto Quest Claim loop...")
                    currentQuestClaimTask = task.spawn(function()
                        while autoClaimQuestEnabled do
                            claimAllQuests()
                            task.wait(5) -- Wait 5 seconds between claim attempts
                        end
                        currentQuestClaimTask = nil
                        print("Auto Quest Claim loop stopped.")
                    end)
                end
            end
        })
    end

    -- ** New Pet Farm Toggle in PetTab (FIXED GUARD) **
    if not PetFarmComingSoonToggle then
        PetFarmComingSoonToggle = PetTab:CreateToggle({ -- Assign to the guard variable
            Name = "Pet Farm Coming Soon!",
            CurrentValue = false,
            Flag = "PetFarmComingSoon",
            Callback = function(val)
                if val then
                    warn("Pet Farm: This feature is not yet implemented.")
                end
            end
        })
    end
    
    -- ** Open Pet Pen UI Toggle **
    if not OpenPetPenUIToggle then
        OpenPetPenUIToggle = PetTab:CreateToggle({
            Name = "Open PetPenUI",
            CurrentValue = false,
            Flag = "OpenPetPenUIToggle",
            Callback = function(val)
                local PET_PEN_URL = 'https://raw.githubusercontent.com/AdoptmeEvent/PetPenUpdate-/refs/heads/main/AdoptMe!.lua'
                if val then
                    loadExternalScript("PetPenUI", PET_PEN_URL, OpenPetPenUIToggle)
                end
            end
        })
    end


    -- Utility & Auto-Buy Tab Elements
    ExtraTab:CreateLabel(
        "--- Pet Utilities ---", 
        "info", 
        FIX_TEXT_COLOR,
        true
    )

    if not SelectedPetAgeLabel then
        SelectedPetAgeLabel = ExtraTab:CreateLabel(
            "Selected Pet Age: N/A", 
            "info", 
            FIX_TEXT_COLOR,
            false
        )
        if currentlySelectedPetUniqueId and uniqueIdToPetDataMap[currentlySelectedPetUniqueId] then
            SelectedPetAgeLabel:Set("Selected Pet Age: " .. tostring(uniqueIdToPetDataMap[currentlySelectedPetUniqueId].fullData.age or "N/A"))
        end
    end

    if not FoodDropdown then
        FoodDropdown = ExtraTab:CreateDropdown({
            Name = "Select Food (Equips on Select)",
            Options = foodOptions,
            CurrentOption = {initialFoodOption},
            MultipleOptions = false,
            Flag = "FoodDropdownSelection",
            Callback = function(selectedOptions)
                local selected = selectedOptions[1]
                local targetUid = nil
                
                -- FIX: Updated match pattern to reflect new display format
                local match = selected:match("| UID: ([%w_]+)")
                if match then targetUid = match end

                if targetUid then
                    local args = {
                        targetUid,
                        {
                            use_sound_delay = false,
                            equip_as_last = false
                        }
                    }
                    pcall(function()
                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/Equip"):InvokeServer(unpack(args))
                    end)
                    print("Equipped Food/Potion with UID:", targetUid)
                end
            end
        })
    elseif FoodDropdown.UpdateOptions and FoodDropdown.Set then
        FoodDropdown:UpdateOptions(foodOptions)
        FoodDropdown:Set(initialFoodOption)
    end

    -- --- AGE POTION ELEMENTS ---
    if not PotionDelaySlider then
        PotionDelaySlider = ExtraTab:CreateSlider({
            Name = "Potion Use Delay (Seconds)",
            Range = {0.1, 10},
            Increment = 0.1,
            CurrentValue = potionUseDelay,
            Compact = false,
            Flag = "PotionDelaySlider",
            Callback = function(val) potionUseDelay=val end,
        })
    end

    if not AutoAgeToggle then
        AutoAgeToggle = ExtraTab:CreateToggle({
            Name = "Enable Auto Age-Potion (Use All)",
            CurrentValue = autoGiveAgePotionEnabled,
            Flag = "AutoAgeToggle",
            Callback = function(val)
                autoGiveAgePotionEnabled = val
                if val then
                    task.spawn(function()
                        while autoGiveAgePotionEnabled do
                            local stopAndReset = false
                            
                            if not currentlySelectedPetUniqueId then stopAndReset = true end
                            local data = getLatestServerData()
                            if not data then stopAndReset = true end
                            local foods = data and data[targetPlayerName] and data[targetPlayerName].inventory and data[targetPlayerName].inventory.food
                            if not foods and not stopAndReset then stopAndReset = true end
                            
                            if stopAndReset then
                                stopAutoAgePotionFeature()
                                break
                            end
                            
                            local agePotions = {}
                            for uid, food in pairs(foods) do
                                if food.id == "pet_age_potion" then
                                    table.insert(agePotions, tostring(uid))
                                end
                            end
                            
                            if #agePotions > 0 then
                                local firstUID = table.remove(agePotions, 1)
                                local additionalUids = agePotions
                                local args = {
                                    "__Enum_PetObjectCreatorType_2",
                                    {
                                        additional_consume_uniques = additionalUids,
                                        pet_unique = currentlySelectedPetUniqueId,
                                        unique_id = firstUID
                                    }
                                }
                                pcall(function()
                                    game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("PetObjectAPI/CreatePetObject"):InvokeServer(unpack(args))
                                end)
                            else
                                stopAutoAgePotionFeature()
                                break
                            end
                            
                            wait(potionUseDelay)
                        end
                    end)
                end
            end
        })
    end
    -- --- END AGE POTION ---

    -- Neon Fusion
    if not NeonFusionPetDropdown then
        NeonFusionPetDropdown = ExtraTab:CreateDropdown({
            Name = "Select Pet Species for Neon Fusion",
            Options = neonFusionOptions,
            CurrentOption = {initialNeonFusionOption},
            MultipleOptions = false,
            Flag = "NeonFusionPetSelection",
            Callback = function(selectedOptions)
                local selected = selectedOptions[1]
                if selected and selected ~= "Select a pet species for fusion" then
                    selectedNeonPetSpeciesId = selected
                else
                    selectedNeonPetSpeciesId = nil
                end
            end
        })
    elseif NeonFusionPetDropdown.UpdateOptions and NeonFusionPetDropdown.Set then
        NeonFusionPetDropdown:UpdateOptions(neonFusionOptions)
        NeonFusionPetDropdown:Set(initialNeonFusionOption)
    end

    if not AutoNeonToggle then
        AutoNeonToggle = ExtraTab:CreateToggle({
            Name = "Enable Auto Neon Fusion",
            CurrentValue = autoNeonEnabled,
            Flag = "AutoNeonToggle",
            Callback = function(val)
                autoNeonEnabled = val
                if val then
                    task.spawn(function()
                        while autoNeonEnabled do
                            local stopAndReset = false
                            if not selectedNeonPetSpeciesId then stopAndReset = true end
                            local data = getLatestServerData()
                            if not data and not stopAndReset then stopAndReset = true end
                            local petsInInventory = data and data[targetPlayerName] and data[targetPlayerName].inventory and data[targetPlayerName].inventory.pets
                            if not petsInInventory and not stopAndReset then stopAndReset = true end

                            if stopAndReset then
                                stopAutoNeonFeature()
                                break
                            end

                            local petsOfSelectedSpecies = {}
                            for uid, pet in pairs(petsInInventory) do
                                if pet.id == selectedNeonPetSpeciesId then
                                    table.insert(petsOfSelectedSpecies, tostring(uid))
                                end
                            end
                            
                            if #petsOfSelectedSpecies >= 4 then
                                local fusionPetUids = {}
                                for i = 1, 4 do
                                    table.insert(fusionPetUids, table.remove(petsOfSelectedSpecies, 1))
                                end
                                pcall(function()
                                    game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("PetAPI/DoNeonFusion"):InvokeServer(fusionPetUids)
                                end)
                            end
                            wait(2)
                        end
                    end)
                end
            end
        })
    end

    -- Box/Gift Selection (Now integrated here)
    ExtraTab:CreateLabel(
        "--- Gift/Box Management ---", 
        "gift", 
        FIX_TEXT_COLOR,
        true
    )

    if not GiftDropdown then
        GiftDropdown = ExtraTab:CreateDropdown({
            Name = "Select Gift/Box",
            Options = giftOptions,
            CurrentOption = initialGiftOption,
            MultipleOptions = false,
            Flag = "GiftDropdown",
            Callback = function(selectedOptions)
                local selected = selectedOptions[1]
                local targetUid = nil
                
                local match = selected:match("UID: ([%w_]+)") 
                if match then targetUid = match end

                if targetUid then
                    local args = {
                        targetUid,
                        {
                            use_sound_delay = false,
                            equip_as_last = false
                        }
                    }
                    -- Equip the gift/box when selected
                    pcall(function()
                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/Equip"):InvokeServer(unpack(args))
                    end)
                    print("Equipped Gift/Box with UID:", targetUid)
                end
            end
        })
    elseif GiftDropdown.UpdateOptions and GiftDropdown.Set then
        GiftDropdown:UpdateOptions(giftOptions)
        GiftDropdown:Set(initialGiftOption)
    end

    -- Auto Open Box toggle
    if not AutoOpenBoxToggle then
        AutoOpenBoxToggle = ExtraTab:CreateToggle({
            Name = "Auto Open ALL Gifts/Boxes in Inventory",
            CurrentValue = autoOpenGiftBoxEnabled, -- Updated state variable name
            Flag = "AutoOpenBox",
            Callback = function(val)
                autoOpenGiftBoxEnabled = val -- Updated state variable name
                if val then
                    task.spawn(function()
                        -- CRITICAL LIST: The default boxes that also require the LootBoxAPI call
                        local boxIDsThatNeedLootAPI = {"summerfest_2025_kelp_raider_box", "halloween_2025_spider_box"}
                        while autoOpenGiftBoxEnabled do
                            local stopAndReset = false
                            local data = getLatestServerData()
                            if not data then stopAndReset = true end
                            local gifts = data and data[targetPlayerName] and data[targetPlayerName].inventory and data[targetPlayerName].inventory.gifts
                            if not gifts and not stopAndReset then stopAndReset = true end
                            
                            if stopAndReset then
                                stopAutoOpenBoxFeature()
                                break
                            end

                            local giftsToOpen = {}
                            for uid, gift in pairs(gifts) do
                                -- Include ONLY items that are on the openable safelist
                                if isItemOpenableGift(gift.id) then
                                    table.insert(giftsToOpen, tostring(uid))
                                end
                            end
                            
                            if #giftsToOpen > 0 then
                                for _, uidToOpen in ipairs(giftsToOpen) do
                                    local giftData = uniqueIdToGiftDataMap[uidToOpen]
                                    local itemId = giftData and giftData.itemId or nil
                                    
                                    pcall(function()
                                        local cframe = CFrame.new(-2981.871, 4000.5, -9020.676, -0.879, 0, -0.477, 0, 1, 0, 0.477, 0, -0.879)
                                        
                                        -- 1. Equip the item
                                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/Equip"):InvokeServer({uidToOpen, {spawn_cframe = cframe, use_sound_delay=false, equip_as_last=false}})
                                        wait(0.2)
                                        
                                        -- 2. Use tool start
                                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/ServerUseTool"):FireServer({uidToOpen, "START"})
                                        wait(0.2)
                                        
                                        -- 3. Unequip
                                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/Unequip"):InvokeServer(uidToOpen)
                                        wait(0.2)
                                        
                                        -- 4. Use tool end
                                        game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ToolAPI/ServerUseTool"):FireServer({uidToOpen, "END"})
                                        wait(0.2)
                                        
                                        -- 5. Loot API call (only for specific boxes)
                                        if itemId and table.find(boxIDsThatNeedLootAPI, itemId) then
                                            print("Attempting LootBoxAPI/ExchangeItemForReward for:", itemId)
                                            -- NOTE: We use the actual itemId for the ExchangeItemForReward API call
                                            game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("LootBoxAPI/ExchangeItemForReward"):InvokeServer(itemId, uidToOpen)
                                        else
                                            print("Skipping LootBoxAPI for:", itemId or "Unknown Item")
                                        end
                                    end)
                                    wait(1)
                                end
                            else
                                stopAutoOpenBoxFeature()
                                break
                            end
                            wait(2)
                        end
                    end)
                end
            end
        })
    end

    -- --- Auto-Buy ---
    ExtraTab:CreateLabel(
        "--- Shop Auto-Buy ---", 
        "shopping-cart", 
        FIX_TEXT_COLOR,
        true
    )

    local autoBuyOptions = {}
    for _, item in ipairs(allBuyableItems) do
        table.insert(autoBuyOptions, item.name)
    end
    local initialAutoBuyOption = autoBuyOptions[1] or "No items available"

    if not AutoBuyItemDropdown then
        AutoBuyItemDropdown = ExtraTab:CreateDropdown({
            Name = "Select Item to Auto-Buy",
            Options = autoBuyOptions,
            CurrentOption = {initialAutoBuyOption},
            MultipleOptions = false,
            Flag = "AutoBuyItemSelection",
            Callback = function(selectedOptions)
                local selectedName = selectedOptions[1]
                local selectedItem = nil
                for _, item in ipairs(allBuyableItems) do
                    if item.name == selectedName then selectedItem = item break end
                end
                if selectedItem then
                    currentSelectedAutoBuyItemId = selectedItem.id
                    if AutoBuyAmountSlider then AutoBuyAmountSlider:Set(autoBuyCounts[currentSelectedAutoBuyItemId] or selectedItem.defaultCount) end
                    if AutoBuyGlobalToggle then AutoBuyGlobalToggle:Set(autoBuyStates[currentSelectedAutoBuyItemId] or false) end
                else
                    currentSelectedAutoBuyItemId = nil
                    if AutoBuyAmountSlider then AutoBuyAmountSlider:Set(1) end
                    if AutoBuyGlobalToggle then AutoBuyGlobalToggle:Set(false) end
                end
            end
        })
        local initialSelectedItem = allBuyableItems[1]
        if initialSelectedItem then
            currentSelectedAutoBuyItemId = initialSelectedItem.id
            if AutoBuyAmountSlider then
                AutoBuyAmountSlider:Set(autoBuyCounts[currentSelectedAutoBuyItemId] or initialSelectedItem.defaultCount)
            end
        end
    elseif AutoBuyItemDropdown.UpdateOptions and AutoBuyItemDropdown.Set then
        AutoBuyItemDropdown:UpdateOptions(autoBuyOptions)
        AutoBuyItemDropdown:Set(initialAutoBuyOption)
    end

    if not AutoBuyAmountSlider then
        AutoBuyAmountSlider = ExtraTab:CreateSlider({
            Name = "Amount to Buy (Selected Item)",
            Range = {1, 100},
            Increment = 1,
            CurrentValue = (currentSelectedAutoBuyItemId and autoBuyCounts[currentSelectedAutoBuyItemId]) or 1,
            Compact = false,
            Flag = "AutoBuyAmountSlider",
            Callback = function(val)
                if currentSelectedAutoBuyItemId then
                    autoBuyCounts[currentSelectedAutoBuyItemId] = val
                end
            end,
        })
    elseif AutoBuyAmountSlider.Set then
        if currentSelectedAutoBuyItemId then
            AutoBuyAmountSlider:Set(autoBuyCounts[currentSelectedAutoBuyItemId])
        end
    end

    if not AutoBuyGlobalToggle then
        AutoBuyGlobalToggle = ExtraTab:CreateToggle({
            Name = "Enable Auto-Buy (Selected Item)",
            CurrentValue = (currentSelectedAutoBuyItemId and autoBuyStates[currentSelectedAutoBuyItemId]) or false,
            Flag = "AutoBuyGlobalToggle",
            Callback = function(val)
                if val then
                    for itemId, isBuying in pairs(autoBuyStates) do
                        if isBuying and itemId ~= currentSelectedAutoBuyItemId then
                            autoBuyStates[itemId] = false
                        end
                    end
                end

                if currentAutoBuyTask then 
                    task.cancel(currentAutoBuyTask)
                    currentAutoBuyTask = nil
                end
                
                autoBuyStates[currentSelectedAutoBuyItemId] = val

                if val then
                    local itemToBuy = nil
                    for _, item in ipairs(allBuyableItems) do
                        if item.id == currentSelectedAutoBuyItemId then itemToBuy = item break end 
                    end
                    
                    if not itemToBuy then 
                        warn("Auto-Buy failed: Item data not found for ID:", currentSelectedAutoBuyItemId)
                        stopAutoBuyFeature(currentSelectedAutoBuyItemId) 
                        return 
                    end
                    
                    print("Starting Auto-Buy for:", itemToBuy.name, "(ID:", itemToBuy.id .. ")")

                    currentAutoBuyTask = task.spawn(function()
                        while autoBuyStates[itemToBuy.id] do
                            local buyCount = autoBuyCounts[itemToBuy.id] or itemToBuy.defaultCount
                            local success, err = pcall(function()
                                local args = { itemToBuy.category, itemToBuy.id, { buy_count = buyCount } }
                                game:GetService("ReplicatedStorage"):WaitForChild("API"):WaitForChild("ShopAPI/BuyItem"):InvokeServer(unpack(args))
                            end)
                            
                            if not success then
                                warn("BuyItem InvokeServer failed:", tostring(err))
                                stopAutoBuyFeature(itemToBuy.id)
                                break
                            else
                                print("Successfully sent BuyItem request for " .. tostring(buyCount) .. "x " .. itemToBuy.name)
                            end
                            wait(5)
                        end
                        currentAutoBuyTask = nil
                    end)
                end
            end
        })
    elseif AutoBuyGlobalToggle.Set then
        if currentSelectedAutoBuyItemId then
            AutoBuyGlobalToggle:Set(autoBuyStates[currentSelectedAutoBuyItemId])
        end
    end

    if not RefreshButton then
        RefreshButton = ExtraTab:CreateButton({
            Name = "Refresh All Data",
            Callback = function()
                local data = getLatestServerData()
                if data then createOrUpdateUIData(data) end
            end,
        })
    end
    
    -- Call creation functions to ensure they run at least once
    createVisualTabUI()
    createEventTabUI()
    
    -- =======================
    -- ReleaseNotes Tab Elements (FIXED GUARD)
    if not ReleaseNotesHeaderLabel then
        ReleaseNotesHeaderLabel = ReleaseNotesTab:CreateLabel(
            "--- Release Notes (v" .. VERSION .. ") ---", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )
        ReleaseNotesTab:CreateLabel(
            "2025/10/18 (v1.0.19) - FIX: Changed UID display format from 'Name (Unique ID: UID)' to 'Name | UID: UID' to prevent the Rayfield dropdown UI from truncating the ID.", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )
        ReleaseNotesTab:CreateLabel(
            "2025/10/18 (v1.0.20) - FEATURE: The 'Select Gift/Box' dropdown and the 'Auto Open' toggle now include **all gift items** found in your inventory, making it much more versatile for opening any kind of reward/gift item.", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )
        ReleaseNotesTab:CreateLabel(
            "2025/10/18 (v1.0.21) - **CLARIFICATION**: Confirmed that the 'Select Gift/Box' dropdown ONLY uses your player inventory. Shop items are in the separate 'Shop Auto-Buy' section.", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )
        ReleaseNotesTab:CreateLabel(
            "2025/10/18 (v" .. VERSION .. ") - **FIX**: Implemented an internal safelist filter on the **Select Gift/Box** dropdown to exclude non-openable items (like the Haunted Piano) that the game incorrectly places in your 'gifts' inventory.", 
            "info", 
            FIX_TEXT_COLOR,
            true
        )
    end
end

-- Initial data load
local initialServerData = getLatestServerData()
createOrUpdateUIData(initialServerData)

Rayfield:LoadConfiguration()
