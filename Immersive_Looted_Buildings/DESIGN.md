# Immersive Looted Buildings — design v2 (gradual loot loss)

Status: **design only.** The code in `Contents/` still implements v1 (a building is either raided or intact). v1 is archived in [archive/DESIGN_v1.md](archive/DESIGN_v1.md) and [archive/TEST_PLAN_v1.md](archive/TEST_PLAN_v1.md). Research and evidence about the game's loot system: [RESEARCH.md](RESEARCH.md). Tests: [TEST_PLAN.md](TEST_PLAN.md).

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

**When a container is updated:**

- **At the fill** (`OnFillContainer`): the container goes to today's `K(t)`, once the building is fully loaded (the queue from v1 stays). The items are created by this step, so nothing visible is removed.
- **When the player looks at it** (the loot window, `buttonsAdded`): the update of the day is **not** run while the player is in front of the building. See "Never in front of the player" below.
- At most **once per in-game day** per container.

### Never in front of the player

The mod never removes items while the player is close to the building. "Close" means within `ProtectRadius` tiles of any square of the building (default 12, sandbox option). This also covers teleporting into a shop: the player is close, so nothing is removed, and the removal happens when they leave.

How it works:

1. **Due, not done.** When an update would remove items but the player is close, nothing is removed and `A` stays where it was. The container is now *due*: `A > K(today)`. This needs no extra saved data, because "due" is just that comparison.
2. **Deferred set.** The building is added to an in-memory set `ILB.deferred` (building key only, not saved). Adding it costs one table write.
3. **Leaving.** The `OnPlayerMove` event checks the set only when it is not empty. When the player is more than `ProtectRadius` away from every deferred building, the mod runs the update on each container of that building that is due, and removes the set entry. The removal is the share `1 - K(today) / A`, so the result is exactly today's `K(t)`; nothing is lost twice.
4. **Reload.** The set is not saved. After a reload the set is empty, and a due container is handled the next time the player is away from its building and comes back, or leaves it. Nothing is lost: `A` is still the old value, so the target is reached at that point.
5. **Multiplayer.** The server knows every player's position, so the same check runs there for each building in the set.

Items are never removed in front of the player, and a deferred removal does not change the total loss: the loss is applied later, not less.

Why not at the look: opening a container means standing in front of it, so an update at the window would remove items the player is looking at. The cost is that the first look of the day shows the previous day's loot, and the loss appears when the player walks away. For a container the player stays next to, the loss can wait as long as they stay.

Containers filled before the mod was added have no `A`: they start at `A = 1` on their first update.

### Overrun places

Hospitals, prisons, police and army rooms are never touched by the loss. They get the bonus (25% by default) **once**, at the first fill: copies of the container's own items. The bonus does not grow over time and is not given again on later updates. A refill by the game's loot respawn can receive it again if "apply on loot respawn" is on.

### Player bases

A building is a **base** once the player, in its tier rooms:

- stores `BaseItems` items or more (default 3), **or**
- has activity on `BaseActiveDays` different days or more (default 3).

Activity is opening a container (loot window), taking an item out or putting one in, the same events as v1.

**A base is never touched again by the mod**, no matter how long the player is away. This is simpler than v1: no 30 / 60 day windows, no "abandoned" state.

A building the player only passed through (fewer items and days than the thresholds) keeps losing loot normally. A claimed safehouse (multiplayer) counts as a base.

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
| Protect radius (tiles) | 12 | No item is removed while the player is this close to the building; removal waits until they leave |
| Apply on the game's loot respawn | on | A refill goes to the building's `K(t)` and the overrun bonus is given again |
| Items stored to count as a base | 3 | |
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
- Player move: `OnPlayerMove` does one check of the deferred set, which returns at once when it is empty. Only buildings with a due container are in the set.
- Saved data: the seed, the small activity table (only buildings the player used) and one number per tier container.

## Compatibility and limits

- Deferred removals are not saved: after a reload they happen the next time the player leaves the building (see "Never in front of the player").
- Safe to add mid-save: containers already filled start at `A = 1` and go to today's loot the first time the player looks at them. Safe to remove: tags and numbers stay in the save, inert.
- Loot other mods add to the same rooms is counted in the same share.
- Not covered: the 17 rooms the game fills from the map (clothing stores, bookstores, army surplus...), zombies, vehicles, items on the floor.
- A container the player never looks at after its fill keeps the fill-day loot until the player comes to it; the loss is applied before the player sees it, so the result looks the same.
- Items that enter a container by crafting or other non-transfer means are not tagged.
- Multiplayer: fill and transfer run on the server; the loot-window update runs only in singleplayer until an open event is sent to the server.

## Questions for the user

1. Medium and Low: are the minimum 50 / 70 and peak 70 / 80 right for v2?
2. The lucky range: 70 to 85% of the hit loss gives a High lucky building 40.5 to 51% on day 360, as in the example. Keep it?
3. Should buildings the game already looted stay untouched (as planned) or also lose loot gradually?
4. The protect radius is 12 tiles by default. Is that the distance you mean by "muito perto", or should it be the building only (inside the walls)?
5. Removal waits until the player leaves, so the first look of a day shows the previous day's loot. Is that acceptable, or should the removal run at the look when the player is not looting that container (for example, the window was only opened to see)?
