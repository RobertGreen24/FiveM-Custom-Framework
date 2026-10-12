--[[
    Nexus Framework :: nx_vehicles (client)
    Keys, locks, fuel, seatbelts, cruise control and hotwiring.
]]

local Nexus = Nexus
local Client = Nexus.Client

local keys = {}                 -- [plate] = true
local fuelThreads = {}          -- [plate] = true (running)
local cruise = nil              -- { vehicle, speed }
local beltOn = false
local lockState = {}            -- [plate] = locked
local hotwiring = false
local lastSent = {}             -- [plate] = { fuel, engine, body, mileage, at }
local mileage = {}              -- [plate] = km travelled
local fuel = {}                 -- [plate] = 0-100

local function normalisePlate(plate)
    return tostring(plate or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
end

local function plateOf(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local statePlate = Entity(vehicle).state.nx_plate
    if statePlate and statePlate ~= '' then return normalisePlate(statePlate) end
    return normalisePlate(GetVehicleNumberPlateText(vehicle))
end

--- Public helper other resources use ("does the ped have the keys?").
local function hasKeysVehicle(vehicle)
    local plate = plateOf(vehicle)
    if plate == '' then return true end
    if keys[plate] then return true end

    -- (requireItem is enforced server-side: the key list only contains plates
    -- the character actually owns or was handed)
    return false
end

local function notify(message, kind)
    Nexus.Notify(message, kind or 'info', 5000)
end

-- ===========================================================================
--  KEY REGISTRY
-- ===========================================================================

RegisterNetEvent('nexus:client:vehicleKeys', function(data)
    if not data or not data.plate then return end
    keys[normalisePlate(data.plate)] = data.add ~= false
end)

RegisterNetEvent('nexus:client:vehicleLockChanged', function(plate, locked, bySource)
    plate = normalisePlate(plate)
    lockState[plate] = locked

    -- visible feedback for everyone close enough to care
    local coords = GetEntityCoords(PlayerPedId())
    for _, entity in ipairs(GetGamePool('CVehicle')) do
        if plateOf(entity) == plate and #(coords - GetEntityCoords(entity)) < 40.0 then
            SetVehicleLights(entity, locked and 2 or 1)
            if VehicleConfig.keys.lockSound then
                PlayVehicleDoorCloseSound(entity, locked and 1 or 0)
            end
            Citizen.SetTimeout(600, function()
                if DoesEntityExist(entity) then SetVehicleLights(entity, 0) end
            end)
        end
    end

    if keys[plate] then
        notify(locked and 'Vehicle locked.' or 'Vehicle unlocked.', 'info')
    end
end)

--- Server asks us to write a new plate onto a vehicle entity.
RegisterNetEvent('nx_vehicles:applyPlate', function(vehicle, plate)
    if DoesEntityExist(vehicle) then
        SetVehicleNumberPlateText(vehicle, plate)
        Entity(vehicle).state:set('nx_plate', plate, true)
    end
end)

--- Requests the full key list (on spawn and after a purchase).
RegisterNetEvent('nexus:client:playerLoaded', function()
    TriggerServerEvent('nx_vehicles:requestKeys')
end)

--- Tag every vehicle we sit in with its plate so the server can identify it.
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        if Client.isLoaded() and IsPedInAnyVehicle(ped, false) then
            sleep = 500
            local vehicle = GetVehiclePedIsIn(ped, false)
            if IsPedInAnyVehicle(ped, false) and vehicle ~= 0 then
                local plate = plateOf(vehicle)
                if plate ~= '' then
                    Entity(vehicle).state:set('nx_plate', plate, true)
                    if GetPedInVehicleSeat(vehicle, -1) == ped then
                        Entity(vehicle).state:set('nx_driver', GetPlayerServerId(PlayerId()), true)
                    end
                end
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  LOCK / UNLOCK
-- ===========================================================================

local function toggleLock(vehicle)
    if not vehicle or vehicle == 0 then return end

    local plate = plateOf(vehicle)
    if plate == '' then return end

    if not hasKeysVehicle(vehicle) then
        notify('You do not have the keys to this vehicle.', 'error')
        return
    end

    local locked = not (lockState[plate] == true)
    lockState[plate] = locked
    SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
    TriggerServerEvent('nx_vehicles:setLock', plate, locked)
end

RegisterCommand('vehiclelock', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        -- lock the closest vehicle to the player
        local coords = GetEntityCoords(ped)
        local best, distance = nil, 6.0
        for _, entity in ipairs(GetGamePool('CVehicle')) do
            local dist = #(coords - GetEntityCoords(entity))
            if dist < distance then best, distance = entity, dist end
        end
        vehicle = best
    end
    if vehicle then toggleLock(vehicle) end
end, false)

RegisterKeyMapping('vehiclelock', 'Lock / unlock your vehicle', 'keyboard', VehicleConfig.keys.defaultKey or 'U')

--- Prevent entering a locked vehicle without the keys.
CreateThread(function()
    while true do
        Citizen.Wait(600)
        if Client.isLoaded() then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                local plate = plateOf(vehicle)
                if plate ~= '' and not keys[plate] and #(coords - GetEntityCoords(vehicle)) < 8.0 then
                    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), lockState[plate] == true)
                end
            end
        end
    end
end)

