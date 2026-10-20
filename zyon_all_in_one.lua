local identifyexecutor = rawget(getfenv(), "identifyexecutor")
local gethui          = rawget(getfenv(), "gethui")
local getgenv         = rawget(getfenv(), "getgenv")
local writefile       = rawget(getfenv(), "writefile")
local getcustomasset  = rawget(getfenv(), "getcustomasset")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInput    = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer  = Players.LocalPlayer
local function log(...)
    local n = select("#", ...)
    local t = table.create(n)
    for i = 1, n do
        t[i] = tostring(select(i, ...))
    end
    print("[Zyon] " .. table.concat(t, " "))
end
log("=== ZYON MENU — TUDO EM UM SÓ ===")
if identifyexecutor ~= nil then
    local ok, name = pcall(identifyexecutor)
    log("executor:", ok and tostring(name) or "?")
end
log("Drawing disponivel:", tostring(rawget(getfenv(), "Drawing") ~= nil),
    "(nao usamos de qualquer forma)")
local ZYON_ESP = (function()
local identifyexecutor = rawget(getfenv(), "identifyexecutor")
local gethui          = rawget(getfenv(), "gethui")
local getgenv         = rawget(getfenv(), "getgenv")
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local function log(...)
    local n = select("#", ...)
    local t = table.create(n)
    for i = 1, n do
        t[i] = tostring(select(i, ...))
    end
    print("[ZyonESP] " .. table.concat(t, " "))
end
local CFG = {
    enabled         = true,
    team_check      = true,
    max_dist        = 3000,
    show_box        = true,
    show_fill       = false,
    box_style       = "Normal",
    box_scale       = 1.0,
    fill_alpha      = 0.88,
    stroke_thickness = 1.5,
    label_size      = 13,
    show_name       = true,
    show_dist       = true,
    show_dist_m     = false,
    show_dist_studs = true,
    dist_unit       = "m",
    studs_per_meter = 3.571,
    show_health     = true,
    show_health_num = false,
    show_health_bar = true,
    show_glow       = true,
    show_chams      = true,
    show_skeleton   = false,
    show_snapline   = false,
    show_tracer     = false,
    show_head_dot   = false,
    show_armor      = false,
    show_tool       = false,
    show_status     = false,
    show_occlusion  = true,
    show_speed      = false,
    visible_only    = true,
    glow            = true,
    glow_layers     = 3,
    glow_intensity  = 1.0,
    color_enemy     = Color3.fromRGB(255, 70, 70),
    color_team      = Color3.fromRGB(70, 200, 255),
    color_glow      = Color3.fromRGB(255, 60, 140),
    color_dead      = Color3.fromRGB(150, 150, 150),
    color_skeleton  = Color3.fromRGB(255, 255, 255),
    tracer_color    = Color3.fromRGB(255, 70, 70),
    snapline_color  = Color3.fromRGB(255, 70, 70),
    head_dot_color  = Color3.fromRGB(255, 70, 70),
    tracer_width    = 1,
    snapline_width  = 1,
    head_dot_size   = 7,
    skeleton_width  = 1,
}
log("=== INICIO ===")
if identifyexecutor ~= nil then
    local ok, name = pcall(identifyexecutor)
    log("executor:", ok and tostring(name) or "?")
end
log("LocalPlayer:", LocalPlayer.Name)
local function gui_parent(): Instance
    if gethui ~= nil then
        local ok, h = pcall(gethui)
        if ok and h ~= nil then
            return h :: Instance
        end
    end
    return game:GetService("CoreGui")
end
local sg = Instance.new("ScreenGui")
sg.Name = "ZyonESP"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
    local ok, err = pcall(function()
        sg.Parent = gui_parent()
    end)
    if not ok then
        log("ERRO ao criar ScreenGui:", tostring(err))
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg ~= nil then
            sg.Parent = pg
            log("ScreenGui pendurada em PlayerGui (fallback)")
        end
    end
end
log("ScreenGui:", sg.Parent ~= nil and tostring(sg.Parent) or "NIL — FALHOU")
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Position = UDim2.new(0, 0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 200
overlay.Active = false
overlay.Parent = sg
local function new(class: string, props: { [string]: any }?, parent: Instance?): Instance
    local inst = Instance.new(class)
    if props ~= nil then
        for k, v in pairs(props) do
            local ok, err = pcall(function()
                (inst :: any)[k] = v
            end)
            if not ok then
                log("propriedade falhou:", class, tostring(k), tostring(err))
            end
        end
    end
    if parent ~= nil then
        inst.Parent = parent
    end
    return inst
end
local function setp(inst: Instance?, prop: string, valor: any)
    if inst == nil then
        return false
    end
    local ok, err = pcall(function()
        (inst :: any)[prop] = valor
    end)
    if not ok then
        log("setp falhou:", tostring(prop), tostring(err))
    end
    return ok
end
local function getp(inst: Instance?, prop: string): any
    if inst == nil then
        return nil
    end
    local ok, valor = pcall(function()
        local alvo = inst :: any
        return alvo[prop]
    end)
    if not ok then
        log("getp falhou:", tostring(prop), tostring(valor))
        return nil
    end
    return valor
end
local HRP_NAME = "HumanoidRootPart"
local SKELETON_BONES = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "Left Arm" },
    { "UpperTorso", "Right Arm" },
    { "UpperTorso", "Left Leg" },
    { "UpperTorso", "Right Leg" },
    { "LowerTorso", "Left Leg" },
    { "LowerTorso", "Right Leg" },
    { "Left Leg", "Left Foot" },
    { "Right Leg", "Right Foot" },
    { "Head", "Right Arm" },
}
local api_set_max: (number) -> number
type Glow = {
    frame: Frame?,
    stroke: UIStroke?,
}
type Part2D = {
    frame: Frame?,
}
type Line2D = {
    line: Frame?,
    glow: Frame?,
}
type Esp = {
    bb: BillboardGui?,
    fill: Frame?,
    glow1: Frame?,
    glow2: Frame?,
    glow3: Frame?,
    box: Frame?,
    stroke: UIStroke?,
    stroke2: UIStroke?,
    stroke3: UIStroke?,
    corners: { Frame? },
    corners3d: { Frame? },
    hp_bg: Frame?,
    hp_fill: Frame?,
    hp_stroke: UIStroke?,
    label: TextLabel?,
    parts: { Frame? },
    head_dot: Frame?,
    skeleton: { Line2D },
    tracer: Line2D,
    snapline: Line2D,
    chams: Highlight?,
}
type Entry = {
    esp: Esp,
    adornee: BasePart?,
    last_pos: Vector3?,
    speed: number,
    speed_t: number,
    visible: boolean?,
    vis_t: number,
    adv: Adv?,
}
type Adv = {
    has_ut: boolean,
    has_lt: boolean,
    has_torso: boolean,
}
local line_owner: { [Frame]: string } = {}
local adv_state: { [Player]: Adv } = {}
local warned_used = {}
local function claim(store, obj: Frame?, tag: string, parent: Instance?): Frame?
    if obj == nil then
        return nil
    end
    local dono = store[obj]
    if dono ~= nil and dono ~= tag and not warned_used[tag] then
        warned_used[tag] = true
        log("AVISO: Frame de linha ja pertence a", dono, "-- reassumido por", tag)
    end
    store[obj] = tag
    if parent ~= nil and obj.Parent ~= parent then
        local ok, err = pcall(function()
            obj.Parent = parent
        end)
        if not ok then
            log("ERRO ao reparentar", tag, ":", tostring(err))
            return nil
        end
    end
    return obj
end
local function release(store, obj: Frame?)
    if obj ~= nil then
        store[obj] = nil
    end
end
local function glow_frame(bb: BillboardGui?, z: number): Frame?
    return new("Frame", {
        Name = "Glow",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = CFG.color_glow,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = z,
        Visible = false,
    }, bb) :: Frame?
