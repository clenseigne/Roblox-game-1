-- Edit-time builder for Workspace.Map.Hills: cartoon cliffs (blender/hills.py's kit) on green land
-- along both sides of the hub and behind the plots, dressed with pines on their grass tops and
-- rocks, mushrooms, barrels, fences and grass tufts round their feet.
--
-- The kit: import assets/HillKit.fbx into Workspace (it arrives as Workspace.HillKit), then run
-- this. The first run splits it into ServerStorage.HillKit.<Piece> models (parts named
-- "Piece-Part_HEX" -> Part, colored, SmoothPlastic, pivot at the bottom center) and deletes the
-- import; later runs reuse ServerStorage.HillKit. Rebuilds Map.Hills from scratch every run.
local ServerStorage = game:GetService("ServerStorage")

-- hub layout (BuildMap): interior x -218..218, z -96..96, walls 8 thick and 30 tall
local HUB_X, HUB_BACK, HUB_FRONT, WALL_T = 218, -96, 96, 8
local WILDS_END = 100 + 4 * 150 -- BuildWilds START_Z + zones * ZONE_D
local LAND = Color3.fromRGB(70, 214, 58)
local LAND_EDGE = Color3.fromRGB(150, 98, 58)

local rng = Random.new(21)

local function prepareKit(): Folder?
	local kit = ServerStorage:FindFirstChild("HillKit") :: Folder?
	local import = workspace:FindFirstChild("HillKit")
	if import and import:IsA("Model") then
		if kit then
			kit:Destroy()
		end
		kit = Instance.new("Folder")
		kit.Name = "HillKit"
		local models: { [string]: Model } = {}
		for _, d in import:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				d:Destroy()
			end
		end
		for _, p in import:GetDescendants() do
			if p:IsA("BasePart") then
				local piece, part, hex = string.match(p.Name, "^(%w+)%-(%w+)_(%x%x%x%x%x%x)")
				if piece then
					local m = models[piece]
					if not m then
						m = Instance.new("Model")
						m.Name = piece
						models[piece] = m
					end
					p.Name = part
					p.Color = Color3.fromHex(hex)
					p.Material = Enum.Material.SmoothPlastic
					if p:IsA("MeshPart") then
						p.TextureID = ""
					end
					p.Anchored = true
					p.CanTouch = false
					p.CastShadow = true
					p.Parent = m
				end
			end
		end
		for name, m in models do
			-- pivot: bottom center
			local cf, size = m:GetBoundingBox()
			local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
			m.WorldPivot = CFrame.new(bottom)
			m:PivotTo(CFrame.new())
			m.Parent = kit
			local _ = name
		end
		import:Destroy()
		kit.Parent = ServerStorage
	end
	return kit
end

local function place(kit: Folder, piece: string, parent: Instance, pos: Vector3, scale: number, yaw: number?, collide: boolean?): Model?
	local src = kit:FindFirstChild(piece) :: Model?
	if not src then
		return nil
	end
	local m = src:Clone()
	m:ScaleTo(scale)
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw or rng:NextNumber(0, math.pi * 2), 0))
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = collide == true
			p.CanQuery = collide == true
		end
	end
	m.Parent = parent
	return m
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

-- Points on a cliff's grass tops (raycast down onto its Grass part).
local function topSpots(cliff: Model, n: number): { Vector3 }
	local grass = cliff:FindFirstChild("Grass") :: BasePart?
	local out = {}
	if not grass then
		return out
	end
	params.FilterDescendantsInstances = { grass }
	local cf, size = grass.CFrame, grass.Size
	for _ = 1, n * 6 do
		if #out >= n then
			break
		end
		local x = rng:NextNumber(-0.3, 0.3) * size.X
		local z = rng:NextNumber(-0.3, 0.3) * size.Z
		local from = Vector3.new(cf.X + x, cf.Y + size.Y + 50, cf.Z + z)
		local hit = workspace:Raycast(from, Vector3.new(0, -200, 0), params)
		if hit and hit.Normal.Y > 0.8 then
			local ok = true
			for _, o in out do
				if (o - hit.Position).Magnitude < 7 then
					ok = false
				end
			end
			if ok then
				table.insert(out, hit.Position)
			end
		end
	end
	return out
