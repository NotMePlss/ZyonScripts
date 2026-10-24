-- language: Luau, file: LF.luau, target: The Lost Front (72299838142412)
-- One file. ESP + aimbot + menu. Load with live-reload, label "lf".
--
-- Design rules learned the hard way in this session:
--   1. Every stage prints, so a failure names itself instead of "nothing showed".
--   2. No enum is ever indexed by name outside a pcall. Enum.TeamColor does not
--      exist in this executor and that single line killed the whole ESP.
--   3. One player's error cannot stop the frame. Each is drawn under its own pcall.
--   4. CurrentCamera is read every frame; caching it kills the ESP on respawn.
--   5. The game's camera module writes Camera.CFrame from BindToRenderStep at
--      CAMERA priority, which runs BEFORE RenderStepped. Writing the camera from
--      RenderStepped loses that race. Aim therefore binds at a priority AFTER
--      CAMERA, not in RenderStepped.
--
-- Anti-cheat note: there is nothing to bypass client-side. The recon found a
-- clean DataModel metatable, zero guard scripts, and all defence server-side.
-- This build fires no remotes, writes no replicated property, and never touches
-- movement. The camera is client-only. There is no signal to suppress.

print("[LF] stage 1: started")

-- Retire the previous instance before doing anything else.
--
-- live-reload runs this file again while the old chunk is still alive. The
-- teardown at the bottom of the file registers a callback for it, but that only
-- helps if the loader actually calls the callback - and when it does not, every
-- reload leaves another RenderStepped handler and another input listener in
-- place. Measured: two loads -> 2 handlers, three loads -> 3. The visible result
-- is that one menu click toggles twice and nothing changes.
--
-- Rather than trust the loader, each instance hands its teardown to the next one
-- through the shared environment and calls it up front. Works with a loader that
-- supports cleanup, and without one. pcall so a half-dead previous instance
-- cannot stop the new one from loading.
local __prev_teardown = nil
pcall(function()
	local e = getfenv(0)
	if type(e) == "table" then
		__prev_teardown = e.LF_TEARDOWN
	end
end)
if type(__prev_teardown) == "function" then
	pcall(__prev_teardown)
	print("[LF] previous instance torn down")
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local WS = game:GetService("Workspace")

local LP = Players.LocalPlayer
print("[LF] stage 2: local player = " .. tostring(LP and LP.Name))

if typeof(Drawing) ~= "table" or typeof(Drawing.new) ~= "function" then
	warn("[LF] FATAL: no Drawing library")
	return
end

-- A missing library is fatal: there is nothing to draw with and every path
-- below assumes it. A library that exists but will not hand out an object is a
-- different case - that is a full budget, not a missing feature. Aborting there
-- took the aim down with the ESP, even though aiming only writes the camera.
-- So: probe, warn, and carry on degraded.
local probe = Drawing.new("Square")
if probe ~= nil and probe.Visible == false then
	pcall(function() probe:Remove() end)
	print("[LF] stage 3: Drawing ok")
else
	warn("[LF] WARN: Drawing.new returned nil - running without ESP/menu")
end
-- read again later by new_drawing; leave a flag rather than a local because the
-- probe runs long before that helper is defined
local drawing_available = probe ~= nil

--[[ drawing allocation ]]
--
-- Every Drawing object in this file is created through new_drawing, never by
-- calling Drawing.new directly. When an executor's object budget is exhausted
-- Drawing.new returns nil, and indexing that nil used to throw at load - which
-- took the menu, the ESP and the aim down together even though aiming only
-- writes the camera. A stub that quietly swallows reads, writes and methods
-- keeps every later code path walking the same lines: nothing appears on
-- screen, and everything that does not need pixels still runs.
--
-- The stub has to exist above the first slot allocation, so it is defined here
-- rather than next to the menu.
local DRAW_STUB_MT = {}
DRAW_STUB_MT.__index = function(t, k)
	return function() end
end
DRAW_STUB_MT.__newindex = function(t, k, v) end
DRAW_STUB_MT.__call = function() return nil end

local function new_drawing(kind)
	if not drawing_available then
		return setmetatable({}, DRAW_STUB_MT)
	end
	local ok, obj = pcall(Drawing.new, kind)
	if not ok or obj == nil then
		return setmetatable({}, DRAW_STUB_MT)
	end
	return obj
end

--[[ enums, resolved once, never assumed ]]

local function try_enum(getter)
	local ok, v = pcall(getter)
	if ok then
		return v
	end
	return nil
end

-- EnumItem comparison that survives an executor which builds a fresh object per
-- lookup.
--
-- `input.UserInputType == E.inputtype` compares two EnumItems. In the mock they
-- are the same table, so == is true. An executor that wraps Enum may hand out a
-- new object every access; == is then false, the right mouse button never
-- matches, aim_held never becomes true, and the aimbot does nothing at all while
-- every test still passes. Comparing Name (and Value when present) is immune.
local function same_enum(a, b)
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	local ok, an = pcall(function() return a.Name end)
	local ok2, bn = pcall(function() return b.Name end)
	if ok and ok2 and an ~= nil and an == bn then
		return true
	end
	local ok3, av = pcall(function() return a.Value end)
	local ok4, bv = pcall(function() return b.Value end)
	if ok3 and ok4 and av ~= nil and av == bv then
		return true
	end
	return false
end

local E = {
	headers = try_enum(function() return Enum.RenderPriority.Camera.Value end),
	inputtype = try_enum(function() return Enum.UserInputType.MouseButton2 end),
	mouse1 = try_enum(function() return Enum.UserInputType.MouseButton1 end),
	mousemove = try_enum(function() return Enum.UserInputType.MouseMovement end),
	insert = try_enum(function() return Enum.KeyCode.Insert end),
	-- RightShift opens the menu. Kept alongside Insert rather than replacing it:
	-- the shipped menu key was Insert, and a test or a user reflex may still send
	-- that key. MacLib only listens for the one it was given, so both are bound.
	rightshift = try_enum(function() return Enum.KeyCode.RightShift end),
	f1 = try_enum(function() return Enum.KeyCode.F1 end),
	f2 = try_enum(function() return Enum.KeyCode.F2 end),
	rayexclude = try_enum(function() return Enum.RaycastFilterType.Exclude end),
	-- Camera mode for the World tab's third-person toggle. Resolved through
	-- try_enum like the rest: an executor without an Enum table must make the
	-- toggle inert, never throw while the menu is being built.
	classic = try_enum(function() return Enum.CameraMode.Classic end),
	thirdperson = try_enum(function() return Enum.CameraMode.ThirdPerson end),
	custom = try_enum(function() return Enum.CameraType.Custom end),
}

print("[LF] stage 4: enums resolved")

--[[ config ]]

local CFG = {
	esp_on = true,
	esp_box = true,
	esp_box_style = 2,     -- 1 full box, 2 corner braces
	esp_skel = false,
	esp_name = true,
	esp_hp = true,
	esp_dist = true,
	esp_team = true,
	-- Hide teammates from the ESP entirely, rather than only colouring them.
	-- On by default because a team-only view is what was asked for; the colour
	-- branch stays for when this is off.
	esp_hide_team = true,
	esp_visible = false,
	esp_range = 1200,

	-- Colours. Stored as {r, g, b} 0-255 rather than Color3 so CFG stays plain
	-- data: Color3 needs the engine, and CFG is read before the ESP starts.
	esp_color_enemy = { 205, 45, 45 },
	esp_color_team = { 70, 150, 240 },
	-- Rainbow over the enemy colour. Speed is cycles per second.
	esp_rgb = false,
	esp_rgb_speed = 0.35,
	-- Bright overlay on every ESP'd player, so they read against a dark map.
	esp_glow = false,
	esp_glow_color = { 255, 70, 70 },
	esp_glow_transparency = 0.55,
	-- Translucent interior for the full box. Bottom of the stack at 0.7, so the
	-- target still reads through it instead of turning into a solid card.
	esp_box_fill = false,
	esp_box_fill_alpha = 0.78,

	aim_on = true,
	-- The shipped aim is the one that pulls in game, verbatim except where noted
	-- in the aim section. Its fov is a RADIUS IN PIXELS around the MOUSE, not
	-- degrees around screen centre, and its speed is an exp rate, so both keep
	-- those units and those names.
	aim_fov = 150,
	aim_speed = 18,
	-- Whether the hold button is down. Not a menu option and not a widget: the
	-- shipped aim polls the button itself, and this only drives the reticle and
	-- the diagnostics. Declared here so the first frame reads false rather than
	-- nil, and so no UI widget owns it.
	aim_held = false,

	-- World tab. Every one of these is client-side only: Lighting effects,
	-- Atmosphere and the camera are not replicated, so none of them puts
	-- anything on the wire the server could compare against.
	world_drone = false,     -- hide the drone's ColorCorrection
	world_fog = false,       -- push FogEnd out
	world_atmosphere = false, -- hide Atmosphere instances (haze)
	world_third = false,     -- third-person camera
	-- Lighting.Brightness override. Killing the fog and the atmosphere removes the
	-- haze that was scattering light, and the map reads as too dark. This raises
	-- the brightness to a value the user picks, and restores the captured original
	-- when switched off.
	world_bright = false,
	world_bright_value = 3,
	-- Which part the aim pulls to, set by the 3D dummy beside the menu.
	-- Head by default: it is what the shipped aim used.
	aim_part = "Head",

	-- Target the enemy DRONES instead of enemy players. The aim resolves its
	-- target through aim_candidates(), so this only changes which list it walks.
	aim_drones_only = false,

	--[[ UI tab ]]
	-- Scale multiplies the whole menu, 0.6 to 1.4. Opacity is the menu's own
	-- transparency in percent: 100 = solid, 10 = nearly see-through. The floor is
	-- 10 because below about that the menu stops being readable at all.
	ui_scale = 1.0,
	ui_opacity = 100,
	-- Theme name, one of THEMES below. "Preto com branco" is the library default.
	ui_theme = "Preto com branco",
	-- Rainbow only paints the borders, as asked: the body stays dark so the
	-- rolling hue never fights the text.
	ui_rgb = false,
	ui_rgb_speed = 0.25,

	--[[ DRONE tab ]]
	-- The vision fix is the same ColorCorrection toggle the WORLD tab had; it is
	-- kept under one name so both tabs drive one state.
	drone_vision = false,
	drone_esp = false,
	drone_esp_dist = true,
	drone_esp_pilot = true,
	drone_esp_glow = true,
	drone_esp_range = 2000,
}
-- Publish diagnostics on the executor's global table, whichever exists.
--
-- This used to call getgenv() directly. An executor without getgenv then threw
-- at stage 5 - before the aim, the menu and the input listener existed - so the
-- whole script died and the user saw "nothing works" rather than "esp works but
-- aim does not". Nothing here is essential to the script running, so it must
-- never be able to stop it.
local function globals()
	local g = nil
	pcall(function()
		g = getgenv()
	end)
	if type(g) == "table" then
		return g
	end
	pcall(function()
		g = getfenv(0)
	end)
	if type(g) == "table" then
		return g
	end
	return nil
end

do
	local env = globals()
	if env ~= nil then
		env.LF_SHARED = { CFG = CFG, DONE = true }
	end
end

-- apply_world is defined much later, once the Lighting objects and the camera
-- helpers exist. It is hung on LF_SHARED at the end of the UI section so a
-- reload (and a diagnostic) can re-apply the World switches without having to
-- drive a Toggle widget through its click handler.

print("[LF] stage 5: config published")

--[[ helpers ]]

local function cam()
	return WS.CurrentCamera
end

local function safe_get(inst, prop)
	if inst == nil then
		return nil
	end
	local ok, v = pcall(function()
		return inst[prop]
	end)
	if ok then
		return v
	end
	return nil
end

-- The rig lookup is deliberately loose about names.
--
-- It used to require exactly `Head` and `HumanoidRootPart`. Any place whose rig
-- names them differently, or that parents them outside Character, produced no
-- target at all - and because the aim has no error path for "nothing found", the
-- aimbot simply did nothing while every test still passed against a mock that
-- used the standard names.
--
-- So: any Humanoid, any root (the part the Humanoid reports as its root, else the
-- conventional name, else the character's primary part), and a head found by
-- name or by a head-shaped fallback. Only a missing Humanoid or zero health
-- rejects outright.
local function find_root(char, hum)
	local ok, rp = pcall(function()
		return hum.RootPart
	end)
	if ok and rp ~= nil then
		return rp
	end
	local named = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("RootPart")
	if named ~= nil then
		return named
	end
	local ok2, primary = pcall(function()
		return char.PrimaryPart
	end)
	if ok2 and primary ~= nil then
		return primary
	end
	return nil
end

local function find_head(char)
	local named = char:FindFirstChild("Head")
	if named ~= nil then
		return named
	end
	-- some rigs tuck the head under a model instead of the character
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "Head" then
			return d
		end
	end
	return nil
end

local function rig_of(char)
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local head = find_head(char)
	-- A head is optional now: torso/nearest-bone aiming has its own fallbacks,
	-- and rejecting the whole rig because one part is renamed was the bug.
	local root = find_root(char, hum)
	if not root then
		return nil
	end
	return hum, head, root
end

local function torso_of(char)
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

-- Resolve a player's rig when Player.Character does not hold it. In this place
-- Character is a stub Model (or nil) while the real body lives under
-- Workspace.<rig folder>.<player name>, so anything that needs a Humanoid has to
-- go through here. Returns nil rather than erroring when the player is in the
-- lobby and has no body at all.
local RIG_FOLDER_NAMES = {
	"IIIIllllIIIllIIlIlI_IIllIlIIIllII_o",
	"IIoooIIl",
	"lIIooolll",
}

-- Every folder under Workspace that holds player rigs.
--
-- The game does not keep one: measured in a 21-player server, the rigs were split
-- 7/7 across two sibling folders with different hashes (lIIooolll and IIoooIIl)
-- inside the same wrapper. Looking a player up in the FIRST folder that exists and
-- stopping there - which is what this did - found the 7 in one folder and silently
-- returned nil for everyone in the other, so half the server had no box, no glow,
-- no name, nothing.
--
-- The list is rebuilt per lookup rather than cached: two folders, a dozen children
-- each, and the wrapper is renamed between servers. Cheap enough at one lookup per
-- player per frame, and it cannot go stale.
local function rig_roots()
	local roots = {}
	-- `workspace` is a global, and it is not guaranteed to exist. Reading it
	-- directly threw "attempt to index global 'workspace'" on every player on
	-- every frame in the harness, which is exactly the sort of thing that has no
	-- business being able to kill the render loop. Resolved defensively, with the
	-- service as a fallback for the case where the global is missing.
	local ws = nil
	pcall(function()
		ws = workspace
	end)
	if ws == nil then
		pcall(function()
			ws = game:GetService("Workspace")
		end)
	end
	if ws == nil then
		return roots
	end
	-- Wrapped: nothing about a missing method on the world object should be able to
	-- take the render loop down. A lookup that cannot be done yields no roots, which
	-- is the same answer as "no rig found".
	pcall(function()
		for _, folder_name in ipairs(RIG_FOLDER_NAMES) do
			local folder = ws:FindFirstChild(folder_name)
			if folder ~= nil then
				table.insert(roots, folder)
				for _, sub in ipairs(folder:GetChildren()) do
					table.insert(roots, sub)
				end
			end
		end
	end)
	pcall(function()
		for _, folder in ipairs(ws:GetChildren()) do
			if folder:FindFirstChildOfClass("Humanoid") == nil then
				table.insert(roots, folder)
			end
		end
	end)
	return roots
end

local function rig_of_char(p)
	if p == nil then
		return nil
	end
	-- Every candidate is tried; the first rig with a Humanoid wins. Stopping at the
	-- first folder that happened to exist is what hid half the server.
	for _, folder in ipairs(rig_roots()) do
		local rig = folder:FindFirstChild(p.Name)
		if rig ~= nil and rig:FindFirstChildOfClass("Humanoid") ~= nil then
			return rig
		end
	end
	return nil
end

-- TeamColor items are compared directly; identity via tostring, because
-- Enum.TeamColor is not indexable here.
local function is_default_color(item)
	if item == nil then
		return true
	end
	local ok, n = pcall(function()
		return item.Name
	end)
	if ok and type(n) == "string" then
		-- Enum.TeamColor names look like "White", "Bright red"
		return n == "White" or n == "Medium stone grey"
	end
	local ok2, s = pcall(tostring, item)
	if not ok2 or type(s) ~= "string" then
		return true
	end
	-- tostring on an EnumItem yields "Enum.TeamColor.White"
	return string.find(s, "White", 1, true) ~= nil
end

-- Colour identity by Name, then by tostring. Comparing the objects with == fails
-- when two reads return different wrappers, and comparing tostring alone fails
-- whenever the wrapper is a plain table (both render as "table: 0x...").
local function same_color(a, b)
	local ok1, na = pcall(function()
		return a.Name
	end)
	local ok2, nb = pcall(function()
		return b.Name
	end)
	if ok1 and ok2 and type(na) == "string" and type(nb) == "string" then
		return na == nb
	end
	local ok3, sa = pcall(tostring, a)
	local ok4, sb = pcall(tostring, b)
	return ok3 and ok4 and sa == sb
end

-- True when p is on the local player's side.
--
-- Two signals, in order of reliability:
--
--   1. `Team`. Compared by Name rather than object identity, because different
--      reads can hand back different wrappers for the same team and `==` then
--      fails - which silently made every teammate look like an enemy.
--   2. `TeamColor`, but only when it is not the default. In this place the recon
--      found TeamColor == White for all thirteen players, so if White counted as
--      a team, everyone would be an ally and the ESP would show nobody. A default
--      colour means "no team", not "same team".
--
-- When neither signal exists the answer is false: an unknown player is treated as
-- an enemy, so the ESP errs towards showing someone rather than hiding the map.
-- The Lost Front does not use Player.Team or Player.TeamColor.
--
-- Verified in game: all 17 players in a live server reported Team = nil and
-- TeamColor = White, and the Teams service is empty. The real side lives on the
-- server registry, which the game's own client reads once at startup:
--
--   ReplicatedStorage.network.loadregistry:InvokeServer()
--     -> { [playerName] = { team = "attackers" | "defenders", equipped = n } }
--
-- The client also listens to network.joinedTeam for changes mid-match. Both are
-- read here; the registry is fetched once and refreshed on a slow timer, because
-- it is one round trip and the answer changes only on a team switch.
local SIDE_REGISTRY = nil       -- name -> "attackers" | "defenders"
local side_fetched_at = -1e9
local SIDE_REFRESH = 20         -- seconds between registry reads
local side_errors = 0
local side_busy = false

-- Team membership changes when the player joins/changes team, not per frame.
-- The raw ally() does four pcall reads; calling it for every player every frame
-- is 50+ protected reads per frame for a value that almost never moves. Cache
-- it and refresh when the registry is re-read.
-- Declared here because fetch_sides clears it; a later `local` would shadow it
-- and the cache would never reset on a team change.
local ally_cache = {}

local function fetch_sides()
	local net = nil
	local ok = pcall(function()
		net = game:GetService("ReplicatedStorage"):FindFirstChild("network")
	end)
	if not ok or net == nil then
		return
	end
	local reg = net:FindFirstChild("loadregistry")
	if reg == nil then
		return
	end
	-- Coroutine, hard 3 s wall clock. InvokeServer blocks the calling thread until
	-- the server answers; an unresponsive server must not freeze the render step,
	-- so the read happens in a task and the result is picked up when it arrives.
	local done, payload = false, nil
	task.spawn(function()
		local good, res = pcall(function()
			return reg:InvokeServer()
		end)
		done = true
		if good then
			payload = res
		end
	end)
	task.spawn(function()
		local waited = 0
		while not done and waited < 3 do
			task.wait(0.1)
			waited = waited + 0.1
		end
		if not done then
			side_errors = side_errors + 1
			if side_errors <= 2 then
				warn("[LF] team registry timed out; ESP team check stays off")
			end
			return
		end
		if type(payload) ~= "table" then
			return
		end
		local map = {}
		for name, info in pairs(payload) do
			if type(info) == "table" then
				local side = info.team
				if side == "attackers" or side == "defenders" then
					map[tostring(name)] = side
				end
			end
		end
		SIDE_REGISTRY = map
		side_fetched_at = os.clock()
		ally_cache = {}
	end)
end

local function side_of(p)
	if SIDE_REGISTRY == nil or p == nil then
		return nil
	end
	local ok, name = pcall(function()
		return p.Name
	end)
	if not ok or name == nil then
		return nil
	end
	return SIDE_REGISTRY[name]
end

local function team_name(p)
	local t = safe_get(p, "Team")
	if t == nil then
		return nil
	end
	local ok, n = pcall(function()
		return t.Name
	end)
	if ok and n ~= nil then
		return n
	end
	return nil
end

local function ally(p)
	if not p then
		return false
	end
	-- The game's own registry first: it is the only signal that exists here.
	local sa = side_of(LP)
	local sb = side_of(p)
	if sa ~= nil and sb ~= nil then
		return sa == sb
	end
	local na = team_name(LP)
	local nb = team_name(p)
	if na ~= nil and nb ~= nil then
		return na == nb
	end
	local ca = safe_get(LP, "TeamColor")
	local cb = safe_get(p, "TeamColor")
	if ca ~= nil and cb ~= nil and not is_default_color(ca) then
		return same_color(ca, cb)
	end
	return false
end

-- Team membership changes when the player joins/changes team, not per frame.
-- The raw ally() does four pcall reads; calling it for every player every frame
-- is 50+ protected reads per frame for a value that almost never moves. Cache
-- it and refresh when the registry is re-read.
local function ally_cached(p)
	local hit = ally_cache[p]
	if hit ~= nil then
		return hit
	end
	local v = ally(p)
	ally_cache[p] = v
	return v
end

-- A background loop must stop on teardown, or every reload leaves another one
-- running forever. `alive` is a plain flag the teardown clears.
local alive = true

task.spawn(function()
	while alive do
		task.wait(1.5)
		if not alive then
			break
		end
		ally_cache = {}
	end
end)

local ray = nil
if E.rayexclude ~= nil then
	ray = RaycastParams.new()
	ray.FilterType = E.rayexclude
	ray.IgnoreWater = true
end

local function is_visible(from, to, char)
	if ray == nil then
		return true
	end
	ray.FilterDescendantsInstances = { char, LP.Character }
	local ok, hit = pcall(function()
		return WS:Raycast(from, to - from, ray)
	end)
	if not ok then
		return true
	end
	return hit == nil
end

print("[LF] stage 6: helpers ok")

--[[ esp ]]

local state = {}

-- Bone pairs walked for the skeleton overlay, per rig type. R15 and R6 have
-- different joint names, so both are listed and missing ones are skipped.
local SKEL_R15 = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "RightLowerLeg", "RightFoot" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "UpperTorso", "RightUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "RightLowerArm", "RightHand" },
}

