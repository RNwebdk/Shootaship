--[[
	ShipController (Client)
	=======================
	Handles the client-side visual representation of all ships as GUI elements.
	
	Since this is a 2D GUI game, each ship is a Frame (polygon shape)
	placed on the game canvas. The server sends us position/rotation data
	and we render it as rotated/positioned GUI elements.
	
	KEY CONCEPTS:
	
	1. SERVER STATE vs VISUAL STATE
	   - Server sends positions 20x/sec (SYNC_RATE)
	   - Screen refreshes 60x/sec
	   - We INTERPOLATE between updates to fill the gaps
	
	2. INTERPOLATION (smoothing)
	   - When we receive a server update, we don't snap to it instantly
	   - We smoothly blend from current visual position to the new target
	   - This makes movement look fluid despite 20fps network updates
	
	3. LOCAL PLAYER PREDICTION (future improvement)
	   - For now, even the local player's ship uses server positions
	   - In a later phase, we could predict movement locally for responsiveness
	
	ANALOGY:
	  Like optimistic UI in React — show what you think will happen,
	  then reconcile when the server confirms.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)
local ViewportController = require(script.Parent.ViewportController)
local ShipBuilder = require(script.Parent.ShipBuilder)
local WakeEffect = require(script.Parent.WakeEffect)
local AmmoHUD = require(script.Parent.AmmoHUD)
local HealthHUD = require(script.Parent.HealthHUD)
local KillsHUD = require(script.Parent.KillsHUD)
local Leaderboard = require(script.Parent.Leaderboard)

local ShipController = {}

-- Pre-built sound objects for bounce effects
local function playBounceSound(pitch, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_water.mp3"
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1.2
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

--[[
	Tracks all ship visuals on screen.
	
	Key: userId (number)
	Value: {
	  frame:      Frame       -- the GUI element on the canvas
	  targetPos:  Vector2     -- latest server position (what we're interpolating toward)
	  targetRot:  number      -- latest server rotation
	  targetVel:  Vector2     -- latest server velocity (for extrapolation)
	  currentPos: Vector2     -- current visual position (what's on screen right now)
	  currentRot: number      -- current visual rotation
	  health:     number      -- for health bar (Phase 5)
	}
]]
local shipVisuals = {}

-- Speed line particles (streaks that appear at high speed for the local player)
local speedLines = {}  -- active speed line Frame objects
local MAX_SPEED_LINES = 12
local SPEED_LINE_SPAWN_TIMER = 0

-- How fast visuals catch up to server state (higher = snappier, lower = smoother)
local LERP_SPEED = 15

local localPlayer = Players.LocalPlayer

function ShipController.init()
	-- Listen for ship state sync from the server
	local syncEvent = EventManager.waitForEvent("ShipStateSync")
	
	--[[
		OnClientEvent fires when the server calls :FireAllClients().
		stateData is a table like:
		{
		  [userId] = { px=100, py=200, vx=10, vy=-5, r=1.2, hp=80 },
		  [userId2] = { ... },
		}
	]]
	syncEvent.OnClientEvent:Connect(function(stateData)
		ShipController.onStateSync(stateData)
	end)
	
	-- Listen for player spawn confirmation
	local spawnEvent = EventManager.waitForEvent("PlayerSpawned")
	spawnEvent.OnClientEvent:Connect(function(data)
		print("[ShipController] Our ship spawned at", data.position.x, data.position.y)
	end)
	
	-- Listen for wall bounces (play VFX)
	local bounceEvent = EventManager.waitForEvent("ShipBounced")
	bounceEvent.OnClientEvent:Connect(function(data)
		ShipController.onShipBounced(data)
	end)
	
	-- Listen for block/shockwave activation (play VFX)
	local blockActivatedEvent = EventManager.waitForEvent("BlockActivated")
	blockActivatedEvent.OnClientEvent:Connect(function(data)
		ShipController.onBlockActivated(data)
	end)
	
	print("[ShipController] Initialized — waiting for ship state sync")
end

--[[
	Plays a shockwave ring + burst when a ship activates block/reflect.
]]
function ShipController.onBlockActivated(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	local worldPos = Vector2.new(data.px, data.py)
	local canvasPos = ViewportController.worldToCanvas(worldPos)
	
	-- Play a sound for the shockwave
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_water.mp3"
	sound.Volume = 0.8
	sound.PlaybackSpeed = 2.0  -- high pitch whoosh
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	
	-- === SHOCKWAVE RING (cyan/white, expands to BLOCK_RADIUS) ===
	local ring = Instance.new("Frame")
	ring.Name = "BlockRing"
	ring.Size = UDim2.new(0, 20, 0, 20)
	ring.Position = canvasPos
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 8
	ring.Parent = canvas
	
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(100, 255, 255)
	ringStroke.Thickness = 5
	ringStroke.Transparency = 0
	ringStroke.Parent = ring
	
	-- Expand to match BLOCK_RADIUS and fade
	local targetSize = Constants.BLOCK_RADIUS * 2
	local expandTween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, targetSize, 0, targetSize),
	})
	local fadeTween = TweenService:Create(ringStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Thickness = 1,
	})
	expandTween:Play()
	fadeTween:Play()
	expandTween.Completed:Connect(function()
		ring:Destroy()
	end)
	
	-- === INNER FLASH (bright circle that fades quickly) ===
	local flash = Instance.new("Frame")
	flash.Name = "BlockFlash"
	flash.Size = UDim2.new(0, 50, 0, 50)
	flash.Position = canvasPos
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.BackgroundColor3 = Color3.fromRGB(180, 255, 255)
	flash.BackgroundTransparency = 0.3
	flash.BorderSizePixel = 0
	flash.ZIndex = 7
	flash.Parent = canvas
	
	local flashCorner = Instance.new("UICorner")
	flashCorner.CornerRadius = UDim.new(1, 0)
	flashCorner.Parent = flash
	
	local flashTween = TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 100, 0, 100),
		BackgroundTransparency = 1,
	})
	flashTween:Play()
	flashTween.Completed:Connect(function()
		flash:Destroy()
	end)
