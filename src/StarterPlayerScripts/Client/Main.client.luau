local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Client = script.Parent
local HUD = require(Client.HUD)
local Stand = require(Client.Stand)
local Coins = require(Client.Coins)
local Lucky = require(Client.Lucky)
local Roll = require(Client.Roll)
local Placement = require(Client.Placement)
local Pets = require(Client.Pets)
local Battle = require(Client.Battle)
local Mount = require(Client.Mount)

local player = Players.LocalPlayer
player.CameraMaxZoomDistance = 80

HUD.init()
Stand.init()
Coins.init()
Lucky.init()
Roll.init()
Placement.init()
Pets.init()
Battle.init()
Mount.init()

local function setOwner(index: number, userId: number)
	Stand.setOwner(index, userId)
	Roll.setOwner(index, userId)
	Pets.setOwner(index, userId)
end

Net.event("PlotChanged").OnClientEvent:Connect(setOwner)
local state = Net.func("GetState"):InvokeServer()
for index, plot in state do
	setOwner(index, plot.owner)
	for _, entry in plot.foods do
		Stand.add(index, entry, false)
	end
	Coins.load(index, plot.coins)
	Lucky.load(index, plot.luckies)
	Pets.load(index, plot.pets)
end
