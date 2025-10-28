#!/usr/bin/env zsh -e

# Refactored wget2 build script for macOS M1 (arm64)
# Installs to $HOME/local
# Builds from source only, no Homebrew
#
# Notes:
# - autogen.sh is run where required (libpsl)
# - GNU mirror mirror.truenetwork.ru restored for faster downloads in some regions

set -euo pipefail

# --- Configuration ---
export PREFIX="${PREFIX:-$HOME/local}"
CPU_COUNT="${CPU_COUNT:-$(sysctl -n hw.ncpu)}"

# Tool/flags
export PATH="${PREFIX}/bin:${PATH}"
export PKG_CONFIG="${PREFIX}/bin/pkgconf"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
export CPPFLAGS="-I${PREFIX}/include"
export CFLAGS="-arch arm64"
export CXXFLAGS="-arch arm64"

# Ensure directories
mkdir -p "${PREFIX}/src" "${PREFIX}/bin" "${PREFIX}/lib" "${PREFIX}/include"
cd "${PREFIX}/src"

# --- Helper functions ---
log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

download() {
  local url="$1" out="$2"
  if [[ -f "${out}" ]]; then
    log "Found cached ${out}"
    return 0
  fi
  log "Downloading ${out} from ${url} ..."
  curl -# -L -o "${out}" "${url}" || err "Failed to download ${url}"
}

extract() {
  local archive="$1"
  log "Extracting ${archive} ..."
  case "${archive}" in
    *.tar.gz|*.tgz) tar -xzf "${archive}" ;;
    *.tar.xz)       tar -xJf "${archive}" ;;
    *.tar.bz2)      tar -xjf "${archive}" ;;
    *.zip)          unzip -q "${archive}" ;;
    *)              err "Unknown archive type: ${archive}" ;;
  esac
}

build_autotools() {
  local srcdir="$1" cfg_args=("${(@s: :)2}")
  log "Building (autotools) ${srcdir}"
  pushd "${srcdir}" >/dev/null
  if [[ ! -f "./configure" ]]; then
    log "Running autoreconf -i"
    autoreconf -i
  fi
  log "./configure --prefix=${PREFIX} ${cfg_args[*]}"
  ./configure --prefix="${PREFIX}" --enable-shared --disable-static "${cfg_args[@]}"
  log "make -j${CPU_COUNT}"
  make -j"${CPU_COUNT}"
  make install
  popd >/dev/null
}

build_configure() {
  local srcdir="$1" cfg_args=("${(@s: :)2}")
  log "Building (configure) ${srcdir}"
  pushd "${srcdir}" >/dev/null
  ./configure --prefix="${PREFIX}" "${cfg_args[@]}"
  make -j"${CPU_COUNT}"
  make install
  popd >/dev/null
}

build_make_prefix() {
  local srcdir="$1" install_target="${2:-install}" install_prefix="${3:-${PREFIX}}"
  log "Building (make-prefix) ${srcdir}"
  pushd "${srcdir}" >/dev/null
  make -j"${CPU_COUNT}"
  make "${install_target}" PREFIX="${install_prefix}"
  popd >/dev/null
}

