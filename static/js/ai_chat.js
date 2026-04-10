/**
 * Global AI Chat Module - Works across all terminals
 * Supports: BITS Terminal, MSF PTY, Agent PTY
 */

// ============================================================================
// AI STATE
// ============================================================================
let aiAvailable = false;
let aiOutputBuffer = [];  // Store terminal output for AI context
const MAX_AI_BUFFER = 50000;  // Max chars to keep
let aiPanelVisible = false;

// ============================================================================
// INIT
// ============================================================================
async function initAIChat() {
    await checkAIStatus();
    setupAIEventListeners();
    console.log('[AI] Chat module initialized, available:', aiAvailable);
}

function setupAIEventListeners() {
    const aiInput = document.getElementById('aiInput');
    if (aiInput) {
        aiInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendAIMessage();
            }
        });
    }
}

// ============================================================================
// AI STATUS
// ============================================================================
async function checkAIStatus() {
    try {
        const token = localStorage.getItem('c2_token') || localStorage.getItem('token');
        const resp = await fetch('/api/ai/status', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (resp.ok) {
            const data = await resp.json();
            aiAvailable = data.available;
            const badge = document.getElementById('aiModelBadge');
            if (badge) {
                badge.textContent = data.model ? data.model.substring(0, 20) : 'No model';
            }
            return data;
        }
    } catch (e) {
        console.warn('[AI] Status check failed:', e);
    }
    return { available: false };
}

// ============================================================================
// AI PANEL TOGGLE
// ============================================================================
function toggleAIPanel() {
    const panel = document.getElementById('aiPanel') || document.getElementById('ptyAIPanel') || document.getElementById('globalAIPanel');
    if (!panel) {
        console.warn('[AI] No AI panel found');
        return;
    }
    
    panel.classList.toggle('collapsed');
    aiPanelVisible = !panel.classList.contains('collapsed');
    
    // Re-fit terminals when panel toggles
    setTimeout(() => {
        if (typeof msfPtyFitAddon !== 'undefined' && msfPtyFitAddon) msfPtyFitAddon.fit();
        if (typeof ptyFitAddon !== 'undefined' && ptyFitAddon) ptyFitAddon.fit();
    }, 300);
}

// Legacy function names for compatibility
function togglePtyAI() { toggleAIPanel(); }

// ============================================================================
// CAPTURE TERMINAL OUTPUT
// ============================================================================
function captureTerminalOutput(text) {
    if (!text) return;
    aiOutputBuffer.push(text);
    // Trim buffer if too large
    const totalLen = aiOutputBuffer.join('').length;
    if (totalLen > MAX_AI_BUFFER) {
        while (aiOutputBuffer.join('').length > MAX_AI_BUFFER * 0.8) {
            aiOutputBuffer.shift();
        }
    }
}

function getRecentOutput(maxChars = 15000) {
    const output = aiOutputBuffer.join('');
    return output.slice(-maxChars);
}

function clearAIBuffer() {
    aiOutputBuffer = [];
}

// ============================================================================
// AI MESSAGES
// ============================================================================
function addAIMessage(content, role = 'assistant') {
    const chat = document.getElementById('aiChat');
    if (!chat) return;
    
    const msg = document.createElement('div');
    msg.className = `ai-message ${role}`;
    
    // Parse markdown-like formatting
    let html = content
        .replace(/```([\s\S]*?)```/g, '<pre>$1</pre>')
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/🔴/g, '<span style="color:#ff4444">🔴</span>')
        .replace(/✅/g, '<span style="color:#00ff00">✅</span>')
        .replace(/⚠️/g, '<span style="color:#ffaa00">⚠️</span>')
        .replace(/\n/g, '<br>');
    
    msg.innerHTML = html;
    chat.appendChild(msg);
    chat.scrollTop = chat.scrollHeight;
}

function showAILoading(show) {
    const chat = document.getElementById('aiChat');
    if (!chat) return;
    
    let loader = document.getElementById('aiLoader');
    
    if (show && !loader) {
        loader = document.createElement('div');
        loader.id = 'aiLoader';
        loader.className = 'ai-loading';
        loader.innerHTML = '<div class="spinner"></div> AI is thinking...';
        chat.appendChild(loader);
        chat.scrollTop = chat.scrollHeight;
    } else if (!show && loader) {
        loader.remove();
    }
}

function clearAIChat() {
    const chat = document.getElementById('aiChat');
    if (chat) {
        chat.innerHTML = '<div class="ai-message system">🤖 Chat cleared. AI Red Team Assistant ready.</div>';
    }
}

