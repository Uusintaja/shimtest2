<#
.SYNOPSIS
    Implementation A: PowerShell-main ConPTY wrapper MVP.

.DESCRIPTION
    This MVP keeps the lifecycle state machine, config handling, logging, post actions, and result
    object in PowerShell. It uses embedded C# for the unavoidable Win32/ConPTY boundary and small
    helper queues.

    Scope of Step 3 MVP:
      - ConPTY process startup
      - realtime output forwarding
      - app output optional log
      - environment variable injection
      - working directory
      - Ctrl+C capture and forwarding by writing ETX 0x03 to ConPTY input
      - timeout and kill
      - generic post actions

    Explicitly deferred to Step 7:
      - robust CTRL_CLOSE_EVENT handling
      - shutdown/logoff sentinel
      - CancelAndReissue shutdown mode

.NOTES
    Target: Windows PowerShell 5.1, Windows 10 1809+.
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
    <#
    .SYNOPSIS
        Quotes command-line arguments for CreateProcess command line.

    .NOTES
        Do not name this parameter $Args. PowerShell has a built-in automatic variable $args;
        using a parameter with the same effective name is confusing and caused argument loss
        in Windows PowerShell 5.1 testing.
    #>
    param([object[]]$ArgumentList)

    if ($null -eq $ArgumentList -or @($ArgumentList).Count -eq 0) { return "" }

    $quoted = New-Object System.Collections.Generic.List[string]
    foreach ($argObj in @($ArgumentList)) {
        $arg = [string]$argObj
        if ($arg.Length -eq 0) {
            $quoted.Add('""')
            continue
        }
        if ($arg -notmatch '[\s"]') {
            $quoted.Add($arg)
            continue
        }

        # Windows CreateProcess quoting. Escape backslashes before a quote and before final quote.
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $arg.ToCharArray()) {
            if ($ch -eq '\\') {
                $bs++
            }
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

function Add-PsMainConptyType {
    if ("PsMainConpty.ConptySession" -as [type]) { return }

    $cs = @'
using System;
using System.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent;

namespace PsMainConpty
{
    internal static class Native
    {
        public const int PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
        public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        public const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        public const uint WAIT_TIMEOUT = 0x00000102;
        public const uint WAIT_OBJECT_0 = 0x00000000;
        public const uint INFINITE = 0xFFFFFFFF;
        public const int STILL_ACTIVE = 259;

        [StructLayout(LayoutKind.Sequential)]
        public struct COORD
        {
            public short X;
            public short Y;
            public COORD(short x, short y) { X = x; Y = y; }
        }

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
        public struct STARTUPINFOEX
        {
            public STARTUPINFO StartupInfo;
            public IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct SECURITY_ATTRIBUTES
        {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)]
            public bool bInheritHandle;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, uint nSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToRead, out int lpNumberOfBytesRead, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, IntPtr lpOverlapped);

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
        public static extern bool CreateProcessW(
            string lpApplicationName,
            string lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandles,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            string lpCurrentDirectory,
            ref STARTUPINFOEX lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetExitCodeProcess(IntPtr hProcess, out int lpExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate HandlerRoutine, bool Add);
    }

    public delegate bool ConsoleCtrlDelegate(uint ctrlType);

    public sealed class SignalRouter
    {
        private static readonly ConcurrentQueue<int> _signals = new ConcurrentQueue<int>();
        private static ConsoleCtrlDelegate _handler;
        private static bool _handleCtrlC;
        private static bool _handleBreak;
        private static bool _handleClose;

        public static void Register(bool handleCtrlC, bool handleBreak, bool handleClose)
        {
            Unregister();
            DrainSignals();
            _handleCtrlC = handleCtrlC;
            _handleBreak = handleBreak;
            _handleClose = handleClose;
            _handler = new ConsoleCtrlDelegate(Handler);
            if (!Native.SetConsoleCtrlHandler(_handler, true))
            {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "SetConsoleCtrlHandler failed");
            }
        }

        public static void Unregister()
        {
            if (_handler != null)
            {
                Native.SetConsoleCtrlHandler(_handler, false);
                _handler = null;
            }
            DrainSignals();
        }

        private static void DrainSignals()
        {
            int ignored;
            while (_signals.TryDequeue(out ignored)) { }
        }

        public static void Clear()
        {
            DrainSignals();
        }

        private static bool Handler(uint ctrlType)
        {
            // 0=CTRL_C_EVENT, 1=CTRL_BREAK_EVENT, 2=CTRL_CLOSE_EVENT, 5=LOGOFF, 6=SHUTDOWN
            _signals.Enqueue((int)ctrlType);
            if (ctrlType == 0) return _handleCtrlC;
            if (ctrlType == 1) return _handleBreak;
            if (ctrlType == 2) return _handleClose;
            return false;
        }

        public static bool TryDequeueSignal(out int signal)
        {
            return _signals.TryDequeue(out signal);
        }
    }

    public sealed class ConptySession : IDisposable
    {
        private IntPtr _hPC = IntPtr.Zero;
        private IntPtr _inputWrite = IntPtr.Zero;
        private IntPtr _outputRead = IntPtr.Zero;
        private IntPtr _process = IntPtr.Zero;
        private IntPtr _thread = IntPtr.Zero;
        private Thread _readerThread;
        private volatile bool _disposed;
        private readonly ConcurrentQueue<string> _outputQueue = new ConcurrentQueue<string>();
        private readonly StringBuilder _allOutput = new StringBuilder();
        private long _stdoutBytes;
        private int _outputLines;
        private int _pid;

        public int Pid { get { return _pid; } }
        public long StdoutBytes { get { return Interlocked.Read(ref _stdoutBytes); } }
        public int OutputLines { get { return _outputLines; } }
        public bool OutputEof { get; private set; }
        public string CapturedOutput { get { lock (_allOutput) { return _allOutput.ToString(); } } }

        private ConptySession() {}

        public static ConptySession Start(string appPath, string args, string workingDirectory, IDictionary env, bool inheritParentEnvironment, string outputEncodingName)
        {
            if (String.IsNullOrEmpty(appPath)) throw new ArgumentException("appPath is required");
            ConptySession s = new ConptySession();

            IntPtr inputRead = IntPtr.Zero;
            IntPtr outputWrite = IntPtr.Zero;
            IntPtr attrList = IntPtr.Zero;
            IntPtr envBlock = IntPtr.Zero;
            IntPtr hPC = IntPtr.Zero;

            try
            {
                if (!Native.CreatePipe(out inputRead, out s._inputWrite, IntPtr.Zero, 0))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe input failed");
                if (!Native.CreatePipe(out s._outputRead, out outputWrite, IntPtr.Zero, 0))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe output failed");

                int hr = Native.CreatePseudoConsole(new Native.COORD(120, 30), inputRead, outputWrite, 0, out hPC);
                if (hr != 0)
                    throw new System.ComponentModel.Win32Exception(hr, "CreatePseudoConsole failed");
                s._hPC = hPC;

                IntPtr size = IntPtr.Zero;
                Native.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
                attrList = Marshal.AllocHGlobal(size);
                if (!Native.InitializeProcThreadAttributeList(attrList, 1, 0, ref size))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "InitializeProcThreadAttributeList failed");

                // Important: PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE expects the HPCON handle value
                // itself as lpValue, not a pointer to a variable containing the handle. Passing &hPC
                // can make CreateProcess appear to succeed while the child process fails during
                // console/DLL initialization (commonly observed as 0xC0000142).
                if (!Native.UpdateProcThreadAttribute(attrList, 0, (IntPtr)Native.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPC, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "UpdateProcThreadAttribute(PSEUDOCONSOLE) failed");

                Native.STARTUPINFOEX si = new Native.STARTUPINFOEX();
                si.StartupInfo.cb = Marshal.SizeOf(typeof(Native.STARTUPINFOEX));
                si.lpAttributeList = attrList;

                string cmdline = QuoteArg(appPath);
                if (!String.IsNullOrWhiteSpace(args)) cmdline += " " + args;

                envBlock = BuildEnvironmentBlock(env, inheritParentEnvironment);
                uint flags = Native.EXTENDED_STARTUPINFO_PRESENT | Native.CREATE_UNICODE_ENVIRONMENT;

                Native.PROCESS_INFORMATION pi;
                bool ok = Native.CreateProcessW(appPath, cmdline, IntPtr.Zero, IntPtr.Zero, false, flags, envBlock, String.IsNullOrWhiteSpace(workingDirectory) ? null : workingDirectory, ref si, out pi);
                if (!ok)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "CreateProcessW failed: " + appPath);

                s._process = pi.hProcess;
                s._thread = pi.hThread;
                s._pid = pi.dwProcessId;

                // The pseudoconsole has taken what it needs. Close wrapper's unused sides.
                if (inputRead != IntPtr.Zero) { Native.CloseHandle(inputRead); inputRead = IntPtr.Zero; }
                if (outputWrite != IntPtr.Zero) { Native.CloseHandle(outputWrite); outputWrite = IntPtr.Zero; }

                s.StartReader(outputEncodingName);
                return s;
            }
            catch
            {
                s.Dispose();
                throw;
            }
            finally
            {
                if (attrList != IntPtr.Zero)
                {
                    Native.DeleteProcThreadAttributeList(attrList);
                    Marshal.FreeHGlobal(attrList);
                }
                if (envBlock != IntPtr.Zero) Marshal.FreeHGlobal(envBlock);
                if (inputRead != IntPtr.Zero) Native.CloseHandle(inputRead);
                if (outputWrite != IntPtr.Zero) Native.CloseHandle(outputWrite);
            }
        }

        private void StartReader(string encodingName)
        {
            Encoding enc = ResolveEncoding(encodingName);
            Decoder decoder = enc.GetDecoder();
            _readerThread = new Thread(delegate()
            {
                byte[] buffer = new byte[4096];
                char[] chars = new char[8192];
                try
                {
                    while (!_disposed)
                    {
                        int read;
                        bool ok = Native.ReadFile(_outputRead, buffer, buffer.Length, out read, IntPtr.Zero);
                        if (!ok || read <= 0) break;
                        Interlocked.Add(ref _stdoutBytes, read);
                        int charCount = decoder.GetChars(buffer, 0, read, chars, 0, false);
                        if (charCount > 0)
                        {
                            string text = new string(chars, 0, charCount);
                            _outputQueue.Enqueue(text);
                            lock (_allOutput) { _allOutput.Append(text); }
                            for (int i = 0; i < text.Length; i++) if (text[i] == '\n') Interlocked.Increment(ref _outputLines);
                        }
                    }
                    int flushCount = decoder.GetChars(Array.Empty<byte>(), 0, 0, chars, 0, true);
                    if (flushCount > 0)
                    {
                        string text = new string(chars, 0, flushCount);
                        _outputQueue.Enqueue(text);
                        lock (_allOutput) { _allOutput.Append(text); }
                    }
                }
                catch (Exception ex)
                {
                    _outputQueue.Enqueue("\r\n[wrapper-reader-error] " + ex.Message + "\r\n");
                }
                finally
                {
                    OutputEof = true;
                }
            });
            _readerThread.IsBackground = true;
            _readerThread.Name = "ConPTY output reader";
            _readerThread.Start();
        }

        public bool TryDequeueOutput(out string text)
        {
            return _outputQueue.TryDequeue(out text);
        }

        public void WriteInputString(string text, string encodingName)
        {
            if (text == null) return;
            byte[] bytes = ResolveEncoding(encodingName).GetBytes(text);
            WriteInputBytes(bytes);
        }

        public void SendCtrlC()
        {
            WriteInputBytes(new byte[] { 0x03 });
        }

        public void WriteInputBytes(byte[] bytes)
        {
            if (bytes == null || bytes.Length == 0) return;
            int written;
            if (!Native.WriteFile(_inputWrite, bytes, bytes.Length, out written, IntPtr.Zero))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "WriteFile input failed");
        }

        public bool WaitForExit(int milliseconds)
        {
            if (_process == IntPtr.Zero) return true;
            uint r = Native.WaitForSingleObject(_process, (uint)Math.Max(0, milliseconds));
            return r == Native.WAIT_OBJECT_0;
        }

        public bool HasExited()
        {
            return WaitForExit(0);
        }

        public int GetExitCode()
        {
            if (_process == IntPtr.Zero) return -1;
            int code;
            if (!Native.GetExitCodeProcess(_process, out code))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "GetExitCodeProcess failed");
            return code;
        }

        public void Kill()
        {
            if (_process != IntPtr.Zero && !HasExited())
            {
                Native.TerminateProcess(_process, 0xFFFFFFFF);
            }
        }

        public void Dispose()
        {
            _disposed = true;
            if (_inputWrite != IntPtr.Zero) { Native.CloseHandle(_inputWrite); _inputWrite = IntPtr.Zero; }
            if (_hPC != IntPtr.Zero) { Native.ClosePseudoConsole(_hPC); _hPC = IntPtr.Zero; }
            if (_outputRead != IntPtr.Zero) { Native.CloseHandle(_outputRead); _outputRead = IntPtr.Zero; }
            if (_thread != IntPtr.Zero) { Native.CloseHandle(_thread); _thread = IntPtr.Zero; }
            if (_process != IntPtr.Zero) { Native.CloseHandle(_process); _process = IntPtr.Zero; }
        }

        private static Encoding ResolveEncoding(string name)
        {
            if (String.IsNullOrWhiteSpace(name)) return Encoding.UTF8;
            string n = name.ToLowerInvariant().Replace("-", "");
            if (n == "utf8") return Encoding.UTF8;
            if (n == "unicode" || n == "utf16") return Encoding.Unicode;
            if (n == "ascii") return Encoding.ASCII;
            if (n == "default") return Encoding.Default;
            return Encoding.GetEncoding(name);
        }

        private static string QuoteArg(string arg)
        {
            if (arg == null) return "\"\"";
            if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return arg;
            StringBuilder sb = new StringBuilder();
            sb.Append('"');
            int bs = 0;
            foreach (char c in arg)
            {
                if (c == '\\') bs++;
                else if (c == '"')
                {
                    sb.Append('\\', bs * 2 + 1);
                    sb.Append('"');
                    bs = 0;
                }
                else
                {
                    if (bs > 0) { sb.Append('\\', bs); bs = 0; }
                    sb.Append(c);
                }
            }
            if (bs > 0) sb.Append('\\', bs * 2);
            sb.Append('"');
            return sb.ToString();
        }

        private static IntPtr BuildEnvironmentBlock(IDictionary env, bool inherit)
        {
            SortedDictionary<string, string> map = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (inherit)
            {
                IDictionary current = Environment.GetEnvironmentVariables();
                foreach (DictionaryEntry de in current)
                {
                    map[Convert.ToString(de.Key)] = Convert.ToString(de.Value);
                }
            }
            if (env != null)
            {
                foreach (DictionaryEntry de in env)
                {
                    string k = Convert.ToString(de.Key);
                    string v = Convert.ToString(de.Value);
                    if (!String.IsNullOrEmpty(k)) map[k] = v ?? String.Empty;
                }
            }

            StringBuilder sb = new StringBuilder();
            foreach (KeyValuePair<string, string> kv in map)
            {
                sb.Append(kv.Key).Append('=').Append(kv.Value).Append('\0');
            }
            sb.Append('\0');
            byte[] bytes = Encoding.Unicode.GetBytes(sb.ToString());
            IntPtr ptr = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            return ptr;
        }
    }
}
'@

    Add-Type -TypeDefinition $cs -Language CSharp -ReferencedAssemblies @("System.Core.dll")
}

