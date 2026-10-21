-- Select a food in the bar: your empty pedestals pulse, a see-through ghost of the food bobs on
-- whichever pedestal you hover, and clicking (or tapping) places it there.
-- Select a pet: its ghost follows your mouse around your farm, and clicking lets it out there.
-- Select an aura: the farm pet nearest your mouse lights up in the aura's color; click to give it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodWander = require(ReplicatedStorage.Shared.FoodWander)
local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Assets)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)
local Pets = require(script.Parent.Pets)
local Puppet = require(script.Parent.Puppet)
local Stand = require(script.Parent.Stand)

local player = Players.LocalPlayer

local Placement = {}
local selectedId: string? = nil
local ghost: Model? = nil
local ghostPuppet: any = nil
local hovered: number? = nil
local placing = false
local petMode = false
local auraMode = false
local auraTarget: any = nil -- the pet the aura would go to
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 0.55
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = workspace
local ringRest: { [BasePart]: { size: Vector3, transparency: number } } = {}

local function myIndex(): number
	return player:GetAttribute("Plot") or 0
end

local function farmFloor(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. myIndex())
	return plot and plot:FindFirstChild("FarmFloor") :: BasePart?
end

-- Where a screen ray lands on your farm: (world point, farm-local x, z), kept inside the fence
-- (with the selected pet's margin, so big pets aren't dropped half through it).
local function farmSpot(ray: Ray): (Vector3?, number, number)
	local floor = farmFloor()
	if not floor then
		return nil, 0, 0
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { floor }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not hit then
		return nil, 0, 0
	end
	local def = selectedId and Config.Pets[selectedId]
	local frame, hx, hz = FoodWander.frame(floor, def and def.margin or Config.Pet.margin)
	local lp = frame:PointToObjectSpace(hit.Position)
	local x, z = math.clamp(lp.X, -hx, hx), math.clamp(lp.Z, -hz, hz)
	return frame * Vector3.new(x, 0, z), x, z
end

-- Which free pedestal (slot number) a screen ray hits, if any.
local function slotUnder(ray: Ray): number?
	local free = Stand.freeSlots(myIndex())
	local list = {}
	for _, slot in free do
		table.insert(list, slot.model)
	end
	if #list == 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	local node = hit and hit.Instance
	while node and node ~= workspace do
		local n = node:GetAttribute("Slot")
		if n then
			return n
		end
		node = node.Parent
	end
	return nil
end

local function restoreRings()
	for ring, rest in ringRest do
		ring.Size = rest.size
		ring.Transparency = rest.transparency
	end
	table.clear(ringRest)
end

local function setSelected(id: string?)
	if ghost then
		ghost:Destroy()
		ghost, ghostPuppet = nil, nil
	end
	restoreRings()
	selectedId, hovered = id, nil
	petMode = id ~= nil and Config.isPet(id)
	auraMode = id ~= nil and Config.isAura(id)
	auraTarget = nil
	highlight.Enabled = false
	if not id or auraMode then
		return
	end
	local g = Assets.critter(id)
	ghostPuppet = Puppet.new(g)
	ghostPuppet:setTransparency(0.45)
	g.Parent = workspace
	ghost = g
end

local function placePet(ray: Ray)
	local at, x, z = farmSpot(ray)
	local uid = selectedId and HUD.firstUid(selectedId)
	if not at then
		return
	elseif not uid then
		HUD.select(nil)
		return
	end
	placing = true
	Juice.sound("place", 0.9, 0.5)
	Juice.burst(at + Vector3.new(0, 0.5, 0), Color3.new(1, 1, 1), 10)
	task.spawn(function()
		local ok = pcall(function()
			return Net.func("PlacePet"):InvokeServer(uid, x, z)
		end)
		placing = false
		if not ok then
			HUD.toast("Couldn't let it out, try again!")
		end
	end)
end

-- The farm pet nearest the mouse on screen (within reach), if any.
local function petUnderMouse(): any
	local cam = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local best, bestDist = nil, 110
	for _, pet in Pets.mine() do
		local center = pet.pos + Vector3.new(0, Pets.heightOf(pet) * pet.scale.x * 0.5, 0)
		local sp, onScreen = cam:WorldToViewportPoint(center)
		if onScreen then
			local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
			if d < bestDist then
				best, bestDist = pet, d
			end
		end
	end
	return best
end

