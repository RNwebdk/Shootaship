--[[
	KillsHUD (Client)
	=================
	Displays the player's kill count in a stylish badge at the top-right of the screen.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local KillsHUD = {}

local localPlayer = Players.LocalPlayer
local killLabel = nil
local hudFrame = nil
local currentKills = 0

function KillsHUD.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KillsHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	
	-- Container at top-right
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "KillsContainer"
	hudFrame.Size = UDim2.new(0, 120, 0, 44)
	hudFrame.Position = UDim2.new(1, -20, 0, 20)
	hudFrame.AnchorPoint = Vector2.new(1, 0)
	hudFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	hudFrame.BackgroundTransparency = 0.2
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = hudFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 60, 60)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = hudFrame
	
	-- Skull icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 30, 1, 0)
	icon.Position = UDim2.new(0, 8, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "\u{2620}"
	icon.TextSize = 22
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = Color3.fromRGB(220, 60, 60)
	icon.Parent = hudFrame
	
	-- Kill count label
	killLabel = Instance.new("TextLabel")
	killLabel.Name = "KillCount"
	killLabel.Size = UDim2.new(0, 70, 1, 0)
	killLabel.Position = UDim2.new(0, 38, 0, 0)
	killLabel.BackgroundTransparency = 1
	killLabel.Text = "0"
	killLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	killLabel.TextSize = 24
	killLabel.Font = Enum.Font.GothamBold
	killLabel.TextXAlignment = Enum.TextXAlignment.Left
	killLabel.Parent = hudFrame
	
	local killStroke = Instance.new("UIStroke")
	killStroke.Color = Color3.fromRGB(0, 0, 0)
	killStroke.Thickness = 1
	killStroke.Parent = killLabel
	
	print("[KillsHUD] Initialized")
end

function KillsHUD.setKills(kills: number)
	kills = kills or 0
	if kills == currentKills then return end
	
	local wasHigher = kills > currentKills
	currentKills = kills
	
	if not killLabel then return end
	killLabel.Text = tostring(kills)
	
	-- Flash on new kill
	if wasHigher and hudFrame then
		local original = hudFrame.BackgroundColor3
		hudFrame.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
		TweenService:Create(hudFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = original,
		}):Play()
		
		-- Scale pop on kill label
		if killLabel then
			killLabel.TextSize = 32
			TweenService:Create(killLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextSize = 24,
			}):Play()
		end
	end
end

return KillsHUD
