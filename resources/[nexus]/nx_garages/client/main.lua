--[[
    Nexus Framework :: nx_garages (client)
    Garage blips, the retrieval marker and spawning stored vehicles.
]]

local Nexus = Nexus
local Client = Nexus.Client

local uiOpen = false
local data = nil
local activeGarage = nil
local spawned = {}          -- [plate] = netId of vehicles this client pulled out

local function notify(message, kind)
    Nexus.Notify(message, kind or 'info', 6000)
end

--- Vehicle type from the *config* so the garage can decide where it fits.
local function typeOfVehicle(vehicle)
    local class = GetVehicleClass(vehicle)
    if class == 8 then return 'bike' end
    if class == 15 then return 'heli' end
    if class == 16 then return 'plane' end
    if class == 14 then return 'boat' end
    if class == 11 or class == 12 then return 'truck' end
    return 'automobile'
end

-- ===========================================================================
--  BLIPS
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local function blip(coords, info, label)
        if not info then return end
        local handle = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(handle, info.sprite or 357)
        SetBlipColour(handle, info.colour or 3)
        SetBlipScale(handle, 0.75)
        SetBlipAsShortRange(handle, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(label)
        EndTextCommandSetBlipName(handle)
    end

    for _, garage in ipairs(Garages) do blip(garage.coords, garage.blip, garage.label) end
    for _, impound in ipairs(Impounds) do blip(impound.coords, impound.blip, impound.label) end
end)

-- ===========================================================================
--  RETRIEVAL
-- ===========================================================================

local function applyMods(vehicle, info)
    if info.mods then
        for id, level in pairs(info.mods) do
            SetVehicleModKit(vehicle, 0)
            SetVehicleMod(vehicle, tonumber(id) or 0, tonumber(level) or -1, false)
        end
    end

    if info.colors then
        if info.colors.primary then
            SetVehicleColours(vehicle, tonumber(info.colors.primary) or 0, tonumber(info.colors.secondary) or 0)
        end
        if info.colors.pearlescent then
            SetVehicleExtraColours(vehicle, tonumber(info.colors.pearlescent) or 0, tonumber(info.colors.wheel) or 0)
        end
        if info.colors.livery then
            SetVehicleModKit(vehicle, 0)
            SetVehicleLivery(vehicle, tonumber(info.colors.livery) or -1)
        end
    end

    if info.extras then
        for id, enabled in pairs(info.extras) do
            SetVehicleExtra(vehicle, tonumber(id) or 0, enabled and 0 or 1)
        end
    end

    if info.neon then
        if info.neon.enabled ~= nil then
            SetVehicleNeonLightsOn(vehicle, 0, info.neon.enabled and true or false)
            SetVehicleNeonLightsOn(vehicle, 1, info.neon.enabled and true or false)
            SetVehicleNeonLightsOn(vehicle, 2, info.neon.enabled and true or false)
            SetVehicleNeonLightsOn(vehicle, 3, info.neon.enabled and true or false)
        end
        if info.neon.colour then
            SetVehicleNeonLightsColour(vehicle,
                tonumber(info.neon.colour[1]) or 255,
                tonumber(info.neon.colour[2]) or 255,
                tonumber(info.neon.colour[3]) or 255)
        end
    end

    if info.tyres then
        if info.tyres.smoke then
            SetVehicleTyreSmokeColor(vehicle,
                tonumber(info.tyres.smoke[1]) or 255,
                tonumber(info.tyres.smoke[2]) or 255,
                tonumber(info.tyres.smoke[3]) or 255)
        end
        if info.tyres.bulletproof then
            SetVehicleTyresCanBurst(vehicle, false)
        end
    end

    if info.engineHealth then
        SetVehicleEngineHealth(vehicle, math.max(0.0, tonumber(info.engineHealth) or 1000.0))
    end
    if info.bodyHealth then
        SetVehicleBodyHealth(vehicle, math.max(0.0, tonumber(info.bodyHealth) or 1000.0))
    end
end

Nexus.ApplyVehicleMods = applyMods

