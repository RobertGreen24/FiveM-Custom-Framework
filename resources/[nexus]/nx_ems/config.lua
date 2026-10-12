-- Nexus :: nx_ems/config.lua

EmsConfig = {
    job             = 'ambulance',
    reviveItem      = 'medikit',
    bandageItem     = 'bandage',
    reviveTime      = 12000,     -- ms spent reviving
    reviveHealth    = 35.0,      -- health the patient wakes up with (0-100)
    treatTime       = 6000,
    treatHealth     = 25.0,
    treatArmour     = 10.0,
    -- A failed revive (walking away) loses the patient a life
    failPenalty     = 5.0,

    -- How long a downed player may be revived before they must respawn
    deathWindow     = 300,       -- seconds (matches Config.Death.respawnTime in nx_core)

    -- Charge the patient for treatment (paid to the ambulance society)
    billPatients   = true,
    reviveFee       = 750,
    treatFee        = 250,
    billAtHospital  = true,      -- send the bill when they are dropped at a hospital

    -- Carrying
    allowStretcher  = true,
    stretcherModel  = 'gurney',
    carryDistance   = 1.8,

    -- Ambulance spawn points (used by the MDT quick actions)
    vehicles = {
        { model = 'ambulance',   label = 'Ambulance' },
        { model = 'ambulance3',  label = 'Rapid Response' },
        { model = 'ambulance4',  label = 'Air Ambulance' },
        { model = 'lguard',      label = 'Lifeguard' },
    },

    -- Supply lockers at each hospital (shared stash ids)
    supplies = {
        { hospital = 'pillbox', stash = 'ambulance_locker', label = 'Pillbox Supply Room' },
    },

    -- Loadout drawn from the hospital supply room
    loadout = {
        { item = 'bandage',  amount = 10 },
        { item = 'medikit',  amount = 3 },
        { item = 'painkillers', amount = 5 },
        { item = 'weapon_flashlight', amount = 1 },
        { item = 'radio',    amount = 1 },
    },
}

--- Hospitals: bed coordinates used for spawning patients when they respawn.
EmsConfig.hospitals = {
    {
        name = 'pillbox', label = 'Pillbox Hill Medical Center',
        coords = vector3(307.7, -595.0, 43.3), heading = 340.0,
        bed = vector3(354.0, -584.4, 28.8),
        blip = { sprite = 61, colour = 1 },
    },
    {
        name = 'sandy', label = 'Sandy Shores Medical',
        coords = vector3(1839.6, 3672.9, 34.3), heading = 210.0,
        bed = vector3(1826.0, 3665.0, 34.2),
        blip = { sprite = 61, colour = 1 },
    },
    {
        name = 'paleto', label = 'Paleto Bay Clinic',
        coords = vector3(-242.0, 6328.0, 32.4), heading = 224.0,
        bed = vector3(-228.0, 6329.0, 32.4),
        blip = { sprite = 61, colour = 1 },
    },
    {
        name = 'jungle', label = 'Mount Zonah Medical',
        coords = vector3(-448.0, -338.0, 34.5), heading = 12.0,
        bed = vector3(-440.0, -343.0, 34.2),
        blip = { sprite = 61, colour = 1 },
    },
}

--- Injury labels shown in the death/alert UI ("shot", "beaten", ...).
EmsConfig.causes = {
    [0] = 'Unknown',
    [1] = 'Blunt force trauma',
    [2] = 'Gunshot wound',
    [3] = 'Stab wound',
    [4] = 'Vehicle impact',
    [5] = 'Fall damage',
    [6] = 'Burns',
    [7] = 'Drowning',
    [8] = 'Drug overdose',
    [9] = 'Explosion',
}
