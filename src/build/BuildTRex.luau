-- Builds a chunky, studded, LEGO-style T-rex out of plain Parts and WedgeParts (no meshes or
-- unions). Every part has whole-stud sizes and whole-stud corners, so it all sits on a 1-stud
-- grid. Classic SurfaceType studs don't render in current Studio (and this place overrides
-- Plastic with an all-faces stud variant), so parts use a plain Plastic variant plus a
-- repeating stud Texture on their top faces; TopSurface/BottomSurface are still set to
-- Studs/Inlet. Faces -Z. Lives in workspace as Model "TRex" with sub-models Head, Jaw, Body, Tail,
-- LeftLeg, RightLeg, LeftArm, RightArm; PrimaryPart = HumanoidRootPart (hidden, in the hips).
--
-- Tweak the numbers below and re-run. Coordinates are studs relative to ORIGIN, which is the
-- ground point under the front of the hips; x = the T-rex's right, y = up, z = toward the tail.

local ORIGIN = CFrame.new(-80, 0, -80)
local RIG = true -- add Motor6Ds (jaw, neck, legs, arms, tail) for animating later
local STUD_TEXTURE = "rbxassetid://98595611474582" -- transparent stud tile (art/ui/stud_tile.png)
local PLAIN_VARIANT = "PlainPlastic" -- created if missing: Plastic without the place's stud override

-- colors
local GREEN = Color3.fromRGB(75, 151, 75)
local DARK_GREEN = Color3.fromRGB(39, 104, 52)
local BELLY = Color3.fromRGB(178, 221, 112)
local WHITE = Color3.fromRGB(248, 248, 248)
local YELLOW = Color3.fromRGB(245, 205, 48)
local BLACK = Color3.fromRGB(27, 42, 53)
local MOUTH = Color3.fromRGB(150, 38, 52)

-- body (y = bottom/top heights, z = lengths front-to-back)
local BODY_W = 8 -- hips and chest width
local BODY_BOTTOM = 9
local HIP_TOP = 15 -- plus a 1-stud wedge sloping back
local HIP_LEN = 5
local CHEST_TOP = 17
local CHEST_LEN = 5

-- neck and head
local NECK_W, NECK_BOTTOM, NECK_TOP, NECK_LEN = 6, 11, 17, 3
local SKULL_W, SKULL_LEN, SKULL_TOP = 8, 3, 18
local SNOUT_W, SNOUT_LEN = 6, 6
local SNOUT_BOTTOM = 14 -- skull bottom too; the snout top is SKULL_TOP - 1 plus a wedge
local JAW_OPEN = 2 -- gap between the snout and the lower jaw
local JAW_H = 2

-- legs (one side; the other is mirrored)
local FOOT_H, SHIN_H, THIGH_H = 1, 5, 6
local THIGH_W, SHIN_W, FOOT_W = 3, 2, 5
local SHIN_LEN, TOE_LEN = 3, 3

-- arms
local UPPER_ARM_H, FOREARM_LEN = 2, 3

-- tail segments, hips outward: { width, height, length }; each top is 1 lower than the last
local TAIL = { { 6, 4, 3 }, { 4, 3, 3 }, { 4, 2, 2 }, { 2, 2, 2 }, { 2, 1, 3 } }

-- ----------------------------------------------------------------------------------------------

local old = workspace:FindFirstChild("TRex")
if old then
	old:Destroy()
end

local MaterialService = game:GetService("MaterialService")
if not MaterialService:FindFirstChild(PLAIN_VARIANT) then
	local v = Instance.new("MaterialVariant")
	v.Name = PLAIN_VARIANT
	v.BaseMaterial = Enum.Material.Plastic
	v.Parent = MaterialService
end

local trex = Instance.new("Model")
trex.Name = "TRex"
local groups = {}
for _, name in { "Body", "Head", "Jaw", "Tail", "LeftLeg", "RightLeg", "LeftArm", "RightArm" } do
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = trex
	groups[name] = m
end

