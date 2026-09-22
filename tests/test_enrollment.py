import concurrent.futures
import importlib.util
import time
import unittest
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from qrbridge import Enrollment, encode_payload, decode_payload, validate_key

spec = importlib.util.spec_from_file_location('android_client', Path(__file__).parents[1] / 'android/client.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


def key():
    return Ed25519PrivateKey.generate().public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH).decode()


class EnrollmentTests(unittest.TestCase):
    def setUp(self):
        self.records = []
        self.enrollment = Enrollment('a' * 43, time.time() + 60, self.records.append, {'ok': True})
        self.payload = dict(v=1, host='100.90.80.70', port=8443, token='a'*43, pin='b'*64, expires=int(time.time())+60)

    def test_roundtrip(self):
        uri = encode_payload(self.payload)
        self.assertEqual(decode_payload(uri), self.payload)
        self.assertEqual(client.parse_uri(uri), self.payload)

    def test_key_validation(self):
        valid = key()
        self.assertEqual(validate_key(valid + ' comment'), valid)
        for value in ['ssh-ed25519 invalid', valid+'\ncommand=x', 'ssh-rsa AAAA', 'command="cmd" '+valid]:
            with self.assertRaises(ValueError):
                validate_key(value)

    def test_wrong_token(self):
        with self.assertRaises(PermissionError):
            self.enrollment.claim('wrong', key())
        self.assertEqual(self.records, [])

    def test_expiry(self):
        self.enrollment.expires = time.time()-1
        with self.assertRaises(PermissionError):
            self.enrollment.claim('a'*43, key())

    def test_single_use_idempotent_retry(self):
        first = key()
        self.enrollment.claim('a'*43, first)
        self.enrollment.claim('a'*43, first)
        self.assertEqual(self.records, [first])
        with self.assertRaises(PermissionError):
            self.enrollment.claim('a'*43, key())

    def test_concurrent_claim(self):
        def claim(candidate):
            try:
                self.enrollment.claim('a'*43, candidate)
                return True
            except PermissionError:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(claim, [key() for _ in range(8)]))
        self.assertEqual(sum(results), 1)
        self.assertEqual(len(self.records), 1)

    def test_failed_registration_can_retry(self):
        def fail(_):
            raise OSError('disk full')
        self.enrollment.register = fail
        with self.assertRaises(OSError):
            self.enrollment.claim('a'*43, key())
        self.assertIsNone(self.enrollment.accepted)

    def test_payload_rejects_injection_and_public_addresses(self):
        for field, value in [('host','8.8.8.8'), ('host','100.1.2.3\nProxyCommand evil'), ('port',22), ('expires',0), ('v',2), ('pin','x'*64)]:
            payload = dict(self.payload, **{field:value})
            with self.assertRaises(ValueError):
                client.parse_uri(encode_payload(payload))


if __name__ == '__main__':
    unittest.main()