local SKEL_R6 = {
	{ "Head", "Torso" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
}

local SKEL_LINES = math.max(#SKEL_R15, #SKEL_R6)

-- Which pair list applies is decided by the rig, not by trying both.
-- Running R15 first and then R6 into the same buffer filled the allocation with
-- invisible R15 pairs and left no room for the six R6 ones, so R6 characters
-- drew almost nothing. Detect once per character and walk only the right set.
local function skeleton_set(char)
	if char:FindFirstChild("UpperTorso") then
		return SKEL_R15
	end
	return SKEL_R6
end

--[[ slot allocation ]]
--
-- 32 Drawing objects per player, created all at once, is 384 objects across a
-- 12-player lobby. When players appear together (round start, group respawn)
-- that lands on a single frame and the frame stalls.
--
-- So the slot is built in two layers: the eight core drawings are made on first
-- sight, and the two line sets are made only when their feature is actually
-- switched on, one player per frame. Nothing allocates during a toggle except
-- for the players who need it.

local function make_core(p)
	local s = {
		outline = new_drawing("Square"),
		box = new_drawing("Square"),
		name = new_drawing("Text"),
		tag = new_drawing("Text"),
		hp_bg = new_drawing("Square"),
		hp_fill = new_drawing("Square"),
		hp_edge = new_drawing("Square"),
		dist = new_drawing("Text"),
		snap = nil,
		lines = nil,
		box_fill = nil,
	}

	-- NOT filled. This was the "FULL box leaves a black interior" bug: a filled
	-- Square is a solid block, and this one is drawn behind the box at +2 px
	-- larger in a near-black colour, so every player turned into a black card. It
	-- is meant as a 1 px dark edge behind the coloured one, which needs an outline,
	-- not a fill.
	s.outline.Filled = false
	s.outline.Color = Color3.fromRGB(0, 0, 0)
	s.outline.Thickness = 1
	s.outline.ZIndex = 2

	s.box.Filled = false
	s.box.Thickness = 2
	s.box.ZIndex = 3

	s.name.Size = 14
	s.name.Center = true
	s.name.Outline = true
	s.name.OutlineColor = Color3.fromRGB(0, 0, 0)
	s.name.ZIndex = 5

	s.tag.Size = 12
	s.tag.Center = true
	s.tag.Outline = true
	s.tag.OutlineColor = Color3.fromRGB(0, 0, 0)
	s.tag.ZIndex = 5

	s.hp_bg.Filled = true
	s.hp_bg.Color = Color3.fromRGB(0, 0, 0)
	s.hp_bg.ZIndex = 2

	s.hp_edge.Filled = false
	s.hp_edge.Thickness = 1
	s.hp_edge.Color = Color3.fromRGB(0, 0, 0)
	s.hp_edge.ZIndex = 4

	s.hp_fill.Filled = true
	s.hp_fill.ZIndex = 3

	s.dist.Size = 13
	s.dist.Center = true
	s.dist.Outline = true
	s.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
	s.dist.Color = Color3.fromRGB(215, 215, 215)
	s.dist.ZIndex = 5

	state[p] = s
	return s
end

-- eight lines: two per corner
local function make_snap(s)
	if s.snap then
		return s.snap
	end
	local list = {}
	for i = 1, 8 do
		local l = new_drawing("Line")
		l.Thickness = 2
		l.ZIndex = 4
		list[i] = l
	end
	s.snap = list
	return list
end

local function make_lines(s)
	if s.lines then
		return s.lines
	end
	local list = {}
	for i = 1, SKEL_LINES do
		local l = new_drawing("Line")
		l.Thickness = 1
		l.Color = Color3.fromRGB(255, 255, 255)
		l.Transparency = 0.7
		l.ZIndex = 2
		list[i] = l
	end
	s.lines = list
	return list
end

-- Line-set allocation is staged: when a feature is switched on, every player
-- that needs the set is queued, and one player per frame is served. Creating
-- them inline meant a single toggle could allocate 12 * 14 objects in one frame
-- and the game stuttered exactly at the moment the user pressed a button.
-- Two independent queues, one per line set. A single queue with a "kind" tag
-- cannot work: draw_player can need both sets in the same frame, and the second
-- queue_alloc call reset the first one's list before it was ever served.
local alloc = {
	snap = nil,
	lines = nil,
	box_fill = nil,
}

local function make_box_fill(s)
	if s.box_fill then
		return s.box_fill
	end
	local d = new_drawing("Square")
	d.Filled = true
	d.ZIndex = 2
	s.box_fill = d
	return d
end

local function queue_alloc(kind)
	if alloc[kind] ~= nil then
		return
	end
	local list = {}
	for p, s in pairs(state) do
		if kind == "snap" and s.snap == nil then
			list[#list + 1] = p
		elseif kind == "lines" and s.lines == nil then
			list[#list + 1] = p
		elseif kind == "box_fill" and s.box_fill == nil then
			list[#list + 1] = p
		end
	end
	if #list > 0 then
		alloc[kind] = list
	end
end

-- one player per queue per frame, so the cost is spread instead of spiking.
-- A player can leave between being queued and being served, so state[p] is
-- checked before use and the entry is dropped rather than retried forever.
local function service_alloc()
	for _, kind in ipairs({ "snap", "lines", "box_fill" }) do
		local list = alloc[kind]
		if list ~= nil and #list > 0 then
			local p = table.remove(list)
			local s = p and state[p]
			if s then
				if kind == "snap" then
					pcall(make_snap, s)
				elseif kind == "lines" then
					pcall(make_lines, s)
				else
					pcall(make_box_fill, s)
				end
			end
			if #list == 0 then
				alloc[kind] = nil
			end
		end
	end
end

-- Players who leave keep their slot forever otherwise: nothing else removes it.
-- Clearing on removal also keeps the alloc queues from carrying dead entries.
--
-- keep() is defined further down, so this connection is parked in early_conns
-- and the teardown walks that list too. Connecting it unregistered would leave
-- one live handler per reload, all of them clearing the same tables.
local early_conns = {}

early_conns[#early_conns + 1] = Players.PlayerRemoving:Connect(function(p)
	local s = state[p]
	if s then
		-- The glow is a real Highlight instance parented to their character. If it
		-- is not destroyed here it outlives the slot and keeps glowing a player who
		-- already left, which is also a leak of one instance per departure.
		pcall(function()
			if s.hl ~= nil and s.hl.Parent ~= nil then
				s.hl:Destroy()
			end
		end)
		s.hl = nil
		-- box_fill is created lazily, so it is usually nil. Putting it inline in a
		-- table literal is what leaked every name/tag/health/distance drawing: a
		-- nil in the middle truncates the array, so ipairs stopped there and the
		-- rest of the slot was never removed. Named keys, then an explicit skip.
		local singles = {
			s.outline, s.box, s.name, s.tag,
			s.hp_bg, s.hp_fill, s.hp_edge, s.dist,
		}
		if s.box_fill ~= nil then
			singles[#singles + 1] = s.box_fill
		end
		for _, obj in ipairs(singles) do
			pcall(function() obj:Remove() end)
		end
		if s.snap then
			for _, obj in pairs(s.snap) do
				pcall(function() obj:Remove() end)
			end
		end
		if s.lines then
			for _, obj in pairs(s.lines) do
				pcall(function() obj:Remove() end)
			end
		end
		state[p] = nil
	end
	ally_cache[p] = nil
end)

local function slot_for(p)
	local s = state[p]
	if s then
		return s
	end
	return make_core(p)
end

-- make_core builds 8 Drawing objects. When 12 players appear in the same frame
-- that is 96 objects at once, which shows up as a hitch on a 7 GB machine.
-- Players start with core slots in a burst at round start / group respawn, so
-- the slot is staged instead: the first frames after appearing each build one
-- player's slot, and until then the player is simply not drawn.
--
-- core_pending is a queue of players waiting for a slot. It is drained one per
-- frame, before the ESP asks for slots, so nobody is starved.
local core_pending = {}
local core_queued = {}

local function request_core(p)
	if state[p] ~= nil or core_queued[p] then
		return
	end
	core_queued[p] = true
	core_pending[#core_pending + 1] = p
end

local function service_core()
	if #core_pending == 0 then
		return
	end
	local p = table.remove(core_pending, 1)
	core_queued[p] = nil
	if p == nil then
		return
	end
	if state[p] == nil and p.Character ~= nil then
		pcall(make_core, p)
	end
end

local function hide(s)
	s.outline.Visible = false
	s.box.Visible = false
	s.name.Visible = false
	s.tag.Visible = false
	s.hp_bg.Visible = false
	s.hp_fill.Visible = false
	s.hp_edge.Visible = false
	s.dist.Visible = false
	-- Lazily built by the box-fill option, so usually nil.
	if s.box_fill then
		s.box_fill.Visible = false
	end
	-- snap and lines are created lazily, so both can still be nil here
	if s.snap then
		for _, l in pairs(s.snap) do
			l.Visible = false
		end
	end
	if s.lines then
		for _, l in pairs(s.lines) do
			l.Visible = false
		end
	end
end

-- Box from head and feet.
--
-- The first version used root.Y - 2.4 as the feet, which assumes a standing
-- character of one fixed height - it drifts when the rig is short, crouched or
-- R6 vs R15. This measures the real extent instead: the lowest visible part
-- gives the feet, the head gives the top. Falls back to the old constant only
-- when neither part is present.

local function feet_y(char, root)
	local lowest = nil

	local function consider(part)
		if part and part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y * 0.5
			if lowest == nil or bottom < lowest then
				lowest = bottom
			end
		end
	end

	-- R15
	consider(char:FindFirstChild("LeftFoot"))
	consider(char:FindFirstChild("RightFoot"))
	consider(char:FindFirstChild("LeftLowerLeg"))
	consider(char:FindFirstChild("RightLowerLeg"))
	-- R6
	consider(char:FindFirstChild("Left Leg"))
	consider(char:FindFirstChild("Right Leg"))

	if lowest == nil then
		return root.Position.Y - 2.4
	end
	return lowest
end

local function project(char, head, root, c)
	-- The head is optional. rig_of accepts any Humanoid and falls back to the root
	-- when a character has no part called "Head"; project then indexed head.Position
	-- unguarded, which threw, and the pcall around draw_player turned the whole
	-- player's ESP into one line in the console. Observed in game as:
	--   [LF] draw error: :782: attempt to index nil with 'Position'
	-- The top of a rig measured from the root is a reasonable box even without a
	-- head: the R6/R15 torso is about 2 studs tall above the hip.
	local top_part = head or root
	if top_part == nil then
		return nil
	end
	local top_y = top_part.Position.Y + 0.4
	if head == nil then
		-- root sits at hip height; add the head-ish height above it
		top_y = root.Position.Y + 1.8
	end
	local top = Vector3.new(root.Position.X, top_y, root.Position.Z)
	local bottom = Vector3.new(root.Position.X, feet_y(char, root), root.Position.Z)

	local st = c:WorldToViewportPoint(top)
	local sb = c:WorldToViewportPoint(bottom)

	-- Both ends must be in front of the camera. A single projected point makes
	-- boxes slide when the player is half off-screen.
	if st.Z <= 0 or sb.Z <= 0 then
		return nil
	end

	local h = math.abs(sb.Y - st.Y)
	if h < 6 then
		return nil
	end

	local w = h * 0.52
	local x = (st.X + sb.X) * 0.5 - w * 0.5
	local y = math.min(st.Y, sb.Y)

	return Vector2.new(x, y), Vector2.new(w, h)
end

local function hp_color(frac)
	return Color3.new(1 - frac * 0.78, 0.22 + frac * 0.62, 0.18)
end

--[[ corner braces ]]
--
-- Eight short lines: two per corner. A full box around every player turns the
-- screen into a cage when several are on screen; corner braces read the same
-- at a glance and leave the target itself unobstructed.

local function draw_corners(s, list, pos, size, col)
	local arm = math.clamp(size.X * 0.28, 4, 16)

	local x1, y1 = pos.X, pos.Y
	local x2, y2 = pos.X + size.X, pos.Y + size.Y

	local pts = {
		{ Vector2.new(x1, y1), Vector2.new(x1 + arm, y1) }, -- top left, horizontal
		{ Vector2.new(x1, y1), Vector2.new(x1, y1 + arm) }, -- top left, vertical
		{ Vector2.new(x2, y1), Vector2.new(x2 - arm, y1) }, -- top right, horizontal
		{ Vector2.new(x2, y1), Vector2.new(x2, y1 + arm) }, -- top right, vertical
		{ Vector2.new(x1, y2), Vector2.new(x1 + arm, y2) }, -- bottom left, horizontal
		{ Vector2.new(x1, y2), Vector2.new(x1, y2 - arm) }, -- bottom left, vertical
		{ Vector2.new(x2, y2), Vector2.new(x2 - arm, y2) }, -- bottom right, horizontal
		{ Vector2.new(x2, y2), Vector2.new(x2, y2 - arm) }, -- bottom right, vertical
	}

	for i = 1, 8 do
		local l = list[i]
		l.From = pts[i][1]
		l.To = pts[i][2]
		l.Color = col
		l.Visible = true
	end
end

--[[ skeleton ]]
--
-- Bones are shared between pairs: UpperTorso appears in three of them, so
-- projecting inside the loop called WorldToViewportPoint twice per pair - 28
-- calls per player per frame for 14 pairs. The same ~15 joints get projected
-- over and over.
--
-- The cache lives for exactly one frame and is keyed by the part instance, so
-- joints shared inside one character cost one call each. It is cleared once at
-- the top of on_frame - clearing it per player would throw away the previous
-- player's entries and multiply the work by player count.

local proj_cache = {}

local function clear_proj_cache()
	for k in pairs(proj_cache) do
		proj_cache[k] = nil
	end
end

local function proj_of(c, part)
	local hit = proj_cache[part]
	if hit ~= nil then
		return hit
	end
	local sp = c:WorldToViewportPoint(part.Position)
	if sp.Z <= 0 then
		proj_cache[part] = false
		return false
	end
	proj_cache[part] = sp
	return sp
end

local function draw_skeleton(s, list, char, c, col)
	local used = 0
	local bone_pairs = skeleton_set(char)

	for _, pair in ipairs(bone_pairs) do
		used = used + 1
		local a = char:FindFirstChild(pair[1])
		local b = char:FindFirstChild(pair[2])
		local l = list[used]

		local ok = false
		if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
			local sa = proj_of(c, a)
			local sb = proj_of(c, b)
			if sa and sb then
				l.From = Vector2.new(sa.X, sa.Y)
				l.To = Vector2.new(sb.X, sb.Y)
				l.Color = col
				ok = true
			end
		end

		l.Visible = ok
	end

	-- any line not written this frame must not linger from the last one
	for i = used + 1, SKEL_LINES do
		list[i].Visible = false
	end
end

local function draw_player(p, my_pos)
	local char = p.Character
	local hum, head, root = nil, nil, nil
	if char then
		hum, head, root = rig_of(char)
	end
	-- Player.Character is not always the body. Measured in a 21-player server:
	-- several players had a Character with one or four children and no Humanoid -
	-- a stub - while their full rig (Humanoid, root, head) sat in the rig folder.
	-- rig_of returned nil for those, so they got no box, no name, no glow, and
	-- nothing said why. rig_of_char is the resolver that knows about the folder
	-- layout, and this is the one place that needed it and did not call it.
	if root == nil then
		local folder_rig = rig_of_char(p)
		if folder_rig ~= nil and folder_rig ~= char then
			local fh, fhead, froot = rig_of(folder_rig)
			if froot ~= nil then
				char, hum, head, root = folder_rig, fh, fhead, froot
			end
		end
	end

	local s = state[p]
	local c = cam()
	local pos, size = nil, nil
	local dist = 0

	-- team filter: hide players on the local player's side entirely.
	-- Checked before any projection so a teammate costs one cached lookup and
	-- nothing else.
	if CFG.esp_hide_team and ally_cached(p) then
		if s then
			hide(s)
		end
		return
	end

	-- esp_on gates everything. Without this read the menu's "esp" toggle had no
	-- effect at all - the key existed and nothing consulted it.
	if CFG.esp_on and hum and root and c then
		dist = (root.Position - my_pos).Magnitude
		if dist <= CFG.esp_range then
			pos, size = project(char, head, root, c)
			-- the visibility ray needs a point; fall back to the root when the
			-- rig has no head part rather than erroring out of the frame
			local eye = head or root
			if pos and CFG.esp_visible then
				if not is_visible(c.CFrame.Position, eye.Position, char) then
					pos = nil
				end
			end
		end
	end

	-- Glow runs here, before the projection gate below.
	--
	-- It used to live after it, which meant the glow was only applied to players
	-- that projected on screen, and turned off for everyone else. Measured on a
	-- 21-player server: the players whose rig happened to be outside the viewport
	-- had no glow at all, and the ones on screen did - nothing to do with who was
	-- an enemy. A glow is a world-space effect; it does not care where the camera
	-- is pointing. Its rule is the one the user asked for: alive, in range, and not
	-- a teammate.
	--
	-- s.hl is created lazily and reused, so this is cheap on the frames where
	-- nothing changed. `char` is the rig resolved above, which may be the folder
	-- copy rather than Player.Character.
	if CFG.esp_glow and char ~= nil then
		local glow_dist = 0
		if root ~= nil and my_pos ~= nil then
			glow_dist = (root.Position - my_pos).Magnitude
		end
		local glow_friendly = CFG.esp_team and ally_cached(p)
		local glow_wanted = glow_dist <= CFG.esp_range and not glow_friendly
		local gcol = glow_wanted and Color3.fromRGB(
			CFG.esp_color_enemy[1], CFG.esp_color_enemy[2], CFG.esp_color_enemy[3])
		if glow_wanted and CFG.esp_rgb then
			gcol = Color3.fromHSV((os.clock() * CFG.esp_rgb_speed) % 1, 1, 1)
		end
		-- The Highlight lives on the character, not in the ESP slot. Tying it to
		-- the slot meant a player with no slot yet - slots are handed out one per
		-- frame - had no glow for as long as the queue was behind, and the glow
		-- vanished the moment the ESP was toggled off. Reading it off `char` makes
		-- it independent of the drawing state, which is what a world-space glow is.
		local have_hl = char:FindFirstChild("LF_Glow")
		if s ~= nil then s.hl = have_hl end
		if glow_wanted then
			if s == nil or s.hl == nil or s.hl.Parent ~= char then
				pcall(function()
					if have_hl ~= nil then
						have_hl:Destroy()
					end
					local hl = Instance.new("Highlight")
					hl.Name = "LF_Glow"
					hl.FillColor = Color3.fromRGB(
						CFG.esp_glow_color[1], CFG.esp_glow_color[2], CFG.esp_glow_color[3])
					hl.OutlineColor = gcol
					hl.FillTransparency = CFG.esp_glow_transparency
					hl.OutlineTransparency = 0.15
					pcall(function()
						hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					end)
					hl.Parent = char
					if s ~= nil then s.hl = hl end
					have_hl = hl
				end)
			end
			local live = char:FindFirstChild("LF_Glow")
			if live ~= nil then
				pcall(function()
					live.Enabled = true
					live.OutlineColor = gcol
				end)
				if s ~= nil then s.hl = live end
			end
		else
			local off = char:FindFirstChild("LF_Glow")
			if off ~= nil then
				pcall(function() off.Enabled = false end)
			end
		end
	end

	if not pos then
		if s then
			hide(s)
			-- The glow is NOT turned off here any more. It used to be, and that was
			-- the bug: a player off screen or out of range lost the glow even while
			-- standing alive in plain sight of the world. The glow has its own rule
			-- below - alive, in range, enemy - and it runs before this early return.
		end
		return
	end

	-- Slot creation is staged one player per frame (see request_core). Until
	-- this player's turn comes it has no drawings, so the frame is skipped with
	-- a request queued. The queue drains in on_frame before drawing starts.
	if s == nil then
		request_core(p)
		return
	end

	local friendly = CFG.esp_team and ally_cached(p)
	-- Enemy colour is configurable; the friendly blue stays fixed so the two can
	-- never collapse into the same colour and make a teammate look hostile.
	local e = CFG.esp_color_enemy
	local col = Color3.fromRGB(e[1], e[2], e[3])
	if friendly then
		local f = CFG.esp_color_team
		col = Color3.fromRGB(f[1], f[2], f[3])
	end
	-- Rainbow cycles the enemy colour. Applied after the branch above so it also
	-- overrides the fixed enemy colour, but never the teammate blue.
	if CFG.esp_rgb and not friendly then
		col = Color3.fromHSV((os.clock() * CFG.esp_rgb_speed) % 1, 1, 1)
	end


	-- Box styles: 1 = full box, 2 = corner braces. Only one is drawn at a time;
	-- leaving the other set visible from a previous frame is how you get a box
	-- and braces stacked on top of each other after a toggle.
	if CFG.esp_box and CFG.esp_box_style == 1 then
		-- Full box. The dark edge behind it is an OUTLINE, 1 px, offset by -1.
		-- Its colour used to be near-black AND filled; disabling the fill is the
		-- fix for the "FULL leaves the box interior black" report.
		s.outline.Visible = true
		s.outline.Position = Vector2.new(pos.X - 1, pos.Y - 1)
		s.outline.Size = Vector2.new(size.X + 2, size.Y + 2)

		s.box.Visible = true
		s.box.Position = pos
		s.box.Size = size
		s.box.Color = col

		-- Translucent interior, drawn BETWEEN the dark edge and the coloured
		-- border so the outline still reads. This is a separate drawing on
		-- purpose: reusing s.outline for a fill is what produced the black box,
		-- because that square is also the 1 px shadow behind every style.
		if CFG.esp_box_fill then
			if s.box_fill == nil then
				queue_alloc("box_fill")
				s.box_fill = nil
			end
			if s.box_fill ~= nil then
				s.box_fill.Visible = true
				s.box_fill.Filled = true
				s.box_fill.Color = col
				s.box_fill.Transparency = CFG.esp_box_fill_alpha
				s.box_fill.Position = pos
				s.box_fill.Size = size
			end
		elseif s.box_fill ~= nil then
			s.box_fill.Visible = false
		end
	else
		s.outline.Visible = false
		s.box.Visible = false
	end

	if CFG.esp_box and CFG.esp_box_style == 2 then
		if s.snap then
			draw_corners(s, s.snap, pos, size, col)
		else
			queue_alloc("snap")
		end
	elseif s.snap then
		for _, l in pairs(s.snap) do
			l.Visible = false
		end
	end

	if CFG.esp_skel then
		if s.lines then
			draw_skeleton(s, s.lines, char, c, col)
		else
			queue_alloc("lines")
		end
	elseif s.lines then
		for _, l in pairs(s.lines) do
			l.Visible = false
		end
	end

	if CFG.esp_name then
		s.name.Visible = true
		s.name.Text = p.Name
		s.name.Color = col
		s.name.Position = Vector2.new(pos.X + size.X * 0.5, pos.Y - 17)
	else
		s.name.Visible = false
	end

	if CFG.esp_team and friendly then
		s.tag.Visible = true
		s.tag.Text = "TEAM"
		s.tag.Color = col
		s.tag.Position = Vector2.new(pos.X + size.X * 0.5, pos.Y - 33)
	else
		s.tag.Visible = false
	end

	if CFG.esp_hp then
		local frac = 1
		if hum.MaxHealth > 0 then
			frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		end

		local bx = pos.X - 8
		local fill_h = math.max(1, size.Y * frac)

		s.hp_bg.Visible = true
		s.hp_bg.Position = Vector2.new(bx, pos.Y)
		s.hp_bg.Size = Vector2.new(4, size.Y)

		s.hp_edge.Visible = true
		s.hp_edge.Position = Vector2.new(bx - 1, pos.Y - 1)
		s.hp_edge.Size = Vector2.new(6, size.Y + 2)

		s.hp_fill.Visible = true
		s.hp_fill.Position = Vector2.new(bx, pos.Y + size.Y - fill_h)
		s.hp_fill.Size = Vector2.new(4, fill_h)
		s.hp_fill.Color = hp_color(frac)
	else
		s.hp_bg.Visible = false
		s.hp_fill.Visible = false
		s.hp_edge.Visible = false
	end

	if CFG.esp_dist then
		s.dist.Visible = true
		s.dist.Text = tostring(math.floor(dist)) .. "m"
		s.dist.Position = Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y + 2)
	else
		s.dist.Visible = false
	end
end

print("[LF] stage 7: esp ready")

--[[ drones ]]
--
-- Measured in game rather than guessed: a drone is NOT a part on the pilot's
-- character and not in the player rig folder. It is a Model inside
-- workspace["IllllII_iiii"], carrying two attributes that are all the ESP needs:
--
--   :GetAttribute("player")   the PILOT's name
--   :GetAttribute("throttle") "1" / "2" while flying
--
-- Dead drones stay in the folder with no children and no PrimaryPart, so every
-- candidate is checked for a real body before it is drawn or aimed at - otherwise
-- the ESP happily draws a box at (0, 0, 0) for a drone that no longer exists.
local DRONE_FOLDER_NAMES = { "IllllII_iiii" }

local function drone_folder()
	-- Resolved through the service, not the `workspace` global: an executor can
	-- install this file into an environment where that global is absent, and the
	-- drone pass runs inside a pcall per frame - so the failure was silent apart
	-- from a warning, and every drone went undrawn.
	local ws = WS
	if ws == nil then
		-- WS is resolved once at the top of the file. Under an executor that does
		-- not expose GetService at load time it can be nil, so it is retried here
		-- rather than crashing the whole drone pass every frame.
		local ok, svc = pcall(function()
			return game:GetService("Workspace")
		end)
		ws = ok and svc or nil
	end
	if ws == nil then
		return nil
	end
	-- Guard the shape, not just the nil: WS is whatever the environment calls the
	-- workspace, and asking it for children when it is not a container must degrade
	-- to "no drones" rather than throwing once per frame.
	if type(ws.FindFirstChild) ~= "function" then
		return nil
	end
	for _, name in ipairs(DRONE_FOLDER_NAMES) do
		local f = ws:FindFirstChild(name)
		if f ~= nil then
			return f
		end
	end
	-- the folder name is a hash and can change between servers
	for _, d in ipairs(ws:GetChildren()) do
		if d:IsA("Folder") or d:IsA("Model") then
			local child = d:GetChildren()
			if #child > 0 then
				for _, c in ipairs(child) do
					if c:IsA("Model") and c:GetAttribute("player") ~= nil then
						return d
					end
				end
			end
		end
	end
	return nil
end

local function drone_body(model)
	if model == nil then
		return nil
	end
	local pp = model.PrimaryPart
	if pp ~= nil then
		return pp
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

-- Every live drone: { model, pilot, part, pos }.
local function live_drones()
	local list = {}
	local folder = drone_folder()
	if folder == nil then
		return list
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local part = drone_body(model)
			if part ~= nil then
				list[#list + 1] = {
					model = model,
					pilot = model:GetAttribute("player"),
					part = part,
					pos = part.Position,
				}
			end
		end
	end
	return list
end

-- A drone is an enemy when its pilot is not on our side. Reuses ally_cached, so
-- there is one definition of "teammate" in the whole file.
local function drone_is_enemy(pilot)
	if pilot == nil then
		return false
	end
	local p = Players:FindFirstChild(tostring(pilot))
	if p == nil then
		-- A pilot who already left: their drone still exists for a moment. Treat it
		-- as an enemy so the ESP does not blink it out mid-despawn.
		return true
	end
	return not ally_cached(p)
end

-- One Drawing set per drone, keyed by the Model. Separate from the player slots
-- because drones come and go far more often and must not consume the player
-- alloc queues.
local drone_draw = {}

local function drone_slot(model)
	local s = drone_draw[model]
	if s ~= nil then
		return s
	end
	s = {
		box = new_drawing("Square"),
		outline = new_drawing("Square"),
		label = new_drawing("Text"),
		dist = new_drawing("Text"),
	}
	s.outline.Filled = false
	s.outline.Color = Color3.fromRGB(0, 0, 0)
	s.outline.Thickness = 1
	s.outline.ZIndex = 2
	s.box.Filled = false
	s.box.Thickness = 2
	s.box.ZIndex = 3
	s.label.Size = 13
	s.label.Center = true
	s.label.Outline = true
	s.label.OutlineColor = Color3.fromRGB(0, 0, 0)
	s.label.ZIndex = 5
	s.dist.Size = 12
	s.dist.Center = true
	s.dist.Outline = true
	s.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
	s.dist.ZIndex = 5
	drone_draw[model] = s
	return s
end

local function drone_hide(s)
	if s == nil then
		return
	end
	pcall(function()
		s.box.Visible = false
		s.outline.Visible = false
		s.label.Visible = false
		s.dist.Visible = false
	end)
end

-- Glow for a drone: a Highlight on the Model, client-side only, same as the
-- player glow. Kept on the model so it dies with it.
local function drone_glow(model, on, colour)
	local hl = model:FindFirstChild("LF_DroneGlow")
	if on then
		if hl == nil then
			pcall(function()
				hl = Instance.new("Highlight")
				hl.Name = "LF_DroneGlow"
				hl.FillColor = colour
				hl.FillTransparency = 0.55
				hl.OutlineColor = colour
				hl.OutlineTransparency = 0.1
				-- Best-effort: an executor whose Enum table lacks HighlightDepthMode
				-- would throw here, and the glow is still worth having without it.
				pcall(function()
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				end)
				hl.Parent = model
			end)
		end
		if hl ~= nil then
			pcall(function()
				hl.Enabled = true
				hl.FillColor = colour
				hl.OutlineColor = colour
			end)
		end
	elseif hl ~= nil then
		pcall(function() hl.Enabled = false end)
	end
end

-- Drone ESP, drawn from the frame loop right after the player ESP.
local function draw_drones(c, my_pos)
	local seen = {}
	for _, d in ipairs(live_drones()) do
		seen[d.model] = true
		if CFG.drone_esp then
			local dist = (d.pos - my_pos).Magnitude
			if dist <= CFG.drone_esp_range then
				local screen, onScreen = c:WorldToViewportPoint(d.pos)
				if onScreen then
					local s = drone_slot(d.model)
					local enemy = drone_is_enemy(d.pilot)
					local col = enemy and rgb3(CFG.esp_color_enemy) or rgb3(CFG.esp_color_team)
					-- Drones are small: give the box a fixed floor so it stays visible
					-- at range instead of collapsing to a couple of pixels.
					local h = math.clamp(2400 / math.max(dist, 1), 18, 90)
					local w = h * 0.9
					local pos = Vector2.new(screen.X - w * 0.5, screen.Y - h * 0.5)

					s.outline.Visible = true
					s.outline.Position = Vector2.new(pos.X - 1, pos.Y - 1)
					s.outline.Size = Vector2.new(w + 2, h + 2)
					s.box.Visible = true
					s.box.Position = pos
					s.box.Size = Vector2.new(w, h)
					s.box.Color = col

					local y = pos.Y - 16
					if CFG.drone_esp_pilot and d.pilot ~= nil then
						s.label.Visible = true
						s.label.Text = tostring(d.pilot)
						s.label.Color = col
						s.label.Position = Vector2.new(screen.X, y)
					else
						s.label.Visible = false
					end

					if CFG.drone_esp_dist then
						s.dist.Visible = true
						s.dist.Text = tostring(math.floor(dist)) .. "m"
						s.dist.Color = Color3.fromRGB(215, 215, 215)
						s.dist.Position = Vector2.new(screen.X, pos.Y + h + 2)
					else
						s.dist.Visible = false
					end

					drone_glow(d.model, CFG.drone_esp_glow, col)
				else
					drone_hide(drone_draw[d.model])
				end
			else
				drone_hide(drone_draw[d.model])
			end
		else
			drone_hide(drone_draw[d.model])
		end
	end
	-- drones that vanished: free their drawings
	for model, s in pairs(drone_draw) do
		if not seen[model] then
			drone_hide(s)
			for _, obj in ipairs({ s.box, s.outline, s.label, s.dist }) do
				pcall(function() obj:Remove() end)
			end
			drone_draw[model] = nil
		end
	end
end


--[[ aim ]]
--
-- This section is the user's own aimbot, which works in this game where the
-- previous one did not. It is kept as close to the original as possible; the
-- only additions are the menu switches (enable, and three fov steps) and the
-- teardown hook the rest of this file needs.
--
-- How it works, because the differences matter:
--
--   * The fov is a RADIUS IN PIXELS around the MOUSE, squared and compared
--     against dx*dx + dy*dy. Screen centre is not involved and neither is
--     Camera.FieldOfView, so the cone is exactly what the drawn circle shows.
--   * The pull is `mousemoverel`, not a camera write. It moves the OS cursor,
--     which the game's camera follows through its own CameraModule - so there is
--     nothing to fight and no priority to lose.
--   * Team check comes from the game's own replicated module, found by walking
--     getloadedmodules() for a table exporting isFriendly.
--
-- The one thing that had to change: the original takes a character that the game
-- may be recreating, and `head.Position` on a rig whose head is gone throws. The
-- loop below keeps the same shape but guards the parts it indexes.

-- The button the aim holds on. The shipped code named it directly; here it is
-- resolved defensively, because an executor without that enum entry would throw
-- on the very first frame and kill the aim outright. Right mouse, matching the
-- input listeners below.
local AIM_BUTTON = E.inputtype

-- The user's original ran with the aim always on. Here it starts on (what was
-- asked for) and a menu toggle stops and restarts it; FOV steps do not restart
-- it, because fov is read fresh each frame.
local aim_enabled = true
local aim_unbind = nil

local rayParams = RaycastParams.new()
-- Exclude is the modern name; Blacklist is what older clients still expose. Some
-- executors throw on the missing one, so this is resolved under pcall and the
-- raycast is skipped entirely if neither exists.
do
	local ok_ex, ex = pcall(function() return Enum.RaycastFilterType.Exclude end)
	if not ok_ex or ex == nil then
		ok_ex, ex = pcall(function() return Enum.RaycastFilterType.Blacklist end)
	end
	if ok_ex and ex ~= nil then
		pcall(function()
			rayParams.FilterType = ex
		end)
	end
end
rayParams.IgnoreWater = true
local ignored = {}

-- Team check, from the game's own module. This used to be this script's own
-- side registry; the module below is the game's authority and is one call.
local function find_is_friendly()
	local ok_all, mods = pcall(getloadedmodules)
	if not ok_all or type(mods) ~= "table" then
		return nil
	end
	for _, module in ipairs(mods) do
		local ok_desc, in_rs = pcall(function()
			return module:IsDescendantOf(ReplicatedStorage)
		end)
		if ok_desc and in_rs then
			local ok, exports = pcall(require, module)
			if ok and type(exports) == "table" and rawget(exports, "isFriendly") and rawget(exports, "getEnemyTeam") then
				return exports.isFriendly
			end
		end
	end
	return nil
end

-- The user's original also draws the fov circle. This file already had one, so
-- its circle is not created here: the existing `ring` drawing below is driven
-- from the values the aim is actually using, which keeps one reticle instead of
-- two overlapping ones.

-- the values the frame loop publishes for the ring and the diagnostics
local aim_state = {
	dx = 0,
	dy = 0,
	target = nil,
	pulls = 0,
	errors = 0,
}

local function start_aim()
	if aim_unbind ~= nil then
		return true
	end

	local isFriendly = find_is_friendly()

	local ok_bind, err = pcall(function()
		aim_unbind = RunService.RenderStepped:Connect(function(dt)
			-- Read the option every frame rather than capturing it: the menu
			-- changes it whenever it is clicked, and rebuilding the connection
			-- on every fov step would strobe the reticle.
			local fov = CFG.aim_fov

			local ok_frame, e = pcall(function()
				-- The two coordinate spaces this loop mixes are NOT the same.
				--
				--   * WorldToViewportPoint returns SCREEN space: origin at the
				--     top-left, Y growing downward, matching the viewport.
				--   * UserInputService:GetMouseLocation returns MOUSE space: origin
				--     at the BOTTOM-left, Y growing upward, so its Y is
				--     viewport.Y - screenY.
				--
				-- Subtracting one from the other without converting meant every
				-- target scored an error of roughly the viewport height on Y:
				-- measured live at 1920x1009 with the cursor mid-screen, the mouse
				-- read 924,1008 while a dead-centre target projected to 960,504.
				-- dy was ~500 px for a target the cursor was sitting on, the fov
				-- test (150 px) rejected everything, and the aim never pulled - it
				-- looked like the feature had been deleted.
				--
				-- Converted once here, so everything below compares screen to
				-- screen. mouse_raw stays available for anything that needs the
				-- original value.
				local mouse_raw = UIS:GetMouseLocation()
				local viewport = WS.CurrentCamera and WS.CurrentCamera.ViewportSize
				local mouse = mouse_raw
				if viewport ~= nil then
					local ok_conv = pcall(function()
						mouse = Vector2.new(mouse_raw.X, viewport.Y - mouse_raw.Y)
					end)
					if not ok_conv then
						mouse = mouse_raw
					end
				end
				aim_state.mouse = mouse
				aim_state.mouse_raw = mouse_raw

				local character = LP and LP.Character
				if not character or not UIS:IsMouseButtonPressed(AIM_BUTTON) then
					aim_state.target = nil
					return
				end

				local camera = cam()
				if camera == nil then
					return
				end
				local origin = camera.CFrame.Position
				local bestX, bestY, bestDistance = nil, nil, fov * fov

				ignored[1] = camera
				ignored[2] = character
				rayParams.FilterDescendantsInstances = ignored

				-- Drone mode. Same pull, same raycast, same everything - only the
				-- list of things it is allowed to pick from changes, which is why
				-- the aim maths below is untouched.
				if CFG.aim_drones_only then
					for _, d in ipairs(live_drones()) do
						if drone_is_enemy(d.pilot) then
							local screen, onScreen = camera:WorldToViewportPoint(d.pos)
							local dx, dy = screen.X - mouse.X, screen.Y - mouse.Y
							local distance = dx * dx + dy * dy
							local take = onScreen and distance < bestDistance
							if take then
								local hit = WS:Raycast(origin, d.pos - origin, rayParams)
								if hit and not hit.Instance:IsDescendantOf(d.model) then
									take = false
								end
							end
							if take then
								bestX, bestY, bestDistance = dx, dy, distance
								aim_state.target = d.model
							end
						end
					end
				else
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LP then
						local target = player.Character
						local head = target and target:FindFirstChild("Head")
						local humanoid = head and target:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 and head then
							-- Which part to pull to comes from the 3D dummy in the AIM tab.
							-- Head is the shipped behaviour and stays the fallback: a
							-- character without the requested part must still be aimable,
							-- not silently skipped.
							local aim_bone = head
							local want = CFG.aim_part
							if want == "Torso" then
								aim_bone = target:FindFirstChild("UpperTorso")
									or target:FindFirstChild("Torso")
									or head
							elseif want == "Legs" then
								aim_bone = target:FindFirstChild("UpperLeg")
									or target:FindFirstChild("LeftUpperLeg")
									or target:FindFirstChild("Left Leg")
									or head
							end
							local head_pos = aim_bone.Position
							local screen, onScreen = camera:WorldToViewportPoint(head_pos)
							local dx, dy = screen.X - mouse.X, screen.Y - mouse.Y
							local distance = dx * dx + dy * dy
							local take = onScreen and distance < bestDistance

							if take and isFriendly then
								local okf, friendly = pcall(isFriendly, player)
								if okf and friendly then
									take = false
								end
							end

							if take then
								local hit = WS:Raycast(origin, head_pos - origin, rayParams)
								if hit and not hit.Instance:IsDescendantOf(target) then
									take = false
								end
							end

							if take then
								bestX, bestY, bestDistance = dx, dy, distance
								aim_state.target = player
							end
						end
					end
				end
				end

				if bestX then
					local step = 1 - math.exp(-CFG.aim_speed * dt)
					aim_state.dx, aim_state.dy = bestX, bestY
					aim_state.pulls = aim_state.pulls + 1
					mousemoverel(bestX * step, bestY * step)
				else
					aim_state.target = nil
				end
			end)
			if not ok_frame then
				aim_state.errors = aim_state.errors + 1
				if aim_state.errors <= 3 then
					warn("[LF] aim error: " .. tostring(e))
				end
			end
		end)
	end)

	if not ok_bind then
		aim_unbind = nil
		warn("[LF] aim bind failed: " .. tostring(err))
		return false
	end
	return true
end

local function stop_aim()
	if aim_unbind ~= nil then
		pcall(function()
			aim_unbind:Disconnect()
		end)
		aim_unbind = nil
	end
	aim_state.target = nil
end

-- Reconcile the wanted state with the running one. Called from the frame loop
-- and right after a menu click, so the toggle takes effect on the next frame.
local function sync_aim()
	if CFG.aim_on and aim_enabled then
		if aim_unbind == nil then
			start_aim()
		end
	else
		stop_aim()
	end
end

aim_enabled = start_aim()
print("[LF] stage 8: aim ready, bound = " .. tostring(aim_enabled))

--[[ fov ring ]]
--
-- The shipped aim drew its own circle around the MOUSE. This reuses the drawing
-- this file already had, so there is one reticle and not two. Its radius is the
-- fov in PIXELS - the exact value the range test uses - and it is only visible
-- while the aim is on and the hold button is down.

local ring = new_drawing("Circle")
ring.NumSides = 64
ring.Thickness = 1
ring.Filled = false
ring.Color = Color3.fromRGB(255, 255, 255)
ring.Transparency = 0.55
ring.Visible = false

--[[ ui: MacLib ]]
--
-- The menu is MacLib now, not the Drawing list this file used to draw. MacLib
-- builds real Instances - ScreenGui, Frames, TextButtons - so it survives an
-- executor without Drawing, and it gives the sidebar, tabs and widgets that were
-- asked for.
--
-- CFG stays the single source of truth. Every widget here only WRITES CFG (or
-- calls the same start/stop hooks the old menu called), and the ESP and the aim
-- read CFG exactly as before. That is deliberate: the ESP is working and the
-- aim is working, and a new UI is not a reason to touch either of them.
--
-- MacLib is embedded below as a string rather than required, because this file
-- has to stay a single script: one live-reload, one order, and the loader stays
-- honest about which version of the library is running.

local MACLIB_SRC = [=[--[[
!! OUTDATED REPOSITORY !! Please use the new repository:
https://github.com/biggaboy212/Maclib/tree/main
]]

local MacLib = {}

--// Services
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

--// Variables
local isStudio = RunService:IsStudio()
local LocalPlayer = Players.LocalPlayer

local windowState
local acrylicBlur
local orientationConnection
local hasGlobalSetting

local tabs = {}
local currentTabInstance = nil
local tabIndex = 0

local assets = {
	interFont = "rbxassetid://12187365364",
	userInfoBlurred = "rbxassetid://18824089198",
	toggleBackground = "rbxassetid://18772190202",
	togglerHead = "rbxassetid://18772309008",
	buttonImage = "rbxassetid://10709791437",
	searchIcon = "rbxassetid://86737463322606"
}

--// Functions
local function Tween(instance, tweeninfo, propertytable)
	return TweenService:Create(instance, tweeninfo, propertytable)
end

--// Library Functions
function MacLib:Window(Settings)
	local WindowFunctions = {}
	if Settings.AcrylicBlur ~= nil then
		acrylicBlur = Settings.AcrylicBlur
	else
		acrylicBlur = true
	end

	local macLib = Instance.new("ScreenGui")
	macLib.Name = "MacLib"
	macLib.ResetOnSpawn = false
	macLib.DisplayOrder = 100
	macLib.IgnoreGuiInset = true
	macLib.ScreenInsets = Enum.ScreenInsets.None
	macLib.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- [LF patch] The vendored library wrote straight to CoreGui with no fallback.
	-- Places that guard CoreGui made that line throw, and because it is the first
	-- thing Window() does, the whole menu died on it. This tries, in order: the
	-- executor's hidden container, CoreGui, then PlayerGui. The original line is
	-- kept verbatim as the last case, so wherever it already worked, nothing about
	-- the result changes.
	do
		local placed = false
		local function try(parent)
			if placed or parent == nil then return end
			local ok = pcall(function()
				macLib.Parent = parent
			end)
			placed = ok and macLib.Parent ~= nil
		end
		if not isStudio then
			pcall(function() try(gethui and gethui()) end)
			pcall(function() try(game:GetService("CoreGui")) end)
		end
		pcall(function()
			try(Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
		end)
		if not placed then
			macLib.Parent = (isStudio and LocalPlayer.PlayerGui) or game:GetService("CoreGui")
		end
	end

	local notifications = Instance.new("Frame")
	notifications.Name = "Notifications"
	notifications.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	notifications.BackgroundTransparency = 1
	notifications.BorderColor3 = Color3.fromRGB(0, 0, 0)
	notifications.BorderSizePixel = 0
	notifications.Size = UDim2.fromScale(1, 1)
	notifications.Parent = macLib
	notifications.ZIndex = 2

	local notificationsUIListLayout = Instance.new("UIListLayout")
	notificationsUIListLayout.Name = "NotificationsUIListLayout"
	notificationsUIListLayout.Padding = UDim.new(0, 10)
	notificationsUIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	notificationsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	notificationsUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	notificationsUIListLayout.Parent = notifications

	local notificationsUIPadding = Instance.new("UIPadding")
	notificationsUIPadding.Name = "NotificationsUIPadding"
	notificationsUIPadding.PaddingBottom = UDim.new(0, 10)
	notificationsUIPadding.PaddingLeft = UDim.new(0, 10)
	notificationsUIPadding.PaddingRight = UDim.new(0, 10)
	notificationsUIPadding.PaddingTop = UDim.new(0, 10)
	notificationsUIPadding.Parent = notifications

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	base.BackgroundTransparency = Settings.BackgroundTransparency
		or (Settings.AcrylicBlur and 0.05 or 0)
	base.BorderColor3 = Color3.fromRGB(0, 0, 0)
	base.BorderSizePixel = 0
	base.Position = UDim2.fromScale(0.5, 0.5)
	base.Size = Settings.Size or UDim2.fromOffset(868, 650)

	local baseUIScale = Instance.new("UIScale")
	baseUIScale.Name = "BaseUIScale"
	baseUIScale.Parent = base

	local baseUICorner = Instance.new("UICorner")
	baseUICorner.Name = "BaseUICorner"
	baseUICorner.CornerRadius = UDim.new(0, 10)
	baseUICorner.Parent = base

	local baseUIStroke = Instance.new("UIStroke")
	baseUIStroke.Name = "BaseUIStroke"
	baseUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	baseUIStroke.Color = Color3.fromRGB(255, 255, 255)
	baseUIStroke.Transparency = 0.9
	baseUIStroke.Parent = base

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sidebar.BackgroundTransparency = 1
	sidebar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	sidebar.BorderSizePixel = 0
	sidebar.Position = UDim2.fromScale(-3.52e-08, 4.69e-08)
	sidebar.Size = UDim2.fromScale(0.325, 1)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(1, 0)
	divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider.BackgroundTransparency = 0.9
	divider.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromScale(1, 0)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Parent = sidebar

	local windowControls = Instance.new("Frame")
	windowControls.Name = "WindowControls"
	windowControls.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	windowControls.BackgroundTransparency = 1
	windowControls.BorderColor3 = Color3.fromRGB(0, 0, 0)
	windowControls.BorderSizePixel = 0
	windowControls.Size = UDim2.new(1, 0, 0, 31)

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundColor3 = Color3.fromRGB(119, 174, 94)
	controls.BackgroundTransparency = 1
	controls.BorderColor3 = Color3.fromRGB(0, 0, 0)
	controls.BorderSizePixel = 0
	controls.Size = UDim2.fromScale(1, 1)

	local uIListLayout = Instance.new("UIListLayout")
	uIListLayout.Name = "UIListLayout"
	uIListLayout.Padding = UDim.new(0, 5)
	uIListLayout.FillDirection = Enum.FillDirection.Horizontal
	uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	uIListLayout.Parent = controls

	local uIPadding = Instance.new("UIPadding")
	uIPadding.Name = "UIPadding"
	uIPadding.PaddingLeft = UDim.new(0, 11)
	uIPadding.Parent = controls
	
	local windowControlSettings = {
		sizes = { enabled = UDim2.fromOffset(8, 8), disabled = UDim2.fromOffset(7, 7) },
		transparencies = { enabled = 0, disabled = 1 },
		strokeTransparency = 0.9,
	}

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BaseUIStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = windowControlSettings.strokeTransparency

	local exit = Instance.new("TextButton")
	exit.Name = "Exit"
	exit.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	exit.Text = ""
	exit.TextColor3 = Color3.fromRGB(0, 0, 0)
	exit.TextSize = 14
	exit.AutoButtonColor = false
	exit.BackgroundColor3 = Color3.fromRGB(250, 93, 86)
	exit.BorderColor3 = Color3.fromRGB(0, 0, 0)
	exit.BorderSizePixel = 0

	local uICorner = Instance.new("UICorner")
	uICorner.Name = "UICorner"
	uICorner.CornerRadius = UDim.new(1, 0)
	uICorner.Parent = exit

	exit.Parent = controls

	local minimize = Instance.new("TextButton")
	minimize.Name = "Minimize"
	minimize.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	minimize.Text = ""
	minimize.TextColor3 = Color3.fromRGB(0, 0, 0)
	minimize.TextSize = 14
	minimize.AutoButtonColor = false
	minimize.BackgroundColor3 = Color3.fromRGB(252, 190, 57)
	minimize.BorderColor3 = Color3.fromRGB(0, 0, 0)
	minimize.BorderSizePixel = 0
	minimize.LayoutOrder = 1
	
	local uICorner1 = Instance.new("UICorner")
	uICorner1.Name = "UICorner"
	uICorner1.CornerRadius = UDim.new(1, 0)
	uICorner1.Parent = minimize
	
	minimize.Parent = controls

	local maximize = Instance.new("TextButton")
	maximize.Name = "Maximize"
	maximize.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	maximize.Text = ""
	maximize.TextColor3 = Color3.fromRGB(0, 0, 0)
	maximize.TextSize = 14
	maximize.AutoButtonColor = false
	maximize.BackgroundColor3 = Color3.fromRGB(119, 174, 94)
	maximize.BorderColor3 = Color3.fromRGB(0, 0, 0)
	maximize.BorderSizePixel = 0
	maximize.LayoutOrder = 1

	local uICorner2 = Instance.new("UICorner")
	uICorner2.Name = "UICorner"
	uICorner2.CornerRadius = UDim.new(1, 0)
	uICorner2.Parent = maximize

	maximize.Parent = controls
	
	local function applyState(button, enabled)
		local size = enabled and windowControlSettings.sizes.enabled or windowControlSettings.sizes.disabled
		local transparency = enabled and windowControlSettings.transparencies.enabled or windowControlSettings.transparencies.disabled

		button.Size = size
		button.BackgroundTransparency = transparency
		button.Active = enabled
		button.Interactable = enabled

		for _, child in ipairs(button:GetChildren()) do
			if child:IsA("UIStroke") then
				child.Transparency = transparency
			end
		end
		if not enabled then
			stroke:Clone().Parent = button
		end
	end

	applyState(maximize, false)
	
	local controlsList = {exit, minimize}
	for _, button in pairs(controlsList) do
		local buttonName = button.Name
		local isEnabled = true

		if Settings.DisabledWindowControls and table.find(Settings.DisabledWindowControls, buttonName) then
			isEnabled = false
		end

		applyState(button, isEnabled)
	end

	-- HideWindowControls removes the three dots outright. DisabledWindowControls
	-- only fades them: applyState leaves a 7px ghost with a cloned stroke, so they
	-- were still visibly there. When the window is driven entirely by keybind the
	-- dots are noise, and the user asked for them gone.
	if Settings.HideWindowControls then
		controls.Visible = false
	end
	controls.Parent = windowControls

	local divider1 = Instance.new("Frame")
	divider1.Name = "Divider"
	divider1.AnchorPoint = Vector2.new(0, 1)
	divider1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider1.BackgroundTransparency = 0.9
	divider1.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider1.BorderSizePixel = 0
	divider1.Position = UDim2.fromScale(0, 1)
	divider1.Size = UDim2.new(1, 0, 0, 1)
	divider1.Parent = windowControls

	windowControls.Parent = sidebar

	local information = Instance.new("Frame")
	information.Name = "Information"
	information.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	information.BackgroundTransparency = 1
	information.BorderColor3 = Color3.fromRGB(0, 0, 0)
	information.BorderSizePixel = 0
	information.Position = UDim2.fromOffset(0, 31)
	information.Size = UDim2.new(1, 0, 0, 60)

	local divider2 = Instance.new("Frame")
	divider2.Name = "Divider"
	divider2.AnchorPoint = Vector2.new(0, 1)
	divider2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider2.BackgroundTransparency = 0.9
	divider2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider2.BorderSizePixel = 0
	divider2.Position = UDim2.fromScale(0, 1)
	divider2.Size = UDim2.new(1, 0, 0, 1)
	divider2.Parent = information

	local informationHolder = Instance.new("Frame")
	informationHolder.Name = "InformationHolder"
	informationHolder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	informationHolder.BackgroundTransparency = 1
	informationHolder.BorderColor3 = Color3.fromRGB(0, 0, 0)
	informationHolder.BorderSizePixel = 0
	informationHolder.Size = UDim2.fromScale(1, 1)

	local informationHolderUIPadding = Instance.new("UIPadding")
	informationHolderUIPadding.Name = "InformationHolderUIPadding"
	informationHolderUIPadding.PaddingBottom = UDim.new(0, 10)
	informationHolderUIPadding.PaddingLeft = UDim.new(0, 23)
	informationHolderUIPadding.PaddingRight = UDim.new(0, 22)
	informationHolderUIPadding.PaddingTop = UDim.new(0, 10)
	informationHolderUIPadding.Parent = informationHolder

	local globalSettingsButton = Instance.new("ImageButton")
	globalSettingsButton.Name = "GlobalSettingsButton"
	globalSettingsButton.Image = "rbxassetid://18767849817"
	globalSettingsButton.ImageTransparency = 0.4
	globalSettingsButton.AnchorPoint = Vector2.new(1, 0.5)
	globalSettingsButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	globalSettingsButton.BackgroundTransparency = 1
	globalSettingsButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	globalSettingsButton.BorderSizePixel = 0
	globalSettingsButton.Position = UDim2.fromScale(1, 0.5)
	globalSettingsButton.Size = UDim2.fromOffset(15, 15)
	globalSettingsButton.Parent = informationHolder

	local function ChangeGlobalSettingsButtonState(State)
		if State == "Default" then
			Tween(globalSettingsButton, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.4
			}):Play()
		elseif State == "Hover" then
			Tween(globalSettingsButton, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.2
			}):Play()
		end
	end

	globalSettingsButton.MouseEnter:Connect(function()
		ChangeGlobalSettingsButtonState("Hover")
	end)
	globalSettingsButton.MouseLeave:Connect(function()
		ChangeGlobalSettingsButtonState("Default")
	end)

	local titleFrame = Instance.new("Frame")
	titleFrame.Name = "TitleFrame"
	titleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	titleFrame.BackgroundTransparency = 1
	titleFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	titleFrame.BorderSizePixel = 0
	titleFrame.Size = UDim2.fromScale(1, 1)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.FontFace = Font.new(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	title.Text = Settings.Title
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.RichText = true
	title.TextSize = 20
	title.TextTransparency = 0.2
	title.TextTruncate = Enum.TextTruncate.SplitWord
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	title.BackgroundTransparency = 1
	title.BorderColor3 = Color3.fromRGB(0, 0, 0)
	title.BorderSizePixel = 0
	title.Size = UDim2.new(1, -20, 0, 0)
	title.Parent = titleFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.FontFace = Font.new(
		assets.interFont,
		Enum.FontWeight.Medium,
		Enum.FontStyle.Normal
	)
	subtitle.RichText = true
	subtitle.Text = Settings.Subtitle
	subtitle.RichText = true
	subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.TextSize = 12
	subtitle.TextTransparency = 0.7
	subtitle.TextTruncate = Enum.TextTruncate.SplitWord
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.BackgroundTransparency = 1
	subtitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	subtitle.BorderSizePixel = 0
	subtitle.LayoutOrder = 1
	subtitle.Size = UDim2.new(1, -20, 0, 0)
	subtitle.Parent = titleFrame

	local titleFrameUIListLayout = Instance.new("UIListLayout")
	titleFrameUIListLayout.Name = "TitleFrameUIListLayout"
	titleFrameUIListLayout.Padding = UDim.new(0, 3)
	titleFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleFrameUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleFrameUIListLayout.Parent = titleFrame

	titleFrame.Parent = informationHolder

	informationHolder.Parent = information

	information.Parent = sidebar

	local sidebarGroup = Instance.new("Frame")
	sidebarGroup.Name = "SidebarGroup"
	sidebarGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sidebarGroup.BackgroundTransparency = 1
	sidebarGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
	sidebarGroup.BorderSizePixel = 0
	sidebarGroup.Position = UDim2.fromOffset(0, 91)
	sidebarGroup.Size = UDim2.new(1, 0, 1, -91)

	local userInfo = Instance.new("Frame")
	userInfo.Name = "UserInfo"
	userInfo.AnchorPoint = Vector2.new(0, 1)
	userInfo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	userInfo.BackgroundTransparency = 1
	userInfo.BorderColor3 = Color3.fromRGB(0, 0, 0)
	userInfo.BorderSizePixel = 0
	userInfo.Position = UDim2.fromScale(0, 1)
	userInfo.Size = UDim2.new(1, 0, 0, 107)

	local informationGroup = Instance.new("Frame")
	informationGroup.Name = "InformationGroup"
	informationGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	informationGroup.BackgroundTransparency = 1
	informationGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
	informationGroup.BorderSizePixel = 0
	informationGroup.Size = UDim2.fromScale(1, 1)

	local informationGroupUIPadding = Instance.new("UIPadding")
	informationGroupUIPadding.Name = "InformationGroupUIPadding"
	informationGroupUIPadding.PaddingBottom = UDim.new(0, 17)
	informationGroupUIPadding.PaddingLeft = UDim.new(0, 25)
	informationGroupUIPadding.Parent = informationGroup

	local informationGroupUIListLayout = Instance.new("UIListLayout")
	informationGroupUIListLayout.Name = "InformationGroupUIListLayout"
	informationGroupUIListLayout.FillDirection = Enum.FillDirection.Horizontal
	informationGroupUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	informationGroupUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	informationGroupUIListLayout.Parent = informationGroup

	local userId = LocalPlayer.UserId
	local thumbType = Enum.ThumbnailType.AvatarBust
	local thumbSize = Enum.ThumbnailSize.Size48x48
	local headshotImage, isReady = Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	headshot.BackgroundTransparency = 1
	headshot.BorderColor3 = Color3.fromRGB(0, 0, 0)
	headshot.BorderSizePixel = 0
	headshot.Size = UDim2.fromOffset(32, 32)
	headshot.Image = (isReady and headshotImage) or "rbxassetid://0"

	local uICorner3 = Instance.new("UICorner")
	uICorner3.Name = "UICorner"
	uICorner3.CornerRadius = UDim.new(1, 0)
	uICorner3.Parent = headshot

	local baseUIStroke2 = Instance.new("UIStroke")
	baseUIStroke2.Name = "BaseUIStroke"
	baseUIStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	baseUIStroke2.Color = Color3.fromRGB(255, 255, 255)
	baseUIStroke2.Transparency = 0.9
	baseUIStroke2.Parent = headshot

	headshot.Parent = informationGroup

	local userAndDisplayFrame = Instance.new("Frame")
	userAndDisplayFrame.Name = "UserAndDisplayFrame"
	userAndDisplayFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	userAndDisplayFrame.BackgroundTransparency = 1
	userAndDisplayFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	userAndDisplayFrame.BorderSizePixel = 0
	userAndDisplayFrame.LayoutOrder = 1
	userAndDisplayFrame.Size = UDim2.new(1, -42, 0, 32)

	local displayName = Instance.new("TextLabel")
	displayName.Name = "DisplayName"
	displayName.FontFace = Font.new(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	displayName.Text = LocalPlayer.DisplayName
	displayName.TextColor3 = Color3.fromRGB(255, 255, 255)
	displayName.TextSize = 13
	displayName.TextTransparency = 0.2
	displayName.TextTruncate = Enum.TextTruncate.SplitWord
	displayName.TextXAlignment = Enum.TextXAlignment.Left
	displayName.TextYAlignment = Enum.TextYAlignment.Top
	displayName.AutomaticSize = Enum.AutomaticSize.XY
	displayName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	displayName.BackgroundTransparency = 1
	displayName.BorderColor3 = Color3.fromRGB(0, 0, 0)
	displayName.BorderSizePixel = 0
	displayName.Parent = userAndDisplayFrame
	displayName.Size = UDim2.fromScale(1,0)

	local userAndDisplayFrameUIPadding = Instance.new("UIPadding")
	userAndDisplayFrameUIPadding.Name = "UserAndDisplayFrameUIPadding"
	userAndDisplayFrameUIPadding.PaddingLeft = UDim.new(0, 8)
	userAndDisplayFrameUIPadding.PaddingTop = UDim.new(0, 3)
	userAndDisplayFrameUIPadding.Parent = userAndDisplayFrame

	local userAndDisplayFrameUIListLayout = Instance.new("UIListLayout")
	userAndDisplayFrameUIListLayout.Name = "UserAndDisplayFrameUIListLayout"
	userAndDisplayFrameUIListLayout.Padding = UDim.new(0, 1)
	userAndDisplayFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	userAndDisplayFrameUIListLayout.Parent = userAndDisplayFrame

	local username = Instance.new("TextLabel")
	username.Name = "Username"
	username.FontFace = Font.new(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	username.Text = "@"..LocalPlayer.Name
	username.TextColor3 = Color3.fromRGB(255, 255, 255)
	username.TextSize = 12
	username.TextTransparency = 0.8
	username.TextTruncate = Enum.TextTruncate.SplitWord
	username.TextXAlignment = Enum.TextXAlignment.Left
	username.TextYAlignment = Enum.TextYAlignment.Top
	username.AutomaticSize = Enum.AutomaticSize.XY
	username.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	username.BackgroundTransparency = 1
	username.BorderColor3 = Color3.fromRGB(0, 0, 0)
	username.BorderSizePixel = 0
	username.LayoutOrder = 1
	username.Parent = userAndDisplayFrame
	username.Size = UDim2.fromScale(1,0)

	userAndDisplayFrame.Parent = informationGroup

	informationGroup.Parent = userInfo

	local userInfoUIPadding = Instance.new("UIPadding")
	userInfoUIPadding.Name = "UserInfoUIPadding"
	userInfoUIPadding.PaddingLeft = UDim.new(0, 10)
	userInfoUIPadding.PaddingRight = UDim.new(0, 10)
	userInfoUIPadding.Parent = userInfo

	userInfo.Parent = sidebarGroup

	local sidebarGroupUIPadding = Instance.new("UIPadding")
	sidebarGroupUIPadding.Name = "SidebarGroupUIPadding"
	sidebarGroupUIPadding.PaddingLeft = UDim.new(0, 10)
	sidebarGroupUIPadding.PaddingRight = UDim.new(0, 10)
	sidebarGroupUIPadding.PaddingTop = UDim.new(0, 31)
	sidebarGroupUIPadding.Parent = sidebarGroup

	local tabSwitchers = Instance.new("Frame")
	tabSwitchers.Name = "TabSwitchers"
	tabSwitchers.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tabSwitchers.BackgroundTransparency = 1
	tabSwitchers.BorderColor3 = Color3.fromRGB(0, 0, 0)
	tabSwitchers.BorderSizePixel = 0
	tabSwitchers.Size = UDim2.new(1, 0, 1, -107)

	local tabSwitchersScrollingFrame = Instance.new("ScrollingFrame")
	tabSwitchersScrollingFrame.Name = "TabSwitchersScrollingFrame"
	tabSwitchersScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabSwitchersScrollingFrame.BottomImage = ""
	tabSwitchersScrollingFrame.CanvasSize = UDim2.new()
	tabSwitchersScrollingFrame.ScrollBarImageTransparency = 0.8
	tabSwitchersScrollingFrame.ScrollBarThickness = 1
	tabSwitchersScrollingFrame.TopImage = ""
	tabSwitchersScrollingFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tabSwitchersScrollingFrame.BackgroundTransparency = 1
	tabSwitchersScrollingFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	tabSwitchersScrollingFrame.BorderSizePixel = 0
	tabSwitchersScrollingFrame.Size = UDim2.fromScale(1, 1)

	local tabSwitchersScrollingFrameUIListLayout = Instance.new("UIListLayout")
	tabSwitchersScrollingFrameUIListLayout.Name = "TabSwitchersScrollingFrameUIListLayout"
	tabSwitchersScrollingFrameUIListLayout.Padding = UDim.new(0, 17)
	tabSwitchersScrollingFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabSwitchersScrollingFrameUIListLayout.Parent = tabSwitchersScrollingFrame

	local tabSwitchersScrollingFrameUIPadding = Instance.new("UIPadding")
	tabSwitchersScrollingFrameUIPadding.Name = "TabSwitchersScrollingFrameUIPadding"
	tabSwitchersScrollingFrameUIPadding.PaddingTop = UDim.new(0, 2)
	tabSwitchersScrollingFrameUIPadding.Parent = tabSwitchersScrollingFrame

	tabSwitchersScrollingFrame.Parent = tabSwitchers

	tabSwitchers.Parent = sidebarGroup

	sidebarGroup.Parent = sidebar

	sidebar.Parent = base

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(1, 0)
	content.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	content.BackgroundTransparency = 1
	content.BorderColor3 = Color3.fromRGB(0, 0, 0)
	content.BorderSizePixel = 0
	content.Position = UDim2.fromScale(1, 4.69e-08)
	content.Size = UDim2.fromScale(0.675, 1)

	local topbar = Instance.new("Frame")
	topbar.Name = "Topbar"
	topbar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	topbar.BackgroundTransparency = 1
	topbar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	topbar.BorderSizePixel = 0
	topbar.Size = UDim2.new(1, 0, 0, 63)

	local divider4 = Instance.new("Frame")
	divider4.Name = "Divider"
	divider4.AnchorPoint = Vector2.new(0, 1)
	divider4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider4.BackgroundTransparency = 0.9
	divider4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider4.BorderSizePixel = 0
	divider4.Position = UDim2.fromScale(0, 1)
	divider4.Size = UDim2.new(1, 0, 0, 1)
	divider4.Parent = topbar

	local elements = Instance.new("Frame")
	elements.Name = "Elements"
	elements.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	elements.BackgroundTransparency = 1
	elements.BorderColor3 = Color3.fromRGB(0, 0, 0)
	elements.BorderSizePixel = 0
	elements.Size = UDim2.fromScale(1, 1)

	local uIPadding2 = Instance.new("UIPadding")
	uIPadding2.Name = "UIPadding"
	uIPadding2.PaddingLeft = UDim.new(0, 20)
	uIPadding2.PaddingRight = UDim.new(0, 20)
	uIPadding2.Parent = elements

	local moveIcon = Instance.new("ImageButton")
	moveIcon.Name = "MoveIcon"
	moveIcon.Image = "rbxassetid://10734900011"
	moveIcon.ImageTransparency = 0.5
	moveIcon.AnchorPoint = Vector2.new(1, 0.5)
	moveIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	moveIcon.BackgroundTransparency = 1
	moveIcon.BorderColor3 = Color3.fromRGB(0, 0, 0)
	moveIcon.BorderSizePixel = 0
	moveIcon.Position = UDim2.fromScale(1, 0.5)
	moveIcon.Size = UDim2.fromOffset(15, 15)
	moveIcon.Parent = elements
	moveIcon.Visible = not Settings.DragStyle or Settings.DragStyle == 1
	
	local interact = Instance.new("TextButton")
	interact.Name = "Interact"
	interact.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	interact.Text = ""
	interact.TextColor3 = Color3.fromRGB(0, 0, 0)
	interact.TextSize = 14
	interact.AnchorPoint = Vector2.new(0.5, 0.5)
	interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	interact.BackgroundTransparency = 1
	interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
	interact.BorderSizePixel = 0
	interact.Position = UDim2.fromScale(0.5, 0.5)
	interact.Size = UDim2.fromOffset(30, 30)
	interact.Parent = moveIcon

	local function ChangemoveIconState(State)
		if State == "Default" then
			Tween(moveIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.5
			}):Play()
		elseif State == "Hover" then
			Tween(moveIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.2
			}):Play()
		end
	end

	interact.MouseEnter:Connect(function()
		ChangemoveIconState("Hover")
	end)
	interact.MouseLeave:Connect(function()
		ChangemoveIconState("Default")
	end)

	local dragging_ = false
	local dragInput
	local dragStart
	local startPos

	local function update(input)
		local delta = input.Position - dragStart
		base.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end

	local function onDragStart(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging_ = true
			dragStart = input.Position
			startPos = base.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging_ = false
				end
			end)
		end
	end

	local function onDragUpdate(input)
		if dragging_ and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			dragInput = input
		end
	end

	if not Settings.DragStyle or Settings.DragStyle == 1 then
		interact.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				onDragStart(input)
			end
		end)

		interact.InputChanged:Connect(onDragUpdate)

		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging_ then
				update(input)
			end
		end)

		interact.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging_ = false
			end
		end)
	elseif Settings.DragStyle == 2 then
		base.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				onDragStart(input)
			end
		end)

		base.InputChanged:Connect(onDragUpdate)

		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging_ then
				update(input)
			end
		end)

		base.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging_ = false
			end
		end)
	end

	local currentTab = Instance.new("TextLabel")
	currentTab.Name = "CurrentTab"
	currentTab.FontFace = Font.new(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	currentTab.RichText = true
	currentTab.Text = "Tab"
	currentTab.RichText = true
	currentTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	currentTab.TextSize = 15
	currentTab.TextTransparency = 0.5
	currentTab.TextTruncate = Enum.TextTruncate.SplitWord
	currentTab.TextXAlignment = Enum.TextXAlignment.Left
	currentTab.TextYAlignment = Enum.TextYAlignment.Top
	currentTab.AnchorPoint = Vector2.new(0, 0.5)
	currentTab.AutomaticSize = Enum.AutomaticSize.Y
	currentTab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	currentTab.BackgroundTransparency = 1
	currentTab.BorderColor3 = Color3.fromRGB(0, 0, 0)
	currentTab.BorderSizePixel = 0
	currentTab.Position = UDim2.fromScale(0, 0.5)
	currentTab.Size = UDim2.fromScale(0.9, 0)
	currentTab.Parent = elements

	elements.Parent = topbar

	topbar.Parent = content

	content.Parent = base

	local globalSettings = Instance.new("Frame")
	globalSettings.Name = "GlobalSettings"
	globalSettings.AutomaticSize = Enum.AutomaticSize.XY
	globalSettings.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	globalSettings.BorderColor3 = Color3.fromRGB(0, 0, 0)
	globalSettings.BorderSizePixel = 0
	globalSettings.Position = UDim2.fromScale(0.298, 0.104)

	local globalSettingsUIStroke = Instance.new("UIStroke")
	globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
	globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
	globalSettingsUIStroke.Transparency = 0.9
	globalSettingsUIStroke.Parent = globalSettings

	local globalSettingsUICorner = Instance.new("UICorner")
	globalSettingsUICorner.Name = "GlobalSettingsUICorner"
	globalSettingsUICorner.CornerRadius = UDim.new(0, 10)
	globalSettingsUICorner.Parent = globalSettings

	local globalSettingsUIPadding = Instance.new("UIPadding")
	globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
	globalSettingsUIPadding.PaddingBottom = UDim.new(0, 10)
	globalSettingsUIPadding.PaddingTop = UDim.new(0, 10)
	globalSettingsUIPadding.Parent = globalSettings

	local globalSettingsUIListLayout = Instance.new("UIListLayout")
	globalSettingsUIListLayout.Name = "GlobalSettingsUIListLayout"
	globalSettingsUIListLayout.Padding = UDim.new(0, 5)
	globalSettingsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	globalSettingsUIListLayout.Parent = globalSettings

	local globalSettingsUIScale = Instance.new("UIScale")
	globalSettingsUIScale.Name = "GlobalSettingsUIScale"
	globalSettingsUIScale.Scale = 1e-07
	globalSettingsUIScale.Parent = globalSettings
	globalSettings.Parent = base
	base.Parent = macLib

	function WindowFunctions:UpdateTitle(NewTitle)
		title.Text = NewTitle
	end

	function WindowFunctions:UpdateSubtitle(NewSubtitle)
		subtitle.Text = NewSubtitle
	end

	local hovering
	local toggled = globalSettingsUIScale.Scale == 1 and true or false
	local function toggle()
		if not toggled then
			local intween = Tween(globalSettingsUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 1
			})
			intween:Play()
			intween.Completed:Wait()
			toggled = true
		elseif toggled then
			local outtween = Tween(globalSettingsUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 0
			})
			outtween:Play()
			outtween.Completed:Wait()
			toggled = false
		end
	end
	globalSettingsButton.MouseButton1Click:Connect(function()
		if not hasGlobalSetting then return end
		toggle()
	end)
	globalSettings.MouseEnter:Connect(function()
		hovering = true
	end)
	globalSettings.MouseLeave:Connect(function()
		hovering = false
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 and toggled and not hovering then
			toggle()
		end
	end)

	local BlurTarget = base

	local HS = game:GetService('HttpService')
	local camera = workspace.CurrentCamera
	local MTREL = "Glass"
	local binds = {}
	local wedgeguid = HS:GenerateGUID(true)

	local DepthOfField

	for _,v in pairs(game:GetService("Lighting"):GetChildren()) do
		if not v:IsA("DepthOfFieldEffect") and v:HasTag(".") then
			DepthOfField = Instance.new('DepthOfFieldEffect', game:GetService('Lighting'))
			DepthOfField.FarIntensity = 0
			DepthOfField.FocusDistance = 51.6
			DepthOfField.InFocusRadius = 50
			DepthOfField.NearIntensity = 1
			DepthOfField.Name = HS:GenerateGUID(true)
			DepthOfField:AddTag(".")
		elseif v:IsA("DepthOfFieldEffect") and v:HasTag(".") then
			DepthOfField = v
		end
	end

	if not DepthOfField then
		DepthOfField = Instance.new('DepthOfFieldEffect', game:GetService('Lighting'))
		DepthOfField.FarIntensity = 0
		DepthOfField.FocusDistance = 51.6
		DepthOfField.InFocusRadius = 50
		DepthOfField.NearIntensity = 1
		DepthOfField.Name = HS:GenerateGUID(true)
		DepthOfField:AddTag(".")
	end

	local frame = Instance.new('Frame')
	frame.Parent = BlurTarget
	frame.Size = UDim2.new(0.97, 0, 0.97, 0)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Name = HS:GenerateGUID(true)

	do
		local function IsNotNaN(x)
			return x == x
		end
		local continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		while not continue do
			RunService.RenderStepped:wait()
			continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		end
	end

	local DrawQuad; do
		local acos, max, pi, sqrt = math.acos, math.max, math.pi, math.sqrt
		local sz = 0.2

		local function DrawTriangle(v1, v2, v3, p0, p1)
			local s1 = (v1 - v2).magnitude
			local s2 = (v2 - v3).magnitude
			local s3 = (v3 - v1).magnitude
			local smax = max(s1, s2, s3)
			local A, B, C
			if s1 == smax then
				A, B, C = v1, v2, v3
			elseif s2 == smax then
				A, B, C = v2, v3, v1
			elseif s3 == smax then
				A, B, C = v3, v1, v2
			end

			local para = ( (B-A).x*(C-A).x + (B-A).y*(C-A).y + (B-A).z*(C-A).z ) / (A-B).magnitude
			local perp = sqrt((C-A).magnitude^2 - para*para)
			local dif_para = (A - B).magnitude - para

			local st = CFrame.new(B, A)
			local za = CFrame.Angles(pi/2,0,0)

			local cf0 = st

			local Top_Look = (cf0 * za).lookVector
			local Mid_Point = A + CFrame.new(A, B).lookVector * para
			local Needed_Look = CFrame.new(Mid_Point, C).lookVector
			local dot = Top_Look.x*Needed_Look.x + Top_Look.y*Needed_Look.y + Top_Look.z*Needed_Look.z

			local ac = CFrame.Angles(0, 0, acos(dot))

			cf0 = cf0 * ac
			if ((cf0 * za).lookVector - Needed_Look).magnitude > 0.01 then
				cf0 = cf0 * CFrame.Angles(0, 0, -2*acos(dot))
			end
			cf0 = cf0 * CFrame.new(0, perp/2, -(dif_para + para/2))

			local cf1 = st * ac * CFrame.Angles(0, pi, 0)
			if ((cf1 * za).lookVector - Needed_Look).magnitude > 0.01 then
				cf1 = cf1 * CFrame.Angles(0, 0, 2*acos(dot))
			end
			cf1 = cf1 * CFrame.new(0, perp/2, dif_para/2)

			if not p0 then
				p0 = Instance.new('Part')
				p0.FormFactor = 'Custom'
				p0.TopSurface = 0
				p0.BottomSurface = 0
				p0.Anchored = true
				p0.CanCollide = false
				p0.CastShadow = false
				p0.Material = MTREL
				p0.Size = Vector3.new(sz, sz, sz)
				p0.Name = HS:GenerateGUID(true)
				local mesh = Instance.new('SpecialMesh', p0)
				mesh.MeshType = 2
				mesh.Name = wedgeguid
			end
			p0[wedgeguid].Scale = Vector3.new(0, perp/sz, para/sz)
			p0.CFrame = cf0

			if not p1 then
				p1 = p0:clone()
			end
			p1[wedgeguid].Scale = Vector3.new(0, perp/sz, dif_para/sz)
			p1.CFrame = cf1

			return p0, p1
		end

		function DrawQuad(v1, v2, v3, v4, parts)
			parts[1], parts[2] = DrawTriangle(v1, v2, v3, parts[1], parts[2])
			parts[3], parts[4] = DrawTriangle(v3, v2, v4, parts[3], parts[4])
		end
	end

	if binds[frame] then
		return binds[frame].parts
	end

	local parts = {}

	local parents = {}
	do
		local function add(child)
			if child:IsA'GuiObject' then
				parents[#parents + 1] = child
				add(child.Parent)
			end
		end
		add(frame)
	end

	local function IsVisible(instance)
		while instance do
			if instance:IsA("GuiObject") then
				if not instance.Visible then
					return false
				end
			elseif instance:IsA("ScreenGui") then
				if not instance.Enabled then
					return false
				end
				break
			end
			instance = instance.Parent
		end
		return true
	end

	local function UpdateOrientation(fetchProps)
		if not IsVisible(frame) or not acrylicBlur then
			for _, pt in pairs(parts) do
				pt.Parent = nil
				DepthOfField.Enabled = false
			end
			return
		end
		DepthOfField.Enabled = true
		local properties = {
			Transparency = 0.98;
			BrickColor = BrickColor.new('Institutional white');
		}
		local zIndex = 1 - 0.05*frame.ZIndex

		local tl, br = frame.AbsolutePosition, frame.AbsolutePosition + frame.AbsoluteSize
		local tr, bl = Vector2.new(br.x, tl.y), Vector2.new(tl.x, br.y)
		do
			local rot = 0;
			for _, v in ipairs(parents) do
				rot = rot + v.Rotation
			end
			if rot ~= 0 and rot%180 ~= 0 then
				local mid = tl:lerp(br, 0.5)
				local s, c = math.sin(math.rad(rot)), math.cos(math.rad(rot))
				local vec = tl
				tl = Vector2.new(c*(tl.x - mid.x) - s*(tl.y - mid.y), s*(tl.x - mid.x) + c*(tl.y - mid.y)) + mid
				tr = Vector2.new(c*(tr.x - mid.x) - s*(tr.y - mid.y), s*(tr.x - mid.x) + c*(tr.y - mid.y)) + mid
				bl = Vector2.new(c*(bl.x - mid.x) - s*(bl.y - mid.y), s*(bl.x - mid.x) + c*(bl.y - mid.y)) + mid
				br = Vector2.new(c*(br.x - mid.x) - s*(br.y - mid.y), s*(br.x - mid.x) + c*(br.y - mid.y)) + mid
			end
		end
		DrawQuad(
			camera:ScreenPointToRay(tl.x, tl.y, zIndex).Origin, 
			camera:ScreenPointToRay(tr.x, tr.y, zIndex).Origin, 
			camera:ScreenPointToRay(bl.x, bl.y, zIndex).Origin, 
			camera:ScreenPointToRay(br.x, br.y, zIndex).Origin, 
			parts
		)
		if fetchProps then
			for _, pt in pairs(parts) do
				pt.Parent = camera
			end
			for propName, propValue in pairs(properties) do
				for _, pt in pairs(parts) do
					pt[propName] = propValue
				end
			end
		end
	end

	UpdateOrientation(true)

	-- Held so Unload can drop it. The library never disconnected this, so every
	-- reload left another UpdateOrientation running for the life of the session -
	-- four reloads meant six render handlers instead of one. It returns early with
	-- the blur off, so it never showed up as an error, only as a slow leak.
	orientationConnection = RunService.RenderStepped:connect(UpdateOrientation)

	function WindowFunctions:GlobalSetting(Settings)
		hasGlobalSetting = true
		local GlobalSettingFunctions = {}
		local globalSetting = Instance.new("TextButton")
		globalSetting.Name = "GlobalSetting"
		globalSetting.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
		globalSetting.Text = ""
		globalSetting.TextColor3 = Color3.fromRGB(0, 0, 0)
		globalSetting.TextSize = 14
		globalSetting.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		globalSetting.BackgroundTransparency = 1
		globalSetting.BorderColor3 = Color3.fromRGB(0, 0, 0)
		globalSetting.BorderSizePixel = 0
		globalSetting.Size = UDim2.fromOffset(200, 30)

		local globalSettingToggleUIPadding = Instance.new("UIPadding")
		globalSettingToggleUIPadding.Name = "GlobalSettingToggleUIPadding"
		globalSettingToggleUIPadding.PaddingLeft = UDim.new(0, 15)
		globalSettingToggleUIPadding.Parent = globalSetting

		local settingName = Instance.new("TextLabel")
		settingName.Name = "SettingName"
		settingName.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		settingName.Text = Settings.Name
		settingName.RichText = true
		settingName.TextColor3 = Color3.fromRGB(255, 255, 255)
		settingName.TextSize = 13
		settingName.TextTransparency = 0.5
		settingName.TextTruncate = Enum.TextTruncate.SplitWord
		settingName.TextXAlignment = Enum.TextXAlignment.Left
		settingName.TextYAlignment = Enum.TextYAlignment.Top
		settingName.AnchorPoint = Vector2.new(0, 0.5)
		settingName.AutomaticSize = Enum.AutomaticSize.Y
		settingName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		settingName.BackgroundTransparency = 1
		settingName.BorderColor3 = Color3.fromRGB(0, 0, 0)
		settingName.BorderSizePixel = 0
		settingName.Position = UDim2.fromScale(1.3e-07, 0.5)
		settingName.Size = UDim2.new(1,-40,0,0)
		settingName.Parent = globalSetting

		local globalSettingToggleUIListLayout = Instance.new("UIListLayout")
		globalSettingToggleUIListLayout.Name = "GlobalSettingToggleUIListLayout"
		globalSettingToggleUIListLayout.Padding = UDim.new(0, 10)
		globalSettingToggleUIListLayout.FillDirection = Enum.FillDirection.Horizontal
		globalSettingToggleUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		globalSettingToggleUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		globalSettingToggleUIListLayout.Parent = globalSetting

		local checkmark = Instance.new("TextLabel")
		checkmark.Name = "Checkmark"
		checkmark.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		checkmark.Text = "✓"
		checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
		checkmark.TextSize = 13
		checkmark.TextTransparency = 1
		checkmark.TextXAlignment = Enum.TextXAlignment.Left
		checkmark.TextYAlignment = Enum.TextYAlignment.Top
		checkmark.AnchorPoint = Vector2.new(0, 0.5)
		checkmark.AutomaticSize = Enum.AutomaticSize.Y
		checkmark.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		checkmark.BackgroundTransparency = 1
		checkmark.BorderColor3 = Color3.fromRGB(0, 0, 0)
		checkmark.BorderSizePixel = 0
		checkmark.LayoutOrder = -1
		checkmark.Position = UDim2.fromScale(1.3e-07, 0.5)
		checkmark.Size = UDim2.fromOffset(-10, 0)
		checkmark.Parent = globalSetting

		globalSetting.Parent = globalSettings

		local tweensettings = {
			duration = 0.2,
			easingStyle = Enum.EasingStyle.Quint,
			transparencyIn = 0.2,
			transparencyOut = 0.5,
			checkSizeIncrease = 12,
			checkSizeDecrease = -globalSettingToggleUIListLayout.Padding.Offset,
			waitTime = 1
		}

		local tweens = {
			checkIn = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
				Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
			}),
			checkOut = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
			}),
			nameIn = Tween(settingName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				TextTransparency = tweensettings.transparencyIn
			}),
			nameOut = Tween(settingName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				TextTransparency = tweensettings.transparencyOut
			})
		}

		local function Toggle(State)
			if not State then
				tweens.checkOut:Play()
				tweens.nameOut:Play()
				checkmark:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if checkmark.AbsoluteSize.X <= 0 then
						checkmark.TextTransparency = 1
					end
				end)
			else
				tweens.checkIn:Play()
				tweens.nameIn:Play()
				checkmark:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if checkmark.AbsoluteSize.X > 0 then
						checkmark.TextTransparency = 0
					end
				end)
			end
		end

		local toggled = Settings.Default
		Toggle(toggled)

		globalSetting.MouseButton1Click:Connect(function()
			toggled = not toggled
			Toggle(toggled)

			task.spawn(function()
				if Settings.Callback then
					Settings.Callback(toggled)
				end
			end)
		end)

		function GlobalSettingFunctions:UpdateName(NewName)
			settingName.Text = NewName
		end

		function GlobalSettingFunctions:UpdateState(NewState)
			Toggle(NewState)
			toggled = NewState
			task.spawn(function()
				if Settings.Callback then
					Settings.Callback(toggled)
				end
			end)
		end

		return GlobalSettingFunctions
	end

	function WindowFunctions:TabGroup()
		local SectionFunctions = {}

		local tabGroup = Instance.new("Frame")
		tabGroup.Name = "Section"
		tabGroup.AutomaticSize = Enum.AutomaticSize.Y
		tabGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tabGroup.BackgroundTransparency = 1
		tabGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
		tabGroup.BorderSizePixel = 0
		tabGroup.Size = UDim2.fromScale(1, 0)

		local divider3 = Instance.new("Frame")
		divider3.Name = "Divider"
		divider3.AnchorPoint = Vector2.new(0.5, 1)
		divider3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		divider3.BackgroundTransparency = 0.9
		divider3.BorderColor3 = Color3.fromRGB(0, 0, 0)
		divider3.BorderSizePixel = 0
		divider3.Position = UDim2.fromScale(0.5, 1)
		divider3.Size = UDim2.new(1, -21, 0, 1)
		divider3.Parent = tabGroup

		local sectionTabSwitchers = Instance.new("Frame")
		sectionTabSwitchers.Name = "SectionTabSwitchers"
		sectionTabSwitchers.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sectionTabSwitchers.BackgroundTransparency = 1
		sectionTabSwitchers.BorderColor3 = Color3.fromRGB(0, 0, 0)
		sectionTabSwitchers.BorderSizePixel = 0
		sectionTabSwitchers.Size = UDim2.fromScale(1, 1)

		local uIListLayout1 = Instance.new("UIListLayout")
		uIListLayout1.Name = "UIListLayout"
		uIListLayout1.Padding = UDim.new(0, 15)
		uIListLayout1.HorizontalAlignment = Enum.HorizontalAlignment.Center
		uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout1.Parent = sectionTabSwitchers

		local uIPadding1 = Instance.new("UIPadding")
		uIPadding1.Name = "UIPadding"
		uIPadding1.PaddingBottom = UDim.new(0, 15)
		uIPadding1.Parent = sectionTabSwitchers

		sectionTabSwitchers.Parent = tabGroup
		tabGroup.Parent = tabSwitchersScrollingFrame

		function SectionFunctions:Tab(Settings)
			local TabFunctions = {}
			local tabSwitcher = Instance.new("TextButton")
			tabSwitcher.Name = "TabSwitcher"
			tabSwitcher.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
			tabSwitcher.Text = ""
			tabSwitcher.TextColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcher.TextSize = 14
			tabSwitcher.AutoButtonColor = false
			tabSwitcher.AnchorPoint = Vector2.new(0.5, 0)
			tabSwitcher.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcher.BackgroundTransparency = 1
			tabSwitcher.BorderColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcher.BorderSizePixel = 0
			tabSwitcher.Position = UDim2.fromScale(0.5, 0)
			tabSwitcher.Size = UDim2.new(1, -21, 0, 40)

			tabIndex += 1
			tabSwitcher.LayoutOrder = tabIndex

			local tabSwitcherUICorner = Instance.new("UICorner")
			tabSwitcherUICorner.Name = "TabSwitcherUICorner"
			tabSwitcherUICorner.Parent = tabSwitcher

			local tabSwitcherUIStroke = Instance.new("UIStroke")
			tabSwitcherUIStroke.Name = "TabSwitcherUIStroke"
			tabSwitcherUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tabSwitcherUIStroke.Color = Color3.fromRGB(255, 255, 255)
			tabSwitcherUIStroke.Transparency = 1
			tabSwitcherUIStroke.Parent = tabSwitcher

			local tabSwitcherUIListLayout = Instance.new("UIListLayout")
			tabSwitcherUIListLayout.Name = "TabSwitcherUIListLayout"
			tabSwitcherUIListLayout.Padding = UDim.new(0, 9)
			tabSwitcherUIListLayout.FillDirection = Enum.FillDirection.Horizontal
			tabSwitcherUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			tabSwitcherUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			tabSwitcherUIListLayout.Parent = tabSwitcher

			if Settings.Image then
				local tabImage = Instance.new("ImageLabel")
				tabImage.Name = "TabImage"
				tabImage.Image = Settings.Image
				tabImage.ImageTransparency = 0.4
				tabImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				tabImage.BackgroundTransparency = 1
				tabImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
				tabImage.BorderSizePixel = 0
				tabImage.Size = UDim2.fromOffset(16, 16)
				tabImage.Parent = tabSwitcher
			end

			local tabSwitcherName = Instance.new("TextLabel")
			tabSwitcherName.Name = "TabSwitcherName"
			tabSwitcherName.FontFace = Font.new(
				assets.interFont,
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			)
			tabSwitcherName.Text = Settings.Name
			tabSwitcherName.RichText = true
			tabSwitcherName.TextColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcherName.TextSize = 16
			tabSwitcherName.TextTransparency = 0.4
			tabSwitcherName.TextTruncate = Enum.TextTruncate.SplitWord
			tabSwitcherName.TextXAlignment = Enum.TextXAlignment.Left
			tabSwitcherName.TextYAlignment = Enum.TextYAlignment.Top
			tabSwitcherName.AutomaticSize = Enum.AutomaticSize.Y
			tabSwitcherName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcherName.BackgroundTransparency = 1
			tabSwitcherName.BorderColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcherName.BorderSizePixel = 0
			tabSwitcherName.Size = UDim2.fromScale(1, 0)
			tabSwitcherName.Parent = tabSwitcher
			tabSwitcherName.LayoutOrder = 1

			local tabSwitcherUIPadding = Instance.new("UIPadding")
			tabSwitcherUIPadding.Name = "TabSwitcherUIPadding"
			tabSwitcherUIPadding.PaddingLeft = UDim.new(0, 24)
			tabSwitcherUIPadding.PaddingRight = UDim.new(0, 35)
			tabSwitcherUIPadding.PaddingTop = UDim.new(0, 1)
			tabSwitcherUIPadding.Parent = tabSwitcher

			tabSwitcher.Parent = sectionTabSwitchers

			local elements1 = Instance.new("Frame")
			elements1.Name = "Elements"
			elements1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			elements1.BackgroundTransparency = 1
			elements1.BorderColor3 = Color3.fromRGB(0, 0, 0)
			elements1.BorderSizePixel = 0
			elements1.Position = UDim2.fromOffset(0, 63)
			elements1.Size = UDim2.new(1, 0, 1, -63)

			local elementsUIPadding = Instance.new("UIPadding")
			elementsUIPadding.Name = "ElementsUIPadding"
			elementsUIPadding.PaddingRight = UDim.new(0, 5)
			elementsUIPadding.PaddingTop = UDim.new(0, 10)
			elementsUIPadding.Parent = elements1

			local elementsScrolling = Instance.new("ScrollingFrame")
			elementsScrolling.Name = "ElementsScrolling"
			elementsScrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
			elementsScrolling.BottomImage = ""
			elementsScrolling.CanvasSize = UDim2.new()
			elementsScrolling.ScrollBarImageTransparency = 0.5
			elementsScrolling.ScrollBarThickness = 1
			elementsScrolling.TopImage = ""
			elementsScrolling.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			elementsScrolling.BackgroundTransparency = 1
			elementsScrolling.BorderColor3 = Color3.fromRGB(0, 0, 0)
			elementsScrolling.BorderSizePixel = 0
			elementsScrolling.Size = UDim2.fromScale(1, 1)

			local elementsScrollingUIPadding = Instance.new("UIPadding")
			elementsScrollingUIPadding.Name = "ElementsScrollingUIPadding"
			elementsScrollingUIPadding.PaddingBottom = UDim.new(0, 15)
			elementsScrollingUIPadding.PaddingLeft = UDim.new(0, 11)
			elementsScrollingUIPadding.PaddingRight = UDim.new(0, 3)
			elementsScrollingUIPadding.PaddingTop = UDim.new(0, 5)
			elementsScrollingUIPadding.Parent = elementsScrolling

			local elementsScrollingUIListLayout = Instance.new("UIListLayout")
			elementsScrollingUIListLayout.Name = "ElementsScrollingUIListLayout"
			elementsScrollingUIListLayout.Padding = UDim.new(0, 15)
			elementsScrollingUIListLayout.FillDirection = Enum.FillDirection.Horizontal
			elementsScrollingUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			elementsScrollingUIListLayout.Parent = elementsScrolling

			local left = Instance.new("Frame")
			left.Name = "Left"
			left.AutomaticSize = Enum.AutomaticSize.Y
			left.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			left.BackgroundTransparency = 1
			left.BorderColor3 = Color3.fromRGB(0, 0, 0)
			left.BorderSizePixel = 0
			left.Position = UDim2.fromScale(0.512, 0)
			left.Size = UDim2.new(0.5, -10, 0, 0)

			local leftUIListLayout = Instance.new("UIListLayout")
			leftUIListLayout.Name = "LeftUIListLayout"
			leftUIListLayout.Padding = UDim.new(0, 15)
			leftUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			leftUIListLayout.Parent = left

			left.Parent = elementsScrolling

			local right = Instance.new("Frame")
			right.Name = "Right"
			right.AutomaticSize = Enum.AutomaticSize.Y
			right.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			right.BackgroundTransparency = 1
			right.BorderColor3 = Color3.fromRGB(0, 0, 0)
			right.BorderSizePixel = 0
			right.LayoutOrder = 1
			right.Position = UDim2.fromScale(0.512, 0)
			right.Size = UDim2.new(0.5, -10, 0, 0)

			local rightUIListLayout = Instance.new("UIListLayout")
			rightUIListLayout.Name = "RightUIListLayout"
			rightUIListLayout.Padding = UDim.new(0, 15)
			rightUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rightUIListLayout.Parent = right

			right.Parent = elementsScrolling

			elementsScrolling.Parent = elements1

			function TabFunctions:Section(Settings)
				local SectionFunctions = {}
				local section = Instance.new("Frame")
				section.Name = "Section"
				section.AutomaticSize = Enum.AutomaticSize.Y
				section.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				section.BackgroundTransparency = 0.98
				section.BorderColor3 = Color3.fromRGB(0, 0, 0)
				section.BorderSizePixel = 0
				section.Position = UDim2.fromScale(0, 6.78e-08)
				section.Size = UDim2.fromScale(1, 0)
				section.Parent = Settings.Side == "Left" and left or right

				local sectionUICorner = Instance.new("UICorner")
				sectionUICorner.Name = "SectionUICorner"
				sectionUICorner.Parent = section

				local sectionUIStroke = Instance.new("UIStroke")
				sectionUIStroke.Name = "SectionUIStroke"
				sectionUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				sectionUIStroke.Color = Color3.fromRGB(255, 255, 255)
				sectionUIStroke.Transparency = 0.95
				sectionUIStroke.Parent = section

				local sectionUIListLayout = Instance.new("UIListLayout")
				sectionUIListLayout.Name = "SectionUIListLayout"
				sectionUIListLayout.Padding = UDim.new(0, 10)
				sectionUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
				sectionUIListLayout.Parent = section

				local sectionUIPadding = Instance.new("UIPadding")
				sectionUIPadding.Name = "SectionUIPadding"
				sectionUIPadding.PaddingBottom = UDim.new(0, 20)
				sectionUIPadding.PaddingLeft = UDim.new(0, 20)
				sectionUIPadding.PaddingRight = UDim.new(0, 18)
				sectionUIPadding.PaddingTop = UDim.new(0, 22)
				sectionUIPadding.Parent = section

				function SectionFunctions:Button(Settings)
					local ButtonFunctions = {}
					local button = Instance.new("Frame")
					button.Name = "Button"
					button.AutomaticSize = Enum.AutomaticSize.Y
					button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					button.BackgroundTransparency = 1
					button.BorderColor3 = Color3.fromRGB(0, 0, 0)
					button.BorderSizePixel = 0
					button.Size = UDim2.new(1, 0, 0, 38)
					button.Parent = section

					local buttonInteract = Instance.new("TextButton")
					buttonInteract.Name = "ButtonInteract"
					buttonInteract.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					buttonInteract.RichText = true
					buttonInteract.TextColor3 = Color3.fromRGB(255, 255, 255)
					buttonInteract.TextSize = 13
					buttonInteract.TextTransparency = 0.5
					buttonInteract.TextTruncate = Enum.TextTruncate.AtEnd
					buttonInteract.TextXAlignment = Enum.TextXAlignment.Left
					buttonInteract.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					buttonInteract.BackgroundTransparency = 1
					buttonInteract.BorderColor3 = Color3.fromRGB(0, 0, 0)
					buttonInteract.BorderSizePixel = 0
					buttonInteract.Size = UDim2.fromScale(1, 1)
					buttonInteract.Parent = button
					buttonInteract.Text = Settings.Name

					local buttonImage = Instance.new("ImageLabel")
					buttonImage.Name = "ButtonImage"
					buttonImage.Image = assets.buttonImage
					buttonImage.ImageTransparency = 0.5
					buttonImage.AnchorPoint = Vector2.new(1, 0.5)
					buttonImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					buttonImage.BackgroundTransparency = 1
					buttonImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
					buttonImage.BorderSizePixel = 0
					buttonImage.Position = UDim2.fromScale(1, 0.5)
					buttonImage.Size = UDim2.fromOffset(15, 15)
					buttonImage.Parent = button

					local TweenSettings = {
						DefaultTransparency = 0.5,
						HoverTransparency = 0.3,

						EasingStyle = Enum.EasingStyle.Sine
					}

					local function ChangeState(State)
						if State == "Idle" then
							Tween(buttonInteract, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								TextTransparency = TweenSettings.DefaultTransparency
							}):Play()
							Tween(buttonImage, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								ImageTransparency = TweenSettings.DefaultTransparency
							}):Play()
						elseif State == "Hover" then
							Tween(buttonInteract, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								TextTransparency = TweenSettings.HoverTransparency
							}):Play()
							Tween(buttonImage, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								ImageTransparency = TweenSettings.HoverTransparency
							}):Play()
						end
					end

					local function Callback()
						if Settings.Callback then
							Settings.Callback()
						end
					end

					buttonInteract.MouseEnter:Connect(function()
						ChangeState("Hover")
					end)
					buttonInteract.MouseLeave:Connect(function()
						ChangeState("Idle")
					end)

					buttonInteract.MouseButton1Click:Connect(Callback)
					function ButtonFunctions:UpdateName(Name)
						buttonInteract.Text = Name
					end
					function ButtonFunctions:SetVisibility(State)
						button.Visible = State
					end
					return ButtonFunctions
				end

				function SectionFunctions:Toggle(Settings)
					local ToggleFunctions = {}
					local toggle = Instance.new("Frame")
					toggle.Name = "Toggle"
					toggle.AutomaticSize = Enum.AutomaticSize.Y
					toggle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					toggle.BackgroundTransparency = 1
					toggle.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggle.BorderSizePixel = 0
					toggle.Size = UDim2.new(1, 0, 0, 38)
					toggle.Parent = section

					local toggleName = Instance.new("TextLabel")
					toggleName.Name = "ToggleName"
					toggleName.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					toggleName.Text = Settings.Name
					toggleName.RichText = true
					toggleName.TextColor3 = Color3.fromRGB(255, 255, 255)
					toggleName.TextSize = 13
					toggleName.TextTransparency = 0.5
					toggleName.TextTruncate = Enum.TextTruncate.AtEnd
					toggleName.TextXAlignment = Enum.TextXAlignment.Left
					toggleName.TextYAlignment = Enum.TextYAlignment.Top
					toggleName.AnchorPoint = Vector2.new(0, 0.5)
					toggleName.AutomaticSize = Enum.AutomaticSize.Y
					toggleName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					toggleName.BackgroundTransparency = 1
					toggleName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggleName.BorderSizePixel = 0
					toggleName.Position = UDim2.fromScale(0, 0.5)
					toggleName.Size = UDim2.new(1, -50, 0, 0)
					toggleName.Parent = toggle

					local toggle1 = Instance.new("ImageButton")
					toggle1.Name = "Toggle"
					toggle1.Image = assets.toggleBackground
					toggle1.ImageColor3 = Color3.fromRGB(61, 61, 61)
					toggle1.AutoButtonColor = false
					toggle1.AnchorPoint = Vector2.new(1, 0.5)
					toggle1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					toggle1.BackgroundTransparency = 1
					toggle1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggle1.BorderSizePixel = 0
					toggle1.Position = UDim2.fromScale(1, 0.5)
					toggle1.Size = UDim2.fromOffset(41, 21)

					local toggleUIPadding = Instance.new("UIPadding")
					toggleUIPadding.Name = "ToggleUIPadding"
					toggleUIPadding.PaddingBottom = UDim.new(0, 1)
					toggleUIPadding.PaddingLeft = UDim.new(0, -2)
					toggleUIPadding.PaddingRight = UDim.new(0, 3)
					toggleUIPadding.PaddingTop = UDim.new(0, 1)
					toggleUIPadding.Parent = toggle1

					local togglerHead = Instance.new("ImageLabel")
					togglerHead.Name = "TogglerHead"
					togglerHead.Image = "rbxassetid://18772309008"
					togglerHead.ImageColor3 = Color3.fromRGB(91, 91, 91)
					togglerHead.AnchorPoint = Vector2.new(1, 0.5)
					togglerHead.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					togglerHead.BackgroundTransparency = 1
					togglerHead.BorderColor3 = Color3.fromRGB(0, 0, 0)
					togglerHead.BorderSizePixel = 0
					togglerHead.Position = UDim2.fromScale(0.5, 0.5)
					togglerHead.Size = UDim2.fromOffset(15, 15)
					togglerHead.ZIndex = 2
					togglerHead.Parent = toggle1

					toggle1.Parent = toggle

					local TweenSettings = {
						Info = TweenInfo.new(0.2, Enum.EasingStyle.Sine),

						EnabledColors = {Toggle = Color3.fromRGB(87, 86, 86), ToggleHead = Color3.fromRGB(255, 255, 255)},
						DisabledColors = {Toggle = Color3.fromRGB(61, 61, 61), ToggleHead = Color3.fromRGB(91, 91, 91)},

						EnabledPosition = UDim2.new(1, 0, 0.5, 0),
						DisabledPosition = UDim2.new(0.5, 0, 0.5, 0),
					}

					local function ToggleState(State)
						if State then
							Tween(toggle1, TweenSettings.Info, {
								ImageColor3 = TweenSettings.EnabledColors.Toggle
							}):Play()

							Tween(togglerHead, TweenSettings.Info, {
								ImageColor3 = TweenSettings.EnabledColors.ToggleHead
							}):Play()

							Tween(togglerHead, TweenSettings.Info, {
								Position = TweenSettings.EnabledPosition
							}):Play()
						else
							Tween(toggle1, TweenSettings.Info, {
								ImageColor3 = TweenSettings.DisabledColors.Toggle
							}):Play()

							Tween(togglerHead, TweenSettings.Info, {
								ImageColor3 = TweenSettings.DisabledColors.ToggleHead
							}):Play()

							Tween(togglerHead, TweenSettings.Info, {
								Position = TweenSettings.DisabledPosition
							}):Play()
						end
						
						ToggleFunctions.State = State
					end

					local togglebool = Settings.Default
					ToggleState(togglebool)

					local function Toggle()
						togglebool = not togglebool
						ToggleState(togglebool)
						if Settings.Callback then
							Settings.Callback(togglebool)
						end
					end

					toggle1.MouseButton1Click:Connect(Toggle)

					function ToggleFunctions:Toggle()
						Toggle()
					end
					function ToggleFunctions:UpdateState(State)
						togglebool = State
						ToggleState(togglebool)
						if Settings.Callback then
							Settings.Callback(togglebool)
						end
					end
					function ToggleFunctions:GetState()
						return togglebool
					end
					function ToggleFunctions:UpdateName(Name)
						toggleName.Text = Name
					end
					function ToggleFunctions:SetVisibility(State)
						toggle.Visible = State
					end
					return ToggleFunctions
				end

				function SectionFunctions:Slider(Settings)
					local SliderFunctions = {}
					local slider = Instance.new("Frame")
					slider.Name = "Slider"
					slider.AutomaticSize = Enum.AutomaticSize.Y
					slider.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					slider.BackgroundTransparency = 1
					slider.BorderColor3 = Color3.fromRGB(0, 0, 0)
					slider.BorderSizePixel = 0
					slider.Size = UDim2.new(1, 0, 0, 38)
					slider.Parent = section

					local sliderName = Instance.new("TextLabel")
					sliderName.Name = "SliderName"
					sliderName.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					sliderName.Text = Settings.Name
					sliderName.RichText = true
					sliderName.TextColor3 = Color3.fromRGB(255, 255, 255)
					sliderName.TextSize = 13
					sliderName.TextTransparency = 0.5
					sliderName.TextTruncate = Enum.TextTruncate.AtEnd
					sliderName.TextXAlignment = Enum.TextXAlignment.Left
					sliderName.TextYAlignment = Enum.TextYAlignment.Top
					sliderName.AnchorPoint = Vector2.new(0, 0.5)
					sliderName.AutomaticSize = Enum.AutomaticSize.XY
					sliderName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderName.BackgroundTransparency = 1
					sliderName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderName.BorderSizePixel = 0
					sliderName.Position = UDim2.fromScale(1.3e-07, 0.5)
					sliderName.Parent = slider

					local sliderElements = Instance.new("Frame")
					sliderElements.Name = "SliderElements"
					sliderElements.AnchorPoint = Vector2.new(1, 0)
					sliderElements.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderElements.BackgroundTransparency = 1
					sliderElements.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderElements.BorderSizePixel = 0
					sliderElements.Position = UDim2.fromScale(1, 0)
					sliderElements.Size = UDim2.fromScale(1, 1)

					local sliderValue = Instance.new("TextBox")
					sliderValue.Name = "SliderValue"
					sliderValue.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					sliderValue.Text = "100%"
					sliderValue.TextColor3 = Color3.fromRGB(255, 255, 255)
					sliderValue.TextSize = 12
					sliderValue.TextTransparency = 0.4
					sliderValue.TextTruncate = Enum.TextTruncate.AtEnd
					sliderValue.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderValue.BackgroundTransparency = 0.95
					sliderValue.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderValue.BorderSizePixel = 0
					sliderValue.LayoutOrder = 1
					sliderValue.Position = UDim2.fromScale(-0.0789, 0.171)
					sliderValue.Size = UDim2.fromOffset(41, 21)

					local sliderValueUICorner = Instance.new("UICorner")
					sliderValueUICorner.Name = "SliderValueUICorner"
					sliderValueUICorner.CornerRadius = UDim.new(0, 4)
					sliderValueUICorner.Parent = sliderValue

					local sliderValueUIStroke = Instance.new("UIStroke")
					sliderValueUIStroke.Name = "SliderValueUIStroke"
					sliderValueUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					sliderValueUIStroke.Color = Color3.fromRGB(255, 255, 255)
					sliderValueUIStroke.Transparency = 0.9
					sliderValueUIStroke.Parent = sliderValue

					local sliderValueUIPadding = Instance.new("UIPadding")
					sliderValueUIPadding.Name = "SliderValueUIPadding"
					sliderValueUIPadding.PaddingLeft = UDim.new(0, 2)
					sliderValueUIPadding.PaddingRight = UDim.new(0, 2)
					sliderValueUIPadding.Parent = sliderValue

					sliderValue.Parent = sliderElements

					local sliderElementsUIListLayout = Instance.new("UIListLayout")
					sliderElementsUIListLayout.Name = "SliderElementsUIListLayout"
					sliderElementsUIListLayout.Padding = UDim.new(0, 20)
					sliderElementsUIListLayout.FillDirection = Enum.FillDirection.Horizontal
					sliderElementsUIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
					sliderElementsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					sliderElementsUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
					sliderElementsUIListLayout.Parent = sliderElements

					local sliderBar = Instance.new("ImageLabel")
					sliderBar.Name = "SliderBar"
					sliderBar.Image = "rbxassetid://18772615246"
					sliderBar.ImageColor3 = Color3.fromRGB(87, 86, 86)
					sliderBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderBar.BackgroundTransparency = 1
					sliderBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderBar.BorderSizePixel = 0
					sliderBar.Position = UDim2.fromScale(0.219, 0.457)
					sliderBar.Size = UDim2.fromOffset(123, 3)

					local sliderHead = Instance.new("ImageButton")
					sliderHead.Name = "SliderHead"
					sliderHead.Image = "rbxassetid://18772834246"
					sliderHead.AnchorPoint = Vector2.new(0.5, 0.5)
					sliderHead.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderHead.BackgroundTransparency = 1
					sliderHead.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderHead.BorderSizePixel = 0
					sliderHead.Position = UDim2.fromScale(1, 0.5)
					sliderHead.Size = UDim2.fromOffset(12, 12)
					sliderHead.Parent = sliderBar

					sliderBar.Parent = sliderElements

					local sliderElementsUIPadding = Instance.new("UIPadding")
					sliderElementsUIPadding.Name = "SliderElementsUIPadding"
					sliderElementsUIPadding.PaddingTop = UDim.new(0, 3)
					sliderElementsUIPadding.Parent = sliderElements

					sliderElements.Parent = slider

					local dragging = false

					-- math.round is Luau-only. The DisplayMethods closures call it directly, and on
