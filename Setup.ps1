#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$UserName=$env:USERNAME, [switch]$Pair, [ValidateSet('WindowsCapability','WinGetPreview','GitHubZipPreview')][string]$Distribution='WindowsCapability', [ValidateSet('Firewall','MeshBind')][string]$IngressPolicy='Firewall')
$ErrorActionPreference='Stop'
. "$PSScriptRoot\windows\Common.ps1"
Assert-Administrator
$python=Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { Invoke-Checked py.exe @('-3','-m','venv',"$PSScriptRoot\.venv") }
Invoke-Checked $python @('-m','pip','install','-r',"$PSScriptRoot\requirements.lock")
Invoke-Checked $python @('-m','pip','install','--no-deps','-e',$PSScriptRoot)
$manifest=Join-Path $script:StateRoot 'installation.json'
if (-not (Test-Path $manifest)) { & "$PSScriptRoot\windows\Install-Bridge.ps1" -UserName $UserName -Distribution $Distribution -IngressPolicy $IngressPolicy }
else {
    $state=Get-Content $manifest -Raw | ConvertFrom-Json
    if($state.phase -eq 'rolled-back'){& "$PSScriptRoot\windows\Install-Bridge.ps1" -UserName $UserName -Distribution $Distribution -IngressPolicy $IngressPolicy}
    elseif($state.phase -ne 'installed'){throw "Installation state is $($state.phase). Inspect logs and rollback before reinstalling."}
}
$status=& "$env:ProgramFiles\Tailscale\tailscale.exe" status --json | ConvertFrom-Json
if($status.BackendState -ne 'Running') {
    Write-Output 'Complete Tailscale sign-in, then rerun Setup.ps1 -Pair.'
    Invoke-Checked "$env:ProgramFiles\Tailscale\tailscale.exe" @('up','--unattended=true','--timeout=60s')
}
& "$PSScriptRoot\windows\Test-Bridge.ps1" -Loopback
if($Pair){ & "$PSScriptRoot\windows\Start-Pairing.ps1" }
