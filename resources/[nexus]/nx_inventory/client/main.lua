--[[
    Nexus Framework :: nx_inventory/client/main.lua
    Opens the grid, drives the NUI, spawns ground bags and handles the hotbar.

    The client is deliberately dumb about contents: it renders whatever the
    server pushes and sends back intentions ("move slot 3 to trunk slot 7").
]]

local Nexus = Nexus
local Client = Nexus.Client

local open = false
local currentData = nil
local drops = {}          -- [dropId] = { coords, label, object }
local nearDrop = nil
local lastWeaponRequest = 0

-- ===========================================================================
--  UI CONTROL
-- ===========================================================================

local function setFocus(state)
    SetNuiFocus(state, state)
    open = state
    TriggerEvent('nexus:client:setUIOpen', state)

    if state then
        SendNUIMessage({ action = 'open', data = currentData })
    else
        SendNUIMessage({ action = 'close', data = {} })
    end
end

local function openInventory(owner, targetOwner, opts)
    currentData = nil
    TriggerServerEvent('nx_inv:requestOpen', owner, targetOwner, opts)
end

Nexus.OpenInventory = openInventory

--- Opens the player's own inventory.
local function openSelf()
    if open then
        setFocus(false)
        TriggerServerEvent('nx_inv:close')
        return
    end
    if not Client.isLoaded() then return end
    if Nexus.IsProgressActive and Nexus.IsProgressActive() then return end
    if Client.isDowned() then return end

    openInventory(('char:%s'):format(Client.getCharId()))
end

RegisterNetEvent('nexus:client:inventoryData', function(payload)
    currentData = payload
    if not payload then return end

    if not open then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = payload })
    end
end)

RegisterNetEvent('nx_inv:forceClose', function()
    if open then setFocus(false) end
end)

RegisterNetEvent('nexus:client:inventoryReady', function()
    -- ask what weapons we should be holding (reconnect / resource restart)
    TriggerServerEvent('nx_inv:syncWeapons')
end)

RegisterNetEvent(Nexus.Events.PLAYER_LOADED, function()
    Citizen.SetTimeout(1500, function()
        TriggerServerEvent('nx_inv:syncWeapons')
    end)
end)

--- Common openers used by other resources -----------------------------------

--- Trunk / glovebox of the vehicle the player is standing next to.
function Nexus.OpenVehicleStorage(kind)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsUsing(ped)
        if not vehicle or vehicle == 0 then
            -- nearest vehicle within reach
            local coords = GetEntityCoords(ped)
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 3.5, 0, 71)
        end
        if not vehicle or vehicle == 0 then
            Nexus.Notify('No vehicle nearby.', 'error')
            return
        end
    else
        Nexus.Notify('Get out of the vehicle first.', 'error')
        return
    end

    local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', '')
    if plate == '' then
        Nexus.Notify('That vehicle has no plate.', 'error')
        return
    end

    local kindKey = (kind == 'glove') and 'glove' or 'trunk'
    openInventory(('char:%s'):format(Client.getCharId()), ('%s:%s'):format(kindKey, plate), {
        vehicleNetId = VehToNet(vehicle),
    })
end

exports('openInventory', function(owner, targetOwner, opts)
    openInventory(owner, targetOwner, opts)
end)

exports('openSelf', function() openSelf() end)

exports('openStash', function(stashId)
    openInventory(('char:%s'):format(Client.getCharId()), ('stash:%s'):format(stashId))
end)

exports('openVehicleStorage', function(kind) Nexus.OpenVehicleStorage(kind) end)

exports('isOpen', function() return open end)

-- ===========================================================================
--  INPUT
-- ===========================================================================

RegisterCommand('inv', function() openSelf() end, false)
RegisterKeyMapping('inv', 'Nexus: open inventory', 'keyboard', 'F2')

--- Hotbar 1-5 (registered as separate commands so they show up in the keybinds
--- menu rather than fighting with the weapon wheel).
for slot = 1, 5 do
    RegisterCommand(('hotbar%d'):format(slot), function()
        if open or not Client.isLoaded() then return end
        TriggerServerEvent('nx_inv:hotbar', slot)
    end, false)
    RegisterKeyMapping(('hotbar%d'):format(slot), ('Nexus: use hotbar slot %d'):format(slot), 'keyboard', tostring(slot))
end

--- Give an item to the closest player.
RegisterCommand('give', function()
    if not Client.isLoaded() then return end
    TriggerEvent('nexus:client:inventory:givePrompt')
end, false)

