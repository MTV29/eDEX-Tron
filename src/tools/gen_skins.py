"""Generate the eDEX-Tron Rainmeter suite.

Each skin reproduces one eDEX-UI module using the visual grammar taken from
eDEX's own CSS: a caption with a hairline underline capped by short downward
ticks, dashed rules bounding any graph, and values carried at full opacity
against dimmer labels. Panel contents are parameterised by the host's real
topology (thread count, drives) so the suite fits the machine it is built on.

Typography note: labels sit at ~75% opacity, not the ~50% the CSS uses. eDEX
renders its own UI at a large size on a black page; at Rainmeter's panel sizes
United Sans Light at half opacity is effectively invisible on the desktop.
"""
import argparse, json, os, re, textwrap

W = 250                      # panel width, ~17% of a 1536px desktop (eDEX column)
PAD = 8

# --- typography -------------------------------------------------------------
FS_HEAD  = 9     # panel caption
FS_LABEL = 9     # dim field labels
FS_VAL   = 12    # field values
FS_BIG   = 20    # the large percentages
FS_CLOCK = 30
FS_MONO  = 9

A_HEAD  = 255
A_LABEL = 190    # the legibility fix -- was 120, which read as near-black
A_VAL   = 255
A_DIM   = 170

ROW = 17         # label -> value baseline step
GAP = 22         # value -> next label step
# A String meter with ClipString=1 clips to its H box, so H must clear the
# font's full ascender-to-descender height or glyphs get sliced. 12pt needs ~22.
H_VAL = 22
H_LABEL = 16


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_theme(path):
    with open(path) as f:
        c = json.load(f)['colors']
    return {
        'accent': f"{c['r']},{c['g']},{c['b']}",
        'bg': ','.join(str(v) for v in hex2rgb(c['light_black'])),
        'grey': ','.join(str(v) for v in hex2rgb(c['grey'])),
    }


def skin_header(update=1000, extra=''):
    lines = [f'Update={update}', 'AccurateText=1', 'DynamicWindowSize=1']
    if extra:
        lines.append(extra)
    body = '\n    '.join(lines)
    return textwrap.dedent(f"""
    [Rainmeter]
    {body}

    [Variables]
    @Include=#@#Variables.inc
    """).strip()


def header(title, right='', width=None, right_action=None):
    """eDEX `section > h3.title`: caption, hairline rule, ticks at both ends.

    `right_action` turns the right-hand caption into a button. The panel must
    then be deployed with ClickThrough=0 (see gen_rainmeter_ini.INTERACTIVE).
    """
    w = W if width is None else width
    action = (f"LeftMouseUpAction={right_action}\n    ToolTipText={right}\n    "
              if right_action else '')
    return textwrap.dedent(f"""
    [MeterTitle]
    Meter=String
    X={PAD}
    Y=0
    FontFace=#FontMain#
    FontSize={FS_HEAD}
    FontColor=#Accent#,{A_HEAD}
    StringCase=Upper
    AntiAlias=1
    Text={title}

    [MeterTitleRight]
    Meter=String
    X={w - PAD}
    Y=0r
    FontFace=#FontLight#
    FontSize={FS_HEAD}
    FontColor=#Accent#,{A_DIM}
    StringAlign=Right
    StringCase=Upper
    AntiAlias=1
    {action}Text={right}

    [MeterTitleRule]
    Meter=Shape
    X=0
    Y=15r
    Shape=Line 0,0,{w},0 | StrokeWidth 1 | Stroke Color #Accent#,90
    Shape2=Line 0.5,0,0.5,5 | StrokeWidth 1 | Stroke Color #Accent#,130
    Shape3=Line {w - 0.5},0,{w - 0.5},5 | StrokeWidth 1 | Stroke Color #Accent#,130
    """).strip()


