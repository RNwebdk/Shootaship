--[[
	AmmoHUD (Client)
	================
	Displays the player's current ammo count and active power-up
	indicators as fixed overlays on screen.
	
	Bottom-center: Ammo counter
	Above ammo: Active power-up badges (icon + timer/count)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local AmmoHUD = {}

local localPlayer = Players.LocalPlayer
local ammoLabel = nil
local hudFrame = nil
local screenGui = nil
local currentAmmo = 0

-- Active power-up indicator frames (created dynamically)
local powerupIndicators = {}

-- Power-up display config: { icon, color, label }
local POWERUP_CONFIG = {
	boost    = { "⚡", Color3.fromRGB(30, 160, 60),   "SPEED" },
	dmgBoost = { "🔥", Color3.fromRGB(180, 40, 40),   "DMG" },
	shield   = { "🛡", Color3.fromRGB(40, 80, 200),   "SHIELD" },
	scatter  = { "*",  Color3.fromRGB(140, 40, 180),  "SCATTER" },
	ghost    = { "👻", Color3.fromRGB(40, 190, 200),  "GHOST" },
	ram      = { "💥", Color3.fromRGB(220, 120, 20),  "RAM" },
	homing   = { "🎯", Color3.fromRGB(220, 80, 160),  "HOMING" },
	sBounce  = { "💢", Color3.fromRGB(120, 230, 50),  "S.BOUNCE" },
	mines    = { "💣", Color3.fromRGB(120, 20, 20),   "MINES" },
	mg       = { "🔫", Color3.fromRGB(70, 130, 180),  "MACHGUN" },
	block    = { "🗜", Color3.fromRGB(100, 255, 255), "BLOCK" },
	blockCd  = { "🗜", Color3.fromRGB(80, 80, 100),   "BLOCK CD" },
}

function AmmoHUD.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AmmoHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	
	-- Container at bottom-center
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "AmmoContainer"
	hudFrame.Size = UDim2.new(0, 180, 0, 50)
	hudFrame.Position = UDim2.new(0.5, 0, 1, -20)
	hudFrame.AnchorPoint = Vector2.new(0.5, 1)
	hudFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	hudFrame.BackgroundTransparency = 0.3
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = hudFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 100)
	stroke.Thickness = 1
	stroke.Parent = hudFrame
	
	-- Cannonball icon (circle)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 24, 0, 24)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	icon.BorderSizePixel = 0
	icon.Parent = hudFrame
	
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon
	
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 140, 0)
	iconStroke.Thickness = 2
	iconStroke.Parent = icon
	
	-- Ammo count label
	ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "AmmoCount"
	ammoLabel.Size = UDim2.new(0, 110, 1, 0)
	ammoLabel.Position = UDim2.new(0, 50, 0, 0)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Text = "0 / " .. Constants.MAX_AMMO
	ammoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	ammoLabel.TextSize = 22
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
	ammoLabel.Parent = hudFrame
	
	-- Listen for crate collection to flash the HUD
	local collectEvent = EventManager.waitForEvent("CrateCollected")
	collectEvent.OnClientEvent:Connect(function(data)
		if data.playerId == localPlayer.UserId then
			AmmoHUD.flashPickup()
		end
	end)
	
	print("[AmmoHUD] Initialized")
end

function AmmoHUD.setAmmo(ammo: number)
	if ammo == currentAmmo then return end
	currentAmmo = ammo
	
	if not ammoLabel then return end
	ammoLabel.Text = tostring(ammo) .. " / " .. Constants.MAX_AMMO
	
	if ammo <= 0 then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	elseif ammo <= 2 then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 200, 60)
	else
		ammoLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	end
end

function AmmoHUD.flashPickup()
	if not hudFrame then return end
	
	local original = hudFrame.BackgroundColor3
	hudFrame.BackgroundColor3 = Color3.fromRGB(80, 160, 40)
	
	TweenService:Create(hudFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = original,
	}):Play()
end

--[[
	Update all active power-up indicators.
	Called by ShipController with the current state data for our ship.
	
	powerups: { boost=2.1, dmgBoost=4.0, shield=1, scatter=2, ghost=1.5, ram=3.0, homing=1 }
	(nil values mean that power-up is not active)
]]
function AmmoHUD.setPowerUps(powerups)
	if not screenGui then return end
	
	-- Collect active power-ups
	local active = {}
	for key, config in POWERUP_CONFIG do
		local val = powerups[key]
		if val and val > 0 then
			table.insert(active, { key = key, value = val, config = config })
		end
	end
	
	-- Remove indicators that are no longer active
	for key, indicator in powerupIndicators do
		local stillActive = false
		for _, a in active do
			if a.key == key then stillActive = true; break end
		end
		if not stillActive then
			indicator:Destroy()
			powerupIndicators[key] = nil
		end
	end
	
	-- Create/update indicators, arranged horizontally above ammo bar
	local totalWidth = #active * 80  -- 80px per indicator
	local startX = -totalWidth / 2
	
	for idx, entry in active do
		local key = entry.key
		local val = entry.value
		local config = entry.config
		local iconText = config[1]
		local color = config[2]
		local label = config[3]
		
		local indicator = powerupIndicators[key]
		if not indicator then
			-- Create new indicator
			indicator = Instance.new("Frame")
			indicator.Name = "PU_" .. key
			indicator.Size = UDim2.new(0, 72, 0, 30)
			indicator.AnchorPoint = Vector2.new(0.5, 1)
			indicator.BackgroundColor3 = color
			indicator.BackgroundTransparency = 0.3
			indicator.BorderSizePixel = 0
			indicator.Parent = screenGui
			
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = indicator
			
			local lbl = Instance.new("TextLabel")
			lbl.Name = "Label"
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextSize = 13
			lbl.Font = Enum.Font.GothamBold
			lbl.Parent = indicator
			
			powerupIndicators[key] = indicator
		end
		
		-- Position
		local xOff = startX + (idx - 1) * 80 + 40
		indicator.Position = UDim2.new(0.5, xOff, 1, -78)
		
		-- Update text: show timer or count
		local textLabel = indicator:FindFirstChild("Label")
		if textLabel then
			if val == math.floor(val) and val <= 10 then
				-- Likely a count (shield hits, scatter volleys, homing shots)
				textLabel.Text = iconText .. " " .. label .. " x" .. tostring(val)
			else
				-- Timer
				textLabel.Text = iconText .. " " .. label .. " " .. string.format("%.1fs", val)
			end
		end
	end
end

return AmmoHUD
