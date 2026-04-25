--[[
	ShipBuilder (Client utility)
	============================
	Creates a polished pirate-ship GUI visual with UIGradient shading,
	layered depth, and animated billowing sails.

	SHIP DESIGN (top-down view):

	       ▲  bowsprit (gilded tip)
	      ╱│╲
	     ╱ │ ╲   bow (tapered, gradient-shaded)
	    ╱  │  ╲
	   ║═══●═══║  cannon ports (barrels + mounts)
	   ║  ╔═╗  ║  hull (gradient wood + plank lines)
	   ║  ║▓║  ║  sail (animated billow via UIGradient)
	   ║  ╚═╝  ║
	   ║═══●═══║  cannon ports (rear pair)
	    ╲  █  ╱
	     ╲_█_╱    stern (captain's cabin + ornament)
	       ▼  rudder + flag

	Features:
	- UIGradient on hull/bow/stern for 3D depth & lighting illusion
	- Drop shadow beneath the ship for a floating look
	- Animated sail: UIGradient offset oscillates to simulate wind
	- Railing / gunwale trim with gold highlights
	- Bold variable-thickness cartoon outlines
	- Flag pennant that sways with its own animation

	The entire ship is one root Frame, positioned/rotated by ShipController.
	Call ShipBuilder.startSailAnimation(shipFrame) after parenting to canvas.
]]

local TweenService = game:GetService("TweenService")
local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local ShipBuilder = {}

-- Richer color palettes with light/dark variants for gradients
local SHIP_COLORS = {
	{ -- Red
		hull      = Color3.fromRGB(165, 48, 42),
		hullLight = Color3.fromRGB(215, 90, 75),
		hullDark  = Color3.fromRGB(95, 22, 18),
		deck      = Color3.fromRGB(185, 140, 95),
		deckDark  = Color3.fromRGB(130, 90, 55),
		accent    = Color3.fromRGB(255, 210, 65),
		trim      = Color3.fromRGB(120, 28, 22),
		sail      = Color3.fromRGB(250, 240, 225),
		sailShade = Color3.fromRGB(215, 185, 155),
		railing   = Color3.fromRGB(225, 185, 110),
	},
	{ -- Blue
		hull      = Color3.fromRGB(42, 90, 175),
		hullLight = Color3.fromRGB(80, 140, 220),
		hullDark  = Color3.fromRGB(22, 50, 110),
		deck      = Color3.fromRGB(180, 148, 102),
		deckDark  = Color3.fromRGB(128, 98, 58),
		accent    = Color3.fromRGB(255, 218, 75),
		trim      = Color3.fromRGB(22, 48, 100),
		sail      = Color3.fromRGB(232, 242, 255),
		sailShade = Color3.fromRGB(185, 208, 242),
		railing   = Color3.fromRGB(218, 192, 128),
	},
	{ -- Green
		hull      = Color3.fromRGB(42, 148, 62),
		hullLight = Color3.fromRGB(78, 198, 100),
		hullDark  = Color3.fromRGB(22, 88, 35),
		deck      = Color3.fromRGB(178, 145, 98),
		deckDark  = Color3.fromRGB(125, 95, 55),
		accent    = Color3.fromRGB(255, 225, 72),
		trim      = Color3.fromRGB(20, 82, 32),
		sail      = Color3.fromRGB(228, 248, 232),
		sailShade = Color3.fromRGB(182, 218, 188),
		railing   = Color3.fromRGB(215, 188, 118),
	},
	{ -- Gold
		hull      = Color3.fromRGB(178, 138, 38),
		hullLight = Color3.fromRGB(228, 188, 68),
		hullDark  = Color3.fromRGB(108, 78, 18),
		deck      = Color3.fromRGB(192, 155, 105),
		deckDark  = Color3.fromRGB(138, 102, 58),
		accent    = Color3.fromRGB(255, 235, 120),
		trim      = Color3.fromRGB(105, 75, 15),
		sail      = Color3.fromRGB(252, 248, 228),
		sailShade = Color3.fromRGB(228, 215, 178),
		railing   = Color3.fromRGB(238, 208, 128),
	},
	{ -- Purple
		hull      = Color3.fromRGB(128, 48, 178),
		hullLight = Color3.fromRGB(172, 88, 225),
		hullDark  = Color3.fromRGB(72, 22, 112),
		deck      = Color3.fromRGB(175, 142, 100),
		deckDark  = Color3.fromRGB(122, 92, 58),
		accent    = Color3.fromRGB(255, 215, 85),
		trim      = Color3.fromRGB(68, 20, 108),
		sail      = Color3.fromRGB(238, 225, 248),
		sailShade = Color3.fromRGB(205, 185, 228),
		railing   = Color3.fromRGB(218, 188, 125),
	},
	{ -- Orange
		hull      = Color3.fromRGB(188, 98, 38),
		hullLight = Color3.fromRGB(235, 142, 68),
		hullDark  = Color3.fromRGB(115, 52, 18),
		deck      = Color3.fromRGB(185, 150, 102),
		deckDark  = Color3.fromRGB(132, 98, 58),
		accent    = Color3.fromRGB(255, 228, 82),
		trim      = Color3.fromRGB(110, 48, 15),
		sail      = Color3.fromRGB(248, 238, 222),
		sailShade = Color3.fromRGB(225, 198, 162),
		railing   = Color3.fromRGB(228, 195, 118),
	},
}

-- Outline color (rich dark, not pure black — looks more polished)
local OUTLINE = Color3.fromRGB(18, 14, 28)

-- Helper: attach a UICorner to a frame
local function addCorner(parent: Frame, radius: UDim): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

-- Helper: attach a UIStroke outline
local function addOutline(parent: Frame, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or OUTLINE
	s.Thickness = thickness
	s.Parent = parent
	return s
end

-- Helper: attach a UIGradient (vertical by default)
local function addGradient(parent: Frame, colorTop: Color3, colorBot: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorTop),
		ColorSequenceKeypoint.new(1, colorBot),
	})
	g.Rotation = rotation or 90 -- top-to-bottom by default
	g.Parent = parent
	return g
