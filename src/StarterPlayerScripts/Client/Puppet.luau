-- Poses a multi-part Blender model every frame without physics: squash/stretch around the
-- model's pivot (bottom-center), eye blinks (Eyes/Pupils/Shine) and leg swings (LegFL/FR/BL/BR).
local Puppet = {}
Puppet.__index = Puppet

local EYE_PARTS = { Eyes = true, Pupils = true, Shine = true }
local LEG_SIGN = { LegFL = 1, LegBR = 1, LegFR = -1, LegBL = -1 }

local function absVector(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

export type Entry = {
	part: BasePart,
	pos: Vector3,
	rot: CFrame,
	size: Vector3,
	ax: Vector3,
	ay: Vector3,
	az: Vector3,
	eye: boolean,
	leg: number?,
	hinge: Vector3?,
}

function Puppet.new(model: Model)
	local self = setmetatable({}, Puppet)
	self.model = model
	self.entries = {} :: { Entry }
	local base = model:GetPivot()
	local eyeSum, eyeCount = Vector3.zero, 0
	-- a leg can be several parts (one per color): they share one hinge at the top-center of them all
	local legLo, legHi = {}, {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and LEG_SIGN[p.Name] then
			local rel = base:ToObjectSpace(p.CFrame)
			local half = Vector3.new(
				math.abs(rel.XVector.X) * p.Size.X + math.abs(rel.YVector.X) * p.Size.Y + math.abs(rel.ZVector.X) * p.Size.Z,
				math.abs(rel.XVector.Y) * p.Size.X + math.abs(rel.YVector.Y) * p.Size.Y + math.abs(rel.ZVector.Y) * p.Size.Z,
				math.abs(rel.XVector.Z) * p.Size.X + math.abs(rel.YVector.Z) * p.Size.Y + math.abs(rel.ZVector.Z) * p.Size.Z
			) / 2
			legLo[p.Name] = (legLo[p.Name] or rel.Position - half):Min(rel.Position - half)
			legHi[p.Name] = (legHi[p.Name] or rel.Position + half):Max(rel.Position + half)
		end
	end
	for _, p in model:GetDescendants() do
		if not p:IsA("BasePart") then
			continue
		end
		local rel = base:ToObjectSpace(p.CFrame)
		local e: Entry = {
			part = p,
			pos = rel.Position,
			rot = rel.Rotation,
			size = p.Size,
			ax = absVector(rel.XVector),
			ay = absVector(rel.YVector),
			az = absVector(rel.ZVector),
			eye = EYE_PARTS[p.Name] == true,
			leg = LEG_SIGN[p.Name],
		}
		if e.leg then
			local lo, hi = legLo[p.Name], legHi[p.Name]
			e.hinge = Vector3.new((lo.X + hi.X) / 2, hi.Y, (lo.Z + hi.Z) / 2)
		end
		if p.Name == "Eyes" then
			eyeSum += rel.Position
			eyeCount += 1
		end
		table.insert(self.entries, e)
	end
	self.eyeCenter = if eyeCount > 0 then eyeSum / eyeCount else Vector3.new(0, 1, 0)
	return self
end

-- root: world CFrame of the pivot. s: per-axis scale (squash * size). blink: 1 open .. ~0.1 shut.
-- legSwing: radians. Appends to parts/cframes for one BulkMoveTo per frame.
function Puppet:pose(root: CFrame, s: Vector3, blink: number, legSwing: number, parts: { BasePart }, cframes: { CFrame })
	local eyeY = self.eyeCenter.Y
	for _, e in self.entries do
		local pos, rot, sv = e.pos, e.rot, s
		if e.leg and legSwing ~= 0 then
			local r = CFrame.Angles(legSwing * e.leg, 0, 0)
			local hinge = e.hinge :: Vector3
			pos = hinge + r:VectorToWorldSpace(pos - hinge)
			rot = r * rot
		end
		if e.eye and blink < 0.999 then
			pos = Vector3.new(pos.X, eyeY + (pos.Y - eyeY) * blink, pos.Z)
			sv = Vector3.new(s.X, s.Y * blink, s.Z)
		end
		table.insert(parts, e.part)
		table.insert(cframes, root * CFrame.new(pos * s) * rot)
		e.part.Size = e.size * Vector3.new(e.ax:Dot(sv), e.ay:Dot(sv), e.az:Dot(sv))
	end
end

function Puppet:setTransparency(t: number)
	for _, e in self.entries do
		e.part.Transparency = t
	end
end

-- Blink driver: call every frame, returns the blink factor.
function Puppet:blink(now: number): number
	if not self.nextBlink then
		self.nextBlink = now + math.random() * 3
	end
	if now >= self.nextBlink then
		self.blinkStart = now
		self.nextBlink = now + 1.8 + math.random() * 3.2
	end
	local b = (now - (self.blinkStart or -10)) / 0.15
	if b < 1 then
		return 1 - 0.9 * math.sin(b * math.pi)
	end
	return 1
end

return Puppet
