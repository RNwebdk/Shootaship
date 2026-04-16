--[[
	ViewportController (Client)
	===========================
	Manages the 2D viewport — what portion of the game world is visible.
	
	Since this is a 2D GUI game (not 3D), there is no Roblox Camera.
	Instead, we have a ScreenGui with two layers:
	
	  ScreenGui (full screen)
	    └── GameCanvas (large Frame = the game world)
	         ├── Ocean background
	         ├── Ship frames (added by ShipController)
	         ├── Cannonball frames (added later)
	         └── Crate frames (added later)
	
	HOW VIEWPORT PANNING WORKS:
	  The GameCanvas is much larger than the screen (3000x3000 world units).
	  We shift the canvas Position so the local player's ship stays at
	  screen center. Think of it like a CSS div with overflow:hidden and
	  transform: translate().
	
	  Example: If your ship is at world (500, 200):
	    canvas.Position = screenCenter - Vector2(500, 200)
	    → Your ship appears at the center of the screen
	
	WHY this runs on the client:
	  Each player sees a different part of the map (centered on their ship).
	  The server doesn't care what you're looking at.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local ViewportController = {}

-- References to GUI objects (set during init)
local screenGui = nil   -- The ScreenGui container
local gameCanvas = nil  -- The large "world" frame that everything lives on

-- The world position the viewport is centered on (smoothly follows player)
local viewportCenter = Vector2.new(0, 0)

-- Camera lead offset (shifts viewport ahead of travel direction at speed)
local currentLead = Vector2.new(0, 0)

-- Smoothing speed for camera follow (higher = snappier, lower = floatier)
local FOLLOW_SPEED = 8

--[[
	Creates the ScreenGui and GameCanvas.
	
	ROBLOX GUI BASICS (for web devs):
	  - ScreenGui = the <body> of a fullscreen overlay
	  - Frame = a <div>
	  - UDim2 = like CSS with mixed units: UDim2.new(scaleX, offsetX, scaleY, offsetY)
	    - Scale: 0 to 1 = percentage of parent (like %)
	    - Offset: pixels (like px)
	  - AnchorPoint = transform-origin (0,0 = top-left, 0.5,0.5 = center)
]]
function ViewportController.init()
	local player = Players.LocalPlayer
	
	-- Create the ScreenGui (fullscreen overlay)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShootashipUI"
	screenGui.ResetOnSpawn = false            -- Don't destroy when player respawns
	screenGui.IgnoreGuiInset = true           -- Cover the entire screen (including top bar)
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui       -- PlayerGui is where client GUIs live
	
	-- Create the clipping viewport (the visible window)
	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.new(1, 0, 1, 0)    -- Full screen
	viewport.Position = UDim2.new(0, 0, 0, 0)
	viewport.BackgroundColor3 = Color3.fromRGB(20, 40, 70)  -- Deep ocean blue (visible at edges)
	viewport.ClipsDescendants = true          -- IMPORTANT: hides anything outside the viewport
	viewport.BorderSizePixel = 0
	viewport.Parent = screenGui
	
	-- Create the game canvas (the big "world" frame)
	-- This is larger than the screen. We'll move it around to "scroll" the view.
	gameCanvas = Instance.new("Frame")
	gameCanvas.Name = "GameCanvas"
	-- Size = map dimensions in pixels (at 1:1 scale)
	gameCanvas.Size = UDim2.new(0, Constants.MAP_WIDTH, 0, Constants.MAP_HEIGHT)
	gameCanvas.AnchorPoint = Vector2.new(0.5, 0.5) -- Center pivot point
	gameCanvas.Position = UDim2.new(0.5, 0, 0.5, 0) -- Start centered on screen
	gameCanvas.BackgroundColor3 = Color3.fromRGB(30, 90, 150) -- Dark edge color visible through tile gaps
	gameCanvas.BorderSizePixel = 0
	gameCanvas.Parent = viewport
	
	-- === LOW-POLY WATER BACKGROUND ===
	-- Flat-colored tiles with visible gaps between them.
	-- The dark gaps create the "edges" of the polygon facets.
	-- No gradients, no rotation — just simple flat colored tiles
	-- with a slightly darker base showing through the cracks.
	
	local cellSize = 70
	local gap = 2  -- px gap between tiles creates visible polygon edges
	
	-- Water layer — transparent container; dark canvas base shows through tile gaps
	local waterLayer = Instance.new("Frame")
	waterLayer.Name = "WaterLayer"
	waterLayer.Size = UDim2.new(1, 0, 1, 0)
	waterLayer.BackgroundTransparency = 1
	waterLayer.BorderSizePixel = 0
	waterLayer.ZIndex = 0
	waterLayer.Parent = gameCanvas
	
	-- Ocean blue palette — flat colors, no gradients
	local waterColors = {
		Color3.fromRGB(62, 152, 208),
		Color3.fromRGB(74, 164, 218),
		Color3.fromRGB(84, 174, 228),
		Color3.fromRGB(94, 184, 238),
		Color3.fromRGB(78, 168, 222),
		Color3.fromRGB(88, 178, 232),
		Color3.fromRGB(68, 158, 212),
		Color3.fromRGB(98, 188, 242),
	}
	local numColors = #waterColors
	
	local gridCols = math.ceil(Constants.MAP_WIDTH / cellSize) + 1
	local gridRows = math.ceil(Constants.MAP_HEIGHT / cellSize) + 1
	
	for row = 0, gridRows do
		for col = 0, gridCols do
			local ci = ((row * 7 + col * 13 + math.floor(row/2) * 3) % numColors) + 1
			
			local tile = Instance.new("Frame")
			tile.Name = "PT"
			tile.Size = UDim2.new(0, cellSize - gap, 0, cellSize - gap)
			tile.Position = UDim2.new(0, col * cellSize + gap/2, 0, row * cellSize + gap/2)
			tile.BackgroundColor3 = waterColors[ci]
			tile.BackgroundTransparency = 0
			tile.BorderSizePixel = 0
			tile.ZIndex = 0
			tile.Parent = waterLayer
		end
	end
	
	-- Subtle pulsing caustic highlights
	for _ = 1, 15 do
		local sz = math.random(40, 90)
		local caustic = Instance.new("Frame")
		caustic.Name = "Caustic"
		caustic.Size = UDim2.new(0, sz, 0, sz)
		caustic.Position = UDim2.new(0, math.random(0, Constants.MAP_WIDTH), 0, math.random(0, Constants.MAP_HEIGHT))
		caustic.AnchorPoint = Vector2.new(0.5, 0.5)
		caustic.BackgroundColor3 = Color3.fromRGB(130, 215, 255)
		caustic.BackgroundTransparency = 0.88
		caustic.Rotation = 45
		caustic.BorderSizePixel = 0
		caustic.ZIndex = 1
		caustic.Parent = gameCanvas
		
		TweenService:Create(caustic, TweenInfo.new(
			2 + math.random() * 3,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, true
		), {
			BackgroundTransparency = 0.96,
			Size = UDim2.new(0, sz + 15, 0, sz + 15),
		}):Play()
	end
	
	-- === PRO WORLD BORDER ===
	-- Thick animated glowing border around the map
	local borderThickness = 6
	local borderColor = Color3.fromRGB(40, 180, 255)
	local borderGlow = Color3.fromRGB(80, 200, 255)
	
	-- Inner border stroke (the main solid line)
	local innerBorder = Instance.new("UIStroke")
	innerBorder.Name = "BorderInner"
	innerBorder.Color = borderColor
	innerBorder.Thickness = borderThickness
	innerBorder.Transparency = 0.1
	innerBorder.Parent = gameCanvas
	
	-- Outer glow frames on each side
	local sides = {
		{ name = "Top",    pos = UDim2.new(0.5, 0, 0, 0),    size = UDim2.new(1, 20, 0, 14), anchor = Vector2.new(0.5, 0.5) },
		{ name = "Bottom", pos = UDim2.new(0.5, 0, 1, 0),    size = UDim2.new(1, 20, 0, 14), anchor = Vector2.new(0.5, 0.5) },
		{ name = "Left",   pos = UDim2.new(0, 0, 0.5, 0),    size = UDim2.new(0, 14, 1, 20), anchor = Vector2.new(0.5, 0.5) },
		{ name = "Right",  pos = UDim2.new(1, 0, 0.5, 0),    size = UDim2.new(0, 14, 1, 20), anchor = Vector2.new(0.5, 0.5) },
	}
	
	for _, side in sides do
		local glowBar = Instance.new("Frame")
		glowBar.Name = "BorderGlow_" .. side.name
		glowBar.Position = side.pos
		glowBar.Size = side.size
		glowBar.AnchorPoint = side.anchor
		glowBar.BackgroundColor3 = borderGlow
		glowBar.BackgroundTransparency = 0.6
		glowBar.BorderSizePixel = 0
		glowBar.ZIndex = 10
		glowBar.Parent = gameCanvas
		
		-- Pulsing glow animation
		TweenService:Create(glowBar, TweenInfo.new(
			1.5,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, -- loop forever
			true -- reverse
		), {
			BackgroundTransparency = 0.85,
		}):Play()
	end
	
	-- Corner accent dots (4 corners with a bright circle)
	local cornerPositions = {
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, 0, 0, 0),
		UDim2.new(0, 0, 1, 0),
		UDim2.new(1, 0, 1, 0),
	}
	for _, cPos in cornerPositions do
		local dot = Instance.new("Frame")
		dot.Name = "CornerDot"
		dot.Size = UDim2.new(0, 20, 0, 20)
		dot.Position = cPos
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.BackgroundColor3 = Color3.fromRGB(100, 220, 255)
		dot.BackgroundTransparency = 0.3
		dot.BorderSizePixel = 0
		dot.ZIndex = 11
		dot.Parent = gameCanvas
		
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot
		
		TweenService:Create(dot, TweenInfo.new(
			2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		), {
			BackgroundTransparency = 0.7,
			Size = UDim2.new(0, 14, 0, 14),
		}):Play()
	end
	
	print("[ViewportController] Initialized — canvas:", Constants.MAP_WIDTH, "x", Constants.MAP_HEIGHT)
end

--[[
	Updates the viewport to follow a target position.
	Called by the client init script every render frame.
	
	HOW THE MATH WORKS:
	  World origin (0,0) is at the CENTER of the canvas.
	  GUI origin (0,0) is at the center of the canvas (due to AnchorPoint 0.5, 0.5).
	  
	  To center the view on a ship at world position (px, py):
	    canvas.Position = UDim2.new(0.5, -px, 0.5, -py)
	  
	  This shifts the canvas so that world point (px, py) aligns with screen center.
]]
function ViewportController.update(deltaTime: number)
	if not gameCanvas then return end
	
	-- Smooth follow: lerp toward target (prevents jarring jumps)
	local t = math.min(1, FOLLOW_SPEED * deltaTime)
	local targetPos = ViewportController.targetPosition or Vector2.new(0, 0)
	
	-- Camera lead: shift viewport ahead in the travel direction at high speed
	local vel = ViewportController.targetVelocity or Vector2.new(0, 0)
	local speed = vel.Magnitude
	local maxSpd = Constants.SHIP_MAX_SPEED
	local speedFrac = math.clamp(speed / maxSpd, 0, 1)
	local targetLead = Vector2.new(0, 0)
	if speed > 10 then
		targetLead = vel.Unit * speedFrac * Constants.CAMERA_LEAD_AMOUNT
	end
	local leadT = math.min(1, Constants.CAMERA_LEAD_SPEED * deltaTime)
	currentLead = currentLead:Lerp(targetLead, leadT)
	
	viewportCenter = viewportCenter:Lerp(targetPos + currentLead, t)
	
	gameCanvas.Position = UDim2.new(0.5, -viewportCenter.X, 0.5, -viewportCenter.Y)
end

-- The target position to follow (set by ShipController when it gets updates)
ViewportController.targetPosition = Vector2.new(0, 0)
ViewportController.targetVelocity = Vector2.new(0, 0)

-- Expose the canvas so other controllers can add children to it
function ViewportController.getCanvas(): Frame
	return gameCanvas
end

-- Convert world coordinates to position on the canvas
-- Since canvas origin is top-left but world origin is center:
--   canvasX = worldX + MAP_WIDTH/2
--   canvasY = worldY + MAP_HEIGHT/2
function ViewportController.worldToCanvas(worldPos: Vector2): UDim2
	local canvasX = worldPos.X + Constants.MAP_WIDTH / 2
	local canvasY = worldPos.Y + Constants.MAP_HEIGHT / 2
	return UDim2.new(0, canvasX, 0, canvasY)
end

return ViewportController
