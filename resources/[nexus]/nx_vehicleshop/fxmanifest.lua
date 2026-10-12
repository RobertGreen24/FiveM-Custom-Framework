fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_vehicleshop'
author 'Nexus Framework'
description 'Dealerships with showroom preview, test drives and vehicle purchases.'
version '1.0.0'

dependency 'nx_core'
dependency 'nx_vehicles'

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
