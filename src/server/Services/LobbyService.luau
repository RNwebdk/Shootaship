--[[
	LobbyService (Server — Hub Mode Only)
	======================================
	Manages the main menu experience: game creation, browsing, joining,
	and sandbox invites. Only runs on hub servers (PrivateServerId == "").

	Uses MemoryStoreService to share active game listings across all
	hub server instances, and TeleportService to move players between servers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local LobbyService = {}

-- MemoryStore: not available in Studio, so we wrap it safely
local gameListMap = nil
local isStudio = RunService:IsStudio()

if not isStudio then
	local ok, map = pcall(function()
		local MemoryStoreService = game:GetService("MemoryStoreService")
		return MemoryStoreService:GetSortedMap("ActiveGames")
	end)
	if ok then
		gameListMap = map
	else
		warn("[LobbyService] MemoryStoreService not available, running in local-only mode")
	end
end

-- Local cache of game listings (refreshed periodically)
local cachedGameList = {}
local listRefreshTimer = 0

-- Sandbox tracking: adminUserId → accessCode
local sandboxCodes = {}

-- Studio-only: local game list (since MemoryStore doesn't work in Studio)
local studioGames = {} -- gameId → { hostName, hostId, playerCount, maxPlayers, killTarget, status }
local studioServicesBooted = false

-- Generate a short readable game ID
local function generateGameId()
	return HttpService:GenerateGUID(false):sub(1, 8):upper()
end

function LobbyService.init()
	-- Server mode is communicated via the "ServerMode" StringValue in
	-- ReplicatedStorage (set by init.server.luau). No event needed.

	-- === CREATE GAME ===
	local createEvent = EventManager.getEvent("CreateGame")
	createEvent.OnServerEvent:Connect(function(player: Player, settings)
		if typeof(settings) ~= "table" then return end

		local killTarget = math.clamp(tonumber(settings.killTarget) or Constants.DEFAULT_KILL_TARGET, 1, 100)
		local maxPlayers = math.clamp(tonumber(settings.maxPlayers) or Constants.MAX_PLAYERS_PER_GAME, 2, Constants.MAX_PLAYERS_PER_GAME)

		local gameId = generateGameId()

		if isStudio then
			-- Studio can only run one game at a time (single server)
			if studioServicesBooted then
				warn("[LobbyService] Studio: game already running — join the existing one instead")
				return
			end
			if settings.gameMode == "race" then
				LobbyService._startLocalRace(player, gameId, maxPlayers)
			else
				LobbyService._startLocalGame(player, gameId, killTarget, maxPlayers)
			end
			return
		end

		-- Reserve a server for this game
		local success, accessCode = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)

		if not success then
			warn("[LobbyService] Failed to reserve server:", accessCode)
			return
		end

		-- Store game listing in MemoryStore
		local gameEntry = {
			gameId = gameId,
			hostName = player.Name,
			hostId = player.UserId,
			playerCount = 1,
			maxPlayers = maxPlayers,
			killTarget = killTarget,
			accessCode = accessCode,
			status = "waiting",
		}

		if gameListMap then
			pcall(function()
				gameListMap:SetAsync(gameId, HttpService:JSONEncode(gameEntry), Constants.GAME_ENTRY_TTL)
			end)
		end

		-- Teleport the host to the reserved server
		local teleportData = {
			gameId = gameId,
			killTarget = killTarget,
			maxPlayers = maxPlayers,
			hostId = player.UserId,
			isSandbox = false,
		}

		local teleportReadyEvent = EventManager.getEvent("TeleportReady")
		teleportReadyEvent:FireClient(player, { gameId = gameId })

		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, accessCode, { player }, nil, teleportData)
		end)

		print("[LobbyService]", player.Name, "created game", gameId, "| Kill target:", killTarget, "| Max:", maxPlayers)
	end)

	-- === JOIN GAME ===
	local joinEvent = EventManager.getEvent("JoinGame")
	joinEvent.OnServerEvent:Connect(function(player: Player, data)
		if typeof(data) ~= "table" then return end
		local gameId = data.gameId
		if typeof(gameId) ~= "string" then return end

		if isStudio then
			-- Studio: join the local game via GameService.addPlayer
			local game_entry = studioGames[gameId]
			if not game_entry then
				warn("[LobbyService] Studio game not found:", gameId)
				return
			end
			if game_entry.playerCount >= game_entry.maxPlayers then
				warn("[LobbyService] Studio game full:", gameId)
				return
			end

			local GameService = require(script.Parent.GameService)
			GameService.addPlayer(player)
			game_entry.playerCount = game_entry.playerCount + 1
			LobbyService._broadcastStudioGameList()
			print("[LobbyService]", player.Name, "joined studio game", gameId)
			return
		end

		if not gameListMap then return end

		-- Look up the game in MemoryStore
		local success, rawEntry = pcall(function()
			return gameListMap:GetAsync(gameId)
		end)

		if not success or not rawEntry then
			warn("[LobbyService] Game not found:", gameId)
			return
		end

		local gameEntry = HttpService:JSONDecode(rawEntry)

		if gameEntry.playerCount >= gameEntry.maxPlayers then
			warn("[LobbyService] Game full:", gameId)
			return
		end

		local teleportReadyEvent = EventManager.getEvent("TeleportReady")
		teleportReadyEvent:FireClient(player, { gameId = gameId })

		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, gameEntry.accessCode, { player })
		end)

		print("[LobbyService]", player.Name, "joining game", gameId)
	end)

	-- === REQUEST GAME LIST ===
	local requestListEvent = EventManager.getEvent("RequestGameList")
	requestListEvent.OnServerEvent:Connect(function(player: Player)
		local gameListEvent = EventManager.getEvent("GameListUpdate")
		if isStudio then
			-- Return the local studio game list
			local list = {}
			for _, entry in studioGames do
				table.insert(list, entry)
			end
			gameListEvent:FireClient(player, list)
		else
			gameListEvent:FireClient(player, cachedGameList)
		end
	end)

	-- === CREATE SANDBOX (admin only) ===
	local createSandboxEvent = EventManager.getEvent("CreateSandbox")
	createSandboxEvent.OnServerEvent:Connect(function(player: Player)
		if player.Name ~= Constants.ADMIN_NAME then return end

		if isStudio then
			-- In Studio: switch to sandbox mode locally
			LobbyService._startLocalSandbox(player)
			return
		end

		local success, accessCode = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)

		if not success then
			warn("[LobbyService] Failed to reserve sandbox server:", accessCode)
			return
		end

		-- Store sandbox code for invites
		sandboxCodes[player.UserId] = accessCode

		local teleportData = {
			isSandbox = true,
			hostId = player.UserId,
			killTarget = Constants.DEFAULT_KILL_TARGET,
			maxPlayers = Constants.MAX_PLAYERS_PER_GAME,
		}

		local teleportReadyEvent = EventManager.getEvent("TeleportReady")
		teleportReadyEvent:FireClient(player, { sandbox = true })

		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, accessCode, { player }, nil, teleportData)
		end)

		print("[LobbyService]", player.Name, "entered sandbox")
	end)

	-- === INVITE TO SANDBOX ===
	local inviteEvent = EventManager.getEvent("InviteToSandbox")
	inviteEvent.OnServerEvent:Connect(function(player: Player, data)
		if player.Name ~= Constants.ADMIN_NAME then return end
		if typeof(data) ~= "table" then return end

		local targetUserId = tonumber(data.targetUserId)
		if not targetUserId then return end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then return end

		local accessCode = sandboxCodes[player.UserId]
		if not accessCode then
			warn("[LobbyService] No sandbox active for", player.Name)
			return
		end

		-- Send invite to target player
		local sandboxInviteEvent = EventManager.getEvent("SandboxInvite")
		sandboxInviteEvent:FireClient(targetPlayer, {
			hostName = player.Name,
			hostId = player.UserId,
		})

		print("[LobbyService]", player.Name, "invited", targetPlayer.Name, "to sandbox")
	end)

	-- === ACCEPT SANDBOX INVITE ===
	local acceptEvent = EventManager.getEvent("AcceptSandboxInvite")
	acceptEvent.OnServerEvent:Connect(function(player: Player, data)
		if typeof(data) ~= "table" then return end

		local hostId = tonumber(data.hostId)
		if not hostId then return end

		local accessCode = sandboxCodes[hostId]
		if not accessCode then
			warn("[LobbyService] Sandbox no longer active for host", hostId)
			return
		end

		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, accessCode, { player })
		end)

		print("[LobbyService]", player.Name, "accepted sandbox invite")
	end)

	-- === PLAYER LIST (for sandbox invite UI) ===
	local requestPlayerListEvent = EventManager.getEvent("RequestPlayerList")
	requestPlayerListEvent.OnServerEvent:Connect(function(player: Player)
		if player.Name ~= Constants.ADMIN_NAME then return end

		local playerList = {}
		for _, p in Players:GetPlayers() do
			if p.UserId ~= player.UserId then
				table.insert(playerList, {
					userId = p.UserId,
					name = p.Name,
					displayName = p.DisplayName,
				})
			end
		end

		local playerListEvent = EventManager.getEvent("PlayerListUpdate")
		playerListEvent:FireClient(player, playerList)
	end)

	print("[LobbyService] Initialized (hub mode)")
