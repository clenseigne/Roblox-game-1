-- Wild encounters in the brush, presented for the player who triggered them:
--   alert  -> a cartoon "!" speech bubble pops over your head while the camera eases in on you
--   reveal -> white-flash cut to a low, tilted shot of the grass (letterbox, speed lines,
--             vignette, punchier grading, depth of field); the grass rustles, the monster bursts
--             out, lands, roars, and its name card slams in
--   whip   -> a motion-blurred whip-pan to a side view of the two facing off
--   odds   -> a dark studded panel: both pets, a 1-100 meter split at the line (red = lose,
--             green = win), "Roll over N to win  -  X%", and FIGHT (there's no running away)
--   fight  -> the pets clash three times (impact stars, squash, shake) while the needle
--             ping-pongs across the meter, slows and lands on the server's roll
--   win    -> the wild pet spins into sparkles and the aura flies into your bar
--   lose   -> your pet tumbles and poofs home to rest; the wild one hops off into the brush
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Assets)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)
local Pets = require(script.Parent.Pets)
local Puppet = require(script.Parent.Puppet)
local UIStyle = require(script.Parent.UIStyle)

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local WIN = UIStyle.Colors.green
local LOSE = UIStyle.Colors.red
local LEAF = Color3.fromRGB(96, 178, 64)
local GOLD = Color3.fromRGB(255, 216, 74)
local UP = Vector3.yAxis
local CLASH_TIME = 2.6
-- cinematic beats (seconds from the encounter)
local T_CUT, T_BURST, T_LAND, T_WHIP, T_ODDS = 1.1, 1.85, 2.3, 4.05, 4.55

type Fighter = { model: Model?, puppet: any, pet: any?, spot: Vector3, yaw: number, scale: number, squash: any, height: number, centre: Vector3? }

local Battle = {}
local gui: ScreenGui
local flash: Frame
local panel: Frame
local myName: TextLabel
local wildName: TextLabel
local odds: TextLabel
local meter: Frame
local winZone: Frame
local lineMark: Frame
local lineLabel: TextLabel
local needle: Frame
local rollLabel: TextLabel
local fightBtn: TextButton
local fightBox: Frame
local vignette: ImageLabel
local speed: ImageLabel
local barTop: Frame
local barBottom: Frame
local card: Frame
local cardName: TextLabel
local cardLevel: TextLabel
local cardTitle: TextLabel
local cardAura: Frame
local blur: BlurEffect
local grade: ColorCorrectionEffect
local dof: DepthOfFieldEffect
local active: any = nil

-- ---------------------------------------------------------------- ui

local new = UIStyle.new
local label = UIStyle.label

