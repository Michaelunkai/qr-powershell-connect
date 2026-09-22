import http.client
import ssl
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from http.server import HTTPServer
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from qrbridge import Enrollment, PinnedServer, encode_payload, make_certificate, make_handler
from test_enrollment import client, key


class TlsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        cert, private, self.pin = make_certificate(self.root, '127.0.0.1')
        self.records = []
        self.state = Enrollment('a'*43, time.time()+60, self.records.append,
                                dict(host='100.90.80.70', port=2222, user='Admin', hostkey=key()))
        self.server = PinnedServer(('127.0.0.1', 0), make_handler(self.state))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, private)
        self.server.context = context
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()
        identity = Ed25519PrivateKey.generate()
        (self.root/'id_ed25519').write_bytes(identity.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()))
        (self.root/'id_ed25519.pub').write_bytes(identity.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH))
        self.payload = dict(v=1, host='100.90.80.70', port=self.server.server_port, pin=self.pin, token='a'*43, expires=int(time.time())+60)
        self.real_connection = http.client.HTTPSConnection

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=3)
        self.temp.cleanup()

    def connection(self, host, port, **kwargs):
        return self.real_connection('127.0.0.1', port, **kwargs)

    def test_real_tls_enrollment_persists_pinned_ssh_config(self):
        with patch.object(client, 'ROOT', self.root), patch.object(client, 'HTTPSConnection', self.connection), patch.object(client.subprocess, 'run') as run:
            client.enroll(encode_payload(self.payload))
        self.assertEqual(len(self.records), 1)
        self.assertIn('StrictHostKeyChecking yes', (self.root/'config').read_text())
        self.assertIn('[100.90.80.70]:2222 ssh-ed25519 ', (self.root/'known_hosts').read_text())
        run.assert_called_once()

    def test_bad_certificate_pin_sends_no_key(self):
        self.payload['pin'] = '0'*64
        with patch.object(client, 'ROOT', self.root), patch.object(client, 'HTTPSConnection', self.connection):
            with self.assertRaisesRegex(ValueError, 'pin mismatch'):
                client.enroll(encode_payload(self.payload))
        self.assertEqual(self.records, [])
        self.assertFalse((self.root/'config').exists())

    def test_invalid_token_over_tls(self):
        self.payload['token'] = 'b'*43
        with patch.object(client, 'ROOT', self.root), patch.object(client, 'HTTPSConnection', self.connection):
            with self.assertRaisesRegex(ValueError, '403'):
                client.enroll(encode_payload(self.payload))
        self.assertEqual(self.records, [])


if __name__ == '__main__':
    unittest.main()
