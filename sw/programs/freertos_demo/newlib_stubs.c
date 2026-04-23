/*
 * sw/programs/freertos_demo/newlib_stubs.c
 *
 * Minimal freestanding implementations of the handful of libc symbols
 * that FreeRTOS (and sometimes GCC's builtin lowering) expect to find.
 * We link with -nostdlib/-nodefaultlibs, so there is no newlib to pull
 * these in for us.  Each function is kept deliberately tiny and
 * branch-free-ish -- none of the call sites is performance-critical
 * on this core.
 */

#include <stddef.h>
#include <stdint.h>

void *memset(void *dst, int c, size_t n)
{
    unsigned char       *d  = (unsigned char *)dst;
    const unsigned char  v  = (unsigned char)c;
    while (n--) *d++ = v;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d == s || n == 0) return dst;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (n--) {
        if (*pa != *pb) return (int)*pa - (int)*pb;
        pa++; pb++;
    }
    return 0;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}
