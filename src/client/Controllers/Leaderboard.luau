--[[
	Leaderboard (Client)
	====================
	Displays a live scoreboard showing all players sorted by kills.
	Updated every state sync tick from ShipController.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Leaderboard = {}

local localPlayer = Players.LocalPlayer
local container = nil
local rowsFrame = nil
local rows = {} -- reusable row frames

local MAX_ROWS = 10
local ROW_HEIGHT = 26
local PANEL_WIDTH = 180

function Leaderboard.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LeaderboardUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 8
	screenGui.Parent = playerGui

	-- Container on the right side, below KillsHUD
	container = Instance.new("Frame")
	container.Name = "LeaderboardPanel"
	container.Size = UDim2.new(0, PANEL_WIDTH, 0, 30) -- will resize dynamically
	container.Position = UDim2.new(1, -20, 0, 80)
	container.AnchorPoint = Vector2.new(1, 0)
	container.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	container.BackgroundTransparency = 0.25
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 140, 220)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = container

	-- Header
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 28)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundTransparency = 1
	header.Text = "\u{1F3C6} LEADERBOARD"
	header.TextColor3 = Color3.fromRGB(255, 220, 80)
	header.TextSize = 14
	header.Font = Enum.Font.GothamBold
	header.Parent = container

	-- Rows container
	rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.Size = UDim2.new(1, 0, 1, -28)
	rowsFrame.Position = UDim2.new(0, 0, 0, 28)
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.BorderSizePixel = 0
	rowsFrame.Parent = container

	-- Pre-create row frames
	for i = 1, MAX_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
		row.Position = UDim2.new(0, 6, 0, (i - 1) * ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Visible = false
		row.Parent = rowsFrame

		-- Rank label
		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.Size = UDim2.new(0, 22, 1, 0)
		rank.Position = UDim2.new(0, 0, 0, 0)
		rank.BackgroundTransparency = 1
		rank.TextColor3 = Color3.fromRGB(160, 160, 180)
		rank.TextSize = 12
		rank.Font = Enum.Font.GothamBold
		rank.TextXAlignment = Enum.TextXAlignment.Center
		rank.Text = ""
		rank.Parent = row

		-- Name label
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.Size = UDim2.new(1, -60, 1, 0)
		name.Position = UDim2.new(0, 24, 0, 0)
		name.BackgroundTransparency = 1
		name.TextColor3 = Color3.fromRGB(220, 220, 230)
		name.TextSize = 13
		name.Font = Enum.Font.GothamMedium
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = ""
		name.Parent = row

		-- Kills label
		local kills = Instance.new("TextLabel")
		kills.Name = "Kills"
		kills.Size = UDim2.new(0, 34, 1, 0)
		kills.Position = UDim2.new(1, -34, 0, 0)
		kills.BackgroundTransparency = 1
		kills.TextColor3 = Color3.fromRGB(220, 60, 60)
		kills.TextSize = 14
		kills.Font = Enum.Font.GothamBold
		kills.TextXAlignment = Enum.TextXAlignment.Right
		kills.Text = ""
		kills.Parent = row

		rows[i] = row
	end

	print("[Leaderboard] Initialized")
end

--[[
	Called from ShipController.onStateSync with the full stateData table.
	Extracts userId + kills, sorts by kills desc, updates the UI rows.
]]
function Leaderboard.updateScores(stateData)
	if not container then return end

	-- Build sorted list
	local entries = {}
	for userIdStr, data in stateData do
		local userId = tonumber(userIdStr) or userIdStr
		local killCount = data.kills or 0

		-- Resolve display name
		local displayName
		local player = Players:GetPlayerByUserId(userId)
		if player then
			displayName = player.DisplayName
		elseif userId < 0 then
			-- Negative userId with no matching player = bot
			displayName = "Bot"
		else
			displayName = "Player " .. tostring(userId)
		end

		table.insert(entries, { userId = userId, name = displayName, kills = killCount })
	end

	-- Sort by kills descending, then by name ascending for ties
	table.sort(entries, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.name < b.name
	end)

	-- Update rows
	local count = math.min(#entries, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = rows[i]
		if i <= count then
			local entry = entries[i]
			row.Visible = true

			local rankLabel = row:FindFirstChild("Rank")
			local nameLabel = row:FindFirstChild("PlayerName")
			local killsLabel = row:FindFirstChild("Kills")

			-- Rank with medal for top 3
			if i == 1 then
				rankLabel.Text = "\u{1F947}"
			elseif i == 2 then
				rankLabel.Text = "\u{1F948}"
			elseif i == 3 then
				rankLabel.Text = "\u{1F949}"
			else
				rankLabel.Text = tostring(i)
			end

			nameLabel.Text = entry.name

			-- Highlight local player's row
			if entry.userId == localPlayer.UserId then
				nameLabel.TextColor3 = Color3.fromRGB(80, 220, 255)
				nameLabel.Font = Enum.Font.GothamBold
			else
				nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
				nameLabel.Font = Enum.Font.GothamMedium
			end

			killsLabel.Text = tostring(entry.kills)
		else
			row.Visible = false
		end
	end

	-- Resize container to fit rows
	local totalHeight = 28 + count * ROW_HEIGHT + 6
	container.Size = UDim2.new(0, PANEL_WIDTH, 0, totalHeight)
end

return Leaderboard
