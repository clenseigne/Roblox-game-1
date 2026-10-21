-- Lucky blocks a food sometimes drops instead of a coin:
--   toss   -> tumbles off the pedestal onto the ramp
--   slide  -> skids down the ramp and across the dirt, then lands with a bounce
--   idle   -> floats and slowly spins above the dirt wrapped in its tier aura
--   grab   -> the owner walks up (hands free): it swoops into their hand with a white trail
-- The block in your hand is a server Tool; the HUD panel opens it for coins or tosses it:
--   open   -> a copy in the hand shakes harder and harder, swells, then bursts in its tier color;
--             the prize pet pops out, hops, and flies into the bar
--   throw  -> it's lobbed away, spinning, and vanishes in a poof
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local LuckyModel = require(ReplicatedStorage.Shared.LuckyModel)
local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Assets)
local FoodView = require(script.Parent.FoodView)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)
local Puppet = require(script.Parent.Puppet)
local Stand = require(script.Parent.Stand)
local StandPath = require(script.Parent.StandPath)

local player = Players.LocalPlayer
local INK = Color3.fromRGB(30, 21, 48)
local GOLD = Color3.fromRGB(255, 216, 74)
local WHITE = Color3.new(1, 1, 1)
local DUST = Color3.fromRGB(235, 220, 170)
local UP = Vector3.yAxis
local FLOAT = 0.45 -- hover height while idling
local GRAB_TIME = 0.4
local SHAKE_TIME = 0.8
local THROW_TIME = 0.6

type Block = {
	id: number,
	plot: number,
	slot: number?,
	tier: number,
	model: Model,
	puppet: any,
	state: string, -- toss | slide | land | idle | grab
	t0: number,
	from: Vector3,
	land: Vector3,
	stop: Vector3,
	mover: any?,
	pos: Vector3,
	yaw: number,
	tumble: number,
	requested: boolean,
	grabber: Player?,
	carrier: BasePart?,
}

-- A client-only copy of a held block, for the open / throw animations.
type Fx = {
	kind: string, -- open | throw
	tier: number,
	owner: Player?,
	model: Model,
	puppet: any,
	half: number, -- half the model's height (pivot is its bottom)
	t0: number,
	offset: Vector3, -- block center relative to the owner's hand when it started
	start: Vector3,
	dir: Vector3,
	prize: string?,
	weight: number,
	center: Vector3,
	nextTick: number,
}

local Lucky = {}
local blocks: { [number]: Block } = {}
local fxs: { Fx } = {}
local lastFullToast = 0
local opening = false
local folder = Instance.new("Folder")
folder.Name = "ClientLucky"
folder.Parent = workspace

local function rootOf(p: Player?): BasePart?
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Roughly where a held tool sits: in front of the right hand.
local function handOf(p: Player?): Vector3?
	local char = p and p.Character
	if not char then
		return nil
	end
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hand and root then
		return hand.Position + root.CFrame.LookVector * 0.9
	elseif root then
		return root.Position + root.CFrame.LookVector * 1.5
	end
	return nil
end

local function floatText(pos: Vector3, message: string, color: Color3, size: number?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = a
	gui.Size = UDim2.fromOffset(size or 300, (size or 300) / 4)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = player:WaitForChild("PlayerGui")
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = message
	t.TextColor3 = color
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = INK
	s.Parent = t
	t.Parent = gui
	Juice.popIn(t, 0.4)
	Juice.tween(gui, 1.5, { StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) })
	task.delay(1.1, function()
		Juice.tween(t, 0.4, { TextTransparency = 1 })
		Juice.tween(s, 0.4, { Transparency = 1 })
		task.wait(0.45)
		gui:Destroy()
		a:Destroy()
	end)
end

local function makeTrail(pos: Vector3): BasePart
	local carrier = Instance.new("Part")
	carrier.Name = "LuckyTrail"
	carrier.Size = Vector3.one * 0.1
	carrier.Transparency = 1
	carrier.Anchored, carrier.CanCollide, carrier.CanQuery, carrier.CanTouch = true, false, false, false
	carrier.CFrame = CFrame.new(pos)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(WHITE)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Lifetime = 0.25
	trail.MinLength = 0.02
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) })
	trail.Parent = carrier
	carrier.Parent = folder
	return carrier
end

local function dropTrail(carrier: BasePart?)
	if carrier then
		task.delay(0.3, function()
			carrier:Destroy()
		end)
	end
end

