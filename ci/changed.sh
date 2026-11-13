#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/changed.sh all
# ci/changed.sh list <pkg>...
# ci/changed.sh diff <base> <head>
#
# Prints the templates to build, one per line (main package names; a
# subpackage symlink such as xlibre-xserver-devel maps to xlibre-xserver).
# Order does not matter, the build sorts by dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

main_name() {   # srcpkgs/<name> -> name of the template that builds it
	local n="$1"
	if [ -L "srcpkgs/$n" ]; then
		basename "$(readlink "srcpkgs/$n")"
	else
		echo "$n"
	fi
}

case "${1:-}" in
	all)
		for d in srcpkgs/*; do
			[ -L "$d" ] && continue
			[ -f "$d/template" ] && basename "$d"
		done
		;;
	list)
		shift
		for n in "$@"; do
			[ -e "srcpkgs/$n" ] || { echo "unknown package: $n" >&2; exit 1; }
			main_name "$n"
		done | sort -u
		;;
	diff)
		base="${2:?base}" head="${3:?head}"
		git diff --no-renames --name-only "$base" "$head" -- 'srcpkgs/*' |
			cut -d/ -f2 | sort -u |
			while read -r n; do
				[ -e "srcpkgs/$n" ] || continue     # removed package
				main_name "$n"
			done | sort -u
		;;
	*)
		echo "usage: ci/changed.sh all | list <pkg>... | diff <base> <head>" >&2
		exit 2
		;;
esac
