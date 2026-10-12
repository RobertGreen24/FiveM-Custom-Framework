fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_police'
author 'Nexus Framework'
description 'Police: MDT, warrants, arrests, jail, fines, evidence and radar.'
version '1.0.0'

dependency 'nx_core'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/main.lua',
    'server/mdt.lua',
}

client_scripts {
    'client/main.lua',
    'client/interactions.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
