--[[
    Nexus Framework :: client/exports.lua
    The public client API. Data getters are synchronous; anything that talks to
    the server or shows UI takes a callback.
]]

Nexus = Nexus or {}
local Client = Nexus.Client

-- ===========================================================================
--  DATA
-- ===========================================================================

exports('isLoaded', function() return Client.isLoaded() end)
exports('getPlayerData', function() return Client.getData() end)
exports('getCharId', function() return Client.getCharId() end)
exports('getStateId', function() return Client.getStateId() end)
exports('getName', function() return Client.getName() end)
exports('getMoney', function(account) return Client.getMoney(account) end)
exports('getJob', function() return Client.getJob() end)
exports('getGang', function() return Client.getGang() end)
exports('getVitals', function() return Client.getVitals() end)
exports('isOnDuty', function() return Client.isOnDuty() end)
exports('isAdmin', function() return Client.isAdmin() end)
exports('isDead', function() return Client.isDowned() end)
exports('getLicences', function() return Client.getLicences() end)
exports('hasLicence', function(name) return Client.hasLicence(name) end)
exports('getMeta', function(key, default) return Client.getMeta(key, default) end)

--- Every spawn point from the shared config (nx_spawn, housing, admin tools).
exports('getSpawnPoints', function() return Config.SpawnPoints end)
exports('getJobDefinitions', function() return Nexus.Jobs end)
exports('getItemDefinitions', function() return Nexus.Items end)
exports('getJobDefinition', function(name) return Nexus.Jobs[name] end)
exports('getItemDefinition', function(name) return Nexus.Items[name] end)

-- ===========================================================================
--  ACTIONS
-- ===========================================================================

exports('triggerServerCallback', function(name, cb, ...)
    Nexus.TriggerServerCallback(name, cb, ...)
end)

exports('registerClientCallback', function(name, fn)
    Nexus.RegisterClientCallback(name, fn)
end)

exports('toggleDuty', function()
    TriggerServerEvent('nexus:server:toggleDuty')
end)

exports('setDuty', function(state)
    TriggerServerEvent('nexus:server:setDuty', state == true)
end)

exports('setWaypoint', function(coords, blipType)
    Nexus.Client.setWaypoint(coords, blipType)
end)

exports('deleteWaypoint', function()
    Nexus.Client.deleteWaypoint()
end)

exports('getWaypoint', function()
    return Nexus.Client.getWaypoint()
end)

exports('getNearbyPlayers', function(radius)
    return Nexus.Client.getNearbyPlayers(radius or 10.0)
end)

exports('getPlayersOnDuty', function()
    return Nexus.Client.getDutyPlayers()
end)

exports('playSound', function(name, ref, volume)
    PlaySoundFrontend(-1, name, ref or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end)

exports('showSubtitle', function(text, duration)
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandPrint(duration or 4000, true)
end)

exports('switchCharacter', function()
    Nexus.Confirm({ title = 'Switch character', message = 'Return to the character select screen?' }, function(confirmed)
        if confirmed then
            TriggerServerEvent('nexus:server:switchCharacter')
        end
    end)
end)
