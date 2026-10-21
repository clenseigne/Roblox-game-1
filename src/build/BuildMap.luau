-- Edit-time map builder. Run once from the command bar / MCP; it rebuilds Workspace.Map
-- and Workspace.Plots from scratch. Everything is Plastic so the "Studs" MaterialVariant
-- gives the whole world the stud look.
--
-- Layout (laid out like Steal An Egg's hub): a walled hub island on open ocean. Five 64x74 plots
-- sit in a row along the back wall (80 apart), their entrances facing the open front strip. A
-- gap in the front wall (z = HUB_FRONT) leads out onto the Wilds runway (BuildWilds.luau).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

local STUD_NORMAL = "rbxassetid://109962062979392"
local PLOT_COUNT, PLOT_SPACING = 5, 80
local PLOT_W, PLOT_D = 64, 74
local HUB_W, HUB_BACK, HUB_FRONT = 436, -96, 96 -- hub interior: x -218..218, z -96..96
local GATE_W = HUB_W -- the front is open all the way across onto the Wilds runway (same width)
local WALL_H, WALL_T = 30, 8
local FONT = Enum.Font.FredokaOne

local C = {
	ground = Color3.fromRGB(141, 170, 69),
	plot = Color3.fromRGB(163, 194, 85),
	farm = Color3.fromRGB(196, 214, 106),
	path = Color3.fromRGB(217, 194, 138),
	wood = Color3.fromRGB(107, 59, 42),
	woodDark = Color3.fromRGB(78, 42, 30),
	purple = Color3.fromRGB(124, 77, 255),
	purpleDark = Color3.fromRGB(75, 46, 131),
	leaf1 = Color3.fromRGB(122, 79, 224),
	leaf2 = Color3.fromRGB(146, 104, 240),
	gold = Color3.fromRGB(255, 201, 60),
	ink = Color3.fromRGB(30, 21, 48),
	pink = Color3.fromRGB(255, 126, 182),
	sand = Color3.fromRGB(242, 214, 150),
	water = Color3.fromRGB(64, 156, 226),
	wall = Color3.fromRGB(204, 118, 84),
	trim = Color3.fromRGB(132, 214, 72),
	hub = Color3.fromRGB(150, 186, 74),
}
local ACCENTS = {
	Color3.fromRGB(255, 95, 162), Color3.fromRGB(255, 166, 48), Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(120, 220, 90), Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 220, 70),
}

-- ---------------------------------------------------------------- helpers

local function part(props: { [string]: any }): BasePart
	local p: BasePart = Instance.new(props.Shape and "Part" or (props.Class or "Part")) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Plastic
	for k, v in props do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function label(parent: BasePart, text: string, face: Enum.NormalId, color: Color3, pps: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = pps or 40
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = C.ink
	stroke.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.05, 0), UDim.new(0.05, 0)
	pad.Parent = t
	t.Parent = gui
	gui.Parent = parent
	return t
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- ---------------------------------------------------------------- props

local function tree(parent: Instance, cf: CFrame, scale: number, round: boolean)
	local m = model("Tree", parent)
	part({ Name = "Trunk", Size = Vector3.new(1.6, 6, 1.6) * scale, CFrame = cf * CFrame.new(0, 3 * scale, 0),
		Color = C.woodDark, Parent = m })
	if round then
		for i, s in { { 0, 7, 0, 6 }, { 1.8, 8.6, 0.6, 4.4 }, { -1.6, 8.8, -0.8, 4 } } do
			part({ Name = "Leaves" .. i, Shape = Enum.PartType.Ball, Size = Vector3.one * s[4] * scale,
				CFrame = cf * CFrame.new(s[1] * scale, s[2] * scale, s[3] * scale),
				Color = i == 1 and C.leaf1 or C.leaf2, Parent = m })
		end
	else
		for i = 1, 4 do
			local w = (7 - i * 1.4) * scale
			part({ Name = "Leaves" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8 * scale, w, w),
				CFrame = cf * CFrame.new(0, (4.5 + i * 1.7) * scale, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = i % 2 == 0 and C.leaf2 or C.leaf1, Parent = m })
		end
	end
	return m