end
local function glow_stroke(f: Frame?, z: number): UIStroke?
    if f == nil then
        return nil
    end
    return new("UIStroke", {
        Name = "GlowStroke",
        Color = CFG.color_glow,
        Thickness = 2,
        Transparency = 0.7,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, f) :: UIStroke?
end
local function line_frame(parent: Instance?, z: number): Frame?
    return new("Frame", {
        Size = UDim2.new(0, 1, 0, 1),
        Position = UDim2.new(0, 0, 0, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = CFG.color_enemy,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = z,
        Visible = false,
    }, parent) :: Frame?
end
local function build_esp(): Esp
    local e: Esp = {
        bb = nil, fill = nil,
        glow1 = nil, glow2 = nil, glow3 = nil,
        box = nil, stroke = nil, stroke2 = nil, stroke3 = nil,
        corners = {}, corners3d = {},
        hp_bg = nil, hp_fill = nil, hp_stroke = nil,
        label = nil,
        parts = {}, head_dot = nil,
        skeleton = {},
        tracer = { line = nil, glow = nil },
        snapline = { line = nil, glow = nil },
        chams = nil,
    }
    e.bb = new("BillboardGui", {
        Name = "ZyonEsp",
        Size = UDim2.new(0, 100, 0, 140),
        AlwaysOnTop = true,
        LightInfluence = 0,
        MaxDistance = 3000,
        ResetOnSpawn = false,
        ClipsDescendants = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, sg) :: BillboardGui
    e.fill = new("Frame", {
        Name = "Fill",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = CFG.color_enemy,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        ZIndex = 1,
    }, e.bb) :: Frame
    new("UICorner", { CornerRadius = UDim.new(0, 3) }, e.fill)
    e.glow1 = glow_frame(e.bb, 0)
    e.glow2 = glow_frame(e.bb, 0)
    e.glow3 = glow_frame(e.bb, 0)
    e.box = new("Frame", {
        Name = "Box",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, e.bb) :: Frame
    e.stroke = new("UIStroke", {
        Name = "BoxStroke",
        Color = CFG.color_enemy,
        Thickness = CFG.stroke_thickness,
        Transparency = 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, e.box) :: UIStroke
    e.stroke2 = glow_stroke(e.box, 0)
    e.stroke3 = glow_stroke(e.box, 0)
    local k = 0
    while k < 4 do
        k = k + 1
        local c3 = new("Frame", {
            Name = "Box3D",
            Size = UDim2.new(0, 7, 0, 7),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = CFG.color_enemy,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 2,
            Visible = false,
        }, e.bb) :: Frame
        e.corners3d[k] = c3
    end
    local i = 0
    while i < 8 do
        i = i + 1
        local c = new("Frame", {
            Name = "Corner",
            Size = UDim2.new(0, 8, 0, 2),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = CFG.color_enemy,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            ZIndex = 6,
            Visible = false,
        }, e.bb) :: Frame
        e.corners[i] = c
    end
    e.hp_bg = new("Frame", {
        Name = "HpBg",
        Size = UDim2.new(0, 4, 1, 0),
        Position = UDim2.new(0, -7, 0, 0),
        BackgroundColor3 = Color3.fromRGB(15, 15, 15),
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, e.bb) :: Frame
    new("UICorner", { CornerRadius = UDim.new(0, 2) }, e.hp_bg)
    e.hp_stroke = new("UIStroke", {
        Name = "HpGlow",
        Color = Color3.fromRGB(0, 255, 80),
        Thickness = 2,
        Transparency = 0.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, e.hp_bg) :: UIStroke
    e.hp_fill = new("Frame", {
        Name = "HpFill",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(0, 255, 80),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, e.hp_bg) :: Frame
    new("UICorner", { CornerRadius = UDim.new(0, 2) }, e.hp_fill)
    e.head_dot = new("Frame", {
        Name = "HeadDot",
        Size = UDim2.new(0, 7, 0, 7),
        Position = UDim2.new(0.5, -3, 0, -10),
        BackgroundColor3 = CFG.color_enemy,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 7,
        Visible = false,
    }, e.bb) :: Frame
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, e.head_dot)
    new("UIStroke", {
        Name = "DotStroke",
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1,
        Transparency = 0.25,
    }, e.head_dot)
    local n = 0
    while n < 6 do
        n = n + 1
        local linha = new("TextLabel", {
            Name = "Info",
            Size = UDim2.new(1, 0, 0, 13),
            Position = UDim2.new(0, 0, 0, -16),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = CFG.label_size,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextStrokeTransparency = 0.6,
            TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
            Text = "",
            TextScaled = false,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 8,
            Visible = false,
        }, e.bb) :: TextLabel
        new("UIStroke", {
            Name = "TxtGlow",
            Color = CFG.color_glow,
            Thickness = 1.5,
            Transparency = 0.55,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
        }, linha)
        e.parts[n] = linha
    end
    e.tracer.line = line_frame(overlay, 210)
    e.tracer.glow = line_frame(overlay, 209)
    e.snapline.line = line_frame(overlay, 208)
    e.snapline.glow = line_frame(overlay, 207)
    local b = 0
    while b < #SKELETON_BONES do
        b = b + 1
        local par: Line2D = {
            line = line_frame(overlay, 205),
            glow = line_frame(overlay, 204),
        }
        e.skeleton[b] = par
    end
    return e
end
local function destroy_esp(e: Esp)
    if e.bb ~= nil then
        local ok, err = pcall(function()
            (e.bb :: BillboardGui):Destroy()
        end)
        if not ok then
            log("erro destruindo BillboardGui:", tostring(err))
        end
        e.bb = nil
    end
    if e.chams ~= nil then
        local okc, errc = pcall(function()
            (e.chams :: Highlight):Destroy()
        end)
        if not okc then
            log("erro destruindo Highlight:", tostring(errc))
        end
        e.chams = nil
    end
    local function drop(f: Frame?)
        if f == nil then
            return
        end
        release(line_owner, f)
        local ok, err = pcall(function()
            (f :: Frame):Destroy()
        end)
        if not ok then
            log("erro destruindo Frame de linha:", tostring(err))
        end
    end
    for _, par in ipairs(e.skeleton) do
        drop(par.line)
        drop(par.glow)
        par.line = nil
        par.glow = nil
    end
    drop(e.tracer.line)
    drop(e.tracer.glow)
    e.tracer.line = nil
    e.tracer.glow = nil
    drop(e.snapline.line)
    drop(e.snapline.glow)
    e.snapline.line = nil
    e.snapline.glow = nil
end
local State: {
    entries: { [Player]: Entry },
    running: boolean,
    frames: number,
    drawn: number,
} = {
    entries = {},
    running = true,
    frames = 0,
    drawn = 0,
}
local function is_enemy(plr: Player): boolean
    if plr == LocalPlayer then
        return false
    end
    if not CFG.team_check then
        return true
    end
    local a = LocalPlayer.Team
    local b = plr.Team
    if a ~= nil and b ~= nil and a == b then
        return false
    end
    return true
end
local function get_char(plr: Player): Model?
    local char = getp(plr, "Character")
    if char == nil or not (char :: any):IsA("Model") then
        return nil
    end
    return char :: Model
end
local function body_part(char: Model?, nome: string): BasePart?
    if char == nil then
        return nil
    end
    local nomeOk, peca = pcall(function()
        return (char :: Model):FindFirstChild(nome)
    end)
    if not nomeOk then
        log("FindFirstChild falhou em", nome, ":", tostring(peca))
        return nil
    end
    if peca ~= nil and (peca :: any):IsA("BasePart") then
        local okPos, pos = pcall(function()
            return (peca :: BasePart).Position
        end)
        if not okPos then
            log("Position falhou em", nome, ":", tostring(pos))
            return nil
        end
        return peca :: BasePart
    end
    return nil
end
local function color_for(plr: Player, hum: Humanoid?): Color3
    if hum ~= nil and (hum :: Humanoid).Health <= 0 then
        return CFG.color_dead
    end
    local meu = LocalPlayer.Team
    if meu ~= nil and plr.Team == meu then
        return CFG.color_team
    end
    return CFG.color_enemy
end
local function pixel_of(bb: BillboardGui?): Vector2
    local ok, p = pcall(function()
        return (bb :: BillboardGui).AbsoluteSize
    end)
    if not ok or p == nil then
        return Vector2.new(0, 0)
    end
    return p :: Vector2
end
local function put(inst: Frame?, pos: Vector2, size: Vector2, z: number, visivel: boolean)
    if inst == nil then
        return
    end
    setp(inst, "Position", UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y)))
    setp(inst, "Size", UDim2.fromOffset(math.max(1, math.floor(size.X)), math.max(1, math.floor(size.Y))))
    if z > 0 then
        setp(inst, "ZIndex", z)
    end
    setp(inst, "Visible", visivel)
end
local function put_line(inst: Frame?, ax: number, ay: number, bx: number, by: number,
                       espessura: number, z: number, cor: Color3, opac: number,
                       visivel: boolean): number
    if inst == nil then
        return 0
    end
    local dx = bx - ax
    local dy = by - ay
    local comprimento = math.sqrt(dx * dx + dy * dy)
    local angulo = math.deg(math.atan2(dy, dx))
    setp(inst, "AnchorPoint", Vector2.new(0, 0.5))
    setp(inst, "Position", UDim2.fromOffset(math.floor(ax), math.floor(ay)))
    setp(inst, "Size", UDim2.fromOffset(math.max(1, math.floor(comprimento)),
                                         math.max(1, math.floor(espessura))))
    setp(inst, "Rotation", angulo)
    setp(inst, "BackgroundColor3", cor)
    setp(inst, "BackgroundTransparency", opac)
    setp(inst, "ZIndex", z)
    setp(inst, "Visible", visivel)
    return comprimento
end
local function show_glow_layer(f: Frame?, bb: BillboardGui?, inflar: number,
                               borda: number, alpha: number, cor: Color3,
                               visivel: boolean)
    if f == nil then
        return
    end
    setp(f, "Position", UDim2.fromOffset(-inflar, -inflar))
    setp(f, "Size", UDim2.new(1, inflar * 2, 1, inflar * 2))
    setp(f, "BackgroundColor3", cor)
    setp(f, "BackgroundTransparency", 1)
    setp(f, "Visible", visivel)
    local s = f:FindFirstChildOfClass("UIStroke")
    if s ~= nil then
        setp(s, "Color", cor)
        setp(s, "Thickness", borda)
        setp(s, "Transparency", alpha)
        setp(s, "Enabled", visivel)
    end
end
local function alpha_of(forca: number, camada: number): number
    local base = 0.90 - 0.12 * (forca - 1)
    local a = base + 0.07 * (camada - 1)
    return math.clamp(a, 0.15, 1)
end
local function inflate_of(forca: number, camada: number): number
    local f = math.clamp(forca, 0.2, 4)
    return math.floor(1 + camada * f * 1.5)
end
local function thickness_of(forca: number, camada: number): number
    local f = math.clamp(forca, 0.2, 4)
    local t = 1 + camada * 2 * f
    return math.clamp(t, 1, 24)
end
local function units_of(studs: number): (number, string)
    local spm = CFG.studs_per_meter
    if type(spm) ~= "number" or spm <= 0 then
        log("studs_per_meter invalido, usando 3.571:", tostring(spm))
        spm = 3.571
    end
    return studs / spm, CFG.dist_unit
end
local function format_unidades(studs: number): string
    if not CFG.show_dist then
        return ""
    end
    local txt = ""
    if CFG.show_dist_studs then
        if CFG.show_dist_m then
            txt = txt .. " " .. tostring(math.floor(studs)) .. "s"
        else
            txt = txt .. " " .. tostring(math.floor(studs))
        end
    end
    if CFG.show_dist_m then
        local metros = units_of(studs)
        txt = txt .. " " .. string.format("%.1f", metros) .. CFG.dist_unit
    end
    return txt
end
local function arma_de(char: Model?): string
    if char == nil then
        return ""
    end
    local ok, tool = pcall(function()
        return (char :: Model):FindFirstChildOfClass("Tool")
    end)
    if not ok then
        log("FindFirstChildOfClass(Tool) falhou:", tostring(tool))
        return ""
    end
    if tool == nil then
        return ""
    end
    local nome = getp(tool, "Name")
    if type(nome) == "string" then
        return nome
    end
    return ""
end
local OCCL_CACHE: { [Player]: { t: number, ocl: boolean } } = {}
local function occluded(plr: Player, char: Model?): boolean
    local now = os.clock()
    local c = OCCL_CACHE[plr]
    if c ~= nil and now - c.t < 0.15 then
        return c.ocl
    end
    local cam = workspace.CurrentCamera
    if cam == nil or char == nil then
        OCCL_CACHE[plr] = { t = now, ocl = false }
        return false
    end
    local origem = cam.CFrame.Position
    local partes = {
        body_part(char, "Head"),
        body_part(char, "UpperTorso") or body_part(char, "Torso"),
        body_part(char, "HumanoidRootPart"),
    }
    local filtro: { Instance } = {}
    if LocalPlayer.Character ~= nil then
        filtro[#filtro + 1] = LocalPlayer.Character :: Instance
    end
    filtro[#filtro + 1] = char :: Instance
    local algum_livre = false
    for _, parte in ipairs(partes) do
        if parte ~= nil then
            local ok, hit = pcall(function()
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = filtro
                params.IgnoreWater = true
                return workspace:Raycast(origem, (parte :: BasePart).Position - origem, params)
            end)
            if ok and hit == nil then
                algum_livre = true
                break
            end
        end
    end
    local ocl = not algum_livre
    OCCL_CACHE[plr] = { t = now, ocl = ocl }
    return ocl
end
local function status_de(hum: Humanoid?, visivel: boolean, atras: boolean): string
    if hum ~= nil and (hum :: Humanoid).Health <= 0 then
        return "MORTO"
    end
    if atras then
        return "PAREDE"
    end
    if not visivel then
        return "FORA DE VISTA"
    end
    return "VISIVEL"
end
local function now_s(): number
    local ok, t = pcall(function()
        return os.clock()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return 0
end
local function compute_visible(char: Model?, plr: Player): boolean
    local cabeca = body_part(char, "Head")
    local cam = workspace.CurrentCamera
    if cabeca == nil or cam == nil then
        return true
    end
    local ok, sp, on = pcall(function()
        return (cam :: Camera):WorldToViewportPoint((cabeca :: BasePart).Position)
    end)
    if not ok then
        log("checagem de visibilidade falhou:", tostring(sp))
        return true
    end
    if sp == nil then
        return true
    end
    local v = sp :: Vector3
    if v.Z <= 0 then
        return false
    end
    return on == true
end
local function update_visibility(plr: Player, entry: Entry, char: Model?)
    local agora = now_s()
    if entry.visible == nil or (agora - entry.vis_t) >= 0.2 then
        entry.visible = compute_visible(char, plr)
        entry.vis_t = agora
    end
end
local function build_adv(plr: Player, char: Model?): Adv
    local adv = {
        has_ut = false, has_lt = false, has_torso = false,
    }
    if char == nil then
        return adv
    end
    adv.has_ut = body_part(char, "UpperTorso") ~= nil
    adv.has_lt = body_part(char, "LowerTorso") ~= nil
    adv.has_torso = body_part(char, "Torso") ~= nil
    adv_state[plr] = adv
    return adv
end
local function adv_of(plr: Player, char: Model?): Adv?
    local cache = adv_state[plr]
    if cache ~= nil then
        return cache
    end
    if char == nil then
        return nil
    end
    return build_adv(plr, char)
end
local function part_size_y(peca: BasePart): number
    local ok, s = pcall(function()
        return (peca :: BasePart).Size
    end)
    if not ok or s == nil then
        log("Size falhou na peca, usando 2:", tostring(s))
        return 2
    end
    return (s :: Vector3).Y
end
local function resolve_pos(char: Model?, adv: Adv?, nome: string): Vector3?
    if nome == "UpperTorso" and (adv == nil or not adv.has_ut) and adv ~= nil and adv.has_torso then
        local torso = body_part(char, "Torso")
        if torso ~= nil then
            local t = torso :: BasePart
            return t.Position + Vector3.new(0, part_size_y(t) * 0.5, 0)
        end
    end
    if nome == "LowerTorso" and (adv == nil or not adv.has_lt) and adv ~= nil and adv.has_torso then
        local torso = body_part(char, "Torso")
        if torso ~= nil then
            local t = torso :: BasePart
            return t.Position + Vector3.new(0, -part_size_y(t) * 0.5, 0)
        end
    end
    local peca = body_part(char, nome)
    if peca == nil and adv ~= nil and adv.has_torso then
        peca = body_part(char, "Torso")
    end
    if peca == nil then
        return nil
    end
    return (peca :: BasePart).Position
end
local function project(cam: Camera?, pos: Vector3): (Vector2?, boolean)
    if cam == nil then
        return nil, false
    end
    local ok, resultado, on = pcall(function()
        return (cam :: Camera):WorldToViewportPoint(pos)
    end)
    if not ok then
        log("WorldToViewportPoint falhou:", tostring(resultado))
        return nil, false
    end
    if resultado == nil then
        return nil, false
    end
    local v = resultado :: Vector3
    return Vector2.new(v.X, v.Y), on == true
end
local function draw_skeleton(plr: Player, entry: Entry, cam: Camera?, cor: Color3,
                             visivel: boolean)
    local e = entry.esp
    local char = get_char(plr)
    local adv = adv_of(plr, char)
    local pontos: { [string]: Vector2 } = {}
    local vis: { [string]: boolean } = {}
    for i, b in ipairs(SKELETON_BONES) do
        local nomeA = b[1]
        local nomeB = b[2]
        local a = pontos[nomeA]
        local bpos = pontos[nomeB]
        if a == nil then
            local posA = resolve_pos(char, adv, nomeA)
            if posA ~= nil then
                local sp_a, on_a = project(cam, posA)
                if sp_a ~= nil then
                    pontos[nomeA] = sp_a
                    vis[nomeA] = on_a
                    a = sp_a
                end
            end
        end
        if bpos == nil then
            local posB = resolve_pos(char, adv, nomeB)
            if posB ~= nil then
                local sp_b, on_b = project(cam, posB)
                if sp_b ~= nil then
                    pontos[nomeB] = sp_b
                    vis[nomeB] = on_b
                    bpos = sp_b
                end
            end
        end
        local par = e.skeleton[i]
        if par ~= nil then
            local desenha = visivel and a ~= nil and bpos ~= nil
            if a ~= nil and vis[nomeA] == false then
                desenha = false
            end
            if bpos ~= nil and vis[nomeB] == false then
                desenha = false
            end
            if desenha and a ~= nil and bpos ~= nil then
                local gl = claim(line_owner, par.glow, "skeleton_glow", overlay)
                put_line(gl, a.X, a.Y, bpos.X, bpos.Y,
                         CFG.skeleton_width + 3, 204, cor, 0.72, true)
                local li = claim(line_owner, par.line, "skeleton", overlay)
                put_line(li, a.X, a.Y, bpos.X, bpos.Y,
                         CFG.skeleton_width, 205, cor, 0.15, true)
            else
                if par.glow ~= nil then
                    setp(par.glow, "Visible", false)
                end
                if par.line ~= nil then
                    setp(par.line, "Visible", false)
                end
            end
        end
    end
end
local function box_variant(nome: string): string
    if nome == "Corner" then
        return "Corner"
    end
    if nome == "3D" then
        return "3D"
    end
    return "Normal"
end
local function draw_box(entry: Entry, cor: Color3, visivel: boolean, px: Vector2)
    local e = entry.esp
    local estilo = box_variant(CFG.box_style)
    if CFG.box_style ~= estilo then
        log("box_style desconhecido:", tostring(CFG.box_style), "-> usando Normal")
        CFG.box_style = estilo
    end
    local normal = estilo == "Normal"
    local corner = estilo == "Corner"
    local tresd = estilo == "3D"
    local box = e.box
    if box == nil then
        return
    end
    setp(box, "Visible", visivel)
    local forca = CFG.glow_intensity
    local glow_on = CFG.show_glow and CFG.glow and visivel
    local camadas = math.floor(tonumber(CFG.glow_layers) or 3)
    if camadas < 0 then
        camadas = 0
    end
    if camadas > 3 then
        camadas = 3
    end
    show_glow_layer(e.glow1, e.bb, inflate_of(forca, 1), thickness_of(forca, 3),
                    alpha_of(forca, 3), cor, glow_on and camadas >= 1)
    show_glow_layer(e.glow2, e.bb, inflate_of(forca, 2), thickness_of(forca, 2),
                    alpha_of(forca, 2), cor, glow_on and camadas >= 2)
    show_glow_layer(e.glow3, e.bb, inflate_of(forca, 3), thickness_of(forca, 1),
                    alpha_of(forca, 1), cor, glow_on and camadas >= 3)
    local s1 = e.stroke
    if s1 ~= nil then
        setp(s1, "Color", cor)
        setp(s1, "Thickness", CFG.stroke_thickness)
        setp(s1, "Enabled", visivel)
    end
    local s2 = e.stroke2
    if s2 ~= nil then
        setp(s2, "Color", cor)
        setp(s2, "Thickness", thickness_of(forca, 2))
        setp(s2, "Transparency", alpha_of(forca, 2))
        setp(s2, "Enabled", glow_on and camadas >= 2)
    end
    local s3 = e.stroke3
    if s3 ~= nil then
        setp(s3, "Color", cor)
        setp(s3, "Thickness", thickness_of(forca, 3))
        setp(s3, "Transparency", alpha_of(forca, 3))
        setp(s3, "Enabled", glow_on and camadas >= 3)
    end
    if s1 ~= nil then
        setp(s1, "Transparency", normal and 0 or 1)
    end
    local i = 0
    while i < 8 do
        i = i + 1
        local c = e.corners[i]
        if c ~= nil then
            setp(c, "BackgroundColor3", cor)
        end
    end
    local ativoCorner = corner and visivel
    local par = 0
    if ativoCorner then
        local L = math.floor(math.max(4, math.min(px.X, px.Y) * 0.18))
        local T = 3
        while par < 4 do
            par = par + 1
            local cima = par <= 2
            local esquerda = (par == 1 or par == 3)
            local x = esquerda and 0 or (px.X - L)
            local y = cima and 0 or (px.Y - T)
            put(e.corners[par], Vector2.new(x, y), Vector2.new(L, T), 6, true)
        end
        local base = 4
        local v = 0
        while v < 4 do
            v = v + 1
            local esq = (v == 1 or v == 3)
            local topo = v <= 2
            local x = esq and 0 or (px.X - T)
            local y = topo and 0 or (px.Y - L)
            put(e.corners[base + v], Vector2.new(x, y), Vector2.new(T, L), 6, true)
        end
    else
        while par < 8 do
            par = par + 1
            if e.corners[par] ~= nil then
                setp(e.corners[par], "Visible", false)
            end
        end
    end
    local off = 6
    local v3 = 0
    while v3 < 4 do
        v3 = v3 + 1
        local c3 = e.corners3d[v3]
        if c3 ~= nil then
            local cima = v3 <= 2
            local esquerda = (v3 == 1 or v3 == 3)
            local x = (esquerda and 0 or (px.X - 7)) + (tresd and off or 0)
            local y = (cima and 0 or (px.Y - 7)) + (tresd and off or 0)
            setp(c3, "BackgroundColor3", cor)
            put(c3, Vector2.new(x, y), Vector2.new(7, 7), 2, tresd and visivel or false)
        end
    end
end
local function update_label(entry: Entry, plr: Player, hum: Humanoid?, char: Model?,
                            dist: number, vel: number, visivel: boolean, cor: Color3)
    local e = entry.esp
    local linhas: { string } = {}
    if CFG.show_name then
        table.insert(linhas, plr.Name)
    end
    if CFG.show_health_num and hum ~= nil then
        local h = hum :: Humanoid
        table.insert(linhas, tostring(math.floor(h.Health)) .. "/" .. tostring(math.floor(h.MaxHealth)))
    end
    if CFG.show_armor and hum ~= nil then
        local armadura = getp(hum, "Armor")
        if type(armadura) == "number" then
            if CFG.show_health_num then
                local ultimo = linhas[#linhas]
                if ultimo ~= nil then
                    linhas[#linhas] = ultimo .. " | BLIND " .. tostring(math.floor(armadura))
                end
            else
                table.insert(linhas, "BLIND " .. tostring(math.floor(armadura)))
            end
        end
    end
    if CFG.show_tool then
        local arma = arma_de(char)
        if arma ~= "" then
            table.insert(linhas, "ARMA: " .. arma)
        end
    end
    if CFG.show_status then
        local atras = false
        if CFG.show_occlusion then
            atras = occluded(plr, char)
        end
        table.insert(linhas, status_de(hum, visivel, atras))
    end
    if CFG.show_speed then
        table.insert(linhas, "VEL " .. string.format("%.0f", vel) .. "s/s")
    end
    if CFG.show_dist and (CFG.show_dist_m or CFG.show_dist_studs) then
        local unidades = format_unidades(dist)
        if unidades ~= "" then
            table.insert(linhas, "DIST" .. unidades)
        end
    end
    local total = #linhas
    if total > #e.parts then
        total = #e.parts
    end
    local i = 0
    while i < #e.parts do
        i = i + 1
        local lbl = e.parts[i]
        if lbl ~= nil then
            setp(lbl, "TextSize", CFG.label_size)
            if i <= total then
                local txt = linhas[i]
                if txt == nil then
                    txt = ""
                end
                setp(lbl, "Text", txt)
                setp(lbl, "TextColor3", cor)
                setp(lbl, "Visible", true)
            else
                setp(lbl, "Visible", false)
            end
            local idx = i - 1
            setp(lbl, "Position", UDim2.new(0, 0, 0, -18 + idx * (CFG.label_size + 1)))
        end
    end
    return total
end
local function hide(e: Esp)
    local bb = e.bb :: BillboardGui?
    if bb ~= nil then
        setp(bb, "Enabled", false)
    end
    if e.chams ~= nil then
        setp(e.chams, "Enabled", false)
    end
    for _, par in ipairs(e.skeleton) do
        if par.line ~= nil then
            setp(par.line, "Visible", false)
        end
        if par.glow ~= nil then
            setp(par.glow, "Visible", false)
        end
    end
    if e.tracer.line ~= nil then
        setp(e.tracer.line, "Visible", false)
    end
    if e.tracer.glow ~= nil then
        setp(e.tracer.glow, "Visible", false)
    end
    if e.snapline.line ~= nil then
        setp(e.snapline.line, "Visible", false)
    end
    if e.snapline.glow ~= nil then
        setp(e.snapline.glow, "Visible", false)
    end
end
local function show(e: Esp)
    local bb = e.bb :: BillboardGui?
    if bb ~= nil then
        setp(bb, "Enabled", true)
    end
end
local function update_entry(plr: Player, entry: Entry, cam: Camera)
    local e = entry.esp
    if e.bb == nil then
        return
    end
    local camara = cam :: Camera
    local my_pos = camara.CFrame.Position
    local char = get_char(plr)
    local hum: Humanoid? = nil
    if char ~= nil then
        local okH, h = pcall(function()
            return (char :: Model):FindFirstChildOfClass("Humanoid")
        end)
        if not okH then
            log("FindFirstChildOfClass(Humanoid) falhou:", tostring(h))
            h = nil
        end
        if h ~= nil and (h :: any):IsA("Humanoid") then
            hum = h :: Humanoid
        end
    end
    local root: BasePart? = nil
    local hrp = body_part(char, HRP_NAME)
    if hrp ~= nil then
        root = hrp
    elseif char ~= nil then
        local okP, prim = pcall(function()
            return (char :: Model).PrimaryPart
        end)
        if okP and prim ~= nil and (prim :: any):IsA("BasePart") then
            root = prim :: BasePart
        end
    end
    if root == nil or hum == nil then
        hide(e)
        entry.adornee = nil
        return
    end
    local raiz = root :: BasePart
    local h = hum :: Humanoid
    if not is_enemy(plr) then
        hide(e)
        return
    end
    local dist = (my_pos - raiz.Position).Magnitude
    if dist > CFG.max_dist then
        hide(e)
        return
    end
    local agora = now_s()
    local vel = 0
    if entry.last_pos ~= nil and entry.speed_t > 0 then
        local dt = agora - entry.speed_t
        if dt > 0 and dt < 1 then
            vel = ((raiz.Position - entry.last_pos) :: Vector3).Magnitude / dt
        end
    end
    entry.last_pos = raiz.Position
    entry.speed_t = agora
    if vel > 0 then
        entry.speed = vel
    end
    adv_of(plr, char)
    update_visibility(plr, entry, char)
    local visivel = entry.visible
    if visivel == nil then
        visivel = true
    end
    if CFG.visible_only and not visivel then
        hide(e)
        return
    end
    local cor = color_for(plr, h)
    local bb = e.bb :: BillboardGui
    if entry.adornee ~= raiz then
        entry.adornee = raiz
        setp(bb, "Adornee", raiz)
    end
    local topo = body_part(char, "Head")
    if topo == nil then
        topo = raiz
    end
    local pe = body_part(char, "LeftFoot")
    if pe == nil then
        pe = body_part(char, "RightFoot")
    end
    local altura = 5
    if topo ~= nil and pe ~= nil then
        altura = math.abs((topo :: BasePart).Position.Y - (pe :: BasePart).Position.Y) + 1.2
    end
    local w = 60 * CFG.box_scale
    local hh = 110 * CFG.box_scale
    if altura > 1 then
        hh = altura * 22 * CFG.box_scale
        w = hh * 0.545
    end
    if hh > 300 then
        hh = 300
        w = hh * 0.545
    end
    setp(bb, "Size", UDim2.new(0, w, 0, hh))
    setp(bb, "MaxDistance", CFG.max_dist)
    local pixel = pixel_of(bb)
    if CFG.show_chams and e.chams ~= nil then
        setp(e.chams, "Adornee", char)
        setp(e.chams, "FillColor", cor)
        setp(e.chams, "OutlineColor", cor)
        setp(e.chams, "DepthMode", Enum.HighlightDepthMode.AlwaysOnTop)
        setp(e.chams, "Enabled", true)
    end
    draw_box(entry, cor, CFG.show_box, pixel)
    local fill = e.fill
    if fill ~= nil then
        setp(fill, "Visible", CFG.show_fill)
        setp(fill, "BackgroundColor3", cor)
        setp(fill, "BackgroundTransparency", CFG.fill_alpha)
    end
    if e.head_dot ~= nil then
        local d = CFG.head_dot_size
        setp(e.head_dot, "BackgroundColor3", CFG.head_dot_color)
        setp(e.head_dot, "Size", UDim2.new(0, d, 0, d))
        setp(e.head_dot, "Position", UDim2.new(0.5, -math.floor(d / 2), 0, -d - 4))
        setp(e.head_dot, "Visible", CFG.show_head_dot)
    end
    if CFG.show_health and CFG.show_health_bar then
        local pct = math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
        local bg = e.hp_bg :: Frame
        local preench = e.hp_fill :: Frame
        setp(bg, "Visible", true)
        setp(preench, "Visible", true)
        setp(preench, "Size", UDim2.new(1, 0, pct, 0))
        setp(preench, "Position", UDim2.new(0, 0, 1 - pct, 0))
        local corVida = Color3.fromRGB(255, 40, 40)
        if pct > 0.6 then
            corVida = Color3.fromRGB(0, 230, 90)
        elseif pct > 0.3 then
            corVida = Color3.fromRGB(255, 200, 0)
        end
        setp(preench, "BackgroundColor3", corVida)
        if e.hp_stroke ~= nil then
            setp(e.hp_stroke, "Color", corVida)
            setp(e.hp_stroke, "Enabled", CFG.show_glow)
        end
    else
        local hpbg = e.hp_bg :: Frame
        setp(hpbg, "Visible", false)
    end
    if CFG.show_name or CFG.show_dist or CFG.show_health_num or CFG.show_tool
        or CFG.show_status or CFG.show_speed or CFG.show_armor then
        update_label(entry, plr, h, char, dist, entry.speed, visivel, cor)
    else
        for _, lbl2 in ipairs(e.parts) do
            if lbl2 ~= nil then
                setp(lbl2, "Visible", false)
            end
        end
    end
    local centro = Vector2.new(camara.ViewportSize.X / 2, camara.ViewportSize.Y / 2)
    local sp_alvo = project(camara, raiz.Position)
    local tracer_ok = CFG.show_tracer and sp_alvo ~= nil
    if tracer_ok then
        local p = sp_alvo :: Vector2
        local tr = e.tracer
        local gl = claim(line_owner, tr.glow, "tracer_glow", overlay)
        put_line(gl, centro.X, centro.Y, p.X, p.Y, CFG.tracer_width + 3, 209,
                 cor, 0.8, true)
        local li = claim(line_owner, tr.line, "tracer", overlay)
        put_line(li, centro.X, centro.Y, p.X, p.Y, CFG.tracer_width, 210,
                 CFG.tracer_color, 0.25, true)
    else
        if e.tracer.line ~= nil then
            setp(e.tracer.line, "Visible", false)
        end
        if e.tracer.glow ~= nil then
            setp(e.tracer.glow, "Visible", false)
        end
    end
    local cima = body_part(char, "Head")
    if cima == nil then
        cima = raiz
    end
    local sp_topo = project(camara, (cima :: BasePart).Position)
    if CFG.show_snapline and sp_topo ~= nil then
        local st = sp_topo :: Vector2
        local gls = claim(line_owner, e.snapline.glow, "snapline_glow", overlay)
        put_line(gls, st.X, st.Y, st.X, st.Y - pixel.Y, CFG.snapline_width + 3,
                 207, cor, 0.8, true)
        local lis = claim(line_owner, e.snapline.line, "snapline", overlay)
        put_line(lis, st.X, st.Y, st.X, st.Y - pixel.Y, CFG.snapline_width,
                 208, CFG.snapline_color, 0.25, true)
    else
        if e.snapline.line ~= nil then
            setp(e.snapline.line, "Visible", false)
        end
        if e.snapline.glow ~= nil then
            setp(e.snapline.glow, "Visible", false)
        end
    end
    draw_skeleton(plr, entry, camara, CFG.color_skeleton, CFG.show_skeleton and visivel)
    show(e)
    State.drawn = State.drawn + 1
end
local function esp_update()
    local cam = workspace.CurrentCamera
    if cam == nil then
        return
    end
    for plr, entry in pairs(State.entries) do
        local ok, err = pcall(update_entry, plr, entry, cam)
        if not ok then
            log("erro atualizando", plr.Name, ":", tostring(err))
        end
    end
end
local function ensure_chams(plr: Player, entry: Entry)
    if not CFG.show_chams or entry.esp.chams ~= nil then
        return
    end
    local ch = new("Highlight", {
        Name = "ZyonChams",
        FillTransparency = 0.65,
        OutlineTransparency = 0.1,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = false,
    }, sg) :: Highlight
    local parent = getp(ch, "Parent")
    if parent == nil then
        log("Highlight ficou sem Parent — chams desligado para", plr.Name)
        return
    end
    entry.esp.chams = ch
end
local function add_player(plr: Player)
    if plr == LocalPlayer then
        return
    end
    if State.entries[plr] ~= nil then
        return
    end
    local entry: Entry = {
        esp = build_esp(),
        adornee = nil,
        last_pos = nil,
        speed = 0,
        speed_t = 0,
        visible = nil,
        vis_t = 0,
        adv = nil,
    }
    State.entries[plr] = entry
    ensure_chams(plr, entry)
    local ok = entry.esp.bb ~= nil and entry.esp.bb.Parent ~= nil
    log("ESP criado para", plr.Name, ok and "(ok)" or "(FALHOU)")
    hide(entry.esp)
end
local function remove_player(plr: Player)
    local entry = State.entries[plr]
    if entry == nil then
        return
    end
    destroy_esp(entry.esp)
    adv_state[plr] = nil
    State.entries[plr] = nil
end
for _, plr in ipairs(Players:GetPlayers()) do
    add_player(plr)
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.3)
        local e = State.entries[p]
        if e ~= nil then
            local char = get_char(p)
            local root = body_part(char, HRP_NAME)
            local bb = e.esp.bb :: BillboardGui?
            if root ~= nil and bb ~= nil then
                e.adornee = root
                setp(bb, "Adornee", root)
            end
            adv_state[p] = nil
        end
    end)
    task.wait(0.3)
    add_player(p)
end)
Players.PlayerRemoving:Connect(function(p)
    remove_player(p)
end)
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    for plr, entry in pairs(State.entries) do
        local char = get_char(plr)
        local root = body_part(char, HRP_NAME)
        local bb = entry.esp.bb :: BillboardGui?
        if root ~= nil and bb ~= nil then
            entry.adornee = root
            setp(bb, "Adornee", root)
        end
        adv_state[plr] = nil
    end
end)
function api_set_max(v: number?)
    if v == nil then
        v = CFG.max_dist
    end
    CFG.max_dist = math.floor(math.max(1, v))
    log("max_dist:", CFG.max_dist)
    return CFG.max_dist
end
UIS.InputBegan:Connect(function(input, processado)
    if processado then
        return
    end
    local tecla = input.KeyCode
    if tecla == Enum.KeyCode.RightBracket then
        api_set_max(CFG.max_dist + 100)
    elseif tecla == Enum.KeyCode.LeftBracket then
        api_set_max(CFG.max_dist - 100)
    end
end)
local reported = false
RunService.RenderStepped:Connect(function(dt)
    if not State.running or not CFG.enabled then
        return
    end
    local ok, err = pcall(esp_update)
    if not ok then
        log("erro no esp_update:", tostring(err))
    end
    State.frames = State.frames + 1
    if State.frames == 120 and not reported then
        reported = true
        local count = 0
        for _ in pairs(State.entries) do
            count = count + 1
        end
        log("--- relatorio apos 120 frames ---")
        log("jogadores monitorados:", count)
        log("atualizacoes de desenho:", State.drawn)
        if count == 0 then
            log("PROBLEMA: nenhum jogador monitorado")
        elseif State.drawn == 0 then
            log("PROBLEMA: ninguem passou nos filtros")
            log("  checando: time, distancia, humanoid vivo")
        else
            log("ESP ATIVO — caixas devem estar na tela")
        end
    end
end)
api_set_max = api_set_max
local api = {}
api.cfg = CFG
function api.set_box_style(estilo: string?)
    CFG.box_style = box_variant(estilo or "Normal")
    log("box_style:", CFG.box_style)
    return CFG.box_style
end
function api.set_glow(v: boolean?, forca: number?)
    CFG.show_glow = v ~= false
    if forca ~= nil then
        CFG.glow_intensity = math.clamp(forca, 0.2, 4)
    end
    log("glow:", tostring(CFG.show_glow), "intensidade:", CFG.glow_intensity)
    return CFG.show_glow
end
api.set_max_dist = function(v: number?)
    return api_set_max(v)
end
api.set = function(nome: any, valor: any)
    if type(nome) == "boolean" or nome == nil then
        local novo = nome and true or false
        if CFG.enabled == novo then
            return CFG.enabled
        end
        CFG.enabled = novo
        log("ESP:", CFG.enabled and "LIGADO" or "DESLIGADO")
        return CFG.enabled
    end
    if type(nome) ~= "string" then
        return false
    end
    local campo = nome
    local antes = CFG[campo]
    if antes == nil and campo:sub(1, 4) == "esp_" then
        campo = campo:sub(5)
        antes = CFG[campo]
    end
    if antes == nil then
        return false
    end
    local novo = valor
    if type(antes) == "boolean" then
        novo = valor and true or false
    elseif type(antes) == "number" then
        local n = tonumber(valor)
        if n == nil then
            return antes
        end
        novo = n
    end
    if antes == novo then
        return antes
    end
    CFG[campo] = novo
    log("opcao:", campo, "=", tostring(novo))
    return novo
end
api.hide_all = function()
    for plr, entry in pairs(State.entries) do
        local ok, err = pcall(hide, entry.esp)
        if not ok then
            log("erro escondendo", plr.Name, ":", tostring(err))
        end
    end
    log("todos escondidos")
end
api.status = function()
    local count = 0
    for _ in pairs(State.entries) do
        count = count + 1
    end
    local drawn = State.drawn
    log("status: jogadores=" .. count .. " atualizacoes=" .. drawn ..
        " ligado=" .. tostring(CFG.enabled))
    return {
        jogadores = count,
        atualizacoes = drawn,
        ligado = CFG.enabled,
        max_dist = CFG.max_dist,
        estilo = CFG.box_style,
    }
end
api.unload = function()
    State.running = false
    for plr, entry in pairs(State.entries) do
        destroy_esp(entry.esp)
        State.entries[plr] = nil
    end
    local ok, err = pcall(function()
        sg:Destroy()
    end)
    if not ok then
        log("erro destruindo ScreenGui:", tostring(err))
    end
    log("descarregado")
end
if getgenv ~= nil then
    local ok = pcall(function()
        getgenv().ZyonESP = api
        getgenv().ZyonESP_Unload = api.unload
        getgenv().ZyonESP_Set = api.set
        getgenv().ZyonESP_Status = api.status
    end)
    if not ok then
        log("ERRO ao publicar em getgenv: a api continua no retorno do script")
    end
end
log("=== PRONTO ===")
log("atalhos: [ e ] mudam o filtro de distancia; digite no campo dist max (estuds)")
return api
end)()
local ZYON_AIM = (function()
local identifyexecutor = rawget(getfenv(), "identifyexecutor")
local gethui          = rawget(getfenv(), "gethui")
local getgenv         = rawget(getfenv(), "getgenv")
local function log(...)
    local n = select("#", ...)
    local t = table.create(n)
    for i = 1, n do
        t[i] = tostring(select(i, ...))
    end
    print("[ZyonAim] " .. table.concat(t, " "))
end
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UserInput   = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if workspace.CurrentCamera == nil then
    repeat task.wait() until workspace.CurrentCamera ~= nil
end
local function cam(): Camera
    return workspace.CurrentCamera :: Camera
end
log("=== INICIO ===")
if identifyexecutor ~= nil then
    local ok, name = pcall(identifyexecutor)
    log("executor:", ok and tostring(name) or "?")
end
local CFG = {
    aim_enabled    = true,
    aim_mode       = "Hold",
    aim_key        = Enum.KeyCode.E,
    aim_toggle_key = Enum.KeyCode.T,
    panic_key      = Enum.KeyCode.P,
    profile        = "Cravado",
    aim_fov        = 220,
    aim_shape      = "Circle",
    aim_part       = "Head",
    aim_smooth     = 0.35,
    aim_max_step   = 6,
    aim_prediction = 0.12,
    aim_sticky     = true,
    aim_team_check = true,
    aim_max_dist   = 2000,
    aim_visible_only = false,
    snap_mode      = true,
    hitbox_expand  = true,
    silent_aim     = false,
    sticky_lock    = true,
    lock_switch_delay = 0.15,
    auto_fire      = false,
    auto_fire_range = 500,
    auto_fire_delay = 0.08,
    prefer_part    = "Head",
    bone_offset_y  = 0.0,
    fov_show       = true,
    fov_color      = Color3.fromRGB(0, 220, 255),
    fov_locked_color = Color3.fromRGB(0, 255, 160),
}
local PROFILES = {
    Suave = {
        aim_smooth     = 0.55,
        aim_max_step   = 5,
        aim_prediction = 0.10,
        snap_mode      = false,
        hitbox_expand  = false,
    },
    Equilibrado = {
        aim_smooth     = 0.30,
        aim_max_step   = 25,
        aim_prediction = 0.14,
        snap_mode      = true,
        hitbox_expand  = true,
    },
    Cravado = {
        aim_smooth     = 0.02,
        aim_max_step   = 360,
        aim_prediction = 0.18,
        snap_mode      = true,
        hitbox_expand  = true,
        aim_visible_only = false,
    },
    Rage = {
        aim_smooth     = 0.0,
        aim_max_step   = 360,
        aim_prediction = 0.20,
        snap_mode      = true,
        hitbox_expand  = true,
        aim_visible_only = false,
        aim_switch_delay = 0.0,
    },
}
local function apply_profile(name: string)
    local p = PROFILES[name]
    if p == nil then
        log("perfil desconhecido:", tostring(name))
        return false
    end
    for k, v in pairs(p) do
        CFG[k] = v
    end
    CFG.profile = name
    log("perfil aplicado:", name)
    return true
end
local function gui_parent(): Instance
    if gethui ~= nil then
        local ok, h = pcall(gethui)
        if ok and h ~= nil then
            return h :: Instance
        end
    end
    return game:GetService("CoreGui")
end
local sg = Instance.new("ScreenGui")
sg.Name = "ZyonAimFov"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
    local ok, err = pcall(function()
        sg.Parent = gui_parent()
    end)
    if not ok then
        log("ERRO ao criar ScreenGui:", tostring(err))
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg ~= nil then
            sg.Parent = pg
            log("ScreenGui em PlayerGui (fallback)")
        end
    end
end
log("ScreenGui:", sg.Parent ~= nil and tostring(sg.Parent) or "NIL")
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FovCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Visible = false
fovCircle.ZIndex = 10
fovCircle.Parent = sg
local circleStroke = Instance.new("UIStroke")
circleStroke.Name = "Stroke"
circleStroke.Thickness = 2
circleStroke.Transparency = 0.25
circleStroke.Color = CFG.fov_color
circleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
circleStroke.Parent = fovCircle
do
    local ok, corner = pcall(function()
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = fovCircle
        return c
    end)
    if not ok then
        log("UICorner falhou (o anel vai sair quadrado):", tostring(corner))
    end
end
local function set_circle_visible(v: boolean)
    fovCircle.Visible = v
end
local function update_circle(radius: number, locked: boolean)
    local d = math.max(4, radius * 2)
    fovCircle.Size = UDim2.new(0, d, 0, d)
    local target = locked and CFG.fov_locked_color or CFG.fov_color
    circleStroke.Color = target
    circleStroke.Thickness = locked and 3 or 2
    circleStroke.Transparency = locked and 0 or 0.25
    if CFG.aim_shape == "Square" then
        local ok = pcall(function()
            local uc = fovCircle:FindFirstChildOfClass("UICorner")
            if uc ~= nil then
                (uc :: UICorner).CornerRadius = UDim.new(0, 0)
            end
        end)
        if not ok then
            log("nao consegui trocar para quadrado")
        end
    else
        local ok = pcall(function()
            local uc = fovCircle:FindFirstChildOfClass("UICorner")
            if uc ~= nil then
                (uc :: UICorner).CornerRadius = UDim.new(0.5, 0)
            end
        end)
        if not ok then
            log("nao consegui trocar para circulo")
        end
    end
    set_circle_visible(true)
end
local function is_enemy(plr: Player): boolean
    if plr == LocalPlayer then
        return false
    end
    if not CFG.aim_team_check then
        return true
    end
    local a = LocalPlayer.Team
    local b = plr.Team
    if a ~= nil and b ~= nil and a == b then
        return false
    end
    return true
end
local function get_target_part(plr: Player): BasePart?
    local char = plr.Character
    if char == nil or char.Parent == nil then
        return nil
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum == nil or (hum :: Humanoid).Health <= 0 then
        return nil
    end
    local want = CFG.aim_part
    if want == "Head" then
        local h = char:FindFirstChild("Head")
        if h ~= nil and h:IsA("BasePart") then
            return h :: BasePart
        end
    end
    if want == "HumanoidRootPart" then
        local r = char:FindFirstChild("HumanoidRootPart")
        if r ~= nil and r:IsA("BasePart") then
            return r :: BasePart
        end
    end
    if want == "UpperTorso" or want == "Torso" then
        local t = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if t ~= nil and t:IsA("BasePart") then
            return t :: BasePart
        end
    end
    local r = char:FindFirstChild("HumanoidRootPart")
    if r ~= nil and r:IsA("BasePart") then
        return r :: BasePart
    end
    local h = char:FindFirstChild("Head")
    if h ~= nil and h:IsA("BasePart") then
        return h :: BasePart
    end
    return nil
end
local function is_visible(part: BasePart): boolean
    local c = cam()
    local _, on = c:WorldToViewportPoint(part.Position)
    if not on then
        return false
    end
    local origin = c.CFrame.Position
    local dir = part.Position - origin
    if dir.Magnitude < 1 then
        return true
    end
    local offsets = { 0, -1.6, -2.8 }
    for _, off in ipairs(offsets) do
        local target = part.Position + Vector3.new(0, off, 0)
        local d = target - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            LocalPlayer.Character or Instance.new("Folder"),
            part.Parent or Instance.new("Folder"),
        }
        local hit = workspace:Raycast(origin, d, params)
        if hit == nil then
            return true
        end
    end
    return false
end
local function w2s(pos: Vector3): (Vector2, boolean)
    local c = cam()
    local sp, on = c:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), on
end
local function aim_point(part: BasePart, cam_pos: Vector3): Vector3
    local p = part.Position
    local ok, size = pcall(function()
        return (part :: BasePart).Size
    end)
    if ok and size ~= nil then
    end
    p = p + Vector3.new(0, CFG.bone_offset_y, 0)
    if CFG.hitbox_expand then
        local to_cam = (cam_pos - p)
        if to_cam.Magnitude > 0.001 then
            p = p + to_cam.Unit * 0.35
        end
    end
    return p
end
local function fov_metric(sp: Vector2): number
    local vp = cam().ViewportSize
    local cx = vp.X / 2
    local cy = vp.Y / 2
    local dx = sp.X - cx
    local dy = sp.Y - cy
    if CFG.aim_shape == "Square" then
        return math.max(math.abs(dx), math.abs(dy))
    end
    return math.sqrt(dx * dx + dy * dy)
end
local State = {
    target = nil,
    part = nil,
    last_switch = 0,
    last_delta = 0,
    last_fire = 0,
    fired = 0,
}
local function collect(): ({ any }, BasePart?)
    local list = {}
    local held = nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and is_enemy(plr) then
            local part = get_target_part(plr)
            if part ~= nil then
                local char = plr.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local dist = 9999
                if root ~= nil and root:IsA("BasePart") then
                    dist = (cam().CFrame.Position - (root :: BasePart).Position).Magnitude
                end
                if dist <= CFG.aim_max_dist then
                    local sp, on = w2s((part :: BasePart).Position)
                    if on and fov_metric(sp) <= CFG.aim_fov then
                        local visible = true
                        if CFG.aim_visible_only then
                            visible = is_visible(part :: BasePart)
                        end
                        if visible then
                            list[#list + 1] = {
                                plr = plr,
                                part = part,
                                screen = sp,
                                dist = dist,
                            }
                            if plr == State.target then
                                held = part
                            end
                        end
                    end
                end
            end
        end
    end
    return list, held
end
local function find_target(): BasePart?
    local now = os.clock()
    local list, held = collect()
    if CFG.aim_sticky and held ~= nil then
        return held
    end
    if held == nil and State.target ~= nil then
        log("alvo", State.target.Name, "saiu do campo de visao — soltando")
        State.target = nil
        State.part = nil
    end
    if #list == 0 then
        return nil
    end
    if now - State.last_switch < CFG.lock_switch_delay and State.target ~= nil then
        for _, e in ipairs(list) do
            if e.plr == State.target then
                return e.part
            end
        end
    end
    local best = list[1]
    local best_score = -fov_metric(best.screen)
    for i = 2, #list do
        local s = -fov_metric(list[i].screen)
        if s > best_score then
            best = list[i]
            best_score = s
        end
    end
    if State.target ~= best.plr then
        log("novo alvo:", best.plr.Name, "dist", math.floor(best.dist))
    end
    State.last_switch = now
    State.target = best.plr
    return best.part
end
local latched = false
local FORCE_OFF = false
local function input_held(): boolean
    local ok, down = pcall(function()
        return UserInput:IsKeyDown(CFG.aim_key)
    end)
    return ok and down
end
local function should_aim(): boolean
    if not FORCE_OFF and not CFG.aim_enabled then
        return false
    end
    if FORCE_OFF or CFG.aim_mode == "Always" then
        return not FORCE_OFF
    end
    if CFG.aim_mode == "Toggle" then
        return latched
    end
    return input_held() or latched
end
local announced = false
local function apply_aim(dt: number)
    if not should_aim() then
        State.target = nil
        State.part = nil
        set_circle_visible(false)
        return
    end
    local part = find_target()
    State.part = part
    if CFG.fov_show then
        update_circle(CFG.aim_fov, part ~= nil)
    else
        set_circle_visible(false)
    end
    if part == nil then
        return
    end
    if not announced then
        announced = true
        log(">>> TRAVADO em", State.target and State.target.Name or "?", "<<<")
    end
    local c = cam()
    local cam_pos = c.CFrame.Position
    local target_pos = aim_point(part :: BasePart, cam_pos)
    if CFG.aim_prediction > 0 then
        local bp = part :: BasePart
        local okVel, vel = pcall(function()
            return bp.AssemblyLinearVelocity
        end)
        if okVel and vel ~= nil then
            target_pos = target_pos + vel * CFG.aim_prediction
            if math.abs(vel.Y) > 20 then
                local t = CFG.aim_prediction
                target_pos = target_pos + Vector3.new(0, -4.9 * t * t, 0)
            end
        end
    end
    local delta = target_pos - cam_pos
    if delta.Magnitude < 0.05 then
        return
    end
    local desired = CFrame.lookAt(cam_pos, target_pos, Vector3.new(0, 1, 0))
    if CFG.snap_mode or CFG.aim_smooth <= 0.001 then
        c.CFrame = desired
        State.last_delta = 0
        return
    end
    local raw = math.clamp(1 - CFG.aim_smooth, 0, 1)
    local frame_scale = math.clamp(dt * 60, 0, 2)
    local alpha = math.clamp(raw * frame_scale, 0, 1)
    local blended = c.CFrame:Lerp(desired, alpha)
    if CFG.aim_max_step < 359 then
        local dot = math.clamp(c.CFrame.LookVector:Dot(blended.LookVector), -1, 1)
        local angle = math.deg(math.acos(dot))
        local max_step = CFG.aim_max_step * frame_scale
        if angle > max_step and angle > 0.001 then
            blended = c.CFrame:Lerp(blended, max_step / angle)
        end
    end
    c.CFrame = blended
end
local function auto_fire(part: BasePart?)
    if not CFG.auto_fire or part == nil then
        return
    end
    local c = cam()
    local cam_pos = c.CFrame.Position
    local target_pos = (part :: BasePart).Position
    local dist = (target_pos - cam_pos).Magnitude
    if dist > CFG.auto_fire_range then
        return
    end
    local to_target = (target_pos - cam_pos).Unit
    local dot = math.clamp(c.CFrame.LookVector:Dot(to_target), -1, 1)
    local angle = math.deg(math.acos(dot))
    if angle > 8 then
        return
    end
    local now = os.clock()
    if now - State.last_fire < CFG.auto_fire_delay then
        return
    end
    State.last_fire = now
    State.fired = State.fired + 1
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local vp = c.ViewportSize
        local x = vp.X / 2
        local y = vp.Y / 2
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    if not ok then
        log("auto disparo falhou:", tostring(err))
    end
end
UserInput.InputBegan:Connect(function(input: InputObject, gp: boolean)
    if gp then
        return
    end
    if input.KeyCode == CFG.aim_toggle_key then
        latched = not latched
        log("toggle:", latched and "LIGADO" or "DESLIGADO",
            "| modo:", CFG.aim_mode)
        if latched and not CFG.aim_enabled then
            CFG.aim_enabled = true
            log("mira estava desligada — liguei pelo T")
        end
    end
    if input.KeyCode == CFG.panic_key then
        FORCE_OFF = not FORCE_OFF
        if FORCE_OFF then
            CFG.aim_enabled = false
            latched = false
            State.target = nil
            State.part = nil
            set_circle_visible(false)
            log("PANICO: mira travada desligada (P para voltar)")
        else
            log("PANICO liberado")
        end
    end
end)
RunService:UnbindFromRenderStep("ZyonAim")
RunService:BindToRenderStep("ZyonAim", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local ok, err = pcall(apply_aim, dt)
    if not ok then
        log("erro no aimbot:", tostring(err))
    end
    if CFG.auto_fire and should_aim() then
        local okFire, errFire = pcall(auto_fire, State.part)
        if not okFire then
            log("erro no auto disparo:", tostring(errFire))
        end
    end
end)
log("teclas: E = mirar (segurar) | T = travar/alternar | P = panico")
local api = {}
local function unload()
    pcall(function()
        RunService:UnbindFromRenderStep("ZyonAim")
    end)
    pcall(function()
        sg:Destroy()
    end)
    log("descarregado")
end
api.unload = unload
api.set = function(nome: any, valor: any)
    if type(nome) == "boolean" or nome == nil then
        local novo = nome and true or false
        if CFG.aim_enabled == novo then
            return CFG.aim_enabled
        end
        CFG.aim_enabled = novo
        log("mira:", CFG.aim_enabled and "LIGADA" or "DESLIGADA")
        return CFG.aim_enabled
    end
    if type(nome) ~= "string" then
        return false
    end
    local campo = nome
    local antes = CFG[campo]
    if antes == nil and campo:sub(1, 4) == "aim_" then
        campo = campo:sub(5)
        antes = CFG[campo]
    end
    local APELIDO = {
        snap = "snap_mode",
    }
    if antes == nil and APELIDO[campo] ~= nil then
        campo = APELIDO[campo]
        antes = CFG[campo]
    end
    if antes == nil then
        return false
    end
    local novo = valor
    if type(antes) == "boolean" then
        novo = valor and true or false
    elseif type(antes) == "number" then
        local n = tonumber(valor)
        if n == nil then
            return antes
        end
        novo = n
    end
    if antes == novo then
        return antes
    end
    CFG[campo] = novo
    log("opcao mira:", campo, "=", tostring(novo))
    return novo
end
api.mode = function(m: string)
    CFG.aim_mode = m
    log("modo:", tostring(m))
end
api.fov = function(r: number)
    CFG.aim_fov = r
    log("FOV:", r)
end
api.smooth = function(s: number)
    CFG.aim_smooth = s
    log("suavizacao:", s)
end
api.part = function(p: string)
    CFG.aim_part = p
    log("parte do corpo:", p)
end
api.profile = function(n: string)
    return apply_profile(n)
end
api.autofire = function(v: boolean, range: number?)
    CFG.auto_fire = v and true or false
    if range ~= nil then
        CFG.auto_fire_range = range
    end
    log("auto disparo:", CFG.auto_fire and "LIGADO" or "DESLIGADO",
        "| alcance:", CFG.auto_fire_range)
end
api.status = function()
    local t = {
        ligada = CFG.aim_enabled,
        modo = CFG.aim_mode,
        perfil = CFG.profile,
        travado_em = State.target and State.target.Name or "ninguem",
        fov = CFG.aim_fov,
        suavizacao = CFG.aim_smooth,
        snap = CFG.snap_mode,
        auto_fire = CFG.auto_fire,
        disparos = State.fired,
        panic = FORCE_OFF,
    }
    log("status: ligada=" .. tostring(t.ligada) ..
        " perfil=" .. tostring(t.perfil) ..
        " travado_em=" .. t.travado_em ..
        " disparos=" .. tostring(t.disparos))
    return t
end
if getgenv ~= nil then
    local ok = pcall(function()
        getgenv().ZyonAim = api
        getgenv().ZyonAim_Unload = unload
        getgenv().ZyonAim_Set = api.set
        getgenv().ZyonAim_SetMode = api.mode
        getgenv().ZyonAim_Status = api.status
    end)
    if ok then
        log("controle tambem disponivel em getgenv().ZyonAim")
    end
end
log("=== PRONTO ===")
apply_profile(CFG.profile)
log("MIRA JA ESTA LIGADA e cravada (perfil " .. tostring(CFG.profile) .. ").")
log("  E = mirar (segurar)  |  T = travar/alternar  |  P = panico")
log("FOV:", CFG.aim_fov, "| suavizacao:", CFG.aim_smooth,
    "| snap:", tostring(CFG.snap_mode), "| auto disparo:", tostring(CFG.auto_fire))
log("troque de perfil com: z.profile('Rage')")
return api
end)()
local ZYON_MOV = (function()
local identifyexecutor = rawget(getfenv(), "identifyexecutor")
local gethui          = rawget(getfenv(), "gethui")
local getgenv         = rawget(getfenv(), "getgenv")
local function log(...)
    local n = select("#", ...)
    local t = table.create(n)
    for i = 1, n do
        t[i] = tostring(select(i, ...))
    end
    print("[ZyonMove] " .. table.concat(t, " "))
end
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UserInput   = game:GetService("UserInputService")
local Lighting    = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local ZYON_MERGED = true
log("=== INICIO ===")
if identifyexecutor ~= nil then
    local ok, name = pcall(identifyexecutor)
    log("executor:", ok and tostring(name) or "?")
end
local CFG = {
    speed      = { on = false, value = 28, default = 16 },
    jump       = { on = false, value = 70, default = 50 },
    infjump    = { on = false },
    fly        = { on = false, value = 60 },
    noclip     = { on = false },
    hipheight  = { on = false, value = 2.5, default = 2 },
    fullbright = { on = false },
    clocktime  = { on = false, value = 14 },
    fog        = { on = false },
    antifling  = { on = false },
    autoreload = { on = false },
    invisible  = { on = false },
}
local conns = {}
local function track(c: RBXScriptConnection?)
    if c ~= nil then
        conns[#conns + 1] = c
    end
    return c
end
local function untrack_all()
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    conns = {}
end
local State = {
    fly_bv = nil,
    fly_bg = nil,
    saved = {},
    running = true,
}
local function char(): (Model?, Humanoid?, BasePart?, BasePart?)
    local c = LocalPlayer.Character
    if c == nil or c.Parent == nil then
        return nil, nil, nil, nil
    end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    local head = c:FindFirstChild("Head")
    local r = nil
    if root ~= nil and root:IsA("BasePart") then
        r = root :: BasePart
    end
    local h = nil
    if head ~= nil and head:IsA("BasePart") then
        h = head :: BasePart
    end
    return c, hum, r, h
end
local function apply_speed()
    local _, hum = char()
    if hum == nil then
        return
    end
    pcall(function()
        (hum :: Humanoid).WalkSpeed = CFG.speed.on and CFG.speed.value or CFG.speed.default
    end)
end
local function apply_jump()
    local _, hum = char()
    if hum == nil then
        return
    end
    pcall(function()
        (hum :: Humanoid).UseJumpPower = true
        ;(hum :: Humanoid).JumpPower = CFG.jump.on and CFG.jump.value or CFG.jump.default
    end)
end
track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if CFG.speed.on then apply_speed() end
    if CFG.jump.on then apply_jump() end
    if CFG.hipheight.on then
        local _, hum = char()
        if hum ~= nil then
            pcall(function()
                (hum :: Humanoid).HipHeight = CFG.hipheight.value
            end)
        end
    end
end))
track(RunService.Stepped:Connect(function()
    if not State.running or not CFG.infjump.on then
        return
    end
    local _, hum, root = char()
    if hum == nil or root == nil then
        return
    end
    local h = hum :: Humanoid
    local r = root :: BasePart
    if h:GetState() ~= Enum.HumanoidStateType.Jumping then
        local ok, down = pcall(function()
            return UserInput:IsKeyDown(Enum.KeyCode.Space)
        end)
        if ok and down then
            pcall(function()
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end
end))
local function aplicar_noclip()
    local c = LocalPlayer.Character
    if c == nil then
        return 0
    end
    local n = 0
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            local ok = pcall(function()
                part.CanCollide = false
            end)
            if ok then
                n = n + 1
            end
        end
    end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum ~= nil then
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
        end)
    end
    return n
end
track(RunService.RenderStepped:Connect(function()
    if not State.running or not CFG.noclip.on then
        return
    end
    local ok, err = pcall(aplicar_noclip)
    if not ok then
        log("erro no noclip:", tostring(err))
    end
end))
track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    if CFG.noclip.on then
        pcall(aplicar_noclip)
    end
end))
local function stop_fly()
    local bv = State.fly_bv
    local bg = State.fly_bg
    if bv ~= nil then
        pcall(function()
            (bv :: BodyVelocity):Destroy()
        end)
    end
    if bg ~= nil then
        pcall(function()
            (bg :: BodyGyro):Destroy()
        end)
    end
    State.fly_bv = nil
    State.fly_bg = nil
end
local function start_fly()
    local _, _, root = char()
    if root == nil then
        return
    end
    stop_fly()
    local r = root :: BasePart
    local bv = Instance.new("BodyVelocity")
    bv.Name = "ZyonFly"
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity = Vector3.zero
    bv.Parent = r
    local bg = Instance.new("BodyGyro")
    bg.Name = "ZyonFlyGyro"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.P = 1000
    bg.CFrame = r.CFrame
    bg.Parent = r
    State.fly_bv = bv
    State.fly_bg = bg
end
track(RunService.Stepped:Connect(function()
    local r = State.fly_bv
    if not State.running or not CFG.fly.on or r == nil then
        return
    end
    local _, _, root = char()
    if root == nil then
        return
    end
    local cam = workspace.CurrentCamera
    if cam == nil then
        return
    end
    local move = Vector3.zero
    local ok, human = pcall(function()
        return (LocalPlayer.Character :: Model):FindFirstChildOfClass("Humanoid")
    end)
    if ok and human ~= nil then
        local dir = (human :: Humanoid).MoveDirection
        if dir.Magnitude > 0.01 then
            move = dir.Unit * CFG.fly.value
        end
    end
    local up = 0
    local okUp, upDown = pcall(function()
        return UserInput:IsKeyDown(Enum.KeyCode.Space)
    end)
    if okUp and upDown then
        up = CFG.fly.value
    end
    local okDn, downDown = pcall(function()
        return UserInput:IsKeyDown(Enum.KeyCode.LeftControl)
    end)
    if okDn and downDown then
        up = -CFG.fly.value
    end
    pcall(function()
        (r :: BodyVelocity).Velocity = move + Vector3.new(0, up, 0)
    end)
    pcall(function()
        if State.fly_bg ~= nil then
            (State.fly_bg :: BodyGyro).CFrame = cam.CFrame
        end
    end)
end))
local function apply_lighting()
    if CFG.fullbright.on then
        if State.saved.brightness == nil then
            State.saved.brightness = Lighting.Brightness
            State.saved.ambient = Lighting.Ambient
            State.saved.outdoor = Lighting.OutdoorAmbient
        end
        pcall(function()
            Lighting.Brightness = 3
            Lighting.Ambient = Color3.fromRGB(180, 180, 180)
            Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
            Lighting.GlobalShadows = false
        end)
    else
        pcall(function()
            if State.saved.brightness ~= nil then
                Lighting.Brightness = State.saved.brightness
                Lighting.Ambient = State.saved.ambient
                Lighting.OutdoorAmbient = State.saved.outdoor
                Lighting.GlobalShadows = true
            end
        end)
    end
    if CFG.clocktime.on then
        if State.saved.clocktime == nil then
            State.saved.clocktime = Lighting.ClockTime
        end
        pcall(function()
            Lighting.ClockTime = CFG.clocktime.value
        end)
    elseif State.saved.clocktime ~= nil then
        pcall(function()
            Lighting.ClockTime = State.saved.clocktime
        end)
    end
    if CFG.fog.on then
        if State.saved.fogend == nil then
            State.saved.fogend = Lighting.FogEnd
            State.saved.fogstart = Lighting.FogStart
        end
        pcall(function()
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
        end)
    elseif State.saved.fogend ~= nil then
        pcall(function()
            Lighting.FogEnd = State.saved.fogend
            Lighting.FogStart = State.saved.fogstart
        end)
    end
end
track(RunService.Heartbeat:Connect(function()
    if not State.running then
        return
    end
    if CFG.antifling.on then
        local _, hum, root = char()
        if hum ~= nil and root ~= nil then
            local ok, vel = pcall(function()
                return (root :: BasePart).AssemblyLinearVelocity
            end)
            if ok and vel ~= nil and vel.Magnitude > 300 then
                pcall(function()
                    (root :: BasePart).AssemblyLinearVelocity = vel.Unit * 100
                end)
            end
        end
    end
    if CFG.autoreload.on then
        local c = LocalPlayer.Character
        if c ~= nil then
            for _, tool in ipairs(c:GetChildren()) do
                if tool:IsA("Tool") then
                    pcall(function()
                        (tool :: Tool):Activate()
                    end)
                end
            end
        end
    end
end))
local function apply_invisible()
    local c = LocalPlayer.Character
    if c == nil then
        return
    end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                (part :: BasePart).LocalTransparencyModifier = CFG.invisible.on and 1 or 0
            end)
        end
        if part:IsA("Decal") then
            pcall(function()
                (part :: Decal).Transparency = CFG.invisible.on and 1 or 0
            end)
        end
    end
