#!/usr/bin/env bash
# Warns when a Swift file over 600 lines gets longer, or a new one over 600
# lines is added ("Large files" in AGENTS.md). That part is advisory. It
# fails (exit 1) only when one of the files AGENTS.md says must not grow, the
# `frozen` list below, got longer.
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
# The files "Large files" in AGENTS.md names. Keep the two lists the same.
frozen=(
  Packages/Features/Playback/iOS/AudioPlayerManager.swift
  Packages/Core/Storage/iOS/DownloadManager.swift
  Apps/iOS/Screens/Player/FullScreenPlayerView.swift
  Apps/iOS/Screens/Search/SearchView.swift
  Apps/iOS/Navigation/ContentView.swift
)

warn() {
  local path="$1" message="$2"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning file=$path,title=Large file grew::$message"
  else
    echo "! $message"
  fi
}

error() {
  local path="$1" message="$2"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error file=$path,title=Frozen file grew::$message"
  else
    echo "✗ $message"
  fi
}

# True when $1 is a frozen file's current path, which the frozen check below
# already judged. The ${array[@]+...} form survives an empty array under
# set -u in macOS's bash 3.2.
is_frozen_now() {
  local candidate
  for candidate in ${frozen_now[@]+"${frozen_now[@]}"}; do
    [[ "$candidate" == "$1" ]] && return 0
  done
  return 1
}

# Prints the line count; fails if the file is gone, for example deleted
# while the check runs, so the caller skips it.
line_count() {
  [[ -f "$1" ]] || return 1
  wc -l < "$1" | tr -d '[:space:]'
}

grown=0
frozen_grown=0
frozen_now=()

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

# Frozen files: compare each one's length at the merge base with the file it
# is now, following a rename, so moving a frozen file doesn't lift the rule.
# Git only pairs a rename once the new path is tracked or staged.
if ! renames="$(git diff --name-status -M --diff-filter=R "$merge_base" -- "${paths[@]}")"; then
  echo "File growth: comparing with $base failed, skipped."
  exit 0
fi
for path in "${frozen[@]}"; do
  # Not in the base: nothing to compare with.
  git cat-file -e "$merge_base:$path" 2>/dev/null || continue
  base_lines="$(git show "$merge_base:$path" | wc -l | tr -d '[:space:]')"
  current="$path"
  moved=""
  if [[ ! -f "$path" ]]; then
    current="$(awk -F'\t' -v old="$path" '$2 == old { print $3; exit }' <<< "$renames")"
    # Deleted, or split up beyond what Git recognizes as a rename.
    [[ -n "$current" ]] || continue
    moved=" (renamed from $path)"
  fi
  frozen_now+=("$current")
  lines="$(line_count "$current")" || continue
  ((lines > base_lines)) || continue
  error "$current" "$current$moved grew by $((lines - base_lines)) lines to $lines. AGENTS.md says this file must not grow: move the new code into its own type and file."
  frozen_grown=$((frozen_grown + 1))
done

if ! numstat="$(git diff --numstat --no-renames "$merge_base" -- "${paths[@]}")"; then
  echo "File growth: comparing with $base failed, skipped."
  exit 0
fi
while IFS=$'\t' read -r added deleted path; do
  # Binary files show "-" instead of line counts.
  [[ -n "$path" && "$added" != "-" ]] || continue
  ((added > deleted)) || continue
  is_frozen_now "$path" && continue
  lines="$(line_count "$path")" || continue
  ((lines > limit)) || continue
  warn "$path" "$path grew by $((added - deleted)) lines to $lines (over $limit). Move new code into its own type and file; see \"Large files\" in AGENTS.md."
  grown=$((grown + 1))
done <<< "$numstat"

if ((frozen_grown > 0)); then
  exit 1
fi
if ((grown == 0)); then
  echo "File growth: no Swift file over $limit lines got longer."
fi
exit 0
