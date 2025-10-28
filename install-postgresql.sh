#!/bin/bash

set -euxo pipefail

# --- Configuration ---
PREFIX="$HOME/local"
MAKEFLAGS="-j$(sysctl -n hw.ncpu)"

# Latest versions as of October 27, 2025
XXHASH_VERSION="v0.8.2"
LZ4_VERSION="v1.10.0"
LIBXML2_VERSION="2.13.5"
ICU4C_VERSION="release-77-1"
OSSP_UUID_VERSION="1.6.2"
LIBMD_VERSION="1.1.0"
POSTGRES_VERSION="REL_18_0"

# GitHub base URLs
XXHASH_URL="https://github.com/Cyan4973/xxHash/archive/refs/tags/${XXHASH_VERSION}.tar.gz"
LZ4_URL="https://github.com/lz4/lz4/archive/refs/tags/${LZ4_VERSION}.tar.gz"
LIBXML2_URL="https://github.com/GNOME/libxml2/archive/refs/tags/v${LIBXML2_VERSION}.tar.gz"
ICU4C_URL="https://github.com/unicode-org/icu/archive/refs/tags/${ICU4C_VERSION}.tar.gz"
OSSP_UUID_URL="https://github.com/rbtying/ossp-uuid/archive/refs/tags/v${OSSP_UUID_VERSION}.tar.gz"
LIBMD_URL="https://github.com/guillemj/libmd/archive/refs/tags/${LIBMD_VERSION}.tar.gz"
POSTGRES_URL="https://github.com/postgres/postgres/archive/refs/tags/${POSTGRES_VERSION}.tar.gz"

# --- Setup ---
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export CPPFLAGS="-I$PREFIX/include"
export CFLAGS="-O2 -g -I$PREFIX/include"
export CXXFLAGS="-O2 -g -I$PREFIX/include"

mkdir -p "$PREFIX" "$PREFIX/src"
cd "$PREFIX/src"

# --- Helper Functions ---
download_and_extract() {
    local url=$1
    local dir=$2
    local archive=$(basename "$url")

    if [ ! -f "$archive" ]; then
        curl -L# "$url" -o "$archive"
    fi

    if [ ! -d "$dir" ]; then
        tar -xzf "$archive"
    fi
}

build_autotools() {
    local dir=$1
    local configure_args=${2:-""}
    (
        cd "$dir"
        autoreconf -i
        ./configure --prefix="$PREFIX" \
            --enable-shared \
            --disable-static \
            --host=arm64-apple-darwin \
            "$configure_args"
        make "$MAKEFLAGS"
        make install
    )
}

if false; then

    # --- Build xxHash (required by lz4 bench) ---
    download_and_extract "$XXHASH_URL" "xxHash-${XXHASH_VERSION#v}"
    (
        cd "xxHash-${XXHASH_VERSION#v}"
        make PREFIX="$PREFIX" install
    )

    # --- Build lz4 ---
    download_and_extract "$LZ4_URL" "lz4-${LZ4_VERSION#v}"
    (
        cd "lz4-${LZ4_VERSION#v}"
        # Prevent bench build if xxHash is missing (but we just installed it)
        # Alternatively, skip bench entirely to avoid risk:
        make PREFIX="$PREFIX" install
    )

    # --- Build libmd ---
    download_and_extract "$LIBMD_URL" "libmd-${LIBMD_VERSION}"
    build_autotools "libmd-${LIBMD_VERSION}"

    # --- Build libxml2 ---
    download_and_extract "$LIBXML2_URL" "libxml2-${LIBXML2_VERSION}"
    build_autotools "libxml2-${LIBXML2_VERSION}" "--with-lzma=no"

    # --- Build ICU4C ---
    download_and_extract "$ICU4C_URL" "icu-${ICU4C_VERSION}"
    (
        cd "icu-${ICU4C_VERSION}/icu4c/source"
        ./configure --prefix="$PREFIX" \
            --enable-shared \
            --disable-static \
            --with-library-bits=64 \
            --build=arm64-apple-darwin
        make "$MAKEFLAGS"
        make install
    )

    # --- Build OSSP UUID ---
    download_and_extract "$OSSP_UUID_URL" "ossp-uuid-${OSSP_UUID_VERSION}"
    (
        cd "ossp-uuid-${OSSP_UUID_VERSION}"
        ./configure --prefix="$HOME/local" --includedir="$HOME/local/include/ossp" --without-perl --without-php --without-pgsql

        ./configure --prefix="$PREFIX" \
            --enable-shared \
            --disable-static \
            --mandir="$PREFIX/share/man"
        make "$MAKEFLAGS"
        make install
    )

fi

# --- Build PostgreSQL ---
download_and_extract "$POSTGRES_URL" "postgres-${POSTGRES_VERSION}"
(
    cd "postgres-${POSTGRES_VERSION}"
    ./configure --prefix="$PREFIX" \
        --with-openssl \
        --with-libxml \
        --with-icu \
        --with-uuid=ossp \
        --with-lz4 \
        --with-libmd \
        --enable-thread-safety \
        --with-includes="$PREFIX/include" \
        --with-libraries="$PREFIX/lib"
    make "$MAKEFLAGS" world
    make install-world
)

echo "✅ PostgreSQL and all dependencies installed to $PREFIX"
echo "💡 Add to your shell profile: export PATH=\"$PREFIX/bin:\$PATH\""
