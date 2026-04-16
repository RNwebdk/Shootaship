--[[
	Server Entry Point
	==================
	This is the MAIN server script. It runs once when the game starts.
	
	In Roblox, "server" means the authoritative game host.
	The server:
	  - Controls the "truth" of the game state
	  - Validates all player actions (anti-cheat)
	  - Manages spawning, damage, scoring
	  - Sends updates to clients via RemoteEvents
	
	Think of it like a backend API server in web dev.
	
	MODES:
	  - Hub (PrivateServerId == ""): Main menu server, runs LobbyService only
	  - Game (PrivateServerId ~= ""): Gameplay server, runs all game services
	
	BOOT ORDER matters:
	  1. Create RemoteEvents (so clients can find them)
	  2. Detect mode (hub vs game)
	  3. Initialize services for that mode
	  4. Start the game loop
]]

----- Roblox Services -----
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- This is a 2D GUI game — we don't need the default 3D character at all.
Players.CharacterAutoLoads = false

----- Our Modules -----
local EventManager = require(ReplicatedStorage.Shared.EventManager)

----- Step 1: Create RemoteEvents -----
EventManager.createEvents()

----- Step 2: Detect Mode & publish it as a persistent StringValue -----
-- Using a StringValue instead of a RemoteEvent so the client can read it
-- at any time (no race condition — WaitForChild always works).
local isHub = game.PrivateServerId == ""

local modeValue = Instance.new("StringValue")
modeValue.Name = "ServerMode"
modeValue.Value = isHub and "hub" or "game"
modeValue.Parent = ReplicatedStorage

if isHub then
	-------------------------------
	-- HUB MODE: Main menu only
	-------------------------------
	local LobbyService = require(script.Services.LobbyService)
	
	LobbyService.init()
	
	RunService.Heartbeat:Connect(function(deltaTime: number)
		LobbyService.update(deltaTime)
	end)
	
	print("[Server] Shootaship HUB server started successfully!")
else
	-------------------------------
	-- GAME MODE: Full gameplay
	-------------------------------
	local ShipService = require(script.Services.ShipService)
	local CombatService = require(script.Services.CombatService)
	local CrateService = require(script.Services.CrateService)
	local GameService = require(script.Services.GameService)
	local DevService = require(script.Services.DevService)
	local BotService = require(script.Services.BotService)
	
	ShipService.init()
	CombatService.init()
	CrateService.init()
	GameService.init()
	DevService.init()
	BotService.init()
	
	RunService.Heartbeat:Connect(function(deltaTime: number)
		ShipService.update(deltaTime)
		CombatService.update(deltaTime)
		CrateService.update(deltaTime)
		GameService.update(deltaTime)
		DevService.update(deltaTime)
		BotService.update(deltaTime)
	end)
	
	print("[Server] Shootaship GAME server started successfully!")
end
