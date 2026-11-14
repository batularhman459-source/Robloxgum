# HUNTED (working title) – Game Design

Nov 14, 2026 · @batu

## Pitch

**Drop into a map full of hunters, take risks for cash, and if you get caught, you become a hunter.**

HUNTED is a round-based parkour survival game. Runners escape NPC minions and one player-controlled Special Hunter. The closer you play to danger, the more you earn.

Four rules guide every decision:

- **Always playing.** Nobody spectates. Caught players hunt, and new players drop into the running round.
- **Risk pays.** Close calls, dodges and tricks near hunters earn the most.
- **Skill wins.** Nothing you can buy makes you faster or harder to catch.
- **Every round is different.** Maps, modifiers and server events change the rules each round.

It is not a steal-game: no plots, no stealing, no passive income.

## Round flow

A round lasts about 5 minutes, then everyone is beamed up to a floating lobby, votes for 20 seconds, and drops straight back in. The longest anyone waits is about 30 seconds.

&#91;embedded content: round loop · 4 phases + lobby\]

Caught runners stay in the round as hunters, and new players can jump from the lobby into the running round at any time.

**Lobby (floats above the map)**

- Players can see the map below them.
- Things to do while waiting: a small parkour course, the shop, cosmetics preview, vote pads.
- **Join anytime.** A new player spawns in the lobby and can jump down into the running round right away, as a runner. Coins count from when you join, so joining late is never a disadvantage.

**Round phases (starting values, to tune in playtests)**

1. **Drop-in (0:00).** Everyone is dropped or beamed down. A Special Hunter is chosen and released after a 10-second head start for runners.
2. **Hunt (0:10–4:00).** Minions spawn over time. More hunters on the map = more coins per second for survivors.
3. **Frenzy (last 60 s).** Hunters get faster, extra minions spawn, and the map changes (for example a bridge collapses or the lights go out).
4. **End.** The round ends when the timer runs out or every runner is caught.

**After the round**

- Everyone is **beamed up** with a light-beam effect into the lobby.
- A short results screen shows: survivors, top hunter, best close call, coins earned.
- **20-second vote** on the next map and modifier (for example 3 cards to pick from).
- Everyone is dropped back into the new round.

## Runners: movement and coins

Runners earn coins for staying alive, and earn the most for being close to hunters without getting caught.

**Movement (rebuilt from scratch)**

- Starting moves: sprint, double jump, slide, wall run, wall jump, vault, landing roll.
- Unlockable moves later: grapple, wall climb, glide, air dash (see Progression).
- Must work on mobile from day one: big buttons for jump, slide and wall run.

**Coin sources (starting values, to tune)**

| Source | When | Coins |
| --- | --- | --- |
| Survival | Every 5 s alive | 5 × danger multiplier (+10% per hunter on the map) |
| Close call | A hunter passes within \~6 studs of you | 15 |
| Dodge | A hunter's grab or lunge misses you | 30 |
| Trick | Wall run, vault, wall jump, etc. | 2–5, doubled if a hunter is within \~20 studs |
| Danger streak | Several close calls/dodges in a row | Streak multiplier up to ×2 |
| Survived | Still alive when the round ends | 100 |

**Anti-farming**

- Close calls and dodges from the same hunter have a cooldown (about 3 s).
- Coins from close calls and dodges are capped per hunter per round, so friends can't farm each other by missing on purpose.

## Hunters

There are three kinds of hunter. Minions are numerous and weak, the Special Hunter is one strong player, and caught runners join the hunt.

| Hunter | Controlled by | Strength | How you become one |
| --- | --- | --- | --- |
| Minion | NPC | Slower than a good runner, can't wall run, more spawn over time | Spawned by the game |
| Special Hunter | One player per round | Faster than minions, has a lunge/grab and one ability (e.g. a big leap or a short reveal of nearby runners) | Picked at random each round, or guaranteed once with the "Be the Hunter" product |
| Caught runner | The player who was caught | Like a minion, but player-controlled | Getting caught |

**Rules**

- **Random pick is weighted:** players who haven't been the Special Hunter recently get a better chance.
- **Too few players** (e.g. under 3): an NPC takes the Special Hunter role, so the game still works on near-empty servers.
- **Caught runners stay hunters until the round ends** and earn coins for catches and assists.
- **Readable danger:** the Special Hunter is big and glowing, with a heartbeat sound that gets louder as it gets closer.
- **Win conditions:** runners win if anyone survives the timer. Hunters win if everyone is caught, which ends the round early.

## Maps and modifiers

Launch with one strong map (City) and add more maps and modifiers in updates. That steady flow of new content is the main reason to use rounds.

**Maps**

- **City (first map):** rooftops, fire escapes, billboards, cranes, alleys. Plenty of wall-run walls and gaps to vault.
- Later ideas: construction site, harbour with containers, shopping mall at night.
- Each map has 2–3 **changes during Frenzy** (e.g. a crane swings, a bridge falls, the power goes out).
- Maps should be compact enough that hunters and runners keep running into each other. Better too dense than too empty.

**Modifiers (one per round, picked in the vote)**

