--[[
	Client Entry Point
	==================
	This script runs on EACH player's machine when they join the game.
	
	The client waits for a ServerMode event from the server to determine
	which mode to run in:
	  - "hub": Show the main menu (create/browse/join games)
	  - "game": Full gameplay (ships, combat, HUDs)
	  - "sandbox": Full gameplay + dev panel
	
	BOOT ORDER:
	  1. Wait for RemoteEvents to exist (server creates them)
	  2. Wait for ServerMode event to know which mode we're in
	  3. Initialize the appropriate controllers
	  4. Start the render loop (game/sandbox modes only)
]]

----- Roblox Services -----
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for the server to create the Events folder.
ReplicatedStorage:WaitForChild("Events", 15)

----- Read Server Mode -----
-- The server publishes a StringValue "ServerMode" in ReplicatedStorage.
-- Using WaitForChild is race-condition-free (unlike RemoteEvents).
local modeValue = ReplicatedStorage:WaitForChild("ServerMode", 10)
local serverMode = (modeValue and modeValue.Value) or "hub"

if not modeValue then
	warn("[Client] ServerMode not found within 10s, defaulting to hub mode")
end

print("[Client] Detected server mode:", serverMode)

-- All gameplay ScreenGui names (used for cleanup)
local GAMEPLAY_GUIS = {
	"ShootashipUI", "AmmoHUD", "HealthHUD", "KillsHUD",
	"ScoreHUDGui", "HostMenuGui", "LeaderboardUI", "DevPanel", "LeaveGameGui",
}

-- Function to boot all gameplay controllers; returns a cleanup function
local function bootGameplay(isSandbox: boolean): () -> ()
	local Players = game:GetService("Players")
	local EventManager = require(ReplicatedStorage.Shared.EventManager)

	local InputController = require(script.Controllers.InputController)
	local ViewportController = require(script.Controllers.ViewportController)
	local ShipController = require(script.Controllers.ShipController)
	local ProjectileController = require(script.Controllers.ProjectileController)
	local CrateController = require(script.Controllers.CrateController)
	local AmmoHUD = require(script.Controllers.AmmoHUD)
	local HealthHUD = require(script.Controllers.HealthHUD)
	local MineController = require(script.Controllers.MineController)
	local KillsHUD = require(script.Controllers.KillsHUD)
	local Leaderboard = require(script.Controllers.Leaderboard)
	local ScoreHUD = require(script.Controllers.ScoreHUD)
	local HostMenu = require(script.Controllers.HostMenu)

	InputController.init()
	ViewportController.init()
	ShipController.init()
	ProjectileController.init()
	CrateController.init()
	AmmoHUD.init()
	HealthHUD.init()
	MineController.init()
	KillsHUD.init()
	Leaderboard.init()
	ScoreHUD.init()
	HostMenu.init()

	-- DevPanel: init if sandbox, or listen for GameConfig to detect sandbox later
	local devPanelLoaded = false
	local function tryLoadDevPanel()
		if devPanelLoaded then return end
		devPanelLoaded = true
		local DevPanel = require(script.Controllers.DevPanel)
		DevPanel.init()
		print("[Client] DevPanel loaded (sandbox mode)")
	end

	if isSandbox then
		tryLoadDevPanel()
	end

	local configEvent = EventManager.waitForEvent("GameConfig")
	configEvent.OnClientEvent:Connect(function(config)
		if config and config.isSandbox then
			tryLoadDevPanel()
		end
	end)

	-- "Leave Game" button (top-left)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local leaveGui = Instance.new("ScreenGui")
	leaveGui.Name = "LeaveGameGui"
	leaveGui.ResetOnSpawn = false
	leaveGui.DisplayOrder = 100
	leaveGui.Parent = playerGui

	local leaveBtn = Instance.new("TextButton")
	leaveBtn.Name = "LeaveButton"
	leaveBtn.Size = UDim2.new(0, 120, 0, 36)
	leaveBtn.Position = UDim2.new(0, 12, 0, 12)
	leaveBtn.AnchorPoint = Vector2.new(0, 0)
	leaveBtn.BackgroundColor3 = Color3.fromHex("#da3633")
	leaveBtn.TextColor3 = Color3.fromHex("#ffffff")
	leaveBtn.Text = "← Leave Game"
	leaveBtn.Font = Enum.Font.GothamBold
	leaveBtn.TextSize = 14
	leaveBtn.BorderSizePixel = 0
	leaveBtn.Parent = leaveGui

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = leaveBtn

	leaveBtn.MouseButton1Click:Connect(function()
		local leaveEvent = EventManager.getEvent("LeaveGame")
		leaveEvent:FireServer()
	end)

	-- Render loop
	local renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		ViewportController.update(deltaTime)
		ShipController.update(deltaTime)
		ProjectileController.update(deltaTime)
		MineController.update(deltaTime)
	end)

	-- Return cleanup function
	return function()
		renderConnection:Disconnect()
		for _, guiName in GAMEPLAY_GUIS do
			local gui = playerGui:FindFirstChild(guiName)
			if gui then
				gui:Destroy()
			end
		end
		print("[Client] Gameplay cleaned up")
	end
end

----- Initialize Based on Mode -----
if serverMode == "hub" then
	-------------------------------
	-- HUB MODE: Main menu only
	-------------------------------
	local MainMenu = require(script.Controllers.MainMenu)
	local EventManager = require(ReplicatedStorage.Shared.EventManager)
	MainMenu.init()

	-- Track the cleanup function from bootGameplay so we can tear down later
	local cleanupGameplay = nil

	local function switchToGame(newMode: string)
		if cleanupGameplay then return end -- already in game
		print("[Client] Switching to", newMode, "mode")
		MainMenu.destroy()
		cleanupGameplay = bootGameplay(newMode == "sandbox")
		print("[Client] Switched to", newMode:upper(), "mode!")
	end

	local function switchToHub()
		if not cleanupGameplay then return end -- already in hub
		print("[Client] Returning to main menu")
		cleanupGameplay()
		cleanupGameplay = nil
		MainMenu.init()
		print("[Client] Back in HUB mode!")
	end

	-- Listen for per-player SwitchMode event (Studio multi-player)
	local switchModeEvent = EventManager.waitForEvent("SwitchMode")
	switchModeEvent.OnClientEvent:Connect(function(newMode: string)
		if newMode == "game" or newMode == "sandbox" then
			switchToGame(newMode)
		elseif newMode == "hub" then
			switchToHub()
		end
	end)

	-- Also watch StringValue changes (fallback for production mode transitions)
	if modeValue then
		modeValue.Changed:Connect(function(newMode)
			if newMode == "game" or newMode == "sandbox" then
				switchToGame(newMode)
			elseif newMode == "hub" then
				switchToHub()
			end
		end)
	end

	print("[Client] Shootaship client started in HUB mode!")

else
	-------------------------------
	-- GAME / SANDBOX MODE: Full gameplay
	-------------------------------
	bootGameplay(serverMode == "sandbox")
	print("[Client] Shootaship client started in", serverMode:upper(), "mode!")
end
