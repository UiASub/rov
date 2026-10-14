[CmdletBinding()]
param(
    [switch]$Blinky,
    [string]$Runner = 'openocd',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$FlashArgs
)
. "$PSScriptRoot/zephyr-env.ps1"
$mode = 'ota'
if ($Blinky) { $mode = 'blinky' }
Push-Location $Workspace
try {
    & $West flash -d (Join-Path $ProjectDir "build-$mode") --runner $Runner @FlashArgs
    if ($LASTEXITCODE -ne 0) { throw "Flash failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
