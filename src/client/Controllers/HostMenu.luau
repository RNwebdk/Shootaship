--[[
	HostMenu (Client — Game Mode, Host Only)
	==========================================
	Gear icon in the top-right that expands to show host controls:
	restart game, change kill target, end game (return to hub).
	Only visible to the host player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EventManager = require(ReplicatedStorage.Shared.EventManager)

local HostMenu = {}

local player = Players.LocalPlayer
local screenGui = nil
local hostPanel = nil
local isHost = false

local COLORS = {
	panel = Color3.fromHex("#161b22"),
	panelBorder = Color3.fromHex("#30363d"),
	accent = Color3.fromHex("#58a6ff"),
	green = Color3.fromHex("#3fb950"),
	red = Color3.fromHex("#f85149"),
	yellow = Color3.fromHex("#d29922"),
	text = Color3.fromHex("#e6edf3"),
	textMuted = Color3.fromHex("#8b949e"),
	separator = Color3.fromHex("#21262d"),
}

local killTarget = 10

function HostMenu.init()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HostMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- Gear toggle button (top-right)
	local gearBtn = Instance.new("TextButton")
	gearBtn.Name = "GearButton"
	gearBtn.Size = UDim2.new(0, 40, 0, 40)
	gearBtn.Position = UDim2.new(1, -52, 0, 52)
	gearBtn.BackgroundColor3 = COLORS.panel
	gearBtn.Text = "⚙"
	gearBtn.TextColor3 = COLORS.accent
	gearBtn.Font = Enum.Font.Gotham
	gearBtn.TextSize = 22
	gearBtn.AutoButtonColor = false
	gearBtn.Visible = false
	gearBtn.Parent = screenGui

	local gearCorner = Instance.new("UICorner")
	gearCorner.CornerRadius = UDim.new(0, 8)
	gearCorner.Parent = gearBtn

	local gearStroke = Instance.new("UIStroke")
	gearStroke.Color = COLORS.panelBorder
	gearStroke.Thickness = 1
	gearStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gearStroke.Parent = gearBtn

	-- Host panel
	hostPanel = Instance.new("Frame")
	hostPanel.Name = "HostPanel"
	hostPanel.Size = UDim2.new(0, 220, 0, 260)
	hostPanel.Position = UDim2.new(1, -232, 0, 98)
	hostPanel.BackgroundColor3 = COLORS.panel
	hostPanel.BorderSizePixel = 0
	hostPanel.Visible = false
	hostPanel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = hostPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLORS.panelBorder
	panelStroke.Thickness = 1
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.Parent = hostPanel

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0, 12)
	panelPadding.PaddingBottom = UDim.new(0, 12)
	panelPadding.PaddingLeft = UDim.new(0, 12)
	panelPadding.PaddingRight = UDim.new(0, 12)
	panelPadding.Parent = hostPanel

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "HOST CONTROLS"
	titleLabel.TextColor3 = COLORS.accent
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 13
	titleLabel.Parent = hostPanel

	-- Kill Target adjustment
	local ktLabel = Instance.new("TextLabel")
	ktLabel.Size = UDim2.new(1, 0, 0, 18)
	ktLabel.Position = UDim2.new(0, 0, 0, 36)
	ktLabel.BackgroundTransparency = 1
	ktLabel.Text = "KILL TARGET"
	ktLabel.TextColor3 = COLORS.textMuted
	ktLabel.Font = Enum.Font.GothamBold
	ktLabel.TextSize = 10
	ktLabel.TextXAlignment = Enum.TextXAlignment.Left
	ktLabel.Parent = hostPanel

	local ktFrame = Instance.new("Frame")
	ktFrame.Size = UDim2.new(1, 0, 0, 32)
	ktFrame.Position = UDim2.new(0, 0, 0, 56)
	ktFrame.BackgroundTransparency = 1
	ktFrame.Parent = hostPanel

	local ktMinus = Instance.new("TextButton")
	ktMinus.Size = UDim2.new(0, 32, 1, 0)
	ktMinus.BackgroundColor3 = COLORS.separator
	ktMinus.Text = "−"
	ktMinus.TextColor3 = COLORS.text
	ktMinus.Font = Enum.Font.GothamBold
	ktMinus.TextSize = 16
	ktMinus.AutoButtonColor = false
	ktMinus.Parent = ktFrame

	local ktMinusCorner = Instance.new("UICorner")
	ktMinusCorner.CornerRadius = UDim.new(0, 6)
	ktMinusCorner.Parent = ktMinus

	local ktValue = Instance.new("TextLabel")
	ktValue.Size = UDim2.new(1, -72, 1, 0)
	ktValue.Position = UDim2.new(0, 36, 0, 0)
	ktValue.BackgroundColor3 = Color3.fromHex("#0d1117")
	ktValue.Text = tostring(killTarget)
	ktValue.TextColor3 = COLORS.yellow
	ktValue.Font = Enum.Font.GothamBlack
	ktValue.TextSize = 16
	ktValue.Parent = ktFrame

	local ktValueCorner = Instance.new("UICorner")
	ktValueCorner.CornerRadius = UDim.new(0, 4)
	ktValueCorner.Parent = ktValue

	local ktPlus = Instance.new("TextButton")
	ktPlus.Size = UDim2.new(0, 32, 1, 0)
	ktPlus.Position = UDim2.new(1, -32, 0, 0)
	ktPlus.BackgroundColor3 = COLORS.separator
	ktPlus.Text = "+"
	ktPlus.TextColor3 = COLORS.text
	ktPlus.Font = Enum.Font.GothamBold
	ktPlus.TextSize = 16
	ktPlus.AutoButtonColor = false
	ktPlus.Parent = ktFrame

	local ktPlusCorner = Instance.new("UICorner")
	ktPlusCorner.CornerRadius = UDim.new(0, 6)
	ktPlusCorner.Parent = ktPlus

	ktMinus.MouseButton1Click:Connect(function()
		killTarget = math.max(1, killTarget - 5)
		ktValue.Text = tostring(killTarget)
		local hostEvent = EventManager.getEvent("HostAction")
		hostEvent:FireServer({ action = "setKillTarget", value = killTarget })
	end)

	ktPlus.MouseButton1Click:Connect(function()
		killTarget = math.min(100, killTarget + 5)
		ktValue.Text = tostring(killTarget)
		local hostEvent = EventManager.getEvent("HostAction")
		hostEvent:FireServer({ action = "setKillTarget", value = killTarget })
	end)

	-- Restart button
	local restartBtn = Instance.new("TextButton")
	restartBtn.Size = UDim2.new(1, 0, 0, 38)
	restartBtn.Position = UDim2.new(0, 0, 0, 108)
	restartBtn.BackgroundColor3 = COLORS.green
	restartBtn.Text = "RESTART GAME"
	restartBtn.TextColor3 = COLORS.text
	restartBtn.Font = Enum.Font.GothamBold
	restartBtn.TextSize = 14
	restartBtn.AutoButtonColor = false
	restartBtn.Parent = hostPanel

	local restartCorner = Instance.new("UICorner")
	restartCorner.CornerRadius = UDim.new(0, 6)
	restartCorner.Parent = restartBtn

	restartBtn.MouseButton1Click:Connect(function()
		local hostEvent = EventManager.getEvent("HostAction")
		hostEvent:FireServer({ action = "restart" })
	end)

	-- End Game button
	local endBtn = Instance.new("TextButton")
	endBtn.Size = UDim2.new(1, 0, 0, 38)
	endBtn.Position = UDim2.new(0, 0, 0, 154)
	endBtn.BackgroundColor3 = COLORS.red
	endBtn.Text = "END GAME"
	endBtn.TextColor3 = COLORS.text
	endBtn.Font = Enum.Font.GothamBold
	endBtn.TextSize = 14
	endBtn.AutoButtonColor = false
	endBtn.Parent = hostPanel

	local endCorner = Instance.new("UICorner")
	endCorner.CornerRadius = UDim.new(0, 6)
	endCorner.Parent = endBtn

	endBtn.MouseButton1Click:Connect(function()
		endBtn.Text = "Ending..."
		local hostEvent = EventManager.getEvent("HostAction")
		hostEvent:FireServer({ action = "endGame" })
	end)

	-- Info text
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 36)
	infoLabel.Position = UDim2.new(0, 0, 0, 200)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "You are the host.\nThese controls affect all players."
	infoLabel.TextColor3 = COLORS.textMuted
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 10
	infoLabel.TextWrapped = true
	infoLabel.Parent = hostPanel

	-- Toggle panel
	gearBtn.MouseButton1Click:Connect(function()
		hostPanel.Visible = not hostPanel.Visible
	end)

	-- Listen for GameConfig to know if we're the host
	local configEvent = EventManager.waitForEvent("GameConfig")
	configEvent.OnClientEvent:Connect(function(config)
		if config.hostId == player.UserId then
			isHost = true
			gearBtn.Visible = true
		else
			isHost = false
			gearBtn.Visible = false
			hostPanel.Visible = false
		end

		killTarget = config.killTarget or killTarget
		ktValue.Text = tostring(killTarget)
	end)

	print("[HostMenu] Initialized")
end

return HostMenu
