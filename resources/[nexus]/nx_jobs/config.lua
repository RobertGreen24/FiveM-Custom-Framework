-- Nexus :: nx_jobs/config.lua
--
-- Payroll, duty points and the job centre. Jobs themselves are registered in
-- nx_core/shared/jobs.lua; this resource drives the day-to-day of holding one.

JobConfig = {
    payInterval     = 15,       -- minutes between paycheques (real time)
    payDutyOnly     = true,     -- only pay while on duty
    payWhileOffline = false,    -- bank salary earned during the pay window anyway
    announceDuty    = true,     -- notify colleagues when someone clocks in
    requireDutyPermission = false, -- true = only grades with permissions.duty may clock in
    dutyRange       = 5.0,      -- metres for clocking in/out
    allowGradeChange = true,    -- owners/managers can promote within their job
    maxGradeDelta   = 1,        -- how many grades a manager may move someone at once
    jobCommand      = 'job',    -- /job [name] — switches to an available/unemployed job

    -- Tax applied to every paycheque (share of gross). Society money is
    -- credited to the society account when the job has one.
    taxRate         = 0.09,

    -- Salary scaling by grade: grade 0 = base, each grade adds this share.
    gradeBonus      = 0.12,
}

--- Duty points. Players clock in/out here; each point can offer a stash and
--- a fleet of job vehicles (handled by nx_garages / nx_vehicles).
DutyPoints = {
    {
        name    = 'police_mrpd',
        label   = 'Mission Row PD',
        job     = 'police',
        coords  = vector3(441.0, -982.1, 30.7),
        blip    = { sprite = 60, colour = 38, scale = 0.85 },
        stash   = { slots = 60, weight = 200000, label = 'MRPD Locker Room' },
        dutyBlip = true,
    },
    {
        name    = 'police_sandy',
        label   = 'Sandy Shores Sheriff',
        job     = 'police',
        coords  = vector3(1853.0, 3688.0, 34.3),
        blip    = { sprite = 60, colour = 38, scale = 0.8 },
        stash   = { slots = 40, weight = 150000, label = 'Sandy Locker Room' },
    },
    {
        name    = 'ambulance_pillbox',
        label   = 'Pillbox Hill Medical',
        job     = 'ambulance',
        coords  = vector3(331.0, -595.0, 43.3),
        blip    = { sprite = 61, colour = 1, scale = 0.85 },
        stash   = { slots = 60, weight = 180000, label = 'Pillbox Locker Room' },
    },
    {
        name    = 'ambulance_paleto',
        label    = 'Paleto Bay Medical',
        job     = 'ambulance',
        coords  = vector3(-247.0, 6331.0, 32.4),
        blip    = { sprite = 61, colour = 1, scale = 0.8 },
    },
    {
        name    = 'mechanic_bennys',
        label = "Benny's Garage",
        job    = 'mechanic',
        coords  = vector3(-211.0, -1324.0, 30.9),
        blip    = { sprite = 446, colour = 3, scale = 0.85 },
        stash   = { slots = 50, weight = 200000, label = "Benny's Storage" },
    },
    {
        name    = 'taxi_depot',
        label   = 'Downtown Cab Co',
        job    = 'taxi',
        coords  = vector3(894.5, -179.5, 74.7),
        blip    = { sprite = 198, colour = 5, scale = 0.8 },
    },
    {
        name    = 'government_cityhall',
        label   = 'City Hall',
        job    = 'government',
        coords  = vector3(-545.0, -204.0, 38.2),
        blip    = { sprite = 419, colour = 4, scale = 0.8 },
        stash   = { slots = 40, weight = 100000, label = 'City Hall Storage' },
    },
    {
        name    = 'trucker_depot',
        label   = 'LS Freight Depot',
        job    = 'trucker',
        coords  = vector3(1208.0, -1265.0, 36.0),
        blip    = { sprite = 477, colour = 47, scale = 0.8 },
    },
    {
        name    = 'fisherman_docks',
        label = 'Del Perro Pier',
        job    = 'fisherman',
        coords  = vector3(-1814.0, -1166.0, 13.3),
        blip    = { sprite = 371, colour = 3, scale = 0.8 },
    },
    {
        name    = 'miner_quarry',
        label   = 'Davis Quarry',
        job    = 'miner',
        coords  = vector3(2947.0, 2749.0, 43.3),
        blip    = { sprite = 527, colour = 47, scale = 0.8 },
    },
    {
        name    = 'farmer_field',
        label   = 'Grapeseed Fields',
        job    = 'farmer',
        coords  = vector3(2743.0, 4452.0, 48.6),
        blip    = { sprite = 496, colour = 25, scale = 0.8 },
    },
}

--- Where the player can change job (public employment office).
JobCentre = {
    label  = 'Employment Office',
    coords = vector3(-265.0, -963.0, 31.2),
    blip   = { sprite = 407, colour = 4, scale = 0.8 },
    -- jobs a player may simply walk in and take; everything else needs a hiring
    -- event from another resource (nx_police, nx_ems, ...).
    open = {
        'unemployed', 'taxi', 'trucker', 'fisherman', 'miner', 'farmer', 'realestate',
    },
}

JobConfig.dutyPoints = DutyPoints
JobConfig.jobCentre = JobCentre
