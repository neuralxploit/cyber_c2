#!/usr/bin/env python3
"""
Shodan Hunter - Generic Shodan Search Tool
Search Shodan with custom queries and export targets
"""

import shodan
import argparse
import json
import signal
import sys
from datetime import datetime
from typing import List, Dict, Optional


# Graceful shutdown
SHUTDOWN = False
def signal_handler(sig, frame):
    global SHUTDOWN
    if SHUTDOWN:
        sys.exit(1)
    SHUTDOWN = True
    print("\n[!] Ctrl+C - Stopping...")

signal.signal(signal.SIGINT, signal_handler)


class Colors:
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    MAGENTA = "\033[95m"
    BOLD = "\033[1m"
    RESET = "\033[0m"

def c(text, color):
    return f"{color}{text}{Colors.RESET}"


class ShodanHunter:
    """Generic Shodan search and target discovery tool."""
    
    # Predefined search queries (tested and working)
    PRESETS = {
        "nextjs": 'X-Powered-By: Next.js',
        "nextjs-rsc": 'http.html:"__NEXT_DATA__" "x-action"',
        "react": 'http.html:"__NEXT_DATA__" OR http.html:"react-root"',
        "nuxt": 'X-Powered-By: Nuxt',
        "express": 'X-Powered-By: Express',
        "django": 'http.html:"csrfmiddlewaretoken"',
        "flask": 'Server: Werkzeug',
        "laravel": 'Set-Cookie: laravel_session',
        "wordpress": 'http.html:"wp-content"',
        "graphql": 'http.html:"graphql" OR http.title:"GraphQL"',
        "kubernetes": 'http.title:"Kubernetes Dashboard" OR port:6443',
        "docker": 'port:2375 product:"Docker"',
        "jenkins": 'http.title:"Dashboard [Jenkins]"',
        "gitlab": 'http.title:"GitLab"',
        "ssh": 'port:22 product:"OpenSSH"',
        "rdp": 'port:3389 "Remote Desktop"',
        "vnc": 'port:5900 "VNC"',
        "ftp": 'port:21 "FTP"',
        "mysql": 'port:3306 product:"MySQL"',
        "postgres": 'port:5432 product:"PostgreSQL"',
        "mongodb": 'port:27017 product:"MongoDB"',
        "redis": 'port:6379 product:"Redis"',
        "elasticsearch": 'port:9200 "elasticsearch"',
        "apache": 'Server: Apache',
        "nginx": 'Server: nginx',
        "iis": 'Server: Microsoft-IIS',
        "tomcat": 'Server: Apache-Coyote OR http.title:"Apache Tomcat"',
    }
    
    # Honeypot detection
    HONEYPOT_INDICATORS = {
        "orgs": ["honeypot", "honeynet", "research", "security lab", "trap", "deception"],
        "banners": ["honeypot", "honeyd", "cowrie", "kippo", "dionaea", "glastopf", "conpot"],
        "ip_prefixes": ["8.209.", "47.88.", "47.89.", "47.90.", "47.91."],
    }
    
    def __init__(self, api_key: str):
        self.api = shodan.Shodan(api_key)
        self.results = []
        
    def search(self, query: str, limit: int = 100, filter_honeypots: bool = True) -> List[Dict]:
        """
        Search Shodan with custom query.
        
        Args:
            query: Shodan search query
            limit: Maximum results
            filter_honeypots: Remove likely honeypots
            
        Returns:
            List of target dictionaries
        """
        global SHUTDOWN
        targets = []
        honeypots_skipped = 0
        
        try:
            print(c(f"[*] Searching: {query}", Colors.CYAN))
            results = self.api.search(query, limit=limit)
            total = results['total']
            
            print(c(f"[+] Total matches: {total:,}", Colors.GREEN))
            print(c(f"[*] Processing up to {limit} results...\n", Colors.CYAN))
            
            for result in results['matches']:
                if SHUTDOWN:
                    break
                    
                # Honeypot check
                if filter_honeypots and self._is_honeypot(result):
                    honeypots_skipped += 1
                    continue
                
                target = self._parse_result(result)
                targets.append(target)
                
                # Print result
                print(f"[{len(targets)}] {c(target['url'], Colors.GREEN)}")
                print(f"    IP: {target['ip']} | Port: {target['port']}")
                print(f"    Org: {target['org'][:40]}")
                print(f"    Country: {target['country']}")
                print()
                
                if len(targets) >= limit:
                    break
                    
            if honeypots_skipped > 0:
                print(c(f"[!] Skipped {honeypots_skipped} potential honeypots", Colors.YELLOW))
                
        except shodan.APIError as e:
            print(c(f"[-] Shodan API Error: {e}", Colors.RED))
            
        self.results = targets
        return targets
    
    def _parse_result(self, result: Dict) -> Dict:
        """Parse Shodan result into target dict."""
        ip = result.get('ip_str', '')
        port = result.get('port', 80)
        hostnames = result.get('hostnames', [])
        hostname = hostnames[0] if hostnames else ip
        
        # Determine protocol
        ssl = result.get('ssl', {})
        protocol = 'https' if ssl or port == 443 else 'http'
        
        # Build URL
        if port in [80, 443]:
            url = f"{protocol}://{hostname}"
        else:
            url = f"{protocol}://{hostname}:{port}"
        
        return {
            'url': url,
            'ip': ip,
            'port': port,
            'hostname': hostname,
            'org': result.get('org', 'Unknown'),
            'country': result.get('location', {}).get('country_name', 'Unknown'),
            'country_code': result.get('location', {}).get('country_code', ''),
            'asn': result.get('asn', ''),
            'isp': result.get('isp', ''),
            'product': result.get('product', ''),
            'version': result.get('version', ''),
            'os': result.get('os', ''),
            'banner': result.get('data', '')[:500],
            'timestamp': result.get('timestamp', ''),
        }
    
    def _is_honeypot(self, result: Dict) -> bool:
        """Check if result is likely a honeypot."""
        org = (result.get('org') or '').lower()
        banner = (result.get('data') or '').lower()
        ip = result.get('ip_str') or ''
        
        # Check org
        for indicator in self.HONEYPOT_INDICATORS['orgs']:
            if indicator in org:
                return True
        
        # Check banner
        for indicator in self.HONEYPOT_INDICATORS['banners']:
            if indicator in banner:
                return True
        
        # Check IP prefix
        for prefix in self.HONEYPOT_INDICATORS['ip_prefixes']:
            if ip.startswith(prefix):
                return True
        
        # Suspicious pre-canned output
        if "uid=0(root)" in banner and "gid=0(root)" in banner:
            return True
            
        return False
    
    def export_urls(self, filepath: str):
        """Export just URLs to file."""
        with open(filepath, 'w') as f:
            for target in self.results:
                f.write(target['url'] + '\n')
        print(c(f"[+] URLs exported to {filepath}", Colors.GREEN))
    
    def export_ips(self, filepath: str):
        """Export just IPs to file."""
        with open(filepath, 'w') as f:
            for target in self.results:
                f.write(target['ip'] + '\n')
        print(c(f"[+] IPs exported to {filepath}", Colors.GREEN))
    
    def export_json(self, filepath: str):
        """Export full results to JSON."""
        data = {
            'scan_time': datetime.now().isoformat(),
            'total_results': len(self.results),
            'targets': self.results
        }
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)
        print(c(f"[+] JSON exported to {filepath}", Colors.GREEN))
    
    def export_csv(self, filepath: str):
        """Export results to CSV."""
        import csv
        with open(filepath, 'w', newline='') as f:
            if self.results:
                writer = csv.DictWriter(f, fieldnames=['url', 'ip', 'port', 'hostname', 'org', 'country', 'product'])
                writer.writeheader()
                for target in self.results:
                    writer.writerow({k: target.get(k, '') for k in ['url', 'ip', 'port', 'hostname', 'org', 'country', 'product']})
        print(c(f"[+] CSV exported to {filepath}", Colors.GREEN))
    
    def get_api_info(self):
        """Get Shodan API info and credits."""
        try:
            info = self.api.info()
            print(c("\n[*] Shodan API Info:", Colors.CYAN))
            print(f"    Plan: {info.get('plan', 'Unknown')}")
            print(f"    Query Credits: {info.get('query_credits', 0)}")
            print(f"    Scan Credits: {info.get('scan_credits', 0)}")
        except shodan.APIError as e:
            print(c(f"[-] API Error: {e}", Colors.RED))
    
    @classmethod
    def list_presets(cls):
        """List available search presets."""
        print(c("\n[*] Available Search Presets:\n", Colors.CYAN))
        for name, query in cls.PRESETS.items():
            print(f"  {c(name, Colors.GREEN):20} → {query[:60]}...")
        print()