def stat_row(prefix, cells, y_first, width=None):
    """A row of label-over-value cells, as eDEX uses for sysinfo and netstat.

    The first cell sets the baseline; later cells in the same row step back up
    to it, since Rainmeter's relative Y is measured from the previous meter.
    """
    w = W if width is None else width
    n = len(cells)
    colw = (w - PAD * 2) // n
    # Narrow cells cannot carry 12pt without truncating values like an IPv4
    # address, so step the size down as the row gets busier.
    fs = FS_VAL if colw >= 110 else (11 if colw >= 85 else 10)
    out = []
    for i, (label, value, is_measure) in enumerate(cells):
        y = y_first if i == 0 else f'-{ROW}r'
        body = (f'MeasureName={value}' if is_measure else '')
        text = '%1' if is_measure else value
        out.append(textwrap.dedent(f"""
        [Meter{prefix}Label{i}]
        Meter=String
        X={PAD + i * colw}
        Y={y}
        FontFace=#FontLight#
        FontSize={FS_LABEL}
        FontColor=#Accent#,{A_LABEL}
        StringCase=Upper
        AntiAlias=1
        Text={label}

        [Meter{prefix}Value{i}]
        Meter=String
        {body}
        X={PAD + i * colw}
        Y={ROW}r
        W={colw - 4}
        H={H_VAL}
        ClipString=1
        FontFace=#FontMain#
        FontSize={fs}
        FontColor=#Accent#,{A_VAL}
        AntiAlias=1
        Text={text}
        """).strip())
    return '\n\n'.join(out)


# ------------------------------------------------------------------- CLOCK ---
def clock():
    """eDEX's clock module: the time large, then a row of four small stats."""
    return '\n\n'.join([
        skin_header(200),
        header('Panel', 'system'),
        textwrap.dedent(f"""
        [MeasureTime]
        Measure=Time
        Format=%H:%M:%S

        [MeasureDate]
        Measure=Time
        Format=%b %#d

        [MeasureYear]
        Measure=Time
        Format=%Y

        [MeasureUptime]
        Measure=Uptime
        Format=%3!i!d%2!02i!:%1!02i!

        [MeasureHost]
        Measure=Plugin
        Plugin=SysInfo
        SysInfoType=COMPUTER_NAME

        [MeasureOS]
        Measure=Plugin
        Plugin=SysInfo
        SysInfoType=OS_VERSION

        [MeterTime]
        Meter=String
        MeasureName=MeasureTime
        X={PAD}
        Y=10R
        FontFace=#FontLight#
        FontSize={FS_CLOCK}
        FontColor=#Accent#,{A_VAL}
        AntiAlias=1
        Text=%1

        [MeterClockRule]
        Meter=Shape
        X=0
        Y=8R
        Shape=Line {PAD},0,{W - PAD},0 | StrokeWidth 1 | Stroke Color #Accent#,70 | StrokeDashes 3,3
        """).strip(),
        stat_row('Clock', [
            ('Date', 'MeasureDate', True),
            ('Uptime', 'MeasureUptime', True),
            ('Type', 'win', False),
            ('Power', 'ON', False),
        ], '8R'),
        # machine identity, where eDEX puts manufacturer / model / chassis
        stat_row('Machine', [
            ('Host', 'MeasureHost', True),
            ('OS', 'MeasureOS', True),
        ], f'{GAP}R'),
    ])


# ----------------------------------------------------------------- SYSINFO ---
def sysinfo():
    out = [skin_header(5000), header('Machine', 'sysinfo'), textwrap.dedent("""
    [MeasureHost]
    Measure=Plugin
    Plugin=SysInfo
    SysInfoType=COMPUTER_NAME

    [MeasureOS]
    Measure=Plugin
    Plugin=SysInfo
    SysInfoType=OS_VERSION
    """).strip()]
    out.append(stat_row('Sys', [
        ('Host', 'MeasureHost', True),
        ('OS', 'MeasureOS', True),
    ], '10R'))
    return '\n\n'.join(out)


