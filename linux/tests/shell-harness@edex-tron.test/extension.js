// TEST ONLY: D-Bus hooks used by linux/tests/run_shell_test.sh.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Shell.Screenshot.prototype, 'screenshot');

const IFACE = `<node><interface name="io.github.mtv29.EdexTronTest">
  <method name="Shot"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
  <method name="Windows"><arg type="s" direction="out"/></method>
  <method name="Call"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="Overview"><arg type="b" direction="in"/></method>
</interface></node>`;

const TYPES = Object.fromEntries(Object.entries(Meta.WindowType).map(([k, v]) => [v, k]));

class Service {
    async ShotAsync([path], invocation) {
        try {
            const file = Gio.File.new_for_path(path);
            const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null);
            await new Shell.Screenshot().screenshot(false, stream);
            stream.close(null);
            invocation.return_value(new GLib.Variant('(b)', [true]));
        } catch (e) {
            invocation.return_error_literal(Gio.DBusError, Gio.DBusError.FAILED, e.message);
        }
    }

    Windows() {
        const edex = Extension.lookupByUUID('edex-tron@mtv29.github.io');
        const list = global.get_window_actors().map(a => {
            const w = a.meta_window;
            const r = w.get_frame_rect();
            return {
                title: w.get_title(), type: TYPES[w.get_window_type()],
                rect: [r.x, r.y, r.width, r.height], layer: w.get_layer?.(),
                sticky: w.is_on_all_workspaces(), skipTaskbar: w.is_skip_taskbar(),
                minimized: w.minimized, focus: w === global.display.focus_window,
                hud: edex?._hud?.owns(w) ?? null, effects: a.get_effects().map(e => e.get_name()),
            };
        });
        const stack = global.display.sort_windows_by_stacking(global.display.list_all_windows())
            .map(w => w.get_title());
        return JSON.stringify({
            windows: list, stack,
            monitors: Main.layoutManager.monitors.map(m => [m.x, m.y, m.width, m.height]),
            workarea: (() => {
                const r = Main.layoutManager.getWorkAreaForMonitor(Main.layoutManager.primaryIndex);
                return [r.x, r.y, r.width, r.height];
            })(),
            uiGroupEffects: Main.layoutManager.uiGroup.get_effects().map(e => e.get_name()),
            glow: global.window_group.get_children().filter(c => c.name === 'edexTronGlow')
                .map(c => ({visible: c.visible, box: [c.x, c.y, c.width, c.height]})),
            extensionState: edex ? 'loaded' : 'missing',
        });
    }

    Call(name) {
        const edex = Extension.lookupByUUID('edex-tron@mtv29.github.io');
        const status = Main.panel.statusArea;
        const fns = {
            peek: () => edex._togglePeek(),
            focus: () => edex._focusTerminal(),
            quick: () => status.quickSettings.menu.open(),
            calendar: () => status.dateMenu.menu.open(),
            close: () => {
                status.quickSettings.menu.close();
                status.dateMenu.menu.close();
            },
            lock: () => Main.screenShield?.lock(false),
            unlock: () => Main.screenShield?.deactivate(false),
        };
        if (!fns[name] || (!edex && ['peek', 'focus'].includes(name)))
            return 'unknown';
        if (['lock', 'unlock'].includes(name) && !Main.screenShield)
            return 'unavailable';
        fns[name]();
        return 'ok';
    }

    Overview(show) {
        if (show)
            Main.overview.show();
        else
            Main.overview.hide();
    }
}

export default class Harness extends Extension {
    enable() {
        this._impl = Gio.DBusExportedObject.wrapJSObject(IFACE, new Service());
        this._impl.export(Gio.DBus.session, '/io/github/mtv29/EdexTronTest');
        this._own = Gio.bus_own_name(Gio.BusType.SESSION, 'io.github.mtv29.EdexTronTest',
            Gio.BusNameOwnerFlags.NONE, null, null, null);
    }

    disable() {
        this._impl.unexport();
        Gio.bus_unown_name(this._own);
    }
}
