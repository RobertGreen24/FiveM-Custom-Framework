--[[
    Nexus Framework :: shared/jobs.lua
    Job definitions: grades, salaries, duty points, armouries, depots and blips.

    Every job is open data — add-on resources read from Nexus.Jobs, so a new job
    only needs a definition here (or a call to Nexus.RegisterJob at runtime) and
    the whole framework picks it up: HUD, payroll, admin panel, MDT, duty blips.

    Grade shape:
        name        string   display title
        salary      number   $ per payroll tick (Config.Jobs.payInterval minutes)
        boss        boolean  can manage society funds / hire / fire
        permissions table    arbitrary flags for job scripts (e.g. fast_duty)
        xp          number   xp needed to reach this grade (informational)
]]

Nexus = Nexus or {}
Nexus.Jobs = {}
Nexus.Gangs = {}

function Nexus.RegisterJob(name, data)
    assert(type(name) == 'string', 'RegisterJob: name must be a string')
    assert(type(data) == 'table', 'RegisterJob: data must be a table')
    data.name = name
    data.label = data.label or name:gsub('^%l', string.upper)
    data.type = data.type or 'none'          -- none | leo | ems | mechanic | taxi | business | crime
    data.grades = data.grades or { { name = 'Employee', salary = 250 } }
    data.defaultGrade = data.defaultGrade or 0
    data.paycheckInterval = data.paycheckInterval or 15
    data.blip = data.blip or nil              -- { sprite = 60, colour = 29, coords = vector3(...) }
    Nexus.Jobs[name] = data
    return Nexus.Jobs[name]
end

function Nexus.GetJob(name)
    return Nexus.Jobs[name]
end

function Nexus.GetJobLabel(name)
    local job = Nexus.Jobs[name]
    return job and job.label or name
end

function Nexus.GetJobGrade(jobName, grade)
    local job = Nexus.Jobs[jobName]
    if not job then return nil end
    return job.grades[(tonumber(grade) or 0) + 1]
end

function Nexus.GetGradeLabel(jobName, grade)
    local g = Nexus.GetJobGrade(jobName, grade)
    return g and g.name or 'Unknown'
end

--- Every grade index for a job, e.g. {0,1,2,3,4}
function Nexus.GetJobGradeIndices(jobName)
    local job = Nexus.Jobs[jobName]
    if not job then return {} end
    local out = {}
    for i = 1, #job.grades do out[i] = i - 1 end
    return out
end

--- Capability flags used by job scripts (`grade.permissions.fast_duty` etc).
function Nexus.JobHasPermission(jobName, grade, flag)
    local g = Nexus.GetJobGrade(jobName, grade)
    if g == nil or g.permissions == nil then return false end
    return g.permissions[flag] == true or g.permissions.all == true
end

--- Governance level: 'employee' | 'supervisor' | 'boss'
function Nexus.JobRank(jobName, grade)
    local g = Nexus.GetJobGrade(jobName, grade)
    if not g then return 'employee' end
    if g.boss then return 'boss' end
    if g.permissions and (g.permissions.hire or g.permissions.duty_all) then return 'supervisor' end
    return 'employee'
end

-- ============================================================================
--  JOBS
-- ============================================================================

Nexus.RegisterJob('unemployed', {
    label = 'Unemployed',
    type = 'none',
    grades = { { name = 'Civilian', salary = 0 } },
})

Nexus.RegisterJob('government', {
    label = 'City Government',
    type = 'business',
    grades = {
        { name = 'Intern',        salary = 300 },
        { name = 'Clerk',         salary = 450 },
        { name = 'Analyst',       salary = 700 },
        { name = 'Director',      salary = 1300, permissions = { hire = true } },
        { name = 'Mayor',         salary = 2500, boss = true, permissions = { hire = true, funds = true } },
    },
    blip = { sprite = 419, colour = 4, coords = vector3(-544.0, -204.0, 38.2), label = 'City Hall' },
})

