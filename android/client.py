#!/data/data/com.termux/files/usr/bin/python
"""Termux enrollment client using certificate pinning before sending credentials."""
import base64
import hashlib
from http.client import HTTPSConnection
import ipaddress
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import time
from urllib.parse import urlsplit

ROOT = Path.home() / '.ssh/qrbridge'


def control_path(destination):
    # OpenSSH appends a temporary suffix while creating its Unix socket.
    # Termux's long home path leaves insufficient space for the 40-byte %C.
    digest = hashlib.sha256(json.dumps(destination, sort_keys=True).encode()).hexdigest()[:16]
    return ROOT / ('c-' + digest)


def parse_uri(uri):
    prefix = 'https://qrbridge.invalid/enroll#'
    parsed = urlsplit(uri)
    legacy = uri.startswith(prefix)
    if len(uri) > 4096 or not (legacy or (parsed.scheme == 'http' and parsed.port == 8080 and parsed.path == '/enroll' and not parsed.username and not parsed.password and not parsed.query)):
        raise ValueError('Not a QR Bridge enrollment link')
    raw = parsed.fragment
    data = json.loads(base64.urlsafe_b64decode(raw + '=' * (-len(raw) % 4)))
    if not legacy and parsed.hostname != data['host']:
        raise ValueError('Landing page and enrollment hosts differ')
    if data['v'] != 1 or data['expires'] <= time.time():
        raise ValueError('Expired or unsupported enrollment')
    if ipaddress.ip_address(data['host']) not in ipaddress.ip_network('100.64.0.0/10'):
        raise ValueError('Expected a Tailscale IPv4 address')
    if not isinstance(data['port'], int) or not 1024 <= data['port'] <= 65535:
        raise ValueError('Invalid port')
    if not re.fullmatch('[a-f0-9]{64}', data['pin']) or not re.fullmatch('[A-Za-z0-9_-]{43}', data['token']):
        raise ValueError('Invalid pin or token')
    return data


def enroll(uri):
    data = parse_uri(uri)
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True)
    ROOT.chmod(0o700)
    identity = ROOT / 'id_ed25519'
    if not identity.exists():
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(identity)], check=True)
    identity.chmod(0o600)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE  # Exact DER certificate pin below replaces CA validation.
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    connection = HTTPSConnection(data['host'], data['port'], context=context, timeout=15)
    try:
        connection.connect()
        if hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest() != data['pin']:
            raise ValueError('Certificate pin mismatch; no credential was sent')
        body = json.dumps({'token': data['token'], 'key': identity.with_suffix('.pub').read_text().strip()})
        connection.request('POST', '/enroll', body, {'Content-Type': 'application/json'})
        response = connection.getresponse()
        if response.status != 200:
            raise ValueError(f'Enrollment rejected ({response.status})')
        result = json.loads(response.read(4096))
    finally:
        connection.close()
    if result['host'] != data['host'] or not re.fullmatch('[a-zA-Z0-9_.-]+', result['user']):
        raise ValueError('Invalid SSH destination')
    if not isinstance(result['port'], int) or not 1024 <= result['port'] <= 65535:
        raise ValueError('Invalid SSH port')
    if not re.fullmatch(r'ssh-ed25519 [A-Za-z0-9+/]+={0,2}', result['hostkey']):
        raise ValueError('Invalid host public key')
    known = ROOT / 'known_hosts'
    known.write_text(f"[{result['host']}]:{result['port']} {result['hostkey']}\n")
    config = ROOT / 'config'
    config.write_text(f'''Host windows
    HostName {result['host']}
    Port {result['port']}
    User {result['user']}
    IdentityFile {identity}
    UserKnownHostsFile {known}
    StrictHostKeyChecking yes
    IdentitiesOnly yes
    PasswordAuthentication no
    BatchMode yes
    ConnectTimeout 8
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPersist 600
    ControlPath {control_path(result)}
''')
    for path in (config, known):
        path.chmod(0o600)
    print('Enrolled. Open your terminal with: windows')
    subprocess.run(['ssh', '-F', str(config), 'windows', "Write-Output 'QRBRIDGE_ANDROID_OK'; whoami"], check=True)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: client.py ENROLLMENT_URI')
    enroll(sys.argv[1])
