# Anland Wayland

`--display wayland` connects **Anland: Termux APK → anland daemon → startplasma-wayland
(patched KWin) → KDE Plasma**. The launcher no longer starts Termux:X11 or nested-X11
labwc.

The Wayland session runs Plasma. Existing SM-F956N / Adreno 750 device notes
report that XFCE 4.20 did not produce a usable desktop on the tested KWin stack:

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

Plasma uses KWin's own protocols; earlier device checks confirmed wallpaper,
per-output scaling, tasklist and display settings before the failures below.
XFCE remains installed and is used by `--display x11`.

`plasma-workspace` depends on `kwin-x11`; the pinned `kwin-anland` declares
`Provides: kwin-x11` to satisfy that dependency with the Anland compositor. This
package relationship is not a guarantee of compatibility with every unpinned Plasma
release.

`startplasma-wayland` starts KWin itself and chooses the Wayland socket name, so the
session publishes the name it actually got in `$SESSION_STATE_DIR/anland-ready` and the
launcher waits on that rather than assuming a socket.

## Known blockers

The recorded device failures below have not been cleared by a new validation of
this repository's installed stack. Keep this backend experimental and use X11 for
the default desktop. Upstream fixes and successful mock tests are not device results.

* **Plasma popup failure.** The recorded session lost `plasmashell` after panel
  popups, with:

  ```text
  layershellqt: Cannot attach popup of unknown type
  xdg_wm_base#3: error 3: no xdg_popup parent surface has been specified
  The Wayland connection experienced a fatal error: Protocol error
  ```

  The watchdog can restart the shell, but that does not fix the cause. The
  [Anland 5.13.3 release instructions](https://github.com/lfdevs/anland-termux/releases/tag/5.13.3)
  now require a modified LayerShellQt for native Plasma and link
  [layer-shell-qt 6.7.4-1](https://github.com/lfdevs/termux-packages/releases/tag/layer-shell-qt_6.7.4-1).
  The repository's installer does **not** explicitly fetch, pin or hold that package.
  Its effect on this recorded failure needs device testing; a Plasma/KWin version
  mismatch alone has not been established as the cause.

* **Xwayland/Mesa failure on A7xx.** X11 clients triggered this assertion in the
  pinned Mesa stack:

  ```text
  fd6_texture.cc:854: assertion "state->view_rsc_seqno[i] == seqno" failed  [CHIP = A7XX]
  Fatal server error: (EE) Caught signal 6 (Aborted). Server aborting
  ```

  This affects clients using Xwayland. The current supervisor requests native
  Wayland for Firefox with `MOZ_ENABLE_WAYLAND=1`; that setting does not repair the
  Xwayland path used by other apps.

Revalidate panel menus, app launching and X11 clients when changing LayerShellQt,
Plasma, KWin or Mesa. Record the versions actually installed: Plasma packages come
from the repository, while the graphics components below are pinned. Zink swapchain
fallback was also observed with stock Mesa on this device; do not attribute every
rendering failure to Anland's pinned build.

## Install and start

The pinned native packages target **ARM64 Snapdragon/Adreno with `/dev/kgsl-3d0`**.
The hardware preflight rejects other devices before configuration/package changes
for a native Wayland installation; use `--display x11` on those devices. Running Anland inside proot is outside this implementation. Existing proot
GUI apps use the Xwayland display inherited from the Plasma session.

Run from the usix-termux checkout with its submodule initialized:

```bash
# Configure the native desktop without running proot setup
bash install.sh --display wayland --no-proot

# Or include proot setup; replace desktop with your proot username
bash install.sh --display wayland --distro ubuntu --user desktop
```

`--no-proot` clears the saved proot selection and selects native-only operation;
existing container files remain on disk. `--proot-only` skips native
runtime/APK/launcher setup and cannot be used to switch the desktop backend. See the
[parent installation options](../README.md#installation).

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

Anland 5.13.3 includes the soft-keyboard desktop-resizing change listed in its
[release notes](https://github.com/lfdevs/anland-termux/releases/tag/5.13.3). Automatic
keyboard display on tapping a desktop text field is not claimed by this integration.

## Pinned dependencies

The Plasma shell packages (`plasma-workspace`, `plasma-desktop`, `kscreen`,
`systemsettings`, `plasma-integration`, `plasma-pa`, `milou`) and the screenshot tool
`spectacle` come from Termux's
x11-repo at its current version and are not pinned; only the patched graphics and
compositor packages below are.

| Package | Version |
| --- | --- |
| anland | 5.13.3 |
| kwin-anland | 6.7.4 |
| xwayland | 24.1.12-2 |
| mesa | 26.2.0-1 |
| mesa-vulkan-icd-freedreno | 26.2.0-1 |

These five packages and both APK variants have SHA-256 constants in
[adapters/output/anland_install.sh](../adapters/output/anland_install.sh).
`fetch_verified` verifies downloaded files; the installer checks each installed
package version and applies `apt-mark hold`. Already-installed matching package
versions are reused. LayerShellQt is not part of this pin/hold table; see the
[popup blocker](#known-blockers).

Mesa and Xwayland are shared with other native apps. Reinstalling with `--display x11`
does not automatically remove those packages or holds. To restore the stock graphics
packages, stop the desktop, inspect package state, then explicitly unhold/reinstall
the desired repository versions. The graphics holds are `mesa`,
`mesa-vulkan-icd-freedreno` and `xwayland`; `anland` and `kwin-anland` are also held.
An unhold alone does not replace the installed package. A partial install failure
stops installation but does not roll back completed package transactions.

## Runtime and validation

`wayvnc` requires a wlroots compositor and does not support this Anland/KWin
backend. The app installer and `wayvnc-start` reject known KWin sessions; switching
to `--display wayland` does not enable VNC access. See the
[wayvnc compatibility statement](https://github.com/any1/wayvnc#introduction).

* The daemon socket is `$TMPDIR/anland/display_daemon.sock`; another running daemon
  is not replaced. `startplasma-wayland` picks KWin's Wayland socket name itself (it
  has been `wayland-0` in practice), and the session writes the name it actually got
  into `$SESSION_STATE_DIR/anland-ready` for the launcher to read.
* The [supervisor](../runtime/anland-session.sh) tracks its daemon, bridge, compositor
  and PipeWire/WirePlumber children by PID,
  propagates failures and cleans them up on exit. Startup waits for a running
  `plasmashell` whose Wayland socket exists. This does not prove that a frame was
  rendered. If `plasmashell` disappears, the watchdog attempts at most five restarts
  before failing the session.
* Logs: `~/.xfce-wayland.log`. Anland handles the clipboard; the outer-X11 xclip
  polling daemon is not started. Existing PulseAudio TCP audio remains available;
  microphone/camera streams use a separate PipeWire runtime.
* Host tests cover APK selection, hardware preflight, corrupt downloads, install
  failures, launcher generation, and actual shell supervision with mock processes.
  The mock compositor supplies `DISPLAY=:91` to catch hardcoded `:0` regressions.
* Earlier device observations (SM-F956N, Adreno 750): Plasma shell renders, KWin composites
  through OpenGL 4.6 on `freedreno`/FD750, Xwayland runs glamor on the KGSL surfaceless
  EGL backend (`zink`/Turnip, direct rendering), `kscreen-doctor` reports the output at
  scale 2, `plasma-apply-wallpaperimage` sets the wallpaper, and Korean is typed from
  the Android keyboard over Wayland `text-input` with the IME variables unset —
  leaving `GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS` set to `nimf` broke input
  instead. `NotShowIn=KDE` keeps XFCE's autostart from starting `nimf`, but Plasma's
  `manage-inputmethod` applet may still launch it; it is not needed on this path.
  These checks were made before the blockers above were hit.
* **Device checks still required:** rotation/app switching, clipboard, proot GUI apps,
  sound, Spectacle screenshots (full/region/window), and X11 with the shared patched
  Mesa packages. The `screenshot` wrapper now dispatches Wayland captures to Spectacle;
  mock tests verify dispatch, but actual capture still needs a device check. XFCE's
  XDG autostart entries for Conky and X11 input helpers remain excluded from KDE.

## Primary sources

* [Release 5.13.3 and APKs](https://github.com/lfdevs/anland-termux/releases/tag/5.13.3)
* [Pinned user guide](https://github.com/lfdevs/anland-termux/blob/5.13.3/docs/user-guide.md)
* [Native KWin environment/audio script](https://github.com/lfdevs/anland-termux/blob/5.13.3/scripts/startplasma-anland.sh)
* [Compatible bridge](https://github.com/lfdevs/anland-termux/blob/5.13.3/termux/anland/anland-compatible)
* [Soft-keyboard resizing PR #30](https://github.com/lfdevs/anland-termux/pull/30)
* [Required native Plasma LayerShellQt patch](https://github.com/lfdevs/termux-packages/releases/tag/layer-shell-qt_6.7.4-1)
* [KGSL Mesa release](https://github.com/lfdevs/termux-packages/releases/tag/freedreno-26.2.0-devel-20260709)
* [KWin session-launch contract](https://github.com/KDE/kwin/blob/Plasma/6.4/src/main_wayland.cpp)

The upstream KWin source link is background material, not the exact patched build.
This integration invokes `startplasma-wayland`; the generated launcher and the
repository supervisor define its runtime behavior.