RegisterNetEvent('nexus:client:garageSpawn', function(info)
    local spawn = info.spawn or {}
    local coords = vector3(spawn[1] or 0.0, spawn[2] or 0.0, spawn[3] or 0.0)
    local heading = spawn[4] or 0.0

    if info.delay and info.delay > 0 then
        local delay = info.delay
        info.delay = nil   -- strip it before the inner call re-enters this handler

        Nexus.Progress({
            label = 'Retrieving vehicle…',
            duration = delay,
            disableMovement = true,
            disableCombat = true,
        }, function(completed)
            if completed then TriggerEvent('nexus:client:garageSpawn', info) end
        end)
        return
    end

    local model = info.model
    if not model then
        notify('That vehicle model is unknown.', 'error')
        return
    end

    local hash = GetHashKey(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 6000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Citizen.Wait(10)
    end
    if not HasModelLoaded(hash) then
        notify('That vehicle could not be loaded.', 'error')
        return
    end

    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, true)
    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < 50 do
        Citizen.Wait(20)
        attempts = attempts + 1
    end
    if not DoesEntityExist(vehicle) then
        notify('The garage failed to bring the vehicle out.', 'error')
        return
    end

    SetVehicleNumberPlateText(vehicle, info.plate or '')
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleEngineOn(vehicle, GarageConfig.engineOnRetrieve or false, true, false)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetModelAsNoLongerNeeded(hash)

    applyMods(vehicle, info)

    -- fuel is a percentage in our system
    local fuel = tonumber(info.fuel) or 100.0
    local tank = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    if not tank or tank <= 0 then tank = 65.0 end
    SetVehicleFuelLevel(vehicle, (fuel / 100.0) * tank)

    Entity(vehicle).state:set('nx_plate', info.plate or '', true)
    Entity(vehicle).state:set('nx_fuel', fuel, true)

    local netId = VehToNet(vehicle)
    spawned[info.plate or model] = netId

    if info.keys ~= false and info.plate then
        TriggerServerEvent('nx_vehicles:updateState', netId, {
            fuel = fuel,
            engine = info.engineHealth or 1000.0,
            body = info.bodyHealth or 1000.0,
            mileage = info.mileage or 0,
        })
    end

    -- a little blip so the player can find the car in a busy lot
    if info.plate and info.plate ~= 'FLEET' then
        local blip = AddBlipForEntity(vehicle)
        SetBlipSprite(blip, 225)
        SetBlipColour(blip, 2)
        SetBlipScale(blip, 0.6)
        Citizen.SetTimeout(30000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end)
    end

    Nexus.Notify('Vehicle brought out.', 'success', 5000)
end)

--- Stores the vehicle the player is sitting in (or standing next to).
local function storeVehicle(garageName, netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 then
        notify('No vehicle to store.', 'error')
        return
    end

    local speed = GetEntitySpeed(vehicle) * 3.6
    if speed > GarageConfig.maxSpeedOnStore then
        notify('Stop the vehicle before storing it.', 'error')
        return
    end

    local plate = tostring(Entity(vehicle).state.nx_plate or GetVehicleNumberPlateText(vehicle))
    plate = plate:upper():gsub('[^A-Z0-9]', '')

    -- fuel is kept as a percentage, but nx_inventory wants litres sometimes:
    -- the snapshot below is what nx_garages writes to MySQL.
    local tank = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    if not tank or tank <= 0 then tank = 65.0 end

    local fuelPercent = (GetVehicleFuelLevel(vehicle) / tank) * 100.0

    local mods = {}
    SetVehicleModKit(vehicle, 0)
    for id = 0, 49 do
        local level = GetVehicleMod(vehicle, id)
        if level ~= -1 then mods[id] = level end
    end

    local primary, secondary = GetVehicleColours(vehicle)
    local pearlescent, wheel = GetVehicleExtraColours(vehicle)

    local extras = {}
    for id = 0, 14 do
        if DoesExtraExist(vehicle, id) then
            extras[id] = IsVehicleExtraTurnedOn(vehicle, id)
        end
    end

    local neon = {
        enabled = IsVehicleNeonLightEnabled(vehicle, 0) or IsVehicleNeonLightEnabled(vehicle, 1)
            or IsVehicleNeonLightEnabled(vehicle, 2) or IsVehicleNeonLightEnabled(vehicle, 3),
        colour = { GetVehicleNeonLightsColour(vehicle) },
    }

    local r, g, b = GetVehicleTyreSmokeColor(vehicle)
    local tyres = {
        smoke = { r, g, b },
        bulletproof = not GetVehicleTyresCanBurst(vehicle),
    }

    local snapshot = {
        plate = plate,
        label = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        vtype = typeOfVehicle(vehicle),
        fuel = fuelPercent,
        engineHealth = GetVehicleEngineHealth(vehicle),
        bodyHealth = GetVehicleBodyHealth(vehicle),
        mileage = tonumber(Entity(vehicle).state.nx_mileage) or 0,
        mods = mods,
        colors = { primary = primary, secondary = secondary, pearlescent = pearlescent, wheel = wheel },
        extras = extras,
        neon = neon,
        tyres = tyres,
    }

    Nexus.Progress({
        label = 'Storing vehicle…',
        duration = GarageConfig.storeDelay,
        disableMovement = true,
        disableCarMovement = true,
        disableCombat = true,
    }, function(completed)
        if not completed then return end
        TriggerServerEvent('nx_garages:store', garageName, netId, snapshot)
        spawned[plate] = nil
        Nexus.Notify('Vehicle stored.', 'success', 5000)
    end)
end

-- ===========================================================================
--  UI
-- ===========================================================================

local function setFocus(state)
    uiOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = data })
