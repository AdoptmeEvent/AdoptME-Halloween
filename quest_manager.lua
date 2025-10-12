--[[
    INTERACTIVE QUEST CLAIM UI
    
    This LocalScript creates an interactive UI to display and individually 
    claim active quests by reading the game's ClientData module.
    
    PLACE THIS SCRIPT IN: StarterPlayerScripts
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local task = task -- Use the modern task library

-- Define constants based on our successful inspection
local ModulePath = "ClientModules.Core.ClientData" 
-- Dynamically set the parent key to the local player's name
local PARENT_KEY = LocalPlayer.Name 
local QUEST_MANAGER_KEY = "quest_manager"
local CACHED_QUESTS_KEY = "quests_cached"

-- FIX: The literal name of the RemoteFunction, as indicated by the user's structure.
local QUEST_CLAIM_API_NAME = "QuestAPI/ClaimQuest" 
local QUEST_CLAIM_API_PATH = "API/" .. QUEST_CLAIM_API_NAME

-- Global State for Auto-Claim Loop
local IsLoopRunning = false
local AutoClaimThread = nil

-- Global reference to the API RemoteFunction
local QuestAPI = nil
local Success, FoundAPI = pcall(function()
    -- FIX: Access the "API" folder first, then search for the full, combined name inside it.
    local API_Folder = ReplicatedStorage:WaitForChild("API", 5)
    
    -- Check if the API_Folder exists before trying to access its children
    if API_Folder then
        return API_Folder:WaitForChild(QUEST_CLAIM_API_NAME, 5)
    end
    return nil -- If API folder wasn't found, return nil
end)

if Success and FoundAPI and FoundAPI:IsA("RemoteFunction") then
    QuestAPI = FoundAPI
    print("[INIT] QuestAPI RemoteFunction found successfully.")
else
    -- Fallback warning now uses the correct full path string for clarity
    warn("ERROR: QuestAPI RemoteFunction not found at path 'ReplicatedStorage." .. QUEST_CLAIM_API_PATH .. "'. Claiming will not be functional.")
end

-- Function to handle the actual server invocation for a single or multiple ID(s)
local function handleClaim(uuid_or_table)
    if not QuestAPI then
        warn("[CLAIM] Cannot claim: QuestAPI RemoteFunction is missing.")
        return false
    end
    
    local args = {}
    if typeof(uuid_or_table) == "table" then
        args = uuid_or_table
    else
        table.insert(args, uuid_or_table)
    end
    
    if #args == 0 then return end
    
    print(string.format("[CLAIM] Attempting to claim %d quest(s)...", #args))
    
    local success, result = pcall(QuestAPI.InvokeServer, QuestAPI, unpack(args))
    
    if success then
        print(string.format("[CLAIM] Claim attempt finished. Server result: %s", tostring(result)))
        return result
    else
        warn("[CLAIM] Claim failed due to pcall error:", result)
        return false
    end
end

-- Function to fetch and process quest data
local function getActiveQuests()
    -- UPDATED: New initial loading message
    print(string.format("loading %s from clients data...", QUEST_MANAGER_KEY))
    local CurrentObject = ReplicatedStorage
    for i, name in ipairs(ModulePath:split(".")) do
        local nextObject = CurrentObject:FindFirstChild(name)
        if nextObject then
            CurrentObject = nextObject
        else
            warn("[DATA FETCH] Error: Path component '" .. name .. "' not found. Failed to locate module.")
            return nil
        end
    end
    local FullPath = CurrentObject

    local success, requiredModule = pcall(require, FullPath)
    if not success or typeof(requiredModule) ~= "table" then 
        warn("[DATA FETCH] Error: Failed to require module.")
        return nil 
    end
    
    -- UPDATED: New success message & Added task.wait(1)
    print(string.format("loaded %s %s!", QUEST_MANAGER_KEY, CACHED_QUESTS_KEY))
    task.wait(1) -- Pause to ensure the log is visible

    local getDataFunction = requiredModule.get_data
    if typeof(getDataFunction) ~= "function" then
        warn("[DATA FETCH] Error: Module does not have a 'get_data' function.")
        return nil 
    end
    
    local callSuccess, result = pcall(getDataFunction)
    if not callSuccess or typeof(result) ~= "table" then 
        warn("[DATA FETCH] Error: Failed to call get_data().")
        return nil 
    end
    print("[DATA FETCH] get_data() called successfully.")
    print(string.format("[DATA FETCH] Using PARENT_KEY: '%s'", PARENT_KEY)) -- New log for player name

    -- Safely access the deeply nested table
    local parentData = result[PARENT_KEY]
    local managerData = parentData and parentData[QUEST_MANAGER_KEY]
    local questData = managerData and managerData[CACHED_QUESTS_KEY]
    
    if not parentData then
        warn(string.format("[DATA FETCH] Failed: Missing PARENT_KEY ('%s'). Check if the key is the Player.Name.", PARENT_KEY))
    elseif not managerData then
        warn(string.format("[DATA FETCH] Failed: Missing QUEST_MANAGER_KEY ('%s') inside parent.", QUEST_MANAGER_KEY))
    elseif not questData then
        warn(string.format("[DATA FETCH] Failed: Missing CACHED_QUESTS_KEY ('%s') inside manager.", CACHED_QUESTS_KEY))
    end
    
    if typeof(questData) == "table" then
        local questList = {}
        for uuid, data in pairs(questData) do
            -- Collect the ID and relevant display data
            table.insert(questList, {
                id = uuid,
                name = data.entry_name or "Unknown Quest",
                steps = data.steps_completed or 0
            })
        end
        print(string.format("[DATA FETCH] Successfully retrieved %d active quests.", #questList))
        return questList
    end
    
    return nil
end

-- Function to populate the UI with quest data
-- FIX: Changed definition style to guarantee scope resolution within the startAutoClaimLoop coroutine.
local populateQuests = function(QuestScrollFrame)
    -- Clear old quests
    for _, child in pairs(QuestScrollFrame:GetChildren()) do
        if child.Name == "QuestItem" or child.Name == "NoQuestsLabel" then child:Destroy() end
    end
    
    local quests = getActiveQuests()
    
    if not quests or #quests == 0 then
        local Label = Instance.new("TextLabel")
        Label.Name = "NoQuestsLabel" -- Added Name for clarity
        Label.Text = "No Active Quests Found (Or Data Fetch Failed)."
        Label.Size = UDim2.new(1, 0, 0, 30)
        Label.BackgroundColor3 = Color3.fromRGB(60, 40, 40) -- Made background redder for visibility
        Label.TextColor3 = Color3.fromRGB(255, 200, 200)
        Label.Font = Enum.Font.Arial
        Label.TextSize = 14
        Label.Parent = QuestScrollFrame
        print("[UI POPULATION] Displaying 'No Quests Found' message.")
        return
    end

    for _, quest in ipairs(quests) do
        local ItemFrame = Instance.new("Frame")
        ItemFrame.Name = "QuestItem"
        ItemFrame.Size = UDim2.new(1, -8, 0, 50)
        ItemFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        ItemFrame.BorderSizePixel = 0
        ItemFrame.Parent = QuestScrollFrame
        
        -- FIX: Store the ID in a StringValue instead of a custom property on the Frame
        local IdValue = Instance.new("StringValue")
        IdValue.Name = "QuestId"
        IdValue.Value = quest.id -- Store the actual quest ID here
        IdValue.Parent = ItemFrame
        
        -- Add UICorner for rounded corners on ItemFrame
        local ItemFrameCorner = Instance.new("UICorner")
        ItemFrameCorner.CornerRadius = UDim.new(0, 8)
        ItemFrameCorner.Parent = ItemFrame
        
        -- Quest Name & Progress
        local InfoLabel = Instance.new("TextLabel")
        -- FIX: Show the UUID (quest.id) and the friendly name (quest.name)
        InfoLabel.Text = string.format("%s (Name: %s | Progress: %d)", quest.id, quest.name, quest.steps)
        InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
        InfoLabel.Size = UDim2.new(0.7, -10, 1, 0)
        InfoLabel.Position = UDim2.new(0, 5, 0, 0)
        InfoLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        InfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        InfoLabel.Font = Enum.Font.Arial
        InfoLabel.TextSize = 14
        InfoLabel.Parent = ItemFrame

        -- Claim Button
        local ClaimButton = Instance.new("TextButton")
        ClaimButton.Name = "ClaimButton"
        ClaimButton.Text = "CLAIM"
        ClaimButton.Size = UDim2.new(0.3, -10, 0, 40)
        ClaimButton.Position = UDim2.new(0.7, 5, 0, 5)
        ClaimButton.BackgroundColor3 = Color3.fromRGB(70, 120, 180)
        ClaimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        ClaimButton.Font = Enum.Font.Arial
        ClaimButton.TextSize = 16
        ClaimButton.BorderSizePixel = 0
        ClaimButton.Parent = ItemFrame
        
        -- Add UICorner for rounded corners on ClaimButton
        local ClaimButtonCorner = Instance.new("UICorner")
        ClaimButtonCorner.CornerRadius = UDim.new(0, 8)
        ClaimButtonCorner.Parent = ClaimButton
        
        ClaimButton.MouseButton1Click:Connect(function()
            -- We retrieve the ID from the StringValue for robustness
            local targetId = ItemFrame:FindFirstChild("QuestId").Value
            local success = handleClaim(targetId) 
            if success then
                ItemFrame.BackgroundColor3 = Color3.fromRGB(30, 80, 30) -- Visual feedback
                ClaimButton.Text = "CLAIMED"
                ClaimButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                ClaimButton.Active = false -- Disable further clicking
            else
                ItemFrame.BackgroundColor3 = Color3.fromRGB(80, 30, 30) -- Visual feedback
            end
        end)
    end
end

-- Function to run the auto-claim loop
local function startAutoClaimLoop(questScrollFrame)
    local function loop()
        while IsLoopRunning do
            -- Line 182 is here: populateQuests(questScrollFrame)
            -- We should repopulate the quests before claiming to ensure we have the latest IDs
            populateQuests(questScrollFrame)
            
            local allIds = {}
            -- Iterate and retrieve the ID from the child StringValue
            for _, item in pairs(questScrollFrame:GetChildren()) do
                if item.Name == "QuestItem" then
                    local idValue = item:FindFirstChild("QuestId")
                    if idValue and idValue:IsA("StringValue") then
                        table.insert(allIds, idValue.Value) -- Get ID from the StringValue
                    end
                end
            end

            if #allIds > 0 then
                print(string.format("[AUTO-CLAIM] Attempting to claim %d quest(s) in loop...", #allIds))
                handleClaim(allIds)
            else
                print("[AUTO-CLAIM] No quests available to claim. Waiting 5s...")
            end
            
            -- Wait 5 seconds before trying again
            task.wait(5)
        end
        print("[AUTO-CLAIM] Loop stopped.")
    end
    
    AutoClaimThread = coroutine.wrap(loop)
    AutoClaimThread()
    print("[AUTO-CLAIM] Loop started.")
end

-- Function to build the UI
local function createQuestClaimUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "QuestClaimUI"
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 400, 0, 550) -- Increased height for new button
    MainFrame.Position = UDim2.new(0.5, -200, 0.5, -275)
    MainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    MainFrame.BorderSizePixel = 0
    
    -- Add UICorner for rounded corners on MainFrame
    local MainFrameCorner = Instance.new("UICorner")
    MainFrameCorner.CornerRadius = UDim.new(0, 12)
    MainFrameCorner.Parent = MainFrame
    
    MainFrame.Parent = ScreenGui
    
    -- Title
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Text = "Active Quest Manager"
    Title.Size = UDim2.new(1, 0, 0, 40)
    Title.Position = UDim2.new(0, 0, 0, 0)
    Title.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.Font = Enum.Font.Arial
    Title.TextSize = 18
    Title.BorderSizePixel = 0
    Title.Parent = MainFrame

    -- Scroll Frame for Quest List
    local QuestScrollFrame = Instance.new("ScrollingFrame")
    QuestScrollFrame.Name = "QuestScrollFrame"
    QuestScrollFrame.Size = UDim2.new(1, -20, 1, -170) -- Adjusted height
    QuestScrollFrame.Position = UDim2.new(0, 10, 0, 50)
    QuestScrollFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    QuestScrollFrame.BorderSizePixel = 0
    QuestScrollFrame.Parent = MainFrame
    
    local ListLayout = Instance.new("UIListLayout")
    ListLayout.Name = "ListLayout"
    ListLayout.Padding = UDim.new(0, 8)
    ListLayout.Parent = QuestScrollFrame

    -- Button Container (Bottom)
    local ButtonContainer = Instance.new("Frame")
    ButtonContainer.Name = "ButtonContainer"
    ButtonContainer.Size = UDim2.new(1, 0, 0, 100) -- Increased height to fit all buttons
    ButtonContainer.Position = UDim2.new(0, 0, 1, -100)
    ButtonContainer.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    ButtonContainer.BorderSizePixel = 0
    ButtonContainer.Parent = MainFrame
    
    local ButtonLayout = Instance.new("UIListLayout")
    ButtonLayout.FillDirection = Enum.FillDirection.Vertical -- Changed to vertical layout
    ButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    ButtonLayout.Padding = UDim.new(0, 5)
    ButtonLayout.Parent = ButtonContainer
    
    -- Inner frame for horizontal buttons (Close & Claim All)
    local HorizontalFrame = Instance.new("Frame")
    HorizontalFrame.Name = "HorizontalButtons"
    HorizontalFrame.Size = UDim2.new(1, -20, 0, 30)
    HorizontalFrame.Position = UDim2.new(0, 10, 0, 5)
    HorizontalFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    HorizontalFrame.BorderSizePixel = 0
    HorizontalFrame.Parent = ButtonContainer
    
    local HorizontalLayout = Instance.new("UIListLayout")
    HorizontalLayout.FillDirection = Enum.FillDirection.Horizontal
    HorizontalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    HorizontalLayout.Padding = UDim.new(0, 10)
    HorizontalLayout.Parent = HorizontalFrame

    -- CLOSE Button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.Text = "Close UI"
    CloseButton.Size = UDim2.new(0, 100, 1, 0)
    CloseButton.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.Font = Enum.Font.Arial
    CloseButton.TextSize = 16
    CloseButton.BorderSizePixel = 0
    CloseButton.Parent = HorizontalFrame
    
    -- Add UICorner for rounded corners on CloseButton
    local CloseButtonCorner = Instance.new("UICorner")
    CloseButtonCorner.CornerRadius = UDim.new(0, 8)
    CloseButtonCorner.Parent = CloseButton
    
    CloseButton.MouseButton1Click:Connect(function()
        IsLoopRunning = false -- Stop the loop if running
        ScreenGui:Destroy() -- Destroys the whole UI
    end)
    
    -- CLAIM ALL ACTIVE Button
    local ClaimAllButton = Instance.new("TextButton")
    ClaimAllButton.Name = "ClaimAllButton"
    ClaimAllButton.Text = "Claim All Active Quests"
    ClaimAllButton.Size = UDim2.new(0, 200, 1, 0)
    ClaimAllButton.BackgroundColor3 = Color3.fromRGB(70, 150, 70)
    ClaimAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ClaimAllButton.Font = Enum.Font.Arial
    ClaimAllButton.TextSize = 16
    ClaimAllButton.BorderSizePixel = 0
    ClaimAllButton.Parent = HorizontalFrame
    
    -- Add UICorner for rounded corners on ClaimAllButton
    local ClaimAllButtonCorner = Instance.new("UICorner")
    ClaimAllButtonCorner.CornerRadius = UDim.new(0, 8)
    ClaimAllButtonCorner.Parent = ClaimAllButton
    
    ClaimAllButton.MouseButton1Click:Connect(function()
        local allIds = {}
        for _, item in pairs(QuestScrollFrame:GetChildren()) do
            if item.Name == "QuestItem" then
                local idValue = item:FindFirstChild("QuestId")
                if idValue and idValue:IsA("StringValue") then
                    table.insert(allIds, idValue.Value)
                end
            end
        end
        handleClaim(allIds)
    end)
    
    -- NEW: TOGGLE AUTO-CLAIM Button (Below the horizontal frame)
    local ToggleAutoClaimButton = Instance.new("TextButton")
    ToggleAutoClaimButton.Name = "ToggleAutoClaimButton"
    ToggleAutoClaimButton.Text = "Toggle Auto-Claim: OFF"
    ToggleAutoClaimButton.Size = UDim2.new(1, -20, 0, 40)
    ToggleAutoClaimButton.Position = UDim2.new(0, 10, 0, 40)
    ToggleAutoClaimButton.BackgroundColor3 = Color3.fromRGB(150, 40, 40) -- Default OFF (Red)
    ToggleAutoClaimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleAutoClaimButton.Font = Enum.Font.Arial
    ToggleAutoClaimButton.TextSize = 16
    ToggleAutoClaimButton.BorderSizePixel = 0
    ToggleAutoClaimButton.Parent = ButtonContainer

    local AutoClaimCorner = Instance.new("UICorner")
    AutoClaimCorner.CornerRadius = UDim.new(0, 8)
    AutoClaimCorner.Parent = ToggleAutoClaimButton
    
    ToggleAutoClaimButton.MouseButton1Click:Connect(function()
        IsLoopRunning = not IsLoopRunning -- Toggle state
        
        if IsLoopRunning then
            ToggleAutoClaimButton.Text = "Toggle Auto-Claim: ON"
            ToggleAutoClaimButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50) -- ON (Green)
            startAutoClaimLoop(QuestScrollFrame)
        else
            ToggleAutoClaimButton.Text = "Toggle Auto-Claim: OFF"
            ToggleAutoClaimButton.BackgroundColor3 = Color3.fromRGB(150, 40, 40) -- OFF (Red)
            -- Note: Since the loop function only runs while IsLoopRunning is true, setting it to false effectively stops the coroutine.
        end
    end)
    
    return MainFrame, QuestScrollFrame
end

-- Main Execution
local MainFrame, QuestScrollFrame = createQuestClaimUI()
populateQuests(QuestScrollFrame)

-- Optional: Add a simple refresh button or feature if the quest data changes frequently
local RefreshButton = Instance.new("TextButton")
RefreshButton.Name = "RefreshButton"
RefreshButton.Text = "Refresh"
RefreshButton.Size = UDim2.new(0, 80, 0, 30)
RefreshButton.Position = UDim2.new(0.75, 0, 0, 8) -- Positioned near the top right of the frame
RefreshButton.BackgroundColor3 = Color3.fromRGB(180, 120, 70)
RefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshButton.Font = Enum.Font.Arial
RefreshButton.TextSize = 16
RefreshButton.BorderSizePixel = 0
RefreshButton.Parent = MainFrame

-- Add UICorner for rounded corners on RefreshButton
local RefreshButtonCorner = Instance.new("UICorner")
RefreshButtonCorner.CornerRadius = UDim.new(0, 8)
RefreshButtonCorner.Parent = RefreshButton

RefreshButton.MouseButton1Click:Connect(function()
    populateQuests(QuestScrollFrame)
end)
