# Boogie — Game Design Document (Working Title)

A mid-weight golf deckbuilder. 60-90 min per round. Solo vs. par or head-to-head.

## 1. High Concept

You play a round of golf by building a permanent, ever-growing hand (up to 14
cards) — one card at a time, at the end of each hole. Shots are resolved with
an aim-and-roll system: you declare your aim on the course board, then roll
to determine distance and a degree-of-deviation offset from that aim,
physically placed with a pivoting distance/angle tool. Hazards can add bad
cards to your hand; putting is a separate push-your-luck mini-game. Play solo
against par, or against friends.

## 2. Core Loop (Per Hole)

Each course is a fixed physical board/mat — all 18 holes are printed in place
with their yardage, par, hazard zones, and slope markers already visible.
There's no random hole draw; you always know the course, and can learn it
and develop strategy for it over repeat plays. Randomness lives in the dice,
weather, and card draws, not the hole layout.

1. Move to the next hole on the course board (yardage, par, hazards, slope,
   and pin position are all pre-printed and already known).
2. Choose a club from your current hand to play the shot.
3. Roll Power die + Accuracy die — modified by the club's own accuracy
   rating and current lie.
4. Resolve position — fairway, rough, bunker, water, green.
5. Repeat steps 2-4 until on the green.
6. Putt — switch to the Green Deck push-your-luck mini-game.
7. Score the hole.
8. End-of-hole draft: draw 3 cards from the shared club deck, look at all 3,
   pick 1 to add permanently to your hand (see Section 3). If your hand is
   at the 14-card cap, discard a card from hand first to make room.
9. Move to the next hole.

## 3. The Hand (Collection-Building System)

- You start with 3 bog-standard cards: Driver, Putter, 7-Iron. These stay in
  your hand for the whole game — nothing is discarded unless forced by the
  cap.
- At the end of every hole, draw 3 cards from the shared club deck, look at
  all 3, and pick 1 to add permanently to your hand. The 2 you didn't pick
  go to a discard pile, which reshuffles into the club deck when it runs
  dry.
- Your hand caps at 14 cards (the real-club limit). Once full, you must
  discard a card from hand before drawing again — a genuine "what's earning
  its place in the bag" decision.
- You can play any card in your hand for a shot — old standards or something
  you picked up on a previous hole.
- Over an 18-hole round, this means up to 18 potential additions — you'll
  likely hit the 14-card cap somewhere on the back nine, adding escalating
  "what do I cut" tension as the round progresses.
- Limited edition cards are shuffled into the same shared club deck at lower
  odds. They follow the same club types (driver/iron/wedge/putter-
  equivalent) but have stronger stats or a bonus ability (e.g. ignore one
  lie penalty, reroll one die, extra distance in specific weather).
- No currency involved — this is the entire acquisition system. There is no
  separate flight-based market; drafting happens once per hole, at the end
  of it.

### Brand Loyalty (Set Bonuses)

Every club card in the shared deck (standards and limited editions alike)
belongs to one of 4-5 fictional brands, each with a distinct golf-equipment
archetype. Any card of that brand in your hand counts toward its total,
regardless of club type — a Driver, an Iron, and a Putter from the same
brand all stack together. This gives the end-of-hole draft a second axis of
tension beyond raw stats: take the better card, or the on-brand card that
pushes you toward a threshold?

- Thresholds: **3 / 5 / 7** cards of one brand in hand, each unlocking a
  stronger tier of that brand's passive bonus (tiers are cumulative — hitting
  7 keeps 3 and 5's effects active too).
- Because thresholds are counted from cards *currently in hand*, discarding a
  brand card to make room at the 14-card cap can drop you back below a
  threshold and switch a bonus off — late-round discard decisions now also
  have to weigh "am I about to break my own set."
- You can pursue more than one brand at once, but 14 hand slots and ~18 total
  draft picks over a round mean going deep on one brand's 7-tier generally
  means abandoning a second brand's progress — a real commitment, not a
  freebie.
- Each brand plays a different real-world equipment archetype so no two
  brands compete for the same "best" slot:

