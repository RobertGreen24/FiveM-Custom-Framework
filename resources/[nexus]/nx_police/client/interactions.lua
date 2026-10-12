--[[
    Nexus Framework :: nx_police/client/interactions.lua
    Radar, speed traps and the small quality-of-life bits officers expect.
]]

local Nexus = Nexus
local Client = Nexus.Client

local radarOn = false
local radarEntries = {}
local lastRadarCheck = 0

local function isOfficer()
    local job = Client.getJob()
    return job.name == PoliceConfig.job or Client.isAdmin()
end

-- ===========================================================================
--  RADAR
-- ===========================================================================

local function roadSpeed(vehicle)
    return math.floor(GetEntitySpeed(vehicle) * 3.6)
end

local function pushRadar()
    SendNUIMessage({
        action = 'radar',
        data = {
            active = radarOn,
            limit = PoliceConfig.speedLimit,
            entries = radarEntries,
            plate = radarEntries[1] and radarEntries[1].plate or '—',
            speed = radarEntries[1] and radarEntries[1].speed or 0,
        },
    })
end

RegisterNetEvent('nx_police:radarReport', function(entry)
    if not entry or not entry.plate then return end
    table.insert(radarEntries, 1, entry)
    while #radarEntries > 6 do table.remove(radarEntries) end
    if radarOn then pushRadar() end
end)

RegisterCommand(PoliceConfig.radarCommand, function()
    if not isOfficer() then return end
    radarOn = not radarOn
    pushRadar()
    Nexus.Notify(radarOn and 'Radar on.' or 'Radar off.', 'info', 3000, 'Radar')
end, false)

RegisterKeyMapping(PoliceConfig.radarCommand, 'Toggle speed radar', 'keyboard', PoliceConfig.radarToggleKey or 'F5')

--- Scans the traffic in front of the cruiser and logs speeders.
CreateThread(function()
    while true do
        local sleep = 1000
        if radarOn and isOfficer() then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                sleep = 250
                local myVehicle = GetVehiclePedIsIn(ped, false)
                local coords = GetEntityCoords(myVehicle)

                for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                    if vehicle ~= myVehicle and DoesEntityExist(vehicle) then
                        local vehicleCoords = GetEntityCoords(vehicle)
                        local distance = #(coords - vehicleCoords)
                        if distance <= 45.0 then
                            local speed = roadSpeed(vehicle)
                            if speed > PoliceConfig.speedLimit and speed < PoliceConfig.radarMaxSpeed then
                                local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', '')
                                local now = GetGameTimer()
                                if plate ~= '' and (now - (lastRadarCheck or 0)) > 5000 then
                                    lastRadarCheck = now
                                    local model = GetEntityModel(vehicle)
                                    TriggerServerEvent('nx_police:radarReport', plate, speed, model)
                                    TriggerEvent('nx_police:radarReport', {
                                        plate = plate, speed = speed, distance = math.floor(distance),
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  SEARCH LIGHT / TASER SAFETY NETS
-- ===========================================================================

--- /spotlight — toggles the vehicle search light (unmarked cars, helicopters).
local spotlightOn = false
RegisterCommand('spotlight', function()
    if not isOfficer() then
        Nexus.Notify('Only the police may use the spotlight.', 'error')
        return
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        Nexus.Notify('You are not in a vehicle.', 'error')
        return
    end

    spotlightOn = not spotlightOn
    local vehicle = GetVehiclePedIsIn(ped, false)
    SetVehicleSearchlight(vehicle, spotlightOn, true)
    Nexus.Notify(spotlightOn and 'Spotlight on.' or 'Spotlight off.', 'info', 3000)
end, false)

--- Recently deceased ped detection so officers get a nudge to log a death.
local lastDeathCheck = 0
CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if isOfficer() then
            local now = GetGameTimer()
            if (now - lastDeathCheck) > 15000 then
                lastDeathCheck = now
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                for _, other in ipairs(GetGamePool('CPed')) do
                    if other ~= ped and DoesEntityExist(other) and IsPedDeadOrDying(other, true) then
                        local otherCoords = GetEntityCoords(other)
                        if #(coords - otherCoords) < 12.0 then
                            SendNUIMessage({
                                action = 'corpse',
                                data = { coords = { otherCoords.x, otherCoords.y, otherCoords.z } },
                            })
                        end
                        break
                    end
                end
            end
        end
    end
end)

exports('radarActive', function() return radarOn end)