def main():
    parser = argparse.ArgumentParser(
        description="Shodan Hunter - Search and Export Targets",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -q "X-Powered-By: Next.js" -o targets.txt
  %(prog)s --preset nextjs-rsc -o rsc_targets.txt
  %(prog)s -q "port:22 country:US" --limit 50 --json results.json
  %(prog)s --list-presets
  %(prog)s --info
"""
    )
    
    parser.add_argument("-q", "--query", help="Custom Shodan search query")
    parser.add_argument("-p", "--preset", help="Use predefined search preset")
    parser.add_argument("-k", "--api-key", help="Shodan API key (or set SHODAN_API_KEY env)")
    parser.add_argument("-l", "--limit", type=int, default=100, help="Max results (default: 100)")
    parser.add_argument("-o", "--output", help="Output file for URLs")
    parser.add_argument("--ips", help="Output file for IPs only")
    parser.add_argument("--json", help="Output file for full JSON")
    parser.add_argument("--csv", help="Output file for CSV")
    parser.add_argument("--no-honeypot-filter", action="store_true", help="Disable honeypot filtering")
    parser.add_argument("--list-presets", action="store_true", help="List available presets")
    parser.add_argument("--info", action="store_true", help="Show API info and credits")
    
    args = parser.parse_args()
    
    # List presets
    if args.list_presets:
        ShodanHunter.list_presets()
        return
    
    # Get API key
    import os
    api_key = args.api_key or os.getenv("SHODAN_API_KEY")
    if not api_key:
        print(c("[-] No API key. Use -k or set SHODAN_API_KEY env", Colors.RED))
        return
    
    print(c("\n🔍 Shodan Hunter\n", Colors.CYAN + Colors.BOLD))
    
    hunter = ShodanHunter(api_key)
    
    # Show API info
    if args.info:
        hunter.get_api_info()
        return
    
    # Get query
    if args.preset:
        if args.preset not in ShodanHunter.PRESETS:
            print(c(f"[-] Unknown preset: {args.preset}", Colors.RED))
            ShodanHunter.list_presets()
            return
        query = ShodanHunter.PRESETS[args.preset]
        print(c(f"[*] Using preset '{args.preset}'", Colors.CYAN))
    elif args.query:
        query = args.query
    else:
        # Interactive mode
        print(c("[*] Available presets:", Colors.CYAN))
        for i, (name, q) in enumerate(list(ShodanHunter.PRESETS.items())[:10], 1):
            print(f"  {i}. {name}")
        print(f"  0. Custom query")
        
        choice = input(c("\n[?] Select preset (0-10) or enter custom query: ", Colors.YELLOW))
        
        if choice.isdigit():
            idx = int(choice)
            if idx == 0:
                query = input(c("[?] Enter Shodan query: ", Colors.YELLOW))
            elif 1 <= idx <= 10:
                query = list(ShodanHunter.PRESETS.values())[idx-1]
            else:
                print(c("[-] Invalid choice", Colors.RED))
                return
        else:
            query = choice
    
    # Search
    filter_hp = not args.no_honeypot_filter
    targets = hunter.search(query, limit=args.limit, filter_honeypots=filter_hp)
    
    # Export
    if targets:
        print(c(f"\n[+] Found {len(targets)} targets", Colors.GREEN + Colors.BOLD))
        
        if args.output:
            hunter.export_urls(args.output)
        if args.ips:
            hunter.export_ips(args.ips)
        if args.json:
            hunter.export_json(args.json)
        if args.csv:
            hunter.export_csv(args.csv)
        
        # Default export if no output specified
        if not any([args.output, args.ips, args.json, args.csv]):
            default_file = f"shodan_targets_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
            hunter.export_urls(default_file)
    else:
        print(c("[-] No targets found", Colors.RED))


if __name__ == "__main__":
    main()
