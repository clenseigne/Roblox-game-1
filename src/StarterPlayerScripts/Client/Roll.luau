-- Roll pedestal presentation: pull the lever and food critters pop up on the pedestal one by one,
-- each springing out with squash/stretch, then getting slurped back down as the next one appears.
-- Every candidate is a locked black silhouette ("???", only its rarity shown). They start fast
-- and slow down (with an occasional near-miss tease); the winner pops up locked, then unlocks:
-- a white flash, its colors wash in and its name appears. It does a victory jump, the ring
-- lights up in its rarity color, then it hops off and flies into the owner's inventory bar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local FoodView = require(script.Parent.FoodView)
local HUD = require(script.Parent.HUD)
local Juice = require(script.Parent.Juice)

local player = Players.LocalPlayer
local INK = Color3.fromRGB(30, 21, 48)
local DISPLAY_SCALE = 1.25
local APPEAR, VANISH = 0.16, 0.12
local REVEAL_DELAY = 0.32 -- the winner sits locked for a beat before it unlocks

type Machine = {
	index: number,
	model: Model,
	display: Attachment,
	ring: BasePart,
	prompt: ProximityPrompt,
	leverParts: { { part: BasePart, rel: CFrame } },
	leverPivot: CFrame,
	lever: any,
	sign: BasePart?,
	signRest: CFrame?,
	tag: BillboardGui,
	tagText: TextLabel,
	tagSub: TextLabel,
	tagStamp: number?,
	busy: boolean,
	spinning: boolean,
}

local Roll = {}
local machines: { [number]: Machine } = {}
local folder = Instance.new("Folder")
folder.Name = "RollFX"
folder.Parent = workspace

-- ---------------------------------------------------------------- helpers

local function weightedPick(rareOnly: boolean?): string
	local total = 0
	for _, id in Config.FoodOrder do
		local food = Config.Foods[id]
		if not rareOnly or Config.Rarities[food.rarity].order >= 4 then
			total += food.weight ^ 0.35 -- flattened so rares show up often in the reel
		end
	end
	local r = math.random() * total
	for _, id in Config.FoodOrder do
		local food = Config.Foods[id]
		if not rareOnly or Config.Rarities[food.rarity].order >= 4 then
			r -= food.weight ^ 0.35
			if r <= 0 then
				return id
			end
		end
	end
	return Config.FoodOrder[1]
end

-- Candidate list ending in the result; no food repeats within two steps so views can be reused.
local function sequence(result: string, count: number): { string }
	local list = {}
	for i = 1, count - 1 do
		local id
		repeat
			id = if i == count - 1 and math.random() < 0.5 then weightedPick(true) else weightedPick()
		until id ~= list[i - 1] and id ~= list[i - 2] and (i < count - 2 or id ~= result)
		list[i] = id
	end
	list[count] = result
	return list
end

-- Appear times: intervals grow geometrically so the reel starts fast and slows down.
local function schedule(count: number): { number }
	local times, t = {}, 0
	for i = 1, count do
		times[i] = t
		t += 0.1 * 1.16 ^ (i - 1)
	end
	return times
end

local function makeTag(display: Attachment): (BillboardGui, TextLabel, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = display
	gui.Size = UDim2.fromOffset(240, 78)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local function line(name: string, y: number, h: number, thickness: number)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, h)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		local s = Instance.new("UIStroke")
		s.Thickness = thickness
		s.Color = INK
		s.Parent = t
		t.Parent = gui
		return t
	end
	return gui, line("Name", 0, 46, 4), line("Rarity", 46, 30, 3)
end

local function setTag(mach: Machine, id: string, final: boolean, locked: boolean?)
	local rarity, rarityName = Config.rarityOf(id)
	mach.tagStamp = os.clock()
	mach.tag.Enabled = true
	for _, label in { mach.tagText, mach.tagSub } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
	mach.tagText.Text = if locked then "???" else Config.displayName(id)
	mach.tagText.TextColor3 = if final then rarity.color else Color3.new(1, 1, 1)
	mach.tagSub.Text = string.upper(rarityName)
	mach.tagSub.TextColor3 = rarity.color
	mach.tagText.TextTransparency, mach.tagSub.TextTransparency = 0, 0
	Juice.punch(mach.tagText, if final then 0.6 else 0.3)
end

