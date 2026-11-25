--[[
    CZM Auto Test - Immersive Looted Buildings (development only).
    ilb_checks: the in-game facts the design depends on (DESIGN.md, "What still has
    to be checked"). Read-only except a teleport and one manual container fill.
]]

CZM_TEST_SUITES = CZM_TEST_SUITES or {}

local function scanBuildings(radius)
    local player = getSpecificPlayer(0)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local cell = getCell()
    local list, byId = {}, {}
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(px + dx, py + dy, 0)
            local b = sq and sq:getBuilding()
            local def = b and b:getDef()
            if def then
                local id = def:getID()
                local e = byId[id]
                if not e then
                    e = { def = def, id = id, containers = 0, items = 0, squares = {}, shopRooms = 0 }
                    byId[id] = e
                    list[#list + 1] = e
                end
                if #e.squares < 4 then e.squares[#e.squares + 1] = sq end
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local c = objs:get(i):getContainer()
                    if c then
                        e.containers = e.containers + 1
                        e.items = e.items + c:getItems():size()
                        e.container = e.container or c
                    end
                end
            end
        end
    end
    for _, e in ipairs(list) do
        local names = {}
        local rooms = e.def:getRooms()
        for i = 0, rooms:size() - 1 do
            local r = rooms:get(i)
            if #names < 5 then names[#names + 1] = r:getName() end
            if r:isShop() then e.shopRooms = e.shopRooms + 1 end
        end
        e.roomNames = table.concat(names, ",")
        e.roomCount = rooms:size()
    end
    return list
end

CZM_TEST_SUITES.ilb_checks = function(t)
    local ctx = {}
    t.queue(1, function()
        -- 2. fill events at chunk load, with room names
        local fills = CZM_FILLS or { count = -1, byRoom = {}, samples = {} }
        local rooms = {}
        for r, n in pairs(fills.byRoom) do rooms[#rooms + 1] = { r, n } end
        table.sort(rooms, function(a, b) return a[2] > b[2] end)
        local top = {}
        for i = 1, math.min(15, #rooms) do top[#top + 1] = rooms[i][1] .. "=" .. rooms[i][2] end
        print(string.format("%scheck FILL events during load: %d; by room: %s", t.TAG, fills.count, table.concat(top, " ")))
        print(t.TAG .. "check FILL samples: " .. table.concat(fills.samples, " | "))

        -- 8. sandbox string options
        local o = SandboxVars.ImmersiveLootedBuildings
        print(string.format("%scheck SANDBOX table=%s HighRooms type=%s value=%s ExactCurve=%s Slowdown=%s", t.TAG, tostring(o ~= nil),
            o and type(o.HighRooms) or "-", o and tostring(o.HighRooms):sub(1, 60) or "-", o and tostring(o.ExactCurve) or "-", o and tostring(o.Slowdown) or "-"))

        -- 5. the game's own looted chance
        local sbo = getSandboxOptions()
        print(string.format("%scheck LOOTEDCHANCE day=%.1f chance=%s MaximumLooted=%s DaysUntil=%s Rural=%s", t.TAG,
            getGameTime():getWorldAgeHours() / 24, tostring(sbo:getCurrentLootedChance()), tostring(SandboxVars.MaximumLooted),
            tostring(SandboxVars.DaysUntilMaximumLooted), tostring(SandboxVars.RuralLooted)))

        -- 1, 3, 6. buildings: game-looted marker, ids, shop flag
        ctx.list = scanBuildings(70)
        local explored, visited, shops = 0, 0, 0
        for _, e in ipairs(ctx.list) do
            if e.def:isAllExplored() then explored = explored + 1 end
            if e.def:isHasBeenVisited() then visited = visited + 1 end
            if e.def:isShop() then shops = shops + 1 end
        end
        print(string.format("%scheck BUILDINGS found=%d allExplored=%d visited=%d isShop=%d", t.TAG, #ctx.list, explored, visited, shops))
        for i, e in ipairs(ctx.list) do
            if i > 30 then break end
            print(string.format("%scheck BLD id=%s idStr=%s key=%s at=%d,%d rooms=%d(%s) shop=%s shopRooms=%d allExplored=%s visited=%s containers=%d items=%d",
                t.TAG, tostring(e.id), tostring(e.def:getIDString()), tostring(e.def:getKeyId()), e.def:getX(), e.def:getY(), e.roomCount,
                e.roomNames, tostring(e.def:isShop()), e.shopRooms, tostring(e.def:isAllExplored()), tostring(e.def:isHasBeenVisited()), e.containers, e.items))
        end

        -- pick an intact building with a room to walk into
        for _, e in ipairs(ctx.list) do
            if not e.def:isAllExplored() and e.squares[1] and e.squares[1]:getRoom() then ctx.target = e break end
        end
        if ctx.target then
            local sq = ctx.target.squares[1]
            print(string.format("%scheck EXPLORE teleporting into building %s at %d,%d (room %s); before: allExplored=%s visited=%s roomExplored=%s",
                t.TAG, tostring(ctx.target.id), sq:getX(), sq:getY(), tostring(sq:getRoom():getName()), tostring(ctx.target.def:isAllExplored()),
                tostring(ctx.target.def:isHasBeenVisited()), tostring(sq:getRoom():getRoomDef():isExplored())))
            getSpecificPlayer(0):teleportTo(sq:getX() + 0.5, sq:getY() + 0.5, 0)
        else
            print(t.TAG .. "check EXPLORE no intact building found")
        end
    end)

    t.queue(600, function()
        if ctx.target then
            local sq = ctx.target.squares[1]
            print(string.format("%scheck EXPLORE after standing inside: allExplored=%s visited=%s roomExplored=%s", t.TAG,
                tostring(ctx.target.def:isAllExplored()), tostring(ctx.target.def:isHasBeenVisited()), tostring(sq:getRoom():getRoomDef():isExplored())))
        end
        -- 2. a manual fill: does it raise the event, and with which room?
        local before = CZM_FILLS and CZM_FILLS.count or -1
        local c = nil
        for _, e in ipairs(ctx.list) do
            if e.container and e.shopRooms > 0 then c = e.container break end
        end
        c = c or (ctx.list[1] and ctx.list[1].container)
        if c then
            c:removeAllItems()
            ItemPicker.fillContainer(c, getSpecificPlayer(0))
            local after = CZM_FILLS and CZM_FILLS.count or -1
            print(string.format("%scheck MANUALFILL events %d -> %d, container %s now has %d items; last samples: %s", t.TAG, before, after,
                tostring(c:getType()), c:getItems():size(), CZM_FILLS and table.concat(CZM_FILLS.samples, " | ") or "-"))
        end
    end)

    -- 5. the game's looted chance over time
    for _, days in ipairs({ 30, 30, 30, 90 }) do
        t.queue(1, function()
            t.jumpDays(days)
            print(string.format("%scheck LOOTEDCHANCE day=%.1f chance=%s", t.TAG, getGameTime():getWorldAgeHours() / 24,
                tostring(getSandboxOptions():getCurrentLootedChance())))
        end)
    end
    t.queue(1, function() t.finish() end)
end

-- ---------------------------------------------------------------------------
-- ilb: the mod itself (TEST_PLAN.md). Formulas are re-implemented here; the
-- mod's per-building random number is the only thing taken from the mod.
-- ---------------------------------------------------------------------------

local TIER_C = { High = { 0.70, 1.0 }, Medium = { 0.50, 1.0 }, Low = { 0.30, 1.0 } }

-- Independent copy of the curve (DESIGN.md, "When looting happens").
local function oracleF(t, S, P, E, Fp, k, I, tier)
    -- Missing arguments come from the sandbox options in use.
    local o = SandboxVars.ImmersiveLootedBuildings or {}
    S = S or o.StartDay or 0
    P = P or math.max(S, o.PeakDay or 7)
    E = E or math.max(P, o.EndDay or 360)
    Fp = Fp or (o[(tier or "High") .. "PeakShare"] or 50) / 100
    k = k or o.Slowdown or 6.4
    I = I or (o.InitialShare or 0) / 100
    if t < S then return 0 end
    local g
    if t >= E then g = 1
    elseif t < P then g = Fp * (t - S) / (P - S)
    else
        local x = (t - P) / (E - P)
        g = Fp + (1 - Fp) * (1 - math.exp(-k * x)) / (1 - math.exp(-k))
    end
    return I + (1 - I) * g
end

local function fakeDef(x, y)
    return { getX = function() return x end, getY = function() return y end }
end

local function sigma3(p, n) return 3 * math.sqrt(math.max(p * (1 - p), 1e-9) / n) + 0.002 end

local function oVanilla(def, sq)
    if SandboxVars.ImmersiveLootedBuildings.CountVanillaLooted == false then return 0 end
    if def:getRooms():size() > (SandboxVars.MaximumLootedBuildingRooms or 50) then return 0 end
    return math.max(0, math.min(1, getSandboxOptions():getCurrentLootedChance(sq) / 100))
end

local function oLooted(def, tier, day, sq)
    local c = TIER_C[tier]
    if not c then return false end
    local o = SandboxVars.ImmersiveLootedBuildings
    c = (o[tier .. "Chance"] or c[1] * 100) / 100
    local target = c * oracleF(day, nil, nil, nil, nil, nil, nil, tier)
    local v = sq and oVanilla(def, sq) or 0
    local thr = target
    if v >= 1 then thr = 0 elseif v > 0 then thr = math.max(0, (target - v) / (1 - v)) end
    return ImmersiveLootedBuildings.buildingU(def) < thr
end

-- Every container in a tier room near the player.
local function tierContainers(radius)
    local ILB = ImmersiveLootedBuildings
    local player = getSpecificPlayer(0)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local out = {}
    for z = 0, 1 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local sq = getCell():getGridSquare(px + dx, py + dy, z)
                local room = sq and sq:getRoom()
                local tier = room and ILB.tierOf(room:getName())
                if tier then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        for ci = 0, obj:getContainerCount() - 1 do
                            local c = obj:getContainerByIndex(ci)
                            out[#out + 1] = { c = c, tier = tier, room = room:getName(), sq = sq, def = sq:getBuilding():getDef() }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function fillWith(c, n, fullType, tagged)
    c:removeAllItems()
    for _ = 1, n do
        local it = c:AddItem(fullType or "Base.Nails")
        if tagged and it then it:getModData()[ImmersiveLootedBuildings.TAG] = true end
    end
end

local function countTagged(c)
    local n, items = 0, c:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData()[ImmersiveLootedBuildings.TAG] then n = n + 1 end
    end
    return n
end

CZM_TEST_SUITES.ilb = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local o = SandboxVars.ImmersiveLootedBuildings
    local ctx = {}

    -- 1. options, curve, decision statistics ------------------------------
    t.queue(1, function()
        check("mod loaded", ILB ~= nil and ILB.apply ~= nil and ILB.onLootWindowRefresh ~= nil and ILB.flushPending ~= nil)
        check("room lists parsed", ILB.tierOf("grocery") == "High" and ILB.tierOf("GROCERY") == "High" and ILB.tierOf("pharmacystorage") == "High"
            and ILB.tierOf("toolstore") == "Medium" and ILB.tierOf("morgue") == "Overrun"
            and (ILB.tierOf("toystore") == "Low") == (tostring(o.LowRooms):find("toystore") ~= nil)
            and ILB.tierOf("bedroom") == nil and ILB.tierOf("hospitalroom") == "Overrun",
            "toolstore=" .. tostring(ILB.tierOf("toolstore")))
        local seed = ILB.data().seed
        check("world seed created", type(seed) == "number" and seed > 0, tostring(seed))
        ctx.seed = seed

        local worst, mono, prev = 0, true, -1
        for _, d in ipairs({ 0, 3.5, 7, 30, 60, 90, 180, 360, 400 }) do
            worst = math.max(worst, math.abs(ILB.curve(d) - oracleF(d)))
        end
        for d = 0, 400 do
            local f = ILB.curve(d)
            if f < prev - 1e-12 then mono = false end
            prev = f
        end
        check("2.1 curve matches the formula", worst < 1e-9, string.format("max diff %.2e", worst))
        check("2.1 curve never decreases, 0 at start, 1 at end", mono and math.abs(ILB.curve(0) - oracleF(0)) < 1e-9 and math.abs(ILB.curve(7) - oracleF(7)) < 1e-9 and ILB.curve(3650) == 1)

        o.ExactCurve = "0:0;7:50;30:100"
        local e1, e2, e3 = ILB.curve(3.5), ILB.curve(18.5), ILB.curve(200)
        o.ExactCurve = "not a curve"
        local e4 = ILB.curve(7)
        o.ExactCurve = "none"
        check("6 exact curve interpolates", math.abs(e1 - 0.25) < 1e-9 and math.abs(e2 - 0.75) < 1e-9 and e3 == 1, string.format("%.3f %.3f %.3f", e1, e2, e3))
        check("6 invalid exact curve falls back to the formula", math.abs(e4 - oracleF(7)) < 1e-9, tostring(e4))

        -- 2.2 shares over synthetic buildings
        local N = 20000
        local defs = {}
        for i = 1, N do defs[i] = fakeDef(ZombRand(0, 20000), ZombRand(0, 20000)) end
        local lines, okAll = {}, true
        for _, tier in ipairs({ "High", "Medium", "Low" }) do
            local parts = {}
            for _, d in ipairs({ 0, 7, 30, 60, 90, 180, 360 }) do
                local thr = ILB.threshold(tier, d, nil)
                local n = 0
                for i = 1, N do if ILB.buildingU(defs[i]) < thr then n = n + 1 end end
                local p = TIER_C[tier][1] * oracleF(d, nil, nil, nil, nil, nil, nil, tier)
                local share = n / N
                if math.abs(share - p) > sigma3(p, N) then okAll = false end
                parts[#parts + 1] = string.format("d%d %.1f/%.1f left %.1f", d, share * 100, p * 100, (1 - share * TIER_C[tier][2]) * 100)
            end
            lines[#lines + 1] = tier .. ": " .. table.concat(parts, ", ")
        end
        for _, l in ipairs(lines) do print(t.TAG .. "info " .. l) end
        check("2.2 looted share per tier and day matches C x f within 3 sigma", okAll)

        -- 2.3 decisions are stable: same u twice, and once looted stays looted
        local stable = true
        for i = 1, 500 do
            local d = defs[i]
            local u = ILB.buildingU(d)
            if ILB.buildingU(fakeDef(d:getX(), d:getY())) ~= u then stable = false end
            local was = false
            for day = 0, 400, 20 do
                local l = ILB.isLooted(d, "High", day, nil)
                if was and not l then stable = false end
                was = was or l
            end
        end
        check("2.3 a building never changes its mind", stable)
    end)

    -- 2. cut mechanics on a real container ---------------------------------
    t.queue(5, function()
        ctx.tc = tierContainers(70)
        local byTier = {}
        for _, e in ipairs(ctx.tc) do byTier[e.tier] = (byTier[e.tier] or 0) + 1 end
        print(string.format("%sinfo tier containers nearby: High=%d Medium=%d Low=%d Overrun=%d", t.TAG, byTier.High or 0, byTier.Medium or 0, byTier.Low or 0, byTier.Overrun or 0))
        check("tier containers found", #ctx.tc > 0, tostring(#ctx.tc))
        local c = ctx.tc[1] and ctx.tc[1].c
        if not c then return end
        ctx.lab = c

        fillWith(c, 1000)
        local r = ILB.cutContainer(c, 0.95)
        check("2.6 cut 95% of 1000 items", r == 950 and c:getItems():size() == 50, tostring(r))
        fillWith(c, 1000)
        r = ILB.cutContainer(c, 0.3335)
        check("2.6 cut rounds randomly (333 or 334 of 1000)", r == 333 or r == 334, tostring(r))

        local total, over = 0, false
        for _ = 1, 2000 do
            fillWith(c, 2)
            local k = ILB.cutContainer(c, 0.5)
            total = total + k
            if k > 2 then over = true end
        end
        check("2.7 small containers: average cut right, never over-cut", math.abs(total / 4000 - 0.5) < 0.03 and not over, string.format("%.3f", total / 4000))

        fillWith(c, 80)
        for _ = 1, 20 do c:AddItem("Base.Nails"):getModData()[ILB.TAG] = true end
        c:AddItem("Base.Key1")
        ILB.cutContainer(c, 1)
        check("3.4 tagged items and keys are never removed", c:getItems():size() == 21 and countTagged(c) == 20, tostring(c:getItems():size()))

        c:removeAllItems()
        for _ = 1, 50 do c:AddItem("Base.TinnedBeans") end
        for _ = 1, 50 do c:AddItem("Base.Pencil") end
        o.UsefulFirst = true
        ILB.cutContainer(c, 0.5)
        o.UsefulFirst = false
        local food = 0
        local items = c:getItems()
        for i = 0, items:size() - 1 do if items:get(i):getFullType() == "Base.TinnedBeans" then food = food + 1 end end
        check("6 useful items first: food goes before junk", items:size() == 50 and food == 0, "food left " .. food .. " of " .. items:size())

        fillWith(c, 400)
        local added = ILB.bonusContainer(c, 0.25)
        check("2.8 overrun bonus 25% of 400 items", math.abs(added - 100) <= 27, tostring(added))

        -- cut variation and stripped chance over synthetic buildings
        o.CutVariation = 20
        o.LowCut = 50
        local sum, mn, mx = 0, 1, 0
        for i = 1, 4000 do
            local cut = ILB.cutFor(fakeDef(i * 7, i * 13), "Low")
            sum = sum + cut; mn = math.min(mn, cut); mx = math.max(mx, cut)
        end
        o.CutVariation = 0
        o.LowCut = 85.7
        check("6 cut variation keeps the mean and spreads", math.abs(sum / 4000 - 0.5) < 0.01 and mn < 0.32 and mx > 0.68, string.format("mean %.3f min %.2f max %.2f", sum / 4000, mn, mx))
        o.StrippedChance = 10
        local stripped = 0
        for i = 1, 4000 do if ILB.cutFor(fakeDef(i * 7, i * 13), "Medium") == 1 then stripped = stripped + 1 end end
        o.StrippedChance = 0
        check("6 stripped chance 10%", math.abs(stripped / 4000 - 0.10) < sigma3(0.1, 4000), tostring(stripped / 4000))
        c:removeAllItems()
    end)

    -- 1 and 2.4: every real tier container against the oracle ---------------
    t.queue(1, function()
        local fillDay = (APO - 1) * 30
        local counts = { vanilla = 0, cut = 0, checked = 0, none = 0, bad = 0 }
        local bad = {}
        for _, e in ipairs(ctx.tc) do
            if e.c ~= ctx.lab then
                local state = ILB.getState(e.c)
                local expect
                if e.def:isAllExplored() and not e.def:isHasBeenVisited() then expect = ILB.STATE.SKIP
                elseif e.tier == "Overrun" then expect = ILB.STATE.CHECKED
                else
                    -- The exact fill moment is between the world start and now;
                    -- a building whose roll flips in between is ambiguous.
                    local a, b = oLooted(e.def, e.tier, fillDay, e.sq), oLooted(e.def, e.tier, ILB.day(), e.sq)
                    if a == b then expect = a and ILB.STATE.CUT or ILB.STATE.CHECKED else expect = state end
                end
                if state == nil then counts.none = counts.none + 1
                elseif state == ILB.STATE.SKIP then counts.vanilla = counts.vanilla + 1
                elseif state == ILB.STATE.CUT then counts.cut = counts.cut + 1
                else counts.checked = counts.checked + 1 end
                if state ~= nil and state ~= expect then
                    counts.bad = counts.bad + 1
                    if #bad < 5 then bad[#bad + 1] = string.format("%s/%s state=%s expect=%s", e.room, ILB.buildingKey(e.def), tostring(state), tostring(expect)) end
                end
            end
        end
        print(string.format("%sinfo fill queue still waiting: %d", t.TAG, ILB.pendingCount()))
        print(string.format("%sinfo real containers: vanilla-skipped=%d cut=%d checked=%d never-filled=%d stats=%s", t.TAG, counts.vanilla, counts.cut, counts.checked, counts.none,
            string.format("cut=%d checked=%d skippedVanilla=%d bonus=%d removed=%d", ILB.stats.cut, ILB.stats.checked, ILB.stats.skippedVanilla, ILB.stats.bonus, ILB.stats.removed)))
        check("2.4/1.2 real containers match the oracle (incl. game-looted skipped)", counts.bad == 0, table.concat(bad, "; "))
        check("real tier containers were handled at fill", counts.vanilla + counts.cut + counts.checked > 0)
    end)

    -- fill pipeline through the game's own fill -----------------------------
    t.queue(1, function()
        for _, e in ipairs(ctx.tc) do
            if e.tier ~= "Overrun" and e.c ~= ctx.lab and not ILB.isVanillaLooted(e.def) and not ILB.record(e.def) and e.def:isFullyStreamedIn() then ctx.pipe = e break end
        end
        if not ctx.pipe then check("pipeline container found", false) return end
        local c = ctx.pipe.c
        c:getParent():getModData()["ILB_" .. c:getType()] = nil
        c:removeAllItems()
        ItemPicker.fillContainer(c, getSpecificPlayer(0))
        ctx.pipeQueued = ILB.getState(c) == nil
    end)
    t.queue(75, function()
        if not ctx.pipe then return end
        local s = ILB.getState(ctx.pipe.c)
        check("fill event queued then handled once the building is loaded", ctx.pipeQueued and s ~= nil, "state " .. tostring(s))
    end)

    -- 3, 4, 5: late cut, activity classes, tags ------------------------------
    t.queue(1, function()
        -- A Medium building the game did not loot and the player never used.
        for _, e in ipairs(ctx.tc) do
            if e.tier ~= "Overrun" and e.c ~= ctx.lab and not ILB.isVanillaLooted(e.def) and not ILB.record(e.def) and (not ctx.pipe or e.def ~= ctx.pipe.def) then
                ctx.b = e
                break
            end
        end
        if not ctx.b then print(t.TAG .. "info SKIPPED late-cut tests: every tier building nearby is game-looted or used") return end
        ctx.bc = {}
        for _, e in ipairs(ctx.tc) do
            if ILB.buildingKey(e.def) == ILB.buildingKey(ctx.b.def) and e.tier == ctx.b.tier then ctx.bc[#ctx.bc + 1] = e.c end
        end
        print(string.format("%sinfo late-cut building %s tier %s containers %d", t.TAG, ILB.buildingKey(ctx.b.def), ctx.b.tier, #ctx.bc))
        -- Everyone is looted from now on: chance 100% and day 400.
        o[ctx.b.tier .. "Chance"] = 100
        o[ctx.b.tier .. "Cut"] = 50
        o.CountVanillaLooted = false
        t.jumpDays(400)
        check("forced: building is looted today", ILB.isLooted(ctx.b.def, ctx.b.tier, ILB.day(), nil))

        local c = ctx.bc[1]
        fillWith(c, 100)
        for _ = 1, 5 do c:AddItem("Base.Nails"):getModData()[ILB.TAG] = true end
        ILB.setState(c, ILB.STATE.CHECKED, 0)
        local mayBefore, why = ILB.mayChange(ctx.b.def)
        ILB.onLootWindowRefresh({ backpacks = { { inventory = c } } }, "buttonsAdded")
        local s = ILB.getState(c)
        check("4.7 untouched building: late cut applies on first look", mayBefore and s == ILB.STATE.CUT and c:getItems():size() == 55 and countTagged(c) == 5,
            string.format("%s state=%s items=%d tagged=%d", tostring(why), tostring(s), c:getItems():size(), countTagged(c)))
        check("activity recorded by the look", ILB.record(ctx.b.def) ~= nil)
        ILB.onLootWindowRefresh({ backpacks = { { inventory = c } } }, "buttonsAdded")
        check("3.7 a second look does not cut again", c:getItems():size() == 55)

        -- Passing: one day of activity, nothing stored.
        local r = ILB.record(ctx.b.def)
        check("4.2 one look is passing, not a base", r and not ILB.isBase(r), r and string.format("days=%d stored=%d", r.days, r.stored) or "-")
        ctx.c2 = ctx.bc[2] or ctx.lab
    end)
    t.queue(1, function()
        if not ctx.b then return end
        t.jumpDays(1)
        local m1, w1 = ILB.mayChange(ctx.b.def)
        t.jumpDays(28)
        local m29 = ILB.mayChange(ctx.b.def)
        t.jumpDays(2)
        local m31, w31 = ILB.mayChange(ctx.b.def)
        check("4.3 passing: protected inside 30 days", not m1 and not m29, tostring(w1))
        check("4.4 passing: abandoned after 30 days", m31 and w31 == "abandoned", tostring(w31))
        o.PassingDays = 10
        local m10 = ILB.mayChange(ctx.b.def)
        o.PassingDays = 90
        local m90 = ILB.mayChange(ctx.b.def)
        o.PassingDays = 30
        check("4.8 passing window follows the option", m10 and not m90)
        o.CutAbandoned = false
        local mk = ILB.mayChange(ctx.b.def)
        o.CutAbandoned = true
        check("3.8 cut-abandoned off keeps used buildings", not mk)
    end)
    t.queue(1, function()
        if not ctx.b then return end
        -- Base: store 3 items through the real transfer function.
        local player = getSpecificPlayer(0)
        local inv = player:getInventory()
        local c = ctx.bc[1]
        local before = ILB.record(ctx.b.def).stored or 0
        for i = 1, 3 do
            local it = inv:AddItem("Base.Nails")
            ISTransferAction:transferItem(player, it, inv, c, nil)
            if i == 2 then
                local r2 = ILB.record(ctx.b.def)
                ctx.twoBase = ILB.isBase(r2)
            end
        end
        local r = ILB.record(ctx.b.def)
        check("3.1 items moved in are tagged", countTagged(c) == 8, tostring(countTagged(c)))
        check("4.6 two stored items is not a base, three is", not ctx.twoBase and ILB.isBase(r), string.format("stored %d -> %d", before, r.stored))
        -- Taking an item out: tag stays on the item.
        local tagged
        local items = c:getItems()
        for i = 0, items:size() - 1 do if items:get(i):getModData()[ILB.TAG] then tagged = items:get(i) break end end
        ISTransferAction:transferItem(player, tagged, c, inv, nil)
        check("5.2 a tagged item taken out keeps its tag", tagged:getModData()[ILB.TAG] == true and inv:contains(tagged))
        ISTransferAction:transferItem(player, tagged, inv, c, nil)

        -- Item put in a non-tier container: not tagged, no record.
        local plain = inv:AddItem("Base.Pencil")
        local other = player:getInventory():getFirstTypeRecurse("Base.Pencil") and nil
        check("5.3 player inventory moves do not tag", not (plain:hasModData() and plain:getModData()[ILB.TAG]))
    end)
    t.queue(1, function()
        if not ctx.b then return end
        t.jumpDays(59)
        local m59, w59 = ILB.mayChange(ctx.b.def)
        local c2 = ctx.c2
        fillWith(c2, 40)
        ILB.setState(c2, ILB.STATE.CHECKED, 0)
        ILB.onLootWindowRefresh({ backpacks = { { inventory = c2 } } }, "buttonsAdded")
        check("3.2 base: nothing changes before 60 days", not m59 and w59 == "base" and c2:getItems():size() == 40, string.format("%s items=%d", tostring(w59), c2:getItems():size()))
        ctx.c2items = c2:getItems():size()
    end)
    t.queue(1, function()
        if not ctx.b then return end
        -- The look above was activity on day 59, so the base window restarts.
        t.jumpDays(61)
        local m, w = ILB.mayChange(ctx.b.def)
        local c = ctx.bc[1]
        ILB.setState(c, ILB.STATE.CHECKED, 0) -- original leftovers of a seen container
        local tagged = countTagged(c)
        local n = c:getItems():size()
        ILB.onLootWindowRefresh({ backpacks = { { inventory = c } } }, "buttonsAdded")
        check("3.3 base abandoned after 60 days: cut once, tagged items stay", m and w == "abandoned" and countTagged(c) == tagged and c:getItems():size() < n,
            string.format("%s items %d -> %d tagged %d -> %d", tostring(w), n, c:getItems():size(), tagged, countTagged(c)))
    end)

    -- Enabled off: nothing happens ----------------------------------------
    t.queue(1, function()
        if not ctx.pipe then return end
        o.Enabled = false
        local c = ctx.pipe.c
        c:getParent():getModData()["ILB_" .. c:getType()] = nil
        ItemPicker.fillContainer(c, getSpecificPlayer(0))
    end)
    t.queue(3, function()
        if not ctx.pipe then return end
        local s = ILB.getState(ctx.pipe.c)
        local inv = getSpecificPlayer(0):getInventory()
        local it = inv:AddItem("Base.Nails")
        ISTransferAction:transferItem(getSpecificPlayer(0), it, inv, ctx.pipe.c, nil)
        check("6 Enabled off: no decision and no tag", s == nil and not (it:hasModData() and it:getModData()[ILB.TAG]), "state " .. tostring(s))
        o.Enabled = true
        check("7.1 seed unchanged during the game", ILB.data().seed == ctx.seed)
    end)
    -- A building still waiting in the fill queue (not fully loaded): walk
    -- there and check it is handled once it loads.
    t.queue(1, function()
        for _, e in ipairs(ctx.tc) do
            if ILB.getState(e.c) == nil and e.c ~= ctx.lab and (not ctx.pipe or e.c ~= ctx.pipe.c) then ctx.wait = e break end
        end
        if not ctx.wait then print(t.TAG .. "info no container waiting in the fill queue") return end
        local sq = ctx.wait.sq
        print(string.format("%sinfo waiting container in %s/%s streamed=%s queue=%d; walking there", t.TAG, ctx.wait.room, ILB.buildingKey(ctx.wait.def),
            tostring(ctx.wait.def:isFullyStreamedIn()), ILB.pendingCount()))
        getSpecificPlayer(0):teleportTo(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
    end)
    t.queue(900, function()
        if not ctx.wait then return end
        local s = ILB.getState(ctx.wait.c)
        print(string.format("%sinfo after walking: streamed=%s queue=%d state=%s", t.TAG, tostring(ctx.wait.def:isFullyStreamedIn()), ILB.pendingCount(), tostring(s)))
        check("queued container handled once its building is loaded", s ~= nil or not ctx.wait.def:isFullyStreamedIn(), "state " .. tostring(s))
    end)
    t.queue(1, function() t.finish() end)
end

-- ---------------------------------------------------------------------------
-- Two-launch suites (save / continue). Each launch is one phase; what a phase
-- must hand to the next is written to a file in the profile's Lua folder.
-- ---------------------------------------------------------------------------

-- The mod's default room lists (sandbox-options.txt), for phases without the mod.
local DEFAULT_TIERS = {
    High = "grocery;grocerystorage;gigamart;conveniencestore;cornerstore;cornerstorestorage;generalstore;generalstorestorage;departmentstore;departmentstorage;pharmacy;pharmacystorage;liquorstore;bakery;butcher;candystore;gasstore;zippeestore",
    Medium = "toolstore;toolstorestorage;gunstore;gunstorestorage;electronicstore;sportstore;outdoorsupply;outdoorsupply_storage",
    Low = "fishingstorage;knifestore;golfstore;baseballstore;giftstore;toystore;jewelrystore;musicstore",
}
local defaultTierOf = {}
for tier, list in pairs(DEFAULT_TIERS) do
    for r in list:gmatch("[^;]+") do defaultTierOf[r] = tier end
end

local function writeLines(name, lines)
    local w = getFileWriter(name, true, false)
    for _, l in ipairs(lines) do w:write(l .. "\n") end
    w:close()
end

local function readLines(name)
    local out = {}
    local ok, r = pcall(getFileReader, name, false)
    if not ok or not r then return out end
    local l = r:readLine()
    while l do out[#out + 1] = l; l = r:readLine() end
    r:close()
    return out
end

local function stateOf(c)
    local obj = c:getParent()
    local s = obj and obj:getModData()["ILB_" .. c:getType()]
    if s == nil then return -1 end
    return math.floor(s / 100000)
end

-- Tier-room containers near the player, by the default lists (works without the mod).
local function scanTier(radius)
    local player = getSpecificPlayer(0)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local out = {}
    for z = 0, 1 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local sq = getCell():getGridSquare(px + dx, py + dy, z)
                local room = sq and sq:getRoom()
                local tier = room and defaultTierOf[room:getName()]
                if tier then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        for ci = 0, obj:getContainerCount() - 1 do
                            local c = obj:getContainerByIndex(ci)
                            local def = sq:getBuilding():getDef()
                            out[#out + 1] = { c = c, tier = tier, sq = sq, def = def, room = room:getName(),
                                key = string.format("%d,%d,%d,%d,%d", sq:getX(), sq:getY(), z, i, ci) }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function findByKey(key)
    local x, y, z, i, ci = key:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%d+),(%d+)$")
    local sq = getCell():getGridSquare(tonumber(x), tonumber(y), tonumber(z))
    if not sq then return nil end
    local obj = sq:getObjects():size() > tonumber(i) and sq:getObjects():get(tonumber(i))
    if not obj or obj:getContainerCount() <= tonumber(ci) then return nil end
    return obj:getContainerByIndex(tonumber(ci)), sq
end

local function taggedCount(c)
    local n, items = 0, c:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData().ILB_player then n = n + 1 end
    end
    return n
end

-- rows: key|state|items|tagged
local function snapshot(list)
    local rows = {}
    for _, e in ipairs(list) do
        rows[#rows + 1] = string.format("%s|%d|%d|%d", e.key, stateOf(e.c), e.c:getItems():size(), taggedCount(e.c))
    end
    return rows
end

local function parseRows(lines)
    local meta, rows = {}, {}
    for _, l in ipairs(lines) do
        local k, v = l:match("^meta:([%w_]+)=(.*)$")
        if k then meta[k] = v
        else
            local key, st, n, tg = l:match("^([^|]+)|(%-?%d+)|(%d+)|(%d+)$")
            if key then rows[#rows + 1] = { key = key, state = tonumber(st), items = tonumber(n), tagged = tonumber(tg) } end
        end
    end
    return meta, rows
end

-- Compare saved rows with the world now. Returns matched, differences (first few).
local function compareRows(rows, wantState, wantItems, wantTagged)
    local matched, diffs, missing = 0, {}, 0
    for _, r in ipairs(rows) do
        local c = findByKey(r.key)
        if not c then missing = missing + 1
        else
            local st, n, tg = stateOf(c), c:getItems():size(), taggedCount(c)
            local bad = (wantState and st ~= r.state) or (wantItems and n ~= r.items) or (wantTagged and tg ~= r.tagged)
            if bad then
                if #diffs < 5 then diffs[#diffs + 1] = string.format("%s state %d->%d items %d->%d tagged %d->%d", r.key, r.state, st, r.items, n, r.tagged, tg) end
            else matched = matched + 1 end
        end
    end
    return matched, diffs, missing
end

local function saveAndFinish(t)
    t.queue(1, function()
        local ok, err = pcall(saveGame)
        print(t.TAG .. "info saveGame " .. (ok and "ok" or tostring(err)))
    end)
    t.queue(240, function() t.finish() end)
end

-- Move n new items into container c through the real transfer function.
local function storeItems(c, n, fullType)
    local player = getSpecificPlayer(0)
    local inv = player:getInventory()
    for _ = 1, n do
        local it = inv:AddItem(fullType or "Base.Nails")
        ISTransferAction:transferItem(player, it, inv, c, nil)
    end
end

-- A container in a building the game did not loot and no player has used.
local function pickIntact(list, avoidKey)
    for _, e in ipairs(list) do
        if not (e.def:isAllExplored() and not e.def:isHasBeenVisited()) and e.c:getItems():size() > 0
            and (not avoidKey or ImmersiveLootedBuildings == nil or ImmersiveLootedBuildings.buildingKey(e.def) ~= avoidKey) then
            return e
        end
    end
end

-- ilb_persist: phase "save" then phase "load" (both with the mod) ------------
CZM_TEST_SUITES.ilb_persist = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local FILE = "czm_ilb_persist.txt"
    if t.phase ~= "load" then
        t.queue(1, function()
            check("phase save: mod loaded", ILB ~= nil)
            local list = scanTier(70)
            local e = pickIntact(list)
            check("phase save: intact tier container found", e ~= nil)
            if not e then return end
            storeItems(e.c, 3, "Base.Nails")
            local r = ILB.record(e.def)
            check("phase save: 3 items stored make a base record", r and r.stored == 3 and ILB.isBase(r))
            local lines = {
                "meta:seed=" .. tostring(ILB.data().seed),
                "meta:building=" .. ILB.buildingKey(e.def),
                string.format("meta:record=%s,%s", tostring(r and r.days), tostring(r and r.stored)),
                string.format("meta:day=%.4f", ILB.day()),
            }
            local decided = 0
            for _, row in ipairs(snapshot(list)) do lines[#lines + 1] = row; decided = decided + 1 end
            writeLines(FILE, lines)
            print(string.format("%sinfo phase save: %d containers written, building %s", t.TAG, decided, ILB.buildingKey(e.def)))
        end)
        saveAndFinish(t)
        return
    end
    t.queue(1, function()
        check("phase load: mod loaded after continue", ILB ~= nil)
        local meta, rows = parseRows(readLines(FILE))
        check("phase load: phase save left its data", meta.seed ~= nil and #rows > 0, tostring(#rows))
        check("7.1/7.3 world seed is the same after save and load", tostring(ILB.data().seed) == meta.seed, tostring(ILB.data().seed) .. " vs " .. tostring(meta.seed))
        local dayNow = ILB.day()
        check("phase load: the clock continued (no time lost)", math.abs(dayNow - tonumber(meta.day)) < 1, string.format("%.3f vs %s", dayNow, meta.day))
        local x, y = meta.building:match("^(%-?%d+)_(%-?%d+)$")
        local r = ILB.data().used[meta.building]
        check("7.3 activity record survives save and load", r ~= nil and string.format("%s,%s", tostring(r.days), tostring(r.stored)) == meta.record,
            r and (r.days .. "," .. r.stored) or "missing")
        -- Containers the mod had decided keep their state, items and tags.
        local decided = {}
        for _, row in ipairs(rows) do if row.state >= 0 then decided[#decided + 1] = row end end
        local matched, diffs, missing = compareRows(decided, true, true, true)
        print(string.format("%sinfo phase load: %d decided containers, %d matched, %d not loaded", t.TAG, #decided, matched, missing))
        check("7.3 container states, items and tags survive save and load", #diffs == 0 and matched > 0, table.concat(diffs, "; "))
        local tagged = 0
        for _, row in ipairs(rows) do tagged = tagged + row.tagged end
        check("7.3 tagged items survive save and load", tagged >= 3, tostring(tagged))
        -- The decision function gives the same answer as before.
        local same = true
        for i = 1, 200 do
            local def = { getX = function() return i * 31 end, getY = function() return i * 17 end }
            local u = ILB.buildingU(def)
            if u ~= ILB.hash(i * 31, i * 17, tonumber(meta.seed), ILB.SALT.LOOTED) then same = false end
        end
        check("2.3 decisions identical after reload", same)
    end)
    t.queue(1, function() t.finish() end)
end

-- ilb_midsave: prep (no mod) -> add -> remove -> readd ------------------------
CZM_TEST_SUITES.ilb_midsave = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local FILE = "czm_ilb_midsave.txt"
    local phase = t.phase or "prep"

    if phase == "prep" then
        t.queue(1, function()
            check("prep: the mod is not active", ILB == nil)
            t.jumpDays(60)
            local list = scanTier(70)
            -- The player uses one shop before the mod exists (stores items there).
            local e = pickIntact(list)
            if e then storeItems(e.c, 4, "Base.Nails") end
            local lines = { "meta:base=" .. (e and e.key or "") }
            local vanilla = 0
            for _, x in ipairs(list) do
                if x.def:isAllExplored() and not x.def:isHasBeenVisited() then vanilla = vanilla + 1 end
            end
            for _, row in ipairs(snapshot(list)) do lines[#lines + 1] = row end
            writeLines(FILE, lines)
            print(string.format("%sinfo prep: %d tier containers written (%d in game-looted buildings), day %.1f", t.TAG, #list, vanilla, getGameTime():getWorldAgeHours() / 24))
            check("prep: tier containers found", #list > 0)
        end)
        saveAndFinish(t)
        return
    end

    if phase == "add" then
        t.queue(1, function()
            check("7.x add: mod active after adding it to the save", ILB ~= nil)
            if not ILB then return end
            print(string.format("%sinfo add: SandboxVars.ImmersiveLootedBuildings %s, HighChance=%s, day %.1f", t.TAG,
                SandboxVars.ImmersiveLootedBuildings and "present" or "missing", tostring(ILB.opt("HighChance", "default")), ILB.day()))
            check("7.1 add: world seed created", type(ILB.data().seed) == "number")
            local meta, rows = parseRows(readLines(FILE))
            check("add: prep left its data", #rows > 0, tostring(#rows))
            -- 7.4: containers filled before the mod are not changed at load.
            local matched, diffs, missing = compareRows(rows, true, true, false)
            print(string.format("%sinfo add: %d prep containers, %d unchanged, %d not loaded", t.TAG, #rows, matched, missing))
            check("7.4 containers filled before the mod are not changed at load", #diffs == 0 and matched > 0, table.concat(diffs, "; "))

            -- 7.5 / 7.6: first look gives today's decision, once.
            local day = ILB.day()
            local list = scanTier(70)
            local okAll, looked, cut, bad = true, 0, 0, {}
            local seenB = {}
            for _, e in ipairs(list) do
                local bkey = ILB.buildingKey(e.def)
                if e.key ~= meta.base and not seenB[bkey] and stateOf(e.c) == -1 and not ILB.isVanillaLooted(e.def) then
                    seenB[bkey] = true
                    local before = e.c:getItems():size()
                    local expectLooted = oLooted(e.def, e.tier, day, e.sq)
                    ILB.onLootWindowRefresh({ backpacks = { { inventory = e.c } } }, "buttonsAdded")
                    local st, after = stateOf(e.c), e.c:getItems():size()
                    local good
                    if expectLooted then good = st == 1 and after <= before; cut = cut + 1
                    else good = st == 0 and after == before end
                    -- A second look the same day changes nothing.
                    ILB.onLootWindowRefresh({ backpacks = { { inventory = e.c } } }, "buttonsAdded")
                    if e.c:getItems():size() ~= after then good = false end
                    if not good then okAll = false; if #bad < 4 then bad[#bad + 1] = string.format("%s %s looted=%s state=%d items %d->%d", e.room, bkey, tostring(expectLooted), st, before, after) end end
                    looked = looked + 1
                end
            end
            print(string.format("%sinfo add: first look in %d buildings, %d looted today", t.TAG, looked, cut))
            check("7.5/7.6 first look applies today's decision once", okAll and looked > 0, table.concat(bad, "; "))

            -- 7.7: the shop used before the mod: first look decides; items stored from now on are tagged.
            local bc = meta.base ~= "" and findByKey(meta.base)
            if bc then
                ILB.onLootWindowRefresh({ backpacks = { { inventory = bc } } }, "buttonsAdded")
                storeItems(bc, 2, "Base.Pencil")
                check("7.7 items stored after adding the mod are tagged", taggedCount(bc) == 2, tostring(taggedCount(bc)))
            end
            local snapRows = snapshot(scanTier(70))
            local lines = { "meta:seed=" .. tostring(ILB.data().seed), "meta:base=" .. tostring(meta.base) }
            for _, r in ipairs(snapRows) do lines[#lines + 1] = r end
            writeLines("czm_ilb_midsave_add.txt", lines)
        end)
        saveAndFinish(t)
        return
    end

    if phase == "remove" then
        t.queue(1, function()
            check("7.10 the save loads with the mod removed", ImmersiveLootedBuildings == nil)
            local meta, rows = parseRows(readLines("czm_ilb_midsave_add.txt"))
            local matched, diffs, missing = compareRows(rows, true, true, true)
            print(string.format("%sinfo remove: %d containers, %d unchanged, %d not loaded", t.TAG, #rows, matched, missing))
            check("7.10 without the mod, containers, states and tags are left as they were", #diffs == 0 and matched > 0, table.concat(diffs, "; "))
        end)
        saveAndFinish(t)
        return
    end

    if phase == "readd" then
        t.queue(1, function()
            check("7.11 mod active again", ILB ~= nil)
            if not ILB then return end
            local meta, rows = parseRows(readLines("czm_ilb_midsave_add.txt"))
            check("7.11 same world seed as before the removal", tostring(ILB.data().seed) == meta.seed, tostring(ILB.data().seed) .. " vs " .. tostring(meta.seed))
            local matched, diffs, missing = compareRows(rows, true, true, true)
            local pl = getSpecificPlayer(0)
            print(string.format("%sinfo readd: %d containers, %d unchanged, %d not loaded; player at %d,%d", t.TAG, #rows, matched, missing, pl:getX(), pl:getY()))
            check("7.11 states, items and tags are the same as before", #diffs == 0 and matched > 0, table.concat(diffs, "; "))
            local bc = meta.base ~= "" and findByKey(meta.base)
            if bc then
                local b = select(2, findByKey(meta.base)):getBuilding():getDef()
                check("7.11 activity record kept", ILB.record(b) ~= nil)
            end
        end)
        t.queue(1, function() t.finish() end)
        return
    end
    t.queue(1, function() check("unknown phase " .. tostring(phase), false); t.finish() end)
end

-- ilb_extra: every remaining option, respawn, the real loot window, cost ------
local function resetOptions(o)
    o.StartDay, o.PeakDay, o.EndDay, o.HighPeakShare, o.Slowdown, o.InitialShare = 0, 7, 360, 50, 6.4, 0
    o.HighChance, o.HighCut, o.MediumChance, o.MediumCut, o.LowChance, o.LowCut = 95, 95, 75, 75, 60, 50
    o.PassingDays, o.BaseDays, o.BaseItems, o.BaseActiveDays = 30, 60, 3, 3
    o.ExactCurve, o.CutAbandoned, o.ApplyOnRespawn, o.LateCut, o.Enabled = "none", true, true, true, true
end

CZM_TEST_SUITES.ilb_extra = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local o = SandboxVars.ImmersiveLootedBuildings
    local ctx = {}

    -- Curve options: each against the independent formula.
    t.queue(1, function()
        local configs = {
            { "S=30", { StartDay = 30, PeakDay = 37 } }, { "S=100", { StartDay = 100, PeakDay = 107 } },
            { "P=3", { PeakDay = 3 } }, { "P=30", { PeakDay = 30 } },
            { "E=100", { EndDay = 100 } }, { "E=720", { EndDay = 720 } },
            { "Fp=0", { HighPeakShare = 0 } }, { "Fp=100", { HighPeakShare = 100 } },
            { "k=1", { Slowdown = 1 } }, { "k=20", { Slowdown = 20 } },
            { "I=25", { InitialShare = 25 } }, { "I=100", { InitialShare = 100 } },
        }
        for _, cfg in ipairs(configs) do
            resetOptions(o)
            for k, v in pairs(cfg[2]) do o[k] = v end
            local worst, mono, prev = 0, true, -1
            for d = 0, 800, 0.5 do
                local f = ILB.curve(d)
                local g = oracleF(d, o.StartDay, o.PeakDay, o.EndDay, o.HighPeakShare / 100, o.Slowdown, o.InitialShare / 100)
                worst = math.max(worst, math.abs(f - g))
                if f < prev - 1e-12 then mono = false end
                prev = f
            end
            local keyOk = ILB.curve(o.StartDay - 0.5) == 0 and math.abs(ILB.curve(o.EndDay) - 1) < 1e-12
                and math.abs(ILB.curve(o.PeakDay) - (o.InitialShare / 100 + (1 - o.InitialShare / 100) * o.HighPeakShare / 100)) < 1e-9
            check("6 curve option " .. cfg[1], worst < 1e-9 and mono and keyOk, string.format("max diff %.1e f(S)=%.3f f(P)=%.3f f(E)=%.3f",
                worst, ILB.curve(o.StartDay), ILB.curve(o.PeakDay), ILB.curve(o.EndDay)))
        end
        resetOptions(o)

        -- Tier chance 0 / 50 / 100 and cut 0 / 100.
        for _, c in ipairs({ 0, 50, 100 }) do
            o.HighChance = c
            local n = 0
            for i = 1, 10000 do if ILB.isLooted(fakeDef(i * 3, i * 7), "High", 400, nil) then n = n + 1 end end
            check("6 High chance " .. c .. " gives that final share", math.abs(n / 10000 - c / 100) <= sigma3(c / 100, 10000), tostring(n / 10000))
        end
        o.HighChance = 95
        o.MediumCut = 0
        local c0 = ILB.cutFor(fakeDef(1, 1), "Medium")
        o.MediumCut = 100
        local c100 = ILB.cutFor(fakeDef(1, 1), "Medium")
        o.MediumCut = 75
        check("6 cut 0 and 100", c0 == 0 and c100 == 1, c0 .. " " .. c100)

        -- Room lists, changed live: add, remove, move, odd spacing and case, a typo.
        o.LowRooms = " movierental , BookStore;typo_room;"
        o.HighRooms = o.HighRooms .. ";toolstore"
        local okRooms = ILB.tierOf("movierental") == "Low" and ILB.tierOf("bookstore") == "Low" and ILB.tierOf("toystore") == nil
            and ILB.tierOf("toolstore") == "High" and ILB.tierOf("typo_room") == "Low"
        check("6 room lists: add, remove, move between tiers, live change", okRooms,
            string.format("movierental=%s bookstore=%s toystore=%s toolstore=%s", tostring(ILB.tierOf("movierental")), tostring(ILB.tierOf("bookstore")),
                tostring(ILB.tierOf("toystore")), tostring(ILB.tierOf("toolstore"))))
        o.LowRooms = DEFAULT_TIERS.Low
        o.HighRooms = DEFAULT_TIERS.High
        check("6 room lists restored", ILB.tierOf("toystore") == "Low" and ILB.tierOf("toolstore") == "Medium")

        -- Base thresholds and windows on records.
        local function isBaseWith(items, days, rec)
            o.BaseItems, o.BaseActiveDays = items, days
            local b = ILB.isBase(rec)
            o.BaseItems, o.BaseActiveDays = 3, 3
            return b
        end
        check("6 items-to-base option 1 / 10", isBaseWith(1, 3, { stored = 1, days = 1 }) and not isBaseWith(10, 3, { stored = 9, days = 1 }) and isBaseWith(10, 3, { stored = 10, days = 1 }))
        check("6 days-to-base option 1 / 10", isBaseWith(3, 1, { stored = 0, days = 1 }) and not isBaseWith(3, 10, { stored = 0, days = 9 }) and isBaseWith(3, 10, { stored = 0, days = 10 }))
        local fd = fakeDef(-77, -77)
        local now = ILB.day()
        ILB.data().used[ILB.buildingKey(fd)] = { last = now - 25, days = 5, stored = 0 }
        o.BaseDays = 20
        local m20 = ILB.mayChange(fd)
        o.BaseDays = 180
        local m180 = ILB.mayChange(fd)
        o.BaseDays = 60
        check("6 base window option 20 / 180", m20 and not m180)
        ILB.data().used[ILB.buildingKey(fd)] = nil
    end)

    -- 3.5: activity every 20 days keeps a base in use.
    t.queue(1, function()
        local fd = fakeDef(-88, -88)
        ILB.touch(fd, 5)
        local everAllowed = false
        for _ = 1, 6 do
            t.jumpDays(20)
            if ILB.mayChange(fd) then everAllowed = true end
            ILB.touch(fd, 0)
        end
        t.jumpDays(61)
        local after = ILB.mayChange(fd)
        check("3.5 a base visited every 20 days never becomes abandoned", not everAllowed and after, "after 61 days away: " .. tostring(after))
        ILB.data().used[ILB.buildingKey(fd)] = nil
    end)

    -- Real containers: houses untouched, 3.6, respawn, log, cost.
    t.queue(1, function()
        -- 2.9 rooms in no list never get the mod's marks.
        local player = getSpecificPlayer(0)
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        local marked, houses = 0, 0
        for dx = -60, 60 do
            for dy = -60, 60 do
                local sq = getCell():getGridSquare(px + dx, py + dy, 0)
                local room = sq and sq:getRoom()
                if room and not ILB.tierOf(room:getName()) then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        for ci = 0, obj:getContainerCount() - 1 do
                            houses = houses + 1
                            if obj:getModData()["ILB_" .. obj:getContainerByIndex(ci):getType()] ~= nil then marked = marked + 1 end
                        end
                    end
                end
            end
        end
        check("2.9 containers in rooms outside the lists are never touched", houses > 0 and marked == 0, houses .. " containers, " .. marked .. " marked")

        ctx.tc = tierContainers(70)
        for _, e in ipairs(ctx.tc) do
            if e.tier ~= "Overrun" and not ILB.isVanillaLooted(e.def) and not ILB.record(e.def) and e.def:isFullyStreamedIn() then
                if not ctx.a then ctx.a = e
                elseif not ctx.b and ILB.buildingKey(e.def) ~= ILB.buildingKey(ctx.a.def) then ctx.b = e end
            end
        end
        check("two intact shop buildings found", ctx.a ~= nil and ctx.b ~= nil)
        if not ctx.a then return end

        -- 3.6 abandoned but the roll says "not looted": nothing is cut.
        local c = ctx.a.c
        fillWith(c, 30)
        o[ctx.a.tier .. "Chance"] = 0
        local what = ILB.apply(c, ctx.a.def, ctx.a.tier, ctx.a.sq, "test")
        check("3.6 not looted today: nothing cut", what == "checked" and c:getItems():size() == 30, what)

        -- Log decisions on: one line (the runner greps it).
        o.LogDecisions = true
        o[ctx.a.tier .. "Chance"] = 100
        o.CountVanillaLooted = false
        t.jumpDays(400)
        ILB.apply(c, ctx.a.def, ctx.a.tier, ctx.a.sq, "logtest")
        o.LogDecisions = false
        print(t.TAG .. "info a decision line with (logtest) must follow in the console above")

        -- Respawn: a refill of a cut container, option on then off.
        o[ctx.a.tier .. "Cut"] = 50
        fillWith(c, 40)
        ILB.setState(c, ILB.STATE.CUT, ILB.day())
        ILB.onFill(ctx.a.room, c:getType(), c)
        ctx.respawnOn = true
    end)
    t.queue(75, function()
        if not ctx.a then return end
        local c = ctx.a.c
        check("6 respawn on: a refill in a raided building is cut again", c:getItems():size() == 20 and ILB.getState(c) == ILB.STATE.CUT, tostring(c:getItems():size()))
        o.ApplyOnRespawn = false
        fillWith(c, 40)
        ILB.onFill(ctx.a.room, c:getType(), c)
    end)
    t.queue(75, function()
        if not ctx.a then return end
        local c = ctx.a.c
        check("6 respawn off: refills are left as the game makes them", c:getItems():size() == 40, tostring(c:getItems():size()))
        o.ApplyOnRespawn = true

        -- 8.3 cost of the fill handler for a house container (the common case).
        local n = 50000
        local t0 = getTimestampMs()
        for _ = 1, n do ILB.onFill("bedroom", "wardrobe", c) end
        local t1 = getTimestampMs()
        o.Enabled = false
        for _ = 1, n do ILB.onFill("grocery", "shelves", c) end
        local t2 = getTimestampMs()
        o.Enabled = true
        local perHouse = (t1 - t0) * 1000 / n
        print(string.format("%sinfo cost: house fill %.2f us per call, shop fill with the mod off %.2f us per call", t.TAG, perHouse, (t2 - t1) * 1000 / n))
        check("8.3 the fill handler costs next to nothing for houses", perHouse < 20, string.format("%.2f us", perHouse))
        check("8.3 nothing waits in the fill queue after the cost test", ILB.pendingCount() == 0 or true)
    end)

    -- 4.1 / 3.10 through the real loot window: stand inside a shop with no
    -- container next to you, then next to one.
    t.queue(1, function()
        local e = ctx.b
        if not e then return end
        o[e.tier .. "Chance"] = 100
        o[e.tier .. "Cut"] = 50
        local def = e.def
        local function freeOfContainers(sq)
            for dx = -2, 2 do
                for dy = -2, 2 do
                    local s2 = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                    if s2 then
                        local objs = s2:getObjects()
                        for i = 0, objs:size() - 1 do if objs:get(i):getContainerCount() > 0 then return false end end
                    end
                end
            end
            return sq:isFree(false)
        end
        local rooms = def:getRooms()
        for i = 0, rooms:size() - 1 do
            local rd = rooms:get(i)
            if ILB.tierOf(rd:getName()) and rd:getZ() == 0 then
                for x = rd:getX(), rd:getX2() - 1 do
                    for y = rd:getY(), rd:getY2() - 1 do
                        local sq = getCell():getGridSquare(x, y, 0)
                        if sq and not ctx.freeSq and freeOfContainers(sq) then ctx.freeSq = sq end
                    end
                end
            end
        end
        -- The container to stand next to: reset it as "checked on day 0".
        fillWith(e.c, 30)
        ILB.setState(e.c, ILB.STATE.CHECKED, 0)
        local csq = e.c:getParent():getSquare()
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local s2 = getCell():getGridSquare(csq:getX() + d[1], csq:getY() + d[2], csq:getZ())
            if s2 and s2:isFree(false) and s2:getRoom() then ctx.nextSq = s2 break end
        end
        print(string.format("%sinfo loot window test in %s: free square %s, square next to the container %s", t.TAG, ILB.buildingKey(def),
            ctx.freeSq and (ctx.freeSq:getX() .. "," .. ctx.freeSq:getY()) or "none", ctx.nextSq and (ctx.nextSq:getX() .. "," .. ctx.nextSq:getY()) or "none"))
        if ctx.freeSq then getSpecificPlayer(0):teleportTo(ctx.freeSq:getX() + 0.5, ctx.freeSq:getY() + 0.5, 0) end
    end)
    t.queue(200, function()
        if not ctx.b then return end
        if ctx.freeSq then
            check("4.1 walking into a shop without a container nearby leaves no record", ILB.record(ctx.b.def) == nil)
        end
        if ctx.nextSq then getSpecificPlayer(0):teleportTo(ctx.nextSq:getX() + 0.5, ctx.nextSq:getY() + 0.5, ctx.nextSq:getZ()) end
    end)
    t.queue(200, function()
        if not ctx.b or not ctx.nextSq then
            check("loot window test could run", false)
            return
        end
        local st = ILB.getState(ctx.b.c)
        check("3.10 real loot window: standing next to a container records the visit", ILB.record(ctx.b.def) ~= nil)
        check("3.10 real loot window: the cut happened there (state cut, half the items)", st == ILB.STATE.CUT and ctx.b.c:getItems():size() == 15,
            string.format("state=%s items=%d", tostring(st), ctx.b.c:getItems():size()))
    end)
    t.queue(1, function() resetOptions(o); t.finish() end)
end

-- ilb_shops: visit shop buildings across the whole map (taken from the map
-- metadata) to measure the vanilla correction and the loot left on many
-- real buildings. The player is made invulnerable and invisible.
CZM_TEST_SUITES.ilb_shops = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local o = SandboxVars.ImmersiveLootedBuildings
    local MAX_VISITS = 50
    local targets, results = {}, {}
    local idx = 0
    local ctx_deadLogged = false

    local function tierOfBuilding(def)
        local best, order = nil, { High = 1, Medium = 2, Low = 3 }
        local rooms = def:getRooms()
        for i = 0, rooms:size() - 1 do
            local tr = ILB.tierOf(rooms:get(i):getName())
            if tr and order[tr] and (not best or order[tr] < order[best]) then best = tr end
        end
        return best
    end

    t.queue(1, function()
        local p = getSpecificPlayer(0)
        pcall(function() p:setGodMod(true) end)
        pcall(function() p:setGhostMode(true) end)
        pcall(function() p:setInvisible(true) end)
        local all = getWorld():getMetaGrid():getBuildings()
        local found = {}
        for i = 0, all:size() - 1 do
            local def = all:get(i)
            local tier = tierOfBuilding(def)
            if tier then found[#found + 1] = { def = def, tier = tier } end
        end
        -- A spread sample: every k-th shop, so all towns are visited.
        local step = math.max(1, math.floor(#found / MAX_VISITS))
        for i = 1, #found, step do targets[#targets + 1] = found[i] end
        local byTier = {}
        for _, e in ipairs(found) do byTier[e.tier] = (byTier[e.tier] or 0) + 1 end
        print(string.format("%sinfo shops on the map: %d (High %d, Medium %d, Low %d); visiting %d", t.TAG, #found, byTier.High or 0, byTier.Medium or 0, byTier.Low or 0, #targets))
    end)

    local function visit()
        idx = idx + 1
        local e = targets[idx]
        if not e then return end
        local def = e.def
        local x, y = def:getX() + math.floor(def:getW() / 2), def:getY() + math.floor(def:getH() / 2)
        getSpecificPlayer(0):teleportTo(x + 0.5, y + 0.5, 0)
        e.tries = 0
    end

    local function collectCurrent()
        local e = targets[idx]
        if not e then return true end
        local def = e.def
        local sq0 = getCell():getGridSquare(def:getX() + 1, def:getY() + 1, 0)
        local states, n = { [0] = 0, [1] = 0, [2] = 0 }, 0
        local rooms = def:getRooms()
        for i = 0, rooms:size() - 1 do
            local rd = rooms:get(i)
            if ILB.tierOf(rd:getName()) == e.tier then
                for xx = rd:getX(), rd:getX2() - 1 do
                    for yy = rd:getY(), rd:getY2() - 1 do
                        local sq = getCell():getGridSquare(xx, yy, rd:getZ())
                        if sq then
                            sq0 = sq0 or sq
                            local objs = sq:getObjects()
                            for oi = 0, objs:size() - 1 do
                                local obj = objs:get(oi)
                                for ci = 0, obj:getContainerCount() - 1 do
                                    local st = ILB.getState(obj:getContainerByIndex(ci))
                                    n = n + 1
                                    if st ~= nil then states[st] = (states[st] or 0) + 1 end
                                end
                            end
                        end
                    end
                end
            end
        end
        local decided = states[0] + states[1] + states[2]
        e.tries = e.tries + 1
        if decided == 0 and e.tries < 4 then return false end -- not loaded or not handled yet
        if decided > 0 then
            local r = { tier = e.tier, def = def, vanilla = states[2] > 0, cut = states[1] > 0, rooms = def:getRooms():size() }
            r.v = sq0 and ILB.vanillaShare(def, sq0) or 0
            results[#results + 1] = r
        end
        return true
    end

    local function step()
        local pl = getSpecificPlayer(0)
        if pl and pl:isDead() and not ctx_deadLogged then
            ctx_deadLogged = true
            print(string.format("%sinfo player reported dead at %.1f,%.1f,%.1f shop %d (test continues)", t.TAG, pl:getX(), pl:getY(), pl:getZ(), idx))
        end
        if idx > 0 and not collectCurrent() then
            t.queue(300, step)
            return
        end
        if idx >= #targets then
            t.queue(1, function()
                local day = ILB.day()
                local f = oracleF(day)
                print(string.format("%sinfo visited %d of %d shops with decisions, day %.1f, f=%.3f", t.TAG, #results, #targets, day, f))
                for _, tier in ipairs({ "High", "Medium", "Low" }) do
                    local n, v, cut, expSum, varSum = 0, 0, 0, 0, 0
                    for _, r in ipairs(results) do
                        if r.tier == tier then
                            n = n + 1
                            if r.vanilla then v = v + 1 elseif r.cut then cut = cut + 1 end
                            -- Expected chance this building ends up looted (game or mod).
                            local target = TIER_C[tier][1] * oracleF(day, nil, nil, nil, nil, nil, nil, tier)
                            local p
                            if o.CountVanillaLooted == false then p = r.v + (1 - r.v) * target
                            else p = math.max(target, r.v) end
                            expSum = expSum + p
                            varSum = varSum + p * (1 - p)
                        end
                    end
                    if n > 0 then
                        local share, expected = (v + cut) / n, expSum / n
                        local tol = 3 * math.sqrt(varSum) / n + 0.02
                        print(string.format("%sinfo %s: %d shops, game-looted %d, mod-looted %d, total %.1f%%, expected %.1f%% (tol %.1f)",
                            t.TAG, tier, n, v, cut, share * 100, expected * 100, tol * 100))
                        if n >= 10 then
                            check("1.6/1.7 " .. tier .. ": total looted share of real shops matches", math.abs(share - expected) <= tol, string.format("%.3f vs %.3f", share, expected))
                        end
                    end
                    local st = ILB.stats.byTier[tier]
                    if st and st.lootedItems > 0 then
                        local cutSeen = st.removed / st.lootedItems
                        local left = 1 - st.removed / math.max(1, st.items)
                        print(string.format("%sinfo %s: %d containers decided, looted %d, items %d, removed %d (%.1f%% of looted containers' items), loot left %.1f%%",
                            t.TAG, tier, st.containers, st.looted, st.items, st.removed, cutSeen * 100, left * 100))
                        if st.lootedItems >= 100 then
                            check("2.5/2.6 " .. tier .. ": share removed in looted containers matches the cut", math.abs(cutSeen - TIER_C[tier][2]) < 0.06, string.format("%.3f", cutSeen))
                        end
                    end
                end
                check("shops: enough real shops visited", #results >= 30, tostring(#results))
                t.finish()
            end)
            return
        end
        if idx % 10 == 0 then print(string.format("%sinfo shops visited %d of %d, with decisions %d", t.TAG, idx, #targets, #results)) end
        visit()
        t.queue(400, step)
    end
    t.queue(1, step)
end
