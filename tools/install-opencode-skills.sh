#!/bin/sh
# Install the Hackmode OpenCode skill suite into consuming repositories.
#
# Usage: install-opencode-skills.sh <destination-repo> [more-repos...]
#
# Copies .opencode/skills/hackmode-* from this checkout (canonical home)
# into each destination repo's .opencode/skills/, replacing previous
# copies. Non-hackmode skills in the destination are left untouched.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/.opencode/skills"

if [ ! -d "$src" ]; then
    echo "error: $src not found (run from a Hackmode checkout)" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <destination-repo> [more-repos...]" >&2
    exit 1
fi

for dest in "$@"; do
    skills_dir="$dest/.opencode/skills"
    mkdir -p "$skills_dir"
    for skill in "$src"/hackmode-*; do
        if [ ! -d "$skill" ]; then
            echo "error: no hackmode-* skills found under $src" >&2
            exit 1
        fi
        name="$(basename "$skill")"
        rm -rf "$skills_dir/$name"
        cp -r "$skill" "$skills_dir/$name"
        echo "installed $name -> $skills_dir/$name"
    done
done
