fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_shops'
author 'Nexus Framework'
description 'Convenience stores, liquor stores, ammunations, pharmacies and hardware shops.'
version '1.0.0'

dependency 'nx_core'
dependency 'nx_inventory'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
