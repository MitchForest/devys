#include <stdio.h>

int main(void) {
    const char *name = "Devys";
    for (int i = 0; i < 3; i++) {
        printf("Hello %s %d\n", name, i);
    }
    return 0;
}
