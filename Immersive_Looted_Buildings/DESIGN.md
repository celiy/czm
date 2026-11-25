# Immersive Looted Buildings — design

Status: **implemented (0.1.0), being tested in game.** The section "What the game showed" lists what the in-game probes found and how the code follows it. Research and evidence are in [RESEARCH.md](RESEARCH.md); the test checklist is in [TEST_PLAN.md](TEST_PLAN.md).

## Goal

Make the world feel already picked over, the way it would after the first weeks of the end: some shops have been raided and some have not, more of them as time goes on, and places nobody could reach (overrun hospitals, prisons, bases) are still full. Everything configurable from the sandbox, cheap to run, and safe for a player who lives in a shop.

## Decisions confirmed by the user

- **Peak day** is the day when, realistically, many people raid the shops; after it fewer and fewer do, because they die off. Looting is fastest up to the peak and then slows until the max day.
- The curve table (day 0 100%, day 7 60%, day 30 40%, day 90 20%, day 180 15%, day 360 10%) is for the **High** tier. The tier numbers and curve in this document are accepted.
- A used building counts as **abandoned after 60 days** (confirmed), and the leftovers of abandoned buildings **are cut** (confirmed).
- A player who only passed through, looted normally, or merely rendered a building for a moment is **not** a base: coming back 30 days later it is realistic that the building was looted if the player did almost nothing there. The design separates that case from a real base (see "Used buildings").
- The mod does **not** touch buildings the game itself already looted (see below); only buildings still standing.
- Everything is configurable from the sandbox, tested for every option, and works in new games and in saves that did not have the mod.

## Systems the game already has

Everything here was read from the game's own scripts and code. The collection's current preset values are in the third column.

| System | What it does | Preset | Relation to this mod |
|---|---|---|---|
| **Container fill** (`ItemPicker`) | Fills a container the first time its area loads, from the room tables; 21 sandbox category multipliers | per category | The mod hooks after it (`OnFillContainer`) |
| **Looted buildings** (`RBLooted`, `RBShopLooted`, `RBTrashed`) | When a building first loads, with chance `getCurrentLootedChance()` it becomes "already looted": its containers are emptied, windows smashed, doors broken or locked, the building is marked `setAllExplored(true)`; shops (47 building names) also get zombies. Buildings with too many rooms, spawn buildings and stash buildings are skipped | `MaximumLooted` 25, `DaysUntilMaximumLooted` 90, `RuralLooted` 0.5, `MaximumLootedBuildingRooms` 50 | **The mod never touches these buildings.** It is the vanilla version of the same idea, with a single curve, no tiers and total emptying |
| **Diminished loot** | A growing share of all loot simply does not spawn, everywhere, over time | `MaximumDiminishedLoot` 20, `DaysUntilMaximumDiminishedLoot` 3650 | Independent; it stacks on top. With 3650 days it is about 2% in the first year |
| **Loot respawn** (`LootRespawn`) | Optionally refills containers in towns and trailer parks; skips containers with at least `MaxItemsForLootRespawn` items, zones seen recently, claimed safehouses (multiplayer) and zones where the player built or barricaded | `HoursForLootRespawn` 0 (off), `SeenHoursPreventLootRespawn` 0, `MaxItemsForLootRespawn` 5, `ConstructionPreventsLootRespawn` true | Off in the preset. If turned on, refills go through the same fill event and the building keeps its decision |
| **Shop flags** | `BuildingDef:isShop()`, `RoomDef:isShop()` mark map shops | | Possible extra classifier; the vanilla looted-shops code uses it |
| **Visited / explored flags** | `BuildingDef:isHasBeenVisited()`, `isAllExplored()`, `RoomDef:isExplored()`, container `isExplored()` | | `isAllExplored()` is how vanilla-looted buildings are recognised (to verify, see below) |
| **`hasBeenLooted`** (container) | Set when the player takes an item **out** (vanilla transfer action; the server does it in multiplayer) | | Used only as a hint: it is not set when opening or storing |
| **Zone flags** | `Zone.haveConstruction` (the player built or barricaded in the zone), `Zone:getHoursSinceLastSeen()` | | Too coarse (a whole zone) to detect a base |
| **Safehouses** | `SafeHouse.getSafeHouse(square)` | multiplayer | A claimed safehouse always counts as in use |
| **Rooms never filled** (`NoContainerFillRooms`) | 17 rooms whose loot is placed by the map | | Out of reach of this mod |
| **Room tables / procedural lists** | Which items each room can hold | | Used only for the overrun bonus and, later, item rarity |

