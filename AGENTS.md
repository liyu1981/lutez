# AGENTS.md

## Commit rule (mandatory)

An agent **must not commit on its own initiative**. No `git commit`, `git commit --amend`,
tagging, or pushing unless the user explicitly asks for a commit.

- The working tree may be left dirty; staging, building, testing, and editing are fine.
- When the user calls for a commit, commit **once** with the requested changes.
- After that single commit, stop and return to the waiting state: do not chain further
  commits, amendments, or pushes until the user calls again.

If something seems to require an extra commit, ask first.
