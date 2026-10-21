-- Foods placed on the food stand's pedestals, their drops (tossed onto the ramp in front of the
-- food, gliding to rest on the apron) and collection. A drop is usually a coin; sometimes it's a
-- lucky block that the owner picks up by walking up to it (see LuckyService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PetService = require(script.Parent.PetService)
local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)

type Entry = { uid: string, id: string, slot: number, seed: number, t0: number, nextDrop: number }
-- land = where it hits the ramp; pos = where it comes to rest on the apron (where it's collected)
type Coin = { id: number, slot: number, land: Vector3, pos: Vector3, value: number }
type Lucky = { id: number, slot: number, land: Vector3, pos: Vector3, tier: number }

local StandService = {}
local foods: { [number]: { [number]: Entry } } = {} -- plot -> slot -> entry
local coins: { [number]: { [number]: Coin } } = {}
local coinCount: { [number]: number } = {}
local luckies: { [number]: { [number]: Lucky } } = {}
local nextCoinId = 0
local rng = Random.new()

local REST_SPREAD_X, REST_SPREAD_Z = 2.6, 2.4 -- how far around the slot's apron spot coins can stop

local function stand(plot): Model?
	return plot.model:FindFirstChild("FoodStand") :: Model?
end

local function slotModel(plot, slot: number): Model?
	local s = stand(plot)
	return s and s:FindFirstChild("Slot" .. slot) :: Model?
end

local function slotCount(plot): number
	local s = stand(plot)
	local n = 0
	if s then
		for _, child in s:GetChildren() do
			if child:GetAttribute("Slot") then
				n += 1
			end
		end
	end
	return n
end

-- A resting spot on the apron in front of the slot, picked to sit clear of the coins already there.
local function restPosition(index: number, slot: number, rest: CFrame): Vector3
	local best, bestGap = rest.Position, -1
	for _ = 1, 8 do
		local p = rest * Vector3.new(rng:NextNumber(-REST_SPREAD_X, REST_SPREAD_X), 0, rng:NextNumber(-REST_SPREAD_Z, REST_SPREAD_Z))
		local gap = math.huge
		for _, c in coins[index] do
			if c.slot == slot then
				gap = math.min(gap, (c.pos - p).Magnitude)
			end
		end
		for _, l in luckies[index] do
			if l.slot == slot then
				gap = math.min(gap, (l.pos - p).Magnitude - 1)
			end
		end
		if gap > bestGap then
			best, bestGap = p, gap
		end
		if gap > 2.2 then
			break
		end
	end
	return best
end

local function clearPlot(index: number)
	foods[index] = {}
	coins[index] = {}
	coinCount[index] = 0
	luckies[index] = {}
	PetService.clear(index)
	Net.event("FoodsCleared"):FireAllClients(index)
end

local function pickTier(): number
	local total = 0
	for _, t in Config.Lucky.tiers do
		total += t.weight
	end
	local r = rng:NextNumber() * total
	for i, t in Config.Lucky.tiers do
		r -= t.weight
		if r <= 0 then
			return i
		end
	end
	return 1
end

local function publicEntry(e: Entry)
	return { uid = e.uid, id = e.id, slot = e.slot, seed = e.seed, t0 = e.t0 }
end

local function place(player: Player, uid: any, slot: any)
	if typeof(uid) ~= "string" or typeof(slot) ~= "number" or slot ~= math.floor(slot) then
		return false
	end
	local d = PlayerData.get(player)
	local plot = PlotService.plotOf(player)
	if not (d and plot) or slot < 1 or slot > slotCount(plot) then
		return false
	end
	if foods[plot.index][slot] then
		PlayerData.toast(player, "That pedestal is taken!")
		return false
	end
	local at
	for i, item in d.inventory do
		if item.uid == uid then
			at = i
			break
		end
	end
	if not (at and Config.Foods[d.inventory[at].id]) then -- pets go on the farm, not pedestals
		return false
	end
	local item = table.remove(d.inventory, at)
	local now = workspace:GetServerTimeNow()
	local def = Config.Foods[item.id]
	local e: Entry = {
		uid = item.uid,
		id = item.id,
		slot = slot,
		seed = rng:NextNumber(0, 10000),
		t0 = now + Config.Farm.placeTime,
		nextDrop = now + Config.Farm.placeTime + def.interval * 0.6,
	}
	foods[plot.index][slot] = e
	Net.event("FoodPlaced"):FireAllClients(plot.index, publicEntry(e))
	PlayerData.sendInventory(player)
	return true
end

local function dropCoins()
	local now = workspace:GetServerTimeNow()
	for index, list in foods do
		local plot = PlotService.plots[index]
		if not plot.owner then
			continue
		end
		for _, e in list do
			if now < e.nextDrop then
				continue
			end
			local def = Config.Foods[e.id]
			e.nextDrop = now + def.interval * rng:NextNumber(0.85, 1.15)
			if coinCount[index] >= Config.Coins.maxPerPlot then
				continue
			end
			local slot = slotModel(plot, e.slot)
			local drop = slot and slot:FindFirstChild("Drop", true) :: Attachment?
			local rest = slot and slot:FindFirstChild("Rest", true) :: Attachment?
			if not (drop and rest) then
				continue
			end
			nextCoinId += 1
			local pos = restPosition(index, e.slot, rest.WorldCFrame)
			local waiting = 0
			for _ in luckies[index] do
				waiting += 1
			end
			if waiting < Config.Lucky.maxPerPlot and rng:NextNumber() < Config.Lucky.chance then
				local lucky: Lucky = { id = nextCoinId, slot = e.slot, land = drop.WorldPosition, pos = pos, tier = pickTier() }
				luckies[index][lucky.id] = lucky
				Net.event("LuckySpawned"):FireAllClients(index, {
					id = lucky.id, from = e.uid, slot = lucky.slot, land = lucky.land, pos = lucky.pos, tier = lucky.tier,
				})
				continue
			end
			local coin: Coin = { id = nextCoinId, slot = e.slot, land = drop.WorldPosition, pos = pos, value = def.value }
			coins[index][coin.id] = coin
			coinCount[index] += 1
			Net.event("CoinSpawned"):FireAllClients(index, {
				id = coin.id, from = e.uid, slot = coin.slot, land = coin.land, pos = coin.pos, value = coin.value,
			})
		end
	end
end

-- Hands a resting lucky block to its plot's owner if they're close enough (LuckyService puts it
-- in their hand). Returns the block's tier, or nil.
function StandService.takeLucky(player: Player, id: any): number?
	if typeof(id) ~= "number" then
		return nil
	end
	local plot = PlotService.plotOf(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lucky = plot and luckies[plot.index][id]
	if not (plot and root and lucky) then
		return nil
	end
	if (root.Position - lucky.pos).Magnitude > Config.Lucky.pickupDistance + Config.Coins.collectSlack then
		return nil
	end
	luckies[plot.index][id] = nil
	Net.event("LuckyPickedUp"):FireAllClients(plot.index, id, player.UserId)
	return lucky.tier
end

local function collect(player: Player, ids: any)
	if typeof(ids) ~= "table" then
		return
	end
	local plot = PlotService.plotOf(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (plot and root) then
		return
	end
	local list = coins[plot.index]
	local reach = Config.Coins.magnetRadius + Config.Coins.collectSlack
	local total, removed = 0, {}
	for i, id in ids do
		if i > 80 then
			break
		end
		local coin = typeof(id) == "number" and list[id]
		if coin and (root.Position - coin.pos).Magnitude <= reach then
			total += coin.value
			list[id] = nil
			coinCount[plot.index] -= 1
			table.insert(removed, id)
		end
	end
	if total > 0 then
		PlayerData.addCoins(player, total)
		Net.event("CoinsRemoved"):FireAllClients(plot.index, removed, player.UserId)
	end
end

local function getState()
	local state = {}
	for index, plot in PlotService.plots do
		local plotFoods, plotCoins, plotLuckies = {}, {}, {}
		for _, e in foods[index] do
			table.insert(plotFoods, publicEntry(e))
		end
		for _, c in coins[index] do
			table.insert(plotCoins, { id = c.id, pos = c.pos, value = c.value })
		end
		for _, l in luckies[index] do
			table.insert(plotLuckies, { id = l.id, slot = l.slot, pos = l.pos, tier = l.tier })
		end
		state[index] = {
			owner = plot.owner and plot.owner.UserId or 0,
			foods = plotFoods,
			coins = plotCoins,
			luckies = plotLuckies,
			pets = PetService.state(index),
		}
	end
	return state
end

function StandService.init()
	for index in PlotService.plots do
		foods[index] = {}
		coins[index] = {}
		coinCount[index] = 0
		luckies[index] = {}
	end
	PlotService.onReleased = clearPlot
	Net.func("Place").OnServerInvoke = place
	Net.func("GetState").OnServerInvoke = getState
	Net.event("Collect").OnServerEvent:Connect(collect)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			dropCoins()
		end
	end)
end

return StandService
