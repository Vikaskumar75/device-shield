#!/usr/bin/env python3
"""PreToolUse guard: Claude must get approval before running git or gh
commands that change the repository or talk to GitHub.

Reads the hook payload on stdin. For a Bash command containing a write
operation it prints a permissionDecision of "ask", so the user is prompted
even in auto mode. Read-only commands produce no output and continue through
the normal permission flow. Anything unrecognised is treated as a write.

Best effort: it parses the command text, so git invoked indirectly (from a
script, an alias or another language) is not caught.
"""

import json
import os
import re
import shlex
import sys

# git subcommands that never change the repository or contact a remote.
GIT_READ_ONLY = {
    "status", "diff", "log", "show", "blame", "grep", "ls-files", "ls-tree",
    "rev-parse", "rev-list", "describe", "shortlog", "cat-file", "merge-base",
    "name-rev", "whatchanged", "check-ignore", "var", "help", "version",
    "count-objects", "for-each-ref", "show-ref", "diff-tree", "diff-files",
    "diff-index", "cherry",
}

# git global options that take a separate value argument.
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}

# Flags that turn `git branch` into a write.
BRANCH_WRITE_FLAGS = {
    "-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy",
    "-u", "--set-upstream-to", "--unset-upstream", "-f", "--force",
    "--edit-description", "-t", "--track", "--no-track",
}
# Flags that take a value in `git branch` listing mode.
BRANCH_LIST_OPTS_WITH_VALUE = {
    "--contains", "--no-contains", "--merged", "--no-merged", "--points-at",
    "--format", "--sort", "--color", "--column",
}

GIT_CONFIG_READ_FLAGS = {
    "--get", "--get-all", "--get-regexp", "--list", "-l", "--get-urlmatch",
    "--show-origin", "--show-scope", "--name-only", "--null", "-z",
    "--global", "--local", "--system", "--worktree", "--file", "-f",
    "--includes", "--no-includes", "--type", "--default",
}

# gh "<group> <action>" pairs that only read.
GH_READ_ONLY = {
    ("issue", "view"), ("issue", "list"), ("issue", "status"),
    ("pr", "view"), ("pr", "list"), ("pr", "status"), ("pr", "checks"),
    ("pr", "diff"),
    ("repo", "view"), ("repo", "list"),
    ("run", "view"), ("run", "list"), ("run", "watch"),
    ("workflow", "view"), ("workflow", "list"),
    ("release", "view"), ("release", "list"),
    ("auth", "status"), ("search", "*"), ("browse", "*"), ("status", "*"),
    ("help", "*"), ("version", "*"),
}

SEGMENT_SPLIT = re.compile(r"&&|\|\||[;|&\n]|\$\(|`|\(|\)")
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def tokens_of(segment):
    try:
        return shlex.split(segment, comments=True)
    except ValueError:
        return segment.split()


def git_write_reason(args):
    """args: tokens after `git`. Returns a reason string if this is a write."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        opt = args[i].split("=", 1)[0]
        i += 2 if (opt in GIT_OPTS_WITH_VALUE and "=" not in args[i]) else 1
    if i >= len(args):
        return None  # bare `git` or `git --version`
    sub, rest = args[i], args[i + 1:]

    if sub in GIT_READ_ONLY:
        return None
    if sub == "branch":
        j = 0
        while j < len(rest):
            tok = rest[j]
            if tok.split("=", 1)[0] in BRANCH_WRITE_FLAGS:
                return "git branch (create/delete/rename/upstream)"
            if tok.split("=", 1)[0] in BRANCH_LIST_OPTS_WITH_VALUE and "=" not in tok:
                j += 2
                continue
            if not tok.startswith("-"):
                # A positional without --list creates a branch.
                if "--list" in rest or "-l" in rest:
                    j += 1
                    continue
                return "git branch (create)"
            j += 1
        return None
    if sub == "remote":
        if not rest or rest[0] in {"-v", "--verbose", "get-url"}:
            return None
        return f"git remote {rest[0]}"
    if sub == "config":
        if any(t in {"--get", "--get-all", "--get-regexp", "--list", "-l",
                     "--get-urlmatch"} for t in rest):
            return None
        positional = [t for t in rest if not t.startswith("-")]
        if all(t in GIT_CONFIG_READ_FLAGS or not t.startswith("-") for t in rest) \
                and len(positional) <= 1 and "--unset" not in rest:
            return None  # `git config key` reads a value
        return "git config (write)"
    if sub == "stash" and rest and rest[0] in {"list", "show"}:
        return None
    if sub == "tag" and (not rest or "-l" in rest or "--list" in rest):
        return None  # listing, optionally filtered by a pattern
    if sub == "worktree" and rest and rest[0] == "list":
        return None
    if sub == "submodule" and (not rest or rest[0] in {"status", "summary"}):
        return None
    if sub == "reflog" and (not rest or rest[0] == "show"):
        return None
    if sub == "notes" and rest and rest[0] in {"list", "show"}:
        return None
    return f"git {sub}"


def gh_write_reason(args):
    """args: tokens after `gh`."""
    words = [t for t in args if not t.startswith("-")]
    if not words:
        return None  # `gh`, `gh --version`
    group = words[0]
    action = words[1] if len(words) > 1 else ""
    if group == "api":
        method = "GET"
        for k, tok in enumerate(args):
            if tok in {"-X", "--method"} and k + 1 < len(args):
                method = args[k + 1].upper()
            elif tok.startswith("--method="):
                method = tok.split("=", 1)[1].upper()
            elif tok in {"-f", "-F", "--field", "--raw-field", "--input"} or \
                    tok.startswith(("--field=", "--raw-field=", "--input=")):
                if method == "GET":
                    method = "POST"  # gh defaults to POST when fields are given
        return None if method == "GET" else f"gh api {method}"
    if (group, action) in GH_READ_ONLY or (group, "*") in GH_READ_ONLY:
        return None
    return f"gh {group} {action}".strip()


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""

    reasons = []
    for segment in SEGMENT_SPLIT.split(command):
        toks = tokens_of(segment)
        while toks and (ENV_ASSIGN.match(toks[0]) or toks[0] in {"sudo", "command", "exec", "time", "nohup", "env"}):
            toks = toks[1:]
        if not toks:
            continue
        prog = os.path.basename(toks[0])
        reason = None
        if prog == "git":
            reason = git_write_reason(toks[1:])
        elif prog == "gh":
            reason = gh_write_reason(toks[1:])
        if reason:
            reasons.append(reason)

    if reasons:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    "Git guard: this runs " + ", ".join(dict.fromkeys(reasons)) +
                    ". Git and GitHub write actions need your explicit approval "
                    "(.claude/hooks/git_guard.py)."
                ),
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
