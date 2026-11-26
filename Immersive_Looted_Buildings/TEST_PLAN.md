# Immersive Looted Buildings — test plan v2

Status: **implemented and tested (2026-11-26).** Design: [DESIGN.md](DESIGN.md). The v1 plan and its results are in [archive/TEST_PLAN_v1.md](archive/TEST_PLAN_v1.md).

## How to run

- Offline (plain Lua 5.4, 2 seconds): `lua dev/ilb_offline_test.lua`, 87 checks of the formulas, groups, containers, bases and base signs, the visit clock and the options, with fake game objects.
- In game: `dev/run-autotest.sh` with `CZM_TEST_MODE=ilb2` (phases `full`, `series`, `vanilla`, `apo`), `ilb2_persist` (`save`, `load`) and `ilb2_midsave` (`prep`, `add`, `remove`, `readd`). The runner renames the test copies of the mods to `czmtest_<id>` so a Workshop subscription cannot replace them.

## Results

| Run | Where | Result |
|---|---|---|
| Offline | | 87/87 |
| `ilb2` full | West Point | 67/67 |
| `ilb2` base (signs of a player base) | West Point | 21/21 |
| `ilb2` series | Riverside 6270,5270 | 38/38 |
| `ilb2` series with overrun | Muldraugh | 42/42 |
| `ilb2` vanilla looted 100% | West Point | 3/3 |
| `ilb2` start 3 months after the apocalypse | West Point | 2/2 |
| `ilb2_persist` save and load | West Point | 3/3 + 6/6 |
| `ilb2_midsave` without the mod, add, remove, add again | West Point | 2 + 4 + 2 + 3, all pass |
| Gasoline Degradation and Perishable Foods suites | | 33/33 and 34/34 |

Covered in game: 1.1-1.5, 2.1-2.5, 3.1-3.5, 3.9, 3.10, 4.1, 4.4, 4.6, 4.10, 5 (Enabled, respawn on and off, log decisions, radius), 6.1-6.4, 7.1, 8.1, 8.3, 8.4, 9.1-9.7, 9.10, 9.11, 10.1, 10.3-10.5. Covered offline only (the same functions, with fake objects): 3.6-3.8, 4.5, 4.7, 4.8, the curve, chance, peak, minimum, lucky range and room list options, 10.2, 10.6-10.9, 10.12, 10.13 arithmetic. Base signs (4.11-4.18), in game: a barricade added without a player action is not a sign; the player barricading, placing furniture or plugging in a generator (the real, hooked vanilla actions) makes a base; a running generator and furniture moved by a player found at load make a base; building against the wall counts (handler of the hooked build action, the full build is not run in the test), 4 tiles away does not; a shop only visited is not a base. Not covered: multiplayer (9.12, no dedicated server installed), 5.4 (items entering by crafting are not tagged, documented).

## Principles

- **Never test the mod with itself.** The suite re-implements `g(t)`, `Fp`, `s` and `K(t)` independently and compares them with what the game shows.
- **Two kinds of checks.**
  - Exact checks for one building or one container, where the result is fixed.
  - Statistical checks over many buildings or containers, with a 3-sigma tolerance.
- **Synthetic buildings** (fake map positions, 20,000 per run) give the shares and the distribution quickly. **Real containers** check that the game does what the numbers say.
- **Time is moved with the game clock** (`setNightsSurvived`), one step at a time where it matters.
- **Keep runs fast.** One launch for the main suite, short launches only for what needs a new world or a reload. No long tours of the map. The test player's death does not stop a suite; it is only logged.
- The default numbers are checked once in full. For other sandbox values, the curve and the shares are checked through the same functions, not by repeating every case.

## 1. The curve and the reference tables

| # | Check | Expected |
|---|---|---|
| 1.1 | `Fp` per tier from peak and minimum loot | High 0.571, Medium 0.600, Low 0.667 |
| 1.2 | `g(t)` on days 0, 3.5, 7, 30, 60, 90, 180, 360, 400 and a step of 0.5 days up to 800 | Matches the formula, never decreases, 0 before `S`, 1 from `E` on |
| 1.3 | Hit building `K(t)` per tier on days 0, 7, 30, 60, 90, 180, 360 | The DESIGN tables: High 100 / 60 / 49.8 / 41.4 / 36.6 / 31.3 / 30, Medium and Low likewise |
| 1.4 | Lucky building `K(t)`, least and most | DESIGN tables, for example High on day 360 between 40.5 and 51.0 |
| 1.5 | Average `K(t)` over 20,000 synthetic buildings per tier and day | DESIGN averages within 3 sigma, for example High day 360 34.7% |

## 2. Groups and distribution (which buildings are most affected)

Over 20,000 synthetic buildings per tier, on days 7, 90 and 360:

