--[[
    Nexus Framework :: nx_banking (client)
    ATM and bank-counter interaction, blips and the NUI session.
]]

local Nexus = Nexus
local Client = Nexus.Client

local uiOpen = false
local currentLocation = nil
local lastData = nil

-- ===========================================================================
--  BLIPS
-- ===========================================================================

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in ipairs(BankConfig.blips or {}) do
        local blip = AddBlipForCoord(entry.coords.x, entry.coords.y, entry.coords.z)
        SetBlipSprite(blip, entry.sprite or 108)
        SetBlipColour(blip, entry.colour or 2)
        SetBlipScale(blip, 0.75)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(entry.label or 'Bank')
        EndTextCommandSetBlipName(blip)
    end
end)

-- ===========================================================================
--  UI
-- ===========================================================================

local function setFocus(state)
    uiOpen = state
    SetNuiFocus(state, state)
    TriggerEvent('nexus:client:setUIOpen', state)
    SendNUIMessage({ action = state and 'open' or 'close', data = lastData })
    if not state then
        TriggerServerEvent('nx_banking:close')
    end
end

RegisterNetEvent('nexus:client:bankData', function(data)
    lastData = data
    if not uiOpen then
        setFocus(true)
    else
        SendNUIMessage({ action = 'update', data = data })
    end
end)

RegisterNetEvent('nx_banking:openUI', function(locationName)
    currentLocation = locationName or 'legacy_bank'
    TriggerServerEvent('nx_banking:open', currentLocation)
end)

-- ===========================================================================
--  INTERACTION
-- ===========================================================================

local function closestLocation()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance = nil, 2.0
    for _, location in ipairs(BankLocations) do
        local distance = #(coords - location.coords)
        if distance < bestDistance then
            best, bestDistance = location, distance
        end
    end
    return best
end

CreateThread(function()
    while true do
        local sleep = 600
        if Client.isLoaded() and not uiOpen then
            local location = closestLocation()
            if location then
                sleep = 0
                Nexus.TextUI(true, 'E', ('Use %s'):format(location.label))
                if IsControlJustPressed(0, 38) then
                    Nexus.TextUI(false)
                    currentLocation = location.name
                    TriggerServerEvent('nx_banking:open', location.name)
                end
            else
                Nexus.TextUI(false)
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ===========================================================================
--  COMMANDS
-- ===========================================================================

RegisterCommand('bank', function()
    local location = closestLocation()
    if not location then
        Nexus.Notify('You are not near a bank or ATM.', 'error')
        return
    end
    currentLocation = location.name
    TriggerServerEvent('nx_banking:open', location.name)
end, false)

--- Quick cash transfer: /transfer <phone|id|name> <amount>
RegisterCommand('transfer', function(_, args)
    local target, amount = args[1], tonumber(args[2])
    if not target or not amount then
        Nexus.Notify('Usage: /transfer [phone or id] [amount]', 'error')
        return
    end
    TriggerServerEvent('nx_banking:transfer', 'bank', target, amount)
end, false)

--- /paycash <id> <amount> hands physical cash over.
RegisterCommand('paycash', function(_, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount then
        Nexus.Notify('Usage: /paycash [id] [amount]', 'error')
        return
    end
    TriggerServerEvent('nx_banking:giveCash', target, amount)
end, false)

--- /charge <id> <amount> <reason> — used by businesses (bills, fees).
RegisterCommand('charge', function(_, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    local reason = table.concat(args, ' ', 3)
    if not target or not amount then return end
    TriggerServerEvent('nx_banking:requestCharge', target, amount, reason)
end, false)

RegisterNetEvent('nx_banking:chargePrompt', function(fromSource, amount, reason)
    Nexus.Confirm({
        title = 'Payment request',
        message = ('%s is requesting %s%s'):format(
            Player(fromSource).state.nx_name or ('player ' .. fromSource),
            Nexus.Utils.formatMoney(amount),
            reason and reason ~= '' and ('\n' .. reason) or ''),
        confirmLabel = 'Pay',
    }, function(confirmed)
        TriggerServerEvent('nx_banking:respondCharge', fromSource, amount, reason, confirmed)
    end)
end)

-- ===========================================================================
--  NUI CALLBACKS
-- ===========================================================================

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setFocus(false)
end)

RegisterNUICallback('nx:deposit', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_banking:deposit', data.account, data.amount)
end)

RegisterNUICallback('nx:withdraw', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_banking:withdraw', data.account, data.amount)
end)

RegisterNUICallback('nx:transfer', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_banking:transfer', data.account, data.target, data.amount, data.note)
end)

RegisterNUICallback('nx:refresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_banking:refresh')
end)

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
end)

exports('openBank', function() ExecuteCommand('bank') end)
exports('isOpen', function() return uiOpen end)
