// eDEX-Tron: keeps the HUD on the desktop, loads the generated shell theme,
// and provides the hotkeys and screen effects.
//
// eDEX-Tron is based on eDEX-UI by Gabriel "Squared" Saillard (GPL-3.0).
// The desktop-window technique follows Desktop Icons NG by Sergio Costas.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {Effects} from './effects.js';

const TITLE_PREFIX = 'eDEX-Tron HUD @';
const RESTART_LIMIT = 5;          // crashes allowed ...
const RESTART_WINDOW_S = 120;     // ... within this many seconds
const LINGER_MS = 1500;

// GNOME briefly disables and re-enables extensions when others change. The
// HUD (and its shell sessions) survives that: disable() parks it here and a
// following enable() takes it back; otherwise it is stopped.
let lingering = null;
// Only one instance may be live, even if GNOME loses track of one.
let activeInstance = null;

class HudProcess {
    constructor(settings) {
        this.settings = settings;
        this._client = null;
        this._proc = null;
        this._cancellable = null;
        this._crashes = [];
        this._restartId = 0;
        this._windows = new Set();
        this.stopping = false;
    }

    start() {
        this.stopping = false;
        if (this._proc)
            return;
        console.debug('eDEX-Tron: starting the HUD');
        const argv = this.settings.get_strv('hud-command');
        if (!argv.length)
            return;
        const exe = GLib.find_program_in_path(argv[0]);
        if (!exe) {
            console.warn(`eDEX-Tron: ${argv[0]} not found; is eDEX-Tron installed?`);
            return;
        }
        const primary = Main.layoutManager.primaryMonitor;
        const full = [exe, ...argv.slice(1)];
        if (primary)
            full.push(`--primary=${primary.x},${primary.y}`);

        const launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
        });
        launcher.setenv('EDEX_TRON_MANAGED', '1', true);
        try {
            this._client = Meta.WaylandClient.new_subprocess(global.context, launcher, full);
            this._proc = this._client.get_subprocess();
        } catch (e) {
            console.error(`eDEX-Tron: could not start the HUD: ${e.message}`);
            this._client = null;
            this._proc = null;
            return;
        } finally {
            launcher.close?.();
        }
        this._cancellable = new Gio.Cancellable();
        this._pipeLog(this._proc.get_stdout_pipe(), this._cancellable);
        const proc = this._proc;
        proc.wait_async(this._cancellable, () => {
            if (this._proc !== proc)
                return;
            this._proc = null;
            this._client = null;
            this._windows.clear();
            // a clean exit (e.g. quit from the HUD) is not a crash
            const clean = proc.get_if_exited() && proc.get_exit_status() === 0;
            if (!this.stopping && !clean)
                this._scheduleRestart();
        });
    }

    _pipeLog(stream, cancellable) {
        const input = new Gio.DataInputStream({base_stream: stream});
        const next = () => {
            input.read_line_async(GLib.PRIORITY_LOW, cancellable, (s, res) => {
                try {
                    const [line] = s.read_line_finish_utf8(res);
                    if (line === null)
                        return;
                    console.log(`eDEX-Tron HUD: ${line}`);
                    next();
                } catch {
                    // cancelled or closed
                }
            });
        };
        next();
    }

    _scheduleRestart() {
        const now = GLib.get_monotonic_time() / 1e6;
        this._crashes = this._crashes.filter(t => now - t < RESTART_WINDOW_S);
        this._crashes.push(now);
        if (this._crashes.length > RESTART_LIMIT) {
            console.error('eDEX-Tron: the HUD keeps exiting; not restarting it. ' +
                'Run `edex-tron hud --window` in a terminal to see why.');
            Main.notify('eDEX-Tron', 'The HUD keeps closing, so it was not restarted. ' +
                'Run "edex-tron doctor" in a terminal for details.');
            return;
        }
        this._restartId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._restartId = 0;
            this.start();
            return GLib.SOURCE_REMOVE;
        });
    }

    stop() {
        this.stopping = true;
        if (this._restartId) {
            GLib.source_remove(this._restartId);
            this._restartId = 0;
        }
        this._cancellable?.cancel();
        this._cancellable = null;
        const proc = this._proc;
        if (proc) {
            proc.send_signal(15);
            // make sure it is gone before a new one can start
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
                if (proc.get_identifier())
                    proc.force_exit();
                return GLib.SOURCE_REMOVE;
            });
        }
        this._proc = null;
        this._client = null;
        this._windows.clear();
    }

    owns(window) {
        if (!this._client || !window)
            return false;
        if (this._windows.has(window))
            return true;
        try {
            return this._client.owns_window(window);
        } catch {
            return false;   // X11 windows raise here
        }
    }

    remember(window) {
        this._windows.add(window);
        window.connectObject('unmanaged', () => this._windows.delete(window), this);
    }

    get windows() {
        return [...this._windows];
    }
}

