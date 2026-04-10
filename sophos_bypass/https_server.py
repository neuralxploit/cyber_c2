#!/usr/bin/env python3
"""
HTTPS Payload Server - Serves payloads over TLS
Replaces: python3 -m http.server 9000
"""

import ssl
import http.server
import os
import sys

PORT = 9000
CERTS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "certs")

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler with minimal logging"""
    
    def log_message(self, format, *args):
        print(f"[HTTPS:{PORT}] {args[0]}")
    
    def end_headers(self):
        # Add security headers
        self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()

def main():
    cert_file = os.path.join(CERTS_DIR, "server.crt")
    key_file = os.path.join(CERTS_DIR, "server.key")
    
    if not os.path.exists(cert_file) or not os.path.exists(key_file):
        print(f"❌ ERROR: SSL certificates not found!")
        print(f"   Required: {cert_file}")
        print(f"            {key_file}")
        sys.exit(1)
    
    # Create SSL context
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(certfile=cert_file, keyfile=key_file)
    
    # Create server
    server = http.server.HTTPServer(('0.0.0.0', PORT), QuietHandler)
    server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
    
    print(f"🔒 HTTPS Payload Server running on https://0.0.0.0:{PORT}")
    print(f"   Serving: {os.getcwd()}")
    print(f"   Cert: {cert_file}")
    print()
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped")
        server.shutdown()

if __name__ == "__main__":
    main()
