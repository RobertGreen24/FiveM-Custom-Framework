--[[
    Nexus Framework :: nx_vehicleshop (client)
    Blips, the browsing camera, preview vehicles and test drives.
]]

local Nexus = Nexus
local Client = Nexus.Client

local uiOpen = false
local currentShop = nil
local catalogue = nil
local previewVehicle = nil
local previewCam = nil
local testDrive = nil

-- ===========================================================================
--  BLIPS
-- ===========================================================================

local function createBlips()
    for _, shop in ipairs(Shops) do
        if shop.blip then
            local blip = AddBlipForCoord(shop.showroom.x, shop.showroom.y, shop.showroom.z)
            SetBlipSprite(blip, shop.blip.sprite or 326)
            SetBlipColour(blip, shop.blip.colour or 67)
            SetBlipScale(blip, shop.blip.scale or 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createBlips()
end)

-- ===========================================================================
--  PREVIEW
-- ===========================================================================

local function clearPreview()
    if previewVehicle and DoesEntityExist(previewVehicle) then
        DeleteVehicle(previewVehicle)
    end
    previewVehicle = nil

    if previewCam then
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
end

local function showPreview(shop, model)
    clearPreview()

    local hash = GetHashKey(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 4000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Citizen.Wait(10)
    end
    if not HasModelLoaded(hash) then return end

    local spawn = shop.preview
    previewVehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, false, false)
    SetVehicleOnGroundProperly(previewVehicle)
    SetEntityInvincible(previewVehicle, true)
    SetVehicleDirtLevel(previewVehicle, 0.0)
    SetVehicleDoorsLocked(previewVehicle, 2)
    SetModelAsNoLongerNeeded(hash)

    -- slow turntable
    CreateThread(function()
        while previewVehicle and DoesEntityExist(previewVehicle) and uiOpen do
            Citizen.Wait(0)
            local heading = GetEntityHeading(previewVehicle) + 0.25
            SetEntityHeading(previewVehicle, heading % 360.0)
        end
    end)

    -- camera on the showroom glass
    local cam = shop.camera
    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        cam.coords[1], cam.coords[2], cam.coords[3], 0.0, 0.0, 0.0, 42.0, false, 0)
    PointCamAtCoord(previewCam, cam.lookAt[1], cam.lookAt[2], cam.lookAt[3])
    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 800, true, true)
end

-- ===========================================================================
--  UI
-- ===========================================================================

local function setFocus(state)
    uiOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = catalogue })
    if not state then
        clearPreview()
    end
end

local function requestShop(shopName)
    currentShop = shopName
    TriggerServerEvent('nx_vehicleshop:requestCatalogue', shopName)
end

RegisterNetEvent('nexus:client:shopCatalogue', function(data)
    catalogue = data
    if not uiOpen then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = data })
    end
end)

RegisterNetEvent('nx_vehicleshop:refresh', function()
    if currentShop then requestShop(currentShop) end
end)

RegisterNetEvent('nexus:client:shopPurchased', function(info)
    Nexus.Notify(('%s is waiting at %s'):format(info.label, info.garage or 'the garage'), 'success', 8000, 'Dealership')
    if currentShop then requestShop(currentShop) end
end)

-- ===========================================================================
--  INTERACTION
-- ===========================================================================

local function closestShop()
    local coords = GetEntityCoords(PlayerPedId())
    for _, shop in ipairs(Shops) do
        if #(coords - shop.showroom) <= 3.0 then return shop end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 750
        if Client.isLoaded() and not uiOpen then
            local shop = closestShop()
            if shop then
                sleep = 0
                Nexus.TextUI(true, 'E', ('Browse %s'):format(shop.label))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    requestShop(shop.name)
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  TEST DRIVE
-- ===========================================================================

RegisterNetEvent('nexus:client:testDriveStart', function(info)
    setFocus(false)

    local entity = NetworkGetEntityFromNetworkId(info.netId)
    local timeout = GetGameTimer() + 6000
    while (not entity or entity == 0) and GetGameTimer() < timeout do
        Citizen.Wait(50)
        entity = NetworkGetEntityFromNetworkId(info.netId)
    end
    if not entity or entity == 0 then return end

    NetworkRequestControlOfEntity(entity)
    local controlTimeout = GetGameTimer() + 3000
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < controlTimeout do
        Citizen.Wait(10)
        NetworkRequestControlOfEntity(entity)
    end

    SetVehicleNumberPlateText(entity, info.plate)
    SetVehicleFuelLevel(entity, 100.0)
    SetVehicleEngineOn(entity, true, true, false)

    testDrive = {
        plate = info.plate,
        entity = entity,
        expires = GetGameTimer() + (info.duration * 1000),
        start = GetEntityCoords(entity),
        maxDistance = info.distance,
    }

    Nexus.Notify(('%s test drive · %ds'):format(info.label, info.duration), 'info', 6000, 'Test drive')
end)

CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if testDrive then
            local expired = GetGameTimer() > testDrive.expires
            local entity = testDrive.entity
            local lost = not entity or not DoesEntityExist(entity)

            local tooFar = false
            if not lost then
                local ped = PlayerPedId()
                local inThisCar = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) == entity
                tooFar = not inThisCar and #(GetEntityCoords(ped) - testDrive.start) > testDrive.maxDistance
            end

            if expired or tooFar or lost then
                if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
                TriggerServerEvent('nx_vehicleshop:endTestDrive', testDrive.plate)
                Nexus.Notify('Test drive ended.', 'info', 5000, 'Dealership')
                testDrive = nil
            end
        end
    end
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:preview', function(data, cb)
    cb({ ok = true })
    if not data or not catalogue then return end
    local shop = {
        preview = {
            x = catalogue.shop.preview[1], y = catalogue.shop.preview[2],
            z = catalogue.shop.preview[3], w = catalogue.shop.preview[4],
        },
        camera = catalogue.shop.camera,
    }
    showPreview(shop, data.model)
end)

RegisterNUICallback('nx:buy', function(data, cb)
    cb({ ok = true })
    if not data or not currentShop then return end
    TriggerServerEvent('nx_vehicleshop:buy', currentShop, data.model, data.payment or 'bank', data.finance or nil)
end)

RegisterNUICallback('nx:testDrive', function(data, cb)
    cb({ ok = true })
    if not data or not currentShop then return end
    TriggerServerEvent('nx_vehicleshop:testDrive', currentShop, data.model)
end)

RegisterNUICallback('nx:sell', function(data, cb)
    cb({ ok = true })
    if not data or not currentShop then return end
    TriggerServerEvent('nx_vehicleshop:sell', currentShop, data.plate)
end)

--- Control blocking while browsing.
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
    clearPreview()
end)

exports('openShop', function(shopName) requestShop(shopName) end)
exports('getShops', function() return Shops end)
