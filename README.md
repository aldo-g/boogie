# Pars and Chars

A golf-themed **card** game — currently being prototyped digitally in Godot 4
to test whether the core mechanics are fun before committing to physical
production. Working title "Pars and Chars."

> **Note on the design:** this project pivoted away from dice. Shot
> resolution is now the **Form Card System**: you can see every card's effect
> before you play it, and nothing about where the ball goes is hidden. The
> randomness is *which cards you are offered* and each hole's wind, which is
> shown before you aim. There is one deliberate exception: a shot that
> finishes on the cup from off the green earns a **d20**, and only a natural
> 20 holes it (see "Holing out from off the green" below). See
> [GAME_DESIGN.md](GAME_DESIGN.md) for the full design document, which is
> the source of truth.

## Concept

Play a round of golf across a **fixed 18-hole course** (a real course layout —
no random hole generation). Grow a bag of club cards as you go, resolve each
shot by picking from a hand of Form cards whose effects are fully visible, and
finish on the green with a timing-based putting meter. Solo play is against
par; **2-4 players** can share a screen in hot-seat.

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

**Club abilities — every card's text does what it says**
- Many clubs carry a **rider** that changes how that club plays: better or
  worse buffering, no rough penalty, a wider Mid tier, a wood that plays
  from sand. These live as `effects` beside the card text in
  `assets/data/clubs.json`.
- Some clubs **create** Form cards. An *active* ability is a button in the
  Abilities box under the shot panel, with a charge per hole or per round
  ("Gold Cleek: create a Pure Strike · 1 left per hole"). Pressing it puts
  the card straight into the current Form hand. A *passive* one fires on
  its own (land in sand with Old Tom's Niblick and your next draw holds a
  Flop Shot). A created card exhausts whether you play it or not, so the
  decision is which shot to spend it on, not whether to hoard it.
- A created card always makes a forced draw a real choice: in a bunker the
  club still forces a bad card on you, but a created card beside it is the
  bail-out.
- Activated set bonuses sit in the same box: Titanist 7 re-draws the hand,
  MacGregorian 7 improves your lie, Nimbus 2 plays a shot one tier better,
  Nimbus 7 plays it as the ideal club.
- **Range session**: at the end of any hole you can skip the draft to
  remove 2 bad cards from your Form deck. It's the way back from a run of
  bad holes, paid for in bag progress.

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
  distance multiplier, side. The deck's good cards are Stinger, Controlled
  Draw/Fade, Power Draw, Soft Fade, Flushed, Spinner, Punch Out, Flop Shot,
  Bump and Run and In the Zone (which also removes a bad card from your
  deck); bad ones are Hook, Slice, Pull, Push, Duck Hook, Overswing, Top,
  Thin, Chunk, Skied, Shank and Yips. Pure Strike, Big Strike and Steady
  Hands are never drawn — only clubs create them.
- The Form deck starts at 28 good / 14 bad (67% good). **Landing in a
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

## Records and settings

**Records** are kept per course in `user://records.json`: your best
round (strokes, vs par, who and when), rounds played, the last 20 rounds,
and your best score on every hole. The title screen's course box shows
the course record, **Records** on the title opens the full card, the shot
panel shows "Your best" on the hole you're playing, and the end of a round
says whether you've set a new course record. Solo and every hot-seat seat
are recorded; online, only your own seat. A course is identified by its
contents, so editing a custom course starts its record afresh, and
editor test rounds record nothing.

