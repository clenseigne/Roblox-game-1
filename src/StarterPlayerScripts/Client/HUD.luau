-- Screen UI in a clean line-art style (white fills, bold ink outlines): coin counter,
-- inventory bar (foods and pets), held lucky block panel (Open / Toss), rarity banners, toasts and icons that fly
-- into the bar / counter.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Juice = require(script.Parent.Juice)
local UIStyle = require(script.Parent.UIStyle)

local player = Players.LocalPlayer
local INK = Color3.fromRGB(12, 8, 6)
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne

local HUD = {}
HUD.onSelect = nil :: ((string?) -> ())?
HUD.onLuckyOpen = nil :: (() -> ())?
HUD.onLuckyToss = nil :: (() -> ())?

local gui: ScreenGui
local coinPill: Frame
local coinIcon: ImageLabel
local coinText: TextLabel
local bar: Frame
local hint: TextLabel
local toastLabel: TextLabel
local bannerFrame: Frame
local luckyPanel: Frame
local luckyCube: Frame
local luckyName: TextLabel
local luckyCost: TextLabel
local luckyTier = 0

local inventory = {} :: { { uid: string, id: string } }
local hidden: { [string]: number } = {} -- foodId -> newest N items held back until their fly-in lands
local slots: { [string]: TextButton } = {}
local selected: string? = nil
local focused = false -- a battle is on screen: the bar, hint and lucky panel step aside
local coinTarget, coinShown, lastPunch = 0, 0, 0

-- ---------------------------------------------------------------- builders

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(thickness: number, color: Color3?)
	return new("UIStroke", { Thickness = thickness, Color = color or INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(props: { [string]: any }): TextLabel
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = props.TextColor3 or INK,
		TextScaled = true,
	})
	for k, v in props do
		if k ~= "Outline" then
			(t :: any)[k] = v
		end
	end
	if props.Outline then
		new("UIStroke", { Thickness = props.Outline, Color = INK, Parent = t })
	end
	return t
end

-- ---------------------------------------------------------------- coins

function HUD.predict(amount: number)
	coinTarget += amount
end

function HUD.coinTarget(): GuiObject
	return coinIcon
end

-- ---------------------------------------------------------------- toast / banner

function HUD.toast(message: string)
	toastLabel.Text = message
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	Juice.popIn(toastLabel, 0.3)
	local stamp = os.clock()
	HUD._toastStamp = stamp
	task.delay(1.8, function()
		if HUD._toastStamp == stamp then
			Juice.tween(toastLabel, 0.25, { TextTransparency = 1 })
			task.wait(0.25)
			if HUD._toastStamp == stamp then
				toastLabel.Visible = false
			end
		end
	end)
end

function HUD.banner(title: string, subtitle: string, color: Color3)
	local titleLabel = bannerFrame:FindFirstChild("Title") :: TextLabel
	local subLabel = bannerFrame:FindFirstChild("Sub") :: TextLabel
	titleLabel.Text = title
	titleLabel.TextColor3 = color
	subLabel.Text = subtitle
	bannerFrame.Visible = true
	bannerFrame.Rotation = -8
	titleLabel.TextTransparency, subLabel.TextTransparency = 0, 0
	Juice.popIn(bannerFrame, 0.45)
	Juice.tween(bannerFrame, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	local stamp = os.clock()
	HUD._bannerStamp = stamp
	task.delay(1.7, function()
		if HUD._bannerStamp ~= stamp then
			return
		end
		Juice.tween(titleLabel, 0.3, { TextTransparency = 1 })
		Juice.tween(subLabel, 0.3, { TextTransparency = 1 })
		task.wait(0.3)
		if HUD._bannerStamp == stamp then
			bannerFrame.Visible = false
		end
	end)
end

-- ---------------------------------------------------------------- fly-in icons

-- Flies an image from a screen point into a gui object along an arc, then calls onArrive.
function HUD.fly(image: string, from: Vector2, to: GuiObject, size: number, duration: number, onArrive: (() -> ())?)
	local icon = new("ImageLabel", {
		Image = image,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromOffset(from.X, from.Y),
		ZIndex = 20,
		Parent = gui,
	})
	local start = os.clock()
	local lift = math.random(60, 120)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / duration, 0, 1)
		local target = to.AbsolutePosition + to.AbsoluteSize / 2
		local mid = (from + target) / 2 - Vector2.new(0, lift)
		local e = Juice.easeInQuad(a)
		local p = from:Lerp(mid, e):Lerp(mid:Lerp(target, e), e) -- quadratic bezier
		icon.Position = UDim2.fromOffset(p.X, p.Y)
		local s = size * (1 + 0.3 * math.sin(a * math.pi)) * (1 - 0.35 * a)
		icon.Size = UDim2.fromOffset(s, s)
		icon.Rotation = math.sin(a * math.pi * 2) * 12
		if a >= 1 then
			conn:Disconnect()
			icon:Destroy()
			if onArrive then
				onArrive()
			end
		end
	end)
