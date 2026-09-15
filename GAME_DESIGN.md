# Bogey — Game Design Document (Working Title)

*A mid-weight golf deckbuilder. 60-90 min per round. Solo vs. par or head-to-head. Video game (Steam target), built as a card-resolution deckbuilder in the spirit of Slay the Spire — no dice, and no timing checks anywhere in the tee-to-green game. Putting is the deliberate exception: it's a timing meter whose difficulty scales with distance (Section 6).*

---

## 1. High Concept

You play a round of golf by building a permanent, ever-growing hand of clubs (your **Bag**, up to 14 cards) — one card at a time, at the end of each hole. Every shot is resolved by drawing from a separate **Form** hand (representing your current swing state — good and bad), reading its fully known effect, and aiming to compensate or exploit it. Nothing is hidden or randomly rolled once a card is drawn — luck lives in the draw, skill lives in reading it and adjusting your aim. Hazards degrade your Form deck; putting switches to a distance-scaled timing meter. Play solo against par, or against friends.

---

## 2. Core Loop (Per Hole)

Each course is a **fixed, designed layout** — all 18 holes have known yardage, par, hazard placement, and pin position. There's no random hole generation; you always know the course, and can learn it and develop strategy for it over repeat plays. Randomness lives in the Form draw, not the hole layout itself.

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

- You start with 3 cards: a **Bogey-Mart Driver, Putter and 7-Iron** — the cheap supermarket starter set, and deliberately the worst clubs in the game (Section 3A). They stay in your Bag until you choose to cut them, which is the run's first real goal.
- **At the end of every hole**, draw 3 cards from the shared club deck, look at all 3, and pick 1 to add permanently to your Bag. The 2 you didn't pick go to a discard pile, which reshuffles into the club deck when it runs dry.
- Your Bag caps at **14 cards** (the real-club limit). Once full, you must discard a card before drawing again — a genuine "what's earning its place in the bag" decision.
- You can play **any** card in your Bag for a shot — old standards or something you picked up on a previous hole.
- Over an 18-hole round, this means up to 18 potential additions — you'll likely hit the 14-card cap somewhere on the back nine, adding escalating "what do I cut" tension as the round progresses. **14 is fixed** — it's golf's actual club limit, and keeping it means the cap needs no explanation. The real squeeze comes from having to cover the course's yardage gaps with those 14 slots (Section 3A), not from the number itself.
- **Limited edition cards** are shuffled into the same shared club deck at lower odds. They follow the same club categories (Wood/Iron/Wedge/Putter) but have stronger yardage bands and a bonus ability tied to the Form Card System (see Section 4).
- No currency involved — this is the entire acquisition system. Drafting happens once per hole, at the end of it.

### Starting Bag (baseline, tune in playtesting)
| Club | Brand | Category | Yardage Band | Handicap |
|---|---|---|---|---|
| Bogey-Mart Driver | Bogey-Mart | Wood | 190-235 | Buffers deviation 25% worse |
| Bogey-Mart 7-Iron | Bogey-Mart | Iron | 95-140 | Narrow band → more 2-card draws |
| Bogey-Mart Putter | Bogey-Mart | Putter | Green only | No Steady Hands ability |

Every draft is measured against this floor. See Section 3A for why the starting set is bad on purpose.

---

## 3A. Brands — The Synergy Layer

Every club card carries **two** classifications, and they do different jobs:

- **Category** (Wood / Iron / Wedge / Putter) — mechanical. Sets yardage band, buffering strength, and which Created card it makes (Section 4). Already load-bearing.
- **Brand** (Titanist, Callowell, …) — social. Does nothing on its own; only pays out when you collect several, or when a specific partner card is in the Bag alongside it.

The split matters: category tells you *what a club does*, brand tells you *what your Bag is becoming*. A player drafting purely on category picks the best club for the yardage gap. A player drafting on brand sometimes takes the slightly worse club because it completes a set — and that tension is the whole point of the draft.

Brand names are deliberately golf-adjacent inventions, not real trademarks.

### The brands

Six *draftable* brands, plus one you start with and spend the round escaping.

