"""
mTLS Configuration for Cyber C2
Mutual TLS authentication for BITS agents
"""

import ssl
import os

CERTS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "certs")

def get_server_ssl_context():
    """
    Create SSL context for server with client certificate verification (mTLS)
    """
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    
    # Load server certificate and key
    ctx.load_cert_chain(
        certfile=os.path.join(CERTS_DIR, "server.crt"),
        keyfile=os.path.join(CERTS_DIR, "server.key")
    )
    
    # Require client certificate (mTLS)
    ctx.verify_mode = ssl.CERT_REQUIRED
    
    # Load CA to verify client certificates
    ctx.load_verify_locations(os.path.join(CERTS_DIR, "ca.crt"))
    
    return ctx


def get_server_ssl_context_optional():
    """
    Create SSL context where client cert is optional
    Used for endpoints that may or may not have client certs
    """
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    
    ctx.load_cert_chain(
        certfile=os.path.join(CERTS_DIR, "server.crt"),
        keyfile=os.path.join(CERTS_DIR, "server.key")
    )
    
    # Client cert optional - we verify if provided
    ctx.verify_mode = ssl.CERT_OPTIONAL
    ctx.load_verify_locations(os.path.join(CERTS_DIR, "ca.crt"))
    
    return ctx


def verify_client_cert(request) -> bool:
    """
    Verify if request has valid client certificate
    Returns True if valid mTLS client cert present
    """
    # In uvicorn with SSL, client cert info is in transport
    try:
        transport = request.scope.get("transport")
        if transport:
            ssl_object = transport.get_extra_info("ssl_object")
            if ssl_object:
                peer_cert = ssl_object.getpeercert()
                if peer_cert:
                    # Check if cert is from our CA (subject contains our O)
                    subject = dict(x[0] for x in peer_cert.get("subject", []))
                    if subject.get("O") == "CyberC2":
                        return True
    except Exception:
        pass
    return False