-- The prize (a pet) pops out of the burst, hops, then flies into the owner's bar.
local function prizePop(at: Vector3, foodId: string, mine: boolean)
	local view = FoodView.new(foodId, folder)
	view.scale = 0.2
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local parts, cframes = {}, {}
		local u = math.min(t / 0.7, 1)
		local h = 3.2 * 4 * u * (1 - u) + 0.6
		view.scale = 0.2 + 0.8 * Juice.easeOutBack(math.min(t / 0.35, 1))
		view:step(dt, CFrame.new(at + UP * h) * CFrame.Angles(0, t * 7, 0), 1 + 0.25 * (1 - u), parts, cframes)
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		if t >= 1.0 then
			conn:Disconnect()
			local pos = at + UP * 0.8
			view:destroy()
			Juice.burst(pos, (Config.rarityOf(foodId)).color, 12)
			if mine then
				local screen = workspace.CurrentCamera:WorldToViewportPoint(pos)
				Juice.sound("whoosh", 1.1, 0.4)
				HUD.fly(Config.Icons[foodId] or Config.CoinImage, Vector2.new(screen.X, screen.Y), HUD.slotFor(foodId), 80, 0.55, function()
					HUD.reveal(foodId)
					Juice.sound("pop", 1.25, 0.5)
				end)
			end
		end
	end)
end

-- ---------------------------------------------------------------- blocks on the stand

local function spawnBlock(index: number, l, animate: boolean)
	if blocks[l.id] then
		return
	end
	local model = Assets.lucky(l.tier)
	model.Parent = folder
	local land = l.land or l.pos
	local from = land + UP * 3
	if animate then
		local foodPos = Stand.foodPosition(index, l.from)
		if foodPos then
			from = foodPos + UP * 1.4
		end
		Stand.hiccup(index, l.from)
		Juice.sound("pop", 0.8, 0.5)
		Juice.burst(from, Config.Lucky.tiers[l.tier].color, 10)
	end
	blocks[l.id] = {
		id = l.id,
		plot = index,
		slot = l.slot,
		tier = l.tier,
		model = model,
		puppet = Puppet.new(model),
		state = if animate then "toss" else "idle",
		t0 = os.clock(),
		from = from,
		land = land,
		stop = l.pos,
		mover = nil,
		pos = if animate then from else l.pos + UP * FLOAT,
		yaw = math.random() * math.pi * 2,
		tumble = 0,
		requested = false,
		grabber = nil,
		carrier = nil,
	}
end

local function removeBlock(b: Block)
	blocks[b.id] = nil
	b.model:Destroy()
	dropTrail(b.carrier)
end

local function tryPickup(b: Block)
	if (player:GetAttribute("HeldLucky") or 0) > 0 then
		local now = os.clock()
		if now - lastFullToast > 2.5 then
			lastFullToast = now
			HUD.toast("Hands full! Open or toss your block first")
			HUD.shakeLucky()
		end
		return
	end
	b.requested = true
	task.spawn(function()
		local ok, res = pcall(function()
			return Net.func("PickupLucky"):InvokeServer(b.id)
		end)
		if not (ok and res and res.ok) then
			task.wait(0.5)
			b.requested = false
		end
	end)
end

local function startGrab(b: Block, who: Player?)
	b.state, b.t0 = "grab", os.clock()
	b.grabber = who
	b.from = b.pos
	b.carrier = makeTrail(b.pos + UP * Config.Lucky.size / 2)
	Juice.sound("whoosh", 1.25, 0.35)
	Juice.burst(b.pos + UP * Config.Lucky.size / 2, WHITE, 8)
end

