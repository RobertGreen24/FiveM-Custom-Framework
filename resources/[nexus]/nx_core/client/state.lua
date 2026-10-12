--[[
    Nexus Framework :: client/state.lua
    The client's mirror of its own character. Resources read it instead of
    round-tripping to the server for every HUD frame.
]]

Nexus = Nexus or {}

local Client = {}
Nexus.Client = Client

Client.data = nil           -- full payload from nexus:client:playerData
Client.loaded = false
Client.account = nil        -- account payload from nexus:client:accountLoaded
Client.spawned = false
Client.duty = false
Client.admin = { level = 0, onDuty = false }

local listeners = {}        -- event name -> { fn }

--- Tiny pub/sub so HUD/UI resources can react without re-registering handlers.
function Client.on(eventName, fn)
    listeners[eventName] = listeners[eventName] or {}
    table.insert(listeners[eventName], fn)
end

function Client.emit(eventName, ...)
    for _, fn in ipairs(listeners[eventName] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            Nexus.Print.error('Client listener for "%s" errored: %s', eventName, tostring(err))
        end
    end
end

--- Getters ------------------------------------------------------------------

function Client.isLoaded()
    return Client.loaded == true
end

function Client.getData()
    return Client.data
end

function Client.getCharId()
    return Client.data and Client.data.charId or nil
end

function Client.getStateId()
    return Client.data and Client.data.stateId or 0
end

function Client.getName()
    return Client.data and Client.data.fullName or GetPlayerName(PlayerId())
end

function Client.getMoney(account)
    if not Client.data then return 0 end
    return Client.data.money[account or 'cash'] or 0
end

function Client.getJob()
    return Client.data and Client.data.job or { name = 'unemployed', grade = 0, onDuty = false }
end

function Client.getGang()
    return Client.data and Client.data.gang or { name = 'none', grade = 0 }
end

function Client.getVitals()
    return Client.data and Client.data.vitals or {}
end

function Client.isOnDuty()
    local job = Client.getJob()
    return job.onDuty == true
end

function Client.getLicences()
    return (Client.data and Client.data.licences) or {}
end

function Client.hasLicence(name)
    local lic = Client.getLicences()[name]
    return lic ~= nil and lic.revoked ~= true
end

function Client.isAdmin()
    return (Client.data and Client.data.isAdmin) or false
end

function Client.getMeta(key, default)
    local meta = Client.data and Client.data.metadata
    if not meta or meta[key] == nil then return default end
    return meta[key]
end

-- ===========================================================================
--  SERVER -> CLIENT EVENT WIRING
-- ===========================================================================

RegisterNetEvent(Nexus.Events.PLAYER_DATA, function(data)
    Client.data = data
    Client.loaded = true
    Client.emit('dataChanged', data)
end)

RegisterNetEvent(Nexus.Events.MONEY_CHANGED, function(account, value, previous, reason)
    if not Client.data then return end
    Client.data.money[account] = value
    Client.emit('moneyChanged', account, value, previous, reason)
end)

RegisterNetEvent(Nexus.Events.JOB_CHANGED, function(job)
    if not Client.data then return end
    Client.data.job = job
    Client.emit('jobChanged', job)
end)

RegisterNetEvent(Nexus.Events.GANG_CHANGED, function(gang)
    if not Client.data then return end
    Client.data.gang = gang
    Client.emit('gangChanged', gang)
end)

RegisterNetEvent(Nexus.Events.DUTY_CHANGED, function(state, job)
    if not Client.data then return end
    Client.data.job = job or Client.data.job
    Client.data.job.onDuty = state
    Client.emit('dutyChanged', state)
end)

RegisterNetEvent(Nexus.Events.LICENCE_CHANGED, function(licences)
    if not Client.data then return end
    Client.data.licences = licences
    Client.emit('licencesChanged', licences)
end)

RegisterNetEvent('nexus:client:vitalChanged', function(key, value)
    if not Client.data then return end
    Client.data.vitals[key] = value
    Client.emit('vitalChanged', key, value)
end)

RegisterNetEvent('nexus:client:metaChanged', function(key, value)
    if not Client.data then return end
    Client.data.metadata[key] = value
    Client.emit('metaChanged', key, value)
end)

RegisterNetEvent('nexus:client:callsignChanged', function(callsign)
    if not Client.data then return end
    Client.data.callsign = callsign
    Client.emit('callsignChanged', callsign)
end)

RegisterNetEvent('nexus:client:accountLoaded', function(account)
    Client.account = account
    Client.loaded = false
    Client.data = nil
    Client.emit('accountLoaded', account)
end)

RegisterNetEvent('nexus:client:characterList', function(characters, maxSlots)
    Client.emit('characterList', characters, maxSlots)
end)

RegisterNetEvent(Nexus.Events.PLAYER_LOADED, function(data)
    Client.data = data
    Client.loaded = true
    LocalPlayer.state:set('nx_loaded', true, false)
    Client.emit('playerLoaded', data)
end)

RegisterNetEvent(Nexus.Events.PLAYER_UNLOADED, function()
    Client.loaded = false
    Client.data = nil
    LocalPlayer.state:set('nx_loaded', false, false)
    Client.emit('playerUnloaded')
end)
