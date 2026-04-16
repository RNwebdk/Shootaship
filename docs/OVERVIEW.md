# Shootaship — Game Overview

## What Is It?
Shootaship is a **multiplayer top-down 2D ship combat game** built on Roblox. Players control pirate-style ships, collect ammo crates, and blast each other with broadside cannons. The entire game is rendered as **2D GUI elements** (Frames on a ScreenGui), not 3D parts.

## Inspiration
The game is inspired by **"Shipped"** — a top-down ship battle game with momentum-based physics.

## Tech Stack

| Layer           | Technology              | Notes                                  |
|-----------------|-------------------------|----------------------------------------|
| Engine          | Roblox Studio           | Runtime + multiplayer networking        |
| Language        | Luau                    | Roblox's typed Lua dialect             |
| Build System    | Rojo 7.6.1              | Syncs VS Code files into Studio        |
| Toolchain       | Rokit                   | Manages Rojo binary                    |
| Rendering       | Roblox GUI system       | ScreenGui, Frame, UICorner, UIStroke   |
| Physics         | Custom 2D engine        | Vector2-based, NOT Roblox physics      |
| Networking      | Roblox RemoteEvents     | Built-in client/server RPC             |

## Project Structure

```
Shootaship/
├── .tools/
│   └── rojo.exe              # Rojo binary (Windows)
├── docs/                     # You are here
├── src/
│   ├── shared/               # ReplicatedStorage — shared between client & server
│   │   ├── Constants.luau    # All tuning values
│   │   ├── EventDefs.luau    # RemoteEvent name definitions
│   │   └── EventManager.luau # Creates/retrieves RemoteEvents
│   ├── server/               # ServerScriptService — authoritative game logic
│   │   ├── init.server.luau  # Server boot script
│   │   └── Services/
│   │       ├── ShipService.luau    # Ship physics, spawning, state sync
│   │       ├── CombatService.luau  # Cannons, projectiles, hit detection
│   │       ├── CrateService.luau   # Crate/power-up spawning & pickup
│   │       └── GameService.luau    # Round lifecycle (stub)
│   └── client/               # StarterPlayerScripts — rendering & input
│       ├── init.client.luau  # Client boot script
│       └── Controllers/
│           ├── InputController.luau       # Keyboard input → server
│           ├── ViewportController.luau    # 2D camera/canvas panning
│           ├── ShipController.luau        # Ship rendering & interpolation
│           ├── ShipBuilder.luau           # Polygon ship GUI factory
│           ├── ProjectileController.luau  # Cannonball rendering & effects
│           ├── CrateController.luau       # Crate/power-up rendering
│           ├── WakeEffect.luau            # Wake particle trail
│           └── AmmoHUD.luau               # Ammo count & boost indicator
├── default.project.json      # Rojo project mapping
├── rokit.toml                # Toolchain config
└── README.md                 # Quick start
```

## Current State (Phases Completed)

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Environment Setup | ✅ Done | Rokit, Rojo, project structure |
| 2. Core Architecture | ✅ Done | Service/controller pattern, events |
| 3. Ship Movement     | ✅ Done | Physics, input, rendering, wake particles |
| 4. Physics Tuning    | ✅ Done | Drift, angular momentum, particle density |
| 5. Combat System     | ✅ Done | Dual cannons, projectiles, damage, respawn |
| 6. Crates & Power-ups| ✅ Done | Ammo crates, speed boost, HUD |
| 7. Game Rounds       | ⏳ Stub | Round start/end, win conditions |
| 8. Polish            | ⏳ Future | Sounds, UI, tutorial, leaderboard |



All 9 Power-Up Types (including existing speed boost)

Color	Icon   Name	    Effect	    Duration/Count
Green	⚡	  Speed    Boost	   2x thrust & max speed	3 seconds
Red	    🔥	   Damage   Boost	    2x cannonball damage (fiery red cannonballs)	10 seconds
Blue	🛡	    Shield	 Absorbs    next hit (projectile or ram)	1 hit
Purple	✦	   Scatter  Shot	    Each fire shoots 4 cannonballs per side in a spread	3 volleys
Yellow	❤	   Repair	Instantly   restores 50 HP	Instant
Cyan	👻	   Ghost    Mode	    Invulnerable but can't fire	2 seconds
Orange	💥	   Ram	    Deal        40 damage on ship-to-ship contact	5 seconds
White	📦	   Ammo     Dump	    Fills ammo to max (12)	Instant
Pink	🎯	   Homing   Shot	    Next shot fires a forward-tracking cannonball that curves toward the nearest enemy	1 shot

