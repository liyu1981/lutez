#!/usr/bin/env bash
# Inspect/verify the pinned upstream lute submodule (upstream/lute).
#
#   tools/upstream.sh --status        # submodule HEAD, pin sources, drift between them
#   tools/upstream.sh --verify        # exit 1 if pin copies disagree (CI gate)
#   tools/upstream.sh --diff          # scoped-file diff pin..origin/master
#   tools/upstream.sh --bump <ref>    # checkout <ref> in the submodule (does not edit docs)
#
# The gitlink recorded by the submodule IS the pin. `src/types.zig:upstream_sha` and
# NOTICE mirror it for runtime reporting and human readers; --verify keeps them honest.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sub="$root/upstream/lute"
types="$root/src/types.zig"
notice="$root/NOTICE"

die() { echo "error: $*" >&2; exit 1; }
[ -d "$sub/.git" ] || [ -f "$sub/.git" ] || die "submodule missing; run: git submodule update --init --recursive"

sub_head="$(git -C "$sub" rev-parse HEAD)"
subj="$(git -C "$sub" log -1 --format=%s)"
subdate="$(git -C "$sub" log -1 --format=%ad --date=short)"
types_sha="$(sed -n 's/.*upstream_sha = "\([0-9a-f]\{40\}\)".*/\1/p' "$types" | head -1)"
notice_sha="$(grep -Eo '[0-9a-f]{40}' "$notice" | head -1 || true)"

case "${1:---status}" in
  --status)
    echo "submodule:  upstream/lute"
    echo "HEAD:       $sub_head ($subdate) $subj"
    echo "types.zig:  ${types_sha:-<missing>}"
    echo "NOTICE:     ${notice_sha:-<missing>}"
    if git -C "$sub" rev-parse --is-shallow-repository >/dev/null 2>&1 \
       && [ "$(git -C "$sub" rev-parse --is-shallow-repository)" = "true" ]; then
      echo "clone:      shallow (git -C upstream/lute fetch --unshallow for full history)"
    fi
    ;;
  --verify)
    [ -n "$types_sha" ] || die "no upstream_sha in $types"
    [ "$sub_head" = "$types_sha" ] || die "pin mismatch: submodule $sub_head != src/types.zig $types_sha"
    [ -z "$notice_sha" ] || [ "$sub_head" = "$notice_sha" ] || die "pin mismatch: submodule $sub_head != NOTICE $notice_sha"
    echo "pin ok: $sub_head"
    ;;
  --diff)
    git -C "$sub" fetch -q origin master || git -C "$sub" fetch -q --unshallow origin
    git -C "$sub" diff --stat "$sub_head" origin/master -- \
      lex ast parse html/entity.go html/escape.go html/escape_encode.go html/unesc_str.go
    ;;
  --bump)
    ref="${2:-}"; [ -n "$ref" ] || die "usage: $0 --bump <ref>"
    git -C "$sub" fetch origin "$ref" || git -C "$sub" fetch --unshallow origin
    git -C "$sub" checkout -q --detach FETCH_HEAD
    echo "submodule now at $(git -C "$sub" rev-parse HEAD)"
    echo "now: update src/types.zig upstream_sha + NOTICE, run --verify, then follow doc/UPSTREAM.md §4"
    ;;
  *)
    die "usage: $0 [--status|--verify|--diff|--bump <ref>]"
    ;;
esac
