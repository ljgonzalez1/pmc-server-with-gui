#!/usr/bin/env python3
import os
import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

# Allowed commands; an empty POST will invoke entrypoint with no args
ALLOWED = {
    "start",
    "stop",
    "restart",
    "update-mc",
    "update-lgsm",
    "update",
    "console"
}

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        # Read JSON body (if any)
        length = int(self.headers.get("Content-Length", 0))
        if length:
            raw = self.rfile.read(length)
            try:
                data = json.loads(raw.decode())
            except json.JSONDecodeError:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'{"error":"invalid json"}')
                return
            cmd = data.get("cmd", "")
        else:
            cmd = ""

        # Decide whether to invoke entrypoint
        if cmd in ALLOWED or cmd == "":
            # Spawn entrypoint.sh with or without argument
            args = ["/usr/local/bin/entrypoint.sh"]
            if cmd:
                args.append(cmd)
            subprocess.Popen(args)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            # Unknown command → no action
            self.send_response(204)
            self.end_headers()

if __name__ == "__main__":
    port = int(os.environ.get("API_PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()