end

-- ---------------------------------------------------------------- inventory

local function counts(): ({ [string]: number }, { string })
	local c, order = {}, {}
	for _, item in inventory do
		c[item.id] = (c[item.id] or 0) + 1
	end
	for id, n in c do
		c[id] = n - (hidden[id] or 0)
		if c[id] <= 0 then
			c[id] = nil
		else
			table.insert(order, id)
		end
	end
	table.sort(order, function(a, b)
		return (Config.rarityOf(a)).order > (Config.rarityOf(b)).order
	end)
	return c, order
end

local function styleSelected(id: string, slot: TextButton)
	local isSel = id == selected
	local s = slot:FindFirstChildOfClass("UIStroke") :: UIStroke
	s.Color = if isSel then Color3.fromRGB(255, 196, 40) else INK
	s.Thickness = if isSel then 6 else 4
	Juice.tween(slot, 0.2, { Position = UDim2.new(0, 0, 0, if isSel then -10 else 0) }, Enum.EasingStyle.Back)
end

local function makeSlot(id: string): TextButton
	local rarity = (Config.rarityOf(id))
	local holder = new("Frame", { Name = id, BackgroundTransparency = 1, Size = UDim2.fromOffset(82, 82), Parent = bar })
	holder.LayoutOrder = -rarity.order
	local slot = new("TextButton", {
		Name = "Slot",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = UIStyle.Colors.panel,
		BackgroundTransparency = 0.12,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	}, { corner(10), stroke(4) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(UIStyle.Colors.panelTop, UIStyle.Colors.row), Parent = slot })
	new("Frame", {
		Name = "Band",
		BackgroundColor3 = rarity.color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -14, 0, 9),
		Parent = slot,
	}, { corner(5) })
	local icon = Config.Icons[id]
	if icon then
		new("ImageLabel", {
			Name = "Icon",
			Image = icon,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromOffset(62, 62),
			Parent = slot,
		})
	else
		UIStyle.label({ Name = "Icon", Text = Config.displayName(id), Size = UDim2.new(1, -10, 0, 30),
			Position = UDim2.fromOffset(5, 20), Parent = slot })
	end
	-- count: an outlined "x3" over the top-right corner
	local badge = new("Frame", {
		Name = "Badge",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, -10),
		Size = UDim2.fromOffset(44, 30),
		ZIndex = 3,
		Parent = slot,
	})
	UIStyle.label({ Name = "Count", Outline = 3, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = badge })
	slot.MouseEnter:Connect(function()
		Juice.tween(Juice.scaleOf(slot), 0.15, { Scale = 1.07 }, Enum.EasingStyle.Back)
	end)
	slot.MouseLeave:Connect(function()
		Juice.tween(Juice.scaleOf(slot), 0.15, { Scale = 1 })
	end)
	slot.Activated:Connect(function()
		HUD.select(if selected == id then nil else id)
	end)
	Juice.popIn(slot)
	return slot
end

local function hintFor(id: string?): string
	if not id then
		return "Pull the lever to roll some food!"
	elseif Config.isPet(id) then
		return "Click your farm to let it roam  -  right-click to cancel"
	elseif Config.isAura(id) then
		return "Click one of your farm pets to give it the aura  -  right-click to cancel"
	end
	return "Click a glowing pedestal to place  -  right-click to cancel"
end

