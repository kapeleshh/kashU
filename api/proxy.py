"""Vercel serverless CORS proxy for the KashU web app.

Same contract as the local dev proxy (proxy_server.py):

    GET /api/proxy?url=<url-encoded absolute https URL>

Browsers block direct calls to the price/forex APIs, so the web build
routes every request through this same-origin function. Only the
whitelisted API hosts are reachable, and every redirect hop is
re-validated so an open redirect on a whitelisted host cannot escape
the allowlist.

Responses are cached at Vercel's edge per upstream host (see
_cache_ttl), which both speeds the app up and shields the free-tier
upstream APIs from repeated identical requests. Large bodies (the
~37k-scheme MFAPI list is several MB of JSON) are gzipped to stay well
under the function response-size cap.

Stdlib only — no requirements.txt needed.
"""

import gzip
import json
import posixpath
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

# Per-host allowlist of the path prefixes the app actually calls. Anything
# else on these hosts is refused, so the function can't be abused as a
# general relay to drain the free APIs' rate limits.
ALLOWED_HOSTS = {
    'query1.finance.yahoo.com': ('/v8/finance/chart', '/v1/finance/search'),
    'query2.finance.yahoo.com': ('/v8/finance/chart', '/v1/finance/search'),
    'open.er-api.com': ('/v6/latest',),              # forex rates
    'api.mfapi.in': ('/mf',),                        # Indian mutual fund NAVs
    'api.coingecko.com': ('/api/v3',),               # crypto prices + search
    'min-api.cryptocompare.com': ('/data',),         # crypto fallback
    'stooq.com': ('/q/l',),                          # stock/gold fallback
}

# Refuse upstream bodies beyond this size (the largest legitimate response,
# MFAPI's full scheme list, is ~5.7MB).
_MAX_BODY_BYTES = 10_000_000

# Yahoo/Stooq reject requests without a browser User-Agent. Ask upstream
# for identity encoding so the gzip decision below sees the raw size.
_UPSTREAM_HEADERS = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json,text/csv;q=0.9,*/*;q=0.8',
    'Accept-Encoding': 'identity',
}

_UPSTREAM_TIMEOUT_S = 15
_GZIP_THRESHOLD_BYTES = 50_000


def _validation_error(url):
    """Return why `url` may not be proxied, or None if it is allowed."""
    try:
        parsed = urllib.parse.urlparse(url)
        port = parsed.port  # raises ValueError on a malformed port
    except ValueError:
        return 'Malformed url'
    if parsed.scheme != 'https':
        return 'Only https targets are allowed'
    if parsed.username or parsed.password:
        return 'Credentials in url are not allowed'
    if port not in (None, 443):
        return 'Non-default ports are not allowed'
    prefixes = ALLOWED_HOSTS.get(parsed.hostname)
    if prefixes is None:
        return f'Host not allowed: {parsed.hostname}'
    # Normalise before matching so encoded "../" segments can't sidestep
    # the prefix check (upstream servers resolve them after decoding).
    path = posixpath.normpath(urllib.parse.unquote(parsed.path or '/'))
    if not any(path == p or path.startswith(p + '/') for p in prefixes):
        return f'Path not allowed: {parsed.path}'
    return None


class _ValidatingRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Re-validate every redirect hop. Yahoo legitimately bounces between
    query1 and query2 (both whitelisted), so redirects stay enabled but
    may never leave the allowlist."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if _validation_error(newurl) is not None:
            raise urllib.error.HTTPError(
                req.full_url, 403,
                f'Redirect target not allowed: {newurl}', headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_ValidatingRedirectHandler())


def _cache_ttl(url):
    """Edge-cache TTL in seconds, per upstream host/path."""
    parsed = urllib.parse.urlparse(url)
    host, path = parsed.hostname, parsed.path
    if host == 'open.er-api.com':
        return 3600  # forex rates update ~daily
    if host in ('query1.finance.yahoo.com', 'query2.finance.yahoo.com'):
        # Symbol search results are stable; quotes move intraday.
        return 3600 if path.startswith('/v1/finance/search') else 300
    if host == 'api.mfapi.in':
        # Full scheme list (client also caches it 6h) vs a single NAV
        # (updates once daily).
        return 21600 if path.rstrip('/') == '/mf' else 3600
    if host == 'stooq.com':
        return 900
    return 300  # coingecko, cryptocompare


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Browsers label cross-site subresource requests via Sec-Fetch-Site;
        # refuse those so other websites can't embed this proxy. Requests
        # without the header (curl, old browsers) are still subject to the
        # host/path allowlist above.
        fetch_site = self.headers.get('Sec-Fetch-Site', '')
        if fetch_site not in ('', 'same-origin', 'none'):
            self._send_json_error(403, 'Cross-site requests are not allowed')
            return

        query = urllib.parse.urlparse(self.path).query
        target_url = urllib.parse.parse_qs(query).get('url', [None])[0]

        if not target_url:
            self._send_json_error(400, 'Missing url parameter')
            return
        problem = _validation_error(target_url)
        if problem is not None:
            self._send_json_error(403, problem)
            return

        req = urllib.request.Request(target_url, headers=_UPSTREAM_HEADERS)
        try:
            with _OPENER.open(req, timeout=_UPSTREAM_TIMEOUT_S) as response:
                status = response.status
                body = response.read(_MAX_BODY_BYTES + 1)
                content_type = response.headers.get(
                    'Content-Type', 'application/json')
        except urllib.error.HTTPError as e:
            # Pass the real upstream status through (the app's services
            # treat non-200 as a miss and fall back), but never cache it.
            self._send_json_error(e.code, str(e))
            return
        except Exception as e:  # URLError, timeout, ...
            self._send_json_error(502, f'Upstream request failed: {e}')
            return

        if len(body) > _MAX_BODY_BYTES:
            self._send_json_error(502, 'Upstream response too large')
            return

        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header(
            'Cache-Control',
            f'public, s-maxage={_cache_ttl(target_url)}, '
            'stale-while-revalidate=60, max-age=0')
        if (len(body) > _GZIP_THRESHOLD_BYTES
                and 'gzip' in self.headers.get('Accept-Encoding', '')):
            body = gzip.compress(body, compresslevel=6)
            self.send_header('Content-Encoding', 'gzip')
        self.send_header('Vary', 'Accept-Encoding')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json_error(self, code, message):
        body = json.dumps({'error': message}).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
