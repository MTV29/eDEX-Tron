// Screen effects: CRT scanlines, focused-window glow, TV switch-on/off.
import Cairo from 'cairo';
import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const TV_OPEN_MS = 320;
const TV_CLOSE_MS = 150;   // matches GNOME's own close animation

// --- scanlines -----------------------------------------------------------------
// A non-reactive overlay above everything, drawn once per size change. (An
// offscreen shader over the whole UI broke some app windows' colours.)

const ScanlineOverlay = GObject.registerClass(
class ScanlineOverlay extends St.DrawingArea {
    _init(monitor) {
        super._init({reactive: false, x: monitor.x, y: monitor.y,
            width: monitor.width, height: monitor.height});
        this._strength = 0.18;
    }

    setStrength(v) {
        this._strength = v;
        this.queue_repaint();
    }

    vfunc_repaint() {
        const cr = this.get_context();
        const [w, h] = this.get_surface_size();
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const step = 3 * scale;
        cr.setSourceRGBA(0, 0, 0, this._strength);
        for (let y = 0; y < h; y += step)
            cr.rectangle(0, y, w, scale);
        cr.fill();
        // soft vignette
        const cx = w / 2, cy = h / 2;
        const g = new Cairo.RadialGradient(cx, cy, Math.min(w, h) * 0.35, cx, cy, Math.hypot(cx, cy));
        g.addColorStopRGBA(0, 0, 0, 0, 0);
        g.addColorStopRGBA(1, 0, 0, 0, this._strength * 1.4);
        cr.setSource(g);
        cr.paint();
        cr.$dispose();
    }
});

// --- TV switch-on / switch-off -----------------------------------------------------

const TV_DECL = `
uniform float progress;
uniform vec3 glow;
`;
// progress 0 -> 1: a bright line grows across the middle, then opens up.
const TV_CODE = `
vec2 uv = cogl_tex_coord_in[0].st;
float w = smoothstep(0.0, 0.35, progress);
float h = smoothstep(0.30, 1.0, progress);
float half_h = max(h * 0.5, 0.003);
float inside = step(abs(uv.y - 0.5), half_h) * step(abs(uv.x - 0.5), w * 0.5);
float flash = (1.0 - h) * 0.85;
float a = cogl_color_out.a * inside;
cogl_color_out.rgb = min(vec3(a), cogl_color_out.rgb * inside + glow * flash * a);
cogl_color_out.a = a;
`;

const TvEffect = GObject.registerClass(
class TvEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT, TV_DECL, TV_CODE, false);
    }

    setGlow(rgb) {
        this.set_uniform_float(this.get_uniform_location('glow'), 3, rgb);
    }

    setProgress(v) {
        this.set_uniform_float(this.get_uniform_location('progress'), 1, [v]);
        this.queue_repaint();
    }
});

function hexToRgb(hex) {
    const h = hex.replace('#', '');
    return [0, 2, 4].map(i => parseInt(h.substring(i, i + 2), 16) / 255);
}

function isNormal(window) {
    return window && window.get_window_type() === Meta.WindowType.NORMAL &&
        !window.is_skip_taskbar();
}

export class Effects {
    constructor(settings, isHudWindow) {
        this._settings = settings;
        this._isHud = isHudWindow;
        this._scan = null;
        this._glow = null;
        this._glowWindow = null;
        this._running = new Map();   // timeout id -> cleanup
    }

    enable() {
        this._settings.connectObject(
            'changed::scanlines', () => this._syncScanlines(),
            'changed::scanline-strength', () => this._syncScanlines(),
            'changed::glow', () => this._syncGlow(),
            'changed::accent', () => this._syncGlow(),
            this);
        global.display.connectObject(
            'notify::focus-window', () => this._syncGlow(),
            'restacked', () => this._placeGlow(),
            this);
        global.workspace_manager.connectObject(
            'active-workspace-changed', () => this._placeGlow(), this);
        global.window_manager.connectObject(
            'map', (_wm, actor) => this._tvOpen(actor),
            'destroy', (_wm, actor) => this._tvClose(actor),
            this);
        Main.overview.connectObject(
            'showing', () => this._glow?.hide(),
            'hidden', () => this._syncGlow(),
            this);
        Main.layoutManager.connectObject(
            'monitors-changed', () => this._syncScanlines(), this);
        // chrome added later (menus, OSDs) must stay under the lines
        Main.layoutManager.uiGroup.connectObject(
            'child-added', () => this._raiseScanlines(), this);
        this._syncScanlines();
        this._syncGlow();
    }

    disable() {
        this._settings.disconnectObject(this);
        global.display.disconnectObject(this);
        global.workspace_manager.disconnectObject(this);
        global.window_manager.disconnectObject(this);
        Main.overview.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        Main.layoutManager.uiGroup.disconnectObject(this);
        for (const [id, cleanup] of this._running) {
            GLib.source_remove(id);
            cleanup();
        }
        this._running.clear();
        this._removeScanlines();
        this._trackWindow(null);
        this._glow?.destroy();
        this._glow = null;
    }

