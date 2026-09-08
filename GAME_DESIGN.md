# Boogie — Game Design Document (Working Title)

*A mid-weight golf deckbuilder. 60-90 min per round. Solo vs. par or head-to-head. Video game (Steam target), built as a card-resolution deckbuilder in the spirit of Slay the Spire — no dice, and no timing checks anywhere in the tee-to-green game. Putting is the deliberate exception: it's a timing meter whose difficulty scales with distance (Section 7).*

---

## 1. High Concept

You play a round of golf by building a permanent, ever-growing hand of clubs (your **Bag**, up to 14 cards) — one card at a time, at the end of each hole. Every shot is resolved by drawing from a separate **Form** hand (representing your current swing state — good and bad), reading its fully known effect, and aiming to compensate or exploit it. Nothing is hidden or randomly rolled once a card is drawn — luck lives in the draw, skill lives in reading it and adjusting your aim. Hazards degrade your Form deck; putting switches to a distance-scaled timing meter. Play solo against par, or against friends.

---

## 2. Core Loop (Per Hole)

Each course is a **fixed, designed layout** — all 18 holes have known yardage, par, hazard placement, and pin position. There's no random hole generation; you always know the course, and can learn it and develop strategy for it over repeat plays. Randomness lives in the Form draw and weather, not the hole layout itself.

1. **Move to the next hole** (yardage, par, hazards, and pin position are all known upfront).
2. **Declare your shot**: choose a club from your Bag and your target (usually the pin, but can be a deliberate layup). This sets your swing tier for that club (see Section 4).
3. **Draw 3 Form cards**, look at all 3, pick 1 to pair with your shot.
4. **Read the Form card's known effect**, then make your **final aim adjustment** to compensate or exploit it.
5. **Resolve deterministically** — fairway, rough, bunker, water, or green.
6. **Repeat** steps 2-5 until on the green.
7. **Putt** — switch to the putting meter, a timing check that gets harder the further you are from the hole.
8. **Score the hole.**
9. **End-of-hole draft**: draw 3 cards from the shared club deck, look at all 3, pick 1 to add permanently to your Bag. If your Bag is at the 14-card cap, discard a card first to make room.
10. Move to the next hole.

---

## 3. The Bag (Collection-Building System)

- You start with 3 bog-standard cards: **Driver, Putter, 7-Iron**. These stay in your Bag for the whole round — nothing is discarded unless forced by the cap.
- **At the end of every hole**, draw 3 cards from the shared club deck, look at all 3, and pick 1 to add permanently to your Bag. The 2 you didn't pick go to a discard pile, which reshuffles into the club deck when it runs dry.
- Your Bag caps at **14 cards** (the real-club limit). Once full, you must discard a card before drawing again — a genuine "what's earning its place in the bag" decision.
- You can play **any** card in your Bag for a shot — old standards or something you picked up on a previous hole.
- Over an 18-hole round, this means up to 18 potential additions — you'll likely hit the 14-card cap somewhere on the back nine, adding escalating "what do I cut" tension as the round progresses.
- **Limited edition cards** are shuffled into the same shared club deck at lower odds. They follow the same club categories (Wood/Iron/Wedge/Putter) but have stronger yardage bands and a bonus ability tied to the Form Card System (see Section 4).
- No currency involved — this is the entire acquisition system. Drafting happens once per hole, at the end of it.

### Starting Bag (baseline, tune in playtesting)
| Club | Category | Yardage Band |
|---|---|---|
| Driver | Wood | Long (200-260) |
| 7-Iron | Iron | Medium (100-180) |
| Putter | Putter | Green only |

---

## 4. Shot Resolution — The Form Card System

Every shot from tee to green is resolved by reading a fully known Form card and aiming around it — no hidden probability, no dice, no timing check (putting is the one exception; see Section 7). Luck lives in what you draw; skill lives in reading it correctly and adjusting your aim.

### The two-hand split

- **The Bag**: your 14-card hand of clubs (Section 3) — permanent, grows via the end-of-hole draft, determines available distances.
- **Form**: a separate, small hand representing your current swing state, not your equipment. This is where Hook, Slice, Top, and the Yips live — they were never really clubs, they're modifiers on how you're striking the ball *today*.

