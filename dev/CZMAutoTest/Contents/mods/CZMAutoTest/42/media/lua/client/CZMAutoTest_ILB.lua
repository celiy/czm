--[[
    CZM Auto Test - Immersive Looted Buildings v2 (development only).

    Suites (TEST_PLAN.md):
      ilb2          phase "full" (default): sections 1-5, 9, 10, 3.10, 8.1
                    phase "series": the time series and overrun only (towns with few shops)
                    phase "vanilla": section 7.1 (run with MaximumLooted 100)
                    phase "apo": section 6.1 (run with TimeSinceApo 4)
      ilb2_persist  phases "save", "load": section 6.2, 9.10, 10.13
      ilb2_midsave  phases "prep" (without the mod), "add", "remove", "readd": 6.3, 6.4

    The formulas are written again here. The only thing taken from the mod is
    each building's permanent random number (ILB.buildingU), so the oracle can
    know which buildings are hit or lucky.
]]

CZM_TEST_SUITES = CZM_TEST_SUITES or {}

-- ---------------------------------------------------------------- oracle

local DEF = { -- defaults, from DESIGN.md
    High = { chance = 70, peak = 60, min = 30 }, Medium = { chance = 50, peak = 70, min = 50 }, Low = { chance = 30, peak = 80, min = 70 },
}

local function opt(name, default)
    local o = SandboxVars.ImmersiveLootedBuildings or {}
    if o[name] == nil then return default end
    return o[name]
end

local function oFp(tier)
    local mn, pk = opt(tier .. "MinLoot", DEF[tier].min) / 100, opt(tier .. "PeakLoot", DEF[tier].peak) / 100
    if mn >= 1 then return 1 end
    return math.max(0, math.min(1, (1 - pk) / (1 - mn)))
end

local function oG(t, tier)
    local S, P, E = opt("StartDay", 0), opt("PeakDay", 7), opt("EndDay", 360)
    P = math.max(S, P); E = math.max(P, E)
    local k, I = opt("Slowdown", 6.4), opt("InitialShare", 0) / 100
    if t < S then return 0 end
    local Fp, g = oFp(tier)
    if t <= S then g = 0
    elseif t >= E then g = 1
    elseif t < P then g = Fp * (t - S) / (P - S)
    else
        local x = (t - P) / (E - P)
        g = Fp + (1 - Fp) * (1 - math.exp(-k * x)) / (1 - math.exp(-k))
    end
    return I + (1 - I) * g
end

-- Loss strength of a real building, from its permanent random numbers.
local function oS(def, tier)
    local ILB = ImmersiveLootedBuildings
    if ILB.buildingU(def, 1) < opt(tier .. "Chance", DEF[tier].chance) / 100 then return 1, true end
    local lo, hi = opt("LuckyLossMin", 70) / 100, opt("LuckyLossMax", 85) / 100
    if lo > hi then lo, hi = hi, lo end
    return lo + (hi - lo) * ILB.buildingU(def, 2), false
end

local function oK(def, tier, e)
    return 1 - oS(def, tier) * (1 - opt(tier .. "MinLoot", DEF[tier].min) / 100) * oG(e, tier)
end

local function fakeDef(x, y)
    return { getX = function() return x end, getY = function() return y end, getW = function() return 10 end, getH = function() return 10 end }
end

local function sigma3(p, n) return 3 * math.sqrt(math.max(p * (1 - p), 1e-9) / n) + 0.002 end

-- ---------------------------------------------------------------- world helpers

local LOSS = { High = true, Medium = true, Low = true }

-- Containers in tier rooms near the player (mod's room lists).
local function tierContainers(radius)
    local ILB = ImmersiveLootedBuildings
    local p = getSpecificPlayer(0)
    local px, py = math.floor(p:getX()), math.floor(p:getY())
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
                            local def = sq:getBuilding():getDef()
                            local c = obj:getContainerByIndex(ci)
                            out[#out + 1] = { c = c, tier = tier, room = room:getName(), sq = sq, def = def, key = ILB.buildingKey(def),
                                x = sq:getX(), y = sq:getY(), z = sq:getZ(), oi = i, ci = ci, ctype = c:getType() }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- The container at the entry's position now. Teleports unload and reload
-- chunks, and a reloaded chunk has new objects: never keep old references.
local function C(e)
    local sq = getCell():getGridSquare(e.x, e.y, e.z)
    if not sq then return nil end
    local objs = sq:getObjects()
    if objs:size() > e.oi then
        local obj = objs:get(e.oi)
        if obj:getContainerCount() > e.ci then
            local c = obj:getContainerByIndex(e.ci)
            if c:getType() == e.ctype then return c end
        end
    end
    for i = 0, objs:size() - 1 do -- the object order may change after a reload
        local obj = objs:get(i)
        for ci = 0, obj:getContainerCount() - 1 do
            local c = obj:getContainerByIndex(ci)
            if c:getType() == e.ctype then return c end
        end
    end
end

local function fillWith(c, n, fullType)
    c:removeAllItems()
    for _ = 1, n do c:AddItem(fullType or "Base.Nails") end
end

local function countUntagged(c)
    local n, items = 0, c:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not (it:hasModData() and it:getModData().ILB_player) then n = n + 1 end
    end
    return n
end

local function countTagged(c)
    return c:getItems():size() - countUntagged(c)
end

local function storeItems(c, n, fullType)
    local player = getSpecificPlayer(0)
    local inv = player:getInventory()
    for _ = 1, n do
        local it = inv:AddItem(fullType or "Base.Nails")
        ISTransferAction:transferItem(player, it, inv, c, nil)
    end
end

-- A walkable square outside every building near the player.
local function outdoorSquare(radius)
    local p = getSpecificPlayer(0)
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    for r = 3, radius do
        for dx = -r, r do
            for _, dy in ipairs({ -r, r }) do
                local sq = getCell():getGridSquare(px + dx, py + dy, 0)
                if sq and not sq:getBuilding() and sq:isFree(false) then return sq end
            end
        end
    end
end

local function freeSquareNextTo(c)
    local sq = c:getParent():getSquare()
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 } }) do
        local s2 = getCell():getGridSquare(sq:getX() + d[1], sq:getY() + d[2], sq:getZ())
        if s2 and s2:isFree(false) and s2:getRoom() then return s2 end
    end
