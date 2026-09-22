#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'QrPowerShellConnect'
$state=Get-Content (Join-Path $root 'installation.json') -Raw | ConvertFrom-Json
if($state.phase -ne 'installed' -or $state.ingressPolicy -ne 'MeshBind'){exit 0}
$log=Join-Path $root 'recovery.log'
if((Test-Path $log) -and (Get-Item $log).Length -gt 1MB){Move-Item $log "$log.1" -Force}
try {
    for($attempt=0;$attempt -lt 60;$attempt++) {
        $address=Get-NetIPAddress -IPAddress $state.meshIp -ErrorAction SilentlyContinue
        if($address) {
            $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $state.port -ErrorAction SilentlyContinue)
            if($state.meshIp -notin @($listeners | ForEach-Object {$_.LocalAddress})) {
                Restart-Service sshd
                Add-Content $log "$([DateTime]::UtcNow.ToString('o')) Restarted SSH after mesh listener was missing."
            }
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    Add-Content $log "$([DateTime]::UtcNow.ToString('o')) Mesh address is unavailable; next scheduled check will retry."
    exit 1
} catch {
    Add-Content $log "$([DateTime]::UtcNow.ToString('o')) $($_.Exception.Message)"
    exit 1
}
