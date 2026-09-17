<#
.SYNOPSIS
  Restore the legacy sidebar/session layout in OpenCode Desktop 1.18.31 (Windows).

.DESCRIPTION
  OpenCode Desktop retires the old sidebar layout after 2026-09-14
  (oldInterfaceSunset) and migrates users to the new tab layout.
  This script patches the renderer bundle inside app.asar to disable
  all five enforcement points, and sets newLayoutDesigns=false in
  the persisted settings. Provider/API settings are untouched.

  Tested on: OpenCode Desktop 1.18.31, Windows.
  Other versions: the script aborts unless every expected pattern is
  found or already patched, so it fails safe instead of corrupting.

.PARAMETER InstallDir
  Folder containing app.asar. Default:
  $env:LOCALAPPDATA\Programs\@opencode-aidesktop\resources

.PARAMETER UserDataDir
  OpenCode user-data folder. Default:
  $env:APPDATA\ai.opencode.desktop

.EXAMPLE
  # 1. Fully quit OpenCode (including the tray icon).
  # 2. Run:
  powershell -ExecutionPolicy Bypass -File .\restore-legacy-ui.ps1

.NOTES
  Unofficial community script. Not affiliated with OpenCode.
  Rollback: a timestamped backup (app.asar.pre-fullpatch-*) is created
  next to app.asar on every run; copy it back over app.asar to undo.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\@opencode-aidesktop\resources"),
  [string]$UserDataDir = (Join-Path $env:APPDATA "ai.opencode.desktop")
)

$ErrorActionPreference = "Stop"

$asar      = Join-Path $InstallDir "app.asar"
$tmp       = Join-Path $env:TEMP "opencode-legacy-full"
$checkDir  = Join-Path $env:TEMP "opencode-legacy-verify"
$newAsar   = Join-Path $env:TEMP "opencode-legacy-ui-patched-full.asar"
$defaultDat = Join-Path $UserDataDir "default.dat"

Write-Host "=== 1) Is OpenCode running? (quit it first, tray icon included) ==="
$procs = Get-Process -Name "OpenCode" -ErrorAction SilentlyContinue
if ($procs) {
  Write-Host "ERROR: OpenCode is still running. Quit it completely, then re-run this script." -ForegroundColor Red
  $procs | Format-Table Id, ProcessName, StartTime | Out-String | Write-Host
  exit 1
}
Write-Host "OK: OpenCode is not running."

Write-Host "`n=== 2) Back up current app.asar ==="
if (-not (Test-Path -LiteralPath $asar)) { throw "app.asar not found: $asar (override with -InstallDir)" }
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$curBackup = Join-Path $InstallDir "app.asar.pre-fullpatch-$ts"
Copy-Item -LiteralPath $asar -Destination $curBackup -Force
Write-Host "Current asar backed up to: $curBackup"

Write-Host "`n=== 3) Extract app.asar ==="
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
npx --yes @electron/asar extract $asar $tmp
$js = Get-ChildItem "$tmp\out\renderer\assets" -Filter "main-*.js" -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $js -or -not (Test-Path -LiteralPath $js)) { throw "Renderer bundle (main-*.js) not found after extract. exit=$LASTEXITCODE" }
Write-Host "Bundle: $js"

$pkgFile = Join-Path $tmp "package.json"
if (Test-Path -LiteralPath $pkgFile) {
  $ver = (Get-Content -LiteralPath $pkgFile -Raw | ConvertFrom-Json).version
  Write-Host "Detected app version: $ver"
  if ($ver -ne "1.18.31") {
    Write-Host "WARNING: this script was built for 1.18.31. Continuing, but it aborts if patterns do not match." -ForegroundColor Yellow
  }
}

Write-Host "`n=== 4) Patch (idempotent: safe to re-run) ==="
$c = [IO.File]::ReadAllText($js)
$origLen = $c.Length

# 4a) Sunset 2026-09-14 -> 2099, so oldInterfaceRetired() stays false.
$n1a = ([regex]::Matches($c, 'new Date\(2026\s*,\s*8\s*,\s*14\)')).Count
Write-Host "4a) sunset-2026 matches: $n1a"
$c = [regex]::Replace($c, 'new Date\(2026\s*,\s*8\s*,\s*14\)', 'new Date(2099,0,1)')

# 4b) Memo forcing new UI: if (layoutUpgrade()) return true -> if(false)return true
$n1b = ([regex]::Matches($c, 'if\s*\(\s*layoutUpgrade\(\s*\)\s*\)\s*return\s*true')).Count
Write-Host "4b) memo layoutUpgrade matches: $n1b"
$c = [regex]::Replace($c, 'if\s*\(\s*layoutUpgrade\(\s*\)\s*\)\s*return\s*true', 'if(false)return true')

# 4c) Migration effect writing newLayoutDesigns=true to disk on upgrade -> neutralized
$n1cAlready = ([regex]::Matches($c, 'if\(false&&layoutUpgrade\(\)&&')).Count
Write-Host "4c) migration effect (already patched: $n1cAlready)"
if ($n1cAlready -eq 0) {
  $c = [regex]::Replace($c, 'if\s*\(\s*layoutUpgrade\(\)\s*&&', 'if(false&&layoutUpgrade()&&')
}

