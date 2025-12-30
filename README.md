# super-excavate

Wireless-enabled ComputerCraft quarry helper for All The Mods 10 / Minecraft 1.21 turtles.

## What's included
- `sexcavate.lua`: Primary launcher that supports OTA updates, auto-start, and resume from saves.
- `excavate_core.lua`: Turtle quarry core that:
  - Mines a rectangular prism (length × width × optional depth).
  - Auto-unloads into a chest placed directly above the starting position.
  - Broadcasts wireless status (progress/fuel/errors) over `rednet` with the `super_excavate` protocol.
- `receiver.lua`: Dashboard that listens for broadcasts and prints a live table of turtles. On gold/advanced monitors it switches to a drawing-based, 2×2-optimized view.

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
- To auto-resume on boot (and optionally auto-update), install the startup hook:
  ```
  sexcavate install-startup
  ```
  On reboot the turtle will call `sexcavate auto`, download updates (if HTTP is enabled), and continue the saved job if one exists.

### Over-the-air updates
- OTA pulls files directly from the public GitHub repo listed in `ota_manifest.lua` (update `repo`/`branch` there if you fork).
- With HTTP enabled in ComputerCraft:
  ```
  sexcavate update               # uses repo from ota_manifest.lua
  sexcavate update --repo you/super-excavate --branch main
  ```
- The updater refreshes core files: `sexcavate.lua`, `excavate.lua`, `excavate_core.lua`, `receiver.lua`, `gold_dashboard.lua`, `ota.lua`, `ota_manifest.lua`, `startup.lua`, and `state_store.lua`.

## Dashboard setup (`receiver.lua`)
1. Place a ComputerCraft computer with a **wireless modem** on any side; activate the modem.
2. Copy `receiver.lua` onto the computer and run:
```
receiver
```
3. The screen lists each broadcasting turtle with:
   - Computer ID & label
   - Current state
   - Progress %
   - Fuel remaining
   - Age of last update (seconds)
4. Optional: Place the computer next to an **advanced/gold monitor**, assemble it as a 2×2 (or larger), and run `receiver` on the computer. The dashboard will switch to a colorful drawing-mode UI tuned for a 2×2 gold monitor layout while still working on the computer’s own screen or basic monitors.

You can run multiple dashboards; they all listen on the `super_excavate` protocol.

## Copying the scripts into Minecraft
Option A (pastebin/URL): Upload these files somewhere accessible (e.g., `pastebin put`). On the turtle/computer:
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
