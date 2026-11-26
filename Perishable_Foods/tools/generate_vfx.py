"""Build the Vanilla Foods Expanded compatibility tables (run from Perishable_Foods/).

Input:  compat/vfx_foods.tsv  (every food and drink of Vanilla Foods Expanded, from its scripts)
Output: data/vfx_shelf_life.json  and
        Contents/mods/PerishableFoodsVFX/42/media/lua/shared/PerishableFoodsVFX/PFVFX_Data.lua

Only items that never spoil today and that make sense to spoil are given a shelf
life, with the same "realistic but arcade" groups as the main mod. Canned goods,
sealed alcohol, sugar and salt, utensils, and anything the other mod handles itself
(starters, ferments, cheese wheels, pots in the middle of cooking) are left alone.
"""
import csv, json, os, re, collections

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..')

# group -> (fresh days, rotten days)
FOOD = {
    'spice': (730, 820),        # dried herbs, spices, seasoning mixes, extracts
    'sauce': (365, 420),        # jarred sauces, dressings, relishes, juices of lemon and lime
    'pickled': (365, 420),      # jarred pickles and olives
    'jam': (365, 420),
    'flour': (365, 420),
    'dry': (365, 420),          # pasta, rice, ramen, stuffing and meal mixes, grits
    'powder': (365, 420),       # baking mixes, soup sachets, tea bags, creamers, pudding and jelly boxes
    'frosting': (365, 420),
    'cereal': (180, 240),       # cereals, granola, croutons, crumbs, coconut, spreads
    'cup': (180, 240),          # jelly, pudding and fruit cups
    'candy': (365, 420),
    'chocolate': (365, 420),
    'snack': (365, 420),        # chips, crackers, nuts, trail mix, dried fruit, rice cakes
    'packaged_cake': (30, 45),  # strudels, creme pies, swiss rolls and the like
    'fudge': (90, 120),
    'butter': (60, 80),
    'homemade_sauce': (30, 45),
}
DRINK = {'milk': 60, 'juice': 30, 'juice_box': 120, 'soda': 365}

# Left alone on purpose.
SKIP_NAMES = re.compile(r'(FoodStorageContainer|Starter|Fermenting|Dead|^Bottle(Beer|Wine)Empty$|BottleHomemade|HomemadeWinePrep|HomemadeBeerPrep|'
                        r'HomemadeVinegar|Nettle|Rennet|TomatoPastePot|SugarBeet|PowderedSugar|SaltCan|HomemadeGrits|JarPickleJuiceOpen|'
                        r'CatFood|CannedWorms|Crickets|Snails|Empty|MixingBowl|Pitcher|Shaker|SmallJar|SmallTinCan|MilkshakeGlass|VFXHomemadeJam$|VFXHomemadeJam)')

def classify_food(cat, item):
    n = item.split('.', 1)[1]
    if SKIP_NAMES.search(n):
        return None
    if cat == 'Canned':
        return 'pickled' if n.startswith('Jar') else None            # cans stay as sealed cans do
    if cat == 'Seasoning and sauces':
        if re.search(r'(Dressing|Sauce$|Relish|Mustard$|Ranch$|Aioli|Horseradish|Juice$|Vinaigrette)', n) and 'Seasoning' not in n and 'Powder' not in n:
            return 'sauce'
        if n.endswith('Sugar') and n != 'CinnamonSugar':
            return None
        return 'spice'
    if cat == 'Homemade':
        return 'homemade_sauce'
    if cat == 'Baking':
        return 'frosting' if 'Frosting' in n else 'powder'
    if cat == 'Candy':
        if n == 'Fudge':
            return 'fudge'
        return 'chocolate' if n.startswith('Chocolate') else 'candy'
    if cat == 'Beverages':          # the "food" rows: tea bags and creamers
        return 'powder' if (n.endswith('TeaBag_2') or n.startswith('CoffeeCreamer')) else None
    if cat == 'Snacks':
        if re.search(r'(Strudel|CoffeeCake|CosmicBrownie|FudgeRound|CremePie|SwissRoll|ZebraCakes)', n):
            return 'packaged_cake'
        if re.search(r'(JelloBox|PuddingBox)$', n):
            return 'powder'
        if re.search(r'(JelloCup|PuddingCup|JellyFruit|SyrupFruit)', n):
            return 'cup'
        if 'GranolaBar' in n:
            return 'cereal'
        return 'snack'
    if cat == 'Pantry':
        if n.endswith('Flour'):
            return 'flour'
        if re.search(r'(Ramen|Sachet|StuffingMix|ScallopedPotatoes|^PM|^RM|Rice$|Fettuccine|Gnocchi|LasagnaSheets|Macaroni|Penne|Grits$)', n) and 'Flavour' not in n:
            return 'dry'
        if 'Flavour' in n or n.startswith('SeasoningMix') or n == 'VanillaExtract':
            return 'spice'
        if re.search(r'Jam$|Marmalade$|AppleButter|MapleButter', n):
            return 'jam'
        if n == 'CinnamonButter':
            return 'butter'
        if re.search(r'(Granola|Croutons|Breadcrumbs|ShreddedCoconut|CheeseSpread|LiverSpread)', n) or n in (
                'AdmiralChomp', 'CocoaPuffs', 'FrostyCrunch', 'FruityLoops', 'HoneyOatyOs', 'OatyOs', 'RiceKrisps', 'UnluckyCharms', 'Wheaties'):
            return 'cereal'
        if n == 'HazelnutSpread':
            return 'jam'
        if n == 'Sprinkles':
            return 'candy'
        if n == 'BagFriedOnion':
            return 'snack'
        if re.search(r'(Sauce$|Molasses|Marinara$)', n):
            return 'sauce'
        return None
    return None

