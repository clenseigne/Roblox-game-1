-- Small animation toolkit: easing, springs, UI pops, sounds and camera shake.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Juice = {}

function Juice.easeOutBack(x: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

function Juice.easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

function Juice.easeInQuad(x: number): number
	return x * x
end

function Juice.lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Frame-rate independent smoothing factor.
function Juice.smoothing(speed: number, dt: number): number
	return 1 - math.exp(-speed * dt)
end

function Juice.tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Returns (creating if needed) the UIScale of a gui object.
function Juice.scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = gui
	end
	return s :: UIScale
end

-- Pops a gui object in from nothing with a springy overshoot.
function Juice.popIn(gui: GuiObject, time: number?)
	local s = Juice.scaleOf(gui)
	s.Scale = 0
	Juice.tween(s, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Quick squash-punch for counters and slots.
function Juice.punch(gui: GuiObject, amount: number?)
	local s = Juice.scaleOf(gui)
	s.Scale = 1 + (amount or 0.18)
	Juice.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Horizontal "nope" shake for buttons / pills.
function Juice.shakeGui(gui: GuiObject)
	local base = gui.Position
	task.spawn(function()
		for i = 1, 6 do
			local o = (i % 2 == 0 and 1 or -1) * (7 - i) * 2
			gui.Position = base + UDim2.fromOffset(o, 0)
			task.wait(0.03)
		end
		gui.Position = base
	end)
end

-- Damped spring on a number.
export type Spring = { x: number, v: number, target: number, k: number, d: number, step: (Spring, number) -> number }
function Juice.spring(x: number, k: number?, d: number?): Spring
	local s = { x = x, v = 0, target = x, k = k or 300, d = d or 18 }
	function s.step(self: Spring, dt: number): number
		dt = math.min(dt, 1 / 30)
		local a = self.k * (self.target - self.x) - self.d * self.v
		self.v += a * dt
		self.x += self.v * dt
		return self.x
	end
	return s :: Spring
end

local soundCache: { [string]: Sound } = {}
function Juice.sound(name: string, pitch: number?, volume: number?)
	local id = Config.Sounds[name]
	if not id or id == "" then
		return
	end
	local base = soundCache[name]
	if not base then
		base = Instance.new("Sound")
		base.SoundId = id
		base.Parent = SoundService
		soundCache[name] = base
	end
	local s = base:Clone()
	s.PlaybackSpeed = pitch or 1
	s.Volume = volume or 0.6
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- Camera shake layered on top of the default camera.
local shakeUntil, shakeAmp = 0, 0
RunService:BindToRenderStep("JuiceShake", Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	if now >= shakeUntil then
		return
	end
	local k = (shakeUntil - now) * shakeAmp
	local cam = workspace.CurrentCamera
	cam.CFrame *= CFrame.new(math.noise(now * 30, 1) * k, math.noise(now * 30, 2) * k, 0)
end)
function Juice.shake(amplitude: number, duration: number)
	shakeAmp = math.max(shakeAmp * math.max(0, shakeUntil - os.clock()), amplitude) / duration
	shakeUntil = os.clock() + duration
end

-- Burst of particles at a world position (one shared emitter per color).
local burstHolder: Attachment?
local emitters: { [string]: ParticleEmitter } = {}
function Juice.burst(pos: Vector3, color: Color3, count: number, kind: string?)
	if not burstHolder then
		local a = Instance.new("Attachment")
		a.Name = "JuiceBursts"
		a.Parent = workspace.Terrain
		burstHolder = a
	end
	local key = (kind or "spark") .. color:ToHex()
	local e = emitters[key]
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.LightEmission = kind == "dust" and 0 or 0.6
		e.LightInfluence = kind == "dust" and 1 or 0
		e.Color = ColorSequence.new(color)
		if kind == "dust" then
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.35)
			e.Lifetime = NumberRange.new(0.3, 0.45)
			e.Speed = NumberRange.new(3, 5)
			e.SpreadAngle = Vector2.new(180, 10)
			e.Drag = 6
		elseif kind == "confetti" then
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
			e.Lifetime = NumberRange.new(0.8, 1.3)
			e.Speed = NumberRange.new(14, 24)
			e.SpreadAngle = Vector2.new(50, 50)
			e.Acceleration = Vector3.new(0, -35, 0)
			e.Drag = 2
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-300, 300)
		else
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
			e.Lifetime = NumberRange.new(0.25, 0.45)
			e.Speed = NumberRange.new(5, 9)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 5
		end
		e.Parent = burstHolder
		emitters[key] = e
	end
	(burstHolder :: Attachment).WorldPosition = pos
	e:Emit(count)
end

return Juice