# ----------------------------------------------------------------- CPUINFO ---
def cpuinfo(cores, cpu_name):
    """eDEX groups cores into stacked line graphs of ten, with a stat row under."""
    per_graph = 10
    groups = [list(range(i, min(i + per_graph, cores)))
              for i in range(0, cores, per_graph)]
    gw, gh = W - PAD * 2 - 46, 46

    out = [skin_header(), header('CPU Usage', f'{cores} threads')]
    out.append('[MeasureCPUTotal]\nMeasure=CPU')
    for c in range(cores):
        out.append(f"[MeasureCore{c}]\nMeasure=CPU\nProcessor={c + 1}")
    # per-group average, for the label beside each graph
    for gi, g in enumerate(groups):
        formula = '(' + ' + '.join(f'MeasureCore{c}' for c in g) + f') / {len(g)}'
        out.append(f"[MeasureAvg{gi}]\nMeasure=Calc\nFormula={formula}")

    # Absolute Y from here down. The graphs are positioned relative to their
    # own labels, so a relative chain leaves the following meters anchored
    # inside the graph box and everything after it overlaps.
    top = 34
    for gi, g in enumerate(groups):
        gy = top + gi * (gh + 12)
        # Line meter plots one series per MeasureName slot; LineCount must match
        names = '\n'.join(
            (f'MeasureName={m}' if i == 0 else f'MeasureName{i + 1}={m}')
            for i, m in enumerate(f'MeasureCore{c}' for c in g))
        colors = '\n'.join(
            (f'LineColor={"#Accent#"},{200 - i * 8}' if i == 0
             else f'LineColor{i + 1}={"#Accent#"},{200 - i * 8}')
            for i in range(len(g)))
        out.append(textwrap.dedent(f"""
        [MeterCpuGroup{gi}]
        Meter=String
        X={PAD}
        Y={gy}
        FontFace=#FontMain#
        FontSize={FS_LABEL}
        FontColor=#Accent#,{A_VAL}
        AntiAlias=1
        Text=# {g[0] + 1} - {g[-1] + 1}

        [MeterCpuGroupAvg{gi}]
        Meter=String
        MeasureName=MeasureAvg{gi}
        X={PAD}
        Y={gy + 15}
        FontFace=#FontLight#
        FontSize={FS_LABEL}
        FontColor=#Accent#,{A_LABEL}
        NumOfDecimals=0
        AntiAlias=1
        Text=Avg. %1%

        [MeterCpuGraph{gi}]
        Meter=Line
        {names}
        X={PAD + 46}
        Y={gy}
        W={gw}
        H={gh}
        LineCount={len(g)}
        {colors}
        AntiAlias=1
        GraphStart=Right
        SolidColor=#Accent#,12
        """).strip())

    stat_y = top + len(groups) * (gh + 12) + 6
    out.append(stat_row('Cpu', [
        ('Cores', str(cores), False),
        ('Load', 'MeasureCPUTotal', True),
    ], str(stat_y)))
    out.append(textwrap.dedent(f"""
    [MeterCpuName]
    Meter=String
    X={PAD}
    Y={stat_y + ROW + H_VAL + 2}
    W={W - PAD * 2}
    H={H_LABEL}
    ClipString=1
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringCase=Upper
    AntiAlias=1
    Text={cpu_name}
    """).strip())
    return '\n\n'.join(out)


# -------------------------------------------------------------- RAMWATCHER ---
def ramwatcher(cols=28, rows=7):
    """eDEX's pointmap. Every dot lives in ONE Shape meter and reads its alpha
    straight off a Calc measure as a section variable -- no SetVariable
    round-trip, so this stays cheap despite the dot count."""
    dot, gap = 4, 4
    total = cols * rows
    bar_w = W - PAD * 2 - 46 - 56

    out = [skin_header(), header('Memory', 'ramwatcher'), textwrap.dedent(f"""
    [MeasureRAM]
    Measure=PhysicalMemory

    [MeasureRAMTotal]
    Measure=PhysicalMemory
    Total=1

    [MeasureRAMPct]
    Measure=Calc
    Formula=MeasureRAM / MeasureRAMTotal * 100

    [MeasureRAMGB]
    Measure=Calc
    Formula=MeasureRAM / 1073741824

    [MeasureRAMTotalGB]
    Measure=Calc
    Formula=MeasureRAMTotal / 1073741824

    [MeasureSwap]
    Measure=SwapMemory

    [MeasureSwapTotal]
    Measure=SwapMemory
    Total=1

    [MeterRAMLabel]
    Meter=String
    X={PAD}
    Y=10R
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringCase=Upper
    AntiAlias=1
    DynamicVariables=1
    Text=Using [&MeasureRAMGB:1] of [&MeasureRAMTotalGB:1] GiB

    [MeterRAMPct]
    Meter=String
    MeasureName=MeasureRAMPct
    X={W - PAD}
    Y=-6r
    FontFace=#FontMain#
    FontSize={FS_BIG}
    FontColor=#Accent#,{A_VAL}
    StringAlign=Right
    NumOfDecimals=0
    AntiAlias=1
    Text=%1%
    """).strip()]

    for i in range(total):
        threshold = (i + 1) / total * 100
        out.append(f"[MeasureDot{i}]\nMeasure=Calc\n"
                   f"Formula=(MeasureRAMPct >= {threshold:.4f}) ? 255 : 30")

    shapes = []
    for i in range(total):
        c, r = divmod(i, rows)          # column-major fill, as eDEX does it
        key = 'Shape' if i == 0 else f'Shape{i + 1}'
        shapes.append(f"{key}=Rectangle {c * (dot + gap)},{r * (dot + gap)},{dot},{dot} | "
                      f"Fill Color #Accent#,[MeasureDot{i}] | StrokeWidth 0")
    out.append("[MeterDots]\nMeter=Shape\nX=%d\nY=14R\nDynamicVariables=1\n%s"
               % (PAD, '\n'.join(shapes)))

    out.append(textwrap.dedent(f"""
    [MeterSwapLabel]
    Meter=String
    X={PAD}
    Y=14R
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringCase=Upper
    AntiAlias=1
    Text=Swap

    [MeterSwapBarBg]
    Meter=Shape
    X={PAD + 46}
    Y=6r
    Shape=Rectangle 0,0,{bar_w},3 | Fill Color #Accent#,90 | StrokeWidth 0

    [MeterSwapBar]
    Meter=Bar
    MeasureName=MeasureSwap
    X={PAD + 46}
    Y=0r
    W={bar_w}
    H=3
    BarColor=#Accent#,255

    [MeterSwapText]
    Meter=String
    MeasureName=MeasureSwapTotal
    X={W - PAD}
    Y=-7r
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringAlign=Right
    AntiAlias=1
    AutoScale=1
    Text=%1
    """).strip())
    return '\n\n'.join(out)


