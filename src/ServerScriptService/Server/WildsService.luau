-- The Wilds: walk into the brush with a pet and, like Pokemon, every few steps there's a chance a
-- wild pet jumps out. Its weight (kg) comes from the zone you're in (each brush box carries
-- MinWeight/MaxWeight): the further down the runway, the heavier. The odds of winning come from both
-- sides' power (weight x aura); you see
-- them and choose to fight or run. A fight is one 1-100 roll: over the line wins an aura, under
-- it knocks your pet out.
--
-- The pet you're riding is the one that fights: you hop off for the battle and climb back on
-- after a win (a loss knocks it out, so you walk home).
-- Player attributes for the client: InWilds (bool), Companion (pet uid or "").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PetService = require(script.Parent.PetService)
local PlayerData = require(script.Parent.PlayerData)

type Encounter = {
	id: number,
	species: string,
	weight: number, -- kg
	aura: string, -- worn in the fight (adds to its power), won if you beat it
	petUid: string,
	petWeight: number,
	chance: number, -- whole percent
	line: number, -- roll over this to win
	started: number,
}
type State = { last: Vector3?, walked: number, cooldownUntil: number, encounter: Encounter?, remount: string? }

local WildsService = {}
local states: { [Player]: State } = {}
local nextId = 0
local rng = Random.new()
local zone: BasePart? = nil
local brushZones: { BasePart } = {}

local function inside(box: BasePart, p: Vector3): boolean
	local lp = box.CFrame:PointToObjectSpace(p)
	local h = box.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Z) <= h.Z and math.abs(lp.Y) <= h.Y
end

local function brushAt(p: Vector3): BasePart?
	for _, b in brushZones do
		if inside(b, p) then
			return b
		end
	end
	return nil
end

local function pickWeighted(weights: { [string]: number }): string
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = rng:NextNumber() * total
	local last
	for id, w in weights do
		last = id
		r -= w
		if r <= 0 then
			return id
		end
	end
	return last
end