### How the mod relates to the game's looted buildings

- A building the game already looted is skipped completely: no cut, no registry, no late cut. Only buildings that are still standing get this mod's roll. Recognition is by `BuildingDef:isAllExplored()` at fill time (both vanilla routines set it). Whether the player exploring a building can also set it is **not yet known** and is the first item to check.
- The game's looted share `v(t)` and this mod's share overlap. With the preset (25% maximum, reached on day 90, half for rural buildings) and no correction, a market on day 360 would keep about 7% of its loot instead of the 10% in the table, because the game's looted markets are emptied first.
- Option **Count buildings the game already looted** (on by default) corrects it: the mod raises its own chance on the buildings that are left to `(C x f(t) - v(t)) / (1 - v(t))`, so the total share looted equals the tier's curve, whatever the vanilla setting. Turn it off to let the two systems add up. The user can also set the vanilla `MaximumLooted` to 0 for shops.
- The game's looted buildings are emptied fully; this mod's looted buildings keep a part of their loot (cut 95% for markets). They are meant to look different.

## The model

### Priority tiers

| Tier | Meaning | Looted chance (at the end) | Loot cut if looted | Default rooms (editable) |
|---|---|---|---|---|
| **High** | Shops people would raid first | 95% | 95% | `grocery`, `grocerystorage`, `gigamart`, `conveniencestore`, `cornerstore`, `cornerstorestorage`, `generalstore`, `generalstorestorage`, `departmentstore`, `departmentstorage`, `pharmacy`, `pharmacystorage`, `liquorstore`, `bakery`, `butcher`, `candystore`, `gasstore`, `zippeestore` |
| **Medium** | Survival essentials | 75% | 75% | `toolstore`, `toolstorestorage`, `gunstore`, `gunstorestorage`, `electronicstore`, `sportstore`, `outdoorsupply`, `outdoorsupply_storage` |
| **Low** | Small, less important shops | 60% | 50% | `fishingstorage`, `knifestore`, `golfstore`, `baseballstore`, `giftstore`, `toystore`, `jewelrystore`, `musicstore` |
| **Overrun** | Full of zombies, nobody raided them | none (0%) | — | `hospitalroom`, `hospitalstorage`, `hospitalhallway`, `morgue`, `medical`, `medicalstorage`, `prisoncells`, `prisonstorage`, `policeoffice`, `policestorage`, `policelocker`, `policearchive`, `armystorage`, `oldarmy`, `armytent` |

Rooms not in any list are never touched. Houses are in no list. Hospitals are **not** High, as the user asked. Storage rooms follow the tier of their shop.

**Why these numbers.** The first values (60/40, 50/30, 40/20) can only take a market down to 76% of its loot after a year. The user's target curve ends at 10%, which needs chance x cut = 0.90 (95% x 95% = 0.9025). Medium and Low keep the proportions of the user's original values. Any pair with the same product gives the same average; the pair only changes how uneven the world looks.

### When looting happens

Four sandbox values describe the curve: the looting **starts** on day `S` (default 0), is **at its peak** on day `P` (default 7), and **ends** on day `E` (default 360). Looting is fastest up to the peak, then keeps going ever more slowly, and by day `E` it has stopped.

`f(t)` is the share of the final looting done by day `t` (0 before `S`, 1 from `E` on):

- From `S` to `P`: grows in a straight line up to `Fp`, the share done at the peak (default **44%**, so on day 7 a market has lost 40 of its 90 points).
- From `P` to `E`: `f(t) = Fp + (1 - Fp) x (1 - e^(-k x)) / (1 - e^(-k))` with `x = (t - P) / (E - P)` and a slowdown `k` (default **6.4**).

An optional **exact curve** (a list of `day:percent` points) replaces the formula.

