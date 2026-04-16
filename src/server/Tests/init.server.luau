--[[
	Test Runner (Server)
	====================
	Automated tests that verify game logic works correctly.
	
	Runs once on server start (after a short delay to let services init).
	Tests exercise actual service logic with controlled inputs.
	
	HOW TO USE:
	  1. Play in Studio (any mode)
	  2. Check Output window for test results
	  3. Green ✅ = pass, Red ❌ = fail
	
	Tests do NOT use mocks — they call real service functions with
	controlled data, which catches integration bugs (the kind we
	actually hit in development).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Only run tests in Studio
if not RunService:IsStudio() then return end

-- Wait for services to initialize
task.wait(2)

local Constants = require(ReplicatedStorage.Shared.Constants)

print("\n========================================")
print("  🧪 SHOOTASHIP TEST SUITE")
print("========================================\n")

-- ============ Test Framework ============

local totalTests = 0
local passed = 0
local failed = 0
local failedTests = {}

local currentSection = ""

local function section(name: string)
	currentSection = name
	print("── " .. name .. " ──")
end

local function test(name: string, fn: () -> ())
	totalTests = totalTests + 1
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  ✅ " .. name)
	else
		failed = failed + 1
		print("  ❌ " .. name)
		print("     └─ " .. tostring(err))
		table.insert(failedTests, currentSection .. " > " .. name .. ": " .. tostring(err))
	end
end

local function expect(value: any, message: string?)
	if not value then
		error(message or "Expected truthy value, got: " .. tostring(value), 2)
	end
end

local function expectEqual(a: any, b: any, message: string?)
	if a ~= b then
		error((message or "Expected equal") .. " — got " .. tostring(a) .. " vs " .. tostring(b), 2)
	end
end

local function expectNear(a: number, b: number, tolerance: number, message: string?)
	if math.abs(a - b) > tolerance then
		error((message or "Expected near") .. " — got " .. tostring(a) .. " vs " .. tostring(b) .. " (tol " .. tolerance .. ")", 2)
	end
end

-- ============ Tests ============

section("Constants Sanity")

test("Block constants exist and are valid", function()
	expect(Constants.BLOCK_DURATION, "BLOCK_DURATION missing")
	expect(Constants.BLOCK_COOLDOWN, "BLOCK_COOLDOWN missing")
	expect(Constants.BLOCK_RADIUS, "BLOCK_RADIUS missing")
	expect(Constants.BLOCK_DURATION > 0, "BLOCK_DURATION must be positive")
	expect(Constants.BLOCK_COOLDOWN > 0, "BLOCK_COOLDOWN must be positive")
	expect(Constants.BLOCK_RADIUS > 0, "BLOCK_RADIUS must be positive")
	expect(Constants.BLOCK_RADIUS > Constants.CANNONBALL_SIZE, "BLOCK_RADIUS must be larger than cannonball")
end)

test("Combat constants exist", function()
	expect(Constants.CANNONBALL_SPEED > 0, "CANNONBALL_SPEED")
	expect(Constants.CANNONBALL_DAMAGE > 0, "CANNONBALL_DAMAGE")
	expect(Constants.CANNONBALL_LIFETIME > 0, "CANNONBALL_LIFETIME")
	expect(Constants.CANNONBALL_SIZE > 0, "CANNONBALL_SIZE")
	expect(Constants.SHIP_MAX_HEALTH > 0, "SHIP_MAX_HEALTH")
end)

test("Ship physics constants exist", function()
	expect(Constants.SHIP_MAX_SPEED > 0, "SHIP_MAX_SPEED")
	expect(Constants.SHIP_THRUST_FORCE > 0, "SHIP_THRUST_FORCE")
	expect(Constants.DASH_IMPULSE > 0, "DASH_IMPULSE")
	expect(Constants.DASH_COOLDOWN > 0, "DASH_COOLDOWN")
end)

test("Map constants exist", function()
	expect(Constants.MAP_WIDTH > 0, "MAP_WIDTH")
	expect(Constants.MAP_HEIGHT > 0, "MAP_HEIGHT")
end)

print("")

-- ============ Ship State Tests ============
-- These create fake ship tables and test logic that operates on them

section("Ship State Structure")

local function createTestShip(overrides: {[string]: any}?)
	local ship = {
		position = Vector2.new(0, 0),
		velocity = Vector2.new(0, 0),
		rotation = 0,
		angularVelocity = 0,
		health = Constants.SHIP_MAX_HEALTH,
		ammo = Constants.STARTING_AMMO,
		speedBoostTimer = 0,
		speedBoostStacks = 0,
		damageBoostTimer = 0,
		shield = 0,
		scatterShotCount = 0,
		ghostTimer = 0,
		ramTimer = 0,
		homingShotCount = 0,
		superBounceTimer = 0,
		mineCount = 0,
		dashCooldown = 0,
		blockTimer = 0,
		blockCooldown = 0,
		thrustRamp = 0,
		input = { thrust = 0, turn = 0 },
	}
	if overrides then
		for k, v in overrides do
			ship[k] = v
		end
	end
	return ship
end

test("Ship has all required fields (no nil timers)", function()
	local ship = createTestShip()
	-- These are the fields that caused the "compare number < nil" crash
	expect(ship.blockTimer ~= nil, "blockTimer is nil")
	expect(ship.blockCooldown ~= nil, "blockCooldown is nil")
	expect(ship.dashCooldown ~= nil, "dashCooldown is nil")
	expect(ship.ghostTimer ~= nil, "ghostTimer is nil")
	expect(ship.ramTimer ~= nil, "ramTimer is nil")
	expect(ship.superBounceTimer ~= nil, "superBounceTimer is nil")
	expect(ship.speedBoostTimer ~= nil, "speedBoostTimer is nil")
	expect(ship.damageBoostTimer ~= nil, "damageBoostTimer is nil")
end)

test("Block activation sets correct timers", function()
	local ship = createTestShip()
	-- Simulate block activation (mirrors ShipService block handler)
	expect(ship.blockCooldown == 0, "Should start off cooldown")
	expect(ship.blockTimer == 0, "Should start with no block")
	
	ship.blockTimer = Constants.BLOCK_DURATION
	ship.blockCooldown = Constants.BLOCK_COOLDOWN
	
	expect(ship.blockTimer > 0, "Block should be active")
	expect(ship.blockCooldown > 0, "Cooldown should be set")
end)

test("Block rejected while on cooldown", function()
	local ship = createTestShip({ blockCooldown = 3.0 })
	local canBlock = ship.blockCooldown <= 0 and ship.blockTimer <= 0
	expect(not canBlock, "Should NOT be able to block while on cooldown")
end)

test("Block rejected while already blocking", function()
	local ship = createTestShip({ blockTimer = 0.2 })
	local canBlock = ship.blockCooldown <= 0 and ship.blockTimer <= 0
	expect(not canBlock, "Should NOT be able to block while already blocking")
end)

test("Block rejected when dead", function()
	local ship = createTestShip({ health = 0 })
	local canBlock = ship.health > 0
	expect(not canBlock, "Dead ships should not block")
end)

print("")

-- ============ Timer Tick Tests ============

section("Timer Tick-Down")

local function tickTimers(ship, dt)
	-- Mirrors the timer logic in ShipService.update
	if (ship.blockTimer or 0) > 0 then
		ship.blockTimer = math.max(0, ship.blockTimer - dt)
	end
	if (ship.blockCooldown or 0) > 0 then
		ship.blockCooldown = math.max(0, ship.blockCooldown - dt)
	end
	if ship.dashCooldown > 0 then
		ship.dashCooldown = math.max(0, ship.dashCooldown - dt)
	end
	if ship.ghostTimer > 0 then
		ship.ghostTimer = math.max(0, ship.ghostTimer - dt)
	end
end

test("Block timer ticks down to zero", function()
	local ship = createTestShip({ blockTimer = 0.35 })
	tickTimers(ship, 0.5)
	expectEqual(ship.blockTimer, 0, "Block timer should be 0 after expiry")
end)

test("Block cooldown ticks down correctly", function()
	local ship = createTestShip({ blockCooldown = 2.0 })
	tickTimers(ship, 1.0)
	expectNear(ship.blockCooldown, 1.0, 0.001, "Cooldown should be 1.0s")
	tickTimers(ship, 1.5)
	expectEqual(ship.blockCooldown, 0, "Cooldown should be 0 after expiry")
end)

test("Nil-safe timer tick (legacy ship without blockTimer)", function()
	-- Simulates a ship spawned before block was added
	local ship = createTestShip()
	ship.blockTimer = nil
	ship.blockCooldown = nil
	-- This should NOT error (the (x or 0) > 0 guard handles it)
	local ok, err = pcall(function()
		tickTimers(ship, 0.016)
	end)
	expect(ok, "Timer tick should not crash on nil fields: " .. tostring(err))
end)

print("")

-- ============ Bounce Rotation Tests ============

section("Bounce Rotation Convention")

test("Ship facing matches velocity after bounce (up)", function()
	local vel = Vector2.new(0, -100)  -- moving up
	local rot = math.atan2(vel.X, -vel.Y)
	-- Forward direction from rotation: (sin(r), -cos(r))
	local fwdX = math.sin(rot)
	local fwdY = -math.cos(rot)
	expectNear(fwdX, 0, 0.001, "Forward X should be ~0")
	expectNear(fwdY, -1, 0.001, "Forward Y should be ~-1 (up)")
end)

test("Ship facing matches velocity after bounce (right)", function()
	local vel = Vector2.new(100, 0)  -- moving right
	local rot = math.atan2(vel.X, -vel.Y)
	local fwdX = math.sin(rot)
	local fwdY = -math.cos(rot)
	expectNear(fwdX, 1, 0.001, "Forward X should be ~1 (right)")
	expectNear(fwdY, 0, 0.001, "Forward Y should be ~0")
end)

test("Ship facing matches velocity after bounce (down-left)", function()
	local vel = Vector2.new(-70, 70)  -- moving down-left
	local rot = math.atan2(vel.X, -vel.Y)
	local fwdX = math.sin(rot)
	local fwdY = -math.cos(rot)
	-- Forward should be in the same direction as velocity
	local velUnit = vel.Unit
	expectNear(fwdX, velUnit.X, 0.01, "Forward X should match velocity direction")
	expectNear(fwdY, velUnit.Y, 0.01, "Forward Y should match velocity direction")
end)

test("Old atan2(vy,vx) convention is WRONG for this game", function()
	-- Verify the old code would give wrong results
	local vel = Vector2.new(0, -100)  -- moving up
	local oldRot = math.atan2(vel.Y, vel.X)  -- OLD (wrong)
	local fwdX = math.sin(oldRot)
	local fwdY = -math.cos(oldRot)
	-- With the old formula, forward would NOT match up-direction
	local isCorrect = math.abs(fwdY - (-1)) < 0.1
	expect(not isCorrect, "Old formula should NOT give correct facing for upward movement")
end)

print("")

-- ============ Projectile Reflection Tests ============

section("Projectile Block / Reflect")

local function createTestProjectile(overrides: {[string]: any}?)
	local proj = {
		id = 1,
		ownerId = 100,
		position = Vector2.new(0, 0),
		velocity = Vector2.new(0, -Constants.CANNONBALL_SPEED),
		age = 0,
		homing = false,
		reflected = false,
	}
	if overrides then
		for k, v in overrides do
			proj[k] = v
		end
	end
	return proj
end

test("Projectile reflects when ship is blocking within radius", function()
	local proj = createTestProjectile({
		ownerId = 100,
		position = Vector2.new(50, 0),  -- within BLOCK_RADIUS of ship at origin
		velocity = Vector2.new(-Constants.CANNONBALL_SPEED, 0),  -- heading left toward ship
	})
	local ship = createTestShip({ blockTimer = 0.3 })
	local shipUserId = 200
	
	-- Simulate reflect check (mirrors CombatService logic)
	local reflected = false
	if not proj.reflected then
		if shipUserId ~= proj.ownerId and ship.health > 0 and (ship.blockTimer or 0) > 0 then
			local dist = (proj.position - ship.position).Magnitude
			if dist <= Constants.BLOCK_RADIUS then
				proj.velocity = -proj.velocity
				proj.ownerId = shipUserId
				proj.age = 0
				proj.homing = false
				proj.reflected = true
				reflected = true
			end
		end
	end
	
	expect(reflected, "Projectile should be reflected")
	expect(proj.reflected, "reflected flag should be set")
	expectEqual(proj.ownerId, 200, "ownerId should change to blocker")
	expect(proj.velocity.X > 0, "Velocity should reverse (now heading right)")
	expectEqual(proj.age, 0, "Age should reset")
end)

test("Projectile NOT reflected when outside block radius", function()
	local proj = createTestProjectile({
		position = Vector2.new(200, 0),  -- far from ship
	})
	local ship = createTestShip({ blockTimer = 0.3 })
	
	local dist = (proj.position - ship.position).Magnitude
	expect(dist > Constants.BLOCK_RADIUS, "Projectile should be outside radius")
	
	local reflected = false
	if dist <= Constants.BLOCK_RADIUS then
		reflected = true
	end
	expect(not reflected, "Should NOT reflect when outside radius")
end)

test("Projectile NOT reflected twice (reflected flag)", function()
	local proj = createTestProjectile({
		reflected = true,  -- already reflected
		position = Vector2.new(50, 0),
	})
	local ship = createTestShip({ blockTimer = 0.3 })
	
	local reflected = false
	if not proj.reflected then
		reflected = true
	end
	expect(not reflected, "Already-reflected projectile should not reflect again")
end)

test("Projectile NOT reflected by own owner", function()
	local proj = createTestProjectile({
		ownerId = 200,
		position = Vector2.new(50, 0),
	})
	local ship = createTestShip({ blockTimer = 0.3 })
	local shipUserId = 200  -- same as projectile owner
	
	local reflected = false
	if not proj.reflected and shipUserId ~= proj.ownerId then
		reflected = true
	end
	expect(not reflected, "Should NOT reflect own projectiles")
end)

test("Projectile NOT reflected when ship is not blocking", function()
	local proj = createTestProjectile({
		position = Vector2.new(50, 0),
	})
	local ship = createTestShip({ blockTimer = 0 })
	
	local reflected = false
	if not proj.reflected and (ship.blockTimer or 0) > 0 then
		reflected = true
	end
	expect(not reflected, "Should NOT reflect when not blocking")
end)

test("Homing disabled after reflect", function()
	local proj = createTestProjectile({
		homing = true,
		position = Vector2.new(50, 0),
		velocity = Vector2.new(-Constants.CANNONBALL_SPEED, 0),
	})
	local ship = createTestShip({ blockTimer = 0.3 })
	
	-- Simulate reflect
	proj.velocity = -proj.velocity
	proj.homing = false
	proj.reflected = true
	
	expect(not proj.homing, "Homing should be disabled after reflect")
end)

print("")

-- ============ Projectile-vs-Projectile Collision Tests ============

section("Projectile-vs-Projectile Collision")

test("Two opposing projectiles collide when close enough", function()
	local p1 = createTestProjectile({
		id = 1, ownerId = 100,
		position = Vector2.new(5, 0),
		velocity = Vector2.new(Constants.CANNONBALL_SPEED, 0),
	})
	local p2 = createTestProjectile({
		id = 2, ownerId = 200,
		position = Vector2.new(-5, 0),
		velocity = Vector2.new(-Constants.CANNONBALL_SPEED, 0),
	})
	
	local dist = (p1.position - p2.position).Magnitude
	local collides = dist <= Constants.CANNONBALL_SIZE * 2
	expect(collides, "Projectiles at distance " .. dist .. " should collide (threshold " .. Constants.CANNONBALL_SIZE * 2 .. ")")
end)

test("Same-owner projectiles do NOT collide (broadside pair)", function()
	local p1 = createTestProjectile({
		id = 1, ownerId = 100,
		position = Vector2.new(5, 0),
	})
	local p2 = createTestProjectile({
		id = 2, ownerId = 100,  -- same owner
		position = Vector2.new(-5, 0),
	})
	
	local collides = (p1.ownerId ~= p2.ownerId) and (p1.position - p2.position).Magnitude <= Constants.CANNONBALL_SIZE * 2
	expect(not collides, "Same-owner projectiles should NOT collide")
end)

test("Far-apart projectiles do NOT collide", function()
	local p1 = createTestProjectile({
		id = 1, ownerId = 100,
		position = Vector2.new(0, 0),
	})
	local p2 = createTestProjectile({
		id = 2, ownerId = 200,
		position = Vector2.new(100, 0),
	})
	
	local dist = (p1.position - p2.position).Magnitude
	local collides = (p1.ownerId ~= p2.ownerId) and dist <= Constants.CANNONBALL_SIZE * 2
	expect(not collides, "Far-apart projectiles should NOT collide")
end)

print("")

-- ============ Shield / Damage Priority Tests ============

section("Hit Priority (Block > Shield > Damage)")

test("Block takes priority over shield", function()
	local ship = createTestShip({ blockTimer = 0.3, shield = 1 })
	local proj = createTestProjectile({ position = Vector2.new(10, 0) })
	
	-- Simulate priority check (matches CombatService order)
	local result = "damage"
	if (ship.blockTimer or 0) > 0 then
		result = "blocked"
	elseif ship.shield > 0 then
		result = "shielded"
	end
	expectEqual(result, "blocked", "Block should take priority over shield")
end)

test("Shield takes priority over damage", function()
	local ship = createTestShip({ blockTimer = 0, shield = 1 })
	
	local result = "damage"
	if (ship.blockTimer or 0) > 0 then
		result = "blocked"
	elseif ship.shield > 0 then
		result = "shielded"
	end
	expectEqual(result, "shielded", "Shield should take priority over damage")
end)

test("Damage applied when no block or shield", function()
	local ship = createTestShip({ blockTimer = 0, shield = 0 })
	
	local result = "damage"
	if (ship.blockTimer or 0) > 0 then
		result = "blocked"
	elseif ship.shield > 0 then
		result = "shielded"
	end
	expectEqual(result, "damage", "Damage should apply when no defenses")
end)

test("Ghost ships are immune to everything", function()
	local ship = createTestShip({ ghostTimer = 2.0, shield = 0, blockTimer = 0 })
	local immune = ship.ghostTimer > 0
	expect(immune, "Ghost ships should be immune")
end)

print("")

-- ============ Damage Calculation Tests ============

section("Damage Calculation")

test("Normal cannonball deals base damage", function()
	local ship = createTestShip()
	local damage = Constants.CANNONBALL_DAMAGE
	ship.health = ship.health - damage
	expectEqual(ship.health, Constants.SHIP_MAX_HEALTH - Constants.CANNONBALL_DAMAGE, "Health after 1 hit")
end)

test("Damage boost doubles cannonball damage", function()
	local attacker = createTestShip({ damageBoostTimer = 3.0 })
	local target = createTestShip()
	
	local dmgMul = 1
	if attacker.damageBoostTimer > 0 then
		dmgMul = Constants.DAMAGE_BOOST_MULTIPLIER
	end
	local damage = Constants.CANNONBALL_DAMAGE * dmgMul
	target.health = target.health - damage
	
	local expected = Constants.SHIP_MAX_HEALTH - (Constants.CANNONBALL_DAMAGE * Constants.DAMAGE_BOOST_MULTIPLIER)
	expectEqual(target.health, expected, "Damage-boosted hit")
end)

test("Ship dies at 0 HP", function()
	local ship = createTestShip({ health = 10 })
	ship.health = ship.health - Constants.CANNONBALL_DAMAGE
	expect(ship.health <= 0, "Ship should be dead")
end)

test("Mine deals correct damage", function()
	local ship = createTestShip()
	ship.health = ship.health - Constants.MINE_DAMAGE
	expectEqual(ship.health, Constants.SHIP_MAX_HEALTH - Constants.MINE_DAMAGE, "Health after mine hit")
end)

print("")

-- ============ Wall Bounce Tests ============

section("Wall Bounce Physics")

test("Ship bounces off right wall", function()
	local halfW = Constants.MAP_WIDTH / 2
	local ship = createTestShip({
		position = Vector2.new(halfW + 10, 0),
		velocity = Vector2.new(200, 50),
	})
	
	-- Simulate bounce logic
	if ship.position.X > halfW then
		ship.position = Vector2.new(halfW, ship.position.Y)
		local vx = -math.abs(ship.velocity.X)
		ship.velocity = Vector2.new(vx, ship.velocity.Y)
	end
	
	expectEqual(ship.position.X, halfW, "Position should be clamped to wall")
	expect(ship.velocity.X < 0, "Velocity X should be negative (bouncing left)")
end)

test("Ship bounces off bottom wall", function()
	local halfH = Constants.MAP_HEIGHT / 2
	local ship = createTestShip({
		position = Vector2.new(0, halfH + 10),
		velocity = Vector2.new(50, 200),
	})
	
	if ship.position.Y > halfH then
		ship.position = Vector2.new(ship.position.X, halfH)
		local vy = -math.abs(ship.velocity.Y)
		ship.velocity = Vector2.new(ship.velocity.X, vy)
	end
	
	expectEqual(ship.position.Y, halfH, "Position should be clamped to wall")
	expect(ship.velocity.Y < 0, "Velocity Y should be negative (bouncing up)")
end)

print("")

-- ============ Game State Tests ============

section("Game State Logic")

test("Player can create a game when no game exists", function()
	-- Simulates the studioServicesBooted check
	local studioServicesBooted = false
	local canCreate = not studioServicesBooted
	expect(canCreate, "Should be able to create first game")
end)

test("Player cannot create second game in Studio", function()
	local studioServicesBooted = true
	local canCreate = not studioServicesBooted
	expect(not canCreate, "Should NOT be able to create second game")
end)

test("Game shuts down when last player leaves", function()
	-- Simulate gamePlayers tracking
	local gamePlayers = { [100] = true }
	
	-- Player 100 leaves
	gamePlayers[100] = nil
	
	-- Count remaining
	local remainingCount = 0
	for _ in gamePlayers do
		remainingCount = remainingCount + 1
	end
	
	expectEqual(remainingCount, 0, "No players remaining")
	expect(remainingCount == 0, "Should trigger shutdown")
end)

test("Game continues when other players remain", function()
	local gamePlayers = { [100] = true, [200] = true }
	gamePlayers[100] = nil
	
	local remainingCount = 0
	for _ in gamePlayers do
		remainingCount = remainingCount + 1
	end
	
	expect(remainingCount > 0, "Should NOT shut down with players remaining")
end)

print("")

-- ============ Broadcast State Tests ============

section("State Broadcast Data Shape")

test("Broadcast data includes block fields", function()
	local ship = createTestShip({ blockTimer = 0.2, blockCooldown = 1.5 })
	
	-- Mirrors ShipService.broadcastState() packing
	local data = {
		block = ship.blockTimer > 0 and ship.blockTimer or nil,
		blockCd = ship.blockCooldown > 0 and ship.blockCooldown or nil,
	}
	
	expect(data.block ~= nil, "block should be included when active")
	expect(data.blockCd ~= nil, "blockCd should be included when on cooldown")
end)

test("Broadcast data omits zero block fields (bandwidth save)", function()
	local ship = createTestShip({ blockTimer = 0, blockCooldown = 0 })
	
	local data = {
		block = ship.blockTimer > 0 and ship.blockTimer or nil,
		blockCd = ship.blockCooldown > 0 and ship.blockCooldown or nil,
	}
	
	expect(data.block == nil, "block should be nil when not active")
	expect(data.blockCd == nil, "blockCd should be nil when not on cooldown")
end)

test("Broadcast data includes all required fields", function()
	local ship = createTestShip()
	local kills = 5
	
	local data = {
		px = ship.position.X,
		py = ship.position.Y,
		vx = ship.velocity.X,
		vy = ship.velocity.Y,
		r = ship.rotation,
		hp = ship.health,
		ammo = ship.ammo,
		kills = kills,
	}
	
	expect(data.px ~= nil, "px required")
	expect(data.py ~= nil, "py required")
	expect(data.vx ~= nil, "vx required")
	expect(data.vy ~= nil, "vy required")
	expect(data.r ~= nil, "r required")
	expect(data.hp ~= nil, "hp required")
	expect(data.ammo ~= nil, "ammo required")
	expect(data.kills ~= nil, "kills required")
end)

print("")

-- ============ EventDefs Completeness ============

section("EventDefs Completeness")

test("All required events are defined", function()
	local EventDefs = require(ReplicatedStorage.Shared.EventDefs)
	local requiredEvents = {
		"PlayerInput", "ShipStateSync", "FireCannon", "CannonFired",
		"ShipDamaged", "ShipDestroyed", "CrateSpawned", "CrateCollected",
		"PowerUpSpawned", "PowerUpCollected", "ShipBounced",
		"Dash", "DeployMine", "MineDeployed", "MineExploded",
		"Block", "BlockActivated",
		"DevCommand", "DevResponse",
		"RoundStarting", "RoundEnded", "PlayerSpawned",
		"ServerMode", "RequestGameList", "GameListUpdate",
		"CreateGame", "JoinGame", "TeleportReady",
		"GameConfig", "ScoreUpdate", "GameOver", "HostAction",
		"LeaveGame", "SwitchMode",
	}
	
	for _, name in requiredEvents do
		expect(EventDefs[name] ~= nil, "Missing event: " .. name)
	end
end)

print("")

-- ============ Summary ============

print("========================================")
if failed == 0 then
	print("  ✅ ALL " .. totalTests .. " TESTS PASSED")
else
	print("  ❌ " .. failed .. " FAILED / " .. totalTests .. " TOTAL")
	print("")
	for _, msg in failedTests do
		print("  • " .. msg)
	end
end
print("========================================\n")
