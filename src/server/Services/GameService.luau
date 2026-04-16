--[[
	GameService (Server — Game Mode Only)
	======================================
	Manages the deathmatch round lifecycle: waiting for players,
	active round, kill tracking, win detection, and restart.

	Only runs on game servers (PrivateServerId ~= "").
	Reads game config from TeleportData (kill target, max players, host).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local GameService = {}

-- Possible game states
GameService.States = {
	WaitingForPlayers = "WaitingForPlayers",
	RoundActive = "RoundActive",
	RoundOver = "RoundOver",
}

local currentState = GameService.States.WaitingForPlayers

-- Game config (set from TeleportData of first player)
local gameConfig = {
	gameId = nil,
	killTarget = Constants.DEFAULT_KILL_TARGET,
	maxPlayers = Constants.MAX_PLAYERS_PER_GAME,
	hostId = nil,
	isSandbox = false,
}

-- Kill scores: userId → number
local scores = {}

-- Set of players currently in the game (userId → true)
-- In production (dedicated game server), all players are in the game.
-- In Studio, only players who created/joined are tracked here.
local gamePlayers = {}

-- Timers
local roundOverTimer = 0
local memoryRefreshTimer = 0
local waitingTimer = 0
local configReceived = false

-- MemoryStore for updating game listing (deferred to avoid Studio crash)
local RunService = game:GetService("RunService")
local gameListMap = nil
if not RunService:IsStudio() then
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap("ActiveGames")
	end)
	if ok then
		gameListMap = map
	end
end

-- Reference to ShipService (set during init to avoid require timing issues)
local ShipService = nil

-- Get the list of Player objects currently in the game
local function getGamePlayerList(): {Player}
	local list = {}
	-- If no one is explicitly tracked, treat all players as in-game (production servers)
	if not next(gamePlayers) then
		return Players:GetPlayers()
	end
	for userId in gamePlayers do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(list, p)
		end
	end
	return list
end

local function fireToGamePlayers(event, ...)
	for _, p in getGamePlayerList() do
		event:FireClient(p, ...)
	end
end

local function broadcastScores()
	local scoreEvent = EventManager.getEvent("ScoreUpdate")
	local scoreData = {}
	for userId, killCount in scores do
		local player = Players:GetPlayerByUserId(userId)
		scoreData[userId] = {
			kills = killCount,
			name = player and player.Name or ("Player " .. userId),
			displayName = player and player.DisplayName or ("Player " .. userId),
		}
	end
	fireToGamePlayers(scoreEvent, {
		scores = scoreData,
		killTarget = gameConfig.killTarget,
	})
end

local function broadcastConfig()
	local configEvent = EventManager.getEvent("GameConfig")
	fireToGamePlayers(configEvent, {
		killTarget = gameConfig.killTarget,
		maxPlayers = gameConfig.maxPlayers,
		hostId = gameConfig.hostId,
		isSandbox = gameConfig.isSandbox,
		state = currentState,
	})
end

local function refreshMemoryStoreEntry()
	if not gameListMap then return end
	if not gameConfig.gameId then return end
	if gameConfig.isSandbox then return end

	pcall(function()
		local entry = {
			gameId = gameConfig.gameId,
			hostName = "",
			hostId = gameConfig.hostId,
			playerCount = #Players:GetPlayers(),
			maxPlayers = gameConfig.maxPlayers,
			killTarget = gameConfig.killTarget,
			accessCode = "", -- don't need to update this, original set has it
			status = currentState == GameService.States.RoundActive and "playing" or "waiting",
		}

		-- Try to get current entry for host name and access code
		local rawEntry = gameListMap:GetAsync(gameConfig.gameId)
		if rawEntry then
			local existing = HttpService:JSONDecode(rawEntry)
			entry.hostName = existing.hostName or ""
			entry.accessCode = existing.accessCode or ""
		end

		gameListMap:SetAsync(gameConfig.gameId, HttpService:JSONEncode(entry), Constants.GAME_ENTRY_TTL)
	end)
end

local function startRound()
	currentState = GameService.States.RoundActive

	-- Reset all scores
	table.clear(scores)
	for _, player in getGamePlayerList() do
		scores[player.UserId] = 0
	end

	-- Spawn all game players
	if ShipService then
		for _, player in getGamePlayerList() do
			ShipService.spawnShip(player)
		end
	end

	broadcastConfig()
	broadcastScores()
	print("[GameService] Round started! First to", gameConfig.killTarget, "kills wins.")
end

local function endRound(winnerId: number)
	currentState = GameService.States.RoundOver
	roundOverTimer = 0

	local winnerPlayer = Players:GetPlayerByUserId(winnerId)
	local winnerName = winnerPlayer and winnerPlayer.Name or ("Player " .. winnerId)
	local winnerDisplayName = winnerPlayer and winnerPlayer.DisplayName or winnerName

	-- Build final score list
	local finalScores = {}
	for userId, killCount in scores do
		local p = Players:GetPlayerByUserId(userId)
		finalScores[userId] = {
			kills = killCount,
			name = p and p.Name or ("Player " .. userId),
			displayName = p and p.DisplayName or ("Player " .. userId),
		}
	end

	local gameOverEvent = EventManager.getEvent("GameOver")
	fireToGamePlayers(gameOverEvent, {
		winnerId = winnerId,
		winnerName = winnerName,
		winnerDisplayName = winnerDisplayName,
		scores = finalScores,
	})

	print("[GameService] Game over!", winnerDisplayName, "wins with", scores[winnerId], "kills!")
end

function GameService.init()
	-- Check for Studio config injected by LobbyService._startLocalGame()
	if GameService._studioConfig and not configReceived then
		local cfg = GameService._studioConfig
		gameConfig.gameId = cfg.gameId
		gameConfig.killTarget = tonumber(cfg.killTarget) or Constants.DEFAULT_KILL_TARGET
		gameConfig.maxPlayers = tonumber(cfg.maxPlayers) or Constants.MAX_PLAYERS_PER_GAME
		gameConfig.hostId = tonumber(cfg.hostId)
		gameConfig.isSandbox = cfg.isSandbox == true
		configReceived = true
		print("[GameService] Config loaded from Studio injection | Kill target:", gameConfig.killTarget, "| Sandbox:", gameConfig.isSandbox)
	end

	-- Handle new players joining the game server
	Players.PlayerAdded:Connect(function(player: Player)
		-- In Studio, players are managed via addPlayer/removePlayer — skip auto-handling
		if RunService:IsStudio() then return end

		-- Initialize their score
		scores[player.UserId] = 0

		-- Read teleport data (only from first player, who is the host)
		if not configReceived then
			local joinData = player:GetJoinData()
			local teleportData = joinData and joinData.TeleportData

			if teleportData and typeof(teleportData) == "table" then
				gameConfig.gameId = teleportData.gameId
				gameConfig.killTarget = tonumber(teleportData.killTarget) or Constants.DEFAULT_KILL_TARGET
				gameConfig.maxPlayers = tonumber(teleportData.maxPlayers) or Constants.MAX_PLAYERS_PER_GAME
				gameConfig.hostId = tonumber(teleportData.hostId)
				gameConfig.isSandbox = teleportData.isSandbox == true
				configReceived = true

				-- Update the persistent ServerMode StringValue if this is a sandbox
				if gameConfig.isSandbox then
					local modeValue = ReplicatedStorage:FindFirstChild("ServerMode")
					if modeValue then
						modeValue.Value = "sandbox"
					end
				end

				print("[GameService] Config received from", player.Name, "| Kill target:", gameConfig.killTarget, "| Sandbox:", gameConfig.isSandbox)
			end
		end

		-- Send current config
		task.defer(function()
			local configEvent = EventManager.getEvent("GameConfig")
			configEvent:FireClient(player, {
				killTarget = gameConfig.killTarget,
				maxPlayers = gameConfig.maxPlayers,
				hostId = gameConfig.hostId,
				isSandbox = gameConfig.isSandbox,
				state = currentState,
			})

			broadcastScores()
		end)

		-- Auto-start if we hit the minimum players
		if currentState == GameService.States.WaitingForPlayers then
			if #Players:GetPlayers() >= Constants.MIN_PLAYERS_TO_START then
				task.defer(function()
					startRound()
				end)
			end
		elseif currentState == GameService.States.RoundActive then
			-- Late joiner: spawn them into the active round
			if ShipService then
				task.defer(function()
					ShipService.spawnShip(player)
				end)
			end
		end
	end)

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Only handle players that are in the game
		if next(gamePlayers) and not gamePlayers[player.UserId] then return end

		scores[player.UserId] = nil
		gamePlayers[player.UserId] = nil

		-- If host leaves, transfer host to next game player
		if player.UserId == gameConfig.hostId then
			for _, p in getGamePlayerList() do
				if p.UserId ~= player.UserId then
					gameConfig.hostId = p.UserId
					broadcastConfig()
					print("[GameService] Host transferred to", p.Name)
					break
				end
			end
		end

		-- If no game players left, clean up MemoryStore entry
		task.defer(function()
			if #getGamePlayerList() == 0 and gameConfig.gameId and not gameConfig.isSandbox then
				if gameListMap then
					pcall(function()
						gameListMap:RemoveAsync(gameConfig.gameId)
					end)
				end
				print("[GameService] Game", gameConfig.gameId, "removed (empty)")
			end
		end)
	end)

	-- === HOST ACTIONS ===
	local hostActionEvent = EventManager.getEvent("HostAction")
	hostActionEvent.OnServerEvent:Connect(function(player: Player, data)
		if player.UserId ~= gameConfig.hostId then return end
		if typeof(data) ~= "table" then return end

		local action = data.action

		if action == "restart" then
			startRound()

		elseif action == "setKillTarget" then
			local newTarget = math.clamp(tonumber(data.value) or gameConfig.killTarget, 1, 100)
			gameConfig.killTarget = newTarget
			broadcastConfig()
			broadcastScores()
			print("[GameService] Kill target changed to", newTarget, "by", player.Name)

		elseif action == "endGame" then
			-- Teleport everyone back to the hub
			local TeleportService = game:GetService("TeleportService")
			local allPlayers = Players:GetPlayers()

			-- Clean up MemoryStore entry
			if gameConfig.gameId and not gameConfig.isSandbox then
				pcall(function()
					gameListMap:RemoveAsync(gameConfig.gameId)
				end)
			end

			pcall(function()
				TeleportService:Teleport(game.PlaceId, allPlayers)
			end)

			print("[GameService] Game ended by host", player.Name)
		end
	end)

	-- === LEAVE GAME (any player) ===
	local leaveEvent = EventManager.getEvent("LeaveGame")
	leaveEvent.OnServerEvent:Connect(function(player: Player)
		print("[GameService] Leave requested by", player.Name)

		if RunService:IsStudio() then
			-- Studio: remove this player from the game, send them back to hub
			GameService.removePlayer(player)
		else
			-- Production: teleport everyone back to hub
			local TeleportService = game:GetService("TeleportService")
			local allPlayers = getGamePlayerList()

			if gameListMap and gameConfig.gameId and not gameConfig.isSandbox then
				pcall(function()
					gameListMap:RemoveAsync(gameConfig.gameId)
				end)
			end

			pcall(function()
				TeleportService:Teleport(game.PlaceId, allPlayers)
			end)
		end
	end)

	-- Lazy-require ShipService
	ShipService = require(script.Parent.ShipService)

	isActive = true

	-- Handle players already connected (production game server scenario)
	-- In Studio, players are added via addPlayer() from LobbyService instead
	if not RunService:IsStudio() then
		for _, player in Players:GetPlayers() do
			scores[player.UserId] = 0
		end
		if configReceived and #Players:GetPlayers() >= Constants.MIN_PLAYERS_TO_START then
			task.defer(function()
				startRound()
			end)
		end
	end

	print("[GameService] Initialized (game mode) — waiting for players")