"Day" means days since the apocalypse: days played plus the sandbox's months since the apocalypse (30 days each), the same rule as the Perishable Foods mod. A game that starts months after the apocalypse begins part-way along the curve. The option **Already looted at the start** lifts the curve at day `S`.

### What a building does

The decision is **per building**, taken when its containers are filled:

1. Give the building a permanent random number `u` in [0, 1) from a hash of its id (`BuildingDef:getID()`) and a seed saved with the world.
2. Its tier's looted share on day `t` is `C x f(t)`. The building is looted if `u < C x f(t)`.
3. If looted, containers filled in tier rooms of that building lose the tier's `cut`.

`u` never changes, so a building's decision is the same every time it is checked and never goes back. Nothing is stored per building. The final share is exactly `C`.

### What "cut" does

After the game fills a container (`OnFillContainer(roomName, containerType, container)`), items are removed so that on average `cut` of them are gone, rounding randomly so small containers average out. Keys and other must-keep items are skipped. Three options shape it:

- **Cut variation:** each looted building cuts a random amount around the set cut (useful with high chance x cut, so looted shops do not all look the same).
- **Stripped chance:** some looted buildings are emptied completely.
- **Looters take useful items first:** the cut removes food, medicine, tools and weapons before clothes and junk, with the same total cut. This fits the goal of issue 1: a raided shop still has junk.

### Overrun places

Never looted, and they get **extra loot** (25% by default): either cloned lists with more `rolls` and a re-read of the tables (proven approach), or one extra fill pass with a guard against recursion. To be decided in the first test.

### Used buildings: passing, looting and bases

The core cut happens when the game fills a container. To cover a shop the player saw on day 5 and comes back to on day 100, the mod also acts when the player **opens** a container. For that it has to tell apart: nothing happened here; the player passed or looted normally; the player lives here. The game has no signal for this (see "Systems the game already has"), so the mod keeps a small record.

**Activity record.** A saved table `used[buildingId] = { last, days, stored }`: the last day of activity, how many different days had activity, and how many items the player put in. An entry is created and updated only by three events: the player opens a container of a tier room in the building, takes an item out, or puts an item in. Nothing polls it, and rendering a building or walking in without opening anything creates no entry.

**Item mark.** Every item the player moves **into** a container of a tier room gets a tag (`ILB_player`), using the same transfer hook the Gasoline mod already has (proven in game). **The mod never removes a tagged item, in any case.**

**Classes**, derived from the record:

| Class | Record | Meaning |
|---|---|---|
| **Untouched** | none | Rendered, entered or never seen. The normal rules apply |
| **Passing / looted** | exists, fewer than 3 items stored and fewer than 3 days of activity | The player opened or looted things and left; did "practically nothing" |
| **Base** | 3 or more items stored, or 3 or more days of activity | The player really uses it |

The two numbers (3 items, 3 days) are sandbox options.

**What each class gets when a container is opened:**

| Class | Within its window | After its window |
|---|---|---|
| Untouched | Today's decision applies to a container not yet cut, once | — |
| Passing / looted | Nothing changes for **30 days** after the last activity (the user just left) | **Abandoned**: today's decision applies once; unseen containers get the cut, and the original leftovers of seen ones too. Tagged items stay |
| Base | Nothing changes for **60 days** after the last activity; any container, seen or not | **Abandoned**, same as above |

So the user's case, "looted a building, came back 30 days later", gets the building looted if its roll says so today. A base is left alone until it has been abandoned for 60 days, and the player's items are never removed.

The cut runs **before** the loot window shows the container, so the player never sees items disappear.

Other rules: a claimed safehouse (multiplayer) always counts as a base. Rooms outside the tier lists (bedrooms above a shop, offices) are never touched, so a base set up there is safe anyway. `hasBeenLooted` is read as an extra hint that the player took something.

## Expected effect with the defaults

Share of buildings looted, and average loot left in a shop of that tier (without the vanilla correction, buildings the game did not loot):

