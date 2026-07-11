-- ════════════════════════════════════════════════════════════════════
-- Orbital Strike — Self-Contained
-- Validates key independently before running.
-- ════════════════════════════════════════════════════════════════════

-- Step 1: Load Panda SDK
local PANDA_SERVICE = "orbital"
local PANDA_KEYFILE = "OrbitalStrikeKey.txt"

local function loadPanda()
    local ok, src = pcall(function() return game:HttpGet("https://api.pandauth.com/lib/external/panda-v3-external.lua") end)
    if not ok or not src then return nil end
    local fn = loadstring(src); if not fn then return nil end
    local ok2, lib = pcall(fn); return ok2 and lib or nil
end

local Pelinda = loadPanda()
if not Pelinda then
    warn("[OrbitalStrike] Panda SDK unavailable — exiting")
    return
end

-- Step 2: Validate key
local function validateKey(key)
    key = (key or ""):gsub("%s+", "")
    if #key < 5 then return false end
    local ok, r = pcall(Pelinda.Init, { Service = PANDA_SERVICE, Key = key, SilentMode = true })
    return ok and r == "validated!!"
end

local keyValid = false
if isfile and isfile(PANDA_KEYFILE) then
    local ok, data = pcall(readfile, PANDA_KEYFILE)
    if ok and data then keyValid = validateKey(data) end
end

if not keyValid then
    -- Fallback: try getgenv key from loader session
    local sessionKey = getgenv().__OSH_LOADER_KEY
    if sessionKey and validateKey(sessionKey) then
        keyValid = true
    end
end

if not keyValid then
    warn("[OrbitalStrike] No valid key — exiting")
    return
end

warn("[OrbitalStrike] Key validated. Starting...")