| # | Check | Expected |
|---|---|---|
| 2.1 | Share in the hit group | Chance (70 / 50 / 30%) within 3 sigma, on every day: the group does not change with time |
| 2.2 | Every hit building | Keeps exactly the hit `K(t)` |
| 2.3 | Every lucky building | Keeps more than a hit building and stays inside the lucky range |
| 2.4 | Lucky `s` spread | Uniform between 0.70 and 0.85: ten buckets each 10% within tolerance |
| 2.5 | Summary printed per tier and day | Share at the minimum, lucky minimum / average / maximum kept, overall average, the 10 most and 10 least affected buildings with their `K` |
| 2.6 | A building's group and `s` after a reload and on any later day | Unchanged |
| 2.7 | Each building over days 0 to 400 | `K` never goes up |

## 3. Loot that disappears in real containers

Real shop containers near the spawn (West Point: about 116 High containers; Muldraugh for Medium and Overrun).

| # | Check | Expected |
|---|---|---|
| 3.1 | Fill on day 0, then the clock moved to day 7, 30, 90, 360, with an update (loot window) after each step | Each container's item count follows `K(t)` of its building: removed per step = share `1 - K/A` of what is left, within random rounding |
| 3.2 | Over all tier containers, items left / items at fill, per tier and day | Matches the average `K(t)` within tolerance |
| 3.3 | Hit and lucky containers apart | Hit ones match the hit table, lucky ones sit between the lucky minimum and maximum |
| 3.4 | A container filled first on day 90 | Already at day 90's `K` at the fill |
| 3.5 | Two looks on the same day | The second one removes nothing |
| 3.6 | A container the player half emptied, then a day later | The update removes the share of what is left, not more |
| 3.7 | Small containers (1 to 3 items), 2,000 repetitions | Average removed share right, never more than the items there |
| 3.8 | Useful items first, on | Same count removed, food and medicine go before junk |
| 3.9 | Overrun container | Bonus once at the fill (25% within tolerance), nothing removed on later days, no second bonus |
| 3.10 | Rooms outside the lists, houses | No state, nothing removed, item counts unchanged across days |

## 4. Player items and bases

| # | Check | Expected |
|---|---|---|
| 4.1 | Items moved by the player into a tier container (real transfer function) | Tagged; never removed across all later updates, up to day 400 |
| 4.2 | A tagged item moved to another container and back | Still tagged, still kept |
| 4.3 | Keys in a container | Never removed |
| 4.4 | 2 items stored, then 3 | Not a base, then a base |
| 4.5 | Activity on 2 days, then 3 | Not a base, then a base |
| 4.6 | A base building, the clock moved 30, 90, 360 days, containers looked at and the building entered | Nothing removed, from any container of the building, ever |
| 4.10 | A non-base building that loses loot, then becomes a base (3 items stored) | Loss stops from that day on; the loss already done stays; no further removal |
| 4.7 | A non-base building the player only looked at once (see section 10) | Loses loot as the curve says, after the 14-day pause, from where the clock stopped |
| 4.8 | Base thresholds changed (1 and 10) | Classes change at the new values |
| 4.9 | The real loot window: standing next to a container on a new day | The update runs before the items are shown |

## 5. Sandbox options

Each option set to at least two other values, checked through the functions (fast) and, where it touches the game, on one real container.

| Option | Values | Expected |
|---|---|---|
| Enabled | off | No state, no removal, no tag |
| Start / peak / end day | 30, 3, 100 / 720 | `g` follows; nothing lost before `S`; flat from `E` |
| Slowdown | 1, 20 | Tail shape changes, `g(E) = 1` |
| Exact curve | user table, invalid text | Followed; invalid falls back with a console message |
| Already lost at the start | 25, 100 | `g(S)` lifted |
| Chance per tier | 0, 50, 100 | Hit share follows; 0 means every building is lucky, 100 every building is hit |
| Loot at the peak per tier | 40, 90 | Hit `K(P)` equals it |
| Minimum loot per tier | 0, 60, 100 | Hit `K(E)` equals it; 100 means no loss at all |
| Peak loot below the minimum | 20 with minimum 30 | `Fp` clamped to 1, no error |
| Lucky range | 0-0, 50-100, 100-100, min above max | 0-0: lucky buildings lose nothing; 100-100: same as hit; swapped values are read in order |
| Overrun bonus | 0, 100 | No bonus; double |
| Room lists | add, remove, move, typo, live change | Rooms follow their new tier at the next fill or look |
| Useful first | on | 3.8 |
| Update when looking | off | After the fill, nothing changes on later days |
| Apply on loot respawn | on / off | Refill goes to `K(t)` and gets the overrun bonus / refill left as the game made it |
| Base thresholds | 1, 10 | 4.8 |
| Protect radius | 0, 50, 400 | 9.7 |
| Recent visit pause (days) | 0, 1, 30 | 10.12 |
| Log decisions | on | One line per update, none when off |

## 6. Time, saves and mid-save

| # | Check | Expected |
|---|---|---|
| 6.1 | Game started 3 months after the apocalypse | Day 0 of the game already uses day 90's `K` |
| 6.2 | Save, quit, continue | Seed, `A` of every container, tags, base records identical; next update continues from `A` |
| 6.3 | Save made without the mod, mod added on day 60 | Containers untouched at load; first look takes them to day 60's `K` |
| 6.4 | Mod removed, save loaded, mod added again | Loads fine; numbers and tags kept; updates continue |
| 6.5 | A v1 save (v1 states and records) | v1 states read as described in DESIGN; no error |

