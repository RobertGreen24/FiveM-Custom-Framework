--[[
    Nexus Framework :: server/admin.lua
    Permissions, the admin command set, bans/warnings and the backend that feeds
    the in-game admin panel (nx_admin).

    Permission model
    ----------------
    Two layers, checked in this order:
      1. ACE  (`add_ace group.admin nexus.admin.ban allow`) — server owners win.
      2. The `admin_level` column on nx_players, mapped through Nexus.Capabilities.
    Every action is written to nx_admin_logs and mirrored to the log webhook.
]]

Nexus = Nexus or {}
local Admin = {}
Nexus.Admin = Admin

Admin.onDuty = {}         -- [source] = true
Admin.frozen = {}         -- [source] = true
Admin.spectating = {}     -- [source] = targetSource

-- ===========================================================================
--  PERMISSION HELPERS
-- ===========================================================================

---@param source number
---@param capability string
---@return boolean
function Admin.hasPermission(source, capability)
    if IsPlayerAceAllowed(source, capability) then return true end
    local player = Nexus.GetPlayer(source)
    if not player then return false end
    return player:can(capability)
end

--- Prints a denial and returns false. Use as `if not Admin.guard(src, cap) then return end`.
function Admin.guard(source, capability)
    if Admin.hasPermission(source, capability) then return true end
    local player = Nexus.GetPlayer(source)
    if player then
        player:notify('You do not have permission to do that.', 'error')
    end
    TriggerEvent('nexus:server:permissionDenied', source, capability)
    return false
end

--- Resolve a user-supplied player identifier: server id, state id, char id or name.
---@return Player|nil
function Admin.resolvePlayer(source, needle)
    if needle == nil then return nil end
    needle = tostring(needle)

    local numeric = tonumber(needle)
    if numeric then
        -- 1. direct source
        local direct = Nexus.GetPlayer(numeric)
        if direct then return direct end
        -- 2. state id (the number shown in the HUD)
        for _, candidate in pairs(Nexus.Players) do
            if candidate.stateId == numeric then return candidate end
        end
        -- 3. character id
        local byChar = Nexus.GetPlayerByCharId(numeric)
        if byChar then return byChar end
    end

    -- 4. (partial) name match, including the player's own name
    needle = needle:lower()
    local best
    for _, candidate in pairs(Nexus.Players) do
        local full = candidate:getName():lower()
        if full == needle then return candidate end
        if not best and full:find(needle, 1, true) then best = candidate end
    end
    return best
end

-- ===========================================================================
--  ADMIN DUTY
-- ===========================================================================

function Admin.setDuty(source, state)
    state = state == true
    if state then
        Admin.onDuty[source] = true
        TriggerClientEvent('nexus:client:adminDuty', source, true)
    else
        Admin.onDuty[source] = nil
        TriggerClientEvent('nexus:client:adminDuty', source, false)
    end
    local player = Nexus.GetPlayer(source)
    Nexus.Log.action('admin_duty', {
        actor = player and player:getName() or GetPlayerName(source),
        details = state and 'on duty' or 'off duty',
    })
    return true
end

function Admin.isOnDuty(source)
    return Admin.onDuty[source] == true
end

-- ===========================================================================
--  ACTIONS  (shared by commands and the NUI panel)
-- ===========================================================================

Admin.actions = {}

--- Kick -----------------------------------------------------------------------
Admin.actions.kick = function(actor, target, reason)
    reason = reason or 'No reason provided'
    Nexus.Log.action('kick', {
        actor = actor:getName(), target = target:getName(), details = reason, colour = 0xf97316,
    })
    target:notify('You were kicked: ' .. reason, 'error', 8000)
    Citizen.SetTimeout(500, function() target:kick(('Kicked by a staff member: %s'):format(reason)) end)
    return true, ('%s kicked (%s)'):format(target:getName(), reason)
end

