-- Motion for anything a food tosses onto the stand: it speeds down the ramp, levels off, then
-- glides across the gutter floor and brakes to a stop exactly on its resting spot.
local Stand = require(script.Parent.Stand)

local StandPath = {}
StandPath.__index = StandPath

local ACCEL = 34 -- down the ramp
local RAMP_TOP_SPEED = 14

export type Mover = {
	points: { Vector3 },
	lens: { number },
	dist: number,
	speed: number,
	decel: number?,
	step: (Mover, number) -> (Vector3, boolean, boolean),
}

-- land: where it hits the ramp; stop: where it rests; lift: offset so the object sits on the surface.
function StandPath.new(plotIndex: number, slot: number?, land: Vector3, stop: Vector3, lift: Vector3): Mover
	local plot = Stand.plots[plotIndex]
	local s = plot and slot and plot.slots[slot]
	local points = { land + lift }
	if s and s.rampEnd then
		table.insert(points, s.rampEnd + lift) -- straight down the slope from where it landed
	end
	table.insert(points, stop + lift)
	local lens = { 0 }
	for i = 2, #points do
		lens[i] = lens[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return setmetatable({ points = points, lens = lens, dist = 0, speed = 3, decel = nil }, StandPath) :: any
end

local function at(self: Mover): (Vector3, number)
	local points, lens = self.points, self.lens
	for i = 2, #points do
		if self.dist <= lens[i] then
			local seg = lens[i] - lens[i - 1]
			local u = if seg > 0 then (self.dist - lens[i - 1]) / seg else 1
			return points[i - 1]:Lerp(points[i], u), i - 1
		end
	end
	return points[#points], #points
end

-- Returns (position, justLeveledOff, done).
function StandPath.step(self: Mover, dt: number): (Vector3, boolean, boolean)
	local _, seg = at(self)
	local leveled = false
	if seg == 1 and #self.points > 2 then
		self.speed = math.min(self.speed + ACCEL * dt, RAMP_TOP_SPEED)
	else
		if not self.decel then -- off the ramp: brake so it glides to a stop right on its spot
			local left = self.lens[#self.lens] - self.dist
			self.decel = self.speed * self.speed / (2 * math.max(left, 0.5))
			leveled = true
		end
		self.speed = math.max(self.speed - (self.decel :: number) * dt, 0.8)
	end
	self.dist += self.speed * dt
	local pos = at(self)
	return pos, leveled, self.dist >= self.lens[#self.lens]
end

return StandPath
