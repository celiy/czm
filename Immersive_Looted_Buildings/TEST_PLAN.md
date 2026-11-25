# Immersive Looted Buildings — test plan

Status: **suites written and passing (2026-11-25).** Harness: `dev/run-autotest.sh`, suites `ilb`, `ilb_persist`, `ilb_midsave` in `dev/CZMAutoTest/.../CZMAutoTest_ILB.lua`. Design: [DESIGN.md](DESIGN.md).

## Results so far

| Run | Where | Result |
|---|---|---|
| `ilb`, new game, vanilla looted off | Muldraugh (Medium + Overrun shops) | 39/39 |
| `ilb`, start 3 months after the apocalypse | West Point (116 High containers) | 39/39 |
| `ilb`, vanilla looted 100% | Muldraugh | 22/22 (late-cut part skipped: every shop was game-looted) |
| `ilb_persist`: save, continue | West Point | 3/3 + 8/8 |
| `ilb_midsave`: save without the mod, add, remove, add again | West Point | 2 + 6 + 2 + 4, all pass |

Covered: 1.1-1.3, 1.5, 1.8, 2.1-2.4, 2.6-2.8, 2.10-2.11, 3.1-3.4, 3.7-3.8, 4.2-4.4, 4.6-4.8, 5.2-5.3, 7.1, 7.3-7.7, 7.10-7.11, and from section 6: Enabled, exact curve, cut variation, stripped chance, useful first, passing window, cut abandoned.

Not yet covered in game: 1.6/1.7 (statistical check of the vanilla correction), 1.9, 2.5 (average loot left over 300 real containers), the start/peak/end/share/slowdown/initial options in game (covered by the curve unit test), room-list edits, loot respawn, live option changes, 3.5, 3.9/8.5 (multiplayer), 8.3 cost measure.

Harness notes: one run at a time (the runner holds a lock); `CZM_TEST_MODS` picks the mods, `CZM_TEST_CONTINUE=1` + `CZM_TEST_PHASE` run two-launch suites. The console line "invalid room metaID ... cell 25,33" appears on every continued West Point save, with or without the mod: it is the game's own.

## Principles

- **Never test the mod with itself.** Each suite re-implements the formulas independently and compares them with what the game shows.
- **Per-building oracle.** The decision for a building is deterministic (its id, the world seed and the day). For every real building in the tested areas the suite computes what the decision should be and checks that the containers show it: looted buildings are cut, the others are not. That is an exact check, not a statistical one.
- **Statistics only where needed.** Averages (looted share over many buildings, loot left over many containers) are compared with the formula with a 3-sigma tolerance: `3 x sqrt(p x (1 - p) / N)`.
- **Enough buildings.** Real towns have few shops of each tier, so the same decision function is also run over 100,000 synthetic building ids per day (exact share to about 0.5 points), and the real buildings of at least four towns (Muldraugh, West Point, Rosewood, Riverside, Louisville if loaded) check the integration.
- **Mind the house cap.** A house room gives no loot after about 100 refills (RESEARCH.md). Tests that refill a container stay under 80 fills for houses; shops have no cap.
- **Time is moved with the game clock** (days jumped one step at a time where "in use" matters, as in the Gasoline seat test), never by faking the mod's own variables.
- Fixed seed and repeated runs: a run must give the same result twice.

## 0. Harness work needed first

- Choose the town to start in (done: `CZM_TEST_SPAWN`), and run several towns in one go.
- Choose the mod list (to start a world **without** the mod, for the mid-save tests).
- **Continue a saved game** (second launch loads the save the first one made), and save on exit.
- Simulate the player's actions through the real game code paths: open a container (loot window refresh), move an item out and into a container (the real transfer function), so the hooks are exercised for real.
- Find buildings by tier, with their ids, for every tier.
- A read-only report of the mod's decisions (the "Log decisions" option) to compare with the oracle.

## 1. Buildings the game already looted are left alone