| Brand | Identity | Feel | Categories it appears in |
|---|---|---|---|
| **Titanist** | Tour precision — tight dispersion, punishing to mis-club | Cold, clinical, expensive | Iron, Wood, Putter |
| **Callowell** | Forgiveness — big sweet spot, blunts your worst days | Friendly, chunky, mid-handicap | Wood, Iron, Wedge |
| **Ping-Well** | Fitted feel — rewards playing a club at its comfortable middle | Engineered, methodical | Iron, Wedge, Putter |
| **MacGregorian** | Classic persimmon revival — low running ball, built for scrappy lies | Heritage, wooden, romantic | Wood, Iron, Wedge |
| **Slazinger** | Aggressive distance — more yards, more danger | Loud, brash, high-risk | Wood, Iron |
| **Nimbus** | Modern hybrid tech — flexible, covers gaps, no strong opinions | Neutral, adaptable, safe | Wood, Iron, Wedge |
| **Bogey-Mart** | Supermarket starter set — what you actually own on day one | Cheap, plastic, embarrassing | Wood, Iron, Putter (starter only) |

### Bogey-Mart — the starting set

Your opening three clubs (Driver, 7-Iron, Putter — Section 3) are all **Bogey-Mart**: the cheap full set you'd buy off a supermarket shelf with the bag included. They are, by design, **the worst clubs in the game**:

| Bogey-Mart club | Yardage band | Penalty vs. a standard club |
|---|---|---|
| Bogey-Mart Driver | 190-235 (vs. 200-260) | Buffers Form deviation **25% worse** — a Hook hooks harder |
| Bogey-Mart 7-Iron | 95-140 (vs. 100-150) | Narrower band, so more shots fall into Full/Finesse tier instead of Mid |
| Bogey-Mart Putter | Green only | Cannot create Steady Hands at all — no Putter ability |

They have **no set bonus**. Collecting Bogey-Mart clubs does nothing; there are none in the club deck to collect. The brand exists purely as the floor you measure everything else against.

**Why this matters more than it looks.** It turns the Bag from an accumulation into an *arc*. The first genuinely good Wood you draft is a visible upgrade, not a sidegrade. It gives the early holes a clear, legible goal — replace this junk — before the player understands brands well enough to chase sets. And it makes the eventual Bag-cap decisions cleaner: the first four cuts are obvious (the starter clubs), and only after they're gone does the hard "which real club do I break a set for" tension begin.

**The narrow-band penalty is the sharpest of the three**, because it compounds with Section 4's swing tiers: a club with a tight yardage band drops you into 2-card draws far more often than a club with a wide one. The starter set doesn't just hit shorter — it hands you *less choice*, on every hole, until you replace it.

**Retiring the set**: dropping your last Bogey-Mart club is worth marking with a small moment (a UI beat, a scorecard note). It's the run's first real milestone.

### Brand set bonuses (count-based, always on)

Set bonuses check the **whole Bag** and are always active — no activation, no exhaust. They're displayed as a live counter in the Bag UI so the player always knows how close they are to the next tier.

**The design rule for every bonus on this table: a set bonus must be a rules effect, never a yardage effect.** "Draw an extra Form card," "ignore terrain penalties," "bad cards hit at half severity" — these mean the same thing on a 7,200-yard parkland course and a 6,100-yard links. A bonus like "+15 yards on Woods" is worth wildly different amounts depending on the course's distances, and would need rebalancing with every expansion. Yardage lives on **individual club cards** (Section 3C), where it's a local stat; **sets bend the rules of the game instead.**

The tiers are **2 / 4 / 7**. Seven is chosen deliberately: it's half your Bag, so a 7-set is an identity, not a bonus — and it leaves exactly 7 slots for everything else, which is not quite enough to cover a course comfortably. A 7-set player is choosing to be excellent at one thing and to have a real hole in their bag.