end

local function barrel(parent: Instance, cf: CFrame)
	local m = model("Barrel", parent)
	part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 2.6, 2.6),
		CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = C.woodDark, Parent = m })
	for _, y in { 0.5, 2.7 } do
		part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2.8, 2.8),
			CFrame = cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(70, 90, 190), Parent = m })
	end
	part({ Name = "Lid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.3, 2.3),
		CFrame = cf * CFrame.new(0, 3.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 90, 120), Parent = m })
	return m
end

local function flower(parent: Instance, cf: CFrame, color: Color3)
	local m = model("Flower", parent)
	part({ Name = "Center", Size = Vector3.new(0.6, 0.3, 0.6), CFrame = cf * CFrame.new(0, 0.35, 0),
		Color = C.gold, Parent = m })
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		part({ Name = "Petal", Size = Vector3.new(0.7, 0.2, 0.7),
			CFrame = cf * CFrame.new(math.cos(a) * 0.55, 0.3, math.sin(a) * 0.55) * CFrame.Angles(0, a, 0),
			Color = color, Parent = m })
	end
	return m
end

local function fence(parent: Instance, a: Vector3, b: Vector3, base: CFrame)
	local dir = b - a
	local len = dir.Magnitude
	local mid = (a + b) / 2
	local rot = CFrame.lookAt(Vector3.zero, dir)
	for _, y in { 1.4, 2.8 } do
		part({ Name = "Rail", Size = Vector3.new(0.5, 0.5, len), CFrame = base * (CFrame.new(mid + Vector3.new(0, y, 0)) * rot),
			Color = C.wood, Parent = parent })
	end
	local posts = math.max(1, math.floor(len / 5))
	for i = 0, posts do
		local p = a + dir * (i / posts)
		part({ Name = "Post", Size = Vector3.new(0.9, 3.8, 0.9), CFrame = base * CFrame.new(p + Vector3.new(0, 1.9, 0)),
			Color = C.woodDark, Parent = parent })
	end
end

-- ---------------------------------------------------------------- machine + feed station

-- Roll pedestal: foods pop up on top while rolling. A pull-lever stands beside it, joined by a pipe.
-- (Model keeps the name "RollMachine"; its PrimaryPart is the pedestal column.)
local function rollMachine(parent: Instance, cf: CFrame, accent: Color3)
	local m = model("RollMachine", parent)
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand upright
	part({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 8.6, 8.6),
		CFrame = cf * CFrame.new(0, 0.5, 0) * up, Color = C.purpleDark, Parent = m })
	local column = part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 6.4, 6.4),
		CFrame = cf * CFrame.new(0, 2.3, 0) * up, Color = C.purple, Parent = m })
	part({ Name = "Trim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7, 7),
		CFrame = cf * CFrame.new(0, 3.5, 0) * up, Color = C.gold, Parent = m })
	part({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 7.4, 7.4),
		CFrame = cf * CFrame.new(0, 3.95, 0) * up, Color = C.purpleDark, Parent = m })
	part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 6.6, 6.6),
		CFrame = cf * CFrame.new(0, 4.33, 0) * up, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Parent = m })
	part({ Name = "Stage", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 5.8, 5.8),
		CFrame = cf * CFrame.new(0, 4.36, 0) * up, Color = accent, Parent = m })
	local display = Instance.new("Attachment")
	display.Name = "Display"
	display.Parent = column
	display.WorldCFrame = cf * CFrame.new(0, 4.44, 0)

	-- lever on the right, joined to the pedestal by a gold pipe
	local lx = 6.6
	local leverBase = part({ Name = "LeverBase", Size = Vector3.new(2.2, 1.6, 2.2), CFrame = cf * CFrame.new(lx, 0.8, 0),
		Color = C.purpleDark, Parent = m })
	part({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(lx - 1.1 - 3.6, 0.8, 0.8),
		CFrame = cf * CFrame.new((3.6 + lx - 1.1) / 2, 1, 0), Color = C.gold, Parent = m })
	part({ Name = "PipeCollar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.2, 1.2),
		CFrame = cf * CFrame.new(lx - 1.2, 1, 0), Color = C.gold, Parent = m })
	local lever = model("Lever", m)
	local pivot = part({ Name = "Pivot", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1,
		CFrame = cf * CFrame.new(lx, 1.8, 0), Color = C.gold, Parent = lever })
	part({ Name = "Rod", Size = Vector3.new(0.45, 3.8, 0.45), CFrame = pivot.CFrame * CFrame.new(0, 1.9, 0),
		Color = Color3.fromRGB(200, 200, 214), Material = Enum.Material.Metal, Parent = lever })
	part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = pivot.CFrame * CFrame.new(0, 3.9, 0),
		Color = Color3.fromRGB(232, 33, 58), Material = Enum.Material.SmoothPlastic, Parent = lever })
	lever.PrimaryPart = pivot

	local sign = part({ Name = "Sign", Size = Vector3.new(7, 2, 0.5), CFrame = cf * CFrame.new(0, 9.6, 4.6), Color = C.pink, Parent = m })
	label(sign, "ROLL!", Enum.NormalId.Front, Color3.new(1, 1, 1))
	for _, x in { -2.6, 2.6 } do
		part({ Name = "SignPost", Size = Vector3.new(0.5, 8.6, 0.5), CFrame = cf * CFrame.new(x, 4.3, 4.8), Color = C.woodDark, Parent = m })
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RollPrompt"
	prompt.ActionText = "Pull"
	prompt.ObjectText = "Roll Lever"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = leverBase
	m.PrimaryPart = column
	return m
