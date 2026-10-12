fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_multicharacter'
author 'Nexus Framework'
description 'Character select and creation screen for the Nexus framework.'
version '1.0.0'

dependency 'nx_core'

client_scripts {
    'client/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