| Brand | 2 in Bag | 4 in Bag | 7 in Bag |
|---|---|---|---|
| **Titanist** *(draw quality)* | Your Form draw **discards the worst card** before you pick | **Draw +1 Form card** at every tier | Once per hole, **re-draw your entire Form hand** before picking |
| **Callowell** *(severity)* | Bad Form cards played from **rough** lose half their deviation | **Ignore all terrain penalties** — rough, bunker, and lie downgrades no longer apply | Bad Form cards **cannot downgrade your lie or taint a putt**; Chunk and Top hit at half severity everywhere |
| **Ping-Well** *(tier)* | The **Mid tier is widened** — the middle third counts as the middle half | **Every club plays one tier better** than its distance implies | **Extreme Finesse is abolished** for you — you always draw normally, never a forced card |
| **MacGregorian** *(lie recovery)* | Landing in rough or a bunker **no longer adds a bad card** to your Form deck | Playing **out of** rough or bunker draws Form cards as though you were on the fairway (no forced card in bunkers) | Once per hole, **improve your lie one step** before playing (bunker→rough, rough→fairway) |
| **Slazinger** *(risk/reward)* | **Draw +1 Form card**, but bad cards you play hit at **+25% severity** | **Draw +2**, same penalty | Created cards (Big Strike, Pure Strike) **no longer exhaust** — they return to hand at the end of each hole |
| **Nimbus** *(flexibility)* | Any club may be played **one tier better**, once per hole | Your Bag's clubs **count as every category** for set and ability purposes | Once per hole, **play any shot as though you held the ideal club** for it |

**Why these are the right axes.** Each brand attacks a different part of the shot pipeline, so stacking two brands combines rather than overlaps:

| Axis | Brand | What it changes |
|---|---|---|
| **How many cards you see** | Titanist, Slazinger | The draw itself |
| **How badly a bad card hurts** | Callowell | The consequence |
| **Which tier you draw at** | Ping-Well, Nimbus | The gate before the draw |
| **What your lie does to you** | MacGregorian | The terrain and the Form deck's decay |

**Titanist vs. Slazinger** is the sharpest pairing: both give you more cards, but Slazinger charges severity for it. A Slazinger 4-set draws +2 cards and plays them 25% harder — brilliant with Callowell's severity reduction, near-suicidal alone. That's the intended trap, and it's now a *rules* trap rather than a yardage one.

**Callowell's 4-set is deliberately enormous** — ignoring all terrain penalties invalidates most of Section 5. That's correct for a half-Bag commitment: it turns the hazard game off, and a player who builds it has spent their whole draft buying that. Its counterweight is that Callowell does nothing for your draw quality, so you'll be safely in the rough with a mediocre hand.

**MacGregorian and Callowell both answer hazards, but at different points in the chain** — and that separation has to be maintained or the two brands collapse into one. Callowell reduces the *consequence* of a bad card once you're in trouble; MacGregorian attacks the *lie itself*, stopping the Form deck degrading and restoring your draw quality. Stacked, they make a player almost immune to hazards, which is a legitimate and expensive thing to build. Alone, Callowell keeps you safe with a poor hand while MacGregorian gives you a good hand in a bad spot.

### Yardage coverage — what actually makes 14 slots tight

The Bag caps at **14**, golf's real limit, and that number is fixed. On its own it isn't very restrictive: 14 slots over 18 drafts would let a player hoard one brand and still have room to spare. What makes the cap bite is that **those 14 slots also have to play golf.**

Any golf course, on any expansion, asks for a spread of distances — that's what a golf course *is*. If your Bag has no club whose band covers the shot in front of you, you don't get to skip it: you play a club at the wrong end of its band, drop into a 2-card Form draw, and take the risk. **Coverage is not optional, and it competes directly with brand-stacking for the same 14 slots.**

Covering a course's spread properly costs roughly **8-9 clubs**, leaving about **5-6 discretionary slots**. That budget is deliberately just under a 6-set:

- **A 6-set is a genuine sacrifice** — it means deliberately leaving a distance band uncovered and playing the round around the hole in your Bag.
- **A 4-set is the comfortable target** — affordable, still a real commitment.
- **Two 4-sets is the greedy line** — 8 branded clubs, eating most of your coverage. Possible, punishing, and exactly the run a player should attempt once and learn from.

