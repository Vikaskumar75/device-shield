#!/usr/bin/env bash
# Prepares this repository for development. Safe to re-run.
#
#   app/tool/setup.sh           check everything, offer to install what's missing
#   app/tool/setup.sh --yes     install missing Homebrew packages without asking
#   app/tool/setup.sh --check   only report; install and change nothing
#
# Installs command-line tools with Homebrew (macOS). It never uses sudo and
# never edits your shell profile: where a step needs that, it prints the
# command for you to run.
set -euo pipefail

cd "$(dirname "$0")/.."

# Keep in sync with .fvmrc, pubspec.yaml and .github/workflows/ci.yml.
FLUTTER_VERSION=3.44.8
JDK_VERSION=17
NODE_MIN_MAJOR=22

mode=ask
for arg in "$@"; do
  case "$arg" in
    --yes) mode=yes ;;
    --check) mode=check ;;
    -h | --help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (see --help)" >&2
      exit 2
      ;;
  esac
done

problems=()
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() {
  printf '  \033[33m!\033[0m %s\n' "$1"
  problems+=("$1")
}
have() { command -v "$1" >/dev/null 2>&1; }
confirm() {
  [[ $mode == yes ]] && return 0
  [[ $mode == check ]] && return 1
  read -r -p "  $1 [y/N] " reply
  [[ $reply =~ ^[Yy]$ ]]
}

is_mac=false
[[ $(uname -s) == Darwin ]] && is_mac=true

# Prefer the fvm-pinned SDK when the project has one.
[[ -x .fvm/flutter_sdk/bin/flutter ]] && export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"

# ---------------------------------------------------------------------------
section 'Repository'

pkg_dir=$(basename "$PWD")
if [[ $pkg_dir == device_shield ]]; then
  ok "package folder is named device_shield"
else
  echo "  note: the iOS example can't build in place while the package folder is named '$pkg_dir'"
  echo "        (Flutter bug, F10 in docs/HANDOVER.md). Build it from a copy named device_shield."
fi

if $is_mac; then
  ok 'macOS'
else
  warn 'not macOS: Dart and Android work is fine, but iOS builds and Swift tooling need a Mac'
fi

# ---------------------------------------------------------------------------
section 'Flutter'

flutter_version() {
  flutter --version --machine 2>/dev/null |
    sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'
}

current=$(have flutter && flutter_version || true)
if [[ $current == "$FLUTTER_VERSION" ]]; then
  ok "Flutter $FLUTTER_VERSION"
else
  echo "  Flutter ${current:-not found}; this project uses $FLUTTER_VERSION."
  if ! have fvm && have brew && confirm 'Install fvm (Flutter version manager) with Homebrew?'; then
    brew install fvm
  fi
  if have fvm && confirm "Install Flutter $FLUTTER_VERSION for this project with fvm (about 1 GB)?"; then
    fvm install "$FLUTTER_VERSION"
    fvm use "$FLUTTER_VERSION" --skip-pub-get
    export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
    ok "Flutter $FLUTTER_VERSION via fvm. Use 'fvm flutter …', or point your IDE at .fvm/flutter_sdk"
  else
    warn "Flutter $FLUTTER_VERSION not active (fvm install $FLUTTER_VERSION && fvm use $FLUTTER_VERSION)"
  fi
fi

# One `flutter doctor -v` run answers both the Android SDK and JDK questions.
doctor=$(have flutter && flutter doctor -v 2>/dev/null || true)
# The JDK Flutter's Gradle builds use (usually Android Studio's bundled JBR).
flutter_jdk=$(sed -n 's/^.*Java binary at: \(.*\)\/bin\/java$/\1/p' <<<"$doctor" | head -1)

# ---------------------------------------------------------------------------
section 'Homebrew packages'

formulae=()
java_ok() {
  local v
  v=$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1) || return 1
  [[ -n $v && $v -ge $JDK_VERSION ]]
}
node_ok() {
  have node && [[ $(node -p 'process.versions.node.split(".")[0]') -ge $NODE_MIN_MAJOR ]]
}

