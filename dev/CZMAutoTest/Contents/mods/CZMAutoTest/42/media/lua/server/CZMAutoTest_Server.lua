-- CZM Auto Test (development only): counts the game's container fill events.
-- Registered from a server file, where OnFillContainer is known to work.
CZM_FILLS = { count = 0, byRoom = {}, samples = {} }

Events.OnFillContainer.Add(function(roomName, containerType, container)
    CZM_FILLS.count = CZM_FILLS.count + 1
    local r = tostring(roomName)
    CZM_FILLS.byRoom[r] = (CZM_FILLS.byRoom[r] or 0) + 1
    if #CZM_FILLS.samples < 6 then
        CZM_FILLS.samples[#CZM_FILLS.samples + 1] = r .. "/" .. tostring(containerType) .. "/" .. tostring(container and container:getItems():size())
    end
end)