// Pins one HUD window to its monitor, below everything, on every workspace.
class DesktopWindow {
    constructor(window) {
        this.window = window;
        this._placeId = 0;
        window.connectObject(
            'raised', () => this._lower(),
            'position-changed', () => this._queuePlace(),
            'size-changed', () => this._queuePlace(),
            'notify::title', () => this._queuePlace(),
            'notify::above', () => window.above && window.unmake_above(),
            'notify::minimized', () => window.minimized && window.unminimize(),
            this);
        try {
            // desktop layer: always below normal windows, never in Alt+Tab
            window.set_type(Meta.WindowType.DESKTOP);
        } catch (e) {
            console.warn(`eDEX-Tron: set_type failed, lowering instead: ${e.message}`);
        }
        window.hide_from_window_list();
        window.stick();
        this.place();
    }

    monitorIndex() {
        const title = this.window.get_title() ?? '';
        const at = title.indexOf(TITLE_PREFIX);
        if (at < 0)
            return Main.layoutManager.primaryIndex;
        const [x, y] = title.slice(at + TITLE_PREFIX.length).split(',').map(Number);
        const idx = Main.layoutManager.monitors.findIndex(m => m.x === x && m.y === y);
        return idx >= 0 ? idx : Main.layoutManager.primaryIndex;
    }

    place() {
        const w = this.window;
        const area = Main.layoutManager.getWorkAreaForMonitor(this.monitorIndex());
        const r = w.get_frame_rect();
        if (r.x !== area.x || r.y !== area.y || r.width !== area.width || r.height !== area.height) {
            if (w.is_maximized?.())
                w.unmaximize?.();
            w.move_resize_frame(false, area.x, area.y, area.width, area.height);
        }
        this._lower();
    }

    _queuePlace() {
        if (this._placeId)
            return;
        this._placeId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
            this._placeId = 0;
            if (this.window)
                this.place();
            return GLib.SOURCE_REMOVE;
        });
    }

    _lower() {
        this.window?.lower();
    }

    destroy() {
        if (this._placeId)
            GLib.source_remove(this._placeId);
        this.window?.disconnectObject(this);
        this.window = null;
    }
}

export default class EdexTronExtension extends Extension {
    enable() {
        // GNOME can call enable() again on an enabled instance when the
        // extension lists change in quick succession; only the first counts.
        if (this._settings)
            return;
        if (activeInstance && activeInstance !== this)
            activeInstance.disable();
        activeInstance = this;
        console.debug('eDEX-Tron: enable');
        this._settings = this.getSettings();
        this._managed = new Map();   // MetaWindow -> DesktopWindow
        if (lingering) {
            GLib.source_remove(lingering.id);
            this._hud = lingering.hud;
            this._hud.settings = this._settings;
            lingering = null;
            for (const window of this._hud.windows)
                this._manage(window);
        } else {
            this._hud = new HudProcess(this._settings);
        }
        this._peeked = null;
        this._stylesheet = null;

        global.window_manager.connectObject('map', (_wm, actor) => this._onMap(actor), this);
        global.display.connectObject('workareas-changed', () => this._placeAll(), this);
        Main.layoutManager.connectObject('monitors-changed', () => this._placeAll(), this);
        this._settings.connectObject(
            'changed::hud-enabled', () => this._syncHud(),
            'changed::shell-stylesheet', () => this._loadStylesheet(),
            this);

        this._effects = new Effects(this._settings, w => this._isHud(w));
        this._effects.enable();
        this._loadStylesheet();
        this._addKeybindings();

        if (Main.layoutManager._startingUp)
            Main.layoutManager.connectObject('startup-complete', () => this._syncHud(), this);
        else
            this._syncHud();
    }

    disable() {
        // Also called when the session ends. On the lock screen we stay
        // enabled (session-modes) so the HUD's shells are not killed.
        if (!this._settings)
            return;
        console.debug('eDEX-Tron: disable');
        if (activeInstance === this)
            activeInstance = null;
        this._removeKeybindings();
        this._restorePeek();
        this._effects?.disable();
        this._effects = null;
        this._unloadStylesheet();
        global.window_manager.disconnectObject(this);
        global.display.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        this._settings.disconnectObject(this);
        for (const [window, dw] of this._managed) {
            window.disconnectObject(this);
            dw.destroy();
        }
        this._managed.clear();
        if (lingering) {
            GLib.source_remove(lingering.id);
            lingering.hud.stop();
        }
        const hud = this._hud;
        lingering = {
            hud,
            id: GLib.timeout_add(GLib.PRIORITY_DEFAULT, LINGER_MS, () => {
                hud.stop();
                lingering = null;
                return GLib.SOURCE_REMOVE;
            }),
        };
        this._hud = null;
        this._settings = null;
    }

