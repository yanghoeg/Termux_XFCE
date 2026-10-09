/*
 * hostinfo_proc.so — Termux 네이티브 프로그램(htop 등)용 Host Info Bridge LD_PRELOAD 훅
 *
 * Android은 앱에서 /proc/stat·/proc/uptime·/proc/loadavg 읽기를 막는다(EACCES).
 * 원래 파일이 EACCES로 열리지 않는 읽기 전용 열기·읽기 확인만 TERMUX_XFCE_HOSTINFO 디렉터리의
 * 같은 이름 파일(termux-xfce-hostinfo가 1초마다 갱신)로 다시 시도한다.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* 막힌 /proc 항목이면 alt에 대체 경로를 채우고 1을 돌려준다 */
static int bridged(const char *path, char alt[PATH_MAX])
{
    const char *dir = getenv("TERMUX_XFCE_HOSTINFO");
    const char *name;

    if (!path || !dir || !*dir || strncmp(path, "/proc/", 6) != 0)
        return 0;
    name = path + 6;
    if (strcmp(name, "stat") != 0 && strcmp(name, "uptime") != 0 && strcmp(name, "loadavg") != 0)
        return 0;
    return snprintf(alt, PATH_MAX, "%s/%s", dir, name) < PATH_MAX;
}

FILE *fopen(const char *path, const char *mode)
{
    static FILE *(*real)(const char *, const char *);
    char alt[PATH_MAX];
    FILE *f, *g;

    if (!real)
        real = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen");
    f = real(path, mode);
    if (f || errno != EACCES || mode[0] != 'r' || strchr(mode, '+') || !bridged(path, alt))
        return f;
    g = real(alt, mode);
    if (!g)
        errno = EACCES;
    return g;
}

/* open과 openat 모두 실제 openat으로 연다 (open은 openat(AT_FDCWD, …)과 같다) */
static int open_bridged(int dirfd, const char *path, int flags, mode_t mode)
{
    static int (*real)(int, const char *, int, ...);
    char alt[PATH_MAX];
    int fd;

    if (!real)
        real = (int (*)(int, const char *, int, ...))dlsym(RTLD_NEXT, "openat");
    fd = real(dirfd, path, flags, mode);
    if (fd >= 0 || errno != EACCES || (flags & O_ACCMODE) != O_RDONLY || !bridged(path, alt))
        return fd;
    fd = real(dirfd, alt, flags, mode);
    if (fd < 0)
        errno = EACCES;
    return fd;
}

/* mode 인자는 O_CREAT·O_TMPFILE일 때만 넘어온다 */
#define NEEDS_MODE(flags) (((flags) & O_CREAT) || ((flags) & O_TMPFILE) == O_TMPFILE)

int open(const char *path, int flags, ...)
{
    mode_t mode = 0;

    if (NEEDS_MODE(flags)) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    return open_bridged(AT_FDCWD, path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...)
{
    mode_t mode = 0;

    if (NEEDS_MODE(flags)) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    return open_bridged(dirfd, path, flags, mode);
}

/* Termux htop은 /proc/stat을 열기 전에 access(R_OK)로 먼저 확인하고, 막혀 있으면 CPU를 읽지 않는다 */
static int access_bridged(int dirfd, const char *path, int mode, int flags)
{
    static int (*real)(int, const char *, int, int);
    char alt[PATH_MAX];
    int rc;

    if (!real)
        real = (int (*)(int, const char *, int, int))dlsym(RTLD_NEXT, "faccessat");
    rc = real(dirfd, path, mode, flags);
    if (rc == 0 || errno != EACCES || (mode & (W_OK | X_OK)) || !bridged(path, alt))
        return rc;
    rc = real(dirfd, alt, mode, flags);
    if (rc != 0)
        errno = EACCES;
    return rc;
}

int access(const char *path, int mode)
{
    return access_bridged(AT_FDCWD, path, mode, 0);
}

int faccessat(int dirfd, const char *path, int mode, int flags)
{
    return access_bridged(dirfd, path, mode, flags);
}
