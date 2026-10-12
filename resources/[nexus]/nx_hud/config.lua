-- Nexus :: nx_hud/config.lua

HudConfig = {
    enabled = true,

    -- Which blocks to draw.
    elements = {
        status     = true,     -- health / armour / hunger / thirst / stress rings
        money      = true,
        job        = true,
        player     = true,     -- name + server id
        vehicle    = true,
        voice      = true,
        serverinfo = true,     -- framework name + online count
        date       = true,
        ammo       = true,
        stamina    = false,
        compass    = false,
    },

    -- mph | kph
    speedUnit = 'mph',

    -- Native HUD components to hide (we draw our own).
    hideNative = {
        3,      -- cash
        4,      -- MP cash
        7,      -- area name
        13,     -- cash change
        19,     -- weapon wheel (no, leave it) -- remove this line to keep the wheel
    },

    -- Minimap look.
    minimap = {
        square   = true,
        scale    = 0.9,
        x        = 0.0,
        y        = 0.0,
        streetName = true,      -- native street name above the minimap
    },

    -- Colours (hex) for the rings, low to high.
    colours = {
        health = { low = '#ef4444', mid = '#f59e0b', high = '#22c55e' },
        armour = '#3b82f6',
        hunger = '#f59e0b',
        thirst = '#22d3ee',
        stress = '#a855f7',
    },

    -- Update rate for the NUI payload (ms). 100 is smooth without being heavy.
    updateInterval = 100,

    -- Flash the money field when it changes.
    moneyAnimation = true,

    -- Show a "NEW" pulse on the job badge when it changes.
    jobAnimation = true,
}
