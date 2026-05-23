--[[
	Shared Constants
	================
	Values used by BOTH client and server.
	
	This file lives in ReplicatedStorage, which means both the server
	and every client can require() it. This avoids magic numbers and
	keeps client/server in sync.
	
	Think of it like a shared config/env file in web dev.
]]

local Constants = {
	-- ===================
	-- 2D WORLD COORDINATES
	-- ===================
	-- The game world uses abstract 2D units (not pixels, not studs).
	-- The server simulates physics in world-space using Vector2.
	-- The client maps world-space onto GUI pixel positions.
	-- Think of it like CSS: you design in relative units, the browser renders pixels.

	-- Ship physics (all in world-space units per second)
	SHIP_MAX_SPEED = 600,        -- max world-units per second
	SHIP_THRUST_FORCE = 300,     -- acceleration when pressing W
	SHIP_TURN_SPEED = 8,        -- angular acceleration (radians/sec²) — very responsive
	SHIP_MAX_TURN_SPEED = 4.5,   -- max angular velocity (radians/sec)
	SHIP_DRAG = 1.0,             -- linear drag (lower = more coast after releasing W)
	                             -- At 1.0: velocity halves every ~0.7s — noticeable glide
	SHIP_ANGULAR_DRAG = 0.5,     -- rotational drag (lower = spin continues longer after A/D)
	                             -- At 1.5: spin halves every ~0.46s — visible carry-through
	SHIP_SIZE = Vector2.new(40, 60), -- width x height in world units

	-- Dash (press Q for a burst of speed)
	DASH_IMPULSE = 450,            -- velocity burst added in facing direction
	DASH_COOLDOWN = 3,             -- seconds between dashes

	-- Speed-dependent turning (faster = wider turns)
	SPEED_TURN_REDUCTION = 0.5,    -- at max speed, turn rate reduced by this fraction

	-- Acceleration curve (thrust ramps up gradually)
	THRUST_RAMP_SPEED = 2.5,       -- how fast thrust ramps from 0→1 (seconds⁻¹, ~0.4s to full)
	THRUST_RAMP_DECAY = 5.0,       -- how fast ramp decays when not thrusting (snappy release)
	THRUST_RAMP_MIN = 0.15,        -- minimum thrust fraction (so you're never at 0 when pressing W)

	-- Speed visual effects
	SPEED_LINE_THRESHOLD = 0.6,    -- speed fraction (of max) where speed lines start appearing
	CAMERA_LEAD_AMOUNT = 80,       -- max pixels the camera shifts ahead of the ship at full speed
	CAMERA_LEAD_SPEED = 4,         -- how fast camera lead interpolates

	-- Combat
	CANNONBALL_SPEED = 600,      -- world-units per second
	CANNONBALL_DAMAGE = 25,      -- HP per hit
	CANNONBALL_LIFETIME = 2,     -- seconds before despawning
	CANNONBALL_SIZE = 8,         -- radius in world units
	SHIP_MAX_HEALTH = 100,       -- starting HP
	CANNON_SIDE_OFFSET = 22,     -- how far left/right cannons are from ship center
	STARTING_AMMO = 0,           -- ships spawn with no ammo (must collect crates)
	AMMO_PER_CRATE = 3,          -- shots gained per crate pickup
	MAX_AMMO = 12,               -- max ammo a ship can hold

	-- Power-ups (general)
	POWERUP_SPAWN_INTERVAL = 6,    -- seconds between power-up crate spawns
	MAX_POWERUPS = 10,             -- max power-up crates on map at once

	-- Green: Speed Boost (stackable — collecting more adds duration)
	SPEED_BOOST_MULTIPLIER = 1.5,  -- base speed multiplier per stack
	SPEED_BOOST_DURATION = 4,      -- seconds added per pickup
	SPEED_BOOST_MAX_STACKS = 5,    -- max stacks (caps multiplier)

	-- Red: Damage Boost
	DAMAGE_BOOST_MULTIPLIER = 2.0, -- cannonball damage multiplier
	DAMAGE_BOOST_DURATION = 10,    -- seconds the buff lasts

	-- Blue: Shield
	SHIELD_HITS = 1,               -- number of hits the shield absorbs

	-- Purple: Scatter Shot
	SCATTER_SHOT_VOLLEYS = 3,      -- how many scatter volleys you get
	SCATTER_SHOT_COUNT = 4,        -- cannonballs per scatter volley (spread)
	SCATTER_SHOT_SPREAD = 0.8,     -- total spread angle in radians (~45°)

	-- Yellow: Repair
	REPAIR_AMOUNT = 25,            -- HP restored per crate (25% of max HP)

	-- Cyan: Ghost Mode
	GHOST_DURATION = 2,            -- seconds of invulnerability (can't fire)

	-- Orange: Ram
	RAM_DURATION = 5,              -- seconds the ram buff lasts
	RAM_DAMAGE = 40,               -- damage dealt on ship-to-ship collision
	RAM_RADIUS = 35,               -- collision distance for ram hits

	-- White: Ammo Dump
	AMMO_DUMP_AMOUNT = 12,         -- ammo given (fills to max)

	-- Pink: Homing Shot
	HOMING_SHOT_COUNT = 1,         -- homing cannonballs granted
	HOMING_TURN_SPEED = 2.0,       -- how fast homing balls curve (rad/s)

	-- Map (the 2D play area)
	MAP_WIDTH = 3000,            -- world units wide
	MAP_HEIGHT = 3000,           -- world units tall

	-- Wall bounce
	BOUNCE_SPEED_MULTIPLIER = 1.5,  -- speed multiplied on wall bounce
	BOUNCE_MIN_SPEED = 200,         -- minimum speed after bounce (so slow bumps still feel punchy)

	-- Lime: Super Bounce
	SUPERBOUNCE_MULTIPLIER = 8.0,   -- bounce multiplier (walls AND ships)
	SUPERBOUNCE_DURATION = 8,       -- seconds the buff lasts
	SUPERBOUNCE_MIN_SPEED = 500,    -- minimum speed after bounce with super bounce active

	-- Block / Shockwave (press F to reflect nearby cannonballs)
	BLOCK_DURATION = 0.35,           -- seconds the shockwave is active
	BLOCK_COOLDOWN = 2,              -- seconds between blocks
	BLOCK_RADIUS = 80,               -- world units — cannonballs within this range get reflected

	-- Dark Red: Naval Mine
	MINE_COUNT = 3,                 -- mines given per pickup
	MINE_DAMAGE = 50,               -- damage on explosion
	MINE_RADIUS = 60,               -- trigger radius (world units)
	MINE_LIFETIME = 30,             -- seconds before mine despawns
	MINE_ARM_DELAY = 1.0,           -- seconds before mine can hurt the dropper
	MINE_DROP_OFFSET = 50,          -- how far behind the ship the mine spawns
	MINE_SIZE = 20,                 -- visual size in world units

	-- Steel Blue: Machinegun
	MACHINEGUN_DURATION = 6,        -- seconds the machinegun is active
	MACHINEGUN_FIRE_RATE = 0.15,    -- seconds between auto-fire shots
	MACHINEGUN_DAMAGE = 10,         -- damage per bullet (less than cannonball)
	MACHINEGUN_SPEED = 900,         -- bullet speed (faster than cannonballs)
	MACHINEGUN_LIFETIME = 1.2,      -- seconds before bullet despawns
	MACHINEGUN_SIZE = 4,            -- bullet radius (smaller than cannonball)

	-- Viewport (what the player sees on screen)
	VIEWPORT_SCALE = 1,          -- 1 world unit = 1 pixel at default zoom

	-- Crates
	CRATE_SPAWN_INTERVAL = 8,    -- seconds between crate spawns
	CRATE_SIZE = 30,             -- width/height in world units
	MAX_CRATES = 8,              -- max crates on map at once
	CRATE_PICKUP_RADIUS = 40,    -- how close a ship must be to collect

	-- Networking
	SYNC_RATE = 1 / 20,          -- server sends position updates 20 times per second

	-- ========================
	-- LOBBY / MATCHMAKING
	-- ========================
	MAX_PLAYERS_PER_GAME = 10,         -- max players in a public game
	DEFAULT_KILL_TARGET = 10,          -- default kills to win deathmatch
	MIN_PLAYERS_TO_START = 1,          -- min players before game auto-starts (1 for testing)
	GAME_LIST_REFRESH = 3,             -- seconds between game list polls on hub
	GAME_ENTRY_TTL = 30,               -- MemoryStore entry lifetime (refreshed by game server)
	GAME_ENTRY_REFRESH = 10,           -- how often game server refreshes its MemoryStore entry

	-- ========================
	-- DEATHMATCH
	-- ========================
	WIN_ANNOUNCEMENT_DURATION = 5,     -- seconds to show "X WINS!" screen
	RESTART_COUNTDOWN = 5,             -- seconds before game auto-restarts after win

	-- ========================
	-- ADMIN
	-- ========================
	ADMIN_NAME = "Synt4xify",          -- admin username for sandbox access

	-- ========================
	-- RACE MODE
	-- ========================
	RACE_START_Y = 1000,             -- ships line up on this row (south side)
	RACE_FINISH_Y = -1300,           -- (informational) target finish row
	RACE_SPACING = 140,              -- horizontal spacing between starting ships
	RACE_KILL_BEHIND = 900,          -- world units behind leader before elimination
	RACE_COUNTDOWN_INTERVAL = 1.0,   -- seconds per countdown step (3/2/1/GO)
	RACE_BOT_COUNT = 4,              -- bots added for race testing
	RACE_FINISH_DELAY = 6,           -- seconds before race resets after winner
	RACE_ROCK_COUNT = 14,            -- number of static rock obstacles
	RACE_ROCK_RADIUS = 55,           -- rock collision radius
	RACE_ROCK_DAMAGE = 35,           -- damage dealt by rock collisions
	RACE_ROCK_KNOCKBACK = 350,       -- velocity knockback on rock hit
	RACE_KILLLINE_VISIBLE = true,    -- show kill-line on client
}

return Constants
