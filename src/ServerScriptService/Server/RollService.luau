-- Weighted food rolls at the player's own machine (free in the test build, short cooldown).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)

local RollService = {}
local rng = Random.new()

-- Weighted food pick. luck > 1 boosts rarer foods: weight * luck^(rarity order - 1).
local function pick(luck: number?): string
	local boost = luck or 1
	local weights, total = {}, 0
	for _, id in Config.FoodOrder do
		local w = Config.Foods[id].weight * boost ^ ((Config.rarityOf(id)).order - 1)
		weights[id] = w
		total += w
	end
	local r = rng:NextNumber() * total
	for _, id in Config.FoodOrder do
		r -= weights[id]
		if r <= 0 then
			return id
		end
	end
	return Config.FoodOrder[1]
end
RollService.pick = pick

local function roll(player: Player)
	local d = PlayerData.get(player)
	local plot = PlotService.plotOf(player)
	if not (d and plot) then
		return { ok = false, reason = "You need a farm first!" }
	end
	local now = os.clock()
	if now - d.lastRoll < Config.Roll.cooldown then
		return { ok = false, reason = "cooldown" }
	end
	if #d.inventory >= Config.Roll.maxInventory then
		return { ok = false, reason = "Bag full! Place some food first." }
	end
	local machine = plot.model:FindFirstChild("RollMachine") :: Model
	if not PlotService.near(player, machine and machine.PrimaryPart, Config.Roll.maxDistance) then
		return { ok = false, reason = "Get closer to the machine!" }
	end
	d.lastRoll = now
	local id = pick()
	local uid = PlayerData.newUid(player)
	table.insert(d.inventory, { uid = uid, id = id })
	Net.event("RollStarted"):FireAllClients(plot.index, id, player.UserId)
	PlayerData.sendInventory(player)
	return { ok = true, uid = uid, id = id }
end

function RollService.init()
	Net.func("Roll").OnServerInvoke = roll
end

return RollService
