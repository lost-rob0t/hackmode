#!/usr/bin/env python3
"""Lexical boundary check mirroring .github/workflows/agent-framework-boundary.yml."""
import pathlib
import re
import subprocess
import sys

config = pathlib.Path("agent-zero/forbidden-outside-agent-zero.txt")
tokens = [
    line.strip()
    for line in config.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
if not tokens:
    sys.exit("forbidden-token configuration is empty")

patterns = [
    (token, re.compile(rf"(?i)(?<![A-Za-z0-9_]){re.escape(token)}(?![A-Za-z0-9_])"))
    for token in tokens
]

tracked = subprocess.check_output(["git", "ls-files", "-z"])
paths = [p for p in tracked.decode("utf-8").split("\0") if p]
violations = []

for rel in paths:
    if rel == "agent-zero" or rel.startswith("agent-zero/"):
        continue
    for token, pattern in patterns:
        if pattern.search(rel):
            violations.append((rel, None, token, "path"))
    path = pathlib.Path(rel)
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for line_number, line in enumerate(text.splitlines(), 1):
        for token, pattern in patterns:
            if pattern.search(line):
                violations.append((rel, line_number, token, "content"))

for rel, line_number, token, kind in violations:
    print(f"VIOLATION: {rel}:{line_number} {token} ({kind})")
if violations:
    sys.exit(1)
print("BOUNDARY-CLEAN: Agent Zero lexical boundary satisfied")
