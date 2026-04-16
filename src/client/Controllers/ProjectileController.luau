--[[
	ProjectileController (Client)
	==============================
	Renders cannonball projectiles as GUI circles on the game canvas.
	
	The server fires "CannonFired" with position + velocity data.
	We create a circle Frame and move it each frame using velocity.
	After CANNONBALL_LIFETIME the projectile is removed.
	
	We also listen for "ShipDamaged" to flash the hit ship and
	"ShipDestroyed" to play a sink animation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)
local ViewportController = require(script.Parent.ViewportController)

local localPlayer = Players.LocalPlayer

local ProjectileController = {}

--[[
	Active projectile visuals.
	Each entry: {
	  id:       number   -- matches server projectile ID
	  frame:    Frame    -- the GUI circle
	  position: Vector2  -- world position
	  velocity: Vector2  -- world units/sec
	  age:      number   -- seconds alive
	}
]]
local projectiles = {}

function ProjectileController.init()
	local cannonFiredEvent = EventManager.waitForEvent("CannonFired")
	local shipDamagedEvent = EventManager.waitForEvent("ShipDamaged")
	local shipDestroyedEvent = EventManager.waitForEvent("ShipDestroyed")
	
	-- When the server says a cannon was fired, create the visual
	cannonFiredEvent.OnClientEvent:Connect(function(data)
		-- Projectile-vs-projectile explosion: just show VFX
		if data.exploded then
			ProjectileController.onProjectileExploded(data)
			return
		end
		-- Reflected projectile: update existing visual instead of creating new one
		if data.reflected then
			ProjectileController.onProjectileReflected(data)
			return
		end
		ProjectileController.onCannonFired(data)
	end)
	
	-- Flash the ship red on damage
	shipDamagedEvent.OnClientEvent:Connect(function(data)
		ProjectileController.onShipDamaged(data)
	end)
	
	-- Sink animation on destroy
	shipDestroyedEvent.OnClientEvent:Connect(function(data)
		ProjectileController.onShipDestroyed(data)
	end)
	
	print("[ProjectileController] Initialized — spacebar to fire")
end

--[[
	Creates a cannonball visual on the canvas with a cartoon style.
]]
function ProjectileController.onCannonFired(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end

	local size = Constants.CANNONBALL_SIZE * 2  -- diameter
	local isBoosted = data.boosted == true
	
	-- Main ball — solid dark normally, fiery red when boosted
	local ball = Instance.new("Frame")
	ball.Name = "Cannonball_" .. tostring(data.id)
	ball.Size = UDim2.new(0, size, 0, size)
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	ball.BackgroundColor3 = if isBoosted then Color3.fromRGB(200, 30, 15) else Color3.fromRGB(15, 15, 15)
	ball.BorderSizePixel = 0
	ball.ZIndex = 5
	ball.Parent = canvas
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ball
	
	-- Cartoon shine highlight (small white circle in top-left)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(0, size * 0.35, 0, size * 0.35)
	shine.Position = UDim2.new(0.2, 0, 0.15, 0)
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.BackgroundColor3 = if isBoosted then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.4
	shine.BorderSizePixel = 0
	shine.ZIndex = 6
	shine.Parent = ball
	
	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(1, 0)
	shineCorner.Parent = shine
	
	-- Glow behind the ball (larger, transparent) — orange-red when boosted
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.Size = UDim2.new(0, size * 2, 0, size * 2)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundColor3 = if isBoosted then Color3.fromRGB(255, 100, 20) else Color3.fromRGB(30, 30, 30)
	glow.BackgroundTransparency = if isBoosted then 0.55 else 0.75
	glow.BorderSizePixel = 0
	glow.ZIndex = 4
	glow.Parent = ball
	
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow
	
	local pos = Vector2.new(data.px, data.py)
	ball.Position = ViewportController.worldToCanvas(pos)
	
	-- === MUZZLE FLASH VFX ===
	local flashSize = size * 3
	local flash = Instance.new("Frame")
	flash.Name = "MuzzleFlash"
	flash.Size = UDim2.new(0, flashSize, 0, flashSize)
	flash.Position = ViewportController.worldToCanvas(pos)
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.BackgroundColor3 = if isBoosted then Color3.fromRGB(255, 80, 30) else Color3.fromRGB(255, 220, 100)
	flash.BackgroundTransparency = 0.3
	flash.BorderSizePixel = 0
	flash.ZIndex = 6
	flash.Parent = canvas
	
	local flashCorner = Instance.new("UICorner")
	flashCorner.CornerRadius = UDim.new(1, 0)
	flashCorner.Parent = flash
	
	-- Flash expands and fades
	TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, flashSize * 2, 0, flashSize * 2),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.3, function()
		if flash and flash.Parent then flash:Destroy() end
	end)
	
	-- Smoke puff particles (3-5 tiny circles)
	for _ = 1, 4 do
		local puff = Instance.new("Frame")
		puff.Size = UDim2.new(0, math.random(4, 8), 0, math.random(4, 8))
		puff.Position = ViewportController.worldToCanvas(pos)
		puff.AnchorPoint = Vector2.new(0.5, 0.5)
		puff.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		puff.BackgroundTransparency = 0.4
		puff.BorderSizePixel = 0
		puff.ZIndex = 6
		puff.Parent = canvas
		
		local puffCorner = Instance.new("UICorner")
		puffCorner.CornerRadius = UDim.new(1, 0)
		puffCorner.Parent = puff
		
		local angle = math.random() * math.pi * 2
		local dist = math.random(15, 35)
		local ox = math.cos(angle) * dist
		local oy = math.sin(angle) * dist
		
		TweenService:Create(puff, TweenInfo.new(0.4 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = ViewportController.worldToCanvas(pos) + UDim2.new(0, ox, 0, oy),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 2, 0, 2),
		}):Play()
		task.delay(0.7, function()
			if puff and puff.Parent then puff:Destroy() end
		end)
	end
	
	table.insert(projectiles, {
		id = data.id,
		frame = ball,
		position = pos,
		velocity = Vector2.new(data.vx, data.vy),
		age = 0,
	})
