# Loot control — research (Build 42.22)

Goal (collection issues 1 and 4): make **specific structures** (supermarkets, pharmacies, hardware stores...) give less loot, and make **specific items** (painkillers...) rarer, while houses and other places stay normal.

Everything below was checked in the game, not assumed. Method: `dev/run-autotest.sh` with the `loot_*` suites in `dev/CZMAutoTest/.../CZMAutoTest_Perishable.lua`.

## Verdict

**Yes, there is a reliable way**: change the game's loot tables **per room name** before the game reads them. It is the game's own mechanism, costs nothing while playing, and was proven in game: the chosen rooms lost about 80% of their loot while houses stayed at 98%.

## How loot is generated

Three layers:

1. **Room table** (`media/lua/server/Items/Distributions.lua`, 649 entries). A room name (`grocery`, `pharmacy`, `bedroom`...) maps to container types (`shelves`, `counter`, `fridge`...). Each container either lists items directly (`rolls`, `items`, `junk`) or points to procedural lists (`procedural = true, procList = { {name=..., min, max, weightChance} }`). Bags, cases and caches live in the same table.
2. **Procedural lists** (`ProceduralDistributions.lua`, 1420 lists). A list has `rolls` and `items = { "Item", chance, ... }`.
3. **The Java sorter** (`ItemPicker` = `ItemPickerJava`). `ItemPicker.Parse()` reads the Lua tables into Java maps; a container is filled when its chunk loads the first time. It also applies 21 **sandbox category multipliers** (food, medical, ammo, tools, clothing...). Those multipliers are global per category, which is why the vanilla sandbox cannot do "less loot in stores only".

The game supports mods editing these tables:

- Events `OnPreDistributionMerge`, `OnDistributionMerge`, `OnPostDistributionMerge` run before Java reads the tables. Mods that add their own tables are merged in between.
- Helpers in vanilla: `ClearAllDistributionItems`, `RemoveItemFromDistribution(dist, item, chance, recursive)`, `ReplaceItemInDistribution`, `MergeDistributionRecursive`.
- Many rooms are **aliases** (`grocers = grocery`, `clinic = medical`, `garage = mechanic`...): the same Lua table under two names.

## What was measured

### 1. Procedural lists are shared among shops, almost never with houses

| Room | Lists used | Also used by houses |
|---|---|---|
| grocery | 45 | 0 |
| gigamart | 50 | 0 |
| pharmacy | 18 | 0 |
| liquorstore | 21 | 0 |
| medical | 8 | 0 |
| conveniencestore | 21 | 1 |
| toolstore | 21 | 6 (garage and shed crates) |

Editing a shared list in place would also change other shops that use it. So the change must be made on **copies** of the lists, assigned only to the chosen rooms. No procList entry object is shared between the shop rooms tested and bedroom, kitchen or livingroom.

### 2. Per-room change: proven, no leak

Cloned every list of the chosen rooms with item chances x0.2, pointed only those rooms at the clones, called `ItemPicker.Parse()`, and counted items per fill (30 fills per measure).

| Town | Room | Items per fill before | after | ratio |
|---|---|---|---|---|
| Muldraugh | cornerstore | 4.03 | 0.63 | **0.16** |
| Muldraugh | toolstore | 6.87 | 1.10 | **0.16** |
| Muldraugh | bedroom (control) | 3.63 | 3.63 | 1.00 |
| Muldraugh | livingroom (control) | 3.57 | 3.50 | 0.98 |
| Muldraugh | kitchen (control) | 2.87 | 2.77 | 0.97 |
| West Point | cornerstore / gasstore / generalstore / medical | | | 0.12 – 0.24 |
| West Point | bedroom / livingroom (control) | | | 0.83 – 1.05 |

Chance scaling is roughly linear for rooms (x0.2 gave 0.16–0.24).

### 3. One item only: proven, but not linear

