"""
Cryptographic Authentication Module

Ed25519 signature-based authentication:
- No passwords transmitted
- Challenge-response protocol
- Private keys never leave the client

Flow:
1. Client requests challenge (random nonce)
2. Client signs challenge with private key
3. Server verifies signature with stored public key
4. On success, JWT token issued
"""

import os
import secrets
import hashlib
import base64
import json
import time
from typing import Optional, Tuple, Dict, Any
from datetime import datetime, timedelta

# Use cryptography library for Ed25519
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey, Ed25519PublicKey
    )
    from cryptography.hazmat.primitives import serialization
    from cryptography.exceptions import InvalidSignature
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False
    print("Warning: cryptography library not installed. Run: pip install cryptography")

# Challenge storage (in-memory with expiration)
# In production, use Redis or database
_pending_challenges: Dict[str, Dict[str, Any]] = {}
CHALLENGE_EXPIRY_SECONDS = 60


def generate_keypair() -> Tuple[str, str]:
    """
    Generate an Ed25519 keypair.
    
    Returns:
        Tuple of (private_key_pem, public_key_pem)
    """
    if not HAS_CRYPTO:
        raise RuntimeError("cryptography library required")
    
    # Generate private key
    private_key = Ed25519PrivateKey.generate()
    
    # Serialize private key (PEM format)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ).decode('utf-8')
    
    # Get public key
    public_key = private_key.public_key()
    
    # Serialize public key (PEM format)
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode('utf-8')
    
    return private_pem, public_pem


def generate_keypair_raw() -> Tuple[str, str]:
    """
    Generate keypair and return as base64-encoded raw bytes.
    Smaller format, easier for copy/paste.
    
    Returns:
        Tuple of (private_key_b64, public_key_b64)
    """
    if not HAS_CRYPTO:
        raise RuntimeError("cryptography library required")
    
    private_key = Ed25519PrivateKey.generate()
    
    # Raw private key bytes (32 bytes)
    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    # Raw public key bytes (32 bytes)
    public_bytes = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    
    return base64.b64encode(private_bytes).decode(), base64.b64encode(public_bytes).decode()


def public_key_from_pem(pem: str) -> Ed25519PublicKey:
    """Load public key from PEM string."""
    return serialization.load_pem_public_key(pem.encode())


def public_key_from_raw(b64: str) -> Ed25519PublicKey:
    """Load public key from base64-encoded raw bytes."""
    raw_bytes = base64.b64decode(b64)
    return Ed25519PublicKey.from_public_bytes(raw_bytes)


def private_key_from_raw(b64: str) -> Ed25519PrivateKey:
    """Load private key from base64-encoded raw bytes."""
    raw_bytes = base64.b64decode(b64)
    return Ed25519PrivateKey.from_private_bytes(raw_bytes)


def create_challenge(username: str) -> Dict[str, str]:
    """
    Create a challenge for authentication.
    
    Args:
        username: The username requesting auth
        
    Returns:
        Dict with challenge_id and challenge (nonce)
    """
    # Clean up expired challenges
    _cleanup_challenges()
    
    # Generate random challenge (32 bytes = 256 bits)
    nonce = secrets.token_bytes(32)
    challenge = base64.b64encode(nonce).decode()
    
    # Challenge ID for lookup
    challenge_id = secrets.token_hex(16)
    
    # Store with expiry
    _pending_challenges[challenge_id] = {
        "username": username,
        "challenge": challenge,
        "created_at": time.time(),
        "expires_at": time.time() + CHALLENGE_EXPIRY_SECONDS
    }
    
    return {
        "challenge_id": challenge_id,
        "challenge": challenge,
        "expires_in": CHALLENGE_EXPIRY_SECONDS
    }