local function refresh()
	local c, order = counts()
	for id, slot in slots do
		if not c[id] then
			(slot.Parent :: Instance):Destroy()
			slots[id] = nil
		end
	end
	for _, id in order do
		local slot = slots[id] or makeSlot(id)
		slots[id] = slot
		local label = slot:FindFirstChild("Badge"):FindFirstChild("Count") :: TextLabel
		local newText = "x" .. c[id]
		if label.Text ~= newText and label.Text ~= "" then
			Juice.punch(slot, 0.15)
		end
		label.Text = newText
		styleSelected(id, slot)
	end
	if selected and not c[selected] then
		HUD.select(nil)
	end
	hint.Visible = not focused and (selected ~= nil or #order == 0)
	hint.Text = hintFor(selected)
end

function HUD.select(id: string?)
	selected = id
	for slotId, slot in slots do
		styleSelected(slotId, slot)
	end
	hint.Visible = not focused and (id ~= nil or next(slots) == nil)
	hint.Text = hintFor(id)
	if HUD.onSelect then
		HUD.onSelect(id)
	end
end

function HUD.selected(): string?
	return selected
end

-- Oldest item of a type (held-back items are always the newest, so they're never picked).
function HUD.firstUid(id: string): string?
	local total = 0
	for _, item in inventory do
		if item.id == id then
			total += 1
		end
	end
	if total - (hidden[id] or 0) <= 0 then
		return nil
	end
	for _, item in inventory do
		if item.id == id then
			return item.uid
		end
	end
	return nil
end

-- Keep a freshly rolled item out of the bar until its fly-in lands.
function HUD.hide(id: string)
	hidden[id] = (hidden[id] or 0) + 1
	refresh()
end

function HUD.reveal(id: string)
	hidden[id] = math.max(0, (hidden[id] or 0) - 1)
	refresh()
	local slot = slots[id]
	if slot then
		Juice.punch(slot, 0.25)
	end
end

-- Hides the bar, hint and lucky panel while a battle has the screen (and brings them back).
function HUD.setFocus(on: boolean)
	focused = on
	bar.Visible = not on
	if on then
		hint.Visible = false
		luckyPanel.Visible = false
	else
		refresh()
		HUD.setLucky(luckyTier)
	end
end

-- Screen-space target for an item's fly-in (its slot, or the bar if the slot doesn't exist yet).
function HUD.slotFor(id: string): GuiObject
	local slot = slots[id]
	return slot or bar
end

-- ---------------------------------------------------------------- held lucky block

local openFace: TextButton

local function updateLuckyCost()
	local tier = Config.Lucky.tiers[luckyTier]
	if tier then
		luckyCost.Text = Format.short(tier.cost)
		local short = (player:GetAttribute("Coins") or 0) < tier.cost
		luckyCost.TextColor3 = if short then Color3.fromRGB(255, 150, 150) else WHITE
		UIStyle.recolor(openFace, if short then Color3.fromRGB(96, 92, 120) else UIStyle.Colors.green)
	end
end

-- Shows the panel for the block in your hand (tier index), or hides it (0).
function HUD.setLucky(tierIndex: number)
	local tier = Config.Lucky.tiers[tierIndex]
	luckyTier = if tier then tierIndex else 0
	local s = Juice.scaleOf(luckyPanel)
	if tier and not focused then
		luckyName.Text = string.upper(tier.name) .. " BLOCK"
		luckyName.TextColor3 = tier.color
		luckyCube.BackgroundColor3 = tier.color
		local accent = luckyPanel:FindFirstChild("Accent") :: Frame?
		if accent then
			accent.BackgroundColor3 = tier.color
		end
		updateLuckyCost()
		luckyPanel.Visible = true
		Juice.popIn(luckyPanel, 0.4)
	elseif luckyPanel.Visible then
		Juice.tween(s, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.18, function()
			if luckyTier == 0 or focused then
				luckyPanel.Visible = false
			end
		end)
	end
end

function HUD.shakeLucky()
	if luckyPanel.Visible then
		Juice.shakeGui(luckyPanel)
	end
end

-- Dark studded panel: a studded "?" tile in the tier's color, the block's name, OPEN (with its
-- coin cost) and TOSS.
local function buildLuckyPanel()
	luckyPanel = UIStyle.panel({ Name = "LuckyBlock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -132),
		Size = UDim2.fromOffset(404, 136), Visible = false, Parent = gui })
	luckyCube = UIStyle.new("Frame", { Name = "Cube", BackgroundColor3 = UIStyle.Colors.gold, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(66, 72), Size = UDim2.fromOffset(84, 84), ZIndex = 2,
		Parent = luckyPanel })
	UIStyle.corner(luckyCube, 14)
	UIStyle.stroke(luckyCube, 3)
	UIStyle.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)), Parent = luckyCube })
	UIStyle.studs(luckyCube, 21, 0.55, 14).ZIndex = 2
	UIStyle.label({ Name = "Mark", Text = "?", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 1, -20),
		ZIndex = 3, Outline = 3, Parent = luckyCube })
	luckyName = UIStyle.label({ Name = "Name", Text = "", TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(124, 20), Size = UDim2.fromOffset(262, 26), Parent = luckyPanel })
	UIStyle.label({ Name = "Sub", Text = "Open it to hatch a pet!", Font = UIStyle.FONT_BODY, TextColor3 = UIStyle.Colors.muted,
		TextXAlignment = Enum.TextXAlignment.Left, Outline = 1, Position = UDim2.fromOffset(124, 50), Size = UDim2.fromOffset(262, 16),
		Parent = luckyPanel })
	local openBox
	openFace, openBox = UIStyle.button({ Name = "Open", Text = "OPEN", Color = UIStyle.Colors.green,
		Size = UDim2.fromOffset(170, 52), Position = UDim2.fromOffset(124, 74), AnchorPoint = Vector2.new(0, 0), Parent = luckyPanel })
	local openLabel = openFace:FindFirstChild("Label") :: TextLabel
	openLabel.AnchorPoint = Vector2.new(0, 0.5)
	openLabel.Position = UDim2.new(0, 12, 0.5, 0)
	openLabel.Size = UDim2.new(0, 70, 0.5, 0)
	UIStyle.new("ImageLabel", { Name = "Coin", Image = Config.CoinImage, BackgroundTransparency = 1, ZIndex = 3,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 86, 0.5, 0), Size = UDim2.fromOffset(28, 28), Parent = openFace })
	luckyCost = UIStyle.label({ Name = "Cost", Text = "0", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 116, 0.5, 0), Size = UDim2.new(0, 46, 0.5, 0), Parent = openFace })
	local tossFace = UIStyle.button({ Name = "Toss", Text = "TOSS", Color = UIStyle.Colors.red,
		Size = UDim2.fromOffset(90, 52), Position = UDim2.fromOffset(302, 74), AnchorPoint = Vector2.new(0, 0), Parent = luckyPanel })
	openFace.Activated:Connect(function()
		if HUD.onLuckyOpen then
			HUD.onLuckyOpen()
		end
	end)
	tossFace.Activated:Connect(function()
		if HUD.onLuckyToss then
			HUD.onLuckyToss()
		end
	end)
	-- the "?" tile bobs; OPEN breathes when you can afford it
	RunService.RenderStepped:Connect(function()
		if luckyPanel.Visible then
			local t = os.clock()
			luckyCube.Rotation = math.sin(t * 2.2) * 5
			luckyCube.Position = UDim2.fromOffset(66, 72 + math.sin(t * 3.1) * 3)
			local tier = Config.Lucky.tiers[luckyTier]
			local canOpen = tier and (player:GetAttribute("Coins") or 0) >= tier.cost
			openBox.Rotation = if canOpen then math.sin(t * 6) * 1.5 else 0
		end
	end)
