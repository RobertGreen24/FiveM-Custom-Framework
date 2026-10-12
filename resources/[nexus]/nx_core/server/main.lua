--[[
    Nexus Framework :: server/main.lua
    Boot sequence, connection pipeline and the character selection events.
]]

Nexus = Nexus or {}

local RESOURCE = GetCurrentResourceName()
local pendingAccounts = {}   -- [license] = { row, identifiers, dropped = false }
local pendingBySource = {}   -- [source]  = license

Nexus.Ready = false

-- ===========================================================================
--  BOOT
-- ===========================================================================

local function printBanner()
    print('^5')
    print('    _   _  _____  ___   _  ___   ___ ')
    print('   | \\ | || ____|/ _ \\ | |/ / | | / / ')
    print('   |  \\| ||  _| | | | || \' /| | |/ /  ')
    print('   | |\\  || |___| |_| || . \\| |   /   ')
    print('   |_| \\_||_____|\\___/ |_|\\_\\_| |_|   ')
    print(('   Nexus Framework v%s  ^7|^5  %d jobs ^7|^5  %d items'):format(
        Nexus.Version, Nexus.Utils.count(Nexus.Jobs), Nexus.Utils.count(Nexus.Items)))
    print('^7')
end

local function syncGangs()
    local rows = Nexus.DB.query('SELECT name, label, tag, colour, reputation FROM nx_gangs')
    for _, row in ipairs(rows or {}) do
        local existing = Nexus.Gangs[row.name] or {}
        Nexus.RegisterGang(row.name, {
            label = row.label,
            tag = row.tag,
            colour = row.colour,
            reputation = tonumber(row.reputation) or 0,
            grades = existing.grades,
            maxGrade = existing.maxGrade,
        })
    end
    Nexus.Print.debug('Synced %d gangs from the database.', #(rows or {}))
end

local function syncSocieties()
    local rows = Nexus.DB.query('SELECT name, label, balance FROM nx_societies')
    Nexus.Societies = Nexus.Societies or {}
    for _, row in ipairs(rows or {}) do
        Nexus.Societies[row.name] = {
            name = row.name, label = row.label, balance = tonumber(row.balance) or 0,
        }
    end
    Nexus.Print.debug('Synced %d societies from the database.', #(rows or {}))
end

local function boot()
    Nexus.Print.info('Booting Nexus v%s ...', Nexus.Version)

    if not Nexus.DB.detect() then
        Nexus.Print.error('oxmysql is not started! Nexus cannot persist data.')
        Nexus.Print.error('Start oxmysql (ensure oxmysql) above nx_core in server.cfg, then restart nx_core.')
        if GetConvar('nx_allow_no_database', 'false') ~= 'true' then
            return false
        end
        Nexus.Print.warn('nx_allow_no_database is enabled: running WITHOUT persistence.')
    else
        Nexus.DB.verifySchema()
    end

    Nexus.PrimeStateIds()
    syncGangs()
    syncSocieties()

    -- Re-register anyone who survived a resource restart.
    for _, source in ipairs(GetPlayers()) do
        local src = tonumber(source)
        Nexus.RegisterConnectedPlayer(src, true)
    end

    Nexus.Ready = true
    TriggerEvent(Nexus.Events.SERVER_STARTED)
    Nexus.Print.success('Ready. Type /nexus in game for the framework menu.')
    return true
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= RESOURCE then return end
    Citizen.CreateThread(function()
        boot()
    end)
end)

-- ===========================================================================
--  CONNECTION
-- ===========================================================================

local function getIdentifiers(source)
    local ids = {}
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        local kind, value = identifier:match('^([^:]+):(.+)$')
        if kind and value then ids[kind] = value end
    end
    ids.ip = GetPlayerEndpoint(source) or '0.0.0.0'
    return ids
end

--- Returns a ban row when the player is banned right now.
local function findActiveBan(source, identifiers)
    if not Nexus.DB.available then return nil end
    local candidates = {
        identifiers.license, identifiers.license2, identifiers.discord,
        identifiers.steam, identifiers.ip,
    }
    local placeholders, params = {}, {}
    for _, value in ipairs(candidates) do
        if value and value ~= '0.0.0.0' then
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = value
        end
    end
    if #placeholders == 0 then return nil end

    local row = Nexus.DB.single(([[
        SELECT * FROM nx_bans
        WHERE active = 1 AND identifier IN (%s)
          AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY created_at DESC LIMIT 1
    ]]):format(table.concat(placeholders, ',')), params)

    if not row then return nil end
    -- check the account-wide identifier too (license bans apply to every alt)
    if row.identifier ~= identifiers.license then
        local accountBan = Nexus.DB.single(
            'SELECT * FROM nx_bans WHERE active = 1 AND identifier = ? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1',
            { identifiers.license })
        if accountBan then row = accountBan end
    end
    return row
end

local function fetchOrCreateAccount(source, identifiers)
    if not Nexus.DB.available then
        -- offline mode: synthesise an account so the UI can still be tested
        return {
            id = 0, license = identifiers.license or 'offline', admin_level = 0,
            playername = GetPlayerName(source), total_playtime = 0, priority = 0,
        }
    end

    local row = Nexus.DB.single('SELECT * FROM nx_players WHERE license = ?', { identifiers.license })
    if row then
        Nexus.DB.defer([[
            UPDATE nx_players SET ip = ?, playername = ?, license2 = ?, discord = COALESCE(?, discord),
                steam = COALESCE(?, steam), fivem = COALESCE(?, fivem), live = COALESCE(?, live),
                xbl = COALESCE(?, xbl), last_seen = CURRENT_TIMESTAMP
            WHERE id = ?
        ]], {
            identifiers.ip, GetPlayerName(source), identifiers.license2, identifiers.discord,
            identifiers.steam, identifiers.fivem, identifiers.live, identifiers.xbl, row.id,
        })
        return row
    end

    local id = Nexus.DB.insert([[
        INSERT INTO nx_players (license, license2, discord, steam, fivem, live, xbl, ip, playername)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        identifiers.license, identifiers.license2, identifiers.discord, identifiers.steam,
        identifiers.fivem, identifiers.live, identifiers.xbl, identifiers.ip, GetPlayerName(source),
    })

    Nexus.Print.info('New account created for %s (%s).', GetPlayerName(source), tostring(identifiers.license))
    return {
        id = id, license = identifiers.license, admin_level = 0, playername = GetPlayerName(source),
        total_playtime = 0, priority = 0, ip = identifiers.ip,
    }
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    local identifiers = getIdentifiers(source)
    local license = identifiers.license or ('src:' .. tostring(source))

    deferrals.defer()
    Citizen.Wait(100)
    deferrals.update(('^5Nexus^7 :: verifying %s ...'):format(name))

    if not Nexus.Ready then
        deferrals.done('^1The framework is still starting up. Try again in a moment.')
        return
    end

    if not Nexus.DB.available and GetConvar('nx_allow_no_database', 'false') ~= 'true' then
        deferrals.done('^1The server database is offline. Please report this to staff.')
        return
    end

    -- identifiers
    if not identifiers.license then
        deferrals.done('^1Could not read your Rockstar licence. Restart FiveM and try again.')
        return
    end

    -- bans
    local ban = findActiveBan(source, identifiers)
    if ban then
        local expires = ban.expires_at and ('Expires: ' .. tostring(ban.expires_at)) or 'Permanent ban'
        deferrals.done(('^1You are banned from this server.\n^7Reason: %s\n^7%s\n^7Banned by: %s')
            :format(ban.reason, expires, ban.banned_by))
        return
    end

    deferrals.update('^5Nexus^7 :: loading your account ...')

    local row = fetchOrCreateAccount(source, identifiers)
    if not row then
        deferrals.done('^1Could not load your account. Please try again.')
        return
    end

    pendingAccounts[license] = { row = row, identifiers = identifiers, name = name }
    pendingBySource[source] = license

    deferrals.update(('^5Nexus^7 :: welcome back, %s.'):format(name))
    deferrals.done()
end)

--- Called both from the connection pipeline and after a resource restart.
function Nexus.RegisterConnectedPlayer(source, isReconnect)
    local license = pendingBySource[source]
    local entry = license and pendingAccounts[license]

    if not entry then
        -- resource restart: rebuild from scratch
        local identifiers = getIdentifiers(source)
        local row = Nexus.DB.available and Nexus.DB.single('SELECT * FROM nx_players WHERE license = ?', { identifiers.license })
        entry = { row = row or { id = 0, admin_level = 0, playername = GetPlayerName(source) }, identifiers = identifiers, name = GetPlayerName(source) }
    else
        pendingAccounts[license] = nil
        pendingBySource[source] = nil
    end

    if not entry.row then
        entry.row = { id = 0, admin_level = 0, playername = GetPlayerName(source) }
    end

    local player = Nexus.Player.new(source, entry.row, entry.identifiers)
    Nexus.Players[source] = player
    Nexus.PlayerByIdentifier[player.identifier] = player

    player:pushState()

    -- Hand the character list to the client's multicharacter screen.
    local characters = Nexus.DB.available and Nexus.Characters.list(player) or {}
    TriggerClientEvent('nexus:client:accountLoaded', source, {
        name = GetPlayerName(source),
        adminLevel = player:getAdminLevel(),
        permissionLabel = player:getPermissionLabel(),
        characters = characters,
        maxSlots = Nexus.Characters.maxSlots(player),
        spawns = Config.SpawnPoints,
        multicharacter = Config.Multicharacter.enabled,
        isReconnect = isReconnect == true,
    })

    Nexus.Print.debug('Registered connection for %s (account %s).', GetPlayerName(source), tostring(entry.row.id))
    return player
end

AddEventHandler('playerJoining', function()
    local source = source
    Citizen.CreateThread(function()
        Nexus.RegisterConnectedPlayer(source, false)
    end)
end)

AddEventHandler('playerDropped', function(reason)
    local source = source
    local player = Nexus.Players[source]
    if player then
        if player.loaded then
            player:save()
            TriggerEvent('nexus:server:playerDropped', player, reason)
        end
        player:disconnectCleanup()
    end
    local license = pendingBySource[source]
    if license then
        pendingAccounts[license] = nil
        pendingBySource[source] = nil
    end
end)

-- ===========================================================================
--  CHARACTER FLOW (driven by nx_multicharacter)
-- ===========================================================================

RegisterNetEvent('nexus:server:requestCharacterList', function()
    local player = Nexus.GetPlayer(source)
    if not player then return end
    local characters = Nexus.DB.available and Nexus.Characters.list(player) or {}
    TriggerClientEvent('nexus:client:characterList', source, characters, Nexus.Characters.maxSlots(player))
end)

RegisterNetEvent('nexus:server:createCharacter', function(data)
    local player = Nexus.GetPlayer(source)
    if not player then return end
    if player.loaded then
        player:notify('You are already playing.', 'error')
        return
    end

    local charId, err, slot, stateId = Nexus.Characters.create(player, data)
    if not charId then
        TriggerClientEvent('nexus:client:characterCreateFailed', source, err or 'Unknown error')
        return
    end

    TriggerClientEvent('nexus:client:characterCreated', source, charId, slot, stateId)
end)

RegisterNetEvent('nexus:server:loadCharacter', function(charId)
    local player = Nexus.GetPlayer(source)
    if not player then return end
    if player.loaded then
        player:notify('You are already playing.', 'error')
        return
    end

    local ok, err = Nexus.Characters.load(player, charId)
    if not ok then
        TriggerClientEvent('nexus:client:characterLoadFailed', source, err)
        return
    end
end)

RegisterNetEvent('nexus:server:deleteCharacter', function(charId)
    local player = Nexus.GetPlayer(source)
    if not player then return end
    local ok, err = Nexus.Characters.delete(player, charId)
    if not ok then
        TriggerClientEvent('nexus:client:notify', source, err or 'Could not delete that character', 'error')
        return
    end
    TriggerClientEvent('nexus:client:notify', source, 'Character deleted.', 'success')
    local characters = Nexus.Characters.list(player)
    TriggerClientEvent('nexus:client:characterList', source, characters, Nexus.Characters.maxSlots(player))
end)

--- Sent by nx_appearance when the creator is finished.
RegisterNetEvent('nexus:server:creationComplete', function(appearance)
    local player = Nexus.GetPlayer(source)
    if not player or not player.charId then return end
    if type(appearance) == 'table' then
        Nexus.Characters.saveAppearance(player, appearance)
    end
    player:setLastLocation(Config.DefaultSpawn)
    Nexus.FinishSpawn(player, Config.DefaultSpawn)
end)

--- Sent when the player wants to switch character (from /switch or the phone).
RegisterNetEvent('nexus:server:switchCharacter', function()
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    player:save()
    TriggerEvent('nexus:server:playerUnloaded', player)
    TriggerClientEvent(Nexus.Events.PLAYER_UNLOADED, source)
    local characters = Nexus.Characters.list(player)
    TriggerClientEvent('nexus:client:characterList', source, characters, Nexus.Characters.maxSlots(player))
end)

-- ===========================================================================
--  SPAWNING
-- ===========================================================================

--- Places a player at a named spawn point and tells the client to fade in.
function Nexus.FinishSpawn(player, spawnKey, coordsOverride, headingOverride)
    local def = Config.SpawnPoints[spawnKey] or Config.SpawnPoints[Config.DefaultSpawn]
    local coords = coordsOverride or def.coords
    local heading = headingOverride or (coords.w or 0.0)

    player.position.x, player.position.y, player.position.z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
    player.position.w = heading
    player.spawned = true
    if spawnKey then player.lastLocation = spawnKey end

    TriggerClientEvent('nexus:client:doSpawn', player.source, {
        x = coords.x, y = coords.y, z = coords.z, w = heading,
        spawnKey = spawnKey,
        isDead = player.isDead,
    })
    TriggerEvent('nexus:server:playerSpawned', player, spawnKey)
end

--- The default spawn handler. nx_spawn overrides this by handling the event
--- before us and flagging `handled` on the player.
AddEventHandler('nexus:server:requestSpawn', function(player)
    if GetResourceState('nx_spawn') == 'started' then
        return -- nx_spawn owns the selection UI
    end
    Citizen.CreateThread(function()
        Citizen.Wait(250)
        Nexus.FinishSpawn(player, player.lastLocation)
    end)
end)

-- ===========================================================================
--  RUNTIME SYNC FROM THE CLIENT
-- ===========================================================================

RegisterNetEvent('nexus:server:setPosition', function(x, y, z, w)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if type(x) ~= 'number' or type(y) ~= 'number' then return end
    player:setCoords(x, y, z, w)
end)

RegisterNetEvent('nexus:server:syncVitals', function(vitals)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if type(vitals) ~= 'table' then return end
    for key, value in pairs(vitals) do
        if key == 'health' or key == 'armour' then
            -- health is server-trusted when it changes because of damage events
            player.vitals[key] = Nexus.Utils.clampVital(key, value)
        else
            player:setVital(key, value, true)
        end
    end
end)

RegisterNetEvent('nexus:server:toggleDuty', function()
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    player:setDuty(not player:isOnDuty())
end)

RegisterNetEvent('nexus:server:setDuty', function(state)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    player:setDuty(state == true)
end)

RegisterNetEvent('nexus:server:playerReady', function()
    local player = Nexus.GetPlayer(source)
    if not player then return end
    TriggerEvent('nexus:server:playerReady', player)
end)

RegisterNetEvent('nexus:server:death', function(cause)
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded then return end
    if player.isDead then return end
    player:setDead(true)
    TriggerEvent('nexus:server:playerDied', player, cause)
end)

RegisterNetEvent('nexus:server:respawnRequest', function()
    local player = Nexus.GetPlayer(source)
    if not player or not player.loaded or not player.isDead then return end
    if Config.Death.manualRespawnCost > 0 and player:getMoney('bank') >= Config.Death.manualRespawnCost then
        player:removeMoney('bank', Config.Death.manualRespawnCost, 'hospital fees')
    end
    Nexus.FinishSpawn(player, 'hospital')
end)

-- ===========================================================================
--  AUTOSAVE + HOUSEKEEPING
-- ===========================================================================

CreateThread(function()
    while true do
        Citizen.Wait(5 * 60 * 1000)  -- every five minutes
        local saved = 0
        for _, player in pairs(Nexus.Players) do
            if player.loaded then
                player:save()
                saved = saved + 1
            end
        end
        if saved > 0 then
            Nexus.Print.debug('Autosaved %d character(s).', saved)
        end
        collectgarbage('collect')
    end
end)

--- Players are not allowed to sit on the select screen forever: holding a
--- source open without a character wastes a slot.
CreateThread(function()
    while true do
        Citizen.Wait(60 * 1000)
        for source, player in pairs(Nexus.Players) do
            if not player.loaded and (os.time() - player.sessionStart) > (10 * 60) then
                player:kick('You idled on the character select screen for too long.')
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    for _, player in pairs(Nexus.Players) do
        if player.loaded then player:save() end
    end
    Nexus.Print.warn('Shutting down: all characters saved.')
end)

-- Kick off the boot in a thread so the main chunk finishes loading first.
Citizen.CreateThread(function()
    Citizen.Wait(500)
    if not Nexus.Ready then boot() end
end)
