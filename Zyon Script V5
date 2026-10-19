--[[
    ZYON SUITE — single-file build (v5)
    target : Roblox executor
    build  : hardened ESP + aimbot (Camera/Silent/Triggerbot) + tabbed UI + THEME tab

    changes over v4
      - FIXED : espToggle and uiToggle both bound to RightShift (menu ate the ESP bind)
      - ADDED : THEME tab — live colour pickers for every UI surface
      - ADDED : performance pass — lazy skeleton, rig cache, pooled drawing objects,
                single RenderStepped loop, reused RaycastParams
      - ADDED : theme persists across respawn via a captured session snapshot

    run order: join a server FIRST, then execute.

    layout
      01 CONFIG + THEME
      02 SERVICES
      03 OPSEC
      04 SPOOF
      05 PROBE GUARD
      06 TEAM
      07 DRAW CORE (pooled)
      08 ESP LOOP + AIMBOT (single loop)
      09 UI CORE
      10 UI WIDGETS
      11 UI TABS
      12 SAFETY + BINDS
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
    headDot         = true,
    skeleton        = false,        -- lazy: 20 Drawing objects allocated only when true

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

    hitPart         = "Head",       -- "Head" | "UpperTorso" | "LowerTorso" | "HumanoidRootPart" | "Nearest"
    hitOffsetY      = 0,
    hitboxExpand    = 1.0,

    smoothness      = 0.22,
    maxStep         = 12,
    prediction      = true,
    predictionTime  = 0.14,

    humanize        = true,
    jitterAmount    = 0.35,
    overshoot       = 0.08,
    reactionDelay   = 0.09,

    triggerDelay    = 0.02,
    triggerHold     = 0.04,
    triggerChance   = 1.0,
    triggerOnAim    = false,
    triggerMaxDist  = 400,

    silentMethod    = "Mouse",      -- "Mouse" | "CFrame" | "VirtualInput"
    silentSmooth    = 0.0,

    maxFovChange    = 15,
    requireEquipped = true,
}

-- ---- THEME: every colour the UI uses, all live-editable ----------------
local Theme = {
    accent      = Color3.fromRGB(255, 50, 50),   -- titles, indicators, active tab
    accentDim   = Color3.fromRGB(150, 30, 30),   -- toggle on, slider fill
    background  = Color3.fromRGB(25, 25, 25),    -- main frame
    sidebar     = Color3.fromRGB(20, 20, 20),    -- sidebar
    section     = Color3.fromRGB(30, 30, 30),    -- section boxes
    row         = Color3.fromRGB(36, 36, 36),    -- widget rows
    text        = Color3.fromRGB(205, 205, 205), -- widget labels
    textDim     = Color3.fromRGB(170, 170, 170), -- inactive tabs
    stroke      = true,                          -- outer border
    transparency= 0.1,                           -- frame background alpha
}

local KeyConfig = {
    espToggle  = Enum.KeyCode.RightShift,
    aimKey     = Enum.KeyCode.E,
    silentKey  = Enum.KeyCode.Q,
    triggerKey = Enum.KeyCode.C,
    uiToggle   = Enum.KeyCode.RightControl,   -- was RightShift, collided with ESP
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
        local marks = {
            "syn", "KRNL_LOADED", "is_sirhurt_closure",
            "fluxus", "is_fluxus", "secure_load", "ZyonESP", "ZyonSuite",
        }
        for _, k in ipairs(marks) do
            pcall(function() rawset(genv, k, nil) end)
        end
    end)

    pcall(function()
        local env = (getfenv and getfenv(0)) or _G
        if type(env) ~= "table" then return end
        if env.getidentity       then env.getidentity       = function() return 2 end end
        if env.getthreadidentity then env.getthreadidentity = function() return 2 end end
        if env.getscriptidentity then env.getscriptidentity = function() return 2 end end
    end)
end

-- =========================================================================
-- 04 · SPOOF
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
                    or l:find("cheat") or l:find("flag") or l:find("suspect") then
                        hum:SetAttribute(attr, nil)
                    end
                end
            end)
        end
        pcall(function()
            for _, c in ipairs(char:GetChildren()) do
                local l = c.Name:lower()
                if l:find("esp") or l:find("aim") or l:find("zyon") then c:Destroy() end
            end
        end)
    end

    if LocalPlayer.Character then stabilize(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(function(c) task.wait(0.5) stabilize(c) end)
end

-- =========================================================================
-- 05 · PROBE GUARD / KILL SWITCH
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
            if c:IsA("Folder") or c:IsA("Model") or c:IsA("RemoteEvent")
            or c:IsA("BindableEvent") or c:IsA("ObjectValue") then
                local n = c.Name:lower()
                if n:find("check") or n:find("detect") or n:find("probe")
                or n:find("verify") or n:find("scan") then
                    return "character_probe:" .. c.Name
                end
            end
        end
    end

    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, a in ipairs(hum:GetAttributes()) do
            local l = a:lower()
            if l:find("flag") or l:find("suspect") or l:find("cheat")
            or l:find("hack") or l:find("ban") then
                return "attribute_flag:" .. a
            end
        end
    end

    if guiObjectCount() > baselineGuiObjects + 250 then
        return "gui_scan"
    end

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
-- 06 · TEAM
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
-- 07 · DRAW CORE — pooled, zero allocation inside the loop
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

local function makeLine()
    if useDrawing then return Drawing.new("Line") end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Parent = drawGui
    return f
end

local function makeCircle(radius)
    if useDrawing then
        local d = Drawing.new("Circle")
        d.Radius, d.Filled = radius, true
        return d
    end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Size = UDim2.fromOffset(radius * 2, radius * 2)
    Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
    f.Parent = drawGui
    return f
end

local function setVisible(o, s) pcall(function() o.Visible = s end) end

-- pools: one slot per on-screen target, reused forever
local POOL_KINDS = {"box", "name", "dist", "hBg", "hFg", "hTxt", "head", "tracer"}
local pool    = {}
local poolUse = {}
for _, k in ipairs(POOL_KINDS) do pool[k] = {}; poolUse[k] = 0 end

local FACTORY = {
    box    = makeBox,
    name   = function() return makeText(13, true) end,
    dist   = function() return makeText(12, true) end,
    hBg    = makeFill,
    hFg    = makeFill,
    hTxt   = function() return makeText(12, false) end,
    head   = function() return makeCircle(3) end,
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

local function resetPool()
    for _, k in ipairs(POOL_KINDS) do poolUse[k] = 0 end
end

local function hideRemainder()
    for _, k in ipairs(POOL_KINDS) do
        local list = pool[k]
        for i = poolUse[k] + 1, #list do setVisible(list[i], false) end
    end
end

registerCleanup(function()
    for _, k in ipairs(POOL_KINDS) do
        for _, o in ipairs(pool[k]) do
            if useDrawing then pcall(function() o:Remove() end)
            else pcall(function() o:Destroy() end) end
        end
    end
end)

-- lazy skeleton: allocated only when the toggle is on
local skelPool = {}

local function acquireSkel(i)
    local ln = skelPool[i]
    if not ln then
        ln = makeLine()
        skelPool[i] = ln
    end
    return ln
end

-- cached rig lookup — FindFirstChild is expensive at 30Hz
local rigCache     = setmetatable({}, { __mode = "k" })
local rigCacheTime = setmetatable({}, { __mode = "k" })
local RIG_TTL      = 1.0

local function getRig(p)
    local now = os.clock()
    local c = rigCache[p]
    if c and (now - (rigCacheTime[p] or 0)) < RIG_TTL then
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

-- reused RaycastParams — constructing one per frame is a measurable cost
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRayFilter()
    local parts = {Camera}
    if LocalPlayer.Character then parts[#parts + 1] = LocalPlayer.Character end
    rayParams.FilterDescendantsInstances = parts
end

-- target list refreshed at 10Hz, not every frame
local targetList = {}
local targetListTime = 0

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
-- 08 · ESP + AIMBOT — one RenderStepped, one accumulator
-- =========================================================================
local SKEL_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
    "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
}
local SKEL_LINKS = {
    {1,2}, {2,3}, {2,4}, {4,5}, {2,6}, {6,7}, {3,8}, {8,9}, {3,10}, {10,11},
}

local AimState = {
    active         = false,
    lockedTarget   = nil,
    lockTime       = 0,
    lastAimTime    = 0,
    overshootUntil = 0,
    triggerQueued  = false,
    triggerAt      = 0,
    shotsFired     = 0,
    silentActive   = false,
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

local function resolveHitPosition(char)
    if not char then return nil, nil end

    local function finish(part)
        if not part then return nil, nil end
        return part.Position + Vector3.new(0, AimConfig.hitOffsetY, 0), part
    end

    if AimConfig.hitPart == "Nearest" then
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

    local part = char:FindFirstChild(AimConfig.hitPart)
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

local function selectTarget()
    local camCF  = Camera.CFrame
    local myPos  = camCF.Position
    local myLook = camCF.LookVector

    local best, bestScore, bestPos = nil, math.huge, nil

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
                                if ang <= AimConfig.fov / 2 then
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
    AimState.silentActive = true

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

local function crosshairOnTarget()
    local target, targetPos = selectTarget()
    if not target or not targetPos then return nil end
    local toTarget = targetPos - Camera.CFrame.Position
    local gate     = math.min(AimConfig.fov, 12) / 2
    if angleBetween(Camera.CFrame.LookVector, toTarget) > gate then return nil end
    return target, targetPos
end

local function fireClick(holdTime)
    pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 1) end)
    task.delay(holdTime or AimConfig.triggerHold, function()
        pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
    end)
end

-- ---- the single loop ---------------------------------------------------
local accum = 0

RunService.RenderStepped:Connect(function(dt)
    if not State.alive then return end

    local interval = 1 / math.max(Config.updateRate, 1)
    accum += dt
    if accum < interval then return end
    accum = 0

    -- ================= ESP =================
    if Config.enabled then
        resetPool()
        refreshRayFilter()

        local targets  = refreshTargetList()
        local camPos   = Camera.CFrame.Position
        local maxD     = Config.maxDistance
        local camCF    = Camera.CFrame

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
                            local h   = math.abs(rootSp.Y - headSp.Y) * 1.55
                            local w   = h * 0.55
                            local top = headSp.Y - h * 0.18
                            local lft = rootSp.X - w / 2
                            local hf  = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local col = healthColor(hf)
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

                                local d = acquire("dist")
                                d.Visible, d.Position, d.Text = Config.distance,
                                    Vector2.new(lft + w / 2, top + h + 4),
                                    string.format("%d studs", math.floor(dist))
                                d.Color = Theme.textDim

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

                                local hd = acquire("head")
                                hd.Visible, hd.Position, hd.Color =
                                    Config.headDot, Vector2.new(headSp.X, headSp.Y), Config.boxColor

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

                                -- lazy skeleton
                                if Config.skeleton then
                                    local pts = {}
                                    for si, n in ipairs(SKEL_PARTS) do
                                        local part = p.Character:FindFirstChild(n)
                                        if part then
                                            local ssp = Camera:WorldToViewportPoint(part.Position)
                                            pts[si] = Vector2.new(ssp.X, ssp.Y)
                                        end
                                    end
                                    local idx = 0
                                    for li, link in ipairs(SKEL_LINKS) do
                                        local a, b2 = pts[link[1]], pts[link[2]]
                                        if a and b2 then
                                            idx += 1
                                            local ln = acquireSkel(idx)
                                            ln.Visible = true
                                            ln.From, ln.To, ln.Color = a, b2, Config.boxColor
                                        end
                                    end
                                    for k = idx + 1, #skelPool do skelPool[k].Visible = false end
                                else
                                    for k = 1, #skelPool do skelPool[k].Visible = false end
                                end
                            else
                                -- GUI fallback
                                local b = acquire("box")
                                b.Visible, b.Position, b.Size = Config.box,
                                    UDim2.fromOffset(lft, top), UDim2.fromOffset(w, h)
                                b.BorderColor3 = Config.boxColor

                                local nm = acquire("name")
                                nm.Visible  = Config.name
                                nm.Position = UDim2.fromOffset(lft + w / 2 - 75, top - 15)
                                nm.Size     = UDim2.fromOffset(150, 14)
                                nm.Text     = label
                                nm.TextColor3 = Theme.text

                                local d = acquire("dist")
                                d.Visible  = Config.distance
                                d.Position = UDim2.fromOffset(lft + w / 2 - 50, top + h + 4)
                                d.Size     = UDim2.fromOffset(100, 12)
                                d.Text     = string.format("%d studs", math.floor(dist))
                                d.TextColor3 = Theme.textDim

                                local bg = acquire("hBg")
                                bg.Visible  = Config.healthBar
                                bg.Position = UDim2.fromOffset(lft - 6, top)
                                bg.Size     = UDim2.fromOffset(3, h)
                                bg.BackgroundColor3 = Color3.new(0, 0, 0)

                                local fg = acquire("hFg")
                                fg.Visible  = Config.healthBar
                                fg.Position = UDim2.fromOffset(lft - 6, top + h * (1 - hf))
                                fg.Size     = UDim2.fromOffset(3, h * hf)
                                fg.BackgroundColor3 = col

                                local ht = acquire("hTxt")
                                ht.Visible  = Config.health
                                ht.Position = UDim2.fromOffset(lft + w + 4, top + h / 2 - 7)
                                ht.Size     = UDim2.fromOffset(40, 14)
                                ht.Text     = string.format("%d", math.floor(hum.Health))
                                ht.TextColor3 = col

                                local hd = acquire("head")
                                hd.Visible  = Config.headDot
                                hd.Position = UDim2.fromOffset(headSp.X - 3, headSp.Y - 3)
                                hd.BackgroundColor3 = Config.boxColor

                                local tr = acquire("tracer"); tr.Visible = false
                                for k = 1, #skelPool do skelPool[k].Visible = false end
                            end
                        end
                    end
                end
            end
        end

        hideRemainder()
    else
        for _, k in ipairs(POOL_KINDS) do
            for _, o in ipairs(pool[k]) do setVisible(o, false) end
        end
        for k = 1, #skelPool do skelPool[k].Visible = false end
    end

    -- ================= AIMBOT =================
    if AimConfig.enabled then
        if hasWeapon() then
            if AimConfig.mode == "Triggerbot" then
                if not (AimConfig.triggerOnAim and not State.aimKeyHeld) then
                    local target, targetPos = crosshairOnTarget()
                    if target and targetPos then
                        local dist = (targetPos - Camera.CFrame.Position).Magnitude
                        if dist <= AimConfig.triggerMaxDist then
                            if not AimState.triggerQueued then
                                AimState.triggerQueued = true
                                local jitter = (1 - AimConfig.triggerChance) * math.random() * 0.08
                                AimState.triggerAt = tick() + AimConfig.triggerDelay + jitter
                                AimState.lockedTarget = target
                            end
                            if tick() >= AimState.triggerAt then
                                fireClick(AimConfig.triggerHold)
                                AimState.shotsFired += 1
                                AimState.triggerQueued = false
                                AimState.triggerAt = tick() + 0.08
                            end
                            AimState.active = true
                        else
                            AimState.active = false
                        end
                    else
                        AimState.triggerQueued = false
                        AimState.active = false
                        AimState.lockedTarget = nil
                    end
                end
            else
                local target, targetPos = selectTarget()
                if target then
                    if target ~= AimState.lockedTarget then
                        AimState.lockedTarget = target
                        AimState.lockTime     = tick()
                        AimState.active       = false
                        AimState.lastAimTime  = tick()
                    elseif tick() - AimState.lockTime >= 0.05 then
                        AimState.active = true
                        if AimConfig.mode == "Silent" then
                            silentAim(targetPos)
                        else
                            AimState.silentActive = false
                            aimMoveCamera(targetPos)
                        end
                    end
                else
                    AimState.active = false
                    AimState.lockedTarget = nil
                    AimState.silentActive = false
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
mainFrame.Size = UDim2.new(0, 600, 0, 400)
mainFrame.Position = UDim2.new(0.5, -300, 0.5, -200)
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
mainStroke.Transparency = 0.5

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
titleText.Size = UDim2.new(1, 0, 0, 50)
titleText.BackgroundTransparency = 1
titleText.Text = "ZYON"
titleText.TextColor3 = Theme.accent
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 18
titleText.Parent = sideBar

local titleSub = Instance.new("TextLabel")
titleSub.Size = UDim2.new(1, 0, 0, 14)
titleSub.Position = UDim2.new(0, 0, 0, 32)
titleSub.BackgroundTransparency = 1
titleSub.Text = "suite v5"
titleSub.TextColor3 = Color3.fromRGB(110, 110, 110)
titleSub.Font = Enum.Font.Gotham
titleSub.TextSize = 10
titleSub.Parent = sideBar

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -20, 0, 1)
divider.Position = UDim2.new(0, 10, 0, 52)
divider.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
divider.BorderSizePixel = 0
divider.Parent = sideBar

local tabHolder = Instance.new("Frame")
tabHolder.Size = UDim2.new(1, -12, 1, -116)
tabHolder.Position = UDim2.new(0, 6, 0, 62)
tabHolder.BackgroundTransparency = 1
tabHolder.Parent = sideBar

local tabLayout = Instance.new("UIListLayout", tabHolder)
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -12, 0, 46)
statusLabel.Position = UDim2.new(0, 6, 1, -52)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "armed"
statusLabel.TextColor3 = Color3.fromRGB(120, 200, 120)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 9
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = sideBar

