# Nana Creator Studio — open-source components

Nana Creator Studio Professional includes open-source software. This repository holds the
source code and build instructions for the parts whose licences ask for that, so anyone can
get them, rebuild them and see exactly what is inside the app.

The app's own code is not open source and is not in this repository.

## FFmpeg 6.1.6 (LGPL 2.1 or later)

The app uses the `ffmpeg` program to make and analyse videos on your Mac. It is built
**without** `--enable-gpl` and **without** `--enable-nonfree`, so it is covered by the
GNU Lesser General Public License, version 2.1 or later. It includes:

| Component | Version | Licence |
|---|---|---|
| FFmpeg | 6.1.6 | LGPL 2.1 or later |
| FreeType | 2.14.3 | FreeType License (FTL) |
| HarfBuzz | 14.6.0 | "Old MIT" |
| zimg | 3.0.6 | WTFPL |

**Get the exact source:** download the archives from the
[ffmpeg-lgpl-6.1.6 release](../../releases/tag/ffmpeg-lgpl-6.1.6). Their SHA-256 checksums are in
[`ffmpeg-lgpl-6.1.6/SHA256SUMS`](ffmpeg-lgpl-6.1.6/SHA256SUMS) and are also pinned inside the build script.

**Rebuild it:** [`ffmpeg-lgpl-6.1.6/build-macos.sh`](ffmpeg-lgpl-6.1.6/build-macos.sh) is the exact script
used (macOS 12 or later, universal Apple silicon + Intel). Run it with a work folder:

```
bash ffmpeg-lgpl-6.1.6/build-macos.sh ~/ffmpeg-build
```

It downloads the same archives (plus the build-only tools pkgconf 3.0.10 and nasm 2.16.03,
which are not shipped in the app), checks every checksum and stops on any mismatch.
[`ffmpeg-lgpl.json`](ffmpeg-lgpl-6.1.6/ffmpeg-lgpl.json) records the checksum of the program the app ships
before Apple code-signing (signing adds a signature, so the signed copy's checksum differs).

**Licence texts:** [`ffmpeg-lgpl-6.1.6/licenses/`](ffmpeg-lgpl-6.1.6/licenses/). The same files are inside the
app, and the app's Help → Licences & Credits page shows them.

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project. This build is not
made or endorsed by the FFmpeg project.
