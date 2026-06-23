#include <stdio.h>
#include <windows.h>

int main(void) {
    SetConsoleOutputCP(CP_UTF8);
    fprintf(stdout, "[stderr_output.exe] stdout line 1\n");
    fprintf(stderr, "[stderr_output.exe] stderr line 1\n");
    fprintf(stdout, "[stderr_output.exe] stdout line 2\n");
    fprintf(stderr, "[stderr_output.exe] stderr line 2\n");
    fflush(stdout);
    fflush(stderr);
    return 0;
}