local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Size = UDim2.new(1, -166, 1, -20)
contentArea.Position = UDim2.new(0, 158, 0, 10)
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
local function refreshAll()
    for _, fn in ipairs(refreshHooks) do pcall(fn) end
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
        btn.BackgroundColor3 = (pages[name] and pages[name].Visible) and Theme.row or Theme.sidebar
        btn.TextColor3 = (pages[name] and pages[name].Visible) and Theme.accent or Theme.textDim
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
        inner.ScrollBarThickness = 3
        inner.CanvasSize = UDim2.new(0, 0, 0, 0)
        inner.AutomaticCanvasSize = Enum.AutomaticSize.Y
    else
        inner = Instance.new("Frame")
    end
    inner.Size = UDim2.new(1, -12, 1, -32)
    inner.Position = UDim2.new(0, 6, 0, 30)
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 0
    inner.Parent = box

    local list = Instance.new("UIListLayout", inner)
    list.Padding = UDim.new(0, 4)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    table.insert(refreshHooks, function()
        box.BackgroundColor3 = Theme.section
        lbl.TextColor3 = Theme.accent
        if scrollable and inner.ScrollBarImageColor3 then
            inner.ScrollBarImageColor3 = Theme.accentDim
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
        box.BackgroundColor3  = on and Theme.accentDim or Color3.fromRGB(50, 50, 50)
        knob.Position         = on and UDim2.new(1, -12, 0.5, -5) or UDim2.new(0, 2, 0.5, -5)
        knob.BackgroundColor3 = on and Theme.accent or Color3.fromRGB(150, 150, 150)
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
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
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

local activeCapture = nil
local keybindRegistry = {}

local function addKeybind(parent, label, cfgTable, key, order)
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
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local function render()
        if activeCapture == row then
            lbl.Text = label .. ":  [ press a key ]"
            lbl.TextColor3 = Theme.accent
        else
            local k = cfgTable[key]
            lbl.Text = label .. ":  " .. tostring(type(k) == "userdata" and k.Name or k)
            lbl.TextColor3 = Theme.text
        end
        row.BackgroundColor3 = Theme.row
    end

    row.MouseButton1Click:Connect(function()
        activeCapture = row
        refreshAll()
    end)

    table.insert(keybindRegistry, {row = row, cfgTable = cfgTable, key = key})
    table.insert(refreshHooks, render)
    render()
    return row
end

-- ---- COLOUR PICKER (RGB sliders + live preview swatch) -----------------
local function addColorPicker(parent, label, themeKey, order)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 108)
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

    local function apply()
        local c = Color3.fromRGB(channels.R, channels.G, channels.B)
        Theme[themeKey] = c
        swatch.BackgroundColor3 = c
        refreshAll()
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
        cl.TextColor3 = Color3.fromRGB(160, 160, 160)
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
        val.TextColor3 = Color3.fromRGB(160, 160, 160)
        val.Font = Enum.Font.Code
        val.TextSize = 10
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.Parent = pr

        local dragging = false
        local function update(input)
            local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
            channels[cname] = math.floor(rel * 255 + 0.5)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            val.Text = tostring(channels[cname])
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
            local cur = (cname == "R" and math.floor(c.R * 255))
                     or (cname == "G" and math.floor(c.G * 255))
                     or math.floor(c.B * 255)
            channels[cname] = cur
            fill.Size = UDim2.new(cur / 255, 0, 1, 0)
            fill.BackgroundColor3 = c
            val.Text = tostring(cur)
            pr.BackgroundTransparency = 1
            cl.TextColor3 = Theme.textDim
            val.TextColor3 = Theme.textDim
            holder.BackgroundColor3 = Theme.row
            lbl.TextColor3 = Theme.text
            swatch.BackgroundColor3 = c
        end)
    end

    -- seed from the current theme value
    local c = Theme[themeKey]
    channels.R = math.floor(c.R * 255)
    channels.G = math.floor(c.G * 255)
    channels.B = math.floor(c.B * 255)
