[CmdletBinding()]
param(
    [string]$Workspace = $env:ZEPHYR_WORKSPACE,
    [switch]$SkipSystem,
    [switch]$SkipSdk
)
$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path $PSScriptRoot -Parent
if (-not $Workspace) { $Workspace = Join-Path $ProjectDir '.zephyr' }

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

function Assert-Windows {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
        throw 'Use install-zephyr.sh on Linux or inside WSL2.'
    }
}

function Refresh-ToolPath {
    # Preserve the current session's entries as well as newly installed tools.
    $paths = @($env:Path,
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:ProgramFiles\7-Zip", "$env:ProgramFiles\Go\bin")
    $env:Path = $paths -join [IO.Path]::PathSeparator
}

function Install-WindowsPrerequisites {
    Refresh-ToolPath
    $packages = @(
        @{ Command = 'git'; Id = 'Git.Git' },
        @{ Command = 'uv'; Id = 'astral-sh.uv' },
        @{ Command = 'ninja'; Id = 'Ninja-build.Ninja' },
        @{ Command = 'gperf'; Id = 'oss-winget.gperf' },
        @{ Command = 'dtc'; Id = 'oss-winget.dtc' },
        @{ Command = 'wget'; Id = 'JernejSimoncic.Wget' },
        @{ Command = '7z'; Id = '7zip.7zip' },
        @{ Command = 'go'; Id = 'GoLang.Go' }
    )
    foreach ($package in $packages) {
        if (Get-Command $package.Command -CommandType Application -ErrorAction SilentlyContinue) { continue }
        if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
            throw 'Install Windows App Installer (winget), then rerun this script: https://aka.ms/getwinget'
        }
        Invoke-Checked winget @('install', '--id', $package.Id, '--exact', '--source', 'winget',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        Refresh-ToolPath
        if (-not (Get-Command $package.Command -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "$($package.Command) was installed but is not on PATH. Open a new terminal and rerun."
        }
    }
}

function Install-WindowsOpenOcd {
    param([string]$Root)
    if (Get-Command openocd -CommandType Application -ErrorAction SilentlyContinue) { return }
    $tools = Join-Path $Root 'tools'
    $executable = Join-Path $tools 'xpack-openocd-0.12.0-7/bin/openocd.exe'
    if (Test-Path $executable) { return }
    New-Item -ItemType Directory -Force $tools | Out-Null
    $archive = Join-Path $tools 'openocd.zip'
    # Pinned official xPack release, verified against its published SHA256.
    $url = 'https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-7/xpack-openocd-0.12.0-7-win32-x64.zip'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '6bfd3c97135aafef8affc9af1acf34fd0e2b9ca26044506f6abd7f95b7630052') {
            throw 'OpenOCD archive checksum mismatch.'
        }
        Expand-Archive -Path $archive -DestinationPath $tools -Force
        if (-not (Test-Path $executable)) { throw 'OpenOCD extraction did not provide openocd.exe.' }
    } finally { if (Test-Path $archive) { Remove-Item $archive } }
}

function Install-Zephyr {
    Assert-Windows
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Workspace)
    $sourceManifest = Join-Path $ProjectDir 'west.yml'
    $manifest = Join-Path $resolved 'manifest/west.yml'
    if ((Test-Path (Join-Path $resolved '.west')) -or (Test-Path $manifest)) {
        if (-not (Test-Path $manifest) -or
            (Get-FileHash $sourceManifest).Hash -ne (Get-FileHash $manifest).Hash) {
            throw 'Workspace manifest differs; use a new -Workspace path.'
        }
    }
    if (-not $SkipSystem) { Install-WindowsPrerequisites }
    foreach ($command in @('uv', 'git', 'ninja', '7z', 'go')) {
        if (-not (Get-Command $command -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "Missing $command; rerun without -SkipSystem."
        }
    }
    New-Item -ItemType Directory -Force (Join-Path $resolved 'manifest') | Out-Null
    Copy-Item $sourceManifest $manifest
    $venv = Join-Path $resolved '.venv'
    $python = Join-Path $venv 'Scripts/python.exe'
    $west = Join-Path $venv 'Scripts/west.exe'
    if (-not (Test-Path $python)) { Invoke-Checked uv @('venv', '--python', '3.12', $venv) }
    Invoke-Checked uv @('pip', 'install', '--python', $python, 'west==1.4.0', 'cmake==3.31.6', 'pip')
    $oldPath = $env:Path
    $oldGoBin = $env:GOBIN
    # Enable long-path checkouts only for this process, preserving existing Git overrides.
    $oldGitCount = $env:GIT_CONFIG_COUNT
    $gitIndex = [int]$oldGitCount
    $gitKey = "GIT_CONFIG_KEY_$gitIndex"
    $gitValue = "GIT_CONFIG_VALUE_$gitIndex"
    $oldGitKey = [Environment]::GetEnvironmentVariable($gitKey)
    $oldGitValue = [Environment]::GetEnvironmentVariable($gitValue)
    [Environment]::SetEnvironmentVariable($gitKey, 'core.longpaths')
    [Environment]::SetEnvironmentVariable($gitValue, 'true')
    $env:GIT_CONFIG_COUNT = [string]($gitIndex + 1)
    $env:Path = "$(Join-Path $venv 'Scripts');$env:Path"
    Push-Location $resolved
    try {
        if (-not (Test-Path '.west')) { Invoke-Checked $west @('init', '-l', 'manifest') }
        Invoke-Checked $west @('update', '--narrow', '--fetch-opt=--depth=1')
        Invoke-Checked uv @('pip', 'install', '--python', $python,
            '-r', 'zephyr/scripts/requirements-base.txt', '-r', 'bootloader/mcuboot/scripts/requirements.txt')
        Invoke-Checked $west @('config', '--local', 'build.board', 'nucleo_h755zi_q/stm32h755xx/m7')
        if (-not $SkipSdk) {
            Invoke-Checked $west @('sdk', 'install', '--version', '0.17.2', '--toolchains',
                'arm-zephyr-eabi', '--install-dir', (Join-Path $resolved 'sdk'))
        }
        Install-WindowsOpenOcd $resolved
        $env:GOBIN = Join-Path $venv 'Scripts'
        Invoke-Checked go @('install', 'github.com/apache/mynewt-mcumgr-cli/mcumgr@5c56bd24066c780aad5836429bfa2ecc4f9a944c')
    } finally {
        Pop-Location
        $env:Path = $oldPath
        $env:GOBIN = $oldGoBin
        [Environment]::SetEnvironmentVariable($gitKey, $oldGitKey)
        [Environment]::SetEnvironmentVariable($gitValue, $oldGitValue)
        $env:GIT_CONFIG_COUNT = $oldGitCount
    }
    Write-Host "Ready. Activate with: & '$venv\Scripts\Activate.ps1'"
    Write-Host 'Build with: .\mcu\scripts\build.ps1'
}

# Dot-sourcing exposes the functions for tests without installing anything.
if ($MyInvocation.InvocationName -ne '.') { Install-Zephyr }
