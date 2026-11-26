--[[
    CZM Auto Test - Perishable Foods: Vanilla Foods Expanded add-on (development only).
    Needs the Workshop mod Vanilla Foods Expanded (CZM_TEST_EXTERNAL=VanillaFoodsExpanded) and the
    mods PerishableFoods and PerishableFoodsVFX. Suite: pfvfx.
]]

CZM_TEST_SUITES = CZM_TEST_SUITES or {}

local FOOD_ROOMS = { grocery = true, generalstore = true, conveniencestore = true, cornerstore = true, gigamart = true,
    departmentstore = true, bakery = true, candystore = true, liquorstore = true, pharmacy = true, grocerystorage = true,
    generalstorestorage = true, cornerstorestorage = true, departmentstorage = true }

local function fluidName(item)
    local fc = item:getFluidContainerFromSelfOrWorldItem()
    return fc and fc:getPrimaryFluid() and tostring(fc:getPrimaryFluid():getFluidTypeString()) or "-"
end

CZM_TEST_SUITES.pfvfx = function(t)
    local PF = PerishableFoods
    local VFX = PerishableFoodsVFX
    local check = t.check
    local ctx = {}
    local function scriptOf(full) return getScriptManager():getItem(full) end

    -- 1. the add-on and the data ------------------------------------------------
    t.queue(1, function()
        check("add-on loaded", VFX ~= nil and VFX.FOODS ~= nil and VFX.DRINKS ~= nil and VFX.addedFoods ~= nil)
        check("Vanilla Foods Expanded is loaded", scriptOf("VFX.Allspice") ~= nil)
        local nFoods, nDrinks = #VFX.FOODS, 0
        for _ in pairs(VFX.DRINKS) do nDrinks = nDrinks + 1 end
        check("the add-on's foods were added to the main mod's table", VFX.addedFoods == nFoods and #PF.SCHEDULE >= 116 + nFoods, string.format("%d added, %d in table", VFX.addedFoods, #PF.SCHEDULE))
        check("the add-on's drinks were added to the main mod's table", VFX.addedDrinks == nDrinks, string.format("%d", VFX.addedDrinks))
        print(string.format("%sinfo add-on data: %d foods, %d drinks", t.TAG, nFoods, nDrinks))

        -- every food: the script now has the shelf life of its group
        local missing, wrong, applied = {}, {}, 0
        for _, e in ipairs(VFX.FOODS) do
            local sc = scriptOf(e[1])
            if not sc then missing[#missing + 1] = e[1]
            elseif sc:getDaysFresh() ~= e[2] or sc:getDaysTotallyRotten() ~= e[3] then
                if #wrong < 5 then wrong[#wrong + 1] = string.format("%s %s/%s", e[1], tostring(sc:getDaysFresh()), tostring(sc:getDaysTotallyRotten())) end
            else applied = applied + 1 end
        end
        check("every food of the add-on has its shelf life in the script", #missing == 0 and #wrong == 0 and applied == nFoods,
            string.format("applied %d, missing %d (%s), wrong %d (%s)", applied, #missing, table.concat(missing, ","):sub(1, 80), #wrong, table.concat(wrong, ", ")))

        -- group spot checks (days fresh / totally rotten)
        local expect = {
            ["VFX.Allspice"] = { 730, 820 }, ["VFX.VanillaExtract"] = { 730, 820 }, ["VFX.BeefBouillonCube"] = { 730, 820 },
            ["VFX.GumSpearmint"] = { 365, 420 }, ["VFX.ChocolateBarDark"] = { 365, 420 }, ["VFX.CheezItz"] = { 365, 420 },
            ["VFX.Almonds"] = { 365, 420 }, ["VFX.JasmineRice"] = { 365, 420 }, ["VFX.BrownieMix_2"] = { 365, 420 },
            ["VFX.StrawberryJam"] = { 365, 420 }, ["VFX.Ranch"] = { 365, 420 }, ["VFX.JarPickles"] = { 365, 420 },
            ["VFX.Wheaties"] = { 180, 240 }, ["VFX.CherryJelloCup"] = { 180, 240 }, ["VFX.Croutons"] = { 180, 240 },
            ["VFX.SwissRoll"] = { 30, 45 }, ["VFX.PackagedCherryStrudel"] = { 30, 45 }, ["VFX.Fudge"] = { 90, 120 },
            ["VFX.CinnamonButter"] = { 60, 80 }, ["VFX.HomemadeAlfredoSauce"] = { 30, 45 },
        }
        local bad = {}
        for full, e in pairs(expect) do
            local sc = scriptOf(full)
            if not sc or sc:getDaysFresh() ~= e[1] or sc:getDaysTotallyRotten() ~= e[2] then bad[#bad + 1] = full end
        end
        check("group spot checks (spice 2 years, candy and snacks 1 year, cereal 6 months, cakes 1 month...)", #bad == 0, table.concat(bad, ", "))

        -- left alone on purpose, and items that already spoiled by themselves
        local alone = { "VFX.CannedChicken", "VFX.CannedTomatoSoup", "VFX.SaltCan", "VFX.SugarBeetSugar", "VFX.PowderedSugar", "VFX.SourdoughStarter",
            "VFX.HomemadeWinePreparation", "VFX.FoodStorageContainer" }
        local changed = {}
        for _, full in ipairs(alone) do
            local sc = scriptOf(full)
            if sc and sc:getDaysFresh() < PF.NEVER then changed[#changed + 1] = full end
        end
        check("cans, salt, sugar, starters and ferments are left as they were", #changed == 0, table.concat(changed, ", "))
        local pre = scriptOf("VFX.Pretzel")
        check("a food that already spoiled in the other mod keeps its own shelf life", pre ~= nil and pre:getDaysFresh() == 3 and pre:getDaysTotallyRotten() == 6)
        check("the main mod's own table is unchanged", scriptOf("Base.Chocolate"):getDaysFresh() == 365 and scriptOf("Base.CookiesOatmeal"):getDaysFresh() == 30)
    end)

    -- 2. items: world generated and carried -------------------------------------
    t.queue(1, function()
        local function made(name, world) local i = instanceItem(name); PF.processItem(i, world); return i end
        local age = PF.worldGeneratedAge()
        local spice, gum, strudel, cereal = made("VFX.Allspice", true), made("VFX.GumSpearmint", true), made("VFX.PackagedCherryStrudel", true), made("VFX.Wheaties", true)
        check("world-generated add-on items are aged by the world's clock", math.abs(spice:getAge() - age) < 0.5 and math.abs(gum:getAge() - age) < 0.5,
            string.format("age %.2f / %.2f, world %.2f", spice:getAge(), gum:getAge(), age))
        check("offAge and offAgeMax follow the group (spice 730 / 820)", spice:getOffAge() == 730 and spice:getOffAgeMax() == 820)
        check("90 days in: strudel (45 days) is rotten, spice and gum are fresh, cereal (180) fine", strudel:isRotten() and spice:isFresh() and gum:isFresh() and not cereal:isRotten(),
            string.format("strudel %s, spice fresh %s, cereal rotten %s", tostring(strudel:isRotten()), tostring(spice:isFresh()), tostring(cereal:isRotten())))
        local carried = made("VFX.GumSpearmint", false)
        check("a carried item starts fresh", carried:getAge() == 0)
        ctx.carried, ctx.strudel = carried, made("VFX.PackagedCherryStrudel", false)
        -- food ages while it sits in an inventory (as the time-table suite does)
        local inv = getSpecificPlayer(0):getInventory()
        inv:AddItem(ctx.carried); inv:AddItem(ctx.strudel)
        local canned = made("VFX.CannedChicken", true)
        check("a canned food stays non-perishable", canned:getOffAge() >= PF.NEVER or canned:getOffAge() == 1000000000 or not canned:isRotten())
    end)
    t.queue(1, function()
        t.jumpDays(50)
        ctx.strudel:updateAge()
        ctx.carried:updateAge()
        check("50 days later: the carried strudel (45 days) is rotten", ctx.strudel:isRotten(), string.format("age %.1f", ctx.strudel:getAge()))
        check("50 days later: the carried gum is fresh", not ctx.carried:isRotten() and ctx.carried:isFresh())
        t.jumpDays(400)
        ctx.carried:updateAge()
        check("450 days later: gum (365 / 420) is rotten", ctx.carried:isRotten(), string.format("age %.1f", ctx.carried:getAge()))
        local spice = instanceItem("VFX.Allspice"); getSpecificPlayer(0):getInventory():AddItem(spice); PF.processItem(spice, false)
        t.jumpDays(400)
        spice:updateAge()
        check("400 days later a spice is still fresh (limit 2 years)", not spice:isRotten() and spice:getAge() > 399)
    end)

    -- 3. drinks ---------------------------------------------------------------
    t.queue(1, function()
        local function drink(name) local i = instanceItem(name); PF.processItem(i, false); return i end
        ctx.milk, ctx.juice, ctx.box, ctx.soda, ctx.tea = drink("VFX.ChocolateMilk"), drink("VFX.PineappleJuice"), drink("VFX.JuiceBoxTropical"), drink("VFX.CherryColaCan"), drink("VFX.IcedTeaLemon")
        ctx.beer = instanceItem("VFX.BottleStout"); PF.processItem(ctx.beer, false)
        check("add-on drinks have a clock", ctx.milk:getModData().PF_age == 0 and ctx.juice:getModData().PF_age == 0 and ctx.soda:getModData().PF_age == 0)
        check("sealed beer has no clock", ctx.beer:getModData().PF_age == nil)
        ctx.fluid0 = fluidName(ctx.milk)
    end)
    local function ageAll()
        for _, k in ipairs({ "milk", "juice", "box", "soda", "tea", "beer" }) do PF.ageDrink(ctx[k], false) end
    end
    t.queue(1, function()
        t.jumpDays(25); ageAll()
        check("day 25: milk, juice and soda are fine", fluidName(ctx.milk) ~= "SpoiledDrink" and fluidName(ctx.juice) ~= "SpoiledDrink" and fluidName(ctx.soda) ~= "SpoiledDrink")
        t.jumpDays(10); ageAll()
        check("day 35: the juice (30 days) spoiled, milk (60) did not", fluidName(ctx.juice) == "SpoiledDrink" and fluidName(ctx.milk) ~= "SpoiledDrink", fluidName(ctx.juice) .. " / " .. fluidName(ctx.milk))
        t.jumpDays(30); ageAll()
        check("day 65: the milk (60 days) spoiled, the juice box and tea (120) did not", fluidName(ctx.milk) == "SpoiledDrink" and fluidName(ctx.box) ~= "SpoiledDrink" and fluidName(ctx.tea) ~= "SpoiledDrink")
        t.jumpDays(60); ageAll()
        check("day 125: juice box and iced tea (120 days) spoiled, the soda (365) did not", fluidName(ctx.box) == "SpoiledDrink" and fluidName(ctx.tea) == "SpoiledDrink" and fluidName(ctx.soda) ~= "SpoiledDrink")
        t.jumpDays(300); ageAll()
        check("day 425: the soda spoiled, the sealed beer never does", fluidName(ctx.soda) == "SpoiledDrink" and fluidName(ctx.beer) ~= "SpoiledDrink")
    end)

    -- 4. the sandbox multiplier reaches the add-on's items ---------------------------
    t.queue(1, function()
        SandboxVars.PerishableFoods = SandboxVars.PerishableFoods or {}
        local old = SandboxVars.PerishableFoods.ShelfLifeMultiplier
        SandboxVars.PerishableFoods.ShelfLifeMultiplier = 200
        PF.applySchedule()
        local sc = scriptOf("VFX.Allspice")
        local ok2 = sc:getDaysFresh() == 1460 and sc:getDaysTotallyRotten() == 1640
        SandboxVars.PerishableFoods.ShelfLifeMultiplier = old
        PF.applySchedule()
        check("the main mod's multiplier (200) doubles the add-on's shelf lives, and goes back", ok2 and scriptOf("VFX.Allspice"):getDaysFresh() == 730)
        SandboxVars.PerishableFoods.Enabled = false
        local it = instanceItem("VFX.GumSpearmint"); PF.processItem(it, true)
        check("main mod disabled: the add-on does nothing either", it:getAge() == 0)
        SandboxVars.PerishableFoods.Enabled = nil
    end)

    -- 5. loot the game fills into real shop shelves, with the other mod swapping items ----
    t.queue(1, function()
        local player = getSpecificPlayer(0)
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        ctx.shelves = {}
        for dx = -70, 70 do
            for dy = -70, 70 do
                local sq = getCell():getGridSquare(px + dx, py + dy, 0)
                local room = sq and sq:getRoom()
                if room and FOOD_ROOMS[room:getName()] then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        for ci = 0, obj:getContainerCount() - 1 do ctx.shelves[#ctx.shelves + 1] = obj:getContainerByIndex(ci) end
                    end
                end
            end
        end
        check("food shop shelves near the spawn", #ctx.shelves >= 5, tostring(#ctx.shelves))
        ctx.fills = 0
        ctx.sched = {}
        for _, e in ipairs(PF.SCHEDULE) do ctx.sched[e[1]] = e end
    end)
    for round = 1, 3 do
        t.queue(40, function()
            local player = getSpecificPlayer(0)
            for _, c in ipairs(ctx.shelves or {}) do
                c:removeAllItems()
                ItemPicker.fillContainer(c, player)
                ctx.fills = ctx.fills + 1
            end
        end)
    end
    t.queue(80, function()
        local age = PF.worldGeneratedAge()
        local vfxSeen, vfxManaged, vfxBadAge, vfxBadOff, baseManaged, baseBad, drinksVfx, drinksBadAge, total = 0, 0, 0, 0, 0, 0, 0, 0, 0
        local examples = {}
        local function visit(item)
            total = total + 1
            local full = item:getFullType()
            local isVfx = full:sub(1, 4) == "VFX."
            if isVfx then vfxSeen = vfxSeen + 1 end
            local sched = ctx.sched[full]
            if sched and instanceof(item, "Food") then
                if isVfx then vfxManaged = vfxManaged + 1 else baseManaged = baseManaged + 1 end
                local offOk = item:getOffAge() == sched[2] and item:getOffAgeMax() == sched[3]
                local ageOk = math.abs(item:getAge() - age) < 1.5
                if not offOk then if isVfx then vfxBadOff = vfxBadOff + 1 else baseBad = baseBad + 1 end end
                if not ageOk then if isVfx then vfxBadAge = vfxBadAge + 1 else baseBad = baseBad + 1 end end
                if isVfx and #examples < 6 then examples[#examples + 1] = string.format("%s age %.0f/%.0f", full, item:getAge(), age) end
            end
            local d = PF.DRINKS[full]
            if d and item:getFluidContainer() and not item:getFluidContainer():isEmpty() and isVfx then
                drinksVfx = drinksVfx + 1
                local pa = item:getModData().PF_age
                if not (item:getModData().PF_spoiled or (pa and math.abs(pa - age) < 1.5)) then drinksBadAge = drinksBadAge + 1 end
            end
        end
        for _, c in ipairs(ctx.shelves or {}) do
            local items = c:getItems()
            for i = 0, items:size() - 1 do visit(items:get(i)) end
        end
        print(string.format("%sinfo loot: %d fills, %d items, %d from Vanilla Foods Expanded (%d with a shelf life from the add-on, %d such drinks), world age %.1f; e.g. %s",
            t.TAG, ctx.fills, total, vfxSeen, vfxManaged, drinksVfx, age, table.concat(examples, "; ")))
        check("real loot contains items swapped in by Vanilla Foods Expanded", vfxSeen > 0, tostring(vfxSeen))
        check("those items that the add-on covers carry the group's shelf life", vfxManaged > 0 and vfxBadOff == 0, string.format("%d covered, %d wrong", vfxManaged, vfxBadOff))
        check("and are aged by the world's clock like the main mod's own items", vfxBadAge == 0 and baseBad == 0, string.format("vfx %d wrong, base %d wrong of %d + %d", vfxBadAge, baseBad, vfxManaged, baseManaged))
        check("add-on drinks found in loot have their age too", drinksBadAge == 0, string.format("%d drinks, %d wrong", drinksVfx, drinksBadAge))
        t.finish()
    end)
end

-- pfvfx_probe: why can a drink not be turned into Spoiled Drink? (diagnostic, prints only)
CZM_TEST_SUITES.pfvfx_probe = function(t)
    t.queue(1, function()
        local spoiled = Fluid.Get("SpoiledDrink")
        for _, name in ipairs({ "VFX.CherryColaCan", "VFX.CreamSodaCan", "VFX.VanillaColaCan", "Base.SodaCan", "VFX.OrangeSodaBottle" }) do
            local item = instanceItem(name)
            local fc = item and item:getFluidContainer()
            if fc then
                local amount = fc:getAmount()
                local l = string.format("%sprobe %s sealed? canAdd(before)=%s", t.TAG, name, tostring(fc:canAddFluid(spoiled)))
                fc:Empty()
                l = l .. string.format(" | after Empty: canAdd=%s amount=%.2f", tostring(fc:canAddFluid(spoiled)), fc:getAmount())
                pcall(function() fc:unseal() end)
                l = l .. string.format(" | after unseal: canAdd=%s", tostring(fc:canAddFluid(spoiled)))
                fc:addFluid(spoiled, amount)
                l = l .. string.format(" | added: fluid=%s amount=%.2f", fluidName(item), fc:getAmount())
                print(l)
            end
        end
        t.finish()
    end)
end
