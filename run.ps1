#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the BurnBridgers Godot project.

.PARAMETER Mode
    editor  - Open the Godot editor with this project (default)
    offline - Open the editor and immediately run in offline test mode via --scene arg

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Mode offline
#>
param(
    [ValidateSet("editor", "offline")]
    [string]$Mode = "editor"
)

$ProjectRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# 1. Find Godot executable
# ---------------------------------------------------------------------------
$Godot = $null

# First: check PATH (works after shell restart post-winget install)
$onPath = Get-Command godot -ErrorAction SilentlyContinue
if ($onPath) {
    $Godot = $onPath.Source
}

# Second: check WinGet package location (works without shell restart)
if (-not $Godot) {
    $wingetPkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine*" `
        -Recurse -Filter "Godot_v*win64.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "console" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($wingetPkg) {
        $Godot = $wingetPkg.FullName
    }
}

# Third: check common manual install locations
if (-not $Godot) {
    $candidates = @(
        "C:\Program Files\Godot\Godot_v4*.exe",
        "C:\Godot\Godot_v4*.exe",
        "$env:USERPROFILE\Godot\Godot_v4*.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $Godot = $found.FullName; break }
    }
}

if (-not $Godot) {
    Write-Error @"
Godot executable not found.

Install it with:
  winget install --id GodotEngine.GodotEngine --exact

Then restart your terminal and try again.
"@
    exit 1
}

Write-Host "[BurnBridgers] Using Godot: $Godot" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 2. Check required files
# ---------------------------------------------------------------------------
$appIdFile = Join-Path $ProjectRoot "steam_appid.txt"
if (-not (Test-Path $appIdFile)) {
    Write-Host "[BurnBridgers] Creating steam_appid.txt (app ID 480 for dev)..." -ForegroundColor Yellow
    Set-Content -Path $appIdFile -Value "480" -NoNewline
}

$gdextension = Join-Path $ProjectRoot "addons\godotsteam\godotsteam.gdextension"
if (-not (Test-Path $gdextension)) {
    Write-Warning @"
GodotSteam GDExtension not found at addons/godotsteam/godotsteam.gdextension.
The game will fail to start. Run the setup steps in SETUP.md first.
"@
}

# ---------------------------------------------------------------------------
# 3. Launch
# ---------------------------------------------------------------------------
$args = @("--path", $ProjectRoot)

if ($Mode -eq "offline") {
    # Pass a flag via a user arg so the game can read it (future) —
    # for now, editor opens normally; press Test (Offline) in the main menu.
    Write-Host "[BurnBridgers] Opening editor. Press 'Test (Offline)' in the main menu to skip Steam." -ForegroundColor Green
}

Write-Host "[BurnBridgers] Launching... (mode: $Mode)" -ForegroundColor Cyan
Start-Process -FilePath $Godot -ArgumentList $args