-- an executor whose math table is the plain Lua one that throws the moment a
-- slider is drawn - the whole menu body dies with it. Fall back to floor(x+0.5).
local mround = math.round or function(x)
	return math.floor(x + 0.5)
end

					local DisplayMethods = {
						Hundredths = function(sliderValue)
							return string.format("%.2f", sliderValue)
						end,
						Tenths = function(sliderValue)
							return string.format("%.1f", sliderValue)
						end,
						Round = function(sliderValue)
							return tostring(mround(sliderValue))
						end,
						Degrees = function(sliderValue)
							return tostring(mround(sliderValue)) .. "°"
						end,
						Percent = function(sliderValue)
							local percentage = (sliderValue - Settings.Minimum) / (Settings.Maximum - Settings.Minimum) * 100
							return tostring(mround(percentage)) .. "%"
						end,
						Value = function(sliderValue)
							return tostring(sliderValue)
						end
					}

					local ValueDisplayMethod = DisplayMethods[Settings.DisplayMethod]
					local finalValue

					local function SetValue(val, ignorecallback)
						local posXScale

						if typeof(val) == "Instance" then
							local input = val
							posXScale = math.clamp((input.Position.X - sliderBar.AbsolutePosition.X) / sliderBar.AbsoluteSize.X, 0, 1)
						else
							local value = val
							posXScale = (value - Settings.Minimum) / (Settings.Maximum - Settings.Minimum)
						end

						local pos = UDim2.new(posXScale, 0, 0.5, 0)
						sliderHead.Position = pos

						finalValue = posXScale * (Settings.Maximum - Settings.Minimum) + Settings.Minimum
						sliderValue.Text = ValueDisplayMethod(finalValue)

						if not ignorecallback then
							task.spawn(function()
								if Settings.Callback then
									Settings.Callback(finalValue)
								end
							end)
						end
						
						SliderFunctions.Value = finalValue
					end

					SetValue(Settings.Default, true)

					sliderHead.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							dragging = true
							SetValue(input)
						end
					end)

					sliderHead.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							dragging = false
						end
					end)

					sliderValue.FocusLost:Connect(function(enterPressed)
						local inputText = sliderValue.Text
						local value, isPercent = inputText:match("^(%-?%d+%.?%d*)(%%?)$")

						if value then
							value = tonumber(value)
							isPercent = isPercent == "%"

							if isPercent then
								value = Settings.Minimum + (value / 100) * (Settings.Maximum - Settings.Minimum)
							end

							local newValue = math.clamp(value, Settings.Minimum, Settings.Maximum)
							SetValue(newValue)
						else
							sliderValue.Text = ValueDisplayMethod(sliderValue)
						end
					end)

					UserInputService.InputChanged:Connect(function(input)
						if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
							SetValue(input)
						end
					end)

					local function updateSliderBarSize()
						local padding = sliderElementsUIListLayout.Padding.Offset
						local sliderValueWidth = sliderValue.AbsoluteSize.X
						local sliderNameWidth = sliderName.AbsoluteSize.X
						local totalWidth = sliderElements.AbsoluteSize.X

						local newBarWidth = totalWidth - (padding + sliderValueWidth + sliderNameWidth + 20)
						sliderBar.Size = UDim2.new(sliderBar.Size.X.Scale, newBarWidth, sliderBar.Size.Y.Scale, sliderBar.Size.Y.Offset)
					end

					updateSliderBarSize()

					sliderName:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSliderBarSize)
					section:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSliderBarSize)

					function SliderFunctions:UpdateName(Name)
						sliderName = Name
					end
					function SliderFunctions:SetVisibility(State)
						slider.Visible = State
					end
					function SliderFunctions:UpdateValue(Value)
						SetValue(Value)
					end
					function SliderFunctions:GetValue()
						return finalValue
					end
					return SliderFunctions
				end

				function SectionFunctions:Input(Settings)
					local InputFunctions = {}
					local input = Instance.new("Frame")
					input.Name = "Input"
					input.AutomaticSize = Enum.AutomaticSize.Y
					input.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					input.BackgroundTransparency = 1
					input.BorderColor3 = Color3.fromRGB(0, 0, 0)
					input.BorderSizePixel = 0
					input.Size = UDim2.new(1, 0, 0, 38)
					input.Parent = section

					local inputName = Instance.new("TextLabel")
					inputName.Name = "InputName"
					inputName.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName.Text = Settings.Name
					inputName.RichText = true
					inputName.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName.TextSize = 13
					inputName.TextTransparency = 0.5
					inputName.TextTruncate = Enum.TextTruncate.AtEnd
					inputName.TextXAlignment = Enum.TextXAlignment.Left
					inputName.TextYAlignment = Enum.TextYAlignment.Top
					inputName.AnchorPoint = Vector2.new(0, 0.5)
					inputName.AutomaticSize = Enum.AutomaticSize.XY
					inputName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName.BackgroundTransparency = 1
					inputName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName.BorderSizePixel = 0
					inputName.Position = UDim2.fromScale(0, 0.5)
					inputName.Parent = input

					local inputBox = Instance.new("TextBox")
					inputBox.Name = "InputBox"
					inputBox.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox.Text = "Hello world!"
					inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.TextSize = 12
					inputBox.TextTransparency = 0.4
					inputBox.AnchorPoint = Vector2.new(1, 0.5)
					inputBox.AutomaticSize = Enum.AutomaticSize.X
					inputBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.BackgroundTransparency = 0.95
					inputBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox.BorderSizePixel = 0
					inputBox.ClipsDescendants = true
					inputBox.LayoutOrder = 1
					inputBox.Position = UDim2.fromScale(1, 0.5)
					inputBox.Size = UDim2.fromOffset(21, 21)

					local inputBoxUICorner = Instance.new("UICorner")
					inputBoxUICorner.Name = "InputBoxUICorner"
					inputBoxUICorner.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner.Parent = inputBox

					local inputBoxUIStroke = Instance.new("UIStroke")
					inputBoxUIStroke.Name = "InputBoxUIStroke"
					inputBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke.Transparency = 0.9
					inputBoxUIStroke.Parent = inputBox

					local inputBoxUIPadding = Instance.new("UIPadding")
					inputBoxUIPadding.Name = "InputBoxUIPadding"
					inputBoxUIPadding.PaddingLeft = UDim.new(0, 5)
					inputBoxUIPadding.PaddingRight = UDim.new(0, 5)
					inputBoxUIPadding.Parent = inputBox

					local inputBoxUISizeConstraint = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint.Parent = inputBox

					inputBox.Parent = input

					local Input = input
					local InputBox = inputBox
					local InputName = inputName
					local Constraint = inputBoxUISizeConstraint

					local CharacterSubs = {
						All = function(value)
							return value
						end,
						Numeric = function(value)
							return value:match("^%-?%d*$") and value or value:gsub("[^%d-]", ""):gsub("(%-)", function(match, pos, original)
								if pos == 1 then
									return match
								else
									return ""
								end
							end)
						end,
						Alphabetic = function(value)
							return value:gsub("[^a-zA-Z ]", "")
						end,
					}

					local AcceptedCharacters = CharacterSubs[Settings.AcceptedCharacters] or CharacterSubs.All

					InputBox.AutomaticSize = Enum.AutomaticSize.X

					local function checkSize()
						local nameWidth = InputName.AbsoluteSize.X
						local totalWidth = Input.AbsoluteSize.X

						local maxWidth = totalWidth - nameWidth - 20
						Constraint.MaxSize = Vector2.new(maxWidth, 9e9)
					end

					checkSize()
					InputName:GetPropertyChangedSignal("AbsoluteSize"):Connect(checkSize)

					InputBox.FocusLost:Connect(function()
						local inputText = InputBox.Text
						local filteredText = AcceptedCharacters(inputText)
						InputBox.Text = filteredText
						task.spawn(function()
							if Settings.Callback then
								Settings.Callback(filteredText)
							end
						end)
					end)
					InputBox.Text = Settings.Default or ""
					InputBox.PlaceholderText = Settings.Placeholder or ""

					InputBox:GetPropertyChangedSignal("Text"):Connect(function()
						InputBox.Text = AcceptedCharacters(InputBox.Text)
						if Settings.onChanged then
							Settings.onChanged(InputBox.Text)
						end
						InputFunctions.Text = InputBox.Text
					end)

					function InputFunctions:UpdateName(Name)
						inputName.Text = Name
					end
					function InputFunctions:SetVisibility(State)
						input.Visible = State
					end
					function InputFunctions:GetInput()
						return InputBox.Text
					end
					function InputFunctions:UpdatePlaceholder(Placeholder)
						inputBox.PlaceholderText = Placeholder
					end
					function InputFunctions:UpdateText(Text)
						inputBox.Text = Text
					end
					return InputFunctions
				end

				function SectionFunctions:Keybind(Settings)
					local KeybindFunctions = {}
					local keybind = Instance.new("Frame")
					keybind.Name = "Keybind"
					keybind.AutomaticSize = Enum.AutomaticSize.Y
					keybind.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					keybind.BackgroundTransparency = 1
					keybind.BorderColor3 = Color3.fromRGB(0, 0, 0)
					keybind.BorderSizePixel = 0
					keybind.Size = UDim2.new(1, 0, 0, 38)
					keybind.Parent = section

					local keybindName = Instance.new("TextLabel")
					keybindName.Name = "KeybindName"
					keybindName.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					keybindName.Text = Settings.Name
					keybindName.RichText = true
					keybindName.TextColor3 = Color3.fromRGB(255, 255, 255)
					keybindName.TextSize = 13
					keybindName.TextTransparency = 0.5
					keybindName.TextTruncate = Enum.TextTruncate.AtEnd
					keybindName.TextXAlignment = Enum.TextXAlignment.Left
					keybindName.TextYAlignment = Enum.TextYAlignment.Top
					keybindName.AnchorPoint = Vector2.new(0, 0.5)
					keybindName.AutomaticSize = Enum.AutomaticSize.XY
					keybindName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					keybindName.BackgroundTransparency = 1
					keybindName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					keybindName.BorderSizePixel = 0
					keybindName.Position = UDim2.fromScale(0, 0.5)
					keybindName.Parent = keybind

					local binderBox = Instance.new("TextBox")
					binderBox.Name = "BinderBox"
					binderBox.CursorPosition = -1
					binderBox.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					binderBox.PlaceholderText = "..."
					binderBox.Text = ""
					binderBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					binderBox.TextSize = 12
					binderBox.TextTransparency = 0.4
					binderBox.AnchorPoint = Vector2.new(1, 0.5)
					binderBox.AutomaticSize = Enum.AutomaticSize.X
					binderBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					binderBox.BackgroundTransparency = 0.95
					binderBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					binderBox.BorderSizePixel = 0
					binderBox.ClipsDescendants = true
					binderBox.LayoutOrder = 1
					binderBox.Position = UDim2.fromScale(1, 0.5)
					binderBox.Size = UDim2.fromOffset(21, 21)

					local binderBoxUICorner = Instance.new("UICorner")
					binderBoxUICorner.Name = "BinderBoxUICorner"
					binderBoxUICorner.CornerRadius = UDim.new(0, 4)
					binderBoxUICorner.Parent = binderBox

					local binderBoxUIStroke = Instance.new("UIStroke")
					binderBoxUIStroke.Name = "BinderBoxUIStroke"
					binderBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					binderBoxUIStroke.Color = Color3.fromRGB(255, 255, 255)
					binderBoxUIStroke.Transparency = 0.9
					binderBoxUIStroke.Parent = binderBox

					local binderBoxUIPadding = Instance.new("UIPadding")
					binderBoxUIPadding.Name = "BinderBoxUIPadding"
					binderBoxUIPadding.PaddingLeft = UDim.new(0, 5)
					binderBoxUIPadding.PaddingRight = UDim.new(0, 5)
					binderBoxUIPadding.Parent = binderBox

					local binderBoxUISizeConstraint = Instance.new("UISizeConstraint")
					binderBoxUISizeConstraint.Name = "BinderBoxUISizeConstraint"
					binderBoxUISizeConstraint.Parent = binderBox

					binderBox.Parent = keybind

					local focused
					local binded = Settings.Default
					if binded then
						binderBox.Text = binded.Name
					end

					binderBox.Focused:Connect(function()
						focused = true
					end)
					binderBox.FocusLost:Connect(function()
						focused = false
					end)
				
					UserInputService.InputEnded:Connect(function(inp)
						if macLib ~= nil then
							if focused and inp.KeyCode.Name ~= "Unknown" then
								binded = inp.KeyCode
								KeybindFunctions.Bind = binded
								binderBox.Text = inp.KeyCode.Name
								binderBox:ReleaseFocus()
								if Settings.onBinded then
									Settings.onBinded(binded)
								end
							elseif inp.KeyCode == binded then
								if Settings.Callback then
									Settings.Callback(binded)
								end
							end
						end
					end)
					function KeybindFunctions:Bind(Key)
						binded = Key
						binderBox.Text = Key.Name
					end
					function KeybindFunctions:Unbind()
						binded = nil
						binderBox.Text = ""
					end
					function KeybindFunctions:GetBind()
						return binded
					end
					function KeybindFunctions:UpdateName(Name)
						keybindName = Name
					end
					function KeybindFunctions:SetVisibility(State)
						keybind.Visible = State
					end
					return KeybindFunctions
				end

				function SectionFunctions:Dropdown(Settings)
					local DropdownFunctions = {}
					local Selected = {}
					local OptionObjs = {}

					local dropdown = Instance.new("Frame")
					dropdown.Name = "Dropdown"
					dropdown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdown.BackgroundTransparency = 0.985
					dropdown.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdown.BorderSizePixel = 0
					dropdown.Size = UDim2.new(1, 0, 0, 38)
					dropdown.Parent = section
					dropdown.ClipsDescendants = true
					
					local dropdownUIPadding = Instance.new("UIPadding")
					dropdownUIPadding.Name = "DropdownUIPadding"
					dropdownUIPadding.PaddingLeft = UDim.new(0, 15)
					dropdownUIPadding.PaddingRight = UDim.new(0, 15)
					dropdownUIPadding.Parent = dropdown

					local interact = Instance.new("TextButton")
					interact.Name = "Interact"
					interact.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
					interact.Text = ""
					interact.TextColor3 = Color3.fromRGB(0, 0, 0)
					interact.TextSize = 14
					interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					interact.BackgroundTransparency = 1
					interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interact.BorderSizePixel = 0
					interact.Size = UDim2.new(1, 0, 0, 38)
					interact.Parent = dropdown

					local dropdownName = Instance.new("TextLabel")
					dropdownName.Name = "DropdownName"
					dropdownName.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					dropdownName.Text = Settings.Name
					dropdownName.RichText = true
					dropdownName.TextColor3 = Color3.fromRGB(255, 255, 255)
					dropdownName.TextSize = 13
					dropdownName.TextTransparency = 0.5
					dropdownName.TextTruncate = Enum.TextTruncate.SplitWord
					dropdownName.TextXAlignment = Enum.TextXAlignment.Left
					dropdownName.AutomaticSize = Enum.AutomaticSize.Y
					dropdownName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownName.BackgroundTransparency = 1
					dropdownName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownName.BorderSizePixel = 0
					dropdownName.Size = UDim2.new(1, -20, 0, 38)
					dropdownName.Parent = dropdown

					local dropdownUIStroke = Instance.new("UIStroke")
					dropdownUIStroke.Name = "DropdownUIStroke"
					dropdownUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					dropdownUIStroke.Color = Color3.fromRGB(255, 255, 255)
					dropdownUIStroke.Transparency = 0.95
					dropdownUIStroke.Parent = dropdown

					local dropdownUICorner = Instance.new("UICorner")
					dropdownUICorner.Name = "DropdownUICorner"
					dropdownUICorner.CornerRadius = UDim.new(0, 6)
					dropdownUICorner.Parent = dropdown

					local dropdownImage = Instance.new("ImageLabel")
					dropdownImage.Name = "DropdownImage"
					dropdownImage.Image = "rbxassetid://18865373378"
					dropdownImage.ImageTransparency = 0.5
					dropdownImage.AnchorPoint = Vector2.new(1, 0)
					dropdownImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownImage.BackgroundTransparency = 1
					dropdownImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownImage.BorderSizePixel = 0
					dropdownImage.Position = UDim2.new(1, 0, 0, 12)
					dropdownImage.Size = UDim2.fromOffset(14, 14)
					dropdownImage.Parent = dropdown

					local dropdownFrame = Instance.new("Frame")
					dropdownFrame.Name = "DropdownFrame"
					dropdownFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownFrame.BackgroundTransparency = 1
					dropdownFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownFrame.BorderSizePixel = 0
					dropdownFrame.ClipsDescendants = true
					dropdownFrame.Size = UDim2.fromScale(1, 1)
					dropdownFrame.Visible = false
					dropdownFrame.AutomaticSize = Enum.AutomaticSize.Y

					local dropdownFrameUIPadding = Instance.new("UIPadding")
					dropdownFrameUIPadding.Name = "DropdownFrameUIPadding"
					dropdownFrameUIPadding.PaddingTop = UDim.new(0, 38)
					dropdownFrameUIPadding.PaddingBottom = UDim.new(0, 10)
					dropdownFrameUIPadding.Parent = dropdownFrame

					local dropdownFrameUIListLayout = Instance.new("UIListLayout")
					dropdownFrameUIListLayout.Name = "DropdownFrameUIListLayout"
					dropdownFrameUIListLayout.Padding = UDim.new(0, 5)
					dropdownFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					dropdownFrameUIListLayout.Parent = dropdownFrame
					
					local search = Instance.new("Frame")
					search.Name = "Search"
					search.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					search.BackgroundTransparency = 0.95
					search.BorderColor3 = Color3.fromRGB(0, 0, 0)
					search.BorderSizePixel = 0
					search.LayoutOrder = -1
					search.Size = UDim2.new(1, 0, 0, 30)
					search.Parent = dropdownFrame
					search.Visible = Settings.Search

					local sectionUICorner = Instance.new("UICorner")
					sectionUICorner.Name = "SectionUICorner"
					sectionUICorner.Parent = search

					local searchIcon = Instance.new("ImageLabel")
					searchIcon.Name = "SearchIcon"
					searchIcon.Image = assets.searchIcon
					searchIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
					searchIcon.AnchorPoint = Vector2.new(0, 0.5)
					searchIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					searchIcon.BackgroundTransparency = 1
					searchIcon.BorderColor3 = Color3.fromRGB(0, 0, 0)
					searchIcon.BorderSizePixel = 0
					searchIcon.Position = UDim2.fromScale(0, 0.5)
					searchIcon.Size = UDim2.fromOffset(12, 12)
					searchIcon.Parent = search

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingLeft = UDim.new(0, 15)
					uIPadding.Parent = search

					local searchBox = Instance.new("TextBox")
					searchBox.Name = "SearchBox"
					searchBox.CursorPosition = -1
					searchBox.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
					searchBox.PlaceholderText = "Search..."
					searchBox.Text = ""
					searchBox.TextColor3 = Color3.fromRGB(200, 200, 200)
					searchBox.TextSize = 14
					searchBox.TextXAlignment = Enum.TextXAlignment.Left
					searchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					searchBox.BackgroundTransparency = 1
					searchBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					searchBox.BorderSizePixel = 0
					searchBox.Size = UDim2.fromScale(1, 1)
					
					local function CalculateDropdownSize()
						local totalHeight = 0
						local visibleChildrenCount = 0
						local padding = dropdownFrameUIPadding.PaddingTop.Offset + dropdownFrameUIPadding.PaddingBottom.Offset

						for _, v in pairs(dropdownFrame:GetChildren()) do
							if not v:IsA("UIComponent") and v.Visible then
								totalHeight += v.AbsoluteSize.Y
								visibleChildrenCount += 1
							end
						end

						local spacing = dropdownFrameUIListLayout.Padding.Offset * (visibleChildrenCount - 1)

						return totalHeight + spacing + padding
					end

					local function findOption()
						local searchTerm = searchBox.Text:lower()

						for _, v in pairs(OptionObjs) do
							local optionText = v.NameLabel.Text:lower()
							local isVisible = string.find(optionText, searchTerm) ~= nil

							if v.Button.Visible ~= isVisible then
								v.Button.Visible = isVisible
							end
						end

						dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
					end

					searchBox:GetPropertyChangedSignal("Text"):Connect(findOption)

					local uIPadding1 = Instance.new("UIPadding")
					uIPadding1.Name = "UIPadding"
					uIPadding1.PaddingLeft = UDim.new(0, 23)
					uIPadding1.Parent = searchBox

					searchBox.Parent = search
					
					local tweensettings = {
						duration = 0.2,
						easingStyle = Enum.EasingStyle.Quint,
						transparencyIn = 0.2,
						transparencyOut = 0.5,
						checkSizeIncrease = 12,
						checkSizeDecrease = -13,
						waitTime = 1
					}
					
					local function Toggle(optionName, State)
						local option = OptionObjs[optionName]

						if not option then return end

						local checkmark = option.Checkmark
						local optionNameLabel = option.NameLabel

						if State then
							if Settings.Multi then
								if not table.find(Selected, optionName) then
									table.insert(Selected, optionName)
									DropdownFunctions.Value = Selected
								end
							else
								for name, opt in pairs(OptionObjs) do
									if name ~= optionName then
										Tween(opt.Checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											Size = UDim2.new(opt.Checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, opt.Checkmark.Size.Y.Scale, opt.Checkmark.Size.Y.Offset)
										}):Play()
										Tween(opt.NameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											TextTransparency = tweensettings.transparencyOut
										}):Play()
										opt.Checkmark.TextTransparency = 1
									end
								end
								Selected = {optionName}
								DropdownFunctions.Value = Selected[1]
							end
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyIn
							}):Play()
							checkmark.TextTransparency = 0
						else
							if Settings.Multi then
								local idx = table.find(Selected, optionName)
								if idx then
									table.remove(Selected, idx)
								end
							else
								Selected = {}
							end
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyOut
							}):Play()
							checkmark.TextTransparency = 1
						end

						if Settings.Required and #Selected == 0 and not State then
							return
						end

						if #Selected > 0 then
							dropdownName.Text = Settings.Name .. " • " .. table.concat(Selected, ", ")
						else
							dropdownName.Text = Settings.Name
						end
					end

					local dropped = false
					local db = false
					
					local function ToggleDropdown()
						if db then return end
						db = true
						local defaultDropdownSize = 38
						local isDropdownOpen = not dropped
						local targetSize = isDropdownOpen and UDim2.new(1, 0, 0, CalculateDropdownSize()) or UDim2.new(1, 0, 0, defaultDropdownSize)

						local tween = Tween(dropdown, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
							Size = targetSize
						})

						tween:Play()

						if isDropdownOpen then
							dropdownFrame.Visible = true
							tween.Completed:Connect(function()
								db = false
							end)
						else
							tween.Completed:Connect(function()
								dropdownFrame.Visible = false
								db = false
							end)
						end

						dropped = isDropdownOpen
					end

					interact.MouseButton1Click:Connect(ToggleDropdown)
					
					local function addOption(i, v)
						local option = Instance.new("TextButton")
						option.Name = "Option"
						option.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
						option.Text = ""
						option.TextColor3 = Color3.fromRGB(0, 0, 0)
						option.TextSize = 14
						option.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						option.BackgroundTransparency = 1
						option.BorderColor3 = Color3.fromRGB(0, 0, 0)
						option.BorderSizePixel = 0
						option.Size = UDim2.new(1, 0, 0, 30)

						local optionUIPadding = Instance.new("UIPadding")
						optionUIPadding.Name = "OptionUIPadding"
						optionUIPadding.PaddingLeft = UDim.new(0, 15)
						optionUIPadding.Parent = option

						local optionName = Instance.new("TextLabel")
						optionName.Name = "OptionName"
						optionName.FontFace = Font.new(
							assets.interFont,
							Enum.FontWeight.Medium,
							Enum.FontStyle.Normal
						)
						optionName.Text = v
						optionName.RichText = true
						optionName.TextColor3 = Color3.fromRGB(255, 255, 255)
						optionName.TextSize = 13
						optionName.TextTransparency = 0.5
						optionName.TextTruncate = Enum.TextTruncate.AtEnd
						optionName.TextXAlignment = Enum.TextXAlignment.Left
						optionName.TextYAlignment = Enum.TextYAlignment.Top
						optionName.AnchorPoint = Vector2.new(0, 0.5)
						optionName.AutomaticSize = Enum.AutomaticSize.XY
						optionName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						optionName.BackgroundTransparency = 1
						optionName.BorderColor3 = Color3.fromRGB(0, 0, 0)
						optionName.BorderSizePixel = 0
						optionName.Position = UDim2.fromScale(1.3e-07, 0.5)
						optionName.Parent = option

						local optionUIListLayout = Instance.new("UIListLayout")
						optionUIListLayout.Name = "OptionUIListLayout"
						optionUIListLayout.Padding = UDim.new(0, 10)
						optionUIListLayout.FillDirection = Enum.FillDirection.Horizontal
						optionUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
						optionUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
						optionUIListLayout.Parent = option

						local checkmark = Instance.new("TextLabel")
						checkmark.Name = "Checkmark"
						checkmark.FontFace = Font.new(
							assets.interFont,
							Enum.FontWeight.Medium,
							Enum.FontStyle.Normal
						)
						checkmark.Text = "✓"
						checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
						checkmark.TextSize = 13
						checkmark.TextTransparency = 1
						checkmark.TextXAlignment = Enum.TextXAlignment.Left
						checkmark.TextYAlignment = Enum.TextYAlignment.Top
						checkmark.AnchorPoint = Vector2.new(0, 0.5)
						checkmark.AutomaticSize = Enum.AutomaticSize.Y
						checkmark.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						checkmark.BackgroundTransparency = 1
						checkmark.BorderColor3 = Color3.fromRGB(0, 0, 0)
						checkmark.BorderSizePixel = 0
						checkmark.LayoutOrder = -1
						checkmark.Position = UDim2.fromScale(1.3e-07, 0.5)
						checkmark.Size = UDim2.fromOffset(-10, 0)
						checkmark.Parent = option

						option.Parent = dropdownFrame

						dropdownFrame.Parent = dropdown
						OptionObjs[v] = {
							Index = i,
							Button = option,
							NameLabel = optionName,
							Checkmark = checkmark
						}

						local tweensettings = {
							duration = 0.2,
							easingStyle = Enum.EasingStyle.Quint,
							transparencyIn = 0.2,
							transparencyOut = 0.5,
							checkSizeIncrease = 12,
							checkSizeDecrease = -optionUIListLayout.Padding.Offset,
							waitTime = 1
						}
						local tweens = {
							checkIn = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}),
							checkOut = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}),
							nameIn = Tween(optionName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								TextTransparency = tweensettings.transparencyIn
							}),
							nameOut = Tween(optionName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								TextTransparency = tweensettings.transparencyOut
							})
						}

						local isSelected = false
						if Settings.Default then
							if Settings.Multi then
								isSelected = table.find(Settings.Default, v) and true or false
							else
								isSelected = (Settings.Default == i) and true or false
							end
						end
						Toggle(v, isSelected)

						local option = OptionObjs[v].Button

						option.MouseButton1Click:Connect(function()
							local isSelected = table.find(Selected, v) and true or false
							local newSelected = not isSelected

							if Settings.Required and not newSelected and #Selected <= 1 then
								return
							end

							Toggle(v, newSelected)

							task.spawn(function()
								if Settings.Multi then
									local Return = {}
									for _, opt in ipairs(Selected) do
										Return[opt] = true
									end
									if Settings.Callback then
										Settings.Callback(Return)
									end

								else
									if newSelected and Settings.Callback then
										Settings.Callback(Selected[1] or nil)
									end
								end
							end)
						end)
						
						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end

					for i, v in pairs(Settings.Options) do
						addOption(i, v)
					end
					
					function DropdownFunctions:UpdateName(New)
						dropdownName.Text = New
					end
					function DropdownFunctions:SetVisibility(State)
						dropdown.Visible = State
					end
					function DropdownFunctions:UpdateSelection(newSelection)
						if type(newSelection) == "number" then
							for option, data in pairs(OptionObjs) do
								local isSelected = data.Index == newSelection
								Toggle(option, isSelected)
							end
						elseif type(newSelection) == "table" then
							for option, data in pairs(OptionObjs) do
								local isSelected = table.find(newSelection, option) ~= nil
								Toggle(option, isSelected)
							end
						end
					end
					function DropdownFunctions:InsertOptions(newOptions)
						Settings.Options = newOptions
						for i, v in pairs(newOptions) do
							addOption(i, v)
						end
					end
					function DropdownFunctions:ClearOptions()
						for _, optionData in pairs(OptionObjs) do
							optionData.Button:Destroy()
						end
						OptionObjs = {}
						Selected = {}
						
						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end
					function DropdownFunctions:GetOptions()
						local optionsStatus = {}

						for option, data in pairs(OptionObjs) do
							local isSelected = table.find(Selected, option) and true or false
							optionsStatus[option] = isSelected
						end

						return optionsStatus
					end
					
					function DropdownFunctions:RemoveOptions(remove)
						for _, optionName in ipairs(remove) do
							local optionData = OptionObjs[optionName]

							if optionData then
								for i = #Selected, 1, -1 do
									if Selected[i] == optionName then
										table.remove(Selected, i)
									end
								end

								optionData.Button:Destroy()

								OptionObjs[optionName] = nil
							end
						end
						
						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end
					function DropdownFunctions:IsOption(optionName)
						return OptionObjs[optionName] ~= nil
					end

					return DropdownFunctions
				end
				
				function SectionFunctions:Colorpicker(Settings)
					local ColorpickerFunctions = {}
					
					local isAlpha = Settings.Alpha and true or false
					ColorpickerFunctions.Color = Settings.Default
					ColorpickerFunctions.Alpha = isAlpha and Settings.Alpha
					
					local colorpicker = Instance.new("Frame")
					colorpicker.Name = "Colorpicker"
					colorpicker.AutomaticSize = Enum.AutomaticSize.Y
					colorpicker.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					colorpicker.BackgroundTransparency = 1
					colorpicker.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorpicker.BorderSizePixel = 0
					colorpicker.Size = UDim2.new(1, 0, 0, 38)
					colorpicker.Parent = section

					local colorpickerName = Instance.new("TextLabel")
					colorpickerName.Name = "KeybindName"
					colorpickerName.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					colorpickerName.Text = Settings.Name
					colorpickerName.TextColor3 = Color3.fromRGB(255, 255, 255)
					colorpickerName.TextSize = 13
					colorpickerName.TextTransparency = 0.5
					colorpickerName.RichText = true
					colorpickerName.TextTruncate = Enum.TextTruncate.AtEnd
					colorpickerName.TextXAlignment = Enum.TextXAlignment.Left
					colorpickerName.TextYAlignment = Enum.TextYAlignment.Top
					colorpickerName.AnchorPoint = Vector2.new(0, 0.5)
					colorpickerName.AutomaticSize = Enum.AutomaticSize.XY
					colorpickerName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorpickerName.BackgroundTransparency = 1
					colorpickerName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorpickerName.BorderSizePixel = 0
					colorpickerName.Position = UDim2.fromScale(0, 0.5)
					colorpickerName.Parent = colorpicker

					local colorCbg = Instance.new("ImageLabel")
					colorCbg.Name = "NewColor"
					colorCbg.Image = "rbxassetid://121484455191370"
					colorCbg.ScaleType = Enum.ScaleType.Tile
					colorCbg.TileSize = UDim2.fromOffset(500, 500)
					colorCbg.AnchorPoint = Vector2.new(1, 0.5)
					colorCbg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorCbg.BackgroundTransparency = 1
					colorCbg.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorCbg.BorderSizePixel = 0
					colorCbg.Position = UDim2.fromScale(1, 0.5)
					colorCbg.Size = UDim2.fromOffset(21, 21)

					local colorC = Instance.new("Frame")
					colorC.Name = "Color"
					colorC.AnchorPoint = Vector2.new(0.5, 0.5)
					colorC.BackgroundColor3 = ColorpickerFunctions.Color
					colorC.BorderSizePixel = 0
					colorC.Position = UDim2.fromScale(0.5, 0.5)
					colorC.Size = UDim2.fromScale(1, 1)
					colorC.BackgroundTransparency = ColorpickerFunctions.Alpha or 0

					local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(0, 6)
					uICorner.Parent = colorC

					local interact = Instance.new("TextButton")
					interact.Name = "Interact"
					interact.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
					interact.Text = ""
					interact.TextColor3 = Color3.fromRGB(0, 0, 0)
					interact.TextSize = 14
					interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					interact.BackgroundTransparency = 1
					interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interact.BorderSizePixel = 0
					interact.Size = UDim2.fromScale(1, 1)
					interact.Parent = colorC

					colorC.Parent = colorCbg

					local uICorner1 = Instance.new("UICorner")
					uICorner1.Name = "UICorner"
					uICorner1.CornerRadius = UDim.new(0, 8)
					uICorner1.Parent = colorCbg

					colorCbg.Parent = colorpicker

					local colorPicker = Instance.new("Frame")
					colorPicker.Name = "ColorPicker"
					colorPicker.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					colorPicker.BackgroundTransparency = 0.5
					colorPicker.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorPicker.BorderSizePixel = 0
					colorPicker.Size = UDim2.fromScale(1, 1)
					colorPicker.Visible = false
					
					local baseUICorner = Instance.new("UICorner")
					baseUICorner.Name = "BaseUICorner"
					baseUICorner.CornerRadius = UDim.new(0, 10)
					baseUICorner.Parent = colorPicker

					local prompt = Instance.new("Frame")
					prompt.Name = "Prompt"
					prompt.AnchorPoint = Vector2.new(0.5, 0.5)
					prompt.AutomaticSize = Enum.AutomaticSize.Y
					prompt.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
					prompt.BorderColor3 = Color3.fromRGB(0, 0, 0)
					prompt.BorderSizePixel = 0
					prompt.Position = UDim2.fromScale(0.5, 0.5)
					prompt.Size = UDim2.fromOffset(420, 0)

					local globalSettingsUIStroke = Instance.new("UIStroke")
					globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
					globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
					globalSettingsUIStroke.Transparency = 0.9
					globalSettingsUIStroke.Parent = prompt

					local globalSettingsUICorner = Instance.new("UICorner")
					globalSettingsUICorner.Name = "GlobalSettingsUICorner"
					globalSettingsUICorner.CornerRadius = UDim.new(0, 10)
					globalSettingsUICorner.Parent = prompt

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.Padding = UDim.new(0, 10)
					uIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = prompt

					local colorOptions = Instance.new("Frame")
					colorOptions.Name = "ColorOptions"
					colorOptions.AutomaticSize = Enum.AutomaticSize.XY
					colorOptions.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorOptions.BackgroundTransparency = 1
					colorOptions.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorOptions.BorderSizePixel = 0
					colorOptions.LayoutOrder = 1
					colorOptions.Size = UDim2.fromScale(1, 0)

					local value = Instance.new("TextButton")
					value.Name = "Value"
					value.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
					value.Text = ""
					value.TextColor3 = Color3.fromRGB(0, 0, 0)
					value.TextSize = 14
					value.AutoButtonColor = false
					value.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					value.BorderColor3 = Color3.fromRGB(0, 0, 0)
					value.BorderSizePixel = 0
					value.LayoutOrder = 1
					value.Position = UDim2.fromScale(0.092, 0.886)
					value.Size = UDim2.new(1, 0, 0, 15)

					local uIGradient = Instance.new("UIGradient")
					uIGradient.Name = "UIGradient"
					uIGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
					})
					uIGradient.Parent = value

					local slide = Instance.new("Frame")
					slide.Name = "Slide"
					slide.AnchorPoint = Vector2.new(0, 0.5)
					slide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					slide.BorderColor3 = Color3.fromRGB(27, 42, 53)
					slide.BorderSizePixel = 0
					slide.Position = UDim2.fromScale(0, 0.5)
					slide.Size = UDim2.new(0, 13, 1, 8)

					local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(1, 0)
					uICorner.Parent = slide

					local uIStroke = Instance.new("UIStroke")
					uIStroke.Name = "UIStroke"
					uIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					uIStroke.Transparency = 0.5
					uIStroke.Parent = slide

					slide.Parent = value

					local uICorner1 = Instance.new("UICorner")
					uICorner1.Name = "UICorner"
					uICorner1.CornerRadius = UDim.new(0, 6)
					uICorner1.Parent = value

					local uIStroke1 = Instance.new("UIStroke")
					uIStroke1.Name = "UIStroke"
					uIStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					uIStroke1.Color = Color3.fromRGB(255, 255, 255)
					uIStroke1.Transparency = 0.9

					local uIGradient1 = Instance.new("UIGradient")
					uIGradient1.Name = "UIGradient"
					uIGradient1.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
					})
					uIGradient1.Rotation = 180
					uIGradient1.Parent = uIStroke1

					uIStroke1.Parent = value

					value.Parent = colorOptions

					local uIListLayout1 = Instance.new("UIListLayout")
					uIListLayout1.Name = "UIListLayout"
					uIListLayout1.Padding = UDim.new(0, 25)
					uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout1.Parent = colorOptions

					local wheel = Instance.new("Frame")
					wheel.Name = "Wheel"
					wheel.AutomaticSize = Enum.AutomaticSize.Y
					wheel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					wheel.BackgroundTransparency = 1
					wheel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					wheel.BorderSizePixel = 0
					wheel.Size = UDim2.new(1, 0, 0, 100)

					local wheel1 = Instance.new("ImageButton")
					wheel1.Name = "Wheel"
					wheel1.Image = "rbxassetid://2849458409"
					wheel1.AutoButtonColor = false
					wheel1.Active = false
					wheel1.BackgroundColor3 = Color3.fromRGB(248, 248, 248)
					wheel1.BackgroundTransparency = 1
					wheel1.BorderColor3 = Color3.fromRGB(27, 42, 53)
					wheel1.Selectable = false
					wheel1.Size = UDim2.fromOffset(220, 220)
					wheel1.SizeConstraint = Enum.SizeConstraint.RelativeYY
		
					local target = Instance.new("ImageLabel")
					target.Name = "Target"
					target.Image = "rbxassetid://73265255323268"
					target.ImageColor3 = Color3.fromRGB(0, 0, 0)
					target.AnchorPoint = Vector2.new(0.5, 0.5)
					target.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					target.BackgroundTransparency = 1
					target.BorderColor3 = Color3.fromRGB(27, 42, 53)
					target.Position = UDim2.fromScale(0.5, 0.5)
					target.Size = UDim2.fromOffset(22, 22)
					target.SizeConstraint = Enum.SizeConstraint.RelativeYY
					target.Parent = wheel1

					wheel1.Parent = wheel

					local inputs = Instance.new("Frame")
					inputs.Name = "Inputs"
					inputs.AnchorPoint = Vector2.new(1, 0.5)
					inputs.AutomaticSize = Enum.AutomaticSize.XY
					inputs.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputs.BackgroundTransparency = 1
					inputs.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputs.BorderSizePixel = 0
					inputs.LayoutOrder = 1
					inputs.Position = UDim2.fromScale(1, 0.5)

					local uIListLayout2 = Instance.new("UIListLayout")
					uIListLayout2.Name = "UIListLayout"
					uIListLayout2.Padding = UDim.new(0, 5)
					uIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout2.Parent = inputs

					local red = Instance.new("Frame")
					red.Name = "Red"
					red.AutomaticSize = Enum.AutomaticSize.XY
					red.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					red.BackgroundTransparency = 1
					red.BorderColor3 = Color3.fromRGB(0, 0, 0)
					red.BorderSizePixel = 0
					red.LayoutOrder = 1
					red.Size = UDim2.fromOffset(0, 38)

					local inputName = Instance.new("TextLabel")
					inputName.Name = "InputName"
					inputName.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName.Text = "Red"
					inputName.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName.TextSize = 13
					inputName.TextTransparency = 0.5
					inputName.TextTruncate = Enum.TextTruncate.AtEnd
					inputName.TextXAlignment = Enum.TextXAlignment.Left
					inputName.TextYAlignment = Enum.TextYAlignment.Top
					inputName.AnchorPoint = Vector2.new(0, 0.5)
					inputName.AutomaticSize = Enum.AutomaticSize.XY
					inputName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName.BackgroundTransparency = 1
					inputName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName.BorderSizePixel = 0
					inputName.LayoutOrder = 2
					inputName.Position = UDim2.fromScale(0, 0.5)
					inputName.Parent = red

					local uIListLayout3 = Instance.new("UIListLayout")
					uIListLayout3.Name = "UIListLayout"
					uIListLayout3.Padding = UDim.new(0, 15)
					uIListLayout3.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout3.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout3.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout3.Parent = red

					local inputBox = Instance.new("TextBox")
					inputBox.Name = "InputBox"
					inputBox.ClearTextOnFocus = false
					inputBox.CursorPosition = -1
					inputBox.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox.Text = "255"
					inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.TextSize = 12
					inputBox.TextTransparency = 0.4
					inputBox.TextXAlignment = Enum.TextXAlignment.Left
					inputBox.AnchorPoint = Vector2.new(1, 0.5)
					inputBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.BackgroundTransparency = 0.95
					inputBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox.BorderSizePixel = 0
					inputBox.ClipsDescendants = true
					inputBox.LayoutOrder = 1
					inputBox.Position = UDim2.fromScale(1, 0.5)
					inputBox.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner = Instance.new("UICorner")
					inputBoxUICorner.Name = "InputBoxUICorner"
					inputBoxUICorner.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner.Parent = inputBox

					local inputBoxUIStroke = Instance.new("UIStroke")
					inputBoxUIStroke.Name = "InputBoxUIStroke"
					inputBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke.Transparency = 0.9
					inputBoxUIStroke.Parent = inputBox

					local inputBoxUISizeConstraint = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint.Parent = inputBox

					local inputBoxUIPadding = Instance.new("UIPadding")
					inputBoxUIPadding.Name = "InputBoxUIPadding"
					inputBoxUIPadding.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding.Parent = inputBox

					inputBox.Parent = red

					red.Parent = inputs

					local green = Instance.new("Frame")
					green.Name = "Green"
					green.AutomaticSize = Enum.AutomaticSize.XY
					green.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					green.BackgroundTransparency = 1
					green.BorderColor3 = Color3.fromRGB(0, 0, 0)
					green.BorderSizePixel = 0
					green.LayoutOrder = 2
					green.Size = UDim2.fromOffset(0, 38)

					local inputName1 = Instance.new("TextLabel")
					inputName1.Name = "InputName"
					inputName1.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName1.Text = "Green"
					inputName1.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName1.TextSize = 13
					inputName1.TextTransparency = 0.5
					inputName1.TextTruncate = Enum.TextTruncate.AtEnd
					inputName1.TextXAlignment = Enum.TextXAlignment.Left
					inputName1.TextYAlignment = Enum.TextYAlignment.Top
					inputName1.AnchorPoint = Vector2.new(0, 0.5)
					inputName1.AutomaticSize = Enum.AutomaticSize.XY
					inputName1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName1.BackgroundTransparency = 1
					inputName1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName1.BorderSizePixel = 0
					inputName1.LayoutOrder = 2
					inputName1.Position = UDim2.fromScale(0, 0.5)
					inputName1.Parent = green

					local uIListLayout4 = Instance.new("UIListLayout")
					uIListLayout4.Name = "UIListLayout"
					uIListLayout4.Padding = UDim.new(0, 15)
					uIListLayout4.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout4.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout4.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout4.Parent = green

					local inputBox1 = Instance.new("TextBox")
					inputBox1.Name = "InputBox"
					inputBox1.ClearTextOnFocus = false
					inputBox1.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox1.Text = "255"
					inputBox1.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox1.TextSize = 12
					inputBox1.TextTransparency = 0.4
					inputBox1.TextXAlignment = Enum.TextXAlignment.Left
					inputBox1.AnchorPoint = Vector2.new(1, 0.5)
					inputBox1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox1.BackgroundTransparency = 0.95
					inputBox1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox1.BorderSizePixel = 0
					inputBox1.ClipsDescendants = true
					inputBox1.LayoutOrder = 1
					inputBox1.Position = UDim2.fromScale(1, 0.5)
					inputBox1.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner1 = Instance.new("UICorner")
					inputBoxUICorner1.Name = "InputBoxUICorner"
					inputBoxUICorner1.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner1.Parent = inputBox1

					local inputBoxUIStroke1 = Instance.new("UIStroke")
					inputBoxUIStroke1.Name = "InputBoxUIStroke"
					inputBoxUIStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke1.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke1.Transparency = 0.9
					inputBoxUIStroke1.Parent = inputBox1

					local inputBoxUISizeConstraint1 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint1.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint1.Parent = inputBox1

					local inputBoxUIPadding1 = Instance.new("UIPadding")
					inputBoxUIPadding1.Name = "InputBoxUIPadding"
					inputBoxUIPadding1.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding1.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding1.Parent = inputBox1

					inputBox1.Parent = green

					green.Parent = inputs

					local blue = Instance.new("Frame")
					blue.Name = "Blue"
					blue.AutomaticSize = Enum.AutomaticSize.XY
					blue.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					blue.BackgroundTransparency = 1
					blue.BorderColor3 = Color3.fromRGB(0, 0, 0)
					blue.BorderSizePixel = 0
					blue.LayoutOrder = 3
					blue.Size = UDim2.fromOffset(0, 38)

					local inputName2 = Instance.new("TextLabel")
					inputName2.Name = "InputName"
					inputName2.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName2.Text = "Blue"
					inputName2.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName2.TextSize = 13
					inputName2.TextTransparency = 0.5
					inputName2.TextTruncate = Enum.TextTruncate.AtEnd
					inputName2.TextXAlignment = Enum.TextXAlignment.Left
					inputName2.TextYAlignment = Enum.TextYAlignment.Top
					inputName2.AnchorPoint = Vector2.new(0, 0.5)
					inputName2.AutomaticSize = Enum.AutomaticSize.XY
					inputName2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName2.BackgroundTransparency = 1
					inputName2.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName2.BorderSizePixel = 0
					inputName2.LayoutOrder = 2
					inputName2.Position = UDim2.fromScale(0, 0.5)
					inputName2.Parent = blue

					local uIListLayout5 = Instance.new("UIListLayout")
					uIListLayout5.Name = "UIListLayout"
					uIListLayout5.Padding = UDim.new(0, 15)
					uIListLayout5.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout5.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout5.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout5.Parent = blue

					local inputBox2 = Instance.new("TextBox")
					inputBox2.Name = "InputBox"
					inputBox2.ClearTextOnFocus = false
					inputBox2.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox2.Text = "255"
					inputBox2.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox2.TextSize = 12
					inputBox2.TextTransparency = 0.4
					inputBox2.TextXAlignment = Enum.TextXAlignment.Left
					inputBox2.AnchorPoint = Vector2.new(1, 0.5)
					inputBox2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox2.BackgroundTransparency = 0.95
					inputBox2.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox2.BorderSizePixel = 0
					inputBox2.ClipsDescendants = true
					inputBox2.LayoutOrder = 1
					inputBox2.Position = UDim2.fromScale(1, 0.5)
					inputBox2.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner2 = Instance.new("UICorner")
					inputBoxUICorner2.Name = "InputBoxUICorner"
					inputBoxUICorner2.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner2.Parent = inputBox2

					local inputBoxUIStroke2 = Instance.new("UIStroke")
					inputBoxUIStroke2.Name = "InputBoxUIStroke"
					inputBoxUIStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke2.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke2.Transparency = 0.9
					inputBoxUIStroke2.Parent = inputBox2

					local inputBoxUISizeConstraint2 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint2.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint2.Parent = inputBox2

					local inputBoxUIPadding2 = Instance.new("UIPadding")
					inputBoxUIPadding2.Name = "InputBoxUIPadding"
					inputBoxUIPadding2.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding2.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding2.Parent = inputBox2

					inputBox2.Parent = blue

					blue.Parent = inputs

					local alpha = Instance.new("Frame")
					alpha.Name = "Alpha"
					alpha.AutomaticSize = Enum.AutomaticSize.XY
					alpha.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					alpha.BackgroundTransparency = 1
					alpha.BorderColor3 = Color3.fromRGB(0, 0, 0)
					alpha.BorderSizePixel = 0
					alpha.LayoutOrder = 4
					alpha.Size = UDim2.fromOffset(0, 38)
					alpha.Visible = isAlpha

					local inputName3 = Instance.new("TextLabel")
					inputName3.Name = "InputName"
					inputName3.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName3.Text = "Alpha"
					inputName3.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName3.TextSize = 13
					inputName3.TextTransparency = 0.5
					inputName3.TextTruncate = Enum.TextTruncate.AtEnd
					inputName3.TextXAlignment = Enum.TextXAlignment.Left
					inputName3.TextYAlignment = Enum.TextYAlignment.Top
					inputName3.AnchorPoint = Vector2.new(0, 0.5)
					inputName3.AutomaticSize = Enum.AutomaticSize.XY
					inputName3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName3.BackgroundTransparency = 1
					inputName3.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName3.BorderSizePixel = 0
					inputName3.LayoutOrder = 2
					inputName3.Position = UDim2.fromScale(0, 0.5)
					inputName3.Parent = alpha

					local uIListLayout6 = Instance.new("UIListLayout")
					uIListLayout6.Name = "UIListLayout"
					uIListLayout6.Padding = UDim.new(0, 15)
					uIListLayout6.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout6.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout6.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout6.Parent = alpha

					local inputBox3 = Instance.new("TextBox")
					inputBox3.Name = "InputBox"
					inputBox3.ClearTextOnFocus = false
					inputBox3.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox3.Text = "0"
					inputBox3.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox3.TextSize = 12
					inputBox3.TextTransparency = 0.4
					inputBox3.TextXAlignment = Enum.TextXAlignment.Left
					inputBox3.AnchorPoint = Vector2.new(1, 0.5)
					inputBox3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox3.BackgroundTransparency = 0.95
					inputBox3.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox3.BorderSizePixel = 0
					inputBox3.ClipsDescendants = true
					inputBox3.LayoutOrder = 1
					inputBox3.Position = UDim2.fromScale(1, 0.5)
					inputBox3.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner3 = Instance.new("UICorner")
					inputBoxUICorner3.Name = "InputBoxUICorner"
					inputBoxUICorner3.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner3.Parent = inputBox3

					local inputBoxUIStroke3 = Instance.new("UIStroke")
					inputBoxUIStroke3.Name = "InputBoxUIStroke"
					inputBoxUIStroke3.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke3.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke3.Transparency = 0.9
					inputBoxUIStroke3.Parent = inputBox3

					local inputBoxUISizeConstraint3 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint3.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint3.Parent = inputBox3

					local inputBoxUIPadding3 = Instance.new("UIPadding")
					inputBoxUIPadding3.Name = "InputBoxUIPadding"
					inputBoxUIPadding3.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding3.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding3.Parent = inputBox3

					inputBox3.Parent = alpha

					alpha.Parent = inputs

					local hex = Instance.new("Frame")
					hex.Name = "Hex"
					hex.AutomaticSize = Enum.AutomaticSize.XY
					hex.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					hex.BackgroundTransparency = 1
					hex.BorderColor3 = Color3.fromRGB(0, 0, 0)
					hex.BorderSizePixel = 0
					hex.Size = UDim2.fromOffset(0, 38)

					local inputName4 = Instance.new("TextLabel")
					inputName4.Name = "InputName"
					inputName4.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputName4.Text = "Hex"
					inputName4.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName4.TextSize = 13
					inputName4.TextTransparency = 0.5
					inputName4.TextTruncate = Enum.TextTruncate.AtEnd
					inputName4.TextXAlignment = Enum.TextXAlignment.Left
					inputName4.TextYAlignment = Enum.TextYAlignment.Top
					inputName4.AnchorPoint = Vector2.new(0, 0.5)
					inputName4.AutomaticSize = Enum.AutomaticSize.XY
					inputName4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName4.BackgroundTransparency = 1
					inputName4.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName4.BorderSizePixel = 0
					inputName4.LayoutOrder = 2
					inputName4.Position = UDim2.fromScale(0, 0.5)
					inputName4.Parent = hex

					local uIListLayout7 = Instance.new("UIListLayout")
					uIListLayout7.Name = "UIListLayout"
					uIListLayout7.Padding = UDim.new(0, 15)
					uIListLayout7.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout7.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout7.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout7.Parent = hex

					local inputBox4 = Instance.new("TextBox")
					inputBox4.Name = "InputBox"
					inputBox4.ClearTextOnFocus = false
					inputBox4.CursorPosition = -1
					inputBox4.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					inputBox4.Text = "255"
					inputBox4.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox4.TextSize = 12
					inputBox4.TextTransparency = 0.4
					inputBox4.TextXAlignment = Enum.TextXAlignment.Left
					inputBox4.AnchorPoint = Vector2.new(1, 0.5)
					inputBox4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox4.BackgroundTransparency = 0.95
					inputBox4.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox4.BorderSizePixel = 0
					inputBox4.ClipsDescendants = true
					inputBox4.LayoutOrder = 1
					inputBox4.Position = UDim2.fromScale(1, 0.5)
					inputBox4.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner4 = Instance.new("UICorner")
					inputBoxUICorner4.Name = "InputBoxUICorner"
					inputBoxUICorner4.CornerRadius = UDim.new(0, 4)
					inputBoxUICorner4.Parent = inputBox4

					local inputBoxUIStroke4 = Instance.new("UIStroke")
					inputBoxUIStroke4.Name = "InputBoxUIStroke"
					inputBoxUIStroke4.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke4.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke4.Transparency = 0.9
					inputBoxUIStroke4.Parent = inputBox4

					local inputBoxUISizeConstraint4 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint4.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint4.Parent = inputBox4

					local inputBoxUIPadding4 = Instance.new("UIPadding")
					inputBoxUIPadding4.Name = "InputBoxUIPadding"
					inputBoxUIPadding4.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding4.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding4.Parent = inputBox4

					inputBox4.Parent = hex

					hex.Parent = inputs

					inputs.Parent = wheel

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingRight = UDim.new(0, 5)
					uIPadding.Parent = wheel

					wheel.Parent = colorOptions

					local colorWells = Instance.new("Frame")
					colorWells.Name = "ColorWells"
					colorWells.AutomaticSize = Enum.AutomaticSize.Y
					colorWells.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorWells.BackgroundTransparency = 1
					colorWells.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorWells.BorderSizePixel = 0
					colorWells.LayoutOrder = 2
					colorWells.Size = UDim2.fromScale(1, 0)

					local uIGridLayout = Instance.new("UIGridLayout")
					uIGridLayout.Name = "UIGridLayout"
					uIGridLayout.CellPadding = UDim2.fromOffset(10, 0)
					uIGridLayout.CellSize = UDim2.new(0.5, -5, 0, 30)
					uIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIGridLayout.Parent = colorWells

					local newColor = Instance.new("ImageLabel")
					newColor.Name = "NewColor"
					newColor.Image = "rbxassetid://121484455191370"
					newColor.ScaleType = Enum.ScaleType.Tile
					newColor.TileSize = UDim2.fromOffset(500, 500)
					newColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					newColor.BackgroundTransparency = 1
					newColor.BorderColor3 = Color3.fromRGB(0, 0, 0)
					newColor.BorderSizePixel = 0
					newColor.Size = UDim2.fromOffset(100, 100)

					local uICorner2 = Instance.new("UICorner")
					uICorner2.Name = "UICorner"
					uICorner2.Parent = newColor

					local color = Instance.new("Frame")
					color.Name = "Color"
					color.AnchorPoint = Vector2.new(0.5, 0.5)
					color.BorderColor3 = Color3.fromRGB(27, 42, 53)
					color.BorderSizePixel = 0
					color.Position = UDim2.fromScale(0.5, 0.5)
					color.Size = UDim2.new(1, 1, 1, 1)

					local uICorner3 = Instance.new("UICorner")
					uICorner3.Name = "UICorner"
					uICorner3.Parent = color

					color.Parent = newColor

					newColor.Parent = colorWells

					local oldColor = Instance.new("ImageLabel")
					oldColor.Name = "OldColor"
					oldColor.Image = "rbxassetid://121484455191370"
					oldColor.ScaleType = Enum.ScaleType.Tile
					oldColor.TileSize = UDim2.fromOffset(500, 500)
					oldColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					oldColor.BackgroundTransparency = 1
					oldColor.BorderColor3 = Color3.fromRGB(0, 0, 0)
					oldColor.BorderSizePixel = 0
					oldColor.LayoutOrder = 1
					oldColor.Size = UDim2.fromOffset(100, 100)

					local uICorner4 = Instance.new("UICorner")
					uICorner4.Name = "UICorner"
					uICorner4.Parent = oldColor

					local color1 = Instance.new("Frame")
					color1.Name = "Color"
					color1.AnchorPoint = Vector2.new(0.5, 0.5)
					color1.BorderColor3 = Color3.fromRGB(27, 42, 53)
					color1.BorderSizePixel = 0
					color1.Position = UDim2.fromScale(0.5, 0.5)
					color1.Size = UDim2.new(1, 1, 1, 1)

					local uICorner5 = Instance.new("UICorner")
					uICorner5.Name = "UICorner"
					uICorner5.Parent = color1

					color1.Parent = oldColor

					oldColor.Parent = colorWells

					colorWells.Parent = colorOptions

					colorOptions.Parent = prompt

					local interactions = Instance.new("Frame")
					interactions.Name = "Interactions"
					interactions.AutomaticSize = Enum.AutomaticSize.Y
					interactions.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					interactions.BackgroundTransparency = 1
					interactions.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interactions.BorderSizePixel = 0
					interactions.LayoutOrder = 2
					interactions.Size = UDim2.fromScale(1, 0)

					local uIListLayout8 = Instance.new("UIListLayout")
					uIListLayout8.Name = "UIListLayout"
					uIListLayout8.Padding = UDim.new(0, 10)
					uIListLayout8.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout8.Parent = interactions

					local confirm = Instance.new("TextButton")
					confirm.Name = "Confirm"
					confirm.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					confirm.Text = "Confirm"
					confirm.TextColor3 = Color3.fromRGB(255, 255, 255)
					confirm.TextSize = 15
					confirm.TextTransparency = 0.5
					confirm.TextTruncate = Enum.TextTruncate.AtEnd
					confirm.AutoButtonColor = false
					confirm.AutomaticSize = Enum.AutomaticSize.Y
					confirm.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
					confirm.BorderColor3 = Color3.fromRGB(0, 0, 0)
					confirm.BorderSizePixel = 0
					confirm.Size = UDim2.fromScale(1, 0)

					local uIPadding1 = Instance.new("UIPadding")
					uIPadding1.Name = "UIPadding"
					uIPadding1.PaddingBottom = UDim.new(0, 9)
					uIPadding1.PaddingLeft = UDim.new(0, 10)
					uIPadding1.PaddingRight = UDim.new(0, 10)
					uIPadding1.PaddingTop = UDim.new(0, 9)
					uIPadding1.Parent = confirm

					local baseUICorner = Instance.new("UICorner")
					baseUICorner.Name = "BaseUICorner"
					baseUICorner.CornerRadius = UDim.new(0, 10)
					baseUICorner.Parent = confirm

					confirm.Parent = interactions

					local cancel = Instance.new("TextButton")
					cancel.Name = "Cancel"
					cancel.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					cancel.Text = "Cancel"
					cancel.TextColor3 = Color3.fromRGB(255, 255, 255)
					cancel.TextSize = 15
					cancel.TextTransparency = 0.5
					cancel.TextTruncate = Enum.TextTruncate.AtEnd
					cancel.AutoButtonColor = false
					cancel.AutomaticSize = Enum.AutomaticSize.Y
					cancel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
					cancel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					cancel.BorderSizePixel = 0
					cancel.Size = UDim2.fromScale(1, 0)

					local baseUICorner1 = Instance.new("UICorner")
					baseUICorner1.Name = "BaseUICorner"
					baseUICorner1.CornerRadius = UDim.new(0, 10)
					baseUICorner1.Parent = cancel

					local uIPadding2 = Instance.new("UIPadding")
					uIPadding2.Name = "UIPadding"
					uIPadding2.PaddingBottom = UDim.new(0, 9)
					uIPadding2.PaddingLeft = UDim.new(0, 10)
					uIPadding2.PaddingRight = UDim.new(0, 10)
					uIPadding2.PaddingTop = UDim.new(0, 9)
					uIPadding2.Parent = cancel

					cancel.Parent = interactions

					local uIPadding3 = Instance.new("UIPadding")
					uIPadding3.Name = "UIPadding"
					uIPadding3.PaddingTop = UDim.new(0, 10)
					uIPadding3.Parent = interactions

					interactions.Parent = prompt

					local globalSettingsUIPadding = Instance.new("UIPadding")
					globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
					globalSettingsUIPadding.PaddingBottom = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingLeft = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingRight = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingTop = UDim.new(0, 20)
					globalSettingsUIPadding.Parent = prompt

					local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.Y
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.fromScale(1, 0)

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = Settings.Name
					paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.TextSize = 18
					paragraphHeader.TextTransparency = 0.4
					paragraphHeader.TextWrapped = true
					paragraphHeader.TextYAlignment = Enum.TextYAlignment.Top
					paragraphHeader.AutomaticSize = Enum.AutomaticSize.XY
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.fromScale(1, 0)
					paragraphHeader.Parent = paragraph

					local uIListLayout9 = Instance.new("UIListLayout")
					uIListLayout9.Name = "UIListLayout"
					uIListLayout9.Padding = UDim.new(0, 15)
					uIListLayout9.HorizontalAlignment = Enum.HorizontalAlignment.Center
					uIListLayout9.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout9.Parent = paragraph

					local uIPadding4 = Instance.new("UIPadding")
					uIPadding4.Name = "UIPadding"
					uIPadding4.PaddingBottom = UDim.new(0, 15)
					uIPadding4.Parent = paragraph

					local line = Instance.new("Frame")
					line.Name = "Line"
					line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					line.BackgroundTransparency = 0.9
					line.BorderColor3 = Color3.fromRGB(0, 0, 0)
					line.BorderSizePixel = 0
					line.LayoutOrder = 1
					line.Size = UDim2.new(1, 0, 0, 1)
					line.Parent = paragraph

					paragraph.Parent = prompt

					prompt.Parent = colorPicker

					colorPicker.Parent = base
					
					local fromHSV, fromRGB, v2, udim2 = Color3.fromHSV, Color3.fromRGB, Vector2.new, UDim2.new

					local wheel = wheel1
					local ring = target
					local slider = value
					local colour = color

					-- hex/red/green/blue/alpha are Frames; the editable box is their
					-- child TextBox named "InputBox". The vendored library indexed it as
					-- a field (`hex.InputBox`), which is nil in the real engine - Frame
					-- has no such member - so the Colorpicker threw at the first
					-- modifierInputs use and took the entire menu body down with it.
					local function input_box(frame)
						return frame:FindFirstChild("InputBox")
					end

					local modifierInputs = {
						Hex = input_box(hex),
						Red = input_box(red),
						Green = input_box(green),
						Blue = input_box(blue),
						Alpha = input_box(alpha)
					}

					local Mouse = LocalPlayer:GetMouse()

					local WheelDown, SlideDown = false, false
					local hue, saturation, value = 0, 0, 1

					local function toPolar(v)
						return math.atan2(v.y, v.x), v.magnitude
					end

					local function radToDeg(x)
						return ((x + math.pi) / (2 * math.pi)) * 360
					end

					local function degToRad(degrees)
						return degrees * (math.pi / 180)
					end

					local function hexToRGB(hex)
						hex = hex:gsub("#","")
						if #hex ~= 6 then return 0, 0, 0 end
						local r = tonumber(hex:sub(1, 2), 16) or 0
						local g = tonumber(hex:sub(3, 4), 16) or 0
						local b = tonumber(hex:sub(5, 6), 16) or 0
						return r, g, b
					end

					local function clampInput(value, min, max)
						local num = tonumber(value)
						if num then
							return math.clamp(num, min, max)
						end
						return min
					end

					local function update()
						local c = fromHSV(hue, saturation, value)
						colour.BackgroundColor3 = c
						colour.BackgroundTransparency = clampInput(modifierInputs.Alpha.Text, 0, 1)

						modifierInputs.Red.Text = tostring(math.floor(c.r * 255 + 0.5))
						modifierInputs.Green.Text = tostring(math.floor(c.g * 255 + 0.5))
						modifierInputs.Blue.Text = tostring(math.floor(c.b * 255 + 0.5))
						modifierInputs.Alpha.Text = clampInput(modifierInputs.Alpha.Text, 0, 1)

						local hexColor = string.format("#%02X%02X%02X", 
							math.floor(c.r * 255 + 0.5),
							math.floor(c.g * 255 + 0.5),
							math.floor(c.b * 255 + 0.5))
						modifierInputs.Hex.Text = hexColor
					end

					local function UpdateSlide(iX)
						local rY = iX - slider.AbsolutePosition.X
						local cY = math.clamp(rY, 0, slider.AbsoluteSize.X - slide.AbsoluteSize.X)
						slide.Position = udim2(0, cY, 0.5, 0)
						value = 1 - (cY / (slider.AbsoluteSize.X - slide.AbsoluteSize.X))
						update()
					end

					local function UpdateRing(iX, iY)
						local r = wheel.AbsoluteSize.x / 2
						local d = v2(iX, iY) - wheel.AbsolutePosition - wheel.AbsoluteSize / 2

						if d:Dot(d) > r * r then
							d = d.unit * r
						end

						ring.Position = udim2(0.5, d.x, 0.5, d.y)
						local phi, len = toPolar(d * v2(1, -1))
						hue, saturation = radToDeg(phi) / 360, math.clamp(len / r, 0, 1)
						slider.BackgroundColor3 = fromHSV(hue, saturation, 1)
						update()
					end

					local function UpdateSlideFromValue(value)
						local cY = (1 - value) * (slider.AbsoluteSize.X - slide.AbsoluteSize.X)
						slide.Position = UDim2.new(0, cY, 0.5, 0)
					end

					local function UpdateRingFromHSV(hue, saturation)
						local r = wheel.AbsoluteSize.X / 2
						local phi = degToRad(hue * 360)
						local len = saturation * r
						local x = len * math.cos(phi)
						local y = len * math.sin(phi)

						ring.Position = UDim2.new(0.5, -x, 0.5, y)
						slider.BackgroundColor3 = fromHSV(hue, saturation, 1)
					end

					local function updateFromRGB()
						local r = clampInput(modifierInputs.Red.Text, 0, 255)
						local g = clampInput(modifierInputs.Green.Text, 0, 255)
						local b = clampInput(modifierInputs.Blue.Text, 0, 255)
						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
						update()
					end

					local function updateFromHex()
						local hex = modifierInputs.Hex.Text
						local r, g, b = hexToRGB(hex)

						r = clampInput(r, 0, 255)
						g = clampInput(g, 0, 255)
						b = clampInput(b, 0, 255)

						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()
						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
						update()
					end
					
					local function updateFromSettings()
						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b
						modifierInputs.Alpha.Text = isAlpha and ColorpickerFunctions.Alpha or 0
						
						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()
						
						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)
						colour.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
					end

					wheel.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							WheelDown = true
							UpdateRing(Mouse.X, Mouse.Y)
						end
					end)

					slider.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							SlideDown = true
							UpdateSlide(Mouse.X)
						end
					end)

					slider.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							SlideDown = false
						end
					end)

					wheel.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							WheelDown = false
						end
					end)

					UserInputService.InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							if SlideDown then
								UpdateSlide(Mouse.X)
							elseif WheelDown then
								UpdateRing(Mouse.X, Mouse.Y)
							end
						end
					end)

					local function onFocusEnter(instance)
						local placeholder = instance.Text
						instance.Text = ""
						instance.PlaceholderText = placeholder
					end

					modifierInputs.Hex.FocusLost:Connect(updateFromHex)
					modifierInputs.Red.FocusLost:Connect(updateFromRGB)
					modifierInputs.Green.FocusLost:Connect(updateFromRGB)
					modifierInputs.Blue.FocusLost:Connect(updateFromRGB)
					modifierInputs.Alpha.FocusLost:Connect(update)

					modifierInputs.Hex.Focused:Connect(function()
						onFocusEnter(modifierInputs.Hex)
					end)
					modifierInputs.Red.Focused:Connect(function()
						onFocusEnter(modifierInputs.Red)
					end)
					modifierInputs.Green.Focused:Connect(function()
						onFocusEnter(modifierInputs.Green)
					end)
					modifierInputs.Blue.Focused:Connect(function()
						onFocusEnter(modifierInputs.Blue)
					end)
					modifierInputs.Alpha.Focused:Connect(function()
						onFocusEnter(modifierInputs.Alpha)
					end)
					
					local function makeCanvas()
						local ColorPickerCanvas = Instance.new("CanvasGroup")
						ColorPickerCanvas.Name = "ColorPickerCanvas"
						ColorPickerCanvas.BackgroundTransparency = 1
						ColorPickerCanvas.BorderSizePixel = 0
						ColorPickerCanvas.Size = UDim2.fromScale(1, 1)
						ColorPickerCanvas.ZIndex = 5
						ColorPickerCanvas.GroupTransparency = 1
						ColorPickerCanvas.Parent = base
						ColorPickerCanvas.Visible = false
						return ColorPickerCanvas
					end

					local function transition(isIn)
						local canvas = makeCanvas()
						local tweenTransparency = isIn and 0 or 1
						local stateTransparency = isIn and 1 or 0
						local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine)
						local canvasTween = Tween(canvas, tweenInfo, { GroupTransparency = tweenTransparency })

						colorPicker.Visible = true
						colorPicker.Parent = canvas
						canvas.Visible = true
						canvas.GroupTransparency = stateTransparency
						canvasTween:Play()
						canvasTween.Completed:Wait()

						if not isIn then
							colorPicker.Visible = false
							canvas.Visible = false
						end

						colorPicker.Parent = base
						canvas:Destroy()
					end

					local function colorpickerIn()
						transition(true)
					end

					local function colorpickerOut()
						transition(false)
					end

					interact.MouseButton1Click:Connect(colorpickerIn)
					
					cancel.MouseButton1Click:Connect(colorpickerOut)
					confirm.MouseButton1Click:Connect(function()
						colorpickerOut()
						local c = fromHSV(hue, saturation, value)
						ColorpickerFunctions.Color = Color3.fromRGB(c.r * 255, c.g * 255, c.b * 255)
						ColorpickerFunctions.Alpha = isAlpha and clampInput(modifierInputs.Alpha.Text, 0, 1)
						
						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0
						
						colorC.BackgroundColor3 = ColorpickerFunctions.Color
						colorC.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0
						
						if Settings.Callback then
							task.spawn(function()
								Settings.Callback(ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
							end)
						end
					end)
					
					updateFromSettings()
					
					function ColorpickerFunctions:UpdateName(New)
						colorpickerName.Text = New
					end
					function ColorpickerFunctions:SetVisibility(State)
						colorpicker.Visible = State
					end
			
					function ColorpickerFunctions:SetColor(color3)
						ColorpickerFunctions.Color = color3
						colorC.BackgroundColor3 = color3
						
						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b

						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						color1.BackgroundColor3 = ColorpickerFunctions.Color
						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)

						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
					end
					
					function ColorpickerFunctions:SetAlpha(alpha)
						ColorpickerFunctions.Alpha = alpha
						colorC.Transparency = alpha
						updateFromSettings()
					end
					
					return ColorpickerFunctions
				end
				
				function SectionFunctions:Header(Settings)
					local HeaderFunctions = {}
					
					local header = Instance.new("Frame")
					header.Name = "Header"
					header.AutomaticSize = Enum.AutomaticSize.Y
					header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					header.BackgroundTransparency = 1
					header.BorderColor3 = Color3.fromRGB(0, 0, 0)
					header.BorderSizePixel = 0
					header.LayoutOrder = 0
					header.Size = UDim2.fromScale(1, 0)
					header.Parent = section
					
					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingBottom = UDim.new(0, 5)
					uIPadding.Parent = header

					local headerText = Instance.new("TextLabel")
					headerText.Name = "HeaderText"
					headerText.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					headerText.RichText = true
					headerText.Text = Settings.Text or Settings.Name
					headerText.TextColor3 = Color3.fromRGB(255, 255, 255)
					headerText.TextSize = 16
					headerText.TextTransparency = 0.4
					headerText.TextWrapped = true
					headerText.TextXAlignment = Enum.TextXAlignment.Left
					headerText.AutomaticSize = Enum.AutomaticSize.Y
					headerText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					headerText.BackgroundTransparency = 1
					headerText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					headerText.BorderSizePixel = 0
					headerText.Size = UDim2.fromScale(1, 0)
					headerText.Parent = header
					
					function HeaderFunctions:UpdateName(New)
						headerText.Text = New
					end
					function HeaderFunctions:SetVisibility(State)
						header.Visible = State
					end
					
					return HeaderFunctions
				end
				
				function SectionFunctions:Label(Settings)
					local LabelFunctions = {}
					
					local label = Instance.new("Frame")
					label.Name = "Label"
					label.AutomaticSize = Enum.AutomaticSize.Y
					label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					label.BackgroundTransparency = 1
					label.BorderColor3 = Color3.fromRGB(0, 0, 0)
					label.BorderSizePixel = 0
					label.Size = UDim2.new(1, 0, 0, 38)
					label.Parent = section

					local labelText = Instance.new("TextLabel")
					labelText.Name = "LabelText"
					labelText.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					labelText.RichText = true
					labelText.Text = Settings.Text or Settings.Name -- Settings.Name Deprecated
					labelText.TextColor3 = Color3.fromRGB(255, 255, 255)
					labelText.TextSize = 13
					labelText.TextTransparency = 0.5
					labelText.TextWrapped = true
					labelText.TextXAlignment = Enum.TextXAlignment.Left
					labelText.AutomaticSize = Enum.AutomaticSize.Y
					labelText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					labelText.BackgroundTransparency = 1
					labelText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					labelText.BorderSizePixel = 0
					labelText.Size = UDim2.fromScale(1, 1)
					labelText.Parent = label
					
					function LabelFunctions:UpdateName(New)
						labelText.Text = New
					end
					function LabelFunctions:SetVisibility(State)
						label.Visible = State
					end
					
					return LabelFunctions
				end
				
				function SectionFunctions:SubLabel(Settings)
					local SubLabelFunctions = {}

					local subLabel = Instance.new("Frame")
					subLabel.Name = "SubLabel"
					subLabel.AutomaticSize = Enum.AutomaticSize.Y
					subLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					subLabel.BackgroundTransparency = 1
					subLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					subLabel.BorderSizePixel = 0
					subLabel.Size = UDim2.new(1, 0, 0, 0)
					subLabel.Parent = section

					local subLabelText = Instance.new("TextLabel")
					subLabelText.Name = "SubLabelText"
					subLabelText.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					subLabelText.RichText = true
					subLabelText.Text = Settings.Text or Settings.Name -- Settings.Name Deprecated
					subLabelText.TextColor3 = Color3.fromRGB(255, 255, 255)
					subLabelText.TextSize = 11
					subLabelText.TextTransparency = 0.7
					subLabelText.TextWrapped = true
					subLabelText.TextXAlignment = Enum.TextXAlignment.Left
					subLabelText.AutomaticSize = Enum.AutomaticSize.Y
					subLabelText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					subLabelText.BackgroundTransparency = 1
					subLabelText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					subLabelText.BorderSizePixel = 0
					subLabelText.Size = UDim2.fromScale(1, 1)
					subLabelText.Parent = subLabel

					function SubLabelFunctions:UpdateName(New)
						subLabelText.Text = New
					end
					function SubLabelFunctions:SetVisibility(State)
						subLabel.Visible = State
					end

					return SubLabelFunctions
				end
				
				function SectionFunctions:Paragraph(Settings)
					local ParagraphFunctions = {}

					local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.Y
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.new(1, 0, 0, 38)
					paragraph.Parent = section

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = Settings.Header
					paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.TextSize = 16
					paragraphHeader.TextTransparency = 0.4
					paragraphHeader.TextWrapped = true
					paragraphHeader.TextXAlignment = Enum.TextXAlignment.Left
					paragraphHeader.AutomaticSize = Enum.AutomaticSize.Y
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.fromScale(1, 0)
					paragraphHeader.Parent = paragraph

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.Padding = UDim.new(0, 5)
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = paragraph

					local paragraphBody = Instance.new("TextLabel")
					paragraphBody.Name = "ParagraphBody"
					paragraphBody.FontFace = Font.new(assets.interFont)
					paragraphBody.RichText = true
					paragraphBody.Text = Settings.Body
					paragraphBody.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphBody.TextSize = 13
					paragraphBody.TextTransparency = 0.5
					paragraphBody.TextWrapped = true
					paragraphBody.TextXAlignment = Enum.TextXAlignment.Left
					paragraphBody.AutomaticSize = Enum.AutomaticSize.Y
					paragraphBody.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphBody.BackgroundTransparency = 1
					paragraphBody.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphBody.BorderSizePixel = 0
					paragraphBody.LayoutOrder = 1
					paragraphBody.Size = UDim2.fromScale(1, 0)
					paragraphBody.Parent = paragraph

					function ParagraphFunctions:UpdateHeader(New)
						paragraphHeader.Text = New
					end
					function ParagraphFunctions:UpdateBody(New)
						paragraphBody.Text = New
					end
					function ParagraphFunctions:SetVisibility(State)
						paragraph.Visible = State
					end

					return ParagraphFunctions
				end
				
				function SectionFunctions:Divider()
					local DividerFunctions = {}
					
					local divider = Instance.new("Frame")
					divider.Name = "Divider"
					divider.AnchorPoint = Vector2.new(0, 1)
					divider.AutomaticSize = Enum.AutomaticSize.Y
					divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					divider.BackgroundTransparency = 1
					divider.BorderColor3 = Color3.fromRGB(0, 0, 0)
					divider.BorderSizePixel = 0
					divider.Position = UDim2.fromScale(0, 1)
					divider.Size = UDim2.new(1, 0, 0, 1)
					divider.Parent = section

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingBottom = UDim.new(0, 8)
					uIPadding.PaddingTop = UDim.new(0, 8)
					uIPadding.Parent = divider

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = divider

					local line = Instance.new("Frame")
					line.Name = "Line"
					line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					line.BackgroundTransparency = 0.9
					line.BorderColor3 = Color3.fromRGB(0, 0, 0)
					line.BorderSizePixel = 0
					line.Size = UDim2.new(1, 0, 0, 1)
					line.Parent = divider
					
					function DividerFunctions:Remove()
						divider:Destroy()
					end
					function DividerFunctions:SetVisibility(State)
						divider.Visible = State
					end
					
					return DividerFunctions
				end
				
				function SectionFunctions:Spacer()
					local SpacerFunctions = {}

					local spacer = Instance.new("Frame")
					spacer.Name = "Spacer"
					spacer.AnchorPoint = Vector2.new(0, 1)
					spacer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					spacer.BackgroundTransparency = 1
					spacer.BorderColor3 = Color3.fromRGB(0, 0, 0)
					spacer.BorderSizePixel = 0
					spacer.Position = UDim2.fromScale(0, 1)
					spacer.Parent = section

					function SpacerFunctions:Remove()
						spacer:Destroy()
					end
					function SpacerFunctions:SetVisibility(State)
						spacer.Visible = State
					end

					return SpacerFunctions
				end
				return SectionFunctions
			end

			local function SelectCurrentTab()
				local easetime = 0.15

				if currentTabInstance then
					currentTabInstance.Parent = nil
				end

				for _, v in pairs(tabSwitchersScrollingFrame:GetDescendants()) do
					if v.Name == "TabSwitcher" then
						Tween(v, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							BackgroundTransparency = 1
						}):Play()
						Tween(v:FindFirstChild("TabSwitcherUIStroke"), TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							Transparency = 1
						}):Play()
					end
				end

				tabs[tabSwitcher].Parent = content
				currentTabInstance = tabs[tabSwitcher]
				currentTab.Text = Settings.Name

				Tween(tabSwitcher, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
					BackgroundTransparency = 0.98
				}):Play()
				Tween(tabSwitcherUIStroke, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
					Transparency = 0.95
				}):Play()
			end

			tabSwitcher.MouseButton1Click:Connect(function()
				SelectCurrentTab()
			end)

			function TabFunctions:Select()
				SelectCurrentTab()
			end

			tabs[tabSwitcher] = elements1
			return TabFunctions
		end

		return SectionFunctions
	end

	function WindowFunctions:Notify(Settings)
		local NotificationFunctions = {}
		
		local notification = Instance.new("Frame")
		notification.Name = "Notification"
		notification.AnchorPoint = Vector2.new(0.5, 0.5)
		notification.AutomaticSize = Enum.AutomaticSize.Y
		notification.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		notification.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notification.BorderSizePixel = 0
		notification.Position = UDim2.fromScale(0.5, 0.5)
		notification.Size = UDim2.fromOffset(Settings.SizeX or 250, 0)
		
		notification.Parent = notifications

		local notificationUIStroke = Instance.new("UIStroke")
		notificationUIStroke.Name = "NotificationUIStroke"
		notificationUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		notificationUIStroke.Color = Color3.fromRGB(255, 255, 255)
		notificationUIStroke.Transparency = 0.9
		notificationUIStroke.Parent = notification

		local notificationUICorner = Instance.new("UICorner")
		notificationUICorner.Name = "NotificationUICorner"
		notificationUICorner.CornerRadius = UDim.new(0, 10)
		notificationUICorner.Parent = notification

		local notificationUIScale = Instance.new("UIScale")
		notificationUIScale.Name = "NotificationUIScale"
		notificationUIScale.Parent = notification
		notificationUIScale.Scale = 0

		local notificationInformation = Instance.new("Frame")
		notificationInformation.Name = "NotificationInformation"
		notificationInformation.AutomaticSize = Enum.AutomaticSize.Y
		notificationInformation.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationInformation.BackgroundTransparency = 1
		notificationInformation.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationInformation.BorderSizePixel = 0
		notificationInformation.Size = UDim2.fromScale(1, 1)

		local notificationTitle = Instance.new("TextLabel")
		notificationTitle.Name = "NotificationTitle"
		notificationTitle.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.SemiBold,
			Enum.FontStyle.Normal
		)
		notificationTitle.RichText = true
		notificationTitle.Text = Settings.Title
		notificationTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		notificationTitle.TextSize = 13
		notificationTitle.TextTransparency = 0.2
		notificationTitle.TextTruncate = Enum.TextTruncate.SplitWord
		notificationTitle.TextXAlignment = Enum.TextXAlignment.Left
		notificationTitle.TextYAlignment = Enum.TextYAlignment.Top
		notificationTitle.AutomaticSize = Enum.AutomaticSize.XY
		notificationTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationTitle.BackgroundTransparency = 1
		notificationTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationTitle.BorderSizePixel = 0
		notificationTitle.Size = UDim2.new(1, -12, 0, 0)

		local notificationTitleUIPadding = Instance.new("UIPadding")
		notificationTitleUIPadding.Name = "NotificationTitleUIPadding"
		notificationTitleUIPadding.PaddingRight = UDim.new(0, 25)
		notificationTitleUIPadding.Parent = notificationTitle

		notificationTitle.Parent = notificationInformation

		local notificationDescription = Instance.new("TextLabel")
		notificationDescription.Name = "NotificationDescription"
		notificationDescription.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		notificationDescription.Text = Settings.Description
		notificationDescription.TextColor3 = Color3.fromRGB(255, 255, 255)
		notificationDescription.TextSize = 11
		notificationDescription.TextTransparency = 0.5
		notificationDescription.TextWrapped = true
		notificationDescription.RichText = true
		notificationDescription.TextXAlignment = Enum.TextXAlignment.Left
		notificationDescription.TextYAlignment = Enum.TextYAlignment.Top
		notificationDescription.AutomaticSize = Enum.AutomaticSize.XY
		notificationDescription.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationDescription.BackgroundTransparency = 1
		notificationDescription.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationDescription.BorderSizePixel = 0
		notificationDescription.Size = UDim2.new(1, -12, 0, 0)

		local notificationDescriptionUIPadding = Instance.new("UIPadding")
		notificationDescriptionUIPadding.Name = "NotificationDescriptionUIPadding"
		notificationDescriptionUIPadding.PaddingRight = UDim.new(0, 25)
		notificationDescriptionUIPadding.PaddingTop = UDim.new(0, 17)
		notificationDescriptionUIPadding.Parent = notificationDescription

		notificationDescription.Parent = notificationInformation

		local notificationUIPadding = Instance.new("UIPadding")
		notificationUIPadding.Name = "NotificationUIPadding"
		notificationUIPadding.PaddingBottom = UDim.new(0, 12)
		notificationUIPadding.PaddingLeft = UDim.new(0, 10)
		notificationUIPadding.PaddingRight = UDim.new(0, 10)
		notificationUIPadding.PaddingTop = UDim.new(0, 10)
		notificationUIPadding.Parent = notificationInformation

		notificationInformation.Parent = notification

		local notificationControls = Instance.new("Frame")
		notificationControls.Name = "NotificationControls"
		notificationControls.AutomaticSize = Enum.AutomaticSize.Y
		notificationControls.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationControls.BackgroundTransparency = 1
		notificationControls.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationControls.BorderSizePixel = 0
		notificationControls.Size = UDim2.fromScale(1, 1)

		local interactable = Instance.new("TextButton")
		interactable.Name = "Interactable"
		interactable.FontFace = Font.new(assets.interFont)
		interactable.Text = "✓"
		interactable.TextColor3 = Color3.fromRGB(255, 255, 255)
		interactable.TextSize = 17
		interactable.TextTransparency = 0.2
		interactable.AnchorPoint = Vector2.new(1, 0.5)
		interactable.AutomaticSize = Enum.AutomaticSize.XY
		interactable.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		interactable.BackgroundTransparency = 1
		interactable.BorderColor3 = Color3.fromRGB(0, 0, 0)
		interactable.BorderSizePixel = 0
		interactable.LayoutOrder = 1
		interactable.Position = UDim2.fromScale(1, 0.5)
		interactable.Parent = notificationControls

		local uIPadding = Instance.new("UIPadding")
		uIPadding.Name = "UIPadding"
		uIPadding.PaddingBottom = UDim.new(0, 6)
		uIPadding.PaddingRight = UDim.new(0, 13)
		uIPadding.PaddingTop = UDim.new(0, 6)
		uIPadding.Parent = notificationControls

		notificationControls.Parent = notification
		
		local tweens = {
			In = Tween(notificationUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = Settings.Scale or 1
			}),
			Out = Tween(notificationUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 0
			}),
		}
		
		local styles = {
			None = function() interactable:Destroy() end,
			Confirm = function() interactable.Text = "✓" end,
			Cancel = function() interactable.Text = "✗" end
		}

		local style = styles[Settings.Style] or function() interactable:Destroy() end
		style()

		if interactable then
			interactable.MouseButton1Click:Connect(function()
				NotificationFunctions:Cancel()
				if Settings.Callback then
					task.spawn(Settings.Callback)
				end
			end)
		end
	
		local AnimateNotification = task.spawn(function()
			tweens.In:Play()
			
			Settings.Lifetime = Settings.Lifetime or 3

			if Settings.Lifetime ~= 0 then
				task.wait(Settings.Lifetime)

				local out = tweens.Out
				out:Play()
				out.Completed:Wait()
				notification:Destroy()
			end
		end)
		
		function NotificationFunctions:UpdateTitle(New)
			notificationTitle.Text = New
		end
		
		function NotificationFunctions:UpdateDescription(New)
			notificationDescription.Text = New
		end
		
		function NotificationFunctions:Resize(X)
			local targ = X or 250
			notification.Size = UDim2.fromOffset(targ, 0)
		end
		
		function NotificationFunctions:Cancel()
			task.cancel(AnimateNotification)
			
			local out = tweens.Out
			out:Play()
			out.Completed:Wait()
			notification:Destroy()
		end
		
		return NotificationFunctions
	end
	
	function WindowFunctions:Dialog(Settings)
		local DialogFunctions = {}
		
		local dialogCanvas = Instance.new("CanvasGroup")
		dialogCanvas.Name = "DialogCanvas"
		dialogCanvas.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dialogCanvas.BackgroundTransparency = 1
		dialogCanvas.BorderColor3 = Color3.fromRGB(0, 0, 0)
		dialogCanvas.BorderSizePixel = 0
		dialogCanvas.Size = UDim2.fromScale(1, 1)
		dialogCanvas.GroupTransparency = 1
		dialogCanvas.Parent = base

		local dialog = Instance.new("Frame")
		dialog.Name = "Dialog"
		dialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		dialog.BackgroundTransparency = 0.5
		dialog.BorderColor3 = Color3.fromRGB(0, 0, 0)
		dialog.BorderSizePixel = 0
		dialog.Size = UDim2.fromScale(1, 1)

		local baseUICorner = Instance.new("UICorner")
		baseUICorner.Name = "BaseUICorner"
		baseUICorner.CornerRadius = UDim.new(0, 10)
		baseUICorner.Parent = dialog

		local prompt = Instance.new("Frame")
		prompt.Name = "Prompt"
		prompt.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.AutomaticSize = Enum.AutomaticSize.Y
		prompt.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		prompt.BorderColor3 = Color3.fromRGB(0, 0, 0)
		prompt.BorderSizePixel = 0
		prompt.Position = UDim2.fromScale(0.5, 0.5)
		prompt.Size = UDim2.fromOffset(280, 0)

		local globalSettingsUIStroke = Instance.new("UIStroke")
		globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
		globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
		globalSettingsUIStroke.Transparency = 0.9
		globalSettingsUIStroke.Parent = prompt

		local globalSettingsUICorner = Instance.new("UICorner")
		globalSettingsUICorner.Name = "GlobalSettingsUICorner"
		globalSettingsUICorner.CornerRadius = UDim.new(0, 10)
		globalSettingsUICorner.Parent = prompt

		local globalSettingsUIPadding = Instance.new("UIPadding")
		globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
		globalSettingsUIPadding.PaddingBottom = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingLeft = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingRight = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingTop = UDim.new(0, 20)
		globalSettingsUIPadding.Parent = prompt

		local paragraph = Instance.new("Frame")
		paragraph.Name = "Paragraph"
		paragraph.AutomaticSize = Enum.AutomaticSize.Y
		paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		paragraph.BackgroundTransparency = 1
		paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraph.BorderSizePixel = 0
		paragraph.Size = UDim2.new(1, 0, 0, 38)

		local paragraphHeader = Instance.new("TextLabel")
		paragraphHeader.Name = "ParagraphHeader"
		paragraphHeader.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.SemiBold,
			Enum.FontStyle.Normal
		)
		paragraphHeader.RichText = true
		paragraphHeader.Text = Settings.Title
		paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
		paragraphHeader.TextSize = 18
		paragraphHeader.TextTransparency = 0.4
		paragraphHeader.TextWrapped = true
		paragraphHeader.AutomaticSize = Enum.AutomaticSize.Y
		paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		paragraphHeader.BackgroundTransparency = 1
		paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraphHeader.BorderSizePixel = 0
		paragraphHeader.Size = UDim2.fromScale(1, 0)
		paragraphHeader.Parent = paragraph

		local uIListLayout = Instance.new("UIListLayout")
		uIListLayout.Name = "UIListLayout"
		uIListLayout.Padding = UDim.new(0, 15)
		uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout.Parent = paragraph

		local paragraphBody = Instance.new("TextLabel")
		paragraphBody.Name = "ParagraphBody"
		paragraphBody.FontFace = Font.new(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		paragraphBody.RichText = true
		paragraphBody.Text = Settings.Description
		paragraphBody.TextColor3 = Color3.fromRGB(255, 255, 255)
		paragraphBody.TextSize = 14
		paragraphBody.TextTransparency = 0.5
		paragraphBody.TextWrapped = true
		paragraphBody.AutomaticSize = Enum.AutomaticSize.Y
		paragraphBody.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		paragraphBody.BackgroundTransparency = 1
		paragraphBody.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraphBody.BorderSizePixel = 0
		paragraphBody.LayoutOrder = 1
		paragraphBody.Size = UDim2.fromScale(1, 0)
		paragraphBody.Parent = paragraph

		paragraph.Parent = prompt

		local interactions = Instance.new("Frame")
		interactions.Name = "Interactions"
		interactions.AutomaticSize = Enum.AutomaticSize.Y
		interactions.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		interactions.BackgroundTransparency = 1
		interactions.BorderColor3 = Color3.fromRGB(0, 0, 0)
		interactions.BorderSizePixel = 0
		interactions.LayoutOrder = 1
		interactions.Size = UDim2.fromScale(1, 0)

		local uIListLayout1 = Instance.new("UIListLayout")
		uIListLayout1.Name = "UIListLayout"
		uIListLayout1.Padding = UDim.new(0, 10)
		uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout1.Parent = interactions

		local uIPadding = Instance.new("UIPadding")
		uIPadding.Name = "UIPadding"
		uIPadding.PaddingTop = UDim.new(0, 20)
		uIPadding.Parent = interactions

		interactions.Parent = prompt

		local uIListLayout2 = Instance.new("UIListLayout")
		uIListLayout2.Name = "UIListLayout"
		uIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout2.Parent = prompt

		prompt.Parent = dialog

		dialog.Parent = dialogCanvas
		
		local canvasIn = Tween(dialogCanvas, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {
			GroupTransparency = 0,
		})
		local canvasOut = Tween(dialogCanvas, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {
			GroupTransparency = 1,
		})
		
		local function dialogIn()
			canvasIn:Play()
			canvasIn.Completed:Wait()
			dialog.Parent = base
		end
		
		local function dialogOut()
			dialog.Parent = dialogCanvas

			canvasOut:Play()
			canvasOut.Completed:Wait()
			dialogCanvas:Destroy()
		end
		
		for _, v in pairs(Settings.Buttons) do
			local button = Instance.new("TextButton")
			button.Name = "Button"
			button.FontFace = Font.new(
				assets.interFont,
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			)
			button.Text = v.Name
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
			button.TextSize = 15
			button.TextTransparency = 0.5
			button.TextTruncate = Enum.TextTruncate.AtEnd
			button.AutoButtonColor = false
			button.AutomaticSize = Enum.AutomaticSize.Y
			button.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
			button.BorderColor3 = Color3.fromRGB(0, 0, 0)
			button.BorderSizePixel = 0
			button.Size = UDim2.fromScale(1, 0)

			local uIPadding1 = Instance.new("UIPadding")
			uIPadding1.Name = "UIPadding"
			uIPadding1.PaddingBottom = UDim.new(0, 9)
			uIPadding1.PaddingLeft = UDim.new(0, 10)
			uIPadding1.PaddingRight = UDim.new(0, 10)
			uIPadding1.PaddingTop = UDim.new(0, 9)
			uIPadding1.Parent = button

			local baseUICorner1 = Instance.new("UICorner")
			baseUICorner1.Name = "BaseUICorner"
			baseUICorner1.CornerRadius = UDim.new(0, 10)
			baseUICorner1.Parent = button

			button.Parent = interactions
			
			local TweenSettings = {
				DefaultTransparency = 0,
				DefaultTransparency2 = 0.5,
				HoverTransparency = 0.3,
				HoverTransparency2 = 0.6,

				EasingStyle = Enum.EasingStyle.Sine
			}
			
			local function ChangeState(State)
				if State == "Idle" then
					Tween(button, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
						BackgroundTransparency = TweenSettings.DefaultTransparency,
						TextTransparency = TweenSettings.DefaultTransparency2
					}):Play()
				elseif State == "Hover" then
					Tween(button, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
						BackgroundTransparency = TweenSettings.HoverTransparency,
						TextTransparency = TweenSettings.HoverTransparency2
					}):Play()
				end
			end
			
			button.MouseButton1Click:Connect(function()
				if dialogCanvas.GroupTransparency ~= 0 then return end
				if v.Callback then
					v.Callback()
				end
				
				dialog.Parent = dialogCanvas
				
				dialogOut()
			end)
			
			button.MouseEnter:Connect(function()
				ChangeState("Hover")
			end)
			button.MouseLeave:Connect(function()
				ChangeState("Idle")
			end)
		end
		
		dialogIn()
		
		function DialogFunctions:UpdateTitle(New)
			paragraphHeader.Text = New
		end
		function DialogFunctions:UpdateDescription(New)
			paragraphBody.Text = New
		end
		
		function DialogFunctions:Cancel()
			dialogOut()
		end
		
		return DialogFunctions
	end

	function WindowFunctions:SetNotificationsState(State)
		notifications.Visible = State
	end

	function WindowFunctions:GetNotificationsState(State)
		return notifications.Visible
	end

	function WindowFunctions:SetState(State)
		windowState = State
		base.Visible = State
	end

	function WindowFunctions:GetState()
		return windowState
	end
	
	local onUnloadCallback

	function WindowFunctions:Unload()
		if onUnloadCallback then
			onUnloadCallback()  
		end
		-- Added to the vendored library: without this each reload leaves another
		-- UpdateOrientation connection running forever.
		if orientationConnection then
			pcall(function() orientationConnection:Disconnect() end)
			orientationConnection = nil
		end
		macLib:Destroy()
	end

	function WindowFunctions.onUnloaded(callback)
		onUnloadCallback = callback
	end

	local MenuKeybind = Settings.Keybind or Enum.KeyCode.RightControl

	local function ToggleMenu()
		local state = not WindowFunctions:GetState()
		WindowFunctions:SetState(state)
		WindowFunctions:Notify({
			Title = Settings.Title,
			Description = (state and "Maximized " or "Minimized ") .. "the menu. Use " .. tostring(MenuKeybind.Name) .. " to toggle it.",
			Lifetime = 5
		})
	end

	UserInputService.InputEnded:Connect(function(inp, gpe)
		if gpe then return end
		if inp.KeyCode == MenuKeybind then
			ToggleMenu()
		end
	end)

	minimize.MouseButton1Click:Connect(ToggleMenu)
	exit.MouseButton1Click:Connect(function()
		WindowFunctions:Unload()
	end)

	function WindowFunctions:SetKeybind(Keycode)
		MenuKeybind = Keycode
	end

	function WindowFunctions:SetAcrylicBlurState(State)
		acrylicBlur = State
		base.BackgroundTransparency = State and 0.05 or 0
	end

	function WindowFunctions:GetAcrylicBlurState()
		return acrylicBlur
	end

	local function _SetUserInfoState(State)
		if State then
			headshot.Image = (isReady and headshotImage) or "rbxassetid://0"
			username.Text = "@"..LocalPlayer.Name
			displayName.Text = LocalPlayer.DisplayName
		else
			headshot.Image = assets.userInfoBlurred
			local nameLength = #LocalPlayer.Name
			local displayNameLength = #LocalPlayer.DisplayName
			username.Text = "@"..string.rep(".", nameLength)
			displayName.Text = string.rep(".", displayNameLength)
		end
	end

	local showUserInfo
	if Settings.ShowUserInfo ~= nil then
		showUserInfo = Settings.ShowUserInfo
	else
		showUserInfo = true
	end

	_SetUserInfoState(showUserInfo)

	function WindowFunctions:SetUserInfoState(State)
		_SetUserInfoState(State)
	end
	function WindowFunctions:GetUserInfoState(State)
		return showUserInfo
	end
	
	function WindowFunctions:SetSize(Size)
		base.Size = Size
	end
	function WindowFunctions:GetSize(Size)
		return base.Size
	end
	
	function WindowFunctions:SetScale(Scale)
		baseUIScale.Scale = Scale
	end
	function WindowFunctions:GetScale()
		return baseUIScale.Scale
	end

	macLib.Enabled = false
	
	local assetList = {}
	for _, assetId in pairs(assets) do
		table.insert(assetList, assetId)
	end
	
	ContentProvider:PreloadAsync(assetList)
	macLib.Enabled = true
	windowState = true

	return WindowFunctions
