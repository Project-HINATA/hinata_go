#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_check_dir=$(mktemp -d)
trap 'kill "$cookie_server_pid" 2>/dev/null || true; wait "$cookie_server_pid" 2>/dev/null || true; rm -rf "$prism_check_dir"' EXIT
# Real HTTP transport exercises system cookie handling, which URLProtocol mocks bypass.
python3 - "$prism_check_dir/port" <<'PY_SERVER' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
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
server = HTTPServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as f: f.write(str(server.server_port))
server.serve_forever()
PY_SERVER
cookie_server_pid=$!
swiftc -parse-as-library ios/PrismClip/InvocationParser.swift ios/PrismClip/Models.swift ios/PrismClip/PrismAPI.swift ios/PrismClip/MachineLoginViewModel.swift test/native/prism_visit_check.swift -o "$prism_check_dir/prism-visit-check"
PRISM_COOKIE_TEST_PORT="$(cat "$prism_check_dir/port")" "$prism_check_dir/prism-visit-check"
