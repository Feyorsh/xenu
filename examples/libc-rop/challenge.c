#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void setup() {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    setvbuf(stdin, NULL, _IONBF, 0);
}

int main() {
    char answer[32];
    
    setup();

    puts("Hey, what's your name? Sorry I keep forgetting it.");
    gets(answer);
    printf("My name is Hugh. Nice to meet you, ");
    printf(answer);
    puts(". Where are you from?");
    gets(answer);
    puts("Cool. I've never been there before!");

    return 0;
}