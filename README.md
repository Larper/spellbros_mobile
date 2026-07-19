# Spellbros

An endless runner-builder for phones: an auto-running wizard, one finger, and a
level that only exists because you build it. Flappy Bird ethos — dead simple,
brutally hard, one-more-run addictive.

**Play it:** https://spellbros.neven.one (best on a phone, landscape)

Built in **Godot 4.7**, code-first: one scene ([scenes/main.tscn](scenes/main.tscn)),
every node created in GDScript, all art drawn in `_draw()`, all audio
procedurally synthesized. Zero asset files.

## How it plays

The wizard runs right on his own. You only decide when he jumps and where
platforms appear:

- **Tap LEFT of the wizard → jump** (coyote time + input buffer make taps forgiving)
- **Tap RIGHT of the wizard → build a platform** there (costs 1 mana)
- Touch builds land **90 px left of the tap** (`BUILD_TOUCH_NUDGE`) because
  thumbs consistently aim wide right
- The jump/build divider **never shrinks left of the wizard's resting spot**
  (~22% from the left edge), so the jump zone survives even when the crush
  camera pushes him toward the edge
- Keyboard (PC convenience): **Space** jump, **R** restart, **P** pause

**Score** is distance in meters (100 px = 1 m). **You start with 0 mana** —
the opening teaches you to be greedy.

## Core systems

- **Mana economy** — crystals are deliberately scarce: at most 2 entities
  (crystals + enemies + pickups) per chunk, 3 after 300 m. Stomping an enemy
  pays **+1 mana bounty**, so brave stomps are income.
- **Built platforms** — 240×24 one-way light-bridges. They crumble after
  **4.0 s** early game, shrinking to **2.4 s** between 300–600 m. Collision is
  full-size instantly, so a panic-build under your feet saves you.
- **Enemies (blobs)** — glowing circles that sit still where they spawn;
  stomp from above kills them (and refreshes one mid-air jump until you
  land), any other touch kills you.
- **Crush camera** — the camera never waits. It holds a lead while you keep
  pace but keeps rolling (at 85% run speed) if you stall; fall behind the left
  screen edge and you die. Stalling to build stairs is a calculated risk.
- **Speed ramp** — 470 px/s base, +1.5 px/s per meter past 110 m, capped at
  900 px/s (~397 m). All normal gaps are sized as fractions of the *live* run
  speed so they stay jumpable at any speed (jump math is documented in
  [scripts/terrain_spawner.gd](scripts/terrain_spawner.gd)).
- **Camera framing** — 1.25× zoom (visible world 1536×864), wizard at ~22%
  from the left edge, and the camera eases down when terrain ahead sits lower
  so the next pillar is on screen before you drop.

## Pickups

| Pickup | Looks | Where | Effect |
|---|---|---|---|
| Mana crystal | cyan diamond | everywhere (scarce) | +1 mana |
| Star of Levity | gold star, hung high | from 50 m, 8% of chunks | stores **one mid-air jump**; gold sparkles orbit you while held; stomp refresh is spent before the star so it's never wasted |
| Spring powerup | green coil | from 300 m, 8% of chunks + 20% of void pillars | your **next 3 builds are spring pads** (still 1 mana) that launch you at ~1.6× jump height on landing; HUD counts SPRING x3 → x1 |

## Level layout — the difficulty phases

There are no levels: terrain is generated chunk by chunk, and difficulty gates
on **where the chunk sits in meters** (never on player distance — chunks spawn
~27 m ahead, and gating on the player made phases arrive visibly late). It
opens with a 20 m safe runway and two teaching crystals, then:

| Meters | Phase | What changes |
|---|---|---|
| 0–25 | warm-up | plain gaps, all jumpable |
| 25 | BUILD | **mega gaps** appear — wider than any jump, must be bridged (one platform always suffices); a crystal floats over each as the reward |
| 50 | ENEMY | blobs start appearing; Stars of Levity start spawning |
| 85 | CLIMB | **climb waves** — terrain staircases up beyond jump height; each step needs a build, steps pay out crystals more reliably |
| 110 | SPEED | run speed starts ramping (+1.5 px/s per meter) |
| 170 | SWARM | 2 enemies per wide chunk, faster blobs, mega gaps can **chain into doubles** (45%) |
| 300 | RICH | entity budget 2 → 3; platforms now crumble fastest; spring powerups appear |
| 380 | VOID | ground mostly **vanishes**: crystal fragment trails float in open sky and must be caught with platform chains; rare narrow pillars offer solid ground (and springs) |

The headless test suite audits every phase band for **beatability**: 80 sampled
chunks per band, every gap checked against the jump-reach math, zero unbeatable
chunks tolerated.

## Development

```powershell
# run the game (Neven playtests; agents verify headless only)
godot --path "C:\Dev\Spellbros Mobile"

# headless smoke test — the only automated verification
godot --headless --path . -s res://tests/smoke_test.gd

# after adding a new class_name script
godot --headless --path . --import

# deploy to https://spellbros.neven.one (exports Web preset, uploads via cPanel API)
powershell -File deploy.ps1
```

- [scripts/main.gd](scripts/main.gd) — game manager: input routing, camera, speed/platform tuning
- [scripts/player.gd](scripts/player.gd) — wizard physics (gravity 3300, jump −1170, coyote/buffer)
- [scripts/terrain_spawner.gd](scripts/terrain_spawner.gd) — all phases, gap math, entity budget
- [scripts/hud.gd](scripts/hud.gd), [scripts/audio.gd](scripts/audio.gd) — HUD; synthesized SFX + music
- [tests/smoke_test.gd](tests/smoke_test.gd) — feature tests + difficulty/beatability audit

The **web build** is single-threaded (no COOP/COEP headers needed anywhere),
shows a rotate-your-phone overlay in portrait, and locks fullscreen landscape
on first tap where the browser allows it. An Android APK deploy (Pixel 8 Pro,
direct install) is planned; export templates are already installed.
