--[[
	InputController (Client)
	========================
	Captures keyboard input and sends it to the server.
	
	WHY this runs on the client:
	  Only the client knows what keys the player is pressing.
	  We read input here, then send it to the server as a compact message.
	  
	  We do NOT move the ship here — the server does that.
	  The client just says "I'm pressing W and turning left."
	
	HOW INPUT WORKS IN ROBLOX:
	  Roblox has UserInputService (UIS) — similar to addEventListener("keydown").
	  We track which keys are currently held down, then every frame we send
	  the current state to the server.
	  
	  We send input EVERY frame (not just on key press/release) because:
	  - It's simpler and more reliable
	  - The server always has the latest state
	  - Handles missed events gracefully
	
	ANALOGY:
	  Like polling vs events in web dev. We poll the keyboard state each
	  frame and POST it to the server.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local EventManager = require(ReplicatedStorage.Shared.EventManager)

local InputController = {}

-- Track which keys are currently held down
local keysDown = {}

function InputController.init()
	local inputEvent = EventManager.waitForEvent("PlayerInput")
	local fireEvent = EventManager.waitForEvent("FireCannon")
	local deployMineEvent = EventManager.waitForEvent("DeployMine")
	local dashEvent = EventManager.waitForEvent("Dash")
	local blockEvent = EventManager.waitForEvent("Block")
	
	--[[
		InputBegan fires when a key is PRESSED.
		InputEnded fires when a key is RELEASED.
		
		gameProcessedEvent = true means Roblox already handled this input
		(e.g., typing in a chat box). We ignore those to prevent moving
		while chatting.
	]]
	UserInputService.InputBegan:Connect(function(inputObj, gameProcessedEvent)
		if gameProcessedEvent then return end
		keysDown[inputObj.KeyCode] = true
		
		-- Fire cannon on spacebar press (not hold — one shot per press)
		if inputObj.KeyCode == Enum.KeyCode.Space then
			fireEvent:FireServer()
		end
		
		-- Deploy naval mine on E press
		if inputObj.KeyCode == Enum.KeyCode.E then
			deployMineEvent:FireServer()
		end
		
		-- Dash on Q press (one burst per press, server handles cooldown)
		if inputObj.KeyCode == Enum.KeyCode.Q then
			dashEvent:FireServer()
		end
		
		-- Block / shockwave on F press (server handles cooldown)
		if inputObj.KeyCode == Enum.KeyCode.F then
			print("[InputController] F pressed — firing Block event")
			blockEvent:FireServer()
		end
	end)
	
	UserInputService.InputEnded:Connect(function(inputObj, gameProcessedEvent)
		keysDown[inputObj.KeyCode] = nil
	end)
	
	--[[
		Every frame, read the current key state and send it to the server.
		
		We convert keys into simple -1/0/1 values:
		  thrust:  W=1, S=-1, neither=0
		  turn:    A=-1, D=1, neither=0
		
		This is a compact representation — the server doesn't need to know
		which specific keys are pressed, just the intent.
	]]
	RunService.Heartbeat:Connect(function()
		local thrust = 0
		local turn = 0
		
		-- W or Up Arrow = forward thrust
		if keysDown[Enum.KeyCode.W] or keysDown[Enum.KeyCode.Up] then
			thrust = thrust + 1
		end
		-- S or Down Arrow = reverse thrust
		if keysDown[Enum.KeyCode.S] or keysDown[Enum.KeyCode.Down] then
			thrust = thrust - 1
		end
		-- A or Left Arrow = turn left
		if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left] then
			turn = turn - 1
		end
		-- D or Right Arrow = turn right
		if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then
			turn = turn + 1
		end
		
		-- Only send if there's actual input (saves bandwidth when idle)
		if thrust ~= 0 or turn ~= 0 then
			inputEvent:FireServer({ thrust = thrust, turn = turn })
		else
			-- Send zero input occasionally to clear server-side state
			-- (otherwise the ship would keep thrusting after key release)
			inputEvent:FireServer({ thrust = 0, turn = 0 })
		end
	end)
	
	print("[InputController] Initialized — W/S=thrust, A/D=turn, Q=dash, Space=fire, E=mine, F=block")
end

return InputController
