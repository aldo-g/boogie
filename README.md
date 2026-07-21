# Boogie

A golf-themed card/dice board game — currently being prototyped digitally in
Godot 4 to test whether the core mechanics are fun before committing to
physical production. Working title "Boogie."

## Concept

Play a round of golf across a **fixed, printed 18-hole course** (like a real
course layout — no random hole generation). Progress down each hole using
club cards and dice, then finish with a push-your-luck putting mini-game.
Solo mode plays against par; multiplayer plays head-to-head.

## Core mechanics

**The hand (deckbuilding-adjacent, but non-standard)**
- Start with 3 cards: Driver, 7-Iron, Putter.
- Before every single shot, draw 3 cards from a shared club deck, look at
  all 3, and permanently add 1 to your hand.
- Hand caps at 14 cards (a real club limit). Once full, discard a card
  before drawing again.
- Any card in hand can be played for a shot, old or new.
- No currency, no shop — the draw-3-pick-1 step is the entire acquisition
  system.
- Limited edition cards are mixed into the same shared deck at lower odds —
  same club types, better stats or a bonus ability.

**Shot resolution**
- Each club has a yardage band (min–max) and an Accuracy die (d4–d12;
  smaller = more accurate).
- A power roll determines distance traveled within the club's yardage band.
- An accuracy roll (on the club's die) determines the resulting lie:
  fairway, rough, bunker, or water.
- Bad lies step the accuracy die down for the *next* shot (rough/bunker).
- Bunkers also cap how far you can hit out.
- Water = stroke penalty + drop.
- Hazards have a chance to add a "bad card" (e.g. Shank) directly into your
  hand — punishment enters via the hand, same as upgrades do.

**Putting — the Green Deck (push-your-luck)**
- A separate, small deck: numbered cards (1–6) + Miss cards.
- Distance-to-pin sets a target number.
- Draw cards one at a time, summing toward the target; bank (stop) anytime.
- Drawing a Miss card before banking resets progress for that stroke.
- Slope/weather bias the deck's number/Miss ratio (not yet built digitally).

**Course structure**
- The course is a fixed physical board/mat — all 18 holes printed with
  yardage, par, hazard zones, and slope already visible.
- The course is split into 3 flights of 6 holes; weather is drawn once per
  flight (front 9 / mid / back 9 conditions), not per hole.
- Base game = 1 course. Expansions = new course boards, each with new club
  cards, hazards, weather, and possibly new green rules.

## Repo layout

```
Boogie/
├── project.godot     Godot project config
├── assets/
│   └── maps/
│       └── llanfair-course.jpeg   Reference course layout (18 holes)
├── scenes/
│   └── Main.tscn     Single scene: a Control node + script, no editor wiring
└── scripts/
    └── Main.gd        All game logic and UI construction
```

The prototype's entire UI is built in code by `scripts/Main.gd` — there's
nothing to wire up in the scene editor.

## Running the prototype

1. Install [Godot 4.x](https://godotengine.org) (standard/non-.NET build,
   unless you specifically want C#).
2. Open Godot, click **Import**, and select `project.godot` in this repo.
3. Press **Play** (▶ top-right, or Cmd+B on macOS / F5 on Windows/Linux).
   It runs `scenes/Main.tscn` automatically.

## What's implemented in the prototype

- Starting hand: Driver, 7-Iron, Putter
- Draw-3-pick-1 before every shot (14-card cap, forced discard when full)
- Limited edition cards mixed into the same deck at lower odds
- Power + Accuracy dice, with the accuracy die stepped down in rough/bunker
- Water (stroke penalty) and bunker (capped power) hazards, with a chance
  of picking up a "Shank" bad card into your hand
- Green Deck push-your-luck putting: draw and sum toward a target, bank
  anytime, Miss cards reset progress for that stroke
- Single hole only, solo, vs. par

## What's deliberately not in this version

- Full 18 holes / course board
- Weather (per-flight conditions)
- Multiplayer (simultaneous selection, turn order)
- Slope
- Any real visual board — this is pure UI/logic to test the *numbers*

## Numbers worth tuning after a few playthroughs

All of these live in `scripts/Main.gd` and are deliberately easy to find:

- `hole_yardage` / `hole_par` (top of the script)
- Club yardage bands and accuracy dice in `build_club_pool()`
- Hazard odds in `resolve_lie()` (currently: 15% hazard, next 25% rough,
  rest fairway)
- Bad card odds in `play_shot()` (currently 40% chance on any hazard)
- Green Deck number/miss ratio in `build_green_deck()`
- `GREEN_THRESHOLD` (yards remaining that triggers putting — currently 20)

Play it a handful of times, see if the shot resolution and putting both feel
tense in the right way, then tune these before building out the full
18-hole board.
