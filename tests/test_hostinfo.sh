#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: termux-xfce-hostinfo (Android Host Info Bridge)
#   - 코어별 cpuidle 체류 시간으로 /proc/stat을 만들고, 꺼진 코어는 뺀다
#   - proot-distro sysdata(stat/uptime/loadavg)와 chroot-ng용 파일을 같은 inode에 덮어쓴다
#     (top/vmstat은 fd를 열어 둔 채 되감아 읽으므로 바꿔치기하면 값이 멈춘다)
#   - getprop으로 DMI·cpuinfo Hardware 줄을 만든다
#   - Termux 네이티브 htop: exec가 hostinfo_proc.so 훅을 붙이고, 훅은 EACCES인 /proc만 대신 연다
# 가짜 sysfs·getprop·uptime으로 생성된 스크립트를 실제 실행해 검증한다.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"
_BASH="${BASH:-$(command -v bash)}"

_setup_hostinfo_sandbox() {
    local sb="$1" n
    setup_fs_sandbox "$sb"
    mock_pkg_adapter
    mock_ui_adapter
    source "${DOMAIN_DIR}/packages.sh"
    source "${DOMAIN_DIR}/../adapters/output/script_builder_zenity.sh"
    source "${DOMAIN_DIR}/termux_env.sh"
    _build_hostinfo_proc() { :; }   # 실제 clang 빌드는 네이티브 htop 테스트에서만 한다
    _setup_hostinfo

    # 코어 3개 중 cpu2는 꺼져 있다. cpu0 idle 합 = 1s + 2s = 3s
    mkdir -p "$sb/cpu"
    echo "0-2" > "$sb/cpu/possible"
    for n in 0 1 2; do mkdir -p "$sb/cpu/cpu$n/cpuidle/state0" "$sb/cpu/cpu$n/cpuidle/state1"; done
    echo 1000000 > "$sb/cpu/cpu0/cpuidle/state0/time"
    echo 2000000 > "$sb/cpu/cpu0/cpuidle/state1/time"
    echo 500000 > "$sb/cpu/cpu1/cpuidle/state0/time"
    echo 0 > "$sb/cpu/cpu1/cpuidle/state1/time"
    echo 1 > "$sb/cpu/cpu1/online"
    echo 0 > "$sb/cpu/cpu2/online"

    mkdir -p "$sb/fakebin" "${PREFIX}/var/lib/proot-distro/containers/archlinux/sysdata"
    cat > "$sb/fakebin/getprop" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
case "$1" in
    ro.product.manufacturer) echo samsung ;;
    ro.product.model) echo SM-F956N ;;
    ro.board.platform) echo pineapple ;;
    ro.soc.manufacturer) echo QTI ;;
    ro.soc.model) echo SM8650 ;;
esac
EOF
    cat > "$sb/fakebin/uptime" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
if [ "$1" = -s ]; then echo "2026-10-01 00:00:00"; else echo " 10:00:00 up 1 day,  0 users,  load average: 1.50, 0.75, 0.25"; fi
EOF
    chmod +x "$sb/fakebin/"*
}

_hostinfo() {
    local sb="$1"; shift
    PATH="$sb/fakebin:$PATH" HOSTINFO_DIR="$sb/out" HOSTINFO_CPU_ROOT="$sb/cpu" \
        HOSTINFO_UPTIME="$sb/fakebin/uptime" "$_BASH" "${PREFIX}/bin/termux-xfce-hostinfo" "$@"
}

_hostinfo_once() { _hostinfo "$1" once; }

describe "termux-xfce-hostinfo — /proc 대체 파일"

_test_stat_from_cpuidle() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local stat="$sb/out/stat" rc=0 btime
    btime=$(date -d "2026-10-01 00:00:00" +%s)
    assert_file_contains "$stat" '^cpu  ' || rc=1
    # cpu0 idle = 3,000,000µs = 300 jiffies (USER_HZ 100)
    assert_file_contains "$stat" '^cpu0 [0-9][0-9]* 0 0 300 ' || rc=1
    assert_file_contains "$stat" '^cpu1 ' || rc=1
    assert_file_not_contains "$stat" '^cpu2 ' || rc=1
    assert_file_contains "$stat" "^btime ${btime}$" || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "cpuidle 체류 시간으로 코어별 /proc/stat을 만들고 꺼진 코어와 btime을 반영한다" _test_stat_from_cpuidle

_test_proot_sysdata_files() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local sd="${PREFIX}/var/lib/proot-distro/containers/archlinux/sysdata" rc=0
    cmp -s "$sb/out/stat" "$sd/stat" || { echo "[ASSERT] sysdata/stat이 chroot-ng용 stat과 다르다" >&2; rc=1; }
    assert_file_contains "$sd/loadavg" '^1.50 0.75 0.25 ' || rc=1
    assert_file_contains "$sd/uptime" '^[0-9][0-9]*\.[0-9][0-9] [0-9][0-9]*\.[0-9][0-9]$' || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "proot-distro sysdata의 stat·uptime·loadavg를 실제 값으로 채운다" _test_proot_sysdata_files

