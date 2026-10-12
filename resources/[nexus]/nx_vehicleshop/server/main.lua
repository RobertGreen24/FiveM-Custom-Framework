--[[
    Nexus Framework :: nx_vehicleshop (server)
    Purchases, test drives, trade-ins and finance. Prices come from the shared
    catalogue, so a client can never invent a discount.
]]

Nexus = Nexus or {}
local Vehicles = Nexus.Vehicles

local function shopByName(name)
    for _, shop in ipairs(Shops) do
        if shop.name == name then return shop end
    end
    return nil
end

local function ownedCount(charId)
    return tonumber(Nexus.DB.scalar('SELECT COUNT(*) FROM nx_vehicles WHERE char_id = ?', { charId })) or 0
end

--- Credit score for finance (stored in character metadata, defaults to 650).
local function creditScore(player)
    return tonumber(player:getMeta('credit', ShopConfig.finance.defaultScore)) or ShopConfig.finance.defaultScore
end

local function financeRate(player)
    local score = creditScore(player)
    local bucket = math.floor((score / ShopConfig.finance.scoreMax) * #ShopConfig.finance.rates)
    bucket = math.max(1, math.min(#ShopConfig.finance.rates, bucket + 1))
    return ShopConfig.finance.rates[bucket], score
end

-- ===========================================================================
--  BROWSING
-- ===========================================================================

RegisterNetEvent('nx_vehicleshop:requestCatalogue', function(shopName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local shop = shopByName(shopName)
    if not shop then return end

    -- filter the catalogue down to what this shop sells
    local allowed = {}
    for _, id in ipairs(shop.categories or {}) do allowed[id] = true end

    local vehicles = {}
    for _, entry in ipairs(ShopVehicles) do
        if allowed[entry.category] then
            vehicles[#vehicles + 1] = {
                model = entry.model,
                label = entry.label,
                price = entry.price,
                category = entry.category,
                vtype = entry.vtype,
            }
        end
    end

    TriggerClientEvent('nexus:client:shopCatalogue', source, {
        shop = {
            name = shop.name,
            label = shop.label,
            categories = shop.categories,
            preview = { shop.preview.x, shop.preview.y, shop.preview.z, shop.preview.w },
            camera = {
                coords = { shop.camera.coords.x, shop.camera.coords.y, shop.camera.coords.z },
                lookAt = { shop.camera.lookAt.x, shop.camera.lookAt.y, shop.camera.lookAt.z },
            },
        },
        categoryLabels = ShopCategories,
        vehicles = vehicles,
        money = { cash = player:getMoney('cash'), bank = player:getMoney('bank') },
        owned = ownedCount(player.charId),
        maxOwned = ShopConfig.maxOwned,
        fee = ShopConfig.registrationFee,
        finance = {
            enabled = ShopConfig.finance.enabled,
            minDeposit = ShopConfig.finance.minDeposit,
            rate = financeRate(player),
            score = creditScore(player),
            terms = { 7, 14, 28 },   -- in-game days
        },
        sellBack = ShopConfig.sellBack,
        myVehicles = Nexus.DB.query('SELECT plate, model, label, mileage, fuel FROM nx_vehicles WHERE char_id = ? ORDER BY label', { player.charId }),
    })
end)

-- ===========================================================================
--  PURCHASE
-- ===========================================================================

RegisterNetEvent('nx_vehicleshop:buy', function(shopName, model, payment, finance)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local shop = shopByName(shopName)
    if not shop then return end

    local entry = ShopFindVehicle(model)
    if not entry then
        player:notify('That vehicle is not for sale.', 'error')
        return
    end

    -- only vehicles the shop actually stocks
    local allowed = false
    for _, id in ipairs(shop.categories or {}) do
        if id == entry.category then allowed = true end
    end
    if not allowed then
        player:notify('This dealership does not sell that.', 'error')
        return
    end

    local total = entry.price + ShopConfig.registrationFee

    if ownedCount(player.charId) >= ShopConfig.maxOwned then
        player:notify(('You already own %d vehicles — sell one first.'):format(ShopConfig.maxOwned), 'error')
        return
    end

    -- finance?
    if finance and ShopConfig.finance.enabled then
        local deposit = math.floor(total * ShopConfig.finance.minDeposit)
        local rate = financeRate(player)
        local financed = math.floor((total - deposit) * (1 + rate))
        local terms = tonumber(finance.terms) or 14
        local perPayment = math.ceil(financed / math.max(1, math.floor(terms / 7)))

        if not player:removeMoney('bank', deposit, ('deposit for %s'):format(entry.label)) then
            player:notify(('You need %s for the deposit.'):format(Nexus.Utils.formatMoney(deposit)), 'error')
            return
        end

        player:setMeta('finance', {
            model = model,
            remaining = financed,
            payment = perPayment,
            nextPayment = os.time() + (7 * 24 * 3600),
            label = entry.label,
        })
        player:notify(('Financed %s · %s per week'):format(entry.label, Nexus.Utils.formatMoney(perPayment)), 'money', 8000)
    else
        local account = (payment == 'cash') and 'cash' or 'bank'
        if not player:removeMoney(account, total, ('purchase of %s'):format(entry.label)) then
            player:notify(('You cannot afford that (%s).'):format(Nexus.Utils.formatMoney(total)), 'error')
            return
        end
    end

    local plate, err = Vehicles.register(entry.model, player.charId, {
        label = entry.label,
        garage = shop.garage or 'legion',
        vtype = entry.vtype or 'automobile',
    })

    if not plate then
        -- refund on failure
        player:addMoney('bank', total, 'refund: vehicle registration failed')
        player:notify('The dealership could not register that vehicle. You were refunded.', 'error')
        return
    end

    -- record the purchase price so trade-ins can be valued
    Nexus.DB.update('UPDATE nx_vehicles SET purchase_price = ? WHERE plate = ?', { entry.price, plate })

    Nexus.Log.action('vehicle_purchased', {
        actor = player:getName(), target = plate,
        details = ('%s for %s at %s'):format(entry.label, Nexus.Utils.formatMoney(total), shop.label),
        colour = 0x22c55e,
    })

    TriggerClientEvent('nexus:client:shopPurchased', source, {
        plate = plate,
        label = entry.label,
        total = total,
        garage = shop.garage,
    })
    player:notify(('%s purchased · %s'):format(entry.label, plate), 'success', 8000, shop.label)
end)

--- Weekly finance collection.
CreateThread(function()
    while true do
        Citizen.Wait(60 * 1000)
        for _, player in ipairs(Nexus.GetPlayers()) do
            local finance = player:getMeta('finance')
            if finance and finance.nextPayment and os.time() >= finance.nextPayment then
                if player:removeMoney('bank', finance.payment, 'vehicle finance payment') then
                    finance.remaining = math.max(0, finance.remaining - finance.payment)
                    finance.nextPayment = os.time() + (7 * 24 * 3600)
                    if finance.remaining <= 0 then
                        player:setMeta('finance', nil)
                        player:notify('Your vehicle finance is paid off.', 'success', 8000, 'Finance')
                    else
                        player:setMeta('finance', finance)
                        player:notify(('Finance payment taken: %s · %s left'):format(
                            Nexus.Utils.formatMoney(finance.payment), Nexus.Utils.formatMoney(finance.remaining)), 'money')
                    end
                else
                    player:notify('Your finance payment failed — you are behind.', 'error', 8000, 'Finance')
                    Nexus.Log.action('finance_missed', { actor = 'system', target = player:getName(), details = finance.label })
                end
            end
        end
    end
end)

-- ===========================================================================
--  SELL BACK
-- ===========================================================================

RegisterNetEvent('nx_vehicleshop:sell', function(shopName, plate)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local shop = shopByName(shopName)
    if not shop then return end
    if not ShopConfig.sellBack.enabled then
        player:notify('This dealership does not buy vehicles.', 'error')
        return
    end

    local row = Nexus.DB.single('SELECT * FROM nx_vehicles WHERE plate = ? AND char_id = ?', { plate, player.charId })
    if not row then
        player:notify('You do not own that vehicle.', 'error')
        return
    end

    local entry = ShopFindVehicle(row.model)
    local basePrice = (tonumber(row.purchase_price) or (entry and entry.price) or 0)
    local mileageFactor = math.max(0.5, 1.0 - ((tonumber(row.mileage) or 0) / 200000))
    local damageFactor = math.max(0.6, (tonumber(row.engine_health) or 1000) / 1000)

    local offer = math.floor(basePrice * ShopConfig.sellBack.percentage * mileageFactor * damageFactor)
    if offer <= 0 then
        player:notify('That vehicle is worth nothing.', 'error')
        return
    end

    -- the vehicle must be at this dealership
    local entity = Vehicles.getEntity(plate)
    if entity then
        local coords = GetEntityCoords(GetPlayerPed(source))
        if coords and #(coords - GetEntityCoords(entity)) > 12.0 then
            player:notify('Bring the vehicle to the dealership first.', 'error')
            return
        end
        DeleteEntity(entity)
        Vehicles.detach(plate)
    end

    player:addMoney('bank', offer, ('sold %s'):format(row.label or row.model))
    Nexus.DB.update('DELETE FROM nx_vehicles WHERE plate = ?', { plate })

    Nexus.Log.action('vehicle_sold', {
        actor = player:getName(), target = plate,
        details = ('%s for %s'):format(row.label or row.model, Nexus.Utils.formatMoney(offer)),
    })
    player:notify(('Sold %s for %s'):format(row.label or row.model, Nexus.Utils.formatMoney(offer)), 'money', 8000)
    TriggerClientEvent('nx_vehicleshop:refresh', source)
end)

-- ===========================================================================
--  TEST DRIVE
-- ===========================================================================

RegisterNetEvent('nx_vehicleshop:testDrive', function(shopName, model)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local shop = shopByName(shopName)
    local entry = ShopFindVehicle(model)
    if not shop or not entry then return end

    local coords = shop.spawn
    local plate, netId = Vehicles.spawn(source, entry.model, coords, {
        owner = player.charId,
        fuel = 100.0,
    })
    if not plate then
        player:notify('The test vehicle could not be brought out.', 'error')
        return
    end

    TriggerClientEvent('nexus:client:testDriveStart', source, {
        plate = plate,
        netId = netId,
        camera = { shop.camera.coords.x, shop.camera.coords.y, shop.camera.coords.z },
        duration = ShopConfig.testDriveTime,
        distance = ShopConfig.testDriveDistance,
        label = entry.label,
    })

    -- clean the car up if it is abandoned (test drives never get a DB row)
    Citizen.SetTimeout((ShopConfig.testDriveTime + 20) * 1000, function()
        local entity = Vehicles.getEntity(plate)
        if entity then DeleteEntity(entity) end
        Vehicles.detach(plate)
    end)
end)

RegisterNetEvent('nx_vehicleshop:endTestDrive', function(plate)
    local entity = Vehicles.getEntity(plate)
    if entity then DeleteEntity(entity) end
    Vehicles.detach(plate)
end)

exports('getShops', function() return Shops end)
exports('getCatalogue', function() return ShopVehicles end)
exports('getShop', function(name) return shopByName(name) end)
exports('findVehicle', function(model) return ShopFindVehicle(model) end)
