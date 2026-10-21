-- Pets, rendered locally. On the farm each one follows Shared/FoodWander (the same path the server
-- computes): waddles from spot to spot with swinging legs and little hop-steps, looks around,
-- sometimes does a happy jump, breathes and blinks. Walk up to your own pet and press F to feed
-- it (coins stream into its mouth, it gulps and grows) or hold E to ride it.
-- A ridden pet runs along under its rider (whose "Mounted" attribute holds its uid), legs going
-- with their speed; a battle (Battle.luau) takes control of it while it fights. Pets with an
-- aura wear its effect; knocked-out pets rest on the farm.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodWander = require(ReplicatedStorage.Shared.FoodWander)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Assets)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)
local PetCard = require(script.Parent.PetCard)
local Puppet = require(script.Parent.Puppet)

local player = Players.LocalPlayer
local INK = Color3.fromRGB(30, 21, 48)
local PINK = Color3.fromRGB(255, 140, 200)
local GREY = Color3.fromRGB(190, 190, 205)
local DUST = Color3.fromRGB(235, 220, 170)
local UP = Vector3.yAxis

export type Pet = {
	plot: number,
	uid: string,
	id: string,
	weight: number, -- kg
	aura: string?,
	koUntil: number,
	entry: any, -- FoodWander entry { seed, x, z, t0 }
	model: Model,
	puppet: any,
	body: BasePart,
	scale: any,
	squash: any,
	yaw: number,
	pos: Vector3,
	lastHop: number,
	wasAir: boolean,
	prompt: ProximityPrompt?,
	adventure: ProximityPrompt?,
	tag: BillboardGui,
	tagText: TextLabel,
	auraCore: BasePart?,
	following: boolean,
	vel: Vector3,
	phase: number,
	controlled: boolean,
}

local Pets = {}
local pets: { [string]: Pet } = {}
local owners: { [number]: number } = {}
local frames: { [string]: { cf: CFrame, hx: number, hz: number } } = {}
local busy = false
local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local function rootOf(p: Player?): BasePart?
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A plot's farm frame for one kind of pet (same as the server's: bigger pets keep further in).
local function frameOf(index: number, id: string)
	local key = index .. id
	local f = frames[key]
	if not f then
		local plot = workspace:WaitForChild("Plots"):FindFirstChild("Plot" .. index)
		local floor = plot and plot:FindFirstChild("FarmFloor") :: BasePart?
		if not floor then
			return nil
		end
		local def = Config.Pets[id]
		local cf, hx, hz = FoodWander.frame(floor, def and def.margin or Config.Pet.margin)
		f = { cf = cf, hx = hx, hz = hz }
		frames[key] = f
	end
	return f
end

local function heightOf(pet): number
	local def = Config.Pets[pet.id]
	return def and def.height or Config.Pet.baseHeight
end
Pets.heightOf = heightOf

local function mouthOf(pet: Pet): Vector3
	local def = Config.Pets[pet.id]
	local m = def and def.mouth or { 0.41, 0.47 }
	local h = heightOf(pet) * pet.scale.x
	local fwd = Vector3.new(-math.sin(pet.yaw), 0, -math.cos(pet.yaw))
	return pet.pos + fwd * (m[1] * h) + UP * (m[2] * h)
end

local function knockedOut(pet: Pet): boolean
	return pet.koUntil > workspace:GetServerTimeNow()
end

local function cardInfo(pet: Pet): PetCard.Info
	return { uid = pet.uid, id = pet.id, weight = pet.weight, aura = pet.aura, ko = knockedOut(pet) }
end

local function promptText(pet: Pet)
	local aura = pet.aura and Config.PetAuras[pet.aura]
	local power = Config.petPower(pet.weight, pet.aura)
	if pet.prompt then
		pet.prompt.ActionText = "Feed  " .. Format.short(Config.petCost(pet.weight)) .. " coins"
		pet.prompt.ObjectText = Config.displayName(pet.id) .. "  " .. Config.kg(pet.weight)
			.. (if aura then "  |  " .. aura.name else "")
	end
	if pet.adventure then
		pet.adventure.ObjectText = Config.displayName(pet.id) .. "  |  Power " .. Format.short(power)
	end
	PetCard.update(cardInfo(pet))
	if knockedOut(pet) then
		pet.tagText.Text = "Resting..."
		pet.tagText.TextColor3 = GREY
	else
		pet.tagText.Text = Config.kg(pet.weight)
		pet.tagText.TextColor3 = if aura then aura.color else PINK
	end
end

