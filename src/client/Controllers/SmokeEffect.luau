--[[
	SmokeEffect (Client)
	====================
	Emits dark smoke puffs from damaged ships based on health percentage.
	
	Smoke intensity tiers:
	  100-76% HP = no smoke
	  75-51% HP  = light smoke (few small puffs)
	  50-26% HP  = medium smoke (more puffs, darker)
	  25-1% HP   = heavy smoke (lots of big dark puffs)
	
	Smoke particles are parented to the game canvas and positioned
	in world-space so they drift upward and linger behind the ship.
]]

local SmokeEffect = {}

-- All active smoke particles across all ships
local smokeParticles = {}

-- Per-ship spawn timers
local spawnTimers = {}

-- Config
local MAX_SMOKE_PARTICLES = 300
local SMOKE_LIFETIME = 1.0
local DRIFT_SPEED = 30           -- world units/sec upward drift

--[[
	Smoke tier config based on health fraction.
	Returns: spawnInterval, particlesPerTick, sizeMin, sizeMax, startAlpha, colors
]]
local function getSmokeConfig(hpFrac: number)
	if hpFrac > 0.75 then
		-- No smoke
		return nil
	elseif hpFrac > 0.50 then
		-- Light smoke: sparse, small, lighter gray puffs
		return {
			interval = 0.18,
			count = 1,
			sizeMin = 5,
			sizeMax = 9,
			alphaMin = 0.45,
			alphaMax = 0.60,
			colors = {
				Color3.fromRGB(140, 140, 140),
				Color3.fromRGB(160, 160, 160),
				Color3.fromRGB(150, 145, 135),
			},
		}
	elseif hpFrac > 0.25 then
		-- Medium smoke: moderate, bigger, darker puffs
		return {
			interval = 0.10,
			count = 2,
			sizeMin = 7,
			sizeMax = 14,
			alphaMin = 0.30,
			alphaMax = 0.50,
			colors = {
				Color3.fromRGB(100, 100, 100),
				Color3.fromRGB(80, 80, 80),
				Color3.fromRGB(110, 105, 90),
			},
		}
	else
		-- Heavy smoke: dense, large, very dark puffs with occasional embers
		return {
			interval = 0.05,
			count = 3,
			sizeMin = 9,
			sizeMax = 18,
			alphaMin = 0.15,
			alphaMax = 0.35,
			colors = {
				Color3.fromRGB(50, 50, 50),
				Color3.fromRGB(40, 40, 40),
				Color3.fromRGB(65, 55, 40),
				Color3.fromRGB(70, 45, 30),
			},
		}
	end
end

