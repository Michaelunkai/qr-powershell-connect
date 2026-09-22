#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$UserName = $env:USERNAME, [ValidateRange(1024,65535)][int]$Port = 2222, [ValidateSet('WindowsCapability','WinGetPreview','GitHubZipPreview')][string]$Distribution='WindowsCapability', [ValidateSet('Firewall','MeshBind')][string]$IngressPolicy='Firewall')
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
if ($UserName -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Use a local Windows account with a simple account name.' }
$user = Get-LocalUser -Name $UserName
if (-not $user.Enabled) { throw 'Account is disabled.' }
$admins = Get-LocalGroupMember -SID 'S-1-5-32-544'
if ($user.SID.Value -notin @($admins | ForEach-Object { $_.SID.Value })) { throw 'Requested account must already belong to Administrators.' }
New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
Protect-Path $script:StateRoot
$manifest = Join-Path $script:StateRoot 'installation.json'
$config = Join-Path $env:ProgramData 'ssh\sshd_config'
$reg = 'HKLM:\SOFTWARE\OpenSSH'
$sshd = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
if (Test-Path $manifest) {
    $previous=Get-Content $manifest -Raw | ConvertFrom-Json
    if($previous.phase -ne 'rolled-back'){throw 'Installation already recorded. Run Test-Bridge.ps1 or rollback before reinstalling.'}
    Move-Item -LiteralPath $manifest -Destination (Join-Path $script:StateRoot "installation-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json")
}
if (Get-Service sshd -ErrorAction SilentlyContinue) { throw 'Existing sshd detected. Refusing to replace an independently managed SSH server.' }
$cap = $null
if($Distribution -eq 'WindowsCapability'){$cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0}
$oldShell = Get-ItemProperty -Path $reg -Name DefaultShell -ErrorAction SilentlyContinue
$state = [ordered]@{
    version=1; user=$UserName; port=$Port; phase='preparing'; installedCapability=($Distribution -eq 'WindowsCapability' -and $cap.State -ne 'Installed')
    distribution=$Distribution; installedMsi=$false; sshd=$sshd; ingressPolicy=$IngressPolicy; installedZip=$false
    hadConfig=(Test-Path $config); hadShell=($null -ne $oldShell); oldShell=$null
    hadTailscale=([bool](Get-Service Tailscale -ErrorAction SilentlyContinue)); tailscaleChanged=$false
}
if ($oldShell) { $state.oldShell=$oldShell.DefaultShell }
if (Test-Path $config) { Copy-Item $config (Join-Path $script:StateRoot 'sshd_config.original') }
Write-Atomic $manifest ($state | ConvertTo-Json)
try {
    if($Distribution -eq 'GitHubZipPreview') {
        $zipRoot=Join-Path $env:ProgramFiles 'QrPowerShellConnect'
        $reuse=$false
        if(Test-Path $zipRoot){
            if($null -eq (Get-Variable previous -ErrorAction SilentlyContinue) -or $previous.distribution -ne 'GitHubZipPreview' -or -not $previous.installedZip){throw "Unmanaged installation directory already exists: $zipRoot"}
            $reuse=$true
        }
        $archive=Join-Path $script:StateRoot 'OpenSSH-Win64.zip'
        Invoke-WebRequest -UseBasicParsing 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64.zip' -OutFile $archive
        if((Get-FileHash $archive -Algorithm SHA256).Hash -ne '23f50f3458c4c5d0b12217c6a5ddfde0137210a30fa870e98b29827f7b43aba5'){throw 'Microsoft release archive hash mismatch.'}
        if(-not $reuse){Expand-Archive -LiteralPath $archive -DestinationPath $zipRoot}
        $zipBin=Join-Path $zipRoot 'OpenSSH-Win64'
        foreach($binary in @('sshd.exe','ssh-keygen.exe','sshd-session.exe')) {
            $sig=Get-AuthenticodeSignature (Join-Path $zipBin $binary)
            if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw "Invalid Microsoft signature: $binary"}
        }
        $sshd=Join-Path $zipBin 'sshd.exe'
        $state.sshd=$sshd
        $state.installedZip=$true
        Write-Atomic $manifest ($state | ConvertTo-Json)
        $serviceCommand="`"$sshd`" -E `"$script:StateRoot\sshd.log`""
        New-Service -Name sshd -DisplayName 'OpenSSH SSH Server' -BinaryPathName $serviceCommand -Description 'QR PowerShell Connect SSH service' -StartupType Manual | Out-Null
        Invoke-Checked sc.exe @('privs','sshd','SeAssignPrimaryTokenPrivilege/SeTcbPrivilege/SeBackupPrivilege/SeRestorePrivilege/SeImpersonatePrivilege') | Out-Null
        if(-not (Get-Service sshd -ErrorAction SilentlyContinue)){throw 'ZIP service registration failed.'}
        Get-Service sshd | Stop-Service -Force
    }
    if($Distribution -eq 'WinGetPreview') {
        $state.installedMsi=$true
        Write-Atomic $manifest ($state | ConvertTo-Json)
        Invoke-Checked winget.exe @('install','--id','Microsoft.OpenSSH.Preview','--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity','--override','ADDLOCAL=Server /qn /norestart')
        $sshd=Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe'
        $state.sshd=$sshd
        Write-Atomic $manifest ($state | ConvertTo-Json)
        Get-Service sshd -ErrorAction SilentlyContinue | Stop-Service -Force
    }
    if ($state.installedCapability) {
        $result = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        if ($result.RestartNeeded) { throw 'Windows requires a reboot to finish OpenSSH installation.' }
    }
    $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (-not (Test-Path $ts)) {
        Invoke-Checked winget.exe @('install','--id','Tailscale.Tailscale','--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    }
    if (-not (Test-Path $ts)) { throw 'Tailscale CLI was not installed.' }
    Set-Service Tailscale -StartupType Automatic
    Start-Service Tailscale
    $debugPrefs = & $ts debug prefs
    if ($LASTEXITCODE -ne 0) { throw 'Cannot snapshot Tailscale preferences.' }
    $prefs = $debugPrefs | ConvertFrom-Json
    $state['oldForceDaemon'] = ($prefs.PSObject.Properties.Name -contains 'ForceDaemon' -and [bool]$prefs.ForceDaemon)
    $state.tailscaleChanged=$true
    Write-Atomic $manifest ($state | ConvertTo-Json)
    Invoke-Checked $ts @('set','--unattended=true')
    $listen=''
    if($IngressPolicy -eq 'MeshBind') {
        $mesh=& $ts status --json | ConvertFrom-Json
        if($mesh.BackendState -ne 'Running'){throw 'MeshBind requires Tailscale sign-in before installation.'}
        $meshIp=@($mesh.TailscaleIPs | Where-Object {$_ -match '^100\.'})[0]
        if(-not $meshIp){throw 'No Tailscale IPv4 address.'}
        $listen="ListenAddress 127.0.0.1`nListenAddress $meshIp"
        $state['meshIp']=$meshIp
    }
    if(-not (Test-Path $reg)){New-Item -Path $reg | Out-Null}
    New-ItemProperty -Path $reg -Name DefaultShell -PropertyType String -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Force | Out-Null
    $keyFile = Join-Path $script:StateRoot 'authorized_keys'
    if (-not (Test-Path $keyFile)) { Write-Atomic $keyFile '' }
    Protect-Path $keyFile
    $keyPath = $keyFile.Replace('\','/')
    New-Item -ItemType Directory -Path (Join-Path $env:ProgramData 'ssh\logs') -Force | Out-Null
    $text = @"
Port $Port
AddressFamily inet
$listen
HostKey __PROGRAMDATA__/ssh/ssh_host_ed25519_key
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
AllowUsers $($UserName.ToLowerInvariant())
AuthorizedKeysFile $keyPath
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
X11Forwarding no
LoginGraceTime 20
MaxAuthTries 3
LogLevel VERBOSE
SyslogFacility LOCAL0
Subsystem sftp internal-sftp
"@
    Write-Atomic $config $text
    Invoke-Checked (Join-Path (Split-Path $sshd) 'ssh-keygen.exe') @('-A')
    Get-ChildItem (Join-Path $env:ProgramData 'ssh') -Filter 'ssh_host_*_key' | ForEach-Object {Protect-Path $_.FullName}
    Invoke-Checked $sshd @('-t','-f',$config)
    if($IngressPolicy -eq 'Firewall') {
        Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule | Out-Null
        New-NetFirewallRule -Name 'QrBridge-SSH' -DisplayName 'QR Bridge SSH (Tailscale only)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
    }
    Set-Service sshd -StartupType Automatic
    Invoke-Checked sc.exe @('config','sshd','depend=','Tailscale') | Out-Null
    Invoke-Checked sc.exe @('failure','sshd','reset=','86400','actions=','restart/5000/restart/15000/restart/60000') | Out-Null
    Invoke-Checked sc.exe @('failureflag','sshd','1') | Out-Null
    Start-Service sshd
    $state.phase='installed'
    Write-Atomic $manifest ($state | ConvertTo-Json)
    if($IngressPolicy -eq 'MeshBind'){ & "$PSScriptRoot\Register-Recovery.ps1" }
    Write-Log 'Installed OpenSSH and unattended mesh service; enrollment still required.'
    & $ts status --json | ConvertFrom-Json | Select-Object BackendState,TailscaleIPs
    Write-Output "Installed. SSH port: $Port. Run Test-Bridge.ps1, then enroll Android."
} catch {
    if(Test-Path $config){Copy-Item $config (Join-Path $script:StateRoot 'sshd_config.failed') -Force}
    Write-Log "Installation failed: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
    & "$PSScriptRoot\Uninstall-Bridge.ps1"
    throw
}