This is why brands appear across **multiple categories** (Section 3A table): a brand spanning Wood, Iron and Wedge can serve coverage *and* set-count with the same card, which is the resource efficiency the drafting game is about. Nimbus's hybrids — counting as both Wood and Iron — are the extreme case, and the reason it's the "safe" brand.

**Important: do not tune sets against a specific course's yardages.** Courses are the main expansion axis (Section 9), and a set balanced around one course's distance gaps becomes wrong the moment a links course with different yardages ships. Individual *clubs* carry yardage bands; *set bonuses* must be course-independent rules effects (see below). The coverage-vs-sets squeeze above holds on any course precisely because it doesn't depend on which distances that course asks for.

### Club pairs ("while X is in your Bag")

Individual cards — mostly limited editions — carry pairwise riders printed directly on the card. These reward drafting a *specific* partner rather than a count, and give the draft its "I need one more thing" hooks.

| Card | Category / Brand | Pair rider |
|---|---|---|
| **Gold Cleek** | Iron / Titanist | While a Titanist **Wood** is in your Bag, its Pure Strike creation triggers **twice per hole** |
| **The Bulger** (Tour Driver X) | Wood / Slazinger | While any **Wedge** is in your Bag, The Bulger's Big Strike no longer needs a rough/bunker lie |
| **Old Tom's Niblick** | Wedge / MacGregorian | While a MacGregorian **Wood** is in your Bag, also creates a **Bump and Run** on any fairway lie |
| **The Rutter** | Wedge / Callowell | While a Callowell **Iron** is in your Bag, purges **two** bad Form cards per hazard instead of one |
| **Old Reliable Putter** | Putter / Ping-Well | While any other **Ping-Well** club is in your Bag, Steady Hands becomes **once every six holes** rather than once per round |
| **Persimmon Spoon** | Wood / MacGregorian | While a second MacGregorian club is in your Bag, playable from **any** lie with no penalty |
| **The Equaliser** | Iron / Nimbus | While your Bag holds **3+ distinct brands**, this club counts as **every** brand for set-bonus purposes |

**The Equaliser** is the deliberate release valve: a player whose draft went badly and ended up with a scattered Bag has one card that turns that scatter into an asset. It should be rare, and it should feel like a rescue.

---

## 3B. Per-Run Draft Pool (Replayability)

The course is fixed and knowable (Section 2), and the starting Bag is fixed (Section 3). **The variance that makes runs distinct lives in the club deck's composition.**

At the start of every round, the game seeds the shared club deck with only **4 of the 6 brands**. The other two are absent entirely — not rarer, gone. Standard, brandless clubs (plain Driver, plain 7-Iron) are always present at full weight, so the deck is never unplayable; the brands sit on top of that reliable base. **Bogey-Mart is never in the draft pool** — you start with it and you only ever lose it.

**What this creates:**

1. **A read-the-pool phase.** Holes 1-4 are discovery. Which brands keep showing up? A player who notices three Callowell cards in the first four drafts knows a forgiveness build is live this run.
2. **A commit decision.** Somewhere around holes 5-8 you commit to one or two brands and start passing on clubs that don't serve them. Passing a strictly-better club to protect a set is the most interesting decision in the draft.
3. **Genuinely different runs from a fixed course.** The same 18 holes played with a Slazinger/MacGregorian pool (long, and forgiving of scrappy lies) plays differently from the same holes with a Titanist/Ping-Well pool (tight, precise, draw-manipulating) — different clubs are correct on the same tee.

**Pool display**: the four live brands are shown to the player **at the start of the round**, before hole 1. Hiding them would make holes 1-4 a guessing game rather than a planning one, and the game's whole stance (Section 1) is that information is known and skill lives in using it. You know which brands are live; you don't know what order they'll come, or whether you'll actually be offered the cards you need.

**Pairing rule**: the four brands are drawn so that at least two of the four axes (draw / severity / lie / tier) are represented. A pool of four brands all attacking the same axis would collapse the run into one strategy; the constraint guarantees every run has at least two viable directions to commit to.

---

