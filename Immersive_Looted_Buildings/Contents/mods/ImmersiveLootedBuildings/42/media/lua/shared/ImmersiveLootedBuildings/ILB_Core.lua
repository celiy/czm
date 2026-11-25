--[[
    Immersive Looted Buildings - core

    Each building gets a permanent random number u in [0, 1) from its map
    position and a seed saved with the world. A building is looted on day t,
    for a tier with final chance C, when u < C x f(t), where f is the share of
    the final looting done by day t (see DESIGN.md). Looted buildings lose a
    share ("cut") of the items in their tier rooms. Nothing is stored per
    building except for buildings the player used (the activity record).

    Container states, kept in the parent object's mod data per container type:
      nil  never seen by the mod (filled before the mod was added)
      0    checked, not looted at that time (may still be cut later)
      1    cut applied (never cut again)
      2    skipped for good (a building the game itself looted)
]]

ImmersiveLootedBuildings = ImmersiveLootedBuildings or {}
local ILB = ImmersiveLootedBuildings

ILB.TAG = "ILB_player"          -- item mod data key: put there by the player
ILB.MODDATA = "ImmersiveLootedBuildings"
ILB.STATE = { CHECKED = 0, CUT = 1, SKIP = 2 }


----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

local function opts()
    return SandboxVars.ImmersiveLootedBuildings or {}
end

function ILB.opt(name, default)
    local v = opts()[name]
    if v == nil then return default end
    return v
end

function ILB.isEnabled()
    return ILB.opt("Enabled", true) == true
end

local function parseRooms(s, out, tier)
    if type(s) ~= "string" then return end
    for raw in string.gmatch(s, "[^;,]+") do
        local name = string.lower((raw:gsub("^%s+", ""):gsub("%s+$", "")))
        if name ~= "" and name ~= "none" and out[name] == nil then out[name] = tier end
    end
end

