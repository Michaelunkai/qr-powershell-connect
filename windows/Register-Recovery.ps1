#Requires -RunAsAdministrator
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
$target=Join-Path $script:StateRoot 'Repair-Bridge.ps1'
Copy-Item (Join-Path $PSScriptRoot 'Repair-Bridge.ps1') $target -Force
Protect-Path $target
$action=New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
$boot=New-ScheduledTaskTrigger -AtStartup
$periodic=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery' -Action $action -Trigger @($boot,$periodic) -Principal $principal -Settings $settings -Description 'Restore SSH mesh listener after boot/network readiness; SYSTEM Session 0.' -Force | Out-Null
Start-ScheduledTask -TaskName 'QrPowerShellConnect-Recovery'
Write-Log 'Registered headless SYSTEM mesh readiness recovery task.'
