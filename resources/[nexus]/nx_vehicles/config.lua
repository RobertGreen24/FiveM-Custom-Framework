-- Nexus :: nx_vehicles/config.lua

VehicleConfig = {
    -- Keys ------------------------------------------------------------------
    keys = {
        defaultKey   = 'U',          -- lock / unlock
        itemName     = 'vehicle_keys',
        requireItem  = false,        -- true = the key item must be in the inventory
        canShare     = true,         -- /givekeys hands a spare key to a nearby player
        shareDistance = 4.0,
        lockSound    = true,
        alarmOnPick  = true,
    },

    -- Fuel ------------------------------------------------------------------
    fuel = {
        enabled      = true,
        consumption  = 1.0,          -- multiplier; 1.0 drains a full tank in ~55 min of driving
        idleBurn     = 0.02,         -- litres per second while idling
        pumpRadius   = 12.0,
        pumpCost     = 8,            -- $ per litre
        jerrycanItem = 'jerrycan',
        jerrycanLitres = 20.0,
        refuelRate   = 1.6,          -- litres per second while pumping
        electricModels = {
            ['tesla'] = true, ['neon'] = true, ['cyclone'] = true, ['raiden'] = true,
        },
    },

    -- Driving aids ----------------------------------------------------------
    seatbelt = {
        enabled      = true,
        key          = 'B',
        ejectOnCrash = true,
        crashSpeed   = 45.0,         -- km/h above which an unbelted crash hurts
        ejectChance  = 0.55,
    },

    cruise = {
        enabled = true,
        key     = 'Y',
        minSpeed = 20.0,
        step     = 5.0,
        maxSpeed = 160.0,
    },

    engine = {
        key          = 'G',          -- engine on/off (needs a key)
        stallAtZeroFuel = true,
    },

    -- Hotwire ---------------------------------------------------------------
    hotwire = {
        enabled  = true,
        duration = 9000,
        failPain = 8.0,              -- health lost when the alarm goes off
        alarmDuration = 20000,
    },

    -- Damage / persistence --------------------------------------------------
    damage = {
        enabled        = true,
        saveFrequency  = 60,         -- seconds between state pushes
        writeOffBelow  = 0.05,       -- engine health ratio that counts as written off
    },

    -- Ownership -------------------------------------------------------------
    ownership = {
        maxPerCharacter = 20,
        transferCommand = 'givecar', -- /givecar [id] [plate]
        transferDistance = 5.0,
        transferFeeRatio = 0.05,     -- share of the value charged on a transfer
    },

    -- Cleanup ---------------------------------------------------------------
    cleanup = {
        emptyAfter   = 10 * 60,      -- seconds an abandoned player vehicle may linger
        detectRange  = 30.0,
        blipOwner    = true,         -- show a blip for your own spawned vehicles
    },

    plate = {
        changeCommand = 'plate',
        changePrice   = 5000,
        validator     = '^[A-Z0-9 ]{3,8}$',
    },
}

--- Petrol stations (the map already has the props; these are the pumps).
VehicleConfig.petrolStations = {
    { name = 'davis',    coords = vector3(-70.0, -1761.0, 29.3) },
    { name = 'legion',   coords = vector3(28.0, -1339.0, 29.3) },
    { name = 'vinewood', coords = vector3(265.0, -1261.0, 29.3) },
    { name = 'sandy',    coords = vector3(1965.0, 3740.0, 32.3) },
    { name = 'paleto',   coords = vector3(167.0, 6636.0, 31.7) },
    { name = 'route68',  coords = vector3(1039.0, 2671.0, 39.6) },
    { name = 'grapeseed',coords = vector3(1698.0, 4929.0, 42.1) },
    { name = 'airport',  coords = vector3(-727.0, -935.0, 19.2) },
}

--- Vehicles that may never be owned (job-spawned only).
VehicleConfig.restrictedModels = {
    ['rhino'] = true, ['lazer'] = true, ['hydra'] = true, ['buzzard2'] = true,
    ['cargoplane'] = true, ['titan'] = true,
}