local function stepBlock(b: Block, dt: number, now: number, root: BasePart?, mine: number, parts, cframes): boolean
	local age = now - b.t0
	local pos, rot = b.pos, CFrame.Angles(0, b.yaw, 0)
	local scale = 1
	if b.state == "toss" then
		local a = math.min(age / 0.55, 1)
		pos = b.from:Lerp(b.land, a) + UP * (math.sin(a * math.pi) * 3)
		rot = CFrame.Angles(a * math.pi * 2, b.yaw + a * math.pi, 0) -- tumbling
		if a >= 1 then
			Juice.sound("land", 0.7, 0.35)
			Juice.burst(b.land, DUST, 5, "dust")
			b.state, b.t0 = "slide", now
			b.mover = StandPath.new(b.plot, b.slot, b.land, b.stop, Vector3.zero) -- pivot is the block's bottom
		end
	elseif b.state == "slide" then
		local p, _, done = b.mover:step(dt)
		b.tumble += b.mover.speed * dt * 0.9
		pos = p
		rot = CFrame.Angles(math.sin(b.tumble) * 0.25, b.yaw + b.tumble * 0.4, 0)
		if done then
			b.state, b.t0, b.mover = "land", now, nil
			Juice.burst(b.stop, DUST, 6, "dust")
		end
	elseif b.state == "land" then
		-- squash-bounce up into its hover
		local u = math.min(age / 0.45, 1)
		pos = b.stop + UP * (FLOAT * Juice.easeOutBack(u))
		scale = 1 + 0.12 * math.sin(u * math.pi) * (1 - u)
		if u >= 1 then
			b.state, b.t0 = "idle", now
		end
	elseif b.state == "idle" then
		b.yaw += dt * 0.9
		pos = b.stop + UP * (FLOAT + 0.25 * math.sin(now * 2.4 + b.id))
		rot = CFrame.Angles(0, b.yaw, math.sin(now * 1.7 + b.id) * 0.08)
		if b.plot == mine and root and not b.requested
			and (root.Position - pos).Magnitude < Config.Lucky.pickupDistance then
			tryPickup(b)
		end
	elseif b.state == "grab" then
		-- curved swoop into the hand, shrinking to hand size
		local u = math.min(age / GRAB_TIME, 1)
		local e = Juice.easeInQuad(u)
		local tier = Config.Lucky.tiers[b.tier]
		local hand = handOf(b.grabber) or b.from
		local small = Config.Lucky.handSize / Config.Lucky.size
		scale = 1 + (small - 1) * Juice.easeOutCubic(u)
		local target = hand - UP * (Config.Lucky.size * (tier.scale or 1) * scale / 2) -- pivot is the bottom
		local mid = (b.from + target) / 2 + UP * 3
		pos = b.from:Lerp(mid, e):Lerp(mid:Lerp(target, e), e)
		rot = CFrame.Angles(0, b.yaw + u * math.pi * 3, 0)
		if b.carrier then
			b.carrier.CFrame = CFrame.new(pos + UP * (Config.Lucky.size * scale / 2))
		end
		if u >= 1 then
			Juice.burst(hand, WHITE, 8)
			Juice.burst(hand, tier.color, 6)
			if b.grabber == player then
				Juice.sound("pop", 1.1, 0.5)
			end
			removeBlock(b)
			return false
		end
	end
	b.pos = pos
	b.puppet:pose(CFrame.new(pos) * rot, Vector3.one * scale, 1, 0, parts, cframes)
	return true
end

-- ---------------------------------------------------------------- held block: open / throw

local function newFx(kind: string, owner: Player?, tierIndex: number, center: Vector3): Fx
	local tier = Config.Lucky.tiers[tierIndex]
	local model = LuckyModel.build(tierIndex, Config.Lucky.handSize * (tier.scale or 1))
	model.Parent = folder
	local _, size = model:GetBoundingBox()
	local hand = handOf(owner) or center
	local root = rootOf(owner)
	local fx: Fx = {
		kind = kind,
		tier = tierIndex,
		owner = owner,
		model = model,
		puppet = Puppet.new(model),
		half = size.Y / 2,
		t0 = os.clock(),
		offset = center - hand,
		start = center,
		dir = if root then root.CFrame.LookVector else Vector3.zAxis,
		prize = nil,
		weight = 10,
		center = center,
		nextTick = 0,
	}
	table.insert(fxs, fx)
	return fx
end

local function burstOpen(fx: Fx)
	local tier = Config.Lucky.tiers[fx.tier]
	local center = fx.center
	local mine = fx.owner == player
	Juice.burst(center, tier.color, 40, "confetti")
	Juice.burst(center, WHITE, 18)
	Juice.burst(center, GOLD, 16)
	Juice.sound("rare", 1, 0.7)
	floatText(center + UP * 2.5, string.upper(tier.name) .. " BLOCK!", tier.color, 340)
	if mine then
		Juice.shake(if fx.tier >= 3 then 1.2 else 0.6, 0.45)
		if fx.prize then
			HUD.banner("NEW PET!", Config.displayName(fx.prize) .. "  " .. Config.kg(fx.weight), tier.color)
		end
	end
	if fx.prize then
		prizePop(center - UP * 0.6, fx.prize, mine)
	end
end

