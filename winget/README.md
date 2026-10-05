# winget package

The manifest for `winget install MTV29.eDEXTron`. Submitting it to
[microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) is the free
way past the SmartScreen warning on the installer — far better value than a
code-signing certificate, which costs a few hundred a year to silence one
dialog.

**This has not been submitted yet.** It is kept here so the next release can
submit it without starting from scratch.

## State

`manifests/m/MTV29/eDEXTron/0.9.1/` validates:

```powershell
winget validate --manifest winget\manifests\m\MTV29\eDEXTron\0.9.1
```

## Before submitting

Two things, in this order:

1. **Point it at a release that registers in Apps & features.** 0.9.1 was built
   before `install.ps1` gained `Register-AppEntry`, so winget cannot tell
   whether that version is installed, which version it is, or how to remove it.
   Any release after that can.
2. **Then add the matching entry to the installer manifest**, so winget
   correlates the package with what it finds installed:

   ```yaml
   AppsAndFeaturesEntries:
     - DisplayName: eDEX-Tron
       Publisher: MTV29
       DisplayVersion: <the version>
   ```

Also update `PackageVersion` (all three files), `ReleaseDate`, `InstallerUrl`,
`InstallerSha256` (from the release's `SHA256SUMS.txt`, uppercased) and
`ReleaseNotesUrl`.

It is also worth having run the clean-machine install test first. Everything
the installer does has only ever been done on machines that already had
Rainmeter, Python and the fonts; winget's reviewers run it on one that does
not, and so should we.

## Submitting

Fork `microsoft/winget-pkgs`, copy the version folder to the same path under
its `manifests/`, and open a pull request. Their pipeline installs the package
on a clean VM and runs the static validators, so expect it to exercise exactly
the paths listed above.

`wingetcreate update MTV29.eDEXTron --version <v> --urls <installer url>` does
the mechanical part of a version bump once the package exists.
