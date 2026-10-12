--[[
    Nexus Framework :: nx_shops (client)
    Counter interaction, blips and the shop NUI (buy + sell modes).
]]

local Nexus = Nexus
local Client = Nexus.Client

local uiOpen = false
local data = nil
local activeShop = nil
local activeSellPoint = nil

-- ===========================================================================
--  BLIPS
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local function addBlip(coords, info, label)
        if not info then return end
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, info.sprite or 52)
        SetBlipColour(blip, info.colour or 2)
        SetBlipScale(blip, info.scale or 0.7)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(label)
        EndTextCommandSetBlipName(blip)
    end

    for _, shop in ipairs(Shops) do
        addBlip(shop.coords, shop.blip, shop.label)
    end
    for _, point in ipairs(SellPoints) do
        addBlip(point.coords, point.blip, point.label)
    end
end)

-- ===========================================================================
--  INTERACTION
-- ===========================================================================

local function closest(radius)
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance, kind = nil, radius or 2.5, nil

    for _, shop in ipairs(Shops) do
        local distance = #(coords - shop.coords)
        if distance < bestDistance then
            best, bestDistance, kind = shop, distance, 'shop'
        end
    end
    for _, point in ipairs(SellPoints) do
        local distance = #(coords - point.coords)
        if distance < bestDistance then
            best, bestDistance, kind = point, distance, 'sell'
        end
    end

    return best, kind, bestDistance
end

local function openShop(shop, kind)
    if kind == 'sell' then
        activeSellPoint = shop.name
        activeShop = nil
        TriggerServerEvent('nx_shops:request', nil, shop.name)
    else
        activeShop = shop.name
        activeSellPoint = nil
        TriggerServerEvent('nx_shops:request', shop.name)
    end
end

local function setFocus(state)
    uiOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = data })
end

RegisterNetEvent('nexus:client:shopData', function(payload)
    data = payload
    if not uiOpen then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = payload })
    end
end)

RegisterNetEvent('nx_shops:refresh', function()
    if activeShop then
        TriggerServerEvent('nx_shops:request', activeShop)
    elseif activeSellPoint then
        TriggerServerEvent('nx_shops:request', nil, activeSellPoint)
    end
end)

CreateThread(function()
    while true do
        local sleep = 600
        if Client.isLoaded() and not uiOpen then
            local shop, kind = closest(2.5)
            if shop then
                sleep = 0
                local verb = kind == 'sell' and 'Sell items to' or 'Browse'
                Nexus.TextUI(true, 'E', ('%s %s'):format(verb, shop.label))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    openShop(shop, kind)
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:buy', function(payload, cb)
    cb({ ok = true })
    if not activeShop then return end
    TriggerServerEvent('nx_shops:buy', activeShop, payload.item, payload.amount, payload.payment or 'cash')
end)

RegisterNUICallback('nx:sell', function(payload, cb)
    cb({ ok = true })
    if not activeSellPoint then return end
    TriggerServerEvent('nx_shops:sell', activeSellPoint, payload.item, payload.amount)
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    TriggerEvent('nx_shops:refresh')
end)

CreateThread(function()
    while true do
        Citizen.Wait(uiOpen and 0 or 500)
        if uiOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if uiOpen then SetNuiFocus(false, false) end
end)

exports('openShop', function(shopName)
    local shop = shopName
    if type(shopName) == 'string' then
        for _, entry in ipairs(Shops) do
            if entry.name == shopName then shop = entry break end
        end
    end
    if shop and shop.name then openShop(shop, 'shop') end
end)

exports('getShops', function() return Shops end)
exports('getSellPoints', function() return SellPoints end)
