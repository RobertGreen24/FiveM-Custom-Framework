--[[
    Nexus Framework :: server/player.lua
    The Player object. One instance per connected player source.

    A Player starts life as an "account" (nx_players row: licence, discord, admin
    level) and gains a "character" (nx_characters row: name, money, job, vitals)
    once they pick a slot. Everything other resources need is reachable from here:

        local player = exports.nx_core:getPlayer(source)
        player:addMoney('cash', 500, 'Bank heist payout')
        player:setJob('police', 2)
]]

Nexus = Nexus or {}

local Player = {}
Player.__index = Player
Nexus.Player = Player

Nexus.Players = {}          -- [source]  = Player
Nexus.PlayerByCharId = {}   -- [charId]  = Player
Nexus.PlayerByIdentifier = {} -- ['license:xxxx'] = Player

local MONEY_ACCOUNTS = Nexus.MoneyConfig.accounts

-- ===========================================================================
--  CONSTRUCTION
-- ===========================================================================

---@param source number
---@param row table|nil nx_players row (nil = brand new account, not yet inserted)
---@param identifiers table map of type -> value, e.g. { license = 'abc' }
function Player.new(source, row, identifiers)
    local self = setmetatable({}, Player)

    self.source = source
    self.identifiers = identifiers or {}
    self.accountId = row and row.id or nil
    self.account = row or {}

    -- identity
    self.identifier = self.identifiers.license or ('src:' .. tostring(source))
    self.name = (row and row.playername) or GetPlayerName(source) or 'Unknown'

    -- permissions
    self.adminLevel = tonumber(row and row.admin_level) or 0
    self.priority = tonumber(row and row.priority) or 0

    -- character (filled by :loadCharacter)
    self.charId = nil
    self.stateId = nil
    self.firstName = nil
    self.lastName = nil
    self.gender = 0
    self.birthDate = nil
    self.nationality = 'American'
    self.phone = nil
    self.callsign = nil

    self.money = { cash = 0, bank = 0, black = 0, savings = 0 }
    self.job = { name = 'unemployed', grade = 0, onDuty = false }
    self.gang = { name = 'none', grade = 0 }
    self.vitals = { health = 200, armour = 0, hunger = 100, thirst = 100, stress = 0 }
    self.metadata = {}
    self.appearance = nil
    self.licences = {}
    self.position = { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
    self.lastLocation = Config.DefaultSpawn

    -- runtime
    self.loggedIn = false        -- account row exists
    self.loaded = false          -- character selected and spawned
    self.isDead = false
    self.spawned = false
    self.inventory = nil         -- set by nx_inventory
    self.sessionStart = os.time()
    self.playtime = tonumber(row and row.total_playtime) or 0
    self.charPlaytime = 0
    self.lastSave = os.time()
    self.bucket = 0
    self.muted = false
    self.frozen = false
    self.dirty = false           -- needs a DB write
    self.dropReason = nil

    return self
end

--- Convenience accessors -----------------------------------------------------

function Player:getName()
    if self.firstName then
        return ('%s %s'):format(self.firstName, self.lastName)
    end
    return self.name
end

function Player:getIdentifier() return self.identifier end

function Player:getIdentifiers() return self.identifiers end

function Player:getStateId() return self.stateId end

function Player:isLoaded() return self.loaded end

--- Has the player picked a character yet? --------------------------------
function Player:hasCharacter() return self.charId ~= nil end

-- ===========================================================================
--  MONEY
-- ===========================================================================

function Player:getMoney(account)
    account = account or 'cash'
    return self.money[account] or 0
end

function Player:getAllMoney()
    return self.money
end

function Player:hasMoney(account, amount)
    amount = tonumber(amount) or 0
    if amount < 0 then return true end
    return self:getMoney(account) >= amount
end

local function validAccount(account)
    for i = 1, #MONEY_ACCOUNTS do
        if MONEY_ACCOUNTS[i] == account then return true end
    end
    return false
end

--- Hard set (admin use). Fires the change event and the ledger.
function Player:setMoney(account, amount, reason, actor)
    if not validAccount(account) then
        Nexus.Print.error('setMoney: unknown account "%s"', tostring(account))
        return false
    end
    amount = math.floor(tonumber(amount) or 0)
    amount = Nexus.Utils.clamp(amount, 0, Nexus.MoneyConfig.maxValue)

    local previous = self.money[account] or 0
    self.money[account] = amount
    self.dirty = true

    self:onMoneyChanged(account, amount, previous, reason, actor)
    return true
end

function Player:addMoney(account, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    return self:setMoney(account, self:getMoney(account) + amount, reason, actor)
end

--- Returns true only if the funds existed and were deducted.
function Player:removeMoney(account, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if not self:hasMoney(account, amount) then return false end
    return self:setMoney(account, self:getMoney(account) - amount, reason, actor)
end

--- Move money between accounts in one atomic step (bank -> cash, etc).
function Player:transferMoney(from, to, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if not self:hasMoney(from, amount) then return false end
    self.money[from] = self.money[from] - amount
    self.money[to] = (self.money[to] or 0) + amount
    self.dirty = true
    self:onMoneyChanged(from, self.money[from], self.money[from] + amount, reason)
    self:onMoneyChanged(to, self.money[to], self.money[to] - amount, reason)
    return true
end

--- Internal: notify client, statebag and ledger.
function Player:onMoneyChanged(account, value, previous, reason, actor)
    TriggerClientEvent(Nexus.Events.MONEY_CHANGED, self.source, account, value, previous, reason)
    TriggerEvent('nexus:server:moneyChanged', self, account, value, previous, reason)

    if Nexus.DB.available and account ~= 'savings' then
        Nexus.DB.defer(
            'INSERT INTO nx_transactions (char_id, account, amount, balance_after, type, reason, actor) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { self.charId, account, (value - (previous or 0)), value, 'set', reason or 'unspecified', actor or 'system' }
        )
    end
end

-- ===========================================================================
--  JOBS & GANGS
-- ===========================================================================

---@param jobName string
---@param grade number
---@param opts table|nil { silent, keepDuty }
function Player:setJob(jobName, grade, opts)
    opts = opts or {}
    jobName = jobName or 'unemployed'
    grade = math.floor(tonumber(grade) or 0)

    if not Nexus.Jobs[jobName] then
        Nexus.Print.error('setJob: unknown job "%s"', tostring(jobName))
        return false
    end

    local maxGrade = #Nexus.Jobs[jobName].grades - 1
    if grade < 0 or grade > maxGrade then
        grade = math.min(math.max(grade, 0), maxGrade)
    end

    local previous = self.job.name
    self.job.name = jobName
    self.job.grade = grade
    self.job.label = Nexus.GetJobLabel(jobName)
    self.job.gradeName = Nexus.GetGradeLabel(jobName, grade)
    self.job.type = Nexus.Jobs[jobName].type

    if opts.keepDuty ~= true then
        self.job.onDuty = false
    end
    if previous ~= jobName then
        self.callsign = nil
    end

    self.dirty = true
    self:pushState()

    if not opts.silent then
        TriggerClientEvent(Nexus.Events.JOB_CHANGED, self.source, self.job)
    end
    TriggerEvent('nexus:server:jobChanged', self, self.job, previous)
    return true
end

function Player:getJob()
    return self.job.name, self.job.grade
end

function Player:getJobObject()
    return self.job
end

function Player:getJobLabel()
    return self.job.label or Nexus.GetJobLabel(self.job.name)
end

function Player:isJob(jobName, minGrade)
    if self.job.name ~= jobName then return false end
    if minGrade and self.job.grade < minGrade then return false end
    return true
end

function Player:setDuty(state)
    state = state == true
    if state and self.job.name == 'unemployed' then
        self:notify('You are not employed.', 'error')
        return false
    end
    self.job.onDuty = state
    self.dirty = true
    self:pushState()
    TriggerClientEvent(Nexus.Events.DUTY_CHANGED, self.source, state, self.job)
    TriggerEvent('nexus:server:dutyChanged', self, state)
    return true
end

function Player:isOnDuty()
    return self.job.onDuty == true
end

function Player:hasJobPermission(flag)
    if self:can('nexus.admin') then return true end
    return Nexus.JobHasPermission(self.job.name, self.job.grade, flag)
end

function Player:isBoss()
    return Nexus.JobRank(self.job.name, self.job.grade) == 'boss'
end

function Player:isSupervisor()
    local rank = Nexus.JobRank(self.job.name, self.job.grade)
    return rank == 'boss' or rank == 'supervisor'
end

function Player:setCallsign(callsign)
    self.callsign = callsign and tostring(callsign):sub(1, 12) or nil
    self.dirty = true
    self:pushState()
    TriggerClientEvent('nexus:client:callsignChanged', self.source, self.callsign)
end

function Player:setGang(gangName, grade, silent)
    gangName = gangName or 'none'
    grade = math.floor(tonumber(grade) or 0)

    if not Nexus.Gangs[gangName] then
        Nexus.Print.error('setGang: unknown gang "%s"', tostring(gangName))
        return false
    end

    local previous = self.gang.name
    self.gang.name = gangName
    self.gang.grade = grade
    self.gang.label = Nexus.GetGangLabel(gangName)
    self.gang.gradeName = Nexus.GetGangGradeLabel(gangName, grade)

    self.dirty = true
    self:pushState()

    if not silent then
        TriggerClientEvent(Nexus.Events.GANG_CHANGED, self.source, self.gang)
    end
    TriggerEvent('nexus:server:gangChanged', self, self.gang, previous)
    return true
end

function Player:hasGang(gangName, minGrade)
    if self.gang.name ~= gangName then return false end
    if minGrade and self.gang.grade < minGrade then return false end
    return true
end

-- ===========================================================================
--  VITALS
-- ===========================================================================

function Player:getVital(key)
    return self.vitals[key] or 0
end

function Player:setVital(key, value, silent)
    if Nexus.Vitals[key] == nil then return false end
    value = Nexus.Utils.clampVital(key, value)

    local changed = self.vitals[key] ~= value
    self.vitals[key] = value
    if changed then
        self.dirty = true
        if not silent then
            TriggerClientEvent('nexus:client:vitalChanged', self.source, key, value)
        end
    end
    return true
end

function Player:addVital(key, value, silent)
    return self:setVital(key, self:getVital(key) + (tonumber(value) or 0), silent)
end

--- Server-authoritative health (used by EMS revive etc).
function Player:setHealth(value)
    self.vitals.health = Nexus.Utils.clampVital('health', value)
    self.dirty = true
    TriggerClientEvent('nexus:client:setHealth', self.source, self.vitals.health, self.vitals.armour)
end

function Player:revive(health, armour)
    self.isDead = false
    self.vitals.health = Nexus.Utils.clampVital('health', health or Config.Death.reviveHealth)
    self.vitals.armour = Nexus.Utils.clampVital('armour', armour or Config.Death.reviveArmour)
    self.dirty = true
    self:pushState()
    TriggerClientEvent(Nexus.Events.RESPAWN, self.source)
    TriggerEvent('nexus:server:playerRevived', self)
    Nexus.Log.action('revive', { actor = 'system', target = self:getName(), details = ('char %s'):format(tostring(self.charId)) })
end

function Player:setDead(state)
    state = state == true
    if self.isDead == state then return end
    self.isDead = state
    self.dirty = true
    self:pushState()
    TriggerEvent('nexus:server:deathState', self, state)
end

-- ===========================================================================
--  METADATA & LICENCES
-- ===========================================================================

function Player:getMeta(key, default)
    local value = self.metadata[key]
    if value == nil then return default end
    return value
end

function Player:setMeta(key, value)
    self.metadata[key] = value
    self.dirty = true
    TriggerClientEvent('nexus:client:metaChanged', self.source, key, value)
    return true
end

function Player:getLicences()
    return self.licences
end

function Player:hasLicence(name)
    local lic = self.licences[name]
    return lic ~= nil and lic.revoked ~= true
end

function Player:addLicence(name, points, issuedBy)
    if not Nexus.LicenceTypes or not Nexus.LicenceTypes[name] then
        -- unknown licences are still allowed, they just have no label
    end
    self.licences[name] = { name = name, points = points or 0, revoked = false }
    self.dirty = true
    if Nexus.DB.available then
        Nexus.DB.defer(
            'INSERT INTO nx_licences (char_id, name, points, issued_by) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE revoked = 0, issued_by = VALUES(issued_by)',
            { self.charId, name, points or 0, issuedBy or 'system' }
        )
    end
    TriggerClientEvent(Nexus.Events.LICENCE_CHANGED, self.source, self.licences)
    return true
end

function Player:removeLicence(name, revoked)
    if not self.licences[name] then return false end
    self.licences[name].revoked = revoked ~= false
    self.dirty = true
    if Nexus.DB.available then
        Nexus.DB.defer('UPDATE nx_licences SET revoked = ? WHERE char_id = ? AND name = ?', {
            self.licences[name].revoked and 1 or 0, self.charId, name,
        })
    end
    TriggerClientEvent(Nexus.Events.LICENCE_CHANGED, self.source, self.licences)
    return true
end

-- ===========================================================================
--  POSITION / WORLD
-- ===========================================================================

function Player:getCoords()
    return vector3(self.position.x, self.position.y, self.position.z)
end

function Player:getHeading()
    return self.position.w
end

function Player:setCoords(x, y, z, w)
    self.position.x = tonumber(x) or self.position.x
    self.position.y = tonumber(y) or self.position.y
    self.position.z = tonumber(z) or self.position.z
    self.position.w = tonumber(w) or self.position.w
    self.dirty = true
end

function Player:setLastLocation(key)
    if key then
        self.lastLocation = key
        self.dirty = true
    end
end

--- Move the player. `coords` may be vector3 or vector4.
function Player:teleport(coords, keepVehicle)
    if type(coords) == 'table' then
        coords = vector3(coords.x or coords[1] or 0, coords.y or coords[2] or 0, coords.z or coords[3] or 0)
    end
    TriggerClientEvent('nexus:client:teleport', self.source, coords, keepVehicle == true)
end

--- Very cheap distance helper against another Player.
function Player:distanceTo(otherPlayer)
    return #(self:getCoords() - otherPlayer:getCoords())
end

-- ===========================================================================
--  PERMISSIONS
-- ===========================================================================

---@param capability string e.g. 'nexus.admin.ban'
function Player:can(capability)
    if capability == nil then return false end
    -- explicit ACE always wins (server owners can hook in with `add_ace`)
    if IsPlayerAceAllowed(self.source, capability) then return true end

    local required = Nexus.Capabilities[capability]
    if required == nil then
        -- allow loose matching: "nexus.admin.foo" requires base nexus.admin
        if Nexus.Utils.startsWith(capability, 'nexus.admin.') then
            required = Nexus.Capabilities['nexus.admin'] or Nexus.Permissions.ADMIN
        else
            return false
        end
    end

    return self:getAdminLevel() >= required
end

function Player:getAdminLevel()
    if self.account and self.account.admin_level then
        return tonumber(self.account.admin_level) or 0
    end
    return self.adminLevel or 0
end

function Player:setAdminLevel(level)
    level = Nexus.Utils.clamp(math.floor(tonumber(level) or 0), 0, #Nexus.PermissionLabels - 1)
    self.adminLevel = level
    self.account.admin_level = level
    if Nexus.DB.available then
        Nexus.DB.defer('UPDATE nx_players SET admin_level = ? WHERE id = ?', { level, self.accountId })
    end
    self:pushState()
    TriggerClientEvent('nexus:client:adminLevelChanged', self.source, level)
    return true
end

function Player:isAdmin()
    return self:getAdminLevel() >= Nexus.Permissions.HELPER
end

--- Permission label for the UI ("Moderator").
function Player:getPermissionLabel()
    return Nexus.PermissionLabels[self:getAdminLevel() + 1] or 'Player'
end

-- ===========================================================================
--  INTERACTION HELPERS
-- ===========================================================================

function Player:notify(message, ntype, duration, title)
    TriggerClientEvent(Nexus.Events.NOTIFY, self.source, message, ntype or 'info', duration, title)
end

--- One-line helper used by job scripts: only notify if the player is close to
--- `coords`, otherwise stay silent (avoids spamming the whole server).
function Player:notifyIfNear(coords, radius, message, ntype)
    if not coords then
        self:notify(message, ntype)
        return
    end
    local ped = GetPlayerPed(self.source)
    if ped == 0 then return end
    local playerCoords = GetEntityCoords(ped)
    if #(playerCoords - vector3(coords.x, coords.y, coords.z)) <= radius then
        self:notify(message, ntype)
    end
end

function Player:kick(reason)
    self.dropReason = reason
    DropPlayer(self.source, reason or 'Kicked by Nexus')
end

function Player:trigger(eventName, ...)
    TriggerClientEvent(eventName, self.source, ...)
end

function Player:emit(eventName, ...)
    TriggerEvent(eventName, self, ...)
end

--- Pushes the lightweight statebag other clients/resources read to render
--- nametags, medical status and dispatch info.
function Player:pushState()
    local state = Player(self.source).state
    state:set('nx_char_id', self.charId, true)
    state:set('nx_state_id', self.stateId, true)
    state:set('nx_name', self:getName(), true)
    state:set('nx_job', self.job.name, true)
    state:set('nx_job_label', self.job.label, true)
    state:set('nx_job_grade', self.job.grade, true)
    state:set('nx_duty', self.job.onDuty, true)
    state:set('nx_gang', self.gang.name, true)
    state:set('nx_gang_label', self.gang.label, true)
    state:set('nx_dead', self.isDead, true)
    state:set('nx_admin', self:isAdmin(), true)
    state:set('nx_loaded', self.loaded, true)
    state:set('nx_callsign', self.callsign, true)
    state:set('nx_phone', self.phone, true)
end

--- Client-facing copy of the player. Sensitive fields (account id, ip) are
--- deliberately omitted.
function Player:toClient()
    return {
        charId = self.charId,
        stateId = self.stateId,
        firstName = self.firstName,
        lastName = self.lastName,
        fullName = self:getName(),
        gender = self.gender,
        birthDate = self.birthDate,
        nationality = self.nationality,
        phone = self.phone,
        callsign = self.callsign,
        money = Nexus.Utils.deepCopy(self.money),
        job = Nexus.Utils.deepCopy(self.job),
        gang = Nexus.Utils.deepCopy(self.gang),
        vitals = Nexus.Utils.deepCopy(self.vitals),
        metadata = Nexus.Utils.deepCopy(self.metadata),
        licences = Nexus.Utils.deepCopy(self.licences),
        appearance = Nexus.Utils.deepCopy(self.appearance),
        position = Nexus.Utils.deepCopy(self.position),
        lastLocation = self.lastLocation,
        isDead = self.isDead,
        playtime = self.charPlaytime,
        accountPlaytime = self.playtime,
        adminLevel = self:getAdminLevel(),
        permissionLabel = self:getPermissionLabel(),
        isAdmin = self:isAdmin(),
    }
end

function Player:pushData()
    TriggerClientEvent(Nexus.Events.PLAYER_DATA, self.source, self:toClient())
end

-- ===========================================================================
--  PERSISTENCE
-- ===========================================================================

local SAVE_FIELDS = { 'cash', 'bank', 'black', 'savings' }

function Player:save()
    if not self.charId or not Nexus.DB.available then return false end

    local position = self.position
    Nexus.DB.update([[
        UPDATE nx_characters SET
            cash = ?, bank = ?, black_money = ?,
            job = ?, job_grade = ?, on_duty = ?,
            gang = ?, gang_grade = ?, callsign = ?,
            x = ?, y = ?, z = ?, heading = ?,
            last_location = ?,
            health = ?, armour = ?, hunger = ?, thirst = ?, stress = ?, is_dead = ?,
            metadata = ?, playtime = playtime + ?,
            skin = COALESCE(?, skin),
            last_played = CURRENT_TIMESTAMP
        WHERE id = ?
    ]], {
        self.money.cash, self.money.bank, self.money.black,
        self.job.name, self.job.grade, self.job.onDuty and 1 or 0,
        self.gang.name, self.gang.grade, self.callsign,
        position.x, position.y, position.z, position.w,
        self.lastLocation,
        self.vitals.health, self.vitals.armour, self.vitals.hunger, self.vitals.thirst, self.vitals.stress,
        self.isDead and 1 or 0,
        Nexus.Utils.encodeJson(self.metadata) or '{}',
        math.max(0, os.time() - self.lastSave),
        self.appearance and Nexus.Utils.encodeJson(self.appearance) or nil,
        self.charId,
    })

    -- account-level counters
    local sessionSeconds = math.max(0, os.time() - self.lastSave)
    Nexus.DB.update('UPDATE nx_players SET total_playtime = total_playtime + ?, playername = ?, ip = ? WHERE id = ?', {
        sessionSeconds, GetPlayerName(self.source) or self.name, self.identifiers.ip, self.accountId,
    })

    self.lastSave = os.time()
    self.dirty = false
    self.charPlaytime = (self.charPlaytime or 0) + sessionSeconds
    return true
end

--- Async save used when a player drops (we still get the await callback).
function Player:saveBlocking()
    if not self.charId or not Nexus.DB.available then return false end
    self.lastSave = os.time()  -- keep playtime accounting sane if save() re-runs
    return self:save()
end

function Player:disconnectCleanup()
    Nexus.Players[self.source] = nil
    if self.charId then
        Nexus.PlayerByCharId[self.charId] = nil
    end
    Nexus.ReleaseStateId(self.stateId)
    Nexus.PlayerByIdentifier[self.identifier] = nil
end

-- ===========================================================================
--  REGISTRY
-- ===========================================================================

function Nexus.GetPlayer(source)
    if source == nil then return nil end
    return Nexus.Players[tonumber(source)]
end

function Nexus.GetPlayerByCharId(charId)
    return Nexus.PlayerByCharId[tonumber(charId)]
end

function Nexus.GetPlayerByIdentifier(identifier)
    return Nexus.PlayerByIdentifier[identifier]
end

--- Every logged-in player (skips players still on the character select screen
--- unless `includeLoading` is true).
function Nexus.GetPlayers(includeLoading)
    local out = {}
    for _, player in pairs(Nexus.Players) do
        if includeLoading or player.loaded then
            out[#out + 1] = player
        end
    end
    return out
end

function Nexus.GetPlayersByJob(jobName, onDutyOnly)
    local out = {}
    for _, player in pairs(Nexus.Players) do
        if player.loaded and player.job.name == jobName and (not onDutyOnly or player.job.onDuty) then
            out[#out + 1] = player
        end
    end
    return out
end

function Nexus.GetPlayersByJobType(jobType, onDutyOnly)
    local out = {}
    for _, player in pairs(Nexus.Players) do
        local def = Nexus.Jobs[player.job.name]
        if player.loaded and def and def.type == jobType and (not onDutyOnly or player.job.onDuty) then
            out[#out + 1] = player
        end
    end
    return out
end

--- Broadcast to a set of players (default: everyone logged in).
function Nexus.NotifyPlayers(players, message, ntype, duration, title)
    for _, player in ipairs(players or Nexus.GetPlayers()) do
        player:notify(message, ntype, duration, title)
    end
end

-- ===========================================================================
--  STATE ID ALLOCATION
-- ===========================================================================

local usedStateIds = {}

--- Smallest free ID starting at 1, mirroring the classic "player ID" display.
function Nexus.AllocateStateId(preferred)
    if preferred and not usedStateIds[preferred] then
        usedStateIds[preferred] = true
        return preferred
    end
    local id = 1
    while usedStateIds[id] do
        id = id + 1
    end
    usedStateIds[id] = true
    return id
end

function Nexus.ReleaseStateId(id)
    if id then usedStateIds[id] = nil end
end

function Nexus.IsStateIdTaken(id)
    return usedStateIds[id] == true
end

--- Server start / restart: rebuild the in-use table from the database so state
--- IDs stay stable across sessions.
function Nexus.PrimeStateIds(cb)
    if not Nexus.DB.available then
        if cb then cb() end
        return
    end
    local rows = Nexus.DB.query('SELECT state_id FROM nx_characters')
    for _, row in ipairs(rows or {}) do
        usedStateIds[tonumber(row.state_id)] = true
    end
    if cb then cb() end
end
