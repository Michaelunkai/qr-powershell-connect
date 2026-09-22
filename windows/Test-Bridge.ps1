#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([switch]$Loopback)
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$state = Get-Content (Join-Path $script:StateRoot 'installation.json') -Raw | ConvertFrom-Json
$checks = New-Object System.Collections.Generic.List[object]
function Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject]@{name=$Name; passed=$Passed; detail=$Detail})
}
foreach ($name in @('sshd','Tailscale')) {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$name'"
    Check "$name automatic service" ($svc.StartMode -eq 'Auto' -and $svc.State -eq 'Running') "$($svc.StartMode)/$($svc.State)"
    Check "$name noninteractive" (($svc.ServiceType -notmatch 'Interactive') -and $svc.StartName -eq 'LocalSystem') "$($svc.ServiceType)/$($svc.StartName)"
    if ($svc.ProcessId) {
        $proc = Get-Process -Id $svc.ProcessId
        Check "$name session zero" ($proc.SessionId -eq 0) "Session $($proc.SessionId)"
    }
}
$shell = (Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH').DefaultShell
Check 'Default PowerShell' ($shell -eq "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe") $shell
$ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
$status = & $ts status --json | ConvertFrom-Json
Check 'Mesh authenticated' ($status.BackendState -eq 'Running') $status.BackendState
$prefs = & $ts debug prefs | ConvertFrom-Json
$unattended=($prefs.PSObject.Properties.Name -contains 'ForceDaemon' -and [bool]$prefs.ForceDaemon)
Check 'Mesh unattended' $unattended "ForceDaemon=$unattended"
$auth = Join-Path $script:StateRoot 'authorized_keys'
$acl = Get-Acl $auth
$bad = @($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544') })
Check 'Strict key ACL' ($acl.AreAccessRulesProtected -and $bad.Count -eq 0) $acl.Sddl
& $state.sshd -t
Check 'sshd configuration syntax' ($LASTEXITCODE -eq 0) 'sshd -t'
if($state.ingressPolicy -eq 'MeshBind') {
    $task=Get-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery'
    Check 'Silent SYSTEM recovery task' ($task.Principal.UserId -in @('SYSTEM','S-1-5-18') -and $task.Principal.LogonType -eq 'ServiceAccount' -and $task.Settings.Hidden) "$($task.Principal.UserId)/$($task.Principal.LogonType)"
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $state.port)
    $unexpected=@($listeners | Where-Object {$_.LocalAddress -notin @('127.0.0.1',$state.meshIp)})
    Check 'Mesh-only listener binding' ($listeners.Count -eq 2 -and $unexpected.Count -eq 0) (($listeners | ForEach-Object {$_.LocalAddress}) -join ',')
} else {
    $rule = Get-NetFirewallRule -Name 'QrBridge-SSH'
    $filter = $rule | Get-NetFirewallAddressFilter
    Check 'Mesh-only firewall rule' ($rule.Enabled -eq 'True' -and $filter.RemoteAddress -contains '100.64.0.0/255.192.0.0' -or $rule.Enabled -eq 'True' -and $filter.RemoteAddress -contains '100.64.0.0/10') ($filter.RemoteAddress -join ',')
}
if ($Loopback) {
    $python = Join-Path (Split-Path $PSScriptRoot) '.venv\Scripts\python.exe'
    & $python (Join-Path (Split-Path $PSScriptRoot) 'tests\loopback.py')
    Check 'Authenticated loopback and administrator token' ($LASTEXITCODE -eq 0) 'Ephemeral ED25519 key; pinned host; key removed in finally'
}
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
$report = [ordered]@{time=[DateTime]::UtcNow.ToString('o'); boot=$boot; checks=@($checks.ToArray()); visualBootAudit='Not observed: reboot and visual observation are required'; android='Requires enrollment and device-side test'}
Write-Atomic (Join-Path $script:StateRoot 'verification.json') ($report | ConvertTo-Json -Depth 6)
$checks | Format-Table -AutoSize
if (@($checks | Where-Object { -not $_.passed }).Count) { exit 1 }
