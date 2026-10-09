#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: termux-xfce-hostinfo (Android Host Info Bridge)
#   - 코어별 cpuidle 체류 시간으로 /proc/stat을 만들고, 꺼진 코어는 뺀다
#   - proot-distro sysdata(stat/uptime/loadavg)와 chroot-ng용 파일을 같은 inode에 덮어쓴다
#     (top/vmstat은 fd를 열어 둔 채 되감아 읽으므로 바꿔치기하면 값이 멈춘다)
#   - getprop으로 DMI·cpuinfo Hardware 줄을 만든다
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

_hostinfo_once() {
    local sb="$1"
    PATH="$sb/fakebin:$PATH" HOSTINFO_DIR="$sb/out" HOSTINFO_CPU_ROOT="$sb/cpu" \
        HOSTINFO_UPTIME="$sb/fakebin/uptime" "$_BASH" "${PREFIX}/bin/termux-xfce-hostinfo" once
}

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

print_results
