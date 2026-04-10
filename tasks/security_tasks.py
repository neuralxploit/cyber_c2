"""
Security Tool Tasks - Celery Background Jobs

Each tool runs in background, stores results in Redis,
and can be retrieved by task UUID.
"""
import subprocess
import json
import os
import re
import urllib3
from datetime import datetime
from typing import Dict, Any, Optional
from celery import current_task
from .celery_app import celery_app

# Suppress InsecureRequestWarning for verify=False requests
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

import logging
logger = logging.getLogger(__name__)


def run_command(cmd: str, timeout: int = 600) -> Dict[str, Any]:
    """Execute a command and return structured results."""
    start_time = datetime.now()
    
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        return {
            "success": result.returncode == 0,
            "command": cmd,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_seconds": duration
        }
        
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "command": cmd,
            "error": f"Command timed out after {timeout} seconds",
            "start_time": start_time.isoformat(),
            "end_time": datetime.now().isoformat()
        }
    except Exception as e:
        return {
            "success": False,
            "command": cmd,
            "error": str(e),
            "start_time": start_time.isoformat(),
            "end_time": datetime.now().isoformat()
        }


@celery_app.task(bind=True, name="tasks.security_tasks.run_shodan_search")
def run_shodan_search(self, api_key: str, query: str, limit: int = 100, save_file: str = None) -> Dict[str, Any]:
    """
    Shodan Search - Generic search with presets or custom queries
    
    Args:
        api_key: Shodan API key
        query: Search query or preset name (nextjs, ssh, mysql, etc.)
        limit: Maximum results
        save_file: Optional filename to save results (json, txt, or csv)
    
    Returns:
        Dict with search results and targets
    """
    import sys
    import json
    from pathlib import Path
    
    # Import Shodan hunter
    tools_path = Path(__file__).parent.parent / "tools"
    sys.path.insert(0, str(tools_path))
    
    try:
        from shodan_hunter import ShodanHunter
    except ImportError as e:
        return {
            "success": False,
            "error": f"Failed to import Shodan hunter: {e}",
            "task_id": self.request.id
        }
    
    start_time = datetime.now()
    self.update_state(
        state="RUNNING", 
        meta={
            "status": f"Searching Shodan: {query}...",
            "query": query,
            "limit": limit
        }
    )
    
    try:
        hunter = ShodanHunter(api_key)
        
        # Check if query is a preset
        if query.lower() in hunter.PRESETS:
            actual_query = hunter.PRESETS[query.lower()]
        else:
            actual_query = query
        
        targets = hunter.search(actual_query, limit=limit)
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        # Format results
        urls = [t['url'] for t in targets]
        
        # Save to file if requested
        saved_file = None
        if save_file:
            output_dir = Path(__file__).parent.parent / "output"
            output_dir.mkdir(exist_ok=True)
            
            # Determine format from extension
            save_path = output_dir / save_file
            ext = save_path.suffix.lower()
            
            if ext == '.json':
                with open(save_path, 'w') as f:
                    json.dump({
                        "query": query,
                        "actual_query": actual_query,
                        "total": len(targets),
                        "targets": targets
                    }, f, indent=2)
            elif ext == '.csv':
                import csv
                with open(save_path, 'w', newline='') as f:
                    if targets:
                        writer = csv.DictWriter(f, fieldnames=targets[0].keys())
                        writer.writeheader()
                        writer.writerows(targets)
            else:  # .txt or other - just URLs
                with open(save_path, 'w') as f:
                    f.write(f"# Shodan Search: {query}\n")
                    f.write(f"# Total: {len(targets)}\n\n")
                    for t in targets:
                        f.write(f"{t['url']}\n")
            
            saved_file = str(save_path)
            logger.info(f"Saved Shodan results to: {saved_file}")
        
        return {
            "success": True,
            "task_id": self.request.id,
            "query": query,
            "actual_query": actual_query,
            "total_found": len(targets),
            "targets": targets,
            "urls": urls,
            "saved_file": saved_file,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_seconds": duration
        }
        
    except Exception as e:
        logger.error(f"Shodan search failed: {e}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
            "task_id": self.request.id
        }


