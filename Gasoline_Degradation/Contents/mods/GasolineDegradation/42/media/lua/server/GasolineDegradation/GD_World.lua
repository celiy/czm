--[[
    Gasoline Degradation - world scheduler (singleplayer and server)

    Runs on the in-game clock, never per frame:
      * every CheckIntervalMinutes (default 1): loaded vehicles and the known
        pumps, barrels and floor items;
      * every 10 in-game minutes: the players' own inventories, occupied
        vehicles and floor items near players;
      * when a square loads: find pumps/barrels on it and catch them up;
      * when loot spawns into a container: catch the new gasoline up;
    Whatever is far away is caught up the next time it is loaded or seen
    (see GD_Core.lua), so there is no need to touch the whole map.
]]

require "GasolineDegradation/GD_Core"

if isClient() then return end -- multiplayer clients: the server does the work

local GD = GasolineDegradation

GD.squares = GD.squares or {}  -- "x,y,z" -> {x, y, z}: squares with pumps/barrels
local minutesSinceWorldCheck = 0

local function squareKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- Java HashSet / ArrayList iteration helper.
local function forEachVehicle(fn)
    local vehicles = getCell() and getCell():getVehicles()
    if not vehicles then return end
    local it = vehicles:iterator()
    while it:hasNext() do
        fn(it:next())
    end
end

local function processPlayers(now)
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            GD.processContainer(players:get(i):getInventory(), now, true)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player and not player:isDead() then
                GD.processContainer(player:getInventory(), now, true)
            end
        end
    end
end

local function trackSquare(square)
    GD.squares[squareKey(square:getX(), square:getY(), square:getZ())] =
        { square:getX(), square:getY(), square:getZ() }
end

