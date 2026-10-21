local Server = script.Parent

local PlayerData = require(Server.PlayerData)
local PlotService = require(Server.PlotService)
local StandService = require(Server.StandService)
local RollService = require(Server.RollService)
local PetService = require(Server.PetService)
local LuckyService = require(Server.LuckyService)
local WildsService = require(Server.WildsService)

PlayerData.init()
PlotService.init()
StandService.init()
RollService.init()
PetService.init()
LuckyService.init()
WildsService.init()
