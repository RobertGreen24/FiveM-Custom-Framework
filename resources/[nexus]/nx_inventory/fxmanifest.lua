fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_inventory'
author 'Nexus Framework'
description 'Weight and slot based inventory: grid UI, hotbar, weapons, drops, trunks, gloveboxes and stashes.'
version '1.0.0'

dependency 'nx_core'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
}

server_scripts {
    'server/containers.lua',
    'server/main.lua',
    'server/exports.lua',
}

client_scripts {
    'client/weapons.lua',
    'client/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
