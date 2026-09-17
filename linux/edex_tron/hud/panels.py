"""The system panels: clock, system, CPU, memory, processes, network, ports, disks."""
import collections
import os
import platform
import socket
import subprocess
import threading
import time

import psutil
from gi.repository import GLib, Gtk

from .widgets import Bar, DotMap, Graph, KeyValue, Panel, label

HISTORY = 90


def human_bytes(n, per_second=False):
    units = ['B', 'K', 'M', 'G', 'T']
    i = 0
    n = float(n)
    while n >= 1024 and i < len(units) - 1:
        n /= 1024
        i += 1
    s = f'{n:.0f}{units[i]}' if n >= 100 or i == 0 else f'{n:.1f}{units[i]}'
    return s + ('/s' if per_second else '')


def human_duration(seconds):
    d, rem = divmod(int(seconds), 86400)
    h, rem = divmod(rem, 3600)
    m, _ = divmod(rem, 60)
    return f'{d}d {h:02d}:{m:02d}' if d else f'{h:02d}:{m:02d}'


def run_async(fn, done):
    """Run fn() on a worker thread, deliver the result on the GTK thread."""
    def worker():
        try:
            result = fn()
        except Exception as e:  # noqa: BLE001 - shown in the panel, not fatal
            result = e
        GLib.idle_add(lambda: done(result) and False)
    threading.Thread(target=worker, daemon=True).start()


class Clock(Panel):
    def __init__(self):
        super().__init__('Clock', time.strftime('%Z'))
        self.time = self.add(label('', 'clock', xalign=0.5, ellipsize=False))
        self.kv = self.add(KeyValue(['Date', 'Uptime', 'Power']))
        self.body.set_vexpand(False)

    def tick(self):
        now = time.localtime()
        self.time.set_label(time.strftime('%H:%M:%S', now))
        self.kv.set('Date', time.strftime('%a %d %b', now).upper())
        self.kv.set('Uptime', human_duration(time.time() - psutil.boot_time()))
        bat = psutil.sensors_battery() if hasattr(psutil, 'sensors_battery') else None
        if bat is None:
            self.kv.set('Power', 'ON AC')
        else:
            state = 'CHG' if bat.power_plugged else 'BAT'
            self.kv.set('Power', f'{bat.percent:.0f}% {state}')


class System(Panel):
    def __init__(self):
        super().__init__('System', socket.gethostname())
        self.kv = self.add(KeyValue(['Type', 'Kernel', 'User']))
        self.body.set_vexpand(False)
        distro = 'linux'
        try:
            with open('/etc/os-release') as f:
                info = dict(line.rstrip().split('=', 1) for line in f if '=' in line)
            distro = info.get('NAME', 'linux').strip('"').lower() + ' ' + info.get('VERSION_ID', '').strip('"')
        except OSError:
            pass
        self.kv.set('Type', distro)
        self.kv.set('Kernel', platform.release().split('-')[0])
        self.kv.set('User', os.environ.get('USER', '?'))

    def tick(self):
        pass


class Cpu(Panel):
    def __init__(self):
        n = psutil.cpu_count() or 1
        model = _cpu_model()
        super().__init__('CPU usage', model)
        self.n = n
        self.hist = [collections.deque(maxlen=HISTORY) for _ in range(n)]
        # eDEX splits the cores into two stacked graphs
        half = (n + 1) // 2
        self.groups = [list(range(0, half)), list(range(half, n))] if n > 1 else [[0]]
        self.graphs, self.avgs = [], []
        for gi_, cores in enumerate(self.groups):
            row = Gtk.Box(spacing=6)
            info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            info.set_size_request(64, -1)
            info.append(label(f'#{cores[0] + 1}-{cores[-1] + 1}', 'kv-key'))
            avg = label('0%', 'big')
            info.append(avg)
            row.append(info)
            g = Graph(HISTORY, 44)
            row.append(g)
            self.add(row)
            self.graphs.append(g)
            self.avgs.append(avg)
        self.kv = self.add(KeyValue(['Temp', 'Freq', 'Tasks', 'Load']))
        psutil.cpu_percent(percpu=True)

    def tick(self):
        per = psutil.cpu_percent(percpu=True)
        for i, v in enumerate(per[:self.n]):
            self.hist[i].append(v)
        for g, avg, cores in zip(self.graphs, self.avgs, self.groups):
            g.set_series([(self.hist[c], 0.85) for c in cores])
            vals = [per[c] for c in cores if c < len(per)]
            avg.set_label(f'{sum(vals) / max(1, len(vals)):.0f}%')
        self.kv.set('Temp', _cpu_temp())
        f = psutil.cpu_freq()
        self.kv.set('Freq', f'{f.current / 1000:.1f}GHz' if f else '--')
        self.kv.set('Tasks', len(psutil.pids()))
        self.kv.set('Load', f'{os.getloadavg()[0]:.2f}')


