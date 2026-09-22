"""Serve synthetic, non-authorizing QR data for browser testing. Never enrolls a key."""
import argparse
from http.server import ThreadingHTTPServer
import time
from landing import make_landing_handler
from qrbridge import encode_payload

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True)
    args = parser.parse_args()
    expires = int(time.time()) + 600
    payload = dict(v=1, host=args.host, port=8443, pin='b'*64, token='a'*43, expires=expires)
    with ThreadingHTTPServer((args.host, 8080), make_landing_handler(expires)) as server:
        server.timeout = 1
        print(encode_payload(payload), flush=True)
        while time.time() < expires:
            server.handle_request()