    // --- HUD -----------------------------------------------------------------
    _syncHud() {
        if (this._settings.get_boolean('hud-enabled'))
            this._hud.start();
        else
            this._hud.stop();
    }

    _isHud(window) {
        return this._hud?.owns(window) ?? false;
    }

    _onMap(actor) {
        const window = actor.meta_window;
        if (this._hud.owns(window))
            this._manage(window);
    }

    _manage(window) {
        if (this._managed.has(window))
            return;
        this._hud.remember(window);
        this._managed.set(window, new DesktopWindow(window));
        window.connectObject('unmanaged', () => {
            this._managed.get(window)?.destroy();
            this._managed.delete(window);
        }, this);
    }

    _placeAll() {
        for (const dw of this._managed.values())
            dw.place();
    }

    _primaryHud() {
        const primary = Main.layoutManager.primaryIndex;
        for (const dw of this._managed.values()) {
            if (dw.monitorIndex() === primary)
                return dw.window;
        }
        return null;
    }

    // --- theme -------------------------------------------------------------------
    _loadStylesheet() {
        this._unloadStylesheet();
        if (!this._settings)
            return;
        const path = this._settings.get_string('shell-stylesheet');
        if (!path || !GLib.file_test(path, GLib.FileTest.EXISTS))
            return;
        const file = Gio.File.new_for_path(path);
        const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
        try {
            theme.load_stylesheet(file);
            this._stylesheet = file;
        } catch (e) {
            console.error(`eDEX-Tron: bad stylesheet ${path}: ${e.message}`);
        }
        // pick up `edex-tron theme` changes without a restart
        this._styleMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
        this._styleMonitor.connect('changed', (_m, _f, _o, event) => {
            if (event === Gio.FileMonitorEvent.CHANGES_DONE_HINT ||
                event === Gio.FileMonitorEvent.CREATED)
                this._loadStylesheet();
        });
    }

    _unloadStylesheet() {
        this._styleMonitor?.cancel();
        this._styleMonitor = null;
        if (this._stylesheet) {
            const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
            theme.unload_stylesheet(this._stylesheet);
            this._stylesheet = null;
        }
    }

    // --- hotkeys -------------------------------------------------------------
    _addKeybindings() {
        const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        Main.wm.addKeybinding('peek-hud', this._settings, Meta.KeyBindingFlags.NONE,
            modes, () => this._togglePeek());
        Main.wm.addKeybinding('focus-terminal', this._settings, Meta.KeyBindingFlags.NONE,
            modes, () => this._focusTerminal());
        Main.wm.addKeybinding('toggle-scanlines', this._settings, Meta.KeyBindingFlags.NONE,
            modes, () => this._settings.set_boolean('scanlines',
                !this._settings.get_boolean('scanlines')));
    }

    _removeKeybindings() {
        for (const name of ['peek-hud', 'focus-terminal', 'toggle-scanlines'])
            Main.wm.removeKeybinding(name);
    }

    _normalWindowsHere() {
        const ws = global.workspace_manager.get_active_workspace();
        return global.display.get_tab_list(Meta.TabList.NORMAL, ws)
            .filter(w => !w.minimized && !this._isHud(w));
    }

    _togglePeek() {
        if (this._peeked) {
            this._restorePeek();
            return;
        }
        const windows = this._normalWindowsHere();
        if (!windows.length) {
            this._activateHud();
            return;
        }
        this._peeked = windows;
        for (const w of windows)
            w.minimize();
        this._activateHud();
    }

    _restorePeek() {
        if (!this._peeked)
            return;
        // unminimize bottom-up so the original stacking comes back
        for (const w of [...this._peeked].reverse()) {
            try {
                w.unminimize();
            } catch {
                // window closed meanwhile
            }
        }
        const top = this._peeked[0];
        this._peeked = null;
        if (top)
            Main.activateWindow(top);
    }

    _focusTerminal() {
        if (Main.overview.visible)
            Main.overview.hide();
        if (!this._peeked && this._normalWindowsHere().length)
            this._togglePeek();
        else
            this._activateHud();
    }

    _activateHud() {
        const hud = this._primaryHud();
        if (hud)
            Main.activateWindow(hud);
    }
}