end

RegisterNetEvent('nexus:client:garageData', function(payload)
    data = payload
    activeGarage = payload.garage and payload.garage.name or nil
    if not uiOpen then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = payload })
    end
end)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:retrieve', function(payload, cb)
    cb({ ok = true })
    if not activeGarage then return end
    TriggerServerEvent('nx_garages:retrieve', activeGarage, payload.plate or payload.model)
end)

RegisterNUICallback('nx:store', function(payload, cb)
    cb({ ok = true })
    if not activeGarage then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        local best, distance = nil, 12.0
        for _, entity in ipairs(GetGamePool('CVehicle')) do
            local dist = #(coords - GetEntityCoords(entity))
            if dist < distance then best, distance = entity, dist end
        end
        vehicle = best
    end

    if not vehicle or vehicle == 0 then
        Nexus.Notify('No vehicle nearby to store.', 'error')
        setFocus(false)
        return
    end

    setFocus(false)
    storeVehicle(activeGarage, VehToNet(vehicle))
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    if activeGarage then TriggerServerEvent('nx_garages:open', activeGarage) end
end)

-- ===========================================================================
--  INTERACTION
-- ===========================================================================

local function nearestGarage()
    local coords = GetEntityCoords(PlayerPedId())
    for _, garage in ipairs(Garages) do
        if #(coords - garage.coords) <= GarageConfig.spawnRadius then return garage end
    end
    for _, impound in ipairs(Impounds) do
        if #(coords - impound.coords) <= GarageConfig.spawnRadius then return impound end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 600
        if Client.isLoaded() and not uiOpen then
            local garage = nearestGarage()
            if garage then
                sleep = 0
                local inVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
                local label = inVehicle and ('Store vehicle · %s'):format(garage.label) or ('Open %s'):format(garage.label)

                Nexus.TextUI(true, 'E', label)
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    if inVehicle then
                        storeVehicle(garage.name, VehToNet(GetVehiclePedIsIn(PlayerPedId(), false)))
                    else
                        TriggerServerEvent('nx_garages:open', garage.name)
                    end
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

--- Impound hook: police and mechanic resources call this with a plate.
RegisterNetEvent('nx_garages:impoundFromClient', function(plate, reason)
    TriggerServerEvent('nx_garages:impound', plate, reason)
end)

RegisterCommand('garage', function()
    local garage = nearestGarage()
    if not garage then
        Nexus.Notify('You are not at a garage.', 'error')
        return
    end
    TriggerServerEvent('nx_garages:open', garage.name)
end, false)

RegisterCommand('store', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Nexus.Notify('You are not in a vehicle.', 'error')
        return
    end

    local garage = nearestGarage()
    if not garage then
        Nexus.Notify('You are not at a garage.', 'error')
        return
    end
    storeVehicle(garage.name, VehToNet(vehicle))
end, false)

RegisterKeyMapping('store', 'Store the vehicle at a garage', 'keyboard', '')

exports('openGarage', function(name) TriggerServerEvent('nx_garages:open', name) end)
exports('isOpen', function() return uiOpen end)
exports('nearestGarage', function()
    local garage = nearestGarage()
    return garage and garage.name or nil
end)
