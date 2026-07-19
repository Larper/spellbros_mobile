# Spellbros — Gameplay Mechanic Brainstorm (creative agent)

Design ethos check for every idea: Flappy-simple, one-finger tap-position input only,
must feed the central tension (scarce mana), readable mid-run with zero tutorial.

Scoring: each axis 1-5. **F** = one-finger input fit, **S** = implementation simplicity,
**M** = mana-economy synergy, **A** = addictiveness. Verdict after prototyping/testing.

| # | Idea | F | S | M | A | Verdict |
|---|------|---|---|---|---|---------|
| 1 | **Stomp bounty** — squishing a spike blob drops +1 mana | 5 | 5 | 5 | 4 | **BUILT** |
| 2 | **Golden crystal** — rare crystal worth 3 mana | 5 | 5 | 5 | 4 | **BUILT** |
| 3 | **Spring platform** — every 4th build is a launcher pad | 5 | 4 | 4 | 4 | **BUILT** |
| 4 | **Star of Levity** — pickup granting one stored air-jump | 5 | 4 | 3 | 4 | **BUILT** |
| 5 | Coin magnet pickup (attract crystals for 10 s) | 5 | 3 | 2 | 3 | rejected |
| 6 | Slow-motion focus spell | 2 | 3 | 2 | 3 | rejected |
| 7 | Near-miss score bonus (graze spikes for points) | 5 | 3 | 1 | 2 | rejected |
| 8 | Sticky platform variant (stops the runner briefly) | 5 | 4 | 2 | 1 | rejected |
| 9 | Crumble refund (unused platform refunds its mana) | 5 | 4 | 3 | 1 | rejected |
| 10 | Crystal combo chain (collect within 2 s = double value) | 4 | 3 | 3 | 3 | rejected |
| 11 | Shield bubble (survive one hit) | 5 | 4 | 2 | 3 | rejected |
| 12 | Daily-seed runs | 5 | 2 | 1 | 4 | rejected (meta, not a mechanic) |
| 13 | Mana cap with overflow-to-score | 5 | 3 | 2 | 2 | rejected |
| 14 | Flying ghost enemy | 5 | 3 | 2 | 3 | deferred (content, not a mechanic) |

## Why the winners won

1. **Stomp bounty (+1 mana per squished blob).** The entity budget means a chunk with an
   enemy usually *lost* its crystal slot — so the enemy IS the crystal, if you are brave
   enough to stomp it. Turns every blob from pure threat into a risk/reward decision at
   full run speed. Zero new input, zero UI, self-teaching via a "+1" popup. Deterministic
   (always drops) because a probabilistic drop would be unreadable mid-run.

2. **Golden crystal (worth 3).** Classic rare-reward dopamine. 10% of all crystal spawns.
   Directly feeds the economy without inflating it much (expected value of a crystal goes
   from 1.0 to 1.2 mana). Instantly readable: gold, bigger, sparkles, "+3" popup.

3. **Spring platform (every 4th build).** Adds a counting rhythm to the build economy:
   skilled players *save* the spring for mega gaps or climb walls, because one spring
   launch (~1.6x jump height) replaces a whole staircase of builds. The HUD shows a small
   "SPRING READY" tag when the next build is a springboard, so it needs no tutorial and
   never surprises. Springs are green with up-chevrons; landing on one always launches.

4. **Star of Levity (stored air-jump).** Already floated in the plan file as double-jump;
   reshaped to the simplest possible form: a rare star pickup stores exactly ONE mid-air
   jump (tap the wizard while airborne to spend it). No timers, no stacking — one charge,
   sparkles around the wizard while held so you always know you have it. Economy synergy:
   an air jump is effectively a free platform in the climb/void phases (saves 1 mana),
   but it never *generates* mana, so no inflation. Spawns after the enemy phase, high up,
   competing for the same entity budget as crystals.

## Why the losers lost

- **Coin magnet (5):** crystals are hand-placed *on the intended path* — a magnet either
  does nothing or trivializes the void-phase fragment trails, which are the endgame's
  entire skill test. Fights the scarcity design head-on.
- **Slow-motion (6):** needs a new input verb (hold? double-tap?) — violates the
  tap-position-is-everything vocabulary. Auto-triggering it removes player agency.
