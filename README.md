# ESX Discord Job Sync

Synchronisiert **ESX Jobs & Ränge** automatisch mit **Discord-Rollen** –  
sowohl für **Online-Spieler** als auch für **Offline-Änderungen** über das Boss-Menü.

---

## ✨ Features

- 🔄 Automatische Job- & Rang-Synchronisation
- 🟢 Online Sync (live im Spiel)
- 🔴 Offline Sync (Boss-Menü / Datenbank)
- 🤖 Discord Bot Integration
- 📜 Logging in Discord
- ⚡ Unterstützung für okokBossMenu

---

## 📦 Voraussetzungen

- **ESX Framework**
- **okokBossMenu**
- **oxmysql**
- **Discord Bot** mit folgenden Rechten:
  - `Manage Roles`
  - `View Channels`
  - `Send Messages`

---

## ⚙️ Installation

1. Lege das Script in deinen `resources` Ordner
2. Stelle sicher, dass das Resource gestartet wird:
   ```cfg
   ensure esx_discord_job_sync
   ```

---

## 🔧 Konfiguration

Trage folgende Variablen in deine `server.cfg` ein:

```cfg
setr discord_bot_token ""
setr discord_guild_id ""
setr discord_log_channel_id ""
```

### Erklärung

| Variable | Beschreibung |
|--------|--------------|
| `discord_bot_token` | Bot Token aus dem Discord Developer Portal |
| `discord_guild_id` | ID deines Discord Servers |
| `discord_log_channel_id` | Channel-ID für Log-Nachrichten |

---

## 🔄 Offline Sync (Boss-Menü Integration)

⚠️ **Wichtig:**  
Damit **Offline-Jobänderungen** korrekt mit Discord synchronisiert werden, müssen die Exports im Boss-Menü eingebunden sein.

### okokBossMenu – `sv_utils`

```lua
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
```

---

## 🧠 Funktionsweise

### 🟢 Online Synchronisation
- Wird ausgelöst, wenn ein Spieler **online** befördert oder degradiert wird
- Discord-Rollen werden sofort aktualisiert

### 🔴 Offline Synchronisation
- Greift bei Änderungen über das **Boss-Menü**
- Wartet auf den Datenbank-Commit
- Synchronisiert anhand der **Identifier**

---

## 📝 Hinweise

- Das Resource **`esx_discord_job_sync`** muss gestartet sein
- Discord-Rollen müssen korrekt den Jobs & Rängen zugewiesen sein
- Logs erscheinen im konfigurierten Discord-Channel

---

## 🛠️ Troubleshooting

| Problem | Lösung |
|------|-------|
| Rollen werden nicht gesetzt | Bot-Rechte prüfen |
| Offline Sync funktioniert nicht | Boss-Menü Exports prüfen |
| Keine Logs in Discord | `discord_log_channel_id` kontrollieren |