end
track(RunService.Stepped:Connect(function()
    if State.running and CFG.invisible.on then
        apply_invisible()
    end
end))
local function set_flag(name: string, on: boolean, value: number?): boolean
    local entry = CFG[name]
    if entry == nil then
        log("modulo desconhecido:", tostring(name))
        return false
    end
    local novo = on and true or false
    local mudou = (entry.on ~= novo) or (value ~= nil and entry.value ~= value)
    entry.on = novo
    if value ~= nil then
        entry.value = value
    end
    if name == "speed" then
        apply_speed()
    elseif name == "jump" then
        apply_jump()
    elseif name == "fly" then
        if entry.on then
            start_fly()
            if mudou then
                log("voo ligado — WASD move, espaço sobe, ctrl desce")
            end
        else
            stop_fly()
        end
    elseif name == "hipheight" then
        local _, hum = char()
        if hum ~= nil then
            pcall(function()
                (hum :: Humanoid).HipHeight = entry.on and entry.value or entry.default
            end)
        end
    elseif name == "fullbright" or name == "clocktime" or name == "fog" then
        apply_lighting()
    end
    if mudou then
        log(name .. ":", entry.on and "LIGADO" or "DESLIGADO",
            entry.value ~= nil and ("valor=" .. tostring(entry.value)) or "")
    end
    return true
