--[[
	DevPanel (Client)
	=================
	Development sandbox GUI. Toggle with F9.
	
	Lets you:
	  - Spawn any crate type in front of your ship
	  - Apply any power-up instantly
	  - Set health/ammo
	  - Clear the map
	  - God mode
	  - Teleport to center
	
	THIS IS FOR DEVELOPMENT ONLY — remove before shipping.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local DevPanel = {}

local localPlayer = Players.LocalPlayer
local screenGui = nil
local mainFrame = nil
local isVisible = false
local devEvent = nil

-- All power-up types with labels and colors
local POWERUP_BUTTONS = {
	{ id = "speed",       label = "⚡ Speed",      color = Color3.fromRGB(30, 160, 60) },
	{ id = "damage",      label = "🔥 Damage",     color = Color3.fromRGB(180, 40, 40) },
	{ id = "shield",      label = "🛡 Shield",     color = Color3.fromRGB(40, 80, 200) },
	{ id = "scatter",     label = "* Scatter",     color = Color3.fromRGB(140, 40, 180) },
	{ id = "repair",      label = "❤ Repair",      color = Color3.fromRGB(200, 180, 30) },
	{ id = "ghost",       label = "👻 Ghost",      color = Color3.fromRGB(40, 190, 200) },
	{ id = "ram",         label = "💥 Ram",        color = Color3.fromRGB(220, 120, 20) },
	{ id = "ammodump",    label = "📦 AmmoDump",   color = Color3.fromRGB(200, 200, 210) },
	{ id = "homing",      label = "🎯 Homing",     color = Color3.fromRGB(220, 80, 160) },
	{ id = "superbounce", label = "💢 S.Bounce",   color = Color3.fromRGB(120, 230, 50) },
	{ id = "mine",        label = "💣 Mine",       color = Color3.fromRGB(120, 20, 20) },
}

local UTILITY_BUTTONS = {
	{ id = "spawnAmmo",       label = "📦 Spawn Ammo Crate",  color = Color3.fromRGB(160, 100, 40) },
	{ id = "clearMap",        label = "🧹 Clear All Crates",  color = Color3.fromRGB(100, 100, 100) },
	{ id = "clearMines",      label = "💣 Clear All Mines",   color = Color3.fromRGB(120, 20, 20) },
	{ id = "resetKills",      label = "☠ Reset Kills",       color = Color3.fromRGB(180, 40, 40) },
	{ id = "teleportCenter",  label = "🎯 Teleport Center",   color = Color3.fromRGB(80, 80, 140) },
	{ id = "godMode",         label = "⭐ God Mode",          color = Color3.fromRGB(255, 200, 50) },
	{ id = "fireAtMe",        label = "🎯 Fire At Me",        color = Color3.fromRGB(255, 80, 80) },
}

-- Helper to create a styled button
local function createButton(parent, text, bgColor, size, position, callback)
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundColor3 = bgColor
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	btn.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	
	btn.MouseButton1Click:Connect(callback)
	
	return btn
end

local function sendCmd(cmd)
	if devEvent then
		devEvent:FireServer(cmd)
	end
end

function DevPanel.init()
	-- Admin gate: only allow "Synt4xify" to use dev panel
	if localPlayer.Name ~= "Synt4xify" then
		print("[DevPanel] Not admin — dev panel disabled")
		return
	end
	
	devEvent = EventManager.waitForEvent("DevCommand")
	
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DevPanel"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 100
	screenGui.Parent = playerGui
	
	-- Main panel (left side) — fixed height, content scrolls inside
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "Panel"
	mainFrame.Size = UDim2.new(0, 220, 0, 0)  -- height set after content
	mainFrame.Position = UDim2.new(0, 10, 0, 60)
	mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	mainFrame.BackgroundTransparency = 0.1
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 10)
	mainCorner.Parent = mainFrame
	
	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(60, 60, 80)
	mainStroke.Thickness = 1
	mainStroke.Parent = mainFrame
	
	-- Title (fixed at top, outside scroll)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "🛠 DEV SANDBOX"
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.TextSize = 15
	title.Font = Enum.Font.GothamBold
	title.Parent = mainFrame
	
	-- Scrolling content area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, 0, 1, -30) -- fill below title
	scroll.Position = UDim2.new(0, 0, 0, 30)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 160)
	scroll.ScrollBarImageTransparency = 0.3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- set after content
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.Parent = mainFrame
	
	-- Section: Spawn Crate (drops in front of ship)
	local yOff = 4
	
	local spawnHeader = Instance.new("TextLabel")
	spawnHeader.Size = UDim2.new(1, -16, 0, 20)
	spawnHeader.Position = UDim2.new(0, 8, 0, yOff)
	spawnHeader.BackgroundTransparency = 1
	spawnHeader.Text = "SPAWN CRATE (in front)"
	spawnHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	spawnHeader.TextSize = 11
	spawnHeader.Font = Enum.Font.GothamBold
	spawnHeader.TextXAlignment = Enum.TextXAlignment.Left
	spawnHeader.Parent = scroll
	yOff = yOff + 22
	
	-- Power-up spawn buttons (2 columns)
	local col = 0
	local row = 0
	local btnW = UDim2.new(0, 96, 0, 28)
	
	for _, pu in POWERUP_BUTTONS do
		local xPos = 8 + col * 104
		local yPos = yOff + row * 32
		
		createButton(scroll, pu.label, pu.color, btnW, UDim2.new(0, xPos, 0, yPos), function()
			sendCmd({ action = "spawnPowerUp", powerType = pu.id })
		end)
		
		col = col + 1
		if col >= 2 then
			col = 0
			row = row + 1
		end
	end
	
	if col > 0 then row = row + 1 end  -- finish partial row
	yOff = yOff + row * 32 + 8
	
	-- Section: Apply Instantly
	local applyHeader = Instance.new("TextLabel")
	applyHeader.Size = UDim2.new(1, -16, 0, 20)
	applyHeader.Position = UDim2.new(0, 8, 0, yOff)
	applyHeader.BackgroundTransparency = 1
	applyHeader.Text = "APPLY INSTANTLY"
	applyHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	applyHeader.TextSize = 11
	applyHeader.Font = Enum.Font.GothamBold
	applyHeader.TextXAlignment = Enum.TextXAlignment.Left
	applyHeader.Parent = scroll
	yOff = yOff + 22
	
	col = 0
	row = 0
	for _, pu in POWERUP_BUTTONS do
		local xPos = 8 + col * 104
		local yPos = yOff + row * 32
		
		local btnColor = Color3.fromRGB(
			math.min(255, math.floor(pu.color.R * 255 * 0.6)),
			math.min(255, math.floor(pu.color.G * 255 * 0.6)),
			math.min(255, math.floor(pu.color.B * 255 * 0.6))
		)
		
		createButton(scroll, pu.label, btnColor, btnW, UDim2.new(0, xPos, 0, yPos), function()
			sendCmd({ action = "applyPowerUp", powerType = pu.id })
		end)
		
		col = col + 1
		if col >= 2 then
			col = 0
			row = row + 1
		end
	end
	
	if col > 0 then row = row + 1 end
	yOff = yOff + row * 32 + 8
	
	-- Section: Stats
	local statsHeader = Instance.new("TextLabel")
	statsHeader.Size = UDim2.new(1, -16, 0, 20)
	statsHeader.Position = UDim2.new(0, 8, 0, yOff)
	statsHeader.BackgroundTransparency = 1
	statsHeader.Text = "SHIP STATS"
	statsHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	statsHeader.TextSize = 11
	statsHeader.Font = Enum.Font.GothamBold
	statsHeader.TextXAlignment = Enum.TextXAlignment.Left
	statsHeader.Parent = scroll
	yOff = yOff + 22
	
	-- Health buttons
	createButton(scroll, "HP 25", Color3.fromRGB(180, 40, 40), UDim2.new(0, 46, 0, 26), UDim2.new(0, 8, 0, yOff), function()
		sendCmd({ action = "setHealth", value = 25 })
	end)
	createButton(scroll, "HP 50", Color3.fromRGB(200, 140, 40), UDim2.new(0, 46, 0, 26), UDim2.new(0, 58, 0, yOff), function()
		sendCmd({ action = "setHealth", value = 50 })
	end)
	createButton(scroll, "HP 100", Color3.fromRGB(40, 180, 60), UDim2.new(0, 52, 0, 26), UDim2.new(0, 108, 0, yOff), function()
		sendCmd({ action = "setHealth", value = 100 })
	end)
	yOff = yOff + 30
	
	-- Ammo buttons
	createButton(scroll, "Ammo 0", Color3.fromRGB(100, 60, 30), UDim2.new(0, 60, 0, 26), UDim2.new(0, 8, 0, yOff), function()
		sendCmd({ action = "setAmmo", value = 0 })
	end)
	createButton(scroll, "Ammo 6", Color3.fromRGB(140, 90, 40), UDim2.new(0, 60, 0, 26), UDim2.new(0, 72, 0, yOff), function()
		sendCmd({ action = "setAmmo", value = 6 })
	end)
	createButton(scroll, "Max", Color3.fromRGB(180, 120, 50), UDim2.new(0, 46, 0, 26), UDim2.new(0, 136, 0, yOff), function()
		sendCmd({ action = "setAmmo", value = 99 })
	end)
	yOff = yOff + 34
	
	-- Section: Utility
	local utilHeader = Instance.new("TextLabel")
	utilHeader.Size = UDim2.new(1, -16, 0, 20)
	utilHeader.Position = UDim2.new(0, 8, 0, yOff)
	utilHeader.BackgroundTransparency = 1
	utilHeader.Text = "UTILITY"
	utilHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	utilHeader.TextSize = 11
	utilHeader.Font = Enum.Font.GothamBold
	utilHeader.TextXAlignment = Enum.TextXAlignment.Left
	utilHeader.Parent = scroll
	yOff = yOff + 22
	
	for _, util in UTILITY_BUTTONS do
		createButton(scroll, util.label, util.color, UDim2.new(1, -16, 0, 28), UDim2.new(0, 8, 0, yOff), function()
			sendCmd({ action = util.id })
		end)
		yOff = yOff + 32
	end
	
	yOff = yOff + 8
	
	-- Section: Crate Spawning
	local crateHeader = Instance.new("TextLabel")
	crateHeader.Size = UDim2.new(1, -16, 0, 20)
	crateHeader.Position = UDim2.new(0, 8, 0, yOff)
	crateHeader.BackgroundTransparency = 1
	crateHeader.Text = "CRATE SPAWNING"
	crateHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	crateHeader.TextSize = 11
	crateHeader.Font = Enum.Font.GothamBold
	crateHeader.TextXAlignment = Enum.TextXAlignment.Left
	crateHeader.Parent = scroll
	yOff = yOff + 22
	
	-- Max Ammo Crates row
	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Size = UDim2.new(0, 100, 0, 26)
	ammoLabel.Position = UDim2.new(0, 8, 0, yOff)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Text = "Ammo Crates:"
	ammoLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	ammoLabel.TextSize = 12
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
	ammoLabel.Parent = scroll
	
	local ammoValue = Instance.new("TextLabel")
	ammoValue.Name = "AmmoValue"
	ammoValue.Size = UDim2.new(0, 30, 0, 26)
	ammoValue.Position = UDim2.new(0, 112, 0, yOff)
	ammoValue.BackgroundTransparency = 1
	ammoValue.Text = "8"
	ammoValue.TextColor3 = Color3.fromRGB(255, 220, 80)
	ammoValue.TextSize = 14
	ammoValue.Font = Enum.Font.GothamBold
	ammoValue.Parent = scroll
	
	local crateCount = 8
	
	createButton(scroll, "-", Color3.fromRGB(160, 50, 50), UDim2.new(0, 28, 0, 26), UDim2.new(0, 148, 0, yOff), function()
		crateCount = math.max(0, crateCount - 1)
		ammoValue.Text = tostring(crateCount)
		sendCmd({ action = "setMaxCrates", value = crateCount })
	end)
	createButton(scroll, "+", Color3.fromRGB(40, 140, 60), UDim2.new(0, 28, 0, 26), UDim2.new(0, 180, 0, yOff), function()
		crateCount = crateCount + 1
		ammoValue.Text = tostring(crateCount)
		sendCmd({ action = "setMaxCrates", value = crateCount })
	end)
	yOff = yOff + 30
	
	-- Max Power-up Crates row
	local puLabel = Instance.new("TextLabel")
	puLabel.Size = UDim2.new(0, 100, 0, 26)
	puLabel.Position = UDim2.new(0, 8, 0, yOff)
	puLabel.BackgroundTransparency = 1
	puLabel.Text = "Power-ups:"
	puLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	puLabel.TextSize = 12
	puLabel.Font = Enum.Font.GothamBold
	puLabel.TextXAlignment = Enum.TextXAlignment.Left
	puLabel.Parent = scroll
	
	local puValue = Instance.new("TextLabel")
	puValue.Name = "PuValue"
	puValue.Size = UDim2.new(0, 30, 0, 26)
	puValue.Position = UDim2.new(0, 112, 0, yOff)
	puValue.BackgroundTransparency = 1
	puValue.Text = "10"
	puValue.TextColor3 = Color3.fromRGB(255, 220, 80)
	puValue.TextSize = 14
	puValue.Font = Enum.Font.GothamBold
	puValue.Parent = scroll
	
	local puCount = 10
	
	createButton(scroll, "-", Color3.fromRGB(160, 50, 50), UDim2.new(0, 28, 0, 26), UDim2.new(0, 148, 0, yOff), function()
		puCount = math.max(0, puCount - 1)
		puValue.Text = tostring(puCount)
		sendCmd({ action = "setMaxPowerups", value = puCount })
	end)
	createButton(scroll, "+", Color3.fromRGB(40, 140, 60), UDim2.new(0, 28, 0, 26), UDim2.new(0, 180, 0, yOff), function()
		puCount = puCount + 1
		puValue.Text = tostring(puCount)
		sendCmd({ action = "setMaxPowerups", value = puCount })
	end)
	yOff = yOff + 34
	
	-- Listen for server responses to sync displayed values
	local devResponse = EventManager.waitForEvent("DevResponse")
	devResponse.OnClientEvent:Connect(function(data)
		if data.key == "maxCrates" then
			crateCount = data.value
			ammoValue.Text = tostring(data.value)
		elseif data.key == "maxPowerups" then
			puCount = data.value
			puValue.Text = tostring(data.value)
		end
	end)
	
	-- Request current config from server
	sendCmd({ action = "getCrateConfig" })
	
	-- Section: Bots
	local botHeader = Instance.new("TextLabel")
	botHeader.Size = UDim2.new(1, -16, 0, 20)
	botHeader.Position = UDim2.new(0, 8, 0, yOff)
	botHeader.BackgroundTransparency = 1
	botHeader.Text = "BOTS"
	botHeader.TextColor3 = Color3.fromRGB(160, 160, 180)
	botHeader.TextSize = 11
	botHeader.Font = Enum.Font.GothamBold
	botHeader.TextXAlignment = Enum.TextXAlignment.Left
	botHeader.Parent = scroll
	yOff = yOff + 22
	
	-- Add / Remove bot buttons side by side
	createButton(scroll, "+ Add Bot", Color3.fromRGB(40, 140, 60), UDim2.new(0, 96, 0, 28), UDim2.new(0, 8, 0, yOff), function()
		sendCmd({ action = "addBot" })
	end)
	createButton(scroll, "- Remove", Color3.fromRGB(160, 50, 50), UDim2.new(0, 96, 0, 28), UDim2.new(0, 112, 0, yOff), function()
		sendCmd({ action = "removeBot" })
	end)
	yOff = yOff + 32
	
	createButton(scroll, "Remove All Bots", Color3.fromRGB(120, 30, 30), UDim2.new(1, -16, 0, 28), UDim2.new(0, 8, 0, yOff), function()
		sendCmd({ action = "removeAllBots" })
	end)
	yOff = yOff + 34
	
	-- Difficulty buttons
	local diffLabel = Instance.new("TextLabel")
	diffLabel.Size = UDim2.new(1, -16, 0, 16)
	diffLabel.Position = UDim2.new(0, 8, 0, yOff)
	diffLabel.BackgroundTransparency = 1
	diffLabel.Text = "DIFFICULTY"
	diffLabel.TextColor3 = Color3.fromRGB(130, 130, 150)
	diffLabel.TextSize = 10
	diffLabel.Font = Enum.Font.GothamBold
	diffLabel.TextXAlignment = Enum.TextXAlignment.Left
	diffLabel.Parent = scroll
	yOff = yOff + 18
	
	local difficulties = {
		{ id = "easy",   label = "Easy",   color = Color3.fromRGB(60, 160, 80) },
		{ id = "medium", label = "Medium", color = Color3.fromRGB(180, 160, 40) },
		{ id = "hard",   label = "Hard",   color = Color3.fromRGB(200, 50, 50) },
	}
	
	local diffBtns = {}
	local diffBtnWidth = 62
	for idx, diff in difficulties do
		local xPos = 8 + (idx - 1) * (diffBtnWidth + 8)
		local btn = createButton(scroll, diff.label, diff.color, UDim2.new(0, diffBtnWidth, 0, 26), UDim2.new(0, xPos, 0, yOff), function()
			sendCmd({ action = "setBotDifficulty", difficulty = diff.id })
			-- Highlight selected button
			for _, b in diffBtns do
				b.BackgroundTransparency = 0.15
			end
			btn.BackgroundTransparency = 0
		end)
		-- Default highlight on "medium"
		if diff.id == "medium" then
			btn.BackgroundTransparency = 0
		end
		table.insert(diffBtns, btn)
	end
	yOff = yOff + 34
	
	-- Set scroll canvas to fit all content, cap panel height to screen
	scroll.CanvasSize = UDim2.new(0, 0, 0, yOff)
	local maxPanelHeight = 600  -- max visible height before scrolling kicks in
	local totalHeight = math.min(yOff + 30, maxPanelHeight)  -- 30 for title
	mainFrame.Size = UDim2.new(0, 220, 0, totalHeight)
	
	-- Toggle button (always visible)
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "DevToggle"
	toggleBtn.Size = UDim2.new(0, 36, 0, 36)
	toggleBtn.Position = UDim2.new(0, 10, 0, 60)
	toggleBtn.AnchorPoint = Vector2.new(0, 0)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	toggleBtn.BackgroundTransparency = 0.15
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Text = "🛠"
	toggleBtn.TextSize = 20
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextColor3 = Color3.fromRGB(255, 220, 80)
	toggleBtn.AutoButtonColor = true
	toggleBtn.Parent = screenGui
	
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent = toggleBtn
	
	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = Color3.fromRGB(255, 220, 80)
	toggleStroke.Thickness = 1
	toggleStroke.Transparency = 0.5
	toggleStroke.Parent = toggleBtn
	
	toggleBtn.MouseButton1Click:Connect(function()
		isVisible = not isVisible
		mainFrame.Visible = isVisible
		if isVisible then
			mainFrame.Position = UDim2.new(0, 10, 0, 100)
		end
	end)
	
	-- Shift panel down so it appears below the toggle button
	mainFrame.Position = UDim2.new(0, 10, 0, 100)
	
	print("[DevPanel] Initialized — click 🛠 button to toggle")
end

return DevPanel
