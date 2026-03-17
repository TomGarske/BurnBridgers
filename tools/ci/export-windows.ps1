param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $false)]
    [string]$ExportPresetName = "Windows Desktop",
    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "build/windows"
)

$ErrorActionPreference = "Stop"

function Resolve-GodotCommand {
    # 1. Env vars: only trust them when they point to a real .exe file.
    #    chickensoft-games/setup-godot creates a no-extension hard link and sets
    #    GODOT/GODOT4 to that path. Calling an extension-less binary by full path
    #    on Windows silently does nothing (LASTEXITCODE stays null). Instead we
    #    fall through and use the command name from PATH below.
    foreach ($envPath in @($env:GODOT4, $env:GODOT)) {
        if ([string]::IsNullOrWhiteSpace($envPath)) { continue }
        if ($envPath -match '\.exe$' -and (Test-Path $envPath)) { return $envPath }
        if (Test-Path "$envPath.exe") { return "$envPath.exe" }
    }

    # 2. Command name lookup — return the NAME (not resolved source path) so
    #    PowerShell invokes it via PATH, which handles hard links correctly.
    foreach ($name in @("godot4", "godot")) {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return $name }
    }

    throw "Godot CLI not found. Set GODOT4/GODOT env var to a .exe path, or ensure godot/godot4 is in PATH."
}

$projectRootResolved = (Resolve-Path $ProjectRoot).Path
$outputDirResolved = Join-Path $projectRootResolved $OutputDir
$presetTemplatePath = Join-Path $projectRootResolved "tools/ci/export_presets.ci.cfg"
$presetPath = Join-Path $projectRootResolved "export_presets.cfg"

if (-not (Test-Path $presetTemplatePath)) {
    throw "Missing preset template at '$presetTemplatePath'."
}

Copy-Item -Path $presetTemplatePath -Destination $presetPath -Force
New-Item -ItemType Directory -Path $outputDirResolved -Force | Out-Null

$gameExePath = Join-Path $outputDirResolved "FireTeamMNG.exe"
$godotCommand = Resolve-GodotCommand

Write-Host "Exporting with preset '$ExportPresetName' to '$gameExePath'..."
Write-Host "Using Godot CLI: $godotCommand"
# Stream Godot output directly to the log (no capture) so every line is visible in CI.
& $godotCommand --headless --verbose --path $projectRootResolved --export-release $ExportPresetName $gameExePath
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "Godot export command failed with exit code $exitCode."
}

if (-not (Test-Path $gameExePath)) {
    $dirListing = (Get-ChildItem -Path $outputDirResolved -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "
    if ([string]::IsNullOrWhiteSpace($dirListing)) { $dirListing = "<none>" }
    throw "Export failed: expected executable '$gameExePath' was not created. Output directory files: $dirListing"
}

Write-Host "Export complete."
