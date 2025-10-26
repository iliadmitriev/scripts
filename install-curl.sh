#!/bin/zsh
set -e

# === Centralized Versions (as of October 26, 2025) ===
PREFIX="$HOME/local"

# Core crypto & network
OPENSSL_VER="3.6.0"  # [[15],[16]]
NGTCP2_VER="1.17.0"  # [[23]]
NGHTTP3_VER="1.12.0" # [[25]]
NGHTTP2_VER="1.67.1" # [[21]]

# DNS & async
C_ARES_VER="1.34.5" # [[49],[50]]

# Compression
ZLIB_VER="1.3.1"   # [[65]]
ZSTD_VER="1.5.7"   # [[62]]
BROTLI_VER="1.1.0" # [[59]] (latest stable from GitHub)

# Internationalization & text
LIBICONV_VER="1.18"      # [[73]]
LIBUNISTRING_VER="1.4.1" # [[75]]
LIBIDN2_VER="2.3.8"      # [[39],[43]]
GETTEXT_VER="0.26"       # inferred from latest stable; 0.26.2 is latest as of late 2025 [[78]]

# SSH
LIBSSH2_VER="1.11.1" # [[29],[35]]

# Main
CURL_VER="8.16.0" # [[1],[9]]

# === Environment ===
export PREFIX
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export CPPFLAGS="-I$PREFIX/include"
export CFLAGS="-O2 -arch arm64"
export CXXFLAGS="-O2 -arch arm64"
export MACOSX_DEPLOYMENT_TARGET="11.0"
export MAKEFLAGS="-j$(sysctl -n hw.ncpu)"

# Create prefix
mkdir -p "$PREFIX"

# Temporary build dir
# BUILD_DIR="$(mktemp -d)"
BUILD_DIR="$PREFIX/src"
echo "Building in $BUILD_DIR"
cd "$BUILD_DIR"

# === Helper: build autotools project ===
build_autotools() {
    local name=$1 ver=$2 url=$3
    echo "=== Building $name $ver ==="
    local tarball="${name}-${ver}.tar.gz"
    curl -# -L -O "$url/$tarball"
    tar xzf "$tarball"
    cd "${name}-${ver}"
    ./configure --prefix="$PREFIX" --enable-shared
    make
    make install
    cd "$BUILD_DIR"
    echo "=== $name installed ==="
}

# === Helper: build CMake project (like Brotli) ===
build_cmake() {
    local repo=$1
    local version=$2
    local name=$3
    local tarball="${name}-v${version}.tar.gz"
    local url="https://github.com/${repo}/archive/refs/tags/v${version}.tar.gz"

    echo "=== Building $name $version via CMake ==="
    curl -# -L -o "$tarball" "$url"
    tar xzf "$tarball"
    cd "${name}-${version}"

    mkdir -p out
    cd out
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        ..
    cmake --build . --config Release --target install

    cd "$BUILD_DIR"
    echo "=== $name installed ==="
    echo
}

download_github() {
    local repo=$1
    local version=$2
    local name=$3
    local tarball="${name}-v${version}.tar.gz"
    local url="https://github.com/${repo}/archive/refs/tags/v${version}.tar.gz"
    echo "=== Download $name $version via github ==="
    curl -# -L -o "$tarball" "$url"
    tar xzf "$tarball"
}

# === 1. zlib (required by many) ===
build_autotools "zlib" "$ZLIB_VER" "https://zlib.net"

# === 2. libiconv ===
build_autotools "libiconv" "$LIBICONV_VER" "https://ftp.gnu.org/pub/gnu/libiconv"

# === 3. libunistring ===
build_autotools "libunistring" "$LIBUNISTRING_VER" "https://ftp.gnu.org/pub/gnu/libunistring"

# === 4. libidn2 ===
build_autotools "libidn2" "$LIBIDN2_VER" "https://ftp.gnu.org/pub/gnu/libidn"

# === 5. gettext ===
build_autotools "gettext" "$GETTEXT_VER" "https://ftp.gnu.org/pub/gnu/gettext"