local function giveAura()
	local pet = auraTarget
	local uid = selectedId and HUD.firstUid(selectedId)
	if not (pet and uid) then
		return
	end
	placing = true
	task.spawn(function()
		local ok, res = pcall(function()
			return Net.func("ApplyAura"):InvokeServer(uid, pet.uid)
		end)
		placing = false
		if not (ok and res and res.ok) then
			HUD.toast("Couldn't use that aura, try again!")
		end
	end)
end

local function place(ray: Ray)
	if not selectedId or placing then
		return
	end
	if auraMode then
		giveAura()
		return
	end
	if petMode then
		placePet(ray)
		return
	end
	local slot = slotUnder(ray)
	if not slot then
		return
	end
	local uid = HUD.firstUid(selectedId)
	if not uid then
		HUD.select(nil)
		return
	end
	placing = true
	Juice.sound("place", 1, 0.5)
	local info = Stand.freeSlots(myIndex())[slot]
	if info then
		Juice.burst(info.stage.Position + Vector3.new(0, 0.3, 0), Color3.new(1, 1, 1), 8)
	end
	task.spawn(function()
		local ok = pcall(function()
			return Net.func("Place"):InvokeServer(uid, slot)
		end)
		placing = false
		if not ok then
			HUD.toast("Couldn't place that, try again!")
		end
	end)
end

function Placement.init()
	HUD.onSelect = setSelected
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape
			or input.KeyCode == Enum.KeyCode.Q then
			if selectedId then
				HUD.select(nil)
			end
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			place(workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y))
		end
	end)
	RunService.RenderStepped:Connect(function()
		if auraMode and selectedId then
			auraTarget = petUnderMouse()
			local def = Config.PetAuras[selectedId]
			highlight.Enabled = auraTarget ~= nil
			if auraTarget then
				highlight.Adornee = auraTarget.model
				highlight.FillColor = def.color
			end
			return
		end
		if not (selectedId and ghost and ghostPuppet) then
			return
		end
		local t = os.clock()
		if petMode then
			-- the pet's ghost waddles after your mouse across the farm
			local mouse = UserInputService:GetMouseLocation()
			local at = farmSpot(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
			local parts, cframes = {}, {}
			if at then
				local root = CFrame.new(at + Vector3.new(0, 0.3 + 0.3 * math.abs(math.sin(t * 5)), 0))
					* CFrame.Angles(0, math.sin(t * 2) * 0.5, 0)
				ghostPuppet:pose(root, Vector3.one, 1, math.sin(t * 10) * 0.5, parts, cframes)
			else
				ghostPuppet:pose(CFrame.new(0, -500, 0), Vector3.one * 0.01, 1, 0, parts, cframes)
			end
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			return
		end
		local free = Stand.freeSlots(myIndex())
		-- rings of pedestals that just got filled go back to normal
		for ring, rest in ringRest do
			local stillFree = false
			for _, slot in free do
				if slot.ring == ring then
					stillFree = true
				end
			end
			if not stillFree then
				ring.Size, ring.Transparency = rest.size, rest.transparency
				ringRest[ring] = nil
			end
		end
		-- pulse every empty pedestal's ring so you can see where food can go
		for n, slot in free do
			local ring = slot.ring
			if ring then
				if not ringRest[ring] then
					ringRest[ring] = { size = ring.Size, transparency = ring.Transparency }
				end
				local rest = ringRest[ring]
				local k = if n == hovered then 1.25 else 1 + 0.08 * math.sin(t * 6 + n)
				ring.Size = Vector3.new(rest.size.X, rest.size.Y * k, rest.size.Z * k)
				ring.Transparency = if n == hovered then 0 else 0.25 + 0.2 * math.sin(t * 6 + n)
			end
		end
		local mouse = UserInputService:GetMouseLocation()
		hovered = slotUnder(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
		local parts, cframes = {}, {}
		if hovered and free[hovered] then
			local stage = free[hovered].stage
			local root = stage * CFrame.new(0, 0.4 + 0.25 * math.sin(t * 5), 0) * CFrame.Angles(0, math.sin(t * 2) * 0.4, 0)
			ghostPuppet:pose(root, Vector3.one, 1, 0, parts, cframes)
		else
			ghostPuppet:pose(CFrame.new(0, -500, 0), Vector3.one * 0.01, 1, 0, parts, cframes)
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return Placement
