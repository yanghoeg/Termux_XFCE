/*
 * hostinfo_net — Host Info Bridge 네트워크 카운터 (termux-xfce-hostinfo 데몬이 -w로 띄워 둔다)
 *
 * Android은 앱에서 /proc/net/dev·/sys/class/net 통계·netlink RTM_GETLINK를 모두 막는다.
 * TrafficStats가 쓰는 시스템 서비스 netstats의 getIfaceStats는 권한 없이 부를 수 있으므로,
 * getifaddrs()에 보이는 인터페이스마다 그 값을 받아 두 모양으로 쓴다.
 *   - OUT/net/<if>/statistics/{rx,tx}_bytes: btop이 읽는 /sys/class/net 모양
 *   - OUT/proc_net/dev: /proc/net/dev 형식(htop·psutil·bmon·ifconfig). 에러·드롭 등 netstats에 없는 열은 0이다
 *
 * 사용: hostinfo_net [-w] OUT — 한 번 쓰고 끝난다. -w면 1초마다 다시 쓰고, 띄운 프로세스(부모)가 끝나면 끝난다.
 *       값을 하나도 얻지 못하면 1로 끝난다.
 */
/* libbinder_ndk는 API 29부터다 — 함수는 모두 dlsym으로 찾고 헤더는 형식에만 쓴다 */
#define __ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__
#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* binder_manager.h는 NDK에 없다 */
AIBinder *AServiceManager_checkService(const char *instance);

/* framework-connectivity-t.jar INetworkStatsService$Stub.TRANSACTION_getIfaceStats.
 * Android 16은 StatsResult getIfaceStats(String iface)다 — 응답 모양이 다르면 쓰지 않는다 */
#define GET_IFACE_STATS 12

#define FN(name) static __typeof__(name) *p_##name
FN(AServiceManager_checkService);
FN(AIBinder_Class_define);
FN(AIBinder_associateClass);
FN(AIBinder_prepareTransaction);
FN(AIBinder_transact);
FN(AParcel_writeString);
FN(AParcel_readStatusHeader);
FN(AParcel_readInt32);
FN(AParcel_readInt64);
FN(AParcel_delete);
FN(AStatus_isOk);
FN(AStatus_delete);

static int load(void)
{
    /* 이름만으로 열면 RUNPATH($PREFIX/lib)의 libandroid-stub 가짜 라이브러리가 먼저 잡힌다 */
    void *lib = dlopen("/system/lib64/libbinder_ndk.so", RTLD_NOW);

#define LOAD(name) if (!(p_##name = (__typeof__(name) *)dlsym(lib, #name))) return 0
    if (!lib)
        return 0;
    LOAD(AServiceManager_checkService);
    LOAD(AIBinder_Class_define);
    LOAD(AIBinder_associateClass);
    LOAD(AIBinder_prepareTransaction);
    LOAD(AIBinder_transact);
    LOAD(AParcel_writeString);
    LOAD(AParcel_readStatusHeader);
    LOAD(AParcel_readInt32);
    LOAD(AParcel_readInt64);
    LOAD(AParcel_delete);
    LOAD(AStatus_isOk);
    LOAD(AStatus_delete);
    return 1;
}

/* 원격 서비스만 부르므로 로컬 객체 콜백은 쓰이지 않는다 */
static void *on_create(void *args) { return args; }
static void on_destroy(void *data) { (void)data; }
static binder_status_t on_transact(AIBinder *b, transaction_code_t code, const AParcel *in, AParcel *out)
{
    (void)b; (void)code; (void)in; (void)out;
    return STATUS_UNKNOWN_TRANSACTION;
}

/* 응답: 예외 헤더, 널 아님(1), 크기(36), StatsResult { rxBytes, rxPackets, txBytes, txPackets } */
static int query(AIBinder *svc, const char *iface, int64_t v[4])
{
    AParcel *in = NULL, *out = NULL;
    AStatus *st = NULL;
    int32_t nonnull = 0, size = 0;
    int i, ok = 0;

    if (p_AIBinder_prepareTransaction(svc, &in) != STATUS_OK)
        return 0;
    if (p_AParcel_writeString(in, iface, (int32_t)strlen(iface)) != STATUS_OK) {
        p_AParcel_delete(in);
        return 0;
    }
    /* transact는 성공 여부와 상관없이 in을 지운다 */
    if (p_AIBinder_transact(svc, GET_IFACE_STATS, &in, &out, 0) != STATUS_OK)
        return 0;
    if (p_AParcel_readStatusHeader(out, &st) == STATUS_OK && p_AStatus_isOk(st) &&
        p_AParcel_readInt32(out, &nonnull) == STATUS_OK && nonnull == 1 &&
        p_AParcel_readInt32(out, &size) == STATUS_OK && size == 4 + 4 * 8) {
        for (i = 0; i < 4 && p_AParcel_readInt64(out, &v[i]) == STATUS_OK; i++)
            ;
        ok = i == 4;
    }
    if (st)
        p_AStatus_delete(st);
    p_AParcel_delete(out);
    return ok;
}

