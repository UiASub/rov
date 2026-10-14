[CmdletBinding()]
param(
    [switch]$Blinky,
    [string]$Key,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$CMakeArgs
)
. "$PSScriptRoot/zephyr-env.ps1"
$buildArgs = @('build', '-p', 'always', '-b', 'nucleo_h755zi_q/stm32h755xx/m7')
if ($Blinky) {
    if ($Key) { throw '-Key applies only to OTA builds.' }
    $buildArgs += @('-d', (Join-Path $ProjectDir 'build-blinky'), $ProjectDir, '--')
} else {
    $buildArgs += @('--sysbuild', '-d', (Join-Path $ProjectDir 'build-ota'), $ProjectDir, '--',
        '-DEXTRA_CONF_FILE=ota.conf', '-DEXTRA_DTC_OVERLAY_FILE=boards/ota.overlay')
    if ($Key) {
        $resolvedKey = (Resolve-Path $Key -ErrorAction Stop).Path.Replace('\', '/')
        # A config file avoids native argument quoting differences between PowerShell 5 and 7.
        $signingConfig = Join-Path $Workspace 'signing.conf'
        $content = [IO.File]::ReadAllText((Join-Path $ProjectDir 'sysbuild.conf')) +
            "`nSB_CONFIG_BOOT_SIGNATURE_KEY_FILE=`"$resolvedKey`"`n"
        [IO.File]::WriteAllText($signingConfig, $content, [Text.UTF8Encoding]::new($false))
        $buildArgs += "-DSB_CONF_FILE=$signingConfig"
    }
}
Push-Location $Workspace
try {
    & $West @buildArgs @CMakeArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
