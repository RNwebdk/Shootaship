--[[
	HealthHUD (Client)
	==================
	Big screen-level health bar — cartoon style with thick outline,
	rounded corners, animated fill, and pulse effect on damage.
	Positioned at top-center of the screen.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local HealthHUD = {}

local localPlayer = Players.LocalPlayer
local screenGui = nil
local barContainer = nil
local barFill = nil
local barTrail = nil -- trailing "damage ghost" bar
local hpLabel = nil
local heartIcon = nil
local lastHP = Constants.SHIP_MAX_HEALTH

function HealthHUD.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HealthHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 12
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui
	
	-- Outer container (thick cartoon border)
	barContainer = Instance.new("Frame")
	barContainer.Name = "HealthBar"
	barContainer.Size = UDim2.new(0, 300, 0, 32)
	barContainer.Position = UDim2.new(0.5, 0, 0, 18)
	barContainer.AnchorPoint = Vector2.new(0.5, 0)
	barContainer.BackgroundColor3 = Color3.fromRGB(20, 15, 25)
	barContainer.BackgroundTransparency = 0.1
	barContainer.BorderSizePixel = 0
	barContainer.Parent = screenGui
	
	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 14)
	outerCorner.Parent = barContainer
	
	-- Thick cartoon outline
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = Color3.fromRGB(40, 35, 50)
	outerStroke.Thickness = 3
	outerStroke.Parent = barContainer
	
	-- Inner background (slightly inset)
	local innerBg = Instance.new("Frame")
	innerBg.Name = "InnerBg"
	innerBg.Size = UDim2.new(1, -12, 1, -10)
	innerBg.Position = UDim2.new(0, 6, 0, 5)
	innerBg.BackgroundColor3 = Color3.fromRGB(35, 25, 30)
	innerBg.BorderSizePixel = 0
	innerBg.Parent = barContainer
	
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 10)
	innerCorner.Parent = innerBg
	
	-- Damage trail bar (red, lags behind actual HP)
	barTrail = Instance.new("Frame")
	barTrail.Name = "Trail"
	barTrail.Size = UDim2.new(1, 0, 1, 0)
	barTrail.Position = UDim2.new(0, 0, 0, 0)
	barTrail.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	barTrail.BorderSizePixel = 0
	barTrail.ZIndex = 2
	barTrail.Parent = innerBg
	
	local trailCorner = Instance.new("UICorner")
	trailCorner.CornerRadius = UDim.new(0, 10)
	trailCorner.Parent = barTrail
	
	-- Main fill bar (green → yellow → red)
	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.Position = UDim2.new(0, 0, 0, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 3
	barFill.Parent = innerBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 10)
	fillCorner.Parent = barFill
	
	-- Shine highlight on fill bar (cartoon gloss)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(1, -4, 0.3, 0)
	shine.Position = UDim2.new(0, 2, 0, 2)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.75
	shine.BorderSizePixel = 0
	shine.ZIndex = 4
	shine.Parent = barFill
	
	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 8)
	shineCorner.Parent = shine
	
	-- Heart icon
	heartIcon = Instance.new("TextLabel")
	heartIcon.Name = "Heart"
	heartIcon.Size = UDim2.new(0, 30, 0, 30)
	heartIcon.Position = UDim2.new(0, -22, 0.5, 0)
	heartIcon.AnchorPoint = Vector2.new(1, 0.5)
	heartIcon.BackgroundTransparency = 1
	heartIcon.Text = "❤"
	heartIcon.TextSize = 22
	heartIcon.Font = Enum.Font.GothamBold
	heartIcon.TextColor3 = Color3.fromRGB(255, 80, 80)
	heartIcon.ZIndex = 5
	heartIcon.Parent = barContainer
	
	-- HP text overlay
	hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPText"
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.Position = UDim2.new(0, 0, 0, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = "100 / 100"
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextSize = 14
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0.3
	hpLabel.ZIndex = 5
	hpLabel.Parent = barContainer
	
	print("[HealthHUD] Initialized")
end

function HealthHUD.setHealth(hp: number)
	if not barFill then return end
	
	local maxHP = Constants.SHIP_MAX_HEALTH
	local hpFrac = math.clamp(hp / maxHP, 0, 1)
	
	-- Animate fill bar
	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(hpFrac, 0, 1, 0),
	}):Play()
	
	-- Trail bar follows slower (shows damage taken)
	if hp < lastHP then
		task.delay(0.4, function()
			if barTrail then
				TweenService:Create(barTrail, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(hpFrac, 0, 1, 0),
				}):Play()
			end
		end)
	else
		-- Healing — trail catches up immediately
		TweenService:Create(barTrail, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(hpFrac, 0, 1, 0),
		}):Play()
	end
	
	-- Color gradient: green → yellow → red
	local fillColor
	if hpFrac > 0.5 then
		local t2 = (hpFrac - 0.5) * 2
		fillColor = Color3.fromRGB(
			math.floor(240 * (1 - t2)),
			math.floor(200 + 40 * t2),
			80
		)
	else
		local t2 = hpFrac * 2
		fillColor = Color3.fromRGB(
			240,
			math.floor(200 * t2),
			80
		)
	end
	
	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = fillColor,
	}):Play()
	
	-- Update text
	if hpLabel then
		hpLabel.Text = tostring(math.floor(hp)) .. " / " .. tostring(maxHP)
	end
	
	-- Shake/pulse on damage
	if hp < lastHP and barContainer then
		local origPos = barContainer.Position
		barContainer.Position = origPos + UDim2.new(0, math.random(-4, 4), 0, math.random(-2, 2))
		TweenService:Create(barContainer, TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Position = origPos,
		}):Play()
	end
	
	lastHP = hp
end

return HealthHUD
