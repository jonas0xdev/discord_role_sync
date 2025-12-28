local ESX

CreateThread(function()
    if GetResourceState('es_extended') == 'started' then
        if exports and exports['es_extended'] and exports['es_extended'].getSharedObject then
            ESX = exports['es_extended']:getSharedObject()
        end
        if not ESX then
            TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        end
    end
end)

-- ========== Utils ==========
local function dprint(msg) if Config.Debug then print(('^5[discord-job-sync]^7 %s'):format(msg)) end end
local function lowerOrNil(s) if type(s) == 'string' then return s:lower() end return s end

local function getDiscordId(src)
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'discord')
    if id and id ~= '' then return id:sub(1,8) == 'discord:' and id:sub(9) or id end
    for _, v in ipairs(GetPlayerIdentifiers(src)) do
        if v:find('discord:') == 1 then return v:sub(9) end
    end
    return nil
end

-- ========== Discord HTTP ==========
local function discordRequest(method, endpoint, body)
    if (Config.BotToken or '') == '' or (Config.GuildId or '') == '' then
        dprint('FEHLER: BotToken oder GuildId leer (server.cfg prüfen).')
        return { status = 400, data = 'missing config', headers = {} }
    end
    local url = ('https://discord.com/api/v10%s'):format(endpoint)
    local p = promise.new()
    PerformHttpRequest(url, function(status, data, headers)
        p:resolve({ status = status, data = data, headers = headers or {} })
    end, method, body and json.encode(body) or '', {
        ['Authorization'] = 'Bot ' .. Config.BotToken,
        ['Content-Type']  = 'application/json'
    })
    return Citizen.Await(p)
end

local function computeBackoff(res, defaultMs)
    local ms = defaultMs or 1200
    local h = res.headers or {}
    local ra = h['retry-after'] or h['Retry-After']
    local rla = h['x-ratelimit-reset-after'] or h['X-RateLimit-Reset-After']
    if rla then
        local sec = tonumber(rla) or 0; if sec > 0 then ms = math.floor(sec * 1000) + 200 end
    elseif ra then
        local sec = tonumber(ra) or 0; if sec > 0 then ms = math.floor(sec * 1000) + 200 end
    end
    return ms
end

local function postLog(content)
    if not Config.LogToDiscord then return end
    if not Config.LogChannelId or Config.LogChannelId == '' then return end
    local res = discordRequest('POST', ('/channels/%s/messages'):format(Config.LogChannelId), { content = content })
    dprint(('LOG %s: %s'):format(res.status or 'nil', content))
    return res
end

local function getMemberRoles(did)
    local res = discordRequest('GET', ('/guilds/%s/members/%s'):format(Config.GuildId, did))
    if res.status == 200 and res.data then
        local ok, data = pcall(json.decode, res.data)
        if ok and data and data.roles then return data.roles end
    end
    return nil
end

-- ========== Grade-only Logging (mit Rollen-Ping) ==========
local function shouldLog(kind) -- 'grade'|'job'|'info'
    if Config.LogOnlyGradeChanges then return kind == 'grade' end
    return true
end

local function logAdd(did, rid, ctx, kind)
    if shouldLog(kind or 'grade') then
        postLog(('✅ Rolle <@&%s> hinzugefügt für <@%s> — %s'):format(rid, did, ctx or ''))
    end
end
local function logRem(did, rid, ctx, kind)
    if shouldLog(kind or 'grade') then
        postLog(('🗑️ Rolle <@&%s> entfernt bei <@%s>%s'):format(rid, did, ctx and (' — ' .. ctx) or ''))
    end
end

