--[[
    LOVE HUB
    Tela de carregamento animada (a personagem vai ficando mais apaixonada até 100%)
    + menu completo (abas, toggles, sliders, dropdowns, botões, notificações).

    COMO USAR (executor):
      1) Copie a pasta "IntroFrames" (46 PNGs) para a pasta "workspace" do executor
         (ou suba num GitHub e preencha CONFIG.BaseUrl).
      2) Execute este arquivo.
      3) Edite a função populate() no final para colocar as funções do SEU script.

    Tecla para esconder/mostrar o menu: RightShift (CONFIG.ToggleKey)
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CONFIG = {
    Title = "LOVE HUB",
    Version = "v1.0",
    LoadTime = 8,                           -- duração mínima do carregamento (segundos)
    Accent = Color3.fromRGB(255, 105, 180),
    ToggleKey = Enum.KeyCode.RightShift,

    NormalFPS = 5,                          -- idle "normal"
    LoveFPSMin = 9,                         -- velocidade da animação apaixonada em 20%
    LoveFPSMax = 16,                        -- ...e em 100%

    Folder = "IntroFrames",                 -- pasta dentro do workspace do executor
    BaseUrl = "https://raw.githubusercontent.com/SEU_USER/SEU_REPO/main/frames/",
    NormalCount = 4,
    LoveCount = 42,

    -- Alternativa: IDs do Roblox (se você subiu as imagens). Se preencher, ignora a pasta/URL.
    AssetIds = {
        Normal = {},   -- {"rbxassetid://1", "rbxassetid://2", ...}
        Love = {},
    },
}

local Theme = {
    Bg = Color3.fromRGB(16, 13, 24),
    Panel = Color3.fromRGB(22, 18, 34),
    Item = Color3.fromRGB(31, 26, 47),
    ItemHover = Color3.fromRGB(41, 34, 62),
    Off = Color3.fromRGB(58, 50, 82),
    Stroke = Color3.fromRGB(70, 58, 100),
    Text = Color3.fromRGB(242, 237, 252),
    SubText = Color3.fromRGB(150, 140, 178),
}

----------------------------------------------------------------
-- INSTÂNCIA ÚNICA
----------------------------------------------------------------
local env = (getgenv and getgenv()) or _G
if env.LoveHub and env.LoveHub.Destroy then
    pcall(env.LoveHub.Destroy, env.LoveHub)
end

----------------------------------------------------------------
-- UTILIDADES
----------------------------------------------------------------
local Accent = CONFIG.Accent
local accentBinders = {}

local function bindAccent(fn)
    table.insert(accentBinders, fn)
    fn(Accent)
end

local function setAccent(color)
    Accent = color
    for _, fn in ipairs(accentBinders) do
        pcall(fn, color)
    end
end

local function create(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function tween(obj, time, props, style, dir)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function round(obj, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius) }, obj)
end

