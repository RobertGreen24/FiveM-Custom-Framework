--[[
    Nexus Framework :: shared/config.lua
    Settings that must exist on BOTH the client and the server.
    Server-only tuning lives in config/server.lua, client-only in config/client.lua.
]]

Config = {}

--- Meta ----------------------------------------------------------------------
Config.Locale      = 'en'                -- see nx_core/locales/
Config.Debug       = false               -- verbose [nexus] prints
Config.DevMode     = false               -- exposes /nx_dev commands + reload commands
Config.FrameworkName = 'Nexus'
Config.ShowWelcome = true                -- server welcome message on join

--- Multi-character -----------------------------------------------------------
Config.Multicharacter = {
    enabled      = true,
    defaultSlots = 4,
    maxSlots     = 10,
    minAge       = 18,
    maxAge       = 90,
    nameMinLength = 2,
    nameMaxLength = 24,
    -- Purely for flavour, shown in the character list:
    nationalities = {
        'American', 'British', 'Irish', 'Mexican', 'Italian', 'Russian',
        'Japanese', 'Chinese', 'Indian', 'Australian', 'Canadian', 'French',
    },
    -- Camera looks at this heading while you sit on the select screen
    camera = {
        default = { coords = vector3(-75.9, -818.6, 326.2), lookAt = vector3(-75.0, -816.0, 325.0) },
    },
}

--- Spawn locations -----------------------------------------------------------
--- Used by nx_spawn (last-location spawn), nx_multicharacter and /respawn.
Config.SpawnPoints = {
    legion      = { label = 'Legion Square',       coords = vector4(215.76, -810.13, 30.73, 243.5) },
    airport     = { label = 'LS International',    coords = vector4(-1037.7, -2737.7, 20.17, 329.0) },
    sandy       = { label = 'Sandy Shores',        coords = vector4(1848.5, 3689.0, 34.27, 210.0) },
    paleto      = { label = 'Paleto Bay',          coords = vector4(-278.3, 6637.0, 7.5, 45.0) },
    hospital    = { label = 'Pillbox Hill Medical',coords = vector4(307.7, -595.1, 43.28, 340.0) },
    police      = { label = 'Mission Row PD',      coords = vector4(425.1, -979.5, 30.71, 90.0) },
    mechanic    = { label = 'Benny\'s Motor Works',coords = vector4(-211.1, -1325.3, 30.89, 320.0) },
    taxi        = { label = 'Downtown Cab Co.',    coords = vector4(895.4, -179.0, 74.7, 240.0) },
    beach       = { label = 'Vespucci Beach',      coords = vector4(-1221.0, -1433.6, 4.3, 130.0) },
    vineyard    = { label = 'Marlowe Vineyards',   coords = vector4(-1885.0, 2053.6, 140.9, 220.0) },
}

Config.DefaultSpawn = 'legion'

--- Vitals --------------------------------------------------------------------
--- Values are per-minute drain/interaction rates. The HUD thread applies them.
Config.Vitals = {
    enabled        = true,
    startHunger    = 100,
    startThirst    = 100,
    startStress    = 0,
    -- drain per minute while idle
    hungerDecay    = 0.55,
    thirstDecay    = 0.75,
    -- extra drain per minute while sprinting / swimming
    sprintMultiplier = 2.4,
    -- stress
    stressDecay    = 0.4,      -- natural recovery per minute
    stressFromCombat = 3,      -- added per shot fired nearby
    stressFromFastDriving = 2,
    -- effects kick in below these thresholds
    sprintDisabledAt = 8,      -- hunger/thirst
    healthDrainAt    = 0,      -- hunger/thirst: starts damaging at 0
    healthDrainInterval = 30,  -- seconds between damage ticks
    -- alarms
    warnAt = 25,
}

--- Death / respawn -----------------------------------------------------------
Config.Death = {
    respawnTime       = 300,     -- seconds of 'hospital' hold before automatic respawn
    manualRespawnCost = 500,     -- fee to respawn early (deducted from bank)
    blackoutOnDeath   = true,    -- fade to black while downed
    allowSuicideCmd   = true,
    medicalItems      = { 'bandage', 'medikit', 'defibrillator' },
    reviveHealth      = 120,
    reviveArmour      = 0,
    lootOnDeath       = true,    -- drop inventory into a lootable bag
    lootTimeout       = 300,     -- seconds a death bag persists
}

--- Stamina / melee combat ----------------------------------------------------
Config.Combat = {
    combatLogTime   = 10,        -- seconds you stay 'in combat' after taking fire
    bleedOutTime    = 600,       -- seconds before an unrevived player dies outright
    headshotInstant = false,     -- if true, headshots on downed players finish them
}

--- Inventory -----------------------------------------------------------------
Config.Inventory = {
    maxWeight          = 40000,  -- grams
    maxSlots           = 40,
    dropWeight         = 8000,
    dropSlots          = 12,
    trunkSlots         = 35,
    gloveboxSlots      = 10,
    hotbarSlots        = 5,
    -- weight per slot when a slot is empty (keeps the grid readable)
    showEmptySlots     = true,
    -- item name -> world object used for dropped weapons
    weaponDropModel    = 'w_me_pistol',
    -- how far away another player can be for a give/trade prompt
    interactionRange   = 3.0,
    -- money item names that should never occupy a slot
    virtualItems       = { cash = true, bank = true, black = true, savings = true },
}

--- Vehicle keys --------------------------------------------------------------
Config.VehicleKeys = {
    system      = 'nexus',  -- 'nexus' | 'none'
    giveKeys    = true,
    lockOnExit  = true,
    hornOnLock  = false,
    hotwireTime = 8000,     -- ms to hotwire a stolen car
}

--- Fuel ----------------------------------------------------------------------
Config.Fuel = {
    enabled      = true,
    rate         = 1.0,      -- multiplier on fuel consumption
    nozzleCost   = 12,       -- $ per fuel unit
    electricBoost = 1.4,
}

--- Duty / jobs ---------------------------------------------------------------
Config.Jobs = {
    allowMultiple      = false,  -- if true a player can hold a second (side) job
    payInterval        = 15,     -- minutes between automatic payroll ticks
    salaryOnDutyOnly   = true,
    resetOnUnemployed  = true,
    -- xp/grade progression
    xpPerPayroll       = 20,
    xpPerAction        = 5,
}

--- Notifications ---------------------------------------------------------------
Config.Notifications = {
    defaultDuration = 5000,  -- ms
    maxVisible      = 5,
    position        = 'top-right',
}

--- Interaction ----------------------------------------------------------------
--- Shared by nx_inventory, nx_garages, nx_shops and friends so the whole server
--- uses one consistent "press E" experience.
Config.Interaction = {
    key        = 38,      -- E
    distance   = 2.5,
    drawSprite = true,
}

--- Blips ----------------------------------------------------------------------
Config.Blips = {
    enabled   = true,
    police    = 1,   -- colour ids
    ambulance = 2,
    mechanic  = 3,
    shop      = 4,
    garage    = 5,
    bank      = 6,
}
