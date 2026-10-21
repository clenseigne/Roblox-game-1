-- Pets on the farm. A lucky block gives you a pet (it goes into your bar); you let it out on your
-- farm, where it roams (Shared/FoodWander: deterministic from its seed and server time, so nothing
-- is replicated per frame and the server knows where it is); then you walk up to it and feed it
-- coins: each feed adds weight (kg), and it grows. Auras won in the Wilds are applied to a pet to multiply
-- its power; a pet that loses a fight there is knocked out (resting on the farm) for a while.
-- Hold E on a pet to ride it: the player's "Mounted" attribute holds its uid, their humanoid rides
-- higher (on its back) and faster; every client draws the pet under its rider (Pets.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodWander = require(ReplicatedStorage.Shared.FoodWander)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)

-- x/z = landing spot in farm-local studs, t0 = landing time (FoodWander entry)
type FarmPet = {
	uid: string,
	id: string,
	weight: number, -- kg: its power and size
	seed: number,
	x: number,
	z: number,
	t0: number,
	aura: string?,
	koUntil: number, -- server time; knocked out (can't fight) until then
}

type Ride = { uid: string, hip: number, walk: number, jump: number }

local PetService = {}
local riding: { [Player]: Ride } = {}
local farmPets: { [number]: { [string]: FarmPet } } = {} -- plot -> uid -> pet
local rng = Random.new()

local function petsOf(index: number): { [string]: FarmPet }
	local list = farmPets[index]
	if not list then
		list = {}
		farmPets[index] = list
	end
	return list
end

-- The farm's roaming frame for a pet (bigger pets keep further from the fence).
local function frameOf(plot, id: string): (CFrame?, number, number)
	local floor = plot.model:FindFirstChild("FarmFloor") :: BasePart?
	if not floor then
		return nil, 0, 0
	end
	local def = Config.Pets[id]
	return FoodWander.frame(floor, def and def.margin or Config.Pet.margin)
end

local function public(p: FarmPet)
	return { uid = p.uid, id = p.id, weight = p.weight, seed = p.seed, x = p.x, z = p.z, t0 = p.t0, aura = p.aura, ko = p.koUntil }
end

local function count(list): number
	local n = 0
	for _ in list do
		n += 1
	end
	return n
end

local function placePet(player: Player, uid: any, x: any, z: any)
	if typeof(uid) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" or x ~= x or z ~= z then
		return false
	end
	local d = PlayerData.get(player)
	local plot = PlotService.plotOf(player)
	if not (d and plot) then
		return false
	end
	local list = petsOf(plot.index)
	if count(list) >= Config.Pet.maxOnFarm then
		PlayerData.toast(player, "Your farm is full of pets!")
		return false
	end
	local at
	for i, item in d.inventory do
		if item.uid == uid and Config.isPet(item.id) then
			at = i
			break
		end
	end
	if not at then
		return false
	end
	local frame, hx, hz = frameOf(plot, d.inventory[at].id)
	if not frame then
		return false
	end
	local item = table.remove(d.inventory, at)
	local pet: FarmPet = {
		uid = item.uid,
		id = item.id,
		weight = item.weight or Config.Pet.baseWeight,
		seed = rng:NextNumber(0, 10000),
		x = math.clamp(x, -hx, hx),
		z = math.clamp(z, -hz, hz),
		t0 = workspace:GetServerTimeNow() + Config.Farm.placeTime,
		aura = nil,
		koUntil = 0,
	}
	list[pet.uid] = pet
	Net.event("PetPlaced"):FireAllClients(plot.index, public(pet))
	PlayerData.sendInventory(player)
	return true
end

-- Where a farm pet is right now (FoodWander, same as every client) and how close you must be.
local function nearPet(player: Player, plot, pet: FarmPet): boolean
	local frame, hx, hz = frameOf(plot, pet.id)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (frame and root) then
		return false
	end
	local s = FoodWander.sample(pet, workspace:GetServerTimeNow(), hx, hz)
	local pos = frame * Vector3.new(s.x, 0, s.z)
	local def = Config.Pets[pet.id]
	local reach = Config.Pet.feedDistance + (def and def.height or 3.4) * Config.petScale(pet.weight) + Config.Coins.collectSlack
	return (Vector3.new(root.Position.X, pos.Y, root.Position.Z) - pos).Magnitude <= reach
end

local function feed(player: Player, uid: any)
	local d = PlayerData.get(player)
	local plot = PlotService.plotOf(player)
	local pet = plot and typeof(uid) == "string" and petsOf(plot.index)[uid]
	if not (d and plot and pet) then
		return { ok = false, reason = "That's not your pet!" }
	end
	if riding[player] and riding[player].uid == pet.uid then
		return { ok = false, reason = "Hop off to feed it!" }
	end
	if not nearPet(player, plot, pet) then
		return { ok = false, reason = "Get closer to your pet!" }
	end
	local cost = Config.petCost(pet.weight)
	if d.coins < cost then
		return { ok = false, reason = "Need " .. Format.short(cost) .. " coins!" }
	end
	PlayerData.addCoins(player, -cost)
	pet.weight = math.floor((pet.weight + Config.feedGain(pet.weight)) * 10 + 0.5) / 10
	Net.event("PetFed"):FireAllClients(plot.index, pet.uid, pet.weight, player.UserId)
	if riding[player] and riding[player].uid == pet.uid then
		PetService.refreshRide(player)
	end
	return { ok = true, weight = pet.weight, cost = Config.petCost(pet.weight) }
end

-- Gives a pet one of your auras (replacing the one it had).
local function applyAura(player: Player, auraUid: any, petUid: any)
	local d = PlayerData.get(player)
	local plot = PlotService.plotOf(player)
	local pet = plot and typeof(petUid) == "string" and petsOf(plot.index)[petUid]
	if not (d and pet and typeof(auraUid) == "string") then
		return { ok = false }
	end
	local at
	for i, item in d.inventory do
		if item.uid == auraUid and Config.isAura(item.id) then
			at = i
			break
		end
	end
	if not at then
		return { ok = false }
	end
	local aura = table.remove(d.inventory, at).id
	pet.aura = aura
	Net.event("PetAura"):FireAllClients(plot.index, pet.uid, aura)
	PlayerData.sendInventory(player)
	return { ok = true, aura = aura }
end

-- ---------------------------------------------------------------- riding

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Ride height (the pet's back) and speed for the pet a player is on.
function PetService.refreshRide(player: Player)
	local ride = riding[player]
	local plot = PlotService.plotOf(player)
	local pet = ride and plot and petsOf(plot.index)[ride.uid]
	local humanoid = humanoidOf(player)
	if not (pet and humanoid) then
		return
	end
	local def = Config.Pets[pet.id]
	local back = (def and def.height or 3.4) * Config.petScale(pet.weight) * 0.8 -- seat on its back
	humanoid.HipHeight = math.max(ride.hip, back)
	humanoid.WalkSpeed = Config.rideSpeed(pet.weight)
end

-- Climb on a pet. `force` skips the walk-up check (getting back on after a fight).
function PetService.mount(player: Player, uid: any, force: boolean?)
	local plot = PlotService.plotOf(player)
	local pet = plot and typeof(uid) == "string" and petsOf(plot.index)[uid]
	local humanoid = humanoidOf(player)
	if not (pet and humanoid) or humanoid.Health <= 0 then
		return { ok = false }
	end
	if pet.koUntil > workspace:GetServerTimeNow() then
		return { ok = false, reason = "It's resting after that fight!" }
	end
	if not force and not nearPet(player, plot, pet) then
		return { ok = false, reason = "Get closer to your pet!" }
	end
	local old = riding[player]
	riding[player] = {
		uid = pet.uid,
		hip = if old then old.hip else humanoid.HipHeight,
		walk = if old then old.walk else humanoid.WalkSpeed,
		jump = if old then old.jump else humanoid.JumpPower,
	}
	PetService.refreshRide(player)
	player:SetAttribute("Mounted", pet.uid)
	return { ok = true }
end

-- Hop off: the pet goes back to roaming the farm.
function PetService.dismount(player: Player)
	local ride = riding[player]
	riding[player] = nil
	player:SetAttribute("Mounted", "")
	local humanoid = humanoidOf(player)
	if ride and humanoid then
		humanoid.HipHeight = ride.hip
		humanoid.WalkSpeed = ride.walk
	end
	return { ok = true }
end

-- The pet a player is riding, if any (it's the one that fights in the Wilds).
function PetService.mountOf(player: Player): FarmPet?
	local ride = riding[player]
	local plot = PlotService.plotOf(player)
	local pet = ride and plot and petsOf(plot.index)[ride.uid]
	if pet and pet.koUntil <= workspace:GetServerTimeNow() then
		return pet
	end
	return nil
end

-- Any farm pets at all (to tell "no pets" apart from "all knocked out").
function PetService.hasPets(player: Player): boolean
	local plot = PlotService.plotOf(player)
	return plot ~= nil and next(petsOf(plot.index)) ~= nil
end

function PetService.knockOut(player: Player, uid: string)
	local plot = PlotService.plotOf(player)
	local pet = plot and petsOf(plot.index)[uid]
	if pet then
		pet.koUntil = workspace:GetServerTimeNow() + Config.Wilds.koTime
		Net.event("PetKO"):FireAllClients(plot.index, uid, pet.koUntil)
		if riding[player] and riding[player].uid == uid then
			PetService.dismount(player)
		end
	end
end

-- Farm pets of a plot, for GetState.
function PetService.state(index: number)
	local out = {}
	for _, p in petsOf(index) do
		table.insert(out, public(p))
	end
	return out
end

-- The plot was released (its owner left): the pets go with them.
function PetService.clear(index: number)
	farmPets[index] = {}
end

function PetService.init()
	Net.func("PlacePet").OnServerInvoke = placePet
	Net.func("Feed").OnServerInvoke = feed
	Net.func("ApplyAura").OnServerInvoke = applyAura
	Net.func("Mount").OnServerInvoke = function(player, uid)
		return PetService.mount(player, uid)
	end
	Net.func("Dismount").OnServerInvoke = function(player)
		return PetService.dismount(player)
	end
	local Players = game:GetService("Players")
	local function watch(player: Player)
		player:SetAttribute("Mounted", "")
		player.CharacterAdded:Connect(function()
			riding[player] = nil -- a fresh character starts on foot
			player:SetAttribute("Mounted", "")
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		riding[p] = nil
	end)
end

return PetService
