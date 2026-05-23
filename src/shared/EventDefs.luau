--[[
	EventDefs (Event Definitions)
	=============================
	This module defines ALL RemoteEvents used in the game.
	
	WHY a central list?
	  - Single source of truth: both client and server reference the same names
	  - Easy to see all network messages at a glance
	  - Prevents typos (you get an error if a name doesn't exist)
	
	HOW RemoteEvents work:
	  RemoteEvents are Roblox's way to send messages between client and server.
	  Think of them like named WebSocket channels:
	  
	  Client → Server:  event:FireServer(data)       -- like POST /api/action
	  Server → Client:  event:FireClient(player, data)  -- like ws.send(message)
	  Server → All:     event:FireAllClients(data)      -- like io.emit(event)
	
	  They live in ReplicatedStorage so both sides can find them.
]]

-- Each key is an event name. The value describes its purpose (for documentation).
-- The actual RemoteEvent objects are created at runtime by the server.
local EventDefs = {
	-- Player input → server
	PlayerInput = "Client sends movement input (thrust, turn direction) to server",

	-- Ship state sync
	ShipStateSync = "Server sends all ship positions/velocities to all clients",

	-- Combat
	FireCannon = "Client requests to fire a cannon (left or right)",
	CannonFired = "Server tells all clients a cannon was fired (for visual effects)",
	ShipDamaged = "Server tells all clients a ship took damage",
	ShipDestroyed = "Server tells all clients a ship was destroyed",

	-- Crates
	CrateSpawned = "Server tells all clients a new crate appeared",
	CrateCollected = "Server tells all clients a crate was picked up",

	-- Power-ups
	PowerUpSpawned = "Server tells all clients a power-up crate appeared",
	PowerUpCollected = "Server tells all clients a power-up was picked up",

	-- Wall bounce
	ShipBounced = "Server tells all clients a ship bounced off a wall",

	-- Movement abilities
	Dash = "Client requests a dash burst in the facing direction",

	-- Mines
	DeployMine = "Client requests to drop a naval mine behind their ship",
	MineDeployed = "Server tells all clients a mine was placed",
	MineExploded = "Server tells all clients a mine exploded",

	-- Block / Shockwave
	Block = "Client requests to activate block shockwave (F key)",
	BlockActivated = "Server tells all clients a ship activated its block shockwave",

	-- Dev sandbox
	DevCommand = "Client sends a dev command to the server (spawn crate, apply powerup, etc.)",
	DevResponse = "Server sends dev panel data back to requesting client",

	-- Game flow
	RoundStarting = "Server tells all clients a new round is starting",
	RoundEnded = "Server tells all clients the round is over (with winner)",
	PlayerSpawned = "Server tells a specific client their ship has been created",

	-- ========================
	-- LOBBY / MATCHMAKING
	-- ========================
	ServerMode = "Server tells client which mode it's in: hub, game, or sandbox",
	RequestGameList = "Client asks hub server for current public game listings",
	GameListUpdate = "Server sends array of active games to client",
	CreateGame = "Client requests to create a new public game with settings",
	JoinGame = "Client requests to join a public game by ID",
	TeleportReady = "Server tells client a teleport is about to happen",

	-- ========================
	-- DEATHMATCH (in-game)
	-- ========================
	GameConfig = "Server sends game settings to all clients on join",
	ScoreUpdate = "Server sends updated kill scores to all clients",
	GameOver = "Server tells all clients the game is over with winner info",
	HostAction = "Client (host) sends a game action: restart, setKillTarget, endGame",
	LeaveGame = "Any client requests to leave the game and return to the main menu",
	SwitchMode = "Server tells a specific client to switch mode (hub, game, sandbox)",

	-- ========================
	-- SANDBOX
	-- ========================
	CreateSandbox = "Admin client requests to create a sandbox server",
	InviteToSandbox = "Admin invites a player (by userId) to their sandbox",
	SandboxInvite = "Server tells a player they've been invited to a sandbox",
	AcceptSandboxInvite = "Client accepts a sandbox invite",

	-- ========================
	-- PLAYER LIST (for invite UI)
	-- ========================
	RequestPlayerList = "Client asks for list of players in the hub",
	PlayerListUpdate = "Server sends list of players in the hub",

	-- ========================
	-- RACE MODE
	-- ========================
	RaceStartConfig = "Server sends obstacle positions and finish-line info at race start",
	RaceCountdown = "Server sends countdown step (3/2/1 or 0=GO)",
	RaceLeaderUpdate = "Server sends leader position, kill-line Y, and rankings each tick",
	RaceEliminated = "Server tells clients a ship was eliminated (with placement)",
	RaceFinished = "Server tells clients the race is over with the winner",
}

return EventDefs