-- A block (or wedge) from its min corner and size. Wedges slope down toward the tail by default
-- (high side at -z); highAt = "back" puts the high side toward the tail (+z) instead.
local function block(group: string, name: string, x0: number, y0: number, z0: number, sx: number, sy: number, sz: number,
	color: Color3, wedge: string?): BasePart
	local p = Instance.new(if wedge then "WedgePart" else "Part")
	p.Name = name
	p.Size = Vector3.new(sx, sy, sz)
	-- a WedgePart's high (vertical) face is its Back face (+Z); turn it around for "front"
	local turn = if wedge == "front" then CFrame.Angles(0, math.pi, 0) else CFrame.identity
	p.CFrame = ORIGIN * CFrame.new(x0 + sx / 2, y0 + sy / 2, z0 + sz / 2) * turn
	p.Anchored = true
	p.Material = Enum.Material.Plastic
	p.MaterialVariant = PLAIN_VARIANT
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	if not wedge then -- slopes stay smooth, like real slope bricks
		local t = Instance.new("Texture")
		t.Name = "Studs"
		t.Texture = STUD_TEXTURE
		t.Face = Enum.NormalId.Top
		t.StudsPerTileU, t.StudsPerTileV = 1, 1
		t.Parent = p
	end
	p.Parent = groups[group]
	return p
end

-- The same block on the right (+x, as given) and mirrored onto the left.
local function pair(side: string, name: string, x0: number, y0: number, z0: number, sx: number, sy: number, sz: number,
	color: Color3, wedge: string?): (BasePart, BasePart)
	local r = block("Right" .. side, name, x0, y0, z0, sx, sy, sz, color, wedge)
	local l = block("Left" .. side, name, -(x0 + sx), y0, z0, sx, sy, sz, color, wedge)
	return r, l
end

local half = BODY_W / 2

-- ---------------------------------------------------------------- body
-- z runs front (-) to back (+): snout | skull | neck | chest | hips | tail
local hipZ = 0
local chestZ = hipZ - CHEST_LEN
local neckZ = chestZ - NECK_LEN
local skullZ = neckZ - SKULL_LEN + 1 -- the skull overlaps the neck by a stud
local snoutZ = skullZ - SNOUT_LEN

local hips = block("Body", "Hips", -half, BODY_BOTTOM, hipZ, BODY_W, HIP_TOP - BODY_BOTTOM, HIP_LEN, GREEN)
block("Body", "HipSlope", -half, HIP_TOP, hipZ, BODY_W, 1, HIP_LEN, GREEN, "front")
local chest = block("Body", "Chest", -half, BODY_BOTTOM, chestZ, BODY_W, CHEST_TOP - BODY_BOTTOM, CHEST_LEN, GREEN)
block("Body", "Belly", -half + 1, BODY_BOTTOM - 1, chestZ, BODY_W - 2, 1, CHEST_LEN + HIP_LEN - 1, BELLY)
block("Body", "ChestPlate", -half + 1, BODY_BOTTOM - 1, chestZ - 1, BODY_W - 2, NECK_BOTTOM - BODY_BOTTOM + 1, 1, BELLY)
for i = 0, CHEST_LEN - 1, 2 do -- spine ridges
	block("Body", "Ridge", -1, CHEST_TOP, chestZ + i, 2, 1, 1, DARK_GREEN)
end
local root = block("Body", "HumanoidRootPart", -1, BODY_BOTTOM + 2, hipZ + 1, 2, 2, 2, GREEN)
root.Transparency = 1
root.CanCollide = false
local neck = block("Head", "Neck", -NECK_W / 2, NECK_BOTTOM, neckZ, NECK_W, NECK_TOP - NECK_BOTTOM, NECK_LEN, GREEN)
block("Head", "Throat", -NECK_W / 2 + 1, NECK_BOTTOM - 1, neckZ, NECK_W - 2, 1, NECK_LEN - 1, BELLY)