end

function MacLib:Demo()
	local Window = MacLib:Window({
		Title = "MacLib Demo",
		Subtitle = "This is a subtitle.",
		Size = UDim2.fromOffset(868, 650),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.RightControl,
		AcrylicBlur = true,
	})

	local globalSettings = {
		UIBlurToggle = Window:GlobalSetting({
			Name = "UI Blur",
			Default = Window:GetAcrylicBlurState(),
			Callback = function(bool)
				Window:SetAcrylicBlurState(bool)
				Window:Notify({
					Title = "MacLib Demo",
					Description = (bool and "Enabled" or "Disabled") .. " UI Blur",
					Lifetime = 5
				})
			end,
		}),
		NotificationToggler = Window:GlobalSetting({
			Name = "Notifications",
			Default = Window:GetNotificationsState(),
			Callback = function(bool)
				Window:SetNotificationsState(bool)
				Window:Notify({
					Title = "MacLib Demo",
					Description = (bool and "Enabled" or "Disabled") .. " Notifications",
					Lifetime = 5
				})
			end,
		}),
		ShowUserInfo = Window:GlobalSetting({
			Name = "Show User Info",
			Default = Window:GetUserInfoState(),
			Callback = function(bool)
				Window:SetUserInfoState(bool)
				Window:Notify({
					Title = "MacLib Demo",
					Description = (bool and "Showing" or "Redacted") .. " User Info",
					Lifetime = 5
				})
			end,
		})
	}
	
	local tabGroups = {
		TabGroup1 = Window:TabGroup()
	}

	local tabs = {
		Main = tabGroups.TabGroup1:Tab({ Name = "Demo", Image = "rbxassetid://18821914323" })
	}
	
	local sections = {
		MainSection1 = tabs.Main:Section({ Side = "Left" })
	}

	sections.MainSection1:Header({
		Name = "Header #1"
	})

	sections.MainSection1:Button({
		Name = "Button",
		Callback = function()
			Window:Dialog({
				Title = "MacLib Demo",
				Description = "Lorem ipsum odor amet, consectetuer adipiscing elit. Eros vestibulum aliquet mattis, ex platea nunc.",
				Buttons = {
					{
						Name = "Confirm",
						Callback = function()
							print("Confirmed!")
						end,
					},
					{
						Name = "Cancel"
					}
				}
			})
		end,
	})

	sections.MainSection1:Input({
		Name = "Input",
		Placeholder = "Input",
		AcceptedCharacters = "All",
		Callback = function(input)
			Window:Notify({
				Title = "MacLib Demo",
				Description = "Successfully set input to " .. input
			})
		end,
		onChanged = function(input)
			print("Input is now ".. input)
		end,
	})

	sections.MainSection1:Slider({
		Name = "Slider",
		Default = 50,
		Minimum = 0,
		Maximum = 100,
		DisplayMethod = "Percent",
		Callback = function(Value)
			print("Changed to ".. Value)
		end,
	})

	sections.MainSection1:Toggle({
		Name = "Toggle",
		Default = false,
		Callback = function(value)
			Window:Notify({
				Title = "MacLib Demo",
				Description = (value and "Enabled " or "Disabled ") .. "Toggle"
			})
		end,
	})

	sections.MainSection1:Keybind({
		Name = "Keybind",
		Callback = function(binded)
			Window:Notify({
				Title = "Demo Window",
				Description = "Pressed keybind - "..tostring(binded.Name),
				Lifetime = 3
			})
		end,
		onBinded = function(bind)
			Window:Notify({
				Title = "Demo Window",
				Description = "Successfully Binded Keybind to - "..tostring(bind.Name),
				Lifetime = 3
			})
		end,
	})

	sections.MainSection1:Colorpicker({
		Name = "Colorpicker",
		Default = Color3.fromRGB(0, 255, 255),
		Callback = function(color)
			print("Color: ", color)
		end,
	})

	local alphaColorPicker = sections.MainSection1:Colorpicker({
		Name = "Transparency Colorpicker",
		Default = Color3.fromRGB(255,0,0),
		Alpha = 0,
		Callback = function(color, alpha)
			print("Color: ", color, " Alpha: ", alpha)
		end,
	})
	
	local rainbowActive
	local rainbowConnection
	local hue = 0

	sections.MainSection1:Toggle({
		Name = "Rainbow",
		Default = false,
		Callback = function(value)
			rainbowActive = value
			if rainbowActive then
				rainbowConnection = game:GetService("RunService").RenderStepped:Connect(function(deltaTime)
					hue = (hue + deltaTime * 0.1) % 1
					local newColor = Color3.fromHSV(hue, 1, 1)
					alphaColorPicker:SetColor(newColor)
				end)
			else
				if rainbowConnection then
					rainbowConnection:Disconnect()
					rainbowConnection = nil
				end
			end
		end,
	})
	
	local optionTable = {}
	
	for i = 1,10 do
		local formatted = "Option ".. tostring(i)
		table.insert(optionTable, formatted)
	end

	local Dropdown = sections.MainSection1:Dropdown({
		Name = "Dropdown",
		Multi = false,
		Required = true,
		Options = optionTable,
		Default = 1,
		Callback = function(Value)
			print("Dropdown changed: ".. Value)
		end,
	})

	local MultiDropdown = sections.MainSection1:Dropdown({
		Name = "Multi Dropdown",
		Search = true,
		Multi = true,
		Required = false,
		Options = optionTable,
		Default = {"Option 1", "Option 3"},
		Callback = function(Value)
			local Values = {}
			for Value, State in next, Value do
				table.insert(Values, Value)
			end
			print("Mutlidropdown changed:", table.concat(Values, ", "))
		end,
	})

	sections.MainSection1:Button({
		Name = "Update Selection",
		Callback = function()
			Dropdown:UpdateSelection(4)
			MultiDropdown:UpdateSelection({"Option 2", "Option 5"})
		end,
	})

	sections.MainSection1:Divider()

	sections.MainSection1:Header({
		Text = "Header #2"
	})

	sections.MainSection1:Paragraph({
		Header = "Paragraph",
		Body = "Paragraph body. Lorem ipsum odor amet, consectetuer adipiscing elit. Morbi tempus netus aliquet per velit est gravida."
	})

	sections.MainSection1:Label({
		Text = "Label. Lorem ipsum odor amet, consectetuer adipiscing elit."
	})

	sections.MainSection1:SubLabel({
		Text = "Sub-Label. Lorem ipsum odor amet, consectetuer adipiscing elit."
	})
	
	Window.onUnloaded(function()
		print("Unloaded!")
	end)

	tabs.Main:Select()
