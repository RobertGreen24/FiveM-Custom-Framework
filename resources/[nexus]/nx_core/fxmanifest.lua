fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_core'
author 'Nexus Framework'
description 'Nexus core: player object, economy, jobs, permissions, character flow and the shared UI kit.'
version '1.0.0'

dependencies {
    'oxmysql',
}

shared_scripts {
    'locales/en.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'shared/config.lua',
    'shared/items.lua',
    'shared/jobs.lua',
    'shared/callbacks.lua',
}

client_scripts {
    'client/state.lua',
    'client/nui.lua',
    'client/vitals.lua',
    'client/death.lua',
    'client/util.lua',
    'client/main.lua',
    'client/exports.lua',
}

server_scripts {
    'server/database.lua',
    'server/log.lua',
    'server/player.lua',
    'server/characters.lua',
    'server/society.lua',
    'server/admin.lua',
    'server/main.lua',
    'server/exports.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

-- oxmysql is the only hard dependency; everything else is optional and detected
-- at runtime (nx_inventory, nx_vehicles, nx_hud, pma-voice ...).
