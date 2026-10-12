--[[
    Nexus Framework :: nx_chat (server)
    Channel routing, ranges, cooldowns and the 911/311 dispatch hook.
]]

Nexus = Nexus or {}

local lastAdvert = {}       -- [charId] = os.time()
local lastTweet = {}        -- [charId] = os.time()
local lastReport = {}       -- [source] = os.time()

local function withinRange(a, b, range)
    if not range or range <= 0 then return true end
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or not pb or pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= range
end

--- Sends a chat line globally. `author` is what players see as the speaker.
local function broadcast(channelId, author, text, colour)
    TriggerClientEvent('nx_chat:push', -1, {
        channel = channelId,
        author = author or 'Server',
        text = text,
        colour = colour,
        time = os.date('%H:%M'),
    })
end

-- ===========================================================================
--  CHAT MESSAGES
-- ===========================================================================

RegisterNetEvent('nx_chat:message', function(channelId, text)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    text = tostring(text or ''):sub(1, ChatConfig.maxLength)
    text = text:gsub('[\n\r]', ' ')
    if text:match('^%s*$') then return end

    channelId = tostring(channelId or 'local')

    if channelId == 'ooc' then
        broadcast('ooc', player:getName(), '(( ' .. text .. ' ))', 0)
        return
    end

    if channelId == 'me' or channelId == 'do' then
        local payload = {
            channel = channelId, author = player:getName(), text = text,
            time = os.date('%H:%M'),
        }
        local range = channelId == 'me' and ChatConfig.ranges.me or ChatConfig.ranges.do_
        for _, target in ipairs(GetPlayers()) do
            local id = tonumber(target)
            if id and withinRange(id, source, range) then
                TriggerClientEvent('nx_chat:push', id, payload)
            end
        end
        return
    end

    if channelId == 'whisper' then
        local payload = { channel = 'whisper', author = player:getName(), text = text, time = os.date('%H:%M') }
        TriggerClientEvent('nx_chat:push', source, payload)

        -- anyone within 3m overhears a whisper
        for _, target in ipairs(GetPlayers()) do
            local id = tonumber(target)
            if id ~= source and id and withinRange(id, source, ChatConfig.ranges.whisper) then
                TriggerClientEvent('nx_chat:push', id, {
                    channel = 'whisper', author = player:getName(),
                    text = ('(whispering) %s'):format(text), time = os.date('%H:%M'),
                })
            end
        end
        return
    end

    if channelId == 'shout' then
        local payload = {
            channel = 'shout', author = player:getName(), text = text:upper(),
            time = os.date('%H:%M'),
        }
        for _, target in ipairs(GetPlayers()) do
            local id = tonumber(target)
            if id and withinRange(id, source, ChatConfig.ranges.shout) then
                TriggerClientEvent('nx_chat:push', id, payload)
            end
        end
        return
    end

    if channelId == 'ad' then
        if not ChatConfig.advert.enabled then return end

        local last = lastAdvert[player.charId] or 0
        if (os.time() - last) < ChatConfig.advert.cooldown then
            player:notify(('Wait %d more seconds before advertising again.'):format(
                ChatConfig.advert.cooldown - (os.time() - last)), 'error')
            return
        end

        local cost = ChatConfig.advert.cost or 0
        if cost > 0 and not player:removeMoney('bank', cost, 'advertisement') then
            player:notify(('Advertising costs %s.'):format(Nexus.Utils.formatMoney(cost)), 'error')
            return
        end

        lastAdvert[player.charId] = os.time()
        broadcast('ad', ('[%s] %s'):format(ChatConfig.advert.prefix, player:getName()), text, 0)
        return
    end

    if channelId == 'twt' then
        if not ChatConfig.twitter.enabled then return end

        local last = lastTweet[player.charId] or 0
        if (os.time() - last) < ChatConfig.twitter.cooldown then
            player:notify('You are posting too quickly.', 'error')
            return
        end
        lastTweet[player.charId] = os.time()

        local handle = player:getMeta('twitter', nil)
        if not handle then
            handle = '@' .. player:getName():gsub('%s+', ''):lower()
            player:setMeta('twitter', handle)
        end

        broadcast('twt', handle, text, 0)
        TriggerEvent('nx_phone:newTweet', { handle = handle, text = text, charId = player.charId })
        return
    end

    if channelId == 'dispatch' then
        if player.job.type ~= 'leo' and player.job.type ~= 'ems' and not player:can('nexus.admin') then
            player:notify('You are not on a dispatch channel.', 'error')
            return
        end
        local tag = player.callsign and ('%s %s'):format(player.job.label, player.callsign) or player.job.label
        broadcast('dispatch', tag, text, 0)
        return
    end

    if channelId == 'staff' then
        if not player:can('nexus.admin') then return end
        for _, other in ipairs(Nexus.GetPlayers()) do
            if other:can('nexus.admin') then
                TriggerClientEvent('nx_chat:push', other.source, {
                    channel = 'staff', author = ('[STAFF] %s'):format(player:getName()),
                    text = text, time = os.date('%H:%M'),
                })
            end
        end
        return
    end

    -- default: local roleplay chat ("says" + distance attenuation)
    local payload = {
        channel = 'local', author = player:getName(), text = text,
        time = os.date('%H:%M'), whisper = #text < 40,
    }
    for _, target in ipairs(GetPlayers()) do
        local id = tonumber(target)
        if id and withinRange(id, source, ChatConfig.ranges.local_) then
            TriggerClientEvent('nx_chat:push', id, payload)
        end
    end
end)

