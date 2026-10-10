# 설치 매트릭스와 검증 가이드

메인 설치기의 분기와 설정 보존은 [test_install_matrix.sh](test_install_matrix.sh),
새 설치·기존 설정 이전은 [test_modern_install.sh](test_modern_install.sh)에서 검사합니다.
호스트 테스트는 실제 Android 설치와 구분합니다. 설치 옵션 설명은
[한국어 README](../README.ko.md#설치)와 [English README](../README.md#installation)를
기준으로 합니다.

## 호스트에서 실행

usix-termux 저장소 루트에서 서브모듈을 초기화한 상태로 실행합니다.

```bash
bash tests/run_tests.sh

# 필요한 스위트만 선택
bash tests/run_tests.sh install_matrix
bash tests/run_tests.sh display_wayland modern_install

# App Installer 자체 스위트
for suite in domain_apps adapters ports fetch proot_path cli; do
    bash "app-installer/tests/test_${suite}.sh" || exit 1
done
```

스위트 이름과 실행 목록은 [run_tests.sh](run_tests.sh)가 관리합니다. 통과·실패·건너뜀
건수는 실행 결과를 확인하며 문서에 고정된 합계로 관리하지 않습니다.
`force_gettext`는 ASan·UBSan을 지원하는 Clang 또는 GCC가 필요하고,
`display_wayland`의 런타임 검사는 Python 3와 로컬 Unix 소켓을 사용합니다. 소켓 생성을
막는 실행 환경에서는 이 검사를 실행할 수 있는 환경이 필요합니다.

## 매트릭스가 검증하는 범위

`_INSTALL_HOOK`은 모든 어댑터·도메인 로드와 계약 검사 이후, 하드웨어 사전 검사 및
실제 설치 전에 실행됩니다. 테스트는 이 지점에서 설치 함수들을 호출 기록용 스텁으로
바꾸고 임시 홈·PREFIX를 사용합니다. 패키지 다운로드, APK 설치, 실제 GPU 검사는
수행하지 않습니다. 실제 배포판 이미지를 설치하는 모든 조합의 E2E 시험도 아닙니다.

| 범위 | 입력 또는 조건 | 검증 내용 |
|------|----------------|-----------|
| native | `--no-proot` | native 기본 구성·XFCE·자동 시작·단축키·APK 함수 호출, proot 설치 생략 |
| 보조 셸 구성 | `setup_xfce_fancybash` 실패 | fancybash 실패가 전체 설치를 중단하지 않음 |
| proot 전용 | Ubuntu / Arch의 `--proot-only --distro … --user …` | native·APK 단계를 생략하고 proot 설치·사용자·진입 명령 구성 |
| 전체 설치 | Ubuntu / Arch의 `--distro … --user …` | native와 proot 구성 모두 호출 |
| 환경변수 | `SKIP_PROOT=true`, `DISTRO=ubuntu USERNAME=testuser` | CLI 대응 환경변수의 설치 분기 |
| 도움말 | `--help` | 성공 종료 |
| 잘못된 입력 | 알 수 없는 플래그, `--distro freebsd`, 잘못된 사용자 이름, `PROOT_SHELL=fish` | 0이 아닌 종료 코드 |
| 모드 충돌 | `--no-proot --proot-only`, `--no-proot --distro ubuntu` | 충돌 거부 |
| 새 설정 | 배포판·사용자 지정, 또는 새 환경의 `--no-proot` | 설정 파일에 배포판·사용자 기록, 권한 600; 새 native 전용 설정의 배포판은 빈 값 |
| 셸 설정 병합 | 기존 `zsh`, 키가 빠진 구형 설정, 명시적 `PROOT_SHELL=zsh` | 기존 값 보존, 누락 시 `bash`, 명시한 값 우선 |
| 디스플레이 보존 | 기존 Wayland 설정에서 `--proot-only` | 저장된 `DISPLAY_SERVER` 유지 |
| Wayland 순서 | `--display wayland --no-proot` | 하드웨어 사전 검사 → XFCE 패키지 → native 런타임 → 런처 → APK 순서 |
| Wayland 거부 | 하드웨어 사전 검사 실패 | 패키지·런타임·APK 설치 시작 안 함 |

정확한 개별 사례는 `test_install_matrix.sh`의 `it` 선언을 확인합니다. 특히
`--no-proot`는 기존 설정이 있어도 저장된 배포판·사용자를 비워 native 전용으로 전환하며,
기존 컨테이너 파일은 유지합니다. `--proot-only`는 native 디스플레이 설정을 유지합니다.

`modern_install`은 공통 입력기 선택·제거·마이그레이션, Wayland 입력 모듈 해제,
GPU 설정 정리와 컨테이너 Turnip 검사, 생성된 GUI 런처의 인자 전달, 스크린샷 분기,
native 전용 Conky 동작 등을 임시 환경에서 검사합니다.
`display_wayland`는 APK 선택, 하드웨어 사전 검사, 해시·설치 실패 처리와 mock 자식
프로세스를 이용한 세션 시작·종료를 다룹니다. 렌더링·키보드 입력 성공 여부는 별도입니다.

## 2026-10-01 리뷰 회귀 검증

24개 후보를 현재 코드와 대조했습니다. #14의 native 전용 전환은 의도된 동작으로,
설정 보존이라는 오래된 설명과 설치 시 안내를 수정했습니다. #3의 롤백 스왑은 검증
시점에 이미 수정되어 있어 열린 파일이 유지되는 회귀 테스트로 확인했습니다.
나머지는 수정 후 임시 HOME/PREFIX와 패키지·다운로드 mock으로 검사합니다.

| 후보 | 검증 스위트 | 확인 내용 |
|------|-------------|-----------|
| #1, #2, #23 | `desktop_review`, `review_regressions` | rootfs symlink, 실패 시 기존 런처 보존, 중복 래핑 방지, GUI 오류 표시 |
| #3, #4 | App Installer `test_review_claude_code.sh`, 부모 `review_regressions` | 롤백 inode 보존, preload 해제, glibc 세션 환경 정리 |
| #5, #6 | `review_regressions`, `domain_locale_ko`, `domain_xfce`, App Installer `test_cli.sh` | 소스 변경 시 훅 재빌드, ZIP 없이 한글 훅 업그레이드, 실제 폰트 파일명으로 재다운로드 방지 |
| #7, #8, #9, #12 | App Installer `test_review_input_gpu.sh` | alarm 탐지 제외, 없는 IME 오선택 방지, Hidden 보존, 레거시 GPU 설치 오탐 제거 |
| #10, #11, #13, #15, #20, #21, #24 | App Installer `test_review_removal_wine.sh` | 멱등 제거와 오류 전파, Python 빌드 의존, 컨테이너 Wine 경로, conffile 보존, login 훅 차단과 DISPLAY 보존, Sway 게이트, 소스 box64 제거 |
| #14 | `install_matrix` | native 전용 전환 시 선택 해제와 컨테이너 파일 유지 |
| #16, #17, #18, #19 | `review_regressions` | 서브모듈 조기 확인, 옛 종료 명령 전달, Conky 인자 유지, 옛 RC 뒤 사용자 설정 보존 |
| #22 | App Installer `test_cli.sh`, `test_review_removal_wine.sh` | GUI/CLI의 은퇴 앱 표시·설치 정책 일치, 기존 설치 제거 가능 |

App Installer에는 전체 러너가 없으므로 위 `test_review_*.sh` 파일은 `bash`로 각각 실행합니다.

## 실기기 설치 스크립트

아래 스크립트는 호스트 스위트에 포함되지 않으며 실제 Termux 환경을 변경합니다.

| 스크립트 | 동작과 범위 |
|----------|-------------|
| [batch_test_appinstaller.sh](batch_test_appinstaller.sh) | 지정 배포판·사용자에 앱 설치. 기본 목록과 `INCLUDE_HEAVY` 목록만 검사하며 전체 레지스트리 검증은 아님. `PROOT_FRESH=1`은 공용 proot 런처를 정리함 |
| [autopilot.sh](autopilot.sh) | 선택한 배포판을 사전 제거한 뒤 `--proot-only`와 앱 배치를 실행하고 마지막에 다시 제거. `SKIP_APPS=1`은 앱 배치만 생략하며 제거는 생략하지 않음 |
| [test_nimf_ubuntu_real.sh](../app-installer/tests/test_nimf_ubuntu_real.sh), [test_nimf_arch_real.sh](../app-installer/tests/test_nimf_arch_real.sh) | Termux에서 실행해 실제 proot에 접속하고 입력기 패키지 설치·검사 |

`proot-distro remove`는 컨테이너와 그 안의 데이터를 제거합니다. `autopilot.sh`의
현재 사전 존재 검사는 구형 `installed-rootfs` 경로를 사용하므로 새 `containers` 구조의
초기화까지 확인하는 도구로 간주하지 마세요. 배치의 heavy 목록에는 신규 설치가 중단된
`tor_browser`도 포함되어 있어 현재 지원 앱 목록과 동일하지 않습니다. 배치의 GPU 진단도
호스트 ICD 경로를 지정하는 구형 방식이므로 `gpu_proot`의 컨테이너 드라이버 검사를
대신하지 않습니다.

`batch_test_appinstaller.sh`는 실패 건수가 있어도 0으로 종료하므로 로그의
`PASS`/`FAIL`/`SKIP`을 확인해야 합니다. `autopilot.sh`도 앱 배치·teardown 실패를
최종 종료 코드에 반영하지 않으므로 종료 코드만으로 전체 성공을 판정하지 않습니다.

실기기에서는 입력기 전환, X11·Wayland 스크린샷, 컨테이너 Turnip 지원, Wine GUI,
APK 연동을 별도로 확인합니다. [App Installer 체크리스트](../app-installer/TEST_LOG.md)와
[Anland의 알려진 제약](../docs/wayland-anland.md#known-blockers)을 함께 참고하세요.
테스트 스크립트는 코드 수정·커밋·push를 자동으로 수행하지 않습니다.

## 테스트 유지

설치 분기가 바뀌면 해당 입력의 호출 여부와 실패 코드를 검사하고, 런처 내용이 바뀌면
생성된 스크립트를 실행하는 회귀 검사로 확인합니다. 실패가 예상되는 명령은
`cmd … || rc=$?`처럼 종료 코드를 받아 `set -e` 때문에 검증 전에 끝나지 않게 합니다.
호스트 검사와 실기기 확인 결과는 사용한 코드·환경 및 검증 범위와 함께 구분해서 보고합니다.