end

local function feedStation(parent: Instance, cf: CFrame)
	local m = model("FeedStation", parent)
	local bowl = part({ Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 6.4, 6.4),
		CFrame = cf * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = C.pink, Parent = m })
	part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7, 7),
		CFrame = cf * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 170, 205), Parent = m })
	part({ Name = "Inside", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5.4, 5.4),
		CFrame = cf * CFrame.new(0, 2.85, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 60, 100), Parent = m })
	part({ Name = "Post", Size = Vector3.new(0.6, 6, 0.6), CFrame = cf * CFrame.new(0, 3, 4.2), Color = C.woodDark, Parent = m })
	local sign = part({ Name = "Sign", Size = Vector3.new(5, 1.8, 0.4), CFrame = cf * CFrame.new(0, 6.4, 4.2), Color = C.gold, Parent = m })
	label(sign, "FEED", Enum.NormalId.Front, Color3.new(1, 1, 1))
	local spot = Instance.new("Attachment")
	spot.Name = "PetSpot"
	spot.Parent = bowl
	spot.WorldCFrame = cf * CFrame.new(0, 1, -4.5)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FeedPrompt"
	prompt.ActionText = "Feed Pet"
	prompt.ObjectText = "Pet Bowl"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bowl
	m.PrimaryPart = bowl
	return m
end

-- ---------------------------------------------------------------- food stand
-- Looks dug into the ground: a low grass terrace holds a row of stepping-stone pedestals; in
-- front, a dirt ramp drops into a sunken dirt gutter that's closed off by a grass curb and grass
-- ends. Coins roll down the ramp and glide to a stop on the gutter floor. Built in its own frame:
-- the row runs along local X, pedestals at +Z, the gutter at -Z (facing the player).
-- Everything is Plastic so it gets the stud texture (only the glow ring is Neon).
local STAND_SLOTS, STAND_SPACING = 6, 7
local GROUND_Y = 1.0 -- plot base top
local TERRACE_Y = 1.6 -- grass terrace top (pedestal row)
local PED_Z = 5.6 -- pedestal centers
local RAMP_TOP_Z, RAMP_TOP_Y = 2.2, TERRACE_Y
local RAMP_BOT_Z, RAMP_BOT_Y = -2.4, 1.1
local GUTTER_FRONT_Z = -9.4
local DIRT = Color3.fromRGB(206, 166, 112)
local DIRT_DARK = Color3.fromRGB(176, 134, 86)
local STONE = Color3.fromRGB(226, 208, 165)

