fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gg_busjob_advanced'
author 'Custom'
description 'Bus job for Qbox, QBCore and ESX in 7 languages: terminal UI (workers, routes, history), passengers that board through the door, levels, fines, garage hand-in and a payout path that can never drop your money'
version '8.0.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/style.css',
    'web/js/app.js',
    'web/fonts/*.woff2',
    'web/img/*.webp',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/locales.lua',
    'config/routes.lua',
    'shared.lua',
}

client_scripts {
    'client/passengers.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
