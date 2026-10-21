-- The pet upgrade card: walk up to one of your farm pets and this window slides in on the right
-- (it replaces the default proximity prompts, which still handle the F / E keys):
--   title bar  -> the pet's name
--   info row   -> its icon, weight, rarity chip, power and aura chips
--   feed row   -> FEED, how much it grows, the coin price in red, and a red FEED [F] button
--   ride       -> a green "HOLD E TO RIDE" button that fills while you hold E (or click it)
-- Pets.luau drives it: show / update / hide, hold progress, and the onFeed / onRide callbacks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Juice = require(script.Parent.Juice)
local UIStyle = require(script.Parent.UIStyle)

local player = Players.LocalPlayer
local C = UIStyle.Colors

export type Info = { uid: string, id: string, weight: number, aura: string?, ko: boolean }

local PetCard = {}
PetCard.onFeed = nil :: ((uid: string) -> ())?
PetCard.onRide = nil :: ((uid: string) -> ())?

local gui: ScreenGui
local window: Frame
local icon: ImageLabel
local weightLabel: TextLabel
local rarityChip: Frame
local powerChip: Frame
local auraChip: Frame
local gainLabel: TextLabel
local priceLabel: TextLabel
local feedFace: TextButton
local rideFace: TextButton
local rideFill: Frame
local current: Info? = nil

local function build()
	gui = UIStyle.new("ScreenGui", { Name = "PetCard", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	window = UIStyle.panel({ Name = "Window", Title = "Pet", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30, 0.5, 30),
		Size = UDim2.fromOffset(430, 270), Visible = false, Parent = gui })

	-- info row
	local info = UIStyle.row({ Name = "Info", Position = UDim2.fromOffset(14, 18), Size = UDim2.fromOffset(402, 106), Parent = window })
	icon = UIStyle.new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(90, 90), Parent = info })
	weightLabel = UIStyle.label({ Name = "Weight", Text = "", TextColor3 = C.money, Outline = 3.5, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(106, 10), Size = UDim2.fromOffset(150, 44), Parent = info })
	rarityChip = UIStyle.chip({ Name = "Rarity", Text = "", Color = C.grey, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 12), Size = UDim2.fromOffset(132, 34), Parent = info })
	powerChip = UIStyle.chip({ Name = "Power", Text = "", Color = C.cyan, Outlined = true,
		Position = UDim2.fromOffset(106, 64), Size = UDim2.fromOffset(150, 30), Parent = info })
	auraChip = UIStyle.chip({ Name = "Aura", Text = "", Color = C.gold, Outlined = true,
		Position = UDim2.fromOffset(264, 64), Size = UDim2.fromOffset(128, 30), Parent = info })

	-- feed row
	local feed = UIStyle.row({ Name = "Feed", Position = UDim2.fromOffset(14, 134), Size = UDim2.fromOffset(402, 68), Parent = window })
	UIStyle.label({ Name = "Title", Text = "Feed", TextXAlignment = Enum.TextXAlignment.Left, Outline = 3,
		Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(90, 30), Parent = feed })
	gainLabel = UIStyle.label({ Name = "Gain", Text = "", TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Left, Outline = 2.5,
		Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(100, 22), Parent = feed })
	UIStyle.new("ImageLabel", { Name = "Coin", Image = Config.CoinImage, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 108, 0.5, 0), Size = UDim2.fromOffset(38, 38), Parent = feed })
	priceLabel = UIStyle.label({ Name = "Price", Text = "", TextColor3 = C.price, TextXAlignment = Enum.TextXAlignment.Left, Outline = 3.5,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 148, 0.5, 0), Size = UDim2.fromOffset(92, 44), Parent = feed })
	feedFace = UIStyle.button({ Name = "FeedButton", Text = "FEED [F]", Color = C.red, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 2), Size = UDim2.fromOffset(150, 54), Parent = feed })

	-- ride
	local rideBox
	rideFace, rideBox = UIStyle.button({ Name = "Ride", Text = "HOLD E TO RIDE", Color = C.green,
		Position = UDim2.new(0.5, 0, 0, 240), Size = UDim2.fromOffset(402, 56), Parent = window })
	rideFill = UIStyle.new("Frame", { Name = "Fill", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55,
		BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 2, Parent = rideFace })
	UIStyle.corner(rideFill, 8)

	feedFace.Activated:Connect(function()
		if current and PetCard.onFeed then
			PetCard.onFeed(current.uid)
		end
	end)
	rideFace.Activated:Connect(function()
		if current and PetCard.onRide then
			PetCard.onRide(current.uid)
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if current then
			PetCard.update(current)
		end
	end)
	local _ = rideBox
end

function PetCard.update(info: Info)
	if not (current and current.uid == info.uid) then
		return
	end
	current = info
	local title = window:FindFirstChild("Accent") and window.Accent:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = Config.displayName(info.id)
	end
	icon.Image = Config.Icons[info.id] or ""
	local rarity, rarityName = Config.rarityOf(info.id)
	UIStyle.setChip(rarityChip, rarityName, rarity.color)
	local aura = info.aura and Config.PetAuras[info.aura]
	auraChip.Visible = aura ~= nil
	if aura then
		UIStyle.setChip(auraChip, aura.name, aura.color)
	end
	UIStyle.setChip(powerChip, "Power " .. Format.short(Config.petPower(info.weight, info.aura)), C.cyan)
	local cost = Config.petCost(info.weight)
	priceLabel.Text = Format.short(cost)
	gainLabel.Text = string.format("+%.1f kg", Config.feedGain(info.weight))
	local canFeed = not info.ko and (player:GetAttribute("Coins") or 0) >= cost
	UIStyle.recolor(feedFace, if canFeed then C.red else C.grey)
	if info.ko then
		weightLabel.Text = "Resting..."
		weightLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		UIStyle.recolor(rideFace, C.grey)
		UIStyle.setText(rideFace, "RESTING...")
	else
		weightLabel.Text = Config.kg(info.weight)
		weightLabel.TextColor3 = C.money
		UIStyle.recolor(rideFace, C.green)
		UIStyle.setText(rideFace, "HOLD E TO RIDE")
	end
end

function PetCard.show(info: Info)
	local was = current
	current = info
	PetCard.update(info)
	if not (was and window.Visible) then
		window.Visible = true
		window.Position = UDim2.new(1, 460, 0.5, 30)
		Juice.tween(window, 0.32, { Position = UDim2.new(1, -30, 0.5, 30) }, Enum.EasingStyle.Back)
	end
end

function PetCard.hide(uid: string?)
	if not current or (uid and current.uid ~= uid) then
		return
	end
	current = nil
	PetCard.hold(false)
	Juice.tween(window, 0.2, { Position = UDim2.new(1, 460, 0.5, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.2, function()
		if not current then
			window.Visible = false
		end
	end)
end

function PetCard.showing(): string?
	return current and current.uid
end

-- Hold-to-ride progress on the RIDE button.
function PetCard.hold(on: boolean, duration: number?)
	if on then
		rideFill.Size = UDim2.fromScale(0, 1)
		Juice.tween(rideFill, duration or 0.45, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	else
		Juice.tween(rideFill, 0.12, { Size = UDim2.fromScale(0, 1) })
	end
end

function PetCard.punchFeed()
	Juice.punch(priceLabel, 0.25)
	Juice.punch(weightLabel, 0.3)
end

build()

return PetCard
