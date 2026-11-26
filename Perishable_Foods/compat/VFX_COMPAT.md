# Vanilla Foods Expanded (3577903007) and Perishable Foods

Analysed on 2026-11-26 from the Workshop files (version 3.4.4). The full list of its foods and drinks is in [vfx_foods.tsv](vfx_foods.tsv) (2065 rows: 1983 foods and 82 drinks).

## What the mod adds

- 1983 food items (`base:food`) and 82 drinks (items with a fluid container, 67 new fluids: sodas, juices, milks, protein shakes, iced teas, lemonades, wines, beers). Items live in the modules `VFX` and `Base`.
- Cookbooks, recipes, evolved recipes, kitchenware, birthday cakes and candles, cheese aging and sourdough, yeast, vinegar and beer fermentation.
- 76 vanilla items edited in `vfx_modifiedbasegameitems.txt`: icons, models, tags, nutrition values, `ReplaceOnUse`. Two of them also get a shelf life: `Base.Cheese` (28 / 56 days) and `Base.SourCream` (7 / 14 days). Perishable Foods does not touch either.
- At every container fill (`OnFillContainer`) it **replaces 251 vanilla and VFX items** with items picked from a weighted list of its own foods (`vfx_distribution.lua`, `replaceDistributionItems`). The replacement calls `setAutoAge()`.
- Its own aging code (`vfx_agingmanager.lua`) handles only its homemade items (sourdough, cheese wheels, homemade beer and wine, yeast, vinegar, ice). It never writes `DaysFresh` or `DaysTotallyRotten`.

## Does it break Perishable Foods?

No. Nothing crashes or overwrites anything.

- Perishable Foods sets `DaysFresh` and `DaysTotallyRotten` on 158 `Base.*` foods with `DoParam` after all scripts load. Vanilla Foods Expanded does not set those two values on any of them. Of the 14 names that appear in both mods, 11 are vanilla items it only re-skins (tags, models, icons, nutrition, `ReplaceOnUse`), and 3 (`Pretzel`, `DriedApricots`, `Macaroni`) are different items in the `VFX` module.
- The 46 drinks Perishable Foods ages are `Base.*` items; Vanilla Foods Expanded does not edit them.
- The two mods use different mod data keys and fluid names (`PF_age`, `SpoiledDrink` against `VFX_*`).

## Where it dilutes Perishable Foods

1. **The fill replacement.** 61 of the 251 replaced vanilla items are items Perishable Foods handles. Each one becomes a random pick from the VFX list. Share of the picks that are VFX items that never spoil (foods), or VFX drinks that Perishable Foods does not track:
   - Cereal 93%, jam 88%, pasta and macaroni 83%, rice 80%, flour 68%.
   - Candy 67% to 89%, gum and lollipops 96%, chocolate bars 50% to 86%, crisps 50%, crackers 80%, granola bars 87%, peanuts 89%, dried apricots 90%.
   - Juice 50% to 75%, boxed juice 50%, soda 80% to 88%, tea bags 58% foods and 33% drinks.
2. **Its own foods.** 595 of its 1983 foods have no `DaysFresh`, so they never spoil: candy 128 of 129, snacks 121 of 126, seasoning and sauces 62 of 62, pantry 112 of 228, canned 85 of 201, baking 46 of 374. Most are sealed or dry, but the vanilla versions of the same things get a shelf life in Perishable Foods, so the two kinds are treated differently.
3. **Its drinks.** The 82 drinks are fluid containers, and the engine has no rot for fluids. Perishable Foods ages drinks by item type (46 `Base.*` types), so milks (chocolate, strawberry, banana, soy), juices (grapefruit, pineapple, tropical), sodas, iced teas, lemonades and protein shakes from Vanilla Foods Expanded never spoil.
4. Perishable foods of Vanilla Foods Expanded (1388 foods) use its own shelf lives. The engine ages them by the world clock, and they follow the fridge and freezer rules of the vanilla engine.

## The add-on: PerishableFoodsVFX

A second mod in the same Workshop item (`Contents/mods/PerishableFoodsVFX`), shown as its own entry in the mod list: **Perishable Foods: Vanilla Foods Expanded**. Its `mod.info` has `require=\PerishableFoods,\VanillaFoodsExpanded`, so it can only be enabled with both.

- `tools/generate_vfx.py` reads `compat/vfx_foods.tsv` and writes `data/vfx_shelf_life.json` and `PFVFX_Data.lua`: **489 foods and 38 drinks** that never spoil today and make sense to spoil.
- `PFVFX_Apply.lua` appends them to `PerishableFoods.SCHEDULE` and `PerishableFoods.DRINKS` and applies them. Aging, fridges, freezers, spoiled drinks and the sandbox multiplier are the main mod's code.
- `PFVFX_World.lua` registers a second `OnFillContainer` handler after both mods, so items that Vanilla Foods Expanded swaps in while a container is filled are aged by the world clock whatever the handler order.

| Group | Fresh / rotten (days) | What |
|---|---|---|
| spice | 730 / 820 | herbs, spices, seasoning mixes, bouillon, sachets of flavour, vanilla extract |
| sauce, pickled, jam, flour, dry, powder, frosting, candy, chocolate, snack | 365 / 420 | jarred sauces and dressings, pickles and olives, jams and spreads, flours, rice, pasta, ramen, meal and stuffing mixes, baking mixes, tea bags, creamers, jelly and pudding boxes, candy, chocolate, chips, nuts, dried fruit |
| cereal, cup | 180 / 240 | cereals, granola, granola bars, croutons, crumbs, coconut, spreads, jelly, pudding and fruit cups |
| fudge | 90 / 120 | fudge |
| butter | 60 / 80 | cinnamon butter |
| packaged_cake, homemade_sauce | 30 / 45 | strudels, creme pies, swiss rolls, coffee cakes, homemade sauces |
| drinks | milk 60, juice 30, boxed juice and iced tea 120, soda and sports drinks 365 | same fluid ageing as the main mod |

Left alone on purpose: canned goods (79), sealed beer and wine and wine boxes, salt, sugar, starters and every ferment, cheese rennet, pots in the middle of cooking, containers and utensils, and the foods of Vanilla Foods Expanded that already spoil (1388).

A food seen by the main mod before the add-on was turned on is patched the next time the main mod sees it: the main mod no longer marks non-perishable foods as done.