**Settings** (title screen, or the header's **Settings** mid-round) are
kept in `user://settings.cfg` and apply as you change them: master, music
and effects volume; shot animation (Normal, Fast, or Instant, which skips
straight to where the ball stops); and the putt strike key (Space by
default).

## Multiplayer (2-4 players)

Two ways to play together, both from the title screen.

**Online** — one player hosts, the others join by address. Up to 4 players,
each on their own machine. On the same network (two people in one house,
say) there is nothing to configure: the host's lobby shows the address to
type, and that's the whole setup.

**Hot-seat** — pick a player count and everyone shares one screen, taking
turns. Clicking the background still tees off solo.

Both use the same turn rules below.

- **Turn order is "furthest from the pin plays first"** — real golf
  etiquette, and it spreads downtime evenly. Seating order off the tee,
  since there are no distances to compare yet.
- The order applies to **putting as well**, so a player who leaves a long
  one doesn't stand there holing out while everyone waits.
- A hole ends only once **every** player is in.
- The header shows **whose turn it is**, tinted by seat colour, plus a
  running standings chip per player. The other players' balls show on the
  hole map in their seat colours.
- At the end of the round the log leads with **final standings** and the
  winner (stroke play — lowest total wins; ties are reported as ties).

### Online play

ENet over LAN or a direct IP, with **no backend to run**. On the same
network it just works — the host's lobby displays the address to join on,
so there is nothing to look up. Across the internet it needs port
forwarding or a VPN (Tailscale, ZeroTier).

The host is also a player and is **authoritative**: clients send what they
want to do, the host decides what happened and tells everyone. Clients
never roll their own dice, so nobody can disagree about a shot. The design
makes this cheap — every per-player write in `Main.gd` goes through the
active player, so pointing that at the acting seat makes the ordinary
hot-seat code the authoritative code, with no separate server logic.

If a player drops, their seat is retired, the hole is conceded for them,
and the round carries on. If the *host* drops the round ends — there is no
host migration.

One accepted limitation: the putting meter is a real-time timing check on
the putting player's own machine, so the host takes their word for the
result. For a game among friends that is the right trade; hardening it
would mean the host owning the meter's clock, which would make the one
timing-based moment in the game feel laggy.

### Per-player state

**Each player has their own bag, Form deck, and draft pool.** That means
hazard decay only degrades the Form deck of the player who found the
hazard, and the end-of-hole draft is an **independent draw-3 per player** —
nobody can take the card you wanted. Whether that lack of contention makes
the draft feel inert is an open playtesting question; see
[GAME_DESIGN.md](GAME_DESIGN.md) Section 7.

Because the drafts are independent, **online everyone drafts at once** —
each on their own machine — and the next hole starts when the last pick
is in. Hot-seat drafts stay one at a time, since everyone shares the
screen.

Every draft card says **what it would change**: a set tier it completes,
a club rider it switches on, a yardage gap it fills, or how far it moves
a brand toward its next set. When the bag is full, each club you might
cut says what cutting it would break.

After every shot the log and the shot panel take it apart — **how far it
carried and rolled, and what the wind and the slope added or cost** — so
the wind and elevation are something you can learn, not just suffer.

Simultaneous/secret shot declaration (in the original design note) is not
implemented and isn't buildable on one shared screen — it needs networked
multiplayer. Sequential turns are the hot-seat equivalent.

## Repo layout

```
Bogey/
├── project.godot          Godot project config
├── GAME_DESIGN.md         Full design document (source of truth)
├── assets/
│   ├── data/clubs.json    The club roster — every club's band, type, brand and text
│   ├── data/caddy_lines.json  Everything Charlie the caddy says, by situation
│   ├── art/caddy/         Charlie, the arctic char caddy
│   ├── fonts/             AlexBrush (title wordmark)
│   └── maps/              Reference course layout (18 holes)
├── scenes/
│   ├── Title.tscn         Title screen + player-count picker (entry point)
│   ├── CourseEditor.tscn  The course editor
│   └── Main.tscn          The game
├── tools/
│   └── Capture.tscn       Screenshot capture helper
└── scripts/
    ├── Main.gd            Game loop, state machine, UI construction
    ├── ShotRules.gd       The rules of a stroke — tier, Form draw, lies, penalties, putt leaves
    ├── ClubAbilities.gd   What club text does: riders, created cards, charges, passives
    ├── Records.gd         Per-course bests and history, saved between sessions
    ├── DraftAdvisor.gd    What a draft pick would change, and what a cut would cost
    ├── Settings.gd        Volume, shot speed and putt key, saved between sessions
    ├── SettingsPanel.gd   The settings controls (title page and in-game popup)
    ├── ClubRoster.gd      Loads the club roster; starter bag, draft pool, live brands
    ├── Player.gd          One player's state (bag, ball, score, Form deck)
    ├── Net.gd             The multiplayer connection (autoload)
    ├── Credits.gd         Attributions shown on the credits screen
    ├── Caddy.gd           Charlie the caddy: when he pops up and what he says
    ├── GameSetup.gd       Round setup carried between scenes
    ├── MPTest.gd          Headless flow harness (dev tool, see below)
    ├── DetTest.gd         Determinism harness (dev tool)
    ├── GuardTest.gd       Action-validation harness (dev tool)
    ├── NetTest.gd         Two-peer networked harness (dev tool)
    ├── CreditsCheck.gd    Checks required attributions reach the screen
    ├── CourseTest.gd      Custom-course harness (dev tool)
    ├── RulesTest.gd       Rules and roster harness, no screen (dev tool)
    ├── TestBags.gd        Ability loadouts the flow harnesses play with (dev tool)
    ├── RecordsTest.gd     Records and settings persistence harness (dev tool)
    ├── ShotResolver.gd    Shot math — distance, deviation, cup radius
    ├── FormCard.gd        A single Form card and its known effect
    ├── FormDeck.gd        The shared Form deck and per-tier draws
    ├── Brands.gd          Brand sets and their rules bonuses
    ├── HoleData.gd        The built-in 18 as centrelines; terrain, bounds, elevation
    ├── Course.gd          The active course; custom courses, save/load, sanitising
    ├── CourseEditor.gd    The course editor screen
    ├── CourseEditOverlay.gd  Drag handles over the hole map in the editor
    ├── CourseShape.gd     Turns centrelines into curved polygons
    ├── CourseMapView.gd   The hole map: terrain, aiming, ball flight
    ├── ElevationProfileView.gd  Side-view elevation strip under the hole map
    ├── Wind.gd            Per-hole wind from the round's seed, and how to describe it
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

Note that `--check-only` on a single script reports false errors for
`class_name` globals (`Player`, `GameSetup`) and autoloads (`Sound`),
because neither is registered when one script is checked in isolation.
Import the project once (`godot --headless --editor --quit`) and those
resolve.

Headless harnesses, all dev tools:

```sh
# The rules and the club roster on their own, no screen: swing tiers,
# Form draw counts, brand bonuses, lies and penalties, putt leaves, and
# every club ability against its card text
godot --headless --script res://scripts/RulesTest.gd

# Records and settings: bests only improve, history caps, an edited course
# starts fresh, settings survive a reload and survive a bad file. Uses
# scratch files — never your own records
godot --headless --script res://scripts/RecordsTest.gd

# Full 18-hole rounds for 1-4 players: turn order, hole flow, bag caps
godot --headless --script res://scripts/MPTest.gd

# The caddy's line file: every situation has lines, no typo'd keys or
# placeholders
godot --headless --script res://scripts/CaddyTest.gd

# Malformed and out-of-turn actions are refused rather than crashing
godot --headless --script res://scripts/GuardTest.gd

# Two instances, same actions + same rolls -> identical state.
# This is the property online play depends on.
godot --headless --script res://scripts/DetTest.gd

# A real host and client over a socket in one process, asserting after
# every action that they agree about the whole round.
godot --headless --script res://scripts/NetTest.gd

# ...and the same, but the client disconnects partway through
NETTEST_DROP_AT=120 godot --headless --script res://scripts/NetTest.gd

# Custom courses: wire round-trip, sanitising, save/load, editor edits,
# a 3-hole round, and the course travelling in the online payload
godot --headless --script res://scripts/CourseTest.gd
```

## Custom courses

**Course editor** on the title screen builds courses of 1-18 holes. Drag
the fairway points, width tabs, green, bunkers and water corners on the
hole map; set par, green size and tilt, and elevation in the side panel.
**Test play** runs a solo round on the course in progress and its
**Editor** button brings you back. Saved courses are JSON in
`user://courses/` (on macOS,
`~/Library/Application Support/Godot/app_userdata/Pars and Chars/courses/`)
and appear in the title screen's course picker. A hosted online round
sends its course to everyone who joins, so other players don't need the
file.