| # | Check | Expected |
|---|---|---|
| 1.1 | Find buildings the game looted (set the vanilla `MaximumLooted` to 100 so most are, `DaysUntilMaximumLooted` to 0) | They report `isAllExplored()` and have emptied containers |
| 1.2 | Tier rooms in those buildings, day 0 to 360 | No cut from the mod, no tag, no activity record, no decision logged |
| 1.3 | Buildings still standing, same towns | They get the mod's decision as usual |
| 1.4 | Burnt and other story buildings the game makes (`RBBurnt*` and similar) | Not touched (check what marks them) |
| 1.5 | The player exploring a building on foot (opening doors, rooms) | Does **not** make the mod treat it as game-looted: `isAllExplored()` stays false for an intact building, or another marker is used |
| 1.6 | Vanilla `MaximumLooted` 25, `DaysUntilMaximumLooted` 90, `RuralLooted` 0.5 (the preset), option "Count buildings the game already looted" **on** | The total share of looted High shops (game + mod) equals `C x f(day)` at days 0, 7, 30, 60, 90, 180, 360 within tolerance |
| 1.7 | Same, option **off** | The mod's share applies only to the buildings left; the total is `v + (1 - v) x C x f` |
| 1.8 | Vanilla `MaximumLooted` 0 | The mod alone gives exactly the table |
| 1.9 | Rural buildings (vanilla half chance) | Counted with their own `v(t)` |

## 2. The numbers: chance, loot left and the day curve

Run for **High, Medium and Low** and for **Overrun**, at days **0, 7, 30, 60, 90, 180, 360** (and one day after 360, to check it stays flat, and one day before `S`).

Expected values with the defaults (buildings the game did not loot):

| Day | 0 | 7 | 30 | 60 | 90 | 180 | 360 |
|---|---|---|---|---|---|---|---|
| High looted | 0% | 42.2% | 60.2% | 74.9% | 83.3% | 92.8% | 95.0% |
| High loot left | 100% | 59.9% | 42.8% | 28.9% | 20.8% | 11.8% | 9.8% |
| Medium looted | 0% | 33.3% | 47.6% | 59.1% | 65.8% | 73.3% | 75.0% |
| Medium loot left | 100% | 75.0% | 64.3% | 55.7% | 50.6% | 45.1% | 43.8% |
| Low looted | 0% | 26.7% | 38.0% | 47.3% | 52.6% | 58.6% | 60.0% |
| Low loot left | 100% | 86.7% | 81.0% | 76.4% | 73.7% | 70.7% | 70.0% |

| # | Check | Expected |
|---|---|---|
| 2.1 | Curve unit test: `f` at the days above, and its shape | 0 before `S`, `Fp` at `P`, 1 from `E` on, never decreasing, matches the table; the exact-curve option reproduces the user's table (100, 60, 40, 20, 15, 10) |
| 2.2 | Decision unit test, 100,000 ids per tier per day | Share looted = `C x f(day)` within 3 sigma |
| 2.3 | A building never changes its mind | Same building, same decision on every check, after a reload, and at any later day once looted |
| 2.4 | Oracle on every real High / Medium / Low building, each day | 0 mismatches between the oracle and the game |
| 2.5 | Loot left per tier (average over at least 300 containers per tier, looted or not) | Within 4 points of the table |
| 2.6 | Items removed in a looted building, per tier | Average equals the tier's cut (95 / 75 / 50%) within tolerance |
| 2.7 | Small containers (1 to 3 items) | The average cut is still right (random rounding), the container is never over-cut |
| 2.8 | Overrun rooms | Never cut; extra loot equals the bonus (25%) within tolerance |
| 2.9 | Rooms in no list (houses, clothing stores, anything else) | Identical to the game without the mod |
| 2.10 | Storage rooms (`grocerystorage`, `pharmacystorage`...) | Follow the tier of their shop and the same building decision |
| 2.11 | A game that starts 3 months after the apocalypse (`TimeSinceApo` 4) | Day 0 of the game already shows the curve at day 90 |
| 2.12 | Custom `S`, `P`, `E`, `Fp`, `k` | The curve follows (see section 6) |

