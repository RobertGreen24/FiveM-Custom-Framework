--[[
    Nexus Framework :: nx_police (client)
    Handcuffing, jail cells, radar and the MDT window.
]]

local Nexus = Nexus
local Client = Nexus.Client

local cuffed = false
local cuffedBy = nil
local jailed = false
local jailInfo = nil

local mdtOpen = false
local mdtData = nil
local searchResult = nil

-- ===========================================================================
--  HELPERS
-- ===========================================================================

local function isOfficer()
    local job = Client.getJob()
    return job.name == PoliceConfig.job or Client.isAdmin()
end

local function nearestPlayer(radius)
    local closest, distance = nil, radius or 3.0
    local coords = GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= PlayerPedId() and DoesEntityExist(ped) then
            local pedCoords = GetEntityCoords(ped)
            local dist = #(coords - pedCoords)
            if dist < distance then
                closest, distance = GetPlayerServerId(player), dist
            end
        end
    end
    return closest, distance
end

-- ===========================================================================
--  CUFFS
-- ===========================================================================

RegisterNetEvent('nx_police:cuffState', function(state, info)
    cuffed = state and true or false
    cuffedBy = state and info or nil

    if cuffed then
        Nexus.Notify(('You are cuffed by %s.'):format(info and info.officer or 'an officer'), 'warning', 6000)
    else
        Nexus.Notify('You are free to move.', 'info', 5000)
        ClearPedTasks(PlayerPedId())
    end
end)

