#!/usr/bin/env python3
"""
Simple CORS proxy server for kashU Flutter web app.
Proxies requests to Yahoo Finance and open.er-api.com to bypass browser CORS restrictions.

Usage: python3 proxy_server.py
Then open http://localhost:8080 in your browser.
"""

import http.server
import urllib.request
import urllib.parse
import os
import json
import sys

WEB_BUILD_DIR = os.path.join(os.path.dirname(__file__), 'build', 'web')
PORT = 8080

ALLOWED_PROXY_HOSTS = [
    'query1.finance.yahoo.com',
    'query2.finance.yahoo.com',
    'open.er-api.com',
    'api.mfapi.in',                  # Indian mutual fund NAV data
    'api.coingecko.com',             # Cryptocurrency prices and search
    'min-api.cryptocompare.com',     # Crypto fallback provider
    'stooq.com',                     # Stock/gold fallback provider
]

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_BUILD_DIR, **kwargs)

    def do_GET(self):
        # Handle proxy requests: /proxy?url=https://...
        if self.path.startswith('/proxy?'):
            self._handle_proxy()
            return
        # Serve static Flutter web files
        super().do_GET()

    def _handle_proxy(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        target_url = params.get('url', [None])[0]

        if not target_url:
            self._send_error(400, 'Missing url parameter')
            return

        # Security: only allow whitelisted hosts
        target_parsed = urllib.parse.urlparse(target_url)
        if target_parsed.hostname not in ALLOWED_PROXY_HOSTS:
            self._send_error(403, f'Host not allowed: {target_parsed.hostname}')
            return

        try:
            req = urllib.request.Request(
                target_url,
                headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                    'Accept': 'application/json',
                }
            )
            with urllib.request.urlopen(req, timeout=15) as response:
                data = response.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', '*')
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self._send_error(e.code, str(e))
        except Exception as e:
            self._send_error(500, str(e))

    def _send_error(self, code, message):
        body = json.dumps({'error': message}).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def log_message(self, format, *args):
        # Only log proxy requests, suppress static file noise
        if '/proxy?' in (args[0] if args else ''):
            print(f'[PROXY] {args[0]} -> {args[1]}')

if __name__ == '__main__':
    print(f'kashU proxy server running at http://localhost:{PORT}')
    print(f'Serving Flutter web from: {WEB_BUILD_DIR}')
    print(f'Open http://localhost:{PORT} in Edge')
    print('Press Ctrl+C to stop\n')
    
    with http.server.HTTPServer(('', PORT), ProxyHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print('\nServer stopped.')