-- ========== Role add/remove mit 429-Backoff ==========
local function addRole(did, rid, ctx, isGrade, tried)
    if not rid or rid == '' then return end
    local res = discordRequest('PUT', ('/guilds/%s/members/%s/roles/%s'):format(Config.GuildId, did, rid))
    if res.status == 429 and not tried then
        local waitMs = computeBackoff(res, 1400); dprint(('429 ADD %s wait %dms'):format(rid, waitMs))
        Citizen.Wait(waitMs); return addRole(did, rid, ctx, isGrade, true)
    end
    if res.status and res.status >= 200 and res.status < 300 then
        logAdd(did, rid, ctx, isGrade and 'grade' or 'job')
    else
        if not Config.LogOnlyGradeChanges then postLog(('❌ Add %s bei <@%s> (HTTP %s)%s'):format(rid, did, tostring(res.status), ctx and (' — ' .. ctx) or '')) end
    end
    return res
end

local function removeRole(did, rid, ctx, isGrade, tried)
    if not rid or rid == '' then return end
    local res = discordRequest('DELETE', ('/guilds/%s/members/%s/roles/%s'):format(Config.GuildId, did, rid))
    if res.status == 429 and not tried then
        local waitMs = computeBackoff(res, 1400); dprint(('429 REM %s wait %dms'):format(rid, waitMs))
        Citizen.Wait(waitMs); return removeRole(did, rid, ctx, isGrade, true)
    end
    if res.status and res.status >= 200 and res.status < 300 then
        logRem(did, rid, ctx, isGrade and 'grade' or 'job')
    else
        if not Config.LogOnlyGradeChanges then postLog(('❌ Rem %s bei <@%s> (HTTP %s)%s'):format(rid, did, tostring(res.status), ctx and (' — ' .. ctx) or '')) end
    end
    return res
end

-- ========== Mapping / Checks ==========
local function isProtected(rid)
    for _, r in ipairs(Config.ProtectedRoles or {}) do if r == rid then return true end end
    return false
end

local function inNoSync(jobName)
    local key = lowerOrNil(jobName)
    for _, j in ipairs(Config.NoSyncJobs or {}) do if lowerOrNil(j) == key then return true end end
    return false
end

local function resolveGradeRole(jobName, grade, grade_name)
    local jobKey = lowerOrNil(jobName)
    local jm = Config.GradeRoleMap and Config.GradeRoleMap[jobKey]
    if not jm then return nil end
    local gnk = lowerOrNil(grade_name)
    if gnk and jm[gnk] then return jm[gnk] end
    if grade ~= nil and jm[grade] then return jm[grade] end
    local gs = tostring(grade); if jm[gs] then return jm[gs] end
    return nil
end

local function getJobRoleId(jobName)
    local jm = Config.JobRoleMap or {}
    return jm[lowerOrNil(jobName)]
end

-- Debounce identische Signale
local lastSig = {}
local function shouldSkip(src, job, grade)
    local now = GetGameTimer()
    local key = ('%s:%s:%s'):format(src, lowerOrNil(job) or 'nil', tostring(grade))
    local rec = lastSig[src]
    if rec and rec.key == key and (now - rec.ts) < 2000 then return true end
    lastSig[src] = { key = key, ts = now }; return false
end

-- Nur entfernen, was der Spieler **wirklich hat**; Job-Rollen global, Grade-Rollen über ALLE Jobs
local function cleanupRolesMinimal(did, keepJobRid, keepGradeRid, memberRoles)
    if not memberRoles then return end
    local has = {}; for _, r in ipairs(memberRoles) do has[r] = true end
    if Config.EnforceSingleJobRole and Config.JobRoleMap then
        for _, rid in pairs(Config.JobRoleMap) do
            if rid ~= keepJobRid and not isProtected(rid) and has[rid] then removeRole(did, rid, 'Aufräumen (Job)', false); Citizen.Wait(250) end
        end
    end
    if Config.EnforceSingleGradeRole and Config.GradeRoleMap then
        for _, grades in pairs(Config.GradeRoleMap) do
            for _, rid in pairs(grades) do
                if rid ~= keepGradeRid and not isProtected(rid) and has[rid] then removeRole(did, rid, 'Aufräumen (Grade)', true); Citizen.Wait(250) end
            end
        end
    end