end

--[[
	Plays a shockwave ring + splash particles when a ship bounces off a wall.
]]
function ShipController.onShipBounced(data)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	local worldPos = Vector2.new(data.px, data.py)
	local canvasPos = ViewportController.worldToCanvas(worldPos)
	local normalX = data.nx or 0
	local normalY = data.ny or 0
	
	-- Play bounce sound (higher pitch for ship-to-ship, lower for walls)
	local isShipCollision = data.shipCollision
	if isShipCollision then
		playBounceSound(1.6, 0.7)  -- higher pitch thud for ship hits
	else
		playBounceSound(0.9, 0.8)  -- deep splash for wall bounces
	end
	
	-- === SHOCKWAVE RING ===
	local ring = Instance.new("Frame")
	ring.Name = "BounceRing"
	ring.Size = UDim2.new(0, 10, 0, 10)
	ring.Position = canvasPos
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 7
	ring.Parent = canvas
	
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(180, 220, 255)
	ringStroke.Thickness = 4
	ringStroke.Transparency = 0
	ringStroke.Parent = ring
	
	-- Expand and fade
	local expandTween = TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 120, 0, 120),
	})
	local fadeTween = TweenService:Create(ringStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Thickness = 1,
	})
	expandTween:Play()
	fadeTween:Play()
	expandTween.Completed:Connect(function()
		ring:Destroy()
	end)
	
	-- === SPLASH PARTICLES (spray away from wall) ===
	for _ = 1, 8 do
		local particle = Instance.new("Frame")
		particle.Size = UDim2.new(0, math.random(4, 8), 0, math.random(4, 8))
		particle.Position = canvasPos
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.BackgroundColor3 = Color3.fromRGB(
			180 + math.random(0, 75),
			220 + math.random(0, 35),
			255
		)
		particle.BackgroundTransparency = 0.2
		particle.BorderSizePixel = 0
		particle.ZIndex = 7
		particle.Rotation = math.random(0, 360)
		particle.Parent = canvas
		
		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(1, 0)
		pCorner.Parent = particle
		
		-- Spray in the direction of the bounce normal with some random spread
		local spreadAngle = (math.random() - 0.5) * 1.8  -- ~±51° spread
		local baseAngle = math.atan2(normalY, normalX)
		local angle = baseAngle + spreadAngle
		local dist = math.random(40, 100)
		local offsetX = math.cos(angle) * dist
		local offsetY = math.sin(angle) * dist
		
		local pTween = TweenService:Create(particle, TweenInfo.new(0.4 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = canvasPos + UDim2.new(0, offsetX, 0, offsetY),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 2, 0, 2),
		})
		pTween:Play()
		pTween.Completed:Connect(function()
			particle:Destroy()
		end)
	end
end

