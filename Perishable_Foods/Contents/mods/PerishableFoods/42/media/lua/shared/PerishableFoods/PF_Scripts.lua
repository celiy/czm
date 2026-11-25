--[[
    Perishable Foods - applies the shelf lives to the item scripts.

    Runs when the mod's Lua loads (every script has been parsed by then, and
    this mod loads after the ones it may conflict with), and again when a game
    starts, once the sandbox options of that save are known. Item:DoParam sets
    DaysFresh and DaysTotallyRotten on the script item. Only these two values
    change; models, animations and the rest of the item are untouched.
    The ShelfLifeMultiplier sandbox option scales both.
]]

require "PerishableFoods/PF_Core"
require "PerishableFoods/PF_Data"

local PF = PerishableFoods

function PF.applySchedule()
    local mult = PF.multiplier()
    local applied, missing = 0, 0
    for _, entry in ipairs(PF.SCHEDULE) do
        local script = getScriptManager():getItem(entry[1])
        if script then
            local fresh = math.max(1, math.floor(entry[2] * mult + 0.5))
            local rotten = math.max(fresh + 1, math.floor(entry[3] * mult + 0.5))
            script:DoParam("DaysFresh = " .. fresh)
            script:DoParam("DaysTotallyRotten = " .. rotten)
            applied = applied + 1
        else
            missing = missing + 1
        end
    end
    PF.appliedCount, PF.missingCount = applied, missing
    print(string.format("[PerishableFoods] shelf lives applied to %d items (%d not found), multiplier %.2f", applied, missing, mult))
end

PF.applySchedule()
Events.OnGameStart.Add(PF.applySchedule)
