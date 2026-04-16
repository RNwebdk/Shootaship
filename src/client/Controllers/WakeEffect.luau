--[[
	WakeEffect (Client)
	===================
	Spawns small white square "bubbles" behind moving ships
	that smoothly fade away. Purely visual — runs only on the client.
	
	HOW IT WORKS:
	  Every few frames, if a ship is moving fast enough, we spawn a small
	  white square Frame at the ship's stern (back). Each particle:
	  - Starts white and semi-transparent
	  - Slowly fades to fully transparent over its lifetime
	  - Drifts slightly in a random direction (simulates water turbulence)
	  - Gets destroyed when fully faded
	
	  We use a simple "particle pool" approach: spawn new ones, tick all
	  alive ones each frame, remove dead ones. No object pooling needed
	  since GUI Frame creation is cheap.
	
	PERFORMANCE:
	  We cap the total number of particles and skip spawning for off-screen
	  ships to avoid creating thousands of Frames.
]]

local WakeEffect = {}

-- All active particles
local particles = {}

-- Config
local MAX_PARTICLES = 600           -- higher cap for dense, visible wake
local PARTICLE_LIFETIME = 1.2       -- seconds before fully faded (longer = longer trail)
local PARTICLE_SIZE_MIN = 4         -- min pixel size
local PARTICLE_SIZE_MAX = 9         -- max pixel size
local SPAWN_INTERVAL = 0.01         -- seconds between spawns per ship (very dense)
local SPEED_THRESHOLD = 8           -- lower threshold so particles appear sooner
local DRIFT_SPEED = 15              -- how fast particles drift outward

-- Track spawn timers per ship (to avoid spawning every frame)
local spawnTimers = {}

--[[
	Spawns wake particles for a ship if it's moving fast enough.
	
	@param shipId: unique identifier for the ship
	@param worldPos: Vector2 world position of the ship center
	@param rotation: number in radians (ship facing direction)
	@param speed: number (magnitude of ship velocity)
	@param canvas: Frame to parent particles to
	@param worldToCanvas: function to convert world→canvas UDim2
]]
function WakeEffect.emit(shipId, worldPos: Vector2, rotation: number, speed: number, canvas: Frame, worldToCanvas)
	-- Don't emit if ship is barely moving
	if speed < SPEED_THRESHOLD then
		spawnTimers[shipId] = 0
		return
	end
	
	-- Particle cap
	if #particles >= MAX_PARTICLES then return end
	
	-- Spawn timer per ship
	spawnTimers[shipId] = (spawnTimers[shipId] or 0)
	if spawnTimers[shipId] > 0 then return end
	
	-- Reset spawn timer
	spawnTimers[shipId] = SPAWN_INTERVAL
	
	-- Calculate stern position (back of the ship)
	-- The ship faces "up" at rotation=0, so the stern is in the +Y direction (opposite of bow)
	local sternOffsetX = math.sin(rotation) * -25  -- 25 units behind center
	local sternOffsetY = -math.cos(rotation) * -25
	local sternPos = worldPos + Vector2.new(sternOffsetX, sternOffsetY)
	
	-- Spawn multiple particles per tick for a dense, visible wake
	-- More particles at higher speeds
	local count = if speed > 200 then 5 elseif speed > 100 then 4 elseif speed > 40 then 3 else 2
	
	for _ = 1, count do
		if #particles >= MAX_PARTICLES then break end
		
		-- Random offset so particles fan out behind the ship
		local spreadX = (math.random() - 0.5) * 18
		local spreadY = (math.random() - 0.5) * 18
		local spawnPos = sternPos + Vector2.new(spreadX, spreadY)
		
		-- Random drift direction (mostly backward with spread)
		local driftAngle = rotation + math.pi + (math.random() - 0.5) * 1.4
		local driftDir = Vector2.new(math.sin(driftAngle), -math.cos(driftAngle))
		
		-- Create the particle Frame
		local size = math.random(PARTICLE_SIZE_MIN, PARTICLE_SIZE_MAX)
		local particle = Instance.new("Frame")
		particle.Name = "Wake"
		particle.Size = UDim2.new(0, size, 0, size)
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = worldToCanvas(spawnPos)
		-- Slightly vary the white color for natural look
		local brightness = math.random(220, 255)
		particle.BackgroundColor3 = Color3.fromRGB(brightness, brightness, 255)
		particle.BackgroundTransparency = 0.2 + math.random() * 0.2  -- 0.2 to 0.4 start
		particle.BorderSizePixel = 0
		particle.ZIndex = 2  -- Above water tiles, below ships
		particle.Parent = canvas
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = particle
		
		table.insert(particles, {
			frame = particle,
			worldPos = spawnPos,
			driftDir = driftDir,
			age = 0,
			lifetime = PARTICLE_LIFETIME + (math.random() - 0.5) * 0.4,
			startTransparency = particle.BackgroundTransparency,
			startSize = size,
			worldToCanvas = worldToCanvas,
		})
	end
end

--[[
	Updates all alive particles. Call every frame.
	
	Each particle:
	  - Ages by deltaTime
	  - Drifts in its random direction
	  - Fades from starting transparency to fully transparent
	  - Gets destroyed when lifetime expires
]]
function WakeEffect.update(deltaTime: number)
	-- Tick down per-ship spawn timers
	for shipId, timer in spawnTimers do
		spawnTimers[shipId] = timer - deltaTime
	end
	
	-- Update particles in reverse order (so we can remove without skipping)
	local i = #particles
	while i >= 1 do
		local p = particles[i]
		p.age = p.age + deltaTime
		
		if p.age >= p.lifetime then
			-- Particle expired — remove it
			p.frame:Destroy()
			table.remove(particles, i)
		else
			-- Fade from start transparency → 1.0 over lifetime
			local progress = p.age / p.lifetime  -- 0 to 1
			local startT = p.startTransparency or 0.3
			p.frame.BackgroundTransparency = startT + ((1 - startT) * progress)
			
			-- Shrink slightly as it fades
			local scale = 1 - (progress * 0.5)  -- 1.0 → 0.5
			local sz = (p.startSize or 6) * scale
			p.frame.Size = UDim2.new(0, sz, 0, sz)
			
			-- Drift outward
			p.worldPos = p.worldPos + (p.driftDir * DRIFT_SPEED * deltaTime)
			p.frame.Position = p.worldToCanvas(p.worldPos)
		end
		
		i = i - 1
	end
end

-- Clean up all particles (e.g., on round reset)
function WakeEffect.clear()
	for _, p in particles do
		p.frame:Destroy()
	end
	table.clear(particles)
	table.clear(spawnTimers)
end

return WakeEffect
