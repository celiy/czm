--[[
    Gasoline Degradation - interactions that count as "recently accessed"

    Fueling and siphoning actions touch the vehicle or pump when they start:
    first the object's gasoline is brought up to date, then the access time is
    recorded (see GD.touch in GD_Core.lua). The hooks wrap the vanilla timed
    actions and call the original unchanged. They only act where the action
    really runs (singleplayer or the server), never on a multiplayer client.
]]

require "GasolineDegradation/GD_Core"
require "Vehicles/TimedActions/ISAddGasolineToVehicle"
require "Vehicles/TimedActions/ISTakeGasolineFromVehicle"
require "Vehicles/TimedActions/ISRefuelFromGasPump"
require "TimedActions/ISTakeFuel"

local GD = GasolineDegradation

local function wrap(class, method, touchFn)
    local original = class[method]
    if not original then return end
    class[method] = function(self, ...)
        if not isClient() and GD.isEnabled() then
            local ok, err = pcall(touchFn, self)
            if not ok then print("[GasolineDegradation] access hook failed: " .. tostring(err)) end
        end
        return original(self, ...)
    end
end

local function touchPart(self)
    if self.part then GD.touchVehicle(self.part:getVehicle()) end
end

local function touchPartAndPump(self)
    touchPart(self)
    GD.touchPump(self.fuelStation)
end

local function touchPumpOnly(self)
    GD.touchPump(self.fuelStation)
end

for _, method in ipairs({ "start", "serverStart" }) do
    wrap(ISAddGasolineToVehicle, method, touchPart)
    wrap(ISTakeGasolineFromVehicle, method, touchPart)
    wrap(ISRefuelFromGasPump, method, touchPartAndPump)
    wrap(ISTakeFuel, method, touchPumpOnly)
end

----------------------------------------------------------------------------
-- Every other way a player uses a vehicle or moves items between containers
--
-- Doors, trunk, hood, windows, parts, engine, locks, washing, hotwiring:
-- each vanilla timed action gets the vehicle touched when it is created.
-- Item transfers (inventory <-> bag, container <-> container, floor) touch
-- both the source and the destination container. A player's own inventory
-- has no holder, so carrying an item never touches anything extra.
----------------------------------------------------------------------------

local VEHICLE_ACTIONS = {
    { "Vehicles/TimedActions/ISOpenVehicleDoor", "ISOpenVehicleDoor" },
    { "Vehicles/TimedActions/ISCloseVehicleDoor", "ISCloseVehicleDoor" },
    { "Vehicles/TimedActions/ISOpenCloseVehicleWindow", "ISOpenCloseVehicleWindow" },
    { "Vehicles/TimedActions/ISLockVehicleDoor", "ISLockVehicleDoor" },
    { "Vehicles/TimedActions/ISUnlockVehicleDoor", "ISUnlockVehicleDoor" },
    { "Vehicles/TimedActions/ISLockDoors", "ISLockDoors" },
    { "Vehicles/TimedActions/ISInstallVehiclePart", "ISInstallVehiclePart" },
    { "Vehicles/TimedActions/ISUninstallVehiclePart", "ISUninstallVehiclePart" },
    { "Vehicles/TimedActions/ISFixVehiclePartAction", "ISFixVehiclePartAction" },
    { "Vehicles/TimedActions/ISStartVehicleEngine", "ISStartVehicleEngine" },
    { "Vehicles/TimedActions/ISShutOffVehicleEngine", "ISShutOffVehicleEngine" },
    { "Vehicles/TimedActions/ISWashVehicle", "ISWashVehicle" },
    { "Vehicles/TimedActions/ISHotwireVehicle", "ISHotwireVehicle" },
    { "Vehicles/TimedActions/ISTakeEngineParts", "ISTakeEngineParts" },
    { "Vehicles/TimedActions/ISSmashVehicleWindow", "ISSmashVehicleWindow" },
}

-- The vehicle an argument refers to: the vehicle itself, or a part's vehicle.
local function vehicleOf(arg)
    if not arg then return nil end
    if instanceof(arg, "BaseVehicle") then return arg end
    if instanceof(arg, "VehiclePart") then return arg:getVehicle() end
    return nil
end

local function hookVehicleActions()
    for _, entry in ipairs(VEHICLE_ACTIONS) do
        local ok = pcall(require, entry[1])
        local class = ok and _G[entry[2]]
        if class and class.new then
            local original = class.new
            class.new = function(self, a, b, c, ...)
                if not isClient() and GD.isEnabled() then
                    local v = vehicleOf(b) or vehicleOf(a) or vehicleOf(c)
                    if v then GD.touchVehicle(v) end
                end
                return original(self, a, b, c, ...)
            end
        end
    end
end

-- ISInventoryTransferUtil creates the action for every item move a player
-- makes; ISTransferAction moves the item when it really happens.
local function hookTransfers()
    pcall(require, "TimedActions/ISInventoryTransferUtil")
    local util = _G["ISInventoryTransferUtil"]
    if util and util.newInventoryTransferAction then
        local original = util.newInventoryTransferAction
        util.newInventoryTransferAction = function(character, item, srcContainer, destContainer, ...)
            if not isClient() and GD.isEnabled() then
                if srcContainer then GD.touchContainer(srcContainer) end
                if destContainer then GD.touchContainer(destContainer) end
            end
            return original(character, item, srcContainer, destContainer, ...)
        end
    end
end

hookVehicleActions()
hookTransfers()
