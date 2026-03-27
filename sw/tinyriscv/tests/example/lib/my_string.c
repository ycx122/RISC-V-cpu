#include "../include/my_string.h"
#define size_t int
#define NULL 0

void *my_memcpy(void *dest, const void *src, size_t n) {
    // 将输入参数转换为字符指针以便逐字节操作
    char *d = (char *)dest;
    const char *s = (const char *)src;

    // 确保源和目标指针不为 NULL 且不会重叠
    if (d == NULL || s == NULL || d == s) {
        return dest;
    }

    // 拷贝 n 个字节，从源到目标
    for (size_t i = 0; i < n; ++i) {
        d[i] = s[i];
    }

    // 返回目标指针
    return dest;
}

void *my_memset(void *str, int c, size_t n) {
    // 将输入参数转换为字符指针，以便逐字节操作
    unsigned char *s = (unsigned char *)str;

    // 填充 n 个字节，使用给定的值 c
    for (size_t i = 0; i < n; ++i) {
        s[i] = (unsigned char)c;
    }

    // 返回原始内存块指针
    return str;
}

int my_memcmp(const void *str1, const void *str2, size_t n) {
    // 将输入参数转换为无符号字符指针，以便逐字节操作
    const unsigned char *s1 = (const unsigned char *)str1;
    const unsigned char *s2 = (const unsigned char *)str2;

    // 逐字节比较两个内存区域
    for (size_t i = 0; i < n; ++i) {
        if (s1[i] != s2[i]) {
            return s1[i] - s2[i];
        }
    }

    // 如果所有字节都相同，返回0
    return 0;
}