--- Ban ------------------------------------------------------------------------
Admin.actions.ban = function(actor, target, reason, duration, identifier)
    reason = reason or 'No reason provided'
    local expiresAt = nil
    duration = tonumber(duration) or 0
    if duration > 0 then
        expiresAt = os.date('!%Y-%m-%d %H:%M:%S', os.time() + duration)
    end

    local banIdentifier = identifier or target.identifiers.license
    Nexus.DB.insert('INSERT INTO nx_bans (identifier, reason, banned_by, expires_at) VALUES (?, ?, ?, ?)', {
        banIdentifier, reason, actor:getName(), expiresAt,
    })

    Nexus.Log.action('ban', {
        actor = actor:getName(), target = target:getName(),
        details = ('%s | %s | %s'):format(banIdentifier, reason, expiresAt or 'permanent'),
        colour = 0xef4444,
    })
    target:kick(('Banned: %s%s'):format(reason, expiresAt and (' (until ' .. expiresAt .. ')') or ' (permanent)'))
    return true, ('%s banned (%s)'):format(target:getName(), reason)
end

Admin.actions.unban = function(actor, identifier)
    if not identifier or identifier == '' then return false, 'Provide a licence, discord or ip' end
    local affected = Nexus.DB.update('UPDATE nx_bans SET active = 0 WHERE identifier = ?', { identifier })
    Nexus.Log.action('unban', { actor = actor:getName(), target = identifier, details = ('%s rows'):format(tostring(affected)) })
    return true, ('%s unbanned (%s entries)'):format(identifier, tostring(affected))
end

--- Warn -----------------------------------------------------------------------
Admin.actions.warn = function(actor, target, reason)
    reason = reason or 'No reason provided'
    Nexus.DB.insert('INSERT INTO nx_warnings (char_id, identifier, reason, issued_by) VALUES (?, ?, ?, ?)', {
        target.charId, target.identifiers.license, reason, actor:getName(),
    })
    target:notify(('Staff warning: %s'):format(reason), 'warning', 10000, 'Warning')
    Nexus.Log.action('warn', { actor = actor:getName(), target = target:getName(), details = reason, colour = 0xeab308 })
    return true, ('%s warned'):format(target:getName())
end

--- Health ---------------------------------------------------------------------
Admin.actions.heal = function(actor, target)
    target:setHealth(200)
    target:setVital('hunger', 100)
    target:setVital('thirst', 100)
    target:setVital('stress', 0)
    TriggerClientEvent('nexus:client:clearEffects', target.source)
    Nexus.Log.action('heal', { actor = actor:getName(), target = target:getName() })
    return true, ('%s healed'):format(target:getName())
end

Admin.actions.revive = function(actor, target)
    target:revive()
    Nexus.Log.action('revive', { actor = actor:getName(), target = target:getName() })
    return true, ('%s revived'):format(target:getName())
end

--- Movement --------------------------------------------------------------------
Admin.actions['goto'] = function(actor, target)
    actor:teleport(target:getCoords())
    return true, ('Teleported to %s'):format(target:getName())
end

Admin.actions.bring = function(actor, target)
    target:teleport(actor:getCoords())
    target:notify('You were brought to a staff member.', 'info')
    return true, ('%s brought'):format(target:getName())
end

Admin.actions.freeze = function(actor, target)
    Admin.frozen[target.source] = not Admin.frozen[target.source]
    local state = Admin.frozen[target.source] == true
    TriggerClientEvent('nexus:client:freeze', target.source, state)
    Nexus.Log.action('freeze', { actor = actor:getName(), target = target:getName(), details = tostring(state) })
    return true, ('%s %s'):format(target:getName(), state and 'frozen' or 'unfrozen')
end

Admin.actions.spectate = function(actor, target)
    if Admin.spectating[actor.source] then
        Admin.spectating[actor.source] = nil
        TriggerClientEvent('nexus:client:spectate', actor.source, nil)
        return true, 'Stopped spectating'
    end
    Admin.spectating[actor.source] = target.source
    TriggerClientEvent('nexus:client:spectate', actor.source, target.source)
    return true, ('Spectating %s'):format(target:getName())
