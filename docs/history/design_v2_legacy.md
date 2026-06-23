# ConPTY 通用包装器脚本 - 双实现详细设计 v2

版本：2.0  
日期：2026-06-17  
目标平台：最低 Windows 10 1809+（ConPTY 可用）；推荐/主要验证 Windows 10 22H2+，Windows PowerShell 5.1，.NET Framework 4.5+

---

## 0. 本版设计的核心修正

本设计将包装器定义为：

> 面向 Windows 控制台 stdio / line-oriented 程序的通用 ConPTY 包装器。

它不是无限通用终端模拟器，不承诺完整支持所有 TUI、鼠标、复杂 Console API 输入事件、GUI 程序、服务程序或自行 detach console 的程序。

本版同时设计两种实现：

1. **方案 A：PowerShell 主控版**  
   PowerShell 负责主状态机、配置、日志、后处理、输入输出队列；C# 仅提供必要 P/Invoke/helper。

2. **方案 B：PowerShell + C# WrapperHost 版**  
   PowerShell 负责配置和后处理；C# 负责 ConPTY、进程、管道、控制台事件、隐藏窗口、异步 IO、资源释放。

两者必须共享同一套配置模型、结果模型、测试矩阵，便于公平比较。

---

## 1. 目标与非目标

### 1.1 目标

包装第三方黑盒控制台程序 `app.exe` 或其他控制台程序，提供：

| 编号 | 能力 | 说明 |
|---|---|---|
| G1 | 实时输出 | app 输出实时显示到宿主控制台 |
| G2 | 日志分流 | wrapper 自身日志写文件，不污染 app 正常输出 |
| G3 | Ctrl+C 转发 | 用户 Ctrl+C 不中断 wrapper，而是转发给 app |
| G4 | 控制台关闭保护 | 用户点击窗口 X 时尽力通知 app 优雅退出 |
| G5 | 关机/注销保护 | 系统关机/注销时尽力通知 app 优雅退出 |
| G6 | 输入转发 | 将宿主控制台用户输入转发给 app |
| G7 | 环境变量注入 | 为 app 设置自定义环境变量 |
| G8 | 工作目录控制 | 可配置 app 工作目录 |
| G9 | 超时与强杀 | app 不退出时可按策略强制终止 |
| G10 | 后处理框架 | 根据结果执行文件校验、脚本钩子等后处理 |
| G11 | 可扩展匹配 | 未来支持输出内容匹配与自动响应（reserved，rc1 未实现） |

### 1.2 非目标

不承诺支持：

- GUI 程序；
- Windows Service；
- 完整全屏 TUI，例如 vim、复杂 curses 程序；
- 鼠标事件；
- 精确键盘事件流，例如方向键组合、Alt 序列、原始 `ReadConsoleInput` 事件；
- 自行创建/分离控制台的程序；
- 反调试、反重定向、检测终端后改变行为的程序。

---

## 2. 支持程序范围

### 2.1 推荐支持对象

- 普通 Windows 控制台程序；
- 基于 stdin/stdout/stderr 的行式交互程序；
- 能在 ConPTY 中运行；
- 对 Ctrl+C 的响应依赖标准控制台输入处理机制；
- 输出为文本，可用指定编码解码。

### 2.2 风险对象

| 类型 | 风险 |
|---|---|
| 复杂 TUI | 输出包含大量 ANSI/control sequence，输入需要原始键盘事件 |
| 禁用 processed input 的程序 | 写入 `0x03` 可能只变成普通字符，无法触发 Ctrl+C |
| 大量输出程序 | wrapper 必须持续 drain pipe，否则可能导致 app 阻塞 |
| 忽略 Ctrl+C 程序 | wrapper 只能超时后强杀 |
| 子进程树复杂程序 | 仅等待主进程可能不足，需要可选 job object 支持 |

---

## 3. 通用配置模型

两种实现必须支持同一配置模型。PowerShell 中建议使用 Hashtable，传给 C# 时可序列化为 JSON 或手动映射。

```powershell
$WrapperConfig = @{
    # 必需
    AppPath = "C:\path\to\app.exe"

    # 可选
    AppArgs = @()
    WorkingDirectory = $null

    EnvironmentVariables = @{}
    InheritParentEnvironment = $true

    CreateDirectories = @()

    LogFilePath = ".\wrapper.log"
    AppOutputLogFilePath = $null

    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"

    InputMode = "Line"    # None / Line supported; Char is reserved/experimental

    CtrlCTimeoutSeconds = 5
    KillOnTimeout = $true

    CloseAppWaitMilliseconds = 2000
    CloseHandlerBudgetMilliseconds = 3000
    CloseReserveMilliseconds = 800
    CloseSkipPostActions = $true

    ShutdownAppWaitMilliseconds = 2000
    ShutdownHandlerBudgetMilliseconds = 3000
    ShutdownReserveMilliseconds = 800
    ShutdownSkipPostActions = $true

    EnableCtrlCForwarding = $true
    EnableCtrlBreakEmergencyExit = $true
    EnableConsoleCloseHandling = $true
    EnableShutdownSentinel = $true

    ShutdownMode = "BestEffort"  # BestEffort / CancelAndReissue，默认只实现 BestEffort

    StripAnsiSequences = $false

    PostActions = @()
}
```

