#!/bin/zsh -e

# wget2 build script for macOS M1 (arm64)
# Installs to $HOME/local
# Strictly no Homebrew, builds from source only

set -e # Exit on error

# --- Configuration ---
export PREFIX="$HOME/local"
export CPU_COUNT=$(sysctl -n hw.ncpu)

# Latest stable versions as of October 28, 2025
# Collected in one place per requirement
declare -A VERSIONS=(
    [liblzma]="5.8.1"
    [libbz2]="1.0.8"
    [libgnutls]="3.8.10"
    [libidn2]="2.3.8"
    [libpsl]="0.21.5"
    [libnghttp2]="1.67.1"
    [libhsts]="0.1.0"
    [wget2]="2.2.0"
    [nettle]="3.10.2"
    [gmplib]="6.3.0"
    [p11_kit]="0.25.10"
    [gpgme]="2.0.1"
    [libtasn1]="4.20.0"
    [libffi]="3.5.2"
    [libevent]="2.1.12"
    [libunbound]="1.24.1"
)

# --- Helper functions ---
download_and_extract() {
    local repo="$1"
    local version="$2"
    local name="$3"
    local tarball="${name}-${version}.tar.gz"
    local url="https://github.com/${repo}/archive/refs/tags/v${version}.tar.gz"

    if [[ ! -f "${tarball}" ]]; then
        echo "Downloading ${name} ${version} at ${url} ..."
        curl -# -L -o "${tarball}" "${url}"
    fi

    if [[ ! -d "${name}-${version}" ]]; then
        echo "Extracting ${name} ${version}..."
        tar -xzf "${tarball}"
        # rm "${tarball}"
    fi
}

build_autotools_project() {
    local name="$1"
    local version="$2"
    local extra_configure_args=("${@:3}")

    local build_dir="${name}-${version}"
    echo "Building ${name} ${version}..."
    cd "${build_dir}"

    if [[ ! -f "configure" ]]; then
        echo "Configuring ${name}..."
        autoreconf -i
    fi

    if [[ ! -f "Makefile" ]]; then
        echo "Configuring ${name}..."
        ./configure \
            --prefix="${PREFIX}" \
            --enable-shared \
            --disable-static \
            "${extra_configure_args[@]}"
    fi

    echo "Building ${name}..."
    make -j"${CPU_COUNT}"
    make install
    cd ..
}

# --- Setup ---
export PATH="${PREFIX}/bin:$PATH"
export PKG_CONFIG="${PREFIX}/bin/pkgconf"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
export CPPFLAGS="-I${PREFIX}/include"
export CFLAGS="-arch arm64"
export CXXFLAGS="-arch arm64"

mkdir -p "${PREFIX}/src"
cd "${PREFIX}/src"

# --- Build dependencies ---
# liblzma (xz)
if [[ ! -f "${PREFIX}/lib/liblzma.dylib" ]]; then
    download_and_extract "tukaani-project/xz" "${VERSIONS[liblzma]}" "xz"
    build_autotools_project "xz" "${VERSIONS[liblzma]}" \
        --disable-doc
fi

# libbz2
if [[ ! -f "${PREFIX}/lib/libbz2.a" ]]; then
    echo "Downloading libbz2 ${VERSIONS[libbz2]}..."
    curl -# -L -o "bzip2-${VERSIONS[libbz2]}.tar.gz" "https://sourceware.org/pub/bzip2/bzip2-${VERSIONS[libbz2]}.tar.gz"

    download_and_extract "kyz/libbz2" "${VERSIONS[libbz2]}" "bzip2"
    cd "bzip2-${VERSIONS[libbz2]}"
    echo "Building libbz2..."
    make -j"${CPU_COUNT}" install PREFIX="${PREFIX}"
    cd ..
fi

# libidn2
# https://mirror.truenetwork.ru/gnu/libidn/libidn2-2.3.8.tar.gz
if [[ ! -f "${PREFIX}/lib/libidn2.dylib" ]]; then
    echo "Downloading libidn2 ${VERSIONS[libidn2]}..."
    curl -# -L -o "libidn2-${VERSIONS[libidn2]}.tar.gz" "https://mirror.truenetwork.ru/gnu/libidn/libidn2-${VERSIONS[libidn2]}.tar.gz"

    download_and_extract "rockdaboot/libidn2" "${VERSIONS[libidn2]}" "libidn2"
    cd "libidn2-${VERSIONS[libidn2]}"
    echo "Building libidn2..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libpsl
if [[ ! -f "${PREFIX}/lib/libpsl.dylib" ]]; then
    echo "Downloading libpsl ${VERSIONS[libpsl]}..."
    curl -# -L -o "libpsl-${VERSIONS[libpsl]}.tar.gz" "https://github.com/rockdaboot/libpsl/archive/refs/tags/${VERSIONS[libpsl]}.tar.gz"

    echo "Extracting libpsl-${VERSIONS[libpsl]}..."
    tar -xzf "libpsl-${VERSIONS[libpsl]}.tar.gz"

    cd "libpsl-${VERSIONS[libpsl]}"
    echo "Building libpsl..."
    echo "Downloading public_suffix_list.dat..."
    curl -# -o list/public_suffix_list.dat https://publicsuffix.org/list/public_suffix_list.dat
    ./autogen.sh
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libnghttp2
if [[ ! -f "${PREFIX}/lib/libnghttp2.dylib" ]]; then
    download_and_extract "nghttp2/nghttp2" "${VERSIONS[libnghttp2]}" "nghttp2"
    build_autotools_project "nghttp2" "${VERSIONS[libnghttp2]}" \
        --enable-lib-only