Nexus.RegisterJob('police', {
    label = 'Los Santos Police',
    type = 'leo',
    grades = {
        { name = 'Cadet',            salary = 400, permissions = { arrest = true, armoury = true } },
        { name = 'Officer',          salary = 600, permissions = { arrest = true, armoury = true, vehicle = true } },
        { name = 'Senior Officer',   salary = 800, permissions = { arrest = true, armoury = true, vehicle = true, roadblock = true } },
        { name = 'Sergeant',         salary = 1050, permissions = { arrest = true, armoury = true, vehicle = true, roadblock = true, hire = true, mdt = true } },
        { name = 'Lieutenant',       salary = 1350, permissions = { arrest = true, armoury = true, vehicle = true, roadblock = true, hire = true, mdt = true, funds = true } },
        { name = 'Chief of Police',  salary = 1800, boss = true, permissions = { all = true, funds = true, hire = true, mdt = true } },
    },
    blip = { sprite = 60, colour = 29, coords = vector3(428.0, -981.0, 30.7), label = 'Mission Row PD' },
    dutyPoints = {
        { label = 'Mission Row Locker Room', coords = vector3(452.6, -993.0, 30.7), radius = 1.5 },
        { label = 'Sandy Shores Office',     coords = vector3(1853.0, 3689.6, 34.3), radius = 1.5 },
    },
    armory = {
        { item = 'weapon_pistol',     price = 0,    grade = 0 },
        { item = 'weapon_stungun',    price = 0,    grade = 0 },
        { item = 'ammo_pistol',       price = 0,    grade = 0 },
        { item = 'handcuffs',         price = 0,    grade = 0 },
        { item = 'spikestrip',        price = 0,    grade = 2 },
        { item = 'weapon_carbinerifle', price = 1500, grade = 2 },
        { item = 'ammo_rifle',        price = 250,  grade = 2 },
        { item = 'weapon_pumpshotgun', price = 1200, grade = 3 },
        { item = 'ammo_shotgun',      price = 200,  grade = 3 },
        { item = 'armour',            price = 500,  grade = 1 },
    },
    vehicles = {
        { model = 'police',          label = 'Police Cruiser',   grade = 1, garage = 'police' },
        { model = 'police2',         label = 'Police Interceptor',grade = 2, garage = 'police' },
        { model = 'police3',         label = 'Police SUV',       grade = 2, garage = 'police' },
        { model = 'policeb',         label = 'Police Bike',      grade = 1, garage = 'police' },
        { model = 'riot',            label = 'Riot Van',         grade = 4, garage = 'police' },
        { model = 'fbi',             label = 'Unmarked',         grade = 5, garage = 'police' },
    },
})