-- ===========================================================================
--  KEYS COMMANDS
-- ===========================================================================

RegisterCommand('givekeys', function(_, args)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = vehicle ~= 0 and plateOf(vehicle) or nil
    if not plate or plate == '' then
        notify('Sit in the vehicle you want to share.', 'error')
        return
    end

    if not hasKeysVehicle(vehicle) then
        notify('You cannot hand out keys you do not have.', 'error')
        return
    end

    local target = tonumber(args[1])
    if not target then
        local closest, distance = nil, VehicleConfig.keys.shareDistance
        local coords = GetEntityCoords(ped)
        for _, other in ipairs(GetActivePlayers()) do
            local otherPed = GetPlayerPed(other)
            if otherPed ~= ped then
                local dist = #(coords - GetEntityCoords(otherPed))
                if dist < distance then
                    closest, distance = other, dist
                end
            end
        end
        target = closest and GetPlayerServerId(closest) or nil
    end

    if not target then
        notify('No one nearby to give keys to.', 'error')
        return
    end

    TriggerServerEvent('nx_vehicles:giveKeys', target, plate)
end, false)

RegisterCommand('engine', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end
    if not hasKeysVehicle(vehicle) then
        notify('No keys.', 'error')
        return
    end

    local engine = not GetIsVehicleEngineRunning(vehicle)
    SetVehicleEngineOn(vehicle, engine, false, true)
end, false)

-- ===========================================================================
--  FUEL
-- ===========================================================================

local function tankSize(vehicle)
    local volume = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    if not volume or volume <= 0.0 then volume = 65.0 end
    return volume
end

--- Fuel is tracked as a percentage so different tank sizes behave the same.
local function fuelPercent(vehicle)
    local stored = fuel[plateOf(vehicle)]
    if stored then return stored end
    return (GetVehicleFuelLevel(vehicle) / tankSize(vehicle)) * 100.0
end

local function setFuel(vehicle, percent)
    local plate = plateOf(vehicle)
    percent = math.max(0.0, math.min(100.0, percent))
    fuel[plate] = percent

    SetVehicleFuelLevel(vehicle, (percent / 100.0) * tankSize(vehicle))
    Entity(vehicle).state:set('nx_fuel', percent, true)
end

Nexus.SetVehicleFuel = setFuel
Nexus.GetVehicleFuel = function(vehicle) return fuelPercent(vehicle) end

--- Burns fuel while the player drives.
CreateThread(function()
    while true do
        Citizen.Wait(1000)
        local ped = PlayerPedId()
        if Client.isLoaded() and IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(vehicle, -1) == ped and GetIsVehicleEngineRunning(vehicle) then
                local plate = plateOf(vehicle)
                local model = GetEntityModel(vehicle)
                local electric = false
                for name in pairs(VehicleConfig.fuel.electricModels) do
                    if model == GetHashKey(name) then electric = true end
                end

                local speed = GetEntitySpeed(vehicle) * 3.6
                local rpm = GetVehicleCurrentRpm and GetVehicleCurrentRpm(vehicle) or 0.4
                local burn

                if electric then
                    burn = (speed > 1.0 and (0.004 + rpm * 0.006) or 0.0) * VehicleConfig.fuel.consumption
                else
                    burn = (VehicleConfig.fuel.idleBurn + (rpm * 0.02) + (speed / 100.0) * 0.05)
                        * VehicleConfig.fuel.consumption
                end

                local percent = fuelPercent(vehicle) - burn
                if percent <= 0.0 then
                    percent = 0.0
                    if VehicleConfig.engine.stallAtZeroFuel then
                        SetVehicleEngineOn(vehicle, false, true, true)
                        notify('You are out of fuel.', 'error')
                    end
                end
                setFuel(vehicle, percent)

                mileage[plate] = (mileage[plate] or 0) + (speed / 3600.0) * 1000.0  -- metres per second * 1000
            end
        end
    end
end)