## 3C. The Club Roster

The full draftable list. **Standard** clubs are brandless, always in the pool, and exist so the deck always covers every yardage gap. **Branded** clubs are the draft's real content — slightly better than standard, and they count toward set bonuses. **Limited** clubs are rare, carry a Created-card ability and usually a pair rider.

Yardage bands are the tuning surface: a *wide* band means more shots land in the Mid tier (3-card draw), a *narrow* band pushes you into Full/Finesse (2-card draw). Band width is therefore a real stat, not flavour — see Section 4.

### Standard clubs (brandless, always in the pool)

| Club | Category | Band | Width | Notes |
|---|---|---|---|---|
| Driver | Wood | 200-260 | 60 | The baseline big stick |
| 3-Wood | Wood | 180-220 | 40 | Playable from fairway, unlike Driver |
| 5-Iron | Iron | 140-180 | 40 | |
| 7-Iron | Iron | 100-150 | 50 | |
| 9-Iron | Iron | 80-110 | 30 | Narrow — often a 2-card draw |
| Pitching Wedge | Wedge | 50-90 | 40 | |
| Sand Wedge | Wedge | 20-60 | 40 | Passive bunker ability (Section 4) |
| Putter | Putter | Green | — | Steady Hands source |

### Branded clubs

**How clubs and sets divide the work.** An individual club card is where **yardage** lives — bands, widths, and per-club riders that reference distance are all fine here, because a club's band is a local stat the player reads on the card. **Set bonuses never touch yardage** (Section 3A); they bend rules. So a Slazinger club can be long, while the Slazinger *set* gives you extra Form cards at a severity cost. Both express "aggressive distance," but only the club half needs retuning when a new course ships.

**Titanist** — *tour precision; tight bands, strong buffering, unforgiving off-centre*

| Club | Category | Band | Rider |
|---|---|---|---|
| Titanist Pro Driver | Wood | 205-250 | Buffers deviation 20% better; **-30% distance from rough** |
| Titanist 4-Iron | Iron | 155-190 | Buffers deviation 25% better |
| Titanist 8-Iron | Iron | 90-125 | Buffers deviation 25% better |
| Titanist Blade Putter | Putter | Green | Steady Hands also narrows nothing — but grants a **second** timing attempt once per round |

**Callowell** — *forgiveness; wide bands, blunts bad cards, low ceiling*

| Club | Category | Band | Rider |
|---|---|---|---|
| Callowell Big Deal Driver | Wood | 195-255 | Chunk and Top hit at **half severity** with this club |
| Callowell 6-Iron | Iron | 115-175 | **Width 60** — the widest iron in the game, almost always a Mid-tier draw |
| Callowell Rescue | Iron | 130-185 | Playable from rough with **no distance penalty** |
| Callowell Gap Wedge | Wedge | 40-85 | Shank cannot downgrade your lie when played with this club |

**Ping-Well** — *fitted feel; rewards the comfortable middle*

| Club | Category | Band | Rider |
|---|---|---|---|
| Ping-Well i-Series 5 | Iron | 135-185 | Mid-tier band is **widened** — the middle third counts as the middle half |
| Ping-Well i-Series 8 | Iron | 85-130 | Same widened Mid tier |
| Ping-Well Lob Wedge | Wedge | 15-55 | Creates Flop Shot on **any** hazard lie, not just bunker |
| Ping-Well Mallet Putter | Putter | Green | Steady Hands widens the sunk band **twice** as much |

**MacGregorian** — *heritage; low running ball, built for scrappy lies*

| Club | Category | Band | Rider |
|---|---|---|---|
| MacGregorian Persimmon Driver | Wood | 185-245 | The only Wood **playable from a bunker** |
| MacGregorian Brassie | Wood | 170-215 | Bump and Run played with this gains **+20 yds roll** |
| MacGregorian Mashie | Iron | 120-165 | Ignores the rough's distance penalty |
| MacGregorian Niblick | Wedge | 45-95 | Landing in a hazard with this in your Bag adds **no** bad card to the Form deck |

**Slazinger** — *distance at a price*