### 3.1 配置优先级

1. 脚本默认值；
2. 配置文件；
3. 命令行参数；
4. 运行时显式传入参数。

当前 rc1 至少支持脚本内配置对象；外部配置加载可作为后续增强。

---

## 4. 通用结果模型

包装器必须输出结构化结果，供日志、后处理、测试比较使用。

```powershell
$WrapperResult = @{
    WrapperVersion = "unknown"
    Implementation = "PowerShellMain" # PowerShellMain / CSharpHost

    AppPath = $null
    AppPid = $null

    StartTime = $null
    EndTime = $null
    DurationMs = $null

    TriggerReason = "Unknown"
    # AppExited / CtrlC / CtrlClose / Shutdown / Timeout / Break / StartupFailed / ConPTYFailed / ScriptError

    FinalState = "Unknown"
    # Exited / Killed / FailedToStart / FailedToCreateConPTY / Aborted / Error

    AppExitCode = $null
    WasKilled = $false
    TimedOut = $false

    CtrlCSent = $false
    CloseEventReceived = $false
    ShutdownEventReceived = $false

    StdoutBytes = 0
    OutputLines = 0

    PostActions = @()
    Errors = @()
}
```

### 4.1 TriggerReason 与 FinalState 分离

不能只用一个 `ExitReason`。例如：

```text
TriggerReason = CtrlC
FinalState = Exited
AppExitCode = 0
```

和：

```text
TriggerReason = CtrlC
FinalState = Killed
TimedOut = true
```

含义完全不同。

---

## 5. 通用生命周期模型

```text
Initialize configuration
  -> prepare directories
  -> initialize logging
  -> create ConPTY
  -> start app with environment and working directory
  -> register console/shutdown handlers
  -> start IO pumps
  -> main wait loop
  -> trigger handling: app exit / Ctrl+C / close / shutdown / timeout / break
  -> cleanup resources
  -> post actions
  -> return result
```

资源释放必须尽量幂等：重复调用 cleanup 不应抛出致命错误。

---

## 6. 信号策略

### 6.1 Ctrl+C：强目标

用户按宿主控制台 Ctrl+C 后：

1. wrapper 捕获宿主控制台 `CTRL_C_EVENT`；
2. wrapper 返回 TRUE，阻止 PowerShell 默认中断；
3. wrapper 向 ConPTY 输入端写入 ASCII ETX 字节 `0x03`，即终端输入层面的 Ctrl+C 控制字符；
4. 在目标程序保持标准控制台 processed input 行为时，ConPTY/控制台层会将该控制字符解释为 Ctrl+C 控制输入，使目标程序收到 Ctrl+C 语义，例如触发 `SetConsoleCtrlHandler` 注册的 `CTRL_C_EVENT`；
5. wrapper 等待 app 退出；
6. 若超时，根据 `KillOnTimeout` 决定强杀或返回超时结果；
7. 执行通用后处理。

关键澄清：`0x03` 与 Windows 的 `CTRL_C_EVENT` 不是同一层概念。`0x03` 是终端输入流中的控制字符；`CTRL_C_EVENT` 是 Windows 控制台控制事件。wrapper 写入 `0x03` 是与 ConPTY 的终端输入通信约定，用来模拟用户在伪终端中按下 Ctrl+C，而不是假设 app 一定会从 stdin 读取到字符 `0x03` 后自行退出。

注意：如果目标程序禁用 processed input、改写控制台模式、或不在 ConPTY 前台控制台语义内，`0x03` 可能退化为普通输入字符，无法触发 Ctrl+C 控制事件。此时 wrapper 只能按超时策略处理。

### 6.2 Ctrl+Break：紧急出口

默认不转发给 app。用于 wrapper 卡死或 app 无响应时人工退出。

策略：

```text
CTRL_BREAK_EVENT -> TriggerReason=Break -> 尽快清理/强杀 -> 退出
```

### 6.3 控制台关闭：尽力而为

`CTRL_CLOSE_EVENT` 是关闭通知，不应视为可完全取消的普通事件。

处理策略：

1. handler/native 层立即向 ConPTY 写入 `0x03`；
2. 在 `CloseAppWaitMilliseconds` / close budget 内等待 app 退出；
3. 超时则根据配置强杀；
4. 记录最小必要日志；
5. 不依赖 PowerShell `finally` 完成关键业务清理。

文档不得承诺“返回 TRUE 后主循环必然继续完整执行”。

### 6.4 关机/注销：默认 BestEffort

`WM_QUERYENDSESSION` 返回 `FALSE` 代表拒绝/取消本次会话结束，不是“暂停后自动放行”。`ShutdownBlockReasonCreate` 只提供阻止原因说明，不是异步锁。

默认模式：`ShutdownMode = BestEffort`

```text
收到关机/注销信号
  -> 尽快向 app 发送 Ctrl+C
  -> 等待 ShutdownAppWaitMilliseconds / shutdown budget
  -> 超时按策略处理
  -> 允许系统继续
```

