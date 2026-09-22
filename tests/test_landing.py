import http.client
import threading
import time
import unittest
from urllib.parse import urlsplit
from qrbridge import encode_payload, decode_payload
from landing import make_landing_handler
from http.server import ThreadingHTTPServer


class BrowserQrTests(unittest.TestCase):
    def setUp(self):
        self.data = dict(v=1, host='100.90.80.70', port=8443, pin='b'*64,
                         token='a'*43, expires=int(time.time())+300)

    def test_qr_is_a_real_tailnet_browser_address(self):
        url = urlsplit(encode_payload(self.data))
        self.assertEqual(url.scheme, 'http')
        self.assertEqual(url.hostname, self.data['host'])
        self.assertEqual(url.port, 8080)
        self.assertEqual(url.path, '/enroll')
        self.assertEqual(decode_payload(url.geturl()), self.data)
        self.assertNotIn(self.data['token'], url.path + url.query)

    def test_url_host_cannot_disagree_with_payload(self):
        uri = encode_payload(self.data).replace('100.90.80.70', '100.90.80.71')
        with self.assertRaises(ValueError):
            decode_payload(uri)

    def test_http_page_works_without_enrollment_credentials(self):
        with ThreadingHTTPServer(('127.0.0.1', 0), make_landing_handler(time.time()+60)) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
                connection.request('GET', '/enroll')
                response = connection.getresponse()
                body = response.read().decode()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.getheader('Cache-Control'), 'no-store')
                self.assertIn('Copy pairing command', body)
                self.assertIn('QRBRIDGE_ANDROID_OK', body)
                self.assertNotIn(self.data['token'], body)
                self.assertIn("script-src 'sha256-", response.getheader('Content-Security-Policy'))
                connection.close()
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
                connection.request('POST', '/enroll', '{"token":"not-accepted-here"}')
                response = connection.getresponse()
                self.assertEqual(response.status, 405)
                response.read()
                connection.close()
            finally:
                server.shutdown()
                worker.join(timeout=5)


if __name__ == '__main__':
    unittest.main()