_test_rewrites_same_inode() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local sd="${PREFIX}/var/lib/proot-distro/containers/archlinux/sysdata" before after
    before="$(stat -c %i "$sb/out/stat") $(stat -c %i "$sd/stat")"
    echo 4000000 > "$sb/cpu/cpu0/cpuidle/state0/time"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    after="$(stat -c %i "$sb/out/stat") $(stat -c %i "$sd/stat")"
    local rc=0
    assert_eq "$before" "$after" "갱신해도 inode가 그대로여야 fd를 열어 둔 top이 새 값을 본다" || rc=1
    assert_file_contains "$sb/out/stat" '^cpu0 [0-9][0-9]* 0 0 600 ' || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "같은 inode에 덮어써서 fd를 열어 둔 채 다시 읽는 top/vmstat도 새 값을 본다" _test_rewrites_same_inode

_test_replaces_planted_symlink() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    local sd="${PREFIX}/var/lib/proot-distro/containers/archlinux/sysdata"
    echo "keep" > "$sb/victim"
    ln -s "$sb/victim" "$sd/stat"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local rc=0
    [ ! -L "$sd/stat" ] || { echo "[ASSERT] 심볼릭 링크가 남아 있다" >&2; rc=1; }
    assert_eq "keep" "$(cat "$sb/victim")" "링크 대상 파일을 덮어쓰면 안 된다" || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "sysdata에 심어진 심볼릭 링크를 따라가지 않고 일반 파일로 바꾼다" _test_replaces_planted_symlink

describe "termux-xfce-hostinfo — 기기 정보"

_test_device_info() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local rc=0
    assert_eq "samsung" "$(cat "$sb/out/dmi/sys_vendor")" "sys_vendor" || rc=1
    assert_eq "SM-F956N" "$(cat "$sb/out/dmi/product_name")" "product_name" || rc=1
    assert_eq "pineapple" "$(cat "$sb/out/dmi/board_name")" "board_name" || rc=1
    assert_eq "$(printf 'Hardware\t: Qualcomm Technologies, Inc SM8650')" "$(tail -1 "$sb/out/cpuinfo")" \
        "cpuinfo 끝에 Hardware 줄" || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "getprop으로 DMI(제조사·모델·보드)와 cpuinfo Hardware 줄을 만든다" _test_device_info

describe "termux-xfce-hostinfo — Termux 네이티브 htop"

_test_native_uptime_loadavg() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _hostinfo_once "$sb" || { cleanup_sandbox "$sb"; return 1; }
    local sd="${PREFIX}/var/lib/proot-distro/containers/archlinux/sysdata" rc=0
    cmp -s "$sb/out/uptime" "$sd/uptime" || { echo "[ASSERT] 네이티브용 uptime이 sysdata와 다르다" >&2; rc=1; }
    assert_file_contains "$sb/out/loadavg" '^1.50 0.75 0.25 ' || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}
it "훅이 대신 열 uptime·loadavg도 브리지 디렉터리에 쓴다" _test_native_uptime_loadavg

# exec 대상: 받은 환경과 자기 PID를 출력한다
_write_env_probe() {
    cat > "$1/fakebin/probe" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "pid=$$"
echo "hostinfo=${TERMUX_XFCE_HOSTINFO-unset}"
echo "preload=${LD_PRELOAD-}"
EOF
    chmod +x "$1/fakebin/probe"
}

_test_exec_without_shim() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"; _write_env_probe "$sb"
    local out rc=0
    out=$(_hostinfo "$sb" exec "$sb/fakebin/probe") || rc=1
    assert_output_contains "$out" '^hostinfo=unset$' || rc=1
    assert_eq "preload=${LD_PRELOAD-}" "$(grep '^preload=' <<< "$out")" "LD_PRELOAD를 건드리지 않는다" || rc=1
    # start는 첫 갱신을 동기로 쓰므로, 브리지 디렉터리가 없어야 데몬도 PID 기록도 없었던 것이다
    [ ! -e "$sb/out" ] || { echo "[ASSERT] 훅이 없는데 데몬을 띄우거나 PID를 남겼다" >&2; rc=1; }
    cleanup_sandbox "$sb"; return "$rc"
}
it "훅이 없으면(clang 없이 설치) exec는 명령을 그대로 실행하고 데몬을 띄우지 않는다" _test_exec_without_shim

# 샌드박스 설정이 빌드를 막아 두므로 함수를 다시 읽어 실제 clang으로 빌드한다
_build_real_shim() {
    source "${DOMAIN_DIR}/termux_env.sh"
    SCRIPT_DIR="${DOMAIN_DIR}/.." _build_hostinfo_proc
}

