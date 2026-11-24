--[[
    CZM Auto Test - development only, never published.

    Armed by a file in the game's Lua cache folder (czm_autotest.txt, written
    by dev/run-autotest.sh). When armed it starts a throw-away sandbox world
    from the main menu (the same way PZ Optimization's benchmark does), runs
    the checks below, prints "[CZM-TEST] ..." lines to console.txt and quits.
    Without that file it does nothing.
]]

local TAG = "[CZM-TEST] "
local WORLD = "czm-autotest"

-- The trigger file may name another world: "world=<name>" on its first line.
do
    local ok, reader = pcall(getFileReader, "czm_autotest.txt", false)
    if ok and reader then
        local line = reader:readLine()
        reader:close()
        local name = line and line:match("^world=(%S+)")
        if name then WORLD = name end
    end
end
local SPAWN = { x = 8283, y = 12262, z = 0 }

local state = { armed = nil, started = false, frames = 0, done = false, pass = 0, fail = 0, ingame = false, ingameFrames = 0 }

local function armed()
    if state.armed ~= nil then return state.armed end
    state.armed = false
    local ok, reader = pcall(getFileReader, "czm_autotest.txt", false)
    if ok and reader then
        reader:close()
        state.armed = true
    end
    return state.armed
end

local function check(name, cond, detail)
    if cond then
        state.pass = state.pass + 1
        print(TAG .. "PASS " .. name .. (detail and (" (" .. detail .. ")") or ""))
    else
        state.fail = state.fail + 1
        print(TAG .. "FAIL " .. name .. (detail and (" (" .. detail .. ")") or ""))
    end
end

local function finish(why)
    if state.done then return end
    state.done = true
    print(string.format("%sDONE pass=%d fail=%d %s", TAG, state.pass, state.fail, why or ""))
    getCore():quit()
end

-- ---------------------------------------------------------------- the world

local function startWorld()
    local ms = MainScreen.instance
    print(TAG .. "starting test world at " .. SPAWN.x .. "," .. SPAWN.y)
    ms:setDefaultSandboxVars()
    SandboxVars.Helicopter = 1
    SandboxVars.MetaEvent = 1
    SandboxVars.StarterKit = false
    SandboxVars.TimeSinceApo = 1
    SandboxVars.GasolineDegradation = SandboxVars.GasolineDegradation or {}
    local o = SandboxVars.GasolineDegradation
    o.Enabled = true
    o.StartDay = 0
    o.DaysToFullDegradation = 14
    o.AccessDelay = true
    o.AccessDelayDays = 14
    o.ContainerMinLiters = 0.5
    o.VehicleMinLiters = 1.0
    o.CheckIntervalMinutes = 1
    pcall(function() getSandboxOptions():updateFromLua() end)
    pcall(function() WorldGenParams.INSTANCE:setSeedString(WORLD) end)
    local okDesc = pcall(function() ms.desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, false) end)
    if not okDesc or not ms.desc then ms.desc = SurvivorFactory.CreateSurvivor() end
    selectedDebugScenario = { name = "czm autotest", startLoc = { x = SPAWN.x, y = SPAWN.y, z = SPAWN.z } }
    getWorld():setGameMode("Sandbox")
    getWorld():setMap("DEFAULT")
    getWorld():setWorld(WORLD)
    deleteSave("Sandbox/" .. WORLD)
    createWorld(WORLD)
    GameWindow.doRenderEvent(false)
    forceChangeState(LoadingQueueState.new())
end

-- ---------------------------------------------------------------- the checks

local function petrolCan(litres)
    local item = instanceItem("Base.PetrolCan")
    local fc = item:getFluidContainer()
    fc:Empty()
    fc:addFluid(Fluid.Petrol, litres)
    return item
end

local function petrolOf(item)
    -- Same getter the mod uses: it also covers items lying on the floor.
    local fc = item and item:getFluidContainerFromSelfOrWorldItem()
    if not fc then return -1 end
    return fc:getSpecificFluidAmount(Fluid.Petrol)
end

local function tankOf(vehicle)
    return vehicle:getPartById("GasTank")
end

local function near(a, b, tol)
    return math.abs(a - b) <= (tol or 0.05) * math.max(1, math.abs(b))
end

local function jumpDays(days)
    local gt = getGameTime()
    gt:setNightsSurvived(gt:getNightsSurvived() + days)
end

-- The checks run as steps, a few frames apart: a vehicle spawned in this
-- frame only joins the world's vehicle set on a later tick, and the mod
-- only sees vehicles in that set.
local steps = {}
local ctx = {}