end

local function clearAllMappedRoles(did, memberRoles)
    if not memberRoles then return end
    local has = {}; for _, r in ipairs(memberRoles) do has[r] = true end
    if Config.JobRoleMap then
        for _, rid in pairs(Config.JobRoleMap) do if not isProtected(rid) and has[rid] then removeRole(did, rid, 'NoSync: Clear (Job)', false); Citizen.Wait(250) end end
    end
    if Config.GradeRoleMap then
        for _, grades in pairs(Config.GradeRoleMap) do
            for _, rid in pairs(grades) do if not isProtected(rid) and has[rid] then removeRole(did, rid, 'NoSync: Clear (Grade)', true); Citizen.Wait(250) end end
        end
    end
end

-- ========== Core Sync (online) ==========
local function syncDiscordRoles(src, jobName, grade, grade_name, is_manual)
    if shouldSkip(src, jobName, grade) then dprint(('Skip dup #%s %s/%s'):format(src, tostring(jobName), tostring(grade))); return end
    local did = getDiscordId(src)
    if not did then dprint(('Spieler %s ohne Discord-ID.')) return end

    local respect_manual = Config.NoSyncJobs_RespectManualSync ~= false
    local bypass = (is_manual and not respect_manual)
    if inNoSync(jobName) and not bypass then
        if not Config.LogOnlyGradeChanges then postLog(('⏸️ NoSync: <@%s> — job=%s | grade=%s/%s'):format(did, tostring(jobName), tostring(grade), tostring(grade_name))) end
        if Config.NoSyncJobs_ClearRoles then local roles = getMemberRoles(did); if roles then clearAllMappedRoles(did, roles) end end
        return
    end

    local jobRid   = Config.AssignJobRole   and getJobRoleId(jobName) or nil
    local gradeRid = Config.AssignGradeRole and resolveGradeRole(jobName, grade, grade_name) or nil
    local memberRoles = getMemberRoles(did)

    cleanupRolesMinimal(did, jobRid, gradeRid, memberRoles)

    local has = {}; if memberRoles then for _, r in ipairs(memberRoles) do has[r] = true end end
    if jobRid and not has[jobRid]   then addRole(did, jobRid,   'Setze Job-Rolle', false); Citizen.Wait(300) end
    if gradeRid and not has[gradeRid] then addRole(did, gradeRid, ('Setze Grade-Rolle — job=%s | grade=%s/%s'):format(tostring(jobName), tostring(grade), tostring(grade_name)), true) end
end

local function extractJobParts(x)
    if not x then return nil,nil,nil end
    local name  = x.name       or (x.job and x.job.name)
    local grade = x.grade      or (x.job and x.job.grade)
    local gname = x.grade_name or (x.job and x.job.grade_name) or (x.grade and x.grade.name) or x.grade_label
    return name, grade, gname
end

-- ========== Events (online) ==========
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer, isNew)
    local jobName, grade, grade_name = extractJobParts(xPlayer and (xPlayer.job or xPlayer))
    if jobName then
        syncDiscordRoles(playerId, jobName, grade, grade_name, false)
        CreateThread(function()
            Citizen.Wait(800)
            local xp = ESX and ESX.GetPlayerFromId(playerId); if not xp then return end
            local j = xp.job or (xp.getJob and xp.getJob()); if not j then return end
            syncDiscordRoles(playerId, j.name, j.grade, (j.grade_name or (j.grade and j.grade.name) or j.grade_label), false)
        end)
    end
end)