`NetTest` shares a process, so it covers the protocol and the mirroring
but cannot catch genuine socket problems (real latency, packet loss, MTU).
Two machines, or two processes over 127.0.0.1, are still worth a smoke
test before trusting a change.

Add `MPTEST_COUNTS=3,4` to run a subset. It plays randomly rather than
well, so the stroke totals are meaningless — it checks that the flow never
stalls, never skips a player, keeps every bag within the 14-club cap, and
finishes 18 holes for everyone. In group rounds every seat after the first
plays an ability loadout from `TestBags.gd`, and the bots press abilities
and take range sessions at random, so every ability gets played; DetTest
and NetTest do the same. It sets `CourseMapView.skip_animation` so
shots resolve with no tween; a full 4-player round is ~1,200 actions and
takes a few seconds.

## What's implemented

- Full **18-hole round** with a running scorecard and end-of-round summary
- **Multiplayer for 2-4 players, online or hot-seat** — furthest-from-pin
  turn order, per-player bags/Form decks/draft pools, standings and a
  winner; host-authoritative online with disconnect recovery
- Starting Bogey-Mart bag; draw-3-pick-1 club draft each hole (14-club cap,
  forced discard when full)
- **Brands, set bonuses at 2/4/7, per-run draft pools, and limited-edition
  clubs**
