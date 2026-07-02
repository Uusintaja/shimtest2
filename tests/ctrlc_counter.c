#include <stdio.h>
#include <windows.h>
#include <stdbool.h>

volatile bool keep_running = true;
volatile LONG ctrlc_count = 0;
ULONGLONG first_tick = 0;

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
    if (ctrlType == CTRL_C_EVENT) {
        ULONGLONG now = GetTickCount64();
        if (first_tick == 0 || now - first_tick > 2000) {
            first_tick = now;
            InterlockedExchange(&ctrlc_count, 1);
        } else {
            InterlockedIncrement(&ctrlc_count);
        }

        LONG count = ctrlc_count;
        printf("[ctrlc_counter.exe] Ctrl+C received. count=%ld\n", count);
        fflush(stdout);

        if (count >= 3) {
            printf("[ctrlc_counter.exe] Triple Ctrl+C threshold reached. Exiting.\n");
            fflush(stdout);
            keep_running = false;
        }
        return TRUE;
    }
    return FALSE;
}

int main(void) {
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCtrlHandler(ConsoleHandler, TRUE);
    printf("[ctrlc_counter.exe] started. Press Ctrl+C three times within 2 seconds to exit.\n");
    fflush(stdout);
    int i = 0;
    while (keep_running) {
        printf("ctrlc-counter-loop:%d\n", i++);
        fflush(stdout);
        Sleep(300);
    }
    printf("[ctrlc_counter.exe] exiting with code 0.\n");
    fflush(stdout);
    return 0;
}