end
local api = {}
api.set = function(name: string, value: any)
    if type(value) == "boolean" then
        return set_flag(name, value)
    end
    return set_flag(name, true, value)
end
api.on = function(name: string)
    return set_flag(name, true)
end
api.off = function(name: string)
    return set_flag(name, false)
end
api.toggle = function(name: string)
    local entry = CFG[name]
    if entry == nil then
        log("modulo desconhecido:", tostring(name))
        return false
    end
    return set_flag(name, not entry.on)
end
api.speed = function(v: number)
    return set_flag("speed", true, v)
end
api.fly = function(v: number?)
    return set_flag("fly", true, v)
end
api.status = function()
    local t = {}
    local on = {}
    for name, entry in pairs(CFG) do
        t[name] = entry.on
        if entry.on then
            on[#on + 1] = name
        end
    end
    if #on == 0 then
        log("status: nada ligado")
    else
        log("status:", table.concat(on, ", "))
    end
    return t
end
api.panic = function()
    for name, entry in pairs(CFG) do
        if type(entry) == "table" then
            entry.on = false
        end
    end
    stop_fly()
    apply_speed()
    apply_jump()
    apply_lighting()
    apply_invisible()
    local _, hum = char()
    if hum ~= nil then
        pcall(function()
            (hum :: Humanoid).HipHeight = CFG.hipheight.default
        end)
    end
    log("PANICO: tudo desligado (o script continua ativo)")
end
api.cfg = CFG
api.unload = function()
    State.running = false
    untrack_all()
    stop_fly()
    for name, _ in pairs(CFG) do
        local entry = CFG[name]
        if type(entry) == "table" then
            entry.on = false
        end
    end
    apply_speed()
    apply_jump()
    apply_lighting()
    apply_invisible()
    log("descarregado")
end
track(UserInput.InputBegan:Connect(function(input: InputObject, gp: boolean)
    if gp then
        return
    end
    if input.KeyCode == Enum.KeyCode.P and not ZYON_MERGED then
        api.panic()
    end
end))
if getgenv ~= nil then
    local ok = pcall(function()
        getgenv().ZyonMove = api
        getgenv().ZyonMoveUnload = api.unload
    end)
    if ok then
        log("controle tambem em getgenv().ZyonMove")
    end
end
log("=== PRONTO ===")
log("exemplos: z.speed(30)  z.fly()  z.toggle('noclip')  z.panic()")
log("teclas: P = panico | RightShift = esconde o painel")
return api
end)()
local identifyexecutor = rawget(getfenv(), "identifyexecutor")
local gethui          = rawget(getfenv(), "gethui")
local getgenv         = rawget(getfenv(), "getgenv")
local writefile       = rawget(getfenv(), "writefile")
local getcustomasset  = rawget(getfenv(), "getcustomasset")
local function log(...)
    local n = select("#", ...)
    local t = table.create(n)
    for i = 1, n do
        t[i] = tostring(select(i, ...))
    end
    print("[Zyon] " .. table.concat(t, " "))
