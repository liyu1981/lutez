# Upstream pin (git submodule)

`lutez` ports from exactly one upstream revision. The pin **is** the gitlink recorded
for the submodule in the superproject commit — there is no separate fetch script and no
vendored copy.

| Field | Value |
|---|---|
| Submodule path | `upstream/lute` |
| Submodule name | `lute` (see `.gitmodules`) |
| Repository | https://github.com/88250/lute |
| Pinned commit | `61eb27b6d43418b79ee91d8618f7acbccdcd1ba5` |
| Commit date | 2026-11-13 |
| Nearest release tag | `v1.7.8` (`56b87cd`, 2026-09-23) — **not** the pin |
| Clone | shallow, `depth = 1` (`shallow = true` in `.gitmodules`) |
| License | Mulan PSL v2 (`LICENSE`) |

The pin commit is mirrored in two places for humans and runtime reporting:

- `src/types.zig` → `upstream_sha` (exposed by the library),
- `NOTICE` → “Upstream revision ported”.

`tools/upstream.sh --verify` fails if either mirror disagrees with the submodule HEAD.
That check runs as the `pin` CI job on every push.

## Why master instead of the tag

Between `v1.7.8` and the pin, scoped files changed substantially:
`parse/linkrefdef_index.go` (+66), `parse/inline.go` (+35), `parse/table.go` (78),
`parse/parse.go` (+42), `parse/inlines.go` (+16), `parse/inline_html.go` (+16),
plus smaller fixes. Parity must target current behavior, otherwise the differential
harness would encode stale expectations.

## Commands

```sh
# first checkout / after clone
git submodule update --init --recursive

# inspect: submodule HEAD vs the two pin mirrors, shallow status
tools/upstream.sh --status

# CI gate: all pin copies must agree
tools/upstream.sh --verify

# drift review: scoped-file diff pin..origin/master
tools/upstream.sh --diff

# move the submodule to another revision (does not edit docs/mirrors)
tools/upstream.sh --bump v1.7.8
```

Because the clone is shallow, `--diff`/`--bump` fetch what they need on demand
(`fetch --unshallow` is the fallback). Do not run `git -C upstream/lute commit` — the
submodule is read-only reference material.

## Rules

1. `upstream/lute/` is **never** edited and **never** imported by `src/`. Nothing in the
   build needs it: `zig build check` works on a plain checkout.
2. Paths under `upstream/` are read-only inputs for:
   `parity/` (oracle, cgo bridge, corpus + schema checks) and `tools/gen-entity`.
3. Only `parity/`, `tools/`, and docs may reference `upstream/`; the port in `src/` is
   self-contained.
4. Never mix a pin bump with behavior changes; bump first, then port upstream diffs in
   dedicated `port(...)` commits.

## Bump procedure

1. Pick the new revision (prefer a release tag if the scoped-file diff is small).
2. `tools/upstream.sh --bump <ref>`; confirm the printed SHA and that
   `git -C upstream/lute rev-parse --is-shallow-repository` is still `true`.
3. Update the two mirrors: `src/types.zig:upstream_sha` and `NOTICE`; update this table.
4. `tools/upstream.sh --verify` must pass.
5. Regenerate anything the bump invalidates:
   - `go run ./tools/gen-unicode` (if the Go/Unicode baseline moved),
   - `go run ./tools/gen-entity` (reads `upstream/lute/html/entity.go`),
   - `cd parity/go && go run ./cmd/gencorpus` (writes `test/corpus/*.lzc`),
   - `cd parity/go && go run ./cmd/check-schema` (AST field drift).
6. Run the parity dashboard:
   `cd parity/go && go run ./cmd/diff --dashboard`; triage every new diff as
   “upstream behavior change” (port it) or “out of scope” (extend the mask, with a note).
7. `zig build check` + `node js/smoke.mjs`.
8. Commit **together**: submodule gitlink, `.gitmodules` (if changed), mirrors, schema
   doc, generated tables, corpus, and this file.

## Drift policy

- CI verifies the pin on every push (`pin` job) and fails on mirror drift.
- During M2–M4, run `tools/upstream.sh --diff` weekly and keep the output in the parity
  notes; upstream is active and `master` moves.
- A bump that changes wire-visible fields requires a `format_version` bump and a
  `doc/AST_SCHEMA.md` revision.

## Scope note

Files outside the parser subset are not translated. See
`doc/ZIG_PORT_FEASIBILITY.md` §2.2 for the upstream exclusion list and
`doc/PLAN.md` §1.2 for the hard scope fence.