local function outline(obj, color, thickness, transparency)
    return create("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function mount(gui)
    local ok = pcall(function()
        gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function fadeOut(root, time)
    local info = TweenInfo.new(time)
    for _, d in ipairs(root:GetDescendants()) do
        local goal
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            goal = { TextTransparency = 1, BackgroundTransparency = 1 }
        elseif d:IsA("ImageLabel") then
            goal = { ImageTransparency = 1, BackgroundTransparency = 1 }
        elseif d:IsA("Frame") then
            goal = { BackgroundTransparency = 1 }
        elseif d:IsA("UIStroke") then
            goal = { Transparency = 1 }
        end
        if goal then
            TweenService:Create(d, info, goal):Play()
        end
    end
end

----------------------------------------------------------------
-- FRAMES DA PERSONAGEM
----------------------------------------------------------------
local Frames = { Normal = {}, Love = {} }
local useAssetIds = #CONFIG.AssetIds.Normal > 0
local normalTotal = useAssetIds and #CONFIG.AssetIds.Normal or CONFIG.NormalCount
local loveTotal = useAssetIds and #CONFIG.AssetIds.Love or CONFIG.LoveCount
local totalFrames = normalTotal + loveTotal
local loadedCount = 0

local function frameName(kind, i)
    return string.format("%s_%03d.png", kind, i)
end

local function fetchFrame(kind, i)
    local name = frameName(kind, i)
    local path = CONFIG.Folder .. "/" .. name
    if not isfile(path) then
        assert(
            not string.find(CONFIG.BaseUrl, "SEU_USER", 1, true),
            "[LoveHub] Frames não encontrados. Coloque a pasta '" .. CONFIG.Folder
                .. "' no workspace do executor ou configure CONFIG.BaseUrl."
        )
        writefile(path, game:HttpGet(CONFIG.BaseUrl .. name))
    end
    return getcustomasset(path)
end

local function startFrameLoading()
    if useAssetIds then
        Frames.Normal = CONFIG.AssetIds.Normal
        Frames.Love = CONFIG.AssetIds.Love
        loadedCount = totalFrames
        task.spawn(function()
            local list = {}
            for _, id in ipairs(Frames.Normal) do table.insert(list, id) end
            for _, id in ipairs(Frames.Love) do table.insert(list, id) end
            pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
        end)
        return
    end

    pcall(makefolder, CONFIG.Folder)

    -- frames "normal" primeiro (rápido), pois aparecem logo no início
    for i = 1, normalTotal do
        Frames.Normal[i] = fetchFrame("normal", i)
        loadedCount = loadedCount + 1
    end
    -- frames "apaixonada" em paralelo
    for i = 1, loveTotal do
        task.spawn(function()
            local ok, asset = pcall(fetchFrame, "love", i)
            if ok then
                Frames.Love[i] = asset
            else
                warn("[LoveHub] falha ao carregar frame love " .. i .. ": " .. tostring(asset))
            end
            loadedCount = loadedCount + 1
        end)
    end
end

----------------------------------------------------------------
-- CORAÇÕES
----------------------------------------------------------------
local function spawnHeart(layer, intensity, big)
    local size = big and math.random(24, 46) or math.floor(12 + intensity * 16 + math.random(0, 8))
    local startX = 0.08 + math.random() * 0.84
    local startY = 0.5 + math.random() * 0.12

    local heart = create("TextLabel", {
        Text = "♥",
        Font = Enum.Font.GothamBold,
        TextSize = size,
        TextColor3 = Color3.fromRGB(255, math.random(70, 140), math.random(130, 190)),
        BackgroundTransparency = 1,
        TextTransparency = 1,
        Size = UDim2.fromOffset(size, size),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(startX, 0, startY, 0),
        Rotation = math.random(-25, 25),
        ZIndex = 5,
    }, layer)

    local dur = 1.5 + math.random() * 1.3
    tween(heart, 0.2, { TextTransparency = 0 })
    tween(heart, dur, {
        Position = UDim2.new(startX + (math.random() - 0.5) * 0.3, 0, -0.12 - math.random() * 0.25, 0),
        Rotation = heart.Rotation + math.random(-40, 40),
    }, Enum.EasingStyle.Sine)
    task.delay(dur * 0.6, function()
        if heart.Parent then
            tween(heart, dur * 0.4, { TextTransparency = 1 })
        end
    end)
    task.delay(dur + 0.1, function()
        heart:Destroy()
    end)
end

----------------------------------------------------------------
-- TELA DE CARREGAMENTO
----------------------------------------------------------------
local STAGES = {
    { 0.00, "Preparando módulos..." },
    { 0.20, "Ela notou você..." },
    { 0.40, "Ela está corando..." },
    { 0.65, "O coração dela acelerou..." },
    { 0.85, "Quase apaixonada..." },
    { 1.00, "Apaixonada! ♥" },
}

local function runLoading(gui, onDone)
    local overlay = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(8, 6, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, gui)
    tween(overlay, 0.5, { BackgroundTransparency = 0.35 })

    local blur
    pcall(function()
        blur = create("BlurEffect", { Size = 0 }, Lighting)
        tween(blur, 0.6, { Size = 14 })
    end)

    local card = create("Frame", {
        Size = UDim2.fromOffset(440, 390),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.56, 0),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
    }, gui)
    round(card, 18)
    local cardStroke = outline(card, Accent, 1.5, 0.5)
    create("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(34, 20, 46), Color3.fromRGB(14, 12, 22)),
        Rotation = 90,
    }, card)
    tween(card, 0.6, { Position = UDim2.new(0.5, 0, 0.5, 0) }, Enum.EasingStyle.Back)

    local glow = create("Frame", {
        Size = UDim2.fromOffset(240, 240),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 125),
        BackgroundColor3 = Accent,
        BackgroundTransparency = 0.95,
        BorderSizePixel = 0,
        ZIndex = 1,
    }, card)
    create("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)

    local BASE_W, BASE_H = 360, 233 -- proporção dos frames (403x261)
    local char = create("ImageLabel", {
        Size = UDim2.fromOffset(BASE_W, BASE_H),
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 0, 238),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Image = Frames.Normal[1] or "",
        ZIndex = 3,
    }, card)
    tween(char, 0.6, { ImageTransparency = 0 })

    local heartsLayer = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, card)

    create("TextLabel", {
        Text = "♥ " .. CONFIG.Title,
        Font = Enum.Font.GothamBlack,
        TextSize = 24,
        TextColor3 = Theme.Text,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 34),
        Position = UDim2.fromOffset(0, 246),
        ZIndex = 6,
    }, card)

    local statusLabel = create("TextLabel", {
        Text = STAGES[1][2],
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.fromOffset(0, 282),
        ZIndex = 6,
    }, card)

    local barBack = create("Frame", {
        Size = UDim2.new(1, -56, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 314),
        BackgroundColor3 = Color3.fromRGB(40, 34, 58),
        BorderSizePixel = 0,
        ZIndex = 6,
    }, card)
    round(barBack, 5)

    local barFill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.fromRGB(130, 120, 190),
        BorderSizePixel = 0,
        ZIndex = 7,
    }, barBack)
    round(barFill, 5)

    create("TextLabel", {
        Text = "Nível de amor",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(200, 18),
        Position = UDim2.fromOffset(28, 334),
        ZIndex = 6,
    }, card)

    local percentLabel = create("TextLabel", {
        Text = "♥ 0%",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(200, 18),
        Position = UDim2.new(1, -228, 0, 334),
        ZIndex = 6,
    }, card)

    create("TextLabel", {
        Text = "Aperte " .. CONFIG.ToggleKey.Name .. " depois para esconder/mostrar o menu",
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = Color3.fromRGB(105, 96, 130),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.fromOffset(0, 362),
        ZIndex = 6,
    }, card)

    ------------------------------------------------------------
    -- loop principal
    ------------------------------------------------------------
    local startTime = os.clock()
    local frameTimer, frameIdx, heartTimer, pingDir = 0, 1, 0, 1
    local phase, popScale = 0, 0
    local mode = "normal"
    local stageIdx = 1
    local burst, finished = false, false
    local conn

    local function finish()
        finished = true
        conn:Disconnect()
        fadeOut(card, 0.5)
        tween(card, 0.5, { BackgroundTransparency = 1 })
        tween(overlay, 0.6, { BackgroundTransparency = 1 })
        if blur then tween(blur, 0.6, { Size = 0 }) end
        task.wait(0.7)
        card:Destroy()
        overlay:Destroy()
        if blur then blur:Destroy() end
        onDone()
    end

    conn = RunService.RenderStepped:Connect(function(dt)
        if finished then return end

        -- progresso: nunca passa do que já foi baixado nem do tempo mínimo
        local t = math.min((os.clock() - startTime) / CONFIG.LoadTime, 1)
        local timeP = t * t * (3 - 2 * t)
        local realP = loadedCount / totalFrames
        local p = math.min(timeP, realP)
        local pct = math.floor(p * 100)

        -- textos / barra
        percentLabel.Text = "♥ " .. pct .. "%"
        barFill.Size = UDim2.fromScale(p, 1)
        barFill.BackgroundColor3 = Color3.fromRGB(130, 120, 190):Lerp(Accent, p)
        percentLabel.TextColor3 = Color3.fromRGB(190, 170, 220):Lerp(Accent, p)
        cardStroke.Color = Color3.fromRGB(90, 75, 130):Lerp(Accent, p)

        local newStage = 1
        for i, s in ipairs(STAGES) do
            if p >= s[1] then newStage = i end
        end
        if newStage ~= stageIdx then
            stageIdx = newStage
            statusLabel.Text = STAGES[stageIdx][2]
            statusLabel.TextColor3 = Theme.Text
            tween(statusLabel, 0.6, { TextColor3 = Theme.SubText })
        end

        -- troca de "normal" para "apaixonada"
        if mode == "normal" and p >= 0.2 and Frames.Love[1] then
            mode = "love"
            frameIdx = 1
            char.Image = Frames.Love[1]
            popScale = 0.06
            for _ = 1, 6 do
                task.delay(math.random() * 0.3, function() spawnHeart(heartsLayer, 0.3, false) end)
            end
        end

        -- animação dos frames
        local fps = CONFIG.NormalFPS
        if mode == "love" then
            fps = CONFIG.LoveFPSMin + (CONFIG.LoveFPSMax - CONFIG.LoveFPSMin) * p
        end
        frameTimer = frameTimer + dt
        if frameTimer >= 1 / fps then
            frameTimer = 0
            if mode == "love" then
                frameIdx = frameIdx % loveTotal + 1
                local img = Frames.Love[frameIdx]
                if img then
                    char.Image = img
                else
                    frameIdx = 1
                end
            else
                frameIdx = frameIdx + pingDir
                if frameIdx >= #Frames.Normal then
                    pingDir = -1
                elseif frameIdx <= 1 then
                    pingDir = 1
                end
                if Frames.Normal[frameIdx] then
                    char.Image = Frames.Normal[frameIdx]
                end
            end
        end

        -- batimento cardíaco (acelera e aumenta com o %)
        phase = phase + dt * (1.5 + p * 3.5) * math.pi * 2
        local pulse = math.sin(phase) * (0.008 + p * 0.03)
        popScale = popScale * math.max(0, 1 - 7 * dt)
        local scale = 1 + pulse + popScale
        char.Size = UDim2.fromOffset(BASE_W * scale, BASE_H * scale)

        -- brilho e tom rosado
        local g = 240 + 120 * p + pulse * 300
        glow.Size = UDim2.fromOffset(g, g)
        glow.BackgroundTransparency = 0.95 - 0.4 * p
        glow.BackgroundColor3 = Accent
        char.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 205, 225), p * 0.55)

        -- corações: quanto maior o %, mais corações
        heartTimer = heartTimer + dt
        local interval = 1.0 - 0.9 * p
        if p > 0.03 and heartTimer >= interval then
            heartTimer = 0
            spawnHeart(heartsLayer, p, false)
        end

        -- 100%: explosão de amor e abre o menu
        if p >= 1 and not burst then
            burst = true
            popScale = 0.14
            for _ = 1, 38 do
                task.delay(math.random() * 0.6, function() spawnHeart(heartsLayer, 1, true) end)
            end
            task.delay(2.0, finish)
        end
    end)
