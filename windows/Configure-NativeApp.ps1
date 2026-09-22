#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [string]$Package='org.qrbridge.powershell',
    [string]$Adb='F:\backup\windowsapps\installed\AndroidStudio\android-sdk\platform-tools\adb.exe',
    [string]$ExpectedModel='SM-S938B'
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
if($Package -notmatch '^org\.qrbridge\.powershell(?:\.debug)?$'){throw 'Unexpected application package'}
$model=(& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $model -ne $ExpectedModel){throw 'Target device model does not match the intended phone'}
$state=Get-Content (Join-Path $script:StateRoot 'installation.json') -Raw | ConvertFrom-Json
if($state.phase -ne 'installed'){throw 'Install and verify the Windows bridge first'}
& $Adb -s $Serial shell am start -W -n "$Package/org.connectbot.bridge.BridgeActivity" | Out-Null
if($LASTEXITCODE -ne 0){throw 'Cannot launch installed native app'}
$remote="/sdcard/Android/data/$Package/files"
$public=$null
for($attempt=0;$attempt -lt 20;$attempt++) {
    $candidate=(& $Adb -s $Serial shell cat "$remote/device-public-key.txt" 2>$null | Out-String).Trim()
    if($LASTEXITCODE -eq 0 -and $candidate -match '^ssh-ed25519 [A-Za-z0-9+/]+=*$'){$public=$candidate;break}
    Start-Sleep -Milliseconds 500
}
if(-not $public){throw 'The app has not generated its public key yet. Check its setup screen.'}
$project=Split-Path $PSScriptRoot
$validation=Join-Path $script:StateRoot 'native-device-public-key.txt'
[IO.File]::WriteAllText($validation,$public,(New-Object Text.UTF8Encoding($false)))
& "$project\.venv\Scripts\python.exe" -c 'from pathlib import Path; from qrbridge import validate_key; import sys; validate_key(Path(sys.argv[1]).read_text())' $validation
if($LASTEXITCODE -ne 0){throw 'Invalid device public key'}
$mesh=(& "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4 | Select-Object -First 1).Trim()
if($mesh -notmatch '^100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}$'){throw 'No running Tailscale IPv4 address'}
$hostkey=(Get-Content "$env:ProgramData\ssh\ssh_host_ed25519_key.pub" -Raw).Trim().Split(' ')[0..1] -join ' '
$mutex=New-Object Threading.Mutex($false,'Global\QrPowerShellConnect-Keys')
$locked=$false
try {
    try{$locked=$mutex.WaitOne(10000)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another key-store operation is running'}
    $auth=Join-Path $script:StateRoot 'authorized_keys'
    $existing=@(Get-Content -LiteralPath $auth)
    if(-not($existing | Where-Object { $_ -eq $public -or $_.StartsWith("$public ") })) {
        [IO.File]::AppendAllText($auth,"`n$public powershell-native-android`n",(New-Object Text.UTF8Encoding($false)))
    }
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
$metadata=Join-Path $script:StateRoot 'native-connection.json'
@{host=$mesh;port=[int]$state.port;user=$state.user;hostkey=$hostkey;devicePublicKey=$public} | ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding UTF8
& $Adb -s $Serial push $metadata "$remote/connection.json" | Out-Null
if($LASTEXITCODE -ne 0){throw 'Connection metadata transfer failed; public key remains authorized for retry'}
& $Adb -s $Serial shell am start -W -n "$Package/org.connectbot.bridge.BridgeActivity" | Out-Null
if($LASTEXITCODE -ne 0){throw 'Native app launch failed'}
Write-Log 'Configured native Android application using its locally generated public key.'
Write-Host 'Native connection configured. Verify the PowerShell session on the phone.'