| Brand archetype | Identity | 3 | 5 | 7 |
|---|---|---|---|---|
| **Forgiveness / Game-Improvement** | Wide margins, punishes less | Sweet Spot +1 width on all brand clubs | + Rough no longer shrinks Sweet Spot width (distance cap and Accuracy shift still apply) | + Bunker penalties treated as Rough instead of Bunker |
| **Tour / Players** | Raw power, low forgiveness | +1 to the Power roll's effective distance tier on brand clubs (e.g. Mid-range reads as Full swing) | + Extreme Finesse floor removed penalty (treat as Finesse instead of -4) | + Once per hole, treat an overshoot as landing inside the zone instead of shrinking Accuracy's Sweet Spot |
| **Precision** | Tight dispersion, no distance help | Accuracy roll's degree-offset bands shift one tier better (e.g. OFF reads as GOOD) on brand clubs | + PERFECT band widens by 1° on brand clubs | + Once per hole, choose Draw or Fade side outright instead of rolling |
| **Value / Classic** | Flexible utility, no sharp edges | Brand clubs ignore one full lie-penalty step (rough plays as fairway once per hole) | + Once per flight, a self-consuming bad card (see Section 5) discards without triggering its effect | + Once per round, swap one hand card for any card in the discard pile |

Brand identity is meant to echo Section 10's expansion structure long-term —
a new course expansion could introduce a new brand alongside its new club
cards, giving each expansion its own signature loyalty archetype.

### Starting Hand (baseline, tune in playtesting)

| Club | Yardage Band | Accuracy Die |
|---|---|---|
| Driver | Long (200-260) | d8 (least accurate) |
| 7-Iron | Medium (100-180) | d6 |
| Putter | Green only | — (Green Deck) |

Smaller accuracy die = tighter deviation = more reliable. Lies (rough,
bunker) step the die down one size.

## 4. Shot Resolution — Aim & Roll System

Every shot uses two d20 rolls — Power and Accuracy — read against a Sweet
Spot target that's the same shape for every club (centered on 10-11), but
whose width changes based on the club and the situation. A physical aim
tool (a pivoting arm with distance and degree markings, like a
protractor-ruler) converts the rolls into where the ball actually ends up on
the printed course board.

### Sweet Spot width

Base width by club type:

- Driver / Woods: narrow (4) — high risk/reward
- Mid-Irons: medium (6) — reliable workhorse
- Wedges: wide (8) — very forgiving

**Swing tier modifier** — where your target distance falls within the
club's own yardage band changes the width further. A full, committed swing
(near the top of the club's range) is more repeatable than a delicate
finesse shot (near the bottom):

| Tier | Modifier |
|---|---|
| Top third of band (full swing) | +2 |
| Middle third | +0 |
| Bottom third (finesse) | -2 |
| Below the club's minimum (Extreme Finesse) | -4, floor of 1 — technically legal, essentially a Hail Mary |

Example — full spread across club types and tiers:

| Club type | Full swing (top 1/3) | Mid-range (mid 1/3) | Finesse (bottom 1/3) | Extreme Finesse (below min) |
|---|---|---|---|---|
| Driver | 6 | 4 | 2 | 1 |
| Mid-Iron | 8 | 6 | 4 | 2 |
| Wedge | 10 | 8 | 6 | 4 |

Every Sweet Spot is centered on 10-11, but split asymmetrically — roughly
60% of the width extends downward (undershoot side) and 40% extends upward
(overshoot side). This bakes in a real-golf truth: overswinging costs you
control more than easing off does.

### Power roll (distance)

- Roll d20 against the club's Sweet Spot (as sized above).
- Inside the zone: clean strike, close to the club's max yardage for this
  shot.
- Below the zone (undershoot): safe miss — ball lands short, scaling down
  toward the club's minimum. No further penalty.
- Above the zone (overshoot): ball carries past the target — and this
  shot's Accuracy roll gets its Sweet Spot shrunk further, since swinging
  too hard is exactly when a shot goes wild. This is the costlier miss.

### Accuracy roll (direction — draw/fade)

- Roll d20 against the same Sweet Spot shape (its own width, per the table
  above; further shrunk if the Power roll overshot).
- Low side of center = Draw (curves left); high side of center = Fade
  (curves right). Distance from center = severity.

| Zone | Degree offset from aim |
|---|---|
| PERFECT (dead center) | 0-2° |
| GOOD | 3-8° |
| OFF | 9-20° |
| MISS | 21-40° |

### The Aim Tool

1. Declare aim: before rolling, place the tool's pivot on your ball's
   current position and point its 0° line wherever you're aiming (usually
   the pin, but can be a deliberate layup line to avoid a hazard).
