#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

static void print_env(const char* name) {
    const char* v = getenv(name);
    printf("env:%s=%s\n", name, v ? v : "<null>");
}

int main(int argc, char** argv) {
    SetConsoleOutputCP(CP_UTF8);
    printf("[args_env.exe] argc=%d\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("argv[%d]=%s\n", i, argv[i]);
    }
    print_env("APP_CONFIG_PATH");
    print_env("WRAPPER_TEST_ENV1");
    print_env("WRAPPER_TEST_PROXY");
    print_env("APPDATA");
    print_env("USERPROFILE");
    fflush(stdout);
    return 0;
}
