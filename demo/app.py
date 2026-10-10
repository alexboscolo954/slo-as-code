"""Demo "checkout" service with a fault knob, plus a load generator.

    python app.py serve                      # :8080, /api/checkout, /metrics, POST /fault
    python app.py load http://app:8080 50    # 50 requests/second, forever

POST /fault?error_rate=0.05&slow_rate=0.2 changes behavior at runtime: 5% of
requests return 500, 20% take longer than the 250ms latency SLO.
"""

import random
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

REQUESTS = Counter("http_requests", "Checkout API requests", ["code"])
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Checkout API latency",
    buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.5),  # 0.25 is the latency SLO threshold
)
fault = {"error_rate": 0.0, "slow_rate": 0.0}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args: object) -> None:  # keep container logs quiet
        pass

    def reply(self, code: int, body: bytes, ctype: str = "text/plain") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/metrics":
            self.reply(200, generate_latest(), CONTENT_TYPE_LATEST)
        elif path == "/api/checkout":
            start = time.monotonic()
            slow = random.random() < fault["slow_rate"]  # noqa: S311 - not crypto
            time.sleep(random.uniform(0.3, 0.4) if slow else random.uniform(0.005, 0.03))  # noqa: S311
            code = 500 if random.random() < fault["error_rate"] else 200  # noqa: S311
            LATENCY.observe(time.monotonic() - start)
            REQUESTS.labels(str(code)).inc()
            self.reply(code, b"ok" if code == 200 else b"internal error")
        else:
            self.reply(404, b"not found")

    def do_POST(self) -> None:
        url = urlparse(self.path)
        if url.path != "/fault":
            return self.reply(404, b"not found")
        for key, values in parse_qs(url.query).items():
            if key in fault:
                fault[key] = min(1.0, max(0.0, float(values[0])))
        return self.reply(200, f"{fault}\n".encode())


def load(base: str, rps: float) -> None:
    def hit() -> None:
        try:
            urllib.request.urlopen(f"{base}/api/checkout", timeout=5).read()  # noqa: S310
        except (urllib.error.URLError, TimeoutError):
            pass  # 500s raise HTTPError (a URLError); the service counts them

    while True:
        threading.Thread(target=hit, daemon=True).start()
        time.sleep(1 / rps)


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()  # noqa: S104
    elif sys.argv[1] == "load":
        load(sys.argv[2], float(sys.argv[3]))
