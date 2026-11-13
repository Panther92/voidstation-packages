#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/publish.sh <artifacts> <out>
#
# Runs in the 'publish' job (environment "release", needs Paul's approval).
#
#   <artifacts>/pkgs-<arch>-<group>/*.xbps   unsigned packages from the build jobs
#   <out>/                           signed result, uploaded afterwards
#
# Steps per architecture:
#   1. fetch the current <arch>-repodata from $REPO_URL (if it exists), so
#      packages that were not rebuilt stay in the index
#   2. add the new packages (noarch packages are taken once, from x86_64,
#      so both indexes point at the very same file)
#   3. sign the index and every new package with $XBPS_PRIVKEY
#   4. check that xbps accepts the signed repository
#   5. upload: packages first, repodata last - a client never sees an index
#      entry whose file is not there yet
#
# Environment:
#   XBPS_PRIVKEY     PEM private key (secret)                      required
#   REPO_URL         public base URL, e.g. https://repo.voidstation.de
#   UPLOAD           none | rsync | bunny                          default none
#   rsync:  RSYNC_TARGET (user@host:path), UPLOAD_SSH_KEY (secret),
#           UPLOAD_KNOWN_HOSTS (ssh-keyscan line of the host)
#   bunny:  BUNNY_STORAGE_HOST (e.g. storage.bunnycdn.com), BUNNY_STORAGE_ZONE,
#           BUNNY_STORAGE_KEY (secret), BUNNY_PATH (optional sub folder),
#           BUNNY_API_KEY (secret, optional: purge the cached repodata)
set -euo pipefail

art="${1:?artifacts dir}" out="${2:?output dir}"
here="$(cd "$(dirname "$0")/.." && pwd)"
signer="VoidStation packages"
archs="x86_64 i686"