end

--[[
	When a projectile is reflected by a block/shockwave, update its
	position and velocity so it visually reverses direction.
]]
function ProjectileController.onProjectileReflected(data)
	for _, proj in projectiles do
		if proj.id == data.id then
			proj.position = Vector2.new(data.px, data.py)
			proj.velocity = Vector2.new(data.vx, data.vy)
			proj.age = 0  -- reset age to match server
			-- Flash the ball cyan briefly to show it was reflected
			if proj.frame then
				proj.frame.BackgroundColor3 = Color3.fromRGB(100, 255, 255)
				task.delay(0.2, function()
					if proj.frame and proj.frame.Parent then
						proj.frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
					end
				end)
			end
			return
		end
	end
end

--[[
	When two projectiles collide, show an explosion at their midpoint.
]]
function ProjectileController.onProjectileExploded(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	local pos = Vector2.new(data.px, data.py)
	local canvasPos = ViewportController.worldToCanvas(pos)
	
	-- Bright flash
	local flash = Instance.new("Frame")
	flash.Name = "ProjExplosion"
	flash.Size = UDim2.new(0, 30, 0, 30)
	flash.Position = canvasPos
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	flash.BackgroundTransparency = 0
	flash.BorderSizePixel = 0
	flash.ZIndex = 8
	flash.Parent = canvas
	
	local flashCorner = Instance.new("UICorner")
	flashCorner.CornerRadius = UDim.new(1, 0)
	flashCorner.Parent = flash
	
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 60, 0, 60),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.35, function()
		if flash and flash.Parent then flash:Destroy() end
	end)
	
	-- Spark particles
	for _ = 1, 6 do
		local spark = Instance.new("Frame")
		spark.Size = UDim2.new(0, math.random(3, 6), 0, math.random(3, 6))
		spark.Position = canvasPos
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.BackgroundColor3 = Color3.fromRGB(
			255,
			math.random(140, 220),
			math.random(20, 80)
		)
		spark.BackgroundTransparency = 0
		spark.BorderSizePixel = 0
		spark.ZIndex = 8
		spark.Parent = canvas
		
		local sparkCorner = Instance.new("UICorner")
		sparkCorner.CornerRadius = UDim.new(1, 0)
		sparkCorner.Parent = spark
		
		local angle = math.random() * math.pi * 2
		local dist = math.random(20, 50)
		local ox = math.cos(angle) * dist
		local oy = math.sin(angle) * dist
		
		TweenService:Create(spark, TweenInfo.new(0.3 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = canvasPos + UDim2.new(0, ox, 0, oy),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 1, 0, 1),
		}):Play()
		task.delay(0.6, function()
			if spark and spark.Parent then spark:Destroy() end
		end)
	end
	
	-- Also remove any client-side projectiles near this point (cleanup)
	local explodePos = pos
	for idx = #projectiles, 1, -1 do
		local p = projectiles[idx]
		if (p.position - explodePos).Magnitude < Constants.CANNONBALL_SIZE * 3 then
			p.frame:Destroy()
			table.remove(projectiles, idx)
		end
	end
