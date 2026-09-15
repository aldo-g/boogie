# Bogey

A golf-themed **card** game — currently being prototyped digitally in Godot 4
to test whether the core mechanics are fun before committing to physical
production. Working title "Bogey."

> **Note on the design:** this project pivoted away from dice. Shot
> resolution is now the **Form Card System** — fully deterministic, no hidden
> rolls. The only randomness in the tee-to-green game is *which cards you are
> offered*. See [GAME_DESIGN.md](GAME_DESIGN.md) for the full design document,
> which is the source of truth.

## Concept

Play a round of golf across a **fixed 18-hole course** (a real course layout —
no random hole generation). Grow a bag of club cards as you go, resolve each
shot by picking from a hand of Form cards whose effects are fully visible, and
finish on the green with a timing-based putting meter. Solo play is against
par.

## Core mechanics

**The bag (deckbuilding-adjacent, but non-standard)**
- Start with three Bogey-Mart clubs — Driver, 7-Iron, Putter. Deliberately the
  worst gear in the game: you start with it and only ever lose it.
- At the **end of every hole**, draw 3 clubs from a shared pool and permanently
  add 1 to your bag.
- Bag caps at 14 clubs (a real club limit). Once full, discard before adding.
- Any club in the bag can be played for any shot.
- No currency, no shop — the draw-3-pick-1 step is the entire acquisition
  system.

**Brands — the synergy layer**
- Every club carries a **type** (wood / iron / wedge / putter), which is
  mechanical, and a **brand** (Titanist, Callowell, Ping-Well, MacGregorian,
  Slazinger, Nimbus), which is social and does nothing on its own.
- Brands pay out at **2 / 4 / 7** clubs sharing your bag. Seven is half the bag,
  so a 7-set is an identity rather than a bonus — that squeeze is the point.