end
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UserInput   = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
log("=== INICIO ===")
if identifyexecutor ~= nil then
    local ok, name = pcall(identifyexecutor)
    log("executor:", ok and tostring(name) or "?")
end
log("Drawing:", tostring(rawget(getfenv(), "Drawing") ~= nil),
    "(nao usamos)")
local IS_MOBILE = UserInput.TouchEnabled and not UserInput.KeyboardEnabled
log("mobile:", tostring(IS_MOBILE))
local BG_B64 = table.concat({
    "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",
}, "")
local BG_IMAGE, BG_READY = nil, false
do
    if writefile ~= nil and getcustomasset ~= nil then
        local ok, err = pcall(function()
            local nome = "zyon_bg.png"
            local tem_isfile = rawget(getfenv(), "isfile")
            local existe = false
            if tem_isfile ~= nil then
                local okCheck, r = pcall(tem_isfile, nome)
                existe = okCheck and r == true
            end
            if not existe then
                writefile(nome, BG_B64)
            end
            BG_IMAGE = getcustomasset(nome)
            BG_READY = true
        end)
        if not ok then
            log("foto indisponivel:", tostring(err))
        end
    else
        log("sem writefile/getcustomasset - usando gradiente")
    end
end
local T = {
    bg        = Color3.fromRGB(14, 15, 20),
    panel     = Color3.fromRGB(20, 22, 30),
    row       = Color3.fromRGB(30, 33, 44),
    accent    = Color3.fromRGB(0, 220, 255),
    accent2   = Color3.fromRGB(255, 60, 140),
    on        = Color3.fromRGB(0, 235, 150),
    off       = Color3.fromRGB(70, 76, 92),
    text      = Color3.fromRGB(238, 241, 248),
    dim       = Color3.fromRGB(150, 158, 176),
    radius    = 12,
}
local FONT = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold
local CFG = {
    esp_enabled     = true,
    esp_box         = true,
    esp_fill        = true,
    esp_glow        = true,
    esp_name        = true,
    esp_dist        = true,
    esp_health      = true,
    esp_tracer      = true,
    esp_snapline    = true,
    esp_head_dot    = true,
    esp_skeleton    = false,
    esp_chams       = true,
    esp_team_check  = true,
    esp_max_dist    = 3000,
    aim_enabled     = true,
    aim_mode        = "Hold",
    aim_fov         = 220,
    aim_smooth      = 0.02,
    aim_snap        = true,
    aim_auto_fire   = false,
    aim_visible_only = false,
    aim_team_check  = true,
    mov_speed       = false,
    mov_speed_value = 28,
    mov_jump        = false,
    mov_infjump     = false,
    mov_fly         = false,
    mov_noclip      = false,
    mov_fullbright  = false,
    mov_fog         = false,
    mov_invisible   = false,
    ui_photo_fade   = 0.30,
}
local function apply_photo(panel: ImageLabel?, on: boolean)
    if panel == nil then
        return
    end
    local ok = pcall(function()
        (panel :: ImageLabel).ImageTransparency = on and CFG.ui_photo_fade or 1
    end)
    if not ok then
        log("nao consegui ajustar a foto")
    end
