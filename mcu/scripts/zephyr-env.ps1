# Shared by the native Windows build and flash entry points.
$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path $PSScriptRoot -Parent
$Workspace = $env:ZEPHYR_WORKSPACE
if (-not $Workspace) { $Workspace = Join-Path $ProjectDir '.zephyr' }
$Workspace = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Workspace)
$West = Join-Path $Workspace '.venv/Scripts/west.exe'
if (-not (Test-Path $West)) { throw 'Run .\mcu\scripts\install-zephyr.ps1 first.' }
$env:Path = "$(Join-Path $Workspace '.venv/Scripts');$env:Path"
$env:ZEPHYR_BASE = Join-Path $Workspace 'zephyr'
if (Test-Path (Join-Path $Workspace 'sdk')) { $env:ZEPHYR_SDK_INSTALL_DIR = Join-Path $Workspace 'sdk' }
$openOcdBin = Join-Path $Workspace 'tools/xpack-openocd-0.12.0-7/bin'
if (Test-Path $openOcdBin) { $env:Path = "$openOcdBin;$env:Path" }