_test_build_shim_once() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    local so="$PREFIX/lib/hostinfo_proc.so" rc=0 before
    _build_real_shim || { cleanup_sandbox "$sb"; return 1; }
    assert_file_exists "$so" || rc=1
    assert_eq "$(sha256sum "${DOMAIN_DIR}/../assets/hostinfo_proc.c" | cut -d' ' -f1)" "$(cat "$so.sha256")" \
        "소스 해시를 기록한다" || rc=1
    before=$(stat -c %i "$so")
    _build_real_shim || rc=1
    assert_eq "$before" "$(stat -c %i "$so")" "소스가 그대로면 다시 빌드하지 않는다" || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}

_test_exec_attaches_shim() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"; _write_env_probe "$sb"
    _build_real_shim || { cleanup_sandbox "$sb"; return 1; }
    # 이미 떠 있는 데몬처럼 보이는 프로세스를 두어 exec가 진짜 데몬을 띄우지 않게 한다
    mkdir -p "$sb/out" && mkfifo "$sb/fifo"
    "$_BASH" -c 'read -t 30 <> "$1"' termux-xfce-hostinfo-dummy "$sb/fifo" &
    local dummy=$! out pid rc=0
    echo "$dummy" > "$sb/out/pid"
    out=$(_hostinfo "$sb" exec "$sb/fakebin/probe") || rc=1
    kill "$dummy" 2>/dev/null; wait "$dummy" 2>/dev/null || true
    pid=$(sed -n 's/^pid=//p' <<< "$out")
    assert_file_exists "$sb/out/holders/$pid" || rc=1
    assert_output_contains "$out" "^hostinfo=$sb/out$" || rc=1
    assert_output_contains "$out" "^preload=$PREFIX/lib/hostinfo_proc.so" || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}

_test_shim_redirects_blocked_proc() {
    local sb; sb=$(make_sandbox); _setup_hostinfo_sandbox "$sb"
    _build_real_shim || { cleanup_sandbox "$sb"; return 1; }
    mkdir -p "$sb/bridge"
    echo "cpu  1 0 0 2 0 0 0 0 0 0" > "$sb/bridge/stat"
    echo "123.45 67.89" > "$sb/bridge/uptime"
    echo "1.50 0.75 0.25 1/1 1" > "$sb/bridge/loadavg"
    cat > "$sb/reader.c" << 'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static void show(const char *tag, int fd)
{
    char buf[64] = "";
    ssize_t n = fd < 0 ? -1 : read(fd, buf, sizeof(buf) - 1);
    printf("%s=%s", tag, n > 0 ? buf : "fail\n");
    if (fd >= 0)
        close(fd);
}

int main(void)
{
    char buf[64] = "";
    FILE *f = fopen("/proc/stat", "r");
    printf("fopen=%s", f && fgets(buf, sizeof(buf), f) ? buf : "fail\n");
    show("open", open("/proc/uptime", O_RDONLY));
    show("openat", openat(AT_FDCWD, "/proc/loadavg", O_RDONLY));
    printf("access=%d\n", access("/proc/stat", R_OK));
    printf("access_w=%d\n", access("/proc/stat", W_OK));
    return 0;
}
EOF
    clang -O2 -o "$sb/reader" "$sb/reader.c" || { cleanup_sandbox "$sb"; return 1; }
    local preload="$PREFIX/lib/hostinfo_proc.so${LD_PRELOAD:+:$LD_PRELOAD}" out plain rc=0
    out=$(TERMUX_XFCE_HOSTINFO="$sb/bridge" LD_PRELOAD="$preload" "$sb/reader")
    plain=$(unset TERMUX_XFCE_HOSTINFO; LD_PRELOAD="$preload" "$sb/reader")
    assert_output_contains "$out" '^fopen=cpu  1 0 0 2 ' || rc=1
    assert_output_contains "$out" '^open=123.45 67.89$' || rc=1
    assert_output_contains "$out" '^openat=1.50 0.75 0.25 ' || rc=1
    assert_output_contains "$out" '^access=0$' || rc=1
    assert_output_contains "$out" '^access_w=-1$' || rc=1
    # 브리지 경로가 없으면 원래 실패(EACCES)를 그대로 돌려준다
    assert_output_contains "$plain" '^fopen=fail$' || rc=1
    assert_output_contains "$plain" '^access=-1$' || rc=1
    cleanup_sandbox "$sb"; return "$rc"
}

if ! command -v clang >/dev/null 2>&1; then
    skip "훅 빌드·exec 연결·/proc 대체 열기 (clang 없음)"
else
    it "clang으로 훅을 빌드하고 소스가 그대로면 다시 빌드하지 않는다" _test_build_shim_once
    it "exec는 훅과 브리지 경로를 붙여 실행하고 데몬이 볼 PID를 남긴다" _test_exec_attaches_shim
    if (read -r _ < /proc/stat) 2>/dev/null; then
        skip "훅의 /proc 대체 열기 (이 환경은 /proc/stat을 직접 읽을 수 있다)"
    else
        it "훅은 EACCES인 /proc/stat·uptime·loadavg 읽기·확인만 브리지 파일로 대신 연다" _test_shim_redirects_blocked_proc
    fi
fi

print_results
