--[[
    Nexus Framework :: server/exports.lua
    The public server API. Every function takes primitives (source id, strings,
    numbers) and returns plain data, because Lua resources run in separate states
    and only plain values survive the trip. That makes this surface safe to call
    from any resource, any language:

        local ok = exports.nx_core:addMoney(source, 'cash', 500, 'delivery payout')
        local job = exports.nx_core:getJob(source)

    A short, friendly list of what is available is printed by /nexus help.
]]

Nexus = Nexus or {}

-- Helper: run something against a loaded player, failing soft if they are gone.
local function withPlayer(source, fn)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return nil end
    return fn(player)
end

-- ===========================================================================
--  PLAYER DATA
-- ===========================================================================

exports('getPlayer', function(source)
    local player = Nexus.GetPlayer(source)
    if not player then return nil end
    local data = player:toClient()
    data.source = player.source
    data.identifier = player.identifier
    data.identifiers = player.identifiers
    data.accountId = player.accountId
    data.loaded = player.loaded
    data.adminLevel = player:getAdminLevel()
    -- strip internal methods: consumers get data, and verbs are separate exports
    for key, value in pairs(data) do
        if type(value) == 'function' then data[key] = nil end
    end
    return data
end)

exports('isPlayerLoaded', function(source)
    local player = Nexus.GetPlayer(source)
    return player ~= nil and player.loaded
end)

exports('getPlayerData', function(source)
    return exports.nx_core:getPlayer(source)
end)

exports('getCharId', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player.charId or nil
end)

exports('getStateId', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player.stateId or nil
end)

exports('getIdentifier', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player.identifiers.license or nil
end)

exports('getIdentifiers', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player.identifiers or nil
end)

exports('getSourceByCharId', function(charId)
    local player = Nexus.GetPlayerByCharId(charId)
    return player and player.source or nil
end)

exports('getSourceByIdentifier', function(identifier)
    local player = Nexus.GetPlayerByIdentifier(identifier)
    return player and player.source or nil
end)

