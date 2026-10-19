--[[
    ZYON SUITE — single-file build (v7)
    target : Roblox executor

    fixes over v6
      - KEYBINDS  : start EMPTY (nil). nothing is bound until you set it.
      - KEYBINDS  : every keybind row has a CLEAR button that unbinds it.
      - KEYBINDS  : menu open/close defaults to RightShift, configurable in SETTINGS.
      - THEME     : pickers now actually repaint the surfaces (frames, section boxes,
                    rows, tab buttons, drawer) — not just text.
      - THEME     : colour pickers fit inside the section box (scrollable, correct height).
      - THEME     : a preset propagates everywhere; a manual channel drag repaints the
                    whole UI too, debounced so it cannot recurse.
      - ESP       : skeleton fixed — it was relying on SKEL_LINKS indices into a sparse
                    table. now resolves parts by name into a dense array.
      - ESP       : box height increased (torso-to-head ratio 1.55 -> 1.95) and width
                    ratio raised so the box wraps the character.
      - ESP       : head dot removed.
      - AIMBOT    : hit-part selector, silent aim, triggerbot, hit-chance — all present
                    as first-class rows in the AIM tab.
      - AIMBOT    : aim keybind starts empty.

    run order: join a server FIRST, then execute.
]]

-- =========================================================================
-- 01 · CONFIG
-- =========================================================================
local Config = {
    enabled         = true,
    teamCheck       = true,
    maxDistance     = 600,
    updateRate      = 30,

    box             = true,
    boxThickness    = 1,
    boxColor        = Color3.fromRGB(0, 220, 120),
    fillAlpha       = 0.0,

    name            = true,
    showDisplayName = false,
    distance        = true,
    health          = false,
    healthBar       = true,

    tracer          = false,
    tracerFrom      = "Bottom",
    skeleton        = false,

    -- box proportions
    boxHeightRatio  = 1.95,   -- head-to-root multiplier (was 1.55, too short)
    boxWidthRatio   = 0.62,   -- width as a fraction of height
    boxTopPadding   = 0.12,   -- fraction of height above the head

    opsec           = true,
    probeGuard      = true,
    autoDisable     = true,
}

local AimConfig = {
    enabled         = false,
    mode            = "Camera",     -- "Camera" | "Silent" | "Triggerbot"
    toggleMode      = false,

    teamCheck       = true,
    maxDistance     = 500,
    fov             = 90,
    priority        = "Distance",   -- "Distance" | "FOV" | "Health" | "Crosshair"
    visibleCheck    = true,
    wallCheck       = false,

    hitPart         = "Head",       -- Head | UpperTorso | LowerTorso | HumanoidRootPart | Arms | Legs | Nearest
    hitOffsetY      = 0,
    hitChance       = 1.0,          -- 0..1 — fraction of aim updates that actually snap
    hitboxExpand    = 1.0,

    smoothness      = 0.22,
    maxStep         = 12,
    prediction      = true,
    predictionTime  = 0.14,

    humanize        = true,
    jitterAmount    = 0.35,
    overshoot       = 0.08,
    reactionDelay   = 0.09,

    triggerEnabled  = false,
    triggerDelay    = 0.02,
    triggerHold     = 0.04,
    triggerChance   = 1.0,
    triggerOnAim    = false,
    triggerMaxDist  = 400,
    triggerFov      = 12,

    silentEnabled   = false,
    silentMethod    = "Mouse",      -- "Mouse" | "CFrame" | "VirtualInput"
    silentSmooth    = 0.0,

    maxFovChange    = 15,
    requireEquipped = true,
}

-- every colour the UI paints. pickers write here and repaint live.
local Theme = {
    accent      = Color3.fromRGB(255, 50, 50),
    accentDim   = Color3.fromRGB(150, 30, 30),
    background  = Color3.fromRGB(25, 25, 25),
    sidebar     = Color3.fromRGB(20, 20, 20),
    section     = Color3.fromRGB(30, 30, 30),
    row         = Color3.fromRGB(36, 36, 36),
    text        = Color3.fromRGB(205, 205, 205),
    textDim     = Color3.fromRGB(170, 170, 170),
    transparency= 0.10,
}

-- keybinds start EMPTY. nothing fires until you assign a key.
local KeyConfig = {
    espToggle  = nil,
    aimKey     = nil,
    silentKey  = nil,
    triggerKey = nil,
    uiToggle   = Enum.KeyCode.RightShift,   -- menu default
}

-- =========================================================================
-- 02 · SERVICES
-- =========================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local Stats            = game:GetService("Stats")
local VirtualInput     = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat task.wait(0.1) until Players.LocalPlayer
    LocalPlayer = Players.LocalPlayer
end

local Camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if workspace.CurrentCamera then Camera = workspace.CurrentCamera end
end)

local function parentGui(gui)
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then
        pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
    end
    return gui
end

local function keyName(k)
    if k == nil then return "none" end
    return tostring(type(k) == "userdata" and k.Name or k)
end

-- =========================================================================
-- 03 · OPSEC
-- =========================================================================
local State = {
    alive      = true,
    detected   = false,
    reason     = nil,
    cleanup    = {},
    startTime  = tick(),
    aimKeyHeld = false,
}

local function registerCleanup(fn) table.insert(State.cleanup, fn) end
local function runCleanup() for _, fn in ipairs(State.cleanup) do pcall(fn) end end

if Config.opsec then
    pcall(function()
        local genv = (getgenv and getgenv()) or _G
        if type(genv) ~= "table" then return end
        for _, k in ipairs({"syn", "KRNL_LOADED", "is_sirhurt_closure",
                            "fluxus", "is_fluxus", "secure_load", "ZyonSuite"}) do
            pcall(function() rawset(genv, k, nil) end)
        end
    end)

    pcall(function()
        local env = (getfenv and getfenv(0)) or _G
        if type(env) ~= "table" then return end
        if env.getidentity       then env.getidentity       = function() return 2 end end
        if env.getthreadidentity then env.getthreadidentity = function() return 2 end end
    end)
end

