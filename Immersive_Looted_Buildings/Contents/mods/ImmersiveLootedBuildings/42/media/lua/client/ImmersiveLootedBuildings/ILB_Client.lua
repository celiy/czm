--[[
    Immersive Looted Buildings - late cut (singleplayer)

    When the loot window lists the containers next to the player, after the
    container buttons are added and before their items are shown, each
    container of a tier room gets today's decision if it was not cut yet:
    containers filled before the mod was added, or checked on a day the
    building was not looted yet. Buildings the player used are left alone
    until abandoned (see ILB.mayChange). Then the visit is recorded.

    Multiplayer clients do nothing here: the server owns the containers.
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local function lateCheck(container, now, today, touched)
    local def, room, square = ILB.locate(container)
    if not def then return end
    local tier = ILB.tierOf(room)
    if not tier then return end
    local key = ILB.buildingKey(def)
    if not touched[key] then
        touched[key] = { def = def, may = ILB.mayChange(def, now) }
    end
    if tier ~= "Overrun" and ILB.opt("LateCut", true) and touched[key].may then
        local state, day = ILB.getState(container)
        -- Cut and skipped containers are final; a container checked today is
        -- not checked again until tomorrow.
        if state == nil or (state == ILB.STATE.CHECKED and day < today) then
            ILB.apply(container, def, tier, square, "late")
        end
    end
end

local function onRefresh(page, step)
    if step ~= "buttonsAdded" or isClient() or page.onCharacter then return end
    if not ILB.isEnabled() then return end
    local now = ILB.day()
    local today = math.floor(now)
    local touched = {}
    for _, button in ipairs(page.backpacks or {}) do
        local c = button.inventory
        if c and c:getType() ~= "floor" then
            local ok, err = pcall(lateCheck, c, now, today, touched)
            if not ok then print("[ImmersiveLootedBuildings] late check failed: " .. tostring(err)) end
        end
    end
    -- Record the visit after deciding, so the decision uses the activity
    -- before this visit.
    for _, t in pairs(touched) do ILB.touch(t.def, 0) end
end

Events.OnRefreshInventoryWindowContainers.Add(onRefresh)

-- For the tests: the same handler, called with a page of chosen containers.
ILB.onLootWindowRefresh = onRefresh
