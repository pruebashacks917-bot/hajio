-- Universal Hub (executor script, any Roblox game)
-- Rail on the left (tabs), player card + search on top, option cards below. Default menu key: RightShift.
-- Some features need executor functions: Drawing (ESP boxes/lines), hookmetamethod (silent aim),
-- mouse1click (triggerbot), mousemoverel (mouse aim method), file functions (configs, remembered settings).

local genv = (getgenv and getgenv()) or _G
if genv.__UA_UNLOAD then pcall(genv.__UA_UNLOAD) end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer

local has = {
	mouseMove = type(mousemoverel) == "function",
	click = type(mouse1click) == "function",
	drawing = type(Drawing) ~= "nil" and type(Drawing.new) == "function",
	hook = type(hookmetamethod) == "function" and type(newcclosure) == "function"
		and type(checkcaller) == "function" and type(getnamecallmethod) == "function",
	files = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function"
		and type(listfiles) == "function",
}

----------------------------------------------------------------------
-- config (everything the menu edits lives here; saved/loaded as JSON)
----------------------------------------------------------------------
local cfg = {
	-- combat
	aimbot = true,
	aimBind = { kind = "Mouse", name = "MouseButton2" },
	aimMethod = "Camera",
	aimPart = "Head",
	priority = "Cursor",
	smooth = 6,
	prediction = 0,
	fov = 150,
	showFov = true,
	fovColor = { 255, 255, 255 },
	teamCheck = true,
	wallCheck = true,
	aliveCheck = true,
	ffCheck = true, -- skip ForceField / spawn-protected / invulnerable targets
	silentAim = false,
	trigger = false,
	triggerDelay = 60,
	-- visual
	espBox = true,
	espName = true,
	espDist = true,
	espHealth = true,
	espTracer = false,
	tracerFrom = "Bottom",
	espSkeleton = false,
	chams = true,
	chamsFill = 55,
	teamColors = true,
	enemyColor = { 255, 70, 70 },
	espRange = 2000,
	-- player
	speed = false,
	walkspeed = 32,
	jump = false,
	jumppower = 80,
	fly = false,
	flyspeed = 60,
	noclip = false,
	infjump = false,
	antiafk = false,
	-- rage (Prison Life)
	rgOn = false,
	rgActivate = "Always", -- Always | Hold
	rgHold = { kind = "Mouse", name = "MouseButton2" },
	rgHitbox = "Head", -- Head | Torso | Legs | Random
	rgFallback = true, -- hitbox hidden and wallbang off: try the other parts
	rgPriority = "Distance", -- Distance | Health | Cursor
	rgMaxDist = 2000,
	rgFovOn = false,
	rgFov = 300,
	rgTeamCheck = true,
	rgTeamFilter = "All", -- All | Guards | Inmates | Criminals
	rgFFCheck = true,
	rgFriends = false, -- skip your Roblox friends
	rgWall = true, -- wallbang: shoot without a clear line
	rgPredict = 0,
	rgOrigin = "Real", -- Real | Spoof (ray origin glued to the target)
	rgSpoofDist = 3,
	rgTargets = "Single", -- Single | Cycle | All
	rgMaxTargets = 4,
	rgMultiHit = false, -- several players inside one ShootEvent payload
	rgRapid = false,
	rgRate = 20,
	rgBurst = 1,
	rgGunMods = true, -- GunStates: no spread, autofire, fire rate
	rgInfAmmo = true,
	rgAutoEquip = true,
	rgGun = "Auto", -- Auto | AK-47 | Remington 870 | M9
	rgAutoGuns = false, -- ask the armory for guns when you have none
	rgStrafe = false,
	rgStrafeMode = "Orbit", -- Orbit | Jitter | Behind
	rgStrafeR = 14,
	rgStrafeSpeed = 4,
	rgStrafeY = -2,
	rgAntiAim = "Off", -- Off | Spin | Jitter | Away
	rgSpin = 20,
	rgMelee = false,
	rgMeleeRange = 12,
	rgMeleeHits = 3,
	-- interface
	menuBind = { kind = "Key", name = "RightShift" },
	theme = "Dark",
	accent = { 108, 230, 200 }, -- mint
	customBg = { 23, 25, 30 },
	opacity = 7, -- % of see-through on the panel background
	notify = true,
	sounds = true, -- soft click on switches, whoosh on open
	streamer = false,
	autosave = true, -- remember settings between sessions
	rank = "PRO",
	credit = "Tu nombre",
	winX = 60,
	winY = 90,
	binds = {}, -- per-function toggle keys: cfgKey -> { kind, name }
}

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = deepcopy(v) end
	return o
end
local defaults = deepcopy(cfg)

local function col(c) return Color3.fromRGB(c[1], c[2], c[3]) end

local function bindName(b)
	if not b then return "None" end
	return (b.name:gsub("MouseButton", "M"))
end

local function bindMatches(b, input)
	if not b then return false end
	if b.kind == "Key" then
		return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == b.name
	end
	return input.UserInputType.Name == b.name
end

----------------------------------------------------------------------
-- shared namespaces (tables keep the local/upvalue counts low)
----------------------------------------------------------------------
local UI = { themed = {}, rows = {}, refreshers = {}, painters = {}, toggles = {}, pages = {}, tabBtns = {}, tabOrder = {}, meta = {}, open = false }
local F = {}
local S = { rolls = {}, esp = {}, orig = {}, nc = {}, conns = {}, aimHeld = false, lastClick = 0, startT = tick(), protCache = setmetatable({}, { __mode = "k" }) }