end

--[[
	Creates a professional pirate ship GUI element with gradient shading
	and layered detail.

	@param colorIndex: number (1-6) to pick a color palette
	@return Frame: the ship's root frame (position and rotate this)
]]
function ShipBuilder.createShip(colorIndex: number): Frame
	local colors = SHIP_COLORS[((colorIndex - 1) % #SHIP_COLORS) + 1]
	local shipW = Constants.SHIP_SIZE.X
	local shipH = Constants.SHIP_SIZE.Y

	-- Root container (invisible, positioned/rotated by ShipController)
	local root = Instance.new("Frame")
	root.Name = "Ship"
	root.Size = UDim2.new(0, shipW, 0, shipH)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 0 — DROP SHADOW (depth / floating look)  ║
	-- ╚══════════════════════════════════════════════════╝
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(0.88, 0, 0.82, 0)
	shadow.Position = UDim2.new(0.54, 0, 0.55, 0) -- offset slightly down-right
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
	shadow.BackgroundTransparency = 0.65
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = root
	addCorner(shadow, UDim.new(0.22, 0))

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 1 — HULL (main body with gradient)       ║
	-- ╚══════════════════════════════════════════════════╝
	local hull = Instance.new("Frame")
	hull.Name = "Hull"
	hull.Size = UDim2.new(0.84, 0, 0.64, 0)
	hull.Position = UDim2.new(0.5, 0, 0.52, 0)
	hull.AnchorPoint = Vector2.new(0.5, 0.5)
	hull.BackgroundColor3 = colors.hull
	hull.BorderSizePixel = 0
	hull.ZIndex = 3
	hull.Parent = root
	addCorner(hull, UDim.new(0.16, 0))
	addOutline(hull, 2.5)

	-- Hull gradient: lighter at the top edge (waterline highlight) → darker below
	addGradient(hull, colors.hullLight, colors.hullDark, 90)

	-- ── Hull plank line 1 (subtle horizontal detail)
	local plank1 = Instance.new("Frame")
	plank1.Name = "Plank1"
	plank1.Size = UDim2.new(0.92, 0, 0.04, 0)
	plank1.Position = UDim2.new(0.5, 0, 0.38, 0)
	plank1.AnchorPoint = Vector2.new(0.5, 0.5)
	plank1.BackgroundColor3 = colors.trim
	plank1.BorderSizePixel = 0
	plank1.ZIndex = 4
	plank1.Parent = hull

	-- ── Hull plank line 2
	local plank2 = Instance.new("Frame")
	plank2.Name = "Plank2"
	plank2.Size = UDim2.new(0.85, 0, 0.035, 0)
	plank2.Position = UDim2.new(0.5, 0, 0.62, 0)
	plank2.AnchorPoint = Vector2.new(0.5, 0.5)
	plank2.BackgroundColor3 = colors.trim
	plank2.BorderSizePixel = 0
	plank2.ZIndex = 4
	plank2.Parent = hull

	-- ── Hull plank line 3 (faint)
	local plank3 = Instance.new("Frame")
	plank3.Name = "Plank3"
	plank3.Size = UDim2.new(0.7, 0, 0.025, 0)
	plank3.Position = UDim2.new(0.5, 0, 0.82, 0)
	plank3.AnchorPoint = Vector2.new(0.5, 0.5)
	plank3.BackgroundColor3 = colors.trim
	plank3.BorderSizePixel = 0
	plank3.ZIndex = 4
	plank3.Parent = hull

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 2 — BOW (tapered front with gradient)    ║
	-- ╚══════════════════════════════════════════════════╝
	local bow = Instance.new("Frame")
	bow.Name = "Bow"
	bow.Size = UDim2.new(0.58, 0, 0.34, 0)
	bow.Position = UDim2.new(0.5, 0, 0.12, 0)
	bow.AnchorPoint = Vector2.new(0.5, 0.5)
	bow.BackgroundColor3 = colors.hull
	bow.BorderSizePixel = 0
	bow.ZIndex = 3
	bow.Parent = root
	addCorner(bow, UDim.new(0.58, 0))
	addOutline(bow, 2.5)
	addGradient(bow, colors.hullLight, colors.hull, 90)

	-- Inner bow highlight (narrow lighter strip for curvature)
	local bowHighlight = Instance.new("Frame")
	bowHighlight.Name = "BowHighlight"
	bowHighlight.Size = UDim2.new(0.35, 0, 0.5, 0)
	bowHighlight.Position = UDim2.new(0.5, 0, 0.35, 0)
	bowHighlight.AnchorPoint = Vector2.new(0.5, 0.5)
	bowHighlight.BackgroundColor3 = colors.hullLight
	bowHighlight.BorderSizePixel = 0
	bowHighlight.ZIndex = 4
	bowHighlight.Parent = bow
	addCorner(bowHighlight, UDim.new(0.5, 0))

	-- Bow highlight gradient fades to transparent at edges
	local bhGrad = Instance.new("UIGradient")
	bhGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	bhGrad.Rotation = 0 -- left-to-right
	bhGrad.Parent = bowHighlight

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 3 — BOWSPRIT (gilded tip at front)       ║
	-- ╚══════════════════════════════════════════════════╝
	local bowsprit = Instance.new("Frame")
	bowsprit.Name = "Bowsprit"
	bowsprit.Size = UDim2.new(0.15, 0, 0.14, 0)
	bowsprit.Position = UDim2.new(0.5, 0, -0.01, 0)
	bowsprit.AnchorPoint = Vector2.new(0.5, 0.5)
	bowsprit.BackgroundColor3 = colors.accent
	bowsprit.BorderSizePixel = 0
	bowsprit.ZIndex = 7
	bowsprit.Parent = root
	addCorner(bowsprit, UDim.new(0.5, 0))
	addOutline(bowsprit, 1.5)

	-- Gold sheen gradient on bowsprit
	addGradient(bowsprit, Color3.fromRGB(255, 248, 200), colors.accent, 135)

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 4 — STERN (captain's quarters, wide)     ║
	-- ╚══════════════════════════════════════════════════╝
	local stern = Instance.new("Frame")
	stern.Name = "Stern"
	stern.Size = UDim2.new(0.76, 0, 0.2, 0)
	stern.Position = UDim2.new(0.5, 0, 0.88, 0)
	stern.AnchorPoint = Vector2.new(0.5, 0.5)
	stern.BackgroundColor3 = colors.hull
	stern.BorderSizePixel = 0
	stern.ZIndex = 3
	stern.Parent = root
	addCorner(stern, UDim.new(0.3, 0))
	addOutline(stern, 2)
	addGradient(stern, colors.hull, colors.hullDark, 90)

	-- Stern ornamental strip (gold trim)
	local sternTrim = Instance.new("Frame")
	sternTrim.Name = "SternTrim"
	sternTrim.Size = UDim2.new(0.8, 0, 0.18, 0)
	sternTrim.Position = UDim2.new(0.5, 0, 0.3, 0)
	sternTrim.AnchorPoint = Vector2.new(0.5, 0.5)
	sternTrim.BackgroundColor3 = colors.accent
	sternTrim.BorderSizePixel = 0
	sternTrim.ZIndex = 4
	sternTrim.Parent = stern
	addCorner(sternTrim, UDim.new(0.3, 0))

	-- Stern window (tiny dark porthole for detail)
	local sternWindow = Instance.new("Frame")
	sternWindow.Name = "SternWindow"
	sternWindow.Size = UDim2.new(0.22, 0, 0.35, 0)
	sternWindow.Position = UDim2.new(0.5, 0, 0.6, 0)
	sternWindow.AnchorPoint = Vector2.new(0.5, 0.5)
	sternWindow.BackgroundColor3 = colors.hullDark
	sternWindow.BorderSizePixel = 0
	sternWindow.ZIndex = 4
	sternWindow.Parent = stern
	addCorner(sternWindow, UDim.new(0.35, 0))

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 5 — RAILING / GUNWALE (gold edge trim)   ║
	-- ╚══════════════════════════════════════════════════╝
	-- Left railing
	local railL = Instance.new("Frame")
	railL.Name = "RailingLeft"
	railL.Size = UDim2.new(0.06, 0, 0.52, 0)
	railL.Position = UDim2.new(0.1, 0, 0.5, 0)
	railL.AnchorPoint = Vector2.new(0.5, 0.5)
	railL.BackgroundColor3 = colors.railing
	railL.BorderSizePixel = 0
	railL.ZIndex = 5
	railL.Parent = root
	addCorner(railL, UDim.new(0.5, 0))
	addGradient(railL, colors.accent, colors.railing, 90)

	-- Right railing
	local railR = Instance.new("Frame")
	railR.Name = "RailingRight"
	railR.Size = UDim2.new(0.06, 0, 0.52, 0)
	railR.Position = UDim2.new(0.9, 0, 0.5, 0)
	railR.AnchorPoint = Vector2.new(0.5, 0.5)
	railR.BackgroundColor3 = colors.railing
	railR.BorderSizePixel = 0
	railR.ZIndex = 5
	railR.Parent = root
	addCorner(railR, UDim.new(0.5, 0))
	addGradient(railR, colors.accent, colors.railing, 90)

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 6 — DECK (warm wood tone, central)       ║
	-- ╚══════════════════════════════════════════════════╝
	local deck = Instance.new("Frame")
	deck.Name = "Deck"
	deck.Size = UDim2.new(0.52, 0, 0.38, 0)
	deck.Position = UDim2.new(0.5, 0, 0.5, 0)
	deck.AnchorPoint = Vector2.new(0.5, 0.5)
	deck.BackgroundColor3 = colors.deck
	deck.BorderSizePixel = 0
	deck.ZIndex = 5
	deck.Parent = root
	addCorner(deck, UDim.new(0.12, 0))
	addOutline(deck, 1)
	addGradient(deck, colors.deck, colors.deckDark, 90)

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 7 — MAST (vertical pole through center)  ║
	-- ╚══════════════════════════════════════════════════╝
	local mast = Instance.new("Frame")
	mast.Name = "Mast"
	mast.Size = UDim2.new(0.065, 0, 0.58, 0)
	mast.Position = UDim2.new(0.5, 0, 0.42, 0)
	mast.AnchorPoint = Vector2.new(0.5, 0.5)
	mast.BackgroundColor3 = Color3.fromRGB(95, 62, 35)
	mast.BorderSizePixel = 0
	mast.ZIndex = 6
	mast.Parent = root
	addCorner(mast, UDim.new(0.5, 0))
	addGradient(mast, Color3.fromRGB(130, 92, 55), Color3.fromRGB(65, 40, 22), 0)

	-- Crow's nest (small circle at top of mast)
	local crowsNest = Instance.new("Frame")
	crowsNest.Name = "CrowsNest"
	crowsNest.Size = UDim2.new(0.12, 0, 0.055, 0)
	crowsNest.Position = UDim2.new(0.5, 0, 0.18, 0)
	crowsNest.AnchorPoint = Vector2.new(0.5, 0.5)
	crowsNest.BackgroundColor3 = Color3.fromRGB(85, 55, 30)
	crowsNest.BorderSizePixel = 0
	crowsNest.ZIndex = 7
	crowsNest.Parent = root
	addCorner(crowsNest, UDim.new(0.5, 0))
	addOutline(crowsNest, 1)

	-- ╔══════════════════════════════════════════════════════════╗
	-- ║  LAYER 8 — SAIL (animated billow via UIGradient offset) ║
	-- ╚══════════════════════════════════════════════════════════╝
	local sail = Instance.new("Frame")
	sail.Name = "Sail"
	sail.Size = UDim2.new(0.52, 0, 0.3, 0)
	sail.Position = UDim2.new(0.5, 0, 0.4, 0)
	sail.AnchorPoint = Vector2.new(0.5, 0.5)
	sail.BackgroundColor3 = colors.sail
	sail.BorderSizePixel = 0
	sail.ZIndex = 7
	sail.Parent = root
	addCorner(sail, UDim.new(0.22, 0))
	addOutline(sail, 1.5)

	-- Sail billow gradient: simulates curvature from wind
	-- The color shifts from shadow (edges) → bright (center bulge)
	local sailGrad = Instance.new("UIGradient")
	sailGrad.Name = "SailBillowGrad"
	sailGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors.sailShade),
		ColorSequenceKeypoint.new(0.35, colors.sail),
		ColorSequenceKeypoint.new(0.65, colors.sail),
		ColorSequenceKeypoint.new(1, colors.sailShade),
	})
	sailGrad.Rotation = 0 -- horizontal across the sail
	sailGrad.Offset = Vector2.new(-0.12, 0)
	sailGrad.Parent = sail

	-- Sail crossbar (horizontal yard/boom)
	local yard = Instance.new("Frame")
	yard.Name = "Yard"
	yard.Size = UDim2.new(0.65, 0, 0.06, 0)
	yard.Position = UDim2.new(0.5, 0, 0.15, 0)
	yard.AnchorPoint = Vector2.new(0.5, 0.5)
	yard.BackgroundColor3 = Color3.fromRGB(100, 68, 38)
	yard.BorderSizePixel = 0
	yard.ZIndex = 8
	yard.Parent = sail
	addCorner(yard, UDim.new(0.5, 0))

	-- Second yard at bottom of sail
	local yard2 = Instance.new("Frame")
	yard2.Name = "Yard2"
	yard2.Size = UDim2.new(0.55, 0, 0.05, 0)
	yard2.Position = UDim2.new(0.5, 0, 0.85, 0)
	yard2.AnchorPoint = Vector2.new(0.5, 0.5)
	yard2.BackgroundColor3 = Color3.fromRGB(90, 60, 34)
	yard2.BorderSizePixel = 0
	yard2.ZIndex = 8
	yard2.Parent = sail
	addCorner(yard2, UDim.new(0.5, 0))

	-- Team emblem on sail (small colored dot)
	local emblem = Instance.new("Frame")
	emblem.Name = "Emblem"
	emblem.Size = UDim2.new(0.28, 0, 0.28, 0)
	emblem.Position = UDim2.new(0.5, 0, 0.5, 0)
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.BackgroundColor3 = colors.hull
	emblem.BorderSizePixel = 0
	emblem.ZIndex = 8
	emblem.Parent = sail
	addCorner(emblem, UDim.new(1, 0))

	-- ╔══════════════════════════════════════════════════════════╗
	-- ║  LAYER 9 — CANNON BARRELS (paired, with gradient metal) ║
	-- ╚══════════════════════════════════════════════════════════╝
	for _, side in { "Left", "Right" } do
		local isLeft = (side == "Left")
		local xBarrel = if isLeft then 0.0 else 1.0
		local xMount  = if isLeft then 0.12 else 0.88

		-- Front cannon barrel
		local barrel = Instance.new("Frame")
		barrel.Name = "Cannon" .. side
		barrel.Size = UDim2.new(0.3, 0, 0.085, 0)
		barrel.Position = UDim2.new(xBarrel, 0, 0.4, 0)
		barrel.AnchorPoint = Vector2.new(0.5, 0.5)
		barrel.BackgroundColor3 = Color3.fromRGB(50, 48, 55)
		barrel.BorderSizePixel = 0
		barrel.ZIndex = 4
		barrel.Parent = root
		addCorner(barrel, UDim.new(0.35, 0))
		addOutline(barrel, 1.5)

		-- Metallic sheen on barrel
		addGradient(barrel,
			Color3.fromRGB(85, 82, 90),
			Color3.fromRGB(30, 28, 35),
			if isLeft then 90 else 270
		)

		-- Cannon mount (bronze circle)
		local mount = Instance.new("Frame")
		mount.Name = "CannonMount" .. side
		mount.Size = UDim2.new(0.14, 0, 0.1, 0)
		mount.Position = UDim2.new(xMount, 0, 0.4, 0)
		mount.AnchorPoint = Vector2.new(0.5, 0.5)
		mount.BackgroundColor3 = Color3.fromRGB(148, 118, 62)
		mount.BorderSizePixel = 0
		mount.ZIndex = 5
		mount.Parent = root
		addCorner(mount, UDim.new(1, 0))
		addGradient(mount, Color3.fromRGB(185, 155, 85), Color3.fromRGB(105, 78, 38), 135)

		-- Rear cannon barrel (slightly smaller)
		local barrel2 = Instance.new("Frame")
		barrel2.Name = "Cannon" .. side .. "Rear"
		barrel2.Size = UDim2.new(0.26, 0, 0.07, 0)
		barrel2.Position = UDim2.new(xBarrel, 0, 0.62, 0)
		barrel2.AnchorPoint = Vector2.new(0.5, 0.5)
		barrel2.BackgroundColor3 = Color3.fromRGB(50, 48, 55)
		barrel2.BorderSizePixel = 0
		barrel2.ZIndex = 4
		barrel2.Parent = root
		addCorner(barrel2, UDim.new(0.35, 0))
		addOutline(barrel2, 1.5)
		addGradient(barrel2,
			Color3.fromRGB(80, 78, 88),
			Color3.fromRGB(30, 28, 35),
			if isLeft then 90 else 270
		)

		-- Rear cannon mount
		local mount2 = Instance.new("Frame")
		mount2.Name = "CannonMount" .. side .. "Rear"
		mount2.Size = UDim2.new(0.11, 0, 0.08, 0)
		mount2.Position = UDim2.new(if isLeft then 0.14 else 0.86, 0, 0.62, 0)
		mount2.AnchorPoint = Vector2.new(0.5, 0.5)
		mount2.BackgroundColor3 = Color3.fromRGB(140, 112, 58)
		mount2.BorderSizePixel = 0
		mount2.ZIndex = 5
		mount2.Parent = root
		addCorner(mount2, UDim.new(1, 0))
	end

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 10 — DIRECTION INDICATOR (bow glow)      ║
	-- ╚══════════════════════════════════════════════════╝
	local indicator = Instance.new("Frame")
	indicator.Name = "DirectionDot"
	indicator.Size = UDim2.new(0.16, 0, 0.065, 0)
	indicator.Position = UDim2.new(0.5, 0, 0.06, 0)
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.BackgroundColor3 = colors.accent
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 8
	indicator.Parent = root
	addCorner(indicator, UDim.new(1, 0))

	-- Glow effect on direction indicator
	local indicatorGlow = Instance.new("UIStroke")
	indicatorGlow.Color = colors.accent
	indicatorGlow.Thickness = 2
	indicatorGlow.Transparency = 0.4
	indicatorGlow.Parent = indicator

	-- ╔══════════════════════════════════════════════════╗
	-- ║  LAYER 11 — FLAG (pennant at stern, animated)   ║
	-- ╚══════════════════════════════════════════════════╝
	local flag = Instance.new("Frame")
	flag.Name = "Flag"
	flag.Size = UDim2.new(0.2, 0, 0.1, 0)
	flag.Position = UDim2.new(0.5, 0, 0.96, 0)
	flag.AnchorPoint = Vector2.new(0.5, 0.5)
	flag.BackgroundColor3 = colors.hull
	flag.BorderSizePixel = 0
	flag.ZIndex = 8
	flag.Parent = root
	addCorner(flag, UDim.new(0.25, 0))
	addOutline(flag, 1)

	-- Flag gradient (team-color sheen)
	addGradient(flag, colors.hullLight, colors.hull, 0)

	-- ╔══════════════════════════════════════════════════╗
	-- ║  AUTO-START SAIL + FLAG ANIMATION                ║
	-- ╚══════════════════════════════════════════════════╝
	ShipBuilder._animateSail(sailGrad)
	ShipBuilder._animateFlag(flag)

	return root
end

--[[
	Animates the sail's UIGradient offset to create a billowing wind effect.
	The gradient shifts left-right in a smooth sine wave, making the
	light/shadow on the sail appear to ripple as if catching wind.
]]
function ShipBuilder._animateSail(sailGrad: UIGradient)
	sailGrad.Offset = Vector2.new(-0.12, -0.04)

	local billowTween = TweenService:Create(sailGrad,
		TweenInfo.new(
			1.8,                              -- duration
			Enum.EasingStyle.Sine,            -- smooth natural motion
			Enum.EasingDirection.InOut,
			-1,                               -- repeat forever
			true                              -- reverse (oscillate)
		),
		{ Offset = Vector2.new(0.12, 0.04) }
	)
	billowTween:Play()
end

--[[
	Gives the flag a gentle sway by tweening its Rotation.
]]
function ShipBuilder._animateFlag(flag: Frame)
	flag.Rotation = -8

	local swayTween = TweenService:Create(flag,
		TweenInfo.new(
			1.2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ Rotation = 8 }
	)
	swayTween:Play()
end

-- Helper to get a color index from a player's UserId
function ShipBuilder.getColorIndex(userId: number): number
	return (userId % #SHIP_COLORS) + 1
end

return ShipBuilder