/* 같은 inode에 덮어쓴다 — 바꿔치기하면 fd를 열어 둔 채 다시 읽는 프로그램이 옛 값에 멈춘다.
 * 게스트에 바인드된 디렉터리(/sys/class/net·/proc/net)에 심은 심볼릭 링크는 따라가지 않고 일반 파일로 바꾼다 */
static void put(const char *path, const char *data, int len)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0644);

    if (fd < 0 && errno == ELOOP && unlink(path) == 0)
        fd = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (fd < 0)
        return;
    if (write(fd, data, len) == len)
        ftruncate(fd, len);
    close(fd);
}

static void put_stat(const char *out, const char *iface, const char *name, int64_t v)
{
    char path[PATH_MAX], buf[32];
    int n = snprintf(buf, sizeof buf, "%" PRId64 "\n", v);

    snprintf(path, sizeof path, "%s/net/%s", out, iface);
    mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/net/%s/statistics", out, iface);
    mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/net/%s/statistics/%s", out, iface, name);
    put(path, buf, n);
}

/* getifaddrs()에 보이는 인터페이스마다 값을 받아 쓴다. 하나도 얻지 못하면 0 */
static int update(AIBinder *svc, const char *out)
{
    /* 커널과 같은 머리글 두 줄 — psutil 등은 두 줄을 건너뛰고 읽는다 */
    static const char header[] =
        "Inter-|   Receive                                                |  Transmit\n"
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n";
    struct ifaddrs *ifs, *a, *b;
    char dev[16384], path[PATH_MAX];
    int64_t v[4];
    int len = sizeof header - 1, ok = 0;

    if (getifaddrs(&ifs) != 0)
        return 0;
    memcpy(dev, header, len);
    for (a = ifs; a; a = a->ifa_next) {
        /* 주소마다 항목이 하나씩이라 같은 이름이 여러 번 나온다 */
        for (b = ifs; b != a && strcmp(b->ifa_name, a->ifa_name) != 0; b = b->ifa_next)
            ;
        if (b != a || !query(svc, a->ifa_name, v))
            continue;
        put_stat(out, a->ifa_name, "rx_bytes", v[0]);
        put_stat(out, a->ifa_name, "tx_bytes", v[2]);
        if (len < (int)sizeof dev)
            len += snprintf(dev + len, sizeof dev - len,
                            "%6s: %7" PRId64 " %7" PRId64 "    0    0    0     0          0         0"
                            " %8" PRId64 " %7" PRId64 "    0    0    0     0       0          0\n",
                            a->ifa_name, v[0], v[1], v[2], v[3]);
        ok = 1;
    }
    freeifaddrs(ifs);
    if (ok && len < (int)sizeof dev) {
        snprintf(path, sizeof path, "%s/proc_net/dev", out);
        put(path, dev, len);
    }
    return ok;
}

int main(int argc, char **argv)
{
    pid_t parent = getppid();
    int watch = argc == 3 && strcmp(argv[1], "-w") == 0;
    const char *out = argv[argc - 1];
    AIBinder *svc;
    AIBinder_Class *cls;

    if (argc != 2 && !watch) {
        fprintf(stderr, "사용법: hostinfo_net [-w] OUT\n");
        return 2;
    }
    if (!load() || !(svc = p_AServiceManager_checkService("netstats")) ||
        !(cls = p_AIBinder_Class_define("android.net.INetworkStatsService", on_create, on_destroy, on_transact)) ||
        !p_AIBinder_associateClass(svc, cls))
        return 1;
    while (update(svc, out)) {
        if (!watch)
            return 0;
        sleep(1);
        if (getppid() != parent)
            return 0;
    }
    return 1;
}
