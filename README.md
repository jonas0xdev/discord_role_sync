# README placeholder
in der server.cfg eintragen:
setr discord_bot_token ""
setr discord_guild_id ""
setr discord_log_channel_id ""

Zum offline Sync müssen die exports richtig im Boss Menü eingetragen werden!
Für okokBoss Menü muss das in die sv_utils eingetagen werden
-- Discord RoleSync: Online & Offline Trigger
local function discordSyncOnline(src)
    CreateThread(function()
        Citizen.Wait(800) -- kleiner Puffer, falls Grade minimal später final gesetzt wird
        TriggerEvent('esx_discord_job_sync:resync', src)
    end)
end

local function discordSyncOffline(identifier, job, grade)
    CreateThread(function()
        Citizen.Wait(300) -- DB-Commit abwarten
        if GetResourceState('esx_discord_job_sync') == 'started'
           and exports['esx_discord_job_sync']
           and exports['esx_discord_job_sync'].SyncByIdentifier then
            exports['esx_discord_job_sync']:SyncByIdentifier(identifier, job, grade)
        else
            TriggerEvent('esx_discord_job_sync:offlineChanged', identifier, job, grade)
        end
    end)
end