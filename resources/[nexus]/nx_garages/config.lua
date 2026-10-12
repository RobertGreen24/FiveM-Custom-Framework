-- Nexus :: nx_garages/config.lua
--
-- Garages are car parks with a spawn point. Job garages additionally require a
-- job (and optionally a minimum grade). Impound lots only release vehicles that
-- were impounded (and charge a fee).

GarageConfig = {
    spawnRadius     = 8.0,      -- how close to the marker you must be to open
    maxSpeedOnStore = 12.0,     -- km/h — above this, "store" refuses
    storeDelay      = 2500,     -- ms the store animation takes
    retrieveDelay   = 2000,
    impoundFee      = 1500,     -- release fee (paid to the police society)
    impoundRate     = 90,       -- $ per hour in the lot, capped below
    impoundFeeCap   = 7500,
    saveFuel        = true,
    repairOnRetrieve = 0.0,     -- 0 = store the damage, 1 = fully repair on retrieve
    keysOnRetrieve  = true,
    engineOnRetrieve = false,
}

--- Vehicle type buckets used by the UI (filter chips) and by the spawn checks.
GarageConfig.types = {
    { id = 'automobile', label = 'Cars' },
    { id = 'bike',       label = 'Bikes' },
    { id = 'truck',      label = 'Trucks' },
    { id = 'heli',       label = 'Helicopters' },
    { id = 'plane',      label = 'Planes' },
    { id = 'boat',       label = 'Boats' },
}

Garages = {
    {
        name = 'legion', label = 'Legion Square Garage', type = 'public',
        coords = vector3(215.0, -810.0, 30.7),     -- where you open the menu
        spawn  = vector4(229.0, -800.0, 30.6, 160.0),
        blip   = { sprite = 357, colour = 3 },
        capacity = 4,
    },
    {
        name = 'legion_bike', label = 'Legion Bikes', type = 'public',
        coords = vector3(214.0, -788.0, 30.7),
        spawn  = vector4(218.0, -782.0, 30.6, 340.0),
        blip   = { sprite = 522, colour = 3 },
        types  = { 'bike' },
        capacity = 3,
    },
    {
        name = 'pillbox', label = 'Pillbox Garage', type = 'public',
        coords = vector3(215.0, -807.0, 30.7),
        spawn  = vector4(208.0, -791.0, 30.6, 340.0),
        blip   = { sprite = 357, colour = 3 },
        capacity = 4,
    },
    {
        name = 'sandy', label = 'Sandy Shores Garage', type = 'public',
        coords = vector3(1738.0, 3711.0, 34.3),
        spawn  = vector4(1725.0, 3716.0, 34.2, 20.0),
        blip   = { sprite = 357, colour = 3 },
        capacity = 4,
    },
    {
        name = 'paleto', label = 'Paleto Bay Garage', type = 'public',
        coords = vector3(-227.0, 6331.0, 32.4),
        spawn  = vector4(-215.0, 6325.0, 32.4, 130.0),
        blip   = { sprite = 357, colour = 3 },
        capacity = 4,
    },
    {
        name = 'airport', label = 'LSIA Hangar', type = 'public',
        coords = vector3(-1006.0, -2900.0, 13.9),
        spawn  = vector4(-1020.0, -2880.0, 13.9, 340.0),
        blip   = { sprite = 360, colour = 3 },
        types  = { 'heli', 'plane' },
        capacity = 6,
    },
    {
        name = 'marina', label = 'Marina Docks', type = 'public',
        coords = vector3(-800.0, -1330.0, 5.0),
        spawn  = vector4(-820.0, -1345.0, 1.0, 100.0),
        blip   = { sprite = 410, colour = 3 },
        types  = { 'boat' },
        capacity = 4,
    },
    {
        name = 'police_mrpd', label = 'MRPD Motor Pool', type = 'job',
        coords = vector3(452.0, -1000.0, 30.7),
        spawn  = vector4(438.0, -1018.0, 28.7, 95.0),
        blip   = { sprite = 60, colour = 38 },
        job = 'police',
        minGrade = 0,
        capacity = 8,
        fleet = true,       -- job garage: spawn/free return, no ownership
        fleetVehicles = {
            { model = 'police', label = 'Cruiser' },
            { model = 'police2', label = 'Interceptor' },
            { model = 'police3', label = 'Unmarked' },
            { model = 'riot', label = 'Riot Van' },
            { model = 'policeb', label = 'Motorcycle' },
            { model = 'polmav', label = 'Helicopter' },
        },
    },
    {
        name = 'ambulance_pillbox', label = 'Pillbox Ambulance Bay', type = 'job',
        coords = vector3(305.0, -590.0, 43.3),
        spawn  = vector4(295.0, -600.0, 43.3, 70.0),
        blip   = { sprite = 61, colour = 1 },
        job = 'ambulance',
        capacity = 6,
        fleet = true,
        fleetVehicles = {
            { model = 'ambulance', label = 'Ambulance' },
            { model = 'ambulance3', label = 'Rapid Response' },
            { model = 'lguard', label = 'Lifeguard' },
        },
    },
    {
        name = 'mechanic_bennys', label = "Benny's Garage", type = 'job',
        coords = vector3(-205.0, -1315.0, 31.0),
        spawn  = vector4(-215.0, -1320.0, 30.9, 130.0),
        blip   = { sprite = 446, colour = 3 },
        job = 'mechanic',
        capacity = 6,
        fleet = true,
        fleetVehicles = {
            { model = 'towtruck', label = 'Tow Truck' },
            { model = 'slamvan', label = 'Slamvan' },
            { model = 'flatbed', label = 'Flatbed' },
        },
    },
}

--- Impound lots: only vehicles with state = 2 (impounded) appear here.
Impounds = {
    {
        name = 'police_impound', label = 'LS Impound Lot', type = 'impound',
        coords = vector3(409.0, -1623.0, 29.3),
        spawn  = vector4(400.0, -1640.0, 29.0, 230.0),
        blip   = { sprite = 68, colour = 38 },
        job = 'police',     -- which society gets the fee (optional)
    },
    {
        name = 'sandy_impound', label = 'Sandy Impound', type = 'impound',
        coords = vector3(1727.0, 3710.0, 34.3),
        spawn  = vector4(1715.0, 3700.0, 34.3, 20.0),
        blip   = { sprite = 68, colour = 38 },
        job = 'police',
    },
}

--- Returns a garage/impound definition by name.
function GarageFind(name)
    for _, garage in ipairs(Garages) do
        if garage.name == name then return garage end
    end
    for _, impound in ipairs(Impounds) do
        if impound.name == name then return impound end
    end
    return nil
end

--- Simple type check used when retrieving.
function GarageAllowsType(garage, vtype)
    if not garage.types then return true end
    for _, allowed in ipairs(garage.types) do
        if allowed == vtype then return true end
    end
    return false
end
