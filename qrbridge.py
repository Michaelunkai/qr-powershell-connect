"""Single-use, certificate-pinned enrollment. No private SSH keys cross the wire."""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import hmac
import http.server
import ipaddress
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import threading
import time
from urllib.parse import urlsplit

import segno
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.x509.oid import NameOID
from keylock import key_lock
from landing import make_landing_handler

PREFIX = 'https://qrbridge.invalid/enroll#'


def print_client_steps():
    print('\nNEXT STEPS ON YOUR ANDROID PHONE:')
    print('1. Keep Tailscale connected to the same account as this Windows PC.')
    print('2. Install the signed PowerShell Connect APK from the project release.')
    print('3. Open PowerShell Connect and use its built-in Scan connection QR button.')
    print('4. Scan this QR inside the app. Allow its notification permission.')
    print('5. Wait for your Windows PowerShell prompt. Future launches use the saved pairing.')
    print('6. Open the PowerShell icon whenever needed; active sessions continue in the background.')
    print('Legacy Termux option: open the QR in your browser, copy its pairing command,')
    print('paste into the installed Termux client, then run: windows --reconnect')
    print('Keep this Windows pairing window open until enrollment succeeds.')
    print('If the QR expires, run Start-Pairing.ps1 again to create another.\n', flush=True)


class PinnedServer(http.server.HTTPServer):
    def get_request(self):
        connection, address = self.socket.accept()
        connection.settimeout(5)
        try:
            return self.context.wrap_socket(connection, server_side=True), address
        except Exception:
            connection.close()
            raise


def validate_key(key: str) -> str:
    parts = key.split()
    if len(parts) < 2 or parts[0] != 'ssh-ed25519' or len(key) > 256 or '\n' in key or '\r' in key:
        raise ValueError('Expected one ED25519 public key')
    clean = ' '.join(parts[:2])
    parsed = serialization.load_ssh_public_key(clean.encode('ascii'))
    if not isinstance(parsed, ed25519.Ed25519PublicKey):
        raise ValueError('Wrong key type')
    return clean


def encode_payload(data: dict) -> str:
    return f'http://{data["host"]}:8080/enroll#' + base64.urlsafe_b64encode(json.dumps(data, separators=(',', ':')).encode()).decode().rstrip('=')


def decode_payload(uri: str) -> dict:
    parsed = urlsplit(uri)
    legacy = uri.startswith(PREFIX)
    if len(uri) > 4096 or not (legacy or (parsed.scheme == 'http' and parsed.port == 8080 and parsed.path == '/enroll' and not parsed.username and not parsed.password and not parsed.query)):
        raise ValueError('Invalid enrollment URI')
    raw = urlsplit(uri).fragment
    data = json.loads(base64.urlsafe_b64decode(raw + '=' * (-len(raw) % 4)))
    if not legacy and parsed.hostname != data['host']:
        raise ValueError('Landing page and enrollment hosts differ')
    if data['v'] != 1 or int(data['expires']) <= time.time():
        raise ValueError('Unsupported or expired enrollment')
    if ipaddress.ip_address(data['host']) not in ipaddress.ip_network('100.64.0.0/10'):
        raise ValueError('Enrollment must use a Tailscale IPv4 address')
    if not 1024 <= data['port'] <= 65535 or len(data['pin']) != 64 or len(data['token']) < 40:
        raise ValueError('Invalid enrollment parameters')
    return data


class Enrollment:
    def __init__(self, token, expires, register, response):
        self.token, self.expires = token, expires
        self.register, self.response = register, response
        self.lock = threading.Lock()
        self.accepted = None

    def claim(self, token, key):
        with self.lock:
            if time.time() >= self.expires or not hmac.compare_digest(str(token), self.token):
                raise PermissionError('Expired or invalid token')
            key = validate_key(key)
            if self.accepted is not None and key != self.accepted:
                raise PermissionError('Token already used')
            if self.accepted is None:
                self.register(key)
                self.accepted = key
            return self.response


def make_certificate(root: Path, host: str):
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'QR Bridge enrollment')])
    now = dt.datetime.now(dt.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - dt.timedelta(minutes=1)).not_valid_after(now + dt.timedelta(hours=1))
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(host))]), False)
            .sign(key, hashes.SHA256()))
    certfile, keyfile = root / 'enrollment-cert.pem', root / 'enrollment-key.pem'
    certfile.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    keyfile.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    return certfile, keyfile, cert.fingerprint(hashes.SHA256()).hex()


def make_handler(enrollment):
    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *args):
            return  # Tokens and submitted keys must never appear in HTTP access logs.

        def do_POST(self):
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if self.path != '/enroll' or not 1 <= size <= 2048:
                    raise ValueError('Invalid request')
                body = json.loads(self.rfile.read(size))
                result = enrollment.claim(body['token'], body['key'])
                payload = json.dumps(result).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except (ValueError, KeyError, PermissionError, TypeError):
                self.send_error(403, 'Enrollment rejected')
            except Exception:
                logging.getLogger('qrbridge').exception('Enrollment operation failed')
                self.send_error(500, 'Enrollment failed; check host state')
    return Handler


