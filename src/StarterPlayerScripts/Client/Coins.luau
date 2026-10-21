-- 3D food coins (Blender model + burger sticker) and their trip from the food stand to the player:
--   toss   -> the food hiccups and tosses the coin, flipping, onto the ramp in front of it
--   slide  -> it speeds down the ramp, then glides out across the flat apron and slows to a stop
--   settle -> spinning-coin settle (Euler's disk wobble) where it stops
--   idle   -> lies flat; every few seconds wiggles or hop-flips
--   collect-> walk along the apron: each coin pops up and swoops along a curve into you with a
--             white trail, finishing in a sparkle with a rising-pitch ding on chains
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Assets)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)
local Stand = require(script.Parent.Stand)
local StandPath = require(script.Parent.StandPath)

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 216, 74)
local WHITE = Color3.new(1, 1, 1)
local UP = Vector3.yAxis
local RADIUS = 1.0 -- coin radius in studs (Assets.coin scales it to 2 across)

type Coin = {
	id: number,
	plot: number,
	value: number,
	model: Model,
	parts: { { part: BasePart, rel: CFrame } },
	thickness: number,
	state: string, -- toss | slide | settle | idle | flip | pop | swoop
	slot: number?,
	t0: number,
	from: Vector3,
	land: Vector3, -- where it hits the ramp (surface level)
	stop: Vector3, -- where it comes to rest on the apron (surface level)
	mover: any?, -- StandPath while sliding
	pos: Vector3,
	rot: CFrame,
	yaw: number,
	settleAmp: number,
	settleDur: number,
	nextEvent: number,
	wobble: number,
	target: Player?,
	mine: boolean,
	curve: Vector3?,
	carrier: BasePart?,
}

local Coins = {}
local coins: { [number]: Coin } = {}
local pending: { number } = {}
local chain, lastCollect, lastDing = 0, 0, 0
local DING_GAP = 0.075 -- a scoop of coins plays a clean run of dings, not a pile-up
local folder = Instance.new("Folder")
folder.Name = "ClientCoins"
folder.Parent = workspace

local function myPlot(): number
	return player:GetAttribute("Plot") or 0
end

local function rootOf(p: Player?): BasePart?
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function restHeight(coin: Coin): number
	return coin.thickness / 2 + 0.03
end

local function startSettle(coin: Coin, now: number, amp: number, dur: number)
	coin.state, coin.t0 = "settle", now
	coin.settleAmp, coin.settleDur = amp, dur
end

local function scheduleIdle(coin: Coin, now: number)
	coin.state, coin.t0 = "idle", now
	coin.nextEvent = now + 2.5 + math.random() * 4.5
end

-- ---------------------------------------------------------------- lifecycle

local function spawnCoin(index: number, c, animate: boolean)
	if coins[c.id] then
		return
	end
	local model, thickness = Assets.coin()
	model.Parent = folder
	local parts = {}
	local pivot = model:GetPivot()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, rel = pivot:ToObjectSpace(p.CFrame) })
		end
	end
	local land = c.land or c.pos
	local from = land + Vector3.new(0, 3, 0)
	if animate then
		local foodPos = Stand.foodPosition(index, c.from)
		if foodPos then
			from = foodPos + Vector3.new(0, 1.6, 0)
		end
		Stand.hiccup(index, c.from)
		Juice.sound("pop", 1.1 + math.random() * 0.2, 0.35)
	end
	local now = os.clock()
	local coin: Coin = {
		id = c.id,
		plot = index,
		value = c.value,
		model = model,
		parts = parts,
		thickness = thickness,
		state = if animate then "toss" else "idle",
		slot = c.slot,
		t0 = now,
		from = from,
		land = land,
		stop = c.pos,
		mover = nil,
		pos = if animate then from else c.pos + Vector3.new(0, thickness / 2 + 0.03, 0),
		rot = CFrame.identity,
		yaw = math.random() * math.pi * 2,
		settleAmp = 0,
		settleDur = 0,
		nextEvent = now + math.random() * 5,
		wobble = 0,
		target = nil,
		mine = false,
		curve = nil,
		carrier = nil,
	}
	coins[c.id] = coin
end