-- Self-integrity: periodic bypass verification
task.spawn(function()
    while true do
        task.wait(300) -- every 5 minutes
        local Query = {Constants = {" - On Xbox", " - On mobile", "_"}, IgnoreExecutor = true}
        local d = filtergc("function", Query, true)
        if d then
            local u3 = debug.getupvalues(d)[3]
            local ok = pcall(debug.getconstants, u3)
            if ok then
                -- Bypass was unhooked! Re-arm immediately
                warn("[OrbitalStrike] Bypass compromised — re-arming")
                local a, b, c, d2, e, f = debug.info(d, "slanf")
                if getrenv and getrenv().debug and getrenv().debug.info then
                    local origInfo = getrenv().debug.info
                    local spoof = newcclosure(function(target, what, ...)
                        if target == d then return a, b, c, d2, e, f end
                        return origInfo(target, what, ...)
                    end)
                    pcall(hookfunction, origInfo, spoof)
                end
                if newcclosure then
                    pcall(hookfunction, d, newcclosure(function() return task.wait(9e9) end))
                end
                -- Re-arm RemoteEvent disconnect
                pcall(function()
                    for _, child in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
                        if child:IsA("RemoteEvent") and child:FindFirstChild("__FUNCTION") then
                            local conns = getconnections(child.OnClientEvent)
                            for _, conn in ipairs(conns) do
                                local ok2, consts = pcall(debug.getconstants, conn.Function)
                                if ok2 and consts then
                                    for _, c in ipairs(consts) do
                                        if c == "Detected" then
                                            for _, c2 in ipairs(conns) do
                                                pcall(function() c2:Disconnect() end)
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end
end)



setthreadidentity(8)

local bypassArmed = false
local function armBypass()
    local getType = typeof or type

    -- Verify prerequisites
    if getType(filtergc) ~= "function"
    or getType(hookfunction) ~= "function"
    or getType(newcclosure) ~= "function" then
        warn("[Syphon] Required APIs unavailable")
        return false
    end
    local useSetupvalue = (getType(debug.setupvalue) == "function"
                       and getType(debug.getupvalues) == "function")

    -- Retry loop (Adonis may init after script loads)
    warn("[Syphon] Scanning for Adonis...")
    local Query = {Constants = {" - On Xbox", " - On mobile", "_"}, IgnoreExecutor = true}
    local detected = nil
    while not detected do
        detected = filtergc("function", Query, true)
        if detected and getType(detected) == "function" then break end
        detected = nil
        task.wait(0.5)
    end
    warn("[Syphon] Detected found")

    -- Harvest upvalues
    local sendFunc, killFunc = nil, nil
    if useSetupvalue then
        local upvals = debug.getupvalues(detected)
        sendFunc = upvals[3]
        killFunc = upvals[9]
    end

    -- Capture debug.info for spoofing
    local sig = {}
    for _, flag in ipairs({"s", "l", "a", "n"}) do
        local ok, val = pcall(debug.info, detected, flag)
        if ok then sig[flag] = val end
    end

    -- Spoof debug.info (per-flag reconstruction)
    local function hookDebugInfo(orig)
        if getType(orig) ~= "function" then return end
        pcall(hookfunction, orig, newcclosure(function(target, what, ...)
            if target == detected or target == killFunc then
                local results = {}
                for i = 1, #what do
                    local flag = string.sub(what, i, i)
                    if sig[flag] ~= nil then
                        results[#results + 1] = sig[flag]
                    end
                end
                return unpack(results)
            end
            return orig(target, what, ...)
        end))
    end
    hookDebugInfo(debug.info)
    if getType(getrenv) == "function" then hookDebugInfo(getrenv().debug.info) end
    if getType(debug.getinfo) == "function" then hookDebugInfo(debug.getinfo) end
    warn("[Syphon] debug.info spoofed")

    -- Spoof iscclosure (Potassium exposes this; defense-in-depth)
    if getType(iscclosure) == "function" then
        local origCc = iscclosure
        pcall(hookfunction, origCc, newcclosure(function(f, ...)
            if f == killFunc then return false end
            return origCc(f, ...)
        end))
        warn("[Syphon] iscclosure spoofed")
    end

    -- Block hookfunction re-hook attack
    local origHook = hookfunction
    pcall(hookfunction, origHook, newcclosure(function(f, wrapper)
        if f == detected then
            return newcclosure(function() return task.wait(9e9) end)
        end
        return origHook(f, wrapper)
    end))
    warn("[Syphon] hookfunction defended")

    -- ===== CORE: Upvalue Remapping =====
    if useSetupvalue and sendFunc and getType(sendFunc) == "function" then
        local ok3 = pcall(debug.setupvalue, detected, 3,
            newcclosure(function() return nil end))
        warn(string.format("[Syphon] uv3 (Send): %s", ok3 and "REMAP" or "FAIL"))

        if killFunc and getType(killFunc) == "function" then
            local ok9 = pcall(debug.setupvalue, detected, 9,
                newcclosure(function() return nil end))
            warn(string.format("[Syphon] uv9 (Kill): %s", ok9 and "REMAP" or "FAIL"))
        end
    else
        -- Fallback: hook Detected directly
        warn("[Syphon] Using Detected hook fallback")
        pcall(hookfunction, detected, newcclosure(function() return task.wait(9e9) end))
    end

    -- ===== Kill ALL server→client channels =====
    pcall(function()
        for _, child in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
            if child:IsA("RemoteEvent") and child:FindFirstChild("__FUNCTION") then
                local conns = getconnections(child.OnClientEvent)
                for _, conn in ipairs(conns) do
                    pcall(function() conn:Disconnect() end)
                end
                warn(string.format("[Syphon] Re %s: %d conns killed", child.Name, #conns))
            end
        end
    end)

    warn("[Syphon] Bypass armed")
    return true
end
bypassArmed = armBypass()


-- Task library fallback (for executors without native task library)
if not task or not task.wait then
    local _wait = wait or function(t) return _G.wait(t or 1/60) end
    local _spawn = spawn or function(fn) coroutine.wrap(fn)() end
    getgenv().task = {
        wait = _wait,
        spawn = _spawn,
        delay = function(t, fn) _spawn(function() _wait(t) fn() end) end,
    }
end

-- Ensure RobloxGui container exists (required by Rayfield)
local coreGui = game:GetService("CoreGui")
if not coreGui:FindFirstChild("RobloxGui") then
    local f = Instance.new("Folder")
    f.Name = "RobloxGui"
    f.Parent = coreGui
end

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

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer



-- ──────────────────────────────────────────────────────────
getgenv().RAYFIELD_SECURE = true
getgenv().RAYFIELD_ASSET_ID = 133114655245392
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VolleyLaunchEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("VolleyLaunch")
local LaunchMissileEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("LaunchMissile")
local MissileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MissileData"))

-- Utility: pcall that surfaces errors to console
local function safely(context, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[OrbitalStrike] " .. context .. ": " .. tostring(err))
    end
    return ok, err
end

-- ──────────────────────────────────────────────────────────
-- Config & State (all toggle states consolidated)
-- ──────────────────────────────────────────────────────────
local activeTargetPlayer = nil
local targetMode = "Bases" -- "Bases", "PlayerOnly", "CityRaid"
local isAutoFiring = false
local blatantAutoEnabled = false -- toggle for blatant continuous rapid fire
local blatantCooldown = 0.5 -- seconds between blatant salvos
local blatantSalvoSize = 250 -- missiles per blatant salvo
local autoCycleEnabled = false -- auto-switch target when current base is wiped
local autoCycleShieldNotified = false -- prevent shield notification spam
local targetPriorityMode = "None" -- "None", "Richest", "Weakest", "Custom"
local autoRejoinEnabled = false -- instantly rejoin on kick/disconnect
local defenseModeEnabled = false -- detect and respond to incoming attacks
local defenseShieldTypes = {["Good Shield"]=true, ["Big Shield"]=true, ["Hellstone Shield"]=true} -- which shields to use
local underAttackUntil = 0 -- os.clock() timestamp when attack alert expires
local lastAttackerName = nil -- name of the last player who attacked us
-- Dynamic coverage radii per shield type (half the force field X/Z extent)
local shieldCoverage = {
    ["Good Shield"] = 29,       -- force field 57×63 → ~29 stud radius
    ["Big Shield"] = 74,        -- force field 148×162 → ~74 stud radius
    ["Hellstone Shield"] = 122, -- force field 245×245 → ~122 stud radius
}
local targetPriorityList = {} -- custom player name priority list
local salvoSizeLimit = 250
local burstRemaining = 0 -- missiles left in current burst (0 = idle)
local selectedMissileTypes = {}
local firedCache = {}
local dispatchedDamage = {}
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
local autoRepairEnabled = false
local autoSpinBlackMarket = false
local autoSpinLucky = false
local autoClaimRewards = false
local autoClanClaimEnabled = false
local autoBuildMissilesToggleEnabled = false
local precisionBuildEnabled = false -- true = per-placement verify + retry; false = batch fire-and-forget
local autoBuildSelectedMissileTypes = {}
local precisionPlaceEnabled = false -- PlaceBuilding/PlaceShield grid placement from backpack tools
local isBuilding = false  -- mutex guard for auto-build

-- Session Stats
local sessionStats = {
    missilesFired = 0,
    totalDamage = 0,
    buildingsDestroyed = 0,
    basesWiped = 0,
    eloGained = 0,
}
local destroyedThisSession = {} -- [baseName] = count of buildings destroyed

-- AFK Mode Config
local afkModeEnabled = false
local afkFpsLimit = 30

-- Missile Threshold Alert
local missileAlertEnabled = false
local missileAlertThreshold = 10
local missileAlertLast = 0 -- prevents spam

-- UI Elements References (for Profile Loading UI Updates)
local modeDropdownUI = nil
local autoFireToggleUI = nil
local autoBuildToggleUI = nil
local autoBuildMissilesDropdownUI = nil
local weaponDropdownUI = nil
local autoBuyToggleUI = nil
local autoBuyMissilesDropdownUI = nil
local autoBuyBuildingsDropdownUI = nil
local autoBuyDefensesDropdownUI = nil
local cameraTrackingToggleUI = nil
local autoRepairToggleUI = nil
local autoSpinBlackMarketToggleUI = nil
local autoClaimRewardsToggleUI = nil
local priorityInputUI = nil
local salvoSizeInputUI = nil
local uiToggleKeybindUI = nil
local afkToggleUI = nil


-- Ordered Shop lists (Excluding Black Market Items)
local orderedMissiles = {
    "Stinger", "Silvershot", "Purple Phantom", "Beetle", "Nighthawk", "Falcon", "Fury",
    "Patriot", "Shadow", "Blue Bolt", "Bunker Buster", "Good Cannon", "Crimson Comet",
    "Sunspear", "Super Cannon", "Viper", "Frozone", "Mega Cannon", "Venom", "Goliath",
    "Super Missile", "Uncle Sam", "Firework Cannon", "Hellstone Cannon",
    "Colossal", "Javelin", "Doomsday"
}
local orderedBuildings = {
    "Basic House", "Small House", "Large House", "Motel", "Farm", "Trade Port",
    "Oil Rig", "Power Plant", "Apartment", "Bank", "Military Barracks", "Factory",
    "Industrial Factory", "SkyScraper", "Nuclear Plant", "Trade Tower",
    "Oil Refinery", "Gold Mine", "Quantum Tower", "Particle Accelerator"
}
local orderedDefenses = {
    "Scrap Turret", "Small Shield", "Twin Turret", "Good Shield", "Basic Turret",
    "Super Soldier", "Big Shield", "Hellstone Turret", "Firework Launcher", "Good Turret",
    "Mega Turret"
}

-- Priorities List
local priorityString = "PlacedTurrets, PlacedBuildings, PlacedShields"
local priorityList = {"PlacedTurrets", "PlacedBuildings", "PlacedShields"}

-- Missile Damage Map (precomputed once)
local missileDamage = {}
local cannonSet = {} -- set of cannon names for fast lookup
for name, data in pairs(MissileData) do
    missileDamage[name] = data.Damage or 0
    if data.IsCannon or name:lower():find("cannon") then
        cannonSet[name] = true
    end
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

-- Helper: Get Base by Player Name (improved robust fallback)
local function getBaseByPlayerName(name)
    if not name or name == "" then return nil end
    local basesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
    if basesFolder then
        for _, base in ipairs(basesFolder:GetChildren()) do
            local playerNameVal = base:FindFirstChild("PlayerInformation") and base.PlayerInformation:FindFirstChild("PlayerName")
            if playerNameVal and playerNameVal.Value == name then
                return base
            end
        end
    end
    return nil
end

local myBase = getBaseByPlayerName(LocalPlayer.Name)

-- Check and re-resolve base dynamically on access to handle respawn or map changes
local function getMyBase()
    if not myBase or not myBase.Parent then
        myBase = getBaseByPlayerName(LocalPlayer.Name)
    end
    return myBase
end

-- Find active CityRaid model in workspace
local function findCityRaidModel()
    local main = workspace:FindFirstChild("CityRaid")
    if main then return main end
    local map = workspace:FindFirstChild("Map")
    if map then
        main = map:FindFirstChild("CityRaid")
        if main then return main end
        for _, child in ipairs(map:GetChildren()) do
            if child:IsA("Model") and child.Name:lower():find("city") and child.Name:lower():find("raid") then
                return child
            end
        end
    end
    return nil
end

-- Get targetable components within a CityRaid model (Buildings only, turrets excluded)
local function getCityRaidTargets(cityRaid)
    local targets = {}
    local buildings = cityRaid:FindFirstChild("Buildings")
    if not buildings then return targets end

    for _, child in ipairs(buildings:GetChildren()) do
        local hp = child:GetAttribute("CityHP") or child:GetAttribute("HP")
        local maxHp = child:GetAttribute("CityMaxHP") or child:GetAttribute("MaxHP") or hp
        local isDead = child:GetAttribute("CityDead") or child:GetAttribute("Dead") or false

        if hp and hp > 0 and not isDead then
            local disp = dispatchedDamage[child] or 0
            local netHp = hp - disp
            if netHp > 0 then
                local isHighlighted = child:FindFirstChildOfClass("Highlight") ~= nil or child:FindFirstChildOfClass("SelectionBox") ~= nil
                if not isHighlighted then
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
                    hp = netHp,
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
    return obj.isHighlighted and 1 or 2
end

-- Find all targetable elements in a player's base
local function getTargetableObjects(targetPlayerName)
    local base = getBaseByPlayerName(targetPlayerName)
    if not base then return {} end

    local objects = {}
    local folderNames = {"PlacedTurrets", "PlacedShields", "PlacedBuildings"}

    for _, folderName in ipairs(folderNames) do
        local folder = base:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                local hp = child:GetAttribute("HP")
                local maxHp = child:GetAttribute("MaxHP")
                if hp and hp > 0 then
                    local disp = dispatchedDamage[child] or 0
                    local netHp = hp - disp
                    table.insert(objects, {
                        instance = child,
                        folder = folderName,
                        name = child.Name,
                        hp = netHp > 0 and netHp or 0.1, -- use net HP for priority but keep at 0.1 so it remains targetable
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
        if obj.folder == pName then
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
            if pA ~= pB then return pA < pB end
            return a.hp < b.hp
        end)

        return targets[1]
    elseif targetMode == "PlayerOnly" then
        local targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then return nil end

        -- 1. Check if there are active defenses protecting their base
        local baseObjects = getTargetableObjects(targetName)
        local defenses = {}
        for _, obj in ipairs(baseObjects) do
            if obj.folder == "PlacedTurrets" or obj.folder == "PlacedShields" then
                table.insert(defenses, obj)
            end
        end

        if #defenses > 0 then
            table.sort(defenses, function(a, b) return a.hp < b.hp end)
            return defenses[1]
        end

        return nil
    else
        -- Default: Bases Target Mode
        local objects = getTargetableObjects(targetName)
        if #objects == 0 then return nil end

        table.sort(objects, function(a, b)
            local scoreA = getPriorityScore(a)
            local scoreB = getPriorityScore(b)
            if scoreA ~= scoreB then return scoreA < scoreB end
            return a.hp < b.hp
        end)

        return objects[1]
    end
end

-- Get all local ready missiles that match checked types
local function getReadyMissiles()
    local base = getMyBase()
    if not base then return {} end
    local placed = base:FindFirstChild("PlacedMissiles")
    if not placed then return {} end

    local ready = {}
    for _, m in ipairs(placed:GetChildren()) do
        if not cannonSet[m.Name] and selectedMissileTypes[m.Name] and not firedCache[m] then
            local prompt = m:FindFirstChild("LaunchPrompt", true) or m:FindFirstChild("CannonToggle", true)
            if prompt and prompt.Enabled then
                table.insert(ready, {
                    instance = m,
                    name = m.Name,
                    damage = missileDamage[m.Name] or 0
                })
            end
        end
    end

    -- Sort by damage ascending to prioritize weaker/cheaper missiles first, preserving rare event ones
    table.sort(ready, function(a, b)
        return a.damage < b.damage
    end)

    return ready
end

-- Helper: Get active target objects list based on target mode
local function getActiveTargetObjects(targetName)
    if not targetName or targetName == "" then return {} end

    -- Skip players with new player protection shield active
    local targetBase = getBaseByPlayerName(targetName)
    if targetBase then
        local baseShield = targetBase:FindFirstChild("BaseShield")
        if baseShield and baseShield:GetAttribute("IsProtectionShield") then
            return {} -- shielded, no targets available
        end
    end

    local objects = {}
    if targetMode == "CityRaid" or targetName == "City Raid" then
        local cityRaid = findCityRaidModel()
        if cityRaid then objects = getCityRaidTargets(cityRaid) end
    elseif targetMode == "PlayerOnly" then
        local targetPlayer = Players:FindFirstChild(targetName)
        if targetPlayer then
            local baseObjects = getTargetableObjects(targetName)
            for _, obj in ipairs(baseObjects) do
                if obj.folder == "PlacedTurrets" or obj.folder == "PlacedShields" then
                    table.insert(objects, obj)
                end
            end
        end
    else
        objects = getTargetableObjects(targetName)
    end
    return objects
end

-- Calculate salvo launch positions and targets based on HP and checklist rules
local function getSalvoLaunches(targetName, ready)
    local objects = getActiveTargetObjects(targetName)

    if #objects == 0 then return {} end

    -- Sort targets by HP descending (strongest first)
    table.sort(objects, function(a, b) return (a.hp or 0) > (b.hp or 0) end)

    -- Initialize remaining HP for each target
    local remainingHp = {}
    local targetMissileCounts = {}
    for _, obj in ipairs(objects) do
        remainingHp[obj] = obj.hp
        targetMissileCounts[obj] = 0
    end

    -- Allocate ready missiles sequentially (weakest/cheapest first)
    -- HP-aware: strongest-first until all targets are overkilled, then round-robin
    local launches = {}
    local totalToFire = math.min(#ready, salvoSizeLimit)
    local roundRobinIdx = 1

    for i = 1, totalToFire do
        local mInfo = ready[i]

        -- Find target with the highest remaining HP
        local bestTarget = nil
        local maxHpVal = -999999
        for _, obj in ipairs(objects) do
            if remainingHp[obj] > maxHpVal then
                maxHpVal = remainingHp[obj]
                bestTarget = obj
            end
        end

        -- If all targets overkilled, cycle round-robin to keep firing
        if maxHpVal <= 0 then
            if #objects == 0 then break end
            bestTarget = objects[roundRobinIdx]
            roundRobinIdx = (roundRobinIdx % #objects) + 1
        end

        if bestTarget then
            targetMissileCounts[bestTarget] = targetMissileCounts[bestTarget] + 1
            remainingHp[bestTarget] = remainingHp[bestTarget] - mInfo.damage

            table.insert(launches, {
                missile = mInfo.instance,
                missileName = mInfo.name,
                damage = mInfo.damage,
                targetPos = bestTarget.instance:GetPivot().Position,
                targetInstance = bestTarget.instance
            })
        end
    end

    return launches
end

-- Global cooldown tracker — all missile types share the same server cooldown
local nextFireTime = 0
local VOLLEY_LIMIT = 3      -- max per call (tested up to 5, 3 is optimal for throughput)
local VOLLEY_COOLDOWN = 1.5 -- minimum seconds between VolleyLaunch calls (verified)

-- Fire via VolleyLaunch with optimal batching and cooldown enforcement
local function fireVolley(launches)
    local firedCount = 0

    -- Group launches by missile name
    local byName = {}
    for _, launch in ipairs(launches) do
        if not byName[launch.missileName] then byName[launch.missileName] = {} end
        table.insert(byName[launch.missileName], launch)
    end

    -- Sort names by damage ascending (cheapest first)
    local sortedNames = {}
    for mName, _ in pairs(byName) do table.insert(sortedNames, mName) end
    table.sort(sortedNames, function(a, b) return (missileDamage[a] or 0) < (missileDamage[b] or 0) end)

    for _, mName in ipairs(sortedNames) do
        if not isAutoFiring and burstRemaining <= 0 then break end
        local group = byName[mName]
        -- Fire in chunks of VOLLEY_LIMIT
        for i = 1, #group, VOLLEY_LIMIT do
            if not isAutoFiring and burstRemaining <= 0 then break end
            local chunkEnd = math.min(i + VOLLEY_LIMIT - 1, #group)
            local targets = {}
            for j = i, chunkEnd do
                local launch = group[j]
                firedCache[launch.missile] = true
                task.delay(3.5, function() firedCache[launch.missile] = nil end)
                if launch.targetInstance then
                    local dmg = missileDamage[launch.missileName] or 500
                    local inst = launch.targetInstance
                    dispatchedDamage[inst] = (dispatchedDamage[inst] or 0) + dmg
                    task.delay(4.0, function()
                        if dispatchedDamage[inst] then
                            dispatchedDamage[inst] = dispatchedDamage[inst] - dmg
                            if dispatchedDamage[inst] <= 0 then dispatchedDamage[inst] = nil end
                        end
                    end)
                end
                table.insert(targets, launch.targetPos)
                firedCount = firedCount + 1
            end
            -- Enforce global cooldown before firing (abort if auto-fire stopped)
            local now = os.clock()
            while now < nextFireTime and (isAutoFiring or burstRemaining > 0) do
                task.wait(0.05)
                now = os.clock()
            end
            safely("VolleyLaunch", function() VolleyLaunchEvent:FireServer(mName, targets) end)
            nextFireTime = os.clock() + VOLLEY_COOLDOWN
        end
    end
    -- Track session stats
    sessionStats.missilesFired = sessionStats.missilesFired + firedCount
    for _, launch in ipairs(launches) do
        sessionStats.totalDamage = sessionStats.totalDamage + (missileDamage[launch.missileName] or 500)
    end
    return firedCount
end

-- Blatant rapid fire — fires all ready launchers at once
local function fireAllRapid(targetName)
    local ready = getReadyMissiles()
    if #ready == 0 then return 0 end
    local objects = getActiveTargetObjects(targetName)
    if #objects == 0 then return 0 end
    local fired = 0
    for _, mInfo in ipairs(ready) do
        local target = objects[(fired % #objects) + 1]
        firedCache[mInfo.instance] = true
        task.delay(3.5, function() firedCache[mInfo.instance] = nil end)
        if target.instance then
            local dmg = missileDamage[mInfo.name] or 500
            dispatchedDamage[target.instance] = (dispatchedDamage[target.instance] or 0) + dmg
            task.delay(4.0, function()
                if dispatchedDamage[target.instance] then
                    dispatchedDamage[target.instance] = dispatchedDamage[target.instance] - dmg
                    if dispatchedDamage[target.instance] <= 0 then dispatchedDamage[target.instance] = nil end
                end
            end)
        end
        pcall(function() LaunchMissileEvent:FireServer(mInfo.instance, target.instance:GetPivot().Position) end)
        fired = fired + 1
        if fired % 25 == 0 then task.wait(0.01) end
    end
    sessionStats.missilesFired = sessionStats.missilesFired + fired
    return fired
end


-- ──────────────────────────────────────────────────────────
-- Rayfield Window Construction
-- ──────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name = "Orbital Strike Command",
    LoadingTitle = "Orbital Strike Command",
    LoadingSubtitle = "by picksov",
    ConfigurationSaving = {
        Enabled = false
    },
    Discord = {
        Enabled = false
    },
    KeySystem = false
})

-- Tabs
local TargetTab = Window:CreateTab("💥 Target Controls", 4483362458)
local PriorityTab = Window:CreateTab("📊 Priority Sorting", 4483362458)
local WeaponTab = Window:CreateTab("💣 Weapon Checklist", 4483362458)
local BuyTab = Window:CreateTab("💰 Auto Buy", 4483362458)
local DefenseTab = Window:CreateTab("🛡️ Defense", 4483362458)
local MiscTab = Window:CreateTab("✨ Miscellaneous", 4483362458)
local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

-- ──────────────────────────────────────────────────────────
-- 1. Direct Target Controls Tab Elements
-- ──────────────────────────────────────────────────────────
TargetTab:CreateSection("Target Selector")

local selectedPlayerLabel = TargetTab:CreateLabel("Target Player: None")

local playerList = {}
local function refreshPlayerList()
    local list = {}
    if findCityRaidModel() then
        table.insert(list, "City Raid")
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(list, p.Name)
        end
    end
    playerList = list
    return list
end

refreshPlayerList()

-- Dynamic background monitor to auto-refresh target player dropdown
task.spawn(function()
    local lastCRAState = nil
    local lastPlayerCount = 0
    while true do
        task.wait(3.0)
        local currentCRA = findCityRaidModel() ~= nil
        local currentPC = #Players:GetPlayers()
        if currentCRA ~= lastCRAState or currentPC ~= lastPlayerCount then
            lastCRAState = currentCRA
            lastPlayerCount = currentPC
            pcall(function()
                if playerDropdown and not isAutoFiring then
                    -- Only refresh when not auto-firing (avoids overriding auto-cycle)
                    playerDropdown:Refresh(refreshPlayerList())
                end
            end)
        end
    end
end)

local playerDropdown = TargetTab:CreateDropdown({
    Name = "Select Target Player",
    Options = playerList,
    CurrentOption = "",
    MultipleOptions = false,
    Callback = function(Option)
        local opt = typeof(Option) == "table" and Option[1] or Option
        activeTargetPlayer = opt
        autoCycleShieldNotified = false
        selectedPlayerLabel:Set("Target Player: " .. tostring(opt))
    end,
})

TargetTab:CreateButton({
    Name = "🔄 Refresh Player Dropdown",
    Callback = function()
        playerDropdown:Refresh(refreshPlayerList())
    end,
})

TargetTab:CreateSection("System Status")

local statusParagraph = TargetTab:CreateParagraph({
    Title = "SYSTEM MONITOR",
    Content = "Status: IDLE\nTarget Component: None\nTarget HP: - / -"
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

TargetTab:CreateSection("Target Priority & Cycling")
TargetTab:CreateToggle({
    Name = "🔄 Auto-Cycle: Switch target when base is wiped",
    CurrentValue = false,
    Callback = function(Value)
        autoCycleEnabled = Value
    end,
})

TargetTab:CreateDropdown({
    Name = "Target Priority Order",
    Options = {"None", "Richest First", "Weakest First", "Custom Order"},
    CurrentOption = "None",
    MultipleOptions = false,
    Callback = function(Option)
        local opt = Option[1] or Option
        targetPriorityMode = opt
    end,
})

TargetTab:CreateInput({
    Name = "Custom Priority (comma-separated names)",
    PlaceholderText = "Player1, Player2, Player3",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local list = {}
        for name in string.gmatch(Text, "([^,]+)") do
            local clean = name:gsub("^%s*(.-)%s*$", "%1")
            if clean ~= "" then table.insert(list, clean) end
        end
        targetPriorityList = list
    end,
})

TargetTab:CreateSection("Firing Commands")

autoFireToggleUI = TargetTab:CreateToggle({
    Name = "⚡ Enable Auto-Fire",
    CurrentValue = false,
    Callback = function(Value)
        isAutoFiring = Value
    end,
})

salvoSizeInputUI = TargetTab:CreateInput({
    Name = "Missiles per Burst (Max 250)",
    PlaceholderText = "250",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val > 0 then
            salvoSizeLimit = math.clamp(val, 1, 250)
        else
            salvoSizeLimit = 250
        end
    end,
})

TargetTab:CreateButton({
    Name = "🔥 BURST FIRE",
    Callback = function()
        if not activeTargetPlayer then
            Rayfield:Notify({ Title = "Error", Content = "Choose a target player first!", Duration = 2.5 })
            return
        end
        local ready = getReadyMissiles()
        if #ready == 0 then
            Rayfield:Notify({ Title = "Error", Content = "No launchers ready!", Duration = 2.5 })
            return
        end
        if burstRemaining > 0 then
            Rayfield:Notify({ Title = "Busy", Content = "Burst already in progress (" .. burstRemaining .. " left). Use Emergency Stop to cancel.", Duration = 3 })
            return
        end
        burstRemaining = salvoSizeLimit
        Rayfield:Notify({
            Title = "Burst Fire",
            Content = "Firing " .. salvoSizeLimit .. " missiles at " .. activeTargetPlayer .. "...",
            Duration = 3
        })
    end,
})

TargetTab:CreateButton({
    Name = "🚨 EMERGENCY STOP",
    Callback = function()
        isAutoFiring = false
        burstRemaining = 0
        if autoFireToggleUI then pcall(function() autoFireToggleUI:Set(false) end) end
        Rayfield:Notify({ Title = "Stopped", Content = "Emergency stop triggered! Firing disabled.", Duration = 3 })
    end,
})

TargetTab:CreateSection("🔥 Blatant — Rapid Fire")

TargetTab:CreateToggle({
    Name = "💥 Enable Blatant Auto-Fire",
    CurrentValue = false,
    Callback = function(Value)
        blatantAutoEnabled = Value
    end,
})

TargetTab:CreateInput({
    Name = "Missiles per Blatant Salvo (Max 250)",
    PlaceholderText = "250",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val > 0 then blatantSalvoSize = math.clamp(val, 1, 250) end
    end,
})

TargetTab:CreateInput({
    Name = "Blatant Cooldown (seconds, 0 = none)",
    PlaceholderText = "0.5",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val >= 0 then blatantCooldown = val end
    end,
})

TargetTab:CreateButton({
    Name = "🔥 FIRE ALL",
    Callback = function()
        if not activeTargetPlayer then
            Rayfield:Notify({ Title = "Error", Content = "Choose a target player first!", Duration = 2.5 })
            return
        end
        local fired = fireAllRapid(activeTargetPlayer)
        if fired > 0 then
            Rayfield:Notify({ Title = "Blatant Fire", Content = "Fired " .. fired .. " missiles at once!", Duration = 3 })
        else
            Rayfield:Notify({ Title = "No Fire", Content = "No ready launchers or targets found.", Duration = 2.5 })
        end
    end,
})

TargetTab:CreateParagraph({
    Title = "Blatant Info",
    Content = "Fires missiles at maximum speed with no restrictions. Blatantly obvious cheating. Use at your own risk."
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
for name, data in pairs(MissileData) do
    if not cannonSet[name] then
        table.insert(sortedMissiles, name)
    end
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
        if not Options then return end
        local newSelected = {}
        for k, v in pairs(Options) do
            if type(k) == "number" and type(v) == "string" then
                newSelected[v] = true
            elseif type(k) == "string" and v == true then
                newSelected[k] = true
            end
        end
        selectedMissileTypes = newSelected
    end,
})

-- ──────────────────────────────────────────────────────────
-- 4. Auto Buy Tab Elements
-- ──────────────────────────────────────────────────────────
BuyTab:CreateSection("Auto-Buy Activation")

autoBuyToggleUI = BuyTab:CreateToggle({
    Name = "💰 Enable Auto-Buy",
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
        if not Options then return end
        local newSelected = {}
        for k, v in pairs(Options) do
            if type(k) == "number" and type(v) == "string" then
                newSelected[v] = true
            elseif type(k) == "string" and v == true then
                newSelected[k] = true
            end
        end
        autoBuySelectedMissiles = newSelected
    end,
})

autoBuyBuildingsDropdownUI = BuyTab:CreateDropdown({
    Name = "Auto-Buy Buildings",
    Options = orderedBuildings,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuyBuildings",
    Callback = function(Options)
        if not Options then return end
        local newSelected = {}
        for k, v in pairs(Options) do
            if type(k) == "number" and type(v) == "string" then
                newSelected[v] = true
            elseif type(k) == "string" and v == true then
                newSelected[k] = true
            end
        end
        autoBuySelectedBuildings = newSelected
    end,
})

autoBuyDefensesDropdownUI = BuyTab:CreateDropdown({
    Name = "Auto-Buy Defenses",
    Options = orderedDefenses,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuyDefenses",
    Callback = function(Options)
        if not Options then return end
        local newSelected = {}
        for k, v in pairs(Options) do
            if type(k) == "number" and type(v) == "string" then
                newSelected[v] = true
            elseif type(k) == "string" and v == true then
                newSelected[k] = true
            end
        end
        autoBuySelectedDefenses = newSelected
    end,
})

-- ──────────────────────────────────────────────────────────
-- 6. Miscellaneous Tab Elements
-- ──────────────────────────────────────────────────────────
MiscTab:CreateSection("Overlook Enemy Base")

cameraTrackingToggleUI = MiscTab:CreateToggle({
    Name = "📷 Overlook Enemy Base",
    CurrentValue = false,
    Callback = function(Value)
        trackingEnabled = Value
        if Value then
            local camera = workspace.CurrentCamera
            if camera then
                camera.CameraType = Enum.CameraType.Scriptable
                -- Determine target position (enemy base or current look-at)
                local lookTarget
                if activeTargetPlayer then
                    local eb = getBaseByPlayerName(activeTargetPlayer)
                    if eb then
                        lookTarget = eb:GetPivot().Position
                        local myPos = getMyBase() and getMyBase():GetPivot().Position or camera.CFrame.Position
                        local dir = (lookTarget - myPos).Unit
                        targetYaw = math.deg(math.atan2(dir.X, dir.Z))
                        targetPitch = 35
                    end
                end
                if not lookTarget then
                    lookTarget = camera.CFrame.Position + camera.CFrame.LookVector * 80
                    targetYaw, targetPitch = 45, 35
                end
                cameraTargetPos = lookTarget
                targetPos = lookTarget
                targetDist = 120

                -- Start from current camera position for smooth transition
                local currentOffset = camera.CFrame.Position - lookTarget
                cameraDistance = math.clamp(currentOffset.Magnitude, 40, 350)
                cameraYaw = math.deg(math.atan2(currentOffset.X, currentOffset.Z))
                cameraPitch = math.deg(math.asin(math.clamp(currentOffset.Y / cameraDistance, -1, 1)))
                activeTrackingEnd = 9e9
            end
        else
            pcall(function()
                local camera = workspace.CurrentCamera
                if camera and camera.CameraType == Enum.CameraType.Scriptable then
                    camera.CameraType = Enum.CameraType.Custom
                    local char = LocalPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then camera.CameraSubject = hum end
                end
            end)
            activeTrackingEnd = 0
        end
    end,
})

-- Effect removal — targets game's custom effects: ParticleEmitters, Trails, Beams, FireParts
local disableEffectsEnabled = false
local function setEffectsEnabled(enabled)
    for _, obj in ipairs(workspace:GetDescendants()) do
        local cn = obj.ClassName
        if cn == "ParticleEmitter" or cn == "Trail" or cn == "Beam" then
            pcall(function() obj.Enabled = enabled end)
        elseif cn == "Part" or cn == "MeshPart" then
            local n = obj.Name
            if n == "DestroyedFirePart" or n == "FirePart" or n == "FirePlaceholder" then
                pcall(function() obj.Transparency = enabled and 0 or 1 end)
            end
        end
    end
end
MiscTab:CreateToggle({
    Name = "🎨 Disable Missile Effects (Smoke/Explosions)",
    CurrentValue = false,
    Callback = function(Value)
        disableEffectsEnabled = Value
        setEffectsEnabled(not Value)
    end,
})

local hpOverlayEnabled = false
local hpBars = {} -- [building] = BillboardGui

MiscTab:CreateToggle({
    Name = "💚 Enemy HP Bars (Free Cam Overlay)",
    CurrentValue = false,
    Callback = function(Value)
        hpOverlayEnabled = Value
        if not Value then
            for _, bg in pairs(hpBars) do pcall(function() bg:Destroy() end) end
            hpBars = {}
        end
    end,
})

-- ──────────────────────────────────────────────────────────
-- 5. Defense Tab Elements
-- ──────────────────────────────────────────────────────────

DefenseTab:CreateSection("Defense Mode")
DefenseTab:CreateToggle({
    Name = "🛡️ Defense Mode — Detect incoming attacks",
    CurrentValue = false,
    Callback = function(Value)
        defenseModeEnabled = Value
        if not Value then underAttackUntil = 0 end
    end,
})
DefenseTab:CreateDropdown({
    Name = "Shields to Use for Defense",
    Options = {"Good Shield", "Big Shield", "Hellstone Shield"},
    CurrentOption = {"Good Shield", "Big Shield", "Hellstone Shield"},
    MultipleOptions = true,
    Callback = function(Options)
        local sel = {}
        for _, name in ipairs(Options) do sel[name] = true end
        defenseShieldTypes = sel
    end,
})

DefenseTab:CreateSection("Auto-Repair")

autoRepairToggleUI = DefenseTab:CreateToggle({
    Name = "🔧 Enable Auto-Repair",
    CurrentValue = false,
    Callback = function(Value)
        autoRepairEnabled = Value
    end,
})

DefenseTab:CreateSection("Precision Build")

local precisionPlaceToggleUI = nil
precisionPlaceToggleUI = DefenseTab:CreateToggle({
    Name = "🎯 Precision Place (Buildings + Defenses)",
    CurrentValue = false,
    Callback = function(Value)
        precisionPlaceEnabled = Value
    end,
})

MiscTab:CreateSection("Black Market Actions")

autoSpinBlackMarketToggleUI = MiscTab:CreateToggle({
    Name = "🎰 Auto-Spin Black Market (Gems)",
    CurrentValue = false,
    Callback = function(Value)
        autoSpinBlackMarket = Value
    end,
})
MiscTab:CreateToggle({
    Name = "🍀 Auto-Spin Lucky Spins",
    CurrentValue = false,
    Callback = function(Value)
        autoSpinLucky = Value
    end,
})

MiscTab:CreateSection("Rewards & Quests Auto-Claim")

autoClaimRewardsToggleUI = MiscTab:CreateToggle({
    Name = "🎁 Auto-Claim Quests & Rewards",
    CurrentValue = false,
    Callback = function(Value)
        autoClaimRewards = Value
    end,
})

MiscTab:CreateToggle({
    Name = "🏰 Auto-Claim Clan Mission Rewards",
    CurrentValue = false,
    Callback = function(Value)
        autoClanClaimEnabled = Value
    end,
})

MiscTab:CreateSection("Session Stats")

local statsParagraph = MiscTab:CreateParagraph({
    Title = "SESSION STATS",
    Content = "Missiles Fired: 0\nDamage Dealt: 0\nBuildings Destroyed: 0\nBases Wiped: 0\nELO Gained: 0"
})

DefenseTab:CreateSection("Missile Threshold Alert")

DefenseTab:CreateToggle({
    Name = "⚠️ Alert when Missile Count Drops Below Threshold",
    CurrentValue = false,
    Callback = function(Value)
        missileAlertEnabled = Value
    end,
})

DefenseTab:CreateInput({
    Name = "Missile Alert Threshold",
    PlaceholderText = "10",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val > 0 then missileAlertThreshold = val end
    end,
})

MiscTab:CreateSection("Tycoon Placement Actions")

-- Precompute Weapon Geometry: floor offset + directional horizontal footprints
-- After -90deg Z rotation: local-Y becomes world-X, local-Z stays world-Z
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
            -- After -90deg Z rotation: bbox local-X→world-Y(up), local-Y→world-X(horizontal), local-Z→world-Z(vertical)
            -- But GetBoundingBox doesn't reflect rotation, so swap manually:
            -- world-X footprint = local Y, world-Z footprint = local Z
            local u45 = Y - (bboxCF.Y - bboxSize.Y / 2)
            local stepX = bboxSize.Y + 0.2  -- row-direction: local-Y → world-X
            local stepZ = bboxSize.Z + 0.2  -- column-direction: local-Z → world-Z
            weaponGeometry[name] = { u45 = u45, stepX = stepX, stepZ = stepZ, size = bboxSize }
            clone:Destroy()
        else
            weaponGeometry[name] = { u45 = 2, stepX = 3.2, stepZ = 3.2, size = Vector3.new(4, 8, 4) }
        end
    end
end
precomputeWeaponGeometry()

-- Fast collision check — scans only our own base's placed items
local function canPlaceAt(cf, size, base)
    local pos = cf.Position
    local halfWorldX = size.Y / 2 + 1.0
    local halfWorldZ = size.Z / 2 + 1.0
    local folders = {"PlacedMissiles", "PlacedBuildings", "PlacedTurrets", "PlacedShields"}
    for _, folderName in ipairs(folders) do
        local folder = base:FindFirstChild(folderName)
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                local itemPos = nil
                if item:IsA("Model") then itemPos = item:GetPivot().Position
                elseif item:IsA("BasePart") then itemPos = item.Position end
                if itemPos then
                    local dx = math.abs(pos.X - itemPos.X)
                    local dz = math.abs(pos.Z - itemPos.Z)
                    if dx < halfWorldX and dz < halfWorldZ then return false end
                end
            end
        end
    end
    return true
end

-- Instant verification hook — tracks placements (tool removed) and pickups (tool added)
local placementCallbacks = {} -- [toolName] = {callback = fn, thread = co}
local pickupCallbacks = {}   -- [toolName] = {callback = fn, thread = co}
local function initPlacementHook()
    local backpack = LocalPlayer.Backpack
    local mt = getrawmetatable(backpack)
    if not mt then return end
    makewritable(mt)
    local oldNewindex = rawget(mt, "__newindex") or function() end
    rawset(mt, "__newindex", function(t, k, v)
        if type(k) == "string" then
            if v == nil then
                -- Tool removed: placement consumed
                local pending = placementCallbacks[k]
                if pending then
                    placementCallbacks[k] = nil
                    if pending.callback then pending.callback() end
                    if pending.thread then pcall(coroutine.resume, pending.thread) end
                end
            else
                -- Tool added: pickup returned or purchase arrived
                local pending = pickupCallbacks[k]
                if pending then
                    pickupCallbacks[k] = nil
                    if pending.callback then pending.callback() end
                    if pending.thread then pcall(coroutine.resume, pending.thread) end
                end
            end
        end
        return oldNewindex(t, k, v)
    end)
end
initPlacementHook()

-- Auto-Build: speed = batch-fire, precision = per-placement verify, gap-fill + retry
local function runAutoBuild()
    if isBuilding then return 0 end
    isBuilding = true
    local placedCount = 0
    local success, err = pcall(function()
        local base = getMyBase()
        if not base then return end
        local zone = base:FindFirstChild("PlacementZone")
        if not zone then return end
        local zoneCF = zone.CFrame
        local zoneSize = zone.Size
        local halfX = math.floor(zoneSize.X / 2)
        local halfZ = math.floor(zoneSize.Z / 2)

        -- Helper: wait for server (reduced polling thanks to Backpack hook)
        local placedFolder = base:FindFirstChild("PlacedMissiles")
        local function syncPlaced(minExpected)
            for attempt = 1, 15 do
                task.wait(0.05)
                local now = placedFolder and #placedFolder:GetChildren() or 0
                if now >= 250 or now >= minExpected then return now end
            end
            return placedFolder and #placedFolder:GetChildren() or 0
        end

        -- 1. Count tools in Backpack + Character (once per type)
        local toolCounts = {}
        local orderedToBuild = {}
        for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if child:IsA("Tool") and autoBuildSelectedMissileTypes[child.Name] then
                toolCounts[child.Name] = (toolCounts[child.Name] or 0) + 1
            end
        end
        if LocalPlayer.Character then
            for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                if child:IsA("Tool") and autoBuildSelectedMissileTypes[child.Name] then
                    toolCounts[child.Name] = (toolCounts[child.Name] or 0) + 1
                end
            end
        end

        for name, count in pairs(toolCounts) do
            local price = MissileData[name] and MissileData[name].Price or 0
            table.insert(orderedToBuild, {name = name, count = count, price = price})
        end
        table.sort(orderedToBuild, function(a, b) return a.price < b.price end)

        local fires = 0
        local scanMargin = 4

        -- ── Primary scan ──
        local wIndex = 0
        for _, info in ipairs(orderedToBuild) do
            if not autoBuildMissilesToggleEnabled then break end
            local name = info.name
            local geom = weaponGeometry[name] or { u45 = 2, stepX = 3.2, stepZ = 3.2, size = Vector3.new(4, 8, 4) }
            local isCannon = cannonSet[name]
            local upRotation = isCannon and CFrame.identity or CFrame.Angles(0, 0, -1.5707963267948966)
            local invRemaining = info.count

            local stepX = geom.stepX
            local stepZ = geom.stepZ
            for x = -halfX + scanMargin, halfX - scanMargin, stepX do
                if not autoBuildMissilesToggleEnabled or invRemaining <= 0 then break end
                for z = -halfZ + scanMargin, halfZ - scanMargin, stepZ do
                    if not autoBuildMissilesToggleEnabled or invRemaining <= 0 then break end
                    if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end

                    local localCF = CFrame.new(x, geom.u45, z) * upRotation
                    local worldCF = zoneCF:ToWorldSpace(localCF)

                    if precisionBuildEnabled then
                        if canPlaceAt(worldCF, geom.size, base) then
                            local placedFolder = base.PlacedMissiles
                            local before = placedFolder and #placedFolder:GetChildren() or 0
                            placementCallbacks[name] = {}
                            pcall(function() ReplicatedStorage.Events.PlaceMissile:FireServer(name, worldCF) end)
                            for _ = 1, 20 do
                                local now = placedFolder and #placedFolder:GetChildren() or 0
                                if now > before then placedCount = placedCount + 1; break end
                                if not placementCallbacks[name] then placedCount = placedCount + 1; break end
                                task.wait(0.02)
                            end
                            placementCallbacks[name] = nil
                            invRemaining = invRemaining - 1
                        end
                    else
                        -- Speed mode: canPlaceAt filters base structures (always synced); fire and forget
                        if canPlaceAt(worldCF, geom.size, base) then
                            pcall(function() ReplicatedStorage.Events.PlaceMissile:FireServer(name, worldCF) end)
                            fires = fires + 1
                            invRemaining = invRemaining - 1
                            if fires % 8 == 0 then task.wait(0.01) end
                        end
                    end
                end
            end
        end

        if not precisionBuildEnabled then
            -- Speed mode: wait for server, sync count, done (no gap-fill)
            task.wait(0.2)
            placedCount = placedFolder and #placedFolder:GetChildren() or fires
        end

        -- ── Gap-fill (precision mode only) ──
        if precisionBuildEnabled then
        local currentPlaced = base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0
        if autoBuildMissilesToggleEnabled and currentPlaced < 250 then
            local remainingTools = {}
            for _, info in ipairs(orderedToBuild) do
                local n = 0
                for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
                    if child.Name == info.name then n = n + 1 end
                end
                if LocalPlayer.Character then
                    for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                        if child.Name == info.name then n = n + 1 end
                    end
                end
                if n > 0 then table.insert(remainingTools, {name = info.name, price = info.price, inv = n}) end
            end
            table.sort(remainingTools, function(a, b) return a.price < b.price end)

            local gapFires = 0
            for _, rt in ipairs(remainingTools) do
                if not autoBuildMissilesToggleEnabled then break end
                if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end
                local geom = weaponGeometry[rt.name] or { u45 = 2, size = Vector3.new(4, 8, 4) }
                local upRotation = cannonSet[rt.name] and CFrame.identity or CFrame.Angles(0, 0, -1.5707963267948966)
                local invLeft = rt.inv

                for x = -halfX, halfX, 1.8 do
                    if not autoBuildMissilesToggleEnabled then break end
                    if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end
                    if invLeft <= 0 then break end
                    for z = -halfZ, halfZ, 1.8 do
                        if not autoBuildMissilesToggleEnabled then break end
                        if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end
                        if invLeft <= 0 then break end

                        local localCF = CFrame.new(x, geom.u45, z) * upRotation
                        local worldCF = zoneCF:ToWorldSpace(localCF)
                        if precisionBuildEnabled then
                            local placedFolder = base.PlacedMissiles
                            local before = placedFolder and #placedFolder:GetChildren() or 0
                            placementCallbacks[rt.name] = {}
                            pcall(function() ReplicatedStorage.Events.PlaceMissile:FireServer(rt.name, worldCF) end)
                            for _ = 1, 20 do
                                local now = placedFolder and #placedFolder:GetChildren() or 0
                                if now > before then placedCount = placedCount + 1; break end
                                if not placementCallbacks[rt.name] then placedCount = placedCount + 1; break end
                                task.wait(0.02)
                            end
                            placementCallbacks[rt.name] = nil
                        else
                            -- Speed mode: check canPlaceAt now that folders have synced
                            if canPlaceAt(worldCF, geom.size, base) then
                                pcall(function() ReplicatedStorage.Events.PlaceMissile:FireServer(rt.name, worldCF) end)
                                gapFires = gapFires + 1
                                placedCount = placedCount + 1
                                if gapFires % 10 == 0 then task.wait(0.01) end
                            end
                        end
                        invLeft = invLeft - 1
                    end
                end
            end

            -- Speed mode: fire-and-forget, no sync wait needed; precision: already counted above

            -- ── Precision retry: 1.0-stud sweep for remaining spots ──
            if precisionBuildEnabled and (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) < 250 then
                local retryTools = {}
                for _, info in ipairs(orderedToBuild) do
                    local n = 0
                    for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
                        if child.Name == info.name then n = n + 1 end
                    end
                    if LocalPlayer.Character then
                        for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                            if child.Name == info.name then n = n + 1 end
                        end
                    end
                    if n > 0 then table.insert(retryTools, {name = info.name, price = info.price}) end
                end
                table.sort(retryTools, function(a, b) return a.price < b.price end)

                for _, rt in ipairs(retryTools) do
                    if not autoBuildMissilesToggleEnabled then break end
                    if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end
                    local geom = weaponGeometry[rt.name] or { u45 = 2, size = Vector3.new(4, 8, 4) }
                    local upRotation = cannonSet[rt.name] and CFrame.identity or CFrame.Angles(0, 0, -1.5707963267948966)

                    for x = -halfX, halfX, 1.0 do
                        if not autoBuildMissilesToggleEnabled then break end
                        if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end
                        for z = -halfZ, halfZ, 1.0 do
                            if not autoBuildMissilesToggleEnabled then break end
                            if (base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0) >= 250 then break end

                            local localCF = CFrame.new(x, geom.u45, z) * upRotation
                            local worldCF = zoneCF:ToWorldSpace(localCF)
                            local placedFolder = base.PlacedMissiles
                            local before = placedFolder and #placedFolder:GetChildren() or 0
                            placementCallbacks[rt.name] = {}
                            pcall(function() ReplicatedStorage.Events.PlaceMissile:FireServer(rt.name, worldCF) end)
                            for _ = 1, 20 do
                                local now = placedFolder and #placedFolder:GetChildren() or 0
                                if now > before then placedCount = placedCount + 1; break end
                                if not placementCallbacks[rt.name] then placedCount = placedCount + 1; break end
                                task.wait(0.02)
                            end
                            placementCallbacks[rt.name] = nil
                            if (placedFolder and #placedFolder:GetChildren() or 0) >= 250 then break end
                        end
                    end
                end
            end
        end
        end -- precisionBuildEnabled gap-fill wrapper
    end)
    isBuilding = false
    if not success then warn("[Auto-Build Error]: " .. tostring(err)) end
    return placedCount
end

MiscTab:CreateParagraph({
    Title = "Placement Mode",
    Content = "SPEED (off): Fire-and-forget — places missiles as fast as possible with batch verification. Runs smoothly alongside auto-fire. May leave 1-3 spots unfilled due to server timing.\n\nPRECISION (on): Verifies every placement individually with retries. Fills every possible spot but is significantly slower. Use for setup, not combat."
})

MiscTab:CreateToggle({
    Name = "🎯 Precision Placement Mode",
    CurrentValue = false,
    Callback = function(Value)
        precisionBuildEnabled = Value
    end,
})

autoBuildToggleUI = MiscTab:CreateToggle({
    Name = "🏗️ Enable Auto-Build Missiles",
    CurrentValue = false,
    Flag = "autoBuildToggle",
    Callback = function(Value)
        autoBuildMissilesToggleEnabled = Value
        if not Value then
            isBuilding = false -- immediately release the build mutex
        end
    end,
})

autoBuildMissilesDropdownUI = MiscTab:CreateDropdown({
    Name = "Select Missiles to Auto-Build",
    Options = sortedMissiles, -- only missiles (no cannons, buildings, defenses)
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "autoBuildMissileSelection",
    Callback = function(Options)
        if not Options then return end
        local newSelected = {}
        for k, v in pairs(Options) do
            if type(k) == "number" and type(v) == "string" then
                newSelected[v] = true
            elseif type(k) == "string" and v == true then
                newSelected[k] = true
            end
        end
        autoBuildSelectedMissileTypes = newSelected
    end,
})

-- Clear placed MISSILE launchers only (not cannons, buildings, or defenses)
MiscTab:CreateButton({
    Name = "🗑️ Clear All Placed Missile Launchers",
    Callback = function()
        local base = getMyBase()
        if not base then
            Rayfield:Notify({ Title = "Error", Content = "Base not found!", Duration = 2.5 })
            return
        end
        local placed = base:FindFirstChild("PlacedMissiles")
        if not placed then
            Rayfield:Notify({ Title = "Info", Content = "No placed missiles to clear.", Duration = 2.5 })
            return
        end

        local itemsToPickup = {}
        for _, child in ipairs(placed:GetChildren()) do
            if not cannonSet[child.Name] then
                table.insert(itemsToPickup, child)
            end
        end

        if #itemsToPickup == 0 then
            Rayfield:Notify({ Title = "Info", Content = "No missile launchers to clear.", Duration = 2.5 })
            return
        end

        local player = game.Players.LocalPlayer
        local backpack = player.Backpack
        local char = player.Character

        local hammer = backpack:FindFirstChild("Hammer")
        if not hammer and char then
            hammer = char:FindFirstChild("Hammer")
        end

        if not hammer then
            Rayfield:Notify({ Title = "Error", Content = "Hammer tool not found in inventory!", Duration = 2.5 })
            return
        end

        -- Equip hammer
        pcall(function() hammer.Parent = char end)

        local count = 0
        for _, child in ipairs(itemsToPickup) do
            if child and child.Parent then
                pcall(function()
                    ReplicatedStorage.Events.PickupMissile:FireServer(child)
                end)
            end
        end
        -- Wait briefly for Backpack hook to confirm pickups
        task.wait(0.5)
        -- Count remaining items — they were picked up if gone from PlacedMissiles
        count = #itemsToPickup - (placed and #placed:GetChildren() or 0)

        task.wait(0.3) -- brief wait for final batch to process

        -- Unequip hammer
        pcall(function()
            if hammer and hammer.Parent == char then
                hammer.Parent = backpack
            end
        end)

        Rayfield:Notify({
            Title = "Launchers Cleared",
            Content = "Picked up " .. count .. " missile launchers (cannons preserved).",
            Duration = 3
        })
    end,
})

-- ──────────────────────────────────────────────────────────
-- 7. Settings Tab Elements
-- ──────────────────────────────────────────────────────────
SettingsTab:CreateSection("Profiles Preset Manager")

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
            clean = clean:gsub("%.json$", ""):gsub("%.JSON$", "")
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
        currentProfileSelection = Option[1] or Option
    end,
})

SettingsTab:CreateButton({
    Name = "🔄 Refresh Profile Presets",
    Callback = function()
        profileDropdown:Refresh(getProfileList())
    end,
})

local function getKeysFromMap(map)
    local list = {}
    for k, v in pairs(map) do
        if v then table.insert(list, k) end
    end
    return list
end

local function saveProfile(profileName)
    if not profileName or profileName == "" then
        Rayfield:Notify({Title = "Error", Content = "Invalid profile name!", Duration = 2.5})
        return
    end

    local data = {
        targetMode = targetMode,
        salvoSizeLimit = salvoSizeLimit,
        selectedMissileTypes = selectedMissileTypes,
        autoBuyEnabled = autoBuyEnabled,
        autoBuySelectedMissiles = autoBuySelectedMissiles,
        autoBuySelectedBuildings = autoBuySelectedBuildings,
        autoBuySelectedDefenses = autoBuySelectedDefenses,
        trackingEnabled = trackingEnabled,
        autoRepairEnabled = autoRepairEnabled,
        autoSpinBlackMarket = autoSpinBlackMarket,
        autoClaimRewards = autoClaimRewards,
        priorityString = priorityString,
        autoBuildMissilesToggleEnabled = autoBuildMissilesToggleEnabled,
        autoBuildSelectedMissileTypes = autoBuildSelectedMissileTypes,
        precisionPlaceEnabled = precisionPlaceEnabled
    }

    local success, err = pcall(function()
        if makefolder and writefile then
            if not isfolder("OrbitalStrikeConfigs") then makefolder("OrbitalStrikeConfigs") end
            writefile("OrbitalStrikeConfigs/" .. profileName .. ".json", HttpService:JSONEncode(data))
        end
    end)

    Rayfield:Notify({
        Title = success and "Success" or "Error",
        Content = success and ("Saved config: " .. profileName) or ("Failed: " .. tostring(err)),
        Duration = 3
    })
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
        -- Load state variables
        if data.targetMode ~= nil then targetMode = data.targetMode end
        if data.salvoSizeLimit ~= nil then salvoSizeLimit = data.salvoSizeLimit end
        if data.selectedMissileTypes ~= nil then selectedMissileTypes = data.selectedMissileTypes end
        if data.autoBuyEnabled ~= nil then autoBuyEnabled = data.autoBuyEnabled end
        if data.autoBuySelectedMissiles ~= nil then autoBuySelectedMissiles = data.autoBuySelectedMissiles end
        if data.autoBuySelectedBuildings ~= nil then autoBuySelectedBuildings = data.autoBuySelectedBuildings end
        if data.autoBuySelectedDefenses ~= nil then autoBuySelectedDefenses = data.autoBuySelectedDefenses end
        if data.trackingEnabled ~= nil then trackingEnabled = data.trackingEnabled end
        if data.autoRepairEnabled ~= nil then autoRepairEnabled = data.autoRepairEnabled end
        if data.autoSpinBlackMarket ~= nil then autoSpinBlackMarket = data.autoSpinBlackMarket end
        if data.autoClaimRewards ~= nil then autoClaimRewards = data.autoClaimRewards end
        if data.autoBuildMissilesToggleEnabled ~= nil then autoBuildMissilesToggleEnabled = data.autoBuildMissilesToggleEnabled end
        if data.autoBuildSelectedMissileTypes ~= nil then autoBuildSelectedMissileTypes = data.autoBuildSelectedMissileTypes end
        if data.precisionPlaceEnabled ~= nil then precisionPlaceEnabled = data.precisionPlaceEnabled end
        if data.priorityString ~= nil then
            priorityString = data.priorityString
            updatePriorityList(priorityString)
        end

        -- Update all UI elements to reflect loaded settings
        local displayMode = "Bases Mode (Priority Queue)"
        if targetMode == "PlayerOnly" then displayMode = "Player Mode (Defenses First)"
        elseif targetMode == "CityRaid" then displayMode = "City Raid Mode (No Turrets)" end

        if modeDropdownUI then pcall(function() modeDropdownUI:Set(displayMode) end) end
        if autoFireToggleUI then pcall(function() autoFireToggleUI:Set(isAutoFiring) end) end
        if salvoSizeInputUI then pcall(function() salvoSizeInputUI:Set(tostring(salvoSizeLimit)) end) end
        if weaponDropdownUI then pcall(function() weaponDropdownUI:Set(getKeysFromMap(selectedMissileTypes)) end) end
        if autoBuyToggleUI then pcall(function() autoBuyToggleUI:Set(autoBuyEnabled) end) end
        if autoBuyMissilesDropdownUI then pcall(function() autoBuyMissilesDropdownUI:Set(getKeysFromMap(autoBuySelectedMissiles)) end) end
        if autoBuyBuildingsDropdownUI then pcall(function() autoBuyBuildingsDropdownUI:Set(getKeysFromMap(autoBuySelectedBuildings)) end) end
        if autoBuyDefensesDropdownUI then pcall(function() autoBuyDefensesDropdownUI:Set(getKeysFromMap(autoBuySelectedDefenses)) end) end
        if cameraTrackingToggleUI then pcall(function() cameraTrackingToggleUI:Set(trackingEnabled) end) end
        if autoRepairToggleUI then pcall(function() autoRepairToggleUI:Set(autoRepairEnabled) end) end
        if autoSpinBlackMarketToggleUI then pcall(function() autoSpinBlackMarketToggleUI:Set(autoSpinBlackMarket) end) end
        if autoClaimRewardsToggleUI then pcall(function() autoClaimRewardsToggleUI:Set(autoClaimRewards) end) end
        if priorityInputUI then pcall(function() priorityInputUI:Set(priorityString) end) end
        if autoBuildToggleUI then pcall(function() autoBuildToggleUI:Set(autoBuildMissilesToggleEnabled) end) end
        if autoBuildMissilesDropdownUI then pcall(function() autoBuildMissilesDropdownUI:Set(getKeysFromMap(autoBuildSelectedMissileTypes)) end) end
        if precisionPlaceToggleUI then pcall(function() precisionPlaceToggleUI:Set(precisionPlaceEnabled) end) end

        Rayfield:Notify({ Title = "Success", Content = "Loaded profile: " .. profileName, Duration = 3 })
    end)
end

local saveProfileName = "default"
SettingsTab:CreateInput({
    Name = "New Profile Name",
    PlaceholderText = "default",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text) saveProfileName = Text end,
})

SettingsTab:CreateButton({
    Name = "💾 Save Current Config",
    Callback = function()
        saveProfile(saveProfileName)
        profileDropdown:Refresh(getProfileList())
    end,
})

SettingsTab:CreateButton({
    Name = "📂 Load Selected Profile",
    Callback = function() loadProfile(currentProfileSelection) end,
})

SettingsTab:CreateButton({
    Name = "📝 Overwrite Selected Profile",
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
   Name = "Keybind Example",
   CurrentKeybind = "Q",
   HoldToInteract = false,
   Flag = "Keybind1",
   Callback = function(Keybind) end,
})

uiToggleKeybindUI:Set("RightControl")

SettingsTab:CreateSection("Server Utilities")

SettingsTab:CreateButton({
    Name = "🔁 Rejoin Server",
    Callback = function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end,
})

SettingsTab:CreateSection("Auto-Rejoin")

SettingsTab:CreateToggle({
    Name = "🔁 Auto-Rejoin: Instantly rejoin on kick or disconnect",
    CurrentValue = false,
    Callback = function(Value)
        autoRejoinEnabled = Value
    end,
})

SettingsTab:CreateButton({
    Name = "🌐 Server Hop (Low Player Lobby)",
    Callback = function()
        local placeId = game.PlaceId
        local success, raw = pcall(function()
            return game:HttpGet("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100")
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

SettingsTab:CreateButton({
    Name = "🎲 Server Hop (Random)",
    Callback = function()
        local placeId = game.PlaceId
        local success, raw = pcall(function()
            return game:HttpGet("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?limit=100")
        end)
        if success and raw then
            local list = HttpService:JSONDecode(raw)
            if list and list.data then
                local candidates = {}
                for _, server in ipairs(list.data) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        table.insert(candidates, server)
                    end
                end
                if #candidates > 0 then
                    local pick = candidates[math.random(1, #candidates)]
                    pcall(function()
                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, pick.id, LocalPlayer)
                    end)
                end
            end
        end
    end,
})

SettingsTab:CreateSection("Community")

SettingsTab:CreateButton({
    Name = "💬 Copy Discord Invite",
    Callback = function()
        local invite = "discord.gg/"
        local success, code = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/picksov/Roblox/refs/heads/main/Discord")
        end)
        if success and code then
            invite = invite .. code:gsub("%s+", "")
            if setclipboard then
                setclipboard(invite)
                Rayfield:Notify({
                    Title = "Copied!",
                    Content = invite,
                    Duration = 4
                })
            end
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Failed to load invite: " .. tostring(code),
                Duration = 5
            })
        end
    end,
})

SettingsTab:CreateSection("AFK Mode")

SettingsTab:CreateParagraph({
    Title = "AFK Mode Info",
    Content = "Disables 3D rendering and applies an FPS cap to minimize resource usage.\nRecommended FPS: 30 (lower may cause script timing issues)."
})

afkToggleUI = SettingsTab:CreateToggle({
    Name = "💤 Enable AFK Mode",
    CurrentValue = false,
    Callback = function(Value)
        afkModeEnabled = Value
        pcall(function()
            if Value then
                -- Disable 3D rendering
                game:GetService("RunService"):Set3dRenderingEnabled(false)
                -- Apply FPS cap
                if setfpscap then setfpscap(afkFpsLimit) end
            else
                -- Re-enable 3D rendering
                game:GetService("RunService"):Set3dRenderingEnabled(true)
                -- Remove FPS cap
                if setfpscap then setfpscap(999) end
            end
        end)
    end,
})

SettingsTab:CreateInput({
    Name = "AFK FPS Limit",
    PlaceholderText = "30",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local val = tonumber(Text)
        if val and val >= 5 then
            afkFpsLimit = val
            if afkModeEnabled and setfpscap then
                pcall(function() setfpscap(afkFpsLimit) end)
            end
        end
    end,
})

-- ──────────────────────────────────────────────────────────
-- Background Threads & Event-Driven Logic
-- ──────────────────────────────────────────────────────────

-- Helper: Get current player cash balance
local function getMoney()
    local stats = LocalPlayer:FindFirstChild("playerstats") or LocalPlayer:FindFirstChild("leaderstats")
    if stats then
        local cash = stats:FindFirstChild("Cash") or stats:FindFirstChild("Money") or stats:FindFirstChild("Credits")
        if cash then return cash.Value end
    end
    return 0
end

-- Helper: Get the price of an item across all shop categories
local buildingPriceCache, defensePriceCache = nil, nil
local function getItemPrice(name)
    if MissileData[name] and MissileData[name].Price then
        return MissileData[name].Price
    end
    if not buildingPriceCache then
        pcall(function()
            local mod = ReplicatedStorage.Modules.Shared:FindFirstChild("BuildingData")
            if mod then buildingPriceCache = require(mod) end
        end)
    end
    if buildingPriceCache and buildingPriceCache[name] and buildingPriceCache[name].Price then
        return buildingPriceCache[name].Price
    end
    if not defensePriceCache then
        pcall(function()
            local mod = ReplicatedStorage.Modules.Shared:FindFirstChild("DefenseData")
            if mod then defensePriceCache = require(mod) end
        end)
    end
    if defensePriceCache and defensePriceCache[name] and defensePriceCache[name].Price then
        return defensePriceCache[name].Price
    end
    return nil -- unknown price, skip money check for this item
end

-- Helper: Get the repair cost of an item (uses cached BuildingData/DefenseData)
local function getRepairCost(name)
    if buildingPriceCache and buildingPriceCache[name] and buildingPriceCache[name].RepairCost then
        return buildingPriceCache[name].RepairCost
    end
    if defensePriceCache and defensePriceCache[name] and defensePriceCache[name].RepairCost then
        return defensePriceCache[name].RepairCost
    end
    -- Fallback: estimate 10% of item price when RepairCost not in data
    local price = getItemPrice(name)
    if price then
        return math.floor(price * 0.1)
    end
    return nil -- unknown, skip money check
end

-- Stock tracking — event-driven from game's own StockUpdated/MissileStockUpdated events.
-- Stores {itemName = stockCount} for all categories (names are unique across missiles/buildings/defenses).
-- nil = haven't received stock data yet (assume in stock until first update).
local currentStock = {}
local stockInitialized = false

pcall(function()
    local stockUpdatedEv = ReplicatedStorage.Events:FindFirstChild("StockUpdated")
    if stockUpdatedEv then
        stockUpdatedEv.OnClientEvent:Connect(function(stockTable, _timer)
            for name, count in pairs(stockTable) do
                currentStock[name] = count
            end
            stockInitialized = true
        end)
    end
end)

pcall(function()
    local missileStockUpdatedEv = ReplicatedStorage.Events:FindFirstChild("MissileStockUpdated")
    if missileStockUpdatedEv then
        missileStockUpdatedEv.OnClientEvent:Connect(function(stockTable)
            for name, count in pairs(stockTable) do
                currentStock[name] = count
            end
            stockInitialized = true
        end)
    end
end)

-- Check whether an item has stock available (true when stock unknown or > 0)
local function isInStock(name)
    if not stockInitialized then return true end       -- haven't received stock data yet, assume available
    local s = currentStock[name]
    if s == nil then return false end                  -- not in stock table, assume out of stock
    return s > 0
end

-- Purchase all selected auto-buy items, skipping out-of-stock items and items
-- the player can't afford. Re-checks money between categories.
local function purchaseCheckedInStockItems()
    if not autoBuyEnabled then return end
    local money = getMoney()

    for name, enabled in pairs(autoBuySelectedMissiles) do
        if enabled and isInStock(name) then
            local price = getItemPrice(name)
            if not price or money >= price then
                safely("PurchaseMissile:" .. name, function() ReplicatedStorage.Events.PurchaseMissile:FireServer(name, 1000) end)
                if price then money = money - price end
            end
        end
    end
    if next(autoBuySelectedMissiles) then task.wait(0.05) end

    money = getMoney()
    for name, enabled in pairs(autoBuySelectedBuildings) do
        if enabled and isInStock(name) then
            local price = getItemPrice(name)
            if not price or money >= price then
                safely("PurchaseBuilding:" .. name, function() ReplicatedStorage.Events.PurchaseBuilding:FireServer(name, 1000) end)
                if price then money = money - price end
            end
        end
    end
    if next(autoBuySelectedBuildings) then task.wait(0.05) end

    money = getMoney()
    for name, enabled in pairs(autoBuySelectedDefenses) do
        if enabled and isInStock(name) then
            local price = getItemPrice(name)
            if not price or money >= price then
                safely("PurchaseDefense:" .. name, function() ReplicatedStorage.Events.PurchaseDefense:FireServer(name, 1000) end)
                if price then money = money - price end
            end
        end
    end
end

local currentActiveObject = nil

-- ──────────────────────────────────────────────────────────
-- Target Monitor Loop (throttled, only updates when UI visible)
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    local function formatNumber(val)
        if not val then return "0" end
        if val >= 1e9 then return string.format("%.2fB", val / 1e9)
        elseif val >= 1e6 then return string.format("%.2fM", val / 1e6)
        elseif val >= 1e3 then return string.format("%.1fK", val / 1e3)
        else return tostring(math.floor(val)) end
    end

    while true do
        task.wait(0.3)
        if not Rayfield:IsVisible() then
            task.wait(2.0)
        else
            local firingState = "IDLE"
            if underAttackUntil > os.clock() then
                firingState = "🛡️ DEFENDING"
            elseif burstRemaining > 0 then
                firingState = "BURST (" .. burstRemaining .. " left)"
            elseif isAutoFiring then
                firingState = "STRIKING"
            end
            local statusStr = "Status: " .. firingState
            local componentStr = "Target Component: None"
            local hpStr = "Target HP: - / -"
            local estimationStr = "Est. Missiles to Destroy Base: N/A"

            if activeTargetPlayer then
                local nextTarget = findNextTarget(activeTargetPlayer)
                if nextTarget then
                    currentActiveObject = nextTarget.instance
                    componentStr = "Target Component: [" .. nextTarget.folder .. "] " .. nextTarget.name

                    local hp = nextTarget.instance:IsA("Humanoid") and nextTarget.instance.Health or (nextTarget.instance:GetAttribute("CityHP") or nextTarget.instance:GetAttribute("HP"))
                    local maxHp = nextTarget.instance:IsA("Humanoid") and nextTarget.instance.MaxHealth or (nextTarget.instance:GetAttribute("CityMaxHP") or nextTarget.instance:GetAttribute("MaxHP"))

                    if hp and maxHp then
                        hpStr = string.format("Target HP: %d / %d", hp, maxHp)
                    else
                        hpStr = "Target HP: Active"
                    end
                else
                    currentActiveObject = nil
                    componentStr = targetMode == "CityRaid" and "Target Component: Waiting for Raid..." or "Target Component: Wiped!"
                end

                -- Calculate total base HP and estimate missiles
                local targetObjects = getActiveTargetObjects(activeTargetPlayer)

                if #targetObjects > 0 then
                    local totalBaseHP = 0
                    for _, obj in ipairs(targetObjects) do totalBaseHP = totalBaseHP + (obj.hp or 0) end

                    local base = getMyBase()
                    local placedLaunchers = {}
                    local totalCannonDmg = 0
                    local cannonCounts = {}

                    if base and base:FindFirstChild("PlacedMissiles") then
                        for _, m in ipairs(base.PlacedMissiles:GetChildren()) do
                            local dmg = missileDamage[m.Name] or 0
                            if dmg > 0 and dmg < 1e9 then
                                if cannonSet[m.Name] then
                                    totalCannonDmg = totalCannonDmg + dmg
                                    cannonCounts[m.Name] = (cannonCounts[m.Name] or 0) + 1
                                else
                                    table.insert(placedLaunchers, { Name = m.Name, Damage = dmg })
                                end
                            end
                        end
                    end

                    if #placedLaunchers > 0 then
                        table.sort(placedLaunchers, function(a, b) return a.Damage < b.Damage end)

                        local strongest = placedLaunchers[#placedLaunchers]
                        local strongestCount = math.ceil(totalBaseHP / (strongest.Damage + totalCannonDmg))
                        local strongestEst = strongestCount .. "x " .. strongest.Name .. (totalCannonDmg > 0 and " (+ cannons)" or "")

                        local tempHP = totalBaseHP
                        local neededCounts = {}
                        local salvos = 0
                        while tempHP > 0 and salvos < 1000 do
                            salvos = salvos + 1
                            tempHP = tempHP - totalCannonDmg
                            if tempHP <= 0 then break end
                            for _, item in ipairs(placedLaunchers) do
                                tempHP = tempHP - item.Damage
                                neededCounts[item.Name] = (neededCounts[item.Name] or 0) + 1
                                if tempHP <= 0 then break end
                            end
                        end

                        local comboList = {}
                        local seen = {}
                        for _, item in ipairs(placedLaunchers) do
                            if neededCounts[item.Name] and neededCounts[item.Name] > 0 and not seen[item.Name] then
                                seen[item.Name] = true
                                table.insert(comboList, neededCounts[item.Name] .. "x " .. item.Name)
                            end
                        end

                        local cannonStrList = {}
                        for cname, ccount in pairs(cannonCounts) do
                            local unitDmg = missileDamage[cname] or 0
                            table.insert(cannonStrList, string.format("%dx %s (+%s ea)", ccount, cname, formatNumber(unitDmg)))
                        end

                        estimationStr = string.format("Est. (Total HP: %s):\n• Strongest: %s\n• Cannons: %s\n• Salvos: %d\n• Mix: %s",
                            formatNumber(totalBaseHP), strongestEst,
                            #cannonStrList > 0 and table.concat(cannonStrList, ", ") or "None",
                            salvos, #comboList > 0 and table.concat(comboList, ", ") or "N/A")
                    else
                        estimationStr = "Est. Missiles: N/A (Total HP: " .. formatNumber(totalBaseHP) .. ")"
                    end
                end
            else
                currentActiveObject = nil
            end

            local base = getMyBase()
            local readyCount = #getReadyMissiles()
            local totalPlaced = base and base:FindFirstChild("PlacedMissiles") and #base.PlacedMissiles:GetChildren() or 0
            statusStr = statusStr .. string.format(" | Ready: %d/%d", readyCount, totalPlaced)

            pcall(function()
                statusParagraph:Set({
                    Title = "SYSTEM MONITOR",
                    Content = statusStr .. "\n" .. componentStr .. "\n" .. hpStr .. "\n" .. estimationStr
                })
                statsParagraph:Set({
                    Title = "SESSION STATS",
                    Content = string.format("Missiles Fired: %d\nDamage Dealt: %s\nBuildings Destroyed: %d\nBases Wiped: %d\nELO Gained: %d",
                        sessionStats.missilesFired,
                        sessionStats.totalDamage >= 1e6 and string.format("%.1fM", sessionStats.totalDamage/1e6) or tostring(math.floor(sessionStats.totalDamage)),
                        sessionStats.buildingsDestroyed,
                        sessionStats.basesWiped,
                        sessionStats.eloGained)
                })
            end)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Blatant Auto-Fire Loop (rapid fire, no restrictions)
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.2)
    local lastBlatantFire = 0
    while true do
        if blatantAutoEnabled and activeTargetPlayer then
            local now = os.clock()
            if now - lastBlatantFire >= blatantCooldown then
                local ready = getReadyMissiles()
                if #ready > 0 then
                    local limit = math.min(#ready, blatantSalvoSize)
                    local objects = getActiveTargetObjects(activeTargetPlayer)
                    if #objects > 0 then
                        local fired = 0
                        for i = 1, limit do
                            local mInfo = ready[i]
                            local target = objects[(i % #objects) + 1]
                            firedCache[mInfo.instance] = true
                            task.delay(3.5, function() firedCache[mInfo.instance] = nil end)
                            if target.instance then
                                local dmg = missileDamage[mInfo.name] or 500
                                dispatchedDamage[target.instance] = (dispatchedDamage[target.instance] or 0) + dmg
                                task.delay(4.0, function()
                                    if dispatchedDamage[target.instance] then
                                        dispatchedDamage[target.instance] = dispatchedDamage[target.instance] - dmg
                                        if dispatchedDamage[target.instance] <= 0 then dispatchedDamage[target.instance] = nil end
                                    end
                                end)
                            end
                            pcall(function() LaunchMissileEvent:FireServer(mInfo.instance, target.instance:GetPivot().Position) end)
                            fired = fired + 1
                            if fired % 25 == 0 then task.wait(0.01) end
                        end
                        sessionStats.missilesFired = sessionStats.missilesFired + fired
                        lastBlatantFire = now
                    end
                end
            end
            task.wait(0.1)
        else
            task.wait(0.5)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Fire / Burst Loop (VolleyLaunch batching)
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.1) -- stagger from other threads
    while true do
        local shouldFire = isAutoFiring or burstRemaining > 0

        if shouldFire and activeTargetPlayer then
            -- Check if target player left or gained protection shield
            -- Skip validation for City Raid (not a player)
            local targetStillValid = true
            if activeTargetPlayer ~= "City Raid" then
                local targetPlayer = Players:FindFirstChild(activeTargetPlayer)
                if not targetPlayer then
                    targetStillValid = false
                else
                    local tb = getBaseByPlayerName(activeTargetPlayer)
                    local bs = tb and tb:FindFirstChild("BaseShield")
                    if bs and bs:GetAttribute("IsProtectionShield") then
                        targetStillValid = false
                        Rayfield:Notify({Title = "Shield Active", Content = activeTargetPlayer .. " has protection shield. Cycling target.", Duration = 3})
                    end
                end
            end

            if not targetStillValid then
                if autoCycleEnabled then
                    -- Find next available player
                    local playerList = refreshPlayerList()
                    local newTarget = nil
                    for _, name in ipairs(playerList) do
                        if name ~= activeTargetPlayer and Players:FindFirstChild(name) then
                            local objects = getActiveTargetObjects(name)
                            if #objects > 0 then newTarget = name; break end
                        end
                    end
                    if newTarget then
                        Rayfield:Notify({Title = "Target Invalid", Content = activeTargetPlayer .. " is not a valid target. Cycled to " .. newTarget .. ".", Duration = 3})
                        activeTargetPlayer = newTarget
                        pcall(function() selectedPlayerLabel:Set("Target Player: " .. newTarget) end)
                        pcall(function() playerDropdown:Set(newTarget) end)
                    else
                        isAutoFiring = false
                        burstRemaining = 0
                        pcall(function() autoFireToggleUI:Set(false) end)
                        Rayfield:Notify({Title = "Server Empty", Content = "Target left and no other players to cycle to. Auto-fire stopped.", Duration = 5})
                    end
                else
                    isAutoFiring = false
                    burstRemaining = 0
                    pcall(function() autoFireToggleUI:Set(false) end)
                    Rayfield:Notify({Title = "Target Invalid", Content = activeTargetPlayer .. " is not a valid target. Auto-fire stopped.", Duration = 3})
                end
            end

            local ready = getReadyMissiles()
            if #ready > 0 then
                local launches = {}
                safely("getSalvoLaunches", function()
                    launches = getSalvoLaunches(activeTargetPlayer, ready)
                end)
                -- Burst mode: cap launches at remaining count
                if burstRemaining > 0 and #launches > burstRemaining then
                    local trimmed = {}
                    for i = 1, burstRemaining do trimmed[i] = launches[i] end
                    launches = trimmed
                end
                if #launches > 0 then
                    local firedCount = 0
                    safely("fireVolley", function()
                        firedCount = fireVolley(launches)
                    end)
                    if burstRemaining > 0 then
                        burstRemaining = burstRemaining - firedCount
                        if burstRemaining <= 0 then
                            burstRemaining = 0
                            Rayfield:Notify({
                                Title = "Burst Complete",
                                Content = "All missiles in the burst have been fired.",
                                Duration = 3
                            })
                        end
                    end
                    task.wait(0.1)
                else
                    -- Check if no launches because targets are wiped vs. no ready missiles
                    local targetObjects = getActiveTargetObjects(activeTargetPlayer)
                    if isAutoFiring and #targetObjects == 0 and not autoCycleShieldNotified then
                        -- Check if shielded (notification only)
                        local tb = getBaseByPlayerName(activeTargetPlayer)
                        local bs = tb and tb:FindFirstChild("BaseShield")
                        if bs and bs:GetAttribute("IsProtectionShield") then
                            autoCycleShieldNotified = true
                            Rayfield:Notify({Title = "Shield Protected", Content = activeTargetPlayer .. " has a protection shield. Skipping.", Duration = 3})
                        end
                    end
                    if autoCycleEnabled and isAutoFiring and #targetObjects == 0 then
                        -- Build prioritized player list for server dominance
                        local playerList = refreshPlayerList()
                        if targetPriorityMode == "Richest" then
                            table.sort(playerList, function(a, b)
                                local pA, pB = Players:FindFirstChild(a), Players:FindFirstChild(b)
                                local cashA = pA and pA:FindFirstChild("leaderstats") and pA.leaderstats:FindFirstChild("Cash") and pA.leaderstats.Cash.Value or 0
                                local cashB = pB and pB:FindFirstChild("leaderstats") and pB.leaderstats:FindFirstChild("Cash") and pB.leaderstats.Cash.Value or 0
                                return cashA > cashB
                            end)
                        elseif targetPriorityMode == "Weakest" then
                            table.sort(playerList, function(a, b)
                                local objA, objB = getActiveTargetObjects(a), getActiveTargetObjects(b)
                                local hpA, hpB = 0, 0
                                for _, o in ipairs(objA) do hpA = hpA + (o.hp or 0) end
                                for _, o in ipairs(objB) do hpB = hpB + (o.hp or 0) end
                                return hpA < hpB
                            end)
                        elseif targetPriorityMode == "Custom" and #targetPriorityList > 0 then
                            local ordered = {}
                            local seen = {}
                            for _, name in ipairs(targetPriorityList) do
                                for _, pName in ipairs(playerList) do
                                    if pName:lower() == name:lower() and not seen[pName] then
                                        table.insert(ordered, pName)
                                        seen[pName] = true
                                    end
                                end
                            end
                            for _, pName in ipairs(playerList) do
                                if not seen[pName] then table.insert(ordered, pName) end
                            end
                            playerList = ordered
                        end
                        -- Find next player with targets
                        local newTarget = nil
                        local currentIdx = 0
                        for i, name in ipairs(playerList) do
                            if name == activeTargetPlayer then currentIdx = i; break end
                        end
                        for offset = 1, #playerList do
                            local idx = (currentIdx + offset - 1) % #playerList + 1
                            local name = playerList[idx]
                            if name ~= activeTargetPlayer then
                                local objects = getActiveTargetObjects(name)
                                if #objects > 0 then
                                    newTarget = name
                                    break
                                end
                            end
                        end
                        if newTarget then
                            sessionStats.basesWiped = sessionStats.basesWiped + 1
                            activeTargetPlayer = newTarget
                            autoCycleShieldNotified = false
                            pcall(function() selectedPlayerLabel:Set("Target Player: " .. newTarget) end)
                            pcall(function() playerDropdown:Set(newTarget) end)
                            Rayfield:Notify({
                                Title = "Target Cycled",
                                Content = "Switched to " .. newTarget .. " (previous base wiped).",
                                Duration = 3
                            })
                        else
                            isAutoFiring = false
                            pcall(function() autoFireToggleUI:Set(false) end)
                            Rayfield:Notify({
                                Title = "Server Wiped",
                                Content = "No targets remaining on any player. Auto-fire stopped.",
                                Duration = 5
                            })
                        end
                    end
                    if burstRemaining > 0 and not isAutoFiring then
                        burstRemaining = 0
                    end
                    task.wait(0.5)
                end
            else
                if burstRemaining > 0 and not isAutoFiring then
                    burstRemaining = 0
                end
                task.wait(0.5)
            end
        else
            if burstRemaining > 0 and not isAutoFiring then
                burstRemaining = 0
            end
            task.wait(0.5)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Build Background Thread
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.2) -- stagger
    while true do
        if autoBuildMissilesToggleEnabled and not isBuilding then
            -- Quick check: any selected missiles in inventory?
            local hasAny = false
            for name, _ in pairs(autoBuildSelectedMissileTypes) do
                for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
                    if child.Name == name then hasAny = true; break end
                end
                if hasAny then break end
                if LocalPlayer.Character then
                    for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                        if child.Name == name then hasAny = true; break end
                    end
                end
                if hasAny then break end
            end

            if hasAny then
                local base = getMyBase()
                local currentlyPlaced = base and base.PlacedMissiles and #base.PlacedMissiles:GetChildren() or 0
                if currentlyPlaced < 250 then
                    pcall(runAutoBuild)
                end
            end
            task.wait(2.5)
        else
            task.wait(3.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Buy Background Thread
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        if autoBuyEnabled then
            purchaseCheckedInStockItems()
            task.wait(1.5)
        else
            task.wait(5.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Repair Thread — priority-sorted, checks money before repairing
-- Priority: Turrets > Buildings (by repair cost, cheapest first) > Shields > Missiles
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.3)
    local folders = {"PlacedTurrets","PlacedBuildings","PlacedShields","PlacedMissiles"}
    local items, rebuild = {}, 0

    local function findAttr(obj, attr)
        while obj do
            local val = obj:GetAttribute(attr)
            if val ~= nil then return val end
            obj = obj.Parent
        end
        return nil
    end

    local function categoryPriority(folderName)
        if folderName == "PlacedTurrets" then return 1
        elseif folderName == "PlacedBuildings" then return 2
        elseif folderName == "PlacedShields" then return 3
        else return 4 end
    end

    while true do
        if autoRepairEnabled then
            local base = getMyBase()
            local char = LocalPlayer.Character
            if base and char then
                if rebuild <= 0 then
                    -- Rebuild faster when under attack, slower when idle
                    rebuild = (underAttackUntil > os.clock()) and 5 or 30
                    items = {}
                    for fi = 1, 4 do
                        local f = base:FindFirstChild(folders[fi])
                        if f then
                            for _, item in ipairs(f:GetChildren()) do
                                local hp = findAttr(item, "HP")
                                if hp and hp <= 0 and not findAttr(item, "IsConstructing") then
                                    local prompt = item:FindFirstChild("RepairPrompt", true)
                                    if prompt then
                                        items[#items+1] = {
                                            prompt = prompt,
                                            pos = item:GetPivot().Position,
                                            name = item.Name,
                                            repairCost = getRepairCost(item.Name),
                                            cat = folders[fi],
                                        }
                                    end
                                end
                            end
                        end
                    end
                    -- Sort: category priority first, then cheapest repair cost within category
                    table.sort(items, function(a, b)
                        local catA = categoryPriority(a.cat)
                        local catB = categoryPriority(b.cat)
                        if catA ~= catB then return catA < catB end
                        local costA = a.repairCost or math.huge
                        local costB = b.repairCost or math.huge
                        return costA < costB
                    end)
                end
                rebuild = rebuild - 1
                for _, it in ipairs(items) do
                    if not autoRepairEnabled then break end
                    -- Check money before repairing — skip items we can't afford
                    local money = getMoney()
                    if not it.repairCost or money >= it.repairCost then
                        char:PivotTo(CFrame.new(it.pos))
                        fireproximityprompt(it.prompt, 1)
                    end
                end
            end
            task.wait()
        else
            items, rebuild = {}, 0
            task.wait(4.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Precision Build Thread — uses PlaceBuilding/PlaceShield to grid-place backpack tools
-- Faster than shop purchase: tools already owned, just positioned via fast-place remotes
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.5)
    local PlaceBuilding = ReplicatedStorage.Events.PlaceBuilding
    local PlaceShield = ReplicatedStorage.Events.PlaceShield
    local buildingData = nil; pcall(function() buildingData = require(ReplicatedStorage.Modules.Shared.BuildingData) end)
    local defenseData = nil; pcall(function() defenseData = require(ReplicatedStorage.Modules.Shared.DefenseData) end)

    local function isPlaceable(name)
        if buildingData then local ok, _ = pcall(function() return buildingData[name] end); if ok then return true end end
        if defenseData then local ok, _ = pcall(function() return defenseData[name] end); if ok then return true end end
        return false
    end

    while true do
        if precisionPlaceEnabled then
            local base = getMyBase()
            local zone = base and base:FindFirstChild("PlacementZone")
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if zone and humanoid then
                -- Group backpack tools by name (only placeable types)
                local toolCounts = {}
                for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
                    if child:IsA("Tool") and isPlaceable(child.Name) then
                        toolCounts[child.Name] = (toolCounts[child.Name] or 0) + 1
                    end
                end
                -- Also count equipped tool
                local eq = char:FindFirstChildOfClass("Tool")
                if eq and isPlaceable(eq.Name) then
                    toolCounts[eq.Name] = (toolCounts[eq.Name] or 0) + 1
                end

                if next(toolCounts) then
                    -- Sort by cheapest repair cost first
                    local sorted = {}
                    for name, count in pairs(toolCounts) do
                        local cost = getRepairCost(name) or getItemPrice(name) or 999999999
                        sorted[#sorted+1] = {name = name, count = count, cost = cost}
                    end
                    table.sort(sorted, function(a, b) return a.cost < b.cost end)

                    local halfX = math.floor(zone.Size.X / 2) - 4
                    local halfZ = math.floor(zone.Size.Z / 2) - 4
                    local step = 8 -- 8-stud grid spacing

                    for _, info in ipairs(sorted) do
                        if not precisionPlaceEnabled then break end
                        local remaining = info.count
                        local isShield = info.name:find("Shield") ~= nil
                        local remote = isShield and PlaceShield or PlaceBuilding

                        for x = -halfX, halfX, step do
                            if remaining <= 0 or not precisionPlaceEnabled then break end
                            for z = -halfZ, halfZ, step do
                                if remaining <= 0 or not precisionPlaceEnabled then break end

                                -- Equip tool if not already holding it
                                local currentTool = char:FindFirstChildOfClass("Tool")
                                if not currentTool or currentTool.Name ~= info.name then
                                    humanoid:UnequipTools()
                                    task.wait(0.08)
                                    local tool = LocalPlayer.Backpack:FindFirstChild(info.name)
                                    if tool then
                                        humanoid:EquipTool(tool)
                                        task.wait(0.12)
                                    else
                                        remaining = 0
                                        break
                                    end
                                end

                                local localCF = CFrame.new(x, 0, z)
                                local worldCF = zone.CFrame:ToWorldSpace(localCF) * CFrame.Angles(0, 0, 0)
                                pcall(function() remote:FireServer(info.name, worldCF) end)
                                remaining = remaining - 1
                                task.wait(0.12)
                            end
                        end
                    end
                end
            end
            task.wait(2.0)
        else
            task.wait(4.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Spin Black Market Thread (event-driven, waits for ship arrival)
-- ──────────────────────────────────────────────────────────
local blackMarketShipActive = false
local blackMarketTimerEnd = 0

-- Listen for BlackMarketArrived server event
pcall(function()
    local bmArrived = ReplicatedStorage:WaitForChild("Events"):FindFirstChild("BlackMarketArrived")
    if bmArrived then
        bmArrived.OnClientEvent:Connect(function()
            blackMarketShipActive = true

            -- Read the rarity and look up duration from game CargoData
            local rarity = "Common"
            local ship = workspace:FindFirstChild("CargoShip")
            if ship then
                local rLabel = ship:FindFirstChild("CargoInfo") and ship.CargoInfo:FindFirstChild("TextLabels") and ship.CargoInfo.TextLabels:FindFirstChild("Rarity")
                if rLabel then
                    rarity = rLabel.Text or "Common"
                end
            end

            local CargoData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CargoData"))
            local duration = CargoData[rarity] and CargoData[rarity].RoundTripTime or 300
            blackMarketTimerEnd = os.clock() + duration

            task.spawn(function()
                task.wait(duration)
                if os.clock() >= blackMarketTimerEnd then
                    blackMarketShipActive = false
                end
            end)
        end)
    end
end)

-- Listen for OpenBlackMarket (confirms ship is at our base specifically)
pcall(function()
    local openBM = ReplicatedStorage:WaitForChild("Events"):FindFirstChild("OpenBlackMarket")
    if openBM then
        openBM.OnClientEvent:Connect(function()
            blackMarketShipActive = true
        end)
    end
end)

-- Monitor ship and seller presence directly under our base
task.spawn(function()
    while true do
        local base = getMyBase()
        if base then
            local hasShip = base:FindFirstChild("Pirate Ship") ~= nil
            local hasSeller = base:FindFirstChild("BlackmarketSeller") ~= nil

            if hasShip or hasSeller then
                blackMarketShipActive = true
            else
                blackMarketShipActive = false
            end
        else
            blackMarketShipActive = false
        end
        task.wait(2.0)
    end
end)

task.spawn(function()
    local spendGemsFn = ReplicatedStorage.Events:FindFirstChild("SpendGemsForSpin")
    local spendLuckyFn = ReplicatedStorage.Events:FindFirstChild("SpendLuckySpin")
    local function getGems()
        local gemsVal = LocalPlayer:FindFirstChild("playerstats") and LocalPlayer.playerstats:FindFirstChild("Gems") or (LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Gems"))
        return gemsVal
    end
    local function getLuckySpins()
        local ls = LocalPlayer:FindFirstChild("playerstats") and LocalPlayer.playerstats:FindFirstChild("LuckySpins") or (LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("LuckySpins"))
        return ls
    end
    -- Event-driven spin completion — no more blind waits
    local spinComplete = false
    pcall(function()
        local spinEv = ReplicatedStorage.Events:FindFirstChild("CargoSpinEvent")
        if spinEv then
            spinEv.OnClientEvent:Connect(function() spinComplete = true end)
        end
    end)

    while true do
        if autoSpinBlackMarket and blackMarketShipActive then
            -- Normal spin (gems)
            local gemsVal = getGems()
            if gemsVal and gemsVal.Value >= 25 then
                if spendGemsFn then
                    spinComplete = false
                    safely("SpendGemsForSpin", function() spendGemsFn:InvokeServer() end)
                    -- Wait for spin animation to complete (event-driven, 8s timeout fallback)
                    for _ = 1, 80 do
                        task.wait(0.1)
                        if spinComplete then break end
                    end
                end
            end
            -- Lucky spin
            if autoSpinLucky then
                local luckyVal = getLuckySpins()
                if luckyVal and luckyVal.Value > 0 and spendLuckyFn then
                    spinComplete = false
                    safely("SpendLuckySpin", function() spendLuckyFn:InvokeServer() end)
                    for _ = 1, 40 do
                        task.wait(0.1)
                        if spinComplete then break end
                    end
                end
            end
            task.wait(0.5)
        else
            task.wait(3.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Claim Quests, Daily & Tier Rewards Thread
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    -- Cache remote references once
    local claimDaily = ReplicatedStorage.Events:FindFirstChild("ClaimDailyReward")
    local claimFree = ReplicatedStorage.Events:FindFirstChild("ClaimFreeReward")
    local claimTier = ReplicatedStorage.Events:FindFirstChild("ClaimTierChest")
    local claimQuest = ReplicatedStorage.Events:FindFirstChild("ClaimQuest")

    while true do
        if autoClaimRewards then
            pcall(function()
                if claimDaily then claimDaily:InvokeServer() end
            end)

            pcall(function()
                if claimFree then claimFree:InvokeServer() end
            end)

            pcall(function()
                if claimTier then claimTier:FireServer() end
            end)

            if claimQuest then
                -- Try claiming all possible quest IDs (server ignores inactive/incomplete)
                pcall(function()
                    local QuestData = require(ReplicatedStorage.Modules.Shared.QuestData)
                    if QuestData and QuestData.ById then
                        for questId, _ in pairs(QuestData.ById) do
                            pcall(function() claimQuest:FireServer(questId) end)
                        end
                    end
                end)
            end

            -- Clan mission claim
            if autoClanClaimEnabled then
                pcall(function()
                    local claimClan = ReplicatedStorage.Events:FindFirstChild("ClaimClanMission")
                    if claimClan then claimClan:FireServer() end
                end)
            end

            task.wait(8.0)
        else
            task.wait(10.0)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Cinematic Free Camera: right-drag orbit (mouse locked), scroll zoom
-- Smooth lerp on all movements, auto-orbit when idle, no gimbal flip
-- ──────────────────────────────────────────────────────────
local UIS = game:GetService("UserInputService")
local mouseDeltaX, mouseDeltaY = 0, 0
local targetYaw, targetPitch, targetDist = 45, 40, 120
local targetPos = Vector3.zero

pcall(function()
    UIS.InputBegan:Connect(function(input, processed)
        if not trackingEnabled then return end
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isDraggingCamera = true
            UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isDraggingCamera = false
            UIS.MouseBehavior = Enum.MouseBehavior.Default
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not trackingEnabled then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement and isDraggingCamera then
            mouseDeltaX = mouseDeltaX + input.Delta.X
            mouseDeltaY = mouseDeltaY + input.Delta.Y
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            targetDist = math.clamp(targetDist - input.Position.Z * 6, 15, 350)
        end
    end)
end)

-- Initialize state
if cameraTargetPos then targetPos = cameraTargetPos end

game:GetService("RunService").RenderStepped:Connect(function(dt)
    if not trackingEnabled then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    camera.CameraType = Enum.CameraType.Scriptable

    -- Follow enemy base
    if activeTargetPlayer then
        local eb = getBaseByPlayerName(activeTargetPlayer)
        if eb then cameraTargetPos = eb:GetPivot().Position end
    end
    if cameraTargetPos then targetPos = cameraTargetPos end

    -- Apply orbit from mouse drag (no modulo — avoids 360° snap-back)
    if mouseDeltaX ~= 0 or mouseDeltaY ~= 0 then
        targetYaw = targetYaw - mouseDeltaX * 0.3
        targetPitch = math.clamp(targetPitch + mouseDeltaY * 0.3, -65, 65)
        mouseDeltaX, mouseDeltaY = 0, 0
    end

    -- Smooth lerp ALL camera values for cinematic feel
    cameraYaw = cameraYaw + (targetYaw - cameraYaw) * math.min(dt * 3, 1)
    cameraPitch = cameraPitch + (targetPitch - cameraPitch) * math.min(dt * 3, 1)
    cameraDistance = cameraDistance + (targetDist - cameraDistance) * math.min(dt * 4, 1)

    -- Compute camera position (spherical coords, pitch-clamped to avoid gimbal flip)
    local radYaw = math.rad(cameraYaw)
    local radPitch = math.rad(cameraPitch)
    local offset = Vector3.new(
        cameraDistance * math.cos(radPitch) * math.sin(radYaw),
        cameraDistance * math.sin(radPitch),
        cameraDistance * math.cos(radPitch) * math.cos(radYaw)
    )
    camera.CFrame = CFrame.new(targetPos + offset, targetPos)

    -- HP Overlay: BillboardGuis on enemy buildings
    if hpOverlayEnabled and activeTargetPlayer then
        local enemyBase = getBaseByPlayerName(activeTargetPlayer)
        if enemyBase then
            for _, fn in ipairs({"PlacedBuildings","PlacedTurrets","PlacedShields"}) do
                local folder = enemyBase:FindFirstChild(fn)
                if folder then
                    for _, item in ipairs(folder:GetChildren()) do
                        local hp = item:GetAttribute("HP")
                        local maxHp = item:GetAttribute("MaxHP")
                        if hp and maxHp and hp > 0 then
                            local bg = hpBars[item]
                            if not bg then
                                bg = Instance.new("BillboardGui")
                                bg.Name = "HPBar"
                                bg.Size = UDim2.new(6, 0, 1.2, 0)
                                bg.StudsOffset = Vector3.new(0, 8, 0)
                                bg.MaxDistance = 500
                                bg.AlwaysOnTop = true
                                bg.Parent = item
                                -- Outline
                                local ol = Instance.new("Frame")
                                ol.Name = "Outline"
                                ol.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
                                ol.BorderSizePixel = 0
                                ol.Size = UDim2.new(1, 0, 1, 0)
                                ol.Parent = bg
                                -- Dark fill behind HP
                                local bg2 = Instance.new("Frame")
                                bg2.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                                bg2.BorderSizePixel = 0
                                bg2.Position = UDim2.new(0, 1, 0, 1)
                                bg2.Size = UDim2.new(1, -2, 1, -2)
                                bg2.Parent = bg
                                -- Green HP bar
                                local bar = Instance.new("Frame")
                                bar.Name = "Bar"
                                bar.BackgroundColor3 = Color3.fromRGB(0, 210, 0)
                                bar.BorderSizePixel = 0
                                bar.Position = UDim2.new(0, 1, 0, 1)
                                bar.Size = UDim2.new(1, -2, 1, -2)
                                bar.Parent = bg
                                -- Percentage label
                                local label = Instance.new("TextLabel")
                                label.Name = "Pct"
                                label.BackgroundTransparency = 1
                                label.TextColor3 = Color3.fromRGB(255, 255, 255)
                                label.TextStrokeTransparency = 0
                                label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                                label.Font = Enum.Font.GothamBold
                                label.TextScaled = true
                                label.Size = UDim2.new(1, -2, 1, -2)
                                label.Position = UDim2.new(0, 1, 0, 1)
                                label.Parent = bg
                                hpBars[item] = bg
                            end
                            local ratio = hp / maxHp
                            local bar = hpBars[item]:FindFirstChild("Bar")
                            local pct = hpBars[item]:FindFirstChild("Pct")
                            if bar then
                                bar.Size = UDim2.new(ratio, -(2 * ratio), 1, -2)
                                bar.BackgroundColor3 = Color3.fromRGB(
                                    ratio < 0.5 and 255 or (255 * (1 - ratio) * 2),
                                    ratio > 0.5 and 255 or (255 * ratio * 2),
                                    0
                                )
                            end
                            if pct then
                                pct.Text = math.floor(ratio * 100) .. "%"
                            end
                        end
                    end
                end
            end
        end
        -- Clean bars for destroyed/removed items
        for item, bg in pairs(hpBars) do
            if not item.Parent or (item:GetAttribute("HP") or 0) <= 0 then
                bg:Destroy(); hpBars[item] = nil
            end
        end
    elseif not hpOverlayEnabled and next(hpBars) then
        for _, bg in pairs(hpBars) do bg:Destroy() end
        hpBars = {}
    end
end)

-- Refresh effect removal for newly spawned effects
task.spawn(function()
    while true do
        if disableEffectsEnabled then setEffectsEnabled(false) end
        task.wait(2.0)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Keybind synchronization loop
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    local lastBind = nil
    local targetBindObj = nil

    while true do
        task.wait(2.0)
        local currentBind = uiToggleKeybindUI and uiToggleKeybindUI.CurrentKeybind
        if currentBind and currentBind ~= lastBind then
            if not targetBindObj then
                pcall(function()
                    for _, obj in ipairs(getgc(true)) do
                        if type(obj) == "table" and obj.Name == "Rayfield Keybind" and type(obj.Set) == "function" then
                            targetBindObj = obj
                            break
                        end
                    end
                end)
            end
            if targetBindObj then
                lastBind = currentBind
                pcall(function() targetBindObj:Set(currentBind) end)
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Missile Threshold Alert — warns when placed missile count drops low
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        if missileAlertEnabled then
            local base = getMyBase()
            if base then
                local placed = base:FindFirstChild("PlacedMissiles")
                local count = placed and #placed:GetChildren() or 0
                if count < missileAlertThreshold and os.clock() - missileAlertLast > 15 then
                    missileAlertLast = os.clock()
                    Rayfield:Notify({
                        Title = "⚠️ LOW MISSILES",
                        Content = "Only " .. count .. " left (threshold: " .. missileAlertThreshold .. ")",
                        Duration = 5
                    })
                end
            end
        end
        task.wait(3.0)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Defense Mode Alert — notifies when under attack and auto-retaliates
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    local lastAlert = 0
    while true do
        if defenseModeEnabled and underAttackUntil > os.clock() then
            -- Show alert every 8 seconds while under attack
            if os.clock() - lastAlert > 8 then
                lastAlert = os.clock()
                local msg = lastAttackerName and ("Incoming fire from " .. lastAttackerName .. "! Auto-repair engaged.")
                    or "Incoming fire detected! Auto-repair engaged."
                Rayfield:Notify({
                    Title = "🛡️ DEFENSE ALERT",
                    Content = msg,
                    Duration = 5
                })
                -- Auto-target the attacker if no target is set
                if not activeTargetPlayer and lastAttackerName then
                    activeTargetPlayer = lastAttackerName
                    pcall(function() selectedPlayerLabel:Set("Target Player: " .. lastAttackerName) end)
                    pcall(function() playerDropdown:Set(lastAttackerName) end)
                end
            end
        end
        task.wait(2)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Missile launch tracking + Defense Mode incoming detection
-- ──────────────────────────────────────────────────────────
pcall(function()
    local function handleMissileAnimation(_, targetPos, __, playerInstance, ___)
        -- Defense mode: detect incoming enemy missiles + shield defense
        if defenseModeEnabled and playerInstance ~= LocalPlayer and playerInstance then
            local myBase = getMyBase()
            if myBase and targetPos and _ then
                local startPos = _
                local myPos = myBase:GetPivot().Position
                local dist = (targetPos - myPos).Magnitude
                if dist < 200 then
                    underAttackUntil = os.clock() + 10
                    lastAttackerName = playerInstance.Name
                    -- Shield defense: place shields at player position to protect nearby structures
                    local char = LocalPlayer.Character
                    if char then
                        local playerPos = char:GetPivot().Position
                        -- Find max coverage radius among existing shields covering the player
                        local maxCoverage = 0
                        local shields = myBase:FindFirstChild("PlacedShields")
                        if shields then
                            for _, shield in ipairs(shields:GetChildren()) do
                                local hp = shield:GetAttribute("HP")
                                if hp and hp > 0 then
                                    local radius = shieldCoverage[shield.Name]
                                    if radius then
                                        local sd = (shield:GetPivot().Position - playerPos).Magnitude
                                        if sd < radius and radius > maxCoverage then
                                            maxCoverage = radius
                                        end
                                    end
                                end
                            end
                        end
                        -- Place ALL selected shields bigger than what's already covering us
                        -- Spread positions so shields don't overlap
                        local shieldOrder = {"Hellstone Shield", "Big Shield", "Good Shield"}
                        local placed = 0
                        for _, shieldName in ipairs(shieldOrder) do
                            if defenseShieldTypes[shieldName] and shieldCoverage[shieldName] and shieldCoverage[shieldName] > maxCoverage then
                                local found = nil
                                for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
                                    if tool.Name == shieldName then found = tool; break end
                                end
                                if not found then
                                    for _, tool in ipairs(char:GetChildren()) do
                                        if tool.Name == shieldName then found = tool; break end
                                    end
                                end
                                if found then
                                    -- Offset each shield slightly so they don't all stack at player position
                                    local offsets = {Vector3.new(0,0,0), Vector3.new(10,0,10), Vector3.new(-10,0,-10)}
                                    local pos = playerPos + (offsets[placed + 1] or offsets[1])
                                    pcall(function()
                                        ReplicatedStorage.Events.PlaceShield:FireServer(shieldName, CFrame.new(pos))
                                    end)
                                    placed = placed + 1
                                    maxCoverage = shieldCoverage[shieldName]
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Friendly missile tracking (existing behavior)
        if playerInstance ~= LocalPlayer then return end
        local enemyBase = activeTargetPlayer and getBaseByPlayerName(activeTargetPlayer)
        if enemyBase then
            cameraTargetPos = enemyBase:GetPivot().Position
        elseif targetMode == "CityRaid" then
            local cityRaid = findCityRaidModel()
            cameraTargetPos = cityRaid and cityRaid:GetPivot().Position or targetPos
        else
            cameraTargetPos = targetPos
        end
    end

    ReplicatedStorage.Events.AnimateMissile.OnClientEvent:Connect(handleMissileAnimation)
    local AnimateCannonNuke = ReplicatedStorage.Events:FindFirstChild("AnimateCannonNuke")
    if AnimateCannonNuke then
        AnimateCannonNuke.OnClientEvent:Connect(handleMissileAnimation)
    end
end)

Rayfield:Notify({
    Title = "Orbital Strike Command",
    Content = "Orbital Strike Command script is loaded",
    Duration = 5,
    Image = "check",
})

-- ──────────────────────────────────────────────────────────
-- Session Stats Tracking — hooks building destruction events
-- ──────────────────────────────────────────────────────────
pcall(function()
    local bdEvent = ReplicatedStorage.Events:FindFirstChild("BuildingDestroyedNotify")
    if bdEvent then
        bdEvent.OnClientEvent:Connect(function()
            sessionStats.buildingsDestroyed = sessionStats.buildingsDestroyed + 1
        end)
    end
end)

-- Anti-AFK (Bypasses Roblox idle disconnect automatically)
pcall(function()
    LocalPlayer.Idled:Connect(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)

-- ──────────────────────────────────────────────────────────
-- Auto-Rejoin — queues scripts for teleport, hooks Kick to rejoin
-- ──────────────────────────────────────────────────────────
task.spawn(function()
    if queueonteleport then
        queueonteleport([[
            task.wait(3)
            pcall(function() loadstring(game:HttpGet('https://raw.githubusercontent.com/picksov/Roblox/refs/heads/main/syphon-bypass.lua'))() end)
            task.wait(5)
            pcall(function() loadstring(game:HttpGet('https://raw.githubusercontent.com/picksov/Roblox/refs/heads/main/orbital-strike-command.lua'))() end)
        ]])
    end
end)

-- Hook Kick to teleport to a new server instead of closing
task.spawn(function()
    while true do
        if autoRejoinEnabled then
            pcall(function()
                local oldKick = LocalPlayer.Kick
                if oldKick and type(hookfunction) == "function" then
                    pcall(hookfunction, oldKick, function(msg)
                        local placeId = game.PlaceId
                        local raw = game:HttpGet("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=10")
                        local data = game:GetService("HttpService"):JSONDecode(raw)
                        if data and data.data then
                            for _, server in ipairs(data.data) do
                                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                                    pcall(function()
                                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                                    end)
                                    break
                                end
                            end
                        end
                    end)
                end
            end)
        end
        task.wait(30)
    end
end)
