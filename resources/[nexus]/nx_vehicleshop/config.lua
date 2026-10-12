-- Nexus :: nx_vehicleshop/config.lua
--
-- `showroom` is where the player stands to browse, `preview` is where the
-- model you are looking at appears, and `camera` is the orbit position.

ShopConfig = {
    registrationFee = 250,       -- $ added to every purchase
    testDriveTime   = 90,        -- seconds
    testDriveDistance = 400.0,   -- metres before the test drive is cancelled
    maxOwned        = 12,        -- vehicles one character may own
    finance = {
        enabled   = true,
        minDeposit = 0.20,       -- share of the price paid up front
        rates     = { 0.05, 0.08, 0.12, 0.18, 0.25 },  -- by credit score bucket
        scoreMin  = 0,
        scoreMax  = 1000,
        defaultScore = 650,
    },
    sellBack = {
        enabled    = true,
        percentage = 0.55,       -- of the original purchase price
    },
    -- Spawned preview vehicles are cleaned up if the shop is closed abruptly
    cleanupOnStop = true,
}

--- Catalogue categories (order shown in the UI) -----------------------------
ShopCategories = {
    { id = 'compacts', label = 'Compacts' },
    { id = 'sedans',   label = 'Sedans' },
    { id = 'suvs',     label = 'SUVs' },
    { id = 'muscle',   label = 'Muscle' },
    { id = 'sports',   label = 'Sports' },
    { id = 'super',    label = 'Super' },
    { id = 'bikes',    label = 'Motorcycles' },
    { id = 'vans',     label = 'Commercial' },
    { id = 'boats',    label = 'Boats' },
    { id = 'heli',     label = 'Aircraft' },
}

--- Dealerships ---------------------------------------------------------------
Shops = {
    {
        name = 'pdm',
        label = 'Premium Deluxe Motorsport',
        blip = { sprite = 326, colour = 67, scale = 0.8 },
        showroom = vector3(-45.0, -1093.0, 26.4),
        preview  = vector4(-45.0, -1105.0, 26.2, 70.0),
        camera   = { coords = vector3(-41.5, -1108.5, 27.6), lookAt = vector3(-45.0, -1105.0, 26.6) },
        categories = { 'compacts', 'sedans', 'suvs', 'muscle', 'sports', 'super', 'vans' },
        garage = 'legion',
        spawn  = vector4(-20.0, -1100.0, 26.6, 340.0),
    },
    {
        name = 'luxury',
        label = 'Luxury Autos',
        blip = { sprite = 326, colour = 27, scale = 0.8 },
        showroom = vector3(-796.0, -222.0, 37.0),
        preview  = vector4(-792.0, -230.0, 36.8, 340.0),
        camera   = { coords = vector3(-787.0, -226.0, 38.6), lookAt = vector3(-792.0, -230.0, 37.2) },
        categories = { 'super', 'sports', 'sedans' },
        garage = 'legion',
        spawn  = vector4(-800.0, -215.0, 37.0, 340.0),
    },
    {
        name = 'bennys',
        label = 'Benny\'s Original Motor Works',
        blip = { sprite = 446, colour = 3, scale = 0.8 },
        showroom = vector3(-211.0, -1327.0, 30.9),
        preview  = vector4(-211.0, -1338.0, 30.6, 340.0),
        camera   = { coords = vector3(-206.0, -1341.0, 32.2), lookAt = vector3(-211.0, -1338.0, 31.0) },
        categories = { 'muscle', 'sports', 'compacts' },
        garage = 'mechanic',
        spawn  = vector4(-215.0, -1330.0, 30.6, 340.0),
    },
    {
        name = 'boats',
        label = 'Boat Trader',
        blip = { sprite = 410, colour = 4, scale = 0.8 },
        showroom = vector3(-798.0, -1500.0, 5.0),
        preview  = vector4(-790.0, -1495.0, 1.0, 20.0),
        camera   = { coords = vector3(-784.0, -1498.0, 3.6), lookAt = vector3(-790.0, -1495.0, 1.4) },
        categories = { 'boats' },
        garage = 'marina',
        spawn  = vector4(-795.0, -1490.0, 1.0, 110.0),
    },
    {
        name = 'air',
        label = 'Elitás Travel',
        blip = { sprite = 423, colour = 4, scale = 0.8 },
        showroom = vector3(-1055.0, -2719.0, 20.2),
        preview  = vector4(-1043.0, -2725.0, 20.2, 330.0),
        camera   = { coords = vector3(-1035.0, -2720.0, 22.4), lookAt = vector3(-1043.0, -2725.0, 20.8) },
        categories = { 'heli', 'boats' },
        garage = 'airport',
        spawn  = vector4(-1030.0, -2728.0, 20.2, 330.0),
    },
}