# 4d) Retired effect writing newLayoutDesigns=true to disk once retired -> always return early
$n1d = ([regex]::Matches($c, 'if\s*\(\s*!ready\(\)\s*\|\|\s*!oldInterfaceRetired\(\)\s*\)\s*return')).Count
Write-Host "4d) retired-effect matches: $n1d"
$c = [regex]::Replace($c, 'if\s*\(\s*!ready\(\)\s*\|\|\s*!oldInterfaceRetired\(\)\s*\)\s*return', 'if(true)return')

# 4e) resolveNewLayoutDesigns(retired,...){ if(retired) return true } -> never force
$n1e = ([regex]::Matches($c, 'if\s*\(\s*retired\s*\)\s*return\s*true')).Count
Write-Host "4e) resolveNewLayoutDesigns matches: $n1e"
$c = [regex]::Replace($c, 'if\s*\(\s*retired\s*\)\s*return\s*true', 'if(false&&retired)return true')

[IO.File]::WriteAllText($js, $c, [Text.UTF8Encoding]::new($false))
Write-Host "Patched. length $origLen -> $($c.Length)"

Write-Host "`n=== 5) Verify final state (aborts on mismatch) ==="
$script:fail = $false
function Check($name, $pat, $min, $max) {
  $n = ([regex]::Matches($c, $pat)).Count
  $ok = ($n -ge $min -and $n -le $max)
  if ($ok) { Write-Host ("  [OK] {0}: {1}" -f $name, $n) }
  else { Write-Host ("  [FAIL] {0}: {1} (expected {2}..{3})" -f $name, $n, $min, $max) -ForegroundColor Red; $script:fail = $true }
}
Check "sunset moved to 2099" "new Date\(2099,0,1\)" 1 5
Check "no 2026 sunset left" "new Date\(2026\s*,\s*8\s*,\s*14\)" 0 0
Check "memo neutralized" "if\(false\)return true" 1 5
Check "no original memo forcing left" "if\s*\(\s*layoutUpgrade\(\s*\)\s*\)\s*return\s*true" 0 0
Check "migration neutralized" "if\(false&&layoutUpgrade\(\)&&" 1 5
Check "no unpatched migration left" "if\s+\(\s*layoutUpgrade\(\)\s*&&" 0 0
Check "retired effect neutralized" "if\(true\)return" 1 5
Check "resolve neutralized" "if\(false&&retired\)return true" 1 5
if ($script:fail) { throw "Verification failed, app.asar was NOT modified." }

Write-Host "`n=== 6) Repack asar ==="
Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
npx --yes @electron/asar pack $tmp $newAsar
if (-not (Test-Path -LiteralPath $newAsar)) { throw "Repack failed, no output asar." }
Write-Host ("New asar: {0} ({1} bytes)" -f $newAsar, (Get-Item $newAsar).Length)

Write-Host "`n=== 7) Verify repacked asar ==="
Remove-Item $checkDir -Recurse -Force -ErrorAction SilentlyContinue
npx --yes @electron/asar extract $newAsar $checkDir
$js2 = Get-ChildItem "$checkDir\out\renderer\assets" -Filter "main-*.js" -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $js2) { throw "Verification extract failed." }
$c2 = [IO.File]::ReadAllText($js2)
$v2099 = ([regex]::Matches($c2, 'new Date\(2099,0,1\)')).Count
$v2026 = ([regex]::Matches($c2, 'new Date\(2026\s*,\s*8\s*,\s*14\)')).Count
Write-Host "  repacked asar: 2099=$v2099 (must be 1+), 2026=$v2026 (must be 0)"
if ($v2099 -lt 1 -or $v2026 -ne 0) { throw "Repacked asar verification failed." }

Write-Host "`n=== 8) Replace app.asar ==="
Copy-Item -LiteralPath $newAsar -Destination $asar -Force
Write-Host ("Installed: {0} ({1} bytes)" -f $asar, (Get-Item $asar).Length)

Write-Host "`n=== 9) Settings: set newLayoutDesigns=false (nothing else touched) ==="
if (-not (Test-Path -LiteralPath $defaultDat)) { throw "default.dat not found: $defaultDat (override with -UserDataDir)" }
Copy-Item -LiteralPath $defaultDat -Destination "$defaultDat.pre-fullpatch-$ts" -Force
$outer = Get-Content -LiteralPath $defaultDat -Raw | ConvertFrom-Json
if (-not $outer.'settings.v3') { throw "settings.v3 not found in default.dat" }
$inner = $outer.'settings.v3' | ConvertFrom-Json
if (-not $inner.general) { $inner | Add-Member -NotePropertyName general -NotePropertyValue @{} }
$inner.general.newLayoutDesigns = $false
if ($inner.general.layoutTransitionEligible -isnot [bool]) { $inner.general.layoutTransitionEligible = $true }
$outer.'settings.v3' = ($inner | ConvertTo-Json -Depth 20 -Compress)
$outer | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $defaultDat -Encoding UTF8
Write-Host "default.dat updated (backup taken). newLayoutDesigns=false."

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "1) Start OpenCode - the legacy sidebar/session layout should be back."
Write-Host ("2) Rollback: copy '{0}' back over app.asar." -f $curBackup)