def serve(args):
    if os.name != 'nt':
        raise RuntimeError('Enrollment host requires Windows')
    import ctypes
    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise PermissionError('Run enrollment as Administrator')
    root = Path(os.environ['PROGRAMDATA']) / 'QrPowerShellConnect'
    logger = logging.getLogger('qrbridge')
    handler = RotatingFileHandler(root / 'enrollment.log', maxBytes=5*1024*1024, backupCount=1, encoding='utf-8')
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    state = json.loads((root / 'installation.json').read_text(encoding='utf-8-sig'))
    if state['phase'] != 'installed':
        raise RuntimeError('Install the bridge first')
    ts = Path(os.environ['PROGRAMFILES']) / 'Tailscale/tailscale.exe'
    status = json.loads(subprocess.check_output([str(ts), 'status', '--json']))
    if status.get('BackendState') != 'Running':
        raise RuntimeError('Sign into Tailscale first: tailscale up --unattended=true')
    host = next(ip for ip in status['TailscaleIPs'] if ':' not in ip)
    hostkey = validate_key((Path(os.environ['PROGRAMDATA']) / 'ssh/ssh_host_ed25519_key.pub').read_text().strip())
    response = {'host': host, 'port': state['port'], 'user': state['user'], 'hostkey': hostkey}
    expires = int(time.time()) + args.ttl
    certfile, keyfile, pin = make_certificate(root, host)
    token = secrets.token_urlsafe(32)
    payload = dict(v=1, host=host, port=args.port, pin=pin, token=token, expires=expires)
    uri = encode_payload(payload)
    qr = segno.make(uri, error='m')
    auth = root / 'authorized_keys'
    def register(key):
        with key_lock():
            existing = [line.split()[:2] for line in auth.read_text().splitlines()]
            if key.split()[:2] not in existing:
                with auth.open('a', encoding='ascii', newline='\n') as stream:
                    stream.write(key + ' qrbridge-android\n')
                    stream.flush()
                    os.fsync(stream.fileno())
        with (root / 'operations.log').open('a', encoding='utf-8') as log:
            fingerprint = hashlib.sha256(base64.b64decode(key.split()[1])).hexdigest()
            log.write(f'{dt.datetime.now(dt.timezone.utc).isoformat()} enrolled key SHA256(hex):{fingerprint}\n')
        logger.info('Public key enrolled; fingerprint SHA256(hex):%s', fingerprint)
    enrollment = Enrollment(token, expires, register, response)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certfile, keyfile)
    try:
        with PinnedServer((host, args.port), make_handler(enrollment)) as server:
            server.timeout = 1
            server.context = context
            with http.server.ThreadingHTTPServer((host, 8080), make_landing_handler(expires)) as landing:
                worker = threading.Thread(target=landing.serve_forever, daemon=True)
                worker.start()
                try:
                    qr.save(str(root / 'pairing.png'), scale=6)
                    (root / 'pairing.txt').write_text(uri, encoding='utf-8')
                    logger.info('Enrollment and browser landing listeners started with %s second lifetime', args.ttl)
                    print(f'Enrollment QR: {root / "pairing.png"}. Expires in {args.ttl}s. Treat it as an administrator credential.', flush=True)
                    if not args.no_terminal:
                        qr.terminal(compact=True)
                        print_client_steps()
                    while time.time() < expires:
                        server.handle_request()
                finally:
                    landing.shutdown()
                    worker.join(timeout=5)
    finally:
        for path in (keyfile, certfile, root / 'pairing.txt', root / 'pairing.png'):
            path.unlink(missing_ok=True)
        logger.info('Enrollment listener stopped; paired=%s', enrollment.accepted is not None)
        handler.close()
        logger.removeHandler(handler)
    print('Enrollment closed. Paired:', enrollment.accepted is not None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8443, choices=range(1024, 65536), metavar='PORT')
    parser.add_argument('--ttl', type=int, default=300, choices=range(30, 901), metavar='SECONDS')
    parser.add_argument('--no-terminal', action='store_true', help='Generate the protected PNG without rendering a QR into redirected logs')
    parser.add_argument('--show-active', type=Path, help='Display an existing, unexpired enrollment QR and phone instructions')
    args = parser.parse_args()
    if args.show_active:
        uri = args.show_active.read_text(encoding='utf-8')
        if uri.startswith(PREFIX):
            raise ValueError('This is an old .invalid QR. Close the old pairing process and run Start-Pairing.ps1 again.')
        data = decode_payload(uri)
        print('Seconds remaining:', max(0, int(data['expires'] - time.time())))
        segno.make(uri, error='m').terminal(compact=True)
        print_client_steps()
        return
    serve(args)


if __name__ == '__main__':
    main()
