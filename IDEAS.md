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

(Filled in as mechanics were built and tested — see bottom of file.)