# ----------------------------------------------------------------- TOPLIST ---
def toplist(interval=30):
    """eDEX mod_toplist. Sampled by @Resources/toplist.ps1 rather than a plugin:
    UsageMonitor access-violates on the Process category under Windows 11 25H2,
    and AdvancedCPU's TopProcess yields raw counters instead of names."""
    hdr = skin_header(extra='OnRefreshAction=[!CommandMeasure MeasureTop "Run"]')
    return '\n\n'.join([hdr, header('Top Processes', 'toplist'), textwrap.dedent(f"""
    [MeasureTop]
    Measure=Plugin
    Plugin=RunCommand
    Program=powershell
    Parameter=-NoProfile -ExecutionPolicy Bypass -File "#@#toplist.ps1"
    OutputType=ANSI
    State=Hide
    FinishAction=[!UpdateMeter MeterTopTable][!Redraw]

    ; RunCommand never fires on its own -- it only executes when sent "Run".
    ; This timer measure ticks once every #interval# updates and issues it.
    [MeasureTrigger]
    Measure=Calc
    Formula=1
    UpdateDivider={interval}
    OnUpdateAction=[!CommandMeasure MeasureTop "Run"]

    [MeterTopHead]
    Meter=String
    X={PAD}
    Y=10R
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringCase=Upper
    AntiAlias=1
    Text=Name | CPU | Mem

    [MeterTopTable]
    Meter=String
    MeasureName=MeasureTop
    X={PAD}
    Y=6R
    W={W - PAD * 2}
    FontFace=#FontMono#
    FontSize={FS_MONO}
    FontColor=#Accent#,235
    AntiAlias=1
    ClipString=1
    Text=%1
    """).strip()])


# ----------------------------------------------------------------- NETSTAT ---
def netstat():
    """eDEX's network status strip: state, address, latency."""
    out = [skin_header(), header('Network Status', '[ Refresh ]',
                             right_action='[!Refresh]'), textwrap.dedent("""
    [MeasureIP]
    Measure=Plugin
    Plugin=SysInfo
    SysInfoType=IP_ADDRESS
    SysInfoData=Best

    [MeasureAdapter]
    Measure=Plugin
    Plugin=SysInfo
    SysInfoType=ADAPTER_DESCRIPTION
    SysInfoData=Best

    [MeasurePing]
    Measure=Plugin
    Plugin=PingPlugin
    DestAddress=1.1.1.1
    UpdateRate=20
    TimeoutValue=2000
    Substitute="2000":"--"

    [MeasureState]
    Measure=Calc
    Formula=(MeasurePing > 0 && MeasurePing < 2000) ? 1 : 0
    Substitute="1":"ONLINE","0":"OFFLINE"
    """).strip()]
    # State and ping share a row; the address and adapter each get the full
    # width, because an IPv4 address does not fit in a third of 250px.
    out.append(stat_row('Net', [
        ('State', 'MeasureState', True),
        ('Ping', 'MeasurePing', True),
    ], '10R'))
    for i, (label, measure) in enumerate((('IPv4', 'MeasureIP'),
                                          ('Adapter', 'MeasureAdapter'))):
        out.append(textwrap.dedent(f"""
        [MeterWide{i}Label]
        Meter=String
        X={PAD}
        Y={GAP}R
        FontFace=#FontLight#
        FontSize={FS_LABEL}
        FontColor=#Accent#,{A_LABEL}
        StringCase=Upper
        AntiAlias=1
        Text={label}

        [MeterWide{i}Value]
        Meter=String
        MeasureName={measure}
        X={PAD}
        Y={ROW}r
        W={W - PAD * 2}
        H={H_VAL}
        ClipString=1
        FontFace=#FontMain#
        FontSize={FS_VAL}
        FontColor=#Accent#,{A_VAL}
        AntiAlias=1
        Text=%1
        """).strip())
    return '\n\n'.join(out)


