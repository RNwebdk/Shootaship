--[[
	RaceService (Server)
	====================
	Implements an isolated "Race" game mode.

	Rules:
	  - Ships spawn on a horizontal start line facing DOWN (rotation = pi).
	  - A 3-2-1-GO countdown locks input. Then ships must turn around
	    and race NORTH (negative Y).
	  - The screen follows the LEADER (highest-up ship = smallest Y).
	  - A horizontal "kill line" trails behind the leader at
	    Constants.RACE_KILL_BEHIND world units. Any ship behind it is
	    eliminated.
	  - Static rock obstacles deal RACE_ROCK_DAMAGE on collision.
	  - Last ship alive wins, then the race auto-resets.

	State machine: WAITING -> COUNTDOWN -> RACING -> FINISHED -> (reset)
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ShipService
local BotService

local RaceService = {}

-- Internal state
local racers = {}        -- [userId] = true ; who is currently in the race
local placements = {}    -- ordered list of userIds (1 = winner, last = first eliminated)
local rocks = {}         -- list of { x, y, r }
local phase = "WAITING"  -- "WAITING" | "COUNTDOWN" | "RACING" | "FINISHED"
local phaseTimer = 0     -- seconds remaining in current phase
local countdownStep = 0  -- counts 3,2,1,0(GO)
local lastCountdownTick = 0
local leaderId = nil
local leaderboardTimer = 0

local LEADER_BROADCAST_HZ = 15  -- send leader update 15x/sec
local LEADER_BROADCAST_INTERVAL = 1 / LEADER_BROADCAST_HZ

-- =========================================================================
-- HELPERS
-- =========================================================================

local function getAlive(): { [number]: any }
	local ships = ShipService.getShips()
	local alive = {}
	for uid in racers do
		local s = ships[uid]
		if s and s.health > 0 then
			alive[uid] = s
		end
	end
	return alive
end

local function countAlive(): number
	local n = 0
	for _ in getAlive() do
		n += 1
	end
	return n
end

local function findLeader(): (number?, any?)
	local bestId, bestY, bestShip = nil, math.huge, nil
	for uid, s in getAlive() do
		if s.position.Y < bestY then
			bestY = s.position.Y
			bestId = uid
			bestShip = s
		end
	end
	return bestId, bestShip
end

local function generateRocks()
	rocks = {}
	-- Scatter rocks down the racing corridor.
	-- Corridor X range: [-1200, 1200], Y range: [+700 .. -1200]
	local count = Constants.RACE_ROCK_COUNT
	for i = 1, count do
		local t = (i - 1) / math.max(1, count - 1)
		local yBase = 700 - t * 1900   -- 700 down to -1200
		local y = yBase + math.random(-80, 80)
		local x = math.random(-1100, 1100)
		table.insert(rocks, { x = x, y = y, r = Constants.RACE_ROCK_RADIUS })
	end
end

local function broadcastStartConfig()
	local ev = EventManager.getEvent("RaceStartConfig")
	ev:FireAllClients({
		rocks = rocks,
		startY = Constants.RACE_START_Y,
		finishY = Constants.RACE_FINISH_Y,
		killBehind = Constants.RACE_KILL_BEHIND,
	})
end

local function broadcastCountdown(step: number)
	local ev = EventManager.getEvent("RaceCountdown")
	ev:FireAllClients(step)  -- 3, 2, 1, then 0 = GO
end

local function broadcastEliminated(userId: number, placement: number, name: string)
	local ev = EventManager.getEvent("RaceEliminated")
	ev:FireAllClients({ userId = userId, placement = placement, name = name })
end

local function broadcastFinished(winnerId: number?, winnerName: string?)
	local ev = EventManager.getEvent("RaceFinished")
	ev:FireAllClients({ winnerId = winnerId, winnerName = winnerName })
end

local function broadcastLeaderUpdate()
	if not leaderId then return end
	local ships = ShipService.getShips()
	local leader = ships[leaderId]
	if not leader then return end
	local killLineY = leader.position.Y + Constants.RACE_KILL_BEHIND
	-- Build rankings (sorted by Y ascending = leader first)
	local rank = {}
	for uid, s in getAlive() do
		table.insert(rank, { userId = uid, y = s.position.Y })
	end
	table.sort(rank, function(a, b) return a.y < b.y end)
	local ev = EventManager.getEvent("RaceLeaderUpdate")
	ev:FireAllClients({
		leaderId = leaderId,
		leaderX = leader.position.X,
		leaderY = leader.position.Y,
		leaderVX = leader.velocity.X,
		leaderVY = leader.velocity.Y,
		killLineY = killLineY,
		rankings = rank,
	})
end

local function nameForUserId(userId: number): string
	if userId < 0 then
		return "Bot " .. tostring(-userId)
	end
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Name or ("User " .. userId)
end

local function getRacerCount(): number
	local n = 0
	for _ in racers do n += 1 end
	return n
end

-- Place ship at the start line at index i out of total
local function placeAtStart(ship, index: number, total: number)
	local spacing = Constants.RACE_SPACING
	-- Center the row of ships around X = 0
	local offset = (index - 1) - (total - 1) / 2
	ship.position = Vector2.new(offset * spacing, Constants.RACE_START_Y)
	ship.velocity = Vector2.new(0, 0)
	ship.rotation = math.pi  -- facing DOWN
	ship.angularVelocity = 0
	ship.input.thrust = 0
	ship.input.turn = 0
	ship.health = Constants.SHIP_MAX_HEALTH
	ship.thrustRamp = 0
end

local function setupGrid()
	local ships = ShipService.getShips()
	local ids = {}
	for uid in racers do
		if ships[uid] then
			table.insert(ids, uid)
		end
	end
	table.sort(ids)  -- deterministic ordering
	local total = #ids
	for i, uid in ipairs(ids) do
		placeAtStart(ships[uid], i, total)
	end
end

local function eliminate(userId: number)
	if not racers[userId] then return end
	local ships = ShipService.getShips()
	local ship = ships[userId]
	local alive = countAlive()
	local placement = alive  -- the eliminated player finishes in "alive" place
	racers[userId] = nil
	table.insert(placements, 1, userId)  -- prepend (so winner ends up first)
	if ship then
		ship.health = 0
		ships[userId] = nil
	end
	print(string.format("[RaceService] Eliminated %s (placement %d)", nameForUserId(userId), placement))
	broadcastEliminated(userId, placement, nameForUserId(userId))
end

local function finishRace()
	phase = "FINISHED"
	phaseTimer = Constants.RACE_FINISH_DELAY

	-- Whoever is still alive is the winner
	local winnerId = nil
	for uid in racers do
		winnerId = uid
		break
	end
	local winnerName = winnerId and nameForUserId(winnerId) or nil
	if winnerId then
		table.insert(placements, 1, winnerId)
	end
	print("[RaceService] Race finished. Winner:", winnerName or "(none)")
	broadcastFinished(winnerId, winnerName)
end

-- =========================================================================
-- PHASE TRANSITIONS
-- =========================================================================

local function startCountdown()
	phase = "COUNTDOWN"
	countdownStep = 3
	phaseTimer = Constants.RACE_COUNTDOWN_INTERVAL * 4  -- 3 -> 2 -> 1 -> GO
	lastCountdownTick = 0
	leaderId = nil
	placements = {}
	setupGrid()
	broadcastCountdown(3)
end

local function startRacing()
	phase = "RACING"
	phaseTimer = 0
	broadcastCountdown(0)  -- GO!
	-- Pick initial leader (the first one to ever be ahead)
	leaderId = nil
	for uid in racers do
		leaderId = uid
		break
	end
end

local function resetRace()
	-- Re-add all bot ships that were eliminated, and re-add living players
	local ships = ShipService.getShips()

	-- Wipe old race state
	racers = {}
	placements = {}
	leaderId = nil

	-- Refill bots if BotService is in race mode
	if BotService and BotService.isRaceMode and BotService.isRaceMode() then
		BotService.removeAllBots()
		for _ = 1, Constants.RACE_BOT_COUNT do
			local botId = BotService.addBot()
			racers[botId] = true
		end
	end

	-- Add all current players (those whose ships exist)
	for _, player in Players:GetPlayers() do
		if ships[player.UserId] then
			racers[player.UserId] = true
		end
	end

	generateRocks()
	broadcastStartConfig()
	startCountdown()
end

-- =========================================================================
-- PUBLIC API
-- =========================================================================

function RaceService.init()
	ShipService = require(script.Parent.ShipService)
	BotService = require(script.Parent.BotService)

	math.randomseed(os.time())
	racers = {}
	placements = {}
	phase = "WAITING"
	print("[RaceService] Initialized")
end

-- Called by LobbyService to add a player to the active race
function RaceService.addPlayer(player: Player)
	-- Make sure the player has a ship
	if not ShipService.getShips()[player.UserId] then
		ShipService.spawnShip(player)
	end
	racers[player.UserId] = true
	print("[RaceService] Added player", player.Name)

	-- If we're idle (e.g. first player joined), start the round
	if phase == "WAITING" then
		resetRace()
	end
end

-- Called by LobbyService AFTER addPlayer to manually kick off the round
-- (used for the single-player Studio test).
function RaceService.beginRound()
	resetRace()
end

-- Runs BEFORE ShipService.update each heartbeat.
-- During COUNTDOWN we keep ships frozen even if input was sent.
function RaceService.preUpdate(_deltaTime: number)
	if phase ~= "COUNTDOWN" then return end
	local ships = ShipService.getShips()
	for uid in racers do
		local s = ships[uid]
		if s then
			s.velocity = Vector2.new(0, 0)
			s.angularVelocity = 0
			s.input.thrust = 0
			s.input.turn = 0
			s.thrustRamp = 0
			-- Lock rotation to face south
			s.rotation = math.pi
		end
	end
end

function RaceService.update(deltaTime: number)
	if phase == "WAITING" then
		return
	end

	if phase == "COUNTDOWN" then
		phaseTimer -= deltaTime
		lastCountdownTick += deltaTime
		if lastCountdownTick >= Constants.RACE_COUNTDOWN_INTERVAL then
			lastCountdownTick = 0
			countdownStep -= 1
			if countdownStep > 0 then
				broadcastCountdown(countdownStep)
			else
				startRacing()
			end
		end
		return
	end

	if phase == "RACING" then
		local ships = ShipService.getShips()

		-- Find leader
		local newLeaderId, leader = findLeader()
		leaderId = newLeaderId
		if not leader then
			-- Everyone eliminated somehow
			finishRace()
			return
		end

		-- Kill-line check
		local killY = leader.position.Y + Constants.RACE_KILL_BEHIND
		local toEliminate = {}
		for uid, s in getAlive() do
			if uid == leaderId then continue end
			if s.position.Y > killY then
				table.insert(toEliminate, uid)
			end
		end
		for _, uid in toEliminate do
			eliminate(uid)
		end

		-- Rock collision check
		for uid, s in getAlive() do
			for _, rock in rocks do
				local dx = s.position.X - rock.x
				local dy = s.position.Y - rock.y
				local distSq = dx * dx + dy * dy
				local hitRad = rock.r + 25  -- approximate ship collision radius
				if distSq <= hitRad * hitRad then
					-- Damage
					s.health = math.max(0, s.health - Constants.RACE_ROCK_DAMAGE * deltaTime * 4)
					-- Knockback (away from rock center)
					local dist = math.sqrt(distSq)
					if dist > 0.01 then
						local nx = dx / dist
						local ny = dy / dist
						s.velocity = Vector2.new(nx * Constants.RACE_ROCK_KNOCKBACK, ny * Constants.RACE_ROCK_KNOCKBACK)
					end
					if s.health <= 0 then
						eliminate(uid)
						break
					end
				end
			end
		end

		-- Win condition
		if countAlive() <= 1 then
			finishRace()
			return
		end

		-- Broadcast leader update at fixed rate
		leaderboardTimer += deltaTime
		if leaderboardTimer >= LEADER_BROADCAST_INTERVAL then
			leaderboardTimer = 0
			broadcastLeaderUpdate()
		end

		return
	end

	if phase == "FINISHED" then
		phaseTimer -= deltaTime
		if phaseTimer <= 0 then
			resetRace()
		end
		return
	end
end

function RaceService.getPhase(): string
	return phase
end

return RaceService
