"""
Cyber security tools - OS/System operations.
These tools require admin/cyber role to execute.
"""
import subprocess
import socket
import platform
import os
import asyncio
from typing import Dict, Any, List, Optional
import asyncio
import socket
from typing import Dict, Any


async def run_command(cmd: List[str], timeout: int = 30) -> Dict[str, Any]:
    """Run a shell command safely with timeout."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return {
            "success": proc.returncode == 0,
            "stdout": stdout.decode("utf-8", errors="replace"),
            "stderr": stderr.decode("utf-8", errors="replace"),
            "returncode": proc.returncode,
        }
    except asyncio.TimeoutError:
        proc.kill()
        return {"success": False, "error": "Command timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


async def vuln_scan(target: str, ports: str = "80,443,22") -> Dict[str, Any]:
    """
    Run nmap vulnerability scan with --script vuln.
    
    Usage examples:
        await vuln_scan("10.10.11.242")                    # scan common ports
        await vuln_scan("10.10.11.242", "80,443")          # specific ports
        await vuln_scan("10.10.11.242", "all")             # all ports (slow!)
    """
    # Clean target - remove protocol, trailing slashes, paths
    target = target.strip()
    target = target.replace("http://", "").replace("https://", "")
    target = target.rstrip("/")
    target = target.split("/")[0]  # Remove any path
    target = target.split(":")[0]  # Remove any port in URL
    
    if not target:
        return {"error": "No target specified", "target": target}
    
    try:
        ip = socket.gethostbyname(target)
    except Exception as e:
        return {"error": f"Cannot resolve target: {target}", "target": target}
    
    # Build port argument
    if "all" in ports.lower():
        port_arg = "-p-"
    else:
        port_arg = f"-p{ports}"
    
    cmd = ["nmap", port_arg, "--script", "vuln", "-sV", "-v", target]
    
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=900)  # 15 min for vuln scans
        
        output = stdout.decode() + stderr.decode()
        
        # Parse vulnerabilities found
        vulns = []
        current_vuln = None
        
        for line in output.splitlines():
            # Look for CVE mentions
            if "CVE-" in line.upper():
                import re
                cves = re.findall(r'CVE-\d{4}-\d+', line, re.IGNORECASE)
                for cve in cves:
                    if cve not in [v.get('cve') for v in vulns]:
                        vulns.append({"cve": cve.upper(), "line": line.strip()})
            
            # Look for VULNERABLE keyword
            if "VULNERABLE" in line.upper():
                vulns.append({"type": "vulnerable", "line": line.strip()})
        
        return {
            "target": target,
            "ip": ip,
            "scanner": "nmap --script vuln",
            "tool": "vuln_scan",
            "command": " ".join(cmd),
            "vulnerabilities": vulns,
            "vuln_count": len(vulns),
            "raw_output": output,
            "summary": f"{len(vulns)} potential vulnerabilities found"
        }
    
    except asyncio.TimeoutError:
        return {"error": "Vulnerability scan timed out (15 min limit)"}
    except Exception as e:
        return {"error": f"Scan failed: {str(e)}"}


async def port_scan(target: str, ports: str = "22,80,443,8080,3306,5432") -> Dict[str, Any]:
    """
    REAL Nmap-powered port scanner with verbose output.
    
    Usage examples:
        await port_scan("10.10.11.242")                    # default scan
        await port_scan("10.10.11.242", "1-65535")         # full ports
        await port_scan("10.10.11.242", "-sC -sV -p-")     # classic HTB
        await port_scan("10.10.11.242", "-sU --top-ports 100")  # UDP
    """
    # Clean target - remove protocol, trailing slashes, paths
    target = target.strip()
    target = target.replace("http://", "").replace("https://", "")
    target = target.rstrip("/")
    target = target.split("/")[0]  # Remove any path
    target = target.split(":")[0]  # Remove any port in URL
    
    if not target:
        return {"error": "No target specified", "target": target}
    
    try:
        ip = socket.gethostbyname(target)
    except Exception as e:
        return {"error": f"Cannot resolve target: {target}", "target": target}

    # If user passed actual nmap args → use them directly
    if ports.strip().startswith("-"):
        nmap_args = ports.split()
    else:
        # Parse port list and build nmap args
        if "all" in ports.lower() or "full" in ports.lower():
            nmap_args = ["-p-", "-sC", "-sV", "-v"]
        elif "udp" in ports.lower():
            nmap_args = ["-sU", "--top-ports", "100", "-sV", "-v"]
        elif "top" in ports.lower():
            nmap_args = ["--top-ports", "1000", "-sC", "-sV", "-v"]
        else:
            # Parse port list like "22,80,443" or "1-1000"
            port_list = []
            for p in ports.split(","):
                p = p.strip()
                if "-" in p:
                    port_list.append(p)  # Keep range as-is
                elif p.isdigit():
                    port_list.append(p)
            ports_arg = ",".join(port_list) if port_list else "22,80,443,8080"
            nmap_args = ["-p", ports_arg, "-sC", "-sV", "-v"]

    # Final command: nmap -sC -sV -v <target>
    cmd = ["nmap"] + nmap_args + [target]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=600)

        output = stdout.decode() + stderr.decode()

        # Parse open ports from verbose output
        open_ports = []
        import re
        
        for line in output.splitlines():
            line = line.strip()
            
            # Skip non-port lines
            if not line or line.startswith('#') or line.startswith('|'):
                continue
            
            # Match the standard nmap port table format:
            # "22/tcp   open  ssh     OpenSSH 8.9p1"
            # "8080/tcp open  http    Uvicorn"
            match = re.match(r'^(\d+)/(tcp|udp)\s+open\s+(\S+)\s*(.*)?$', line)
            if match:
                port = int(match.group(1))
                proto = match.group(2)
                service = match.group(3)
                version = match.group(4).strip() if match.group(4) else ""
                open_ports.append({
                    "port": port,
                    "protocol": proto,
                    "service": service,
                    "version": version
                })

        return {
            "target": target,
            "ip": ip,
            "scanner": "nmap",
            "tool": "port_scan",
            "command": " ".join(cmd),
            "open_ports": open_ports,
            "raw_output": output,
            "summary": f"{len(open_ports)} open ports found"
        }

    except FileNotFoundError:
        return {"error": "nmap not found — install it: sudo apt install nmap"}
    except asyncio.TimeoutError:
        return {"error": "Nmap scan timed out (10 min)"}
    except Exception as e:
        return {"error": f"Scan failed: {str(e)}"}


async def process_list(filter_name: Optional[str] = None) -> Dict[str, Any]:
    """
    List running processes.
    
    Args:
        filter_name: Optional process name to filter by
    """
    system = platform.system()
    
    if system == "Darwin" or system == "Linux":
        cmd = ["ps", "aux"]
    elif system == "Windows":
        cmd = ["tasklist"]
    else:
        return {"error": f"Unsupported OS: {system}"}
    
    result = await run_command(cmd)
    
    if not result["success"]:
        return result
    
    lines = result["stdout"].strip().split("\n")
    
    if filter_name:
        lines = [l for l in lines if filter_name.lower() in l.lower()]
    
    # Limit output to prevent flooding
    if len(lines) > 50:
        lines = lines[:50] + [f"... and {len(lines) - 50} more processes"]
    
    return {
        "success": True,
        "process_count": len(lines) - 1,  # Exclude header
        "processes": lines,
    }


async def network_info() -> Dict[str, Any]:
    """Get network interface information."""
    system = platform.system()
    
    if system == "Darwin":
        cmd = ["ifconfig"]
    elif system == "Linux":
        cmd = ["ip", "addr"]
    elif system == "Windows":
        cmd = ["ipconfig", "/all"]
    else:
        return {"error": f"Unsupported OS: {system}"}
    
    result = await run_command(cmd)
    
    if not result["success"]:
        return result
    
    # Parse basic info
    info = {
        "success": True,
        "hostname": socket.gethostname(),
        "raw_output": result["stdout"][:2000],  # Limit output
    }
    
    # Try to get local IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        info["local_ip"] = s.getsockname()[0]
        s.close()
    except Exception:
        info["local_ip"] = "unknown"
    
    return info


async def system_info() -> Dict[str, Any]:
    """Get system information."""
    return {
        "success": True,
        "platform": platform.platform(),
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "hostname": socket.gethostname(),
        "python_version": platform.python_version(),
    }


async def netstat(show_listening: bool = True) -> Dict[str, Any]:
    """Show network connections and listening ports."""
    system = platform.system()
    
    if system == "Darwin":
        # macOS: use lsof for better output, or netstat -an
        if show_listening:
            # Use lsof to show listening ports with process info
            cmd = ["lsof", "-i", "-P", "-n"]
        else:
            cmd = ["netstat", "-an"]
    elif system == "Linux":
        cmd = ["netstat", "-tulpn"] if show_listening else ["netstat", "-an"]
    elif system == "Windows":
        cmd = ["netstat", "-an"]
    else:
        return {"error": f"Unsupported OS: {system}"}
    
    result = await run_command(cmd, timeout=15)
    
    if not result["success"]:
        # Fallback for macOS
        if system == "Darwin":
            result = await run_command(["netstat", "-an"], timeout=15)
        # Try ss on Linux if netstat not available
        elif system == "Linux":
            result = await run_command(["ss", "-tulpn"])
    
    if not result["success"]:
        return result
    
    lines = result["stdout"].strip().split("\n")
    
    # Filter for listening ports if requested
    if show_listening:
        if system == "Darwin":
            # lsof output - filter for LISTEN
            lines = [l for l in lines if "LISTEN" in l or "COMMAND" in l]
        else:
            lines = [l for l in lines if "LISTEN" in l or "Active" in l or "Proto" in l]
    
    # Limit output
    if len(lines) > 100:
        lines = lines[:100] + [f"... and {len(lines) - 100} more connections"]
    
    return {
        "success": True,
        "connections": lines,
        "os": system,
    }


async def dns_lookup(domain: str) -> Dict[str, Any]:
    """Perform DNS lookup for a domain."""
    try:
        # Get all IPs for domain
        ips = socket.gethostbyname_ex(domain)
        
        result = {
            "success": True,
            "domain": domain,
            "hostname": ips[0],
            "aliases": ips[1],
            "addresses": ips[2],
        }
        
        # Try reverse DNS
        for ip in ips[2][:3]:  # Limit to first 3
            try:
                reverse = socket.gethostbyaddr(ip)
                result.setdefault("reverse_dns", {})[ip] = reverse[0]
            except socket.herror:
                pass
        
        return result
        
    except socket.gaierror as e:
        return {"success": False, "error": str(e), "domain": domain}


async def whois_lookup(target: str) -> Dict[str, Any]:
    """Perform WHOIS lookup (requires whois command)."""
    result = await run_command(["whois", target], timeout=15)
    
    if not result["success"]:
        return {"error": "WHOIS lookup failed or whois command not available"}
    
    # Limit output
    output = result["stdout"][:3000]
    if len(result["stdout"]) > 3000:
        output += "\n... (truncated)"
    
    return {
        "success": True,
        "target": target,
        "whois": output,
    }


# Tool registry
CYBER_TOOLS = {
    "port_scan": {
        "function": port_scan,
        "description": "Scan ports on a target host using nmap",
        "params": {"target": "str", "ports": "str (optional, default: common ports)"},
        "requires_role": ["admin", "cyber"],
    },
    "vuln_scan": {
        "function": vuln_scan,
        "description": "Run nmap vulnerability scan with --script vuln to find CVEs",
        "params": {"target": "str", "ports": "str (optional, default: 80,443,22)"},
        "requires_role": ["admin", "cyber"],
    },
    "process_list": {
        "function": process_list,
        "description": "List running processes on the system",
        "params": {"filter_name": "str (optional)"},
        "requires_role": ["admin", "cyber"],
    },
    "network_info": {
        "function": network_info,
        "description": "Get network interface information",
        "params": {},
        "requires_role": ["admin", "cyber"],
    },
    "system_info": {
        "function": system_info,
        "description": "Get system/OS information",
        "params": {},
        "requires_role": ["admin", "cyber"],
    },
    "netstat": {
        "function": netstat,
        "description": "Show network connections and listening ports",
        "params": {"show_listening": "bool (optional, default: True)"},
        "requires_role": ["admin", "cyber"],
    },
    "dns_lookup": {
        "function": dns_lookup,
        "description": "Perform DNS lookup for a domain",
        "params": {"domain": "str"},
        "requires_role": ["admin", "cyber", "researcher"],
    },
    "whois": {
        "function": whois_lookup,
        "description": "Perform WHOIS lookup for a domain or IP",
        "params": {"target": "str"},
        "requires_role": ["admin", "cyber", "researcher"],
    },
}


async def execute_tool(tool_name: str, user_roles: List[str], **kwargs) -> Dict[str, Any]:
    """
    Execute a cyber tool if user has permission.
    
    Args:
        tool_name: Name of the tool to execute
        user_roles: List of user's roles
        **kwargs: Tool parameters
    
    Returns:
        Tool result or error dict
    """
    if tool_name not in CYBER_TOOLS:
        return {"error": f"Unknown tool: {tool_name}", "available": list(CYBER_TOOLS.keys())}
    
    tool = CYBER_TOOLS[tool_name]
    required_roles = tool["requires_role"]
    
    # Check permission
    if not any(role in required_roles for role in user_roles):
        return {
            "error": "Permission denied",
            "tool": tool_name,
            "required_roles": required_roles,
            "your_roles": user_roles,
        }
    
    # Execute tool
    try:
        result = await tool["function"](**kwargs)
        result["tool"] = tool_name
        return result
    except Exception as e:
        return {"error": str(e), "tool": tool_name}


def get_available_tools(user_roles: List[str]) -> Dict[str, Any]:
    """Get list of tools available to user based on roles."""
    available = {}
    for name, tool in CYBER_TOOLS.items():
        if any(role in tool["requires_role"] for role in user_roles):
            available[name] = {
                "description": tool["description"],
                "params": tool["params"],
            }
    return available
