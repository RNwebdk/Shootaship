--[[
	DevService (Server)
	===================
	Handles dev sandbox commands from the client DevPanel.
	Allows spawning specific crates, applying power-ups directly,
	adjusting ship stats, clearing the map, etc.
	
	THIS IS FOR DEVELOPMENT ONLY — remove before shipping.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ShipService
local CrateService
local CombatService
local BotService

local DevService = {}

function DevService.init()
	ShipService = require(script.Parent.ShipService)
	CrateService = require(script.Parent.CrateService)
	CombatService = require(script.Parent.CombatService)
	BotService = require(script.Parent.BotService)
	
	local devEvent = EventManager.getEvent("DevCommand")
	
	devEvent.OnServerEvent:Connect(function(player: Player, cmd)
		if typeof(cmd) ~= "table" then return end
		if typeof(cmd.action) ~= "string" then return end
		
		-- Admin gate: only allow "Synt4xify"
		if player.Name ~= "Synt4xify" then
			warn("[DevService] Unauthorized dev command from", player.Name)
			return
		end
		
		DevService.handleCommand(player, cmd)
	end)
	
	print("[DevService] Initialized (sandbox mode)")
end

function DevService.handleCommand(player: Player, cmd)
	local ships = ShipService.getShips()
	local ship = ships[player.UserId]
	local action = cmd.action
	
	-- Spawn a specific power-up type near the player
	if action == "spawnPowerUp" then
		local powerType = cmd.powerType
		if typeof(powerType) ~= "string" then return end
		
		local x, y = 0, 0
		if ship then
			-- Spawn 80 units in front of the ship
			local dirX = math.sin(ship.rotation)
			local dirY = -math.cos(ship.rotation)
			x = ship.position.X + dirX * 80
			y = ship.position.Y + dirY * 80
		end
		
		local crates = CrateService.getPowerUps()
		local nextId = #crates + 1000 + math.random(1, 9999)
		
		table.insert(crates, {
			id = nextId,
			position = Vector2.new(x, y),
			powerType = powerType,
		})
		
		local spawnEvent = EventManager.getEvent("PowerUpSpawned")
		spawnEvent:FireAllClients({
			id = nextId,
			px = x,
			py = y,
			powerType = powerType,
		})
		
	-- Spawn an ammo crate near the player
	elseif action == "spawnAmmo" then
		local x, y = 0, 0
		if ship then
			local dirX = math.sin(ship.rotation)
			local dirY = -math.cos(ship.rotation)
			x = ship.position.X + dirX * 80
			y = ship.position.Y + dirY * 80
		end
		
		local crates = CrateService.getCrates()
		local nextId = #crates + 2000 + math.random(1, 9999)
		
		table.insert(crates, {
			id = nextId,
			position = Vector2.new(x, y),
		})
		
		local spawnEvent = EventManager.getEvent("CrateSpawned")
		spawnEvent:FireAllClients({
			id = nextId,
			px = x,
			py = y,
			crateType = "ammo",
		})
		
	-- Apply a power-up directly to the player's ship
	elseif action == "applyPowerUp" then
		if not ship then return end
		local powerType = cmd.powerType
		if typeof(powerType) ~= "string" then return end
		
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
			ship.health = Constants.SHIP_MAX_HEALTH
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
		end
		
	-- Set ship stats directly
	elseif action == "setHealth" then
		if not ship then return end
		local val = tonumber(cmd.value)
		if val then ship.health = math.clamp(val, 1, Constants.SHIP_MAX_HEALTH) end
		
	elseif action == "setAmmo" then
		if not ship then return end
		local val = tonumber(cmd.value)
		if val then ship.ammo = math.clamp(val, 0, 99) end
		
	elseif action == "setSpeed" then
		local val = tonumber(cmd.value)
		if val then Constants.SHIP_MAX_SPEED = math.clamp(val, 100, 3000) end
		
	-- Clear all crates/powerups from the map
	elseif action == "clearMap" then
		local crates = CrateService.getCrates()
		local powerups = CrateService.getPowerUps()
		
		local collectEvent = EventManager.getEvent("CrateCollected")
		local puCollectEvent = EventManager.getEvent("PowerUpCollected")
		
		for _, crate in crates do
			collectEvent:FireAllClients({ crateId = crate.id, playerId = 0, crateType = "ammo" })
		end
		for _, pu in powerups do
			puCollectEvent:FireAllClients({ crateId = pu.id, playerId = 0, powerType = pu.powerType })
		end
		
		table.clear(crates)
		table.clear(powerups)
		
	-- Teleport to center
	elseif action == "teleportCenter" then
		if not ship then return end
		ship.position = Vector2.new(0, 0)
		ship.velocity = Vector2.new(0, 0)
		
	-- God mode (full health + full ammo)
	elseif action == "godMode" then
		if not ship then return end
		ship.health = Constants.SHIP_MAX_HEALTH
		ship.ammo = Constants.MAX_AMMO
		ship.shield = 99
	
	-- Clear all mines
	elseif action == "clearMines" then
		local mines = CombatService.getMines()
		local explodeEvent = EventManager.getEvent("MineExploded")
		for _, mine in mines do
			explodeEvent:FireAllClients({
				id = mine.id,
				px = mine.position.X,
				py = mine.position.Y,
				despawn = true,
			})
		end
		table.clear(mines)
	
	-- Reset kills for the requesting player
	elseif action == "resetKills" then
		ShipService.resetAllKills()
	
	-- Bot controls
	elseif action == "addBot" then
		BotService.addBot()
	
	elseif action == "removeBot" then
		-- Remove the most recently added bot
		local ships = ShipService.getShips()
		local lastBotId = nil
		for uid, _ in ships do
			if uid < 0 then
				if not lastBotId or uid < lastBotId then
					lastBotId = uid
				end
			end
		end
		if lastBotId then
			BotService.removeBot(lastBotId)
		end
	
	elseif action == "removeAllBots" then
		BotService.removeAllBots()
	
	elseif action == "setBotDifficulty" then
		local diff = cmd.difficulty
		if typeof(diff) == "string" then
			BotService.setDifficulty(diff)
		end
	
	-- Crate spawn controls
	elseif action == "setMaxCrates" then
		local val = tonumber(cmd.value)
		if val then
			CrateService.setMaxCrates(val)
			-- Respond with current value so client can update display
			local responseEvent = EventManager.getEvent("DevResponse")
			responseEvent:FireClient(player, { key = "maxCrates", value = CrateService.getMaxCrates() })
		end
	
	elseif action == "setMaxPowerups" then
		local val = tonumber(cmd.value)
		if val then
			CrateService.setMaxPowerups(val)
			local responseEvent = EventManager.getEvent("DevResponse")
			responseEvent:FireClient(player, { key = "maxPowerups", value = CrateService.getMaxPowerups() })
		end
	
	elseif action == "getCrateConfig" then
		local responseEvent = EventManager.getEvent("DevResponse")
		responseEvent:FireClient(player, { key = "maxCrates", value = CrateService.getMaxCrates() })
		responseEvent:FireClient(player, { key = "maxPowerups", value = CrateService.getMaxPowerups() })
	
	-- Fire a cannonball directly at the player (for testing block/shockwave)
	elseif action == "fireAtMe" then
		if not ship then return end
		local spawnDist = 300  -- spawn 300 units away, heading toward the player
		-- Pick a random direction to fire FROM
		local angle = math.random() * math.pi * 2
		local fromX = ship.position.X + math.cos(angle) * spawnDist
		local fromY = ship.position.Y + math.sin(angle) * spawnDist
		local spawnPos = Vector2.new(fromX, fromY)
		-- Aim directly at the player's current position
		local toPlayer = (ship.position - spawnPos)
		if toPlayer.Magnitude > 0.1 then
			toPlayer = toPlayer.Unit
		end
		local projVelocity = toPlayer * Constants.CANNONBALL_SPEED
		
		local projId = CombatService.getNextProjectileId()
		CombatService.addProjectile({
			id = projId,
			ownerId = -9999,  -- fake owner so it can hit the player
			position = spawnPos,
			velocity = projVelocity,
			age = 0,
			homing = false,
		})
		
		local cannonFiredEvent = EventManager.getEvent("CannonFired")
		cannonFiredEvent:FireAllClients({
			id = projId,
			ownerId = -9999,
			px = fromX,
			py = fromY,
			vx = projVelocity.X,
			vy = projVelocity.Y,
		})
	end
end

function DevService.update(_deltaTime: number)
	-- No per-frame logic needed
end

return DevService