end

return MacLib
]=]

-- Loading is the risky step: a syntax change in the library, an executor without
-- loadstring, or CoreGui being locked all fail here. None of them should take
-- the ESP and the aim down with it, so this is wrapped and the ESP keeps running
-- with no menu if it fails.
local function load_maclib()
	local ok_ls, chunk = pcall(function()
		return (loadstring or load)(MACLIB_SRC, "=maclib")
	end)
	if not ok_ls or type(chunk) ~= "function" then
		return nil, "loadstring unavailable"
	end
	-- The library must see the SAME globals this script does. `loadstring`
	-- compiles against the executor's global table, which on some builds is a
	-- narrow sandbox without `game` or `Instance` -- the library then dies on its
	-- first line with "attempt to index global 'game'". Where the executor exposes
	-- setfenv (every one that ships loadstring does), point the chunk at our
	-- environment. It costs nothing when the globals already matched.
	pcall(function()
		if type(setfenv) == "function" then
			setfenv(chunk, getfenv and getfenv() or _G)
		end
	end)
	local ok, lib = pcall(chunk)
	if not ok then
		return nil, tostring(lib)
	end
	if type(lib) ~= "table" or type(lib.Window) ~= "function" then
		return nil, "MacLib did not return a library table"
	end
	return lib, nil