| Day | 0 | 7 | 30 | 60 | 90 | 180 | 360 |
|---|---|---|---|---|---|---|---|
| `f(day)` | 0 | 0.444 | 0.634 | 0.788 | 0.877 | 0.977 | 1.000 |
| High: looted | 0% | 42.2% | 60.2% | 74.9% | 83.3% | 92.8% | 95.0% |
| High: loot left | 100% | **59.9%** | 42.8% | 28.9% | 20.8% | 11.8% | **9.8%** |
| Medium: looted | 0% | 33.3% | 47.6% | 59.1% | 65.8% | 73.3% | 75.0% |
| Medium: loot left | 100% | 75.0% | 64.3% | 55.7% | 50.6% | 45.1% | **43.8%** |
| Low: looted | 0% | 26.7% | 38.0% | 47.3% | 52.6% | 58.6% | 60.0% |
| Low: loot left | 100% | 86.7% | 81.0% | 76.4% | 73.7% | 70.7% | **70.0%** |

The user's table for High: 100, 60, 40, —, 20, 15, 10. The curve is within 3 points.

Overrun rooms are never cut and get the bonus.

## Sandbox options

Page "Immersive Looted Buildings". Every option is tested (see TEST_PLAN.md, section 6).

| Option | Default | Notes |
|---|---|---|
| Enabled | on | |
| Looting starts on day | 0 | `S` |
| Looting peaks on day | 7 | `P` |
| Looting ends on day | 360 | `E` (max day) |
| Share of the looting done at the peak (%) | 44 | `Fp` |
| Slowdown after the peak | 6.4 | `k` |
| Exact looting curve (advanced) | empty | `day:percent` points that replace the formula |
| Already looted at the start (%) | 0 | Part of the final looting done on day `S` |
| High: chance looted (%) / loot cut (%) | 95 / 95 | |
| Medium: chance looted (%) / loot cut (%) | 75 / 75 | |
| Low: chance looted (%) / loot cut (%) | 60 / 50 | |
| Overrun: extra loot (%) | 25 | 0 turns it off |
| Room lists (High, Medium, Low, Overrun) | the defaults above | Text lists, so rooms from other maps and mods can be added |
| Cut variation (%) | 0 | |
| Stripped chance (%) | 0 | |
| Looters take useful items first | off | |
| Count buildings the game already looted | on | See "How the mod relates to the game's looted buildings" |
| Also apply to containers already filled | on | The first-open check. Off keeps strictly to "when the area first loads" |
| Days until a looted-and-left building can be raided | 30 | Window of the Passing / looted class |
| Days until a base counts as abandoned | 60 | Window of the Base class |
| Items stored to count as a base | 3 | |
| Days of activity to count as a base | 3 | |
| Cut the leftovers of abandoned buildings | on | Off leaves any building the player used untouched for good |
| Apply when vanilla loot respawn refills a container | on | The building keeps its decision |
| Log decisions | off | Writes each building's decision to the console |

## How it will be built

- **One fill handler**, `OnFillContainer`, on the server (singleplayer included). First thing in it: look `roomName` up in a table built once at game start (room name -> tier). Houses, the large majority of containers, leave there. Then skip buildings the game already looted.
- **One open handler** for the first-open check and the activity record (`OnRefreshInventoryWindowContainers`, early enough to change contents before they show).
- **The transfer hook** (as in the Gasoline mod) for item tags and the stored-items count.
- Building id: `container:getParent():getSquare():getBuilding():getDef():getID()`. The decision per building and tier is computed once per session and cached.
- Room lists are parsed once at game start and again when the sandbox changes.
- Load before Perishable Foods, so removed items are not aged for nothing.

## Optimization

- Nothing runs on a timer: no tick, minute or square-load handlers.
- Fill: one table lookup (almost always a miss). Shops pay a cached decision lookup and, in looted buildings, one pass over their items.
- Open: one lookup in the activity table. The table only holds buildings the player used.
- The save does not grow with the map: no per-building data for buildings the player never used, only the seed and the small activity table.

## Compatibility and mid-save