Scaling every entry of `Pills` (89 procedural entries, 55 room-table entries) by 0.2 and sampling 24 shop containers: 3.1–3.5 Pills per fill became 0.08–0.16 per fill, a **ratio of 0.03–0.05, not 0.2**. The same item appears at two layers, so the effect compounds. **Any item-level factor has to be calibrated by measurement.** If the effect is roughly the square of the factor, a factor near 0.45 should give about 0.2; that is a hypothesis to test, not a result.

### 4. Re-reading the tables at runtime works

`ItemPicker.Parse()` can be called after the game started, and the new tables are used by the next fill. Useful for live sandbox changes. Containers already filled keep what they have.

## Things that could trip an implementation

- **House rooms have a loot cap.** Refilling the same house room about 100 times makes every container in it give 0 items (bedroom: 3.5, 3.4, 1.6, 0, 0, 0 per 40 fills; the second wardrobe also started at 0). Shops never showed it (320 fills stayed flat). This produced a fake "leak" in the first experiment. Any test that refills a house container must stay under about 80 fills.
- **17 rooms are never filled from the tables** (`NoContainerFillRooms`): armysurplus, armysurplusstorage, bookstore, camping, campingstorage, carsupply, clothingstore, clothingstorage, hunting, jayschicken_*, pawnshop*, spiffo_*. Their loot is placed by the map. Table edits do nothing to them, which fits the idea that a clothing store should keep its clothes.
- **`isShop` is not a store flag.** It marks bags, cases and boxes (wallets, key rings, toolboxes). Room names are the classifier.
- Only containers **not yet filled** are affected. Buildings already looted in a save stay as they are, which makes adding or removing the mod mid-save safe.
- Mods that add their own room names (custom shops, other maps) are not covered unless configured. Edit in `OnPostDistributionMerge` so their tables are already merged.
- Shop rooms often have a matching `...storage` room (grocery, grocerystorage; pharmacy, pharmacystorage). They are separate names.
- Zombie corpses, vehicles and stash containers use other tables and are not covered.

## Approaches compared

| Approach | Precise by room | Precise by item | Cost while playing | Verdict |
|---|---|---|---|---|
| **Clone lists per room + `ItemPicker.Parse()`** | yes (proven) | n/a | none | **recommended for structures** |
| **Scale/remove one item in every list** | no | yes (needs calibration) | none | **recommended for issue 4** |
| Remove items after the fill (`OnFillContainer`) | yes | yes | one pass per container fill | possible fallback; the event worked in other tests, but its arguments were not checked here |
| Vanilla sandbox category multipliers | no (global per category) | no | none | already known not to fit |
| Pre-empty whole buildings in the map | yes | no | heavy, fragile | not recommended |

## Suggested design for the mod

- A data table: room name -> percentage of loot kept (for example grocery 20%, gigamart 15%, pharmacy 10%, toolstore 30%). Rooms not listed are untouched. Aliases are resolved so `grocers` follows `grocery`.
- A second data table: item -> percentage kept (painkillers and whatever else is too common), calibrated with the measured non-linear response.
- Both run in `OnPostDistributionMerge`; they clone, never edit shared lists in place.
- Sandbox options: on/off, a global multiplier for the room table, and a global multiplier for the item table. Presets for "stores picked clean" and "mild".
- Tests in the harness using the same method as here: shop rooms and house rooms in the same town, under 80 fills per measure.

## Questions for the user

1. Which structures count, and how empty? Suggested starting point: grocery, gigamart, conveniencestore, cornerstore, generalstore, departmentstore (food), pharmacy, pharmacystorage, medical (medicine), toolstore (tools), liquorstore.
2. Should the storage rooms behind the shop (`grocerystorage`, `pharmacystorage`) be emptied as much as the shop floor, or less?
3. Which items besides painkillers are too common?
4. Should some shops get *more* loot (for example hospitals) to balance, or only less?