Nexus.RegisterJob('ambulance', {
    label = 'Pillbox Medical',
    type = 'ems',
    grades = {
        { name = 'Trainee',        salary = 400, permissions = { treat = true, revivify = true, vehicle = true } },
        { name = 'Paramedic',      salary = 700, permissions = { treat = true, revivify = true, vehicle = true, surgery = true } },
        { name = 'Doctor',         salary = 1000, permissions = { treat = true, revivify = true, vehicle = true, surgery = true } },
        { name = 'Surgeon',        salary = 1400, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 61, colour = 1, coords = vector3(307.7, -595.1, 43.3), label = 'Pillbox Hill Medical' },
    dutyPoints = {
        { label = 'Pillbox Bay', coords = vector3(310.0, -599.0, 43.3), radius = 1.5 },
    },
    armory = {
        { item = 'bandage',        price = 0,   grade = 0 },
        { item = 'medikit',        price = 0,   grade = 1 },
        { item = 'blood_bag',      price = 0,   grade = 1 },
        { item = 'defibrillator',  price = 0,   grade = 1 },
        { item = 'bodybag',        price = 0,   grade = 0 },
        { item = 'weapon_fireextinguisher', price = 0, grade = 0 },
    },
    vehicles = {
        { model = 'ambulance', label = 'Ambulance', grade = 0, garage = 'ambulance' },
        { model = 'nspeedo',   label = 'Rapid Response', grade = 2, garage = 'ambulance' },
        { model = 'riata',     label = 'Rescue SUV',  grade = 1, garage = 'ambulance' },
    },
})

Nexus.RegisterJob('mechanic', {
    label = 'Benny\'s Motor Works',
    type = 'mechanic',
    grades = {
        { name = 'Apprentice', salary = 350, permissions = { repair = true, tow = true, vehicle = true } },
        { name = 'Technician', salary = 550, permissions = { repair = true, tow = true, vehicle = true, spray = true } },
        { name = 'Lead Tech',  salary = 800, permissions = { repair = true, tow = true, vehicle = true, spray = true, tune = true } },
        { name = 'Owner',      salary = 1300, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 446, colour = 3, coords = vector3(-211.1, -1325.3, 30.9), label = 'Benny\'s Motor Works' },
    dutyPoints = {
        { label = 'Benny\'s Workshop', coords = vector3(-192.0, -1312.0, 31.3), radius = 1.5 },
    },
    armory = {
        { item = 'wrench',            price = 0, grade = 0 },
        { item = 'screwdriverset',    price = 0, grade = 0 },
        { item = 'repairkit',         price = 0, grade = 1 },
        { item = 'advanced_repairkit',price = 0, grade = 2 },
        { item = 'tyrekit',           price = 0, grade = 1 },
        { item = 'cleaningkit',       price = 0, grade = 1 },
        { item = 'tow_rope',          price = 0, grade = 1 },
    },
    vehicles = {
        { model = 'towtruck',  label = 'Tow Truck',   grade = 0, garage = 'mechanic' },
        { model = 'slamvan3',  label = 'Slamvan',     grade = 2, garage = 'mechanic' },
        { model = 'yosemite',  label = 'Yosemite',    grade = 1, garage = 'mechanic' },
    },
})

Nexus.RegisterJob('taxi', {
    label = 'Downtown Cab Co.',
    type = 'taxi',
    grades = {
        { name = 'Driver',     salary = 300, permissions = { meter = true, vehicle = true } },
        { name = 'Senior Driver', salary = 500, permissions = { meter = true, vehicle = true, dispatch = true } },
        { name = 'Dispatcher', salary = 750, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 198, colour = 5, coords = vector3(895.4, -179.0, 74.7), label = 'Downtown Cab Co.' },
    dutyPoints = {
        { label = 'Cab Rank', coords = vector3(894.0, -179.0, 74.7), radius = 2.0 },
    },
    vehicles = {
        { model = 'taxi', label = 'Taxi', grade = 0, garage = 'taxi' },
    },
})

Nexus.RegisterJob('realestate', {
    label = 'Dynasty 8',
    type = 'business',
    grades = {
        { name = 'Agent',    salary = 400, permissions = { sell = true, vehicle = true } },
        { name = 'Broker',   salary = 900, permissions = { sell = true, vehicle = true, keys = true } },
        { name = 'Director', salary = 1600, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 374, colour = 2, coords = vector3(-128.0, -633.0, 168.8), label = 'Dynasty 8' },
})

Nexus.RegisterJob('trucker', {
    label = 'J & Sons Haulage',
    type = 'business',
    grades = {
        { name = 'Loader',  salary = 300, permissions = { haul = true, vehicle = true } },
        { name = 'Driver',  salary = 500, permissions = { haul = true, vehicle = true, heavy = true } },
        { name = 'Foreman', salary = 800, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 477, colour = 47, coords = vector3(1208.0, -3116.0, 5.5), label = 'Haulage Depot' },
    vehicles = {
        { model = 'hauler',  label = 'Hauler',   grade = 1, garage = 'trucker' },
        { model = 'phantom', label = 'Phantom',  grade = 2, garage = 'trucker' },
    },
})

Nexus.RegisterJob('fisherman', {
    label = 'Cape Catfish',
    type = 'business',
    grades = {
        { name = 'Deckhand', salary = 250, permissions = { fish = true } },
        { name = 'Captain',  salary = 600, permissions = { fish = true, boat = true } },
        { name = 'Fleet Owner', salary = 1000, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 371, colour = 3, coords = vector3(-1604.0, -1100.0, 3.5), label = 'Cape Catfish' },
})

Nexus.RegisterJob('miner', {
    label = 'Davis Quarry',
    type = 'business',
    grades = {
        { name = 'Labourer', salary = 250, permissions = { mine = true } },
        { name = 'Foreman',  salary = 550, permissions = { mine = true, vehicle = true } },
        { name = 'Excavation Boss', salary = 950, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 318, colour = 40, coords = vector3(2957.0, 2748.0, 43.0), label = 'Davis Quarry' },
})

Nexus.RegisterJob('farmer', {
    label = 'Marlowe Vineyards',
    type = 'business',
    grades = {
        { name = 'Picker',   salary = 250, permissions = { farm = true } },
        { name = 'Harvester',salary = 500, permissions = { farm = true, vehicle = true } },
        { name = 'Land Owner', salary = 950, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 496, colour = 25, coords = vector3(-1885.0, 2053.6, 140.9), label = 'Marlowe Vineyards' },
})

Nexus.RegisterJob('cardealer', {
    label = 'Premium Deluxe Motorsport',
    type = 'business',
    grades = {
        { name = 'Sales',   salary = 400, permissions = { sell = true } },
        { name = 'Manager', salary = 900, boss = true, permissions = { all = true, funds = true, hire = true } },
    },
    blip = { sprite = 326, colour = 67, coords = vector3(-56.0, -1096.0, 26.4), label = 'PDM Showroom' },
})

-- ============================================================================
--  GANGS  ::  DB rows in nx_gangs extend (or replace) these defaults.
-- ============================================================================

local gangDefaults = {
    { 'none',     'No Affiliation', nil,   '#6b7280', 0 },
    { 'vagos',    'Vagos',          'VGS', '#eab308', 3 },
    { 'ballas',   'Ballas',         'BLS', '#a855f7', 3 },
    { 'families', 'Families',       'FML', '#22c55e', 3 },
    { 'lostmc',   'The Lost MC',    'LMC', '#ef4444', 4 },
    { 'cartel',   'Madrazo Cartel', 'MDZ', '#f97316', 4 },
}

for _, g in ipairs(gangDefaults) do
    Nexus.Gangs[g[1]] = {
        name = g[1],
        label = g[2],
        tag = g[3],
        colour = g[4],
        maxGrade = g[5],
        grades = { 'Associate', 'Member', 'Enforcer', 'Shot Caller', 'Boss', 'Kingpin' },
    }
end

function Nexus.RegisterGang(name, data)
    data.name = name
    data.label = data.label or name
    data.colour = data.colour or '#8b5cf6'
    data.grades = data.grades or { 'Member', 'Enforcer', 'Boss' }
    data.maxGrade = data.maxGrade or (#data.grades - 1)
    Nexus.Gangs[name] = data
    return Nexus.Gangs[name]
end

function Nexus.GetGang(name)
    return Nexus.Gangs[name]
end

function Nexus.GetGangLabel(name)
    local gang = Nexus.Gangs[name]
    return gang and gang.label or tostring(name)
end

function Nexus.GetGangGradeLabel(gangName, grade)
    local gang = Nexus.Gangs[gangName]
    if not gang then return 'Unknown' end
    return gang.grades[(tonumber(grade) or 0) + 1] or 'Unknown'
end
