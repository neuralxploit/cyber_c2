"""
Database for C2 - Chat history only.
Uses SQLite for persistence.
"""
import os
import sqlite3
from typing import Optional, Dict, Any, List
from contextlib import contextmanager

# Database path
DB_PATH = os.getenv("A2A_DB_PATH", os.path.join(os.path.dirname(__file__), "../data/users.db"))


@contextmanager
def get_db():
    """Get database connection context manager."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    """Initialize database with chat_history table."""
    with get_db() as conn:
        cursor = conn.cursor()
        
        # Chat history table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS chat_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER DEFAULT 1,
                username TEXT NOT NULL DEFAULT 'admin',
                role TEXT NOT NULL,
                message TEXT NOT NULL,
                agent TEXT,
                message_type TEXT DEFAULT 'text',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Create index for faster queries
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_chat_history_user 
            ON chat_history(user_id, created_at DESC)
        """)
        
        conn.commit()


def authenticate_user(username: str, password: str) -> Optional[Dict[str, Any]]:
    """Authenticate user - only admin with key auth supported."""
    # Only key-based auth is used
    return None


def get_user_by_username(username: str) -> Optional[Dict[str, Any]]:
    """Get user by username - returns admin for key auth."""
    if username == "admin" or username == "cyber":
        return {
            "id": 1,
            "username": username,
            "role": "admin",
            "roles": "admin",
            "is_active": True
        }
    return None


def save_chat_message(user_id: int, username: str, role: str, message: str, agent: str = None, message_type: str = "text"):
    """Save a chat message to history."""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO chat_history (user_id, username, role, message, agent, message_type) 
               VALUES (?, ?, ?, ?, ?, ?)""",
            (user_id, username, role, message, agent, message_type)
        )
        conn.commit()
        return cursor.lastrowid


def get_chat_history(user_id: int = 1, limit: int = 50) -> List[Dict[str, Any]]:
    """Get chat history for user."""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """SELECT id, username, role, message, agent, message_type, created_at 
               FROM chat_history 
               WHERE user_id = ? 
               ORDER BY created_at DESC 
               LIMIT ?""",
            (user_id, limit)
        )
        rows = cursor.fetchall()
        return [dict(row) for row in reversed(rows)]


def clear_chat_history(user_id: int = 1):
    """Clear chat history for user."""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM chat_history WHERE user_id = ?", (user_id,))
        conn.commit()
