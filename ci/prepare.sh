#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/prepare.sh <workdir>
#
# Fetches void-packages at the pinned commit (ci/void-packages.ref) into
# <workdir> and lays our srcpkgs/ (and common/shlibs additions) over it.
#
# Refuses to continue if one of our package names already exists in
# void-packages: we never replace a Void package under the same name
# (variants get their own name, e.g. vs-chdman). Exceptions would have to be
# listed in ci/shadow-allow, which is empty on purpose.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
work="${1:?usage: ci/prepare.sh <workdir>}"
ref="$(grep -Ev '^\s*(#|$)' "$here/ci/void-packages.ref" | head -n1)"

[ -n "$ref" ] || { echo "ci/void-packages.ref: no commit" >&2; exit 1; }

if [ ! -d "$work/.git" ]; then
	rm -rf "$work"
	git init -q "$work"
	git -C "$work" remote add origin https://github.com/void-linux/void-packages.git
fi
git -C "$work" fetch -q --depth 1 origin "$ref"
git -C "$work" checkout -q --force FETCH_HEAD
git -C "$work" clean -qfdx -e hostdir -e 'masterdir*' -e etc/conf

# --- name collisions -----------------------------------------------------
allow=()
if [ -f "$here/ci/shadow-allow" ]; then
	mapfile -t allow < <(grep -Ev '^\s*(#|$)' "$here/ci/shadow-allow")
fi
clash=0
for dir in "$here"/srcpkgs/*; do
	name="$(basename "$dir")"
	if [ -e "$work/srcpkgs/$name" ]; then
		if printf '%s\n' "${allow[@]:-}" | grep -qx "$name"; then
			echo "note: $name shadows a Void package (allowed in ci/shadow-allow)"
		else
			echo "::error title=Name clash::srcpkgs/$name already exists in void-packages ($ref). Use a vs- name instead." >&2
			clash=1
		fi
	fi
done
[ "$clash" = 0 ] || exit 1

# --- overlay -------------------------------------------------------------
cp -a "$here"/srcpkgs/. "$work"/srcpkgs/
if [ -s "$here/common/shlibs" ]; then
	cat "$here/common/shlibs" >> "$work/common/shlibs"
fi

# --- build configuration -------------------------------------------------
{
	echo XBPS_BUILD_ENVIRONMENT=void-packages-ci
	echo XBPS_CHROOT_CMD=uchroot
	echo XBPS_ALLOW_RESTRICTED=no
	echo XBPS_CCACHE=no
} > "$work/etc/conf"

echo "void-packages $ref + $(find "$here/srcpkgs" -mindepth 1 -maxdepth 1 | wc -l) templates from this repository"
