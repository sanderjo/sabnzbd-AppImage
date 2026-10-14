#!/usr/bin/env bash
# Build a self-contained SABnzbd AppImage for x86_64 Linux.
#
# Bundles: conda-forge CPython (built against glibc 2.17, with a shared OpenSSL
# so sabctools can use its fast SSL path), SABnzbd + all Python dependencies
# (manylinux wheels), unrar (RARLAB), par2cmdline-turbo (static), 7-Zip
# (static), and libstdc++/libgcc_s for the C++ parts (unrar, sabctools, ujson).
#
# Requirements on the build host: bash, curl, tar, unzip, xz, file, objdump.
set -euo pipefail

SABNZBD_VERSION="${SABNZBD_VERSION:-5.1.3}"
PYTHON_VERSION="3.13.16"
PY_MM="3.13"
MICROMAMBA_VERSION="2.9.0-0"
PAR2_VERSION="1.5.0"
UNRAR_VERSION="723"
SEVENZIP_VERSION="2604"
SEVENZIP_TAG="26.04"
# Highest manylinux level accepted for binary wheels (sabctools is tagged 2.24)
MAX_GLIBC_MINOR=24

ROOT="$(cd "$(dirname "$0")" && pwd)"
DL="$ROOT/downloads"
WORK="$ROOT/build"
APPDIR="$WORK/SABnzbd.AppDir"
OUT="$ROOT/SABnzbd-${SABNZBD_VERSION}-x86_64.AppImage"

fetch() { # url [filename]
    local url="$1" name="${2:-$(basename "$1")}"
    if [ ! -s "$DL/$name" ]; then
        echo ">> Downloading $name" >&2
        curl -fsSL --retry 3 -o "$DL/$name.part" "$url"
        mv "$DL/$name.part" "$DL/$name"
    fi
    echo "$DL/$name"
}

mkdir -p "$DL"
rm -rf "$WORK"
mkdir -p "$WORK" "$APPDIR/usr/bin"

