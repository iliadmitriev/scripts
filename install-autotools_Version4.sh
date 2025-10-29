#!/usr/bin/env bash
#
# install-autotools.sh
#
# Build and install autotools toolchain from source on macOS M1 (arm64)
# Installs to $PREFIX (default: $HOME/local)
# No Homebrew required or used.
#
# Centralized versions (each version defined only once)
set -euo pipefail

# --- Versions (single source of truth) ---
M4_VERSION="1.4.20"
AUTOCONF_VERSION="2.72"
AUTOMAKE_VERSION="1.18"
LIBTOOL_VERSION="2.5.4"
GENGETOPT_VERSION="2.23"
PKGCONF_VERSION="2.5.1"
GETTEXT_VERSION="0.26"
TEXINFO_VERSION="7.2"

# --- Defaults / Configuration ---
PREFIX="${PREFIX:-$HOME/local}"
CPU_COUNT="${CPU_COUNT:-$(sysctl -n hw.ncpu)}"
MIRROR_GNU="${MIRROR_GNU:-https://mirror.truenetwork.ru/gnu}"

# CLI flags
FORCE=0 # if 1, build & install even if binaries already exist under PREFIX
VERBOSE=0

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --force       Force build/install even if binaries already exist under PREFIX
  -v, --verbose     Verbose logging
  -h, --help        Show this help and exit

Environment:
  PREFIX            Installation prefix (default: $HOME/local)
  MIRROR_GNU        GNU mirror base URL (default: $MIRROR_GNU)
  CPU_COUNT         Number of parallel make jobs (default: detected hw.ncpu)
EOF
}

# Parse args (simple)
while [[ $# -gt 0 ]]; do
  case "$1" in
  -f | --force)
    FORCE=1
    shift
    ;;
  -v | --verbose)
    VERBOSE=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1"
    usage
    exit 2
    ;;
  esac
done

export PATH="${PREFIX}/bin:${PATH}"
export PKG_CONFIG="${PREFIX}/bin/pkgconf"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
export CPPFLAGS="-I${PREFIX}/include"
export CFLAGS="-arch arm64"
export CXXFLAGS="-arch arm64"

mkdir -p "${PREFIX}/src" "${PREFIX}/bin" "${PREFIX}/lib" "${PREFIX}/include"
cd "${PREFIX}/src"

log() { [[ "${VERBOSE}" -eq 1 ]] && echo "==> $*"; }
info() { echo "==> $*"; }
err() {
  echo "ERROR: $*" >&2
  exit 1
}

download() {
  local url="$1" out="$2"
  if [[ -f "${out}" ]]; then
    info "Found cached ${out}"
    return 0
  fi
  info "Downloading ${out} from ${url} ..."
  curl -# -L -o "${out}" "${url}" || err "Failed to download ${url}"
}

extract() {
  local archive="$1"
  info "Extracting ${archive} ..."
  case "${archive}" in
  *.tar.gz | *.tgz) tar -xzf "${archive}" ;;
  *.tar.xz) tar -xJf "${archive}" ;;
  *.tar.bz2) tar -xjf "${archive}" ;;
  *.zip) unzip -q "${archive}" ;;
  *) err "Unknown archive type: ${archive}" ;;
  esac
}

build_autotools() {
  local srcdir="$1"
  local extra_cfg="$2"
  info "Building (autotools) ${srcdir}"
  pushd "${srcdir}" >/dev/null
  if [[ ! -f "./configure" ]]; then
    info "Running autoreconf -i"
    autoreconf -i
  fi
  info "./configure --prefix=${PREFIX} ${extra_cfg}"
  eval "./configure --prefix=\"${PREFIX}\" --enable-shared ${extra_cfg}"
  info "make -j${CPU_COUNT}"
  make -j"${CPU_COUNT}"
  make install
  popd >/dev/null
}

build_configure() {
  local srcdir="$1"
  local extra_cfg="$2"
  info "Building (configure) ${srcdir}"
  pushd "${srcdir}" >/dev/null
  info "./configure --prefix=${PREFIX} ${extra_cfg}"
  eval "./configure --prefix=\"${PREFIX}\" ${extra_cfg}"
  info "make -j${CPU_COUNT}"
  make -j"${CPU_COUNT}"
  make install
  popd >/dev/null
}

