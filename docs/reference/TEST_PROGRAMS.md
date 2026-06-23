# Test programs

Compile on Windows with MinGW-w64 or MSVC Developer Command Prompt.

## MinGW-w64 example

```powershell
mkdir .\bin -Force
x86_64-w64-mingw32-gcc .\tests\stdown.c -o .\bin\app.exe
x86_64-w64-mingw32-gcc .\tests\echo_stdin.c -o .\bin\echo_stdin.exe
x86_64-w64-mingw32-gcc .\tests\ignore_ctrlc.c -o .\bin\ignore_ctrlc.exe
x86_64-w64-mingw32-gcc .\tests\bulk_output.c -o .\bin\bulk_output.exe
x86_64-w64-mingw32-gcc .\tests\stderr_output.c -o .\bin\stderr_output.exe
x86_64-w64-mingw32-gcc .\tests\exit_code.c -o .\bin\exit_code.exe
x86_64-w64-mingw32-gcc .\tests\no_output_sleep.c -o .\bin\no_output_sleep.exe
x86_64-w64-mingw32-gcc .\tests\args_env.c -o .\bin\args_env.exe
```

## MSVC example

Run from a Developer Command Prompt:

```cmd
mkdir bin
cl /Fe:bin\app.exe tests\stdown.c
cl /Fe:bin\echo_stdin.exe tests\echo_stdin.c
cl /Fe:bin\ignore_ctrlc.exe tests\ignore_ctrlc.c
cl /Fe:bin\bulk_output.exe tests\bulk_output.c
cl /Fe:bin\stderr_output.exe tests\stderr_output.c
cl /Fe:bin\exit_code.exe tests\exit_code.c
cl /Fe:bin\no_output_sleep.exe tests\no_output_sleep.c
cl /Fe:bin\args_env.exe tests\args_env.c
```
