#!/bin/zsh

set -e

# === Configuration: centralized versions (as of October 26, 2025) ===
PREFIX="$HOME/local"

# Source versions (latest stable as of 2025-10-26)
M4_VERSION="1.4.20"
AUTOCONF_VERSION="2.72"
AUTOMAKE_VERSION="1.18"
LIBTOOL_VERSION="2.5.4"
GENGETOPT_VERSION="2.23"
PKGCONF_VERSION="2.5.1"

# === Environment setup ===
export PREFIX
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export LDFLAGS="-L$PREFIX/lib"
export CPPFLAGS="-I$PREFIX/include"
export MAKEFLAGS="-j$(sysctl -n hw.ncpu)"

mkdir -p "$PREFIX"

# BUILD_DIR="$(mktemp -d)"
BUILD_DIR="$PREFIX/src"
echo "Building in $BUILD_DIR"
cd "$BUILD_DIR"

# === Helper: build from tarball (GNU/official) ===
build_from_tarball() {
    local name=$1
    local version=$2
    local url=$3
    local tarball="${name}-${version}.tar.xz"

    echo "=== Building $name $version ==="
    curl -# -L -O "$url/$tarball"
    tar xf "$tarball"
    cd "${name}-${version}"

    ./configure --prefix="$PREFIX"
    make
    make install

    cd "$BUILD_DIR"
    echo "=== $name installed ==="
    echo
}

# === Helper: build from GitHub release ===
build_from_github() {
    local repo=$1
    local version=$2
    local name=$3
    local tarball="${name}-${version}.tar.gz"
    local url="https://github.com/${repo}/archive/refs/tags/${name}-${version}.tar.gz"

    echo ${url}

    echo "=== Building $name $version from GitHub ==="
    curl -# -L -o "$tarball" "$url"
    tar xzf "$tarball"
    cd "${name}-${name}-${version}"

    # Assume autoreconf is needed
    autoreconf -fi
    ./configure --prefix="$PREFIX"

    make
    make install

    cd "$BUILD_DIR"
    echo "=== $name installed ==="
    echo
}

# === 1. m4 (required by autoconf) ===
build_from_tarball "m4" "$M4_VERSION" "https://ftp.gnu.org/gnu/m4"

# === 2. autoconf ===
build_from_tarball "autoconf" "$AUTOCONF_VERSION" "https://ftp.gnu.org/gnu/autoconf"

# === 3. automake ===
build_from_tarball "automake" "$AUTOMAKE_VERSION" "https://ftp.gnu.org/gnu/automake"

# === 4. libtool ===
build_from_tarball "libtool" "$LIBTOOL_VERSION" "https://ftp.gnu.org/gnu/libtool"

# === 5. gengetopt (from GNU Savannah) ===
build_from_tarball "gengetopt" "$GENGETOPT_VERSION" "https://ftp.gnu.org/gnu/gengetopt"

# === 6. pkgconf (from GitHub) ===
build_from_github "pkgconf/pkgconf" "$PKGCONF_VERSION" "pkgconf"

# === Finalize ===
echo "✅ Autotools suite installed to $PREFIX"
echo
echo "Add to your shell profile (~/.zshrc):"
echo "  export PATH=\"$HOME/local/bin:\$PATH\""
echo "  export PKG_CONFIG_PATH=\"$HOME/local/lib/pkgconfig:\$HOME/local/share/pkgconfig\""
echo
echo "Test with:"
echo "  autoconf --version"
echo "  automake --version"
echo "  libtool --version"
echo "  pkgconf --version"
echo "  gengetopt --version"

# Optional: cleanup
# rm -rf "$BUILD_DIR"
