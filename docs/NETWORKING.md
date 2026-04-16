# Networking & Events

## Overview
Shootaship uses Roblox's built-in **RemoteEvent** system for client-server communication. All events are defined in `src/shared/EventDefs.luau` and created at server startup by `EventManager`.

## Event Reference

### Client → Server Events

#### `PlayerInput`
- **Sender**: InputController (every frame)
- **Payload**: `{ thrust: number, turn: number }`
  - `thrust`: -1 (backward), 0 (none), 1 (forward)
  - `turn`: -1 (left), 0 (none), 1 (right)
- **Server handler**: ShipService — updates ship.input, validates/clamps values

#### `FireCannon`
- **Sender**: InputController (on spacebar press)
- **Payload**: none
- **Server handler**: CombatService.handleFire — validates ammo, creates 2 projectiles

### Server → All Clients Events

#### `ShipStateSync`
- **Sender**: ShipService.broadcastState (20×/sec)
- **Payload**: table keyed by userId
  ```lua
  {
    [userId] = {
      px = number,    -- position X
      py = number,    -- position Y
      vx = number,    -- velocity X
      vy = number,    -- velocity Y
      r  = number,    -- rotation (radians)
      av = number,    -- angular velocity
      hp = number,    -- health
      ammo = number,  -- current ammo
      boost = number? -- speed boost seconds remaining (nil if not boosted)
    }
  }
  ```
- **Client handler**: ShipController.onStateSync — creates/updates/removes ship visuals

#### `CannonFired`
- **Sender**: CombatService (on valid fire)
- **Payload**:
  ```lua
  {
    id = number,      -- projectile ID
    ownerId = number, -- userId of shooter
    px = number,      -- spawn position X
    py = number,      -- spawn position Y
    vx = number,      -- velocity X
    vy = number,      -- velocity Y
  }
  ```
- **Client handler**: ProjectileController.onCannonFired — creates cannonball visual

#### `ShipDamaged`
- **Sender**: CombatService (on hit)
- **Payload**:
  ```lua
  {
    targetId = number,   -- userId of damaged ship
    attackerId = number, -- userId of attacker
    damage = number,     -- damage dealt
    newHealth = number,  -- target's remaining HP
  }
  ```
- **Client handler**: ProjectileController.onShipDamaged — red flash on target ship

#### `ShipDestroyed`
- **Sender**: CombatService (when health ≤ 0)
- **Payload**:
  ```lua
  {
    targetId = number,   -- userId of destroyed ship
    attackerId = number, -- userId of killer
  }
  ```
- **Client handler**: ProjectileController.onShipDestroyed — shrink+fade animation

#### `CrateSpawned`
- **Sender**: CrateService (on ammo crate spawn)
- **Payload**: `{ id = number, px = number, py = number, crateType = "ammo" }`
- **Client handler**: CrateController.onCrateSpawned — creates brown crate visual

#### `CrateCollected`
- **Sender**: CrateService (on ammo crate pickup)
- **Payload**: `{ crateId = number, playerId = number, newAmmo = number, crateType = "ammo" }`
- **Client handler**: CrateController.onCrateCollected — pop-out animation + AmmoHUD flash

#### `PowerUpSpawned`
- **Sender**: CrateService (on speed boost spawn)
- **Payload**: `{ id = number, px = number, py = number, powerType = "speed" }`
- **Client handler**: CrateController.onPowerUpSpawned — creates green crate with ⚡

#### `PowerUpCollected`
- **Sender**: CrateService (on speed boost pickup)
- **Payload**: `{ crateId = number, playerId = number, powerType = "speed" }`
- **Client handler**: CrateController.onCrateCollected — pop-out animation

### Server → Specific Client Events

#### `PlayerSpawned`
- **Sender**: ShipService (when a player's ship is created)
- **Payload**: `{ position = { x = number, y = number }, rotation = number }`
- **Client handler**: ShipController — logs spawn position

### Unused (Future)

#### `RoundStarting`
For future round lifecycle — server tells all clients a new round is beginning.

#### `RoundEnded`
For future round lifecycle — server tells all clients the round is over with winner info.

## Network Timing

| Data | Rate | Direction | Bandwidth |
|------|------|-----------|-----------|
| Player input | ~60 fps | C → S | Low (2 numbers) |
| Ship state sync | 20 fps | S → All | Medium (8 fields × N players) |
| Fire events | On press | C → S, S → All | Burst |
| Crate events | On spawn/collect | S → All | Rare |

## Client Interpolation
The server sends positions at 20fps, but the screen renders at 60fps. The client uses **lerp interpolation** (LERP_SPEED = 15) to smoothly move ship visuals between server updates. This fills the 50ms gaps and makes movement look fluid.

## Security Model
- **Roblox guarantees** the `player` argument in `OnServerEvent` — clients cannot spoof their identity
- **Server validates** all input: thrust/turn clamped to [-1, 1], ammo checked before firing, health checked before actions
- **No client-side game logic** — clients only render what the server tells them
- **Hit detection is server-only** — clients cannot fake hits or damage
