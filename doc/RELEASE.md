# Release checklist

Toolchain: **Zig 0.17.0** (pinned). Node 24 is used for the WASM smoke test. Go 1.26+ and
the `upstream/lute` submodule are only needed for parity/corpus regeneration.

## 1. Pre-flight (must be green)

```sh
git submodule update --init --recursive   # only for parity/pin checks
tools/upstream.sh --verify                # pin mirrors agree
zig fmt --check build.zig src test samples
zig build check                           # unit + CM/GFM conformance + fuzz + C/WASM smoke
zig build test -Dsanitize=thread          # 8-thread stress under TSan
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
node test/wasm/smoke.mjs                  # after zig build wasm (also in check)

# live parity tooling (needs the gnu-target static lib + zig's linker for cgo)
cd parity/go
CC="zig cc" go run ./cmd/diff --dashboard
CC="zig cc" go run ./cmd/html-oracle
CC="zig cc" go run ./cmd/fuzz -n 3000
go run ./cmd/check-schema
```

Expected dashboard: `cm: 652/652`, `gfm: 672/672`, zero leaks, fuzz/thread tests pass.
Performance: `zig build bench` (~0.95 ms for the spec corpus; see `BENCHMARKS.md`).

## 2. Version bump

Update all three places and keep them equal:

1. `build.zig.zon` → `.version`
2. `src/types.zig` → `version` / `version_string`
3. `build.zig` shared-library `.version`

The release script refuses to run when (1) and (2) disagree.

## 3. Build artifacts

```sh
tools/build-release.sh --clean                  # full matrix + wasm + tarballs + SHA256SUMS
tools/build-release.sh --targets native,wasm    # fast local check
```

Output (`dist/`):

```
lutez-<ver>-<target>-static.tar.gz     include/lutez.h + lib/liblutez.a (Windows: lutez_static.lib)
lutez-<ver>-<target>-dynamic.tar.gz    header + .so/.dylib/.dll (+ import lib)
lutez-<ver>-wasm32-freestanding.tar.gz lutez.wasm + lutez.mjs
SHA256SUMS
```

Matrix: `x86_64/aarch64-linux-gnu`, `x86_64/aarch64-linux-musl`, `x86_64/aarch64-macos`,
`x86_64-windows-gnu`, each static and dynamic.

Archives are reproducible: GNU tar sorts entries, zeroes mtimes/owners, `gzip -9n`.
Re-running the script must produce identical checksums (verify with
`cd dist && sha256sum -c SHA256SUMS`).

## 4. Verify the artifacts

```sh
cd dist && sha256sum -c SHA256SUMS
cd /tmp && tar xzf lutez-<ver>-x86_64-linux-gnu-static.tar.gz
zig cc -std=c99 -I<dir>/include samples/c/smoke.c <dir>/lib/liblutez.a -o smoke && ./smoke
node test/wasm/smoke.mjs dist/lutez-<ver>-wasm32-freestanding/lutez.wasm
```

## 5. Publish

- Commit the version bump + regenerated corpus/tables (one commit).
- Create the annotated tag (`git tag -a v<version> -m "lutez v<version>"`) and attach
  `dist/*.tar.gz` + `SHA256SUMS` to the release.
- Record the tag in `doc/UPSTREAM.md` only when the upstream pin moves.

## 6. Post-release

- Run `tools/upstream.sh --diff`; schedule the next tag bump.
- Keep `test/corpus/*.lzc` in sync with `parity/go/cmd/gencorpus` output.
- Re-run the full matrix after any Zig upgrade (separate benchmarked PR).