local function on(signal, fn)
	S.conns[#S.conns + 1] = signal:Connect(fn)
end

----------------------------------------------------------------------
-- remembered settings: loaded now (before the UI exists), saved after every change
----------------------------------------------------------------------
local DIR = "UniversalHub"
local AUTO_FILE = DIR .. "/autosave.json"

function F.merge(data)
	for k, v in pairs(data) do
		if cfg[k] ~= nil and type(cfg[k]) == type(v) then cfg[k] = deepcopy(v) end
	end
end

function F.autoload()
	if not has.files then return end
	pcall(function()
		if isfile(AUTO_FILE) then F.merge(HttpService:JSONDecode(readfile(AUTO_FILE))) end
	end)
end

function F.autosaveNow()
	if not (cfg.autosave and has.files) then return end
	pcall(function()
		if not isfolder(DIR) then makefolder(DIR) end
		writefile(AUTO_FILE, HttpService:JSONEncode(cfg))
	end)
end

-- debounced: many quick changes (dragging a slider) end in one write
function UI.changed()
	if not (cfg.autosave and has.files) then return end
	S.saveTok = (S.saveTok or 0) + 1
	local tok = S.saveTok
	task.delay(0.8, function()
		if tok == S.saveTok then F.autosaveNow() end
	end)
end

F.autoload()

----------------------------------------------------------------------
-- theme
----------------------------------------------------------------------
local THEMES = {
	Dark = {
		bg = Color3.fromRGB(23, 25, 30), side = Color3.fromRGB(17, 19, 23), card = Color3.fromRGB(31, 34, 43), hi = Color3.fromRGB(39, 43, 54),
		track = Color3.fromRGB(17, 19, 23), chip = Color3.fromRGB(26, 29, 36), stroke = Color3.fromRGB(46, 50, 60), line = Color3.fromRGB(36, 39, 47),
		text = Color3.fromRGB(238, 240, 246), sub = Color3.fromRGB(168, 174, 188), faint = Color3.fromRGB(104, 110, 124), -- titles / options / details
		offtrack = Color3.fromRGB(44, 48, 59), offknob = Color3.fromRGB(138, 143, 156),
	},
	Light = {
		bg = Color3.fromRGB(244, 245, 248), side = Color3.fromRGB(232, 234, 240), card = Color3.fromRGB(255, 255, 255), hi = Color3.fromRGB(238, 241, 247),
		track = Color3.fromRGB(224, 227, 235), chip = Color3.fromRGB(240, 242, 247), stroke = Color3.fromRGB(205, 209, 220), line = Color3.fromRGB(222, 225, 232),
		text = Color3.fromRGB(24, 28, 40), sub = Color3.fromRGB(84, 90, 106), faint = Color3.fromRGB(140, 146, 160),
		offtrack = Color3.fromRGB(214, 218, 228), offknob = Color3.fromRGB(160, 166, 180),
	},
	Midnight = {
		bg = Color3.fromRGB(10, 13, 26), side = Color3.fromRGB(6, 8, 18), card = Color3.fromRGB(20, 25, 46), hi = Color3.fromRGB(28, 34, 62),
		track = Color3.fromRGB(8, 10, 22), chip = Color3.fromRGB(16, 20, 38), stroke = Color3.fromRGB(40, 48, 88), line = Color3.fromRGB(26, 32, 58),
		text = Color3.fromRGB(232, 236, 255), sub = Color3.fromRGB(160, 170, 214), faint = Color3.fromRGB(96, 108, 158),
		offtrack = Color3.fromRGB(36, 42, 76), offknob = Color3.fromRGB(122, 134, 190),
	},
}
local T = {}

function UI.computeTheme()
	local base = THEMES[cfg.theme]
	if not base then -- "Custom": derive everything from the chosen background color
		local bg = col(cfg.customBg)
		local light = (bg.R * 0.299 + bg.G * 0.587 + bg.B * 0.114) > 0.55
		local tint = light and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		local black = Color3.new(0, 0, 0)
		base = {
			bg = bg,
			side = bg:Lerp(black, light and 0.05 or 0.3),
			card = bg:Lerp(tint, 0.06),
			hi = bg:Lerp(tint, 0.11),
			track = bg:Lerp(black, light and 0.08 or 0.35),
			chip = bg:Lerp(tint, 0.03),
			stroke = bg:Lerp(tint, 0.2),
			line = bg:Lerp(tint, 0.1),
			text = light and Color3.fromRGB(24, 28, 40) or Color3.fromRGB(238, 240, 246),
			sub = light and Color3.fromRGB(84, 90, 106) or Color3.fromRGB(168, 174, 188),
			faint = light and Color3.fromRGB(140, 146, 160) or Color3.fromRGB(104, 110, 124),
			offtrack = bg:Lerp(tint, 0.18),
			offknob = bg:Lerp(tint, 0.5),
		}
	end
	for k, v in pairs(base) do T[k] = v end
	T.accent = col(cfg.accent)
end
UI.computeTheme()

-- create an instance; th maps property -> theme key so it recolors on theme change
local function N(class, props, parent, th)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if th then
		for prop, key in pairs(th) do
			o[prop] = T[key]
			UI.themed[#UI.themed + 1] = { o, prop, key }
		end
	end
	o.Parent = parent
	return o
end

local function corner(parent, r)
	return N("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

-- every animation eases out (Quint): fast start, soft landing, never linear
local function TI(t)
	return TweenInfo.new(t or 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end
local function tw(o, t, props)
	local x = TweenService:Create(o, TI(t), props)
	x:Play()
	return x
end

-- border stroke (explicit Border mode: on Text* objects the default would outline the glyphs instead)
local function stroke(parent, thk, key)
	return N("UIStroke", { Thickness = thk or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent, { Color = key or "stroke" })
end

function UI.applyTheme()
	UI.computeTheme()
	for i = #UI.themed, 1, -1 do
		local e = UI.themed[i]
		if e[1].Parent == nil then
			table.remove(UI.themed, i)
		else
			e[1][e[2]] = T[e[3]]
		end
	end
	for _, p in ipairs(UI.painters) do pcall(p) end -- state-dependent colors (switches, tabs, ...)
end

function UI.refresh()
	for _, r in ipairs(UI.refreshers) do pcall(r) end
end

----------------------------------------------------------------------
-- gui root, fov circle, sounds, dim layer, toasts
-- spacing is a multiple of 4; radii nest: window 12 > cards 8 > inner chips 6
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "UH" .. math.random(1000, 9999)
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
	local ok = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = lp:WaitForChild("PlayerGui")
	end
end
-- Highlights render reliably from CoreGui-like parents; otherwise they go on the character
S.hlInGui = not gui:IsDescendantOf(lp)

function UI.screen()
	local s = gui.AbsoluteSize
	if s.X < 200 or s.Y < 200 then
		local cam = workspace.CurrentCamera
		s = cam and cam.ViewportSize or Vector2.new(1280, 720)
	end
	return s
end

F.fovFrame = N("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(300, 300),
	Visible = false,
}, gui)
corner(F.fovFrame, 9999)
F.fovStroke = N("UIStroke", { Thickness = 1.5, Transparency = 0.3, Color = Color3.new(1, 1, 1) }, F.fovFrame)

-- sounds: client built-in files, first candidate that actually loads wins (silent if none does)
UI.snd = {}
do
	local sets = {
		click = { "rbxasset://sounds/switch.mp3", "rbxasset://sounds/clickfast.mp3", "rbxasset://sounds/button.mp3" },
		open = { "rbxasset://sounds/swoosh.mp3", "rbxasset://sounds/snap.mp3" },
	}
	local level = { click = { 0.18, 1.3 }, open = { 0.14, 1.5 } } -- volume, playback speed
	task.spawn(function()
		local CP = game:GetService("ContentProvider")
		for name, list in pairs(sets) do
			for _, id in ipairs(list) do
				local s = Instance.new("Sound")
				s.SoundId, s.Volume, s.PlaybackSpeed = id, level[name][1], level[name][2]
				s.Parent = gui
				pcall(function() CP:PreloadAsync({ s }) end)
				if s.TimeLength > 0 then
					UI.snd[name] = s
					break
				end
				s:Destroy()
			end
		end
	end)
end

function UI.sfx(name)
	if not cfg.sounds or cfg.streamer then return end
	local s = UI.snd[name]
	if s and s.Parent then
		pcall(function()
			s.TimePosition = 0
			s:Play()
		end)
	end
end

-- dim layer behind the window (does not block clicks)
local dim = N("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)

----------------------------------------------------------------------
-- window: rail (tabs) on the left; strip + player card + search + page on the right
----------------------------------------------------------------------
local RAIL_W = 68
local scr0 = UI.screen()
local WIN_W = math.min(600, scr0.X - 24)
local WIN_H = math.min(560, scr0.Y - 48)
local LOW = 128 -- y where the lower part (search, heading, page) starts; also the collapsed height
UI.WIN_W, UI.WIN_H = WIN_W, WIN_H

function UI.clampPos(p)
	local s = UI.screen()
	return Vector2.new(math.clamp(p.X, 120 - WIN_W, s.X - 120), math.clamp(p.Y, 0, s.Y - 60))
end
UI.pos = UI.clampPos(Vector2.new(cfg.winX, cfg.winY))

local root = N("Frame", {
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.fromOffset(UI.pos.X, UI.pos.Y),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
UI.scale = N("UIScale", { Scale = 0.95 }, root)

-- very soft, wide shadow: stacked near-transparent layers (no image asset needed)
local shadowG = N("CanvasGroup", {
	Position = UDim2.fromOffset(-40, -40),
	Size = UDim2.new(1, 80, 1, 80),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
}, root)
for k = 1, 6 do
	local e = k * 4
	local l = N("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		Size = UDim2.new(1, -80 + 2 * e, 1, -80 + 2 * e),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
	}, shadowG)
	corner(l, 12 + e)
end

local W = N("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1 }, root)
corner(W, 13)

local body = N("Frame", {
	Position = UDim2.fromOffset(1, 1),
	Size = UDim2.new(1, -2, 1, -2),
	BorderSizePixel = 0,
	Active = true, -- clicks on the panel never reach the game
	BackgroundTransparency = cfg.opacity / 100,
}, W, { BackgroundColor3 = "bg" })
corner(body, 12)
stroke(body, 1, "stroke")

local rail = N("Frame", { Size = UDim2.new(0, RAIL_W, 1, 0), BorderSizePixel = 0, BackgroundTransparency = cfg.opacity / 100 }, body, { BackgroundColor3 = "side" })
N("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0 }, rail, { BackgroundColor3 = "line" })

local logo = N("TextLabel", {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(44, 44),
	Text = "H",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(17, 19, 23),
	BorderSizePixel = 0,
}, rail, { BackgroundColor3 = "accent" })
corner(logo, 8)

local navTop = N("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, rail)
local navBot = N("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, rail)

local main = N("Frame", { Position = UDim2.fromOffset(RAIL_W, 0), Size = UDim2.new(1, -RAIL_W, 1, 0), BackgroundTransparency = 1 }, body)

-- 1px highlight along the top edge, brightest in the middle, as if lit from above
do
	local hl = N("Frame", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, body)
	N("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, hl)
end

-- top strip: drag handle (click without moving collapses) + live fps / ping on the right
local strip = N("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, main)
N("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(32, 4), BorderSizePixel = 0 }, strip, { BackgroundColor3 = "offtrack" })
corner(strip:FindFirstChildOfClass("Frame"), 9999)
UI.liveLbl = N("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 4),
	Size = UDim2.fromOffset(140, 16),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.RobotoMono,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
}, strip, { TextColor3 = "faint" })

UI.card = N("Frame", { Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -32, 0, 96), BorderSizePixel = 0 }, main, { BackgroundColor3 = "card" })
corner(UI.card, 8)

local lower = N("Frame", { Position = UDim2.fromOffset(0, LOW), Size = UDim2.new(1, 0, 1, -LOW), BackgroundTransparency = 1 }, main)

local sbar = N("Frame", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 0, 40), BorderSizePixel = 0 }, lower, { BackgroundColor3 = "card" })
corner(sbar, 8)

UI.title = N("TextLabel", {
	Position = UDim2.fromOffset(16, 52),
	Size = UDim2.new(0.5, -16, 0, 32),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
}, lower, { TextColor3 = "text" })
UI.subtitle = N("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 52),
	Size = UDim2.new(0.5, -16, 0, 32),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
}, lower, { TextColor3 = "faint" })

local pagesGroup = N("CanvasGroup", { Position = UDim2.fromOffset(16, 92), Size = UDim2.new(1, -32, 1, -140), BackgroundTransparency = 1, BorderSizePixel = 0 }, lower)

-- hover cursor: one thin accent bar that slides from row to row (driven by UI.hoverStep)
UI.cursor = N("Frame", { Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(3, 20), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, pagesGroup, { BackgroundColor3 = "accent" })
corner(UI.cursor, 9999)

N("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -32), Size = UDim2.new(1, -32, 0, 1), BorderSizePixel = 0 }, lower, { BackgroundColor3 = "line" })
UI.verLbl = N("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -8),
	Size = UDim2.new(0.5, -16, 0, 20),
	BackgroundTransparency = 1,
	Text = "v2.6 · build 124",
	Font = Enum.Font.RobotoMono,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, lower, { TextColor3 = "faint" })
UI.keyLbl = N("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -8),
	Size = UDim2.new(0.5, -16, 0, 20),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
}, lower, { TextColor3 = "faint" })
function UI.paintFooter()
	UI.keyLbl.Text = bindName(cfg.menuBind) .. " para ocultar"
end
UI.refreshers[#UI.refreshers + 1] = UI.paintFooter
UI.paintFooter()

function UI.applyOpacity()
	local a = math.clamp(cfg.opacity, 0, 70) / 100
	body.BackgroundTransparency = a
	rail.BackgroundTransparency = a
end

----------------------------------------------------------------------
-- toasts: small notices at the bottom center
----------------------------------------------------------------------
UI.toastBox = N("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -32), Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1 }, gui)
N("UIListLayout", {
	Padding = UDim.new(0, 8),
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, UI.toastBox)
UI.toasts, UI.toastN = {}, 0

local function toastFade(t, a, dur)
	for _, p in ipairs(t.parts) do
		tw(p[1], dur, { [p[2]] = a })
	end
end

local function toastArm(t, key)
	t.tok = t.tok + 1
	local tok = t.tok
	task.delay(2.4, function()
		if t.tok ~= tok or not t.f.Parent then return end
		toastFade(t, 1, 0.3)
		task.delay(0.32, function()
			if t.tok == tok then
				UI.toasts[key] = nil
				t.f:Destroy()
			end
		end)
	end)
end

function UI.notify(title, sub)
	if not cfg.notify or cfg.streamer then return end
	local key = title .. "|" .. (sub or "")
	local old = UI.toasts[key]
	if old and old.f.Parent then
		toastFade(old, 0, 0.1)
		toastArm(old, key)
		return
	end
	UI.toastN = UI.toastN + 1
	local h = sub and 56 or 40
	local f = N("Frame", { Size = UDim2.fromOffset(300, h), BorderSizePixel = 0, BackgroundTransparency = 1, LayoutOrder = UI.toastN }, UI.toastBox, { BackgroundColor3 = "card" })
	corner(f, 8)
	local st = stroke(f, 1, "stroke")
	st.Transparency = 1
	local bar = N("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(0, 3, 1, -24), BackgroundTransparency = 1, BorderSizePixel = 0 }, f, { BackgroundColor3 = "accent" })
	corner(bar, 9999)
	local t1 = N("TextLabel", {
		Position = UDim2.fromOffset(28, sub and 10 or 0),
		Size = UDim2.new(1, -40, 0, sub and 20 or h),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, f, { TextColor3 = "text" })
	local parts = { { f, "BackgroundTransparency" }, { st, "Transparency" }, { bar, "BackgroundTransparency" }, { t1, "TextTransparency" } }
	if sub then
		local t2 = N("TextLabel", {
			Position = UDim2.fromOffset(28, 30),
			Size = UDim2.new(1, -40, 0, 16),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			Text = sub,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, f, { TextColor3 = "faint" })
		parts[#parts + 1] = { t2, "TextTransparency" }
	end
	local t = { f = f, parts = parts, tok = 0 }
	UI.toasts[key] = t
	toastFade(t, 0, 0.25)
	toastArm(t, key)
end

----------------------------------------------------------------------
-- drag (strip / rail / player card), click on the strip collapses
----------------------------------------------------------------------
UI.collapsed = false

function UI.collapse(v)
	if v == nil then v = not UI.collapsed end
	UI.collapsed = v
	navTop.Visible, navBot.Visible, lower.Visible = not v, not v, not v
	if UI.ind then UI.ind.Visible = not v end
	tw(root, 0.35, { Size = UDim2.fromOffset(WIN_W, v and LOW or WIN_H) })
end

do
	local dragging, moved, dragStart, startPos, collapses = false, false, nil, nil, false
	local function hook(handle, canCollapse)
		handle.InputBegan:Connect(function(i)
			local t = i.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging, moved, dragStart, startPos, collapses = true, false, i.Position, UI.pos, canCollapse
			end
		end)
	end
	hook(strip, true)
	hook(rail, false)
	hook(UI.card, false)
	on(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			if d.Magnitude > 4 then moved = true end
			if moved then
				UI.pos = UI.clampPos(Vector2.new(startPos.X + d.X, startPos.Y + d.Y))
				root.Position = UDim2.fromOffset(UI.pos.X, UI.pos.Y)
			end
		end
	end)
	on(UIS.InputEnded, function(i)
		local t = i.UserInputType
		if dragging and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			dragging = false
			if moved then
				cfg.winX, cfg.winY = UI.pos.X, UI.pos.Y
				UI.changed()
			elseif collapses then
				UI.collapse()
			end
		end
	end)
end

----------------------------------------------------------------------
-- open / close: grows 95% -> 100% while fading in, dim layer darkens, soft whoosh
----------------------------------------------------------------------
UI.openTok = 0

function UI.setOpen(v)
	if v == UI.open and root.Visible == v then return end
	UI.open = v
	UI.openTok = UI.openTok + 1
	local tok = UI.openTok
	local sx, sy = root.Size.X.Offset, root.Size.Y.Offset
	if v then
		if not root.Visible then
			UI.scale.Scale = 0.95
			root.Position = UDim2.fromOffset(UI.pos.X + sx * 0.025, UI.pos.Y + sy * 0.025 + 8)
			W.GroupTransparency, shadowG.GroupTransparency = 1, 1
			dim.BackgroundTransparency = 1
		end
		root.Visible, dim.Visible = true, true
		tw(UI.scale, 0.4, { Scale = 1 })
		tw(root, 0.4, { Position = UDim2.fromOffset(UI.pos.X, UI.pos.Y) })
		tw(W, 0.25, { GroupTransparency = 0 })
		tw(shadowG, 0.4, { GroupTransparency = 0 })
		tw(dim, 0.3, { BackgroundTransparency = 0.6 })
		UI.sfx("open")
	else
		tw(UI.scale, 0.25, { Scale = 0.97 })
		tw(root, 0.25, { Position = UDim2.fromOffset(UI.pos.X + sx * 0.015, UI.pos.Y + sy * 0.015 + 4) })
		tw(W, 0.2, { GroupTransparency = 1 })
		tw(shadowG, 0.2, { GroupTransparency = 1 })
		tw(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.28, function()
			if UI.openTok == tok then root.Visible, dim.Visible = false, false end
		end)
	end
	if UI.avatarShow then UI.avatarShow(v) end
end

function UI.retheme()
	UI.applyTheme()
	UI.applyOpacity()
	UI.refresh()
	UI.changed()
end

----------------------------------------------------------------------
-- shared helpers: slider dragging, key capture, press feedback
----------------------------------------------------------------------
function UI.dragTrack(track, cb)
	local dragging = false
	local function upd(x)
		cb(math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			upd(i.Position.X)
		end
	end)
	on(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			upd(i.Position.X)
		end
	end)
	on(UIS.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- next key / mouse button goes to cb(bind); Esc cancels (cb(nil))
function UI.capture(cb)
	if S.capture then S.capture(nil) end
	S.capture = cb
end

-- click feedback: shrinks to 98% on press, eases back on release
function UI.pressFX(btn, target)
	local sc = N("UIScale", { Scale = 1 }, target or btn)
	btn.MouseButton1Down:Connect(function() tw(sc, 0.08, { Scale = 0.98 }) end)
	local function up() tw(sc, 0.25, { Scale = 1 }) end
	btn.MouseButton1Up:Connect(up)
	btn.MouseLeave:Connect(up)
end

----------------------------------------------------------------------
-- icons: drawn from rounded frames, all 20x20 with the same 2px line (no emojis)
----------------------------------------------------------------------
function UI.icon(kind, parent, x, y)
	local box = N("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1 }, parent)
	local ic = { box = box, strokes = {}, fills = {} }

	-- (bx, by, bw, bh) is the outer visual box; the 2px stroke grows outside the frame, so the frame is 4px smaller
	local function ring(par, bx, by, bw, bh)
		local f = N("Frame", { Position = UDim2.fromOffset(bx + 2, by + 2), Size = UDim2.fromOffset(bw - 4, bh - 4), BackgroundTransparency = 1, BorderSizePixel = 0 }, par)
		corner(f, 9999)
		ic.strokes[#ic.strokes + 1] = N("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	end
	local function fill(par, bx, by, bw, bh, round)
		local f = N("Frame", { Position = UDim2.fromOffset(bx, by), Size = UDim2.fromOffset(bw, bh), BorderSizePixel = 0 }, par)
		if round then corner(f, 9999) end
		ic.fills[#ic.fills + 1] = f
		return f
	end

	if kind == "target" then
		ring(box, 2, 2, 16, 16)
		fill(box, 9, 0, 2, 4)
		fill(box, 9, 16, 2, 4)
		fill(box, 0, 9, 4, 2)
		fill(box, 16, 9, 4, 2)
		fill(box, 8, 8, 4, 4, true)
	elseif kind == "eye" then
		ring(box, 0, 4, 20, 12)
		fill(box, 7, 7, 6, 6, true)
	elseif kind == "user" then
		ring(box, 6, 0, 8, 8)
		local clip = N("Frame", { Position = UDim2.fromOffset(0, 11), Size = UDim2.fromOffset(20, 9), BackgroundTransparency = 1, ClipsDescendants = true }, box)
		ring(clip, 2, 0, 16, 14)
	elseif kind == "mix" then
		ring(box, 0, 4, 12, 12)
		ring(box, 8, 4, 12, 12)
	elseif kind == "info" then
		ring(box, 1, 1, 18, 18)
		fill(box, 9, 5, 2, 2)
		fill(box, 9, 9, 2, 6)
	elseif kind == "tune" then
		fill(box, 0, 3, 20, 2)
		fill(box, 0, 9, 20, 2)
		fill(box, 0, 15, 20, 2)
		fill(box, 11, 1, 6, 6, true)
		fill(box, 3, 7, 6, 6, true)
		fill(box, 12, 13, 6, 6, true)
	elseif kind == "rage" then
		ring(box, 0, 0, 20, 20)
		local a = fill(box, 0, 0, 2, 12)
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.Position = UDim2.fromOffset(10, 10)
		a.Rotation = 45
		local b = fill(box, 0, 0, 2, 12)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromOffset(10, 10)
		b.Rotation = -45
	elseif kind == "search" then
		ring(box, 0, 0, 13, 13)
		local h = fill(box, 0, 0, 2, 8)
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Position = UDim2.fromOffset(15, 15)
		h.Rotation = -45
	end

	function ic.paint(c)
		for _, s in ipairs(ic.strokes) do s.Color = c end
		for _, f in ipairs(ic.fills) do f.BackgroundColor3 = c end
	end
	return ic
end

----------------------------------------------------------------------
-- search bar
----------------------------------------------------------------------
do
	local sicon = UI.icon("search", sbar, 12, 10)
	UI.painters[#UI.painters + 1] = function() sicon.paint(T.faint) end
	UI.painters[#UI.painters]()
end

UI.searchBox = N("TextBox", {
	Position = UDim2.fromOffset(44, 0),
	Size = UDim2.new(1, -112, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	PlaceholderText = "Buscar opciones",
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, sbar, { TextColor3 = "sub", PlaceholderColor3 = "faint" })

do
	local kc = N("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(52, 24), BorderSizePixel = 0 }, sbar, { BackgroundColor3 = "chip" })
	corner(kc, 6)
	stroke(kc, 1, "line")
	N("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "Ctrl F", Font = Enum.Font.RobotoMono, TextSize = 11 }, kc, { TextColor3 = "faint" })
end

function UI.focusSearch()
	local sb = UI.searchBox
	local prev = sb.Text
	task.defer(function()
		sb:CaptureFocus()
		task.delay(0.08, function() -- drop the "f" that was typed with the shortcut
			if sb.Text == prev .. "f" or sb.Text == prev .. "F" then sb.Text = prev end
		end)
	end)
end

----------------------------------------------------------------------
-- tabs: icon buttons on the rail, accent indicator that slides to the active one
----------------------------------------------------------------------
UI.nTop, UI.nBot = 0, 0
UI.ind = N("Frame", { Size = UDim2.fromOffset(3, 20), Position = UDim2.fromOffset(0, 88), BorderSizePixel = 0 }, rail, { BackgroundColor3 = "accent" })
corner(UI.ind, 9999)

function UI.paintTabs()
	for n, t in pairs(UI.tabBtns) do
		local act = (n == UI.current)
		tw(t.b, 0.25, { BackgroundTransparency = act and 0 or (t.hover and 0.6 or 1) })
		tw(t.st, 0.25, { Transparency = act and 0.78 or 1 }) -- very faint accent glow on the active tab
		t.ic.paint(act and T.text:Lerp(T.accent, 0.45) or (t.hover and T.sub or T.faint))
	end
end
UI.painters[#UI.painters + 1] = UI.paintTabs

function UI.selectTab(name, instant)
	local same = (UI.current == name)
	UI.current = name
	for n, p in pairs(UI.pages) do p.Visible = (n == name) end
	local m = UI.meta[name]
	UI.title.Text = name
	UI.subtitle.Text = m and m.sub or ""
	UI.paintTabs()
	if m then
		if instant then
			UI.ind.Position = m.ind
		else
			tw(UI.ind, 0.4, { Position = m.ind })
		end
	end
	if not instant and not same then
		local p = UI.pages[name]
		pagesGroup.GroupTransparency = 1
		p.Position = UDim2.fromOffset(0, 8)
		tw(pagesGroup, 0.3, { GroupTransparency = 0 })
		tw(p, 0.4, { Position = UDim2.fromOffset(0, 0) })
	end
end

function UI.addTab(name, icon, sub, bottom)
	local pos, ind
	if bottom then
		local i = UI.nBot
		UI.nBot = i + 1
		pos = UDim2.new(0, 12, 1, -(56 + i * 52))
		ind = UDim2.new(0, 0, 1, -(44 + i * 52))
	else
		local i = UI.nTop
		UI.nTop = i + 1
		pos = UDim2.fromOffset(12, 76 + i * 52)
		ind = UDim2.fromOffset(0, 88 + i * 52)
	end
	local b = N("TextButton", {
		Position = pos,
		Size = UDim2.fromOffset(44, 44),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	}, bottom and navBot or navTop, { BackgroundColor3 = "card" })
	corner(b, 8)
	local st = N("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 1 }, b, { Color = "accent" })
	local ic = UI.icon(icon, b, 12, 12)
	UI.pressFX(b)
	local tab = { b = b, st = st, ic = ic, hover = false }
	b.MouseEnter:Connect(function() tab.hover = true; UI.paintTabs() end)
	b.MouseLeave:Connect(function() tab.hover = false; UI.paintTabs() end)

	local page = N("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, pagesGroup, { ScrollBarImageColor3 = "accent" })
	N("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	N("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, page)

	UI.tabBtns[name] = tab
	UI.pages[name] = page
	UI.meta[name] = { sub = sub, ind = ind }
	UI.tabOrder[#UI.tabOrder + 1] = name
	b.MouseButton1Click:Connect(function()
		if UI.current ~= name then UI.selectTab(name) end
	end)
	return setmetatable({ page = page, name = name }, { __index = UI.TabMethods })
end

----------------------------------------------------------------------
-- hover: the hovered card lightens and the accent cursor slides to it (called every frame)
----------------------------------------------------------------------
function UI.hoverStep(dt)
	local hit
	if UI.open and not UI.collapsed and pagesGroup.Visible then
		local m = UIS:GetMouseLocation()
		local pp, ps = pagesGroup.AbsolutePosition, pagesGroup.AbsoluteSize
		if m.X >= pp.X and m.X <= pp.X + ps.X and m.Y >= pp.Y and m.Y <= pp.Y + ps.Y then
			for _, r in ipairs(UI.rows) do
				if not r.section and r.page == UI.current and r.f.Visible then
					local p, s = r.f.AbsolutePosition, r.f.AbsoluteSize
					if m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y then
						hit = r.f
						break
					end
				end
			end
		end
	end
	if hit ~= UI.hov then
		if UI.hov and UI.hov.Parent then tw(UI.hov, 0.3, { BackgroundColor3 = T.card }) end
		if hit then tw(hit, 0.3, { BackgroundColor3 = T.hi }) end
		UI.hov = hit
	end

	-- exponential smoothing = an ease-out slide that also keeps up with scrolling
	local c = UI.cursor
	local a = 1 - math.exp(-dt * 22)
	if hit then
		local sc = UI.scale.Scale
		local ty = (hit.AbsolutePosition.Y - pagesGroup.AbsolutePosition.Y) / sc + (math.min(hit.AbsoluteSize.Y / sc, 48) - 20) / 2
		if not UI.curOn then
			c.Position = UDim2.fromOffset(4, ty)
			UI.curOn = true
		end
		local cur = c.Position.Y.Offset
		c.Position = UDim2.fromOffset(4, cur + (ty - cur) * a)
		c.BackgroundTransparency = c.BackgroundTransparency * (1 - a)
	else
		UI.curOn = false
		c.BackgroundTransparency = c.BackgroundTransparency + (1 - c.BackgroundTransparency) * a
	end
end

-- filter rows by name; jumps to the first tab that has a match
function UI.search(q)
	q = q:lower()
	local counts = {}
	for _, r in ipairs(UI.rows) do
		local vis
		if r.section then
			vis = (q == "")
		else
			vis = (q == "") or (r.name:find(q, 1, true) ~= nil)
			if vis then counts[r.page] = (counts[r.page] or 0) + 1 end
		end
		r.f.Visible = vis
	end
	if q ~= "" and (counts[UI.current] or 0) == 0 then
		for _, n in ipairs(UI.tabOrder) do
			if (counts[n] or 0) > 0 then
				UI.selectTab(n)
				break
			end
		end
	end
end
UI.searchBox:GetPropertyChangedSignal("Text"):Connect(function() UI.search(UI.searchBox.Text) end)

----------------------------------------------------------------------
-- player card: slowly rotating 3D avatar, greeting, name + rank badge, @user, live info
----------------------------------------------------------------------
do
	local card = UI.card

	local slot = N("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(72, 72), BorderSizePixel = 0 }, card, { BackgroundColor3 = "chip" })
	corner(slot, 6)
	local thumb = N("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop }, slot)
	corner(thumb, 6)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and img then thumb.Image = img end
	end)

	-- the viewport lives outside the (canvas) window so it re-renders every frame; it follows the slot
	local vp = N("ViewportFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ImageTransparency = 1,
		Visible = false,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(0.4, -0.5, 1),
	}, gui)
	corner(vp, 6)
	local cam = N("Camera", { FieldOfView = 28 }, vp)
	vp.CurrentCamera = cam

	local clone, angle = nil, 0

	local function build(char)
		if clone then clone:Destroy() clone = nil end
		if not char then return false end
		local ok = pcall(function()
			local was = char.Archivable
			char.Archivable = true
			local c = char:Clone()
			char.Archivable = was
			assert(c, "no clone")
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BaseScript") or d:IsA("Sound") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			c.Parent = vp
			c:PivotTo(CFrame.new())
			local head = c:FindFirstChild("Head")
			local hy = head and head.Position.Y or 1.6
			cam.CFrame = CFrame.lookAt(Vector3.new(0, hy + 0.1, -4.6), Vector3.new(0, hy - 0.3, 0))
			clone = c
		end)
		return ok and clone ~= nil
	end

	local function loadChar(char)
		task.spawn(function()
			if not char then return end
			char:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.8) -- let the appearance finish loading
			if lp.Character ~= char then return end
			if build(char) then thumb.Visible = false end
		end)
	end
	loadChar(lp.Character)
	on(lp.CharacterAdded, loadChar)

	function UI.avatarShow(v)
		if v then
			vp.Visible = true
			UI.avatarFollow()
		end
		tw(vp, 0.3, { ImageTransparency = v and 0 or 1 })
		if not v then
			task.delay(0.3, function()
				if not UI.open then vp.Visible = false end
			end)
		end
	end

	function UI.avatarFollow()
		if not vp.Visible then return end
		vp.Position = UDim2.fromOffset(slot.AbsolutePosition.X, slot.AbsolutePosition.Y)
		vp.Size = UDim2.fromOffset(slot.AbsoluteSize.X, slot.AbsoluteSize.Y)
	end

	function UI.avatarSpin(dt)
		if clone and clone.Parent and vp.Visible then
			angle = (angle + dt * 0.6) % (math.pi * 2)
			clone:PivotTo(CFrame.Angles(0, angle, 0))
		end
	end

	-- text column
	local TX = 96
	UI.greetLbl = N("TextLabel", {
		Position = UDim2.fromOffset(TX, 12),
		Size = UDim2.new(1, -(TX + 120), 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card, { TextColor3 = "faint" })

	local nameRow = N("Frame", { Position = UDim2.fromOffset(TX, 28), Size = UDim2.new(1, -(TX + 120), 0, 24), BackgroundTransparency = 1 }, card)
	N("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, nameRow)
	N("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = lp.DisplayName,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		LayoutOrder = 1,
	}, nameRow, { TextColor3 = "text" })
	UI.rankLbl = N("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		LayoutOrder = 2,
	}, nameRow, { TextColor3 = "accent" })
	N("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, UI.rankLbl)
	corner(UI.rankLbl, 4)
	stroke(UI.rankLbl, 1, "accent")

	N("TextLabel", {
		Position = UDim2.fromOffset(TX, 52),
		Size = UDim2.new(1, -(TX + 16), 0, 16),
		BackgroundTransparency = 1,
		Text = "@" .. lp.Name,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card, { TextColor3 = "sub" })

	UI.infoLbl = N("TextLabel", {
		Position = UDim2.fromOffset(TX, 68),
		Size = UDim2.new(1, -(TX + 16), 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.RobotoMono,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card, { TextColor3 = "faint" })

	-- "En línea" pill: one drawn dot + text, 1px accent outline
	local pill = N("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, card)
	corner(pill, 9999)
	local ps = stroke(pill, 1, "accent")
	ps.Transparency = 0.5
	N("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pill)
	N("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
	local dot = N("Frame", { Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, LayoutOrder = 1 }, pill, { BackgroundColor3 = "accent" })
	corner(dot, 9999)
	N("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "En línea",
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		LayoutOrder = 2,
	}, pill, { TextColor3 = "accent" })
end

function UI.paintRank()
	local r = cfg.rank or ""
	UI.rankLbl.Visible = (r ~= "")
	UI.rankLbl.Text = r
end
UI.refreshers[#UI.refreshers + 1] = UI.paintRank
UI.paintRank()

local function greeting()
	local h = tonumber(os.date("%H")) or 12
	if h >= 6 and h < 12 then return "Buenos días" end
	if h >= 12 and h < 20 then return "Buenas tardes" end
	return "Buenas noches"
end

-- slow info (greeting, session time, players); called about once a second
function UI.updateInfo()
	local mins = math.floor((tick() - S.startT) / 60)
	local t = (mins >= 60) and string.format("%d h %02d min", math.floor(mins / 60), mins % 60) or (mins .. " min")
	UI.greetLbl.Text = greeting() .. ","
	UI.infoLbl.Text = string.format("Sesión %s  ·  %d/%d jugadores", t, #Players:GetPlayers(), Players.MaxPlayers)
end
UI.updateInfo()

function UI.ping()
	local ok, v = pcall(function()
		return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return (ok and type(v) == "number") and v or nil
end

----------------------------------------------------------------------
-- components: rounded cards (radius 8), inner chips (radius 6), 16px side padding
-- text tones: titles = text, options = sub, details = faint. One accent color.
----------------------------------------------------------------------
local TM = {}
UI.TabMethods = TM

local ROW = 48 -- standard card height

local function lbl(parent, text, rightPad)
	return N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -(16 + rightPad), 0, ROW),
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent, { TextColor3 = "sub" })
end

-- small key chip anchored to the right of a card (fixed-width font so it never jumps)
local function keycap(parent, rightOff, text, minW)
	local b = N("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightOff, 0, ROW / 2),
		Size = UDim2.fromOffset(minW or 32, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = Enum.Font.RobotoMono,
		TextSize = 11,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, parent, { BackgroundColor3 = "chip", TextColor3 = "faint" })
	corner(b, 6)
	N("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	stroke(b, 1, "line")
	UI.pressFX(b)
	return b
end

function TM.row(self, h, text)
	self.n = (self.n or 0) + 1
	local f = N("Frame", { Size = UDim2.new(1, 0, 0, h), BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = self.n }, self.page, { BackgroundColor3 = "card" })
	corner(f, 8)
	UI.rows[#UI.rows + 1] = { f = f, name = (text or ""):lower(), page = self.name }
	return f
end

-- small spaced-out caps caption ("APUNTADO" -> "A P U N T A D O")
function TM.section(self, text)
	self.n = (self.n or 0) + 1
	local out = {}
	for _, c in utf8.codes(text) do out[#out + 1] = utf8.char(c) end
	local f = N("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = table.concat(out, " "),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = self.n,
	}, self.page, { TextColor3 = "faint" })
	N("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, f)
	UI.rows[#UI.rows + 1] = { f = f, name = "", page = self.name, section = true }
end

-- switch (slides) + key chip; opts.bind = false hides the chip; opts.cb(v) may return false to reject
function TM.toggle(self, text, key, opts)
	opts = opts or {}
	local withBind = opts.bind ~= false
	local f = self:row(ROW, text)
	lbl(f, text, withBind and 124 or 76)
	local hit = N("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, f)
	local sw = N("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(44, 24), BorderSizePixel = 0 }, f)
	corner(sw, 9999)
	local knob = N("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0 }, sw)
	corner(knob, 9999)
	local kc = withBind and keycap(f, 72, "—", 32) or nil

	local function paint(instant)
		local v = cfg[key]
		local trackC = v and T.accent or T.offtrack
		local knobC = v and T.side or T.offknob
		local kp = UDim2.new(0, v and 24 or 4, 0.5, 0)
		if instant then
			sw.BackgroundColor3, knob.BackgroundColor3, knob.Position = trackC, knobC, kp
		else
			tw(sw, 0.3, { BackgroundColor3 = trackC })
			tw(knob, 0.3, { BackgroundColor3 = knobC, Position = kp })
		end
		if kc then
			local b = cfg.binds[key]
			kc.Text = b and bindName(b) or "—"
			kc.TextColor3 = b and T.sub or T.faint
		end
	end
	local function set(v)
		cfg[key] = v
		if opts.cb and opts.cb(v) == false then cfg[key] = false end
		paint()
		UI.changed()
	end
	local function flip() -- used by the click and by the per-function key
		set(not cfg[key])
		UI.sfx("click")
		UI.notify(text, (cfg[key] and "Activado" or "Desactivado") .. ((cfg.autosave and has.files) and "  ·  guardado" or ""))
	end
	hit.MouseButton1Click:Connect(flip)
	UI.toggles[key] = flip
	if kc then
		kc.MouseButton1Click:Connect(function()
			kc.Text = "…"
			UI.capture(function(bind)
				if bind then cfg.binds[key] = bind end
				paint(true)
				UI.changed()
			end)
		end)
		kc.MouseButton2Click:Connect(function() -- right click clears the key
			cfg.binds[key] = nil
			paint(true)
			UI.changed()
		end)
	end
	UI.refreshers[#UI.refreshers + 1] = function() paint(true) end
	UI.painters[#UI.painters + 1] = function() paint(true) end
	paint(true)
end

-- name left, accent value right (counts up to the new number), thick rounded bar
function TM.slider(self, text, key, min, max, suffix, cb)
	suffix = suffix or ""
	local f = self:row(68, text)
	N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -128, 0, 20),
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, f, { TextColor3 = "sub" })
	local value = N("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(104, 20),
		Font = Enum.Font.RobotoMono,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, f, { TextColor3 = "accent" })
	local track = N("Frame", { Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 0, 8), BorderSizePixel = 0 }, f, { BackgroundColor3 = "track" })
	corner(track, 9999)
	local fillBar = N("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, track, { BackgroundColor3 = "accent" })
	corner(fillBar, 9999)
	local hitArea = N("Frame", { Position = UDim2.fromOffset(16, 32), Size = UDim2.new(1, -32, 0, 32), BackgroundTransparency = 1 }, f)

	local nv = Instance.new("NumberValue") -- the shown number runs to the new value instead of jumping
	nv.Changed:Connect(function(v)
		value.Text = math.floor(v + 0.5) .. suffix
	end)
	local function paint(instant)
		local rel = (cfg[key] - min) / (max - min)
		if instant then
			nv.Value = cfg[key]
			value.Text = cfg[key] .. suffix
			fillBar.Size = UDim2.fromScale(rel, 1)
		else
			tw(nv, 0.25, { Value = cfg[key] })
			tw(fillBar, 0.12, { Size = UDim2.fromScale(rel, 1) })
		end
	end
	UI.dragTrack(hitArea, function(rel)
		local v = math.floor(min + (max - min) * rel + 0.5)
		if v == cfg[key] then return end
		cfg[key] = v
		paint()
		if cb then cb(v) end
		UI.changed()
	end)
	UI.refreshers[#UI.refreshers + 1] = function() paint(true) end
	paint(true)
end

-- accent value + chevron on the right; the card grows and the options appear one after another
function TM.dropdown(self, text, key, options, cb)
	local opts = {}
	for i, o in ipairs(options) do opts[i] = type(o) == "table" and o or { o, o } end
	local function labelOf(v)
		for _, o in ipairs(opts) do
			if o[1] == v then return o[2] end
		end
		return tostring(v)
	end
	local f = self:row(ROW, text)
	lbl(f, text, 160)
	local head = N("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(0, ROW),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, f)
	N("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, head)
	local val = N("TextLabel", { Size = UDim2.fromOffset(0, ROW), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, LayoutOrder = 1 }, head, { TextColor3 = "accent" })
	local chev = N("TextLabel", { Size = UDim2.fromOffset(8, ROW), BackgroundTransparency = 1, Text = "›", Font = Enum.Font.GothamBold, TextSize = 18, LayoutOrder = 2 }, head, { TextColor3 = "faint" })

	local items, open = {}, false
	local function paint()
		val.Text = labelOf(cfg[key])
		for i, it in ipairs(items) do
			it.b.TextColor3 = (opts[i][1] == cfg[key]) and T.accent or T.sub
		end
	end
	local function setOpen(v, instant)
		open = v
		local h = v and (64 + #opts * 36) or ROW
		if instant then
			f.Size = UDim2.new(1, 0, 0, h)
			chev.Rotation = v and 90 or 0
		else
			tw(f, 0.3, { Size = UDim2.new(1, 0, 0, h) })
			tw(chev, 0.25, { Rotation = v and 90 or 0 })
		end
		for i, it in ipairs(items) do
			it.b.Visible = v
			if v and not instant then
				it.b.BackgroundTransparency, it.b.TextTransparency, it.st.Transparency = 1, 1, 1
				it.b.Position = UDim2.new(0, 16, 0, 56 + (i - 1) * 36 + 8)
				task.delay((i - 1) * 0.03, function() -- 0.03s between options
					if open and it.b.Parent then
						tw(it.b, 0.3, { BackgroundTransparency = 0, TextTransparency = 0, Position = UDim2.new(0, 16, 0, 56 + (i - 1) * 36) })
						tw(it.st, 0.3, { Transparency = 0 })
					end
				end)
			end
		end
		paint()
	end
	for i, o in ipairs(opts) do
		local ob = N("TextButton", {
			Position = UDim2.new(0, 16, 0, 56 + (i - 1) * 36),
			Size = UDim2.new(1, -32, 0, 32),
			Text = o[2],
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Visible = false,
		}, f, { BackgroundColor3 = "chip" })
		corner(ob, 6)
		local st = stroke(ob, 1, "line")
		UI.pressFX(ob)
		items[i] = { b = ob, st = st }
		ob.MouseButton1Click:Connect(function()
			cfg[key] = o[1]
			setOpen(false)
			if cb then cb(o[1]) end
			UI.changed()
			UI.notify(text, o[2])
		end)
	end
	head.MouseButton1Click:Connect(function() setOpen(not open) end)
	UI.refreshers[#UI.refreshers + 1] = function() setOpen(false, true) end
	UI.painters[#UI.painters + 1] = paint
	setOpen(false, true)
end

-- swatch on the right; opens H / S / V bars. cfg[key] = { r, g, b } (0-255)
function TM.color(self, text, key, cb)
	local f = self:row(ROW, text)
	lbl(f, text, 80)
	local sw = N("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0, ROW / 2),
		Size = UDim2.fromOffset(44, 24),
		Text = "",
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, f)
	corner(sw, 6)
	stroke(sw, 1, "line")
	UI.pressFX(sw)
	local hsv, fills = { 0, 0, 1 }, {}
	local function apply()
		local c = Color3.fromHSV(hsv[1], hsv[2], hsv[3])
		cfg[key] = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
		sw.BackgroundColor3 = c
		if cb then cb() end
		UI.changed()
	end
	for i, name in ipairs({ "H", "S", "V" }) do
		local y = 56 + (i - 1) * 28
		N("TextLabel", { Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(16, 20), BackgroundTransparency = 1, Text = name, Font = Enum.Font.RobotoMono, TextSize = 11 }, f, { TextColor3 = "faint" })
		local tr = N("Frame", { Position = UDim2.fromOffset(40, y + 6), Size = UDim2.new(1, -56, 0, 8), BorderSizePixel = 0 }, f, { BackgroundColor3 = "track" })
		corner(tr, 9999)
		fills[i] = N("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, tr, { BackgroundColor3 = "accent" })
		corner(fills[i], 9999)
		local hitArea = N("Frame", { Position = UDim2.fromOffset(40, y), Size = UDim2.new(1, -56, 0, 20), BackgroundTransparency = 1 }, f)
		UI.dragTrack(hitArea, function(rel)
			hsv[i] = rel
			tw(fills[i], 0.12, { Size = UDim2.fromScale(rel, 1) })
			apply()
		end)
	end
	local open = false
	sw.MouseButton1Click:Connect(function()
		open = not open
		tw(f, 0.3, { Size = UDim2.new(1, 0, 0, open and 140 or ROW) })
	end)
	local function paint()
		local c = col(cfg[key])
		hsv[1], hsv[2], hsv[3] = c:ToHSV()
		sw.BackgroundColor3 = c
		for i = 1, 3 do fills[i].Size = UDim2.fromScale(hsv[i], 1) end
	end
	UI.refreshers[#UI.refreshers + 1] = paint
	paint()
end

-- three preset swatches (single accent color for the whole menu); cfg[key] = { r, g, b }
function TM.presets(self, text, key, presets, cb)
	local f = self:row(80, text)
	N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 20),
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, f, { TextColor3 = "sub" })
	local holder = N("Frame", { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 32), BackgroundTransparency = 1 }, f)
	N("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	local n = #presets
	local btns = {}
	for i, p in ipairs(presets) do
		local b = N("TextButton", {
			Size = UDim2.new(1 / n, -(8 * (n - 1)) / n, 1, 0),
			Text = "",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = i,
		}, holder, { BackgroundColor3 = "chip" })
		corner(b, 6)
		local st = stroke(b, 1, "line")
		local dot = N("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, BackgroundColor3 = col(p[2]) }, b)
		corner(dot, 9999)
		local nm = N("TextLabel", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Text = p[1], Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, b)
		UI.pressFX(b)
		btns[i] = { st = st, nm = nm }
		b.MouseButton1Click:Connect(function()
			cfg[key] = deepcopy(p[2])
			UI.applyTheme()
			UI.refresh()
			UI.changed()
			if cb then cb() end
			UI.notify("Color de acento", p[1])
		end)
	end
	local function paint()
		local c = cfg[key]
		for i, p in ipairs(presets) do
			local sel = (c[1] == p[2][1] and c[2] == p[2][2] and c[3] == p[2][3])
			btns[i].st.Color = sel and T.accent or T.line
			btns[i].nm.TextColor3 = sel and T.text or T.sub
		end
	end
	UI.refreshers[#UI.refreshers + 1] = paint
	UI.painters[#UI.painters + 1] = paint
	paint()
end

-- whole card is the button; click feedback shrinks it to 98%
function TM.button(self, text, cb)
	local f = self:row(ROW, text)
	local b = N("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		AutoButtonColor = false,
	}, f, { TextColor3 = "sub" })
	UI.pressFX(b, f)
	b.MouseButton1Click:Connect(function()
		UI.sfx("click")
		cb()
	end)
end

function TM.textbox(self, text, default, cb)
	local f = self:row(ROW, text)
	lbl(f, text, 188)
	local tb = N("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0, ROW / 2),
		Size = UDim2.fromOffset(160, 28),
		Text = default,
		PlaceholderText = "nombre",
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
	}, f, { BackgroundColor3 = "chip", TextColor3 = "sub", PlaceholderColor3 = "faint" })
	corner(tb, 6)
	stroke(tb, 1, "line")
	N("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tb)
	tb.FocusLost:Connect(function() cb(tb.Text) end)
	return tb
end

-- hold-style key / mouse button picker stored in cfg[key]
function TM.keybind(self, text, key, cb)
	local f = self:row(ROW, text)
	lbl(f, text, 128)
	local b = keycap(f, 16, "", 64)
	local function paint()
		b.Text = bindName(cfg[key])
		b.TextColor3 = T.sub
	end
	b.MouseButton1Click:Connect(function()
		b.Text = "Esc cancela"
		UI.capture(function(bind)
			if bind then
				cfg[key] = bind
				UI.changed()
				if cb then cb(bind) end
			end
			paint()
		end)
	end)
	UI.refreshers[#UI.refreshers + 1] = paint
	UI.painters[#UI.painters + 1] = paint
	paint()
end

-- read-only text card; returns a setter
function TM.info(self, text)
	local f = self:row(40, text)
	local l = N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, f, { TextColor3 = "sub" })
	return function(t) l.Text = t end
end

-- title + short list of lines (changelog style)
function TM.notes(self, title, lines)
	local f = self:row(48 + #lines * 24, title)
	N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 20),
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, f, { TextColor3 = "text" })
	for i, line in ipairs(lines) do
		N("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 40 + (i - 1) * 24),
			Size = UDim2.new(1, -32, 0, 20),
			Text = "•  " .. line,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, f, { TextColor3 = "sub" })
	end
end

-- name / logo / version card (name comes from cfg.credit)
function TM.credits(self)
	local f = self:row(88, "créditos creditos nombre versión")
	local mark = N("TextLabel", {
		Position = UDim2.fromOffset(16, 22),
		Size = UDim2.fromOffset(44, 44),
		Text = "H",
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(17, 19, 23),
		BorderSizePixel = 0,
	}, f, { BackgroundColor3 = "accent" })
	corner(mark, 8)
	UI.creditLbl = N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(76, 20),
		Size = UDim2.new(1, -92, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, f, { TextColor3 = "text" })
	N("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(76, 48),
		Size = UDim2.new(1, -92, 0, 16),
		Text = "Universal Hub  ·  v2.5 · build 118",
		Font = Enum.Font.RobotoMono,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, f, { TextColor3 = "faint" })
	function UI.paintCredit()
		UI.creditLbl.Text = cfg.credit
	end
	UI.refreshers[#UI.refreshers + 1] = UI.paintCredit
	UI.paintCredit()
end

----------------------------------------------------------------------
-- combat: targeting, aimbot, silent aim, triggerbot
----------------------------------------------------------------------
F.rayParams = RaycastParams.new()
F.rayParams.FilterType = Enum.RaycastFilterType.Exclude
F.rayParams.IgnoreWater = true

function F.enemy(plr)
	if plr == lp then return false end
	if cfg.teamCheck and plr.Team ~= nil and plr.Team == lp.Team then return false end
	return true
end

-- clear line from the camera to the part? see-through / non-solid parts are traced through
function F.visible(cam, part)
	local origin = cam.CFrame.Position
	local ignore = { cam }
	if lp.Character then ignore[#ignore + 1] = lp.Character end
	for _ = 1, 10 do
		F.rayParams.FilterDescendantsInstances = ignore
		local res = workspace:Raycast(origin, part.Position - origin, F.rayParams)
		if not res then return true end
		local hit = res.Instance
		if hit:IsDescendantOf(part.Parent) then return true end
		if hit.Transparency >= 0.9 or not hit.CanCollide then
			ignore[#ignore + 1] = hit
		else
			return false
		end
	end
	return false
end

-- names games use for spawn protection / safe zones / god mode (attributes and Bool/Number values)
local FLAGS = { "forcefield", "invinc", "invuln", "godmode", "spawnprotect", "safezone", "insafe", "protected", "immune", "untouchable" }
local function flagged(name)
	name = name:lower()
	for _, f in ipairs(FLAGS) do
		if name:find(f, 1, true) then return true end
	end
	return false
end

-- protected = has a ForceField, infinite health, or carries a protection flag; those shots do nothing
function F.protected(char, hum)
	if char:FindFirstChildOfClass("ForceField") then return true end
	if hum.Health == math.huge or hum.MaxHealth == math.huge or hum.MaxHealth >= 1e6 then return true end
	for _, inst in ipairs({ char, hum }) do
		for name, v in pairs(inst:GetAttributes()) do
			if (v == true or (type(v) == "number" and v > 0)) and flagged(name) then return true end
		end
	end
	for _, c in ipairs(char:GetChildren()) do
		if flagged(c.Name) then
			if c:IsA("BoolValue") and c.Value then return true end
			if c:IsA("NumberValue") and c.Value > 0 then return true end
		end
	end
	return false
end

function F.isProtected(char, hum) -- cached for a quarter second, it runs for every player each frame
	local c = S.protCache[char]
	local now = tick()
	if c and now - c[1] < 0.25 then return c[2] end
	local v = F.protected(char, hum)
	S.protCache[char] = { now, v }
	return v
end

function F.pickPart(plr, char)
	local mode = cfg.aimPart
	if mode == "Random" then
		mode = S.rolls[plr]
		if not mode then
			mode = (math.random(2) == 1) and "Head" or "Torso"
			S.rolls[plr] = mode
		end
	end
	if mode == "Head" then
		return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	end
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
end

-- where to aim: current position pushed forward by velocity * prediction time
function F.aimPos(part)
	return part.Position + part.AssemblyLinearVelocity * (cfg.prediction / 1000)
end

-- returns part, score (lower = better), aimPosition when plr is a valid target right now
function F.candidate(plr, cam, mouse, best)
	if not F.enemy(plr) then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if cfg.aliveCheck and hum.Health <= 0 then return end
	if cfg.ffCheck and F.isProtected(char, hum) then return end
	local part = F.pickPart(plr, char)
	if not part then return end
	local pos = F.aimPos(part)
	local sp, onScreen = cam:WorldToViewportPoint(pos)
	if not onScreen then return end
	local pix = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
	if pix > cfg.fov then return end
	local score = pix
	if cfg.priority == "Distance" then
		score = (pos - cam.CFrame.Position).Magnitude
	elseif cfg.priority == "Health" then
		score = hum.Health
	end
	if best and score >= best then return end
	if cfg.wallCheck and not F.visible(cam, part) then return end
	return part, score, pos
end

-- lockKey ("lock" / "slock") keeps the current target until it stops being valid
function F.findTarget(cam, lockKey)
	local mouse = UIS:GetMouseLocation()
	if S[lockKey] then
		local part, _, pos = F.candidate(S[lockKey], cam, mouse)
		if part then return part, pos end
		S[lockKey] = nil
	end
	local bestPart, bestPos, bestScore, bestPlr
	for _, plr in ipairs(Players:GetPlayers()) do
		local part, score, pos = F.candidate(plr, cam, mouse, bestScore)
		if part then
			bestPart, bestScore, bestPos, bestPlr = part, score, pos, plr
		end
	end
	S[lockKey] = bestPlr
	return bestPart, bestPos
end

S.remX, S.remY = 0, 0

function F.aim(cam, dt)
	if not (cfg.aimbot and S.aimHeld) then
		S.lock = nil
		return
	end
	local part, pos = F.findTarget(cam, "lock")
	if not part then return end
	-- frame-rate independent smoothing: 1 = snap, higher = slower
	local alpha = 1 - (1 - 1 / math.max(cfg.smooth, 1)) ^ (dt * 60)
	if cfg.aimMethod == "Mouse" and has.mouseMove then
		local sp = cam:WorldToViewportPoint(pos)
		local m = UIS:GetMouseLocation()
		-- mouse moves are whole pixels: carry the fraction so slow speeds still converge
		local dx = (sp.X - m.X) * alpha + S.remX
		local dy = (sp.Y - m.Y) * alpha + S.remY
		local ix, iy = math.round(dx), math.round(dy)
		S.remX, S.remY = dx - ix, dy - iy
		if ix ~= 0 or iy ~= 0 then mousemoverel(ix, iy) end
	else
		local origin = cam.CFrame.Position
		cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(origin, pos), alpha)
	end
end

-- silent aim: the game keeps seeing your normal camera, but mouse.Hit / mouse.Target and
-- Raycast / FindPartOnRay calls made by game scripts are pointed at the target.
-- Hooks are installed once per executor session and only act while G.enabled is true.
function F.installHooks()
	if genv.__UA_G then return true end
	if not has.hook then return false end
	local G = { enabled = false, target = nil, aimPos = nil }
	genv.__UA_G = G
	local mouse = lp:GetMouse()
	local oldIndex, oldNamecall

	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
		if G.enabled and G.aimPos and self == mouse and not checkcaller() then
			if key == "Hit" then return CFrame.new(G.aimPos) end
			if key == "Target" then return G.target end
		end
		return oldIndex(self, key)
	end))

	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		if G.enabled and G.aimPos and self == workspace and not checkcaller() then
			local method = getnamecallmethod()
			local args = table.pack(...)
			if method == "Raycast" and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
				args[2] = (G.aimPos - args[1]).Unit * args[2].Magnitude
				return oldNamecall(self, table.unpack(args, 1, args.n))
			elseif (method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist")
				and typeof(args[1]) == "Ray" then
				local r = args[1]
				args[1] = Ray.new(r.Origin, (G.aimPos - r.Origin).Unit * r.Direction.Magnitude)
				return oldNamecall(self, table.unpack(args, 1, args.n))
			end
		end
		return oldNamecall(self, ...)
	end))
	return true
end

function F.silent(cam)
	local G = genv.__UA_G
	if cfg.silentAim then
		if not G then
			if not F.installHooks() then
				cfg.silentAim = false
				UI.notify("Silent aim: tu executor no tiene hooks")
				UI.refresh()
				return
			end
			G = genv.__UA_G
		end
		local part, pos = F.findTarget(cam, "slock")
		G.enabled = part ~= nil
		G.target, G.aimPos = part, pos
	elseif G then
		G.enabled = false
	end
end

-- triggerbot: click when the crosshair (cursor) is on a valid enemy; walls block it naturally
function F.trigger(cam)
	if not cfg.trigger then return end
	if not has.click then
		cfg.trigger = false
		UI.notify("Triggerbot: tu executor no tiene mouse1click")
		UI.refresh()
		return
	end
	if tick() - S.lastClick < cfg.triggerDelay / 1000 then return end
	local m = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	F.rayParams.FilterDescendantsInstances = { lp.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, F.rayParams)
	if not res then return end
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	local plr = model and Players:GetPlayerFromCharacter(model)
	if not (plr and F.enemy(plr)) then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and (hum.Health > 0 or not cfg.aliveCheck) and not (cfg.ffCheck and F.isProtected(model, hum)) then
		mouse1click()
		S.lastClick = tick()
	end
end

----------------------------------------------------------------------
-- visuals: boxes, names, distance, health, tracers, skeleton (Drawing) + chams (Highlight)
----------------------------------------------------------------------
F.SKEL15 = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
F.SKEL6 = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

function F.mk(class, props)
	local d = Drawing.new(class)
	for k, v in pairs(props) do d[k] = v end
	return d
end

function F.makeESP()
	local d = { all = {}, bones = {} }
	function d.add(o)
		d.all[#d.all + 1] = o
		return o
	end
	d.box = d.add(F.mk("Square", { Thickness = 1, Filled = false, Visible = false }))
	d.name = d.add(F.mk("Text", { Size = 13, Center = true, Outline = true, Visible = false }))
	d.dist = d.add(F.mk("Text", { Size = 12, Center = true, Outline = true, Visible = false }))
	d.hpBack = d.add(F.mk("Line", { Thickness = 4, Color = Color3.new(0, 0, 0), Visible = false }))
	d.hp = d.add(F.mk("Line", { Thickness = 2, Visible = false }))
	d.tracer = d.add(F.mk("Line", { Thickness = 1, Visible = false }))
	return d
end

function F.hideESP(d)
	for _, o in ipairs(d.all) do o.Visible = false end
	if d.hl then
		d.hl:Destroy()
		d.hl = nil
	end
end

function F.freeESP(plr)
	local d = S.esp[plr]
	if not d then return end
	for _, o in ipairs(d.all) do
		pcall(function() o:Remove() end)
	end
	if d.hl then d.hl:Destroy() end
	S.esp[plr] = nil
end

function F.esp(cam)
	local vp = cam.ViewportSize
	local mouse = UIS:GetMouseLocation()
	local camPos = cam.CFrame.Position
	local anyDraw = has.drawing and (cfg.espBox or cfg.espName or cfg.espDist or cfg.espHealth or cfg.espTracer or cfg.espSkeleton)

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local dist = root and (root.Position - camPos).Magnitude
			local show = hum and root and hum.Health > 0 and F.enemy(plr) and dist <= cfg.espRange and (anyDraw or cfg.chams)
			local d = S.esp[plr]

			if not show then
				if d then F.hideESP(d) end
			else
				if not d then
					d = has.drawing and F.makeESP() or { all = {}, bones = {} }
					S.esp[plr] = d
				end
				local color = (cfg.teamColors and plr.Team) and plr.TeamColor.Color or col(cfg.enemyColor)

				-- chams
				if cfg.chams then
					if not d.hl or d.hl.Parent == nil or d.hl.Adornee ~= char then
						if d.hl then d.hl:Destroy() end
						d.hl = N("Highlight", {
							DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
							OutlineTransparency = 0,
							Adornee = char,
						}, S.hlInGui and gui or char)
					end
					d.hl.FillColor = color
					d.hl.OutlineColor = Color3.new(1, 1, 1)
					d.hl.FillTransparency = 1 - cfg.chamsFill / 100
				elseif d.hl then
					d.hl:Destroy()
					d.hl = nil
				end

				-- drawn esp
				if anyDraw then
					local top = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
					local bot = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
					if top.Z <= 0 or bot.Z <= 0 then
						for _, o in ipairs(d.all) do o.Visible = false end
					else
						local h = math.abs(bot.Y - top.Y)
						local w = h * 0.55
						local cx = (top.X + bot.X) / 2
						local x, y = cx - w / 2, top.Y

						d.box.Visible = cfg.espBox
						if cfg.espBox then
							d.box.Size = Vector2.new(w, h)
							d.box.Position = Vector2.new(x, y)
							d.box.Color = color
						end

						d.name.Visible = cfg.espName
						if cfg.espName then
							d.name.Text = plr.DisplayName
							d.name.Position = Vector2.new(cx, y - 16)
							d.name.Color = color
						end

						d.dist.Visible = cfg.espDist
						if cfg.espDist then
							d.dist.Text = "[" .. math.floor(dist) .. "m]"
							d.dist.Position = Vector2.new(cx, y + h + 2)
							d.dist.Color = Color3.new(1, 1, 1)
						end

						d.hpBack.Visible, d.hp.Visible = cfg.espHealth, cfg.espHealth
						if cfg.espHealth then
							local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
							d.hpBack.From, d.hpBack.To = Vector2.new(x - 5, y + h + 1), Vector2.new(x - 5, y - 1)
							d.hp.From, d.hp.To = Vector2.new(x - 5, y + h), Vector2.new(x - 5, y + h - h * frac)
							d.hp.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), frac)
						end

						d.tracer.Visible = cfg.espTracer
						if cfg.espTracer then
							local from = Vector2.new(vp.X / 2, vp.Y)
							if cfg.tracerFrom == "Center" then
								from = Vector2.new(vp.X / 2, vp.Y / 2)
							elseif cfg.tracerFrom == "Mouse" then
								from = mouse
							end
							d.tracer.From, d.tracer.To = from, Vector2.new(cx, y + h)
							d.tracer.Color = color
						end

						if cfg.espSkeleton then
							if #d.bones == 0 then
								for i = 1, 14 do
									d.bones[i] = d.add(F.mk("Line", { Thickness = 1, Visible = false }))
								end
							end
							local pairsList = char:FindFirstChild("UpperTorso") and F.SKEL15 or F.SKEL6
							for i, line in ipairs(d.bones) do
								local pr = pairsList[i]
								local p1 = pr and char:FindFirstChild(pr[1])
								local p2 = pr and char:FindFirstChild(pr[2])
								line.Visible = false
								if p1 and p2 then
									local a = cam:WorldToViewportPoint(p1.Position)
									local b = cam:WorldToViewportPoint(p2.Position)
									if a.Z > 0 and b.Z > 0 then
										line.From, line.To = Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y)
										line.Color = color
										line.Visible = true
									end
								end
							end
						else
							for _, line in ipairs(d.bones) do line.Visible = false end
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- player: walkspeed, jump, fly, noclip, infinite jump, anti-afk
----------------------------------------------------------------------
function F.player()
	local char = lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local o = S.orig
	if o.hum ~= hum then -- new character: remember its stock values before touching anything
		o.hum, o.ws, o.jp, o.ujp = hum, hum.WalkSpeed, hum.JumpPower, hum.UseJumpPower
	end
	if cfg.speed then
		hum.WalkSpeed = cfg.walkspeed
	elseif S.speedOn then
		hum.WalkSpeed = o.ws
	end
	S.speedOn = cfg.speed
	if cfg.jump then
		hum.UseJumpPower = true
		hum.JumpPower = cfg.jumppower
	elseif S.jumpOn then
		hum.UseJumpPower = o.ujp
		hum.JumpPower = o.jp
	end
	S.jumpOn = cfg.jump
end

function F.noclip()
	local char = lp.Character
	if cfg.noclip and char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				S.nc[p] = true
				p.CanCollide = false
			end
		end
	elseif next(S.nc) then
		for p in pairs(S.nc) do
			if p.Parent then p.CanCollide = true end
		end
		S.nc = {}
	end
end

function F.flyClean()
	if S.fv then S.fv:Destroy() S.fv = nil end
	if S.fg then S.fg:Destroy() S.fg = nil end
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	if hum and S.flying then hum.PlatformStand = false end
	S.flying = false
end

function F.fly(cam)
	local char = lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (cfg.fly and hrp and hum) then
		if S.flying or S.fv then F.flyClean() end
		return
	end
	if not S.fv or S.fv.Parent ~= hrp then
		F.flyClean()
		S.fv = N("BodyVelocity", { MaxForce = Vector3.new(1e9, 1e9, 1e9), Velocity = Vector3.new() }, hrp)
		S.fg = N("BodyGyro", { MaxTorque = Vector3.new(1e9, 1e9, 1e9), P = 9e4, CFrame = cam.CFrame }, hrp)
		S.flying = true
	end
	hum.PlatformStand = true
	local d = Vector3.new()
	local cf = cam.CFrame
	if not UIS:GetFocusedTextBox() then
		if UIS:IsKeyDown(Enum.KeyCode.W) then d = d + cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then d = d - cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then d = d + cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then d = d - cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then d = d + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then d = d - Vector3.new(0, 1, 0) end
	end
	S.fv.Velocity = d.Magnitude > 0 and d.Unit * cfg.flyspeed or Vector3.new()
	S.fg.CFrame = cf
end
----------------------------------------------------------------------
-- Prison Life ragebot (engine shared with the standalone script; UI lives in the Rage tab)
----------------------------------------------------------------------
F.rage = {}
do
local R = F.rage
local function notify(a, b) UI.notify(a, b) end
R.capturing = function() return S.capture ~= nil end
----------------------------------------------------------------------
-- Prison Life ragebot engine (shared by the hub's Rage tab and the standalone script)
-- The wrapper provides: cfg, lp, Players, RunService, UIS, genv, has, on, notify, R
-- Shots go straight to ReplicatedStorage.ShootEvent, so the camera never moves.
----------------------------------------------------------------------
local RS = game:GetService("ReplicatedStorage")

local rayP = RaycastParams.new()
rayP.FilterType = Enum.RaycastFilterType.Exclude
rayP.IgnoreWater = true

local ST = {
	last = 0, lastMelee = 0, lastEquip = 0, lastGive = 0,
	angle = 0, yaw = 0, cycle = 0, fast = false,
	pending = {},
	states = setmetatable({}, { __mode = "k" }),
	rate0 = setmetatable({}, { __mode = "k" }),
	friends = {},
}
R.stats = { shots = 0, hits = 0 }
R.cat = { wall = { n = 0, h = 0 }, spoof = { n = 0, h = 0 }, rapid = { n = 0, h = 0 }, multi = { n = 0, h = 0 } }
R.held = false
R.active = false
R.capturing = R.capturing or function() return false end

local CAT_NAME = { wall = "pared", spoof = "origen", rapid = "rapid", multi = "multi" }
local HINTS = {
	wall = "El server parece validar la línea de vista. Apaga Wallbang",
	spoof = "El server parece validar el origen del disparo. Pon Origen en Real",
	rapid = "El server parece limitar la cadencia. Apaga Rapid fire",
	multi = "El server parece ignorar los impactos extra. Apaga Multi-hit",
}

----------------------------------------------------------------------
-- remote
----------------------------------------------------------------------
function R.remote()
	local sch = R.schema
	if sch and sch.remote and sch.remote.Parent then return sch.remote end
	local r = ST.remote
	if r and r.Parent then return r end
	r = RS:FindFirstChild("ShootEvent")
	ST.remote = r
	return r
end

----------------------------------------------------------------------
-- targeting
----------------------------------------------------------------------
local GROUPS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
	Legs = { "LowerTorso", "Left Leg", "Right Leg", "LeftUpperLeg", "RightUpperLeg" },
}
local ROLL = { "Head", "Torso", "Legs" }

local function findPart(char, g)
	for _, n in ipairs(GROUPS[g]) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then return p end
	end
end

-- clear line from origin to the part? see-through / non-solid parts are traced through
local function los(origin, part)
	local ignore = { lp.Character }
	for _ = 1, 8 do
		rayP.FilterDescendantsInstances = ignore
		local res = workspace:Raycast(origin, part.Position - origin, rayP)
		if not res then return true end
		local hit = res.Instance
		if hit:IsDescendantOf(part.Parent) then return true end
		if hit.Transparency >= 0.9 or not hit.CanCollide then
			ignore[#ignore + 1] = hit
		else
			return false
		end
	end
	return false
end

local function protected(char, hum)
	if char:FindFirstChildOfClass("ForceField") then return true end
	return hum.Health == math.huge or hum.MaxHealth >= 1e6
end

local function isFriend(plr)
	local v = ST.friends[plr.UserId]
	if v == nil then
		ST.friends[plr.UserId] = false
		task.spawn(function()
			local ok, r = pcall(function() return lp:IsFriendsWith(plr.UserId) end)
			ST.friends[plr.UserId] = ok and r == true
		end)
		return false
	end
	return v
end

local function teamOk(plr)
	local t = plr.Team
	if t and t.Name == "Spectators" then return false end
	if cfg.rgTeamCheck and t ~= nil and t == lp.Team then return false end
	if cfg.rgTeamFilter ~= "All" and not (t and t.Name == cfg.rgTeamFilter) then return false end
	return true
end

-- returns part, hasClearLine (part is nil when nothing can be shot)
local function choosePart(char, origin)
	local g = cfg.rgHitbox
	if g == "Random" then g = ROLL[math.random(#ROLL)] end
	local part = findPart(char, g) or findPart(char, "Torso")
	if not part then return nil end
	local vis = los(origin, part)
	if vis or cfg.rgWall then return part, vis end
	if cfg.rgFallback then
		for _, name in ipairs(ROLL) do
			if name ~= g then
				local p = findPart(char, name)
				if p and los(origin, p) then return p, true end
			end
		end
	end
	return nil
end

local function collect(cam, origin)
	local list = {}
	local mouse = UIS:GetMouseLocation()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and teamOk(plr) and not (cfg.rgFriends and isFriend(plr)) then
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not (cfg.rgFFCheck and protected(char, hum)) then
				local part, vis = choosePart(char, origin)
				if part then
					local dist = (part.Position - origin).Magnitude
					if dist <= cfg.rgMaxDist then
						local score, ok = dist, true
						if cfg.rgPriority == "Health" then score = hum.Health end
						if cfg.rgFovOn or cfg.rgPriority == "Cursor" then
							local sp, onScr = cam:WorldToViewportPoint(part.Position)
							local pix = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
							if cfg.rgFovOn and (not onScr or pix > cfg.rgFov) then ok = false end
							if cfg.rgPriority == "Cursor" then score = onScr and pix or 1e6 end
						end
						if ok then
							list[#list + 1] = { plr = plr, hum = hum, part = part, vis = vis, score = score }
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.score < b.score end)
	return list
end

local function pickTargets(list)
	local mode = cfg.rgTargets
	if mode == "Single" or #list == 1 then return { list[1] } end
	if mode == "Cycle" then
		ST.cycle = (ST.cycle % #list) + 1
		return { list[ST.cycle] }
	end
	local out = {}
	for i = 1, math.min(#list, cfg.rgMaxTargets) do out[i] = list[i] end
	return out
end

----------------------------------------------------------------------
-- guns
----------------------------------------------------------------------
local PREF = { ["AK-47"] = 1, ["Remington 870"] = 2, ["M9"] = 3 }
local ARMORY = { "AK-47", "Remington 870", "M9" }

local function backpack() return lp:FindFirstChild("Backpack") end

local function isGun(t)
	return t:IsA("Tool") and t:FindFirstChild("GunStates") ~= nil and not t.Name:lower():find("taser", 1, true)
end

local function pickGun(container)
	local want, best, rank = cfg.rgGun, nil, 1e9
	if not container then return nil end
	for _, t in ipairs(container:GetChildren()) do
		if isGun(t) then
			if want ~= "Auto" and t.Name == want then return t end
			local r = PREF[t.Name] or 50
			if want == "Auto" and r < rank then best, rank = t, r end
		end
	end
	return best
end

local function gunStates(tool)
	local s = ST.states[tool]
	if s == nil then
		local ok, r = pcall(function() return require(tool:FindFirstChild("GunStates")) end)
		s = (ok and type(r) == "table") and r or false
		ST.states[tool] = s
	end
	return s or {}
end

local function currentGun(char, hum, now)
	local held = char:FindFirstChildOfClass("Tool")
	local heldGun = held and isGun(held) and held or nil
	if heldGun and (cfg.rgGun == "Auto" or heldGun.Name == cfg.rgGun) then return heldGun end
	if not cfg.rgAutoEquip then return heldGun end
	if now - ST.lastEquip < 0.35 then return nil end
	local pick = pickGun(backpack())
	if pick then
		ST.lastEquip = now
		hum:EquipTool(pick) -- the shot goes out next tick, once the tool is in the hand
		return nil
	end
	return heldGun
end

local function hasTool(name)
	local bp = backpack()
	return (bp ~= nil and bp:FindFirstChild(name) ~= nil) or (lp.Character ~= nil and lp.Character:FindFirstChild(name) ~= nil)
end

-- workspace.Remote.ItemHandler:InvokeServer(Prison_ITEMS.giver[gun].ITEMPICKUP)
local function giveGuns(now)
	if ST.giving or now - ST.lastGive < 2.5 then return end
	local items = workspace:FindFirstChild("Prison_ITEMS")
	local giver = items and items:FindFirstChild("giver")
	local remotes = workspace:FindFirstChild("Remote")
	local handler = remotes and remotes:FindFirstChild("ItemHandler")
	if not (giver and handler) then return end
	local missing = {}
	for _, name in ipairs(ARMORY) do
		if (cfg.rgGun == "Auto" or cfg.rgGun == name) and not hasTool(name) then
			local gun = giver:FindFirstChild(name)
			local pad = gun and gun:FindFirstChild("ITEMPICKUP")
			if pad then missing[#missing + 1] = pad end
		end
	end
	if #missing == 0 then return end
	ST.lastGive, ST.giving = now, true
	task.spawn(function()
		for _, pad in ipairs(missing) do pcall(function() handler:InvokeServer(pad) end) end
		ST.giving = false
	end)
end

-- only touches fields that exist, so a renamed field is skipped instead of invented
local function applyMods(tool, s)
	pcall(function()
		if cfg.rgInfAmmo then
			for _, k in ipairs({ "MaxAmmo", "CurrentAmmo", "StoredAmmo" }) do
				if s[k] ~= nil and s[k] ~= math.huge then s[k] = math.huge end
			end
		end
		if s.FireRate ~= nil and ST.rate0[tool] == nil then ST.rate0[tool] = s.FireRate end
		if cfg.rgGunMods then
			if s.SpreadRadius ~= nil and s.SpreadRadius ~= 0 then s.SpreadRadius = 0 end
			if s.AutoFire ~= nil and s.AutoFire ~= true then s.AutoFire = true end
			local base = ST.rate0[tool]
			if base then
				local want = cfg.rgRapid and (1 / math.max(cfg.rgRate, 1)) or base
				if s.FireRate ~= want then s.FireRate = want end
			end
		end
	end)
end

----------------------------------------------------------------------
-- shot payload: ShootEvent:FireServer({ {RayObject, Distance, Cframe, Hit}, ... }, tool)
-- once a real shot has been learned, its field names / argument order are copied instead
----------------------------------------------------------------------
local function aimPoint(t)
	local p = t.part.Position
	if cfg.rgPredict > 0 then p = p + t.part.AssemblyLinearVelocity * (cfg.rgPredict / 1000) end
	return p
end

-- ray origin glued to the target: first free side, so a server that checks the line still sees it clear
local function spoofOrigin(part)
	local c, d = part.Position, cfg.rgSpoofDist
	local offs = {
		Vector3.new(0, d, 0), Vector3.new(d, 0, 0), Vector3.new(-d, 0, 0),
		Vector3.new(0, 0, d), Vector3.new(0, 0, -d), Vector3.new(0, -d, 0),
	}
	for _, o in ipairs(offs) do
		if los(c + o, part) then return c + o end
	end
	return c + offs[1]
end

local function makeEntry(sample, origin, aim, part)
	local dir = aim - origin
	if not sample then
		return { RayObject = Ray.new(origin, dir), Distance = dir.Magnitude, Cframe = CFrame.new(origin, aim), Hit = part }
	end
	local e = {}
	for k, v in pairs(sample) do
		local tv, kn = typeof(v), tostring(k):lower()
		if tv == "Ray" then
			e[k] = Ray.new(origin, dir)
		elseif tv == "CFrame" then
			e[k] = CFrame.new(origin, aim)
		elseif tv == "Instance" then
			e[k] = part
		elseif tv == "number" and (kn:find("dist") or kn:find("range") or kn:find("len")) then
			e[k] = dir.Magnitude
		elseif tv == "Vector3" then
			e[k] = kn:find("dir") and dir.Unit or (kn:find("orig") and origin or aim)
		else
			e[k] = v
		end
	end
	return e
end

local function entriesFor(sample, g)
	local list = {}
	for _, e in ipairs(g) do
		for _ = 1, e.pellets do list[#list + 1] = makeEntry(sample, e.origin, e.aim, e.part) end
	end
	return list
end

local function buildArgs(tool, g)
	local sch = R.schema
	if not sch then return { entriesFor(nil, g), tool }, 2 end
	local args = {}
	for i = 1, sch.n do
		local v = sch[i]
		if i == 1 and type(v) == "table" then
			args[i] = entriesFor(v[1], g)
		elseif typeof(v) == "Instance" and v.ClassName == "Tool" then
			args[i] = tool
		else
			args[i] = v
		end
	end
	return args, sch.n
end

----------------------------------------------------------------------
-- feedback: did the target actually lose health after our shot?
----------------------------------------------------------------------
local function track(e, multi, spoofed)
	if #ST.pending > 60 then table.remove(ST.pending, 1) end
	local cats = {}
	if not e.t.vis then cats[#cats + 1] = "wall" end
	if spoofed then cats[#cats + 1] = "spoof" end
	if ST.fast then cats[#cats + 1] = "rapid" end
	if multi then cats[#cats + 1] = "multi" end
	ST.pending[#ST.pending + 1] = { t = tick(), hum = e.t.hum, hp = e.t.hum.Health, cats = cats }
end

local function trackHits(now)
	local p = ST.pending
	for i = #p, 1, -1 do
		local e = p[i]
		local dmg = e.hum.Health < e.hp - 0.01
		if dmg or now - e.t > 0.8 then
			table.remove(p, i)
			if dmg then R.stats.hits = R.stats.hits + 1 end
			for _, name in ipairs(e.cats) do
				local c = R.cat[name]
				c.n = c.n + 1
				if dmg then c.h = c.h + 1 end
				if c.n >= 8 and c.h == 0 and not c.warned then
					c.warned = true
					notify("Ragebot", HINTS[name])
				end
			end
		end
	end
end

function R.resetStats()
	R.stats.shots, R.stats.hits = 0, 0
	for _, c in pairs(R.cat) do c.n, c.h, c.warned = 0, 0, nil end
	ST.pending = {}
end

function R.status()
	local rem = R.remote()
	local s = R.stats
	local pct = s.shots > 0 and math.floor(s.hits / s.shots * 100 + 0.5) or 0
	return string.format("%s · %s · %d tiros · %d con daño (%d%%)",
		rem and rem.Name or "sin ShootEvent", R.schema and "esquema aprendido" or "esquema base", s.shots, s.hits, pct)
end

function R.catStatus()
	local out = {}
	for _, name in ipairs({ "wall", "spoof", "rapid", "multi" }) do
		local c = R.cat[name]
		if c.n > 0 then out[#out + 1] = string.format("%s %d/%d", CAT_NAME[name], c.h, c.n) end
	end
	return #out > 0 and ("Impactos por tipo: " .. table.concat(out, " · ")) or "Impactos por tipo: sin datos todavía"
end

----------------------------------------------------------------------
-- firing
----------------------------------------------------------------------
local function fire(tool, s, picks, head)
	local rem = R.remote()
	if not rem then return end
	local spoofed = cfg.rgOrigin == "Spoof"
	local pellets = math.max(1, math.floor(tonumber(s.Bullets) or 1))
	pellets = math.max(1, math.min(pellets, math.floor(40 / #picks))) -- keep payloads small
	local entries = {}
	for i, t in ipairs(picks) do
		entries[i] = {
			t = t, part = t.part, aim = aimPoint(t), pellets = pellets,
			origin = spoofed and spoofOrigin(t.part) or head.Position,
		}
	end
	local groups = {}
	if cfg.rgMultiHit then
		groups[1] = entries
	else
		for i, e in ipairs(entries) do groups[i] = { e } end
	end
	for _, g in ipairs(groups) do
		local args, n = buildArgs(tool, g)
		local ok = pcall(function() rem:FireServer(table.unpack(args, 1, n)) end)
		if ok then
			R.stats.shots = R.stats.shots + #g
			for _, e in ipairs(g) do track(e, #g > 1, spoofed) end
		end
	end
end

----------------------------------------------------------------------
-- movement: strafe + anti-aim
----------------------------------------------------------------------
local function strafe(t, dt, hrp)
	local c, m, r = t.part.Position, cfg.rgStrafeMode, cfg.rgStrafeR
	local pos
	if m == "Orbit" then
		ST.angle = ST.angle + dt * cfg.rgStrafeSpeed
		pos = Vector3.new(c.X + math.cos(ST.angle) * r, c.Y + cfg.rgStrafeY, c.Z + math.sin(ST.angle) * r)
	elseif m == "Jitter" then
		local a = math.random() * math.pi * 2
		pos = Vector3.new(c.X + math.cos(a) * r, c.Y + cfg.rgStrafeY, c.Z + math.sin(a) * r)
	else -- Behind: opposite to where the target is facing
		local look = t.part.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
		pos = c - flat.Unit * r + Vector3.new(0, cfg.rgStrafeY, 0)
	end
	hrp.CFrame = CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

local function antiAim(dt, hrp, hum, t)
	local m = cfg.rgAntiAim
	if m == "Off" then return end
	hum.AutoRotate = false
	ST.noRotate = true
	local pos = hrp.Position
	if m == "Away" and t then
		local c = t.part.Position
		hrp.CFrame = CFrame.lookAt(pos, Vector3.new(2 * pos.X - c.X, pos.Y, 2 * pos.Z - c.Z))
		return
	end
	if m == "Spin" then
		ST.yaw = ST.yaw + dt * cfg.rgSpin
	else
		ST.yaw = math.random() * math.pi * 2
	end
	hrp.CFrame = CFrame.new(pos) * CFrame.Angles(0, ST.yaw, 0)
end

-- meleeEvent:FireServer(player), repeated a few times per target
local function melee(now, hrp)
	if now - ST.lastMelee < 0.12 then return end
	local ev = RS:FindFirstChild("meleeEvent")
	if not ev then return end
	ST.lastMelee = now
	local hits = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and teamOk(plr) and not (cfg.rgFriends and isFriend(plr)) then
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and not (cfg.rgFFCheck and protected(char, hum))
				and (root.Position - hrp.Position).Magnitude <= cfg.rgMeleeRange then
				for _ = 1, cfg.rgMeleeHits do ev:FireServer(plr) end
				hits = hits + 1
				if hits >= 3 then return end
			end
		end
	end
end

----------------------------------------------------------------------
-- main step
----------------------------------------------------------------------
function R.restore()
	R.active = false
	if ST.noRotate then
		ST.noRotate = false
		local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = true end
	end
end

function R.step(dt)
	if not cfg.rgOn then
		if R.active then R.restore() end
		return
	end
	local char = lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not (hum and hrp and head) or hum.Health <= 0 then return end
	local now = tick()

	if R.learning and now - ST.learnT > 20 then
		R.learning = false
		notify("Ragebot", "Tiempo agotado: no vi ningún disparo")
	end
	trackHits(now)
	if cfg.rgAutoGuns then giveGuns(now) end
	if cfg.rgMelee then melee(now, hrp) end

	if cfg.rgActivate == "Hold" and not R.held then
		if R.active then R.restore() end
		return
	end
	R.active = true

	local cam = workspace.CurrentCamera
	local list = collect(cam, head.Position)
	local primary = list[1]
	if cfg.rgStrafe and primary then strafe(primary, dt, hrp) end
	if cfg.rgAntiAim ~= "Off" then
		antiAim(dt, hrp, hum, primary)
	elseif ST.noRotate then
		hum.AutoRotate = true
		ST.noRotate = false
	end
	if not primary then return end

	local tool = currentGun(char, hum, now)
	if not tool then return end
	local s = gunStates(tool)
	applyMods(tool, s)

	local base = ST.rate0[tool] or tonumber(s.FireRate) or 0.1
	local interval = cfg.rgRapid and (1 / math.max(cfg.rgRate, 1)) or base
	if now - ST.last < interval then return end
	ST.last = now
	ST.fast = cfg.rgRapid and interval < base * 0.95

	local picks = pickTargets(list)
	for _ = 1, (cfg.rgRapid and cfg.rgBurst or 1) do
		fire(tool, s, picks, head)
	end
end

----------------------------------------------------------------------
-- learn a real shot: hook the next FireServer that carries a hit table + your tool,
-- and copy its remote, argument order and field names (survives game updates)
----------------------------------------------------------------------
function R.onLearn(remote, args)
	local first = args[1]
	local sample = type(first) == "table" and type(first[1]) == "table" and first[1]
	if not sample then return end
	local sch = { n = args.n, remote = remote }
	for i = 1, args.n do sch[i] = args[i] end
	R.schema = sch
	R.learning = false
	local keys = {}
	for k in pairs(sample) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	task.defer(notify, "Disparo aprendido", remote.Name .. " { " .. table.concat(keys, ", ") .. " }")
end

function R.hook()
	if genv.__PL_RG_HOOKED then return true end
	if not has.hook then return false end
	local old
	-- no method calls inside the hook (they would overwrite the namecall method of the call in flight)
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local G = genv.__PL_RG
		if G and G.learning and getnamecallmethod() == "FireServer" and not checkcaller() then
			local args = table.pack(...)
			if type(args[1]) == "table" and typeof(self) == "Instance" and self.ClassName == "RemoteEvent" then
				local hasTool = false
				for i = 2, args.n do
					if typeof(args[i]) == "Instance" and args[i].ClassName == "Tool" then hasTool = true end
				end
				if hasTool then pcall(G.onLearn, self, args) end
			end
		end
		return old(self, ...)
	end))
	genv.__PL_RG_HOOKED = true
	return true
end

function R.learn()
	if not R.hook() then
		notify("Ragebot", "Tu executor no tiene hookmetamethod")
		return false
	end
	genv.__PL_RG = R
	ST.learnT = tick()
	R.learning = true
	notify("Ragebot", "Dispara una vez a mano con tu arma")
	return true
end

function R.forget()
	R.schema, R.learning = nil, false
	notify("Ragebot", "Esquema aprendido borrado")
end

-- prints the held gun's GunStates (names and values) so field names can be checked in the field
function R.dump()
	local char = lp.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not (tool and isGun(tool)) then tool = pickGun(backpack()) end
	if not tool then return notify("GunStates", "No tienes arma") end
	local s = gunStates(tool)
	local keys = {}
	for k in pairs(s) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	if #keys == 0 then return notify("GunStates", tool.Name .. ": no se pudo leer") end
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(s[k]) end
	local text = table.concat(parts, ", ")
	warn("[ragebot] GunStates " .. tool.Name .. ": " .. text)
	notify("GunStates " .. tool.Name, #text > 110 and (text:sub(1, 107) .. "...") or text)
end

function R.unload()
	R.restore()
	R.learning = false
	if genv.__PL_RG == R then genv.__PL_RG = nil end
	for tool, base in pairs(ST.rate0) do
		local s = ST.states[tool]
		if s then pcall(function() s.FireRate = base end) end
	end
end

----------------------------------------------------------------------
-- hold key + frame loop
----------------------------------------------------------------------
local function bindHit(b, input)
	if not b then return false end
	if b.kind == "Key" then
		return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == b.name
	end
	return input.UserInputType.Name == b.name
end

on(UIS.InputBegan, function(input, gpe)
	if gpe or R.capturing() then return end
	if bindHit(cfg.rgHold, input) then R.held = true end
end)
on(UIS.InputEnded, function(input)
	if bindHit(cfg.rgHold, input) then R.held = false end
end)

on(RunService.Heartbeat, function(dt)
	local ok, err = pcall(R.step, dt)
	if not ok and not ST.err then
		ST.err = true
		warn("[ragebot] " .. tostring(err))
	end
end)
end
cfg.rgOn = false -- every session starts with the ragebot off

----------------------------------------------------------------------
-- configs (JSON files in the executor workspace; DIR comes from the core part)
----------------------------------------------------------------------
local function cleanName(n)
	return (n:gsub("[^%w_%-]", ""))
end

function F.cfgSave(name)
	name = cleanName(name)
	if name == "" then return UI.notify("Config", "Escribe un nombre") end
	if not has.files then return UI.notify("Config", "Tu executor no tiene archivos") end
	local ok = pcall(function()
		if not isfolder(DIR) then makefolder(DIR) end
		writefile(DIR .. "/" .. name .. ".json", HttpService:JSONEncode(cfg))
	end)
	if ok then UI.notify("Config guardada", name) else UI.notify("Config", "No se pudo guardar") end
end

function F.cfgLoad(name)
	name = cleanName(name)
	if name == "" then return UI.notify("Config", "Escribe un nombre") end
	if not has.files then return UI.notify("Config", "Tu executor no tiene archivos") end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(DIR .. "/" .. name .. ".json"))
	end)
	if not ok or type(data) ~= "table" then return UI.notify("Config", "No se pudo leer " .. name) end
	F.merge(data)
	S.rolls = {}
	UI.retheme()
	UI.notify("Config cargada", name)
end

function F.cfgList()
	local out = {}
	if has.files then
		pcall(function()
			if isfolder(DIR) then
				for _, p in ipairs(listfiles(DIR)) do
					local n = p:match("([^/\\]+)%.json$")
					if n and n ~= "autosave" then out[#out + 1] = n end
				end
			end
		end)
	end
	return out
end

----------------------------------------------------------------------
-- tabs (rail icons; Ajustes is created first so it sits at the very bottom)
----------------------------------------------------------------------
local general = UI.addTab("General", "target", "Apuntado y chequeos")
local rage = UI.addTab("Rage", "rage", "Ragebot de Prison Life")
local visual = UI.addTab("Visual", "eye", "ESP y chams")
local player = UI.addTab("Jugador", "user", "Movimiento y utilidades")
local themes = UI.addTab("Temas", "mix", "Color de acento y fondo")
local settings = UI.addTab("Ajustes", "tune", "Interfaz y configs", true)
local about = UI.addTab("Info", "info", "Créditos y novedades", true)

general:section("APUNTADO")
general:toggle("Aimbot", "aimbot")
general:keybind("Tecla de apuntado (mantener)", "aimBind")
general:dropdown("Apuntar a", "aimPart", { { "Head", "Cabeza" }, { "Torso", "Torso" }, { "Random", "Aleatorio" } }, function() S.rolls = {} end)
general:dropdown("Prioridad de objetivo", "priority", { { "Cursor", "Cursor" }, { "Distance", "Distancia" }, { "Health", "Vida" } })
general:dropdown("Método de apuntado", "aimMethod", { { "Camera", "Cámara" }, { "Mouse", "Mouse" } })
general:slider("Suavizado (1 = instantáneo)", "smooth", 1, 30)
general:slider("Predicción de movimiento", "prediction", 0, 300, " ms")
general:section("CAMPO DE VISIÓN")
general:slider("Radio del FOV", "fov", 20, 600, " px")
general:toggle("Mostrar círculo FOV", "showFov")
general:color("Color del círculo", "fovColor")
general:section("CHEQUEOS")
general:toggle("Team check", "teamCheck")
general:toggle("Wall check (paredes)", "wallCheck")
general:toggle("Check de vivo", "aliveCheck")
general:toggle("FF check (ForceField / protegidos)", "ffCheck")
general:section("SILENT AIM")
general:toggle("Silent aim", "silentAim")
general:section("TRIGGERBOT")
general:toggle("Triggerbot", "trigger")
general:slider("Delay del trigger", "triggerDelay", 0, 500, " ms")

rage:section("RAGEBOT (PRISON LIFE)")
rage:toggle("Ragebot", "rgOn")
rage:dropdown("Activación", "rgActivate", { { "Always", "Siempre" }, { "Hold", "Mantener tecla" } })
rage:keybind("Tecla (modo mantener)", "rgHold")
local rgStatus = rage:info("...")
local rgCats = rage:info("...")
rage:button("Reiniciar contadores", function() F.rage.resetStats() end)
rage:section("OBJETIVO")
rage:dropdown("Hitbox", "rgHitbox", { { "Head", "Cabeza" }, { "Torso", "Torso" }, { "Legs", "Piernas" }, { "Random", "Aleatorio" } })
rage:toggle("Probar otras partes si no se ve", "rgFallback")
rage:dropdown("Prioridad", "rgPriority", { { "Distance", "Distancia" }, { "Health", "Vida" }, { "Cursor", "Cursor" } })
rage:slider("Distancia máxima", "rgMaxDist", 50, 3000, " studs")
rage:toggle("Limitar al FOV", "rgFovOn")
rage:slider("Radio del FOV", "rgFov", 50, 800, " px")
rage:dropdown("Equipos objetivo", "rgTeamFilter", { { "All", "Todos" }, { "Guards", "Guards" }, { "Inmates", "Inmates" }, { "Criminals", "Criminals" } })
rage:toggle("Team check", "rgTeamCheck")
rage:toggle("FF check (spawn protegido)", "rgFFCheck")
rage:toggle("Ignorar amigos de Roblox", "rgFriends")
rage:slider("Predicción de movimiento", "rgPredict", 0, 300, " ms")
rage:section("DISPARO")
rage:toggle("Wallbang (sin línea de vista)", "rgWall")
rage:dropdown("Origen del disparo", "rgOrigin", { { "Real", "Real (tu cabeza)" }, { "Spoof", "Pegado al objetivo" } })
rage:slider("Distancia del origen falso", "rgSpoofDist", 1, 10, " studs")
rage:dropdown("Objetivos por disparo", "rgTargets", { { "Single", "Uno" }, { "Cycle", "Rotar" }, { "All", "Todos" } })
rage:slider("Máximo de objetivos", "rgMaxTargets", 2, 12)
rage:toggle("Multi-hit (varios en un disparo)", "rgMultiHit")
rage:section("CADENCIA Y ARMA")
rage:toggle("Rapid fire", "rgRapid")
rage:slider("Disparos por segundo", "rgRate", 1, 60)
rage:slider("Ráfaga por tick", "rgBurst", 1, 5)
rage:toggle("Mods de arma (sin spread, autofire)", "rgGunMods")
rage:toggle("Munición infinita", "rgInfAmmo")
rage:toggle("Auto equipar", "rgAutoEquip")
rage:dropdown("Arma", "rgGun", { { "Auto", "Automática" }, { "AK-47", "AK-47" }, { "Remington 870", "Remington 870" }, { "M9", "M9" } })
rage:toggle("Auto armería (pedir armas)", "rgAutoGuns")
rage:button("Ver GunStates del arma", function() F.rage.dump() end)
rage:section("MOVIMIENTO")
rage:toggle("Strafe", "rgStrafe")
rage:dropdown("Tipo de strafe", "rgStrafeMode", { { "Orbit", "Órbita" }, { "Jitter", "Saltos al azar" }, { "Behind", "Detrás" } })
rage:slider("Radio del strafe", "rgStrafeR", 3, 60, " studs")
rage:slider("Velocidad de la órbita", "rgStrafeSpeed", 1, 20)
rage:slider("Altura del strafe", "rgStrafeY", -10, 20, " studs")
rage:dropdown("Anti-aim", "rgAntiAim", { { "Off", "Apagado" }, { "Spin", "Giro" }, { "Jitter", "Temblor" }, { "Away", "De espaldas" } })
rage:slider("Velocidad de giro", "rgSpin", 1, 60)
rage:section("MELEE")
rage:toggle("Melee aura", "rgMelee")
rage:slider("Alcance melee", "rgMeleeRange", 3, 30, " studs")
rage:slider("Golpes por tick", "rgMeleeHits", 1, 6)
rage:section("AJUSTE AUTOMÁTICO")
rage:button("Aprender disparo (dispara 1 vez a mano)", function() F.rage.learn() end)
rage:button("Olvidar disparo aprendido", function() F.rage.forget() end)

visual:section("ESP")
visual:toggle("Cajas", "espBox")
visual:toggle("Nombres", "espName")
visual:toggle("Distancia", "espDist")
visual:toggle("Barras de vida", "espHealth")
visual:toggle("Tracers", "espTracer")
visual:dropdown("Origen de tracers", "tracerFrom", { { "Bottom", "Abajo" }, { "Center", "Centro" }, { "Mouse", "Mouse" } })
visual:toggle("Esqueleto", "espSkeleton")
visual:section("CHAMS")
visual:toggle("Chams", "chams")
visual:slider("Relleno de chams", "chamsFill", 0, 100, " %")
visual:section("COLORES")
visual:toggle("Colores por equipo", "teamColors")
visual:color("Color de enemigo", "enemyColor")
visual:slider("Rango del ESP", "espRange", 100, 5000, " studs")

player:section("MOVIMIENTO")
player:toggle("Velocidad", "speed")
player:slider("Valor de velocidad", "walkspeed", 16, 200)
player:toggle("Salto", "jump")
player:slider("Valor de salto", "jumppower", 50, 300)
player:toggle("Volar (WASD, Espacio sube, Ctrl baja)", "fly")
player:slider("Velocidad de vuelo", "flyspeed", 10, 300)
player:toggle("Noclip", "noclip")
player:toggle("Salto infinito", "infjump")
player:section("UTILIDAD")
player:toggle("Anti-AFK", "antiafk")

themes:section("ACENTO")
themes:presets("Color de acento", "accent", {
	{ "Menta", { 108, 230, 200 } },
	{ "Durazno", { 255, 179, 138 } },
	{ "Azul hielo", { 159, 216, 255 } },
}, function() UI.applyTheme() end)
themes:color("Color personalizado", "accent", function() UI.applyTheme() end)
themes:section("FONDO")
themes:dropdown("Tema", "theme", { { "Dark", "Oscuro" }, { "Light", "Claro" }, { "Midnight", "Medianoche" }, { "Custom", "Personalizado" } }, function() UI.retheme() end)
themes:color("Fondo personalizado", "customBg", function()
	if cfg.theme ~= "Custom" then
		cfg.theme = "Custom"
		UI.refresh()
	end
	UI.applyTheme()
end)

settings:section("INTERFAZ")
settings:keybind("Tecla del menú", "menuBind", function() UI.paintFooter() end)
settings:slider("Transparencia del panel", "opacity", 0, 70, " %", function() UI.applyOpacity() end)
settings:toggle("Notificaciones", "notify", { bind = false })
settings:toggle("Sonidos de interfaz", "sounds", { bind = false })
settings:toggle("Recordar ajustes", "autosave", { bind = false, cb = function(v)
	if v then UI.changed() end
end })
settings:toggle("Modo streamer", "streamer", { bind = false, cb = function(v)
	if v then UI.setOpen(false) end
end })
settings:dropdown("Insignia de rango", "rank", { { "PRO", "PRO" }, { "VIP", "VIP" }, { "ELITE", "ELITE" }, { "", "Ninguna" } }, function() UI.paintRank() end)
local tbCredit = settings:textbox("Nombre en créditos", cfg.credit, function(t)
	cfg.credit = (t ~= "") and t or "Tu nombre"
	UI.paintCredit()
	UI.changed()
end)
UI.refreshers[#UI.refreshers + 1] = function() tbCredit.Text = cfg.credit end
settings:section("CONFIGS")
local cfgName = "default"
settings:textbox("Nombre de config", cfgName, function(t) cfgName = t end)
settings:button("Guardar config", function() F.cfgSave(cfgName) end)
settings:button("Cargar config", function() F.cfgLoad(cfgName) end)
settings:button("Ver configs guardadas", function()
	local l = F.cfgList()
	if #l > 0 then UI.notify("Configs guardadas", table.concat(l, ", ")) else UI.notify("Configs", "No hay configs guardadas") end
end)
settings:section("INFO")
local setGame = settings:info("Juego: ...")
local setStats = settings:info("FPS: ...")
task.spawn(function()
	local ok, info = pcall(function()
		return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
	end)
	setGame("Juego: " .. ((ok and info and info.Name) or "desconocido") .. "  (" .. game.PlaceId .. ")")
end)
settings:section("SCRIPT")
settings:button("Restablecer opciones", function()
	for k, v in pairs(defaults) do cfg[k] = deepcopy(v) end
	S.rolls = {}
	UI.retheme()
	UI.notify("Opciones restablecidas")
end)
settings:button("Descargar script", function()
	if genv.__UA_UNLOAD then genv.__UA_UNLOAD() end
end)

about:section("CRÉDITOS")
about:credits()
about:section("NOVEDADES")
about:notes("Versión 2.6", {
	"Pestaña Rage: ragebot completo para Prison Life",
	"Interfaz nueva: riel de pestañas y tarjeta de jugador",
	"Avatar 3D girando y saludo según la hora",
	"Atajos visibles junto a cada opción",
	"Ajustes recordados entre sesiones",
	"Acento a elegir: menta, durazno o azul hielo",
	"FF check: no apunta a jugadores protegidos",
})

----------------------------------------------------------------------
-- input
----------------------------------------------------------------------
on(UIS.InputBegan, function(input, gpe)
	if S.capture then -- binding a key: next key / mouse button wins, Esc cancels
		local t = input.UserInputType
		local bind
		if t == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Unknown then return end
			if input.KeyCode ~= Enum.KeyCode.Escape then
				bind = { kind = "Key", name = input.KeyCode.Name }
			end
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
			bind = { kind = "Mouse", name = t.Name }
		else
			return
		end
		local cb = S.capture
		S.capture, S.aimHeld = nil, false
		cb(bind)
		return
	end
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F and UI.open and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
		UI.focusSearch()
		return
	end
	if bindMatches(cfg.menuBind, input) then
		UI.setOpen(not UI.open)
	end
	if bindMatches(cfg.aimBind, input) then
		S.aimHeld, S.rolls, S.lock = true, {}, nil
	end
	for key, b in pairs(cfg.binds) do
		if bindMatches(b, input) and UI.toggles[key] then UI.toggles[key]() end
	end
end)

on(UIS.InputEnded, function(input)
	if bindMatches(cfg.aimBind, input) then
		S.aimHeld, S.lock = false, nil
	end
end)

on(UIS.JumpRequest, function()
	if not cfg.infjump then return end
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

on(lp.Idled, function()
	if not cfg.antiafk then return end
	local vu = game:GetService("VirtualUser")
	vu:CaptureController()
	vu:ClickButton2(Vector2.new())
end)

on(UIS.WindowFocusReleased, function()
	if cfg.streamer then UI.setOpen(false) end
end)

on(Players.PlayerRemoving, function(p)
	F.freeESP(p)
	S.rolls[p] = nil
	if S.lock == p then S.lock = nil end
	if S.slock == p then S.slock = nil end
end)

on(RunService.Heartbeat, function() pcall(F.player) end)
on(RunService.Stepped, function() pcall(F.noclip) end)

----------------------------------------------------------------------
-- main loop (right after the default camera so our camera write wins)
----------------------------------------------------------------------
local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not S.errShown then
		S.errShown = true
		warn("[Universal Hub] " .. tostring(err))
	end
end

S.fpsAcc, S.fpsN, S.infoAcc = 0, 0, 0

RunService:BindToRenderStep("UA_main", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end

	local showFov = (cfg.aimbot or cfg.silentAim) and cfg.showFov and not cfg.streamer
	F.fovFrame.Visible = showFov
	if showFov then
		local m = UIS:GetMouseLocation()
		F.fovFrame.Position = UDim2.fromOffset(m.X, m.Y)
		F.fovFrame.Size = UDim2.fromOffset(cfg.fov * 2, cfg.fov * 2)
		F.fovStroke.Color = col(cfg.fovColor)
	end

	safe(F.aim, cam, dt)
	safe(F.silent, cam)
	safe(F.trigger, cam)
	safe(F.esp, cam)
	safe(F.fly, cam)

	-- menu animation helpers
	safe(UI.hoverStep, dt)
	safe(UI.avatarFollow)
	safe(UI.avatarSpin, dt)

	S.fpsAcc, S.fpsN, S.infoAcc = S.fpsAcc + dt, S.fpsN + 1, S.infoAcc + dt
	if S.fpsAcc >= 0.5 then
		local fps = math.floor(S.fpsN / S.fpsAcc + 0.5)
		local ping = UI.ping()
		UI.liveLbl.Text = ping and string.format("%3d FPS  ·  %3d ms", fps, math.floor(ping + 0.5)) or string.format("%3d FPS", fps)
		setStats(string.format("FPS: %d  |  Jugadores: %d", fps, #Players:GetPlayers()))
		if UI.current == "Rage" then
			rgStatus(F.rage.status())
			rgCats(F.rage.catStatus())
		end
		S.fpsAcc, S.fpsN = 0, 0
	end
	if S.infoAcc >= 1 then
		S.infoAcc = 0
		safe(UI.updateInfo)
	end
end)

----------------------------------------------------------------------
-- unload + start
----------------------------------------------------------------------
genv.__UA_UNLOAD = function()
	pcall(F.autosaveNow)
	pcall(F.rage.unload)
	pcall(function() RunService:UnbindFromRenderStep("UA_main") end)
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	if genv.__UA_G then genv.__UA_G.enabled = false end
	cfg.speed, cfg.jump, cfg.fly, cfg.noclip = false, false, false, false
	pcall(F.player)
	pcall(F.noclip)
	pcall(F.flyClean)
	for plr in pairs(S.esp) do F.freeESP(plr) end
	gui:Destroy()
	genv.__UA_UNLOAD = nil
end

UI.selectTab("General", true)
UI.applyOpacity()
if not cfg.streamer then UI.setOpen(true) end
if not has.drawing then
	UI.notify("Sin Drawing", "Cajas y líneas apagadas (chams sí)")
end
print("[Universal Hub] listo | " .. bindName(cfg.menuBind) .. " = menú")