def classify_drink(item):
    n = item.split('.', 1)[1]
    if n.startswith('RootBeer'):
        return 'soda'
    if re.search(r'(Beer|Lager|Ale$|Pilsner|Porter|Stout|Wine|Merlot|Chardonnay|Riesling|Sauvignon|Pinot|Cabernet)', n):
        return None                          # sealed alcohol keeps
    if n.endswith('Milk'):
        return 'milk'
    if n.startswith('JuiceBox'):
        return 'juice_box'
    if n.endswith('Juice'):
        return 'juice'
    if n.startswith('IcedTea'):
        return 'juice_box'
    if re.search(r'(Soda|Cola|RootBeer|^Sports)', n):
        return 'soda'
    return None

rows = list(csv.DictReader(open(os.path.join(root, 'compat', 'vfx_foods.tsv'), encoding='utf-8'), delimiter='\t'))
foods, drinks, left = {}, {}, collections.Counter()
for r in rows:
    if r['spoilage'] == 'spoils':
        continue
    if r['kind'] == 'food':
        g = classify_food(r['category'], r['item'])
        if g:
            foods[r['item']] = g
        else:
            left[r['category']] += 1
    else:
        g = classify_drink(r['item'])
        if g:
            drinks[r['item']] = g
        else:
            left['drink: ' + r['category']] += 1

data = {'foods': {k: {'group': g, 'freshDays': FOOD[g][0], 'rottenDays': FOOD[g][1]} for k, g in sorted(foods.items())},
        'drinks': {k: {'group': g, 'days': DRINK[g]} for k, g in sorted(drinks.items())}}
json.dump(data, open(os.path.join(root, 'data', 'vfx_shelf_life.json'), 'w'), indent=1)

lines = ['-- Generated from data/vfx_shelf_life.json by tools/generate_vfx.py. Do not edit by hand.',
         'PerishableFoodsVFX = PerishableFoodsVFX or {}',
         'PerishableFoodsVFX.FOODS = {']
for k, v in data['foods'].items():
    lines.append(f'    {{ "{k}", {v["freshDays"]}, {v["rottenDays"]}, "{v["group"]}" }},')
lines += ['}', '', 'PerishableFoodsVFX.DRINKS = {']
for k, v in data['drinks'].items():
    lines.append(f'    ["{k}"] = {{ {v["days"]}, "{v["group"]}" }},')
lines.append('}')
out = os.path.join(root, 'Contents', 'mods', 'PerishableFoodsVFX', '42', 'media', 'lua', 'shared', 'PerishableFoodsVFX', 'PFVFX_Data.lua')
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w').write('\n'.join(lines) + '\n')

print(len(foods), 'foods,', len(drinks), 'drinks given a shelf life')
print('by group:', dict(collections.Counter(list(foods.values()) + list(drinks.values()))))
print('left alone (never spoil, not changed):', dict(left))
