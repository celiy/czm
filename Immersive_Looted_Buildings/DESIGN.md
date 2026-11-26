# Immersive Looted Buildings — design v2 (gradual loot loss)

Status: **implemented (code in `Contents/`), being tested in game.** The offline checks are in `dev/ilb_offline_test.lua`, the in-game suites in `dev/CZMAutoTest` (`ilb2`, `ilb2_persist`, `ilb2_midsave`). v1 is archived in [archive/DESIGN_v1.md](archive/DESIGN_v1.md) and [archive/TEST_PLAN_v1.md](archive/TEST_PLAN_v1.md). Research and evidence about the game's loot system: [RESEARCH.md](RESEARCH.md). Tests: [TEST_PLAN.md](TEST_PLAN.md).

## What the user asked for (2026-11-25)

- Every shop building **loses loot gradually** over time; no building is simply "raided" or "intact".
- Each tier has a **chance**: the share of its buildings that are guaranteed to lose the most. High 70%, Medium 50%, Low 30%.
- Each tier has a **reference table** of the loot those buildings keep over time. High: day 0 100%, day 7 60%, day 360 30%.
- The rest of the buildings, the ones that escaped the roll, still lose loot, but **less**, and not all the same amount. On day 360 a lucky High building keeps "a bit more than 30%", for example 40 or 50%.
- **Keep the looting curve with the peak day** from v1: fastest up to the peak, then slower until the end day.
- A building **used by the player as a base is never touched** by the mod. This replaces the v1 protection windows.
- **Remove the v1 logic** that copied the game's own "looted building" idea (all-or-nothing per building).
- Player items are never removed.
- Everything configurable in the sandbox, and every case tested (see TEST_PLAN.md).

## The model

### Inputs per tier

| Option | High | Medium | Low | Meaning |
|---|---|---|---|---|
| Chance (%) | 70 | 50 | 30 | Share of buildings in the **hit group**, which follows the full reference curve |
| Loot left at the peak (%) | 60 | 70 | 80 | Loot a hit building keeps on the peak day |
| Minimum loot at the end (%) | 30 | 50 | 70 | Loot a hit building keeps from the end day on |

Medium and Low use the values the user confirmed for v1 (option 3: minimum 50 / 70, peak 70 / 80). **To confirm with the user**, since in v2 the chance and the minimum are independent.

Shared options:

| Option | Default | Meaning |
|---|---|---|
| Looting starts on day `S` | 0 | |
| Looting peaks on day `P` | 7 | |
| Looting ends on day `E` | 360 | |
| Slowdown after the peak `k` | 6.4 | Shape of the tail, as in v1 |
| Exact curve | none | `day:percent` points of the share of the loss done; replaces the formula for every tier |
| Already lost at the start (%) | 0 | Lifts the curve at day `S` |
| Lucky buildings lose, at least (%) | 70 | Of what a hit building loses |
| Lucky buildings lose, at most (%) | 85 | Of what a hit building loses |

### The curve

`g(t)` is the share of the final loss done by day `t`, exactly the v1 curve:

- 0 before `S`, 1 from `E` on.
- From `S` to `P`: a straight line up to `Fp`.
- From `P` to `E`: `g = Fp + (1 - Fp) x (1 - e^(-k x)) / (1 - e^(-k))`, with `x = (t - P) / (E - P)`.

`Fp` is no longer an option. It comes from the tier's peak and minimum loot: `Fp = (1 - PeakLoot) / (1 - MinLoot)`, clamped to [0, 1]. High: `(1 - 0.60) / (1 - 0.30) = 0.571`. Medium `0.600`, Low `0.667`.

"Day" is days since the apocalypse: days played plus `(TimeSinceApo - 1) x 30`, as in Perishable Foods and v1.

### Each building

Each building gets two permanent random numbers in [0, 1) from its map position and the world seed (the v1 hash, which was checked for uniformity and independence):

