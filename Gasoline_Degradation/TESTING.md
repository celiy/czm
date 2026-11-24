# In-game testing — Gasoline Degradation

Install (or re-install after edits) from the repo root; it replaces any existing copy in the game's mods folder:

```bash
./install.sh Gasoline_Degradation
```

## Setup

1. Launch the game with `-debug` (Steam launch options) to get the Lua console.
2. Enable **Gasoline Degradation** in Mods.
3. New solo game, sandbox page **Gasoline Degradation**:
   - Days for gasoline to degrade: **7** (to see the effect quickly)
   - Delay for recently used: **off** for the first tests (carried cans and used cars don't degrade while it is on).
   - With 7 days, a full 10 L can sitting untouched: ~6.4 L after 1 day, ~2.6 L after 3 days, 0.5 L after 7 days.
4. (Optional) `GD.DEBUG = true` in `GD_Core.lua` logs every change to the console.

Lua console commands (debug):
- `GDReport()` — settings plus gasoline in your inventory, vehicles and pumps within 30 tiles.
- `GDForceCheck()` — applies the update now, without waiting for the interval.

Expected value of any object: `liters_at_stamp × 0.05 ^ (days_since_stamp / lifetime)`, minus any delay window.

## Checklist

| # | Test | Expected |
|---|---|---|
| 1 | Sandbox page | Shown with proper texts, no raw keys |
| 2 | `GDReport()` right at the start | No error; degradation day ~0 |
| 3 | Car near spawn: note the tank, advance ~1 day, `GDForceCheck()` + `GDReport()` | Tank dropped along the curve; stamp updated |
| 4 | Fill a can at a pump (with power) | Gets a stamp, no immediate loss; drops over time |
| 5 | Used pump: `GDReport()` after some time | Pump `fuelAmount` decreases |
| 6 | Go to a never-visited area late in the save (lifetime 200, e.g. day 100) | Cars and pumps there already hold ~22% of their normal gas; with a short lifetime (7) they are at the 1 L / 0 minimum — that is the curve, not a bug |
| 6b | Drop full cans on the floor, advance 1 day (lifetime 7) | ~6.5 L each, counted from when you dropped them (`GDReport()` lists them as `floor`) |
| 7a | Advance the clock far (e.g. 2× the lifetime), then spawn a full can and leave it in a crate for 1 day | Drops only by 1 day of decay (~6.4 L with lifetime 7), not straight to 0.5 L |
| 7 | Store a can in a crate, go far away 1–2 days, come back and open it | Up to date when the loot window opens |
| 8 | Can/tank at or below the minimum (0.5 L / 1 L) | Unchanged |
| 9 | Disable "Gasoline degrades" in a save | Nothing changes |
| 10 | Walk around the map for a few minutes | No noticeable stutter |
| 11 | With the delay on (14 days): drive or refuel a car, advance 1 day, `GDForceCheck()` | That car's tank is unchanged; other cars still drop. After 14+ days without touching it, it degrades again |
| 12 | Open a crate with a can in the loot window, leave, check after 1 day | Can unchanged for the delay; a can in your own backpack does not drop at all while carried; after dropping it, it only starts degrading once the delay (14 days) has passed |
| 13 | Add the mod to an existing save at day N | `GDReport()` shows degradation day ~0; cars/pumps are not instantly drained |
| 14 | Remove the mod from that save and load it | Loads without errors; gasoline already lost stays lost |

## Errors

After playing, look for errors in `~/Zomboid/console.txt`:

```bash
grep -nE "GasolineDegradation|GD_(Core|World|Client)" ~/Zomboid/console.txt | head -50
```