--[[
	Called when server sends new ship positions.
	
	This does three things:
	  1. Creates GUI elements for NEW ships we haven't seen before
	  2. Updates target positions for EXISTING ships
	  3. Removes GUI elements for ships that DISCONNECTED
]]
function ShipController.onStateSync(stateData)
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	
	-- Track which ships are still active (for cleanup)
	local activeUserIds = {}
	
	for userIdStr, data in stateData do
		local userId = tonumber(userIdStr) or userIdStr
		activeUserIds[userId] = true
		
		-- Create visual if we haven't seen this ship before
		if not shipVisuals[userId] then
			local colorIndex = ShipBuilder.getColorIndex(userId)
			local shipFrame = ShipBuilder.createShip(colorIndex)
			shipFrame.Parent = canvas
			
			shipFrame.ZIndex = 3  -- Above wake particles (ZIndex 2) and water tiles (ZIndex 0)
			
			-- Mark the local player's ship differently
			if userId == localPlayer.UserId then
				shipFrame.Name = "LocalShip"
			else
				shipFrame.Name = "Ship_" .. tostring(userId)
			end
			
			-- Create health bar (parented to ship so it moves with it)
			local hpBarContainer = Instance.new("Frame")
			hpBarContainer.Name = "HPBar"
			hpBarContainer.Size = UDim2.new(0, 44, 0, 6)
			hpBarContainer.Position = UDim2.new(0.5, 0, 0, -10)  -- above ship
			hpBarContainer.AnchorPoint = Vector2.new(0.5, 1)
			hpBarContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			hpBarContainer.BackgroundTransparency = 0.3
			hpBarContainer.BorderSizePixel = 0
			hpBarContainer.ZIndex = 8
			hpBarContainer.Parent = shipFrame

			local hpCorner = Instance.new("UICorner")
			hpCorner.CornerRadius = UDim.new(0, 2)
			hpCorner.Parent = hpBarContainer

			local hpFill = Instance.new("Frame")
			hpFill.Name = "Fill"
			hpFill.Size = UDim2.new(1, 0, 1, 0)
			hpFill.Position = UDim2.new(0, 0, 0, 0)
			hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
			hpFill.BorderSizePixel = 0
			hpFill.ZIndex = 9
			hpFill.Parent = hpBarContainer

			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0, 2)
			fillCorner.Parent = hpFill

			shipVisuals[userId] = {
				frame = shipFrame,
				hpBar = hpBarContainer,
				hpFill = hpFill,
				targetPos = Vector2.new(data.px, data.py),
				targetRot = data.r,
				targetVel = Vector2.new(data.vx, data.vy),
				currentPos = Vector2.new(data.px, data.py),
				currentRot = data.r,
				health = data.hp,
				ammo = data.ammo,
			}
			
			-- Position the frame immediately (no interpolation on first appearance)
			shipFrame.Position = ViewportController.worldToCanvas(Vector2.new(data.px, data.py))
			shipFrame.Rotation = math.deg(data.r)
			
			print("[ShipController] Created ship visual for userId:", userId)
		else
			-- Update target for existing ship (interpolation will handle the rest)
			local visual = shipVisuals[userId]
			visual.targetPos = Vector2.new(data.px, data.py)
			visual.targetRot = data.r
			visual.targetVel = Vector2.new(data.vx, data.vy)
			visual.health = data.hp
			visual.ammo = data.ammo
			-- Restore visibility after respawn (sink animation hides it)
			if not visual.frame.Visible and not visual.frame:GetAttribute("Dying") then
				visual.frame.Visible = true
				visual.frame.Size = UDim2.new(0, Constants.SHIP_SIZE.X, 0, Constants.SHIP_SIZE.Y)
			end
			-- Store all power-up states
			visual.boost = data.boost
			visual.dmgBoost = data.dmgBoost
			visual.shield = data.shield
			visual.scatter = data.scatter
			visual.ghost = data.ghost
			visual.ram = data.ram
			visual.homing = data.homing
			visual.sBounce = data.sBounce
			visual.mines = data.mines
			visual.kills = data.kills
			visual.dashCd = data.dashCd
			visual.block = data.block
			visual.blockCd = data.blockCd
		end
	end
	
	-- Remove ships that are no longer in the state (player left)
	for userId, visual in shipVisuals do
		if not activeUserIds[userId] then
			visual.frame:Destroy()
			shipVisuals[userId] = nil
		end
	end

	-- Update leaderboard with all player scores
	Leaderboard.updateScores(stateData)
end

