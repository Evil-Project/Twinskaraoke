#!/usr/bin/env bash
# Runs the same checks as CI, so humans and AI agents can verify a change
# before opening a PR.
#
#   Scripts/verify.sh            format check, lint, Release build + analyze
#                                of all 4 schemes, iOS + watchOS unit tests
#   Scripts/verify.sh --quick    format check, lint, Release build + analyze
#                                of the iOS app only
#   Scripts/verify.sh --lint     format check and lint only (works on Linux)
#
# Needs: Xcode (macOS), swiftformat and swiftlint (Scripts/install-tools.sh
# installs them). xcbeautify is used for shorter logs when installed.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="full"
case "${1:-}" in
  --quick) mode="quick" ;;
  --lint) mode="lint" ;;
  "") ;;
  -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  *) echo "Unknown option: $1 (use --quick, --lint or --help)" >&2; exit 2 ;;
esac

project="Twinskaraoke.xcodeproj"
common_flags=(-project "$project" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO)
failures=()

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*"; failures+=("$*"); }
pass() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

pretty() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify --quieter; else cat; fi
}

# Newest available simulator whose name starts with $1 ("iPhone", "Apple Watch").
simulator_udid() {
  xcrun simctl list devices available -j | ruby -rjson -e '
    prefix = ARGV[0]
    devices = JSON.parse(STDIN.read)["devices"]
    devices.keys.sort_by { |runtime| runtime.scan(/\d+/).map(&:to_i) }.reverse_each do |runtime|
      match = devices[runtime].find { |d| d["isAvailable"] && d["name"].start_with?(prefix) }
      if match
        puts match["udid"]
        exit
      end
    end' "$1"
}

# --- Format -----------------------------------------------------------------
step "SwiftFormat (lint mode)"
if [[ ! -f .swiftformat ]]; then
  echo "No .swiftformat config yet — skipped."
elif command -v swiftformat >/dev/null 2>&1; then
  if swiftformat --lint . ; then pass "Formatting"; else fail "Formatting — run swiftformat on the files you changed (see AGENTS.md)"; fi
else
  fail "swiftformat not installed (run Scripts/install-tools.sh)"
fi

# --- Lint -------------------------------------------------------------------
step "SwiftLint"
if [[ ! -f .swiftlint.yml ]]; then
  echo "No .swiftlint.yml config yet — skipped."
elif command -v swiftlint >/dev/null 2>&1; then
  baseline_args=()
  [[ -f .swiftlint-baseline.json ]] && baseline_args=(--baseline .swiftlint-baseline.json)
  if swiftlint lint --quiet "${baseline_args[@]}"; then pass "Lint"; else fail "Lint — run: swiftlint --fix, then fix the rest"; fi
else
  fail "swiftlint not installed (run Scripts/install-tools.sh)"
fi

# --- Large files ------------------------------------------------------------
# Warns when a Swift file over 600 lines grows. Fails only when one of the
# files AGENTS.md says must not grow got longer.
step "Large files"
if Scripts/check-file-growth.sh; then
  pass "Large files"
else
  fail "Large files — a file AGENTS.md says must not grow got longer"
fi

if [[ "$mode" == "lint" ]]; then
  :
elif ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild not found — build and tests need macOS with Xcode"
else
  # --- Build ----------------------------------------------------------------
  if [[ "$mode" == "quick" ]]; then
    builds=("Twinskaraoke|generic/platform=iOS Simulator")
  else
    builds=(
      "Twinskaraoke|generic/platform=iOS Simulator"
      "Twinskaraoke Mac App|platform=macOS"
      "Twinskaraoke TV App|generic/platform=tvOS Simulator"
      "TwinskaraokeWatchApp|generic/platform=watchOS Simulator"
    )
  fi
  for entry in "${builds[@]}"; do
    scheme="${entry%%|*}"; destination="${entry#*|}"
    step "Build and analyze $scheme (Release)"
    # Same as analyze.yml: Release configuration plus the static analyzer.
    if xcodebuild build analyze "${common_flags[@]}" -configuration Release \
        -scheme "$scheme" -destination "$destination" 2>&1 | pretty; then
      pass "Build $scheme"
    else
      fail "Build $scheme"
    fi
  done

  # --- Unit tests -----------------------------------------------------------
  if [[ "$mode" == "full" ]]; then
    step "iOS unit tests"
    udid="$(simulator_udid iPhone || true)"
    if [[ -z "$udid" ]]; then
      fail "No iPhone simulator available"
    else
      if ! xcrun simctl bootstatus "$udid" -b >/dev/null; then
        fail "iPhone simulator $udid did not boot"
      elif xcodebuild test "${common_flags[@]}" -scheme Twinskaraoke \
          -destination "platform=iOS Simulator,id=$udid" \
          -only-testing:TwinskaraokeTests -parallel-testing-enabled NO 2>&1 | pretty; then
        pass "iOS unit tests"
      else
        fail "iOS unit tests"
      fi
    fi

    step "watchOS unit tests"
    udid="$(simulator_udid "Apple Watch" || true)"
    if [[ -z "$udid" ]]; then
      fail "No Apple Watch simulator available"
    elif xcodebuild test "${common_flags[@]}" -scheme TwinskaraokeWatchApp \
        -destination "platform=watchOS Simulator,id=$udid" \
        -only-testing:'Twinskaraoke Watch AppTests' 2>&1 | pretty; then
      pass "watchOS unit tests"
    else
      fail "watchOS unit tests"
    fi
  fi
fi

# --- Summary ----------------------------------------------------------------
echo
if ((${#failures[@]})); then
  printf '\033[1;31mverify.sh: %d check(s) failed:\033[0m\n' "${#failures[@]}"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
printf '\033[1;32mverify.sh: all checks passed (%s)\033[0m\n' "$mode"
