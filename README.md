# OpenCode Desktop: Restore Legacy Sidebar UI (Windows, 1.18.31 to 1.18.35)

Hate the new tab layout? This script brings back the old sidebar and session list
in **OpenCode Desktop** on Windows with a single command.

## One-line usage

> **Close OpenCode completely first** (including the tray icon), then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore-legacy-ui.ps1
```

Or directly from GitHub:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nopeion/opencode-legacy-ui/main/restore-legacy-ui.ps1 -OutFile $env:TEMP\restore-legacy-ui.ps1; & $env:TEMP\restore-legacy-ui.ps1"
```

Then start OpenCode. The legacy sidebar and session layout should be back.

Custom install locations:

```powershell
.\restore-legacy-ui.ps1 -InstallDir "D:\Custom\resources" -UserDataDir "D:\Custom\user-data"
```

## What it does

OpenCode retires the old UI after `2026-09-14` (`oldInterfaceSunset`) and
forces the new layout in several other places. The script disables all five
enforcement points in the renderer bundle (`out/renderer/assets/main-*.js`
inside `app.asar`):

| # | Code | Patch |
|---|------|-------|
| 1 | `const oldInterfaceSunset = new Date(2026, 8, 14)` | Becomes `new Date(2099,0,1)`, so `oldInterfaceRetired()` stays `false` |
| 2 | `if (layoutUpgrade()) return true` (memo) | Becomes `if(false)return true` |
| 3 | Migration effect that writes `newLayoutDesigns=true` to disk on upgrade past `1.17.19` | Neutralized with `if(false&&layoutUpgrade()&& ...)` |
| 4 | Retired effect that writes `newLayoutDesigns=true` once retired | Neutralized with `if(true)return` |
| 5 | `resolveNewLayoutDesigns(retired,...){ if(retired) return true }` | Becomes `if(false&&retired)return true` |

It also sets `newLayoutDesigns=false` in `default.dat` (`settings.v3`, then
`general`). Provider and API keys and all other settings are left untouched.

The script is **idempotent** (safe to re-run) and **fails safe**: it verifies
every final state with regex counts and aborts without touching `app.asar`
if anything is unexpected (for example a new app version with different code).

Note: every OpenCode update reinstalls a fresh `app.asar`, which wipes the
patch. Just close OpenCode and run the script again after each update.

## Requirements

- Windows
- OpenCode Desktop **1.18.31 to 1.18.35** (other versions abort unless every pattern matches)
- Node.js (`npx @electron/asar` is used for extract and pack)
- OpenCode fully quit before running (the script refuses to run otherwise,
  because patching while Electron holds the file leaves the old code in memory)

## Rollback

Every run creates timestamped backups:

- `<resources>\app.asar.pre-fullpatch-<timestamp>`: copy back over `app.asar`
- `%APPDATA%\ai.opencode.desktop\default.dat.pre-fullpatch-<timestamp>`

## Disclaimer

Unofficial community script, not affiliated with OpenCode. Patching `app.asar`
can break on future updates (re-run after each update). Use at your own risk.
