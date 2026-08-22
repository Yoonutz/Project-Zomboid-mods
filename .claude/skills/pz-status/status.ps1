<#
    One pass over everything worth knowing about a TwoManCrew build.

    Written because the same five checks were being run by hand, one command at
    a time, several times an hour - and one of those hand-runs read a log from a
    previous session and produced a confidently wrong answer. The stale-log
    guard below exists because of that, not as decoration.

    Usage:
      status.ps1              report only, changes nothing
      status.ps1 -Sync        copy repo -> mods folder first (refuses while the game runs)
#>
param(
    [switch]$Sync,
    [string]$Repo = "D:\Dropbox\Apps\Project Zomboid\two-man-crew\Contents\mods\TwoManCrew",
    [string]$Mods = "$env:USERPROFILE\Zomboid\mods\TwoManCrew",
    [string]$Logs = "$env:USERPROFILE\Zomboid\Logs"
)

$ErrorActionPreference = "Stop"

function Get-ModVersion([string]$infoPath) {
    if (-not (Test-Path $infoPath)) { return "(missing)" }
    $line = Get-Content $infoPath | Select-String '^modversion='
    if (-not $line) { return "(none)" }
    return ($line -replace 'modversion=', '').Trim()
}

# ---------------------------------------------------------------- game state
$proc = Get-Process -Name "ProjectZomboid*" -ErrorAction SilentlyContinue
$running = [bool]$proc

Write-Output "== GAME =="
if ($running) {
    Write-Output "  running (pid $($proc[0].Id))"
} else {
    Write-Output "  not running"
}

# ---------------------------------------------------------------- sync
if ($Sync) {
    Write-Output ""
    Write-Output "== SYNC =="
    if ($running) {
        Write-Output "  REFUSED - the game is running. Deploying under a live session replaces the mod folder."
    } else {
        $item = Get-Item $Mods -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType) {
            Write-Output "  REFUSED - destination is a $($item.LinkType), not a real directory."
        } else {
            if (Test-Path $Mods) { Remove-Item $Mods -Recurse -Force -Confirm:$false }
            Copy-Item $Repo $Mods -Recurse -Force
            Write-Output "  copied"
        }
    }
}

# ---------------------------------------------------------------- install match
Write-Output ""
Write-Output "== INSTALL =="
Write-Output ("  repo      {0}" -f (Get-ModVersion "$Repo\mod.info"))
Write-Output ("  installed {0}" -f (Get-ModVersion "$Mods\mod.info"))

if (Test-Path $Mods) {
    # Hash every file. A matching version number proves nothing: a half-copied
    # tree carries the new mod.info and the old Lua, which looks identical from
    # the outside and behaves like the build you thought you replaced.
    $a = Get-ChildItem $Repo -Recurse -File | ForEach-Object {
        $_.FullName.Substring($Repo.Length + 1) + "|" + (Get-FileHash $_.FullName -Algorithm MD5).Hash
    }
    $b = Get-ChildItem $Mods -Recurse -File | ForEach-Object {
        $_.FullName.Substring($Mods.Length + 1) + "|" + (Get-FileHash $_.FullName -Algorithm MD5).Hash
    }
    $diff = Compare-Object $a $b
    if ($diff) {
        Write-Output "  MISMATCH - installed tree differs from the repo:"
        $diff | ForEach-Object {
            $side = if ($_.SideIndicator -eq '<=') { 'repo' } else { 'installed' }
            Write-Output ("    [{0}] {1}" -f $side, ($_.InputObject -split '\|')[0])
        }
    } else {
        Write-Output ("  identical - {0} files match" -f $a.Count)
    }
} else {
    Write-Output "  NOT INSTALLED"
}

# ---------------------------------------------------------------- the log
Write-Output ""
Write-Output "== LOG =="
$log = Get-ChildItem "$Logs\*DebugLog.txt" -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $log) {
    Write-Output "  no debug log found"
    return
}

$ageSec = [int]((Get-Date) - $log.LastWriteTime).TotalSeconds
Write-Output ("  {0}  (written {1}, {2}s ago)" -f $log.Name, $log.LastWriteTime.ToString("HH:mm:ss"), $ageSec)

# The trap this guard exists for: a log that stopped updating is from a session
# that has ENDED. Reading it and reporting "no errors" says nothing about the
# build now installed, and that mistake has already been made once here.
if ($running -and $ageSec -gt 60) {
    Write-Output "  WARNING: game is running but this log is stale. It may be from a previous session."
}
if (-not $running -and $ageSec -gt 120) {
    Write-Output "  NOTE: this log is from a finished session. Nothing here reflects the current install."
}

$text = Get-Content $log.FullName -Raw

# ---------------------------------------------------------------- mod errors
Write-Output ""
Write-Output "== MOD ERRORS =="
$sites = [regex]::Matches($text, 'TwoManCrew_[A-Za-z]+\.lua:\d+')
if ($sites.Count -eq 0) {
    Write-Output "  none"
} else {
    $sites | Group-Object { $_.Value } | Sort-Object Count -Descending |
        Select-Object -First 8 | ForEach-Object {
            Write-Output ("  x{0}  {1}" -f $_.Count, $_.Name)
        }
    [regex]::Matches($text, '(?m)^.*(not defined for operands|attempt to (index|call|perform|compare)).*$') |
        ForEach-Object { $_.Value.Trim() } | Select-Object -Unique -First 5 |
        ForEach-Object { Write-Output ("    {0}" -f $_) }
}

# ---------------------------------------------------------------- timings
Write-Output ""
Write-Output "== TIMINGS =="
$perf = [regex]::Matches($text, 'TMC_PERF (\w+) ms=(\d+)')
if ($perf.Count -eq 0) {
    Write-Output "  none recorded (no claim yet, or instrumentation removed)"
} else {
    $perf | Group-Object { $_.Groups[1].Value } | ForEach-Object {
        $vals = $_.Group | ForEach-Object { [int]$_.Groups[2].Value }
        $worst = ($vals | Measure-Object -Maximum).Maximum
        $verdict = if ($worst -ge 16) { "  <-- over one frame at 60fps" } else { "" }
        Write-Output ("  {0,-16} worst {1} ms   ({2} samples){3}" -f $_.Name, $worst, $vals.Count, $verdict)
    }
}

Write-Output ""
Write-Output "Nothing above proves the mod works on screen. Only a real look does."
