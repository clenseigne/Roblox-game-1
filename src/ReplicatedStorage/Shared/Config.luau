-- Tunables shared by server and client. Economy numbers are first-pass and meant to be tuned.
local Config = {}

Config.Rarities = {
	Common = { order = 1, color = Color3.fromRGB(205, 205, 215) },
	Uncommon = { order = 2, color = Color3.fromRGB(110, 220, 90) },
	Rare = { order = 3, color = Color3.fromRGB(70, 170, 255) },
	Epic = { order = 4, color = Color3.fromRGB(185, 95, 255) },
	Legendary = { order = 5, color = Color3.fromRGB(255, 180, 40) },
	Mythic = { order = 6, color = Color3.fromRGB(255, 70, 140) },
}

-- weight = roll odds (relative), value = coins per drop, interval = seconds between drops
Config.Foods = {
	Apple = { rarity = "Common", weight = 40, value = 1, interval = 3.0 },
	Carrot = { rarity = "Common", weight = 34, value = 1, interval = 2.6 },
	Donut = { rarity = "Uncommon", weight = 15, value = 3, interval = 3.0 },
	Taco = { rarity = "Rare", weight = 5, value = 8, interval = 3.2 },
	Sushi = { rarity = "Rare", weight = 4, value = 10, interval = 3.4 },
	Pizza = { rarity = "Epic", weight = 1.5, value = 30, interval = 3.5 },
	Burger = { rarity = "Legendary", weight = 0.4, value = 120, interval = 4.0 },
	GoldenCake = { rarity = "Mythic", weight = 0.1, value = 600, interval = 4.5 },
}
Config.FoodOrder = { "Apple", "Carrot", "Donut", "Taco", "Sushi", "Pizza", "Burger", "GoldenCake" }
Config.DisplayNames = { GoldenCake = "Golden Cake", TRex = "T-Rex" }

Config.Roll = { cooldown = 2.6, spinTime = 2.2, maxInventory = 30, maxDistance = 16 }
-- foodSize = largest dimension of a food model in studs (fits a pedestal top)
Config.Farm = { margin = 2.6, foodSize = 3.4, placeTime = 0.55 }
Config.Coins = { magnetRadius = 7.5, maxPerPlot = 80, collectSlack = 10 } -- walk along the apron to scoop them up
-- Pets come out of lucky blocks, roam your farm, and grow when you feed them coins.
-- Pets (and wild monsters) are measured by WEIGHT in kg: it's their power (x aura), it sets their
-- size (cube-root: 10 kg = normal, 80 kg = double), feeding adds to it, and it sets ride speed.
-- height = model height in studs at 10 kg; mouth = where fed coins fly to (fractions of the
-- height: forward, up); margin = how far from the fence it keeps while roaming.
export type PetDef = { rarity: string, height: number, mouth: { number }, margin: number }
Config.Pets = {
	Hippo = { rarity = "Epic", height = 3.4, mouth = { 0.41, 0.47 }, margin = 4.5 },
	TRex = { rarity = "Legendary", height = 5.5, mouth = { 0.84, 0.73 }, margin = 7 },
} :: { [string]: PetDef }
Config.PetOrder = { "Hippo", "TRex" } -- fixed order so weighted picks are stable
Config.Pet = { baseWeight = 10, baseCost = 8, costCurve = 1.15, feedGain = 0.18, baseHeight = 3.4, margin = 4.5,
	feedDistance = 12, maxOnFarm = 8, maxScale = 3.2,
	-- riding: hold E on a pet to mount it, tap E to hop off; heavier (bigger) pets run faster
	rideSpeed = 24, rideSpeedPerScale = 12, maxRideSpeed = 44, mountHold = 0.45 }

function Config.rideSpeed(weight: number): number
	return math.min(Config.Pet.rideSpeed + (Config.petScale(weight) - 1) * Config.Pet.rideSpeedPerScale, Config.Pet.maxRideSpeed)
end

-- "12.4 kg" / "143 kg"
function Config.kg(weight: number): string
	return if weight < 100 then string.format("%.1f kg", weight) else string.format("%d kg", math.floor(weight + 0.5))
end

-- What a feed adds: a share of the current weight (at least 1 kg), to a tenth of a kg.
function Config.feedGain(weight: number): number
	return math.floor(math.max(1, weight * Config.Pet.feedGain) * 10 + 0.5) / 10
end