## 9. Never in front of the player

| # | Check | Expected |
|---|---|---|
| 9.1 | Player inside a shop (within `ProtectRadius`), the clock moved one day, container updated by the window | Item count unchanged; container is due (`A > K(today)`); building in the deferred set |
| 9.2 | Same, one step further: player stands still for 200 ticks next to the containers | Still no removal |
| 9.3 | Teleport into a shop on a day when containers are due | Nothing removed on arrival |
| 9.4 | Player walks out past `ProtectRadius` | Due containers of that building updated; item count equals `K(today)` within rounding; deferred set entry removed |
| 9.5 | Leaving the building again, and coming back the same day | No second removal; the same day never removes twice |
| 9.6 | Items shown in the window | Count equals the count before the step, every time the window is open |
| 9.7 | Radius option 0, 50, 200 (default), 400 | 0: removal as soon as the player is outside the building; larger values wait longer, same final count |
| 9.8 | Two buildings, player close to one and away from the other | Only the away building is updated |
| 9.9 | The player's own tagged items during deferred removal | Never removed |
| 9.10 | Save while a removal is deferred, quit, load, walk away | Removal happens on leaving; final count equals the one of 9.4 |
| 9.11 | Cost with an empty deferred set | `OnPlayerMove` returns at once (measured per call, microseconds) |
| 9.12 | Multiplayer (if a server is available): second client nearby | Server does not remove while any player is near; untested if no server |

## 10. Recent visit: the loss pauses, then restarts gradually

Use a building the player did not use before the test, unless the case needs a base.

| # | Check | Expected |
|---|---|---|
| 10.1 | Visit on day 0 (container opened), clock moved to day 13 | Nothing removed; `E = 0` |
| 10.2 | Clock at day 14 | Still nothing removed; `E = 0` |
| 10.3 | Clock at day 20 | `E = 6`: containers go to `K(6)`, not `K(20)` |
| 10.4 | Clock at day 30 | `E = 16`: containers go to `K(16)`; the loss is gradual, no jump at day 14 |
| 10.5 | Only entering on day 0 (no container opened) | Same as 10.1 to 10.4: entering counts as a visit |
| 10.6 | Visit on day 0, then on day 10, clock at day 23 | `E = 0` until day 24; `E = 9` on day 33 (the pause restarted on day 10) |
| 10.7 | Building never visited, clock at day 90 | `E = 90`: follows the calendar, no pause |
| 10.8 | First visit on day 60, then the clock at day 74 and 100 | `E = 60` at the first visit, still 60 at 74, `E = 86` at 100 |
| 10.9 | Continuous visits every 14 days for 360 days | `E` never moves; no removal in the whole run |
| 10.10 | Base building (3 items stored) with a long clock | Nothing removed; `E` not used |
| 10.11 | Non-base building loses loot on day 30, then becomes a base (3 items stored) on day 40 | Nothing removed after day 40; loss before day 40 stays |
| 10.12 | `RecentVisitDays` 0, 1, 30 | 0: no pause, `E` = calendar; others move the restart day |
| 10.13 | Visit on day 0, save on day 20 (stored E = 0, S = 0, L = 0, no sync yet), load on day 25 | The first sync after the load gives `E = 11` (25 minus the 14-day pause); the same as a run without the save |
| 10.14 | Player's tagged items during and after the pause | Never removed |
| 10.15 | Cost of the visit check and the sync (a few thousand building updates) | A few microseconds each; no timer |

## 7. Buildings the game itself looted

| # | Check | Expected |
|---|---|---|
| 7.1 | Vanilla looted at 100% | Those buildings are marked skipped, no update, no removal, on any day |
| 7.2 | Player walks into an intact building | Not mistaken for a game-looted one |

## 8. Robustness and cost

| # | Check | Expected |
|---|---|---|
| 8.1 | 50,000 fills of a house container | A few microseconds each (v1 measured 1.7) |
| 8.2 | No tick, minute or square-load handler | Only the fill queue ticks while it has entries |
| 8.3 | Lua errors in the console across every run | None from the mod or the test harness |
| 8.4 | The Gasoline Degradation and Perishable Foods suites with the new harness | Still pass |

## Runs

About six launches, run one after another by a subagent:

1. Main suite (sections 1, 2, 3, 4, 5, 7.2, 8.1-8.2, 9, 10) in West Point, new game, vanilla looted off.
2. Main suite in Muldraugh (Medium and Overrun rooms).
3. Vanilla looted at 100% (section 7.1).
4. Game started 3 months after the apocalypse (6.1).
5. Save and continue (6.2), and the mid-save chain without the mod / add / remove / add again (6.3, 6.4), as two-launch suites.
6. Regression of the other mods' suites (8.4).

Each run prints the per-tier summary of 2.5 so the most and least affected buildings can be read straight from the results.
