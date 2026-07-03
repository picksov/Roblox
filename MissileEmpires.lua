-- Antigravity Rayfield-Powered Orbital Strike Hub (Settings & Profiles Edition)
-- Place ID: 90950521756963 (Missile Empire)

-- ──────────────────────────────────────────────────────────
-- Clean up previous GUI instances
-- ──────────────────────────────────────────────────────────
local function cleanupRayfield()
    local rg = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
    if rg then
        for _, child in ipairs(rg:GetChildren()) do
            if child.Name:find("Rayfield") then
                pcall(function() child:Destroy() end)
            end
        end
    end
    for _, child in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
        if child.Name:find("Rayfield") then
            pcall(function() child:Destroy() end)
        end
    end
end
cleanupRayfield()

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local LaunchMissileEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("LaunchMissile")
local MissileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MissileData"))

-- Config & State
local activeTargetPlayer = nil
local targetMode = "Bases" -- "Bases", "PlayerOnly", "CityRaid"
local isAutoFiring = false
local fireDelay = 0.5
local salvoSizeLimit = 999
local selectedMissileTypes = {}
local firedCache = {}
local activeTrackingEnd = 0
local cameraTargetPos = nil
local cameraYaw = 45
local cameraPitch = 35
local cameraDistance = 75
local isDraggingCamera = false
local lastMousePos = nil

-- Auto-Buy Config
local autoBuyEnabled = false
local autoBuyInterval = 2.0
local autoBuySelectedMissiles = {}
local autoBuySelectedBuildings = {}
local autoBuySelectedDefenses = {}

-- Misc Options
local trackingEnabled = false
local autoKickStaffEnabled = false
local autoRepairEnabled = false
local autoSpinBlackMarket = false
local autoClaimRewards = false

-- UI Elements References (for Profile Loading UI Updates)
local modeDropdownUI = nil
local autoFireToggleUI = nil
local launchDelayInputUI = nil
local weaponDropdownUI = nil
local autoBuyToggleUI = nil
local autoBuyMissilesDropdownUI = nil
local autoBuyBuildingsDropdownUI = nil
local autoBuyDefensesDropdownUI = nil
local cameraTrackingToggleUI = nil
local autoKickToggleUI = nil
local autoRepairToggleUI = nil
local autoSpinBlackMarketToggleUI = nil
local autoClaimRewardsToggleUI = nil
local priorityInputUI = nil
local salvoSizeInputUI = nil
local uiToggleKeybindUI = nil

-- UI Toggle settings
local uiToggleKey = Enum.KeyCode.RightShift
local uiVisible = true

-- Group ID check for game moderation/staff detection (CreatorId is Catalyst Games group)
local CREATOR_GROUP_ID = 703038082

-- Ordered Shop lists (Excluding Black Market Items)
local orderedMissiles = {"Stinger","Super Cannon","Sunspear","Crimson Comet","Good Cannon","Viper","Mega Cannon","Frozone","Venom","Goliath","Bunker Buster","Shadow","Beetle","Purple Phantom","Silvershot","Blue Bolt","Nighthawk","Fury","Falcon","Patriot","Bullet Missile"}
local orderedBuildings = {"Basic House","Industrial Factory","Factory","Military Barracks","SkyScraper","Oil Refinery","Nuclear Plant","Gold Mine","Quantum Tower","Bank","Power Plant","Large House","Small House","Apartment","Motel","Oil Rig","Farm","Trade Port","Particle Accelerator"}
local orderedDefenses = {"Small Shield","Basic Turret","Good Turret","Big Shield","Good Shield","Mega Turret"}

-- Priorities List
local priorityString = "PlacedTurrets, PlacedBuildings, PlacedShields"
local priorityList = {"PlacedTurrets", "PlacedBuildings", "PlacedShields"}

-- Missile Damage Map
local missileDamage = {}
for name, data in pairs(MissileData) do
    missileDamage[name] = data.Damage or 0
end

-- Helper: Split Priority String
local function updatePriorityList(newString)
    priorityString = newString
    local list = {}
    for item in string.gmatch(newString, "([^,]+)") do
        local clean = string.gsub(item, "^%s*(.-)%s*$", "%1")
        if clean ~= "" then
            table.insert(list, clean)
        end
    end
    priorityList = list
end

-- Helper: Get Base by Player Name
local function getBaseByPlayerName(name)
    if not name or name == "" then return nil end
    for _, base in ipairs(workspace.Map.Bases:GetChildren()) do
        local playerNameVal = base:FindFirstChild("PlayerInformation") and base.PlayerInformation:FindFirstChild("PlayerName")
        if playerNameVal and playerNameVal.Value == name then
            return base
        end
    end
    return nil
end

local myBase = getBaseByPlayerName(LocalPlayer.Name)

-- Find active CityRaid model in workspace
local function findCityRaidModel()
    local main = workspace:FindFirstChild("CityRaid") or workspace.Map:FindFirstChild("CityRaid")
    if main then return main end
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "CityRaid" or (child:IsA("Model") and child.Name:lower():find("city") and child.Name:lower():find("raid")) then
            return child
        end
    end
    for _, child in ipairs(workspace.Map:GetChildren()) do
        if child.Name == "CityRaid" or (child:IsA("Model") and child.Name:lower():find("city") and child.Name:lower():find("raid")) then
            return child
        end
    end
    return nil
end

-- Get targetable components within a CityRaid model (Buildings only, turrets excluded)
local function getCityRaidTargets(cityRaid)
    local targets = {}
    local buildings = cityRaid:FindFirstChild("Buildings")
    if buildings then
        for _, child in ipairs(buildings:GetChildren()) do
            local hp = child:GetAttribute("HP")
            local maxHp = child:GetAttribute("MaxHP")
            if hp == nil then
                hp = 1000
                maxHp = 1000
            end

            if hp > 0 then
                local isHighlighted = false
                if child:FindFirstChildOfClass("Highlight") or child:FindFirstChildOfClass("SelectionBox") then
                    isHighlighted = true
                else
                    for _, desc in ipairs(child:GetDescendants()) do
                        if desc:IsA("Highlight") or desc:IsA("SelectionBox") then
                            isHighlighted = true
                            break
                        end
                    end
                end

                table.insert(targets, {
                    instance = child,
                    folder = "Buildings",
                    name = child.Name,
                    hp = hp,
                    maxHp = maxHp,
                    isHighlighted = isHighlighted
                })
            end
        end
    end
    return targets
end

-- Assign City Raid Priority Score (Nuke charging building is 1, regular skyscraper is 2)
local function getCityRaidPriority(obj)
    if obj.isHighlighted then
        return 1
    end
    return 2
end

