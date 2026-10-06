// The key click, played properly.
//
// PlaySound was the obvious thing and it is wrong for this in three ways:
// it opens the audio device on every call, which is the lag between pressing
// a key and hearing it; it can only play one sound at a time, so typing faster
// than the click is long cuts each one off; and it plays the same bytes every
// time, which after a few seconds stops sounding like a keyboard and starts
// sounding like a machine with a bell on it.
//
// So: open the device once and leave it open, keep several buffers queued so
// presses can overlap, and pre-render a handful of variants of the sample --
// slightly different pitch and level -- so no two consecutive presses are
// identical. That is roughly what a real keyboard does: the same mechanism
// each time, never quite the same sound.

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

static class KeyAudio
{
    [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr hwo, int deviceId,
        ref WAVEFORMATEX fmt, IntPtr callback, IntPtr instance, int flags);
    [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr hwo, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr hwo, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr hwo, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr hwo);
    [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr hwo);

    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX
    {
        public ushort wFormatTag, nChannels;
        public uint nSamplesPerSec, nAvgBytesPerSec;
        public ushort nBlockAlign, wBitsPerSample, cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength, dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags, dwLoops;
        public IntPtr lpNext, reserved;
    }

    const int WAVE_MAPPER = -1;
    const uint WHDR_DONE = 0x00000001;
    const uint WHDR_INQUEUE = 0x00000010;
    const int VARIANTS = 6;        // how many versions of the sample to keep
    const int VOICES = 3;          // how many may be sounding at once

    static IntPtr device = IntPtr.Zero;
    static readonly List<IntPtr> headers = new List<IntPtr>();
    static readonly List<IntPtr> blocks = new List<IntPtr>();
    static readonly Random rnd = new Random();
    static int hdrSize;
    static int lastVariant = -1;
    static int writeErrors;
    // Kept so the variants can be written out and listened to; see Dump.
    static readonly List<short[]> shapedVariants = new List<short[]>();
    static int shapedRate = 44100;

    public static bool Ready { get { return device != IntPtr.Zero; } }

    /// <summary>Open the device and render the variants. False if it cannot.</summary>
    public static bool Start(string wavPath, out string problem)
    {
        problem = null;
        try
        {
            int rate, channels, bits;
            short[] pcm = ReadWav(wavPath, out rate, out channels, out bits);
            if (pcm == null) { problem = "not a 16-bit PCM wav"; return false; }

            var fmt = new WAVEFORMATEX
            {
                wFormatTag = 1,                                  // PCM
                nChannels = (ushort)channels,
                nSamplesPerSec = (uint)rate,
                wBitsPerSample = 16,
                nBlockAlign = (ushort)(channels * 2),
                cbSize = 0,
            };
            fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;

            int err = waveOutOpen(out device, WAVE_MAPPER, ref fmt, IntPtr.Zero, IntPtr.Zero, 0);
            if (err != 0) { device = IntPtr.Zero; problem = "waveOutOpen failed (" + err + ")"; return false; }

            hdrSize = Marshal.SizeOf(typeof(WAVEHDR));

            // Stretch whatever sample this is to the length a keystroke should
            // sound, then spread the variants around that -- rather than
            // around however long the source happened to be. The stretch keeps
            // the pitch where it was, so the six variants are the same keyboard
            // rather than six different ones.
            double targetMs = EdexTron.Number("keyclickms", 43.0);
            double sourceMs = pcm.Length / (double)channels / rate * 1000.0;
            double baseSpeed = targetMs > 1.0 ? sourceMs / targetMs : 1.0;

            // How loud the clicks are, as a percentage, and only the clicks:
            // the boot sound and everything else keep their own levels. Baked
            // into the variants rather than set on the device, because the
            // device is the system's -- turning it down would turn down
            // whatever else happened to be playing through it.
            double volume = EdexTron.Number("keyclickvolume", 100.0) / 100.0;
            if (volume < 0.0) volume = 0.0;
            if (volume > 1.0) volume = 1.0;

            for (int v = 0; v < VARIANTS; v++)
            {
                // Either side of that: a little slower and quieter through a
                // little faster and louder.
                double spread = VARIANTS == 1 ? 0.0 : (v / (double)(VARIANTS - 1)) * 2.0 - 1.0;
                int targetLen = (int)(pcm.Length / channels / baseSpeed
                                      * (1.0 + spread * 0.05));
                short[] shaped = Reshape(pcm, targetLen,
                                         (1.0 - Math.Abs(spread) * 0.18) * volume, rate);
                shapedVariants.Add(shaped);
                shapedRate = rate;
                byte[] raw = new byte[shaped.Length * 2];
                Buffer.BlockCopy(shaped, 0, raw, 0, raw.Length);

                for (int voice = 0; voice < VOICES; voice++)
                {
                    IntPtr block = Marshal.AllocHGlobal(raw.Length);
                    Marshal.Copy(raw, 0, block, raw.Length);
                    blocks.Add(block);

                    var hdr = new WAVEHDR { lpData = block, dwBufferLength = (uint)raw.Length };
                    IntPtr hp = Marshal.AllocHGlobal(hdrSize);
                    Marshal.StructureToPtr(hdr, hp, false);
                    waveOutPrepareHeader(device, hp, hdrSize);
                    headers.Add(hp);
                }
            }
            return true;
        }
        catch (Exception ex)
        {
            problem = ex.Message;
            Stop();
            return false;
        }
    }