def verify_signature(
    challenge_id: str,
    signature_b64: str,
    public_key_b64: str
) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Verify a signed challenge.
    
    Args:
        challenge_id: The challenge ID to verify
        signature_b64: Base64-encoded signature
        public_key_b64: Base64-encoded public key
        
    Returns:
        Tuple of (success, username, error_message)
    """
    if not HAS_CRYPTO:
        return False, None, "Crypto library not available"
    
    # Get challenge
    challenge_data = _pending_challenges.get(challenge_id)
    if not challenge_data:
        return False, None, "Challenge not found or expired"
    
    # Check expiry
    if time.time() > challenge_data["expires_at"]:
        del _pending_challenges[challenge_id]
        return False, None, "Challenge expired"
    
    try:
        # Load public key
        public_key = public_key_from_raw(public_key_b64)
        
        # Decode signature and challenge
        signature = base64.b64decode(signature_b64)
        challenge = base64.b64decode(challenge_data["challenge"])
        
        # Verify signature
        public_key.verify(signature, challenge)
        
        # Success! Remove used challenge
        username = challenge_data["username"]
        del _pending_challenges[challenge_id]
        
        return True, username, None
        
    except InvalidSignature:
        return False, None, "Invalid signature"
    except Exception as e:
        return False, None, f"Verification error: {str(e)}"


def sign_challenge(challenge_b64: str, private_key_b64: str) -> str:
    """
    Sign a challenge with private key (for testing).
    In production, this happens client-side in JavaScript.
    
    Args:
        challenge_b64: Base64-encoded challenge
        private_key_b64: Base64-encoded private key
        
    Returns:
        Base64-encoded signature
    """
    if not HAS_CRYPTO:
        raise RuntimeError("Crypto library not available")
    
    private_key = private_key_from_raw(private_key_b64)
    challenge = base64.b64decode(challenge_b64)
    signature = private_key.sign(challenge)
    return base64.b64encode(signature).decode()


def get_key_fingerprint(public_key_b64: str) -> str:
    """
    Get SHA256 fingerprint of public key.
    Used for display and verification.
    
    Args:
        public_key_b64: Base64-encoded public key
        
    Returns:
        Hex fingerprint (first 16 chars)
    """
    raw_bytes = base64.b64decode(public_key_b64)
    fp = hashlib.sha256(raw_bytes).hexdigest()
    return fp[:16].upper()


def _cleanup_challenges():
    """Remove expired challenges."""
    now = time.time()
    expired = [k for k, v in _pending_challenges.items() if now > v["expires_at"]]
    for k in expired:
        del _pending_challenges[k]


# ============================================================================
# Key file format helpers
# ============================================================================

def export_key_file(private_key_b64: str, public_key_b64: str, username: str) -> str:
    """
    Export keypair as downloadable JSON file content.
    
    Args:
        private_key_b64: Base64 private key
        public_key_b64: Base64 public key
        username: Username this key belongs to
        
    Returns:
        JSON string for download
    """
    return json.dumps({
        "version": 1,
        "type": "a2a-cyber-key",
        "username": username,
        "fingerprint": get_key_fingerprint(public_key_b64),
        "public_key": public_key_b64,
        "private_key": private_key_b64,
        "created_at": datetime.now().isoformat(),
        "warning": "KEEP THIS FILE SECURE - Anyone with this key can access your account"
    }, indent=2)


def import_key_file(json_content: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Import keypair from JSON file.
    
    Args:
        json_content: JSON string from key file
        
    Returns:
        Tuple of (private_key_b64, public_key_b64, error)
    """
    try:
        data = json.loads(json_content)
        if data.get("type") != "a2a-cyber-key":
            return None, None, "Invalid key file format"
        return data.get("private_key"), data.get("public_key"), None
    except json.JSONDecodeError:
        return None, None, "Invalid JSON"
    except Exception as e:
        return None, None, str(e)


# ============================================================================
# Simple test
# ============================================================================

if __name__ == "__main__":
    print("Testing Ed25519 Challenge-Response Auth\n")
    
    # 1. Generate keypair
    print("1. Generating keypair...")
    private_key, public_key = generate_keypair_raw()
    print(f"   Private key: {private_key[:20]}...")
    print(f"   Public key:  {public_key}")
    print(f"   Fingerprint: {get_key_fingerprint(public_key)}")
    
    # 2. Create challenge
    print("\n2. Creating challenge...")
    challenge_data = create_challenge("admin")
    print(f"   Challenge ID: {challenge_data['challenge_id']}")
    print(f"   Challenge:    {challenge_data['challenge'][:20]}...")
    
    # 3. Sign challenge (normally done client-side)
    print("\n3. Signing challenge...")
    signature = sign_challenge(challenge_data["challenge"], private_key)
    print(f"   Signature:    {signature[:30]}...")
    
    # 4. Verify signature
    print("\n4. Verifying signature...")
    success, username, error = verify_signature(
        challenge_data["challenge_id"],
        signature,
        public_key
    )
    if success:
        print(f"   ✅ SUCCESS! Authenticated as: {username}")
    else:
        print(f"   ❌ FAILED: {error}")
    
    # 5. Test key file export/import
    print("\n5. Testing key file export/import...")
    key_file = export_key_file(private_key, public_key, "admin")
    print(f"   Exported: {len(key_file)} bytes")
    
    priv, pub, err = import_key_file(key_file)
    if err:
        print(f"   ❌ Import failed: {err}")
    else:
        print(f"   ✅ Import successful")
        print(f"   Keys match: {priv == private_key and pub == public_key}")
