--[[
    Immersive Looted Buildings - fill handler (singleplayer and server)

    OnFillContainer fires after the game fills a container. Most containers
    are in houses and leave at the first table lookup. Containers in tier
    rooms are queued: the game turns some buildings into "looted" buildings
    after filling them, once the whole building is loaded (a building can
    span several chunks), and only then can they be recognised.

    The queue is checked every CHECK_TICKS ticks, only while it has entries:
    the tick handler is added with the first entry and removes itself when the
    queue is empty. An entry is handled on the first check after its building
    was seen fully loaded, so the game's own pass has run by then. Entries
    whose square was unloaded are dropped (the first-look check covers them).
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local CHECK_TICKS = 30
local pending = {}
local ticking = false
local tickCount = 0

local function handle(p)
    local c, def, tier = p.container, p.def, p.tier
    if ILB.isVanillaLooted(def) then
        ILB.setState(c, ILB.STATE.SKIP, ILB.day())
        ILB.stats.skippedVanilla = ILB.stats.skippedVanilla + 1
        return
    end
    if not ILB.mayChange(def) then
        ILB.setState(c, ILB.STATE.CHECKED, ILB.day())
        return
    end
    ILB.apply(c, def, tier, p.square, p.refill and "refill" or "fill")
end

-- force: handle every entry now, loaded or not (tests).
local function processPending(force)
    local keep = {}
    local streamed = {} -- per building, this check
    for _, p in ipairs(pending) do
        local ok, err = pcall(function()
            local sq = p.square
            if getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then return end -- unloaded
            local key = p.key
            if streamed[key] == nil then streamed[key] = p.def:isFullyStreamedIn() end
            if force == true or (streamed[key] and p.seenStreamed) then
                handle(p)
            else
                if streamed[key] then p.seenStreamed = true end
                keep[#keep + 1] = p
            end
        end)
        if not ok then print("[ImmersiveLootedBuildings] fill handling failed: " .. tostring(err)) end
    end
    pending = keep
    if #pending == 0 and ticking then
        Events.OnTick.Remove(ILB.onFillTick)
        ticking = false
    end
end

function ILB.onFillTick()
    tickCount = tickCount + 1
    if tickCount < CHECK_TICKS then return end
    tickCount = 0
    processPending(false)
end

local function onFill(roomName, containerType, container)
    local tier = ILB.tierOf(roomName)
    if not tier then return end
    if not container or not ILB.isEnabled() then return end
    local def, _, square = ILB.locate(container)
    if not def then return end
    local state = ILB.getState(container)
    local refill = state ~= nil
    if refill then
        -- A container the mod already saw is being filled again (loot respawn
        -- or a manual fill).
        if state == ILB.STATE.SKIP or not ILB.opt("ApplyOnRespawn", true) then return end
    end
    pending[#pending + 1] = { container = container, def = def, key = ILB.buildingKey(def), tier = tier, square = square, refill = refill }
    if not ticking then
        ticking = true
        tickCount = 0
        Events.OnTick.Add(ILB.onFillTick)
    end
end

Events.OnFillContainer.Add(onFill)

-- For the tests.
ILB.onFill = onFill
ILB.flushPending = function() processPending(true) end
ILB.pendingCount = function() return #pending end
