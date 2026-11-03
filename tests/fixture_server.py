"""Local-only browser checks: real cookie sharing, isolation and beforeunload."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import html

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = urlparse(self.path)
        self.send_response(200)
        if route.path == "/set":
            self.send_header("Set-Cookie", "aelo_test=shared-profile; Path=/; SameSite=Lax")
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        page = """<!doctype html><html><meta charset="utf-8"><title>Aelo browser check</title>
        <style>body{font:18px -apple-system,sans-serif;padding:55px;color:#30364c;background:#f9f9fd}h1{font-size:36px}a{display:block;margin:25px 0}input{padding:12px;font-size:18px}</style>
        <h1>Browser profile check</h1><p id="cookie"></p>
        <script>document.getElementById('cookie').textContent='Cookie: '+(document.cookie||'(empty)');</script>
        <a href="/set">Set a test cookie</a><a href="/">Read test cookie</a>
        <p>Type here to test unsaved-page protection:</p><input aria-label="Unsaved draft" oninput="window.onbeforeunload=()=>true">
        </html>"""
        self.wfile.write(page.encode())

if __name__ == "__main__":
    print("Aelo fixture: http://127.0.0.1:8765", flush=True)
    # Chromium preconnects idle sockets; a single-threaded server would block
    # other Profiles behind an unused connection and give a false hang result.
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