end

local function land(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(x1 - x0, 6, z1 - z0)
	p.CFrame = CFrame.new((x0 + x1) / 2, -3, (z0 + z1) / 2)
	p.Color = LAND
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	-- a brown dirt lip round the edge, like the reference's base
	local lip = p:Clone()
	lip.Name = name .. "Edge"
	lip.Size = Vector3.new(x1 - x0 + 2, 5, z1 - z0 + 2)
	lip.CFrame = CFrame.new((x0 + x1) / 2, -4.2, (z0 + z1) / 2)
	lip.Color = LAND_EDGE
	lip.Parent = parent
end

-- How far a model reaches along a direction (max over its parts' box corners of corner . n).
local function reachAlong(model: Model, n: Vector3): number
	local best = -math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local h = p.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, 1, -1) } do
				best = math.max(best, (p.CFrame * (h * c)):Dot(n))
			end
		end
	end
	return best
end

-- One hill: a cliff with pines on top, and a scatter of small things round its foot. On the border
-- (`inward` = the direction toward the playable area, `limit` = how far it may reach that way) the
-- cliff lies with its long side along the edge and is slid out so it stops right at the boundary.
local function hill(kit: Folder, parent: Instance, pos: Vector3, scale: number, avoid: (Vector3) -> boolean,
	yaw: number?, inward: Vector3?, limit: number?)
	local cliffs = { "CliffA", "CliffB", "CliffC" }
	local m = Instance.new("Model")
	m.Name = "Hill"
	m.Parent = parent
	local cliff = place(kit, cliffs[rng:NextInteger(1, #cliffs)], m, pos, scale, yaw, true)
	if not cliff then
		return
	end
	if inward and limit then
		local over = reachAlong(cliff, inward) - limit
		cliff:PivotTo(cliff:GetPivot() - inward * over)
		pos -= inward * over
	end
	for _, top in topSpots(cliff, rng:NextInteger(1, 3)) do
		place(kit, "Pine", m, top - Vector3.new(0, 0.6, 0), rng:NextNumber(1.1, 1.6) * math.sqrt(scale))
		if rng:NextNumber() < 0.5 then
			place(kit, "Mushroom", m, top + Vector3.new(rng:NextNumber(-3, 3), -0.3, rng:NextNumber(-3, 3)), rng:NextNumber(1.6, 2.4))
		end
	end
	local _, size = cliff:GetBoundingBox()
	local reach = math.max(size.X, size.Z) * 0.5
	local function foot(minR: number, maxR: number): Vector3?
		for _ = 1, 8 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = reach + rng:NextNumber(minR, maxR)
			local p = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if not avoid(p) then
				return p
			end
		end
		return nil
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local p = foot(1, 6)
		if p then
			place(kit, "Boulder", m, p, rng:NextNumber(1.6, 2.8), nil, true)
		end
	end
	for _ = 1, rng:NextInteger(2, 4) do
		local p = foot(2, 14)
		if p then
			place(kit, "Pebble", m, p, rng:NextNumber(1.5, 2.6))
		end
	end
	for _ = 1, rng:NextInteger(5, 9) do
		local p = foot(0, 18)
		if p then
			place(kit, "Tuft", m, p, rng:NextNumber(2.2, 3.4))
		end
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local p = foot(1, 10)
		if p then
			place(kit, "Mushroom", m, p, rng:NextNumber(2, 3))
		end
	end
	if rng:NextNumber() < 0.6 then
		local p = foot(2, 8)
		if p then
			place(kit, "Pine", m, p, rng:NextNumber(1.5, 2.2))
		end
	end
	if rng:NextNumber() < 0.35 then -- a pair of barrels by a bit of fence, like the reference
		local p = foot(3, 6)
		if p then
			local yaw = rng:NextNumber(0, math.pi * 2)
			local side = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
			place(kit, "Fence", m, p, 2.2, yaw, true)
			place(kit, "Barrel", m, p + side * 6 + Vector3.new(0, 0, 2), 2.2, nil, true)
			place(kit, "Barrel", m, p + side * 9.5 + Vector3.new(1, 0, 1), 2.2, nil, true)
		end
	end
end

local function build()
	local kit = prepareKit()
	if not kit then
		return "BuildHills: no kit - import assets/HillKit.fbx into Workspace first"
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		return "BuildHills: no Workspace.Map (run BuildMap first)"
	end
	local old = map:FindFirstChild("Hills")
	if old then
		old:Destroy()
	end
	local hills = Instance.new("Model")
	hills.Name = "Hills"
	hills.Parent = map

	-- the playable area's outer edges: hub sides / back, and the Wilds runway (BuildWilds) out front
	local edge = HUB_X + WALL_T -- side barriers' outer face (the runway is as wide as the hub)
	local back = HUB_BACK - WALL_T
	local far = WILDS_END + WALL_T -- the runway's far barrier
	local W = 190 -- land strip width outside the edge
	land(hills, "LandLeft", -edge - W, -edge, back - W, far + W)
	land(hills, "LandRight", edge, edge + W, back - W, far + W)
	land(hills, "LandBack", -edge, edge, back - W, back)
	land(hills, "LandFar", -edge, edge, far, far + W)
	local function avoid(p: Vector3): boolean
		local inside = math.abs(p.X) < edge + 3 and p.Z > back - 3 and p.Z < far + 3
		local outside = math.abs(p.X) > edge + W - 4 or p.Z < back - W + 4 or p.Z > far + W - 4
		return inside or outside
	end
	local count = 0
	local function row(from: Vector3, along: Vector3, length: number, out: Vector3, gap: number, step: { number },
		scales: { number }, border: boolean)
		local t = 0
		while t < length do
			local p = from + along * t + out * (gap + rng:NextNumber(-6, 6))
			-- long side along the edge (the kit's cliffs are long in X), a little jitter
			local yaw = math.atan2(-along.Z, along.X) + rng:NextNumber(-0.14, 0.14) + (if rng:NextNumber() < 0.5 then math.pi else 0)
			local limit = if border then -(from:Dot(out)) + 1 else nil
			hill(kit, hills, p, rng:NextNumber(scales[1], scales[2]), avoid, yaw, if border then -out else nil, limit)
			count += 1
			t += rng:NextNumber(step[1], step[2])
			task.wait()
		end
	end
	local zFrom, zLen = back - W + 30, (far + W - 30) - (back - W + 30)
	for _, sx in { -1, 1 } do
		local out = Vector3.new(sx, 0, 0)
		local start = Vector3.new(sx * edge, 0, zFrom)
		row(start, Vector3.new(0, 0, 1), zLen, out, 30, { 36, 46 }, { 2.2, 2.9 }, true) -- the boundary itself
		row(start, Vector3.new(0, 0, 1), zLen, out, 110, { 46, 60 }, { 2.6, 3.4 }, false) -- bigger ones behind
	end
	for _, edgeZ in { back, far } do
		local out = Vector3.new(0, 0, if edgeZ == back then -1 else 1)
		local start = Vector3.new(-edge + 24, 0, edgeZ)
		row(start, Vector3.new(1, 0, 0), edge * 2 - 48, out, 30, { 36, 46 }, { 2.2, 2.9 }, true)
		row(start, Vector3.new(1, 0, 0), edge * 2 - 48, out, 110, { 46, 60 }, { 2.6, 3.4 }, false)
	end
	return string.format("BuildHills: %d hills", count)
end

return build()
