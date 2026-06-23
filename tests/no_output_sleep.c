#include <windows.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    int seconds = 5;
    if (argc > 1) seconds = atoi(argv[1]);
    Sleep(seconds * 1000);
    return 0;
}