# ---------------------------------------------------------------- CONNINFO ---
def conninfo(gh=95):
    """eDEX mod_conninfo: mirrored up/down histograms sharing a centre rule.

    This occupies the slot eDEX gives its globe -- a spinning WebGL sphere has
    no Rainmeter equivalent and showed nothing real, so the space goes to the
    traffic graph instead, which is what the panel is actually for.
    """
    gw = W - PAD * 2
    return '\n\n'.join([skin_header(), header('Network Usage', 'conninfo'),
                        textwrap.dedent(f"""
    [MeasureDown]
    Measure=NetIn
    Interface=Best
    MaxValue=#NetMax#

    [MeasureUp]
    Measure=NetOut
    Interface=Best
    MaxValue=#NetMax#

    [MeasureDownText]
    Measure=NetIn
    Interface=Best

    [MeasureUpText]
    Measure=NetOut
    Interface=Best

    [MeterTrafficLabel]
    Meter=String
    X={PAD}
    Y=10R
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    StringCase=Upper
    AntiAlias=1
    Text=Up / Down

    [MeterGraphTop]
    Meter=Shape
    X={PAD}
    Y=6R
    Shape=Line 0,0,{gw},0 | StrokeWidth 1 | Stroke Color #Accent#,70 | StrokeDashes 3,3

    [MeterDownGraph]
    Meter=Line
    LineCount=1
    LineColor=#Accent#,220
    AutoScale=1
    SolidColor=#Accent#,10
    MeasureName=MeasureDown
    X={PAD}
    Y=2R
    W={gw}
    H={gh}
    GraphStart=Right

    [MeterMidRule]
    Meter=Shape
    X={PAD}
    Y=0R
    Shape=Line 0,0,{gw},0 | StrokeWidth 1 | Stroke Color #Accent#,120

    [MeterUpGraph]
    Meter=Line
    LineCount=1
    LineColor=#Accent#,220
    AutoScale=1
    SolidColor=#Accent#,10
    MeasureName=MeasureUp
    X={PAD}
    Y=1R
    W={gw}
    H={gh}
    GraphStart=Right
    Flip=1

    [MeterGraphBottom]
    Meter=Shape
    X={PAD}
    Y=0R
    Shape=Line 0,0,{gw},0 | StrokeWidth 1 | Stroke Color #Accent#,70 | StrokeDashes 3,3

    [MeterDownLabel]
    Meter=String
    MeasureName=MeasureDownText
    X={PAD}
    Y=6R
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_VAL}
    AntiAlias=1
    AutoScale=1
    Text=DOWN %1/s

    [MeterUpLabel]
    Meter=String
    MeasureName=MeasureUpText
    X={W - PAD}
    Y=0r
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_VAL}
    StringAlign=Right
    AntiAlias=1
    AutoScale=1
    Text=UP %1/s
    """).strip()])