end

local MacLib, maclib_err = load_maclib()
if MacLib == nil then
	warn("[LF] menu unavailable: " .. tostring(maclib_err))
	print("[LF] stage 10: menu skipped (" .. tostring(maclib_err) .. ")")
end

-- Cycles read like the old menu: a fixed list, and CFG holds the value. Keeping
-- the same lists means the ESP keeps seeing the values it already handles.
local BOX_STYLES = { 1, 2 }
local BOX_STYLE_NAMES = { "full", "corner" }
local RANGES = { 400, 800, 1200, 2000 }
local FOVS = { 150, 250, 400 }
-- Drones fly far higher and further than a body, so their ESP gets its own list.
local DRONE_RANGES = { 500, 1000, 2000, 4000 }

-- 1-based index of a STRING option in a dropdown list. The themes are picked by
-- name, not by number, so option_index (which compares numbers) cannot serve them.
local function option_index_by_name(list, value)
	for i, k in ipairs(list) do
		if k == value then
			return i
		end
	end
	return 1
end

-- label to show for a cycle value, so the dropdown shows "corner" and not "2"
local function name_of(keys, names, value)
	for i, k in ipairs(keys) do
		if k == value then
			return names[i]
		end
	end
	return tostring(value)
end

-- 1-based index of `value` in a dropdown's option list, which is what MacLib's
-- `Default` expects. Falls back to 1 so a CFG value outside the list still opens
-- the menu instead of leaving the dropdown pointing at nothing.
local function option_index(list, value)
	for i, k in ipairs(list) do
		if k == value then
			return i
		end
	end
	return 1
