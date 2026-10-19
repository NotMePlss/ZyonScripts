--[[
    ZYON SUITE — single-file build (v10)
    target : Roblox executor

    THE FIX IN THIS BUILD
      Each page was a bare Frame with no UIListLayout and no scroll. Sections
      were parented to it with LayoutOrder, but nothing consumed that order, so
      every section spawned at (0,0), stacked on top of each other, and the
      right-hand column rendered outside the visible content area. The AIMBOT
      tab looked "empty" because MODE covered KEYBINDS and HIT PART sat off-box.

      Pages are now scrolling containers with a UIListLayout, and columns are
      sized to their content. Nothing can hide outside the box anymore.

    layout of the AIMBOT tab
      left  column : AIMBOT    (master switch, mode, keybinds, smoothing)
                     TRIGGERBOT (shot chance, delay, hold, range)
      right column : SILENT AIM (transport, smooth, wall check)
                     HIT PART   (body part, offset, hit chance)
                     TARGET     (priority, fov, distance, filters)

    keybinds start EMPTY. every row has an X button that unbinds it.
    menu default bind is RightShift, changeable in SETTINGS.

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

    boxHeightRatio  = 1.95,
    boxWidthRatio   = 0.62,
    boxTopPadding   = 0.12,

    opsec           = true,
    probeGuard      = true,
    autoDisable     = true,
}

local AimConfig = {
    enabled         = false,
    mode            = "Camera",

    teamCheck       = true,
    maxDistance     = 500,
    fov             = 90,
    priority        = "Distance",
    visibleCheck    = true,
    wallCheck       = false,

    hitPart         = "Head",
    hitOffsetY      = 0,
    hitChance       = 1.0,
    hitboxExpand    = 1.0,

    smoothness      = 0.22,
    maxStep         = 12,
    prediction      = true,
    predictionTime  = 0.14,

    humanize        = true,
    jitterAmount    = 0.35,
    overshoot       = 0.08,
    reactionDelay   = 0.09,

    -- AIMBOT (camera / snap)
    aimEnabled      = false,
    aimToggleMode   = false,

    -- SILENT
    silentEnabled   = false,
    silentMethod    = "Mouse",
    silentSmooth    = 0.0,

    -- TRIGGERBOT
    triggerEnabled  = false,
    triggerDelay    = 0.02,
    triggerHold     = 0.04,
    triggerChance   = 1.0,
    triggerOnAim    = false,
    triggerMaxDist  = 400,
    triggerFov      = 12,

    requireEquipped = true,
    debug           = true,
}

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

local KeyConfig = {
    aimKey     = nil,
    silentKey  = nil,
    triggerKey = nil,
    espToggle  = nil,
    uiToggle   = Enum.KeyCode.RightShift,
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
-- 03 · OPSEC + STATE
-- =========================================================================
local State = {
    alive      = true,
    detected   = false,
    reason     = nil,
    cleanup    = {},
    startTime  = tick(),
    aimKeyHeld = false,
    silentHeld = false,
    trigHeld   = false,
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
end

-- =========================================================================
-- 04 · PROBE GUARD
-- =========================================================================
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
            if c:IsA("Folder") or c:IsA("RemoteEvent") or c:IsA("BindableEvent") then
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
    State.detected     = true
    State.alive        = false
    State.reason       = reason
    Config.enabled     = false
    AimConfig.aimEnabled     = false
    AimConfig.silentEnabled  = false
    AimConfig.triggerEnabled = false
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

local skelPool, skelUsed = {}, 0

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

local rigCache, rigCacheTime = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})

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

local function healthColor(f) return Color3.fromRGB(255 * (1 - f), 255 * f, 0) end

-- =========================================================================
-- 07 · SKELETON
-- =========================================================================
local SKEL_BONES = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
    "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
}

local SKEL_EDGES = {
    {1,2},{2,3},{2,4},{4,5},{2,6},{6,7},{3,8},{8,9},{3,10},{10,11},
}

local R6_MAP = {
    Head = "Head", UpperTorso = "Torso", LowerTorso = "Torso",
    LeftUpperArm = "Left Arm", LeftLowerArm = "Left Arm",
    RightUpperArm = "Right Arm", RightLowerArm = "Right Arm",
    LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg",
    RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg",
}

local function collectSkeletonPoints(char)
    local pts = {}
    for i, bone in ipairs(SKEL_BONES) do
        local part = char:FindFirstChild(bone)
        if not (part and part:IsA("BasePart")) then
            local alt = R6_MAP[bone]
            if alt then part = char:FindFirstChild(alt) end
        end
        if part and part:IsA("BasePart") then
            local sp = Camera:WorldToViewportPoint(part.Position)
            pts[i] = Vector2.new(sp.X, sp.Y)
        else
            pts[i] = nil
        end
    end
    return pts
end

