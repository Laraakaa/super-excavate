# super-excavate

Wireless-enabled ComputerCraft quarry helper for All The Mods 10 / Minecraft 1.21 turtles.

## What's included
- `setup.lua`: One-shot installer/OTA bootstrap that downloads the latest files (and can install the startup hook).
- `sexcavate.lua`: Primary launcher that supports auto-start and resume from saves.
- `excavate_core.lua`: Turtle quarry core that:
  - Mines a rectangular prism (length × width × optional depth).
  - Auto-unloads into a chest placed directly above the starting position.
  - Broadcasts wireless status (progress/fuel/errors) over `rednet` with the `super_excavate` protocol.
- `receiver.lua`: Dashboard that listens for broadcasts and prints a live table of turtles. On gold/advanced monitors it switches to a drawing-based, 2×2-optimized view.

## Install / update with `setup`
Download the installer directly from GitHub raw and run it on the turtle/computer:
```
wget https://raw.githubusercontent.com/Laraakaa/super-excavate/main/setup.lua setup
setup --startup
```

- By default, it pulls from `Laraakaa/super-excavate` on `main`.
- Use `--repo owner/name` and `--branch branch-name` to point OTA at your fork; `setup` will fetch that repo’s `ota_manifest.lua` first so it automatically follows file additions/removals (including updating itself).
- Rerun `setup` any time to update to the latest files; it overwrites the tracked scripts, refreshes `ota_manifest.lua`, and removes stale tracked files.
- `--startup` installs `startup.lua` for the detected/forced role:
  - **Turtle (default when the `turtle` API exists):** `startup.lua` runs `sexcavate auto` to resume digs.
  - **Receiver (default on a regular ComputerCraft PC):** `startup.lua` runs `receiver` on boot.
- Force a role with `--role turtle` or `--role receiver`.

## Turtle setup (`sexcavate`)
1. Place a **chest directly above** the turtle start block (e.g., turtle on the floor, chest one block higher).
2. Attach a **wireless modem** to any turtle side and right-click it once to activate.
3. Fuel:
   - Drop fuel into any inventory slots (charcoal/coal/etc.). Program will consume only as needed.
   - The script estimates fuel conservatively; bring extra for safety.
4. Facing: The turtle will dig forward along the direction it faces, then snake rows to the right.

### Run it
```
sexcavate <length> <width> [depth]
```
- `length`: Blocks forward.
- `width`: Blocks to the right.
- `depth`: (Optional) Layers downward. Default `1`. The turtle digs the starting layer and moves down each time.

Example (10×6 area, 3 layers deep):
```
sexcavate 10 6 3
```

### Behavior notes
- **Unloading**: When inventory fills or when finished, the turtle returns home, drops everything into the chest above, then resumes (if mid-job).
- **Status**: Broadcasts `ready`, `excavating`, `unloading`, `error`, and `done` with progress %, fuel, and position.
- **Fuel check**: Stops immediately with an error if it cannot reach the estimated fuel budget.
- **Obstacles/mobs**: The turtle digs/attacks forward/up/down until it can move. Keep mobs cleared if possible.
- **Reach/safety**: Turtle moves one block at a time. Ensure the quarry fits within loaded chunks; keep dimensions within chunk boundaries for unattended runs when chunkloading isn't available.

### Auto-resume & startup
- Jobs are persisted to `.sexcavate_state` so a reboot or crash can resume in-place.
- To resume manually:
  ```
  sexcavate resume
  ```
- To auto-resume on boot, run `setup --startup` once. On reboot the turtle will call `sexcavate auto` and continue the saved job if one exists.

### Over-the-air updates
- OTA pulls files directly from the public GitHub repo listed in `ota_manifest.lua` (default `Laraakaa/super-excavate` on `main`).
- With HTTP enabled in ComputerCraft, rerun the installer to refresh everything:
  ```
  setup                         # updates from the default repo/branch
  setup --repo you/super-excavate --branch main
  ```
- The installer/updater refreshes core files: `setup.lua`, `sexcavate.lua`, `excavate.lua`, `excavate_core.lua`, `receiver.lua`, `gold_dashboard.lua`, `ota.lua`, `ota_manifest.lua`, `startup.lua`, `state_store.lua`, and `version.lua`.
- How it works:
  - `ota_manifest.lua` declares the GitHub `repo`, optional `branch`, and the list of files to pull.
  - `setup` builds `https://raw.githubusercontent.com/<repo>/<branch>/<file>` URLs, downloads each with the ComputerCraft `http` API, and overwrites the local copies.
  - If you pass `--repo`/`--branch`, the manifest is rewritten locally so future updates continue to use that source.
  - The command exits with an error if HTTP is disabled in your server/client config; enable `http` in ComputerCraft to use OTA.

## Dashboard setup (`receiver.lua`)
1. Place a ComputerCraft computer with a **wireless modem** on any side; activate the modem.
2. Install/update with the setup script (non-turtle PCs auto-detect as receivers):
```
wget https://raw.githubusercontent.com/Laraakaa/super-excavate/main/setup.lua setup
setup --role receiver --startup
```
3. Or copy `receiver.lua` manually and run:
```
receiver
```
4. The screen lists each broadcasting turtle with:
   - Computer ID & label
   - Current state
   - Progress %
   - Fuel remaining
   - Age of last update (seconds)
   - Version + git commit (short)
5. Optional: Place the computer next to an **advanced/gold monitor**, assemble it as a 2×2 (or larger), and run `receiver` on the computer. The dashboard will switch to a colorful drawing-mode UI tuned for a 2×2 gold monitor layout while still working on the computer’s own screen or basic monitors.

You can run multiple dashboards; they all listen on the `super_excavate` protocol.

## Copying the scripts into Minecraft
Option A (recommended): use the installer directly from GitHub:
```
wget https://raw.githubusercontent.com/Laraakaa/super-excavate/main/setup.lua setup
setup --startup
```
Option B (manual copy): Upload individual files somewhere accessible (e.g., `pastebin put`). On the turtle/computer:
```
wget <url-to-sexcavate.lua> sexcavate
wget <url-to-receiver.lua> receiver
```
Option B (disk/drive): Copy the files into a ComputerCraft disk directory and insert the disk into the turtle/computer, then copy:
```
cp disk/sexcavate.lua sexcavate
cp disk/receiver.lua receiver
```
Make the files executable by running them directly (`sexcavate ...`, `receiver`).

## Tips and limitations
- Keep quarry dimensions reasonable to avoid chunk borders if you do not use chunk loaders.
- For very large digs, consider placing extra chests above the start point so unloading never backs up.
- If you lose wireless coverage, excavation continues; status just won't reach the dashboard until signal resumes.

## Testing outside Minecraft
- The excavation logic lives in `excavate_core.lua`, which can run against a simulated environment.
- Run `lua5.4 tests/run.lua` to execute the lightweight unit tests that mock the turtle, modem, and rednet APIs.
- Local setup tips:
  - Ubuntu/Debian: `sudo apt-get update && sudo apt-get install -y lua5.4`.
  - macOS (Homebrew): `brew install lua`.
  - If your environment blocks apt mirrors, try a different mirror or run the tests in GitHub Actions (already configured).