local function makeTag(pet: Pet)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = pet.body
	gui.Size = UDim2.fromOffset(120, 34)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = player:WaitForChild("PlayerGui")
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = PINK
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = INK
	s.Parent = t
	t.Parent = gui
	pet.tag, pet.tagText = gui, t
end

-- The aura effect (Assets.Auras.<vfx>: an invisible core part with emitters), sized to the pet.
local function setAura(pet: Pet)
	if pet.auraCore then
		pet.auraCore:Destroy()
		pet.auraCore = nil
	end
	local def = pet.aura and Config.PetAuras[pet.aura]
	local auras = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Auras")
	local src = def and auras and auras:FindFirstChild(def.vfx)
	if not src then
		return
	end
	local core = (src :: BasePart):Clone()
	local holder = Instance.new("Model")
	core.Parent = holder
	holder:ScaleTo(math.clamp(heightOf(pet) * Config.petScale(pet.weight) / 3.2, 0.8, 4))
	core.Name = "Aura"
	core.Transparency = 1
	core.Anchored, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, false, false, false, false
	core.Parent = folder
	holder:Destroy()
	pet.auraCore = core
end

local function request(pet: Pet, fn: string): any
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(function()
		return Net.func(fn):InvokeServer(pet.uid)
	end)
	busy = false
	return if ok then res else nil
end

