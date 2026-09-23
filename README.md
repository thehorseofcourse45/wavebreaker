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
then upgrades on top of. The shop itself carries **38 rows** (each with a
procedurally drawn icon); every wave clears and deals a random hand of six —
REROLL or the `offers` upgrade widens it.

| Gun | Character |
|-----|-----------|
| `RIFLE` | Balanced automatic (the default: the baseline every other gun is measured against) |
| `NEEDLER` | Very fast, light rounds, sloppy at range |
| `BREACHER` | Five pellets, punishing up close, falls off fast |
| `VIPER` | Slow, precise, hard-hitting marksman |
| `LANCE` | Hyper-velocity slug that pierces four enemies in a line |
| `FURNACE` | Short-range cone of short-lived rounds |
| `SLUGGER` | Slow hand cannon, pierces one, shoves hard |

## Arenas

Seven arenas (`Main.ARENA_SCENES`), unlocked in run order: a full boss wave
advances to the next; the vault behind `vault_arena` is gated until you clear
wave 20. Each has its own hazard table entry (`ArenaHazard`).

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

## The bestiary

`Esc` -> **BESTIARY**: every enemy in the game (49 rows), grouped `NORMAL` /
`ELITES` / `BOSSES`, each with a portrait, a line on how it fights and its base
HP. The roster is taller than the window, so the tab scrolls.

Enemies you have not met yet are dimmed and keep their fight hint hidden; the
progress line counts how many you have met, and that set is saved when a run
ends. It all comes from one registry (`scripts/beasts.gd`) that the wave spawner
draws its scenes from too, so adding an enemy is one row there plus its scene --
never three lists to keep in step.

## Elites

Every archetype you meet also has an **elite variant** (49 bestiary rows in all:
23 normal, 22 elite, 4 bosses). An elite is the same enemy with a shield phase --
invulnerable in bursts, cyan while it holds and its natural colour when it drops
-- plus 2.5x health and 3x score.

The wave table's `elite` column says *how many* elites a wave fields, not which
ones: the registry picks the archetypes, so an elite can be anything from a
shielded rusher to a shielded medic. Bosses are excluded -- their phases are
already their own thing.

**Difficulty decides how many.** `EASY` fields none at all, `NORMAL` the count the
wave table authors, `HARD` doubles it and `NIGHTMARE` triples it (the same table
that scales health/speed/spawn, so every wave routes through one place).

Tuning: `WaveManager.DIFFICULTIES[id]["elite"]` for the counts,
`Beasts.ELITE_HP_MULT` / `ELITE_SCORE_MULT` for the family defaults (a row
overrides with its own `hp_mult` or `score_mult`), and the shield timings are the
`shielded` affix in `scripts/enemy.gd`.

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

## Shop

Between waves: a random hand of 6 from the 38-row registry (`UpgradeSystem.DEFS`).
Prices grow ×1.70 per level of the same row (plus a ~+50% base-cost pass over
earlier builds). Rarity (`common` / `rare` / `epic`) multiplies both price and
effect size. `bargain` cuts rerolls 40%/level; `offers` adds one row per level to
the hand. Pool-written rows (crit, homing, ricochet, explosive, bossbane, mark,
executioner, burn, magnet, scavenger) reset at the start of every run via
`BulletPool.reset_run_config()` / `PickupPool.reset_run_config()`.

## Build

Export templates for the engine version must be installed. The Windows preset is
committed in `export_presets.cfg` and writes `Wavebreaker.exe`:

```sh
godot --path . --headless --export-release "Windows Desktop" Wavebreaker.exe
```

The build output (`*.exe`, `*.pck`) and the `.godot/` cache are git-ignored; the
game is always rebuilt from source.
