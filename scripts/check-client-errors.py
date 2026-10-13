"""Verify Godot request error reporting using real local HTTP responses."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import threading


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/v1/guests":
            code, payload = 201, {"access_token": "fixture-only"}
        elif self.path == "/matchmake/joinOrCreate/arena":
            code, payload = 429, {}
        elif self.path == "/v1/login":
            code, payload = {
                "invalid": (422, {"detail": [{"input": "DO_NOT_DISPLAY_PASSWORD"}]}),
                "missing": (401, {}),
                "limited": (429, {}),
                "offline": (503, {}),
                "broken": (200, []),
                "notoken": (200, {}),
            }.get(body.get("username"), (400, {}))
        else:
            code, payload = 404, {}
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server, socket.socket() as closed:
        # Reserve a port without listening: deterministic connection refusal.
        closed.bind(("127.0.0.1", 0))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = os.environ.copy()
        env["SUNI_ERROR_TEST_URL"] = f"http://127.0.0.1:{server.server_port}"
        env["SUNI_ERROR_TEST_UNREACHABLE"] = f"http://127.0.0.1:{closed.getsockname()[1]}"
        try:
            result = subprocess.run(
                [os.environ.get("GODOT", "godot"), "--headless", "--path", "apps/client",
                 "--script", "res://tests/request_errors.gd"],
                cwd=Path(__file__).resolve().parents[1], env=env, timeout=40,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            print(result.stdout)
            if result.returncode or "SCRIPT ERROR" in result.stdout or "GODOT_REQUEST_ERRORS_OK" not in result.stdout:
                raise SystemExit(1)
        finally:
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    main()
