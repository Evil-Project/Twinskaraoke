#!/usr/bin/env python3
"""PreToolUse guard for Claude Code (.claude/settings.json).

Turns a few AGENTS.md rules into checks. It reads the hook input on stdin and
prints a permission decision, or nothing when the call is fine:

  deny  edits to files that are generated or third-party
  ask   edits to files that need approval first
  ask   shell commands that write either kind of file
  deny  `git commit` on main
  ask   `git push` to main

The shell checks read the command text. They catch the usual forms (a
redirect, tee, sed -i, cp, mv, rm, ...), not every way a command can write a
file: a script that opens the path itself gets through. Other tools (Codex,
Cursor, ...) don't run this at all; they follow AGENTS.md.
A guard that fails must never block work, so every error exits 0.
"""
import json
import os
import re
import shlex
import subprocess
import sys

DENY_EDIT = [
    (r"(^|/)\.agents/skills/", "Files in .agents/skills/ are a third-party copy. Update them from "
     "their source (skills-lock.json) in a separate PR."),
    (r"(^|/)docs/api/.*\.md$", "The Markdown in docs/api/ is generated. Refresh it with "
     "Scripts/update-api-docs.py in its own PR."),
    (r"(^|/)\.swiftlint-baseline\.json$", "Never edit the SwiftLint baseline to hide new violations. "
     "Fix them, or add a scoped swiftlint:disable with a reason."),
]
ASK_EDIT = [
    (r"\.pbxproj$", "AGENTS.md: don't edit project.pbxproj unless the task is about the project, "
     "and ask for approval first."),
    (r"(^|/)\.github/workflows/", "AGENTS.md: CI changes need approval and their own PR."),
    (r"(^|/)\.github/CODEOWNERS$", "AGENTS.md: CODEOWNERS changes need approval and their own PR."),
    (r"(^|/)AGENTS\.md$", "AGENTS.md: rule changes need approval and their own PR."),
]
GIT = re.compile(r"(?:^|[;&|(]|\s)git((?:\s+-[cC]\s+\S+|\s+--[\w-]+(?:=\S+)?)*)\s+(commit|push)\b([^;&|]*)")
REDIRECT = re.compile(r"(?<![0-9&])>{1,2}\s*((?:\"[^\"]*\"|'[^']*'|[^\s;&|<>()])+)")
# Commands whose arguments are files they change. cp only changes its last one.
WRITERS = {"tee", "rm", "mv", "cp", "touch", "truncate", "install", "ln"}
CD = re.compile(r"(?:^|[;&|(]\s*)cd\s+((?:\"[^\"]*\"|'[^']*'|\S)+)")


def decide(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def words(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def branch(directory):
    try:
        out = subprocess.run(["git", "-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def check_edit(tool_input):
    path = (tool_input.get("file_path") or tool_input.get("notebook_path") or "").replace(os.sep, "/")
    for pattern, reason in DENY_EDIT:
        if re.search(pattern, path):
            decide("deny", reason)
    for pattern, reason in ASK_EDIT:
        if re.search(pattern, path):
            decide("ask", reason)


def written_paths(command):
    """Paths the command text shows it writing; see the module docstring."""
    paths = [words(target)[0] for target in REDIRECT.findall(command) if words(target)]
    for simple in re.split(r"[;&|\n]+", command):
        tokens = words(simple)
        while tokens and re.match(r"^\w+=", tokens[0]):  # VAR=value prefixes
            tokens.pop(0)
        if not tokens:
            continue
        name, args = os.path.basename(tokens[0]), tokens[1:]
        files = [a for a in args if not a.startswith("-")]
        in_place = any(re.match(r"^-[a-zA-Z]*i", a) or a.startswith("--in-place") for a in args)
        if name in WRITERS:
            paths += files[-1:] if name == "cp" else files
        elif name in ("sed", "perl") and in_place:
            paths += files
        elif name == "swiftlint" and "--write-baseline" in args:
            paths.append(".swiftlint-baseline.json")
    return paths


def check_bash(tool_input, cwd):
    command = tool_input.get("command") or ""
    for path in written_paths(command):
        path = path.replace(os.sep, "/")
        for pattern, reason in DENY_EDIT + ASK_EDIT:
            if re.search(pattern, path):
                decide("ask", "This command looks like it writes " + path + ". " + reason)
    for match in GIT.finditer(command):
        options, verb, rest = match.group(1), match.group(2), match.group(3)
        # Where the command runs: every `cd` before it in turn, then `git -C`.
        directory = cwd
        for target in CD.findall(command[:match.start()]):
            if words(target):
                directory = os.path.join(directory, os.path.expanduser(words(target)[0]))
        opts = words(options)
        for index, opt in enumerate(opts[:-1]):
            if opt == "-C":
                directory = os.path.join(directory, os.path.expanduser(opts[index + 1]))
        current = branch(directory)
        if verb == "commit" and current == "main":
            decide("deny", "AGENTS.md: never commit to main. Create a branch first: "
                   "feat/<slug>, fix/<slug>, refactor/<slug> or chore/<slug>.")
        if verb == "push":
            rest_words = words(rest)
            args = [w for w in rest_words if not w.startswith("-")]
            refspecs = args[1:]  # args[0] is the remote
            to_main = any(r == "main" or r.endswith(":main") or r.endswith(":refs/heads/main")
                          for r in refspecs)
            # These push every branch, main included, whatever is checked out.
            every_branch = any(w in ("--all", "--mirror", "--branches") for w in rest_words)
            if to_main or every_branch or (not refspecs and current == "main"):
                decide("ask", "AGENTS.md: never push to main. Every push to main publishes the "
                       "public nightly IPA. Allow this only to sync a fork's main.")


def main():
    data = json.load(sys.stdin)
    tool, tool_input = data.get("tool_name"), data.get("tool_input") or {}
    if tool == "Bash":
        check_bash(tool_input, data.get("cwd") or os.getcwd())
    elif tool in ("Edit", "Write", "NotebookEdit"):
        check_edit(tool_input)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # A broken guard must not block work.
        pass
    sys.exit(0)