-- ---------------------------------------------------------------- head
local skull = block("Head", "Skull", -SKULL_W / 2, SNOUT_BOTTOM, skullZ, SKULL_W, SKULL_TOP - SNOUT_BOTTOM, SKULL_LEN, GREEN)
local sw = SNOUT_W / 2
block("Head", "Snout", -sw, SNOUT_BOTTOM, snoutZ, SNOUT_W, SKULL_TOP - 1 - SNOUT_BOTTOM, SNOUT_LEN, GREEN)
block("Head", "SnoutSlope", -sw, SKULL_TOP - 1, snoutZ, SNOUT_W, 1, SNOUT_LEN, GREEN, "back")
-- eyes: yellow, with a black pupil block looking forward, under a brow ridge sloping to the front
local sk = SKULL_W / 2
block("Head", "BrowR", sk, SKULL_TOP - 1, skullZ, 1, 1, 2, DARK_GREEN, "back")
block("Head", "BrowL", -sk - 1, SKULL_TOP - 1, skullZ, 1, 1, 2, DARK_GREEN, "back")
for _, s in { 1, -1 } do -- a 2x2 eye on each side of the skull: pupil in the front-upper corner
	local x = if s > 0 then sk else -sk - 1
	block("Head", "Eye", x, SNOUT_BOTTOM + 1, skullZ, 1, 1, 2, YELLOW)
	block("Head", "Eye", x, SNOUT_BOTTOM + 2, skullZ + 1, 1, 1, 1, YELLOW)
	block("Head", "Pupil", x, SNOUT_BOTTOM + 2, skullZ, 1, 1, 1, BLACK)
end
-- upper teeth hang from the snout: two in front, then every other stud down both sides
local jawTop = SNOUT_BOTTOM - JAW_OPEN
block("Head", "Tooth", 1, SNOUT_BOTTOM - 1, snoutZ, 1, 1, 1, WHITE)
block("Head", "Tooth", -2, SNOUT_BOTTOM - 1, snoutZ, 1, 1, 1, WHITE)
for z = snoutZ + 2, snoutZ + SNOUT_LEN - 2, 2 do
	block("Head", "Tooth", sw - 1, SNOUT_BOTTOM - 1, z, 1, 1, 1, WHITE)
	block("Head", "Tooth", -sw, SNOUT_BOTTOM - 1, z, 1, 1, 1, WHITE)
end
-- dark mouth inside, so you can't see through the open jaw
block("Head", "MouthInside", -sw + 1, jawTop, snoutZ + 2, SNOUT_W - 2, JAW_OPEN, (neckZ - 1) - (snoutZ + 2), MOUTH)

-- ---------------------------------------------------------------- jaw
local jawZ = snoutZ + 1 -- a stud shorter than the snout
local jawLen = neckZ - jawZ -- reaches back to the neck
local jaw = block("Jaw", "LowerJaw", -sw, jawTop - JAW_H, jawZ, SNOUT_W, JAW_H, jawLen, GREEN)
block("Jaw", "Chin", -sw + 1, jawTop - JAW_H - 1, jawZ + 1, SNOUT_W - 2, 1, jawLen - 2, BELLY)
block("Jaw", "Hinge", -sw, jawTop, neckZ - 1, SNOUT_W, JAW_OPEN, 1, GREEN) -- closes the corner of the mouth
-- lower teeth stand between the upper ones
block("Jaw", "Tooth", -1, jawTop, jawZ, 1, 1, 1, WHITE)
block("Jaw", "Tooth", 0, jawTop, jawZ, 1, 1, 1, WHITE)
for z = jawZ, neckZ - 3, 2 do
	block("Jaw", "Tooth", sw - 1, jawTop, z, 1, 1, 1, WHITE)
	block("Jaw", "Tooth", -sw, jawTop, z, 1, 1, 1, WHITE)
end

-- ---------------------------------------------------------------- legs
local thighY = FOOT_H + SHIN_H
local shinZ = hipZ + HIP_LEN - SHIN_LEN -- shins sit under the back of the thighs
local footX = half - 1
pair("Leg", "Thigh", half, thighY, hipZ, THIGH_W, THIGH_H, HIP_LEN, GREEN)
pair("Leg", "Shin", half + THIGH_W - SHIN_W, FOOT_H, shinZ, SHIN_W, SHIN_H, SHIN_LEN, GREEN) -- narrower: a knee step
pair("Leg", "Heel", footX, 0, shinZ, FOOT_W, FOOT_H, SHIN_LEN, GREEN)
for i = 0, 2 do -- three toes with gaps, each with a claw
	local x = footX + i * 2
	pair("Leg", "Toe", x, 0, shinZ - TOE_LEN, 1, FOOT_H, TOE_LEN, GREEN)
	pair("Leg", "Claw", x, 0, shinZ - TOE_LEN - 1, 1, FOOT_H, 1, WHITE, "back")