-- Feed / ride requests (from the F / E keys or the pet card's buttons).
local function act(pet: Pet, fn: string)
	local res = request(pet, fn)
	if res and not res.ok and res.reason then
		HUD.toast(res.reason)
		pet.squash.v += 4 -- a little "hm?" wobble
		Juice.sound("tick", 0.55, 0.45)
	end
end

local nearUid: string? = nil -- the pet whose prompts are showing (the card's pet)

local function riding(): boolean
	return (player:GetAttribute("Mounted") or "") ~= ""
end

-- The prompts are invisible (Style = Custom): they only handle the keys and the "near your pet"
-- check; the pet card (PetCard.luau) is what you see.
local function setPrompt(pet: Pet)
	local mine = owners[pet.plot] == player.UserId
	if mine and not pet.prompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FeedPrompt"
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Pet.feedDistance + heightOf(pet) * 0.5
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function()
			act(pet, "Feed")
		end)
		prompt.PromptShown:Connect(function()
			nearUid = pet.uid
			if not riding() then
				PetCard.show(cardInfo(pet))
			end
		end)
		prompt.PromptHidden:Connect(function()
			if nearUid == pet.uid then
				nearUid = nil
			end
			PetCard.hide(pet.uid)
		end)
		prompt.Parent = pet.body
		pet.prompt = prompt
		local adventure = Instance.new("ProximityPrompt")
		adventure.Name = "RidePrompt"
		adventure.Style = Enum.ProximityPromptStyle.Custom
		adventure.ActionText = "Ride"
		adventure.KeyboardKeyCode = Enum.KeyCode.E
		adventure.HoldDuration = Config.Pet.mountHold
		adventure.MaxActivationDistance = prompt.MaxActivationDistance
		adventure.RequiresLineOfSight = false
		adventure.Triggered:Connect(function()
			PetCard.hold(false)
			act(pet, "Mount")
		end)
		adventure.PromptButtonHoldBegan:Connect(function()
			if PetCard.showing() == pet.uid then
				PetCard.hold(true, Config.Pet.mountHold)
			end
		end)
		adventure.PromptButtonHoldEnded:Connect(function()
			PetCard.hold(false)
		end)
		adventure.Parent = pet.body
		pet.adventure = adventure
		promptText(pet)
	elseif not mine and pet.prompt then
		pet.prompt:Destroy()
		pet.prompt = nil
		if pet.adventure then
			pet.adventure:Destroy()
			pet.adventure = nil
		end
		PetCard.hide(pet.uid)
	end
end

local function add(index: number, e, animate: boolean)
	if pets[e.uid] then
		return
	end
	local model = Assets.pet(e.id)
	model.Name = "Pet_" .. e.uid
	model.Parent = folder
	-- the biggest "Body" part carries the prompts and weight tag (any part if there's no Body)
	local body: BasePart = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	local bestBody = false
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local isBody = string.sub(part.Name, 1, 4) == "Body"
			if (isBody and not bestBody) or (isBody == bestBody and part.Size.Magnitude > body.Size.Magnitude) then
				body, bestBody = part, isBody
			end
		end
	end
	local weight = e.weight or Config.Pet.baseWeight
	local pet: Pet = {
		plot = index,
		uid = e.uid,
		id = e.id,
		weight = weight,
		aura = e.aura,
		koUntil = e.ko or 0,
		entry = e,
		model = model,
		puppet = Puppet.new(model),
		body = body,
		scale = Juice.spring(if animate then 0.15 else Config.petScale(weight), 170, 9),
		squash = Juice.spring(1, 300, 14),
		yaw = math.random() * math.pi * 2,
		pos = Vector3.zero,
		lastHop = -1,
		wasAir = false,
		prompt = nil,
		adventure = nil,
		tag = nil :: any,
		tagText = nil :: any,
		auraCore = nil,
		following = false,
		vel = Vector3.zero,
		phase = 0,
		controlled = false,
	}
	makeTag(pet)
	pets[e.uid] = pet
	setPrompt(pet)
	promptText(pet)
	setAura(pet)
	if animate then
		pet.scale.target = Config.petScale(weight)
		pet.scale.v += 6 -- pops out big, then settles
		local f = frameOf(index, e.id)
		if f then
			local at = f.cf * Vector3.new(e.x, 0, e.z)
			Juice.burst(at + UP, PINK, 18, "confetti")
			Juice.burst(at, DUST, 8, "dust")
		end
		Juice.sound("pop", 0.85, 0.6)
	end
end

local function remove(pet: Pet)
	pets[pet.uid] = nil
	PetCard.hide(pet.uid)
	pet.model:Destroy()
	pet.tag:Destroy()
	if pet.auraCore then
		pet.auraCore:Destroy()
	end
end

-- ---------------------------------------------------------------- feeding / auras

local function flyCoin(from: Vector3, pet: Pet, delayTime: number, onArrive: () -> ())
	task.delay(delayTime, function()
		local a = Instance.new("Attachment")
		a.WorldPosition = from
		a.Parent = workspace.Terrain
		local gui = Instance.new("BillboardGui")
		gui.Adornee = a
		gui.Size = UDim2.fromScale(1.6, 1.6)
		gui.LightInfluence = 0
		gui.Parent = player:WaitForChild("PlayerGui")
		local img = Instance.new("ImageLabel")
		img.Image = Config.CoinImage
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = gui
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local u = math.clamp((os.clock() - t0) / 0.38, 0, 1)
			local to = mouthOf(pet)
			a.WorldPosition = from:Lerp(to, Juice.easeInQuad(u)) + UP * (math.sin(u * math.pi) * 3)
			img.Size = UDim2.fromScale(math.max(0.15, math.abs(math.cos(os.clock() * 16))), 1)
			if u >= 1 then
				conn:Disconnect()
				gui:Destroy()
				a:Destroy()
				onArrive()
			end
		end)
	end)
end

local function popup(pet: Pet, text: string, color: Color3)
	local a = Instance.new("Attachment")
	a.WorldPosition = mouthOf(pet) + UP * (2.5 * pet.scale.x)
	a.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = a
	gui.Size = UDim2.fromOffset(260, 70)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = player:WaitForChild("PlayerGui")
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = INK
	s.Parent = t
	t.Parent = gui
	Juice.popIn(t, 0.4)
	Juice.tween(gui, 1.3, { StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) })
	task.delay(0.9, function()
		Juice.tween(t, 0.35, { TextTransparency = 1 })
		Juice.tween(s, 0.35, { Transparency = 1 })
		task.wait(0.4)
		gui:Destroy()
		a:Destroy()
	end)
end

local function onFed(_, uid: string, weight: number, userId: number)
	local pet = pets[uid]
	if not pet then
		return
	end
	local gained = weight - pet.weight
	pet.weight = weight
	promptText(pet)
	local feeder = Players:GetPlayerByUserId(userId)
	local root = rootOf(feeder)
	local from = if root then root.Position + UP * 1.5 else mouthOf(pet) + UP * 4
	local n = 6
	for i = 1, n do
		flyCoin(from, pet, (i - 1) * 0.06, function()
			pet.squash.v -= 3.5 -- gulp
			Juice.sound("gulp", 0.9 + i * 0.05, 0.4)
			if i == n then
				pet.scale.target = Config.petScale(weight)
				pet.scale.v += 3.5 -- inflate past the new size, then settle
				Juice.burst(mouthOf(pet), PINK, 22, "confetti")
				Juice.sound("grow", 1, 0.6)
				popup(pet, string.format("+%.1f kg!", gained), PINK)
				if PetCard.showing() == pet.uid then
					PetCard.punchFeed()
				end
				setAura(pet) -- resize it with the pet
			end
		end)
	end
end

