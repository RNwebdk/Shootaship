--[[
	MineController (Client)
	=======================
	Renders naval mines on the game canvas.
	Mines appear as dark spiked circles that pulse/flash before exploding.
	Explosion VFX: expanding fireball ring.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)
local ViewportController = require(script.Parent.ViewportController)

local MineController = {}

-- Active mine visuals: mineId → { frame, position }
local mineVisuals = {}

function MineController.init()
	local deployEvent = EventManager.waitForEvent("MineDeployed")
	local explodeEvent = EventManager.waitForEvent("MineExploded")
	
	deployEvent.OnClientEvent:Connect(function(data)
		MineController.onMineDeployed(data)
	end)
	
	explodeEvent.OnClientEvent:Connect(function(data)
		MineController.onMineExploded(data)
	end)
	
	print("[MineController] Initialized")
end

function MineController.onMineDeployed(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	local size = Constants.MINE_SIZE
	local pos = Vector2.new(data.px, data.py)
	
	-- Main mine body (dark circle)
	local mine = Instance.new("Frame")
	mine.Name = "Mine_" .. tostring(data.id)
	mine.Size = UDim2.new(0, size, 0, size)
	mine.AnchorPoint = Vector2.new(0.5, 0.5)
	mine.Position = ViewportController.worldToCanvas(pos)
	mine.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
	mine.BorderSizePixel = 0
	mine.ZIndex = 3
	mine.Parent = canvas
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = mine
	
	-- Red danger stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(200, 30, 30)
	stroke.Thickness = 2
	stroke.Parent = mine
	
	-- Spike accents (4 small triangular prongs)
	for i = 0, 3 do
		local spike = Instance.new("Frame")
		spike.Size = UDim2.new(0, 6, 0, 6)
		spike.AnchorPoint = Vector2.new(0.5, 0.5)
		local angle = (i / 4) * math.pi * 2
		local offsetX = math.cos(angle) * (size * 0.55)
		local offsetY = math.sin(angle) * (size * 0.55)
		spike.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
		spike.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
		spike.BorderSizePixel = 0
		spike.Rotation = 45
		spike.ZIndex = 3
		spike.Parent = mine
	end
	
	-- Center dot (blinking red light)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	dot.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	dot.BorderSizePixel = 0
	dot.ZIndex = 4
	dot.Parent = mine
	
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	
	-- Pop-in animation
	mine.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(mine, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, size, 0, size),
	}):Play()
	
	mineVisuals[data.id] = {
		frame = mine,
		position = pos,
		dot = dot,
		age = 0,
	}
end

function MineController.onMineExploded(data)
	local visual = mineVisuals[data.id]
	
	if visual then
		visual.frame:Destroy()
		mineVisuals[data.id] = nil
	end
	
	-- Explosion VFX (unless it's a silent despawn)
	if not data.despawn then
		local canvas = ViewportController.getCanvas()
		if not canvas then return end
		
		local pos = Vector2.new(data.px, data.py)
		
		-- Fireball ring
		local ring = Instance.new("Frame")
		ring.Size = UDim2.new(0, 10, 0, 10)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = ViewportController.worldToCanvas(pos)
		ring.BackgroundColor3 = Color3.fromRGB(255, 80, 20)
		ring.BackgroundTransparency = 0.2
		ring.BorderSizePixel = 0
		ring.ZIndex = 10
		ring.Parent = canvas
		
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(1, 0)
		ringCorner.Parent = ring
		
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = Color3.fromRGB(255, 200, 50)
		ringStroke.Thickness = 4
		ringStroke.Parent = ring
		
		-- Expand and fade
		local expandSize = Constants.MINE_RADIUS * 2.5
		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, expandSize, 0, expandSize),
			BackgroundTransparency = 1,
		}):Play()
		
		TweenService:Create(ringStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 0,
			Transparency = 1,
		}):Play()
		
		task.delay(0.6, function()
			ring:Destroy()
		end)
	end
end

-- Update mine positions relative to camera + blink the red dot
function MineController.update(deltaTime: number)
	for id, visual in mineVisuals do
		visual.frame.Position = ViewportController.worldToCanvas(visual.position)
		
		-- Blink the red center dot
		visual.age = visual.age + deltaTime
		local blink = math.sin(visual.age * 6) > 0
		if visual.dot then
			visual.dot.BackgroundTransparency = blink and 0 or 0.7
		end
	end
end

return MineController
