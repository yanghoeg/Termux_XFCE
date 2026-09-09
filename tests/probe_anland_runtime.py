"""Exercise actual runtime scripts with mock Android/compositor processes only."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
prefix = Path(os.environ['PREFIX'])
base = prefix.parent
bin_dir = prefix / 'bin'
stub = bin_dir / 'mock-anland-tool'
stub.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, signal, socket, subprocess, sys, time
name = pathlib.Path(sys.argv[0]).name
if name == 'dbus-run-session':
    args = sys.argv[1:]
    if args[0] == '--': args = args[1:]
    os.execvp(args[0], args)
with open(os.environ['ANLAND_TEST_TRACE'], 'a') as f:
    f.write(json.dumps({'name': name, 'pid': os.getpid(), 'argv': sys.argv[1:],
        'DISPLAY': os.getenv('DISPLAY'), 'WAYLAND_DISPLAY': os.getenv('WAYLAND_DISPLAY'),
        'ANLAND_SOCKET': os.getenv('ANLAND_SOCKET'),
        'MESA': os.getenv('MESA_LOADER_DRIVER_OVERRIDE'),
        'GDK': os.getenv('GDK_BACKEND')})+'\n')
if name in ('am', 'termux-wake-unlock', 'dbus-update-activation-environment'):
    sys.exit(0)
if os.getenv('ANLAND_TEST_FAIL') == name:
    sys.exit(7)
sock = None
if name == 'anland':
    path = pathlib.Path(sys.argv[sys.argv.index('--socket')+1])
elif name == 'pipewire':
    path = pathlib.Path(os.environ['PIPEWIRE_RUNTIME_DIR']) / 'pipewire-0'
elif name == 'kwin_wayland':
    path = pathlib.Path(os.environ['XDG_RUNTIME_DIR']) / sys.argv[sys.argv.index('--socket')+1]
else:
    path = None
if path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(path)); sock.listen()
child = None
stopping = False
def stop(*_):
    global stopping
    stopping = True
    if child: child.terminate()
signal.signal(signal.SIGTERM, stop)
if name == 'kwin_wayland':
    env = dict(os.environ, DISPLAY=':91', WAYLAND_DISPLAY=path.name)
    script = sys.argv[sys.argv.index('--exit-with-session')+1]
    child = subprocess.Popen(['bash', script], env=env)
    while child.poll() is None: time.sleep(0.05)
    result = child.returncode
    if sock: sock.close(); path.unlink(missing_ok=True)
    sys.exit(result)
while not stopping: time.sleep(0.05)
if sock: sock.close(); path.unlink(missing_ok=True)
''')
stub.chmod(0o755)
for name in ('dbus-run-session', 'anland', 'anland-compatible', 'am', 'pipewire',
             'wireplumber', 'kwin_wayland', 'termux-wake-unlock',
             'dbus-update-activation-environment', 'xfce4-session'):
    (bin_dir / name).symlink_to(stub)
for src, dest in [('anland-session.sh', 'termux-xfce-anland-session'),
                  ('anland-xfce.sh', 'termux-xfce-anland-xfce')]:
    shutil.copyfile(root / 'runtime' / src, bin_dir / dest)

def alive(pid):
    try: os.kill(pid, 0)
    except ProcessLookupError: return False
    return True

def run_case(failure, variant):
    case = base / f'case-{failure or "success"}-{variant}'
    state = case / 'state'
    runtime = case / 'run'
    temp = case / 'tmp'
    for d in (state, runtime, temp): d.mkdir(parents=True)
    (Path(os.environ['HOME']) / '.config/termux-xfce/anland-variant').write_text(variant+'\n')
    trace = case / 'trace.jsonl'
    env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'],
               SESSION_STATE_DIR=str(state), XDG_RUNTIME_DIR=str(runtime), TMPDIR=str(temp),
               ANLAND_TEST_TRACE=str(trace), ANLAND_TEST_FAIL=failure,
               DISPLAY=':0', WAYLAND_DISPLAY='wrong-parent', WLR_BACKENDS='x11',
               MESA_LOADER_DRIVER_OVERRIDE='zink', GDK_BACKEND='x11')
    with (case / 'log').open('w') as log:
        proc = subprocess.Popen(['bash', str(bin_dir/'termux-xfce-anland-session')], env=env,
                                stdout=log, stderr=log)
        try:
            deadline = time.monotonic()+12
            while time.monotonic() < deadline:
                if proc.poll() is not None or (state/'anland-ready').exists(): break
                time.sleep(.05)
            rows = [json.loads(line) for line in trace.read_text().splitlines()]
            if failure:
                assert proc.wait(timeout=8) != 0, (failure, (case/'log').read_text())
                assert not (state/'anland-ready').exists()
            else:
                assert (state/'anland-ready').exists(), (case/'log').read_text()
                assert (state/'anland-ready').read_text().strip() == ':91', (case/'log').read_text()
                kwin = next(r for r in rows if r['name']=='kwin_wayland')
                assert kwin['DISPLAY'] is None and kwin['WAYLAND_DISPLAY'] is None
                assert kwin['MESA']=='kgsl' and kwin['GDK']=='wayland,x11'
                assert '--anland' in kwin['argv'] and '--xwayland' in kwin['argv']
                xfce = next(r for r in rows if r['name']=='xfce4-session')
                assert xfce['DISPLAY']==':91' and xfce['WAYLAND_DISPLAY']=='wayland-termux-xfce'
                assert any(r['name']=='anland-compatible' for r in rows) == (variant=='compatible')
                assert any(r['name']=='am' and 'com.anland.termux/.MainActivity' in r['argv'] for r in rows)
                os.kill(kwin['pid'], signal.SIGTERM)
                proc.wait(timeout=8)
            deadline = time.monotonic()+3
            while time.monotonic()<deadline and any(alive(r['pid']) for r in rows): time.sleep(.05)
            assert not any(alive(r['pid']) for r in rows), ('child leaked', rows)
            assert not (state/'anland-ready').exists()
            assert not (temp/'anland/display_daemon.sock').exists()
            print(f'PASS runtime: {variant}, {failure or "normal shutdown"}')
        finally:
            if proc.poll() is None: proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            if trace.exists():
                for row in map(json.loads, trace.read_text().splitlines()):
                    try: os.kill(row['pid'], signal.SIGTERM)
                    except ProcessLookupError: pass

run_case('', 'compatible')
run_case('', 'standard')
run_case('anland', 'compatible')
run_case('anland-compatible', 'compatible')
run_case('kwin_wayland', 'compatible')
run_case('xfce4-session', 'compatible')