local function onAura(_, uid: string, aura: string)
	local pet = pets[uid]
	local def = Config.PetAuras[aura]
	if not (pet and def) then
		return
	end
	pet.aura = aura
	setAura(pet)
	promptText(pet)
	pet.squash.v -= 6
	pet.scale.v += 4
	local at = pet.pos + UP * heightOf(pet) * pet.scale.x * 0.5
	Juice.burst(at, def.color, 36, "confetti")
	Juice.burst(at, Color3.new(1, 1, 1), 16)
	Juice.sound("grow", 1.1, 0.6)
	popup(pet, def.name .. "!  x" .. def.mult, def.color)
end

-- ---------------------------------------------------------------- moving


local function riderOf(pet: Pet): Player?
	local owner = Players:GetPlayerByUserId(owners[pet.plot] or 0)
	if owner and owner:GetAttribute("Mounted") == pet.uid then
		return owner
	end
	return nil
end

local function poof(at: Vector3, pet: Pet)
	Juice.burst(at + UP * heightOf(pet) * 0.5, Color3.new(1, 1, 1), 14)
	Juice.burst(at, DUST, 8, "dust")
end

-- Ridden: the pet runs along right under its rider, facing where they face, legs going with
-- their speed and a little gallop bob. It sits a fixed distance under the rider (their hip
-- height), so it jumps when they jump.
local function stepRide(pet: Pet, rider: Player, dt: number, now: number, k: number, parts, cframes)
	local root = rootOf(rider)
	if not root then
		return
	end
	local humanoid = rider.Character and rider.Character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	pet.pos = root.Position - UP * (root.Size.Y / 2 + hip)
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = math.clamp(speed / 10, 0, 1)
	pet.phase += dt * (4 + speed * 0.45) / math.sqrt(k) * moving
	local legSwing = math.sin(pet.phase * 2) * 0.65 * moving
	local bob = math.abs(math.sin(pet.phase * 2)) * 0.3 * k * moving
	pet.squash.target = 1 - 0.07 * moving * math.abs(math.cos(pet.phase * 2)) + 0.03 * math.sin(now * 2.2)
	local look = root.CFrame.LookVector
	pet.yaw = Juice.lerpAngle(pet.yaw, math.atan2(-look.X, -look.Z), Juice.smoothing(14, dt))
	local sq = math.clamp(pet.squash:step(dt), 0.6, 1.5)
	local sxz = 1 / math.sqrt(sq)
	pet.puppet:pose(CFrame.new(pet.pos + UP * bob) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(-0.06 * moving, 0, 0),
		Vector3.new(sxz * k, sq * k, sxz * k), pet.puppet:blink(now), legSwing, parts, cframes)
end

local function stepFarm(pet: Pet, dt: number, now: number, t: number, k: number, parts, cframes)
	local f = frameOf(pet.plot, pet.id)
	if not f then
		return
	end
	local s = FoodWander.sample(pet.entry, t, f.hx, f.hz)
	pet.pos = f.cf * Vector3.new(s.x, 0, s.z)
	local ko = knockedOut(pet)
	-- face where it's going, plus a look-around while it rests
	local dir = f.cf:VectorToWorldSpace(Vector3.new(s.dx, 0, s.dz))
	if dir.Magnitude > 0.01 then
		local desired = math.atan2(-dir.X, -dir.Z) + s.look
		pet.yaw = Juice.lerpAngle(pet.yaw, desired, Juice.smoothing(8, dt))
	end
	-- squash/stretch: crouch before a hop, stretch in the air, squash on landing
	if s.hop ~= pet.lastHop then
		if pet.wasAir then
			pet.squash.v -= if s.big then 7 else 2.5
			if s.big then
				Juice.burst(pet.pos, DUST, 4, "dust")
			end
		end
		pet.lastHop = s.hop
	end
	pet.wasAir = s.air
	local breathe = 0.03 * math.sin(now * 2.2 + pet.entry.seed)
	pet.squash.target = (1 - 0.22 * s.crouch + (if s.air then 0.12 * math.sin(s.phase * math.pi) else 0) + breathe)
		* (if ko then 0.85 else 1) -- knocked out: slumped
	local sq = math.clamp(pet.squash:step(dt), 0.6, 1.5)
	local sxz = 1 / math.sqrt(sq)
	local legSwing = if s.air and not s.big then math.sin(s.phase * math.pi * 2) * 0.55
		elseif s.big then 0.35 * math.sin(s.phase * math.pi)
		else 0
	local spin = if s.big then s.phase * math.pi * 2 else 0
	local rootCf = CFrame.new(pet.pos + UP * (s.h * math.sqrt(k)))
		* CFrame.Angles(0, pet.yaw + spin, 0) * CFrame.Angles(0, 0, s.roll + (if ko then 0.12 else 0))
	pet.puppet:pose(rootCf, Vector3.new(sxz * k, sq * k, sxz * k), if ko then 0.15 else pet.puppet:blink(now),
		legSwing, parts, cframes)