end

--- Jobs / gangs ---------------------------------------------------------------
Admin.actions.setjob = function(actor, target, jobName, grade)
    if not jobName then return false, 'Job name required' end
    if not Nexus.Jobs[jobName] then return false, ('Unknown job "%s"'):format(jobName) end
    target:setJob(jobName, tonumber(grade) or 0)
    target:notify(('You are now %s (%s)'):format(target:getJobLabel(), target.job.gradeName), 'success')
    Nexus.Log.action('setjob', {
        actor = actor:getName(), target = target:getName(),
        details = ('%s grade %s'):format(jobName, tostring(grade)),
    })
    return true, ('%s is now %s'):format(target:getName(), Nexus.GetJobLabel(jobName))
end

Admin.actions.setgang = function(actor, target, gangName, grade)
    if not gangName then return false, 'Gang name required' end
    if not Nexus.Gangs[gangName] then return false, ('Unknown gang "%s"'):format(gangName) end
    target:setGang(gangName, tonumber(grade) or 0)
    Nexus.Log.action('setgang', {
        actor = actor:getName(), target = target:getName(),
        details = ('%s grade %s'):format(gangName, tostring(grade)),
    })
    return true, ('%s is now %s'):format(target:getName(), Nexus.GetGangLabel(gangName))
end

--- Money ----------------------------------------------------------------------
Admin.actions.money = function(actor, target, account, amount, reason)
    account = account or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false, 'Amount must not be zero' end

    if amount > 0 then
        target:addMoney(account, amount, reason or ('admin grant by ' .. actor:getName()), actor:getName())
    else
        if not target:removeMoney(account, -amount, reason or ('admin removal by ' .. actor:getName()), actor:getName()) then
            return false, ('%s does not have that much %s'):format(target:getName(), account)
        end
    end

    Nexus.Log.money(actor:getName(), target:getName(), account, amount, reason)
    target:notify(('Your %s was %s %s by staff'):format(account, amount > 0 and 'increased by' or 'reduced by',
        Nexus.Utils.formatMoney(math.abs(amount))), amount > 0 and 'success' or 'warning', 7000)
    return true, ('%s %s %s'):format(target:getName(), amount > 0 and '+' or '', Nexus.Utils.formatMoney(amount))
end

Admin.actions.setadmin = function(actor, target, level)
    level = tonumber(level) or 0
    if actor:getAdminLevel() < Nexus.Permissions.SUPER then
        return false, 'Only superadmins can change permission levels'
    end
    target:setAdminLevel(level)
    Nexus.Log.action('setadmin', {
        actor = actor:getName(), target = target:getName(),
        details = ('level %d (%s)'):format(level, Nexus.PermissionLabels[level + 1] or '?'),
        colour = 0x8b5cf6,
    })
    target:notify(('Your permission level is now %s'):format(Nexus.PermissionLabels[level + 1] or '?'), 'info')
    return true, ('%s is now %s'):format(target:getName(), Nexus.PermissionLabels[level + 1] or '?')
end

--- Miscellaneous ---------------------------------------------------------------
Admin.actions.teleport = function(actor, target, spawnKey)
    if not spawnKey then return false, 'Spawn key required' end
    target:setLastLocation(spawnKey)
    Nexus.FinishSpawn(target, spawnKey)
    Nexus.Log.action('teleport', { actor = actor:getName(), target = target:getName(), details = spawnKey })
    return true, ('%s sent to %s'):format(target:getName(), spawnKey)
end

