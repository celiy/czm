--[[
    Immersive Looted Buildings - signs that the player uses a shop as a base

    A shop with any of these signs is a base and never loses loot:

    * Player actions (the vanilla timed actions, wrapped): barricading a door
      or window of the shop, placing furniture inside it, building something
      in or right next to it, turning on or plugging in a generator in or near
      it. Barricades the game itself puts on buildings when it creates the
      world never go through these actions, so they never count.
    * Traces found when the shop loads (for bases made before the mod was
      added): a running generator inside it, or furniture the game marks as
      moved by a player (isMovedThumpable).

    The items-stored and days-of-use rules in ILB_Core still apply too. The
    hooks act only where the action really runs (singleplayer or the server).
]]

require "ImmersiveLootedBuildings/ILB_Core"

local ILB = ImmersiveLootedBuildings

local NEAR_BUILD = 1      -- tiles: something built against the shop's walls
local NEAR_GENERATOR = 3  -- tiles: a generator standing next to the shop

-- Mark a shop as a base (saved in the activity record, permanent).
function ILB.markBase(def, reason, t)
    if not def or not ILB.isShop(def) then return false end
    local used = ILB.data().used
    local key = ILB.buildingKey(def)
    t = t or ILB.day()
    local r = used[key]
    if not r then
        r = { E = t, S = t, last = t, days = 0, stored = 0 }
        used[key] = r
    end
    if not r.baseSignal then
        r.baseSignal = reason
        r.baseDay = t
        ILB.log("base %s: %s", key, reason)
    end
    return true
end

-- Shops within `radius` tiles of (x, y): the square's own building first,
-- then the shop index for buildings around it.
function ILB.shopsNear(x, y, z, radius)
    local out, seen = {}, {}
    local sq = getCell():getGridSquare(x, y, z or 0)
    local b = sq and sq:getBuilding()
    local def = b and b:getDef()
    if def and ILB.isShop(def) then
        out[#out + 1] = def
        seen[ILB.buildingKey(def)] = true
    end
    if radius and radius > 0 and ILB.shopIndex then
        local idx = ILB.shopIndex()
        if idx then
            for cx = math.floor((x - radius) / 8), math.floor((x + radius) / 8) do
                for cy = math.floor((y - radius) / 8), math.floor((y + radius) / 8) do
                    for _, d in ipairs(idx[cx .. "," .. cy] or {}) do
                        local key = ILB.buildingKey(d)
                        if not seen[key] and ILB.distanceTo(d, x, y) <= radius then
                            seen[key] = true
                            out[#out + 1] = d
                        end
                    end
                end
            end
        end
    end
    return out
end

local function markNear(sq, radius, reason)
    if not sq then return 0 end
    local n = 0
    for _, def in ipairs(ILB.shopsNear(sq:getX(), sq:getY(), sq:getZ(), radius)) do
        if ILB.markBase(def, reason) then n = n + 1 end
    end
    return n
end

-- The handlers the wrapped actions call (also used by the tests).
function ILB.onPlayerBarricade(object)
    if not object then return 0 end
    local n = markNear(object:getSquare(), 0, "barricade")
    if object.getOppositeSquare then
        local ok, opp = pcall(function() return object:getOppositeSquare() end)
        if ok and opp then n = n + markNear(opp, 0, "barricade") end
    end
    return n
end

function ILB.onPlayerPlacedFurniture(square)
    return markNear(square, 0, "furniture")
end

function ILB.onPlayerBuilt(x, y, z)
    return markNear(getCell():getGridSquare(x, y, z or 0), NEAR_BUILD, "built")
end

function ILB.onPlayerGenerator(generator)
    if not generator then return 0 end
    return markNear(generator:getSquare(), NEAR_GENERATOR, "generator")
end

-- Traces a player leaves, read when the shop loads. Returns the reason or nil.
function ILB.scanBaseTraces(def)
    local rooms = def:getRooms()
    local cell = getCell()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local z = rd:getZ()
        for x = rd:getX(), rd:getX2() - 1 do
            for y = rd:getY(), rd:getY2() - 1 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local objs = sq:getObjects()
                    for oi = 0, objs:size() - 1 do
                        local obj = objs:get(oi)
                        if instanceof(obj, "IsoGenerator") and obj:isActivated() then return "generator" end
                        if instanceof(obj, "IsoThumpable") and obj:isMovedThumpable() then return "furniture" end
                    end
                end
            end
        end
    end
    return nil
end

----------------------------------------------------------------------------
-- Wrapping the vanilla actions (the original always runs first, unchanged)
----------------------------------------------------------------------------

local function wrapAfter(className, method, fn)
    local class = _G[className]
    if not class or not class[method] then return false end
    local flag = "ILB_wrapped_" .. method
    if class[flag] then return true end
    local original = class[method]
    class[method] = function(self, ...)
        local result = original(self, ...)
        if not isClient() and ILB.isEnabled() then
            local ok, err = pcall(fn, self, ...)
            if not ok then print("[ImmersiveLootedBuildings] base hook " .. className .. "." .. method .. " failed: " .. tostring(err)) end
        end
        return result
    end
    class[flag] = true
    return true
end

function ILB.hookBaseActions()
    pcall(require, "TimedActions/ISBarricadeAction")
    pcall(require, "Moveables/ISMoveablesAction")
    pcall(require, "TimedActions/ISActivateGenerator")
    pcall(require, "TimedActions/ISPlugGenerator")
    pcall(require, "BuildingObjects/ISBuildIsoEntity")
    local hooked = {}
    hooked.barricade = wrapAfter("ISBarricadeAction", "complete", function(self) ILB.onPlayerBarricade(self.item) end)
    hooked.furniture = wrapAfter("ISMoveablesAction", "complete", function(self)
        if self.mode == "place" and self.square then ILB.onPlayerPlacedFurniture(self.square) end
    end)
    hooked.generatorOn = wrapAfter("ISActivateGenerator", "complete", function(self)
        if self.activate and self.generator and self.generator:isActivated() then ILB.onPlayerGenerator(self.generator) end
    end)
    hooked.generatorPlug = wrapAfter("ISPlugGenerator", "complete", function(self)
        if self.plug and self.generator then ILB.onPlayerGenerator(self.generator) end
    end)
    hooked.built = wrapAfter("ISBuildIsoEntity", "create", function(self, x, y, z) ILB.onPlayerBuilt(x, y, z) end)
    ILB.baseHooks = hooked
    return hooked
end

ILB.hookBaseActions()
Events.OnGameStart.Add(ILB.hookBaseActions)
if Events.OnServerStarted then Events.OnServerStarted.Add(ILB.hookBaseActions) end