end

--[[
	Update all projectile positions each frame.
	Matches the server's movement so visuals line up with hit detection.
]]
function ProjectileController.update(deltaTime: number)
	local i = #projectiles
	while i >= 1 do
		local proj = projectiles[i]
		proj.age = proj.age + deltaTime
		
		-- Remove expired projectiles
		if proj.age >= Constants.CANNONBALL_LIFETIME then
			proj.frame:Destroy()
			table.remove(projectiles, i)
			i = i - 1
			continue
		end
		
		-- Move
		proj.position = proj.position + (proj.velocity * deltaTime)
		proj.frame.Position = ViewportController.worldToCanvas(proj.position)
		
		-- Fade slightly near end of life
		local remaining = Constants.CANNONBALL_LIFETIME - proj.age
		if remaining < 0.3 then
			proj.frame.BackgroundTransparency = 1 - (remaining / 0.3)
		end
		
		i = i - 1
	end
end

--[[
	Flash the damaged ship red briefly.
]]
function ProjectileController.onShipDamaged(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	-- Find the ship frame on the canvas
	local shipFrame = canvas:FindFirstChild("Ship_" .. tostring(data.targetId))
		or canvas:FindFirstChild("LocalShip")
	
	if not shipFrame then return end
	
	-- Flash red then restore
	-- We'll tint the hull frame (first child that is a Frame)
	local hull = shipFrame:FindFirstChildWhichIsA("Frame")
	if not hull then return end
	
	-- Store the true original color once (avoid capturing red from overlapping flashes)
	if not hull:GetAttribute("OriginalColor") then
		hull:SetAttribute("OriginalColor", hull.BackgroundColor3:ToHex())
	end
	local originalHex = hull:GetAttribute("OriginalColor")
	
	hull.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	
	task.delay(0.15, function()
		if hull and hull.Parent then
			hull.BackgroundColor3 = Color3.fromHex(originalHex)
		end
	end)
end

--[[
	Play a simple "sink" effect — shrink and fade the ship.
	The server will remove the ship from state sync, so ShipController
	will clean up the frame. We just do a quick visual.
]]
function ProjectileController.onShipDestroyed(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	local targetName = "Ship_" .. tostring(data.targetId)
	if data.targetId == localPlayer.UserId then
		targetName = "LocalShip"
	end
	
	local shipFrame = canvas:FindFirstChild(targetName)
	if not shipFrame then return end
	
	-- Tag frame as dying so ShipController doesn't restore it
	shipFrame:SetAttribute("Dying", true)
	
	-- Play death sound
	local deathSound = Instance.new("Sound")
	deathSound.SoundId = "rbxasset://sounds/impact_water.mp3"
	deathSound.Volume = 0.5
	deathSound.PlaybackSpeed = 0.5
	deathSound.Parent = SoundService
	deathSound:Play()
	deathSound.Ended:Once(function()
		deathSound:Destroy()
	end)
	
	-- Shrink + spin + fade the ship directly (no clone needed)
	local tweenService = game:GetService("TweenService")
	local tween = tweenService:Create(shipFrame, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 4, 0, 4),
		Rotation = shipFrame.Rotation + 360,
	})
	tween:Play()
	
	-- Fade all child frames
	for _, child in shipFrame:GetChildren() do
		if child:IsA("Frame") then
			tweenService:Create(child, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}):Play()
		end
	end
	
	-- After animation completes, hide the frame
	tween.Completed:Connect(function()
		shipFrame.Visible = false
	end)
end

-- Clean up all projectiles (for round reset)
function ProjectileController.clear()
	for _, proj in projectiles do
		proj.frame:Destroy()
	end
	table.clear(projectiles)
end

return ProjectileController
