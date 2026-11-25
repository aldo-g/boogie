# Pars and Chars — Game Design Document

*A mid-weight golf deckbuilder. 60-90 min per round. Solo vs. par or head-to-head. Video game (Steam target), built as a card-resolution deckbuilder in the spirit of Slay the Spire — no timing checks anywhere in the tee-to-green game, and no dice except one: a shot that finishes on the cup from off the green earns a hole-out d20 (Section 4). Putting is aimed too: you set a line and a weight on the green and the ball rolls over its slope (Section 6).*

---

## 1. High Concept

You play a round of golf by building a permanent, ever-growing hand of clubs (your **Bag**, up to 14 cards) — one card at a time, at the end of each hole. Every shot is resolved by drawing from a separate **Form** hand (representing your current swing state — good and bad), reading its fully known effect, and aiming to compensate or exploit it. Nothing is hidden or randomly rolled once a card is drawn — luck lives in the draw, skill lives in reading it and adjusting your aim. Hazards degrade your Form deck; a putt is aimed on the green and rolled over its slope. Play solo against par, or against friends.

---

## 2. Core Loop (Per Hole)

Each course is a **fixed, designed layout** — all 18 holes have known yardage, par, hazard placement, and pin position. There's no random hole generation; you always know the course, and can learn it and develop strategy for it over repeat plays. Randomness lives in the Form draw, not the hole layout itself.

**Before the first tee (2026-11-25):** the round opens at the pro shop, five clubs on the rack and two to keep (Section 3H). The steps below then run for each hole.

1. **Move to the next hole** (yardage, par, hazards, and pin position are all known upfront).
2. **Declare your shot**: choose a club from your Bag and your target (usually the pin, but can be a deliberate layup). This sets your swing tier for that club (see Section 4).
3. **Draw 3 Form cards**, look at all 3, pick 1 to pair with your shot.
4. **Read the Form card's known effect**, then make your **final aim adjustment** to compensate or exploit it.
5. **Resolve deterministically** — fairway, rough, bunker, water, or green.
6. **Repeat** steps 2-5 until on the green.
7. **Putt** — aim on the green: set a line and a weight, and the ball rolls over the slope (Section 6).
8. **Score the hole.**
9. **End of the hole: choose a stop** (Section 3F, since 2026-11-19): the pro shop, or the round's other stop here (a fitting bay, the range or the hut). The pro shop is the **draft**: draw 3 cards from the shared club deck, look at all 3, pick 1 to add permanently to your Bag. If your Bag is at the 14-card cap, discard a card first to make room. There is no draft after the last hole: the round ends on the final putt, since there is no shot left to play a new club with. A hole you **called** on the tee changes those numbers, and a draft can be **dug** or widened by **trading in** a club (Section 3D).
10. Move to the next hole.

---

## 3. The Bag (Collection-Building System)