RegisterNetEvent('nx_police:releasePlayer', function()
    local wasJailed = jailed
    cuffed = false
    jailed = false
    jailInfo = nil
    cuffedBy = nil
    FreezeEntityPosition(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    SendNUIMessage({ action = 'jail', data = { active = false } })
    if wasJailed then
        Nexus.Notify('You are free to go.', 'success', 7000, 'Police')
    end
end)

--- Cuffed players shuffle instead of running and cannot fight.
CreateThread(function()
    while true do
        local sleep = 500
        if cuffed then
            sleep = 0
            local ped = PlayerPedId()
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 140, true)  -- melee
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisablePlayerFiring(PlayerId(), true)
            SetPedConfigFlag(ped, 292, true)    -- not allowed to fight
            SetPedCanRagdoll(ped, true)
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  JAIL
-- ===========================================================================

local jailCell = { x = 461.4, y = -990.9, z = 24.9, w = 90.0 }

RegisterNetEvent('nx_police:jailPlayer', function(info)
    jailed = true
    jailInfo = info

    DoScreenFadeOut(600)
    Citizen.Wait(700)

    local ped = PlayerPedId()
    SetEntityCoords(ped, jailCell.x, jailCell.y, jailCell.z, false, false, false, true)
    SetEntityHeading(ped, jailCell.w)
    FreezeEntityPosition(ped, true)

    DoScreenFadeIn(600)
    Nexus.Notify(('Jailed for %d minute(s) · %s'):format(info.minutes, info.reason or ''), 'error', 10000, 'Police')
    SendNUIMessage({ action = 'jail', data = { active = true, minutes = info.minutes, reason = info.reason, fine = info.fine } })
end)

RegisterNetEvent('nx_police:blip', function(coords, label)
    if not coords then return end
    local blip = AddBlipForCoord(coords[1], coords[2], coords[3])
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Incident')
    EndTextCommandSetBlipName(blip)

    SetTimeout(90000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- ===========================================================================
--  MDT
-- ===========================================================================

local function setMDT(state)
    mdtOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = mdtData })
    if not state then
        SendNUIMessage({ action = 'jail', data = { active = jailed, minutes = jailInfo and jailInfo.minutes, reason = jailInfo and jailInfo.reason } })
    end
end

RegisterNetEvent('nx_police:openMDT', function(data)
    mdtData = data
    if not mdtOpen then
        setMDT(true)
    else
        SendNUIMessage({ action = 'update', data = data })
    end
end)

RegisterNetEvent('nx_police:mdtResults', function(results)
    SendNUIMessage({ action = 'results', data = results })
end)

RegisterNetEvent('nx_police:mdtProfile', function(profile)
    SendNUIMessage({ action = 'profile', data = profile })
end)

RegisterNetEvent('nx_police:mdtPlate', function(result)
    SendNUIMessage({ action = 'plate', data = result })
end)

RegisterNetEvent('nx_police:mdtRefresh', function()
    TriggerServerEvent('nx_police:openMDT')
end)

RegisterNetEvent('nx_police:searchResult', function(result)
    searchResult = result
    SendNUIMessage({ action = 'search', data = result })
    if not mdtOpen then
        Nexus.Notify(('%s · %d item(s) · $%d cash'):format(
            result.name or 'Subject', #(result.items or {}), tonumber(result.cash) or 0),
            'info', 8000, 'Search')
    end
end)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setMDT(false)
end)

RegisterNUICallback('nx:search', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:mdtSearch', payload.query)
end)

RegisterNUICallback('nx:profile', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:mdtProfile', payload.charId)
end)

RegisterNUICallback('nx:plate', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:mdtPlate', payload.plate)
end)

RegisterNUICallback('nx:warrant', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:addWarrant', payload.charId, payload.reason, payload.charges, payload.fine, payload.priority)
end)

RegisterNUICallback('nx:clearWarrant', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:clearWarrant', payload.id)
end)

RegisterNUICallback('nx:bolo', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:addBolo', payload)
end)

RegisterNUICallback('nx:clearBolo', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:clearBolo', payload.id)
end)

RegisterNUICallback('nx:incident', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:addIncident', payload)
end)

RegisterNUICallback('nx:closeIncident', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:closeIncident', payload.id, payload.note)
end)

RegisterNUICallback('nx:call', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:handleCall', payload.id)
end)

RegisterNUICallback('nx:jail', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:jail', payload.target, payload.minutes, payload.reason, payload.fine)
end)

RegisterNUICallback('nx:fine', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:fine', payload.target, payload.amount, payload.reason)
end)

RegisterNUICallback('nx:impound', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_police:impound', payload.plate, payload.reason)
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
    TriggerServerEvent('nx_police:openMDT')
end)

-- ===========================================================================
--  ALERTS
-- ===========================================================================

RegisterNetEvent('nx_police:dispatchAlert', function(alert)
    Nexus.Notify(('[%s] %s'):format(alert.code or '911', alert.message or 'Incident'), 'warning', 9000, 'Dispatch')

    local coords = alert.coords
    if coords then
        TriggerEvent('nx_police:blip', coords, alert.message)
        SendNUIMessage({
            action = 'dispatch',
            data = { message = alert.message, code = alert.code, coords = coords, priority = alert.priority },
        })
    end
end)

RegisterNetEvent('nx_police:backupAlert', function(alert)
    Nexus.Notify(('%s · %s requested %s'):format(alert.callsign or '?', alert.from, alert.kind), 'warning', 9000, 'Dispatch')
    if alert.coords then
        TriggerEvent('nx_police:blip', alert.coords, alert.kind)
    end
end)

RegisterNetEvent('nx_police:fineAdded', function(amount, reason)
    SendNUIMessage({ action = 'fine', data = { active = true, amount = amount, reason = reason } })
end)

-- ===========================================================================
--  COMMANDS
-- ===========================================================================

RegisterCommand(PoliceConfig.mdtCommand, function()
    if not isOfficer() then
        Nexus.Notify('Only the police may use the MDT.', 'error')
        return
    end
    if mdtOpen then
        setMDT(false)
    else
        TriggerServerEvent('nx_police:openMDT')
    end
end, false)

RegisterCommand('panic', function()
    if not isOfficer() then return end
    TriggerServerEvent('nx_police:panic')
end, false)

RegisterCommand('backup', function()
    if not isOfficer() then return end
    TriggerServerEvent('nx_police:backup', 'backup', GetEntityCoords(PlayerPedId()))
end, false)

RegisterCommand('cuff', function(_, args)
    if not isOfficer() then return end
    local target = tonumber(args[1]) or nearestPlayer(3.0)
    if not target then
        Nexus.Notify('No one nearby.', 'error')
        return
    end
    TriggerServerEvent('nx_police:cuff', target)
end, false)

RegisterCommand('search', function(_, args)
    if not isOfficer() then return end
    local target = tonumber(args[1]) or nearestPlayer(3.0)
    if not target then
        Nexus.Notify('No one nearby.', 'error')
        return
    end
    TriggerServerEvent('nx_police:search', target)
end, false)

RegisterCommand('jail', function(_, args)
    if not isOfficer() then return end
    local target = tonumber(args[1])
    local minutes = tonumber(args[2]) or 5
    local reason = table.concat(args, ' ', 3)

    if not target then
        target = nearestPlayer(4.0)
        if not target then
            Nexus.Notify('Usage: /jail [id] [minutes] [reason]', 'error')
            return
        end
    end
    TriggerServerEvent('nx_police:jail', target, minutes, reason)
end, false)

RegisterCommand('unjail', function(_, args)
    if not isOfficer() then return end
    TriggerServerEvent('nx_police:unjail', tonumber(args[1]))
end, false)

RegisterCommand('impound', function(_, args)
    if not isOfficer() then return end
    local plate = args[1]
    if not plate then
        Nexus.Notify('Usage: /impound [plate] [reason]', 'error')
        return
    end
    TriggerServerEvent('nx_police:impound', plate, table.concat(args, ' ', 2))
end, false)

RegisterCommand('takefines', function()
    TriggerServerEvent('nx_police:payFines')
end, false)

RegisterCommand('loadout', function()
    if not isOfficer() then return end
    TriggerServerEvent('nx_police:requestLoadout')
end, false)

-- ===========================================================================
--  NUI CONTROL BLOCKING
-- ===========================================================================

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

exports('isOfficer', isOfficer)
exports('isCuffed', function() return cuffed end)
exports('isJailed', function() return jailed end)
exports('openMDT', function() TriggerServerEvent('nx_police:openMDT') end)