### Shot flow

1. **Declare your shot**: choose a club and your target (usually the pin, but can be a deliberate layup short of a hazard). This is your intended distance and general line — and it's what determines your **swing tier** for that club (full swing vs. mid-range vs. finesse vs. extreme finesse), which sets your draw bias (see below).
2. **Draw 3 Form cards** from the Form deck (biased by swing tier + terrain), look at all 3, pick 1 to pair with your shot. The other 2 go to the Form discard pile (reshuffled in when the deck runs dry).
3. **Read the Form card's exact, known effect** (e.g. "Hook: pulls 15° left, -10% distance") — nothing is hidden or rolled.
4. **Final aim adjustment**: now that the deviation is fully known, fine-tune your aim to compensate or exploit it (or lean into a good card, like using Controlled Draw to shape around a dogleg). This is the entire skill expression for the long game — no timing input, no hidden roll, just correctly reading known information and adjusting your line.
5. **Resolve deterministically** — the outcome follows directly from club + target + Form card + final aim; no further randomness.

This mirrors how a shot actually feels: you commit to a club and general shot shape first (the strategic decision), then make a last-second correction once you know what's actually happening with your swing — represented here by seeing your Form card, rather than a physical feel.

### Club suitability — swing tier changes how many cards you draw

Where your target distance falls within a club's own yardage band changes how many Form cards you get to choose from — as a bell curve, not a straight line. A smooth mid-range swing is the most repeatable motion; both swinging all-out for max distance and easing off for a delicate touch shot are more likely to go wrong than a comfortable middle-of-the-bag swing. The Form deck itself is never biased — every draw pulls at the same, plain odds. Risk instead comes from how much choice you get: fewer cards to pick from means less room to dodge a bad one.