local function hideTag(mach: Machine)
	local stamp = os.clock()
	mach.tagStamp = stamp
	for _, label in { mach.tagText, mach.tagSub } do
		Juice.tween(label, 0.3, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Juice.tween(stroke, 0.3, { Transparency = 1 })
		end
	end
	task.delay(0.32, function()
		if mach.tagStamp == stamp then -- no newer roll has shown the tag since
			mach.tag.Enabled = false
		end
	end)
end

local function pullLever(mach: Machine)
	mach.lever.target = -1.1 -- yank toward the player
	task.delay(0.15, function()
		mach.lever.target = 0
	end)
	Juice.sound("lever", 1.1, 0.5)
end

-- ---------------------------------------------------------------- the reveal

local function spin(mach: Machine, result: string, mine: boolean)
	mach.spinning = true
	if mine then
		mach.prompt.Enabled = false
	end
	local count = 13
	local ids = sequence(result, count)
	local times = schedule(count)
	local finalAt = times[count]
	local views: { [string]: any } = {}
	for _, id in ids do
		if not views[id] then
			local v = FoodView.new(id, folder)
			v.scale = 0.001
			v:silhouette()
			views[id] = v
		end
	end
	local base = mach.display.WorldCFrame
	local front = base.LookVector
	local rarity = (Config.rarityOf(result))
	local big = rarity.order >= 3
	local ringRest = mach.ring.Color

	local t0 = os.clock()
	local shown = 0
	local stage = "cycle" -- cycle -> victory -> hop -> done
	local revealAt = finalAt + REVEAL_DELAY
	local victoryAt = revealAt + 0.1
	local revealed, jumped, landed = false, false, false
	local hopStart = 0
	local hopFrom = base.Position
	local hopTo = Vector3.new(base.X, base.Y - 4.44, base.Z) + front * 6
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local parts, cframes = {}, {}

		-- next candidate pops up
		while shown < count and t >= times[shown + 1] do
			shown += 1
			local id = ids[shown]
			local final = shown == count
			views[id]:kick(if final then 9 else 6) -- springs out stretched
			setTag(mach, id, false, true)
			local c = (Config.rarityOf(id)).color
			mach.ring.Color = c
			Juice.sound("tick", if final then 0.75 else 0.9 + shown * 0.05, 0.4)
			Juice.burst(base.Position + Vector3.new(0, 0.4, 0), c, 4)
		end

		-- the winner unlocks
		if not revealed and t >= revealAt then
			revealed = true
			local winnerView = views[result]
			winnerView:reveal(0.45)
			winnerView:kick(10)
			setTag(mach, result, true)
			mach.ring.Color = rarity.color
			local at = base.Position + Vector3.new(0, 1.4, 0)
			Juice.burst(at, Color3.new(1, 1, 1), 18)
			Juice.burst(at, rarity.color, if big then 22 else 14)
			Juice.sound("pop", 0.9, 0.7)
		end

		-- pose every candidate view
		for i = math.max(1, shown - 2), shown do
			local id = ids[i]
			local view = views[id]
			if not view or (i < shown and ids[i] == ids[shown]) then
				continue
			end
			local appearT = t - times[i]
			local nextT = if i < count then times[i + 1] else math.huge
			local y, scale, yaw, stretch = 0, 1, 0, 1
			local u = math.clamp(appearT / APPEAR, 0, 1)
			scale = Juice.easeOutBack(u)
			y = -1.2 * (1 - u)
			yaw = math.sin(appearT * 9) * 0.35 * (1 - math.clamp(appearT / 0.6, 0, 1))
			stretch = 1 + 0.25 * (1 - u)
			if t >= nextT then -- slurped back into the pedestal
				local v = math.clamp((t - nextT) / VANISH, 0, 1)
				scale *= 1 - Juice.easeInQuad(v)
				y -= 1.6 * v
				stretch = 1 + 0.5 * v
			end
			if i == count and stage ~= "cycle" then
				continue -- the winner is posed by the victory code below
			end
			view.scale = math.max(scale * DISPLAY_SCALE, 0.001)
			view:step(dt, base * CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0), stretch, parts, cframes)
		end

		local winner = views[result]
		if stage == "cycle" and shown == count and t >= victoryAt then
			stage = "victory"
		end
		if stage == "victory" then
			local vt = t - victoryAt
			local h, stretch, yaw = 0, 1, 0
			if vt > 0.3 and vt < 0.85 then -- big twirl jump
				local u = (vt - 0.3) / 0.55
				h = 2.6 * 4 * u * (1 - u)
				stretch = 1 + 0.3 * math.abs(1 - 2 * u)
				yaw = u * math.pi * 2
				if not jumped then
					jumped = true
					winner:kick(8)
				end
			elseif vt >= 0.85 and not landed then
				landed = true
				winner:kick(-9)
				Juice.burst(base.Position + Vector3.new(0, 3, 0), rarity.color, if big then 45 else 20, "confetti")
				Juice.sound(if big then "rare" else "land", 1, 0.6)
				Juice.tween(mach.ring, 0.15, { Size = mach.ring.Size + Vector3.new(0, 0.8, 0.8) }, Enum.EasingStyle.Back)
				task.delay(0.2, function()
					Juice.tween(mach.ring, 0.4, { Size = Vector3.new(0.12, 6.6, 6.6) })
				end)
				if mine and big then
					local _, rarityName = Config.rarityOf(result)
					HUD.banner(string.upper(rarityName) .. "!", Config.displayName(result), rarity.color)
					Juice.shake(if rarity.order >= 5 then 1.2 else 0.6, 0.45)
				end
			elseif vt < 0.3 then
				stretch = 1 - 0.25 * (vt / 0.3) -- crouch
			end
			winner.scale = DISPLAY_SCALE
			winner:step(dt, base * CFrame.new(0, h, 0) * CFrame.Angles(0, yaw, 0), stretch, parts, cframes)
			if vt > 1.5 then
				stage, hopStart = "hop", t
				hideTag(mach)
			end
		elseif stage == "hop" then
			local u = math.clamp((t - hopStart) / 0.5, 0, 1)
			local pos = hopFrom:Lerp(hopTo, u) + Vector3.new(0, math.sin(u * math.pi) * 3.5, 0)
			winner.scale = DISPLAY_SCALE + (1 - DISPLAY_SCALE) * u
			winner:step(dt, CFrame.new(pos) * base.Rotation * CFrame.Angles(0, u * math.pi * 2, 0), 1.25, parts, cframes)
			if u >= 1 then
				stage = "done"
				winner:kick(-8)
				Juice.burst(hopTo, Color3.fromRGB(235, 220, 170), 6, "dust")
				task.delay(0.35, function()
					local pos2 = hopTo + Vector3.new(0, 1.2, 0)
					for _, v in views do
						v:destroy()
					end
					Juice.burst(pos2, rarity.color, 10)
					if mine then
						local screen = workspace.CurrentCamera:WorldToViewportPoint(pos2)
						Juice.sound("whoosh", 1.1, 0.4)
						HUD.fly(Config.Icons[result] or Config.CoinImage, Vector2.new(screen.X, screen.Y), HUD.slotFor(result), 80, 0.55, function()
							HUD.reveal(result)
							Juice.sound("pop", 1.25, 0.5)
						end)
					end
					mach.ring.Color = ringRest
					mach.spinning = false
					if mine then
						mach.prompt.Enabled = true
					end
				end)
			end
		end

		-- drumroll wobble on the sign while cycling
		if mach.sign and mach.signRest then
			local k = if stage == "cycle" then 1 else 0
			mach.sign.CFrame = mach.signRest * CFrame.new(0, 0.2 * math.abs(math.sin(t * 20)) * k, 0)
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if stage == "done" then
			conn:Disconnect()
		end
	end)
