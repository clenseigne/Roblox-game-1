-- The game's UI look, in the style of the big Roblox simulators: chunky Fredoka type in white with
-- thick black outlines; windows with a bright studded (LEGO plate) title bar sitting on a dark,
-- see-through brown body with a rainbow rim; dark inset row cards; studded chips; and glossy
-- studded buttons on a darker lip that press down into it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Juice = require(script.Parent.Juice)

local UIStyle = {}

UIStyle.STUDS = "rbxassetid://126362877972374" -- crisp stud tile (art/ui/stud_tile2.png, tools/make_stud_tile2.py)
UIStyle.FONT = Enum.Font.FredokaOne
UIStyle.FONT_BODY = Enum.Font.FredokaOne
UIStyle.Colors = {
	panel = Color3.fromRGB(62, 44, 32), -- window body (see-through)
	panelTop = Color3.fromRGB(84, 60, 42),
	row = Color3.fromRGB(26, 18, 12), -- inset row cards
	edge = Color3.fromRGB(12, 8, 6),
	text = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(236, 222, 200),
	header = Color3.fromRGB(96, 214, 62), -- studded title bars
	green = Color3.fromRGB(86, 206, 62),
	money = Color3.fromRGB(110, 236, 70), -- big currency numbers
	red = Color3.fromRGB(228, 42, 42),
	price = Color3.fromRGB(255, 58, 58),
	gold = Color3.fromRGB(255, 212, 46),
	grey = Color3.fromRGB(128, 128, 128),
	cyan = Color3.fromRGB(64, 214, 255),
	track = Color3.fromRGB(30, 22, 16),
}
local C = UIStyle.Colors

UIStyle.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 64, 64)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 236, 60)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 80)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 150, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 80, 255)),
})

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end
UIStyle.new = new

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
UIStyle.darker, UIStyle.lighter = darker, lighter

function UIStyle.corner(parent: Instance, r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

function UIStyle.stroke(parent: Instance, thickness: number, color: Color3?)
	return new("UIStroke", { Thickness = thickness, Color = color or C.edge, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

-- A rainbow rim around a frame (a UIStroke with a rainbow gradient on it).
function UIStyle.rainbow(parent: GuiObject, thickness: number?): UIStroke
	local s = UIStyle.stroke(parent, thickness or 5, Color3.new(1, 1, 1))
	new("UIGradient", { Color = UIStyle.RAINBOW, Rotation = 0, Parent = s })
	return s
end

-- The stud pattern over a frame (it tints to whatever color is under it).
function UIStyle.studs(parent: GuiObject, tile: number?, transparency: number?, radius: number?)
	local s = new("ImageLabel", {
		Name = "Studs",
		Image = UIStyle.STUDS,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile or 30, tile or 30),
		ImageTransparency = transparency or 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	UIStyle.corner(s, radius or 6)
	return s
end

-- White chunky text with a thick black outline.
function UIStyle.label(props: { [string]: any }): TextLabel
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIStyle.FONT,
		TextColor3 = C.text,
		TextScaled = true,
	})
	for k, v in props do
		if k ~= "Outline" then
			(t :: any)[k] = v
		end
	end
	new("UIStroke", { Thickness = props.Outline or 2.5, Color = C.edge, LineJoinMode = Enum.LineJoinMode.Round, Parent = t })
	return t
end

-- A studded title bar: bright plate color, studs, black rim, big outlined title on the left.
local function header(color: Color3, title: string, height: number, z: number): Frame
	local h = new("Frame", {
		Name = "Accent",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, 24, 0, height),
		ZIndex = z + 2,
	})
	UIStyle.corner(h, 6)
	UIStyle.stroke(h, 4)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(lighter(color, 0.12), darker(color, 0.08)), Parent = h })
	UIStyle.studs(h, math.floor(height * 0.5), 0, 6).ZIndex = z + 2
	UIStyle.label({ Name = "Title", Text = title, TextXAlignment = Enum.TextXAlignment.Left, Outline = 4,
		Position = UDim2.new(0, 20, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(1, -40, 0.62, 0),
		ZIndex = z + 3, Parent = h })
	return h
end

-- A window: dark see-through brown body with a rainbow rim. With `Title`, a studded title bar
-- (props.Accent = its color, default green) sits on top, outside the body, so the body's own
-- layout is unchanged; without one, a slim studded strip in the Accent color runs across the top.
-- The bar is the child named "Accent" (recolor it freely).
function UIStyle.panel(props: { [string]: any }): Frame
	local p = new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	})
	for k, v in props do
		if k ~= "Accent" and k ~= "Parent" and k ~= "Title" and k ~= "HeaderHeight" then
			(p :: any)[k] = v
		end
	end
	local z = props.ZIndex or 1
	UIStyle.corner(p, 6)
	UIStyle.rainbow(p, 5)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.panelTop, C.panel), Parent = p })
	if props.Title then
		header(props.Accent or C.header, props.Title, props.HeaderHeight or 66, z).Parent = p
	else
		local strip = new("Frame", {
			Name = "Accent",
			BackgroundColor3 = props.Accent or C.header,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 12),
			ZIndex = z + 1,
			Parent = p,
		})
		UIStyle.corner(strip, 6)
		UIStyle.studs(strip, 12, 0, 6).ZIndex = z + 1
	end
	p.Parent = props.Parent
	return p
end