@celery_app.task(bind=True, name="tasks.security_tasks.run_react2shell")
def run_react2shell(self, target: str, action: str = "check", command: str = None, oast_url: str = None) -> Dict[str, Any]:
    """
    React2Shell - CVE-2025-55182 Scanner/Exploiter
    
    Args:
        target: Target URL
        action: check, scan, or cmd
        command: Command to execute (if action=cmd)
        oast_url: OAST URL for exfiltration
    
    Returns:
        Dict with scan/exploit results
    """
    import sys
    from pathlib import Path
    
    tools_path = Path(__file__).parent.parent / "tools"
    sys.path.insert(0, str(tools_path))
    
    try:
        from react2shell_exploit import React2ShellExploit
    except ImportError as e:
        return {
            "success": False,
            "error": f"Failed to import React2Shell: {e}",
            "task_id": self.request.id
        }
    
    start_time = datetime.now()
    self.update_state(
        state="RUNNING", 
        meta={
            "status": f"Running React2Shell {action} on {target}...",
            "target": target,
            "action": action
        }
    )
    
    try:
        exploit = React2ShellExploit(oast_url=oast_url)
        
        if action == "check":
            result = exploit.check_vulnerable(target)
        elif action == "cmd" and command:
            result = exploit.exploit(target, command)
        else:
            result = exploit.check_vulnerable(target)
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        return {
            "success": True,
            "task_id": self.request.id,
            "target": target,
            "action": action,
            "vulnerable": result.get("vulnerable", False),
            "command_output": result.get("command_output", ""),
            "result": result,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_seconds": duration
        }
        
    except Exception as e:
        logger.error(f"React2Shell failed: {e}", exc_info=True)
        return {
            "success": False,
            "error": str(e),
            "task_id": self.request.id,
            "target": target
        }


# =============================================================================
# SCANNING TASKS
# =============================================================================

