--[[
    Nexus Framework :: client/main.lua
    Connection-side behaviour: fallback spawn handling, position sync, resource
    pausing while the player is on the character select screen.
]]

Nexus = Nexus or {}
local Client = Nexus.Client

local SPAWN_SELECT_FALLBACK_WAIT = 1500   -- ms to let nx_spawn take over

-- ===========================================================================
--  SPAWN
-- ===========================================================================

--- Called by the server (or nx_spawn) once a location is decided.
---@param data table { x, y, z, w, spawnKey, isDead }
RegisterNetEvent('nexus:client:doSpawn', function(data)
    local ped = PlayerPedId()

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Citizen.Wait(10) end

    RequestCollisionAtCoord(data.x, data.y, data.z)
    SetEntityCoordsNoOffset(ped, data.x + 0.0, data.y + 0.0, data.z + 0.0, false, false, false)
    SetEntityHeading(ped, data.w + 0.0)
    NetworkResurrectLocalPlayer(data.x, data.y, data.z, data.w, true, false)
    SetPlayerInvincible(PlayerId(), false)
    ClearPedBloodDamage(ped)
    FreezeEntityPosition(ped, true)

    -- wait for the world under our feet
    local timeout = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(data.x, data.y, data.z)
        Citizen.Wait(50)
    end

    Client.spawned = true
    LocalPlayer.state:set('nx_spawned', true, false)
    TriggerEvent('nexus:client:spawned', data)
    Client.emit('spawned', data)

    Citizen.SetTimeout(400, function()
        FreezeEntityPosition(PlayerPedId(), false)
        ShutdownLoadingScreen()
        DoScreenFadeIn(750)
    end)

    if data.isDead then
        TriggerEvent('nexus:client:downed', 'respawn')
    end
end)

--- Fallback spawn: if nx_spawn is not installed, just place the player at their
--- last known location (the server already decided it).
RegisterNetEvent('nexus:client:prepareSpawn', function(data)
    Citizen.SetTimeout(SPAWN_SELECT_FALLBACK_WAIT, function()
        if GetResourceState('nx_spawn') == 'started' then return end
        TriggerServerEvent('nexus:server:requestSpawn')
    end)
end)

--- Teleporting from the server (admin /goto, /bring, job scripts).
RegisterNetEvent('nexus:client:teleport', function(coords, keepVehicle)
    local ped = PlayerPedId()
    if not coords or not coords.x then return end

    local entity = ped
    if keepVehicle and IsPedInAnyVehicle(ped, false) then
        entity = GetVehiclePedIsIn(ped, false)
    end

    DoScreenFadeOut(200)
    while not IsScreenFadedOut() do Citizen.Wait(10) end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(entity, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false, keepVehicle == true)
    if keepVehicle and entity ~= ped then
        SetPedIntoVehicle(ped, entity, -1)
    end

    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Citizen.Wait(50)
    end

    DoScreenFadeIn(400)
    Nexus.Client.emit('teleported', coords)
end)

-- ===========================================================================
--  POSITION SYNC (server keeps a copy for blip/dispatch/PanelData)
-- ===========================================================================

CreateThread(function()
    local lastSent = 0
    while true do
        Citizen.Wait(5000)
        if Client.loaded and Client.spawned then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local heading = GetEntityHeading(ped)
                -- only push when we actually moved, or every 60s as a heartbeat
                if not lastSent or GetGameTimer() - lastSent > 60000 or
                    #(coords - (Client.lastCoords or coords)) > 1.0 then
                    Client.lastCoords = coords
                    lastSent = GetGameTimer()
                    TriggerServerEvent('nexus:server:setPosition', coords.x, coords.y, coords.z, heading)
                end
            end
        end
    end
end)

-- ===========================================================================
--  FREEZE / SPECTATE / MISC ADMIN EVENTS
-- ===========================================================================

local frozen = false

RegisterNetEvent('nexus:client:freeze', function(state)
    frozen = state == true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, frozen)
    if IsPedInAnyVehicle(ped, false) then
        FreezeEntityPosition(GetVehiclePedIsIn(ped, false), frozen)
    end
end)

CreateThread(function()
    -- re-apply freeze every frame while frozen (some scripts unfreeze peds)
    while true do
        local wait = frozen and 100 or 1500
        Citizen.Wait(wait)
        if frozen then
            local ped = PlayerPedId()
            SetPlayerControl(PlayerId(), false, 0)
        end
    end
end)

local spectating = false

RegisterNetEvent('nexus:client:spectate', function(targetSource)
    if not targetSource then
        if spectating then
            local ped = PlayerPedId()
            NetworkSetInSpectatorMode(false, ped)
            SetEntityVisible(ped, true, false)
            spectating = false
        end
        return
    end

    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetSource))
    if targetPed == 0 then return end

    spectating = true
    NetworkSetInSpectatorMode(true, targetPed)

    CreateThread(function()
        while spectating do
            Citizen.Wait(0)
            if not DoesEntityExist(targetPed) then
                NetworkSetInSpectatorMode(false, PlayerPedId())
                spectating = false
                break
            end
            local coords = GetEntityCoords(targetPed)
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z + 0.5, false, false, false, false)
        end
    end)
end)

RegisterNetEvent('nexus:client:clearEffects', function()
    local ped = PlayerPedId()
    ClearPedBloodDamage(ped)
    ClearPedDamageDecalByZone(ped, 10, 'ALL')
    SetPedMotionBlur(ped, false)
    ClearTimecycleModifier()
    StopScreenEffect('DrugsMichaelAliensFight')
    ResetScenarioTypesEnabled()
    ResetPlayerStamina(PlayerId())
end)

RegisterNetEvent('nexus:client:setHealth', function(health, armour)
    local ped = PlayerPedId()
    if health then SetEntityHealth(ped, math.floor(health)) end
    if armour then SetPedArmour(ped, math.floor(armour)) end
end)

-- ===========================================================================
--  RESOURCE LIFECYCLE
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- tell the server who we are so it can re-send our character list after a
    -- client-side restart
    Citizen.SetTimeout(1000, function()
        TriggerServerEvent('nexus:server:playerReady')
    end)
end)

--- Keep the game paused while the select/creator screens are up.
--- Resources that render full-screen UI can opt in by triggering
--- 'nexus:client:setUIOpen', true/false.
local uiOpen = false

RegisterNetEvent('nexus:client:setUIOpen', function(state)
    uiOpen = state == true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, uiOpen)
    if uiOpen then
        SetPlayerControl(PlayerId(), false, 0)
    else
        SetPlayerControl(PlayerId(), true, 0)
    end
end)
