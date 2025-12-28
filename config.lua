Config = {}

-- Empfohlen: in server.cfg setzen (siehe README)
Config.GuildId       = GetConvar('discord_guild_id', '')
Config.BotToken      = GetConvar('discord_bot_token', '')

-- Logging in Discord-Channel (jede Änderung wird gepostet)
Config.LogToDiscord  = true
Config.LogChannelId  = GetConvar('discord_log_channel_id', '') -- Channel-ID für Logs

-- Jobs, bei denen NICHT synchronisiert wird
Config.NoSyncJobs = {'off_feuerwehr' }
Config.NoSyncJobs_ClearRoles = false
Config.NoSyncJobs_RespectManualSync = false

-- Nur Grade-Änderungen loggen (mit Rollen-Ping); NoSync-Hinweise werden unterdrückt
Config.LogOnlyGradeChanges = true


Config.JobRoleMap = {
    feuerwehr = '1442265281857847303',
}

Config.GradeRoleMap = {
    feuerwehr = {
        ['0'] = '1442265281815642247', -- Brandmeisteranwärter/in
        ['1'] = '1442265281815642248', -- Brandmeister/in
        ['2'] = '1442265281815642249', -- Oberbrandmesiter/in
        ['3'] = '1442265281815642250', -- Hauptbrandmeister/in
        ['4'] = '1442265281815642251', -- Hauptbrandmeister/in m. Zulage
        ['5'] = '1442265281815642252', -- Brandoberinspektoranwärter/in
        ['6'] = '1442265281857847296', -- Brandoberinspektor/in
        ['9'] = '1442265281857847297', -- Brandamtmann/frau
        ['10'] = '1442265281857847298', -- Brandrefendar/in
        ['11'] = '1442265281857847299', -- Brandrat/in
        ['12'] = '1442265281857847300', -- Oberbrandrat/in
        ['13'] = '1442265281857847301', -- Branddirektor/in
        ['14'] = '1442265281857847302', -- Leitende/r Branddirektor/in

    },       

}

-- Einstellungen
Config.AssignJobRole          = true    -- Job-Basisrolle vergeben
Config.AssignGradeRole        = true    -- Grade-Rolle vergeben
Config.EnforceSingleJobRole   = true    -- Nur eine Job-Rolle behalten
Config.EnforceSingleGradeRole = true    -- Nur eine Grade-Rolle behalten (aufräumen über alle Grade-Rollen)

-- Rollen, die nie entfernt werden sollen
Config.ProtectedRoles = {
    '1442265282008711209',
    '1442265281958252622'
}

-- Debug-Logs in Server-Konsole
Config.Debug = true