end

function LobbyService.update(deltaTime: number)
	-- MemoryStore not available in Studio — skip refresh
	if not gameListMap then return end

	-- Periodically refresh the game list from MemoryStore
	listRefreshTimer = listRefreshTimer + deltaTime
	if listRefreshTimer < Constants.GAME_LIST_REFRESH then return end
	listRefreshTimer = 0

	-- Fetch all active games from MemoryStore
	local success, items = pcall(function()
		return gameListMap:GetRangeAsync(Enum.SortDirection.Ascending, 50)
	end)

	if not success or not items then return end

	local newList = {}
	for _, item in items do
		local ok, entry = pcall(function()
			return HttpService:JSONDecode(item.value)
		end)
		if ok and entry then
			-- Don't expose access codes to clients
			table.insert(newList, {
				gameId = entry.gameId,
				hostName = entry.hostName,
				playerCount = entry.playerCount,
				maxPlayers = entry.maxPlayers,
				killTarget = entry.killTarget,
				status = entry.status,
			})
		end
	end

	cachedGameList = newList

	-- Broadcast to all connected hub players
	local gameListEvent = EventManager.getEvent("GameListUpdate")
	gameListEvent:FireAllClients(cachedGameList)
end

--[[
	Studio-only: Start a game locally without TeleportService.
	Boots up all gameplay services in the same server instance,
	switches the mode StringValue, and tells the client to reload.
]]
function LobbyService._startLocalGame(player: Player, gameId: string, killTarget: number, maxPlayers: number)
	print("[LobbyService] Starting LOCAL game (Studio mode) for", player.Name)

	-- Add to local game list so other players can see and join
	studioGames[gameId] = {
		gameId = gameId,
		hostName = player.DisplayName or player.Name,
		hostId = player.UserId,
		playerCount = 1,
		maxPlayers = maxPlayers,
		killTarget = killTarget,
		status = "waiting",
	}

	-- Broadcast updated game list to all hub players
	LobbyService._broadcastStudioGameList()

	-- Boot game services once (shared across all local games)
	if not studioServicesBooted then
		studioServicesBooted = true

		local ShipService = require(script.Parent.ShipService)
		local CombatService = require(script.Parent.CombatService)
		local CrateService = require(script.Parent.CrateService)
		local GameService = require(script.Parent.GameService)
		local DevService = require(script.Parent.DevService)
		local BotService = require(script.Parent.BotService)

		ShipService.init()
		CombatService.init()
		CrateService.init()
		DevService.init()
		BotService.init()

		-- Inject config
		GameService._studioConfig = {
			gameId = gameId,
			killTarget = killTarget,
			maxPlayers = maxPlayers,
			hostId = player.UserId,
			isSandbox = false,
		}
		GameService.init()

		-- Start the game loop
		GameService._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
			ShipService.update(deltaTime)
			CombatService.update(deltaTime)
			CrateService.update(deltaTime)
			GameService.update(deltaTime)
			DevService.update(deltaTime)
			BotService.update(deltaTime)
		end)
	end

	-- Add this player to the game (fires SwitchMode and GameConfig to them)
	local GameService = require(script.Parent.GameService)
	GameService.addPlayer(player)

	print("[LobbyService] Local game started! GameId:", gameId)
