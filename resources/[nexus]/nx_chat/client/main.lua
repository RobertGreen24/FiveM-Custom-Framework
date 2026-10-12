--[[
    Nexus Framework :: nx_chat (client)
    The chat box, slash commands and the channel switcher.
]]

local Nexus = Nexus
local Client = Nexus.Client

local open = false
local history = {}
local historyIndex = 0
local activeChannel = 'local'
local muted = false

-- ===========================================================================
--  UI
-- ===========================================================================

local function setOpen(state)
    open = state
    SetNuiFocus(state, state)
    SendNUIMessage({
        action = state and 'open' or 'close',
        data = {
            channels = ChatChannels,
            suggestions = ChatConfig.suggestions and Nexus.ChatCommands or {},
            timestamps = ChatConfig.timestamps,
            maxLength = ChatConfig.maxLength,
            advertCost = ChatConfig.advert.cost,
            history = history,
            channel = activeChannel,
        },
    })
    if not state and Nexus.TextUI then
        Nexus.TextUI(false)
    end
end

RegisterNetEvent('nx_chat:push', function(payload)
    local local_ = payload.channel == 'local' or payload.channel == 'me' or payload.channel == 'do'
    SendNUIMessage({
        action = 'message',
        data = {
            channel = payload.channel,
            author = payload.author,
            text = payload.text,
            kind = payload.kind,
            colour = payload.colour,
            whisper = payload.whisper,
            ['local'] = local_,
            time = ChatConfig.timestamps and (payload.time or os.date('%H:%M')) or nil,
        },
    })

    if muted then return end

    -- a subtle animation cue for local chatter so it is not missed
    if local_ and not open then
        PlaySoundFrontend(-1, 'Text_Message_Alert', 'GTAO_FM_Events_Soundset', true)
    end
end)

RegisterNUICallback('nx:close', function(_, cb)
    cb({ ok = true })
    setOpen(false)
end)

RegisterNUICallback('nx:send', function(payload, cb)
    cb({ ok = true })
    local text = tostring(payload.text or ''):sub(1, ChatConfig.maxLength)
    if text:match('^%s*$') then
        setOpen(false)
        return
    end

    table.insert(history, 1, text)
    while #history > ChatConfig.maxHistory do table.remove(history) end
    historyIndex = 0

    local channel = payload.channel or activeChannel
    if channel == 'all' then channel = 'local' end
    activeChannel = channel

    TriggerServerEvent('nx_chat:message', channel, text)
    setOpen(false)
end)

RegisterNUICallback('nx:channel', function(payload, cb)
    cb({ ok = true })
    activeChannel = payload.channel or 'local'
end)

RegisterNUICallback('nx:emergency', function(payload, cb)
    cb({ ok = true })
    TriggerServerEvent('nx_chat:emergency', payload.service, payload.message)
end)

-- ===========================================================================
--  INPUT
-- ===========================================================================

RegisterCommand('+nxChat', function() if not open then setOpen(true) end end, false)
RegisterCommand('-nxChat', function() end, false)
RegisterKeyMapping('+nxChat', 'Open chat', 'keyboard', ChatConfig.key or 'T')

--- Quick slash commands (T is chat, these save typing).
local function chatCommand(channel)
    return function(_, args)
        local text = table.concat(args, ' ')
        if text == '' then
            activeChannel = channel
            setOpen(true)
        else
            TriggerServerEvent('nx_chat:message', channel, text)
        end
    end
end

RegisterCommand('me', chatCommand('me'), false)
RegisterCommand('do', chatCommand('do'), false)
RegisterCommand('ooc', chatCommand('ooc'), false)
RegisterCommand('whisper', chatCommand('whisper'), false)
RegisterCommand('shout', function(_, args)
    TriggerServerEvent('nx_chat:message', 'shout', table.concat(args, ' '))
end, false)
RegisterCommand('ad', chatCommand('ad'), false)
RegisterCommand('twt', chatCommand('twt'), false)
RegisterCommand('dispatch', chatCommand('dispatch'), false)
RegisterCommand('staff', chatCommand('staff'), false)

RegisterCommand('911', function(_, args)
    TriggerServerEvent('nx_chat:emergency', 'police', table.concat(args, ' '))
end, false)

RegisterCommand('311', function(_, args)
    TriggerServerEvent('nx_chat:emergency', '311', table.concat(args, ' '))
end, false)

RegisterCommand('ems', function(_, args)
    TriggerServerEvent('nx_chat:emergency', 'ambulance', table.concat(args, ' '))
end, false)

RegisterCommand('report', function(_, args)
    local target = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not target then
        Nexus.Notify('Usage: /report [id] [reason]', 'error')
        return
    end
    TriggerServerEvent('nx_chat:report', target, reason)
end, false)

RegisterCommand('commands', function()
    local lines = {}
    for _, command in ipairs(Nexus.ChatCommands) do
        lines[#lines + 1] = ('%s — %s'):format(command.name, command.description)
    end
    SendNUIMessage({ action = 'message', data = {
        channel = 'system', author = 'Commands', text = table.concat(lines, '\n'), multiline = true,
    } })
    SendNUIMessage({ action = 'open', data = {
        channels = ChatChannels,
        suggestions = ChatConfig.suggestions and Nexus.ChatCommands or {},
        timestamps = ChatConfig.timestamps,
        maxLength = ChatConfig.maxLength,
        advertCost = ChatConfig.advert.cost,
        history = history,
        channel = activeChannel,
        browsing = true,
    } })
    open = true
    SetNuiFocus(true, true)
end, false)

RegisterCommand('clearchat', function()
    SendNUIMessage({ action = 'clear' })
end, false)

RegisterCommand('mutetchat', function()
    muted = not muted
    Nexus.Notify(muted and 'Chat muted.' or 'Chat unmuted.', 'info')
end, false)

-- ===========================================================================
--  KEYBINDS
-- ===========================================================================

--- Page up / page down scrolls the chat while it is open.
CreateThread(function()
    while true do
        Citizen.Wait(open and 0 or 300)
        if open then
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
    if open then SetNuiFocus(false, false) end
end)

exports('send', function(channel, text) TriggerServerEvent('nx_chat:message', channel or 'local', text) end)
exports('push', function(payload)
    payload.channel = payload.channel or 'system'
    SendNUIMessage({ action = 'message', data = payload })
end)
exports('isOpen', function() return open end)
