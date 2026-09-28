# device_shield

A Flutter plugin (Dart + Kotlin + Swift) for runtime device-security checks.

- Coding rules and tooling: @docs/CONTRIBUTING.md. Follow them.
- Current state and known issues: docs/HANDOVER.md.
- Layout: `app/` is the Flutter plugin package (with `example/`),
  `website/` is the docs site, `docs/` holds every project document.
- **No git or GitHub write actions unless the user explicitly asks**: no
  commit, push, add, mv, branch, stash, remote changes or `gh` writes. Move
  files with plain `mv`. Read-only git (status, diff, log) is fine.
  `.claude/hooks/git_guard.py` forces an approval prompt for writes.
- New machine: `app/tool/setup.sh --check` reports missing prerequisites.
- Before calling a change done, run `app/tool/check.sh`. It must pass.
- The iOS example can't build in place while the package folder is named
  `app` (F10 in docs/HANDOVER.md). Build from a copy of `app/` named
  `device_shield`.

## Documents

All project documents go in `docs/`. Never create them at the repo root or
inside `app/`.

- **Plans** (implementation plans, roadmaps, migration plans, any plan file)
  go in `docs/plans/`. Plan-mode plans are saved there automatically
  (`plansDirectory` in `.claude/settings.json`).
- Architecture and design go in `docs/architecture/`, feature designs in
  `docs/features/`, and status or investigation reports in `docs/reports/`.
- When you add a document, add a line for it to `docs/README.md`.
- Exceptions: `README.md` and `CLAUDE.md` stay at the root. The root
  `README.md` is a copy of `app/README.md`: edit `app/README.md`, then
  `cp app/README.md README.md` (`check.sh` enforces it).
  `app/README.md` and `app/CHANGELOG.md` stay in the package (pub.dev
  requires them). User-facing docs are pages in `website/src/content/docs/`.