-- ===========================================================================
--  EMERGENCY CALLS
-- ===========================================================================

RegisterNetEvent('nx_chat:emergency', function(service, message)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    message = tostring(message or ''):sub(1, 200)
    if message:match('^%s*$') then
        player:notify('Describe the emergency.', 'error')
        return
    end

    local coords = player:getCoords()
    local serviceName = service == '311' and 'police' or (service == 'mechanic' and 'mechanic' or (service or 'police'))

    local call = {
        caller = player:getName(),
        number = tostring(player.stateId or player.charId or 'unknown'),
        service = serviceName,
        message = message,
        coords = ('{"x":%.2f,"y":%.2f,"z":%.2f}'):format(coords.x, coords.y, coords.z),
    }

    -- route to the right department (nx_police / nx_ems listen for these)
    if service == '311' then
        TriggerEvent('nx_police:registerCall', call)
    elseif serviceName == 'police' then
        TriggerEvent('nx_police:registerCall', call)
        TriggerEvent('nx_ems:call', call)
    else
        TriggerEvent('nx_ems:call', call)
    end

    player:notify(('%s call placed.'):format(serviceName == 'ambulance' and 'Medical' or 'Emergency'), 'info', 6000)
end)

--- Departments use this to answer a call in the chat.
RegisterNetEvent('nx_chat:departmentMessage', function(service, message)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if player.job.type ~= 'leo' and player.job.type ~= 'ems' and not player:can('nexus.admin') then return end

    TriggerClientEvent('nx_chat:push', -1, {
        channel = 'dispatch',
        author = service == 'police' and 'LSPD' or (service == 'ambulance' and 'EMS' or 'Dispatch'),
        text = message,
        time = os.date('%H:%M'),
    })
end)

RegisterNetEvent('nx_chat:report', function(targetSource, reason)
    local source = source
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end

    if (os.time() - (lastReport[source] or 0)) < 60 then
        player:notify('You can only report once a minute.', 'error')
        return
    end
    lastReport[source] = os.time()

    local target = Nexus.GetPlayer(tonumber(targetSource))
    local line = ('%s reported %s: %s'):format(
        player:getName(), target and target:getName() or 'unknown', tostring(reason or 'no reason'):sub(1, 160))

    for _, staff in ipairs(Nexus.GetPlayers()) do
        if staff:can('nexus.admin.helper') or staff:can('nexus.admin') then
            staff:notify(line, 'warning', 10000, 'Report')
        end
    end

    Nexus.Log.action('player_report', {
        actor = player:getName(), target = target and target:getName() or 'unknown', details = reason,
        colour = 0xf59e0b,
    })
    player:notify('Your report was sent to the staff team.', 'success')
end)

-- ===========================================================================
--  ANNOUNCEMENTS
-- ===========================================================================

CreateThread(function()
    if not ChatConfig.announcements.enabled then return end
    local index = 1
    while true do
        Citizen.Wait(ChatConfig.announcements.interval * 1000)
        local messages = ChatConfig.announcements.messages
        if #messages > 0 then
            TriggerClientEvent('nx_chat:push', -1, {
                channel = 'system', author = 'Nexus',
                text = messages[index], time = os.date('%H:%M'),
            })
            index = (index % #messages) + 1
        end
    end
end)

exports('broadcast', function(channelId, author, text)
    TriggerClientEvent('nx_chat:push', -1, {
        channel = channelId or 'system', author = author or 'Server',
        text = text, time = os.date('%H:%M'),
    })
end)

exports('announce', function(text)
    TriggerClientEvent('nx_chat:push', -1, {
        channel = 'system', author = 'Announcement', text = text, time = os.date('%H:%M'), kind = 'announce',
    })
end)
