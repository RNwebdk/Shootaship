--[[
	CrateService (Server)
	=====================
	Spawns two categories of crates on the map:
	  1. Ammo crates (brown) — give cannonball ammo
	  2. Power-up crates (colored) — grant temporary buffs or instant effects
	
	Power-up types:
	  speed (green), damage (red), shield (blue), scatter (purple),
	  repair (yellow), ghost (cyan), ram (orange), ammodump (white), homing (pink)
	
	Server-authoritative:
	  - Server controls spawn timing/positions
	  - Server detects which ship reaches a crate first
	  - Server awards the pickup (client can't cheat)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

-- Lazy requires to avoid circular dependency
local ShipService
local GameService

local CrateService = {}

-- Active ammo crates on the map
local crates = {}
-- Active power-up crates on the map
local powerups = {}

local nextCrateId = 1
local spawnTimer = 0
local powerupTimer = 0

-- Configurable limits (can be changed via DevService)
local maxCrates = Constants.MAX_CRATES
local maxPowerups = Constants.MAX_POWERUPS

-- All possible power-up types (weighted equally)
local POWERUP_TYPES = { "speed", "damage", "shield", "scatter", "repair", "ghost", "ram", "ammodump", "homing", "superbounce", "mine", "machinegun" }

function CrateService.init()
	ShipService = require(script.Parent.ShipService)
	GameService = require(script.Parent.GameService)
	
	-- Spawn a few ammo crates immediately so the map isn't empty
	for _ = 1, 3 do
		CrateService.spawnCrate()
	end
	-- Spawn several power-ups so there's variety on the map
	for _ = 1, 5 do
		CrateService.spawnPowerUp()
	end
	
	print("[CrateService] Initialized")
end

-- Helper: random position on the map (avoid edges)
local function randomMapPosition()
	local halfW = Constants.MAP_WIDTH / 2
	local halfH = Constants.MAP_HEIGHT / 2
	local x = math.random(-halfW * 0.8, halfW * 0.8)
	local y = math.random(-halfH * 0.8, halfH * 0.8)
	return x, y
end

--[[
	Spawns an ammo crate.
]]
function CrateService.spawnCrate()
	if #crates >= maxCrates then return end
	
	local x, y = randomMapPosition()
	local id = nextCrateId
	nextCrateId = nextCrateId + 1
	
	table.insert(crates, {
		id = id,
		position = Vector2.new(x, y),
	})
	
	local spawnEvent = EventManager.getEvent("CrateSpawned")
	local data = {
		id = id,
		px = x,
		py = y,
		crateType = "ammo",
	}
	if GameService then
		GameService.fireAllGameClients(spawnEvent, data)
	else
		spawnEvent:FireAllClients(data)
	end
end

--[[
	Spawns a random power-up crate.
]]
function CrateService.spawnPowerUp()
	if #powerups >= maxPowerups then return end
	
	local x, y = randomMapPosition()
	local id = nextCrateId
	nextCrateId = nextCrateId + 1
	
	local powerType = POWERUP_TYPES[math.random(1, #POWERUP_TYPES)]
	
	table.insert(powerups, {
		id = id,
		position = Vector2.new(x, y),
		powerType = powerType,
	})
	
	local spawnEvent = EventManager.getEvent("PowerUpSpawned")
	local data = {
		id = id,
		px = x,
		py = y,
		powerType = powerType,
	}
	if GameService then
		GameService.fireAllGameClients(spawnEvent, data)
	else
		spawnEvent:FireAllClients(data)
	end
end

--[[
	Apply a power-up effect to a ship.
]]
local function applyPowerUp(ship, powerType)
	if powerType == "speed" then
		ship.speedBoostTimer = ship.speedBoostTimer + Constants.SPEED_BOOST_DURATION
		ship.speedBoostStacks = math.min((ship.speedBoostStacks or 0) + 1, Constants.SPEED_BOOST_MAX_STACKS)
	elseif powerType == "damage" then
		ship.damageBoostTimer = Constants.DAMAGE_BOOST_DURATION
	elseif powerType == "shield" then
		ship.shield = Constants.SHIELD_HITS
	elseif powerType == "scatter" then
		ship.scatterShotCount = ship.scatterShotCount + Constants.SCATTER_SHOT_VOLLEYS
	elseif powerType == "repair" then
		ship.health = math.min(ship.health + Constants.REPAIR_AMOUNT, Constants.SHIP_MAX_HEALTH)
	elseif powerType == "ghost" then
		ship.ghostTimer = Constants.GHOST_DURATION
	elseif powerType == "ram" then
		ship.ramTimer = Constants.RAM_DURATION
	elseif powerType == "ammodump" then
		ship.ammo = Constants.AMMO_DUMP_AMOUNT
	elseif powerType == "homing" then
		ship.homingShotCount = ship.homingShotCount + Constants.HOMING_SHOT_COUNT
	elseif powerType == "superbounce" then
		ship.superBounceTimer = Constants.SUPERBOUNCE_DURATION
	elseif powerType == "mine" then
		ship.mineCount = ship.mineCount + Constants.MINE_COUNT
	elseif powerType == "machinegun" then
		ship.machinegunTimer = ship.machinegunTimer + Constants.MACHINEGUN_DURATION
	end
end

--[[
	Per-frame update: spawn timers + pickup detection for both types.
]]
function CrateService.update(deltaTime: number)
	local ships = ShipService.getShips()
	
	-- Ammo crate spawn timer
	spawnTimer = spawnTimer + deltaTime
	if spawnTimer >= Constants.CRATE_SPAWN_INTERVAL then
		spawnTimer = 0
		CrateService.spawnCrate()
	end
	
	-- Power-up spawn timer
	powerupTimer = powerupTimer + deltaTime
	if powerupTimer >= Constants.POWERUP_SPAWN_INTERVAL then
		powerupTimer = 0
		CrateService.spawnPowerUp()
	end
	
	-- Check ammo crate pickups
	local i = #crates
	while i >= 1 do
		local crate = crates[i]
		local collected = false
		
		for userId, ship in ships do
			if ship.health <= 0 then continue end
			local dist = (ship.position - crate.position).Magnitude
			if dist <= Constants.CRATE_PICKUP_RADIUS then
				ship.ammo = math.min(ship.ammo + Constants.AMMO_PER_CRATE, Constants.MAX_AMMO)
				
				local collectEvent = EventManager.getEvent("CrateCollected")
				GameService.fireAllGameClients(collectEvent, {
					crateId = crate.id,
					playerId = userId,
					newAmmo = ship.ammo,
					crateType = "ammo",
				})
				collected = true
				break
			end
		end
		
		if collected then
			table.remove(crates, i)
		end
		i = i - 1
	end
	
	-- Check power-up crate pickups
	local j = #powerups
	while j >= 1 do
		local pu = powerups[j]
		local collected = false
		
		for userId, ship in ships do
			if ship.health <= 0 then continue end
			local dist = (ship.position - pu.position).Magnitude
			if dist <= Constants.CRATE_PICKUP_RADIUS then
				-- Apply the power-up effect
				applyPowerUp(ship, pu.powerType)
				
				local collectEvent = EventManager.getEvent("PowerUpCollected")
				GameService.fireAllGameClients(collectEvent, {
					crateId = pu.id,
					playerId = userId,
					powerType = pu.powerType,
				})
				collected = true
				break
			end
		end
		
		if collected then
			table.remove(powerups, j)
		end
		j = j - 1
	end
end

function CrateService.getCrates()
	return crates
end

function CrateService.getPowerUps()
	return powerups
end

function CrateService.setMaxCrates(value: number)
	maxCrates = math.clamp(value, 0, 50)
end

function CrateService.setMaxPowerups(value: number)
	maxPowerups = math.clamp(value, 0, 50)
end

function CrateService.getMaxCrates(): number
	return maxCrates
end

function CrateService.getMaxPowerups(): number
	return maxPowerups
end

--[[
	Sync all existing crates/powerups to a specific player who just joined.
	Needed because initial spawns fire before the client connects listeners.
]]
function CrateService.syncToPlayer(player: Player)
	local crateSpawnEvent = EventManager.getEvent("CrateSpawned")
	local puSpawnEvent = EventManager.getEvent("PowerUpSpawned")

	for _, crate in crates do
		crateSpawnEvent:FireClient(player, {
			id = crate.id,
			px = crate.position.X,
			py = crate.position.Y,
			crateType = "ammo",
		})
	end

	for _, pu in powerups do
		puSpawnEvent:FireClient(player, {
			id = pu.id,
			px = pu.position.X,
			py = pu.position.Y,
			powerType = pu.powerType,
		})
	end
end

return CrateService