- Set bonuses are always **rules** effects ("draw an extra Form card", "ignore
  terrain penalties"), never yardage, so they don't need rebalancing per course.
- Each run draws a limited pool guaranteeing at least two genuinely different
  directions to build in.
- **Limited-edition clubs** are mixed into the same pool at lower odds — the
  same club types with better stats or a bonus ability.

**Shot resolution — the Form Card System**
- Each club has a yardage band (min–max) and a type that determines
  *buffering*: how much of a Form card's deviation actually reaches the ball.
  A wedge halves it; a driver applies it in full.
- Aim by clicking the hole map. Where you aim within the club's band sets the
  **swing tier**, which decides how many Form cards you get to choose from:
  - **Mid-range** → draw 3, pick 1 *(the comfortable, repeatable swing)*
  - **Full swing / Finesse** → draw 2, pick 1 *(less room to dodge a bad card)*
  - **Extreme Finesse** → no draw at all; a bad card is created and forced on you
- Form cards are **fully known before you pick** — degrees of deviation,
  distance multiplier, side. Good cards include Pure Strike, Stinger,
  Controlled Draw/Fade, Flop Shot; bad ones are Hook, Slice, Top, Chunk, Shank
  and Yips.
- The shared Form deck starts at 24 good / 12 bad (67% good). **Landing in a
  hazard can add a bad card into that deck**, so a rough patch degrades your
  draws for the rest of the round.

**Terrain and hazards**
- Rough cuts distance to 80%, bunkers to 50%. Bunkers also force the Extreme
  Finesse treatment (no draw, forced bad card) and bar woods — except the
  MacGregorian Persimmon Driver, whose whole identity is being the one wood you
  can play from sand.
- Water is a stroke penalty and a drop.
- **Out of bounds** is stroke-and-distance (Rule 18) — the playable extent is
  computed from each hole's own geometry, so it doesn't shift with window size.

**Holing out from off the green**
- A shot that finishes on the cup earns a **d20**, and only a natural **20**
  drops. The cup radius scales with distance travelled (3 yards on a short
  chip, tightening to 1.1 at 260+), so distance governs how often you get to
  roll — but no distance is excluded, and an ace is possible on the par 3s.
- Anything short of 20 rattles the cup and leaves a short putt scaled by the
  roll, so the die is visible in where the ball ends up.
- The **aim line turns yellow** when your current line would earn that roll.

**Putting — a timing meter**
- The deliberate exception to "no timing checks": a marker sweeps a bar and you
  stop it. Distance to the pin sets both the width of the sunk band and the
  marker's speed, so a tap-in is nearly free and a long lag putt is a real
  nerve test.
- Putts inside 0.7 yards (about 2 feet) are conceded as a gimme.

## Repo layout

```
Bogey/
├── project.godot          Godot project config
├── GAME_DESIGN.md         Full design document (source of truth)
├── assets/
│   ├── fonts/             AlexBrush (title wordmark)
│   └── maps/              Reference course layout (18 holes)
├── scenes/
│   ├── Title.tscn         Title screen (entry point)
│   └── Main.tscn          The game
├── tools/
│   └── Capture.tscn       Screenshot capture helper
└── scripts/
    ├── Main.gd            Game loop, state machine, UI construction
    ├── ShotResolver.gd    Shot math — distance, deviation, cup radius
    ├── FormCard.gd        A single Form card and its known effect
    ├── FormDeck.gd        The shared Form deck and per-tier draws
    ├── Brands.gd          Brand sets and their rules bonuses
    ├── HoleData.gd        18 holes as centrelines; terrain and bounds
    ├── CourseShape.gd     Turns centrelines into curved polygons
    ├── CourseMapView.gd   The hole map: terrain, aiming, ball flight
    ├── PuttMeter.gd       The putting timing meter
    ├── CardView.gd        Club card rendering and hover detail
    ├── FormCardView.gd    Form card rendering
    ├── ScorecardView.gd   Running scorecard
    ├── BogeyTheme.gd      Colour palette
    ├── BogeyUI.gd         Shared UI helpers (panels, chips, headings)
    └── Title.gd           Title screen
```

The entire UI is built in code — there's nothing to wire up in the scene
editor.

## Running the prototype

1. Install [Godot 4.x](https://godotengine.org) (standard/non-.NET build).
2. Open Godot, click **Import**, and select `project.godot` in this repo.
3. Press **Play** (▶ top-right, or Cmd+B on macOS / F5 on Windows/Linux).
   It runs `scenes/Title.tscn`; click to tee off.

To parse-check a script without opening the editor:

```sh
godot --headless --check-only --script scripts/Main.gd
```

## What's implemented

- Full **18-hole round** with a running scorecard and end-of-round summary
- Starting Bogey-Mart bag; draw-3-pick-1 club draft each hole (14-club cap,
  forced discard when full)
- **Brands, set bonuses at 2/4/7, per-run draft pools, and limited-edition
  clubs**
- **Form Card shot resolution** — deterministic, tier-based draw counts, club
  buffering
- Click-to-aim on a drawn hole map with swing-tier bands and a live landing
  preview per Form card
- Terrain (fairway / rough / bunker / water / **out of bounds**) with distance
  caps, penalties, and hazard-driven Form deck decay
- **Hole-outs from any distance**, gated on a d20, with a yellow aim line
- Distance-scaled **putting timing meter** with gimmes
- **Restart** from the header at any point (arms then confirms mid-round)

## Not in this version

- Weather (per-flight conditions)
- Multiplayer (simultaneous selection, turn order)
- Slope on the greens

## Numbers worth tuning

- **Hole-out odds** — `HOLE_OUT_TARGET` in `scripts/ShotResolver.gd`
  (currently 20 on a d20 = 5%; 19 would make it 10%). Cup radius curve is
  `CUP_RADIUS_NEAR` / `CUP_RADIUS_FAR` in the same file.
- **Terrain distance caps** — `TERRAIN_DISTANCE_CAP` in `ShotResolver.gd`
  (rough 80%, bunker 50%).
- **Club buffering** — `BUFFER_BY_TYPE` in `ShotResolver.gd`.
- **Form deck good/bad ratio** — `build_starting_deck()` in `FormDeck.gd`
  (currently 24 good / 12 bad = 67%).
- **Hazard → bad card odds** — `maybe_add_bad_card_to_form_deck()` in
  `Main.gd` (currently 1 in 3).
- **Putting difficulty** — the `SUNK_HALF_*` / `CLOSE_HALF_*` / `SPEED_*`
  constants in `PuttMeter.gd`.
- **Bag cap and gimme range** — `HAND_CAP` and `GIMME_YARDS` at the top of
  `Main.gd`.
- **Club yardage bands and brands** — `build_club_pool()` in `Main.gd`.
- **Hole layouts** — the `HOLES` centreline table in `HoleData.gd` (line ~104).
