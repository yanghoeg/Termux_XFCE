# 설치 매트릭스 테스트 — 실행/유지 가이드

이 문서는 `install.sh`의 모든 CLI 옵션 조합을 검증하는 매트릭스 테스트와,
"설치 → 오류 → 수정 → push → 초기화 → 재설치" 자동화 루프를 다음 세션에서도
재현 가능하도록 정리한 기록이다.

---

## 1. 빠른 실행

```bash
cd ~/Termux_XFCE
git checkout dev && git pull

# 단위 + e2e 전체
bash tests/run_tests.sh

# 매트릭스만 (CLI 옵션 조합 dispatch 검증, mock 기반, 빠름)
bash tests/test_install_matrix.sh
```

매트릭스 테스트는 `_INSTALL_HOOK` 환경변수를 사용해 install.sh의 모든
`setup_*` 도메인 함수를 트레이스 스텁으로 교체한다. **실제 설치는 일어나지 않는다.**
훅 주입 지점: `install.sh` step 7 (도메인 로드 직후) 종료선.

---

## 2. 테스트 케이스

케이스 수는 `tests/test_install_matrix.sh`의 `it` 항목 수 그대로다 —
정확한 통과/실패 건수는 `bash tests/test_install_matrix.sh` 실행 결과를 참고할 것
(이 표의 건수는 스냅샷이며 테스트 추가/삭제 시 갱신 필요).

| # | 카테고리 | CLI / 환경변수 | 검증 |
|---|----------|----------------|------|
| 1 | native | `--no-proot` | termux_base/xfce_packages/xfce_autostart/termux_shortcuts/display_setup_apk/termux_api_apk/termux_float_apk 호출, proot_install 없음 |
| 2 | proot-only | `--proot-only --distro ubuntu --user testuser` | termux_base/xfce_packages/display_setup_apk/termux_api_apk/termux_float_apk 없음, proot_install/proot_user/proot_alias 호출 |
| 3 | proot-only | `--proot-only --distro archlinux --user testuser` | termux_base 없음, proot_install/proot_alias 호출 |
| 4 | full | `--distro ubuntu --user testuser` | termux_base/proot_install/proot_base_packages/proot_alias/display_setup_apk 모두 호출 |
| 5 | full | `--distro archlinux --user testuser` | termux_base/proot_install/proot_alias 모두 호출 |
| 6 | env vars | `SKIP_PROOT=true` | termux_base 호출, proot_install 없음 |
| 7 | env vars | `DISTRO=ubuntu USERNAME=testuser` | termux_base/proot_install 모두 호출 |
| 8 | CLI 검증 | `--help` | exit 0 |
| 9 | CLI 검증 | `--not-a-real-flag` | non-zero exit |
| 10 | CLI 검증 | `--distro freebsd --user testuser` | non-zero exit |
| 11 | CLI 검증 | `--distro ubuntu --user 'bad;name'` | non-zero exit (위험 문자 사용자명 거부) |
| 12 | CLI 검증 | `--no-proot --proot-only` | non-zero exit (모드 충돌) |
| 13 | CLI 검증 | `--no-proot --distro ubuntu` | non-zero exit (no-proot에 distro 지정 불가) |
| 14 | CLI 검증 | `PROOT_SHELL=fish --distro ubuntu --user testuser` | non-zero exit (지원하지 않는 shell) |
| 15 | config | `--distro ubuntu --user lideok` | config에 `PROOT_DISTRO="ubuntu"`/`PROOT_USER="lideok"` 기록, 권한 600 |
| 16 | config | `--no-proot` | config의 `PROOT_DISTRO=""` |
| 17 | config | 기존 config `PROOT_SHELL="zsh"` + `--proot-only --distro ubuntu --user lideok` | 재실행해도 기존 `PROOT_SHELL="zsh"` 유지 (never reset) |
| 18 | config | 구버전 config(키 누락, `DISPLAY_SERVER="x11"`만 존재) + `--proot-only --distro ubuntu --user testuser` | rc 0, 병합된 config에 `PROOT_SHELL="bash"`(기본값) 기록 |
| 19 | config | `PROOT_SHELL=zsh` + `--distro ubuntu --user testuser` (신규 설치) | rc 0, config에 `PROOT_SHELL="zsh"` 기록 |
| 20 | config | 기존 config `PROOT_SHELL="bash"` + `PROOT_SHELL=zsh` + `--proot-only --distro ubuntu --user testuser` | rc 0, config가 `PROOT_SHELL="zsh"`로 덮어써짐 |
| 21 | config | 기존 config `DISPLAY_SERVER="wayland"` + `--proot-only --distro ubuntu --user lideok` (`--display` 미지정) | 재실행해도 기존 `DISPLAY_SERVER="wayland"` 유지 |

---

## 3. 자동화 루프 워크플로우

사용자 요청: **모든 옵션 조합을 실제 설치 → 오류 시 수정 → dev push → 패키지만 제거 → 재설치 반복**

```
1. baseline:  bash tests/run_tests.sh
2. matrix:    bash tests/test_install_matrix.sh
3. for each combo in §2:
     a) bash install.sh <options>      # 실제 설치 시도
     b) 오류 발생 시:
        - 근본 원인 파악 (스택 추적, 로그)
        - domain/* 또는 adapter/* 수정
        - 회귀 테스트 추가 (tests/test_*.sh)
        - bash tests/run_tests.sh 통과 확인
        - git add -p && git commit && git push origin dev
     c) 패키지 제거(초기화):
        - Termux native: pkg uninstall <목록>
        - proot: bash tests/autopilot.sh 의 teardown_proot 패턴 참고
4. matrix 다시 실행 → 모든 조합 통과까지 반복
```

**주의**:
- "초기화"는 **설치 패키지만** 제거 (`pkg uninstall`) — Termux 환경 자체나 홈 디렉토리는 보존.
- proot 제거: `proot-distro remove <distro>` (autopilot.sh §단계4 참조).
- gh 인증은 이미 완료 (`gh auth status`로 확인). HTTPS 토큰 사용.

---

## 4. 변경 이력

- **exit code 검증 실패 교훈**: `set -euo pipefail` 하의 서브셸에서 `bash install.sh ...`가
  non-zero로 종료하면 `set -e`가 즉시 트립해 `local rc=$?` 라인에 도달하지 못하고 테스트가
  단순 실패로 보고된다. 해결: `cmd ... || rc=$?` 패턴으로 exit code를 캡처 (`set -e` 면제됨).
- **GPU 가속·한글 입력기 선택용 CLI 플래그 4종(및 대응 환경변수) 제거**: 이전 버전에서
  선택적 구성요소 설치에 쓰이던 플래그들은 모두 사라졌다 — 해당 구성요소는 이제 설치 후
  App Installer에서 선택한다. 매트릭스는 그 대신 `PROOT_SHELL`/`DISPLAY_SERVER`
  config 보존 여부(§2의 17~21번)를 커버한다.
