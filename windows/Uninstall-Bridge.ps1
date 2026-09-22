#Requires -RunAsAdministrator
[CmdletBinding()]
param()
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$manifest = Join-Path $script:StateRoot 'installation.json'
if (-not (Test-Path $manifest)) { throw 'No installation manifest exists.' }
$state = Get-Content $manifest -Raw | ConvertFrom-Json
if ($state.phase -eq 'rolled-back') { Write-Output 'Already rolled back.'; return }
Get-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery' -ErrorAction SilentlyContinue | Stop-ScheduledTask
Get-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
Get-Service sshd -ErrorAction SilentlyContinue | Stop-Service -Force
Get-NetFirewallRule -Name 'QrBridge-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$config = Join-Path $env:ProgramData 'ssh\sshd_config'
if ($state.hadConfig) { Copy-Item (Join-Path $script:StateRoot 'sshd_config.original') $config -Force }
elseif (Test-Path $config) { Remove-Item -LiteralPath $config }
$reg = 'HKLM:\SOFTWARE\OpenSSH'
if ($state.hadShell) { Set-ItemProperty $reg DefaultShell $state.oldShell }
else { Remove-ItemProperty $reg DefaultShell -ErrorAction SilentlyContinue }
if ($state.tailscaleChanged) {
    $setting = '--unattended=' + $state.oldForceDaemon.ToString().ToLowerInvariant()
    Invoke-Checked "$env:ProgramFiles\Tailscale\tailscale.exe" @('set',$setting)
}
if ($state.installedCapability) { Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
elseif ($state.PSObject.Properties.Name -contains 'installedMsi' -and $state.installedMsi) {
    & winget.exe uninstall --id Microsoft.OpenSSH.Preview --exact --silent --disable-interactivity
    if($LASTEXITCODE -notin @(0,-1978335212)){throw "OpenSSH MSI rollback failed: $LASTEXITCODE"}
    $global:LASTEXITCODE=0
}
elseif ($state.PSObject.Properties.Name -contains 'installedZip' -and $state.installedZip) {
    if(Get-Service sshd -ErrorAction SilentlyContinue){Invoke-Checked sc.exe @('delete','sshd') | Out-Null}
    Write-Log 'ZIP binaries retained under Program Files for audit; sshd service removed.'
}
elseif (Get-Service sshd -ErrorAction SilentlyContinue) { Set-Service sshd -StartupType Disabled }
$state.phase='rolled-back'
Write-Atomic $manifest ($state | ConvertTo-Json)
Write-Log 'Rolled back SSH bridge. Tailscale installation, identity, audit logs and enrolled public keys retained.'
Write-Output 'Bridge stopped and configuration restored. Tailscale is retained to avoid deleting its identity.'
