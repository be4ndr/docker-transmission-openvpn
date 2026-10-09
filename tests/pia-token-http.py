#!/usr/bin/env python3
"""Exercise token requests with real curl and a local HTTP fixture; no PIA account."""

import http.server
import json
from pathlib import Path
import subprocess
import threading
import unittest
import urllib.parse


SCRIPT = (Path(__file__).resolve().parents[1] / "openvpn/pia/update-port.sh").read_text()
# Run the production helpers without container startup or the PF loop.
HELPERS = SCRIPT[SCRIPT.index("curl_quote() {"):SCRIPT.index("transmission_credentials_file=")]
TOKEN_HELPER = SCRIPT[SCRIPT.index("get_auth_token() {"):SCRIPT.index("get_sig() {")]


class TokenHTTPTests(unittest.TestCase):
    def request(self, responses, username="example-user", password="example-password"):
        received = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                received.append((self.path, dict(self.headers), body))
                status, response = responses[min(len(received) - 1, len(responses) - 1)]
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                if status == 302:
                    self.send_header("Location", "/redirected")
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

            def log_message(self, *_args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            helper = TOKEN_HELPER.replace(
                "https://www.privateinternetaccess.com/api/client/v2/token",
                f"http://127.0.0.1:{server.server_port}/api/client/v2/token",
            ).replace("--retry-delay 15", "--retry-delay 0")
            # Only helper code is in argv; Bash reads credentials from stdin.
            script = "set +x\n" + HELPERS + helper + "\n"
            script += "read -r user\nread -r pass\n"
            script += "if get_auth_token; then printf 'ok'; else printf '%s' \"$token_error\"; exit 1; fi\n"
            result = subprocess.run(["bash", "-c", script], input=username + "\n" + password + "\n",
                                    text=True, capture_output=True, timeout=10)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        self.assertEqual(result.stderr, "")
        return result, received

    def test_form_encoding_and_no_basic_auth(self):
        username = 'example-user+&%=:@"\\'
        password = 'example-password+&%=:@"\\ ; space ü'
        result, received = self.request([(200, {"token": "example-token"})], username, password)
        self.assertEqual((result.returncode, result.stdout), (0, "ok"))
        self.assertEqual(len(received), 1)
        path, headers, body = received[0]
        self.assertEqual(path, "/api/client/v2/token")
        self.assertEqual(headers["Content-Type"], "application/x-www-form-urlencoded")
        self.assertNotIn("Authorization", headers)
        self.assertEqual(urllib.parse.parse_qs(body.decode()), {"username": [username], "password": [password]})

    def test_transient_http_failure_is_retried(self):
        result, received = self.request([(503, {}), (200, {"token": "example-token"})])
        self.assertEqual((result.returncode, result.stdout, len(received)), (0, "ok", 2))

    def test_authentication_failures_are_not_retried_or_logged(self):
        for status in (401, 403):
            with self.subTest(status=status):
                result, received = self.request([(status, {"token": "example-token", "echo": "example-password"})])
                self.assertEqual((result.returncode, result.stdout, len(received)),
                                 (1, "token authentication failed", 1))

    def test_redirect_does_not_forward_credentials(self):
        result, received = self.request([(302, {"token": "example-token"})])
        self.assertEqual((result.returncode, result.stdout, len(received)), (1, "token request failed", 1))

    def test_empty_token_is_rejected(self):
        result, _ = self.request([(200, {"token": None})])
        self.assertEqual((result.returncode, result.stdout), (1, "token response invalid"))


if __name__ == "__main__":
    unittest.main()
