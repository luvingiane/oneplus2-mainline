#!/usr/bin/env python3
# Live screen of the phone over HTTP (auto-refreshing page, grim snapshots).
# Run on the phone (as root, via systemd-run):
#   systemd-run --unit=op2stream env XDG_RUNTIME_DIR=/run/user/1000 python3 /tmp/screenstream.py 8080
# then from the PC:  http://<host>:8081/  (host forwards 8081 -> phone 8080)
import http.server, subprocess, sys, threading, time, os
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
PAGE = b'<html><body style="margin:0;background:#000"><img src="/shot.png" style="width:100%%"></body><script>setInterval(()=>{document.querySelector("img").src="/shot.png?t="+Date.now()},700)</script></html>'
if os.geteuid() == 1000:
    GRIM = ['grim','-']
else:
    GRIM = ['runuser','-u','zerone','--','env','XDG_RUNTIME_DIR=/run/user/1000','WAYLAND_DISPLAY=wayland-0','grim','-']
lock = threading.Lock()
cache = {'png': b''}
def grabber():
    while True:
        try:
            p = subprocess.run(GRIM, capture_output=True, timeout=120)
            if p.stdout:
                with lock: cache['png'] = p.stdout
        except Exception:
            pass
        time.sleep(0.2)
import threading as t; t.Thread(target=grabber, daemon=True).start()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path.startswith('/shot'):
                with lock: data = cache['png']
                if not data: raise ValueError('no frame yet')
                self.send_response(200); self.send_header('Content-Type','image/png'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
            else:
                self.send_response(200); self.send_header('Content-Type','text/html'); self.send_header('Content-Length',str(len(PAGE))); self.end_headers(); self.wfile.write(PAGE)
        except Exception:
            try: self.send_error(500)
            except Exception: pass
    def log_message(self, *a): pass
class S(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def handle_error(self, req, addr): pass
S(('0.0.0.0', PORT), H).serve_forever()