| Club | Category | Band | Rider |
|---|---|---|---|
| Slazinger Cannon Driver | Wood | 215-285 | **Longest in the game**; buffers deviation **30% worse** |
| Slazinger Power Iron | Iron | 150-200 | +15 yds over a standard 5-Iron; buffers 20% worse |
| Slazinger Launch Wood | Wood | 190-240 | Big Strike created by this club grants **max band +10** |

**Nimbus** — *hybrid; covers gaps, no strong opinion*

| Club | Category | Band | Rider |
|---|---|---|---|
| Nimbus Hybrid 3 | Iron | 160-215 | Counts as **both Wood and Iron** for set bonuses and Created cards |
| Nimbus Hybrid 5 | Iron | 130-180 | Counts as both Wood and Iron |
| Nimbus Utility Wedge | Wedge | 30-80 | May be played from **any** lie with no terrain penalty, once per hole |
| Nimbus All-Rounder | Iron | 105-165 | Width 60; no rider — pure flexible filler |

### Limited edition clubs (rare; ability + pair rider)

| Club | Cat / Brand | Band | Created-card ability | Pair rider |
|---|---|---|---|---|
| **Gold Cleek** | Iron / Titanist | 145-185 | Once per hole, create a Pure Strike | Titanist Wood in Bag → twice per hole |
| **The Bulger** (Tour Driver X) | Wood / Slazinger | 210-270 | Create Big Strike when played from rough/bunker | Any Wedge in Bag → no lie requirement |
| **Old Tom's Niblick** | Wedge / MacGregorian | 30-70 | Creates Flop Shot on bunker landing (passive) | MacGregorian Wood → also Bump and Run on fairway |
| **The Rutter** | Wedge / Callowell | 35-80 | Purges one bad Form card per hazard (passive) | Callowell Iron → purges two |
| **Old Reliable Putter** | Putter / Ping-Well | Green | Once per round, create Steady Hands | Another Ping-Well club → once every six holes |
| **Persimmon Spoon** | Wood / MacGregorian | 175-225 | Playable from rough with no distance penalty | 2nd MacGregorian → playable from any lie, no penalty |
| **The Equaliser** | Iron / Nimbus | 120-170 | — | Bag holds 3+ brands → counts as **every** brand for sets |

**Roster totals**: 8 standard, 19 branded, 7 limited — 34 distinct clubs. With a per-run pool of 4 brands, roughly 8 standard + 12-13 branded + 7 limited are live in any given run, which is enough to fill 18 drafts with real choices without the pool being so deep that sets never complete.

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
| Stinger | Low, controlled flight — minimal deviation, slightly reduced distance |
| Controlled Draw | Deliberate leftward curve, usable tactically around a left-side dogleg/hazard |
| Controlled Fade | Same idea, rightward |
| Flop Shot | High, soft landing — ignores rough/bunker penalty entirely, minimal roll |
| Bump and Run | Low running shot — extra roll distance |
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

**Scope note (2026-09-08):** weather and slope are **cut for now**. Terrain — tee, fairway, rough, bunker, water, green — is the only environmental system in the game. This removes the per-flight weather deck entirely and leaves the round a continuous 18 holes with no flight breaks. Both are re-addable later (weather as a per-flight modifier deck, slope as marked zones biasing rest position and the putt meter), but nothing in the current design depends on either, and the brands were rebalanced so none needs them.


| Terrain | Effect on Form draw | Effect on distance | Other effects |
|---|---|---|---|
| **Tee** | Normal (swing tier still applies) | None — full aimed-for distance | No restrictions — every club playable |
| **Fairway** | Normal (swing tier still applies) | None — full aimed-for distance | No modifiers |
| **Rough** | Normal (swing tier still applies) | **-20%** — whatever distance you aimed for is multiplied by 0.8 | None else |
| **Bunker** | Forces the Extreme Finesse treatment regardless of swing tier: the club creates 1 fresh bad Form card on the spot, no draw, no choice, forced to play it | **-50%** — whatever distance you aimed for is multiplied by 0.5 | Driver/Fairway Woods unplayable — irons/wedges only |
| **Water** | — | — | Not a lie you play from — a resolution outcome. +1 penalty stroke, ball placed back at nearest fairway/rough point at roughly the same distance as before the shot |
| **Green** | N/A | N/A | Switches entirely to the putting meter (Section 6) |