local function runSteps()
    if #steps == 0 then return end
    local st = steps[1]
    st.wait = (st.wait or 0) - 1
    if st.wait > 0 then return end
    table.remove(steps, 1)
    local ok, err = pcall(st.fn)
    if not ok then
        state.fail = state.fail + 1
        print(TAG .. "FAIL step error: " .. tostring(err))
    end
end

local function queue(wait, fn)
    table.insert(steps, { wait = wait, fn = fn })
end

local function setupSteps()
    local GD = GasolineDegradation
    queue(1, function()
        check("mod loaded", GD ~= nil and GDForceCheck ~= nil)
        local o = SandboxVars.GasolineDegradation
        check("sandbox options reach the mod", o and o.DaysToFullDegradation == 14 and o.AccessDelay == true,
            o and ("lifetime=" .. tostring(o.DaysToFullDegradation)) or "no SandboxVars")
        local player = getSpecificPlayer(0)
        ctx.player = player
        ctx.px, ctx.py, ctx.pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
        local cell = getCell()
        local carSquare = cell:getGridSquare(ctx.px, ctx.py - 4, ctx.pz)
        ctx.car = carSquare and addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, carSquare)
        check("test car spawned", ctx.car ~= nil)
        ctx.tank = ctx.car and tankOf(ctx.car)
        if ctx.tank then
            ctx.cap = ctx.tank:getContainerCapacity()
            ctx.tank:setContainerContentAmount(ctx.cap)
            print(string.format("%sdiag tank capacity=%s", TAG, tostring(ctx.cap)))
        end
        -- floor can: check the fluid is still there after it is placed
        local floorSquare = cell:getGridSquare(ctx.px + 2, ctx.py, ctx.pz)
        ctx.floorCan = petrolCan(10)
        print(string.format("%sdiag floor can before place: %.2f L", TAG, petrolOf(ctx.floorCan)))
        ctx.floorSquare = floorSquare
        ctx.placed = floorSquare and floorSquare:AddWorldInventoryItem(ctx.floorCan, 0.5, 0.5, 0)
        print(string.format("%sdiag floor item after place: fluid=%.2f L (same object=%s)", TAG,
            petrolOf(ctx.placed), tostring(ctx.placed == ctx.floorCan)))
        local found = -1
        if floorSquare then
            local wos = floorSquare:getWorldObjects()
            for i = 0, wos:size() - 1 do
                local wo = wos:get(i)
                if wo:getItem() == ctx.placed or wo:getItem() == ctx.floorCan then found = petrolOf(wo:getItem()) end
            end
        end
        print(string.format("%sdiag floor world object fluid=%.2f L", TAG, found))
        ctx.carried = ctx.player:getInventory():AddItem(petrolCan(10))
        check("carried can in inventory", ctx.carried ~= nil)
    end)

    queue(120, function()
        local GD = GasolineDegradation
        local inSet = false
        local it = getCell():getVehicles():iterator()
        while it:hasNext() do if it:next() == ctx.car then inSet = true end end
        print(TAG .. "diag car in cell vehicles set after wait: " .. tostring(inSet))
        GDForceCheck() -- first sighting of the world-generated car
        ctx.day0 = GD.elapsedDays()
        local a = ctx.tank and ctx.tank:getContainerContentAmount() or -1
        check("first sighting matches the clock since start", ctx.tank ~= nil and near(a, ctx.cap * GD.decayFactor(ctx.day0), 0.03),
            string.format("%.2f L, expected %.2f", a, ctx.cap * GD.decayFactor(ctx.day0)))
    end)

    queue(1, function()
        local GD = GasolineDegradation
        jumpDays(7)
        local now = GD.elapsedDays()
        local dt = now - ctx.day0
        check("clock advanced about 7 days", dt > 6.5 and dt < 7.5, string.format("dt=%.2f", dt))
        GDForceCheck()
        local f = GD.decayFactor(now)
        local a = ctx.tank and ctx.tank:getContainerContentAmount() or -1
        check("car tank decayed with the curve", ctx.tank ~= nil and near(a, ctx.cap * f, 0.04),
            string.format("%.2f L, expected %.2f", a, ctx.cap * f))
        check("carried can did not degrade", near(petrolOf(ctx.carried), 10, 0.02), string.format("%.2f L", petrolOf(ctx.carried)))
    end)

    queue(60, function()
        local GD = GasolineDegradation
        local cell = getCell()
        local late = ctx.px and addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, cell:getGridSquare(ctx.px, ctx.py - 8, ctx.pz))
        ctx.late = late
        local lateTank = late and tankOf(late)
        if lateTank then lateTank:setContainerContentAmount(lateTank:getContainerCapacity()) end
        ctx.lateTank = lateTank
    end)

    queue(120, function()
        local GD = GasolineDegradation
        if not ctx.lateTank then check("late car spawned", false) return end
        GDForceCheck()
        local cap = ctx.lateTank:getContainerCapacity()
        local expect = cap * GD.decayFactor(GD.elapsedDays())
        local a = ctx.lateTank:getContainerContentAmount()
        check("car found on day 7 is caught up from day 0", near(a, expect, 0.06),
            string.format("%.2f L, expected %.2f", a, expect))
    end)

    queue(1, function()
        local GD = GasolineDegradation
        local player = ctx.player
        local cell = getCell()
        local dropSquare = cell:getGridSquare(ctx.px - 2, ctx.py, ctx.pz)
        player:getInventory():Remove(ctx.carried)
        dropSquare:AddWorldInventoryItem(ctx.carried, 0.5, 0.5, 0)
        jumpDays(1)
        GDForceCheck()
        check("can just put down is still inside its delay", near(petrolOf(ctx.carried), 10, 0.02), string.format("%.2f L", petrolOf(ctx.carried)))
        jumpDays(20)
        GDForceCheck()
        check("can put down 20 days ago has degraded", petrolOf(ctx.carried) < 9.5, string.format("%.2f L", petrolOf(ctx.carried)))
        ctx.part2 = true
    end)

    -- ---- recent access delay on a vehicle the player used
    queue(1, function()
        local GD = GasolineDegradation
        local tank = ctx.tank
        tank:setContainerContentAmount(tank:getContainerCapacity())
        GD.touchVehicle(ctx.car)
        ctx.touchAmount = tank:getContainerContentAmount()
        ctx.touchDay = GD.elapsedDays()
        check("used car is touched", ctx.touchAmount > 0, string.format("%.2f L", ctx.touchAmount))
    end)
    queue(1, function()
        local GD = GasolineDegradation
        jumpDays(1)
        GDForceCheck()
        check("used car keeps its gas during the 14-day delay", near(ctx.tank:getContainerContentAmount(), ctx.touchAmount, 0.01),
            string.format("%.2f L, expected %.2f", ctx.tank:getContainerContentAmount(), ctx.touchAmount))
    end)
    queue(1, function()
        local GD = GasolineDegradation
        jumpDays(14)
        GDForceCheck()
        local expect = ctx.touchAmount * GD.decayFactor(1) -- 1 day past the delay window
        check("used car degrades again after the delay", near(ctx.tank:getContainerContentAmount(), expect, 0.04),
            string.format("%.2f L, expected %.2f", ctx.tank:getContainerContentAmount(), expect))
    end)

    -- ---- gas pump loses fuel gradually
    queue(1, function()
        local GD = GasolineDegradation
        local cell = getCell()
        ctx.pump = nil
        for dx = -25, 25 do
            for dy = -25, 25 do
                if not ctx.pump then
                    local sq = cell:getGridSquare(ctx.px + dx, ctx.py + dy, ctx.pz)
                    if sq then
                        local objs = sq:getObjects()
                        for i = 0, objs:size() - 1 do
                            local o = objs:get(i)
                            if not ctx.pump and GD.isGasPump(o) then ctx.pump = o end
                        end
                    end
                end
            end
        end
        check("a gas pump is near the spawn", ctx.pump ~= nil)
        if ctx.pump then
            ctx.pump:setPipedFuelAmount(100)
            ctx.pumpDay0 = GD.elapsedDays()
            GDForceCheck()
        end
    end)
    queue(1, function()
        local GD = GasolineDegradation
        if not ctx.pump then return end
        jumpDays(7)
        GDForceCheck()
        local now = GD.elapsedDays()
        local expect = 100 * GD.decayFactor(now - ctx.pumpDay0)
        local got = ctx.pump:getPipedFuelAmount()
        check("gas pump loses fuel gradually", math.abs(got - expect) <= 2.5,
            string.format("%d L, expected about %.1f", got, expect))
        check("gas pump is not drained to the minimum", got > 5, string.format("%d L", got))
    end)

    -- ---- gas pumps can be switched off in the sandbox
    queue(1, function()
        local GD = GasolineDegradation
        if not ctx.pump then return end
        SandboxVars.GasolineDegradation.AffectGasPumps = false
        ctx.pump:setPipedFuelAmount(100)
        ctx.pump:getModData()[GD.KEY] = nil
        jumpDays(7)
        GDForceCheck()
        check("gas pumps untouched when AffectGasPumps is off", ctx.pump:getPipedFuelAmount() == 100,
            string.format("%d L", ctx.pump:getPipedFuelAmount()))
        SandboxVars.GasolineDegradation.AffectGasPumps = true
    end)

    -- ---- a container opened in the loot window: stamped, then degrades later
    queue(1, function()
        local GD = GasolineDegradation
        ctx.cont = nil
        local cell = getCell()
        for dx = -25, 25 do
            for dy = -25, 25 do
                if not ctx.cont then
                    local sq = cell:getGridSquare(ctx.px + dx, ctx.py + dy, ctx.pz)
                    if sq then
                        local objs = sq:getObjects()
                        for i = 0, objs:size() - 1 do
                            local o = objs:get(i)
                            if not ctx.cont and not GD.isGasPump(o) and o:getContainer() then ctx.cont = o:getContainer() end
                        end
                    end
                end
            end
        end
        check("a world container is near the spawn", ctx.cont ~= nil)
        if ctx.cont then
            ctx.contCan = instanceItem("Base.PetrolCan")
            ctx.contCan:getFluidContainer():Empty()
            ctx.contCan:getFluidContainer():addFluid(Fluid.Petrol, 10)
            ctx.cont:AddItem(ctx.contCan)
            GD.touchContainer(ctx.cont)
            ctx.contDay = GD.elapsedDays()
        end
    end)
    queue(1, function()
        local GD = GasolineDegradation
        if not ctx.cont then return end
        jumpDays(1)
        GD.processContainer(ctx.cont, GD.elapsedDays())
        check("can in a container keeps its gas right after it was opened", near(petrolOf(ctx.contCan), 10, 0.01),
            string.format("%.2f L", petrolOf(ctx.contCan)))
    end)
    queue(1, function()
        local GD = GasolineDegradation
        if not ctx.cont then return end
        jumpDays(14)
        GD.processContainer(ctx.cont, GD.elapsedDays())
        local expect = 10 * GD.decayFactor(1)
        check("can in a container degrades after the delay", near(petrolOf(ctx.contCan), expect, 0.04),
            string.format("%.2f L, expected %.2f", petrolOf(ctx.contCan), expect))
    end)

    -- ---- live sandbox changes take effect without a restart
    queue(1, function()
        local GD = GasolineDegradation
        local o = SandboxVars.GasolineDegradation
        o.DaysToFullDegradation = 28
        check("live change: lifetime 28 is used", near(GD.decayFactor(7), 0.05 ^ (7 / 28), 0.001),
            string.format("%.4f", GD.decayFactor(7)))
        o.DaysToFullDegradation = 14
        o.ContainerMinLiters = 2
        check("live change: container minimum is read", GD.containerMin() == 2, tostring(GD.containerMin()))
        o.ContainerMinLiters = 0.5
        local before = GD.elapsedDays()
        o.StartDay = 5
        local after = GD.elapsedDays()
        check("live change: start day shifts the clock", math.abs(after - math.max(0, before - 5)) < 0.01,
            string.format("before=%.2f after=%.2f", before, after))
        o.StartDay = 0
        o.Enabled = false
        check("live change: disable is read", GD.isEnabled() == false)
        o.Enabled = true
        check("live change: enable is read", GD.isEnabled() == true)
    end)

    -- ---- other ways of using a vehicle or container also start the delay
    queue(1, function()
        local GD = GasolineDegradation
        ctx.doorCar = ctx.car
        local part = ctx.car and ctx.car:getPartById("DoorFrontLeft")
        if not part then check("car has a front door part", false) return end
        ctx.beforeDoor = ctx.car:getModData()[GD.ACCESS_KEY]
        jumpDays(2)
        local act = ISOpenVehicleDoor:new(ctx.player, ctx.car, part)
        check("opening a door creates its timed action", act ~= nil)
        local acc = ctx.car:getModData()[GD.ACCESS_KEY]
        check("opening a door starts the car's delay", acc ~= nil and math.abs(acc - getGameTime():getWorldAgeHours() / 24) < 0.01,
            string.format("access day=%s now=%.3f", tostring(acc), getGameTime():getWorldAgeHours() / 24))
    end)

    queue(1, function()
        local GD = GasolineDegradation
        if not ctx.cont then return end
        local holder = GD.holderModData(ctx.cont)
        ctx.contHolder = holder
        local before = holder and holder[GD.ACCESS_KEY]
        jumpDays(2)
        local item = instanceItem("Base.PetrolCan")
        local act = ISInventoryTransferUtil.newInventoryTransferAction(ctx.player, item, ctx.player:getInventory(), ctx.cont, 1)
        local after = holder and holder[GD.ACCESS_KEY]
        check("moving an item into a container starts its delay", after ~= nil and math.abs(after - getGameTime():getWorldAgeHours() / 24) < 0.01,
            string.format("before=%s after=%s", tostring(before), tostring(after)))
    end)

    -- ---- other liquids: water in a bottle is never touched, petrol in a bottle degrades
    queue(1, function()
        local GD = GasolineDegradation
        SandboxVars.GasolineDegradation.ContainerMinLiters = 0.05
        local cell = getCell()
        local sq = cell:getGridSquare(ctx.px + 3, ctx.py, ctx.pz)
        ctx.waterBottle = instanceItem("Base.Canteen")
        ctx.waterBottle:getFluidContainer():Empty()
        ctx.waterBottle:getFluidContainer():addFluid(Fluid.Water, 0.3)
        ctx.petrolBottle = instanceItem("Base.Canteen")
        ctx.petrolBottle:getFluidContainer():Empty()
        ctx.petrolBottle:getFluidContainer():addFluid(Fluid.Petrol, 0.3)
        ctx.bottleSquare = sq
        if sq then
            sq:AddWorldInventoryItem(ctx.waterBottle, 0.5, 0.5, 0)
            sq:AddWorldInventoryItem(ctx.petrolBottle, 0.5, 0.5, 0)
        end
        check("water bottle filled", near(ctx.waterBottle:getFluidContainerFromSelfOrWorldItem():getAmount(), 0.3, 0.01),
            string.format("%.2f L", ctx.waterBottle:getFluidContainerFromSelfOrWorldItem():getAmount()))
        check("petrol bottle filled", near(petrolOf(ctx.petrolBottle), 0.3, 0.01), string.format("%.2f L", petrolOf(ctx.petrolBottle)))
        ctx.bottleDay = GD.elapsedDays()
        GDForceCheck()
    end)
    queue(1, function()
        local GD = GasolineDegradation
        jumpDays(7)
        GDForceCheck()
        local expect = 0.3 * GD.decayFactor(GD.elapsedDays() - ctx.bottleDay)
        check("water bottle is not touched", near(ctx.waterBottle:getFluidContainerFromSelfOrWorldItem():getAmount(), 0.3, 0.01),
            string.format("%.3f L", ctx.waterBottle:getFluidContainerFromSelfOrWorldItem():getAmount()))
        check("petrol bottle degrades", near(petrolOf(ctx.petrolBottle), expect, 0.02),
            string.format("%.3f L, expected %.3f", petrolOf(ctx.petrolBottle), expect))
        SandboxVars.GasolineDegradation.ContainerMinLiters = 0.5
    end)

    queue(1, function()
        finish()
    end)
end

local function runTests()
    local ok, err = pcall(setupSteps)
    if not ok then
        state.fail = state.fail + 1
        print(TAG .. "FAIL could not build steps: " .. tostring(err))
        finish("setup error")
    end
end

-- ---------------------------------------------------------------- driving it

Events.OnPostUIDraw.Add(function()
    if state.done or not armed() then return end
    if state.ingame then
        state.ingameFrames = state.ingameFrames + 1
        if state.ingameFrames == 300 then -- let the world settle
            runTests()
        elseif state.ingameFrames > 300 then
            runSteps()
        end
        if state.ingameFrames > 9000 then
            print(TAG .. "FAIL timed out")
            finish("timeout")
        end
        return
    end
    if state.started then return end
    if MainScreen and MainScreen.instance and MainScreen.instance:isVisible() then
        state.frames = state.frames + 1
        if state.frames > 120 then
            state.started = true
            local ok, err = pcall(startWorld)
            if not ok then
                print(TAG .. "FAIL could not start world: " .. tostring(err))
                finish("startup error")
            end
        end
    end
end)

Events.OnGameStart.Add(function()
    if state.armed then
        selectedDebugScenario = nil
        state.ingame = true
        print(TAG .. "world started")
    end
end)