SAB_TGZ=$(fetch "https://github.com/sabnzbd/sabnzbd/releases/download/${SABNZBD_VERSION}/SABnzbd-${SABNZBD_VERSION}-src.tar.gz")
MICROMAMBA=$(fetch "https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-linux-64" "micromamba-${MICROMAMBA_VERSION}")
PAR2_ZIP=$(fetch "https://github.com/animetosho/par2cmdline-turbo/releases/download/v${PAR2_VERSION}/par2cmdline-turbo-${PAR2_VERSION}-linux-amd64.zip")
UNRAR_TGZ=$(fetch "https://www.rarlab.com/rar/rarlinux-x64-${UNRAR_VERSION}.tar.gz")
SZ_TXZ=$(fetch "https://github.com/ip7z/7zip/releases/download/${SEVENZIP_TAG}/7z${SEVENZIP_VERSION}-linux-x64.tar.xz")
APPIMAGETOOL=$(fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage")
chmod +x "$MICROMAMBA" "$APPIMAGETOOL"

echo ">> Python ${PYTHON_VERSION} (conda-forge)"
PYROOT="$APPDIR/usr/python"
MAMBA_ROOT_PREFIX="$WORK/mamba" "$MICROMAMBA" create -y -q -p "$PYROOT" \
    -c conda-forge --override-channels "python=${PYTHON_VERSION}" openssl=3 libstdcxx pip
PY="$PYROOT/bin/python${PY_MM}"
PYLIB="$PYROOT/lib/python${PY_MM}"
# Trim parts SABnzbd does not need
rm -rf "$PYROOT"/{conda-meta,include,man,share,compiler_compat,x86_64-conda*} \
       "$PYROOT"/lib/{pkgconfig,cmake,tcl*,tk*,itcl*,thread*,sqlite3.*,libtcl*,libtk*} \
       "$PYROOT"/lib/*.a \
       "$PYLIB"/{test,idlelib,tkinter,turtledemo,ensurepip,config-*} \
       "$PYLIB"/lib-dynload/{_tkinter*,_test*,xxlimited*}
find "$PYROOT/bin" -mindepth 1 ! -name "python${PY_MM}" ! -name python3 ! -name python ! -name 'pip*' -exec rm -rf {} +
find "$PYROOT" -name __pycache__ -type d -prune -exec rm -rf {} +

echo ">> SABnzbd ${SABNZBD_VERSION}"
tar xzf "$SAB_TGZ" -C "$WORK"
SRC="$WORK/SABnzbd-${SABNZBD_VERSION}"
mkdir -p "$APPDIR/usr/share/sabnzbd"
cp -a "$SRC"/{SABnzbd.py,sabnzbd,interfaces,locale,email,icons,scripts,licenses} \
      "$SRC"/{COPYRIGHT.txt,GPL2.txt,GPL3.txt,LICENSE.txt,README.mkd} "$APPDIR/usr/share/sabnzbd/"

echo ">> Python dependencies"
SITE="$PYLIB/site-packages"
grep -vE '^\s*(notify2)\b' "$SRC/requirements.txt" > "$WORK/requirements.txt"
PLATFORMS=()
for t in manylinux1 manylinux2010 manylinux2014; do PLATFORMS+=(--platform "${t}_x86_64"); done
for i in $(seq 5 "$MAX_GLIBC_MINOR"); do PLATFORMS+=(--platform "manylinux_2_${i}_x86_64"); done
# sgmllib3k is sdist-only (pure Python): turn it into a wheel first
"$PY" -m pip wheel -q --disable-pip-version-check --no-deps -w "$WORK/wheels" sgmllib3k==1.0.0
"$PY" -m pip install -q --disable-pip-version-check --no-compile --upgrade \
    --target "$SITE" --find-links "$WORK/wheels" \
    --only-binary=:all: --implementation cp --python-version "$PY_MM" "${PLATFORMS[@]}" \
    -r "$WORK/requirements.txt"

echo ">> par2cmdline-turbo ${PAR2_VERSION}"
unzip -qo "$PAR2_ZIP" par2 -d "$APPDIR/usr/bin"

echo ">> unrar ${UNRAR_VERSION}"
tar xzf "$UNRAR_TGZ" -C "$WORK" rar/unrar rar/license.txt
# RARLAB's license only allows redistributing unrar unmodified, so the binary
# is shipped as-is. A wrapper points it at the bundled libstdc++ instead.
mkdir -p "$APPDIR/usr/lib/unrar"
install -m755 "$WORK/rar/unrar" "$APPDIR/usr/lib/unrar/unrar"
ln -s ../../python/lib/libstdc++.so.6 "$APPDIR/usr/lib/unrar/libstdc++.so.6"
ln -s ../../python/lib/libgcc_s.so.1 "$APPDIR/usr/lib/unrar/libgcc_s.so.1"
cat > "$APPDIR/usr/bin/unrar" <<'EOF'
#!/bin/sh
LIBDIR="$(dirname "$(readlink -f "$0")")/../lib/unrar"
LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$LIBDIR/unrar" "$@"
EOF
chmod +x "$APPDIR/usr/bin/unrar"
mkdir -p "$APPDIR/usr/share/licenses/unrar"
cp "$WORK/rar/license.txt" "$APPDIR/usr/share/licenses/unrar/"

echo ">> 7-Zip ${SEVENZIP_VERSION}"
mkdir -p "$WORK/7z"
tar xJf "$SZ_TXZ" -C "$WORK/7z"
install -m755 "$WORK/7z/7zzs" "$APPDIR/usr/bin/7zzs"
mkdir -p "$APPDIR/usr/share/licenses/7zip"
cp "$WORK/7z/License.txt" "$APPDIR/usr/share/licenses/7zip/"

echo ">> Strip debug info"
find "$PYROOT" -type f \( -name '*.so*' -o -path '*/bin/*' \) -print0 \
    | xargs -0 file | grep -E ':.*ELF.*not stripped' | cut -d: -f1 \
    | xargs -r strip --strip-unneeded

echo ">> Point C++ Python modules at the bundled libstdc++"
"$PY" -m pip install -q --disable-pip-version-check --target "$WORK/tools" patchelf
PATCHELF="$WORK/tools/bin/patchelf"
find "$SITE" -name '*.so' | while read -r so; do
    if objdump -p "$so" | grep -q 'NEEDED.*libstdc++'; then
        rel=$("$PY" -c 'import os,sys;print(os.path.relpath(sys.argv[1],os.path.dirname(sys.argv[2])))' "$PYROOT/lib" "$so")
        echo "   $so"
        "$PATCHELF" --set-rpath "\$ORIGIN/$rel" "$so"
    fi
done

# Don't ship pip in the final image
rm -rf "$SITE"/pip "$SITE"/pip-* "$SITE"/bin "$APPDIR"/usr/python/bin/pip*

echo ">> Precompile bytecode"
"$PY" -m compileall -q -j0 "$PYLIB" "$APPDIR/usr/share/sabnzbd" >/dev/null || true

echo ">> AppRun, desktop entry, icon"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
# SABnzbd AppImage launcher. All arguments are passed to SABnzbd.py
# (try: --help). Config defaults to ~/.sabnzbd, as with a normal install.
HERE="$(dirname "$(readlink -f "$0")")"
# Bundled unrar, par2 and 7zzs come first so SABnzbd always finds them
export PATH="$HERE/usr/bin:$PATH"
unset PYTHONHOME PYTHONPATH
export PYTHONNOUSERSITE=1
exec "$HERE/usr/python/bin/python3" -s "$HERE/usr/share/sabnzbd/SABnzbd.py" "$@"
EOF
chmod +x "$APPDIR/AppRun"

sed -e 's|^Exec=.*|Exec=SABnzbd --browser 1 %F|' "$SRC/linux/sabnzbd.desktop" > "$APPDIR/sabnzbd.desktop"
cp "$SRC/icons/logo-arrow.svg" "$APPDIR/sabnzbd.svg"
mkdir -p "$APPDIR/usr/share/metainfo"
cp "$SRC/linux/org.sabnzbd.sabnzbd.appdata.xml" "$APPDIR/usr/share/metainfo/" 2>/dev/null || true

echo ">> Checking glibc requirement of bundled binaries"
maxv=$(find "$APPDIR" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'file -b "$1" | grep -q ELF && objdump -T "$1"' _ {} \; 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -Vu | tail -1)
echo "   highest symbol version needed: $maxv"

echo ">> Building AppImage"
rm -f "$OUT"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUT"
# unrar must be byte-identical to RARLAB's release
cmp "$WORK/rar/unrar" "$APPDIR/usr/lib/unrar/unrar"
echo ">> Done: $OUT"
