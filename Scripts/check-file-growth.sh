#!/usr/bin/env bash
# Warns when a Swift file over 600 lines gets longer, or a new one over 600
# lines is added ("Large files" in AGENTS.md). Advisory only: always exits 0.
#
#   Scripts/check-file-growth.sh [base]
#
# Compares the working tree, including uncommitted and untracked files, with
# the merge base of HEAD and <base> (default: upstream/main, origin/main or
# main, whichever exists). In GitHub Actions the warnings become annotations.
#
# This replaces SwiftLint's file_length and type_body_length rules: their
# messages contain the current count, so the baseline re-reported every long
# file on any edit, even one that made it shorter.
set -euo pipefail

cd "$(dirname "$0")/.."

limit=600
paths=('Apps/*.swift' 'Packages/*.swift' 'Extensions/*.swift' 'Tests/*.swift')

warn() {
  local path="$1" message="$2"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning file=$path,title=Large file grew::$message"
  else
    echo "! $message"
  fi
}

# Prints the line count; fails if the file is gone, for example deleted
# while the check runs, so the caller skips it.
line_count() {
  [[ -f "$1" ]] || return 1
  wc -l < "$1" | tr -d '[:space:]'
}

grown=0

# New, untracked files first: they don't need a base to compare with. Each
# git command's output is captured first, so a failure is reported as a
# skipped check instead of looking like "nothing grew".
if ! untracked="$(git ls-files --others --exclude-standard -- "${paths[@]}")"; then
  echo "File growth: couldn't list untracked files, skipped."
  exit 0
fi
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  lines="$(line_count "$path")" || continue
  ((lines > limit)) || continue
  warn "$path" "New file $path has $lines lines (over $limit). Split it before it lands; see \"Large files\" in AGENTS.md."
  grown=$((grown + 1))
done <<< "$untracked"

base="${1:-}"
if [[ -z "$base" ]]; then
  for candidate in upstream/main origin/main main; do
    if git rev-parse -q --verify "$candidate^{commit}" >/dev/null; then
      base="$candidate"
      break
    fi
  done
fi
if [[ -z "$base" ]] || ! merge_base="$(git merge-base HEAD "$base" 2>/dev/null)"; then
  echo "File growth: no base branch to compare with, so only new files were checked."
  exit 0
fi

if ! numstat="$(git diff --numstat --no-renames "$merge_base" -- "${paths[@]}")"; then
  echo "File growth: comparing with $base failed, skipped."
  exit 0
fi
while IFS=$'\t' read -r added deleted path; do
  # Binary files show "-" instead of line counts.
  [[ -n "$path" && "$added" != "-" ]] || continue
  ((added > deleted)) || continue
  lines="$(line_count "$path")" || continue
  ((lines > limit)) || continue
  warn "$path" "$path grew by $((added - deleted)) lines to $lines (over $limit). Move new code into its own type and file; see \"Large files\" in AGENTS.md."
  grown=$((grown + 1))
done <<< "$numstat"

if ((grown == 0)); then
  echo "File growth: no Swift file over $limit lines got longer."
fi
exit 0
