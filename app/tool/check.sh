#!/usr/bin/env bash
# Runs the same checks as CI (.github/workflows/ci.yml), skipping any tool
# that isn't installed. Usage: app/tool/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer the fvm-pinned SDK when the project has one.
[[ -x .fvm/flutter_sdk/bin/flutter ]] && export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"

skipped=()
have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n==> %s\n' "$1"; }

step 'Dart format'
dart format --output=none --set-exit-if-changed .

step 'Dart analyze'
flutter analyze

step 'Dart tests'
flutter test
(cd example && flutter test)

SWIFT_PATHS=(ios/device_shield/Sources ios/device_shield/Tests example/ios/Runner example/ios/RunnerTests)

if have swift && swift format --version >/dev/null 2>&1; then
  step 'swift-format'
  swift format lint --strict --recursive "${SWIFT_PATHS[@]}"
else
  skipped+=('swift-format')
fi

if have swiftlint; then
  step 'SwiftLint'
  swiftlint lint --quiet
else
  skipped+=('SwiftLint')
fi

# The Homebrew ktlint and detekt wrappers bring their own JDK.
if have ktlint; then
  step 'ktlint'
  ktlint 'android/src/**/*.kt'
else
  skipped+=('ktlint')
fi

if have detekt; then
  step 'detekt'
  detekt --input android/src/main/kotlin,android/src/test/kotlin \
    --config android/config/detekt.yml --build-upon-default-config
else
  skipped+=('detekt')
fi

if ((${#skipped[@]})); then
  printf '\nSkipped, not installed: %s\n' "${skipped[*]}"
  printf 'CI still runs these. Install them with app/tool/setup.sh.\n'
fi
printf '\nAll available checks passed.\n'
