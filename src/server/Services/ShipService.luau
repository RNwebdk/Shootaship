--[[
	ShipService (Server)
	====================
	Manages all ship state: spawning, 2D physics, position tracking.
	
	This runs on the SERVER because the server is the "source of truth"
	for where ships actually are. If we let the client control positions,
	a hacker could teleport their ship anywhere.
	
	The server:
	  1. Receives input from clients (thrust, turn)
	  2. Simulates 2D physics (applies thrust, drag, rotation)
	  3. Broadcasts the authoritative positions to all clients
	
	All positions and velocities are 2D (Vector2) because this is a
	top-down GUI-based game. The client renders these positions as
	GUI elements on a ScreenGui canvas.
	
	PHYSICS MODEL (each frame):
	  1. Apply rotation from input (A/D keys)
	  2. Calculate thrust direction from current rotation
	  3. Add thrust to velocity (if W pressed)
	  4. Apply drag to velocity (simulates water resistance)
	  5. Clamp velocity to max speed
	  6. Add velocity to position
	  7. Clamp position to map bounds
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ShipService = {}

--[[
	Ship state table. One entry per active player.
	
	Key: player UserId (number)
	Value: {
	  position: Vector2    -- center of ship in world space
	  velocity: Vector2    -- movement per second in world space
	  rotation: number     -- radians, 0 = pointing up, clockwise positive
	  health:   number     -- current HP
	  input: {             -- latest input from client
	    thrust:  number    -- -1 (reverse), 0 (none), 1 (forward)
	    turn:    number    -- -1 (left), 0 (none), 1 (right)
	  }
	}
]]
local ships = {}

-- Kill tracking (persists across respawns)
local kills = {} -- userId → number

-- Timer for network sync (we don't send every frame — too expensive)
local syncTimer = 0

-- Ram damage cooldown per pair (prevent damage every frame while overlapping)
local ramCooldowns = {}  -- "minId_maxId" → seconds until next ram hit
local RAM_COOLDOWN = 1.0  -- 1 second between ram hits per pair

function ShipService.init()
	-- Listen for player input from clients
	local inputEvent = EventManager.getEvent("PlayerInput")
	
	--[[
		OnServerEvent fires when ANY client calls :FireServer() on this event.
		The first argument is always the Player who sent it (Roblox adds this
		automatically — the client CANNOT fake who they are. This is a key
		security feature).
	]]
	inputEvent.OnServerEvent:Connect(function(player: Player, input)
		local ship = ships[player.UserId]
		if not ship then return end -- Ignore input if player has no ship
		
		-- VALIDATE input: never trust the client blindly.
		-- A hacked client could send thrust = 9999. We clamp to valid range.
		if typeof(input) ~= "table" then return end
		
		ship.input = {
			thrust = math.clamp(input.thrust or 0, -1, 1),
			turn = math.clamp(input.turn or 0, -1, 1),
		}
	end)
	
	-- Ship spawning is now managed by GameService (which calls ShipService.spawnShip
	-- when the round starts). We don't auto-spawn on PlayerAdded anymore.
	
	-- Clean up when a player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		ships[player.UserId] = nil
		kills[player.UserId] = nil
		-- Also clean up combat cooldowns
		local CombatService = require(script.Parent.CombatService)
		CombatService.onPlayerRemoved(player.UserId)
	end)
	
	-- (Players already in the game when GameService starts the round
	-- will be spawned by GameService.startRound(), not here)
	
	-- Listen for dash requests from clients
	local dashEvent = EventManager.getEvent("Dash")
	dashEvent.OnServerEvent:Connect(function(player: Player)
		local ship = ships[player.UserId]
		if not ship then return end
		if ship.health <= 0 then return end
		if ship.dashCooldown > 0 then return end
		
		-- Apply impulse in the facing direction
		local dirX = math.sin(ship.rotation)
		local dirY = -math.cos(ship.rotation)
		local dashDir = Vector2.new(dirX, dirY)
		ship.velocity = ship.velocity + dashDir * Constants.DASH_IMPULSE
		ship.dashCooldown = Constants.DASH_COOLDOWN
	end)
	
	-- Listen for block/shockwave requests from clients
	local blockEvent = EventManager.getEvent("Block")
	blockEvent.OnServerEvent:Connect(function(player: Player)
		print("[ShipService] Block event received from", player.Name)
		local ship = ships[player.UserId]
		if not ship then print("[ShipService] Block rejected: no ship") return end
		if ship.health <= 0 then print("[ShipService] Block rejected: dead") return end
		if ship.blockCooldown > 0 then print("[ShipService] Block rejected: cooldown", ship.blockCooldown) return end
		if ship.blockTimer > 0 then print("[ShipService] Block rejected: already blocking") return end  -- already blocking
		
		-- Activate block shockwave
		ship.blockTimer = Constants.BLOCK_DURATION
		ship.blockCooldown = Constants.BLOCK_COOLDOWN
		
		-- Tell all clients for VFX
		local blockActivatedEvent = EventManager.getEvent("BlockActivated")
		local GameService = require(script.Parent.GameService)
		GameService.fireAllGameClients(blockActivatedEvent, {
			userId = player.UserId,
			px = ship.position.X,
			py = ship.position.Y,
		})
	end)
	
	print("[ShipService] Initialized")
end

--[[
	Spawn a new ship for a player at a random position on the map.
]]
function ShipService.spawnShip(player: Player)
	local halfW = Constants.MAP_WIDTH / 2
	local halfH = Constants.MAP_HEIGHT / 2
	-- Random position in the center region (not too close to edges)
	local spawnX = math.random(-halfW * 0.6, halfW * 0.6)
	local spawnY = math.random(-halfH * 0.6, halfH * 0.6)
	
	ships[player.UserId] = {
		position = Vector2.new(spawnX, spawnY),
		velocity = Vector2.new(0, 0),
		rotation = 0,
		angularVelocity = 0,         -- radians per second (spin momentum)
		health = Constants.SHIP_MAX_HEALTH,
		ammo = Constants.STARTING_AMMO,
		-- Power-up timers & counters
		speedBoostTimer = 0,         -- seconds remaining on speed boost
		speedBoostStacks = 0,        -- how many speed boosts stacked
		damageBoostTimer = 0,        -- seconds remaining on damage boost
		shield = 0,                  -- hits remaining on shield (0 = none)
		scatterShotCount = 0,        -- scatter volleys remaining
		ghostTimer = 0,              -- seconds remaining on ghost mode
		ramTimer = 0,                -- seconds remaining on ram mode
		homingShotCount = 0,         -- homing shots remaining
		superBounceTimer = 0,        -- seconds remaining on super bounce
		mineCount = 0,               -- naval mines available to deploy
		machinegunTimer = 0,         -- seconds remaining on machinegun auto-fire
		machinegunCooldown = 0,      -- internal cooldown between machinegun shots
		dashCooldown = 0,            -- seconds until next dash is available
		blockTimer = 0,              -- seconds remaining on active block shockwave
		blockCooldown = 0,           -- seconds until next block is available
		thrustRamp = 0,              -- acceleration curve: 0→1 ramp-up while thrusting
		input = { thrust = 0, turn = 0 },
	}
	
	-- Tell this specific client their ship is ready
	local spawnEvent = EventManager.getEvent("PlayerSpawned")
	spawnEvent:FireClient(player, {
		position = { x = spawnX, y = spawnY },
		rotation = 0,
	})
	
	print("[ShipService] Spawned ship for", player.Name)
end

--[[
	Physics tick — called every server frame (~60fps).
	
	This is where the "asteroids-style" movement happens:
	  - Rotation changes facing direction (A/D)
	  - Thrust pushes in facing direction (W)
	  - Drag slows you down over time (water resistance)
	  - Velocity moves the position
]]
function ShipService.update(deltaTime: number)
	for userId, ship in ships do
		-- Tick down all power-up timers
		if ship.speedBoostTimer > 0 then
			ship.speedBoostTimer = math.max(0, ship.speedBoostTimer - deltaTime)
			if ship.speedBoostTimer <= 0 then
				ship.speedBoostStacks = 0
			end
		end
		if ship.damageBoostTimer > 0 then
			ship.damageBoostTimer = math.max(0, ship.damageBoostTimer - deltaTime)
		end
		if ship.ghostTimer > 0 then
			ship.ghostTimer = math.max(0, ship.ghostTimer - deltaTime)
		end
		if ship.ramTimer > 0 then
			ship.ramTimer = math.max(0, ship.ramTimer - deltaTime)
		end
		if ship.superBounceTimer > 0 then
			ship.superBounceTimer = math.max(0, ship.superBounceTimer - deltaTime)
		end
		if (ship.machinegunTimer or 0) > 0 then
			ship.machinegunTimer = math.max(0, ship.machinegunTimer - deltaTime)
		end
		if ship.dashCooldown > 0 then
			ship.dashCooldown = math.max(0, ship.dashCooldown - deltaTime)
		end
		if (ship.blockTimer or 0) > 0 then
			ship.blockTimer = math.max(0, ship.blockTimer - deltaTime)
		end
		if (ship.blockCooldown or 0) > 0 then
			ship.blockCooldown = math.max(0, ship.blockCooldown - deltaTime)
		end
		local boosted = ship.speedBoostTimer > 0
		local boostMul = 1
		if boosted then
			local stacks = math.max(1, ship.speedBoostStacks or 1)
			boostMul = 1 + (Constants.SPEED_BOOST_MULTIPLIER - 1) * stacks
		end
		
		-- 1. ANGULAR MOMENTUM: Apply turn input as angular acceleration
		-- Speed-dependent turning: faster = wider turns (reduced turn rate)
		local speedFraction = 0
		local maxSpd = Constants.SHIP_MAX_SPEED * boostMul
		if maxSpd > 0 then
			speedFraction = math.clamp(ship.velocity.Magnitude / maxSpd, 0, 1)
		end
		local effectiveTurnSpeed = Constants.SHIP_TURN_SPEED * (1 - speedFraction * Constants.SPEED_TURN_REDUCTION)
		
		if ship.input.turn ~= 0 then
			ship.angularVelocity = ship.angularVelocity + (ship.input.turn * effectiveTurnSpeed * deltaTime)
		end
		
		-- Clamp angular velocity to max turn speed
		ship.angularVelocity = math.clamp(ship.angularVelocity, -Constants.SHIP_MAX_TURN_SPEED, Constants.SHIP_MAX_TURN_SPEED)
		
		-- Apply angular drag (frame-rate independent, same formula as linear drag)
		local angularDragMul = math.exp(-Constants.SHIP_ANGULAR_DRAG * deltaTime)
		ship.angularVelocity = ship.angularVelocity * angularDragMul
		
		-- Stop tiny angular velocities
		if math.abs(ship.angularVelocity) < 0.01 then
			ship.angularVelocity = 0
		end
		
		-- Apply angular velocity to rotation
		ship.rotation = ship.rotation + (ship.angularVelocity * deltaTime)
		
		-- 2. THRUST: Apply force in the direction the ship is facing
		-- Acceleration curve: thrust ramps up gradually for satisfying build-up
		if ship.input.thrust ~= 0 then
			-- Ramp up thrust factor toward 1.0
			ship.thrustRamp = math.min(1, ship.thrustRamp + Constants.THRUST_RAMP_SPEED * deltaTime)
			local rampFactor = Constants.THRUST_RAMP_MIN + (1 - Constants.THRUST_RAMP_MIN) * ship.thrustRamp
			
			local dirX = math.sin(ship.rotation)
			local dirY = -math.cos(ship.rotation)
			local thrustDir = Vector2.new(dirX, dirY)
			
			-- Add thrust to velocity (F = ma, but we treat mass as 1)
			ship.velocity = ship.velocity + (thrustDir * ship.input.thrust * Constants.SHIP_THRUST_FORCE * boostMul * rampFactor * deltaTime)
		else
			-- Decay ramp quickly when not thrusting
			ship.thrustRamp = math.max(0, ship.thrustRamp - Constants.THRUST_RAMP_DECAY * deltaTime)
		end
		
		-- 3. DRAG: Reduce velocity over time (simulates water resistance)
		local dragMultiplier = math.exp(-Constants.SHIP_DRAG * deltaTime)
		ship.velocity = ship.velocity * dragMultiplier
		
		-- 4. SPEED CAP: Clamp velocity magnitude to max speed
		-- Allow dash to temporarily exceed max speed — only cap when not in dash burst
		local justDashed = ship.dashCooldown > (Constants.DASH_COOLDOWN - 0.3)
		if ship.velocity.Magnitude > maxSpd and not justDashed then
			ship.velocity = ship.velocity.Unit * maxSpd
		end
		
		-- 5. Stop tiny velocities (prevent infinite micro-drifting)
		if ship.velocity.Magnitude < 0.5 then
			ship.velocity = Vector2.new(0, 0)
		end
		
		-- 6. MOVE: Add velocity to position
		ship.position = ship.position + (ship.velocity * deltaTime)
		
		-- 7. BOUNCE: Reflect off map edges with a speed boost
		local halfW = Constants.MAP_WIDTH / 2
		local halfH = Constants.MAP_HEIGHT / 2
		local bounced = false
		local bounceNormal = Vector2.new(0, 0)
		local vx = ship.velocity.X
		local vy = ship.velocity.Y
		
		if ship.position.X < -halfW then
			ship.position = Vector2.new(-halfW, ship.position.Y)
			vx = math.abs(vx)
			bounced = true
			bounceNormal = Vector2.new(1, 0)
		elseif ship.position.X > halfW then
			ship.position = Vector2.new(halfW, ship.position.Y)
			vx = -math.abs(vx)
			bounced = true
			bounceNormal = Vector2.new(-1, 0)
		end
		
		if ship.position.Y < -halfH then
			ship.position = Vector2.new(ship.position.X, -halfH)
			vy = math.abs(vy)
			bounced = true
			bounceNormal = bounceNormal + Vector2.new(0, 1)
		elseif ship.position.Y > halfH then
			ship.position = Vector2.new(ship.position.X, halfH)
			vy = -math.abs(vy)
			bounced = true
			bounceNormal = bounceNormal + Vector2.new(0, -1)
		end
		
		if bounced then
			local newVel = Vector2.new(vx, vy)
			-- Use super bounce multiplier if active
			local bounceMul = Constants.BOUNCE_SPEED_MULTIPLIER
			local minSpeed = Constants.BOUNCE_MIN_SPEED
			if ship.superBounceTimer > 0 then
				bounceMul = Constants.SUPERBOUNCE_MULTIPLIER
				minSpeed = Constants.SUPERBOUNCE_MIN_SPEED
			end
			local speed = math.max(newVel.Magnitude * bounceMul, minSpeed)
			if newVel.Magnitude > 0.1 then
				ship.velocity = newVel.Unit * speed
			else
				-- Was barely moving, push away from wall
				ship.velocity = bounceNormal.Unit * minSpeed
			end
			
			-- Rotate ship to face the bounce direction
			-- Ship convention: 0=up, rotation increases clockwise
			-- Forward = (sin(r), -cos(r)), so r = atan2(vx, -vy)
			ship.rotation = math.atan2(ship.velocity.X, -ship.velocity.Y)
			ship.angularVelocity = 0
			
			-- Notify clients for VFX
			local bounceEvent = EventManager.getEvent("ShipBounced")
			bounceEvent:FireAllClients({
				userId = userId,
				px = ship.position.X,
				py = ship.position.Y,
				nx = bounceNormal.X,
				ny = bounceNormal.Y,
			})
		end
	end
	
	-- SHIP-TO-SHIP BOUNCE: Push ships apart when they overlap
	local bouncedPairs = {}
	local shipRadius = Constants.SHIP_SIZE.X * 0.5
	local shipIds = {}
	for uid, _ in ships do
		table.insert(shipIds, uid)
	end
	for i = 1, #shipIds do
		for j = i + 1, #shipIds do
			local idA = shipIds[i]
			local idB = shipIds[j]
			local a = ships[idA]
			local b = ships[idB]
			if a.health <= 0 or b.health <= 0 then continue end
			
			local diff = a.position - b.position
			local dist = diff.Magnitude
			local minDist = shipRadius * 2
			
			if dist < minDist and dist > 0.1 then
				local normal = diff.Unit  -- A ← B direction
				
				-- Separate so they don't overlap
				local overlap = (minDist - dist) / 2
				a.position = a.position + normal * overlap
				b.position = b.position - normal * overlap
				
				-- Bounce velocities: reflect each ship's velocity off the collision normal
				local relVel = a.velocity - b.velocity
				local relSpeed = relVel:Dot(normal)
				
				-- Only bounce if ships are moving toward each other
				if relSpeed < 0 then
					-- Check if either ship has super bounce active
					local hasSuperBounce = a.superBounceTimer > 0 or b.superBounceTimer > 0
					local bounceMul = hasSuperBounce and Constants.SUPERBOUNCE_MULTIPLIER or Constants.BOUNCE_SPEED_MULTIPLIER
					local minSpeed = hasSuperBounce and Constants.SUPERBOUNCE_MIN_SPEED or Constants.BOUNCE_MIN_SPEED
					
					local bounceImpulse = normal * math.abs(relSpeed) * bounceMul
					a.velocity = a.velocity + bounceImpulse * 0.5
					b.velocity = b.velocity - bounceImpulse * 0.5
					
					-- Ensure minimum bounce speed
					if a.velocity.Magnitude < minSpeed then
						a.velocity = normal * minSpeed
					end
					if b.velocity.Magnitude < minSpeed then
						b.velocity = -normal * minSpeed
					end
					
					-- Spin for flair (more with super bounce)
					local spinAmount = hasSuperBounce and 5 or 1.5
					a.angularVelocity = a.angularVelocity + (math.random() > 0.5 and spinAmount or -spinAmount)
					b.angularVelocity = b.angularVelocity + (math.random() > 0.5 and spinAmount or -spinAmount)
					
					-- VFX at the midpoint between the two ships
					local midpoint = (a.position + b.position) / 2
					local bounceEvent = EventManager.getEvent("ShipBounced")
					bounceEvent:FireAllClients({
						userId = idA,
						px = midpoint.X,
						py = midpoint.Y,
						nx = normal.X,
						ny = normal.Y,
						shipCollision = true,
					})
				end
			end
		end
	end
	
	-- RAM COLLISION: Check ship-vs-ship collisions for ramming ships
	-- Tick ram cooldowns
	for key, cd in ramCooldowns do
		ramCooldowns[key] = cd - deltaTime
		if ramCooldowns[key] <= 0 then
			ramCooldowns[key] = nil
		end
	end
	
	local rammedPairs = {}  -- prevent double-hits per frame
	for userId, ship in ships do
		if ship.ramTimer <= 0 then continue end
		if ship.health <= 0 then continue end
		
		for targetId, target in ships do
			if targetId == userId then continue end
			if target.health <= 0 then continue end
			
			local pairKey = math.min(userId, targetId) .. "_" .. math.max(userId, targetId)
			if rammedPairs[pairKey] then continue end
			if ramCooldowns[pairKey] then continue end  -- on cooldown
			
			local dist = (ship.position - target.position).Magnitude
			if dist <= Constants.RAM_RADIUS then
				rammedPairs[pairKey] = true
				ramCooldowns[pairKey] = RAM_COOLDOWN  -- set cooldown
				
				-- Ghost ships are immune
				if target.ghostTimer > 0 then continue end
				
				-- Shield absorbs ram
				if target.shield > 0 then
					target.shield = target.shield - 1
					continue
				end
				
				target.health = target.health - Constants.RAM_DAMAGE
				
				local dmgEvent = EventManager.getEvent("ShipDamaged")
				dmgEvent:FireAllClients({
					targetId = targetId,
					attackerId = userId,
					damage = Constants.RAM_DAMAGE,
					newHealth = target.health,
				})
				
				if target.health <= 0 then
					local destroyEvent = EventManager.getEvent("ShipDestroyed")
					destroyEvent:FireAllClients({
						targetId = targetId,
						attackerId = userId,
					})
					ShipService.onShipDestroyed(targetId, userId)
				end
			end
		end
	end
	
	-- NETWORK SYNC: Send positions to all clients at fixed rate
	syncTimer = syncTimer + deltaTime
	if syncTimer >= Constants.SYNC_RATE then
		syncTimer = 0
		ShipService.broadcastState()
	end
end

--[[
	Sends all ship positions to all clients.
	
	We pack the data into a simple table (not full Vector2 objects)
	because RemoteEvents serialize data for network transfer.
	Smaller data = less bandwidth = less lag.
]]
function ShipService.broadcastState()
	local syncEvent = EventManager.getEvent("ShipStateSync")
	
	-- Build a compact state table
	local stateData = {}
	for userId, ship in ships do
		stateData[userId] = {
			px = ship.position.X,      -- position X
			py = ship.position.Y,      -- position Y
			vx = ship.velocity.X,      -- velocity X (for client interpolation)
			vy = ship.velocity.Y,      -- velocity Y
			r = ship.rotation,         -- rotation in radians
			av = ship.angularVelocity, -- angular velocity (for smooth rotation lerp)
			hp = ship.health,          -- health
			ammo = ship.ammo,          -- current ammo count
			-- Power-up states (only send non-zero to save bandwidth)
			boost = ship.speedBoostTimer > 0 and ship.speedBoostTimer or nil,
			boostStacks = ship.speedBoostStacks > 0 and ship.speedBoostStacks or nil,
			dmgBoost = ship.damageBoostTimer > 0 and ship.damageBoostTimer or nil,
			shield = ship.shield > 0 and ship.shield or nil,
			scatter = ship.scatterShotCount > 0 and ship.scatterShotCount or nil,
			ghost = ship.ghostTimer > 0 and ship.ghostTimer or nil,
			ram = ship.ramTimer > 0 and ship.ramTimer or nil,
			homing = ship.homingShotCount > 0 and ship.homingShotCount or nil,
			sBounce = ship.superBounceTimer > 0 and ship.superBounceTimer or nil,
			mines = ship.mineCount > 0 and ship.mineCount or nil,
			mg = (ship.machinegunTimer or 0) > 0 and ship.machinegunTimer or nil,
			kills = kills[userId] or 0,
			dashCd = ship.dashCooldown > 0 and ship.dashCooldown or nil,
			block = ship.blockTimer > 0 and ship.blockTimer or nil,
			blockCd = ship.blockCooldown > 0 and ship.blockCooldown or nil,
		}
	end
	
	-- Fire only to game players (not hub players in Studio multi-player)
	local GameService = require(script.Parent.GameService)
	GameService.fireAllGameClients(syncEvent, stateData)
end

function ShipService.getShips()
	return ships
end

--[[
	Called by CombatService when a ship reaches 0 HP.
	Removes the ship and respawns it after a short delay.
]]
function ShipService.onShipDestroyed(targetId: number, attackerId: number)
	local ship = ships[targetId]
	if not ship then return end
	
	-- Track the kill
	if attackerId and attackerId ~= targetId then
		kills[attackerId] = (kills[attackerId] or 0) + 1
	end
	
	-- Notify GameService for deathmatch scoring
	local GameService = require(script.Parent.GameService)
	if attackerId and attackerId ~= targetId then
		GameService.onKill(attackerId, targetId)
	end
	
	-- Remove the ship immediately so it stops appearing in state sync
	-- (client-side sink animation handles the visual)
	ships[targetId] = nil
	
	-- Find the player to respawn them
	local Players = game:GetService("Players")
	local player = Players:GetPlayerByUserId(targetId)
	if not player then return end
	
	-- Respawn after 3 seconds
	task.delay(3, function()
		if player.Parent then  -- still in game
			ShipService.spawnShip(player)
			print("[ShipService] Respawned", player.Name)
		end
	end)
end

function ShipService.resetKills(userId: number)
	kills[userId] = 0
end

function ShipService.resetAllKills()
	table.clear(kills)
end

function ShipService.destroyAllShips()
	table.clear(ships)
	table.clear(kills)
	-- Broadcast empty state so clients clear their ship visuals
	local syncEvent = EventManager.getEvent("ShipStateSync")
	local GameService = require(script.Parent.GameService)
	GameService.fireAllGameClients(syncEvent, {})
end

return ShipService