end

function LobbyService._startLocalSandbox(player: Player)
	print("[LobbyService] Starting LOCAL sandbox (Studio mode) for", player.Name)

	-- Boot game services once (idempotent via studioServicesBooted flag)
	if not studioServicesBooted then
		studioServicesBooted = true

		local ShipService = require(script.Parent.ShipService)
		local CombatService = require(script.Parent.CombatService)
		local CrateService = require(script.Parent.CrateService)
		local GameService = require(script.Parent.GameService)
		local DevService = require(script.Parent.DevService)
		local BotService = require(script.Parent.BotService)

		ShipService.init()
		CombatService.init()
		CrateService.init()
		DevService.init()
		BotService.init()

		GameService._studioConfig = {
			gameId = "SANDBOX",
			killTarget = Constants.DEFAULT_KILL_TARGET,
			maxPlayers = Constants.MAX_PLAYERS_PER_GAME,
			hostId = player.UserId,
			isSandbox = true,
		}
		GameService.init()

		GameService._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
			ShipService.update(deltaTime)
			CombatService.update(deltaTime)
			CrateService.update(deltaTime)
			GameService.update(deltaTime)
			DevService.update(deltaTime)
			BotService.update(deltaTime)
		end)
	end

	-- Add this player to the game
	local GameService = require(script.Parent.GameService)
	GameService.addPlayer(player)

	print("[LobbyService] Local sandbox started!")
