fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_appearance'
author 'Nexus Framework'
description 'Character creator: face, hair, clothing, tattoos, clothing shops and outfits.'
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
    'client/creator.lua',
    'client/shops.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
