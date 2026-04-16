--[[
	ShipBuilder (Shared/Client utility)
	====================================
	Creates a cartoon pirate-ship GUI visual.
	
	Each ship is built from multiple colored Frames arranged
	to form a chunky, cartoony boat shape with visible cannons,
	wood plank details, a sail, and a bold outline.
	
	SHIP SHAPE (top-down view):
	
	       ▲  bowsprit
	      /|\
	     / | \   bow (pointed, rounded)
	    /  |  \
	   |===●===|  cannons (barrels sticking out)
	   |  [■]  |  hull + sail
	   |===●===|  cannons
	    \  |  /
	     \_█_/    stern + rudder
	       ▼  flag
	
	The entire ship is contained in one parent Frame that gets
	rotated/positioned by ShipController.
]]

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local ShipBuilder = {}

-- Color palettes for different players — richer cartoon tones
local SHIP_COLORS = {
	{ hull = Color3.fromRGB(190, 55, 55),   deck = Color3.fromRGB(145, 40, 40),  accent = Color3.fromRGB(240, 90, 90),  trim = Color3.fromRGB(120, 30, 30),  sail = Color3.fromRGB(230, 210, 190) },  -- Red
	{ hull = Color3.fromRGB(55, 115, 190),  deck = Color3.fromRGB(40, 85, 145),  accent = Color3.fromRGB(90, 160, 240), trim = Color3.fromRGB(30, 60, 120),  sail = Color3.fromRGB(210, 225, 240) },  -- Blue
	{ hull = Color3.fromRGB(55, 170, 75),   deck = Color3.fromRGB(40, 125, 55),  accent = Color3.fromRGB(90, 215, 110), trim = Color3.fromRGB(30, 90, 40),   sail = Color3.fromRGB(210, 235, 215) },  -- Green
	{ hull = Color3.fromRGB(190, 150, 45),  deck = Color3.fromRGB(145, 115, 35), accent = Color3.fromRGB(235, 195, 65), trim = Color3.fromRGB(120, 85, 20),  sail = Color3.fromRGB(240, 235, 210) },  -- Gold
	{ hull = Color3.fromRGB(145, 55, 190),  deck = Color3.fromRGB(110, 40, 145), accent = Color3.fromRGB(180, 90, 235), trim = Color3.fromRGB(80, 25, 120),  sail = Color3.fromRGB(230, 215, 240) },  -- Purple
	{ hull = Color3.fromRGB(195, 105, 45),  deck = Color3.fromRGB(150, 80, 35),  accent = Color3.fromRGB(235, 140, 65), trim = Color3.fromRGB(120, 55, 20),  sail = Color3.fromRGB(240, 225, 210) },  -- Orange
}

