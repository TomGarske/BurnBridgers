param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $false)]
    [string]$BuildOutputDir = "build/windows",
    [Parameter(Mandatory = $false)]
    [string]$LinuxBuildOutputDir = "build/linux"
)

$ErrorActionPreference = "Stop"

function Require-Env {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
    return $value
}

function Require-NumericId {
    param(
        [string]$Name,
        [string]$Value
    )
    if ($Value -notmatch '^\d+$') {
        throw "$Name must be numeric digits only. Current value: '$Value'"
    }
    return $Value
}

$projectRootResolved = (Resolve-Path $ProjectRoot).Path
$contentRootWindows = Join-Path $projectRootResolved $BuildOutputDir
$contentRootLinux = Join-Path $projectRootResolved $LinuxBuildOutputDir
$hasWindows = Test-Path $contentRootWindows
$hasLinux = Test-Path $contentRootLinux

if (-not $hasWindows -and -not $hasLinux) {
    throw "No build output directories found. Expected at least one of: '$contentRootWindows', '$contentRootLinux'"
}

$steamAppId = (Require-Env "STEAM_APP_ID").Trim()
$steamUser = (Require-Env "STEAM_USERNAME").Trim()
$steamPassword = Require-Env "STEAM_PASSWORD"
$steamTotpSecret = Require-Env "STEAM_TOTP_SECRET"
$steamAppId = Require-NumericId -Name "STEAM_APP_ID" -Value $steamAppId

$steamDepotIdWindows = ""
if ($hasWindows) {
    $steamDepotIdWindows = (Require-Env "STEAM_DEPOT_ID_WINDOWS").Trim()
    $steamDepotIdWindows = Require-NumericId -Name "STEAM_DEPOT_ID_WINDOWS" -Value $steamDepotIdWindows
}

$steamDepotIdLinux = ""
if ($hasLinux) {
    $steamDepotIdLinux = (Require-Env "STEAM_DEPOT_ID_LINUX").Trim()
    $steamDepotIdLinux = Require-NumericId -Name "STEAM_DEPOT_ID_LINUX" -Value $steamDepotIdLinux
}

$steamDir = Join-Path $env:RUNNER_TEMP "steamcmd"
New-Item -ItemType Directory -Path $steamDir -Force | Out-Null
$steamZip = Join-Path $steamDir "steamcmd.zip"
$steamExe = Join-Path $steamDir "steamcmd.exe"

if (-not (Test-Path $steamExe)) {
    Write-Host "Downloading SteamCMD..."
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $steamZip -UseBasicParsing
    Expand-Archive -Path $steamZip -DestinationPath $steamDir -Force
}

