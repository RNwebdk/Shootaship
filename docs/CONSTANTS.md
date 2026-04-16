# Constants Reference

All values are defined in `src/shared/Constants.luau` and shared between client and server.

## Ship Physics

| Constant | Value | Description |
|----------|-------|-------------|
| `SHIP_MAX_SPEED` | 600 | Maximum velocity (world-units/sec) |
| `SHIP_THRUST_FORCE` | 300 | Acceleration when pressing W |
| `SHIP_TURN_SPEED` | 8 | Angular acceleration (radians/sec²) |
| `SHIP_MAX_TURN_SPEED` | 4.5 | Max angular velocity (radians/sec) |
| `SHIP_DRAG` | 1.0 | Linear drag — velocity halves every ~0.7s |
| `SHIP_ANGULAR_DRAG` | 0.5 | Rotational drag — spin halves every ~1.4s |
| `SHIP_SIZE` | 40 × 60 | Ship width × height (world units) |

### Drag Tuning Guide
- **SHIP_DRAG** controls how quickly the ship slows down after releasing thrust:
  - `0.5` = Very floaty, lots of drift
  - `1.0` = Moderate glide (current)
  - `2.0` = Snappy, stops quickly
  - Terminal velocity ≈ THRUST_FORCE / DRAG (currently ~300)
- **SHIP_ANGULAR_DRAG** controls spin carry-through after releasing A/D:
  - `0.5` = Long spin (current)
  - `1.5` = Quick stop
  - `3.0` = Almost instant stop

## Combat

| Constant | Value | Description |
|----------|-------|-------------|
| `CANNONBALL_SPEED` | 600 | Projectile speed (units/sec) |
| `CANNONBALL_DAMAGE` | 25 | HP per hit (4 hits to kill) |
| `CANNONBALL_LIFETIME` | 2 | Seconds before despawning |
| `CANNONBALL_SIZE` | 8 | Hitbox radius (world units) |
| `SHIP_MAX_HEALTH` | 100 | Starting HP |
| `CANNON_SIDE_OFFSET` | 22 | Distance from ship center to cannon mount |
| `STARTING_AMMO` | 0 | Ammo on spawn (must collect crates) |
| `AMMO_PER_CRATE` | 3 | Shots gained per ammo crate |
| `MAX_AMMO` | 12 | Maximum ammo capacity |

## Power-Ups

| Constant | Value | Description |
|----------|-------|-------------|
| `SPEED_BOOST_MULTIPLIER` | 2.0 | Thrust & max speed multiplier during boost |
| `SPEED_BOOST_DURATION` | 3 | Seconds the speed boost lasts |
| `POWERUP_SPAWN_INTERVAL` | 12 | Seconds between power-up crate spawns |
| `MAX_POWERUPS` | 4 | Max power-up crates on map |

## Map

| Constant | Value | Description |
|----------|-------|-------------|
| `MAP_WIDTH` | 3000 | World width (units) |
| `MAP_HEIGHT` | 3000 | World height (units) |
| `VIEWPORT_SCALE` | 1 | 1 world unit = 1 pixel |

## Crates

| Constant | Value | Description |
|----------|-------|-------------|
| `CRATE_SPAWN_INTERVAL` | 8 | Seconds between ammo crate spawns |
| `CRATE_SIZE` | 30 | Crate width/height (world units) |
| `MAX_CRATES` | 8 | Max ammo crates on map |
| `CRATE_PICKUP_RADIUS` | 40 | Collection distance (world units) |

## Networking

| Constant | Value | Description |
|----------|-------|-------------|
| `SYNC_RATE` | 1/20 (0.05) | Server sends state updates every 50ms (20fps) |