fi

# libhsts
if false && [[ ! -f "${PREFIX}/lib/libhsts.dylib" ]]; then
    echo "Downloading libhsts ${VERSIONS[libhsts]}..."
    curl -# -L -o "libhsts-${VERSIONS[libhsts]}.tar.gz" "https://gitlab.com/rockdaboot/libhsts/-/archive/libhsts-${VERSIONS[libhsts]}/libhsts-libhsts-${VERSIONS[libhsts]}.tar.gz"
    echo "Extracting libhsts-${VERSIONS[libhsts]}..."
    tar -xzf "libhsts-${VERSIONS[libhsts]}.tar.gz"

    cd "libhsts-libhsts-${VERSIONS[libhsts]}"

    echo "Building libhsts..."
    ./autogen.sh
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..

fi

# gmplib
if [[ ! -f "${PREFIX}/lib/libgmp.dylib" ]]; then
    # https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz
    # https://mirror.truenetwork.ru/gnu/gmp/gmp-6.3.0.tar.xz
    #
    echo "Downloading gmplib ${VERSIONS[gmplib]}..."
    curl -# -L -o "gmp-${VERSIONS[gmplib]}.tar.xz" "https://mirror.truenetwork.ru/gnu/gmp/gmp-${VERSIONS[gmplib]}.tar.xz"

    echo "Extracting gmp-${VERSIONS[gmplib]}..."
    tar -xJf "gmp-${VERSIONS[gmplib]}.tar.xz"

    cd "gmp-${VERSIONS[gmplib]}"
    echo "Building gmplib..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# nettle
if [[ ! -f "${PREFIX}/lib/libnettle.dylib" ]]; then
    # https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz
    # https://mirror.truenetwork.ru/gnu/nettle/nettle-3.10.2.tar.gz

    echo "Downloading nettle ${VERSIONS[nettle]}..."
    curl -# -L -o "nettle-${VERSIONS[nettle]}.tar.gz" "https://mirror.truenetwork.ru/gnu/nettle/nettle-${VERSIONS[nettle]}.tar.gz"

    echo "Extracting nettle-${VERSIONS[nettle]}..."
    tar -xzf "nettle-${VERSIONS[nettle]}.tar.gz"

    cd "nettle-${VERSIONS[nettle]}"
    echo "Building nettle..."
    autoreconf -i
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libtasn1
# https://mirror.truenetwork.ru/gnu/libtasn1/libtasn1-4.20.0.tar.gz

if [[ ! -f "${PREFIX}/lib/libtasn1.dylib" ]]; then
    echo "Downloading libtasn1 ${VERSIONS[libtasn1]}..."
    curl -# -L -o "libtasn1-${VERSIONS[libtasn1]}.tar.gz" "https://mirror.truenetwork.ru/gnu/libtasn1/libtasn1-${VERSIONS[libtasn1]}.tar.gz"

    echo "Extracting libtasn1-${VERSIONS[libtasn1]}..."
    tar -xzf "libtasn1-${VERSIONS[libtasn1]}.tar.gz"

    cd "libtasn1-${VERSIONS[libtasn1]}"
    echo "Building libtasn1..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libffi
# https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz

if [[ ! -f "${PREFIX}/lib/libffi.dylib" ]]; then
    echo "Downloading libffi ${VERSIONS[libffi]}..."
    curl -# -L -o "libffi-${VERSIONS[libffi]}.tar.gz" "https://github.com/libffi/libffi/releases/download/v${VERSIONS[libffi]}/libffi-${VERSIONS[libffi]}.tar.gz"

    echo "Extracting libffi-${VERSIONS[libffi]}..."
    tar -xzf "libffi-${VERSIONS[libffi]}.tar.gz"

    cd "libffi-${VERSIONS[libffi]}"
    echo "Building libffi..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# p11-kit
# https://github.com/p11-glue/p11-kit/releases/download/0.25.10/p11-kit-0.25.10.tar.xz
if [[ ! -f "${PREFIX}/lib/libp11-kit.dylib" ]]; then
    echo "Downloading p11-kit ${VERSIONS[p11_kit]}..."
    curl -# -L -o "p11-kit-${VERSIONS[p11_kit]}.tar.xz" "https://github.com/p11-glue/p11-kit/releases/download/${VERSIONS[p11_kit]}/p11-kit-${VERSIONS[p11_kit]}.tar.xz"

    echo "Extracting p11-kit-${VERSIONS[p11_kit]}..."
    tar -xJf "p11-kit-${VERSIONS[p11_kit]}.tar.xz"

    cd "p11-kit-${VERSIONS[p11_kit]}"
    echo "Building p11-kit..."
    ./configure --prefix="${PREFIX}" --with-trust-paths=$HOME/local/etc/ssl/certs
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# gpgme
# https://www.gnupg.org/ftp/gcrypt/gpgme/gpgme-2.0.1.tar.bz2

