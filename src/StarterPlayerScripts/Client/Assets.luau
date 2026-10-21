-- Clones prepared Blender models from ReplicatedStorage.Assets (pivot = bottom-center, facing -Z).
-- Falls back to simple placeholders so the game still runs before assets are imported.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LuckyModel = require(ReplicatedStorage.Shared.LuckyModel)

local Assets = {}

local function source(folderName: string, name: string): Model?
	local root = ReplicatedStorage:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(name) :: Model?
end

local function prep(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = d.Name ~= "Eyes" and d.Name ~= "Pupils" and d.Name ~= "Shine"
		end
	end
end

local function ball(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function placeholder(name: string, color: Color3, legs: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	ball(m, "Body", Vector3.one * 2, CFrame.new(0, 1.1, 0), color)
	ball(m, "Eyes", Vector3.new(0.5, 0.6, 0.3), CFrame.new(0, 1.4, -0.92), Color3.new(1, 1, 1))
	ball(m, "Pupils", Vector3.new(0.3, 0.4, 0.2), CFrame.new(0, 1.36, -1.02), Color3.fromRGB(36, 27, 47))
	if legs then
		for legName, x in { LegFL = -0.5, LegFR = 0.5, LegBL = -0.5, LegBR = 0.5 } do
			local z = string.find(legName, "F") == 4 and -0.5 or 0.5
			local leg = Instance.new("Part")
			leg.Name = legName
			leg.Size = Vector3.new(0.45, 0.5, 0.45)
			leg.CFrame = CFrame.new(x, 0.25, z)
			leg.Color = color:Lerp(Color3.new(0, 0, 0), 0.2)
			leg.Material = Enum.Material.SmoothPlastic
			leg.Parent = m
		end
	end
	m.WorldPivot = CFrame.new()
	return m
end

-- Scales a model so `measure(size)` equals `target` (pivot stays at the bottom-center).
local function normalized(model: Model, target: number, measure: (Vector3) -> number): Model
	prep(model)
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	local current = measure(size)
	if current > 0 then
		model:ScaleTo(model:GetScale() * target / current)
	end
	model:PivotTo(CFrame.new())
	return model
end

-- Foods are sized by their largest dimension so flat ones (donut, pizza) don't balloon.
function Assets.food(id: string): Model
	local src = source("Foods", id)
	local model = if src then src:Clone() else placeholder(id, (Config.rarityOf(id)).color, false)
	return normalized(model, Config.Farm.foodSize, function(s)
		return math.max(s.X, s.Y, s.Z)
	end)
end

function Assets.pet(id: string?): Model
	local name = id or "Hippo"
	local src = source("Pets", name)
	local model = if src then src:Clone() else placeholder(name, Color3.fromRGB(156, 143, 214), true)
	local def = Config.Pets[name]
	return normalized(model, def and def.height or Config.Pet.baseHeight, function(s)
		return s.Y
	end)
end

-- A wild monster (falls back to a pet model, so zones can still spawn pets).
function Assets.wild(id: string): Model
	local def = Config.Monsters[id]
	if not def then
		return Assets.pet(id)
	end
	local src = source("Monsters", id)
	if src and src:GetAttribute("VisualHeight") then
		-- store models (Verity): textured meshes whose boxes overhang the visible body, so they
		-- come pre-pivoted at their bottom-center and carry their real height
		local model = src:Clone()
		prep(model)
		model:PivotTo(CFrame.new())
		model:ScaleTo(model:GetScale() * def.height / model:GetAttribute("VisualHeight"))
		model:PivotTo(CFrame.new())
		return model
	end
	local model = if src then src:Clone() else placeholder(id, def.color, true)
	return normalized(model, def.height, function(s)
		return s.Y
	end)
end

-- A food or a pet, whichever the id is.
function Assets.critter(id: string): Model
	return if Config.isPet(id) then Assets.pet(id) else Assets.food(id)
end

-- The 3D food coin, re-pivoted to its center with its face pointing up (lying flat).
-- Returns the model plus its thickness. Falls back to a gold disc before the model is imported.
local coinTemplate: Model? = nil
local coinThickness = 0.3
function Assets.coin(): (Model, number)
	if not coinTemplate then
		local src = source("Props", "Coin")
		local m: Model
		if src then
			m = src:Clone()
			prep(m)
			-- swap the embossed 3D burger for the flat cartoon sticker on both faces
			for _, name in { "Bun", "Patty", "Lettuce" } do
				local part = m:FindFirstChild(name)
				if part then
					part:Destroy()
				end
			end
			local gold = m:FindFirstChild("Gold") :: BasePart?
			if gold then
				local s = gold.Size
				local faces = if s.X <= s.Y and s.X <= s.Z then { Enum.NormalId.Left, Enum.NormalId.Right }
					elseif s.Y <= s.Z then { Enum.NormalId.Top, Enum.NormalId.Bottom }
					else { Enum.NormalId.Front, Enum.NormalId.Back }
				for _, face in faces do
					local decal = Instance.new("Decal")
					decal.Texture = Config.CoinEmblem
					decal.Face = face
					decal.Parent = gold
				end
			end
		else
			m = Instance.new("Model")
			local disc = Instance.new("Part")
			disc.Name = "Gold"
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.3, 1.3, 1.3)
			disc.Color = Color3.fromRGB(255, 216, 74)
			disc.Material = Enum.Material.SmoothPlastic
			disc.CFrame = CFrame.Angles(0, 0, math.rad(90))
			disc.Parent = m
			prep(m)
		end
		m.PrimaryPart = nil
		m.WorldPivot = CFrame.new()
		-- the thinnest bounding axis is the coin's face normal; rotate it onto +Y
		local cf, size = m:GetBoundingBox()
		local face: Vector3
		if size.X <= size.Y and size.X <= size.Z then
			face = cf.XVector
		elseif size.Y <= size.Z then
			face = cf.YVector
		else
			face = cf.ZVector
		end
		coinThickness = math.min(size.X, size.Y, size.Z)
		local diameter = math.max(size.X, size.Y, size.Z)
		local up = if math.abs(face.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
		local right = up:Cross(face).Unit
		-- pivot frame: Y = face normal, so posing the pivot upright lays the coin flat
		m.WorldPivot = CFrame.fromMatrix(cf.Position, right, face)
		m:PivotTo(CFrame.new())
		local target = 2.0 -- studs across
		m:ScaleTo(m:GetScale() * target / diameter)
		coinThickness *= target / diameter
		m:PivotTo(CFrame.new())
		coinTemplate = m
	end
	return (coinTemplate :: Model):Clone(), coinThickness
end

-- A lucky block for a tier at its stand size (see Shared/LuckyModel).
function Assets.lucky(tierIndex: number): Model
	local tier = Config.Lucky.tiers[tierIndex] or Config.Lucky.tiers[1]
	return LuckyModel.build(tierIndex, Config.Lucky.size * (tier.scale or 1))
end

function Assets.icon(id: string): string
	return Config.Icons[id] or ""
end

return Assets
