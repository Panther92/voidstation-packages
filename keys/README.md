# Repository keys

Public key(s) of this repository as xbps key plists,
named `<fingerprint>.plist` (the fingerprint `xbps-install` shows).

Created with `tools/genkey.sh`. VoidStation devices get the file as
`/var/db/xbps/keys/<fingerprint>.plist`, so xbps trusts the repository
without asking on the first sync.

The private key is only stored as the secret `XBPS_PRIVKEY` in the GitHub
environment `release` and in one offline copy.