| Swing tier | Cards drawn | Why |
|---|---|---|
| Mid-range | **3** — best choice | The most repeatable, comfortable swing |
| Full swing (top third of the club's yardage band) | **2** | Swinging for max distance risks a mishit — less room to dodge a bad card |
| Finesse (bottom third) | **2** | A delicate touch shot risks a mishit — less room to dodge a bad card |
| **Extreme Finesse (below the club's minimum)** | **1**, and it isn't drawn from the deck at all | The club creates a fresh bad Form card on the spot (the same Created-card mechanism as Section 4's Pure Strike/Big Strike, just bad instead of good) and hands it to you directly — no pick, no choice, you must play it |

This creates two distinct levers working together — swing tier affects how much *choice* you get among the draw, club category affects how *severe* whatever you end up playing is once it lands (see Club buffering below). Forcing a big club into a delicate touch shot is doubly risky: fewer cards to choose from, *and* whatever you're stuck with hits at full severity. A Wedge forced into the same situation is only mildly worse off. This also makes saved Created cards (Pure Strike, Big Strike) genuinely valuable bail-outs for exactly the moments a player's Bag shouldn't really be attempting.

### Club buffering

Clubs modulate how strongly a Form card's effect applies: a forgiving Wedge might halve a Hook's deviation, while a Driver applies it at full severity. This keeps club choice meaningful — a Driver is riskier specifically because it doesn't protect you from bad Form.

### Bad Form cards

| Card | Effect |
|---|---|
| Hook | Pulls shot left by a known degree, slight distance loss |
| Slice | Pushes shot right by a known degree, slight distance loss |
| Top | Ball stays low, big distance loss, no directional change |
| Chunk/Fat | Hits ground first, major distance loss |
| Shank | Severe direction error + downgrades your lie |
| The Yips | Only triggers on the green — see Putting cross-trigger below |

### Good Form cards

| Card | Effect |
|---|---|
| Pure Strike | Full accurate distance, zero deviation — the reliable baseline |
| Stinger | Low, controlled flight — cuts through wind, minimal deviation, slightly reduced distance |
| Controlled Draw | Deliberate leftward curve, usable tactically around a left-side dogleg/hazard |
| Controlled Fade | Same idea, rightward |
| Flop Shot | High, soft landing — ignores rough/bunker penalty entirely, minimal roll |
| Bump and Run | Low running shot — extra roll distance, especially strong in dry weather |
| Steady Hands | Widens the sunk band on your next putt, as if the putt were a short one |
| In the Zone | Cancel any one bad Form card in your hand without playing it |

### Form deck composition & hazards

- Starts weighted toward good cards (~65% good / 35% bad) so early holes feel encouraging.
- Every hazard hit adds bad Form cards into the **Form deck** (not directly into your Bag) — this degrades the quality of future draws for the rest of the round rather than permanently cluttering your Bag. A rough patch of holes genuinely makes your swing worse as the round goes on.
- A "range session" action (costs a turn, or usable between holes) purges bad cards from the Form deck.

### Created cards ("exhaust" resources, not draws)

To stop top-tier good cards (like Pure Strike) from being either "always in the pool, trivializing decisions" or "randomly lucky when drawn," they don't live in the natural Form deck at all. Instead, **club abilities generate them directly into your Form hand**, and once played they **exhaust** — removed from the game entirely, not discarded back into the cycle. This turns them into a genuine resource to manage (save it for the shot that really can't miss) rather than a lucky draw to hope for.

**Category-to-creation mapping** (also gives each Bag archetype a distinct identity):

| Category | Thematic role | What it creates | Trigger type |
|---|---|---|---|
| **Woods** | Power/burst | "Big Strike" — guarantees near-max distance, ignores deviation | **Active** — saved for a deliberate big moment (a carry over water, a reachable par-5) |
| **Irons** | Precision/control | "Pure Strike" — guarantees zero deviation, standard distance | **Active** — saved for a shot that really can't miss |
| **Wedges** | Finesse/recovery | "Flop Shot," or directly purges one bad card from your Form deck | **Passive** — triggers automatically when you're already in a hazard, rewarding correct club selection rather than activation timing |
| **Putter** | Green mastery | "Steady Hands" — widens the sunk band on your next putt | **Active** — saved for a genuinely must-make putt |

**The design principle**: Passive fits abilities that reward good *positional play* (reaching for the right club in a bad lie); Active fits abilities meant to be *saved for a clutch moment* (the timing decision itself is the interesting choice).

**Limited Edition club abilities:**

| Card | Ability | Trigger |
|---|---|---|
| Gold Cleek | Once per hole, create a Pure Strike card in your Form hand | Active |
| Tour Driver X ("The Bulger") | Create a Big Strike card whenever you play a Wood from rough/bunker | Active |
| The Rutter | Automatically purges one bad Form card whenever you're in a hazard | Passive |
| Old Tom's Niblick | Creates a Flop Shot card whenever you land in a bunker | Passive |
| Old Reliable Putter | Once per round, you may create a Steady Hands card | Active |

### Putting cross-trigger (the Yips)

The Yips card can be drawn in your Form hand approaching the green. You can avoid playing it (pick one of the other 2 draws), but if you're forced to play it, it taints your *next* putt specifically — that putt misses regardless of how well you actually strike it on the meter. This keeps the Yips doing what it's known for: a mental carryover into putting, not just another distance modifier.

### Worked example

140 yards to pin, fairway lie. **You declare your shot**: 7-Iron, aiming at the pin — this is a full swing for the 7-Iron's band, so your draw is biased toward better odds. Draw **Slice, Top, Hook** anyway — a bad hand despite the good tier. You pick **Slice** (least distance-punishing, known effect: pushes right by a set degree). **Final aim adjustment**: you aim left of the pin to compensate for the known rightward push. The outcome is still fully deterministic — correct compensation lands you close to your actual target despite playing a "bad" card. That's the skill: committing to a sound shot plan, then reading an imperfect hand and adjusting your line around it, not hoping for good luck.

---

## 5. Terrain Modifiers

| Terrain | Effect on Form draw | Effect on distance | Other effects |
|---|---|---|---|
| **Tee** | Normal (swing tier still applies) | None — full aimed-for distance | No restrictions — every club playable |
| **Fairway** | Normal (swing tier still applies) | None — full aimed-for distance | No modifiers |
| **Rough** | Normal (swing tier still applies) | **-20%** — whatever distance you aimed for is multiplied by 0.8 | None else |
| **Bunker** | Forces the Extreme Finesse treatment regardless of swing tier: the club creates 1 fresh bad Form card on the spot, no draw, no choice, forced to play it | **-50%** — whatever distance you aimed for is multiplied by 0.5 | Driver/Fairway Woods unplayable — irons/wedges only |
| **Water** | — | — | Not a lie you play from — a resolution outcome. +1 penalty stroke, ball placed back at nearest fairway/rough point at roughly the same distance as before the shot |
| **Green** | N/A | N/A | Switches entirely to the putting meter (Section 7) |

The distance penalty applies to your actual aimed-for distance, not an abstract tier ceiling — aim for 200 yards from rough and the shot flies at 160 (before the Form card's own multiplier/bonus lands on top). A Flop Shot card ignores this penalty entirely (Section 4). Bunker already stacks two penalties at once (forced bad card + a steep distance cut, on top of Driver/Woods being unplayable there at all) — a deliberate "hazards should feel bad" design. Rough currently only affects distance, not card count; **playtest whether rough also needs its own Form-draw penalty** (e.g. dropping the card count by one tier-step) before locking these numbers in.

- **Slope**: marked at specific points on the course; shifts the ball's final resting position or adjusts the next shot's draw bias when you land on a marked slope zone.
- **Bad cards from hazards**: landing in rough, bunker, or water carries a chance of adding bad cards directly into the **Form deck** (not your Bag) — see Section 4, Form deck composition & hazards.

---

## 6. Weather (Per-Flight)

- Course is split into **3 flights** of 6 holes (holes 1-6, 7-12, 13-18).
- Draw one **weather card** at the start of each flight — conditions shift front 9 / middle / back 9 rather than every hole, and stay fixed for that stretch.
- Card acquisition doesn't happen at flight breaks — it's continuous via the end-of-hole club draft (Section 3). Flight breaks are purely a weather-change beat.
- **Weather effects on the Form system**:
  - Wind: biases the Form deck toward directional bad cards (Hook/Slice) matching the wind's direction, or adds a further known offset to whichever Form card you play.
  - Rain: reduces effective distance across the board (ball doesn't run after landing).
  - Dry/Sun: extends effective distance (ball runs further after landing).

---

## 7. Putting — The Putting Meter (Timing)

Putting is the one place in the game that asks for a timing input rather than a read. The long game is about *decisions under known information*; putting is about *nerve over a short one*, which is exactly how the real sport divides. Making the green feel different in kind from the fairway is the point — you stop calculating and start holding your breath.

**How it works**: a marker sweeps back and forth across a bar. Stop it (Space, or the Strike button) and where it lands decides the putt:

| Band | Result |
|---|---|
| **Sunk** (centre) | Holed out |
| **Close** (flanking) | Missed, but the ball finishes near the hole — a short one left |
| **Miss** (outside) | Pushed off line; how far it finishes depends on how wild the timing was |

**Distance drives difficulty** — the single lever that makes the mini-game a real decision. As distance to the pin grows, the sunk band narrows *and* the marker sweeps faster:

| Distance | Sunk band | Marker speed | Window on the band |
|---|---|---|---|
| 6 ft (tap-in) | 40% of the bar | 0.55 sweeps/sec | ~730 ms |
| 15 ft | 31% | 0.78 | ~400 ms |
| 12 yds | 23% | 0.97 | ~240 ms |
| 25 yds | 15% | 1.18 | ~120 ms |
| 30 yds+ | 12% (floor) | 1.25 (floor) | ~95 ms |

The curve is eased so difficulty ramps hardest over the first stretch — the step up from a 3-footer to a 12-footer bites more than the step from 25 to 34 yards, where it's already a lag putt either way. Both ends are **floored deliberately**: at maximum difficulty the marker is still inside the sunk band for roughly six frames at 60fps, so the hardest putt in the game is a demanding read rather than a coin flip the player can't actually hit.

**Why this shapes the long game**: because a putt's difficulty is set purely by where you land, approach play now has a real target rather than just "the green." Leaving yourself 25 yards on the green is meaningfully worse than leaving 10 feet — so laying up to a good distance, or reaching for the club that gets you close rather than merely on, becomes a live decision on the shot before.

**Termination**: every miss finishes at most as far out as it started, so a putting sequence always walks toward the hole. Inside ~2 feet the putt is **conceded as a gimme** — no drama left to play for, and it guarantees the loop can't grind forever on a short one. In practice a competent player averages 1.1-2.0 putts and even a badly struggling one tops out around 7.

**Still to build**: slope and weather should bias the meter — an uphill putt narrowing the sunk band, a downhill one biasing where "close" finishes past the hole.

---

## 8. Modes

- **Solo vs. Par**: track strokes against course par, no opponents needed. Clean, works as-is.
- **Multiplayer**: simultaneous shot declarations — everyone secretly picks their club/target, reveal together, resolve shots in "furthest from pin plays first" order (mirrors real golf etiquette, minimizes downtime).

---

## 9. Course & Expansion Structure

- **Base game**: 1 full 18-hole course with a fixed, designed layout (yardages, hazard placement, slope all fixed), plus base weather deck, base hazard/bad-card set, and the shared club deck (standards + limited editions).
- **Expansions**: new courses, each introducing:
  - A distinct fixed 18-hole layout with its own identity (signature holes, hazard placement, par).
  - New club cards (standard and limited edition) for the shared club deck.
  - New hazard types or bad cards.
  - New weather conditions.
  - Possibly new putting-green rules (e.g., wildly sloped greens on a links-style expansion course).

---

## 10. Design Priorities to Nail First (before anything else)

These are the game's actual feel — everything else is dressing:

1. **Full Form card list** (currently a first draft of 6 bad / 8 good) — needs expansion to a real deck-sized set.
2. **Swing-tier draw-bias percentages** — exact numbers for how much full swing vs. finesse shifts your odds.
3. **Created card sources and exhaust economy** — how often players should realistically have a Pure Strike/Big Strike available.
4. **Putting meter difficulty curve** — band widths and marker speed across the distance range, and how much slope/weather shifts them.

**Prototyping order**: build a single-hole digital prototype with the Form Card System end to end → validate the "read the hand, aim around it" loop is fun and legible → expand to full 18 holes, the Bag draft, and hazards once the core loop feels good.

---

## 11. Digital Prototype — Build Plan (Godot)

Suggested build order, each stage playable before moving to the next. **Note**: the existing prototype (`Main.gd`) was built against the earlier dice-based system and needs updating to match the Form Card System described in Section 4 before further work continues.

1. **Single hole, single player**: hole data, starting Bag of 3 clubs, Form draw-3-pick-1 resolution, distance-to-pin tracking.
2. **Add terrain**: rough/bunker/water zones affecting Form draw bias and distance caps.
3. **Add the putting meter mini-game.**
4. **Full 18 holes + scoring vs. par** (solo mode complete).
5. **Add the end-of-hole club draft** (shared club deck, permanent growing Bag, 14-card cap, forced discard when full).
6. **Add limited edition cards** into the shared club deck, including their Created-card abilities.
7. **Add weather conditions** (modifiers to Form draw bias and the putting meter).
8. **Add local multiplayer** (simultaneous shot declarations, turn order by distance).

---

## Open Questions / To Decide in Playtesting

- Exact odds of limited edition cards appearing in the shared club deck.
- How many bad cards enter the Form deck economy per hazard hit, and how fast it should degrade — needs playtesting to avoid a death spiral where one bad hole compounds into an unplayable back nine.
- How aggressive slope/weather modifiers should be — enough to matter, not enough to dominate.
- Whether a 14-card Bag cap feels right — untested since the system moved away from a cycling deck to a permanent growing hand.
- In multiplayer, whether the shared club deck creates awkward "sniping" (another player takes the card you wanted) and whether that's good tension or needs softening.
- Whether Form cards should differ between clubs (e.g. a Driver-specific bad card set vs. a universal pool) or stay universal for simplicity.
- Full Form card list is still a first draft (6 bad / 8 good) — needs expansion to a real deck-sized set before implementation.
- How many Created-card sources should exist across the full club list (standard clubs too, or Limited Edition only?) — needs deciding before the full club list is finalized.
- Whether "Active" abilities need an explicit UI/UX moment (a visible button/prompt) versus being framed as "you may" in the moment of club selection.