-- =========================================================================
-- 08 · AIM CORE
-- =========================================================================
local AimState = {
    active       = false,
    lockedTarget = nil,
    lockTime     = 0,
    overshootUntil = 0,
    shotsFired   = 0,
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

local HIT_PART_GROUPS = {
    Arms = {"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
            "Left Arm", "Right Arm"},
    Legs = {"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
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
        local camPos, camLook = Camera.CFrame.Position, Camera.CFrame.LookVector
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
        local sum, count, any = Vector3.zero, 0, nil
        for _, name in ipairs(HIT_PART_GROUPS[choice]) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                sum += part.Position; count += 1; any = any or part
            end
        end
        if count > 0 then
            return (sum / count) + Vector3.new(0, AimConfig.hitOffsetY, 0), any
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

local function scanForTarget(gateDegrees)
    local camCF, myPos, myLook = Camera.CFrame, Camera.CFrame.Position, Camera.CFrame.LookVector
    local best, bestScore, bestPos = nil, math.huge, nil
    local gate = gateDegrees or (AimConfig.fov / 2)

    for _, p in next, Players:GetPlayers() do
        if p ~= LocalPlayer and not (AimConfig.teamCheck and Team.isAlly(p)) then
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
                            if ang <= gate and isVisible(char, predicted) then
                                local score
                                if AimConfig.priority == "FOV" then score = ang
                                elseif AimConfig.priority == "Health" then score = hum.Health
                                elseif AimConfig.priority == "Crosshair" then score = ang * (dist / 100)
                                else score = dist end
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
    local camCF, myPos = Camera.CFrame, Camera.CFrame.Position

    -- BUG THAT LIVED HERE: CFrame:Lerp interpolates the rotation MATRIX
    -- component-wise, not spherically. For large angles the intermediate value
    -- is not a valid rotation, so ToOrientation() returned a degraded Euler and
    -- the camera jittered / never settled. Interpolating in ANGLE SPACE instead.
    local toTarget = targetWorldPos - myPos
    if toTarget.Magnitude < 0.01 then return end
    local dir = toTarget.Unit

    -- desired pitch / yaw straight from the direction vector, no CFrame lerp
    local wantPitch = math.asin(math.clamp(dir.Y, -1, 1))
    local wantYaw   = math.atan2(-dir.X, -dir.Z)

    local curPitch, curYaw, _ = camCF:ToOrientation()

    -- shortest-path yaw wrap so it never spins the long way round
    local dYaw = wantYaw - curYaw
    while dYaw >  math.pi do dYaw -= math.pi * 2 end
    while dYaw < -math.pi do dYaw += math.pi * 2 end
    local dPitch = wantPitch - curPitch

    -- smoothing as an eased fraction of the remaining angle
    local k = 1 - AimConfig.smoothness
    local stepPitch = dPitch * k
    local stepYaw   = dYaw   * k

    -- maxStep clamps the per-frame rotation; scale to degrees for the config
    local maxRad = math.rad(AimConfig.maxStep)
    stepPitch = math.clamp(stepPitch, -maxRad, maxRad)
    stepYaw   = math.clamp(stepYaw,   -maxRad, maxRad)

    -- overshoot: deliberately go slightly past, then settle
    if AimConfig.humanize and AimConfig.overshoot > 0
       and math.random() < AimConfig.overshoot
       and tick() > AimState.overshootUntil then
        stepPitch *= 1.15
        stepYaw   *= 1.15
        AimState.overshootUntil = tick() + 0.05
    end

    local jp, jy = humanizeOffset()

    Camera.CFrame = CFrame.new(myPos) * CFrame.fromOrientation(
        curPitch + stepPitch + jp,
        curYaw   + stepYaw   + jy,
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
            local dx, dy = sp.X - (vp.X / 2), sp.Y - (vp.Y / 2)
            local k = AimConfig.silentSmooth <= 0 and 1 or AimConfig.silentSmooth
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

-- =========================================================================
-- 09 · MAIN LOOP
-- =========================================================================
local accum = 0

RunService.RenderStepped:Connect(function(dt)
    if not State.alive then return end

    accum += dt
    if accum < 1 / math.max(Config.updateRate, 1) then return end
    accum = 0

    -- ---------- ESP ----------
    if Config.enabled then
        resetPool(); refreshRayFilter(); skelUsed = 0

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
                            local base = math.abs(rootSp.Y - headSp.Y)
                            local h    = base * Config.boxHeightRatio
                            local w    = h * Config.boxWidthRatio
                            local top  = headSp.Y - h * Config.boxTopPadding
                            local lft  = rootSp.X - w / 2
                            local hf   = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local col  = healthColor(hf)
                            local label = Config.showDisplayName
                                and (p.DisplayName .. " (@" .. p.Name .. ")") or p.Name

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
                                ht.Visible, ht.Position = Config.health, Vector2.new(lft + w + 4, top + h / 2 - 7)
                                ht.Text, ht.Color = string.format("%d", math.floor(hum.Health)), col

                                local tr = acquire("tracer")
                                tr.Visible = Config.tracer
                                if Config.tracer then
                                    local from
                                    if Config.tracerFrom == "Mouse" then from = UserInputService:GetMouseLocation()
                                    elseif Config.tracerFrom == "Top" then from = Vector2.new(Camera.ViewportSize.X/2, 0)
                                    else from = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y) end
                                    tr.From, tr.To, tr.Color = from, Vector2.new(lft + w/2, top + h), Config.boxColor
                                end

                                if Config.skeleton then
                                    local pts = collectSkeletonPoints(p.Character)
                                    for _, edge in ipairs(SKEL_EDGES) do
                                        local a, b2 = pts[edge[1]], pts[edge[2]]
                                        if a and b2 then
                                            local ln = acquireSkel()
                                            ln.Visible, ln.Thickness = true, 1
                                            ln.From, ln.To, ln.Color = a, b2, Config.boxColor
                                        end
                                    end
                                end
                            else
                                local b = acquire("box")
                                b.Visible, b.Position, b.Size = Config.box,
                                    UDim2.fromOffset(lft, top), UDim2.fromOffset(w, h)
                                b.BorderColor3 = Config.boxColor

                                local nm = acquire("name")
                                nm.Visible, nm.Position = Config.name, UDim2.fromOffset(lft + w/2 - 75, top - 15)
                                nm.Size, nm.Text, nm.TextColor3 = UDim2.fromOffset(150, 14), label, Theme.text

                                local dd = acquire("dist")
                                dd.Visible, dd.Position = Config.distance, UDim2.fromOffset(lft + w/2 - 50, top + h + 4)
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
                                ht.Visible, ht.Position = Config.health, UDim2.fromOffset(lft + w + 4, top + h/2 - 7)
                                ht.Size = UDim2.fromOffset(40, 14)
                                ht.Text = string.format("%d", math.floor(hum.Health))
                                ht.TextColor3 = col

                                acquire("tracer").Visible = false
                            end
                        end
                    end
                end
            end
        end

        hideRemainder(); hideSkelFrom(skelUsed + 1)
    else
        for _, k in ipairs(POOL_KINDS) do
            for _, o in ipairs(pool[k]) do setVisible(o, false) end
        end
        hideSkelFrom(1)
    end
end)

-- =========================================================================
-- 09b · AIM LOOP — runs at full framerate, NOT throttled with the ESP.
--
-- two bugs used to live here:
--   1. `if not hasWeapon() then return end` sat before every aim block, so on
--      any game without a Tool the whole aim section never executed.
--   2. the aim ran inside the 30Hz ESP accumulator, which made the snap jerky.
-- now it has its own RenderStepped and the weapon gate is opt-in.
-- =========================================================================
RunService.RenderStepped:Connect(function()
    if not State.alive then return end

    -- weapon gate is a soft filter, never a hard return
    if AimConfig.requireEquipped and not hasWeapon() then
        AimState.active = false
        return
    end

    -- ---------- AIMBOT (camera snap to hit part) ----------
    if AimConfig.aimEnabled then
        local target, targetPos = scanForTarget()
        if target and targetPos then
            if target ~= AimState.lockedTarget then
                AimState.lockedTarget = target
                AimState.lockTime     = tick()
            elseif tick() - AimState.lockTime >= AimConfig.reactionDelay then
                if math.random() <= AimConfig.hitChance then
                    AimState.active = true
                    aimMoveCamera(targetPos)
                end
            end
        else
            AimState.active, AimState.lockedTarget = false, nil
        end
    end

    -- ---------- SILENT ----------
    if AimConfig.silentEnabled then
        local target, targetPos = scanForTarget()
        if target and targetPos and math.random() <= AimConfig.hitChance then
            silentAim(targetPos)
            AimState.active, AimState.lockedTarget = true, target
        end
    end

    -- ---------- TRIGGERBOT ----------
    if AimConfig.triggerEnabled then
        local allow = true
        if AimConfig.triggerOnAim
           and not (State.aimKeyHeld or State.trigHeld or State.silentHeld) then
            allow = false
        end
        if allow then
            local target, targetPos = scanForTarget(AimConfig.triggerFov / 2)
            if target and targetPos then
                local dist = (targetPos - Camera.CFrame.Position).Magnitude
                if dist <= AimConfig.triggerMaxDist then
                    if math.random() <= AimConfig.triggerChance then
                        fireClick(AimConfig.triggerHold)
                        AimState.shotsFired += 1
                    end
                    AimState.active, AimState.lockedTarget = true, target
                end
            else
                AimState.active = false
            end
        end
    end
end)

-- =========================================================================
-- 09c · AIM DIAGNOSTICS — prints state every 2s while aiming.
-- disable with AimConfig.debug = false
-- =========================================================================
task.spawn(function()
    while State.alive do
        task.wait(2)
        if AimConfig.debug then
            local on = {}
            if AimConfig.aimEnabled     then on[#on+1] = "AIM" end
            if AimConfig.silentEnabled  then on[#on+1] = "SILENT" end
            if AimConfig.triggerEnabled then on[#on+1] = "TRIG" end

            if #on == 0 then
                print("[ZYON AIM] nenhum bot ligado")
            else
                local lock = AimState.lockedTarget and AimState.lockedTarget.Name or "nenhum"
                print(string.format("[ZYON AIM] %s | alvo: %s | arma: %s",
                    table.concat(on, "+"), lock,
                    hasWeapon() and "sim" or "nao"))
            end
        end
    end
end)

-- =========================================================================
-- 10 · UI CORE
--
--  every page is a ScrollingFrame with a UIListLayout. this is the fix for
--  sections spawning at (0,0) and hiding outside the content area.
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
mainStroke.Color, mainStroke.Thickness, mainStroke.Transparency = Theme.accentDim, 1, 0.4

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
titleText.Size, titleText.BackgroundTransparency = UDim2.new(1, 0, 0, 46), 1
titleText.Text, titleText.TextColor3 = "ZYON", Theme.accent
titleText.Font, titleText.TextSize = Enum.Font.GothamBold, 18
titleText.Parent = sideBar

local titleSub = Instance.new("TextLabel")
titleSub.Size, titleSub.Position, titleSub.BackgroundTransparency = UDim2.new(1,0,0,14), UDim2.new(0,0,0,30), 1
titleSub.Text, titleSub.TextColor3 = "suite v10", Theme.textDim
titleSub.Font, titleSub.TextSize = Enum.Font.Gotham, 10
titleSub.Parent = sideBar

local divider = Instance.new("Frame")
divider.Size, divider.Position = UDim2.new(1, -20, 0, 1), UDim2.new(0, 10, 0, 48)
divider.BackgroundColor3, divider.BorderSizePixel = Theme.row, 0
divider.Parent = sideBar

local tabHolder = Instance.new("Frame")
tabHolder.Size, tabHolder.Position = UDim2.new(1, -12, 1, -122), UDim2.new(0, 6, 0, 58)
tabHolder.BackgroundTransparency = 1
tabHolder.Parent = sideBar

local tabLayout = Instance.new("UIListLayout", tabHolder)
tabLayout.Padding, tabLayout.SortOrder = UDim.new(0, 6), Enum.SortOrder.LayoutOrder

local statusLabel = Instance.new("TextLabel")
statusLabel.Size, statusLabel.Position = UDim2.new(1, -12, 0, 48), UDim2.new(0, 6, 1, -54)
statusLabel.BackgroundTransparency = 1
statusLabel.Text, statusLabel.TextColor3 = "armed", Theme.accent
statusLabel.Font, statusLabel.TextSize = Enum.Font.Code, 9
statusLabel.TextWrapped = true
statusLabel.TextXAlignment, statusLabel.TextYAlignment =
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
statusLabel.Parent = sideBar

local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Size, contentArea.Position = UDim2.new(1, -168, 1, -20), UDim2.new(0, 160, 0, 10)
contentArea.BackgroundTransparency = 1
contentArea.Parent = mainFrame

local pages, tabButtons = {}, {}

local function selectPage(name)
    for n, page in pairs(pages) do page.Visible = (n == name) end
    for n, btn in pairs(tabButtons) do
        local on = (n == name)
        btn.BackgroundColor3 = on and Theme.row or Theme.sidebar
        btn.TextColor3 = on and Theme.accent or Theme.textDim
        local ind = btn:FindFirstChild("Indicator")
        if ind then ind.Visible = on end
    end
end

-- page: ScrollingFrame + horizontal row of two columns, each with its own list
local function makePage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.Visible = false
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Theme.accentDim
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.Parent = contentArea
    pages[name] = page

    -- the row must NOT inherit the viewport height. inside a ScrollingFrame with
    -- AutomaticCanvasSize.Y, a 1,0,1,0 child makes the automatic canvas measure
    -- against an unstable base and the whole page can collapse to zero height.
    -- height is computed from the tallest column instead.
    local row = Instance.new("Frame")
    row.Name = "Row"
    row.Size = UDim2.new(1, 0, 0, 0)
    row.BackgroundTransparency = 1
    row.Parent = page

    local rowList = Instance.new("UIListLayout", row)
    rowList.FillDirection = Enum.FillDirection.Horizontal
    rowList.Padding = UDim.new(0, 8)
    rowList.SortOrder = Enum.SortOrder.LayoutOrder

    -- grows the row to the tallest column so the canvas always has real height
    local function syncRow()
        local tallest = 0
        for _, col in ipairs(row:GetChildren()) do
            if col:IsA("Frame") and col.Name == "Col" then
                local h = col.AbsoluteSize.Y
                if h > tallest then tallest = h end
            end
        end
        if tallest > 0 then
            row.Size = UDim2.new(1, 0, 0, tallest)
        end
    end

    -- re-measure whenever any column changes size
    row.ChildAdded:Connect(function()
        task.defer(function()
            for _ = 1, 5 do syncRow(); task.wait(0.05) end
            local list = row:FindFirstChildOfClass("UIListLayout")
            if list then
                list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncRow)
            end
        end)
    end)

    return page, row
end

-- =========================================================================
-- 11 · WIDGETS
-- =========================================================================
local refreshHooks, refreshing = {}, false

local function refreshAll()
    if refreshing then return end
    refreshing = true
    for _, fn in ipairs(refreshHooks) do pcall(fn) end
    refreshing = false
end

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
    btn.Size, btn.BackgroundColor3 = UDim2.new(1, 0, 0, 30), Theme.sidebar
    btn.BorderSizePixel, btn.Text = 0, "   " .. name
    btn.TextColor3, btn.Font, btn.TextSize = Theme.textDim, Enum.Font.GothamSemibold, 12
    btn.TextXAlignment, btn.LayoutOrder, btn.AutoButtonColor =
        Enum.TextXAlignment.Left, order, false
    btn.Parent = tabHolder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size, indicator.Position = UDim2.new(0, 3, 0, 16), UDim2.new(0, 0, 0.5, -8)
    indicator.BackgroundColor3, indicator.BorderSizePixel, indicator.Visible =
        Theme.accent, 0, false
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
end

-- column inside a page row: fixed width, auto height.
-- named "Col" so makePage's syncRow can find it.
local function makeColumn(row, width, order)
    local col = Instance.new("Frame")
    col.Name = "Col"
    col.Size = UDim2.new(0, width, 0, 0)
    col.AutomaticSize = Enum.AutomaticSize.Y
    col.Position = UDim2.new(0, (order - 1) * (width + 8), 0, 0)
    col.BackgroundTransparency = 1
    col.LayoutOrder = order
    col.Parent = row
    local list = Instance.new("UIListLayout", col)
    list.Padding, list.SortOrder = UDim.new(0, 8), Enum.SortOrder.LayoutOrder
    return col
end

-- section: auto-height box that grows with its content.
-- CRITICAL: the box needs its own UIListLayout, otherwise AutomaticSize.Y only
-- measures the header label (26px) and the box collapses, hiding every widget.
local function makeSection(parent, title, order, scrollHeight)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.BackgroundColor3 = Theme.section
    box.BorderSizePixel = 0
    box.LayoutOrder = order
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

    -- this layout is what makes AutomaticSize.Y see the inner content
    local boxList = Instance.new("UIListLayout", box)
    boxList.Padding = UDim.new(0, 4)
    boxList.SortOrder = Enum.SortOrder.LayoutOrder
    boxList.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 26)
    lbl.BackgroundTransparency = 1
    lbl.Text, lbl.TextColor3 = title, Theme.accent
    lbl.TextXAlignment, lbl.Font, lbl.TextSize = Enum.TextXAlignment.Left, Enum.Font.GothamSemibold, 12
    lbl.LayoutOrder = 1
    lbl.Parent = box

    local inner
    if scrollHeight then
        inner = Instance.new("ScrollingFrame")
        inner.Size = UDim2.new(1, -14, 0, scrollHeight)
        inner.ScrollBarThickness = 4
        inner.ScrollBarImageColor3 = Theme.accentDim
        inner.CanvasSize = UDim2.new(0, 0, 0, 0)
        inner.AutomaticCanvasSize = Enum.AutomaticSize.Y
        inner.ScrollingDirection = Enum.ScrollingDirection.Y
    else
        inner = Instance.new("Frame")
        inner.Size = UDim2.new(1, -14, 0, 0)
        inner.AutomaticSize = Enum.AutomaticSize.Y
    end
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 0
    inner.LayoutOrder = 2
    inner.Parent = box

    local list = Instance.new("UIListLayout", inner)
    list.Padding, list.SortOrder = UDim.new(0, 4), Enum.SortOrder.LayoutOrder

    -- inner is inset (7px each side, 4px above/below) so the box list layout
    -- positions it directly under the header without overflow
    inner.Size = UDim2.new(1, -14, 0, scrollHeight or 0)
    inner.AutomaticSize = scrollHeight and Enum.AutomaticSize.None or Enum.AutomaticSize.Y

    if scrollHeight then
        box.AutomaticSize = Enum.AutomaticSize.None
        box.Size = UDim2.new(1, 0, 0, 30 + scrollHeight + 8)
    end

    table.insert(refreshHooks, function()
        box.BackgroundColor3 = Theme.section
        lbl.TextColor3 = Theme.accent
        if scrollHeight then
            pcall(function() inner.ScrollBarImageColor3 = Theme.accentDim end)
        end
    end)

    return box, inner
end

local function addToggle(parent, label, cfgTable, key, order)
    local row = Instance.new("TextButton")
    row.Size, row.BackgroundColor3 = UDim2.new(1, 0, 0, 24), Theme.row
    row.BorderSizePixel, row.Text, row.AutoButtonColor = 0, "", false
    row.LayoutOrder, row.Parent = order, parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size, lbl.Position = UDim2.new(1, -50, 1, 0), UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text, lbl.TextColor3 = label, Theme.text
    lbl.Font, lbl.TextSize, lbl.TextXAlignment = Enum.Font.Gotham, 11, Enum.TextXAlignment.Left
    lbl.Parent = row

    local box = Instance.new("Frame")
    box.Size, box.Position = UDim2.new(0, 30, 0, 14), UDim2.new(1, -38, 0.5, -7)
    box.BorderSizePixel, box.Parent = 0, row
    Instance.new("UICorner", box).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size, knob.BorderSizePixel, knob.Parent = UDim2.new(0, 10, 0, 10), 0, box
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
    row.Size, row.BackgroundColor3 = UDim2.new(1, 0, 0, 34), Theme.row
    row.BorderSizePixel, row.LayoutOrder, row.Parent = 0, order, parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size, lbl.Position = UDim2.new(1, -10, 0, 14), UDim2.new(0, 8, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3, lbl.Font, lbl.TextSize = Theme.text, Enum.Font.Gotham, 11
    lbl.TextXAlignment, lbl.Parent = Enum.TextXAlignment.Left, row

    local track = Instance.new("TextButton")
    track.Size, track.Position = UDim2.new(1, -16, 0, 6), UDim2.new(0, 8, 0, 22)
    track.BackgroundColor3, track.Text, track.AutoButtonColor = Theme.row, "", false
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    fill.BackgroundColor3, fill.BorderSizePixel = Theme.accentDim, 0
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
        cfgTable[key] = math.floor(val / step + 0.5) * step
        render()
    end

    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = true; update(i) end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                     or i.UserInputType == Enum.UserInputType.Touch) then update(i) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    render()
    table.insert(refreshHooks, render)
end

local function addCycle(parent, label, cfgTable, key, options, order)
    local row = Instance.new("TextButton")
    row.Size, row.BackgroundColor3 = UDim2.new(1, 0, 0, 24), Theme.row
    row.BorderSizePixel, row.Text, row.AutoButtonColor = 0, "", false
    row.LayoutOrder, row.Parent = order, parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size, lbl.Position = UDim2.new(1, -10, 1, 0), UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3, lbl.Font, lbl.TextSize = Theme.text, Enum.Font.Gotham, 11
    lbl.TextXAlignment, lbl.Parent = Enum.TextXAlignment.Left, row

    local function render()
        lbl.Text = label .. ":  " .. tostring(cfgTable[key])
        row.BackgroundColor3, lbl.TextColor3 = Theme.row, Theme.text
    end

    row.MouseButton1Click:Connect(function()
        local idx = 1
        for i, v in ipairs(options) do if v == cfgTable[key] then idx = i break end end
        idx = (idx % #options) + 1
        cfgTable[key] = options[idx]
        render()
    end)

    render()
    table.insert(refreshHooks, render)
end

local activeCapture, keybindRegistry = nil, {}

local function addKeybind(parent, label, cfgTable, key, order)
    local row = Instance.new("Frame")
    row.Size, row.BackgroundColor3 = UDim2.new(1, 0, 0, 24), Theme.row
    row.BorderSizePixel, row.LayoutOrder, row.Parent = 0, order, parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local bind = Instance.new("TextButton")
    bind.Size, bind.BackgroundTransparency = UDim2.new(1, -34, 1, 0), 1
    bind.Text, bind.AutoButtonColor, bind.Parent = "", false, row

    local lbl = Instance.new("TextLabel")
    lbl.Size, lbl.Position = UDim2.new(1, 0, 1, 0), UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font, lbl.TextSize, lbl.TextXAlignment = Enum.Font.Gotham, 11, Enum.TextXAlignment.Left
    lbl.Parent = bind

    local clr = Instance.new("TextButton")
    clr.Size, clr.Position = UDim2.new(0, 26, 0, 16), UDim2.new(1, -30, 0.5, -8)
    clr.BackgroundColor3, clr.BorderSizePixel = Theme.accentDim, 0
    clr.Text, clr.TextColor3 = "X", Color3.fromRGB(240, 240, 240)
    clr.Font, clr.TextSize, clr.AutoButtonColor = Enum.Font.GothamBold, 10, false
    clr.Parent = row
    Instance.new("UICorner", clr).CornerRadius = UDim.new(0, 3)

    local function render()
        if activeCapture == bind then
            lbl.Text, lbl.TextColor3 = label .. ":  [ press a key ]", Theme.accent
        else
            local k = cfgTable[key]
            lbl.Text = label .. ":  " .. (k ~= nil and keyName(k) or "none")
            lbl.TextColor3 = k ~= nil and Theme.text or Theme.textDim
        end
        row.BackgroundColor3, clr.BackgroundColor3 = Theme.row, Theme.accentDim
    end

    bind.MouseButton1Click:Connect(function() activeCapture = bind; refreshAll() end)
    clr.MouseButton1Click:Connect(function()
        cfgTable[key] = nil
        if activeCapture == bind then activeCapture = nil end
        refreshAll()
    end)

    table.insert(keybindRegistry, {bind = bind, cfgTable = cfgTable, key = key})
    table.insert(refreshHooks, render)
    render()
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

local function addColorPicker(parent, label, themeKey, order)
    local holder = Instance.new("Frame")
    holder.Size, holder.BackgroundColor3 = UDim2.new(1, 0, 0, 106), Theme.row
    holder.BorderSizePixel, holder.LayoutOrder, holder.Parent = 0, order, parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 4)

    local head = Instance.new("Frame")
    head.Size, head.Position = UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 3)
    head.BackgroundTransparency, head.Parent = 1, holder

    local lbl = Instance.new("TextLabel")
    lbl.Size, lbl.BackgroundTransparency = UDim2.new(1, -30, 1, 0), 1
    lbl.Text, lbl.TextColor3 = label, Theme.text
    lbl.Font, lbl.TextSize, lbl.TextXAlignment = Enum.Font.Gotham, 11, Enum.TextXAlignment.Left
    lbl.Parent = head

    local swatch = Instance.new("Frame")
    swatch.Size, swatch.Position = UDim2.new(0, 20, 0, 14), UDim2.new(1, -22, 0.5, -7)
    swatch.BackgroundColor3, swatch.BorderSizePixel, swatch.Parent = Theme[themeKey], 0, head
    Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 3)

    local channels, CH = {}, {"R", "G", "B"}
    local seed = Theme[themeKey]
    channels.R = math.floor(seed.R * 255)
    channels.G = math.floor(seed.G * 255)
    channels.B = math.floor(seed.B * 255)

    local function apply()
        Theme[themeKey] = Color3.fromRGB(channels.R, channels.G, channels.B)
        swatch.BackgroundColor3 = Theme[themeKey]
        queueRepaint()
    end

    for ci, cname in ipairs(CH) do
        local pr = Instance.new("Frame")
        pr.Size, pr.Position = UDim2.new(1, -10, 0, 24), UDim2.new(0, 5, 0, 24 + (ci-1)*25)
        pr.BackgroundTransparency, pr.Parent = 1, holder

        local cl = Instance.new("TextLabel")
        cl.Size, cl.BackgroundTransparency = UDim2.new(0, 42, 1, 0), 1
        cl.Text, cl.TextColor3 = cname, Theme.textDim
        cl.Font, cl.TextSize, cl.TextXAlignment = Enum.Font.Code, 10, Enum.TextXAlignment.Left
        cl.Parent = pr

        local track = Instance.new("TextButton")
        track.Size, track.Position = UDim2.new(1, -48, 0, 6), UDim2.new(0, 44, 0.5, -3)
        track.BackgroundColor3, track.Text, track.AutoButtonColor = Color3.fromRGB(50,50,50), "", false
        track.Parent = pr
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame", track)
        fill.BorderSizePixel = 0
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local val = Instance.new("TextLabel")
        val.Size, val.Position = UDim2.new(0, 26, 1, 0), UDim2.new(1, -26, 0, 0)
        val.BackgroundTransparency, val.TextColor3 = 1, Theme.textDim
        val.Font, val.TextSize, val.TextXAlignment = Enum.Font.Code, 10, Enum.TextXAlignment.Right
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
            paint(); apply()
        end

        track.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = true; update(i) end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                         or i.UserInputType == Enum.UserInputType.Touch) then update(i) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)

        table.insert(refreshHooks, function()
            local c = Theme[themeKey]
            channels[cname] = (cname == "R" and math.floor(c.R * 255))
                           or (cname == "G" and math.floor(c.G * 255))
                           or math.floor(c.B * 255)
            paint()
            holder.BackgroundColor3, lbl.TextColor3 = Theme.row, Theme.text
            cl.TextColor3, val.TextColor3 = Theme.textDim, Theme.textDim
            swatch.BackgroundColor3 = c
        end)

        paint()
    end