高级模式：`CancelAndReissue`（reserved，未实现）（reserved，未实现）

```text
收到 WM_QUERYENDSESSION
  -> 返回 FALSE 取消本次关机
  -> wrapper 完整处理 app 退出与后处理
  -> 可选调用 ExitWindowsEx 重新发起关机
```

第一阶段不实现 `CancelAndReissue`，仅在设计中保留。

---

## 7. ConPTY 管道所有权

必须明确句柄方向，避免实现传错句柄。

| 句柄 | 持有者 | 用途 | 传给 CreatePseudoConsole | wrapper 保留 |
|---|---|---|---|---|
| inputRead | ConPTY | ConPTY 从此读取 wrapper 写入的数据 | 是，作为 hInput | 否 |
| inputWrite | wrapper | wrapper 写入用户输入、`0x03` | 否 | 是 |
| outputWrite | ConPTY | ConPTY 将 app 输出写入此端 | 是，作为 hOutput | 否 |
| outputRead | wrapper | wrapper 从此读取 app 输出 | 否 | 是 |

启动后必须关闭不再需要的句柄，避免 EOF 无法到达或资源泄漏。

---

## 8. IO 策略

### 8.1 输出读取

禁止在主循环中直接阻塞读取 ConPTY output pipe。

推荐：

```text
输出读取线程/Runspace
  -> 阻塞 ReadFile/output stream read
  -> 使用 Decoder 处理跨 chunk 多字节字符
  -> 放入线程安全队列
  -> EOF 时设置事件
```

主循环只消费队列和事件。

### 8.2 UTF-8 与跨 chunk 解码

不得对每个 byte chunk 独立调用 `Encoding.GetString()` 并丢弃 decoder 状态。对于 UTF-8 中文输出，字符可能跨 chunk 分裂。

必须使用：

```csharp
Decoder decoder = Encoding.UTF8.GetDecoder();
```

或 PowerShell 中等价的持续 decoder 状态。

### 8.2.1 ConPTY 输出不是纯 stdout 文本

ConPTY output 是终端渲染流，不是传统匿名管道意义上的干净 stdout。即使目标程序只使用 `printf`，输出流中也可能出现 conhost/terminal 生成的 VT/ANSI 控制序列，例如：

- `ESC[2J`：清屏；
- `ESC[H`：光标归位；
- `ESC]0;title BEL`：设置窗口标题；
- `ESC[?25h`：显示光标；
- `ESC[60X`：擦除若干字符。

因此 wrapper 必须区分：

| 输出去向 | 默认策略 |
|---|---|
| 宿主控制台 | 保留原始终端流，便于正确渲染 |
| app output log | 可按 `StripAnsiSequences` 生成纯文本日志 |
| 内容匹配/PostActions | 可按 `StripAnsiSequences` 使用清洗后的文本 |

`StripAnsiSequences` 不是完整终端模拟器，只是面向行式程序日志和简单正则匹配的清洗器。复杂 TUI 若需要可回放日志，应保留 raw stream。

### 8.2.2 Windows PowerShell 5.1 脚本编码约束

Windows PowerShell 5.1 对无 BOM 的 UTF-8 `.ps1` 文件并不总是按 UTF-8 读取，包含中文字符串的配置文件可能被系统 ANSI 代码页误解码，表现为 `捕获到` 变成 `鎹曡幏鍒` 之类 mojibake。

约束：

