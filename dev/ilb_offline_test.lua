--[[
    Immersive Looted Buildings - offline checks of the core (plain Lua 5.4).

        lua dev/ilb_offline_test.lua

    Loads ILB_Core.lua with small stand-ins for the game API and compares it
    with formulas written again here (never the mod's own functions as the
    reference). The in-game suites (dev/CZMAutoTest, mode ilb2*) check the
    same things against the real game.
]]

local ROOT = arg and arg[0]:match("^(.*)/dev/") or "."
local MOD = ROOT .. "/Immersive_Looted_Buildings/Contents/mods/ImmersiveLootedBuildings/42/media"

-- Sandbox defaults read from sandbox-options.txt.
local function readDefaults()
    local f = assert(io.open(MOD .. "/sandbox-options.txt"))
    local text = f:read("a")
    f:close()
    local o = {}
    for name, typ, def in text:gmatch("option ImmersiveLootedBuildings%.(%w+) = {%s*type = (%w+),[^}]-default = ([^,\n]+),") do
        if typ == "boolean" then o[name] = (def == "true")
        elseif typ == "string" then o[name] = def
        else o[name] = tonumber(def) end
    end
    return o
end
local DEFAULTS = readDefaults()
local function resetOptions()
    SandboxVars = { ImmersiveLootedBuildings = {} }
    for k, v in pairs(DEFAULTS) do SandboxVars.ImmersiveLootedBuildings[k] = v end
end
resetOptions()

-- Game stand-ins.
local worldHours, timeSinceApo = 0, 1
local store = {}
ModData = { getOrCreate = function(k) store[k] = store[k] or {} return store[k] end }
math.randomseed(12345)
ZombRand = function(a, b) if b then return math.random(a, b - 1) end return math.random(0, a - 1) end
ZombRandFloat = function(a, b) return a + math.random() * (b - a) end
getGameTime = function() return { getWorldAgeHours = function() return worldHours end } end
getSandboxOptions = function() return { getTimeSinceApo = function() return timeSinceApo end } end
isServer = function() return false end
instanceof = function(o, cls) return cls == "Key" and o.key == true end
print_ = print
isClient = function() return false end
Events = setmetatable({}, { __index = function() return { Add = function() end, Remove = function() end } end })
package.preload["ImmersiveLootedBuildings/ILB_Core"] = function() return true end -- loaded with dofile below

dofile(MOD .. "/lua/shared/ImmersiveLootedBuildings/ILB_Core.lua")
local ILB = ImmersiveLootedBuildings
ILB.data().seed = 424242

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1 else fail = fail + 1 end
    print((cond and "PASS " or "FAIL ") .. name .. (detail and (" (" .. detail .. ")") or ""))
end

-- Reference formulas, written again from DESIGN.md.
local TIERS = { High = { 0.70, 0.60, 0.30 }, Medium = { 0.50, 0.70, 0.50 }, Low = { 0.30, 0.80, 0.70 } }
local function refFp(tier)
    local o = SandboxVars.ImmersiveLootedBuildings
    local mn, pk = o[tier .. "MinLoot"] / 100, o[tier .. "PeakLoot"] / 100
    if mn >= 1 then return 1 end
    return math.max(0, math.min(1, (1 - pk) / (1 - mn)))
end
local function refG(t, tier)
    local o = SandboxVars.ImmersiveLootedBuildings
    local S, P, E, k, I = o.StartDay, math.max(o.StartDay, o.PeakDay), math.max(o.PeakDay, o.EndDay), o.Slowdown, o.InitialShare / 100
    if t < S then return 0 end
    local Fp, g = refFp(tier)
    if t <= S then g = 0
    elseif t >= E then g = 1
    elseif t < P then g = Fp * (t - S) / (P - S)
    else
        local x = (t - P) / (E - P)
        g = Fp + (1 - Fp) * (1 - math.exp(-k * x)) / (1 - math.exp(-k))
    end
    return I + (1 - I) * g
