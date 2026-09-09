# Anland Wayland

`--display wayland` connects **Anland: Termux APK → anland daemon → startplasma-wayland
(patched KWin) → KDE Plasma**. The launcher no longer starts Termux:X11 or nested-X11
labwc.

The Wayland session runs Plasma, not XFCE. On this device XFCE 4.20 did not produce a
usable desktop on KWin. What was actually observed:

* `xfce4-panel`, `xfsettingsd` and `xfdesktop` reported the compositor missing
  `wlr_foreign_toplevel_manager_v1`, `ext_workspace_manager_v1` and
  `wlr-output-management`, which disables the tasklist, show-desktop, intellihide and
  the display-settings dialog.
* `xfdesktop` ran but drew no desktop, so there was no wallpaper. The cause was not
  established — note that KWin does implement `zwlr_layer_shell_v1`, so a missing
  layer-shell is not the explanation.
* XFCE applies scaling through the X11 XSETTINGS selection, which a Wayland-mode
  `xfsettingsd` does not own, so `/Gdk/WindowScalingFactor` had no effect.
* Running the whole session on Xwayland instead crashed Xwayland in Mesa's freedreno
  a6xx texture path (`fd6_texture.cc` assertion, signal 6).

Plasma uses KWin's own protocols, so wallpaper, per-output scaling, tasklist and
display settings all work. XFCE stays installed and is still what `--display x11` runs.

`plasma-workspace` depends on `kwin-x11`; the pinned `kwin-anland` declares
`Provides: kwin-x11`, so Plasma resolves against the Anland compositor and Termux's
X11-only KWin is never pulled in.

`startplasma-wayland` starts KWin itself and chooses the Wayland socket name, so the
session publishes the name it actually got in `$SESSION_STATE_DIR/anland-ready` and the
launcher waits on that rather than assuming a socket.

## Install and start

The pinned native packages target **ARM64 Snapdragon/Adreno with `/dev/kgsl-3d0`**.
Other devices are rejected before installer changes; use `--display x11` on those
devices. Running Anland inside proot is outside this implementation. Existing proot
GUI apps use the Xwayland display inherited from the Plasma session.

```sh
# Keep the same proot options as the existing installation.
bash install.sh --display wayland --no-proot
# Or: bash install.sh --display wayland --distro ubuntu --user <existing-user>
```

Complete the downloaded APK's Android installation dialog, then run `startXFCE`.
For a restart, run `kill_display_session` followed by `startXFCE`.

`$TMPDIR/.X11-unix` must be mode 1777: KWin's Xwayland refuses a socket directory
without the sticky bit, leaves `DISPLAY` unset and the session then exits. The launcher
enforces the mode after creating the directory, because a restrictive umask otherwise
creates it 0700.

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

The Plasma shell packages (`plasma-workspace`, `plasma-desktop`, `kscreen`,
`systemsettings`, `plasma-integration`, `plasma-pa`, `milou`) come from Termux's
x11-repo at its current version and are not pinned; only the patched graphics and
compositor packages below are.

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
  propagates failures and cleans them up on exit. Startup waits for a running
  `plasmashell` whose Wayland socket exists. This does not prove that a frame was
  rendered.
* Logs: `~/.xfce-wayland.log`. Anland handles the clipboard; the outer-X11 xclip
  polling daemon is not started. Existing PulseAudio TCP audio remains available;
  microphone/camera streams use a separate PipeWire runtime.
* Host tests cover APK selection, hardware preflight, corrupt downloads, install
  failures, launcher generation, and actual shell supervision with mock processes.
  The mock compositor supplies `DISPLAY=:91` to catch hardcoded `:0` regressions.
* Verified on a device (SM-F956N, Adreno 750): Plasma shell renders, KWin composites
  through OpenGL 4.6 on `freedreno`/FD750, Xwayland runs glamor on the KGSL surfaceless
  EGL backend (`zink`/Turnip, direct rendering), `kscreen-doctor` reports the output at
  scale 2, `plasma-apply-wallpaperimage` sets the wallpaper, and Korean input arrives
  from the Android keyboard over Wayland `text-input` with no Linux IME running —
  `nimf`/`fcitx5` are not started in this session.
* **Device checks still required:** rotation/app switching, clipboard, proot GUI apps,
  sound, and X11 with the shared patched Mesa packages. Existing X11 screenshot tools
  do not guarantee capture of the whole Wayland desktop. XFCE's autostart entries are
  XDG-standard and are also read by Plasma; `conky` fails there because it is launched
  through `prun` against the XFCE session's display.

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
