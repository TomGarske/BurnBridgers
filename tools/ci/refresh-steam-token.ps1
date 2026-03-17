<#
.SYNOPSIS
    Regenerates the STEAM_CONFIG_VDF GitHub secret with a fresh Steam session token.
.DESCRIPTION
    Downloads SteamCMD, logs in (will prompt for Steam Guard code via email),
    then base64-encodes the resulting config.vdf and uploads it as a GitHub secret.
    Run this whenever the Steam session token expires and CI uploads start failing.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SteamUsername = "fireteam_buildbot",
    [Parameter(Mandatory = $false)]
    [string]$Repo = "TomGarske/BurnBridgers"
)

$ErrorActionPreference = "Stop"

$steamDir = Join-Path $env:TEMP "steamcmd"
$steamZip = Join-Path $env:TEMP "steamcmd.zip"
$steamExe = Join-Path $steamDir "steamcmd.exe"

# Download SteamCMD if not already present
if (-not (Test-Path $steamExe)) {
    Write-Host "Downloading SteamCMD..."
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $steamZip -UseBasicParsing
    Expand-Archive $steamZip -DestinationPath $steamDir -Force
}

# Self-update
Write-Host "Running SteamCMD self-update..."
& $steamExe +quit

# Prompt for password securely
$cred = Get-Credential -UserName $SteamUsername -Message "Enter Steam builder account password"
$password = $cred.GetNetworkCredential().Password

# Login (will prompt for Steam Guard code)
Write-Host "Logging in as $SteamUsername (check email for Steam Guard code)..."
& $steamExe +login $SteamUsername $password +quit

if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD login failed with exit code $LASTEXITCODE"
}

# Encode and upload
$configPath = Join-Path $steamDir "config\config.vdf"
if (-not (Test-Path $configPath)) {
    throw "config.vdf not found at $configPath"
}

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($configPath))
Write-Host "Uploading new STEAM_CONFIG_VDF secret to $Repo..."
gh secret set STEAM_CONFIG_VDF --repo $Repo --body $b64

Write-Host "Done! Re-run the CI workflow now before the token expires."