local function destroy(coin: Coin)
	coins[coin.id] = nil
	coin.model:Destroy()
	local carrier = coin.carrier
	if carrier then
		local trail = carrier:FindFirstChildOfClass("Trail")
		task.delay(if trail then trail.Lifetime + 0.05 else 0, function()
			carrier:Destroy()
		end)
	end
end

local function makeTrail(coin: Coin)
	local carrier = Instance.new("Part")
	carrier.Name = "CoinTrail"
	carrier.Size = Vector3.one * 0.1
	carrier.Transparency = 1
	carrier.Anchored, carrier.CanCollide, carrier.CanQuery, carrier.CanTouch = true, false, false, false
	carrier.CFrame = CFrame.new(coin.pos)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.5, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.5, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(WHITE)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Lifetime = 0.22
	trail.MinLength = 0.02
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) })
	trail.Parent = carrier
	carrier.Parent = folder
	coin.carrier = carrier
end

-- Starts the collect: a little pop up, then a curved swoop with a trail into `who`.
local function beginCollect(coin: Coin, who: Player, mine: boolean, now: number)
	coin.state, coin.t0 = "pop", now
	coin.target, coin.mine = who, mine
	coin.from = coin.pos
	makeTrail(coin)
end

local function finishCollect(coin: Coin)
	if coin.mine then
		local now = os.clock()
		chain = if now - lastCollect < 0.6 then math.min(chain + 1, 14) else 0
		lastCollect = now
		if now - lastDing >= DING_GAP then
			lastDing = now
			Juice.sound("coin", 1 + math.min(chain, 10) * 0.03, 0.32)
		end
		table.insert(pending, coin.id)
		HUD.predict(coin.value)
	end
	Juice.burst(coin.pos, WHITE, 6)
	Juice.burst(coin.pos, GOLD, 5)
	destroy(coin)
end

