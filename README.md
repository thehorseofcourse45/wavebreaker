# Wavebreaker

A top-down twin-stick arena shooter. Survive escalating waves, spend credits
between waves on upgrades, and bank salvage at the end of a run for permanent
perks. Built with Godot 4.7 (GL Compatibility) — no external art or audio: the
arena, the enemies, the poster and every sound effect are drawn or synthesised
in code, with a handful of CC0 streams for the music beds.

## Controls

| Input | Action |
|-------|--------|
| `WASD` / arrows | Move |
| Mouse | Aim |
| Left mouse | Fire |
| Right mouse | Charge shot (once bought) |
| `Space` | Dash (burst with i-frames) |
| `Esc` | Pause |
| `R` | Restart (on the game-over screen) |

## Weapons

Pick one on the title screen before a run; it sets the shooting baseline the shop
then upgrades on top of.

| Gun | Character |
|-----|-----------|
| `RIFLE` | Balanced automatic (the default: the baseline every other gun is measured against) |
| `NEEDLER` | Very fast, light rounds, sloppy at range |
| `BREACHER` | Five pellets, punishing up close, falls off fast |
| `VIPER` | Slow, precise, hard-hitting marksman |
| `LANCE` | Hyper-velocity slug that pierces four enemies in a line |
| `FURNACE` | Short-range cone of short-lived rounds |
| `SLUGGER` | Slow hand cannon, pierces one, shoves hard |

## The adaptive director

Waves react to how you are actually doing. After every wave the director reads
that wave -- the worst your health got, and how long the pack took to clear --
and biases the next one. Come through untouched and the roster grows (about 25%
heavier, plus a couple of elites) while spawns press in 15% faster; get chewed up
and it thins out and eases off. The wave banner says which way it went
(`PRESSURE RISING` / `EASING OFF`), and `[Wave] ...` in the log carries the
pressure number.

It biases the authored table, it never replaces it: the first wave of a run is
exactly as authored, and boss waves are exempt -- their escort is deliberately
trimmed because the boss *is* the wave.

## Run from source

Requires [Godot 4.7](https://godotengine.org/download) (the project uses the
`4.7` feature set and GL Compatibility renderer).

```sh
# open the project in the editor
godot --path .

# or run it directly
godot --path . --headless   # not playable, but a smoke test
godot --path .
```

On a clean checkout, open the project (or run `godot --path . --import`) once so
Godot builds its import and global-class caches before running the tests or
exporting.

## Tests

The suite is gated behind a command-line flag and runs headless:

```sh
godot --path . --headless NEON_TEST
```

It prints `SELFTEST PASS` and exits `0`, or `SELFTEST FAIL (n):` with one line
per failed probe and exits `1`. It snapshots and restores your real `user://`
save, so running it never touches your records.

Screenshot modes for eyeballing the look (non-headless; writes `shot_<mode>.png`):

```sh
godot --path . NEON_SHOT=menu     # title poster (shows the version strap)
godot --path . NEON_SHOT=run      # arena 1 in a live run
godot --path . NEON_SHOT=over     # game-over summary card
godot --path . NEON_SHOT=shadow   # occluder shadow A/B measurement
```

## Build

Export templates for the engine version must be installed. The Windows preset is
committed in `export_presets.cfg` and writes `Wavebreaker.exe`:

```sh
godot --path . --headless --export-release "Windows Desktop" Wavebreaker.exe
```

The build output (`*.exe`, `*.pck`) and the `.godot/` cache are git-ignored; the
game is always rebuilt from source.
