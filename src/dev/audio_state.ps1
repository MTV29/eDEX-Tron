# What Windows thinks the volume is: the default playback device, its master
# level and mute, and the level and mute of every application that has an audio
# session on it.
#
# Written because "PlaySound returned True" and "I cannot hear it" are both
# true at once surprisingly often, and the gap between them is almost always
# here: a per-application slider left at zero, or a mute nobody set on purpose.
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] public class MMDeviceEnumerator { }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator
{
    int NotImpl1();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice
{
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
}

[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore
{
    int GetCount(out int cProps);
    int GetAt(int iProp, out PROPERTYKEY pkey);
    int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
}

[StructLayout(LayoutKind.Sequential)] public struct PROPERTYKEY { public Guid fmtid; public int pid; }
[StructLayout(LayoutKind.Explicit)] public struct PROPVARIANT
{
    [FieldOffset(0)] public short vt;
    [FieldOffset(8)] public IntPtr pointerValue;
}

[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume
{
    int NotImpl1(); int NotImpl2(); int NotImpl3(); int NotImpl4();
    int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
    int GetMasterVolumeLevel(out float level);
    int GetMasterVolumeLevelScalar(out float level);
    int NotImpl5(); int NotImpl6(); int NotImpl7(); int NotImpl8();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}

[ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionManager2
{
    int NotImpl1(); int NotImpl2();
    int GetSessionEnumerator(out IAudioSessionEnumerator SessionEnum);
}

[ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionEnumerator
{
    int GetCount(out int SessionCount);
    int GetSession(int SessionCount, out IAudioSessionControl Session);
}

[ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl { int NotImpl1(); int GetDisplayName(out IntPtr name); }

[ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl2
{
    int NotImpl1(); int GetDisplayName(out IntPtr name); int NotImpl3(); int NotImpl4();
    int NotImpl5(); int NotImpl6(); int NotImpl7(); int NotImpl8(); int NotImpl9();
    int GetProcessId(out int pid);
}

[ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ISimpleAudioVolume
{
    int SetMasterVolume(float level, ref Guid eventContext);
    int GetMasterVolume(out float level);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}

public static class AudioState
{
    public static string[] Report()
    {
        var lines = new System.Collections.Generic.List<string>();
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);   // eRender, eMultimedia

        var volIid = typeof(IAudioEndpointVolume).GUID;
        object obj;
        device.Activate(ref volIid, 1, IntPtr.Zero, out obj);
        var endpoint = (IAudioEndpointVolume)obj;
        float level; bool muted;
        endpoint.GetMasterVolumeLevelScalar(out level);
        endpoint.GetMute(out muted);
        lines.Add(string.Format("device volume : {0:P0}{1}", level,
                                muted ? "   *** MUTED ***" : ""));

        // PlaySound and the rest of winmm render to the eConsole default,
        // while media players use eMultimedia. When those are different
        // devices, a sound can be playing perfectly into a monitor nobody is
        // listening to, and every API involved still reports success.
        string[] roles = { "eConsole (PlaySound uses this)", "eMultimedia", "eCommunications" };
        for (int r = 0; r < 3; r++)
        {
            IMMDevice d;
            enumerator.GetDefaultAudioEndpoint(0, r, out d);
            string id;
            d.GetId(out id);
            lines.Add(string.Format("  default for {0,-32} {1}", roles[r], id));
        }

        var mgrIid = typeof(IAudioSessionManager2).GUID;
        object mgrObj;
        device.Activate(ref mgrIid, 1, IntPtr.Zero, out mgrObj);
        IAudioSessionEnumerator sessions;
        ((IAudioSessionManager2)mgrObj).GetSessionEnumerator(out sessions);
        int count;
        sessions.GetCount(out count);
        lines.Add("application sessions: " + count);
        for (int i = 0; i < count; i++)
        {
            IAudioSessionControl ctl;
            sessions.GetSession(i, out ctl);
            var ctl2 = (IAudioSessionControl2)ctl;
            int pid;
            ctl2.GetProcessId(out pid);
            string name;
            try { name = System.Diagnostics.Process.GetProcessById(pid).ProcessName; }
            catch { name = "pid " + pid; }
            var sv = (ISimpleAudioVolume)ctl;
            float v; bool m;
            sv.GetMasterVolume(out v);
            sv.GetMute(out m);
            lines.Add(string.Format("  {0,-24} {1,4:P0}{2}", name, v,
                                    m ? "   *** MUTED ***" : ""));
        }
        return lines.ToArray();
    }
}
'@

[AudioState]::Report()