end

-- =========================================================================
-- 11 · UI TABS
-- =========================================================================
local espPage  = makePage("ESP")
local aimPage  = makePage("AIM")
local ctrlPage = makePage("CTRL")
local themePage= makePage("THEME")
local cfgPage  = makePage("SETTINGS")

makeTab("ESP",      1)
makeTab("AIMBOT",   2)
makeTab("CONTROL",  3)
makeTab("THEME",    4)
makeTab("SETTINGS", 5)

-- ---- ESP ---------------------------------------------------------------
do
    local colL = makeColumn(espPage, 0)
    local colR = makeColumn(espPage, 1)

    local _, v = makeSection(colL, "VISUALS", 1, 220)
    addToggle(v, "Enabled",      Config, "enabled",         1)
    addToggle(v, "Box",          Config, "box",             2)
    addToggle(v, "Name",         Config, "name",            3)
    addToggle(v, "Full Display", Config, "showDisplayName", 4)
    addToggle(v, "Distance",     Config, "distance",        5)
    addToggle(v, "Head Dot",     Config, "headDot",         6)
    addToggle(v, "Skeleton",     Config, "skeleton",        7)

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

    local _, tr = makeSection(colR, "TRACER", 2, 92)
    addToggle(tr, "Tracer", Config, "tracer", 1)
    addCycle(tr, "Origin", Config, "tracerFrom", {"Bottom", "Mouse", "Top"}, 2)

    local _, fl = makeSection(colR, "FILTER", 3, 92)
    addToggle(fl, "Team Check", Config, "teamCheck", 1)
    addSlider(fl, "Fill Alpha", Config, "fillAlpha", 0, 1, 0.05,
        function(x) return string.format("%.2f", x) end, 2)
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

    local _, hit = makeSection(colR, "HITBOX", 1, 148, true)
    addCycle(hit, "Hit Part", AimConfig, "hitPart",
        {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Nearest"}, 1)
    addSlider(hit, "Height Offset", AimConfig, "hitOffsetY", -2, 2, 0.05,
        function(x) return string.format("%+.2f studs", x) end, 2)
    addSlider(hit, "Expansion", AimConfig, "hitboxExpand", 1, 2, 0.05,
        function(x) return string.format("%.2fx", x) end, 3)

    local _, cone = makeSection(colR, "TARGET SELECT", 2, 168)
    addCycle(cone, "Priority", AimConfig, "priority",
        {"Distance", "FOV", "Health", "Crosshair"}, 1)
    addSlider(cone, "FOV", AimConfig, "fov", 10, 180, 5,
        function(x) return tostring(x) .. " deg" end, 2)
    addSlider(cone, "Max Distance", AimConfig, "maxDistance", 50, 1000, 25,
        function(x) return tostring(x) .. " studs" end, 3)
    addToggle(cone, "Team Check",    AimConfig, "teamCheck",    4)
    addToggle(cone, "Visible Check", AimConfig, "visibleCheck", 5)
end

-- ---- CONTROL -----------------------------------------------------------
do
    local colL = makeColumn(ctrlPage, 0)
    local colR = makeColumn(ctrlPage, 1)

    local _, motion = makeSection(colL, "MOTION", 1, 174, true)
    addSlider(motion, "Smoothness", AimConfig, "smoothness", 0.05, 0.6, 0.01,
        function(x) return string.format("%.2f", x) end, 1)
    addSlider(motion, "Max Step", AimConfig, "maxStep", 2, 45, 1,
        function(x) return tostring(x) .. " deg/frame" end, 2)
    addToggle(motion, "Prediction", AimConfig, "prediction", 3)
    addSlider(motion, "Lead Time", AimConfig, "predictionTime", 0, 0.4, 0.01,
        function(x) return string.format("%.2fs", x) end, 4)

    local _, human = makeSection(colL, "HUMANIZE", 2, 174, true)
    addToggle(human, "Humanize", AimConfig, "humanize", 1)
    addSlider(human, "Jitter", AimConfig, "jitterAmount", 0, 2, 0.05,
        function(x) return string.format("%.2f", x) end, 2)
    addSlider(human, "Overshoot", AimConfig, "overshoot", 0, 0.4, 0.01,
        function(x) return string.format("%.2f", x) end, 3)
    addSlider(human, "Reaction Delay", AimConfig, "reactionDelay", 0, 0.4, 0.01,
        function(x) return string.format("%.2fs", x) end, 4)

    local _, trig = makeSection(colR, "TRIGGERBOT", 1, 240, true)
    addSlider(trig, "Trigger Delay", AimConfig, "triggerDelay", 0, 0.3, 0.005,
        function(x) return string.format("%.3fs", x) end, 1)
    addSlider(trig, "Click Hold", AimConfig, "triggerHold", 0.01, 0.2, 0.005,
        function(x) return string.format("%.3fs", x) end, 2)
    addSlider(trig, "Hit Chance", AimConfig, "triggerChance", 0.1, 1, 0.05,
        function(x) return string.format("%d%%", math.floor(x * 100)) end, 3)
    addSlider(trig, "Trigger Range", AimConfig, "triggerMaxDist", 50, 800, 25,
        function(x) return tostring(x) .. " studs" end, 4)
    addToggle(trig, "Only While Aiming", AimConfig, "triggerOnAim", 5)

    local _, silent = makeSection(colR, "SILENT", 2, 148, true)
    addCycle(silent, "Transport", AimConfig, "silentMethod",
        {"Mouse", "CFrame", "VirtualInput"}, 1)
    addSlider(silent, "Silent Smooth", AimConfig, "silentSmooth", 0, 1, 0.05,
        function(x) return x == 0 and "instant" or string.format("%.2f", x) end, 2)
    addToggle(silent, "Wall Check", AimConfig, "wallCheck", 3)
end

-- ---- THEME -------------------------------------------------------------
do
    local colL = makeColumn(themePage, 0)
    local colR = makeColumn(themePage, 1)

    local _, acc = makeSection(colL, "ACCENT", 1, 276, true)
    addColorPicker(acc, "Accent",      "accent",     1)
    addColorPicker(acc, "Accent Dim",  "accentDim",  2)

    local _, surf = makeSection(colR, "SURFACES", 1, 276, true)
    addColorPicker(surf, "Background", "background", 1)
    addColorPicker(surf, "Sidebar",    "sidebar",    2)

    -- lower half gets its own column pair via a second row of sections
    local _, txt = makeSection(colL, "TEXT", 2, 168, true)
    addColorPicker(txt, "Text",     "text",     1)
    addColorPicker(txt, "Text Dim", "textDim",  2)

    local _, more = makeSection(colR, "ROWS + SECTIONS", 2, 168, true)
    addColorPicker(more, "Section Box", "section", 1)
    addColorPicker(more, "Widget Row",  "row",     2)

    -- quick presets live in the sidebar area of the theme page bottom
    local presetRow = Instance.new("Frame")
    presetRow.Size = UDim2.new(1, 0, 0, 28)
    presetRow.BackgroundTransparency = 1
    presetRow.LayoutOrder = 3
    presetRow.Parent = makeColumn(themePage, 0)
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
        pb.Size = UDim2.new(0, 52, 1, 0)
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

    local _, safe = makeSection(colL, "SAFETY", 1, 118)
    addToggle(safe, "Opsec",        Config, "opsec",       1)
    addToggle(safe, "Probe Guard",  Config, "probeGuard",  2)
    addToggle(safe, "Auto-Disable", Config, "autoDisable", 3)

    local _, kb = makeSection(colL, "MENU KEYBIND", 2, 62)
    addKeybind(kb, "Toggle Menu", KeyConfig, "uiToggle", 1)

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

    local _, st = makeSection(colR, "STATUS", 2, 92)
    local stateLbl = Instance.new("TextLabel")
    stateLbl.Size = UDim2.new(1, 0, 0, 60)
    stateLbl.BackgroundTransparency = 1
    stateLbl.Text = "armed"
    stateLbl.TextColor3 = Color3.fromRGB(120, 200, 120)
    stateLbl.Font = Enum.Font.Code
    stateLbl.TextSize = 11
    stateLbl.TextXAlignment = Enum.TextXAlignment.Left
    stateLbl.TextYAlignment = Enum.TextYAlignment.Top
    stateLbl.Parent = st

    table.insert(refreshHooks, function()
        infoLbl.TextColor3 = Theme.textDim
    end)

    task.spawn(function()
        while State.alive do
            task.wait(0.5)
            local backend = useDrawing and "Drawing (native)" or "ScreenGui (fallback)"
            local alive = 0
            for _, k in ipairs(POOL_KINDS) do
                if poolUse[k] > alive then alive = poolUse[k] end
            end

            pcall(function()
                infoLbl.Text = string.format(
                    "backend : %s\nplace   : %s\ntargets : %d\nshots   : %d\nuptime  : %ds",
                    backend, tostring(game.PlaceId), alive,
                    AimState.shotsFired, math.floor(tick() - State.startTime))
            end)

            pcall(function()
                if State.detected then
                    stateLbl.Text = "KILLED\n" .. tostring(State.reason)
                    stateLbl.TextColor3 = Color3.fromRGB(255, 80, 80)
                elseif AimState.active and AimState.lockedTarget then
                    stateLbl.Text = string.format("%s LOCK\n%s",
                        string.upper(AimConfig.mode), AimState.lockedTarget.Name)
                    stateLbl.TextColor3 = Theme.accent
                elseif AimConfig.enabled then
                    stateLbl.Text = string.format("%s\nfov %d deg",
                        string.upper(AimConfig.mode), AimConfig.fov)
                    stateLbl.TextColor3 = Color3.fromRGB(255, 200, 90)
                else
                    stateLbl.Text = "ARMED\nesp " .. (Config.enabled and "on" or "off")
                    stateLbl.TextColor3 = Color3.fromRGB(120, 200, 120)
                end
            end)
        end
    end)
end

selectPage("ESP")
refreshAll()

-- =========================================================================
-- 12 · SAFETY LOOP + BINDS
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
                        statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
                    end)
                else
                    pcall(function()
                        statusLabel.Text = "probe: " .. reason
                        statusLabel.TextColor3 = Color3.fromRGB(255, 180, 60)
                    end)
                end
            end
        end

        if State.alive then
            pcall(function()
                local n = 0
                for _, k in ipairs(POOL_KINDS) do
                    if poolUse[k] > n then n = poolUse[k] end
                end
                statusLabel.Text = string.format("armed\n%d targets\n%s", n, string.upper(AimConfig.mode))
                statusLabel.TextColor3 = Color3.fromRGB(120, 200, 120)
            end)
        end
    end
end)

