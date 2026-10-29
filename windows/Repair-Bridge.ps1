#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'QrPowerShellConnect'
$state=Get-Content (Join-Path $root 'installation.json') -Raw | ConvertFrom-Json
if($state.phase -ne 'installed' -or $state.ingressPolicy -ne 'MeshBind'){exit 0}
$log=Join-Path $root 'recovery.log'
if((Test-Path $log) -and (Get-Item $log).Length -gt 1MB){Move-Item $log "$log.1" -Force}
function Note([string]$message){Add-Content $log "$([DateTime]::UtcNow.ToString('o')) $message"}
try {
    # A tuning tool that writes Start=4 straight to the registry can leave
    # SCM's live database stale: queries report Auto but a start fails with
    # 1058 until a fresh ChangeServiceConfig reconciles it. Only a failed
    # start triggers the reconfigure, so healthy cycles stay write-free.
    $mesh=Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    if($mesh -and $mesh.Status -ne 'Running'){
        $started=$false
        try{Start-Service -Name Tailscale -ErrorAction Stop;$started=$true}catch{}
        if(-not $started){
            $null=sc.exe config Tailscale start= auto
            Start-Sleep -Seconds 2
            try{Start-Service -Name Tailscale -ErrorAction Stop;$started=$true}catch{}
        }
        if($started){Note 'Recovered the Tailscale service (re-enabled and started).'}
        else{Note 'Tailscale would not start; next scheduled check will retry.';exit 1}
    }
    # sshd depends on the mesh service; after any outage it needs a nudge.
    $ssh=Get-Service -Name sshd -ErrorAction SilentlyContinue
    if($ssh -and $ssh.Status -ne 'Running'){
        $err=$null
        try{Start-Service -Name sshd -ErrorAction Stop}catch{$err=$_.Exception.Message}
        if($err){Note "sshd would not start: $err";exit 1}
        Note 'Started sshd after mesh recovery.'
    }
    for($attempt=0;$attempt -lt 60;$attempt++) {
        $address=Get-NetIPAddress -IPAddress $state.meshIp -ErrorAction SilentlyContinue
        if($address) {
            $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $state.port -ErrorAction SilentlyContinue)
            if($state.meshIp -notin @($listeners | ForEach-Object {$_.LocalAddress})) {
                Restart-Service sshd
                Note 'Restarted SSH after mesh listener was missing.'
            }
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    Note 'Mesh address is unavailable; next scheduled check will retry.'
    exit 1
} catch {
    Note $_.Exception.Message
    exit 1
}
