#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidateRange(30,900)][int]$Seconds=900)
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$python = Join-Path (Split-Path $PSScriptRoot) '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { throw 'Create the project virtual environment and install the package first.' }
$state=Get-Content (Join-Path $script:StateRoot 'installation.json') -Raw | ConvertFrom-Json
if($state.phase -ne 'installed'){throw 'The Windows bridge installation is not complete.'}
$active=Join-Path $script:StateRoot 'pairing.txt'
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 8443 -ErrorAction SilentlyContinue)
if($listeners.Count) {
    if(-not (Test-Path $active)){throw 'Port 8443 is already occupied. Close the existing pairing window before retrying.'}
    if((Get-Content $active -Raw).StartsWith('https://qrbridge.invalid/')) {
        throw 'An older pairing process is still running. Close that old pairing window, then run this script again. New QR codes open a real browser page.'
    }
    if(-not (Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue)){throw 'The pairing web page is unavailable. Close the old pairing window and rerun this script.'}
    Write-Host 'An enrollment QR is already active. Displaying it with its original expiry:'
    Invoke-Checked $python @('-m','qrbridge','--show-active',$active)
    Write-Host "PNG image: $script:StateRoot\pairing.png"
    return
}
Write-Host "Creating a QR valid for $Seconds seconds. PNG image: $script:StateRoot\pairing.png"
try {
    if($state.ingressPolicy -eq 'Firewall') {
        New-NetFirewallRule -Name 'QrBridge-Pairing' -DisplayName 'QR Bridge temporary pairing' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8443,8080 -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
    }
    Invoke-Checked $python @('-m','qrbridge','--ttl',"$Seconds")
} finally {
    if($state.ingressPolicy -eq 'Firewall') {Get-NetFirewallRule -Name 'QrBridge-Pairing' -ErrorAction SilentlyContinue | Remove-NetFirewallRule}
}