| Modifier | What changes |
| --- | --- |
| None | Normal round |
| Low Gravity | Higher jumps, floatier movement |
| Blackout | Dark map, runners have flashlights |
| Swarm | Twice as many minions |
| Giant Hunter | The Special Hunter is huge and strong, but slower on turns |
| Tiny Runners | Runners are small and fit through gaps |
| Floor Is Lava | The ground slows you down, so stay on rooftops |
| Speed Round | Everyone is faster, and the round is shorter |

## Progression and unlocks

Moves unlock with levels earned by playing. Coins buy looks only. That way progression feels rewarding without breaking "skill wins".

- **XP and levels:** from survival, close calls, catches and finished rounds.
- **Moves unlock by level** (e.g. grapple at level 5, glide at 10). New moves give **more options, not more power**: a grapple opens new routes but isn't faster than a good wall run.
- **Coins buy cosmetics:** skins, trails, trick effects, landing effects, hunter skins, lobby emotes.
- **Later:** daily challenges, achievements, leaderboards (best close-call streak, most survived rounds).

## Monetization

Sell looks, roles and fun for the whole server, never power. Everyone sees your movement, so effects and skins are the core of the shop.

| Item | Roblox type | Notes |
| --- | --- | --- |
| Trick effects and trails | Game pass bundles + Robux shop | Fire trail on wall runs, sparks on vaults, custom landing effects |
| Hunter skins | Robux shop | What you look like as the Special Hunter or as a minion. Makes getting caught fun to show off |
| Be the Hunter | Developer product | Guarantees you're the Special Hunter once. One per round: if someone already bought it, you're queued for the next round |
| Server events ("weather machine") | Developer product | Triggers a modifier or event for the whole server next round (e.g. Giant Hunter, Blackout), with a shout-out banner for the buyer |
| VIP | Game pass | Chat tag, double vote weight, +25% coins (coins only buy cosmetics, so this stays fair) |
| Season pass | Later | Free + paid track, new map or modifiers each season |
| Private servers | Built-in | Cheap, for playing with friends |
| Premium payouts | Built-in | Paid by Roblox for Premium players' playtime, no work needed |

**Never sell:** speed, revives, extra lives, shields, or anything that makes you harder to catch or a stronger hunter.

## Build order

Build the smallest version that answers one question: is it fun to take risks near hunters? Only then add content and monetization.

1. **Phase 1: playable core (playtest with friends)**
   - Basic movement: sprint, double jump, slide, wall run, wall jump, vault.
   - One small grey-box city map.
   - Floating lobby, round timer, beam up/down, 20 s vote (placeholder options are fine).
   - NPC minions, Special Hunter pick, catch → become hunter.
   - Coins with close calls and dodges, results screen.
   - Test: do players take risks on purpose? Do they want another round?
2. **Phase 2: feel and content**
   - Movement and camera polish, effects, sounds.
   - 3–4 modifiers and Frenzy map changes.
   - Saving (coins, level, cosmetics), levels and move unlocks, cosmetics shop.
   - Mobile controls tested on a real phone.
3. **Phase 3: launch prep**
   - Game passes and developer products.
   - Final City art, store icon and thumbnails.
   - Max players set, dev tools removed, saving tested with API access on, maturity questionnaire.
   - Soft launch, then full launch.

## Open questions

- [ ] Final name. "HUNTED" is TAKEN (official Dark Deception game, ~159M visits): must rename. Ideas: CLOSE CALL!, Hype Run, Prime Time Panic.
- [x] Who are the hunters? The game show's security robots (Phase 2 art).
- [x] Round length: start at 4 minutes, tune in playtests.
- [x] Max players per server: 12.
- [x] Two Special Hunters in full servers? Not at launch; later as a modifier.
- [x] Caught players become runners again? No, they hunt until the round ends.

## Decisions (2026-11-15)

Market check (Nov 2026): chase / 1-vs-many games are big but almost all horror (Forsaken ~73K, Violence
District ~29K with 278K event peaks, Evade ~31K). Banking loops work on Roblox but only in co-op PvE
(Deadly Delivery, HUSH, Dungeon Lootr). No game-show chase game found. Bright non-horror tone + banking = the gap.

**Twist: banking (push your luck).** Close calls, dodges and tricks fill a **bag** you carry (visible).
Coins are only kept when banked at a **cash drop**. 2-3 drops are active and **move every minute**.
Caught = you lose the whole bag; **the hunter who caught you gets 50 %**. Survival coins and the
"Survived" bonus go straight to the bank.

**Theme: a futuristic TV game show.** Lobby = studio blimp, beam up/down = the show's teleporter,
hunters = the show's security robots, modifiers = show twists, vote = audience vote, Frenzy = final
minute, close calls raise **Hype**, results = end credits with the best close call. Server events =
sponsor twists. Art comes in Phase 2; Phase 1 is grey box.

**Movement feel: flowing momentum.** Auto-sprint at a base speed; chaining moves (slide, wall run,
wall jump, vault, landing roll) builds speed up to a cap; breaking the flow (bonking a wall, hard
landing, standing still) loses it. Third-person camera. Every number in rules/parkour.toml.

**Core slice (build first):** movement + grey-box course + one NPC minion + close calls / dodges into
the bag + moving cash drops + minimal HUD. Then rounds, lobby, vote, Special Hunter, catch -> hunter.