end

local function value_of(keys, names, label, fallback)
	for i, n in ipairs(names) do
		if n == label then
			return keys[i]
		end
	end
	return fallback
end

local ui = nil

--[[ world ]]

-- Every toggle here is client-side. Lighting, Atmosphere and the camera are not
-- replicated, so none of this is visible to the server. What it does have to do
-- is put everything back the way it was: fog, atmosphere visibility and the
-- player's own camera settings belong to the game, and leaving them changed
-- after the user turns a toggle off would be a bug the user cannot undo.
local WORLD = {
	drone = nil,        -- the ColorCorrection instance named "Drone"
	drone_saved = nil,  -- its original Enabled
	fog_saved = nil,    -- original FogEnd
	atmos = nil,        -- { {inst = ..., visible = ...}, ... }
	third_saved = nil,  -- original CameraMode
	-- The game runs CameraType = Scriptable with no subject; forcing ThirdPerson
	-- needs the camera handed back to the player, so the original CameraType is
	-- captured here and put back on toggle off.
	cam_saved = nil,
	-- Player.CameraMaxZoomDistance as the game had it, so third person off puts
	-- the zoom range back instead of leaving it wide.
	zoom_saved = nil,
	-- Lighting.Brightness as the game had it. Removing the fog and the atmosphere
	-- leaves the scene lit only by whatever the map's own lights do, which reads
	-- as "escuro demais" once the haze that was scattering light is gone. The
	-- brightness toggle is the answer to that, and it has to restore the exact
	-- original number, not a guessed one.
	brightness_saved = nil,
}

local function get_lighting()
	local ok, svc = pcall(function()
		return game:GetService("Lighting")
	end)
	if ok and svc then
		return svc
	end
	return nil
end

-- Capture the originals once, before the first toggle is applied.
local function world_capture()
	if WORLD.drone_saved ~= nil then
		return
	end
	local lighting = get_lighting()
	if lighting == nil then
		return
	end
	local ok = pcall(function()
		WORLD.fog_saved = lighting.FogEnd
		WORLD.brightness_saved = lighting.Brightness
		for _, v in ipairs(lighting:GetChildren()) do
			-- The drone's effect is a ColorCorrection literally named "Drone".
			-- Matched by name, not by position: the recon showed eight other
			-- ColorCorrections in Lighting and the order is not guaranteed.
			if v:IsA("ColorCorrectionEffect") and v.Name == "Drone" then
				WORLD.drone = v
				WORLD.drone_saved = v.Enabled
			end
			if v:IsA("Atmosphere") then
				WORLD.atmos = WORLD.atmos or {}
				table.insert(WORLD.atmos, { inst = v, visible = v.Parent ~= nil })
			end
		end
	end)
	WORLD.drone_saved = WORLD.drone_saved or false
end

local function world_restore_third()
	local players = nil
	local ok = pcall(function()
		players = game:GetService("Players")
	end)
	if not ok or players == nil then
		return
	end
	pcall(function()
		local lp = players.LocalPlayer
		if lp == nil then
			return
		end
		lp.CameraMode = WORLD.third_saved or E.classic or lp.CameraMode
	end)
end

-- Applied on every toggle change. Reads CFG, so it is idempotent.
local function apply_world()
	world_capture()
	local lighting = get_lighting()

	if lighting ~= nil then
		pcall(function()
			if CFG.world_fog then
				lighting.FogEnd = 9999999999
			elseif WORLD.fog_saved ~= nil then
				lighting.FogEnd = WORLD.fog_saved
			end
		end)

		-- Brightness. Killing the fog and the atmosphere removes the haze that was
		-- scattering light, and the map goes dark. Restoring means putting the
		-- captured number back rather than subtracting the boost, so a slider moved
		-- around a dozen times still returns to exactly what the game had.
		pcall(function()
			if CFG.world_bright then
				lighting.Brightness = math.clamp(CFG.world_bright_value or 3, 0, 10)
			elseif WORLD.brightness_saved ~= nil then
				lighting.Brightness = WORLD.brightness_saved
			end
		end)

		if WORLD.drone ~= nil then
			pcall(function()
				-- Turned off means the effect is disabled. Turning the toggle back
				-- on restores whatever the game had, which is not necessarily on:
				-- the game controls this one from the server.
				WORLD.drone.Enabled = (not CFG.world_drone) and (WORLD.drone_saved or false)
			end)
		end

		if WORLD.atmos ~= nil then
			for _, a in ipairs(WORLD.atmos) do
				pcall(function()
					-- Parent is the only way to actually remove an Atmosphere from
					-- the render; Visible does not exist on it.
					if CFG.world_atmosphere then
						a.inst.Parent = nil
					elseif a.inst.Parent == nil and a.visible then
						a.inst.Parent = lighting
					end
				end)
			end
		end
	end

	-- Third person, measured against the real enum rather than assumed.
	--
	-- The first version wrote `lp.CameraMode = Enum.CameraMode.ThirdPerson`, which
	-- CANNOT work here: this build's CameraMode enum has exactly two members,
	-- Classic (0) and LockFirstPerson (1). There is no ThirdPerson, try_enum
	-- returned nil, and `lp.CameraMode = nil` fails without an error anyone sees -
	-- which is why the toggle moved nothing no matter how it was clicked.
	--
	-- Classic IS third person; LockFirstPerson is the one that pins the camera to
	-- the head. So "third person" here means: leave CameraMode on Classic, give the
	-- camera a subject to orbit, and open up the zoom range so the view can pull
	-- back. The first-person mode is what gets forced off.
	pcall(function()
		local players = game:GetService("Players")
		local lp = players.LocalPlayer
		if lp == nil then
			return
		end
		local camera = workspace.CurrentCamera
		local third = CFG.world_third and true or false

		if third then
			-- capture the originals exactly once, so "off" restores the game's own
			-- values instead of whatever this script happened to leave behind
			if WORLD.zoom_saved == nil then
				local ok, v = pcall(function()
					return lp.CameraMaxZoomDistance
				end)
				WORLD.zoom_saved = ok and v or nil
			end
			pcall(function()
				lp.CameraMaxZoomDistance = 32
			end)
		else
			if WORLD.zoom_saved ~= nil and WORLD.zoom_saved ~= false then
				pcall(function()
					lp.CameraMaxZoomDistance = WORLD.zoom_saved
				end)
				WORLD.zoom_saved = nil
			end
		end

		-- CameraMode: only ever set to a member that exists in this build.
		local want_mode = third and E.classic or nil
		if want_mode ~= nil then
			pcall(function()
				lp.CameraMode = want_mode
			end)
		end

		-- The subject and the type only when there is a character to orbit. In the
		-- lobby there is none, so the zoom range above is the whole effect - which
		-- is honest: there is nothing to put in third person yet.
		local char = lp.Character
		if char == nil or char:FindFirstChildOfClass("Humanoid") == nil then
			char = rig_of_char(lp) or char
		end
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum == nil or camera == nil then
			return
		end
		if third then
			pcall(function()
				if WORLD.cam_saved == nil then
					WORLD.cam_saved = camera.CameraType
				end
			end)
			pcall(function()
				camera.CameraSubject = hum
			end)
			pcall(function()
				camera.CameraType = E.custom
			end)
		else
			if WORLD.cam_saved ~= nil then
				pcall(function()
					camera.CameraType = WORLD.cam_saved
				end)
				WORLD.cam_saved = nil
			end
		end
	end)
end

-- The library paints the slider's filled track one fixed colour and gives no
-- hook to change it, so the low/mid/high colour the user asked for is applied
-- to the value box of the FOV slider, found once the menu exists.
local fov_value_box = nil

local function fov_band_colour(n)
	if n < 150 then
		return Color3.fromRGB(230, 90, 90) -- low, red: too tight to catch anyone
	elseif n < 350 then
		return Color3.fromRGB(235, 190, 70) -- mid, amber
	end
	return Color3.fromRGB(120, 210, 130) -- high, green: wide
end

local function aim_tint_fov(n)
	local box = fov_value_box
	if box == nil then
		return
	end
	pcall(function()
		box.TextColor3 = fov_band_colour(n)
	end)
end

--[[ aim target picker ]]

-- A ViewportFrame with a blocky R6 dummy beside the menu, shown only while the
-- AIM tab is up. Everything is built from Parts, so it needs no network and no
-- asset: the proportions are the classic R6 ones (2x2 head, 2x2x1 torso, 1x2x1
-- limbs) and the colours are the stock greys.
--
-- The three zones are invisible hit boxes over head, torso and legs. Clicking
-- one writes CFG.aim_part, which the aim reads to decide which part to pull to.
-- The AIM tab's Section frames, kept so the picker can tell whether that tab
-- is the one on screen. Sections are unnamed, so identity is the only handle.
local AIM_SECTIONS = {}

-- Body-part options for the AIM tab, in Portuguese. The value stored in
-- CFG.aim_part stays the internal English name, because the aim loop and the 3D
-- dummy's hit zones both match on it; these two tables translate at the edges so
-- nothing downstream has to know about the labels.
-- Order matters: it is the order the dropdown lists and the order its 1-based
-- index maps through.
local AIM_PART_LABELS = { "Cabeca", "Tronco", "Pernas" }

local AIM_PART_BY_LABEL = {
	["Cabeca"] = "Head",
	["Tronco"] = "Torso",
	["Pernas"] = "Legs",
}

local AIM_PART_LABEL = {
	Head = "Cabeca",
	Torso = "Tronco",
	Legs = "Pernas",
}

local PICKER = {
	gui = nil,
	frame = nil,
	zones = {},
	built = false,
}

-- Which part the dummy is showing as selected. Drawn as a highlight box.
local PICKER_HILIGHT = nil

local function picker_highlight(part_name)
	if PICKER_HILIGHT == nil then
		return
	end
	local c = nil
	for _, z in ipairs(PICKER.zones) do
		if z.name == part_name then
			c = z
		end
	end
	pcall(function()
		if c == nil then
			PICKER_HILIGHT.Visible = false
			return
		end
		PICKER_HILIGHT.Position = c.frame.Position
		PICKER_HILIGHT.Size = c.frame.Size
		PICKER_HILIGHT.Visible = true
	end)
end

local function picker_select(part_name)
	CFG.aim_part = part_name
	picker_highlight(part_name)
end

local function picker_make_part(viewport, world, name, size, pos, colour)
	local ok = pcall(function()
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = colour
		-- Inside its own pcall: an executor without an Enum table must lose the
		-- material, not the part and not the picker.
		pcall(function()
			p.Material = Enum.Material.SmoothPlastic
		end)
		p.Parent = world
	end)
	return ok
end