end
local parent = nil
if gethui ~= nil then
    local ok, h = pcall(gethui)
    if ok and h ~= nil then
        parent = h
    end
end
if parent == nil then
    parent = game:GetService("CoreGui")
end
local function mk(className: string, props: { [string]: any }, kids: { Instance }?): Instance
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        pcall(function()
            (inst :: any)[k] = v
        end)
    end
    if kids ~= nil then
        for _, kid in ipairs(kids) do
            kid.Parent = inst
        end
    end
    return inst
end
local function corner(r: number): UICorner
    return mk("UICorner", { CornerRadius = UDim.new(0, r) }) :: UICorner
end
local SG = mk("ScreenGui", {
    Name = "ZyonMenu",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})
local okParent = pcall(function()
    SG.Parent = parent
end)
if not okParent then
    log("FALHA ao criar a GUI - abortando")
    return nil
end
log("GUI criada em:", tostring(parent))
local SIDEBAR_W = 118
local W, H = 600, 360
if IS_MOBILE then
    SIDEBAR_W = 92
    W, H = 400, 280
end
local win = mk("Frame", {
    Name = "Janela",
    Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    BackgroundColor3 = T.bg,
    BackgroundTransparency = 0.06,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, {
    corner(T.radius),
}) :: Frame
win.Parent = SG
local winStroke = mk("UIStroke", {
    Color = T.accent,
    Thickness = 1.6,
    Transparency = 0.25,
}) :: UIStroke
winStroke.Parent = win
local headerH = 40
local photo = mk("ImageLabel", {
    Name = "FotoFundo",
    Position = UDim2.new(0, SIDEBAR_W, 0, headerH),
    Size = UDim2.new(1, -SIDEBAR_W, 1, -headerH - 24),
    BackgroundTransparency = 1,
    ImageTransparency = 1,
    ScaleType = Enum.ScaleType.Crop,
    ClipsDescendants = true,
}) :: ImageLabel
photo.Parent = win
local photoVeil = mk("Frame", {
    Position = UDim2.new(0, SIDEBAR_W, 0, headerH),
    Size = UDim2.new(1, -SIDEBAR_W, 1, -headerH - 24),
    BackgroundColor3 = Color3.fromRGB(8, 9, 13),
    BackgroundTransparency = 0.42,
    BorderSizePixel = 0,
}) :: Frame
photoVeil.Parent = win
if BG_READY and BG_IMAGE ~= nil then
    local okImg = pcall(function()
        photo.Image = BG_IMAGE
    end)
    if okImg then
        apply_photo(photo, true)
        log("foto aplicada na area de opcoes")
    end
else
    log("foto nao aplicada - gradiente no lugar")
end
local grad = mk("UIGradient", {
    Rotation = 90,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 0.75),
    }),
}) :: UIGradient
grad.Parent = photoVeil
local header = mk("Frame", {
    Name = "Cabecalho",
    Size = UDim2.new(1, 0, 0, headerH),
    BackgroundColor3 = T.panel,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
}) :: Frame
header.Parent = win
local hGrad = mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.accent),
        ColorSequenceKeypoint.new(1, T.accent2),
    }),
    Rotation = 0,
}) :: UIGradient
hGrad.Parent = header
local title = mk("TextLabel", {
    Name = "Titulo",
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Font = FONT_B,
    TextSize = IS_MOBILE and 14 or 16,
    TextColor3 = T.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "ZYON MENU",
}) :: TextLabel
title.Parent = header
local sub = mk("TextLabel", {
    Size = UDim2.new(0, 70, 1, 0),
    Position = UDim2.new(1, -84, 0, 0),
    BackgroundTransparency = 1,
    Font = FONT,
    TextSize = 10,
    TextColor3 = T.text,
    TextTransparency = 0.25,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = IS_MOBILE and "MOBILE" or "PC",
}) :: TextLabel
sub.Parent = header
local closeBtn = mk("TextButton", {
    Name = "Fechar",
    Size = UDim2.fromOffset(22, 22),
    Position = UDim2.new(1, -30, 0, 8),
    BackgroundColor3 = Color3.fromRGB(60, 24, 34),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = FONT_B,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 130, 130),
    Text = "X",
}, {
    corner(6),
}) :: TextButton
closeBtn.Parent = header
local function animate(inst: Instance, props: { [string]: any }, tempo: number?)
    local ok, err = pcall(function()
        TweenService:Create(
            inst,
            TweenInfo.new(tempo or 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            props
        ):Play()
    end)
    if not ok then
        log("tween falhou:", tostring(err))
        for k, v in pairs(props) do
            pcall(function()
                (inst :: any)[k] = v
            end)
        end
    end
end
local TABS = {
    { id = "ESP",    nome = "VISUAL",   icone = "[+]" },
    { id = "AIMBOT", nome = "MIRA",     icone = "(o)" },
    { id = "MOV",    nome = "MOV",      icone = ">>" },
}
local sidebar = mk("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = T.panel,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
}) :: Frame
sidebar.Parent = win
local sidebarEdge = mk("Frame", {
    Name = "Divisoria",
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(0, SIDEBAR_W, 0, 0),
    BackgroundColor3 = T.accent,
    BackgroundTransparency = 0.6,
    BorderSizePixel = 0,
}) :: Frame
sidebarEdge.Parent = win
local marca = mk("TextLabel", {
    Name = "Marca",
    Size = UDim2.new(1, 0, 0, headerH),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    Font = FONT_B,
    TextSize = IS_MOBILE and 12 or 14,
    TextColor3 = T.accent,
    Text = "ZYON",
}) :: TextLabel
marca.Parent = sidebar
local marcaGrad = mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.accent),
        ColorSequenceKeypoint.new(1, T.accent2),
    }),
    Rotation = 15,
}) :: UIGradient
marcaGrad.Parent = marca
local navList = mk("Frame", {
    Name = "Navegacao",
    Size = UDim2.new(1, -16, 1, -headerH - 44),
    Position = UDim2.new(0, 8, 0, headerH + 6),
    BackgroundTransparency = 1,
}) :: Frame
navList.Parent = sidebar
local navLayout = mk("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}) :: UIListLayout
navLayout.Parent = navList
local pagesHost = mk("Frame", {
    Name = "Paginas",
    Size = UDim2.new(1, -SIDEBAR_W - 16, 1, -headerH - 40),
    Position = UDim2.new(0, SIDEBAR_W + 8, 0, headerH + 8),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}) :: Frame
pagesHost.Parent = win
local pages: { [string]: Frame } = {}
local tabBars: { [string]: Frame } = {}
local activeTab = "ESP"
local select_tab = nil
for i, t in ipairs(TABS) do
    local item = mk("Frame", {
        Name = "Item_" .. t.id,
        Size = UDim2.new(1, 0, 0, IS_MOBILE and 34 or 40),
        BackgroundColor3 = T.row,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = i,
    }, {
        corner(8),
    }) :: Frame
    item.Parent = navList
    local bar = mk("Frame", {
        Name = "Barra",
        Size = UDim2.new(0, 3, 0, 0),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
    }, {
        corner(2),
    }) :: Frame
    bar.Parent = item
    tabBars[t.id] = bar
    local icone = mk("TextLabel", {
        Name = "Icone",
        Size = UDim2.fromOffset(26, 18),
        Position = UDim2.new(0, 8, 0.5, -9),
        BackgroundTransparency = 1,
        Font = FONT_B,
        TextSize = 11,
        TextColor3 = T.dim,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = t.icone,
    }) :: TextLabel
    icone.Parent = item
    local texto = mk("TextLabel", {
        Name = "Texto",
        Size = UDim2.new(1, -42, 1, 0),
        Position = UDim2.new(0, 38, 0, 0),
        BackgroundTransparency = 1,
        Font = FONT_B,
        TextSize = IS_MOBILE and 10 or 11,
        TextColor3 = T.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = t.nome,
    }) :: TextLabel
    texto.Parent = item
    local btn = mk("TextButton", {
        Name = "Botao",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }) :: TextButton
    btn.Parent = item
    item:SetAttribute("Ativo", false)
    btn.MouseButton1Click:Connect(function()
        select_tab(t.id)
    end)
    item.MouseEnter:Connect(function()
        if item:GetAttribute("Ativo") ~= true then
            animate(item, { BackgroundTransparency = 0.65 }, 0.12)
            animate(icone, { TextColor3 = T.text }, 0.12)
        end
    end)
    item.MouseLeave:Connect(function()
        if item:GetAttribute("Ativo") ~= true then
            animate(item, { BackgroundTransparency = 1 }, 0.12)
            animate(icone, { TextColor3 = T.dim }, 0.12)
        end
    end)
    item:SetAttribute("idx", i)
    local page = mk("ScrollingFrame", {
        Name = "Pagina_" .. t.id,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }) :: ScrollingFrame
    page.Parent = pagesHost
    local lay = mk("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }) :: UIListLayout
    lay.Parent = page
    pages[t.id] = page
end
select_tab = function(nome: string)
    activeTab = nome
    for _, t in ipairs(TABS) do
        local n = t.id
        local on = (n == nome)
        local page = pages[n]
        if page ~= nil then
            page.Visible = on
        end
        local item = navList:FindFirstChild("Item_" .. n)
        if item ~= nil then
            item:SetAttribute("Ativo", on)
            animate(item, {
                BackgroundColor3 = on and T.accent or T.row,
                BackgroundTransparency = on and 0.82 or 1,
            }, 0.16)
            local ic = item:FindFirstChild("Icone")
            if ic ~= nil then
                animate(ic, { TextColor3 = on and T.accent or T.dim }, 0.16)
            end
            local tx = item:FindFirstChild("Texto")
            if tx ~= nil then
                animate(tx, {
                    TextColor3 = on and T.text or T.dim,
                }, 0.16)
            end
        end
        local bar = tabBars[n]
        if bar ~= nil then
            local altura = item ~= nil and item.AbsoluteSize.Y or 30
            animate(bar, {
                Size = on and UDim2.new(0, 3, 0, altura - 14) or UDim2.new(0, 3, 0, 0),
                BackgroundColor3 = on and T.accent or T.dim,
            }, 0.18)
        end
    end
    local p = pages[nome]
    if p ~= nil then
        p.Position = UDim2.new(0, 14, 0, 0)
        p.BackgroundTransparency = 1
        animate(p, { Position = UDim2.new(0, 0, 0, 0) }, 0.22)
    end
end
local ROW_H = 30
local function make_row(pagina: string, texto: string, ordem: number): (Frame, TextLabel, Frame)
    local row = mk("Frame", {
        Name = texto,
        Size = UDim2.new(1, -6, 0, ROW_H),
        BackgroundColor3 = T.row,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        LayoutOrder = ordem,
    }, {
        corner(8),
    }) :: Frame
    row.Parent = pages[pagina]
    local stroke = mk("UIStroke", {
        Color = T.accent,
        Thickness = 1,
        Transparency = 1,
    }) :: UIStroke
    stroke.Parent = row
    local label = mk("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        TextSize = IS_MOBILE and 11 or 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = texto,
    }) :: TextLabel
    label.Parent = row
    row.MouseEnter:Connect(function()
        animate(row, { BackgroundTransparency = 0.25 }, 0.12)
        animate(stroke, { Transparency = 0.45 }, 0.12)
    end)
    row.MouseLeave:Connect(function()
        animate(row, { BackgroundTransparency = 0.45 }, 0.12)
        animate(stroke, { Transparency = 1 }, 0.12)
    end)
    return row, label, stroke
end
local toggles: { [string]: { chave: string, knobs: { Frame } } } = {}
local function make_toggle(pagina: string, ordem: number, texto: string,
                           chave: string, padrao: boolean)
    local row = make_row(pagina, texto, ordem)
    local swW = 40
    local sw = mk("Frame", {
        Name = "Switch",
        Size = UDim2.fromOffset(swW, 18),
        Position = UDim2.new(1, -(swW + 10), 0.5, -9),
        BackgroundColor3 = padrao and T.on or T.off,
        BorderSizePixel = 0,
    }, {
        corner(9),
    }) :: Frame
    sw.Parent = row
    local knob = mk("Frame", {
        Name = "Knob",
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, padrao and (swW - 16) or 2, 0.5, -7),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    }, {
        corner(7),
    }) :: Frame
    knob.Parent = sw
    local btn = mk("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }) :: TextButton
    btn.Parent = row
    local entrada = { chave = chave, knobs = { knob } }
    toggles[chave] = entrada
    local function pinta(on: boolean)
        animate(sw, { BackgroundColor3 = on and T.on or T.off }, 0.18)
        animate(knob, { Position = UDim2.new(0, on and (swW - 16) or 2, 0.5, -7) }, 0.18)
    end
    btn.MouseButton1Click:Connect(function()
        CFG[chave] = not CFG[chave]
        local on = CFG[chave] and true or false
        pinta(on)
        log("toggle:", chave, on and "LIGADO" or "DESLIGADO")
    end)
    return row
end
local function make_slider(pagina: string, ordem: number, texto: string,
                           chave: string, minimo: number, maximo: number, passo: number)
    local row = make_row(pagina, texto, ordem)
    local label = row:FindFirstChildOfClass("TextLabel")
    local barW = 120
    if IS_MOBILE then
        barW = 90
    end
    local track = mk("Frame", {
        Name = "Trilha",
        Size = UDim2.fromOffset(barW, 5),
        Position = UDim2.new(1, -(barW + 12), 0.5, -2.5),
        BackgroundColor3 = Color3.fromRGB(48, 52, 66),
        BorderSizePixel = 0,
    }, {
        corner(3),
    }) :: Frame
    track.Parent = row
    local fill = mk("Frame", {
        Name = "Preenchimento",
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
    }, {
        corner(3),
    }) :: Frame
    fill.Parent = track
    local knob = mk("Frame", {
        Name = "Knob",
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    }, {
        corner(6),
    }) :: Frame
    knob.Parent = track
    local atual = CFG[chave] or minimo
    if type(atual) ~= "number" then
        atual = minimo
    end
    local function mostra(v: number)
        local frac = (v - minimo) / (maximo - minimo)
        frac = math.clamp(frac, 0, 1)
        fill.Size = UDim2.new(frac, 0, 1, 0)
        knob.Position = UDim2.new(frac, 0, 0.5, 0)
        if label ~= nil then
            label.Text = texto .. "  [" .. tostring(v) .. "]"
        end
    end
    mostra(atual)
    local dragging = false
    local function de_x(px: number)
        local rel = math.clamp(px / barW, 0, 1)
        local v = minimo + rel * (maximo - minimo)
        v = math.floor(v / passo + 0.5) * passo
        v = math.clamp(v, minimo, maximo)
        local casas = 0
        local p = passo
        while p < 1 and casas < 4 do
            p = p * 10
            casas = casas + 1
        end
        if casas > 0 then
            local mult = 10 ^ casas
            v = math.floor(v * mult + 0.5) / mult
        end
        return v
    end
    local function aplica(px: number)
        local v = de_x(px)
        CFG[chave] = v
        mostra(v)
    end
    local hit = mk("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }) :: TextButton
    hit.Parent = row
    hit.MouseButton1Down:Connect(function()
        dragging = true
    end)
    UserInput.InputChanged:Connect(function(input: InputObject)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            local rel = track.AbsolutePosition
            aplica(pos.X - rel.X)
        end
    end)
    UserInput.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                log("slider:", chave, "=", tostring(CFG[chave]))
            end
        end
    end)
    track.InputBegan:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            aplica(input.Position.X - track.AbsolutePosition.X)
        end
    end)
    return row
