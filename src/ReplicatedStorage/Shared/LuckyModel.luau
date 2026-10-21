-- Builds a lucky block model for a tier: the block (Assets.Lucky.<Tier>) sized by its cube, with
-- the tier's aura (Assets.Auras.<Tier>, an invisible "core" part carrying emitters/lights) mounted
-- at its center so it moves with the block. Pivot = bottom-center, facing -Z. Used by the client
-- (blocks on the stand) and the server (the block held in your hand). Falls back to a "?" cube.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local LuckyModel = {}

local function source(folderName: string, name: string): Instance?
	local root = ReplicatedStorage:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(name)
end

local function fallbackBlock(tier): Model
	local m = Instance.new("Model")
	local cube = Instance.new("Part")
	cube.Name = "Block"
	cube.Size = Vector3.one * 2
	cube.CFrame = CFrame.new(0, 1, 0)
	cube.Color = tier.color
	cube.Material = Enum.Material.SmoothPlastic
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "?"
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = gui
		gui.Parent = cube
	end
	cube.Parent = m
	m.WorldPivot = CFrame.new()
	return m
end

local function fallbackAura(tier): BasePart
	local core = Instance.new("Part")
	core.Size = Vector3.one
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(tier.color)
	e.LightEmission = 0.8
	e.Rate = 18
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(1.5, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = core
	local light = Instance.new("PointLight")
	light.Color = tier.color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = core
	return core
end

-- cubeSize: the block's front-to-back size in studs (wings spread sideways/up, so they don't count).
-- withAura: false for UI previews.
function LuckyModel.build(tierIndex: number, cubeSize: number, withAura: boolean?): Model
	local tier = Config.Lucky.tiers[tierIndex] or Config.Lucky.tiers[1]
	local src = source("Lucky", tier.name)
	local model = if src then (src :: Model):Clone() else fallbackBlock(tier)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		end
	end
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	if size.Z > 0 then
		model:ScaleTo(model:GetScale() * cubeSize / size.Z)
	end
	model:PivotTo(CFrame.new())
	if withAura ~= false then
		-- auras are authored for a 2.4-stud block; scale them with the block
		local auraSrc = source("Auras", tier.name)
		local aura = if auraSrc then (auraSrc :: BasePart):Clone() else fallbackAura(tier)
		local holder = Instance.new("Model")
		aura.Parent = holder
		holder:ScaleTo(cubeSize / (Config.Lucky.size * (tier.scale or 1)))
		local _, s = model:GetBoundingBox()
		aura.Name = "AuraCore"
		aura.Transparency = 1
		aura.Anchored, aura.CanCollide, aura.CanQuery, aura.CanTouch, aura.CastShadow = true, false, false, false, false
		aura.CFrame = CFrame.new(0, s.Y / 2, 0)
		aura.Parent = model
		holder:Destroy()
	end
	return model
end

return LuckyModel