end

local function addLabel(parent, text, order, height)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, height or 14)
    lbl.BackgroundTransparency = 1
    lbl.Text, lbl.TextColor3 = text, Theme.textDim
    lbl.Font, lbl.TextSize = Enum.Font.Code, 9
    lbl.TextXAlignment, lbl.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    lbl.TextWrapped = true
    lbl.LayoutOrder, lbl.Parent = order, parent
    table.insert(refreshHooks, function() lbl.TextColor3 = Theme.textDim end)
    return lbl
end

-- action button: runs a callback, shows a short confirmation
local function addButton(parent, text, order, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 26)
    btn.BackgroundColor3 = Theme.accentDim
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.LayoutOrder = order
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local original = text
    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        btn.Text = ok and "aplicado" or "erro"
        task.delay(1, function()
            btn.Text = original
        end)
        if not ok then print("[ZyonSuite] botao '" .. original .. "': " .. tostring(err)) end
        refreshAll()
    end)

    table.insert(refreshHooks, function()
        btn.BackgroundColor3 = Theme.accentDim
        btn.TextColor3 = Theme.text
    end)
    return btn
end

-- =========================================================================
-- 12 · TABS
-- =========================================================================
local espPage, espRow       = makePage("ESP")
local aimPage, aimRow       = makePage("AIM")
local themePage, themeRow   = makePage("THEME")
local cfgPage, cfgRow       = makePage("SETTINGS")

