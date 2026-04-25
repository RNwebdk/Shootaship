# New Computer Setup (Step-by-Step)

This guide gets the project running on a brand-new Windows machine.

## 1. Install required software

1. Install Git: https://git-scm.com/download/win
2. Install Roblox Studio: https://create.roblox.com/docs/studio/setup
3. Install VS Code (optional but recommended): https://code.visualstudio.com/

## 2. Clone the repository

Open PowerShell and run:

```powershell
git clone https://github.com/RNwebdk/Shootaship.git
cd Shootaship
```

## 3. Install Rojo (choose one method)

### Method A (recommended): Rokit

Run:

```powershell
winget install Rokit.Rokit
rokit install
```

Then check Rojo:

```powershell
rojo --version
```

Expected version: 7.6.1.

### Method B (fallback): local `.tools/rojo.exe`

Use this only if Rokit binaries are blocked by policy on your machine.

1. Download Rojo 7.6.1 Windows binary from the official release page:
   https://github.com/rojo-rbx/rojo/releases
2. Create a `.tools` folder in project root.
3. Place the binary at `.tools/rojo.exe`.

Check it:

```powershell
.\.tools\rojo.exe --version
```

## 4. Install the Rojo plugin in Roblox Studio

1. Open Roblox Studio.
2. Go to Plugins -> Manage Plugins.
3. Search for "Rojo" and install it.

## 5. Start live sync from the project

From project root, run one of these:

```powershell
rojo serve
```

or (if using local binary):

```powershell
.\.tools\rojo.exe serve
```

You should see a local server (usually `localhost:34872`).

## 6. Connect Studio to Rojo

1. In Roblox Studio, open the project place (new baseplate is fine).
2. Open the Rojo plugin.
3. Click Connect.
4. Connect to `localhost:34872`.

The project tree from `default.project.json` will sync into Studio.

## 7. Run and test

1. Press Play in Studio.
2. Verify UI/game loads.
3. For multiplayer test: Home -> Test -> Start with 2+ players.

## 8. Build a place file (optional)

If you want a local place file export:

```powershell
rojo build -o "Shootaship.rbxlx"
```

or:

```powershell
.\.tools\rojo.exe build -o "Shootaship.rbxlx"
```

Important: `Shootaship.rbxlx` is git-ignored, so it is generated locally and not stored in repo.

## 9. Keep your clone up to date

From project root:

```powershell
git pull
```

If code changes include new files, re-run Rojo serve/build commands as needed.

## 10. Common checks if something fails

1. Confirm you are in the repository root before running commands.
2. Confirm Rojo plugin is installed in Studio.
3. Confirm `default.project.json` exists and was not renamed.
4. Confirm Rojo is 7.6.1.
5. If `rojo` command is missing, use `.\.tools\rojo.exe` fallback.
