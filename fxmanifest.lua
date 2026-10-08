fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
lua54 'yes'
author 'BCC Team'
version '2.0.0'

shared_scripts {
    'config.lua',
    'locale.lua',
    'languages/*.lua'
}

server_scripts {
    '@feather-mysql/lib/DB.lua',
    'server/feather/init.lua',
    'server/feather/authority.lua',
    'server/feather/access.lua',
    'server/dbUpdater.lua',
    'server/API.lua',
    'server/server.lua'
}

client_scripts {
    'client/feather/init.lua',
    'client/feather/menu_v2.lua',
    'client/client_init.lua',
    'client/functions.lua',
    'client/client.lua',
    'client/doorhashes.lua',
    'client/MenuSetup.lua'
}

-- bcc-minigames (or rsd_lockpick) is optional: lockpicking is offered only while it runs.
dependencies {
    'feather-mysql',
    'feather-core',
    'feather-character',
    'feather-notify',
    'feather-toolkit',
    'feather-menu-v2',
    'feather-inventory',
    'feather-jobs',
    'feather-authority'
}
