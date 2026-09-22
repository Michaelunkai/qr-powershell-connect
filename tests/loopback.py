"""Exercise the actual Windows SSH server with a temporary key and admin assertion."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from keylock import key_lock


def run_loopback():
    root = Path(os.environ['PROGRAMDATA']) / 'QrPowerShellConnect'
    state = json.loads((root / 'installation.json').read_text(encoding='utf-8-sig'))
    auth = root / 'authorized_keys'
    key = Ed25519PrivateKey.generate()
    public = key.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH).decode()
    entry = public + ' qrbridge-loopback-test'
    try:
        with auth.open('a', encoding='ascii') as out:
            out.write(entry + '\n')
        with tempfile.TemporaryDirectory(dir=root) as directory:
            folder = Path(directory)
            identity = folder / 'key'
            identity.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()))
            subprocess.run(['icacls', str(identity), '/reset'], check=True, capture_output=True)
            subprocess.run(['icacls', str(identity), '/inheritance:r', '/grant:r', '*S-1-5-18:F', '*S-1-5-32-544:F'], check=True, capture_output=True)
            hostkey = (Path(os.environ['PROGRAMDATA']) / 'ssh/ssh_host_ed25519_key.pub').read_text().split()
            known = folder / 'known_hosts'
            known.write_text(f"[127.0.0.1]:{state['port']} {' '.join(hostkey[:2])}\n")
            command = "$p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 41}; Write-Output QRBRIDGE_ADMIN_OK"
            started = time.perf_counter()
            result = subprocess.run(['ssh', '-F', 'NUL', '-i', str(identity), '-p', str(state['port']),
                                     '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=10',
                                     '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={known}',
                                     f"{state['user']}@127.0.0.1", command], capture_output=True, text=True, timeout=60)
            if result.returncode or 'QRBRIDGE_ADMIN_OK' not in result.stdout:
                raise RuntimeError(f'SSH loopback failed ({result.returncode}): {result.stderr}')
            print(json.dumps({'result': 'QRBRIDGE_ADMIN_OK', 'cold_session_ms': round((time.perf_counter()-started)*1000, 2)}))
    finally:
        lines = auth.read_text().splitlines()
        auth.write_text('\n'.join(line for line in lines if line != entry) + '\n', encoding='ascii')


if __name__ == '__main__':
    with key_lock():
        run_loopback()
