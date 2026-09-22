#Requires -RunAsAdministrator
[CmdletBinding()]
param()
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$state=Get-Content (Join-Path $script:StateRoot 'installation.json') -Raw | ConvertFrom-Json
if($state.ingressPolicy -ne 'MeshBind'){throw 'This test exercises the MeshBind recovery task.'}
if(@(Get-Content (Join-Path $script:StateRoot 'authorized_keys') | Where-Object {$_ -match '^ssh-'}).Count){throw 'Recovery test intentionally stops SSH. Run before enrollment to avoid interrupting enrolled users.'}
try {
    Stop-Service sshd
    Start-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery'
    $ready=$false
    for($i=0;$i -lt 30;$i++) {
        $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $state.port -ErrorAction SilentlyContinue)
        if($state.meshIp -in @($listeners | ForEach-Object {$_.LocalAddress})){$ready=$true; break}
        Start-Sleep -Seconds 1
    }
    if(-not $ready){throw 'SYSTEM recovery failed to restore the mesh listener within 30 seconds.'}
    $info=Get-ScheduledTaskInfo -TaskName 'QrPowerShellConnect-Recovery'
    Write-Output "RECOVERY_OK mesh listener restored; last task result=$($info.LastTaskResult)"
    Write-Log 'Verified recovery by stopping SSH and observing the SYSTEM task restore its mesh listener.'
} finally {
    if((Get-Service sshd).Status -ne 'Running'){Start-Service sshd}
}