function Write-AppOutputLogChunk {
    param(
        [hashtable]$Config,
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace([string]$Config.AppOutputLogFilePath)) { return }
    try {
        $logText = $Text
        if ($Config.ContainsKey("StripAnsiSequences") -and [bool]$Config.StripAnsiSequences) {
            $logText = Remove-WrapperAnsiSequences -Text $logText
        }
        [System.IO.File]::AppendAllText([string]$Config.AppOutputLogFilePath, $logText, (Get-WrapperTextEncoding -Name $Config.OutputEncoding))
    }
    catch {
        Write-WrapperLog -Config $Config -Level "WARN" -Message "Failed to write app output log: $_"
    }
}

function Invoke-PsMainWrapper {
    param([hashtable]$Config)

    $result = New-WrapperResult -Implementation "PowerShellMain" -Config $Config
    $session = $null
    $capturedOutput = ""
    $triggerDeadline = $null
    $inputLineBuffer = New-Object System.Text.StringBuilder

    try {
        Assert-WrapperConfig -Config $Config | Out-Null
        Initialize-WrapperDirectories -Config $Config
        Write-WrapperLog -Config $Config -Message "=== Wrapper PowerShellMain started ==="
        Write-WrapperLog -Config $Config -Message "AppPath: $($Config.AppPath)"

        if (-not (Test-Path -LiteralPath ([string]$Config.AppPath) -PathType Leaf)) {
            $result.TriggerReason = "StartupFailed"
            $result.FinalState = "FailedToStart"
            Add-WrapperError -Result $result -Message "AppPath not found: $($Config.AppPath)"
            return $result
        }

        if ($null -ne $Config.WorkingDirectory -and -not [string]::IsNullOrWhiteSpace([string]$Config.WorkingDirectory)) {
            if (-not (Test-Path -LiteralPath ([string]$Config.WorkingDirectory) -PathType Container)) {
                New-Item -ItemType Directory -Path ([string]$Config.WorkingDirectory) -Force | Out-Null
            }
        }

        Add-PsMainConptyType
        [PsMainConpty.SignalRouter]::Register([bool]$Config.EnableCtrlCForwarding, [bool]$Config.EnableCtrlBreakEmergencyExit, $false)

        $appArgsValue = if ($Config.ContainsKey("AppArgs")) { $Config["AppArgs"] } else { @() }
        Write-WrapperLog -Config $Config -Message "AppArgsRawCount: $(@($appArgsValue).Count); AppArgsRaw: $(@($appArgsValue) -join ' | ')"
        $argLine = Join-WrapperCommandLineArgs -ArgumentList @($appArgsValue)
        Write-WrapperLog -Config $Config -Message "AppArgsLine: $argLine"
        $session = [PsMainConpty.ConptySession]::Start(
            [string]$Config.AppPath,
            [string]$argLine,
            [string]$Config.WorkingDirectory,
            [System.Collections.IDictionary]$Config.EnvironmentVariables,
            [bool]$Config.InheritParentEnvironment,
            [string]$Config.OutputEncoding
        )
        $result.AppPid = $session.Pid
        Write-WrapperLog -Config $Config -Message "Started app. PID=$($session.Pid)"

        $running = $true
        while ($running) {
            # Drain app output first to avoid pipe pressure.
            $chunk = $null
            while ($session.TryDequeueOutput([ref]$chunk)) {
                if ($null -ne $chunk -and $chunk.Length -gt 0) {
                    [Console]::Write($chunk)
                    Write-AppOutputLogChunk -Config $Config -Text $chunk
                }
                $chunk = $null
            }

            # Poll console signals captured by native SetConsoleCtrlHandler.
            $sig = 0
            while ([PsMainConpty.SignalRouter]::TryDequeueSignal([ref]$sig)) {
                switch ($sig) {
                    0 {
                        if (-not $result.CtrlCSent) {
                            Write-WrapperLog -Config $Config -Message "CTRL_C_EVENT captured by wrapper. Forwarding ETX 0x03 to ConPTY input."
                            $result.TriggerReason = "CtrlC"
                            $session.SendCtrlC()
                            $result.CtrlCSent = $true
                            $triggerDeadline = (Get-Date).AddSeconds([int]$Config.CtrlCTimeoutSeconds)
                        }
                        else {
                            Write-WrapperLog -Config $Config -Message "Duplicate CTRL_C_EVENT captured while Ctrl+C is already being processed. Ignored by recursive-signal guard."
                        }
                    }
                    1 {
                        Write-WrapperLog -Config $Config -Level "WARN" -Message "CTRL_BREAK_EVENT captured. Emergency abort."
                        $result.TriggerReason = "Break"
                        $result.FinalState = "Aborted"
                        if (-not $session.HasExited()) {
                            $session.Kill()
                            $result.WasKilled = $true
                        }
                        $running = $false
                    }
                    default {
                        Write-WrapperLog -Config $Config -Level "WARN" -Message "Console signal $sig captured but not handled in Step 3 MVP."
                    }
                }
                $sig = 0
            }

            # Optional simple line input forwarding.
            if ([string]$Config.InputMode -eq "Line" -and [Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    $line = $inputLineBuffer.ToString()
                    [void]$inputLineBuffer.Clear()
                    [Console]::WriteLine("")
                    $session.WriteInputString($line + "`r`n", [string]$Config.InputEncoding)
                }
                elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                    if ($inputLineBuffer.Length -gt 0) {
                        $inputLineBuffer.Length = $inputLineBuffer.Length - 1
                        [Console]::Write("`b `b")
                    }
                }
                elseif ($key.KeyChar -ne [char]0) {
                    [void]$inputLineBuffer.Append($key.KeyChar)
                    [Console]::Write($key.KeyChar)
                }
            }

            # Process exit detection.
            if ($session.HasExited()) {
                $result.AppExitCode = $session.GetExitCode()
                if ($result.TriggerReason -eq "Unknown") { $result.TriggerReason = "AppExited" }
                if ($result.FinalState -eq "Unknown") { $result.FinalState = "Exited" }
                $running = $false
                continue
            }

            # Trigger timeout handling.
            if ($null -ne $triggerDeadline -and (Get-Date) -gt $triggerDeadline) {
                $result.TimedOut = $true
                if ($result.TriggerReason -eq "Unknown") { $result.TriggerReason = "Timeout" }
                Write-WrapperLog -Config $Config -Level "WARN" -Message "App did not exit before trigger timeout. KillOnTimeout=$($Config.KillOnTimeout)"
                if ([bool]$Config.KillOnTimeout) {
                    $session.Kill()
                    $result.WasKilled = $true
                    $result.FinalState = "Killed"
                    Start-Sleep -Milliseconds 100
                    try { $result.AppExitCode = $session.GetExitCode() } catch {}
                    $running = $false
                }
                else {
                    $result.FinalState = "Timeout"
                    $running = $false
                }
            }

            Start-Sleep -Milliseconds 30
        }
    }
    catch {
        $result.TriggerReason = "ScriptError"
        $result.FinalState = "Error"
        Add-WrapperError -Result $result -Message ([string]$_)
        Write-WrapperLog -Config $Config -Level "ERROR" -Message "Wrapper error: $_"
        if ($null -ne $session) {
            try {
                if (-not $session.HasExited()) {
                    $session.Kill()
                    $result.WasKilled = $true
                }
            } catch {}
        }
    }
    finally {
        if ($null -ne $session) {
            try {
                # Drain remaining output before disposal.
                Start-Sleep -Milliseconds 100
                $chunk = $null
                while ($session.TryDequeueOutput([ref]$chunk)) {
                    if ($null -ne $chunk -and $chunk.Length -gt 0) {
                        [Console]::Write($chunk)
                        Write-AppOutputLogChunk -Config $Config -Text $chunk
                    }
                    $chunk = $null
                }
                $capturedOutput = $session.CapturedOutput
                if ($Config.ContainsKey("StripAnsiSequences") -and [bool]$Config.StripAnsiSequences) {
                    $capturedOutput = Remove-WrapperAnsiSequences -Text $capturedOutput
                }
                $result.StdoutBytes = $session.StdoutBytes
                $result.OutputLines = $session.OutputLines
            } catch {}

            try { $session.Dispose() } catch {}
        }

        try { [PsMainConpty.SignalRouter]::Unregister(); [PsMainConpty.SignalRouter]::Clear() } catch {}
        Clear-WrapperConsoleInputBuffer

        try {
            Invoke-WrapperPostActions -Config $Config -Result $result -CapturedOutput $capturedOutput | Out-Null
        }
        catch {
            Add-WrapperError -Result $result -Message "Invoke-WrapperPostActions failed: $_"
        }

        Complete-WrapperResult -Result $result | Out-Null
        $exitHex = "null"
        if ($null -ne $result.AppExitCode) {
            $exitValue = [int64]$result.AppExitCode
            $unsignedExitValue = if ($exitValue -lt 0) { [uint64]($exitValue + 4294967296) } else { [uint64]$exitValue }
            $exitHex = "0x{0:X8}" -f $unsignedExitValue
        }
        Write-WrapperLog -Config $Config -Message "Result: TriggerReason=$($result.TriggerReason), FinalState=$($result.FinalState), ExitCode=$($result.AppExitCode)($exitHex), WasKilled=$($result.WasKilled), TimedOut=$($result.TimedOut)"
        Write-WrapperLog -Config $Config -Message "=== Wrapper PowerShellMain ended ==="
    }

    return $result
}

$userConfig = . $ConfigPath
$config = Merge-WrapperConfig -UserConfig $userConfig
$result = Invoke-PsMainWrapper -Config $config

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