end

----------------------------------------------------------------
-- MENU
----------------------------------------------------------------
local function buildMenu(gui)
    local Hub = { Tabs = {} }
    local conns = {}
    local WIN_W, WIN_H, TOP_H = 580, 400, 44

    local function connect(signal, fn)
        local c = signal:Connect(fn)
        table.insert(conns, c)
        return c
    end

    ------------------------------------------------------------
    -- janela
    ------------------------------------------------------------
    local window = create("CanvasGroup", {
        Name = "Window",
        Size = UDim2.fromOffset(WIN_W, WIN_H),
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2 + 14),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
        GroupTransparency = 1,
    }, gui)
    round(window, 14)
    local winStroke = outline(window, Accent, 1.2, 0.5)
    bindAccent(function(c) winStroke.Color = c end)

    local top = create("Frame", {
        Size = UDim2.new(1, 0, 0, TOP_H),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, window)

    local title = create("TextLabel", {
        Text = "♥ " .. CONFIG.Title,
        Font = Enum.Font.GothamBlack,
        TextSize = 16,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(200, TOP_H),
        Position = UDim2.fromOffset(16, 0),
        ZIndex = 3,
    }, top)

    create("TextLabel", {
        Text = CONFIG.Version,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(60, TOP_H),
        Position = UDim2.fromOffset(150, 2),
        ZIndex = 3,
    }, top)

    local function topButton(text, xOffset)
        local b = create("TextButton", {
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 18,
            TextColor3 = Theme.SubText,
            BackgroundColor3 = Theme.Item,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Size = UDim2.fromOffset(28, 28),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, xOffset, 0.5, 0),
            ZIndex = 3,
        }, top)
        round(b, 8)
        connect(b.MouseEnter, function()
            tween(b, 0.12, { BackgroundTransparency = 0, TextColor3 = Theme.Text })
        end)
        connect(b.MouseLeave, function()
            tween(b, 0.12, { BackgroundTransparency = 1, TextColor3 = Theme.SubText })
        end)
        return b
    end
    local btnMin = topButton("–", -44)
    local btnClose = topButton("×", -12)

    -- arrastar
    local dragging, dragStart, startPos = false, nil, nil
    connect(top.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    c:Disconnect()
                end
            end)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    -- corpo
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 1, -TOP_H),
        Position = UDim2.fromOffset(0, TOP_H),
        BackgroundTransparency = 1,
    }, window)

    local sidebar = create("Frame", {
        Size = UDim2.new(0, 150, 1, 0),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, body)

    local tabList = create("Frame", {
        Size = UDim2.new(1, 0, 1, -50),
        BackgroundTransparency = 1,
    }, sidebar)
    create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabList)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
    }, tabList)

    create("TextLabel", {
        Text = "Olá, " .. (LocalPlayer and LocalPlayer.DisplayName or "jogador"),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 40),
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 14, 1, 0),
    }, sidebar)

    local pages = create("Frame", {
        Size = UDim2.new(1, -150, 1, 0),
        Position = UDim2.fromOffset(150, 0),
        BackgroundTransparency = 1,
    }, body)

    ------------------------------------------------------------
    -- minimizar / fechar / esconder
    ------------------------------------------------------------
    local minimized, visible = false, true
    connect(btnMin.MouseButton1Click, function()
        minimized = not minimized
        tween(window, 0.3, {
            Size = minimized and UDim2.fromOffset(WIN_W, TOP_H) or UDim2.fromOffset(WIN_W, WIN_H),
        }, Enum.EasingStyle.Quint)
    end)
    connect(btnClose.MouseButton1Click, function()
        Hub:Destroy()
    end)

    function Hub:SetVisible(v)
        visible = v
        if v then
            window.Visible = true
            tween(window, 0.2, { GroupTransparency = 0 })
        else
            tween(window, 0.2, { GroupTransparency = 1 }).Completed:Connect(function()
                if not visible then window.Visible = false end
            end)
        end
    end

    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        if input.KeyCode == CONFIG.ToggleKey then
            Hub:SetVisible(not visible)
        end
    end)

    ------------------------------------------------------------
    -- notificações
    ------------------------------------------------------------
    local notifHolder = create("Frame", {
        Size = UDim2.new(0, 280, 1, -20),
        Position = UDim2.new(1, -296, 0, 10),
        BackgroundTransparency = 1,
    }, gui)
    create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, notifHolder)

    function Hub:Notify(heading, text, duration)
        duration = duration or 4
        local wrap = create("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1 }, notifHolder)
        local card = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.new(1, 30, 0, 0),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, wrap)
        round(card, 10)
        local st = outline(card, Accent, 1, 0.5)
        local bar = create("Frame", {
            Size = UDim2.new(0, 3, 1, -16),
            Position = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Accent,
            BorderSizePixel = 0,
        }, card)
        round(bar, 2)
        create("TextLabel", {
            Text = heading,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -30, 0, 18),
            Position = UDim2.fromOffset(20, 8),
        }, card)
        create("TextLabel", {
            Text = text or "",
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -30, 0, 18),
            Position = UDim2.fromOffset(20, 28),
        }, card)
        tween(card, 0.35, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Back)
        task.delay(duration, function()
            if not card.Parent then return end
            tween(card, 0.25, { Position = UDim2.new(1, 30, 0, 0) }).Completed:Wait()
            wrap:Destroy()
        end)
    end

    ------------------------------------------------------------
    -- abas e componentes
    ------------------------------------------------------------
    local function fireSafe(callback, ...)
        if callback then
            local ok, err = pcall(callback, ...)
            if not ok then warn("[LoveHub] erro no callback: " .. tostring(err)) end
        end
    end

    function Hub:Tab(name)
        local Tab = { _order = 0 }

        local btn = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.Item,
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = #Hub.Tabs + 1,
        }, tabList)
        round(btn, 8)

        local indicator = create("Frame", {
            Size = UDim2.fromOffset(3, 16),
            Position = UDim2.new(0, 6, 0.5, -8),
            BackgroundColor3 = Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, btn)
        round(indicator, 2)
        bindAccent(function(c) indicator.BackgroundColor3 = c end)

        local lbl = create("TextLabel", {
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -20, 1, 0),
            Position = UDim2.fromOffset(20, 0),
        }, btn)

        local page = create("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Accent,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, pages)
        bindAccent(function(c) page.ScrollBarImageColor3 = c end)
        create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14),
        }, page)

        function Tab.deselect()
            page.Visible = false
            tween(btn, 0.15, { BackgroundTransparency = 1 })
            tween(indicator, 0.15, { BackgroundTransparency = 1 })
            tween(lbl, 0.15, { TextColor3 = Theme.SubText })
        end
        function Tab.select()
            for _, t in ipairs(Hub.Tabs) do t.deselect() end
            page.Visible = true
            tween(btn, 0.15, { BackgroundTransparency = 0 })
            tween(indicator, 0.15, { BackgroundTransparency = 0 })
            tween(lbl, 0.15, { TextColor3 = Theme.Text })
        end
        connect(btn.MouseButton1Click, Tab.select)

        table.insert(Hub.Tabs, Tab)
        if #Hub.Tabs == 1 then Tab.select() end

        local function nextOrder()
            Tab._order = Tab._order + 1
            return Tab._order
        end

        local function newRow(height)
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, height),
                BackgroundColor3 = Theme.Item,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, page)
            round(row, 8)
            outline(row, Theme.Stroke, 1, 0.65)
            return row
        end

        local function rowLabel(parent, text, y, h)
            return create("TextLabel", {
                Text = text,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -90, 0, h),
                Position = UDim2.fromOffset(12, y),
            }, parent)
        end

        local function hoverable(row, hit)
            connect(hit.MouseEnter, function() tween(row, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
            connect(hit.MouseLeave, function() tween(row, 0.12, { BackgroundColor3 = Theme.Item }) end)
        end

        function Tab:Section(text)
            local sec = create("TextLabel", {
                Text = string.upper(text),
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextColor3 = Accent,
                TextXAlignment = Enum.TextXAlignment.Left,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 18),
                LayoutOrder = nextOrder(),
            }, page)
            bindAccent(function(c) sec.TextColor3 = c end)
        end

        function Tab:Label(text)
            create("TextLabel", {
                Text = text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                BackgroundTransparency = 1,
                AutomaticSize = Enum.AutomaticSize.Y,
                Size = UDim2.new(1, 0, 0, 16),
                LayoutOrder = nextOrder(),
            }, page)
        end

        function Tab:Button(text, callback)
            local row = newRow(38)
            local hit = create("TextButton", {
                Text = text,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Size = UDim2.fromScale(1, 1),
            }, row)
            hoverable(row, hit)
            connect(hit.MouseButton1Click, function()
                row.BackgroundColor3 = Accent
                tween(row, 0.3, { BackgroundColor3 = Theme.ItemHover })
                fireSafe(callback)
            end)
        end

        function Tab:Toggle(text, default, callback)
            local state = default and true or false
            local row = newRow(40)
            rowLabel(row, text, 0, 40)

            local sw = create("Frame", {
                Size = UDim2.fromOffset(38, 20),
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                BackgroundColor3 = Theme.Off,
                BorderSizePixel = 0,
            }, row)
            round(sw, 10)
            local knob = create("Frame", {
                Size = UDim2.fromOffset(14, 14),
                Position = UDim2.new(0, 3, 0.5, -7),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
            }, sw)
            round(knob, 7)

            local function render(animate)
                local t = animate and 0.16 or 0
                tween(sw, t, { BackgroundColor3 = state and Accent or Theme.Off })
                tween(knob, t, { Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7) })
            end
            bindAccent(function() render(false) end)

            local hit = create("TextButton", {
                Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2,
            }, row)
            hoverable(row, hit)
            connect(hit.MouseButton1Click, function()
                state = not state
                render(true)
                fireSafe(callback, state)
            end)

            return {
                Set = function(_, v) state = v and true or false; render(true); fireSafe(callback, state) end,
                Get = function() return state end,
            }
        end

        function Tab:Slider(text, min, max, default, callback, step)
            step = step or 1
            local value = math.clamp(default or min, min, max)
            local row = newRow(54)
            rowLabel(row, text, 6, 22)

            local valLabel = create("TextLabel", {
                Text = tostring(value),
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Accent,
                TextXAlignment = Enum.TextXAlignment.Right,
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(70, 22),
                Position = UDim2.new(1, -82, 0, 6),
            }, row)
            bindAccent(function(c) valLabel.TextColor3 = c end)

            local bar = create("Frame", {
                Size = UDim2.new(1, -24, 0, 6),
                Position = UDim2.fromOffset(12, 36),
                BackgroundColor3 = Theme.Off,
                BorderSizePixel = 0,
            }, row)
            round(bar, 3)
            local fill = create("Frame", {
                Size = UDim2.fromScale(0, 1), BackgroundColor3 = Accent, BorderSizePixel = 0,
            }, bar)
            round(fill, 3)
            bindAccent(function(c) fill.BackgroundColor3 = c end)
            local knob = create("Frame", {
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
            }, bar)
            round(knob, 6)

            local function setValue(v, fire)
                v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
                value = v
                local a = (max == min) and 0 or (v - min) / (max - min)
                fill.Size = UDim2.fromScale(a, 1)
                knob.Position = UDim2.new(a, -6, 0.5, -6)
                valLabel.Text = tostring(v)
                if fire then fireSafe(callback, v) end
            end
            setValue(value, false)

            local hit = create("TextButton", {
                Text = "", BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 26),
            }, row)
            local sliding = false
            local function fromInput(input)
                local a = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                setValue(min + a * (max - min), true)
            end
            connect(hit.InputBegan, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    fromInput(input)
                end
            end)
            connect(UserInputService.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end)
            connect(UserInputService.InputChanged, function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    fromInput(input)
                end
            end)

            return {
                Set = function(_, v) setValue(v, true) end,
                Get = function() return value end,
            }
        end

        function Tab:Dropdown(text, options, default, callback)
            local current = default or options[1]
            local box = create("Frame", {
                Size = UDim2.new(1, 0, 0, 40),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Item,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, page)
            round(box, 8)
            outline(box, Theme.Stroke, 1, 0.65)
            create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, box)

            local header = create("TextButton", {
                Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1,
            }, box)
            rowLabel(header, text, 0, 40)
            local valLabel = create("TextLabel", {
                Text = tostring(current) .. "  ▾",
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Accent,
                TextXAlignment = Enum.TextXAlignment.Right,
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(150, 40),
                Position = UDim2.new(1, -162, 0, 0),
            }, header)
            bindAccent(function(c) valLabel.TextColor3 = c end)
            hoverable(box, header)

            local opts = create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Visible = false,
                LayoutOrder = 2,
            }, box)
            create("UIListLayout", {
                Padding = UDim.new(0, 4),
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, opts)
            create("UIPadding", { PaddingBottom = UDim.new(0, 8) }, opts)

            for i, opt in ipairs(options) do
                local ob = create("TextButton", {
                    Text = tostring(opt),
                    Font = Enum.Font.Gotham,
                    TextSize = 12,
                    TextColor3 = Theme.Text,
                    BackgroundColor3 = Theme.ItemHover,
                    BackgroundTransparency = 0.4,
                    AutoButtonColor = false,
                    Size = UDim2.new(1, -16, 0, 28),
                    LayoutOrder = i,
                }, opts)
                round(ob, 6)
                connect(ob.MouseEnter, function() tween(ob, 0.1, { BackgroundTransparency = 0 }) end)
                connect(ob.MouseLeave, function() tween(ob, 0.1, { BackgroundTransparency = 0.4 }) end)
                connect(ob.MouseButton1Click, function()
                    current = opt
                    valLabel.Text = tostring(opt) .. "  ▾"
                    opts.Visible = false
                    fireSafe(callback, opt)
                end)
            end
            connect(header.MouseButton1Click, function()
                opts.Visible = not opts.Visible
            end)

            return { Get = function() return current end }
        end

        return Tab
    end

    ------------------------------------------------------------
    -- destruir
    ------------------------------------------------------------
    function Hub:Destroy()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        pcall(function() gui:Destroy() end)
        if env.LoveHub == Hub then env.LoveHub = nil end
    end

    -- entrada suave
    tween(window, 0.5, {
        GroupTransparency = 0,
        Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    }, Enum.EasingStyle.Quint)

    return Hub
end

----------------------------------------------------------------
-- ✏️ COLOQUE AQUI AS FUNÇÕES DO SEU SCRIPT
----------------------------------------------------------------
local function populate(Hub)
    local function humanoid()
        local char = LocalPlayer.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local main = Hub:Tab("Principal")
    main:Section("Jogador")
    main:Slider("Velocidade (WalkSpeed)", 16, 120, 16, function(v)
        local h = humanoid()
        if h then h.WalkSpeed = v end
    end)
    main:Slider("Pulo (JumpPower)", 50, 200, 50, function(v)
        local h = humanoid()
        if h then
            h.UseJumpPower = true
            h.JumpPower = v
        end
    end)
    main:Section("Exemplos")
    main:Toggle("Função de exemplo", false, function(on)
        Hub:Notify("Função de exemplo", on and "Ativada" or "Desativada", 2.5)
        -- TODO: coloque aqui o código do seu script
    end)
    main:Button("Botão de exemplo", function()
        Hub:Notify("Clicou!", "Troque este botão pela sua função.", 3)
    end)

    local visual = Hub:Tab("Visual")
    visual:Section("Aparência")
    local colors = {
        Rosa = Color3.fromRGB(255, 105, 180),
        Roxo = Color3.fromRGB(170, 110, 255),
        Azul = Color3.fromRGB(90, 170, 255),
        Vermelho = Color3.fromRGB(255, 80, 100),
        Verde = Color3.fromRGB(90, 220, 150),
    }
    visual:Dropdown("Cor do tema", { "Rosa", "Roxo", "Azul", "Vermelho", "Verde" }, "Rosa", function(name)
        setAccent(colors[name])
    end)

    local config = Hub:Tab("Config")
    config:Section("Menu")
    config:Label("Aperte " .. CONFIG.ToggleKey.Name .. " para esconder ou mostrar o menu. Arraste pela barra de cima.")
    config:Button("Fechar e descarregar o menu", function()
        Hub:Destroy()
    end)

    Hub:Notify("Bem-vindo(a)!", "Aperte " .. CONFIG.ToggleKey.Name .. " para esconder o menu.", 5)
end

----------------------------------------------------------------
-- INÍCIO
----------------------------------------------------------------
startFrameLoading()

local gui = create("ScreenGui", {
    Name = "LoveHub",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
mount(gui)

runLoading(gui, function()
    local Hub = buildMenu(gui)
    env.LoveHub = Hub
    populate(Hub)
end)