1. 发布给 PowerShell 5.1 执行的 `.ps1` 文件建议保存为 UTF-8 with BOM；
2. 配置文件中的测试正则尽量使用 ASCII-only 表达式，例如 `Ctrl\+C`；
3. 如果必须在配置文件中写中文断言，必须明确要求该配置文件为 UTF-8 with BOM；
4. 代码中不得使用 PowerShell 7 的 `` `e`` ESC 字面量；PowerShell 5.1 中应使用 `[char]27` 构造 ESC。


### 8.2.3 Windows PowerShell 自动变量命名约束

Windows PowerShell 变量名大小写不敏感，且存在自动变量 `$args`。包装器函数、参数、局部变量不得使用 `$Args` / `$args` 作为自定义参数名或状态名。

真实测试中曾出现如下问题：

```powershell
function Join-WrapperCommandLineArgs {
    param([object[]]$Args)
    ...
}
```

在 Windows PowerShell 5.1 中，该命名与自动变量 `$args` 语义混淆，导致 `AppArgs` 明明存在，但拼接出的 `AppArgsLine` 为空。修正方式是使用明确名称：

```powershell
function Join-WrapperCommandLineArgs {
    param([object[]]$ArgumentList)
    ...
}
```

约束：

1. 禁止自定义参数名 `$Args` / `$args`；
2. Hashtable 配置访问优先使用 `$Config["Key"]`，不要依赖 `$Config.Key`；
3. 每次启动 app 前必须记录 `AppArgsRawCount`、`AppArgsRaw`、`AppArgsLine`，便于排查参数传递问题。

### 8.3 输入转发

第一阶段支持：

- `InputMode=None`：不读取宿主输入；
- `InputMode=Line`：读取整行，追加换行后写入 ConPTY。

`Char` 模式作为后续扩展（reserved/experimental）。


#### 8.3.1 MVP Line 输入模式限制

当前 MVP 的 `InputMode=Line` 不是 raw keyboard emulator。它的行为是：

1. 普通字符作为文本累积；
2. Enter 触发整行写入 ConPTY；
3. Backspace 做简单本地编辑；
4. 实际按下 Ctrl+C 会进入 console signal handler，不作为字符串进入 stdin；
5. 用户键入字面量 `/n`、`\n`、`\x03` 只会作为普通字符发送，不会被 wrapper 翻译为换行或 ETX。

因此 echo 测试中输入特殊字面量没有干扰程序，不是因为 wrapper 做了复杂过滤，而是因为这些输入本身只是普通字符。真正的 Ctrl+C 由信号路径处理。


#### 8.3.2 Unicode 输入与控制台代码页限制

测试发现，`InputEncoding=utf-8` 只代表 wrapper 写入 ConPTY input pipe 时使用 UTF-8 编码，并不自动保证目标程序能按 UTF-8 解释 stdin。目标程序若使用 C runtime 的 `fgets`/`scanf` 读取控制台输入，还受其控制台输入代码页影响。

例如测试程序若只调用：

```c
SetConsoleOutputCP(CP_UTF8);
```

只能保证输出代码页，不保证输入代码页。若要让 `fgets` 更可能正确读取 UTF-8 输入，测试程序还应调用：

```c
SetConsoleCP(CP_UTF8);
```

当前 MVP 的 `InputMode=Line` 使用按键级读取和本地行缓冲，主要适合 ASCII/普通 BMP 文本。它对以下输入不作强保证：

1. IME 组合输入；
2. surrogate pair，例如 `𠮷`；
3. combining marks / Zalgo 文本，例如 `H̷e̷l̷l̷o̷`；
4. 需要 raw keyboard event 的程序。

后续若要提高 Unicode 输入质量，应增加新的输入泵实现：

- 使用独立线程/Runspace 调用 `[Console]::ReadLine()` 获取完整 .NET string；
- 或实现 char-immediate/raw 模式，将按键更接近实时地转发给 ConPTY；
- 明确 local echo 与 ConPTY echo 的关系，避免重复显示用户输入。

---

## 9. 后处理系统

后处理是通用框架，不得写死业务程序。

支持动作建议：

| Type | 说明 |
|---|---|
| FileExists | 检查文件存在 |
| FileContentEquals | 检查文件内容等于期望值 |
| ExitCodeEquals | 检查退出码 |
| RegexOutputContains | 检查输出中包含指定正则 |
| CustomPowerShell | 执行用户提供脚本块 |

示例：

```powershell
PostActions = @(
    @{
        Type = "FileContentEquals"
        Path = "C:\temp\shimtest2\output\output.txt"
        ExpectedContent = "done"
        TrimEnd = $true
        TreatFailureAsError = $true
    }
)
```

这只是 `stdown.c` 的测试配置，不属于 wrapper 核心逻辑。

---

## 10. 方案 A：PowerShell 主控版

### 10.1 职责划分

PowerShell 负责：

- 配置解析；
- 日志；
- 主状态机；
- 队列消费；
- 后处理；
- 结果对象生成。

C# helper 仅负责：

- Win32 P/Invoke；
- 创建 ConPTY；
- CreateProcess with STARTUPINFOEX；
- 必要的管道读写辅助；
- ConsoleCtrlHandler 注册。

### 10.2 线程模型

```text
PowerShell 主线程
  -> main loop

Output Runspace/helper thread
  -> blocking read ConPTY output
  -> enqueue text/data

Input Runspace
  -> ReadLine
  -> enqueue input

Optional Sentinel Thread
  -> hidden window message pump