UserInputService.InputBegan:Connect(function(i, processed)
    if commitCapture(i) then return end
    if processed then return end

    if i.KeyCode == KeyConfig.uiToggle then
        mainFrame.Visible = not mainFrame.Visible

    elseif i.KeyCode == KeyConfig.espToggle then
        Config.enabled = not Config.enabled
        refreshAll()

    elseif i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = true
        AimConfig.enabled = AimConfig.toggleMode and (not AimConfig.enabled) or true
        AimState.lastAimTime = tick()
        refreshAll()

    elseif i.KeyCode == KeyConfig.silentKey then
        if AimConfig.mode == "Silent" then
            AimConfig.enabled = not AimConfig.enabled
            refreshAll()
        end

    elseif i.KeyCode == KeyConfig.triggerKey then
        if AimConfig.mode == "Triggerbot" then
            AimConfig.enabled = not AimConfig.enabled
            refreshAll()
        end
    end
end)

local function commitCaptureRun(input) end

UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == KeyConfig.aimKey then
        State.aimKeyHeld = false
        if not AimConfig.toggleMode and AimConfig.mode ~= "Triggerbot" then
            AimConfig.enabled = false
            AimState.active = false
        end
    end
end)

registerCleanup(function()
    pcall(function() uiGui:Destroy() end)
    if drawGui then pcall(function() drawGui:Destroy() end) end
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