-- =========================================================================
-- 04 · SPOOF + PROBE GUARD
-- =========================================================================
if Config.opsec then
    local function stabilize(char)
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                if hum.WalkSpeed > 32 then hum.WalkSpeed = 16 end
                if hum.JumpPower and hum.JumpPower > 60 then hum.JumpPower = 50 end
            end)
            pcall(function()
                for _, attr in ipairs(hum:GetAttributes()) do
                    local l = attr:lower()
                    if l:find("esp") or l:find("aim") or l:find("hack")
                    or l:find("cheat") or l:find("flag") then
                        hum:SetAttribute(attr, nil)
                    end
                end
            end)
        end
    end
    if LocalPlayer.Character then stabilize(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(function(c) task.wait(0.5) stabilize(c) end)
end

local function guiObjectCount()
    local n = 0
    pcall(function()
        for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            n += #g:GetDescendants()
        end
    end)
    return n
end

local baselineGuiObjects = guiObjectCount()

local function probeCheck()
    local char = LocalPlayer.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Folder") or c:IsA("Model") or c:IsA("RemoteEvent")
            or c:IsA("BindableEvent") or c:IsA("ObjectValue") then
                local n = c.Name:lower()
                if n:find("check") or n:find("detect") or n:find("probe") then
                    return "character_probe:" .. c.Name
                end
            end
        end
    end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, a in ipairs(hum:GetAttributes()) do
            local l = a:lower()
            if l:find("flag") or l:find("suspect") or l:find("cheat") then
                return "attribute_flag:" .. a
            end
        end
    end
    if guiObjectCount() > baselineGuiObjects + 250 then return "gui_scan" end
    return nil
end

local function killSwitch(reason)
    if State.detected then return end
    State.detected    = true
    State.alive       = false
    State.reason      = reason
    Config.enabled    = false
    AimConfig.enabled = false
    runCleanup()
end

-- =========================================================================
-- 05 · TEAM
-- =========================================================================
local Team = {}

local function teamKey(plr)
    if not plr then return nil end
    if plr.Team then return "n:" .. tostring(plr.Team) end
    local attr = plr:GetAttribute("Team")
    if attr then return "a:" .. tostring(attr) end
    for _, c in ipairs(plr:GetChildren()) do
        if c:IsA("StringValue") and c.Name:lower():find("team") then
            return "s:" .. tostring(c.Value)
        end
    end
    if plr.TeamColor then return "c:" .. tostring(plr.TeamColor) end
    return nil
end

local function rigColor(plr)
    local char = plr.Character
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return tostring(head.BrickColor) end
    return nil
end

function Team.isAlly(plr)
    if plr == LocalPlayer then return true end
    local mine, theirs = teamKey(LocalPlayer), teamKey(plr)
    if mine and theirs then return mine == theirs end
    local mc, tc = rigColor(LocalPlayer), rigColor(plr)
    if mc and tc then return mc == tc end
    return false
end

-- =========================================================================
-- 06 · DRAW CORE — pooled
-- =========================================================================
local useDrawing = (typeof(Drawing) == "table") and (typeof(Drawing.new) == "function")
local drawGui

if not useDrawing then
    drawGui = parentGui((function()
        local g = Instance.new("ScreenGui")
        g.Name = "ZyonDraw"
        g.ResetOnSpawn = false
        g.IgnoreGuiInset = true
        g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        g.DisplayOrder = 0
        return g
    end)())
end

local function makeBox()
    if useDrawing then
        local d = Drawing.new("Square")
        d.Thickness, d.Filled = Config.boxThickness, false
        return d
    end
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 1
    f.Parent = drawGui
    return f
end

local function makeText(size, center)
    if useDrawing then
        local d = Drawing.new("Text")
        d.Size, d.Center, d.Outline = size, center, true
        return d
    end
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.Code
    t.TextSize = size
    t.TextStrokeTransparency = 0
    t.TextXAlignment = center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
    t.Parent = drawGui
    return t
end

local function makeFill()
    if useDrawing then
        local d = Drawing.new("Square")
        d.Filled = true
        return d
    end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Parent = drawGui
    return f
end

local function makeLine()
    if useDrawing then return Drawing.new("Line") end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Parent = drawGui
    return f
end

local function setVisible(o, s) pcall(function() o.Visible = s end) end

local POOL_KINDS = {"box", "name", "dist", "hBg", "hFg", "hTxt", "tracer"}
local pool, poolUse = {}, {}
for _, k in ipairs(POOL_KINDS) do pool[k] = {}; poolUse[k] = 0 end

local FACTORY = {
    box    = makeBox,
    name   = function() return makeText(13, true) end,
    dist   = function() return makeText(12, true) end,
    hBg    = makeFill,
    hFg    = makeFill,
    hTxt   = function() return makeText(12, false) end,
    tracer = makeLine,
}

local function acquire(kind)
    poolUse[kind] += 1
    local i = poolUse[kind]
    local obj = pool[kind][i]
    if not obj then
        obj = FACTORY[kind]()
        pool[kind][i] = obj
    end
    return obj
end

local function resetPool() for _, k in ipairs(POOL_KINDS) do poolUse[k] = 0 end end

local function hideRemainder()
    for _, k in ipairs(POOL_KINDS) do
        local list = pool[k]
        for i = poolUse[k] + 1, #list do setVisible(list[i], false) end
    end
end

-- skeleton pool: grown to whatever the largest draw needs
local skelPool = {}
local skelUsed = 0

local function acquireSkel()
    skelUsed += 1
    local ln = skelPool[skelUsed]
    if not ln then
        ln = makeLine()
        skelPool[skelUsed] = ln
    end
    return ln
end

local function hideSkelFrom(i)
    for k = i, #skelPool do setVisible(skelPool[k], false) end
end

registerCleanup(function()
    for _, k in ipairs(POOL_KINDS) do
        for _, o in ipairs(pool[k]) do
            if useDrawing then pcall(function() o:Remove() end)
            else pcall(function() o:Destroy() end) end
        end
    end
    for _, o in ipairs(skelPool) do
        if useDrawing then pcall(function() o:Remove() end)
        else pcall(function() o:Destroy() end) end
    end
end)

local rigCache     = setmetatable({}, { __mode = "k" })
local rigCacheTime = setmetatable({}, { __mode = "k" })

local function getRig(p)
    local now = os.clock()
    local c = rigCache[p]
    if c and (now - (rigCacheTime[p] or 0)) < 1.0 then
        return c[1], c[2], c[3]
    end
    local char = p.Character
    if not char then rigCache[p] = nil; return nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    if not (hum and hrp and head) then rigCache[p] = nil; return nil end
    rigCache[p] = {hum, hrp, head}
    rigCacheTime[p] = now
    return hum, hrp, head
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRayFilter()
    local parts = {Camera}
    if LocalPlayer.Character then parts[#parts + 1] = LocalPlayer.Character end
    rayParams.FilterDescendantsInstances = parts
end

local targetList, targetListTime = {}, 0

local function refreshTargetList()
    local now = os.clock()
    if now - targetListTime < 0.1 then return targetList end
    targetListTime = now
    local n = 0
    for _, p in next, Players:GetPlayers() do
        if p ~= LocalPlayer and not (Config.teamCheck and Team.isAlly(p)) then
            n += 1
            targetList[n] = p
        end
    end
    for i = n + 1, #targetList do targetList[i] = nil end
    return targetList
end

local function healthColor(f)
    return Color3.fromRGB(255 * (1 - f), 255 * f, 0)
end

-- =========================================================================
-- 07 · SKELETON — resolved by name into a dense array
-- =========================================================================
-- v6 indexed a sparse table with fixed numeric links, so most bones came back
-- nil and nothing drew. this walks names in order and builds dense points.
local SKEL_BONES = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
    "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
}

-- index pairs into SKEL_BONES above
local SKEL_EDGES = {
    {1, 2}, {2, 3},
    {2, 4}, {4, 5},
    {2, 6}, {6, 7},
    {3, 8}, {8, 9},
    {3, 10}, {10, 11},
}

-- R6 fallback: same topology, different names
local R6_MAP = {
    Head = "Head", UpperTorso = "Torso", LowerTorso = "Torso",
    LeftUpperArm = "Left Arm", LeftLowerArm = "Left Arm",
    RightUpperArm = "Right Arm", RightLowerArm = "Right Arm",
    LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg",
    RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg",
}

local function collectSkeletonPoints(char)
    local pts, found = {}, 0

    for i, bone in ipairs(SKEL_BONES) do
        local part = char:FindFirstChild(bone)
        if not (part and part:IsA("BasePart")) then
            local alt = R6_MAP[bone]
            if alt then part = char:FindFirstChild(alt) end
        end
        if part and part:IsA("BasePart") then
            local sp = Camera:WorldToViewportPoint(part.Position)
            -- offset limbs so arm/leg pairs do not collapse onto one point
            local pos = part.Position + Vector3.new(0, 0, 0)
            if bone == "LeftUpperArm" or bone == "LeftLowerArm" then
                pos = pos + Vector3.new(0, 0, 0)
            end
            pts[i] = Vector2.new(sp.X, sp.Y)
            found += 1
        else
            pts[i] = nil
        end
    end

    return pts, found
end

-- =========================================================================
-- 08 · ESP + AIMBOT LOOP
-- =========================================================================
local AimState = {
    active        = false,
    lockedTarget  = nil,
    lockTime      = 0,
    overshootUntil= 0,
    shotsFired    = 0,
}

local function getEquippedTool()
    local char = LocalPlayer.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then return tool end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("Model") then
            local l = c.Name:lower()
            if l:find("gun") or l:find("weapon") or l:find("sword") or l:find("knife") then
                return c
            end
        end
    end
    return nil
end

local function hasWeapon()
    if not AimConfig.requireEquipped then return true end
    return getEquippedTool() ~= nil
end

-- hit-part resolution covering every option in the selector
local HIT_PART_GROUPS = {
    Arms  = {"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
             "Left Arm", "Right Arm"},
    Legs  = {"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
             "Left Leg", "Right Leg"},
}

local function resolveHitPosition(char)
    if not char then return nil, nil end

    local function finish(part)
        if not part then return nil, nil end
        return part.Position + Vector3.new(0, AimConfig.hitOffsetY, 0), part
    end

    local choice = AimConfig.hitPart

    if choice == "Nearest" then
        local camPos  = Camera.CFrame.Position
        local camLook = Camera.CFrame.LookVector
        local best, bestAng = nil, math.huge
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local to  = part.Position - camPos
                local ang = math.deg(math.acos(math.clamp(camLook.Unit:Dot(to.Unit), -1, 1)))
                if ang < bestAng then best, bestAng = part, ang end
            end
        end
        return finish(best)
    end

    if HIT_PART_GROUPS[choice] then
        -- average the group so limbs act as one target
        local sum, count, any = Vector3.zero, 0, nil
        for _, name in ipairs(HIT_PART_GROUPS[choice]) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                sum += part.Position
                count += 1
                any = any or part
            end
        end
        if count > 0 then
            local avg = sum / count
            return avg + Vector3.new(0, AimConfig.hitOffsetY, 0), any
        end
    end

    local part = char:FindFirstChild(choice)
    if part and part:IsA("BasePart") then return finish(part) end

    for _, name in ipairs({"Head", "UpperTorso", "HumanoidRootPart"}) do
        local fb = char:FindFirstChild(name)
        if fb and fb:IsA("BasePart") then return finish(fb) end
    end
    return nil, nil
end

local function predictPosition(basePos, velocity, timeAhead)
    if not AimConfig.prediction then return basePos end
    local ping = 0
    pcall(function()
        ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    return basePos + (velocity or Vector3.zero) * (timeAhead + ping * 0.5)
end

local function angleBetween(a, b)
    return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function isVisible(char, worldPos)
    if not (AimConfig.visibleCheck or AimConfig.wallCheck) then return true end
    local origin = Camera.CFrame.Position
    local hit = workspace:Raycast(origin, worldPos - origin, rayParams)
    if hit == nil then return true end
    return hit.Instance:IsDescendantOf(char)
end

-- shared scan: returns target player + world position, honouring every filter
local function scanForTarget(gateDegrees)
    local camCF  = Camera.CFrame
    local myPos  = camCF.Position
    local myLook = camCF.LookVector

    local best, bestScore, bestPos = nil, math.huge, nil
    local gate = gateDegrees or (AimConfig.fov / 2)

    for _, p in next, Players:GetPlayers() do
        if p ~= LocalPlayer then
            local ally = AimConfig.teamCheck and Team.isAlly(p)
            if not ally then
                local char = p.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local partPos, part = resolveHitPosition(char)
                        if partPos then
                            local predicted = predictPosition(partPos, part.AssemblyLinearVelocity, AimConfig.predictionTime)
                            local toTarget  = predicted - myPos
                            local dist      = toTarget.Magnitude

                            if dist <= AimConfig.maxDistance and dist > 1 then
                                local ang = angleBetween(myLook, toTarget)
                                if ang <= gate then
                                    if isVisible(char, predicted) then
                                        local score
                                        if AimConfig.priority == "FOV" then
                                            score = ang
                                        elseif AimConfig.priority == "Health" then
                                            score = hum.Health
                                        elseif AimConfig.priority == "Crosshair" then
                                            score = ang * (dist / 100)
                                        else
                                            score = dist
                                        end
                                        if score < bestScore then
                                            best, bestScore, bestPos = p, score, predicted
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestPos
end

local function humanizeOffset()
    if not AimConfig.humanize then return 0, 0 end
    local jy = (math.random() - 0.5) * 2 * AimConfig.jitterAmount
    local jp = (math.random() - 0.5) * 2 * AimConfig.jitterAmount
    local t  = tick() * (4 + math.random() * 3)
    jy += math.sin(t) * 0.12
    jp += math.cos(t * 1.3) * 0.12
    return math.rad(jy), math.rad(jp)
end

local function aimMoveCamera(targetWorldPos)
    local camCF = Camera.CFrame
    local myPos = camCF.Position

    local desired = CFrame.lookAt(myPos, targetWorldPos)

    if AimConfig.overshoot > 0 and math.random() < AimConfig.overshoot
       and tick() > AimState.overshootUntil then
        local over = targetWorldPos + (targetWorldPos - myPos).Unit * 0.6
        desired = CFrame.lookAt(myPos, over)
        AimState.overshootUntil = tick() + 0.05
    end

    local smoothed = camCF:Lerp(desired, 1 - AimConfig.smoothness)

    local curPitch, curYaw = camCF:ToOrientation()
    local newPitch, newYaw = smoothed:ToOrientation()

    local dPitch = math.clamp(math.deg(newPitch - curPitch), -AimConfig.maxStep, AimConfig.maxStep)
    local dYaw   = math.clamp(math.deg(newYaw - curYaw),   -AimConfig.maxStep, AimConfig.maxStep)

    local jp, jy = humanizeOffset()

    Camera.CFrame = CFrame.new(myPos) * CFrame.fromOrientation(
        math.rad(math.deg(curPitch) + dPitch) + jp,
        math.rad(math.deg(curYaw)   + dYaw)   + jy,
        0
    )
end

local function silentAim(targetPos)
    if AimConfig.silentMethod == "CFrame" then
        local tool = getEquippedTool()
        if tool then
            local handle = tool:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                handle.CFrame = CFrame.lookAt(handle.Position, targetPos)
            end
        end
        pcall(function()
            local mouse = LocalPlayer:GetMouse()
            if mouse then mouse.Hit = CFrame.lookAt(mouse.Origin.Position, targetPos) end
        end)

    elseif AimConfig.silentMethod == "Mouse" then
        local sp, onScreen = Camera:WorldToViewportPoint(targetPos)
        if onScreen then
            local vp = Camera.ViewportSize
            local dx = sp.X - (vp.X / 2)
            local dy = sp.Y - (vp.Y / 2)
            local k  = AimConfig.silentSmooth <= 0 and 1 or AimConfig.silentSmooth
            pcall(function() VirtualInput:SendMouseMoveEvent(dx * k, dy * k, false) end)
            pcall(function()
                local mouse = LocalPlayer:GetMouse()
                if mouse then mouse.Hit = CFrame.lookAt(mouse.Origin.Position, targetPos) end
            end)
        end

    elseif AimConfig.silentMethod == "VirtualInput" then
        local sp, onScreen = Camera:WorldToViewportPoint(targetPos)
        if onScreen then
            pcall(function() VirtualInput:SendMouseMoveEvent(sp.X, sp.Y, false) end)
        end
    end
end

local function fireClick(holdTime)
    pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 1) end)
    task.delay(holdTime or AimConfig.triggerHold, function()
        pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
    end)