RegisterNetEvent('nexus:client:inventory:givePrompt', function()
    local nearby = Client.getNearbyPlayers(3.0)
    if #nearby == 0 then
        Nexus.Notify('Nobody is close enough.', 'error')
        return
    end

    local options = {}
    for _, entry in ipairs(nearby) do
        options[#options + 1] = {
            label = ('%s (%s) · %.1fm'):format(entry.charName or entry.name, entry.stateId or entry.source, entry.distance),
            value = entry.source,
            icon = '⇄',
        }
    end

    Nexus.Menu({ title = 'Give to player', options = options }, function(targetSource)
        if targetSource then
            TriggerEvent('nexus:client:inventory:chooseSlotForGive', targetSource)
        end
    end)
end)

--- NUI can ask for the nearby player list when the user clicks "Give".
RegisterNUICallback('nx:giveList', function(_, cb)
    local list = {}
    for _, entry in ipairs(Client.getNearbyPlayers(3.0)) do
        list[#list + 1] = {
            source = entry.source,
            name = entry.charName or entry.name,
            stateId = entry.stateId or entry.source,
            distance = entry.distance,
        }
    end
    cb({ players = list })
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
    TriggerServerEvent('nx_inv:close')
end)

RegisterNUICallback('nx:move', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:move', data.from, data.fromSlot, data.to, data.toSlot, data.amount)
end)

RegisterNUICallback('nx:use', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:use', data.owner, data.slot)
end)

RegisterNUICallback('nx:drop', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:drop', data.owner, data.slot, data.amount)
end)

RegisterNUICallback('nx:split', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:split', data.owner, data.slot, data.amount)
end)

RegisterNUICallback('nx:quickMove', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:quickMove', data.owner, data.slot)
end)

RegisterNUICallback('nx:give', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:give', data.slot, data.amount, data.target)
end)

RegisterNUICallback('nx:pickup', function(data, cb)
    cb({ ok = true })
    if not data then return end
    TriggerServerEvent('nx_inv:pickup', data.dropId, data.slot, data.amount)
end)

RegisterNUICallback('nx:open', function(data, cb)
    cb({ ok = true })
    if not data then return end
    openInventory(data.self, data.other, data.opts)
end)

-- ===========================================================================
--  GROUND DROPS
-- ===========================================================================

local function createDropObject(drop)
    local coords = vector3(drop.coords[1], drop.coords[2], drop.coords[3])
    local model = GetHashKey(InvConfig.dropModel)
    RequestModel(model)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Citizen.Wait(10) end

    local object = CreateObject(model, coords.x, coords.y, coords.z + 0.15, false, false, false)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityAsMissionEntity(object, true, true)
    SetModelAsNoLongerNeeded(model)

    SetEntityName(object, drop.label or 'Bag')
    return object
end

RegisterNetEvent('nexus:client:addDrop', function(drop)
    if drops[drop.id] then return end
    local object = nil
    -- only spawn the prop when we are close-ish; the marker logic handles the rest
    if Client.isLoaded() then
        object = createDropObject(drop)
    end
    drops[drop.id] = { coords = drop.coords, label = drop.label, object = object }
end)

RegisterNetEvent('nexus:client:removeDrop', function(dropId)
    local entry = drops[dropId]
    if entry then
        if entry.object and DoesEntityExist(entry.object) then
            DeleteObject(entry.object)
        end
        drops[dropId] = nil
    end
    if nearDrop == dropId then nearDrop = nil end
end)

--- Proximity + interaction thread.
CreateThread(function()
    while true do
        local sleep = 750
        if Client.isLoaded() and not open then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local closest, closestDistance = nil, 999

            for id, entry in pairs(drops) do
                local dropCoords = vector3(entry.coords[1], entry.coords[2], entry.coords[3])
                local distance = #(coords - dropCoords)
                if distance < closestDistance and distance < 12.0 then
                    closest, closestDistance = id, distance
                end
            end

            if closest and closestDistance < 2.5 then
                sleep = 0
                local entry = drops[closest]
                Nexus.TextUI(true, 'E', ('Search %s'):format(entry.label or 'bag'))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    openInventory(('char:%s'):format(Client.getCharId()), ('drop:%s'):format(closest))
                end
                nearDrop = closest
            elseif nearDrop then
                Nexus.TextUI(false)
                nearDrop = nil
            end
        end
        Citizen.Wait(sleep)
    end
end)

--- Cursor / control handling while the grid is open ---------------------------

CreateThread(function()
    while true do
        local wait = open and 0 or 500
        Citizen.Wait(wait)
        if open then
            DisableControlAction(0, 1, true)     -- look
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)    -- attack
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 106, true)   -- vehicle mouse
            DisableControlAction(0, 199, true)   -- pause menu
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustPressed(0, 199) or IsDisabledControlJustPressed(0, 200) then
                setFocus(false)
                TriggerServerEvent('nx_inv:close')
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
    for _, entry in pairs(drops) do
        if entry.object and DoesEntityExist(entry.object) then DeleteObject(entry.object) end
    end
end)
