fx_version 'cerulean'
game 'gta5'
lua54 'yes'

ui_page 'web-side/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client-side/*'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server-side/*'
}

files {
    'web-side/*'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core'
}