--[[
	Emit smoke for a ship if damaged enough.
	
	@param shipId:        unique identifier
	@param worldPos:      Vector2 world position of ship center
	@param rotation:      number in radians
	@param hpFrac:        number 0-1 (health / max health)
	@param canvas:        Frame to parent particles to
	@param worldToCanvas: function(Vector2) → UDim2
]]
function SmokeEffect.emit(shipId, worldPos: Vector2, rotation: number, hpFrac: number, canvas: Frame, worldToCanvas)
	local config = getSmokeConfig(hpFrac)
	if not config then
		spawnTimers[shipId] = nil
		return
	end
	
	if #smokeParticles >= MAX_SMOKE_PARTICLES then return end
	
	-- Spawn timer
	spawnTimers[shipId] = (spawnTimers[shipId] or 0)
	if spawnTimers[shipId] > 0 then return end
	spawnTimers[shipId] = config.interval
	
	-- Spawn from center/upper area of ship with some random spread
	for _ = 1, config.count do
		if #smokeParticles >= MAX_SMOKE_PARTICLES then break end
		
		-- Random position around ship center
		local spreadX = (math.random() - 0.5) * 20
		local spreadY = (math.random() - 0.5) * 16
		local spawnPos = worldPos + Vector2.new(spreadX, spreadY)
		
		-- Random drift direction: mostly upward (negative Y in world/canvas),
		-- with horizontal spread
		local driftX = (math.random() - 0.5) * 25
		local driftY = -DRIFT_SPEED - math.random() * 15 -- upward in screen space
		local driftDir = Vector2.new(driftX, driftY)
		
		local size = math.random(config.sizeMin, config.sizeMax)
		local color = config.colors[math.random(1, #config.colors)]
		
		local puff = Instance.new("Frame")
		puff.Name = "Smoke"
		puff.Size = UDim2.new(0, size, 0, size)
		puff.AnchorPoint = Vector2.new(0.5, 0.5)
		puff.Position = worldToCanvas(spawnPos)
		puff.BackgroundColor3 = color
		puff.BackgroundTransparency = config.alphaMin + math.random() * (config.alphaMax - config.alphaMin)
		puff.BorderSizePixel = 0
		puff.ZIndex = 6
		puff.Rotation = math.random(0, 360)
		puff.Parent = canvas
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = puff
		
		table.insert(smokeParticles, {
			frame = puff,
			worldPos = spawnPos,
			driftDir = driftDir,
			age = 0,
			lifetime = SMOKE_LIFETIME + (math.random() - 0.5) * 0.4,
			startTransparency = puff.BackgroundTransparency,
			startSize = size,
			growFactor = 1.4 + math.random() * 0.6,  -- smoke expands as it rises
			worldToCanvas = worldToCanvas,
		})
	end
	
	-- Occasional ember/spark at very low HP
	if hpFrac <= 0.25 and math.random() < 0.3 then
		if #smokeParticles < MAX_SMOKE_PARTICLES then
			local emberPos = worldPos + Vector2.new((math.random() - 0.5) * 16, (math.random() - 0.5) * 12)
			local emberSize = math.random(2, 4)
			
			local ember = Instance.new("Frame")
			ember.Name = "Ember"
			ember.Size = UDim2.new(0, emberSize, 0, emberSize)
			ember.AnchorPoint = Vector2.new(0.5, 0.5)
			ember.Position = worldToCanvas(emberPos)
			ember.BackgroundColor3 = Color3.fromRGB(255, math.random(120, 200), 30)
			ember.BackgroundTransparency = 0
			ember.BorderSizePixel = 0
			ember.ZIndex = 7
			ember.Parent = canvas
			
			local ec = Instance.new("UICorner")
			ec.CornerRadius = UDim.new(1, 0)
			ec.Parent = ember
			
			local emberDriftX = (math.random() - 0.5) * 40
			local emberDriftY = -(35 + math.random() * 25)
			
			table.insert(smokeParticles, {
				frame = ember,
				worldPos = emberPos,
				driftDir = Vector2.new(emberDriftX, emberDriftY),
				age = 0,
				lifetime = 0.4 + math.random() * 0.3,
				startTransparency = 0,
				startSize = emberSize,
				growFactor = 0.3,  -- embers shrink
				worldToCanvas = worldToCanvas,
			})
		end
	end
end

--[[
	Updates all smoke particles. Call every frame.
]]
function SmokeEffect.update(deltaTime: number)
	-- Tick down per-ship spawn timers
	for shipId, timer in spawnTimers do
		spawnTimers[shipId] = timer - deltaTime
	end
	
	local i = #smokeParticles
	while i >= 1 do
		local p = smokeParticles[i]
		p.age = p.age + deltaTime
		
		if p.age >= p.lifetime then
			p.frame:Destroy()
			table.remove(smokeParticles, i)
		else
			local progress = p.age / p.lifetime  -- 0 → 1
			
			-- Fade out
			local startT = p.startTransparency
			p.frame.BackgroundTransparency = startT + ((1 - startT) * progress)
			
			-- Grow (smoke expands) or shrink (embers)
			local scale = 1 + (p.growFactor - 1) * progress
			local sz = math.max(1, p.startSize * scale)
			p.frame.Size = UDim2.new(0, sz, 0, sz)
			
			-- Drift upward
			p.worldPos = p.worldPos + (p.driftDir * deltaTime)
			p.frame.Position = p.worldToCanvas(p.worldPos)
		end
		
		i = i - 1
	end
end

-- Clean up all smoke (e.g., on round reset)
function SmokeEffect.clear()
	for _, p in smokeParticles do
		p.frame:Destroy()
	end
	table.clear(smokeParticles)
	table.clear(spawnTimers)
end

return SmokeEffect