- You start with 3 cards: a **Bogey-Mart Driver, Putter and 7-Iron** — the cheap supermarket starter set, and deliberately the worst clubs in the game (Section 3A). They stay in your Bag until you choose to cut them, which is the run's first real goal. **Since 2026-11-25 the round opens at the pro shop** (Section 3H): five clubs on the rack and two to keep before the first tee, so the first hole is played with five clubs, not three.
- **At the end of every hole but the last**, draw 3 cards from the shared club deck, look at all 3, and pick 1 to add permanently to your Bag. The 2 you didn't pick go to a discard pile, which reshuffles into the club deck when it runs dry.
- Your Bag caps at **14 cards** (the real-club limit). Once full, you must discard a card before drawing again — a genuine "what's earning its place in the bag" decision.
- You can play **any** card in your Bag for a shot — old standards or something you picked up on a previous hole.
- **A bag always holds a putter** (Alastair's rule, 2026-11-25). The only putter can't be traded in, cut to make room for a new club, or left behind on a tour; it can go only when the club coming in for it is a putter. Its tile is greyed on those pages and says so. As built: `DraftRules.can_leave(bag, index, incoming)`, asked by `Main.on_trade_in`, `on_discard_pick` and `_on_pack_leave`, by the pages in `BetweenHoles.gd`, and by the bot before it cuts or trades. Until this date only a tour's packing kept it.
- Over an 18-hole round, this means up to 17 potential additions (until 2026-11-17 the game also dealt a draft after the 18th, for a club that could never be hit) — you'll likely hit the 14-card cap somewhere on the back nine, adding escalating "what do I cut" tension as the round progresses. **14 is fixed** — it's golf's actual club limit, and keeping it means the cap needs no explanation. The real squeeze comes from having to cover the course's yardage gaps with those 14 slots (Section 3A), not from the number itself. (Two more come from the opening shop since 2026-11-25, and what the bag's cap does in play is in Open Questions.)
- **Limited edition cards** are shuffled into the same shared club deck at lower odds. They follow the same club categories (Wood/Iron/Wedge/Putter) but have stronger yardage bands and a bonus ability tied to the Form Card System (see Section 4).
- No currency involved — this is the entire acquisition system. Drafting happens once per hole, at the end of it.
- **Every club brings its shots** (Section 4, "Clubs bring their shots"): two or three Form cards that join the deck with the club and leave with it, so the bag is the deck. And the draft can be **hunted in** rather than waited on: call the hole, dig, or trade in a club (Section 3D).
- **A club is grown as well as drafted** (Section 3E): it wears in with use, each draft offers a boost for a club already held in place of a new one, and a ball in the water can leave a curse on the club that hit it.

### Starting Bag (baseline, tune in playtesting)
| Club | Brand | Category | Yardage Band | Handicap |
|---|---|---|---|---|
| Bogey-Mart Driver | Bogey-Mart | Wood | 170-210 | Buffers deviation 25% worse |
| Bogey-Mart 7-Iron | Bogey-Mart | Iron | 90-135 | Narrow band → more 2-card draws |
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
| Bogey-Mart Driver | 170-210 (vs. 180-230) | Buffers Form deviation **25% worse** — a Hook hooks harder |
| Bogey-Mart 7-Iron | 90-135 (vs. 95-145) | Narrower band, so more shots fall into Full/Finesse tier instead of Mid |
| Bogey-Mart Putter | Green only | Cannot create Steady Hands at all — no Putter ability |

They have **no set bonus**. Collecting Bogey-Mart clubs does nothing; there are none in the club deck to collect. The brand exists purely as the floor you measure everything else against.

**Why this matters more than it looks.** It turns the Bag from an accumulation into an *arc*. The first genuinely good Wood you draft is a visible upgrade, not a sidegrade. It gives the early holes a clear, legible goal — replace this junk — before the player understands brands well enough to chase sets. And it makes the eventual Bag-cap decisions cleaner: the first four cuts are obvious (the starter clubs), and only after they're gone does the hard "which real club do I break a set for" tension begin.

**The narrow-band penalty is the sharpest of the three**, because it compounds with Section 4's swing tiers: a club with a tight yardage band drops you into 2-card draws far more often than a club with a wide one. The starter set doesn't just hit shorter — it hands you *less choice*, on every hole, until you replace it.

**Retiring the set**: dropping your last Bogey-Mart club is worth marking with a small moment (a UI beat, a scorecard note). It's the run's first real milestone. **As built (2026-11-16):** cutting the last one stamps "BOGEY-MART RETIRED" over the hole map and Charlie has a line for it. Note when it can happen: a club only leaves a full bag, and the bag fills after hole 11, so the moment arrives on the back nine — late for a "first arc". Letting a draft pick *replace* a starter club before the bag is full would move it to where the design wants it; that is a rules change and has not been made. **Made 2026-11-17:** a club can be **traded in** at any draft (Section 3D), so a starter club can go on the front nine and the moment arrives when the player chooses.

### Brand set bonuses (count-based, always on)

Set bonuses check the **whole Bag** and are always active — no activation, no exhaust. They're displayed as a live counter in the Bag UI so the player always knows how close they are to the next tier.

**The design rule for every bonus on this table: a set bonus must be a rules effect, never a yardage effect.** "Draw an extra Form card," "ignore terrain penalties," "bad cards hit at half severity" — these mean the same thing on a 7,200-yard parkland course and a 6,100-yard links. A bonus like "+15 yards on Woods" is worth wildly different amounts depending on the course's distances, and would need rebalancing with every expansion. Yardage lives on **individual club cards** (Section 3C), where it's a local stat; **sets bend the rules of the game instead.**

The tiers are **2 / 4 / 8**. Eight is chosen deliberately: it is more than half your Bag, so the top set is an identity, not a bonus — and it leaves six slots for everything else, which is not enough to cover a course comfortably. A player with the top set has chosen to be excellent at one thing and to have a real hole in their bag. (It was 7, half the Bag, until 2026-11-17 — see "The top set" below.)

| Brand | 2 in Bag | 4 in Bag | 8 in Bag |
|---|---|---|---|
| **Titanist** *(draw quality)* | Your Form draw **discards the worst card** before you pick | **Draw +1 Form card** at every tier | Once per hole, **re-draw your entire Form hand** before picking |
| **Callowell** *(severity)* | Bad Form cards played from **rough** lose half their deviation | **Ignore all terrain penalties** — rough, bunker, and lie downgrades no longer apply | Bad Form cards **cannot downgrade your lie or taint a putt**; mishits (Top, Thin, Chunk, Skied) hit at half severity everywhere |
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

### The top set (2026-11-17)

The top tier was **7** — half the Bag — until this date. With seven clubs a maker it was reached in 8% of the bot's rounds. With ten a maker and two limited editions (Section 3C) it was reached in 28%, which made it a thing that happens rather than a thing you build. Alastair's call: *it should be rare, but achievable in a game if you go all out.* So the tier went to **8**, and both halves of that sentence were measured — BotSim at Coley Niblick's settings on seeds 101-124, all four courses for the 8 row, Bogey Links and Windlestraw for the 9 row:

| Top tier | An ordinary round reaches it | Going all out reaches it | ...on which tee (median) | What the chase costs |
|---|---|---|---|---|
| 7 (before) | 28% | not measured | — | — |
| **8 (as built)** | **8%** (96 rounds) | **99%** (96 rounds) | the 14th | 0.8 ± 0.7 strokes (+3.96 against +3.19) |
| 9 | 2% (48 rounds) | 90% (48 rounds) | the 16th | 0.6 ± 1.1 strokes |

- **An ordinary round** is the bot as the rivals play it: it likes sets, but drafts for the whole bag. Eight puts it back at the 8% the old roster gave at seven.
- **Going all out** is BotSim's `allout` (`GreedyBot.all_out`): settle on the first maker offered, take every club of it, dig and then trade in whenever the rack shows none, and call holes freely. It gets there in practically every round, and pays for the chase in digs (2.4 a round, each a bad Form card), clubs traded away (4.3) and a bag that ends at 12.4 clubs — about three-quarters of a stroke, which 96 rounds cannot quite tell from nothing. No rival plays this way.
- **Nine was the alternative.** It is rarer still, but even all out it arrives on the 16th tee, with three holes left to use it. Eight arrives on the 14th. A set that lands with five holes to play is one worth chasing.
- **As built**: the tier is one number, `Brands.top_tier` (default `DEFAULT_TOP`), so every label, bonus, stamp and test follows it, and BotSim's `top=<n>` measures another size from the same tree. The 2 and 4 tiers, and the Staff clubs' waking at 4, are unchanged.

### Yardage coverage — what actually makes 14 slots tight

The Bag caps at **14**, golf's real limit, and that number is fixed. On its own it isn't very restrictive: 14 slots over 17 drafts would let a player hoard one brand and still have room to spare. What makes the cap bite is that **those 14 slots also have to play golf.**

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
| **The Surgeon** | Wood / Titanist | While a Titanist **Iron** is in your Bag, its re-draw is **once every six holes** rather than once per round |
| **The Gambler** | Putter / Slazinger | While a Slazinger **Wood** is in your Bag, a called hole you miss still shows **three** clubs |
| **Old Faithful** | Iron / Callowell | While a Callowell **Wedge** is in your Bag, you may dig **twice** a draft |
| **The Metronome** | Iron / Ping-Well | While a Ping-Well **Wood** is in your Bag, your Stock Shots are straight from **any** tier |
| **The Chameleon** | Wood / Nimbus | While a Nimbus **Wood** is in your Bag, it counts as Nimbus **as well as** the brand you carry most of |

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
| Driver | Wood | 180-230 | 50 | The baseline big stick |
| 3-Wood | Wood | 160-195 | 35 | Playable from fairway, unlike Driver |
| 5-Iron | Iron | 135-170 | 35 | |
| 7-Iron | Iron | 95-145 | 50 | |
| 9-Iron | Iron | 75-105 | 30 | Narrow — often a 2-card draw |
| Pitching Wedge | Wedge | 50-90 | 40 | |
| Sand Wedge | Wedge | 20-60 | 40 | Passive bunker ability (Section 4) |
| Putter | Putter | Green | — | Steady Hands source |

### Branded clubs

**How clubs and sets divide the work.** An individual club card is where **yardage** lives — bands, widths, and per-club riders that reference distance are all fine here, because a club's band is a local stat the player reads on the card. **Set bonuses never touch yardage** (Section 3A); they bend rules. So a Slazinger club can be long, while the Slazinger *set* gives you extra Form cards at a severity cost. Both express "aggressive distance," but only the club half needs retuning when a new course ships.

**Titanist** — *tour precision; tight bands, strong buffering, unforgiving off-centre*

| Club | Category | Band | Rider |
|---|---|---|---|
| Titanist Pro Driver | Wood | 185-225 | Buffers deviation 20% better; **-30% distance from rough** |
| Titanist 4-Iron | Iron | 150-180 | Buffers deviation 25% better |
| Titanist 8-Iron | Iron | 85-120 | Buffers deviation 25% better |
| Titanist Blade Putter | Putter | Green | Once per round, a putt that stays out is taken again with no stroke added |

**Callowell** — *forgiveness; wide bands, blunts bad cards, low ceiling*

| Club | Category | Band | Rider |
|---|---|---|---|
| Callowell Big Deal Driver | Wood | 175-230 | Mishits (Top, Thin, Chunk, Skied) hit at **half severity** with this club |
| Callowell 6-Iron | Iron | 110-165 | **Width 55** — joint-widest iron in the game, almost always a Mid-tier draw |
| Callowell Rescue | Iron | 125-175 | Playable from rough with **no distance penalty** |
| Callowell Gap Wedge | Wedge | 40-85 | Shank cannot downgrade your lie when played with this club |

**Ping-Well** — *fitted feel; rewards the comfortable middle*

| Club | Category | Band | Rider |
|---|---|---|---|
| Ping-Well i-Series 5 | Iron | 130-175 | Mid-tier band is **widened** — the middle third counts as the middle half |
| Ping-Well i-Series 8 | Iron | 80-125 | Same widened Mid tier |
| Ping-Well Lob Wedge | Wedge | 15-55 | Creates Flop Shot on **any** hazard lie, not just bunker |
| Ping-Well Mallet Putter | Putter | Green | Steady Hands makes the cup play bigger by **twice** as much |

**MacGregorian** — *heritage; low running ball, built for scrappy lies*

| Club | Category | Band | Rider |
|---|---|---|---|
| MacGregorian Persimmon Driver | Wood | 165-220 | The only Wood **playable from a bunker** |
| MacGregorian Brassie | Wood | 150-190 | Bump and Run played with this carries **a third** and runs the rest (instead of half and half) |
| MacGregorian Mashie | Iron | 115-155 | Ignores the rough's distance penalty |
| MacGregorian Niblick | Wedge | 45-95 | Landing in a hazard with this in your Bag adds **no** bad card to the Form deck |

**Slazinger** — *distance at a price*

| Club | Category | Band | Rider |
|---|---|---|---|
| Slazinger Cannon Driver | Wood | 190-255 | **Longest in the game** but for the Slazinger Staff Driver (below); buffers deviation **30% worse** |
| Slazinger Power Iron | Iron | 145-190 | +15 yds over a standard 5-Iron; buffers 20% worse |
| Slazinger Launch Wood | Wood | 170-215 | Big Strike created by this club grants **max band +10** |

**Nimbus** — *hybrid; covers gaps, no strong opinion*

| Club | Category | Band | Rider |
|---|---|---|---|
| Nimbus Hybrid 3 | Iron | 150-205 | Counts as **both Wood and Iron** for set bonuses and Created cards |
| Nimbus Hybrid 5 | Iron | 125-170 | Counts as both Wood and Iron |
| Nimbus Utility Wedge | Wedge | 30-80 | May be played from **any** lie with no terrain penalty, once per hole |
| Nimbus All-Rounder | Iron | 100-155 | Width 55; no rider — pure flexible filler |

### Limited edition clubs (rare; ability + pair rider)

| Club | Cat / Brand | Band | Created-card ability | Pair rider |
|---|---|---|---|---|
| **Gold Cleek** | Iron / Titanist | 140-175 | Once per hole, create a Pure Strike | Titanist Wood in Bag → twice per hole |
| **The Bulger** (Tour Driver X) | Wood / Slazinger | 185-240 | Create Big Strike when played from rough/bunker | Any Wedge in Bag → no lie requirement |
| **Old Tom's Niblick** | Wedge / MacGregorian | 30-70 | Creates Flop Shot on bunker landing (passive) | MacGregorian Wood → also Bump and Run on fairway |
| **The Rutter** | Wedge / Callowell | 35-80 | Purges one bad Form card per hazard (passive) | Callowell Iron → purges two |
| **Old Reliable Putter** | Putter / Ping-Well | Green | Once per round, create Steady Hands | Another Ping-Well club → once every six holes |
| **Persimmon Spoon** | Wood / MacGregorian | 155-200 | Playable from rough with no distance penalty | 2nd MacGregorian → playable from any lie, no penalty |
| **The Equaliser** | Iron / Nimbus | 115-160 | — | Bag holds 3+ brands → counts as **every** brand for sets |

**Roster totals (2026-11-17)**: 8 standard, 60 branded (ten a maker, two of them Staff clubs — below) and 12 limited (two a maker): 80 distinct clubs, and the 3 Bogey-Mart starters. `assets/data/clubs.json` is the roster of record; the per-maker tables above show each maker's character rather than every club. With 4 makers live a run's pool is **72 clubs** — 24 standards (three copies of each), 40 branded, 8 limited — against the 51 offers a round deals (17 drafts of three; there is none after the last hole). It was about 57 before this date, which meant every club came past roughly once whatever the player did; now a given club turns up in about seven rounds in ten, and finding it is the business of Section 3D.

### Staff clubs (2026-11-17)

Two of each maker's ten clubs are **Staff clubs**: built for the maker's staff players, poor in a mixed bag, and excellent once the bag holds **four** of the maker's clubs (the Staff club itself counts). Taking one early is a bet on the set. The club that completes the set then wakes every Staff club of that maker at once, and that moment is marked: a stamp over the map ("TITANIST 4-SET · The Staff Driver wakes"), a sound, and a word from Charlie. Completing any set tier gets the stamp; the top set gets it in gilt.

| Maker | Staff clubs (carry) | Asleep | Awake — 4 of the maker in the bag |
|---|---|---|---|
| **Titanist** | Staff Driver 190-235, Staff 7-Iron 105-140 | Draws one Form card **fewer** (never fewer than one) | Draws one **more** |
| **Callowell** | Staff Hybrid 140-190, Staff Wedge 30-80 | A bad card played with it goes back on **top** of the Form deck: its family's next deal | A bad card played with it **leaves the Form deck for good** |
| **Ping-Well** | Staff 4-Wood 160-205, Staff 7-Iron 100-145 | **No Mid tier**: the band is half Full, half Finesse, so every swing draws two | Every swing is **Mid, even below its range** |
| **MacGregorian** | Staff Cleek 140-180, Staff Baffy 160-205 | Flies **half** the aim from rough (the Cleek a quarter from sand) | From rough or sand it draws **one more** Form card; the Baffy becomes playable from sand |
| **Slazinger** | Staff Driver 195-260 (the longest club in the game), Staff Iron 150-200 | Bad cards played with it hit **50% harder** | The Slazinger set's +25% no longer applies to it |
| **Nimbus** | Staff Hybrid 95-185, Staff Wood 150-235 | Lets through **more deviation than a driver** (120% / 150%) | **Less than a wedge** (38% / 45%) |

Each awake effect is something the maker's own 4-set does not already give, or the wake would be nothing: Ping-Well 4 already lifts every swing a tier, so its Staff clubs go further and have no bottom to their range; MacGregorian 4 already plays trouble as fairway, so its Staff clubs draw an extra card from it instead.

**As built**: a Staff club carries a second set of effects (`staff`, beside `effects`, in `clubs.json`). Nothing is stored on the club when the bag changes: `ClubAbilities.effect(club, key, default, bag)` answers from the `staff` effects whenever the bag it is handed holds the 4-set, so every rule that passes the bag — and the bot weighing a bag it doesn't have yet — sees the club as it would play there. The card says "Staff" in its header, in green once awake; the draft says "asleep until you carry 4 Titanist (2/4)", "awake in this bag" or "Wakes your Staff Driver", and a cut that would send one back to sleep says so.

### The limited editions added 2026-11-17

Five more, so every maker has two. Each has a pair rider, like the first seven.

| Club | Cat / Brand | Band | Ability | Pair rider |
|---|---|---|---|---|
| **The Surgeon** | Wood / Titanist | 185-230 | Once per round, re-draw your Form hand | Titanist Iron in Bag → once every six holes |
| **The Gambler** | Putter / Slazinger | Green | A called hole you make keeps 3 clubs, not 2 (Section 3D) | Slazinger Wood → a called hole you miss still shows 3 |
| **Old Faithful** | Iron / Callowell | 120-170 | Digging at the draft costs no bad card (Section 3D) | Callowell Wedge → dig twice a draft |
| **The Metronome** | Iron / Ping-Well | 130-170 | Every swing with it is Mid, even below its range | Ping-Well Wood → your Stock Shots are straight from any tier |
| **The Chameleon** | Wood / Nimbus | 160-215 | Counts as the brand the rest of your bag holds most of, not as Nimbus — the wild card that makes a set | Nimbus Wood → counts as both |

One new plain club a maker rounds each out to ten: Titanist Lob Wedge, Callowell Fairway Wood, Ping-Well i-Series 6, MacGregorian Mashie-Niblick, Slazinger Short Iron, Nimbus Gap Hybrid.

---

## 3D. Hunting for a Club (2026-11-17)

Until this date the draft could only be waited on. Every club came past about once a round, at a hole of its own choosing, and nothing the player did changed when; and a player who committed to a maker reached its 4-set every time (Open Questions), so no single club was ever the one that mattered. Alastair's brief: *it should be rewarding to get the club that you want or that makes the set, and you should be incentivised to take risks in building the perfect deck.* Four things answer it — the deeper pool and the Staff clubs (Section 3C), the signature shots (Section 4, "Clubs bring their shots"), and the three moves here, which let a player go looking for a club, each at a price.

| Move | When | What it does | The price |
|---|---|---|---|
| **Call the hole** | On the tee, before the first stroke | Call birdie. Make birdie or better and the draft shows **5**, and you keep **2** | Miss, and the draft shows **2** |
| **Dig** | In the draft, before anything is kept — once | The whole offer goes back and as many fresh clubs are dealt | A **bad Form card** joins your deck: a miss of the wood, iron or wedge family, and you don't choose which |
| **Trade in** | In the draft, before anything is kept — once | Give up a club from the bag for **one more offer** (the rack never shows more than five) | The club, for good, and the shot it brought leaves the Form deck with it |

- **The call is the one place the way you play a hole changes what you draft.** Before it, a birdie and a triple bogey were followed by the same three clubs. It is known information like everything else in the long game: made on the tee, free to take back until the first Form hand is drawn, shown in the shot panel for as long as the hole is played, and stamped with how it came out ("BIRDIE · called it").
- **Keeping two.** After the first club is kept the draft stays open on what is left. A range session takes the place of one of the two. "That'll do" stops at one.
- **A dig's card is a price, not a hazard.** It is rolled through the same gate as hazard decay, so online every machine adds the same card; MacGregorian's decay block does not stop it.
- **Trading in is how Bogey-Mart goes early.** A club only used to leave a full bag, and the bag fills after hole 11, so the starter set could not be retired before the back nine (Section 3A). Any club can now be traded from the first draft. A bag cannot trade its last club, nor its only putter (Section 3).
- **Two limited editions bend these** (Section 3C): The Gambler pays a made call better and softens a missed one; Old Faithful digs for nothing.
- **The computer golfers hunt too.** GreedyBot calls a hole it rates itself three-in-ten or better to birdie (`call_at`), trades in a club its bag would not miss, and digs when the rack offers next to nothing. It does not change how it plays a called hole, which a person would.

**As built**: the rules are pure functions in `scripts/DraftRules.gd` (how many offers, how many kept, whether a dig or a trade is open), checked by RulesTest; `Main.gd` owns the decks, the rolls and the screen (`on_call_hole`, `on_dig`, `on_trade_in`, `on_draft_done`). Online they are actions like any other — the three draft moves are legal for any seat still drafting — and DetTest, NetTest and MPTest make them at random alongside picks. On screen the draft's other moves are a column beside the offers ("Instead: Range session · Dig · Trade in"), and with four or five on the rack each offer is cut narrow, with the one thing that most matters about taking it underneath.

**Measured (2026-11-17)** — BotSim at Coley Niblick's settings (`aim=13,putt=185`), 24 rounds on each of the four courses per arm on seeds 101-124, so 96 rounds an arm. The new arms are one tree with a switch (`nohunt`, `call=<p>`); the game before is the tree as it stood the night before. All of it was run while a draft was still dealt after the last hole; the set figures are read on the 18th tee, which that draft could not touch.

| Arm | Against par | A 4-set by the 18th tee | Seven of a maker (then the top set) | No Bogey-Mart left |
|---|---|---|---|---|
| The game before | +3.75 ± 0.50 | 96% | 8% | 3% |
| New roster, Staff clubs and signature shots, no hunting | +3.57 ± 0.46 | 99% | 28% | 5% |
| ...with digging and trading in | +3.23 ± 0.49 | 96% | 29% | 21% |
| ...and calling, as built: the bot calls a hole it rates 30% or better (0.8 a round) | +3.20 ± 0.49 | 97% | 28% | 21% |
| ...calling freely instead, at 22% (6.4 a round, 2.2 made) | +2.96 ± 0.50 | 99% | 44% | 39% |

- **Scores did not move by more than chance.** As built the game is 0.5 ± 0.7 strokes easier than the game before, 0.8 ± 0.7 for a bot that calls freely, and no one layer is worth more than a third of a stroke. The deck a round ends with is bigger (56 cards on the 18th tee, against 44) and no cleaner (11 bad cards against 9): what the signature shots add, the baggage and the digs take back, and the bot spends a little more of its draft at the range for it (4.2 sessions a round against 3.8).
- **What the bot does with the moves**, per round: it digs 0.6 times and trades in 3.0 clubs, and ends with 1.1 Staff clubs and 4.1 limited editions in the bag, where it used to end with 3.1 limited. Calling depends on the golfer, as it should: at the shipped threshold the weekend hacker never calls, the club regular calls less than one hole a round and makes 37% of them, and the scratch golfer calls eleven and makes just over half. The threshold was 22% for a morning, at which the scratch golfer called seventeen holes of eighteen — a tic rather than a decision.
- **Seven of a maker was three and a half times as common: 8% of rounds to 28%**, and 44% for a player who calls freely and makes a third of them. The first step is the roster — ten clubs a maker and two limited editions where there were seven and one — and the second is the extra club a made call keeps. The 4-set was near-certain before and still is. The bot did not score better for those sets, which says the top set costs in coverage about what it pays; but at seven it was no longer rare. **Decided the same day: it should be rare, and reachable by going all out — so the top tier is now eight** (Section 3A, "The top set"), where an ordinary round reaches it 8% of the time and an all-out one 99%.
- **Bogey-Mart goes early when the player wants it to.** The bot trades whichever club its bag would miss least, which is often not a starter club, and still ends 21% of rounds with none (3% before). A person who wants them gone can be rid of all three by the fourth tee.
- **The rivals shoot what they shot**: on Bogey Links 85.8 (48 rounds), 74.5 and 66.9 (72 rounds each), against 85.8, 74.5 and 66.6 the night before, so `Rivals.gd` still says +15, +4 and -4.
- **Not measured: people.** The bot plays a called hole exactly as it plays any other, where a person will fire at the flag — so the size of the bet (five-keep-two against two) is still a guess. And a simulation cannot say whether a stamp feels like a reward.

---

## 3E. Growing a Club (2026-11-19)

Alastair's brief, after the deeper draft: the deck-building was still weak, and *"we are already offering a club, and those clubs should be able to be grown and boosted as that feels more natural"*. So the club stays the one thing a hole pays out, and the club becomes the thing that is built. Four parts: every club brings its shots (Section 4, "Clubs bring their shots"), and the three here. Putters take no part in any of it: they bring no shots and are aimed on the green.

**Everything a club gains is kept on the club** (`marks`, `level`, `boosts`, `curse` and its `shots`, on the club's own Dictionary), so it shows on the card, travels with the bag online, and is given up when the club is traded in or cut.

### Wear

- **A shot that finishes on the fairway or the green leaves a mark on the club that hit it** (a hole-out and a rim-out count; a penalty drop does not).
- **Three marks is a level, and a club has two.** The club is stamped WORN IN when it earns one.
- **Each level is a choice, taken at the next draft and costing nothing there**: *groove* one of the club's good shots, *lose* its miss, or (a maker's club, once) take *the maker's gain*, below.
  - A **grooved** shot ("Flushed+") plays exactly as it did and comes with a spare: whenever it is dealt, one more card is dealt beside it. So a grooved shot never costs the hand a choice, which is the same currency as the swing tiers.
  - A **lost** miss leaves the Form deck for good. If a range session already had that card, another miss of the family goes instead.
- The draft opens on the choice when one is owed, and the rack follows. A level earned on the last hole is never offered: no draft follows it.

### Boosts

A boost goes on a club already in the bag, and a club takes each kind once. **Since later the same day they are found at the fitting bay** (Section 3F): the stop has three of the five on its bench, the fork says which before the stop is taken, and one is chosen. (The first cut offered one random boost in every draft, in place of a club.)

| Boost | What it does to that club | As built |
|---|---|---|
| **Regrip** | Its misses hit softer | Bad cards played with it at 0.7x severity |
| **Custom fit** | A wider comfortable middle: more three-card draws | Its Mid tier is a sixth of the band wider. Not for a club with no Mid tier or nothing but one |
| **New shaft** | Ten yards longer | The top of its band moves up 10 yds, so the band is wider too |
| **Fresh grooves** | Its shots stop quicker | Every shot hit with it runs out 0.6x as far |
| **Lead tape** | Adds a shot to the club | The bench shows three shots, drawn from Stinger, Controlled Draw, Controlled Fade, Spinner, Soft Fade, Punch Out, Flushed and In the Zone; the player picks one and it joins the club's shots |

They are the numbers the rules already read (severity, the Mid span, the band, the roll), read through `ClubAbilities`, which is why a boost needed no new rule.

### A maker's gain

**A maker's club can wear into something only that maker gives**, as a third thing a level can be spent on, once a club. It is how sets and wear feed each other: the clubs a set is built from are the ones that grow this way.

| Maker | The gain | What it does |
|---|---|---|
| **Titanist** | Tour grind | The club is dealt one more Form card |
| **Slazinger** | New shaft | Ten yards longer (the fitting bay's boost, for nothing) |
| **Callowell** | Regrip | Its misses hit softer (likewise) |
| **Ping-Well** | Custom fit | A wider comfortable middle (likewise; not its Staff clubs or The Metronome) |
| **MacGregorian** | Hickory shaft | The club takes no cut from the rough |
| **Nimbus** | Utility weighting | Adds a Utility Swing, which any club can be dealt |

### Curses

- **A ball in the water or out of bounds can leave a curse on the club that put it there**: one time in two, one of the three at random, and a club carries one at most.
- **One club in eight on the rack is second-hand**: already worn in (a level waits to be chosen) and carrying a curse. The draft card says so. The hut's club in the gorse is one too, and a limited edition.

| Curse | What it does | Mended by |
|---|---|---|
| **Bent shaft** | The club is dealt one fewer Form card | New shaft |
| **Loose grip** | Its misses hit 1.5x as hard | Regrip |
| **Hosel rocket** | A Shank joins the club's own shots | Custom fit |

- **A curse lasts until the one boost that mends it is spent on the club, or the club leaves the bag.** Spent that way the boost lifts the curse and does nothing else. (The first cut let any boost mend any curse, and the bot mended nine in ten at the next draft: 0.86 landed a round and 0.09 were left at the end. A curse did not bite.)
- The card says the curse in claret where it says the club's type, and the hover detail says what it does and what mends it.

### The putter (2026-11-20)

The putter is the most-used club in the bag and was the only one that took no part. It brings no shots, so it grows its own way:

- **A putt holed in one from 15 feet or more leaves a mark** (5 yards). Three marks is a level, two at most, as for any club.
- **A level needs no choice**: the cup plays 8% bigger for each, at once. The card is stamped WORN IN. (10 feet and 12% at first, which had the bot's putter at its second level by the turn.)
- **Three putts on a green can leave it twitchy** (one time in two): the cup plays a fifth smaller. A second-hand putter on the rack arrives twitchy, and worn in a level.
- **Regrip mends it**, at a fitting bay, which is the only boost a putter takes.

### What the card shows (2026-11-20)

The bag tile says where a club stands without a hover: the marks toward its next level beside its type ("WOOD 2/3"), what it has gained ("IRON +2"), WORN IN in green while a choice waits, and a curse by name in claret. The end of a round says what the bag became in a line (clubs, levels worn in, boosts, cursed).

### As built

- The rules are in `ClubAbilities.gd` ("Growth"): `wear_pending`, `wear_choices`, `can_boost`, `curse`, `MENDS`, `MAKER_WEAR`, and the sizes above as constants. `Main.gd` owns the marks and the rolls (`_mark_club`, `maybe_curse_club`) and the actions: `on_wear_in` ("wear") and `on_boost` ("boost"), legal online for any seat still drafting. What a fitting bay would have on its bench is `Player.draft_boosts` (and `draft_tape`), rolled through `_roll()` when the hole ends and sent in `snapshot_decks()`.
- **The computer golfers grow their clubs too.** GreedyBot takes every wear-in (it loses the miss first, then the maker's gain or a groove), and rates a worn or boosted club higher and a cursed one lower when it drafts and cuts.
- **Defaults that were mine, not Alastair's** (he approved the lists of boosts and curses and "do it all" for the five follow-ups, not their sizes): three marks a level; grooved meaning "comes with a spare card"; lead tape as a choice of three; curses from water and out of bounds at one in two; which boost mends which curse; one club in eight second-hand; and each maker's gain.

### Measured (2026-11-19)

BotSim at Coley Niblick's settings (`aim=13,putt=185`), 24 rounds on each of the four courses per arm on seeds 101-124, so 96 rounds an arm. "The game before" is the committed tree of 2026-11-17 run the same night; the two arms are independent samples.

| Arm | Against par | Front nine | Back nine | Deck on the 18th tee | Curses landed / still there at the end |
|---|---|---|---|---|---|
| The game before (2026-11-17) | +3.19 ± 0.49 | +3.96 | -0.77 | 56 cards, 20% bad | none |
| Clubs bring shots, wear, a boost in every draft, any boost mends | +2.53 ± 0.49 | +3.08 | -0.55 | 55 cards, 22% bad | 0.86 / 0.09 |
| As built: shots dealt to their own club, the route (Section 3F), matching mends, second-hand clubs, makers' gains, the late bite | +1.94 ± 0.47 | +2.49 | -0.55 | 54 cards, 25% bad | 0.81 from trouble / 0.52 |

- **The game is about a stroke easier than it was**: 1.25 ± 0.68 between the first row and the last. It is the front nine that moved (+3.96 to +2.49); the starter bag's first holes are less bleak now that its clubs bring cards and a club is dealt its own.
- **The back nine did not get harder.** The late bite (Section 3F) doubles the chance of a bad card by the last hole and added a third of a card a round (3.3 to 3.6); the back nine plays at -0.55 with it and without. The gap between the nines is narrower than it was (4.7 strokes to 3.0) because the front got easier, not because the back pushes back. Making it push back needs the levers that set the course (wind and pins, Section 5), which change every mode and every rival's score; not pulled.
- **Curses bite now.** With any boost mending them the bot cleared nine in ten at the next draft; with one boost to each and that boost only at a fitting bay, two in three are still on the club when the round ends.
- **What the bot does, per round, as built**: 10.0 pro shops, 3.1 fitting bays, 2.6 ranges and 1.3 huts; 5.3 wear-ins (5.2 levels still in the bag at the end) and 1.9 boosts kept. It digs 0.5 times and trades in 1.5 clubs, half what it traded before: a worn club is worth keeping.
- **The deck is the same size at the end as it ever was** (54 cards), but a swing is no longer dealt from all of a family's share of it: a club's pile is the family's six, its own two or three, and what trouble left.
- **Not measured: people.** The bot reads the fork exactly and never plays the hustler. Whether three marks is the right pace, whether a grooved card is felt, and whether ten strokes in hand is the right allowance are for play to say.

---

## 3F. The Way Round (2026-11-19)

Until this date a hole ended the same way every time: three clubs, keep one. The brief (Alastair, 2026-11-17): *"maybe it should have a path where you pick the path, some have better rewards some worse... there could be random events and stuff to upgrade your clubs or get cursed."* Three things answer it: a fork after every hole, a hut where something happens, and something to lose.

### The fork

**After every hole but the last there are two stops, and one is taken.** One of them is always the pro shop. The other is fixed for the round and known from the first tee, and the fork says what is ahead beside the pro shop for the next three holes, so a round can be planned ("the fitting bay is after the 7th: mend the driver there").

| Stop | What happens | How often it is the other stop |
|---|---|---|
| **Pro shop** | The rack: three clubs, keep one, with the call, the dig and the trade-in (Section 3D) | Always there |
| **Fitting bay** | Three boosts on the bench, one for a club you hold (Section 3E). The only place a curse is mended | 4 holes in 10 |
| **Range** | The two worst bad cards leave the Form deck | 3 in 10 |
| **The hut** | Something happens: take it or walk on | 3 in 10 |

- **The fork says what is at each stop before it is taken**: the three boosts on the bench, how many bad cards the range would find, what is at the hut. The choice is a read, in keeping with everything else in the long game.
- **A called hole pays at the pro shop** (five and keep two, or two), and nowhere else.
- **The route is a pure function of the round's seed and the hole number** (`Route.gd`), like the wind and the pins: the same for every player at the table and for every machine online, with nothing to send. A club that is worn in still gets its choice first, whatever the stop.
- The range used to be a button in the draft ("in place of a club"), and so was the boost. Both are places now.

### The hut

One of these, fixed with the route. Each can be walked on from.

| At the hut | Take it and |
|---|---|
| **A club in the gorse** | A limited edition joins the bag, already worn in and carrying a curse (the bag full, something is cut for it) |
| **A stranger's tip** | The club with the most marks has a shot grooved on the spot; a bad card joins that club's family |
| **The drinks cart** *(a round for keeps only)* | Two strokes in hand; a Top joins the wood pile |
| **The hustler** *(a round for keeps only)* | One real putt from five yards on the green just played, with the putter in the bag as it is: holed, three strokes in hand; anything else, two gone. It is no stroke on the card. (A coin toss until 2026-11-20.) |

### Strokes in hand

**A solo round is played for keeps.** It starts with **10 strokes in hand**; every stroke over par spends one and every stroke under gives one back; **with none left after a hole, the round is over.** (In other words: the round ends the moment it stands ten over par, plus or minus what the hut paid.) The count is on the hole panel, in claret from three down. A round stopped this way is not a course record and is not saved as one.

- Why ten: the mid-skill bot stands ten over before the last hole in 9% of its rounds as built (96 rounds; 16% in the game before). Ten is a round a club golfer usually finishes and a careless one does not. The weekend-hacker bot averages fifteen over, so it would rarely finish.
- **2026-11-25:** with the opening shop (Section 3H) and a hole capped at double par (Section 5) the mid-skill bot runs out in 7% of rounds (96 rounds; 15% that morning without them), and the weekend hacker in 65% (48 rounds). Ten was left alone.
- **Not in hot-seat, online or against the computer**, where the others at the table are the stakes and putting a friend out of the round is no fun; and not in a test round from the course editor.

### The course bites later

**Trouble leaves a bad card more often as the round goes on**: the one-in-three for a hazard and the one-in-five for the rough are multiplied by 1 + how late the hole is (`Course.late`, the same curve the wind and the pins build on), so both have doubled by the last hole. The bag and the deck are at their best there, and this is the course's answer.

### As built

`Route.gd` (the stops, the hut, the look-ahead; pure functions, loaded by preload), `Main.gd` (`on_stop`, `on_leave_stop`, `on_boost`, `on_event`; `strokes_in_hand`, `plays_for_keeps`), `Player.draft_stop` / `draft_boosts` / `hand_bonus`. Online the four are actions like any other ("stop", "leave", "boost", "event"), legal for any seat still drafting. GreedyBot takes the pro shop unless the other stop is worth more than a club: the fitting bay to mend a curse or once the bag holds eleven, the range once a quarter of the Form deck is bad, the hut once the bag holds eleven (and never the hustler).

**What this is not.** It is a fork a hole with the road ahead in view, not a map of lanes that join and part; an event is a fixed trade and a coin toss, not a played challenge; and there is no money. Those are the next steps if this one earns them.

---

## 3G. The Tour (2026-11-20)

A run was one round: the bag peaked around the 14th and was thrown away on the 18th. **The tour is the game's four courses as one run** — Bogey Links, Windlestraw Links, Mirage Mesa, Thin Air Ridge, in that order — alone and for strokes in hand, from its own button on the title screen.

- **Six clubs travel from each course to the next**, with everything they have gained: wear, boosts, curses, the shots they bring. After the last putt the bag is laid out and the rest are left behind one at a time; the only putter always travels.
- **The rest starts again**: a fresh Form deck built from the six, a fresh draft pool of the same four makers (so a set can be carried on), and the route and the wind of a new round.
- **Each course allows two fewer strokes in hand**: ten, eight, six, four. Running out ends the tour where it stands.
- The end of each course gives the tour's total so far; each course is still a round of its own for the course records.

**Measured (2026-11-20)** — the seven follow-ups together (the tile, the cap, the late wind and pins, the putter, the tour, Tempo and Pocket, the hustler's putt). BotSim as in Section 3E, 96 rounds an arm. The bot does not play the tour or the hustler.

| Arm | Against par | Front nine | Back nine | Cards in a Form hand |
|---|---|---|---|---|
| Before them (Section 3E, "as built") | +1.94 ± 0.47 | +2.49 | -0.55 | 2.74 |
| First cut: a pocketed card waits until played; the putter marks from 10 ft, 12% a level | -0.57 ± 0.43 | +0.84 | -1.42 | 3.34 |
| As built: a pocketed card waits once; the putter marks from 15 ft, 8% a level | +0.94 ± 0.47 | +1.59 | -0.66 | 3.13 |
| ...the same with the old late wind and pins | +0.61 ± 0.49 | +1.71 | -1.09 | 3.09 |

- **The game is about a stroke easier again** (1.0 ± 0.7), and 2.2 easier than the game of 2026-11-17. It is the bigger hands: Tempo and Pocket put 0.4 more cards in an average hand, and a bigger hand is what dodges a bad card. If that is too much, the lever is which cards carry the keywords (four do), not their rules.
- **The livelier late wind and tighter late pins made the back nine 0.4 ± 0.4 harder**, which cannot be told from nothing, and it is still the easy half by more than two strokes. Section 5 said as much on 2026-11-16 ("the lever is the bag's arc, not the weather") and this bears it out. The change is kept because it costs nothing measurable; it is not the answer.
- **Ten strokes in hand is generous for a good player now**: the mid-skill bot runs out in 4% of rounds (9% before, 16% in the game of 2026-11-17).
- **The cap is rare in sensible play**: nine holes in 144 rival rounds were picked up.

**As built**: the carry is held in `GameSetup` (`tour`, `tour_leg`, `tour_bag`, `tour_brands`, `tour_results`) and each course is a fresh load of the game scene, so nothing about a round had to learn to change course mid-flight. `Main.gd`: `TOUR`, `TOUR_KEEP`, `TOUR_TIGHTEN`, `_apply_tour_carry`, `build_pack_row`, `strokes_allowance`. MPTest checks that a second course starts with the carried bag, a deck built from it and the tighter allowance. **Not measured**: no bot plays a tour, so six clubs and the 10-8-6-4 allowances are first guesses.

---

## 3H. The Opening Shop (2026-11-25)

Until this date a round began on the first tee with the three Bogey-Mart clubs, the same three every time. Measured that morning (BotSim at Coley Niblick's settings, 96 rounds over the four courses): the first four holes cost 1.9 of the round's 2.5 strokes over par, 63% of the long shots on holes 1-6 were hit with a Bogey-Mart club, and a 4-set first stood on the 11th tee (the median), with seven holes left to use it. The front nine played 3.5 strokes harder than the back. The hardest and least varied part of the game was its first twenty minutes, and it was the same in every run.

**The round now opens at the pro shop: five clubs on the rack, keep two, before the first tee.** It is the rack a made call pays (Section 3D), so there is no new rule to learn, and it is a pro shop like any other: a dig is open (a trade-in is not, since the rack is full at five). Then the first tee, with five clubs.

- **Not in a guided round** (Section 7A), which starts with club, aim and card and nothing else; and **not on the later courses of a tour** (Section 3G), where the six clubs carried over are the opening.
- In hot-seat each player takes the stop in turn. Online everyone does at once, and the host deals every seat's rack with the round, so it travels in the round payload like the decks.
- The computer golfers take it too, as they take any pro shop.

**Measured (2026-11-25)** — BotSim, `aim=13,putt=185`, 24 rounds on each of the four courses per arm on seeds 101-124, so 96 rounds an arm. One tree, with switches (`noopen`, `cap=3`); the arms are independent samples. The hole cap (Section 5) moved the same day, so it has a row of its own.

| Arm | Against par | Front nine | Back nine | Holes 1-4 | Out of strokes in hand | A 4-set first on the tee (median) | ...by the 9th tee | One-card hands a round |
|---|---|---|---|---|---|---|---|---|
| The game that morning (first tee, triple par) | +2.51 ± 0.51 | +2.99 | -0.48 | +1.86 | 15% | 11th | 19% of rounds | 3.7 |
| ...with a hole capped at double par | +2.29 ± 0.48 | +2.76 | -0.47 | +1.80 | 9% | 11th | 20% | 3.6 |
| As built: the opening shop, and double par | +0.42 ± 0.51 | +1.51 | -1.09 | +1.09 | 7% | 9th | 51% | 2.2 |

- **The game is about two strokes easier: 2.1 ± 0.7**, nearly all of it the opening shop (1.9 ± 0.7 against the cap-only row). The front nine gained 1.5 and the back 0.6. That puts it about where it stood on 2026-11-20 (+0.94), before the bent holes and the aimed putt made it harder. Not retuned: whether +0.4 for a club regular is where the game should sit is Alastair's call, and the levers are the ones Section 5 lists.
- **The build arrives two holes sooner**: a 4-set stands on the 9th tee in half of all rounds, where it was one in five.
- **The front nine is still the hard half**, by 2.6 strokes (3.5 before).
- **The bag is nearer its cap**: 12.5 clubs on the 18th tee (11.9), 27% of rounds reach fourteen at some point, and a full bag forced a cut at 9 of 1,632 hole-ends (1 before). It is still the fork, not the cap, that squeezes the bag: see Open Questions.
- **Bogey-Mart goes a little sooner**: 12% of rounds end with no Bogey-Mart wood or iron (2% before), and the driver is still in the bag at the end of 48% (78%). A bot going all out for a set trades them away and ends 63% of rounds with none. Retiring the set is a thing a player chooses to do; nothing was changed to force it.
- **The top set** (Section 3A) was measured before the route existed, so it was measured again: an ordinary round reaches eight of a maker in 2% of rounds (2 of 96), and going all out (`allout`) in 72% (69 of 96), on the 14th tee. The figures were 8% and 99%. The bot going all out still leaves the pro shop for another stop seven times a round, so 72% is a floor for a person who does not. Alastair's test for the top tier was "rare, but achievable in a game if you go all out"; eight still passes it and stays. At seven the figures would be 4% and 96%.
- **The rivals** on Bogey Links (48 rounds each, seeds 201-248): 82.5, 72.2 and 63.7, against 87.9, 74.2 and 66.2 on 2026-11-22, so `Rivals.gd` says +11, +1 and -7. The weekend hacker gains most.
- **Not measured: people.** The bot picks its two clubs as it picks any club. Whether five on the rack is too much to read before a ball has been hit, for a player past the guided round, is for play to say.

**As built**: `Main.begin_round()` starts every round, on the first tee or at the shop (`opens_at_shop()`). The stop is "the stop after hole 0": `_opening` is set, `current_hole_index` is 0 with the first hole on the map, `_draw_draft_options()` deals it as `DraftRules.OPENING`, and `finish_hole_done()` ends it like any other. Online: `deal_opening()` on the host, and the `opening` flag and each seat's rack in `build_round_payload()`. BotSim: `noopen`. **Defaults that were mine** (Alastair's instruction was "do all this", to a list that said to deal the draft a made call already pays before the first tee): leaving it out of guided rounds and of a tour's later courses, leaving the dig open, and the page's wording.

---

## 4. Shot Resolution — The Form Card System

Every shot from tee to green is resolved by reading a fully known Form card and aiming around it — no hidden probability and no timing check (putting included; see Section 6). The only die in the game is the hole-out d20: a shot that finishes on the cup from off the green earns the roll, and only a natural 20 drops. That way a player who reads the cards perfectly can earn a hole-out but can't make one happen at will. Luck lives in what you draw; skill lives in reading it correctly and adjusting your aim.

### The two-hand split

- **The Bag**: your 14-card hand of clubs (Section 3) — permanent, grows via the end-of-hole draft, determines available distances.
- **Form**: a separate, small hand representing your current swing state, not your equipment. This is where Hook, Slice, Top, and the Yips live — they were never really clubs, they're modifiers on how you're striking the ball *today*.

### Shot flow

1. **Declare your shot**: choose a club and your target (usually the pin, but can be a deliberate layup short of a hazard). This is your intended distance and general line — and it's what determines your **swing tier** for that club (full swing vs. mid-range vs. finesse vs. extreme finesse), which sets your draw bias (see below).
2. **Draw 3 Form cards** from the Form deck — from the family of the club in your hand, and no other (see "Form by club family" below) — look at all 3, pick 1 to pair with your shot. The other 2 go to the Form discard pile, and the one you play joins them once it is played (a family's discards are reshuffled in when that family runs dry).
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
| Top | Ball stays low, big distance loss, no directional change — runs out 2x, barely touched by wind (0.3x flight) |
| Chunk/Fat | Hits ground first, major distance loss — runs out half as far, 0.7x flight |
| Shank | Severe direction error + downgrades your lie |
| The Yips | Only triggers on the green — see Putting cross-trigger below |
| Pull | Pulls left 8°, full distance — the mild miss, a good read costs nothing |
| Push | Pushes right 8°, full distance |
| Duck Hook | Pulls left 28°, 70% distance, runs out 1.6x — the left-hand disaster, as Shank is the right-hand one (no lie downgrade) |
| Overswing | Pulls left 12°, **+10% distance** — the bad card with an upside: useful on a par 5, dangerous with trouble behind the green |
| Thin | 80% distance, low (0.6x flight), runs out 1.5x — a milder Top |
| Skied | 70% distance, stops quickly (0.4x roll), balloons (1.8x flight) — short, and the wind's plaything |

Top, Thin, Chunk and Skied are **mishits** (bad contact rather than a bad line); Callowell 8 and the Callowell Big Deal Driver play them at half severity.

### Good Form cards

| Card | Effect |
|---|---|
| Pure Strike | Full accurate distance, zero deviation — the reliable baseline. **Created only** (never in the deck) |
| Big Strike | Flies the club's full carry, dead straight, ignoring the rough/bunker cut. **Created only** |
| Stinger | Low, controlled flight — minimal deviation, slightly reduced distance, runs out 1.8x, punches under the wind (0.4x flight) |
| Controlled Draw | Deliberate leftward curve, usable tactically around a left-side dogleg/hazard |
| Controlled Fade | Same idea, rightward |
| Power Draw | Pulls left 6°, +8% distance, runs out 1.4x — the draw that chases |
| Soft Fade | Pulls right 6°, 95% distance, stops quickly (0.5x roll) — the fade that holds a green |
| Flushed | Dead straight, +8% distance — great to a deep green, a liability with water long |
| Spinner | Dead straight, full distance, checks up (0.25x roll) — the green-holder |
| Punch Out | 90% distance, ignores the rough penalty, low (0.6x flight), runs out 1.4x — the low rough escape, where Flop Shot is the high one |
| Flop Shot | High, soft landing — ignores rough/bunker penalty entirely, stops dead (0.15x roll), balloons in wind (1.6x flight) |
| Bump and Run | Low running shot — carries half the aimed distance (0.5x flight, so the wind barely touches it) and runs the rest to the target. The run is judged: struck with the pace the slope asks for, up to 1.6x the planned run — so rough on the way leaves it short, sand or water in its path stops it, and side slope still bends its line. No green check, since a low runner arrives without backspin. |
| Steady Hands | The cup plays bigger on this putt (+60%; Ping-Well Mallet doubles that). **Created only**, used on the green |
| In the Zone | Plays straight at standard distance, and removes the worst bad card from your Form deck — from the family it was played with first, from any other only once that family has none |
| Knockdown, Bomb, Safe Swing, Scotch Runner, Stock Shot, Utility Swing | The **signature shots**: never in the deck a round starts with, only ever brought to it by a maker's club — see "Clubs bring their shots" below |

### Form by club family (decided 2026-11-16)

**Your form is not one thing — it is how you are striking each kind of club.** Every card in the Form deck belongs to one club family (Wood, Iron, Wedge, Putter), and a swing is dealt **only from the family of the club in hand**. The turn is unchanged: pick a club, walk up and aim, then your form decides the swing. What changes is that the form is that club's.

This replaced a single universal deck, where a driver could be dealt a Flop Shot and a sand wedge a Stinger, and where one wild drive made the wedges exactly as shaky as the driver. Alastair's call, in his words: the order "fits golf in the way you pick a club then go up to a ball and aim, then your swing is impacted by how good your form is" — so the order stayed and the form became the club's.

| Family | Its shots | Its misses | Character |
|---|---|---|---|
| **Wood** | Power Draw, Flushed, Stinger, Controlled Fade, Controlled Draw, In the Zone | Hook, Slice, Duck Hook, Overswing, Skied, Top | Length and shape. The misses are big and off line, and a wood passes them on in full |
| **Iron** | Controlled Draw, Controlled Fade, Punch Out, Stinger, Spinner, Soft Fade, In the Zone | Pull, Push, Hook, Slice, Thin (a rough round can add Chunk and Shank) | Precision. The misses start small — the family to fall back on when the driver has gone |
| **Wedge** | Flop Shot, Bump and Run, Spinner, Soft Fade, In the Zone | Chunk, Thin, Shank, Yips, Pull (and Push) | Height and spin. The misses are the strike itself |
| **Putter** *(played from off the green)* | Bump and Run, Stinger, Punch Out | Thin, Top (and Yips) | It rolls true or it doesn't |

What follows from the one rule:

- **The club choice now picks the kind of shot you will be offered**, before you aim. From 100 yards an iron will offer runners and a wedge will offer shots that stop, so the aim can allow for it — short of the green for the one, at the flag for the other. Under the universal deck the roll and flight of the card were unrelated to the club, and the aim could not anticipate them.
- **Each family keeps its own form.** A hazard's bad card joins the family of the club that found the trouble and is one of that family's own misses; the forced card a bunker or an Extreme Finesse swing creates is one too. A driver can go cold while the wedges stay hot.
- **A cold family is a reason to change clubs**, which is a real golf decision the game did not have: an iron off the tee when the woods are full of hooks. The Form column shows the count for each family between draws (good and bad cards in play, claret once two in five are bad), and passing over a club in the bag picks out the family it would be dealt from.
- **It is still one deck and one discard pile.** A draw takes the next card of its family down and leaves the others where they lie; when a family runs out, that family's discards alone are shuffled back in. A hand bigger than a family holds (a Slazinger 4-set dealing five to a putter) borrows the next card of any family rather than deal short.
- **Created cards belong to no family** — a club makes them for itself — so they are unaffected.
- **Brand bonuses are unchanged.** They count cards, change tiers and soften bad cards; none of them cared which card it was.
- **Range sessions and The Rutter** still take the worst bad cards wherever they are. **In the Zone** mends the family it was played with first.

### Clubs bring their shots (2026-11-17)

The Form deck could be cleaned (range sessions, In the Zone) and dirtied (hazards), but never **built**: the deck every shot is drawn from had no good card to chase, so "deckbuilder" described the bag and not the deck. Now **every maker has a signature shot, and drafting one of its clubs puts that card into your Form deck — in the family of the club that brought it. Cutting or trading the club takes the card out again.** One pick builds the bag and the deck together, and a maker is something you can feel on every swing, not only at its set tiers.

| Maker | Signature shot | What it does |
|---|---|---|
| **Titanist** | Knockdown | Straight, 95% distance, flies low (0.5x flight), stops quickly (0.5x roll) — the wind barely finds it |
| **Slazinger** | Bomb | Straight, **+15% distance**, runs out 1.5x — the longest shot in the game. **A bad card joins the same family with it**: Duck Hook (wood), Hook (iron), Chunk (wedge). The bad card stays when the club goes |
| **Callowell** | Safe Swing | Straight, 90% distance, takes no cut from rough or sand |
| **MacGregorian** | Scotch Runner | Straight, full distance, low (0.4x flight), runs out 2x, no cut from rough or sand |
| **Ping-Well** | Stock Shot | Straight and full **from the Mid tier**; from any other tier it is pushed 8° right. The Form hand shows it as it will play for the swing in hand |
| **Nimbus** | Utility Swing | Straight, 95% distance. It belongs to **no family**: any club can be dealt it, and it counts in every family's form |

- **Putters bring nothing.** They are aimed on the green, and the putter's pile of chips (seven cards) is too small to take a card without changing its nature.
- **Standard clubs and Bogey-Mart bring nothing** — one more reason to leave them behind.
- **The risk is the baggage.** A Slazinger bag hits Bombs and owns Duck Hooks, and cutting the driver later does not take the Duck Hook back. That is the brand's set bonus (more cards, harder bad ones) said again in the deck.
- **They are ordinary deck cards**: dealt, discarded and reshuffled with their family, counted in the form table, listed in the deck popup, and named in the draft ("Brings a Knockdown to your iron form").
- **Stock Shot is the one card whose effect depends on the swing**, and nothing is remembered on the card to do it: `ShotRules.card_for_shot()` works out the shot from the tier each time it is shown or played, so there is nothing to send online.
- **A correction to the proposal**: it said "about 18 new Form cards". It is six shots, each of which can sit in the wood, iron or wedge family — 18 places, six cards to learn.

**Every club brings its shots (2026-11-19).** One signature card a maker's club was not enough to make the bag the deck: the 53 cards a round started with supplied nearly every draw. Now the deck starts small (25 cards, below) and **every club but a putter brings two or three cards** to its family, which leave with it:

| The club is | It brings |
|---|---|
| A standard club | Both of its kind's shots, and its miss |
| A Bogey-Mart club | One shot and the miss: one good card to one bad, the worst ratio in the bag |
| A maker's club (Staff clubs too) | The maker's signature shot, one of its kind's two shots (fixed by the club, so the same club always brings the same), and the miss |
| A limited edition | The signature shot and both shots, and no miss |

| Kind of club | Its two shots | Its miss |
|---|---|---|
| Driver (a wood reaching past 205 yds) | Flushed, Power Draw | Hook |
| Fairway wood | Stinger, Controlled Fade | Slice |
| Long iron (reaching 165 or more) | Stinger, Controlled Draw | Push |
| Mid iron (130 to 164) | Controlled Fade, Punch Out | Pull |
| Short iron | Spinner, Soft Fade | Thin |
| Pitching or gap wedge (reaching 70 or more) | Spinner, Bump and Run | Thin |
| Sand or lob wedge | Flop Shot, Bump and Run | Chunk |

- **A club's shots are dealt to that club and to no other (later on 2026-11-19).** A swing draws from its family's own pile (the six cards above, and whatever trouble has left there) plus the shots of the club in hand. So the Driver's Power Draw is never dealt to the 3-Wood, a pile stays about nine or ten cards however full the bag is, and a club that is grooved, taped or cursed is changed alone. **This narrows "Form by club family" (decided 2026-11-16)**: the family is still where a hazard's card lands and what a club falls back on, but a club's own shots are no longer the family's. Alastair agreed to it as one of five follow-ups ("do it all"), after being told it bends that rule. Each card in the deck carries the club that brought it (`FormCard.owner`, sent online after a "#"); a Nimbus club's Utility Swing carries none, and is still anyone's.
- The shots a club brings are a list on the club (`shots`, from `ClubRoster.shots_for`), because wear changes them (Section 3E). `FormDeck.bring()` and `take()` move them. A range session can still take a club's miss, and the club then leaves without it.
- The Form column's table counts each family's own pile; aiming with a club, and passing over one in the bag, say what that club is dealt from.
- A Nimbus club's Utility Swing still belongs to no family. Slazinger's extra bad card still comes with the club and stays when it goes.
- The bag card's hover detail lists the club's shots; a draft offer says what it would bring and a cut says what would leave.

### Form deck composition & hazards

- **Since 2026-11-19 the deck starts at 25 cards, 17 good / 8 bad, and the bag supplies the rest.** Wood: Controlled Draw, Controlled Fade, Stinger, Flushed; Hook, Slice. Iron: Controlled Draw, Controlled Fade, Punch Out, Stinger; Pull, Push. Wedge: Flop Shot, Bump and Run, Spinner, Soft Fade; Chunk, Thin. Putter: unchanged (Bump and Run ×3, Stinger, Punch Out; Thin, Top), since putters bring nothing. With the starter clubs' four cards a round begins on 29. **In the Zone is in no starting pile**: in piles this small it would clear the deck, so it only ever arrives on lead tape (Section 3E). The bullet below is the deck as it was until then.

- Starts weighted toward good cards in every family — **35 good / 18 bad (66%), 53 cards, 23 kinds**, about two good to one bad in each family (2026-11-16; it was one pile of 42, 28 good / 14 bad) — so early holes feel encouraging. The counts are `FormCard.FAMILY_MIX`:
  - **Wood, 10 good / 6 bad**: Power Draw, Flushed, Stinger, Controlled Fade ×2; Controlled Draw, In the Zone ×1. Bad: Hook, Slice, Duck Hook, Overswing, Skied, Top ×1. The one family that starts worse than two to one: the driver is the risky club.
  - **Iron, 10 good / 5 bad**: Controlled Draw, Controlled Fade, Punch Out ×2; Stinger, Spinner, Soft Fade, In the Zone ×1. Bad: Pull, Push, Hook, Slice, Thin ×1.
  - **Wedge, 10 good / 5 bad**: Flop Shot, Bump and Run ×3; Spinner ×2; Soft Fade, In the Zone ×1. Bad: Chunk, Thin, Shank, Yips, Pull ×1.
  - **Putter, 5 good / 2 bad**: Bump and Run ×3; Stinger, Punch Out ×1. Bad: Thin, Top ×1. No In the Zone: in a pile this small it would turn up on most chips and clear the whole deck.
  - **Why it's built this way**: the aim is committed before the draw, so a pick is a choice between known outcomes on *this* hole. The new cards differ mostly in distance, roll and flight rather than raw quality, so the best card depends on the hole: long or short, holding or running, high or low into the wind. The mild bad cards (Pull, Push, Thin) also make "least bad" a real read rather than an obvious one.
  - Hazard decay and forced cards pick uniformly from the misses of the club's family (`FormCard.FAMILY_BAD`), which is wider than what the family starts with: an iron begins without a Chunk or a Shank, and a rough round can put them there.
- Every hazard hit (1 in 3) and every ball that finishes in the rough (1 in 5, since 2026-11-16) can add a bad Form card into the **Form deck** (not directly into your Bag), in the family of the club that put you there — this degrades the quality of future draws for the rest of the round rather than permanently cluttering your Bag. A rough patch of holes genuinely makes your swing worse as the round goes on.
- **A played card goes to the discard pile like the ones passed over (fixed 2026-11-16).** It never did: only the unpicked cards were returned, so every shot took a card out of the game. A round has about 48 carded shots and the deck had 42 cards, so it ran dry on the back nine — 19.5 cards left at the start of the 10th, 4.8 at the 18th (BotSim, medium bot, 96 rounds) — and an empty deck deals a fallback Pure Strike: the bot played 4.9 of them a round on holes 13-18 against 0.05 on holes 1-6. **Every balance figure in this document measured before this date was measured on that draining deck.** Mending it on its own moved the medium bot from +3.9 to +2.9 against par (±0.7): the free Pure Strikes had been worth less than the damage the thinning deck did before it emptied. Created cards still exhaust.
- **Range session (decided 2026-10-17)**: at the end of any hole, instead of drafting a club, remove the 2 worst bad cards from your Form deck. It costs bag progress rather than strokes, and it's the way back from a death spiral.

### Tempo and Pocket (2026-11-20)

Cards in a club's pile did nothing to each other: a hand was three separate offers. Two keywords, on cards that were already in the game, make one swing matter to the next.

| Keyword | On | What it does |
|---|---|---|
| **Tempo** | Controlled Draw, Controlled Fade | Once played, your next swing is dealt one more card |
| **Pocket** | Stinger, Punch Out | Passed over, it waits and joins your next swing's hand, whatever the club. One card waits at a time. A hand with it in is never forced, so it is a way out of sand |

- Both are said on the card, and the Form column says what the last swing left for the next ("In your pocket: Stinger").
- **A card waits once.** Passed over a second time it is discarded like any other. (In the first cut it went back to the pocket until it was played. The bot then had an extra card on most swings, its average hand went from 2.7 cards to 3.3, and with the putter's first numbers the round was 2.5 strokes easier: -0.57 ± 0.43 against par, from +1.94.)
- `FormCard.tempo` / `pocket`; `Player.tempo` and `Player.pocket`, sent in `snapshot_decks()`. The bot plays them as ordinary cards and does not plan around either.

### Created cards ("exhaust" resources, not draws)

To stop top-tier good cards (like Pure Strike) from being either "always in the pool, trivializing decisions" or "randomly lucky when drawn," they don't live in the natural Form deck at all. Instead, **club abilities generate them directly into your Form hand**, and once played they **exhaust** — removed from the game entirely, not discarded back into the cycle. This turns them into a genuine resource to manage (save it for the shot that really can't miss) rather than a lucky draw to hope for.

**Category-to-creation mapping** (also gives each Bag archetype a distinct identity):

| Category | Thematic role | What it creates | Trigger type |
|---|---|---|---|
| **Woods** | Power/burst | "Big Strike" — guarantees near-max distance, ignores deviation | **Active** — saved for a deliberate big moment (a carry over water, a reachable par-5) |
| **Irons** | Precision/control | "Pure Strike" — guarantees zero deviation, standard distance | **Active** — saved for a shot that really can't miss |
| **Wedges** | Finesse/recovery | "Flop Shot," or directly purges one bad card from your Form deck | **Passive** — triggers automatically when you're already in a hazard, rewarding correct club selection rather than activation timing |
| **Putter** | Green mastery | "Steady Hands" — the cup plays bigger on your next putt | **Active** — saved for a genuinely must-make putt |

**The design principle**: Passive fits abilities that reward good *positional play* (reaching for the right club in a bad lie); Active fits abilities meant to be *saved for a clutch moment* (the timing decision itself is the interesting choice).

**As built (2026-10-17) — charges, spent in the moment.**
- **Sources**: only clubs whose text says so create cards — the limited editions below and a few branded riders (the Ping-Well Lob Wedge's Flop Shot). The category table above is the *flavour* each type's creators follow, not a rule every club gets; a bag of standard clubs creates nothing. That keeps created cards scarce enough to be worth drafting for.
- **Actives** are buttons in an Abilities box under the shot panel, each with a charge per hole, per round, or per six holes. Pressing one puts the card straight into the current Form hand. There is no reserve: the decision is which shot of the hole (or round) to spend the charge on.
- **Passives** add their card to the player's *next* Form draw (Old Tom's Niblick after a bunker) or to the club's own draw (the Lob Wedge from rough or sand).
- **A created card always exhausts**, played or not. That includes the bad card a bunker or an Extreme Finesse shot forces on you, so that card never reaches the discard pile.
- **A created card turns a forced draw into a choice**: in sand the club still forces a bad card, but a created card beside it is the bail-out.
- Activated set bonuses (Titanist 8 re-draw, MacGregorian 8 improve lie, Nimbus 2 tier boost, Nimbus 8 ideal club) sit in the same box with the same charges. **Slazinger 8** was "created cards don't exhaust", which means nothing once nothing is held, so it became **once-per-round abilities recharge every hole**.

**Limited Edition club abilities:**

| Card | Ability | Trigger |
|---|---|---|
| Gold Cleek | Once per hole, create a Pure Strike card in your Form hand | Active |
| Tour Driver X ("The Bulger") | Create a Big Strike card whenever you play a Wood from rough/bunker | Active |
| The Rutter | Automatically purges one bad Form card whenever you're in a hazard | Passive |
| Old Tom's Niblick | Creates a Flop Shot card whenever you land in a bunker | Passive |
| Old Reliable Putter | Once per round, you may create a Steady Hands card | Active |
| Persimmon Spoon | No rough penalty; with a 2nd MacGregorian, plays from any lie (sand included) as the fairway | Passive |
| Nimbus Utility Wedge | Once per hole, plays from rough or sand as though from the fairway | Passive |
| Titanist Blade Putter | Once per round, a missed putt is taken again with no stroke added | Active |

### Putting cross-trigger (the Yips)

The Yips card can be drawn in your Form hand approaching the green. You can avoid playing it (pick one of the other 2 draws), but if you're forced to play it, it taints your *next* putt specifically — that putt misses regardless of how well you read it (it is jabbed off the line, and the cup takes nothing). This keeps the Yips doing what it's known for: a mental carryover into putting, not just another distance modifier.

### The aim guide (2026-11-16)

The map shows **where you are aiming, never where the ball will finish**. While a club is in hand (or hovered in the bag) its yardages are drawn as short carry arcs across the line of play, as a yardage book prints them, each with its number: a dashed arc at the club's shortest yardage, two solid arcs with fine hatching between them for the sweet spot (the Mid tier, best odds), and a plain arc at its longest. The putter gets just its reach arc. The aim line and crosshair carry the aimed yardage, and turn claret below the club's shortest (Extreme Finesse).

Nothing on the map accounts for the wind, the slope, the run-out or the Form card: there is no clean-strike ghost, no per-card landing marker and no hole-out highlight. Every one of those things is still shown in its own place (the wind dial, the painted ground, the elevation strip, the card's own numbers), and the shot still resolves exactly from them, but putting them together is the player's read. That read, not a die, is where the uncertainty lives between picking a card and seeing the ball land.

### Worked example

140 yards to pin, fairway lie. **You declare your shot**: 7-Iron, aiming at the pin — this is a full swing for the 7-Iron's band, so your draw is biased toward better odds. Draw **Slice, Top, Hook** anyway — a bad hand despite the good tier. You pick **Slice** (least distance-punishing, known effect: pushes right by a set degree). **Final aim adjustment**: you aim left of the pin to compensate for the known rightward push. The outcome is still fully deterministic — correct compensation lands you close to your actual target despite playing a "bad" card. That's the skill: committing to a sound shot plan, then reading an imperfect hand and adjusting your line around it, not hoping for good luck.

---

## 5. Terrain Modifiers

**Scope note (2026-09-08):** weather and slope were **cut**. Terrain — tee, fairway, rough, bunker, water, green — was the only environmental system in the game. The per-flight weather *deck* stays cut (the round is a continuous run of holes), but **wind is back as of 2026-10-16** — see "Wind" below.

**Update (2026-10-16): elevation and roll are back in** — see "Elevation & roll" below. Slope returns as authored ground on every hole rather than marked zones. It moves the ball through carry and run-out, and the green's tilt bends and paces every putt (Section 6).


| Terrain | Effect on Form draw | Effect on distance | Other effects |
|---|---|---|---|
| **Tee** | Normal (swing tier still applies) | None — full aimed-for distance | No restrictions — every club playable |
| **Fairway** | Normal (swing tier still applies) | None — full aimed-for distance | No modifiers |
| **Rough** | Normal (swing tier still applies) | **-20%** — whatever distance you aimed for is multiplied by 0.8 | 1 chance in 5 of leaving a bad card in your Form deck (2026-11-16) |
| **Bunker** | Forces the Extreme Finesse treatment regardless of swing tier: the club creates 1 fresh bad Form card on the spot, no draw, no choice, forced to play it | **-50%** — whatever distance you aimed for is multiplied by 0.5 | Driver/Fairway Woods unplayable — irons/wedges only |
| **Water** | — | — | Not a lie you play from — a resolution outcome. +1 penalty stroke, ball placed back at nearest fairway/rough point at roughly the same distance as before the shot |
| **Green** | N/A | N/A | Putts are aimed on the green (Section 6) |

The distance penalty applies to your actual aimed-for distance, not an abstract tier ceiling — aim for 200 yards from rough and the shot flies at 160 (before the Form card's own multiplier/bonus lands on top). A Flop Shot card ignores this penalty entirely (Section 4). Bunker already stacks two penalties at once (forced bad card + a steep distance cut, on top of Driver/Woods being unplayable there at all) — a deliberate "hazards should feel bad" design. Rough currently only affects distance, not card count; **playtest whether rough also needs its own Form-draw penalty** (e.g. dropping the card count by one tier-step) before locking these numbers in.

- **Bad cards from hazards**: landing in rough, bunker, or water carries a chance of adding bad cards directly into the **Form deck** (not your Bag), in the family of the club that put you there — see Section 4, "Form by club family" and "Form deck composition & hazards". As built: 1 in 3 for a hazard (sand, water, out of bounds, a lie a Shank downgraded) and, since 2026-11-16, 1 in 5 for a ball that finishes in the rough. The rough is still not a *hazard* — club abilities that answer hazards don't fire for it — but MacGregorian's decay block stops its cards too.
- **Out of bounds (reshaped 2026-11-16)**: the ground in play used to be a box round each hole (at least 60 yards either side of the tee line, 20 behind the tee, 30 past the pin). It is now a shape grown out from the hole itself: 38 yards either side of the line of play from tee to pin, 34 beyond the fairway's edge, 26 beyond the green's, 12 beyond a bunker's, with the outline allowed to wander by up to 6. Beside a fairway that is about the room the box gave; behind a green there is more than there was (26 yards, not ~10), beside one a little less; and the inside corner of a dogleg, which the box counted as rough, is now out of bounds. Water is in play only within 30 yards of the rest — a stream or coastline runs on past the stakes and is out of bounds out there. The rule itself is unchanged: stroke and distance. Drawn on the map as the lighter clearing with white stakes round it; the aim crosshair can't be set down beyond them.
- **Shapes (2026-11-16)**: hole shapes are generated to flow rather than authored that way — a fairway is a ribbon along one curve through its stations (bowing gently between them, round at both ends, running on into the mouth of the green), water is a shoreline through its corner points held to the area those corners enclose, and greens and bunkers are pulled off the oval into kidneys and pears. The authored data for Bogey Links did not change; its shapes did, slightly, everywhere.

### Wind

**One wind a round (2026-11-24).** A round has one wind, blowing over the whole course: its strength and where it comes from are drawn once, from the round's seed. What changes from hole to hole is which way the hole points on the course (the routing the title screen draws, `Course.to_hole()`), so the same wind is into you on one hole and behind you on the next, as on a real course. It sways a little from hole to hole (1 mph and 12 degrees either way: `Wind.SWAY_MPH`, `SWAY_DEG`) and still freshens through the round (below, now about a mile an hour a hole at most). Until this date every hole drew a wind of its own, so a 4 mph hole could follow a 30 mph one. What a round now has is a kind of day: a calm one, a breezy one, or a gale all the way round, with the terrain's old odds (below) now the odds of the day rather than of each hole. Alastair's call; the sizes of the sway are mine. **Not re-measured:** the rivals' typical scores and the front-nine/back-nine figures in "The course pushes back" were taken with a wind per hole.

**Gusts (2026-11-25).** On a hole blowing 8 mph or more the wind gusts in real time. A lull of 4 to 11 seconds, then a gust that builds over 0.8 s, blows 2.5 to 4.5 s in all and dies over a second, at up to 1.6 times the wind's strength (`Wind.GUST_LULL`, `GUST_LAST`, `GUST_RISE`, `GUST_FALL`, `GUST_TIMES`, `GUST_FROM`). You can see one coming and going: the dial's needle lengthens, its number climbs and goes claret ("14 mph · gusts to 22"), and pale streaks cross the hole the way the wind blows. **A shot flies in the wind that is blowing at the moment its Form card is played**, part-gust included, so a shot can be held for a lull, or for a gust at your back. The shot report says when a shot was struck in one. High shots suffer most, as with the wind itself.

This is the one place in the long game where *when* you act matters, beside putting. Alastair's call, in his words: "it happens on time at random intervals, you can sort of see it, but you might have to time your shot to it" — replacing a first version (one day old) in which one shot in five was rolled a gust, so nothing about a gust is rolled now. The sizes are mine. As built: the clock is each machine's own (`CourseMapView.gust`), the level at the click travels with the pick online (`{"index", "gust"}`, trusted as the putt meter's result was), a computer golfer takes whatever is blowing when it plays, and the flow harnesses and BotSim, which run no frames, never see a gust — so nothing here has been measured.

Each hole's wind is set when the hole starts and **held for the whole hole** — shown on the map (an arrow and mph in the corner), in the shot panel ("Wind 22 mph · into you, from the left"), and in the log. Like everything else in the long game it's known before you commit — but reading it is the player's job. The map's guide shows only where you are aiming (Section 4, "The aim guide"); nothing on it works out where the wind will put the ball, before the aim or after it.

- **Strength**: 0-35 mph, skewed toward calm — about one hole in five is calm, the median is ~10 mph, and roughly one in six blows 26+. Those are the parkland numbers; a course's terrain can change the range (Section 8) — a links blows harder, a desert barely at all.
- **It gets up as the round goes on (2026-11-16)**: nothing changes through the first quarter of a round (holes 1-5 of 18), then each hole's draw is lifted, by up to 26% of the terrain's ceiling on the last hole (`Wind.LATE_LIFT`, on the ramp `Course.late()`: 0.2 at the turn, 0.5 on the 12th, 0.9 on the 16th), the lift fading to nothing as the draw nears the ceiling. So it is the quiet holes that go: on parkland a dead calm has become a 9 mph breeze by the 18th, one hole in five is calm on the 1st and none is from the 12th on, and the mean goes from 13.5 mph to 17.7 — while a 30+ mph hole stays one in ten all round. That last part is deliberate: the first version wore the calm skew down instead, which also made gales half as common again on the closing holes, and on Bogey Links those are the two water holes — the simulations showed it buying its difficulty with more 10s and 12s rather than more bogeys. See "The course pushes back" below.
- **Into / downwind**: headwind costs 0.6% of carry per mph; tailwind adds 0.35% per mph. Into the wind hurts more than downwind helps.
- **Across**: drift of 0.4% of the distance flown per mph — a 220-yard drive in a 15 mph crosswind moves ~12 yds, in a 35 mph gale ~28.
- **Height scales both**: club loft (Wood 0.9, Iron 1.0, Wedge 1.2) times the Form card's flight (Stinger 0.4, Top 0.3, Bump and Run 0.5, Chunk 0.7, Flop Shot 1.6, everything else 1.0). Low cards become genuinely valuable on a windy hole; a Flop Shot into a gale is a gamble.
- **Wind affects the flight only** — the run-out after landing is on the ground and ignores it. Putting ignores it entirely.
- **Online**: one wind seed is rolled per round and sent with the opening decks; each hole's wind is a pure function of that seed and the hole number, so every machine sees the same wind without a roll per hole to sync. The same seed cuts the pins (below), so nothing extra is sent for those either.

### Pin positions (2026-11-16)

The hole is no longer always in the middle of the green. Each green has **nine places** for it — the middle, the four sides and the four corners, in the green's own axes — and a round cuts one per green from its seed and the hole number (`Pins.gd`), so the same hole asks a different question from one round to the next: a front and a back pin are a club apart, and a pin on the left makes the left the side not to miss on.

- **Known before you play**, like the wind: the flag on the map is where the hole is, and a note under the wind dial says it in words ("Pin · back left"). Distances shown to the player are to the pin. The 100/150/200 markers and the scorecard yardage are to the middle of the green, as on a real course.
- **The green doesn't move.** Its tilt, its shape and the ground round it hang off the middle of the green (`HoleData.green_pos`), so the same putt breaks the same way wherever the hole is cut; only `pin_pos` changes.
- **Always puttable**: a spot is drawn back toward the middle until 4 yards of green lie all round it, so on a small or pinched green a "tucked" pin is simply less tucked.
- **Tucked away late.** Early in a round a pin is 40% of the way from the middle to the edge and one time in nine is the middle itself. By the last hole it is 70% of the way out, never the middle, and 70% of the time on the green's guarded side — one of the three spots nearest sand or water (the chance grows with `Course.late()`, as the wind does). In yards: about 8 off the middle on an opening hole, 13-17 on the closing ones.

### The course pushes back (2026-11-16)

The simulations (Open Questions, below) said the round got easier as it went: the bag and the Form deck improve and the course never answers, so the back nine was a lap of honour. Three levers were pulled together:

1. **The rough costs something** beyond distance — a ball that finishes in it can leave a bad Form card (Section 4, "Form deck composition & hazards").
2. **Pins move** from round to round (above) — variety rather than difficulty: on its own it changes nothing measurable.
3. **Conditions build**: the wind gets up and the pins get tucked away, both on the same ramp, both nothing at all for the first five holes. (Steeper since 2026-11-20: the late lift of the wind 0.26 to 0.45 of the terrain's ceiling, the late pin depth 0.70 to 0.85, the chance of a guarded pin on the last hole 0.7 to 0.9. Measured in Section 3G: 0.4 ± 0.4 strokes on the back nine.)

**Measured** (BotSim, Coley Niblick's settings, 96 rounds a side over the four courses, one tree with each lever switched, on the mended Form deck — Section 4): all three together cost **+2.5 strokes** (standard error 0.6): +1.30 against par under the old rules, +3.75 with them. Split up: the pins and the late build without the rough's card +1.8; the rough's card on top of that +0.7 at 1 in 5 and +0.9 at 1 in 3. So the chance stays at 1 in 5: going to 1 in 3 buys nothing that can be measured in strokes, but it nearly doubles the bad cards a wayward player collects (4.5 a round to 7.5 for the weekend-hacker rival) and has them spending five of eighteen drafts at the range. What the rough's card does show up in is the draft: 3.2 range sessions a round without it, 3.8 with it.

**What it did not do** is make the back nine the hard half. Under the old rules the bot plays the front in +3.0 and the back in -1.7; with all three levers, +4.3 and -0.6. The course is harder all round, by a stroke or so on each nine, but the closing holes are still five strokes easier than the opening ones — that gap is the bag (three Bogey-Mart clubs on the 1st tee, fourteen chosen ones by the 12th), and no amount of wind closes it without becoming a different game. If the back nine is to be the climax, the lever is the bag's arc, not the weather.

**The rivals** on Bogey Links now shoot 85.8, 74.5 and 66.6 (48 rounds each), against 80.2, 72.9 and 65.1 when they were first measured; `Rivals.gd` says +15, +4 and -4 accordingly. The weekend hacker has moved most: a tucked pin beside water punishes a bot that fires at every flag.

**The most a hole can cost: double par (2026-11-25; triple par from 2026-11-20).** A ball that has taken twice the hole's par in strokes is picked up and the hole is scored at that: 6 on a par 3, 8 on a par 4, 10 on a par 5 (`ShotRules.hole_cap`; the multiple is `ShotRules.par_mult`). In every mode. Double par is the pick-up golfers already play to. Why it moved: round scores have a standard deviation of 5 strokes where each layer of the design measures at a stroke or less, and at triple par one hole cost the mid-skill bot four over or worse in a quarter of its rounds, which is most of ten strokes in hand gone on one tee. At double par that is 16% of rounds (11% with the opening shop). On its own the change moved the average by 0.2 ± 0.7 strokes, which is nothing, and the rounds that run out of strokes in hand from 15% to 9% (Section 3H, "Measured"). Bogey Links' 17th, the island green, was left as it is: it costs the mid-skill bot half a stroke (+0.51 over 72 rounds) and is played to the cap in 15% of them. The figure of two is mine. It ends the hole described next, which random play in the test harness still met about one solo round in fifteen.

**A hole that can't be finished.** An earlier run of these simulations, on the draining deck, found one: on an island green a ball in the water is replayed from where it was struck, and from rough beside the lake into a gale no club carries it — one easy-rival round in 48 took 117 on Bogey Links' 17th and a medium round never ended. It has not recurred in the 670-odd rounds played since the deck was mended (worst hole: 13), but nothing in the rules prevents it, and tucked pins and a livelier wind on the closing holes are the conditions for it. A maximum score per hole (the Rules of Golf's own "Maximum Score" format) would end it; not built, because it is a rule and not a tuning number.

### Elevation & roll

Every hole has ground: a long profile (heights in feet at stations along the hole, eased between them), a sideways cross-fall on the fairway, the lie of the land either side of it, and a tilted plane for the green. A shot is now a **carry** and then a **run-out**, both fully deterministic. The ground is all on show (the painted slope, the elevation strip under the map), but since 2026-11-16 the map no longer draws where a shot will carry or stop: judging the run-out is the player's read, like the wind. Nothing about the ground is hidden or rolled.

- **Club yardage is carry.** Roll is extra, on top. The guide marks the yardage you aim at, not where the ball will stop: allowing for slope, roll and wind is the player's read.
- **Elevation changes carry**: 1 yard of carry lost per yard (3 ft) the landing sits above the launch, gained when it sits below. A raised green plays longer; a drop shot plays shorter.
- **Run-out on flat fairway** is a share of carry: Woods 12%, Irons 5%, Wedges 2% — on parkland. A course's terrain scales it (Section 8): 1.5x on a links, 1.3x in the desert, 0.8x in the mountains. Form cards scale it (Stinger 1.8x, Top 2x, Chunk 0.5x, Flop 0.15x). Bump and Run replaces it: half carry, half judged run to the target (see Section 4).
- **Turf**: rough grabs the ball (3x fairway resistance); sand stops it where it enters; water and out of bounds end the roll with their usual penalties. Greens are quick (0.4x resistance), but a ball that **pitches straight onto the green checks** and keeps only 35% of its run-out — so irons hold greens, and a ball run on from short of the green keeps its pace.
- **Note**: the MacGregorian Brassie's old "+20 yds roll on Bump and Run" had nothing left to add to once Bump and Run became a judged run. As of 2026-10-17 it changes the split instead: a Brassie Bump and Run carries a third of the way and runs two thirds.
- **Slope** pulls the rolling ball downhill: on fairway, a 12.5% grade is steep enough that the ball never settles. Greens' 1.5-3% tilts visibly bend a run-out.
- **The lie of the land (2026-11-16)**: the long profile used to be ruled dead square across the hole, so on a hole with no cross-fall every contour was a straight line across the map. Off the line of play the ground is now read a little further up or down the profile than its yards-out says. Two swings do it, each changing slowly down the hole and differently on every hole: contours **slant** across the line of play (up to 0.3 yards along per yard across) and **bow** as they run out to the sides (up to 16 yards). It only moves ground along the profile, so the line of play keeps exactly the heights it was given (the elevation strip is unchanged), no ground is higher or lower than the hole's own stations, the tee and green are untouched, and a hole drawn flat stays flat. In play it turns the fall line on sloping ground, so a run-out there drifts a little differently, and a landing spot well off line sits a little higher or lower than it did. Measured over the four courses: fairway ground moves by a median of under 0.1 ft (95% of it by less than 1 ft), rough within 45 yards of the line by a median of 0.1-0.2 ft (95% by less than 2.5 ft; a few feet more in the far corners of the steepest holes), and on fairway that slopes at all the fall line turns by a median of about 10 degrees. The bot's scores did not move by more than chance (Section 8).
- **The cup**: a ball that rolls within 1.2 yds of the pin has found the hole and earns the hole-out d20, the same as one that pitches on it.
- **On the map**: hillshading over the hole, contour lines every 5 ft across the ground in play (every fifth one heavier; none on a flat hole), fall-line chevrons on the green, and a side-view elevation strip under the hole plate showing the ball, the flag, and how far above or below you the flag sits. The map looks straight down, so a ball in flight swells as it climbs and shrinks as it drops, while its shadow stays on the ground and thins: about twice its resting size at the top of a full drive, barely bigger on a Stinger, and noticeably so on a Flop Shot (the height is the same loft-times-flight the wind acts on). It comes back to its resting size as it lands. **Landing (2026-11-16)**: the ball no longer just stops. On turf it skips once or twice as it sets off on its run-out — higher off a high shot, livelier off fairway than green, barely at all out of rough — and leaves a ring where it pitched; rough throws up a few blades, sand a pale puff and a spray of grains (and takes the ball dead), water a splash: a flash, drops thrown up, rings going out, and a short hold before the game moves on. A ball that runs on into sand or water gets that mark where it stopped as well. Each sound now plays at its own moment — the thud at touchdown rather than after the roll. **Putts** are shown too: the ball rolls from where it was to where it finished rather than jumping there, and a holed one drops — it goes dark into the cup, the cup rattles on the drop, and the jingle and the stamp wait a beat for it. All of it is picture and sound only: the game has already decided the shot, nothing waits on the animation but the fanfare, and with shot animations off none of it runs.

**Club rebalance (2026-10-16)**: when yardage became carry, every club band was scaled down by its own flat-fairway run-out — carry = old yardage ÷ (1 + roll share), rounded to 5 — so carry plus a normal run-out on flat fairway lands where the old yardage did. Woods dropped ~11% (Driver 200-260 → 180-230), irons ~5% (7-Iron 100-150 → 95-145), wedges and putters are unchanged. The course was designed around the old totals, so par-5 reachability and the coverage budget (Section 3A) are preserved on flat ground; slopes and rough now push the real finish either side of that.

---

## 6. Putting — Aimed on the Green

**Since 2026-11-24 a putt is aimed like every other shot, and nothing in the game is timed.** Until then putting was a timing meter (a marker swept a bar and you stopped it); Alastair's verdict was that the QTE was the weakest part of the game. The green now asks for the same thing the fairway does: read what is shown, and aim.

**How it works**: on the green the map closes in on the ball and the hole. You click the green to set an **aim point**, and it means one thing: *where the ball would stop if the green were dead flat*. Its direction is the line, its distance the weight. Click again to move it; **Strike** (the button, or its key) plays it. The ball then rolls over the green's real slope:

- **It breaks toward the low side.** A 2.5% fall across a 10-yard putt moves it about 2 feet; the break grows with the grade and the length.
- **It runs on downhill and dies uphill.** Straight up a 2.5% slope a 10-yard putt needs about 5 feet more weight; straight down it, about 2 feet less.
- **Too much pace and it will not drop.** The cup takes a ball that passes within 4 inches of its middle (about twice a real cup) with no more than 1.5 yards of roll left in it dead centre, less toward the lip. A putt dying at the hole has the whole cup to fall into; a firm one needs the middle.

The map shows **where you are aiming, never where the ball will finish** (Section 4, "The aim guide"): a straight aim line and a readout against the hole ("1.7 ft left · 1.3 ft past"). The green's grades on your line are given exactly ("Falls 2.5% to the left · 1.0% uphill"), and the chevrons on the green point down the fall line. How far that moves the ball is the player's read, and the skill of putting is learning it. Watching a putt roll and take the break is the feedback: a miss shows by how much, and on which side.

**Distance still drives difficulty**, with no rule saying so: a longer putt breaks more, so the same misjudgement of the slope misses by more, and on the longest the aim is finer than the cursor. Leaving 25 yards is meaningfully worse than leaving 10 feet, so approach play keeps its target.

**What the bag does**: everything that used to widen or narrow the meter's bands now makes **the cup play bigger or smaller** by the same amount, and the cup is drawn the size it plays: Steady Hands (+60%), a worn-in putter (+8% a level), Twitchy (a fifth smaller), and the Callowell and Slazinger putters' riders. The Blade Putter's second attempt is unchanged (the miss is shown, and the ball is back where it was). **The Yips** jab the putt 12 to 24 degrees off the line and up to 15% out on the weight, and the cup takes nothing: it misses however well it was read.

**Termination**: a putt can now finish further out than it started, if you send it there, but it never leaves the green (it stops at the edge), inside ~2 feet it is **conceded as a gimme**, and a hole is capped at triple par.

**The rules are a pure function** of the green, the ball and the aim (`ShotResolver.roll_putt`), so every machine in an online round rolls the same putt; the only roll is the Yips' jab. The computer golfers putt by the same rule: they work out the aim that would hole it and misread it a little on line and weight, set so that they score as they did on the meter. **Measured (2026-11-24)**: BotSim at Coley Niblick's settings (`aim=13,putt=185`), 24 rounds on each of the four courses per arm on seeds 101-124, the meter and the aimed putt from the same tree: +2.50 ± 0.50 against par on the meter, +2.51 ± 0.51 aimed (first numbers for the misread gave +1.12 ± 0.50, so it was loosened by a tenth).

**To settle in play**: the size of the cup (`PUTT_CUP_RADIUS`) and how hard the slope pulls (`PUTT_SLOPE_PULL`) are first numbers, tuned to the computer golfers and not yet to a person; and whether the grades should be shown as figures at all, or left to the chevrons.

---

## 7. Modes

- **Solo vs. Par**: track strokes against course par, no opponents needed. Clean, works as-is.
- **Multiplayer**: 2-4 players, **online or local hot-seat**. Same turn rules either way.
- **Against the computer**: you and one computer golfer, on one screen, at one of three skill levels. A hot-seat round in which one seat is played by the machine — see "Against the computer — as built" below.

### Hot-seat multiplayer — as built

Turn order is **"furthest from the pin plays first"** (real golf etiquette, and it keeps downtime short and evenly spread). Off the tee there are no distances to compare yet, so the first shot of each hole goes in seating order.

The order is applied to **putting too**, rather than letting a player hole out continuously: a player who leaves themselves 8 yards is no longer the one furthest out, so the turn passes. That was a deliberate call — continuous putting is also realistic, but it would have one player sinking a sequence of putts while everyone else watched.

The hole ends only when **every** player is in. Each player's score for the hole is recorded as they hole out.

**What is per-player, and why:**

| State | Scope | Why |
|---|---|---|
| The Bag, and every brand set bonus from it | Per player | It's the thing you build; sharing it would remove the game |
| Form deck | **Per player** | Hazard decay must punish the player who hit the hazard, not the table |
| Club draft pool + discard | **Per player** | See the draft rule below |
| Live brands (the 4-of-6 roll) | **Per player** | Each player's pool is shaped independently, so two players in the same round can be building toward different brands |
| Score / position / lie / strokes | Per player | Obviously |
| The hole, pin, and terrain | Shared | It's one course |

**The draft rule: independent draw-3 per player, no contention.** Each player draws their own 3 from their own pool at the end of every hole, and nobody can take a card another player wanted. The alternative — one shared pool with sequential picks, where sniping is real — is the more interesting tension and is still worth trying, but it was deliberately not built first: it couples every player's draft to the turn order and makes the pool a shared resource that needs its own balancing. Starting without contention keeps the first playable version honest about what's being tested (does hot-seat golf hold attention?) rather than testing two new things at once.

> **Still open:** whether the lack of sniping makes the draft feel like solitaire played in parallel. The relevant open question below ("whether the shared club deck creates awkward sniping") is now a question about whether to *add* contention rather than soften it.

**Simultaneous shot declaration is still NOT implemented**, even now that play is networked. The original note proposed everyone secretly declaring, then revealing together. Networking makes it *possible* (hidden per-player input exists now), but it was deliberately not built: it drops the furthest-from-pin etiquette the rest of the design leans on, and the chosen pacing is that everyone watches each shot land. Worth revisiting only if 4-player downtime proves intolerable in play.

### Against the computer — as built

**Why it exists.** Solo against par has no opponent and no way to lose: the only thing at stake is a number, and the simulations (Open Questions, below) say a competent player beats par comfortably, so even that number stops meaning much. A rival puts something on every hole — you are ahead or behind, and each shot of theirs changes what yours needs to do — without changing a single rule of the solo game.

**What a rival is.** An ordinary seat in a hot-seat round, played by GreedyBot (the balance harness's player) through the same entry points the screen calls for a person. It has its own Bag, draft pool, live brands and Form deck, plays the real rules, and reads only what the screen shows. There is no rubber-banding and no hidden help: the three rivals differ in exactly two numbers, how badly they misjudge a line and how unsteady they are on the putt meter.

| Rival | | Aim misjudgement (yds per 100, sd) | Putt timing error (sd) | Typical round on Bogey Links |
|---|---|---|---|---|
| Dory Mulligan | Weekend hacker | 19 | 225 ms | ~88 (17 over) |
| Coley Niblick | Club regular | 13 | 185 ms | ~74 (3 over) |
| Ace Marlin | Scratch golfer | 8 | 150 ms | ~66 (5 under) |

(Re-measured 2026-11-22, 48 rounds each, after the holes were bent — Section 8: 87.9, 74.2 and 66.2. On 2026-11-20 they were 83.6, 72.7 and 64.4. They were ~86, ~75 and ~67 until then; clubs that grow and bigger Form hands have made every golfer two to three strokes better.)

Measured with BotSim, 48 rounds each, late on 2026-11-16 — after the course began to push back (Section 5) and the Form deck was mended (Section 4); before both they were ~80, ~73 and ~65. With no misjudgement at all the same bot shot ~58 then (not re-measured since), which is the ceiling; that bot is not offered as a rival because nobody would enjoy losing to it.

**Watching, not waiting.** A rival's turn is shown rather than skipped: the club, the aim line on the map, the Form hand it drew, the card it keeps (lit), then the shot. Each step has a short pause, scaled by the shot-speed setting. Seeing a rival read a hand is also the best tutorial the game has. The cost is downtime: a rival's long shot takes about four seconds at normal speed. **Open:** whether that is too long by the back nine — the first lever is the pause lengths (`CPU_BEAT`), the second is skipping the rival's draft.

**Stroke play, not match play.** The match is the round's total, as in hot-seat. The log says who leads after every hole, and Charlie takes stock at halfway and at the finish. Match play (holes won, "2 up with 3 to play") would make each hole its own contest and is the obvious next step if a round's total feels too slow to care about.

**Records.** A rival's round is never recorded. Yours is, as a "vs computer" round.

**Not built:** rivals online (they are local seats only), more than one rival from the title screen (the game supports any mix of seats; the menu offers one), and rivals with a personality in their play — all three play the same sensible game at different levels of accuracy.

### Online play — as built

ENet, host-is-a-player, **host-authoritative**, LAN or direct IP with no backend. Internet play therefore needs port forwarding or a VPN; that was an accepted trade for having nothing to host.

Clients send intent ("club 3, aiming here, Form card 2"); the host resolves with the ordinary game code and broadcasts the outcome. Clients never roll their own dice, so there is one true game state by construction.

**Why that was cheap:** every per-player write goes through the active player, so pointing the active seat at whoever submitted makes the existing hot-seat code the authoritative code. There is no second implementation to keep in step. What *did* need work was the randomness — 13 sites, all on the global generator — and the aim clamp, which was being computed in the view and read back, making the view the authority on a gameplay value.

Deck shuffles are deliberately **not** made deterministic. Doing so would need every peer's generator in lockstep for the whole session, which is the coupling host authority exists to avoid. Instead the shuffled order *is* the message: a Form deck travels as a list of card names.

**Drafts run at once (2026-10-17).** The drafts are independent, so online every player drafts simultaneously on their own machine and the next hole starts when the last pick is in; a player who's done sees who is still choosing. The host accepts a draft action from any seat that still owes one. Each machine shows its own seat's draft, so mid-draft the "active seat" and phase differ between machines by design — what they must agree on is every player's draft stage, and they do, because every machine replays the same picks in the same order.

**Disconnects:** a departed player's seat is retired, their hole conceded, and the round continues. Turn order skips them — necessary, since they would otherwise stay "furthest from the pin" forever and the hole would never end. If the host leaves, the round ends; there is no migration, which would be weeks of work against a problem friends solve socially.

**The putt is no longer a cheat surface (2026-11-24).** While putting was a timing meter the client reported its own result and the host had to trust it. A putt is now an aim point like any other shot: the client sends where it aimed and the host rolls it.

---

### Leaving a round and coming back (2026-11-25)

A round is an hour or more and a tour is four of them, and until this date nothing was kept: closing the game lost the round, and a tour lived only in memory.

- **The round is saved at the stop after each hole, and before the first tee**: the state as the hole was scored, before anything is dealt at the stop. The title screen shows **Continue** with where the round stands ("Bogey Links · 6 holes played · +3"), and one press picks it up at that stop.
- **Leaving in the middle of a hole means playing that hole again from its tee.** A finished hole is never lost. A save taken mid-hole would have to hold a ball in flight, a Form hand and a putt half read; the stop is the one place a round is at rest.
- **A tour course that is finished is saved as finished**, with the bag still to pack, so a tour survives between its courses too.
- **One save.** Starting another round from the title replaces it, and TEE OFF asks once before it does. Finishing the round, or running out of strokes in hand, removes it.
- **Local rounds a player started, only**: solo, hot-seat, against the computer, guided, the tour. Not online, where the host runs the round; not editor test rounds; and never a harness or a capture (the gate is `Records.enabled`, the one the records use).
- What comes back: the bags with everything the clubs have gained, the club pools, the Form decks in their order, the scores, the charges spent, strokes won and lost at the hut, a pocketed card, the call on the hole just scored, the lessons already said, and the tour so far. The route, the wind and the pins need no saving, since they come from the round's seed. What a fitting bay has on its bench, and whether a club on the rack is second-hand, are rolled again.

**As built**: `scripts/RoundSave.gd` (the file, `user://round.save`, written with `store_var` so that hole numbers and levels stay whole numbers, which JSON would hand back as floats; `restore_setup()`, `summary()`), `Main.save_data()` / `apply_save()` / `resume_round()` / `_save_round()`, `GameSetup.resume`, the title's Continue tile, and `SaveTest.gd`. **Mine, not Alastair's** (he said "do all this" to "save between holes and keep the tour on disk"): one slot, saving at the stop and not mid-hole, the confirm on TEE OFF, and the title's wording.

---

## 7A. The Guided Round (2026-11-25)

A new player's first solo round brings the game in a piece at a time. Nothing is cut; pieces are held back by hole, and Charlie says what each one is the first time it turns up (`scripts/Lessons.gd`). Why: the first tee showed about ten ideas at once and the first pro shop five more, and the systems had outrun what a new player could take in.

| When | What arrives |
|---|---|
| Hole 1 | Club, aim, Form card, putt. Then straight to the pro shop: three plain clubs, keep one |
| Hole 2 | What the dots on a club mean. At the shop: makers and sets |
| Holes 1-2 | Light air only (wind capped at 5 mph, so no gusts to time) |
| After hole 3 | The fork: a choice of stops. The maker rack over the bag |
| Hole 4 | Trouble can leave a fault on a club. Staff, limited and second-hand clubs can be on the rack |
| Hole 5 | Calling the hole |
| After hole 6 | Dig and trade in. Everything is now in play |

Lessons tied to an event (a miss joining the deck, a club wearing in, a gusting hole, a Staff or second-hand club on the rack) are said the first time the event happens, whichever hole that is.

- A guided round is **not played for strokes in hand**, so a first round can't be cut short. The end page says the next one is.
- It applies to a **solo round started from the title's Play** only: not hot-seat, rivals, the tour, online or editor test rounds, and no test script.
- The "guided" setting starts on, switches itself off once a guided round passes hole 6, and can be switched back on in Settings.
- On the shot screen a lesson is Charlie's bubble, which stays until the step it is about is taken (or it is clicked away). Between holes, where he can't be seen, it is a note on the page.

The schedule (which hole each piece opens on) and every line are in `Lessons.gd`; the sizes are first guesses to tune by watching new players.

---

## 8. Course & Expansion Structure

**The ladder (2026-11-24).** The game's courses open one at a time, in the picker's order: Bogey Links is open from the start, and each course after it is locked until a finished round on the one before came in at **5 over par or better** (`CourseLibrary.QUALIFY`; any round recorded on this machine counts, see Records). The tour waits until every course is open. The title screen shows a locked course faintly, says what would open it, and on an open course says what a round there would open; the end-of-round page says when a course has just opened. Courses saved from the editor are never locked, and Settings has a switch that opens everything. Alastair's calls: something to unlock, a target score as the key, and that difficulty should climb through the courses themselves and not through a separate ascension level or modifiers (harder courses are to be added later; the four that ship play about equally hard today). Mine: the figure of 5, one figure for every course, locking the tour, and the settings switch. **2026-11-25: the target steps down the ladder.** 5 over on Bogey Links opens Windlestraw Links, 3 over there opens Mirage Mesa, and level par there opens Thin Air Ridge (`CourseLibrary.QUALIFY` is a list now; `target()`, `target_on()`). The courses play about equally hard, so the target is the one thing that climbs until harder courses are added. The mid-skill bot makes each rung's target in 79%, 83% and 67% of its rounds (72, 24 and 24 rounds, with the opening shop and double par in); the weekend hacker makes 5 over on Bogey Links in 15% of its rounds. A course that has a round on it stays open, so nothing opened under the single figure was taken back. Mine: the three figures and that rule. Wind, pins and strokes in hand were not used as a ladder, as Alastair asked on 2026-11-24.

- **Base game**: 1 full 18-hole course with a fixed, designed layout (yardages and hazard placement fixed), plus the base hazard/bad-card set and the shared club deck (standards + limited editions).
- **Custom courses (built 2026-10-16)**: an in-game course editor builds courses of 1-18 holes in the same format the base course uses — fairway centreline, green, bunkers, water, elevation and green tilt — and saves them as JSON. Any course can be picked for solo, hot-seat or online play; the host's course travels in the round payload and is sanitised on arrival. Shorter courses simply mean fewer holes and fewer drafts, so the Bag never fills: brand sets are much harder to complete on a 3- or 9-hole course, which is fine for quick games but is not the balance the design targets.
- **Bent holes, and the course on one sheet (2026-11-22)**: the title screen now draws the chosen course whole — every hole routed tee to green on one piece of ground (`CoursePlan.gd`; the routing is invented when the course is shown, since a course file says nothing about where its holes lie). Seen whole, the four courses were 72 near-straight strips, so every par 4 and par 5 was given a shaped line: a dogleg, a bow out and back, or a double bend, 25-90 yards at the most. Each point of a hole moved sideways by an amount that depends only on how far out it is, so lengths, widths, hazards and elevations are where they were along the hole; the par 3s are untouched. It is not free: a bend's inside corner is out of bounds (Section 5). Measured with BotSim on the same seeds before and after, at Coley Niblick's settings: Bogey Links +1.6 strokes (se 0.7, 48 rounds), Windlestraw Links -2.1 (1.3, 24 rounds), Mirage Mesa +1.0 (1.2), Thin Air Ridge +1.8 (1.0); on Bogey Links the weekend hacker lost 4.2 (1.2) and the scratch golfer 1.9 (0.7). The rivals' typical scores were moved to match. Records are kept, as they are whenever a hole is reshaped.
- **More courses, and terrain (built 2026-11-16)**: three more fixed 18-hole courses ship alongside the base course, each on its own **course terrain**. Terrain is a property of the course, not of a lie — the lies in Section 5 are the same game everywhere — and it does exactly two things to play, both known before the swing:

  | Terrain | Run-out after landing | Wind draw | Course |
  |---|---|---|---|
  | **Parkland** | 1.0x (the ground every club's run-out was tuned on) | 0-35 mph, median ~11 | Bogey Links — par 71, 6,510 yds |
  | **Links** | 1.5x — firm, fast-running | 0-35 mph, median ~17 | Windlestraw Links — par 71, 6,743 yds |
  | **Desert** | 1.3x | 0-30 mph, median ~6 | Mirage Mesa — par 72, 6,860 yds |
  | **Alpine** | 0.8x — soft, holds the ball | 0-35 mph, median ~13 | Thin Air Ridge — par 70, 6,345 yds |

  Firmness multiplies the whole run-out budget (club share, the Form card's multiplier and any extra roll alike), so it is already in every run-out; a judged Bump and Run is unaffected, since it's struck to reach its target. Wind is the same per-hole draw as before with the terrain's own ceiling and calm-skew. Neither touches a yardage band or a set bonus, which is the Section 3A rule: nothing in the club deck needs retuning per course. The layouts carry the rest of each course's identity — pot bunkers, burns and the sea on the links; narrow fairways, waste bunkers and oasis ponds in the desert; six par 3s, side-hill fairways and climbs and drops of 60 ft and more in the mountains. **Tuning so far (2026-11-16):** the layouts were balanced against each other with BotSim at Coley Niblick's settings (`aim=13,putt=185`), 12 rounds a course on the same seeds. After the holes were reshaped to flow and out of bounds became a shape rather than a box (Section 5): Bogey Links +2.5 against par (it was +2.4 before, so the home course plays as it did), Windlestraw Links +3.3, Mirage Mesa +1.8, Thin Air Ridge +2.1. (Those are history now: with the course pushing back and the Form deck mended, Section 5, the same bot shoots +4.8, +3.3, +2.6 and +4.3 over 24 rounds each — Thin Air Ridge, with its small greens and six par 3s, has taken the tucked pins hardest.) A round's score swings by 3-4 strokes either way, so differences of a stroke between courses are within the noise — and so is a 12-round figure itself. Over 24 rounds the same four came out at +1.4, +1.9, +1.1 and +0.8 without the lie of the land (Section 5, "Elevation & roll") and +3.0, +1.5, +2.2 and +1.0 with it: an average shift of +0.6 strokes with a standard error of 0.6 (96 rounds each way, same seeds, the same code but for that one layer). That is no shift that can be told from chance; if there is one it is small, and on the harder side. That is a bot, which reads wind and slope exactly; the terrain numbers themselves (1.5x / 1.3x / 0.8x, and the wind ranges) are a first pass and haven't been played by people. The rivals' typical scores on the title screen are for Bogey Links.

  Terrain also decides how a hole is painted (palette, and what grows or lies around it). A custom course picks its terrain in the editor; a course file without one is parkland.
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
3. **Created card sources and exhaust economy** — how often players should realistically have a Pure Strike/Big Strike available. *Sources and spending are now decided (Section 4, "As built"); how often a typical bag actually gets one is still to measure.*
4. **Putting difficulty** — the size of the cup and how hard the slope pulls (Section 6). Tuned to the computer golfers so far, not to a person.
5. **Whether brand sets actually get completed** — the single riskiest new assumption. If a typical 18-draft run never reaches a 4-set, the whole synergy layer is decoration. Measure this before tuning any individual bonus.
6. **The coverage-vs-sets budget** — how many of the 14 slots a course's distance spread genuinely demands. Target ~8-9 for coverage, leaving 5-6 discretionary (Section 3A). Measure it on a real layout rather than guessing, but **keep the set bonuses themselves course-independent** so the measurement only tunes the budget, never the bonuses.
7. **Whether the Bogey-Mart arc lands** — the starter set should feel bad enough that replacing it is a goal, without making the first three holes miserable.

**Prototyping order**: build a single-hole digital prototype with the Form Card System end to end → validate the "read the hand, aim around it" loop is fun and legible → expand to full 18 holes, the Bag draft, and hazards once the core loop feels good.

---

## 10. Digital Prototype — Build Plan (Godot)

Suggested build order, each stage playable before moving to the next. **Note**: the prototype (`Main.gd`) has been rebuilt on the Form Card System described in Section 4; nothing from the earlier dice-based system is left in it.

1. **Single hole, single player**: hole data, starting Bag of 3 clubs, Form draw-3-pick-1 resolution, distance-to-pin tracking.
2. **Add terrain**: rough/bunker/water zones affecting Form draw and distance (Section 5).
3. **Add the putting meter mini-game.**
4. **Full 18 holes + scoring vs. par** (solo mode complete).
5. **Add the end-of-hole club draft** (shared club deck, permanent growing Bag, 14-card cap, forced discard when full).
6. **Add brands and the Bogey-Mart starting set** (Section 3A): brand field on every club, the starter set's three handicaps, and the full branded roster (Section 3C). Playable and meaningful *before* any set bonus exists — the roster alone gives the draft real choices.
7. **Add brand set bonuses** (2/4/7 tiers; the top tier became 8 on 2026-11-17) with the live Bag-UI counter. This is the step that turns drafting into building; validate it before adding pair riders on top.
8. **Add per-run pool shaping** (Section 3B): seed 4 of 6 brands per round, with the axis-coverage constraint, and the pre-round reveal.
9. **Add pair riders** on limited editions — the last synergy layer, and the easiest to cut if sets alone already carry the draft.
10. **Add limited edition cards** into the shared club deck, including their Created-card abilities.
11. ~~**Add local multiplayer**~~ **Done** — hot-seat for 2-4 players, turn order by distance (furthest from the pin plays first), independent per-player drafts.
12. ~~**Add online multiplayer**~~ **Done** — ENet, host-authoritative, 2-4 players, with disconnect recovery. See Section 7. Simultaneous/secret declaration remains unbuilt by choice, not by limitation.
13. ~~**Add a computer opponent**~~ **Done** (2026-11-16) — three rivals by skill, played by GreedyBot as a hot-seat seat. See Section 7.
14. ~~**Deepen the draft**~~ **Done** (2026-11-17) — ten clubs a maker with two Staff clubs each, twelve limited editions, signature shots that clubs bring to the Form deck, and three ways to hunt for a club: call the hole, dig, trade in. See Sections 3C, 3D and 4.
15. ~~**Grow the clubs**~~ **Done** (2026-11-19) — every club brings its shots to a deck that starts at 25 cards and is dealt them alone, clubs wear in with use (a maker's club into its maker's gain), boosts at the fitting bay, and curses from water, out of bounds and second-hand clubs, each mended by one boost. See Sections 3E and 4.
16. ~~**The way round**~~ **Done** (2026-11-19) — a fork after every hole (pro shop, or a fitting bay, the range or the hut), four things that can happen at the hut, a solo round played for ten strokes in hand, and trouble that bites harder late. See Section 3F.
17. ~~**Seven follow-ups**~~ **Done** (2026-11-20) — growth shown on the bag tile, a hole capped at triple par, a livelier late wind and tighter late pins, the putter wearing in and going twitchy, the tour of four courses, Tempo and Pocket cards, and the hustler settled by a real putt. See Sections 3E, 3F, 3G, 4 and 5.
18. ~~**The shape of a run**~~ **Done** (2026-11-25) — the round opens at the pro shop, a hole is capped at double par, a round and a tour are saved at every stop and picked up from the title, and the ladder's target steps down. In the code, `Main.gd` lost its play-by-play log (written by 103 calls and read by nothing since the log left the screen) and its between-holes pages, which are `BetweenHoles.gd`. See Sections 3H, 5, 7 and 8.

---

## Open Questions / To Decide in Playtesting

- Exact odds of limited edition cards appearing in the shared club deck.
- How many bad cards enter the Form deck economy per hazard hit, and how fast it should degrade — needs playtesting to avoid a death spiral where one bad hole compounds into an unplayable back nine. **Measured 2026-11-16 (BotSim, Bogey Links, 14-40 rounds per skill level): the opposite problem.** A hazard (sand, water, out of bounds, or a Shank's downgraded lie — as built, rough is not one, though Section 5 says it should be) turns up 0.25 times a round for a perfect aimer and 1-3 times for human-like ones, and adds a bad card a third of the time: at most half a bad card a round. Range sessions (1-1.5 a round) and In the Zone remove them far faster: the deck starts with 14 bad cards and reaches hole 18 with 1-4 at every skill level. The deck gets cleaner as the round goes on, not worse, and the two brands built around hazards (Callowell, MacGregorian) have almost nothing to answer.
- **Whether the round gets easier as it goes.** Same simulations: every skill level plays the back nine better than the front, by 1.6 to 4 strokes (at scratch level, 1.1 under on the front and 4.8 under on the back). That is the bag and the Form deck, not the holes: the same bot given a fixed 13-club bag from the first tee, with no draft, plays the front in 3.1 under and the back in 1.0 under — the back nine is the harder half of the course and still plays the easier. The player grows and the course does not push back, so the back nine is a lap of honour rather than a climax. Levers, none pulled yet: let hazards bite (wider trouble, or decay on every hazard rather than one in three), make range sessions rarer or dearer, or let the course push back late (tougher pins or more wind on the back nine).
- **How to create Bag pressure without touching the 14-card cap.** The cap is **fixed at 14** — it's the real rule, players already know it, and an invented number would cost that recognition for nothing. But 14 slots across 18 drafts is loose enough that a player could complete two sets without ever making a painful cut. The pressure must therefore come from the *draft*, not the cap — see "Yardage coverage" in Section 3A. Do not solve this by shrinking the Bag.
- ~~**Brand set thresholds (2/4/7)** — whether 7 of one brand is reachable inside 18 drafts.~~ **Answered by simulation (2026-09-09, 3,000 runs per strategy):** a player who commits to a brand reaches a 4-set **100%** of the time and a 7-set **74%**; a player drafting without a plan reaches a 4-set **61%** and a 7-set **0.2%**. The thresholds hold as designed — intent is strongly rewarded, and the 7-set is aspirational rather than accidental. Re-run this if the pool size, brand card counts, or draft width change. (It counted 18 drafts. A round has had 17 since 2026-11-17, when the draft after the last hole was removed, and the 18th pick never reached a shot before that, so read these figures as slightly high.) **2026-11-17:** with ten clubs a maker the old top tier of 7 stopped being rare, and it was raised to 8 — measured in Section 3A, "The top set".
- **Whether wind is too swingy at 35 mph** — chosen deliberately "wild". If gale holes feel like they decide rounds rather than test them, lower Wind.MAX_MPH or steepen the calm skew before touching the per-mph effects.
- **Whether terrain, elevation and wind carry enough variety** (slope and wind came back 2026-10-16). Terrain is currently the only thing the environment does to you, and two brands (Callowell, MacGregorian) both feed on it. If the round feels flat, weather is the first thing to reconsider — but only after the Form/draft loop is proven.
- **Whether Callowell and MacGregorian are too close** — both answer hazards. The intended split is consequence (Callowell) vs. lie quality (MacGregorian); if that reads as one brand in play, merge them and add a genuinely new axis rather than keeping two hazard brands.
- **Whether Callowell's 4-set (ignore all terrain penalties) is too strong** — it switches off most of Section 5. Intended as a half-Bag payoff, but it may need to move to the top tier if a 4-set is reachable too early.
- **How many brands should be live per run** — 4 of 6 is the starting guess. 3 makes commitment easier but runs samier; 5 makes the pool noisy and sets hard to complete.
- **Whether Bogey-Mart clubs should be cuttable from hole 1** or locked in for a few holes — cutting the starter Driver on hole 1 for a good Wood may end the "escape the starter set" arc before it's felt.
- **Whether the four live brands should be revealed pre-round** (current stance: yes, Section 3B) or discovered — the reveal fits the game's known-information stance, but discovery may make the early draft more exciting.
- In multiplayer, whether to **introduce** club-deck contention at all. As built, each player drafts from their own pool, so sniping cannot happen (Section 7). The open question is whether the draft feels inert without it — and if so, whether a shared pool with sequential picks is good tension or just a feel-bad.
- Whether downtime is acceptable at 4 players, hot-seat or online, or whether the per-shot turn handover needs to batch somehow. Online makes simultaneous declaration buildable if it isn't — that's the escape hatch.
- ~~Whether the end-of-hole draft should stay sequential online~~ **Decided 2026-10-17:** online, everyone drafts at once (see "Online play — as built"). Hot-seat stays sequential — one screen, one picker.
- ~~Whether Form cards should differ between clubs (e.g. a Driver-specific bad card set vs. a universal pool) or stay universal for simplicity.~~ **Decided 2026-11-16: they differ — every card belongs to a club family and a swing is dealt only from its club's** (Section 4, "Form by club family"). The stance since 2026-10-17 had been universal, to be revisited "if Driver and wedge draws feel the same in playtesting"; they did. Measured the same day (BotSim, medium bot, 24 rounds on each of the four courses per arm, seeds 101-124, both arms with played cards cycling — see "Form deck composition & hazards"): families +3.30 ± 0.52 against par, the single deck +2.89 ± 0.40 — a difference of +0.42 ± 0.65, nothing measurable. The short game is where it shows: with families the bot plays a bad card on 14% of wedge shots and 12% of putter chips, against 18% and 17% without, because the good cards a wedge is dealt are now wedge shots. **What families do not yet do is go cold.** The bot ends a round with 2.7 of the 6 bad wood cards it started with, and a family reached two-in-five bad in 5% of rounds for woods and 1% for irons: hazards add about 3 bad cards a round while range sessions (3.8 a round) and In the Zone take out about three times that. The cold-driver decision needs hazards to add more, or range sessions to remove less, before it turns up in play. Still open: whether the families' misses are evenly painful (wedge misses are the strike, which a wedge's buffering does nothing for), whether the range session should let you choose the family it works on, and whether Nimbus hybrids, which count as both Wood and Iron for riders, should be dealt from both.
- ~~Full Form card list is still a first draft~~ **Expanded 2026-10-17** to 12 bad / 14 good kinds (see Section 4). Still open: whether the four new cards that share an icon with an older card need their own art, and whether the Bad-card mix needs a severity weighting for hazard decay.
- ~~How many Created-card sources should exist across the full club list~~ **Decided 2026-10-17:** only clubs whose text says so (limited editions and a few branded riders). Standard clubs create nothing.
- ~~Whether "Active" abilities need an explicit UI/UX moment~~ **Decided 2026-10-17:** yes — a button with its charges shown, in an Abilities box under the shot panel.
- Whether the Bulger, Gold Cleek and Old Reliable charges are the right size. Gold Cleek in particular hands out a Pure Strike every hole; if it decides rounds, make it once per round with the Titanist Wood rider raising it to once every six holes.
- **Whether the hunting moves, the signature shots and the Staff clubs do what they were built for (2026-11-17).** See Section 3D, "Measured". Still to learn from people rather than the bot: whether "five, keep two" against "only two" is the right size of bet (the bot's play does not change on a called hole, a person's will); whether a signature shot should stay in the deck once earned rather than leave with its club; whether Bomb's baggage is too cheap or too dear; and whether Staff clubs are taken early as bets or only once the set is nearly in.
- **What the bag's cap does (2026-11-25).** Sections 3 and 3A lean on the 14-club cap for "what do I cut". Since the route (Section 3F) the bot takes the pro shop at about ten stops of seventeen, and its bag stood at 11.9 clubs on the 18th tee: one forced cut in 1,632 hole-ends. With the opening shop it is 12.5 clubs and nine cuts, and 27% of rounds touch fourteen (Section 3H). What squeezes the bag in play is the fork (a club, or a boost, or a cleaner deck), not the cap. Nothing was changed for it. If the cut is wanted back as a decision, the lever is how often the other stop is worth more than a club, not the number 14.
