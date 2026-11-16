# Pars and Chars

A golf-themed **card** game — currently being prototyped digitally in Godot 4
to test whether the core mechanics are fun before committing to physical
production. Working title "Pars and Chars."

> **Note on the design:** this project pivoted away from dice. Shot
> resolution is now the **Form Card System**: you can see every card's effect
> before you play it, and nothing about where the ball goes is hidden. The
> randomness is *which cards you are offered*, each hole's wind and where its
> pin is cut — and the wind and the pin are shown before you aim. There is one deliberate exception: a shot that
> finishes on the cup from off the green earns a **d20**, and only a natural
> 20 holes it (see "Holing out from off the green" below). See
> [GAME_DESIGN.md](GAME_DESIGN.md) for the full design document, which is
> the source of truth.

## Concept

Play a round of golf across a **fixed 18-hole course** (a designed layout —
no random hole generation; four ship with the game, each on its own
terrain). Grow a bag of club cards as you go, resolve each
shot by picking from a hand of Form cards whose effects are fully visible, and
finish on the green with a timing-based putting meter. Solo play is against
par; **2-4 players** can share a screen in hot-seat, and you can take on a
**computer golfer** at one of three skill levels.

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
- **Your form is the club's.** Every Form card belongs to a club family —
  Wood, Iron, Wedge or Putter — and a swing is dealt only from the family of
  the club in hand: a driver is never handed a Flop Shot. Each family has its
  own shots and its own misses, and keeps its own form, shown in the Form
  column between draws.
- Form cards are **fully known before you pick** — degrees of deviation,
  distance multiplier, side. The deck's good cards are Stinger, Controlled
  Draw/Fade, Power Draw, Soft Fade, Flushed, Spinner, Punch Out, Flop Shot,
  Bump and Run and In the Zone (which also removes a bad card from your
  deck); bad ones are Hook, Slice, Pull, Push, Duck Hook, Overswing, Top,
  Thin, Chunk, Skied, Shank and Yips. Pure Strike, Big Strike and Steady
  Hands are never drawn — only clubs create them.
- The Form deck starts at 35 good / 18 bad, about two good to one bad in
  each family. **Trouble can add a bad card into that deck** — one time in
  three for sand, water or out of bounds, one in five for a ball that
  finishes in the rough — in the family of the club that found the trouble.
  So a wild driver goes cold and leaves the wedges alone, and a scrappy
  stretch degrades your draws with that kind of club for the rest of the
  round. Played cards go to the discard pile and come round again; only
  cards a club creates are used up.

**Terrain and hazards**
- Rough cuts distance to 80% (and can leave a bad card, above), bunkers to 50%. Bunkers also force the Extreme
  Finesse treatment (no draw, forced bad card) and bar woods — except the
  MacGregorian Persimmon Driver, whose whole identity is being the one wood you
  can play from sand.
- Water is a stroke penalty and a drop.
- **Out of bounds** is stroke-and-distance (Rule 18). The ground in play is
  not a box round the hole but a shape grown out from it — about 38 yards
  either side of the line of play, 34 beyond the fairway's edge, 26 beyond
  the green — marked by white stakes on the map. It is worked out from each
  hole's own geometry, so it doesn't shift with window size. Water counts
  as in play only near the hole: a burn or the sea can run on past the
  stakes, and out there it is out of bounds.

**The course through a round**
- **Pin positions.** Each green has nine places for the hole — the middle,
  four sides, four corners — and every round cuts one per green, so the
  same hole asks for a different shot next time: a front pin and a back
  pin are a club apart. The flag on the map is where the hole is, and a
  note under the wind dial says it in words ("Pin · back left"). Yardage
  markers and the scorecard measure to the middle of the green.
- **It gets harder as it goes.** Through the first five holes of eighteen
  nothing changes. From there the **wind gets up** — a calm hole becomes a
  breezy one, though gales are no stronger and no more common — and the
  **pins get tucked away**: further
  from the middle, never in it by the end, and more and more often on the
  side nearest sand or water. Your bag is fuller by then; so is the
  course's.
