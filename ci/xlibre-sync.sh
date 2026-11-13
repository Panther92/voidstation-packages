#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/xlibre-sync.sh
#
# Keeps srcpkgs/xlibre* in step with xlibre-void/xlibre (the templates were
# taken over from there, see NOTICE.md). Devices get XLibre only from this
# repository, so new upstream versions and fixes must not get lost.
#
# Compares the upstream main branch with the commit in ci/xlibre-void.ref.
# If it moved: copies every changed or new xlibre* template (xlibre-repo and
# old-patches/ stay out, as when they were taken over), removes templates
# upstream dropped, updates the ref and NOTICE.md, and prints the names of the
# changed templates on one line (stdout). Nothing changed upstream: no output.
set -euo pipefail
cd "$(dirname "$0")/.."

REF_FILE=ci/xlibre-void.ref
UPSTREAM=https://github.com/xlibre-void/xlibre
old="$(head -n1 "$REF_FILE")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone -q --depth 1 "$UPSTREAM" "$tmp/x"
new="$(git -C "$tmp/x" rev-parse HEAD)"
if [ "$new" = "$old" ]; then
	echo "xlibre-void: unchanged ($old)" >&2
	exit 0
fi

changed=()
for d in "$tmp"/x/srcpkgs/xlibre*; do
	n="${d##*/}"
	[ "$n" = xlibre-repo ] && continue
	if [ -L "$d" ]; then                       # subpackage: link to the main template
		target="$(readlink "$d")"
		if [ -L "srcpkgs/$n" ] && [ "$(readlink "srcpkgs/$n")" = "$target" ]; then
			continue
		fi
		rm -rf "srcpkgs/$n"
		ln -s "$target" "srcpkgs/$n"
		changed+=("$n")
		continue
	fi
	if [ -d "srcpkgs/$n" ] && [ ! -L "srcpkgs/$n" ] &&
		diff -rq --exclude=old-patches "$d" "srcpkgs/$n" >/dev/null 2>&1; then
		continue
	fi
	rm -rf "srcpkgs/$n"
	cp -a "$d" "srcpkgs/$n"
	rm -rf "srcpkgs/$n/old-patches"
	changed+=("$n")
done

for d in srcpkgs/xlibre*; do
	n="${d##*/}"
	if [ ! -e "$tmp/x/srcpkgs/$n" ] && [ ! -L "$tmp/x/srcpkgs/$n" ]; then
		echo "::warning title=xlibre-void::$n is gone upstream, removed here too" >&2
		rm -rf "$d"
	fi
done

echo "$new" > "$REF_FILE"
sed -i "s/(commit [0-9a-f]\{40\})/(commit $new)/" NOTICE.md
echo "xlibre-void: $old -> $new, changed: ${changed[*]:-none}" >&2
echo "${changed[*]:-}"
