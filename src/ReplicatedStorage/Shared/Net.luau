-- Remote registry. The server creates ReplicatedStorage.Remotes on first require; clients wait for it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"RollStarted", -- s->all (plotIndex, foodId, userId)
	"FoodPlaced", -- s->all (plotIndex, entry)
	"FoodsCleared", -- s->all (plotIndex)
	"CoinSpawned", -- s->all (plotIndex, coin)
	"Collect", -- c->s ({coinId})
	"CoinsRemoved", -- s->all (plotIndex, {coinId}, collectorUserId)
	"PlotChanged", -- s->all (plotIndex, ownerUserId or 0)
	"InventoryChanged", -- s->owner ({ {uid, id} })
	"PetPlaced", -- s->all (plotIndex, farmPet)
	"PetFed", -- s->all (plotIndex, petUid, weight, feederUserId)
	"PetAura", -- s->all (plotIndex, petUid, auraId)
	"PetKO", -- s->all (plotIndex, petUid, koUntil server time)
	"EncounterStarted", -- s->owner (encounter)
	"Toast", -- s->owner (text)
	"LuckySpawned", -- s->all (plotIndex, lucky)
	"LuckyPickedUp", -- s->all (plotIndex, luckyId, userId)
	"LuckyOpened", -- s->all (userId, tier, petId, worldPos, weight)
	"LuckyTossed", -- s->all (userId, tier, worldPos)
}
local FUNCTIONS = { "Roll", "Place", "PlacePet", "Feed", "ApplyAura", "Mount", "Dismount", "Fight", "Run", "GetState", "PickupLucky", "OpenLucky", "TossLucky" }

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder or Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Net = {}

function Net.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
