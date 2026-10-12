-- Nexus :: nx_police/config.lua

PoliceConfig = {
    job             = 'police',
    minGrade        = 0,          -- lowest grade allowed to use police tools
    callsignCommand = 'callsign',
    mdtCommand      = 'mdt',
    jailCommand     = 'jail',

    -- Custody
    maxSentence     = 60,         -- minutes
    jailReleaseFee  = 1500,       -- fine paid at release (per sentence minute / 10)
    jailFinePerMin  = 90,
    stripOnJail     = true,
    seizableItems   = {
        'weapon_pistol', 'weapon_microsmg', 'weapon_knife', 'weapon_bat',
        'ammo_pistol', 'ammo_smg', 'lockpick', 'advanced_lockpick',
        'weed', 'cocaine', 'meth', 'heroin', 'ecstasy', 'joint',
        'marked_bills', 'thermite', 'c4', 'stolen_watch', 'stolen_phone',
        'stolen_tv', 'stolen_laptop', 'gold_bar', 'weapon_parts',
    },

    -- Fines
    fineCommand     = 'fine',
    maxFine         = 25000,
    unpaidFineLimit = 50000,      -- above this the player cannot hold a licence
    wantedFineRatio = 0.15,       -- unpaid ratio that makes you "wanted"

    -- Radar
    radarCommand    = 'radar',
    radarToggleKey  = 'F5',
    speedLimit      = 90,         -- km/h before the radar flags you
    radarFine       = 350,
    radarMaxSpeed   = 220,

    -- Equipment
    loadout = {
        { item = 'handcuffs', amount = 1 },
        { item = 'weapon_stungun', amount = 1 },
        { item = 'ammo_stungun', amount = 40 },
        { item = 'weapon_pistol', amount = 1 },
        { item = 'ammo_pistol', amount = 120 },
        { item = 'weapon_nightstick', amount = 1 },
        { item = 'flashlight', amount = 1 },
        { item = 'radio', amount = 1 },
        { item = 'bandage', amount = 3 },
        { item = 'evidence_bag', amount = 5 },
    },

    -- Evidence storage (shared by the whole department)
    evidence = {
        stash     = 'police_evidence',
        slots     = 120,
        weight    = 500000,
        dirty     = true,
        logAccess = true,
    },

    -- Impound authority
    canImpound  = true,
    impoundFee  = 1500,

    -- Radio channels used by dispatch (nx_phone will offer the UI)
    channels = {
        { id = 1, name = 'Dispatch',  restricted = false, job = 'police' },
        { id = 2, name = 'Tac 2',     restricted = true,  job = 'police' },
        { id = 3, name = 'Sheriff',   restricted = true,  job = 'police' },
        { id = 4, name = 'Traffic',   restricted = false, job = 'police' },
        { id = 5, name = 'Detective', restricted = true,  job = 'police' },
    },
}

--- Patrol vehicle spawns used by the MDT quick-actions.
PoliceConfig.vehicles = {
    { model = 'police',        label = 'Cruiser' },
    { model = 'police2',       label = 'Interceptor' },
    { model = 'police3',       label = 'Unmarked' },
    { model = 'polmav',        label = 'Helicopter' },
    { model = 'riot',          label = 'Riot Van' },
    { model = 'fbi2',          label = 'Slicktop SUV' },
    { model = 'ambulance',     label = 'Rescue' },
    { model = 'policeb',       label = 'Motorcycle' },
}
