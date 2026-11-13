#!/bin/bash
# SPDX-License-Identifier: MIT
#
# tools/genkey.sh [outdir]
#
# Creates the signing key of the package repository (RSA 4096, PEM - xbps
# accepts nothing else) and the public plist for the devices.
#
#   <outdir>/voidstation-packages.pem   PRIVATE key -> GitHub secret, then
#                                       keep one offline copy, delete the rest
#   keys/<fingerprint>.plist            public key, commit it
#
# Run it once, on a trusted machine. Not on a server, not in CI.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-$HOME/voidstation-packages-key}"
signer="VoidStation packages"

umask 077
mkdir -p "$out"
priv="$out/voidstation-packages.pem"
[ -e "$priv" ] && { echo "$priv exists - refusing to overwrite" >&2; exit 1; }

openssl genrsa -traditional -out "$priv" 4096 2>/dev/null \
	|| openssl genrsa -out "$priv" 4096
openssl rsa -in "$priv" -pubout -out "$out/public.pem" 2>/dev/null
fp="$(python3 ci/keyplist.py "$out/public.pem" "$signer" keys)"

cat <<EOF

Fingerprint: $fp
Public key:  keys/$fp.plist   (commit this file)
Private key: $priv

Next steps:
 1. GitHub -> Panther92/voidstation-packages -> Settings -> Environments
    -> release -> Add environment secret
       Name:  XBPS_PRIVKEY
       Value: the complete content of $priv (including BEGIN/END lines)
 2. Copy $priv to an offline place (USB stick), then delete it here:
       shred -u "$priv"
EOF