end

-- Called by ShipService or CombatService when a ship is destroyed
function GameService.onKill(attackerId: number, targetId: number)
	if currentState ~= GameService.States.RoundActive then return end
	if not attackerId or attackerId == targetId then return end

	scores[attackerId] = (scores[attackerId] or 0) + 1

	broadcastScores()

	-- Check win condition
	if scores[attackerId] >= gameConfig.killTarget then
		endRound(attackerId)
	end
end

-- Track whether the game is active (for Studio shutdown)
local isActive = false

function GameService.update(deltaTime: number)
	if not isActive then return end

	-- Handle round-over timer → auto-restart
	if currentState == GameService.States.RoundOver then
		roundOverTimer = roundOverTimer + deltaTime
		if roundOverTimer >= Constants.WIN_ANNOUNCEMENT_DURATION + Constants.RESTART_COUNTDOWN then
			startRound()
		end
	end

	-- Periodically refresh MemoryStore entry
	memoryRefreshTimer = memoryRefreshTimer + deltaTime
	if memoryRefreshTimer >= Constants.GAME_ENTRY_REFRESH then
		memoryRefreshTimer = 0
		task.spawn(refreshMemoryStoreEntry)
	end
end

-- Shut down the entire game (all players removed, services stopped)
function GameService.shutdown()
	-- Send all game players back to hub
	local switchEvent = EventManager.getEvent("SwitchMode")
	for _, p in getGamePlayerList() do
		switchEvent:FireClient(p, "hub")
	end

	isActive = false
	currentState = GameService.States.WaitingForPlayers
	table.clear(scores)
	table.clear(gamePlayers)
	configReceived = false

	-- Remove from studio game list so the browser stops showing it
	if RunService:IsStudio() and gameConfig.gameId then
		local LobbyService = require(script.Parent.LobbyService)
		LobbyService._removeStudioGame(gameConfig.gameId)
	end

	GameService._studioConfig = nil

	-- Destroy all ships
	if ShipService and ShipService.destroyAllShips then
		ShipService.destroyAllShips()
	end

	-- Disconnect the Heartbeat loop if LobbyService stored it
	if GameService._heartbeatConnection then
		GameService._heartbeatConnection:Disconnect()
		GameService._heartbeatConnection = nil
	end

	print("[GameService] Shut down — game ended")