The distance penalty applies to your actual aimed-for distance, not an abstract tier ceiling — aim for 200 yards from rough and the shot flies at 160 (before the Form card's own multiplier/bonus lands on top). A Flop Shot card ignores this penalty entirely (Section 4). Bunker already stacks two penalties at once (forced bad card + a steep distance cut, on top of Driver/Woods being unplayable there at all) — a deliberate "hazards should feel bad" design. Rough currently only affects distance, not card count; **playtest whether rough also needs its own Form-draw penalty** (e.g. dropping the card count by one tier-step) before locking these numbers in.

- **Bad cards from hazards**: landing in rough, bunker, or water carries a chance of adding bad cards directly into the **Form deck** (not your Bag) — see Section 4, Form deck composition & hazards.

---

## 6. Putting — The Putting Meter (Timing)

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

**Still to build**: nothing beyond distance currently biases the meter. Slope was cut along with weather (see below); if putting later needs more texture, green contour is the obvious place to add it back.

---

## 7. Modes

- **Solo vs. Par**: track strokes against course par, no opponents needed. Clean, works as-is.
- **Multiplayer**: simultaneous shot declarations — everyone secretly picks their club/target, reveal together, resolve shots in "furthest from pin plays first" order (mirrors real golf etiquette, minimizes downtime).

---

## 8. Course & Expansion Structure

- **Base game**: 1 full 18-hole course with a fixed, designed layout (yardages and hazard placement fixed), plus the base hazard/bad-card set and the shared club deck (standards + limited editions).
- **Expansions**: new courses, each introducing:
  - A distinct fixed 18-hole layout with its own identity (signature holes, hazard placement, par).
  - New club cards (standard and limited edition) for the shared club deck.
  - New hazard types or bad cards.
  - Possibly new putting-green rules on a links-style expansion course.

---

## 9. Design Priorities to Nail First (before anything else)

These are the game's actual feel — everything else is dressing:

1. **Full Form card list** (currently a first draft of 6 bad / 8 good) — needs expansion to a real deck-sized set.
2. **Swing-tier draw-bias percentages** — exact numbers for how much full swing vs. finesse shifts your odds.
3. **Created card sources and exhaust economy** — how often players should realistically have a Pure Strike/Big Strike available.
4. **Putting meter difficulty curve** — band widths and marker speed across the distance range. Distance is currently the only input.
5. **Whether brand sets actually get completed** — the single riskiest new assumption. If a typical 18-draft run never reaches a 4-set, the whole synergy layer is decoration. Measure this before tuning any individual bonus.
6. **The coverage-vs-sets budget** — how many of the 14 slots a course's distance spread genuinely demands. Target ~8-9 for coverage, leaving 5-6 discretionary (Section 3A). Measure it on a real layout rather than guessing, but **keep the set bonuses themselves course-independent** so the measurement only tunes the budget, never the bonuses.
7. **Whether the Bogey-Mart arc lands** — the starter set should feel bad enough that replacing it is a goal, without making the first three holes miserable.

**Prototyping order**: build a single-hole digital prototype with the Form Card System end to end → validate the "read the hand, aim around it" loop is fun and legible → expand to full 18 holes, the Bag draft, and hazards once the core loop feels good.

---

## 10. Digital Prototype — Build Plan (Godot)

Suggested build order, each stage playable before moving to the next. **Note**: the existing prototype (`Main.gd`) was built against the earlier dice-based system and needs updating to match the Form Card System described in Section 4 before further work continues.

1. **Single hole, single player**: hole data, starting Bag of 3 clubs, Form draw-3-pick-1 resolution, distance-to-pin tracking.
2. **Add terrain**: rough/bunker/water zones affecting Form draw and distance (Section 5).
3. **Add the putting meter mini-game.**
4. **Full 18 holes + scoring vs. par** (solo mode complete).
5. **Add the end-of-hole club draft** (shared club deck, permanent growing Bag, 14-card cap, forced discard when full).
6. **Add brands and the Bogey-Mart starting set** (Section 3A): brand field on every club, the starter set's three handicaps, and the full branded roster (Section 3C). Playable and meaningful *before* any set bonus exists — the roster alone gives the draft real choices.
7. **Add brand set bonuses** (2/4/7 tiers) with the live Bag-UI counter. This is the step that turns drafting into building; validate it before adding pair riders on top.
8. **Add per-run pool shaping** (Section 3B): seed 4 of 6 brands per round, with the axis-coverage constraint, and the pre-round reveal.
9. **Add pair riders** on limited editions — the last synergy layer, and the easiest to cut if sets alone already carry the draft.
10. **Add limited edition cards** into the shared club deck, including their Created-card abilities.
11. **Add local multiplayer** (simultaneous shot declarations, turn order by distance).

---

## Open Questions / To Decide in Playtesting

- Exact odds of limited edition cards appearing in the shared club deck.
- How many bad cards enter the Form deck economy per hazard hit, and how fast it should degrade — needs playtesting to avoid a death spiral where one bad hole compounds into an unplayable back nine.
- **How to create Bag pressure without touching the 14-card cap.** The cap is **fixed at 14** — it's the real rule, players already know it, and an invented number would cost that recognition for nothing. But 14 slots across 18 drafts is loose enough that a player could complete two sets without ever making a painful cut. The pressure must therefore come from the *draft*, not the cap — see "Yardage coverage" in Section 3A. Do not solve this by shrinking the Bag.
- ~~**Brand set thresholds (2/4/7)** — whether 7 of one brand is reachable inside 18 drafts.~~ **Answered by simulation (2026-09-09, 3,000 runs per strategy):** a player who commits to a brand reaches a 4-set **100%** of the time and a 7-set **74%**; a player drafting without a plan reaches a 4-set **61%** and a 7-set **0.2%**. The thresholds hold as designed — intent is strongly rewarded, and the 7-set is aspirational rather than accidental. Re-run this if the pool size, brand card counts, or draft width change.
- **Whether terrain alone carries enough variety** now that weather and slope are cut. Terrain is currently the only thing the environment does to you, and two brands (Callowell, MacGregorian) both feed on it. If the round feels flat, weather is the first thing to reconsider — but only after the Form/draft loop is proven.
- **Whether Callowell and MacGregorian are too close** — both answer hazards. The intended split is consequence (Callowell) vs. lie quality (MacGregorian); if that reads as one brand in play, merge them and add a genuinely new axis rather than keeping two hazard brands.
- **Whether Callowell's 4-set (ignore all terrain penalties) is too strong** — it switches off most of Section 5. Intended as a half-Bag payoff, but it may need to move to the 7-tier if a 4-set is reachable too early.
- **How many brands should be live per run** — 4 of 6 is the starting guess. 3 makes commitment easier but runs samier; 5 makes the pool noisy and sets hard to complete.
- **Whether Bogey-Mart clubs should be cuttable from hole 1** or locked in for a few holes — cutting the starter Driver on hole 1 for a good Wood may end the "escape the starter set" arc before it's felt.
- **Whether the four live brands should be revealed pre-round** (current stance: yes, Section 3B) or discovered — the reveal fits the game's known-information stance, but discovery may make the early draft more exciting.
- In multiplayer, whether the shared club deck creates awkward "sniping" (another player takes the card you wanted) and whether that's good tension or needs softening.
- Whether Form cards should differ between clubs (e.g. a Driver-specific bad card set vs. a universal pool) or stay universal for simplicity.
- Full Form card list is still a first draft (6 bad / 8 good) — needs expansion to a real deck-sized set before implementation.
- How many Created-card sources should exist across the full club list (standard clubs too, or Limited Edition only?) — needs deciding before the full club list is finalized.
- Whether "Active" abilities need an explicit UI/UX moment (a visible button/prompt) versus being framed as "you may" in the moment of club selection.
