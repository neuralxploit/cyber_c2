#!/usr/bin/env python3
"""
Generate RSA keypair for Cyber C2 authentication.

Usage:
    python generate_keys.py

Creates:
    admin.key          - RSA private key (paste into login page)
    admin.key.pub      - RSA public key (for reference)

Prints the base64 public key to add to your .env as ADMIN_PUBLIC_KEY.
"""

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import base64
import sys

def generate_keypair():
    # Generate 2048-bit RSA key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )

    # Serialize private key (PEM)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption()
    )

    # Serialize public key (PEM)
    public_key = private_key.public_key()
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )

    # Get raw public key bytes (DER SubjectPublicKeyInfo) for base64 .env format
    public_der = public_key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    public_b64 = base64.b64encode(public_der).decode()

    # Write private key
    with open("admin.key", "wb") as f:
        f.write(private_pem)
    print("[+] Private key saved to: admin.key")

    # Write public key
    with open("admin.key.pub", "wb") as f:
        f.write(public_pem)
    print("[+] Public key saved to:  admin.key.pub")

    # Print the base64 for .env
    print("\n[+] Add this to your .env file:\n")
    print(f"ADMIN_PUBLIC_KEY={public_b64}")
    print("\n[+] Use the contents of admin.key to login (paste into the login page)")

if __name__ == "__main__":
    generate_keypair()