end

local lastKoCheck = 0
local function step(dt: number)
	local now = os.clock()
	local t = workspace:GetServerTimeNow()
	local parts, cframes = {}, {}
	local refreshTags = now - lastKoCheck > 1
	if refreshTags then
		lastKoCheck = now
	end
	for _, pet in pets do
		local k = pet.scale:step(dt)
		if refreshTags then
			promptText(pet) -- "Resting..." ends on its own
		end
		if not pet.controlled then
			local owner = riderOf(pet)
			if (owner ~= nil) ~= pet.following then
				-- poof out of one place and into the other (onto the rider / back to the farm)
				poof(pet.pos, pet)
				pet.following = owner ~= nil
				pet.vel = Vector3.zero
				if owner then
					local root = rootOf(owner)
					if root then
						pet.pos = root.Position
					end
					pet.squash.v -= 6 -- oof, someone climbed on
				end
				for _, prompt in { pet.prompt, pet.adventure } do
					if prompt then
						prompt.Enabled = not pet.following
					end
				end
				task.defer(function()
					poof(pet.pos, pet)
				end)
				Juice.sound("pop", 1.1, 0.4)
			end
			if owner then
				stepRide(pet, owner, dt, now, k, parts, cframes)
			else
				stepFarm(pet, dt, now, t, k, parts, cframes)
			end
		end
		pet.tag.StudsOffsetWorldSpace = UP * (heightOf(pet) * k * 0.75 + 1)
		if pet.auraCore then
			table.insert(parts, pet.auraCore)
			table.insert(cframes, CFrame.new(pet.pos + UP * heightOf(pet) * k * 0.5))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------- API

function Pets.load(index: number, list)
	for _, e in list or {} do
		add(index, e, false)
	end
end

function Pets.setOwner(index: number, userId: number)
	owners[index] = userId
	for _, pet in pets do
		if pet.plot == index then
			setPrompt(pet)
		end
	end
end

function Pets.get(uid: string): Pet?
	return pets[uid]
end

-- A battle poses the pet itself while it fights (the aura keeps following pet.pos).
function Pets.setControlled(uid: string, on: boolean)
	local pet = pets[uid]
	if pet then
		pet.controlled = on
		pet.tag.Enabled = not on
	end
end

-- Your own farm pets, for picking one on screen (giving an aura).
function Pets.mine(): { Pet }
	local out = {}
	local index = player:GetAttribute("Plot") or 0
	for _, pet in pets do
		if pet.plot == index and not pet.following then
			table.insert(out, pet)
		end
	end
	return out
end

function Pets.init()
	Net.event("PetPlaced").OnClientEvent:Connect(function(index, e)
		add(index, e, true)
	end)
	Net.event("PetFed").OnClientEvent:Connect(onFed)
	Net.event("PetAura").OnClientEvent:Connect(onAura)
	Net.event("PetKO").OnClientEvent:Connect(function(_, uid: string, koUntil: number)
		local pet = pets[uid]
		if pet then
			pet.koUntil = koUntil
			promptText(pet)
		end
	end)
	Net.event("FoodsCleared").OnClientEvent:Connect(function(index)
		for _, pet in pets do
			if pet.plot == index then
				remove(pet)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)

	-- the pet card's buttons, and hiding it while you ride (back when you hop off beside it)
	PetCard.onFeed = function(uid)
		local pet = pets[uid]
		if pet then
			act(pet, "Feed")
		end
	end
	PetCard.onRide = function(uid)
		local pet = pets[uid]
		if pet then
			act(pet, "Mount")
		end
	end
	player:GetAttributeChangedSignal("Mounted"):Connect(function()
		local pet = nearUid and pets[nearUid]
		if riding() then
			PetCard.hide()
		elseif pet then
			PetCard.show(cardInfo(pet))
		end
	end)
	task.spawn(function() -- a resting pet wakes up on its own: keep the card current
		while true do
			task.wait(0.5)
			local uid = PetCard.showing()
			local pet = uid and pets[uid]
			if pet then
				PetCard.update(cardInfo(pet))
			end
		end
	end)
end

return Pets