local function parseCurve(s)
    if type(s) ~= "string" then return nil end
    local pts = {}
    for d, p in string.gmatch(s, "(%-?[%d%.]+)%s*:%s*([%d%.]+)") do
        pts[#pts + 1] = { tonumber(d), math.max(0, math.min(100, tonumber(p))) / 100 }
    end
    if #pts == 0 then return nil end
    table.sort(pts, function(a, b) return a[1] < b[1] end)
    return pts
end

-- Built once and again whenever the sandbox values change (cheap: a few
-- string splits). The key avoids re-parsing on every call.
local CFG_FIELDS = { "HighRooms", "MediumRooms", "LowRooms", "OverrunRooms", "ExactCurve" }
local cfg, cfgSeen = nil, {}
function ILB.config()
    local o = opts()
    if cfg then
        -- Unchanged option values are the same string objects: no allocation here.
        local same = true
        for _, f in ipairs(CFG_FIELDS) do
            if cfgSeen[f] ~= o[f] then same = false break end
        end
        if same then return cfg end
    end
    for _, f in ipairs(CFG_FIELDS) do cfgSeen[f] = o[f] end
    local rooms = {}
    -- First list wins when a room is in two lists.
    parseRooms(o.HighRooms, rooms, "High")
    parseRooms(o.MediumRooms, rooms, "Medium")
    parseRooms(o.LowRooms, rooms, "Low")
    parseRooms(o.OverrunRooms, rooms, "Overrun")
    cfg = { rooms = rooms, curve = parseCurve(o.ExactCurve) }
    return cfg
end

function ILB.tierOf(roomName)
    if not roomName then return nil end
    return ILB.config().rooms[string.lower(tostring(roomName))]
end

function ILB.tierChance(tier)
    return (ILB.opt(tier .. "Chance", 0) or 0) / 100
end

function ILB.tierCut(tier)
    return (ILB.opt(tier .. "Cut", 0) or 0) / 100
end

----------------------------------------------------------------------------
-- Time and the looting curve
----------------------------------------------------------------------------

-- Days since the apocalypse (same rule as Perishable Foods).
function ILB.day()
    return getGameTime():getWorldAgeHours() / 24 + (getSandboxOptions():getTimeSinceApo() - 1) * 30
end

-- Base curve g(t) in [0, 1]: linear to Fp at the peak, then slowing down.
local function baseCurve(t, S, P, E, Fp, k)
    if t <= S then return 0 end
    if t >= E then return 1 end
    if P > S and t < P then return Fp * (t - S) / (P - S) end
    if E <= P then return 1 end
    local x = (math.max(t, P) - P) / (E - P)
    local denom = 1 - math.exp(-k)
    if denom <= 0 then return Fp + (1 - Fp) * x end
    return Fp + (1 - Fp) * (1 - math.exp(-k * x)) / denom
end

local function exactCurve(t, pts)
    if t <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if t <= b[1] then
            if b[1] == a[1] then return b[2] end
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return pts[#pts][2]
end

-- f(t): share of the final looting done by day t.
function ILB.curve(t, tier)
    local c = ILB.config()
    if c.curve then return exactCurve(t, c.curve) end
    local S = ILB.opt("StartDay", 0)
    local P = math.max(S, ILB.opt("PeakDay", 7))
    local E = math.max(P, ILB.opt("EndDay", 360))
    local Fp = ILB.opt((tier or "High") .. "PeakShare", 50) / 100
    local k = ILB.opt("Slowdown", 6.4)
    local I = ILB.opt("InitialShare", 0) / 100
    local g = baseCurve(t, S, P, E, Fp, k)
    if t < S then return 0 end
    return I + (1 - I) * g
end

----------------------------------------------------------------------------
-- Seed and per-building random numbers
----------------------------------------------------------------------------

function ILB.data()
    local d = ModData.getOrCreate(ILB.MODDATA)
    if not d.seed then d.seed = ZombRand(1, 1000000000) end
    d.used = d.used or {}
    return d
end

-- Deterministic hash of (x, y, seed, salt) to [0, 1). Plain arithmetic only
-- (no bit library), every product stays below 2^53.
-- 32-bit helpers on plain numbers (the game's Lua has no bit library).
local TWO32 = 4294967296
local function bxor(a, b)
    local r, bit = 0, 1
    for _ = 1, 32 do
        local x, y = a % 2, b % 2
        if x ~= y then r = r + bit end
        a, b, bit = (a - x) / 2, (b - y) / 2, bit * 2
    end
    return r
end
local function mul32(a, b)
    local alo, ahi = a % 65536, math.floor(a / 65536)
    return (alo * b + ((ahi * b) % 65536) * 65536) % TWO32
end
-- MurmurHash3 finalizer: every input bit affects every output bit.
local function fmix(h)
    h = bxor(h, math.floor(h / 65536))
    h = mul32(h, 0x85ebca6b)
    h = bxor(h, math.floor(h / 8192))
    h = mul32(h, 0xc2b2ae35)
    h = bxor(h, math.floor(h / 65536))
    return h
end

local uCache = {}
function ILB.hash(x, y, seed, salt)
    local key = x .. "," .. y .. "," .. seed .. "," .. (salt or 0)
    local u = uCache[key]
    if u then return u end
    local h = fmix(seed % TWO32)
    h = fmix((h + math.floor(x) * 0x9e3779b1) % TWO32)
    h = fmix((h + math.floor(y) * 0x85ebca77) % TWO32)
    h = fmix((h + (salt or 0) * 0x27d4eb2f + 1) % TWO32)
    u = h / TWO32
    uCache[key] = u
    return u
end

ILB.SALT = { LOOTED = 1, VARIATION = 2, STRIPPED = 3 }

function ILB.buildingKey(def)
    return tostring(def:getX()) .. "_" .. tostring(def:getY())
end

function ILB.buildingU(def, salt)
    return ILB.hash(def:getX(), def:getY(), ILB.data().seed, salt or ILB.SALT.LOOTED)
end

----------------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------------

-- The game's own looted chance for this building (0..1), or 0 when the game
-- would not loot it (too many rooms).
function ILB.vanillaShare(def, square)
    if not ILB.opt("CountVanillaLooted", true) then return 0 end
    local maxRooms = SandboxVars.MaximumLootedBuildingRooms
    if maxRooms and def:getRooms():size() > maxRooms then return 0 end
    local ok, chance = pcall(function() return getSandboxOptions():getCurrentLootedChance(square) end)
    if not ok or not chance then return 0 end
    return math.max(0, math.min(1, chance / 100))
end

-- The threshold u is compared with: C x f(t), corrected for the share the
-- game already looted so the total equals the tier curve.
function ILB.threshold(tier, day, def, square)
    local target = ILB.tierChance(tier) * ILB.curve(day, tier)
    local v = (def and square) and ILB.vanillaShare(def, square) or 0
    if v <= 0 then return target end
    if v >= 1 then return 0 end
    return math.max(0, (target - v) / (1 - v))
end

function ILB.isLooted(def, tier, day, square)
    if tier == "Overrun" then return false end
    return ILB.buildingU(def) < ILB.threshold(tier, day, def, square)
end

-- Cut for this building: tier cut, varied per building, or 1 when stripped.
function ILB.cutFor(def, tier)
    local cut = ILB.tierCut(tier)
    local stripped = ILB.opt("StrippedChance", 0) / 100
    if stripped > 0 and ILB.buildingU(def, ILB.SALT.STRIPPED) < stripped then return 1 end
    local var = ILB.opt("CutVariation", 0) / 100
    if var > 0 then
        cut = cut + (ILB.buildingU(def, ILB.SALT.VARIATION) * 2 - 1) * var
    end
    return math.max(0, math.min(1, cut))
end

----------------------------------------------------------------------------
-- Container helpers
----------------------------------------------------------------------------

local function stateKey(container)
    return "ILB_" .. tostring(container:getType())
end

function ILB.getState(container)
    local obj = container:getParent()
    if not obj then return nil end
    local md = obj:getModData()
    local s = md[stateKey(container)]
    if s == nil then return nil end
    return math.floor(s / 100000), s % 100000
end

function ILB.setState(container, state, day)
    local obj = container:getParent()
    if not obj then return end
    obj:getModData()[stateKey(container)] = state * 100000 + math.max(0, math.min(99999, math.floor(day or 0)))
    if isServer() then obj:transmitModData() end
end

-- Building and room of a world container, or nil.
function ILB.locate(container)
    local obj = container and container:getParent()
    local sq = obj and obj:getSquare()
    if not sq then return nil end
    local building = sq:getBuilding()
    local def = building and building:getDef()
    if not def then return nil end
    local room = sq:getRoom()
    local name = room and room:getName()
    return def, name, sq
end

-- A building the game itself turned into a looted / trashed building: all
-- explored, but no player has been inside. Only meaningful right after a fill.
function ILB.isVanillaLooted(def)
    return def:isAllExplored() and not def:isHasBeenVisited()
end

local USEFUL = {
    Food = true, FirstAid = true, Bandage = true, Medical = true, Weapon = true, WeaponCrafted = true, Ammo = true,
    Tool = true, ToolWeapon = true, WaterContainer = true, Cooking = true, CookingWeapon = true, Electronics = true,
    LightSource = true, Camping = true, Fishing = true, Gardening = true, GardeningWeapon = true, Bag = true,
    Container = true, Explosives = true, VehicleMaintenance = true, Material = true,
}

local function isProtected(item)
    if instanceof(item, "Key") then return true end
    local md = item:hasModData() and item:getModData()
    return md and md[ILB.TAG] == true
end

-- By display category (Food, FirstAid, Tool...). The plain category is too
-- broad: a pencil is a "Weapon" there.
local function isUseful(item)
    local ok, cat = pcall(function() return item:getDisplayCategory() end)
    if ok and cat then return USEFUL[cat] == true end
    return USEFUL[item:getCategory()] == true
end

-- Remove on average share "cut" of the container's removable items, rounding
-- randomly. Returns removed, considered.
function ILB.cutContainer(container, cut)
    if cut <= 0 then return 0, 0 end
    local items = container:getItems()
    local list = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not isProtected(it) then list[#list + 1] = it end
    end
    local n = #list
    if n == 0 then return 0, 0 end
    local target = n * cut
    local k = math.floor(target)
    if ZombRandFloat(0, 1) < target - k then k = k + 1 end
    if k <= 0 then return 0, n end
    -- Random order (Fisher-Yates), then useful items first if asked.
    for i = n, 2, -1 do
        local j = ZombRand(i) + 1
        list[i], list[j] = list[j], list[i]
    end
    if ILB.opt("UsefulFirst", false) then
        local useful, rest = {}, {}
        for _, it in ipairs(list) do
            if isUseful(it) then useful[#useful + 1] = it else rest[#rest + 1] = it end
        end
        list = useful
        for _, it in ipairs(rest) do list[#list + 1] = it end
    end
    for i = 1, math.min(k, n) do
        local it = list[i]
        container:DoRemoveItem(it)
        if isServer() then sendRemoveItemFromContainer(container, it) end
    end
    local obj = container:getParent()
    if obj and ItemPicker and ItemPicker.updateOverlaySprite then pcall(ItemPicker.updateOverlaySprite, obj) end
    return math.min(k, n), n
end

-- Overrun bonus: copies of existing items, on average "bonus" extra per item.
function ILB.bonusContainer(container, bonus)
    if bonus <= 0 then return 0 end
    local items = container:getItems()
    local types = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not isProtected(it) then types[#types + 1] = it:getFullType() end
    end
    local added = 0
    for _, ft in ipairs(types) do
        local copies = math.floor(bonus)
        if ZombRandFloat(0, 1) < bonus - copies then copies = copies + 1 end
        for _ = 1, copies do
            local it = container:AddItem(ft)
            if it then
                added = added + 1
                if isServer() then sendAddItemToContainer(container, it) end
            end
        end
    end
    return added
end

----------------------------------------------------------------------------
-- Activity record (buildings the player used)
----------------------------------------------------------------------------

-- Record activity in a building today. stored = items put in (0 or more).
function ILB.touch(def, stored)
    local used = ILB.data().used
    local key = ILB.buildingKey(def)
    local now = ILB.day()
    local r = used[key]
    if not r then
        r = { last = now, days = 1, stored = 0 }
        used[key] = r
    elseif math.floor(r.last) < math.floor(now) then
        r.before = r.last
        r.days = (r.days or 0) + 1
        r.last = now
    else
        r.last = math.max(r.last, now)
    end
    if stored and stored > 0 then r.stored = (r.stored or 0) + stored end
    return r
end

function ILB.record(def)
    return ILB.data().used[ILB.buildingKey(def)]
end

function ILB.isBase(r)
    return (r.stored or 0) >= ILB.opt("BaseItems", 3) or (r.days or 0) >= ILB.opt("BaseActiveDays", 3)
end

-- May the mod change containers of this building now? Untouched buildings
-- yes; used buildings only once abandoned (window passed since the last
-- activity before today) and if cutting abandoned buildings is on.
function ILB.mayChange(def, now)
    local r = ILB.record(def)
    if not r then return true, "untouched" end
    now = now or ILB.day()
    local ref = r.last
    if math.floor(r.last) >= math.floor(now) then
        ref = r.before
        if not ref then return true, "first-day" end -- record made today: still untouched
    end
    local base = ILB.isBase(r)
    local window = base and ILB.opt("BaseDays", 60) or ILB.opt("PassingDays", 30)
    if now - ref < window then return false, base and "base" or "passing" end
    if not ILB.opt("CutAbandoned", true) then return false, "abandoned-kept" end
    return true, "abandoned"
end

----------------------------------------------------------------------------
-- Applying the decision to one container
----------------------------------------------------------------------------

ILB.stats = { cut = 0, checked = 0, skippedVanilla = 0, bonus = 0, removed = 0, byTier = {} }

local logged = {}
local function log(def, tier, day, looted, why, square)
    if not ILB.opt("LogDecisions", false) then return end
    local key = ILB.buildingKey(def) .. tier .. (looted and "L" or "N") .. why
    if logged[key] then return end
    logged[key] = true
    print(string.format("[ImmersiveLootedBuildings] building %s tier %s day %.1f u=%.4f threshold=%.4f looted=%s (%s)",
        ILB.buildingKey(def), tier, day, ILB.buildingU(def), ILB.threshold(tier, day, def, square), tostring(looted), why))
end

-- Apply today's decision to a container in a tier room. Returns what was done.
function ILB.apply(container, def, tier, square, why)
    local day = ILB.day()
    if tier == "Overrun" then
        local bonus = ILB.opt("OverrunBonus", 25) / 100
        local added = ILB.bonusContainer(container, bonus)
        ILB.stats.bonus = ILB.stats.bonus + added
        ILB.setState(container, ILB.STATE.CHECKED, day)
        return "bonus", added
    end
    local looted = ILB.isLooted(def, tier, day, square)
    log(def, tier, day, looted, why or "fill", square)
    -- Per-tier counters (read by the tests and handy for debugging).
    local t = ILB.stats.byTier[tier]
    if not t then
        t = { containers = 0, looted = 0, items = 0, lootedItems = 0, removed = 0 }
        ILB.stats.byTier[tier] = t
    end
    t.containers = t.containers + 1
    local n = container:getItems():size()
    t.items = t.items + n
    if looted then
        t.lootedItems = t.lootedItems + n
        local removed = ILB.cutContainer(container, ILB.cutFor(def, tier))
        ILB.stats.cut = ILB.stats.cut + 1
        ILB.stats.removed = ILB.stats.removed + removed
        t.looted = t.looted + 1
        t.removed = t.removed + removed
        ILB.setState(container, ILB.STATE.CUT, day)
        return "cut", removed
    end
    ILB.stats.checked = ILB.stats.checked + 1
    ILB.setState(container, ILB.STATE.CHECKED, day)
    return "checked", 0
end