// ============================================================================
// AI API CALLS
// ============================================================================
async function sendAIMessage() {
    const input = document.getElementById('aiInput');
    if (!input) return;
    
    const message = input.value.trim();
    if (!message) return;
    
    // Show AI panel if hidden
    const panel = document.getElementById('aiPanel') || document.getElementById('ptyAIPanel') || document.getElementById('globalAIPanel');
    if (panel && panel.classList.contains('collapsed')) {
        panel.classList.remove('collapsed');
    }
    
    // Add user message
    addAIMessage(message, 'user');
    input.value = '';
    
    // Get recent terminal output for context
    const recentOutput = getRecentOutput(10000);
    
    showAILoading(true);
    
    try {
        const token = localStorage.getItem('c2_token') || localStorage.getItem('token');
        const resp = await fetch('/api/ai/analyze', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
                output: message,
                context: recentOutput ? `Recent terminal output:\n${recentOutput}` : '',
                mode: 'chat'
            })
        });
        
        showAILoading(false);
        
        if (resp.ok) {
            const data = await resp.json();
            if (data.success) {
                addAIMessage(data.analysis, 'assistant');
            } else {
                addAIMessage(`❌ Error: ${data.error}`, 'system');
            }
        } else {
            const errData = await resp.json().catch(() => ({}));
            addAIMessage(`❌ API Error: ${errData.error || resp.status}`, 'system');
        }
    } catch (e) {
        showAILoading(false);
        addAIMessage(`❌ Network error: ${e.message}`, 'system');
    }
}

async function analyzeCurrentOutput() {
    const recentOutput = getRecentOutput(15000);
    
    if (!recentOutput.trim()) {
        addAIMessage('No terminal output to analyze yet. Run some commands first!', 'system');
        return;
    }
    
    // Show AI panel if hidden
    const panel = document.getElementById('aiPanel') || document.getElementById('ptyAIPanel') || document.getElementById('globalAIPanel');
    if (panel && panel.classList.contains('collapsed')) {
        panel.classList.remove('collapsed');
    }
    
    addAIMessage('📊 Analyzing current terminal output...', 'user');
    showAILoading(true);
    
    try {
        const token = localStorage.getItem('c2_token') || localStorage.getItem('token');
        const resp = await fetch('/api/ai/analyze', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
                output: recentOutput,
                context: `Active terminal session`,
                mode: 'analyze'
            })
        });
        
        showAILoading(false);
        
        if (resp.ok) {
            const data = await resp.json();
            if (data.success) {
                addAIMessage(data.analysis, 'assistant');
            } else {
                addAIMessage(`❌ ${data.error}`, 'system');
            }
        } else {
            const errData = await resp.json().catch(() => ({}));
            addAIMessage(`❌ ${errData.error || `API Error ${resp.status}`}`, 'system');
        }
    } catch (e) {
        showAILoading(false);
        addAIMessage(`❌ ${e.message}`, 'system');
    }
}

async function aiQuickAction(action) {
    const prompts = {
        analyze: 'Analyze the current terminal output and identify any security findings, credentials, or opportunities.',
        privesc: 'Based on the system information, suggest specific privilege escalation techniques that might work. Include exact commands.',
        persist: 'Recommend persistence mechanisms suitable for this target. Consider the AV/EDR situation and suggest stealthy options with commands.',
        lateral: 'Suggest lateral movement options based on the current access level and network position. Include specific techniques and commands.',
        creds: 'What credential harvesting techniques should I try? Consider the current privileges and suggest specific commands.',
        exploit: 'What exploits or attack vectors should I try based on the system info? Include CVEs and commands.',
        evasion: 'How can I evade detection on this target? Suggest AV/EDR bypass techniques.',
        cleanup: 'What traces should I clean up after this session? Provide specific commands.'
    };
    
    const prompt = prompts[action];
    if (!prompt) return;
    
    // Show AI panel if hidden
    const panel = document.getElementById('aiPanel') || document.getElementById('ptyAIPanel') || document.getElementById('globalAIPanel');
    if (panel && panel.classList.contains('collapsed')) {
        panel.classList.remove('collapsed');
    }
    
    addAIMessage(prompt, 'user');
    
    const recentOutput = getRecentOutput(10000);
    showAILoading(true);
    
    try {
        const token = localStorage.getItem('c2_token') || localStorage.getItem('token');
        const resp = await fetch('/api/ai/analyze', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
                output: `${prompt}\n\nContext from terminal:\n${recentOutput}`,
                mode: 'chat'
            })
        });
        
        showAILoading(false);
        
        if (resp.ok) {
            const data = await resp.json();
            if (data.success) {
                addAIMessage(data.analysis, 'assistant');
            } else {
                addAIMessage(`❌ ${data.error}`, 'system');
            }
        }
    } catch (e) {
        showAILoading(false);
        addAIMessage(`❌ ${e.message}`, 'system');
    }
}

// ============================================================================
// INIT ON LOAD
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    // Delay init to let other scripts load
    setTimeout(initAIChat, 500);
});

// Export for module usage
if (typeof module !== 'undefined') {
    module.exports = {
        initAIChat,
        toggleAIPanel,
        sendAIMessage,
        analyzeCurrentOutput,
        aiQuickAction,
        clearAIChat,
        captureTerminalOutput,
        addAIMessage
    };
}