local function build()
	gui = new("ScreenGui", { Name = "Battle", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	flash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ZIndex = 10, Parent = gui })
	-- cinematic layers: vignette, speed lines, letterbox bars and the monster's name card
	vignette = new("ImageLabel", { Name = "Vignette", Image = Config.UI.vignette, BackgroundTransparency = 1, ImageTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = gui })
	speed = new("ImageLabel", { Name = "SpeedLines", Image = Config.UI.speedLines, BackgroundTransparency = 1, ImageTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.15, 1.15), ZIndex = 3, Parent = gui })
	barTop = new("Frame", { Name = "BarTop", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0),
		ZIndex = 8, Parent = gui })
	barBottom = new("Frame", { Name = "BarBottom", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 8, Parent = gui })
	-- name card: studded strip in the monster's color, WILD + aura chips, big name, weight, title
	card = UIStyle.panel({ Name = "Card", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -560, 0.66, 0),
		Size = UDim2.fromOffset(500, 150), ZIndex = 9, Accent = LOSE, Parent = gui })
	UIStyle.chip({ Name = "WildChip", Text = "WILD", Color = LOSE, Position = UDim2.fromOffset(20, 26),
		Size = UDim2.fromOffset(88, 32), ZIndex = 10, Parent = card })
	-- the aura it's wearing, as a chip beside WILD
	cardAura = UIStyle.chip({ Name = "AuraChip", Text = "", Color = GOLD, Position = UDim2.fromOffset(118, 26),
		Size = UDim2.fromOffset(196, 32), ZIndex = 10, Parent = card })
	cardAura.Visible = false
	cardLevel = label({ Name = "Weight", Text = "10 KG", TextColor3 = UIStyle.Colors.money, TextXAlignment = Enum.TextXAlignment.Right, Outline = 3.5,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 24), Size = UDim2.fromOffset(150, 36), ZIndex = 10, Parent = card })
	cardName = label({ Name = "MonsterName", Text = "", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(20, 64),
		Size = UDim2.new(1, -40, 0, 50), ZIndex = 10, Outline = 4, Parent = card })
	cardTitle = label({ Name = "Title", Text = "", TextColor3 = UIStyle.Colors.muted, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 116), Size = UDim2.new(1, -40, 0, 22), ZIndex = 10, Outline = 2, Parent = card })
	-- screen effects (local to this client): motion blur pulse, grading, depth of field
	blur = Lighting:FindFirstChild("BattleBlur") :: BlurEffect or Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Parent = "BattleBlur", 0, Lighting
	grade = Lighting:FindFirstChild("BattleGrade") :: ColorCorrectionEffect or Instance.new("ColorCorrectionEffect")
	grade.Name, grade.Parent = "BattleGrade", Lighting
	dof = Lighting:FindFirstChild("BattleDOF") :: DepthOfFieldEffect or Instance.new("DepthOfFieldEffect")
	dof.Name, dof.Enabled, dof.Parent = "BattleDOF", false, Lighting
	-- the fight window: studded title bar, a row card per side, the meter, the odds, FIGHT
	panel = UIStyle.panel({ Name = "Panel", Title = "Wild Battle!", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(700, 262), Visible = false, Parent = gui })
	local myRow = UIStyle.row({ Name = "MyRow", Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(300, 46), Parent = panel })
	myName = label({ Name = "Mine", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIStyle.Colors.money, Outline = 3,
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16), Parent = myRow })
	label({ Name = "Vs", Text = "VS", TextColor3 = UIStyle.Colors.gold, Outline = 4, Position = UDim2.fromOffset(326, 14),
		Size = UDim2.fromOffset(48, 48), Parent = panel })
	local wildRow = UIStyle.row({ Name = "WildRow", Position = UDim2.fromOffset(382, 16), Size = UDim2.fromOffset(300, 46), Parent = panel })
	wildName = label({ Name = "Wild", Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UIStyle.Colors.price, Outline = 3,
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16), Parent = wildRow })

	-- meter: a dark track, red (lose) underneath a green (win) zone that starts at the line
	meter = new("Frame", { Name = "Meter", BackgroundColor3 = LOSE, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 88),
		Size = UDim2.fromOffset(652, 40), Parent = panel })
	UIStyle.corner(meter, 10)
	UIStyle.stroke(meter, 3)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(LOSE:Lerp(WHITE, 0.15), LOSE:Lerp(Color3.new(), 0.15)), Parent = meter })
	winZone = new("Frame", { Name = "Win", BackgroundColor3 = WIN, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.5, 1), Parent = meter })
	UIStyle.corner(winZone, 10)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WIN:Lerp(WHITE, 0.18), WIN:Lerp(Color3.new(), 0.12)), Parent = winZone })
	UIStyle.studs(meter, 20, 0.66, 10).ZIndex = 2
	label({ Name = "LoseText", Text = "LOSE", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(60, 20),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, Parent = meter })
	label({ Name = "WinText", Text = "WIN", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(50, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = meter })
	lineMark = new("Frame", { Name = "Line", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 4, 1, 10), ZIndex = 4, Parent = meter })
	UIStyle.stroke(lineMark, 2)
	local chip = new("Frame", { Name = "Chip", BackgroundColor3 = UIStyle.Colors.track, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(46, 22), ZIndex = 4, Parent = lineMark })
	UIStyle.corner(chip, 6)
	UIStyle.stroke(chip, 2)
	lineLabel = label({ Name = "LineLabel", Text = "50", Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 1, -6),
		ZIndex = 5, Outline = 1, Parent = chip })
	needle = new("Frame", { Name = "Needle", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 10, 1, 20), ZIndex = 6, Parent = meter })
	UIStyle.corner(needle, 5)
	UIStyle.stroke(needle, 3)
	rollLabel = label({ Name = "Roll", Text = "", Outline = 3, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(80, 34), ZIndex = 7, Parent = needle })
	odds = label({ Name = "Odds", Text = "", Outline = 3,
		Position = UDim2.fromOffset(24, 158), Size = UDim2.fromOffset(652, 30), Parent = panel })
	fightBtn, fightBox = UIStyle.button({ Name = "Fight", Text = "FIGHT!", Color = UIStyle.Colors.red, Size = UDim2.fromOffset(300, 62),
		Position = UDim2.new(0.5, 0, 0, 226), Parent = panel })
end

local function showPanel(on: boolean)
	if on then
		panel.Visible = true
		Juice.popIn(panel, 0.45)
	else
		Juice.tween(Juice.scaleOf(panel), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if not active then
				panel.Visible = false
			end
		end)
	end
end