def _cpu_model():
    try:
        with open('/proc/cpuinfo') as f:
            for line in f:
                if line.startswith('model name'):
                    name = line.split(':', 1)[1].strip()
                    for junk in ('(R)', '(TM)', 'CPU', 'Processor', '  '):
                        name = name.replace(junk, ' ')
                    return ' '.join(name.split()[:4])
    except OSError:
        pass
    return platform.machine()


def _cpu_temp():
    try:
        temps = psutil.sensors_temperatures()
    except (AttributeError, OSError):
        return '--'
    for key in ('coretemp', 'k10temp', 'zenpower', 'cpu_thermal', 'acpitz'):
        for t in temps.get(key, []):
            if t.current:
                return f'{t.current:.0f}°C'
    return '--'


class Memory(Panel):
    def __init__(self):
        super().__init__('Memory', '')
        self.map = self.add(DotMap(rows=5))
        row = Gtk.Box(spacing=8)
        row.append(label('SWAP', 'kv-key', ellipsize=False))
        self.swap = Bar()
        self.swap.set_valign(Gtk.Align.CENTER)
        row.append(self.swap)
        self.swap_text = label('', 'kv-key', xalign=1.0, ellipsize=False)
        row.append(self.swap_text)
        self.add(row)
        self.body.set_vexpand(False)

    def tick(self):
        vm = psutil.virtual_memory()
        used = (vm.total - vm.available) / vm.total
        cached = max(0.0, (vm.available - vm.free) / vm.total)
        self.map.set_parts(used, cached)
        self.set_right(f'USING {human_bytes(vm.total - vm.available)} OUT OF {human_bytes(vm.total)}')
        sw = psutil.swap_memory()
        self.swap.set_value(sw.percent / 100 if sw.total else 0)
        self.swap_text.set_label(f'{human_bytes(sw.used)}' if sw.total else 'NONE')


class Processes(Panel):
    ROWS = 7

    def __init__(self):
        super().__init__('Top processes', 'PID | NAME | CPU | MEM')
        self.grid = Gtk.Grid(column_spacing=10)
        self.grid.add_css_class('mono')
        self.cells = []
        for r in range(self.ROWS):
            row = [label('', xalign=1.0), label(''), label('', xalign=1.0), label('', xalign=1.0)]
            row[1].set_hexpand(True)
            for c, w in enumerate(row):
                self.grid.attach(w, c, r, 1, 1)
            self.cells.append(row)
        self.add(self.grid)
        self.procs = {}
        self.n = 0

    def tick(self):
        self.n += 1
        if self.n % 2:
            return
        seen, rows = set(), []
        for p in psutil.process_iter(['pid', 'name']):
            seen.add(p.pid)
            proc = self.procs.setdefault(p.pid, p)
            try:
                cpu = proc.cpu_percent(None)
                mem = proc.memory_percent()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
            rows.append((cpu, mem, p.pid, p.info['name'] or '?'))
        for pid in list(self.procs):
            if pid not in seen:
                del self.procs[pid]
        rows.sort(reverse=True)
        cores = psutil.cpu_count() or 1
        for cells, row in zip(self.cells, rows[:self.ROWS]):
            cpu, mem, pid, name = row
            cells[0].set_label(str(pid))
            cells[1].set_label(name)
            cells[2].set_label(f'{cpu / cores:.0f}%')
            cells[3].set_label(f'{mem:.1f}%')


def default_interface():
    try:
        with open('/proc/net/route') as f:
            for line in f.readlines()[1:]:
                parts = line.split()
                if parts[1] == '00000000' and int(parts[3], 16) & 2:
                    gw = socket.inet_ntoa(bytes.fromhex(parts[2])[::-1])
                    return parts[0], gw
    except (OSError, IndexError, ValueError):
        pass
    return None, None