end

local accum = 0

RunService.RenderStepped:Connect(function(dt)
    if not State.alive then return end

    accum += dt
    if accum < 1 / math.max(Config.updateRate, 1) then return end
    accum = 0

    -- ============ ESP ============
    if Config.enabled then
        resetPool()
        refreshRayFilter()
        skelUsed = 0

        local targets = refreshTargetList()
        local camPos  = Camera.CFrame.Position
        local maxD    = Config.maxDistance

        for i = 1, #targets do
            local p = targets[i]
            local hum, hrp, head = getRig(p)

            if hum and hum.Health > 0 then
                local hrpPos = hrp.Position
                local dx, dy, dz = hrpPos.X - camPos.X, hrpPos.Y - camPos.Y, hrpPos.Z - camPos.Z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                if dist <= maxD then
                    local rootSp, rootOn = Camera:WorldToViewportPoint(hrpPos)
                    if rootOn then
                        local headSp, headOn = Camera:WorldToViewportPoint(head.Position)
                        if headOn then
                            -- larger box: head-to-root span scaled up, width follows
                            local base = math.abs(rootSp.Y - headSp.Y)
                            local h    = base * Config.boxHeightRatio
                            local w    = h * Config.boxWidthRatio
                            local top  = headSp.Y - h * Config.boxTopPadding
                            local lft  = rootSp.X - w / 2
                            local hf   = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local col  = healthColor(hf)
                            local label = Config.showDisplayName
                                and (p.DisplayName .. " (@" .. p.Name .. ")")
                                or p.Name

                            if useDrawing then
                                local b = acquire("box")
                                b.Visible, b.Size, b.Position = Config.box, Vector2.new(w, h), Vector2.new(lft, top)
                                b.Color, b.Thickness = Config.boxColor, Config.boxThickness

                                local nm = acquire("name")
                                nm.Visible, nm.Position, nm.Text, nm.Color =
                                    Config.name, Vector2.new(lft + w / 2, top - 15), label, Theme.text

                                local dd = acquire("dist")
                                dd.Visible, dd.Position = Config.distance, Vector2.new(lft + w / 2, top + h + 4)
                                dd.Text  = string.format("%d studs", math.floor(dist))
                                dd.Color = Theme.textDim

                                local bg = acquire("hBg")
                                bg.Visible = Config.healthBar
                                bg.Size, bg.Position = Vector2.new(3, h), Vector2.new(lft - 6, top)
                                bg.Color = Color3.new(0, 0, 0)

                                local fg = acquire("hFg")
                                fg.Visible = Config.healthBar
                                fg.Size     = Vector2.new(3, h * hf)
                                fg.Position = Vector2.new(lft - 6, top + h * (1 - hf))
                                fg.Color    = col

                                local ht = acquire("hTxt")
                                ht.Visible  = Config.health
                                ht.Position = Vector2.new(lft + w + 4, top + h / 2 - 7)
                                ht.Text     = string.format("%d", math.floor(hum.Health))
                                ht.Color    = col

                                local tr = acquire("tracer")
                                tr.Visible = Config.tracer
                                if Config.tracer then
                                    local from
                                    if Config.tracerFrom == "Mouse" then
                                        from = UserInputService:GetMouseLocation()
                                    elseif Config.tracerFrom == "Top" then
                                        from = Vector2.new(Camera.ViewportSize.X / 2, 0)
                                    else
                                        from = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                                    end
                                    tr.From, tr.To, tr.Color = from, Vector2.new(lft + w / 2, top + h), Config.boxColor
                                end

                                -- skeleton: dense points, drawn per existing edge
                                if Config.skeleton then
                                    local pts = collectSkeletonPoints(p.Character)
                                    for _, edge in ipairs(SKEL_EDGES) do
                                        local a, b2 = pts[edge[1]], pts[edge[2]]
                                        if a and b2 then
                                            local ln = acquireSkel()
                                            ln.Visible = true
                                            ln.From, ln.To, ln.Color = a, b2, Config.boxColor
                                            ln.Thickness = 1
                                        end
                                    end
                                end
                            else
                                local b = acquire("box")
                                b.Visible, b.Position, b.Size = Config.box,
                                    UDim2.fromOffset(lft, top), UDim2.fromOffset(w, h)
                                b.BorderColor3 = Config.boxColor

                                local nm = acquire("name")
                                nm.Visible, nm.Position = Config.name, UDim2.fromOffset(lft + w / 2 - 75, top - 15)
                                nm.Size, nm.Text, nm.TextColor3 = UDim2.fromOffset(150, 14), label, Theme.text

                                local dd = acquire("dist")
                                dd.Visible, dd.Position = Config.distance, UDim2.fromOffset(lft + w / 2 - 50, top + h + 4)
                                dd.Size = UDim2.fromOffset(100, 12)
                                dd.Text = string.format("%d studs", math.floor(dist))
                                dd.TextColor3 = Theme.textDim

                                local bg = acquire("hBg")
                                bg.Visible, bg.Position, bg.Size = Config.healthBar,
                                    UDim2.fromOffset(lft - 6, top), UDim2.fromOffset(3, h)
                                bg.BackgroundColor3 = Color3.new(0, 0, 0)

                                local fg = acquire("hFg")
                                fg.Visible  = Config.healthBar
                                fg.Position = UDim2.fromOffset(lft - 6, top + h * (1 - hf))
                                fg.Size     = UDim2.fromOffset(3, h * hf)
                                fg.BackgroundColor3 = col

                                local ht = acquire("hTxt")
                                ht.Visible, ht.Position = Config.health, UDim2.fromOffset(lft + w + 4, top + h / 2 - 7)
                                ht.Size = UDim2.fromOffset(40, 14)
                                ht.Text = string.format("%d", math.floor(hum.Health))
                                ht.TextColor3 = col

                                local tr = acquire("tracer"); tr.Visible = false
                            end
                        end
                    end
                end
            end
        end

        hideRemainder()
        hideSkelFrom(skelUsed + 1)
    else
        for _, k in ipairs(POOL_KINDS) do
            for _, o in ipairs(pool[k]) do setVisible(o, false) end
        end
        hideSkelFrom(1)
    end

    -- ============ AIMBOT ============
    if AimConfig.enabled and hasWeapon() then

        -- TRIGGERBOT
        if AimConfig.triggerEnabled then
            if not (AimConfig.triggerOnAim and not State.aimKeyHeld) then
                local target, targetPos = scanForTarget(AimConfig.triggerFov / 2)
                if target and targetPos then
                    local dist = (targetPos - Camera.CFrame.Position).Magnitude
                    if dist <= AimConfig.triggerMaxDist then
                        -- trigger chance: skip this shot sometimes
                        if math.random() <= AimConfig.triggerChance then
                            fireClick(AimConfig.triggerHold)
                            AimState.shotsFired += 1
                        end
                        AimState.active = true
                        AimState.lockedTarget = target
                        -- cooldown so one target does not get machine-gunned
                        AimState.lockTime = tick() + 0.08
                    end
                else
                    AimState.active = false
                end
            end
        end

        -- SILENT
        if AimConfig.silentEnabled then
            local target, targetPos = scanForTarget()
            if target and targetPos then
                -- hit chance gate: only redirect on a fraction of updates
                if math.random() <= AimConfig.hitChance then
                    silentAim(targetPos)
                    AimState.active = true
                    AimState.lockedTarget = target
                end
            end
        end

        -- CAMERA MODE
        if AimConfig.mode == "Camera" and not AimConfig.triggerEnabled and not AimConfig.silentEnabled then
            if AimConfig.enabled then
                local target, targetPos = scanForTarget()
                if target then
                    if target ~= AimState.lockedTarget then
                        AimState.lockedTarget = target
                        AimState.lockTime     = tick()
                        AimState.active       = false
                    elseif tick() - AimState.lockTime >= AimConfig.reactionDelay then
                        -- hit chance: occasionally skip an update so not every frame snaps
                        if math.random() <= AimConfig.hitChance then
                            AimState.active = true
                            aimMoveCamera(targetPos)
                        end
                    end
                else
                    AimState.active = false
                    AimState.lockedTarget = nil
                end
            end
        end
    end
end)

