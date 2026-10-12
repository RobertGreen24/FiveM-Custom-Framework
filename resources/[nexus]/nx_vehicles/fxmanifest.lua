fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_vehicles'
author 'Nexus Framework'
description 'Vehicle ownership, keys, locks, fuel, damage and persistence.'
version '1.0.0'

dependency 'nx_core'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
