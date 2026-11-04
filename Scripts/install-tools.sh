#!/usr/bin/env bash
# Installs the command-line tools Scripts/verify.sh uses, through Homebrew:
# SwiftFormat and SwiftLint (required) and xcbeautify (shorter logs).
# Installs Homebrew first if it is missing; that needs an administrator
# account. Safe to rerun: it only installs what is missing. Also checks that
# Xcode, not just the Command Line Tools, is selected.
#
#   Scripts/install-tools.sh           install missing tools, then list versions
#   Scripts/install-tools.sh --check   list versions only; exit 1 if a required
#                                      tool is missing
#
# CI pins exact SwiftFormat and SwiftLint versions in
# .github/workflows/lint.yml. Homebrew installs the latest release, so this
# script warns when a local version differs from CI's.
set -euo pipefail

cd "$(dirname "$0")/.."

check_only=false
case "${1:-}" in
  --check) check_only=true ;;
  "") ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "Unknown option: $1 (use --check or --help)" >&2; exit 2 ;;
esac

required=(swiftformat swiftlint)
optional=(xcbeautify)

installed() { command -v "$1" >/dev/null 2>&1; }

# The version CI pins for a tool, read from lint.yml; empty if none.
pinned_version() {
  local key
  case "$1" in
    swiftformat) key=SWIFTFORMAT_VERSION ;;
    swiftlint) key=SWIFTLINT_VERSION ;;
    *) return 0 ;;
  esac
  sed -n "s/^[[:space:]]*$key:[[:space:]]*//p" .github/workflows/lint.yml 2>/dev/null |
    head -n 1 | tr -d "\"'[:space:]"
}

local_version() {
  case "$1" in
    swiftlint) swiftlint version ;;
    *) "$1" --version ;;
  esac 2>/dev/null | head -n 1
}

# Puts Homebrew on PATH if it is installed but this shell doesn't know it yet,
# as right after installing it on Apple silicon.
find_brew() {
  installed brew && return 0
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  return 1
}

# Runs the official installer from https://brew.sh. It needs an administrator
# account; NONINTERACTIVE makes it fail instead of waiting for input.
install_homebrew() {
  echo "Homebrew is not installed. Installing it from https://brew.sh ..."
  local installer
  installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  NONINTERACTIVE=1 /bin/bash -c "$installer" || return 1
  find_brew
}

if ! $check_only; then
  missing=()
  for tool in "${required[@]}" "${optional[@]}"; do
    installed "$tool" || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    if ! find_brew && ! install_homebrew; then
      echo "Couldn't install Homebrew automatically (it needs an administrator account)." >&2
      echo "Install it from https://brew.sh, then run Scripts/install-tools.sh again." >&2
      exit 1
    fi
    brew install "${missing[@]}"
  fi
fi

status=0
for tool in "${required[@]}" "${optional[@]}"; do
  if ! installed "$tool"; then
    if [[ " ${required[*]} " == *" $tool "* ]]; then
      echo "✗ $tool is not installed"
      status=1
    else
      echo "- $tool is not installed (optional)"
    fi
    continue
  fi
  have="$(local_version "$tool")"
  want="$(pinned_version "$tool")"
  if [[ -n "$want" && "$have" != "$want" ]]; then
    echo "! $tool $have (CI uses $want, so results can differ)"
  else
    echo "✓ $tool $have"
  fi
done

# SwiftLint loads SourceKit from the selected Xcode and crashes with only the
# Command Line Tools selected; verify.sh's xcodebuild needs Xcode too.
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ "$developer_dir" == *.app/Contents/Developer ]]; then
  echo "✓ Xcode selected ($developer_dir)"
else
  echo "✗ Xcode isn't selected (developer directory: ${developer_dir:-none})."
  echo "  SwiftLint and verify.sh need it. Run: sudo xcode-select -s /Applications/Xcode.app"
  echo "  or: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
  status=1
fi
exit "$status"
