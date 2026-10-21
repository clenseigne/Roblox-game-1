-- Per-player session state (no saving in the test build).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Item = { uid: string, id: string, weight: number? } -- weight (kg): pets only
export type Data = {
	coins: number,
	inventory: { Item },
	lastRoll: number,
	uidCounter: number,
}

local PlayerData = {}
local data: { [Player]: Data } = {}

local function add(player: Player)
	data[player] = { coins = 0, inventory = {}, lastRoll = -math.huge, uidCounter = 0 }
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player
	player:SetAttribute("Coins", 0)
end

function PlayerData.init()
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		add(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		data[p] = nil
	end)
end

function PlayerData.get(player: Player): Data?
	return data[player]
end

function PlayerData.addCoins(player: Player, amount: number)
	local d = data[player]
	if not d then
		return
	end
	d.coins = math.max(0, d.coins + amount)
	player:SetAttribute("Coins", d.coins)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins") :: IntValue?
	if value then
		value.Value = d.coins
	end
end

function PlayerData.newUid(player: Player): string
	local d = data[player] :: Data
	d.uidCounter += 1
	return player.UserId .. "_" .. d.uidCounter
end

function PlayerData.sendInventory(player: Player)
	local d = data[player]
	if d then
		Net.event("InventoryChanged"):FireClient(player, d.inventory)
	end
end

function PlayerData.toast(player: Player, text: string)
	Net.event("Toast"):FireClient(player, text)
end

return PlayerData