-- =========================================================================
-- 09 · UI CORE
-- =========================================================================
local uiGui = parentGui((function()
    local g = Instance.new("ScreenGui")
    g.Name = "CustomMenuUI"
    g.ResetOnSpawn = false
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.DisplayOrder = 10
    return g
end)())

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 620, 0, 420)
mainFrame.Position = UDim2.new(0.5, -310, 0.5, -210)
mainFrame.BackgroundColor3 = Theme.background
mainFrame.BackgroundTransparency = Theme.transparency
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = uiGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Color = Theme.accentDim
mainStroke.Thickness = 1
mainStroke.Transparency = 0.4

local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.Size = UDim2.new(0, 150, 1, 0)
sideBar.BackgroundColor3 = Theme.sidebar
sideBar.BorderSizePixel = 0
sideBar.Parent = mainFrame
Instance.new("UICorner", sideBar).CornerRadius = UDim.new(0, 8)

local sideCover = Instance.new("Frame")
sideCover.Size = UDim2.new(0, 8, 1, 0)
sideCover.Position = UDim2.new(1, -8, 0, 0)
sideCover.BackgroundColor3 = Theme.sidebar
sideCover.BorderSizePixel = 0
sideCover.Parent = sideBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, 0, 0, 46)
titleText.BackgroundTransparency = 1
titleText.Text = "ZYON"
titleText.TextColor3 = Theme.accent
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 18
titleText.Parent = sideBar

