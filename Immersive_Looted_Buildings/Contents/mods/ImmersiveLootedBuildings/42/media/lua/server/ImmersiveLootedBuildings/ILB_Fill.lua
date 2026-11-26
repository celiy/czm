--[[
    Immersive Looted Buildings - fills and building loads (singleplayer and server)

    Two moments when nobody has seen a shop's contents yet:

    * OnFillContainer: the game just created the contents of a container.
    * LoadChunk: a chunk with part of a shop was loaded, so the shop was out
      of reach before.

    Both are queued and handled once the whole building is loaded: the game
    turns some buildings into "looted" buildings after filling them, once
    they are fully loaded, and only then can they be recognised. The queue is
    checked every CHECK_TICKS ticks only while it has entries; the tick
    handler removes itself when the queue is empty.
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local CHECK_TICKS = 30
local CHUNK = 8 -- squares per chunk side in Build 42
local pending = {}
local pendingBuildings = {} -- building key -> true while a load entry waits
local ticking = false
local tickCount = 0

----------------------------------------------------------------------------
-- Shop index: chunk -> shop buildings touching it (built from the map data)
----------------------------------------------------------------------------

local index, indexVersion, indexCount = nil, nil, 0

local function buildIndex()
    ILB.config()
    local ok, all = pcall(function() return getWorld():getMetaGrid():getBuildings() end)
    if not ok or not all or all:size() == 0 then return nil end
    local idx, count = {}, 0
    for i = 0, all:size() - 1 do
        local def = all:get(i)
        if ILB.isShop(def) then
            count = count + 1
            local x1, y1 = def:getX(), def:getY()
            local x2, y2 = x1 + def:getW() - 1, y1 + def:getH() - 1
            for cx = math.floor(x1 / CHUNK), math.floor(x2 / CHUNK) do
                for cy = math.floor(y1 / CHUNK), math.floor(y2 / CHUNK) do
                    local k = cx .. "," .. cy
                    local list = idx[k]
                    if not list then list = {}; idx[k] = list end
                    list[#list + 1] = def
                end
            end
        end
    end
    index, indexVersion, indexCount = idx, ILB.version, count
    return idx
end

function ILB.shopIndex()
    ILB.config()
    if index == nil or indexVersion ~= ILB.version then buildIndex() end
    return index, indexCount
end

----------------------------------------------------------------------------
-- Processing
----------------------------------------------------------------------------

local function stillLoaded(def)
    local rooms = def:getRooms()
    if rooms:size() == 0 then return false end
    local rd = rooms:get(0)
    return getCell():getGridSquare(rd:getX(), rd:getY(), rd:getZ()) ~= nil
end

-- Mark a removal that had to wait: the container keeps its A and its last
-- update day is set to yesterday, so the next allowed moment updates it.
local function defer(container, def, t, a)
    ILB.setState(container, a or 1, math.floor(t) - 1)
    ILB.deferred[ILB.buildingKey(def)] = def
    ILB.stats.deferred = ILB.stats.deferred + 1
end

-- beforeShown: run from the loot window before the items are shown.
local function handleFill(p, t, beforeShown)
    local c, def, tier = p.container, p.def, p.tier
    if not ILB.isLossTier(tier) then
        -- Overrun room: the bonus once at the first fill, again on a respawn refill.
        if p.refill and not ILB.opt("ApplyOnRespawn", true) then return end
        local added = ILB.bonusContainer(c, ILB.opt("OverrunBonus", 25) / 100)
        ILB.stats.bonus = ILB.stats.bonus + added
        ILB.setState(c, 1, t)
        ILB.log("bonus %s +%d", ILB.buildingKey(def), added)
        return
    end
    local a = ILB.getState(c)
    if a == ILB.SKIPPED then return end
    if not p.refill and ILB.isVanillaLooted(def) then
        ILB.setState(c, ILB.SKIPPED, t)
        ILB.stats.skippedVanilla = ILB.stats.skippedVanilla + 1
        return
    end
    if p.refill and not ILB.opt("ApplyOnRespawn", true) then return end
    if ILB.keep(def, tier, t) == nil then return end -- a base never loses loot
    if beforeShown or ILB.mayRemove(def, true) then
        ILB.update(c, def, tier, t, p.refill and "refill" or "fill", true)
    else
        defer(c, def, t, 1) -- the player is looking at this building: wait
    end
end

-- Bring every container of a loaded shop to today's loot.
-- fresh: right after a load (nobody saw it since).
function ILB.processBuilding(def, fresh, why)
    if not ILB.isEnabled() or not ILB.isShop(def) then return 0 end
    if not ILB.mayRemove(def, fresh) then
        ILB.deferred[ILB.buildingKey(def)] = def
        return 0
    end
    local t = ILB.day()
    -- Traces of a player base (a running generator, furniture moved by a
    -- player): the shop becomes a base and loses nothing.
    if ILB.scanBaseTraces and not ILB.isBase(ILB.record(def)) then
        local reason = ILB.scanBaseTraces(def)
        if reason then ILB.markBase(def, reason .. " (found at load)", t) end
    end
    local vanilla = ILB.isVanillaLooted(def)
    local removed = 0
    ILB.forEachContainer(def, function(c, tier)
        if not ILB.isLossTier(tier) then return end
        local a = ILB.getState(c)
        if a == nil then
            if not c:isExplored() then return end -- not filled yet: the fill handles it
            if vanilla then
                ILB.setState(c, ILB.SKIPPED, t)
                ILB.stats.skippedVanilla = ILB.stats.skippedVanilla + 1
                return
            end
        end
        local r = ILB.update(c, def, tier, t, why or "load")
        removed = removed + (r or 0)
    end)
    return removed
end

local function handleLoad(p)
    pendingBuildings[p.key] = nil
    ILB.stats.loads = (ILB.stats.loads or 0) + 1
    ILB.processBuilding(p.def, true, "load")
end

local function processPending(force)
    local keep = {}
    local streamed = {}
    local t = ILB.day()
    for _, p in ipairs(pending) do
        local ok, err = pcall(function()
            if p.square then
                local sq = p.square
                if getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then return end -- unloaded
            elseif not stillLoaded(p.def) then
                pendingBuildings[p.key] = nil
                return
            end
            if streamed[p.key] == nil then streamed[p.key] = p.def:isFullyStreamedIn() end
            if force == true or (streamed[p.key] and p.seenStreamed) then
                if p.kind == "fill" then handleFill(p, t) else handleLoad(p) end
            else
                if streamed[p.key] then p.seenStreamed = true end
                keep[#keep + 1] = p
            end
        end)
        if not ok then print("[ImmersiveLootedBuildings] queue failed: " .. tostring(err)) end
    end
    pending = keep
    if #pending == 0 and ticking then
        Events.OnTick.Remove(ILB.onQueueTick)
        ticking = false
    end
end

function ILB.onQueueTick()
    tickCount = tickCount + 1
    if tickCount < CHECK_TICKS then return end
    tickCount = 0
    processPending(false)
end

local function enqueue(entry)
    pending[#pending + 1] = entry
    if not ticking then
        ticking = true
        tickCount = 0
        Events.OnTick.Add(ILB.onQueueTick)
    end
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local function onFill(roomName, containerType, container)
    local tier = ILB.tierOf(roomName)
    if not tier then return end
    if not container or not ILB.isEnabled() then return end
    local def, _, square = ILB.locate(container)
    if not def then return end
    local refill = ILB.getState(container) ~= nil
    enqueue({ kind = "fill", container = container, def = def, key = ILB.buildingKey(def), tier = tier, square = square, refill = refill })
end

local function onLoadChunk(chunk)
    if not chunk or not ILB.isEnabled() then return end
    ILB.stats.loadEvents = (ILB.stats.loadEvents or 0) + 1
    local sq = chunk:getGridSquare(0, 0, 0)
    if not sq then
        for z = chunk:getMinLevel(), chunk:getMaxLevel() do
            sq = chunk:getGridSquare(0, 0, z)
            if sq then break end
        end
    end
    if not sq then return end
    local idx = ILB.shopIndex()
    if not idx then return end
    local list = idx[math.floor(sq:getX() / CHUNK) .. "," .. math.floor(sq:getY() / CHUNK)]
    if not list then return end
    for _, def in ipairs(list) do
        local key = ILB.buildingKey(def)
        if not pendingBuildings[key] then
            pendingBuildings[key] = true
            enqueue({ kind = "load", def = def, key = key })
        end
    end
end

Events.OnFillContainer.Add(onFill)
Events.LoadChunk.Add(onLoadChunk)

-- Run everything waiting for this building now (it must be fully loaded).
-- Called by the loot window before it shows the items: the load or the fill
-- comes first, then the player sees the result.
function ILB.flushBuilding(def)
    if #pending == 0 then return end
    local key = ILB.buildingKey(def)
    if not def:isFullyStreamedIn() then return end
    local keep, mine = {}, {}
    for _, p in ipairs(pending) do
        if p.key == key then mine[#mine + 1] = p else keep[#keep + 1] = p end
    end
    if #mine == 0 then return end
    pending = keep
    local t = ILB.day()
    for _, p in ipairs(mine) do
        local ok, err = pcall(function()
            if p.kind == "fill" then handleFill(p, t, true) else handleLoad(p) end
        end)
        if not ok then print("[ImmersiveLootedBuildings] flush failed: " .. tostring(err)) end
    end
    if #pending == 0 and ticking then
        Events.OnTick.Remove(ILB.onQueueTick)
        ticking = false
    end
end

-- For the tests.
ILB.onFill = onFill
ILB.onLoadChunk = onLoadChunk
ILB.flushPending = function() processPending(true) end
ILB.pendingCount = function() return #pending end
