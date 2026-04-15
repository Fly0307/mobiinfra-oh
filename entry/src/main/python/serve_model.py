#!/usr/bin/env python3
"""Simple HTTP server for model files with a /api/files JSON endpoint."""
import os
import json
from http.server import HTTPServer, SimpleHTTPRequestHandler


class ModelHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/files':
            files = []
            for name in sorted(os.listdir('.')):
                if os.path.isfile(name):
                    files.append({'name': name, 'size': os.path.getsize(name)})
            data = json.dumps(files).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(data)
        else:
            super().do_GET()

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()


if __name__ == '__main__':
    port = 9123
    print(f'Serving model files on 0.0.0.0:{port}')
    print(f'File list API: http://0.0.0.0:{port}/api/files')
    print('Files:')
    total = 0
    for f in sorted(os.listdir('.')):
        if os.path.isfile(f) and f != 'serve_model.py':
            s = os.path.getsize(f)
            total += s
            if s >= 1073741824:
                print(f'  {f}: {s/1073741824:.2f} GB')
            else:
                print(f'  {f}: {s/1048576:.1f} MB')
    print(f'Total: {total/1073741824:.2f} GB')
    HTTPServer(('0.0.0.0', port), ModelHandler).serve_forever()