```

### 10.3 风险

- Runspace 终止不干净；
- `[Console]::ReadLine()` 难以取消；
- close/shutdown 时 PowerShell finally 不可靠；
- 句柄生命周期复杂；
- 大量输出下更容易出现阻塞或性能问题。

### 10.4 适用定位

快速验证需求、内部工具、低频运行、用户重视部署和修改便利性。

---

## 11. 方案 B：PowerShell + C# WrapperHost 版

### 11.1 职责划分

PowerShell 负责：

- 配置对象；
- 参数覆盖；
- 日志路径准备；
- 调用 C# WrapperHost；
- 后处理；
- 输出最终结果。

C# WrapperHost 负责：

- ConPTY 创建/销毁；
- pipe 所有权管理；
- CreateProcess；
- 环境块构造；
- 工作目录设置；
- 异步输出读取；
- 输入写入；
- Ctrl+C/Close/Shutdown handler；
- timeout/kill；
- 资源释放；
- 返回结构化结果。

### 11.2 推荐 C# 类型

```csharp
public sealed class WrapperConfig { ... }
public sealed class WrapperResult { ... }
public sealed class ConPtySession : IDisposable { ... }
public sealed class ConsoleSignalRouter : IDisposable { ... }
public sealed class ShutdownSentinel : IDisposable { ... }
public static class WrapperHost { public static string RunJson(string configJson); }
```

### 11.3 适用定位

长期运行、生产使用、更强边界稳定性、更可维护的 native 资源管理。

---

## 12. 测试矩阵

| 测试 | 程序/场景 | 目标 | 状态 |
|---|---|---|---|
| T1 | stdown/app.exe | 实时输出、UTF-8、Ctrl+C、环境变量、文件 PostAction | PASS |
| T2 | ignore_ctrlc.exe | 忽略 Ctrl+C 后 timeout + kill | PASS |
| T3 | bulk_output.exe normal | 大量输出、输出 drain、最后一行捕获 | PASS |
| T4 | bulk_output.exe Ctrl+C | 大量输出中断，默认 `0xC000013A` 路径 | PASS with ctrlc config |
| T5 | stderr_output.exe | ConPTY terminal stream 中 stdout/stderr 可见性 | PASS |
| T6 | exit_code.exe | AppArgs 与退出码传播 | PASS |
| T7 | no_output_sleep.exe | 长时间无输出但自然退出 | PASS |
| T8 | echo_stdin.exe | 基础 line input 转发 | PASS for basic line input |
| T9 | args_env.exe | 多参数、环境变量覆盖/继承 | PASS |
| T10 | complex Unicode input | IME/surrogate/combining stress | LIMITED / deferred |

### 12.1 stdown.c 验收配置不是 wrapper 核心逻辑

针对当前 `stdown.c`，测试成功条件：

1. app 启动后每 500ms 输出递增数字；
2. 用户 Ctrl+C 后 app 输出“捕获到 Ctrl+C 信号”；
3. app 退出码为 0；
4. wrapper 注入 `APP_CONFIG_PATH`；
5. `APP_CONFIG_PATH\output\output.txt` 存在；
6. 文件内容为 `done`；
7. wrapper 结果为 `TriggerReason=CtrlC`，`FinalState=Exited`，`WasKilled=false`。

这些条件通过 PostActions 表达，不写死在 wrapper 核心中。

---

## 13. 实施路线

1. 修改设计文档为双实现设计；
2. 固化统一配置模型和结果模型；
3. 实现方案 A：PowerShell 主控最小可用版；
4. 实现方案 B：PowerShell + C# WrapperHost 最小可用版；
5. 使用共同测试矩阵测试；
6. 对比两种实现并选主路线；
7. 最后补充控制台关闭和关机处理。

---

## 14. 已知限制

1. Close/Shutdown 均为尽力而为，不能承诺绝对完成后处理；
2. Ctrl+C 转发依赖目标程序在 ConPTY 下保持标准 processed input 行为；
3. PowerShell 5.1 对 UTF-8、异步 IO、控制台事件的处理有天然复杂度；
4. ConPTY 下 stdout/stderr 是终端输出流语义，不应假设一定可分离；
5. 子进程树治理第一阶段不实现，后续可考虑 Job Object。


---

## 15. Close/Shutdown 后处理分级策略

不同信号源下，wrapper 的后处理承诺不同。必须明确区分，不能把 Ctrl+C 的完整后处理承诺套用到窗口关闭或关机事件。

| 信号源 | 目标 | 后处理策略 | 保证级别 |
|---|---|---|---|
| Ctrl+C | 用户请求 app 优雅退出，但 wrapper 仍可完整运行 | 正常主循环等待 app 退出，执行完整 PostActions 和日志 | 强目标 |
| Ctrl+Break | 紧急中断 wrapper/app | 尽快中断/kill，最小日志 | 紧急路径 |
| CTRL_CLOSE_EVENT | 用户关闭控制台窗口 | 在 handler/native 路径内尽快发送 `0x03`，短等待，必要时 kill；只做最小日志 | Best-effort |
| CTRL_LOGOFF/SHUTDOWN | 系统会话结束 | 尽快发送 `0x03`，短等待，必要时 kill；不承诺完整 PostActions | Best-effort |
| WM_QUERYENDSESSION | 系统关机消息 | 默认 BestEffort，不默认取消关机 | Best-effort |

### 15.1 CTRL_CLOSE_EVENT 专用原则

`CTRL_CLOSE_EVENT` 表示用户不想继续运行 wrapper 和内部业务程序。此时 wrapper 的目标不是执行完整业务后处理，而是：

1. 尽快向 ConPTY input 写入 ETX `0x03`；
2. 在 `CloseAppWaitMilliseconds` 与 close handler budget 限制内等待业务程序退出；
3. 超时后按 `KillOnTimeout` 决定是否终止业务程序；
4. 记录最小必要日志；
5. 不依赖 PowerShell `finally`、PostActions、JSON 输出一定完成。

因此 Close 场景应使用独立的 close best-effort path，而不是复用普通 Ctrl+C 后处理流程。

### 15.2 Close 时间预算与用户体验策略

测试显示，如果把 close handler 的可用时间全部用于等待业务程序，Windows 可能在 wrapper 来得及记录 timeout/kill/complete 日志前终止控制台进程。因此 Close 场景需要使用独立预算：

```text
CloseAppWaitMilliseconds       # 等待业务程序退出的目标时间，默认 2000ms
CloseHandlerBudgetMilliseconds # handler 里愿意使用的总预算，默认 3000ms
CloseReserveMilliseconds       # 留给 wrapper kill、短输出 drain、最小日志的保留时间，默认 800ms
```

实际等待业务程序的时间为：

```text
effectiveAppWaitMs = min(CloseAppWaitMilliseconds,
                         CloseHandlerBudgetMilliseconds - CloseReserveMilliseconds)
