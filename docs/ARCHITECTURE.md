# Architecture

## Design Principles

- **Server-authoritative**: The server owns ALL game state (positions, health, ammo). Clients only send input and render what the server tells them. This prevents cheating.
- **Service/Controller pattern**: Server logic lives in Services, client logic in Controllers. Both are plain Luau modules with `init()` and `update()` methods.
- **Shared config**: Constants and event definitions live in `src/shared/` (maps to ReplicatedStorage) so both sides stay in sync.

## Boot Sequence

### Server (`src/server/init.server.luau`)
```
1. EventManager.createEvents()       → Creates "Events" folder + all RemoteEvents
2. ShipService.init()                → Listens for player join/leave/input
3. CombatService.init()              → Listens for fire requests
4. CrateService.init()               → Spawns initial crates
5. GameService.init()                → (stub)
6. RunService.Heartbeat → loop       → Calls .update(dt) on all services every frame
```

### Client (`src/client/init.client.luau`)
```
1. WaitForChild("Events", 15)        → Waits for server to create events folder
2. InputController.init()            → Starts keyboard capture
3. ViewportController.init()         → Creates ScreenGui + GameCanvas
4. ShipController.init()             → Listens for ship state sync
5. ProjectileController.init()       → Listens for cannon fire events
6. CrateController.init()            → Listens for crate spawn/collect
7. AmmoHUD.init()                    → Creates ammo + boost HUD overlay
8. RunService.RenderStepped → loop   → Calls .update(dt) on render controllers
```

## Server Services

### ShipService
**Responsibility**: Owns all ship state, simulates 2D physics, broadcasts positions.

**Ship State** (per player):
| Field | Type | Description |
|-------|------|-------------|
| position | Vector2 | World-space center position |
| velocity | Vector2 | Movement per second |
| rotation | number | Radians, 0 = up, clockwise positive |
| angularVelocity | number | Spin momentum (rad/sec) |
| health | number | Current HP (0 = dead) |
| ammo | number | Current cannonball ammo |
| speedBoostTimer | number | Seconds remaining on speed boost |
| input | table | Latest client input {thrust, turn} |

**Physics Loop** (each frame):
1. Tick down speed boost timer
2. Apply turn input as angular acceleration → clamp → angular drag → update rotation
3. Apply thrust in facing direction (× boost multiplier if boosted)
4. Apply exponential drag to velocity
5. Clamp speed to max (× boost multiplier)
6. Move position by velocity × dt
7. Clamp to map bounds

**Network Sync**: Broadcasts all ship states to all clients 20×/sec (every 50ms).

**Respawn**: When health hits 0, ship is zeroed out. After 3 seconds, a new ship spawns at a random position.

### CombatService
**Responsibility**: Cannon firing, projectile movement, hit detection, damage.

**Projectile State** (per active projectile):
| Field | Type | Description |
|-------|------|-------------|
| id | number | Unique ID (auto-increment) |
| ownerId | number | UserId of the shooter |
| position | Vector2 | Current world position |
| velocity | Vector2 | Direction × speed |
| age | number | Seconds alive |

**Fire Logic**:
- Validates: ship exists, alive, has ammo (≥1)
- No cooldown — fires as fast as you press
- Spawns 2 projectiles (left + right broadside)
- Each flies perpendicular to ship facing + 30% of ship velocity
- Costs 1 ammo per volley

**Hit Detection** (each frame):
- Circle-vs-circle collision: ship radius (20) + cannonball radius (8) = 28 unit hit distance
- Can't hit yourself
- On hit: 25 damage, ShipDamaged event
- On kill: ShipDestroyed event, triggers respawn

**Cleanup**: Projectiles removed when age > 2s or out of map bounds.

### CrateService
**Responsibility**: Spawns and manages two types of pickup crates.

| Crate Type | Color | Spawn Rate | Max on Map | Effect |
|-----------|-------|------------|------------|--------|
| Ammo | Brown | Every 8s | 8 | +3 ammo (cap 12) |
| Speed Boost | Green | Every 12s | 4 | 2× speed for 3s |

- 3 ammo crates + 2 speed crates spawn immediately on game start
- Pickup radius: 40 world units
- One crate → one collector (first ship to touch it)

### GameService
**Status**: Stub — only prints "Initialized".
**Future**: Round lifecycle (WaitingForPlayers → RoundActive → RoundOver), win conditions, scoring.

## Client Controllers

### InputController
Captures W/A/S/D + arrow keys via `UserInputService`. Every Heartbeat frame, sends `{thrust, turn}` to server where thrust/turn are -1, 0, or 1. Spacebar triggers `FireCannon` event (one shot per keypress).

### ViewportController
Creates a `ScreenGui > Viewport (ClipsDescendants) > GameCanvas (3000×3000)`. All game objects are children of GameCanvas. Each frame, pans the canvas so the local player's ship stays centered. Exposes `worldToCanvas(pos)` for coordinate mapping and `getCanvas()` for other controllers to parent objects.

### ShipController
Receives `ShipStateSync` from server (20×/sec). Creates ship GUI frames via ShipBuilder for new ships. Each render frame, lerps visual positions toward server targets (LERP_SPEED=15). Feeds ammo/boost data to AmmoHUD. Emits WakeEffect particles behind moving ships. Cleans up frames for disconnected players.

### ShipBuilder
Factory that creates polygon-style ship visuals from layered Frames. 6 color palettes assigned by `userId % 6`. Ship parts: hull, bow, stern, deck, direction dot, cannon mounts.

### ProjectileController
Receives `CannonFired` events, creates dark circle frames with orange UIStroke. Moves them each frame matching server velocity. Fades near end of lifetime. Also handles `ShipDamaged` (red flash 150ms) and `ShipDestroyed` (shrink+fade tween 500ms).

### CrateController
Renders ammo crates (brown box + cross marking) and speed boost crates (green box + ⚡ icon + pulsing glow). Pop-in animation on spawn, pop-out on collection.

### WakeEffect
Client-only particle system. Spawns 2–5 white/blue square particles behind moving ships (speed > 8 units/sec). Particles drift outward, fade over 1.2s, shrink. Max 600 particles. Spawn interval: 10ms.

### AmmoHUD
Fixed overlay ScreenGui showing:
- Cannonball icon + `X / 12` ammo count (green/yellow/red coloring)
- Speed boost indicator bar with countdown (`⚡ BOOST 3.0s`)
- Flashes green on crate pickup

## Data Flow Diagram

```
┌──────────┐   PlayerInput (60fps)    ┌──────────┐
│  Client   │ ───────────────────────► │  Server   │
│           │   FireCannon (on press)  │           │
│           │ ◄─────────────────────── │           │
│           │   ShipStateSync (20fps)  │           │
│           │   CannonFired            │           │
│           │   ShipDamaged            │           │
│           │   ShipDestroyed          │           │
│           │   CrateSpawned           │           │
│           │   CrateCollected         │           │
│           │   PowerUpSpawned         │           │
│           │   PowerUpCollected       │           │
└──────────┘                           └──────────┘
```
