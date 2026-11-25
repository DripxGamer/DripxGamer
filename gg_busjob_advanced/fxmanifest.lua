fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gg_busjob_advanced'
author 'Custom'
description 'Bus job for QBCore and Qbox: terminal UI (workers, routes, history), visible passengers, levels, fines, exit timer, driver ranking and a payout path that can never drop your money'
version '7.2.0'

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
