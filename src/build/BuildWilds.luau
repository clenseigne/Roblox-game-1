-- Edit-time builder for Workspace.Wilds: the runway out of the hub's front gate (laid out like
-- Steal An Egg's): a walled corridor over the ocean split into themed zones, each ZONE_D deep and
-- tougher than the last. Every zone has tall-grass patches between dirt trails (the first zone's
-- look, scaled up), an arch with its name and weight range, and its own decor. Rebuilt from
-- scratch each run. Plastic everywhere so the place's stud MaterialVariant gives it the stud look.
--   Wilds.Zone            invisible box over the whole runway (server: are you in the Wilds?)
--   Wilds.BrushZones.*    invisible boxes over the tall grass, with MinWeight/MaxWeight attributes (kg)
--   Wilds.Brush.Tuft      the walk-through grass tufts (client: rustle when you push through)

local FONT = Enum.Font.FredokaOne
local START_Z = 100 -- just past the hub's front wall (BuildMap HUB_FRONT + wall)
local WIDTH = 436 -- corridor interior: as wide as the hub (BuildMap HUB_W)
local TUFT_STEP = 4.2 -- grass tuft spacing
local ZONE_D = 150
local WALL_H, WALL_T = 30, 8
local WALL = Color3.fromRGB(204, 118, 84)
local TRIM = Color3.fromRGB(132, 214, 72)
local INK = Color3.fromRGB(30, 21, 48)
local PATH = Color3.fromRGB(196, 160, 104)
local GOLD = Color3.fromRGB(255, 201, 60)

type Theme = {
	name: string,
	weights: { number }, -- kg range of the wild monsters here
	species: string, -- comma list of wild monsters / pets that live here
	floor: Color3,
	brush: { Color3 },
	sign: Color3,
	decor: string, -- meadow | beach | desert | snow
}
local ZONES: { Theme } = {
	{ name = "MEADOW", weights = { 6, 20 }, species = "Verity,Slime,Shroom,Boar,Beetle", floor = Color3.fromRGB(118, 156, 62), sign = Color3.fromRGB(70, 140, 50),
		brush = { Color3.fromRGB(86, 168, 58), Color3.fromRGB(66, 140, 48), Color3.fromRGB(112, 188, 70) }, decor = "meadow" },
	{ name = "BEACH", weights = { 18, 55 }, species = "Slime,Boar,Hippo,TRex", floor = Color3.fromRGB(240, 214, 150), sign = Color3.fromRGB(60, 160, 220),
		brush = { Color3.fromRGB(150, 190, 80), Color3.fromRGB(120, 170, 70), Color3.fromRGB(190, 200, 100) }, decor = "beach" },
	{ name = "DESERT", weights = { 50, 140 }, species = "Hippo,TRex", floor = Color3.fromRGB(226, 170, 100), sign = Color3.fromRGB(214, 110, 60),
		brush = { Color3.fromRGB(176, 156, 82), Color3.fromRGB(150, 130, 70), Color3.fromRGB(198, 176, 100) }, decor = "desert" },
	{ name = "SNOWPEAK", weights = { 130, 320 }, species = "Hippo,TRex", floor = Color3.fromRGB(226, 238, 248), sign = Color3.fromRGB(110, 150, 230),
		brush = { Color3.fromRGB(150, 200, 210), Color3.fromRGB(120, 176, 196), Color3.fromRGB(210, 236, 244) }, decor = "snow" },
}

-- tall-grass patches in zone-local fractions (x: -1..1 across, z: 0..1 along), with trails between
local PATCHES = {
	{ -0.95, 0.06, -0.38, 0.40 },
	{ 0.12, 0.04, 0.95, 0.30 },
	{ -0.15, 0.44, 0.70, 0.66 },
	{ -0.95, 0.52, -0.40, 0.92 },
	{ 0.30, 0.74, 0.95, 0.96 },
}

local rng = Random.new(7)

