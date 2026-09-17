import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class EdexTronPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage({title: 'eDEX-Tron', icon_name: 'preferences-desktop-appearance-symbolic'});

        const hud = new Adw.PreferencesGroup({
            title: 'Desktop HUD',
            description: 'Colours, dock and more: run `edex-tron --help` in a terminal.',
        });
        hud.add(this._switch(settings, 'hud-enabled', 'Show the HUD', 'Panels and terminal behind your windows'));
        page.add(hud);

        const fx = new Adw.PreferencesGroup({title: 'Effects'});
        fx.add(this._switch(settings, 'glow', 'Window glow', 'Accent frame around the focused window'));
        fx.add(this._switch(settings, 'tv-animation', 'CRT animation', 'Switch-on/off effect when windows open and close'));
        fx.add(this._switch(settings, 'scanlines', 'Scanlines', 'Fine CRT lines over the whole screen'));
        const strength = new Adw.ActionRow({title: 'Scanline strength'});
        const scale = new Gtk.Scale({
            adjustment: new Gtk.Adjustment({lower: 0, upper: 0.6, step_increment: 0.02}),
            hexpand: true, draw_value: true, digits: 2, valign: Gtk.Align.CENTER,
        });
        settings.bind('scanline-strength', scale.adjustment, 'value', Gio.SettingsBindFlags.DEFAULT);
        settings.bind('scanlines', scale, 'sensitive', Gio.SettingsBindFlags.GET);
        strength.add_suffix(scale);
        fx.add(strength);
        page.add(fx);

        const keys = new Adw.PreferencesGroup({
            title: 'Shortcuts',
            description: 'Change them with: gsettings set org.gnome.shell.extensions.edex-tron <name> "[\'<Super><Alt>x\']"',
        });
        for (const [key, title] of [
            ['peek-hud', 'Show the HUD (again to restore windows)'],
            ['focus-terminal', 'Show the HUD and focus its terminal'],
            ['toggle-scanlines', 'Scanlines on/off'],
        ]) {
            const row = new Adw.ActionRow({title, subtitle: key});
            const label = new Gtk.ShortcutLabel({
                accelerator: settings.get_strv(key)[0] ?? '', valign: Gtk.Align.CENTER,
            });
            settings.connect(`changed::${key}`, () => {
                label.accelerator = settings.get_strv(key)[0] ?? '';
            });
            row.add_suffix(label);
            keys.add(row);
        }
        page.add(keys);

        const about = new Adw.PreferencesGroup({
            title: 'Credits',
            description: 'Based on eDEX-UI by Gabriel "Squared" Saillard (GPL-3.0).',
        });
        page.add(about);
        window.add(page);
    }

    _switch(settings, key, title, subtitle) {
        const row = new Adw.SwitchRow({title, subtitle});
        settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }
}