end

-- ---------------------------------------------------------------- build

local function build()
	gui = new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- coin ticker: bottom left, the big outlined green number beside the coin (no backing)
	coinPill = new("Frame", {
		Name = "Coins",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.84, 0),
		Size = UDim2.fromOffset(300, 70),
		Parent = gui,
	})
	coinIcon = new("ImageLabel", {
		Name = "Icon",
		Image = Config.CoinImage,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 34, 0.5, 0),
		Size = UDim2.fromOffset(68, 68),
		ZIndex = 2,
		Parent = coinPill,
	})
	coinText = UIStyle.label({ Name = "Amount", Text = "0", TextColor3 = UIStyle.Colors.money, Outline = 4.5,
		Size = UDim2.new(1, -80, 0, 58), Position = UDim2.fromOffset(76, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = coinPill })

	bar = new("Frame", {
		Name = "Inventory",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0.9, 0, 0, 92),
		Parent = gui,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}),
	})
	hint = text({ Name = "Hint", Text = "Pull the lever to roll some food!", TextColor3 = WHITE, Outline = 3,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -122), Size = UDim2.fromOffset(520, 30), Parent = gui })
	toastLabel = text({ Name = "Toast", Text = "", TextColor3 = WHITE, Outline = 3, Visible = false,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -160), Size = UDim2.fromOffset(520, 34), Parent = gui })

	bannerFrame = new("Frame", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(560, 130),
		Visible = false,
		Parent = gui,
	})
	text({ Name = "Title", Text = "", TextColor3 = WHITE, Outline = 6, Size = UDim2.new(1, 0, 0, 80), Parent = bannerFrame })
	text({ Name = "Sub", Text = "", TextColor3 = WHITE, Outline = 4, Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 84), Parent = bannerFrame })
	buildLuckyPanel()
end

function HUD.init()
	-- the lucky block is the only tool, held in hand and driven by the panel: no hotbar
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	build()
	coinTarget = player:GetAttribute("Coins") or 0
	coinShown = coinTarget
	coinText.Text = Format.short(coinShown)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		coinTarget = player:GetAttribute("Coins") or 0
		updateLuckyCost()
	end)
	RunService.RenderStepped:Connect(function(dt)
		if math.abs(coinTarget - coinShown) < 0.5 then
			coinShown = coinTarget
		else
			local before = math.floor(coinShown)
			coinShown += (coinTarget - coinShown) * Juice.smoothing(9, dt)
			if math.floor(coinShown) ~= before and os.clock() - lastPunch > 0.08 then
				lastPunch = os.clock()
				Juice.punch(coinIcon, 0.22)
			end
		end
		coinText.Text = Format.short(coinShown)
	end)
	Net.event("InventoryChanged").OnClientEvent:Connect(function(list)
		inventory = list
		refresh()
	end)
	Net.event("Toast").OnClientEvent:Connect(HUD.toast)
	refresh()
end

return HUD
