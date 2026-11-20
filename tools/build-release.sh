#!/usr/bin/env bash
# Build release artifacts into dist/:
#   - C libraries: static and/or shared, per target
#   - C header (include/lutez.h)
#   - WASM module (wasm32-freestanding, zero imports)
#   - LICENSE / NOTICE / VERSION per package
#   - deterministic .tar.gz archives + SHA256SUMS
#
# Usage:
#   tools/build-release.sh                            # ALL targets x {static,dynamic} + wasm
#   tools/build-release.sh --targets native           # host, static + dynamic
#   tools/build-release.sh --targets native-static    # host, static only
#   tools/build-release.sh --targets x86_64-linux-dynamic
#   tools/build-release.sh --targets x86_64-linux-gnu,aarch64-macos-static,wasm
#   tools/build-release.sh --targets all --with-wasm  # explicit (same as default)
#   tools/build-release.sh --skip-tests --no-archive --optimize ReleaseFast
#
# Target syntax:
#   <zig-target>[-static|-dynamic]   no suffix = both variants
#   native[-static|-dynamic]         host triple from `zig cc -dumpmachine`
#   wasm | wasm32-freestanding       the WASM package
#   all                              every target below, both variants, plus wasm
#
# Matrix targets (--targets all):
#   x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl aarch64-linux-musl
#   x86_64-macos aarch64-macos x86_64-windows-gnu
#
# Output (dist/):
#   lutez-<version>-<target>-static/{include,lib,VERSION,LICENSE,NOTICE}
#   lutez-<version>-<target>-dynamic/{include,lib[,bin],VERSION,LICENSE,NOTICE}
#   lutez-<version>-wasm32-freestanding/{lutez.wasm,VERSION,LICENSE,NOTICE}
#   lutez-<version>-*.tar.gz
#   SHA256SUMS
#
# Requires Zig 0.17.0. Node is optional (WASM import-free smoke test).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/dist"
targets_spec="all"
optimize="ReleaseSafe"
run_tests=1
make_archives=1
clean=0
with_wasm=0

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "error: $*" >&2; exit 1; }
log() { printf '\n== %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --targets)      targets_spec="${2:-}"; shift 2 ;;
    --targets=*)    targets_spec="${1#*=}"; shift ;;
    --out)          out="${2:-}"; shift 2 ;;
    --out=*)        out="${1#*=}"; shift ;;
    --optimize)     optimize="${2:-}"; shift 2 ;;
    --optimize=*)   optimize="${1#*=}"; shift ;;
    --skip-tests)   run_tests=0; shift ;;
    --no-archive)   make_archives=0; shift ;;
    --with-wasm)    with_wasm=1; shift ;;
    --clean)        clean=1; shift ;;
    -h|--help)      usage 0 ;;
    *)              die "unknown argument: $1 (try --help)" ;;
  esac
done

command -v zig >/dev/null || die "zig 0.17.0 not found in PATH"
case "$optimize" in
  ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
  *) die "unsupported --optimize '$optimize' (ReleaseSafe|ReleaseFast|ReleaseSmall)" ;;
esac

version="$(sed -n 's/^[[:space:]]*\.version = "\([^"]*\)".*/\1/p' "$root/build.zig.zon" | head -1)"
[ -n "$version" ] || die "could not read .version from build.zig.zon"
types_version="$(sed -n 's/.*pub const version_string = "\([^"]*\)".*/\1/p' "$root/src/types.zig" | head -1)"
[ "$version" = "$types_version" ] || die "version mismatch: build.zig.zon=$version src/types.zig=$types_version"

native_triple() {
  local triple
  triple="$(zig cc -dumpmachine 2>/dev/null || true)"
  [ -n "$triple" ] || triple="$(uname -m)-unknown-$(uname -s | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$triple" | sed -E 's/\.[0-9]+(\.[0-9]+)*$//'
}

matrix_targets=(
  x86_64-linux-gnu
  aarch64-linux-gnu
  x86_64-linux-musl
  aarch64-linux-musl
  x86_64-macos
  aarch64-macos
  x86_64-windows-gnu
)

# Specs are parallel arrays: target (empty = native), variant (static|dynamic|wasm).
spec_targets=()
spec_variants=()
seen=$'\n'
add_spec() {
  local target="$1" variant="$2" key
  key="$target|$variant"
  case "$seen" in
    *$'\n'"$key"$'\n'*) return 0 ;;
  esac
  seen+="$key"$'\n'
  spec_targets+=("$target")
  spec_variants+=("$variant")
}

expand_token() {
  local tok="$1" t
  case "$tok" in
    "" | all)
      for t in "${matrix_targets[@]}"; do
        add_spec "$t" static
        add_spec "$t" dynamic
      done
      add_spec "" wasm
      ;;
    wasm | wasm32-freestanding)
      add_spec "" wasm
      ;;
    native)
      add_spec "" static
      add_spec "" dynamic
      ;;
    native-static)
      add_spec "" static
      ;;
    native-dynamic)
      add_spec "" dynamic
      ;;
    *-static)
      t="${tok%-static}"
      if [ "$t" = "all" ]; then
        for t in "${matrix_targets[@]}"; do add_spec "$t" static; done
      else
        add_spec "$t" static
      fi
      ;;
    *-dynamic)
      t="${tok%-dynamic}"
      if [ "$t" = "all" ]; then
        for t in "${matrix_targets[@]}"; do add_spec "$t" dynamic; done
      else
        add_spec "$t" dynamic
      fi
      ;;
    *)
      add_spec "$tok" static
      add_spec "$tok" dynamic
      ;;
  esac
}

