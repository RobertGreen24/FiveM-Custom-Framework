--[[
    Nexus Framework :: shared/constants.lua
    The namespace every Nexus resource hangs off. Loaded first, on both sides.
]]

Nexus = Nexus or {}
Nexus.Version = '1.0.0'
Nexus.Name = 'Nexus'

--- Resource name helpers -----------------------------------------------------
--- Every Nexus resource is prefixed `nx_`. These helpers keep event names
--- consistent so add-on resources can hook in without guessing.
Nexus.Events = {
    -- server -> client
    PLAYER_LOADED       = 'nexus:client:playerLoaded',
    PLAYER_UNLOADED     = 'nexus:client:playerUnloaded',
    PLAYER_DATA         = 'nexus:client:playerData',
    STATE_CHANGED       = 'nexus:client:stateChanged',
    NOTIFY              = 'nexus:client:notify',
    MONEY_CHANGED       = 'nexus:client:moneyChanged',
    JOB_CHANGED         = 'nexus:client:jobChanged',
    GANG_CHANGED        = 'nexus:client:gangChanged',
    DUTY_CHANGED        = 'nexus:client:dutyChanged',
    LICENCE_CHANGED     = 'nexus:client:licenceChanged',
    DEATH               = 'nexus:client:death',
    RESPAWN             = 'nexus:client:respawn',
    OPEN_UI             = 'nexus:client:openUI',
    PROGRESS            = 'nexus:client:progress',
    TEXT_UI             = 'nexus:client:textUI',

    -- client -> server (requests)
    REQUEST_SPAWN       = 'nexus:server:requestSpawn',
    SET_POSITION        = 'nexus:server:setPosition',
    TOGGLE_DUTY         = 'nexus:server:toggleDuty',
    PLAYER_READY        = 'nexus:server:playerReady',

    -- core lifecycle
    CHARACTER_SELECTED  = 'nexus:server:characterSelected',
    CHARACTER_DELETED   = 'nexus:server:characterDeleted',
    SERVER_STARTED      = 'nexus:server:started',
    RESOURCE_READY      = 'nexus:server:resourceReady',

    -- client events other resources emit
    PLAYER_JUMPED       = 'nexus:client:onPlayerJump',
    ENTERED_VEHICLE     = 'nexus:client:enteredVehicle',
    LEFT_VEHICLE        = 'nexus:client:leftVehicle',
    COMBAT_ENTERED      = 'nexus:client:combatEntered',
}

--- Economy -------------------------------------------------------------------
Nexus.Accounts = {
    CASH    = 'cash',
    BANK    = 'bank',
    BLACK   = 'black',
    SAVINGS = 'savings',
}

Nexus.MoneyConfig = {
    symbol    = '$',
    startCash = 500,
    startBank = 5000,
    maxValue  = 2 ^ 31 - 1,
    accounts  = { 'cash', 'bank', 'black', 'savings' },
    labels    = { cash = 'Cash', bank = 'Bank', black = 'Dirty Money', savings = 'Savings' },
}

--- Character slots -----------------------------------------------------------
Nexus.CharacterSlots = {
    default = 4,
    premium = 6,
    max     = 10,
}

--- Permission ladder ---------------------------------------------------------
--- 0 = player, 1 = helper, 2 = moderator, 3 = admin, 4 = superadmin
--- ACE permissions (`nexus.admin.<action>`) always win if granted.
Nexus.Permissions = {
    NONE    = 0,
    HELPER  = 1,
    MOD     = 2,
    ADMIN   = 3,
    SUPER   = 4,
}

Nexus.PermissionLabels = { 'Player', 'Helper', 'Moderator', 'Administrator', 'Superadmin' }

--- Capability -> minimum admin level. Add-on resources can extend this table.
Nexus.Capabilities = {
    ['nexus.admin']            = Nexus.Permissions.ADMIN,
    ['nexus.admin.super']      = Nexus.Permissions.SUPER,
    ['nexus.admin.kick']       = Nexus.Permissions.MOD,
    ['nexus.admin.ban']        = Nexus.Permissions.MOD,
    ['nexus.admin.warn']       = Nexus.Permissions.MOD,
    ['nexus.admin.unban']      = Nexus.Permissions.ADMIN,
    ['nexus.admin.job']        = Nexus.Permissions.ADMIN,
    ['nexus.admin.money']      = Nexus.Permissions.SUPER,
    ['nexus.admin.vehicle']    = Nexus.Permissions.MOD,
    ['nexus.admin.heal']       = Nexus.Permissions.MOD,
    ['nexus.admin.teleport']   = Nexus.Permissions.MOD,
    ['nexus.admin.noclip']     = Nexus.Permissions.MOD,
    ['nexus.admin.inventory']  = Nexus.Permissions.ADMIN,
    ['nexus.admin.troll']      = Nexus.Permissions.ADMIN,
    ['nexus.admin.weather']    = Nexus.Permissions.ADMIN,
    ['nexus.admin.revive']     = Nexus.Permissions.MOD,
    ['nexus.admin.police']     = Nexus.Permissions.MOD,
}

--- Item categories -----------------------------------------------------------
Nexus.ItemTypes = {
    ITEM     = 'item',
    WEAPON   = 'weapon',
    AMMO     = 'ammo',
    FOOD     = 'food',
    DRINK    = 'drink',
    MEDICAL  = 'medical',
    TOOL     = 'tool',
    CLOTHING = 'clothing',
    KEY      = 'key',
    MONEY    = 'money',
    MISC     = 'misc',
}

--- Vehicle state -------------------------------------------------------------
Nexus.VehicleState = {
    OUT       = 0,
    STORED    = 1,
    IMPOUNDED = 2,
}

--- Notification types (matched by the NUI stylesheet) ------------------------
Nexus.NotificationTypes = { 'info', 'success', 'warning', 'error', 'police', 'ems', 'money' }

--- Vitals bounds -------------------------------------------------------------
Nexus.Vitals = {
    health = { min = 0, max = 200, label = 'Health' },
    armour = { min = 0, max = 100, label = 'Armour' },
    hunger = { min = 0, max = 100, label = 'Hunger' },
    thirst = { min = 0, max = 100, label = 'Thirst' },
    stress = { min = 0, max = 100, label = 'Stress' },
}

--- Weapon groups accepted by the inventory --------------------------------
Nexus.WeaponTypes = {
    MELEE    = 'melee',
    HANDGUN  = 'handgun',
    SMG      = 'smg',
    SHOTGUN  = 'shotgun',
    RIFLE    = 'rifle',
    MG       = 'machinegun',
    SNIPER   = 'sniper',
    HEAVY    = 'heavy',
    THROWABLE= 'throwable',
    MISC     = 'misc',
}

--- Which side are we running on? -------------------------------------------
--- `IsDuplicityVersion()` is provided by both runtimes (false on client), but
--- we fall back to a native check so the file also loads under plain Lua
--- tooling / unit tests.
local function detectServer()
    if type(IsDuplicityVersion) == 'function' then
        return IsDuplicityVersion() == true
    end
    return type(GetPlayers) == 'function'
end

Nexus.IsServer = detectServer()
Nexus.IsClient = not Nexus.IsServer