```

默认值下，Close 场景实际 app wait 约为 2000ms，handler 总预算约 3000ms，留约 800ms 给 wrapper 做最小收尾。

0.1.9 曾尝试在 Close 路径隐藏控制台窗口，但测试证明该操作不安全，相关 public config 已移除。当前 Close 路径不做窗口 UX 操作，只做信号、短等待、必要时 kill 和最小日志。


### 15.3 0.1.9 Close UX 回归与修正

测试 0.1.9 发现：在 `CTRL_CLOSE_EVENT` handler 内调用 `GetConsoleWindow/ShowWindow(SW_HIDE)` 可能使控制台窗口进入不可交互/冻结状态，并且阻塞在发送 ETX `0x03` 之前，导致业务程序收不到 Ctrl+C，最终被系统或 wrapper 强制结束。

结论：

1. 不应在 `CTRL_CLOSE_EVENT` handler 内直接隐藏/最小化当前控制台窗口；
2. Close UX 隐藏需求不能优先于业务安全退出；
3. 当前版本已移除 `CloseHideWindowOnClose` public config；
4. 若未来仍要做“用户点击 X 后窗口立即消失”的产品体验，应使用独立 helper 进程或宿主级方案，而不是在 close handler 内操作同一个 closing console window。

同时，Close 场景不再复用 `CloseTimeoutSeconds` 作为实际 app wait，而使用独立配置：

```powershell
CloseAppWaitMilliseconds = 2000
CloseHandlerBudgetMilliseconds = 3000
CloseReserveMilliseconds = 800
```

Ctrl+C 正常路径仍只使用：

```powershell
CtrlCTimeoutSeconds
```

两者必须保持独立，避免不同信号源的后处理语义混用。

### 15.4 信号路径计时指标

为了调优不同信号源下的时间预算，wrapper 应记录关键计时指标：

| 指标 | 含义 |
|---|---|
| signalQueueLatencyMs | native handler 捕获信号到主循环处理信号的排队延迟，主要用于 Ctrl+C 路径 |
| sendLatencyMs | 向 ConPTY input 写入 ETX `0x03` 的耗时 |
| appExitAfterCtrlCSentMs | 发送 Ctrl+C 后 app 退出所用时间 |
| waitElapsedMs | Close/Shutdown best-effort 等待 app 的实际耗时 |
| PostActionsDurationMs | 完整后处理耗时，仅普通路径强保证 |

这些指标用于评估业务程序退出耗时和 wrapper 后处理耗时，避免盲目调整 `CtrlCTimeoutSeconds`、`CloseAppWaitMilliseconds` 等配置。

### 15.5 Close UX 备选方案分析

0.1.9 已证明在 close handler 内隐藏窗口风险高。最小化窗口、修改窗口尺寸、本地调整控制台 buffer/window size 本质上仍是对“正在关闭的同一个 console window”做 UI 操作，风险与隐藏窗口同类：

1. 可能阻塞 close handler；
2. 可能导致窗口不可交互但未关闭；
3. 可能发生在发送 Ctrl+C 之前，破坏业务安全退出；
4. 在 Windows Terminal、传统 conhost、IDE terminal 中行为不一致。

因此当前结论：系统级事件中不做 UX 操作。若未来要改善“点击 X 后视觉上立即消失”的产品体验，应设计独立 helper/supervisor 模型，而不是在 `CTRL_CLOSE_EVENT` handler 内操作当前窗口。

### 15.6 Logoff/Shutdown Best-effort 策略

`CTRL_LOGOFF_EVENT` 与 `CTRL_SHUTDOWN_EVENT` 与窗口关闭类似，均属于系统级限时通知。当前 CSharpHost 实现采用独立配置，不复用 Ctrl+C 或 Close 配置：

```powershell
ShutdownAppWaitMilliseconds = 2000
ShutdownHandlerBudgetMilliseconds = 3000
ShutdownReserveMilliseconds = 800
ShutdownSkipPostActions = $true
```

处理原则：

1. 不做任何窗口 UX 操作；
2. 尽快向 ConPTY input 写入 ETX `0x03`；
3. 在独立 shutdown budget 内等待业务程序退出；
4. 超时按 `KillOnTimeout` 处理；
5. 默认跳过 PostActions；
6. 记录最小 timing 日志。

该路径仍然是 best-effort，不承诺 PowerShell finally、JSON 输出、PostActions 完整执行。

### 15.7 0.1.13 ShutdownEventRouter（已废弃记录）

测试显示，仅依赖 `SetConsoleCtrlHandler` 捕获 `CTRL_LOGOFF_EVENT` / `CTRL_SHUTDOWN_EVENT` 不可靠：在 `shutdown /l` 或 `shutdown /r /t 0` 下，wrapper 与 app 可能几乎同时被系统结束，控制台 handler 没有机会写入 ETX `0x03`。

0.1.13 曾在 CSharpHost 中尝试增加基于 `.NET SystemEvents.SessionEnding` 的 `ShutdownEventRouter`，但后续测试证明该方案不可靠，已由 0.1.15 的 hidden-window `WM_QUERYENDSESSION` 路线替代。历史尝试如下：

```text
SystemEvents.SessionEnding
  -> Logoff 映射为 CTRL_LOGOFF_EVENT 语义
  -> Shutdown 映射为 CTRL_SHUTDOWN_EVENT 语义
  -> 调用同一套 best-effort handler