    /// <summary>One keystroke. Returns immediately; the device does the work.</summary>
    public static void Play()
    {
        if (device == IntPtr.Zero) return;

        // A different variant from the last one, so repeats never pair up.
        int variant = rnd.Next(VARIANTS);
        if (variant == lastVariant) variant = (variant + 1) % VARIANTS;
        lastVariant = variant;

        // Take any free voice, starting with the chosen variant's own. Nothing
        // already sounding is ever cut short: a press that lands while the one
        // before it is still ringing simply layers on top, which is what typing
        // on a real keyboard does and what made eDEX-UI's version convincing.
        for (int n = 0; n < VARIANTS; n++)
        {
            int v = (variant + n) % VARIANTS;
            for (int voice = 0; voice < VOICES; voice++)
            {
                IntPtr hp = headers[v * VOICES + voice];
                // dwFlags sits after lpData, dwBufferLength, dwBytesRecorded
                // and dwUser. A header still queued cannot be rewritten.
                uint flags = (uint)Marshal.ReadInt32(hp, IntPtr.Size + 4 + 4 + IntPtr.Size);
                // Busy means queued. Testing for anything else catches
                // WHDR_PREPARED, which every header carries from the moment it
                // is prepared and never loses -- which marks all of them busy
                // forever, so nothing is ever played and nothing reports an
                // error either.
                if ((flags & WHDR_INQUEUE) != 0) continue;
                lastVariant = v;
                int rc = waveOutWrite(device, hp, hdrSize);
                if (rc != 0 && writeErrors++ < 3)
                    EdexTron.Log("key click: waveOutWrite failed (" + rc + ")");
                return;
            }
        }
        // All eighteen voices are sounding at once, which needs typing faster
        // than about two hundred keys a second. Drop it rather than cut one off.
    }

    /// <summary>Write the variants out as wavs, so they can be listened to
    /// rather than taken on trust. eDEX-Tron.exe dumpclicks &lt;folder&gt;.</summary>
    public static int Dump(string folder)
    {
        Directory.CreateDirectory(folder);
        for (int i = 0; i < shapedVariants.Count; i++)
        {
            short[] v = shapedVariants[i];
            string path = Path.Combine(folder, "variant" + (i + 1) + ".wav");
            using (var f = new FileStream(path, FileMode.Create))
            using (var w = new BinaryWriter(f))
            {
                int dataLen = v.Length * 2;
                w.Write(new char[] { 'R', 'I', 'F', 'F' });
                w.Write(36 + dataLen);
                w.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' });
                w.Write(16); w.Write((short)1); w.Write((short)1);
                w.Write(shapedRate); w.Write(shapedRate * 2);
                w.Write((short)2); w.Write((short)16);
                w.Write(new char[] { 'd', 'a', 't', 'a' });
                w.Write(dataLen);
                foreach (short sample in v) w.Write(sample);
            }
        }
        return shapedVariants.Count;
    }

    public static void Stop()
    {
        if (device != IntPtr.Zero)
        {
            waveOutReset(device);
            foreach (IntPtr hp in headers) waveOutUnprepareHeader(device, hp, hdrSize);
            waveOutClose(device);
            device = IntPtr.Zero;
        }
        foreach (IntPtr hp in headers) Marshal.FreeHGlobal(hp);
        foreach (IntPtr b in blocks) Marshal.FreeHGlobal(b);
        headers.Clear();
        blocks.Clear();
        shapedVariants.Clear();
    }

    // --- sample handling -----------------------------------------------------

    /// <summary>Make the sample `targetLen` samples long without moving its pitch,
    /// then scale it by `gain`.</summary>
    static short[] Reshape(short[] src, int targetLen, double gain, int rate)
    {
        short[] body = TimeStretch(src, targetLen, rate);
        int n = body.Length;
        var outp = new short[n];
        for (int i = 0; i < n; i++)
            outp[i] = (short)Math.Max(short.MinValue, Math.Min(short.MaxValue, body[i] * gain));

        // Half a millisecond in and three out: a buffer that starts or stops on
        // a non-zero sample adds a click of its own, on top of the one wanted.
        int fadeIn = Math.Min(n, 22), fadeOut = Math.Min(n, 132);
        for (int i = 0; i < fadeIn; i++) outp[i] = (short)(outp[i] * i / (double)fadeIn);
        for (int i = 0; i < fadeOut; i++)
            outp[n - 1 - i] = (short)(outp[n - 1 - i] * i / (double)fadeOut);
        return outp;
    }