end
local o = 0
o = o + 1; make_toggle("ESP", o, "ESP ligado",        "esp_enabled",    true)
o = o + 1; make_toggle("ESP", o, "Caixa",             "esp_box",        true)
o = o + 1; make_toggle("ESP", o, "Brilho (glow)",     "esp_glow",       true)
o = o + 1; make_toggle("ESP", o, "Nome",              "esp_name",       true)
o = o + 1; make_toggle("ESP", o, "Distancia",         "esp_dist",       true)
o = o + 1; make_toggle("ESP", o, "Vida (barra)",      "esp_health",     true)
o = o + 1; make_toggle("ESP", o, "Chams (Highlight)", "esp_chams",      true)
o = o + 1; make_toggle("ESP", o, "Ignorar time",      "esp_team_check", true)
o = o + 1; make_slider("ESP", o, "Dist. maxima (estuds)", "esp_max_dist", 200, 6000, 100)
o = o + 1; make_toggle("ESP", o, "Esqueleto (linhas)", "esp_skeleton",  false)
o = o + 1; make_toggle("ESP", o, "Snapline",          "esp_snapline",   false)
o = o + 1; make_toggle("ESP", o, "Tracer",            "esp_tracer",     false)
o = o + 1; make_toggle("ESP", o, "Ponto na cabeca",   "esp_head_dot",   false)
o = o + 1; make_toggle("ESP", o, "Preenchimento",     "esp_fill",       false)
o = o + 1; make_toggle("ESP", o, "Vida (numero)",     "esp_health_num", false)
o = o + 1; make_toggle("ESP", o, "Distancia em metros", "esp_dist_m",   false)
o = o + 1; make_toggle("ESP", o, "Armadura",          "esp_armor",      false)
o = o + 1; make_toggle("ESP", o, "Arma na mao",       "esp_tool",       false)
o = o + 1; make_toggle("ESP", o, "Velocidade",        "esp_speed",      false)
o = o + 1; make_toggle("ESP", o, "Status (PAREDE)",   "esp_status",     false)
o = 0
o = o + 1; make_toggle("AIMBOT", o, "Aimbot ligado",   "aim_enabled",     true)
o = o + 1; make_toggle("AIMBOT", o, "Mira cravada",    "aim_snap",        true)
o = o + 1; make_toggle("AIMBOT", o, "Auto disparo",    "aim_auto_fire",   false)
o = o + 1; make_toggle("AIMBOT", o, "So na visao",     "aim_visible_only", false)
o = o + 1; make_toggle("AIMBOT", o, "Ignorar time",    "aim_team_check",  true)
o = o + 1; make_slider("AIMBOT", o, "FOV",             "aim_fov",         30, 600, 10)
o = o + 1; make_slider("AIMBOT", o, "Suavizacao",      "aim_smooth",      0, 1, 0.05)
o = 0
o = o + 1; make_toggle("MOV", o, "Correr mais rapido", "mov_speed",      false)
o = o + 1; make_slider("MOV", o, "Velocidade",         "mov_speed_value", 16, 80, 2)
o = o + 1; make_toggle("MOV", o, "Pulo forte",         "mov_jump",       false)
o = o + 1; make_toggle("MOV", o, "Pulo infinito",      "mov_infjump",    false)
o = o + 1; make_toggle("MOV", o, "Voar",               "mov_fly",        false)
o = o + 1; make_toggle("MOV", o, "Atravessar parede",  "mov_noclip",     false)
o = o + 1; make_toggle("MOV", o, "Visao total",        "mov_fullbright", false)
o = o + 1; make_toggle("MOV", o, "Sem nevoa",          "mov_fog",        false)
o = o + 1; make_toggle("MOV", o, "Invisivel",          "mov_invisible",  false)
local ESP_API, AIM_API, MOV_API = ZYON_ESP, ZYON_AIM, ZYON_MOV
local function push()
    if ESP_API ~= nil and ESP_API.set ~= nil then
        pcall(ESP_API.set, "enabled", CFG.esp_enabled)
        pcall(ESP_API.set, "show_box", CFG.esp_box)
        pcall(ESP_API.set, "show_fill", CFG.esp_fill)
        pcall(ESP_API.set, "show_glow", CFG.esp_glow)
        pcall(ESP_API.set, "show_name", CFG.esp_name)
        pcall(ESP_API.set, "show_dist", CFG.esp_dist)
        pcall(ESP_API.set, "show_health", CFG.esp_health)
        pcall(ESP_API.set, "show_tracer", CFG.esp_tracer)
        pcall(ESP_API.set, "show_snapline", CFG.esp_snapline)
        pcall(ESP_API.set, "show_head_dot", CFG.esp_head_dot)
        pcall(ESP_API.set, "show_skeleton", CFG.esp_skeleton)
        pcall(ESP_API.set, "show_chams", CFG.esp_chams)
        pcall(ESP_API.set, "team_check", CFG.esp_team_check)
        pcall(ESP_API.set, "max_dist", CFG.esp_max_dist)
        pcall(ESP_API.set, "show_health_num", CFG.esp_health_num)
        pcall(ESP_API.set, "show_dist_m", CFG.esp_dist_m)
        pcall(ESP_API.set, "show_dist_studs", CFG.esp_dist)
        pcall(ESP_API.set, "show_armor", CFG.esp_armor)
        pcall(ESP_API.set, "show_tool", CFG.esp_tool)
        pcall(ESP_API.set, "show_speed", CFG.esp_speed)
        pcall(ESP_API.set, "show_status", CFG.esp_status)
        pcall(ESP_API.set, "show_occlusion", CFG.esp_status)
    end
    if AIM_API ~= nil then
        if AIM_API.set ~= nil then
            pcall(AIM_API.set, CFG.aim_enabled)
            pcall(AIM_API.set, "snap_mode", CFG.aim_snap)
            pcall(AIM_API.set, "auto_fire", CFG.aim_auto_fire)
            pcall(AIM_API.set, "visible_only", CFG.aim_visible_only)
            pcall(AIM_API.set, "team_check", CFG.aim_team_check)
            pcall(AIM_API.set, "fov", CFG.aim_fov)
            pcall(AIM_API.set, "smooth", CFG.aim_smooth)
        end
        if AIM_API.cfg ~= nil then
            pcall(function()
                AIM_API.cfg.aim_snap = CFG.aim_snap
                AIM_API.cfg.snap_mode = CFG.aim_snap
                AIM_API.cfg.aim_auto_fire = CFG.aim_auto_fire
                AIM_API.cfg.auto_fire = CFG.aim_auto_fire
                AIM_API.cfg.aim_visible_only = CFG.aim_visible_only
                AIM_API.cfg.aim_team_check = CFG.aim_team_check
                AIM_API.cfg.aim_fov = CFG.aim_fov
                AIM_API.cfg.aim_smooth = CFG.aim_smooth
            end)
        end
    end
    if MOV_API ~= nil and MOV_API.set ~= nil then
        pcall(MOV_API.set, "speed", CFG.mov_speed, CFG.mov_speed_value)
        pcall(MOV_API.set, "jump", CFG.mov_jump)
        pcall(MOV_API.set, "infjump", CFG.mov_infjump)
        pcall(MOV_API.set, "fly", CFG.mov_fly)
        pcall(MOV_API.set, "noclip", CFG.mov_noclip)
        pcall(MOV_API.set, "fullbright", CFG.mov_fullbright)
        pcall(MOV_API.set, "fog", CFG.mov_fog)
        pcall(MOV_API.set, "invisible", CFG.mov_invisible)
    end