```

该方案仍然是 best-effort：

1. 不取消注销/关机；
2. 不做 UX 操作；
3. 使用 `ShutdownAppWaitMilliseconds` 等独立预算；
4. 可能受系统策略、关机速度、PowerShell 进程状态影响；
5. 推荐在虚拟机中测试。

如果该方案仍不可靠，下一候选方案是专用 hidden window + `WM_QUERYENDSESSION`，但实现复杂度和风险更高。

### 15.8 大量输出与 Close 并发日志写入

`bulk_output.exe` 测试中发现 close handler 的短输出 drain 与常规 output reader/main loop 可能同时写 `AppOutputLogFilePath`，导致 `File.AppendAllText` 抛出文件占用异常。0.1.14 修正：

1. CSharpHost 的 wrapper log 与 app output log 均使用进程内 lock；
2. 文件打开使用 `FileShare.ReadWrite`；
3. app output log 写入失败在 best-effort 路径中被吞掉，不再破坏 close handler。

大量输出程序未注册 Ctrl+C handler 时，Close/Ctrl+C 可能触发默认 `STATUS_CONTROL_C_EXIT`，导致程序未完整输出全部内容。这是目标程序默认控制台行为，不是 wrapper 强杀。

### 15.9 系统事件配置注意

历史测试中曾出现 `ShutdownEventRouter registered. EnableShutdownSentinel=False`。这属于已废弃 SystemEvents 路径的诊断记录。当前 rc1 使用 `ShutdownWindowRouter`，相关 sample config 已启用：

```powershell
EnableShutdownSentinel = $true
```

进行注销/关机测试前必须确认 wrapper 日志显示：

```text
ShutdownWindowRouter registered. EnableShutdownSentinel=True
```

否则该测试无效。

### 15.10 0.1.15 Hidden Window WM_QUERYENDSESSION

0.1.15 增加 `ShutdownWindowRouter`，创建专用隐藏窗口并处理：

```text
WM_QUERYENDSESSION
WM_ENDSESSION
```

与 `SystemEvents.SessionEnding` 相比，该方案更直接接近 Windows 会话结束消息。处理策略仍然是：

1. 返回 TRUE，不取消注销/关机；
2. 不做 UX 操作；
3. 调用同一套 Logoff/Shutdown best-effort handler；
4. 使用独立 shutdown 预算；
5. 不承诺完整 PostActions/JSON/finally。

同时修复大量输出 Close 场景中的输出日志乱序风险：对 ConPTY output queue 的 dequeue+write 整体加锁，而不仅仅对文件写入加锁。

### 15.11 AppOutputLog 定位与边界

`AppOutputLogFilePath` 是 wrapper 提供的辅助观测能力，不是业务程序的权威日志系统。它的定位是：

1. 帮助没有日志能力的控制台程序获得一份近似输出记录；
2. 为测试和 PostActions 提供 captured output；
3. 辅助排查 wrapper 与 app 的交互。

它不是核心安全职责，不应为了追求 close/shutdown 场景下 app output log 的完整、有序、无丢失而牺牲 wrapper 的核心目标：

```text
启动 app -> 转发 IO -> 转发信号 -> 等待/kill -> 环境变量 -> 最小可靠日志/结果
```

尤其在 `CTRL_CLOSE_EVENT`、注销、关机场景中，app output log 只能是 best-effort。若业务需要强一致日志，应由业务程序自身写日志，或使用专门的 raw capture/audit 模块。当前 `bulk_output` 乱序/竞态修复到“避免 wrapper 自身异常、尽量保持顺序”即可，不继续把它提升为核心保证。

### 15.12 Normal Exit 输出 drain 与用户可见性

`bulk_output.exe` 自然退出测试发现：reader 已捕获完整输出、PostActions 也可匹配最后一行，但控制台还没来得及显示全部 queued output，wrapper 就打印 summary 并退出，造成用户看到 “输出未结束但程序已完成” 的错觉。

0.1.16 增加正常 AppExited 路径专用配置：

```powershell
NormalExitOutputDrainMilliseconds = 10000
```

普通自然退出路径会等待 reader EOF 并 drain output queue 后再打印 summary/退出。该配置不用于 Close/Shutdown；系统级事件仍使用短 best-effort drain。

这属于核心用户可见 IO 桥接，不同于 `AppOutputLogFilePath` 的辅助日志完整性问题。

### 15.13 SetProcessShutdownParameters

Windows 提供 `SetProcessShutdownParameters(dwLevel, dwFlags)` 设置当前进程相对于其他进程的关机顺序。数值越高越先收到 shutdown；默认级别是 `0x280`。应用保留的 first-shutdown range 是 `0x300-0x3FF`。

0.1.17 增加：

```powershell
```

并在 CSharpHost 启动时调用 `SetProcessShutdownParameters`。这不是替代 `WM_QUERYENDSESSION` 的机制，只是提高 wrapper 在关机序列中较早收到通知的机会。它不保证清理一定完成，也不解决系统强制终止问题。

默认不启用 `SHUTDOWN_NORETRY`，因为 wrapper 的 best-effort 路径本身较短，且隐藏系统 retry/blocking 提示不利于诊断。

### 15.14 0.1.18 Normal Exit drain quiet period

测试发现，ConPTY reader 的 EOF 在子进程退出后不一定立即可见；如果普通退出路径硬等 `OutputEof == true`，wrapper 可能总是等满 `NormalExitOutputDrainMilliseconds`。0.1.18 增加：

```powershell
NormalExitOutputQuietMilliseconds = 250
```

普通 AppExited 路径现在在满足以下任一条件时结束 drain：

1. `OutputEof == true && output queue empty`；
2. output queue 为空并保持 quiet period；
3. 超过 `NormalExitOutputDrainMilliseconds`。

这样既避免 summary 插入业务输出中间，也避免每次都等待完整 10 秒预算。

### 15.15 0.1.18 Output drain 设计评审

0.1.18 的 normal exit drain 通过 `OutputQueueIsEmpty + quiet period` 解决了 summary 插入业务输出中间的问题，但这不是最终理想设计。

关键澄清：normal drain 调用发生在 wrapper 已经通过 process handle 确认业务进程退出之后，因此 quiet period 不是用来判断“业务进程是否退出”，而是用来判断“reader 已观察到的输出是否已经稳定且队列已清空”。

但是，`OutputEof` 不应作为核心判断条件，因为 ConPTY reader 的 EOF 可能在子进程退出后延迟，甚至受 HPCON/pipe 生命周期影响。后续 Step 8 应重构输出泵状态机，目标语义应是：

```text
业务进程已退出 && 已观测输出队列已清空 && 输出泵稳定
```

而不是：

```text
等待 ConPTY EOF 或等满超时
```

### 15.16 timing 指标精度限制

当前 timing 日志多使用 `DateTime.UtcNow` 并格式化到毫秒小数。对于极短路径，例如 handler 内立即调用 `WriteFile` 写入 ETX，真实耗时可能低于计时源分辨率，或在同一系统 tick 内完成，因此会显示：

```text
sendLatencyMs=0.000
handlerEntryLatencyMs=0.000
```

这不代表没有测量，也不代表耗时绝对为零，而是代表“低于当前计时方式可分辨范围”。后续若需要更精确的性能分析，应改用 `System.Diagnostics.Stopwatch`。

### 15.17 0.1.19 Normal Exit drain: close HPCON after process exit

Step 8 第一轮修正：普通 AppExited 路径不再主要依赖“等待自然 ConPTY EOF”。在业务进程已通过 process handle 确认退出后，wrapper 显式调用：

```text
Close inputWrite
ClosePseudoConsole(hPC)
```

但保留 outputRead，让 reader thread 读取 ConPTY output pipe 中的剩余缓冲，直到 EOF，然后 normal drain 等待：

```text
process exited
  -> ClosePseudoConsoleForOutputCompletion
  -> reader observes EOF
  -> output queue empty
  -> summary/result
