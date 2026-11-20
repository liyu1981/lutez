# Upstream regression fixtures (M4.6)

Files copied from `upstream/lute/test/` at the pinned revision (`v1.7.8`) as parser
regression inputs. They are not part of the strict parity corpus (which is generated
separately); they exercise larger real-world documents and must parse without crashing,
leaking, or producing an empty document.

| File | Source |
|---|---|
| `upstream-case1.md` | `test/case1.md` |
| `upstream-format-case0.md` | `test/format-case0.md` |
| `upstream-format-case4.md` | `test/format-case4.md` |
| `upstream-code-syntax.md` | `test/code-syntax-highlight-issue17.md` |
| `upstream-gfm-spec.md` | `test/gfm-spec.md` |
