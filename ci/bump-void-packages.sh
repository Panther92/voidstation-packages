#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/bump-void-packages.sh [commit]
#
# Moves the void-packages pin to the given commit (default: current master).
# The next push rebuilds everything against it.
set -euo pipefail
cd "$(dirname "$0")/.."
new="${1:-$(git ls-remote https://github.com/void-linux/void-packages refs/heads/master | cut -f1)}"
[[ "$new" =~ ^[0-9a-f]{40}$ ]] || { echo "not a commit: $new" >&2; exit 1; }
old="$(grep -Ev '^\s*(#|$)' ci/void-packages.ref | head -n1)"
sed -i "s/^$old\$/$new/" ci/void-packages.ref
echo "void-packages: $old -> $new"
