#!/bin/zsh

set -e

# === Versions (as of 2025-10-27) ===
GIT_VERSION="v2.51.1"       # https://github.com/git/git/releases
EXPAT_VERSION="R_2_7_3"     # https://github.com/libexpat/libexpat/releases (note: tag format)
PCRE2_VERSION="pcre2-10.47" # https://github.com/PhilipHazel/pcre2/releases

# === Configuration ===
PREFIX="$HOME/local"
export PREFIX
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export LDFLAGS="-L$PREFIX/lib -lintl"
export CPPFLAGS="-I$PREFIX/include"
export MAKEFLAGS="-j$(sysctl -n hw.ncpu)"

# Create prefix
mkdir -p "$PREFIX"

# Temporary build dir
# BUILD_DIR="$(mktemp -d)"
BUILD_DIR="${PREFIX}/src"
echo "Building in $BUILD_DIR"
cd "$BUILD_DIR"

# === 1. Build expat ===
# Note: expat uses autoconf but requires autoreconf on some systems
build_expat() {
    echo "=== Building expat ($EXPAT_VERSION) ==="
    local tarball="expat.tar.gz"
    curl -# -L -o "$tarball" "https://github.com/libexpat/libexpat/archive/refs/tags/${EXPAT_VERSION}.tar.gz"
    tar xzf "$tarball"
    cd libexpat-${EXPAT_VERSION}/expat

    # Generate configure if needed (GitHub tarballs may lack it)
    if [ ! -f configure ]; then
        autoreconf -fi
    fi

    ./configure --prefix="$PREFIX" --enable-shared
    make
    make install

    cd "$BUILD_DIR"
    echo "=== expat installed ==="
    echo
}

# === 2. Build pcre2 ===
build_pcre2() {
    echo "=== Building pcre2 ($PCRE2_VERSION) ==="
    local tarball="pcre2.tar.gz"
    curl -# -L -o "$tarball" "https://github.com/PhilipHazel/pcre2/archive/refs/tags/${PCRE2_VERSION}.tar.gz"
    tar xzf "$tarball"
    cd pcre2-${PCRE2_VERSION}

    # Generate configure
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    ./configure --prefix="$PREFIX" --enable-shared --enable-pcre2-16 --enable-pcre2-32
    make
    make install

    cd "$BUILD_DIR"
    echo "=== pcre2 installed ==="
    echo
}

# === Build dependencies ===
build_expat
build_pcre2

# === 3. Build Git ===
echo "=== Building Git ($GIT_VERSION) ==="
local tarball="git.tar.gz"
curl -# -L -o "$tarball" "https://github.com/git/git/archive/refs/tags/${GIT_VERSION}.tar.gz"
tar xzf "$tarball"
cd git-${GIT_VERSION#v}

autoreconf -fi
./configure --prefix="$PREFIX"
make

# NO_GETTEXT=0 # INSTALL_SYMLINKS=1 # NO_CURL=0 # NO_OPENSSL=0 \

make install

cd "$BUILD_DIR"
echo "=== Git installed ==="
echo

# === Final message ===
echo "✅ Git $GIT_VERSION and dependencies installed to $PREFIX"
echo
echo "Add to your shell profile (~/.zshrc):"
echo "  export PATH=\"$HOME/local/bin:\$PATH\""
echo
echo "Verify with:"
echo "  $HOME/local/bin/git --version"

# Optional: uncomment to clean up
# rm -rf "$BUILD_DIR"
