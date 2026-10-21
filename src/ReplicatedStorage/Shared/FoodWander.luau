-- Deterministic free-roaming for food on a farm. Server and every client evaluate the same
-- function of (entry, server time), so nothing is replicated per frame and coin drops spawn
-- exactly where clients see the food.
--
-- Time is split into legs. Each leg the food waddles from one waypoint to the next with small
-- hop-steps, then pauses to look around (and sometimes does a big happy twirl jump).
-- Waypoints come from a smooth noise path, so consecutive legs are a few studs apart and the
-- food drifts all over the farm.
--
-- entry = { seed, x, z, t0 }  (x/z = landing spot in farm-local studs, t0 = landing time)
local FoodWander = {}

local LEG = 4.8 -- seconds per walk + pause cycle
local SPEED = 3.6 -- studs per second while walking
local STEP = 0.34 -- seconds per waddle step
local STEP_HEIGHT = 0.32
local JUMP_HEIGHT = 1.6
local CROUCH = 0.15 -- fraction of a step spent on the ground before lifting off
local PATH_SPACING = 2.8 -- noise-time between waypoints (bigger = longer walks)
local FREQ = 0.075

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end
FoodWander.hash = hash

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function path(seed: number, t: number, hx: number, hz: number): (number, number)
	local nx = math.noise(seed * 0.37, t * FREQ, 0.5)
	local nz = math.noise(t * FREQ, seed * 0.53, 11.1)
	return math.clamp(nx * 2.4, -1, 1) * hx, math.clamp(nz * 2.4, -1, 1) * hz
end

-- Waypoint k (k = 0 is where the food landed).
local function waypoint(e, k: number, hx: number, hz: number): (number, number)
	if k <= 0 then
		return e.x, e.z
	end
	-- ease the first few waypoints out from the landing spot so new food doesn't sprint off
	local px, pz = path(e.seed, k * PATH_SPACING, hx, hz)
	local b = smooth(k / 3)
	return e.x + (px - e.x) * b, e.z + (pz - e.z) * b
end

export type Sample = {
	x: number,
	z: number,
	h: number, -- height above the farm floor
	dx: number, -- facing direction (farm-local)
	dz: number,
	look: number, -- extra yaw while idling (looking around)
	roll: number, -- side-to-side waddle tilt
	hop: number, -- id of the current step/jump (-1 before landing); changes on every landing
	air: boolean,
	phase: number, -- 0..1 through the airborne part
	crouch: number, -- 0..1 anticipation squash before lifting off
	big: boolean, -- big happy jump (vs a small waddle step)
}

local GROUNDED = { h = 0, look = 0, roll = 0, air = false, phase = 0, crouch = 0, big = false }

local function make(x, z, dx, dz, hop, fields): Sample
	local s = { x = x, z = z, dx = dx, dz = dz, hop = hop }
	for k, v in GROUNDED do
		s[k] = v
	end
	for k, v in fields do
		s[k] = v
	end
	return s :: Sample
end

-- A farm's roaming frame: (top-center of the floor, half-extents kept `margin` from the edges).
function FoodWander.frame(floor: BasePart, margin: number): (CFrame, number, number)
	return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0), floor.Size.X / 2 - margin, floor.Size.Z / 2 - margin
end

function FoodWander.sample(e, t: number, hx: number, hz: number): Sample
	local tl = t - e.t0
	if tl < 0 then
		return make(e.x, e.z, 0, -1, -1, {})
	end
	local k = math.floor(tl / LEG)
	local lt = tl - k * LEG
	local ax, az = waypoint(e, k, hx, hz)
	local bx, bz = waypoint(e, k + 1, hx, hz)
	local dx, dz = bx - ax, bz - az
	local dist = math.sqrt(dx * dx + dz * dz)
	local walk = math.clamp(dist / SPEED, 0.7, LEG - 0.9)

	if lt < walk then
		-- waddling: a string of small hop-steps along the leg
		local steps = math.max(1, math.floor(walk / STEP + 0.5))
		local stepDur = walk / steps
		local s = math.floor(lt / stepDur)
		local u = lt / stepDur - s
		local lift = math.clamp((u - CROUCH) / (1 - CROUCH), 0, 1)
		local progress = (s + smooth(lift)) / steps
		local side = if s % 2 == 0 then 1 else -1
		return make(ax + dx * progress, az + dz * progress, dx, dz, k * 100 + s, {
			h = STEP_HEIGHT * 4 * lift * (1 - lift),
			air = u >= CROUCH,
			phase = lift,
			crouch = if u < CROUCH then u / CROUCH else 0,
			roll = side * math.sin(lift * math.pi) * 0.14,
		})
	end

	-- pausing at the waypoint: look around, sometimes a big happy jump
	local pt = lt - walk
	local rest = LEG - walk
	local look = math.sin(pt * 2.1 + e.seed) * 0.7 * smooth(pt / 0.6)
	if hash(e.seed, k) < 0.3 and rest > 1.4 then
		local js = 0.35 -- jump starts this long into the pause
		if pt >= js - 0.18 and pt < js + 0.62 then
			if pt < js then
				return make(bx, bz, dx, dz, k * 100 + 98, { crouch = (pt - (js - 0.18)) / 0.18 })
			end
			local a = (pt - js) / 0.62
			return make(bx, bz, dx, dz, k * 100 + 99, {
				h = JUMP_HEIGHT * 4 * a * (1 - a),
				air = true,
				phase = a,
				big = true,
			})
		end
	end
	return make(bx, bz, dx, dz, k * 100 + 97, { look = look })
end

return FoodWander
