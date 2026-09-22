#Requires -Version 5.1
#Requires -RunAsAdministrator
param()
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$services = foreach ($name in @('sshd','Tailscale')) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$name'"
    if (-not $service) { throw "Missing service: $name" }
    $process = $null
    if ($service.ProcessId) { $process = Get-Process -Id $service.ProcessId }
    [pscustomobject]@{
        name=$name; state=$service.State; startup=$service.StartMode; account=$service.StartName
        serviceType=$service.ServiceType
        sessionId=$(if($process){$process.SessionId}else{$null})
        processStartAfterBootMs=$(if($process){[math]::Round(($process.StartTime-$boot).TotalMilliseconds,2)}else{$null})
    }
}
$events = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=$boot; Id=7036,7031,7034} -ErrorAction SilentlyContinue | Where-Object {$_.Message -match 'OpenSSH|Tailscale'} | Select-Object TimeCreated,Id,Message)
$report = [ordered]@{
    observedAt=[DateTime]::UtcNow.ToString('o'); boot=$boot.ToUniversalTime().ToString('o')
    services=@($services); serviceEvents=$events
    interpretation='Process start offset measures the current process, possibly a later restart. It is not network-ready latency.'
    visualArtifacts='Unverified: observe a physical boot. Session 0 services do not create interactive desktop consoles.'
}
$path=Join-Path $script:StateRoot 'boot-audit.json'
Write-Atomic $path ($report | ConvertTo-Json -Depth 6)
$services | Format-Table -AutoSize
Write-Output "Audit saved to $path"