--- Runs an action from the panel/command with permission checks applied.
---@param source number actor source
---@param action string
---@param payload table { target = id, args = table }
function Admin.perform(source, action, payload)
    local actor = Nexus.GetPlayer(source)
    if not actor then return false, 'Unknown player' end

    local capability = ('nexus.admin.%s'):format(action)
    if not Admin.guard(source, capability) then return false, 'No permission' end

    local fn = Admin.actions[action]
    if not fn then return false, ('Unknown action "%s"'):format(tostring(action)) end

    local target
    if payload and payload.target then
        target = Admin.resolvePlayer(source, payload.target)
        if not target then return false, 'Player not found' end
    end

    local args = (payload and payload.args) or {}
    local ok, result = pcall(fn, actor, target, table.unpack(args, 1, math.min(#args, 6)))
    if not ok then
        Nexus.Print.error('Admin action "%s" failed: %s', action, tostring(result))
        return false, 'Action failed (check server console)'
    end
    return result, nil
end

-- ===========================================================================
--  COMMAND HELPERS
-- ===========================================================================

local function command(name, capability, handler, suggestion)
    RegisterCommand(name, function(source, args, raw)
        if source == 0 then
            -- console: allow everything, there is nobody to permission-check
            source = 0
            local ok, err = pcall(function()
                return handler(0, args, raw)
            end)
            if not ok then Nexus.Print.error('Console command /%s failed: %s', name, tostring(err)) end
            return
        end
        if capability and not Admin.guard(source, capability) then return end
        local ok, err = pcall(handler, source, args, raw)
        if not ok then
            Nexus.Print.error('Command /%s errored: %s', name, tostring(err))
            local player = Nexus.GetPlayer(source)
            if player then player:notify('That command failed. Check the server console.', 'error') end
        end
    end, false, suggestion)
end

--- Console-friendly actor stub so /setjob etc. can be used from the server console.
local consoleActor = setmetatable({}, {
    __index = function(_, key)
        if key == 'getName' then return function() return 'Console' end end
        if key == 'getAdminLevel' then return function() return Nexus.Permissions.SUPER end end
        if key == 'notify' then return function() end end
        if key == 'teleport' then return function() end end
        if key == 'source' then return 0 end
        return function() end
    end,
})

-- ===========================================================================
--  COMMANDS
-- ===========================================================================

command('kick', 'nexus.admin.kick', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local reason = table.concat(args, ' ', 2)
    Admin.actions.kick(actor, target, reason ~= '' and reason or nil)
    if source ~= 0 then actor:notify(('Kicked %s'):format(target:getName()), 'success') end
end, { help = 'Kick a player', params = { { name = 'id', help = 'Server/state id or name' }, { name = 'reason', help = 'Reason' } } })

command('ban', 'nexus.admin.ban', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local duration = tonumber(args[2]) or 0        -- minutes, 0 = permanent
    local reason = table.concat(args, ' ', 3)
    Admin.actions.ban(actor, target, reason ~= '' and reason or nil, duration * 60)
    if source ~= 0 then actor:notify(('Banned %s'):format(target:getName()), 'success') end
end, { help = 'Ban a player (minutes, 0 = permanent)', params = { { name = 'id' }, { name = 'minutes' }, { name = 'reason' } } })

command('unban', 'nexus.admin.unban', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local ok, message = Admin.actions.unban(actor, args[1])
    if source ~= 0 then
        actor:notify(message, ok and 'success' or 'error')
    else
        Nexus.Print.info('%s', tostring(message))
    end
end, { help = 'Remove a ban by identifier', params = { { name = 'identifier', help = 'licence / discord / ip' } } })

command('warn', 'nexus.admin.warn', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local reason = table.concat(args, ' ', 2)
    Admin.actions.warn(actor, target, reason ~= '' and reason or nil)
    if source ~= 0 then actor:notify(('Warned %s'):format(target:getName()), 'success') end
end, { help = 'Warn a player', params = { { name = 'id' }, { name = 'reason' } } })

command('warnings', 'nexus.admin.warn', function(source, args)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local rows = Nexus.DB.query('SELECT reason, issued_by, created_at FROM nx_warnings WHERE identifier = ? ORDER BY created_at DESC LIMIT 10', {
        target.identifiers.license,
    })
    local player = Nexus.GetPlayer(source)
    if not player then return end
    if #rows == 0 then
        player:notify(('%s has no warnings.'):format(target:getName()), 'info')
        return
    end
    for _, row in ipairs(rows) do
        player:notify(('%s — %s by %s'):format(row.created_at, row.reason, row.issued_by), 'warning', 9000, 'Warning history')
    end
end, { help = 'Show recent warnings for a player', params = { { name = 'id' } } })

command('setjob', 'nexus.admin.job', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.setjob(actor, target, args[2], args[3])
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Set a player\'s job', params = { { name = 'id' }, { name = 'job' }, { name = 'grade' } } })

command('setgang', 'nexus.admin.job', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.setgang(actor, target, args[2], args[3])
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Set a player\'s gang', params = { { name = 'id' }, { name = 'gang' }, { name = 'grade' } } })

command('addmoney', 'nexus.admin.money', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.money(actor, target, args[3] or 'cash', math.abs(tonumber(args[2]) or 0), table.concat(args, ' ', 4))
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Give money: /addmoney [id] [amount] [cash|bank|black]' })

command('removemoney', 'nexus.admin.money', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.money(actor, target, args[3] or 'cash', -math.abs(tonumber(args[2]) or 0), table.concat(args, ' ', 4))
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Remove money: /removemoney [id] [amount] [cash|bank|black]' })

command('setadmin', 'nexus.admin.super', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.setadmin(actor, target, args[2])
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Set permission level 0-4' })

command('revive', 'nexus.admin.revive', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1]) or actor
    local ok, message = Admin.actions.revive(actor, target)
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Revive a player (or yourself)' })

command('heal', 'nexus.admin.heal', function(source, args)
    local actor = source == 0 and consoleActor or Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1]) or actor
    local ok, message = Admin.actions.heal(actor, target)
    if source ~= 0 then actor:notify(message, ok and 'success' or 'error') end
end, { help = 'Heal a player (or yourself)' })

command('bring', 'nexus.admin.teleport', function(source, args)
    if source == 0 then return end
    local actor = Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions.bring(actor, target)
    actor:notify(message, ok and 'success' or 'error')
end, { help = 'Bring a player to you' })

command('goto', 'nexus.admin.teleport', function(source, args)
    if source == 0 then return end
    local actor = Nexus.GetPlayer(source)
    local target = Admin.resolvePlayer(source, args[1])
    if not target then return end
    local ok, message = Admin.actions['goto'](actor, target)
    actor:notify(message, ok and 'success' or 'error')
end, { help = 'Teleport to a player' })

command('aduty', 'nexus.admin', function(source)
    if source == 0 then return end
    Admin.setDuty(source, not Admin.isOnDuty(source))
    local player = Nexus.GetPlayer(source)
    player:notify(Admin.isOnDuty(source) and 'Admin duty: on' or 'Admin duty: off', 'info')
end, { help = 'Toggle admin duty' })

command('announce', 'nexus.admin', function(source, args)
    local message = table.concat(args, ' ')
    if message == '' then return end
    local author = source == 0 and 'Server' or (Nexus.GetPlayer(source):getName())
    for _, player in ipairs(Nexus.GetPlayers()) do
        player:notify(message, 'info', 12000, ('Announcement — %s'):format(author))
    end
    Nexus.Log.action('announce', { actor = author, details = message })
end, { help = 'Broadcast a message to everyone' })

command('players', 'nexus.admin', function(source)
    local players = Nexus.GetPlayers(true)
    if source == 0 then
        for _, player in ipairs(players) do
            Nexus.Print.info('[%s] %s — %s (%s)', tostring(player.source), player:getName(),
                Nexus.GetJobLabel(player.job.name), Nexus.PermissionLabels[player:getAdminLevel() + 1])
        end
        return
    end
    local actor = Nexus.GetPlayer(source)
    actor:notify(('%d player(s) connected — see the admin panel for details'):format(#players), 'info')
    TriggerClientEvent('nexus:client:adminPanelRefresh', source)
end, { help = 'List connected players' })

command('nexus', 0, function(source)
    if source == 0 then
        Nexus.Print.info('Nexus v%s — %d jobs, %d items, %d vehicles', Nexus.Version,
            Nexus.Utils.count(Nexus.Jobs), Nexus.Utils.count(Nexus.Items), 0)
        return
    end
    local player = Nexus.GetPlayer(source)
    player:notify(('Nexus v%s · %s · %d players online'):format(
        Nexus.Version, player:getPermissionLabel(), #Nexus.GetPlayers(true)), 'info', 8000, 'Nexus')
end, { help = 'Framework version / account info' })

-- ===========================================================================
--  PANEL BRIDGE (nx_admin NUI talks through these)
-- ===========================================================================

RegisterNetEvent('nexus:server:requestAdminPanel', function()
    local source = source
    if not Admin.hasPermission(source, 'nexus.admin') then
        local player = Nexus.GetPlayer(source)
        if player then player:notify('You are not an administrator.', 'error') end
        return
    end

    local list = {}
    for _, player in ipairs(Nexus.GetPlayers(true)) do
        list[#list + 1] = {
            source = player.source,
            stateId = player.stateId,
            charId = player.charId,
            name = player:getName(),
            job = player.job.label,
            jobName = player.job.name,
            jobGrade = player.job.grade,
            gang = player.gang.label,
            duty = player.job.onDuty,
            ping = GetPlayerPing(player.source),
            identifiers = player.identifiers.license,
            discord = player.identifiers.discord,
            money = player.money,
            health = player.vitals.health,
            dead = player.isDead,
            admin = player:getAdminLevel(),
            adminLabel = player:getPermissionLabel(),
            playtime = player.charPlaytime,
            loaded = player.loaded,
            coords = { player.position.x, player.position.y, player.position.z },
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)

    TriggerClientEvent('nexus:client:adminPanelData', source, {
        players = list,
        jobs = Nexus.Utils.map(Nexus.Jobs, function(job) return { name = job.name, label = job.label, grades = job.grades } end),
        gangs = Nexus.Utils.map(Nexus.Gangs, function(gang) return { name = gang.name, label = gang.label } end),
        permissions = Nexus.PermissionLabels,
        onDuty = Admin.isOnDuty(source),
        capabilities = Nexus.Capabilities,
        stats = {
            uptime = GetGameTimer(),
            players = #list,
            maxClients = GetConvarInt('sv_maxclients', 32),
            resource = GetCurrentResourceName(),
            version = Nexus.Version,
        },
    })
end)

RegisterNetEvent('nexus:server:adminAction', function(action, payload)
    local source = source
    local ok, message = Admin.perform(source, action, payload or {})
    local actor = Nexus.GetPlayer(source)
    if actor then
        actor:notify(message or (ok and 'Done' or 'Failed'), ok and 'success' or 'error')
    end
    TriggerClientEvent('nexus:client:adminActionResult', source, action, ok, message)
end)

RegisterNetEvent('nexus:server:adminDutyToggle', function()
    local source = source
    if not Admin.hasPermission(source, 'nexus.admin') then return end
    Admin.setDuty(source, not Admin.isOnDuty(source))
end)

--- Bans for the panel's ban list tab.
RegisterNetEvent('nexus:server:requestBans', function()
    local source = source
    if not Admin.hasPermission(source, 'nexus.admin.ban') then return end
    local rows = Nexus.DB.query('SELECT id, identifier, reason, banned_by, expires_at, active, created_at FROM nx_bans ORDER BY created_at DESC LIMIT 100')
    TriggerClientEvent('nexus:client:adminBanList', source, rows)
end)

--- Chat-visible staff alerts (nx_chat renders these when installed).
AddEventHandler('nexus:server:staffAlert', function(message, fromSource)
    local label = fromSource and (Nexus.GetPlayer(fromSource) and Nexus.GetPlayer(fromSource):getName() or tostring(fromSource)) or 'System'
    for source in pairs(Admin.onDuty) do
        local player = Nexus.GetPlayer(source)
        if player then
            player:notify(message, 'warning', 8000, ('Staff · %s'):format(label))
        end
    end
end)