@celery_app.task(bind=True, name="tasks.security_tasks.run_nmap")
def run_nmap(self, target: str, options: str = "-sV -sC") -> Dict[str, Any]:
    """Run nmap scan in background."""
    self.update_state(state="RUNNING", meta={"tool": "nmap", "target": target})
    
    # Sanitize target
    target = re.sub(r'[;&|`$]', '', target)
    
    cmd = f"nmap {options} {target}"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=600)
    result["tool"] = "nmap"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse open ports from output
    if result.get("stdout"):
        ports = re.findall(r'(\d+)/tcp\s+open\s+(\S+)', result["stdout"])
        result["parsed"] = {
            "open_ports": [{"port": p[0], "service": p[1]} for p in ports],
            "total_ports": len(ports)
        }
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_sqlmap")
def run_sqlmap(self, target: str, options: str = "--batch --crawl=2") -> Dict[str, Any]:
    """Run sqlmap scan in background."""
    self.update_state(state="RUNNING", meta={"tool": "sqlmap", "target": target})
    
    # Sanitize
    target = target.replace("'", "").replace('"', '')
    
    cmd = f"sqlmap -u '{target}' {options} --output-dir=/tmp/sqlmap_output"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=1800)  # 30 min timeout
    result["tool"] = "sqlmap"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse vulnerabilities - improved detection
    if result.get("stdout"):
        stdout = result["stdout"]
        stdout_lower = stdout.lower()
        vulns = []
        injection_types = []
        
        # Check for various SQLi indicators
        if "is vulnerable" in stdout_lower:
            vulns.append("SQL Injection confirmed")
        
        # Check for injection type indicators (these appear when vuln is found)
        if "boolean-based blind" in stdout_lower:
            injection_types.append("Boolean-based blind SQL injection")
        if "error-based" in stdout_lower:
            injection_types.append("Error-based SQL injection")
        if "time-based blind" in stdout_lower:
            injection_types.append("Time-based blind SQL injection")
        if "union query" in stdout_lower or "union-based" in stdout_lower:
            injection_types.append("UNION query SQL injection")
        if "stacked queries" in stdout_lower:
            injection_types.append("Stacked queries SQL injection")
        
        # Check for parameter identification (means injection point found)
        if "parameter:" in stdout_lower and ("type:" in stdout_lower or "payload:" in stdout_lower):
            if not vulns:
                vulns.append("SQL Injection point identified")
        
        # Check for database extraction
        if "retrieved:" in stdout_lower:
            vulns.append("Data extraction successful")
        if "available databases" in stdout_lower:
            vulns.append("Database enumeration possible")
        if "back-end dbms" in stdout_lower:
            vulns.append("DBMS fingerprinted")
        
        # Combine injection types into vulns
        vulns.extend(injection_types)
        
        # Determine severity
        is_vulnerable = len(injection_types) > 0 or "is vulnerable" in stdout_lower
        severity = "CRITICAL" if is_vulnerable else "INFO"
        
        result["parsed"] = {
            "vulnerabilities": vulns,
            "injection_types": injection_types,
            "is_vulnerable": is_vulnerable,
            "severity": severity
        }
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_nuclei")
def run_nuclei(self, target: str, options: str = "-severity critical,high,medium") -> Dict[str, Any]:
    """Run nuclei vulnerability scan in background."""
    self.update_state(state="RUNNING", meta={"tool": "nuclei", "target": target})
    
    target = re.sub(r'[;&|`$]', '', target)
    
    cmd = f"nuclei -u {target} {options} -json"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=1200)  # 20 min timeout
    result["tool"] = "nuclei"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse JSON output
    if result.get("stdout"):
        findings = []
        for line in result["stdout"].strip().split("\n"):
            if line.strip():
                try:
                    finding = json.loads(line)
                    findings.append({
                        "template": finding.get("template-id", "unknown"),
                        "severity": finding.get("info", {}).get("severity", "unknown"),
                        "name": finding.get("info", {}).get("name", "unknown"),
                        "matched": finding.get("matched-at", "")
                    })
                except json.JSONDecodeError:
                    pass
        result["parsed"] = {
            "findings": findings,
            "total": len(findings),
            "critical": len([f for f in findings if f["severity"] == "critical"]),
            "high": len([f for f in findings if f["severity"] == "high"]),
            "medium": len([f for f in findings if f["severity"] == "medium"])
        }
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_nikto")
def run_nikto(self, target: str, options: str = "-Tuning x") -> Dict[str, Any]:
    """Run nikto web scan in background."""
    self.update_state(state="RUNNING", meta={"tool": "nikto", "target": target})
    
    target = re.sub(r'[;&|`$]', '', target)
    
    cmd = f"nikto -h {target} {options}"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=900)  # 15 min timeout
    result["tool"] = "nikto"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse findings
    if result.get("stdout"):
        findings = re.findall(r'\+ (.+)', result["stdout"])
        result["parsed"] = {
            "findings": findings[:50],  # Limit to 50
            "total": len(findings)
        }
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_gobuster")
def run_gobuster(self, target: str, wordlist: str = "/usr/share/wordlists/dirb/common.txt", options: str = "-t 50") -> Dict[str, Any]:
    """Run gobuster directory scan in background."""
    self.update_state(state="RUNNING", meta={"tool": "gobuster", "target": target})
    
    target = re.sub(r'[;&|`$]', '', target)
    
    # Check if wordlist exists, use alternative if not
    if not os.path.exists(wordlist):
        wordlist = "/usr/share/wordlists/dirbuster/directory-list-2.3-small.txt"
    if not os.path.exists(wordlist):
        wordlist = "/opt/homebrew/share/wordlists/dirb/common.txt"
    
    cmd = f"gobuster dir -u {target} -w {wordlist} {options}"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=600)
    result["tool"] = "gobuster"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse found paths
    if result.get("stdout"):
        paths = re.findall(r'(/\S+)\s+\(Status:\s*(\d+)\)', result["stdout"])
        result["parsed"] = {
            "paths": [{"path": p[0], "status": p[1]} for p in paths],
            "total": len(paths)
        }
    
    return result


# =============================================================================
# RECON TASKS  
# =============================================================================

