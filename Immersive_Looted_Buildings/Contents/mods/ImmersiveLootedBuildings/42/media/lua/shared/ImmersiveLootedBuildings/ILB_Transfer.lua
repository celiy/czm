--[[
    Immersive Looted Buildings - player item moves

    Wraps the vanilla ISTransferAction:transferItem, which really moves an
    item. An item put into a container of a tier room gets the ILB_player tag
    (the mod never removes tagged items) and counts as stored in that
    building; taking an item out counts as activity. Runs only where the
    action really runs (singleplayer or the server).
]]

require "ImmersiveLootedBuildings/ILB_Core"
pcall(require, "TimedActions/ISTransferAction")

local ILB = ImmersiveLootedBuildings

local function tierBuilding(container)
    if not container or container:getType() == "floor" then return nil end
    local def, room = ILB.locate(container)
    if not def or not ILB.tierOf(room) then return nil end
    return def
end

local function onTransfer(item, src, dest)
    local destDef = tierBuilding(dest)
    if destDef then
        item:getModData()[ILB.TAG] = true
        ILB.touch(destDef, "use", 1)
    end
    local srcDef = tierBuilding(src)
    if srcDef and (not destDef or ILB.buildingKey(srcDef) ~= ILB.buildingKey(destDef)) then ILB.touch(srcDef, "use", 0) end
end

local function hook()
    if not ISTransferAction or not ISTransferAction.transferItem or ISTransferAction.ILB_wrapped then return end
    local original = ISTransferAction.transferItem
    ISTransferAction.ILB_wrapped = true
    ISTransferAction.transferItem = function(self, character, item, srcContainer, destContainer, dropSquare, ...)
        local result = original(self, character, item, srcContainer, destContainer, dropSquare, ...)
        if not isClient() and item and ILB.isEnabled() then
            local ok, err = pcall(onTransfer, item, srcContainer, destContainer)
            if not ok then print("[ImmersiveLootedBuildings] transfer hook failed: " .. tostring(err)) end
        end
        return result
    end
end

hook()
Events.OnGameStart.Add(hook)