local function step(dt: number)
	local now = os.clock()
	local mine = myPlot()
	local root = rootOf(player)
	local radius = Config.Coins.magnetRadius
	local parts, cframes = {}, {}
	for _, coin in coins do
		local age = now - coin.t0
		local rest = coin.stop + UP * restHeight(coin)
		local pos, rot = coin.pos, coin.rot

		if coin.state == "toss" then
			-- tossed off the pedestal, flipping, onto the ramp in front of it
			local a = math.min(age / 0.45, 1)
			local landRest = coin.land + UP * restHeight(coin)
			pos = coin.from:Lerp(landRest, a) + UP * (math.sin(a * math.pi) * 2.5)
			rot = CFrame.Angles(0, coin.yaw + a * 3, 0) * CFrame.Angles(a * math.pi * 3, 0, 0)
			if a >= 1 then
				Juice.sound("pop", 1.5 + math.random() * 0.2, 0.15) -- clink onto the ramp
				coin.state, coin.t0, coin.wobble = "slide", now, 0.4
				coin.pos = landRest
				coin.mover = StandPath.new(coin.plot, coin.slot, coin.land, coin.stop, UP * restHeight(coin))
			end
		elseif coin.state == "slide" then
			local mover = coin.mover
			local p, leveled, done = mover:step(dt)
			if leveled then
				coin.wobble = 0.3 -- little clack leveling off
			end
			coin.wobble = math.max(0, coin.wobble - dt * 1.2)
			coin.yaw += mover.speed * dt * 0.35
			local wob = coin.wobble * math.sin(now * 30)
			pos = p
			rot = CFrame.Angles(wob, coin.yaw, wob * 0.6)
			if done then
				coin.mover = nil
				startSettle(coin, now, 0.32, 0.8)
			end
		elseif coin.state == "settle" then
			-- spinning-coin settle: the tilt decays while the wobble spins up
			local u = age
			local tilt = coin.settleAmp * math.exp(-3.4 * u / coin.settleDur) * math.max(0, 1 - u / coin.settleDur)
			local phi = u * 14 + u * u * 16
			local axis = Vector3.new(math.cos(phi), 0, math.sin(phi))
			pos = rest + UP * (RADIUS * math.sin(tilt))
			rot = CFrame.fromAxisAngle(axis, tilt) * CFrame.Angles(0, coin.yaw, 0)
			if u >= coin.settleDur then
				pos, rot = rest, CFrame.Angles(0, coin.yaw, 0)
				scheduleIdle(coin, now)
			end
		elseif coin.state == "idle" then
			pos = rest
			rot = CFrame.Angles(0, coin.yaw, 0)
			if now >= coin.nextEvent then
				if math.random() < 0.6 then
					startSettle(coin, now, 0.22, 0.7) -- wiggle
				else
					coin.state, coin.t0 = "flip", now
				end
			end
		elseif coin.state == "flip" then
			local u = math.min(age / 0.5, 1)
			pos = rest + UP * (1.6 * 4 * u * (1 - u))
			rot = CFrame.Angles(0, coin.yaw, 0) * CFrame.Angles(u * math.pi * 2, 0, 0)
			if u >= 1 then
				coin.yaw += 0.6
				startSettle(coin, now, 0.3, 0.8)
			end
		elseif coin.state == "pop" then
			-- anticipation: hop up and flip toward the collector
			local u = math.min(age / 0.13, 1)
			pos = coin.from + UP * (1.4 * Juice.easeOutCubic(u))
			rot = CFrame.Angles(0, coin.yaw + u * 2, 0) * CFrame.Angles(u * math.pi, 0, 0)
			if u >= 1 then
				coin.state, coin.t0, coin.from = "swoop", now, pos
				-- curve out to one side so it swoops in rather than flying straight
				local who = rootOf(coin.target)
				local toTarget = if who then (who.Position - pos) * Vector3.new(1, 0, 1) else Vector3.zAxis
				local side = UP:Cross(if toTarget.Magnitude > 0.01 then toTarget.Unit else Vector3.zAxis)
				coin.curve = pos + UP * 4 + side * (if math.random() < 0.5 then -3.5 else 3.5)
			end
		elseif coin.state == "swoop" then
			local who = rootOf(coin.target)
			if not who then
				destroy(coin)
				continue
			end
			local u = math.min(age / 0.4, 1)
			local e = u ^ 1.6 -- accelerate into the player
			local target = who.Position + UP * 0.6
			local c = coin.curve :: Vector3
			pos = coin.from * (1 - e) ^ 2 + c * (2 * (1 - e) * e) + target * (e * e)
			rot = CFrame.Angles(age * 22, age * 15, 0)
			if u >= 1 then
				coin.pos = pos
				finishCollect(coin)
				continue
			end
		end

		-- walk-up pickup once the coin has stopped on the apron
		local resting = coin.state == "idle" or coin.state == "settle" or coin.state == "flip"
		if resting and coin.plot == mine and root and (root.Position - pos).Magnitude < radius then
			beginCollect(coin, player, true, now)
		end

		if coin.carrier then
			local vel = pos - coin.pos
			coin.carrier.CFrame = if vel.Magnitude > 1e-3 then CFrame.lookAt(pos, pos + vel) else CFrame.new(pos)
		end
		coin.pos, coin.rot = pos, rot
		local root2 = CFrame.new(pos) * rot
		for _, entry in coin.parts do
			table.insert(parts, entry.part)
			table.insert(cframes, root2 * entry.rel)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Coins.load(index: number, list)
	for _, c in list do
		spawnCoin(index, c, false)
	end
end

function Coins.init()
	Net.event("CoinSpawned").OnClientEvent:Connect(function(index, c)
		spawnCoin(index, c, true)
	end)
	Net.event("CoinsRemoved").OnClientEvent:Connect(function(index, ids, collectorId)
		local collector = Players:GetPlayerByUserId(collectorId)
		for _, id in ids do
			local coin = coins[id]
			if coin and coin.state ~= "pop" and coin.state ~= "swoop" and collector then
				-- someone else's pickup (or one we never animated): swoop it to them, no local credit
				beginCollect(coin, collector, false, os.clock())
			end
		end
	end)
	Net.event("FoodsCleared").OnClientEvent:Connect(function(index)
		for _, coin in coins do
			if coin.plot == index then
				destroy(coin)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		while true do
			task.wait(0.1)
			if #pending > 0 then
				local batch = pending
				pending = {}
				Net.event("Collect"):FireServer(batch)
			end
		end
	end)
end

return Coins
