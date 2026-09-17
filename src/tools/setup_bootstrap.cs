// eDEX-Tron-Setup.exe
//
// A single-file installer: the project is embedded as payload.zip. It unpacks
// to Documents\eDEX-Tron (the path every helper script expects) and hands over
// to src\setup.ps1 in a visible PowerShell window, which installs the
// dependencies and applies the theme.
//
// Built by build_release.ps1, which replaces @VERSION@.

using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("eDEX-Tron Setup")]
[assembly: AssemblyProduct("eDEX-Tron")]
[assembly: AssemblyDescription("Windows desktop theme based on eDEX-UI by Gabriel Saillard")]
[assembly: AssemblyVersion("@VERSION@.0")]
[assembly: AssemblyFileVersion("@VERSION@.0")]
[assembly: AssemblyInformationalVersion("@VERSION@")]

static class EdexTronSetup
{
    const string Version = "@VERSION@";

    // Files a person edits; never overwrite them when installing over an
    // existing copy. (They are not in the payload today, but guard anyway.)
    static readonly string[] Keep = { "dock.txt", "theme.json" };

    [STAThread]
    static int Main()
    {
        string docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        string target = Path.GetFullPath(Path.Combine(docs, "eDEX-Tron"));
        bool upgrading = Directory.Exists(target);

        string prompt =
            "eDEX-Tron " + Version + " (pre-release)\n" +
            "A Windows theme based on eDEX-UI by Gabriel \"Squared\" Saillard.\n\n" +
            (upgrading ? "Update the existing install in:\n" : "Install to:\n") + target + "\n\n" +
            "Setup will install Rainmeter, TranslucentTB and Python if they are missing,\n" +
            "change your wallpaper, accent colour and app themes (backed up first),\n" +
            "and restart Explorer once. Undo any time with src\\uninstall.ps1.\n\n" +
            "Continue?";
        if (MessageBox.Show(prompt, "eDEX-Tron Setup", MessageBoxButtons.OKCancel,
                            MessageBoxIcon.Information) != DialogResult.OK)
            return 1;

        try
        {
            Extract(target);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not unpack the files:\n\n" + ex.Message +
                "\n\nIf the theme is running, switch it off first and try again.",
                "eDEX-Tron Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        string script = Path.Combine(target, "src", "setup.ps1");
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
        psi.UseShellExecute = true;
        psi.WorkingDirectory = target;
        Process.Start(psi);
        return 0;
    }

    static void Extract(string target)
    {
        string root = target + Path.DirectorySeparatorChar;
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry e in zip.Entries)
            {
                string dest = Path.GetFullPath(Path.Combine(target, e.FullName));
                // refuse anything that would land outside the install folder
                if (!dest.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;

                if (e.FullName.EndsWith("/"))
                {
                    Directory.CreateDirectory(dest);
                    continue;
                }
                if (File.Exists(dest) && Array.IndexOf(Keep, e.FullName) >= 0) continue;

                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                e.ExtractToFile(dest, true);
            }
        }
    }
}
