--[[
	ScoreHUD (Client — Game Mode Only)
	====================================
	Top-center scoreboard showing all players' kills during deathmatch.
	Highlights the leader and shows the kill target.
	Also handles the Game Over overlay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EventManager = require(ReplicatedStorage.Shared.EventManager)

local ScoreHUD = {}

local player = Players.LocalPlayer
local screenGui = nil
local scoreContainer = nil
local gameOverOverlay = nil

local COLORS = {
	bg = Color3.fromHex("#0d1117"),
	panel = Color3.fromHex("#161b22"),
	panelBorder = Color3.fromHex("#30363d"),
	accent = Color3.fromHex("#58a6ff"),
	gold = Color3.fromHex("#d29922"),
	green = Color3.fromHex("#3fb950"),
	red = Color3.fromHex("#f85149"),
	text = Color3.fromHex("#e6edf3"),
	textMuted = Color3.fromHex("#8b949e"),
	separator = Color3.fromHex("#21262d"),
}

function ScoreHUD.init()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScoreHUDGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- ========================
	-- COMPACT SCOREBOARD (top-center)
	-- ========================
	scoreContainer = Instance.new("Frame")
	scoreContainer.Name = "ScoreContainer"
	scoreContainer.Size = UDim2.new(0, 280, 0, 36)
	scoreContainer.Position = UDim2.new(0.5, -140, 0, 8)
	scoreContainer.BackgroundColor3 = COLORS.panel
	scoreContainer.BackgroundTransparency = 0.15
	scoreContainer.BorderSizePixel = 0
	scoreContainer.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = scoreContainer

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = scoreContainer

	-- Kill target label
	local targetLabel = Instance.new("TextLabel")
	targetLabel.Name = "TargetLabel"
	targetLabel.Size = UDim2.new(1, 0, 0, 14)
	targetLabel.Position = UDim2.new(0, 0, 0, 2)
	targetLabel.BackgroundTransparency = 1
	targetLabel.Text = "FIRST TO 10 KILLS"
	targetLabel.TextColor3 = COLORS.textMuted
	targetLabel.Font = Enum.Font.GothamBold
	targetLabel.TextSize = 9
	targetLabel.Parent = scoreContainer

	-- Score entries (will be dynamically populated)
	local scoresFrame = Instance.new("Frame")
	scoresFrame.Name = "ScoresFrame"
	scoresFrame.Size = UDim2.new(1, -12, 0, 18)
	scoresFrame.Position = UDim2.new(0, 6, 0, 16)
	scoresFrame.BackgroundTransparency = 1
	scoresFrame.Parent = scoreContainer

	local scoresLayout = Instance.new("UIListLayout")
	scoresLayout.FillDirection = Enum.FillDirection.Horizontal
	scoresLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scoresLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	scoresLayout.Padding = UDim.new(0, 12)
	scoresLayout.Parent = scoresFrame

	-- Expanded scoreboard (toggleable)
	local expandedBoard = Instance.new("Frame")
	expandedBoard.Name = "ExpandedBoard"
	expandedBoard.Size = UDim2.new(0, 300, 0, 0)
	expandedBoard.Position = UDim2.new(0.5, -150, 0, 50)
	expandedBoard.BackgroundColor3 = COLORS.panel
	expandedBoard.BackgroundTransparency = 0.05
	expandedBoard.BorderSizePixel = 0
	expandedBoard.Visible = false
	expandedBoard.AutomaticSize = Enum.AutomaticSize.Y
	expandedBoard.Parent = screenGui

	local expandCorner = Instance.new("UICorner")
	expandCorner.CornerRadius = UDim.new(0, 10)
	expandCorner.Parent = expandedBoard

	local expandStroke = Instance.new("UIStroke")
	expandStroke.Color = COLORS.panelBorder
	expandStroke.Thickness = 1
	expandStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	expandStroke.Parent = expandedBoard

	local expandPadding = Instance.new("UIPadding")
	expandPadding.PaddingTop = UDim.new(0, 10)
	expandPadding.PaddingBottom = UDim.new(0, 10)
	expandPadding.PaddingLeft = UDim.new(0, 12)
	expandPadding.PaddingRight = UDim.new(0, 12)
	expandPadding.Parent = expandedBoard

	local expandLayout = Instance.new("UIListLayout")
	expandLayout.SortOrder = Enum.SortOrder.LayoutOrder
	expandLayout.Padding = UDim.new(0, 4)
	expandLayout.Parent = expandedBoard

	-- Toggle expand on click
	local expandToggle = Instance.new("TextButton")
	expandToggle.Size = UDim2.new(1, 0, 1, 0)
	expandToggle.BackgroundTransparency = 1
	expandToggle.Text = ""
	expandToggle.Parent = scoreContainer

	expandToggle.MouseButton1Click:Connect(function()
		expandedBoard.Visible = not expandedBoard.Visible
	end)

	local function updateScores(data)
		if not data then return end
		local scores = data.scores
		local killTarget = data.killTarget

		targetLabel.Text = "FIRST TO " .. tostring(killTarget) .. " KILLS"

		-- Sort players by kills
		local sorted = {}
		for userId, info in scores do
			table.insert(sorted, {
				userId = tonumber(userId),
				kills = info.kills,
				name = info.name,
				displayName = info.displayName,
			})
		end
		table.sort(sorted, function(a, b) return a.kills > b.kills end)

		-- Update compact scoreboard (top 3)
		for _, child in scoresFrame:GetChildren() do
			if child:IsA("TextLabel") then child:Destroy() end
		end

		local compactWidth = math.min(#sorted, 4)
		scoreContainer.Size = UDim2.new(0, math.max(280, compactWidth * 80 + 20), 0, 36)
		scoreContainer.Position = UDim2.new(0.5, -scoreContainer.Size.X.Offset / 2, 0, 8)

		for i = 1, math.min(#sorted, 4) do
			local entry = sorted[i]
			local entryLabel = Instance.new("TextLabel")
			entryLabel.Size = UDim2.new(0, 70, 0, 18)
			entryLabel.BackgroundTransparency = 1
			entryLabel.LayoutOrder = i

			local displayName = entry.displayName or entry.name
			if #displayName > 8 then
				displayName = displayName:sub(1, 7) .. "…"
			end

			entryLabel.Text = displayName .. " " .. entry.kills
			entryLabel.Font = Enum.Font.GothamBold
			entryLabel.TextSize = 12

			-- Color: leader gets gold, local player gets accent
			if i == 1 then
				entryLabel.TextColor3 = COLORS.gold
			elseif entry.userId == player.UserId then
				entryLabel.TextColor3 = COLORS.accent
			else
				entryLabel.TextColor3 = COLORS.text
			end

			entryLabel.Parent = scoresFrame
		end

		-- Update expanded scoreboard
		for _, child in expandedBoard:GetChildren() do
			if child:IsA("Frame") then child:Destroy() end
		end

		for i, entry in sorted do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = expandedBoard

			local rankLabel = Instance.new("TextLabel")
			rankLabel.Size = UDim2.new(0, 24, 1, 0)
			rankLabel.BackgroundTransparency = 1
			rankLabel.Text = "#" .. i
			rankLabel.TextColor3 = i == 1 and COLORS.gold or COLORS.textMuted
			rankLabel.Font = Enum.Font.GothamBold
			rankLabel.TextSize = 13
			rankLabel.TextXAlignment = Enum.TextXAlignment.Left
			rankLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.6, -24, 1, 0)
			nameLabel.Position = UDim2.new(0, 28, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = entry.displayName or entry.name
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			if entry.userId == player.UserId then
				nameLabel.TextColor3 = COLORS.accent
			else
				nameLabel.TextColor3 = COLORS.text
			end

			local killsLabel = Instance.new("TextLabel")
			killsLabel.Size = UDim2.new(0.3, 0, 1, 0)
			killsLabel.Position = UDim2.new(0.7, 0, 0, 0)
			killsLabel.BackgroundTransparency = 1
			killsLabel.Text = tostring(entry.kills) .. " kills"
			killsLabel.TextColor3 = i == 1 and COLORS.gold or COLORS.textMuted
			killsLabel.Font = Enum.Font.Gotham
			killsLabel.TextSize = 12
			killsLabel.TextXAlignment = Enum.TextXAlignment.Right
			killsLabel.Parent = row
		end
	end

	-- === GAME OVER OVERLAY ===
	local function showGameOver(data)
		if gameOverOverlay then gameOverOverlay:Destroy() end

		gameOverOverlay = Instance.new("Frame")
		gameOverOverlay.Name = "GameOverOverlay"
		gameOverOverlay.Size = UDim2.new(1, 0, 1, 0)
		gameOverOverlay.BackgroundColor3 = COLORS.bg
		gameOverOverlay.BackgroundTransparency = 0.3
		gameOverOverlay.ZIndex = 50
		gameOverOverlay.Parent = screenGui

		-- Winner announcement
		local winnerLabel = Instance.new("TextLabel")
		winnerLabel.Size = UDim2.new(1, 0, 0, 60)
		winnerLabel.Position = UDim2.new(0, 0, 0.25, 0)
		winnerLabel.BackgroundTransparency = 1
		winnerLabel.Text = (data.winnerDisplayName or data.winnerName or "???") .. " WINS!"
		winnerLabel.TextColor3 = COLORS.gold
		winnerLabel.Font = Enum.Font.GothamBlack
		winnerLabel.TextSize = 48
		winnerLabel.ZIndex = 51
		winnerLabel.Parent = gameOverOverlay

		-- Subtitle
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Size = UDim2.new(1, 0, 0, 24)
		subtitleLabel.Position = UDim2.new(0, 0, 0.25, 60)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Text = "Game restarting soon..."
		subtitleLabel.TextColor3 = COLORS.textMuted
		subtitleLabel.Font = Enum.Font.Gotham
		subtitleLabel.TextSize = 16
		subtitleLabel.ZIndex = 51
		subtitleLabel.Parent = gameOverOverlay

		-- Final scoreboard
		local finalBoard = Instance.new("Frame")
		finalBoard.Size = UDim2.new(0, 320, 0, 0)
		finalBoard.Position = UDim2.new(0.5, -160, 0.4, 0)
		finalBoard.BackgroundColor3 = COLORS.panel
		finalBoard.BorderSizePixel = 0
		finalBoard.AutomaticSize = Enum.AutomaticSize.Y
		finalBoard.ZIndex = 51
		finalBoard.Parent = gameOverOverlay

		local fbCorner = Instance.new("UICorner")
		fbCorner.CornerRadius = UDim.new(0, 10)
		fbCorner.Parent = finalBoard

		local fbStroke = Instance.new("UIStroke")
		fbStroke.Color = COLORS.gold
		fbStroke.Thickness = 2
		fbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		fbStroke.Parent = finalBoard

		local fbPadding = Instance.new("UIPadding")
		fbPadding.PaddingTop = UDim.new(0, 12)
		fbPadding.PaddingBottom = UDim.new(0, 12)
		fbPadding.PaddingLeft = UDim.new(0, 16)
		fbPadding.PaddingRight = UDim.new(0, 16)
		fbPadding.Parent = finalBoard

		local fbLayout = Instance.new("UIListLayout")
		fbLayout.SortOrder = Enum.SortOrder.LayoutOrder
		fbLayout.Padding = UDim.new(0, 6)
		fbLayout.Parent = finalBoard

		-- Title row
		local fbTitle = Instance.new("TextLabel")
		fbTitle.Size = UDim2.new(1, 0, 0, 24)
		fbTitle.BackgroundTransparency = 1
		fbTitle.Text = "FINAL SCORES"
		fbTitle.TextColor3 = COLORS.gold
		fbTitle.Font = Enum.Font.GothamBlack
		fbTitle.TextSize = 14
		fbTitle.LayoutOrder = 0
		fbTitle.ZIndex = 52
		fbTitle.Parent = finalBoard

		-- Sort scores
		local sorted = {}
		if data.scores then
			for userId, info in data.scores do
				table.insert(sorted, {
					userId = tonumber(userId),
					kills = info.kills,
					name = info.name,
					displayName = info.displayName,
				})
			end
		end
		table.sort(sorted, function(a, b) return a.kills > b.kills end)

		for i, entry in sorted do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.ZIndex = 52
			row.Parent = finalBoard

			local rankText = Instance.new("TextLabel")
			rankText.Size = UDim2.new(0, 24, 1, 0)
			rankText.BackgroundTransparency = 1
			rankText.Text = "#" .. i
			rankText.TextColor3 = i == 1 and COLORS.gold or COLORS.textMuted
			rankText.Font = Enum.Font.GothamBold
			rankText.TextSize = 13
			rankText.TextXAlignment = Enum.TextXAlignment.Left
			rankText.ZIndex = 52
			rankText.Parent = row

			local nameText = Instance.new("TextLabel")
			nameText.Size = UDim2.new(0.6, -24, 1, 0)
			nameText.Position = UDim2.new(0, 28, 0, 0)
			nameText.BackgroundTransparency = 1
			nameText.Text = entry.displayName or entry.name
			nameText.Font = Enum.Font.GothamBold
			nameText.TextSize = 13
			nameText.TextXAlignment = Enum.TextXAlignment.Left
			nameText.ZIndex = 52
			nameText.Parent = row

			if tonumber(entry.userId) == data.winnerId then
				nameText.TextColor3 = COLORS.gold
			elseif tonumber(entry.userId) == player.UserId then
				nameText.TextColor3 = COLORS.accent
			else
				nameText.TextColor3 = COLORS.text
			end

			local killsText = Instance.new("TextLabel")
			killsText.Size = UDim2.new(0.3, 0, 1, 0)
			killsText.Position = UDim2.new(0.7, 0, 0, 0)
			killsText.BackgroundTransparency = 1
			killsText.Text = tostring(entry.kills) .. " kills"
			killsText.TextColor3 = COLORS.textMuted
			killsText.Font = Enum.Font.Gotham
			killsText.TextSize = 12
			killsText.TextXAlignment = Enum.TextXAlignment.Right
			killsText.ZIndex = 52
			killsText.Parent = row
		end

		-- Auto-dismiss
		task.delay(8, function()
			if gameOverOverlay and gameOverOverlay.Parent then
				local fadeTween = TweenService:Create(gameOverOverlay, TweenInfo.new(1), {
					BackgroundTransparency = 1,
				})
				fadeTween:Play()
				fadeTween.Completed:Wait()
				if gameOverOverlay then gameOverOverlay:Destroy() end
				gameOverOverlay = nil
			end
		end)
	end

	-- === EVENT LISTENERS ===
	local scoreEvent = EventManager.waitForEvent("ScoreUpdate")
	scoreEvent.OnClientEvent:Connect(function(data)
		updateScores(data)
	end)

	local gameOverEvent = EventManager.waitForEvent("GameOver")
	gameOverEvent.OnClientEvent:Connect(function(data)
		showGameOver(data)
	end)

	print("[ScoreHUD] Initialized")
end

return ScoreHUD
