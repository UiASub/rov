$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/install-zephyr.ps1'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors) { throw ($parseErrors | Out-String) }
. $scriptPath
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory $testRoot | Out-Null
$Workspace = Join-Path $testRoot 'workspace with spaces'
$SkipSystem = $true
$SkipSdk = $true
$script:Calls = [Collections.Generic.List[string]]::new()
function Assert-Windows {}
function Install-WindowsOpenOcd { param($Root) }
function Get-Command { param($Name, $ErrorAction, $CommandType) return @{ Name = $Name } }
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    $script:Calls.Add("$Program $($Arguments -join ' ')")
    if ($Program -eq 'uv' -and $Arguments[0] -eq 'venv') {
        $scripts = Join-Path $Arguments[3] 'Scripts'
        New-Item -ItemType Directory -Force $scripts | Out-Null
        New-Item -ItemType File (Join-Path $scripts 'python.exe') | Out-Null
    }
    if ($Arguments[0] -eq 'init') { New-Item -ItemType Directory '.west' | Out-Null }
}
try {
    $originalLocation = Get-Location
    Install-Zephyr
    Install-Zephyr
    $callText = $script:Calls -join "`n"
    if (($script:Calls | Where-Object { $_ -match 'init -l manifest$' }).Count -ne 1) { throw "West init rerun: $callText" }
    if (($script:Calls | Where-Object { $_ -match 'update --narrow' }).Count -ne 2) { throw 'Missing west update' }
    if ($callText -match 'sdk install') { throw 'SkipSdk ignored' }
    if (($script:Calls | Where-Object { $_ -match '^go install' }).Count -ne 2) { throw 'Missing MCUmgr setup' }
    if ((Get-Location).Path -ne $originalLocation.Path) { throw 'Location was not restored' }
    $manifest = Join-Path $Workspace 'manifest/west.yml'
    $before = $script:Calls.Count
    Set-Content $manifest 'foreign'
    $rejected = $false
    try { Install-Zephyr } catch {
        if ($_.Exception.Message -notmatch 'manifest differs') { throw }
        $rejected = $true
    }
    if (-not $rejected -or $script:Calls.Count -ne $before) { throw 'Foreign workspace was changed' }
    Copy-Item (Join-Path $ProjectDir 'west.yml') $manifest
    $SkipSdk = $false
    Install-Zephyr
    if (($script:Calls -join "`n") -notmatch 'sdk install --version 0.17.2 --toolchains arm-zephyr-eabi') { throw 'Missing pinned SDK' }
    # Exercise the dependency plan with missing applications and an existing git.
    function Refresh-ToolPath {}
    $script:Available = @{ git = $true; winget = $true }
    function Get-Command {
        param($Name, $ErrorAction, $CommandType)
        if ($CommandType -ne 'Application') { throw 'Aliases must not satisfy tool checks' }
        if ($script:Available[$Name]) { return @{ Name = $Name } }
    }
    $script:Installed = [Collections.Generic.List[string]]::new()
    function Invoke-Checked {
        param([string]$Program, [string[]]$Arguments)
        if ($Program -ne 'winget') { throw 'Expected winget' }
        $id = $Arguments[2]
        $script:Installed.Add($id)
        $command = @{ 'astral-sh.uv'='uv'; 'Ninja-build.Ninja'='ninja';
            'oss-winget.gperf'='gperf'; 'oss-winget.dtc'='dtc';
            'JernejSimoncic.Wget'='wget'; '7zip.7zip'='7z'; 'GoLang.Go'='go' }[$id]
        $script:Available[$command] = $true
    }
    Install-WindowsPrerequisites
    if ($script:Installed.Count -ne 7 -or $script:Installed.Contains('Git.Git')) { throw 'Prerequisite plan is wrong' }
    # Fail an external command: the real wrapper must surface nonzero exit status.
    . $scriptPath -Workspace $Workspace -SkipSystem -SkipSdk
    $failed = $false
    try { Invoke-Checked 'pwsh' @('-NoProfile', '-Command', 'exit 17') } catch { $failed = $true }
    if (-not $failed) { throw 'External command failure was swallowed' }
    Write-Host 'Windows installer rerun, paths, SDK, ownership and failure checks passed.'
} finally { Remove-Item -Recurse -Force $testRoot }

# Parse every entry point, including files not invoked by the mocked installer.
foreach ($file in Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts') -Filter '*.ps1') {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors) { throw ($parseErrors | Out-String) }
}

# Run unchanged build/flash scripts with a fixture environment and a recording west.
$wrapperRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$fixtureScripts = Join-Path $wrapperRoot 'scripts'
$fixtureWorkspace = Join-Path $wrapperRoot 'workspace with spaces'
New-Item -ItemType Directory $fixtureScripts, $fixtureWorkspace | Out-Null
$sourceScripts = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
Copy-Item (Join-Path $sourceScripts 'build.ps1') $fixtureScripts
Copy-Item (Join-Path $sourceScripts 'flash.ps1') $fixtureScripts
Copy-Item (Join-Path (Split-Path $sourceScripts -Parent) 'sysbuild.conf') $wrapperRoot
$fakeEnv = @'
$ProjectDir = Split-Path $PSScriptRoot -Parent
$Workspace = Join-Path $ProjectDir 'workspace with spaces'
$West = Join-Path $PSScriptRoot 'fake-west.ps1'
'@
Set-Content (Join-Path $fixtureScripts 'zephyr-env.ps1') $fakeEnv
$fakeWest = @'
$record = @{ Arguments = @($args); Location = (Get-Location).Path }
$record | ConvertTo-Json -Depth 4 | Set-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'west-call.json')
$global:LASTEXITCODE = 0
'@
Set-Content (Join-Path $fixtureScripts 'fake-west.ps1') $fakeWest
$keyFile = Join-Path $wrapperRoot 'key with spaces.pem'
New-Item -ItemType File $keyFile | Out-Null
try {
    $beforeLocation = (Get-Location).Path
    & (Join-Path $fixtureScripts 'build.ps1') -Key $keyFile
    $record = Get-Content (Join-Path $wrapperRoot 'west-call.json') -Raw | ConvertFrom-Json
    if ($record.Arguments -notcontains '--sysbuild' -or $record.Location -ne $fixtureWorkspace) { throw 'OTA build invocation is wrong' }
    $config = Get-Content (Join-Path $fixtureWorkspace 'signing.conf') -Raw
    if ($config -notmatch 'SB_CONFIG_BOOTLOADER_MCUBOOT=y' -or $config -notmatch 'key with spaces.pem"') { throw 'Signing configuration is wrong' }
    & (Join-Path $fixtureScripts 'build.ps1') -Blinky
    $record = Get-Content (Join-Path $wrapperRoot 'west-call.json') -Raw | ConvertFrom-Json
    if ($record.Arguments -contains '--sysbuild' -or $record.Arguments -notcontains (Join-Path $wrapperRoot 'build-blinky')) { throw 'Blinky invocation is wrong' }
    & (Join-Path $fixtureScripts 'flash.ps1') -Runner stm32cubeprogrammer
    $record = Get-Content (Join-Path $wrapperRoot 'west-call.json') -Raw | ConvertFrom-Json
    if ($record.Arguments -notcontains 'stm32cubeprogrammer' -or $record.Arguments -notcontains (Join-Path $wrapperRoot 'build-ota')) { throw 'Flash invocation is wrong' }
    if ((Get-Location).Path -ne $beforeLocation) { throw 'Wrapper did not restore location' }
    Write-Host 'Windows build, signing-key and flash wrapper checks passed.'
} finally { Remove-Item -Recurse -Force $wrapperRoot }
