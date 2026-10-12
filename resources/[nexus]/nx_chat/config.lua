-- Nexus :: nx_chat/config.lua

ChatConfig = {
    key            = 'T',        -- open the chat box
    historyKey     = 'UP',       -- browse message history from the input
    maxHistory     = 60,         -- messages kept in the scrollback
    maxLength      = 200,
    fadeAfter      = 0,          -- 0 = messages stay until the max history rolls
    timestamps     = true,
    suggestions    = true,       -- show the command list while typing "/"
    theme          = 'dark',

    -- Chat ranges (metres). 0 = global.
    ranges = {
        local_  = 12.0,
        me      = 12.0,
        do_     = 12.0,
        whisper = 3.0,
        shout   = 30.0,
        radio   = 0.0,
    },

    -- Advertising
    advert = {
        enabled  = true,
        cooldown = 120,          -- seconds between /ad messages
        cost     = 250,          -- $ per advert (0 = free)
        prefix   = 'ADVERT',
    },

    -- Twitter-style channel
    twitter = {
        enabled = true,
        cooldown = 30,
        prefix  = 'Twitter',
        anonymousChance = 0.0,
    },

    -- Staff-only channel
    staff = {
        enabled = true,
        prefix  = 'STAFF',
    },

    -- Auto messages cycled into the chat for new players / ambience
    announcements = {
        enabled  = true,
        interval = 240,          -- seconds between announcements
        messages = {
            'Press F1 for help · use /commands to see everything you can do.',
            'Need a ride? Call a taxi with /taxi or dial it on the phone.',
            'Emergencies: /911 <message> reaches the police and ambulance service.',
            'Join a job at the employment office in Pillbox Hill.',
        },
    },
}

--- Channels shown as tabs in the NUI. `command` is the prefix players type.
ChatChannels = {
    { id = 'all',      label = 'All',      colour = '#e5e7eb' },
    { id = 'ooc',      label = 'OOC',      colour = '#93c5fd', command = 'ooc' },
    { id = 'me',       label = 'Me',       colour = '#c4b5fd', command = 'me',  range = 'me' },
    { id = 'do',       label = 'Do',       colour = '#c4b5fd', command = 'do',  range = 'do_' },
    { id = 'ad',       label = 'Ads',      colour = '#fcd34d', command = 'ad' },
    { id = 'twt',      label = 'Twitter',  colour = '#67e8f9', command = 'twt' },
    { id = 'dispatch', label = 'Dispatch', colour = '#fca5a5', command = 'dispatch' },
    { id = 'staff',    label = 'Staff',    colour = '#f9a8d4', command = 'staff' },
}

--- Commands listed in the autocomplete. Add your own with
--- `Nexus.ChatCommands[#Nexus.ChatCommands + 1] = { name = ..., description = ... }`.
Nexus = Nexus or {}
Nexus.ChatCommands = {
    { name = '/me',       description = 'Describe an action performed by your character' },
    { name = '/do',       description = 'Describe the environment or a result' },
    { name = '/ooc',      description = 'Out-of-character (global, wrapped in (( )))' },
    { name = '/whisper',  description = 'Whisper  (/whisper [id] [text])' },
    { name = '/shout',    description = 'Shout — heard further away' },
    { name = '/ad',       description = 'Paid advertisement (see the price in the UI)' },
    { name = '/twt',      description = 'Post to the Twitter feed' },
    { name = '/911',      description = 'Emergency call to police and ambulance' },
    { name = '/311',      description = 'Non-emergency call to the police' },
    { name = '/taxi',     description = 'Call a taxi to your location' },
    { name = '/report',   description = 'Report a player to staff' },
    { name = '/help',     description = 'Open the help panel' },
    { name = '/job',      description = 'Show or change your job' },
    { name = '/duty',     description = 'Clock in or out at a duty point' },
    { name = '/bank',     description = 'Open your bank account' },
    { name = '/mdt',      description = 'Open the police / medical terminal' },
    { name = '/garage',   description = 'Open the nearest garage' },
    { name = '/switch',   description = 'Return to character selection' },
}
