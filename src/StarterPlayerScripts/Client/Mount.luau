-- Riding, for the local player: while your "Mounted" attribute holds a pet uid you sit on its
-- back (the character's own sit animation, looped), can still jump, and tap E to hop off. A clean
-- light-red "E - Dismount" hint sits below and right of the screen's center while you ride.
-- The pet itself is drawn under you by Pets.luau; the server sets ride height and speed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Juice = require(script.Parent.Juice)
local UIStyle = require(script.Parent.UIStyle)

local player = Players.LocalPlayer
local SIT_FALLBACK = "rbxassetid://2506281703" -- R15 default sit

local Mount = {}
local track: AnimationTrack? = nil
local hopping = false
local hint: Frame

local function sitAnimation(char: Model): string
	local animate = char:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local anim = sit and sit:FindFirstChildOfClass("Animation")
	return if anim and anim.AnimationId ~= "" then anim.AnimationId else SIT_FALLBACK
end

local function buildHint()
	local gui = UIStyle.new("ScreenGui", { Name = "MountHint", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	hint = UIStyle.new("Frame", { Name = "Hint", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.05,
		BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 130, 0.64, 0),
		Size = UDim2.fromOffset(164, 40), Visible = false, Parent = gui })
	UIStyle.corner(hint, 12)
	UIStyle.stroke(hint, 2.5)
	UIStyle.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 160, 160), Color3.fromRGB(240, 96, 96)), Parent = hint })
	-- key cap
	local key = UIStyle.new("Frame", { Name = "Key", BackgroundColor3 = Color3.fromRGB(240, 240, 248), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -1), Size = UDim2.fromOffset(26, 26), Parent = hint })
	UIStyle.corner(key, 8)
	UIStyle.stroke(key, 2.5)
	UIStyle.label({ Text = "E", TextColor3 = Color3.fromRGB(220, 70, 70), Outline = 0, Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, 1, -8), Parent = key })
	UIStyle.label({ Text = "DISMOUNT", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(44, 11),
		Size = UDim2.new(1, -52, 0, 18), Parent = hint })
end

local function showHint(on: boolean)
	if on and not hint.Visible then
		hint.Visible = true
		Juice.popIn(hint, 0.3)
	elseif not on then
		hint.Visible = false
	end
end

local function update()
	local mounted = (player:GetAttribute("Mounted") or "") ~= ""
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if mounted and animator and char then
		if not track then
			local anim = Instance.new("Animation")
			anim.AnimationId = sitAnimation(char)
			track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.15)
		end
		Juice.sound("pop", 0.9, 0.5)
	elseif track then
		track:Stop(0.15)
		track = nil
	end
	showHint(mounted)
end

local function hopOff()
	if hopping or (player:GetAttribute("Mounted") or "") == "" then
		return
	end
	hopping = true
	task.spawn(function()
		pcall(function()
			Net.func("Dismount"):InvokeServer()
		end)
		task.wait(0.3)
		hopping = false
	end)
	Juice.sound("whoosh", 1.2, 0.35)
end

function Mount.init()
	buildHint()
	player:GetAttributeChangedSignal("Mounted"):Connect(update)
	player.CharacterAdded:Connect(function()
		track = nil
		task.defer(update)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonY then
			hopOff()
		end
	end)
	update()
end

return Mount