build_make_prefix() {
  local srcdir="$1"
  local install_target="${2:-install}"
  local install_prefix="${3:-${PREFIX}}"
  info "Building (make-prefix) ${srcdir}"
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

  # Expand checkpath (in case it contains vars like ${PREFIX})
  eval "local checkpath_expanded=\"${checkpath}\""

  if [[ -n "${checkpath_expanded}" && -f "${checkpath_expanded}" ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
      info "${name} ${version}: ${checkpath_expanded} exists but --force specified — will rebuild and reinstall"
    else
      info "${name} ${version}: already present at ${checkpath_expanded}, skipping"
      return 0
    fi
  fi

  local out="${archive##*/}"
  download "${url}" "${out}"
  extract "${out}"

  # Try to determine source directory
  local srcdir_guess="${name}-${version}"
  local srcdir=""
  if [[ -d "${srcdir_guess}" ]]; then
    srcdir="${srcdir_guess}"
  else
    srcdir="$(tar -tf "${out}" 2>/dev/null | head -1 | cut -f1 -d"/")" || true
    if [[ -z "${srcdir}" || ! -d "${srcdir}" ]]; then
      local matches=(./"${name}"* "${name}-${version}"* ./*"${name}"*)
      for m in "${matches[@]}"; do
        [[ -d "${m}" ]] && {
          srcdir="${m}"
          break
        }
      done
      if [[ -z "${srcdir}" ]]; then
        err "Could not determine source directory for ${out}"
      fi
    fi
  fi

  info "Using source directory: ${srcdir}"

  if [[ -n "${pre_cmd}" ]]; then
    info "Running pre-build command for ${name}"
    (cd "${srcdir}" && eval "${pre_cmd}")
  fi

  case "${method}" in
  autotools) build_autotools "${srcdir}" "${cfgargs}" ;;
  configure) build_configure "${srcdir}" "${cfgargs}" ;;
  make-prefix) build_make_prefix "${srcdir}" "install" "${PREFIX}" ;;
  custom)
    if [[ -n "${cfgargs}" ]]; then
      info "Running custom build command for ${name}"
      (cd "${srcdir}" && eval "${cfgargs}")
    else
      err "Package ${name} specified 'custom' but no command provided"
    fi
    ;;
  *) err "Unknown build method '${method}' for ${name}" ;;
  esac

  if [[ -n "${post_cmd}" ]]; then
    info "Running post-build command for ${name}"
    (cd "${srcdir}" && eval "${post_cmd}")
  fi

  info "${name} ${version}: build finished"
}

# --- Packages ---
# Format:
# name|version|archive_name|download_url|check_path|method|cfgargs|pre_cmd|post_cmd
read -r -d '' PACKAGES <<PACK_EOF || true
m4|${M4_VERSION}|m4-${M4_VERSION}.tar.xz|${MIRROR_GNU}/m4/m4-${M4_VERSION}.tar.xz|${PREFIX}/bin/m4|configure|||
pkgconf|${PKGCONF_VERSION}|pkgconf-${PKGCONF_VERSION}.tar.gz|https://github.com/pkgconf/pkgconf/archive/refs/tags/pkgconf-${PKGCONF_VERSION}.tar.gz|${PREFIX}/bin/pkgconf|autotools|||
gettext|${GETTEXT_VERSION}|gettext-${GETTEXT_VERSION}.tar.gz|${MIRROR_GNU}/gettext/gettext-${GETTEXT_VERSION}.tar.gz|${PREFIX}/bin/gettext|configure|||
autoconf|${AUTOCONF_VERSION}|autoconf-${AUTOCONF_VERSION}.tar.gz|${MIRROR_GNU}/autoconf/autoconf-${AUTOCONF_VERSION}.tar.gz|${PREFIX}/bin/autoconf|autotools|||
automake|${AUTOMAKE_VERSION}|automake-${AUTOMAKE_VERSION}.tar.gz|${MIRROR_GNU}/automake/automake-${AUTOMAKE_VERSION}.tar.gz|${PREFIX}/bin/automake|autotools|||
libtool|${LIBTOOL_VERSION}|libtool-${LIBTOOL_VERSION}.tar.xz|${MIRROR_GNU}/libtool/libtool-${LIBTOOL_VERSION}.tar.xz|${PREFIX}/bin/libtool|autotools|||
gengetopt|${GENGETOPT_VERSION}|gengetopt-${GENGETOPT_VERSION}.tar.xz|${MIRROR_GNU}/gengetopt/gengetopt-${GENGETOPT_VERSION}.tar.xz|${PREFIX}/bin/gengetopt|configure|||
texinfo|${TEXINFO_VERSION}|texinfo-${TEXINFO_VERSION}.tar.xz|${MIRROR_GNU}/texinfo/texinfo-${TEXINFO_VERSION}.tar.xz|${PREFIX}/bin/texi2any|configure|||
PACK_EOF

# --- Build loop ---
info "Starting build of autotools toolchain into ${PREFIX}"
if [[ "${FORCE}" -eq 1 ]]; then
  info "Force mode: ON (will build/install even if check paths already exist)"
fi

while IFS='|' read -r name version archive url checkpath method cfgargs pre_cmd post_cmd; do
  [[ -z "${name}" ]] && continue
  # Expand variables inside fields (so ${PREFIX} etc are interpolated)
  eval "checkpath_expanded=\"${checkpath}\""
  eval "cfgargs_expanded=\"${cfgargs}\""
  eval "pre_cmd_expanded=\"${pre_cmd}\""
  eval "post_cmd_expanded=\"${post_cmd}\""

  build_package "${name}" "${version}" "${archive}" "${url}" "${checkpath_expanded}" "${method}" "${cfgargs_expanded}" "${pre_cmd_expanded}" "${post_cmd_expanded}"
done <<<"${PACKAGES}"

info "All requested tools built. Verifying installed binaries..."

for bin in m4 autoconf automake libtool gengetopt pkgconf gettext texi2any; do
  if [[ -x "${PREFIX}/bin/${bin}" ]]; then
    info "OK: ${PREFIX}/bin/${bin}"
  else
    echo "MISSING: ${PREFIX}/bin/${bin}" >&2
  fi
done

info "Done. Please ensure ${PREFIX}/bin is in your PATH before building other projects."