[ -n "${XBPS_PRIVKEY:-}" ] || {
	echo "::error title=No signing key::XBPS_PRIVKEY is not set in the environment 'release'"
	exit 1
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
key="$tmp/key.pem"
( umask 077; printf '%s\n' "$XBPS_PRIVKEY" > "$key" )

mkdir -p "$out"
shopt -s nullglob

# --- 1 + 2: collect ------------------------------------------------------
# One artifact per build job (pkgs-<arch>-<group>). download-artifact puts
# each into its own folder, except when a run has just one: then the files
# land directly in $art (vs-chdman_2, 2026-11-14: "nothing to publish").
# So take every .xbps below $art; x86_64 artifacts first, they win for
# noarch packages.
while IFS= read -r f; do
	[ -e "$out/${f##*/}" ] || cp "$f" "$out/"
done < <(find "$art" -type f -name '*.xbps' | awk '/pkgs-x86_64-/ { print; next } { rest[NR] = $0 } END { for (i in rest) print rest[i] }')
new=("$out"/*.xbps)
if [ ${#new[@]} = 0 ]; then
	echo "::warning title=Nothing published::no packages found in the build artifacts"
	exit 0
fi
printf 'new: %s\n' "${new[@]##*/}"

for arch in $archs; do
	if [ -n "${REPO_URL:-}" ]; then
		if curl -fsSL -o "$out/$arch-repodata" "${REPO_URL%/}/$arch-repodata"; then
			echo "$arch: current index fetched"
		else
			rm -f "$out/$arch-repodata"
			echo "$arch: no index online yet, starting a new one"
		fi
	fi
	files=("$out"/*."$arch".xbps "$out"/*.noarch.xbps)
	[ ${#files[@]} = 0 ] && continue
	# -f: a package rebuilt with an unchanged version (e.g. as dependency of
	# another template) gets new bytes; without -f the index would keep the
	# old checksum while the upload replaces the file -> checksum mismatch
	XBPS_TARGET_ARCH="$arch" xbps-rindex -a -f "${files[@]}"
done

# --- 3: sign -------------------------------------------------------------
for arch in $archs; do
	[ -f "$out/$arch-repodata" ] || continue
	XBPS_TARGET_ARCH="$arch" xbps-rindex --privkey "$key" --sign --signedby "$signer" "$out"
done
xbps-rindex --privkey "$key" --sign-pkg "${new[@]}"

# --- 4: check ------------------------------------------------------------
# The key that signed must be the one committed in keys/ (what devices get).
openssl rsa -in "$key" -pubout -out "$tmp/public.pem" 2>/dev/null
fp="$(python3 "$here/ci/keyplist.py" "$tmp/public.pem" "$signer" "$tmp/keys")"
if ! [ -f "$here/keys/$fp.plist" ]; then
	echo "::error title=Unknown key::signed with $fp, but keys/$fp.plist is not in the repository - devices would not trust it"
	exit 1
fi
# xbps only checks signatures of remote repositories, so serve the result
# over HTTP on localhost and sync it like a device would: with exactly our
# key preinstalled. A different key would show up as a second key file.
port=$(( 20000 + RANDOM % 20000 ))
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$out" >/dev/null 2>&1 &
srv=$!
trap 'kill "$srv" 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
	curl -fsS -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null && break
	sleep 0.5
done
url="http://127.0.0.1:$port"
for arch in $archs; do
	[ -f "$out/$arch-repodata" ] || continue
	root="$tmp/root-$arch"
	mkdir -p "$root/var/db/xbps/keys"
	cp "$here/keys/$fp.plist" "$root/var/db/xbps/keys/"
	XBPS_TARGET_ARCH="$arch" xbps-install -r "$root" -R "$url" -S </dev/null
	keys="$(ls "$root/var/db/xbps/keys")"
	if [ "$keys" != "$fp.plist" ]; then
		echo "::error::$arch: unexpected keys after sync: $keys"
		exit 1
	fi
	XBPS_TARGET_ARCH="$arch" xbps-query -r "$root" --repository="$url" -Lv | tee "$tmp/L"
	grep -q '(RSA signed)' "$tmp/L" || { echo "::error::$arch index is not signed"; exit 1; }
done
for f in "${new[@]}"; do
	[ -s "$f.sig2" ] || { echo "::error::missing signature $f.sig2"; exit 1; }
done
echo "signed with $fp"

# --- 5: upload -----------------------------------------------------------
pkgfiles=("${new[@]}")
for f in "${new[@]}"; do pkgfiles+=("$f.sig2"); done
idxfiles=("$out"/*-repodata)
if compgen -G "$out/*-stagedata" >/dev/null; then
	echo "::warning title=Staged packages::xbps-rindex staged packages (shlib changes not yet resolved); they are not in the published index: $(ls "$out"/*-stagedata)"
fi

case "${UPLOAD:-none}" in
	none)
		echo "UPLOAD=none: signed repository is only kept as workflow artifact"
		;;
	rsync)
		: "${RSYNC_TARGET:?}" "${UPLOAD_SSH_KEY:?}" "${UPLOAD_KNOWN_HOSTS:?}"
		( umask 077; printf '%s\n' "$UPLOAD_SSH_KEY" > "$tmp/ssh"
		  printf '%s\n' "$UPLOAD_KNOWN_HOSTS" > "$tmp/known_hosts" )
		ssh_cmd="ssh -i $tmp/ssh -o UserKnownHostsFile=$tmp/known_hosts -o StrictHostKeyChecking=yes"
		rsync -av -e "$ssh_cmd" "${pkgfiles[@]}" "${RSYNC_TARGET%/}/"
		rsync -av -e "$ssh_cmd" "${idxfiles[@]}" "${RSYNC_TARGET%/}/"
		;;
	bunny)
		: "${BUNNY_STORAGE_HOST:?}" "${BUNNY_STORAGE_ZONE:?}" "${BUNNY_STORAGE_KEY:?}"
		base="https://$BUNNY_STORAGE_HOST/$BUNNY_STORAGE_ZONE"
		[ -n "${BUNNY_PATH:-}" ] && base="$base/${BUNNY_PATH%/}"
		put() {
			curl -fsS --retry 3 -X PUT -H "AccessKey: $BUNNY_STORAGE_KEY" \
				-H "Content-Type: application/octet-stream" \
				--data-binary "@$1" "$base/$(basename "$1")" >/dev/null
			echo "uploaded $(basename "$1")"
		}
		for f in "${pkgfiles[@]}"; do put "$f"; done
		for f in "${idxfiles[@]}"; do put "$f"; done
		if [ -n "${BUNNY_API_KEY:-}" ] && [ -n "${REPO_URL:-}" ]; then
			for f in "${idxfiles[@]}"; do
				curl -fsS -X POST -H "AccessKey: $BUNNY_API_KEY" \
					"https://api.bunny.net/purge?url=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "${REPO_URL%/}/$(basename "$f")")" >/dev/null
				echo "purged $(basename "$f") from the CDN cache"
			done
		fi
		;;
	*)
		echo "::error::unknown UPLOAD=$UPLOAD"; exit 1 ;;
esac