# === 6. c-ares ===
build_autotools "c-ares" "$C_ARES_VER" "https://github.com/c-ares/c-ares/releases/download/v${C_ARES_VER}"

# === 7. brotli ===
echo "=== Building brotli $BROTLI_VER ==="
build_cmake "google/brotli" "$BROTLI_VER" "brotli"

# === 8. zstd ===
echo "=== Building zstd $ZSTD_VER ==="

download_github "facebook/zstd" "$ZSTD_VER" "zstd"
cd "zstd-${ZSTD_VER}"
make install PREFIX=$PREFIX
cd "$BUILD_DIR"
echo "=== zstd installed ==="

# === 9. OpenSSL 3.6.0 ===
echo "=== Building OpenSSL $OPENSSL_VER ==="
curl -# -L -O "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"
tar xzf "openssl-$OPENSSL_VER.tar.gz"
cd "openssl-$OPENSSL_VER"
./Configure darwin64-arm64-cc shared enable-ec_nistp_64_gcc_128 \
    --prefix="$PREFIX" --openssldir="$PREFIX/etc/ssl"
make
make install_sw install_ssldirs
cd "$BUILD_DIR"
echo "=== OpenSSL installed ==="

# === 10. nghttp2 ===
build_autotools "nghttp2" "$NGHTTP2_VER" "https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VER"

# === 11. ngtcp2 (with crypto provider = OpenSSL) ===
echo "=== Building ngtcp2 $NGTCP2_VER ==="
download_github "ngtcp2/ngtcp2" "$NGTCP2_VER" "ngtcp2"
cd ngtcp2-"$NGTCP2_VER"
autoreconf -fi
./configure --prefix="$PREFIX" --enable-shared \
    --with-openssl="$PREFIX"
make
make install
cd "$BUILD_DIR"
echo "=== ngtcp2 installed ==="

# === 12. nghttp3 ===
echo "=== Building nghttp3 $NGHTTP3_VER ==="
curl -# -L -O https://github.com/ngtcp2/nghttp3/releases/download/v${NGHTTP3_VER}/nghttp3-${NGHTTP3_VER}.tar.gz
tar xzf nghttp3-${NGHTTP3_VER}.tar.gz
cd nghttp3-"$NGHTTP3_VER"
autoreconf -fi
./configure --prefix="$PREFIX" --enable-shared
make
make install
cd "$BUILD_DIR"
echo "=== nghttp3 installed ==="

# === 13. libssh2 ===
build_autotools "libssh2" "$LIBSSH2_VER" "https://www.libssh2.org/download"

# === 14. curl ===
echo "=== Building curl $CURL_VER ==="
curl -# -L -O "https://curl.se/download/curl-$CURL_VER.tar.gz"
tar xzf "curl-$CURL_VER.tar.gz"
cd "curl-$CURL_VER"

./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --with-openssl="$PREFIX" \
    --with-zlib="$PREFIX" \
    --with-brotli="$PREFIX" \
    --with-zstd="$PREFIX" \
    --with-libidn2="$PREFIX" \
    --with-libssh2="$PREFIX" \
    --with-cares="$PREFIX" \
    --with-nghttp2="$PREFIX" \
    --with-nghttp3="$PREFIX" \
    --with-ngtcp2="$PREFIX" \
    --enable-http2 \
    --enable-http3

make
make install
cd "$BUILD_DIR"
echo "=== curl installed ==="

# === Finalize ===
echo
echo "✅ curl $CURL_VER with HTTP/2 and HTTP/3 support installed to $PREFIX"
echo
echo "To use, add to your shell profile:"
echo "  export PATH=\"$HOME/local/bin:\$PATH\""
echo "  export PKG_CONFIG_PATH=\"$HOME/local/lib/pkgconfig\""
echo
echo "Test:"
echo "  $HOME/local/bin/curl --version"
echo "  $HOME/local/bin/curl --http3 https://cloudflare.com"