if [[ ! -f "${PREFIX}/lib/libgpgme.dylib" ]]; then
    echo "Downloading gpgme ${VERSIONS[gpgme]}..."
    curl -# -L -o "gpgme-${VERSIONS[gpgme]}.tar.bz2" "https://www.gnupg.org/ftp/gcrypt/gpgme/gpgme-${VERSIONS[gpgme]}.tar.bz2"

    echo "Extracting gpgme-${VERSIONS[gpgme]}..."
    tar -xjf "gpgme-${VERSIONS[gpgme]}.tar.bz2"

    cd "gpgme-${VERSIONS[gpgme]}"
    echo "Building gpgme..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libevent
# https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz

if [[ ! -f "${PREFIX}/lib/libevent.dylib" ]]; then
    echo "Downloading libevent ${VERSIONS[libevent]}..."
    curl -# -L -o "libevent-${VERSIONS[libevent]}-stable.tar.gz" "https://github.com/libevent/libevent/releases/download/release-${VERSIONS[libevent]}-stable/libevent-${VERSIONS[libevent]}-stable.tar.gz"

    echo "Extracting libevent-${VERSIONS[libevent]}..."
    tar -xzf "libevent-${VERSIONS[libevent]}-stable.tar.gz"

    cd "libevent-${VERSIONS[libevent]}-stable"
    echo "Building libevent..."
    ./configure --prefix="${PREFIX}"
    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libunbound
# https://nlnetlabs.nl/downloads/unbound/unbound-1.24.1.tar.gz

if [[ ! -f "${PREFIX}/lib/libunbound.dylib" ]]; then
    echo "Downloading libunbound ${VERSIONS[libunbound]}..."
    curl -# -L -o "unbound-${VERSIONS[libunbound]}.tar.gz" "https://nlnetlabs.nl/downloads/unbound/unbound-${VERSIONS[libunbound]}.tar.gz"

    echo "Extracting unbound-${VERSIONS[libunbound]}..."
    tar -xzf "unbound-${VERSIONS[libunbound]}.tar.gz"

    cd "unbound-${VERSIONS[libunbound]}"
    echo "Building unbound..."
    ./configure --prefix="${PREFIX}" \
        --with-ssl=$PREFIX \
        --with-libnghttp2=$PREFIX \
        --with-libexpat=$PREFIX \
        --with-libevent=$PREFIX

    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

# libgnutls (requires nettle, but we assume it's available via Xcode/macOS)
# If nettle isn't available, you may need to build it separately
if [[ ! -f "${PREFIX}/lib/libgnutls.dylib" ]]; then
    echo "Downloading libgnutls ${VERSIONS[libgnutls]}..."

    # https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.10.tar.xz

    curl -# -L -o "gnutls-${VERSIONS[libgnutls]}.tar.xz" "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-${VERSIONS[libgnutls]}.tar.xz"

    echo "Extracting gnutls-${VERSIONS[libgnutls]}..."
    tar -xzf "gnutls-${VERSIONS[libgnutls]}.tar.xz"

    # download_and_extract "gnutls/gnutls" "${VERSIONS[libgnutls]}" "gnutls"
    build_autotools_project "gnutls" "${VERSIONS[libgnutls]}" \
        --with-included-libtasn1 \
        --with-p11-kit \
        --disable-doc
fi

# --- Build wget2 ---
if [[ ! -f "${PREFIX}/bin/wget2" ]]; then
    # https://mirror.truenetwork.ru/gnu/wget/wget2-2.2.0.tar.gz

    echo "Downloading wget2 ${VERSIONS[wget2]}..."
    curl -# -L -o "wget2-${VERSIONS[wget2]}.tar.gz" "https://mirror.truenetwork.ru/gnu/wget/wget2-${VERSIONS[wget2]}.tar.gz"

    echo "Extracting wget2-${VERSIONS[wget2]}..."
    tar -xzf "wget2-${VERSIONS[wget2]}.tar.gz"

    # download_and_extract "rockdaboot/wget2" "${VERSIONS[wget2]}" "wget2"

    cd "wget2-${VERSIONS[wget2]}"
    echo "Building wget2..."

    # build_autotools_project "wget2" "${VERSIONS[wget2]}" \
    ./configure \
        --prefix="${PREFIX}" \
        --with-lzma \
        --with-bzip2 \
        --with-gnutls \
        --with-libidn2 \
        --with-libpsl \
        --with-nghttp2 \
        --with-libintl-prefix="${PREFIX}"

    make -j"${CPU_COUNT}"
    make install
    cd ..
fi

echo "wget2 installation complete!"
echo "Executable: ${PREFIX}/bin/wget2"
echo "Make sure to add ${PREFIX}/bin to your PATH"