## 3. Bases are not touched until the right day

Use real containers in a real shop and the real game paths for opening and moving items.

| # | Check | Expected |
|---|---|---|
| 3.1 | Player moves 3 or more items into a shop container (base) | The items are tagged; the building is recorded as a base |
| 3.2 | Days 1 to 59 after the last activity, containers opened again | **Nothing changes**, in any container of the building, seen or not |
| 3.3 | Day 61 (abandoned), container opened | Today's decision applies once; original leftovers are cut; **tagged items stay** |
| 3.4 | Any day, any state | A tagged item is never removed, and stays after being moved to another container |
| 3.5 | The player keeps visiting (activity every 20 days) | The building never becomes abandoned |
| 3.6 | A base with the building's roll "not looted today" | Nothing is cut even when abandoned |
| 3.7 | After the cut | A second open does not cut again |
| 3.8 | Option "Cut the leftovers of abandoned buildings" off | An abandoned base is still untouched, only unseen buildings are affected |
| 3.9 | Claimed safehouse (multiplayer) | Always in use |
| 3.10 | The cut runs before the loot window shows the container | The player never sees an item disappear |

## 4. Looted or passing through is not a base

The user's case: opened and looted normally, or only rendered the building for a moment, then returned about 30 days later.

| # | Check | Expected |
|---|---|---|
| 4.1 | Walk into a shop and out, opening nothing | No record at all; the building follows the untouched rules |
| 4.2 | Open containers and take items on one day, store nothing, leave | Recorded as passing / looted (fewer than 3 items stored, fewer than 3 days) |
| 4.3 | Return on day 15 | Nothing changes (inside the 30 day window) |
| 4.4 | Return on day 31 | Today's decision applies once, as for any abandoned building: seen containers lose their original leftovers, unseen containers get the cut |
| 4.5 | Same shop used as a base (stores items) and returned to on day 31 | Nothing changes (base window is 60 days) |
| 4.6 | The thresholds: 2 stored items, then 3; 2 days of activity, then 3 | The class changes exactly at the option values |
| 4.7 | Opening a container for the first time in a building the player never entered on foot (area seen at a distance) | Treated as untouched |
| 4.8 | Both windows changed (10 and 20 days; 90 and 180 days) | The classes follow the options |

## 5. Items the player stored

| # | Check | Expected |
|---|---|---|
| 5.1 | Stored items in a shop container, then the building is looted and abandoned | Stored items survive any number of cuts |
| 5.2 | Items taken out and put back elsewhere | Still tagged |
| 5.3 | Items put into a container outside the tier lists | Not tagged, not touched, no record |
| 5.4 | Items that enter by crafting or other non-transfer means | Documented limitation: not tagged |

## 6. Every sandbox option

Each option is set to at least two other values (including the extremes), a new game or reload is made where the option needs it, and the effect is checked.