- Containers already filled are not changed at fill time. In a save that did not have the mod, they are handled by the first-open check, so a shop the player has only seen can still be raided when first opened.
- A building not yet seen when the mod is added gets the status of today's day.
- Removing the mod leaves everything as it was; item tags are harmless.
- Loot other mods add into the same rooms is handled, because the cut runs after the fill.
- Maps and mods with their own room names need those names in the lists.
- **Not covered:** the 17 rooms the game never fills from tables (clothing stores, bookstore, army surplus, camping, hunting, car supply, pawn shops, Spiffo's, Jay's Chicken); zombie corpses, vehicles, stash containers; items lying on the floor.
- Multiplayer: the handlers run on the server; the open event has to reach the server; a claimed safehouse counts as a base.

## What the game showed (probes, before coding)

| Question | Answer | How the code follows it |
|---|---|---|
| Does `isAllExplored()` mark the game's looted buildings? | Yes, and story buildings such as trashed houses too. **But** the player standing inside an intact building also sets it (and `isHasBeenVisited()`) | A building counts as game-looted when it is all explored **and** no player has been inside |
| When does the game loot a building? | Right **after** filling its containers (it removes 80% of each container's items and marks the building) | Fills in tier rooms are queued and handled on the next tick, when the mark is there. The tick handler is added only while the queue has entries and removes itself |
| `OnFillContainer` | Fires at chunk load with the room name (registered from a server file) and from `ItemPicker.fillContainer` | One fill handler |
| `BuildingDef:getID()` | A large number that loses precision in Lua | The building is identified by its map position (`getX()`, `getY()`), which never changes |
| `BuildingDef:isShop()` | False even for a hardware store | Not used |
| `getCurrentLootedChance()` | Percent (0 to 100) | Divided by 100 for `v(t)` |
| Sandbox `string` options | Hold the room lists | Lists split on `;` or `,` |
| Container explored flag | Means "filled", set by the game on first open | Not a looted marker |

Implementation notes:
- **Overrun bonus:** copies of the container's own items, on average `bonus` extra per item (simple, no second fill, no recursion).
- **Opening:** a container counts as opened when the loot window lists it (the player is next to it). The check runs at the `buttonsAdded` step of `OnRefreshInventoryWindowContainers`, before the items are shown.
- **Activity before today:** the class is decided from the activity before the current day, so every container of a building gets the same answer during a visit; the day a record is created still counts as untouched.
- **Container state** is kept in the parent object's mod data (`ILB_<container type>`): checked (with the day), cut, or skipped.
- **Per-building random number:** MurmurHash3 finalizer on plain numbers (the game's Lua has no bit library), cached per session. Checked offline: neighbour correlation about 0, uniform buckets, independent streams for looted / variation / stripped.

Known limits of 0.1.0:
- Containers filled **before the mod was added** in buildings the game looted cannot be told apart later (the player entering marks every building explored); they can get the mod's cut on first look on top of the game's.
- Loot respawn refills in a cut building are cut again, original leftovers included (tagged items never).
- Multiplayer: the fill handler and the transfer hook run on the server; the first-look check runs only in singleplayer for now.

## What was to be checked in game before coding (original list)

1. **`isAllExplored()` marks the buildings the game looted**, and does not become true when the player merely explores a building. If it does, another marker is needed. (Also check whether the game's looted buildings still fire `OnFillContainer`.)
2. `OnFillContainer` passes the room name for shops at chunk load, and fires from `ItemPicker.fillContainer`.
3. `BuildingDef:getID()` is stable across save and load.
4. The removal call and its synchronisation in multiplayer.
5. What `getCurrentLootedChance()` returns over time (to confirm `v(t)`) and how rural buildings are told apart.
6. What `BuildingDef:isShop()` covers, as an extra classifier.
7. Whether `rolls` accepts fractions for the overrun bonus; otherwise the extra fill pass.
8. That a sandbox `string` option can hold the room lists.
9. The first-open check: the event fires per container the player opens and early enough; marks and the activity table survive save and load; item tags survive being moved between containers.
10. Multiplayer: how the open event reaches the server.

## Tests

The checklist is in [TEST_PLAN.md](TEST_PLAN.md).

## Later (not part of this design)

- Per-item rarity (issue 4): calibrated item scaling from RESEARCH.md. The user chose to postpone it.
- The 17 map-placed rooms.