local function rampY(z: number): number
	local u = math.clamp((RAMP_TOP_Z - z) / (RAMP_TOP_Z - RAMP_BOT_Z), 0, 1)
	return RAMP_TOP_Y + (RAMP_BOT_Y - RAMP_TOP_Y) * u
end

local function attach(parent: Instance, name: string, worldCf: CFrame)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = parent
	a.WorldCFrame = worldCf
	return a
end

-- A block whose top sits at `top` and whose bottom sinks into the plot base.
local function slab(parent: Instance, name: string, cf: CFrame, x: number, z: number, sx: number, sz: number, top: number, color: Color3)
	local h = top - GROUND_Y + 0.5
	return part({ Name = name, Size = Vector3.new(sx, h, sz), CFrame = cf * CFrame.new(x, top - h / 2, z), Color = color, Parent = parent })
end

local function foodStand(parent: Instance, cf: CFrame, accent: Color3)
	local m = model("FoodStand", parent)
	local up = CFrame.Angles(0, 0, math.rad(90))
	local half = (STAND_SLOTS - 1) * STAND_SPACING / 2 + 3.5
	local endW = 2 -- grass ends that close off the gutter

	-- grass terrace behind the gutter, and grass ends + curb around it
	slab(m, "Terrace", cf, 0, (RAMP_TOP_Z + 9.4) / 2, half * 2 + endW * 2, 9.4 - RAMP_TOP_Z, TERRACE_Y, C.plot)
	for side = -1, 1, 2 do
		slab(m, "GrassEnd", cf, side * (half + endW / 2), (RAMP_TOP_Z + GUTTER_FRONT_Z - 1.6) / 2, endW,
			RAMP_TOP_Z - GUTTER_FRONT_Z + 1.6, TERRACE_Y, C.plot)
	end
	slab(m, "Curb", cf, 0, GUTTER_FRONT_Z - 0.8, half * 2, 1.6, 1.45, C.plot)

	-- dirt ramp (thick so its underside never shows) and the sunken dirt gutter floor
	local a = Vector3.new(0, RAMP_TOP_Y, RAMP_TOP_Z)
	local b = Vector3.new(0, RAMP_BOT_Y, RAMP_BOT_Z)
	local mid, dir = (a + b) / 2, (b - a)
	local ramp = part({ Name = "Ramp", Size = Vector3.new(half * 2, 0.8, dir.Magnitude),
		CFrame = cf * CFrame.lookAt(mid, mid + dir) * CFrame.new(0, -0.4, 0), Color = DIRT, Parent = m })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 1
	gui.ClipsDescendants = true
	local count = 16
	for i = 1, count do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, (i - 0.5) / count) -- gui X runs down the slope, gui Y along the row
		t.Size = UDim2.fromScale(0.5, 0.8 / count)
		t.Font = FONT
		t.TextScaled = true
		t.Text = ">" -- points downhill
		t.TextColor3 = DIRT_DARK
		t.TextTransparency = 0.15
		t.Parent = gui
	end
	gui.Parent = ramp
	slab(m, "Gutter", cf, 0, (RAMP_BOT_Z + GUTTER_FRONT_Z) / 2, half * 2, RAMP_BOT_Z - GUTTER_FRONT_Z, RAMP_BOT_Y, DIRT)

	-- stepping-stone pedestals sunk into the terrace
	for i = 1, STAND_SLOTS do
		local x = -half + 3.5 + (i - 1) * STAND_SPACING
		local slot = model("Slot" .. i, m)
		slot:SetAttribute("Slot", i)
		part({ Name = "Foot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 6, 6),
			CFrame = cf * CFrame.new(x, TERRACE_Y + 0.05, PED_Z) * up, Color = DIRT_DARK, Parent = slot })
		local top = part({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5.2, 5.2),
			CFrame = cf * CFrame.new(x, TERRACE_Y + 0.2, PED_Z) * up, Color = STONE, Parent = slot })
		part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 4.6, 4.6),
			CFrame = cf * CFrame.new(x, TERRACE_Y + 0.37, PED_Z) * up, Color = accent, Material = Enum.Material.Neon, Parent = slot })
		part({ Name = "Pad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, 4.0, 4.0),
			CFrame = cf * CFrame.new(x, TERRACE_Y + 0.38, PED_Z) * up, Color = STONE, Parent = slot })
		attach(top, "Stage", cf * CFrame.new(x, TERRACE_Y + 0.42, PED_Z)) -- food stands here, facing the player
		attach(top, "Drop", cf * CFrame.new(x, rampY(1.4), 1.4)) -- coins land on the ramp here
		attach(top, "RampEnd", cf * CFrame.new(x, RAMP_BOT_Y, RAMP_BOT_Z)) -- ...slide to here
		attach(top, "Rest", cf * CFrame.new(x, RAMP_BOT_Y, (RAMP_BOT_Z + GUTTER_FRONT_Z) / 2)) -- ...and glide out around here
		slot.PrimaryPart = top
	end
	return m