build_package() {
  local name="$1"
  local version="$2"
  local archive="$3"
  local url="$4"
  local checkpath="$5"
  local method="$6"
  local cfgargs="$7"
  local pre_cmd="$8"
  local post_cmd="$9"

  if [[ -n "${checkpath}" && -f "${checkpath}" ]]; then
    log "${name} ${version}: already present at ${checkpath}, skipping"
    return 0
  fi

  local out="${archive##*/}"
  download "${url}" "${out}"
  extract "${out}"

  local srcdir_guess1="${name}-${version}"
  local srcdir=""
  if [[ -d "${srcdir_guess1}" ]]; then
    srcdir="${srcdir_guess1}"
  else
    # Best-effort discovery: top-level dir in archive, or a sensible glob
    srcdir="$(tar -tf "${out}" 2>/dev/null | head -1 | cut -f1 -d"/")"
    if [[ -z "${srcdir}" || ! -d "${srcdir}" ]]; then
      local match=(./"${name}"* "${name}-${version}"* ./*"${name}"* )
      for m in "${match[@]}"; do
        [[ -d "${m}" ]] && { srcdir="${m}"; break; }
      done
      if [[ -z "${srcdir}" ]]; then
        err "Could not determine srcdir for ${out}"
      fi
    fi
  fi

  log "Using source directory: ${srcdir}"

  if [[ -n "${pre_cmd}" ]]; then
    log "Running pre-build command for ${name}"
    (cd "${srcdir}" && eval "${pre_cmd}")
  fi

  case "${method}" in
    autotools) build_autotools "${srcdir}" "${cfgargs}" ;;
    configure) build_configure "${srcdir}" "${cfgargs}" ;;
    make-prefix) build_make_prefix "${srcdir}" "install" "${PREFIX}" ;;
    custom)
      if [[ -n "${cfgargs}" ]]; then
        log "Running custom build command: ${cfgargs}"
        (cd "${srcdir}" && eval "${cfgargs}")
      else
        err "Package ${name} specified 'custom' but no command provided"
      fi
      ;;
    *) err "Unknown build method '${method}' for ${name}" ;;
  esac

  if [[ -n "${post_cmd}" ]]; then
    log "Running post-build command for ${name}"
    (cd "${srcdir}" && eval "${post_cmd}")
  fi

  log "${name} ${version}: build finished"
}

# --- Packages list ---
# Format per line:
# name|version|archive_filename|download_url|check_path|method|cfgargs|pre_cmd|post_cmd
read -r -d '' PACKAGES <<'PACK_EOF' || true
xz|5.8.1|xz-5.8.1.tar.gz|https://github.com/tukaani-project/xz/archive/refs/tags/v5.8.1.tar.gz|${PREFIX}/lib/liblzma.dylib|autotools|--disable-doc||
bzip2|1.0.8|bzip2-1.0.8.tar.gz|https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz|${PREFIX}/lib/libbz2.a|make-prefix|||
libidn2|2.3.8|libidn2-2.3.8.tar.gz|https://mirror.truenetwork.ru/gnu/libidn/libidn2-2.3.8.tar.gz|${PREFIX}/lib/libidn2.dylib|configure|||
libpsl|0.21.5|libpsl-0.21.5.tar.gz|https://github.com/rockdaboot/libpsl/archive/refs/tags/0.21.5.tar.gz|${PREFIX}/lib/libpsl.dylib|configure||curl -# -o list/public_suffix_list.dat https://publicsuffix.org/list/public_suffix_list.dat && ./autogen.sh
nghttp2|1.67.1|nghttp2-1.67.1.tar.gz|https://github.com/nghttp2/nghttp2/archive/refs/tags/v1.67.1.tar.gz|${PREFIX}/lib/libnghttp2.dylib|autotools|--enable-lib-only||
gmp|6.3.0|gmp-6.3.0.tar.xz|https://mirror.truenetwork.ru/gnu/gmp/gmp-6.3.0.tar.xz|${PREFIX}/lib/libgmp.dylib|configure|||
nettle|3.10.2|nettle-3.10.2.tar.gz|https://mirror.truenetwork.ru/gnu/nettle/nettle-3.10.2.tar.gz|${PREFIX}/lib/libnettle.dylib|autotools|||
libtasn1|4.20.0|libtasn1-4.20.0.tar.gz|https://mirror.truenetwork.ru/gnu/libtasn1/libtasn1-4.20.0.tar.gz|${PREFIX}/lib/libtasn1.dylib|configure|||
libffi|3.5.2|libffi-3.5.2.tar.gz|https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz|${PREFIX}/lib/libffi.dylib|configure|||
p11-kit|0.25.10|p11-kit-0.25.10.tar.xz|https://github.com/p11-glue/p11-kit/releases/download/0.25.10/p11-kit-0.25.10.tar.xz|${PREFIX}/lib/libp11-kit.dylib|configure|--with-trust-paths=${PREFIX}/etc/ssl/certs||
gpgme|2.0.1|gpgme-2.0.1.tar.bz2|https://www.gnupg.org/ftp/gcrypt/gpgme/gpgme-2.0.1.tar.bz2|${PREFIX}/lib/libgpgme.dylib|configure|||
libevent|2.1.12|libevent-2.1.12-stable.tar.gz|https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz|${PREFIX}/lib/libevent.dylib|configure|||
unbound|1.24.1|unbound-1.24.1.tar.gz|https://nlnetlabs.nl/downloads/unbound/unbound-1.24.1.tar.gz|${PREFIX}/lib/libunbound.dylib|configure|--with-ssl=${PREFIX} --with-libnghttp2=${PREFIX} --with-libexpat=${PREFIX} --with-libevent=${PREFIX}||
gnutls|3.8.10|gnutls-3.8.10.tar.xz|https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.10.tar.xz|${PREFIX}/lib/libgnutls.dylib|autotools|--with-included-libtasn1 --with-p11-kit --disable-doc||
wget2|2.2.0|wget2-2.2.0.tar.gz|https://mirror.truenetwork.ru/gnu/wget/wget2-2.2.0.tar.gz|${PREFIX}/bin/wget2|configure|--with-lzma --with-bzip2 --with-gnutls --with-libidn2 --with-libpsl --with-nghttp2 --with-libintl-prefix=${PREFIX}||
PACK_EOF

# --- Main loop: parse PACKAGES and build ---
log "Beginning build of packages to ${PREFIX}"
while IFS='|' read -r name version archive url checkpath method cfgargs pre_cmd post_cmd; do
  [[ -z "${name}" ]] && continue
  # Expand variables (like ${PREFIX}) in checkpath/pre/post/cfgargs
  eval "checkpath_expanded=\"${checkpath}\""
  eval "pre_cmd_expanded=\"${pre_cmd}\""
  eval "post_cmd_expanded=\"${post_cmd}\""
  eval "cfgargs_expanded=\"${cfgargs}\""

  build_package "${name}" "${version}" "${archive}" "${url}" "${checkpath_expanded}" "${method}" "${cfgargs_expanded}" "${pre_cmd_expanded}" "${post_cmd_expanded}"
done <<< "${PACKAGES}"

log "All dependency builds completed. Verifying wget2..."

if [[ -f "${PREFIX}/bin/wget2" ]]; then
  log "wget2 installation complete: ${PREFIX}/bin/wget2"
else
  err "wget2 binary not found at ${PREFIX}/bin/wget2"
fi

log "Don't forget to add ${PREFIX}/bin to your PATH (if not already present)"