# Generate a Steam TOTP code from the shared secret.
# Steam uses a non-standard TOTP: HMAC-SHA1, 30s period, custom charset, 5-char codes.
function Get-SteamTotpCode {
    param([string]$SharedSecret)

    $secretBytes = [Convert]::FromBase64String($SharedSecret)
    $time = [long][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 30)
    $timeBytes = [byte[]]::new(8)
    for ($i = 7; $i -ge 0; $i--) {
        $timeBytes[$i] = [byte]($time -band 0xFF)
        $time = $time -shr 8
    }

    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $secretBytes
    $hash = $hmac.ComputeHash($timeBytes)

    $offset = $hash[19] -band 0x0F
    $code = (($hash[$offset] -band 0x7F) -shl 24) -bor
            (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
            (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
             ($hash[$offset + 3] -band 0xFF)

    $chars = "23456789BCDFGHJKMNPQRTVWXY"
    $totpCode = ""
    for ($i = 0; $i -lt 5; $i++) {
        $totpCode += $chars[$code % $chars.Length]
        $code = [Math]::Floor($code / $chars.Length)
    }

    return $totpCode
}

# Run SteamCMD once to let it self-update.
Write-Host "Running SteamCMD self-update..."
& $steamExe +quit

$totpCode = Get-SteamTotpCode -SharedSecret $steamTotpSecret
Write-Host "Generated Steam TOTP code from shared secret."

$templateAppBuild = Join-Path $projectRootResolved "tools/steam/app_build_template.vdf"
$templateDepotWindows = Join-Path $projectRootResolved "tools/steam/depot_build_windows_template.vdf"
$templateDepotLinux = Join-Path $projectRootResolved "tools/steam/depot_build_linux_template.vdf"
if (-not (Test-Path $templateAppBuild)) { throw "Missing $templateAppBuild" }

$generatedDir = Join-Path $env:RUNNER_TEMP "steam_build"
New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
$generatedAppBuild = Join-Path $generatedDir "app_build.vdf"

$description = "Ironwake - GitHub Actions #$($env:GITHUB_RUN_NUMBER) $($env:GITHUB_SHA)"

# Build app VDF — only include depots that have build artifacts.
$appBuildText = Get-Content $templateAppBuild -Raw
$appBuildText = $appBuildText.Replace("__APP_ID__", $steamAppId)
$appBuildText = $appBuildText.Replace("__DESC__", $description)
# Content root for the app build is the project root; each depot references its own content.
$appBuildText = $appBuildText.Replace("__CONTENT_ROOT__", $projectRootResolved)

# Windows depot
if ($hasWindows) {
    $appBuildText = $appBuildText.Replace("__DEPOT_ID_WINDOWS__", $steamDepotIdWindows)
    $generatedDepotWindows = Join-Path $generatedDir "depot_build_windows.vdf"
    $depotText = Get-Content $templateDepotWindows -Raw
    $depotText = $depotText.Replace("__DEPOT_ID_WINDOWS__", $steamDepotIdWindows)
    # Override ContentRoot to point at the Windows build output.
    $depotText = $depotText.Replace('"ContentRoot" "."', '"ContentRoot" "' + $contentRootWindows + '"')
    Set-Content -Path $generatedDepotWindows -Value $depotText -NoNewline
    Write-Host "Windows depot configured: $steamDepotIdWindows -> $contentRootWindows"
} else {
    # Remove Windows depot line from app build.
    $appBuildText = $appBuildText -replace '(?m)^\s*"__DEPOT_ID_WINDOWS__".*\r?\n?', ''
    Write-Host "Windows build not found — skipping Windows depot."
}

# Linux depot
if ($hasLinux) {
    $appBuildText = $appBuildText.Replace("__DEPOT_ID_LINUX__", $steamDepotIdLinux)
    $generatedDepotLinux = Join-Path $generatedDir "depot_build_linux.vdf"
    $depotText = Get-Content $templateDepotLinux -Raw
    $depotText = $depotText.Replace("__DEPOT_ID_LINUX__", $steamDepotIdLinux)
    $depotText = $depotText.Replace('"ContentRoot" "."', '"ContentRoot" "' + $contentRootLinux + '"')
    Set-Content -Path $generatedDepotLinux -Value $depotText -NoNewline
    Write-Host "Linux depot configured: $steamDepotIdLinux -> $contentRootLinux"
} else {
    $appBuildText = $appBuildText -replace '(?m)^\s*"__DEPOT_ID_LINUX__".*\r?\n?', ''
    Write-Host "Linux build not found — skipping Linux depot."
}

Set-Content -Path $generatedAppBuild -Value $appBuildText -NoNewline

Write-Host "Uploading build to Steam app $steamAppId..."
& $steamExe +set_steam_guard_code $totpCode +login $steamUser $steamPassword +run_app_build $generatedAppBuild +quit

if ($LASTEXITCODE -ne 0) {
    Write-Host "Generated app build config:"
    Get-Content $generatedAppBuild
    Write-Host "Generated depot build config:"
    Get-Content $generatedDepotBuild
    $stderrPath = Join-Path $steamDir "logs/stderr.txt"
    if (Test-Path $stderrPath) {
        Write-Host "SteamCMD stderr ($stderrPath):"
        Get-Content $stderrPath
    }
    throw "SteamCMD upload failed with exit code $LASTEXITCODE"
}

Write-Host "Steam upload complete."