--- Every connected player as plain data (safe for other resources).
exports('getPlayers', function(includeLoading)
    local out = {}
    for _, player in ipairs(Nexus.GetPlayers(includeLoading == true)) do
        local data = player:toClient()
        data.source = player.source
        data.identifiers = player.identifiers
        out[#out + 1] = data
    end
    return out
end)

exports('getPlayersByJob', function(jobName, onDutyOnly)
    local out = {}
    for _, player in ipairs(Nexus.GetPlayersByJob(jobName, onDutyOnly == true)) do
        local data = player:toClient()
        data.source = player.source
        out[#out + 1] = data
    end
    return out
end)

--- Sources of everyone on duty for a job (dispatch, EMS alerts, etc).
exports('getDutySources', function(jobName)
    local out = {}
    for _, player in ipairs(Nexus.GetPlayersByJob(jobName, true)) do
        out[#out + 1] = player.source
    end
    return out
end)

exports('getPlayersByJobType', function(jobType, onDutyOnly)
    local out = {}
    for _, player in ipairs(Nexus.GetPlayersByJobType(jobType, onDutyOnly == true)) do
        out[#out + 1] = player.source
    end
    return out
end)

exports('getPlayerCount', function()
    return #Nexus.GetPlayers(true)
end)

-- ===========================================================================
--  MONEY
-- ===========================================================================

exports('getMoney', function(source, account)
    return withPlayer(source, function(p) return p:getMoney(account or 'cash') end) or 0
end)

exports('getAllMoney', function(source)
    return withPlayer(source, function(p) return Nexus.Utils.deepCopy(p.money) end)
end)

exports('addMoney', function(source, account, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    return player:addMoney(account or 'cash', amount, reason or 'external add')
end)

exports('removeMoney', function(source, account, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    return player:removeMoney(account or 'cash', amount, reason or 'external remove')
end)

exports('setMoney', function(source, account, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    return player:setMoney(account or 'cash', amount, reason or 'external set')
end)

exports('transferMoney', function(source, from, to, amount, reason)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    return player:transferMoney(from or 'bank', to or 'cash', amount, reason or 'transfer')
end)

exports('canAfford', function(source, account, amount)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return false end
    return player:hasMoney(account or 'cash', amount)
end)

-- ===========================================================================
--  JOBS / GANGS
-- ===========================================================================

exports('getJob', function(source)
    return withPlayer(source, function(p)
        return {
            name = p.job.name, grade = p.job.grade, label = p.job.label,
            gradeName = p.job.gradeName, type = p.job.type, onDuty = p.job.onDuty,
            callsign = p.callsign,
        }
    end)
end)

exports('getJobName', function(source)
    return withPlayer(source, function(p) return p.job.name end)
end)

exports('setJob', function(source, jobName, grade, silent)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setJob(jobName, tonumber(grade) or 0, { silent = silent == true })
end)

exports('setDuty', function(source, state)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setDuty(state == true)
end)

exports('toggleDuty', function(source)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setDuty(not player:isOnDuty())
end)

exports('isOnDuty', function(source)
    return withPlayer(source, function(p) return p:isOnDuty() end) or false
end)

exports('hasJobPermission', function(source, flag)
    return withPlayer(source, function(p) return p:hasJobPermission(flag) end) or false
end)

exports('isBoss', function(source)
    return withPlayer(source, function(p) return p:isBoss() end) or false
end)

exports('setCallsign', function(source, callsign)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:setCallsign(callsign)
    return true
end)

exports('getGang', function(source)
    return withPlayer(source, function(p)
        return { name = p.gang.name, grade = p.gang.grade, label = p.gang.label, gradeName = p.gang.gradeName }
    end)
end)

exports('setGang', function(source, gangName, grade)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setGang(gangName, tonumber(grade) or 0)
end)

-- ===========================================================================
--  VITALS / HEALTH
-- ===========================================================================

exports('getVitals', function(source)
    return withPlayer(source, function(p) return Nexus.Utils.deepCopy(p.vitals) end)
end)

exports('getVital', function(source, key)
    return withPlayer(source, function(p) return p:getVital(key) end) or 0
end)

exports('setVital', function(source, key, value)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setVital(key, value)
end)

exports('addVital', function(source, key, value)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:addVital(key, value)
end)

exports('setHealth', function(source, value)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:setHealth(value)
    return true
end)

exports('revivePlayer', function(source, health, armour)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:revive(health, armour)
    return true
end)

exports('isDead', function(source)
    return withPlayer(source, function(p) return p.isDead end) or false
end)

exports('setLastLocation', function(source, key)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:setLastLocation(key)
    return true
end)

-- ===========================================================================
--  LICENCES / METADATA
-- ===========================================================================

exports('getLicences', function(source)
    return withPlayer(source, function(p) return Nexus.Utils.deepCopy(p.licences) end)
end)

exports('hasLicence', function(source, name)
    return withPlayer(source, function(p) return p:hasLicence(name) end) or false
end)

exports('addLicence', function(source, name, points, issuedBy)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:addLicence(name, points, issuedBy)
end)

exports('removeLicence', function(source, name, revoked)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:removeLicence(name, revoked)
end)

exports('getMeta', function(source, key, default)
    return withPlayer(source, function(p) return p:getMeta(key, default) end)
end)

exports('setMeta', function(source, key, value)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setMeta(key, value)
end)

-- ===========================================================================
--  PERMISSIONS
-- ===========================================================================

exports('hasPermission', function(source, capability)
    return Nexus.Admin.hasPermission(source, capability)
end)

exports('getAdminLevel', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player:getAdminLevel() or 0
end)

exports('setAdminLevel', function(source, level)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:setAdminLevel(level)
end)

exports('isAdmin', function(source)
    local player = Nexus.GetPlayer(source)
    return player and player:isAdmin() or false
end)

-- ===========================================================================
--  DEFINITIONS (jobs, gangs, items)
-- ===========================================================================

exports('getJobDefinitions', function() return Nexus.Jobs end)

exports('getJobDefinition', function(name) return Nexus.Jobs[name] end)

exports('getGangDefinitions', function() return Nexus.Gangs end)

exports('getGangDefinition', function(name) return Nexus.Gangs[name] end)

exports('getItemDefinitions', function() return Nexus.Items end)

exports('getItemDefinition', function(name) return Nexus.Items[name] end)

exports('registerItem', function(name, data)
    Nexus.RegisterItem(name, data)
    return true
end)

exports('registerJob', function(name, data)
    Nexus.RegisterJob(name, data)
    return true
end)

exports('registerGang', function(name, data)
    Nexus.RegisterGang(name, data)
    return true
end)

exports('getConfig', function() return Config end)

exports('getSpawnPoints', function() return Config.SpawnPoints end)

exports('getSpawnPoint', function(key)
    return Config.SpawnPoints[key] or Config.SpawnPoints[Config.DefaultSpawn]
end)

-- ===========================================================================
--  SOCIETIES
-- ===========================================================================

exports('getSociety', function(name)
    local society = Nexus.Society.get(name)
    if not society then return nil end
    return { name = society.name, label = society.label, balance = society.balance }
end)

exports('getSocietyBalance', function(name)
    return Nexus.Society.getBalance(name)
end)

exports('addSocietyMoney', function(name, amount, reason, actor)
    return Nexus.Society.addMoney(name, amount, reason, actor)
end)

exports('removeSocietyMoney', function(name, amount, reason, actor)
    return Nexus.Society.removeMoney(name, amount, reason, actor)
end)

exports('getSocietyMembers', function(name)
    return Nexus.Society.getMembers(name)
end)

-- ===========================================================================
--  MODERATION
-- ===========================================================================

exports('kickPlayer', function(source, reason)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:kick(reason or 'Kicked by the server')
    return true
end)

exports('notify', function(source, message, ntype, duration, title)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    player:notify(message, ntype, duration, title)
    return true
end)

exports('notifyAll', function(message, ntype, duration, title)
    for _, player in ipairs(Nexus.GetPlayers()) do
        player:notify(message, ntype, duration, title)
    end
    return true
end)

exports('log', function(action, data)
    Nexus.Log.action(action, data)
    return true
end)

exports('savePlayer', function(source)
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:save()
end)

exports('saveAll', function()
    local count = 0
    for _, player in ipairs(Nexus.GetPlayers()) do
        if player:save() then count = count + 1 end
    end
    return count
end)

-- ===========================================================================
--  EVENTS / CALLBACKS FOR CONSUMERS
-- ===========================================================================

exports('registerServerCallback', function(name, fn)
    Nexus.RegisterServerCallback(name, fn)
    return true
end)

exports('triggerClientCallback', function(name, source, ...)
    Nexus.TriggerClientCallback(name, source, nil, ...)
    return true
end)

exports('emit', function(eventName, ...)
    TriggerEvent(eventName, ...)
    return true
end)

--- Admin actions bridge so job resources can reuse permission checks + logging.
exports('performAdminAction', function(source, action, payload)
    return Nexus.Admin.perform(source, action, payload)
end)

exports('hasAdminPermission', function(source, capability)
    return Nexus.Admin.hasPermission(source, capability)
end)
