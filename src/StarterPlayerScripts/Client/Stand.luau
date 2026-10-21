-- Renders each plot's food stand: foods sitting on their pedestals, facing the pocket. They blink,
-- look around, do little hops (sometimes a big twirl), and hiccup when they spit out a coin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local FoodView = require(script.Parent.FoodView)
local Juice = require(script.Parent.Juice)

type Slot = { model: Model, stage: CFrame, ring: BasePart?, rampEnd: Vector3? }
type Rec = {
	view: any,
	entry: any,
	slot: number,
	from: Vector3?,
	stage: CFrame,
	lastPos: Vector3,
	nextHop: number,
	hopStart: number,
	hopBig: boolean,
	inAir: boolean,
	lookSeed: number,
}
type PlotView = {
	model: Model,
	owner: number,
	slots: { [number]: Slot },
	views: { [number]: Rec }, -- by slot
	byUid: { [string]: number },
}

local Stand = {}
Stand.plots = {} :: { [number]: PlotView }

local folder = Instance.new("Folder")
folder.Name = "ClientFoods"
folder.Parent = workspace

local DUST = Color3.fromRGB(235, 220, 170)

local function ownerRoot(plot: PlotView): BasePart?
	local player = Players:GetPlayerByUserId(plot.owner)
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Stand.add(index: number, entry, animate: boolean)
	local plot = Stand.plots[index]
	local slot = plot and plot.slots[entry.slot]
	if not slot or plot.views[entry.slot] then
		return
	end
	local root = animate and ownerRoot(plot)
	local now = os.clock()
	plot.views[entry.slot] = {
		view = FoodView.new(entry.id, folder),
		entry = entry,
		slot = entry.slot,
		from = root and root.Position + Vector3.new(0, 1.5, 0) or nil,
		stage = slot.stage,
		lastPos = slot.stage.Position,
		nextHop = now + 0.8 + math.random() * 1.5,
		hopStart = -math.huge,
		hopBig = false,
		inAir = false,
		lookSeed = math.random() * 10,
	}
	plot.byUid[entry.uid] = entry.slot
end

function Stand.clear(index: number)
	local plot = Stand.plots[index]
	if not plot then
		return
	end
	for _, rec in plot.views do
		rec.view:destroy()
	end
	plot.views, plot.byUid = {}, {}
end

local function recFor(index: number, uid: string): Rec?
	local plot = Stand.plots[index]
	local slot = plot and plot.byUid[uid]
	return slot and plot.views[slot]
end

function Stand.foodPosition(index: number, uid: string): Vector3?
	local rec = recFor(index, uid)
	return rec and rec.lastPos
end

-- Squash + a little hop when a food spits out a coin.
function Stand.hiccup(index: number, uid: string)
	local rec = recFor(index, uid)
	if rec then
		rec.view:kick(-7)
		rec.hopStart, rec.hopBig = os.clock(), false
	end
end

function Stand.setOwner(index: number, userId: number)
	local plot = Stand.plots[index]
	if plot then
		plot.owner = userId
	end
end

function Stand.freeSlots(index: number): { [number]: Slot }
	local plot = Stand.plots[index]
	local free = {}
	if plot then
		for n, slot in plot.slots do
			if not plot.views[n] then
				free[n] = slot
			end
		end
	end
	return free
end

local function step(dt: number)
	local t = workspace:GetServerTimeNow()
	local now = os.clock()
	local parts, cframes = {}, {}
	local placeTime = Config.Farm.placeTime
	for _, plot in Stand.plots do
		for _, rec in plot.views do
			local e = rec.entry
			local view = rec.view
			local root: CFrame
			local stretch = 1
			if t < e.t0 then
				-- flying from the owner's hands up onto the pedestal
				local a = math.clamp(1 - (e.t0 - t) / placeTime, 0, 1)
				local spot = rec.stage.Position
				local from = rec.from or spot + Vector3.new(0, 8, 0)
				local pos = from:Lerp(spot, a) + Vector3.new(0, math.sin(a * math.pi) * 5, 0)
				view.scale = 0.35 + 0.65 * Juice.easeOutBack(a)
				root = CFrame.new(pos) * rec.stage.Rotation * CFrame.Angles(0, a * math.pi * 2, 0)
				stretch = 1.3
				rec.inAir = true
			else
				-- idle on the pedestal: little hops, sometimes a big twirl
				if now >= rec.nextHop then
					rec.hopStart = now
					rec.hopBig = math.random() < 0.18
					rec.nextHop = now + 1.4 + math.random() * 1.8
				end
				local dur = if rec.hopBig then 0.62 else 0.38
				local u = (now - rec.hopStart) / dur
				local h, spin = 0, 0
				if u >= 0 and u < 1 then
					h = (if rec.hopBig then 1.7 else 0.55) * 4 * u * (1 - u)
					stretch = 1 + (if rec.hopBig then 0.28 else 0.12) * math.abs(1 - 2 * u)
					spin = if rec.hopBig then u * math.pi * 2 else 0
					rec.inAir = true
				elseif rec.inAir then
					rec.inAir = false
					view:kick(if rec.hopBig then -6 else -2.5) -- landing squash
					if rec.hopBig then
						Juice.burst(rec.stage.Position, DUST, 4, "dust")
					end
				elseif now > rec.nextHop - 0.15 then
					stretch = 1 - 0.18 * (1 - (rec.nextHop - now) / 0.15) -- crouch before the next hop
				end
				local look = math.sin(now * 0.9 + rec.lookSeed) * 0.45
				view.scale += (1 - view.scale) * Juice.smoothing(12, dt)
				root = rec.stage * CFrame.new(0, h, 0) * CFrame.Angles(0, look + spin, 0)
			end
			rec.lastPos = root.Position
			view:step(dt, root, stretch, parts, cframes)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Stand.init()
	for _, model in workspace:WaitForChild("Plots"):GetChildren() do
		local index = model:GetAttribute("Index")
		local stand = model:WaitForChild("FoodStand")
		local slots = {}
		for _, child in stand:GetChildren() do
			local n = child:GetAttribute("Slot")
			if n then
				local top = child:WaitForChild("Top")
				local stage = top:WaitForChild("Stage") :: Attachment
				local rampEnd = top:FindFirstChild("RampEnd") :: Attachment?
				slots[n] = {
					model = child :: Model,
					stage = stage.WorldCFrame,
					ring = child:FindFirstChild("Ring") :: BasePart?,
					rampEnd = rampEnd and rampEnd.WorldPosition,
				}
			end
		end
		Stand.plots[index] = { model = model :: Model, owner = 0, slots = slots, views = {}, byUid = {} }
	end
	Net.event("FoodPlaced").OnClientEvent:Connect(function(index, entry)
		Stand.add(index, entry, true)
	end)
	Net.event("FoodsCleared").OnClientEvent:Connect(Stand.clear)
	RunService.RenderStepped:Connect(step)
end

return Stand