- **Club abilities** — per-club riders, created cards (Pure Strike, Big
  Strike, Flop Shot, Bump and Run, Steady Hands) with per-hole and
  per-round charges, passives, activated set bonuses, and range sessions
- **Form Card shot resolution** — deterministic, tier-based draw counts, club
  buffering
- **Per-hole wind, elevation, slope and roll-out**: club yardage is carry,
  and the ball runs on after landing
- Click-to-aim on a drawn hole map with swing-tier bands and a live landing
  preview per Form card
- Terrain (fairway / rough / bunker / water / **out of bounds**) with distance
  caps, penalties, and hazard-driven Form deck decay
- **Hole-outs from any distance**, gated on a d20, with a yellow aim line
- Distance-scaled **putting timing meter** with gimmes
- **Restart** from the header at any point (arms then confirms mid-round)

## Not in this version

- A per-flight weather deck (wind is per hole and stays fixed for the hole)
- Internet play without port forwarding (no relay — see above)
- Host migration if the host leaves
- Simultaneous/secret shot declaration
- Mid-round join

## Numbers worth tuning

- **Hole-out odds** — `HOLE_OUT_TARGET` in `scripts/ShotResolver.gd`
  (currently 20 on a d20 = 5%; 19 would make it 10%). Cup radius curve is
  `CUP_RADIUS_NEAR` / `CUP_RADIUS_FAR` in the same file.
- **Terrain distance caps** — `TERRAIN_DISTANCE_CAP` in `ShotResolver.gd`
  (rough 80%, bunker 50%).
- **Club buffering** — `BUFFER_BY_TYPE` in `ShotResolver.gd`.
- **Form deck good/bad ratio** — `build_starting_deck()` in `FormDeck.gd`
  (currently 24 good / 12 bad = 67%).
- **Hazard → bad card odds** — `FORM_DECAY_CHANCE` in `scripts/ShotRules.gd`
  (currently 1 in 3). A range session removes `RANGE_SESSION_PURGE` (2).
- **Club abilities** — riders are `effects` in `assets/data/clubs.json`;
  charges (per hole / round / six holes) are in `allowance()` in
  `scripts/ClubAbilities.gd`, and Steady Hands' widening is
  `STEADY_HANDS_WIDEN` there.
- **Putting difficulty** — the `SUNK_HALF_*` / `CLOSE_HALF_*` / `SPEED_*`
  constants in `PuttMeter.gd`.
- **Bag cap and gimme range** — `HAND_CAP` at the top of `Main.gd`;
  `GIMME_YARDS` in `scripts/ShotRules.gd`.
- **Club yardage bands, brands and card text** — `assets/data/clubs.json`.
  Standards appear `standard_copies` times in each run's pool; branded
  clubs only when their brand is live. `RulesTest` checks the file is
  well-formed.
- **Caddy lines** — `assets/data/caddy_lines.json` (see its `_comment` for
  placeholders). How often he talks is `CHANCE` and `COOLDOWN_SEC` in
  `scripts/Caddy.gd`. `CaddyTest` checks the file after editing.
- **Hole layouts** — the `HOLES` centreline table in `HoleData.gd` (line ~104).