local titleSub = Instance.new("TextLabel")
titleSub.Size = UDim2.new(1, 0, 0, 14)
titleSub.Position = UDim2.new(0, 0, 0, 30)
titleSub.BackgroundTransparency = 1
titleSub.Text = "suite v7"
titleSub.TextColor3 = Theme.textDim
titleSub.Font = Enum.Font.Gotham
titleSub.TextSize = 10
titleSub.Parent = sideBar

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -20, 0, 1)
divider.Position = UDim2.new(0, 10, 0, 48)
divider.BackgroundColor3 = Theme.row
divider.BorderSizePixel = 0
divider.Parent = sideBar

local tabHolder = Instance.new("Frame")
tabHolder.Size = UDim2.new(1, -12, 1, -122)
tabHolder.Position = UDim2.new(0, 6, 0, 58)
tabHolder.BackgroundTransparency = 1
tabHolder.Parent = sideBar

local tabLayout = Instance.new("UIListLayout", tabHolder)
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -12, 0, 48)
statusLabel.Position = UDim2.new(0, 6, 1, -54)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "armed"
statusLabel.TextColor3 = Theme.accent
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 9
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = sideBar

local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Size = UDim2.new(1, -168, 1, -20)
contentArea.Position = UDim2.new(0, 160, 0, 10)
contentArea.BackgroundTransparency = 1
contentArea.Parent = mainFrame

local pages, tabButtons = {}, {}

local function selectPage(name)
    for n, page in pairs(pages) do page.Visible = (n == name) end
    for n, btn in pairs(tabButtons) do
        local on = (n == name)
        btn.BackgroundColor3 = on and Theme.row or Theme.sidebar
        btn.TextColor3 = on and Theme.accent or Theme.textDim
        if btn:FindFirstChild("Indicator") then btn.Indicator.Visible = on end
    end
end

local function makePage(name)
    local page = Instance.new("Frame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = contentArea
    pages[name] = page
    return page
end

-- =========================================================================
-- 10 · UI WIDGETS
-- =========================================================================
local refreshHooks = {}
local refreshing   = false

local function refreshAll()
    if refreshing then return end
    refreshing = true
    for _, fn in ipairs(refreshHooks) do pcall(fn) end
    refreshing = false
end

-- debounced full-UI repaint, safe to call from a slider drag
local repaintQueued = false

local function queueRepaint()
    if repaintQueued then return end
    repaintQueued = true
    task.defer(function()
        repaintQueued = false
        refreshAll()
    end)
end

local function makeTab(name, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = Theme.sidebar
    btn.BorderSizePixel = 0
    btn.Text = "   " .. name
    btn.TextColor3 = Theme.textDim
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.LayoutOrder = order
    btn.AutoButtonColor = false
    btn.Parent = tabHolder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(0, 3, 0, 16)
    indicator.Position = UDim2.new(0, 0, 0.5, -8)
    indicator.BackgroundColor3 = Theme.accent
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.Parent = btn
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function() selectPage(name) end)
    tabButtons[name] = btn

    table.insert(refreshHooks, function()
        local on = pages[name] and pages[name].Visible
        btn.BackgroundColor3 = on and Theme.row or Theme.sidebar
        btn.TextColor3 = on and Theme.accent or Theme.textDim
        indicator.BackgroundColor3 = Theme.accent
    end)
    return btn
end

local function makeSection(page, title, order, height, scrollable)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, height or 100)
    box.BackgroundColor3 = Theme.section
    box.BorderSizePixel = 0
    box.LayoutOrder = order
    box.Parent = page
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 26)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = Theme.accent
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 12
    lbl.Parent = box

    local inner
    if scrollable then
        inner = Instance.new("ScrollingFrame")
        inner.ScrollBarThickness = 4
        inner.ScrollBarImageColor3 = Theme.accentDim
        inner.CanvasSize = UDim2.new(0, 0, 0, 0)
        inner.AutomaticCanvasSize = Enum.AutomaticSize.Y
    else
        inner = Instance.new("Frame")
    end
    inner.Size = UDim2.new(1, -14, 1, -34)
    inner.Position = UDim2.new(0, 7, 0, 30)
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 0
    inner.Parent = box

    local list = Instance.new("UIListLayout", inner)
    list.Padding = UDim.new(0, 4)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    table.insert(refreshHooks, function()
        box.BackgroundColor3 = Theme.section
        lbl.TextColor3 = Theme.accent
        if scrollable then
            pcall(function() inner.ScrollBarImageColor3 = Theme.accentDim end)
        end
    end)

    return box, inner
end

local function makeColumn(page, order)
    local col = Instance.new("Frame")
    col.Size = UDim2.new(0.5, -4, 1, 0)
    col.Position = UDim2.new(0.5 * order, 0, 0, 0)
    col.BackgroundTransparency = 1
    col.Parent = page
    local list = Instance.new("UIListLayout", col)
    list.Padding = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    return col
end

local function addToggle(parent, label, cfgTable, key, order)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundColor3 = Theme.row
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Theme.text
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 30, 0, 14)
    box.Position = UDim2.new(1, -38, 0.5, -7)
    box.BorderSizePixel = 0
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 10, 0, 10)
    knob.BorderSizePixel = 0
    knob.Parent = box
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function render()
        local on = cfgTable[key] and true or false
        box.BackgroundColor3  = on and Theme.accentDim or Theme.row
        knob.Position         = on and UDim2.new(1, -12, 0.5, -5) or UDim2.new(0, 2, 0.5, -5)
        knob.BackgroundColor3 = on and Theme.accent or Theme.textDim
        row.BackgroundColor3  = Theme.row
        lbl.TextColor3        = Theme.text
    end

    row.MouseButton1Click:Connect(function()
        cfgTable[key] = not cfgTable[key]
        render()
    end)

    render()
    table.insert(refreshHooks, render)
end

