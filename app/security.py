import os
from typing import Optional, Dict, Any
import time
import jwt


# JWT configuration
A2A_JWT_SECRET = os.getenv("A2A_JWT_SECRET", "dev-secret-please-change")
A2A_JWT_ALG = "HS256"
DEFAULT_EXP = int(os.getenv("A2A_JWT_EXP", str(60 * 60 * 24 * 7)))  # default 7 days


def create_token(subject: str, roles: list[str] | None = None, exp: int | None = None) -> str:
    """Create a JWT for `subject` (e.g. 'admin' or 'assistant') with `roles`.

    This is intended for local demo/test use only. In production issue tokens via a secure auth system.
    """
    if roles is None:
        roles = [subject]
    payload = {"sub": subject, "roles": roles, "iat": int(time.time())}
    payload["exp"] = int(time.time()) + (exp or DEFAULT_EXP)
    token = jwt.encode(payload, A2A_JWT_SECRET, algorithm=A2A_JWT_ALG)
    # PyJWT returns str for encode in modern versions
    return token


def verify_token(token: str) -> Optional[Dict[str, Any]]:
    """Verify a JWT and return payload dict or None if invalid/expired."""
    try:
        payload = jwt.decode(token, A2A_JWT_SECRET, algorithms=[A2A_JWT_ALG])
        return payload
    except Exception:
        return None


# Role-based routing rules used internally for A2A routing
# Analyst acts as PROXY between Cyber and Researcher
ALLOWED_TRANSITIONS: Dict[str, list[str]] = {
    "admin": ["assistant", "cyber", "researcher", "analyst", "admin"],
    "assistant": ["researcher", "cyber", "analyst", "assistant"],
    "researcher": ["analyst", "assistant"],
    "analyst": ["researcher", "assistant"],  # Analyst can route to Researcher for CVE lookups
    "cyber": ["analyst", "assistant"],
}


def role_allowed(sender_role: str, target_role: str) -> bool:
    allowed = ALLOWED_TRANSITIONS.get(sender_role, [])
    return target_role in allowed


# Demo tokens (use create_token to produce JWTs for dev/testing)
DEMO_TOKENS: Dict[str, str] = {
    name: create_token(name, roles=[name]) for name in ["admin", "assistant", "analyst", "researcher", "cyber"]
}


def get_demo_tokens() -> Dict[str, str]:
    return DEMO_TOKENS


def _derive_key(subject: str) -> bytes:
    """Derive a per-agent HMAC key from the master secret (demo only)."""
    import hmac, hashlib

    return hmac.new(A2A_JWT_SECRET.encode('utf-8'), subject.encode('utf-8'), hashlib.sha256).digest()


def build_agent_card(agent_id: str | None = None, name: str | None = None, role: str | None = None, trust_domain: str = "internal") -> dict:
    """Create a small agent card dictionary that can be attached to envelopes.

    This is a lightweight demo implementation inspired by the A2A.py sample.
    It includes a deterministic agent_id, a timestamp and a signature so hops can be
    verified later.
    """
    import time, uuid

    if agent_id is None:
        # agent_id can be a short randomized string
        agent_id = f"agent-{str(uuid.uuid4())[:8]}"

    card = {
        "agent_id": agent_id,
        "name": name or agent_id,
        "role": role or name or agent_id,
        "trust_domain": trust_domain,
        "ts": int(time.time()),
        "version": "a2a-card-v1",
    }
    sig = sign_agent_card(card)
    card["signature"] = sig
    return card


def sign_agent_card(card: dict) -> str:
    """Sign an agent-card dict using the per-agent HMAC key (demo-only).

    The signed content is deterministic using agent_id + ts + version.
    Returns the base64 signature string that is also stored in the card.
    """
    import hmac, hashlib, base64

    agent_id = card.get("agent_id", "")
    ts = str(card.get("ts", 0))
    version = card.get("version", "")
    canonical = f"{agent_id}|{ts}|{version}"
    key = _derive_key(agent_id)
    sig = hmac.new(key, canonical.encode("utf-8"), hashlib.sha256).digest()
    return base64.b64encode(sig).decode("ascii")


def verify_agent_card_dict(card: dict) -> bool:
    """Verify a card dict's signature using derived per-agent key.

    Returns True if the signature matches, False otherwise.
    """
    if not isinstance(card, dict):
        return False
    sig = card.get("signature")
    if not sig:
        return False
    # reconstruct canonical string
    agent_id = card.get("agent_id", "")
    ts = str(card.get("ts", 0))
    version = card.get("version", "")
    canonical = f"{agent_id}|{ts}|{version}"
    import hmac, hashlib, base64

    key = _derive_key(agent_id)
    expected = hmac.new(key, canonical.encode("utf-8"), hashlib.sha256).digest()
    try:
        return hmac.compare_digest(base64.b64encode(expected).decode("ascii"), sig)
    except Exception:
        return False


def sign_envelope(envelope: Dict[str, Any], signer: str) -> str:
    """Sign an envelope for the given signer (adds to envelope['signatures']).

    Returns the signature string.
    """
    import hmac, hashlib, base64

    if 'id' not in envelope:
        # ensure every envelope has a canonical id
        import uuid

        envelope['id'] = str(uuid.uuid4())

    # canonical string: id|from|to|task|ts
    canonical = f"{envelope.get('id')}|{envelope.get('from','')}|{envelope.get('to','')}|{envelope.get('task','')}|{int(time.time())}"
    key = _derive_key(signer)
    sig = hmac.new(key, canonical.encode('utf-8'), hashlib.sha256).digest()
    sig_b64 = base64.b64encode(sig).decode('ascii')
    s = {'signer': signer, 'signature': sig_b64, 'ts': int(time.time())}
    envelope.setdefault('signatures', []).append(s)
    return sig_b64


def verify_signature(envelope: Dict[str, Any], signer: str) -> bool:
    """Verify the most recent signature for signer matches derived key.

    This is a simple best-effort verification for demo purposes.
    """
    import hmac, hashlib, base64

    sigs = envelope.get('signatures', [])
    # find last signature by signer
    found = None
    for s in reversed(sigs):
        if s.get('signer') == signer:
            found = s
            break
    if not found:
        return False

    key = _derive_key(signer)
    canonical = f"{envelope.get('id')}|{envelope.get('from','')}|{envelope.get('to','')}|{envelope.get('task','')}|{found.get('ts',0)}"
    digest = hmac.new(key, canonical.encode('utf-8'), hashlib.sha256).digest()
    try:
        return hmac.compare_digest(base64.b64encode(digest).decode('ascii'), found.get('signature',''))
    except Exception:
        return False