| Option | Test | Expected |
|---|---|---|
| Enabled | off | The game behaves exactly as without the mod (no cut, no tag, no record, no log) |
| Looting starts on day | 0, 30, 100 | No building looted before `S`; the curve starts there |
| Looting peaks on day | 7, 3, 30 | `f(P)` = `Fp` at the new day |
| Looting ends on day | 360, 100, 720 | `f` = 1 from the new day on; flat after it |
| Share done at the peak | 44, 0, 100 | `f(P)` follows; 100 means the whole curve is done at the peak |
| Slowdown after the peak | 6.4, 1, 20 | The tail is flatter or steeper; `f(E)` still 1 |
| Exact looting curve | the user's table; an invalid string; empty | Table reproduced; invalid or empty falls back to the formula, with a console message |
| Already looted at the start | 0, 25, 100 | Day `S` already has that part of the final share |
| High / Medium / Low chance | 0, 50, 100 | Final share equals the value; 0 turns the tier off |
| High / Medium / Low cut | 0, 50, 100 | Average items removed equals the value; 100 empties looted buildings |
| Overrun extra loot | 0, 25, 100 | Extra loot equals the value; 0 gives vanilla loot |
| Room lists (each tier) | add a room to a tier; remove one; move one between tiers; a typo | The room follows its new tier; a name not in the game is ignored with a message |
| Cut variation | 0, 20, 50 | The mean cut is unchanged, the spread between buildings grows |
| Stripped chance | 0, 10, 100 | That share of looted buildings is emptied completely |
| Looters take useful items first | off / on | Same total cut, but food, medicine, tools and weapons go first; clothes and junk stay |
| Count buildings the game already looted | on / off | See 1.6 and 1.7 |
| Also apply to containers already filled | on / off | Off: a shop seen before the mod is never changed |
| Days until a looted-and-left building can be raided | 30, 10, 90 | The window follows (4.3, 4.4, 4.8) |
| Days until a base counts as abandoned | 60, 20, 180 | The window follows (3.2, 3.3, 4.8) |
| Items stored to count as a base | 3, 1, 10 | The class changes at the value (4.6) |
| Days of activity to count as a base | 3, 1, 10 | The class changes at the value (4.6) |
| Cut the leftovers of abandoned buildings | on / off | 3.8 |
| Apply when vanilla loot respawn refills a container | on / off, with `HoursForLootRespawn` > 0 | On: refilled containers keep the building's decision; off: refills are vanilla |
| Log decisions | on / off | One line per decision when on; none when off |
| Live change | change an option in a running game (the Sandbox Options mod, and the Sandbox Control right-click mod in the collection) | The next fill or open uses the new value; no restart |

## 7. New games and saves that did not have the mod

**New games** (`TimeSinceApo` 1 and 4, and a custom start day):

| # | Check | Expected |
|---|---|---|
| 7.1 | First run creates the world seed once | Same seed after save and load; decisions identical |
| 7.2 | Day 0 and later days of a fresh game | Section 2 numbers |
| 7.3 | Quit and continue | Every decision, tag and record identical |

**Saves made without the mod** (first launch without the mod, play and save; second launch with it):

| # | Check | Expected |
|---|---|---|
| 7.4 | Containers the game filled before | Not changed at load |
| 7.5 | A shop seen but never opened, opened now | Today's decision applies once (first-open check); with "Also apply to containers already filled" off, nothing |
| 7.6 | Buildings the player had already looted without the mod | They have no record, so the first open treats them as untouched: leftovers in containers the player emptied are few, and the cut is applied once |
| 7.7 | A player base set up before the mod | The first container the player opens gets today's decision; items stored from then on are tagged. **Known limit:** items stored before the mod cannot be told from the original loot (documented in the sandbox description) |
| 7.8 | Buildings not yet loaded | Fill-time decision for today's day |
| 7.9 | Buildings the game looted before the mod | Left alone (section 1) |
| 7.10 | Remove the mod and load again | The save loads; nothing breaks; tags are inert |
| 7.11 | Add it again | Decisions and records are the same as before |

## 8. Other checks

| # | Check | Expected |
|---|---|---|
| 8.1 | Together with Perishable Foods and Gasoline Degradation, all suites | Every suite of each mod still passes; Immersive Looted Buildings loads first |
| 8.2 | Loot other mods add to the same rooms | Handled by the same cut |
| 8.3 | Cost: 5,000 container fills with the mod off and on | The extra time stays negligible; no per-tick or per-minute handler exists |
| 8.4 | Many towns loaded at once | Memory and the saved table stay small (only used buildings in the table) |
| 8.5 | Multiplayer (dedicated server, if available) | Handlers on the server, options synchronised, the open event reaches the server |
| 8.6 | The 17 map-placed rooms | Unchanged |

## Pass criteria

All of sections 1 to 7 pass in a new game and in a save made without the mod, with every option tested, and the numbers match the tables above within the stated tolerances. Anything that cannot be tested (multiplayer without a server) is listed as untested in the report.