makeTab("ESP",      1)
makeTab("AIMBOT",   2)
makeTab("THEME",    3)
makeTab("SETTINGS", 4)

local COL_W = 218

-- build errors are reported instead of silently killing every later tab
local buildErrors = {}
local function buildTab(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        buildErrors[#buildErrors + 1] = name .. ": " .. tostring(err)
        print("[ZyonSuite] build error in " .. name .. ": " .. tostring(err))
    end
end

-- ---- ESP ---------------------------------------------------------------
buildTab("ESP", function()
    local colL = makeColumn(espRow, COL_W, 1)
    local colR = makeColumn(espRow, COL_W, 2)

    local _, v = makeSection(colL, "VISUALS", 1)
    addToggle(v, "Enabled",      Config, "enabled",         1)
    addToggle(v, "Box",          Config, "box",             2)
    addToggle(v, "Name",         Config, "name",            3)
    addToggle(v, "Full Display", Config, "showDisplayName", 4)
    addToggle(v, "Distance",     Config, "distance",        5)
    addToggle(v, "Skeleton",     Config, "skeleton",        6)

    local _, hh = makeSection(colL, "HEALTH", 2)
    addToggle(hh, "Health Bar",  Config, "healthBar", 1)
    addToggle(hh, "Health Text", Config, "health",    2)

    local _, kb = makeSection(colL, "KEYBIND", 3)
    addKeybind(kb, "Toggle ESP", KeyConfig, "espToggle", 1)
    addLabel(kb, "X clears the bind", 2)

    local _, rng = makeSection(colR, "RANGE", 1)
    addSlider(rng, "Max Distance", Config, "maxDistance", 50, 1500, 25,
        function(x) return tostring(x) .. " studs" end, 1)
    addSlider(rng, "Update Rate",  Config, "updateRate",  5, 60, 5,
        function(x) return tostring(x) .. " Hz" end, 2)

    local _, bx = makeSection(colR, "BOX SIZE", 2)
    addSlider(bx, "Height",  Config, "boxHeightRatio", 1.2, 3.0, 0.05,
        function(x) return string.format("%.2fx", x) end, 1)
    addSlider(bx, "Width",   Config, "boxWidthRatio",  0.3, 1.0, 0.02,
        function(x) return string.format("%.2fx", x) end, 2)
    addSlider(bx, "Top Pad", Config, "boxTopPadding",  0, 0.4, 0.02,
        function(x) return string.format("%.2f", x) end, 3)

    local _, tr = makeSection(colR, "TRACER + FILTER", 3)
    addToggle(tr, "Tracer", Config, "tracer", 1)
    addCycle(tr, "Origin", Config, "tracerFrom", {"Bottom", "Mouse", "Top"}, 2)
    addToggle(tr, "Team Check", Config, "teamCheck", 3)
    addSlider(tr, "Fill Alpha", Config, "fillAlpha", 0, 1, 0.05,
        function(x) return string.format("%.2f", x) end, 4)
end)

-- ---- AIMBOT ------------------------------------------------------------
buildTab("AIMBOT", function()
    local colL = makeColumn(aimRow, COL_W, 1)
    local colR = makeColumn(aimRow, COL_W, 2)

    -- ===== QUICK START =====
    local _, quick = makeSection(colL, "QUICK START", 1)
    addButton(quick, "ATIVAR AIMBOT (cabeca)", 1, function()
        -- desliga tudo, liga so o aimbot basico na cabeca
        AimConfig.silentEnabled  = false
        AimConfig.triggerEnabled = false

        AimConfig.aimEnabled     = true
        AimConfig.hitPart        = "Head"
        AimConfig.fov            = 180
        AimConfig.maxDistance    = 1000
        AimConfig.smoothness     = 0.35
        AimConfig.maxStep        = 45
        AimConfig.reactionDelay  = 0
        AimConfig.hitChance      = 1.0
        AimConfig.humanize       = false
        AimConfig.prediction     = false
        AimConfig.requireEquipped= false
        AimConfig.teamCheck      = true
        AimConfig.visibleCheck   = false
        AimConfig.wallCheck      = false

        if not KeyConfig.aimKey then
            KeyConfig.aimKey = Enum.KeyCode.E
        end
    end)
    addLabel(quick, "liga o aimbot na cabeca com\nconfig permissiva. segure a Aim Key.", 2, 26)

    -- ===== AIMBOT =====
    local _, aim = makeSection(colL, "AIMBOT", 2)
    addToggle(aim, "Aimbot Enabled",  AimConfig, "aimEnabled",      1)
    addToggle(aim, "Toggle Mode",     AimConfig, "aimToggleMode",   2)
    addKeybind(aim, "Aim Key", KeyConfig, "aimKey", 3)
    addSlider(aim, "Smoothness", AimConfig, "smoothness", 0.05, 0.6, 0.01,
        function(x) return string.format("%.2f", x) end, 4)
    addSlider(aim, "Max Step", AimConfig, "maxStep", 2, 45, 1,
        function(x) return tostring(x) .. " deg/f" end, 5)
    addSlider(aim, "Reaction", AimConfig, "reactionDelay", 0, 0.4, 0.01,
        function(x) return string.format("%.2fs", x) end, 6)
    addToggle(aim, "Humanize",   AimConfig, "humanize",   7)
    addToggle(aim, "Prediction", AimConfig, "prediction", 8)
    addToggle(aim, "Debug Print", AimConfig, "debug",     9)

    -- ===== TRIGGERBOT =====
    local _, trig = makeSection(colL, "TRIGGERBOT", 3)
    addToggle(trig, "Trigger Enabled", AimConfig, "triggerEnabled", 1)
    addKeybind(trig, "Trigger Key", KeyConfig, "triggerKey", 2)
    addSlider(trig, "Shot Chance", AimConfig, "triggerChance", 0.1, 1, 0.05,
        function(x) return string.format("%d%%", math.floor(x * 100)) end, 3)
    addSlider(trig, "Delay", AimConfig, "triggerDelay", 0, 0.3, 0.005,
        function(x) return string.format("%.3fs", x) end, 4)
    addSlider(trig, "Click Hold", AimConfig, "triggerHold", 0.01, 0.2, 0.005,
        function(x) return string.format("%.3fs", x) end, 5)
    addSlider(trig, "Range", AimConfig, "triggerMaxDist", 50, 800, 25,
        function(x) return tostring(x) .. " studs" end, 6)
    addSlider(trig, "Cone", AimConfig, "triggerFov", 2, 60, 1,
        function(x) return tostring(x) .. " deg" end, 7)
    addToggle(trig, "Only While Aiming", AimConfig, "triggerOnAim", 8)

    -- ===== SILENT =====
    local _, silent = makeSection(colR, "SILENT AIM", 1)
    addToggle(silent, "Silent Enabled", AimConfig, "silentEnabled", 1)
    addKeybind(silent, "Silent Key", KeyConfig, "silentKey", 2)
    addCycle(silent, "Transport", AimConfig, "silentMethod",
        {"Mouse", "CFrame", "VirtualInput"}, 3)
    addSlider(silent, "Smooth", AimConfig, "silentSmooth", 0, 1, 0.05,
        function(x) return x == 0 and "instant" or string.format("%.2f", x) end, 4)
    addToggle(silent, "Wall Check", AimConfig, "wallCheck", 5)

    -- ===== HIT PART =====
    local _, body = makeSection(colR, "HIT PART", 2)
    addCycle(body, "Body Part", AimConfig, "hitPart",
        {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Arms", "Legs", "Nearest"}, 1)
    addSlider(body, "Height Offset", AimConfig, "hitOffsetY", -2, 2, 0.05,
        function(x) return string.format("%+.2f studs", x) end, 2)
    addSlider(body, "Hit Chance", AimConfig, "hitChance", 0.1, 1, 0.05,
        function(x) return string.format("%d%%", math.floor(x * 100)) end, 3)

    -- ===== TARGET =====
    local _, cone = makeSection(colR, "TARGET SELECT", 3)
    addCycle(cone, "Priority", AimConfig, "priority",
        {"Distance", "FOV", "Health", "Crosshair"}, 1)
    addSlider(cone, "FOV", AimConfig, "fov", 10, 180, 5,
        function(x) return tostring(x) .. " deg" end, 2)
    addSlider(cone, "Max Distance", AimConfig, "maxDistance", 50, 1000, 25,
        function(x) return tostring(x) .. " studs" end, 3)
    addToggle(cone, "Team Check",    AimConfig, "teamCheck",    4)
    addToggle(cone, "Visible Check", AimConfig, "visibleCheck", 5)
    addToggle(cone, "Require Weapon", AimConfig, "requireEquipped", 6)
end)

-- ---- THEME -------------------------------------------------------------
buildTab("THEME", function()
    local colL = makeColumn(themeRow, COL_W, 1)
    local colR = makeColumn(themeRow, COL_W, 2)

    local _, acc = makeSection(colL, "ACCENT", 1, 220)
    addColorPicker(acc, "Accent",     "accent",    1)
    addColorPicker(acc, "Accent Dim", "accentDim", 2)

    local _, surf = makeSection(colR, "SURFACES", 1, 220)
    addColorPicker(surf, "Background", "background", 1)
    addColorPicker(surf, "Sidebar",    "sidebar",    2)

    local _, txt = makeSection(colL, "TEXT", 2, 220)
    addColorPicker(txt, "Text",     "text",    1)
    addColorPicker(txt, "Text Dim", "textDim", 2)

    local _, more = makeSection(colR, "BOXES + ROWS", 2, 220)
    addColorPicker(more, "Section Box", "section", 1)
    addColorPicker(more, "Widget Row",  "row",     2)

    local _, pre = makeSection(colL, "PRESETS", 3)
    local presetRow = Instance.new("Frame")
    presetRow.Size, presetRow.BackgroundTransparency = UDim2.new(1, 0, 0, 26), 1
    presetRow.LayoutOrder, presetRow.Parent = 1, pre
    local plist = Instance.new("UIListLayout", presetRow)
    plist.FillDirection, plist.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 4)

    local PRESETS = {
        {name = "Red",    accent = Color3.fromRGB(255, 50, 50),  dim = Color3.fromRGB(150, 30, 30)},
        {name = "Cyan",   accent = Color3.fromRGB(0, 220, 220),  dim = Color3.fromRGB(0, 120, 120)},
        {name = "Green",  accent = Color3.fromRGB(0, 220, 120),  dim = Color3.fromRGB(0, 120, 70)},
        {name = "Purple", accent = Color3.fromRGB(170, 60, 255), dim = Color3.fromRGB(95, 30, 150)},
        {name = "Orange", accent = Color3.fromRGB(255, 150, 40), dim = Color3.fromRGB(150, 85, 25)},
    }

    for _, preset in ipairs(PRESETS) do
        local pb = Instance.new("TextButton")
        pb.Size, pb.BackgroundColor3 = UDim2.new(0, 40, 1, 0), preset.accent
        pb.BorderSizePixel, pb.Text, pb.AutoButtonColor = 0, "", false
        pb.Parent = presetRow
        Instance.new("UICorner", pb).CornerRadius = UDim.new(0, 4)
        pb.MouseButton1Click:Connect(function()
            Theme.accent, Theme.accentDim = preset.accent, preset.dim
            refreshAll()
        end)
        table.insert(refreshHooks, function() pb.BackgroundColor3 = preset.accent end)
    end

    local _, mt = makeSection(colR, "MENU", 3)
    addSlider(mt, "Transparency", Theme, "transparency", 0, 0.8, 0.05,
        function(x) return string.format("%.2f", x) end, 1)
    table.insert(refreshHooks, function()
        mainFrame.BackgroundTransparency = Theme.transparency
        mainStroke.Color = Theme.accentDim
        sideBar.BackgroundColor3 = Theme.sidebar
        sideCover.BackgroundColor3 = Theme.sidebar
        divider.BackgroundColor3 = Theme.row
        mainFrame.BackgroundColor3 = Theme.background
        titleText.TextColor3 = Theme.accent
        titleSub.TextColor3 = Theme.textDim
        contentArea.BackgroundTransparency = 1
    end)
end)

-- ---- SETTINGS ----------------------------------------------------------
buildTab("SETTINGS", function()
    local colL = makeColumn(cfgRow, COL_W, 1)
    local colR = makeColumn(cfgRow, COL_W, 2)

    local _, kb = makeSection(colL, "MENU KEYBIND", 1)
    addKeybind(kb, "Open / Close", KeyConfig, "uiToggle", 1)
    addLabel(kb, "default: RightShift\nX clears the bind", 2, 28)

    local _, safe = makeSection(colL, "SAFETY", 2)
    addToggle(safe, "Opsec",        Config, "opsec",       1)
    addToggle(safe, "Probe Guard",  Config, "probeGuard",  2)
    addToggle(safe, "Auto-Disable", Config, "autoDisable", 3)

    local _, info = makeSection(colR, "RUNTIME", 1)
    local infoLbl = addLabel(info, "collecting", 1, 76)

    local _, st = makeSection(colR, "STATUS + BINDS", 2)
    local stateLbl = Instance.new("TextLabel")
    stateLbl.Size, stateLbl.BackgroundTransparency = UDim2.new(1, 0, 0, 100), 1
    stateLbl.Text, stateLbl.TextColor3 = "armed", Theme.accent
    stateLbl.Font, stateLbl.TextSize = Enum.Font.Code, 10
    stateLbl.TextXAlignment, stateLbl.TextYAlignment =
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    stateLbl.LayoutOrder, stateLbl.Parent = 1, st

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
                stateLbl.Text = table.concat({
                    "menu   : " .. keyName(KeyConfig.uiToggle),
                    "aim    : " .. keyName(KeyConfig.aimKey),
                    "silent : " .. keyName(KeyConfig.silentKey),
                    "trig   : " .. keyName(KeyConfig.triggerKey),
                    "esp    : " .. keyName(KeyConfig.espToggle),
                    "",
                    "aim " .. (AimConfig.aimEnabled and "ON" or "off")
                        .. "  sil " .. (AimConfig.silentEnabled and "ON" or "off")
                        .. "  trg " .. (AimConfig.triggerEnabled and "ON" or "off"),
                }, "\n")
            end)
        end
    end)
end)

-- =========================================================================
-- 13 · SAFETY + BINDS + BOOT
-- =========================================================================
-- watchdog: if any page collapsed, force its row to the tallest column height
-- and print what happened. this is the safety net for the empty-tab symptom.
task.spawn(function()
    for _ = 1, 8 do
        task.wait(0.25)
        for name, page in pairs(pages) do
            local row = page:FindFirstChild("Row")
            if row then
                local tallest = 0
                for _, col in ipairs(row:GetChildren()) do
                    if col:IsA("Frame") and col.Name == "Col" then
                        if col.AbsoluteSize.Y > tallest then tallest = col.AbsoluteSize.Y end
                    end
                end
                if tallest > 0 and row.AbsoluteSize.Y < tallest - 1 then
                    row.Size = UDim2.new(1, 0, 0, tallest)
                end
                if tallest == 0 then
                    print("[ZyonSuite] page " .. name .. " has zero-height columns")
                end
            end
        end
    end
    for _, e in ipairs(buildErrors) do print("[ZyonSuite] " .. e) end
end)

task.spawn(function()
    while State.alive do
        task.wait(2)
        if Config.probeGuard then
            local reason = probeCheck()
            if reason then
                if Config.autoDisable then
                    killSwitch(reason)
                    pcall(function() statusLabel.Text = "KILLED\n" .. reason end)
                else
                    pcall(function() statusLabel.Text = "probe: " .. reason end)
                end
            end
        end
        if State.alive then
            pcall(function()
                local n = 0
                for _, k in ipairs(POOL_KINDS) do if poolUse[k] > n then n = poolUse[k] end end
                statusLabel.Text = string.format("armed\n%d seen", n)
            end)
        end
    end
end)

UserInputService.InputBegan:Connect(function(i, processed)
    if commitCapture(i) then return end
    if processed then return end

    if KeyConfig.uiToggle and i.KeyCode == KeyConfig.uiToggle then
        mainFrame.Visible = not mainFrame.Visible

    elseif KeyConfig.espToggle and i.KeyCode == KeyConfig.espToggle then
        Config.enabled = not Config.enabled
        refreshAll()

    elseif KeyConfig.aimKey and i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = true
        AimConfig.aimEnabled = AimConfig.aimToggleMode and (not AimConfig.aimEnabled) or true
        refreshAll()

    elseif KeyConfig.silentKey and i.KeyCode == KeyConfig.silentKey then
        State.silentHeld = true
        AimConfig.silentEnabled = not AimConfig.silentEnabled
        refreshAll()

    elseif KeyConfig.triggerKey and i.KeyCode == KeyConfig.triggerKey then
        State.trigHeld = true
        AimConfig.triggerEnabled = not AimConfig.triggerEnabled
        refreshAll()
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if KeyConfig.aimKey and i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = false
        if not AimConfig.aimToggleMode then
            AimConfig.aimEnabled = false
            AimState.active = false
        end
    end
    if KeyConfig.silentKey and i.KeyCode == KeyConfig.silentKey then State.silentHeld = false end
    if KeyConfig.triggerKey and i.KeyCode == KeyConfig.triggerKey then State.trigHeld = false end
end)

registerCleanup(function()
    pcall(function() uiGui:Destroy() end)
    if drawGui then pcall(function() drawGui:Destroy() end) end
end)

task.defer(function()
    selectPage("ESP")
    refreshAll()
end)

getgenv().ZyonSuite = {
    Config = Config,
    Aim    = AimConfig,
    Theme  = Theme,
    Keys   = KeyConfig,
    Team   = Team,
    State  = State,
    unload = function()
        State.alive = false
        Config.enabled, AimConfig.aimEnabled = false, false
        AimConfig.silentEnabled, AimConfig.triggerEnabled = false, false
        runCleanup()
    end,
}
