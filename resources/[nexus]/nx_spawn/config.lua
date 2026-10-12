-- Nexus :: nx_spawn/config.lua
-- Which spawn points are public (everyone) and which are job-only.
-- Points themselves are defined in nx_core/shared/config.lua (Config.SpawnPoints).

SpawnConfig = {
    -- Always offered, in this order.
    public = { 'legion', 'airport', 'beach', 'sandy', 'paleto', 'vineyard' },

    -- Only listed for these jobs.
    jobRestricted = {
        police    = { 'police' },
        ambulance = { 'hospital' },
        mechanic  = { 'mechanic' },
        taxi      = { 'taxi' },
    },

    -- Spawn at the exact spot the player logged out from. If false (or the
    -- position is unusable) the last named location is offered instead.
    lastPosition = true,

    -- Refuse to spawn inside this radius of these coords (someone's house etc).
    blockedZones = {
        -- { coords = vector3(0, 0, 0), radius = 0.0 },
    },

    -- Show the player's own last-known spot as the first option.
    highlightLast = true,

    -- How long the selector can stay open before it auto-picks the last location.
    autoSelectTimeout = 45000,
}