end
task.spawn(function()
    while SG.Parent ~= nil do
        local ok, err = pcall(push)
        if not ok then
            log("erro ao aplicar config:", tostring(err))
        end
        task.wait(0.25)
    end
end)
local aberto = false
local function abrir()
    if aberto then
        return
    end
    aberto = true
    win.Visible = true
    win.Size = UDim2.fromOffset(W, H - 30)
    win.BackgroundTransparency = 0.5
    animate(win, {
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = 0.06,
    }, 0.24)
    if BG_READY then
        photo.ImageTransparency = 1
        animate(photo, { ImageTransparency = CFG.ui_photo_fade }, 0.4)
    end
    log("menu aberto")
end
local function fechar()
    if not aberto then
        return
    end
    aberto = false
    animate(win, {
        Size = UDim2.fromOffset(W, H - 30),
        BackgroundTransparency = 0.6,
    }, 0.18)
    task.wait(0.18)
    win.Visible = false
    log("menu fechado")
end
closeBtn.MouseButton1Click:Connect(fechar)
do
    local arrastando = false
    local inicio = Vector2.zero
    local pos0 = UDim2.new(0, 0, 0, 0)
    local function comeca(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            arrastando = true
            inicio = Vector2.new(input.Position.X, input.Position.Y)
            pos0 = win.Position
        end
    end
    local function move(input: InputObject)
        if not arrastando then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = Vector2.new(input.Position.X, input.Position.Y) - inicio
            win.Position = UDim2.new(
                pos0.X.Scale, pos0.X.Offset + d.X,
                pos0.Y.Scale, pos0.Y.Offset + d.Y
            )
        end
    end
    local function solta(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            arrastando = false
        end
    end
    header.InputBegan:Connect(comeca)
    header.InputChanged:Connect(move)
    UserInput.InputChanged:Connect(move)
    UserInput.InputEnded:Connect(solta)
end
local fab = mk("TextButton", {
    Name = "BotaoZyon",
    Size = UDim2.fromOffset(IS_MOBILE and 54 or 46, IS_MOBILE and 54 or 46),
    Position = UDim2.new(0, 14, 0.5, -23),
    BackgroundColor3 = T.bg,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = FONT_B,
    TextSize = IS_MOBILE and 13 or 12,
    TextColor3 = T.accent,
    Text = "ZYON",
    Visible = true,
}, {
    corner(IS_MOBILE and 27 or 23),
}) :: TextButton
fab.Parent = SG
local fabStroke = mk("UIStroke", {
    Color = T.accent,
    Thickness = 1.8,
    Transparency = 0.15,
}) :: UIStroke
fabStroke.Parent = fab
local fabGrad = mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.accent),
        ColorSequenceKeypoint.new(1, T.accent2),
    }),
    Rotation = 45,
}) :: UIGradient
fabGrad.Parent = fabStroke
task.spawn(function()
    local falhou = false
    while fab.Parent ~= nil do
        local ok, err = pcall(function()
            TweenService:Create(fab,
                TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { BackgroundTransparency = 0.35 }):Play()
        end)
        if not ok then
            if not falhou then
                falhou = true
                log("animacao do botao falhou:", tostring(err))
            end
            return
        end
        task.wait(1.1)
        local ok2, err2 = pcall(function()
            TweenService:Create(fab,
                TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { BackgroundTransparency = 0.1 }):Play()
        end)
        if not ok2 then
            if not falhou then
                falhou = true
                log("animacao do botao falhou:", tostring(err2))
            end
            return
        end
        task.wait(1.1)
    end
end)
fab.MouseButton1Click:Connect(function()
    if aberto then
        fechar()
    else
        abrir()
    end
end)
UserInput.InputBegan:Connect(function(input: InputObject, gp: boolean)
    if gp then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if aberto then
            fechar()
        else
            abrir()
        end
    end
    if input.KeyCode == Enum.KeyCode.P then
        if ESP_API ~= nil and ESP_API.set ~= nil then
            pcall(ESP_API.set, "enabled", false)
        end
        if AIM_API ~= nil and AIM_API.set ~= nil then
            pcall(AIM_API.set, false)
        end
        if MOV_API ~= nil and MOV_API.panic ~= nil then
            pcall(MOV_API.panic)
        end
        log("PANICO: tudo desligado")
    end
end)
local api = {}
api.esp = ZYON_ESP
api.aim = ZYON_AIM
api.mov = ZYON_MOV
api.cfg = CFG
api.gui = SG
api.open = abrir
api.close = fechar
api.toggle = function()
    if aberto then
        fechar()
    else
        abrir()
    end
end
api.status = function()
    local on = {}
    for k, v in pairs(CFG) do
        if v == true then
            on[#on + 1] = k
        end
    end
    log("opcoes ligadas:", table.concat(on, ", "))
    log("mira travada em:",
        (ZYON_AIM ~= nil and ZYON_AIM.status ~= nil)
            and (function()
                local ok, t = pcall(ZYON_AIM.status)
                if ok and type(t) == "table" then
                    return tostring(t.travado_em)
                end
                return "?"
            end)() or "?")
    return CFG
end
api.panic = function()
    if ZYON_ESP ~= nil and ZYON_ESP.set ~= nil then
        pcall(ZYON_ESP.set, "enabled", false)
    end
    if ZYON_AIM ~= nil and ZYON_AIM.set ~= nil then
        pcall(ZYON_AIM.set, false)
    end
    if ZYON_MOV ~= nil and ZYON_MOV.panic ~= nil then
        pcall(ZYON_MOV.panic)
    end
    log("PANICO total")
end
api.unload = function()
    if ZYON_ESP ~= nil and ZYON_ESP.unload ~= nil then
        pcall(ZYON_ESP.unload)
    end
    if ZYON_AIM ~= nil and ZYON_AIM.unload ~= nil then
        pcall(ZYON_AIM.unload)
    end
    if ZYON_MOV ~= nil and ZYON_MOV.unload ~= nil then
        pcall(ZYON_MOV.unload)
    end
    pcall(function()
        SG:Destroy()
    end)
    log("tudo descarregado")
end
if getgenv ~= nil then
    local ok = pcall(function()
        getgenv().Zyon = api
    end)
    if ok then
        log("controle tambem em getgenv().Zyon")
    end
end
log("=== PRONTO ===")
log("RightShift = menu | E = mirar | T = travar | P = panico")
log("botao ZYON na tela abre o menu (bom no celular)")
select_tab("ESP")
if IS_MOBILE then
    abrir()
end
return api
