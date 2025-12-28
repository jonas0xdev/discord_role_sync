shared_script '@polgebaude/ai_module_fg-obfuscated.lua'
fx_version 'cerulean'
game 'gta5'
name 'esx_discord_job_sync'
author 'Jonas Ziegler'
description 'Sync ESX job + grade to Discord roles with audit logging to a channel'
version '1.2.0'
server_scripts { 'config.lua', 'server.lua' }
server_exports {
  'SyncByIdentifier',
  'SyncByDiscord',
}

