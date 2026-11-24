--[[
    Gasoline Degradation - loot window hook (singleplayer)

    When the inventory/loot window lists containers, the gasoline inside them
    is brought up to date before the player sees it. This is what makes
    stockpiles in a base, car trunks and anything else catch up after the
    player was away. Each container is handled at most once per 10 in-game
    minutes, so walking around with the window open stays cheap.
    The container currently open in a loot window is also recorded as
    recently accessed (recent access delay).
]]

require "GasolineDegradation/GD_Core"

if isClient() then return end -- multiplayer: handled by the server

local GD = GasolineDegradation
GD.containerCache = GD.containerCache or {}

local function onRefreshContainers(page, state)
    if state ~= "end" or not GD.isEnabled() or not page.backpacks then return end
    local now = GD.elapsedDays()
    for _, button in ipairs(page.backpacks) do
        local container = button.inventory
        if container and not GD.containerCache[container] then
            GD.containerCache[container] = true
            -- Unseen items here were moved by players: stamp, don't catch up.
            GD.processContainer(container, now, true)
        end
    end

    -- The container selected in a loot window counts as accessed. The
    -- player's own inventory page never does (carried gasoline always degrades).
    local selected = not page.onCharacter and page.inventoryPane and page.inventoryPane.inventory
    if selected then GD.touchContainer(selected) end
end

Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
