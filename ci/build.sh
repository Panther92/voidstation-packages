#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/build.sh <workdir> <arch> <pkg>...
#
# Runs inside the Void container as the unprivileged user 'builder'.
# Bootstraps a masterdir for <arch> (x86_64 or i686, both run natively on an
# x86_64 kernel) and builds the given templates in dependency order.
# Templates that are not available for <arch> (archs=) are skipped.
# A failed template does not stop the others; the job fails at the end,
# so nothing half-built gets published.
#
# Result: <workdir>/hostdir/binpkgs/*.xbps
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"   # before cd: $0 may be relative
work="${1:?workdir}" arch="${2:?arch}"
shift 2
cd "$work"

md="masterdir-$arch"
src() { ./xbps-src -m "$md" -A "$arch" "$@"; }

if [ ! -x "$md/usr/bin/xbps-install" ]; then
	src binary-bootstrap
fi

mapfile -t order < <(src sort-dependencies "$@")
echo "build order ($arch): ${order[*]}"

available() {   # templates without archs= build everywhere
	grep -q '^archs=' "srcpkgs/$1/template" || return 0
	src show-avail "$1" >/dev/null 2>&1
}

mkdir -p logs
built=() skipped=() failed=()
for pkg in "${order[@]}"; do
	if ! available "$pkg"; then
		skipped+=("$pkg")
		echo "::notice title=$pkg::not available for $arch (archs=), skipped"
		continue
	fi
	echo "::group::$pkg ($arch)"
	rc=0
	src -j"$(nproc)" pkg "$pkg" > >(tee "logs/$pkg.log") 2>&1 || rc=$?
	echo "::endgroup::"
	# xbps-src: 1 = error; other non-zero codes mean "nothing to do"
	if [ "$rc" = 1 ]; then
		failed+=("$pkg")
		bash "$here/ci/annotate.sh" "$pkg ($arch) failed" "logs/$pkg.log"
		continue
	elif [ "$rc" != 0 ]; then
		echo "::warning title=$pkg::xbps-src exited with $rc for $arch"
	fi
	built+=("$pkg")
done

echo "built: ${built[*]:-none}"
echo "skipped: ${skipped[*]:-none}"
echo "failed: ${failed[*]:-none}"
ls -l hostdir/binpkgs/*.xbps 2>/dev/null || echo "no packages"
# keep going over all templates of the group, fail at the end: one run shows
# every broken template (and every checksum to fill in) at once
[ ${#failed[@]} = 0 ]