    // scanlines over everything the shell draws
    _syncScanlines() {
        this._removeScanlines();
        if (!this._settings.get_boolean('scanlines'))
            return;
        const strength = this._settings.get_double('scanline-strength');
        this._scan = Main.layoutManager.monitors.map(m => {
            const overlay = new ScanlineOverlay(m);
            overlay.setStrength(strength);
            Main.layoutManager.uiGroup.add_child(overlay);
            return overlay;
        });
        this._raiseScanlines();
    }

    _raiseScanlines() {
        for (const o of this._scan ?? [])
            Main.layoutManager.uiGroup.set_child_above_sibling(o, null);
    }

    _removeScanlines() {
        for (const o of this._scan ?? [])
            o.destroy();
        this._scan = null;
    }

    // a glowing frame that sits just below the focused window
    _syncGlow() {
        const window = global.display.focus_window;
        const want = this._settings.get_boolean('glow') && isNormal(window) &&
            !this._isHud(window) && !window.is_fullscreen() && !Main.overview.visible;
        if (!want) {
            this._trackWindow(null);
            this._glow?.hide();
            return;
        }
        if (!this._glow) {
            this._glow = new St.Widget({name: 'edexTronGlow', reactive: false});
            global.window_group.add_child(this._glow);
        }
        const [r, g, b] = hexToRgb(this._settings.get_string('accent')).map(v => Math.round(v * 255));
        this._glow.set_style(
            `border: 1px solid rgba(${r},${g},${b},0.85);` +
            `box-shadow: 0 0 16px 2px rgba(${r},${g},${b},0.45);`);
        this._trackWindow(window);
        this._placeGlow();
    }

    _trackWindow(window) {
        if (this._glowWindow === window)
            return;
        this._glowWindow?.disconnectObject(this);
        this._glowWindow = window;
        window?.connectObject(
            'position-changed', () => this._placeGlow(),
            'size-changed', () => this._placeGlow(),
            'notify::minimized', () => this._syncGlow(),
            'notify::fullscreen', () => this._syncGlow(),
            'workspace-changed', () => this._placeGlow(),
            'unmanaged', () => {
                this._trackWindow(null);
                this._glow?.hide();
            },
            this);
    }

    _placeGlow() {
        const window = this._glowWindow;
        const actor = window?.get_compositor_private();
        const workspace = global.workspace_manager.get_active_workspace();
        if (!this._glow || !actor || window.minimized ||
            !window.located_on_workspace(workspace) || Main.overview.visible) {
            this._glow?.hide();
            return;
        }
        const rect = window.get_frame_rect();
        this._glow.set_position(rect.x - 1, rect.y - 1);
        this._glow.set_size(rect.width + 2, rect.height + 2);
        if (actor.get_parent() === global.window_group)
            global.window_group.set_child_below_sibling(this._glow, actor);
        this._glow.show();
    }

    // CRT switch-on when a window appears
    _tvOpen(actor) {
        const window = actor.meta_window;
        if (!this._settings.get_boolean('tv-animation') || !isNormal(window) ||
            this._isHud(window) || Main.overview.visible)
            return;
        this._runTv(actor, TV_OPEN_MS, false);
        // the new window takes focus: keep the glow on it
        this._syncGlow();
    }

    _tvClose(actor) {
        const window = actor.meta_window;
        if (!this._settings.get_boolean('tv-animation') || !isNormal(window) ||
            this._isHud(window) || Main.overview.visible)
            return;
        this._runTv(actor, TV_CLOSE_MS, true);
    }

    _runTv(actor, duration, reverse) {
        const fx = new TvEffect();
        fx.setGlow(hexToRgb(this._settings.get_string('accent')));
        fx.setProgress(reverse ? 1 : 0);
        actor.add_effect_with_name('edex-tron-tv', fx);
        const start = GLib.get_monotonic_time();
        let alive = true;
        const destroyId = actor.connect('destroy', () => {
            alive = false;
        });
        const cleanup = () => {
            if (!alive)
                return;
            actor.disconnect(destroyId);
            actor.remove_effect(fx);
            alive = false;
        };
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, () => {
            const t = Math.min(1, (GLib.get_monotonic_time() - start) / 1000 / duration);
            if (alive) {
                const eased = 1 - Math.pow(1 - t, 3);
                fx.setProgress(reverse ? 1 - eased : eased);
            }
            // a closing window keeps the effect until GNOME destroys it
            if (t < 1 && alive)
                return GLib.SOURCE_CONTINUE;
            if (!reverse)
                cleanup();
            this._running.delete(id);
            return GLib.SOURCE_REMOVE;
        });
        this._running.set(id, cleanup);
    }
}
