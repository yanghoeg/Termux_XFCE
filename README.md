# Termux XFCE

Android 기기(Termux)에서 XFCE 데스크탑 환경을 자동 설치하는 스크립트입니다.
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

- **Termux native 우선**: XFCE, Firefox, fcitx5-hangul, GPU 가속 모두 Termux 네이티브로 설치
- **proot 선택**: Ubuntu 또는 Arch Linux (또는 없음)
- **헥사고날 아키텍처(Ports & Adapters)** 적용으로 distro 추상화

테스트 기기: Galaxy Fold6 (SD 8 Gen3), Galaxy Tab S9 Ultra (SD 8 Gen2)

---

## 설치

```bash
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

옵션 지정 설치:

```bash
# Ubuntu proot + GPU 가속
bash install.sh --distro ubuntu --user lideok --gpu

# Arch Linux proot
bash install.sh --distro archlinux --user lideok

# Termux native only (proot 없음)
bash install.sh --distro none

# 환경변수로도 지정 가능
DISTRO=ubuntu USERNAME=lideok bash install.sh
```

---

## 사용법

```bash
# XFCE 데스크탑 시작
startXFCE

# proot 진입 (예: ubuntu 또는 archlinux)
ubuntu
archlinux

# proot 앱 실행 (Termux 터미널에서)
prun code
prun libreoffice

# proot .desktop 파일을 XFCE 메뉴에 복사
cp2menu

# 앱 추가 설치/제거 (GUI)
app-installer
```

---

## GPU 가속

Termux native 가속 드라이버: [xMeM/termux-packages](https://github.com/xMeM/termux-packages)
→ Actions → 최신 run → `mesa-vulkan-icd-wrapper` + mesa 드라이버 다운로드 후 설치

zenity가 실행되지 않으면: `pkg install mesa-zink` 후 zenity 실행, 이후 원래 mesa로 재설치

---

## 아키텍처

```
install.sh          → DI(어댑터 선택) → Domain 실행
ports/              → 계약 정의 (pkg_manager, ui)
adapters/input/     → CLI 인자 / 대화형 입력
adapters/output/    → pkg 구현체 (termux/ubuntu/arch), UI 구현체 (terminal/zenity)
domain/             → 비즈니스 로직 (termux_env, xfce_env, proot_env, packages)
app-installer/      → 앱 추가 설치 GUI (Git Submodule)
```

---

## Signal 9 오류 해결

Termux가 강제 종료되는 경우 ADB로 phantom process 제한 해제:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

[LADB](https://github.com/hyperio546/ladb-builds/releases) 또는 Termux에서 직접 ADB 사용 가능.
참고 영상: https://www.youtube.com/watch?v=BHc7uvX34bM