AddEventHandler('esx:setJob', function(playerId, newJob, lastJob)
    local name, grade, gname
    if type(newJob) == 'table' then
        name  = newJob.name
        grade = newJob.grade
        gname = newJob.grade_name or (newJob.grade and newJob.grade.name) or newJob.grade_label
    else
        name = newJob
    end
    syncDiscordRoles(playerId, name, grade, gname, false)
    CreateThread(function()
        Citizen.Wait(800)
        local xp = ESX and ESX.GetPlayerFromId(playerId); if not xp then return end
        local j = xp.job or (xp.getJob and xp.getJob()); if not j then return end
        syncDiscordRoles(playerId, j.name, j.grade, (j.grade_name or (j.grade and j.grade.name) or j.grade_label), false)
    end)
end)

RegisterNetEvent('esx_discord_job_sync:resync')
AddEventHandler('esx_discord_job_sync:resync', function(targetId)
    local pid = targetId or source
    local xPlayer = ESX and ESX.GetPlayerFromId(pid); if not xPlayer then return end
    local j = xPlayer.job or (xPlayer.getJob and xPlayer.getJob()); if not j then return end
    syncDiscordRoles(pid, j.name, j.grade, (j.grade_name or (j.grade and j.grade.name) or j.grade_label), true)
end)

RegisterCommand('syncjobrole', function(src, args)
    local target = src
    if IsPlayerAceAllowed(src, 'command.syncjobrole') and args[1] then target = tonumber(args[1]) or src end
    local xPlayer = ESX and ESX.GetPlayerFromId(target); if not xPlayer then return end
    local j = xPlayer.job or (xPlayer.getJob and xPlayer.getJob()); if not j then return end
    syncDiscordRoles(target, j.name, j.grade, (j.grade_name or (j.grade and j.grade.name) or j.grade_label), true)
end, false)

-- ========== Offline-Support (Link-Tabelle + Exports) ==========
-- DB-Adapter (oxmysql oder mysql-async)
local function usingOx()  return GetResourceState('oxmysql') == 'started' end
local function usingMyA() return GetResourceState('mysql-async') == 'started' end

local function dbExec(sql, params)
    local p = promise.new()
    if usingOx() then
        exports.oxmysql:execute(sql, params or {}, function(affected) p:resolve(affected) end)
    elseif usingMyA() then
        MySQL.Async.execute(sql, params or {}, function(affected) p:resolve(affected) end)
    else
        print('^1[discord-job-sync] Keine DB-Resource (oxmysql/mysql-async)^0'); p:resolve(false)
    end
    return Citizen.Await(p)
end
local function dbFetchAll(sql, params)
    local p = promise.new()
    if usingOx() then
        exports.oxmysql:execute(sql, params or {}, function(rows) p:resolve(rows or {}) end)
    elseif usingMyA() then
        MySQL.Async.fetchAll(sql, params or {}, function(rows) p:resolve(rows or {}) end)
    else
        print('^1[discord-job-sync] Keine DB-Resource (oxmysql/mysql-async)^0'); p:resolve({})
    end
    return Citizen.Await(p)
end
local function dbScalar(sql, params)
    local p = promise.new()
    if usingOx() then
        if exports.oxmysql.scalar then
            exports.oxmysql:scalar(sql, params or {}, function(v) p:resolve(v) end)
        else
            exports.oxmysql:execute(sql, params or {}, function(rows)
                local v; if rows and rows[1] then local k = next(rows[1]); if k then v = rows[1][k] end end
                p:resolve(v)
            end)
        end
    elseif usingMyA() then
        MySQL.Async.fetchScalar(sql, params or {}, function(v) p:resolve(v) end)
    else
        print('^1[discord-job-sync] Keine DB-Resource (oxmysql/mysql-async)^0'); p:resolve(nil)
    end
    return Citizen.Await(p)
end

