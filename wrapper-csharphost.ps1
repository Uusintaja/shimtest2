<#
.SYNOPSIS
    CSharpHost release-candidate implementation of the ConPTY wrapper.

.DESCRIPTION
    PowerShell owns configuration loading, directory initialization, generic post-actions,
    JSON/summary output, and debug-friendly command-line switches.

    Embedded C# owns the native/ConPTY lifecycle: pseudo console creation, process startup,
    process waiting, signal routing, output/input pumping, timeout/kill, console close handling,
    hidden-window logoff/shutdown handling, and timing/lifecycle logs.

    Deployment model: single .ps1 file with embedded C# compiled at runtime via Add-Type.

.NOTES
    Target: Windows PowerShell 5.1, .NET Framework, Windows 10 1809+.
    Baseline: 0.2.0-rc1.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [switch]$Json,

    [switch]$NoSummary,

    [string]$JsonOutputPath = $null,

    [switch]$PauseOnExit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptRoot "src\common.ps1")

function Join-WrapperCommandLineArgs {
    param([object[]]$ArgumentList)
    # Do not name this parameter $Args. PowerShell has a built-in automatic variable $args;
    # using a parameter with the same effective name is confusing and caused argument loss
    # in Windows PowerShell 5.1 testing.
    if ($null -eq $ArgumentList -or @($ArgumentList).Count -eq 0) { return "" }
    $quoted = New-Object System.Collections.Generic.List[string]
    foreach ($argObj in @($ArgumentList)) {
        $arg = [string]$argObj
        if ($arg.Length -eq 0) { $quoted.Add('""'); continue }
        if ($arg -notmatch '[\s"]') { $quoted.Add($arg); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $arg.ToCharArray()) {
            if ($ch -eq '\\') { $bs++ }
            elseif ($ch -eq '"') {
                [void]$sb.Append(('\' * ($bs * 2 + 1)))
                [void]$sb.Append('"')
                $bs = 0
            }
            else {
                if ($bs -gt 0) { [void]$sb.Append(('\' * $bs)); $bs = 0 }
                [void]$sb.Append($ch)
            }
        }
        if ($bs -gt 0) { [void]$sb.Append(('\' * ($bs * 2))) }
        [void]$sb.Append('"')
        $quoted.Add($sb.ToString())
    }
    return ($quoted -join " ")
}

function Add-CSharpHostType {
    if ("CSharpWrapperHost_v020rc2dev.WrapperHost" -as [type]) { return }

    $cs = @'
using System;
using System.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Globalization;

namespace CSharpWrapperHost_v020rc2dev
{
    internal static class Native
    {
        public const int PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
        public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        public const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        public const uint WAIT_OBJECT_0 = 0x00000000;

        [StructLayout(LayoutKind.Sequential)]
        public struct COORD { public short X; public short Y; public COORD(short x, short y) { X = x; Y = y; } }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct STARTUPINFO
        {
            public Int32 cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public Int32 dwX;
            public Int32 dwY;
            public Int32 dwXSize;
            public Int32 dwYSize;
            public Int32 dwXCountChars;
            public Int32 dwYCountChars;
            public Int32 dwFillAttribute;
            public Int32 dwFlags;
            public Int16 wShowWindow;
            public Int16 cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }

        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, uint nSize);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr hObject);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToRead, out int lpNumberOfBytesRead, IntPtr lpOverlapped);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, IntPtr lpOverlapped);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern void ClosePseudoConsole(IntPtr hPC);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CreateProcessW(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr hProcess, out int lpExitCode);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetProcessShutdownParameters(uint dwLevel, uint dwFlags);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetProcessShutdownParameters(out uint lpdwLevel, out uint lpdwFlags);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate HandlerRoutine, bool Add);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern int GetCurrentThreadId();
        [DllImport("user32.dll", SetLastError = true)] public static extern bool PostThreadMessage(int idThread, uint Msg, IntPtr wParam, IntPtr lParam);
        public const uint WM_QUIT = 0x0012;
    }

    internal static class EncodingUtil
    {
        public static Encoding ResolveEncoding(string name)
        {
            if (String.IsNullOrWhiteSpace(name)) return Encoding.UTF8;
            string n = name.ToLowerInvariant().Replace("-", "");
            if (n == "utf8") return Encoding.UTF8;
            if (n == "unicode" || n == "utf16") return Encoding.Unicode;
            if (n == "ascii") return Encoding.ASCII;
            if (n == "default") return Encoding.Default;
            return Encoding.GetEncoding(name);
        }
    }

    public delegate bool ConsoleCtrlDelegate(uint ctrlType);
    public delegate bool ImmediateSignalDelegate(int ctrlType, long signalPerfTicks);

    public sealed class SignalEvent
    {
        public int Type;
        public long PerfTicks;
        public SignalEvent(int type, long perfTicks) { Type = type; PerfTicks = perfTicks; }
    }

    internal sealed class ConsoleSignalRouter : IDisposable
    {
        private static readonly object StaticLock = new object();
        private static ConsoleCtrlDelegate StaticHandlerRef;
        private static bool StaticHandlerInstalled;
        private static ConsoleSignalRouter Current;

        private readonly ConcurrentQueue<SignalEvent> signals = new ConcurrentQueue<SignalEvent>();
        private readonly ImmediateSignalDelegate immediateHandler;
        private readonly bool handleCtrlC;
        private readonly bool handleBreak;
        private readonly bool handleClose;
        private bool disposed;

        public ConsoleSignalRouter(ImmediateSignalDelegate immediateHandler, bool handleCtrlC, bool handleBreak, bool handleClose)
        {
            this.immediateHandler = immediateHandler;
            this.handleCtrlC = handleCtrlC;
            this.handleBreak = handleBreak;
            this.handleClose = handleClose;
        }

        public void Register()
        {
            lock (StaticLock)
            {
                if (Current != null)
                    throw new InvalidOperationException("Concurrent WrapperHost.Run calls in the same PowerShell process are not supported. Start a separate powershell.exe process for concurrent wrappers.");

                if (StaticHandlerRef == null)
                    StaticHandlerRef = new ConsoleCtrlDelegate(StaticHandler);

                if (!StaticHandlerInstalled)
                {
                    if (!Native.SetConsoleCtrlHandler(StaticHandlerRef, true))
                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "SetConsoleCtrlHandler failed");
                    StaticHandlerInstalled = true;
                }

                DrainSignals();
                Current = this;
            }
        }

        public bool TryDequeue(out SignalEvent signal)
        {
            return signals.TryDequeue(out signal);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            lock (StaticLock)
            {
                if (Object.ReferenceEquals(Current, this)) Current = null;
                DrainSignals();
            }
        }

        private void DrainSignals()
        {
            SignalEvent ignored;
            while (signals.TryDequeue(out ignored)) { }
        }

        private bool Handle(uint ctrlType, long signalPerfTicks)
        {
            if (disposed) return false;
            int sig = (int)ctrlType;

            // CTRL_CLOSE_EVENT/LOGOFF/SHUTDOWN are terminal best-effort events.
            // Logoff/shutdown may arrive either here or via the hidden-window WM_QUERYENDSESSION path.
            if ((sig == 2 && handleClose) || sig == 5 || sig == 6)
            {
                if (immediateHandler != null)
                {
                    try { return immediateHandler(sig, signalPerfTicks); }
                    catch { return true; }
                }
                return false;
            }

            signals.Enqueue(new SignalEvent(sig, signalPerfTicks));
            if (sig == 0) return handleCtrlC;
            if (sig == 1) return handleBreak;
            if (sig == 2) return handleClose;
            return false;
        }

        private static bool StaticHandler(uint ctrlType)
        {
            ConsoleSignalRouter router;
            lock (StaticLock) { router = Current; }
            if (router == null) return false;
            return router.Handle(ctrlType, Stopwatch.GetTimestamp());
        }
    }

    internal sealed class ShutdownWindowRouter : IDisposable
    {
        private sealed class SentinelWindow : System.Windows.Forms.NativeWindow
        {
            private readonly ImmediateSignalDelegate handler;
            public SentinelWindow(ImmediateSignalDelegate h)
            {
                handler = h;
                System.Windows.Forms.CreateParams cp = new System.Windows.Forms.CreateParams();
                cp.Caption = "ConPTY Wrapper Shutdown Sentinel";
                cp.ClassName = "STATIC";
                cp.X = 0; cp.Y = 0; cp.Width = 0; cp.Height = 0;
                cp.Style = 0;
                CreateHandle(cp);
            }

            protected override void WndProc(ref System.Windows.Forms.Message m)
            {
                const int WM_QUERYENDSESSION = 0x0011;
                const int WM_ENDSESSION = 0x0016;
                const long ENDSESSION_LOGOFF = unchecked((long)0x80000000);

                if (m.Msg == WM_QUERYENDSESSION)
                {
                    int sig = ((m.LParam.ToInt64() & ENDSESSION_LOGOFF) != 0) ? 5 : 6;
                    try { handler(sig, Stopwatch.GetTimestamp()); } catch { }
                    // Best-effort only: do not cancel logoff/shutdown.
                    m.Result = new IntPtr(1);
                    return;
                }
                if (m.Msg == WM_ENDSESSION)
                {
                    m.Result = IntPtr.Zero;
                    return;
                }
                base.WndProc(ref m);
            }
        }

        private readonly ImmediateSignalDelegate handler;
        private readonly bool enabled;
        private Thread thread;
        private int threadId;
        private ManualResetEvent ready;
        private bool disposed;

        public ShutdownWindowRouter(ImmediateSignalDelegate handler, bool enabled)
        {
            this.handler = handler;
            this.enabled = enabled;
        }

        public void Start(IDictionary config)
        {
            if (!enabled) return;
            ready = new ManualResetEvent(false);
            thread = new Thread(delegate()
            {
                SentinelWindow localWindow = null;
                try
                {
                    threadId = Native.GetCurrentThreadId();
                    localWindow = new SentinelWindow(handler);
                    ready.Set();
                    System.Windows.Forms.Application.Run();
                }
                catch
                {
                    try { if (ready != null) ready.Set(); } catch { }
                }
                finally
                {
                    try { if (localWindow != null) localWindow.DestroyHandle(); } catch { }
                }
            });
            thread.IsBackground = true;
            thread.Name = "ConPTY Wrapper Shutdown Sentinel Window";
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            bool readyOk = ready.WaitOne(1000);
            if (!readyOk)
            {
                try { WrapperHost.Log(config, "ShutdownWindowRouter start timed out before sentinel window became ready.", "WARN"); } catch { }
            }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            int id = threadId;
            Thread t = thread;
            try
            {
                if (id != 0) Native.PostThreadMessage(id, Native.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }
            try
            {
                if (t != null && t.IsAlive) t.Join(1000);
            }
            catch { }
            thread = null;
            threadId = 0;
            ready = null;
        }
    }

    internal sealed class ConptySession : IDisposable
    {
        private IntPtr hPC = IntPtr.Zero;
        private IntPtr inputWrite = IntPtr.Zero;
        private IntPtr outputRead = IntPtr.Zero;
        private IntPtr process = IntPtr.Zero;
        private IntPtr thread = IntPtr.Zero;
        private Thread readerThread;
        private volatile bool disposed;
        private readonly ConcurrentQueue<string> outputQueue = new ConcurrentQueue<string>();
        private readonly StringBuilder captured = new StringBuilder();
        private long stdoutBytes;
        private int outputLines;
        private int pid;
        private volatile bool outputEof;

        public int Pid { get { return pid; } }
        public long StdoutBytes { get { return Interlocked.Read(ref stdoutBytes); } }
        public int OutputLines { get { return Interlocked.CompareExchange(ref outputLines, 0, 0); } }
        public bool OutputEof { get { return outputEof; } }
        public bool OutputQueueIsEmpty { get { return outputQueue.IsEmpty; } }
        public string CapturedOutput { get { lock (captured) { return captured.ToString(); } } }

        private ConptySession() { }

        public static ConptySession Start(string appPath, string args, string workingDirectory, IDictionary env, bool inheritParentEnvironment, string outputEncodingName)
        {
            ConptySession s = new ConptySession();
            IntPtr inputRead = IntPtr.Zero, outputWrite = IntPtr.Zero, attrList = IntPtr.Zero, envBlock = IntPtr.Zero, hPcLocal = IntPtr.Zero;
            try
            {
                if (!Native.CreatePipe(out inputRead, out s.inputWrite, IntPtr.Zero, 0)) throw Win32("CreatePipe input failed");
                if (!Native.CreatePipe(out s.outputRead, out outputWrite, IntPtr.Zero, 0)) throw Win32("CreatePipe output failed");
                int hr = Native.CreatePseudoConsole(new Native.COORD(120, 30), inputRead, outputWrite, 0, out hPcLocal);
                if (hr != 0) throw new System.ComponentModel.Win32Exception(hr, "CreatePseudoConsole failed");
                s.hPC = hPcLocal;

                IntPtr size = IntPtr.Zero;
                Native.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
                attrList = Marshal.AllocHGlobal(size);
                if (!Native.InitializeProcThreadAttributeList(attrList, 1, 0, ref size)) throw Win32("InitializeProcThreadAttributeList failed");
                if (!Native.UpdateProcThreadAttribute(attrList, 0, (IntPtr)Native.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPcLocal, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) throw Win32("UpdateProcThreadAttribute(PSEUDOCONSOLE) failed");

                Native.STARTUPINFOEX si = new Native.STARTUPINFOEX();
                si.StartupInfo.cb = Marshal.SizeOf(typeof(Native.STARTUPINFOEX));
                si.lpAttributeList = attrList;

                string cmdline = QuoteArg(appPath);
                if (!String.IsNullOrWhiteSpace(args)) cmdline += " " + args;
                envBlock = BuildEnvironmentBlock(env, inheritParentEnvironment);
                Native.PROCESS_INFORMATION pi;
                bool ok = Native.CreateProcessW(appPath, cmdline, IntPtr.Zero, IntPtr.Zero, false, Native.EXTENDED_STARTUPINFO_PRESENT | Native.CREATE_UNICODE_ENVIRONMENT, envBlock, String.IsNullOrWhiteSpace(workingDirectory) ? null : workingDirectory, ref si, out pi);
                if (!ok) throw Win32("CreateProcessW failed: " + appPath);

                s.process = pi.hProcess; s.thread = pi.hThread; s.pid = pi.dwProcessId;
                if (inputRead != IntPtr.Zero) { Native.CloseHandle(inputRead); inputRead = IntPtr.Zero; }
                if (outputWrite != IntPtr.Zero) { Native.CloseHandle(outputWrite); outputWrite = IntPtr.Zero; }
                s.StartReader(outputEncodingName);
                return s;
            }
            catch { s.Dispose(); throw; }
            finally
            {
                if (attrList != IntPtr.Zero) { Native.DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); }
                if (envBlock != IntPtr.Zero) Marshal.FreeHGlobal(envBlock);
                if (inputRead != IntPtr.Zero) Native.CloseHandle(inputRead);
                if (outputWrite != IntPtr.Zero) Native.CloseHandle(outputWrite);
            }
        }

        private void StartReader(string encodingName)
        {
            Encoding enc = EncodingUtil.ResolveEncoding(encodingName);
            Decoder decoder = enc.GetDecoder();
            readerThread = new Thread(delegate()
            {
                byte[] buffer = new byte[4096];
                char[] chars = new char[8192];
                try
                {
                    while (!disposed)
                    {
                        int read;
                        bool ok = Native.ReadFile(outputRead, buffer, buffer.Length, out read, IntPtr.Zero);
                        if (!ok || read <= 0) break;
                        Interlocked.Add(ref stdoutBytes, read);
                        int charCount = decoder.GetChars(buffer, 0, read, chars, 0, false);
                        if (charCount > 0)
                        {
                            string text = new string(chars, 0, charCount);
                            outputQueue.Enqueue(text);
                            lock (captured) { captured.Append(text); }
                            for (int i = 0; i < text.Length; i++) if (text[i] == '\n') Interlocked.Increment(ref outputLines);
                        }
                    }
                    int flushCount = decoder.GetChars(new byte[0], 0, 0, chars, 0, true);
                    if (flushCount > 0)
                    {
                        string text = new string(chars, 0, flushCount);
                        outputQueue.Enqueue(text);
                        lock (captured) { captured.Append(text); }
                    }
                }
                catch (Exception ex) { outputQueue.Enqueue("\r\n[wrapper-reader-error] " + ex.Message + "\r\n"); }
                finally { outputEof = true; }
            });
            readerThread.IsBackground = true;
            readerThread.Name = "CSharpHost ConPTY output reader";
            readerThread.Start();
        }

        public bool TryDequeueOutput(out string text) { return outputQueue.TryDequeue(out text); }
        public void SendCtrlC() { WriteInputBytes(new byte[] { 0x03 }); }
        public void WriteInputString(string text, string encodingName) { WriteInputBytes(EncodingUtil.ResolveEncoding(encodingName).GetBytes(text)); }
        public void WriteInputBytes(byte[] bytes)
        {
            int written;
            if (!Native.WriteFile(inputWrite, bytes, bytes.Length, out written, IntPtr.Zero)) throw Win32("WriteFile input failed");
        }
        public bool WaitForExit(int milliseconds) { return process == IntPtr.Zero || Native.WaitForSingleObject(process, (uint)Math.Max(0, milliseconds)) == Native.WAIT_OBJECT_0; }
        public bool HasExited() { return WaitForExit(0); }
        public int GetExitCode() { int code; if (!Native.GetExitCodeProcess(process, out code)) throw Win32("GetExitCodeProcess failed"); return code; }
        public void Kill() { if (process != IntPtr.Zero && !HasExited()) Native.TerminateProcess(process, 0xFFFFFFFF); }

        public void ClosePseudoConsoleForOutputCompletion()
        {
            // Normal AppExited path only: after the child process has exited, close the input side
            // and HPCON to let the ConPTY output pipe reach EOF. Keep outputRead open so the reader
            // thread can drain remaining buffered output before Dispose closes the handle.
            if (inputWrite != IntPtr.Zero) { Native.CloseHandle(inputWrite); inputWrite = IntPtr.Zero; }
            if (hPC != IntPtr.Zero) { Native.ClosePseudoConsole(hPC); hPC = IntPtr.Zero; }
        }

        public bool WaitForOutputReaderExit(int milliseconds)
        {
            try { return readerThread == null || readerThread.Join(Math.Max(0, milliseconds)); }
            catch { return false; }
        }

        public void Dispose()
        {
            disposed = true;
            if (inputWrite != IntPtr.Zero) { Native.CloseHandle(inputWrite); inputWrite = IntPtr.Zero; }
            if (hPC != IntPtr.Zero) { Native.ClosePseudoConsole(hPC); hPC = IntPtr.Zero; }
            if (outputRead != IntPtr.Zero) { Native.CloseHandle(outputRead); outputRead = IntPtr.Zero; }
            if (thread != IntPtr.Zero) { Native.CloseHandle(thread); thread = IntPtr.Zero; }
            if (process != IntPtr.Zero) { Native.CloseHandle(process); process = IntPtr.Zero; }
        }

        private static Exception Win32(string message) { return new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), message); }
        private static string QuoteArg(string arg)
        {
            if (arg == null) return "\"\"";
            if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return arg;
            StringBuilder sb = new StringBuilder(); sb.Append('"'); int bs = 0;
            foreach (char c in arg)
            {
                if (c == '\\') bs++;
                else if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; }
                else { if (bs > 0) { sb.Append('\\', bs); bs = 0; } sb.Append(c); }
            }
            if (bs > 0) sb.Append('\\', bs * 2); sb.Append('"'); return sb.ToString();
        }
        private static IntPtr BuildEnvironmentBlock(IDictionary env, bool inherit)
        {
            SortedDictionary<string, string> map = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (inherit)
            {
                IDictionary current = Environment.GetEnvironmentVariables();
                foreach (DictionaryEntry de in current) map[Convert.ToString(de.Key)] = Convert.ToString(de.Value);
            }
            if (env != null)
            {
                foreach (DictionaryEntry de in env)
                {
                    string k = Convert.ToString(de.Key);
                    if (String.IsNullOrEmpty(k)) continue;
                    if (de.Value == null) map.Remove(k); // null means remove from child environment
                    else map[k] = Convert.ToString(de.Value) ?? String.Empty;
                }
            }
            StringBuilder sb = new StringBuilder();
            foreach (KeyValuePair<string, string> kv in map) sb.Append(kv.Key).Append('=').Append(kv.Value).Append('\0');
            sb.Append('\0');
            byte[] bytes = Encoding.Unicode.GetBytes(sb.ToString());
            IntPtr ptr = IntPtr.Zero;
            try
            {
                ptr = Marshal.AllocHGlobal(bytes.Length);
                Marshal.Copy(bytes, 0, ptr, bytes.Length);
                IntPtr result = ptr;
                ptr = IntPtr.Zero;
                return result;
            }
            finally
            {
                if (ptr != IntPtr.Zero) Marshal.FreeHGlobal(ptr);
            }
        }
    }

    internal sealed class ResultState
    {
        private readonly ConcurrentDictionary<string, object> values = new ConcurrentDictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentQueue<string> errors = new ConcurrentQueue<string>();
        private int ctrlCGuard;

        public object this[string key]
        {
            get { object value; return values.TryGetValue(key, out value) ? value : null; }
            set { values[key] = value; }
        }

        public static ResultState Create(IDictionary config, DateTime start)
        {
            ResultState r = new ResultState();
            r.values["WrapperVersion"] = S(config, "WrapperVersion", "unknown");
            r.values["Implementation"] = "CSharpHost";
            r.values["AppPath"] = S(config, "AppPath", null);
            r.values["AppPid"] = null;
            r.values["StartTime"] = start;
            r.values["EndTime"] = null;
            r.values["DurationMs"] = null;
            r.values["TriggerReason"] = "Unknown";
            r.values["FinalState"] = "Unknown";
            r.values["AppExitCode"] = null;
            r.values["WasKilled"] = false;
            r.values["TimedOut"] = false;
            r.values["CtrlCSentCount"] = 0;
            r.values["CtrlCUnresponsiveCount"] = 0;
            r.values["LastCtrlCSentAt"] = null;
            r.values["CloseEventReceived"] = false;
            r.values["ShutdownEventReceived"] = false;
            r.values["StdoutBytes"] = 0L;
            r.values["OutputLines"] = 0;
            r.values["PostActions"] = new object[0];
            r.values["CapturedOutput"] = "";
            return r;
        }

        public bool TryBeginCtrlCAttempt()
        {
            return Interlocked.CompareExchange(ref ctrlCGuard, 1, 0) == 0;
        }

        public void ResetCtrlCGuard()
        {
            Interlocked.Exchange(ref ctrlCGuard, 0);
        }

        public void RecordCtrlCSent(DateTimeOffset sentAt)
        {
            values.AddOrUpdate("CtrlCSentCount", 1, delegate(string key, object oldValue) { return Convert.ToInt32(oldValue) + 1; });
            values["LastCtrlCSentAt"] = sentAt.ToString("o", CultureInfo.InvariantCulture);
        }

        public void RecordCtrlCUnresponsive()
        {
            values.AddOrUpdate("CtrlCUnresponsiveCount", 1, delegate(string key, object oldValue) { return Convert.ToInt32(oldValue) + 1; });
        }

        public bool TrySetTriggerReason(string reason)
        {
            object current;
            if (!values.TryGetValue("TriggerReason", out current) || current == null || Convert.ToString(current) == "Unknown")
            {
                values["TriggerReason"] = reason;
                return true;
            }
            return false;
        }

        public bool IsTriggerReason(string reason)
        {
            object current;
            return values.TryGetValue("TriggerReason", out current) && Convert.ToString(current) == reason;
        }

        public bool IsFinalState(string state)
        {
            object current;
            return values.TryGetValue("FinalState", out current) && Convert.ToString(current) == state;
        }

        public void AddError(string msg)
        {
            if (msg != null) errors.Enqueue(msg);
        }

        public Hashtable ToHashtable()
        {
            Hashtable ht = new Hashtable(StringComparer.OrdinalIgnoreCase);
            foreach (KeyValuePair<string, object> kv in values) ht[kv.Key] = kv.Value;
            ht["Errors"] = errors.ToArray();
            return ht;
        }

        public void Complete(DateTime start)
        {
            DateTime end = DateTime.Now;
            values["EndTime"] = end;
            values["DurationMs"] = (long)(end - start).TotalMilliseconds;
        }

        private static string S(IDictionary d, string key, string def)
        {
            return d != null && d.Contains(key) && d[key] != null ? Convert.ToString(d[key]) : def;
        }
    }

    public static class WrapperHost
    {
        private static readonly object LogFileLock = new object();
        private static readonly object AppOutputLogLock = new object();
        private static readonly object OutputDrainLock = new object();
        private const int KillOutputDrainMilliseconds = 1000;
        private const int KillOutputQuietMilliseconds = 100;
        private const int CtrlCSendDebounceMilliseconds = 250;

        private static double ElapsedMs(long startTimestamp)
        {
            return (Stopwatch.GetTimestamp() - startTimestamp) * 1000.0 / Stopwatch.Frequency;
        }

        private static double ElapsedMs(long startTimestamp, long endTimestamp)
        {
            return (endTimestamp - startTimestamp) * 1000.0 / Stopwatch.Frequency;
        }

        private static long DeadlineFromNowMs(int milliseconds)
        {
            return Stopwatch.GetTimestamp() + (long)(Math.Max(0, milliseconds) * Stopwatch.Frequency / 1000.0);
        }

        private static string FmtMs(double milliseconds)
        {
            return milliseconds.ToString("F6", CultureInfo.InvariantCulture);
        }

        public static Hashtable Run(IDictionary config, string appArgsLine)
        {
            DateTime start = DateTime.Now;
            ResultState result = ResultState.Create(config, start);
            ConptySession session = null;
            ConsoleSignalRouter signalRouter = null;
            ShutdownWindowRouter shutdownRouter = null;
            long ctrlCDeadlinePerfTicks = 0;
            bool ctrlCDeadlineActive = false;
            StringBuilder inputLine = new StringBuilder();
            string capturedOutput = "";
            bool running = true;
            bool inputUnavailableLogged = false;
            long ctrlCSentPerfTicks = 0;
            bool ctrlCSentPerfValid = false;
            bool ctrlCAttemptActive = false;
            long ctrlCNextAllowedPerfTicks = 0;
            try
            {
                string appPath = S(config, "AppPath", null);
                if (String.IsNullOrWhiteSpace(appPath) || !File.Exists(appPath))
                {
                    result.TrySetTriggerReason("StartupFailed"); result["FinalState"] = "FailedToStart";
                    result.AddError("AppPath not found: " + appPath); return result.ToHashtable();
                }
                Log(config, "=== Wrapper CSharpHost core started ===", "INFO");
                Log(config, "AppPath: " + appPath, "INFO");
                Log(config, "AppArgsLine: " + (appArgsLine ?? ""), "INFO");
                session = ConptySession.Start(appPath, appArgsLine, S(config, "WorkingDirectory", null), config["EnvironmentVariables"] as IDictionary, B(config, "InheritParentEnvironment", true), S(config, "OutputEncoding", "utf-8"));
                result["AppPid"] = session.Pid;
                Log(config, "Started app. PID=" + session.Pid, "INFO");

                ConptySession closeSession = session;
                // Close/Logoff/Shutdown are terminal best-effort events. If multiple arrive,
                // the first one owns the lifecycle; later ones are ignored by this gate.
                int bestEffortStarted = 0;
                ImmediateSignalDelegate bestEffortHandler = delegate(int sig, long signalPerfTicks)
                {
                    bool isClose = (sig == 2);
                    bool isLogoff = (sig == 5);
                    bool isShutdown = (sig == 6);
                    if (!isClose && !isLogoff && !isShutdown) return false;

                    if ((isLogoff || isShutdown) && !B(config, "EnableShutdownSentinel", true))
                    {
                        return false;
                    }

                    string label = isClose ? "CTRL_CLOSE_EVENT" : (isLogoff ? "CTRL_LOGOFF_EVENT" : "CTRL_SHUTDOWN_EVENT");
                    if (Interlocked.Exchange(ref bestEffortStarted, 1) == 1)
                    {
                        try { Log(config, label + " received while another best-effort system event is already being handled. Duplicate ignored.", "WARN"); } catch { }
                        return true;
                    }

                    string trigger = isClose ? "CtrlClose" : (isLogoff ? "Logoff" : "Shutdown");
                    string appWaitKey = isClose ? "CloseAppWaitMilliseconds" : "ShutdownAppWaitMilliseconds";
                    string budgetKey = isClose ? "CloseHandlerBudgetMilliseconds" : "ShutdownHandlerBudgetMilliseconds";
                    string reserveKey = isClose ? "CloseReserveMilliseconds" : "ShutdownReserveMilliseconds";
                    int defaultAppWait = isClose ? 2000 : 2000;
                    int defaultBudget = isClose ? 3000 : 3000;
                    int defaultReserve = isClose ? 800 : 800;

                    try
                    {
                        long handlerEntryPerf = Stopwatch.GetTimestamp();
                        double handlerEntryLatencyMs = ElapsedMs(signalPerfTicks, handlerEntryPerf);
                        Log(config, label + " captured. Entering best-effort path: send ETX 0x03, bounded wait, then optionally kill.", "WARN");
                        Log(config, trigger + " timing: handlerEntryLatencyMs=" + FmtMs(handlerEntryLatencyMs), "WARN");
                        if (isClose) result["CloseEventReceived"] = true;
                        if (isLogoff || isShutdown) result["ShutdownEventReceived"] = true;
                        result.TrySetTriggerReason(trigger);
                        if (closeSession != null && !closeSession.HasExited())
                        {
                            if (result.TryBeginCtrlCAttempt())
                            {
                                try {
                                    long sendStartPerf = Stopwatch.GetTimestamp();
                                    closeSession.SendCtrlC();
                                    result.RecordCtrlCSent(DateTimeOffset.Now);
                                    Log(config, trigger + " Ctrl+C audit: CtrlCSentCount=" + Convert.ToString(result["CtrlCSentCount"]) + ", LastCtrlCSentAt=" + Convert.ToString(result["LastCtrlCSentAt"]), "WARN");
                                    double sendLatencyMs = ElapsedMs(sendStartPerf);
                                    double sinceHandlerEntryMs = ElapsedMs(handlerEntryPerf);
                                    Log(config, trigger + " path sent ETX 0x03 to ConPTY input. sendLatencyMs=" + FmtMs(sendLatencyMs) + ", sinceHandlerEntryMs=" + FmtMs(sinceHandlerEntryMs), "WARN");
                                }
                                catch (Exception ex) { result.AddError(trigger + " handler failed to send Ctrl+C: " + ex.Message); }
                            }
                            else
                            {
                                Log(config, trigger + " path did not send ETX because Ctrl+C was already sent earlier in this run.", "WARN");
                            }

                            int appWaitMs = Math.Max(0, I(config, appWaitKey, defaultAppWait));
                            int budgetMs = Math.Max(500, I(config, budgetKey, defaultBudget));
                            int reserveMs = Math.Max(0, I(config, reserveKey, defaultReserve));
                            int effectiveWaitMs = Math.Max(0, Math.Min(appWaitMs, budgetMs - reserveMs));
                            Log(config, trigger + " timing: appWaitMs=" + appWaitMs + ", budgetMs=" + budgetMs + ", reserveMs=" + reserveMs + ", effectiveAppWaitMs=" + effectiveWaitMs, "WARN");

                            long waitStartPerf = Stopwatch.GetTimestamp();
                            bool exited = closeSession.WaitForExit(effectiveWaitMs);
                            double waitElapsedMs = ElapsedMs(waitStartPerf);
                            object bestEffortExitCode = null;
                            if (exited)
                            {
                                try { bestEffortExitCode = closeSession.GetExitCode(); result["AppExitCode"] = bestEffortExitCode; } catch { }
                                result["FinalState"] = "Exited";
                            }
                            Log(config, trigger + " wait finished: exited=" + exited + ", exitCode=" + (bestEffortExitCode == null ? "null" : Convert.ToString(bestEffortExitCode)) + ", waitElapsedMs=" + FmtMs(waitElapsedMs), "WARN");
                            if (!exited)
                            {
                                result["TimedOut"] = true;
                                Log(config, trigger + " best-effort app wait expired. KillOnTimeout=" + B(config, "KillOnTimeout", true), "WARN");
                                if (B(config, "KillOnTimeout", true))
                                {
                                    try {
                                        closeSession.Kill(); result["WasKilled"] = true; result["FinalState"] = "Killed";
                                        try { result["AppExitCode"] = closeSession.GetExitCode(); } catch { }
                                    } catch { }
                                }
                                else
                                {
                                    result["FinalState"] = "Timeout";
                                }
                            }

                            long drainStartPerf = Stopwatch.GetTimestamp();
                            DrainOutputBestEffort(config, closeSession, false, 300);
                            Log(config, trigger + " output drain attempted: drainElapsedMs=" + FmtMs(ElapsedMs(drainStartPerf)), "WARN");
                        }
                        else
                        {
                            result["FinalState"] = "Exited";
                        }
                        running = false;
                        Log(config, label + " best-effort path completed. PostActions/finally are not guaranteed after close/shutdown/logoff.", "WARN");
                    }
                    catch (Exception ex)
                    {
                        result.AddError(label + " best-effort path failed: " + ex);
                        if (result.IsFinalState("Unknown")) result["FinalState"] = "Error";
                        try
                        {
                            if (closeSession != null && !closeSession.HasExited())
                            {
                                closeSession.Kill();
                                result["WasKilled"] = true;
                            }
                        }
                        catch { }
                        try { Log(config, label + " best-effort path failed; forcing run termination: " + ex, "ERROR"); } catch { }
                    }
                    finally
                    {
                        // Terminal best-effort event owns the lifecycle once bestEffortStarted is set.
                        // Even if the handler fails internally, the main loop must be forced to exit.
                        running = false;
                    }
                    return true;
                };
                signalRouter = new ConsoleSignalRouter(bestEffortHandler, B(config, "EnableCtrlCForwarding", true), B(config, "EnableCtrlBreakEmergencyExit", true), B(config, "EnableConsoleCloseHandling", true));
                signalRouter.Register();
                ConfigureProcessShutdownParameters(config);
                try
                {
                    shutdownRouter = new ShutdownWindowRouter(bestEffortHandler, B(config, "EnableShutdownSentinel", true));
                    shutdownRouter.Start(config);
                    Log(config, "ShutdownWindowRouter registered. EnableShutdownSentinel=" + B(config, "EnableShutdownSentinel", true), "INFO");
                }
                catch (Exception ex)
                {
                    Log(config, "ShutdownWindowRouter registration failed: " + ex.Message, "WARN");
                }

                while (running)
                {
                    DrainOutputBestEffort(config, session, true, 50);

                    SignalEvent signalEvent;
                    while (signalRouter != null && signalRouter.TryDequeue(out signalEvent))
                    {
                        int sig = signalEvent.Type;
                        long signalDequeuePerf = Stopwatch.GetTimestamp();
                        double signalQueueLatencyMs = ElapsedMs(signalEvent.PerfTicks, signalDequeuePerf);
                        if (sig == 0)
                        {
                            string ctrlCPolicy = S(config, "CtrlCUnresponsivePolicy", "Kill");
                            int defaultGraceMs = String.Equals(ctrlCPolicy, "Continue", StringComparison.OrdinalIgnoreCase) ? 1000 : 5000;
                            int ctrlCGraceMs = I(config, "CtrlCGracePeriodMs", defaultGraceMs);
                            long nowPerf = Stopwatch.GetTimestamp();
                            bool canSendCtrlC = result.TryBeginCtrlCAttempt();
                            if (!canSendCtrlC && String.Equals(ctrlCPolicy, "Continue", StringComparison.OrdinalIgnoreCase) && nowPerf >= ctrlCNextAllowedPerfTicks)
                            {
                                // In Continue mode, Ctrl+C is a repeatable forwarded signal. The guard is
                                // only a short debounce, not a grace-period gate.
                                result.ResetCtrlCGuard();
                                canSendCtrlC = result.TryBeginCtrlCAttempt();
                            }

                            if (canSendCtrlC)
                            {
                                Log(config, "CTRL_C_EVENT captured by CSharpHost. Forwarding ETX 0x03 to ConPTY input.", "INFO");
                                Log(config, "CtrlC timing: signalQueueLatencyMs=" + FmtMs(signalQueueLatencyMs) + ", ctrlCGraceMs=" + ctrlCGraceMs + ", ctrlCUnresponsivePolicy=" + ctrlCPolicy + ", ctrlCSendDebounceMs=" + CtrlCSendDebounceMilliseconds, "INFO");
                                long sendStartPerf = Stopwatch.GetTimestamp();
                                session.SendCtrlC();
                                result.RecordCtrlCSent(DateTimeOffset.Now);
                                long sendEndPerf = Stopwatch.GetTimestamp();
                                double sendLatencyMs = ElapsedMs(sendStartPerf, sendEndPerf);
                                ctrlCSentPerfTicks = sendEndPerf;
                                ctrlCSentPerfValid = true;
                                ctrlCAttemptActive = true;
                                ctrlCNextAllowedPerfTicks = DeadlineFromNowMs(CtrlCSendDebounceMilliseconds);
                                Log(config, "CtrlC path sent ETX 0x03 to ConPTY input. sendLatencyMs=" + FmtMs(sendLatencyMs) + ", sinceSignalDequeuedMs=" + FmtMs(ElapsedMs(signalDequeuePerf, sendEndPerf)), "INFO");
                                Log(config, "CtrlC audit: CtrlCSentCount=" + Convert.ToString(result["CtrlCSentCount"]) + ", LastCtrlCSentAt=" + Convert.ToString(result["LastCtrlCSentAt"]), "INFO");
                                ctrlCDeadlinePerfTicks = DeadlineFromNowMs(ctrlCGraceMs);
                                ctrlCDeadlineActive = true;
                            }
                            else
                            {
                                if (String.Equals(ctrlCPolicy, "Continue", StringComparison.OrdinalIgnoreCase))
                                    Log(config, "CTRL_C_EVENT captured but suppressed by Ctrl+C send debounce. No ETX sent.", "INFO");
                                else
                                    Log(config, "Duplicate CTRL_C_EVENT captured while Ctrl+C is already being processed. Ignored by recursive-signal guard.", "INFO");
                            }
                        }
                        else if (sig == 1)
                        {
                            Log(config, "CTRL_BREAK_EVENT captured. Emergency abort.", "WARN");
                            result.TrySetTriggerReason("Break"); result["FinalState"] = "Aborted";
                            if (!session.HasExited()) { session.Kill(); result["WasKilled"] = true; }
                            running = false;
                        }
                        else
                        {
                            Log(config, "Console signal " + sig + " captured but not handled by CSharpHost.", "WARN");
                        }
                    }

                    if (S(config, "InputMode", "Line") == "Line" && !inputUnavailableLogged)
                    {
                        try
                        {
                            if (Console.IsInputRedirected)
                            {
                                inputUnavailableLogged = true;
                                Log(config, "Console input is redirected; InputMode=Line downgraded to None for this run.", "WARN");
                            }
                            else if (Console.KeyAvailable)
                            {
                                ConsoleKeyInfo key = Console.ReadKey(true);
                                if (key.Key == ConsoleKey.Enter)
                                {
                                    string line = inputLine.ToString(); inputLine.Length = 0; Console.WriteLine();
                                    session.WriteInputString(line + "\r\n", S(config, "InputEncoding", "utf-8"));
                                }
                                else if (key.Key == ConsoleKey.Backspace)
                                {
                                    if (inputLine.Length > 0) { inputLine.Length -= 1; Console.Write("\b \b"); }
                                }
                                else if (key.KeyChar != '\0') { inputLine.Append(key.KeyChar); Console.Write(key.KeyChar); }
                            }
                        }
                        catch (InvalidOperationException ex)
                        {
                            inputUnavailableLogged = true;
                            Log(config, "Console input is unavailable; InputMode=Line downgraded to None: " + ex.Message, "WARN");
                        }
                        catch (IOException ex)
                        {
                            inputUnavailableLogged = true;
                            Log(config, "Console input I/O is unavailable; InputMode=Line downgraded to None: " + ex.Message, "WARN");
                        }
                    }

                    // If a close/logoff/shutdown best-effort handler is active on another thread,
                    // let it own wait/kill/drain/result. Do not race into normal finally/dispose.
                    if (Volatile.Read(ref bestEffortStarted) == 1)
                    {
                        Thread.Sleep(30);
                        continue;
                    }

                    if (session.HasExited())
                    {
                        result["AppExitCode"] = session.GetExitCode();
                        if (ctrlCSentPerfValid && (ctrlCAttemptActive || result.IsTriggerReason("CtrlClose")))
                        {
                            Log(config, "Signal response timing: appExitAfterCtrlCSentMs=" + FmtMs(ElapsedMs(ctrlCSentPerfTicks)), "INFO");
                        }
                        if (ctrlCAttemptActive) result.TrySetTriggerReason("CtrlC");
                        else result.TrySetTriggerReason("AppExited");
                        if (result.IsFinalState("Unknown")) result["FinalState"] = "Exited";
                        long normalDrainStartPerf = Stopwatch.GetTimestamp();
                        int normalDrainMs = Math.Max(0, I(config, "NormalExitOutputDrainMilliseconds", 10000));
                        int normalQuietMs = Math.Max(0, I(config, "NormalExitOutputQuietMilliseconds", 250));
                        if (B(config, "NormalExitClosePseudoConsoleBeforeDrain", true))
                        {
                            long closePcStartPerf = Stopwatch.GetTimestamp();
                            session.ClosePseudoConsoleForOutputCompletion();
                            Log(config, "Normal exit ConPTY close-for-output-completion called: durationMs=" + FmtMs(ElapsedMs(closePcStartPerf)), "INFO");
                        }
                        DrainOutputUntilComplete(config, session, true, normalDrainMs, normalQuietMs);
                        Log(config, "Normal exit output drain completed: durationMs=" + FmtMs(ElapsedMs(normalDrainStartPerf)) + ", budgetMs=" + normalDrainMs + ", quietMs=" + normalQuietMs + ", outputEof=" + session.OutputEof + ", queueEmpty=" + session.OutputQueueIsEmpty, "INFO");
                        running = false; continue;
                    }

                    if (ctrlCDeadlineActive && Stopwatch.GetTimestamp() > ctrlCDeadlinePerfTicks)
                    {
                        string ctrlCPolicy = S(config, "CtrlCUnresponsivePolicy", "Kill");
                        result.RecordCtrlCUnresponsive();
                        if (ctrlCSentPerfValid) Log(config, "CtrlC unresponsive timing: elapsedSinceCtrlCSentMs=" + FmtMs(ElapsedMs(ctrlCSentPerfTicks)) + ", policy=" + ctrlCPolicy, "WARN");
                        if (String.Equals(ctrlCPolicy, "Continue", StringComparison.OrdinalIgnoreCase))
                        {
                            Log(config, "App did not exit within CtrlC grace period. CtrlCUnresponsivePolicy=Continue; wrapper remains running.", "WARN");
                            ctrlCDeadlineActive = false;
                            ctrlCAttemptActive = false;
                            ctrlCSentPerfValid = false;
                            result.ResetCtrlCGuard();
                        }
                        else
                        {
                            result["TimedOut"] = true;
                            result.TrySetTriggerReason("CtrlC");
                            Log(config, "App did not exit within CtrlC grace period. CtrlCUnresponsivePolicy=Kill, KillOnTimeout=" + B(config, "KillOnTimeout", true), "WARN");
                            if (B(config, "KillOnTimeout", true))
                            {
                                session.Kill(); result["WasKilled"] = true; result["FinalState"] = "Killed";
                                Thread.Sleep(100); try { result["AppExitCode"] = session.GetExitCode(); } catch { }
                                try
                                {
                                    long killDrainStartPerf = Stopwatch.GetTimestamp();
                                    session.ClosePseudoConsoleForOutputCompletion();
                                    DrainOutputUntilComplete(config, session, true, KillOutputDrainMilliseconds, KillOutputQuietMilliseconds);
                                    Log(config, "CtrlC timeout kill output drain completed: durationMs=" + FmtMs(ElapsedMs(killDrainStartPerf)) + ", budgetMs=" + KillOutputDrainMilliseconds + ", quietMs=" + KillOutputQuietMilliseconds + ", outputEof=" + session.OutputEof + ", queueEmpty=" + session.OutputQueueIsEmpty, "WARN");
                                }
                                catch (Exception ex)
                                {
                                    result.AddError("CtrlC timeout kill output drain failed: " + ex.Message);
                                    try { Log(config, "CtrlC timeout kill output drain failed: " + ex, "WARN"); } catch { }
                                }
                                running = false;
                            }
                            else { result["FinalState"] = "Timeout"; try { result["AppExitCode"] = session.GetExitCode(); } catch { } running = false; }
                        }
                    }

                    Thread.Sleep(30);
                }
            }
            catch (Exception ex)
            {
                result.TrySetTriggerReason("ScriptError"); result["FinalState"] = "Error"; result.AddError(ex.ToString());
                try { Log(config, "Wrapper error: " + ex, "ERROR"); } catch { }
                if (session != null) { try { if (!session.HasExited()) { session.Kill(); result["WasKilled"] = true; } } catch { } }
            }
            finally
            {
                if (session != null)
                {
                    try
                    {
                        Thread.Sleep(100);
                        DrainOutputBestEffort(config, session, true, 100);
                        capturedOutput = session.CapturedOutput;
                        if (B(config, "StripAnsiSequences", false)) capturedOutput = StripAnsi(capturedOutput);
                        result["StdoutBytes"] = session.StdoutBytes;
                        result["OutputLines"] = session.OutputLines;
                    } catch { }
                    try { session.Dispose(); } catch { }
                }
                try { if (shutdownRouter != null) shutdownRouter.Dispose(); } catch { }
                try { if (signalRouter != null) signalRouter.Dispose(); } catch { }
                result["CapturedOutput"] = capturedOutput;
                result.Complete(start);
                try
                {
                    int exitCode = result["AppExitCode"] == null ? 0 : Convert.ToInt32(result["AppExitCode"]);
                    string exitHex = result["AppExitCode"] == null ? "null" : "0x" + unchecked((uint)exitCode).ToString("X8");
                    Log(config, "Result: TriggerReason=" + result["TriggerReason"] + ", FinalState=" + result["FinalState"] + ", ExitCode=" + result["AppExitCode"] + "(" + exitHex + "), WasKilled=" + result["WasKilled"] + ", TimedOut=" + result["TimedOut"], "INFO");
                    Log(config, "=== Wrapper CSharpHost core ended ===", "INFO");
                } catch { }
            }
            return result.ToHashtable();
        }

        private static void ConfigureProcessShutdownParameters(IDictionary config)
        {
            if (!B(config, "EnableShutdownSentinel", true)) return;
            try
            {
                uint requestedLevel = 0x3FFu;
                uint requestedFlags = 0u;
                bool setOk = Native.SetProcessShutdownParameters(requestedLevel, requestedFlags);
                int setErr = Marshal.GetLastWin32Error();

                uint actualLevel = 0;
                uint actualFlags = 0;
                bool getOk = Native.GetProcessShutdownParameters(out actualLevel, out actualFlags);
                int getErr = Marshal.GetLastWin32Error();

                bool verified = setOk && getOk && actualLevel == requestedLevel && actualFlags == requestedFlags;
                string setErrText = setOk ? "n/a" : setErr.ToString();
                string getErrText = getOk ? "n/a" : getErr.ToString();
                string msg = "SetProcessShutdownParameters requestedLevel=0x" + requestedLevel.ToString("X3") +
                    ", requestedFlags=0x" + requestedFlags.ToString("X8") +
                    ", setSuccess=" + setOk +
                    ", setLastError=" + setErrText +
                    ", getSuccess=" + getOk +
                    ", getLastError=" + getErrText +
                    ", actualLevel=0x" + actualLevel.ToString("X3") +
                    ", actualFlags=0x" + actualFlags.ToString("X8") +
                    ", verified=" + verified;
                Log(config, msg, verified ? "INFO" : "WARN");
            }
            catch (Exception ex)
            {
                try { Log(config, "Set/GetProcessShutdownParameters failed: " + ex.Message, "WARN"); } catch { }
            }
        }
        private static void DrainOutputBestEffort(IDictionary config, ConptySession session, bool writeConsole, int maxMilliseconds)
        {
            if (session == null) return;
            long drainStartPerf = Stopwatch.GetTimestamp();
            bool lockTaken = false;
            try
            {
                // Serialize dequeue+write, not only file writes. Otherwise close-handler drain and
                // normal output drain can dequeue ordered chunks in one order but write them in another.
                Monitor.TryEnter(OutputDrainLock, Math.Min(100, Math.Max(0, maxMilliseconds)), ref lockTaken);
                if (!lockTaken) return;

                while (ElapsedMs(drainStartPerf) <= maxMilliseconds)
                {
                    bool hadAny = false;
                    string chunk;
                    while (session.TryDequeueOutput(out chunk))
                    {
                        hadAny = true;
                        if (!String.IsNullOrEmpty(chunk))
                        {
                            if (writeConsole) Console.Write(chunk);
                            AppendAppOutputLog(config, chunk);
                        }
                        if (ElapsedMs(drainStartPerf) > maxMilliseconds) break;
                    }
                    if (!hadAny) Thread.Sleep(10);
                }
            }
            catch { }
            finally
            {
                if (lockTaken) Monitor.Exit(OutputDrainLock);
            }
        }

        private static void DrainOutputUntilComplete(IDictionary config, ConptySession session, bool writeConsole, int maxMilliseconds, int quietMilliseconds)
        {
            if (session == null) return;
            long drainStartPerf = Stopwatch.GetTimestamp();
            long lastActivityPerf = drainStartPerf;
            bool lockTaken = false;
            try
            {
                Monitor.TryEnter(OutputDrainLock, Math.Min(1000, Math.Max(0, maxMilliseconds)), ref lockTaken);
                if (!lockTaken) return;

                while (ElapsedMs(drainStartPerf) <= maxMilliseconds)
                {
                    bool hadAny = false;
                    string chunk;
                    while (session.TryDequeueOutput(out chunk))
                    {
                        hadAny = true;
                        lastActivityPerf = Stopwatch.GetTimestamp();
                        if (!String.IsNullOrEmpty(chunk))
                        {
                            if (writeConsole) Console.Write(chunk);
                            AppendAppOutputLog(config, chunk);
                        }
                    }

                    if (session.OutputEof && session.OutputQueueIsEmpty) break;

                    // In ConPTY mode EOF may not be observed until HPCON disposal, even after the child
                    // process has exited. For normal AppExited path, queue-empty quiet period is enough
                    // to avoid printing summary in the middle of pending output without always waiting
                    // for the full budget.
                    if (session.OutputQueueIsEmpty && ElapsedMs(lastActivityPerf) >= quietMilliseconds) break;

                    if (!hadAny) Thread.Sleep(20);
                }
            }
            catch { }
            finally
            {
                if (lockTaken) Monitor.Exit(OutputDrainLock);
            }
        }

        private static string S(IDictionary d, string key, string def) { return d != null && d.Contains(key) && d[key] != null ? Convert.ToString(d[key]) : def; }
        private static int I(IDictionary d, string key, int def) { return d != null && d.Contains(key) && d[key] != null ? Convert.ToInt32(d[key]) : def; }
        private static bool B(IDictionary d, string key, bool def) { return d != null && d.Contains(key) && d[key] != null ? Convert.ToBoolean(d[key]) : def; }
        private static void AppendTextShared(string path, string text, Encoding encoding, object sync)
        {
            if (String.IsNullOrWhiteSpace(path) || text == null) return;
            lock (sync)
            {
                using (FileStream fs = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                using (StreamWriter sw = new StreamWriter(fs, encoding))
                {
                    sw.Write(text);
                }
            }
        }

        internal static void Log(IDictionary config, string message, string level)
        {
            string path = S(config, "LogFilePath", null); if (String.IsNullOrWhiteSpace(path)) return;
            string runId = S(config, "RunId", null);
            string runPrefix = String.IsNullOrWhiteSpace(runId) ? "" : "[RunId=" + runId + "]";
            string line = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "][" + level + "]" + runPrefix + " " + message + Environment.NewLine;
            try { AppendTextShared(path, line, Encoding.UTF8, LogFileLock); } catch { }
        }
        private static void AppendAppOutputLog(IDictionary config, string text)
        {
            string path = S(config, "AppOutputLogFilePath", null); if (String.IsNullOrWhiteSpace(path) || text == null) return;
            string t = B(config, "StripAnsiSequences", false) ? StripAnsi(text) : text;
            try { AppendTextShared(path, t, EncodingUtil.ResolveEncoding(S(config, "OutputEncoding", "utf-8")), AppOutputLogLock); } catch { }
        }
        private static string StripAnsi(string text)
        {
            if (String.IsNullOrEmpty(text)) return text;
            string esc = "\x1B";
            string s = text;
            s = Regex.Replace(s, esc + @"\][\s\S]*?(?:\x07|" + esc + @"\\)", "");
            s = Regex.Replace(s, esc + @"[P\^_X][\s\S]*?" + esc + @"\\", "");
            s = Regex.Replace(s, esc + @"\[[0-?]*[ -/]*[@-~]", "");
            s = Regex.Replace(s, esc + @"[@-Z\\-_]", "");
            s = Regex.Replace(s, @"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "");
            return s;
        }
    }
}
'@

    Add-Type -TypeDefinition $cs -Language CSharp -ReferencedAssemblies @("System.Core.dll", "System.dll", "System.Windows.Forms.dll")
}

$userConfig = . $ConfigPath
$config = Merge-WrapperConfig -UserConfig $userConfig
Assert-WrapperConfig -Config $config | Out-Null
Initialize-WrapperDirectories -Config $config

Add-CSharpHostType
if (-not $config.ContainsKey("RunId") -or [string]::IsNullOrWhiteSpace([string]$config["RunId"])) {
    $config["RunId"] = ((Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-" + ([guid]::NewGuid().ToString("N").Substring(0, 8)))
}
Write-WrapperLog -Config $config -Message "=== Wrapper PowerShell entry started. RunId=$($config["RunId"]) ==="
$appArgsValue = if ($config.ContainsKey("AppArgs")) { $config["AppArgs"] } else { @() }
try { Write-WrapperLog -Config $config -Message "AppArgsRawCount: $(@($appArgsValue).Count); AppArgsRaw: $(@($appArgsValue) -join ' | ')" } catch {}
try {
    $envOverrides = if ($config.ContainsKey("EnvironmentVariables") -and $null -ne $config["EnvironmentVariables"]) { $config["EnvironmentVariables"] } else { @{} }
    $envKeys = @($envOverrides.Keys | Sort-Object)
    if ($config.ContainsKey("LogEnvironmentVariableValues") -and [bool]$config["LogEnvironmentVariableValues"]) {
        $pairs = @()
        foreach ($k in $envKeys) {
            $v = [string]$envOverrides[$k]
            if ($k -match '(?i)(pass|pwd|secret|token|key|credential)') { $v = '<redacted>' }
            $pairs += ("$k=$v")
        }
        Write-WrapperLog -Config $config -Message "EnvironmentOverridesCount: $($envKeys.Count); EnvironmentOverrides: $($pairs -join ' | ')"
    }
    else {
        Write-WrapperLog -Config $config -Message "EnvironmentOverridesCount: $($envKeys.Count); EnvironmentOverrideNames: $($envKeys -join ' | '); ValuesLogged=False"
    }
} catch {}
$argLine = Join-WrapperCommandLineArgs -ArgumentList @($appArgsValue)
$result = [CSharpWrapperHost_v020rc2dev.WrapperHost]::Run([System.Collections.IDictionary]$config, [string]$argLine)

# Convert C# ArrayList errors to a normal PowerShell array to keep common helpers happy.
if ($result.Errors -is [System.Collections.ArrayList]) {
    $errors = @()
    foreach ($e in $result.Errors) { $errors += [string]$e }
    $result.Errors = $errors
}

$capturedOutput = [string]$result.CapturedOutput
$result.Remove("CapturedOutput")
$skipBestEffortPostActions = (
    ([string]$result.TriggerReason -eq "CtrlClose" -and $config.ContainsKey("CloseSkipPostActions") -and [bool]$config["CloseSkipPostActions"]) -or
    (([string]$result.TriggerReason -eq "Shutdown" -or [string]$result.TriggerReason -eq "Logoff") -and $config.ContainsKey("ShutdownSkipPostActions") -and [bool]$config["ShutdownSkipPostActions"])
)
if (-not $skipBestEffortPostActions) {
    $postActionStart = Get-Date
    Invoke-WrapperPostActions -Config $config -Result $result -CapturedOutput $capturedOutput | Out-Null
    $postActionElapsedMs = [int64](New-TimeSpan -Start $postActionStart -End (Get-Date)).TotalMilliseconds
    $result["PostActionsDurationMs"] = $postActionElapsedMs
    try {
        Write-WrapperLog -Config $config -Message "PostActions timing: durationMs=$postActionElapsedMs"
        Write-WrapperLog -Config $config -Message "=== Wrapper PowerShell post-actions ended ==="
    } catch {}
}
else {
    try {
        Write-WrapperLog -Config $config -Level "WARN" -Message "Skipping PostActions for $($result.TriggerReason) best-effort path."
        Write-WrapperLog -Config $config -Message "=== Wrapper PowerShell post-actions skipped ==="
    } catch {}
}

$resultJson = ConvertTo-WrapperJson -InputObject $result -Depth 10

if ($JsonOutputPath) {
    try {
        $jsonParent = Split-Path -Parent $JsonOutputPath
        if (-not [string]::IsNullOrWhiteSpace($jsonParent) -and -not (Test-Path -LiteralPath $jsonParent)) {
            New-Item -ItemType Directory -Path $jsonParent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText([string]$JsonOutputPath, [string]$resultJson, [System.Text.Encoding]::UTF8)
    }
    catch {
        Add-WrapperError -Result $result -Message "Failed to write JsonOutputPath '$JsonOutputPath': $_"
        try { Write-WrapperLog -Config $config -Level "ERROR" -Message "Failed to write JsonOutputPath '$JsonOutputPath': $_" } catch {}
        $resultJson = ConvertTo-WrapperJson -InputObject $result -Depth 10
    }
}

if (-not $NoSummary) { Show-WrapperResultSummary -Result $result }
if ($Json) { $resultJson }

if ($PauseOnExit) {
    Clear-WrapperConsoleInputBuffer
    try { [void](Read-Host "Wrapper finished. Press Enter to exit") } catch {}
    Clear-WrapperConsoleInputBuffer
}
else {
    Clear-WrapperConsoleInputBuffer
}

if (@($result.Errors).Count -gt 0) { exit 2 }
if ($result.FinalState -eq "FailedToStart" -or $result.FinalState -eq "Error") { exit 1 }
exit 0
