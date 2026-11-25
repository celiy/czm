"""Write workshop.txt with every modified item and its shelf life, from the data tables.
Run from Perishable_Foods/ after editing data/*.json."""
import json, os

here = os.path.dirname(os.path.abspath(__file__))
food = json.load(open(os.path.join(here, '..', 'data', 'shelf_life.json')))
drinks = json.load(open(os.path.join(here, '..', 'data', 'drinks.json')))

def days_text(d):
    if d % 365 == 0 and d >= 365:
        n = d // 365
        return f"{n} year" + ("s" if n > 1 else "")
    if d % 30 == 0 and d >= 30:
        n = d // 30
        return f"{n} month" + ("s" if n > 1 else "")
    if d % 7 == 0 and d >= 7:
        n = d // 7
        return f"{n} week" + ("s" if n > 1 else "")
    return f"{d} days"

FOOD_GROUPS = [
    ('hotdrink', 'Hot drinks'), ('biscuit', 'Biscuits, cookies and baked sweets'), ('butter', 'Butter and margarine'),
    ('jerky', 'Jerky and dried meat'), ('cereal', 'Cereal and granola'), ('candy', 'Candy'), ('chocolate', 'Chocolate'),
    ('snack', 'Salty snacks'), ('flour', 'Flour'), ('pasta', 'Dry pasta, rice and dried beans'), ('dogfood', 'Dry dog food'),
    ('sauce', 'Sauces and condiments'), ('oil', 'Oils and vinegar'), ('peanutbutter', 'Peanut butter and peanuts'),
    ('jam', 'Jams'), ('powder', 'Instant powders (coffee, cocoa, tea bags)'), ('mix', 'Mixes'),
]
DRINK_GROUPS = [
    ('milk', 'Milk'), ('juice', 'Juices'), ('juice_box', 'Boxed juices'), ('soda', 'Soft drinks'),
    ('alcohol_open', 'Opened wine'),
]
NEVER_FOOD = sorted(n for n, v in food.items() if v['group'] == 'never')
NEVER_DRINK = sorted(n for n, v in drinks.items() if v['group'] == 'never')

lines = []
def add(text=''): lines.append('description=' + text)

add('[b]IMPORTANT:[/b] when you add this mod to a save that is already in progress, food and drinks you already own start fresh the first time the mod sees them. Loot in places you have not visited yet is aged from the day you add the mod, so nothing rots retroactively.')
add()
add('In vanilla, much of the food in Project Zomboid never spoils: milk, juice, soft drinks, biscuits, chocolate, jams, sauces... Here they do, each with a believable shelf life. Fridges and freezers slow it down, sealed alcohol keeps, and loot in places nobody has visited is already old.')
add()
add('[h2]How it works[/h2]')
add('[list]')
add('[*] Food that never spoiled now has a shelf life, using the game\'s own spoilage. Fridges, freezers and power cuts work exactly as for any vanilla perishable.')
add('[*] Drinks (milk, juice, soft drinks, opened wine) are liquids in the game, which never spoil. This mod keeps an age for each one, and when it passes its shelf life the liquid becomes [b]Spoiled Drink[/b], which is poisonous. The amount is kept. Fridges slow them down and freezers stop them, like food.')
add('[*] Sealed alcohol never spoils. Opened wine does.')
add('[*] A game that starts months after the apocalypse starts with the world already aged by those months.')
add('[*] Compatible with other mods: only the two spoilage values of each item are changed, applied after every mod has loaded. Models, animations and everything else about the item stay as other mods set them.')
add('[*] Sandbox options: turn it on or off, and scale every shelf life with a percentage.')
add('[/list]')
add()
add('[h2]Shelf lives[/h2]')
add('Food ("good for" is how long it stays fresh; after that it goes stale and then rotten):')
for key, title in FOOD_GROUPS:
    items = sorted(n for n, v in food.items() if v['group'] == key)
    if not items: continue
    fresh, rotten = food[items[0]]['freshDays'], food[items[0]]['rottenDays']
    add(f'[b]{title}[/b] - good for {days_text(fresh)}, rotten after {days_text(rotten)} - {len(items)} items')
    add(', '.join(items))
    add()
add('Drinks:')
for key, title in DRINK_GROUPS:
    items = sorted(n for n, v in drinks.items() if v['group'] == key)
    if not items: continue
    days = drinks[items[0]]['days']
    add(f'[b]{title}[/b] - good for {days_text(days)}, then spoiled - {len(items)} items')
    add(', '.join(items))
    add()

head = ['version=1', 'title=Perishable Foods']
tail = ['tags=Build 42;Realistic;Balance;Food', 'visibility=public']
out = os.path.join(here, '..', 'workshop.txt')
open(out, 'w').write('\n'.join(head + lines + tail) + '\n')
print(len(food) - len(NEVER_FOOD), 'foods and', sum(1 for v in drinks.values() if 'days' in v), 'drinks with a shelf life listed;', len(NEVER_FOOD) + len(NEVER_DRINK), 'never-spoil items listed;', sum(len(l) for l in lines), 'characters')