--- Pushes fuel/health for the vehicle we are in to the server.
CreateThread(function()
    while true do
        Citizen.Wait(5000)
        local ped = PlayerPedId()
        if Client.isLoaded() and IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = plateOf(vehicle)

            if plate ~= '' and (keys[plate] or hasKeysVehicle(vehicle)) then
                local now = GetGameTimer()
                local last = lastSent[plate] or 0
                local occupied = false
                for seat = -1, 8 do
                    if GetPedInVehicleSeat(vehicle, seat) ~= 0 then occupied = true end
                end

                if (now - last) > 15000 or not occupied then
                    lastSent[plate] = now
                    TriggerServerEvent('nx_vehicles:updateState', VehToNet(vehicle), {
                        fuel = fuelPercent(vehicle),
                        engine = GetVehicleEngineHealth(vehicle),
                        body = GetVehicleBodyHealth(vehicle),
                        mileage = mileage[plate] or 0,
                        occupied = occupied,
                    })
                end
            end
        end
    end
end)

--- Refuelling at a pump.
local function nearPump(coords)
    for _, pump in ipairs(VehicleConfig.petrolStations) do
        if #(coords - pump.coords) <= VehicleConfig.fuel.pumpRadius then return pump end
    end
    return nil
end

local function refuel(vehicle, litres, free)
    local tank = tankSize(vehicle)
    local currentLitres = (fuelPercent(vehicle) / 100.0) * tank
    local missing = tank - currentLitres
    if missing <= 0.5 then
        notify('The tank is already full.', 'info')
        return
    end

    local amount = math.min(missing, litres or missing)
    local cost = free and 0 or math.floor(amount * VehicleConfig.fuel.pumpCost)

    Nexus.Progress({
        label = free and 'Refuelling…' or ('Refuelling · $%d'):format(cost),
        duration = math.floor((amount / VehicleConfig.fuel.refuelRate) * 1000),
        disableMovement = true,
        disableCarMovement = true,
        disableCombat = true,
    }, function(completed)
        if not completed then return end
        if cost > 0 then
            TriggerServerEvent('nx_vehicles:payFuel', cost, amount)
        else
            setFuel(vehicle, fuelPercent(vehicle) + (amount / tankSize(vehicle)) * 100.0)
        end
    end)
end

RegisterNetEvent('nx_vehicles:fuelPaid', function(amount, cost)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    local vehicle = GetVehiclePedIsIn(ped, false)
    setFuel(vehicle, fuelPercent(vehicle) + (amount / tankSize(vehicle)) * 100.0)
    notify(('Refuelled %d L for $%d.'):format(math.floor(amount), cost), 'money')
end)

RegisterNetEvent('nx_vehicles:fuelFailed', function()
    notify('You cannot afford that much fuel.', 'error')
end)

RegisterCommand('refuel', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        notify('You are not in a vehicle.', 'error')
        return
    end
    if not nearPump(GetEntityCoords(vehicle)) then
        notify('No fuel pump nearby.', 'error')
        return
    end
    refuel(vehicle, nil, false)
end, false)