have gh && ok 'gh (GitHub CLI)' || formulae+=(gh)
have ktlint && ok 'ktlint' || formulae+=(ktlint)
have detekt && ok 'detekt' || formulae+=(detekt)
if $is_mac; then
  have swiftlint && ok 'swiftlint' || formulae+=(swiftlint)
fi
if ! java_ok && [[ -z $flutter_jdk ]] &&
  ! { have brew && brew list --versions "openjdk@$JDK_VERSION" >/dev/null 2>&1; }; then
  formulae+=("openjdk@$JDK_VERSION")
fi
node_ok && ok "Node.js $NODE_MIN_MAJOR+ (docs site)" || formulae+=(node)

if ((${#formulae[@]})); then
  if ! have brew; then
    warn "missing: ${formulae[*]}. Install Homebrew (https://brew.sh) or install these manually"
  elif confirm "Install with Homebrew: ${formulae[*]}?"; then
    brew install "${formulae[@]}"
    ok "installed ${formulae[*]}"
  else
    warn "missing: ${formulae[*]} (brew install ${formulae[*]})"
  fi
fi

# ---------------------------------------------------------------------------
section 'Java'

if java_ok; then
  ok "$(java -version 2>&1 | head -1) on PATH"
elif [[ -n $flutter_jdk ]]; then
  ok "Flutter builds use the JDK at $flutter_jdk"
  echo "    To run ./gradlew directly, first: export JAVA_HOME=\"$flutter_jdk\""
elif have brew && brew list --versions "openjdk@$JDK_VERSION" >/dev/null 2>&1; then
  jdk_home="$(brew --prefix "openjdk@$JDK_VERSION")/libexec/openjdk.jdk/Contents/Home"
  warn "openjdk@$JDK_VERSION is installed but not on your PATH. Add to your shell profile:
      export JAVA_HOME=\"$jdk_home\"
      export PATH=\"\$JAVA_HOME/bin:\$PATH\""
else
  warn "no Java $JDK_VERSION+ runtime (needed for Android builds)"
fi

# ---------------------------------------------------------------------------
if $is_mac; then
  section 'Xcode'
  if xcodebuild -version >/dev/null 2>&1; then
    ok "$(xcodebuild -version | head -1)"
    swift format --version >/dev/null 2>&1 && ok 'swift format' || warn 'swift format not found (ships with Xcode 16+)'
  else
    warn 'Xcode not found or not selected. Install it from the App Store, then: sudo xcode-select -s /Applications/Xcode.app'
  fi
fi

# ---------------------------------------------------------------------------
section 'Android SDK'

if have flutter; then
  if grep -q '\[✓\] Android toolchain' <<<"$doctor"; then
    ok 'Android toolchain (flutter doctor)'
  else
    warn "Android toolchain not ready. Install Android Studio or the command-line tools, then run 'flutter doctor --android-licenses'"
  fi
else
  warn 'skipped: Flutter not available'
fi

# ---------------------------------------------------------------------------
section 'GitHub CLI'

if have gh; then
  if gh auth status >/dev/null 2>&1; then
    ok 'gh is logged in'
  else
    warn "gh is not logged in (needed for /fix-issue). Run: gh auth login"
  fi
else
  echo '  skipped: gh not installed'
fi

# ---------------------------------------------------------------------------
section 'Project dependencies'

if [[ $mode == check ]]; then
  echo '  skipped (--check)'
else
  if have flutter; then
    flutter pub get >/dev/null && ok 'flutter pub get'
    (cd example && flutter pub get >/dev/null) && ok 'flutter pub get (example)'
  fi
  if node_ok; then
    npm ci --prefix ../website --no-audit --no-fund --loglevel=error >/dev/null && ok 'npm ci (website)'
  fi
fi

# ---------------------------------------------------------------------------
printf '\n'
if ((${#problems[@]})); then
  printf '\033[33mSetup incomplete. %d item(s) need attention:\033[0m\n' "${#problems[@]}"
  for p in "${problems[@]}"; do printf '  - %s\n' "$p"; done
  exit 1
fi
printf '\033[32mReady.\033[0m Run app/tool/check.sh to verify everything passes.\n'
