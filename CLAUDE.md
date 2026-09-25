# device_shield

A Flutter plugin (Dart + Kotlin + Swift) for runtime device-security checks.

- Coding rules and tooling: @CONTRIBUTING.md. Follow them.
- Current state and known issues: HANDOVER.md.
- Layout: `app/` is the Flutter plugin package (with `example/`),
  `website/` is the docs site.
- New machine: `app/tool/setup.sh --check` reports missing prerequisites.
- Before calling a change done, run `app/tool/check.sh`. It must pass.
- The iOS example can't build in place while the package folder is named
  `app` (F10 in HANDOVER.md). Build from a copy of `app/` named
  `device_shield`.
