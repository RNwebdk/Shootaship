--[[
	RaceController (Client)
	========================
	Handles all race-mode UI:
	  - Countdown overlay (3 / 2 / 1 / GO)
	  - Position indicator ("1st of 5")
	  - Kill-line (horizontal red bar on the canvas)
	  - Static rock obstacles (gray circles on the canvas)
	  - Elimination overlay (red tint + placement)
	  - Winner overlay
	  - Camera follow-leader mode handoff to ViewportController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ViewportController

local RaceController = {}

local localPlayer = Players.LocalPlayer

local hudGui: ScreenGui? = nil
local countdownLabel: TextLabel? = nil
local positionLabel: TextLabel? = nil
local raceBadge: TextLabel? = nil
local hintLabel: TextLabel? = nil
local eliminatedFrame: Frame? = nil
local winnerFrame: Frame? = nil

local killLine: Frame? = nil
local rockFrames: { Frame } = {}

local localEliminated = false
local hintTimer = 0
local HINT_DURATION = 6

-- ====================================================================
-- HUD CONSTRUCTION
-- ====================================================================

local function makeLabel(parent: Instance, text: string, size: UDim2, pos: UDim2, fontSize: number, color: Color3): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = size
	lbl.Position = pos
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = fontSize
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Parent = parent
	return lbl
end

local function buildHud()
	if hudGui then return end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "RaceHUD"
	hudGui.ResetOnSpawn = false
	hudGui.IgnoreGuiInset = true
	hudGui.DisplayOrder = 50
	hudGui.Parent = playerGui

	-- Countdown overlay (big centered text)
	countdownLabel = makeLabel(hudGui, "", UDim2.new(0, 480, 0, 200), UDim2.new(0.5, 0, 0.45, 0), 140, Color3.fromRGB(255, 220, 80))
	countdownLabel.Visible = false

	-- Position indicator (top center)
	positionLabel = makeLabel(hudGui, "", UDim2.new(0, 320, 0, 56), UDim2.new(0.5, 0, 0, 40), 28, Color3.fromRGB(255, 255, 255))

	-- RACE badge (top right)
	raceBadge = makeLabel(hudGui, "RACE", UDim2.new(0, 160, 0, 36), UDim2.new(1, -100, 0, 32), 22, Color3.fromRGB(255, 80, 80))

	-- Direction hint
	hintLabel = makeLabel(hudGui, "TURN AROUND AND GO NORTH!", UDim2.new(0, 600, 0, 50), UDim2.new(0.5, 0, 0.8, 0), 26, Color3.fromRGB(120, 240, 255))
	hintLabel.Visible = false

	-- Elimination overlay
	eliminatedFrame = Instance.new("Frame")
	eliminatedFrame.Size = UDim2.new(1, 0, 1, 0)
	eliminatedFrame.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
	eliminatedFrame.BackgroundTransparency = 0.55
	eliminatedFrame.Visible = false
	eliminatedFrame.ZIndex = 5
	eliminatedFrame.Parent = hudGui
	local elLabel = makeLabel(eliminatedFrame, "ELIMINATED", UDim2.new(0, 800, 0, 100), UDim2.new(0.5, 0, 0.4, 0), 64, Color3.fromRGB(255, 80, 80))
	elLabel.ZIndex = 6
	local elPlace = Instance.new("TextLabel")
	elPlace.Name = "Placement"
	elPlace.Size = UDim2.new(0, 600, 0, 60)
	elPlace.Position = UDim2.new(0.5, 0, 0.5, 0)
	elPlace.AnchorPoint = Vector2.new(0.5, 0.5)
	elPlace.BackgroundTransparency = 1
	elPlace.Font = Enum.Font.GothamBold
	elPlace.TextSize = 36
	elPlace.TextColor3 = Color3.fromRGB(255, 255, 255)
	elPlace.TextStrokeTransparency = 0.3
	elPlace.Text = ""
	elPlace.ZIndex = 6
	elPlace.Parent = eliminatedFrame

	-- Winner overlay
	winnerFrame = Instance.new("Frame")
	winnerFrame.Size = UDim2.new(1, 0, 1, 0)
	winnerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	winnerFrame.BackgroundTransparency = 0.5
	winnerFrame.Visible = false
	winnerFrame.ZIndex = 8
	winnerFrame.Parent = hudGui
	local wLabel = makeLabel(winnerFrame, "RACE OVER", UDim2.new(0, 700, 0, 100), UDim2.new(0.5, 0, 0.38, 0), 72, Color3.fromRGB(255, 220, 80))
	wLabel.ZIndex = 9
	local wWinner = Instance.new("TextLabel")
	wWinner.Name = "Winner"
	wWinner.Size = UDim2.new(0, 800, 0, 60)
	wWinner.Position = UDim2.new(0.5, 0, 0.52, 0)
	wWinner.AnchorPoint = Vector2.new(0.5, 0.5)
	wWinner.BackgroundTransparency = 1
	wWinner.Font = Enum.Font.GothamBold
	wWinner.TextSize = 38
	wWinner.TextColor3 = Color3.fromRGB(255, 255, 255)
	wWinner.TextStrokeTransparency = 0.3
	wWinner.Text = ""
	wWinner.ZIndex = 9
	wWinner.Parent = winnerFrame
end

-- ====================================================================
-- CANVAS-SPACE VISUALS (kill-line, rocks)
-- ====================================================================

local function ensureKillLine()
	if killLine then return end
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	killLine = Instance.new("Frame")
	killLine.Name = "RaceKillLine"
	killLine.AnchorPoint = Vector2.new(0, 0.5)
	killLine.Size = UDim2.new(0, Constants.MAP_WIDTH, 0, 6)
	killLine.Position = UDim2.new(0, 0, 0, Constants.MAP_HEIGHT)
	killLine.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	killLine.BackgroundTransparency = 0.15
	killLine.BorderSizePixel = 0
	killLine.ZIndex = 2
	killLine.Visible = false
	killLine.Parent = canvas
end

local function setKillLineY(worldY: number)
	if not killLine then return end
	local canvasY = worldY + Constants.MAP_HEIGHT / 2
	killLine.Position = UDim2.new(0, 0, 0, canvasY)
	killLine.Visible = Constants.RACE_KILLLINE_VISIBLE
end

local function clearRocks()
	for _, frame in rockFrames do
		frame:Destroy()
	end
	rockFrames = {}
end

local function spawnRocks(rocks)
	clearRocks()
	local canvas = ViewportController.getCanvas()
	if not canvas then return end
	for _, rock in rocks do
		local f = Instance.new("Frame")
		f.Name = "RaceRock"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		local diameter = rock.r * 2
		f.Size = UDim2.new(0, diameter, 0, diameter)
		local canvasX = rock.x + Constants.MAP_WIDTH / 2
		local canvasY = rock.y + Constants.MAP_HEIGHT / 2
		f.Position = UDim2.new(0, canvasX, 0, canvasY)
		f.BackgroundColor3 = Color3.fromRGB(80, 78, 70)
		f.BorderSizePixel = 0
		f.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 38, 32)
		stroke.Parent = f
		f.Parent = canvas
		table.insert(rockFrames, f)
	end
end

-- ====================================================================
-- EVENT HANDLERS
-- ====================================================================

local function onCountdown(step: number)
	if not countdownLabel then return end
	if step == 0 then
		countdownLabel.Text = "GO!"
		countdownLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
		countdownLabel.Visible = true
		task.delay(1.0, function()
			if countdownLabel then countdownLabel.Visible = false end
		end)
		-- Show direction hint
		if hintLabel then
			hintLabel.Visible = true
			hintTimer = HINT_DURATION
		end
		-- Switch camera to leader
		if ViewportController then
			ViewportController.setFollowMode("leader")
		end
	else
		countdownLabel.Text = tostring(step)
		countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
		countdownLabel.Visible = true
	end
end

local function onStartConfig(cfg)
	-- Reset overlays
	localEliminated = false
	if eliminatedFrame then eliminatedFrame.Visible = false end
	if winnerFrame then winnerFrame.Visible = false end
	if hintLabel then hintLabel.Visible = false end
	-- Reset camera to local player until GO fires
	if ViewportController then
		ViewportController.setFollowMode("player")
	end
	ensureKillLine()
	if killLine then killLine.Visible = false end
	if cfg and cfg.rocks then
		spawnRocks(cfg.rocks)
	end
end

local function onLeaderUpdate(data)
	if not data then return end
	-- Update leader-follow camera target
	if ViewportController then
		ViewportController.setLeaderPosition(
			Vector2.new(data.leaderX, data.leaderY),
			Vector2.new(data.leaderVX or 0, data.leaderVY or 0)
		)
	end
	-- Kill-line position
	setKillLineY(data.killLineY)

	-- Update position label
	if positionLabel and data.rankings then
		local total = #data.rankings
		local myPlace = nil
		for i, r in ipairs(data.rankings) do
			if r.userId == localPlayer.UserId then
				myPlace = i
				break
			end
		end
		if myPlace and not localEliminated then
			local suffix = "th"
			if myPlace == 1 then suffix = "st"
			elseif myPlace == 2 then suffix = "nd"
			elseif myPlace == 3 then suffix = "rd"
			end
			positionLabel.Text = string.format("%d%s of %d", myPlace, suffix, total)
		elseif not localEliminated then
			positionLabel.Text = string.format("- of %d", total)
		end
	end
end

local function onEliminated(data)
	if not data then return end
	if data.userId == localPlayer.UserId then
		localEliminated = true
		if eliminatedFrame then
			eliminatedFrame.Visible = true
			local placeLabel = eliminatedFrame:FindFirstChild("Placement")
			if placeLabel and placeLabel:IsA("TextLabel") then
				placeLabel.Text = string.format("You finished in place %d", data.placement)
			end
		end
	end
end

local function onFinished(data)
	if not winnerFrame then return end
	local wLabel = winnerFrame:FindFirstChild("Winner")
	if wLabel and wLabel:IsA("TextLabel") then
		if data and data.winnerName then
			wLabel.Text = "WINNER: " .. data.winnerName
		else
			wLabel.Text = "No winner"
		end
	end
	winnerFrame.Visible = true
	if killLine then killLine.Visible = false end
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

function RaceController.init()
	ViewportController = require(script.Parent.ViewportController)

	buildHud()
	ensureKillLine()

	local startEv = EventManager.waitForEvent("RaceStartConfig")
	startEv.OnClientEvent:Connect(onStartConfig)

	local cdEv = EventManager.waitForEvent("RaceCountdown")
	cdEv.OnClientEvent:Connect(onCountdown)

	local leaderEv = EventManager.waitForEvent("RaceLeaderUpdate")
	leaderEv.OnClientEvent:Connect(onLeaderUpdate)

	local elimEv = EventManager.waitForEvent("RaceEliminated")
	elimEv.OnClientEvent:Connect(onEliminated)

	local finEv = EventManager.waitForEvent("RaceFinished")
	finEv.OnClientEvent:Connect(onFinished)

	print("[RaceController] Initialized")
end

function RaceController.update(deltaTime: number)
	if hintTimer > 0 then
		hintTimer -= deltaTime
		if hintTimer <= 0 and hintLabel then
			hintLabel.Visible = false
		end
	end
end

return RaceController