end

--[[
	Start a local Race mode game (Studio only).
	Boots ShipService + BotService + RaceService and adds the player.
]]
function LobbyService._startLocalRace(player: Player, gameId: string, maxPlayers: number)
	print("[LobbyService] Starting LOCAL race (Studio mode) for", player.Name)

	if not studioServicesBooted then
		studioServicesBooted = true

		local ShipService = require(script.Parent.ShipService)
		local BotService = require(script.Parent.BotService)
		local RaceService = require(script.Parent.RaceService)
		local GameService = require(script.Parent.GameService)

		ShipService.init()
		BotService.init()
		RaceService.init()

		-- Stub a minimal GameService config so existing events (GameConfig, SwitchMode) still work.
		GameService._studioConfig = {
			gameId = gameId,
			killTarget = 0,
			maxPlayers = maxPlayers,
			hostId = player.UserId,
			isSandbox = false,
			isRace = true,
		}
		GameService.init()

		-- Enable bot race AI and spawn race bots
		BotService.setRaceMode(true)

		GameService._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
			-- preUpdate runs BEFORE ShipService.update so we can lock ships during countdown
			RaceService.preUpdate(deltaTime)
			ShipService.update(deltaTime)
			BotService.update(deltaTime)
			RaceService.update(deltaTime)
			GameService.update(deltaTime)
		end)
	end

	-- Add player to the underlying GameService (sends SwitchMode "race")
	local GameService = require(script.Parent.GameService)
	GameService.addPlayer(player)

	-- Register them with the race
	local RaceService = require(script.Parent.RaceService)
	RaceService.addPlayer(player)

	print("[LobbyService] Local race started! GameId:", gameId)
end

-- Broadcast the studio game list to all connected players (for the menu)
function LobbyService._broadcastStudioGameList()
	local list = {}
	for _, entry in studioGames do
		table.insert(list, entry)
	end
	local gameListEvent = EventManager.getEvent("GameListUpdate")
	gameListEvent:FireAllClients(list)
end

-- Remove a game from the studio game list and allow new games to be created
function LobbyService._removeStudioGame(gameId: string)
	studioGames[gameId] = nil
	studioServicesBooted = false  -- allow a new game to boot services again
	LobbyService._broadcastStudioGameList()
	print("[LobbyService] Removed studio game:", gameId)
end

return LobbyService
