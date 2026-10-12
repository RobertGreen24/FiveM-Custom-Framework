--[[
    Nexus Framework :: nx_ems (client)
    Revive, treatment, stretcher carry and the patient chart terminal.
]]

local Nexus = Nexus
local Client = Nexus.Client

local mdtOpen = false
local mdtData = nil

local function isMedic()
    local job = Client.getJob()
    return job.name == EmsConfig.job or Client.isAdmin()
end

local function nearestPlayer(radius)
    local closest, distance = nil, radius or 3.0
    local coords = GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= PlayerPedId() and DoesEntityExist(ped) then
            local dist = #(coords - GetEntityCoords(ped))
            if dist < distance then
                closest, distance = GetPlayerServerId(player), dist
            end
        end
    end
    return closest, distance
end

local function nearestDownedPlayer(radius)
    local closest, distance = nil, radius or 3.0
    local coords = GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= PlayerPedId() and DoesEntityExist(ped) then
            local dead = IsPedDeadOrDying(ped, true) or (GetEntityHealth(ped) <= 110)
            local dist = #(coords - GetEntityCoords(ped))
            if dead and dist < distance then
                closest, distance = GetPlayerServerId(player), dist
            end
        end
    end
    return closest, distance
end

-- ===========================================================================
--  BLIPS
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, hospital in ipairs(EmsConfig.hospitals) do
        if hospital.blip then
            local blip = AddBlipForCoord(hospital.coords.x, hospital.coords.y, hospital.coords.z)
            SetBlipSprite(blip, hospital.blip.sprite or 61)
            SetBlipColour(blip, hospital.blip.colour or 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(hospital.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- ===========================================================================
--  TREATMENT ACTIONS
-- ===========================================================================

local function doTreatment(label, duration, thenFn)
    if Nexus.IsProgressActive and Nexus.IsProgressActive() then return end
    Nexus.Progress({
        label = label,
        duration = duration,
        icon = 'medkit',
        disableMovement = true,
        disableCarMovement = true,
        disableCombat = true,
    }, function(completed)
        if completed then thenFn() end
    end)
end

RegisterCommand('revive', function(_, args)
    if not isMedic() then
        Nexus.Notify('Only EMS may revive players.', 'error')
        return
    end
    local target = tonumber(args[1]) or nearestDownedPlayer(2.5)
    if not target then
        Nexus.Notify('No one nearby to revive.', 'error')
        return
    end
    doTreatment('Reviving patient…', EmsConfig.reviveTime, function()
        TriggerServerEvent('nx_ems:revive', target)
    end)
end, false)

RegisterCommand('treat', function(_, args)
    local target = tonumber(args[1]) or nearestPlayer(2.5)

    if not target then
        Nexus.Notify('No one nearby to treat.', 'error')
        return
    end

    if not isMedic() then
        if target ~= GetPlayerServerId(PlayerId()) then
            Nexus.Notify('You are not a paramedic.', 'error')
            return
        end
        doTreatment('Applying a bandage…', 3500, function()
            TriggerServerEvent('nx_ems:selfTreat')
        end)
        return
    end

    doTreatment('Treating patient…', EmsConfig.treatTime, function()
        TriggerServerEvent('nx_ems:treat', target, true)
    end)
end, false)

RegisterCommand('bandage', function()
    doTreatment('Applying a bandage…', 3500, function()
        TriggerServerEvent('nx_ems:selfTreat')
    end)
end, false)

RegisterCommand('hospital', function()
    TriggerServerEvent('nx_ems:requestHospitals')
end, false)

RegisterNetEvent('nexus:client:hospitalList', function(hospitals)
    local coords = GetEntityCoords(PlayerPedId())
    local nearest, distance = nil, math.huge
    for _, hospital in ipairs(hospitals) do
        local dist = #(coords - hospital.coords)
        if dist < distance then
            nearest, distance = hospital, dist
        end
    end
    if not nearest then return end

    Nexus.Confirm({
        title = 'Nearest hospital',
        message = ('%s is %.0f m away. Check in?'):format(nearest.label, distance),
        confirmLabel = 'Check in',
    }, function(confirmed)
        if confirmed then
            TriggerServerEvent('nx_ems:checkIn', nearest.name)
        end
    end)
end)

-- ===========================================================================
--  ALERTS
-- ===========================================================================

RegisterNetEvent('nx_ems:downAlert', function(alert)
    Nexus.Notify(('DOWN: %s (id %s)'):format(alert.name, alert.stateId), 'error', 12000, 'Ambulance')

    local coords = alert.coords
    if not coords then return end

    local blip = AddBlipForCoord(coords[1], coords[2], coords[3])
    SetBlipSprite(blip, 126)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.0)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('DOWN · %s'):format(alert.name))
    EndTextCommandSetBlipName(blip)

    SendNUIMessage({ action = 'alert', data = alert })

    SetTimeout(120000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- ===========================================================================
--  STRETCHER / CARRY
-- ===========================================================================

local carrying = nil

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Citizen.Wait(10)
    end
    return HasAnimDictLoaded(dict)
end

RegisterCommand('carry', function(_, args)
    if not isMedic() or not EmsConfig.allowStretcher then
        Nexus.Notify('Only EMS may carry patients.', 'error')
        return
    end

    if carrying then
        local ped = PlayerPedId()
        DetachEntity(carrying, true, true)
        SetEntityCoords(carrying, GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.2, 0.0))
        ClearPedTasks(ped)
        carrying = nil
        Nexus.Notify('Patient lowered.', 'info')
        return
    end

    local target = tonumber(args[1]) or nearestDownedPlayer(2.0)
    if not target then
        Nexus.Notify('No downed patient nearby.', 'error')
        return
    end

    local targetPed = GetPlayerPed(GetPlayerFromServerId(target))
    if not targetPed or not DoesEntityExist(targetPed) then return end

    loadAnimDict('missfinale_c2mcs_1')
    TaskPlayAnim(PlayerPedId(), 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 8.0, -8.0, -1, 49, 0, false, false, false)
    AttachEntityToEntity(targetPed, PlayerPedId(), 11816, 0.0, 0.6, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
    carrying = targetPed
    Nexus.Notify('Patient lifted.', 'success')
end, false)

CreateThread(function()
    while true do
        Citizen.Wait(1500)
        if carrying and not DoesEntityExist(carrying) then carrying = nil end
        if carrying then
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
        end
    end
end)

-- ===========================================================================
--  SUPPLIES
-- ===========================================================================

RegisterCommand('supplies', function()
    if not isMedic() then
        Nexus.Notify('Only EMS may use the supply room.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    local near = false
    for _, hospital in ipairs(EmsConfig.hospitals) do
        if #(coords - hospital.coords) < 30.0 then near = true end
    end
    if not near then
        Nexus.Notify('You are not at a hospital.', 'error')
        return
    end
    TriggerServerEvent('nx_ems:requestSupplies')
end, false)

RegisterCommand('emsloadout', function()
    TriggerServerEvent('nx_ems:requestLoadout')
end, false)

-- ===========================================================================
--  PATIENT CHARTS (MDT)
-- ===========================================================================

local function setMDT(state)
    mdtOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = mdtData })
end

RegisterNetEvent('nx_ems:openMDT', function(data)
    mdtData = data
    if not mdtOpen then
        setMDT(true)
    else
        SendNUIMessage({ action = 'update', data = data })
    end
end)

RegisterNetEvent('nx_ems:mdtResults', function(results)
    SendNUIMessage({ action = 'results', data = results })
end)

RegisterNetEvent('nx_ems:mdtChart', function(chart)
    SendNUIMessage({ action = 'chart', data = chart })
end)

RegisterNetEvent('nx_ems:mdtRefresh', function()
    TriggerServerEvent('nx_ems:openMDT')
end)

RegisterCommand('mdt', function()
    if not isMedic() then
        Nexus.Notify('Only EMS may use the medical terminal.', 'error')
        return
    end
    if mdtOpen then
        setMDT(false)
    else
        TriggerServerEvent('nx_ems:openMDT')
    end
end, false)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setMDT(false)
end)

RegisterNUICallback('nx:search', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_ems:mdtSearch', payload.query)
end)

RegisterNUICallback('nx:chart', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_ems:mdtChart', payload.charId)
end)

RegisterNUICallback('nx:note', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_ems:mdtNote', payload.charId, payload.title, payload.details)
end)

RegisterNUICallback('nx:call', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_ems:handleCall', payload.id)
end)

RegisterNUICallback('nx:waypoint', function(payload, cb)
    cb({ ok = true })
    local coords = payload.coords
    if type(coords) == 'table' and coords[1] then
        SetNewWaypoint(coords[1] + 0.0, coords[2] + 0.0)
    end
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_ems:openMDT')
end)

CreateThread(function()
    while true do
        Citizen.Wait(mdtOpen and 0 or 400)
        if mdtOpen then
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
    if mdtOpen then SetNuiFocus(false, false) end
end)

exports('isMedic', isMedic)
exports('openMDT', function() TriggerServerEvent('nx_ems:openMDT') end)
