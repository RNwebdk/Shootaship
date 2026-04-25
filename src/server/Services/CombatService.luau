--[[
	CombatService (Server)
	======================
	Handles cannon firing, projectiles, hit detection, and damage.
	
	Server-authoritative because:
	  - We validate cooldowns so clients can't spam fire
	  - We do hit detection server-side so clients can't fake hits
	  - We control damage so clients can't one-shot everyone
	  
	Flow:
	  1. Client presses spacebar → fires "FireCannon" event
	  2. Server validates cooldown, reads ship position/rotation
	  3. Server creates a projectile (position + velocity)
	  4. Server tells all clients "CannonFired" so they render it
	  5. Each frame, server moves projectiles and checks collisions
	  6. On hit: apply damage, fire "ShipDamaged" or "ShipDestroyed"
	  7. On expire: remove projectile after CANNONBALL_LIFETIME
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

-- We need ShipService to read ship positions and apply damage.
-- Lazy-require to avoid circular dependency (ShipService loads first).
local ShipService

local CombatService = {}

--[[
	Active projectiles on the server.
	Each entry: {
	  id:        number    -- unique ID for client sync
	  ownerId:   number    -- userId of the player who fired
	  position:  Vector2   -- current world position
	  velocity:  Vector2   -- direction * speed
	  age:       number    -- seconds alive
	}
]]
local projectiles = {}

-- Cooldown tracking: userId → timestamp of last fire
local cooldowns = {}

-- Auto-incrementing projectile ID
local nextProjectileId = 1

--[[
	Active naval mines on the server.
	Each entry: {
	  id:        number    -- unique ID for client sync
	  ownerId:   number    -- userId of player who dropped it
	  position:  Vector2   -- world position
	  age:       number    -- seconds since deployed
	}
]]
local mines = {}
local nextMineId = 1

function CombatService.init()
	-- Lazy require to break circular dependency
	ShipService = require(script.Parent.ShipService)
	
	local fireEvent = EventManager.getEvent("FireCannon")
	
	fireEvent.OnServerEvent:Connect(function(player: Player)
		CombatService.handleFire(player)
	end)
	
	local deployMineEvent = EventManager.getEvent("DeployMine")
	deployMineEvent.OnServerEvent:Connect(function(player: Player)
		CombatService.handleDeployMine(player)
	end)
	
	print("[CombatService] Initialized")
end

--[[
	Called when a client requests to fire.
	Validates cooldown + ammo, creates projectiles.
	Scatter shot: 4 balls in a spread. Homing: 1 tracking ball. Normal: 2 broadside.
]]
function CombatService.handleFire(player: Player)
	local userId = player.UserId
	local ships = ShipService.getShips()
	local ship = ships[userId]
	
	-- No ship? Can't fire.
	if not ship then return end
	
	-- Dead ships can't fire
	if ship.health <= 0 then return end
	
	-- Ghost mode: can't fire while invulnerable
	if ship.ghostTimer > 0 then return end
	
	-- Ammo check — need at least 1 shot
	if ship.ammo <= 0 then return end
	
	-- Consume 1 ammo
	ship.ammo = ship.ammo - 1
	
	-- Ship's forward direction
	local dirX = math.sin(ship.rotation)
	local dirY = -math.cos(ship.rotation)
	local forward = Vector2.new(dirX, dirY)
	
	-- Perpendicular (right side of the ship)
	local rightX = math.cos(ship.rotation)
	local rightY = math.sin(ship.rotation)
	local right = Vector2.new(rightX, rightY)
	
	local cannonFiredEvent = EventManager.getEvent("CannonFired")
	local sideOffset = Constants.CANNON_SIDE_OFFSET
	local isBoosted = ship.damageBoostTimer > 0
	
	-- Determine fire mode
	if ship.scatterShotCount > 0 then
		-- SCATTER SHOT: fire multiple cannonballs in a spread from each side
		ship.scatterShotCount = ship.scatterShotCount - 1
		local count = Constants.SCATTER_SHOT_COUNT
		local spread = Constants.SCATTER_SHOT_SPREAD
		
		for _, side in { -1, 1 } do
			local sideDir = right * side
			local spawnPos = ship.position + (sideDir * sideOffset)
			local baseAngle = math.atan2(sideDir.X, -sideDir.Y)
			
			for j = 1, count do
				local frac = (j - 1) / math.max(1, count - 1) - 0.5  -- -0.5 to 0.5
				local angle = baseAngle + frac * spread
				local projDir = Vector2.new(math.sin(angle), -math.cos(angle))
				local projVelocity = (projDir * Constants.CANNONBALL_SPEED) + (ship.velocity * 0.3)
				
				local id = nextProjectileId
				nextProjectileId = nextProjectileId + 1
				
				table.insert(projectiles, {
					id = id,
					ownerId = userId,
					position = spawnPos,
					velocity = projVelocity,
					age = 0,
					homing = false,
				})
				
				cannonFiredEvent:FireAllClients({
					id = id,
					ownerId = userId,
					px = spawnPos.X,
					py = spawnPos.Y,
					vx = projVelocity.X,
					vy = projVelocity.Y,
					scatter = true,
					boosted = isBoosted or nil,
				})
			end
		end
	elseif ship.homingShotCount > 0 then
		-- HOMING SHOT: fire one ball forward that tracks nearest enemy
		ship.homingShotCount = ship.homingShotCount - 1
		local spawnPos = ship.position + (forward * 30)
		local projVelocity = forward * Constants.CANNONBALL_SPEED
		
		local id = nextProjectileId
		nextProjectileId = nextProjectileId + 1
		
		table.insert(projectiles, {
			id = id,
			ownerId = userId,
			position = spawnPos,
			velocity = projVelocity,
			age = 0,
			homing = true,
		})
		
		cannonFiredEvent:FireAllClients({
			id = id,
			ownerId = userId,
			px = spawnPos.X,
			py = spawnPos.Y,
			vx = projVelocity.X,
			vy = projVelocity.Y,
			homing = true,
			boosted = isBoosted or nil,
		})
	else
		-- NORMAL: Fire from both sides of the ship (broadside cannons)
		for _, side in { -1, 1 } do
			local sideDir = right * side
			local spawnPos = ship.position + (sideDir * sideOffset)
			local projVelocity = (sideDir * Constants.CANNONBALL_SPEED) + (ship.velocity * 0.3)
			
			local id = nextProjectileId
			nextProjectileId = nextProjectileId + 1
			
			table.insert(projectiles, {
				id = id,
				ownerId = userId,
				position = spawnPos,
				velocity = projVelocity,
				age = 0,
				homing = false,
			})
			
			cannonFiredEvent:FireAllClients({
				id = id,
				ownerId = userId,
				px = spawnPos.X,
				py = spawnPos.Y,
				vx = projVelocity.X,
				vy = projVelocity.Y,
				boosted = isBoosted or nil,
			})
		end
	end
end

--[[
	Called when a client requests to deploy a naval mine.
	Drops a mine behind the ship if they have mines available.
]]
function CombatService.handleDeployMine(player: Player)
	local userId = player.UserId
	local ships = ShipService.getShips()
	local ship = ships[userId]
	
	if not ship then return end
	if ship.health <= 0 then return end
	if ship.mineCount <= 0 then return end
	
	-- Consume one mine
	ship.mineCount = ship.mineCount - 1
	
	-- Drop behind the ship (opposite of forward direction)
	local dirX = math.sin(ship.rotation)
	local dirY = -math.cos(ship.rotation)
	local behindX = ship.position.X - dirX * Constants.MINE_DROP_OFFSET
	local behindY = ship.position.Y - dirY * Constants.MINE_DROP_OFFSET
	
	local id = nextMineId
	nextMineId = nextMineId + 1
	
	table.insert(mines, {
		id = id,
		ownerId = userId,
		position = Vector2.new(behindX, behindY),
		age = 0,
	})
	
	-- Tell all clients to render the mine
	local deployEvent = EventManager.getEvent("MineDeployed")
	deployEvent:FireAllClients({
		id = id,
		ownerId = userId,
		px = behindX,
		py = behindY,
	})
end

--[[
	Per-frame update: move projectiles, homing tracking, check collisions, expire old ones.
	Also tick naval mines — check proximity to ships, explode on contact.
]]
function CombatService.update(deltaTime: number)
	local ships = ShipService.getShips()
	
	-- === MACHINEGUN AUTO-FIRE ===
	local cannonFiredEvent = EventManager.getEvent("CannonFired")
	for userId, ship in ships do
		if ship.machinegunTimer and ship.machinegunTimer > 0 and ship.health > 0 then
			-- Tick the per-ship fire cooldown
			ship.machinegunCooldown = (ship.machinegunCooldown or 0) - deltaTime
			if ship.machinegunCooldown <= 0 then
				ship.machinegunCooldown = Constants.MACHINEGUN_FIRE_RATE
				
				-- Fire one bullet from the front of the ship
				local dirX = math.sin(ship.rotation)
				local dirY = -math.cos(ship.rotation)
				local forward = Vector2.new(dirX, dirY)
				local spawnPos = ship.position + (forward * 30)
				local projVelocity = (forward * Constants.MACHINEGUN_SPEED) + (ship.velocity * 0.2)
				
				local id = nextProjectileId
				nextProjectileId = nextProjectileId + 1
				
				table.insert(projectiles, {
					id = id,
					ownerId = userId,
					position = spawnPos,
					velocity = projVelocity,
					age = 0,
					homing = false,
					machinegun = true,
				})
				
				cannonFiredEvent:FireAllClients({
					id = id,
					ownerId = userId,
					px = spawnPos.X,
					py = spawnPos.Y,
					vx = projVelocity.X,
					vy = projVelocity.Y,
					machinegun = true,
				})
			end
		end
	end
	
	-- === MINE UPDATE ===
	local mineIdx = #mines
	while mineIdx >= 1 do
		local mine = mines[mineIdx]
		mine.age = mine.age + deltaTime
		
		-- Expire old mines
		if mine.age >= Constants.MINE_LIFETIME then
			-- Silent despawn — notify clients
			local explodeEvent = EventManager.getEvent("MineExploded")
			explodeEvent:FireAllClients({
				id = mine.id,
				px = mine.position.X,
				py = mine.position.Y,
				despawn = true,  -- no explosion VFX, just remove
			})
			table.remove(mines, mineIdx)
			mineIdx = mineIdx - 1
			continue
		end
		
		-- Check proximity to all ships
		local exploded = false
		for userId, ship in ships do
			if ship.health <= 0 then continue end
			if ship.ghostTimer > 0 then continue end  -- ghosts are immune
			
			-- Owner is immune during arm delay
			if userId == mine.ownerId and mine.age < Constants.MINE_ARM_DELAY then
				continue
			end
			
			local dist = (ship.position - mine.position).Magnitude
			if dist <= Constants.MINE_RADIUS then
				-- BOOM! Apply damage
				ship.health = ship.health - Constants.MINE_DAMAGE
				
				-- Knockback: push ship away from mine
				local knockDir = (ship.position - mine.position)
				if knockDir.Magnitude > 0.1 then
					knockDir = knockDir.Unit
				else
					knockDir = Vector2.new(0, -1)
				end
				ship.velocity = ship.velocity + knockDir * 400
				ship.angularVelocity = ship.angularVelocity + (math.random() > 0.5 and 4 or -4)
				
				local dmgEvent = EventManager.getEvent("ShipDamaged")
				dmgEvent:FireAllClients({
					targetId = userId,
					attackerId = mine.ownerId,
					damage = Constants.MINE_DAMAGE,
					newHealth = ship.health,
				})
				
				if ship.health <= 0 then
					local destroyEvent = EventManager.getEvent("ShipDestroyed")
					destroyEvent:FireAllClients({
						targetId = userId,
						attackerId = mine.ownerId,
					})
					ShipService.onShipDestroyed(userId, mine.ownerId)
				end
				
				-- Notify clients of explosion VFX
				local explodeEvent = EventManager.getEvent("MineExploded")
				explodeEvent:FireAllClients({
					id = mine.id,
					px = mine.position.X,
					py = mine.position.Y,
					despawn = false,
				})
				
				exploded = true
				break
			end
		end
		
		if exploded then
			table.remove(mines, mineIdx)
		end
		
		mineIdx = mineIdx - 1
	end
	
	-- === PROJECTILE-VS-PROJECTILE COLLISION ===
	-- Check all pairs; mark collided ones for removal
	local collidedSet = {}  -- index → true
	for a = 1, #projectiles do
		if collidedSet[a] then continue end
		for b = a + 1, #projectiles do
			if collidedSet[b] then continue end
			-- Skip same-owner projectiles (broadside pair shouldn't collide)
			if projectiles[a].ownerId == projectiles[b].ownerId then continue end
			local dist = (projectiles[a].position - projectiles[b].position).Magnitude
			if dist <= Constants.CANNONBALL_SIZE * 2 then
				collidedSet[a] = true
				collidedSet[b] = true
				-- Tell clients to show explosion at the midpoint
				local mid = (projectiles[a].position + projectiles[b].position) / 2
				local cannonFiredEvent = EventManager.getEvent("CannonFired")
				cannonFiredEvent:FireAllClients({
					id = -1,
					ownerId = 0,
					px = mid.X,
					py = mid.Y,
					vx = 0,
					vy = 0,
					exploded = true,
				})
			end
		end
	end
	-- Remove collided projectiles (reverse order)
	if next(collidedSet) then
		for idx = #projectiles, 1, -1 do
			if collidedSet[idx] then
				table.remove(projectiles, idx)
			end
		end
	end

	-- === PROJECTILE UPDATE ===
	
	-- Iterate in reverse so we can remove while looping
	local i = #projectiles
	while i >= 1 do
		local proj = projectiles[i]
		proj.age = proj.age + deltaTime
		
		-- Expire old projectiles (machinegun bullets have shorter lifetime)
		local lifetime = proj.machinegun and Constants.MACHINEGUN_LIFETIME or Constants.CANNONBALL_LIFETIME
		if proj.age >= lifetime then
			table.remove(projectiles, i)
			i = i - 1
			continue
		end
		
		-- Homing: curve toward nearest enemy
		if proj.homing then
			local nearestDist = math.huge
			local nearestPos = nil
			for userId, ship in ships do
				if userId == proj.ownerId then continue end
				if ship.health <= 0 then continue end
				if ship.ghostTimer > 0 then continue end  -- can't target ghosts
				local d = (ship.position - proj.position).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearestPos = ship.position
				end
			end
			
			if nearestPos then
				local toTarget = (nearestPos - proj.position)
				if toTarget.Magnitude > 1 then
					toTarget = toTarget.Unit
					local currentDir = proj.velocity.Unit
					-- Blend toward target direction
					local turnAmount = Constants.HOMING_TURN_SPEED * deltaTime
					local newDir = (currentDir + toTarget * turnAmount).Unit
					proj.velocity = newDir * Constants.CANNONBALL_SPEED
				end
			end
		end
		
		-- Move projectile
		proj.position = proj.position + (proj.velocity * deltaTime)
		
		-- Check if out of map bounds
		local halfW = Constants.MAP_WIDTH / 2
		local halfH = Constants.MAP_HEIGHT / 2
		if math.abs(proj.position.X) > halfW or math.abs(proj.position.Y) > halfH then
			table.remove(projectiles, i)
			i = i - 1
			continue
		end
		
		-- Block/shockwave: reflect cannonballs near any blocking ship (wider radius)
		local reflected = false
		if not proj.reflected then
			for userId, ship in ships do
				if userId == proj.ownerId then continue end
				if ship.health <= 0 then continue end
				if not ship.blockTimer or ship.blockTimer <= 0 then continue end
				
				local dist = (proj.position - ship.position).Magnitude
				if dist <= Constants.BLOCK_RADIUS then
					local oldOwnerId = proj.ownerId
					-- Reverse velocity to send it back toward the shooter
					proj.velocity = -proj.velocity
					-- Reassign ownership so reflected ball can hit the original shooter
					proj.ownerId = userId
					proj.age = 0  -- reset age so it has full lifetime to travel back
					proj.homing = false  -- stop homing after reflect
					proj.reflected = true  -- prevent double-reflect
					reflected = true
					
					-- Tell clients to update the projectile visual
					local cannonFiredEvent = EventManager.getEvent("CannonFired")
					cannonFiredEvent:FireAllClients({
						id = proj.id,
						ownerId = userId,
						px = proj.position.X,
						py = proj.position.Y,
						vx = proj.velocity.X,
						vy = proj.velocity.Y,
						reflected = true,  -- client uses this to replace the old visual
					})
					break
				end
			end
		end
		if reflected then
			i = i - 1
			continue
		end
		
		-- Hit detection: check against all ships (except the owner)
		local hit = false
		for userId, ship in ships do
			if userId == proj.ownerId then continue end  -- can't hit yourself
			if ship.health <= 0 then continue end        -- skip dead ships
			if ship.ghostTimer > 0 then continue end     -- ghost ships are invulnerable
			
			local shipRadius = Constants.SHIP_SIZE.X * 0.5
			local hitDistance = shipRadius + Constants.CANNONBALL_SIZE
			local dist = (proj.position - ship.position).Magnitude
			
			if dist <= hitDistance then
				-- Shield absorbs the hit completely
				if ship.shield > 0 then
					ship.shield = ship.shield - 1
					hit = true
					
					local dmgEvent = EventManager.getEvent("ShipDamaged")
					dmgEvent:FireAllClients({
						targetId = userId,
						attackerId = proj.ownerId,
						damage = 0,
						newHealth = ship.health,
						shielded = true,
					})
					break
				end
				
				-- Calculate damage (apply attacker's damage boost)
				local ownerShip = ships[proj.ownerId]
				local dmgMul = 1
				if ownerShip and ownerShip.damageBoostTimer > 0 then
					dmgMul = Constants.DAMAGE_BOOST_MULTIPLIER
				end
				local baseDmg = proj.machinegun and Constants.MACHINEGUN_DAMAGE or Constants.CANNONBALL_DAMAGE
				local damage = baseDmg * dmgMul
				
				ship.health = ship.health - damage
				hit = true
				
				local dmgEvent = EventManager.getEvent("ShipDamaged")
				dmgEvent:FireAllClients({
					targetId = userId,
					attackerId = proj.ownerId,
					damage = damage,
					newHealth = ship.health,
				})
				
				if ship.health <= 0 then
					local destroyEvent = EventManager.getEvent("ShipDestroyed")
					destroyEvent:FireAllClients({
						targetId = userId,
						attackerId = proj.ownerId,
					})
					ShipService.onShipDestroyed(userId, proj.ownerId)
				end
				
				break
			end
		end
		
		if hit then
			table.remove(projectiles, i)
		end
		
		i = i - 1
	end
end

-- Clean up cooldown when player leaves
function CombatService.onPlayerRemoved(userId: number)
	cooldowns[userId] = nil
end

-- Returns the mines table so DevService can clear it
function CombatService.getMines()
	return mines
end

-- Bot helpers: allow BotService to create projectiles/mines
function CombatService.getNextProjectileId(): number
	local id = nextProjectileId
	nextProjectileId = nextProjectileId + 1
	return id
end

function CombatService.addProjectile(proj)
	table.insert(projectiles, proj)
end

function CombatService.getNextMineId(): number
	local id = nextMineId
	nextMineId = nextMineId + 1
	return id
end

function CombatService.addMine(mine)
	table.insert(mines, mine)
end

return CombatService