-- Find all targetable elements in a player's base
local function getTargetableObjects(targetPlayerName)
    local base = getBaseByPlayerName(targetPlayerName)
    if not base then return {} end

    local objects = {}
    local folders = {
        PlacedTurrets = base:FindFirstChild("PlacedTurrets"),
        PlacedShields = base:FindFirstChild("PlacedShields"),
        PlacedBuildings = base:FindFirstChild("PlacedBuildings")
    }

    for folderName, folder in pairs(folders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                local hp = child:GetAttribute("HP")
                local maxHp = child:GetAttribute("MaxHP")
                if hp and hp > 0 then
                    table.insert(objects, {
                        instance = child,
                        folder = folderName,
                        name = child.Name,
                        hp = hp,
                        maxHp = maxHp
                    })
                end
            end
        end
    end
    return objects
end

-- Get Priority Index from Custom Priority List
local function getPriorityScore(obj)
    for idx, pName in ipairs(priorityList) do
        if obj.folder == pName or obj.name:lower():find(pName:lower()) then
            return idx
        end
    end
    return #priorityList + 1
end

-- Find next target
local function findNextTarget(targetName)
    if targetMode == "CityRaid" or targetName == "City Raid" then
        local cityRaid = findCityRaidModel()
        if not cityRaid then return nil end

        local targets = getCityRaidTargets(cityRaid)
        if #targets == 0 then return nil end

        table.sort(targets, function(a, b)
            local pA = getCityRaidPriority(a)
            local pB = getCityRaidPriority(b)
            if pA ~= pB then
                return pA < pB
            end
            return a.hp < b.hp
        end)

        return targets[1]
    elseif targetMode == "PlayerOnly" then
        -- Target player character specifically.
        -- "attack the defenses first such as the turrets first then it will attack the player next."
        local targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then return nil end

        -- 1. Check if there are active defenses protecting their base
        local baseObjects = getTargetableObjects(targetName)
        local defenses = {}
        for _, obj in ipairs(baseObjects) do
            if obj.folder == "PlacedTurrets" or obj.folder == "PlacedShields" or obj.name:lower():find("shield") or obj.name:lower():find("turret") then
                table.insert(defenses, obj)
            end
        end

        if #defenses > 0 then
            table.sort(defenses, function(a, b)
                return a.hp < b.hp
            end)
            return defenses[1]
        end

        -- 2. No active defenses left -> target player character!
        local char = targetPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then
            return {
                instance = root,
                folder = "Player Character",
                name = targetPlayer.Name,
                hp = hum.Health,
                maxHp = hum.MaxHealth
            }
        end

        return nil
    else
        -- Default: Bases Target Mode
        local objects = getTargetableObjects(targetName)
        if #objects == 0 then return nil end

        table.sort(objects, function(a, b)
            local scoreA = getPriorityScore(a)
            local scoreB = getPriorityScore(b)
            if scoreA ~= scoreB then
                return scoreA < scoreB
            end
            return a.hp < b.hp
        end)

        return objects[1]
    end
end

-- Get all local ready missiles that match checked types
local function getReadyMissiles()
    if not myBase then return {} end
    local placed = myBase:FindFirstChild("PlacedMissiles")
    if not placed then return {} end

    local ready = {}
    for _, m in ipairs(placed:GetChildren()) do
        if selectedMissileTypes[m.Name] and not firedCache[m] then
            local prompt = m:FindFirstChild("PromptPart") and m.PromptPart:FindFirstChild("LaunchPrompt")
                or m:FindFirstChild("AttachPart") and m.AttachPart:FindFirstChild("CannonToggle")
                or m:FindFirstChild("AttachPart") and m.AttachPart:FindFirstChild("LaunchPrompt")
            if prompt and prompt.Enabled then
                table.insert(ready, {
                    instance = m,
                    name = m.Name,
                    damage = missileDamage[m.Name] or 0
                })
            end
        end
    end
    return ready
end

-- Rayfield Window Construction
local Window = Rayfield:CreateWindow({
    Name = "Orbital Strike Command",
    LoadingTitle = "Orbital Strike Init...",
    LoadingSubtitle = "by Antigravity",
    ConfigurationSaving = {
        Enabled = false
    },
    Discord = {
        Enabled = false
    },
    KeySystem = false
})

-- Tabs
local TargetTab = Window:CreateTab("🎯 Target Controls", 4483362458)
local PriorityTab = Window:CreateTab("⚙️ Bases Priority Sorting", 4483362458)
local WeaponTab = Window:CreateTab("🚀 Weapon Checklist", 4483362458)
local BuyTab = Window:CreateTab("🛒 Auto Buy", 4483362458)
local MiscTab = Window:CreateTab("🔮 Miscellaneous", 4483362458)
local SettingsTab = Window:CreateTab("🛠️ Settings", 4483362458)

-- ──────────────────────────────────────────────────────────
-- 1. Direct Target Controls Tab Elements
-- ──────────────────────────────────────────────────────────
TargetTab:CreateSection("Target Selector")

local selectedPlayerLabel = TargetTab:CreateLabel("Target Player: None")

local playerList = {}
local function refreshPlayerList()
    local list = {"City Raid"}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(list, p.Name)
        end
    end
    playerList = list
    return list
end

refreshPlayerList()

local playerDropdown = TargetTab:CreateDropdown({
    Name = "Select Target Player",
    Options = playerList,
    CurrentOption = "",
    MultipleOptions = false,
    Callback = function(Option)
        local opt = typeof(Option) == "table" and Option[1] or Option
        activeTargetPlayer = opt
        selectedPlayerLabel:Set("Target Player: " .. tostring(opt))
    end,
})

TargetTab:CreateButton({
    Name = "Refresh Player Dropdown",
    Callback = function()
        playerDropdown:Refresh(refreshPlayerList())
    end,
})

TargetTab:CreateSection("Prioritization Mode")

modeDropdownUI = TargetTab:CreateDropdown({
    Name = "Target Selection Mode",
    Options = {
        "Bases Mode (Priority Queue)",
        "Player Mode (Defenses First)",
        "City Raid Mode (No Turrets)"
    },
    CurrentOption = "Bases Mode (Priority Queue)",
    MultipleOptions = false,
    Callback = function(Option)
        local opt = Option[1] or Option
        if opt == "Bases Mode (Priority Queue)" then
            targetMode = "Bases"
        elseif opt == "Player Mode (Defenses First)" then
            targetMode = "PlayerOnly"
        elseif opt == "City Raid Mode (No Turrets)" then
            targetMode = "CityRaid"
        end
    end,
})

TargetTab:CreateSection("Firing Commands")

autoFireToggleUI = TargetTab:CreateToggle({
    Name = "Enable Auto-Fire",
    CurrentValue = false,
    Callback = function(Value)
        isAutoFiring = Value
    end,
})

launchDelayInputUI = TargetTab:CreateInput({
    Name = "Launch Interval (seconds)",
    PlaceholderText = "0.5",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val >= 0.05 then
            fireDelay = val
        end
    end,
})

salvoSizeInputUI = TargetTab:CreateInput({
    Name = "Salvo Missile Count Limit",
    PlaceholderText = "999",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val > 0 then
            salvoSizeLimit = val
        else
            salvoSizeLimit = 999
        end
    end,
})

TargetTab:CreateButton({
    Name = "Launch Salvo",
    Callback = function()
        if not activeTargetPlayer then
            Rayfield:Notify({
                Title = "Error",
                Content = "Choose target player first!",
                Duration = 2.5
            })
            return
        end

        local ready = getReadyMissiles()
        if #ready == 0 then
            Rayfield:Notify({
                Title = "Error",
                Content = "No launchers ready!",
                Duration = 2.5
            })
            return
        end

        local currentActiveObject = findNextTarget(activeTargetPlayer)
        if currentActiveObject then
            local targetPos = currentActiveObject.instance:GetPivot().Position
            local firedCount = 0

            for _, mInfo in ipairs(ready) do
                if firedCount >= salvoSizeLimit then break end
                
                firedCache[mInfo.instance] = true
                task.spawn(function()
                    task.wait(3.5)
                    firedCache[mInfo.instance] = nil
                end)

                local ok = pcall(function()
                    LaunchMissileEvent:FireServer(mInfo.instance, targetPos)
                end)
                if ok then
                    firedCount = firedCount + 1
                    task.wait(0.05)
                end
            end

            Rayfield:Notify({
                Title = "Salvo Launched",
                Content = "Fired " .. tostring(firedCount) .. " missiles.",
                Duration = 3
            })
        end
    end,
})

TargetTab:CreateButton({
    Name = "🚨 EMERGENCY STOP",
    Callback = function()
        isAutoFiring = false
        if autoFireToggleUI then
            pcall(function() autoFireToggleUI:Set(false) end)
        end
        Rayfield:Notify({
            Title = "Stopped",
            Content = "Emergency stop triggered! Firing disabled.",
            Duration = 3
        })
    end,
})

TargetTab:CreateSection("System Status")

local statusParagraph = TargetTab:CreateParagraph({
    Title = "SYSTEM MONITOR",
    Content = "Status: IDLE\nTarget Component: None\nTarget HP: - / -"
})

-- ──────────────────────────────────────────────────────────
-- 2. Bases Priority Sorting Tab Elements
-- ──────────────────────────────────────────────────────────
PriorityTab:CreateSection("Bases Priority Settings")

PriorityTab:CreateParagraph({
    Title = "About Prioritization List",
    Content = "This priority list is ONLY used when 'Target Selection Mode' is set to 'Bases Mode (Priority Queue)'.\n\nIt searches and locks onto base components in the order specified below. Separate entries with commas."
})

priorityInputUI = PriorityTab:CreateInput({
    Name = "Edit Priority Queue",
    PlaceholderText = "PlacedTurrets, PlacedBuildings, PlacedShields",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        updatePriorityList(Text)
    end,
})

-- ──────────────────────────────────────────────────────────
-- 3. Weapon Checklist Tab Elements
-- ──────────────────────────────────────────────────────────
WeaponTab:CreateSection("Weapon Checklist")

local sortedMissiles = {}
for name, _ in pairs(MissileData) do
    table.insert(sortedMissiles, name)
end
table.sort(sortedMissiles)

-- Default all select in selectedMissileTypes
for _, name in ipairs(sortedMissiles) do
    selectedMissileTypes[name] = true
end

weaponDropdownUI = WeaponTab:CreateDropdown({
    Name = "Select Launcher Types to Fire",
    Options = sortedMissiles,
    CurrentOption = sortedMissiles, -- Select all by default
    MultipleOptions = true,
    Flag = "weaponChecklist",
    Callback = function(Options)
        if not Options or #Options == 0 then return end
        selectedMissileTypes = {}
        for _, name in ipairs(Options) do
            selectedMissileTypes[name] = true
        end
    end,
})

-- ──────────────────────────────────────────────────────────
-- 4. Auto Buy Tab Elements
-- ──────────────────────────────────────────────────────────
BuyTab:CreateSection("Auto-Buy Activation")

autoBuyToggleUI = BuyTab:CreateToggle({
    Name = "Enable Auto-Buy",
    CurrentValue = false,
    Callback = function(Value)
        autoBuyEnabled = Value
    end,
})

BuyTab:CreateSection("Configure Auto-Buy Items")

autoBuyMissilesDropdownUI = BuyTab:CreateDropdown({
    Name = "Auto-Buy Missiles",
    Options = orderedMissiles,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuyMissiles",
    Callback = function(Options)
        autoBuySelectedMissiles = {}
        for _, name in ipairs(Options) do
            autoBuySelectedMissiles[name] = true
        end
    end,
})

autoBuyBuildingsDropdownUI = BuyTab:CreateDropdown({
    Name = "Auto-Buy Buildings",
    Options = orderedBuildings,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuyBuildings",
    Callback = function(Options)
        autoBuySelectedBuildings = {}
        for _, name in ipairs(Options) do
            autoBuySelectedBuildings[name] = true
        end
    end,
})

autoBuyDefensesDropdownUI = BuyTab:CreateDropdown({
    Name = "Auto-Buy Defenses",
    Options = orderedDefenses,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuyDefenses",
    Callback = function(Options)
        autoBuySelectedDefenses = {}
        for _, name in ipairs(Options) do
            autoBuySelectedDefenses[name] = true
        end
    end,
})

-- ──────────────────────────────────────────────────────────
-- 5. Miscellaneous Tab Elements
-- ──────────────────────────────────────────────────────────
MiscTab:CreateSection("Camera Tracking")

cameraTrackingToggleUI = MiscTab:CreateToggle({
    Name = "Enable Camera tracking",
    CurrentValue = false,
    Callback = function(Value)
        trackingEnabled = Value
    end,
})

MiscTab:CreateSection("Security & Admin Kicker")

autoKickToggleUI = MiscTab:CreateToggle({
    Name = "Auto-Kick when Staff joins",
    CurrentValue = false,
    Callback = function(Value)
        autoKickStaffEnabled = Value
    end,
})

MiscTab:CreateSection("Auto-Repair")

autoRepairToggleUI = MiscTab:CreateToggle({
    Name = "Enable Auto-Repair",
    CurrentValue = false,
    Callback = function(Value)
        autoRepairEnabled = Value
    end,
})

MiscTab:CreateSection("Black Market Actions")

autoSpinBlackMarketToggleUI = MiscTab:CreateToggle({
    Name = "Auto-Spin Black Market",
    CurrentValue = false,
    Callback = function(Value)
        autoSpinBlackMarket = Value
    end,
})

MiscTab:CreateSection("Rewards & Quests Auto-Claim")

autoClaimRewardsToggleUI = MiscTab:CreateToggle({
    Name = "Auto-Claim Quests & Rewards",
    CurrentValue = false,
    Callback = function(Value)
        autoClaimRewards = Value
    end,
})

MiscTab:CreateSection("Tycoon Placement Actions")

-- Precompute Weapon Geometry to match tycoon pivot and bounding offsets
local weaponGeometry = {}
local function precomputeWeaponGeometry()
    for name, data in pairs(MissileData) do
        local folder = ReplicatedStorage.Assets:FindFirstChild("Missiles")
        local m = folder and folder:FindFirstChild(name)
        if not m and ReplicatedStorage.Assets:FindFirstChild("Cannons") then
            m = ReplicatedStorage.Assets.Cannons:FindFirstChild(name)
        end
        if m then
            local clone = m:Clone()
            local u42 = data.IsCannon and CFrame.identity or CFrame.Angles(0, 0, -1.5707963267948966)
            clone:PivotTo(clone:GetPivot() * u42)
            
            local Y = clone:GetPivot().Y
            local bboxCF, bboxSize = clone:GetBoundingBox()
            local u45 = Y - (bboxCF.Y - bboxSize.Y / 2)
            
            weaponGeometry[name] = {
                u45 = u45,
                size = bboxSize
            }
            clone:Destroy()
        else
            weaponGeometry[name] = {
                u45 = 2,
                size = Vector3.new(4, 8, 4)
            }
        end
    end
end
precomputeWeaponGeometry()

-- Checks collision parameters on base placement zone
local function canPlaceAt(cf, size)
    local shrinkSize = Vector3.new(size.X - 0.4, size.Y - 0.4, size.Z - 0.4)
    local params = OverlapParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character or workspace}
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local parts = workspace:GetPartBoundsInBox(cf, shrinkSize, params)
    for _, part in ipairs(parts) do
        local parent = part.Parent
        while parent and parent ~= workspace do
            local pName = parent.Name
            if pName == "PlacedBuildings" or pName == "PlacedMissiles" or pName == "PlacedShields" or pName == "PlacedTurrets" then
                return false
            end
            parent = parent.Parent
        end
    end
    return true
