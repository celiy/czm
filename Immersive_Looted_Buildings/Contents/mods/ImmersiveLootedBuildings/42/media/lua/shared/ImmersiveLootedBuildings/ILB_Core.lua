--[[
    Immersive Looted Buildings - core (design v2: gradual loot loss)

    Every shop building loses loot gradually. For a tier with chance C, a
    building is in the "hit" group when its permanent random number u1 < C:
    it follows the full loss curve down to the tier's minimum loot. The other
    buildings ("lucky") lose a share s of that loss, fixed per building,
    between LuckyLossMin and LuckyLossMax. The loot a building keeps on
    effective day e is

        K(e) = 1 - s x (1 - MinLoot) x g(e)

    where g is the share of the final loss done by day e (the v1 curve, with
    the share at the peak derived from the tier's peak and minimum loot).

    Each container keeps A, the share of its original loot already kept.
    An update removes the share 1 - K / A of its removable items and sets
    A = K. See DESIGN.md.
]]

ImmersiveLootedBuildings = ImmersiveLootedBuildings or {}
local ILB = ImmersiveLootedBuildings

ILB.TAG = "ILB_player"   -- item mod data key: put there by the player
ILB.MODDATA = "ImmersiveLootedBuildings"
ILB.SKIPPED = -1         -- container state of a building the game itself looted

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

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
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
    local trimmed = s:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" or trimmed:lower() == "none" then return nil end
    local pts = {}
    for d, p in string.gmatch(s, "(%-?[%d%.]+)%s*:%s*([%d%.]+)") do
        local dn, pn = tonumber(d), tonumber(p)
        if dn and pn then pts[#pts + 1] = { dn, clamp01(pn / 100) } end
    end
    if #pts == 0 then
        print("[ImmersiveLootedBuildings] exact curve '" .. s .. "' has no day:percent points, using the formula")
        return nil
    end
    table.sort(pts, function(a, b) return a[1] < b[1] end)
    return pts
end

-- Parsed once, and again when one of these option values changes.
local CFG_FIELDS = { "HighRooms", "MediumRooms", "LowRooms", "OverrunRooms", "ExactCurve" }
local cfg, cfgSeen = nil, {}
function ILB.config()
    local o = opts()
    if cfg then
        local same = true
        for _, f in ipairs(CFG_FIELDS) do
            if cfgSeen[f] ~= o[f] then same = false break end
        end
        if same then return cfg end
    end
    for _, f in ipairs(CFG_FIELDS) do cfgSeen[f] = o[f] end
    local rooms = {}
    -- The first list wins when a room is in two lists.
    parseRooms(o.HighRooms, rooms, "High")
    parseRooms(o.MediumRooms, rooms, "Medium")
    parseRooms(o.LowRooms, rooms, "Low")
    parseRooms(o.OverrunRooms, rooms, "Overrun")
    cfg = { rooms = rooms, curve = parseCurve(o.ExactCurve) }
    ILB.version = (ILB.version or 0) + 1 -- room lists changed: building indexes rebuild
    return cfg
end

function ILB.tierOf(roomName)
    if not roomName then return nil end
    return ILB.config().rooms[string.lower(tostring(roomName))]
end

function ILB.isLossTier(tier)
    return tier == "High" or tier == "Medium" or tier == "Low"
end

----------------------------------------------------------------------------
-- Time and the loss curve
----------------------------------------------------------------------------

-- Days since the apocalypse (same rule as Perishable Foods).
function ILB.day()
    return getGameTime():getWorldAgeHours() / 24 + (getSandboxOptions():getTimeSinceApo() - 1) * 30
end

function ILB.chance(tier) return clamp01((ILB.opt(tier .. "Chance", 0) or 0) / 100) end
function ILB.minLoot(tier) return clamp01((ILB.opt(tier .. "MinLoot", 100) or 100) / 100) end
function ILB.peakLoot(tier) return clamp01((ILB.opt(tier .. "PeakLoot", 100) or 100) / 100) end

-- Share of the final loss done at the peak: (1 - PeakLoot) / (1 - MinLoot).
function ILB.peakShare(tier)
    local m = ILB.minLoot(tier)
    if m >= 1 then return 1 end
    return clamp01((1 - ILB.peakLoot(tier)) / (1 - m))
end

local function baseCurve(t, S, P, E, Fp, k)
    if t <= S then return 0 end
    if t >= E then return 1 end
    if t < P then
        if P <= S then return Fp end
        return Fp * (t - S) / (P - S)
    end
    if E <= P then return 1 end
    local x = (t - P) / (E - P)
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

-- g(t): share of the final loss done by (effective) day t, for a tier.
function ILB.curve(t, tier)
    local c = ILB.config()
    if c.curve then return exactCurve(t, c.curve) end
    local S = ILB.opt("StartDay", 0)
    if t < S then return 0 end
    local P = math.max(S, ILB.opt("PeakDay", 7))
    local E = math.max(P, ILB.opt("EndDay", 360))
    local k = ILB.opt("Slowdown", 6.4)
    local I = clamp01(ILB.opt("InitialShare", 0) / 100)
    return I + (1 - I) * baseCurve(t, S, P, E, ILB.peakShare(tier or "High"), k)
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

ILB.SALT = { GROUP = 1, STRENGTH = 2 }

function ILB.buildingKey(def)
    return tostring(def:getX()) .. "_" .. tostring(def:getY())
end

function ILB.buildingU(def, salt)
    return ILB.hash(def:getX(), def:getY(), ILB.data().seed, salt or ILB.SALT.GROUP)
end

function ILB.isHit(def, tier)
    return ILB.buildingU(def, ILB.SALT.GROUP) < ILB.chance(tier)
end

function ILB.luckyRange()
    local lo = clamp01(ILB.opt("LuckyLossMin", 70) / 100)
    local hi = clamp01(ILB.opt("LuckyLossMax", 85) / 100)
    if lo > hi then lo, hi = hi, lo end
    return lo, hi
end

-- Loss strength: 1 for the hit group, otherwise inside the lucky range.
function ILB.strength(def, tier)
    if ILB.isHit(def, tier) then return 1 end
    local lo, hi = ILB.luckyRange()
    return lo + (hi - lo) * ILB.buildingU(def, ILB.SALT.STRENGTH)
end

----------------------------------------------------------------------------
-- Activity record: bases and the recent-visit loss clock
----------------------------------------------------------------------------

function ILB.record(def)
    return ILB.data().used[ILB.buildingKey(def)]
end

-- A base: a sign the player lives there (ILB_Base: barricades, furniture,
-- building, generator), or enough items stored, or enough days of use.
function ILB.isBase(r)
    if not r then return false end
    if r.baseSignal then return true end
    return (r.stored or 0) >= ILB.opt("BaseItems", 3) or (r.days or 0) >= ILB.opt("BaseActiveDays", 3)
end

-- Bring the effective day E up to calendar day t: only the days after the
-- recent-visit window count.
function ILB.sync(r, t)
    if r.E == nil then -- a record from v1: the clock paused at its last activity
        r.E = r.last or t
        r.S = r.last or t
    end
    local from = math.max(r.S, (r.last or r.S) + ILB.opt("RecentVisitDays", 14))
    if t > from then r.E = r.E + (t - from) end
    if t > r.S then r.S = t end
    return r.E
end

-- A visit on day t. kind "enter" counts only for the recent-visit pause;
-- "use" (a container looked at, an item moved) also counts a day of activity.
function ILB.touch(def, kind, stored, t)
    local used = ILB.data().used
    local key = ILB.buildingKey(def)
    t = t or ILB.day()
    local r = used[key]
    if not r then
        r = { E = t, S = t, last = t, days = 0, stored = 0 }
        used[key] = r
    else
        ILB.sync(r, t)
        if t > (r.last or t) then r.last = t end
    end
    if kind == "use" then
        local today = math.floor(t)
        if r.lastUseDay ~= today then
            r.days = (r.days or 0) + 1
            r.lastUseDay = today
        end
    end
    if stored and stored > 0 then r.stored = (r.stored or 0) + stored end
    return r
end

-- Effective day of a building on calendar day t (the calendar day if never visited).
function ILB.effectiveDay(def, t)
    local r = ILB.record(def)
    if not r then return t end
    return ILB.sync(r, t)
end

-- Loot the building keeps on day t, or nil for a base (never loses loot).
function ILB.keep(def, tier, t)
    local r = ILB.record(def)
    if ILB.isBase(r) then return nil end
    local e = r and ILB.sync(r, t) or t
    return 1 - ILB.strength(def, tier) * (1 - ILB.minLoot(tier)) * ILB.curve(e, tier)
end

----------------------------------------------------------------------------
-- Containers
----------------------------------------------------------------------------

local function keyA(c) return "ILB2_" .. tostring(c:getType()) end
local function keyD(c) return "ILB2d_" .. tostring(c:getType()) end

-- A (share kept) and the day of the last update, or nil if the mod never
-- updated this container. A is ILB.SKIPPED for a game-looted building.
function ILB.getState(container)
    local obj = container:getParent()
    if not obj then return nil end
    local md = obj:getModData()
    local a = md[keyA(container)]
    if a == nil then
        -- v1 left "ILB_<type>" = state * 100000 + day; state 2 = game looted.
        local v1 = md["ILB_" .. tostring(container:getType())]
        if type(v1) == "number" and math.floor(v1 / 100000) == 2 then return ILB.SKIPPED, 0 end
        return nil
    end
    return a, md[keyD(container)] or 0
end

function ILB.setState(container, a, day)
    local obj = container:getParent()
    if not obj then return end
    local md = obj:getModData()
    md[keyA(container)] = a
    md[keyD(container)] = math.floor(day or 0)
    if isServer() then obj:transmitModData() end
end

-- Building, room name and square of a world container, or nil.
function ILB.locate(container)
    local obj = container and container:getParent()
    local sq = obj and obj:getSquare()
    if not sq then return nil end
    local building = sq:getBuilding()
    local def = building and building:getDef()
    if not def then return nil end
    local room = sq:getRoom()
    return def, room and room:getName(), sq
end

-- A building the game itself turned into a looted / trashed building: all
-- explored, but no player has been inside. Only meaningful once loaded.
function ILB.isVanillaLooted(def)
    return def:isAllExplored() and not def:isHasBeenVisited()
end

local USEFUL = {
    Food = true, FirstAid = true, Bandage = true, Medical = true, Weapon = true, WeaponCrafted = true, Ammo = true,
    Tool = true, ToolWeapon = true, WaterContainer = true, Cooking = true, CookingWeapon = true, Electronics = true,
    LightSource = true, Camping = true, Fishing = true, Gardening = true, GardeningWeapon = true, Bag = true,
    Container = true, Explosives = true, VehicleMaintenance = true, Material = true,
}

function ILB.isProtected(item)
    if instanceof(item, "Key") then return true end
    local md = item:hasModData() and item:getModData()
    return (md and md[ILB.TAG] == true) or false
end

-- By display category. The plain category is too broad (a pencil is a "Weapon").
function ILB.isUseful(item)
    local ok, cat = pcall(function() return item:getDisplayCategory() end)
    if ok and cat then return USEFUL[cat] == true end
    return USEFUL[item:getCategory()] == true
end

-- Remove on average the share r of the container's removable items, rounding
-- randomly. Returns removed, considered.
function ILB.cutContainer(container, r)
    if r <= 0 then return 0, 0 end
    local items = container:getItems()
    local list = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not ILB.isProtected(it) then list[#list + 1] = it end
    end
    local n = #list
    if n == 0 then return 0, 0 end
    local target = n * math.min(1, r)
    local k = math.floor(target)
    if ZombRandFloat(0, 1) < target - k then k = k + 1 end
    if k <= 0 then return 0, n end
    for i = n, 2, -1 do
        local j = ZombRand(i) + 1
        list[i], list[j] = list[j], list[i]
    end
    if ILB.opt("UsefulFirst", false) then
        local useful, rest = {}, {}
        for _, it in ipairs(list) do
            if ILB.isUseful(it) then useful[#useful + 1] = it else rest[#rest + 1] = it end
        end
        list = useful
        for _, it in ipairs(rest) do list[#list + 1] = it end
    end
    k = math.min(k, n)
    for i = 1, k do
        local it = list[i]
        container:DoRemoveItem(it)
        if isServer() then sendRemoveItemFromContainer(container, it) end
    end
    local obj = container:getParent()
    if obj and ItemPicker and ItemPicker.updateOverlaySprite then pcall(ItemPicker.updateOverlaySprite, obj) end
    return k, n
end

-- Overrun bonus: copies of existing items, on average "bonus" extra per item.
function ILB.bonusContainer(container, bonus)
    if bonus <= 0 then return 0 end
    local items = container:getItems()
    local types = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not ILB.isProtected(it) then types[#types + 1] = it:getFullType() end
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
-- Updates
----------------------------------------------------------------------------

ILB.stats = { updates = 0, removed = 0, considered = 0, bonus = 0, skippedVanilla = 0, deferred = 0, byTier = {} }

local function log(fmt, ...)
    if ILB.opt("LogDecisions", false) then print("[ImmersiveLootedBuildings] " .. string.format(fmt, ...)) end
end
ILB.log = log

-- Bring a loss-tier container to the building's loot on day t. Returns
-- removed, considered, or nil when nothing was done (base, skipped, already
-- updated today). fresh: the contents were just created (fill or refill), so
-- A starts again at 1 and the once-a-day rule does not apply.
function ILB.update(container, def, tier, t, why, fresh)
    t = t or ILB.day()
    local a, lastDay = ILB.getState(container)
    if a == ILB.SKIPPED then return nil end
    local k = ILB.keep(def, tier, t)
    if k == nil then return nil end -- a base never loses loot
    if fresh then
        a = 1
    elseif a ~= nil and lastDay >= math.floor(t) then
        return nil -- at most once per in-game day
    end
    a = a or 1
    local removed, considered = 0, 0
    if k < a - 1e-9 then
        removed, considered = ILB.cutContainer(container, 1 - k / a)
        a = k
    end
    ILB.setState(container, a, t)
    local st = ILB.stats
    st.updates = st.updates + 1
    st.removed = st.removed + removed
    st.considered = st.considered + considered
    local bt = st.byTier[tier]
    if not bt then bt = { updates = 0, removed = 0, considered = 0 }; st.byTier[tier] = bt end
    bt.updates = bt.updates + 1
    bt.removed = bt.removed + removed
    bt.considered = bt.considered + considered
    log("%s %s tier %s day %.2f keep %.4f removed %d of %d", why or "update", ILB.buildingKey(def), tier, t, a, removed, considered)
    return removed, considered
end

-- Would this container lose items if it were updated on day t?
function ILB.isDue(container, def, tier, t)
    local a = ILB.getState(container)
    if a == ILB.SKIPPED then return false end
    local k = ILB.keep(def, tier, t or ILB.day())
    if k == nil then return false end
    return k < (a or 1) - 1e-9
end

-- Every container in the tier rooms of a building, on loaded squares.
-- fn(container, tier, square) for each.
function ILB.forEachContainer(def, fn)
    local rooms = def:getRooms()
    local cell = getCell()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local tier = ILB.tierOf(rd:getName())
        if tier then
            local z = rd:getZ()
            for x = rd:getX(), rd:getX2() - 1 do
                for y = rd:getY(), rd:getY2() - 1 do
                    local sq = cell:getGridSquare(x, y, z)
                    local room = sq and sq:getRoom()
                    if room and room:getRoomDef() == rd then
                        local objs = sq:getObjects()
                        for oi = 0, objs:size() - 1 do
                            local obj = objs:get(oi)
                            for ci = 0, obj:getContainerCount() - 1 do
                                fn(obj:getContainerByIndex(ci), tier, sq)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Does this building have a loss-tier room?
local shopCache, shopCacheVersion = {}, nil
function ILB.isShop(def)
    ILB.config()
    if shopCacheVersion ~= ILB.version then shopCache = {}; shopCacheVersion = ILB.version end
    local key = ILB.buildingKey(def)
    local v = shopCache[key]
    if v == nil then
        v = false
        local rooms = def:getRooms()
        for i = 0, rooms:size() - 1 do
            if ILB.isLossTier(ILB.tierOf(rooms:get(i):getName())) then v = true break end
        end
        shopCache[key] = v
    end
    return v
end

----------------------------------------------------------------------------
-- Never in front of the player
----------------------------------------------------------------------------

-- In memory only: buildings whose containers a player has looked at since
-- they were last loaded, and buildings with a removal that had to wait.
ILB.seen = ILB.seen or {}
ILB.deferred = ILB.deferred or {}

-- Distance in tiles from (x, y) to the building's rectangle.
function ILB.distanceTo(def, x, y)
    local x1, y1 = def:getX(), def:getY()
    local x2, y2 = x1 + def:getW() - 1, y1 + def:getH() - 1
    local dx = (x < x1 and x1 - x) or (x > x2 and x - x2) or 0
    local dy = (y < y1 and y1 - y) or (y > y2 and y - y2) or 0
    return math.sqrt(dx * dx + dy * dy)
end

-- The players whose view matters: local players, or every player on a server.
function ILB.players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        if list then for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then out[#out + 1] = p end
        end
    end
    return out
end

function ILB.playerNear(def)
    local r = ILB.opt("ProtectRadius", 200)
    for _, p in ipairs(ILB.players()) do
        if ILB.distanceTo(def, p:getX(), p:getY()) <= r then return true end
    end
    return false
end

-- May the mod remove items of this building now? Right after the building
-- was loaded nobody has seen it yet; after that, not while a player is near
-- or has looked at its containers.
function ILB.mayRemove(def, freshLoad)
    local key = ILB.buildingKey(def)
    if ILB.seen[key] then return false end
    if freshLoad then return true end
    return not ILB.playerNear(def)
end
