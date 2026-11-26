--[[
    Immersive Looted Buildings - visits and waiting removals (OnPlayerMove)

    * Entering a shop counts as a visit (recent-visit pause). It is checked
      only when the player's building changes, so walking inside one building
      or in the open costs one lookup per move.
    * Buildings in ILB.deferred (looked at, or with a removal that had to
      wait) are checked every WATCH_MOVES moves, and only when there are
      some: once a building is unloaded it is forgotten (its next load
      handles it); once no player is within the protect radius, its waiting
      removals run.
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local WATCH_MOVES = 30
local moves = 0
local lastBuilding = {} -- player index -> building key (nil outside)

local function loaded(def)
    local rooms = def:getRooms()
    if rooms:size() == 0 then return false end
    local rd = rooms:get(0)
    return getCell():getGridSquare(rd:getX(), rd:getY(), rd:getZ()) ~= nil
end

function ILB.checkDeferred()
    for key, def in pairs(ILB.deferred) do
        if not loaded(def) then
            ILB.deferred[key] = nil
            ILB.seen[key] = nil
        elseif not ILB.playerNear(def) then
            ILB.deferred[key] = nil
            ILB.seen[key] = nil
            if ILB.processBuilding then ILB.processBuilding(def, false, "away") end
        end
    end
end

local function onPlayerMove(player)
    if not player or not ILB.isEnabled() then return end
    -- Entering a shop.
    local sq = player:getCurrentSquare()
    local b = sq and sq:getBuilding()
    local def = b and b:getDef()
    local idx = player:getPlayerNum() or 0
    local key = def and ILB.buildingKey(def) or nil
    if key ~= lastBuilding[idx] then
        lastBuilding[idx] = key
        if def and ILB.isShop(def) then ILB.touch(def, "enter") end
    end
    -- Waiting removals.
    local any = false
    for _ in pairs(ILB.deferred) do any = true break end -- the game's Lua has no next()
    if not any then return end
    moves = moves + 1
    if moves < WATCH_MOVES then return end
    moves = 0
    local ok, err = pcall(ILB.checkDeferred)
    if not ok then print("[ImmersiveLootedBuildings] watch failed: " .. tostring(err)) end
end

Events.OnPlayerMove.Add(onPlayerMove)

-- For the tests.
ILB.onPlayerMove = onPlayerMove