-- The cartoon "!" speech bubble that pops up beside your head.
local function alertBubble(): BillboardGui?
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local b = new("BillboardGui", { Adornee = head, Size = UDim2.fromScale(4.4, 4.4), StudsOffset = Vector3.new(2.3, 3.1, 0),
		AlwaysOnTop = true, LightInfluence = 0, Parent = gui })
	local img = new("ImageLabel", { Name = "Bubble", Image = Config.UI.alertBubble, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = -28, Parent = b })
	local sc = Juice.scaleOf(img)
	sc.Scale = 0
	Juice.tween(sc, 0.34, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Juice.tween(img, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	return b
end

local function popAway(b: BillboardGui?)
	if not b then
		return
	end
	local img = b:FindFirstChild("Bubble") :: ImageLabel?
	if img then
		Juice.tween(Juice.scaleOf(img), 0.12, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.delay(0.14, function()
		b:Destroy()
	end)
end

-- Hides (for this player only) the grass tufts that would block the shots: anything near the
-- lines from each camera to its subject, and right around the given spots. Tufts inside `keep`
-- (the ground the wild one stands on) always stay, so it stands in the brush.
local function clearGrass(lines: { { Vector3 } }, spots: { { Vector3 | number } }, keep: { Vector3 | number }): { BasePart }
	local brush = workspace:FindFirstChild("Wilds") and workspace.Wilds:FindFirstChild("Brush")
	local hidden = {}
	if not brush then
		return hidden
	end
	for _, t in brush:GetDescendants() do
		if t:IsA("BasePart") then
			local pos = t.Position
			local kc, kr = keep[1] :: Vector3, keep[2] :: number
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(kc.X, 0, kc.Z)).Magnitude < kr then
				continue
			end
			local hide = false
			for _, seg in lines do
				local a, b = seg[1], seg[2]
				local ab = b - a
				local u = math.clamp((pos - a):Dot(ab) / ab:Dot(ab), 0, 1)
				local closest = a + ab * u
				if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(closest.X, 0, closest.Z)).Magnitude < 4.5 and pos.Y < closest.Y + 2 then
					hide = true
					break
				end
			end
			if not hide then
				for _, spot in spots do
					local c, r = spot[1] :: Vector3, spot[2] :: number
					if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude < r then
						hide = true
						break
					end
				end
			end
			if hide then
				t.LocalTransparencyModifier = 1
				table.insert(hidden, t)
			end
		end
	end
	return hidden
end

local function cinematicOff(fast: boolean?)
	local t = if fast then 0 else 0.28
	Juice.tween(barTop, t, { Size = UDim2.fromScale(1, 0) })
	Juice.tween(barBottom, t, { Size = UDim2.fromScale(1, 0) })
	Juice.tween(speed, t, { ImageTransparency = 1 })
	Juice.tween(vignette, t, { ImageTransparency = 1 })
	Juice.tween(grade, t, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	dof.Enabled = false
	blur.Size = 0
end

-- ---------------------------------------------------------------- stage

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundAt(p: Vector3): number
	local list = { workspace:FindFirstChild("ClientPets") }
	for _, plr in Players:GetPlayers() do
		table.insert(list, plr.Character)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(p + UP * 8, Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else p.Y - 3
end

local function wildTag(model: Model, weight: number, aura: string?): BillboardGui
	local def = aura and Config.PetAuras[aura]
	local b = new("BillboardGui", { Adornee = model:FindFirstChildWhichIsA("BasePart", true), Size = UDim2.fromOffset(200, if def then 62 else 40),
		StudsOffsetWorldSpace = Vector3.new(0, 5, 0), LightInfluence = 0, Parent = gui })
	label({ Text = "WILD  " .. string.upper(Config.kg(weight)), TextColor3 = LOSE, Outline = 3, Size = UDim2.new(1, 0, 0, 40), Parent = b })
	if def then
		label({ Text = string.upper(def.name), TextColor3 = def.color, Outline = 2.5, Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 24), Parent = b })
	end
	return b
end

-- The aura effect a wild one wears (the same emitters pets get), sized to it.
local function auraCore(aura: string?, height: number): BasePart?
	local def = aura and Config.PetAuras[aura]
	local auras = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Auras")
	local src = def and auras and auras:FindFirstChild(def.vfx)
	if not (src and src:IsA("BasePart")) then
		return nil
	end
	local core = src:Clone()
	local holder = Instance.new("Model")
	core.Parent = holder
	holder:ScaleTo(math.clamp(height / 3.2, 0.8, 8))
	core.Parent = nil
	holder:Destroy()
	core.Name = "WildAura"
	core.Transparency = 1
	core.Anchored, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, false, false, false, false
	return core
end

-- Poses a fighter: offset toward the other one (dash), hop height, extra spin/tilt, shrink.
local function pose(f: Fighter, dt: number, dash: number, hop: number, spin: number, tilt: number, shrink: number,
	legSwing: number, parts, cframes)
	local face = Vector3.new(-math.sin(f.yaw), 0, -math.cos(f.yaw))
	local pos = f.spot + face * dash + UP * hop
	local sq = math.clamp(f.squash:step(dt), 0.55, 1.6)
	local sxz = 1 / math.sqrt(sq)
	local k = f.scale * shrink
	if f.pet then
		f.pet.pos = pos -- keeps its aura on it
	end
	f.centre = pos + UP * f.height * 0.5 * shrink
	f.puppet:pose(CFrame.new(pos) * CFrame.Angles(0, f.yaw + spin, 0) * CFrame.Angles(tilt, 0, 0),
		Vector3.new(sxz * k, sq * k, sxz * k), f.puppet:blink(os.clock()), legSwing, parts, cframes)
end

local function freeze(on: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if on then
		active.walk, active.jump = humanoid.WalkSpeed, humanoid.JumpHeight
		active.jumpPower = humanoid.JumpPower
		humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower = 0, 0, 0
	elseif active.walk then
		humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower = active.walk, active.jump, active.jumpPower
	end
end

local function finish()
	local b = active
	if not b then
		return
	end
	active = nil
	if b.conn then
		b.conn:Disconnect()
	end
	if b.wild.model then
		b.wild.model:Destroy()
	end
	if b.tag then
		b.tag:Destroy()
	end
	if b.auraCore then
		b.auraCore:Destroy()
	end
	Pets.setControlled(b.enc.petUid, false)
	popAway(b.bubble)
	cinematicOff(true)
	for _, t in b.grass do
		t.LocalTransparencyModifier = 0
	end
	card.Position = UDim2.new(0, -560, 0.66, 0)
	local cam = workspace.CurrentCamera
	cam.FieldOfView = b.baseFov
	cam.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	-- back on foot: restore walking; back on the mount: the server has already set ride speed
	if humanoid and b.walk and (player:GetAttribute("Mounted") or "") == "" then
		humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower = b.walk, b.jump, b.jumpPower
	end
	showPanel(false)
	HUD.setFocus(false)
end

-- Ping-pong across 0..100: lands on `roll` after travelling 4 full widths.
local function needleAt(u: number, roll: number): number
	local d = (400 + roll) * (1 - (1 - u) ^ 3)
	local m = d % 200
	return if m <= 100 then m else 200 - m
end

-- ---------------------------------------------------------------- the encounter

local function start(enc)
	if active then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myPet = Pets.get(enc.petUid)
	if not (root and myPet) then
		Net.func("Run"):InvokeServer(enc.id)
		return
	end
	local look = root.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = if fwd.Magnitude > 0.01 then fwd.Unit else Vector3.new(0, 0, -1)
	local right = fwd:Cross(UP)
	local myH = Pets.heightOf(myPet) * myPet.scale.x
	local wildDef = Config.Monsters[enc.species] or Config.Pets[enc.species]
	local wildScale = Config.petScale(enc.weight)
	local wildH = (wildDef and wildDef.height or Config.Pet.baseHeight) * wildScale
	local gap = 3 + (myH + wildH) * 0.75
	local base = root.Position + fwd * 3
	local mySpot = base + right * 1.5
	local wildSpot = mySpot + fwd * gap
	mySpot = Vector3.new(mySpot.X, groundAt(mySpot), mySpot.Z)
	wildSpot = Vector3.new(wildSpot.X, groundAt(wildSpot), wildSpot.Z)
	local yaw = math.atan2(-fwd.X, -fwd.Z)

	local wildModel = Assets.wild(enc.species)
	wildModel.Parent = workspace
	local b = {
		enc = enc,
		fwd = fwd,
		right = right,
		t0 = os.clock(),
		phase = "intro",
		phaseT = os.clock(),
		roll = nil :: number?,
		win = nil :: boolean?,
		aura = nil :: string?,
		mine = { model = nil, puppet = myPet.puppet, pet = myPet, spot = mySpot, yaw = yaw, scale = myPet.scale.x,
			squash = Juice.spring(1, 300, 12), height = myH } :: Fighter,
		wild = { model = wildModel, puppet = Puppet.new(wildModel), pet = nil, spot = wildSpot, yaw = yaw + math.pi,
			scale = wildScale, squash = Juice.spring(1, 300, 12), height = wildH } :: Fighter,
		from = myPet.pos,
		tag = nil :: BillboardGui?,
		conn = nil :: RBXScriptConnection?,
		lastNeedle = 0,
		shake = 0,
		fov = workspace.CurrentCamera.FieldOfView,
		fovTarget = workspace.CurrentCamera.FieldOfView,
		baseFov = workspace.CurrentCamera.FieldOfView,
		beats = {} :: { [string]: boolean },
		bubble = nil :: BillboardGui?,
		grass = {} :: { BasePart },
		auraCore = auraCore(enc.aura, wildH),
	}
	active = b
	freeze(true)
	HUD.setFocus(true)
	Pets.setControlled(enc.petUid, true)
	b.tag = wildTag(wildModel, enc.weight, enc.aura)

	b.tag.Enabled = false -- shown once the cinematic hands over to the fight
	-- the "!" pops up first
	b.bubble = alertBubble()
	b.shake = 0.12
	b.fovTarget = b.baseFov - 12
	Juice.sound("pop", 1.55, 0.7)
	Juice.sound("rare", 1.45, 0.45)
	-- name card for the reveal
	local monster = Config.Monsters[enc.species]
	local accent = if monster then monster.color else LOSE
	cardName.Text = string.upper(Config.displayName(enc.species))
	cardName.TextColor3 = accent:Lerp(WHITE, 0.25)
	cardLevel.Text = string.upper(Config.kg(enc.weight))
	cardTitle.Text = if monster then monster.title else "Wild pet"
	local wildAura = enc.aura and Config.PetAuras[enc.aura]
	cardAura.Visible = wildAura ~= nil
	if wildAura then
		UIStyle.setChip(cardAura, string.upper(wildAura.name), wildAura.color)
	end
	local cardAccent = card:FindFirstChild("Accent") :: Frame?
	if cardAccent then
		cardAccent.BackgroundColor3 = accent
	end
	card.Position = UDim2.new(0, -560, 0.66, 0)
	card.Rotation = -6

	-- ui
	local myAura = enc.petAura and Config.PetAuras[enc.petAura]
	myName.Text = string.upper(string.format("%s  %s%s", Config.displayName(enc.petId), Config.kg(enc.petWeight), if myAura then "  +" .. myAura.name else ""))
	wildName.Text = string.upper(string.format("Wild %s  %s%s", Config.displayName(enc.species), Config.kg(enc.weight), if wildAura then "  +" .. wildAura.name else ""))
	odds.Text = string.format("Roll over %d to win   \u{2022}   %d%% chance", enc.line, enc.chance)
	winZone.Size = UDim2.fromScale((100 - enc.line) / 100, 1)
	lineMark.Position = UDim2.fromScale(enc.line / 100, 0.5)
	lineLabel.Text = tostring(enc.line)
	needle.Position = UDim2.fromScale(0, 0.5)
	rollLabel.Text = ""
	fightBox.Visible = true

	-- camera: a side view of the face-off
	local cam = workspace.CurrentCamera
	-- frame the face-off from whichever side has a clear view (trees, fences...), else move in close
	local mid = (mySpot + wildSpot) / 2 + UP * math.max(myH, wildH) * 0.45
	local dist = gap * 1.3 + 10 + wildH * 0.35
	local blockers = { wildModel, workspace:FindFirstChild("ClientPets") }
	for _, plr in Players:GetPlayers() do
		table.insert(blockers, plr.Character)
	end
	rayParams.FilterDescendantsInstances = blockers
	local camPos
	for _, side in { 1, -1 } do
		local want = mid + right * side * dist + UP * dist * 0.42 - fwd * dist * 0.2
		if not workspace:Raycast(mid, want - mid, rayParams) then
			camPos = want
			break
		end
	end
	if not camPos then
		local want = mid + right * dist + UP * dist * 0.42 - fwd * dist * 0.2
		local hit = workspace:Raycast(mid, want - mid, rayParams)
		camPos = if hit then mid + (want - mid).Unit * math.max(6, hit.Distance - 1) else want
	end
	-- aim a little below the fighters so they sit above the battle panel
	local camGoal = CFrame.lookAt(camPos, mid - UP * (2 + dist * 0.16))
	local camFrom = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	-- cinematic shots: ease in on the player, then a low tilted shot of the grass pushing in
	local head = (player.Character:FindFirstChild("Head") :: BasePart?) or root
	local alertGoal = CFrame.lookAt(camFrom.Position:Lerp(head.Position, 0.3), head.Position)
	-- eye level with the monster's face, so you get a good look at it
	local lookAt = wildSpot + UP * wildH * 0.5
	local back = -fwd
	local revStart = wildSpot + back * (wildH * 1.9 + 9) + right * (wildH * 0.3 + 3) + UP * (wildH * 0.62 + 2)
	local revEnd = wildSpot + back * (wildH * 1.3 + 6) + right * (wildH * 0.18 + 2) + UP * (wildH * 0.55 + 1.5)
	local revEndCf = CFrame.lookAt(revEnd, lookAt)
	-- facing: the monster stares down the reveal camera, then (like the pet) turns partly toward
	-- the battle camera so you see its face, not its side
	local function yawTo(from: Vector3, to: Vector3): number
		local d = to - from
		return math.atan2(-d.X, -d.Z)
	end
	local revYaw = yawTo(wildSpot, revStart)
	local battleWildYaw = Juice.lerpAngle(yaw + math.pi, yawTo(wildSpot, camPos), 0.45)
	b.mine.yaw = Juice.lerpAngle(yaw, yawTo(mySpot, camPos), 0.35)
	b.wild.yaw = revYaw
	b.grass = clearGrass({ { revStart, lookAt }, { revEnd, lookAt }, { camPos, mid }, { root.Position, mid } },
		{ { mySpot, myH * 0.5 + 3 } }, { wildSpot, wildH * 0.45 + 3 })

	local stars = 0
	b.conn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local t = now - b.t0
		local pt = now - b.phaseT
		local parts, cframes = {}, {}
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable -- keep the default camera from taking it back
		end
		local mine, wild = b.mine, b.wild
		local function beat(name: string, at: number): boolean
			if t >= at and not b.beats[name] then
				b.beats[name] = true
				return true
			end
			return false
		end

		-- ------------------------------------------------ cinematic beats
		if beat("cut", T_CUT) then
			popAway(b.bubble)
			flash.BackgroundTransparency = 0
			Juice.tween(flash, 0.32, { BackgroundTransparency = 1 })
			Juice.tween(barTop, 0.24, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quad)
			Juice.tween(barBottom, 0.24, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quad)
			Juice.tween(speed, 0.2, { ImageTransparency = 0.4 })
			Juice.tween(vignette, 0.25, { ImageTransparency = 0.1 })
			Juice.tween(grade, 0.25, { Saturation = 0.35, Contrast = 0.18, Brightness = 0.02, TintColor = Color3.fromRGB(255, 244, 236) })
			dof.Enabled = true
			dof.FocusDistance = (revStart - lookAt).Magnitude
			dof.InFocusRadius = 5
			dof.NearIntensity = 0.5
			dof.FarIntensity = 0.75
			b.fov, b.fovTarget = b.baseFov - 16, b.baseFov - 14
			Juice.sound("whoosh", 0.8, 0.6)
		end
		for i, at in { T_CUT + 0.08, T_CUT + 0.3, T_CUT + 0.5, T_CUT + 0.66 } do
			if beat("rustle" .. i, at) then
				Juice.burst(wild.spot + UP * 1.2 + b.right * (i - 2) * 0.8, LEAF, 10 + i * 3, "confetti")
				b.shake = math.max(b.shake, 0.08 + i * 0.04)
				Juice.sound("whoosh", 1.7 - i * 0.15, 0.25)
			end
		end
		if beat("burst", T_BURST) then
			Juice.burst(wild.spot + UP * 1.5, LEAF, 48, "confetti")
			Juice.burst(wild.spot, Color3.fromRGB(235, 220, 170), 18, "dust")
			Juice.burst(wild.spot + UP * wild.height * 0.5, WHITE, 16)
			speed.ImageTransparency = 0
			Juice.tween(speed, 0.4, { ImageTransparency = 0.4 })
			flash.BackgroundTransparency = 0.55
			Juice.tween(flash, 0.2, { BackgroundTransparency = 1 })
			b.shake = 0.9
			b.fov = b.baseFov - 4
			b.fovTarget = b.baseFov - 13
			Juice.sound("land", 0.6, 0.9)
			Juice.sound("rare", 0.8, 0.6)
		end
		if beat("land", T_LAND) then
			wild.squash.v -= 10
			Juice.burst(wild.spot, Color3.fromRGB(235, 220, 170), 12, "dust")
			b.shake = math.max(b.shake, 0.5)
			Juice.sound("land", 0.5, 0.8)
			-- the name card slams in
			Juice.tween(card, 0.36, { Position = UDim2.new(0, 56, 0.66, 0), Rotation = 0 }, Enum.EasingStyle.Back)
			Juice.sound("pop", 0.75, 0.6)
		end
		for i, at in { T_LAND + 0.15, T_LAND + 0.45, T_LAND + 0.75, T_LAND + 1.1, T_LAND + 1.4 } do
			if beat("roar" .. i, at) then
				wild.squash.v += 9 - i
				b.shake = math.max(b.shake, 0.35)
				Juice.sound("whoosh", 0.45 + i * 0.05, 0.45)
				if i == 1 then
					Juice.punch(card, 0.08)
				end
			end
		end
		if beat("whip", T_WHIP) then
			Juice.tween(card, 0.3, { Position = UDim2.new(1.2, 0, 0.66, 0), Rotation = 4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			cinematicOff()
			b.fovTarget = b.baseFov
			Juice.sound("whoosh", 1.15, 0.6)
		end
		if beat("odds", T_ODDS) then
			blur.Size = 0
			if b.tag then
				b.tag.Enabled = true
			end
			if b.phase == "intro" then
				b.phase = "odds"
			end
			showPanel(true)
		end

		-- ------------------------------------------------ camera
		local cf: CFrame
		if t < T_CUT then
			cf = camFrom:Lerp(alertGoal, Juice.easeOutCubic(math.min(t / 0.7, 1)))
		elseif t < T_WHIP then
			local e = Juice.easeOutCubic(math.clamp((t - T_CUT) / (T_WHIP - T_CUT), 0, 1))
			local at = revStart:Lerp(revEnd, e)
			cf = CFrame.lookAt(at, lookAt) * CFrame.Angles(0, 0, math.rad(7) * (1 - e))
			dof.FocusDistance = (at - lookAt).Magnitude - wildH * 0.3 -- keep the monster's face sharp
		elseif t < T_ODDS then
			local u = math.clamp((t - T_WHIP) / (T_ODDS - T_WHIP), 0, 1)
			local e = u * u * (3 - 2 * u)
			cf = revEndCf:Lerp(camGoal, e)
			blur.Size = math.sin(u * math.pi) * 18 -- motion blur on the whip
		else
			cf = camGoal
		end
		b.fov += (b.fovTarget - b.fov) * Juice.smoothing(9, dt)
		cam.FieldOfView = b.fov
		if b.shake > 0.005 then
			local k = b.shake
			cf = cf * CFrame.new(math.noise(now * 24, 1.3) * k, math.noise(now * 24, 7.1) * k, 0)
				* CFrame.Angles(0, 0, math.noise(now * 18, 3.7) * k * 0.05)
			b.shake *= math.exp(-dt * 7)
		end
		cam.CFrame = cf
		local breathe = math.sin(now * 3) * 0.04
		mine.squash.target, wild.squash.target = 1 + breathe, 1 - breathe

		if b.phase == "intro" or b.phase == "odds" then
			-- my pet waits where it was, then hops into place during the whip
			local u = math.clamp((t - T_WHIP) / 0.45, 0, 1)
			local spot = mine.spot
			mine.spot = b.from:Lerp(spot, Juice.easeOutCubic(u))
			pose(mine, dt, 0, math.sin(u * math.pi) * 2, 0, 0, 1, if u > 0 and u < 1 then 0.5 else 0, parts, cframes)
			mine.spot = spot
			-- the wild one: hidden in the grass, bursts out in an arc, lands, then menaces
			if t >= T_WHIP then
				wild.yaw = Juice.lerpAngle(revYaw, battleWildYaw, math.clamp((t - T_WHIP) / (T_ODDS - T_WHIP), 0, 1))
			end
			if t < T_BURST then
				pose(wild, dt, 0, -wild.height - 2, 0, 0, 0.001, 0, parts, cframes)
			elseif t < T_LAND then
				local w = (t - T_BURST) / (T_LAND - T_BURST)
				local hop = -wild.height * 1.2 * (1 - w) ^ 2 + math.sin(w * math.pi) * 3 * math.sqrt(wild.scale)
				pose(wild, dt, 0, hop, -(1 - w) * 1.4, 0, math.max(0.001, Juice.easeOutBack(math.min(w * 1.6, 1))), 0.6, parts, cframes)
			else
				local roaring = t < T_WHIP
				local menace = math.abs(math.sin(now * (if roaring then 9 else 4))) * (if roaring then 0.25 else 0.4)
				pose(wild, dt, 0, menace, 0, if roaring then -0.08 else 0, 1, if roaring then 0.3 else 0, parts, cframes)
			end
		elseif b.phase == "clash" then
			-- three bumps; the needle sweeps meanwhile and lands as the last bump ends
			local u = math.min(pt / CLASH_TIME, 1)
			local bumpU = (pt / CLASH_TIME) * 3
			local i = math.floor(bumpU)
			local p = bumpU - i
			local dash = if i < 3 then math.sin(p * math.pi) ^ 2 * gap * 0.32 else 0
			if i < 3 and p > 0.5 and stars <= i then
				stars = i + 1
				local hit = (mine.spot + wild.spot) / 2 + UP * math.min(mine.height, wild.height) * 0.6
				Juice.burst(hit, WHITE, 16)
				Juice.burst(hit, GOLD, 12, "confetti")
				Juice.sound("land", 0.8 + i * 0.15, 0.6)
				Juice.shake(0.35, 0.18)
				mine.squash.v -= 6
				wild.squash.v -= 6
			end
			pose(mine, dt, dash, 0, 0, -dash * 0.04, 1, dash * 0.15, parts, cframes)
			pose(wild, dt, dash, 0, 0, -dash * 0.04, 1, dash * 0.15, parts, cframes)
			local v = needleAt(u, b.roll)
			needle.Position = UDim2.fromScale(v / 100, 0.5)
			if (b.lastNeedle - b.enc.line) * (v - b.enc.line) < 0 then
				Juice.sound("tick", 1 + u * 0.5, 0.3)
			end
			b.lastNeedle = v
			if u >= 1 then
				b.phase, b.phaseT = "result", now
				local won = b.win
				local c = if won then WIN else LOSE
				rollLabel.Text = tostring(b.roll)
				rollLabel.TextColor3 = c
				Juice.popIn(rollLabel, 0.35)
				Juice.punch(needle, 0.4)
				Juice.punch(meter, 0.12)
				if won then
					local def = Config.PetAuras[b.aura]
					HUD.banner("YOU WIN!", def and def.name or "", def and def.color or WIN)
					Juice.sound("rare", 1, 0.7)
					Juice.burst(wild.spot + UP * wild.height * 0.5, def and def.color or GOLD, 40, "confetti")
				else
					HUD.banner("KNOCKED OUT!", "Your pet ran home to rest", LOSE)
					Juice.sound("tick", 0.45, 0.6)
					Juice.shake(0.6, 0.3)
				end
			end
		elseif b.phase == "result" then
			local u = math.min(pt / 0.9, 1)
			if b.win then
				-- wild one spins up and pops; mine does happy hops
				pose(wild, dt, 0, u * 3, u * 12, 0, math.max(0.001, 1 - u), 0, parts, cframes)
				pose(mine, dt, 0, math.abs(math.sin(pt * 9)) * 1.6 * (1 - u * 0.5), 0, 0, 1, 0.4, parts, cframes)
				if u >= 1 and not b.flown then
					b.flown = true
					local def = Config.PetAuras[b.aura]
					local at = wild.spot + UP * wild.height * 0.5
					Juice.burst(at, WHITE, 20)
					local sp = cam:WorldToViewportPoint(at)
					HUD.fly(Config.Icons[b.aura] or "", Vector2.new(sp.X, sp.Y), HUD.slotFor(b.aura), 96, 0.7, function()
						HUD.reveal(b.aura)
						Juice.sound("pop", 1.25, 0.6)
					end)
					if def then
						Juice.burst(at, def.color, 24)
					end
				end
			else
				-- mine tumbles over; the wild one gloats with little hops
				pose(mine, dt, -u * 2, math.sin(u * math.pi) * 1.5, 0, u * 1.4, 1, 0, parts, cframes)
				pose(wild, dt, 0, math.abs(math.sin(pt * 10)) * 1.2, 0, 0, 1, 0.3, parts, cframes)
				if u >= 1 and not b.flown then
					b.flown = true
					Juice.burst(mine.spot + UP * mine.height * 0.5, WHITE, 20)
					Juice.burst(mine.spot, Color3.fromRGB(235, 220, 170), 10, "dust")
				end
			end
			if pt > 1.6 then
				finish()
				return
			end
		elseif b.phase == "flee" then
			-- the wild one bounds off into the brush and shrinks away
			local u = math.min(pt / 0.8, 1)
			pose(mine, dt, 0, 0, 0, 0, 1, 0, parts, cframes)
			pose(wild, dt, -u * gap, math.abs(math.sin(u * math.pi * 3)) * 2, 0, 0, math.max(0.001, 1 - u), 0.5, parts, cframes)
			if u >= 1 then
				Juice.burst(wild.spot - b.fwd * -gap, LEAF, 14, "confetti")
				finish()
				return
			end
		end
		if b.tag then
			b.tag.StudsOffsetWorldSpace = Vector3.new(0, wild.height * 0.8 + 1, 0)
		end
		-- its aura flares up as it bursts out of the grass, and goes when it's beaten
		local core = b.auraCore
		if core then
			if b.phase == "result" and b.win and pt > 0.9 then
				core:Destroy()
				b.auraCore = nil
			elseif t >= T_BURST then
				if not core.Parent then
					core.Parent = workspace
				end
				table.insert(parts, core)
				table.insert(cframes, CFrame.new(wild.centre or wild.spot + UP * wild.height * 0.5)) -- follows its hops and dashes
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

local function onFight()
	local b = active
	if not (b and b.phase == "odds") then
		return
	end
	b.phase = "waiting"
	fightBox.Visible = false
	local ok, res = pcall(function()
		return Net.func("Fight"):InvokeServer(b.enc.id)
	end)
	if active ~= b then
		return
	end
	if not (ok and res and res.ok) then
		HUD.toast("The wild pet got away!")
		b.phase, b.phaseT = "flee", os.clock()
		return
	end
	b.roll, b.win, b.aura = res.roll, res.win, res.aura
	if res.win and res.aura then
		HUD.hide(res.aura) -- held back until it flies into the bar
	end
	b.phase, b.phaseT = "clash", os.clock()
	Juice.sound("whoosh", 1, 0.5)
end

-- ---------------------------------------------------------------- rustling through the brush

local brushZones: { BasePart } = {}
local lastRustle = 0
local function inBrush(p: Vector3): boolean
	for _, z in brushZones do
		local lp = z.CFrame:PointToObjectSpace(p)
		local h = z.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Z) <= h.Z then
			return true
		end
	end
	return false
end

local function rustle()
	if active then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.MoveDirection.Magnitude < 0.1 then
		return
	end
	local now = os.clock()
	if now - lastRustle > 0.28 and inBrush(root.Position) then
		lastRustle = now
		Juice.burst(root.Position - UP * 2, LEAF, 4, "confetti")
		Juice.sound("whoosh", 1.6 + math.random() * 0.3, 0.08)
	end
end

function Battle.init()
	build()
	fightBtn.Activated:Connect(onFight)
	if RunService:IsStudio() then
		-- test hook: lets automated playtests press FIGHT (set the attribute from the command bar)
		player:GetAttributeChangedSignal("DebugFight"):Connect(onFight)
	end
	Net.event("EncounterStarted").OnClientEvent:Connect(start)
	player.CharacterRemoving:Connect(finish)
	task.spawn(function()
		local wilds = workspace:WaitForChild("Wilds", 30)
		local zones = wilds and wilds:WaitForChild("BrushZones", 10)
		if zones then
			for _, z in zones:GetChildren() do
				if z:IsA("BasePart") then
					table.insert(brushZones, z)
				end
			end
		end
	end)
	RunService.Heartbeat:Connect(rustle)
	-- a little hint the first time you walk into the Wilds
	local hinted = false
	player:GetAttributeChangedSignal("InWilds"):Connect(function()
		if not player:GetAttribute("InWilds") then
			return
		end
		if (player:GetAttribute("Mounted") or "") == "" then
			task.delay(0.4, function()
				if player:GetAttribute("InWilds") and (player:GetAttribute("Mounted") or "") == "" then
					HUD.toast("Ride a pet in here to meet wild pets! (hold E on one of your farm pets)")
				end
			end)
		elseif not hinted then
			hinted = true
			HUD.toast("Walk through the tall grass to find wild pets!")
		end
	end)
end

return Battle