--[[
	Render tick — called every frame (~60fps) by the client init script.
	
	Smoothly interpolates each ship's visual position toward its
	server-authoritative target position. This fills the gaps between
	the 20fps server updates to make everything look silky smooth.
]]
function ShipController.update(deltaTime: number)
	local t = math.min(1, LERP_SPEED * deltaTime)  -- Blend factor (0 to 1)
	local canvas = ViewportController.getCanvas()
	
	for userId, visual in shipVisuals do
		-- Lerp position toward target
		visual.currentPos = visual.currentPos:Lerp(visual.targetPos, t)
		
		-- Lerp rotation toward target (handle angle wrapping)
		local rotDiff = visual.targetRot - visual.currentRot
		-- Normalize to [-pi, pi] to take the shortest rotation path
		rotDiff = math.atan2(math.sin(rotDiff), math.cos(rotDiff))
		-- Snap faster for large rotation changes (e.g. wall bounces)
		local rotT = if math.abs(rotDiff) > 1 then math.min(1, LERP_SPEED * 3 * deltaTime) else t
		visual.currentRot = visual.currentRot + rotDiff * rotT
		
		-- Update GUI element
		visual.frame.Position = ViewportController.worldToCanvas(visual.currentPos)
		visual.frame.Rotation = math.deg(visual.currentRot)
		
		-- Apply power-up visual effects to ship frame
		-- Ghost: semi-transparent (only affect child frames, NOT the root container)
		local ghostAlpha = (visual.ghost and visual.ghost > 0) and 0.6 or 0
		for _, child in visual.frame:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundTransparency = ghostAlpha
			end
		end
		
		-- Shield: blue glow outline / Ram: orange glow outline
		local effectStroke = visual.frame:FindFirstChild("EffectStroke")
		if visual.shield and visual.shield > 0 then
			if not effectStroke then
				effectStroke = Instance.new("UIStroke")
				effectStroke.Name = "EffectStroke"
				effectStroke.Parent = visual.frame
			end
			effectStroke.Color = Color3.fromRGB(80, 150, 255)
			effectStroke.Thickness = 3
			effectStroke.Transparency = 0
		elseif visual.ram and visual.ram > 0 then
			if not effectStroke then
				effectStroke = Instance.new("UIStroke")
				effectStroke.Name = "EffectStroke"
				effectStroke.Parent = visual.frame
			end
			effectStroke.Color = Color3.fromRGB(255, 160, 40)
			effectStroke.Thickness = 3
			effectStroke.Transparency = 0
		elseif visual.dmgBoost and visual.dmgBoost > 0 then
			if not effectStroke then
				effectStroke = Instance.new("UIStroke")
				effectStroke.Name = "EffectStroke"
				effectStroke.Parent = visual.frame
			end
			effectStroke.Color = Color3.fromRGB(255, 60, 60)
			effectStroke.Thickness = 2
			effectStroke.Transparency = 0
		elseif visual.block and visual.block > 0 then
			if not effectStroke then
				effectStroke = Instance.new("UIStroke")
				effectStroke.Name = "EffectStroke"
				effectStroke.Parent = visual.frame
			end
			effectStroke.Color = Color3.fromRGB(100, 255, 255)
			effectStroke.Thickness = 4
			effectStroke.Transparency = 0
		else
			if effectStroke then
				effectStroke.Transparency = 1
			end
		end
		
		-- Update per-ship health bar (all ships, including local player)
		if visual.hpFill and visual.hpBar then
			local hpFrac = math.clamp((visual.health or 0) / Constants.SHIP_MAX_HEALTH, 0, 1)
			visual.hpFill.Size = UDim2.new(hpFrac, 0, 1, 0)

			-- Green → Yellow → Red gradient based on HP
			if hpFrac > 0.5 then
				local t2 = (hpFrac - 0.5) * 2  -- 1 at full, 0 at half
				visual.hpFill.BackgroundColor3 = Color3.fromRGB(
					math.floor(220 * (1 - t2)),
					220,
					80
				)
			else
				local t2 = hpFrac * 2  -- 1 at half, 0 at empty
				visual.hpFill.BackgroundColor3 = Color3.fromRGB(
					220,
					math.floor(220 * t2),
					80
				)
			end

			-- Counter-rotate so bar stays horizontal regardless of ship rotation
			visual.hpBar.Rotation = -math.deg(visual.currentRot)

		end

		-- Emit wake particles behind moving ships
		if canvas then
			local speed = visual.targetVel.Magnitude
			WakeEffect.emit(
				userId,
				visual.currentPos,
				visual.currentRot,
				speed,
				canvas,
				ViewportController.worldToCanvas
			)
		end
		
		-- Update viewport to follow local player's ship
		if userId == localPlayer.UserId then
			ViewportController.targetPosition = visual.currentPos
			ViewportController.targetVelocity = visual.targetVel
			-- Update health HUD
			if visual.health then
				HealthHUD.setHealth(visual.health)
			end
			-- Update kills HUD
			KillsHUD.setKills(visual.kills or 0)
			-- Update ammo HUD with our ammo count
			if visual.ammo then
				AmmoHUD.setAmmo(visual.ammo)
			end
			-- Update all power-up indicators on HUD
			AmmoHUD.setPowerUps({
				boost = visual.boost,
				dmgBoost = visual.dmgBoost,
				shield = visual.shield,
				scatter = visual.scatter,
				ghost = visual.ghost,
				ram = visual.ram,
				homing = visual.homing,
				sBounce = visual.sBounce,
				mines = visual.mines,
				dashCd = visual.dashCd,
				block = visual.block,
				blockCd = visual.blockCd,
			})
		end
	end
	
	-- Tick all wake particles (fade, drift, cleanup)
	WakeEffect.update(deltaTime)
	
	-- === SPEED LINES ===
	-- Spawn and update speed-streak effects for the local player
	local localVisual = shipVisuals[localPlayer.UserId]
	if localVisual and canvas then
		local speed = localVisual.targetVel.Magnitude
		local maxSpd = Constants.SHIP_MAX_SPEED
		local speedFrac = math.clamp(speed / maxSpd, 0, 1)
		
		-- Spawn new speed lines when above threshold
		if speedFrac >= Constants.SPEED_LINE_THRESHOLD and #speedLines < MAX_SPEED_LINES then
			SPEED_LINE_SPAWN_TIMER = SPEED_LINE_SPAWN_TIMER - deltaTime
			if SPEED_LINE_SPAWN_TIMER <= 0 then
				-- Spawn interval decreases with speed (more lines at higher speed)
				local intensity = (speedFrac - Constants.SPEED_LINE_THRESHOLD) / (1 - Constants.SPEED_LINE_THRESHOLD)
				SPEED_LINE_SPAWN_TIMER = 0.12 - intensity * 0.08  -- 0.12s at threshold, 0.04s at max
				
				-- Create a speed line near the ship, offset to the side
				local velDir = localVisual.targetVel.Unit
				local sideOffset = (math.random() - 0.5) * 120  -- random lateral spread
				local perpX = -velDir.Y
				local perpY = velDir.X
				local spawnPos = localVisual.currentPos
					+ Vector2.new(perpX, perpY) * sideOffset
					+ velDir * (math.random(20, 60))  -- slightly ahead
				
				local lineLength = math.random(20, 50) + intensity * 30
				local line = Instance.new("Frame")
				line.Name = "SpeedLine"
				line.Size = UDim2.new(0, lineLength, 0, 2)
				line.AnchorPoint = Vector2.new(0.5, 0.5)
				line.Position = ViewportController.worldToCanvas(spawnPos)
				line.BackgroundColor3 = Color3.fromRGB(
					200 + math.random(0, 55),
					220 + math.random(0, 35),
					255
				)
				line.BackgroundTransparency = 0.3 + (1 - intensity) * 0.3
				line.BorderSizePixel = 0
				line.Rotation = math.deg(math.atan2(velDir.Y, velDir.X))
				line.ZIndex = 6
				line.Parent = canvas
				
				table.insert(speedLines, {
					frame = line,
					life = 0,
					maxLife = 0.25 + math.random() * 0.15,
					worldPos = spawnPos,
					velDir = velDir,
				})
			end
		end
		
		-- Update existing speed lines (streak backward, fade out)
		for i = #speedLines, 1, -1 do
			local sl = speedLines[i]
			sl.life = sl.life + deltaTime
			local frac = sl.life / sl.maxLife
			
			if frac >= 1 then
				sl.frame:Destroy()
				table.remove(speedLines, i)
			else
				-- Streak backward (opposite of travel direction)
				sl.worldPos = sl.worldPos - sl.velDir * speed * deltaTime * 0.5
				sl.frame.Position = ViewportController.worldToCanvas(sl.worldPos)
				sl.frame.BackgroundTransparency = 0.3 + frac * 0.7  -- fade out
				-- Shrink length as it fades
				local currentLen = sl.frame.Size.X.Offset * (1 - frac * 0.5)
				sl.frame.Size = UDim2.new(0, currentLen, 0, 2)
			end
		end
	else
		-- Clean up speed lines if no local ship
		for _, sl in speedLines do
			sl.frame:Destroy()
		end
		table.clear(speedLines)
	end
end

return ShipController
