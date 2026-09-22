#Requires -RunAsAdministrator
param([Parameter(Mandatory=$true)][string]$PublicKey)
. "$PSScriptRoot\Common.ps1"
Assert-Administrator
if ($PublicKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+=*( .*)?$') { throw 'Provide an ED25519 public key.' }
$fields = $PublicKey.Split(' ')
$auth = Join-Path $script:StateRoot 'authorized_keys'
$mutex=New-Object Threading.Mutex($false,'Global\QrPowerShellConnect-Keys')
$locked=$false
try {
    try { $locked=$mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if(-not $locked){throw 'Another key-store operation is running; retry later.'}
    $lines = @(Get-Content $auth | Where-Object { -not $_.StartsWith("$($fields[0]) $($fields[1])") })
    [IO.File]::WriteAllText($auth, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
} finally {
    if($locked){$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
Write-Log 'Revoked an enrolled public key. Existing SSH sessions must be closed separately.'
