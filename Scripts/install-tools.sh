#!/usr/bin/env bash
# Installs the command-line tools Scripts/verify.sh uses, through Homebrew:
# SwiftFormat and SwiftLint (required) and xcbeautify (shorter logs).
# Installs Homebrew first if it is missing; that needs an administrator
# account. Safe to rerun: it only installs what is missing. Also checks that
# Xcode, not just the Command Line Tools, is selected.
#
#   Scripts/install-tools.sh           install missing tools, then list versions
#   Scripts/install-tools.sh --check   list versions only; exit 1 if a required
#                                      tool is missing or Xcode isn't selected
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

brew_on_path_at_start=false
installed brew && brew_on_path_at_start=true

# The version CI uses for a tool, read from lint.yml; empty if none.
# SwiftFormat is downloaded at SWIFTFORMAT_VERSION, while SwiftLint runs in a
# container whose image tag is the version actually used.
pinned_version() {
  local workflow=.github/workflows/lint.yml
  case "$1" in
    swiftformat)
      sed -n "s/^[[:space:]]*SWIFTFORMAT_VERSION:[[:space:]]*//p" "$workflow" 2>/dev/null |
        head -n 1 | tr -d "\"'[:space:]"
      ;;
    swiftlint)
      sed -n "s|.*image:[[:space:]]*ghcr.io/realm/swiftlint:\([0-9][0-9.]*\).*|\1|p" "$workflow" 2>/dev/null |
        head -n 1
      ;;
  esac
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
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$candidate" ]]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  return 1
}

# Runs the official installer from https://brew.sh, fetched over HTTPS only
# and with time limits so a stalled download fails instead of hanging. It
# needs an administrator account; NONINTERACTIVE makes it fail instead of
# waiting for input.
install_homebrew() {
  echo "Homebrew is not installed. Installing it from https://brew.sh ..."
  local installer
  if ! installer="$(curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 300 \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo "Couldn't download the Homebrew installer." >&2
    return 1
  fi
  NONINTERACTIVE=1 /bin/bash -c "$installer" || return 1
  find_brew
}

if ! $check_only; then
  missing_required=()
  missing_optional=()
  for tool in "${required[@]}"; do installed "$tool" || missing_required+=("$tool"); done
  for tool in "${optional[@]}"; do installed "$tool" || missing_optional+=("$tool"); done
  if ((${#missing_required[@]})); then
    # Required tools need Homebrew, installing it first if necessary.
    if ! find_brew && ! install_homebrew; then
      echo "Couldn't install Homebrew automatically; see the output above. It needs an" >&2
      echo "administrator account and a network connection. Install it from https://brew.sh," >&2
      echo "then run Scripts/install-tools.sh again." >&2
      exit 1
    fi
    # ${array[@]+"${array[@]}"} expands to nothing for an empty array; plain
    # "${array[@]}" aborts under set -u in macOS's bash 3.2.
    brew install "${missing_required[@]}" ${missing_optional[@]+"${missing_optional[@]}"}
  elif ((${#missing_optional[@]})); then
    # Optional tools only if Homebrew is already there; verify.sh works without them.
    if find_brew; then
      brew install "${missing_optional[@]}"
    else
      echo "- Skipping ${missing_optional[*]}: it needs Homebrew and is optional."
    fi
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

# Homebrew's bin directory was only added to this script's PATH. Without it in
# the shell profile, verify.sh can't find the tools afterwards.
if ! $brew_on_path_at_start && installed brew; then
  shellenv="eval \"\$($(command -v brew) shellenv)\""
  echo "! Homebrew isn't on your shell's PATH. Add it, then open a new terminal:"
  echo "    echo '$shellenv' >> ~/.zprofile"
fi

# SwiftLint loads SourceKit from the selected Xcode and crashes with only the
# Command Line Tools selected; verify.sh's xcodebuild needs Xcode too. On
# Linux only `verify.sh --lint` runs, so there is nothing to check.
if [[ "$(uname -s)" == Darwin ]]; then
  developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  developer_dir="${developer_dir%/}"
  if [[ "$developer_dir" == *.app/Contents/Developer && -d "$developer_dir" ]]; then
    echo "✓ Xcode selected ($developer_dir)"
  else
    echo "✗ Xcode isn't selected (developer directory: ${developer_dir:-none})."
    echo "  SwiftLint and verify.sh need it. Run: sudo xcode-select -s /Applications/Xcode.app"
    echo "  or: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
    status=1
  fi
fi
exit "$status"
