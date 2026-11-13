#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Turn an RSA public key (PEM) into the plist xbps keeps per repository key.

    ci/keyplist.py public.pem "VoidStation packages" [outdir]

Writes <outdir>/<fingerprint>.plist (default: keys/) and prints the
fingerprint. Devices get this file as /var/db/xbps/keys/<fingerprint>.plist,
so xbps trusts the repository without asking on the first sync.

The fingerprint is what xbps shows: MD5 of the key in OpenSSH wire format
("ssh-rsa", e, n) - checked against the plist of the xlibre-void repo.
No third-party modules needed (the NiPoGi has a plain python3).
"""
import base64
import hashlib
import os
import struct
import sys


def der_read(buf, pos):
    tag = buf[pos]
    length = buf[pos + 1]
    pos += 2
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(buf[pos:pos + n], "big")
        pos += n
    return tag, buf[pos:pos + length], pos + length


def rsa_numbers(pem: bytes):
    body = b"".join(line for line in pem.splitlines() if not line.startswith(b"-----"))
    der = base64.b64decode(body)
    tag, spki, _ = der_read(der, 0)                 # SubjectPublicKeyInfo
    if tag != 0x30:
        raise ValueError("not a SubjectPublicKeyInfo")
    _, _, pos = der_read(spki, 0)                   # AlgorithmIdentifier
    tag, bits, _ = der_read(spki, pos)              # BIT STRING
    if tag != 0x03:
        raise ValueError("no BIT STRING")
    tag, seq, _ = der_read(bits[1:], 0)             # RSAPublicKey
    _, n, pos = der_read(seq, 0)
    _, e, _ = der_read(seq, pos)
    return int.from_bytes(n, "big"), int.from_bytes(e, "big")


def fingerprint(n: int, e: int) -> str:
    def mpint(x):
        b = x.to_bytes((x.bit_length() + 7) // 8, "big")
        if b[0] & 0x80:
            b = b"\0" + b
        return struct.pack(">I", len(b)) + b
    blob = struct.pack(">I", 7) + b"ssh-rsa" + mpint(e) + mpint(n)
    return ":".join("%02x" % c for c in hashlib.md5(blob).digest())


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    pem = open(sys.argv[1], "rb").read()
    if b"BEGIN PUBLIC KEY" not in pem:
        sys.exit("expected a PEM public key (BEGIN PUBLIC KEY)")
    signer = sys.argv[2]
    outdir = sys.argv[3] if len(sys.argv) > 3 else "keys"
    n, e = rsa_numbers(pem)
    fp = fingerprint(n, e)
    data = base64.b64encode(pem).decode()
    plist = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n<dict>\n'
        f"\t<key>public-key</key>\n\t<data>{data}</data>\n"
        f"\t<key>public-key-size</key>\n\t<integer>{n.bit_length()}</integer>\n"
        f"\t<key>signature-by</key>\n\t<string>{signer}</string>\n"
        "</dict>\n</plist>\n"
    )
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, fp + ".plist"), "w") as f:
        f.write(plist)
    print(fp)


if __name__ == "__main__":
    main()
