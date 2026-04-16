# Game Mechanics

## Ship Movement

### Controls
| Key | Action |
|-----|--------|
| W / Up Arrow | Thrust forward |
| S / Down Arrow | Thrust backward |
| A / Left Arrow | Rotate left |
| D / Right Arrow | Rotate right |
| Spacebar | Fire cannons |

### Physics Model
Ships use **asteroids-style** momentum physics:
- **Thrust** pushes in the direction the ship is facing
- **Drag** slows you down over time (exponential decay, frame-rate independent)
- **Angular momentum** — turning builds up spin that carries after releasing A/D
- **Angular drag** — spin gradually slows down
- The ship **drifts** when you thrust in one direction then turn — velocity maintains its old direction while facing changes

### Physics Formula
```
-- Each frame (dt = delta time):
angularVelocity += turnInput * TURN_SPEED * dt
angularVelocity *= e^(-ANGULAR_DRAG * dt)
rotation += angularVelocity * dt

velocity += facingDirection * thrustInput * THRUST_FORCE * boostMultiplier * dt
velocity *= e^(-DRAG * dt)
clamp(velocity.Magnitude, 0, MAX_SPEED * boostMultiplier)
position += velocity * dt
clamp(position, mapBounds)
```

### Wake Particles
Moving ships (speed > 8 units/sec) emit 2–5 white/blue square particles from their stern every 10ms. Particles drift outward, fade from semi-transparent to invisible over 1.2 seconds, and shrink. Max 600 particles on screen at once.

---

## Combat

### Cannons
- Ships fire **broadside** — two cannonballs simultaneously, one from each side
- Cannonballs fly **perpendicular** to the ship (left and right), not forward
- Cannonball velocity includes 30% of the ship's own velocity for realism
- **No cooldown** — fire as fast as you can press spacebar
- Each shot costs **1 ammo** (produces 2 cannonballs)

### Cannonball Behavior
- Speed: 600 units/sec
- Lifetime: 2 seconds (then despawns)
- Hitbox: 8-unit radius circle
- Damage: 25 HP per hit
- Removed on hit or when leaving map bounds

### Hit Detection
Server-side circle-vs-circle collision:
- Ship hitbox = circle centered on ship, radius 20 (half of SHIP_SIZE.X)
- Cannonball hitbox = circle, radius 8
- Hit distance = 20 + 8 = 28 world units
- **Self-hit prevention**: cannonballs ignore the ship that fired them
- **One hit per ball**: projectile is removed after hitting one target

### Damage & Death
- Ships have 100 HP
- Each cannonball hit deals 25 damage (4 hits to kill)
- On damage: ship flashes red for 150ms
- On death: ship plays shrink+fade animation (500ms), then is removed from the world
- **Respawn**: Dead ships respawn 3 seconds later at a random position with full HP but 0 ammo

---

## Crates

### Ammo Crates (Brown)
- **Appearance**: Brown wooden box with a cross marking
- **Spawn rate**: One every 8 seconds
- **Max on map**: 8
- **Initial spawn**: 3 at game start
- **Effect**: +3 ammo (capped at 12 max)
- Ships spawn with **0 ammo** — you MUST collect crates before you can fire

### Speed Boost Crates (Green)
- **Appearance**: Green box with ⚡ lightning bolt icon, pulsing glow border
- **Spawn rate**: One every 12 seconds
- **Max on map**: 4
- **Initial spawn**: 2 at game start
- **Effect**: 2× thrust force and max speed for 3 seconds

### Pickup Rules
- Pickup radius: 40 world units (ship center to crate center)
- First ship to reach it gets it — no sharing
- Pop-in animation when spawning (300ms)
- Pop-out animation when collected (200ms)
- Random spawn positions within center 80% of map (avoids edges)

---

## HUD

### Ammo Counter (bottom center)
- Dark rounded bar showing cannonball icon + `X / 12`
- **Green** text: ammo > 2
- **Yellow** text: ammo = 1–2
- **Red** text: ammo = 0
- Flashes green when picking up an ammo crate

### Speed Boost Indicator (above ammo bar)
- Green rounded bar: `⚡ BOOST X.Xs`
- Only visible while boost is active
- Shows countdown of remaining boost time

---

## Map
- Size: 3000 × 3000 world units
- Ships are clamped to stay within bounds
- Projectiles are removed if they leave bounds
- Crates spawn within center 80% (±1200 units from center)

---

## Planned Power-Ups (Not Yet Implemented)

| Color | Name | Effect |
|-------|------|--------|
| Red | Damage Boost | 2× cannonball damage for 5s |
| Blue | Shield | Block the next incoming hit |
| Purple | Scatter Shot | Next 3 volleys fire 4 cannonballs in a spread |
| Yellow | Repair Kit | Instantly heal 50 HP |
| Cyan | Ghost Mode | 2s invulnerability (can't fire during) |
| Orange | Ram | Ship deals contact damage on collision |
| White | Ammo Dump | Instantly fills ammo to max (12) |
| Pink | Homing Shot | Next cannonball curves toward nearest enemy |