end

-- ---------------------------------------------------------------- arms
local armZ = chestZ + 1
pair("Arm", "UpperArm", half, BODY_BOTTOM + 1, armZ, 1, UPPER_ARM_H, 1, GREEN)
pair("Arm", "Forearm", half, BODY_BOTTOM, armZ - FOREARM_LEN + 1, 1, 1, FOREARM_LEN, GREEN)
pair("Arm", "Claw", half, BODY_BOTTOM, armZ - FOREARM_LEN, 1, 1, 1, WHITE, "back")

-- ---------------------------------------------------------------- tail
local tailParts = {}
local z = hipZ + HIP_LEN
local top = HIP_TOP - 1
for i, seg in TAIL do
	local w, h, len = seg[1], seg[2], seg[3]
	local p = block("Tail", "Tail" .. i, -w / 2, top - h, z, w, h, len, GREEN)
	block("Tail", "TailSlope" .. i, -w / 2, top, z, w, 1, len, GREEN, "front")
	table.insert(tailParts, p)
	z += len
	top -= 1
end

-- ---------------------------------------------------------------- finish
trex.PrimaryPart = root
trex.WorldPivot = root.CFrame
trex.Parent = workspace

local count = 0
for _, d in trex:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end

if RIG then
	-- Each group is welded to its main part, which hangs off a Motor6D at its joint. Everything
	-- stays anchored; unanchor all but the HumanoidRootPart to play animations.
	local function weldGroup(groupName: string, main: BasePart)
		for _, p in groups[groupName]:GetDescendants() do
			if p:IsA("BasePart") and p ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = main, p
				w.Parent = p
			end
		end
	end
	local function motor(name: string, part0: BasePart, part1: BasePart, jointLocal: Vector3)
		local joint = ORIGIN * CFrame.new(jointLocal)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0, m.Part1 = part0, part1
		m.C0 = part0.CFrame:ToObjectSpace(joint)
		m.C1 = part1.CFrame:ToObjectSpace(joint)
		m.Parent = part0
	end
	weldGroup("Body", root)
	weldGroup("Head", neck)
	weldGroup("Jaw", jaw)
	motor("Neck", root, neck, Vector3.new(0, NECK_BOTTOM + 2, chestZ))
	motor("Jaw", neck, jaw, Vector3.new(0, jawTop, neckZ - 1))
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local leg = groups[side .. "Leg"]
		local thigh = leg:FindFirstChild("Thigh") :: BasePart
		weldGroup(side .. "Leg", thigh)
		motor(side .. "Hip", root, thigh, Vector3.new(s * (half + THIGH_W / 2), thighY + THIGH_H - 1, hipZ + HIP_LEN / 2))
		local arm = groups[side .. "Arm"]
		local upper = arm:FindFirstChild("UpperArm") :: BasePart
		weldGroup(side .. "Arm", upper)
		motor(side .. "Shoulder", root, upper, Vector3.new(s * (half + 0.5), BODY_BOTTOM + UPPER_ARM_H + 1, armZ + 0.5))
	end
	-- tail: a chain, each segment (with its slope) swinging from the one before
	local prev, jz = root, hipZ + HIP_LEN
	for i, p in tailParts do
		local slope = groups.Tail:FindFirstChild("TailSlope" .. i) :: BasePart
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = p, slope
		w.Parent = slope
		motor("Tail" .. i, prev, p, Vector3.new(0, p.Position.Y - ORIGIN.Y, jz))
		prev = p
		jz += TAIL[i][3]
	end
end

return string.format("TRex built: %d parts, %s", count, if RIG then "rigged" else "not rigged")
