--[[
	BotService (Server)
	===================
	Manages AI-controlled bot ships for testing.
	
	Bots are fake "players" — they get ship entries in ShipService
	with negative userIds (to avoid colliding with real player IDs).
	Each frame, the bot AI decides: thrust, turn, fire, deploy mines.
	
	DIFFICULTY LEVELS:
	  Easy   — slow reactions, poor aim, rarely fires
	  Medium — decent reactions, ok aim, fires regularly
	  Hard   — fast reactions, good aim, aggressive, uses power-ups
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ShipService
local CombatService

local BotService = {}

-- Bot data table: botId → { difficulty, aiState, timers }
local bots = {}
local nextBotId = -1  -- negative IDs to avoid collision with real player UserIds

-- Current global difficulty (can be changed via dev panel)
local currentDifficulty = "medium"

-- Race mode flag (when true, bots use simple race behavior instead of normal AI)
local raceMode = false

-- Difficulty profiles
local DIFFICULTY = {
	easy = {
		reactionTime = 1.2,     -- seconds between AI decisions
		aimAccuracy = 0.3,      -- 0 = terrible, 1 = perfect
		fireChance = 0.15,      -- chance to fire per decision tick
		thrustBias = 0.4,       -- how often they thrust forward
		dodgeChance = 0.1,      -- chance to dodge when taking damage
		engageRange = 800,      -- how far they'll chase a target
		mineChance = 0.02,      -- chance to deploy mine per tick
	},
	medium = {
		reactionTime = 0.6,
		aimAccuracy = 0.6,
		fireChance = 0.35,
		thrustBias = 0.6,
		dodgeChance = 0.3,
		engageRange = 1200,
		mineChance = 0.05,
	},
	hard = {
		reactionTime = 0.25,
		aimAccuracy = 0.9,
		fireChance = 0.6,
		thrustBias = 0.8,
		dodgeChance = 0.6,
		engageRange = 1800,
		mineChance = 0.1,
	},
}

-- Helper: normalize angle into (-pi, pi]
local function normalizeAngle(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- Helper: smooth step toward a value (exponential ease)
local function lerpNum(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * math.min(1, rate * dt)
end

function BotService.init()
	ShipService = require(script.Parent.ShipService)
	CombatService = require(script.Parent.CombatService)
	print("[BotService] Initialized")
end

--[[
	Add a new bot to the game. Returns the bot's ID.
]]
function BotService.addBot(): number
	local botId = nextBotId
	nextBotId = nextBotId - 1
	
	local ships = ShipService.getShips()
	
	-- Spawn a ship entry for the bot (same structure as real players)
	local halfW = Constants.MAP_WIDTH / 2
	local halfH = Constants.MAP_HEIGHT / 2
	local spawnX = math.random(-halfW * 0.6, halfW * 0.6)
	local spawnY = math.random(-halfH * 0.6, halfH * 0.6)
	
	ships[botId] = {
		position = Vector2.new(spawnX, spawnY),
		velocity = Vector2.new(0, 0),
		rotation = math.random() * math.pi * 2,
		angularVelocity = 0,
		health = Constants.SHIP_MAX_HEALTH,
		ammo = Constants.MAX_AMMO,
		speedBoostTimer = 0,
		speedBoostStacks = 0,
		damageBoostTimer = 0,
		shield = 0,
		scatterShotCount = 0,
		ghostTimer = 0,
		ramTimer = 0,
		homingShotCount = 0,
		superBounceTimer = 0,
		mineCount = 0,
		dashCooldown = 0,
		blockTimer = 0,
		blockCooldown = 0,
		thrustRamp = 0,
		input = { thrust = 0, turn = 0 },
	}
	
	bots[botId] = {
		difficulty = currentDifficulty,
		aiTimer = 0,           -- countdown to next AI decision
		targetId = nil,        -- userId of target we're chasing
		wanderAngle = math.random() * math.pi * 2,
		fireCooldown = 0,      -- seconds until bot can fire again
		respawning = false,
		-- Smooth steering state (updated every frame, not just on decision ticks)
		desiredAngle = math.random() * math.pi * 2,  -- where we want to face
		desiredThrust = 0,     -- target thrust 0→1 (smoothly interpolated)
		smoothTurn = 0,        -- current smooth turn value -1→1
		smoothThrust = 0,      -- current smooth thrust value 0→1
		strafeTimer = 0,       -- timer for strafing maneuvers during combat
		strafeDir = 1,         -- 1 or -1
		orbitDir = 1,          -- clockwise or counter-clockwise orbiting
		behaviorState = "wander", -- "wander" | "approach" | "orbit" | "flee"
		stateTimer = 0,        -- how long we've been in current behavior
	}
	
	print("[BotService] Added bot", botId, "difficulty:", currentDifficulty)
	return botId
end

--[[
	Remove a specific bot.
]]
function BotService.removeBot(botId: number)
	local ships = ShipService.getShips()
	ships[botId] = nil
	bots[botId] = nil
	print("[BotService] Removed bot", botId)
end

--[[
	Remove all bots.
]]
function BotService.removeAllBots()
	local ships = ShipService.getShips()
	for botId, _ in bots do
		ships[botId] = nil
	end
	table.clear(bots)
	print("[BotService] Removed all bots")
end

--[[
	Set difficulty for new bots and update existing ones.
]]
function BotService.setDifficulty(diff: string)
	if not DIFFICULTY[diff] then return end
	currentDifficulty = diff
	-- Update existing bots
	for _, bot in bots do
		bot.difficulty = diff
	end
	print("[BotService] Difficulty set to", diff)
end

function BotService.getDifficulty(): string
	return currentDifficulty
end

function BotService.getBotCount(): number
	local count = 0
	for _ in bots do count = count + 1 end
	return count
end

--[[
	Enable/disable race mode behavior for bots.
	In race mode bots: face NORTH (rotation = 0), full thrust, with slight wobble.
	They do not shoot or chase players.
]]
function BotService.setRaceMode(enabled: boolean)
	raceMode = enabled
	print("[BotService] Race mode:", enabled)
end

function BotService.isRaceMode(): boolean
	return raceMode
end

--[[
	Race-mode update: simple straight-line racer AI.
]]
local function updateRaceMode(deltaTime: number)
	local ships = ShipService.getShips()
	for botId, bot in bots do
		local ship = ships[botId]
		if not ship then continue end
		if ship.health <= 0 then continue end

		-- Wobble target angle slightly so bots don't all overlap
		bot.aiTimer = bot.aiTimer - deltaTime
		if bot.aiTimer <= 0 then
			bot.aiTimer = 0.6 + math.random() * 0.6
			-- Desired angle: roughly 0 (north) with +/- small wobble
			bot.desiredAngle = (math.random() - 0.5) * 0.5   -- +/- 0.25 rad
		end

		-- Steer toward desiredAngle
		local currentAngle = ship.rotation
		local diff = normalizeAngle(bot.desiredAngle - currentAngle)
		local turnTarget = math.clamp(diff * 1.5, -1, 1)
		bot.smoothTurn = lerpNum(bot.smoothTurn, turnTarget, 6, deltaTime)
		bot.smoothThrust = lerpNum(bot.smoothThrust, 1, 3, deltaTime)
		ship.input.turn = bot.smoothTurn
		ship.input.thrust = bot.smoothThrust
	end
end

--[[
	AI update — called every server frame.
	
	Decision-making happens on a timer (reaction time), but the actual
	input (thrust/turn) is smoothly interpolated EVERY frame so bots
	ease into turns and accelerate gradually — just like a real player.
]]
function BotService.update(deltaTime: number)
	if raceMode then
		updateRaceMode(deltaTime)
		return
	end

	local ships = ShipService.getShips()
	
	for botId, bot in bots do
		local ship = ships[botId]
		if not ship then
			-- Bot ship was destroyed, handle respawn
			if not bot.respawning then
				bot.respawning = true
				task.delay(3, function()
					if bots[botId] then
						bot.respawning = false
						BotService.respawnBot(botId)
					end
				end)
			end
			continue
		end
		
		if ship.health <= 0 then continue end
		
		-- Keep bots stocked with ammo (they can't pick up crates)
		if ship.ammo <= 2 then
			ship.ammo = Constants.MAX_AMMO
		end
		
		local profile = DIFFICULTY[bot.difficulty] or DIFFICULTY.medium
		
		-- Tick fire cooldown
		bot.fireCooldown = math.max(0, bot.fireCooldown - deltaTime)
		bot.strafeTimer = math.max(0, bot.strafeTimer - deltaTime)
		bot.stateTimer = bot.stateTimer + deltaTime
		
		-- ============================
		-- DECISION TICK (periodic)
		-- ============================
		bot.aiTimer = bot.aiTimer - deltaTime
		if bot.aiTimer <= 0 then
			bot.aiTimer = profile.reactionTime * (0.8 + math.random() * 0.4)
			
			-- === FIND TARGET ===
			local bestTarget = nil
			local bestDist = profile.engageRange
			
			for uid, other in ships do
				if uid == botId then continue end
				if other.health <= 0 then continue end
				
				local dist = (other.position - ship.position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTarget = uid
				end
			end
			
			bot.targetId = bestTarget
			
			if bestTarget then
				local target = ships[bestTarget]
				if target then
					BotService.decideTargetBehavior(bot, ship, target, profile)
				end
			else
				BotService.decideWander(bot, ship, profile)
			end
			
			-- === FIRE DECISION ===
			if bestTarget and bot.fireCooldown <= 0 and ship.ammo > 0 then
				local target = ships[bestTarget]
				if target and target.health > 0 then
					local dist = (target.position - ship.position).Magnitude
					if dist < 500 then
						if math.random() < profile.fireChance then
							BotService.botFire(botId, ship)
							bot.fireCooldown = 0.4 + math.random() * 0.3
						end
					end
				end
			end
			
			-- === MINE DECISION ===
			if ship.mineCount > 0 and math.random() < profile.mineChance then
				BotService.botDeployMine(botId, ship)
			end
			
			-- Randomly change strafe direction
			if bot.strafeTimer <= 0 then
				bot.strafeDir = math.random() > 0.5 and 1 or -1
				bot.strafeTimer = 1.5 + math.random() * 2.0
			end
		end
		
		-- ============================
		-- EVERY-FRAME SMOOTH STEERING
		-- ============================
		-- Wall avoidance — override desired angle if near edges
		BotService.applyWallAvoidance(bot, ship)
		
		-- Smooth turn: compute angle error, apply proportional steering
		local angleDiff = normalizeAngle(bot.desiredAngle - ship.rotation)
		-- Proportional turn: stronger correction for bigger errors, eased for small ones
		local turnStrength = math.clamp(angleDiff / 1.2, -1, 1)
		-- Add a small deadzone so they don't wobble at the target angle
		if math.abs(angleDiff) < 0.05 then turnStrength = 0 end
		
		-- Smooth interpolation of turn & thrust inputs
		local steerRate = 4.0  -- how quickly inputs change (higher = snappier)
		bot.smoothTurn = lerpNum(bot.smoothTurn, turnStrength, steerRate, deltaTime)
		bot.smoothThrust = lerpNum(bot.smoothThrust, bot.desiredThrust, steerRate * 0.7, deltaTime)
		
		ship.input.turn = math.clamp(bot.smoothTurn, -1, 1)
		ship.input.thrust = math.clamp(bot.smoothThrust, -0.2, 1)
	end
end

--[[
	Decision-level targeting: decide WHAT to do (approach, orbit, flee)
	and set desiredAngle + desiredThrust. Called on decision ticks only.
]]
function BotService.decideTargetBehavior(bot, ship, target, profile)
	local toTarget = target.position - ship.position
	local dist = toTarget.Magnitude
	if dist < 0.1 then return end
	
	-- Lead the target: predict where they'll be based on their velocity
	local leadTime = math.clamp(dist / 400, 0.1, 1.2) * profile.aimAccuracy
	local predictedPos = target.position + target.velocity * leadTime
	local toPredicted = predictedPos - ship.position
	local predictedDist = toPredicted.Magnitude
	if predictedDist < 0.1 then return end
	
	-- Base desired angle toward predicted position
	local desiredAngle = math.atan2(toPredicted.X, -toPredicted.Y)
	
	-- Add inaccuracy based on difficulty
	local inaccuracy = (1 - profile.aimAccuracy) * 0.8
	desiredAngle = desiredAngle + (math.random() - 0.5) * inaccuracy
	
	-- Choose behavior based on distance
	if dist > 600 then
		-- APPROACH: head toward target, full thrust
		bot.behaviorState = "approach"
		bot.desiredAngle = desiredAngle
		bot.desiredThrust = 0.7 + math.random() * 0.3  -- 0.7–1.0
		
	elseif dist > 250 then
		-- ORBIT: circle the target at medium distance for broadside attacks
		bot.behaviorState = "orbit"
		-- Orbit = angle to target + 90° offset (perpendicular)
		local orbitOffset = (math.pi / 2) * bot.orbitDir
		bot.desiredAngle = desiredAngle + orbitOffset * (0.5 + 0.5 * profile.aimAccuracy)
		bot.desiredThrust = 0.5 + math.random() * 0.3  -- moderate speed
		
		-- Occasionally flip orbit direction for unpredictability
		if math.random() < 0.08 then
			bot.orbitDir = -bot.orbitDir
		end
		
	else
		-- CLOSE RANGE: mix between passing through and pulling away
		if ship.health < Constants.SHIP_MAX_HEALTH * 0.3 then
			-- Low health — flee!
			bot.behaviorState = "flee"
			bot.desiredAngle = desiredAngle + math.pi  -- face away
			bot.desiredThrust = 1.0
		else
			-- Aggressive pass-through: aim at target but add slight offset
			bot.behaviorState = "orbit"
			local passOffset = bot.strafeDir * 0.6
			bot.desiredAngle = desiredAngle + passOffset
			bot.desiredThrust = 0.6 + math.random() * 0.4
		end
	end
end

--[[
	Wander AI: smooth meandering when no targets are nearby.
	Varies speed, does gentle S-curves instead of straight lines.
]]
function BotService.decideWander(bot, ship, profile)
	-- Organic drift: add a random small adjustment to wander angle
	-- Use larger changes occasionally for variety
	if math.random() < 0.15 then
		-- Big direction change occasionally
		bot.wanderAngle = bot.wanderAngle + (math.random() - 0.5) * 2.0
	else
		-- Small drift most of the time
		bot.wanderAngle = bot.wanderAngle + (math.random() - 0.5) * 0.4
	end
	
	bot.behaviorState = "wander"
	bot.desiredAngle = bot.wanderAngle
	-- Vary thrust: sometimes cruise, sometimes coast, occasionally stop
	local roll = math.random()
	if roll < 0.1 then
		bot.desiredThrust = 0  -- brief coast
	elseif roll < 0.3 then
		bot.desiredThrust = 0.3 + math.random() * 0.2  -- light cruise
	else
		bot.desiredThrust = 0.5 + math.random() * 0.4  -- normal cruising
	end
end

--[[
	Wall avoidance: gently steer away from map edges.
	Applied every frame so the bot smoothly curves away from walls.
]]
function BotService.applyWallAvoidance(bot, ship)
	local halfW = Constants.MAP_WIDTH / 2
	local halfH = Constants.MAP_HEIGHT / 2
	local margin = 300
	local urgentMargin = 150
	
	local px, py = ship.position.X, ship.position.Y
	local steerX, steerY = 0, 0
	
	-- Soft repulsion from each wall
	if px < -halfW + margin then
		local urgency = 1 - ((px - (-halfW)) / margin)
		steerX = steerX + urgency  -- push right
	elseif px > halfW - margin then
		local urgency = 1 - ((halfW - px) / margin)
		steerX = steerX - urgency  -- push left
	end
	if py < -halfH + margin then
		local urgency = 1 - ((py - (-halfH)) / margin)
		steerY = steerY + urgency  -- push down
	elseif py > halfH - margin then
		local urgency = 1 - ((halfH - py) / margin)
		steerY = steerY - urgency  -- push up
	end
	
	if steerX ~= 0 or steerY ~= 0 then
		local wallAngle = math.atan2(steerX, -steerY)
		local blendStrength = math.clamp(math.sqrt(steerX*steerX + steerY*steerY), 0, 1)
		
		-- Blend wall avoidance angle with current desired angle
		local diff = normalizeAngle(wallAngle - bot.desiredAngle)
		bot.desiredAngle = bot.desiredAngle + diff * blendStrength * 0.7
		
		-- If very close to wall, force more thrust to escape
		local closestEdgeDist = math.min(
			px - (-halfW), halfW - px,
			py - (-halfH), halfH - py
		)
		if closestEdgeDist < urgentMargin then
			bot.desiredThrust = math.max(bot.desiredThrust, 0.8)
		end
	end
end

--[[
	Make a bot fire its cannons (mimics what CombatService.handleFire does for players).
]]
function BotService.botFire(botId, ship)
	if ship.ammo <= 0 then return end
	if ship.health <= 0 then return end
	if ship.ghostTimer > 0 then return end
	
	ship.ammo = ship.ammo - 1
	
	local dirX = math.sin(ship.rotation)
	local dirY = -math.cos(ship.rotation)
	local forward = Vector2.new(dirX, dirY)
	local rightX = math.cos(ship.rotation)
	local rightY = math.sin(ship.rotation)
	local right = Vector2.new(rightX, rightY)
	
	local cannonFiredEvent = EventManager.getEvent("CannonFired")
	local sideOffset = Constants.CANNON_SIDE_OFFSET
	
	-- Use the same fire mode logic as CombatService
	if ship.scatterShotCount > 0 then
		ship.scatterShotCount = ship.scatterShotCount - 1
		local count = Constants.SCATTER_SHOT_COUNT
		local spread = Constants.SCATTER_SHOT_SPREAD
		
		for _, side in { -1, 1 } do
			local sideDir = right * side
			local spawnPos = ship.position + (sideDir * sideOffset)
			local baseAngle = math.atan2(sideDir.X, -sideDir.Y)
			
			for j = 1, count do
				local frac = (j - 1) / math.max(1, count - 1) - 0.5
				local angle = baseAngle + frac * spread
				local projDir = Vector2.new(math.sin(angle), -math.cos(angle))
				local projVelocity = (projDir * Constants.CANNONBALL_SPEED) + (ship.velocity * 0.3)
				
				local id = CombatService.getNextProjectileId()
				CombatService.addProjectile({
					id = id,
					ownerId = botId,
					position = spawnPos,
					velocity = projVelocity,
					age = 0,
					homing = false,
				})
				
				cannonFiredEvent:FireAllClients({
					id = id,
					ownerId = botId,
					px = spawnPos.X,
					py = spawnPos.Y,
					vx = projVelocity.X,
					vy = projVelocity.Y,
					scatter = true,
				})
			end
		end
	elseif ship.homingShotCount > 0 then
		ship.homingShotCount = ship.homingShotCount - 1
		local spawnPos = ship.position + (forward * 30)
		local projVelocity = forward * Constants.CANNONBALL_SPEED
		
		local id = CombatService.getNextProjectileId()
		CombatService.addProjectile({
			id = id,
			ownerId = botId,
			position = spawnPos,
			velocity = projVelocity,
			age = 0,
			homing = true,
		})
		
		cannonFiredEvent:FireAllClients({
			id = id,
			ownerId = botId,
			px = spawnPos.X,
			py = spawnPos.Y,
			vx = projVelocity.X,
			vy = projVelocity.Y,
			homing = true,
		})
	else
		-- Normal broadside fire
		for _, side in { -1, 1 } do
			local sideDir = right * side
			local spawnPos = ship.position + (sideDir * sideOffset)
			local projVelocity = (sideDir * Constants.CANNONBALL_SPEED) + (ship.velocity * 0.3)
			
			local id = CombatService.getNextProjectileId()
			CombatService.addProjectile({
				id = id,
				ownerId = botId,
				position = spawnPos,
				velocity = projVelocity,
				age = 0,
				homing = false,
			})
			
			cannonFiredEvent:FireAllClients({
				id = id,
				ownerId = botId,
				px = spawnPos.X,
				py = spawnPos.Y,
				vx = projVelocity.X,
				vy = projVelocity.Y,
			})
		end
	end
end

--[[
	Make a bot deploy a mine (mimics CombatService.handleDeployMine).
]]
function BotService.botDeployMine(botId, ship)
	if ship.mineCount <= 0 then return end
	if ship.health <= 0 then return end
	
	ship.mineCount = ship.mineCount - 1
	
	local dirX = math.sin(ship.rotation)
	local dirY = -math.cos(ship.rotation)
	local behindX = ship.position.X - dirX * Constants.MINE_DROP_OFFSET
	local behindY = ship.position.Y - dirY * Constants.MINE_DROP_OFFSET
	
	local id = CombatService.getNextMineId()
	CombatService.addMine({
		id = id,
		ownerId = botId,
		position = Vector2.new(behindX, behindY),
		age = 0,
	})
	
	local deployEvent = EventManager.getEvent("MineDeployed")
	deployEvent:FireAllClients({
		id = id,
		ownerId = botId,
		px = behindX,
		py = behindY,
	})
end

--[[
	Respawn a dead bot.
]]
function BotService.respawnBot(botId)
	local ships = ShipService.getShips()
	
	local halfW = Constants.MAP_WIDTH / 2
	local halfH = Constants.MAP_HEIGHT / 2
	local spawnX = math.random(-halfW * 0.6, halfW * 0.6)
	local spawnY = math.random(-halfH * 0.6, halfH * 0.6)
	
	ships[botId] = {
		position = Vector2.new(spawnX, spawnY),
		velocity = Vector2.new(0, 0),
		rotation = math.random() * math.pi * 2,
		angularVelocity = 0,
		health = Constants.SHIP_MAX_HEALTH,
		ammo = Constants.MAX_AMMO,
		speedBoostTimer = 0,
		speedBoostStacks = 0,
		damageBoostTimer = 0,
		shield = 0,
		scatterShotCount = 0,
		ghostTimer = 0,
		ramTimer = 0,
		homingShotCount = 0,
		superBounceTimer = 0,
		mineCount = 0,
		dashCooldown = 0,
		blockTimer = 0,
		blockCooldown = 0,
		thrustRamp = 0,
		input = { thrust = 0, turn = 0 },
	}
	
	-- Reset bot AI steering state
	local bot = bots[botId]
	if bot then
		bot.smoothTurn = 0
		bot.smoothThrust = 0
		bot.desiredThrust = 0
		bot.desiredAngle = math.random() * math.pi * 2
		bot.wanderAngle = math.random() * math.pi * 2
		bot.behaviorState = "wander"
		bot.stateTimer = 0
		bot.targetId = nil
	end
	
	print("[BotService] Respawned bot", botId)
end

return BotService