end

-- ---------------------------------------------------------------- plot
-- Local frame: -Z is the front (the entrance, facing the hub's open strip), X is the right.
-- Footprint x -32..32, z -37..37: farm at the back-left, food stand down the right side with a
-- walkway along its coin gutter, roll machine at the front-left, fence all round with a gap.

local function plot(parent: Instance, index: number, cf: CFrame)
	local accent = ACCENTS[index]
	local m = model("Plot" .. index, parent)
	m:SetAttribute("Index", index)
	CollectionService:AddTag(m, "Plot")
	local hw, hd = PLOT_W / 2, PLOT_D / 2
	local base = part({ Name = "Base", Size = Vector3.new(PLOT_W, 1, PLOT_D), CFrame = cf * CFrame.new(0, 0.5, 0), Color = C.plot, Parent = m })
	m.PrimaryPart = base

	-- fence round the whole plot, gap at the front
	local fences = model("Fence", m)
	local y0 = 1.0
	fence(fences, Vector3.new(-hw + 0.5, y0, -hd + 0.5), Vector3.new(-hw + 0.5, y0, hd - 0.5), cf)
	fence(fences, Vector3.new(hw - 0.5, y0, -hd + 0.5), Vector3.new(hw - 0.5, y0, hd - 0.5), cf)
	fence(fences, Vector3.new(-hw + 0.5, y0, hd - 0.5), Vector3.new(hw - 0.5, y0, hd - 0.5), cf)
	fence(fences, Vector3.new(-hw + 0.5, y0, -hd + 0.5), Vector3.new(-6, y0, -hd + 0.5), cf)
	fence(fences, Vector3.new(6, y0, -hd + 0.5), Vector3.new(hw - 0.5, y0, -hd + 0.5), cf)

	-- farm (x -31..3, z 6..34) with its own low fence and an opening toward the walkway
	local farm = part({ Name = "FarmFloor", Size = Vector3.new(34, 0.4, 28), CFrame = cf * CFrame.new(-14, 1.2, 20),
		Color = C.farm, Parent = m })
	farm:SetAttribute("IsFarm", true)
	fence(fences, Vector3.new(-31, y0, 5.5), Vector3.new(-20, y0, 5.5), cf)
	fence(fences, Vector3.new(-8, y0, 5.5), Vector3.new(3.5, y0, 5.5), cf)
	fence(fences, Vector3.new(3.5, y0, 5.5), Vector3.new(3.5, y0, 34.5), cf)

	rollMachine(m, cf * CFrame.new(-19, 1, -22), accent)
	-- row runs along the plot's Z; pedestals against the right fence, the gutter facing the walkway
	foodStand(m, cf * CFrame.new(20.5, 0, -6) * CFrame.Angles(0, math.rad(90), 0), accent)

	local spawnPad = part({ Name = "SpawnPad", Size = Vector3.new(8, 0.4, 8), CFrame = cf * CFrame.new(0, 0.2, -hd - 6),
		Color = accent, Parent = m })
	spawnPad:SetAttribute("IsSpawn", true)

	-- owner sign up on the back fence, facing the hub
	local board = part({ Name = "SignBoard", Size = Vector3.new(24, 5, 0.6), CFrame = cf * CFrame.new(0, 11, hd + 1) * CFrame.Angles(0, math.rad(180), 0),
		Color = C.purple, Parent = m })
	part({ Name = "SignTrim", Size = Vector3.new(25, 6, 0.4), CFrame = board.CFrame * CFrame.new(0, 0, -0.3), Color = C.gold, Parent = m })
	for _, x in { -10, 10 } do
		part({ Name = "SignLeg", Size = Vector3.new(1, 9, 1), CFrame = cf * CFrame.new(x, 5.5, hd + 1.4), Color = C.woodDark, Parent = m })
	end
	local owner = label(board, "Empty Plot", Enum.NormalId.Back, Color3.new(1, 1, 1))
	owner.Name = "OwnerLabel"

	local decor = model("Decor", m)
	local flowerColors = { Color3.fromRGB(232, 64, 72), Color3.fromRGB(160, 100, 240), Color3.fromRGB(255, 140, 200) }
	local rng = Random.new(index * 17)
	for i = 1, 6 do -- along the front, either side of the entrance
		local x = (if i % 2 == 0 then 1 else -1) * rng:NextNumber(9, 12)
		flower(decor, cf * CFrame.new(x, 1, -hd + rng:NextNumber(2, 6)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), flowerColors[i % 3 + 1])
	end
	barrel(decor, cf * CFrame.new(-28, 1, -33))
	barrel(decor, cf * CFrame.new(-25.6, 1, -32.4) * CFrame.Angles(0, 0.5, 0))
	return m
end

-- A hub wall segment along a line, with a studded lime trim on top.
-- An invisible barrier along the edge: the hills outside (BuildHills) are the boundary you see.
local function wall(parent: Instance, a: Vector3, b: Vector3)
	local dir = b - a
	local rot = CFrame.lookAt(Vector3.zero, dir)
	local mid = (a + b) / 2
	local w = part({ Name = "Wall", Size = Vector3.new(WALL_T, WALL_H * 3, dir.Magnitude + WALL_T), CFrame = CFrame.new(mid + Vector3.new(0, WALL_H * 1.5, 0)) * rot,
		Color = C.wall, Parent = parent })
	w.Transparency = 1
	w.CastShadow = false
end

-- ---------------------------------------------------------------- world

local function buildMaterials()
	local variant = MaterialService:FindFirstChild("Studs") :: MaterialVariant?
	if not variant then
		variant = Instance.new("MaterialVariant")
		variant.Name = "Studs"
		variant.Parent = MaterialService
	end
	local v = variant :: MaterialVariant
	v.BaseMaterial = Enum.Material.Plastic
	v.NormalMap = STUD_NORMAL
	v.StudsPerTile = 1
	v.MaterialPattern = Enum.MaterialPattern.Regular
	MaterialService:SetBaseMaterialOverride(Enum.Material.Plastic, "Studs")
end

local function buildLighting()
	pcall(function() -- not writable from every script context
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 96, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 135, 150)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 190, 130)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ShadowSoftness = 0.4
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.24
	atmo.Offset = 0.25
	atmo.Color = Color3.fromRGB(255, 190, 140)
	atmo.Decay = Color3.fromRGB(255, 120, 130)
	atmo.Glare = 0.3
	atmo.Haze = 0.6
	atmo.Parent = Lighting
	local cc = Lighting:FindFirstChild("Warmth") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
	cc.Name = "Warmth"
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 244, 235)
	cc.Parent = Lighting
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
end

