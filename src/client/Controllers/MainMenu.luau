--[[
	MainMenu (Client — Hub Mode Only)
	==================================
	Full-screen main menu GUI with game creation, browsing, joining,
	and admin sandbox access. Clean modern dark UI theme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EventManager = require(ReplicatedStorage.Shared.EventManager)
local Constants = require(ReplicatedStorage.Shared.Constants)

local MainMenu = {}

local player = Players.LocalPlayer
local isAdmin = player.Name == Constants.ADMIN_NAME
local screenGui = nil

-- ========================
-- COLOR PALETTE
-- ========================
local COLORS = {
	bg = Color3.fromHex("#0d1117"),
	panel = Color3.fromHex("#161b22"),
	panelBorder = Color3.fromHex("#30363d"),
	accent = Color3.fromHex("#58a6ff"),
	accentHover = Color3.fromHex("#79c0ff"),
	accentDark = Color3.fromHex("#1f6feb"),
	green = Color3.fromHex("#3fb950"),
	greenHover = Color3.fromHex("#56d364"),
	red = Color3.fromHex("#f85149"),
	yellow = Color3.fromHex("#d29922"),
	text = Color3.fromHex("#e6edf3"),
	textMuted = Color3.fromHex("#8b949e"),
	textDim = Color3.fromHex("#484f58"),
	separator = Color3.fromHex("#21262d"),
	inputBg = Color3.fromHex("#0d1117"),
	sandboxPurple = Color3.fromHex("#a371f7"),
}

-- ========================
-- UI FACTORY HELPERS
-- ========================

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function createStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.panelBorder
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function createPadding(parent, top, right, bottom, left)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top or 12)
	padding.PaddingRight = UDim.new(0, right or 12)
	padding.PaddingBottom = UDim.new(0, bottom or 12)
	padding.PaddingLeft = UDim.new(0, left or 12)
	padding.Parent = parent
	return padding
end

local function createButton(parent, text, color, size, position)
	local btn = Instance.new("TextButton")
	btn.Size = size or UDim2.new(1, 0, 0, 42)
	btn.Position = position or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = color or COLORS.accent
	btn.Text = text
	btn.TextColor3 = COLORS.text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.AutoButtonColor = false
	btn.Parent = parent
	createCorner(btn, 6)

	-- Hover effect
	local defaultColor = color or COLORS.accent
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.new(
				math.min(1, defaultColor.R * 1.2),
				math.min(1, defaultColor.G * 1.2),
				math.min(1, defaultColor.B * 1.2)
			),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = defaultColor,
		}):Play()
	end)

	return btn
end

local function createLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or COLORS.text
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size or 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function createNumberInput(parent, default, min, max)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 36)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local minusBtn = Instance.new("TextButton")
	minusBtn.Size = UDim2.new(0, 36, 1, 0)
	minusBtn.Position = UDim2.new(0, 0, 0, 0)
	minusBtn.BackgroundColor3 = COLORS.separator
	minusBtn.Text = "−"
	minusBtn.TextColor3 = COLORS.text
	minusBtn.Font = Enum.Font.GothamBold
	minusBtn.TextSize = 18
	minusBtn.AutoButtonColor = false
	minusBtn.Parent = frame
	createCorner(minusBtn, 6)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, -80, 1, 0)
	valueLabel.Position = UDim2.new(0, 40, 0, 0)
	valueLabel.BackgroundColor3 = COLORS.inputBg
	valueLabel.Text = tostring(default)
	valueLabel.TextColor3 = COLORS.text
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 18
	valueLabel.Parent = frame
	createCorner(valueLabel, 4)
	createStroke(valueLabel, COLORS.panelBorder)

	local plusBtn = Instance.new("TextButton")
	plusBtn.Size = UDim2.new(0, 36, 1, 0)
	plusBtn.Position = UDim2.new(1, -36, 0, 0)
	plusBtn.BackgroundColor3 = COLORS.separator
	plusBtn.Text = "+"
	plusBtn.TextColor3 = COLORS.text
	plusBtn.Font = Enum.Font.GothamBold
	plusBtn.TextSize = 18
	plusBtn.AutoButtonColor = false
	plusBtn.Parent = frame
	createCorner(plusBtn, 6)

	local currentValue = default

	local function updateDisplay()
		valueLabel.Text = tostring(currentValue)
	end

	minusBtn.MouseButton1Click:Connect(function()
		currentValue = math.max(min, currentValue - 1)
		updateDisplay()
	end)

	plusBtn.MouseButton1Click:Connect(function()
		currentValue = math.min(max, currentValue + 1)
		updateDisplay()
	end)

	return frame, function() return currentValue end
