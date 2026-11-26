--[[
    Immersive Looted Buildings - the loot window (singleplayer)

    When the loot window lists the containers next to the player, nothing is
    removed: the player is in front of them. Each shop whose containers are
    listed is marked as seen (no removal until the player is away or the
    shop is loaded again) and the visit is recorded (recent-visit pause, and
    a day of activity for the base rule).

    Multiplayer clients do nothing here: the server owns the containers.
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local function onRefresh(page, step)
    if step ~= "buttonsAdded" or isClient() or page.onCharacter then return end
    if not ILB.isEnabled() then return end
    local touched = {}
    for _, button in ipairs(page.backpacks or {}) do
        local c = button.inventory
        if c and c:getType() ~= "floor" then
            local ok, err = pcall(function()
                local def, room = ILB.locate(c)
                if not def or not ILB.tierOf(room) then return end
                local key = ILB.buildingKey(def)
                -- A load or fill still waiting for this building runs first,
                -- before the items are shown; then the building counts as seen.
                if not touched[key] and ILB.flushBuilding then ILB.flushBuilding(def) end
                ILB.seen[key] = true
                ILB.deferred[key] = def -- watched until the player is away or it unloads
                touched[key] = def
            end)
            if not ok then print("[ImmersiveLootedBuildings] loot window check failed: " .. tostring(err)) end
        end
    end
    for _, def in pairs(touched) do ILB.touch(def, "use") end
end

Events.OnRefreshInventoryWindowContainers.Add(onRefresh)

-- For the tests: the same handler, called with a page of chosen containers.
ILB.onLootWindowRefresh = onRefresh