- `u1` decides the group: **hit** if `u1 < Chance`, otherwise **lucky**.
- `u2` places a lucky building inside the lucky range.

Its **loss strength** `s`:

- Hit building: `s = 1`.
- Lucky building: `s = LuckyMin + (LuckyMax - LuckyMin) x u2`. With the defaults, between 0.70 and 0.85.

The **loot the building keeps** on day `t`:

`K(t) = 1 - s x (1 - MinLoot) x g(t)`

`K` only goes down over time, and every building gets lower than it was the day before. A hit building follows the reference table exactly. A lucky building keeps more, by a random amount fixed for that building.

Group and strength are computed, never stored, and they never change: the same building always gets the same answer after a reload.

### Containers

The building's `K(t)` is applied to each of its containers in tier rooms. Each container stores one number in the parent object's mod data, `A`: the share of its original loot already kept, 1 after the fill.

When the container is updated on day `t`:

1. Compute the target `K(t)` of its building.
2. If `K(t) < A`, remove the share `1 - K(t) / A` of the removable items, with random rounding so small containers average out.
3. Set `A = K(t)`.

Removable items are every item **except** items with the `ILB_player` tag (put there by the player) and keys. Items are counted one by one (a stack of 20 nails is 20 items, a water bottle is one item).

Because the removal is a share of what is left, a player who takes half the items out does not make the container lose more: the next update removes the same share of what remains.

Loot is never added back, except the overrun bonus.

**When a container is updated.** Only at moments when nobody has seen its contents:

- **Fill** (`OnFillContainer`): the game just created the contents. The container goes to today's `K`. The entry waits in a queue until the building is fully loaded, so buildings the game itself looted are recognised (see below).
- **Building load** (`LoadChunk`): a chunk with part of a shop was loaded, so the shop was out of reach until now. The shop is queued the same way and, once fully loaded, every container of its tier rooms goes to today's `K`. Which shops touch which chunk comes from an index built once from the map data (`getMetaGrid():getBuildings()`), so the event costs one table lookup.
- **Away**: a shop the player looked at is watched; when no player is within `ProtectRadius` while it is still loaded, its due containers are updated.
- At most **once per in-game day** per container (a fresh fill or refill excepted).

### Never in front of the player

This follows the user's idea: a system that processes a shop when it loads (when the player arrives or it renders), and after that removes nothing while the player is close or looting.

- **Seen.** When the loot window lists a container of a shop, the shop is marked *seen* (in memory). A seen shop gets no removal at all until the player is farther than `ProtectRadius` (default 200 tiles) or the shop unloads.
- **First the load, then the player.** The loot window runs, before it shows the items, anything still waiting in the queue for that shop: its load and any fill. So teleporting next to a shelf still gives the shop its loss first, and then nothing more while the player stays.
- **Due, not done.** A removal that cannot run (the shop is seen) leaves `A` where it was; the container is *due* (`A > K(today)`), which needs no extra saved data. The shop goes into the in-memory watch set.
- **Leaving.** `OnPlayerMove` checks the watch set every 30 moves, and only when it is not empty. A shop that is no longer loaded is dropped from it (its next load handles it). A loaded shop with no player within `ProtectRadius` is updated and dropped. With the default 200 tiles the shop is usually unloaded before the player is that far, so in practice the loss is applied at the shop's next load, which is the same moment for the player: they come back and find the shop already changed.
- **Reload of a save.** The watch set is not saved. Loading the save loads the shops again, so due containers are updated at that load, before the player looks.
- **Multiplayer.** "Near" uses every online player's position on the server; the loot-window part runs only in singleplayer for now.

The loss is never smaller because of this, only later: the removal always goes to today's `K`.

Containers filled before the mod was added have no `A`: they start at `A = 1` at their first update, which happens when their shop loads (adding the mod to a save loads every shop near the player again).

### Overrun places