end

-- Remove a single player from the game (Studio per-player leave)
function GameService.removePlayer(player: Player)
	local userId = player.UserId

	-- Remove their ship
	if ShipService then
		local ships = ShipService.getShips()
		if ships[userId] then
			ships[userId] = nil
		end
	end

	scores[userId] = nil
	gamePlayers[userId] = nil

	-- Send this player back to hub
	local switchEvent = EventManager.getEvent("SwitchMode")
	switchEvent:FireClient(player, "hub")

	-- Check remaining human players directly (don't use getGamePlayerList fallback)
	local remainingCount = 0
	for uid in gamePlayers do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			remainingCount = remainingCount + 1
		end
	end

	-- Transfer host if needed
	if userId == gameConfig.hostId then
		if remainingCount > 0 then
			local remaining = getGamePlayerList()
			if #remaining > 0 then
				gameConfig.hostId = remaining[1].UserId
				broadcastConfig()
				print("[GameService] Host transferred to", remaining[1].Name)
			end
		end
	end

	-- If no human players left, shut down the game
	if remainingCount == 0 then
		GameService.shutdown()
	else
		broadcastScores()
	end

	print("[GameService]", player.Name, "left the game")
end

-- Add a player to the active game (Studio join)
function GameService.addPlayer(player: Player)
	local userId = player.UserId
	gamePlayers[userId] = true
	scores[userId] = 0

	-- Send them the game config
	local configEvent = EventManager.getEvent("GameConfig")
	configEvent:FireClient(player, {
		killTarget = gameConfig.killTarget,
		maxPlayers = gameConfig.maxPlayers,
		hostId = gameConfig.hostId,
		isSandbox = gameConfig.isSandbox,
		state = currentState,
	})

	-- Tell the client to switch to game mode
	local switchEvent = EventManager.getEvent("SwitchMode")
	switchEvent:FireClient(player, gameConfig.isSandbox and "sandbox" or "game")

	-- Sync existing crates/powerups so the new player can see them
	local CrateService = require(script.Parent.CrateService)
	task.defer(function()
		CrateService.syncToPlayer(player)
	end)

	-- If round is active, spawn them in
	if currentState == GameService.States.RoundActive then
		if ShipService then
			task.defer(function()
				ShipService.spawnShip(player)
			end)
		end
	elseif currentState == GameService.States.WaitingForPlayers then
		if #getGamePlayerList() >= Constants.MIN_PLAYERS_TO_START then
			task.defer(function()
				startRound()
			end)
		end
	end

	broadcastScores()
	print("[GameService]", player.Name, "joined the game")
end

function GameService.getState(): string
	return currentState
end

function GameService.getConfig()
	return gameConfig
end

function GameService.getScores()
	return scores
end

-- Public: fire a RemoteEvent only to players in the game (not hub players)
-- Other services (ShipService, CombatService, etc.) use this instead of FireAllClients
function GameService.fireAllGameClients(event, ...)
	for _, p in getGamePlayerList() do
		event:FireClient(p, ...)
	end
end

return GameService
