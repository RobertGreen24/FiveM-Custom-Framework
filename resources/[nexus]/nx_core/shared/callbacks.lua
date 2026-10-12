--[[
    Nexus Framework :: shared/callbacks.lua
    Lightweight request/response over latent events, both directions.

    Server:
        Nexus.RegisterServerCallback('nx_core:payPhoneBill', function(source, cb, amount)
            cb(true)
        end)

    Client:
        Nexus.TriggerServerCallback('nx_core:payPhoneBill', function(ok)
            print(ok)
        end, 250)

    Server -> client request:
        Nexus.TriggerClientCallback('nx_inventory:openTrunk', source, function(result)
        end, vehicle)

    Every request is rate limited per player and times out rather than leaking a
    dangling callback, so a misbehaving resource can't hang a player's session.
]]

Nexus = Nexus or {}

local TIMEOUT = 15000        -- ms before we give up on a response
local RATE_LIMIT_MAX = 60    -- requests
local RATE_LIMIT_WINDOW = 1000

local serverCallbacks = {}   -- name -> fn(source, cb, ...)      [server side]
local clientCallbacks = {}   -- name -> fn(cb, ...)              [client side]
local pendingServer = {}     -- id -> { cb, source, timer }      [client waiting on server]
local pendingClient = {}     -- id -> { cb, timer }              [server waiting on client]

local requestCounter = 0
local buckets = {}           -- source -> { count, since }

local function nextId()
    requestCounter = requestCounter + 1
    if requestCounter > 2 ^ 31 then requestCounter = 1 end
    return requestCounter
end

local function rateLimited(source)
    local now = GetGameTimer()
    local bucket = buckets[source]
    if not bucket or (now - bucket.since) > RATE_LIMIT_WINDOW then
        buckets[source] = { count = 1, since = now }
        return false
    end
    bucket.count = bucket.count + 1
    if bucket.count > RATE_LIMIT_MAX then
        Nexus.Print.warn('Rate limit hit for source %s (callbacks).', source)
        return true
    end
    return false
end

-- ===========================================================================
--  SERVER SIDE
-- ===========================================================================

if Nexus.IsServer then

    function Nexus.RegisterServerCallback(name, fn)
        if type(name) ~= 'string' or type(fn) ~= 'function' then
            print('^1[nx_core]^7 RegisterServerCallback: expects (string, function)')
            return
        end
        if serverCallbacks[name] then
            Nexus.Print.warn('Overwriting existing server callback "%s".', name)
        end
        serverCallbacks[name] = fn
    end

    function Nexus.GetServerCallback(name)
        return serverCallbacks[name]
    end

    --- Server -> client request.
    ---@param name string
    ---@param source number|string player source or 'all'
    ---@param cb function|nil
    function Nexus.TriggerClientCallback(name, source, cb, ...)
        local id = nextId()
        local args = { ... }
        if cb then
            local timer
            timer = Citizen.SetTimeout(TIMEOUT, function()
                if pendingClient[id] then
                    pendingClient[id] = nil
                    cb(nil)
                    Nexus.Print.debug('Client callback "%s" timed out for %s.', name, tostring(source))
                end
            end)
            pendingClient[id] = { cb = cb, timer = timer, source = source }
        end
        TriggerClientEvent('nexus:internal:clientCallback', source, name, id, args)
    end

    RegisterNetEvent('nexus:internal:serverCallback', function(name, id, args)
        local source = source
        local fn = serverCallbacks[name]
        if not fn then
            Nexus.Print.warn('Unknown server callback "%s" requested by player %s.', tostring(name), source)
            return
        end
        if rateLimited(source) then return end

        local responded = false
        local function respond(...)
            if responded then
                Nexus.Print.warn('Callback "%s" responded twice for player %s.', tostring(name), source)
                return
            end
            responded = true
            TriggerClientEvent('nexus:internal:serverCallbackResponse', source, name, id, { ... })
        end

        local ok, err = pcall(fn, source, respond, table.unpack(args or {}, 1, (args and #args) or 0))
        if not ok then
            Nexus.Print.error('Server callback "%s" errored for player %s: %s', tostring(name), source, tostring(err))
            respond(false)
        end
    end)

    RegisterNetEvent('nexus:internal:clientCallbackResponse', function(name, id, args)
        local entry = pendingClient[id]
        if not entry then return end
        pendingClient[id] = nil
        if entry.timer then Citizen.ClearTimeout(entry.timer) end
        entry.cb(table.unpack(args or {}, 1, (args and #args) or 0))
    end)

    AddEventHandler('playerDropped', function()
        local source = source
        buckets[source] = nil
        -- release any client callbacks we were waiting on for this player
        for id, entry in pairs(pendingClient) do
            if entry.source == source then
                if entry.timer then Citizen.ClearTimeout(entry.timer) end
                pendingClient[id] = nil
                if entry.cb then pcall(entry.cb, nil) end
            end
        end
    end)

-- ===========================================================================
--  CLIENT SIDE
-- ===========================================================================

else

    function Nexus.RegisterClientCallback(name, fn)
        if type(name) ~= 'string' or type(fn) ~= 'function' then
            print('^1[nx_core]^7 RegisterClientCallback: expects (string, function)')
            return
        end
        clientCallbacks[name] = fn
    end

    --- Client -> server request.
    function Nexus.TriggerServerCallback(name, cb, ...)
        local id = nextId()
        local args = { ... }
        if cb then
            local timer
            timer = Citizen.SetTimeout(TIMEOUT, function()
                if pendingServer[id] then
                    pendingServer[id] = nil
                    cb(nil)
                end
            end)
            pendingServer[id] = { cb = cb, timer = timer }
        end
        TriggerServerEvent('nexus:internal:serverCallback', name, id, args)
    end

    RegisterNetEvent('nexus:internal:serverCallbackResponse', function(name, id, args)
        local entry = pendingServer[id]
        if not entry then return end
        pendingServer[id] = nil
        if entry.timer then Citizen.ClearTimeout(entry.timer) end
        entry.cb(table.unpack(args or {}, 1, (args and #args) or 0))
    end)

    RegisterNetEvent('nexus:internal:clientCallback', function(name, id, args)
        local fn = clientCallbacks[name]
        if not fn then
            Nexus.Print.warn('Unknown client callback "%s".', tostring(name))
            TriggerServerEvent('nexus:internal:clientCallbackResponse', name, id, {})
            return
        end
        local function respond(...)
            TriggerServerEvent('nexus:internal:clientCallbackResponse', name, id, { ... })
        end
        local ok, err = pcall(fn, respond, table.unpack(args or {}, 1, (args and #args) or 0))
        if not ok then
            Nexus.Print.error('Client callback "%s" errored: %s', tostring(name), tostring(err))
            respond(false)
        end
    end)

end