Hospitals, prisons, police and army rooms are never touched by the loss. They get the bonus (25% by default) **once**, at the first fill: copies of the container's own items. The bonus does not grow over time and is not given again on later updates. A refill by the game's loot respawn can receive it again if "apply on loot respawn" is on.

### Player bases

A building is a **base** once the player, in its tier rooms:

- stores `BaseItems` items or more (default 3), **or**
- has activity on `BaseActiveDays` different days or more (default 3).

Activity for the base rule is a container listed in the loot window, an item taken out, or an item put in. **Entering the building counts as a visit for the recent-visit pause, but not as a day of activity**: otherwise walking through a shop on three days would make it a base that never loses loot. Entering is checked only when the player's building changes, so it costs one lookup per move.

**A base never loses loot.** The mod gives it no removal at all, from the day it becomes a base on. Loss it had already caused before that stays, and nothing is added back. This is simpler than v1: no 30 / 60 day windows, no "abandoned" state for bases.

If a building becomes a base later (the player stores items or comes back on several days), its loss stops from that day on. It is evaluated at each update, so the change is picked up the first time the building is updated after it becomes a base.

A claimed safehouse (multiplayer) counts as a base.

### Recent visit: the loss pauses and then restarts gradually

A building that is not a base, and that the player has recently visited, pauses its loss. A **visit** is either:

- opening a container of one of its tier rooms (loot window), taking or putting an item, **or**
- entering the building (the player's position moves from outside into one of its squares).

After a visit, the building counts as visited for `RecentVisitDays` days (default **14**). During those days its loss clock does not run.

**The loss clock.** Each non-base building that has ever been visited has an effective day `E`, which is the day the loss curve reads, instead of the calendar day. Three saved values:

- `E`: the effective day.
- `S`: the calendar day `E` was last brought up to date (the sync day).
- `L`: the day of the last visit.

Rules:

1. **Sync** at a day `t`: `E = E + max(0, t - max(S, L + RecentVisitDays))`, then `S = t`. Only the days after the recent-visit window count.
2. **Visit** on day `t`: sync to `t` first (with the old `L`), then `L = t`.
3. **Update** of a container on day `t`: sync to `t`, then the target is `K(E)`, not `K(t)`.
4. **First visit** of a building (no record): `E = S = L = t`. Before it, the building followed the calendar, so nothing changes at that moment.

So a building visited on day 0 and not again: `E` stays 0 until day 14, then grows one day for each day from then on. On day 20 it reads the curve at day 6, on day 30 at day 16. The loss restarts from where it stopped, with no jump. The loss rate after the restart is the normal rate of the curve.

A building that is visited every 14 days or less never loses loot while it stays a non-base, because `E` never moves. A building the player never visited follows the calendar from day 0.

Each step is a few arithmetic operations and one table write per building. Nothing runs on a timer.

**Base.** A base does not use `E` at all: its loss stops on the day it becomes a base, and nothing is removed afterwards. Loss it caused before that stays.

**What is saved.** The v1 activity record `used[buildingKey] = {last, days, stored}` gets two more fields: `E` and `S`. `last` is `L`. The record is saved with the world, so the clock survives save and load.

The recent-visit pause and the protect radius work together. A removal that is due only waits for the player to be farther than `ProtectRadius` from the building. The recent-visit pause changes what is due, not when it is applied.

Items the player puts in any tier container get the `ILB_player` tag and are never removed, base or not.

### Buildings the game itself looted

The game's own "looted buildings" option empties about 80% of each container of some buildings and marks them. These are **left alone**: the mod gives them no loss. They are recognised as in v1: all explored and not visited by a player, checked once the building is fully loaded.

The v1 option "count buildings the game already looted" (which raised the mod's chance to keep the total on the curve) is **removed**: with a gradual loss there is no share to correct.

## Expected numbers with the defaults

Loot kept, in percent of the original loot:

**High** (chance 70%, peak 60%, minimum 30%)

| Day | 0 | 7 | 30 | 60 | 90 | 180 | 360 |
|---|---|---|---|---|---|---|---|
| Hit buildings (70%) | 100 | 60.0 | 49.8 | 41.4 | 36.6 | 31.3 | 30.0 |
| Lucky buildings, the least they keep | 100 | 66.0 | 57.3 | 50.2 | 46.1 | 41.6 | 40.5 |
| Lucky buildings, the most they keep | 100 | 72.0 | 64.8 | 59.0 | 55.6 | 51.9 | 51.0 |
| Average of all High buildings | 100 | 62.7 | 53.1 | 45.4 | 40.9 | 35.9 | 34.7 |

**Medium** (chance 50%, peak 70%, minimum 50%)

| Day | 0 | 7 | 30 | 60 | 90 | 180 | 360 |
|---|---|---|---|---|---|---|---|
| Hit buildings (50%) | 100 | 70.0 | 63.2 | 57.6 | 54.4 | 50.8 | 50.0 |
| Lucky, least kept | 100 | 74.5 | 68.7 | 64.0 | 61.3 | 58.2 | 57.5 |
| Lucky, most kept | 100 | 79.0 | 74.2 | 70.3 | 68.1 | 65.6 | 65.0 |
| Average | 100 | 73.4 | 67.3 | 62.4 | 59.5 | 56.4 | 55.6 |

**Low** (chance 30%, peak 80%, minimum 70%)

| Day | 0 | 7 | 30 | 60 | 90 | 180 | 360 |
|---|---|---|---|---|---|---|---|
| Hit buildings (30%) | 100 | 80.0 | 76.6 | 73.8 | 72.2 | 70.4 | 70.0 |
| Lucky, least kept | 100 | 83.0 | 80.1 | 77.7 | 76.4 | 74.9 | 74.5 |
| Lucky, most kept | 100 | 86.0 | 83.6 | 81.7 | 80.5 | 79.3 | 79.0 |
| Average | 100 | 83.2 | 80.3 | 77.9 | 76.6 | 75.1 | 74.7 |

A simulation of 100,000 High buildings on day 360 gives 69.9% of them at exactly 30% and the rest between 40.5% and 51.0%, average 34.7%.

These are shares of the **items the game put in the container**. Containers are small and items are whole, so a single container varies around these numbers; the averages hold over many containers.

## Sandbox options (v2)

| Option | Default | Notes |
|---|---|---|
| Enabled | on | |
| Looting starts / peaks / ends on day | 0 / 7 / 360 | |
| Slowdown after the peak | 6.4 | |
| Exact curve | none | Share of the loss done, `day:percent`; invalid text falls back to the formula with a console message |
| Already lost at the start (%) | 0 | |
| High: chance / loot at the peak / minimum loot (%) | 70 / 60 / 30 | |
| Medium: chance / loot at the peak / minimum loot (%) | 50 / 70 / 50 | |
| Low: chance / loot at the peak / minimum loot (%) | 30 / 80 / 70 | |
| Lucky buildings lose at least / at most (%) | 70 / 85 | Of what a hit building loses |
| Overrun: extra loot (%) | 25 | Once, at the first fill |
| Room lists (High, Medium, Low, Overrun) | v1 lists | Text, `;` or `,` separated |
| Looters take useful items first | off | Same amount removed, food, medicine, tools and weapons go first |
| Protect radius (tiles) | 200 | No item is removed while the player is this close to the building; removal waits until they are farther away |
| Apply on the game's loot respawn | on | A refill goes to the building's `K(t)` and the overrun bonus is given again |
| Items stored to count as a base | 3 | |
| Recent visit: days the loss pauses after a visit (non-base) | 14 | `RecentVisitDays`. 0 turns the pause off |
| Days of activity to count as a base | 3 | |
| Log decisions | off | One console line per building and update |

**Removed from v1:** HighCut / MediumCut / LowCut, the global and per-tier peak share (now derived), CutVariation and StrippedChance (replaced by the lucky range), CountVanillaLooted, PassingDays, BaseDays, CutAbandoned.

When a game made with v1 is loaded, the removed options are ignored and the new ones take their defaults.

## How it will be built

Changes to the v1 code, file by file:

- `ILB_Core.lua`
  - Options: new per-tier `PeakLoot` and `MinLoot`, `LuckyLossMin`, `LuckyLossMax`. `Fp` derived per tier.
  - Keep: the curve `g`, the hash, the room lists, `day()`, `cutContainer` (now called with the share `1 - K/A`), the overrun bonus, the useful-first ordering, the activity record and `isBase`.
  - New: `ILB.strength(def, tier)` (hit or lucky `s`), `ILB.keep(def, tier, day)` (`K(t)`), `ILB.update(container, def, tier, day)` (steps 1-3 above, returns removed and considered).
  - Container state: `A` and the day of the last update, packed in one number per container type, as v1 packs state and day.
  - Remove: `isLooted`, `threshold`, `vanillaShare`, `cutFor`, `mayChange` and the passing / abandoned logic.
- `ILB_Fill.lua`: same queue; it calls `ILB.update` instead of `ILB.apply`; overrun bonus only when the container has no state yet.
- `ILB_Client.lua`: same hook; for each container in a tier room of a non-base building, `ILB.update` if the last update was on an earlier day; then record the activity.
- `ILB_Transfer.lua`: unchanged (tag and stored count).
- Sandbox options, EN and PT-BR translations, workshop.txt table.

Data that v1 games already have: container states from v1 (checked / cut / skipped) are read as "no `A` yet" (start at 1), except skipped ones (game-looted buildings), which stay skipped. v1 activity records are kept; a v1 base becomes a v2 base by the same thresholds.

## Optimization

Unchanged from v1, as it was measured (1.7 microseconds per fill for a house container):

- No timer: no tick, minute or square-load handler. The fill queue ticks only while it has entries.
- Fill: one table lookup for houses.
- Loot window: one lookup per listed container. Nothing is removed there.
- Player move: `OnPlayerMove` looks up the player's building (visit) and checks the watch set every 30 moves, only when it has entries.
- Building load: one table lookup per loaded chunk in the shop index.
- Saved data: the seed, the small activity table (only buildings the player used) and one number per tier container.

## Compatibility and limits

- The watch set is not saved: after a reload, due containers are updated when their shop loads.
- Safe to add mid-save: containers already filled start at `A = 1` and go to today's loot when their shop loads. Items the player stored before the mod existed have no tag and cannot be told apart from the original loot. Safe to remove: tags and numbers stay in the save, inert.
- Loot other mods add to the same rooms is counted in the same share.
- Not covered: the 17 rooms the game fills from the map (clothing stores, bookstores, army surplus...), zombies, vehicles, items on the floor.
- A container the player never looks at after its fill keeps the fill-day loot until the player comes to it; the loss is applied before the player sees it, so the result looks the same.
- Items that enter a container by crafting or other non-transfer means are not tagged.
- Multiplayer: fill, load, transfer and the watch run on the server; the loot-window part (seen marks) runs only in singleplayer until an open event is sent to the server.

## Questions for the user

1. Medium and Low: are the minimum 50 / 70 and peak 70 / 80 right for v2?
2. The lucky range: 70 to 85% of the hit loss gives a High lucky building 40.5 to 51% on day 360, as in the example. Keep it?
3. Should buildings the game already looted stay untouched (as planned) or also lose loot gradually?
4. Decided: the loss happens only when the player is outside the building and beyond the protect radius. The radius defaults to 200 tiles, and is a sandbox option.
5. Decided: removal waits until the player leaves. The first look of a day shows the previous day's loot, and the loss appears when the player walks away.
