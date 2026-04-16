# Setup & Development Guide

## Prerequisites
- **Roblox Studio** (free from roblox.com)
- **VS Code** with Rojo extension (optional but recommended)
- **Rojo 7.6.1** — already included in `.tools/rojo.exe`

## Quick Start

### 1. Serve with Rojo (hot reload)
```powershell
cd C:\Users\casha\Documents\Shootaship
.\.tools\rojo.exe serve
```
This starts a local server at `http://localhost:34872`.

### 2. Connect Roblox Studio
1. Open Roblox Studio
2. Install the **Rojo plugin** (Plugins → Manage Plugins → search "Rojo")
3. In Studio: Plugins tab → Rojo → **Connect** to `localhost:34872`
4. Code changes in VS Code now sync to Studio in real-time

### 3. Test the game
- Press **Play** (▶) in Studio to start the game
- Move with WASD, fire with Spacebar
- Pick up brown crates for ammo, green crates for speed boost

### 4. Test multiplayer
- In Studio: Home tab → **Test** → **Start** (set Players to 2+)
- This simulates multiple clients connected to one server

## Alternative: Build to file
```powershell
.\.tools\rojo.exe build -o "Shootaship.rbxlx"
```
Then double-click `Shootaship.rbxlx` to open in Studio.

## Project File Mapping

`default.project.json` maps local files to Roblox services:

| Local Path | Roblox Location | Runs On |
|-----------|-----------------|---------|
| `src/shared/` | ReplicatedStorage.Shared | Both |
| `src/server/` | ServerScriptService.Server | Server only |
| `src/client/` | StarterPlayer.StarterPlayerScripts.Client | Each client |

## Folder Conventions

- **`src/shared/`** — Modules that both client and server need (constants, events)
- **`src/server/Services/`** — One module per game system (ShipService, CombatService, etc.)
- **`src/client/Controllers/`** — One module per client system (InputController, ShipController, etc.)
- **`docs/`** — Game documentation (you are here)
- **`.tools/`** — Local tool binaries (Rojo)

## Adding a New Feature

### New Server Service
1. Create `src/server/Services/MyService.luau`
2. Export `init()` and `update(deltaTime)` functions
3. Require and call both in `src/server/init.server.luau`

### New Client Controller
1. Create `src/client/Controllers/MyController.luau`
2. Export `init()` and optionally `update(deltaTime)`
3. Require and call in `src/client/init.client.luau`

### New RemoteEvent
1. Add the event name to `src/shared/EventDefs.luau`
2. Server fires it with `EventManager.getEvent("Name"):FireAllClients(data)`
3. Client listens with `EventManager.waitForEvent("Name").OnClientEvent:Connect(...)`

### New Constant
1. Add to `src/shared/Constants.luau`
2. Access from any module: `local Constants = require(ReplicatedStorage.Shared.Constants)`

## Toolchain Notes

### Rokit
Config in `rokit.toml`. Manages tool versions. However, **Windows Application Control** may block binaries from `~/.rokit/bin`. Workaround: we use `.tools/rojo.exe` (direct download to project).

### Rojo
Version 7.6.1. Config in `default.project.json`. Syncs file changes into Roblox Studio in real-time via a local HTTP server.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Expected `<eof>`, got `function`" | Leftover duplicate code after a `return` statement — delete everything after the final `return` |
| Events queue exhausted | Client failed to load — check client error above it in the console |
| Ship not moving | Check that InputController initialized (look for print in console) |
| Cannons not firing | Check ammo count — ships start with 0, must collect crates first |
| Rojo won't connect | Make sure `.tools\rojo.exe serve` is running and Studio plugin is installed |