2. Roll Power → extend the tool to the resulting distance.
3. Roll Accuracy → rotate the tool to the resulting degree offset (left for
   Draw, right for Fade).
4. Place your token at the end of the arm. Read the printed course art at
   that exact spot for terrain (fairway/rough/bunker/water) — this is a
   real, physical placement, not a lookup table, and naturally handles
   doglegs since the player chooses their own aim line each shot rather
   than following a fixed track.

## 5. Terrain Modifiers

| Terrain | Sweet Spot width | Power roll / distance cap | Accuracy (degree offset) | Other effects |
|---|---|---|---|---|
| Tee | Full (base width for club/tier) | Normal | Normal | No restrictions — every club playable |
| Fairway | Full (base width) | Normal | Normal | Baseline — no modifiers |
| Rough | -1 width | Capped at ~80% of club's max yardage | Shifts one tier worse (e.g. GOOD reads as OFF) | None else |
| Bunker | -2 width | Capped at ~50% of club's max yardage | Shifts one tier worse | Driver/Fairway Woods unplayable — irons/wedges only |
| Water | — | — | — | Not a lie you play from — a resolution outcome. +1 penalty stroke, ball placed back at nearest fairway/rough point at roughly the same distance as before the shot |
| Green | N/A | N/A | N/A | Switches entirely to the Green Deck putting mini-game |

Rough and Bunker both stack multiple penalties at once (shrunk Sweet Spot +
worse Accuracy tier + distance cap) — this is a deliberate "hazards should
feel bad" design, but since rough is by far the most common hazard over a
full round, playtest specifically for whether rough ends up too
consistently punishing before locking these numbers in.

### Weather (drawn once per flight — see Section 6 — so it shifts partway through the round, e.g. front 9 / back 9)

- Wind: adds a further degree-offset bias to the Accuracy roll (pushes the
  aim tool's placement in the wind's direction).
- Rain: reduces the Power roll's effective distance (ball doesn't run after
  landing).
- Dry/Sun: extends the Power roll's effective distance (ball runs further
  after landing).

### Slope

Printed on the course board at specific points; shifts the ball's final
resting position or adjusts the next shot's roll when the token lands on a
marked slope zone.

### Bad cards

Landing in a hazard (rough, bunker, water) carries a chance of a bad card
being added directly into your hand — punishment enters via the hand, same
as upgrades do through the end-of-hole draft. Bad cards count toward your
14-card cap the moment they're added.

Bad cards are **self-consuming**: the next time you play a shot, the bad
card in your hand triggers its penalty, then discards itself immediately
afterward (face-up, into the same discard pile the club draft uses). You
don't choose whether to play a bad card — if one's in your hand when you're
about to take a shot, it applies automatically before you pick your club,
representing a swing thought or a rattled nerve rather than a piece of
equipment. This means a bad card is never a long-term hand-slot tax — its
cost is one bad shot, not a standing occupant of your 14-card cap — but it
can still cost you the shot that matters (e.g. triggering right as you're
lining up an approach into the green).

| Bad card | Trigger effect |
|---|---|
| **Yips** | Your next Accuracy roll's Sweet Spot shrinks by 2 width, on top of any other modifiers. |
| **Shank** | Your next shot's Accuracy roll auto-reads as OFF, regardless of the roll (Power roll still applies normally). |
| **Lost Ball** | Your next shot immediately costs +1 penalty stroke on top of its normal resolution — the shot still happens, but you're playing 3 off the tee, so to speak. |
| **Duffed** | Your next Power roll is treated as landing in Extreme Finesse tier regardless of the actual roll — a heavily mishit, short shot. |

- Draw odds: roughly 1 in 6 hazard landings adds a bad card (heavier in
  Bunker and Water than Rough, given rough's frequency — see Section 5's
  note on rough already being the most common hazard). Tune in playtesting.
- Because bad cards vanish after one shot, they don't interact with Brand
  Loyalty counts (Section 3) or the 14-card cap beyond the single hole where
  they're drawn — the sting is immediate, not systemic.

## 6. Weather (Per-Flight)

- Course is split into 3 flights of 6 holes (holes 1-6, 7-12, 13-18).
- Draw one weather card at the start of each flight — conditions shift
  front 9 / middle / back 9 rather than every hole, and stay fixed for that
  stretch.
- Card acquisition no longer happens at flight breaks — it's continuous
  now, via the end-of-hole club deck draw (see Section 3). Flight breaks
  are purely a weather-change beat.

