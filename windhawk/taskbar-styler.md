# Windhawk — eDEX-Tron taskbar & window styling

Windhawk compiles each mod from source when you enable it, and it injects into
Explorer. There is no supported way to install a mod from a script, so this
step is manual — but it is only a few clicks, and everything here is a value
you paste into a mod's settings page.

TranslucentTB already makes the taskbar transparent, so the wallpaper grid
shows through it. These mods add the eDEX accent lines on top.

---

## 1. Windows 11 Taskbar Styler

Open **Windhawk → Explore**, search for **"Windows 11 Taskbar Styler"**, click
**Install**, then open its **Settings** tab.

### Theme

Leave `Theme` empty — the styles below are applied directly.

### Control styles

Add these one at a time with **Add item**. `Target` goes in the first box and
each line under `Styles` is its own entry.

**A hairline accent rule along the top edge of the taskbar**

```
Target: Rectangle#BackgroundFill
Styles:
  Fill=#05080D
  Opacity=0.55
```

```
Target: Border#BackgroundBorder
Styles:
  BorderBrush=#AACFD1
  BorderThickness=0,1,0,0
  Opacity=0.45
```

**Accent the running/active indicator under each task button**

```
Target: Taskbar.TaskListButton > Border#Fill
Styles:
  Fill=#AACFD1
```

```
Target: Rectangle#IndicatorFill
Styles:
  Fill=#AACFD1
  Height=2
```

**Cyan hover / pressed states instead of grey**

```
Target: Taskbar.TaskListButtonPanel > Border#BackgroundElement
Styles:
  Background=Transparent
  CornerRadius=0
  BorderBrush=#AACFD1
  BorderThickness=0
```

```
Target: Taskbar.TaskListButton@PointerOver > Border#Fill
Styles:
  Fill=#33AACFD1
```

**Square off the corners, which reads closer to eDEX than Win11's rounding**

```
Target: Border#BackgroundBorder
Styles:
  CornerRadius=0
```

Click **Save settings**. The taskbar restyles immediately; if it does not,
toggle the mod off and on.

---

## 2. Windows 11 Start Menu Styler  *(optional)*

Same idea for the Start menu. Search **"Windows 11 Start Menu Styler"**,
install, then under **Control styles**:

```
Target: Border#StartMenuBorder
Styles:
  Background=#05080D
  BorderBrush=#AACFD1
  BorderThickness=1
  CornerRadius=0
```

---

## 3. Window borders

Windows 11 already draws window borders in the accent colour, and the theme
sets that to `#AACFD1` — so active windows get a cyan outline with no mod
needed.

If you would rather have the whole title bar tinted cyan instead of just the
border, re-run the installer with the switch:

```bash
powershell -ExecutionPolicy Bypass -File src\install.ps1 -AccentTitleBars
```

It is off by default: `#AACFD1` is a light colour, so tinted title bars come
out as pale cyan chrome rather than eDEX's dark-surface-with-cyan-lines look.

---

## Undoing this

Windhawk mods are independent of the rest of the theme. Disable or uninstall
them from the Windhawk UI; `src\uninstall.ps1` does not touch them.