IFS=',' read -r -a requested <<<"$targets_spec"
[ "${#requested[@]}" -gt 0 ] || die "empty --targets"
for tok in "${requested[@]}"; do
  expand_token "$tok"
done
[ "$with_wasm" -eq 1 ] && add_spec "" wasm

label_for() {
  local target="$1" variant="$2" base
  if [ "$variant" = "wasm" ]; then
    printf 'wasm32-freestanding\n'
    return 0
  fi
  if [ -z "$target" ]; then base="$(native_triple)"; else base="$target"; fi
  printf '%s-%s\n' "$base" "$variant" | sed 's#/#-#g; s/ /-/g'
}

archive_pkg() {
  local dir="$1" dest="$2" base
  base="$(basename "$dir")"
  if tar --version 2>/dev/null | head -1 | grep -q 'GNU tar'; then
    tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
      -C "$(dirname "$dir")" -cf - "$base" | gzip -9n >"$dest"
  else
    tar -C "$(dirname "$dir")" -cf - "$base" | gzip -9n >"$dest"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

[ "$clean" -eq 1 ] && rm -rf "$out"
mkdir -p "$out"

log "lutez $version: release build ($optimize)"
echo "   repo:      $root"
echo "   out:       $out"
echo "   targets:   $targets_spec"
echo "   variants:  ${#spec_targets[@]} package(s)"
echo "   zig:       $(zig version)"

if [ "$run_tests" -eq 1 ]; then
  log "pre-flight: zig build check"
  ( cd "$root" && zig build check )
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

packages=()

for i in "${!spec_targets[@]}"; do
  target="${spec_targets[$i]}"
  variant="${spec_variants[$i]}"
  label="$(label_for "$target" "$variant")"
  [ -n "$label" ] || die "could not derive a label for '${target:-native}' ($variant)"
  pkg="$out/lutez-$version-$label"
  prefix="$work/prefix-$label"

  if [ "$variant" = "wasm" ]; then
    log "wasm: wasm32-freestanding"
    ( cd "$root" && zig build wasm --prefix "$prefix" )
  else
    log "c/$variant: $label"
    args=(--prefix "$prefix" -Doptimize="$optimize")
    [ -n "$target" ] && args+=("-Dtarget=$target")
    ( cd "$root" && zig build "lib-$variant" "${args[@]}" )
  fi

  rm -rf "$pkg"
  mkdir -p "$pkg"
  if [ "$variant" = "wasm" ]; then
    [ -f "$prefix/lib/lutez.wasm" ] || die "$label: wasm build produced no lutez.wasm"
    cp "$prefix/lib/lutez.wasm" "$pkg/"
    cp "$root/js/lutez.mjs" "$pkg/"
    cp "$root/js/lutez.d.ts" "$pkg/"
  else
    [ -f "$prefix/include/lutez.h" ] || die "$label: missing include/lutez.h"
    cp -R "$prefix/include" "$pkg/"
    cp -R "$prefix/lib" "$pkg/"
    [ -d "$prefix/bin" ] && cp -R "$prefix/bin" "$pkg/"

    if [ "$variant" = "static" ]; then
      find "$pkg" \( -name '*.a' -o -name '*_static.lib' \) -type f | grep -q . \
        || die "$label: no static library in package"
    else
      find "$pkg" \( -name '*.so*' -o -name '*.dylib' -o -name '*.dll' \) | grep -q . \
        || die "$label: no shared library/DLL in package"
    fi
  fi
  cp "$root/LICENSE" "$root/NOTICE" "$pkg/"
  printf '%s\n' "$version" >"$pkg/VERSION"
  packages+=("$pkg")

  if [ "$variant" = "wasm" ] && command -v node >/dev/null; then
    log "wasm smoke test (zero imports, exports, ABI)"
    node "$root/test/wasm/smoke.mjs" "$pkg/lutez.wasm"
  fi
done

if [ "$make_archives" -eq 1 ]; then
  log "archives"
  for pkg in "${packages[@]}"; do
    archive="$pkg.tar.gz"
    rm -f "$archive"
    archive_pkg "$pkg" "$archive"
    echo "   $(basename "$archive")  $(du -h "$archive" | cut -f1)"
  done

  log "checksums"
  : >"$out/SHA256SUMS"
  for archive in "$out"/lutez-"$version"-*.tar.gz; do
    [ -e "$archive" ] || continue
    ( cd "$out" && sha256 "$(basename "$archive")" ) >>"$out/SHA256SUMS"
  done
  echo "   SHA256SUMS: $(wc -l <"$out/SHA256SUMS" | tr -d ' ') entries"
fi

log "done: ${#packages[@]} package(s) in $out"
for pkg in "${packages[@]}"; do
  echo "   $(basename "$pkg")/"
  ( cd "$pkg" && find . -mindepth 1 \( -type f -o -type l \) | sed 's|^\./|     |' | sort )
done
[ "$make_archives" -eq 1 ] && echo "   SHA256SUMS"