- Both come from one seed per round, so everyone in an online round sees
  the same wind and the same pins.

**Holing out from off the green**
- A shot that finishes on the cup earns a **d20**, and only a natural **20**
  drops. The cup radius scales with distance travelled (3 yards on a short
  chip, tightening to 1.1 at 260+), so distance governs how often you get to
  roll — but no distance is excluded, and an ace is possible on the par 3s.
- Anything short of 20 rattles the cup and leaves a short putt scaled by the
  roll, so the die is visible in where the ball ends up.

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
are recorded; online, only your own seat. A custom course is identified by
its contents, so editing one starts its record afresh; the game's own
courses keep theirs, whoever hosts the round and however a hole is later
reshaped. Editor test rounds record nothing.

**Settings** (title screen, or the header's **Settings** mid-round) are
kept in `user://settings.cfg` and apply as you change them: master, music
and effects volume; shot animation (Normal, Fast, or Instant, which skips
straight to where the ball stops); and the putt strike key (Space by
default).

## Multiplayer (2-4 players)

Three ways to play against someone, all from the title screen.

**Online** — one player hosts, the others join by address. Up to 4 players,
each on their own machine. On the same network (two people in one house,
say) there is nothing to configure: the host's lobby shows the address to
type, and that's the whole setup.

**Hot-seat** — pick a player count and everyone shares one screen, taking
turns. Clicking the background still tees off solo.

**Against the computer** — pick one of three computer golfers on the
title screen and play them shot for shot, on one screen. See "Against the
computer" below.

All three use the same turn rules below.

- **Turn order is "furthest from the pin plays first"** — real golf
  etiquette, and it spreads downtime evenly. Seating order off the tee,
  since there are no distances to compare yet.
- The order applies to **putting as well**, so a player who leaves a long
  one doesn't stand there holing out while everyone waits.
- A hole ends only once **every** player is in.
- The shot column is headed by **whose turn it is**, ruled in that
  player's seat colour, and the scorecard in the header carries a line
  per player. The other players' balls show on the hole map in their seat
  colours.
- At the end of the round the shot column gives the **final standings**
  (stroke play — lowest total first; ties are reported as ties).

### Against the computer

Three computer golfers, by how well they play. The scores are what each
typically shoots on Bogey Links (par 71), measured with the balance
harness:

| Golfer | | Typically shoots |
|---|---|---|
| Dory Mulligan | Weekend hacker | about 86 (15 over) |
| Coley Niblick | Club regular | about 75 (4 over) |
| Ace Marlin | Scratch golfer | about 67 (4 under) |

A computer golfer is an ordinary seat in a hot-seat round, played by
`GreedyBot` through the same functions the screen calls for a person. It
plays the real rules with its own bag, draft pool and Form deck, and it
sees nothing the screen doesn't show. What separates the three is only how
badly each misjudges a line and how unsteady each is on the putt meter.

- You watch their turn: the club, the line on the map, the Form hand they
  drew, the card they keep (lit), then the
  shot. The pauses shorten with the shot-speed setting.
- Nothing you press counts while they are up. The log says who leads after
  every hole, and Charlie remarks on their good and bad holes, takes stock
  at halfway and has the last word on the match.
- Their round is never recorded. Yours is, as a "vs computer" round.

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
│   ├── fonts/             Alex Brush (wordmark), Cormorant Garamond (names and
│   │                      numbers), Jost (labels and text) — all SIL OFL
│   ├── courses/           The game's other courses, as course files (see "Courses")
│   └── maps/              Reference course layout (18 holes)
├── scenes/
│   ├── Title.tscn         Title screen + player-count picker (entry point)
│   ├── CourseEditor.tscn  The course editor
│   └── Main.tscn          The game
├── tools/
│   ├── Capture.tscn       Screenshot capture helper
│   └── CourseSheet.tscn   Paints every hole of a course into one PNG
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
    ├── Rivals.gd          The computer golfers: names and skill numbers
    ├── GreedyBot.gd       The bot behind them (and behind the balance harness)
    ├── HoleBanner.gd      The stamp that lands on the map when a hole is finished
    ├── MPTest.gd          Headless flow harness (dev tool, see below)
    ├── CpuTest.gd         Rounds against computer golfers (dev tool)
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
    ├── CourseLibrary.gd   The courses that ship with the game
    ├── CourseTheme.gd     Terrains: firmness, wind, palette and scenery for each
    ├── CourseEditor.gd    The course editor screen
    ├── CourseEditOverlay.gd  Drag handles over the hole map in the editor
    ├── CourseShape.gd     Turns centrelines into curved polygons
    ├── CourseMapView.gd   The hole map: aiming, ball flight, everything that moves
    ├── CourseArt.gd       The painted ground under it, drawn once per hole
    ├── ElevationProfileView.gd  Side-view elevation strip under the hole map
    ├── Wind.gd            Per-hole wind from the round's seed, and how to describe it
    ├── Pins.gd            Where each green's hole is cut this round, from the same seed
    ├── PuttMeter.gd       The putting timing meter
    ├── CardFace.gd        The one card: the layout, type scale and states clubs and Form cards share
    ├── CardView.gd        Club cards: bag tile, draft specimen and hover detail
    ├── FormCardView.gd    Form cards, as rows beside the hole map, each with its shot drawn to scale
    ├── ScorecardView.gd   The scorecard in the header: holes across, a line per player
    ├── BogeyTheme.gd      Colour palette — ink on paper, colour rationed to three jobs
    ├── BogeyUI.gd         Typefaces, the stock-control theme, and shared UI helpers
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

# Rounds against computer golfers, played by the game's own per-frame
# driver: every seat finishes, nothing a person presses counts on a
# computer turn, their rounds aren't recorded, and the hole stamp, the
# streak and the Bogey-Mart retirement fire when they should. Slower than
# the others (a few minutes): the bot plans every shot properly
godot --headless --script res://scripts/CpuTest.gd

# Courses: wire round-trip, sanitising, save/load, editor edits, a 3-hole
# round, the course travelling in the online payload, terrain (firmness
# and wind, and that parkland plays as it always did), every hole of
# every shipped course checked for soundness, and what builds through a
# round (the wind getting up, the pins: on the green, repeatable, tucked late)
godot --headless --script res://scripts/CourseTest.gd
```

## Courses

Four 18-hole courses ship with the game. Step through them with the
arrows beside the course name on the title screen.

| Course | Terrain | Par | Yards | What it's like |
|---|---|---|---|---|
| **Bogey Links** | Parkland | 71 | 6,510 | The home course: tree-lined, a little of everything |
| **Windlestraw Links** | Links | 71 | 6,743 | Out along the sea and back through the dunes. Wide fairways, pot bunkers, burns |
| **Mirage Mesa** | Desert | 72 | 6,860 | Narrow fairways across hardpan, big waste bunkers, three oasis ponds |
| **Thin Air Ridge** | Alpine | 70 | 6,345 | Six par 3s and the biggest climbs and drops in the game; side-hill fairways, lakes |

Each course sits on a **terrain**, which changes two things about how a
shot plays and how the hole is painted. The rules — lies, penalties, the
Form deck — are the same everywhere.

| Terrain | Run-out after landing | Wind (median) | Painted as |
|---|---|---|---|
| Parkland | 1.0x | about 11 mph | Woodland, broadleaf trees |
| Links | 1.5x — firm, the ball runs | about 17 mph | Fescue and dunes, gorse, no trees |
| Desert | 1.3x | about 6 mph | Sand and red rock, cactus, pale bunkers |
| Alpine | 0.8x — soft, the ball holds | about 13 mph | Pine forest, rock, snow |

Both are known before you swing, like everything else in the long game:
firmness is already in every run-out, and the wind is drawn per hole
as before, just from that terrain's range (and, on any terrain, getting up
as the round goes on). The title screen says what the
selected course's terrain does. The whole table is `THEMES` in
`scripts/CourseTheme.gd` — add an entry there, and its id to `ORDER`, and
it appears in the editor's picker.

A shipped course is a course file in exactly the format the editor saves:
`assets/courses/<id>.json`, listed in `CourseLibrary.FILES`. To ship a
course you built, copy its file from `user://courses/` into that folder
and add its name to the list; `CourseTest` then checks every hole of it.

To look at a whole course at once (a PNG per course, written to
`user://sheets` or `SHEET_OUT`):

```bash
godot --path . res://tools/CourseSheet.tscn
SHEET_COURSE=mirage-mesa SHEET_HOLES=1-6 godot --path . res://tools/CourseSheet.tscn
```

## Custom courses

**Course editor** on the title screen builds courses of 1-18 holes. Pick
the course's terrain beside its name, then drag
the fairway points, width tabs, green, bunkers and water corners on the
hole map; set par, green size and tilt, and elevation in the side panel.
A few points are enough: the fairway is drawn as one curve through its
points and a shoreline as one curve through its corners, and the ground in
play (the white stakes) reshapes itself round whatever you draw. Water
corners can be dragged out past the stakes, for a burn or a coast that
runs off the map. Elevation is set along the line of play; either side of
it the ground follows the lie of the land, so the contour lines on the map
bend across the hole rather than running straight.
**Open** offers a copy of each of the game's own courses to start from.
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

- Full **18-hole round** with a printed-style scorecard across the header
  (rings round birdies, boxes round bogeys) and an end-of-round summary
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
- **A ball you can watch**: it swells as it climbs and shrinks as it drops,
  skips when it pitches on turf, throws up sand from a bunker and a splash
  from water, and a putt rolls to the hole and drops into it — each with
  its sound at the moment it happens
- Click-to-aim on a drawn hole map with yardage-book carry arcs for the
  club in hand; where the ball finishes is left to your read
- Terrain (fairway / rough / bunker / water / **out of bounds**) with distance
  caps, penalties, and hazard-driven Form deck decay
- **Four courses on four terrains** — parkland, links, desert and alpine —
  each with its own firmness, wind and painted look (see "Courses")
- **Hole-outs from any distance**, gated on a d20
- Distance-scaled **putting timing meter** with gimmes
- **Restart** from the header at any point (arms then confirms mid-round)
- **Computer golfers** — three of them, by skill, for a round against the
  machine: the same rules, their own bag, draft and Form deck
- A **stamp on the hole map** for every finished hole (Birdie, Par, Double
  Bogey…), a call-out for three under-par holes running, and a moment
  when the last Bogey-Mart club leaves the bag

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
  (currently 1 in 3), and `ROUGH_DECAY_CHANCE` beside it for the rough (1 in 5).
  A range session removes `RANGE_SESSION_PURGE` (2).
- **What builds through a round** — the ramp is `Course.late()`; how much
  the wind gets up is `LATE_LIFT` in `scripts/Wind.gd`; how far out the pins
  go, and how often to the guarded side, are the constants at the top of
  `scripts/Pins.gd`.
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
- **Computer golfers** — `SKILLS` in `scripts/Rivals.gd`: each golfer's aim
  misjudgement and putt timing error, and the score they typically shoot.
  Re-measure with `BotSim` after changing them
  (`BOTSIM_VARIANT="aim=13,putt=185"`). How long they pause before each
  action is `CPU_BEAT` in `Main.gd`.
- **Hole layouts** — the `HOLES` centreline table in `HoleData.gd` (line ~104).