class NetworkStatus(Panel):
    """Interface, addresses, connectivity. Connectivity comes from
    NetworkManager's own check, so the HUD sends no traffic of its own
    apart from one ping to your router when you press refresh."""

    def __init__(self):
        super().__init__('Network status', '[ REFRESH ]', right_action=self.refresh)
        self.kv = self.add(KeyValue(['State', 'Interface', 'Gateway ping']))
        self.kv2 = self.add(KeyValue(['IPv4', 'IPv6']))
        self.body.set_vexpand(False)
        self.n = 0
        self.refresh()

    def tick(self):
        self.n += 1
        if self.n % 15 == 0:
            self.refresh(ping=False)

    def refresh(self, ping=True):
        iface, gw = default_interface()
        self.kv.set('Interface', iface or 'none')
        v4 = v6 = '--'
        for a in psutil.net_if_addrs().get(iface or '', []):
            if a.family == socket.AF_INET:
                v4 = a.address
            elif a.family == socket.AF_INET6 and not a.address.startswith('fe80'):
                v6 = a.address.split('%')[0]
        self.kv2.set('IPv4', v4)
        self.kv2.set('IPv6', v6)
        run_async(_connectivity, lambda s: self.kv.set('State', s if isinstance(s, str) else 'UNKNOWN'))
        if ping and gw:
            self.kv.set('Gateway ping', '...')
            run_async(lambda: _ping(gw), lambda s: self.kv.set('Gateway ping', s if isinstance(s, str) else '--'))
        elif not gw:
            self.kv.set('Gateway ping', '--')


def _connectivity():
    try:
        r = subprocess.run(['nmcli', 'networking', 'connectivity'],
                           capture_output=True, text=True, timeout=4)
        state = r.stdout.strip().upper()
        return {'FULL': 'ONLINE', 'NONE': 'OFFLINE'}.get(state, state or 'UNKNOWN')
    except (OSError, subprocess.TimeoutExpired):
        return 'ONLINE' if default_interface()[0] else 'OFFLINE'


def _ping(host):
    r = subprocess.run(['ping', '-c', '1', '-W', '1', '-n', host],
                       capture_output=True, text=True, timeout=4)
    for part in r.stdout.split():
        if part.startswith('time='):
            return part[5:] + 'ms'
    return 'NO REPLY'


class NetworkGraph(Panel):
    def __init__(self):
        super().__init__('Network usage', '')
        self.graph = self.add(Graph(HISTORY, 90, autoscale=True))
        self.kv = self.add(KeyValue(['Down', 'Up', 'Total down', 'Total up']))
        self.down = collections.deque(maxlen=HISTORY)
        self.up = collections.deque(maxlen=HISTORY)
        self.last = None

    def tick(self):
        iface, _ = default_interface()
        counters = psutil.net_io_counters(pernic=True)
        c = counters.get(iface) if iface else psutil.net_io_counters()
        if c is None:
            return
        now = time.monotonic()
        if self.last and self.last[0] == iface:
            dt = max(1e-3, now - self.last[1])
            rx = max(0, c.bytes_recv - self.last[2]) / dt
            tx = max(0, c.bytes_sent - self.last[3]) / dt
            self.down.append(rx)
            self.up.append(tx)
            self.kv.set('Down', human_bytes(rx, True))
            self.kv.set('Up', human_bytes(tx, True))
        self.last = (iface, now, c.bytes_recv, c.bytes_sent)
        self.kv.set('Total down', human_bytes(c.bytes_recv))
        self.kv.set('Total up', human_bytes(c.bytes_sent))
        self.set_right((iface or '').upper())
        self.graph.set_series([(self.down, 0.95), (self.up, 0.45)])


class Ports(Panel):
    ROWS = 8

    def __init__(self):
        super().__init__('Open ports', 'LISTENING')
        self.grid = Gtk.Grid(column_spacing=10)
        self.grid.add_css_class('mono')
        self.cells = []
        for r in range(self.ROWS):
            row = [label(''), label('', xalign=1.0), label('')]
            row[2].set_hexpand(True)
            for c, w in enumerate(row):
                self.grid.attach(w, c, r, 1, 1)
            self.cells.append(row)
        self.add(self.grid)
        self.n = -1

    def tick(self):
        self.n += 1
        if self.n % 5:
            return
        run_async(_listening, self._show)

    def _show(self, rows):
        if isinstance(rows, Exception):
            rows = []
        self.set_right(f'{len(rows)} LISTENING' if rows else 'NONE LISTENING')
        for i, cells in enumerate(self.cells):
            if i < len(rows):
                proto, port, name = rows[i]
                texts = (proto, str(port), name)
            else:
                texts = ('', '', '')
            for w, t in zip(cells, texts):
                w.set_label(t)


