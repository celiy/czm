# Perishable Foods — plan (Build 42)

Status: **food path implemented and tested in game (12/12). Drinks not started.** This folder holds the mod skeleton and this plan.

Collection issue 2: some food and drinks never spoil (milk, candy, juices...). Make them spoil, each with a believable shelf life, without turning the game into bookkeeping.

## What the scan found

- A vanilla item never spoils when its script has no `DaysFresh`. Scanning `DisplayCategory = Food` items with no `DaysFresh` gives **268 items**.
- After removing canned goods (52) and things that are not food (38: seeds, tobacco, dung, feathers, hay) there are **178 candidates**.
- Milk and some drinks are `ItemType = base:normal`, not `base:food`. Scans and patches must key on `DisplayCategory`, never on `ItemType`.
- Not yet verified in game that these items really never rot.

## Shelf lives (decided by the user)

Days use 30 per month and 365 per year.

| Group | Rule | Days |
|---|---|---|
| Milk-like drinks flagged non-perishable | spoil at most after 2 months | 60 |
| Non-perishable juices | 1 month | 30 |
| Industrial boxed juices (`JuiceBox*`) | 4 months | 120 |
| Hot drinks | 1 week | 7 |
| Alcohol | **only opened bottles spoil**; sealed ones never do | — |
| Soft drinks (`Pop*`) | 1 year | 365 |
| Candies | 1 year | 365 |
| Biscuits and cookies | 1 month | 30 |
| Savory snacks (crisps, chips, pretzels...) | 1 year | 365 |
| Flours | 1 year | 365 |
| Chocolate | 1 year | 365 |
| Sugar, honey, syrups | never spoil | — |
| Jams | sealed 1 year, opened 1 month | 365 / 30 |
| Dry pasta, rice, dried beans | 1 year | 365 |
| Oils and vinegar | sealed 1 year, opened 6 months | 365 / 180 |
| Sauces and condiments (ketchup, mustard, soy sauce, marinara) | sealed 1 year, opened 2 months | 365 / 60 |
| Salt, pepper, dried spices and herbs | never spoil | — |
| Jerky and dried meat | 6 months | 180 |
| Dog food (dry) | 1 year | 365 |
| Cereal | 6 months | 180 |
| Peanut butter | sealed 1 year, opened 3 months | 365 / 90 |
| Yeast, cake and pancake mixes | 1 year | 365 |
| Instant powders (coffee, cocoa, tea bags) | 1 year | 365 |
| Butter and margarine | 2 months | 60 |

All groups now have a rule. Dried herbs follow the "never spoil" row above; the user can still ask for a year instead.

## Rules the mod must follow

1. **Sealed vs opened.** Sealed items that make sense to keep (a closed wine) must not spoil; once opened they start spoiling. Apply it wherever the game lets us tell the two apart.
   **Fallback (decided by the user): if an item cannot be told apart as sealed or opened, use the sealed shelf life.** Never force the distinction where the game gives no way to see it.
2. **Fridge and freezer still slow spoilage.** Vanilla does this itself (`Food.FreezerAgeMultiplier`, cold storage); the mod must not bypass it. Needs an in-game check.
3. **Mod compatibility.** Other mods override vanilla item scripts. Our values must survive that. Details below.
4. **Safe mid-save.** Adding the mod to an existing save must not make everything rot at once, and removing it must leave the save intact. Same rule as the gasoline mod.
5. Everything in English; sandbox options with EN and PTBR translations.

## How to apply the values without being overwritten

Findings:

- **Carry Visible Items** (workshop 3749026793, id `CVI`) only adds partial script blocks such as `item Bleach { primaryAnimMask = ..., secondaryAnimMask = ... }`. It does **not** touch `DaysFresh`, and a partial block merges into the existing item instead of replacing it.
- `Item:DoParam("DaysFresh = 30")` exists in the Java API, so a script item can be changed from Lua after every mod has loaded.
- Each `Food` instance has its own `offAge` and `offAgeMax`. **Items that already exist in a save keep their old values** when the script changes.

Approach, in order:

1. **Partial script blocks.** Ship `item X { DaysFresh = N, DaysTotallyRotten = M }` only. Same method the other mod uses, never redefines the item, so animation and model overrides stay.
2. **Runtime patch as a safety net.** After scripts load, check each target with `getDaysFresh()` and fix it with `DoParam` if another mod overrode our value. Log every item that had to be fixed.
3. **Instance patch for existing items.** On loading a game and when containers are filled, set `offAge`/`offAgeMax` on food that has the old value, with a spread so a whole shelf does not spoil on the same hour.
4. Declare load order in `mod.info` so our values win ties, and keep the item list in data so users or other mods can extend it.

## TODO

### Research (before writing logic)
- [x] Confirm in game what `offAge`/`offAgeMax` the candidates carry: `1000000000` (never rots) for food, and `DaysFresh = 1000000000` for drinks.
- [x] Partial script blocks in media/scripts do NOT override an existing item's DaysFresh in game. Values are applied with `Item:DoParam` from Lua instead.
- [ ] Find how "opened" is represented: separate items (`WineOpen`, `Wine2Open`), a fluid-container state, or nothing for some items. This decides what the sealed/opened rule can cover. Items with no way to tell use the sealed shelf life.
- [ ] Check what happens to items of an existing save when the script gains a `DaysFresh` (do they start rotting from their creation time, or from now?).
- [ ] Confirm cold storage (fridge, freezer, cooler) slows a `DaysFresh` item the same as vanilla perishables.
- [x] Milk, juices, pop, wine and spirits are fluid containers, NOT `Food`, so vanilla never rots them. They need their own clock (not started).
- [ ] Look at other overrides in the collection (mods that touch food scripts) and at load order.

### Design
- [x] Shelf lives for every group decided by the user (see the table).
- [ ] Decide the rule for drinks that are `base:normal`/`base:drainable`.
- [ ] Decide the spread for instance patching.
- [ ] Decide the sandbox options (global multiplier for shelf lives, on/off per group).

### Build
- [x] `data/shelf_life.json`: item → group and shelf life (127 food items with a finite life, 41 that never spoil).
- [x] `tools/generate_scripts.py` writes `PF_Data.lua`; `PF_Scripts.lua` applies the values at load.
- [x] Instance patching for existing items: age reset to 0 the first time the mod sees the item, marked in modData.
- [ ] Sealed/opened logic.
- [ ] Sandbox options, EN and PTBR translations, mid-save notice in the description like the gasoline mod.
- [ ] Workshop files (`workshop.txt`, preview) and `install.sh` support.

### Test (reuse `dev/run-autotest.sh`, mode `perishable`)
- Done (12/12): values applied to 127 items, new and old items, never-spoil and own-value items left alone, inventory patched.
- Gasoline regression still 33/33.
- Not done: fridge/freezer, Carry Visible Items actually loaded, sealed/opened (food uses the sealed value everywhere, per the user's fallback rule).
- [ ] A new item with a shelf life rots on schedule.
- [ ] A frozen or refrigerated one rots slower.
- [ ] Sealed vs opened alcohol.
- [ ] An item overridden by Carry Visible Items still has our shelf life.
- [ ] Existing item in a loaded save does not spoil all at once.
- [ ] Adding and removing the mod mid-save.
