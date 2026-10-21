-- Hands each joining player one of the plots and sends them home on spawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

export type Plot = {
	index: number,
	model: Model,
	owner: Player?,
	farmCf: CFrame, -- top surface of the farm floor
	hx: number, -- roamable half extents (farm-local)
	hz: number,
}

local PlotService = {}
PlotService.plots = {} :: { [number]: Plot }
PlotService.onReleased = nil :: ((number) -> ())?
local byPlayer: { [Player]: Plot } = {}

local function setSign(plot: Plot, text: string)
	local board = plot.model:FindFirstChild("SignBoard")
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChild("OwnerLabel") :: TextLabel?
	if label then
		label.Text = text
	end
end

local function sendHome(player: Player)
	local plot = byPlayer[player]
	local char = player.Character
	if not (plot and char) then
		return
	end
	local pad = plot.model:FindFirstChild("SpawnPad") :: BasePart
	local farm = plot.model:FindFirstChild("FarmFloor") :: BasePart
	local pos = pad.Position + Vector3.new(0, 3.5, 0)
	char:PivotTo(CFrame.lookAt(pos, Vector3.new(farm.Position.X, pos.Y, farm.Position.Z)))
end

local function assign(player: Player)
	for i = 1, #PlotService.plots do
		local plot = PlotService.plots[i]
		if not plot.owner then
			plot.owner = player
			byPlayer[player] = plot
			player:SetAttribute("Plot", i)
			setSign(plot, player.DisplayName .. "'s Plot")
			Net.event("PlotChanged"):FireAllClients(i, player.UserId)
			break
		end
	end
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart")
		task.wait()
		sendHome(player)
	end)
	if player.Character then
		sendHome(player)
	end
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.owner = nil
	setSign(plot, "Empty Plot")
	if PlotService.onReleased then
		PlotService.onReleased(plot.index)
	end
	Net.event("PlotChanged"):FireAllClients(plot.index, 0)
end

function PlotService.init()
	for _, model in workspace:WaitForChild("Plots"):GetChildren() do
		local index = model:GetAttribute("Index")
		local floor = model:FindFirstChild("FarmFloor") :: BasePart
		PlotService.plots[index] = {
			index = index,
			model = model :: Model,
			owner = nil,
			farmCf = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0),
			hx = floor.Size.X / 2 - Config.Farm.margin,
			hz = floor.Size.Z / 2 - Config.Farm.margin,
		}
	end
	Players.PlayerAdded:Connect(assign)
	for _, p in Players:GetPlayers() do
		assign(p)
	end
	Players.PlayerRemoving:Connect(release)
end

function PlotService.plotOf(player: Player): Plot?
	return byPlayer[player]
end

-- True when the player's character is within maxDistance of part.
function PlotService.near(player: Player, part: BasePart?, maxDistance: number): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and part ~= nil and (root.Position - part.Position).Magnitude <= maxDistance
end

return PlotService