-- Lucky blocks: each food drop has `chance` to be a lucky block instead of a coin. Walking up
-- picks it up into your hand (one at a time). Opening it costs `cost` coins and hatches one of
-- its `pets` (relative odds; better blocks lean T-Rex) at around `kg` (+-15%; better blocks hatch
-- heavier pets); or you can toss it.
-- Tier names match the models in Assets.Lucky and auras in Assets.Auras.
Config.Lucky = {
	chance = 0.1, -- 1 in 10 drops
	maxPerPlot = 4, -- blocks waiting on a plot at once; further drops are coins until one is picked up
	pickupDistance = 8,
	size = 2.4, -- cube size in studs on the stand (measured front-to-back, so wings don't shrink it)
	handSize = 1.4, -- cube size when held
	tiers = {
		{ name = "Lucky", weight = 70, pets = { Hippo = 75, TRex = 25 }, kg = 10, cost = 15, scale = 1, color = Color3.fromRGB(255, 210, 60) },
		{ name = "Super", weight = 22, pets = { Hippo = 55, TRex = 45 }, kg = 25, cost = 60, scale = 1.08, color = Color3.fromRGB(80, 200, 255) },
		{ name = "Mega", weight = 7, pets = { Hippo = 35, TRex = 65 }, kg = 60, cost = 200, scale = 1.16, color = Color3.fromRGB(140, 230, 80) },
		{ name = "Mythic", weight = 1, pets = { Hippo = 15, TRex = 85 }, kg = 150, cost = 800, scale = 1.3, color = Color3.fromRGB(255, 180, 50) },
	},
}

-- The Wilds: take a pet into the brush; every `stepDistance` studs walked in the grass there's
-- `encounterChance` of a wild pet. Its weight comes from the zone (MinWeight/MaxWeight on the
-- brush), else your pet's weight x a random spread. Win the roll
-- and you get an aura; lose and your pet is knocked out (back to the farm) for `koTime` seconds.
Config.Wilds = {
	stepDistance = 4,
	encounterChance = 0.22,
	cooldown = 4, -- seconds after an encounter before the next can start
	koTime = 20,
	species = { TRex = 1, Hippo = 1 },
	weightSpread = { 0.6, 1.4 },
}

-- Wild monsters (Assets.Monsters.<id>; Verity is "Verity" by gasweet1 from the Creator Store,
-- the rest from blender/monsters_voxel.py). Zones list which ones live there (BrushZone "Species" attribute);
-- height = model height in studs at 10 kg.
Config.Monsters = {
	Verity = { height = 17.6, color = Color3.fromRGB(242, 207, 20), title = "Always smiling..." },
	Slime = { height = 4.2, color = Color3.fromRGB(98, 200, 90), title = "Jiggly menace" },
	Shroom = { height = 4.6, color = Color3.fromRGB(224, 72, 72), title = "Spore spitter" },
	Boar = { height = 4.4, color = Color3.fromRGB(162, 104, 64), title = "Tusk charger" },
	Beetle = { height = 3.4, color = Color3.fromRGB(62, 110, 220), title = "Horned bruiser" },
} :: { [string]: { height: number, color: Color3, title: string } }

-- Pet auras: won in the Wilds, applied to a pet to multiply its power. vfx = Assets.Auras.<vfx>.
-- weight = drop odds (rarer ones get likelier against stronger wild pets).
export type AuraDef = { tier: number, name: string, mult: number, vfx: string, weight: number, rarity: string, color: Color3 }
Config.PetAuras = {
	GoldenAura = { tier = 1, name = "Golden Aura", mult = 1.25, vfx = "Lucky", weight = 60, rarity = "Rare", color = Color3.fromRGB(255, 210, 60) },
	FrostAura = { tier = 2, name = "Frost Aura", mult = 1.5, vfx = "Super", weight = 28, rarity = "Epic", color = Color3.fromRGB(80, 200, 255) },
	VenomAura = { tier = 3, name = "Venom Aura", mult = 2, vfx = "Mega", weight = 10, rarity = "Legendary", color = Color3.fromRGB(140, 230, 80) },
	MythicAura = { tier = 4, name = "Mythic Aura", mult = 3, vfx = "Mythic", weight = 2, rarity = "Mythic", color = Color3.fromRGB(255, 120, 200) },
} :: { [string]: AuraDef }
Config.AuraOrder = { "GoldenAura", "FrostAura", "VenomAura", "MythicAura" }

-- Uploaded images (rbxassetid). Icons are filled in once the food renders are uploaded.
Config.CoinImage = "rbxassetid://70480447399148"
Config.CoinEmblem = "rbxassetid://83430600226589" -- burger sticker on both faces of the 3D coin
-- Stud-brick UI art (Higgsfield renders, art/ui/): held lucky block panel
Config.UI = {
	luckyPanel = "rbxassetid://118822797047310", -- cream plate, 1024x346
	luckyOpen = "rbxassetid://83952168391724", -- green brick button, 768x259
	luckyToss = "rbxassetid://83805577554792", -- red brick button, 512x457
	luckyBlock = "rbxassetid://124129880427517", -- white "?" block, tinted per tier, 512x534
	redBrick = "rbxassetid://82725301101386", -- red brick button (same shape as luckyPanel), 768x259
	alertBubble = "rbxassetid://86747072634403", -- cartoon "!" speech bubble (encounter alert)
	speedLines = "rbxassetid://90548719715949", -- white radial speed lines, clear center
	vignette = "rbxassetid://81712027018080", -- soft dark edges
}
Config.Icons = {
	Apple = "rbxassetid://83428066206423",
	Carrot = "rbxassetid://86111893399534",
	Donut = "rbxassetid://104204052855064",
	Taco = "rbxassetid://101464649432533",
	Sushi = "rbxassetid://131815850094780",
	Pizza = "rbxassetid://91364210848248",
	Burger = "rbxassetid://128047171764827",
	GoldenCake = "rbxassetid://88912320673514",
	Hippo = "rbxassetid://125844986022005",
	TRex = "rbxassetid://132255993621615",
	GoldenAura = "rbxassetid://111183445035245",
	FrostAura = "rbxassetid://114575229175933",
	VenomAura = "rbxassetid://88664505435328",
	MythicAura = "rbxassetid://85590058720171",
} :: { [string]: string }

-- Sound ids (rbxassetid); missing entries are simply silent.
-- Mostly the free "Daily Sounds" Creator Store set so the sound palette stays consistent.
Config.Sounds = {
	pop = "rbxassetid://106984966606682", -- Cartoon Pop
	tick = "rbxassetid://106984966606682", -- reel ticks (pitched pop)
	place = "rbxassetid://106984966606682",
	land = "rbxassetid://133564751966469", -- Platformer Jump
	lever = "rbxassetid://133564751966469",
	coin = "rbxassetid://116120982042508", -- Coin Collecting Sound (short 0.34s bling; old: 130378474223829)
	whoosh = "rbxassetid://80984744279155", -- Fast Whoosh
	gulp = "rbxassetid://109679860270937", -- Slurp
	rare = "rbxassetid://4757565956", -- TaDa
	grow = "rbxassetid://4757565956",
} :: { [string]: string }

-- Coins for one feed: grows with weight.
function Config.petCost(weight: number): number
	return math.max(1, math.floor(Config.Pet.baseCost * (weight / Config.Pet.baseWeight) ^ Config.Pet.costCurve + 0.5))
end

-- Size from weight (cube root, like real volume): 10 kg = 1x, 80 kg = 2x, 270 kg = 3x.
function Config.petScale(weight: number): number
	return math.clamp((weight / Config.Pet.baseWeight) ^ (1 / 3), 0.6, Config.Pet.maxScale)
end

function Config.displayName(id: string): string
	local aura = Config.PetAuras[id]
	return Config.DisplayNames[id] or (aura and aura.name) or id
end

function Config.isAura(id: string): boolean
	return Config.PetAuras[id] ~= nil
end

-- A pet's fighting power: its weight, multiplied by its aura.
function Config.petPower(weight: number, auraId: string?): number
	local aura = auraId and Config.PetAuras[auraId]
	return weight * (if aura then aura.mult else 1)
end

-- Win chance (whole percent) of `mine` against `wild`: even fight = 50%, capped to 5..95.
function Config.winChance(mine: number, wild: number): number
	local edge = (mine - wild) / math.max(mine, wild, 1)
	return math.clamp(math.floor(50 + 45 * edge + 0.5), 5, 95)
end

function Config.isPet(id: string): boolean
	return Config.Pets[id] ~= nil
end

function Config.rarityOf(id: string)
	local food = Config.Foods[id] or Config.Pets[id] or Config.PetAuras[id]
	return food and Config.Rarities[food.rarity] or Config.Rarities.Common, food and food.rarity or "Common"
end

return Config