```

这比 0.1.18 的 quiet-period workaround 更接近正确 ConPTY 生命周期。`NormalExitOutputQuietMilliseconds` 保留为 fallback，而非主完成条件。

### 15.18 Step 8 Phase 1 结论

0.1.19 的 normal AppExited output drain 方案通过测试。普通退出路径采用：

```text
process exited
  -> ClosePseudoConsoleForOutputCompletion
  -> reader observes EOF
  -> queue empty
  -> print summary/result
```

测试确认：

1. `stdown Ctrl+C` 正常，无 10 秒停顿；
2. `bulk_output` 正常退出时 summary 严格位于最后业务输出之后；
3. `bulk_output Ctrl+C` 时 wrapper 状态记录正确，业务断言失败属于测试预期差异；
4. `bulk_output Close` 仍按 best-effort 处理。

`AppOutputLogFilePath` 在最近测试中表现为严格递增、无空行。这说明当前输出串行化和 normal drain 改进对辅助日志的实际顺序有正面作用。但该日志仍不是业务强一致日志，Close/Shutdown 场景仍只承诺 best-effort。

### 15.19 Step 8 Phase 2 方向

下一阶段先不实现 Unicode/raw input。应先进行架构审视和清理：

1. 检查是否存在残留代码和废弃路径；
2. 审视配置项是否过多、命名是否清晰、是否有场景混用；
3. 明确 core responsibilities 与 auxiliary features 的边界；
4. 审查 hidden window、shutdown priority、output drain、post-action 等模块之间的耦合；
5. 列出尚未覆盖的边界风险；
6. 在继续新增功能前形成稳定化建议。