    /// <summary>Change the length, keeping the pitch.
    ///
    /// Resampling would be one line, but it moves the pitch with the length --
    /// a longer click becomes a deeper one, and six variants become six
    /// different keyboards. This is overlap-add instead: cut the sound into
    /// short overlapping grains and lay them down at a different spacing than
    /// they were taken from. Each grain keeps its own waveform, so the pitch
    /// does not move; only how often they recur changes.
    ///
    /// Two details earn their keep. The attack is copied through untouched --
    /// stretching the first few milliseconds of a percussive sound smears the
    /// very thing that makes it read as a click. And each grain is positioned
    /// by searching a small window for the offset that best matches what has
    /// already been written, which is what keeps overlap-add from phasing
    /// (this is WSOLA; without the search it sounds hollow and flanged).
    /// </summary>
    static short[] TimeStretch(short[] src, int targetLen, int rate)
    {
        if (targetLen <= 0) return src;
        if (Math.Abs(targetLen - src.Length) <= 2) return (short[])src.Clone();

        int attack = Math.Min(src.Length / 2, (int)(rate * 0.008));   // 8ms, kept intact
        int srcTail = src.Length - attack;
        int dstTail = targetLen - attack;
        if (srcTail < 64 || dstTail < 64)
        {
            // Too short to granulate sensibly; pad or cut the tail instead.
            var plain = new short[targetLen];
            for (int i = 0; i < targetLen; i++) plain[i] = i < src.Length ? src[i] : (short)0;
            return plain;
        }

        double ratio = dstTail / (double)srcTail;
        int grain = Math.Max(64, Math.Min(srcTail / 3, (int)(rate * 0.006)));  // ~6ms
        int synHop = grain / 2;                                   // 50% overlap
        int anaHop = Math.Max(1, (int)Math.Round(synHop / ratio));
        int search = Math.Max(8, grain / 8);

        var window = new double[grain];
        for (int i = 0; i < grain; i++)
            window[i] = 0.5 - 0.5 * Math.Cos(2.0 * Math.PI * i / (grain - 1));

        var acc = new double[targetLen + grain];
        for (int i = 0; i < attack; i++) acc[i] = src[i];

        int outPos = attack, inPos = attack;
        bool first = true;
        while (outPos + grain < targetLen + grain && inPos < src.Length)
        {
            int best = inPos;
            if (!first)
            {
                // Where does this grain line up best with what is already down?
                double bestScore = double.NegativeInfinity;
                for (int d = -search; d <= search; d++)
                {
                    int p = inPos + d;
                    if (p < attack || p + synHop >= src.Length) continue;
                    double score = 0;
                    for (int k = 0; k < synHop; k += 2) score += acc[outPos + k] * src[p + k];
                    if (score > bestScore) { bestScore = score; best = p; }
                }
            }
            for (int k = 0; k < grain; k++)
            {
                int sp = best + k;
                if (sp >= src.Length) break;
                acc[outPos + k] += src[sp] * window[k];
            }
            inPos = best + anaHop;
            outPos += synHop;
            first = false;
        }

        var outp = new short[targetLen];
        for (int i = 0; i < targetLen; i++)
            outp[i] = (short)Math.Max(short.MinValue, Math.Min(short.MaxValue, acc[i]));
        return outp;
    }

    /// <summary>The samples out of a 16-bit PCM wav, or null if it is not one.</summary>
    static short[] ReadWav(string path, out int rate, out int channels, out int bits)
    {
        rate = 44100; channels = 1; bits = 16;
        byte[] f = File.ReadAllBytes(path);
        if (f.Length < 12 || f[0] != 'R' || f[1] != 'I' || f[2] != 'F' || f[3] != 'F') return null;

        int pos = 12;
        int dataAt = -1, dataLen = 0;
        while (pos + 8 <= f.Length)
        {
            string id = "" + (char)f[pos] + (char)f[pos + 1] + (char)f[pos + 2] + (char)f[pos + 3];
            int len = BitConverter.ToInt32(f, pos + 4);
            int body = pos + 8;
            if (id == "fmt ")
            {
                int tag = BitConverter.ToUInt16(f, body);
                channels = BitConverter.ToUInt16(f, body + 2);
                rate = BitConverter.ToInt32(f, body + 4);
                bits = BitConverter.ToUInt16(f, body + 14);
                if (tag != 1 || bits != 16) return null;         // only plain 16-bit PCM
            }
            else if (id == "data") { dataAt = body; dataLen = len; }
            pos = body + len + (len % 2);                        // chunks are word aligned
        }
        if (dataAt < 0) return null;
        dataLen = Math.Min(dataLen, f.Length - dataAt);
        var pcm = new short[dataLen / 2];
        Buffer.BlockCopy(f, dataAt, pcm, 0, pcm.Length * 2);
        return pcm;
    }
}
