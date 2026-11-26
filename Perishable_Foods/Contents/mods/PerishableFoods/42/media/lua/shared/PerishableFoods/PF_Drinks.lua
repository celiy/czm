--[[
    Perishable Foods - drinks

    Milk, juice, pop and opened wine are fluid containers. The engine has no
    rot for fluids, so each of these items keeps its own age in its modData:
      PF_age  days it has aged (slowed in a fridge, stopped in a freezer)
      PF_t    world day of the last update
    When the age passes the shelf life, the liquid inside becomes
    "Spoiled Drink" (a poisonous fluid defined by this mod). The amount is kept.

    Sealed alcohol is not in the table: it never spoils. Opened wine
    (WineOpen, Wine2Open) is. Items we cannot tell as sealed or opened use the
    sealed shelf life (the user's rule).
]]

require "PerishableFoods/PF_Core"
require "PerishableFoods/PF_Data"

local PF = PerishableFoods

PF.AGE_KEY = "PF_age"
PF.STAMP_KEY = "PF_t"
PF.SPOILED_KEY = "PF_spoiled"
PF.SPOILED_FLUID = "SpoiledDrink"

function PF.drinkShelfLife(item)
    local entry = PF.DRINKS[item:getFullType()]
    return entry and entry[1] * PF.multiplier() or nil
end

function PF.isSpoiledDrink(item)
    local fc = item:getFluidContainerFromSelfOrWorldItem()
    return fc ~= nil and fc:isPrimaryFluidType(PF.SPOILED_FLUID)
end

function PF.spoilDrink(item, fc)
    local amount = fc:getAmount()
    local spoiled = Fluid.Get(PF.SPOILED_FLUID)
    fc:Empty()
    -- A sealed container (cans of other mods) refuses new fluid: the sealed drink is opened
    -- by the spoilage.
    if not fc:canAddFluid(spoiled) then fc:unseal() end
    fc:addFluid(spoiled, amount)
    item:getModData()[PF.SPOILED_KEY] = true
    if isServer() then
        item:syncItemFields()
        sendItemStats(item)
    end
end

-- Age one drink. Returns true if it spoiled in this call.
function PF.ageDrink(item, worldGenerated)
    local life = PF.drinkShelfLife(item)
    if not life then return false end
    local fc = item:getFluidContainerFromSelfOrWorldItem()
    if not fc or fc:isEmpty() then return false end
    local md = item:getModData()
    if md[PF.SPOILED_KEY] then return false end

    local now = PF.worldDays()
    local stamp = md[PF.STAMP_KEY]
    if stamp == nil then
        md[PF.STAMP_KEY] = now
        md[PF.AGE_KEY] = worldGenerated and PF.worldGeneratedAge() or 0
    else
        local dt = math.max(0, now - stamp)
        md[PF.AGE_KEY] = (md[PF.AGE_KEY] or 0) + dt * PF.rateFor(PF.outerContainer(item:getContainer()))
        md[PF.STAMP_KEY] = now
    end

    if md[PF.AGE_KEY] >= life then
        PF.spoilDrink(item, fc)
        return true
    end
    return false
end

----------------------------------------------------------------------------
-- Everything the mod does to one item, and to a whole container
----------------------------------------------------------------------------

function PF.processItem(item, worldGenerated)
    if not PF.enabled() then return end
    PF.patchItem(item, worldGenerated)
    PF.ageDrink(item, worldGenerated)
end

-- Walks a container, including bags (depth-limited like the gasoline mod).
function PF.processContainer(container, worldGenerated, depth)
    depth = depth or 0
    if not container or depth > 4 or not PF.enabled() then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        PF.processItem(item, worldGenerated)
        if instanceof(item, "InventoryContainer") then
            PF.processContainer(item:getInventory(), worldGenerated, depth + 1)
        end
    end
end