end
local function refK(s, t, tier)
    return 1 - s * (1 - SandboxVars.ImmersiveLootedBuildings[tier .. "MinLoot"] / 100) * refG(t, tier)
end
local function fakeDef(x, y)
    return { getX = function() return x end, getY = function() return y end, getW = function() return 10 end, getH = function() return 10 end }
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

-- 1. The curve and the reference tables --------------------------------------
check("1.1 Fp High", near(ILB.peakShare("High"), 0.4 / 0.7), tostring(ILB.peakShare("High")))
check("1.1 Fp Medium", near(ILB.peakShare("Medium"), 0.6), tostring(ILB.peakShare("Medium")))
check("1.1 Fp Low", near(ILB.peakShare("Low"), 2 / 3), tostring(ILB.peakShare("Low")))

local worst, mono = 0, true
for _, tier in ipairs({ "High", "Medium", "Low" }) do
    local prev = -1
    for t = 0, 800, 0.5 do
        local g = ILB.curve(t, tier)
        worst = math.max(worst, math.abs(g - refG(t, tier)))
        if g < prev - 1e-12 then mono = false end
        prev = g
    end
end
check("1.2 g(t) matches the formula and never decreases", worst < 1e-9 and mono, string.format("max diff %.1e", worst))

local TABLE = {
    High = { 100, 60.0, 49.8, 41.4, 36.6, 31.3, 30.0 },
    Medium = { 100, 70.0, 63.2, 57.6, 54.4, 50.8, 50.0 },
    Low = { 100, 80.0, 76.6, 73.8, 72.2, 70.4, 70.0 },
}
local LUCKY_LO = { High = { 100, 66.0, 57.3, 50.2, 46.1, 41.6, 40.5 } }
local LUCKY_HI = { High = { 100, 72.0, 64.8, 59.0, 55.6, 51.9, 51.0 } }
local DAYS = { 0, 7, 30, 60, 90, 180, 360 }
local okTable = true
for tier, row in pairs(TABLE) do
    for i, d in ipairs(DAYS) do
        if math.abs(refK(1, d, tier) * 100 - row[i]) > 0.06 then okTable = false end
        if math.abs((1 - (1 - ILB.minLoot(tier)) * ILB.curve(d, tier)) * 100 - row[i]) > 0.06 then okTable = false end
    end
end
check("1.3 hit K(t) matches the DESIGN tables", okTable)
local okLucky = true
for i, d in ipairs(DAYS) do
    if math.abs(refK(0.85, d, "High") * 100 - LUCKY_LO.High[i]) > 0.06 then okLucky = false end
    if math.abs(refK(0.70, d, "High") * 100 - LUCKY_HI.High[i]) > 0.06 then okLucky = false end
end
check("1.4 lucky least / most kept (High) match the DESIGN table", okLucky)