local function build()
	for _, name in { "Map", "Plots" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	buildMaterials()
	buildLighting()

	local map = model("Map", workspace)
	-- open ocean all round, the hub island floor on it
	part({ Name = "Ocean", Size = Vector3.new(3000, 2, 3000), CFrame = CFrame.new(0, -5, 300), Color = C.water,
		Material = Enum.Material.SmoothPlastic, Transparency = 0.1, CanCollide = false, Parent = map })
	local x0, x1 = -HUB_W / 2, HUB_W / 2
	part({ Name = "HubFloor", Size = Vector3.new(HUB_W + WALL_T * 2, 6, HUB_FRONT - HUB_BACK + WALL_T * 2),
		CFrame = CFrame.new(0, -3, (HUB_BACK + HUB_FRONT) / 2), Color = C.hub, Parent = map })
	local walls = model("Walls", map)
	wall(walls, Vector3.new(x0 - WALL_T / 2, 0, HUB_BACK - WALL_T / 2), Vector3.new(x1 + WALL_T / 2, 0, HUB_BACK - WALL_T / 2))
	wall(walls, Vector3.new(x0 - WALL_T / 2, 0, HUB_BACK - WALL_T / 2), Vector3.new(x0 - WALL_T / 2, 0, HUB_FRONT + WALL_T / 2))
	wall(walls, Vector3.new(x1 + WALL_T / 2, 0, HUB_BACK - WALL_T / 2), Vector3.new(x1 + WALL_T / 2, 0, HUB_FRONT + WALL_T / 2))
	if GATE_W < HUB_W then
		wall(walls, Vector3.new(x0 - WALL_T / 2, 0, HUB_FRONT + WALL_T / 2), Vector3.new(-GATE_W / 2 - WALL_T / 2, 0, HUB_FRONT + WALL_T / 2))
		wall(walls, Vector3.new(GATE_W / 2 + WALL_T / 2, 0, HUB_FRONT + WALL_T / 2), Vector3.new(x1 + WALL_T / 2, 0, HUB_FRONT + WALL_T / 2))
	end

	-- neutral spawn in the middle of the front strip
	local spawn = part({ Class = "SpawnLocation", Name = "CenterSpawn", Size = Vector3.new(10, 0.4, 10),
		CFrame = CFrame.new(0, 0.2, 40), Color = C.purple, Parent = map }) :: SpawnLocation
	spawn.Duration = 0
	spawn.Neutral = true
	-- a dirt walkway from the plots' entrances out to the gate, and the start line in the gate
	part({ Name = "Walkway", Size = Vector3.new(HUB_W - 20, 0.3, 12), CFrame = CFrame.new(0, 0.15, 12), Color = C.path, Parent = map })
	part({ Name = "GatePath", Size = Vector3.new(24, 0.3, HUB_FRONT - 12), CFrame = CFrame.new(0, 0.15, (HUB_FRONT + 12) / 2 + 3), Color = C.path, Parent = map })
	local checks = math.floor(GATE_W / 10)
	for i = 0, checks - 1 do -- checkered start line across the gate
		part({ Name = "StartLine", Size = Vector3.new(GATE_W / checks, 0.35, 3), CFrame = CFrame.new(-GATE_W / 2 + GATE_W / checks * (i + 0.5), 0.18, HUB_FRONT - 2),
			Color = if i % 2 == 0 then Color3.new(1, 1, 1) else Color3.fromRGB(232, 64, 72), Parent = map })
	end
	-- decor along the front strip, clear of the walkway and the gate
	local decor = model("Decor", map)
	for i, x in { -200, -150, -110, 110, 150, 200 } do
		tree(decor, CFrame.new(x, 0, 78 - (i % 2) * 14), 1.2, i % 2 == 0)
	end
	for _, x in { -186, -128, 128, 186 } do
		barrel(decor, CFrame.new(x, 0, 52))
	end
	local rng = Random.new(5)
	local flowerColors = { Color3.fromRGB(232, 64, 72), Color3.fromRGB(160, 100, 240), Color3.fromRGB(255, 140, 200) }
	for i = 1, 40 do
		local x = rng:NextNumber(-210, 210)
		if math.abs(x) > GATE_W / 2 - 40 or rng:NextNumber() < 0.3 then
			flower(decor, CFrame.new(x, 0, rng:NextNumber(24, 90)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), flowerColors[i % 3 + 1])
		end
	end

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = workspace
	local plotZ = HUB_BACK + 27 + PLOT_D / 2 -- like the reference: a strip behind the plots
	for i = 1, PLOT_COUNT do
		local x = (i - (PLOT_COUNT + 1) / 2) * PLOT_SPACING
		-- rotated so the plot's local -Z (its entrance) faces the hub's open front (+Z)
		plot(plots, i, CFrame.new(x, 0, plotZ) * CFrame.Angles(0, math.pi, 0))
		task.wait()
	end
	return #plots:GetChildren()
end

return build()