-- A dark inset card for a row inside a window.
function UIStyle.row(props: { [string]: any }): Frame
	local r = new("Frame", { BackgroundColor3 = C.row, BackgroundTransparency = 0.35, BorderSizePixel = 0 })
	for k, v in props do
		if k ~= "Parent" then
			(r :: any)[k] = v
		end
	end
	UIStyle.corner(r, 6)
	UIStyle.stroke(r, 3)
	r.Parent = props.Parent
	return r
end

-- A studded chip with outlined text (rarity tags, "x7 Stock", WILD...). Outlined = dark fill with
-- a colored rim (like the stock pills) instead of a solid fill.
function UIStyle.chip(props: { Text: string, Color: Color3, Size: UDim2, Position: UDim2, AnchorPoint: Vector2?,
	Outlined: boolean?, ZIndex: number?, Name: string?, Parent: Instance }): Frame
	local z = props.ZIndex or 1
	local c = new("Frame", {
		Name = props.Name or "Chip",
		BackgroundColor3 = if props.Outlined then C.row else props.Color,
		BackgroundTransparency = if props.Outlined then 0.15 else 0,
		BorderSizePixel = 0,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position,
		Size = props.Size,
		ZIndex = z,
		Parent = props.Parent,
	})
	UIStyle.corner(c, 6)
	UIStyle.stroke(c, 3, if props.Outlined then props.Color else C.edge)
	if not props.Outlined then
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(lighter(props.Color, 0.1), darker(props.Color, 0.1)), Parent = c })
		UIStyle.studs(c, 18, 0, 6).ZIndex = z
	end
	UIStyle.label({ Name = "Text", Text = props.Text, TextColor3 = if props.Outlined then props.Color:Lerp(Color3.new(1, 1, 1), 0.35) else C.text,
		Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, -14, 0.72, 0),
		ZIndex = z + 1, Outline = 2.5, Parent = c })
	return c
end

-- Sets a chip's color and text.
function UIStyle.setChip(chip: Frame, text: string, color: Color3)
	local outlined = chip.BackgroundColor3 == C.row
	local label = chip:FindFirstChild("Text") :: TextLabel
	label.Text = text
	if outlined then
		local s = chip:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = color
		end
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	else
		chip.BackgroundColor3 = color
		local g = chip:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(lighter(color, 0.1), darker(color, 0.1))
		end
	end
end

-- A chunky glossy studded button on a darker lip; presses down into the lip. Returns the
-- clickable face (connect .Activated) and the container (position / size / animate that).
function UIStyle.button(props: { Name: string, Text: string, Color: Color3, Size: UDim2, Position: UDim2,
	AnchorPoint: Vector2?, Parent: Instance }): (TextButton, Frame)
	local lip = 6
	local box = new("Frame", {
		Name = props.Name,
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Parent = props.Parent,
	})
	local base = new("Frame", {
		Name = "Lip",
		BackgroundColor3 = darker(props.Color, 0.45),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lip),
		Size = UDim2.new(1, 0, 1, -lip),
		Parent = box,
	})
	UIStyle.corner(base, 8)
	UIStyle.stroke(base, 3)
	local face = new("TextButton", {
		Name = "Face",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -lip),
		ZIndex = 2,
		Parent = box,
	})
	UIStyle.corner(face, 8)
	UIStyle.stroke(face, 3)
	local grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(lighter(props.Color, 0.2), props.Color), Parent = face })
	UIStyle.studs(face, 22, 0.35, 8).ZIndex = 2
	local shine = new("Frame", { -- glossy top highlight
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, 0.34, 0),
		ZIndex = 2,
		Parent = face,
	})
	UIStyle.corner(shine, 6)
	UIStyle.label({ Name = "Label", Text = props.Text, Size = UDim2.new(1, -20, 0.62, 0), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Outline = 3, Parent = face })
	local scale = Juice.scaleOf(box)
	local function press(down: boolean)
		face.Position = UDim2.fromOffset(0, if down then lip - 1 else 0)
	end
	face:SetAttribute("Color", props.Color)
	face.MouseEnter:Connect(function()
		local c = face:GetAttribute("Color") or props.Color
		Juice.tween(scale, 0.12, { Scale = 1.04 }, Enum.EasingStyle.Back)
		grad.Color = ColorSequence.new(lighter(c, 0.32), lighter(c, 0.08))
	end)
	face.MouseLeave:Connect(function()
		local c = face:GetAttribute("Color") or props.Color
		Juice.tween(scale, 0.12, { Scale = 1 })
		grad.Color = ColorSequence.new(lighter(c, 0.2), c)
		press(false)
	end)
	face.MouseButton1Down:Connect(function()
		press(true)
		Juice.sound("tick", 1.3, 0.35)
	end)
	face.MouseButton1Up:Connect(function()
		press(false)
	end)
	return face, box
end

-- Sets a button's face color (e.g. greyed out when you can't afford it).
function UIStyle.recolor(face: TextButton, color: Color3)
	face:SetAttribute("Color", color)
	local grad = face:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(lighter(color, 0.2), color)
	end
	local lip = face.Parent and face.Parent:FindFirstChild("Lip") :: Frame?
	if lip then
		lip.BackgroundColor3 = darker(color, 0.45)
	end
end

-- Sets a button's text.
function UIStyle.setText(face: TextButton, text: string)
	local l = face:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

UIStyle.coinImage = Config.CoinImage

return UIStyle
