#include <stdio.h>
#include <windows.h>

int main(void) {
    SetConsoleOutputCP(CP_UTF8);
    for (int i = 0; i < 20000; i++) {
        printf("bulk-line:%05d abcdefghijklmnopqrstuvwxyz 中文输出测试\n", i);
        if ((i % 100) == 0) fflush(stdout);
    }
    fflush(stdout);
    return 0;
}
