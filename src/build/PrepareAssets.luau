-- Edit-time: turns freshly imported Blender models (Workspace.<Name>) into game-ready assets in
-- ReplicatedStorage.Assets.{Foods,Pets,Props}.
--   * part names "Body_E8383D[_Neon|_Foil|_Metal]" -> Name "Body", Color, Material
--   * pivot = bottom-center, facing the way the face looks (front = Blender -Y, measured on the Hippo)
-- Safe to re-run: models already in Assets are reprocessed in place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GROUPS = {
	Foods = { "Apple", "Carrot", "Donut", "Taco", "Sushi", "Pizza", "Burger", "GoldenCake" },
	Pets = { "Hippo", "TRex" },
	Monsters = {}, -- Verity is a Creator Store model set up by hand (keeps its SurfaceAppearances)
	Props = { "Lever", "Coin" },
}
local MATERIALS = {
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
	Metal = Enum.Material.Metal,
}

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage

local function find(group: string, name: string): Model?
	local inWorkspace = workspace:FindFirstChild(name)
	if inWorkspace and inWorkspace:IsA("Model") then
		return inWorkspace
	end
	local folder = assets:FindFirstChild(group)
	return folder and folder:FindFirstChild(name) :: Model?
end

local function bounds(model: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, s = p.CFrame, p.Size / 2
			local ext = Vector3.new(
				math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
				math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
				math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
			)
			lo = lo:Min(p.Position - ext)
			hi = hi:Max(p.Position + ext)
		end
	end
	return lo, hi
end

local function clean(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") or d:IsA("MaterialVariant") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			local base, hex, tag = string.match(d.Name, "^(.-)_(%x%x%x%x%x%x)_?(%a*)$")
			if hex then
				d.Name = base
				d.Color = Color3.fromHex(hex)
				d.Material = MATERIALS[tag] or Enum.Material.SmoothPlastic
			end
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = not (d.Name == "Eyes" or d.Name == "Pupils" or d.Name == "Shine")
		end
	end
end

-- Front direction from the hippo: eyes sit forward of the body center.
local function frontFrom(hippo: Model?): Vector3
	if not hippo then
		return Vector3.new(0, 0, -1)
	end
	local eyes = hippo:FindFirstChild("Eyes", true) :: BasePart?
	local lo, hi = bounds(hippo)
	if not eyes then
		return Vector3.new(0, 0, -1)
	end
	local d = (eyes.Position - (lo + hi) / 2) * Vector3.new(1, 0, 1)
	-- snap to the dominant horizontal axis (the importer only ever rotates by 90 degrees)
	if math.abs(d.X) > math.abs(d.Z) then
		return Vector3.new(math.sign(d.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(d.Z))
end

local report = {}
for _, group in { "Pets", "Foods", "Props", "Monsters" } do
	local folder = assets:FindFirstChild(group) or Instance.new("Folder")
	folder.Name = group
	folder.Parent = assets
end
local hippo = find("Pets", "Hippo")
if hippo then
	clean(hippo)
end
local front = frontFrom(hippo)
for group, names in GROUPS do
	for _, name in names do
		local model = find(group, name)
		if not model then
			table.insert(report, name .. ": missing")
			continue
		end
		clean(model)
		model.PrimaryPart = nil
		local lo, hi = bounds(model)
		local bottom = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
		model.WorldPivot = CFrame.lookAt(bottom, bottom + front)
		model:PivotTo(CFrame.new(0, 0, 0))
		model.Name = name
		model.Parent = assets[group]
		table.insert(report, string.format("%s: ok (%.1f tall)", name, hi.Y - lo.Y))
	end
end
return "front=" .. tostring(front) .. " | " .. table.concat(report, ", ")
