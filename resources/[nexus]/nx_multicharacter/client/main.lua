--[[
    Nexus Framework :: nx_multicharacter
    The character select screen. nx_core sends the account payload, we take over
    the camera and freeze the player, then hand the chosen char id back to the
    server, which loads it and asks nx_spawn where to put them.
]]

local Nexus = Nexus
local Client = Nexus.Client

local PREVIEW = {
    -- where the preview ped stands while the UI is open
    coords = vector3(-75.9, -818.6, 326.2),
    heading = 180.0,
    camera = {
        coords = vector3(-75.3, -821.4, 326.75),
        lookAt = vector3(-75.9, -818.6, 326.3),
    },
}

local uiOpen = false
local uiSettings = nil
local previewPed = nil
local characters = {}
local maxSlots = 4

-- ===========================================================================
--  HELPERS
-- ===========================================================================

local function requestModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Citizen.Wait(10)
    end
    return hash
end

local function startCamera()
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        PREVIEW.camera.coords.x, PREVIEW.camera.coords.y, PREVIEW.camera.coords.z,
        0.0, 0.0, 0.0, 42.0, false, 0)
    PointCamAtCoord(cam, PREVIEW.camera.lookAt.x, PREVIEW.camera.lookAt.y, PREVIEW.camera.lookAt.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 800, true, true)
    return cam
end

local function stopCamera(cam)
    if cam then
        RenderScriptCams(false, true, 700, true, true)
        DestroyCam(cam, false)
    end
end

--- Puts a dressed-up freemode ped on the preview spot so the select screen has
--- something to look at.
local function spawnPreviewPed(gender, appearance)
    local model = (gender == 1) and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    local hash = requestModel(model)

    local ped = CreatePed(4, hash, PREVIEW.coords.x, PREVIEW.coords.y, PREVIEW.coords.z,
        PREVIEW.heading, false, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCanBeDamaged(ped, false)

    local skin = appearance or {}
    if skin.components and next(skin.components) then
        for componentId, drawable in pairs(skin.components) do
            SetPedComponentVariation(ped, tonumber(componentId), drawable.drawable or 0, drawable.texture or 0, 0)
        end
    else
        SetPedRandomComponentVariation(ped, true)
    end
    SetPedRandomProps(ped)

    SetModelAsNoLongerNeeded(hash)
    previewPed = ped
    return ped
end

local function deletePreviewPed()
    if previewPed and DoesEntityExist(previewPed) then
        SetEntityAsMissionEntity(previewPed, false, true)
        DeleteEntity(previewPed)
    end
    previewPed = nil
end

-- ===========================================================================
--  UI
-- ===========================================================================

local function openUI()
    if uiOpen then return end
    uiOpen = true

    local ped = PlayerPedId()
    SetPlayerControl(PlayerId(), false, 0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCoordsNoOffset(ped, PREVIEW.coords.x, PREVIEW.coords.y, PREVIEW.coords.z, false, false, false)

    local cam = startCamera()
    spawnPreviewPed(0, nil)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = {
        characters = characters,
        maxSlots = maxSlots,
        nationalities = (Config.Multicharacter and Config.Multicharacter.nationalities) or { 'American' },
        account = Client.account,
    } })
    TriggerEvent('nexus:client:multicharacterOpened')

    uiSettings = { cam = cam }
end

local function closeUI()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close', data = {} })

    if uiSettings and uiSettings.cam then
        stopCamera(uiSettings.cam)
    end
    uiSettings = nil
    deletePreviewPed()

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
    FreezeEntityPosition(ped, false)
    TriggerEvent('nexus:client:multicharacterClosed')
end

--- Refreshes the list without rebuilding the camera (after create/delete).
local function refreshUI()
    SendNUIMessage({ action = 'update', data = {
        characters = characters,
        maxSlots = maxSlots,
    } })
end

-- ===========================================================================
--  EVENTS
-- ===========================================================================

RegisterNetEvent('nexus:client:accountLoaded', function(account)
    characters = account.characters or {}
    maxSlots = account.maxSlots or 4

    if not (Config.Multicharacter and Config.Multicharacter.enabled) then
        -- no select screen: jump straight into the first character
        if characters[1] then
            TriggerServerEvent('nexus:server:loadCharacter', characters[1].id)
        else
            Nexus.Notify('You have no character and the select screen is disabled.', 'error', 10000)
        end
        return
    end

    Citizen.SetTimeout(500, openUI)
end)

RegisterNetEvent('nexus:client:characterList', function(list, slots)
    characters = list or {}
    maxSlots = slots or maxSlots
    if not uiOpen then
        -- e.g. after /switch: bring the screen back up
        Citizen.SetTimeout(100, openUI)
    else
        refreshUI()
    end
end)

RegisterNetEvent('nexus:client:characterCreated', function(charId, slot, stateId)
    Nexus.Notify('Character created. Welcome to the city.', 'success', 6000, 'Nexus')
    -- straight into the appearance creator if it is installed, otherwise spawn
    if GetResourceState('nx_appearance') == 'started' then
        TriggerEvent('nexus:client:appearance:create', charId)
        TriggerServerEvent('nexus:server:loadCharacter', charId)
    else
        TriggerServerEvent('nexus:server:creationComplete')
    end
end)

RegisterNetEvent('nexus:client:characterLoadFailed', function(err)
    Nexus.Notify(err or 'Could not load that character.', 'error', 7000)
end)

RegisterNetEvent('nexus:client:characterCreateFailed', function(err)
    SendNUIMessage({ action = 'createFailed', data = { message = err } })
    Nexus.Notify(err or 'Could not create that character.', 'error', 7000)
end)

RegisterNetEvent(Nexus.Events.PLAYER_LOADED, function()
    if uiOpen then closeUI() end
end)

RegisterNetEvent(Nexus.Events.RESPAWN, function()
    if uiOpen then closeUI() end
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:select', function(data, cb)
    cb({ ok = true })
    local charId = tonumber(data and data.charId)
    if not charId then return end

    local entry
    for _, character in ipairs(characters) do
        if tonumber(character.id) == charId then
            entry = character
            break
        end
    end
    if entry then
        closeUI()
        spawnPreviewPed(tonumber(entry.gender) or 0, nil)
    end
    TriggerServerEvent('nexus:server:loadCharacter', charId)
end)

RegisterNUICallback('nx:create', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('nexus:server:createCharacter', data or {})
end)

RegisterNUICallback('nx:delete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('nexus:server:deleteCharacter', tonumber(data and data.charId))
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('nexus:server:requestCharacterList')
end)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    -- closing the select screen without choosing is only allowed post-spawn
    if Client.isLoaded() then closeUI() end
end)

--- /switch returns to the select screen.
RegisterCommand('switch', function()
    if not Client.isLoaded() then return end
    Nexus.Confirm({ title = 'Switch character', message = 'Return to the character select screen?' }, function(confirmed)
        if confirmed then
            TriggerServerEvent('nexus:server:switchCharacter')
        end
    end)
end, false)
