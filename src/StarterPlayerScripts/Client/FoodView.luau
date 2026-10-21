-- One animated food critter: a Puppet plus a squash/stretch spring and blinking. It can also be
-- "locked" (an all-black silhouette with a faint rim, like a locked character) and revealed.
local Juice = require(script.Parent.Juice)
local Puppet = require(script.Parent.Puppet)
local Assets = require(script.Parent.Assets)

local SHADOW = Color3.fromRGB(16, 12, 24)
local WHITE = Color3.new(1, 1, 1)

local FoodView = {}
FoodView.__index = FoodView

function FoodView.new(id: string, parent: Instance)
	local self = setmetatable({}, FoodView)
	self.id = id
	self.model = Assets.critter(id) -- foods and pets animate the same way
	self.model.Parent = parent
	self.puppet = Puppet.new(self.model)
	self.squash = Juice.spring(1, 380, 17) -- springy but settles quickly (less jelly bounce)
	self.scale = 1
	return self
end

-- Negative = squash impulse (landing, hiccup), positive = stretch.
function FoodView:kick(velocity: number)
	self.squash.v += velocity
end

-- Black silhouette: every part goes shadow-black (eyes too), with a faint white rim.
function FoodView:silhouette()
	if self.saved then
		return
	end
	local saved = {}
	for _, p in self.model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(saved, { inst = p, color = p.Color, material = p.Material,
				texture = if p:IsA("MeshPart") then p.TextureID else nil })
			p.Color = SHADOW
			p.Material = Enum.Material.SmoothPlastic
			if p:IsA("MeshPart") then
				p.TextureID = ""
			end
		elseif p:IsA("Decal") then
			table.insert(saved, { inst = p, transparency = p.Transparency })
			p.Transparency = 1
		end
	end
	self.saved = saved
	local rim = Instance.new("Highlight")
	rim.Name = "Rim"
	rim.Adornee = self.model
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	rim.FillColor = WHITE
	rim.FillTransparency = 1
	rim.OutlineColor = WHITE
	rim.OutlineTransparency = 0.45
	rim.Parent = self.model
	self.rim = rim
end

-- Unlock: flashes white, then its real colors wash back in over `duration`.
function FoodView:reveal(duration: number?)
	if not self.saved then
		return
	end
	self.revealT0 = os.clock()
	self.revealDur = duration or 0.45
	for _, s in self.saved do
		if s.color then
			s.inst.Material = s.material
			s.inst.Color = WHITE
			if s.texture then
				s.inst.TextureID = s.texture
			end
		else
			s.inst.Transparency = s.transparency
		end
	end
	if self.rim then
		self.rim.FillTransparency = 0
		self.rim.OutlineTransparency = 0
	end
end

local function stepReveal(self)
	local u = math.clamp((os.clock() - self.revealT0) / self.revealDur, 0, 1)
	local e = Juice.easeOutCubic(u)
	for _, s in self.saved do
		if s.color then
			s.inst.Color = WHITE:Lerp(s.color, e)
		end
	end
	if self.rim then
		self.rim.FillTransparency = e
		self.rim.OutlineTransparency = e
	end
	if u >= 1 then
		if self.rim then
			self.rim:Destroy()
			self.rim = nil
		end
		self.saved, self.revealT0 = nil, nil
	end
end

function FoodView:step(dt: number, root: CFrame, stretchTarget: number, parts: { BasePart }, cframes: { CFrame })
	if self.revealT0 then
		stepReveal(self)
	end
	self.squash.target = stretchTarget
	local sy = math.clamp(self.squash:step(dt), 0.45, 1.7)
	local sxz = 1 / math.sqrt(sy) -- keep volume roughly constant
	local k = math.max(self.scale, 0.01)
	self.puppet:pose(root, Vector3.new(sxz * k, sy * k, sxz * k), self.puppet:blink(os.clock()), 0, parts, cframes)
end

function FoodView:destroy()
	self.model:Destroy()
end

return FoodView
