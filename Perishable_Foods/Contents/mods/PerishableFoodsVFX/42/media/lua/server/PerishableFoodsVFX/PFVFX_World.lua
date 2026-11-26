--[[
    Perishable Foods: Vanilla Foods Expanded - loot filled into containers.

    Vanilla Foods Expanded swaps many of the items the game puts in a container
    for its own items while the container is being filled. Whichever of the two
    mods handles the fill first, the swap may happen after the main mod walked
    the container. This handler is registered after both, so it walks the
    container once more and ages the items that were swapped in. Items already
    handled are skipped, so nothing is aged twice.
]]

require "PerishableFoodsVFX/PFVFX_Apply"

if isClient() then return end

local PF = PerishableFoods

local function onFillContainer(roomName, containerType, container)
    if container and instanceof(container, "ItemContainer") then
        PF.processContainer(container, true)
    end
end

Events.OnFillContainer.Add(onFillContainer)
