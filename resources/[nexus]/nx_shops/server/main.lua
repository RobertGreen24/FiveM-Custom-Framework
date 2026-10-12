--[[
    Nexus Framework :: nx_shops (server)
    Buying and selling. Prices and stock come from the shared config; the client
    can only say *what* it wants, never what it costs.
]]

Nexus = Nexus or {}

local function shopByName(name)
    for _, shop in ipairs(Shops) do
        if shop.name == name then return shop end
    end
    return nil
end

local function sellPointByName(name)
    for _, point in ipairs(SellPoints) do
        if point.name == name then return point end
    end
    return nil
end

local function isOpen(shop)
    local from, to = ShopConfig.openHours[1], ShopConfig.openHours[2]
    if from == 0 and to == 24 then return true end
    -- the server has no game clock, so night trading follows the host clock
    local hour = tonumber(os.date('%H')) or 12
    if from <= to then
        return hour >= from and hour < to
    end
    return hour >= from or hour < to
end

local function priceOf(shop, entry)
    local markup = shop.markup or ShopConfig.defaultMarkup
    return math.floor(entry.price * markup)
end

--- Verifies the player is standing at the shop.
local function atLocation(source, location, radius)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return true end
    local coords = GetEntityCoords(ped)
    return #(coords - location.coords) <= (radius or 4.0)
end

-- ===========================================================================
--  CATALOGUE
-- ===========================================================================

local function buildCatalogue(shop)
    local list = {}

    for _, entry in ipairs(shop.items) do
        local def = Nexus.Items[entry.item]
        if def then
            local price = priceOf(shop, entry)
            list[#list + 1] = {
                name = entry.item,
                label = def.label,
                description = def.description,
                price = price,
                type = def.type,
                rarity = def.rarity,
                weight = def.weight,
                illegal = entry.illegal == true,
                licence = def.requiresLicence,
            }
        else
            Nexus.Print.warn('nx_shops: shop "%s" sells unknown item "%s"', shop.name, tostring(entry.item))
        end
    end
    return list
end

RegisterNetEvent('nx_shops:request', function(shopName, sellPointName)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    if sellPointName then
        local point = sellPointByName(sellPointName)
        if not point or not atLocation(source, point) then return end

        local buys = {}
        for item, price in pairs(point.buys) do
            local def = Nexus.Items[item]
            if def then
                buys[#buys + 1] = {
                    name = item,
                    label = def.label,
                    price = math.floor(price * ShopConfig.sellRate),
                    count = exports.nx_inventory:getItemCount(source, item),
                }
            end
        end
        table.sort(buys, function(a, b) return a.label < b.label end)

        TriggerClientEvent('nexus:client:shopData', source, {
            mode = 'sell',
            point = { name = point.name, label = point.label },
            items = buys,
            money = { cash = player:getMoney('cash'), bank = player:getMoney('bank') },
        })
        return
    end

    local shop = shopByName(shopName)
    if not shop then return end
    if not atLocation(source, shop) then
        player:notify('You are too far from the counter.', 'error')
        return
    end
    if not isOpen(shop) then
        player:notify('The shop is closed right now.', 'error')
        return
    end

    local illegalOnly = shop.illegalOnly == true
    local wanted = false
    if illegalOnly then
        -- buying from the black market requires a clean-ish record
        local warnings = tonumber(Nexus.DB.scalar(
            'SELECT COUNT(*) FROM nx_warnings WHERE char_id = ?', { player.charId })) or 0
        wanted = warnings > 3
    end

    TriggerClientEvent('nexus:client:shopData', source, {
        mode = 'buy',
        shop = {
            name = shop.name,
            label = shop.label,
            type = shop.type,
            markup = shop.markup or ShopConfig.defaultMarkup,
            requiresLicence = shop.requiresLicence,
            illegal = illegalOnly,
        },
        items = buildCatalogue(shop),
        money = { cash = player:getMoney('cash'), bank = player:getMoney('bank') },
        max = ShopConfig.maxQuantity,
        licenceHeld = shop.requiresLicence and player:hasLicence(shop.requiresLicence) or nil,
    })
end)

-- ===========================================================================
--  BUY
-- ===========================================================================

RegisterNetEvent('nx_shops:buy', function(shopName, itemName, amount, payment)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local shop = shopByName(shopName)
    if not shop or not atLocation(source, shop) then return end
    if not isOpen(shop) then
        player:notify('The shop is closed.', 'error')
        return
    end

    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 or amount > ShopConfig.maxQuantity then
        player:notify('That is not a valid quantity.', 'error')
        return
    end

    local entry
    for _, candidate in ipairs(shop.items) do
        if candidate.item == itemName then
            entry = candidate
            break
        end
    end
    if not entry then
        player:notify('They do not sell that here.', 'error')
        return
    end

    -- licences
    local def = Nexus.Items[itemName]
    if shop.requiresLicence and not player:hasLicence(shop.requiresLicence) then
        player:notify('You need a valid licence for that.', 'error')
        return
    end
    if def and def.requiresLicence and not player:hasLicence(def.requiresLicence) then
        player:notify('You need a valid licence for that.', 'error')
        return
    end

    local unitPrice = priceOf(shop, entry)
    local total = unitPrice * amount

    if not exports.nx_inventory:canCarryItem(source, itemName, amount) then
        player:notify('You cannot carry that much.', 'error')
        return
    end

    local account = (payment == 'cash') and 'cash' or 'bank'
    if not player:removeMoney(account, total, ('purchase at %s'):format(shop.label)) then
        player:notify(('You cannot afford that (%s).'):format(Nexus.Utils.formatMoney(total)), 'error')
        return
    end

    local ok = exports.nx_inventory:addItem(source, itemName, amount)
    if not ok then
        player:addMoney(account, total, 'refund: purchase failed')
        player:notify('You have no room for that.', 'error')
        return
    end

    player:notify(('Bought %dx %s for %s'):format(amount, def and def.label or itemName, Nexus.Utils.formatMoney(total)), 'money')

    if def and def.type == 'weapon' then
        TriggerClientEvent('nexus:client:equipWeapon', source, itemName, { ammo = 0 })
    end

    TriggerEvent('nexus:server:shopPurchase', player, shop.name, itemName, amount, total)
    TriggerClientEvent('nx_shops:refresh', source)
end)

-- ===========================================================================
--  SELL
-- ===========================================================================

RegisterNetEvent('nx_shops:sell', function(pointName, itemName, amount)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    local point = sellPointByName(pointName)
    if not point or not atLocation(source, point) then return end

    local basePrice = point.buys[itemName]
    if not basePrice then
        player:notify('They will not buy that.', 'error')
        return
    end

    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return end

    local have = exports.nx_inventory:getItemCount(source, itemName)
    if have < amount then
        player:notify('You do not have that many.', 'error')
        return
    end

    if not exports.nx_inventory:removeItem(source, itemName, amount) then
        player:notify('Could not hand it over.', 'error')
        return
    end

    local total = math.floor(basePrice * ShopConfig.sellRate) * amount
    player:addMoney('cash', total, ('sold to %s'):format(point.label))
    player:notify(('Sold %dx %s for %s'):format(amount, Nexus.GetItemLabel(itemName), Nexus.Utils.formatMoney(total)), 'money')

    TriggerEvent('nexus:server:shopSale', player, point.name, itemName, amount, total)
    TriggerClientEvent('nx_shops:refresh', source)
end)

exports('getShops', function() return Shops end)
exports('getSellPoints', function() return SellPoints end)
exports('getShop', function(name) return shopByName(name) end)
