fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_jobs'
author 'Nexus Framework'
description 'Job centres, duty points, paychecks, job grades and job-owned stashes.'
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

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}
