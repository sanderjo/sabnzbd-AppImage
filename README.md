# sabnzbd-AppImage

Build a self-contained [SABnzbd](https://sabnzbd.org) AppImage that runs on
(almost) any x86_64 Linux distribution: anything with glibc 2.17 or newer
(CentOS 7, Ubuntu 14.04, Debian 8 and later).

The AppImage bundles everything SABnzbd needs:

| Component | Source |
|---|---|
| Python 3.13 | conda-forge (built against glibc 2.17, shared OpenSSL) |
| SABnzbd + Python dependencies | SABnzbd source release, manylinux wheels from PyPI |
| unrar | RARLAB `rarlinux-x64` |
| par2 | [par2cmdline-turbo](https://github.com/animetosho/par2cmdline-turbo) (static) |
| 7-Zip | [7-Zip](https://github.com/ip7z/7zip) `7zzs` (static) |
| libstdc++ / libgcc_s | conda-forge, used by unrar, sabctools and ujson only |

conda-forge's Python is used instead of python-build-standalone because the latter
links OpenSSL statically with hidden symbols. That prevents sabctools from using
its faster SSL download path, and SABnzbd shows a warning about it.

## Download

Ready-made AppImages are under **Releases** on the right-hand side of this page
(or go directly to the [Releases page](https://github.com/sanderjo/sabnzbd-AppImage/releases)).

1. Open the release you want: the one marked *Latest* is the current stable
   SABnzbd version; *Pre-release* versions are alphas, betas and release candidates.
2. Under **Assets**, download `SABnzbd-<version>-x86_64.AppImage`.
3. Make the downloaded file executable (browsers don't keep that permission):

   ```sh
   chmod +x SABnzbd-5.1.3-x86_64.AppImage
   ```

Or from the command line, which always fetches the latest stable release:

```sh
url=$(curl -s https://api.github.com/repos/sanderjo/sabnzbd-AppImage/releases/latest | grep -o 'https://[^"]*\.AppImage' | head -1)
wget "$url"
chmod +x "$(basename "$url")"
```

## Usage

```sh
./SABnzbd-5.1.3-x86_64.AppImage            # starts SABnzbd and opens the web UI
./SABnzbd-5.1.3-x86_64.AppImage --help     # all regular SABnzbd.py options work
```

Configuration is stored in `~/.sabnzbd`, just like a regular install.
On systems without FUSE (e.g. many containers), add `--appimage-extract-and-run`.

## Building

Requirements on the build host: bash, curl, tar, unzip, xz, file, objdump, strip.
No compiler or container is needed.

```sh
./build.sh                                  # default SABnzbd version (see build.sh)
SABNZBD_VERSION=5.2.0Beta2 ./build.sh       # any release tag, including betas
```

Downloads are cached in `downloads/`, the AppDir is assembled in `build/`, and the
AppImage is written to the repository root. Versions of the bundled tools are set
at the top of `build.sh`.

### GitHub Actions

Every push and pull request builds the AppImage, starts it as a smoke test, and
uploads it as a workflow artifact. To build a specific release (e.g. a beta), use
*Actions → Build AppImage → Run workflow* and enter the version, or:

```sh
gh workflow run build.yml -f sabnzbd_version=5.2.0Beta2
```

To publish a GitHub Release, tick *Publish the AppImage as a GitHub Release* when
running the workflow, or:

```sh
gh workflow run build.yml -f sabnzbd_version=5.2.0Beta2 -f release=true
```

The release is tagged with the SABnzbd version; alpha, beta and RC versions are
marked as pre-releases. Running it again for the same version replaces the AppImage.

If a future SABnzbd release adds a dependency that is only published as source
(sdist) on PyPI, the dependency step stops with an error. Add it to the
`pip wheel` line in `build.sh`, as is done for `sgmllib3k`.

## Licenses

SABnzbd is GPL-licensed. unrar is freeware from RARLAB; its license
(included in the AppImage under `usr/share/licenses/unrar`) allows distributing
the UnRAR components as long as they are not modified. The AppImage therefore ships
RARLAB's `unrar` binary byte-for-byte unchanged (the build verifies this); a small
wrapper script makes it use the bundled libstdc++.