-- Who jumps out: one of the zone's species (its "Species" attribute), else the default pool.
local function pickSpecies(brush: BasePart): string
	local list = brush:GetAttribute("Species")
	if typeof(list) == "string" and list ~= "" then
		local options = string.split(list, ",")
		return options[rng:NextInteger(1, #options)]
	end
	return pickWeighted(Config.Wilds.species)
end

-- The aura a wild one carries (and drops when beaten): rarer ones get likelier the heavier it is
-- compared to your pet.
local function pickAura(weight: number, petWeight: number): string
	local luck = 1 + math.max(0, weight / petWeight - 1) * 0.8
	local weights = {}
	for id, a in Config.PetAuras do
		weights[id] = a.weight * luck ^ (a.tier - 1)
	end
	return pickWeighted(weights)
end

local function startEncounter(player: Player, st: State, pet, brush: BasePart)
	local lo, hi = brush:GetAttribute("MinWeight"), brush:GetAttribute("MaxWeight")
	local spread = Config.Wilds.weightSpread
	local raw = if lo and hi then rng:NextNumber(lo, hi) else pet.weight * rng:NextNumber(spread[1], spread[2])
	local weight = math.floor(raw * 10 + 0.5) / 10
	local aura = pickAura(weight, pet.weight)
	local mine = Config.petPower(pet.weight, pet.aura)
	local chance = Config.winChance(mine, Config.petPower(weight, aura))
	nextId += 1
	local e: Encounter = {
		id = nextId,
		species = pickSpecies(brush),
		weight = weight,
		aura = aura,
		petUid = pet.uid,
		petWeight = pet.weight,
		chance = chance,
		line = 100 - chance,
		started = os.clock(),
	}
	st.encounter = e
	-- hop off so the pet can fight
	st.remount = pet.uid
	PetService.dismount(player)
	Net.event("EncounterStarted"):FireClient(player, {
		id = e.id,
		species = e.species,
		weight = e.weight,
		aura = e.aura,
		wildPower = Config.petPower(e.weight, e.aura),
		petUid = pet.uid,
		petId = pet.id,
		petWeight = pet.weight,
		petAura = pet.aura,
		power = mine,
		chance = e.chance,
		line = e.line,
	})
end

local function tick()
	for _, player in Players:GetPlayers() do
		local st = states[player]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (st and root) then
			continue
		end
		local pos = root.Position
		local wilds = zone ~= nil and inside(zone, pos)
		if player:GetAttribute("InWilds") ~= wilds then
			player:SetAttribute("InWilds", wilds)
		end
		local pet = if wilds then PetService.mountOf(player) else nil
		-- during a fight the companion stays put even if it gets knocked out
		local companion = if st.encounter then st.encounter.petUid elseif pet then pet.uid else ""
		if player:GetAttribute("Companion") ~= companion then
			player:SetAttribute("Companion", companion)
		end
		local e = st.encounter
		if e and os.clock() - e.started > 90 then
			st.encounter = nil -- abandoned
			if st.remount then
				PetService.mount(player, st.remount, true)
				st.remount = nil
			end
		end
		local moved = if st.last then Vector3.new(pos.X - st.last.X, 0, pos.Z - st.last.Z).Magnitude else 0
		st.last = pos
		local brush = brushAt(pos)
		if not (pet and brush and not st.encounter and os.clock() >= st.cooldownUntil) then
			continue
		end
		if moved > 12 then
			continue -- teleported, not walking
		end
		st.walked += moved
		while st.walked >= Config.Wilds.stepDistance do
			st.walked -= Config.Wilds.stepDistance
			if rng:NextNumber() < Config.Wilds.encounterChance then
				st.walked = 0
				startEncounter(player, st, pet, brush :: BasePart)
				break
			end
		end
	end
end

local function fight(player: Player, id: any)
	local st = states[player]
	local e = st and st.encounter
	local d = PlayerData.get(player)
	if not (e and d and e.id == id) then
		return { ok = false }
	end
	st.encounter = nil
	local roll = rng:NextInteger(1, 100)
	local win = roll > e.line
	local result = { ok = true, roll = roll, line = e.line, win = win, aura = nil :: string? }
	if win then
		local aura = e.aura -- you win the aura it was wearing
		result.aura = aura
		table.insert(d.inventory, { uid = PlayerData.newUid(player), id = aura })
		task.delay(3.2, PlayerData.sendInventory, player) -- after the battle plays out
		local uid = st.remount
		task.delay(4.4, function() -- back on once the victory hop is done
			if uid and states[player] and not states[player].encounter then
				PetService.mount(player, uid, true)
			end
		end)
	else
		PetService.knockOut(player, e.petUid)
	end
	st.remount = nil
	st.cooldownUntil = os.clock() + Config.Wilds.cooldown + 4
	return result
end

local function run(player: Player, id: any)
	local st = states[player]
	if st and st.encounter and st.encounter.id == id then
		st.encounter = nil
		st.cooldownUntil = os.clock() + Config.Wilds.cooldown
		if st.remount then
			PetService.mount(player, st.remount, true)
			st.remount = nil
		end
	end
	return { ok = true }
end

function WildsService.init()
	task.spawn(function()
		local wilds = workspace:WaitForChild("Wilds", 30)
		if not wilds then
			warn("WildsService: no Workspace.Wilds (run src/build/BuildWilds.luau)")
			return
		end
		zone = wilds:WaitForChild("Zone") :: BasePart
		for _, b in wilds:WaitForChild("BrushZones"):GetChildren() do
			if b:IsA("BasePart") then
				table.insert(brushZones, b)
			end
		end
	end)
	local function add(player: Player)
		states[player] = { last = nil, walked = 0, cooldownUntil = 0, encounter = nil }
		player:SetAttribute("InWilds", false)
		player:SetAttribute("Companion", "")
	end
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		add(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end)
	Net.func("Fight").OnServerInvoke = fight
	Net.func("Run").OnServerInvoke = run
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			tick()
		end
	end)
end

return WildsService
