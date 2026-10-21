-- The lucky block in your hand. You can hold one at a time: walking up to a block on your stand
-- picks it up (if your hands are free); then you either open it for coins (a pet) or toss it.
-- The held block is a Tool so the character holds it out; the player's "HeldLucky" attribute
-- (tier index, 0 = empty) drives the client UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local LuckyModel = require(ReplicatedStorage.Shared.LuckyModel)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local StandService = require(script.Parent.StandService)

type Held = { tier: number, tool: Tool }

local LuckyService = {}
local held: { [Player]: Held } = {}

local function makeTool(tierIndex: number): Tool
	local tier = Config.Lucky.tiers[tierIndex]
	local tool = Instance.new("Tool")
	tool.Name = tier.name .. " Lucky Block"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true -- opened from the UI, not by clicking the world
	tool:SetAttribute("LuckyTier", tierIndex)
	local model = LuckyModel.build(tierIndex, Config.Lucky.handSize * (tier.scale or 1))
	local _, size = model:GetBoundingBox()
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one
	handle.Transparency = 1
	handle.CanCollide, handle.CanQuery, handle.CanTouch, handle.Massless = false, false, false, true
	handle.CFrame = CFrame.new(0, size.Y / 2, 0) -- block center
	for _, p in model:GetDescendants() do
		if p:IsA("ParticleEmitter") then
			p.Rate *= 0.4 -- a calmer aura in hand so it doesn't swallow the character
		elseif p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = handle, p
			weld.Parent = handle
		end
	end
	handle.Parent = tool
	model.Parent = tool
	tool.Grip = CFrame.new(0, -0.2, 0.9) -- held out in front of the hand
	return tool
end

local function clear(player: Player)
	local h = held[player]
	held[player] = nil
	if h and h.tool.Parent then
		h.tool:Destroy()
	end
	player:SetAttribute("HeldLucky", 0)
end

local function handPosition(player: Player, h: Held): Vector3
	local handle = h.tool:FindFirstChild("Handle") :: BasePart?
	if handle and h.tool.Parent == player.Character then
		return handle.Position
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position + Vector3.new(0, 1, 0) else Vector3.zero
end

local function equip(player: Player, h: Held)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and held[player] == h then
		humanoid:EquipTool(h.tool)
	end
end

local function pickup(player: Player, id: any)
	if held[player] then
		return { ok = false, reason = "handsFull" }
	end
	local tierIndex = StandService.takeLucky(player, id)
	if not tierIndex then
		return { ok = false }
	end
	local tool = makeTool(tierIndex)
	local h: Held = { tier = tierIndex, tool = tool }
	held[player] = h
	player:SetAttribute("HeldLucky", tierIndex)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
	-- keep it in hand: no unequipping it into the (hidden) backpack
	tool.Unequipped:Connect(function()
		task.defer(equip, player, h)
	end)
	task.delay(0.42, equip, player, h) -- after the block's swoop lands in the hand
	return { ok = true, tier = tierIndex }
end

local function open(player: Player)
	local h = held[player]
	local d = PlayerData.get(player)
	if not (h and d) then
		return { ok = false }
	end
	local tier = Config.Lucky.tiers[h.tier]
	if d.coins < tier.cost then
		return { ok = false, reason = "Need " .. Format.short(tier.cost) .. " coins to open!" }
	end
	if #d.inventory >= Config.Roll.maxInventory then
		return { ok = false, reason = "Bag full! Place some food or pets first." }
	end
	local pos = handPosition(player, h)
	PlayerData.addCoins(player, -tier.cost)
	local petId = tier.pet or "Hippo"
	local weight = math.floor((tier.kg or 10) * (0.85 + math.random() * 0.3) * 10 + 0.5) / 10
	table.insert(d.inventory, { uid = PlayerData.newUid(player), id = petId, weight = weight })
	clear(player)
	Net.event("LuckyOpened"):FireAllClients(player.UserId, h.tier, petId, pos, weight)
	PlayerData.sendInventory(player)
	return { ok = true, pet = petId, weight = weight }
end

local function toss(player: Player)
	local h = held[player]
	if not h then
		return { ok = false }
	end
	local pos = handPosition(player, h)
	clear(player)
	Net.event("LuckyTossed"):FireAllClients(player.UserId, h.tier, pos)
	return { ok = true }
end

function LuckyService.init()
	Net.func("PickupLucky").OnServerInvoke = pickup
	Net.func("OpenLucky").OnServerInvoke = open
	Net.func("TossLucky").OnServerInvoke = toss
	local function watch(player: Player)
		player:SetAttribute("HeldLucky", 0)
		player.CharacterRemoving:Connect(function()
			clear(player) -- respawning empties your hands
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		held[p] = nil
	end)
end

return LuckyService
