#!/usr/bin/env python3
"""
Reverse proxy that forwards requests to Anthropic API and captures rate limit headers.
Handles streaming responses properly for Claude Code compatibility.
"""
import http.server
import http.client
import json
import os
import sys
import time
import ssl
import socket
import threading

HOME = os.path.expanduser("~")
CACHE_FILE = os.path.join(HOME, ".claude", "ratelimit_cache.json")
API_HOST = "api.anthropic.com"
API_PORT = 443


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def _proxy(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length else None

        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(API_HOST, API_PORT, context=ctx, timeout=30)

        # Build headers
        headers = {}
        for key, val in self.headers.items():
            if key.lower() not in ('host', 'transfer-encoding'):
                headers[key] = val
        headers['Host'] = API_HOST

        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()

            # Log ALL response headers for debugging
            all_headers = dict(resp.getheaders())
            try:
                with open(os.path.join(HOME, ".claude", "proxy_debug.json"), "w") as f:
                    json.dump({"status": resp.status, "headers": all_headers, "path": self.path}, f, indent=2)
            except Exception:
                pass

            # Capture rate limit headers
            rl_data = {}
            for hdr_name, hdr_val in resp.getheaders():
                if "ratelimit" in hdr_name.lower():
                    key = hdr_name.replace("anthropic-ratelimit-unified-", "")
                    rl_data[key] = hdr_val.strip()

            if rl_data:
                cache = {
                    "timestamp": time.time(),
                    "5h_util": float(rl_data.get("5h-utilization", 0)),
                    "5h_reset": int(float(rl_data.get("5h-reset", 0))),
                    "5h_status": rl_data.get("5h-status", "unknown"),
                    "7d_util": float(rl_data.get("7d-utilization", 0)),
                    "7d_reset": int(float(rl_data.get("7d-reset", 0))),
                    "7d_status": rl_data.get("7d-status", "unknown"),
                }
                try:
                    with open(CACHE_FILE, "w") as f:
                        json.dump(cache, f)
                except Exception:
                    pass

            # Send response back - read all at once and forward
            resp_body = resp.read()

            self.send_response(resp.status)
            for hdr_name, hdr_val in resp.getheaders():
                if hdr_name.lower() not in ('transfer-encoding', 'connection', 'content-length'):
                    self.send_header(hdr_name, hdr_val)
            self.send_header('Content-Length', str(len(resp_body)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(resp_body)

        except Exception as e:
            try:
                err_msg = json.dumps({"type": "error", "error": {"type": "proxy_error", "message": str(e)}}).encode()
                self.send_response(502)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(err_msg)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(err_msg)
            except Exception:
                pass
        finally:
            conn.close()

    def do_POST(self):
        self._proxy()

    def do_GET(self):
        self._proxy()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Content-Length', '0')
        self.send_header('Connection', 'close')
        self.end_headers()


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]

    server = http.server.HTTPServer(('127.0.0.1', port), ProxyHandler, bind_and_activate=False)
    server.socket = sock
    server.server_activate()
    server.timeout = 5

    # Print port for caller
    print(port, flush=True)

    # Serve for max 60 seconds
    deadline = time.time() + 60
    while time.time() < deadline:
        server.handle_request()

    server.server_close()


if __name__ == "__main__":
    main()
