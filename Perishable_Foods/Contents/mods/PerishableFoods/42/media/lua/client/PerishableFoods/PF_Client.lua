--[[
    Perishable Foods - loot window: containers listed in the window are handled
    when they open, so food and drinks in never-opened containers are caught up.
]]

require "PerishableFoods/PF_Drinks"

if isClient() then return end

local PF = PerishableFoods

local function onRefreshContainers(page, state)
    if state ~= "end" or not page.backpacks then return end
    for _, button in ipairs(page.backpacks) do
        if button.inventory then PF.processContainer(button.inventory, false) end
    end
end

Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
