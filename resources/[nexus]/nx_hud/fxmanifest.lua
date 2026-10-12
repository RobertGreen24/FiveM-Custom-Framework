fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_hud'
author 'Nexus Framework'
description 'Status rings, money, job, vehicle telemetry and voice indicator.'
version '1.0.0'

dependency 'nx_core'

shared_scripts {
    'config.lua',
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
