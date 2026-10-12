--[[
    Nexus Framework :: nx_spawn (client)
    Renders the spawn selector and resolves the choice (or the timeout) back to
    the server. Also owns the small "fade in from black" polish.
]]

local Nexus = Nexus

local uiOpen = false
local timeoutAt = 0
local lastData = nil

local function open(payload)
    lastData = payload
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = payload })
    TriggerEvent('nexus:client:spawnSelectorOpened')
end

local function close()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', data = {} })
    TriggerEvent('nexus:client:spawnSelectorClosed')
end

RegisterNetEvent('nexus:client:openSpawnSelector', function(payload)
    timeoutAt = GetGameTimer() + ((payload and payload.timeout) or 45000)
    open(payload)
end)

--- Hide the selector the moment nx_core tells us to spawn.
RegisterNetEvent('nexus:client:doSpawn', function()
    close()
end)

RegisterNUICallback('nx:spawn', function(data, cb)
    cb({ ok = true })
    close()
    TriggerServerEvent('nexus:server:chooseSpawn', data and data.key, data and data.useLastPosition == true)
end)

RegisterNUICallback('nx:spawnDefault', function(_, cb)
    cb({ ok = true })
    close()
    TriggerServerEvent('nexus:server:chooseSpawn', lastData and lastData.lastLocation, true)
end)

--- Server-side timeout safety net: if the UI is somehow never answered the
--- player would be stuck, so we fire the fallback ourselves.
CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if uiOpen and timeoutAt > 0 and GetGameTimer() > timeoutAt then
            timeoutAt = 0
            close()
            TriggerServerEvent('nexus:server:spawnTimeout')
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if uiOpen then SetNuiFocus(false, false) end
end)
