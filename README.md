# VoidStation packages

xbps package repository for [VoidStation](https://github.com/Panther92/VoidStation),
the Void Linux based media station for TVs. It holds what Void Linux itself does
not ship, or not in the shape VoidStation needs:

- **XLibre** – the X server VoidStation uses, with its drivers
  (templates taken over from [xlibre-void/xlibre](https://github.com/xlibre-void/xlibre), see `NOTICE.md`)
- **vs-chdman** – `chdman` from MAME on its own, without the whole emulator
- later: Mullvad, emulators and apps that upstream only offers as AppImage,
  Flatpak or `.deb`

Packages are built by GitHub Actions on top of a pinned commit of
[void-packages](https://github.com/void-linux/void-packages) and signed with
the repository key in `keys/`.

## Rules

1. **Never replace a Void package under its own name.** A variant gets its own
   name (`vs-…`). CI refuses templates whose name exists in void-packages
   (`ci/shadow-allow` is empty on purpose).
2. **Only what is missing.** Core libraries and anything security critical
   (Qt, PipeWire, ffmpeg, Mesa, OpenSSH, OpenSSL, glibc, the kernel) come from
   Void.
3. **Upstream first.** Small fixes to Void packages go to void-packages as a
   pull request.
4. **Licenses:** only software whose license allows redistribution. Proprietary
   software and software that forbids packaging (e.g. DuckStation) is not
   packaged here.

## Layout

| Path | What |
|---|---|
| `srcpkgs/` | templates (same format as void-packages) |
| `ci/void-packages.ref` | void-packages commit the templates are built against |
| `ci/plan.sh`, `ci/changed.sh` | which templates a push or pull request has to build |
| `ci/prepare.sh` | void-packages at the pinned commit + our templates, name clash check |
| `ci/build.sh` | bootstrap and build for one architecture (x86_64, i686) |
| `ci/publish.sh` | add to the index, sign, check, upload |
| `ci/keyplist.py` | public key → xbps key plist (fingerprint as xbps shows it) |
| `tools/genkey.sh` | create the signing key (run once, on a trusted machine) |
| `keys/` | public key(s) of this repository |

## Build and publish

- Push to a branch or open a pull request: the changed templates are built for
  x86_64 and i686 as a test. No key, no upload.
- Push to `main`: same build, then the job **Sign and publish** waits for
  approval in the environment `release`. Only that job can read the signing
  key. It fetches the current index, adds the new packages, signs, checks the
  signature with xbps and uploads (packages first, index last).
- Manual run (*Actions → Build packages → Run workflow*): `all` or a list of
  template names.

### Environment `release`

| Name | Type | Content |
|---|---|---|
| `XBPS_PRIVKEY` | secret | RSA private key (PEM) from `tools/genkey.sh` |
| `REPO_URL` | variable | public URL of the repository |
| `UPLOAD` | variable | `none`, `rsync` or `bunny` |
| `RSYNC_TARGET`, `UPLOAD_KNOWN_HOSTS` | variables | for `rsync`: `user@host:path`, `ssh-keyscan` line |
| `UPLOAD_SSH_KEY` | secret | for `rsync`: private SSH key for the upload |
| `BUNNY_STORAGE_HOST`, `BUNNY_STORAGE_ZONE`, `BUNNY_PATH` | variables | for `bunny` |
| `BUNNY_STORAGE_KEY`, `BUNNY_API_KEY` | secrets | for `bunny`: storage password, account key (cache purge) |

## Using the repository

Not yet: the repository is being set up. VoidStation devices will get the
repository and its key with a VoidStation update.

## License

The templates and scripts in this repository are MIT licensed (`LICENSE`).
The packaged software keeps its own license, stated in each template.