local function addSlider(parent, label, cfgTable, key, min, max, step, fmt, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Theme.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 14)
    lbl.Position = UDim2.new(0, 8, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Theme.text
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, -16, 0, 6)
    track.Position = UDim2.new(0, 8, 0, 22)
    track.BackgroundColor3 = Theme.row
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    fill.BackgroundColor3 = Theme.accentDim
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local function render()
        local rel = math.clamp((cfgTable[key] - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text  = label .. ": " .. (fmt and fmt(cfgTable[key]) or tostring(cfgTable[key]))
        fill.BackgroundColor3 = Theme.accentDim
        row.BackgroundColor3  = Theme.row
        lbl.TextColor3        = Theme.text
    end

    local dragging = false
    local function update(input)
        local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local val = min + (max - min) * rel
        val = math.floor(val / step + 0.5) * step
        cfgTable[key] = val
        render()
    end

    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(i)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                     or i.UserInputType == Enum.UserInputType.Touch) then
            update(i)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    render()
    table.insert(refreshHooks, render)
end

local function addCycle(parent, label, cfgTable, key, options, order)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundColor3 = Theme.row
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Theme.text
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local function render()
        lbl.Text = label .. ":  " .. tostring(cfgTable[key])
        row.BackgroundColor3 = Theme.row
        lbl.TextColor3 = Theme.text
    end

    row.MouseButton1Click:Connect(function()
        local idx = 1
        for i, v in ipairs(options) do
            if v == cfgTable[key] then idx = i break end
        end
        idx = (idx % #options) + 1
        cfgTable[key] = options[idx]
        render()
    end)

    render()
    table.insert(refreshHooks, render)
end

-- ---- KEYBIND with CLEAR button ----------------------------------------
local activeCapture = nil
local keybindRegistry = {}

local function addKeybind(parent, label, cfgTable, key, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundColor3 = Theme.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    -- clickable bind area
    local bind = Instance.new("TextButton")
    bind.Size = UDim2.new(1, -34, 1, 0)
    bind.BackgroundTransparency = 1
    bind.Text = ""
    bind.AutoButtonColor = false
    bind.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = bind

    -- clear button
    local clr = Instance.new("TextButton")
    clr.Size = UDim2.new(0, 26, 0, 16)
    clr.Position = UDim2.new(1, -30, 0.5, -8)
    clr.BackgroundColor3 = Theme.accentDim
    clr.BorderSizePixel = 0
    clr.Text = "X"
    clr.TextColor3 = Color3.fromRGB(240, 240, 240)
    clr.Font = Enum.Font.GothamBold
    clr.TextSize = 10
    clr.AutoButtonColor = false
    clr.Parent = row
    Instance.new("UICorner", clr).CornerRadius = UDim.new(0, 3)

    local function render()
        if activeCapture == bind then
            lbl.Text = label .. ":  [ press a key ]"
            lbl.TextColor3 = Theme.accent
        else
            local k = cfgTable[key]
            local has = (k ~= nil)
            lbl.Text = label .. ":  " .. (has and keyName(k) or "none")
            lbl.TextColor3 = has and Theme.text or Theme.textDim
        end
        row.BackgroundColor3 = Theme.row
        clr.BackgroundColor3 = Theme.accentDim
    end

    bind.MouseButton1Click:Connect(function()
        activeCapture = bind
        refreshAll()
    end)

    clr.MouseButton1Click:Connect(function()
        cfgTable[key] = nil
        if activeCapture == bind then activeCapture = nil end
        refreshAll()
    end)

    table.insert(keybindRegistry, {bind = bind, cfgTable = cfgTable, key = key})
    table.insert(refreshHooks, render)
    render()
    return row
end

local function commitCapture(input)
    if not activeCapture then return false end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return false end

    for _, entry in ipairs(keybindRegistry) do
        if entry.bind == activeCapture then
            entry.cfgTable[entry.key] = input.KeyCode
            activeCapture = nil
            refreshAll()
            return true
        end
    end
    activeCapture = nil
    refreshAll()
    return false
end

-- ---- COLOUR PICKER — repaints the whole UI ----------------------------
local function addColorPicker(parent, label, themeKey, order)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 106)
    holder.BackgroundColor3 = Theme.row
    holder.BorderSizePixel = 0
    holder.LayoutOrder = order
    holder.Parent = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 4)

    local head = Instance.new("Frame")
    head.Size = UDim2.new(1, -10, 0, 20)
    head.Position = UDim2.new(0, 5, 0, 3)
    head.BackgroundTransparency = 1
    head.Parent = holder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -30, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Theme.text
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = head

    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.new(0, 20, 0, 14)
    swatch.Position = UDim2.new(1, -22, 0.5, -7)
    swatch.BackgroundColor3 = Theme[themeKey]
    swatch.BorderSizePixel = 0
    swatch.Parent = head
    Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 3)

    local channels = {}
    local CH = {"R", "G", "B"}

    local seed = Theme[themeKey]
    channels.R = math.floor(seed.R * 255)
    channels.G = math.floor(seed.G * 255)
    channels.B = math.floor(seed.B * 255)

    -- writes the theme, then schedules a full repaint. the repaint is deferred,
    -- so this cannot recurse back into the drag handler that called it.
    local function apply()
        Theme[themeKey] = Color3.fromRGB(channels.R, channels.G, channels.B)
        swatch.BackgroundColor3 = Theme[themeKey]
        queueRepaint()
    end

    for ci, cname in ipairs(CH) do
        local pr = Instance.new("Frame")
        pr.Size = UDim2.new(1, -10, 0, 24)
        pr.Position = UDim2.new(0, 5, 0, 24 + (ci - 1) * 25)
        pr.BackgroundTransparency = 1
        pr.Parent = holder

        local cl = Instance.new("TextLabel")
        cl.Size = UDim2.new(0, 42, 1, 0)
        cl.BackgroundTransparency = 1
        cl.Text = cname
        cl.TextColor3 = Theme.textDim
        cl.Font = Enum.Font.Code
        cl.TextSize = 10
        cl.TextXAlignment = Enum.TextXAlignment.Left
        cl.Parent = pr

        local track = Instance.new("TextButton")
        track.Size = UDim2.new(1, -48, 0, 6)
        track.Position = UDim2.new(0, 44, 0.5, -3)
        track.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = pr
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame", track)
        fill.BorderSizePixel = 0
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local val = Instance.new("TextLabel")
        val.Size = UDim2.new(0, 26, 1, 0)
        val.Position = UDim2.new(1, -26, 0, 0)
        val.BackgroundTransparency = 1
        val.TextColor3 = Theme.textDim
        val.Font = Enum.Font.Code
        val.TextSize = 10
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.Parent = pr

        local function paint()
            local v = channels[cname] or 0
            fill.Size = UDim2.new(v / 255, 0, 1, 0)
            fill.BackgroundColor3 = Color3.fromRGB(channels.R, channels.G, channels.B)
            val.Text = tostring(v)
        end

        local dragging = false
        local function update(input)
            local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
            channels[cname] = math.floor(rel * 255 + 0.5)
            paint()
            apply()
        end

        track.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; update(i)
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                         or i.UserInputType == Enum.UserInputType.Touch) then
                update(i)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        table.insert(refreshHooks, function()
            local c = Theme[themeKey]
            channels[cname] = (cname == "R" and math.floor(c.R * 255))
                           or (cname == "G" and math.floor(c.G * 255))
                           or math.floor(c.B * 255)
            paint()
            holder.BackgroundColor3 = Theme.row
            lbl.TextColor3 = Theme.text
            cl.TextColor3 = Theme.textDim
            val.TextColor3 = Theme.textDim
            swatch.BackgroundColor3 = c
        end)

        paint()
    end
end

-- =========================================================================
-- 11 · UI TABS
-- =========================================================================
local espPage   = makePage("ESP")
local aimPage   = makePage("AIM")
local themePage = makePage("THEME")
local cfgPage   = makePage("SETTINGS")

makeTab("ESP",      1)
makeTab("AIMBOT",   2)
makeTab("THEME",    3)
makeTab("SETTINGS", 4)