@celery_app.task(bind=True, name="tasks.security_tasks.run_whois")
def run_whois(self, target: str) -> Dict[str, Any]:
    """Run whois lookup in background."""
    self.update_state(state="RUNNING", meta={"tool": "whois", "target": target})
    
    target = re.sub(r'[;&|`$\s]', '', target)
    
    cmd = f"whois {target}"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=60)
    result["tool"] = "whois"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse key info
    if result.get("stdout"):
        parsed = {}
        for pattern, key in [
            (r'Registrar:\s*(.+)', 'registrar'),
            (r'Creation Date:\s*(.+)', 'created'),
            (r'Registry Expiry Date:\s*(.+)', 'expires'),
            (r'Name Server:\s*(.+)', 'nameservers'),
        ]:
            match = re.search(pattern, result["stdout"], re.IGNORECASE)
            if match:
                parsed[key] = match.group(1).strip()
        result["parsed"] = parsed
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_dig")
def run_dig(self, target: str, record_type: str = "ANY") -> Dict[str, Any]:
    """Run DNS lookup in background."""
    self.update_state(state="RUNNING", meta={"tool": "dig", "target": target})
    
    target = re.sub(r'[;&|`$\s]', '', target)
    
    cmd = f"dig {target} {record_type} +noall +answer"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=30)
    result["tool"] = "dig"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse records
    if result.get("stdout"):
        records = []
        for line in result["stdout"].strip().split("\n"):
            parts = line.split()
            if len(parts) >= 5:
                records.append({
                    "name": parts[0],
                    "type": parts[3],
                    "value": " ".join(parts[4:])
                })
        result["parsed"] = {"records": records}
    
    return result


@celery_app.task(bind=True, name="tasks.security_tasks.run_theharvester")
def run_theharvester(self, target: str, sources: str = "all") -> Dict[str, Any]:
    """Run theHarvester OSINT in background."""
    self.update_state(state="RUNNING", meta={"tool": "theHarvester", "target": target})
    
    target = re.sub(r'[;&|`$\s]', '', target)
    
    cmd = f"theHarvester -d {target} -b {sources} -l 200"
    logger.info(f"[TASK {self.request.id}] Running: {cmd}")
    
    result = run_command(cmd, timeout=300)
    result["tool"] = "theHarvester"
    result["target"] = target
    result["task_id"] = self.request.id
    
    # Parse emails and hosts
    if result.get("stdout"):
        emails = re.findall(r'[\w\.-]+@[\w\.-]+\.\w+', result["stdout"])
        hosts = re.findall(r'[\w\.-]+\.' + re.escape(target.split('.')[-2] + '.' + target.split('.')[-1]), result["stdout"])
        result["parsed"] = {
            "emails": list(set(emails)),
            "subdomains": list(set(hosts)),
            "total_emails": len(set(emails)),
            "total_subdomains": len(set(hosts))
        }
    
    return result


# =============================================================================
# FULL SCAN TASK (combines multiple tools)
# =============================================================================

@celery_app.task(bind=True, name="tasks.security_tasks.run_full_scan")
def run_full_scan(self, target: str) -> Dict[str, Any]:
    """Run comprehensive scan using multiple tools."""
    self.update_state(state="RUNNING", meta={"tool": "full_scan", "target": target, "progress": 0})
    
    results = {
        "tool": "full_scan",
        "target": target,
        "task_id": self.request.id,
        "start_time": datetime.now().isoformat(),
        "scans": {}
    }
    
    # Extract domain from URL
    domain = re.sub(r'^https?://', '', target).split('/')[0]
    
    # 1. WHOIS (5%)
    self.update_state(state="RUNNING", meta={"progress": 5, "current": "whois"})
    results["scans"]["whois"] = run_command(f"whois {domain}", timeout=60)
    
    # 2. DNS (10%)
    self.update_state(state="RUNNING", meta={"progress": 10, "current": "dns"})
    results["scans"]["dns"] = run_command(f"dig {domain} ANY +noall +answer", timeout=30)
    
    # 3. Port scan (30%)
    self.update_state(state="RUNNING", meta={"progress": 15, "current": "nmap"})
    results["scans"]["nmap"] = run_command(f"nmap -sV -sC --top-ports 100 {domain}", timeout=300)
    
    # 4. Web headers (35%)
    self.update_state(state="RUNNING", meta={"progress": 35, "current": "headers"})
    results["scans"]["headers"] = run_command(f"curl -sI {target}", timeout=30)
    
    # 5. Nikto (60%)
    self.update_state(state="RUNNING", meta={"progress": 40, "current": "nikto"})
    results["scans"]["nikto"] = run_command(f"nikto -h {target} -Tuning x -maxtime 300", timeout=360)
    
    # 6. SQLMap (90%)
    self.update_state(state="RUNNING", meta={"progress": 65, "current": "sqlmap"})
    results["scans"]["sqlmap"] = run_command(f"sqlmap -u '{target}' --batch --crawl=2 --level=1 --risk=1", timeout=600)
    
    # 7. Nuclei (100%)
    self.update_state(state="RUNNING", meta={"progress": 85, "current": "nuclei"})
    results["scans"]["nuclei"] = run_command(f"nuclei -u {target} -severity critical,high -silent", timeout=300)
    
    results["end_time"] = datetime.now().isoformat()
    results["progress"] = 100
    
    # Summary
    results["summary"] = {
        "total_scans": len(results["scans"]),
        "successful": len([s for s in results["scans"].values() if s.get("success")]),
        "failed": len([s for s in results["scans"].values() if not s.get("success")])
    }
    
    return results


