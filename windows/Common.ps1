Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:StateRoot = Join-Path $env:ProgramData 'QrPowerShellConnect'
function Assert-Administrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator execution is required.' }
}
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}
function Protect-Path([string]$Path) {
    $rights = '(F)'
    if ((Get-Item -LiteralPath $Path).PSIsContainer) { $rights = '(OI)(CI)(F)' }
    Invoke-Checked icacls.exe @($Path, '/inheritance:r', '/grant:r', "*S-1-5-18:$rights", "*S-1-5-32-544:$rights") | Out-Null
    Invoke-Checked icacls.exe @($Path, '/setowner', '*S-1-5-32-544') | Out-Null
    $inherit=''
    if((Get-Item -LiteralPath $Path).PSIsContainer){$inherit='OICI'}
    $acl=Get-Acl -LiteralPath $Path
    $acl.SetSecurityDescriptorSddlForm("O:BAG:BAD:P(A;$inherit;FA;;;SY)(A;$inherit;FA;;;BA)")
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Write-Atomic([string]$Path, [string]$Text) {
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temp, $Text, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Write-Log([string]$Message) {
    $log = Join-Path $script:StateRoot 'operations.log'
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Move-Item $log "$log.1" -Force }
    Add-Content -LiteralPath $log -Value "$([DateTime]::UtcNow.ToString('o')) $Message"
}