--- Catalogue ------------------------------------------------------------------
--- vtype drives which garage accepts the vehicle.
ShopVehicles = {
    -- compacts
    { model = 'blista',      label = 'Blista',        price = 18000,  category = 'compacts', vtype = 'automobile' },
    { model = 'issi2',       label = 'Issi',          price = 16000,  category = 'compacts', vtype = 'automobile' },
    { model = 'panto',       label = 'Panto',         price = 14000,  category = 'compacts', vtype = 'automobile' },
    { model = 'rhapsody',    label = 'Rhapsody',      price = 19000,  category = 'compacts', vtype = 'automobile' },
    { model = 'asea',        label = 'Asea',          price = 17000,  category = 'compacts', vtype = 'automobile' },
    -- sedans
    { model = 'tailgater',   label = 'Tailgater',     price = 42000,  category = 'sedans',   vtype = 'automobile' },
    { model = 'schafter2',   label = 'Schafter',      price = 48000,  category = 'sedans',   vtype = 'automobile' },
    { model = 'fugitive',    label = 'Fugitive',      price = 39000,  category = 'sedans',   vtype = 'automobile' },
    { model = 'premier',     label = 'Premier',       price = 35000,  category = 'sedans',   vtype = 'automobile' },
    { model = 'stanier',     label = 'Stanier',       price = 36000,  category = 'sedans',   vtype = 'automobile' },
    -- suvs
    { model = 'baller',      label = 'Baller',        price = 62000,  category = 'suvs',     vtype = 'automobile' },
    { model = 'granger',     label = 'Granger',       price = 55000,  category = 'suvs',     vtype = 'automobile' },
    { model = 'landstalker', label = 'Landstalker',   price = 48000,  category = 'suvs',     vtype = 'automobile' },
    { model = 'rebla',       label = 'Rebla',         price = 58000,  category = 'suvs',     vtype = 'automobile' },
    -- muscle
    { model = 'dominator',   label = 'Dominator',     price = 72000,  category = 'muscle',   vtype = 'automobile' },
    { model = 'buffalo',     label = 'Buffalo',       price = 64000,  category = 'muscle',   vtype = 'automobile' },
    { model = 'sabregt',     label = 'Sabre Turbo',   price = 68000,  category = 'muscle',   vtype = 'automobile' },
    { model = 'gauntlet',    label = 'Gauntlet',      price = 70000,  category = 'muscle',   vtype = 'automobile' },
    { model = 'phoenix',     label = 'Phoenix',       price = 58000,  category = 'muscle',   vtype = 'automobile' },
    -- sports
    { model = 'elegy2',      label = 'Elegy RH8',     price = 125000, category = 'sports',   vtype = 'automobile' },
    { model = 'sultan',      label = 'Sultan',        price = 115000, category = 'sports',   vtype = 'automobile' },
    { model = 'jester',      label = 'Jester',        price = 145000, category = 'sports',   vtype = 'automobile' },
    { model = 'comet2',      label = 'Comet',         price = 135000, category = 'sports',   vtype = 'automobile' },
    { model = 'feltzer2',    label = 'Feltzer',       price = 128000, category = 'sports',   vtype = 'automobile' },
    { model = 'kuruma',      label = 'Kuruma',        price = 152000, category = 'sports',   vtype = 'automobile' },
    { model = 'ninef',       label = '9F',            price = 158000, category = 'sports',   vtype = 'automobile' },
    -- super
    { model = 'zentorno',    label = 'Zentorno',      price = 725000, category = 'super',    vtype = 'automobile' },
    { model = 'adder',       label = 'Adder',         price = 1000000, category = 'super',   vtype = 'automobile' },
    { model = 't20',         label = 'T20',           price = 2200000, category = 'super',   vtype = 'automobile' },
    { model = 'osiris',      label = 'Osiris',        price = 1950000, category = 'super',   vtype = 'automobile' },
    -- bikes
    { model = 'bati',        label = 'Bati 801',      price = 32000,  category = 'bikes',    vtype = 'bike' },
    { model = 'akuma',       label = 'Akuma',         price = 28000,  category = 'bikes',    vtype = 'bike' },
    { model = 'hakuchou',    label = 'Hakuchou',      price = 44000,  category = 'bikes',    vtype = 'bike' },
    { model = 'faggio',      label = 'Faggio',        price = 6000,   category = 'bikes',    vtype = 'bike' },
    { model = 'ruffian',     label = 'Ruffian',       price = 24000,  category = 'bikes',    vtype = 'bike' },
    -- commercial
    { model = 'speedo',      label = 'Speedo',        price = 38000,  category = 'vans',     vtype = 'truck' },
    { model = 'burrito',     label = 'Burrito',       price = 42000,  category = 'vans',     vtype = 'truck' },
    { model = 'bison',       label = 'Bison',         price = 46000,  category = 'vans',     vtype = 'truck' },
    { model = 'rumpo',       label = 'Rumpo',         price = 35000,  category = 'vans',     vtype = 'truck' },
    -- boats
    { model = 'dinghy',      label = 'Dinghy',        price = 85000,  category = 'boats',    vtype = 'boat' },
    { model = 'seashark',    label = 'Seashark',      price = 25000,  category = 'boats',    vtype = 'boat' },
    { model = 'tropic',      label = 'Tropic',        price = 145000, category = 'boats',    vtype = 'boat' },
    { model = 'jetmax',      label = 'Jetmax',        price = 185000, category = 'boats',    vtype = 'boat' },
    -- aircraft
    { model = 'buzzard2',    label = 'Buzzard',       price = 1200000, category = 'heli',     vtype = 'heli' },
    { model = 'maverick',    label = 'Maverick',      price = 780000,  category = 'heli',     vtype = 'heli' },
    { model = 'frogger',     label = 'Frogger',       price = 950000,  category = 'heli',     vtype = 'heli' },
}

--- Lookup helper used by both sides.
function ShopFindVehicle(model)
    for _, entry in ipairs(ShopVehicles) do
        if entry.model == model then return entry end
    end
    return nil
end