end

-- ========================
-- MAIN MENU BUILD
-- ========================

function MainMenu.init()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- Full-screen background
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = COLORS.bg
	bg.BorderSizePixel = 0
	bg.Parent = screenGui

	-- Subtle grid pattern overlay
	local gridOverlay = Instance.new("Frame")
	gridOverlay.Name = "GridOverlay"
	gridOverlay.Size = UDim2.new(1, 0, 1, 0)
	gridOverlay.BackgroundTransparency = 0.97
	gridOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
	gridOverlay.BorderSizePixel = 0
	gridOverlay.Parent = bg

	-- ========================
	-- TITLE
	-- ========================
	local titleContainer = Instance.new("Frame")
	titleContainer.Name = "TitleContainer"
	titleContainer.Size = UDim2.new(1, 0, 0, 120)
	titleContainer.Position = UDim2.new(0, 0, 0, 30)
	titleContainer.BackgroundTransparency = 1
	titleContainer.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "SHOOTASHIP"
	title.TextColor3 = COLORS.text
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 48
	title.Parent = titleContainer

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 24)
	subtitle.Position = UDim2.new(0, 0, 0, 58)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Naval Combat Arena"
	subtitle.TextColor3 = COLORS.textMuted
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 16
	subtitle.Parent = titleContainer

	-- Accent line under title
	local accentLine = Instance.new("Frame")
	accentLine.Size = UDim2.new(0, 120, 0, 3)
	accentLine.Position = UDim2.new(0.5, -60, 0, 88)
	accentLine.BackgroundColor3 = COLORS.accent
	accentLine.BorderSizePixel = 0
	accentLine.Parent = titleContainer
	createCorner(accentLine, 2)

	-- ========================
	-- MAIN CONTENT AREA
	-- ========================
	local contentArea = Instance.new("Frame")
	contentArea.Name = "ContentArea"
	contentArea.Size = UDim2.new(1, -80, 1, -200)
	contentArea.Position = UDim2.new(0, 40, 0, 160)
	contentArea.BackgroundTransparency = 1
	contentArea.Parent = bg

	-- ========================
	-- LEFT PANEL — CREATE GAME
	-- ========================
	local createPanel = Instance.new("Frame")
	createPanel.Name = "CreatePanel"
	createPanel.Size = UDim2.new(0.35, -10, 1, 0)
	createPanel.Position = UDim2.new(0, 0, 0, 0)
	createPanel.BackgroundColor3 = COLORS.panel
	createPanel.BorderSizePixel = 0
	createPanel.Parent = contentArea
	createCorner(createPanel, 12)
	createStroke(createPanel, COLORS.panelBorder)
	createPadding(createPanel, 20, 20, 20, 20)

	local createTitle = createLabel(createPanel, "CREATE GAME", 18, COLORS.accent, Enum.Font.GothamBlack)
	createTitle.Size = UDim2.new(1, 0, 0, 28)
	createTitle.TextXAlignment = Enum.TextXAlignment.Center

	local separator1 = Instance.new("Frame")
	separator1.Size = UDim2.new(1, 0, 0, 1)
	separator1.Position = UDim2.new(0, 0, 0, 38)
	separator1.BackgroundColor3 = COLORS.separator
	separator1.BorderSizePixel = 0
	separator1.Parent = createPanel

	-- Mode label
	local modeLabel = createLabel(createPanel, "MODE", 11, COLORS.textMuted, Enum.Font.GothamBold)
	modeLabel.Position = UDim2.new(0, 0, 0, 50)
	modeLabel.Size = UDim2.new(1, 0, 0, 18)

	local modeValue = createLabel(createPanel, "DEATHMATCH", 16, COLORS.green, Enum.Font.GothamBlack)
	modeValue.Position = UDim2.new(0, 0, 0, 68)
	modeValue.Size = UDim2.new(1, 0, 0, 24)

	local modeDesc = createLabel(createPanel, "First to reach the kill target wins", 12, COLORS.textDim, Enum.Font.Gotham)
	modeDesc.Position = UDim2.new(0, 0, 0, 94)
	modeDesc.Size = UDim2.new(1, 0, 0, 18)

	-- Kill Target input
	local killLabel = createLabel(createPanel, "KILL TARGET", 11, COLORS.textMuted, Enum.Font.GothamBold)
	killLabel.Position = UDim2.new(0, 0, 0, 130)
	killLabel.Size = UDim2.new(1, 0, 0, 18)

	local killInputFrame = Instance.new("Frame")
	killInputFrame.Size = UDim2.new(1, 0, 0, 36)
	killInputFrame.Position = UDim2.new(0, 0, 0, 152)
	killInputFrame.BackgroundTransparency = 1
	killInputFrame.Parent = createPanel

	local _, getKillTarget = createNumberInput(killInputFrame, Constants.DEFAULT_KILL_TARGET, 1, 100)

	-- Max Players input
	local playersLabel = createLabel(createPanel, "MAX PLAYERS", 11, COLORS.textMuted, Enum.Font.GothamBold)
	playersLabel.Position = UDim2.new(0, 0, 0, 204)
	playersLabel.Size = UDim2.new(1, 0, 0, 18)

	local playersInputFrame = Instance.new("Frame")
	playersInputFrame.Size = UDim2.new(1, 0, 0, 36)
	playersInputFrame.Position = UDim2.new(0, 0, 0, 226)
	playersInputFrame.BackgroundTransparency = 1
	playersInputFrame.Parent = createPanel

	local _, getMaxPlayers = createNumberInput(playersInputFrame, Constants.MAX_PLAYERS_PER_GAME, 2, Constants.MAX_PLAYERS_PER_GAME)

	-- CREATE BUTTON
	local startBtn = createButton(createPanel, "CREATE GAME", COLORS.green, UDim2.new(1, 0, 0, 48))
	startBtn.Position = UDim2.new(0, 0, 0, 286)
	startBtn.TextSize = 17

	startBtn.MouseButton1Click:Connect(function()
		startBtn.Text = "CREATING..."
		local createEvent = EventManager.getEvent("CreateGame")
		createEvent:FireServer({
			killTarget = getKillTarget(),
			maxPlayers = getMaxPlayers(),
		})
		-- Button stays disabled — we'll teleport shortly
		startBtn.AutoButtonColor = false
	end)

	-- Private Game button (coming soon)
	local privateBtn = Instance.new("TextButton")
	privateBtn.Size = UDim2.new(1, 0, 0, 38)
	privateBtn.Position = UDim2.new(0, 0, 0, 346)
	privateBtn.BackgroundColor3 = COLORS.separator
	privateBtn.Text = "🔒  PRIVATE GAME — Coming Soon"
	privateBtn.TextColor3 = COLORS.textDim
	privateBtn.Font = Enum.Font.GothamBold
	privateBtn.TextSize = 13
	privateBtn.AutoButtonColor = false
	privateBtn.Active = false
	privateBtn.Parent = createPanel
	createCorner(privateBtn, 6)

	-- ========================
	-- RIGHT PANEL — GAME BROWSER
	-- ========================
	local browserPanel = Instance.new("Frame")
	browserPanel.Name = "BrowserPanel"
	browserPanel.Size = UDim2.new(0.65, -10, 1, 0)
	browserPanel.Position = UDim2.new(0.35, 10, 0, 0)
	browserPanel.BackgroundColor3 = COLORS.panel
	browserPanel.BorderSizePixel = 0
	browserPanel.Parent = contentArea
	createCorner(browserPanel, 12)
	createStroke(browserPanel, COLORS.panelBorder)
	createPadding(browserPanel, 20, 20, 20, 20)

	local browserTitle = createLabel(browserPanel, "GAME BROWSER", 18, COLORS.accent, Enum.Font.GothamBlack)
	browserTitle.Size = UDim2.new(0.6, 0, 0, 28)
	browserTitle.TextXAlignment = Enum.TextXAlignment.Center
	browserTitle.Size = UDim2.new(1, 0, 0, 28)

	local separator2 = Instance.new("Frame")
	separator2.Size = UDim2.new(1, 0, 0, 1)
	separator2.Position = UDim2.new(0, 0, 0, 38)
	separator2.BackgroundColor3 = COLORS.separator
	separator2.BorderSizePixel = 0
	separator2.Parent = browserPanel

	-- Column headers
	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "Headers"
	headerFrame.Size = UDim2.new(1, 0, 0, 28)
	headerFrame.Position = UDim2.new(0, 0, 0, 48)
	headerFrame.BackgroundTransparency = 1
	headerFrame.Parent = browserPanel

	local colHost = createLabel(headerFrame, "HOST", 11, COLORS.textDim, Enum.Font.GothamBold)
	colHost.Size = UDim2.new(0.3, 0, 1, 0)
	colHost.Position = UDim2.new(0, 0, 0, 0)

	local colPlayers = createLabel(headerFrame, "PLAYERS", 11, COLORS.textDim, Enum.Font.GothamBold)
	colPlayers.Size = UDim2.new(0.2, 0, 1, 0)
	colPlayers.Position = UDim2.new(0.3, 0, 0, 0)
	colPlayers.TextXAlignment = Enum.TextXAlignment.Center

	local colTarget = createLabel(headerFrame, "TARGET", 11, COLORS.textDim, Enum.Font.GothamBold)
	colTarget.Size = UDim2.new(0.15, 0, 1, 0)
	colTarget.Position = UDim2.new(0.5, 0, 0, 0)
	colTarget.TextXAlignment = Enum.TextXAlignment.Center

	local colStatus = createLabel(headerFrame, "STATUS", 11, COLORS.textDim, Enum.Font.GothamBold)
	colStatus.Size = UDim2.new(0.15, 0, 1, 0)
	colStatus.Position = UDim2.new(0.65, 0, 0, 0)
	colStatus.TextXAlignment = Enum.TextXAlignment.Center

	-- Scrolling game list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "GameList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -90)
	scrollFrame.Position = UDim2.new(0, 0, 0, 80)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.textDim
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = browserPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scrollFrame

	-- Empty state message
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 0, 100)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "No public games found.\nCreate one to get started!"
	emptyLabel.TextColor3 = COLORS.textDim
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.TextSize = 14
	emptyLabel.Parent = scrollFrame

	-- Function to populate game list
	local function updateGameList(games)
		-- Clear existing rows (except the empty label and layout)
		for _, child in scrollFrame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if not games or #games == 0 then
			emptyLabel.Visible = true
			return
		end

		emptyLabel.Visible = false

		for i, game in games do
			local row = Instance.new("Frame")
			row.Name = "GameRow_" .. i
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundColor3 = i % 2 == 0 and COLORS.separator or COLORS.panel
			row.BackgroundTransparency = i % 2 == 0 and 0.5 or 1
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = scrollFrame
			createCorner(row, 6)

			local hostLabel = Instance.new("TextLabel")
			hostLabel.Size = UDim2.new(0.3, 0, 1, 0)
			hostLabel.Position = UDim2.new(0, 8, 0, 0)
			hostLabel.BackgroundTransparency = 1
			hostLabel.Text = game.hostName or "Unknown"
			hostLabel.TextColor3 = COLORS.text
			hostLabel.Font = Enum.Font.GothamBold
			hostLabel.TextSize = 14
			hostLabel.TextXAlignment = Enum.TextXAlignment.Left
			hostLabel.TextTruncate = Enum.TextTruncate.AtEnd
			hostLabel.Parent = row

			local playersLabel = Instance.new("TextLabel")
			playersLabel.Size = UDim2.new(0.2, 0, 1, 0)
			playersLabel.Position = UDim2.new(0.3, 0, 0, 0)
			playersLabel.BackgroundTransparency = 1
			playersLabel.Text = game.playerCount .. "/" .. game.maxPlayers
			playersLabel.Font = Enum.Font.GothamBold
			playersLabel.TextSize = 14
			playersLabel.Parent = row

			-- Color code player count
			local isFull = game.playerCount >= game.maxPlayers
			playersLabel.TextColor3 = isFull and COLORS.red or COLORS.green

			local targetLabel = Instance.new("TextLabel")
			targetLabel.Size = UDim2.new(0.15, 0, 1, 0)
			targetLabel.Position = UDim2.new(0.5, 0, 0, 0)
			targetLabel.BackgroundTransparency = 1
			targetLabel.Text = tostring(game.killTarget)
			targetLabel.TextColor3 = COLORS.yellow
			targetLabel.Font = Enum.Font.GothamBold
			targetLabel.TextSize = 14
			targetLabel.Parent = row

			local statusLabel = Instance.new("TextLabel")
			statusLabel.Size = UDim2.new(0.15, 0, 1, 0)
			statusLabel.Position = UDim2.new(0.65, 0, 0, 0)
			statusLabel.BackgroundTransparency = 1
			statusLabel.Text = game.status == "playing" and "In Game" or "Waiting"
			statusLabel.TextColor3 = game.status == "playing" and COLORS.yellow or COLORS.green
			statusLabel.Font = Enum.Font.Gotham
			statusLabel.TextSize = 12
			statusLabel.Parent = row

			-- Join button
			if not isFull then
				local joinBtn = createButton(row, "JOIN", COLORS.accent, UDim2.new(0.15, -8, 0, 30))
				joinBtn.Position = UDim2.new(0.85, 0, 0.5, -15)

				joinBtn.MouseButton1Click:Connect(function()
					joinBtn.Text = "Joining..."
					local joinEvent = EventManager.getEvent("JoinGame")
					joinEvent:FireServer({ gameId = game.gameId })
				end)
			end
		end
	end

	-- Listen for game list updates
	local gameListEvent = EventManager.waitForEvent("GameListUpdate")
	gameListEvent.OnClientEvent:Connect(function(games)
		updateGameList(games)
	end)

	-- Request initial game list
	task.defer(function()
		local requestEvent = EventManager.getEvent("RequestGameList")
		requestEvent:FireServer()
	end)

	-- ========================
	-- BOTTOM BAR — SANDBOX (Admin Only)
	-- ========================
	if isAdmin then
		local sandboxPanel = Instance.new("Frame")
		sandboxPanel.Name = "SandboxPanel"
		sandboxPanel.Size = UDim2.new(0.35, -10, 0, 44)
		sandboxPanel.Position = UDim2.new(0, 0, 1, 10)
		sandboxPanel.BackgroundColor3 = COLORS.panel
		sandboxPanel.BorderSizePixel = 0
		sandboxPanel.Parent = contentArea
		createCorner(sandboxPanel, 10)
		createStroke(sandboxPanel, COLORS.sandboxPurple, 1)

		local sandboxBtnLayout = Instance.new("UIListLayout")
		sandboxBtnLayout.FillDirection = Enum.FillDirection.Horizontal
		sandboxBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		sandboxBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		sandboxBtnLayout.Padding = UDim.new(0, 10)
		sandboxBtnLayout.Parent = sandboxPanel

		local sandboxIcon = Instance.new("TextLabel")
		sandboxIcon.Size = UDim2.new(0, 30, 0, 30)
		sandboxIcon.BackgroundTransparency = 1
		sandboxIcon.Text = "🛠"
		sandboxIcon.TextSize = 20
		sandboxIcon.Font = Enum.Font.Gotham
		sandboxIcon.Parent = sandboxPanel

		local enterSandboxBtn = createButton(sandboxPanel, "ENTER SANDBOX", COLORS.sandboxPurple, UDim2.new(0, 160, 0, 32))

		enterSandboxBtn.MouseButton1Click:Connect(function()
			enterSandboxBtn.Text = "Loading..."
			local createSandboxEvent = EventManager.getEvent("CreateSandbox")
			createSandboxEvent:FireServer()
		end)

		local inviteBtn = createButton(sandboxPanel, "INVITE PLAYER", COLORS.separator, UDim2.new(0, 140, 0, 32))

		-- Sandbox invite panel (toggleable)
		local invitePanel = Instance.new("Frame")
		invitePanel.Name = "InvitePanel"
		invitePanel.Size = UDim2.new(0.4, 0, 0, 300)
		invitePanel.Position = UDim2.new(0, 0, 1, 60)
		invitePanel.BackgroundColor3 = COLORS.panel
		invitePanel.BorderSizePixel = 0
		invitePanel.Visible = false
		invitePanel.Parent = contentArea
		createCorner(invitePanel, 12)
		createStroke(invitePanel, COLORS.sandboxPurple, 1)
		createPadding(invitePanel, 16, 16, 16, 16)

		local invitePanelTitle = createLabel(invitePanel, "INVITE TO SANDBOX", 14, COLORS.sandboxPurple, Enum.Font.GothamBlack)
		invitePanelTitle.Size = UDim2.new(1, 0, 0, 24)
		invitePanelTitle.TextXAlignment = Enum.TextXAlignment.Center

		local inviteScrollFrame = Instance.new("ScrollingFrame")
		inviteScrollFrame.Name = "PlayerList"
		inviteScrollFrame.Size = UDim2.new(1, 0, 1, -36)
		inviteScrollFrame.Position = UDim2.new(0, 0, 0, 32)
		inviteScrollFrame.BackgroundTransparency = 1
		inviteScrollFrame.BorderSizePixel = 0
		inviteScrollFrame.ScrollBarThickness = 4
		inviteScrollFrame.ScrollBarImageColor3 = COLORS.textDim
		inviteScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		inviteScrollFrame.Parent = invitePanel

		local inviteListLayout = Instance.new("UIListLayout")
		inviteListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		inviteListLayout.Padding = UDim.new(0, 4)
		inviteListLayout.Parent = inviteScrollFrame

		local inviteEmptyLabel = Instance.new("TextLabel")
		inviteEmptyLabel.Size = UDim2.new(1, 0, 0, 60)
		inviteEmptyLabel.BackgroundTransparency = 1
		inviteEmptyLabel.Text = "No other players in the hub."
		inviteEmptyLabel.TextColor3 = COLORS.textDim
		inviteEmptyLabel.Font = Enum.Font.Gotham
		inviteEmptyLabel.TextSize = 13
		inviteEmptyLabel.Parent = inviteScrollFrame

		local function updatePlayerList(playersList)
			for _, child in inviteScrollFrame:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end

			if not playersList or #playersList == 0 then
				inviteEmptyLabel.Visible = true
				return
			end

			inviteEmptyLabel.Visible = false

			for i, p in playersList do
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 36)
				row.BackgroundColor3 = COLORS.separator
				row.BackgroundTransparency = 0.5
				row.LayoutOrder = i
				row.Parent = inviteScrollFrame
				createCorner(row, 6)

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(0.65, 0, 1, 0)
				nameLabel.Position = UDim2.new(0, 10, 0, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = p.displayName or p.name
				nameLabel.TextColor3 = COLORS.text
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 13
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.Parent = row

				local invitePlayerBtn = createButton(row, "Invite", COLORS.sandboxPurple, UDim2.new(0.3, -8, 0, 26))
				invitePlayerBtn.Position = UDim2.new(0.7, 0, 0.5, -13)
				invitePlayerBtn.TextSize = 12

				invitePlayerBtn.MouseButton1Click:Connect(function()
					invitePlayerBtn.Text = "Sent!"
					invitePlayerBtn.BackgroundColor3 = COLORS.textDim
					local inviteEvent = EventManager.getEvent("InviteToSandbox")
					inviteEvent:FireServer({ targetUserId = p.userId })
				end)
			end
		end

		inviteBtn.MouseButton1Click:Connect(function()
			invitePanel.Visible = not invitePanel.Visible
			if invitePanel.Visible then
				local requestPlayerListEvent = EventManager.getEvent("RequestPlayerList")
				requestPlayerListEvent:FireServer()
			end
		end)

		-- Listen for player list updates
		local playerListEvent = EventManager.waitForEvent("PlayerListUpdate")
		playerListEvent.OnClientEvent:Connect(function(playersList)
			updatePlayerList(playersList)
		end)
	end

	-- ========================
	-- SANDBOX INVITE POPUP (for non-admin players)
	-- ========================
	local sandboxInviteEvent = EventManager.waitForEvent("SandboxInvite")
	sandboxInviteEvent.OnClientEvent:Connect(function(data)
		-- Create popup
		local popup = Instance.new("Frame")
		popup.Name = "SandboxInvitePopup"
		popup.Size = UDim2.new(0, 360, 0, 140)
		popup.Position = UDim2.new(0.5, -180, 0.5, -70)
		popup.BackgroundColor3 = COLORS.panel
		popup.BorderSizePixel = 0
		popup.ZIndex = 100
		popup.Parent = bg
		createCorner(popup, 12)
		createStroke(popup, COLORS.sandboxPurple, 2)

		local popupTitle = Instance.new("TextLabel")
		popupTitle.Size = UDim2.new(1, 0, 0, 30)
		popupTitle.Position = UDim2.new(0, 0, 0, 16)
		popupTitle.BackgroundTransparency = 1
		popupTitle.Text = "SANDBOX INVITE"
		popupTitle.TextColor3 = COLORS.sandboxPurple
		popupTitle.Font = Enum.Font.GothamBlack
		popupTitle.TextSize = 16
		popupTitle.Parent = popup

		local popupMsg = Instance.new("TextLabel")
		popupMsg.Size = UDim2.new(1, -20, 0, 24)
		popupMsg.Position = UDim2.new(0, 10, 0, 48)
		popupMsg.BackgroundTransparency = 1
		popupMsg.Text = (data.hostName or "Admin") .. " invited you to their sandbox"
		popupMsg.TextColor3 = COLORS.text
		popupMsg.Font = Enum.Font.Gotham
		popupMsg.TextSize = 14
		popupMsg.Parent = popup

		local acceptBtn = createButton(popup, "ACCEPT", COLORS.green, UDim2.new(0, 130, 0, 36))
		acceptBtn.Position = UDim2.new(0.5, -140, 0, 88)

		local declineBtn = createButton(popup, "DECLINE", COLORS.red, UDim2.new(0, 130, 0, 36))
		declineBtn.Position = UDim2.new(0.5, 10, 0, 88)

		acceptBtn.MouseButton1Click:Connect(function()
			local acceptEvent = EventManager.getEvent("AcceptSandboxInvite")
			acceptEvent:FireServer({ hostId = data.hostId })
			popup:Destroy()
		end)

		declineBtn.MouseButton1Click:Connect(function()
			popup:Destroy()
		end)

		-- Auto-dismiss after 30 seconds
		task.delay(30, function()
			if popup.Parent then
				popup:Destroy()
			end
		end)
	end)

	-- ========================
	-- TELEPORT LOADING INDICATOR
	-- ========================
	local teleportEvent = EventManager.waitForEvent("TeleportReady")
	teleportEvent.OnClientEvent:Connect(function()
		local overlay = Instance.new("Frame")
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = COLORS.bg
		overlay.BackgroundTransparency = 0.3
		overlay.ZIndex = 200
		overlay.Parent = bg

		local loadingLabel = Instance.new("TextLabel")
		loadingLabel.Size = UDim2.new(1, 0, 0, 40)
		loadingLabel.Position = UDim2.new(0, 0, 0.5, -20)
		loadingLabel.BackgroundTransparency = 1
		loadingLabel.Text = "Teleporting..."
		loadingLabel.TextColor3 = COLORS.accent
		loadingLabel.Font = Enum.Font.GothamBlack
		loadingLabel.TextSize = 28
		loadingLabel.Parent = overlay
	end)

	print("[MainMenu] Initialized")
end

function MainMenu.destroy()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
end

return MainMenu