## 7. Putting — The Green Deck (Push-Your-Luck)

- Separate small deck: numbered cards (1-6, representing distance covered)
  + Miss cards (lip-out, short, burn the edge).
- Distance-to-pin sets your target number.
- Draw cards one at a time, summing toward the target. Stop any time to
  bank your putt.
- Draw a Miss card before stopping → progress resets for that stroke
  (three-putt danger).
- Slope/weather bias the deck composition:
  - Uphill putt: more Miss cards (harder to judge weight).
  - Downhill putt: fewer big numbers, more Miss cards (fear of racing past
    the hole).
  - Wind/rain: further adjust the Miss ratio.

## 8. Scoring

Standard stroke-play scoring, tracked per hole against that hole's printed
par:

| Strokes vs. par | Name |
|---|---|
| -2 | Eagle |
| -1 | Birdie |
| 0 | Par |
| +1 | Bogey |
| +2 | Double Bogey |
| +3 or worse | Triple Bogey (and so on) |

- Every stroke counts, including penalty strokes (water — see Section 5 —
  and any bad-card effects that add a stroke).
- A scorecard tracks per-hole strokes and a running total vs. par across all
  18 holes (e.g. "-3" after the front nine). No separate points system —
  this is the entire scoring model, deliberately unabstracted so it reads
  exactly like a real round.
- In Solo vs. Par, your final score is that running total. In Multiplayer,
  lowest total (most under, or least over, par) wins — standard stroke
  play, not match play, to keep the shared club-deck draft (Section 3)
  meaningful for everyone through hole 18 rather than ending the contest
  early on some holes.

## 9. Modes

- **Solo vs. Par**: track strokes against course par, no opponents needed.
  Clean, works as-is.
- **Multiplayer**: simultaneous card selection — everyone secretly picks
  their club, reveal together, resolve shots in "furthest from pin plays
  first" order (mirrors real golf etiquette, minimizes downtime).

## 10. Course & Expansion Structure

- **Base game**: 1 full 18-hole course as a printed physical board/mat (all
  holes, yardages, hazard zones, and slope markers fixed in place), plus
  base weather deck, base hazard/bad-card set, and the shared club deck
  (standards + limited editions).

### The Base Course — "Boogie Links" (working title)

An original links-style routing (evokes Scottish/Irish coastal courses —
no real course or trademarked name used). Firm, fast, mostly treeless,
coastline running along one edge of the board so wind is a constant
presence — pairs directly with Section 5's Wind/Dry weather rules ("ball
runs further," wind bias on Accuracy) and gives Slope markers a reason to
exist on nearly every hole. Deep pot bunkers over the softer, wider Rough
of a parkland course, per the terrain table in Section 5.

Routing goal: every terrain type, every club's yardage band, and at least
one hole that rewards each Brand Loyalty archetype (Section 3) shows up
across the 18 — so the base course itself teaches the systems rather than
leaving that to the rules text alone.

| Hole | Par | Yardage | Identity / design intent |
|---|---|---|---|
| 1 | 4 | 380 | Straightaway opener, generous fairway, single pot bunker short-right — a calm on-ramp before the round gets teeth. |
| 2 | 3 | 165 | Coastal par 3, green guarded left by a deep pot bunker — tests Precision-brand Accuracy play. |
| 3 | 5 | 540 | Dogleg-left par 5 along the coastline — rewards the Aim Tool's free-aim layup line to bite off as much of the dogleg as the player dares. |
| 4 | 4 | 410 | Into-the-wind hole (prevailing wind bias strongest here) — tests Tour/Players' distance-tier bonus against a stiff headwind. |
| 5 | 3 | 195 | Long par 3 over a waste/rough carry — no bunker, but undershoot lands in punishing Rough; a Forgiveness-brand showcase hole. |
| 6 | 4 | 365 | Short, sharp dogleg-right around a bunker cluster at the corner — risk/reward tee shot (cut the corner vs. lay up short). |
| 7 | 4 | 425 | Longest par 4 on the front nine, fairway pinched by rough both sides — a "hit the number, not just the direction" test hole. |
| 8 | 5 | 510 | Reachable-in-two par 5 for a big Tour/Players drive, but green is water-guarded — high risk/reward closer to the front nine's turn. |
| 9 | 4 | 395 | Uphill finish to the front nine, slope marker kicks approach shots toward a back-shelf green — first real Slope showcase hole. |
| 10 | 4 | 375 | Back nine opener, downwind — mirror of hole 1's calm energy but with a tailwind distance boost. |
| 11 | 3 | 145 | Short, exposed par 3 right on the coastline — heaviest wind bias on the course, small green. |
| 12 | 5 | 560 | Longest hole on the course, three-shot par 5 threading between two bunker clusters — a genuine "what's your bag missing" test. |
| 13 | 4 | 400 | Crosswind hole, fairway slopes toward rough on the low side — Slope + Wind stacking. |
| 14 | 4 | 355 | Short par 4, driveable for a full-send Tour/Players tee shot, but the green is tiny and bunker-ringed — classic risk/reward. |
| 15 | 3 | 175 | Elevated tee to a well-bunkered green — Value/Classic's lie-penalty forgiveness matters if you miss into rough short. |
| 16 | 4 | 415 | Into the prevailing wind again, tightest fairway on the course — the round's most demanding ballstriking hole. |
| 17 | 3 | 155 | Island-style green surrounded by water on three sides — the course's signature hole, a genuine card-in-hand gamble late in the round. |
| 18 | 5 | 545 | Closing par 5 along the coastline back to the clubhouse, wide fairway but a water hazard guards the green in two — a "how much do you need this birdie" decision to close the round. |