--[[
	Creates a cartoon pirate ship GUI element.
	
	@param colorIndex: number (1-6) to pick a color palette
	@return Frame: the ship's root frame (position and rotate this)
]]
function ShipBuilder.createShip(colorIndex: number): Frame
	local colors = SHIP_COLORS[((colorIndex - 1) % #SHIP_COLORS) + 1]
	local shipW = Constants.SHIP_SIZE.X   -- 40
	local shipH = Constants.SHIP_SIZE.Y   -- 60
	
	-- Root container: this is what gets positioned/rotated
	local root = Instance.new("Frame")
	root.Name = "Ship"
	root.Size = UDim2.new(0, shipW, 0, shipH)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- === HULL (main body — chunky rounded rectangle) ===
	local hull = Instance.new("Frame")
	hull.Name = "Hull"
	hull.Size = UDim2.new(0.82, 0, 0.62, 0)
	hull.Position = UDim2.new(0.5, 0, 0.52, 0)
	hull.AnchorPoint = Vector2.new(0.5, 0.5)
	hull.BackgroundColor3 = colors.hull
	hull.BorderSizePixel = 0
	hull.ZIndex = 3
	hull.Parent = root

	local hullCorner = Instance.new("UICorner")
	hullCorner.CornerRadius = UDim.new(0.18, 0)
	hullCorner.Parent = hull

	-- Bold cartoon outline on hull
	local hullOutline = Instance.new("UIStroke")
	hullOutline.Name = "HullOutline"
	hullOutline.Color = Color3.fromRGB(15, 15, 25)
	hullOutline.Thickness = 2.5
	hullOutline.Parent = hull

	-- === HULL TRIM STRIPE (horizontal plank detail) ===
	local trim = Instance.new("Frame")
	trim.Name = "HullTrim"
	trim.Size = UDim2.new(0.9, 0, 0.08, 0)
	trim.Position = UDim2.new(0.5, 0, 0.55, 0)
	trim.AnchorPoint = Vector2.new(0.5, 0.5)
	trim.BackgroundColor3 = colors.trim
	trim.BorderSizePixel = 0
	trim.ZIndex = 4
	trim.Parent = hull

	-- Second trim stripe
	local trim2 = Instance.new("Frame")
	trim2.Name = "HullTrim2"
	trim2.Size = UDim2.new(0.75, 0, 0.06, 0)
	trim2.Position = UDim2.new(0.5, 0, 0.72, 0)
	trim2.AnchorPoint = Vector2.new(0.5, 0.5)
	trim2.BackgroundColor3 = colors.trim
	trim2.BackgroundTransparency = 0.3
	trim2.BorderSizePixel = 0
	trim2.ZIndex = 4
	trim2.Parent = hull

	-- === BOW (front pointed section — more pronounced) ===
	local bow = Instance.new("Frame")
	bow.Name = "Bow"
	bow.Size = UDim2.new(0.55, 0, 0.32, 0)
	bow.Position = UDim2.new(0.5, 0, 0.12, 0)
	bow.AnchorPoint = Vector2.new(0.5, 0.5)
	bow.BackgroundColor3 = colors.hull
	bow.BorderSizePixel = 0
	bow.ZIndex = 3
	bow.Parent = root

	local bowCorner = Instance.new("UICorner")
	bowCorner.CornerRadius = UDim.new(0.55, 0)
	bowCorner.Parent = bow

	local bowOutline = Instance.new("UIStroke")
	bowOutline.Color = Color3.fromRGB(15, 15, 25)
	bowOutline.Thickness = 2.5
	bowOutline.Parent = bow

	-- === BOWSPRIT (pointy tip at the front) ===
	local bowsprit = Instance.new("Frame")
	bowsprit.Name = "Bowsprit"
	bowsprit.Size = UDim2.new(0.14, 0, 0.15, 0)
	bowsprit.Position = UDim2.new(0.5, 0, 0.0, 0)
	bowsprit.AnchorPoint = Vector2.new(0.5, 0.5)
	bowsprit.BackgroundColor3 = colors.accent
	bowsprit.BorderSizePixel = 0
	bowsprit.ZIndex = 5
	bowsprit.Parent = root

	local bowspritCorner = Instance.new("UICorner")
	bowspritCorner.CornerRadius = UDim.new(0.5, 0)
	bowspritCorner.Parent = bowsprit

	local bowspritOutline = Instance.new("UIStroke")
	bowspritOutline.Color = Color3.fromRGB(15, 15, 25)
	bowspritOutline.Thickness = 1.5
	bowspritOutline.Parent = bowsprit

	-- === STERN (back section — flat & wide) ===
	local stern = Instance.new("Frame")
	stern.Name = "Stern"
	stern.Size = UDim2.new(0.72, 0, 0.18, 0)
	stern.Position = UDim2.new(0.5, 0, 0.88, 0)
	stern.AnchorPoint = Vector2.new(0.5, 0.5)
	stern.BackgroundColor3 = colors.deck
	stern.BorderSizePixel = 0
	stern.ZIndex = 3
	stern.Parent = root

	local sternCorner = Instance.new("UICorner")
	sternCorner.CornerRadius = UDim.new(0.35, 0)
	sternCorner.Parent = stern

	local sternOutline = Instance.new("UIStroke")
	sternOutline.Color = Color3.fromRGB(15, 15, 25)
	sternOutline.Thickness = 2
	sternOutline.Parent = stern

	-- === DECK / SAIL (center — lighter colored area) ===
	local sail = Instance.new("Frame")
	sail.Name = "Deck"
	sail.Size = UDim2.new(0.42, 0, 0.28, 0)
	sail.Position = UDim2.new(0.5, 0, 0.46, 0)
	sail.AnchorPoint = Vector2.new(0.5, 0.5)
	sail.BackgroundColor3 = colors.sail
	sail.BorderSizePixel = 0
	sail.ZIndex = 5
	sail.Parent = root

	local sailCorner = Instance.new("UICorner")
	sailCorner.CornerRadius = UDim.new(0.25, 0)
	sailCorner.Parent = sail

	local sailOutline = Instance.new("UIStroke")
	sailOutline.Color = Color3.fromRGB(15, 15, 25)
	sailOutline.Thickness = 1.5
	sailOutline.Parent = sail

	-- Mast pole (thin vertical line through the sail)
	local mast = Instance.new("Frame")
	mast.Name = "Mast"
	mast.Size = UDim2.new(0.06, 0, 0.55, 0)
	mast.Position = UDim2.new(0.5, 0, 0.42, 0)
	mast.AnchorPoint = Vector2.new(0.5, 0.5)
	mast.BackgroundColor3 = Color3.fromRGB(90, 60, 35)
	mast.BorderSizePixel = 0
	mast.ZIndex = 4
	mast.Parent = root

	local mastCorner = Instance.new("UICorner")
	mastCorner.CornerRadius = UDim.new(0.5, 0)
	mastCorner.Parent = mast

	-- === CANNON BARRELS (chunky, stick out from the sides) ===
	for _, side in { "Left", "Right" } do
		local isLeft = (side == "Left")
		local xPos = if isLeft then 0.0 else 1.0

		-- Cannon barrel (dark rectangle protruding from hull)
		local barrel = Instance.new("Frame")
		barrel.Name = "Cannon" .. side
		barrel.Size = UDim2.new(0.28, 0, 0.09, 0)
		barrel.Position = UDim2.new(xPos, 0, 0.42, 0)
		barrel.AnchorPoint = Vector2.new(0.5, 0.5)
		barrel.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		barrel.BorderSizePixel = 0
		barrel.ZIndex = 4
		barrel.Parent = root

		local barrelCorner = Instance.new("UICorner")
		barrelCorner.CornerRadius = UDim.new(0.35, 0)
		barrelCorner.Parent = barrel

		local barrelOutline = Instance.new("UIStroke")
		barrelOutline.Color = Color3.fromRGB(15, 15, 25)
		barrelOutline.Thickness = 1.5
		barrelOutline.Parent = barrel

		-- Cannon mount (circular base where barrel meets hull)
		local mount = Instance.new("Frame")
		mount.Name = "CannonMount" .. side
		mount.Size = UDim2.new(0.14, 0, 0.1, 0)
		mount.Position = UDim2.new(if isLeft then 0.12 else 0.88, 0, 0.42, 0)
		mount.AnchorPoint = Vector2.new(0.5, 0.5)
		mount.BackgroundColor3 = Color3.fromRGB(70, 65, 55)
		mount.BorderSizePixel = 0
		mount.ZIndex = 5
		mount.Parent = root

		local mountCorner = Instance.new("UICorner")
		mountCorner.CornerRadius = UDim.new(1, 0)
		mountCorner.Parent = mount

		-- Second cannon pair (rear)
		local barrel2 = Instance.new("Frame")
		barrel2.Name = "Cannon" .. side .. "Rear"
		barrel2.Size = UDim2.new(0.24, 0, 0.07, 0)
		barrel2.Position = UDim2.new(xPos, 0, 0.62, 0)
		barrel2.AnchorPoint = Vector2.new(0.5, 0.5)
		barrel2.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		barrel2.BorderSizePixel = 0
		barrel2.ZIndex = 4
		barrel2.Parent = root

		local barrel2Corner = Instance.new("UICorner")
		barrel2Corner.CornerRadius = UDim.new(0.35, 0)
		barrel2Corner.Parent = barrel2

		local barrel2Outline = Instance.new("UIStroke")
		barrel2Outline.Color = Color3.fromRGB(15, 15, 25)
		barrel2Outline.Thickness = 1.5
		barrel2Outline.Parent = barrel2

		local mount2 = Instance.new("Frame")
		mount2.Name = "CannonMount" .. side .. "Rear"
		mount2.Size = UDim2.new(0.11, 0, 0.08, 0)
		mount2.Position = UDim2.new(if isLeft then 0.14 else 0.86, 0, 0.62, 0)
		mount2.AnchorPoint = Vector2.new(0.5, 0.5)
		mount2.BackgroundColor3 = Color3.fromRGB(70, 65, 55)
		mount2.BorderSizePixel = 0
		mount2.ZIndex = 5
		mount2.Parent = root

		local mount2Corner = Instance.new("UICorner")
		mount2Corner.CornerRadius = UDim.new(1, 0)
		mount2Corner.Parent = mount2
	end

	-- === DIRECTION INDICATOR (bright dot near bow) ===
	local indicator = Instance.new("Frame")
	indicator.Name = "DirectionDot"
	indicator.Size = UDim2.new(0.16, 0, 0.07, 0)
	indicator.Position = UDim2.new(0.5, 0, 0.22, 0)
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.BackgroundColor3 = colors.accent
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 6
	indicator.Parent = root

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(1, 0)
	indicatorCorner.Parent = indicator

	-- === FLAG (small colored pennant at the stern) ===
	local flag = Instance.new("Frame")
	flag.Name = "Flag"
	flag.Size = UDim2.new(0.18, 0, 0.1, 0)
	flag.Position = UDim2.new(0.5, 0, 0.95, 0)
	flag.AnchorPoint = Vector2.new(0.5, 0.5)
	flag.BackgroundColor3 = colors.accent
	flag.BorderSizePixel = 0
	flag.ZIndex = 6
	flag.Parent = root

	local flagCorner = Instance.new("UICorner")
	flagCorner.CornerRadius = UDim.new(0.3, 0)
	flagCorner.Parent = flag

	local flagOutline = Instance.new("UIStroke")
	flagOutline.Color = Color3.fromRGB(15, 15, 25)
	flagOutline.Thickness = 1
	flagOutline.Parent = flag

	return root
end

-- Helper to get a color index from a player's UserId
function ShipBuilder.getColorIndex(userId: number): number
	return (userId % #SHIP_COLORS) + 1
end

return ShipBuilder