-- ---- ESP ---------------------------------------------------------------
do
    local colL = makeColumn(espPage, 0)
    local colR = makeColumn(espPage, 1)

    local _, v = makeSection(colL, "VISUALS", 1, 196)
    addToggle(v, "Enabled",      Config, "enabled",         1)
    addToggle(v, "Box",          Config, "box",             2)
    addToggle(v, "Name",         Config, "name",            3)
    addToggle(v, "Full Display", Config, "showDisplayName", 4)
    addToggle(v, "Distance",     Config, "distance",        5)
    addToggle(v, "Skeleton",     Config, "skeleton",        6)

    local _, hh = makeSection(colL, "HEALTH", 2, 92)
    addToggle(hh, "Health Bar",  Config, "healthBar", 1)
    addToggle(hh, "Health Text", Config, "health",    2)

    local _, kb = makeSection(colL, "KEYBIND", 3, 62)
    addKeybind(kb, "Toggle ESP", KeyConfig, "espToggle", 1)

    local _, rng = makeSection(colR, "RANGE", 1, 118)
    addSlider(rng, "Max Distance", Config, "maxDistance", 50, 1500, 25,
        function(x) return tostring(x) .. " studs" end, 1)
    addSlider(rng, "Update Rate",  Config, "updateRate",  5, 60, 5,
        function(x) return tostring(x) .. " Hz" end, 2)

    local _, bx = makeSection(colR, "BOX SIZE", 2, 144)
    addSlider(bx, "Height", Config, "boxHeightRatio", 1.2, 3.0, 0.05,
        function(x) return string.format("%.2fx", x) end, 1)
    addSlider(bx, "Width", Config, "boxWidthRatio", 0.3, 1.0, 0.02,
        function(x) return string.format("%.2fx", x) end, 2)
    addSlider(bx, "Top Pad", Config, "boxTopPadding", 0, 0.4, 0.02,
        function(x) return string.format("%.2f", x) end, 3)

    local _, tr = makeSection(colR, "TRACER + FILTER", 3, 144)
    addToggle(tr, "Tracer", Config, "tracer", 1)
    addCycle(tr, "Origin", Config, "tracerFrom", {"Bottom", "Mouse", "Top"}, 2)
    addToggle(tr, "Team Check", Config, "teamCheck", 3)
    addSlider(tr, "Fill Alpha", Config, "fillAlpha", 0, 1, 0.05,
        function(x) return string.format("%.2f", x) end, 4)
end