# -------------------------------------------------------------- FILESYSTEM ---
def filesystem(drives, rows=9, width=None):
    """eDEX's file browser, backed by the FileView plugin.

    FileView has no parent/child relationship: there is no `FileViewParent`
    option at all (the DLL's option list is Path / Count / Index / Type / Sort*
    / Show* / Icon*). Every measure carries its own `Path` and picks an entry
    with `Index`. Omitting Path makes the plugin list the machine's drives
    instead, which is why a wrong config shows `C:\\` on every row.
    """
    w = W if width is None else width
    row_h = 16
    out = [skin_header(2000), header('Filesystem', 'tracking', width=w),
           textwrap.dedent(f"""
    [MeasureFolderPath]
    Measure=Plugin
    Plugin=FileView
    Path=#FilePath#
    Type=FolderPath

    [MeterPath]
    Meter=String
    MeasureName=MeasureFolderPath
    X={PAD}
    Y=10R
    W={w - PAD * 2}
    H={H_LABEL}
    ClipString=1
    FontFace=#FontLight#
    FontSize={FS_LABEL}
    FontColor=#Accent#,{A_LABEL}
    AntiAlias=1
    Text=%1
    """).strip()]

    for i in range(1, rows + 1):
        out.append(textwrap.dedent(f"""
        [MeasureFile{i}]
        Measure=Plugin
        Plugin=FileView
        Path=#FilePath#
        Count={rows}
        Index={i}
        Type=FileName
        ShowDotDot=1
        SortType=Type
        """).strip())

    top = 54
    for i in range(1, rows + 1):
        out.append(textwrap.dedent(f"""
        [MeterFile{i}]
        Meter=String
        MeasureName=MeasureFile{i}
        X={PAD}
        Y={top + (i - 1) * row_h}
        W={w - PAD * 2}
        H={row_h}
        ClipString=1
        FontFace=#FontMono#
        FontSize={FS_MONO}
        FontColor=#Accent#,220
        AntiAlias=1
        LeftMouseUpAction=[!CommandMeasure MeasureFile{i} "FollowPath"]
        Text=%1
        """).strip())
    return '\n\n'.join(out)


# ---------------------------------------------------------------- TERMINAL ---
def terminal(tw, th):
    """eDEX's main shell panel.

    Rainmeter cannot host a PTY, so this draws the chrome -- title bar, frame,
    corner ticks -- and the real terminal window is launched sized to sit
    inside it. Clicking the panel opens the shell, so this skin is deployed
    with ClickThrough=0 while the read-only panels keep it on.
    """
    tick = 12
    return '\n\n'.join([
        skin_header(1000),
        header('Main Shell', 'terminal', width=tw),
        textwrap.dedent(f"""
        [MeterFrame]
        Meter=Shape
        X=0
        Y=8R
        Shape=Rectangle 0,0,{tw},{th} | StrokeWidth 1 | Stroke Color #Accent#,60 | Fill Color #Background#,120
        Shape2=Line 0,0,{tick},0 | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape3=Line 0,0,0,{tick} | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape4=Line {tw - tick},0,{tw},0 | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape5=Line {tw},0,{tw},{tick} | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape6=Line 0,{th - tick},0,{th} | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape7=Line 0,{th},{tick},{th} | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape8=Line {tw - tick},{th},{tw},{th} | StrokeWidth 2 | Stroke Color #Accent#,170
        Shape9=Line {tw},{th - tick},{tw},{th} | StrokeWidth 2 | Stroke Color #Accent#,170
        LeftMouseUpAction=["powershell.exe" "-NoProfile" "-WindowStyle" "Hidden" "-ExecutionPolicy" "Bypass" "-File" "#@#launch_terminal.ps1"]
        ToolTipText=Open the eDEX shell

        [MeterHint]
        Meter=String
        X={tw // 2}
        Y={-th // 2}r
        FontFace=#FontLight#
        FontSize=11
        FontColor=#Accent#,130
        StringAlign=CenterCenter
        StringCase=Upper
        AntiAlias=1
        Text=Click to open shell
        """).strip(),
    ])


# ------------------------------------------------------------------- BUILD ---
def pick_fonts():
    """eDEX-UI's own fonts when setup could extract them, else Windows' own.

    United Sans is a commercial typeface, so the project never ships it; it is
    only used when the person has eDEX-UI installed (bootstrap_assets.ps1
    copies it out of their copy). Bahnschrift and Consolas ship with Windows
    10/11 and have a similar technical look.
    """
    ttf = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), 'build', 'ttf')
    if os.path.exists(os.path.join(ttf, 'united_sans_medium.ttf')):
        return {'main': 'United Sans Reg Medium', 'light': 'UnitedSansReg-Light',
                'mono': 'Fira Mono' if os.path.exists(os.path.join(ttf, 'fira_mono.ttf')) else 'Consolas'}
    return {'main': 'Bahnschrift', 'light': 'Bahnschrift Light', 'mono': 'Consolas'}


