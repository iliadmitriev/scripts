#!/bin/zsh

# Exit on error
set -e

# === Configuration ===
PREFIX="$HOME/local"
GNUPG_VERSION="2.5.13"
LIBGPG_ERROR_VERSION="1.56"
LIBGCRYPT_VERSION="1.11.2"
LIBASSUAN_VERSION="3.0.2"
LIBKSBA_VERSION="1.6.7"
NTBTLS_VERSION="0.3.2"
NPTH_VERSION="1.8"
PINENTRY_VERSION="1.3.2"

# === Environment setup ===
export PREFIX
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export LDFLAGS="-L$PREFIX/lib"
export CPPFLAGS="-I$PREFIX/include"
export CPPFLAGS="$CPPFLAGS -D_XOPEN_SOURCE_EXTENDED -DNCURSES_WIDECHAR"
export MAKEFLAGS="-j$(sysctl -n hw.ncpu)"

# Create prefix if needed
mkdir -p "$PREFIX"

# Temporary build directory
BUILD_DIR="$PREFIX/src"
# BUILD_DIR="$(mktemp -d)"
echo "Building in $BUILD_DIR"
cd "$BUILD_DIR"

# === Helper function ===
build_package() {
    local name=$1
    local version=$2
    local url_path=$3

    echo "=== Building $name $version ==="
    local tarball="${name}-${version}.tar.bz2"
    local url="https://gnupg.org/ftp/gcrypt/${url_path}/${tarball}"

    curl -# -L -O "$url"
    tar xjf "$tarball"
    cd "${name}-${version}"

    ./configure \
        --prefix="$PREFIX" \
        --enable-shared

    make
    make install

    cd "$BUILD_DIR"
    echo "=== $name installed ==="
    echo
}

# === Build dependencies in order ===

# 1. libgpg-error
build_package "libgpg-error" "$LIBGPG_ERROR_VERSION" "libgpg-error"

# 2. libgcrypt
echo "=== Building libgcrypt $LIBGCRYPT_VERSION ==="
curl -# -L -O "https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2"
tar xjf "libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2"
cd "libgcrypt-${LIBGCRYPT_VERSION}"
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --with-libgpg-error-prefix="$PREFIX"
make
make install
cd "$BUILD_DIR"
echo "=== libgcrypt installed ==="
echo

# 3. libassuan
build_package "libassuan" "$LIBASSUAN_VERSION" "libassuan"

# 4. libksba
build_package "libksba" "$LIBKSBA_VERSION" "libksba"

# 5. ntbtls
build_package "ntbtls" "$NTBTLS_VERSION" "ntbtls"

# 6. npth
build_package "npth" "$NPTH_VERSION" "npth"

# 7. pinentry
echo "=== Building pinentry $PINENTRY_VERSION ==="
curl -# -L -O "https://gnupg.org/ftp/gcrypt/pinentry/pinentry-${PINENTRY_VERSION}.tar.bz2"
tar xjf "pinentry-${PINENTRY_VERSION}.tar.bz2"
cd "pinentry-${PINENTRY_VERSION}"

./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --with-libgpg-error-prefix="$PREFIX" \
    --with-libassuan-prefix="$PREFIX" \
    --enable-pinentry-curses \
    --enable-pinentry-tty \
    --disable-pinentry-gtk2 \
    --disable-pinentry-gtk3 \
    --disable-pinentry-qt \
    --disable-pinentry-qt5 \
    --disable-pinentry-fltk

make
make install
cd "$BUILD_DIR"
echo "=== pinentry installed ==="
echo

# 8. gnupg
echo "=== Building GnuPG $GNUPG_VERSION ==="
curl -# -L -O "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-${GNUPG_VERSION}.tar.bz2"
tar xjf "gnupg-${GNUPG_VERSION}.tar.bz2"
cd "gnupg-${GNUPG_VERSION}"

./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --with-libgpg-error-prefix="$PREFIX" \
    --with-libgcrypt-prefix="$PREFIX" \
    --with-libassuan-prefix="$PREFIX" \
    --with-libksba-prefix="$PREFIX" \
    --with-ntbtls-prefix="$PREFIX" \
    --with-npth-prefix="$PREFIX"

make
make install
cd "$BUILD_DIR"
echo "=== GnuPG installed ==="
echo

# === Finalize ===
echo "✅ GnuPG and dependencies successfully installed to $PREFIX"
echo
echo "To use GnuPG, add this to your shell profile (~/.zshrc or ~/.bashrc):"
echo "  export PATH=\"$HOME/local/bin:\$PATH\""
echo
echo "To set pinentry-curses as default, run:"
echo "  echo \"pinentry-program $HOME/local/bin/pinentry-curses\" >> ~/.gnupg/gpg-agent.conf"
echo "  gpg-connect-agent reloadagent /bye"
echo
echo "Test with:"
echo "  $HOME/local/bin/gpg --version"

# Optional: clean up
# rm -rf "$BUILD_DIR"