# =============================================================================
# UTILITY TASKS
# =============================================================================

@celery_app.task(bind=True, name="tasks.security_tasks.run_custom_command")
def run_custom_command(self, cmd: str, timeout: int = 300) -> Dict[str, Any]:
    """Run any custom command in background."""
    # Security: block dangerous commands
    dangerous = ['rm -rf', 'mkfs', 'dd if=', '> /dev/', ':(){']
    if any(d in cmd.lower() for d in dangerous):
        return {
            "success": False,
            "error": "Command blocked for security",
            "task_id": self.request.id
        }
    
    self.update_state(state="RUNNING", meta={"command": cmd})
    
    result = run_command(cmd, timeout=timeout)
    result["task_id"] = self.request.id
    
    return result


# =============================================================================
# CURL RECON TASK - REAL CURL Commands for Web Reconnaissance
# =============================================================================

@celery_app.task(bind=True, name="tasks.security_tasks.run_curl_recon")
# New CURL RECON - Pure Enumeration (no exploit testing)
# This replaces the old run_curl_recon function in security_tasks.py

@celery_app.task(bind=True, name="tasks.security_tasks.run_curl_recon")
def run_curl_recon(self, target_url: str) -> Dict[str, Any]:
    """
    CURL-based web enumeration - RECON ONLY, no exploit testing.
    
    Features:
    1. Get all HTTP headers
    2. Get page content/body
    3. Extract endpoints from HTML (links, forms, API paths)
    4. Check common paths (robots.txt, sitemap.xml, etc.)
    5. Technology fingerprinting
    6. SSL/TLS info
    """
    from urllib.parse import urlparse, urljoin
    import subprocess
    import re
    
    start_time = datetime.now()
    
    # Normalize URL
    if not target_url.startswith('http'):
        target_url = f'https://{target_url}'
    target_url = target_url.rstrip('/')
    
    parsed = urlparse(target_url)
    base_url = f"{parsed.scheme}://{parsed.netloc}"
    domain = parsed.netloc
    
    results = {
        "success": True,
        "task_id": self.request.id,
        "target": target_url,
        "domain": domain,
        "start_time": start_time.isoformat(),
        "headers": {},
        "response_code": 0,
        "content_type": "",
        "content_length": 0,
        "body_preview": "",
        "body_full": "",
        "ssl_info": "",
        "technologies": [],
        "endpoints": [],
        "forms": [],
        "paths_checked": {},
        "cookies": [],
        "redirects": [],
        "errors": [],
        "curl_commands": []
    }
    
    def run_curl(args: list, desc: str, timeout: int = 30) -> dict:
        """Execute curl command and capture output."""
        cmd = ["curl"] + args
        cmd_str = " ".join(cmd)
        
        out = {"cmd": cmd_str, "desc": desc, "stdout": "", "stderr": "", "ok": False}
        
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            out["stdout"] = proc.stdout
            out["stderr"] = proc.stderr
            out["ok"] = proc.returncode == 0
        except subprocess.TimeoutExpired:
            out["stderr"] = f"Timeout after {timeout}s"
        except Exception as e:
            out["stderr"] = str(e)
        
        results["curl_commands"].append(out)
        return out
    
    user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0"
    
    # =========================================================================
    # STEP 1: GET HEADERS (curl -sIvk)
    # =========================================================================
    self.update_state(state="RUNNING", meta={"status": "Fetching headers...", "progress": 10})
    
    hdr_result = run_curl(
        ["-sIvk", "-A", user_agent, "--connect-timeout", "15", target_url],
        "Get HTTP headers + SSL info"
    )
    
    if hdr_result["ok"]:
        # Parse response headers
        for line in hdr_result["stdout"].split('\n'):
            line = line.strip()
            if ':' in line and not line.startswith('*') and not line.startswith('<') and not line.startswith('>'):
                key, _, val = line.partition(':')
                key = key.strip()
                val = val.strip()
                if key and val:
                    results["headers"][key] = val
        
        # SSL info from stderr (curl -v outputs SSL to stderr)
        results["ssl_info"] = hdr_result["stderr"]
        
        # Extract response code
        for line in hdr_result["stdout"].split('\n'):
            if line.startswith('HTTP/'):
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        results["response_code"] = int(parts[1])
                    except:
                        pass
                break
        
        # Technologies from headers
        for hdr, val in results["headers"].items():
            hdr_lower = hdr.lower()
            if hdr_lower == 'server':
                results["technologies"].append(f"Server: {val}")
            elif hdr_lower == 'x-powered-by':
                results["technologies"].append(f"Powered-By: {val}")
            elif hdr_lower == 'x-aspnet-version':
                results["technologies"].append(f"ASP.NET: {val}")
            elif hdr_lower == 'x-generator':
                results["technologies"].append(f"Generator: {val}")
        
        # Cookies
        for hdr, val in results["headers"].items():
            if hdr.lower() == 'set-cookie':
                results["cookies"].append(val)
        
        # Content type
        results["content_type"] = results["headers"].get("Content-Type", results["headers"].get("content-type", ""))
    
    # =========================================================================
    # STEP 2: GET PAGE BODY (curl -sLk)
    # =========================================================================
    self.update_state(state="RUNNING", meta={"status": "Fetching page content...", "progress": 25})
    
    body_result = run_curl(
        ["-sLk", "-A", user_agent, "--connect-timeout", "15", "-m", "30", target_url],
        "Get page body"
    )
    
    html = ""
    if body_result["ok"]:
        html = body_result["stdout"]
        results["body_full"] = html
        results["body_preview"] = html[:5000]  # First 5KB
        results["content_length"] = len(html)
        
        # Detect technologies from HTML
        tech_patterns = [
            (r'wp-content|wordpress', 'WordPress'),
            (r'drupal|sites/all', 'Drupal'),
            (r'joomla', 'Joomla'),
            (r'shopify', 'Shopify'),
            (r'wix\.com', 'Wix'),
            (r'squarespace', 'Squarespace'),
            (r'react', 'React'),
            (r'vue\.js|vuejs', 'Vue.js'),
            (r'angular', 'Angular'),
            (r'next\.js|_next/', 'Next.js'),
            (r'nuxt', 'Nuxt.js'),
            (r'laravel', 'Laravel'),
            (r'django', 'Django'),
            (r'flask', 'Flask'),
            (r'express', 'Express.js'),
            (r'bootstrap', 'Bootstrap'),
            (r'tailwind', 'Tailwind CSS'),
            (r'jquery', 'jQuery'),
            (r'cloudflare', 'Cloudflare'),
            (r'aws|amazonaws', 'AWS'),
            (r'google-analytics|gtag', 'Google Analytics'),
        ]
        html_lower = html.lower()
        for pattern, tech in tech_patterns:
            if re.search(pattern, html_lower):
                if tech not in results["technologies"]:
                    results["technologies"].append(tech)
    
    # =========================================================================
    # STEP 3: EXTRACT ENDPOINTS FROM HTML
    # =========================================================================
    self.update_state(state="RUNNING", meta={"status": "Extracting endpoints...", "progress": 40})
    
    if html:
        endpoints = set()
        
        # href links
        for match in re.findall(r'href=["\']([^"\']+)["\']', html, re.I):
            endpoints.add(match)
        
        # src attributes
        for match in re.findall(r'src=["\']([^"\']+)["\']', html, re.I):
            endpoints.add(match)
        
        # Form actions
        for match in re.findall(r'action=["\']([^"\']+)["\']', html, re.I):
            endpoints.add(match)
        
        # API paths in JS
        for match in re.findall(r'["\']/(api|v1|v2|graphql)[^"\']*["\']', html, re.I):
            endpoints.add('/' + match if not match.startswith('/') else match)
        
        # fetch/axios URLs
        for match in re.findall(r'fetch\(["\']([^"\']+)["\']', html, re.I):
            endpoints.add(match)
        
        # Filter and categorize
        internal_endpoints = []
        external_endpoints = []
        
        for ep in endpoints:
            # Skip noise
            if any(x in ep.lower() for x in ['javascript:', 'data:', 'mailto:', '#', 'void(0)']):
                continue
            if ep.endswith(('.css', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf')):
                continue
            
            if ep.startswith('/') or ep.startswith(base_url):
                internal_endpoints.append(ep)
            elif ep.startswith('http'):
                external_endpoints.append(ep)
        
        results["endpoints"] = {
            "internal": sorted(list(set(internal_endpoints)))[:100],
            "external": sorted(list(set(external_endpoints)))[:50]
        }
        
        # Extract forms
        form_matches = re.findall(r'<form[^>]*>(.*?)</form>', html, re.I | re.DOTALL)
        for i, form_html in enumerate(form_matches[:10]):
            action_match = re.search(r'action=["\']([^"\']*)["\']', form_html, re.I)
            method_match = re.search(r'method=["\']([^"\']*)["\']', form_html, re.I)
            inputs = re.findall(r'<input[^>]*name=["\']([^"\']+)["\']', form_html, re.I)
            
            results["forms"].append({
                "action": action_match.group(1) if action_match else "/",
                "method": method_match.group(1).upper() if method_match else "GET",
                "inputs": inputs
            })
    
    # =========================================================================
    # STEP 4: CHECK COMMON PATHS
    # =========================================================================
    common_paths = [
        '/robots.txt', '/sitemap.xml', '/favicon.ico',
        '/.well-known/security.txt', '/humans.txt',
        '/api', '/api/', '/api/v1', '/api/v2', '/graphql',
        '/swagger.json', '/openapi.json', '/api-docs',
        '/admin', '/login', '/wp-admin', '/wp-login.php',
        '/.git/config', '/.env', '/package.json', '/composer.json',
        '/server-status', '/phpinfo.php', '/info.php',
        '/health', '/status', '/ping', '/version',
    ]
    
    total_paths = len(common_paths)
    for i, path in enumerate(common_paths):
        progress = 50 + int((i / total_paths) * 40)
        self.update_state(state="RUNNING", meta={"status": f"Checking {path}...", "progress": progress})
        
        url = base_url + path
        path_result = run_curl(
            ["-sk", "-o", "-", "-w", "\n__HTTP_CODE__:%{http_code}", 
             "--connect-timeout", "5", "-m", "10", "-A", user_agent, url],
            f"Check {path}"
        )
        
        if path_result["ok"]:
            output = path_result["stdout"]
            code = 0
            content = output
            
            if "__HTTP_CODE__:" in output:
                parts = output.rsplit("__HTTP_CODE__:", 1)
                content = parts[0].strip()
                try:
                    code = int(parts[1].strip())
                except:
                    pass
            
            # Only record if not 404
            if code != 404 and code > 0:
                # Check if it's a real file or a soft 404
                is_real = True
                if code == 200:
                    content_lower = content.lower()
                    if any(x in content_lower for x in ['not found', 'page not found', '404', 'does not exist']):
                        is_real = False
                
                if is_real:
                    results["paths_checked"][path] = {
                        "status": code,
                        "size": len(content),
                        "preview": content[:500] if code == 200 else ""
                    }
    
    # =========================================================================
    # STEP 5: BUILD OUTPUT
    # =========================================================================
    self.update_state(state="RUNNING", meta={"status": "Building results...", "progress": 95})
    
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()
    results["duration"] = duration
    results["end_time"] = end_time.isoformat()
    
    # Build human-readable stdout
    lines = [
        "╔══════════════════════════════════════════════════════════════╗",
        f"║  CURL RECON: {target_url[:50]}",
        f"║  Duration: {duration:.1f}s | Commands: {len(results['curl_commands'])}",
        "╚══════════════════════════════════════════════════════════════╝",
        "",
        "═══════════════════════════════════════════════════════════════",
        "📋 HTTP RESPONSE",
        "═══════════════════════════════════════════════════════════════",
        f"Status Code: {results['response_code']}",
        f"Content-Type: {results['content_type']}",
        f"Content-Length: {results['content_length']} bytes",
        "",
    ]
    
    # Headers section
    if results["headers"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("📨 HTTP HEADERS")
        lines.append("═══════════════════════════════════════════════════════════════")
        for hdr, val in sorted(results["headers"].items()):
            lines.append(f"  {hdr}: {val[:80]}")
        lines.append("")
    
    # Cookies
    if results["cookies"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("🍪 COOKIES")
        lines.append("═══════════════════════════════════════════════════════════════")
        for cookie in results["cookies"]:
            lines.append(f"  {cookie[:100]}")
        lines.append("")
    
    # Technologies
    if results["technologies"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("🔧 TECHNOLOGIES DETECTED")
        lines.append("═══════════════════════════════════════════════════════════════")
        for tech in results["technologies"]:
            lines.append(f"  • {tech}")
        lines.append("")
    
    # Endpoints
    if results.get("endpoints"):
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("🔗 ENDPOINTS FOUND")
        lines.append("═══════════════════════════════════════════════════════════════")
        if results["endpoints"].get("internal"):
            lines.append(f"  Internal ({len(results['endpoints']['internal'])} found):")
            for ep in results["endpoints"]["internal"][:30]:
                lines.append(f"    → {ep[:70]}")
            if len(results["endpoints"]["internal"]) > 30:
                lines.append(f"    ... +{len(results['endpoints']['internal']) - 30} more")
        if results["endpoints"].get("external"):
            lines.append(f"  External ({len(results['endpoints']['external'])} found):")
            for ep in results["endpoints"]["external"][:10]:
                lines.append(f"    → {ep[:70]}")
        lines.append("")
    
    # Forms
    if results["forms"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("📝 FORMS FOUND")
        lines.append("═══════════════════════════════════════════════════════════════")
        for i, form in enumerate(results["forms"], 1):
            lines.append(f"  Form #{i}: {form['method']} → {form['action']}")
            lines.append(f"    Inputs: {', '.join(form['inputs'][:10])}")
        lines.append("")
    
    # Paths checked
    found_paths = {k: v for k, v in results["paths_checked"].items() if v["status"] in [200, 301, 302, 401, 403]}
    if found_paths:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("📁 PATHS DISCOVERED")
        lines.append("═══════════════════════════════════════════════════════════════")
        for path, info in found_paths.items():
            status_icon = "✓" if info["status"] == 200 else "⚠" if info["status"] in [401, 403] else "→"
            lines.append(f"  {status_icon} {path} [{info['status']}] ({info['size']} bytes)")
            if info.get("preview"):
                preview = info["preview"][:100].replace('\n', ' ').strip()
                lines.append(f"      {preview}...")
        lines.append("")
    
    # SSL Info snippet
    if results["ssl_info"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("🔐 SSL/TLS INFO")
        lines.append("═══════════════════════════════════════════════════════════════")
        ssl_lines = results["ssl_info"].split('\n')
        for sl in ssl_lines:
            if any(x in sl for x in ['SSL', 'TLS', 'certificate', 'issuer', 'subject', 'expire']):
                lines.append(f"  {sl.strip()[:80]}")
        lines.append("")
    
    # Page body preview
    if results["body_preview"]:
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("📄 PAGE BODY PREVIEW (first 2000 chars)")
        lines.append("═══════════════════════════════════════════════════════════════")
        preview = results["body_preview"][:2000].replace('\r', '')
        for line in preview.split('\n')[:50]:
            lines.append(f"  {line[:100]}")
        if len(results["body_full"]) > 2000:
            lines.append(f"  ... [{len(results['body_full']) - 2000} more bytes]")
        lines.append("")
    
    # Summary
    lines.append("═══════════════════════════════════════════════════════════════")
    lines.append("📊 SUMMARY")
    lines.append("═══════════════════════════════════════════════════════════════")
    lines.append(f"  • Response Code: {results['response_code']}")
    lines.append(f"  • Headers: {len(results['headers'])}")
    lines.append(f"  • Technologies: {len(results['technologies'])}")
    lines.append(f"  • Endpoints: {len(results.get('endpoints', {}).get('internal', [])) + len(results.get('endpoints', {}).get('external', []))}")
    lines.append(f"  • Forms: {len(results['forms'])}")
    lines.append(f"  • Paths Found: {len(found_paths)}")
    lines.append(f"  • Cookies: {len(results['cookies'])}")
    lines.append("═══════════════════════════════════════════════════════════════")
    
    results["stdout"] = "\n".join(lines)
    
    return results