end

local function freeSquareInside(def)
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        if rd:getZ() == 0 then
            for x = rd:getX(), rd:getX2() - 1 do
                for y = rd:getY(), rd:getY2() - 1 do
                    local sq = getCell():getGridSquare(x, y, 0)
                    if sq and sq:isFree(false) then return sq end
                end
            end
        end
    end
end

local function teleport(sq)
    getSpecificPlayer(0):teleportTo(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
end

-- Buildings with explored loss containers, not game-looted, never used.
local function eligibleBuildings(list)
    local ILB = ImmersiveLootedBuildings
    local byKey, order = {}, {}
    for _, e in ipairs(list) do
        if LOSS[e.tier] and e.c:isExplored() and not ILB.isVanillaLooted(e.def) and not ILB.record(e.def) and e.def:isFullyStreamedIn() then
            local b = byKey[e.key]
            if not b then b = { def = e.def, key = e.key, containers = {} }; byKey[e.key] = b; order[#order + 1] = b end
            b.containers[#b.containers + 1] = e
        end
    end
    table.sort(order, function(a, b) return #a.containers > #b.containers end)
    return order
end

local function processAll(buildings, why)
    local ILB = ImmersiveLootedBuildings
    for _, b in ipairs(buildings) do ILB.processBuilding(b.def, false, why) end
end

-- ---------------------------------------------------------------- ilb2

local function sectionCurveAndDistribution(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    check("mod loaded (v2)", ILB ~= nil and ILB.keep ~= nil and ILB.processBuilding ~= nil and ILB.onLoadChunk ~= nil and ILB.onPlayerMove ~= nil)
    local o = SandboxVars.ImmersiveLootedBuildings
    check("v2 options reach the game", o and o.HighChance == 70 and o.HighPeakLoot == 60 and o.HighMinLoot == 30 and o.MediumMinLoot == 50
        and o.LowMinLoot == 70 and o.LuckyLossMin == 70 and o.LuckyLossMax == 85 and o.ProtectRadius == 200 and o.RecentVisitDays == 14
        and o.HighCut == nil and o.CountVanillaLooted == nil, o and ("HighChance=" .. tostring(o.HighChance)) or "none")

    -- 1.1 - 1.3
    check("1.1 Fp per tier", math.abs(ILB.peakShare("High") - 4 / 7) < 1e-9 and math.abs(ILB.peakShare("Medium") - 0.6) < 1e-9 and math.abs(ILB.peakShare("Low") - 2 / 3) < 1e-9)
    local worst, mono = 0, true
    for _, tier in ipairs({ "High", "Medium", "Low" }) do
        local prev = -1
        for d = 0, 800, 0.5 do
            local g = ILB.curve(d, tier)
            worst = math.max(worst, math.abs(g - oG(d, tier)))
            if g < prev - 1e-12 then mono = false end
            prev = g
        end
    end
    check("1.2 g(t) matches the formula, never decreases", worst < 1e-9 and mono, string.format("%.1e", worst))
    local TABLE = { High = { 100, 60.0, 49.8, 41.4, 36.6, 31.3, 30.0 }, Medium = { 100, 70.0, 63.2, 57.6, 54.4, 50.8, 50.0 }, Low = { 100, 80.0, 76.6, 73.8, 72.2, 70.4, 70.0 } }
    local days = { 0, 7, 30, 60, 90, 180, 360 }
    local ok13 = true
    for tier, row in pairs(TABLE) do
        for i, d in ipairs(days) do
            local hitK = 1 - (1 - ILB.minLoot(tier)) * ILB.curve(d, tier)
            if math.abs(hitK * 100 - row[i]) > 0.06 then ok13 = false end
        end
    end
    check("1.3 hit K(t) per tier matches the DESIGN tables", ok13)

    -- 1.5, 2.1-2.4 over 20,000 synthetic buildings
    local N = 20000
    local defs = {}
    for i = 1, N do defs[i] = fakeDef(ZombRand(0, 20000), ZombRand(0, 20000)) end
    local AVG = { High = { 100, 62.7, 53.1, 45.4, 40.9, 35.9, 34.7 }, Medium = { 100, 73.4, 67.3, 62.4, 59.5, 56.4, 55.6 }, Low = { 100, 83.2, 80.3, 77.9, 76.6, 75.1, 74.7 } }
    for _, tier in ipairs({ "High", "Medium", "Low" }) do
        local C = DEF[tier].chance / 100
        local hits, okRange, buckets, sums = 0, true, {}, {}
        for b = 0, 9 do buckets[b] = 0 end
        for _, d in ipairs(defs) do
            local s = ILB.strength(d, tier)
            if ILB.isHit(d, tier) then
                hits = hits + 1
                if s ~= 1 then okRange = false end
            else
                if s < 0.7 - 1e-9 or s > 0.85 + 1e-9 then okRange = false end
                local b = math.min(9, math.floor((s - 0.7) / 0.015))
                buckets[b] = buckets[b] + 1
            end
            for j, day in ipairs(days) do sums[j] = (sums[j] or 0) + ILB.keep(d, tier, day) end
        end
        check("2.1 " .. tier .. " hit share = chance", math.abs(hits / N - C) <= sigma3(C, N), string.format("%.4f", hits / N))
        check("2.2/2.3 " .. tier .. " hit s = 1, lucky s inside 0.70-0.85", okRange)
        local okB, lucky = true, N - hits
        for b = 0, 9 do if math.abs(buckets[b] - lucky / 10) > 4 * math.sqrt(lucky / 10) then okB = false end end
        check("2.4 " .. tier .. " lucky strength uniform", okB)
        local okA, parts = true, {}
        for j, day in ipairs(days) do
            local avg = sums[j] / N * 100
            parts[#parts + 1] = string.format("d%d %.1f", day, avg)
            if math.abs(avg - AVG[tier][j]) > 0.5 then okA = false end
        end
        check("1.5 " .. tier .. " average K over 20000 buildings", okA, table.concat(parts, " "))
    end

    -- 2.5 real shops of the whole map: most and least affected on day 360
    local idx, count = ILB.shopIndex()
    check("shop index built from the map", idx ~= nil and count > 50, tostring(count))
    if idx then
        local seenKeys, shops = {}, {}
        for _, list in pairs(idx) do
            for _, def in ipairs(list) do
                local key = ILB.buildingKey(def)
                if not seenKeys[key] then
                    seenKeys[key] = true
                    local tier
                    local rooms = def:getRooms()
                    for i = 0, rooms:size() - 1 do
                        local tr = ILB.tierOf(rooms:get(i):getName())
                        if LOSS[tr] and (not tier or tr == "High" or (tr == "Medium" and tier == "Low")) then tier = tr end
                    end
                    if tier then
                        local _, hit = oS(def, tier)
                        shops[#shops + 1] = { key = key, tier = tier, k = oK(def, tier, 360), hit = hit, modK = ILB.keep(def, tier, 360) }
                    end
                end
            end
        end
        local agree = true
        for _, sh in ipairs(shops) do if sh.modK == nil or math.abs(sh.k - sh.modK) > 1e-9 then agree = false end end
        check("2.5 real shops: mod K(360) equals the oracle for every shop", agree, tostring(#shops) .. " shops")
        for _, tier in ipairs({ "High", "Medium", "Low" }) do
            local list = {}
            for _, sh in ipairs(shops) do if sh.tier == tier then list[#list + 1] = sh end end
            if #list > 0 then
                table.sort(list, function(a, b) return a.k < b.k end)
                local atMin, sum, luckyMin, luckyMax, luckySum, nl = 0, 0, 1, 0, 0, 0
                for _, sh in ipairs(list) do
                    sum = sum + sh.k
                    if sh.hit then atMin = atMin + 1 else
                        nl = nl + 1; luckySum = luckySum + sh.k
                        luckyMin = math.min(luckyMin, sh.k); luckyMax = math.max(luckyMax, sh.k)
                    end
                end
                print(string.format("%sinfo 2.5 %s real shops %d: at the minimum %d (%.1f%%), lucky kept %.1f-%.1f avg %.1f, overall avg %.1f",
                    t.TAG, tier, #list, atMin, atMin / #list * 100, luckyMin * 100, luckyMax * 100, nl > 0 and luckySum / nl * 100 or 0, sum / #list * 100))
                local most, least = {}, {}
                for i = 1, math.min(10, #list) do most[#most + 1] = string.format("%s=%.1f", list[i].key, list[i].k * 100) end
                for i = #list, math.max(1, #list - 9), -1 do least[#least + 1] = string.format("%s=%.1f", list[i].key, list[i].k * 100) end
                print(t.TAG .. "info 2.5 " .. tier .. " most affected: " .. table.concat(most, " "))
                print(t.TAG .. "info 2.5 " .. tier .. " least affected: " .. table.concat(least, " "))
            end
        end
    end
end

local function sectionLoadedWorld(t, ctx)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    check("LoadChunk events reached the mod and shops were processed at load",
        (ILB.stats.loadEvents or 0) > 0 and (ILB.stats.loads or 0) > 0, string.format("events %d loads %d", ILB.stats.loadEvents or 0, ILB.stats.loads or 0))
    ctx.list = tierContainers(110)
    local loss, withState, off, overrun, overrunState = 0, 0, 0, 0, 0
    for _, e in ipairs(ctx.list) do
        local a = ILB.getState(e.c)
        if LOSS[e.tier] and e.c:isExplored() then
            loss = loss + 1
            if a ~= nil then withState = withState + 1 end
            if a ~= nil and a ~= ILB.SKIPPED and math.abs(a - oK(e.def, e.tier, ILB.effectiveDay(e.def, ILB.day()))) > 0.01 then off = off + 1 end
        elseif e.tier == "Overrun" and e.c:isExplored() and e.def:isFullyStreamedIn() then
            overrun = overrun + 1
            if a ~= nil then overrunState = overrunState + 1 end
        end
    end
    print(string.format("%sinfo world: %d loss containers (%d with state), %d overrun (%d with state), queue %d, bonus %d",
        t.TAG, loss, withState, overrun, overrunState, ILB.pendingCount(), ILB.stats.bonus))
    check("filled shop containers carry the state of today's loot", loss > 0 and withState > 0 and off == 0, string.format("%d of %d, %d off", withState, loss, off))
    if overrun > 0 then check("3.9 overrun containers (fully loaded buildings) got the bonus at the fill", overrunState == overrun and ILB.stats.bonus > 0, overrunState .. " of " .. overrun) end

    -- 3.10 rooms outside the lists: no state
    local p = getSpecificPlayer(0)
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    local houses, marked = 0, 0
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
                        if obj:getModData()["ILB2_" .. obj:getContainerByIndex(ci):getType()] ~= nil then marked = marked + 1 end
                    end
                end
            end
        end
    end
    check("3.10 containers outside the lists are never touched", houses > 0 and marked == 0, houses .. " containers, " .. marked .. " marked")
end

CZM_TEST_SUITES.ilb2 = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local o = SandboxVars.ImmersiveLootedBuildings
    local phase = t.phase or "full"
    local ctx = {}

    if phase == "vanilla" then
        t.queue(1, function()
            ctx.list = tierContainers(110)
            ctx.skipped = {}
            for _, e in ipairs(ctx.list) do
                if LOSS[e.tier] and ILB.getState(C(e)) == ILB.SKIPPED then ctx.skipped[#ctx.skipped + 1] = { e = e, n = C(e):getItems():size() } end
            end
            check("7.1 game-looted buildings are marked skipped", #ctx.skipped > 0 and ILB.stats.skippedVanilla > 0, tostring(#ctx.skipped))
            local sq = outdoorSquare(40)
            if sq then teleport(sq) end
            o.ProtectRadius = 0
        end)
        for _, d in ipairs({ 30, 330 }) do
            t.queue(60, function()
                t.jumpDays(d)
                local defs = {}
                for _, s in ipairs(ctx.skipped) do defs[s.e.key] = s.e.def end
                for _, def in pairs(defs) do ILB.processBuilding(def, false, "vanilla") end
                local changed = 0
                for _, s in ipairs(ctx.skipped) do if C(s.e):getItems():size() ~= s.n then changed = changed + 1 end end
                check(string.format("7.1 day %d: game-looted containers lose nothing", math.floor(ILB.day())), changed == 0, tostring(changed))
            end)
        end
        t.queue(1, function() o.ProtectRadius = 200; t.finish() end)
        return
    end

    if phase == "apo" then
        t.queue(1, function()
            local day = ILB.day()
            check("6.1 a game started 3 months after the apocalypse is on day 90", day >= 90 and day < 91, string.format("%.2f", day))
            local list = tierContainers(110)
            local n, bad = 0, 0
            for _, e in ipairs(list) do
                local a = ILB.getState(C(e))
                if LOSS[e.tier] and a ~= nil and a ~= ILB.SKIPPED and not ILB.record(e.def) then
                    n = n + 1
                    if math.abs(a - oK(e.def, e.tier, day)) > 0.003 then bad = bad + 1 end
                end
            end
            check("6.1 containers filled on day 90 hold day 90's loot", n > 0 and bad == 0, string.format("%d containers, %d off", n, bad))
            t.finish()
        end)
        return
    end

    t.queue(1, function()
        sectionCurveAndDistribution(t)
        sectionLoadedWorld(t, ctx)
        ctx.buildings = eligibleBuildings(ctx.list)
        print(string.format("%sinfo eligible shop buildings near the spawn: %d", t.TAG, #ctx.buildings))
        local need = phase == "series" and 1 or 4
        check("enough shop buildings for the tests", #ctx.buildings >= need, tostring(#ctx.buildings))
        if phase == "full" then
            -- The base building is also the one used for "entering" (10.5): it is
            -- entered first, then becomes a base through stored items.
            ctx.look, ctx.tele, ctx.clock, ctx.base = ctx.buildings[1], ctx.buildings[2], ctx.buildings[3], ctx.buildings[4]
            ctx.enter = ctx.base
            ctx.series = {}
            for i = 5, #ctx.buildings do ctx.series[#ctx.series + 1] = ctx.buildings[i] end
        else
            ctx.series = ctx.buildings
        end
        ctx.outside = outdoorSquare(60)
        check("an outdoor square near the spawn", ctx.outside ~= nil)
    end)

    if phase == "full" then
        -- 10 and 4: the recent-visit clock and bases, with the real hooks ------
        t.queue(1, function()
            if not ctx.base then return end
            ctx.t0 = ILB.day()
            local e = ctx.clock.containers[1]
            ctx.clockC = e
            fillWith(C(e), 400)
            ILB.setState(C(e), 1, ctx.t0)
            storeItems(C(e), 1) -- a real transfer: tags the item and records a visit
            local r = ILB.record(ctx.clock.def)
            check("10 a real transfer records the visit (E = S = L = today)", r and math.abs(r.E - ctx.t0) < 0.01 and math.abs(r.last - ctx.t0) < 0.01 and r.stored == 1,
                r and string.format("E %.2f L %.2f stored %d", r.E, r.last, r.stored) or "no record")
            check("4.1 the item moved in is tagged", countTagged(C(e)) == 1)
            -- 10.5 entering only: the real move handler
            teleport(freeSquareInside(ctx.enter.def) or ctx.outside)
        end)
        t.queue(60, function()
            if not ctx.base then return end
            ILB.onPlayerMove(getSpecificPlayer(0))
            local r = ILB.record(ctx.enter.def)
            check("10.5 entering a shop records a visit, without a day of use", r ~= nil and (r.days or 0) == 0, r and ("days " .. tostring(r.days)) or "no record")
            ctx.enterE = r and r.E
            -- 4.4 a base through real transfers
            local e = ctx.base.containers[1]
            ctx.baseC = e
            fillWith(C(e), 100)
            ILB.setState(C(e), 1, ILB.day())
            storeItems(C(e), 2)
            check("4.4 two items stored: not a base", not ILB.isBase(ILB.record(ctx.base.def)))
            storeItems(C(e), 1)
            check("4.4 three items stored: a base", ILB.isBase(ILB.record(ctx.base.def)))
            ctx.baseN = C(e):getItems():size()
            teleport(ctx.outside)
            o.ProtectRadius = 0 -- the player is outside: removals may run (9.7 checks the radius itself)
        end)
        for si, step in ipairs({ { 13, "10.1 day 13: nothing lost inside the pause", 0 }, { 7, "10.3 day 20: the clock reads E = 6", 6 }, { 10, "10.4 day 30: the clock reads E = 16", 16 } }) do
            t.queue(si == 1 and 400 or 30, function()
                if not ctx.clockC then return end
                t.jumpDays(step[1])
                ILB.checkDeferred()
                ILB.processBuilding(ctx.clock.def, false, "clock")
                local e = ctx.clockC
                local E = ctx.t0 + step[3]
                local expect = 400 * oK(ctx.clock.def, e.tier, E)
                local n = countUntagged(C(e))
                check(step[2], math.abs(n - expect) <= 3 and countTagged(C(e)) == 1, string.format("%d vs %.1f (E %.2f)", n, expect, ILB.effectiveDay(ctx.clock.def, ILB.day())))
                if ctx.enterE then
                    check("10.5 entered shop: same clock rule", math.abs(ILB.effectiveDay(ctx.enter.def, ILB.day()) - (ctx.enterE + step[3])) < 0.05)
                end
                ILB.processBuilding(ctx.base.def, false, "base")
                check("4.6 a base loses nothing (" .. step[1] .. " more days)", C(ctx.baseC):getItems():size() == ctx.baseN)
            end)
        end
        t.queue(1, function()
            if not ctx.clockC then return end
            -- 4.10 the clock shop becomes a base: loss stops
            storeItems(C(ctx.clockC), 3)
            ctx.clockN = C(ctx.clockC):getItems():size()
            t.jumpDays(30)
            ILB.processBuilding(ctx.clock.def, false, "clock")
            check("4.10 after becoming a base nothing more is removed", C(ctx.clockC):getItems():size() == ctx.clockN)
            check("5.2 tagged items are still there", countTagged(C(ctx.clockC)) == 4)
        end)

        -- 9: never in front of the player ------------------------------------
        t.queue(1, function()
            if not ctx.look then return end
            o.ProtectRadius = 200
            local e = ctx.look.containers[1]
            ctx.lookC = e
            fillWith(C(e), 100)
            ILB.setState(C(e), 1, math.floor(ILB.day()) - 1)
            check("9 setup: the container is due", ILB.isDue(C(e), ctx.look.def, e.tier, ILB.day()))
            ctx.nextSq = freeSquareNextTo(C(e))
            check("9 setup: a free square next to the container", ctx.nextSq ~= nil)
            if ctx.nextSq then teleport(ctx.nextSq) end
        end)
        t.queue(200, function()
            if not ctx.nextSq then return end
            local e = ctx.lookC
            check("9.1/9.6 the real loot window: nothing removed in front of the player", C(e):getItems():size() == 100)
            check("9.1 the building is seen and watched", ILB.seen[ctx.look.key] == true and ILB.deferred[ctx.look.key] ~= nil)
            ILB.checkDeferred()
            ILB.processBuilding(ctx.look.def, false, "near")
            check("9.2 standing there, the watch and an update remove nothing", C(e):getItems():size() == 100)
        end)
        t.queue(200, function()
            if not ctx.nextSq then return end
            check("9.2 still nothing after 200 more ticks", C(ctx.lookC):getItems():size() == 100)
            -- 9.4 walking away while the shop stays loaded: radius 10 for the test,
            -- player 15 to 30 tiles away (the loaded area reaches less than 45 tiles)
            o.ProtectRadius = 10
            local def = ctx.look.def
            local target
            for r = 15, 30 do
                for _, d in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { def:getW() + r, 0 }, { 0, def:getH() + r } }) do
                    local sq = getCell():getGridSquare(def:getX() + d[1], def:getY() + d[2], 0)
                    if sq and not sq:getBuilding() and sq:isFree(false) and ILB.distanceTo(def, sq:getX(), sq:getY()) > 10 then target = sq break end
                end
                if target then break end
            end
            ctx.awaySq = target
            check("9.4 setup: a square away from the building", target ~= nil)
            if target then teleport(target) end
        end)
        t.queue(60, function()
            if not ctx.awaySq then return end
            local p = getSpecificPlayer(0)
            local stillLoaded = getCell():getGridSquare(ctx.lookC.sq:getX(), ctx.lookC.sq:getY(), ctx.lookC.sq:getZ()) ~= nil
            for _ = 1, 31 do ILB.onPlayerMove(p) end -- the real move handler
            local e = ctx.lookC
            local r = ILB.record(ctx.look.def)
            local expect = 100 * oK(ctx.look.def, e.tier, r.E)
            check("9.4 walking away: the waiting removal runs, to today's loot", stillLoaded and math.abs(C(e):getItems():size() - expect) <= 2
                and ILB.deferred[ctx.look.key] == nil and ILB.seen[ctx.look.key] == nil, string.format("%d vs %.1f loaded %s", C(e):getItems():size(), expect, tostring(stillLoaded)))
            local n = C(e):getItems():size()
            ILB.processBuilding(ctx.look.def, false, "again")
            check("9.5 same day: no second removal", C(e):getItems():size() == n)
            -- 9.7 / 9.8 the radius option, with the real player position
            local def = ctx.look.def
            local dist = ILB.distanceTo(def, p:getX(), p:getY())
            local results = {}
            for _, r2 in ipairs({ 0, 50, 200, 400 }) do
                o.ProtectRadius = r2
                results[#results + 1] = tostring(ILB.playerNear(def) == (dist <= r2))
            end
            o.ProtectRadius = 200
            check("9.7 the radius option decides 'near'", table.concat(results, ",") == "true,true,true,true", string.format("distance %.1f", dist))
        end)

        -- 9.3: the shop loads while the player teleports next to a shelf. The real
        -- LoadChunk handler gets the shop's real chunk; the player arrives in the
        -- same frame. The load must run before the loot window shows the items.
        t.queue(1, function()
            if not ctx.tele then return end
            local e = ctx.tele.containers[1]
            ctx.teleC = e
            fillWith(C(e), 100)
            ILB.setState(C(e), 1, math.floor(ILB.day()) - 1)
            ctx.loadsBefore = ILB.stats.loads or 0
            ctx.teleSq = freeSquareNextTo(C(e))
            check("9.3 setup: due, and a free square next to the shelf", ILB.isDue(C(e), ctx.tele.def, e.tier, ILB.day()) and ctx.teleSq ~= nil)
            if not ctx.teleSq then return end
            ILB.onLoadChunk(C(e):getParent():getSquare():getChunk())
            teleport(ctx.teleSq)
        end)
        t.queue(200, function()
            if not ctx.teleSq then return end
            local def, e = ctx.tele.def, ctx.teleC
            local r = ILB.record(def)
            local E = r and r.E or ILB.day()
            local expect = 100 * oK(def, e.tier, E)
            check("9.3 teleported next to a shelf of a shop being loaded: the load ran first", (ILB.stats.loads or 0) > ctx.loadsBefore
                and math.abs(C(e):getItems():size() - expect) <= 2, string.format("%d vs %.1f, loads %d->%d", C(e):getItems():size(), expect, ctx.loadsBefore, ILB.stats.loads or 0))
            check("9.3 then the shop counts as seen", ILB.seen[ctx.tele.key] == true)
            ctx.teleN = C(e):getItems():size()
            t.jumpDays(1)
            local s2 = freeSquareNextTo(C(e))
            if s2 then teleport(getCell():getGridSquare(s2:getX(), s2:getY(), s2:getZ())) end
        end)
        t.queue(200, function()
            if not ctx.teleSq then return end
            ILB.checkDeferred()
            ILB.processBuilding(ctx.tele.def, false, "near")
            check("9.1 the next day, still in front of the shop: nothing removed", C(ctx.teleC):getItems():size() == ctx.teleN)
            teleport(ctx.outside)
        end)
    end

    -- 3: the time series on real containers (calendar days) ----------------------
    t.queue(60, function()
        o.ProtectRadius = 0
        ILB.checkDeferred()
        ctx.series0 = ILB.day()
        ctx.cs = {}
        for _, b in ipairs(ctx.series or {}) do
            for _, e in ipairs(b.containers) do
                fillWith(C(e), 200)
                ILB.setState(C(e), 1, math.floor(ctx.series0))
                ctx.cs[#ctx.cs + 1] = e
            end
        end
        print(string.format("%sinfo series: %d containers in %d buildings, from day %.1f", t.TAG, #ctx.cs, #(ctx.series or {}), ctx.series0))
        if phase == "series" then check("3 series containers found", #ctx.cs > 0)
        elseif #ctx.cs == 0 then print(t.TAG .. "info no shop left for the series here: it runs in the series phase") end
    end)
    local targets = { 7, 30, 90, 180, 360 }
    for i, day in ipairs(targets) do
        t.queue(30, function()
            if not ctx.cs or #ctx.cs == 0 then return end
            local now = ILB.day()
            local goal = day
            if goal <= now then goal = now + (i == 1 and 1 or 30) end
            t.jumpDays(math.ceil(goal - now))
            local d = ILB.day()
            processAll(ctx.series, "series")
            local bad, tot, left, hitL, hitN, luckL, luckN, luckLo, luckHi = 0, 0, 0, 0, 0, 0, 0, 2, -1
            for _, e in ipairs(ctx.cs) do
                local k = oK(e.def, e.tier, d)
                local n = C(e):getItems():size()
                if math.abs(n - 200 * k) > 4 then bad = bad + 1 end
                tot = tot + 200; left = left + n
                local _, hit = oS(e.def, e.tier)
                if hit then hitL = hitL + n / 200; hitN = hitN + 1 else
                    luckL = luckL + n / 200; luckN = luckN + 1
                    luckLo = math.min(luckLo, n / 200); luckHi = math.max(luckHi, n / 200)
                end
            end
            print(string.format("%sinfo 3.2 day %.1f: loot left %.1f%%, hit containers %d avg %.1f%%, lucky %d avg %.1f%% (%.1f-%.1f)", t.TAG, d,
                left / math.max(1, tot) * 100, hitN, hitN > 0 and hitL / hitN * 100 or 0, luckN, luckN > 0 and luckL / luckN * 100 or 0, luckLo * 100, luckHi * 100))
            check(string.format("3.1/3.3 day %d: every container follows its building's K", math.floor(d)), bad == 0, bad .. " off of " .. #ctx.cs)
            local before = left
            processAll(ctx.series, "series")
            local after = 0
            for _, e in ipairs(ctx.cs) do after = after + C(e):getItems():size() end
            check(string.format("3.5 day %d: a second update the same day removes nothing", math.floor(d)), after == before)
        end)
    end

    -- 3.9 overrun, 5 options, 8.1 cost ------------------------------------------
    t.queue(1, function()
        o.ProtectRadius = 200
        local ov
        -- An overrun container in a fully loaded building (the mod waits for the
        -- whole building before it handles a fill).
        for _, e in ipairs(ctx.list or {}) do
            local c = C(e)
            if e.tier == "Overrun" and c and ILB.getState(c) ~= nil and e.def:isFullyStreamedIn() then ov = e break end
        end
        if ov then
            local n = C(ov):getItems():size()
            ILB.processBuilding(ov.def, true, "overrun")
            check("3.9 overrun containers never lose loot", C(ov):getItems():size() == n)
            fillWith(C(ov), 400)
            ILB.onFill(ov.room, C(ov):getType(), C(ov)) -- a refill (state exists): respawn
            ctx.ov = ov
        else
            print(t.TAG .. "info no overrun room near the spawn")
        end
        -- Enabled off: a fill leaves no state, a transfer no tag
        local e = ctx.series and ctx.series[1] and ctx.series[1].containers[1]
        ctx.offC = e
        if e then
            o.Enabled = false
            local obj = C(e):getParent()
            obj:getModData()["ILB2_" .. C(e):getType()] = nil
            obj:getModData()["ILB2d_" .. C(e):getType()] = nil
            fillWith(C(e), 50)
            ILB.onFill(e.room, C(e):getType(), C(e))
        end
    end)
    t.queue(75, function()
        if ctx.ov then
            local n = C(ctx.ov):getItems():size()
            check("3.9/5 respawn on: an overrun refill gets the bonus again", n > 400 and n <= 520, tostring(n))
            o.ApplyOnRespawn = false
            fillWith(C(ctx.ov), 400)
            ILB.onFill(ctx.ov.room, C(ctx.ov):getType(), C(ctx.ov))
        end
        if ctx.offC then
            local inv = getSpecificPlayer(0):getInventory()
            local it = inv:AddItem("Base.Pencil")
            ISTransferAction:transferItem(getSpecificPlayer(0), it, inv, C(ctx.offC), nil)
            check("5 Enabled off: no state after a fill, no tag after a transfer", ILB.getState(C(ctx.offC)) == nil and not (it:hasModData() and it:getModData().ILB_player))
            o.Enabled = true
        end
    end)
    t.queue(75, function()
        if ctx.ov then
            check("5 respawn off: the refill is left as the game made it", C(ctx.ov):getItems():size() == 400)
            o.ApplyOnRespawn = true
        end
        if ctx.offC then
            o.LogDecisions = true
            ILB.update(C(ctx.offC), ctx.offC.def, ctx.offC.tier, ILB.day(), "logtest", true)
            o.LogDecisions = false
            print(t.TAG .. "info a line with 'logtest' must be in the console above")
            local c = C(ctx.offC)
            local n = 50000
            local t0 = getTimestampMs()
            for _ = 1, n do ILB.onFill("bedroom", "wardrobe", c) end
            local per = (getTimestampMs() - t0) * 1000 / n
            print(string.format("%sinfo cost: house fill %.2f us per call", t.TAG, per))
            check("8.1 a house fill costs a few microseconds", per < 20, string.format("%.2f us", per))
            for k in pairs(ILB.deferred) do ILB.deferred[k] = nil end
            local p = getSpecificPlayer(0)
            t0 = getTimestampMs()
            for _ = 1, n do ILB.onPlayerMove(p) end
            per = (getTimestampMs() - t0) * 1000 / n
            print(string.format("%sinfo cost: move handler %.2f us per call", t.TAG, per))
            check("9.11/10.15 the move handler costs a few microseconds", per < 30, string.format("%.2f us", per))
        end
        t.finish()
    end)
end

-- ---------------------------------------------------------------- two-launch suites

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

-- Default room lists, for phases without the mod.
local DEFAULT_ROOMS = {
    High = "grocery;grocerystorage;gigamart;conveniencestore;cornerstore;cornerstorestorage;generalstore;generalstorestorage;departmentstore;departmentstorage;pharmacy;pharmacystorage;liquorstore;bakery;butcher;candystore;gasstore;zippeestore",
    Medium = "toolstore;toolstorestorage;gunstore;gunstorestorage;electronicstore;sportstore;outdoorsupply;outdoorsupply_storage",
    Low = "fishingstorage;knifestore;golfstore;baseballstore;giftstore;toystore;jewelrystore;musicstore",
}
local roomTier = {}
for tier, list in pairs(DEFAULT_ROOMS) do for r in list:gmatch("[^;]+") do roomTier[r] = tier end end

local function scanShops(radius)
    local p = getSpecificPlayer(0)
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    local out = {}
    for z = 0, 1 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local sq = getCell():getGridSquare(px + dx, py + dy, z)
                local room = sq and sq:getRoom()
                local tier = room and roomTier[room:getName()]
                if tier then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        for ci = 0, obj:getContainerCount() - 1 do
                            out[#out + 1] = { c = obj:getContainerByIndex(ci), tier = tier, sq = sq, def = sq:getBuilding():getDef(),
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
    local objs = sq:getObjects()
    if objs:size() <= tonumber(i) then return nil end
    local obj = objs:get(tonumber(i))
    if obj:getContainerCount() <= tonumber(ci) then return nil end
    return obj:getContainerByIndex(tonumber(ci)), sq
end

local function stateA(c)
    local obj = c:getParent()
    return obj and obj:getModData()["ILB2_" .. c:getType()]
end

-- rows: key|A|items|tagged|tier
local function snapshot(list)
    local rows = {}
    for _, e in ipairs(list) do
        local a = stateA(e.c)
        rows[#rows + 1] = string.format("%s|%s|%d|%d|%s", e.key, a and string.format("%.6f", a) or "nil", e.c:getItems():size(), countTagged(e.c), e.tier)
    end
    return rows
end

local function parseRows(lines)
    local meta, rows = {}, {}
    for _, l in ipairs(lines) do
        local k, v = l:match("^meta:([%w_]+)=(.*)$")
        if k then meta[k] = v else
            local key, a, n, tg, tier = l:match("^([^|]+)|([^|]+)|(%d+)|(%d+)|(%a+)$")
            if key then rows[#rows + 1] = { key = key, a = tonumber(a), items = tonumber(n), tagged = tonumber(tg), tier = tier } end
        end
    end
    return meta, rows
end

local function saveAndFinish(t)
    t.queue(1, function()
        local ok, err = pcall(saveGame)
        print(t.TAG .. "info saveGame " .. (ok and "ok" or tostring(err)))
    end)
    t.queue(240, function() t.finish() end)
end

local function intactShop(list)
    for _, e in ipairs(list) do
        if not (e.def:isAllExplored() and not e.def:isHasBeenVisited()) and e.c:isExplored() then return e end
    end
end

CZM_TEST_SUITES.ilb2_persist = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local FILE = "czm_ilb2_persist.txt"
    if t.phase ~= "load" then
        t.queue(1, function()
            check("save: mod loaded", ILB ~= nil)
            local list = scanShops(80)
            local e = intactShop(list)
            check("save: an intact shop", e ~= nil)
            if not e then return end
            storeItems(e.c, 1) -- a visited shop (clock), with a tagged item
            local r = ILB.record(e.def)
            local w
            for _, x in ipairs(list) do
                if ILB.buildingKey(x.def) ~= ILB.buildingKey(e.def) and x.c:isExplored() and not (x.def:isAllExplored() and not x.def:isHasBeenVisited()) then w = x break end
            end
            local lines = {
                "meta:seed=" .. tostring(ILB.data().seed),
                "meta:building=" .. ILB.buildingKey(e.def),
                string.format("meta:record=%.6f,%.6f,%.6f,%d,%d", r.E, r.S, r.last, r.days or 0, r.stored or 0),
            }
            if w then
                -- 9.10 a removal waiting at the save: the player looks at this shop
                t.jumpDays(1)
                fillWith(w.c, 100)
                ILB.setState(w.c, 1, math.floor(ILB.day()) - 1)
                ILB.seen[ILB.buildingKey(w.def)] = true -- as the loot window does
                ILB.deferred[ILB.buildingKey(w.def)] = w.def
                ILB.processBuilding(w.def, false, "save")
                check("save: the waiting container is due and untouched", w.c:getItems():size() == 100 and ILB.isDue(w.c, w.def, w.tier, ILB.day()))
                lines[#lines + 1] = "meta:waiting=" .. w.key
            end
            for _, row in ipairs(snapshot(list)) do lines[#lines + 1] = row end
            writeLines(FILE, lines)
        end)
        saveAndFinish(t)
        return
    end
    t.queue(1, function()
        check("load: mod loaded after continue", ILB ~= nil)
        local meta, rows = parseRows(readLines(FILE))
        check("load: data from the save phase", meta.seed ~= nil and #rows > 0, tostring(#rows))
        check("6.2 seed unchanged after save and load", tostring(ILB.data().seed) == meta.seed)
        local r = ILB.data().used[meta.building]
        local sE, sS, sL, sD, sSt = meta.record:match("^([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),(%d+),(%d+)$")
        sE, sS, sL = tonumber(sE), tonumber(sS), tonumber(sL)
        -- E only moves after the 14-day pause; S is brought up to date by every update (sync).
        local expectE = sE + math.max(0, ILB.day() - math.max(sS, sL + opt("RecentVisitDays", 14)))
        check("6.2/10.13 the visit clock survives save and load", r ~= nil and math.abs(r.E - expectE) < 1e-4 and math.abs(r.last - sL) < 1e-6
            and (r.days or 0) == tonumber(sD) and (r.stored or 0) == tonumber(sSt) and r.S >= sS - 1e-6,
            r and string.format("E %.6f/%.6f L %.6f S %.6f", r.E, expectE, r.last, r.S) or "missing")
        local bad, matched = {}, 0
        for _, row in ipairs(rows) do
            if row.key ~= meta.waiting and row.a ~= nil then
                local c = findByKey(row.key)
                if c then
                    -- At the load the shop was updated to today's loot (once per day):
                    -- A is the smaller of the saved A and today's K; items follow it.
                    local _, sq = findByKey(row.key)
                    local def = sq:getBuilding():getDef()
                    local a = stateA(c)
                    local k = ILB.keep(def, row.tier, ILB.day())
                    local expectA = k and math.min(row.a, k) or row.a
                    local itemsOk = (math.abs(expectA - row.a) < 1e-9 and c:getItems():size() == row.items)
                        or (c:getItems():size() <= row.items and math.abs(c:getItems():size() - row.items * expectA / row.a) <= 1)
                    if a and math.abs(a - expectA) < 1e-4 and itemsOk and countTagged(c) == row.tagged then matched = matched + 1
                    elseif #bad < 4 then bad[#bad + 1] = string.format("%s a %s->%s (%.6f) items %d->%d", row.key, tostring(row.a), tostring(a), expectA, row.items, c:getItems():size()) end
                end
            end
        end
        check("6.2 A, items and tags survive save and load (updated once to today's loot at the load)", #bad == 0 and matched > 0, table.concat(bad, "; "))
        if meta.waiting then
            local c, sq = findByKey(meta.waiting)
            local def = sq and sq:getBuilding():getDef()
            local tier
            for _, row in ipairs(rows) do if row.key == meta.waiting then tier = row.tier end end
            local expect = def and 100 * oK(def, tier, ILB.effectiveDay(def, ILB.day()))
            check("9.10 the removal waiting at the save ran when the shop loaded again", c ~= nil and expect ~= nil and math.abs(c:getItems():size() - expect) <= 2,
                c and expect and string.format("%d vs %.1f", c:getItems():size(), expect) or "not found")
        end
        t.finish()
    end)
end

CZM_TEST_SUITES.ilb2_midsave = function(t)
    local ILB = ImmersiveLootedBuildings
    local check = t.check
    local phase = t.phase or "prep"
    local FILE, FILE2 = "czm_ilb2_midsave.txt", "czm_ilb2_midsave_add.txt"

    if phase == "prep" then
        t.queue(1, function()
            check("prep: the mod is not active", ILB == nil)
            t.jumpDays(60)
            local list = scanShops(80)
            writeLines(FILE, snapshot(list))
            print(string.format("%sinfo prep: %d shop containers written, day %.1f", t.TAG, #list, getGameTime():getWorldAgeHours() / 24))
            check("prep: shop containers found", #list > 0)
        end)
        saveAndFinish(t)
        return
    end

    if phase == "add" then
        t.queue(1, function()
            check("6.3 mod active after adding it to the save", ILB ~= nil)
            if not ILB then return end
            local _, rows = parseRows(readLines(FILE))
            check("add: prep data", #rows > 0)
            local day = ILB.day()
            local n, bad, skipped = 0, {}, 0
            for _, row in ipairs(rows) do
                local c, sq = findByKey(row.key)
                if c and c:isExplored() then
                    local def = sq:getBuilding():getDef()
                    local a = stateA(c)
                    if a == ILB.SKIPPED then skipped = skipped + 1 else
                        n = n + 1
                        local expect = row.items * oK(def, row.tier, ILB.effectiveDay(def, day))
                        if a == nil or math.abs(c:getItems():size() - expect) > math.max(2, row.items * 0.02) then
                            if #bad < 4 then bad[#bad + 1] = string.format("%s %d->%d (%.1f) a=%s", row.key, row.items, c:getItems():size(), expect, tostring(a)) end
                        end
                    end
                end
            end
            print(string.format("%sinfo add: %d containers checked, %d game-looted, day %.1f", t.TAG, n, skipped, day))
            check("6.3 at the load, shops filled before the mod went to today's loot", n > 0 and #bad == 0, table.concat(bad, "; "))
            local e = intactShop(scanShops(80))
            if e then
                storeItems(e.c, 2, "Base.Pencil")
                check("6.3 items stored after adding the mod are tagged", countTagged(e.c) >= 2)
            end
            local lines = { "meta:seed=" .. tostring(ILB.data().seed) }
            for _, r in ipairs(snapshot(scanShops(80))) do lines[#lines + 1] = r end
            writeLines(FILE2, lines)
        end)
        saveAndFinish(t)
        return
    end

    local function compareAdd(label)
        local meta, rows = parseRows(readLines(FILE2))
        local bad, matched = {}, 0
        for _, row in ipairs(rows) do
            local c = findByKey(row.key)
            if c then
                local a = stateA(c)
                local sameA = (a == nil and row.a == nil) or (a ~= nil and row.a ~= nil and math.abs(a - row.a) < 1e-5)
                if sameA and c:getItems():size() == row.items and countTagged(c) == row.tagged then matched = matched + 1
                elseif #bad < 4 then bad[#bad + 1] = string.format("%s items %d->%d", row.key, row.items, c:getItems():size()) end
            end
        end
        check(label, #bad == 0 and matched > 0, table.concat(bad, "; "))
        return meta
    end

    if phase == "remove" then
        t.queue(1, function()
            check("6.4 the save loads with the mod removed", ImmersiveLootedBuildings == nil)
            compareAdd("6.4 without the mod, containers, states and tags stay as they were")
        end)
        saveAndFinish(t)
        return
    end

    if phase == "readd" then
        t.queue(1, function()
            check("6.4 mod active again", ILB ~= nil)
            if not ILB then return end
            local meta = compareAdd("6.4 added again, same day: states, items and tags unchanged")
            check("6.4 same seed as before the removal", tostring(ILB.data().seed) == meta.seed)
            t.finish()
        end)
        return
    end
    t.queue(1, function() check("unknown phase " .. tostring(phase), false); t.finish() end)
end
