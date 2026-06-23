#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

int main(int argc, char** argv) {
    SetConsoleOutputCP(CP_UTF8);
    int code = 7;
    if (argc > 1) code = atoi(argv[1]);
    printf("[exit_code.exe] exiting with code %d\n", code);
    fflush(stdout);
    return code;
}