-- Tabelle anlegen
CreateThread(function()
    dbExec([[CREATE TABLE IF NOT EXISTS `esx_discord_links` (
        `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
        `discord`    VARCHAR(32) NOT NULL UNIQUE
    )]])
end)

-- Link beim Login speichern/updaten
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer, isNew)
    local did
    do
        local raw = GetPlayerIdentifierByType and GetPlayerIdentifierByType(playerId, 'discord')
        if raw and raw ~= '' then did = raw:sub(1,8) == 'discord:' and raw:sub(9) or raw
        else for _, v in ipairs(GetPlayerIdentifiers(playerId)) do if v:find('discord:') == 1 then did = v:sub(9) break end end end
    end
    local identifier = (xPlayer and (xPlayer.identifier or (xPlayer.getIdentifier and xPlayer.getIdentifier()))) or nil
    if did and identifier then
        dbExec('INSERT INTO esx_discord_links (identifier, discord) VALUES (?, ?) ON DUPLICATE KEY UPDATE discord = VALUES(discord)', {identifier, did})
    end
end)

local function fetchJobFromDBByDiscord(did)
    local rows = dbFetchAll([[
        SELECT u.job, u.job_grade
        FROM esx_discord_links l
        JOIN users u ON u.identifier = l.identifier
        WHERE l.discord = ?
        LIMIT 1
    ]], { did })
    local r = rows[1]; if r then return r.job, tonumber(r.job_grade) end
    return nil, nil
end

local function fetchJobFromDBByIdentifier(identifier)
    local rows = dbFetchAll('SELECT job, job_grade FROM users WHERE identifier = ? LIMIT 1', { identifier })
    local r = rows[1]; if r then return r.job, tonumber(r.job_grade) end
    return nil, nil
end

local function syncDiscordRolesByDiscordId(did, jobName, grade, grade_name, is_manual)
    if not did or did == '' then return end
    -- NoSync / Bypass
    local respect_manual = Config.NoSyncJobs_RespectManualSync ~= false
    local bypass = (is_manual and not respect_manual)
    if jobName and inNoSync(jobName) and not bypass then
        if Config.NoSyncJobs_ClearRoles then local roles = getMemberRoles(did); if roles then clearAllMappedRoles(did, roles) end end
        return
    end

    if not jobName then jobName, grade = fetchJobFromDBByDiscord(did) end
    if not jobName then return end

    local jobRid   = Config.AssignJobRole   and getJobRoleId(jobName) or nil
    local gradeRid = Config.AssignGradeRole and resolveGradeRole(jobName, grade, grade_name) or nil
    local memberRoles = getMemberRoles(did)

    cleanupRolesMinimal(did, jobRid, gradeRid, memberRoles)

    local has = {}; if memberRoles then for _, r in ipairs(memberRoles) do has[r] = true end end
    if jobRid and not has[jobRid]     then addRole(did, jobRid,   '(offline) Setze Job-Rolle', false); Citizen.Wait(300) end
    if gradeRid and not has[gradeRid] then addRole(did, gradeRid, ('(offline) Setze Grade-Rolle — job=%s | grade=%s'):format(tostring(jobName), tostring(grade)), true) end
end

-- Exports für andere Ressourcen (okokBossMenu etc.)
function SyncByDiscord(did, jobName, grade, grade_name)
    syncDiscordRolesByDiscordId(did, jobName, grade, grade_name, true); return true
end
function SyncByIdentifier(identifier, jobName, grade, grade_name)
    local did = dbScalar('SELECT discord FROM esx_discord_links WHERE identifier = ? LIMIT 1', { identifier })
    if not did then return false end
    if not jobName then jobName, grade = fetchJobFromDBByIdentifier(identifier) end
    syncDiscordRolesByDiscordId(did, jobName, grade, grade_name, true); return true
end

-- Optionales Event (falls lieber Events statt Exports)
RegisterNetEvent('esx_discord_job_sync:offlineChanged', function(identifier, jobName, grade, grade_name)
    SyncByIdentifier(identifier, jobName, grade, grade_name)
end)

-- In server.cfg (Beispiel):
-- add_ace group.admin command.syncjobrole allow