- **Near-miss bonus (7):** score is distance; a hidden second score source muddies the
  cleanest number in the game. Invisible mechanics are wasted mechanics.
- **Sticky platform (8):** stopping the runner fights the auto-run core AND the
  crush-camera. A platform that kills you by making you stand still is a trap, not a tool.
- **Crumble refund (9):** rewards NOT using the thing you paid for — a perverse incentive
  that teaches spamming builds you never touch.
- **Combo chain (10):** needs a visible timer to be fair; any timer UI is over budget for
  a game with one number and one resource.
- **Shield bubble (11):** one-mistake-death is the Flappy contract. A shield dilutes the
  tension that makes runs addictive, and stomp-bounce already gives a skill-based save.
- **Daily seed (12):** great retention feature but it is meta/UI work, not a run mechanic;
  out of my lane-size for this pass.
- **Mana cap (13):** adds bookkeeping and punishes hoarding without teaching anything.
- **Ghost enemy (14):** worth doing someday, but it is content variety, not a new
  mechanic, and tuning a flying threat against the one-way platform builder is a whole
  balancing pass of its own.

## Iteration notes

**Stomp bounty.** First question was drop *chance*: a 50% probabilistic drop felt more
"balanced" on paper, but you cannot read a coin flip at 780 px/s — a stomp must always
pay or players will never risk the detour. Went deterministic. Added a dedicated
side-hit regression test after realizing the bounty could tempt a bug where touching a
blob sideways also paid out (it does not: side hits still kill, pay nothing). This
mechanic introduced the `Main.float_text` popup helper, which the next two mechanics
reused for free.

**Golden crystal.** Considered guaranteeing the golden over mega gaps (reward bridging)
but the mega-gap crystal is already a placed reward — stacking certainty there would
turn "jackpot" into "salary". Kept a flat 10% roll on every spawn so *any* crystal can
be the exciting one. Measured spawn rate across test runs: 8.5-12% over 400 samples,
right on target. Expected crystal value rises only 1.0 -> 1.2 mana, so scarcity holds.

**Spring platform.** Two design forks resolved while building:
- *Launch condition:* "bounce only when falling fast" vs "always launch on landing".
  Picked always-launch (a trampoline, not a conditional) — one rule, zero ambiguity,
  and it makes a panic-build spring under your feet a spectacular save.
- *Anticipation:* a surprise launch off the 4th build could fling you into a spike or
  past your landing zone, which felt like the game cheating. Fix was the one-line HUD
  cue "NEXT BUILD: SPRING" shown one build ahead — you always opt in. Also zeroed
  coyote time on launch so a buffered tap cannot stack a jump onto the spring impulse.
  Cadence set to every 4th (every 3rd is too frequent against the 4 s platform
  lifetime — springs should feel banked, not ambient).
  Headless test measured the launch at -1445 observed velocity vs the -1170 jump.

**Star of Levity.** The plan file's "double-jump for 10 s" was reshaped twice:
- Timed buffs are invisible under pressure (no player watches a 10 s clock mid-gap), so
  it became a *stored charge* — state you can see (gold sparkles orbit the wizard) and
  spend deliberately with the existing tap-the-wizard verb. No new input.
- One charge, no stacking: a second star while holding one just refreshes to one.
  Removes all bookkeeping.
  Implementation detail the headless test surfaced: after teleporting the player into
  the air, `is_on_floor()` and coyote time both stay warm for a few frames, so a
  "mid-air" tap can silently take the normal coyote-jump path instead of spending the
  charge. The branch ordering (coyote jump first, star jump only when truly airborne)
  is exactly what the test asserts.

**Economy audit after all four.** Income: crystals (placed, budgeted), stomp bounties
(risk-priced), goldens (rare spike). Spends: builds, with every 4th build also buying a
launcher, and stars saving a build outright. Nothing mints mana for free; everything
routes through the existing entity budget or through risk. Max income per chunk is
unchanged (budget-capped) except the swarm-phase double stomp (+2), which is priced by
stomping two patrolling blobs back-to-back at speed — kept as a skill-expression
jackpot, with the bounty amount noted as the tuning lever if runs ever get too rich.