def _listening():
    seen = {}
    for c in psutil.net_connections(kind='inet'):
        if c.type == socket.SOCK_STREAM and c.status != psutil.CONN_LISTEN:
            continue
        if c.type == socket.SOCK_DGRAM and c.raddr:
            continue
        if not c.laddr:
            continue
        proto = 'TCP' if c.type == socket.SOCK_STREAM else 'UDP'
        key = (proto, c.laddr.port)
        if key in seen:
            continue
        name = '?'
        if c.pid:
            try:
                name = psutil.Process(c.pid).name()
            except psutil.Error:
                pass
        local = c.laddr.ip in ('127.0.0.1', '::1') or c.laddr.ip.startswith('127.')
        seen[key] = name + (' (local)' if local else '')
    return sorted(((p, port, n) for (p, port), n in seen.items()), key=lambda r: (r[1], r[0]))


class Disks(Panel):
    SKIP_FS = {'squashfs', 'tmpfs', 'devtmpfs', 'overlay', 'fuse.snapfuse', 'efivarfs', '9p', 'drvfs'}

    def __init__(self):
        super().__init__('Disk usage', '')
        self.box = self.add(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3))
        self.rows = {}
        self.n = -1

    def tick(self):
        self.n += 1
        if self.n % 10:
            return
        parts = [p for p in psutil.disk_partitions(all=False)
                 if p.fstype not in self.SKIP_FS and not p.mountpoint.startswith(('/snap', '/boot/efi', '/mnt/wsl', '/usr/lib/wsl'))]
        if not any(p.mountpoint == '/' for p in parts):
            parts.insert(0, _root_part())
        seen = set()
        for p in parts[:6]:
            try:
                u = psutil.disk_usage(p.mountpoint)
            except OSError:
                continue
            seen.add(p.mountpoint)
            if p.mountpoint not in self.rows:
                row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                top = Gtk.Box()
                name = label(p.mountpoint, hexpand=True)
                size = label('', 'kv-key', xalign=1.0, ellipsize=False)
                top.append(name)
                top.append(size)
                bar = Bar()
                row.append(top)
                row.append(bar)
                self.box.append(row)
                self.rows[p.mountpoint] = (row, size, bar)
            _, size, bar = self.rows[p.mountpoint]
            size.set_label(f'{human_bytes(u.used)} / {human_bytes(u.total)}  {p.fstype}')
            bar.set_value(u.percent / 100)
        for mp in list(self.rows):
            if mp not in seen:
                self.box.remove(self.rows.pop(mp)[0])
        self.set_right(f'{len(seen)} VOLUMES')


def _root_part():
    class Root:
        device, mountpoint, fstype = 'rootfs', '/', 'root'
    return Root()


class JournalTail(Panel):
    """Live system log for secondary monitors."""

    def __init__(self):
        super().__init__('System log', 'JOURNAL')
        self.view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True)
        self.view.add_css_class('mono')
        self.view.add_css_class('journal')
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_child(self.view)
        self.add(sw)
        buf = self.view.get_buffer()
        self.end = buf.create_mark('end', buf.get_end_iter(), False)
        self.proc = None
        try:
            self.proc = subprocess.Popen(
                ['journalctl', '-f', '-n', '40', '-o', 'short', '--no-hostname'],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        except OSError:
            self.view.get_buffer().set_text('journalctl is not available')
            return
        GLib.io_add_watch(self.proc.stdout, GLib.PRIORITY_LOW, GLib.IO_IN | GLib.IO_HUP, self._read)
        self.connect('destroy', lambda *_: self.proc and self.proc.terminate())

    def _read(self, stream, cond):
        if cond & GLib.IO_HUP:
            return False
        line = stream.readline()
        buf = self.view.get_buffer()
        buf.insert(buf.get_end_iter(), line)
        if buf.get_line_count() > 400:
            buf.delete(buf.get_start_iter(), buf.get_iter_at_line(100)[1])
        self.view.scroll_to_mark(self.end, 0, False, 0, 1)
        return True

    def tick(self):
        pass