end

-- ---------------------------------------------------------------- input + wiring

local function request(mach: Machine)
	if mach.busy or mach.spinning then
		return
	end
	mach.busy = true
	pullLever(mach) -- instant feedback; the server answers while the lever swings
	local ok, res = pcall(function()
		return Net.func("Roll"):InvokeServer()
	end)
	mach.busy = false
	if ok and res and not res.ok and res.reason ~= "cooldown" then
		HUD.toast(res.reason)
		mach.lever.v += 8 -- rattle
	end
end

function Roll.setOwner(index: number, userId: number)
	local mach = machines[index]
	if mach then
		mach.prompt.Enabled = userId == player.UserId and not mach.spinning
	end
end

function Roll.init()
	for _, plotModel in workspace:WaitForChild("Plots"):GetChildren() do
		local index = plotModel:GetAttribute("Index")
		local m = plotModel:WaitForChild("RollMachine") :: Model
		local column = m:WaitForChild("Column") :: BasePart
		local display = column:WaitForChild("Display") :: Attachment
		local leverModel = m:WaitForChild("Lever") :: Model
		local pivot = leverModel:WaitForChild("Pivot") :: BasePart
		local leverParts = {}
		for _, p in leverModel:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(leverParts, { part = p, rel = pivot.CFrame:ToObjectSpace(p.CFrame) })
			end
		end
		local sign = m:FindFirstChild("Sign") :: BasePart?
		local tag, tagText, tagSub = makeTag(display)
		local mach: Machine = {
			index = index,
			model = m,
			display = display,
			ring = m:WaitForChild("Ring") :: BasePart,
			prompt = m:WaitForChild("LeverBase"):WaitForChild("RollPrompt") :: ProximityPrompt,
			leverParts = leverParts,
			leverPivot = pivot.CFrame,
			lever = Juice.spring(0, 260, 9),
			sign = sign,
			signRest = sign and sign.CFrame,
			tag = tag,
			tagText = tagText,
			tagSub = tagSub,
			busy = false,
			spinning = false,
		}
		mach.prompt.Enabled = false
		mach.prompt.Triggered:Connect(function(who)
			if who == player then
				request(mach)
			end
		end)
		machines[index] = mach
	end
	Net.event("RollStarted").OnClientEvent:Connect(function(index, id, userId)
		local mach = machines[index]
		if not mach then
			return
		end
		local mine = userId == player.UserId
		if mine then
			HUD.hide(id)
		else
			pullLever(mach)
		end
		spin(mach, id, mine)
	end)
	RunService.RenderStepped:Connect(function(dt)
		for _, mach in machines do
			local spring = mach.lever
			if math.abs(spring.x) < 0.001 and math.abs(spring.v) < 0.001 and spring.target == 0 then
				continue
			end
			local angle = spring:step(dt)
			local parts, cframes = {}, {}
			local hinge = mach.leverPivot * CFrame.Angles(angle, 0, 0)
			for _, lp in mach.leverParts do
				table.insert(parts, lp.part)
				table.insert(cframes, hinge * lp.rel)
			end
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Roll