Front nine par: 36. Back nine par: 36. **Course par: 72.**

This layout is a first draft for paper-prototyping — exact yardages, bunker
placement, and slope zones should flex once Section 11's die-to-outcome
mapping is locked, since a Sweet Spot that plays too generous or too narrow
will make specific holes above trivial or unfair.
- **Expansions**: new course boards/mats, each introducing:
  - A distinct fixed 18-hole layout with its own identity (signature holes,
    hazard placement, par).
  - New club cards (standard and limited edition) for the shared club deck.
  - New hazard types or bad cards.
  - New weather conditions.
  - Possibly new putting-green rules (e.g., wildly sloped greens on a
    links-style expansion course).

## 11. Design Priorities to Nail First (before anything else)

These three numbers are the game's feel — everything else is dressing:

1. Yardage bands + accuracy die sizes per club.
2. Power/Accuracy die-to-outcome mapping (how a roll translates to
   fairway/rough/bunker/etc.).
3. Green Deck number-to-Miss ratio, and how much slope/weather shifts it.

Prototyping order: paper-prototype hole 1 with dice and index cards →
validate shot resolution is fun → build the digital prototype in Godot →
expand to full 18 holes, drafting, and hazards once the core loop feels
good.

## 12. Digital Prototype — Build Plan (Godot)

Suggested build order, each stage playable before moving to the next:

1. Single hole, single player: hole tile, hand of 3 starting clubs, dice
   roll resolution, distance-to-pin tracking.
2. Add lies & hazards: rough/bunker/water zones affecting die size and
   Power cap.
3. Add the Green Deck putting mini-game.
4. Full 18 holes + scoring vs. par (solo mode complete).
5. Add the end-of-hole draw-3-pick-1 mechanic (shared club deck, permanent
   growing hand, 14-card cap, forced discard when full).
6. Add limited edition cards into the shared club deck at lower odds.
7. Add weather conditions (modifiers to dice and Green Deck).
8. Add local multiplayer (simultaneous selection, turn order by distance).

## Open Questions / To Decide in Playtesting

- Exact odds of limited edition cards appearing in the shared club deck.
- Exact hazard-to-bad-card odds (Section 5 estimates ~1 in 6, weighted
  toward Bunker/Water) and whether the four bad card effects are punishing
  enough to matter without feeling unfair given they trigger on your very
  next shot with no way to play around them.
- How aggressive slope/weather modifiers should be — enough to matter, not
  enough to dominate.
- Whether a 14-card cap feels right in this system (it was tuned for the
  old cycling-deck version) — may need retesting now that the hand never
  resets.
- In multiplayer, whether the shared club deck creates awkward "sniping"
  (another player takes the card you wanted) and whether that's good
  tension or needs softening.
- Whether 3/5/7 is the right Brand Loyalty threshold given 4-5 brands, a
  14-card cap, and ~18 total draft picks — may need more brand-card density
  in the shared deck to make 7 realistically reachable, and the four
  archetype bonuses need head-to-head playtesting so none reads as
  strictly best.