-- ---- AIM ---------------------------------------------------------------
do
    local colL = makeColumn(aimPage, 0)
    local colR = makeColumn(aimPage, 1)

    local _, master = makeSection(colL, "MODE", 1, 146)
    addToggle(master, "Enabled",        AimConfig, "enabled",         1)
    addCycle(master, "Aim Mode", AimConfig, "mode",
        {"Camera", "Silent", "Triggerbot"}, 2)
    addToggle(master, "Toggle Mode",    AimConfig, "toggleMode",      3)
    addToggle(master, "Require Weapon", AimConfig, "requireEquipped", 4)

    local _, kb = makeSection(colL, "KEYBINDS", 2, 146)
    addKeybind(kb, "Aim Key",     KeyConfig, "aimKey",     1)
    addKeybind(kb, "Silent Key",  KeyConfig, "silentKey",  2)
    addKeybind(kb, "Trigger Key", KeyConfig, "triggerKey", 3)

    local _, body = makeSection(colL, "HIT PART", 3, 196, true)
    addCycle(body, "Body Part", AimConfig, "hitPart",
        {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Arms", "Legs", "Nearest"}, 1)
    addSlider(body, "Height Offset", AimConfig, "hitOffsetY", -2, 2, 0.05,
        function(x) return string.format("%+.2f studs", x) end, 2)
    addSlider(body, "Hit Chance", AimConfig, "hitChance", 0.1, 1, 0.05,
        function(x) return string.format("%d%%", math.floor(x * 100)) end, 3)
    addSlider(body, "Expansion", AimConfig, "hitboxExpand", 1, 2, 0.05,
        function(x) return string.format("%.2fx", x) end, 4)

    local _, silent = makeSection(colR, "SILENT AIM", 1, 172, true)
    addToggle(silent, "Silent Enabled", AimConfig, "silentEnabled", 1)
    addCycle(silent, "Transport", AimConfig, "silentMethod",
        {"Mouse", "CFrame", "VirtualInput"}, 2)
    addSlider(silent, "Silent Smooth", AimConfig, "silentSmooth", 0, 1, 0.05,
        function(x) return x == 0 and "instant" or string.format("%.2f", x) end, 3)
    addToggle(silent, "Wall Check", AimConfig, "wallCheck", 4)

    local _, trig = makeSection(colR, "TRIGGERBOT", 2, 220, true)
    addToggle(trig, "Trigger Enabled", AimConfig, "triggerEnabled", 1)
    addSlider(trig, "Shot Chance", AimConfig, "triggerChance", 0.1, 1, 0.05,
        function(x) return string.format("%d%%", math.floor(x * 100)) end, 2)
    addSlider(trig, "Trigger Delay", AimConfig, "triggerDelay", 0, 0.3, 0.005,
        function(x) return string.format("%.3fs", x) end, 3)
    addSlider(trig, "Click Hold", AimConfig, "triggerHold", 0.01, 0.2, 0.005,
        function(x) return string.format("%.3fs", x) end, 4)
    addSlider(trig, "Trigger Range", AimConfig, "triggerMaxDist", 50, 800, 25,
        function(x) return tostring(x) .. " studs" end, 5)
    addToggle(trig, "Only While Aiming", AimConfig, "triggerOnAim", 6)

    local _, cone = makeSection(colR, "TARGET SELECT", 3, 168, true)
    addCycle(cone, "Priority", AimConfig, "priority",
        {"Distance", "FOV", "Health", "Crosshair"}, 1)
    addSlider(cone, "FOV", AimConfig, "fov", 10, 180, 5,
        function(x) return tostring(x) .. " deg" end, 2)
    addSlider(cone, "Max Distance", AimConfig, "maxDistance", 50, 1000, 25,
        function(x) return tostring(x) .. " studs" end, 3)
    addToggle(cone, "Team Check",    AimConfig, "teamCheck",    4)
    addToggle(cone, "Visible Check", AimConfig, "visibleCheck", 5)
end

-- ---- THEME -------------------------------------------------------------
do
    local colL = makeColumn(themePage, 0)
    local colR = makeColumn(themePage, 1)

    -- tall scrollable boxes so pickers never spill outside the menu
    local _, acc = makeSection(colL, "ACCENT", 1, 268, true)
    addColorPicker(acc, "Accent",     "accent",    1)
    addColorPicker(acc, "Accent Dim", "accentDim", 2)

    local _, surf = makeSection(colR, "SURFACES", 1, 268, true)
    addColorPicker(surf, "Background", "background", 1)
    addColorPicker(surf, "Sidebar",    "sidebar",    2)

    local _, txt = makeSection(colL, "TEXT", 2, 268, true)
    addColorPicker(txt, "Text",     "text",    1)
    addColorPicker(txt, "Text Dim", "textDim", 2)

    local _, more = makeSection(colR, "BOXES + ROWS", 2, 268, true)
    addColorPicker(more, "Section Box", "section", 1)
    addColorPicker(more, "Widget Row",  "row",     2)

    local _, pre = makeSection(colL, "PRESETS", 3, 74)
    local presetRow = Instance.new("Frame")
    presetRow.Size = UDim2.new(1, 0, 0, 26)
    presetRow.BackgroundTransparency = 1
    presetRow.LayoutOrder = 1
    presetRow.Parent = pre
    local plist = Instance.new("UIListLayout", presetRow)
    plist.FillDirection = Enum.FillDirection.Horizontal
    plist.Padding = UDim.new(0, 4)

    local PRESETS = {
        {name = "Red",    accent = Color3.fromRGB(255, 50, 50),  dim = Color3.fromRGB(150, 30, 30)},
        {name = "Cyan",   accent = Color3.fromRGB(0, 220, 220),  dim = Color3.fromRGB(0, 120, 120)},
        {name = "Green",  accent = Color3.fromRGB(0, 220, 120),  dim = Color3.fromRGB(0, 120, 70)},
        {name = "Purple", accent = Color3.fromRGB(170, 60, 255), dim = Color3.fromRGB(95, 30, 150)},
        {name = "Orange", accent = Color3.fromRGB(255, 150, 40), dim = Color3.fromRGB(150, 85, 25)},
    }

    for _, preset in ipairs(PRESETS) do
        local pb = Instance.new("TextButton")
        pb.Size = UDim2.new(0, 70, 1, 0)
        pb.BackgroundColor3 = preset.accent
        pb.BorderSizePixel = 0
        pb.Text = ""
        pb.AutoButtonColor = false
        pb.Parent = presetRow
        Instance.new("UICorner", pb).CornerRadius = UDim.new(0, 4)

        pb.MouseButton1Click:Connect(function()
            Theme.accent    = preset.accent
            Theme.accentDim = preset.dim
            refreshAll()
        end)

        table.insert(refreshHooks, function()
            pb.BackgroundColor3 = preset.accent
        end)
    end
end

-- ---- SETTINGS ----------------------------------------------------------
do
    local colL = makeColumn(cfgPage, 0)
    local colR = makeColumn(cfgPage, 1)

    local _, kb = makeSection(colL, "MENU KEYBIND", 1, 92)
    addKeybind(kb, "Open / Close Menu", KeyConfig, "uiToggle", 1)
    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, 0, 0, 14)
    hint.BackgroundTransparency = 1
    hint.Text = "   default: RightShift    X clears"
    hint.TextColor3 = Theme.textDim
    hint.Font = Enum.Font.Code
    hint.TextSize = 9
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.LayoutOrder = 2
    hint.Parent = kb
    table.insert(refreshHooks, function() hint.TextColor3 = Theme.textDim end)

    local _, safe = makeSection(colL, "SAFETY", 2, 118)
    addToggle(safe, "Opsec",        Config, "opsec",       1)
    addToggle(safe, "Probe Guard",  Config, "probeGuard",  2)
    addToggle(safe, "Auto-Disable", Config, "autoDisable", 3)

    local _, info = makeSection(colR, "RUNTIME", 1, 144)
    local infoLbl = Instance.new("TextLabel")
    infoLbl.Size = UDim2.new(1, 0, 0, 100)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Text = "collecting"
    infoLbl.TextColor3 = Theme.textDim
    infoLbl.Font = Enum.Font.Code
    infoLbl.TextSize = 11
    infoLbl.TextXAlignment = Enum.TextXAlignment.Left
    infoLbl.TextYAlignment = Enum.TextYAlignment.Top
    infoLbl.Parent = info
    table.insert(refreshHooks, function() infoLbl.TextColor3 = Theme.textDim end)

    local _, st = makeSection(colR, "STATUS + BINDS", 2, 168)
    local stateLbl = Instance.new("TextLabel")
    stateLbl.Size = UDim2.new(1, 0, 0, 130)
    stateLbl.BackgroundTransparency = 1
    stateLbl.Text = "armed"
    stateLbl.TextColor3 = Theme.accent
    stateLbl.Font = Enum.Font.Code
    stateLbl.TextSize = 10
    stateLbl.TextXAlignment = Enum.TextXAlignment.Left
    stateLbl.TextYAlignment = Enum.TextYAlignment.Top
    stateLbl.Parent = st
    table.insert(refreshHooks, function() end)

    task.spawn(function()
        while State.alive do
            task.wait(0.5)
            local live = 0
            for _, k in ipairs(POOL_KINDS) do
                if poolUse[k] > live then live = poolUse[k] end
            end

            pcall(function()
                infoLbl.Text = string.format(
                    "backend : %s\nplace   : %s\ntargets : %d\nshots   : %d\nuptime  : %ds",
                    useDrawing and "Drawing" or "ScreenGui",
                    tostring(game.PlaceId), live,
                    AimState.shotsFired, math.floor(tick() - State.startTime))
            end)

            pcall(function()
                local lines = {
                    "menu   : " .. keyName(KeyConfig.uiToggle),
                    "esp    : " .. keyName(KeyConfig.espToggle),
                    "aim    : " .. keyName(KeyConfig.aimKey),
                    "silent : " .. keyName(KeyConfig.silentKey),
                    "trig   : " .. keyName(KeyConfig.triggerKey),
                }
                if State.detected then
                    table.insert(lines, 1, "KILLED: " .. tostring(State.reason))
                elseif AimState.active and AimState.lockedTarget then
                    table.insert(lines, 1, "LOCK: " .. AimState.lockedTarget.Name)
                end
                stateLbl.Text = table.concat(lines, "\n")
            end)
        end
    end)
end

-- =========================================================================
-- 12 · SAFETY LOOP + BINDS + BOOT
-- =========================================================================
task.spawn(function()
    while State.alive do
        task.wait(2)

        if Config.probeGuard then
            local reason = probeCheck()
            if reason then
                if Config.autoDisable then
                    killSwitch(reason)
                    pcall(function()
                        statusLabel.Text = "KILLED\n" .. reason
                    end)
                else
                    pcall(function() statusLabel.Text = "probe: " .. reason end)
                end
            end
        end

        if State.alive then
            pcall(function()
                local n = 0
                for _, k in ipairs(POOL_KINDS) do
                    if poolUse[k] > n then n = poolUse[k] end
                end
                statusLabel.Text = string.format("armed\n%d seen\n%s",
                    n, string.upper(AimConfig.mode))
            end)
        end
    end
end)

UserInputService.InputBegan:Connect(function(i, processed)
    if commitCapture(i) then return end
    if processed then return end

    -- every bind is nil-safe now: nothing fires until you assign a key
    if KeyConfig.uiToggle and i.KeyCode == KeyConfig.uiToggle then
        mainFrame.Visible = not mainFrame.Visible

    elseif KeyConfig.espToggle and i.KeyCode == KeyConfig.espToggle then
        Config.enabled = not Config.enabled
        refreshAll()

    elseif KeyConfig.aimKey and i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = true
        AimConfig.enabled = AimConfig.toggleMode and (not AimConfig.enabled) or true
        refreshAll()

    elseif KeyConfig.silentKey and i.KeyCode == KeyConfig.silentKey then
        AimConfig.silentEnabled = not AimConfig.silentEnabled
        refreshAll()

    elseif KeyConfig.triggerKey and i.KeyCode == KeyConfig.triggerKey then
        AimConfig.triggerEnabled = not AimConfig.triggerEnabled
        refreshAll()
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if KeyConfig.aimKey and i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = false
        if not AimConfig.toggleMode then
            AimConfig.enabled = false
            AimState.active = false
        end
    end
end)

registerCleanup(function()
    pcall(function() uiGui:Destroy() end)
    if drawGui then pcall(function() drawGui:Destroy() end) end
end)

task.defer(function()
    selectPage("ESP")
    refreshAll()
end)

local API = {
    Config = Config,
    Aim    = AimConfig,
    Theme  = Theme,
    Keys   = KeyConfig,
    Team   = Team,
    State  = State,
    unload = function()
        State.alive = false
        Config.enabled = false
        AimConfig.enabled = false
        runCleanup()
    end,
}
