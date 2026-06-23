#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <stdbool.h>

volatile bool keep_running = true;

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
    switch (ctrlType) {
        case CTRL_C_EVENT:
            printf("\n[app.exe] 捕获到 Ctrl+C 信号！正在准备退出循环...\n");
            keep_running = false;
            return TRUE;
        default:
            return FALSE;
    }
}

int main() {
    SetConsoleOutputCP(CP_UTF8);
    if (!SetConsoleCtrlHandler(ConsoleHandler, TRUE)) {
        fprintf(stderr, "[app.exe] 错误: 无法注册控制台信号处理器。\n");
        return 1;
    }

    printf("[app.exe] 已启动。每 500ms 计数一次。按 Ctrl+C 触发优雅退出...\n");

    int counter = 0;
    while (keep_running) {
        printf("%d\n", counter++);
        fflush(stdout);
        Sleep(500);
    }

    printf("[app.exe] 已跳出主循环，开始执行数据保存逻辑...\n");

    char* config_path = getenv("APP_CONFIG_PATH");
    char file_path[MAX_PATH];
    if (config_path != NULL) {
        snprintf(file_path, sizeof(file_path), "%s\\output\\output.txt", config_path);
    } else {
        snprintf(file_path, sizeof(file_path), ".\\output\\output.txt");
    }

    printf("[app.exe] 正在尝试写入文件: %s\n", file_path);

    FILE* file = fopen(file_path, "w");
    if (file != NULL) {
        fprintf(file, "done\n");
        fclose(file);
        printf("[app.exe] 文件写入成功！内容: \"done\"\n");
    } else {
        perror("[app.exe] 错误：无法打开或写入文件（请检查 output 文件夹是否存在）");
    }

    printf("[app.exe] 进程安全退出，返回值 0。\n");
    return 0;
}
