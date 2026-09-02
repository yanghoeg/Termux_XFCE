#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: adapters — pkg_common_termux.sh의 pkg_install_deb_url sha256 검증
# -----------------------------------------------------------------------------
# nimf 등 GitHub Releases .deb를 dpkg -i 하기 전 sha256 무결성을 검증하는지
# 확인한다 (체크섬 불일치 시 dpkg를 절대 호출하지 않아야 함).
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

ADAPTER_DIR="${SCRIPT_DIR}/../adapters/output"

describe "pkg_common_termux.sh — pkg_install_deb_url sha256 검증"

# mock_wget이 -O 대상 경로에 항상 "PKmock\n"을 쓰므로 그 sha256을 오라클로 사용
_MOCK_DEB_SHA256="4a35a4a6b53fe111142894049b5f24c79fd28aed9a4d2ea3b55573965894a0de"

_test_deb_url_wrong_checksum_blocks_dpkg() {
    source "${ADAPTER_DIR}/pkg_common_termux.sh"
    mock_wget
    reset_mock_calls
    dpkg() { _record_call "dpkg $*"; return 0; }
    apt() { _record_call "apt $*"; return 0; }

    # set -e 하에서 $(...) 대입이 실패 종료 코드를 내면 그 자리에서 subshell이
    # 죽으므로, "성공하면 실패 처리"하는 && 가드로 감싸 exit code를 안전하게 소비한다.
    local out
    out=$(pkg_install_deb_url "https://example.com/nimf_1.4.19_aarch64.deb" "0000000000000000000000000000000000000000000000000000000000000000" 2>&1) && {
        echo "[ASSERT] 체크섬이 틀렸는데도 pkg_install_deb_url이 성공했다: $out" >&2
        return 1
    }

    assert_not_called "dpkg"
    assert_output_contains "$out" "sha256"
}
it "체크섬이 틀리면 dpkg를 호출하지 않고 실패한다" _test_deb_url_wrong_checksum_blocks_dpkg

_test_deb_url_correct_checksum_calls_dpkg() {
    source "${ADAPTER_DIR}/pkg_common_termux.sh"
    mock_wget
    reset_mock_calls
    dpkg() { _record_call "dpkg $*"; return 0; }
    apt() { _record_call "apt $*"; return 0; }

    pkg_install_deb_url "https://example.com/nimf_1.4.19_aarch64.deb" "${_MOCK_DEB_SHA256}"
    local rc=$?

    assert_eq "0" "$rc" "체크섬이 일치하면 성공해야 함"
    assert_was_called "dpkg"
}
it "체크섬이 맞으면 dpkg -i로 설치한다" _test_deb_url_correct_checksum_calls_dpkg

_test_deb_url_no_checksum_skips_verification() {
    source "${ADAPTER_DIR}/pkg_common_termux.sh"
    mock_wget
    reset_mock_calls
    dpkg() { _record_call "dpkg $*"; return 0; }
    apt() { _record_call "apt $*"; return 0; }

    # 체크섬 없이 호출해도(하위 호환) 기존처럼 dpkg가 호출되어야 함
    pkg_install_deb_url "https://example.com/nimf_1.4.19_aarch64.deb"
    local rc=$?

    assert_eq "0" "$rc" "체크섬 인자가 없으면 검증을 건너뛰고 기존처럼 동작해야 함"
    assert_was_called "dpkg"
}
it "체크섬 인자가 없으면 검증 없이 기존 동작을 유지한다 (하위 호환)" _test_deb_url_no_checksum_skips_verification

print_results