def variables(th, home, desktop):
    fonts = pick_fonts()
    return textwrap.dedent(f"""
    [Variables]
    ; Palette lifted verbatim from eDEX-UI's tron.json -- edit here to retheme
    ; the whole suite at once.
    Accent={th['accent']}
    Background={th['bg']}
    Grey={th['grey']}
    FontMain={fonts['main']}
    FontLight={fonts['light']}
    FontMono={fonts['mono']}
    ; Full-scale deflection for the traffic histograms, in bytes/sec.
    NetMax=5000000
    ; Starting directory for the Filesystem panel. Point it anywhere;
    ; the home directory is avoided because FileView cannot hide the
    ; dot-folders that sort ahead of everything real.
    FilePath={home}
    ; Folder the Shortcuts panel mirrors -- point this anywhere you like.
    DesktopPath={desktop}
    """).strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', default='skins/eDEX-Tron')
    p.add_argument('--theme', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        'themes', 'edex', 'tron.json'))  # bundled; no eDEX-UI install needed
    p.add_argument('--cores', type=int, default=20)
    p.add_argument('--cpu-name', default='CPU')
    p.add_argument('--drives', default='C')
    p.add_argument('--width', type=int, default=250)
    p.add_argument('--term-width', type=int, default=700)
    p.add_argument('--term-height', type=int, default=430)
    p.add_argument('--fs-width', type=int, default=430,
                   help='filesystem panel width in logical px')
    p.add_argument('--fs-rows', type=int, default=9)
    p.add_argument('--graph-height', type=int, default=95,
                   help='height of each half of the network usage graph')
    # Not the home directory: it holds ~30 tool config folders (.cache,
    # .docker, .claude ...) that sort ahead of everything real. They carry no
    # hidden attribute and FileView has no exclusion filter, so a browser
    # rooted there can only show junk. Documents is a folder people browse.
    p.add_argument('--home', default=os.path.join(
        os.environ.get('USERPROFILE', 'C:\\'), 'Documents'))
    p.add_argument('--desktop', default=os.path.join(
        os.environ.get('USERPROFILE', 'C:\\'), 'Desktop'))
    p.add_argument('--config', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'theme.json'))
    a = p.parse_args()

    global W
    W = a.width

    th = load_theme(a.theme)
    try:
        with open(a.config, encoding='utf-8-sig') as f:
            cfg = json.load(f)
        if cfg.get('accent'):
            th['accent'] = ','.join(str(v) for v in hex2rgb(cfg['accent']))
        if cfg.get('background'):
            th['bg'] = ','.join(str(v) for v in hex2rgb(cfg['background']))
    except OSError:
        pass
    os.makedirs(os.path.join(a.out, '@Resources'), exist_ok=True)
    with open(os.path.join(a.out, '@Resources', 'Variables.inc'), 'w') as f:
        f.write(variables(th, a.home, a.desktop) + '\n')

    skins = {
        'Clock': clock(),
        'CpuInfo': cpuinfo(a.cores, a.cpu_name),
        'RamWatcher': ramwatcher(),
        'TopList': toplist(),
        'NetStat': netstat(),
        # The Network Usage graph takes the slot eDEX gives its globe.
        'ConnInfo': conninfo(a.graph_height),
        'FileSystem': filesystem(a.drives.split(','), rows=a.fs_rows, width=a.fs_width),
        # Dock and Desktop are generated by gen_dock.ps1 -- they need icons
        # extracted from real executables, which is a Windows API job.
        'Terminal': terminal(a.term_width, a.term_height),
    }
    problems = 0
    for name, body in skins.items():
        # Rainmeter silently merges same-named sections, so a collision between
        # two meter groups shows up as meters drawn on top of each other rather
        # than as an error. Catch it at generation time instead.
        sections = re.findall(r'^\[([^\]]+)\]', body, re.M)
        dupes = {s for s in sections if sections.count(s) > 1}
        if dupes:
            print(f'{name:12} ERROR duplicate sections: {", ".join(sorted(dupes))}')
            problems += 1

        d = os.path.join(a.out, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, f'{name}.ini'), 'w') as f:
            f.write(body + '\n')
        print(f'{name:12} {len(body.splitlines()):5} lines')

    if problems:
        raise SystemExit(f'{problems} skin(s) have duplicate section names')


if __name__ == '__main__':
    main()
