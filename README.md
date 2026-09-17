# OpenCode Desktop — Restore Legacy Sidebar UI (1.18.31, Windows)

Hate the new tab layout? This script brings back the old sidebar + session-list
layout in **OpenCode Desktop 1.18.31** on Windows with a single command.

## One-line usage

> **Close OpenCode completely first** (including the tray icon), then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore-legacy-ui.ps1
```

Or directly from GitHub:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nopeion/opencode-legacy-ui/main/restore-legacy-ui.ps1 -OutFile $env:TEMP\restore-legacy-ui.ps1; & $env:TEMP\restore-legacy-ui.ps1"
```

Then start OpenCode. The legacy sidebar/session layout should be back.

Custom install locations:

```powershell
.\restore-legacy-ui.ps1 -InstallDir "D:\Custom\resources" -UserDataDir "D:\Custom\user-data"
```

## What it does

OpenCode retires the old UI after `2026-09-14` (`oldInterfaceSunset`) and
otherwise forces the new layout in several places. The script disables all
five enforcement points in the renderer bundle (`out/renderer/assets/main-*.js`
inside `app.asar`):

| # | Code | Patch |
|---|------|-------|
| 1 | `const oldInterfaceSunset = new Date(2026, 8, 14)` | → `new Date(2099,0,1)` so `oldInterfaceRetired()` stays `false` |
| 2 | `if (layoutUpgrade()) return true` (memo) | → `if(false)return true` |
| 3 | Migration effect writing `newLayoutDesigns=true` to disk on upgrade past `1.17.19` | → `if(false&&layoutUpgrade()&& …)` (neutralized) |
| 4 | Retired effect writing `newLayoutDesigns=true` once retired | → `if(true)return` (neutralized) |
| 5 | `resolveNewLayoutDesigns(retired,…){ if(retired) return true }` | → `if(false&&retired)return true` |

Plus it sets `newLayoutDesigns=false` in `default.dat` (`settings.v3` →
`general`). Provider/API keys and all other settings are left untouched.

The script is **idempotent** (safe to re-run) and **fails safe**: it verifies
every final state with regex counts and aborts without touching `app.asar`
if anything is unexpected (e.g. a different app version).

## Requirements

- Windows
- OpenCode Desktop **1.18.31** (other versions abort unless patterns match)
- Node.js (`npx @electron/asar` is used for extract/pack)
- OpenCode fully quit before running (the script refuses to run otherwise —
  patching while Electron holds the file gives you the old UI in memory anyway)

## Rollback

Every run creates timestamped backups:

- `<resources>\app.asar.pre-fullpatch-<timestamp>` — copy back over `app.asar`
- `%APPDATA%\ai.opencode.desktop\default.dat.pre-fullpatch-<timestamp>`

## Disclaimer

Unofficial community script, not affiliated with OpenCode. Patching `app.asar`
may break on future updates (re-run after each update, or restore the backup
first). Use at your own risk.
