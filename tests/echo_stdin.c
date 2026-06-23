#include <stdio.h>
#include <string.h>
#include <windows.h>

int main(void) {
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    char buf[4096];
    printf("[echo_stdin.exe] ready. Type lines; 'quit' exits.\n");
    fflush(stdout);
    while (fgets(buf, sizeof(buf), stdin)) {
        printf("echo:%s", buf);
        fflush(stdout);
        if (strncmp(buf, "quit", 4) == 0) {
            printf("[echo_stdin.exe] quit received.\n");
            fflush(stdout);
            return 0;
        }
    }
    printf("[echo_stdin.exe] stdin EOF.\n");
    return 0;
}
