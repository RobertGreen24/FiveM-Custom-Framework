fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_spawn'
author 'Nexus Framework'
description 'Spawn location selector. Takes over the spawn decision when a character loads.'
version '1.0.0'

dependency 'nx_core'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
