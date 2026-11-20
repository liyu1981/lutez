# Upstream pin (git submodule)

`lutez` ports from exactly one upstream revision. The pin **is** the gitlink recorded
for the submodule in the superproject commit — there is no separate fetch script and no
vendored copy.

| Field | Value |
|---|---|
| Submodule path | `upstream/lute` |
| Submodule name | `lute` (see `.gitmodules`) |
| Repository | https://github.com/88250/lute |
| **Pinned release** | **`v1.7.8`** |
| Pinned commit | `56b87cda10fb394981849aa8de19b8491aea62b4` |
| Commit date | 2026-09-23 |
| Clone | shallow, `depth = 1` (`shallow = true` in `.gitmodules`) |
| License | Mulan PSL v2 (`LICENSE`) |

The pin commit is mirrored in three places for humans and runtime reporting:

- `src/types.zig` → `upstream_sha` (exposed by the library),
- `NOTICE` → “Upstream revision ported”,
- this document.

`tools/upstream.sh --verify` fails if any mirror disagrees with the submodule HEAD.
That check runs as the `pin` CI job on every push.

## Pin policy

1. **Track release tags, not `master`.** The newest published tag is the baseline.
   Upstream moves quickly; tags are the reviewable, reproducible unit for a port.
2. **Bump on the next tag.** A tag bump is a dedicated commit that ports the upstream
   delta as a reviewed set of `port(...)` changes (see §4).
3. **Exception: security fixes only.** A security-relevant upstream fix may be adopted
   before the next tag by cherry-picking the minimal change. Record it in
   §“Security exceptions” below with the upstream commit, rationale, tests, and the tag
   it will fold into. No feature deltas are adopted early.
4. Never mix a pin bump with behavior changes.

## Why `v1.7.8` and what is deferred

At pin time, `master` (2026-11-13) was ~830 changed lines ahead of `v1.7.8`
(2026-09-23) across `lex/`, `ast/`, `parse/`, and `html/` (including out-of-scope files
such as `document_title.go`, `latex_math.go`, and `math_block.go`). Those in-scope deltas
are **not** ported at bootstrap; they are deferred to the next tag bump:

| Upstream file | Δ vs `v1.7.8` | Notes |
|---|---:|---|
| `parse/linkrefdef_index.go` | +66 | ref-def indexing changes |
| `parse/parse.go` | +42 | option/flow changes |
| `parse/inline.go` | +35 | inline flow changes |
| `parse/inline_html.go` | +16 | inline HTML scanning changes |
| `parse/inlines.go` | +16 | |
| `parse/table.go` | 78 | table parsing rework |
| `parse/link.go` | −11 | |
| `parse/delimiter.go`, `code_span.go`, `paragraph.go` | +1..3 | small fixes |

The parity harness is generated from the **pinned** tree, so its expectations match
`v1.7.8`. When the next tag is pinned, regenerate the corpus and fix the diffs.

## Commands

```sh
# first checkout / after clone
git submodule update --init --recursive

# inspect: submodule HEAD vs the pin mirrors, shallow status
tools/upstream.sh --status

# CI gate: all pin copies must agree
tools/upstream.sh --verify

# drift review: scoped-file diff pin..origin/master
tools/upstream.sh --diff

# move the submodule to another ref/tag (does not edit docs/mirrors)
tools/upstream.sh --bump v1.7.9
```

Because the clone is shallow, `--diff`/`--bump` fetch only the needed tip
(`--depth 1`) and fall back to a full fetch if git refuses. Do not run
`git -C upstream/lute commit` — the submodule is read-only reference material.

## Rules

1. `upstream/lute/` is **never** edited and **never** imported by `src/`. Nothing in the
   build needs it: `zig build check` works on a plain checkout.
2. Paths under `upstream/` are read-only inputs for:
   `parity/` (oracle, cgo bridge, corpus + schema checks) and `tools/gen-entity`.
3. Only `parity/`, `tools/`, and docs may reference `upstream/`; the port in `src/` is
   self-contained.
4. Never mix a pin bump with behavior changes; bump first, then port upstream diffs in
   dedicated `port(...)` commits.

## Bump procedure (next release tag)

1. Read the new tag's release notes; note behavior changes inside the scoped files.
2. `tools/upstream.sh --bump v1.7.9`; confirm the printed SHA and that
   `git -C upstream/lute rev-parse --is-shallow-repository` is still `true`.
3. Update the three mirrors: `src/types.zig:upstream_sha`, `NOTICE`, and this table.
4. `tools/upstream.sh --verify` must pass.
5. Port the upstream delta in reviewed slices (block, inline, tables, ref-defs). Each
   slice is a `port(<area>): ...` commit with parity-test evidence.
6. Regenerate dependent artifacts:
   - `go run ./tools/gen-unicode` (if the Go/Unicode baseline moved),
   - `go run ./tools/gen-entity` (reads `upstream/lute/html/entity.go`),
   - `cd parity/go && go run ./cmd/gencorpus` (writes `test/corpus/*.lzc`),
   - `cd parity/go && go run ./cmd/check-schema` (AST field drift).
7. Run the parity dashboard:
   `cd parity/go && go run ./cmd/diff --dashboard`; triage every diff as
   “upstream behavior change” (port it) or “out of scope” (extend the mask, with a note).
8. `zig build check` + `node test/wasm/smoke.mjs`.
9. Commit **together**: submodule gitlink, `.gitmodules` (if changed), mirrors, schema
   doc, generated tables, corpus, and this file.

## Security exceptions

Adopted early, ahead of the next tag. Keep this table empty unless a security fix
requires it.

| Date | Upstream commit | Fix | Tests | Folds into |
|---|---|---|---|---|
| — | — | — | — | — |

## Drift policy

- CI verifies the pin on every push (`pin` job) and fails on mirror drift.
- During M2–M4, run `tools/upstream.sh --diff` weekly and keep the output in the parity
  notes. Do **not** change the pin on the basis of that diff; port at tag time.
- A bump that changes wire-visible fields requires a `format_version` bump and a
  `doc/AST_SCHEMA.md` revision.

## Scope note

Files outside the parser subset are not translated. See
`doc/ZIG_PORT_FEASIBILITY.md` §2.2 for the upstream exclusion list and
`doc/PLAN.md` §1.2 for the hard scope fence.
