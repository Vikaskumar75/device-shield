# Project documentation

Every project document lives here. User-facing documentation is the site in
[`website/`](../website/). The package's own `README.md` and `CHANGELOG.md`
stay in [`app/`](../app/) because pub.dev requires them there.

## Start here

| Document | What it is |
|---|---|
| [HANDOVER.md](HANDOVER.md) | Current state, open findings (F1–F10) and priorities. Read first. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Repository layout, coding rules and the checks CI runs |
| [MANUAL_TEST_PLAN.md](MANUAL_TEST_PLAN.md) | 0.1.0 device test procedure and recorded results, including failures |

## Folders

| Folder | Contents |
|---|---|
| [`plans/`](plans/) | Plans and roadmaps. New plans go here, including Claude Code plan-mode plans. |
| [`architecture/`](architecture/) | Architecture, component contracts and code-flow traces |
| [`features/`](features/) | Design documents for individual detection and protection features |
| [`reports/`](reports/) | Point-in-time status and implementation reports |

## Current plans

- [`plans/release-0.1.0.md`](plans/release-0.1.0.md): scope, phases and open
  questions for the first pub.dev release.

## Out of date

These predate the September 2026 review and don't reflect the current code.
Keep them for history, but check `HANDOVER.md` for current priorities.

- [`plans/ROADMAP.md`](plans/ROADMAP.md) and
  [`plans/SDK_MILESTONE_PLAN.md`](plans/SDK_MILESTONE_PLAN.md): the original
  23-milestone plan. The review recommended a much smaller v0.1 scope.
- [`reports/CURRENT_STATE.md`](reports/CURRENT_STATE.md): describes the
  unmodified plugin template.
- Everything in [`architecture/`](architecture/), and
  [`features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md`](features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md):
  the pre-0.1 Dart architecture, removed in 0.1.0. Each file says so at the top.
- [`reports/MANUAL_TEST_PLAN_pre-0.1.md`](reports/MANUAL_TEST_PLAN_pre-0.1.md):
  the manual test plan for the pre-0.1 API and its old example app.
- [`reports/CURRENT_PROGRESS.md`](reports/CURRENT_PROGRESS.md) and
  [`reports/PROJECT_IMPLEMENTATION_REPORT.md`](reports/PROJECT_IMPLEMENTATION_REPORT.md):
  snapshots from before the `device_shield` rename and the `app/` move.
