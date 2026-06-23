#include <stdio.h>
#include <windows.h>
#include <stdbool.h>

volatile bool keep_running = true;

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
    if (ctrlType == CTRL_C_EVENT) {
        printf("[ignore_ctrlc.exe] Ctrl+C received but intentionally ignored.\n");
        fflush(stdout);
        return TRUE;
    }
    return FALSE;
}

int main(void) {
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCtrlHandler(ConsoleHandler, TRUE);
    int i = 0;
    printf("[ignore_ctrlc.exe] started. Ctrl+C will be ignored.\n");
    fflush(stdout);
    while (keep_running) {
        printf("ignore-loop:%d\n", i++);
        fflush(stdout);
        Sleep(500);
    }
    return 0;
}