local function part(props: { [string]: any }): BasePart
	local p: BasePart = Instance.new(props.Class or "Part") :: BasePart
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

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function ghost(p: BasePart)
	p.Transparency = 1
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
end

local function label(board: BasePart, text: string, size: number?)
	for _, side in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = side
		gui.PixelsPerStud = size or 40
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = FONT
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = INK
		stroke.Parent = t
		t.Parent = gui
		gui.Parent = board
	end
end

-- An invisible barrier along the edge: the hills outside (BuildHills) are the boundary you see.
local function wall(parent: Instance, a: Vector3, b: Vector3)
	local dir = b - a
	local rot = CFrame.lookAt(Vector3.zero, dir)
	local mid = (a + b) / 2
	local w = part({ Name = "Wall", Size = Vector3.new(WALL_T, WALL_H * 3, dir.Magnitude + WALL_T), CFrame = CFrame.new(mid + Vector3.new(0, WALL_H * 1.5, 0)) * rot,
		Color = WALL, Parent = parent })
	w.Transparency = 1
	w.CastShadow = false
end

-- ---------------------------------------------------------------- decor kits

local function roundTree(parent: Instance, pos: Vector3, s: number, leaf1: Color3, leaf2: Color3, trunk: Color3)
	local m = model("Tree", parent)
	local cf = CFrame.new(pos)
	part({ Name = "Trunk", Size = Vector3.new(1.6, 6, 1.6) * s, CFrame = cf * CFrame.new(0, 3 * s, 0), Color = trunk, Parent = m })
	for i, b in { { 0, 7, 0, 6 }, { 1.8, 8.6, 0.6, 4.4 }, { -1.6, 8.8, -0.8, 4 } } do
		part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * b[4] * s, CFrame = cf * CFrame.new(b[1] * s, b[2] * s, b[3] * s),
			Color = if i == 1 then leaf1 else leaf2, Parent = m })
	end
end

local function pine(parent: Instance, pos: Vector3, s: number, leaf1: Color3, leaf2: Color3, trunk: Color3)
	local m = model("Tree", parent)
	local cf = CFrame.new(pos)
	part({ Name = "Trunk", Size = Vector3.new(1.6, 6, 1.6) * s, CFrame = cf * CFrame.new(0, 3 * s, 0), Color = trunk, Parent = m })
	for i = 1, 4 do
		local w = (7 - i * 1.4) * s
		part({ Name = "Leaves", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8 * s, w, w),
			CFrame = cf * CFrame.new(0, (4.5 + i * 1.7) * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i % 2 == 0 then leaf2 else leaf1, Parent = m })
	end
end

local function palm(parent: Instance, pos: Vector3, s: number)
	local m = model("Palm", parent)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-12, 12)))
	local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0) * lean
	for i = 0, 5 do
		part({ Name = "Trunk", Size = Vector3.new(1.4 - i * 0.08, 1.8, 1.4 - i * 0.08) * s, CFrame = cf * CFrame.new(0, (0.9 + i * 1.75) * s, 0)
			* CFrame.Angles(0, i * 0.5, 0), Color = if i % 2 == 0 then Color3.fromRGB(150, 100, 60) else Color3.fromRGB(128, 84, 50), Parent = m })
	end
	local top = cf * CFrame.new(0, 11 * s, 0)
	for i = 0, 5 do
		local a = i * math.pi / 3
		part({ Name = "Frond", Class = "WedgePart", Size = Vector3.new(1.6 * s, 0.6 * s, 6 * s),
			CFrame = top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -3 * s) * CFrame.Angles(math.rad(-18), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(70, 170, 70) else Color3.fromRGB(96, 196, 80), Parent = m })
	end
	part({ Name = "Coconut", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1 * s, CFrame = top * CFrame.new(0.6 * s, -0.6 * s, 0),
		Color = Color3.fromRGB(110, 70, 40), Parent = m })
end

