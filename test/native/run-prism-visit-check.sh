#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_check_dir=$(mktemp -d)
trap 'kill "$cookie_server_pid" 2>/dev/null || true; wait "$cookie_server_pid" 2>/dev/null || true; rm -rf "$prism_check_dir"' EXIT
# Real HTTP transport exercises system cookie handling, which URLProtocol mocks bypass.
python3 - "$prism_check_dir/port" <<'PY_SERVER' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import TCPServer
class LoopbackServer(HTTPServer):
    def server_bind(self):
        # HTTPServer otherwise resolves a hostname for a fixture that only uses an IP.
        TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self): self.do_GET()
    def do_GET(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        if self.path.endswith('/exchange'):
            self.send_header('Set-Cookie', 'prism_session_test=logged-in; Path=/; Max-Age=3600; HttpOnly')
        if self.path.endswith('/logout'):
            self.send_header('Set-Cookie', 'prism_session_test=; Path=/; Max-Age=0; HttpOnly')
        self.end_headers()
        data = {"ok": True}
        if self.path.endswith('/me'):
            data['user'] = {'id':'persisted','username':'test','displayName':'Test'} if 'prism_session_test=logged-in' in self.headers.get('Cookie', '') else None
        self.wfile.write(json.dumps({'data':data}).encode())
server = LoopbackServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as f: f.write(str(server.server_port))
server.serve_forever()
PY_SERVER
cookie_server_pid=$!
attempt=0
while [ ! -s "$prism_check_dir/port" ]; do
  kill -0 "$cookie_server_pid" 2>/dev/null || { echo 'Cookie fixture server exited before startup' >&2; exit 1; }
  attempt=$((attempt + 1))
  [ "$attempt" -lt 100 ] || { echo 'Cookie fixture server did not publish its port' >&2; exit 1; }
  sleep 0.1
done
swiftc -parse-as-library ios/PrismClip/InvocationParser.swift ios/PrismClip/InvocationRouter.swift ios/PrismClip/Models.swift ios/PrismClip/PrismAPI.swift ios/PrismClip/MachineLoginViewModel.swift test/native/prism_visit_fixtures.swift test/native/prism_visit_check.swift -o "$prism_check_dir/prism-visit-check"
PRISM_COOKIE_TEST_PORT="$(cat "$prism_check_dir/port")" "$prism_check_dir/prism-visit-check"
