"""Regenerate the shelf-life table from data/shelf_life.json (run from Perishable_Foods/).

Writes a Lua table, not a script overlay: a partial item block in media/scripts
was observed NOT to override an existing item's DaysFresh in game, so the mod
applies the values at runtime with Item:DoParam (see PF_Scripts.lua).
"""
import json, os

here = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(here, '..', 'data', 'shelf_life.json')))
rows = [(n, v) for n, v in sorted(data.items()) if 'freshDays' in v]
lines = [
    '-- Generated from data/shelf_life.json by tools/generate_scripts.py. Do not edit by hand.',
    'PerishableFoods = PerishableFoods or {}',
    'PerishableFoods.SCHEDULE = {',
]
for n, v in rows:
    lines.append(f'    {{ "Base.{n}", {v["freshDays"]}, {v["rottenDays"]} }},')
lines.append('}')
drinks = json.load(open(os.path.join(here, '..', 'data', 'drinks.json')))
lines += ['', '-- Drinks (fluid containers): item -> { shelf life in days, group }.', 'PerishableFoods.DRINKS = {']
for n, v in sorted(drinks.items()):
    if 'days' in v:
        lines.append(f'    ["Base.{n}"] = {{ {v["days"]}, "{v["group"]}" }},')
lines.append('}')
never_food = sorted(n for n, v in data.items() if v['group'] == 'never')
never_drink = sorted(n for n, v in drinks.items() if v['group'] == 'never')
lines += ['', '-- Items that deliberately never spoil (sugar, salt, sealed alcohol...). Used by the tests.',
          'PerishableFoods.NEVER_FOODS = {'] + [f'    "Base.{n}",' for n in never_food] + ['}',
          'PerishableFoods.NEVER_DRINKS = {'] + [f'    "Base.{n}",' for n in never_drink] + ['}']
out = os.path.join(here, '..', 'Contents', 'mods', 'PerishableFoods', '42', 'media', 'lua', 'shared', 'PerishableFoods', 'PF_Data.lua')
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w').write('\n'.join(lines) + '\n')
print(len(rows), 'food entries,', sum(1 for v in drinks.values() if 'days' in v), 'drink entries written')