local function build_picker()
	if PICKER.built then
		return PICKER.gui
	end

	local built, why = pcall(function()
		local playerGui = nil
		pcall(function()
			playerGui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		end)
		local parent = nil
		-- Same order as the menu itself: the executor's hidden container first,
		-- because that is where MacLib ends up and the dummy has to sit beside
		-- it at the same depth. CoreGui next, PlayerGui last.
		pcall(function()
			parent = gethui and gethui()
		end)
		if parent == nil then
			pcall(function()
				parent = game:GetService("CoreGui")
			end)
		end
		if parent == nil then
			parent = playerGui
		end
		if parent == nil then
			-- Raised, not returned: pcall swallows a bare return as success, and
			-- then the caller thinks the picker exists while the Gui was never
			-- even created - the tab just looks empty and nothing says why.
			error("no CoreGui and no PlayerGui to parent the picker into")
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "LF_Picker"
		pcall(function()
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
		end)
		pcall(function()
			gui.DisplayOrder = 99
		end)

		-- Beside the menu, on the right, in its own box. The menu is 868 wide
		-- centred on screen, so its right edge is at 50% + 434. This frame is
		-- anchored to the same centre line with a fixed gap, so it follows the
		-- menu if the window is resized.
		local frame = Instance.new("Frame")
		frame.Name = "Picker"
		frame.AnchorPoint = Vector2.new(0, 0.5)
		frame.Position = UDim2.new(0.5, 448, 0.5, 0)
		frame.Size = UDim2.fromOffset(210, 380)
		frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		frame.BackgroundTransparency = 0.25
		frame.BorderSizePixel = 0
		frame.Visible = false

		pcall(function()
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = frame
		end)

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Text = "ALVO"
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 13
		pcall(function()
			title.Font = Enum.Font.GothamBold
		end)
		title.Position = UDim2.fromOffset(0, 10)
		title.Size = UDim2.new(1, 0, 0, 16)
		title.Parent = frame

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "View"
		viewport.BackgroundTransparency = 1
		viewport.Position = UDim2.fromOffset(10, 32)
		viewport.Size = UDim2.new(1, -20, 1, -100)
		viewport.Ambient = Color3.fromRGB(180, 180, 180)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.Parent = frame

		local world = Instance.new("WorldModel")
		world.Parent = viewport

		-- A camera looking at the dummy from the front, slightly above centre.
		local pcam = Instance.new("Camera")
		pcam.FieldOfView = 40
		-- The picker's own viewport camera, not the game camera. Wrapped because
		-- CFrame/Vector3 construction is the one thing that depends on the
		-- executor's vector library; a failure here costs the dummy's angle only.
		pcall(function()
			pcam.CFrame = CFrame.new(Vector3.new(0, 0, 12), Vector3.new(0, 0, 0))
		end)
		viewport.CurrentCamera = pcam

		local grey = Color3.fromRGB(163, 162, 165)
		local light = Color3.fromRGB(204, 142, 105)

		-- R6 proportions. The torso centre is the origin, so the whole body sits
		-- from about y = -3 (feet) to y = +3 (top of head).
		picker_make_part(viewport, world, "Head", Vector3.new(2, 1, 1), Vector3.new(0, 2, 0), light)
		picker_make_part(viewport, world, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0.5, 0), grey)
		picker_make_part(viewport, world, "LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0.5, 0), light)
		picker_make_part(viewport, world, "RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0.5, 0), light)
		picker_make_part(viewport, world, "LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -1.5, 0), grey)
		picker_make_part(viewport, world, "RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -1.5, 0), grey)

		-- A key light, so the dummy is not flat-lit.
		pcall(function()
			local lightInst = Instance.new("PointLight")
			lightInst.Brightness = 1.4
			lightInst.Range = 30
			lightInst.Position = Vector3.new(4, 6, 8)
			lightInst.Parent = world
		end)

		local labels = {
			{ name = "Head", text = "Cabeca", y = 32, h = 60 },
			{ name = "Torso", text = "Peito", y = 92, h = 90 },
			{ name = "Legs", text = "Pernas", y = 182, h = 90 },
		}

		for _, z in ipairs(labels) do
			local btn = Instance.new("TextButton")
			btn.Name = z.name
			btn.Text = z.text
			btn.TextColor3 = Color3.fromRGB(220, 220, 220)
			btn.TextSize = 12
			pcall(function()
				btn.Font = Enum.Font.GothamMedium
			end)
			btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			btn.BackgroundTransparency = 0.94
			btn.BorderSizePixel = 0
			-- Placed over the viewport, in viewport-local coordinates scaled to
			-- the frame width, so it lines up with the drawn body.
			btn.Position = UDim2.fromOffset(10, 32 + z.y * 0.62)
			btn.Size = UDim2.new(1, -20, 0, z.h * 0.62)
			btn.Parent = frame

			pcall(function()
				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(0, 6)
				bc.Parent = btn
			end)

			btn.MouseButton1Click:Connect(function()
				picker_select(z.name)
			end)
			table.insert(PICKER.zones, { name = z.name, frame = btn })
		end

		frame.Parent = gui
		gui.Parent = parent
		PICKER.gui = gui
		PICKER.frame = frame
		PICKER.built = true
	end)

	if not built then
		-- Report once. A picker that silently does not appear is the worst case:
		-- the tab looks empty and nothing says why.
		if not PICKER.reported then
			PICKER.reported = true
			warn("[LF] target picker failed: " .. tostring(why))
		end
		return nil
	end

	picker_highlight(CFG.aim_part or "Head")
	return PICKER.gui
end

--[[ theming ]]

-- Cached menu root and the theme bookkeeping. Declared before anything that
-- reads it so the first frame never indexes nil.
local MENU = {
	root = nil,
	applied = false,
	-- The Window handle returned by MacLib:Window. apply_theme needs it for
	-- Window:SetScale - the library's BaseUIScale is the only UIScale that has any
	-- effect on the window, so scale has to go through this.
	window = nil,
}

-- True when the AIM tab is the one on screen. Read from the tree, not from a
-- flag: the library moves the selected tab's sections into "Content", so the
-- presence of the AIM-only header under Content IS the answer.
local function aim_tab_showing()
	if PICKER.content == nil or PICKER.content.Parent == nil then
		return false
	end
	local ok, found = pcall(function()
		for _, d in ipairs(PICKER.content:GetDescendants()) do
			-- Headers render their text into a child but the STRING is what is
			-- unique: the node itself is always named "Header", so matching on the
			-- name would never find anything.
			if d.Text == "Assistencia de mira" then
				return true
			end
		end
		return false
	end)
	return ok and found
end

-- The menu is built by the vendored library, which paints its own colours inline
-- and exposes no theme hook. Rather than fork every colour into the library, the
-- finished tree is recoloured here: the widgets that matter are found by their
-- names and their current colour, and only those are touched.
--
-- Every theme keeps the body dark and changes the accent. "Branco" is the one
-- inversion (light body), and it recolours text to near-black so it stays legible.
local THEMES = {
	["Preto com branco"] = { body = { 15, 15, 15 }, accent = { 255, 255, 255 }, light = false },
	["Vermelho"] = { body = { 24, 12, 12 }, accent = { 220, 55, 55 }, light = false },
	["Verde"] = { body = { 10, 22, 12 }, accent = { 70, 200, 110 }, light = false },
	["Azul"] = { body = { 10, 16, 28 }, accent = { 70, 140, 245 }, light = false },
	["Branco"] = { body = { 235, 235, 238 }, accent = { 30, 30, 34 }, light = true },
	["Amarelo"] = { body = { 24, 21, 8 }, accent = { 240, 205, 60 }, light = false },
}

local THEME_NAMES = {
	"Preto com branco", "Vermelho", "Verde", "Azul", "Branco", "Amarelo",
}

local function theme_of(name)
	return THEMES[name] or THEMES["Preto com branco"]
end

local function rgb3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Rainbow accent, used only when ui_rgb is on. It cycles the accent, which is
-- what paints borders and toggles; the body is left alone.
local function accent_now()
	if CFG.ui_rgb then
		return Color3.fromHSV((os.clock() * CFG.ui_rgb_speed) % 1, 0.85, 1)
	end
	return rgb3(theme_of(CFG.ui_theme).accent)
end

-- The menu's root. Located the same way everything else locates it, and cached
-- because the apply pass runs on every theme change and every frame while RGB is on.
local function menu_root()
	if MENU.root ~= nil and MENU.root.Parent ~= nil then
		return MENU.root
	end
	local found = nil
	local function scan(container)
		if found ~= nil or container == nil then
			return
		end
		local gui = container:FindFirstChild("MacLib")
		if gui ~= nil then
			found = gui:FindFirstChild("Base") or gui
		end
	end
	pcall(function() scan(gethui and gethui()) end)
	if found == nil then
		pcall(function() scan(game:GetService("CoreGui")) end)
	end
	if found == nil then
		pcall(function()
			scan(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui"))
		end)
	end
	MENU.root = found
	return found
end

-- Apply the current theme, scale and opacity to the live menu. Safe to call at
-- any time: missing nodes are skipped rather than fatal, so a library update that
-- renames something costs that one element's colour, not the menu.
local function apply_theme()
	local root = menu_root()
	if root == nil then
		return
	end
	local theme = theme_of(CFG.ui_theme)
	local accent = accent_now()
	local body = rgb3(theme.body)
	local text_col = theme.light and Color3.fromRGB(25, 25, 28) or Color3.fromRGB(255, 255, 255)

	-- Opacity: 100 leaves it solid, 10 is the floor. The library's own base sits at
	-- 0.25 transparency by default, so this is expressed as "how solid", applied on
	-- top of nothing else - the number the user sets is the number they get.
	local alpha = math.clamp((CFG.ui_opacity or 100) / 100, 0.10, 1)
	local base_transparency = 1 - alpha

	-- The Base frame, resolved once for the whole function. menu_root() already
	-- returns Base when it can; only a ScreenGui answer needs the extra lookup.
	local base = root
	if base.Name ~= "Base" then
		base = root:FindFirstChild("Base") or base
	end

	pcall(function()
		if base ~= nil then
			base.BackgroundColor3 = body
			base.BackgroundTransparency = base_transparency
			-- Scale.
			--
			-- The first attempt added a second UIScale named LF_Scale next to the
			-- library's own BaseUIScale. Two sibling UIScales do not multiply - the
			-- last one wins - so the new one was inert and the slider did nothing.
			-- The library already exposes Window:SetScale, which drives BaseUIScale;
			-- that is the handle to use. Fall back to the instance directly for the
			-- case where the Window handle did not survive.
			local wanted = math.clamp(CFG.ui_scale or 1, 0.6, 1.4)
			local via_window = false
			if MENU.window ~= nil then
				local okw = pcall(function()
					MENU.window:SetScale(wanted)
				end)
				via_window = okw
			end
			if not via_window then
				local base_scale = base:FindFirstChild("BaseUIScale")
				if base_scale ~= nil then
					base_scale.Scale = wanted
				end
			end

			-- The library paints the window with a nameless Frame that covers ~97%
			-- of Base at near-full opacity and opaque black. Colouring Base alone
			-- therefore changed nothing visible: the body stayed black while the
			-- accent pass (which runs below) did change, which is exactly the
			-- "bordas mudam, fundo nao" symptom. Any child that covers the window
			-- and is opaque is treated as the body and takes the theme colour.
			for _, child in ipairs(base:GetChildren()) do
				if child:IsA("Frame") and child.BackgroundTransparency < 0.5 then
					local sx = child.Size.X.Scale
					local sy = child.Size.Y.Scale
					if sx > 0.9 and sy > 0.9 then
						child.BackgroundColor3 = body
						child.BackgroundTransparency = base_transparency
					end
				end
			end
		end
	end)

	-- Accent pass: strokes, toggles, sliders, the selected tab underline and the
	-- window controls all carry the accent. Matched by name, which is stable
	-- across the library version this file vendors.
	-- Accent pass.
	--
	-- Two different things share the word "accent" and the first version of this
	-- code treated them as one, which is why RGB painted the buttons instead of the
	-- border:
	--
	--   * the widget accent (toggle heads, slider fills, stroked rows) always takes
	--     the THEME colour. It must not cycle, otherwise the menu reads as broken
	--     rather than themed.
	--   * the border - the outline around the window itself - is what RGB drives.
	--     Only the outer strokes and the aura bars cycle.
	local widget_accent = rgb3(theme.accent)
	local border_accent = accent
	pcall(function()
		for _, d in ipairs(root:GetDescendants()) do
			local n = d.Name
			if n == "UIStroke" or n:find("UIStroke") then
				if d:IsA("UIStroke") then
					-- The window's own outline is the one that cycles; a stroke on an
					-- inner row keeps the theme colour so text stays readable.
					local outer = false
					local p = d.Parent
					while p ~= nil and p ~= root do
						if p.Name == "Base" then
							outer = true
							break
						end
						p = p.Parent
					end
					d.Color = outer and border_accent or widget_accent
				end
			elseif n == "TogglerHead" then
				if d:IsA("ImageLabel") or d:IsA("Frame") then
					d.ImageColor3 = widget_accent
				end
			elseif n == "Toggle" and d:IsA("ImageButton") then
				-- The track stays dark; only the lit state carries the accent and the
				-- library tweens that itself, so it is left alone here.
			elseif n == "SliderFill" or n == "Fill" then
				if d:IsA("Frame") then
					d.BackgroundColor3 = widget_accent
				end
			elseif n == "TabSwitcherUIStroke" then
				if d:IsA("UIStroke") then
					d.Color = widget_accent
				end
			elseif n == "Sidebar" or n == "TabSwitcher" or n == "ElementsScrolling"
				or n == "Content" or n == "Topbar" or n == "Elements" or n == "Information"
				or n == "WindowControls" or n == "SidebarGroup" then
				-- These are the surfaces the user actually looks at. Content, Topbar
				-- and Elements were missing from this list, which is why the theme
				-- changed the accent but left the window black: the three biggest
				-- painted areas were never recoloured.
				if d:IsA("Frame") then
					d.BackgroundColor3 = theme.light and Color3.fromRGB(215, 215, 220) or body
				end
			elseif n == "HeaderText" or n == "LabelText" or n == "SubLabelText"
				or n == "ParagraphHeader" or n == "ParagraphBody" or n == "TabSwitcherName"
				or n == "ToggleName" or n == "SliderName" or n == "DropdownName"
				or n == "ButtonName" or n == "InputName" or n == "KeybindName"
				or n == "SectionName" or n == "ColorpickerName" then
				if d:IsA("TextLabel") then
					d.TextColor3 = text_col
				end
			end
		end
	end)

	-- Window frame ring.
	--
	-- This is what "RGB em volta da UI" means: one frame wrapped around the whole
	-- window, whose stroke cycles. The earlier version recoloured every UIStroke and
	-- slider fill in the tree, which painted the buttons instead of the border - the
	-- exact thing that read as wrong.
	--
	-- Built once and kept parented to Base, sized to Base, sitting behind the
	-- content (ZIndex 0) so it only shows as a ring. The two gradient bars that were
	-- referenced here before were never actually created, which is why the aura
	-- never appeared; the ring replaces them.
	pcall(function()
		local ring = base:FindFirstChild("LF_Ring")
		if ring == nil then
			ring = Instance.new("Frame")
			ring.Name = "LF_Ring"
			ring.BackgroundTransparency = 1
			ring.BorderSizePixel = 0
			ring.ZIndex = 0
			ring.Size = UDim2.fromScale(1, 1)
			ring.Position = UDim2.fromScale(0, 0)
			ring.Parent = base
			local stroke = Instance.new("UIStroke")
			stroke.Name = "LF_RingStroke"
			stroke.Thickness = 2
			-- Resolved through try_enum like every other Enum here: a raw Enum
			-- access throws on an executor that has no Enum table, and this runs on
			-- the theme pass, so it would take the whole menu styling down.
			pcall(function()
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end)
			stroke.Parent = ring
		end
		local stroke = ring:FindFirstChild("LF_RingStroke")
		if stroke ~= nil then
			stroke.Color = border_accent
			stroke.Transparency = 0
		end
		-- The ring has to follow Base if the window is scaled or dragged.
		local sc = ring:FindFirstChild("LF_RingScale")
		if sc == nil then
			sc = Instance.new("UIScale")
			sc.Name = "LF_RingScale"
			sc.Parent = ring
		end
		sc.Scale = 1
	end)
end

-- Called from the tab switcher below: the panel exists only on the AIM tab.
local function picker_show(show)
	if not PICKER.built then
		return
	end
	pcall(function()
		PICKER.frame.Visible = show and true or false
	end)
end

local function build_ui()
	if MacLib == nil then
		return nil
	end

	-- Keybind is RightShift. Resolved through try_enum like every other Enum here:
	-- a direct Enum access would run the library's guarded window setup on an
	-- executor that has no Enum table.
	local window_settings = {
		Title = "LOST FRONT",
		Subtitle = "ESP + aim",
		DragStyle = 1,
		DisabledWindowControls = {},
		-- The window is toggled by RightShift only, so the three dots are dead
		-- weight. HideWindowControls removes them; DisabledWindowControls alone
		-- only faded them to 7px ghosts.
		HideWindowControls = true,
		-- Semi-transparent body so the game shows through behind the menu.
		BackgroundTransparency = 0.25,
		ShowUserInfo = true,
		Keybind = E.rightshift,
		-- Off deliberately. The acrylic blur builds a DepthOfFieldEffect and then
		-- draws the window frame as geometry every frame: CFrame math, a
		-- ViewportPointToRay loop, per-corner triangles. It is decoration, it is
		-- the single heaviest thing in the library, and it is also the only part
		-- that reaches into CFrame/Vector3 arithmetic. Losing it costs nothing
		-- that was asked for; losing the whole window because it threw would.
		AcrylicBlur = false,
	}
	pcall(function()
		window_settings.Size = UDim2.fromOffset(868, 650)
	end)

	-- MacLib parents its own ScreenGui to CoreGui, with no gethui fallback and no
	-- protection around the assignment:
	--
	--   macLib.Parent = (isStudio and LocalPlayer.PlayerGui) or game:GetService("CoreGui")
	--
	-- Where the place refuses that write, Window() throws on its first line and
	-- nothing gets built, so retrying afterwards cannot help - the parent is
	-- decided inside the library.
	--
	-- Redirecting `game` for the duration of the call was tried and dropped: the
	-- library captures `game` from its own environment, and there is no portable
	-- way to swap that from here. Editing the vendored library is the only real
	-- fix, and it is not mine to make unasked. What is left is an accurate
	-- message instead of a raw ProtectedString error, plus a hint at the cause.
	local ok_window, Window = pcall(function()
		return MacLib:Window(window_settings)
	end)
	if not ok_window or Window == nil then
		local msg = tostring(Window)
		if msg:find("InsufficientPermission") or msg:find("CoreGui") then
			warn("[LF] menu unavailable: CoreGui refused the UI (this executor "
				.. "cannot write to CoreGui). ESP and aim are unaffected.")
		else
			warn("[LF] menu window failed: " .. msg)
		end
		return nil
	end

	local W = {}
	-- Kept for apply_theme: Window:SetScale is the only handle that moves the
	-- library's BaseUIScale, and that is the UIScale that actually scales the menu.
	MENU.window = Window

	-- The window's own keybind must be the same key this file already toggles on,
	-- otherwise Insert does nothing visible and the user sees "the menu is gone".
	pcall(function()
		Window:SetState(true)
	end)

	-- The two-tone edge glow used to be built here: two thin Frames pinned to the
	-- left and right of the window, each a UIGradient from blue to violet.
	--
	-- apply_theme builds LF_Ring now - one frame wrapped around the whole window,
	-- whose stroke takes the RGB colour - and that is what "RGB em volta da UI"
	-- means. Keeping both painted the border twice: the aura bars sat on top of
	-- the ring with a FIXED blue-violet, so switching RGB on appeared to do
	-- nothing on the sides. Removed rather than disabled, because two decorations
	-- for one edge is the kind of thing that comes back as a bug report later.

	local ok_body, err = pcall(function()
		local Group = Window:TabGroup()

		-- ============================================================= ESP
		local EspTab = Group:Tab({ Name = "ESP" })
		local esp_main = EspTab:Section({ Side = "Left" })
		local esp_more = EspTab:Section({ Side = "Right" })
		-- Colours and glow get their own sections: the ESP tab already fills both
		-- columns, and stacking colourpickers into "Filtros" reads as if they
		-- filtered something.
		local esp_colors = EspTab:Section({ Side = "Left" })
		local espl_glow = EspTab:Section({ Side = "Right" })

		esp_main:Header({ Text = "ESP" })

		-- Every callback writes CFG and nothing else. The frame loop reads CFG,
		-- so the change lands on the next frame with no restart anywhere.
		esp_main:Toggle({
			Name = "Enabled",
			Default = CFG.esp_on,
			Callback = function(v)
				CFG.esp_on = v and true or false
			end,
		})

		esp_main:Toggle({
			Name = "Boxes",
			Default = CFG.esp_box,
			Callback = function(v)
				CFG.esp_box = v and true or false
			end,
		})

		esp_main:Dropdown({
			Name = "Box style",
			Options = { "full", "corner" },
			-- Must match CFG.esp_box_style, which ships as 2 (corner braces). The
			-- dropdown is 1-based, so 2 means "corner". It was 1 here for a while:
			-- the menu read "full" while the ESP drew corner braces, and the first
			-- click "changed" it to the style already on screen.
			Default = CFG.esp_box_style,
			Callback = function(v)
				CFG.esp_box_style = value_of(BOX_STYLES, BOX_STYLE_NAMES, v, CFG.esp_box_style)
			end,
		})

		esp_main:Toggle({
			Name = "Skeleton",
			Default = CFG.esp_skel,
			Callback = function(v)
				CFG.esp_skel = v and true or false
			end,
		})

		esp_main:Toggle({
			Name = "Names",
			Default = CFG.esp_name,
			Callback = function(v)
				CFG.esp_name = v and true or false
			end,
		})

		esp_main:Toggle({
			Name = "Health",
			Default = CFG.esp_hp,
			Callback = function(v)
				CFG.esp_hp = v and true or false
			end,
		})

		esp_more:Header({ Text = "Filtros" })

		esp_more:Toggle({
			Name = "Distance",
			Default = CFG.esp_dist,
			Callback = function(v)
				CFG.esp_dist = v and true or false
			end,
		})

		esp_more:Toggle({
			Name = "Team colors",
			Default = CFG.esp_team,
			Callback = function(v)
				CFG.esp_team = v and true or false
			end,
		})

		esp_more:Toggle({
			Name = "Hide team",
			Default = CFG.esp_hide_team,
			Callback = function(v)
				CFG.esp_hide_team = v and true or false
			end,
		})

		esp_more:Toggle({
			Name = "Only visible",
			Default = CFG.esp_visible,
			Callback = function(v)
				CFG.esp_visible = v and true or false
			end,
		})

		esp_more:Dropdown({
			Name = "Range",
			Options = { "400", "800", "1200", "2000" },
			-- Same rule as the others: derived from CFG, never hardcoded. This said
			-- 3, which is 1200 purely because the CFG default happens to be 1200.
			Default = option_index(RANGES, CFG.esp_range),
			-- tonumber alone is not enough: the point of a dropdown is that the
			-- value is one of the four offered. Anything else keeps the current
			-- range rather than setting one nothing can satisfy - a zero or
			-- negative range silently blanks the entire ESP.
			Callback = function(v)
				local n = tonumber(v)
				if n == nil then
					return
				end
				for _, allowed in ipairs(RANGES) do
					if n == allowed then
						CFG.esp_range = n
						return
					end
				end
			end,
		})

		-- Colours. MacLib's Colorpicker writes R, G and B as 0-1 floats and the
		-- callback receives a Color3, so CFG keeps plain 0-255 bytes and converts.
		esp_colors:Header({ Text = "Cores" })

		esp_colors:Colorpicker({
			Name = "Inimigo",
			Default = rgb3(CFG.esp_color_enemy),
			Callback = function(_, c)
				if typeof(c) == "Color3" then
					CFG.esp_color_enemy = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
				end
			end,
		})

		esp_colors:Colorpicker({
			Name = "Time",
			Default = rgb3(CFG.esp_color_team),
			Callback = function(_, c)
				if typeof(c) == "Color3" then
					CFG.esp_color_team = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
				end
			end,
		})

		esp_colors:Toggle({
			Name = "RGB",
			Default = CFG.esp_rgb,
			Callback = function(v)
				CFG.esp_rgb = v and true or false
			end,
		})

		esp_colors:Slider({
			Name = "Velocidade RGB",
			Default = math.floor(CFG.esp_rgb_speed * 100 + 0.5),
			Minimum = 5,
			Maximum = 200,
			DisplayMethod = "Percent",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil or n ~= n then
					return
				end
				CFG.esp_rgb_speed = math.clamp(n / 100, 0.05, 2)
			end,
		})

		espl_glow:Header({ Text = "Glowing" })

		espl_glow:Toggle({
			Name = "Enabled",
			Default = CFG.esp_glow,
			Callback = function(v)
				CFG.esp_glow = v and true or false
			end,
		})

		espl_glow:Colorpicker({
			Name = "Cor do glow",
			Default = rgb3(CFG.esp_glow_color),
			Callback = function(_, c)
				if typeof(c) == "Color3" then
					CFG.esp_glow_color = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
				end
			end,
		})

		espl_glow:Slider({
			Name = "Intensidade",
			Default = math.floor((1 - CFG.esp_glow_transparency) * 100 + 0.5),
			Minimum = 5,
			Maximum = 90,
			DisplayMethod = "Percent",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil or n ~= n then
					return
				end
				-- Stored as transparency, which is how Highlight wants it. The
				-- slider speaks intensity because "more" should read as more.
				CFG.esp_glow_transparency = math.clamp(1 - (n / 100), 0.1, 0.95)
			end,
		})

		-- ============================================================= AIM
		local AimTab = Group:Tab({ Name = "AIM" })
		local aim_main = AimTab:Section({ Side = "Left" })
		local aim_info = AimTab:Section({ Side = "Right" })
		-- Section returns only the widget-makers, not the Frame, so the frames are
		-- located by what they contain once they exist (see KEEP_PICKER below).

		-- "Aimbot" would be a lie. The only thing this does is mousemoverel - it moves
		-- the cursor, and never clicks. It assists the aim, it does not take the shot.
		aim_main:Header({ Text = "Assistencia de mira" })

		-- Turning this off must actually stop the connection, not just make the
		-- loop idle: sync_aim is what start_aim/stop_aim are behind.
		aim_main:Toggle({
			Name = "Enabled",
			Default = CFG.aim_on,
			Callback = function(v)
				CFG.aim_on = v and true or false
				sync_aim()
			end,
		})

		-- Slider instead of a three-option dropdown: the FOV is a radius and the
		-- useful range is continuous. The slider writes cfg.aim_fov on every drag,
		-- and the aim reads it fresh each frame, so no restart is needed.
		--
		-- The library paints the filled track a fixed colour and offers no hook to
		-- change it, so the colour-for-low/mid/high is done by tinting the value
		-- box next to the slider from the callback below.
		aim_main:Slider({
			Name = "FOV (px)",
			Default = CFG.aim_fov,
			Minimum = 40,
			Maximum = 600,
			DisplayMethod = "Round",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil then
					return
				end
				-- Clamped, not rejected: a slider can only emit values inside its own
				-- range, but a NaN or an absurd number pasted into the value box could
				-- still arrive here and would make the aim unable to find anything.
				if n ~= n then
					return
				end
				if n < 40 then n = 40 end
				if n > 600 then n = 600 end
				CFG.aim_fov = n
				aim_tint_fov(n)
			end,
		})

		-- Not a Keybind. A Keybind renders a TextBox that waits for a key and looks
		-- editable; the button this aim polls is fixed at MouseButton2, so the row
		-- would have been a control that silently refuses to be changed - worse than
		-- no row at all. A plain Label states the bind without pretending.
		aim_main:Label({
			Text = "Hold: botao direito do mouse (fixo)",
		})

		-- The tutorial that used to live here is gone. It explained the FOV radius
		-- and the hold button in two paragraphs, which the widget labels now say
		-- in one line each.
		aim_info:Header({ Text = "Alvo" })

		-- Which body part the aim pulls to. The stored value is the internal name
		-- (Head / Torso / Legs) because that is what the aim loop and the 3D dummy
		-- both match on; only the labels are Portuguese, so the option text never
		-- has to be parsed back into a part name. Picking here also moves the
		-- dummy's highlight, since both write CFG.aim_part through picker_select.
		-- Default is the 1-based INDEX into Options, the same contract the other
		-- dropdowns here use. Passing a label string instead left the library's
		-- display method at nil and the whole menu body died on the first render.
		aim_info:Dropdown({
			Name = "Parte do corpo",
			Options = AIM_PART_LABELS,
			Default = option_index_by_name(AIM_PART_LABEL, CFG.aim_part),
			Callback = function(option)
				-- The callback hands back the option's position, so the label is
				-- read back from the same list rather than trusted to be a string.
				local label = AIM_PART_LABELS[option]
				local part = AIM_PART_BY_LABEL[label]
				if part ~= nil then
					CFG.aim_part = part
					picker_highlight(part)
				end
			end,
		})

		-- Target the enemy's DRONE instead of their body. Drones live in a folder
		-- in Workspace and carry the pilot's name as an attribute, so "enemy drone"
		-- means "a drone whose pilot is not on my team" - the same check the
		-- player ESP already uses.
		aim_info:Toggle({
			Name = "So drones inimigos",
			Default = CFG.aim_drones_only,
			Callback = function(v)
				CFG.aim_drones_only = v and true or false
			end,
		})

		-- ============================================================ WORLD
		local WorldTab = Group:Tab({ Name = "WORLD" })
		local world_main = WorldTab:Section({ Side = "Left" })
		local world_info = WorldTab:Section({ Side = "Right" })

		world_main:Header({ Text = "Visao" })

		world_main:Toggle({
			Name = "Drone",
			Default = false,
			-- The drone's washed-out look is one ColorCorrection named "Drone"
			-- with Saturation -0.40 and Contrast -0.20. It is a client-side
			-- Lighting effect: nothing about it is replicated, so switching it off
			-- changes only what this client draws.
			Callback = function(v)
				CFG.world_drone = v and true or false
				apply_world()
			end,
		})

		world_main:Toggle({
			Name = "Fog",
			Default = false,
			Callback = function(v)
				CFG.world_fog = v and true or false
				apply_world()
			end,
		})

		world_main:Toggle({
			Name = "Neblina",
			Default = false,
			Callback = function(v)
				CFG.world_atmosphere = v and true or false
				apply_world()
			end,
		})

		-- Brightness. With the fog and the atmosphere off there is no haze left to
		-- scatter light, and the map goes dark. This raises Lighting.Brightness to
		-- the chosen value; off restores the number the game had.
		world_main:Toggle({
			Name = "Brilho",
			Default = false,
			Callback = function(v)
				CFG.world_bright = v and true or false
				apply_world()
			end,
		})

		world_main:Slider({
			Name = "Intensidade do brilho",
			Default = CFG.world_bright_value,
			Minimum = 1,
			Maximum = 10,
			-- One of the library's own display methods. There is no "Default":
			-- the table is Hundredths / Tenths / Round / Degrees / Percent, and
			-- anything else leaves ValueDisplayMethod nil and kills the menu body.
			DisplayMethod = "Round",
			Callback = function(n)
				CFG.world_bright_value = n
				if CFG.world_bright then
					apply_world()
				end
			end,
		})

		world_info:Header({ Text = "Camera" })
		world_info:Toggle({
			Name = "Terceira pessoa",
			Default = false,
			Callback = function(v)
				CFG.world_third = v and true or false
				apply_world()
			end,
		})


		-- =============================================================== UI
		local UiTab = Group:Tab({ Name = "UI" })
		local ui_main = UiTab:Section({ Side = "Left" })
		local ui_colors = UiTab:Section({ Side = "Right" })

		ui_main:Header({ Text = "Menu" })

		ui_main:Slider({
			Name = "Escala",
			Default = CFG.ui_scale,
			Minimum = 60,
			Maximum = 140,
			DisplayMethod = "Percent",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil or n ~= n then
					return
				end
				-- The slider speaks percent (60-140) because DisplayMethod Percent
				-- prints the raw number with a sign. Divided here, not stored, so
				-- CFG.ui_scale stays a multiplier.
				CFG.ui_scale = math.clamp(n / 100, 0.6, 1.4)
				apply_theme()
			end,
		})

		ui_main:Slider({
			Name = "Opacidade",
			Default = CFG.ui_opacity,
			Minimum = 10,
			Maximum = 100,
			DisplayMethod = "Percent",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil or n ~= n then
					return
				end
				CFG.ui_opacity = math.clamp(math.floor(n + 0.5), 10, 100)
				apply_theme()
			end,
		})

		ui_main:Dropdown({
			Name = "Tema",
			Options = THEME_NAMES,
			Default = option_index_by_name(THEME_NAMES, CFG.ui_theme),
			Callback = function(v)
				local name = THEME_NAMES[tonumber(v) or 0]
				if name ~= nil then
					CFG.ui_theme = name
					apply_theme()
				end
			end,
		})

		ui_colors:Header({ Text = "Bordas" })

		ui_colors:Toggle({
			Name = "RGB nas bordas",
			Default = CFG.ui_rgb,
			Callback = function(v)
				CFG.ui_rgb = v and true or false
				apply_theme()
			end,
		})

		ui_colors:Slider({
			Name = "Velocidade RGB",
			Default = math.floor(CFG.ui_rgb_speed * 100 + 0.5),
			Minimum = 5,
			Maximum = 200,
			DisplayMethod = "Percent",
			Callback = function(v)
				local n = tonumber(v)
				if n == nil or n ~= n then
					return
				end
				CFG.ui_rgb_speed = math.clamp(n / 100, 0.05, 2)
			end,
		})

		-- ============================================================ DRONE
		local DroneTab = Group:Tab({ Name = "DRONE" })
		local drone_main = DroneTab:Section({ Side = "Left" })
		local drone_esp = DroneTab:Section({ Side = "Right" })

		drone_main:Header({ Text = "Drone" })

		drone_main:Toggle({
			Name = "Melhorar visao",
			Default = CFG.drone_vision,
			Callback = function(v)
				CFG.drone_vision = v and true or false
				-- Same switch the WORLD tab uses, so the two can never disagree.
				CFG.world_drone = CFG.drone_vision
				apply_world()
			end,
		})

		drone_esp:Header({ Text = "ESP do drone" })

		drone_esp:Toggle({
			Name = "Enabled",
			Default = CFG.drone_esp,
			Callback = function(v)
				CFG.drone_esp = v and true or false
			end,
		})

		drone_esp:Toggle({
			Name = "Distancia",
			Default = CFG.drone_esp_dist,
			Callback = function(v)
				CFG.drone_esp_dist = v and true or false
			end,
		})

		drone_esp:Toggle({
			Name = "Piloto",
			Default = CFG.drone_esp_pilot,
			Callback = function(v)
				CFG.drone_esp_pilot = v and true or false
			end,
		})

		drone_esp:Toggle({
			Name = "Glowing",
			Default = CFG.drone_esp_glow,
			Callback = function(v)
				CFG.drone_esp_glow = v and true or false
			end,
		})

		drone_esp:Dropdown({
			Name = "Alcance",
			Options = { "500", "1000", "2000", "4000" },
			Default = option_index(DRONE_RANGES, CFG.drone_esp_range),
			Callback = function(v)
				local n = tonumber(v)
				if n == nil then
					return
				end
				for _, allowed in ipairs(DRONE_RANGES) do
					if n == allowed then
						CFG.drone_esp_range = n
						return
					end
				end
			end,
		})

		-- The 3D dummy is a separate ScreenGui, so it does not depend on the
		-- library's internals. It follows the AIM tab: shown on AIM, hidden
		-- everywhere else. Wrapped: a picker that cannot be built must not take
		-- the whole menu down with it.
		-- The picker follows the AIM tab. It cannot hook anything: TabFunctions is a
		-- per-tab closure with no event, and the Select on the shared metatable is
		-- not the function that actually runs. What IS reliable is the tree:
		-- MacLib reparents the selected tab's sections into the frame named
		-- "Content". So "the AIM sections are under Content" is exactly "the AIM
		-- tab is on screen", and it is checked once per frame in on_frame.
		local ok_picker = pcall(build_picker)
		if ok_picker then
			pcall(function()
				-- Record the first widget text unique to the AIM tab, so the
				-- sections can be recognised later: Section returns only the
				-- widget-makers, never the Frame, and all sections share one name.
				--
				-- WHERE THE MENU ACTUALLY LIVES, measured in game: not CoreGui and
				-- not PlayerGui. The vendored parent patch tries gethui() first and
				-- that succeeds, so MacLib lands in the executor's hidden container.
				-- Looking only in CoreGui/PlayerGui found nothing, PICKER.content
				-- stayed nil, and the dummy never appeared. All three are checked.
				local function find_content(root)
					if root == nil then
						return nil
					end
					local gui = root:FindFirstChild("MacLib")
					if gui == nil then
						return nil
					end
					for _, d in ipairs(gui:GetDescendants()) do
						if d.Name == "Content" and d:IsA("Frame") then
							return d
						end
					end
					return nil
				end
				PICKER.content = nil
				pcall(function()
					PICKER.content = find_content(gethui and gethui())
				end)
				if PICKER.content == nil then
					pcall(function()
						PICKER.content = find_content(game:GetService("CoreGui"))
					end)
				end
				if PICKER.content == nil then
					pcall(function()
						PICKER.content = find_content(game:GetService("Players")
							.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
					end)
				end
			end)
		end
		EspTab:Select()

		-- Find the value box of the FOV slider so the low/mid/high colour can be
		-- painted. The library builds it as a descendant named "SliderValue" and
		-- hands back no handle, so it is located by name under the window after
		-- the menu exists. Wrapped: a renamed internal only costs the colour.
		--
		-- Searched from the menu root, not from CoreGui: in game the menu lives in
		-- gethui(), and looking only in CoreGui found nothing, so the FOV value
		-- never got its band colour.
		pcall(function()
			local root = menu_root()
			if root == nil then
				return
			end
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == "SliderValue" and d:IsA("TextBox") then
					fov_value_box = d
					break
				end
			end
			if fov_value_box ~= nil then
				aim_tint_fov(CFG.aim_fov)
			end
		end)

		-- First paint of the theme, scale and opacity, once the tree exists.
		pcall(apply_theme)
	end)

	if not ok_body then
		warn("[LF] menu body failed: " .. tostring(err))
		return nil
	end

	W.window = Window
	return W
end

-- The menu is built inline, last, after the teardown registration and the frame
-- loop are already in place, and inside a pcall.
--
-- It used to be deferred to task.spawn, on the theory that a MacLib that hangs
-- while waiting for the camera's rays would then only cost the menu. That did not
-- hold: the build has to run inside a frame to be useful, so deferring it bought
-- nothing but an ordering the harness could not reproduce. Inline is honest - if
-- MacLib throws, the pcall catches it, the ESP and the aim are already running,
-- and the user gets a warning instead of a silent missing menu.
local ok_build, build_err = pcall(function()
	ui = build_ui()
end)
if not ok_build then
	warn("[LF] menu build failed: " .. tostring(build_err))
	ui = nil
end

if MacLib ~= nil then
	if ui ~= nil then
		print("[LF] stage 10: menu built, tabs = ESP, AIM, WORLD, UI, DRONE")
	else
		print("[LF] stage 10: menu built without body")
	end
else
	print("[LF] stage 10: menu unavailable")
end

--[[ teardown registry ]]
--
-- live-reload keeps the old chunk alive unless told to clean up. Without this,
-- every reload stacks another RenderStepped handler, another input listener and
-- another BindToRenderStep, and the oldest one keeps fighting the camera.
--
-- STATE is injected by live-reload as a global; it is read through getfenv so
-- analysis never sees a hard reference to an undeclared global.

local cleanup_conns = {}

local function keep(conn)
	cleanup_conns[#cleanup_conns + 1] = conn
	return conn
end

local marker = nil

local function destroy_all()
	alive = false
	-- The aim is a RenderStepped connection, not a BindToRenderStep. It must be
	-- disconnected here or every reload stacks another one and the pull gets
	-- multiplied by the number of loads.
	pcall(stop_aim)
	-- older builds bound the aim by name; unbind in case a stale one is around
	pcall(function()
		RunService:UnbindFromRenderStep("LF_AIM")
	end)
	for i = #cleanup_conns, 1, -1 do
		pcall(function()
			cleanup_conns[i]:Disconnect()
		end)
	end
	cleanup_conns = {}

	for i = #early_conns, 1, -1 do
		pcall(function()
			early_conns[i]:Disconnect()
		end)
	end
	early_conns = {}

	for _, s in pairs(state) do
		-- name the drawing fields explicitly: s.snap and s.lines are tables of
		-- drawings, so a blind pairs() walk would call :Remove() on a table and
		-- throw once per field per player during teardown.
		--
		-- box_fill is appended conditionally for the same reason the comment below
		-- gives for snap/lines: a nil inside the literal truncates ipairs and
		-- silently skips every entry after it.
		local singles = {
			s.outline, s.box, s.name, s.tag,
			s.hp_bg, s.hp_fill, s.hp_edge, s.dist,
		}
		if s.box_fill ~= nil then
			singles[#singles + 1] = s.box_fill
		end
		for _, obj in ipairs(singles) do
			pcall(function() obj:Remove() end)
		end
		-- ipairs over { s.snap, s.lines } stops at the first nil, and with lazy
		-- allocation either can be nil, so each set is walked on its own.
		if s.snap then
			for _, obj in pairs(s.snap) do
				pcall(function() obj:Remove() end)
			end
		end
		if s.lines then
			for _, obj in pairs(s.lines) do
				pcall(function() obj:Remove() end)
			end
		end
	end
	state = {}
	alloc.snap = nil
	alloc.lines = nil
	alloc.box_fill = nil
	-- drone drawings and their Highlights. The Highlights are Instances on the
	-- drone Models, so they outlive this script unless they are destroyed here -
	-- two reloads would otherwise stack two glows on every drone.
	for model, s in pairs(drone_draw) do
		for _, obj in ipairs({ s.box, s.outline, s.label, s.dist }) do
			pcall(function() obj:Remove() end)
		end
		pcall(function()
			local hl = model:FindFirstChild("LF_DroneGlow")
			if hl ~= nil then
				hl:Destroy()
			end
		end)
	end
	drone_draw = {}
	MENU.root = nil
	MENU.applied = false
	-- staged core slots: players still waiting must not survive a reload, or
	-- the next instance would build slots for a table it no longer owns
	core_pending = {}
	core_queued = {}
	proj_cache = {}

	-- The menu is Instances now, not Drawings. Window:Unload destroys the
	-- ScreenGui and runs its onUnloaded callback; without it a reload left the
	-- old window parented to CoreGui on top of the new one, and every Insert
	-- press toggled two windows at once.
	if ui ~= nil then
		pcall(function()
			ui.window:Unload()
		end)
		ui = nil
	end

	-- The 3D picker is its own ScreenGui, so Window:Unload does not touch it.
	-- Destroyed explicitly: it leaked one ScreenGui per reload until the reload
	-- test counted five of them.
	if PICKER.gui ~= nil then
		pcall(function()
			PICKER.gui:Destroy()
		end)
	end
	PICKER.gui = nil
	PICKER.frame = nil
	PICKER.zones = {}
	PICKER.built = false

	local owned = { ring, marker }
	for _, obj in ipairs(owned) do
		if obj ~= nil then
			pcall(function() obj:Remove() end)
		end
	end

	pcall(function()
		local env = globals()
		if type(env) == "table" then
			env.LF_SHARED = nil
			env.LF_LOG = nil
		end
	end)
end

-- Handed to the next load so it can retire this instance. Kept next to the
-- state it clears rather than in the block below, which only runs when the
-- loader offers a cleanup callback.
pcall(function()
	local env = getfenv(0)
	if type(env) == "table" then
		env.LF_TEARDOWN = destroy_all
	end
end)

-- getfenv is not guaranteed: the block above needed a pcall for exactly this
-- reason, and this one did not have it. On an executor that hides getfenv the
-- whole script died here with "attempt to call global 'getfenv'", which took the
-- ESP down with it - the opposite of what this file promises.
pcall(function()
	if type(getfenv) ~= "function" then
		return
	end
	local env = getfenv(0)
	local STATE_OBJ = nil
	if type(env) == "table" then
		STATE_OBJ = env.STATE
	end
	if STATE_OBJ ~= nil and STATE_OBJ.onCleanup ~= nil then
		STATE_OBJ.onCleanup(destroy_all)
		print("[LF] teardown registered")
	end
end)

--[[ input ]]

keep(UIS.InputBegan:Connect(function(input, processed)
	-- Hold state first, and deliberately before the `processed` check: the game
	-- having consumed a right-click is not a reason for the aim to ignore it.
	if E.inputtype ~= nil and same_enum(input.UserInputType, E.inputtype) then
		CFG.aim_held = true
		held_seen = true
		return
	end

	-- Menu clicks are MacLib's business now. It connects its own buttons and
	-- its own Insert bind, and swallows nothing this file needs: a left click is
	-- only interesting here as a click, and the aim does not use it.
	if processed then
		return
	end
end))

keep(UIS.InputEnded:Connect(function(input)
	if E.inputtype ~= nil and same_enum(input.UserInputType, E.inputtype) then
		CFG.aim_held = false
		held_seen = false
	end
end))

-- InputEnded is not guaranteed.
--
-- An executor that loses focus, a game that swallows the release, or a click
-- that ends outside the window all leave aim_held stuck true: the camera then
-- keeps pulling with no button down, which reads as "the aim is broken and the
-- screen drifts". Also covers the opposite: InputBegan without a matching
-- UserInputType object.
--
-- Polling UserInputService is the only reliable source when the event is missed.
keep(UIS.InputChanged:Connect(function()
	local down = false
	local ok = pcall(function()
		down = UIS:IsMouseButtonPressed(E.inputtype)
	end)
	if not ok then
		return
	end
	if down ~= CFG.aim_held then
		-- only trust this for release: a false negative from an executor that
		-- cannot answer IsMouseButtonPressed would otherwise block the aim
		if not down then
			CFG.aim_held = false
			held_seen = false
		end
	end
end))

do
	local env = globals()
	local sh = env and env.LF_SHARED
	if type(sh) == "table" then
		sh.apply_world = apply_world
		sh.apply_theme = apply_theme
		sh.rebuild_menu = nil
	end
end

print("[LF] stage 11: input bound")

--[[ frame ]]

local draw_errors = 0
local last_error = nil
-- Declared here because the block these used to live in was the old aim block.
-- Removing it left on_frame incrementing a GLOBAL `frames` that was never
-- assigned, which threw on the first frame and took the ESP down with it.
local frames = 0
-- Whether the hold button was seen down. The shipped aim reads the button
-- itself every frame; this only drives the reticle and the diagnostics.
local held_seen = false

local function on_frame()
	-- One widget lookup per frame. Cheap, and it cannot desynchronise the way a
	-- hook or a flag can.
	pcall(function()
		picker_show(aim_tab_showing())
	end)

	-- Recolour the menu while the border RGB is on. Only then: a full recolour
	-- walk is a few hundred property writes, and there is no reason to pay it
	-- when the accent is a fixed colour.
	if CFG.ui_rgb then
		pcall(apply_theme)
	end

	frames = frames + 1

	local c = cam()
	if not c then
		return
	end

	-- LP is nil until the executor hands one over, and nil between server
	-- hops on some builds. Indexing it killed the whole frame in the harness.
	if LP == nil then
		return
	end

	local my_char = LP.Character
	local my_root = my_char and my_char:FindFirstChild("HumanoidRootPart")
	local my_pos = my_root and my_root.Position or c.CFrame.Position

	-- build at most one player's core slot this frame, before the draw loop
	-- asks for one; otherwise a group spawn allocates everything at once
	service_core()

	-- one cache for the whole frame: bones of different players never collide
	-- because the key is the part instance itself
	clear_proj_cache()

	for _, p in ipairs(Players:GetPlayers()) do
		if p == LP then
			local own = state[p]
			if own then
				hide(own)
			end
		else
			local ok, err = pcall(draw_player, p, my_pos)
			if not ok then
				draw_errors = draw_errors + 1
				if err ~= last_error then
					last_error = err
					warn("[LF] draw error: " .. tostring(err))
				end
				local g = globals()
		local log = g and g.LF_LOG
				if type(log) ~= "table" then
					log = {}
					if g ~= nil then g.LF_LOG = log end
				end
				if #log < 10 then
					log[#log + 1] = "draw error: " .. tostring(err)
				end
			end
		end
	end

	-- Drones are drawn after the players and from their own slots, so a drone
	-- that appears or despawns can never disturb a player's drawings.
	local ok_drone, drone_err = pcall(draw_drones, c, my_pos)
	if not ok_drone then
		draw_errors = draw_errors + 1
		if drone_err ~= last_error then
			last_error = drone_err
			warn("[LF] drone draw error: " .. tostring(drone_err))
		end
	end

	-- The reticle follows the MOUSE, not screen centre, because that is the point
	-- the shipped aim measures its fov radius from. Its radius IS the fov in
	-- pixels, so the circle is exactly the region the range test accepts - no
	-- conversion, and Camera.FieldOfView (observed at 4010 degrees in this game)
	-- is never consulted.
	local mouse = aim_state.mouse
	if mouse == nil then
		local okm, loc = pcall(function()
			return UIS:GetMouseLocation()
		end)
		if okm and loc ~= nil then
			-- Same conversion the aim loop does: GetMouseLocation is mouse space
			-- (Y up from the bottom), the reticle is drawn in screen space (Y down
			-- from the top). Without this the circle sat mirrored across the
			-- middle of the screen from where the aim was actually measuring.
			local vp = WS.CurrentCamera and WS.CurrentCamera.ViewportSize
			if vp ~= nil then
				pcall(function()
					loc = Vector2.new(loc.X, vp.Y - loc.Y)
				end)
			end
			mouse = loc
			aim_state.mouse = loc
		end
	end
	ring.Visible = CFG.aim_on and aim_enabled and CFG.aim_held and mouse ~= nil
	if ring.Visible then
		ring.Position = Vector2.new(mouse.X, mouse.Y)
		ring.Radius = CFG.aim_fov
	end

	-- The team registry, read on a slow timer.
	--
	-- It is one round trip and it only changes on a team switch, so it must not
	-- ride the frame loop. First read happens two seconds in, after the client has
	-- settled; the ESP shows everyone until then rather than guessing.
	local now_side = os.clock()
	if now_side - side_fetched_at > SIDE_REFRESH and side_busy == false then
		side_fetched_at = now_side
		side_busy = true
		task.spawn(function()
			pcall(fetch_sides)
			side_busy = false
			ally_cache = {}
		end)
	end

	-- The menu needs no per-frame work: MacLib owns its own rendering, and the
	-- widgets already wrote CFG when they were clicked. The old render_menu()
	-- call lived here and is gone with the Drawing menu.

	-- Publish the aim's state every frame, not on a timer.
	--
	-- The shipped aim pulls the mouse rather than writing the camera, so the old
	-- counters (ticks / turns / overwritten) do not apply. What matters now is
	-- whether a target is held and how far the cursor was moved, which is what
	-- AimDiag reads back.
	do
		local g = globals()
		local sh = g and g.LF_SHARED
		if type(sh) == "table" then
			local st = sh.stats
			if st == nil then
				st = {}
				sh.stats = st
			end
			st.bound = aim_enabled and aim_unbind ~= nil
			st.errors = aim_state.errors
			st.point = aim_state.target ~= nil
			st.target = aim_state.target and aim_state.target.Name or nil
			st.dx = aim_state.dx
			st.dy = aim_state.dy
			st.pulls = aim_state.pulls
			st.fov = CFG.aim_fov
			-- every remaining aim_state field, so a diagnostic never has to guess
			-- which ones were copied across by hand
			for k, v in pairs(aim_state) do
				if k ~= "target" then
					st["aim_" .. k] = v
				end
			end
			-- what the team check believes, so a wrong ESP can be told apart from
			-- no team check at all
			st.side = side_of(LP)
			st.side_count = 0
			if SIDE_REGISTRY ~= nil then
				for _ in pairs(SIDE_REGISTRY) do
					st.side_count = st.side_count + 1
				end
			end
			st.side_errors = side_errors
		end
	end

	-- serve one queued line-set allocation per frame, spreading the cost
	service_alloc()

	-- Reconcile the aim's running state with the menu, in case something set
	-- CFG.aim_on directly instead of clicking the row.
	sync_aim()
end

keep(RunService.RenderStepped:Connect(on_frame))
print("[LF] stage 12: frame connected")

-- Report the aim's state 4 s in. Holding the button is not required to get a
-- useful answer: what is checked is that the connection exists at all.
task.delay(4, function()
	if alive and aim_enabled and aim_unbind == nil and CFG.aim_on then
		warn("[LF] aim is enabled but has no running connection - start_aim failed")
	end
end)

task.delay(3, function()
	print("[LF] alive: frames=" .. tostring(frames) .. " draw_errors=" .. tostring(draw_errors))
end)

-- short-lived marker so "nothing visible" is unambiguous: if this shows and
-- boxes do not, Drawing works and the problem is projection or player list.
-- Assigned, not redeclared: destroy_all holds a reference to this same local.
marker = new_drawing("Text")
if marker == nil then
	-- budget exhausted; the probe is a diagnostic, not a feature, so skip it
	-- rather than throw here and lose everything set up above
	warn("[LF] marker unavailable (Drawing budget full) - script still running")
else
	marker.Text = "LF OK"
	marker.Size = 18
	marker.Outline = true
	marker.OutlineColor = Color3.new(0, 0, 0)
	marker.Color = Color3.fromRGB(255, 70, 70)
	marker.Position = Vector2.new(40, 40)
	marker.ZIndex = 999
	marker.Visible = true
end
task.delay(5, function()
	if marker ~= nil then
		pcall(function() marker:Remove() end)
	end
end)

return "[LF] loaded ok"