-- Squares near players, to pick up gas cans dropped on the floor after the
-- square was loaded (LoadGridsquare only sees what was there at load time).
local SCAN_RADIUS = 12
local function scanAroundPlayers(now)
    local cell = getCell()
    local function scan(player)
        local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
        for x = px - SCAN_RADIUS, px + SCAN_RADIUS do
            for y = py - SCAN_RADIUS, py + SCAN_RADIUS do
                local square = cell:getGridSquare(x, y, pz)
                if square and square:getWorldObjects():size() > 0
                        and not GD.squares[squareKey(x, y, pz)]
                        and GD.processSquare(square, now) then
                    trackSquare(square)
                end
            end
        end
    end
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do scan(players:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player and not player:isDead() then scan(player) end
        end
    end
end

local function processKnownSquares(now)
    local cell = getCell()
    for key, pos in pairs(GD.squares) do
        local square = cell:getGridSquare(pos[1], pos[2], pos[3])
        if not square or not GD.processSquare(square, now) then
            GD.squares[key] = nil -- unloaded or nothing left there
        end
    end
end

-- A vehicle with someone inside counts as being used.
local function touchOccupiedVehicles()
    forEachVehicle(function(vehicle)
        for seat = 0, vehicle:getMaxPassengers() - 1 do
            if vehicle:getCharacter(seat) then
                GD.touchVehicle(vehicle)
                return
            end
        end
    end)
end

local minutesSincePlayerCheck = 0

local function everyMinute()
    if not GD.isEnabled() then return end
    local now = GD.elapsedDays()

    -- Players' own things, every 10 minutes.
    minutesSincePlayerCheck = minutesSincePlayerCheck + 1
    if minutesSincePlayerCheck >= 10 then
        minutesSincePlayerCheck = 0
        if GD.accessDelayEnabled() then touchOccupiedVehicles() end
        GD.containerCache = {}
        processPlayers(now)
        scanAroundPlayers(now)
    end

    -- Loaded vehicles, pumps, barrels and floor items.
    minutesSinceWorldCheck = minutesSinceWorldCheck + 1
    if minutesSinceWorldCheck >= (GD.options().CheckIntervalMinutes or 1) then
        minutesSinceWorldCheck = 0
        forEachVehicle(function(vehicle) GD.processVehicle(vehicle, now) end)
        processKnownSquares(now)
    end
end

local function onLoadGridsquare(square)
    if not GD.isEnabled() then return end
    if GD.processSquare(square, GD.elapsedDays()) then trackSquare(square) end
end

-- Freshly generated loot: catch it up from the start of the clock.
local function onFillContainer(roomName, containerType, container)
    if not GD.isEnabled() then return end
    if container and instanceof(container, "ItemContainer") then
        GD.processContainer(container, GD.elapsedDays(), false)
    end
end

----------------------------------------------------------------------------
-- Debug helpers, for the Lua console (game started with -debug):
--   GDReport()      prints the curve state and the gasoline around player 1
--   GDForceCheck()  runs the vehicle/pump/inventory update right now
----------------------------------------------------------------------------

function GDForceCheck()
    local now = GD.elapsedDays()
    GD.containerCache = {}
    if GD.accessDelayEnabled() then touchOccupiedVehicles() end
    processPlayers(now)
    scanAroundPlayers(now)
    forEachVehicle(function(vehicle) GD.processVehicle(vehicle, now) end)
    processKnownSquares(now)
    print("[GasolineDegradation] forced check at degradation day " .. string.format("%.2f", now))
end

function GDReport()
    local now = GD.elapsedDays()
    local o = GD.options()
    print(string.format("[GasolineDegradation] enabled=%s  world day %.2f  degradation day %.2f  lifetime %s days  (10 L after 30 days: %.2f L)  delay=%s/%s days",
        tostring(GD.isEnabled()), getGameTime():getWorldAgeHours() / 24, now,
        tostring(o.DaysToFullDegradation), 10 * GD.decayFactor(30),
        tostring(GD.accessDelayEnabled()), tostring(GD.accessDelayDays())))

    local player = getSpecificPlayer(0)
    if not player then return end

    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fc = item:getFluidContainer()
        if fc and not fc:isEmpty() and fc:getSpecificFluidAmount(Fluid.Petrol) > 0 then
            print(string.format("  item %s: %.2f L petrol, stamp=%s", item:getFullType(),
                fc:getSpecificFluidAmount(Fluid.Petrol), tostring(item:getModData()[GD.KEY])))
        end
    end

    forEachVehicle(function(vehicle)
        if vehicle:DistTo(player) <= 30 then
            for i = 0, vehicle:getPartCount() - 1 do
                local part = vehicle:getPartByIndex(i)
                if part:isContainer() and part:getContainerContentType() == "Gasoline" then
                    print(string.format("  vehicle %s part %s: %.2f / %d L, stamp=%s", vehicle:getScriptName(),
                        part:getId(), part:getContainerContentAmount(), part:getContainerCapacity(),
                        tostring(part:getModData()[GD.KEY])))
                end
            end
        end
    end)

    local cell = getCell()
    local count = 0
    for _, pos in pairs(GD.squares) do
        count = count + 1
        local square = cell:getGridSquare(pos[1], pos[2], pos[3])
        if square and math.abs(pos[1] - player:getX()) <= 30 and math.abs(pos[2] - player:getY()) <= 30 then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if GD.isGasPump(obj) then
                    local md = obj:getModData()
                    print(string.format("  pump %d,%d: fuelAmount=%s, stamp=%s", pos[1], pos[2],
                        tostring(md.fuelAmount), tostring(md[GD.KEY])))
                end
                if instanceof(obj, "IsoWorldInventoryObject") then
                    local item = obj:getItem()
                    local fc = item and item:getFluidContainer()
                    if fc and not fc:isEmpty() and fc:getSpecificFluidAmount(Fluid.Petrol) > 0 then
                        print(string.format("  floor %s at %d,%d: %.2f L petrol, stamp=%s", item:getFullType(),
                            pos[1], pos[2], fc:getSpecificFluidAmount(Fluid.Petrol), tostring(item:getModData()[GD.KEY])))
                    end
                end
            end
        end
    end
    print("  tracked squares (pumps/barrels/floor items): " .. count)
end

Events.EveryOneMinute.Add(everyMinute)
Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnFillContainer.Add(onFillContainer)