local function cactus(parent: Instance, pos: Vector3, s: number)
	local m = model("Cactus", parent)
	local green, dark = Color3.fromRGB(80, 160, 70), Color3.fromRGB(60, 132, 56)
	local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	part({ Name = "Body", Size = Vector3.new(2, 8, 2) * s, CFrame = cf * CFrame.new(0, 4 * s, 0), Color = green, Parent = m })
	for _, side in { -1, 1 } do
		local h = rng:NextNumber(3, 5)
		part({ Name = "Arm", Size = Vector3.new(2.4, 1.2, 1.2) * s, CFrame = cf * CFrame.new(side * 1.8 * s, h * s, 0), Color = dark, Parent = m })
		part({ Name = "Arm", Size = Vector3.new(1.2, 2.8, 1.2) * s, CFrame = cf * CFrame.new(side * 2.6 * s, (h + 1.2) * s, 0), Color = green, Parent = m })
	end
	part({ Name = "Flower", Size = Vector3.new(0.8, 0.5, 0.8) * s, CFrame = cf * CFrame.new(0, 8.2 * s, 0), Color = Color3.fromRGB(255, 120, 170), Parent = m })
end

local function rock(parent: Instance, pos: Vector3, s: number, c1: Color3, c2: Color3)
	local m = model("Rock", parent)
	part({ Name = "Rock", Size = Vector3.new(3, 2, 2.6) * s, CFrame = CFrame.new(pos + Vector3.new(0, s, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Color = c1, Parent = m })
	part({ Name = "Rock", Size = Vector3.new(1.8, 1.4, 1.8) * s, CFrame = CFrame.new(pos + Vector3.new(1.4 * s, 0.7 * s, 0.8 * s)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Color = c2, Parent = m })
end

local function flower(parent: Instance, pos: Vector3, color: Color3)
	local m = model("Flower", parent)
	part({ Name = "Center", Size = Vector3.new(0.6, 0.3, 0.6), CFrame = CFrame.new(pos + Vector3.new(0, 0.35, 0)), Color = GOLD, Parent = m })
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		part({ Name = "Petal", Size = Vector3.new(0.7, 0.2, 0.7), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 0.55, 0.3, math.sin(a) * 0.55)) * CFrame.Angles(0, a, 0),
			Color = color, Parent = m })
	end
end

local FLOWERS = { Color3.fromRGB(232, 64, 72), Color3.fromRGB(160, 100, 240), Color3.fromRGB(255, 140, 200) }
local function decorate(kind: string, parent: Instance, pos: Vector3)
	local s = rng:NextNumber(0.9, 1.3)
	if kind == "meadow" then
		if rng:NextNumber() < 0.5 then
			roundTree(parent, pos, s, Color3.fromRGB(122, 79, 224), Color3.fromRGB(146, 104, 240), Color3.fromRGB(78, 42, 30))
		else
			pine(parent, pos, s, Color3.fromRGB(122, 79, 224), Color3.fromRGB(146, 104, 240), Color3.fromRGB(78, 42, 30))
		end
	elseif kind == "beach" then
		palm(parent, pos, s)
	elseif kind == "desert" then
		cactus(parent, pos, s)
	else
		pine(parent, pos, s, Color3.fromRGB(60, 120, 90), Color3.fromRGB(236, 244, 250), Color3.fromRGB(96, 70, 56))
	end
end

local function smallDecor(kind: string, parent: Instance, pos: Vector3)
	if kind == "meadow" then
		if rng:NextNumber() < 0.6 then
			flower(parent, pos, FLOWERS[rng:NextInteger(1, 3)])
		else
			rock(parent, pos, rng:NextNumber(0.7, 1.3), Color3.fromRGB(150, 146, 160), Color3.fromRGB(116, 112, 128))
		end
	elseif kind == "beach" then
		if rng:NextNumber() < 0.5 then -- shell / starfish
			part({ Name = "Starfish", Size = Vector3.new(1.4, 0.3, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				Color = Color3.fromRGB(255, 130, 100), Parent = parent })
		else
			rock(parent, pos, rng:NextNumber(0.6, 1.1), Color3.fromRGB(210, 196, 170), Color3.fromRGB(180, 166, 140))
		end
	elseif kind == "desert" then
		rock(parent, pos, rng:NextNumber(0.8, 1.6), Color3.fromRGB(196, 120, 76), Color3.fromRGB(170, 100, 62))
	else
		rock(parent, pos, rng:NextNumber(0.8, 1.5), Color3.fromRGB(170, 210, 236), Color3.fromRGB(220, 236, 248))
	end
end

-- ----------------------------------------------------------------------------------------------

local old = workspace:FindFirstChild("Wilds")
if old then
	old:Destroy()
end
local wilds = Instance.new("Model")
wilds.Name = "Wilds"
local zones = Instance.new("Folder")
zones.Name = "BrushZones"
zones.Parent = wilds
local brush = Instance.new("Folder")
brush.Name = "Brush"
brush.Parent = wilds
local walls = model("Walls", wilds)
local decor = model("Decor", wilds)
wilds.Parent = workspace

local hw = WIDTH / 2
local endZ = START_Z + #ZONES * ZONE_D
local zone = part({ Name = "Zone", Size = Vector3.new(WIDTH, 40, endZ - START_Z + 4), CFrame = CFrame.new(0, 20, (START_Z - 4 + endZ) / 2), Parent = wilds })
ghost(zone)
-- corridor walls, from the hub's gate to the far end
wall(walls, Vector3.new(-hw - WALL_T / 2, 0, START_Z - 8), Vector3.new(-hw - WALL_T / 2, 0, endZ + WALL_T / 2))
wall(walls, Vector3.new(hw + WALL_T / 2, 0, START_Z - 8), Vector3.new(hw + WALL_T / 2, 0, endZ + WALL_T / 2))
wall(walls, Vector3.new(-hw - WALL_T / 2, 0, endZ + WALL_T / 2), Vector3.new(hw + WALL_T / 2, 0, endZ + WALL_T / 2))
-- a gap floor between the hub's gate and the first zone
part({ Name = "GateFloor", Size = Vector3.new(WIDTH + WALL_T * 2, 6, 14), CFrame = CFrame.new(0, -3, START_Z - 3), Color = Color3.fromRGB(150, 186, 74), Parent = wilds })

local tufts = 0
for zi, theme in ZONES do
	local z0 = START_Z + (zi - 1) * ZONE_D
	local mid = z0 + ZONE_D / 2
	part({ Name = "Floor" .. zi, Size = Vector3.new(WIDTH + WALL_T * 2, 6, ZONE_D), CFrame = CFrame.new(0, -2.8, mid), Color = theme.floor, Parent = wilds })
	-- dirt trail snaking up the middle
	for _, seg in { { 0, 0.0, 0.14, 0.5 }, { -0.1, 0.4, 0.14, 0.3 }, { 0.15, 0.62, 0.14, 0.38 }, { -0.35, 0.36, 0.5, 0.1 }, { 0.5, 0.68, 0.5, 0.08 } } do
		-- the runs along the runway keep a fixed width; the cross trails stretch with it
		local x, zf, w, d = seg[1] * hw, seg[2], if seg[3] < 0.3 then 20 else seg[3] * WIDTH, seg[4] * ZONE_D
		part({ Name = "Trail", Size = Vector3.new(w, 0.4, d), CFrame = CFrame.new(x, 0.4, z0 + (zf + seg[4] / 2) * ZONE_D),
			Color = if theme.decor == "snow" then Color3.fromRGB(176, 190, 206) else PATH, Parent = wilds })
	end
	-- zone arch: name and weight range
	local arch = model("Arch" .. zi, wilds)
	for _, x in { -18, 18 } do
		part({ Name = "ArchPost", Size = Vector3.new(1.6, 13, 1.6), CFrame = CFrame.new(x, 6.5, z0 + 2), Color = Color3.fromRGB(78, 42, 30), Parent = arch })
	end
	local board = part({ Name = "Sign", Size = Vector3.new(34, 5, 0.8), CFrame = CFrame.new(0, 13, z0 + 2), Color = theme.sign, Parent = arch })
	part({ Name = "SignTrim", Size = Vector3.new(35.4, 6.2, 0.5), CFrame = CFrame.new(0, 13, z0 + 2.4), Color = GOLD, Parent = arch })
	label(board, string.format("%s   %d-%d kg", theme.name, theme.weights[1], theme.weights[2]))

	-- brush patches
	for pi, p in PATCHES do
		local px0, px1 = p[1] * (hw - 4), p[3] * (hw - 4)
		local pz0, pz1 = z0 + 8 + p[2] * (ZONE_D - 12), z0 + 8 + p[4] * (ZONE_D - 12)
		local box = part({ Name = "BrushZone" .. zi .. "_" .. pi, Size = Vector3.new(px1 - px0, 8, pz1 - pz0),
			CFrame = CFrame.new((px0 + px1) / 2, 4, (pz0 + pz1) / 2), Parent = zones })
		ghost(box)
		box:SetAttribute("MinWeight", theme.weights[1])
		box:SetAttribute("MaxWeight", theme.weights[2])
		box:SetAttribute("Zone", theme.name)
		box:SetAttribute("Species", theme.species)
		local patch = Instance.new("Folder")
		patch.Name = "Patch" .. zi .. "_" .. pi
		for x = px0 + 2, px1 - 2, TUFT_STEP do
			for zz = pz0 + 2, pz1 - 2, TUFT_STEP do
				local h = rng:NextNumber(2.6, 4.0)
				local w = rng:NextNumber(3.2, 4.0)
				local t = part({
					Name = "Tuft",
					Size = Vector3.new(w, h, w),
					CFrame = CFrame.new(x + rng:NextNumber(-0.8, 0.8), 0.2 + h / 2, zz + rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
					Color = theme.brush[rng:NextInteger(1, 3)],
					Parent = patch,
				})
				t.CanCollide, t.CanQuery, t.CanTouch = false, false, false
				tufts += 1
			end
		end
		patch.Parent = brush
		task.wait()
	end

	-- decor outside the patches: big things along the walls, small things scattered
	local function inPatch(x: number, z: number, pad: number): boolean
		for _, p in PATCHES do
			local px0, px1 = p[1] * (hw - 4), p[3] * (hw - 4)
			local pz0, pz1 = z0 + 8 + p[2] * (ZONE_D - 12), z0 + 8 + p[4] * (ZONE_D - 12)
			if x > px0 - pad and x < px1 + pad and z > pz0 - pad and z < pz1 + pad then
				return true
			end
		end
		return false
	end
	local zoneDecor = model("Zone" .. zi, decor)
	for _ = 1, 40 do
		local x, z = rng:NextNumber(-hw + 5, hw - 5), rng:NextNumber(z0 + 10, z0 + ZONE_D - 6)
		if not inPatch(x, z, 4) and math.abs(x) > 12 then
			decorate(theme.decor, zoneDecor, Vector3.new(x, 0.2, z))
		end
	end
	for _ = 1, 80 do
		local x, z = rng:NextNumber(-hw + 3, hw - 3), rng:NextNumber(z0 + 6, z0 + ZONE_D - 4)
		if not inPatch(x, z, 1.5) then
			smallDecor(theme.decor, zoneDecor, Vector3.new(x, 0.2, z))
		end
	end
	task.wait()
end

-- "more to come" sign on the far wall
local sign = part({ Name = "EndSign", Size = Vector3.new(30, 5, 0.8), CFrame = CFrame.new(0, 12, endZ - 1), Color = Color3.fromRGB(124, 77, 255), Parent = wilds })
for _, x in { -13, 13 } do
	part({ Name = "EndPost", Size = Vector3.new(1.6, 14, 1.6), CFrame = CFrame.new(x, 7, endZ - 1), Color = Color3.fromRGB(78, 42, 30), Parent = wilds })
end
label(sign, "MORE ZONES COMING SOON!")

return string.format("Wilds runway built: %d zones, %d tufts", #ZONES, tufts)
