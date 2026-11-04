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
  echo "File growth: no base branch to compare with, skipped."
  exit 0
fi

warn() {
  local path="$1" message="$2"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning file=$path,title=Large file grew::$message"
  else
    echo "! $message"
  fi
}

line_count() { wc -l < "$1" | tr -d '[:space:]'; }

grown=0
while IFS=$'\t' read -r added deleted path; do
  # Binary files show "-"; deleted files are gone from the working tree.
  [[ "$added" == "-" || ! -f "$path" ]] && continue
  ((added > deleted)) || continue
  lines="$(line_count "$path")"
  ((lines > limit)) || continue
  warn "$path" "$path grew by $((added - deleted)) lines to $lines (over $limit). Move new code into its own type and file; see \"Large files\" in AGENTS.md."
  grown=$((grown + 1))
done < <(git diff --numstat --no-renames "$merge_base" -- "${paths[@]}")

while IFS= read -r path; do
  lines="$(line_count "$path")"
  ((lines > limit)) || continue
  warn "$path" "New file $path has $lines lines (over $limit). Split it before it lands; see \"Large files\" in AGENTS.md."
  grown=$((grown + 1))
done < <(git ls-files --others --exclude-standard -- "${paths[@]}")

if ((grown == 0)); then
  echo "File growth: no Swift file over $limit lines got longer."
fi
exit 0