end

local isBuilding = false

-- Auto-Build placement logic (pointed upwards, cheapest-to-expensive layout scan, cannons excluded)
local function runAutoBuild()
    if not myBase then return 0 end
    local zone = myBase:FindFirstChild("PlacementZone")
    if not zone then return 0 end
    
    local zoneCF = zone.CFrame
    local zoneSize = zone.Size
    local halfX = math.floor(zoneSize.X / 2)
    local halfZ = math.floor(zoneSize.Z / 2)

    -- 1. Count tools in Backpack + Character
    local toolCounts = {}
    local orderedToBuild = {}
    
    local function countTools(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("Tool") then
                local name = child.Name
                local isCannon = MissileData[name] and (MissileData[name].IsCannon or name:lower():find("cannon"))
                local isSelected = selectedMissileTypes[name]
                print("[Auto-Build Debug] Found tool in inventory: " .. tostring(name) .. " | isSelected = " .. tostring(isSelected) .. " | isCannon = " .. tostring(isCannon))
                if isSelected and not isCannon then
                    toolCounts[name] = (toolCounts[name] or 0) + 1
                end
            end
        end
    end
    
    countTools(LocalPlayer.Backpack)
    countTools(LocalPlayer.Character)

    -- Get list of unique missile names sorted by price (cheapest first)
    for name, count in pairs(toolCounts) do
        local price = MissileData[name] and MissileData[name].Price or 0
        table.insert(orderedToBuild, {name = name, count = count, price = price})
    end
    table.sort(orderedToBuild, function(a, b)
        return a.price < b.price
    end)

    print("[Auto-Build Debug] Total unique weapon types to place: " .. tostring(#orderedToBuild))

    isBuilding = true
    local placedCount = 0

    -- Helper to get current count of a tool type in backpack/character
    local function getActualInventoryCount(toolName)
        local count = 0
        for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if child.Name == toolName then count = count + 1 end
        end
        if LocalPlayer.Character then
            for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                if child.Name == toolName then count = count + 1 end
            end
        end
        return count
    end

    -- 2. Place each missile type sequentially
    for _, info in ipairs(orderedToBuild) do
        if not isBuilding then break end
        local name = info.name
        local geom = weaponGeometry[name] or { u45 = 2, size = Vector3.new(4, 8, 4) }
        local u45 = geom.u45
        local mSize = geom.size
        
        local isCannon = MissileData[name] and MissileData[name].IsCannon
        local upRotation = isCannon and CFrame.identity or CFrame.Angles(0, 0, -1.5707963267948966)

        -- We want to place `info.count` launchers of this type
        local remainingToPlace = info.count
        
        -- Start scanning from center outwards or with safety margin of 8 studs from tycoon edges
        local scanMargin = 8
        
        for x = -halfX + scanMargin, halfX - scanMargin, 3.2 do
            if not isBuilding or remainingToPlace <= 0 then break end
            for z = -halfZ + scanMargin, halfZ - scanMargin, 3.2 do
                if not isBuilding or remainingToPlace <= 0 then break end
                
                    local localCF = CFrame.new(x, u45, z) * upRotation
                    local worldCF = zoneCF:ToWorldSpace(localCF)

                    if canPlaceAt(worldCF, mSize) then
                        local startCount = getActualInventoryCount(name)
                        if startCount <= 0 then
                            remainingToPlace = 0
                            break
                        end
                        
                        local ok = pcall(function()
                            ReplicatedStorage.Events.PlaceMissile:FireServer(name, worldCF)
                        end)
                        
                        if ok then
                            -- Wait for server consumption check
                            local successPlace = false
                            for i = 1, 10 do -- Poll up to 0.2s max (10 * 0.02s)
                                task.wait(0.02)
                                if getActualInventoryCount(name) < startCount then
                                    successPlace = true
                                    break
                                end
                            end
                            
                            if successPlace then
                                placedCount = placedCount + 1
                                remainingToPlace = remainingToPlace - 1
                                task.wait(0.05) -- Tiny delay between placements
                            end
                        end
                    end
            end
        end
    end

    isBuilding = false
    return placedCount
end

-- Clear base launchers
local function clearPlacedMissiles()
    if not myBase then return 0 end
    local placed = myBase:FindFirstChild("PlacedMissiles")
    if not placed then return 0 end
    
    local count = 0
    for _, child in ipairs(placed:GetChildren()) do
        pcall(function()
            ReplicatedStorage.Events.PickupMissile:FireServer(child)
            count = count + 1
        end)
    end
    return count
end

MiscTab:CreateButton({
    Name = "Auto-Build Missiles (Exclude Cannons, Cheapest First)",
    Callback = function()
        if isBuilding then
            Rayfield:Notify({
                Title = "Already Building",
                Content = "Auto-Build is already running. Stop it first if you want to restart.",
                Duration = 3
            })
            return
        end
        Rayfield:Notify({
            Title = "Auto-Build",
            Content = "Starting placement scan... Please wait.",
            Duration = 3
        })
        task.spawn(function()
            local placed = runAutoBuild()
            Rayfield:Notify({
                Title = "Auto-Build Finished",
                Content = "Placed " .. tostring(placed) .. " launchers.",
                Duration = 4
            })
        end)
    end,
})

MiscTab:CreateButton({
    Name = "🚨 STOP AUTO-BUILD",
    Callback = function()
        isBuilding = false
        Rayfield:Notify({
            Title = "Stopped",
            Content = "Auto-Build stop requested.",
            Duration = 3
        })
    end,
})

MiscTab:CreateButton({
    Name = "Sell / Clear All Placed Launchers",
    Callback = function()
        local count = clearPlacedMissiles()
        Rayfield:Notify({
            Title = "Base Cleared",
            Content = "Successfully cleared " .. tostring(count) .. " launchers.",
            Duration = 3
        })
    end,
})

-- ──────────────────────────────────────────────────────────
-- 6. Settings Tab Elements
-- ──────────────────────────────────────────────────────────
SettingsTab:CreateSection("Profiles Preset Manager")

local HttpService = game:GetService("HttpService")

-- Helper: Get list of saved config profiles
local function getProfileList()
    local list = {}
    local success, files = pcall(function()
        if isfolder and isfolder("OrbitalStrikeConfigs") then
            return listfiles("OrbitalStrikeConfigs")
        end
        return {}
    end)
    if success and files then
        for _, file in ipairs(files) do
            local clean = file:gsub("\\", "/")
            clean = clean:gsub("^OrbitalStrikeConfigs/", "")
            clean = clean:gsub("%.json$", "")
            clean = clean:gsub("%.JSON$", "")
            table.insert(list, clean)
        end
    end
    return list
end

local currentProfileSelection = ""
local profileDropdown = SettingsTab:CreateDropdown({
    Name = "Select Saved Config Profile",
    Options = getProfileList(),
    CurrentOption = "",
    MultipleOptions = false,
    Callback = function(Option)
        local opt = Option[1] or Option
        currentProfileSelection = opt
    end,
})

SettingsTab:CreateButton({
    Name = "Refresh Profile Presets",
    Callback = function()
        profileDropdown:Refresh(getProfileList())
    end,
})

local function saveProfile(profileName)
    if not profileName or profileName == "" then
        Rayfield:Notify({Title = "Error", Content = "Invalid profile name!", Duration = 2.5})
        return
    end

    local data = {
        targetMode = targetMode,
        fireDelay = fireDelay,
        salvoSizeLimit = salvoSizeLimit,
        selectedMissileTypes = selectedMissileTypes,
        autoBuyEnabled = autoBuyEnabled,
        autoBuySelectedMissiles = autoBuySelectedMissiles,
        autoBuySelectedBuildings = autoBuySelectedBuildings,
        autoBuySelectedDefenses = autoBuySelectedDefenses,
        trackingEnabled = trackingEnabled,
        autoKickStaffEnabled = autoKickStaffEnabled,
        autoRepairEnabled = autoRepairEnabled,
        autoSpinBlackMarket = autoSpinBlackMarket,
        autoClaimRewards = autoClaimRewards,
        priorityString = priorityString,
        uiToggleKey = uiToggleKey and uiToggleKey.Name or "RightShift"
    }

    local success, err = pcall(function()
        if makefolder and writefile then
            if not isfolder("OrbitalStrikeConfigs") then
                makefolder("OrbitalStrikeConfigs")
            end
            writefile("OrbitalStrikeConfigs/" .. profileName .. ".json", HttpService:JSONEncode(data))
        end
    end)

    if success then
        Rayfield:Notify({
            Title = "Success",
            Content = "Saved config: " .. profileName,
            Duration = 3
        })
    else
        Rayfield:Notify({
            Title = "Error",
            Content = "Failed to save: " .. tostring(err),
            Duration = 3
        })
    end
end

local function loadProfile(profileName)
    if not profileName or profileName == "" then
        Rayfield:Notify({Title = "Error", Content = "Select a profile first!", Duration = 2.5})
        return
    end

    local path = "OrbitalStrikeConfigs/" .. profileName .. ".json"
    if not isfile or not isfile(path) then
        Rayfield:Notify({Title = "Error", Content = "Profile file not found!", Duration = 2.5})
        return
    end

    local success, content = pcall(readfile, path)
    if not success then
        Rayfield:Notify({Title = "Error", Content = "Failed to read profile file!", Duration = 2.5})
        return
    end

    local successDecode, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not successDecode or not data then
        Rayfield:Notify({Title = "Error", Content = "Failed to parse profile JSON!", Duration = 2.5})
        return
    end

    pcall(function()
        if data.targetMode ~= nil then targetMode = data.targetMode end
        if data.fireDelay ~= nil then fireDelay = data.fireDelay end
        if data.salvoSizeLimit ~= nil then salvoSizeLimit = data.salvoSizeLimit end
        if data.selectedMissileTypes ~= nil then selectedMissileTypes = data.selectedMissileTypes end
        if data.autoBuyEnabled ~= nil then autoBuyEnabled = data.autoBuyEnabled end
        if data.autoBuySelectedMissiles ~= nil then autoBuySelectedMissiles = data.autoBuySelectedMissiles end
        if data.autoBuySelectedBuildings ~= nil then autoBuySelectedBuildings = data.autoBuySelectedBuildings end
        if data.autoBuySelectedDefenses ~= nil then autoBuySelectedDefenses = data.autoBuySelectedDefenses end
        if data.trackingEnabled ~= nil then trackingEnabled = data.trackingEnabled end
        if data.autoKickStaffEnabled ~= nil then autoKickStaffEnabled = data.autoKickStaffEnabled end
        if data.autoRepairEnabled ~= nil then autoRepairEnabled = data.autoRepairEnabled end
        if data.autoSpinBlackMarket ~= nil then autoSpinBlackMarket = data.autoSpinBlackMarket end
        if data.autoClaimRewards ~= nil then autoClaimRewards = data.autoClaimRewards end
        if data.priorityString ~= nil then
            priorityString = data.priorityString
            updatePriorityList(priorityString)
        end
        if data.uiToggleKey ~= nil then
            local ok, key = pcall(function() return Enum.KeyCode[data.uiToggleKey] end)
            if ok and key then
                uiToggleKey = key
            end
        end

        -- Helper to get list of active keys from a lookup map
        local function getKeysFromMap(map)
            local list = {}
            for k, v in pairs(map) do
                if v then
                    table.insert(list, k)
                end
            end
            return list
        end

        -- Update UI elements dynamically to reflect loaded settings
        if modeDropdownUI then
            local displayMode = "Bases Mode (Priority Queue)"
            if targetMode == "PlayerOnly" then
                displayMode = "Player Mode (Defenses First)"
            elseif targetMode == "CityRaid" then
                displayMode = "City Raid Mode (No Turrets)"
            end
            pcall(function() modeDropdownUI:Set(displayMode) end)
        end
        if autoFireToggleUI then pcall(function() autoFireToggleUI:Set(isAutoFiring) end) end
        if launchDelayInputUI then pcall(function() launchDelayInputUI:Set(tostring(fireDelay)) end) end
        if salvoSizeInputUI then pcall(function() salvoSizeInputUI:Set(tostring(salvoSizeLimit)) end) end
        if weaponDropdownUI then pcall(function() weaponDropdownUI:Set(getKeysFromMap(selectedMissileTypes)) end) end
        if autoBuyToggleUI then pcall(function() autoBuyToggleUI:Set(autoBuyEnabled) end) end
        if autoBuyMissilesDropdownUI then pcall(function() autoBuyMissilesDropdownUI:Set(getKeysFromMap(autoBuySelectedMissiles)) end) end
        if autoBuyBuildingsDropdownUI then pcall(function() autoBuyBuildingsDropdownUI:Set(getKeysFromMap(autoBuySelectedBuildings)) end) end
        if autoBuyDefensesDropdownUI then pcall(function() autoBuyDefensesDropdownUI:Set(getKeysFromMap(autoBuySelectedDefenses)) end) end
        if cameraTrackingToggleUI then pcall(function() cameraTrackingToggleUI:Set(trackingEnabled) end) end
        if autoKickToggleUI then pcall(function() autoKickToggleUI:Set(autoKickStaffEnabled) end) end
        if autoRepairToggleUI then pcall(function() autoRepairToggleUI:Set(autoRepairEnabled) end) end
        if autoSpinBlackMarketToggleUI then pcall(function() autoSpinBlackMarketToggleUI:Set(autoSpinBlackMarket) end) end
        if autoClaimRewardsToggleUI then pcall(function() autoClaimRewardsToggleUI:Set(autoClaimRewards) end) end
        if priorityInputUI then pcall(function() priorityInputUI:Set(priorityString) end) end
        if uiToggleKeybindUI then pcall(function() uiToggleKeybindUI:Set(uiToggleKey.Name) end) end

        Rayfield:Notify({
            Title = "Success",
            Content = "Successfully loaded profile: " .. profileName,
            Duration = 3
        })
    end)
end

local saveProfileName = "default"
SettingsTab:CreateInput({
    Name = "New Profile Name",
    PlaceholderText = "default",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        saveProfileName = Text
    end,
})

SettingsTab:CreateButton({
    Name = "Save Current Config",
    Callback = function()
        saveProfile(saveProfileName)
        profileDropdown:Refresh(getProfileList())
    end,
})

SettingsTab:CreateButton({
    Name = "Load Selected Profile",
    Callback = function()
        loadProfile(currentProfileSelection)
    end,
})

SettingsTab:CreateButton({
    Name = "Overwrite Selected Profile",
    Callback = function()
        if currentProfileSelection ~= "" then
            saveProfile(currentProfileSelection)
            profileDropdown:Refresh(getProfileList())
        else
            Rayfield:Notify({Title = "Error", Content = "Select a profile first!", Duration = 2.5})
        end
    end,
})

SettingsTab:CreateSection("UI Customization")

uiToggleKeybindUI = SettingsTab:CreateKeybind({
    Name = "Hide/Show UI Keybind",
    CurrentKeybind = "RightShift",
    HoldToInteract = false,
    Flag = "uiToggleKeybind",
    Callback = function(Key)
        if typeof(Key) == "EnumItem" then
            uiToggleKey = Key
        elseif typeof(Key) == "string" then
            local ok, enumKey = pcall(function() return Enum.KeyCode[Key] end)
            if ok and enumKey then
                uiToggleKey = enumKey
            end
        end
    end,
})

SettingsTab:CreateSection("Server Utilities")

SettingsTab:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end,
})

SettingsTab:CreateButton({
    Name = "Server Hop (Low Player Lobby)",
    Callback = function()
        local placeId = game.PlaceId
        local serversUrl = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        local success, raw = pcall(function()
            return game:HttpGet(serversUrl)
        end)
        if success and raw then
            local list = HttpService:JSONDecode(raw)
            if list and list.data then
                for _, server in ipairs(list.data) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        pcall(function()
                            game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                        end)
                        break
                    end
                end
            end
        end
    end,
})

SettingsTab:CreateSection("Performance Toggles")

local function optimizeGraphics(enable)
    local lighting = game:GetService("Lighting")
    if enable then
        lighting.GlobalShadows = false
        settings().Rendering.QualityLevel = 1
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Material = Enum.Material.SmoothPlastic
                desc.CastShadow = false
            end
        end
    else
        lighting.GlobalShadows = true
    end
end

SettingsTab:CreateToggle({
    Name = "Potato Graphics Mode (FPS Boost)",
    CurrentValue = false,
    Callback = function(Value)
        optimizeGraphics(Value)
    end,
})

-- ──────────────────────────────────────────────────────────
-- Background Threads & Event-Driven Purchase Logic
-- ──────────────────────────────────────────────────────────

-- Helper to launch a single missile
local function launchMissile(missile, targetPos)
    if not missile or not targetPos then return false end
    
    firedCache[missile] = true
    task.spawn(function()
        task.wait(3.5)
        firedCache[missile] = nil
    end)

    local success, err = pcall(function()
        LaunchMissileEvent:FireServer(missile, targetPos)
    end)
    return success
end

-- Check stock status directly from player GUI labels
local function isItemInStock(category, name)
    local shop = game.Players.LocalPlayer.PlayerGui:FindFirstChild("FramesGui") and game.Players.LocalPlayer.PlayerGui.FramesGui:FindFirstChild("Shop")
    local frame = shop and shop:FindFirstChild(category .. "Frame")
    local list = frame and frame:FindFirstChild("ShopProductsList")
    local item = list and list:FindFirstChild(name)
    local stock = item and item:FindFirstChild("Stock")
    if stock then
        return stock.Text ~= "Out of Stock!"
    end
    return false
end

-- Purchase all selected auto-buy items that are currently in stock
local function purchaseCheckedInStockItems()
    if not autoBuyEnabled then return end
    
    -- Buy Missiles
    for name, enabled in pairs(autoBuySelectedMissiles) do
        if enabled and isItemInStock("Missiles", name) then
            pcall(function()
                ReplicatedStorage.Events.PurchaseMissile:FireServer(name, 1000)
            end)
            task.wait(0.08)
        end
    end

    -- Buy Buildings
    for name, enabled in pairs(autoBuySelectedBuildings) do
        if enabled and isItemInStock("Builds", name) then
            pcall(function()
                ReplicatedStorage.Events.PurchaseBuilding:FireServer(name, 1000)
            end)
            task.wait(0.08)
        end
    end

    -- Buy Defenses
    for name, enabled in pairs(autoBuySelectedDefenses) do
        if enabled and isItemInStock("Defense", name) then
            pcall(function()
                ReplicatedStorage.Events.PurchaseDefense:FireServer(name, 1000)
            end)
            task.wait(0.08)
        end
    end
end

local currentActiveObject = nil

-- Target Monitor Loop
task.spawn(function()
    while true do
        task.wait(0.2)
        local statusStr = "Status: " .. (isAutoFiring and "STRIKING" or "IDLE")
        local componentStr = "Target Component: None"
        local hpStr = "Target HP: - / -"

        if activeTargetPlayer then
            local nextTarget = findNextTarget(activeTargetPlayer)
            if nextTarget then
                currentActiveObject = nextTarget.instance
                componentStr = "Target Component: [" .. nextTarget.folder .. "] " .. nextTarget.name
                
                local hp = nextTarget.instance:IsA("Humanoid") and nextTarget.instance.Health or nextTarget.instance:GetAttribute("HP")
                local maxHp = nextTarget.instance:IsA("Humanoid") and nextTarget.instance.MaxHealth or nextTarget.instance:GetAttribute("MaxHP")
                
                if hp and maxHp then
                    hpStr = string.format("Target HP: %d / %d", hp, maxHp)
                else
                    hpStr = "Target HP: Active"
                end
            else
                currentActiveObject = nil
                if targetMode == "CityRaid" then
                    componentStr = "Target Component: Waiting for Raid..."
                else
                    componentStr = "Target Component: Wiped!"
                end
            end
        else
            currentActiveObject = nil
        end

        local ready = getReadyMissiles()
        local readyCount = #ready
        local totalPlaced = 0
        if myBase and myBase:FindFirstChild("PlacedMissiles") then
            totalPlaced = #myBase.PlacedMissiles:GetChildren()
        end
        statusStr = statusStr .. string.format(" | Ready: %d/%d", readyCount, totalPlaced)

        statusParagraph:Set({Title = statusStr, Content = componentStr .. "\n" .. hpStr})
    end
end)

-- Auto-Fire Loop (Dynamic target check on every loop frame)
task.spawn(function()
    while true do
        task.wait(0.05)
        if isAutoFiring and activeTargetPlayer then
            local nextTarget = findNextTarget(activeTargetPlayer)
            if nextTarget then
                local ready = getReadyMissiles()
                if #ready > 0 then
                    local targetPos = nextTarget.instance:GetPivot().Position
                    local targetMissile = ready[1]
                    local ok = launchMissile(targetMissile.instance, targetPos)
                    if ok then
                        task.wait(fireDelay)
                    end
                else
                    task.wait(0.2)
                end
            else
                task.wait(0.2)
            end
        end
    end
end)

-- Silent Background Purchase Checker (Checks stock state automatically in background)
task.spawn(function()
    while true do
        task.wait(1.0)
        if autoBuyEnabled then
            purchaseCheckedInStockItems()
        end
    end
end)

-- Auto-Repair Loop Thread (Repairs destroyed base elements using stealth teleport bypass)
task.spawn(function()
    while true do
        task.wait(1.0)
        if autoRepairEnabled and myBase then
            pcall(function()
                local promptsToFire = {}
                for _, desc in ipairs(myBase:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.Name == "RepairPrompt" and desc.Enabled then
                        table.insert(promptsToFire, desc)
                    end
                end
                
                if #promptsToFire > 0 then
                    local char = LocalPlayer.Character
                    local originalCF = char and char:GetPivot()
                    
                    if char and originalCF then
                        local camera = workspace.CurrentCamera
                        local originalCameraCF = camera and camera.CFrame
                        local originalCameraSubject = camera and camera.CameraSubject
                        
                        -- Lock camera to Scriptable to freeze visual movement
                        if camera and originalCameraCF then
                            pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
                        end
                        
                        for _, prompt in ipairs(promptsToFire) do
                            pcall(function()
                                if prompt and prompt.Parent and prompt.Enabled then
                                    local targetCF = prompt.Parent.Parent:GetPivot()
                                    char:PivotTo(targetCF)
                                    task.wait(0.22)
                                    fireproximityprompt(prompt, 1)
                                    task.wait(0.08)
                                end
                            end)
                        end
                        
                        pcall(function()
                            char:PivotTo(originalCF)
                        end)
                        
                        -- Restore camera custom controls and position
                        if camera and originalCameraCF then
                            pcall(function()
                                camera.CameraSubject = originalCameraSubject
                                camera.CameraType = Enum.CameraType.Custom
                                camera.CFrame = originalCameraCF
                            end)
                        end
                    end
                end
            end)
        end
    end
end)

-- Auto-Spin Black Market Thread
task.spawn(function()
    while true do
        task.wait(2.0)
        if autoSpinBlackMarket and myBase then
            local promptPart = myBase:FindFirstChild("MarketPrompt")
            if promptPart then
                local gemsVal = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Gems")
                if gemsVal and gemsVal.Value >= 25 then
                    local spendGemsFn = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("SpendGemsForSpin")
                    if spendGemsFn then
                        local ok = pcall(function()
                            spendGemsFn:InvokeServer()
                        end)
                        if ok then
                            task.wait(6.0) -- Wait for chest roll animation to finalize
                        end
                    end
                end
            end
        end
    end
end)

-- Auto-Claim Quests, Daily & Tier Rewards Thread
task.spawn(function()
    while true do
        task.wait(5.0)
        if autoClaimRewards then
            -- 1. Daily reward claim
            pcall(function()
                local claimDaily = ReplicatedStorage.Events:FindFirstChild("ClaimDailyReward")
                if claimDaily then
                    claimDaily:InvokeServer()
                end
            end)
            
            -- 2. Playtime free reward claim
            pcall(function()
                local claimFree = ReplicatedStorage.Events:FindFirstChild("ClaimFreeReward")
                if claimFree then
                    claimFree:InvokeServer()
                end
            end)
            
            -- 3. Season pass/tier chest claim
            pcall(function()
                local claimTier = ReplicatedStorage.Events:FindFirstChild("ClaimTierChest")
                if claimTier then
                    claimTier:FireServer()
                end
            end)
            
            -- 4. Active completed quest claims
            pcall(function()
                local Replion = require(ReplicatedStorage:FindFirstChild("Replion", true) or ReplicatedStorage:FindFirstChild("ReplionClient", true))
                local rep = Replion.Client:GetReplion("Data")
                if rep then
                    local data = rep:Get()
                    local quests = data and (data.Quests or data.quests)
                    local claimQuest = ReplicatedStorage.Events:FindFirstChild("ClaimQuest")
                    if quests and claimQuest then
                        for _, q in ipairs(quests) do
                            if q.progress >= q.target and not q.claimed then
                                pcall(function()
                                    claimQuest:FireServer(q.id)
                                end)
                                task.wait(0.5) -- Slight rate limit delay between quest claims
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- UIS User input listeners for drag rotation & zoom
local UIS = game:GetService("UserInputService")
pcall(function()
    UIS.InputBegan:Connect(function(input, processed)
        if not trackingEnabled or os.clock() >= activeTrackingEnd then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingCamera = true
            lastMousePos = UIS:GetMouseLocation()
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingCamera = false
            lastMousePos = nil
        end
    end)

    UIS.InputChanged:Connect(function(input, processed)
        if not trackingEnabled or os.clock() >= activeTrackingEnd then return end
        
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            cameraDistance = math.clamp(cameraDistance - input.Position.Z * 5, 20, 200)
        end
    end)
end)

-- Camera Tracking using RenderStepped (focuses on target in Scriptable mode with manual drag rotation)
game:GetService("RunService").RenderStepped:Connect(function()
    if trackingEnabled and os.clock() < activeTrackingEnd and cameraTargetPos then
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = Enum.CameraType.Scriptable
            
            -- Handle drag rotation
            if isDraggingCamera and lastMousePos then
                local currentMousePos = UIS:GetMouseLocation()
                local delta = currentMousePos - lastMousePos
                lastMousePos = currentMousePos
                
                cameraYaw = cameraYaw - delta.X * 0.4
                cameraPitch = math.clamp(cameraPitch + delta.Y * 0.4, -80, 80)
            end
            
            -- Calculate spherical position
            local radYaw = math.rad(cameraYaw)
            local radPitch = math.rad(cameraPitch)
            local offset = Vector3.new(
                cameraDistance * math.cos(radPitch) * math.sin(radYaw),
                cameraDistance * math.sin(radPitch),
                cameraDistance * math.cos(radPitch) * math.cos(radYaw)
            )
            
            camera.CFrame = CFrame.new(cameraTargetPos + offset, cameraTargetPos)
            return
        end
    end
    
    -- Fallback/Restore normal camera behavior once flight finishes
    local camera = workspace.CurrentCamera
    if camera and camera.CameraType == Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            camera.CameraSubject = hum
        end
    end
end)

-- Staff Detector and Kicker logic
local function checkStaffMember(player)
    if player == LocalPlayer then return end
    
    local isStaff = false
    -- Check if the player is a member of Catalyst Games group and has a high rank
    local success, rank = pcall(function()
        return player:GetRankInGroup(CREATOR_GROUP_ID)
    end)
    if success and rank and rank >= 200 then
        isStaff = true
    end

    -- Fallback check for common moderation roles
    if player.Name == "Taylorma20161114" or player.UserId == 703038082 then
        isStaff = true
    end

    if isStaff and autoKickStaffEnabled then
        LocalPlayer:Kick("[Security] Left the server. A staff member or developer has joined: " .. player.Name)
    end
end

-- Monitor joining players
Players.PlayerAdded:Connect(function(player)
    checkStaffMember(player)
end)

-- Scan existing players on startup/toggle
task.spawn(function()
    while true do
        task.wait(2.0)
        if autoKickStaffEnabled then
            for _, player in ipairs(Players:GetPlayers()) do
                checkStaffMember(player)
            end
        end
    end
end)

-- Custom Hide/Show UI Binder Handler
local function toggleUIVisibility()
    local mainGui = game:GetService("CoreGui").RobloxGui:FindFirstChild("Rayfield")
    if mainGui and mainGui:FindFirstChild("Main") then
        uiVisible = not uiVisible
        mainGui.Main.Visible = uiVisible
    end
end

game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == uiToggleKey then
        toggleUIVisibility()
    end
end)

-- Hook into missile launch animations to track flight durations and target positions
pcall(function()
    ReplicatedStorage.Events.AnimateMissile.OnClientEvent:Connect(function(startPos, targetPos, missileName, playerInstance, missileUUID)
        local isOurMissile = (playerInstance == LocalPlayer)
        
        if isOurMissile then
            -- Calculate bezier path length using bezier formula to get precise flight duration
            local p0 = startPos
            local p3 = targetPos
            local p1 = p0 + Vector3.new(0, 400, 0)
            local p2 = p3 + Vector3.new(0, 400, 0)
            
            local pathLength = 0
            local prev = p0
            for i = 1, 20 do
                local t = i / 20
                local t1 = 1 - t
                local current = t1^3 * p0 + 3 * t1^2 * t * p1 + 3 * t1 * t^2 * p2 + t^3 * p3
                pathLength = pathLength + (current - prev).Magnitude
                prev = current
            end
            
            local duration = math.max(pathLength / 150, 1.5)
            activeTrackingEnd = os.clock() + duration
            cameraTargetPos = targetPos
        end
    end)

    local AnimateCannonNuke = ReplicatedStorage.Events:FindFirstChild("AnimateCannonNuke")
    if AnimateCannonNuke then
        AnimateCannonNuke.OnClientEvent:Connect(function(startPos, targetPos, cannonName, playerInstance, nukeUUID)
            local isOurMissile = (playerInstance == LocalPlayer)
            
            if isOurMissile then
                local p0 = startPos
                local p3 = targetPos
                local p1 = p0 + Vector3.new(0, 400, 0)
                local p2 = p3 + Vector3.new(0, 400, 0)
                
                local pathLength = 0
                local prev = p0
                for i = 1, 20 do
                    local t = i / 20
                    local t1 = 1 - t
                    local current = t1^3 * p0 + 3 * t1^2 * t * p1 + 3 * t1 * t^2 * p2 + t^3 * p3
                    pathLength = pathLength + (current - prev).Magnitude
                    prev = current
                end
                
                local duration = math.max(pathLength / 150, 1.5)
                activeTrackingEnd = os.clock() + duration
                cameraTargetPos = targetPos
            end
        end)
    end
end)

Rayfield:Notify({
    Title = "Ready",
    Content = "Antigravity Rayfield Strike System Initialized.",
    Duration = 5,
    Image = "check",
})

-- Anti-AFK (Bypasses Roblox idle disconnect automatically)
pcall(function()
    LocalPlayer.Idled:Connect(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)