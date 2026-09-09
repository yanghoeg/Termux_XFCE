# Anland Wayland

`--display wayland` connects **Anland: Termux APK → anland daemon → patched KWin → XFCE**.
The launcher no longer starts Termux:X11 or nested-X11 labwc. KWin starts the XFCE
child with `--exit-with-session` and passes its actual Wayland/Xwayland environment.
This is an experimental XFCE integration in this repository; upstream Anland's
supported desktop examples are Plasma/Weston/GNOME, not XFCE.

## Install and start

The pinned native packages target **ARM64 Snapdragon/Adreno with `/dev/kgsl-3d0`**.
Other devices are rejected before installer changes; use `--display x11` on those
devices. Running Anland inside proot is outside this implementation. Existing proot
GUI apps use the Xwayland display inherited from the XFCE session.

```sh
# Keep the same proot options as the existing installation.
bash install.sh --display wayland --no-proot
# Or: bash install.sh --display wayland --distro ubuntu --user <existing-user>
```

Complete the downloaded APK's Android installation dialog, then run `startXFCE`.
For a restart, run `kill_display_session` followed by `startXFCE`.

* `TERMUX_APP__APK_RELEASE=GITHUB` selects the standard APK (shared UID).
* F-Droid and unknown variants select the compatible APK (Binder bridge).
* Override with `ANLAND_APK_VARIANT=standard` or `compatible` on the install command.
* The selection is saved in `~/.config/termux-xfce/anland-variant`; compatible mode
  runs `anland-compatible` alongside the daemon.
* The two APK variants share an application ID. Switching variants may require
  manually uninstalling the previous Anland APK. The installer never uninstalls it.
* Long-press the Anland Android app icon to open settings. Use the soft-keyboard
  binding configured there. Termux:X11's Back-button setting does not apply.

Anland 5.13.3 includes the IME focus/retry fix from PR #30. Automatic keyboard
display on tapping a desktop text field is not claimed by this integration.

## Pinned dependencies

| Package | Version |
| --- | --- |
| anland | 5.13.3 |
| kwin-anland | 6.7.4 |
| xwayland | 24.1.12-2 |
| mesa | 26.2.0-1 |
| mesa-vulkan-icd-freedreno | 26.2.0-1 |

These packages and both APKs have SHA-256 constants in `adapters/output/anland_install.sh`.
All seven release downloads were hashed locally against those constants. Installation
checks the resulting package version and holds each patched package with `apt-mark hold`.
KWin dependency names were checked against the Termux main/x11 indexes.

Mesa and Xwayland are shared with other native apps. Reinstalling with `--display x11`
does not automatically remove those packages or holds. To restore the stock graphics
packages, stop the desktop, inspect package state, then explicitly unhold/reinstall
the desired repository versions. A partial install failure stops installation but
does not roll back already completed package transactions.

## Runtime and validation

* The daemon socket is `$TMPDIR/anland/display_daemon.sock`; another running daemon
  is not replaced. The Wayland socket is `$XDG_RUNTIME_DIR/wayland-termux-xfce`.
* The supervisor tracks its daemon, bridge, compositor and PipeWire children by PID,
  propagates failures and cleans them up on exit. Startup waits for the compositor
  socket and an XFCE process marker. This does not prove that a frame was rendered.
* Logs: `~/.xfce-wayland.log`. Anland handles the clipboard; the outer-X11 xclip
  polling daemon is not started. Existing PulseAudio TCP audio remains available;
  microphone/camera streams use a separate PipeWire runtime.
* Host tests cover APK selection, hardware preflight, corrupt downloads, install
  failures, launcher generation, and actual shell supervision with mock processes.
  The mock compositor supplies `DISPLAY=:91` to catch hardcoded `:0` regressions.
* **Device checks still required:** XFCE rendering/panels, keyboard show/hide and
  English/Korean input, rotation/app switching, clipboard, proot GUI apps, sound,
  restart, and X11 with the shared patched Mesa packages. KWin-specific XFCE
  shortcuts/plugins/screenshots also need checking. Existing X11 screenshot tools
  do not guarantee capture of the whole Wayland desktop.

## Primary sources

* [Release 5.13.3 and APKs](https://github.com/lfdevs/anland-termux/releases/tag/5.13.3)
* [Pinned user guide](https://github.com/lfdevs/anland-termux/blob/5.13.3/docs/user-guide.md)
* [Native KWin environment/audio script](https://github.com/lfdevs/anland-termux/blob/5.13.3/scripts/startplasma-anland.sh)
* [Compatible bridge](https://github.com/lfdevs/anland-termux/blob/5.13.3/termux/anland/anland-compatible)
* [IME fix PR #30](https://github.com/lfdevs/anland-termux/pull/30)
* [KGSL Mesa release](https://github.com/lfdevs/termux-packages/releases/tag/freedreno-26.2.0-devel-20260709)
* [KWin session-launch contract](https://github.com/KDE/kwin/blob/Plasma/6.4/src/main_wayland.cpp)

The `--anland`, `--xwayland`, `--socket`, `--exit-with-session` options were also
checked in the actual pinned `kwin-anland_6.7.4_aarch64.deb` binary.
