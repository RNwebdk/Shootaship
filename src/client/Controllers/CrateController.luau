--[[
	CrateController (Client)
	========================
	Renders pickup crates on the game canvas:
	  1. Ammo crates (brown with cross) — from CrateSpawned
	  2. Power-up crates (9 types, unique colors/icons) — from PowerUpSpawned
	
	Both pop in when spawned and pop out when collected.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)
local ViewportController = require(script.Parent.ViewportController)

local CrateController = {}

-- Active crate visuals: crateId → { frame, position }
local crateVisuals = {}

-- Event listener connections (so we can disconnect on re-init)
local connections = {}

-- Power-up type visual config: { bgColor, strokeColor, icon, glowColor }
local POWERUP_VISUALS = {
	speed   = { Color3.fromRGB(30, 160, 60),   Color3.fromRGB(15, 100, 30),   "⚡", Color3.fromRGB(100, 255, 120) },
	damage  = { Color3.fromRGB(180, 40, 40),    Color3.fromRGB(120, 20, 20),   "🔥", Color3.fromRGB(255, 100, 100) },
	shield  = { Color3.fromRGB(40, 80, 200),    Color3.fromRGB(20, 40, 140),   "🛡", Color3.fromRGB(100, 150, 255) },
	scatter = { Color3.fromRGB(140, 40, 180),   Color3.fromRGB(80, 20, 120),   "*",  Color3.fromRGB(200, 120, 255) },
	repair  = { Color3.fromRGB(200, 180, 30),   Color3.fromRGB(140, 120, 15),  "❤",  Color3.fromRGB(255, 255, 100) },
	ghost   = { Color3.fromRGB(40, 190, 200),   Color3.fromRGB(20, 120, 130),  "👻", Color3.fromRGB(100, 240, 255) },
	ram     = { Color3.fromRGB(220, 120, 20),   Color3.fromRGB(150, 70, 10),   "💥", Color3.fromRGB(255, 180, 80) },
	ammodump= { Color3.fromRGB(200, 200, 210),  Color3.fromRGB(130, 130, 140), "📦", Color3.fromRGB(230, 230, 255) },
	homing  = { Color3.fromRGB(220, 80, 160),   Color3.fromRGB(150, 40, 100),  "🎯", Color3.fromRGB(255, 140, 200) },
	superbounce = { Color3.fromRGB(120, 230, 50), Color3.fromRGB(70, 150, 25), "💢", Color3.fromRGB(180, 255, 80) },
	mine = { Color3.fromRGB(120, 20, 20), Color3.fromRGB(80, 10, 10), "💣", Color3.fromRGB(255, 60, 60) },
}

function CrateController.init()
	-- Disconnect old listeners and clear old visuals (idempotent re-init)
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	CrateController.clear()

	local spawnEvent = EventManager.waitForEvent("CrateSpawned")
	local collectEvent = EventManager.waitForEvent("CrateCollected")
	local puSpawnEvent = EventManager.waitForEvent("PowerUpSpawned")
	local puCollectEvent = EventManager.waitForEvent("PowerUpCollected")
	
	table.insert(connections, spawnEvent.OnClientEvent:Connect(function(data)
		CrateController.onCrateSpawned(data)
	end))
	
	table.insert(connections, collectEvent.OnClientEvent:Connect(function(data)
		CrateController.onCrateCollected(data)
	end))
	
	table.insert(connections, puSpawnEvent.OnClientEvent:Connect(function(data)
		CrateController.onPowerUpSpawned(data)
	end))
	
	table.insert(connections, puCollectEvent.OnClientEvent:Connect(function(data)
		CrateController.onCrateCollected(data)  -- same pop-out animation
	end))
	
	print("[CrateController] Initialized")
end

--[[
	Creates an ammo crate visual (brown wooden box).
]]
function CrateController.onCrateSpawned(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	-- Prevent duplicate: destroy any existing visual with the same ID
	local existing = crateVisuals[data.id]
	if existing then
		existing.frame:Destroy()
		crateVisuals[data.id] = nil
	end
	
	local size = Constants.CRATE_SIZE
	local pos = Vector2.new(data.px, data.py)
	
	local crate = Instance.new("Frame")
	crate.Name = "Crate_" .. tostring(data.id)
	crate.Size = UDim2.new(0, size, 0, size)
	crate.AnchorPoint = Vector2.new(0.5, 0.5)
	crate.Position = ViewportController.worldToCanvas(pos)
	crate.BackgroundColor3 = Color3.fromRGB(160, 100, 40)
	crate.BorderSizePixel = 0
	crate.ZIndex = 3
	crate.Rotation = math.random(0, 45)
	crate.Parent = canvas
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = crate
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 55, 20)
	stroke.Thickness = 2
	stroke.Parent = crate
	
	-- Cross marking
	local hBar = Instance.new("Frame")
	hBar.Size = UDim2.new(0.6, 0, 0.15, 0)
	hBar.Position = UDim2.new(0.2, 0, 0.425, 0)
	hBar.BackgroundColor3 = Color3.fromRGB(220, 180, 80)
	hBar.BorderSizePixel = 0
	hBar.ZIndex = 4
	hBar.Parent = crate
	
	local vBar = Instance.new("Frame")
	vBar.Size = UDim2.new(0.15, 0, 0.6, 0)
	vBar.Position = UDim2.new(0.425, 0, 0.2, 0)
	vBar.BackgroundColor3 = Color3.fromRGB(220, 180, 80)
	vBar.BorderSizePixel = 0
	vBar.ZIndex = 4
	vBar.Parent = crate
	
	-- Pop-in animation
	crate.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(crate, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, size, 0, size),
	}):Play()
	
	crateVisuals[data.id] = { frame = crate, position = pos }