-- Returns false when the effect is finished.
local function stepFx(fx: Fx, now: number, parts, cframes): boolean
	local age = now - fx.t0
	local center, rot, scale = fx.center, CFrame.identity, 1
	if fx.kind == "open" then
		-- shake harder and harder while swelling (follows the hand), then burst
		local u = math.min(age / SHAKE_TIME, 1)
		local k = u * u
		local hand = handOf(fx.owner)
		local base = if hand then hand + fx.offset else fx.start
		center = base + UP * (0.5 * u)
			+ Vector3.new(math.noise(now * 40, 1) * 0.3 * k, 0, math.noise(now * 40, 2) * 0.3 * k)
		rot = CFrame.Angles(math.noise(now * 30, 3) * 0.35 * k, u * 7, math.noise(now * 30, 4) * 0.35 * k)
		scale = 1 + 0.6 * k
		if age >= fx.nextTick and u < 1 then
			fx.nextTick = age + 0.16 - 0.1 * u -- rattling faster and higher
			Juice.sound("tick", 0.8 + u * 0.8, 0.3)
		end
		fx.center = center
		if u >= 1 then
			burstOpen(fx)
			return false
		end
	else
		-- lobbed away in an arc, spinning, shrinking into a poof
		local u = math.min(age / THROW_TIME, 1)
		local flat = Vector3.new(fx.dir.X, 0, fx.dir.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		center = fx.start + flat * (8 * u) + UP * (4 * u * (1 - u) * 3 - 2.5 * u * u)
		rot = CFrame.Angles(u * 9, u * 6, 0)
		scale = if u > 0.7 then 1 - (u - 0.7) / 0.3 * 0.9 else 1
		fx.center = center
		if u >= 1 then
			Juice.burst(center, DUST, 10, "dust")
			Juice.burst(center, WHITE, 10)
			Juice.sound("pop", 0.65, 0.5)
			return false
		end
	end
	local bottom = center - UP * (fx.half * scale)
	fx.puppet:pose(CFrame.new(bottom) * rot, Vector3.one * scale, 1, 0, parts, cframes)
	return true
end

local function requestOpen()
	if opening then
		return
	end
	opening = true
	local ok, res = pcall(function()
		return Net.func("OpenLucky"):InvokeServer()
	end)
	opening = false
	if not (ok and res and res.ok) then
		HUD.toast(if ok and res and res.reason then res.reason else "Can't open that right now")
		HUD.shakeLucky()
		Juice.sound("tick", 0.55, 0.45)
	end
end

local function requestToss()
	pcall(function()
		return Net.func("TossLucky"):InvokeServer()
	end)
end

-- ---------------------------------------------------------------- loop

local function step(dt: number)
	local now = os.clock()
	local root = rootOf(player)
	local mine = player:GetAttribute("Plot") or 0
	local parts, cframes = {}, {}
	for _, b in blocks do
		stepBlock(b, dt, now, root, mine, parts, cframes)
	end
	for i = #fxs, 1, -1 do
		local fx = fxs[i]
		if not stepFx(fx, now, parts, cframes) then
			fx.model:Destroy()
			table.remove(fxs, i)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Lucky.load(index: number, list)
	for _, l in list or {} do
		spawnBlock(index, l, false)
	end
end

function Lucky.init()
	HUD.onLuckyOpen = requestOpen
	HUD.onLuckyToss = requestToss
	local function held()
		HUD.setLucky(player:GetAttribute("HeldLucky") or 0)
	end
	player:GetAttributeChangedSignal("HeldLucky"):Connect(held)
	held()

	Net.event("LuckySpawned").OnClientEvent:Connect(function(index, l)
		spawnBlock(index, l, true)
	end)
	Net.event("LuckyPickedUp").OnClientEvent:Connect(function(_, id, userId)
		local b = blocks[id]
		if b then
			startGrab(b, Players:GetPlayerByUserId(userId))
		end
	end)
	Net.event("LuckyOpened").OnClientEvent:Connect(function(userId, tierIndex, petId, pos, weight)
		local owner = Players:GetPlayerByUserId(userId)
		if owner == player and petId then
			HUD.hide(petId) -- held back until the prize flies into the bar
		end
		local fx = newFx("open", owner, tierIndex, pos)
		fx.prize, fx.weight = petId, weight or 10
		Juice.sound("tick", 0.7, 0.5)
	end)
	Net.event("LuckyTossed").OnClientEvent:Connect(function(userId, tierIndex, pos)
		newFx("throw", Players:GetPlayerByUserId(userId), tierIndex, pos)
		Juice.sound("whoosh", 0.9, 0.45)
	end)
	Net.event("FoodsCleared").OnClientEvent:Connect(function(index)
		for _, b in blocks do
			if b.plot == index then
				removeBlock(b)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Lucky