-- 2. Groups and distribution over synthetic buildings ----------------------------
local N = 20000
local defs = {}
for i = 1, N do defs[i] = fakeDef(math.random(0, 20000), math.random(0, 20000)) end
local AVG = { High = { 100, 62.7, 53.1, 45.4, 40.9, 35.9, 34.7 }, Medium = { 100, 73.4, 67.3, 62.4, 59.5, 56.4, 55.6 }, Low = { 100, 83.2, 80.3, 77.9, 76.6, 75.1, 74.7 } }
for _, tier in ipairs({ "High", "Medium", "Low" }) do
    local C = TIERS[tier][1]
    local hits, okHit, okLucky2, buckets = 0, true, true, {}
    for b = 0, 9 do buckets[b] = 0 end
    local sumK = {}
    for i, def in ipairs(defs) do
        local s = ILB.strength(def, tier)
        if ILB.isHit(def, tier) then
            hits = hits + 1
            if s ~= 1 then okHit = false end
        else
            if s < 0.70 - 1e-9 or s > 0.85 + 1e-9 then okLucky2 = false end
            buckets[math.min(9, math.floor((s - 0.70) / 0.015))] = buckets[math.min(9, math.floor((s - 0.70) / 0.015))] + 1
        end
        for j, d in ipairs(DAYS) do sumK[j] = (sumK[j] or 0) + ILB.keep(def, tier, d) end
    end
    local share = hits / N
    local sigma = 3 * math.sqrt(C * (1 - C) / N)
    check("2.1 " .. tier .. " hit share = chance", math.abs(share - C) <= sigma, string.format("%.4f vs %.2f", share, C))
    check("2.2 " .. tier .. " every hit building has s = 1", okHit)
    check("2.3 " .. tier .. " every lucky building inside the lucky range", okLucky2)
    local lucky = N - hits
    local okBuckets = true
    for b = 0, 9 do
        local e = lucky / 10
        if math.abs(buckets[b] - e) > 4 * math.sqrt(e) then okBuckets = false end
    end
    check("2.4 " .. tier .. " lucky strength uniform (10 buckets)", okBuckets)
    local okAvg = true
    local parts = {}
    for j, d in ipairs(DAYS) do
        local avg = sumK[j] / N * 100
        parts[#parts + 1] = string.format("d%d %.1f/%.1f", d, avg, AVG[tier][j])
        if math.abs(avg - AVG[tier][j]) > 0.5 then okAvg = false end
    end
    check("1.5 " .. tier .. " average K matches the DESIGN averages", okAvg, table.concat(parts, " "))
end
-- 2.6 / 2.7 the same building, same answers, K never goes up
local stable, never = true, true
for i = 1, 500 do
    local d = defs[i]
    if ILB.strength(d, "High") ~= ILB.strength(fakeDef(d.getX(), d.getY()), "High") then stable = false end
    local prev = 2
    for t = 0, 400, 5 do
        local k = ILB.keep(d, "High", t)
        if k > prev + 1e-12 then never = false end
        prev = k
    end
end
check("2.6 group and strength stable", stable)
check("2.7 K never goes up", never)

-- 3. Container updates (fake containers) ----------------------------------------
local function fakeItem(fullType, opts)
    local md = {}
    local it = { fullType = fullType or "Base.Nails", key = opts and opts.key, cat = opts and opts.cat or "Junk" }
    function it:getFullType() return self.fullType end
    function it:hasModData() return next(md) ~= nil end
    function it:getModData() return md end
    function it:getDisplayCategory() return self.cat end
    function it:getCategory() return "Normal" end
    if opts and opts.tag then md[ILB.TAG] = true end
    return it
end
local function fakeContainer(n, ctype)
    local items = {}
    for i = 1, n do items[i] = fakeItem() end
    local md = {}
    local parent = { getModData = function() return md end }
    local c = { items = items, ctype = ctype or "shelves" }
    function c:getItems()
        local list = self.items
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    function c:DoRemoveItem(it)
        for i, x in ipairs(self.items) do if x == it then table.remove(self.items, i) return end end
    end
    function c:AddItem(ft) local it = fakeItem(ft) self.items[#self.items + 1] = it return it end
    function c:getParent() return parent end
    function c:getType() return self.ctype end
    function c:count() return #self.items end
    return c
end
local function hitDef(tier)
    for i = 1, 1000 do local d = fakeDef(i * 13, i * 7) if ILB.isHit(d, tier) then return d end end
end
local function luckyDef(tier)
    for i = 1, 1000 do local d = fakeDef(i * 13, i * 7) if not ILB.isHit(d, tier) then return d end end
end

local function setDay(d) worldHours = d * 24 end

-- 3.1 / 3.2: one hit container followed day by day (1000 items so rounding is small)
do
    local def = hitDef("High")
    local c = fakeContainer(1000)
    setDay(0)
    ILB.update(c, def, "High", 0, "fill", true)
    local okSteps, parts = true, {}
    for _, d in ipairs({ 7, 30, 90, 360 }) do
        ILB.update(c, def, "High", d, "test")
        local expect = refK(1, d, "High") * 1000
        parts[#parts + 1] = string.format("d%d %d/%.1f", d, c:count(), expect)
        if math.abs(c:count() - expect) > 3 then okSteps = false end
    end
    check("3.1 a hit container follows K(t) day by day", okSteps, table.concat(parts, " "))
    local a = ILB.getState(c)
    check("3.1 A equals K at the last update", near(a, refK(1, 360, "High"), 1e-9), tostring(a))
end
-- 3.3 lucky container ends between the lucky minimum and maximum
do
    local def = luckyDef("High")
    local c = fakeContainer(1000)
    ILB.update(c, def, "High", 0, "fill", true)
    ILB.update(c, def, "High", 360, "test")
    local kept = c:count() / 1000
    check("3.3 lucky container ends inside the lucky band", kept >= 0.405 - 0.005 and kept <= 0.51 + 0.005, string.format("%.3f", kept))
end
-- 3.4 first fill on day 90 goes straight to K(90)
do
    local def = hitDef("Medium")
    local c = fakeContainer(1000)
    ILB.update(c, def, "Medium", 90, "fill", true)
    check("3.4 a fill on day 90 is already at K(90)", math.abs(c:count() - refK(1, 90, "Medium") * 1000) <= 3, tostring(c:count()))
end
-- 3.5 twice on the same day removes nothing the second time
do
    local def = hitDef("High")
    local c = fakeContainer(400)
    ILB.update(c, def, "High", 0, "fill", true)
    ILB.update(c, def, "High", 30.2, "a")
    local n1 = c:count()
    local r2 = ILB.update(c, def, "High", 30.8, "b")
    check("3.5 second update on the same day does nothing", r2 == nil and c:count() == n1)
end
-- 3.6 a container the player half emptied loses the share of what is left
do
    local def = hitDef("High")
    local c = fakeContainer(1000)
    ILB.update(c, def, "High", 0, "fill", true)
    ILB.update(c, def, "High", 30, "a")
    local a30 = ILB.getState(c)
    for _ = 1, math.floor(c:count() / 2) do table.remove(c.items) end
    local left = c:count()
    ILB.update(c, def, "High", 90, "b")
    local expect = left * refK(1, 90, "High") / a30
    check("3.6 half emptied: the update removes the share of what is left", math.abs(c:count() - expect) <= 2, string.format("%d vs %.1f", c:count(), expect))
end
-- 3.7 small containers average out
do
    local def = hitDef("High")
    local total, over = 0, false
    for _ = 1, 3000 do
        local c = fakeContainer(2)
        local removed = ILB.update(c, def, "High", 360, "fill", true)
        total = total + removed
        if removed > 2 then over = true end
    end
    local share = total / 6000
    check("3.7 small containers: average removed share right, never over", math.abs(share - 0.70) < 0.03 and not over, string.format("%.3f", share))
end
-- 3.8 useful first
do
    SandboxVars.ImmersiveLootedBuildings.UsefulFirst = true
    local c = fakeContainer(0)
    for _ = 1, 50 do c.items[#c.items + 1] = fakeItem("Base.Beans", { cat = "Food" }) end
    for _ = 1, 50 do c.items[#c.items + 1] = fakeItem("Base.Pencil", { cat = "HouseholdWeapon" }) end
    ILB.cutContainer(c, 0.5)
    local food = 0
    for _, it in ipairs(c.items) do if it.cat == "Food" then food = food + 1 end end
    SandboxVars.ImmersiveLootedBuildings.UsefulFirst = false
    check("3.8 useful first: food goes before junk, same count", c:count() == 50 and food == 0, "food left " .. food)
end
-- 4.1 / 4.3 tagged items and keys are never removed
do
    local def = hitDef("High")
    local c = fakeContainer(80)
    for _ = 1, 20 do c.items[#c.items + 1] = fakeItem("Base.Nails", { tag = true }) end
    c.items[#c.items + 1] = fakeItem("Base.Key1", { key = true })
    SandboxVars.ImmersiveLootedBuildings.HighMinLoot = 0
    ILB.update(c, def, "High", 0, "fill", true)
    ILB.update(c, def, "High", 400, "test")
    SandboxVars.ImmersiveLootedBuildings.HighMinLoot = DEFAULTS.HighMinLoot
    local tagged, keys = 0, 0
    for _, it in ipairs(c.items) do
        if it:hasModData() and it:getModData()[ILB.TAG] then tagged = tagged + 1 end
        if it.key then keys = keys + 1 end
    end
    check("4.1/4.3 with minimum 0 everything goes except tagged items and keys", c:count() == 21 and tagged == 20 and keys == 1, tostring(c:count()))
end

-- 4. Bases ------------------------------------------------------------------
do
    store = {}
    ILB.data().seed = 424242
    local def = hitDef("High")
    ILB.touch(def, "use", 2, 0)
    check("4.4 two items stored is not a base", not ILB.isBase(ILB.record(def)))
    ILB.touch(def, "use", 1, 0)
    check("4.4 three items stored is a base", ILB.isBase(ILB.record(def)))
    check("4.6 a base keeps no target (never loses loot)", ILB.keep(def, "High", 360) == nil)
    local d2 = fakeDef(-5, -5)
    ILB.touch(d2, "use", 0, 1.2)
    ILB.touch(d2, "use", 0, 1.9)
    ILB.touch(d2, "use", 0, 2.5)
    check("4.5 activity on 2 days is not a base", not ILB.isBase(ILB.record(d2)), tostring(ILB.record(d2).days))
    ILB.touch(d2, "use", 0, 3.1)
    check("4.5 activity on 3 days is a base", ILB.isBase(ILB.record(d2)))
    local d3 = fakeDef(-9, -9)
    ILB.touch(d3, "enter", 0, 1); ILB.touch(d3, "enter", 0, 2); ILB.touch(d3, "enter", 0, 3); ILB.touch(d3, "enter", 0, 4)
    check("4.7 entering on 4 days does not make a base", not ILB.isBase(ILB.record(d3)))
    SandboxVars.ImmersiveLootedBuildings.BaseItems = 1
    local b1 = ILB.isBase({ stored = 1, days = 0 })
    SandboxVars.ImmersiveLootedBuildings.BaseItems = 10
    local b10 = ILB.isBase({ stored = 9, days = 0 })
    SandboxVars.ImmersiveLootedBuildings.BaseItems = 3
    check("4.8 base threshold option 1 and 10", b1 and not b10)
    -- 4.10 a building that loses loot, then becomes a base
    local def4 = fakeDef(777, 333)
    local c = fakeContainer(1000)
    ILB.update(c, def4, "High", 0, "fill", true)
    ILB.update(c, def4, "High", 30, "a")
    local n30 = c:count()
    ILB.touch(def4, "use", 3, 40)
    ILB.update(c, def4, "High", 200, "b")
    check("4.10 after becoming a base nothing more is removed", c:count() == n30)
end

-- 10. Recent visit clock (arithmetic of DESIGN.md) ------------------------------
do
    store = {}
    ILB.data().seed = 424242
    local d = fakeDef(100, 100)
    ILB.touch(d, "use", 0, 0)
    check("10.1 day 13: E = 0", near(ILB.effectiveDay(d, 13), 0))
    check("10.2 day 14: E = 0", near(ILB.effectiveDay(d, 14), 0))
    check("10.3 day 20: E = 6", near(ILB.effectiveDay(d, 20), 6))
    check("10.4 day 30: E = 16", near(ILB.effectiveDay(d, 30), 16))
    local e = fakeDef(200, 200)
    ILB.touch(e, "enter", 0, 0)
    check("10.5 entering counts as a visit (E = 6 on day 20)", near(ILB.effectiveDay(e, 20), 6))
    local f = fakeDef(300, 300)
    ILB.touch(f, "use", 0, 0); ILB.touch(f, "use", 0, 10)
    check("10.6 second visit on day 10: E = 0 on day 23 and 24", near(ILB.effectiveDay(f, 23), 0) and near(ILB.effectiveDay(f, 24), 0))
    check("10.6 E = 9 on day 33", near(ILB.effectiveDay(f, 33), 9))
    check("10.7 never visited: E = calendar", near(ILB.effectiveDay(fakeDef(400, 400), 90), 90))
    local g = fakeDef(500, 500)
    ILB.touch(g, "use", 0, 60)
    check("10.8 first visit on day 60: E = 60", near(ILB.record(g).E, 60))
    check("10.8 day 74: E = 60", near(ILB.effectiveDay(g, 74), 60))
    check("10.8 day 100: E = 86", near(ILB.effectiveDay(g, 100), 86))
    local h = fakeDef(600, 600)
    local moved = false
    for day = 0, 360, 14 do ILB.touch(h, "enter", 0, day); if ILB.effectiveDay(h, day) ~= 0 then moved = true end end
    check("10.9 visits every 14 days: E never moves", not moved)
    SandboxVars.ImmersiveLootedBuildings.RecentVisitDays = 0
    local z = fakeDef(700, 700)
    ILB.touch(z, "use", 0, 5)
    local e0 = ILB.effectiveDay(z, 50)
    SandboxVars.ImmersiveLootedBuildings.RecentVisitDays = 30
    local w = fakeDef(800, 800)
    ILB.touch(w, "use", 0, 5)
    local e30 = ILB.effectiveDay(w, 50)
    SandboxVars.ImmersiveLootedBuildings.RecentVisitDays = 14
    check("10.12 pause 0: E follows the calendar; pause 30 moves the restart", near(e0, 50) and near(e30, 20), e0 .. " " .. e30)
    -- 10.13: values saved without a sync give the same E after a load
    local s = fakeDef(900, 900)
    ILB.touch(s, "use", 0, 0)
    local saved = {}
    for k2, v in pairs(ILB.record(s)) do saved[k2] = v end
    ILB.data().used[ILB.buildingKey(s)] = saved
    check("10.13 restored record: E = 11 on day 25", near(ILB.effectiveDay(s, 25), 11))
    -- A container in a visited building reads K(E)
    local hd = hitDef("High")
    store = {}
    ILB.data().seed = 424242
    ILB.touch(hd, "use", 0, 0)
    local c = fakeContainer(1000)
    ILB.update(c, hd, "High", 0, "fill", true)
    ILB.update(c, hd, "High", 13, "a")
    local n13 = c:count()
    ILB.update(c, hd, "High", 20, "b")
    check("10.1 nothing lost inside the pause", n13 == 1000)
    check("10.3 day 20 reads K(6), not K(20)", math.abs(c:count() - refK(1, 6, "High") * 1000) <= 3, string.format("%d vs %.1f", c:count(), refK(1, 6, "High") * 1000))
end

-- 5. Options through the functions ----------------------------------------------
do
    local o = SandboxVars.ImmersiveLootedBuildings
    local function curveOk()
        local w = 0
        for t = 0, 800, 0.5 do w = math.max(w, math.abs(ILB.curve(t, "High") - refG(t, "High"))) end
        return w < 1e-9
    end
    local okAll = true
    for _, cfg in ipairs({ { StartDay = 30, PeakDay = 37 }, { PeakDay = 3 }, { PeakDay = 30 }, { EndDay = 100 }, { EndDay = 720 },
        { Slowdown = 1 }, { Slowdown = 20 }, { InitialShare = 25 }, { InitialShare = 100 } }) do
        resetOptions()
        for k, v in pairs(cfg) do o = SandboxVars.ImmersiveLootedBuildings; o[k] = v end
        if not curveOk() then okAll = false end
    end
    resetOptions()
    check("5 curve options follow the formula", okAll)
    o = SandboxVars.ImmersiveLootedBuildings
    o.ExactCurve = "0:0;7:50;30:100"
    local e1, e2 = ILB.curve(3.5, "High"), ILB.curve(18.5, "High")
    o.ExactCurve = "not a curve"
    local e3 = ILB.curve(7, "High")
    o.ExactCurve = "none"
    check("5 exact curve and invalid fallback", near(e1, 0.25) and near(e2, 0.75) and near(e3, refG(7, "High")))
    for _, c in ipairs({ 0, 50, 100 }) do
        o.HighChance = c
        local n = 0
        for i = 1, 10000 do if ILB.isHit(defs[i], "High") then n = n + 1 end end
        check("5 chance " .. c, math.abs(n / 10000 - c / 100) <= 3 * math.sqrt(math.max(c / 100 * (1 - c / 100), 1e-6) / 10000) + 1e-9, tostring(n / 10000))
    end
    resetOptions(); o = SandboxVars.ImmersiveLootedBuildings
    o.HighPeakLoot = 40
    check("5 peak loot 40: hit K(P) = 40", near(refK(1, 7, "High"), 0.40) and near(1 - (1 - ILB.minLoot("High")) * ILB.curve(7, "High"), 0.40))
    o.HighPeakLoot = 20 -- below the minimum 30
    check("5 peak below the minimum: Fp clamped to 1", ILB.peakShare("High") == 1)
    resetOptions(); o = SandboxVars.ImmersiveLootedBuildings
    o.HighMinLoot = 100
    check("5 minimum 100: no loss", ILB.keep(hitDef("High"), "High", 360) == 1)
    resetOptions(); o = SandboxVars.ImmersiveLootedBuildings
    o.LuckyLossMin, o.LuckyLossMax = 0, 0
    check("5 lucky 0-0: lucky buildings lose nothing", ILB.keep(luckyDef("High"), "High", 360) == 1)
    o.LuckyLossMin, o.LuckyLossMax = 100, 100
    check("5 lucky 100-100: same as hit", near(ILB.keep(luckyDef("High"), "High", 360), 0.30))
    o.LuckyLossMin, o.LuckyLossMax = 85, 70
    local lo, hi = ILB.luckyRange()
    check("5 lucky min above max is read in order", near(lo, 0.70) and near(hi, 0.85))
    resetOptions(); o = SandboxVars.ImmersiveLootedBuildings
    o.LowRooms = " movierental , BookStore;typo_room;"
    o.HighRooms = o.HighRooms .. ";toolstore"
    check("5 room lists: add, remove, move, live change", ILB.tierOf("movierental") == "Low" and ILB.tierOf("bookstore") == "Low"
        and ILB.tierOf("toystore") == nil and ILB.tierOf("toolstore") == "High")
    resetOptions()
    check("5 room lists restored", ILB.tierOf("toystore") == "Low" and ILB.tierOf("toolstore") == "Medium")
end

-- 6.1 a game started 3 months after the apocalypse reads day 90 at hour 0
do
    timeSinceApo, worldHours = 4, 0
    check("6.1 TimeSinceApo 4: day() = 90 at the start", near(ILB.day(), 90))
    timeSinceApo = 1
end

-- 11. Signs of a player base (ILB_Base) ----------------------------------------
do
    store = {}
    ILB.data().seed = 424242
    -- A tiny world: one shop building (10x10 at 1000,1000) with a grocery room.
    local objectsAt = {}
    local function mkRoomDef(name, x, y, w, h)
        return { getName = function() return name end, getX = function() return x end, getY = function() return y end,
            getX2 = function() return x + w end, getY2 = function() return y + h end, getZ = function() return 0 end }
    end
    local shopRooms = { mkRoomDef("grocery", 1000, 1000, 10, 10) }
    local shop = { getX = function() return 1000 end, getY = function() return 1000 end, getW = function() return 10 end, getH = function() return 10 end,
        getRooms = function() return { size = function() return #shopRooms end, get = function(_, i) return shopRooms[i + 1] end } end }
    local building = { getDef = function() return shop end }
    local function square(x, y)
        local inside = x >= 1000 and x < 1010 and y >= 1000 and y < 1010
        return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
            getBuilding = function() return inside and building or nil end,
            getObjects = function()
                local list = objectsAt[x .. "," .. y] or {}
                return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
            end }
    end
    getCell = function() return { getGridSquare = function(_, x, y) return square(x, y) end } end
    ILB.shopIndex = function()
        local idx = {}
        for cx = 125, 126 do for cy = 125, 126 do idx[cx .. "," .. cy] = { shop } end end
        return idx
    end
    local realInstanceof = instanceof
    instanceof = function(o, cls) return o.class == cls or (cls == "Key" and o.key == true) end
    dofile(MOD .. "/lua/shared/ImmersiveLootedBuildings/ILB_Base.lua")

    check("11 the shop counts as a shop", ILB.isShop(shop))
    check("11 no record: not a base", not ILB.isBase(ILB.record(shop)))
    -- A barricade the world generator placed is just an object: no action, no sign.
    objectsAt["1001,1001"] = { { class = "IsoBarricade" } }
    check("11 a pre-generated barricade is not a sign", ILB.scanBaseTraces(shop) == nil)
    -- The player barricades a window of the shop (the action handler).
    local window = { getSquare = function() return square(1000, 1005) end, getOppositeSquare = function() return square(999, 1005) end }
    ILB.onPlayerBarricade(window)
    local r = ILB.record(shop)
    check("11 barricading a window of the shop makes it a base", r and r.baseSignal == "barricade" and ILB.isBase(r))
    check("11 a base keeps all its loot", ILB.keep(shop, "High", 360) == nil)
    -- Furniture placed outside the shop does not count; inside it does.
    store = {}; ILB.data().seed = 424242
    ILB.onPlayerPlacedFurniture(square(1020, 1020))
    check("11 furniture placed outside the shop: not a base", not ILB.isBase(ILB.record(shop)))
    ILB.onPlayerPlacedFurniture(square(1003, 1003))
    check("11 furniture placed inside: a base", ILB.record(shop) and ILB.record(shop).baseSignal == "furniture")
    -- Built right against the wall (1 tile) counts; 3 tiles away does not.
    store = {}; ILB.data().seed = 424242
    ILB.onPlayerBuilt(1012, 1005, 0)
    check("11 built 3 tiles away: not a base", not ILB.isBase(ILB.record(shop)))
    ILB.onPlayerBuilt(1010, 1005, 0)
    check("11 built against the wall: a base", ILB.record(shop) and ILB.record(shop).baseSignal == "built")
    -- A generator next to the shop (3 tiles) counts; 6 tiles away does not.
    store = {}; ILB.data().seed = 424242
    ILB.onPlayerGenerator({ getSquare = function() return square(1015, 1005) end })
    check("11 generator 6 tiles away: not a base", not ILB.isBase(ILB.record(shop)))
    ILB.onPlayerGenerator({ getSquare = function() return square(1012, 1005) end })
    check("11 generator 3 tiles away: a base", ILB.record(shop) and ILB.record(shop).baseSignal == "generator")
    -- Traces found at load.
    objectsAt["1002,1002"] = { { class = "IsoGenerator", isActivated = function() return false end } }
    check("11 a generator that is off is not a trace", ILB.scanBaseTraces(shop) == nil)
    objectsAt["1002,1002"] = { { class = "IsoGenerator", isActivated = function() return true end } }
    check("11 a running generator inside is a trace", ILB.scanBaseTraces(shop) == "generator")
    objectsAt["1002,1002"] = { { class = "IsoThumpable", isMovedThumpable = function() return false end } }
    check("11 furniture from the map is not a trace", ILB.scanBaseTraces(shop) == nil)
    objectsAt["1002,1002"] = { { class = "IsoThumpable", isMovedThumpable = function() return true end } }
    check("11 furniture moved by a player is a trace", ILB.scanBaseTraces(shop) == "furniture")
    -- The sign is permanent and keeps its first reason.
    ILB.markBase(shop, "built")
    check("11 the base sign keeps its first reason", ILB.record(shop).baseSignal == "generator")
    -- A shop only visited: not a base, loses loot after the pause.
    store = {}; ILB.data().seed = 424242
    ILB.touch(shop, "enter", 0, 0)
    check("11 only visited: not a base, loses loot after the pause", not ILB.isBase(ILB.record(shop)) and ILB.keep(shop, "High", 100) < 1)
    instanceof = realInstanceof
end

print(string.format("DONE pass=%d fail=%d", pass, fail))
os.exit(fail == 0 and 0 or 1)