end

--[[
	Creates a power-up crate visual with type-specific color and icon.
]]
function CrateController.onPowerUpSpawned(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	-- Prevent duplicate: destroy any existing visual with the same ID
	local existing = crateVisuals[data.id]
	if existing then
		existing.frame:Destroy()
		crateVisuals[data.id] = nil
	end
	
	local size = Constants.CRATE_SIZE
	local pos = Vector2.new(data.px, data.py)
	local config = POWERUP_VISUALS[data.powerType] or POWERUP_VISUALS.speed
	local bgColor = config[1]
	local strokeColor = config[2]
	local icon = config[3]
	local glowColor = config[4]
	
	local crate = Instance.new("Frame")
	crate.Name = "Crate_" .. tostring(data.id)
	crate.Size = UDim2.new(0, size, 0, size)
	crate.AnchorPoint = Vector2.new(0.5, 0.5)
	crate.Position = ViewportController.worldToCanvas(pos)
	crate.BackgroundColor3 = bgColor
	crate.BorderSizePixel = 0
	crate.ZIndex = 3
	crate.Rotation = math.random(0, 45)
	crate.Parent = canvas
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = crate
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 2
	stroke.Parent = crate
	
	-- Icon label
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.TextSize = size * 0.65
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.ZIndex = 4
	iconLabel.Parent = crate
	
	-- Glow pulse
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.Color = glowColor
	glow.Thickness = 0
	glow.Parent = crate
	
	-- Pop-in animation
	crate.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(crate, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, size, 0, size),
	}):Play()
	
	-- Pulsing glow
	task.spawn(function()
		while crate and crate.Parent do
			TweenService:Create(glow, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Thickness = 4,
			}):Play()
			task.wait(0.6)
			if not crate or not crate.Parent then break end
			TweenService:Create(glow, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Thickness = 0,
			}):Play()
			task.wait(0.6)
		end
	end)
	
	crateVisuals[data.id] = { frame = crate, position = pos }
end

--[[
	Remove a collected crate/power-up with a pop-out animation.
]]
function CrateController.onCrateCollected(data)
	local id = data.crateId
	local visual = crateVisuals[id]
	
	if visual then
		crateVisuals[id] = nil
		
		-- Hide immediately so it's gone even if tween fails
		visual.frame.Visible = false
		
		local tween = TweenService:Create(visual.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			visual.frame:Destroy()
		end)
	else
		-- Fallback: search canvas by frame name (handles orphaned frames)
		local canvas = ViewportController.getCanvas()
		if canvas then
			local frameName = "Crate_" .. tostring(id)
			local orphan = canvas:FindFirstChild(frameName)
			if orphan then
				orphan:Destroy()
			end
		end
	end
end

function CrateController.update(_deltaTime: number)
	-- Crates are static on the canvas, no per-frame logic needed
end

function CrateController.clear()
	for _, visual in crateVisuals do
		visual.frame:Destroy()
	end
	table.clear(crateVisuals)
end

return CrateController