--- Petrol pump interaction loop (E or /refuel).
CreateThread(function()
    while true do
        local sleep = 700
        local ped = PlayerPedId()
        if Client.isLoaded() and GetVehiclePedIsIn(ped, false) == 0 then
            local coords = GetEntityCoords(ped)
            local pump = nearPump(coords)
            if pump then
                sleep = 0
                Nexus.TextUI(true, 'E', 'Refuel the nearest vehicle')
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    local closest, distance = nil, 15.0
                    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                        local dist = #(coords - GetEntityCoords(vehicle))
                        if dist < distance then closest, distance = vehicle, dist end
                    end
                    if closest then refuel(closest, nil, false) end
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  SEATBELT / CRUISE / HOTWIRE
-- ===========================================================================

local function toggleBelt()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    beltOn = not beltOn
    SetPedConfigFlag(ped, 32, beltOn)
    notify(beltOn and 'Seatbelt fastened.' or 'Seatbelt released.', 'info')
    TriggerEvent('nexus:client:hudExtra', { seatbelt = beltOn })
end

RegisterCommand('seatbelt', function() toggleBelt() end, false)
RegisterKeyMapping('seatbelt', 'Toggle seatbelt', 'keyboard', VehicleConfig.seatbelt.key or 'B')

--- Aggressive crash handling: unbelted players may be thrown out.
local lastSpeed = 0.0
local ejectCooldown = 0
CreateThread(function()
    while true do
        Citizen.Wait(100)
        if not VehicleConfig.seatbelt.enabled then break end

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local speed = GetEntitySpeed(vehicle) * 3.6

            if not beltOn and speed > VehicleConfig.seatbelt.crashSpeed
                and lastSpeed > VehicleConfig.seatbelt.crashSpeed + 15
                and (GetGameTimer() - ejectCooldown) > 3000
                and HasEntityCollidedWithAnything(vehicle) then

                ejectCooldown = GetGameTimer()
                if math.random() < VehicleConfig.seatbelt.ejectChance then
                    local coords = GetEntityCoords(ped)
                    local forward = GetEntityForwardVector(vehicle)

                    SetPedToRagdoll(ped, 4000, 4000, 0, true, true, false)
                    SetEntityCoords(ped, coords.x + forward.x * 2.0, coords.y + forward.y * 2.0, coords.z + 1.0, false, false, false, false)
                    ApplyDamageToPed(ped, math.floor(speed * 1.4), false)
                    notify('You were thrown through the windscreen.', 'error')
                    lastSpeed = 0.0
                end
            end

            lastSpeed = speed
        else
            lastSpeed = 0.0
            if beltOn and vehicle == 0 then
                beltOn = false
                SetPedConfigFlag(ped, 32, false)
            end
        end
    end
end)

local function toggleCruise()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    if cruise then
        cruise = nil
        TriggerEvent('nexus:client:hudExtra', { cruise = false })
        notify('Cruise control off.', 'info')
        return
    end

    local speed = GetEntitySpeed(vehicle) * 3.6
    if speed < VehicleConfig.cruise.minSpeed then
        notify('Drive faster to engage cruise control.', 'error')
        return
    end

    cruise = { vehicle = vehicle, speed = math.min(speed, VehicleConfig.cruise.maxSpeed) }
    notify(('Cruise control set to %d km/h.'):format(math.floor(cruise.speed)), 'info')
    TriggerEvent('nexus:client:hudExtra', { cruise = true })
end

RegisterCommand('cruise', function() toggleCruise() end, false)
RegisterKeyMapping('cruise', 'Toggle cruise control', 'keyboard', VehicleConfig.cruise.key or 'Y')

--- Holds the throttle for you. Braking or steering releases it.
CreateThread(function()
    while true do
        Citizen.Wait(150)
        if cruise then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= cruise.vehicle or not DoesEntityExist(vehicle) then
                cruise = nil
                TriggerEvent('nexus:client:hudExtra', { cruise = false })
            else
                if IsControlPressed(0, 76) or IsControlPressed(0, 72) or IsControlPressed(0, 63) or IsControlPressed(0, 64)
                    or IsControlJustPressed(0, 74) then
                    cruise = nil
                    TriggerEvent('nexus:client:hudExtra', { cruise = false })
                    notify('Cruise control cancelled.', 'info')
                elseif GetIsVehicleEngineRunning(vehicle) then
                    local speed = GetEntitySpeed(vehicle) * 3.6
                    local target = cruise.speed

                    if speed < target - 1.0 then
                        -- hold the throttle gently rather than snapping to speed
                        SetVehicleForwardSpeed(vehicle, (speed + math.min(4.0, target - speed)) / 3.6)
                    elseif speed > target + 4.0 then
                        SetVehicleForwardSpeed(vehicle, (speed - 3.0) / 3.6)
                    end
                end
            end
        end
    end
end)

--- Hotwire: start a car you do not have the keys for.
local function hotwire(vehicle)
    if hotwiring then return end
    if hasKeysVehicle(vehicle) then
        notify('You already have the keys.', 'info')
        return
    end

    hotwiring = true
    SetVehicleEngineOn(vehicle, false, true, true)

    Nexus.Progress({
        label = 'Hotwiring…',
        duration = VehicleConfig.hotwire.duration,
        disableMovement = true,
        disableCarMovement = false,
        disableCombat = true,
    }, function(completed)
        hotwiring = false
        if completed then
            local plate = plateOf(vehicle)
            keys[plate] = true
            SetVehicleEngineOn(vehicle, true, true, false)
            TriggerServerEvent('nx_vehicles:stolen', VehToNet(vehicle))
            notify('Engine started. Do not get caught.', 'warning')
        end
    end)
end

RegisterCommand('hotwire', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('Sit in the driver seat first.', 'error')
        return
    end
    hotwire(vehicle)
end, false)

--- Prompt to hotwire when sitting in a car you have no keys for.
CreateThread(function()
    while true do
        local sleep = 600
        local ped = PlayerPedId()
        if Client.isLoaded() and IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(vehicle, -1) == ped and not hasKeysVehicle(vehicle) and not hotwiring then
                sleep = 0
                Nexus.TextUI(true, 'E', 'Hotwire the vehicle')
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    hotwire(vehicle)
                end
            end
        end
        Citizen.Wait(sleep)
    end
end)

--- Server told us the hotwire alarm is ringing.
RegisterNetEvent('nx_vehicles:hotwireAlarm', function(coords)
    if not coords then return end
    PlaySoundFrontend(-1, 'BEEP_3', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
    Nexus.Notify('The alarm is going off!', 'error', 8000)
end)

RegisterNetEvent('nexus:client:vehicleKeysRemoved', function(plate)
    keys[normalisePlate(plate)] = nil
end)

--- Trunk hook: nx_inventory asks us to open a vehicle's storage.
RegisterNetEvent('nx_vehicles:openTrunk', function(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 then return end
    local plate = plateOf(entity)
    if plate == '' or not hasKeysVehicle(entity) then
        notify('You need the keys to open the trunk.', 'error')
        return
    end
    TriggerEvent('nx_inventory:openVehicleStorage', 'trunk', plate, netId)
end)

RegisterCommand('trunk', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        local best, distance = nil, 3.0
        for _, entity in ipairs(GetGamePool('CVehicle')) do
            local dist = #(coords - GetEntityCoords(entity))
            if dist < distance then best, distance = entity, dist end
        end
        vehicle = best
    end
    if not vehicle then return end

    local plate = plateOf(vehicle)
    if plate == '' or not hasKeysVehicle(vehicle) then
        notify('You need the keys to open the trunk.', 'error')
        return
    end
    TriggerEvent('nx_inventory:openVehicleStorage', 'trunk', plate, VehToNet(vehicle))
end, false)

--- Health/armour helpers used by nx_garages when it stores a vehicle.
exports('hasKeys', function(vehicle) return hasKeysVehicle(vehicle) end)
exports('getPlate', function(vehicle) return plateOf(vehicle) end)
exports('getFuel', function(vehicle) return fuelPercent(vehicle) end)
exports('setFuel', function(vehicle, percent) setFuel(vehicle, percent) end)
exports('isSeatbeltOn', function() return beltOn end)
exports('isCruiseOn', function() return cruise ~= nil end)
exports('toggleLock', function(vehicle) toggleLock(vehicle) end)

exports('vehicleData', function(vehicle)
    local plate = plateOf(vehicle)
    return {
        plate = plate,
        fuel = fuelPercent(vehicle),
        engine = GetVehicleEngineHealth(vehicle),
        body = GetVehicleBodyHealth(vehicle),
        mileage = mileage[plate] or 0,
        locked = lockState[plate] == true,
        keys = keys[plate] == true,
    }
end)
